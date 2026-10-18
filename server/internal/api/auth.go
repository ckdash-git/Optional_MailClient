package api

import (
	"context"
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/discover"
	mailx "github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

var platforms = map[string]bool{"android": true, "ios": true, "macos": true, "windows": true, "linux": true, "web": true}

const maxAccountsPerUser = 20

type accountJSON struct {
	ID               string `json:"id"`
	Email            string `json:"email"`
	DisplayName      string `json:"display_name"`
	IncomingProtocol string `json:"incoming_protocol"`
	HasCalendar      bool   `json:"has_calendar"`
	HasContacts      bool   `json:"has_contacts"`
	LastError        string `json:"last_error"`
}

func toAccountJSON(a store.Account) accountJSON {
	return accountJSON{ID: a.ID, Email: a.Email, DisplayName: a.DisplayName, IncomingProtocol: a.Settings.Incoming.Protocol,
		HasCalendar: a.Settings.CalDAVURL != "", HasContacts: a.Settings.CardDAVURL != "", LastError: a.LastError}
}

func validEmail(s string) bool {
	a, err := mail.ParseAddress(s)
	return err == nil && a.Address == s && len(s) <= 254 && strings.Count(s, "@") == 1
}

type credsReq struct {
	Email       string          `json:"email"`
	Password    string          `json:"password"`
	Username    string          `json:"username"`
	DisplayName string          `json:"display_name"`
	Server      *model.Settings `json:"server"`
}

func (c *credsReq) validate() string {
	c.Email = strings.TrimSpace(c.Email)
	switch {
	case !validEmail(c.Email):
		return "email is invalid"
	case c.Password == "" || len(c.Password) > 1024:
		return "password is required"
	case len(c.Username) > 320 || strings.ContainsAny(c.Username, "\r\n\x00"):
		return "username is invalid"
	case len(c.DisplayName) > 200 || strings.ContainsAny(c.DisplayName, "\r\n\x00"):
		return "display_name is invalid"
	}
	return ""
}

type apiError struct {
	status    int
	code, msg string
}

func (e *apiError) Error() string { return e.msg }

// resolve picks the settings for an address: the operator's profile wins, then the
// client's explicit settings (if allowed), then autodiscovery.
func (s *Server) resolve(ctx context.Context, c credsReq) (model.Settings, string, error) {
	username := c.Username
	set, ok := s.Discover.Profile(c.Email)
	if !ok && c.Server != nil {
		if !s.AllowCustom {
			return set, "", &apiError{http.StatusForbidden, "forbidden", "this server only supports its configured mail domains"}
		}
		set = *c.Server
	} else if !ok {
		r, err := s.Discover.Discover(ctx, c.Email)
		if err != nil {
			return set, "", &apiError{http.StatusUnprocessableEntity, "discovery_failed", "could not find server settings for this address; enter them manually"}
		}
		set = r.Settings
		if username == "" && r.LocalPartLogin {
			username, _, _ = strings.Cut(c.Email, "@")
		}
	}
	if err := set.Validate(); err != nil {
		return set, "", &apiError{http.StatusBadRequest, "bad_request", err.Error()}
	}
	// Plaintext only to hosts the operator allowlisted (e.g. an on-prem server on a LAN).
	for _, e := range []model.Endpoint{set.Incoming, set.Outgoing} {
		if e.Security == "none" && !s.Guard.AllowsHost(ctx, e.Host) {
			return set, "", &apiError{http.StatusBadRequest, "bad_request", "unencrypted connections are not allowed; use tls or starttls"}
		}
	}
	if username == "" {
		username = c.Email
	}
	return set, username, nil
}

// verify proves the password against the incoming and outgoing servers and returns the
// account ready to save (sealed secret, stable id).
func (s *Server) verify(ctx context.Context, userID string, c credsReq, set model.Settings, username string) (store.Account, error) {
	a := store.Account{ID: store.NewID(), UserID: userID, Email: strings.ToLower(c.Email), DisplayName: c.DisplayName, Username: username, Settings: set}
	cr := mailx.Creds{Username: username, Password: c.Password}
	box, err := s.Mail.Open(ctx, a, cr)
	if err != nil {
		return a, s.loginErr(err, "incoming")
	}
	box.Close()
	if err := mailx.VerifySMTP(ctx, s.Guard, set.Outgoing, cr); err != nil {
		return a, s.loginErr(err, "outgoing")
	}
	return a, nil
}

func (s *Server) seal(ctx context.Context, a *store.Account, password string) error {
	if id, ok, err := s.Store.AccountIDByEmail(ctx, a.UserID, a.Email); err != nil {
		return err
	} else if ok {
		a.ID = id // re-login: keep the id the secret is bound to
	}
	a.SecretKID, a.Secret = s.Vault.Seal([]byte(password), []byte(a.ID))
	return nil
}

func (s *Server) loginErr(err error, which string) error {
	switch {
	case errors.Is(err, mailx.ErrAuth):
		return &apiError{http.StatusUnauthorized, "invalid_credentials", "the " + which + " mail server rejected the email or password"}
	case errors.Is(err, context.DeadlineExceeded), errors.Is(err, context.Canceled):
		return &apiError{http.StatusBadGateway, "upstream_error", "the " + which + " mail server did not answer in time"}
	}
	if errors.Is(err, netguard.ErrBlocked) {
		return &apiError{http.StatusForbidden, "forbidden", "the " + which + " server address is not allowed"}
	}
	s.Log.Info("login: upstream failure", "which", which, "err", err)
	return &apiError{http.StatusBadGateway, "upstream_error", "could not connect to the " + which + " mail server; check the server settings"}
}

func (s *Server) writeAPIErr(w http.ResponseWriter, err error) {
	var ae *apiError
	if errors.As(err, &ae) {
		writeErr(w, ae.status, ae.code, ae.msg)
		return
	}
	s.Log.Error("internal", "err", err)
	writeErr(w, http.StatusInternalServerError, "internal", "internal error")
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		credsReq
		Device struct {
			Name     string `json:"name"`
			Platform string `json:"platform"`
		} `json:"device"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	if msg := req.validate(); msg != "" {
		badRequest(w, msg)
		return
	}
	req.Device.Name = strings.TrimSpace(req.Device.Name)
	if req.Device.Name == "" || len(req.Device.Name) > 100 || !platforms[req.Device.Platform] {
		badRequest(w, "device.name and a valid device.platform are required")
		return
	}
	if !s.userAuth.allow(strings.ToLower(req.Email)) {
		tooMany(w)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
	defer cancel()
	set, username, err := s.resolve(ctx, req.credsReq)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	a, err := s.verify(ctx, "", req.credsReq, set, username)
	if err != nil {
		s.Store.Audit(ctx, "", "", "login.failed", s.clientIP(r))
		s.writeAPIErr(w, err)
		return
	}
	u, err := s.Store.UpsertUser(ctx, req.Email, store.Identity(a.Username, set.Incoming))
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	a.UserID = u.ID
	if err := s.seal(ctx, &a, req.Password); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	if a, err = s.Store.SaveAccount(ctx, a); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	s.Pool.Drop(a.ID)
	dev, err := s.Store.CreateDevice(ctx, u.ID, req.Device.Name, req.Device.Platform)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	t, err := s.Store.IssueTokens(ctx, dev.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	s.Store.Audit(ctx, u.ID, dev.ID, "login", s.clientIP(r))
	go s.Watch.Reconcile(context.WithoutCancel(r.Context()))
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": t.AccessToken, "access_expires_at": t.AccessExpiresAt, "refresh_token": t.RefreshToken,
		"user": u, "account_id": a.ID,
	})
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	t, err := s.Store.Refresh(r.Context(), req.RefreshToken)
	if errors.Is(err, store.ErrTokenReuse) {
		s.Store.Audit(r.Context(), "", "", "refresh.reuse_detected", s.clientIP(r))
	}
	if err != nil {
		if !errors.Is(err, store.ErrInvalidToken) && !errors.Is(err, store.ErrTokenReuse) {
			s.Log.Error("refresh", "err", err)
		}
		writeErr(w, http.StatusUnauthorized, "unauthorized", "invalid or expired refresh token")
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request, p principal) {
	if err := s.Store.DeleteDevice(r.Context(), p.User.ID, p.DeviceID); err != nil && !errors.Is(err, store.ErrNotFound) {
		s.writeAPIErr(w, err)
		return
	}
	s.Hub.Disconnect(p.DeviceID)
	s.Store.Audit(r.Context(), p.User.ID, p.DeviceID, "logout", s.clientIP(r))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request, p principal) {
	accts, err := s.Store.ListAccounts(r.Context(), p.User.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	out := make([]accountJSON, 0, len(accts))
	for _, a := range accts {
		out = append(out, toAccountJSON(a))
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": p.User, "device_id": p.DeviceID, "accounts": out})
}

func (s *Server) devices(w http.ResponseWriter, r *http.Request, p principal) {
	ds, err := s.Store.ListDevices(r.Context(), p.User.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	type devJSON struct {
		ID         string    `json:"id"`
		Name       string    `json:"name"`
		Platform   string    `json:"platform"`
		CreatedAt  time.Time `json:"created_at"`
		LastSeenAt time.Time `json:"last_seen_at"`
		Current    bool      `json:"current"`
	}
	out := make([]devJSON, 0, len(ds))
	for _, d := range ds {
		out = append(out, devJSON{d.ID, d.Name, d.Platform, time.Unix(d.CreatedAt, 0).UTC(), time.Unix(d.LastSeenAt, 0).UTC(), d.ID == p.DeviceID})
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) deleteDevice(w http.ResponseWriter, r *http.Request, p principal) {
	id := r.PathValue("id")
	if err := s.Store.DeleteDevice(r.Context(), p.User.ID, id); err != nil {
		s.fail(w, r, err)
		return
	}
	s.Hub.Disconnect(id)
	s.Store.Audit(r.Context(), p.User.ID, p.DeviceID, "device.revoked", s.clientIP(r))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) setPush(w http.ResponseWriter, r *http.Request, p principal) {
	var req struct {
		Provider string `json:"provider"`
		Token    string `json:"token"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	if req.Provider != "fcm" || req.Token == "" || len(req.Token) > 4096 || strings.ContainsAny(req.Token, " \r\n\x00") {
		badRequest(w, `provider must be "fcm" and token a valid registration token`)
		return
	}
	if err := s.Store.SetPush(r.Context(), p.DeviceID, req.Provider, req.Token); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) clearPush(w http.ResponseWriter, r *http.Request, p principal) {
	if err := s.Store.SetPush(r.Context(), p.DeviceID, "", ""); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) discover(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	if !validEmail(strings.TrimSpace(req.Email)) {
		badRequest(w, "email is invalid")
		return
	}
	res, err := s.Discover.Discover(r.Context(), strings.TrimSpace(req.Email))
	if errors.Is(err, discover.ErrNotFound) || err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "discovery_failed", "no server settings found for this address")
		return
	}
	writeJSON(w, http.StatusOK, res.Settings)
}

// ---- accounts ----

func (s *Server) accounts(w http.ResponseWriter, r *http.Request, p principal) {
	accts, err := s.Store.ListAccounts(r.Context(), p.User.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	out := make([]accountJSON, 0, len(accts))
	for _, a := range accts {
		out = append(out, toAccountJSON(a))
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) addAccount(w http.ResponseWriter, r *http.Request, p principal) {
	var req credsReq
	if !decode(w, r, maxBody, &req) {
		return
	}
	if msg := req.validate(); msg != "" {
		badRequest(w, msg)
		return
	}
	if !s.userAuth.allow(strings.ToLower(req.Email)) {
		tooMany(w)
		return
	}
	accts, err := s.Store.ListAccounts(r.Context(), p.User.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	if len(accts) >= maxAccountsPerUser {
		badRequest(w, "too many accounts")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
	defer cancel()
	set, username, err := s.resolve(ctx, req)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	a, err := s.verify(ctx, p.User.ID, req, set, username)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	if err := s.seal(ctx, &a, req.Password); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	if a, err = s.Store.SaveAccount(ctx, a); err != nil {
		s.writeAPIErr(w, err)
		return
	}
	s.Pool.Drop(a.ID)
	s.Store.Audit(ctx, p.User.ID, p.DeviceID, "account.added", s.clientIP(r))
	go s.Watch.Reconcile(context.WithoutCancel(r.Context()))
	writeJSON(w, http.StatusOK, toAccountJSON(a))
}

func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request, p principal) {
	accts, err := s.Store.ListAccounts(r.Context(), p.User.ID)
	if err != nil {
		s.writeAPIErr(w, err)
		return
	}
	if len(accts) <= 1 {
		badRequest(w, "you cannot remove your only account; sign out instead")
		return
	}
	id := r.PathValue("aid")
	if err := s.Store.DeleteAccount(r.Context(), p.User.ID, id); err != nil {
		s.fail(w, r, err)
		return
	}
	s.Pool.Drop(id)
	s.Store.Audit(r.Context(), p.User.ID, p.DeviceID, "account.removed", s.clientIP(r))
	go s.Watch.Reconcile(context.WithoutCancel(r.Context()))
	w.WriteHeader(http.StatusNoContent)
}
