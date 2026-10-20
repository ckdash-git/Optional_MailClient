package api

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/signal"
	"strings"
	"testing"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/testutil"
)

const demoMsg = "From: %s\r\nTo: Alice Demo <alice@corp.test>\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: <demo%d@corp.test>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n%s\r\n"

// TestDemoServer runs the whole master with throwaway mail/DAV servers behind it so the
// apps can be tried end to end: MASTER_DEMO=18443 go test -run TestDemoServer ./internal/api
// Sign in as alice@corp.test / pw with server https://localhost:18443 (self-signed cert).
func TestDemoServer(t *testing.T) {
	port := os.Getenv("MASTER_DEMO")
	if port == "" {
		t.Skip("set MASTER_DEMO=<port> to run the demo server")
	}
	e := setup(t)
	now := time.Now().UTC()
	msgs := []struct {
		from, subj, body string
		ago              time.Duration
	}{
		{"Priya Nair <priya@studio.example>", "Design review moved to Thursday", "Hi Alice,\n\nWe moved the design review to Thursday 15:00 so Marco can join.\nAgenda: https://studio.example/review\n\nThanks,\nPriya", 26 * time.Hour},
		{"Billing <billing@cloudhost.example>", "Your invoice for October", "Your invoice #20481 for October is ready. Amount due: 42.00 EUR.\nNo action needed if you pay by card.", 20 * time.Hour},
		{"Marco Rossi <marco@studio.example>", "Re: Release checklist", "Looks good. One question: do we ship the push relay in 1.0 or 1.1?\n\n-- Marco", 5 * time.Hour},
		{"Ops Alerts <alerts@corp.test>", "Backup completed", "Nightly backup finished in 4m12s. 0 errors.", 3 * time.Hour},
		{"Sam Okafor <sam@partner.example>", "Lunch tomorrow?", "Are you free for lunch tomorrow around 12:30? There is a new place near the station.", 40 * time.Minute},
	}
	for i, m := range msgs {
		raw := fmt.Sprintf(demoMsg, m.from, m.subj, now.Add(-m.ago).Format(time.RFC1123Z), 200+i, strings.ReplaceAll(m.body, "\n", "\r\n"))
		testutil.AppendRaw(t, e.imap, "INBOX", raw)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:"+port)
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewUnstartedServer(corsDemo(e.h))
	ts.Listener = ln
	ts.StartTLS()
	defer ts.Close()
	fmt.Println("DEMO_READY https://localhost:" + port)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt)
	<-sig
}

// corsDemo lets the web build served from another localhost port call the demo master.
func corsDemo(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if o := r.Header.Get("Origin"); strings.HasPrefix(o, "http://localhost:") {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
