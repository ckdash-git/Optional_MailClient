// Package testutil runs throwaway IMAP, SMTP, CalDAV and CardDAV servers on loopback
// for tests. It is only imported from _test files.
package testutil

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-imap/v2/imapserver"
	"github.com/emersion/go-imap/v2/imapserver/imapmemserver"
	"github.com/emersion/go-sasl"
	"github.com/emersion/go-smtp"
	"github.com/emersion/go-vcard"
	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/emersion/go-webdav/carddav"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
)

// Loopback is a guard that lets tests reach 127.0.0.1.
var Loopback = &netguard.Guard{Allow: []netip.Prefix{netip.MustParsePrefix("127.0.0.0/8")}}

func Endpoint(ln net.Listener, proto string) model.Endpoint {
	_, p, _ := net.SplitHostPort(ln.Addr().String())
	port, _ := strconv.Atoi(p)
	return model.Endpoint{Protocol: proto, Host: "127.0.0.1", Port: port, Security: "none"}
}

const PlainMsg = "From: Bob <bob@x.io>\r\nTo: alice@x.io\r\nSubject: hello %d\r\nDate: Mon, 02 Jan 2026 15:04:05 +0000\r\nMessage-ID: <m%d@x.io>\r\n\r\nbody %d\r\n"

const RichMsg = "From: Shop <shop@x.io>\r\nTo: alice@x.io\r\nSubject: =?UTF-8?Q?Gr=C3=BC=C3=9Fe?=\r\nDate: Tue, 03 Jan 2026 10:00:00 +0000\r\nMessage-ID: <rich@x.io>\r\nIn-Reply-To: <m1@x.io>\r\nMIME-Version: 1.0\r\n" +
	"Content-Type: multipart/mixed; boundary=B\r\n\r\n" +
	"--B\r\nContent-Type: multipart/alternative; boundary=A\r\n\r\n" +
	"--A\r\nContent-Type: text/plain; charset=iso-8859-1\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nPreis: 5=A4 caf=E9\r\n" +
	"--A\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p onclick=\"x()\">Hi<script>alert(1)</script><img src=\"https://track.x.io/p.gif\"><a href=\"https://x.io\">link</a></p>\r\n" +
	"--A--\r\n" +
	"--B\r\nContent-Type: application/pdf; name=\"r.pdf\"\r\nContent-Disposition: attachment; filename=\"r.pdf\"\r\nContent-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQK\r\n" +
	"--B--\r\n"

// IMAP starts a server with users alice/pw and mallory/pw2. Alice has folders INBOX,
// Sent, Trash and Archive, and four messages in INBOX (three plain, one multipart with an
// attachment).
func IMAP(t *testing.T) model.Endpoint {
	t.Helper()
	mem := imapmemserver.New()
	u := imapmemserver.NewUser("alice", "pw")
	for _, mb := range []string{"INBOX", "Sent", "Trash", "Archive"} {
		if err := u.Create(mb, nil); err != nil {
			t.Fatal(err)
		}
	}
	mem.AddUser(u)
	m := imapmemserver.NewUser("mallory", "pw2") // a second, unrelated mailbox on the same server
	m.Create("INBOX", nil)
	mem.AddUser(m)
	srv := imapserver.New(&imapserver.Options{
		NewSession: func(*imapserver.Conn) (imapserver.Session, *imapserver.GreetingData, error) {
			return mem.NewSession(), nil, nil
		},
		Caps:         imap.CapSet{imap.CapIMAP4rev1: {}, imap.CapIMAP4rev2: {}},
		InsecureAuth: true,
	})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	e := Endpoint(ln, "imap")
	for i := 1; i <= 3; i++ {
		AppendRaw(t, e, "INBOX", fmt.Sprintf(PlainMsg, i, i, i))
	}
	AppendRaw(t, e, "INBOX", RichMsg)
	return e
}

// AppendRaw stores a message as alice.
func AppendRaw(t *testing.T, e model.Endpoint, mailbox, raw string) {
	t.Helper()
	c, err := imapclient.DialInsecure(net.JoinHostPort(e.Host, strconv.Itoa(e.Port)), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if err := c.Login("alice", "pw").Wait(); err != nil {
		t.Fatal(err)
	}
	cmd := c.Append(mailbox, int64(len(raw)), nil)
	io.WriteString(cmd, raw)
	cmd.Close()
	if _, err := cmd.Wait(); err != nil {
		t.Fatal(err)
	}
}

// SMTPBackend records the last message submitted by alice/pw or mallory/pw2.
type SMTPBackend struct {
	Mu   sync.Mutex
	From string
	Rcpt []string
	Data []byte
}

func (b *SMTPBackend) NewSession(*smtp.Conn) (smtp.Session, error) { return &smtpSession{b: b}, nil }

type smtpSession struct {
	b    *SMTPBackend
	auth bool
}

func (s *smtpSession) AuthMechanisms() []string { return []string{sasl.Plain} }
func (s *smtpSession) Auth(string) (sasl.Server, error) {
	return sasl.NewPlainServer(func(_, user, pass string) error {
		if !(user == "alice" && pass == "pw") && !(user == "mallory" && pass == "pw2") {
			return &smtp.SMTPError{Code: 535, Message: "bad credentials"}
		}
		s.auth = true
		return nil
	}), nil
}
func (s *smtpSession) Mail(from string, _ *smtp.MailOptions) error {
	if !s.auth {
		return smtp.ErrAuthRequired
	}
	s.b.Mu.Lock()
	s.b.From = from
	s.b.Mu.Unlock()
	return nil
}
func (s *smtpSession) Rcpt(to string, _ *smtp.RcptOptions) error {
	s.b.Mu.Lock()
	s.b.Rcpt = append(s.b.Rcpt, to)
	s.b.Mu.Unlock()
	return nil
}
func (s *smtpSession) Data(r io.Reader) error {
	b, _ := io.ReadAll(r)
	s.b.Mu.Lock()
	s.b.Data = b
	s.b.Mu.Unlock()
	return nil
}
func (s *smtpSession) Reset()        {}
func (s *smtpSession) Logout() error { return nil }

// SMTP starts a submission server that requires alice/pw.
func SMTP(t *testing.T) (*SMTPBackend, model.Endpoint) {
	be := &SMTPBackend{}
	srv := smtp.NewServer(be)
	srv.AllowInsecureAuth = true
	srv.Domain = "localhost"
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	return be, Endpoint(ln, "")
}

// memBackend is a tiny CalDAV + CardDAV server backend for tests.
type memBackend struct {
	mu    sync.Mutex
	cals  map[string]caldav.CalendarObject
	cards map[string]carddav.AddressObject
	n     int
}

func (b *memBackend) CurrentUserPrincipal(context.Context) (string, error) { return "/alice/", nil }

func (b *memBackend) etag() string { b.n++; return fmt.Sprintf("e%d", b.n) }

func precondition(cur string, exists bool, ifMatch, ifNone webdav.ConditionalMatch) error {
	if ifNone.IsWildcard() && exists {
		return webdav.NewHTTPError(http.StatusPreconditionFailed, errors.New("exists"))
	}
	if ifMatch.IsSet() {
		if ok, _ := ifMatch.MatchETag(cur); !exists || !ok {
			return webdav.NewHTTPError(http.StatusPreconditionFailed, errors.New("etag mismatch"))
		}
	}
	return nil
}

// --- CalDAV ---

func (b *memBackend) CalendarHomeSetPath(context.Context) (string, error) { return "/alice/cal/", nil }
func (b *memBackend) CreateCalendar(context.Context, *caldav.Calendar) error {
	return webdav.NewHTTPError(403, nil)
}
func (b *memBackend) ListCalendars(context.Context) ([]caldav.Calendar, error) {
	return []caldav.Calendar{{Path: "/alice/cal/work/", Name: "Work", SupportedComponentSet: []string{"VEVENT"}},
		{Path: "/alice/cal/tasks/", Name: "Tasks", SupportedComponentSet: []string{"VTODO"}}}, nil
}
func (b *memBackend) GetCalendar(_ context.Context, p string) (*caldav.Calendar, error) {
	if p == "/alice/cal/work/" {
		return &caldav.Calendar{Path: p, Name: "Work", SupportedComponentSet: []string{"VEVENT"}}, nil
	}
	return nil, webdav.NewHTTPError(404, nil)
}
func (b *memBackend) GetCalendarObject(_ context.Context, p string, _ *caldav.CalendarCompRequest) (*caldav.CalendarObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	o, ok := b.cals[p]
	if !ok {
		return nil, webdav.NewHTTPError(404, nil)
	}
	return &o, nil
}
func (b *memBackend) ListCalendarObjects(_ context.Context, p string, _ *caldav.CalendarCompRequest) ([]caldav.CalendarObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	var out []caldav.CalendarObject
	for k, o := range b.cals {
		if strings.HasPrefix(k, p) {
			out = append(out, o)
		}
	}
	return out, nil
}
func (b *memBackend) QueryCalendarObjects(ctx context.Context, p string, q *caldav.CalendarQuery) ([]caldav.CalendarObject, error) {
	all, _ := b.ListCalendarObjects(ctx, p, nil)
	return caldav.Filter(q, all)
}
func (b *memBackend) PutCalendarObject(_ context.Context, p string, cal *ical.Calendar, o *caldav.PutCalendarObjectOptions) (*caldav.CalendarObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	cur, exists := b.cals[p]
	if err := precondition(cur.ETag, exists, o.IfMatch, o.IfNoneMatch); err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	ical.NewEncoder(&buf).Encode(cal)
	obj := caldav.CalendarObject{Path: p, ETag: b.etag(), Data: cal, ModTime: time.Now(), ContentLength: int64(buf.Len())}
	b.cals[p] = obj
	return &obj, nil
}
func (b *memBackend) DeleteCalendarObject(_ context.Context, p string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.cals, p)
	return nil
}

// --- CardDAV ---

func (b *memBackend) AddressBookHomeSetPath(context.Context) (string, error) {
	return "/alice/card/", nil
}
func (b *memBackend) ListAddressBooks(context.Context) ([]carddav.AddressBook, error) {
	return []carddav.AddressBook{{Path: "/alice/card/default/", Name: "Contacts"}}, nil
}
func (b *memBackend) GetAddressBook(_ context.Context, p string) (*carddav.AddressBook, error) {
	if p == "/alice/card/default/" {
		return &carddav.AddressBook{Path: p, Name: "Contacts"}, nil
	}
	return nil, webdav.NewHTTPError(404, nil)
}
func (b *memBackend) CreateAddressBook(context.Context, *carddav.AddressBook) error {
	return webdav.NewHTTPError(403, nil)
}
func (b *memBackend) DeleteAddressBook(context.Context, string) error {
	return webdav.NewHTTPError(403, nil)
}
func (b *memBackend) GetAddressObject(_ context.Context, p string, _ *carddav.AddressDataRequest) (*carddav.AddressObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	o, ok := b.cards[p]
	if !ok {
		return nil, webdav.NewHTTPError(404, nil)
	}
	return &o, nil
}
func (b *memBackend) ListAddressObjects(_ context.Context, p string, _ *carddav.AddressDataRequest) ([]carddav.AddressObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	var out []carddav.AddressObject
	for k, o := range b.cards {
		if strings.HasPrefix(k, p) {
			out = append(out, o)
		}
	}
	return out, nil
}
func (b *memBackend) QueryAddressObjects(ctx context.Context, p string, q *carddav.AddressBookQuery) ([]carddav.AddressObject, error) {
	all, _ := b.ListAddressObjects(ctx, p, nil)
	return carddav.Filter(q, all)
}
func (b *memBackend) PutAddressObject(_ context.Context, p string, c vcard.Card, o *carddav.PutAddressObjectOptions) (*carddav.AddressObject, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	cur, exists := b.cards[p]
	if err := precondition(cur.ETag, exists, o.IfMatch, o.IfNoneMatch); err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	vcard.NewEncoder(&buf).Encode(c)
	obj := carddav.AddressObject{Path: p, ETag: b.etag(), Card: c, ModTime: time.Now(), ContentLength: int64(buf.Len())}
	b.cards[p] = obj
	return &obj, nil
}
func (b *memBackend) DeleteAddressObject(_ context.Context, p string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.cards, p)
	return nil
}

// DAV starts CalDAV and CardDAV servers (basic auth alice/pw). Principal /alice/,
// calendar /alice/cal/work/, address book /alice/card/default/. The returned client
// trusts both test certificates.
func DAV(t *testing.T) (cal, card *httptest.Server, client *http.Client) {
	be := &memBackend{cals: map[string]caldav.CalendarObject{}, cards: map[string]carddav.AddressObject{}}
	auth := func(h http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if u, p, ok := r.BasicAuth(); !ok || u != "alice" || p != "pw" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			h.ServeHTTP(w, r)
		})
	}
	cal = httptest.NewTLSServer(auth(&caldav.Handler{Backend: be}))
	card = httptest.NewTLSServer(auth(&carddav.Handler{Backend: be}))
	t.Cleanup(cal.Close)
	t.Cleanup(card.Close)
	client = cal.Client()
	client.Transport.(*http.Transport).TLSClientConfig.RootCAs.AddCert(card.Certificate())
	return cal, card, client
}
