// Package config reads the master's settings from environment variables.
// Every variable is documented in server/README.md.
package config

import (
	"errors"
	"fmt"
	"net/netip"
	"os"
	"strings"
	"time"
)

type Config struct {
	Listen         string
	TLSCert        string
	TLSKey         string
	BehindProxy    bool
	TrustedProxies []netip.Prefix
	DBPath         string
	VaultKeys      string
	ProfilesPath   string
	AllowCustom    bool // users may type their own server settings
	AllowNetworks  []netip.Prefix
	FCMCredentials string
	CORSOrigins    []string
	POP3Interval   time.Duration
	DAVInterval    time.Duration
}

func FromEnv() (Config, error) {
	c := Config{
		Listen:         env("MASTER_LISTEN", ":8443"),
		TLSCert:        os.Getenv("MASTER_TLS_CERT"),
		TLSKey:         os.Getenv("MASTER_TLS_KEY"),
		BehindProxy:    os.Getenv("MASTER_BEHIND_PROXY") == "true",
		DBPath:         env("MASTER_DB", "data/master.db"),
		VaultKeys:      os.Getenv("MASTER_VAULT_KEYS"),
		ProfilesPath:   os.Getenv("MASTER_PROFILES"),
		AllowCustom:    env("MASTER_ALLOW_CUSTOM_SERVERS", "true") == "true",
		FCMCredentials: os.Getenv("MASTER_FCM_CREDENTIALS"),
	}
	for _, o := range strings.Split(os.Getenv("MASTER_CORS_ORIGINS"), ",") {
		if o = strings.TrimSpace(o); o != "" {
			if !strings.HasPrefix(o, "https://") && !strings.HasPrefix(o, "http://localhost") {
				return c, fmt.Errorf("MASTER_CORS_ORIGINS: %q must be an https origin", o)
			}
			c.CORSOrigins = append(c.CORSOrigins, o)
		}
	}
	var err error
	if c.TrustedProxies, err = prefixes("MASTER_TRUSTED_PROXIES"); err != nil {
		return c, err
	}
	if c.AllowNetworks, err = prefixes("MASTER_ALLOW_NETWORKS"); err != nil {
		return c, err
	}
	if c.POP3Interval, err = duration("MASTER_POP3_INTERVAL", "2m"); err != nil {
		return c, err
	}
	if c.DAVInterval, err = duration("MASTER_DAV_INTERVAL", "5m"); err != nil {
		return c, err
	}
	if c.VaultKeys == "" {
		return c, errors.New("MASTER_VAULT_KEYS is required (generate one with: master genkey)")
	}
	if (c.TLSCert == "") != (c.TLSKey == "") {
		return c, errors.New("set both MASTER_TLS_CERT and MASTER_TLS_KEY, or neither")
	}
	if c.TLSCert == "" && !c.BehindProxy {
		return c, errors.New("refusing to serve plain HTTP: set MASTER_TLS_CERT/MASTER_TLS_KEY, or MASTER_BEHIND_PROXY=true behind a TLS-terminating proxy")
	}
	return c, nil
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func duration(k, def string) (time.Duration, error) {
	d, err := time.ParseDuration(env(k, def))
	if err != nil || d < 30*time.Second {
		return 0, fmt.Errorf("%s must be a duration of at least 30s", k)
	}
	return d, nil
}

func prefixes(k string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, s := range strings.Split(os.Getenv(k), ",") {
		if s = strings.TrimSpace(s); s == "" {
			continue
		}
		p, err := netip.ParsePrefix(s)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", k, err)
		}
		out = append(out, p.Masked())
	}
	return out, nil
}
