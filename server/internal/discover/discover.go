// Package discover works out server settings from an email address.
//
// Order: the operator's own profiles (the "server config"), the domain's autoconfig
// file, Thunderbird's public ISPDB, then DNS SRV records (RFC 6186 / RFC 8314 for mail,
// RFC 6764 for CalDAV/CardDAV).
package discover

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
)

var ErrNotFound = errors.New("no server settings found")

type Result struct {
	Settings model.Settings
	// LocalPartLogin is true when the provider wants "user" rather than "user@domain".
	LocalPartLogin bool
}

type Resolver interface {
	LookupSRV(ctx context.Context, service, proto, name string) (string, []*net.SRV, error)
}

type Discoverer struct {
	Profiles map[string]model.Settings // lower-case domain -> settings
	HTTP     *http.Client              // must be the netguard client
	DNS      Resolver
	ISPDB    string // base URL, default https://autoconfig.thunderbird.net/v1.1/
}

// LoadProfiles reads the operator's JSON file: {"example.com": ServerSettings, ...}.
func LoadProfiles(path string) (map[string]model.Settings, error) {
	if path == "" {
		return map[string]model.Settings{}, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw := map[string]model.Settings{}
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil, fmt.Errorf("profiles: %w", err)
	}
	out := make(map[string]model.Settings, len(raw))
	for d, s := range raw {
		if err := s.Validate(); err != nil {
			return nil, fmt.Errorf("profiles: %s: %w", d, err)
		}
		out[strings.ToLower(d)] = s
	}
	return out, nil
}

// Profile returns the operator profile for an address's domain, if any.
func (d *Discoverer) Profile(email string) (model.Settings, bool) {
	s, ok := d.Profiles[domainOf(email)]
	return s, ok
}

func domainOf(email string) string {
	_, dom, _ := strings.Cut(strings.ToLower(strings.TrimSpace(email)), "@")
	return dom
}

func (d *Discoverer) Discover(ctx context.Context, email string) (Result, error) {
	dom := domainOf(email)
	if dom == "" || strings.ContainsAny(dom, "/?#@ ") {
		return Result{}, ErrNotFound
	}
	if s, ok := d.Profiles[dom]; ok {
		return Result{Settings: s}, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	ispdb := d.ISPDB
	if ispdb == "" {
		ispdb = "https://autoconfig.thunderbird.net/v1.1/"
	}
	for _, u := range []string{
		"https://autoconfig." + dom + "/mail/config-v1.1.xml?emailaddress=" + url.QueryEscape(email),
		"https://" + dom + "/.well-known/autoconfig/mail/config-v1.1.xml",
		ispdb + dom,
	} {
		if r, err := d.autoconfig(ctx, u); err == nil {
			d.addDAV(ctx, dom, &r.Settings)
			return r, nil
		}
	}
	r, err := d.srv(ctx, dom)
	if err != nil {
		return Result{}, err
	}
	d.addDAV(ctx, dom, &r.Settings)
	return r, nil
}

type clientConfig struct {
	Provider struct {
		Incoming []server `xml:"incomingServer"`
		Outgoing []server `xml:"outgoingServer"`
	} `xml:"emailProvider"`
}

type server struct {
	Type       string `xml:"type,attr"`
	Hostname   string `xml:"hostname"`
	Port       int    `xml:"port"`
	SocketType string `xml:"socketType"`
	Username   string `xml:"username"`
}

func (s server) endpoint() (model.Endpoint, bool) {
	sec := map[string]string{"SSL": "tls", "STARTTLS": "starttls"}[strings.ToUpper(s.SocketType)]
	if sec == "" || s.Hostname == "" || strings.Contains(s.Hostname, "%") {
		return model.Endpoint{}, false // plaintext or templated hosts are not offered
	}
	return model.Endpoint{Host: s.Hostname, Port: s.Port, Security: sec}, true
}

func (d *Discoverer) autoconfig(ctx context.Context, u string) (Result, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	resp, err := d.HTTP.Do(req)
	if err != nil {
		return Result{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Result{}, fmt.Errorf("autoconfig: %s", resp.Status)
	}
	var cc clientConfig
	if err := xml.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&cc); err != nil {
		return Result{}, err
	}
	return pick(cc)
}

// pick prefers IMAP over POP3 and implicit TLS over STARTTLS, in the provider's order.
func pick(cc clientConfig) (Result, error) {
	var r Result
	best := -1
	for _, s := range cc.Provider.Incoming {
		e, ok := s.endpoint()
		if !ok || (s.Type != "imap" && s.Type != "pop3") {
			continue
		}
		score := map[string]int{"imap": 2, "pop3": 0}[s.Type] + map[string]int{"tls": 1}[e.Security]
		if score > best {
			best, e.Protocol = score, s.Type
			r.Settings.Incoming = e
			r.LocalPartLogin = s.Username == "%EMAILLOCALPART%"
		}
	}
	bestOut := -1
	for _, s := range cc.Provider.Outgoing {
		if e, ok := s.endpoint(); ok && s.Type == "smtp" {
			if score := map[string]int{"tls": 1}[e.Security]; score > bestOut {
				bestOut, r.Settings.Outgoing = score, e
			}
		}
	}
	if best < 0 || bestOut < 0 {
		return Result{}, ErrNotFound
	}
	return r, r.Settings.Validate()
}

func (d *Discoverer) lookup(ctx context.Context, service, dom string) (string, int, bool) {
	_, addrs, err := d.DNS.LookupSRV(ctx, service, "tcp", dom)
	if err != nil || len(addrs) == 0 {
		return "", 0, false
	}
	a := addrs[0] // already sorted by priority and weight
	host := strings.TrimSuffix(a.Target, ".")
	if host == "" { // "." target means the service is explicitly not offered
		return "", 0, false
	}
	return host, int(a.Port), true
}

func (d *Discoverer) srv(ctx context.Context, dom string) (Result, error) {
	var r Result
	in := []struct{ svc, proto, sec string }{{"imaps", "imap", "tls"}, {"imap", "imap", "starttls"}, {"pop3s", "pop3", "tls"}, {"pop3", "pop3", "starttls"}}
	for _, c := range in {
		if h, p, ok := d.lookup(ctx, c.svc, dom); ok {
			r.Settings.Incoming = model.Endpoint{Protocol: c.proto, Host: h, Port: p, Security: c.sec}
			break
		}
	}
	for _, c := range []struct{ svc, sec string }{{"submissions", "tls"}, {"submission", "starttls"}} {
		if h, p, ok := d.lookup(ctx, c.svc, dom); ok {
			r.Settings.Outgoing = model.Endpoint{Host: h, Port: p, Security: c.sec}
			break
		}
	}
	if r.Settings.Incoming.Host == "" || r.Settings.Outgoing.Host == "" {
		return Result{}, ErrNotFound
	}
	return r, r.Settings.Validate()
}

// addDAV fills CalDAV/CardDAV from RFC 6764 SRV records when present. The path is left
// to /.well-known discovery, which the DAV client performs.
func (d *Discoverer) addDAV(ctx context.Context, dom string, s *model.Settings) {
	if s.CalDAVURL == "" {
		if h, p, ok := d.lookup(ctx, "caldavs", dom); ok {
			s.CalDAVURL = "https://" + net.JoinHostPort(h, strconv.Itoa(p)) + "/"
		}
	}
	if s.CardDAVURL == "" {
		if h, p, ok := d.lookup(ctx, "carddavs", dom); ok {
			s.CardDAVURL = "https://" + net.JoinHostPort(h, strconv.Itoa(p)) + "/"
		}
	}
}
