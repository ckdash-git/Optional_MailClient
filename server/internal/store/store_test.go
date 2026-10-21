package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
)

func open(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestTokenRotationAndReuseRevokesDevice(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	u, _ := s.UpsertUser(ctx, "Ana@Example.com", "ana")
	d, _ := s.CreateDevice(ctx, u.ID, "phone", "android")
	t1, err := s.IssueTokens(ctx, d.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got, dev, err := s.Authenticate(ctx, t1.AccessToken); err != nil || got.Email != "ana@example.com" || dev != d.ID {
		t.Fatalf("authenticate: %v %v %v", got, dev, err)
	}
	t2, err := s.Refresh(ctx, t1.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.Authenticate(ctx, t1.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatal("old access token must die on rotation")
	}
	if _, err := s.Refresh(ctx, t1.RefreshToken); !errors.Is(err, ErrTokenReuse) {
		t.Fatalf("reuse must be detected, got %v", err)
	}
	if _, _, err := s.Authenticate(ctx, t2.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatal("reuse must revoke the whole device")
	}
	if _, err := s.Refresh(ctx, t2.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatal("device is gone, its refresh token must be invalid")
	}
}

func TestAccessTokenExpires(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	u, _ := s.UpsertUser(ctx, "a@x.io", "a")
	d, _ := s.CreateDevice(ctx, u.ID, "p", "ios")
	tk, _ := s.IssueTokens(ctx, d.ID)
	s.now = func() time.Time { return time.Now().Add(AccessTTL + time.Second) }
	if _, _, err := s.Authenticate(ctx, tk.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatal("expired access token accepted")
	}
}

func TestAccountsAreScopedToTheirUser(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	alice, _ := s.UpsertUser(ctx, "alice@x.io", "alice")
	bob, _ := s.UpsertUser(ctx, "bob@x.io", "bob")
	set := model.Settings{Incoming: model.Endpoint{Protocol: "imap", Host: "imap.x.io", Port: 993, Security: "tls"},
		Outgoing: model.Endpoint{Host: "smtp.x.io", Port: 465, Security: "tls"}}
	a, err := s.SaveAccount(ctx, Account{ID: NewID(), UserID: alice.ID, Email: "alice@x.io", Username: "alice", Settings: set, SecretKID: "k", Secret: []byte{1}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.GetAccount(ctx, bob.ID, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatal("bob must not read alice's account")
	}
	if err := s.DeleteAccount(ctx, bob.ID, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatal("bob must not delete alice's account")
	}
	// Saving again for the same email updates in place and keeps the id.
	again, err := s.SaveAccount(ctx, Account{ID: NewID(), UserID: alice.ID, Email: "ALICE@x.io", Username: "alice2", Settings: set, SecretKID: "k", Secret: []byte{2}})
	if err != nil || again.ID != a.ID {
		t.Fatalf("upsert: %v %v", again.ID, err)
	}
}

func TestPushTokenMovesBetweenDevices(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	u, _ := s.UpsertUser(ctx, "a@x.io", "a")
	d1, _ := s.CreateDevice(ctx, u.ID, "old", "android")
	d2, _ := s.CreateDevice(ctx, u.ID, "new", "android")
	_ = s.SetPush(ctx, d1.ID, "fcm", "tok")
	_ = s.SetPush(ctx, d2.ID, "fcm", "tok")
	ds, _ := s.ListDevices(ctx, u.ID)
	n := 0
	for _, d := range ds {
		if d.PushToken == "tok" {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("push token on %d devices", n)
	}
}

func TestIdentityIsBoundToServerAndLogin(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	real := model.Endpoint{Protocol: "imap", Host: "imap.corp.com", Port: 993}
	evil := model.Endpoint{Protocol: "imap", Host: "imap.attacker.io", Port: 993}
	ceo, _ := s.UpsertUser(ctx, "ceo@corp.com", Identity("ceo", real))
	otherServer, _ := s.UpsertUser(ctx, "ceo@corp.com", Identity("ceo", evil))
	otherLogin, _ := s.UpsertUser(ctx, "ceo@corp.com", Identity("mallory", real))
	again, _ := s.UpsertUser(ctx, "ceo@corp.com", Identity("ceo", model.Endpoint{Protocol: "imap", Host: "IMAP.corp.com", Port: 993}))
	if ceo.ID == otherServer.ID {
		t.Fatal("same login on a different server must be a different user")
	}
	if ceo.ID == otherLogin.ID {
		t.Fatal("a different login on the same server must be a different user, whatever email it claims")
	}
	if again.ID != ceo.ID {
		t.Fatal("host names are case-insensitive")
	}
}
