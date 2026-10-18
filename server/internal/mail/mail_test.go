package mail

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/testutil"
)

var loopback = testutil.Loopback

var cr = Creds{Username: "alice", Password: "pw"}

func endpoint(_ *testing.T, ln net.Listener, proto string) model.Endpoint {
	return testutil.Endpoint(ln, proto)
}

// ---- IMAP ----

func TestIMAPMailbox(t *testing.T) {
	ctx := context.Background()
	e := testutil.IMAP(t)

	if _, err := dialIMAP(ctx, loopback, e, Creds{Username: "alice", Password: "nope"}); !errors.Is(err, ErrAuth) {
		t.Fatalf("bad password: want ErrAuth, got %v", err)
	}
	if _, err := dialIMAP(ctx, &netguard.Guard{}, e, cr); !errors.Is(err, netguard.ErrBlocked) {
		t.Fatalf("loopback must be blocked without allowlist, got %v", err)
	}

	b, err := dialIMAP(ctx, loopback, e, cr)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()

	folders, err := b.Folders(ctx)
	if err != nil {
		t.Fatal(err)
	}
	roles := map[string]string{}
	for _, f := range folders {
		roles[f.Name] = f.Role
	}
	if roles["INBOX"] != "inbox" || roles["Sent"] != "sent" || roles["Trash"] != "trash" || folders[0].Name != "INBOX" || folders[0].Total != 4 || folders[0].Unread != 4 {
		t.Fatalf("folders: %+v", folders)
	}

	page1, next, err := b.List(ctx, "INBOX", "", 3)
	if err != nil || len(page1) != 3 || next == "" {
		t.Fatalf("page1: %v %q %v", len(page1), next, err)
	}
	if page1[0].Subject != "Grüße" || !page1[0].HasAttachments || page1[0].From.Email != "shop@x.io" {
		t.Fatalf("newest first with decoded subject: %+v", page1[0])
	}
	page2, next2, err := b.List(ctx, "INBOX", next, 3)
	if err != nil || len(page2) != 1 || next2 != "" || page2[0].Subject != "hello 1" {
		t.Fatalf("page2: %+v %q %v", page2, next2, err)
	}

	m, err := b.Get(ctx, "INBOX", page1[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(m.Text, "5€ café") && !strings.Contains(m.Text, "5¤ café") {
		t.Fatalf("charset decode: %q", m.Text)
	}
	if strings.Contains(m.HTML, "script") || strings.Contains(m.HTML, "onclick") || strings.Contains(m.HTML, "track.x.io") || !m.RemoteContentBlocked {
		t.Fatalf("sanitize: %q blocked=%v", m.HTML, m.RemoteContentBlocked)
	}
	if !strings.Contains(m.HTML, `href="https://x.io"`) || !strings.Contains(m.HTML, "noreferrer") {
		t.Fatalf("links must survive with noreferrer: %q", m.HTML)
	}
	if len(m.Attachments) != 1 || m.Attachments[0].Filename != "r.pdf" || m.InReplyTo != "<m1@x.io>" || m.Seen {
		t.Fatalf("message: %+v", m)
	}

	var got bytes.Buffer
	if err := b.Attachment(ctx, "INBOX", page1[0].ID, 0, func(a Attachment) io.Writer { return &got }); err != nil {
		t.Fatal(err)
	}
	if got.String() != "%PDF-1.4\n" {
		t.Fatalf("attachment: %q", got.String())
	}
	if err := b.Attachment(ctx, "INBOX", page1[0].ID, 5, func(Attachment) io.Writer { return io.Discard }); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing attachment: %v", err)
	}

	yes := true
	if err := b.SetFlags(ctx, "INBOX", page1[1].ID, &yes, &yes); err != nil {
		t.Fatal(err)
	}
	l, _, _ := b.List(ctx, "INBOX", "", 10)
	if !l[1].Seen || !l[1].Flagged {
		t.Fatalf("flags not stored: %+v", l[1])
	}

	if err := b.Delete(ctx, "INBOX", page1[2].ID); err != nil {
		t.Fatal(err)
	}
	trash, _, _ := b.List(ctx, "Trash", "", 10)
	if len(trash) != 1 || trash[0].Subject != "hello 2" {
		t.Fatalf("delete must move to Trash: %+v", trash)
	}
	if err := b.Delete(ctx, "Trash", trash[0].ID); err != nil {
		t.Fatal(err)
	}
	if trash, _, _ = b.List(ctx, "Trash", "", 10); len(trash) != 0 {
		t.Fatal("delete in Trash must expunge")
	}
	if err := b.Move(ctx, "INBOX", page1[1].ID, "Archive"); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Get(ctx, "INBOX", "1.999"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("stale uidvalidity id: %v", err)
	}

	if err := b.SaveSent(ctx, []byte(fmt.Sprintf(testutil.PlainMsg, 9, 9, 9))); err != nil {
		t.Fatal(err)
	}
	sent, _, _ := b.List(ctx, "Sent", "", 10)
	if len(sent) != 1 || !sent[0].Seen {
		t.Fatalf("sent copy: %+v", sent)
	}
}

func TestWatchIMAPNotifiesNewMail(t *testing.T) {
	e := testutil.IMAP(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	got := make(chan string, 8)
	done := make(chan error, 1)
	go func() { done <- WatchIMAP(ctx, loopback, e, cr, time.Minute, func(k string) { got <- k }) }()
	time.Sleep(300 * time.Millisecond) // let IDLE start
	testutil.AppendRaw(t, e, "INBOX", fmt.Sprintf(testutil.PlainMsg, 7, 7, 7))
	select {
	case k := <-got:
		if k != "mail.new" {
			t.Fatalf("want mail.new, got %s", k)
		}
	case err := <-done:
		t.Fatalf("watch ended: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("no IDLE notification")
	}
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("watch should stop on cancel, got %v", err)
	}
}

// ---- SMTP ----

func TestBuildAndSubmit(t *testing.T) {
	be, e := testutil.SMTP(t)

	raw, id, err := Build(model.Address{Name: "Alice", Email: "alice@x.io"}, Outgoing{
		To: []model.Address{{Email: "bob@x.io"}}, Bcc: []model.Address{{Email: "hidden@x.io"}},
		Subject: "Grüße", Text: "hi", HTML: "<p>hi<script>x</script></p>", InReplyTo: "<m1@x.io>",
		Attachments: []OutAttachment{{Filename: "a.txt", ContentType: "text/plain", Data: []byte("att")}},
	}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("hidden@x.io")) || bytes.Contains(raw, []byte("<script>")) || !strings.HasSuffix(id, "@x.io>") {
		t.Fatalf("bcc must not be in headers, html sanitized:\n%s", raw)
	}
	p, err := parseMessage(bytes.NewReader(raw), -1, nil)
	if err != nil || p.text != "hi" || len(p.attachments) != 1 {
		t.Fatalf("round trip: %+v %v", p, err)
	}

	if err := Submit(context.Background(), loopback, e, Creds{"alice", "bad"}, "alice@x.io", []string{"bob@x.io"}, raw); !errors.Is(err, ErrAuth) {
		t.Fatalf("bad password: %v", err)
	}
	if err := Submit(context.Background(), loopback, e, Creds{"alice", "pw"}, "alice@x.io", []string{"bob@x.io", "hidden@x.io"}, raw); err != nil {
		t.Fatal(err)
	}
	be.Mu.Lock()
	defer be.Mu.Unlock()
	if be.From != "alice@x.io" || len(be.Rcpt) != 2 || !bytes.Equal(be.Data, raw) {
		t.Fatalf("delivered: %s %v", be.From, be.Rcpt)
	}
}

// ---- POP3 ----

// fakePOP3 serves a fixed maildrop and records DELE commands.
type fakePOP3 struct {
	mu   sync.Mutex
	msgs map[string]string // uidl -> raw, in insertion order via keys slice
	keys []string
}

func (f *fakePOP3) add(uidl, raw string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.msgs == nil {
		f.msgs = map[string]string{}
	}
	f.msgs[uidl] = raw
	f.keys = append(f.keys, uidl)
}

func (f *fakePOP3) serve(ln net.Listener) {
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go f.session(c)
	}
}

func (f *fakePOP3) session(c net.Conn) {
	defer c.Close()
	f.mu.Lock()
	keys := append([]string(nil), f.keys...) // snapshot: a session sees a fixed maildrop
	f.mu.Unlock()
	r := bufio.NewReader(c)
	w := func(s string) { io.WriteString(c, s+"\r\n") }
	dot := func(s string) {
		for _, l := range strings.Split(strings.TrimRight(s, "\r\n"), "\r\n") {
			if strings.HasPrefix(l, ".") {
				l = "." + l
			}
			w(l)
		}
		w(".")
	}
	w("+OK ready")
	authed, user := false, ""
	var deleted []string
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return
		}
		f := strings.Fields(strings.TrimSpace(line))
		if len(f) == 0 {
			continue
		}
		arg := func(i int) int { n, _ := strconv.Atoi(f[i]); return n }
		switch strings.ToUpper(f[0]) {
		case "USER":
			user = f[1]
			w("+OK")
		case "PASS":
			if user == "alice" && f[1] == "pw" {
				authed = true
				w("+OK")
			} else {
				w("-ERR denied")
			}
		case "QUIT":
			fp.commit(deleted)
			w("+OK bye")
			return
		default:
			if !authed {
				w("-ERR auth first")
				continue
			}
			switch strings.ToUpper(f[0]) {
			case "UIDL":
				w("+OK")
				var b strings.Builder
				for i, k := range keys {
					fmt.Fprintf(&b, "%d %s\r\n", i+1, k)
				}
				dot(b.String())
			case "LIST":
				w("+OK")
				var b strings.Builder
				for i, k := range keys {
					fmt.Fprintf(&b, "%d %d\r\n", i+1, len(fp.raw(k)))
				}
				dot(b.String())
			case "RETR", "TOP":
				n := arg(1)
				raw := fp.raw(keys[n-1])
				if f[0] == "TOP" {
					raw, _, _ = strings.Cut(raw, "\r\n\r\n")
				}
				w("+OK")
				dot(raw)
			case "DELE":
				deleted = append(deleted, keys[arg(1)-1])
				w("+OK")
			default:
				w("-ERR unknown")
			}
		}
	}
}

var fp *fakePOP3

func (f *fakePOP3) raw(k string) string { f.mu.Lock(); defer f.mu.Unlock(); return f.msgs[k] }
func (f *fakePOP3) commit(del []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, d := range del {
		delete(f.msgs, d)
		for i, k := range f.keys {
			if k == d {
				f.keys = append(f.keys[:i], f.keys[i+1:]...)
				break
			}
		}
	}
}

func TestPOP3Mailbox(t *testing.T) {
	ctx := context.Background()
	fp = &fakePOP3{}
	fp.add("u1", fmt.Sprintf(testutil.PlainMsg, 1, 1, 1))
	fp.add("u2", testutil.RichMsg)
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	defer ln.Close()
	go fp.serve(ln)

	st, err := store.Open(filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	u, _ := st.UpsertUser(ctx, "alice@x.io", "alice")
	acct, err := st.SaveAccount(ctx, store.Account{ID: store.NewID(), UserID: u.ID, Email: "alice@x.io", Username: "alice",
		Settings:  model.Settings{Incoming: endpoint(t, ln, "pop3"), Outgoing: model.Endpoint{Host: "x", Port: 1, Security: "tls"}},
		SecretKID: "k", Secret: []byte{1}})
	if err != nil {
		t.Fatal(err)
	}
	d := &Dialer{Guard: loopback, Store: st}

	if _, err := d.Open(ctx, acct, Creds{"alice", "x"}); !errors.Is(err, ErrAuth) {
		t.Fatalf("bad password: %v", err)
	}
	box, err := d.Open(ctx, acct, cr)
	if err != nil {
		t.Fatal(err)
	}
	defer box.Close()
	list, next, err := box.List(ctx, "INBOX", "", 10)
	if err != nil || len(list) != 2 || next != "" || list[0].Subject != "Grüße" || list[1].Subject != "hello 1" {
		t.Fatalf("list: %+v %v", list, err)
	}
	m, err := box.Get(ctx, "INBOX", list[0].ID)
	if err != nil || len(m.Attachments) != 1 || !m.RemoteContentBlocked {
		t.Fatalf("get: %+v %v", m, err)
	}
	yes := true
	if err := box.SetFlags(ctx, "INBOX", list[0].ID, &yes, nil); err != nil {
		t.Fatal(err)
	}
	f, _ := box.Folders(ctx)
	if f[0].Total != 2 || f[0].Unread != 1 {
		t.Fatalf("counts: %+v", f)
	}
	if err := box.Move(ctx, "INBOX", list[0].ID, "x"); !errors.Is(err, ErrUnsupported) {
		t.Fatal("pop3 move must be unsupported")
	}

	fp.add("u3", fmt.Sprintf(testutil.PlainMsg, 3, 3, 3))
	if n, err := d.SyncPOP3(ctx, acct, cr); err != nil || n != 1 {
		t.Fatalf("sync new: %d %v", n, err)
	}
	if err := box.Delete(ctx, "INBOX", list[1].ID); err != nil {
		t.Fatal(err)
	}
	if fp.raw("u1") != "" {
		t.Fatal("DELE must be committed on the server")
	}
	list, _, _ = box.List(ctx, "INBOX", "", 10)
	if len(list) != 2 || list[0].Subject != "hello 3" {
		t.Fatalf("after delete: %+v", list)
	}
}
