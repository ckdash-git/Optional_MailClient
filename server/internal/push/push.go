// Package push fans account events out to a user's devices: open WebSocket streams
// first, FCM for devices that are not connected. Payloads never carry message content.
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
)

// Sub is one open stream. Events arrive on C; it is closed if the client is too slow.
type Sub struct {
	UserID   string
	DeviceID string
	C        chan model.Event
}

type Hub struct {
	Store *store.Store
	FCM   *FCM // nil when not configured
	Log   *slog.Logger

	mu   sync.Mutex
	subs map[string]map[*Sub]struct{}
}

func (h *Hub) Subscribe(userID, deviceID string) *Sub {
	s := &Sub{UserID: userID, DeviceID: deviceID, C: make(chan model.Event, 32)}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.subs == nil {
		h.subs = map[string]map[*Sub]struct{}{}
	}
	if h.subs[userID] == nil {
		h.subs[userID] = map[*Sub]struct{}{}
	}
	h.subs[userID][s] = struct{}{}
	return s
}

func (h *Hub) Unsubscribe(s *Sub) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.subs[s.UserID][s]; ok {
		delete(h.subs[s.UserID], s)
		close(s.C)
	}
}

// Disconnect closes every stream of a device (used when it is revoked).
func (h *Hub) Disconnect(deviceID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, set := range h.subs {
		for s := range set {
			if s.DeviceID == deviceID {
				delete(set, s)
				close(s.C)
			}
		}
	}
}

func (h *Hub) Publish(ctx context.Context, userID, accountEmail string, ev model.Event) {
	online := map[string]bool{}
	h.mu.Lock()
	for s := range h.subs[userID] {
		select {
		case s.C <- ev:
			online[s.DeviceID] = true
		default: // a client that cannot keep up reconnects and refetches
			delete(h.subs[userID], s)
			close(s.C)
		}
	}
	h.mu.Unlock()

	if ev.Type != "mail.new" || h.FCM == nil {
		return
	}
	devices, err := h.Store.ListDevices(ctx, userID)
	if err != nil {
		h.Log.Error("push: list devices", "err", err)
		return
	}
	for _, d := range devices {
		if d.PushToken == "" || online[d.ID] {
			continue
		}
		err := h.FCM.Send(ctx, d.PushToken, ev, accountEmail)
		if err == ErrUnregistered {
			_ = h.Store.ClearPushToken(ctx, d.PushToken)
		} else if err != nil {
			h.Log.Warn("push: fcm send failed", "device", d.ID, "err", err)
		}
	}
}

// ---- FCM HTTP v1 ----

var ErrUnregistered = fmt.Errorf("fcm: token unregistered")

type FCM struct {
	Project  string
	Endpoint string       // override in tests
	Client   *http.Client // authorised with the service account
}

// NewFCM reads a Google service-account JSON key with the firebase.messaging scope.
func NewFCM(ctx context.Context, credentialsPath string) (*FCM, error) {
	b, err := os.ReadFile(credentialsPath)
	if err != nil {
		return nil, err
	}
	creds, err := google.CredentialsFromJSONWithType(ctx, b, google.ServiceAccount, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, err
	}
	if creds.ProjectID == "" {
		return nil, fmt.Errorf("fcm: credentials have no project_id")
	}
	c := oauth2.NewClient(ctx, creds.TokenSource)
	c.Timeout = 10 * time.Second
	return &FCM{Project: creds.ProjectID, Client: c}, nil
}

func (f *FCM) Send(ctx context.Context, token string, ev model.Event, accountEmail string) error {
	data := map[string]string{"type": ev.Type, "account_id": ev.AccountID, "folder": ev.Folder}
	msg := map[string]any{"message": map[string]any{
		"token": token,
		"data":  data,
		// Generic text: no subject or sender passes through Google/Apple.
		"notification": map[string]string{"title": "New mail", "body": "New mail in " + accountEmail},
		"android":      map[string]any{"priority": "high", "collapse_key": ev.AccountID},
		"apns":         map[string]any{"headers": map[string]string{"apns-collapse-id": ev.AccountID}},
	}}
	body, _ := json.Marshal(msg)
	url := f.Endpoint
	if url == "" {
		url = "https://fcm.googleapis.com/v1/projects/" + f.Project + "/messages:send"
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	switch {
	case resp.StatusCode == http.StatusOK:
		return nil
	case resp.StatusCode == http.StatusNotFound || bytes.Contains(rb, []byte("UNREGISTERED")):
		return ErrUnregistered
	default:
		return fmt.Errorf("fcm: %s", resp.Status)
	}
}
