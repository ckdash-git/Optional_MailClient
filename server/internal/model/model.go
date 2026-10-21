// Package model holds the types shared by the store, the protocol adapters and the API.
// JSON tags are the wire format documented in docs/API.md.
package model

import (
	"fmt"
	"net"
	"net/url"
	"regexp"
	"strings"
)

type Endpoint struct {
	Protocol string `json:"protocol,omitempty"` // incoming only: imap | pop3
	Host     string `json:"host"`
	Port     int    `json:"port"`
	Security string `json:"security"` // tls | starttls | none
}

type Settings struct {
	Incoming   Endpoint `json:"incoming"`
	Outgoing   Endpoint `json:"outgoing"`
	CalDAVURL  string   `json:"caldav_url,omitempty"`
	CardDAVURL string   `json:"carddav_url,omitempty"`
}

// Validate checks shape only; reachability and the plaintext policy are checked by the
// caller, which knows the operator allowlist.
func (s Settings) Validate() error {
	if s.Incoming.Protocol != "imap" && s.Incoming.Protocol != "pop3" {
		return fmt.Errorf("incoming.protocol must be imap or pop3")
	}
	for name, e := range map[string]Endpoint{"incoming": s.Incoming, "outgoing": s.Outgoing} {
		if !validHost(e.Host) {
			return fmt.Errorf("%s.host is invalid", name)
		}
		if e.Port < 1 || e.Port > 65535 {
			return fmt.Errorf("%s.port is invalid", name)
		}
		if e.Security != "tls" && e.Security != "starttls" && e.Security != "none" {
			return fmt.Errorf("%s.security must be tls, starttls or none", name)
		}
	}
	for name, u := range map[string]string{"caldav_url": s.CalDAVURL, "carddav_url": s.CardDAVURL} {
		if u == "" {
			continue
		}
		p, err := url.Parse(u)
		if err != nil || p.Scheme != "https" || !validHost(p.Hostname()) || p.User != nil {
			return fmt.Errorf("%s must be an https URL", name)
		}
	}
	return nil
}

var hostLabel = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)

func validHost(h string) bool {
	if net.ParseIP(h) != nil {
		return true
	}
	h = strings.TrimSuffix(h, ".")
	if h == "" || len(h) > 253 {
		return false
	}
	for _, l := range strings.Split(h, ".") {
		if !hostLabel.MatchString(l) {
			return false
		}
	}
	return true
}

type Address struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type Event struct {
	Type      string `json:"type"`
	AccountID string `json:"account_id,omitempty"`
	Folder    string `json:"folder,omitempty"`
	Message   string `json:"message,omitempty"`
}
