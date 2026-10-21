package api

import (
	"context"
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"time"

	mailx "github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

// account loads the caller's account and its credentials. Accounts are looked up by
// (user, id), so an id belonging to another user is simply not found.
func (s *Server) account(w http.ResponseWriter, r *http.Request, p principal) (store.Account, mailx.Creds, bool) {
	a, err := s.Store.GetAccount(r.Context(), p.User.ID, r.PathValue("aid"))
	if err != nil {
		s.fail(w, r, err)
		return a, mailx.Creds{}, false
	}
	pw, err := s.Vault.Open(a.SecretKID, a.Secret, []byte(a.ID))
	if err != nil {
		s.writeAPIErr(w, err)
		return a, mailx.Creds{}, false
	}
	return a, mailx.Creds{Username: a.Username, Password: string(pw)}, true
}

func (s *Server) withBox(w http.ResponseWriter, r *http.Request, p principal, fn func(ctx context.Context, b mailx.Mailbox) error) {
	a, cr, ok := s.account(w, r, p)
	if !ok {
		return
	}
	if err := s.Pool.With(r.Context(), a, cr, func(b mailx.Mailbox) error { return fn(r.Context(), b) }); err != nil {
		s.fail(w, r, err)
	}
}

// folderParam returns the folder query parameter. Names are passed to the IMAP library,
// which quotes them; control characters are refused outright.
func folderParam(w http.ResponseWriter, r *http.Request) (string, bool) {
	f := r.URL.Query().Get("folder")
	if f == "" || len(f) > 1000 || strings.ContainsAny(f, "\r\n\x00") {
		badRequest(w, "folder is required")
		return "", false
	}
	return f, true
}

func validID(id string) bool {
	if id == "" || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if (c < '0' || c > '9') && c != '.' {
			return false
		}
	}
	return true
}

func (s *Server) folders(w http.ResponseWriter, r *http.Request, p principal) {
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		f, err := b.Folders(ctx)
		if err == nil {
			writeJSON(w, http.StatusOK, f)
		}
		return err
	})
}

func (s *Server) listMessages(w http.ResponseWriter, r *http.Request, p principal) {
	folder, ok := folderParam(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	limit := 50
	if v := q.Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 100 {
			badRequest(w, "limit must be 1..100")
			return
		}
		limit = n
	}
	before := q.Get("before")
	if before != "" && !validID(before) {
		badRequest(w, "before is invalid")
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		msgs, next, err := b.List(ctx, folder, before, limit)
		if err != nil {
			return err
		}
		resp := map[string]any{"messages": msgs}
		if next != "" {
			resp["next_before"] = next
		}
		writeJSON(w, http.StatusOK, resp)
		return nil
	})
}

func (s *Server) msgTarget(w http.ResponseWriter, r *http.Request) (folder, id string, ok bool) {
	if folder, ok = folderParam(w, r); !ok {
		return
	}
	if id = r.PathValue("id"); !validID(id) {
		writeErr(w, http.StatusNotFound, "not_found", "not found")
		return "", "", false
	}
	return folder, id, true
}

func (s *Server) getMessage(w http.ResponseWriter, r *http.Request, p principal) {
	folder, id, ok := s.msgTarget(w, r)
	if !ok {
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		m, err := b.Get(ctx, folder, id)
		if err == nil {
			writeJSON(w, http.StatusOK, m)
		}
		return err
	})
}

func (s *Server) attachment(w http.ResponseWriter, r *http.Request, p principal) {
	folder, id, ok := s.msgTarget(w, r)
	if !ok {
		return
	}
	idx, err := strconv.Atoi(r.PathValue("index"))
	if err != nil || idx < 0 || idx > 1000 {
		writeErr(w, http.StatusNotFound, "not_found", "not found")
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		return b.Attachment(ctx, folder, id, idx, func(a mailx.Attachment) io.Writer {
			// Always octet-stream + attachment: an HTML or SVG attachment must never render
			// in a browser under the API's origin.
			h := w.Header()
			h.Set("Content-Type", "application/octet-stream")
			h.Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": a.Filename}))
			w.WriteHeader(http.StatusOK)
			return w
		})
	})
}

func (s *Server) setFlags(w http.ResponseWriter, r *http.Request, p principal) {
	folder, id, ok := s.msgTarget(w, r)
	if !ok {
		return
	}
	var req struct {
		Seen    *bool `json:"seen"`
		Flagged *bool `json:"flagged"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	if req.Seen == nil && req.Flagged == nil {
		badRequest(w, "nothing to change")
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		err := b.SetFlags(ctx, folder, id, req.Seen, req.Flagged)
		if err == nil {
			w.WriteHeader(http.StatusNoContent)
		}
		return err
	})
}

func (s *Server) move(w http.ResponseWriter, r *http.Request, p principal) {
	folder, id, ok := s.msgTarget(w, r)
	if !ok {
		return
	}
	var req struct {
		To string `json:"to"`
	}
	if !decode(w, r, maxBody, &req) {
		return
	}
	if req.To == "" || len(req.To) > 1000 || strings.ContainsAny(req.To, "\r\n\x00") || req.To == folder {
		badRequest(w, "to must be another folder")
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		err := b.Move(ctx, folder, id, req.To)
		if err == nil {
			w.WriteHeader(http.StatusNoContent)
		}
		return err
	})
}

func (s *Server) deleteMessage(w http.ResponseWriter, r *http.Request, p principal) {
	folder, id, ok := s.msgTarget(w, r)
	if !ok {
		return
	}
	s.withBox(w, r, p, func(ctx context.Context, b mailx.Mailbox) error {
		err := b.Delete(ctx, folder, id)
		if err == nil {
			w.WriteHeader(http.StatusNoContent)
		}
		return err
	})
}

const (
	maxSendBody        = 36 << 20 // 25 MiB of attachments after base64 and JSON overhead
	maxAttachmentBytes = 25 << 20
	maxRecipients      = 100
)

func cleanAddrs(l []model.Address) ([]model.Address, string) {
	out := make([]model.Address, 0, len(l))
	for _, a := range l {
		a.Email = strings.TrimSpace(a.Email)
		if !validEmail(a.Email) {
			return nil, "invalid recipient address"
		}
		if len(a.Name) > 200 || strings.ContainsAny(a.Name, "\r\n\x00") {
			return nil, "invalid recipient name"
		}
		out = append(out, a)
	}
	return out, ""
}

func (s *Server) send(w http.ResponseWriter, r *http.Request, p principal) {
	var o mailx.Outgoing
	if !decode(w, r, maxSendBody, &o) {
		return
	}
	var msg string
	for _, l := range []*[]model.Address{&o.To, &o.Cc, &o.Bcc} {
		if *l, msg = cleanAddrs(*l); msg != "" {
			badRequest(w, msg)
			return
		}
	}
	n := len(o.To) + len(o.Cc) + len(o.Bcc)
	total := 0
	for _, a := range o.Attachments {
		total += len(a.Data)
		if a.Filename == "" || len(a.Filename) > 255 || strings.ContainsAny(a.Filename, "\r\n\x00/\\") {
			badRequest(w, "invalid attachment filename")
			return
		}
	}
	switch {
	case n == 0 || n > maxRecipients:
		badRequest(w, "between 1 and 100 recipients are required")
		return
	case len(o.Subject) > 998 || strings.ContainsAny(o.Subject, "\r\n\x00"):
		badRequest(w, "invalid subject")
		return
	case len(o.Attachments) > 20 || total > maxAttachmentBytes:
		writeErr(w, http.StatusRequestEntityTooLarge, "too_large", "attachments are limited to 20 files and 25 MiB")
		return
	case len(o.InReplyTo) > 998 || len(o.References) > 100:
		badRequest(w, "invalid reply headers")
		return
	}
	a, cr, ok := s.account(w, r, p)
	if !ok {
		return
	}
	raw, id, err := mailx.Build(model.Address{Name: a.DisplayName, Email: a.Email}, o, time.Now())
	if err != nil {
		badRequest(w, "could not build the message")
		return
	}
	rcpt := make([]string, 0, n)
	for _, l := range [][]model.Address{o.To, o.Cc, o.Bcc} {
		for _, x := range l {
			rcpt = append(rcpt, x.Email)
		}
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()
	if err := mailx.Submit(ctx, s.Guard, a.Settings.Outgoing, cr, a.Email, rcpt, raw); err != nil {
		s.fail(w, r, err)
		return
	}
	// The mail is sent; failing to file a copy must not make the client retry and send twice.
	if err := s.Pool.With(ctx, a, cr, func(b mailx.Mailbox) error { return b.SaveSent(ctx, raw) }); err != nil {
		s.Log.Warn("send: could not save to Sent", "account", a.ID, "err", err)
	}
	s.Store.Audit(ctx, p.User.ID, p.DeviceID, "mail.sent", s.clientIP(r))
	writeJSON(w, http.StatusAccepted, map[string]string{"message_id": id})
}
