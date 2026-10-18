// Command master is the mail/calendar/contacts gateway.
//
//	master            serve (configuration from MASTER_* environment variables)
//	master genkey     print a new vault key for MASTER_VAULT_KEYS
package main

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/api"
	"github.com/ckdash-git/optional_mailclient/server/internal/config"
	"github.com/ckdash-git/optional_mailclient/server/internal/discover"
	"github.com/ckdash-git/optional_mailclient/server/internal/mail"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
	"github.com/ckdash-git/optional_mailclient/server/internal/push"
	"github.com/ckdash-git/optional_mailclient/server/internal/store"
	"github.com/ckdash-git/optional_mailclient/server/internal/vault"
	"github.com/ckdash-git/optional_mailclient/server/internal/watch"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "genkey" {
		var k [32]byte
		if _, err := rand.Read(k[:]); err != nil {
			panic(err)
		}
		fmt.Printf("k%d:%s\n", time.Now().Unix(), base64.StdEncoding.EncodeToString(k[:]))
		return
	}
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if err := run(log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	v, err := vault.Parse(cfg.VaultKeys)
	if err != nil {
		return err
	}
	os.Unsetenv("MASTER_VAULT_KEYS") // keep keys out of anything that later dumps the environment
	if err := os.MkdirAll(filepath.Dir(cfg.DBPath), 0o700); err != nil {
		return err
	}
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()
	os.Chmod(cfg.DBPath, 0o600)

	profiles, err := discover.LoadProfiles(cfg.ProfilesPath)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	guard := &netguard.Guard{Allow: cfg.AllowNetworks}
	hc := guard.HTTPClient(60 * time.Second)
	hub := &push.Hub{Store: st, Log: log}
	if cfg.FCMCredentials != "" {
		if hub.FCM, err = push.NewFCM(ctx, cfg.FCMCredentials); err != nil {
			return fmt.Errorf("fcm: %w", err)
		}
		log.Info("fcm push enabled", "project", hub.FCM.Project)
	} else {
		log.Warn("MASTER_FCM_CREDENTIALS not set: devices only get updates while the app is open")
	}
	dialer := &mail.Dialer{Guard: guard, Store: st}
	pool := &mail.Pool{Dialer: dialer, TTL: 2 * time.Minute}
	mgr := &watch.Manager{Store: st, Vault: v, Guard: guard, Mail: dialer, HTTP: hc, Hub: hub, Log: log,
		POP3Interval: cfg.POP3Interval, DAVInterval: cfg.DAVInterval, IMAPPoll: 2 * time.Minute}
	srv := &api.Server{Store: st, Vault: v, Guard: guard, Mail: dialer, Pool: pool, HTTP: hc, Hub: hub, Watch: mgr, Log: log,
		Discover:    &discover.Discoverer{Profiles: profiles, HTTP: guard.HTTPClient(15 * time.Second), DNS: net.DefaultResolver},
		AllowCustom: cfg.AllowCustom, TrustedProxies: cfg.TrustedProxies, CORSOrigins: cfg.CORSOrigins}

	go mgr.Run(ctx)
	go func() {
		t := time.NewTicker(time.Minute)
		defer t.Stop()
		for i := 0; ; i++ {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				pool.Sweep()
				if i%60 == 0 {
					if err := st.PurgeExpired(ctx); err != nil {
						log.Error("purge expired tokens", "err", err)
					}
				}
			}
		}
	}()

	hs := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       5 * time.Minute, // large sends; handlers bound their own upstream work
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    64 << 10,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS12},
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}
	errc := make(chan error, 1)
	go func() {
		log.Info("master listening", "addr", cfg.Listen, "tls", cfg.TLSCert != "")
		if cfg.TLSCert != "" {
			errc <- hs.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey)
		} else {
			errc <- hs.ListenAndServe()
		}
	}()
	select {
	case err := <-errc:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
	}
	log.Info("shutting down")
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	return hs.Shutdown(sctx)
}
