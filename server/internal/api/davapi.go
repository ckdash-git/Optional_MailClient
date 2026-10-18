package api

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/dav"
)

// withDAV opens a DAV session for the account. ponytail: discovery (2-3 PROPFINDs) runs
// per request; cache home-set paths per account if calendar views feel slow.
func (s *Server) withDAV(w http.ResponseWriter, r *http.Request, p principal, fn func(ctx context.Context, d *dav.Session) error) {
	a, cr, ok := s.account(w, r, p)
	if !ok {
		return
	}
	if a.Settings.CalDAVURL == "" && a.Settings.CardDAVURL == "" {
		s.fail(w, r, dav.ErrNotConfigured)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()
	sess, err := dav.Open(ctx, s.HTTP, a, cr.Username, cr.Password)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if err := fn(ctx, sess); err != nil {
		s.fail(w, r, err)
	}
}

func (s *Server) calendars(w http.ResponseWriter, r *http.Request, p principal) {
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		c, err := d.Calendars(ctx)
		if err == nil {
			writeJSON(w, http.StatusOK, c)
		}
		return err
	})
}

func (s *Server) events(w http.ResponseWriter, r *http.Request, p principal) {
	q := r.URL.Query()
	from, err1 := time.Parse(time.RFC3339, q.Get("from"))
	to, err2 := time.Parse(time.RFC3339, q.Get("to"))
	if err1 != nil || err2 != nil || !to.After(from) || to.Sub(from) > 366*24*time.Hour {
		badRequest(w, "from and to must be RFC 3339 times, to after from, at most 366 days apart")
		return
	}
	cal := q.Get("calendar")
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		ev, err := d.Events(ctx, cal, from, to)
		if err == nil {
			writeJSON(w, http.StatusOK, ev)
		}
		return err
	})
}

func (s *Server) putEvent(w http.ResponseWriter, r *http.Request, p principal) {
	var in dav.EventInput
	if !decode(w, r, maxBody, &in) {
		return
	}
	in.Summary = strings.TrimSpace(in.Summary)
	switch {
	case in.ID == "" && in.Calendar == "":
		badRequest(w, "calendar is required to create an event")
		return
	case in.Summary == "" || len(in.Summary) > 1000 || len(in.Location) > 1000 || len(in.Description) > 20000:
		badRequest(w, "summary is required; summary/location/description are too long")
		return
	case in.Start.IsZero() || !in.End.After(in.Start) || in.End.Sub(in.Start) > 366*24*time.Hour:
		badRequest(w, "end must be after start")
		return
	}
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		ev, err := d.PutEvent(ctx, in)
		if err == nil {
			writeJSON(w, http.StatusOK, ev)
		}
		return err
	})
}

func (s *Server) deleteEvent(w http.ResponseWriter, r *http.Request, p principal) {
	q := r.URL.Query()
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		err := d.DeleteEvent(ctx, q.Get("id"), q.Get("etag"))
		if err == nil {
			w.WriteHeader(http.StatusNoContent)
		}
		return err
	})
}

func (s *Server) addressBooks(w http.ResponseWriter, r *http.Request, p principal) {
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		b, err := d.AddressBooks(ctx)
		if err == nil {
			writeJSON(w, http.StatusOK, b)
		}
		return err
	})
}

func (s *Server) contacts(w http.ResponseWriter, r *http.Request, p principal) {
	book := r.URL.Query().Get("addressbook")
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		c, err := d.Contacts(ctx, book)
		if err == nil {
			writeJSON(w, http.StatusOK, c)
		}
		return err
	})
}

func (s *Server) putContact(w http.ResponseWriter, r *http.Request, p principal) {
	var in dav.ContactInput
	if !decode(w, r, maxBody, &in) {
		return
	}
	in.FullName = strings.TrimSpace(in.FullName)
	switch {
	case in.ID == "" && in.AddressBook == "":
		badRequest(w, "addressbook is required to create a contact")
		return
	case in.FullName == "" || len(in.FullName) > 500 || len(in.Note) > 20000 || len(in.Org) > 500 || len(in.Title) > 500:
		badRequest(w, "full_name is required; fields are too long")
		return
	case len(in.Emails) > 20 || len(in.Phones) > 20:
		badRequest(w, "at most 20 emails and 20 phones")
		return
	}
	for _, l := range [][]dav.Typed{in.Emails, in.Phones} {
		for _, t := range l {
			if len(t.Value) > 320 || len(t.Type) > 40 || strings.ContainsAny(t.Value+t.Type, "\r\n\x00") {
				badRequest(w, "invalid email or phone")
				return
			}
		}
	}
	for _, e := range in.Emails {
		if e.Value != "" && !validEmail(e.Value) {
			badRequest(w, "invalid email address")
			return
		}
	}
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		c, err := d.PutContact(ctx, in)
		if err == nil {
			writeJSON(w, http.StatusOK, c)
		}
		return err
	})
}

func (s *Server) deleteContact(w http.ResponseWriter, r *http.Request, p principal) {
	q := r.URL.Query()
	s.withDAV(w, r, p, func(ctx context.Context, d *dav.Session) error {
		err := d.DeleteContact(ctx, q.Get("id"), q.Get("etag"))
		if err == nil {
			w.WriteHeader(http.StatusNoContent)
		}
		return err
	})
}
