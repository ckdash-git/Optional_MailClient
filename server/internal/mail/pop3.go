package mail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/textproto"
	"strconv"
	"strings"
	"time"

	gomail "github.com/emersion/go-message/mail"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

// pop3Conn is a minimal RFC 1939 client with STLS (RFC 2595). The available Go POP3
// libraries lack STLS and custom TLS settings, and the protocol is small.
type pop3Conn struct {
	conn net.Conn
	tp   *textproto.Conn
}

func (p *pop3Conn) cmd(format string, args ...any) (string, error) {
	p.conn.SetDeadline(time.Now().Add(60 * time.Second))
	if err := p.tp.PrintfLine(format, args...); err != nil {
		return "", err
	}
	return p.status()
}

func (p *pop3Conn) status() (string, error) {
	line, err := p.tp.ReadLine()
	if err != nil {
		return "", err
	}
	if rest, ok := strings.CutPrefix(line, "+OK"); ok {
		return strings.TrimSpace(rest), nil
	}
	return "", fmt.Errorf("pop3: %s", strings.TrimSpace(strings.TrimPrefix(line, "-ERR")))
}

func (p *pop3Conn) lines() ([]string, error) { return p.tp.ReadDotLines() }

func dialPOP3(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds) (*pop3Conn, error) {
	conn, err := connect(ctx, g, e)
	if err != nil {
		return nil, err
	}
	p := &pop3Conn{conn: conn, tp: textproto.NewConn(conn)}
	fail := func(err error) (*pop3Conn, error) { conn.Close(); return nil, err }
	p.conn.SetDeadline(time.Now().Add(30 * time.Second))
	if _, err := p.status(); err != nil {
		return fail(err)
	}
	if e.Security == "starttls" {
		if _, err := p.cmd("STLS"); err != nil {
			return fail(fmt.Errorf("pop3: server refused STLS: %w", err))
		}
		tc := tls.Client(conn, netguard.TLSConfig(e.Host))
		if err := tc.HandshakeContext(ctx); err != nil {
			return fail(err)
		}
		p.conn, p.tp = tc, textproto.NewConn(tc)
	}
	if strings.ContainsAny(cr.Username+cr.Password, "\r\n") {
		return fail(ErrAuth)
	}
	if _, err := p.cmd("USER %s", cr.Username); err != nil {
		return fail(ErrAuth)
	}
	if _, err := p.cmd("PASS %s", cr.Password); err != nil {
		return fail(ErrAuth)
	}
	return p, nil
}

// uidls maps UIDL -> message number for this session.
func (p *pop3Conn) uidls() (map[string]int, error) {
	if _, err := p.cmd("UIDL"); err != nil {
		return nil, err
	}
	ls, err := p.lines()
	if err != nil {
		return nil, err
	}
	out := make(map[string]int, len(ls))
	for _, l := range ls {
		f := strings.Fields(l)
		if len(f) != 2 {
			continue
		}
		if n, err := strconv.Atoi(f[0]); err == nil {
			out[f[1]] = n
		}
	}
	return out, nil
}

func (p *pop3Conn) sizes() (map[int]int64, error) {
	if _, err := p.cmd("LIST"); err != nil {
		return nil, err
	}
	ls, err := p.lines()
	if err != nil {
		return nil, err
	}
	out := map[int]int64{}
	for _, l := range ls {
		f := strings.Fields(l)
		if len(f) == 2 {
			n, _ := strconv.Atoi(f[0])
			s, _ := strconv.ParseInt(f[1], 10, 64)
			out[n] = s
		}
	}
	return out, nil
}

// retr returns a reader over message n; it must be read to EOF before the next command.
func (p *pop3Conn) retr(n int, top bool) (io.Reader, error) {
	cmd := "RETR %d"
	if top {
		cmd = "TOP %d 0"
	}
	if _, err := p.cmd(cmd, n); err != nil {
		return nil, err
	}
	p.conn.SetDeadline(time.Now().Add(10 * time.Minute))
	return p.tp.DotReader(), nil
}

func (p *pop3Conn) Close() error {
	p.cmd("QUIT") // QUIT commits DELE; errors here only mean the server hung up first
	return p.conn.Close()
}

// ---- mailbox adapter ----

// pop3Box opens a fresh POP3 session per operation: a session locks the maildrop and
// never sees mail that arrives after it started.
type pop3Box struct {
	c       *pop3Conn // the session that verified the login; used once, then closed
	open    func(ctx context.Context) (*pop3Conn, error)
	store   *store.Store
	account string
}

func (b *pop3Box) session(ctx context.Context) (*pop3Conn, error) {
	if b.c != nil {
		c := b.c
		b.c = nil
		return c, nil
	}
	if b.open == nil {
		return nil, errors.New("pop3: session closed")
	}
	return b.open(ctx)
}

func (b *pop3Box) Close() error {
	if b.c != nil {
		return b.c.Close()
	}
	return nil
}

// Sync brings the master's POP3 index in line with the maildrop and returns how many
// messages are new. Messages stay on the server (leave-on-server), so every device and
// a desktop client can all see them.
func (b *pop3Box) Sync(ctx context.Context) (int, error) {
	c, err := b.session(ctx)
	if err != nil {
		return 0, err
	}
	defer c.Close()
	remote, err := c.uidls()
	if err != nil {
		return 0, err
	}
	known, err := b.store.Pop3UIDLs(ctx, b.account)
	if err != nil {
		return 0, err
	}
	var gone []int64
	for u, id := range known {
		if _, ok := remote[u]; !ok {
			gone = append(gone, id)
		}
	}
	if err := b.store.Pop3Remove(ctx, b.account, gone); err != nil {
		return 0, err
	}
	sizes, err := c.sizes()
	if err != nil {
		return 0, err
	}
	// Insert oldest first so ids (and therefore list order) follow arrival order.
	nums := make([]struct {
		uidl string
		n    int
	}, 0)
	for u, n := range remote {
		if _, ok := known[u]; !ok {
			nums = append(nums, struct {
				uidl string
				n    int
			}{u, n})
		}
	}
	for i := 1; i < len(nums); i++ {
		for j := i; j > 0 && nums[j].n < nums[j-1].n; j-- {
			nums[j], nums[j-1] = nums[j-1], nums[j]
		}
	}
	for _, x := range nums {
		r, err := c.retr(x.n, true)
		if err != nil {
			return 0, err
		}
		m := store.Pop3Message{UIDL: x.uidl, Size: sizes[x.n], SentAt: time.Now().UTC()}
		if mr, err := gomail.CreateReader(r); err == nil {
			if from := addrs(mr.Header, "From"); len(from) > 0 {
				m.From = from[0]
			}
			m.Subject, _ = mr.Header.Subject()
			if d, err := mr.Header.Date(); err == nil {
				m.SentAt = d.UTC()
			}
		}
		io.Copy(io.Discard, r)
		if err := b.store.Pop3Insert(ctx, b.account, m); err != nil {
			return 0, err
		}
	}
	return len(nums), nil
}

func (b *pop3Box) Folders(ctx context.Context) ([]Folder, error) {
	total, unread, err := b.store.Pop3Counts(ctx, b.account)
	return []Folder{{Name: "INBOX", Role: "inbox", Total: total, Unread: unread}}, err
}

func pop3Summary(m store.Pop3Message) Summary {
	return Summary{ID: strconv.FormatInt(m.ID, 10), Folder: "INBOX", From: m.From, To: []model.Address{},
		Subject: m.Subject, Date: m.SentAt, Seen: m.Seen, Flagged: m.Flagged, Size: m.Size}
}

func pop3ID(folder, id string) (int64, error) {
	n, err := strconv.ParseInt(id, 10, 64)
	if err != nil || n <= 0 || folder != "INBOX" {
		return 0, ErrNotFound
	}
	return n, nil
}

func (b *pop3Box) List(ctx context.Context, folder, before string, limit int) ([]Summary, string, error) {
	if folder != "INBOX" {
		return nil, "", ErrNotFound
	}
	var cursor int64
	if before == "" {
		if _, err := b.Sync(ctx); err != nil {
			return nil, "", err
		}
	} else if n, err := strconv.ParseInt(before, 10, 64); err == nil {
		cursor = n
	}
	rows, err := b.store.Pop3List(ctx, b.account, cursor, limit+1)
	if err != nil {
		return nil, "", err
	}
	next := ""
	if len(rows) > limit {
		rows = rows[:limit]
		next = strconv.FormatInt(rows[len(rows)-1].ID, 10)
	}
	out := make([]Summary, 0, len(rows))
	for _, r := range rows {
		out = append(out, pop3Summary(r))
	}
	return out, next, nil
}

// withMessage finds the message's number in a new session and calls fn.
func (b *pop3Box) withMessage(ctx context.Context, folder, id string, fn func(c *pop3Conn, n int, row store.Pop3Message) error) error {
	n, err := pop3ID(folder, id)
	if err != nil {
		return err
	}
	row, err := b.store.Pop3Get(ctx, b.account, n)
	if err != nil {
		return ErrNotFound
	}
	c, err := b.session(ctx)
	if err != nil {
		return err
	}
	defer c.Close()
	nums, err := c.uidls()
	if err != nil {
		return err
	}
	num, ok := nums[row.UIDL]
	if !ok {
		b.store.Pop3Remove(ctx, b.account, []int64{row.ID})
		return ErrNotFound
	}
	return fn(c, num, row)
}

func (b *pop3Box) Get(ctx context.Context, folder, id string) (*Message, error) {
	var m *Message
	err := b.withMessage(ctx, folder, id, func(c *pop3Conn, n int, row store.Pop3Message) error {
		r, err := c.retr(n, false)
		if err != nil {
			return err
		}
		p, err := parseMessage(r, -1, nil)
		io.Copy(io.Discard, r)
		if err != nil {
			return err
		}
		m = &Message{Summary: pop3Summary(row)}
		m.To = addrs(p.header, "To")
		p.fill(m)
		return nil
	})
	return m, err
}

func (b *pop3Box) Attachment(ctx context.Context, folder, id string, index int, sink func(Attachment) io.Writer) error {
	return b.withMessage(ctx, folder, id, func(c *pop3Conn, n int, _ store.Pop3Message) error {
		r, err := c.retr(n, false)
		if err != nil {
			return err
		}
		found := false
		_, err = parseMessage(r, index, func(a Attachment) io.Writer { found = true; return sink(a) })
		io.Copy(io.Discard, r)
		if err != nil && err != errStop {
			return err
		}
		if !found {
			return ErrNotFound
		}
		return nil
	})
}

func (b *pop3Box) SetFlags(ctx context.Context, folder, id string, seen, flagged *bool) error {
	n, err := pop3ID(folder, id)
	if err != nil {
		return err
	}
	if err := b.store.Pop3SetFlags(ctx, b.account, n, seen, flagged); err == store.ErrNotFound {
		return ErrNotFound
	} else {
		return err
	}
}

func (b *pop3Box) Move(context.Context, string, string, string) error { return ErrUnsupported }

func (b *pop3Box) Delete(ctx context.Context, folder, id string) error {
	return b.withMessage(ctx, folder, id, func(c *pop3Conn, n int, row store.Pop3Message) error {
		if _, err := c.cmd("DELE %d", n); err != nil {
			return err
		}
		if _, err := c.cmd("QUIT"); err != nil { // commit before forgetting it locally
			return err
		}
		return b.store.Pop3Remove(ctx, b.account, []int64{row.ID})
	})
}

func (b *pop3Box) SaveSent(context.Context, []byte) error { return nil }
