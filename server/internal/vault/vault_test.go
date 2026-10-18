package vault

import (
	"bytes"
	"encoding/base64"
	"strings"
	"testing"
)

func key(b byte) string { return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{b}, 32)) }

func TestSealOpenRotateAndBinding(t *testing.T) {
	old, err := Parse("k1:" + key(1))
	if err != nil {
		t.Fatal(err)
	}
	kid, sealed := old.Seal([]byte("hunter2"), []byte("acct-1"))

	rotated, err := Parse("k2:" + key(2) + ",k1:" + key(1))
	if err != nil {
		t.Fatal(err)
	}
	got, err := rotated.Open(kid, sealed, []byte("acct-1"))
	if err != nil || string(got) != "hunter2" {
		t.Fatalf("open after rotation: %q %v", got, err)
	}
	if k, _ := rotated.Seal([]byte("x"), nil); k != "k2" {
		t.Fatalf("new data must use the first key, got %s", k)
	}
	if _, err := rotated.Open(kid, sealed, []byte("acct-2")); err == nil {
		t.Fatal("ciphertext must be bound to its account id")
	}
	sealed[len(sealed)-1] ^= 1
	if _, err := rotated.Open(kid, sealed, []byte("acct-1")); err == nil {
		t.Fatal("tampered ciphertext must fail")
	}
}

func TestParseRejectsBadKeys(t *testing.T) {
	for _, spec := range []string{"", "nokid", "k:" + base64.StdEncoding.EncodeToString([]byte("short")), "k:" + key(1) + ",k:" + key(2)} {
		if _, err := Parse(spec); err == nil {
			t.Errorf("Parse(%q) should fail", strings.TrimSpace(spec))
		}
	}
}
