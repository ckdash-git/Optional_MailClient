package mail

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
)

type imapBox struct {
	c        *imapclient.Client
	conn     net.Conn
	host     string
	selected string
	uv       uint32
	roles    map[string]string // role -> mailbox name, filled by Folders
}

func newIMAPClient(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds, h *imapclient.UnilateralDataHandler) (*imapclient.Client, net.Conn, error) {
	conn, err := connect(ctx, g, e)
	if err != nil {
		return nil, nil, err
	}
	conn.SetDeadline(time.Now().Add(30 * time.Second))
	opts := &imapclient.Options{TLSConfig: netguard.TLSConfig(e.Host), UnilateralDataHandler: h}
	var c *imapclient.Client
	if e.Security == "starttls" {
		if c, err = imapclient.NewStartTLS(conn, opts); err != nil {
			conn.Close()
			return nil, nil, err
		}
	} else {
		c = imapclient.New(conn, opts)
	}
	if err := c.Login(cr.Username, cr.Password).Wait(); err != nil {
		c.Close()
		var ie *imap.Error
		if errors.As(err, &ie) && ie.Type == imap.StatusResponseTypeNo {
			return nil, nil, ErrAuth
		}
		return nil, nil, err
	}
	conn.SetDeadline(time.Time{})
	return c, conn, nil
}

func dialIMAP(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds) (*imapBox, error) {
	c, conn, err := newIMAPClient(ctx, g, e, cr, nil)
	if err != nil {
		return nil, err
	}
	return &imapBox{c: c, conn: conn, host: e.Host}, nil
}

// op bounds one operation; a server that stops answering cannot hold a request forever.
func (b *imapBox) op(d time.Duration) func() {
	b.conn.SetDeadline(time.Now().Add(d))
	return func() { b.conn.SetDeadline(time.Time{}) }
}

func (b *imapBox) Close() error {
	b.op(5 * time.Second)
	b.c.Logout().Wait()
	return b.c.Close()
}

func msgID(uv uint32, uid imap.UID) string { return fmt.Sprintf("%d.%d", uv, uid) }

func parseMsgID(id string, uv uint32) (imap.UID, error) {
	a, b, ok := strings.Cut(id, ".")
	v, err1 := strconv.ParseUint(a, 10, 32)
	u, err2 := strconv.ParseUint(b, 10, 32)
	if !ok || err1 != nil || err2 != nil || u == 0 || uint32(v) != uv {
		return 0, ErrNotFound // stale UIDVALIDITY means the id no longer names anything
	}
	return imap.UID(u), nil
}

func (b *imapBox) sel(folder string) error {
	if b.selected == folder {
		return nil
	}
	d, err := b.c.Select(folder, nil).Wait()
	if err != nil {
		b.selected = ""
		var ie *imap.Error
		if errors.As(err, &ie) {
			return ErrNotFound
		}
		return err
	}
	b.selected, b.uv = folder, d.UIDValidity
	return nil
}

var roleAttrs = map[imap.MailboxAttr]string{
	imap.MailboxAttrSent: "sent", imap.MailboxAttrDrafts: "drafts", imap.MailboxAttrTrash: "trash",
	imap.MailboxAttrJunk: "junk", imap.MailboxAttrArchive: "archive",
}

var roleNames = map[string]string{
	"sent": "sent", "sent items": "sent", "sent messages": "sent", "sent mail": "sent",
	"drafts": "drafts", "draft": "drafts", "trash": "trash", "deleted items": "trash", "deleted messages": "trash", "bin": "trash",
	"junk": "junk", "spam": "junk", "junk e-mail": "junk", "junk email": "junk", "archive": "archive", "archives": "archive",
}

func (b *imapBox) Folders(ctx context.Context) ([]Folder, error) {
	defer b.op(60 * time.Second)()
	caps := b.c.Caps()
	opts := &imap.ListOptions{}
	if caps.Has(imap.CapListStatus) || caps.Has(imap.CapIMAP4rev2) {
		opts.ReturnStatus = &imap.StatusOptions{NumMessages: true, NumUnseen: true}
	}
	list, err := b.c.List("", "*", opts).Collect()
	if err != nil {
		return nil, err
	}
	b.roles = map[string]string{}
	var out []Folder
	for _, l := range list {
		if slices.Contains(l.Attrs, imap.MailboxAttrNoSelect) || slices.Contains(l.Attrs, imap.MailboxAttrNonExistent) {
			continue
		}
		f := Folder{Name: l.Mailbox}
		if strings.EqualFold(l.Mailbox, "INBOX") {
			f.Role = "inbox"
		}
		for _, a := range l.Attrs {
			if r, ok := roleAttrs[a]; ok {
				f.Role = r
			}
		}
		if f.Role == "" {
			leaf := l.Mailbox
			if l.Delim != 0 {
				leaf = leaf[strings.LastIndexByte(leaf, byte(l.Delim))+1:]
			}
			f.Role = roleNames[strings.ToLower(leaf)]
		}
		if f.Role != "" && b.roles[f.Role] == "" {
			b.roles[f.Role] = f.Name
		}
		st := l.Status
		if st == nil {
			st, _ = b.c.Status(l.Mailbox, &imap.StatusOptions{NumMessages: true, NumUnseen: true}).Wait()
		}
		if st != nil {
			if st.NumMessages != nil {
				f.Total = int(*st.NumMessages)
			}
			if st.NumUnseen != nil {
				f.Unread = int(*st.NumUnseen)
			}
		}
		out = append(out, f)
	}
	order := map[string]int{"inbox": 0, "drafts": 1, "sent": 2, "archive": 3, "junk": 4, "trash": 5, "": 6}
	sort.SliceStable(out, func(i, j int) bool {
		if order[out[i].Role] != order[out[j].Role] {
			return order[out[i].Role] < order[out[j].Role]
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}

func (b *imapBox) role(ctx context.Context, r string) string {
	if b.roles == nil {
		b.Folders(ctx)
	}
	return b.roles[r]
}

func convAddr(l []imap.Address) []model.Address {
	out := make([]model.Address, 0, len(l))
	for _, a := range l {
		if a.IsGroupStart() || a.IsGroupEnd() {
			continue
		}
		out = append(out, model.Address{Name: a.Name, Email: a.Addr()})
	}
	return out
}

func hasAttachment(bs imap.BodyStructure) bool {
	found := false
	if bs == nil {
		return false
	}
	bs.Walk(func(_ []int, p imap.BodyStructure) bool {
		if d := p.Disposition(); d != nil && strings.EqualFold(d.Value, "attachment") {
			found = true
		}
		return !found
	})
	return found
}

func (b *imapBox) summary(folder string, m *imapclient.FetchMessageBuffer) Summary {
	s := Summary{ID: msgID(b.uv, m.UID), Folder: folder, Size: m.RFC822Size, To: []model.Address{}}
	if e := m.Envelope; e != nil {
		if from := convAddr(e.From); len(from) > 0 {
			s.From = from[0]
		}
		s.To = convAddr(e.To)
		s.Subject = e.Subject
		s.Date = e.Date.UTC()
	}
	if s.Date.IsZero() {
		s.Date = m.InternalDate.UTC()
	}
	s.Seen = slices.Contains(m.Flags, imap.FlagSeen)
	s.Flagged = slices.Contains(m.Flags, imap.FlagFlagged)
	s.Answered = slices.Contains(m.Flags, imap.FlagAnswered)
	s.HasAttachments = hasAttachment(m.BodyStructure)
	return s
}

// List pages newest first. ponytail: UID SEARCH returns every UID below the cursor;
// fine up to ~100k messages per folder, switch to ESEARCH/sequence windows beyond that.
func (b *imapBox) List(ctx context.Context, folder, before string, limit int) ([]Summary, string, error) {
	defer b.op(60 * time.Second)()
	if err := b.sel(folder); err != nil {
		return nil, "", err
	}
	crit := &imap.SearchCriteria{}
	if before != "" {
		bu, err := parseMsgID(before, b.uv)
		if err != nil {
			return []Summary{}, "", nil
		}
		if bu <= 1 {
			return []Summary{}, "", nil
		}
		crit.UID = []imap.UIDSet{{{Start: 1, Stop: bu - 1}}}
	}
	data, err := b.c.UIDSearch(crit, nil).Wait()
	if err != nil {
		return nil, "", err
	}
	uids := data.AllUIDs()
	slices.Sort(uids)
	next := ""
	if len(uids) > limit {
		uids = uids[len(uids)-limit:]
		next = msgID(b.uv, uids[0])
	}
	if len(uids) == 0 {
		return []Summary{}, "", nil
	}
	msgs, err := b.c.Fetch(imap.UIDSetNum(uids...), &imap.FetchOptions{
		UID: true, Flags: true, Envelope: true, RFC822Size: true, InternalDate: true,
		BodyStructure: &imap.FetchItemBodyStructure{Extended: true},
	}).Collect()
	if err != nil {
		return nil, "", err
	}
	sort.Slice(msgs, func(i, j int) bool { return msgs[i].UID > msgs[j].UID })
	out := make([]Summary, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, b.summary(folder, m))
	}
	return out, next, nil
}

// fetchOne streams one message: envelope data is collected, the body literal is handed
// to body() as it arrives, so large attachments are never buffered whole.
func (b *imapBox) fetchOne(folder, id string, body func(io.Reader) error) (*imapclient.FetchMessageBuffer, error) {
	if err := b.sel(folder); err != nil {
		return nil, err
	}
	uid, err := parseMsgID(id, b.uv)
	if err != nil {
		return nil, err
	}
	cmd := b.c.Fetch(imap.UIDSetNum(uid), &imap.FetchOptions{
		UID: true, Flags: true, Envelope: true, RFC822Size: true, InternalDate: true,
		BodySection: []*imap.FetchItemBodySection{{Peek: true}},
	})
	defer cmd.Close()
	md := cmd.Next()
	if md == nil {
		if err := cmd.Close(); err != nil {
			return nil, err
		}
		return nil, ErrNotFound
	}
	buf := &imapclient.FetchMessageBuffer{SeqNum: md.SeqNum}
	var bodyErr error
	for item := md.Next(); item != nil; item = md.Next() {
		switch it := item.(type) {
		case imapclient.FetchItemDataUID:
			buf.UID = it.UID
		case imapclient.FetchItemDataFlags:
			buf.Flags = it.Flags
		case imapclient.FetchItemDataEnvelope:
			buf.Envelope = it.Envelope
		case imapclient.FetchItemDataRFC822Size:
			buf.RFC822Size = it.Size
		case imapclient.FetchItemDataInternalDate:
			buf.InternalDate = it.Time
		case imapclient.FetchItemDataBodySection:
			if it.Literal != nil {
				bodyErr = body(it.Literal)
				io.Copy(io.Discard, it.Literal)
			}
		}
	}
	if err := cmd.Close(); err != nil {
		return nil, err
	}
	if bodyErr != nil && bodyErr != errStop {
		return nil, bodyErr
	}
	return buf, nil
}

func (b *imapBox) Get(ctx context.Context, folder, id string) (*Message, error) {
	defer b.op(5 * time.Minute)()
	var p *parsed
	buf, err := b.fetchOne(folder, id, func(r io.Reader) (err error) {
		p, err = parseMessage(r, -1, nil)
		return err
	})
	if err != nil {
		return nil, err
	}
	m := &Message{Summary: b.summary(folder, buf)}
	if p == nil {
		p = &parsed{}
	}
	p.fill(m)
	return m, nil
}

func (b *imapBox) Attachment(ctx context.Context, folder, id string, index int, sink func(Attachment) io.Writer) error {
	defer b.op(10 * time.Minute)()
	found := false
	_, err := b.fetchOne(folder, id, func(r io.Reader) error {
		_, err := parseMessage(r, index, func(a Attachment) io.Writer { found = true; return sink(a) })
		return err
	})
	if err == nil && !found {
		return ErrNotFound
	}
	return err
}

func (b *imapBox) SetFlags(ctx context.Context, folder, id string, seen, flagged *bool) error {
	defer b.op(60 * time.Second)()
	if err := b.sel(folder); err != nil {
		return err
	}
	uid, err := parseMsgID(id, b.uv)
	if err != nil {
		return err
	}
	for flag, v := range map[imap.Flag]*bool{imap.FlagSeen: seen, imap.FlagFlagged: flagged} {
		if v == nil {
			continue
		}
		op := imap.StoreFlagsDel
		if *v {
			op = imap.StoreFlagsAdd
		}
		if err := b.c.Store(imap.UIDSetNum(uid), &imap.StoreFlags{Op: op, Silent: true, Flags: []imap.Flag{flag}}, nil).Close(); err != nil {
			return err
		}
	}
	return nil
}

func (b *imapBox) Move(ctx context.Context, folder, id, to string) error {
	defer b.op(60 * time.Second)()
	if err := b.sel(folder); err != nil {
		return err
	}
	uid, err := parseMsgID(id, b.uv)
	if err != nil {
		return err
	}
	_, err = b.c.Move(imap.UIDSetNum(uid), to).Wait()
	return err
}

func (b *imapBox) Delete(ctx context.Context, folder, id string) error {
	trash := b.role(ctx, "trash")
	if trash != "" && trash != folder {
		return b.Move(ctx, folder, id, trash)
	}
	defer b.op(60 * time.Second)()
	if err := b.sel(folder); err != nil {
		return err
	}
	uid, err := parseMsgID(id, b.uv)
	if err != nil {
		return err
	}
	if err := b.c.Store(imap.UIDSetNum(uid), &imap.StoreFlags{Op: imap.StoreFlagsAdd, Silent: true, Flags: []imap.Flag{imap.FlagDeleted}}, nil).Close(); err != nil {
		return err
	}
	if b.c.Caps().Has(imap.CapUIDPlus) || b.c.Caps().Has(imap.CapIMAP4rev2) {
		return b.c.UIDExpunge(imap.UIDSetNum(uid)).Close()
	}
	return b.c.Expunge().Close()
}

// SaveSent appends to the Sent folder. Gmail files sent mail itself; appending would
// duplicate it.
func (b *imapBox) SaveSent(ctx context.Context, raw []byte) error {
	if strings.HasSuffix(b.host, "gmail.com") || strings.HasSuffix(b.host, "googlemail.com") {
		return nil
	}
	sent := b.role(ctx, "sent")
	if sent == "" {
		return nil
	}
	defer b.op(2 * time.Minute)()
	cmd := b.c.Append(sent, int64(len(raw)), &imap.AppendOptions{Flags: []imap.Flag{imap.FlagSeen}, Time: time.Now()})
	if _, err := io.Copy(cmd, bytes.NewReader(raw)); err != nil {
		cmd.Close()
		return err
	}
	if err := cmd.Close(); err != nil {
		return err
	}
	_, err := cmd.Wait()
	return err
}

// ---- push: IMAP IDLE ----

// WatchIMAP holds one IDLE on INBOX and calls notify("mail.new"|"mail.changed") on
// server updates. It returns when ctx ends or the connection dies; the caller redials.
// Servers without IDLE are polled with NOOP every poll interval.
func WatchIMAP(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds, poll time.Duration, notify func(string)) error {
	events := make(chan string, 16)
	var count uint32
	h := &imapclient.UnilateralDataHandler{
		Mailbox: func(d *imapclient.UnilateralDataMailbox) {
			if d.NumMessages == nil {
				return
			}
			kind := "mail.changed"
			if *d.NumMessages > count {
				kind = "mail.new"
			}
			count = *d.NumMessages
			select {
			case events <- kind:
			default:
			}
		},
		Expunge: func(uint32) {
			select {
			case events <- "mail.changed":
			default:
			}
		},
		Fetch: func(*imapclient.FetchMessageData) {
			select {
			case events <- "mail.changed":
			default:
			}
		},
	}
	c, conn, err := newIMAPClient(ctx, g, e, cr, h)
	if err != nil {
		return err
	}
	defer c.Close()
	conn.SetDeadline(time.Now().Add(30 * time.Second))
	sd, err := c.Select("INBOX", &imap.SelectOptions{ReadOnly: true}).Wait()
	if err != nil {
		return err
	}
	count = sd.NumMessages
	conn.SetDeadline(time.Time{})

	if c.Caps().Has(imap.CapIdle) || c.Caps().Has(imap.CapIMAP4rev2) {
		idle, err := c.Idle()
		if err != nil {
			return err
		}
		defer idle.Close()
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-c.Closed():
				return errors.New("imap: connection closed")
			case k := <-events:
				notify(k)
			}
		}
	}
	t := time.NewTicker(poll)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-c.Closed():
			return errors.New("imap: connection closed")
		case k := <-events:
			notify(k)
		case <-t.C:
			conn.SetDeadline(time.Now().Add(30 * time.Second))
			if err := c.Noop().Wait(); err != nil {
				return err
			}
			conn.SetDeadline(time.Time{})
		}
	}
}
