package dav

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/emersion/go-ical"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/testutil"
)

func TestCalendarAndContacts(t *testing.T) {
	ctx := context.Background()
	calSrv, cardSrv, hc := testutil.DAV(t)
	acct := store.Account{Settings: model.Settings{CalDAVURL: calSrv.URL + "/", CardDAVURL: cardSrv.URL + "/"}}
	s, err := Open(ctx, hc, acct, "alice", "pw")
	if err != nil {
		t.Fatal(err)
	}

	cals, err := s.Calendars(ctx)
	if err != nil || len(cals) != 1 || cals[0].ID != "/alice/cal/work/" || cals[0].Name != "Work" {
		t.Fatalf("calendars (VTODO lists hidden): %+v %v", cals, err)
	}
	d0, _ := s.Digest(ctx, "calendar")

	start := time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)
	ev, err := s.PutEvent(ctx, EventInput{Calendar: "/alice/cal/work/", Summary: "Standup", Location: "Room 1", Start: start, End: start.Add(15 * time.Minute)})
	if err != nil || ev.ETag == "" || ev.UID == "" || !strings.HasPrefix(ev.ID, "/alice/cal/work/") {
		t.Fatalf("create: %+v %v", ev, err)
	}
	if d1, _ := s.Digest(ctx, "calendar"); d1 == d0 {
		t.Fatal("digest must change after a write")
	}

	got, err := s.Events(ctx, "/alice/cal/work/", start.Add(-time.Hour), start.Add(time.Hour))
	if err != nil || len(got) != 1 || got[0].Summary != "Standup" || !got[0].Start.Equal(start) {
		t.Fatalf("events: %+v %v", got, err)
	}
	if got, _ := s.Events(ctx, "/alice/cal/work/", start.Add(24*time.Hour), start.Add(48*time.Hour)); len(got) != 0 {
		t.Fatalf("range filter: %+v", got)
	}

	upd, err := s.PutEvent(ctx, EventInput{ID: ev.ID, ETag: ev.ETag, Summary: "Daily standup", Start: start, End: start.Add(30 * time.Minute)})
	if err != nil || upd.Summary != "Daily standup" || upd.ETag == ev.ETag {
		t.Fatalf("update: %+v %v", upd, err)
	}
	if _, err := s.PutEvent(ctx, EventInput{ID: ev.ID, ETag: ev.ETag, Summary: "stale", Start: start, End: start.Add(time.Hour)}); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale etag must conflict, got %v", err)
	}

	// Path escapes and foreign hosts are refused before any request is made.
	for _, bad := range []string{"/cal/../alice/card/default/", "https://evil.example/alice/cal/work/", "/other/", "alice/cal/work/"} {
		if _, err := s.Events(ctx, bad, start, start.Add(time.Hour)); !errors.Is(err, ErrBadID) {
			t.Errorf("%q: want ErrBadID, got %v", bad, err)
		}
	}
	if err := s.DeleteEvent(ctx, "/alice/cal/work/", "x"); !errors.Is(err, ErrBadID) {
		t.Fatal("deleting a collection must be refused")
	}

	// A recurring event is expanded into instances inside the window.
	rec := ical.NewCalendar()
	rec.Props.SetText(ical.PropVersion, "2.0")
	rec.Props.SetText(ical.PropProductID, "-//t//t//EN")
	re := ical.NewEvent()
	re.Props.SetText(ical.PropUID, "r1")
	re.Props.SetDateTime(ical.PropDateTimeStamp, start)
	re.Props.SetDateTime(ical.PropDateTimeStart, start)
	re.Props.SetDateTime(ical.PropDateTimeEnd, start.Add(time.Hour))
	re.Props.SetText(ical.PropSummary, "Gym")
	re.Props.Set(&ical.Prop{Name: ical.PropRecurrenceRule, Value: "FREQ=DAILY;COUNT=5", Params: ical.Params{}})
	rec.Children = append(rec.Children, re.Component)
	if _, err := s.cal.PutCalendarObject(ctx, "/alice/cal/work/r1.ics", rec); err != nil {
		t.Fatal(err)
	}
	inst, err := s.Events(ctx, "/alice/cal/work/", start.Add(24*time.Hour), start.Add(72*time.Hour))
	gym := 0
	for _, e := range inst {
		if e.Summary == "Gym" && e.Recurrence == "FREQ=DAILY;COUNT=5" {
			gym++
		}
	}
	if err != nil || gym != 2 {
		t.Fatalf("recurrence expansion: %d instances, %+v %v", gym, inst, err)
	}

	if err := s.DeleteEvent(ctx, upd.ID, upd.ETag); err != nil {
		t.Fatal(err)
	}

	books, err := s.AddressBooks(ctx)
	if err != nil || len(books) != 1 {
		t.Fatalf("books: %+v %v", books, err)
	}
	c, err := s.PutContact(ctx, ContactInput{AddressBook: books[0].ID, FullName: "Ana Lima",
		Emails: []Typed{{Type: "work", Value: "ana@x.io"}}, Phones: []Typed{{Type: "cell", Value: "+15550100"}}, Org: "X"})
	if err != nil || c.ETag == "" {
		t.Fatalf("create contact: %+v %v", c, err)
	}
	list, err := s.Contacts(ctx, books[0].ID)
	if err != nil || len(list) != 1 || list[0].Emails[0].Value != "ana@x.io" || list[0].Emails[0].Type != "work" || list[0].Org != "X" {
		t.Fatalf("contacts: %+v %v", list, err)
	}
	c2, err := s.PutContact(ctx, ContactInput{ID: c.ID, ETag: c.ETag, FullName: "Ana L.", Emails: c.Emails})
	if err != nil || c2.FullName != "Ana L." || c2.Org != "" || len(c2.Phones) != 0 {
		t.Fatalf("update contact: %+v %v", c2, err)
	}
	if _, err := s.PutContact(ctx, ContactInput{ID: c.ID, ETag: c.ETag, FullName: "stale"}); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale contact etag: %v", err)
	}
	if err := s.DeleteContact(ctx, c2.ID, c2.ETag); err != nil {
		t.Fatal(err)
	}
	if list, _ := s.Contacts(ctx, books[0].ID); len(list) != 0 {
		t.Fatal("contact not deleted")
	}

	if _, err := Open(ctx, hc, acct, "alice", "wrong"); err == nil {
		t.Fatal("wrong password must fail discovery")
	}
}
