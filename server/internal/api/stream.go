package api

import (
	"context"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
)

// stream is the realtime channel. The token arrives in the first frame: browsers cannot
// set headers on a WebSocket, and a token in the URL would end up in proxy logs.
func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	if !s.ipSoft.allow(s.clientIP(r)) {
		tooMany(w)
		return
	}
	// Any origin may connect: there are no ambient credentials (cookies) to hijack, and
	// nothing is sent before the client proves it holds a token.
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{OriginPatterns: []string{"*"}})
	if err != nil {
		return
	}
	defer c.CloseNow()
	c.SetReadLimit(8 << 10)

	actx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	var hello struct {
		Type  string `json:"type"`
		Token string `json:"token"`
	}
	err = wsjson.Read(actx, c, &hello)
	cancel()
	if err != nil || hello.Type != "auth" {
		c.Close(4401, "auth required")
		return
	}
	u, dev, err := s.Store.Authenticate(r.Context(), hello.Token)
	if err != nil {
		c.Close(4401, "invalid token")
		return
	}
	sub := s.Hub.Subscribe(u.ID, dev)
	defer s.Hub.Unsubscribe(sub)

	ctx := c.CloseRead(r.Context()) // the client sends nothing more; this notices it leaving
	write := func(v any) error {
		wctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		return wsjson.Write(wctx, c, v)
	}
	if write(model.Event{Type: "ready"}) != nil {
		return
	}
	ping := time.NewTicker(30 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case ev, ok := <-sub.C:
			if !ok { // revoked or too slow
				c.Close(4401, "disconnected")
				return
			}
			if write(ev) != nil {
				return
			}
		case <-ping.C:
			pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			err := c.Ping(pctx)
			cancel()
			if err != nil {
				return
			}
		}
	}
}
