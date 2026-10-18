package mail

import (
	"bytes"
	"context"
	"errors"
	"time"

	"github.com/emersion/go-sasl"
	"github.com/emersion/go-smtp"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	"github.com/ckdash-git/optional_mailclient/server/internal/netguard"
)

// smtpLogin connects and authenticates. The master never relays unauthenticated mail.
func smtpLogin(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds, timeout time.Duration) (*smtp.Client, error) {
	conn, err := connect(ctx, g, e)
	if err != nil {
		return nil, err
	}
	conn.SetDeadline(time.Now().Add(timeout))
	var c *smtp.Client
	if e.Security == "starttls" {
		if c, err = smtp.NewClientStartTLS(conn, netguard.TLSConfig(e.Host)); err != nil {
			conn.Close()
			return nil, err
		}
	} else {
		c = smtp.NewClient(conn)
	}
	if err := c.Auth(sasl.NewPlainClient("", cr.Username, cr.Password)); err != nil {
		c.Close()
		var se *smtp.SMTPError
		if errors.As(err, &se) && se.Code == 535 {
			return nil, ErrAuth
		}
		return nil, err
	}
	return c, nil
}

// Submit sends raw to the given recipients through the account's submission server.
func Submit(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds, from string, rcpt []string, raw []byte) error {
	c, err := smtpLogin(ctx, g, e, cr, 5*time.Minute)
	if err != nil {
		return err
	}
	defer c.Close()
	if err := c.SendMail(from, rcpt, bytes.NewReader(raw)); err != nil {
		return err
	}
	return c.Quit()
}

// VerifySMTP checks that the submission server accepts the credentials.
func VerifySMTP(ctx context.Context, g *netguard.Guard, e model.Endpoint, cr Creds) error {
	c, err := smtpLogin(ctx, g, e, cr, 30*time.Second)
	if err != nil {
		return err
	}
	defer c.Close()
	return c.Quit()
}
