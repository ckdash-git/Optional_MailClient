// Package mail adapts IMAP and POP3 mailboxes, and SMTP submission, to one shape.
package mail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

var (
	ErrNotFound    = errors.New("message not found")
	ErrAuth        = errors.New("authentication failed")
	ErrUnsupported = errors.New("not supported by this account's protocol")
)

type Folder struct {
	Name   string `json:"name"`
	Role   string `json:"role"`
	Unread int    `json:"unread"`
	Total  int    `json:"total"`
}

type Summary struct {
	ID             string          `json:"id"`
	Folder         string          `json:"folder"`
	From           model.Address   `json:"from"`
	To             []model.Address `json:"to"`
	Subject        string          `json:"subject"`
	Date           time.Time       `json:"date"`
	Seen           bool            `json:"seen"`
	Flagged        bool            `json:"flagged"`
	Answered       bool            `json:"answered"`
	HasAttachments bool            `json:"has_attachments"`
	Size           int64           `json:"size"`
}

type Attachment struct {
	Index       int    `json:"index"`
	Filename    string `json:"filename"`
	ContentType string `json:"content_type"`
	Size        int64  `json:"size"`
}

type Message struct {
	Summary
	Cc                   []model.Address `json:"cc"`
	ReplyTo              []model.Address `json:"reply_to"`
	MessageID            string          `json:"message_id"`
	InReplyTo            string          `json:"in_reply_to"`
	References           []string        `json:"references"`
	Text                 string          `json:"text"`
	HTML                 string          `json:"html"`
	RemoteContentBlocked bool            `json:"remote_content_blocked"`
	Attachments          []Attachment    `json:"attachments"`
}

// Mailbox is one authenticated connection. It is not safe for concurrent use; the Pool
// hands each one to a single request at a time.
type Mailbox interface {
	Folders(ctx context.Context) ([]Folder, error)
	List(ctx context.Context, folder, before string, limit int) ([]Summary, string, error)
	Get(ctx context.Context, folder, id string) (*Message, error)
	// Attachment streams the decoded attachment with this index to w.
	Attachment(ctx context.Context, folder, id string, index int, w func(Attachment) io.Writer) error
	SetFlags(ctx context.Context, folder, id string, seen, flagged *bool) error
	Move(ctx context.Context, folder, id, to string) error
	Delete(ctx context.Context, folder, id string) error
	// SaveSent stores a copy of a sent message, if the protocol has somewhere to put it.
	SaveSent(ctx context.Context, raw []byte) error
	Close() error
}

type Creds struct {
	Username string
	Password string
}

// Dialer opens mailboxes through the SSRF guard.
type Dialer struct {
	Guard *netguard.Guard
	Store *store.Store
}

func (d *Dialer) Open(ctx context.Context, a store.Account, c Creds) (Mailbox, error) {
	switch a.Settings.Incoming.Protocol {
	case "imap":
		return dialIMAP(ctx, d.Guard, a.Settings.Incoming, c)
	case "pop3":
		open := func(ctx context.Context) (*pop3Conn, error) { return dialPOP3(ctx, d.Guard, a.Settings.Incoming, c) }
		p, err := open(ctx)
		if err != nil {
			return nil, err
		}
		return &pop3Box{c: p, open: open, store: d.Store, account: a.ID}, nil
	}
	return nil, fmt.Errorf("unknown protocol %q", a.Settings.Incoming.Protocol)
}

// connect dials host:port through the guard and does implicit TLS when asked.
// STARTTLS upgrades are protocol specific and done by the caller.
func connect(ctx context.Context, g *netguard.Guard, e model.Endpoint) (net.Conn, error) {
	addr := net.JoinHostPort(e.Host, strconv.Itoa(e.Port))
	conn, err := g.Dialer(15*time.Second).DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	if e.Security != "tls" {
		return conn, nil
	}
	tc := tls.Client(conn, netguard.TLSConfig(e.Host))
	hctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	if err := tc.HandshakeContext(hctx); err != nil {
		conn.Close()
		return nil, err
	}
	return tc, nil
}

// ---- pool ----

// Pool keeps at most one idle mailbox per account for a short time, so a user paging
// through a folder does not pay a TLS handshake and login per request.
type Pool struct {
	Dialer *Dialer
	TTL    time.Duration

	mu   sync.Mutex
	idle map[string]pooled
}

type pooled struct {
	box  Mailbox
	key  string
	used time.Time
}

func poolKey(a store.Account) string {
	in := a.Settings.Incoming
	return strings.Join([]string{a.ID, in.Protocol, in.Host, strconv.Itoa(in.Port), in.Security, a.SecretKID, string(a.Secret)}, "\x00")
}

// With runs fn on a pooled or fresh mailbox. A mailbox that returned an error is not
// reused, since its connection state is unknown.
func (p *Pool) With(ctx context.Context, a store.Account, c Creds, fn func(Mailbox) error) error {
	key := poolKey(a)
	p.mu.Lock()
	it, ok := p.idle[a.ID]
	delete(p.idle, a.ID)
	p.mu.Unlock()
	if ok && (it.key != key || time.Since(it.used) > p.TTL) {
		it.box.Close()
		ok = false
	}
	box := it.box
	if !ok {
		var err error
		if box, err = p.Dialer.Open(ctx, a, c); err != nil {
			return err
		}
	}
	if err := fn(box); err != nil {
		box.Close()
		return err
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.idle == nil {
		p.idle = map[string]pooled{}
	}
	if old, ok := p.idle[a.ID]; ok {
		old.box.Close()
	}
	p.idle[a.ID] = pooled{box: box, key: key, used: time.Now()}
	return nil
}

// Drop closes the idle mailbox of an account (after deletion or a password change).
func (p *Pool) Drop(accountID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if it, ok := p.idle[accountID]; ok {
		it.box.Close()
		delete(p.idle, accountID)
	}
}

// Sweep closes mailboxes idle longer than the TTL; call it periodically.
func (p *Pool) Sweep() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for id, it := range p.idle {
		if time.Since(it.used) > p.TTL {
			it.box.Close()
			delete(p.idle, id)
		}
	}
}

// SyncPOP3 refreshes the POP3 index of an account and returns the number of new messages.
func (d *Dialer) SyncPOP3(ctx context.Context, a store.Account, c Creds) (int, error) {
	box, err := d.Open(ctx, a, c)
	if err != nil {
		return 0, err
	}
	defer box.Close()
	return box.(*pop3Box).Sync(ctx)
}
