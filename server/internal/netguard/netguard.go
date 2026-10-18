// Package netguard dials user-supplied hosts without letting them reach the master's own
// network (SSRF). The check runs on the resolved IP inside the dialer, so DNS rebinding
// cannot slip a private address past it.
package netguard

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"syscall"
	"time"
)

var ErrBlocked = errors.New("destination address is not allowed")

// blocked holds ranges the netip predicates below do not cover.
var blocked = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"),
	netip.MustParsePrefix("100.64.0.0/10"), // carrier-grade NAT
	netip.MustParsePrefix("192.0.0.0/24"),
	netip.MustParsePrefix("198.18.0.0/15"), // benchmarking
	netip.MustParsePrefix("240.0.0.0/4"),
	netip.MustParsePrefix("64:ff9b::/96"), // NAT64 can map to private v4
}

type Guard struct {
	Allow []netip.Prefix // operator allowlist, e.g. an on-prem mail server on 10.0.0.0/8
}

func (g *Guard) Allowed(ip netip.Addr) bool {
	ip = ip.Unmap()
	for _, p := range g.Allow {
		if p.Contains(ip) {
			return true
		}
	}
	if !ip.IsValid() || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsInterfaceLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
		return false
	}
	for _, p := range blocked {
		if p.Contains(ip) {
			return false
		}
	}
	return true
}

// AllowsHost reports whether every address host resolves to is on the operator
// allowlist. Plaintext (no TLS) connections are only permitted to such hosts.
func (g *Guard) AllowsHost(ctx context.Context, host string) bool {
	if len(g.Allow) == 0 {
		return false
	}
	addrs, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	if err != nil || len(addrs) == 0 {
		return false
	}
	for _, a := range addrs {
		ok := false
		for _, p := range g.Allow {
			ok = ok || p.Contains(a.Unmap())
		}
		if !ok {
			return false
		}
	}
	return true
}

func (g *Guard) Dialer(timeout time.Duration) *net.Dialer {
	return &net.Dialer{
		Timeout:   timeout,
		KeepAlive: 30 * time.Second,
		Control: func(_, address string, _ syscall.RawConn) error {
			ap, err := netip.ParseAddrPort(address)
			if err != nil {
				return fmt.Errorf("netguard: %w", err)
			}
			if !g.Allowed(ap.Addr()) {
				return fmt.Errorf("%w: %s", ErrBlocked, ap.Addr())
			}
			return nil
		},
	}
}

// DialContext dials through the guard.
func (g *Guard) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return g.Dialer(15*time.Second).DialContext(ctx, network, addr)
}

// TLSConfig is the client TLS policy for every upstream connection.
func TLSConfig(serverName string) *tls.Config {
	return &tls.Config{ServerName: serverName, MinVersion: tls.VersionTLS12}
}

// HTTPClient is used for CalDAV/CardDAV and autodiscovery. Redirects are re-dialled
// through the guard and must stay on https.
func (g *Guard) HTTPClient(timeout time.Duration) *http.Client {
	tr := &http.Transport{
		DialContext:           g.DialContext,
		TLSClientConfig:       &tls.Config{MinVersion: tls.VersionTLS12},
		ForceAttemptHTTP2:     true,
		MaxIdleConnsPerHost:   4,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
	}
	return &http.Client{
		Transport: tr,
		Timeout:   timeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			if req.URL.Scheme != "https" && via[0].URL.Scheme == "https" {
				return errors.New("refusing redirect from https to http")
			}
			return nil
		},
	}
}
