package netguard

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"testing"
)

func TestAllowed(t *testing.T) {
	g := &Guard{}
	for _, s := range []string{"127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254",
		"100.64.0.1", "0.0.0.0", "::1", "fe80::1", "fc00::1", "::ffff:127.0.0.1", "224.0.0.1", "64:ff9b::a00:1"} {
		if g.Allowed(netip.MustParseAddr(s)) {
			t.Errorf("%s must be blocked", s)
		}
	}
	for _, s := range []string{"1.1.1.1", "2606:4700:4700::1111", "142.250.0.1"} {
		if !g.Allowed(netip.MustParseAddr(s)) {
			t.Errorf("%s must be allowed", s)
		}
	}
	g.Allow = []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8")}
	if !g.Allowed(netip.MustParseAddr("10.1.2.3")) {
		t.Error("operator allowlist must win")
	}
}

func TestDialBlocksLoopback(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	_, err = (&Guard{}).DialContext(context.Background(), "tcp", ln.Addr().String())
	if !errors.Is(err, ErrBlocked) {
		t.Fatalf("want ErrBlocked, got %v", err)
	}
	g := &Guard{Allow: []netip.Prefix{netip.MustParsePrefix("127.0.0.0/8")}}
	c, err := g.DialContext(context.Background(), "tcp", ln.Addr().String())
	if err != nil {
		t.Fatalf("allowlisted dial: %v", err)
	}
	c.Close()
}
