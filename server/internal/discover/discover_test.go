package discover

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
)

type fakeDNS map[string][]*net.SRV

func (f fakeDNS) LookupSRV(_ context.Context, svc, proto, name string) (string, []*net.SRV, error) {
	if r, ok := f["_"+svc+"._"+proto+"."+name]; ok {
		return "", r, nil
	}
	return "", nil, errors.New("nxdomain")
}

const ispdb = `<?xml version="1.0"?><clientConfig version="1.1"><emailProvider id="x">
 <incomingServer type="pop3"><hostname>pop.x.io</hostname><port>995</port><socketType>SSL</socketType><username>%EMAILADDRESS%</username></incomingServer>
 <incomingServer type="imap"><hostname>imap.x.io</hostname><port>143</port><socketType>STARTTLS</socketType><username>%EMAILLOCALPART%</username></incomingServer>
 <incomingServer type="imap"><hostname>imap.x.io</hostname><port>993</port><socketType>SSL</socketType><username>%EMAILLOCALPART%</username></incomingServer>
 <incomingServer type="imap"><hostname>plain.x.io</hostname><port>143</port><socketType>plain</socketType></incomingServer>
 <outgoingServer type="smtp"><hostname>smtp.x.io</hostname><port>587</port><socketType>STARTTLS</socketType></outgoingServer>
 <outgoingServer type="smtp"><hostname>smtp.x.io</hostname><port>465</port><socketType>SSL</socketType></outgoingServer>
</emailProvider></clientConfig>`

func TestISPDBPrefersIMAPOverTLS(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/x.io") {
			w.Write([]byte(ispdb))
			return
		}
		http.NotFound(w, r)
	}))
	defer ts.Close()
	d := &Discoverer{HTTP: ts.Client(), DNS: fakeDNS{
		"_caldavs._tcp.x.io": {{Target: "dav.x.io.", Port: 443}},
	}, ISPDB: ts.URL + "/v1.1/"}
	r, err := d.Discover(context.Background(), "ana@x.io")
	if err != nil {
		t.Fatal(err)
	}
	in, out := r.Settings.Incoming, r.Settings.Outgoing
	if in.Protocol != "imap" || in.Port != 993 || in.Security != "tls" || !r.LocalPartLogin {
		t.Fatalf("incoming: %+v local=%v", in, r.LocalPartLogin)
	}
	if out.Port != 465 || out.Security != "tls" {
		t.Fatalf("outgoing: %+v", out)
	}
	if r.Settings.CalDAVURL != "https://dav.x.io:443/" || r.Settings.CardDAVURL != "" {
		t.Fatalf("dav: %q %q", r.Settings.CalDAVURL, r.Settings.CardDAVURL)
	}
}

func TestSRVFallbackAndProfiles(t *testing.T) {
	ts := httptest.NewServer(http.NotFoundHandler())
	defer ts.Close()
	d := &Discoverer{HTTP: ts.Client(), ISPDB: ts.URL + "/", DNS: fakeDNS{
		"_imaps._tcp.y.io":       {{Target: "mail.y.io.", Port: 993}},
		"_submission._tcp.y.io":  {{Target: "mail.y.io.", Port: 587}},
		"_submissions._tcp.y.io": {{Target: ".", Port: 0}}, // explicitly not offered
	}}
	r, err := d.Discover(context.Background(), "a@y.io")
	if err != nil {
		t.Fatal(err)
	}
	if r.Settings.Incoming.Host != "mail.y.io" || r.Settings.Outgoing.Security != "starttls" {
		t.Fatalf("%+v", r.Settings)
	}

	corp := model.Settings{Incoming: model.Endpoint{Protocol: "pop3", Host: "pop.corp", Port: 995, Security: "tls"},
		Outgoing: model.Endpoint{Host: "smtp.corp", Port: 465, Security: "tls"}}
	d.Profiles = map[string]model.Settings{"corp.example": corp}
	if r, err := d.Discover(context.Background(), "Boss@Corp.Example"); err != nil || r.Settings != corp {
		t.Fatalf("operator profile must win: %+v %v", r.Settings, err)
	}
	if _, err := d.Discover(context.Background(), "nobody@z.io"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}
