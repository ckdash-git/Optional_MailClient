package api

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/ckdash-git/optional_mailclient/server/internal/discover"
	"github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/push"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/testutil"
	"github.com/ckdash-git/optional_mailclient/server/internal/vault"
	"github.com/ckdash-git/optional_mailclient/server/internal/watch"
)

type env struct {
	t     *testing.T
	srv   *httptest.Server
	st    *store.Store
	imap  model.Endpoint
	smtp  *testutil.SMTPBackend
	fcmMu sync.Mutex
	fcm   []string // request bodies received by the fake FCM endpoint
}

func setup(t *testing.T) *env {
	t.Helper()
	e := &env{t: t}
	e.imap = testutil.IMAP(t)
	var smtpEP model.Endpoint
	e.smtp, smtpEP = testutil.SMTP(t)
	cal, card, davClient := testutil.DAV(t)

	fcm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		e.fcmMu.Lock()
		e.fcm = append(e.fcm, string(b))
		e.fcmMu.Unlock()
		w.Write([]byte(`{"name":"projects/p/messages/1"}`))
	}))
	t.Cleanup(fcm.Close)

	var err error
	e.st, err = store.Open(filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { e.st.Close() })
	v, _ := vault.Parse("k1:" + base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32)))
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	guard := testutil.Loopback
	hub := &push.Hub{Store: e.st, Log: log, FCM: &push.FCM{Project: "p", Endpoint: fcm.URL, Client: fcm.Client()}}
	dialer := &mail.Dialer{Guard: guard, Store: e.st}
	pool := &mail.Pool{Dialer: dialer, TTL: time.Minute}
	mgr := &watch.Manager{Store: e.st, Vault: v, Guard: guard, Mail: dialer, HTTP: davClient, Hub: hub, Log: log,
		POP3Interval: time.Minute, DAVInterval: time.Hour, IMAPPoll: time.Minute}
	profile := model.Settings{Incoming: e.imap, Outgoing: smtpEP, CalDAVURL: cal.URL + "/", CardDAVURL: card.URL + "/"}
	s := &Server{Store: e.st, Vault: v, Guard: guard, Mail: dialer, Pool: pool, HTTP: davClient, Hub: hub, Watch: mgr, Log: log,
		Discover:    &discover.Discoverer{Profiles: map[string]model.Settings{"corp.test": profile}, HTTP: http.DefaultClient},
		AllowCustom: false}
	e.srv = httptest.NewServer(s.Handler())
	t.Cleanup(e.srv.Close)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go mgr.Run(ctx)
	return e
}

func (e *env) do(method, path, token string, body any) (*http.Response, map[string]any) {
	e.t.Helper()
	var rd io.Reader
	if body != nil {
		if s, ok := body.(string); ok {
			rd = strings.NewReader(s)
		} else {
			b, _ := json.Marshal(body)
			rd = bytes.NewReader(b)
		}
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	var out map[string]any
	if json.Unmarshal(raw, &out) != nil {
		var arr []any
		if json.Unmarshal(raw, &arr) == nil {
			out = map[string]any{"items": arr}
		} else {
			out = map[string]any{"raw": string(raw)}
		}
	}
	return resp, out
}

func (e *env) must(status int, method, path, token string, body any) map[string]any {
	e.t.Helper()
	resp, out := e.do(method, path, token, body)
	if resp.StatusCode != status {
		e.t.Fatalf("%s %s: want %d, got %d: %v", method, path, status, resp.StatusCode, out)
	}
	return out
}

func errCode(m map[string]any) string {
	if e, ok := m["error"].(map[string]any); ok {
		return e["code"].(string)
	}
	return ""
}

func login(e *env, device string) (access, refresh, accountID string) {
	out := e.must(200, "POST", "/v1/auth/login", "", map[string]any{
		"email": "alice@corp.test", "password": "pw", "username": "alice",
		"device": map[string]string{"name": device, "platform": "android"}})
	return out["access_token"].(string), out["refresh_token"].(string), out["account_id"].(string)
}

func TestEndToEnd(t *testing.T) {
	e := setup(t)

	// Discovery and login policy.
	out := e.must(200, "POST", "/v1/discover", "", map[string]string{"email": "x@corp.test"})
	if out["incoming"].(map[string]any)["protocol"] != "imap" {
		t.Fatalf("discover: %v", out)
	}
	_, out = e.do("POST", "/v1/auth/login", "", map[string]any{"email": "alice@corp.test", "password": "nope", "username": "alice",
		"device": map[string]string{"name": "p", "platform": "android"}})
	if errCode(out) != "invalid_credentials" {
		t.Fatalf("bad password: %v", out)
	}
	_, out = e.do("POST", "/v1/auth/login", "", `{"email":"a@corp.test","password":"x","device":{"name":"p","platform":"android"},"admin":true}`)
	if errCode(out) != "bad_request" {
		t.Fatalf("unknown fields must be rejected: %v", out)
	}
	_, out = e.do("POST", "/v1/auth/login", "", map[string]any{"email": "a@other.test", "password": "x",
		"device": map[string]string{"name": "p", "platform": "ios"}, "server": map[string]any{}})
	if errCode(out) != "forbidden" {
		t.Fatalf("custom servers are disabled by policy: %v", out)
	}

	access, refresh, aid := login(e, "phone")
	resp, _ := e.do("GET", "/v1/me", "", nil)
	if resp.StatusCode != 401 {
		t.Fatal("no token must be 401")
	}
	if resp.Header.Get("X-Content-Type-Options") != "nosniff" || resp.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("security headers missing")
	}
	me := e.must(200, "GET", "/v1/me", access, nil)
	acct := me["accounts"].([]any)[0].(map[string]any)
	if acct["id"] != aid || acct["has_calendar"] != true || acct["incoming_protocol"] != "imap" {
		t.Fatalf("me: %v", me)
	}

	// Mail.
	base := "/v1/accounts/" + aid
	folders := e.must(200, "GET", base+"/folders", access, nil)["items"].([]any)
	if folders[0].(map[string]any)["role"] != "inbox" {
		t.Fatalf("folders: %v", folders)
	}
	page := e.must(200, "GET", base+"/messages?folder=INBOX&limit=2", access, nil)
	msgs := page["messages"].([]any)
	if len(msgs) != 2 || page["next_before"] == nil {
		t.Fatalf("page: %v", page)
	}
	rich := msgs[0].(map[string]any)["id"].(string)
	m := e.must(200, "GET", base+"/messages/"+rich+"?folder=INBOX", access, nil)
	if strings.Contains(m["html"].(string), "<script") || m["remote_content_blocked"] != true {
		t.Fatalf("message html not sanitized: %v", m["html"])
	}
	req, _ := http.NewRequest("GET", e.srv.URL+base+"/messages/"+rich+"/attachments/0?folder=INBOX", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	ar, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(ar.Body)
	ar.Body.Close()
	if ar.Header.Get("Content-Type") != "application/octet-stream" || !strings.Contains(ar.Header.Get("Content-Disposition"), `filename=r.pdf`) || string(body) != "%PDF-1.4\n" {
		t.Fatalf("attachment: %v %q", ar.Header, body)
	}
	e.must(204, "PATCH", base+"/messages/"+rich+"?folder=INBOX", access, map[string]bool{"seen": true})
	e.must(404, "GET", base+"/messages/1.999999?folder=INBOX", access, nil)
	e.must(400, "GET", base+"/messages?folder=", access, nil)

	sent := e.must(202, "POST", base+"/send", access, map[string]any{
		"to": []map[string]string{{"name": "Bob", "email": "bob@x.io"}}, "subject": "Hi", "text": "hello",
		"attachments": []map[string]string{{"filename": "a.txt", "content_type": "text/plain", "data_base64": base64.StdEncoding.EncodeToString([]byte("att"))}},
	})
	if !strings.HasSuffix(sent["message_id"].(string), "@corp.test>") {
		t.Fatalf("send: %v", sent)
	}
	e.smtp.Mu.Lock()
	if e.smtp.From != "alice@corp.test" || len(e.smtp.Rcpt) != 1 {
		t.Fatalf("smtp: %s %v", e.smtp.From, e.smtp.Rcpt)
	}
	e.smtp.Mu.Unlock()
	if s := e.must(200, "GET", base+"/messages?folder=Sent", access, nil)["messages"].([]any); len(s) != 1 {
		t.Fatalf("sent copy: %v", s)
	}
	_, out = e.do("POST", base+"/send", access, map[string]any{"to": []map[string]string{{"email": "bob@x.io\r\nBcc: evil@x.io"}}, "subject": "x"})
	if errCode(out) != "bad_request" {
		t.Fatalf("header injection must be refused: %v", out)
	}
	_, out = e.do("POST", base+"/send", access, map[string]any{"to": []map[string]string{{"email": "bob@x.io"}}, "subject": "a\r\nBcc: evil@x.io"})
	if errCode(out) != "bad_request" {
		t.Fatalf("subject injection must be refused: %v", out)
	}
	e.must(204, "DELETE", base+"/messages/"+rich+"?folder=INBOX", access, nil)

	// Calendar and contacts.
	cals := e.must(200, "GET", base+"/calendars", access, nil)["items"].([]any)
	calID := cals[0].(map[string]any)["id"].(string)
	start := time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)
	ev := e.must(200, "PUT", base+"/events", access, map[string]any{"calendar": calID, "summary": "Standup",
		"start": start, "end": start.Add(15 * time.Minute)})
	q := url.Values{"calendar": {calID}, "from": {start.Add(-time.Hour).Format(time.RFC3339)}, "to": {start.Add(time.Hour).Format(time.RFC3339)}}
	if evs := e.must(200, "GET", base+"/events?"+q.Encode(), access, nil)["items"].([]any); len(evs) != 1 {
		t.Fatalf("events: %v", evs)
	}
	_, out = e.do("PUT", base+"/events", access, map[string]any{"id": ev["id"], "etag": "stale", "summary": "x", "start": start, "end": start.Add(time.Hour)})
	if errCode(out) != "conflict" {
		t.Fatalf("stale etag: %v", out)
	}
	e.must(400, "GET", base+"/events?calendar=/alice/cal/../../etc/&from=2026-01-01T00:00:00Z&to=2026-01-02T00:00:00Z", access, nil)
	if books := e.must(200, "GET", base+"/addressbooks", access, nil)["items"].([]any); len(books) != 1 {
		t.Fatalf("address books: %v", books)
	}

	// Other users' accounts are invisible.
	bob, _ := e.st.UpsertUser(context.Background(), "bob@corp.test", "bob")
	bobAcct, _ := e.st.SaveAccount(context.Background(), store.Account{ID: store.NewID(), UserID: bob.ID, Email: "bob@corp.test",
		Username: "bob", Settings: model.Settings{Incoming: e.imap, Outgoing: e.imap}, SecretKID: "k1", Secret: []byte{1}})
	e.must(404, "GET", "/v1/accounts/"+bobAcct.ID+"/folders", access, nil)

	// Realtime: the streaming device gets mail.new over the socket, the other device by FCM.
	access2, _, _ := login(e, "tablet")
	e.must(204, "PUT", "/v1/devices/current/push", access2, map[string]string{"provider": "fcm", "token": "tok-tablet"})
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(e.srv.URL, "http")+"/v1/stream", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer ws.CloseNow()
	wsjson.Write(ctx, ws, map[string]string{"type": "auth", "token": access})
	var ready model.Event
	if err := wsjson.Read(ctx, ws, &ready); err != nil || ready.Type != "ready" {
		t.Fatalf("stream ready: %v %v", ready, err)
	}
	got := make(chan model.Event, 4)
	go func() {
		for {
			var ev model.Event
			if wsjson.Read(ctx, ws, &ev) != nil {
				return
			}
			got <- ev
		}
	}()
	deadline := time.After(15 * time.Second)
	var newMail model.Event
wait:
	for i := 0; ; i++ {
		testutil.AppendRaw(t, e.imap, "INBOX", fmt.Sprintf(testutil.PlainMsg, 100+i, 100+i, 100+i)) // until IDLE is up
		select {
		case ev := <-got:
			if ev.Type == "mail.new" {
				newMail = ev
				break wait
			}
		case <-time.After(time.Second):
		case <-deadline:
			t.Fatal("no mail.new on the stream")
		}
	}
	if newMail.AccountID != aid || newMail.Folder != "INBOX" {
		t.Fatalf("event: %+v", newMail)
	}
	var fcmBodies string
	for i := 0; i < 50 && !strings.Contains(fcmBodies, "tok-tablet"); i++ { // FCM is sent after the socket write
		time.Sleep(100 * time.Millisecond)
		e.fcmMu.Lock()
		fcmBodies = strings.Join(e.fcm, "\n")
		e.fcmMu.Unlock()
	}
	if !strings.Contains(fcmBodies, `"token":"tok-tablet"`) || !strings.Contains(fcmBodies, `"mail.new"`) {
		t.Fatalf("offline device must get FCM: %s", fcmBodies)
	}
	if strings.Contains(fcmBodies, "hello 10") || strings.Contains(fcmBodies, "bob@x.io") {
		t.Fatalf("push payload must not carry message content: %s", fcmBodies)
	}

	// Bad stream auth is refused.
	ws2, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(e.srv.URL, "http")+"/v1/stream", nil)
	if err != nil {
		t.Fatal(err)
	}
	wsjson.Write(ctx, ws2, map[string]string{"type": "auth", "token": "ma_bogus"})
	var x model.Event
	if err := wsjson.Read(ctx, ws2, &x); websocket.CloseStatus(err) != 4401 {
		t.Fatalf("bad stream token: %v", err)
	}

	// Devices: the phone sees both and can revoke the tablet.
	devs := e.must(200, "GET", "/v1/devices", access, nil)["items"].([]any)
	if len(devs) != 2 {
		t.Fatalf("devices: %v", devs)
	}
	for _, d := range devs {
		if dm := d.(map[string]any); dm["current"] != true {
			e.must(204, "DELETE", "/v1/devices/"+dm["id"].(string), access, nil)
		}
	}
	e.must(401, "GET", "/v1/me", access2, nil)

	// Refresh rotation, then reuse of the old refresh token revokes the device.
	tk := e.must(200, "POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": refresh})
	e.must(401, "GET", "/v1/me", access, nil)
	e.must(200, "GET", "/v1/me", tk["access_token"].(string), nil)
	e.must(401, "POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": refresh})
	e.must(401, "GET", "/v1/me", tk["access_token"].(string), nil)
}

func TestLoginRateLimit(t *testing.T) {
	e := setup(t)
	limited := false
	for i := 0; i < 12; i++ {
		resp, _ := e.do("POST", "/v1/auth/login", "", map[string]any{"email": "alice@corp.test", "password": "wrong", "username": "alice",
			"device": map[string]string{"name": "p", "platform": "android"}})
		if resp.StatusCode == 429 {
			limited = resp.Header.Get("Retry-After") != ""
			break
		}
	}
	if !limited {
		t.Fatal("repeated failed logins must be rate limited")
	}
}

// A real user of the same server cannot become someone else by claiming their address.
func TestLoginCannotClaimAnotherUsersAddress(t *testing.T) {
	e := setup(t)
	alice, _, aliceAcct := login(e, "phone")
	out := e.must(200, "POST", "/v1/auth/login", "", map[string]any{
		"email": "alice@corp.test", "password": "pw2", "username": "mallory",
		"device": map[string]string{"name": "evil", "platform": "android"}})
	mallory := out["access_token"].(string)
	me := e.must(200, "GET", "/v1/me", mallory, nil)
	for _, a := range me["accounts"].([]any) {
		if a.(map[string]any)["id"] == aliceAcct {
			t.Fatal("mallory inherited alice's account")
		}
	}
	e.must(404, "GET", "/v1/accounts/"+aliceAcct+"/folders", mallory, nil)
	if e.must(200, "GET", "/v1/me", alice, nil)["user"].(map[string]any)["id"] == me["user"].(map[string]any)["id"] {
		t.Fatal("mallory and alice must be different users")
	}
}
