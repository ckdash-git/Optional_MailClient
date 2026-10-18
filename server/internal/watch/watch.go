// Package watch keeps one push loop per account: IMAP IDLE (or POP3 polling) for mail
// and ETag-digest polling for CalDAV/CardDAV. It publishes change hints to the hub and
// records why an account is unhealthy so the app can show it.
package watch

import (
	"context"
	"errors"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/dav"
	"github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/push"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/vault"
)

type Manager struct {
	Store        *store.Store
	Vault        *vault.Vault
	Guard        *netguard.Guard
	Mail         *mail.Dialer
	HTTP         *http.Client
	Hub          *push.Hub
	Log          *slog.Logger
	POP3Interval time.Duration
	DAVInterval  time.Duration
	IMAPPoll     time.Duration // NOOP interval for servers without IDLE

	mu      sync.Mutex
	running map[string]runner
}

type runner struct {
	key    string
	cancel context.CancelFunc
}

func key(a store.Account) string {
	s := a.Settings
	return strings.Join([]string{s.Incoming.Protocol, s.Incoming.Host, s.Incoming.Security, s.CalDAVURL, s.CardDAVURL, a.Username, a.SecretKID, string(a.Secret)}, "\x00")
}

// Run reconciles running loops with the database until ctx ends.
func (m *Manager) Run(ctx context.Context) {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for {
		m.Reconcile(ctx)
		select {
		case <-ctx.Done():
			m.mu.Lock()
			for id, r := range m.running {
				r.cancel()
				delete(m.running, id)
			}
			m.mu.Unlock()
			return
		case <-t.C:
		}
	}
}

// Reconcile starts loops for watched accounts and stops loops for accounts that were
// deleted, changed, or whose user has no devices left.
func (m *Manager) Reconcile(ctx context.Context) {
	accts, err := m.Store.WatchedAccounts(ctx)
	if err != nil {
		m.Log.Error("watch: list accounts", "err", err)
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.running == nil {
		m.running = map[string]runner{}
	}
	want := map[string]bool{}
	for _, a := range accts {
		want[a.ID] = true
		k := key(a)
		if r, ok := m.running[a.ID]; ok && r.key == k {
			continue
		} else if ok {
			r.cancel()
		}
		rctx, cancel := context.WithCancel(ctx)
		m.running[a.ID] = runner{key: k, cancel: cancel}
		go m.run(rctx, a)
	}
	for id, r := range m.running {
		if !want[id] {
			r.cancel()
			delete(m.running, id)
		}
	}
}

func (m *Manager) creds(a store.Account) (mail.Creds, error) {
	pw, err := m.Vault.Open(a.SecretKID, a.Secret, []byte(a.ID))
	return mail.Creds{Username: a.Username, Password: string(pw)}, err
}

func (m *Manager) run(ctx context.Context, a store.Account) {
	cr, err := m.creds(a)
	if err != nil {
		m.Log.Error("watch: open secret", "account", a.ID, "err", err)
		return
	}
	h := &health{m: m, a: a}
	if a.Settings.CalDAVURL != "" || a.Settings.CardDAVURL != "" {
		go m.davLoop(ctx, a, cr, h)
	}
	switch a.Settings.Incoming.Protocol {
	case "imap":
		m.imapLoop(ctx, a, cr, h)
	case "pop3":
		m.pop3Loop(ctx, a, cr, h)
	}
}

func (m *Manager) publish(a store.Account, ev model.Event) {
	ev.AccountID = a.ID
	m.Hub.Publish(context.Background(), a.UserID, a.Email, ev)
}

// backoff grows 2s, 4s, ... up to 5 minutes, with jitter so a mail server outage does not
// make every account reconnect in the same second.
func backoff(fails int) time.Duration {
	d := 2 * time.Second << min(fails, 8)
	if d > 5*time.Minute {
		d = 5 * time.Minute
	}
	return d/2 + time.Duration(rand.Int64N(int64(d/2)))
}

func sleep(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

func (m *Manager) imapLoop(ctx context.Context, a store.Account, cr mail.Creds, h *health) {
	fails := 0
	for ctx.Err() == nil {
		started := time.Now()
		err := mail.WatchIMAP(ctx, m.Guard, a.Settings.Incoming, cr, m.IMAPPoll, func(kind string) {
			h.ok()
			m.publish(a, model.Event{Type: kind, Folder: "INBOX"})
		})
		if ctx.Err() != nil {
			return
		}
		if time.Since(started) > time.Minute {
			fails = 0 // the connection lived; this is a normal drop, not a failure streak
			h.ok()
		} else {
			fails++
			h.fail(err)
		}
		wait := backoff(fails)
		if errors.Is(err, mail.ErrAuth) {
			wait = 15 * time.Minute // retrying a bad password fast can lock the mailbox
		}
		if !sleep(ctx, wait) {
			return
		}
	}
}

func (m *Manager) pop3Loop(ctx context.Context, a store.Account, cr mail.Creds, h *health) {
	for {
		n, err := m.Mail.SyncPOP3(ctx, a, cr)
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			h.fail(err)
		} else {
			h.ok()
			if n > 0 {
				m.publish(a, model.Event{Type: "mail.new", Folder: "INBOX"})
			}
		}
		if !sleep(ctx, m.POP3Interval) {
			return
		}
	}
}

func (m *Manager) davLoop(ctx context.Context, a store.Account, cr mail.Creds, h *health) {
	for {
		if s, err := dav.Open(ctx, m.HTTP, a, cr.Username, cr.Password); err == nil {
			for _, kind := range []string{"calendar", "contacts"} {
				d, err := s.Digest(ctx, kind)
				if errors.Is(err, dav.ErrNotConfigured) {
					continue
				}
				if err != nil {
					m.Log.Warn("watch: dav digest", "account", a.ID, "kind", kind, "err", err)
					continue
				}
				if changed, err := m.Store.SwapDigest(ctx, a.ID, kind, d); err == nil && changed {
					m.publish(a, model.Event{Type: kind + ".changed"})
				}
			}
		} else if ctx.Err() == nil {
			m.Log.Warn("watch: dav open", "account", a.ID, "err", err)
		}
		if !sleep(ctx, m.DAVInterval) {
			return
		}
	}
}

// health turns a failure streak into one visible error and clears it on recovery.
type health struct {
	m     *Manager
	a     store.Account
	mu    sync.Mutex
	fails int
	shown bool
}

func describe(err error) string {
	switch {
	case errors.Is(err, mail.ErrAuth):
		return "The mail server rejected the password. Sign in again to restore push."
	case errors.Is(err, netguard.ErrBlocked):
		return "The mail server address is not allowed by this server's policy."
	default:
		return "Cannot reach the mail server; new mail may be delayed."
	}
}

func (h *health) fail(err error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.fails++
	h.m.Log.Warn("watch: mail connection failed", "account", h.a.ID, "fails", h.fails, "err", err)
	if h.fails >= 3 && !h.shown {
		h.shown = true
		msg := describe(err)
		_ = h.m.Store.SetAccountError(context.Background(), h.a.ID, msg)
		h.m.publish(h.a, model.Event{Type: "account.error", Message: msg})
	}
}

func (h *health) ok() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.shown || h.fails > 0 {
		if h.shown {
			_ = h.m.Store.SetAccountError(context.Background(), h.a.ID, "")
		}
		h.fails, h.shown = 0, false
	}
}
