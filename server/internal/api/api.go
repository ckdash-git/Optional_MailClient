// Package api is the master's HTTP surface, documented in docs/API.md.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"

	"github.com/ckdash-git/optional_mailclient/server/internal/dav"
	"github.com/ckdash-git/optional_mailclient/server/internal/discover"
	"github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/push"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/vault"
	"github.com/ckdash-git/optional_mailclient/server/internal/watch"
)

type Server struct {
	Store          *store.Store
	Vault          *vault.Vault
	Guard          *netguard.Guard
	Discover       *discover.Discoverer
	Mail           *mail.Dialer
	Pool           *mail.Pool
	HTTP           *http.Client // guarded client for CalDAV/CardDAV
	Hub            *push.Hub
	Watch          *watch.Manager
	Log            *slog.Logger
	AllowCustom    bool
	TrustedProxies []netip.Prefix
	CORSOrigins    []string

	once     sync.Once
	ipAuth   *limiter // login, discover: per client IP
	ipSoft   *limiter // refresh, stream connects: per client IP, roomy for offices behind one NAT
	userAuth *limiter // login attempts per email address
	perUser  *limiter // everything else: per user
}

func (s *Server) init() {
	s.once.Do(func() {
		s.ipAuth = newLimiter(rate.Every(2*time.Second), 20)
		s.ipSoft = newLimiter(5, 100)
		s.userAuth = newLimiter(rate.Every(time.Minute), 5)
		s.perUser = newLimiter(20, 60)
	})
}

func (s *Server) Handler() http.Handler {
	s.init()
	mux := http.NewServeMux()
	pub := func(pattern string, h http.HandlerFunc) { mux.Handle(pattern, s.limitIP(s.ipAuth, h)) }
	auth := func(pattern string, h func(http.ResponseWriter, *http.Request, principal)) {
		mux.Handle(pattern, s.authed(h))
	}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { io.WriteString(w, "ok") })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if err := s.Store.Ping(r.Context()); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}
		io.WriteString(w, "ok")
	})

	pub("POST /v1/auth/login", s.login)
	mux.Handle("POST /v1/auth/refresh", s.limitIP(s.ipSoft, s.refresh))
	pub("POST /v1/discover", s.discover)
	mux.HandleFunc("GET /v1/stream", s.stream) // authenticates in its first frame

	auth("POST /v1/auth/logout", s.logout)
	auth("GET /v1/me", s.me)
	auth("GET /v1/devices", s.devices)
	auth("DELETE /v1/devices/{id}", s.deleteDevice)
	auth("PUT /v1/devices/current/push", s.setPush)
	auth("DELETE /v1/devices/current/push", s.clearPush)

	auth("GET /v1/accounts", s.accounts)
	auth("POST /v1/accounts", s.addAccount)
	auth("DELETE /v1/accounts/{aid}", s.deleteAccount)

	auth("GET /v1/accounts/{aid}/folders", s.folders)
	auth("GET /v1/accounts/{aid}/messages", s.listMessages)
	auth("GET /v1/accounts/{aid}/messages/{id}", s.getMessage)
	auth("GET /v1/accounts/{aid}/messages/{id}/attachments/{index}", s.attachment)
	auth("PATCH /v1/accounts/{aid}/messages/{id}", s.setFlags)
	auth("POST /v1/accounts/{aid}/messages/{id}/move", s.move)
	auth("DELETE /v1/accounts/{aid}/messages/{id}", s.deleteMessage)
	auth("POST /v1/accounts/{aid}/send", s.send)

	auth("GET /v1/accounts/{aid}/calendars", s.calendars)
	auth("GET /v1/accounts/{aid}/events", s.events)
	auth("PUT /v1/accounts/{aid}/events", s.putEvent)
	auth("DELETE /v1/accounts/{aid}/events", s.deleteEvent)
	auth("GET /v1/accounts/{aid}/addressbooks", s.addressBooks)
	auth("GET /v1/accounts/{aid}/contacts", s.contacts)
	auth("PUT /v1/accounts/{aid}/contacts", s.putContact)
	auth("DELETE /v1/accounts/{aid}/contacts", s.deleteContact)

	return s.recoverer(s.headers(s.cors(mux)))
}

// ---- middleware ----

func (s *Server) headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

// cors lets a browser client on an allowlisted origin call the API. Auth is a bearer
// token, never a cookie, so no credentials mode is needed.
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		allowed := false
		for _, o := range s.CORSOrigins {
			allowed = allowed || (origin != "" && o == origin)
		}
		if allowed {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Add("Vary", "Origin")
			h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE")
			h.Set("Access-Control-Max-Age", "600")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil && v != http.ErrAbortHandler {
				s.Log.Error("panic", "path", r.URL.Path, "panic", fmt.Sprint(v), "stack", string(debug.Stack()))
				writeErr(w, http.StatusInternalServerError, "internal", "internal error")
			}
		}()
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		// No query strings or bodies in logs: they can carry folder names and addresses.
		s.Log.Info("http", "method", r.Method, "path", r.Pattern, "status", sw.status, "ms", time.Since(start).Milliseconds())
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(c int)           { w.status = c; w.ResponseWriter.WriteHeader(c) }
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }
func (w *statusWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// clientIP trusts X-Forwarded-For only when the direct peer is a configured proxy, and
// then takes the right-most address that is not itself a proxy.
func (s *Server) clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	trusted := func(h string) bool {
		a, err := netip.ParseAddr(h)
		if err != nil {
			return false
		}
		for _, p := range s.TrustedProxies {
			if p.Contains(a.Unmap()) {
				return true
			}
		}
		return false
	}
	if !trusted(host) {
		return host
	}
	parts := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		p := strings.TrimSpace(parts[i])
		if _, err := netip.ParseAddr(p); err == nil && !trusted(p) {
			return p
		}
	}
	return host
}

func (s *Server) limitIP(l *limiter, h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !l.allow(s.clientIP(r)) {
			tooMany(w)
			return
		}
		h(w, r)
	})
}

type principal struct {
	User     store.User
	DeviceID string
}

func bearer(r *http.Request) string {
	v := r.Header.Get("Authorization")
	if t, ok := strings.CutPrefix(v, "Bearer "); ok {
		return strings.TrimSpace(t)
	}
	return ""
}

func (s *Server) authed(h func(http.ResponseWriter, *http.Request, principal)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, dev, err := s.Store.Authenticate(r.Context(), bearer(r))
		if err != nil {
			if !errors.Is(err, store.ErrInvalidToken) {
				s.Log.Error("auth lookup", "err", err)
			}
			writeErr(w, http.StatusUnauthorized, "unauthorized", "missing, expired or revoked token")
			return
		}
		if !s.perUser.allow(u.ID) {
			tooMany(w)
			return
		}
		h(w, r, principal{User: u, DeviceID: dev})
	})
}

// ---- rate limiter ----

type limiter struct {
	mu    sync.Mutex
	every rate.Limit
	burst int
	m     map[string]*entry
	last  time.Time
}

type entry struct {
	l    *rate.Limiter
	seen time.Time
}

func newLimiter(r rate.Limit, burst int) *limiter {
	return &limiter{every: r, burst: burst, m: map[string]*entry{}, last: time.Now()}
}

func (l *limiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if now.Sub(l.last) > 10*time.Minute { // drop idle keys so the map cannot grow forever
		for k, e := range l.m {
			if now.Sub(e.seen) > 30*time.Minute {
				delete(l.m, k)
			}
		}
		l.last = now
	}
	e, ok := l.m[key]
	if !ok {
		e = &entry{l: rate.NewLimiter(l.every, l.burst)}
		l.m[key] = e
	}
	e.seen = now
	return e.l.Allow()
}

func tooMany(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "60")
	writeErr(w, http.StatusTooManyRequests, "rate_limited", "too many requests, slow down")
}

// ---- JSON helpers ----

const maxBody = 1 << 20

func decode(w http.ResponseWriter, r *http.Request, limit int64, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			writeErr(w, http.StatusRequestEntityTooLarge, "too_large", "request body too large")
			return false
		}
		writeErr(w, http.StatusBadRequest, "bad_request", "invalid JSON: "+err.Error())
		return false
	}
	if dec.More() {
		writeErr(w, http.StatusBadRequest, "bad_request", "one JSON object expected")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": msg}})
}

func badRequest(w http.ResponseWriter, msg string) {
	writeErr(w, http.StatusBadRequest, "bad_request", msg)
}

// fail maps adapter errors to API errors. Unknown errors are logged, not echoed: they
// can contain server banners or internal addresses.
func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, mail.ErrNotFound), errors.Is(err, store.ErrNotFound), errors.Is(err, dav.ErrNotFound):
		writeErr(w, http.StatusNotFound, "not_found", "not found")
	case errors.Is(err, dav.ErrNotConfigured):
		writeErr(w, http.StatusNotFound, "not_found", "this account has no calendar or contacts server")
	case errors.Is(err, dav.ErrConflict):
		writeErr(w, http.StatusConflict, "conflict", "changed on the server since you loaded it; reload and try again")
	case errors.Is(err, dav.ErrBadID):
		badRequest(w, err.Error())
	case errors.Is(err, mail.ErrUnsupported):
		badRequest(w, "not supported by this account's protocol")
	case errors.Is(err, netguard.ErrBlocked):
		writeErr(w, http.StatusForbidden, "forbidden", "this server address is not allowed")
	case errors.Is(err, mail.ErrAuth):
		writeErr(w, http.StatusBadGateway, "upstream_error", "the mail server rejected the stored password; sign in again")
	case errors.Is(err, context.Canceled):
		// client went away
	default:
		s.Log.Warn("upstream error", "path", r.Pattern, "err", err)
		writeErr(w, http.StatusBadGateway, "upstream_error", "the mail server failed or is unreachable")
	}
}
