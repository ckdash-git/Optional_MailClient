// Package dav reads and writes calendars (CalDAV) and contacts (CardDAV).
package dav

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"path"
	"sort"
	"strings"
	"time"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-vcard"
	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/emersion/go-webdav/carddav"

	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

var (
	ErrNotConfigured = errors.New("this account has no calendar/contacts server")
	ErrConflict      = errors.New("changed on the server since it was read")
	ErrNotFound      = errors.New("not found")
	ErrBadID         = errors.New("invalid id")
)

// cond carries If-Match / If-None-Match into go-webdav, whose PUT does not set them, and
// carries the response status back out.
type cond struct {
	etag   string // "" = unconditional, "*" = must not exist yet
	status int
}

type condKey struct{}

type condClient struct{ next webdav.HTTPClient }

func (c condClient) Do(r *http.Request) (*http.Response, error) {
	cd, _ := r.Context().Value(condKey{}).(*cond)
	if cd != nil && (r.Method == http.MethodPut || r.Method == http.MethodDelete) {
		if cd.etag == "*" {
			r.Header.Set("If-None-Match", "*")
		} else if cd.etag != "" {
			r.Header.Set("If-Match", quoteETag(cd.etag))
		}
	}
	resp, err := c.next.Do(r)
	if cd != nil && resp != nil {
		cd.status = resp.StatusCode
	}
	return resp, err
}

// quoteETag restores the quotes go-webdav strips from ETags; If-Match needs them.
func quoteETag(e string) string {
	if strings.HasPrefix(e, `"`) || strings.HasPrefix(e, `W/"`) {
		return e
	}
	return `"` + e + `"`
}

func conditional(ctx context.Context, etag string) (context.Context, *cond) {
	cd := &cond{etag: etag}
	return context.WithValue(ctx, condKey{}, cd), cd
}

func classify(err error, cd *cond) error {
	if cd != nil && cd.status == http.StatusPreconditionFailed {
		return ErrConflict
	}
	if cd != nil && cd.status == http.StatusNotFound {
		return ErrNotFound
	}
	return err
}

// Session is an authenticated connection to one account's DAV servers.
type Session struct {
	http     webdav.HTTPClient
	cal      *caldav.Client
	card     *carddav.Client
	calHome  string
	cardHome string
}

// Open discovers the calendar and/or address book home sets. A missing URL leaves that
// half unset.
func Open(ctx context.Context, hc *http.Client, a store.Account, user, pass string) (*Session, error) {
	s := &Session{http: condClient{webdav.HTTPClientWithBasicAuth(hc, user, pass)}}
	if u := a.Settings.CalDAVURL; u != "" {
		ep, err := s.principalEndpoint(ctx, hc, u, "caldav")
		if err != nil {
			return nil, fmt.Errorf("caldav: %w", err)
		}
		if s.cal, err = caldav.NewClient(s.http, ep.endpoint); err != nil {
			return nil, err
		}
		if s.calHome, err = s.cal.FindCalendarHomeSet(ctx, ep.principal); err != nil {
			return nil, fmt.Errorf("caldav: home set: %w", err)
		}
	}
	if u := a.Settings.CardDAVURL; u != "" {
		ep, err := s.principalEndpoint(ctx, hc, u, "carddav")
		if err != nil {
			return nil, fmt.Errorf("carddav: %w", err)
		}
		if s.card, err = carddav.NewClient(s.http, ep.endpoint); err != nil {
			return nil, err
		}
		if s.cardHome, err = s.card.FindAddressBookHomeSet(ctx, ep.principal); err != nil {
			return nil, fmt.Errorf("carddav: home set: %w", err)
		}
	}
	return s, nil
}

type principal struct{ endpoint, principal string }

// principalEndpoint finds the current-user-principal at the configured URL, falling back
// to RFC 6764 /.well-known/<service>. The well-known redirect is followed by hand because
// net/http turns a redirected PROPFIND into a GET.
func (s *Session) principalEndpoint(ctx context.Context, hc *http.Client, raw, service string) (principal, error) {
	try := func(ep string) (principal, error) {
		c, err := webdav.NewClient(s.http, ep)
		if err != nil {
			return principal{}, err
		}
		p, err := c.FindCurrentUserPrincipal(ctx)
		return principal{ep, p}, err
	}
	p, err := try(raw)
	if err == nil {
		return p, nil
	}
	base, perr := url.Parse(raw)
	if perr != nil {
		return principal{}, err
	}
	wk := base.ResolveReference(&url.URL{Path: "/.well-known/" + service})
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, wk.String(), nil)
	noFollow := *hc
	noFollow.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, rerr := noFollow.Do(req)
	if rerr != nil {
		return principal{}, err
	}
	resp.Body.Close()
	loc, lerr := resp.Location()
	if lerr != nil || loc.Scheme != "https" {
		return principal{}, err
	}
	return try(loc.String())
}

// within rejects ids that are not plain paths under the home set, so a client cannot
// point the master's credentials at another host or collection.
func within(id, home string) (string, error) {
	if home == "" {
		return "", ErrNotConfigured
	}
	if !strings.HasPrefix(id, "/") || strings.Contains(id, "://") || strings.Contains(id, "\\") {
		return "", ErrBadID
	}
	clean := path.Clean(id)
	if strings.HasSuffix(id, "/") {
		clean += "/"
	}
	h := strings.TrimSuffix(home, "/") + "/"
	if !strings.HasPrefix(clean, h) || clean != id {
		return "", ErrBadID
	}
	return clean, nil
}

// ---- calendar ----

type CalendarInfo struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
}

type Event struct {
	ID          string    `json:"id"`
	Calendar    string    `json:"calendar"`
	ETag        string    `json:"etag"`
	UID         string    `json:"uid"`
	Summary     string    `json:"summary"`
	Description string    `json:"description"`
	Location    string    `json:"location"`
	Start       time.Time `json:"start"`
	End         time.Time `json:"end"`
	AllDay      bool      `json:"all_day"`
	Recurrence  string    `json:"recurrence"`
}

type EventInput struct {
	Calendar    string    `json:"calendar"`
	ID          string    `json:"id"`
	ETag        string    `json:"etag"`
	Summary     string    `json:"summary"`
	Description string    `json:"description"`
	Location    string    `json:"location"`
	Start       time.Time `json:"start"`
	End         time.Time `json:"end"`
	AllDay      bool      `json:"all_day"`
}

func (s *Session) Calendars(ctx context.Context) ([]CalendarInfo, error) {
	if s.cal == nil {
		return nil, ErrNotConfigured
	}
	cals, err := s.cal.FindCalendars(ctx, s.calHome)
	if err != nil {
		return nil, err
	}
	out := []CalendarInfo{}
	for _, c := range cals {
		if len(c.SupportedComponentSet) > 0 && !contains(c.SupportedComponentSet, "VEVENT") {
			continue // task-only lists
		}
		name := c.Name
		if name == "" {
			name = path.Base(strings.TrimSuffix(c.Path, "/"))
		}
		out = append(out, CalendarInfo{ID: c.Path, Name: name})
	}
	return out, nil
}

func contains(l []string, s string) bool {
	for _, x := range l {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

const maxInstances = 500

// Events returns event instances overlapping [from, to). Recurring events are expanded
// here because server-side expansion support varies. ponytail: overridden instances
// (RECURRENCE-ID) are shown as the series rule says; add override handling with
// recurring-event editing (F27).
func (s *Session) Events(ctx context.Context, calendar string, from, to time.Time) ([]Event, error) {
	if s.cal == nil {
		return nil, ErrNotConfigured
	}
	calendar, err := within(calendar, s.calHome)
	if err != nil {
		return nil, err
	}
	objs, err := s.cal.QueryCalendar(ctx, calendar, &caldav.CalendarQuery{
		CompRequest: caldav.CalendarCompRequest{Name: "VCALENDAR", AllProps: true, AllComps: true},
		CompFilter: caldav.CompFilter{Name: "VCALENDAR", Comps: []caldav.CompFilter{{
			Name: "VEVENT", Start: from, End: to,
		}}},
	})
	if err != nil {
		return nil, err
	}
	out := []Event{}
	for _, o := range objs {
		if o.Data == nil {
			continue
		}
		for _, ev := range o.Data.Events() {
			if ev.Props.Get(ical.PropRecurrenceID) != nil {
				continue
			}
			base, ok := toEvent(o, ev)
			if !ok {
				continue
			}
			rs, err := ev.RecurrenceSet(time.UTC)
			if err != nil || rs == nil {
				if base.End.After(from) && base.Start.Before(to) {
					out = append(out, base)
				}
				continue
			}
			dur := base.End.Sub(base.Start)
			for _, st := range rs.Between(from.Add(-dur), to, true) {
				inst := base
				inst.Start, inst.End = st.UTC(), st.UTC().Add(dur)
				if inst.End.After(from) && inst.Start.Before(to) && len(out) < maxInstances {
					out = append(out, inst)
				}
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Start.Before(out[j].Start) })
	return out, nil
}

func toEvent(o caldav.CalendarObject, ev ical.Event) (Event, bool) {
	start, err := ev.DateTimeStart(time.UTC)
	if err != nil {
		return Event{}, false
	}
	allDay := false
	if p := ev.Props.Get(ical.PropDateTimeStart); p != nil && p.ValueType() == ical.ValueDate {
		allDay = true
	}
	end, err := ev.DateTimeEnd(time.UTC)
	if err != nil || end.IsZero() || !end.After(start) {
		end = start.Add(time.Hour)
		if allDay {
			end = start.AddDate(0, 0, 1)
		}
	}
	e := Event{ID: o.Path, Calendar: path.Dir(o.Path) + "/", ETag: o.ETag, Start: start.UTC(), End: end.UTC(), AllDay: allDay}
	e.UID, _ = ev.Props.Text(ical.PropUID)
	e.Summary, _ = ev.Props.Text(ical.PropSummary)
	e.Description, _ = ev.Props.Text(ical.PropDescription)
	e.Location, _ = ev.Props.Text(ical.PropLocation)
	if p := ev.Props.Get(ical.PropRecurrenceRule); p != nil {
		e.Recurrence = p.Value
	}
	return e, true
}

// PutEvent creates (no ID) or updates an event. Updates edit the stored object in place,
// so properties this API does not model (alarms, attendees, the RRULE) survive.
func (s *Session) PutEvent(ctx context.Context, in EventInput) (Event, error) {
	if s.cal == nil {
		return Event{}, ErrNotConfigured
	}
	var cal *ical.Calendar
	var objPath, etag string
	if in.ID == "" {
		calPath, err := within(in.Calendar, s.calHome)
		if err != nil {
			return Event{}, err
		}
		uid := store.NewID()
		objPath, etag = strings.TrimSuffix(calPath, "/")+"/"+uid+".ics", "*"
		cal = ical.NewCalendar()
		cal.Props.SetText(ical.PropVersion, "2.0")
		cal.Props.SetText(ical.PropProductID, "-//Optional Mail//Master//EN")
		ev := ical.NewEvent()
		ev.Props.SetText(ical.PropUID, uid)
		cal.Children = append(cal.Children, ev.Component)
	} else {
		var err error
		if objPath, err = within(in.ID, s.calHome); err != nil {
			return Event{}, err
		}
		if in.ETag == "" {
			return Event{}, fmt.Errorf("%w: etag is required to update", ErrBadID)
		}
		obj, err := s.cal.GetCalendarObject(ctx, objPath)
		if err != nil {
			return Event{}, ErrNotFound
		}
		cal, etag = obj.Data, in.ETag
	}
	var ev *ical.Component
	for _, c := range cal.Children {
		if c.Name == ical.CompEvent && c.Props.Get(ical.PropRecurrenceID) == nil {
			ev = c
			break
		}
	}
	if ev == nil {
		return Event{}, ErrNotFound
	}
	ev.Props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
	ev.Props.SetText(ical.PropSummary, in.Summary)
	setOrDel(ev.Props, ical.PropDescription, in.Description)
	setOrDel(ev.Props, ical.PropLocation, in.Location)
	ev.Props.Del(ical.PropDuration)
	if in.AllDay {
		ev.Props.SetDate(ical.PropDateTimeStart, in.Start)
		ev.Props.SetDate(ical.PropDateTimeEnd, in.End)
	} else {
		ev.Props.SetDateTime(ical.PropDateTimeStart, in.Start.UTC())
		ev.Props.SetDateTime(ical.PropDateTimeEnd, in.End.UTC())
	}
	cctx, cd := conditional(ctx, etag)
	obj, err := s.cal.PutCalendarObject(cctx, objPath, cal)
	if err != nil {
		return Event{}, classify(err, cd)
	}
	if obj.Data == nil {
		obj.Data = cal
	}
	out, _ := toEvent(*obj, ical.Event{Component: ev})
	if out.ETag == "" {
		// Some servers send no ETag on PUT; read it back so the next update can be conditional.
		if fi, err := s.cal.Stat(ctx, objPath); err == nil {
			out.ETag = fi.ETag
		}
	}
	return out, nil
}

func setOrDel(p ical.Props, name, v string) {
	if v == "" {
		p.Del(name)
		return
	}
	p.SetText(name, v)
}

func (s *Session) DeleteEvent(ctx context.Context, id, etag string) error {
	if s.cal == nil {
		return ErrNotConfigured
	}
	return s.remove(ctx, s.cal.Client, id, etag, s.calHome)
}

func (s *Session) remove(ctx context.Context, c *webdav.Client, id, etag, home string) error {
	p, err := within(id, home)
	if err != nil {
		return err
	}
	if etag == "" || strings.HasSuffix(p, "/") {
		return ErrBadID // never delete a whole collection, never delete blind
	}
	cctx, cd := conditional(ctx, etag)
	return classify(c.RemoveAll(cctx, p), cd)
}

// ---- contacts ----

type AddressBookInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Typed struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type Contact struct {
	ID          string  `json:"id"`
	AddressBook string  `json:"addressbook"`
	ETag        string  `json:"etag"`
	UID         string  `json:"uid"`
	FullName    string  `json:"full_name"`
	Emails      []Typed `json:"emails"`
	Phones      []Typed `json:"phones"`
	Org         string  `json:"org"`
	Title       string  `json:"title"`
	Note        string  `json:"note"`
}

type ContactInput struct {
	AddressBook string  `json:"addressbook"`
	ID          string  `json:"id"`
	ETag        string  `json:"etag"`
	FullName    string  `json:"full_name"`
	Emails      []Typed `json:"emails"`
	Phones      []Typed `json:"phones"`
	Org         string  `json:"org"`
	Title       string  `json:"title"`
	Note        string  `json:"note"`
}

func (s *Session) AddressBooks(ctx context.Context) ([]AddressBookInfo, error) {
	if s.card == nil {
		return nil, ErrNotConfigured
	}
	abs, err := s.card.FindAddressBooks(ctx, s.cardHome)
	if err != nil {
		return nil, err
	}
	out := []AddressBookInfo{}
	for _, a := range abs {
		name := a.Name
		if name == "" {
			name = path.Base(strings.TrimSuffix(a.Path, "/"))
		}
		out = append(out, AddressBookInfo{ID: a.Path, Name: name})
	}
	return out, nil
}

func (s *Session) Contacts(ctx context.Context, book string) ([]Contact, error) {
	if s.card == nil {
		return nil, ErrNotConfigured
	}
	book, err := within(book, s.cardHome)
	if err != nil {
		return nil, err
	}
	// List + multiget rather than an addressbook-query: servers disagree on what an
	// empty query filter matches.
	fis, err := s.card.ReadDir(ctx, book, false)
	if err != nil {
		return nil, err
	}
	var paths []string
	for _, fi := range fis {
		if !fi.IsDir {
			paths = append(paths, fi.Path)
		}
	}
	if len(paths) == 0 {
		return []Contact{}, nil
	}
	objs, err := s.card.MultiGetAddressBook(ctx, book, &carddav.AddressBookMultiGet{Paths: paths, DataRequest: carddav.AddressDataRequest{AllProp: true}})
	if err != nil {
		return nil, err
	}
	out := make([]Contact, 0, len(objs))
	for _, o := range objs {
		out = append(out, toContact(o))
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].FullName) < strings.ToLower(out[j].FullName) })
	return out, nil
}

func typed(fs []*vcard.Field) []Typed {
	out := []Typed{}
	for _, f := range fs {
		out = append(out, Typed{Type: strings.ToLower(f.Params.Get(vcard.ParamType)), Value: f.Value})
	}
	return out
}

func toContact(o carddav.AddressObject) Contact {
	c := o.Card
	ct := Contact{ID: o.Path, AddressBook: path.Dir(o.Path) + "/", ETag: o.ETag,
		UID: c.Value(vcard.FieldUID), FullName: c.PreferredValue(vcard.FieldFormattedName),
		Emails: typed(c[vcard.FieldEmail]), Phones: typed(c[vcard.FieldTelephone]),
		Org: c.Value(vcard.FieldOrganization), Title: c.Value(vcard.FieldTitle), Note: c.Value(vcard.FieldNote)}
	if ct.FullName == "" && len(ct.Emails) > 0 {
		ct.FullName = ct.Emails[0].Value
	}
	return ct
}

func setTyped(c vcard.Card, key string, l []Typed) {
	delete(c, key)
	for _, t := range l {
		if t.Value == "" {
			continue
		}
		f := &vcard.Field{Value: t.Value, Params: vcard.Params{}}
		if t.Type != "" {
			f.Params.Set(vcard.ParamType, t.Type)
		}
		c.Add(key, f)
	}
}

// PutContact creates or updates a contact, editing an existing card in place so fields
// this API does not model (photo, addresses, birthdays) survive.
func (s *Session) PutContact(ctx context.Context, in ContactInput) (Contact, error) {
	if s.card == nil {
		return Contact{}, ErrNotConfigured
	}
	var card vcard.Card
	var objPath, etag string
	if in.ID == "" {
		book, err := within(in.AddressBook, s.cardHome)
		if err != nil {
			return Contact{}, err
		}
		uid := store.NewID()
		objPath, etag = strings.TrimSuffix(book, "/")+"/"+uid+".vcf", "*"
		card = vcard.Card{}
		card.SetValue(vcard.FieldVersion, "3.0")
		card.SetValue(vcard.FieldUID, uid)
	} else {
		var err error
		if objPath, err = within(in.ID, s.cardHome); err != nil {
			return Contact{}, err
		}
		if in.ETag == "" {
			return Contact{}, fmt.Errorf("%w: etag is required to update", ErrBadID)
		}
		obj, err := s.card.GetAddressObject(ctx, objPath)
		if err != nil {
			return Contact{}, ErrNotFound
		}
		card, etag = obj.Card, in.ETag
	}
	card.SetValue(vcard.FieldFormattedName, in.FullName)
	if card.Get(vcard.FieldName) == nil {
		card.SetName(&vcard.Name{FamilyName: in.FullName})
	}
	setTyped(card, vcard.FieldEmail, in.Emails)
	setTyped(card, vcard.FieldTelephone, in.Phones)
	for k, v := range map[string]string{vcard.FieldOrganization: in.Org, vcard.FieldTitle: in.Title, vcard.FieldNote: in.Note} {
		if v == "" {
			delete(card, k)
		} else {
			card.SetValue(k, v)
		}
	}
	cctx, cd := conditional(ctx, etag)
	obj, err := s.card.PutAddressObject(cctx, objPath, card)
	if err != nil {
		return Contact{}, classify(err, cd)
	}
	obj.Card = card
	out := toContact(*obj)
	if out.ETag == "" {
		if fi, err := s.card.Stat(ctx, objPath); err == nil {
			out.ETag = fi.ETag
		}
	}
	return out, nil
}

func (s *Session) DeleteContact(ctx context.Context, id, etag string) error {
	if s.card == nil {
		return ErrNotConfigured
	}
	return s.remove(ctx, s.card.Client, id, etag, s.cardHome)
}

// ---- change detection ----

// Digest fingerprints every object's path and ETag in all calendars ("calendar") or
// address books ("contacts"). One PROPFIND per collection; no object bodies.
func (s *Session) Digest(ctx context.Context, kind string) (string, error) {
	var c *webdav.Client
	var cols []string
	switch {
	case kind == "calendar" && s.cal != nil:
		c = s.cal.Client
		cals, err := s.Calendars(ctx)
		if err != nil {
			return "", err
		}
		for _, x := range cals {
			cols = append(cols, x.ID)
		}
	case kind == "contacts" && s.card != nil:
		c = s.card.Client
		abs, err := s.AddressBooks(ctx)
		if err != nil {
			return "", err
		}
		for _, x := range abs {
			cols = append(cols, x.ID)
		}
	default:
		return "", ErrNotConfigured
	}
	var lines []string
	for _, col := range cols {
		fis, err := c.ReadDir(ctx, col, false)
		if err != nil {
			return "", err
		}
		for _, fi := range fis {
			if !fi.IsDir {
				lines = append(lines, fi.Path+" "+fi.ETag)
			}
		}
	}
	sort.Strings(lines)
	h := sha256.Sum256([]byte(strings.Join(lines, "\n")))
	return hex.EncodeToString(h[:]), nil
}
