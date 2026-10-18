// Package vault seals mail-server credentials at rest with AES-256-GCM.
//
// Keys come from MASTER_VAULT_KEYS as "kid:base64key,kid:base64key". The first key
// seals new data; every listed key can open old data, so rotation is: prepend a new key,
// restart, re-seal (accounts are re-sealed on next successful login), drop the old key.
package vault

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
)

type Vault struct {
	active string
	aeads  map[string]cipher.AEAD
}

func Parse(spec string) (*Vault, error) {
	v := &Vault{aeads: map[string]cipher.AEAD{}}
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		kid, b64, ok := strings.Cut(part, ":")
		if !ok || kid == "" {
			return nil, errors.New("vault: key must be kid:base64")
		}
		key, err := base64.StdEncoding.DecodeString(b64)
		if err != nil || len(key) != 32 {
			return nil, fmt.Errorf("vault: key %q must be 32 bytes, base64", kid)
		}
		if _, dup := v.aeads[kid]; dup {
			return nil, fmt.Errorf("vault: duplicate key id %q", kid)
		}
		block, _ := aes.NewCipher(key)
		aead, _ := cipher.NewGCM(block)
		v.aeads[kid] = aead
		if v.active == "" {
			v.active = kid
		}
	}
	if v.active == "" {
		return nil, errors.New("vault: no keys configured")
	}
	return v, nil
}

// Seal encrypts plaintext bound to aad (the account id), so a ciphertext copied onto
// another account row fails to open.
func (v *Vault) Seal(plaintext, aad []byte) (kid string, sealed []byte) {
	aead := v.aeads[v.active]
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		panic(err) // crypto/rand never fails on supported platforms
	}
	return v.active, aead.Seal(nonce, nonce, plaintext, aad)
}

func (v *Vault) Open(kid string, sealed, aad []byte) ([]byte, error) {
	aead, ok := v.aeads[kid]
	if !ok {
		return nil, fmt.Errorf("vault: unknown key id %q", kid)
	}
	n := aead.NonceSize()
	if len(sealed) < n {
		return nil, errors.New("vault: ciphertext too short")
	}
	return aead.Open(nil, sealed[:n], sealed[n:], aad)
}
