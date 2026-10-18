// Package store is the master's only persistence: one SQLite file.
//
// Authorisation rule: every method that reads or changes user-owned rows takes the
// user id and filters on it, so a handler cannot fetch another user's data by guessing
// an id.
package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	_ "embed"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
	_ "modernc.org/sqlite"
)

//go:embed schema.sql
var schema string

var (
	ErrNotFound     = errors.New("not found")
	ErrInvalidToken = errors.New("invalid token")
	ErrTokenReuse   = errors.New("refresh token reuse")
)

type Store struct {
	db  *sql.DB
	now func() time.Time
}

func Open(path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// ponytail: one connection serialises all queries; they are all index lookups.
	// Move to Postgres (same SQL, pgx) when one node is no longer enough.
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("store: migrate: %w", err)
	}
	return &Store{db: db, now: time.Now}, nil
}

func (s *Store) Close() error                   { return s.db.Close() }
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

func NewID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func (s *Store) unix() int64 { return s.now().Unix() }

// ---- users ----

type User struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

// Identity is the key a login resolves to: the login name that actually authenticated and
// the server that vouched for it. Not the email address: a user may type any address next
// to their own username. The username is kept case-sensitive because some servers are.
func Identity(username string, in model.Endpoint) string {
	return username + "|" + in.Protocol + "|" + strings.ToLower(in.Host) + "|" + strconv.Itoa(in.Port)
}

func (s *Store) UpsertUser(ctx context.Context, email, identity string) (User, error) {
	email = strings.ToLower(email)
	_, err := s.db.ExecContext(ctx, `INSERT INTO users(id,email,identity,created_at) VALUES(?,?,?,?) ON CONFLICT(identity) DO NOTHING`,
		NewID(), email, identity, s.unix())
	if err != nil {
		return User{}, err
	}
	u := User{}
	err = s.db.QueryRowContext(ctx, `SELECT id,email FROM users WHERE identity=?`, identity).Scan(&u.ID, &u.Email)
	return u, err
}

// AccountIDByEmail returns the id of the user's account for this address, if any.
func (s *Store) AccountIDByEmail(ctx context.Context, userID, email string) (string, bool, error) {
	var id string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM accounts WHERE user_id=? AND email=?`, userID, strings.ToLower(email)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return id, err == nil, err
}

// ---- devices and tokens ----

type Device struct {
	ID         string `json:"id"`
	UserID     string `json:"-"`
	Name       string `json:"name"`
	Platform   string `json:"platform"`
	PushToken  string `json:"-"`
	CreatedAt  int64  `json:"-"`
	LastSeenAt int64  `json:"-"`
}

type Tokens struct {
	AccessToken     string    `json:"access_token"`
	AccessExpiresAt time.Time `json:"access_expires_at"`
	RefreshToken    string    `json:"refresh_token"`
}

const (
	AccessTTL  = 15 * time.Minute
	RefreshTTL = 60 * 24 * time.Hour
)

func newToken(prefix string) (string, []byte) {
	var b [32]byte
	_, _ = rand.Read(b[:])
	t := prefix + base64.RawURLEncoding.EncodeToString(b[:])
	return t, hashToken(t)
}

func hashToken(t string) []byte { h := sha256.Sum256([]byte(t)); return h[:] }

func (s *Store) CreateDevice(ctx context.Context, userID, name, platform string) (Device, error) {
	d := Device{ID: NewID(), UserID: userID, Name: name, Platform: platform, CreatedAt: s.unix(), LastSeenAt: s.unix()}
	_, err := s.db.ExecContext(ctx, `INSERT INTO devices(id,user_id,name,platform,created_at,last_seen_at) VALUES(?,?,?,?,?,?)`,
		d.ID, d.UserID, d.Name, d.Platform, d.CreatedAt, d.LastSeenAt)
	return d, err
}

func (s *Store) IssueTokens(ctx context.Context, deviceID string) (Tokens, error) {
	return s.issue(ctx, s.db, deviceID)
}

type execer interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

func (s *Store) issue(ctx context.Context, x execer, deviceID string) (Tokens, error) {
	now := s.now()
	at, ah := newToken("ma_")
	rt, rh := newToken("mr_")
	if _, err := x.ExecContext(ctx, `INSERT INTO tokens(hash,device_id,kind,expires_at) VALUES(?,?,'access',?),(?,?,'refresh',?)`,
		ah, deviceID, now.Add(AccessTTL).Unix(), rh, deviceID, now.Add(RefreshTTL).Unix()); err != nil {
		return Tokens{}, err
	}
	return Tokens{AccessToken: at, AccessExpiresAt: now.Add(AccessTTL).UTC().Truncate(time.Second), RefreshToken: rt}, nil
}

// Authenticate resolves an access token to its user and device.
func (s *Store) Authenticate(ctx context.Context, token string) (User, string, error) {
	if !strings.HasPrefix(token, "ma_") {
		return User{}, "", ErrInvalidToken
	}
	var u User
	var deviceID string
	err := s.db.QueryRowContext(ctx, `SELECT u.id,u.email,d.id FROM tokens t JOIN devices d ON d.id=t.device_id JOIN users u ON u.id=d.user_id
		WHERE t.hash=? AND t.kind='access' AND t.expires_at>?`, hashToken(token), s.unix()).Scan(&u.ID, &u.Email, &deviceID)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, "", ErrInvalidToken
	}
	if err != nil {
		return User{}, "", err
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE devices SET last_seen_at=? WHERE id=? AND last_seen_at<?`, s.unix(), deviceID, s.unix()-60)
	return u, deviceID, nil
}

// Refresh exchanges a refresh token for a new pair. A token that was already used means
// it leaked: the device is revoked and ErrTokenReuse returned.
func (s *Store) Refresh(ctx context.Context, token string) (Tokens, error) {
	if !strings.HasPrefix(token, "mr_") {
		return Tokens{}, ErrInvalidToken
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Tokens{}, err
	}
	defer tx.Rollback()
	var deviceID string
	var usedAt sql.NullInt64
	err = tx.QueryRowContext(ctx, `SELECT device_id, used_at FROM tokens WHERE hash=? AND kind='refresh' AND expires_at>?`,
		hashToken(token), s.unix()).Scan(&deviceID, &usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Tokens{}, ErrInvalidToken
	}
	if err != nil {
		return Tokens{}, err
	}
	if usedAt.Valid {
		if _, err := tx.ExecContext(ctx, `DELETE FROM devices WHERE id=?`, deviceID); err != nil {
			return Tokens{}, err
		}
		if err := tx.Commit(); err != nil {
			return Tokens{}, err
		}
		return Tokens{}, ErrTokenReuse
	}
	// Old access tokens die with the rotation; the used refresh row stays as a tripwire
	// until it expires.
	if _, err := tx.ExecContext(ctx, `UPDATE tokens SET used_at=? WHERE hash=?`, s.unix(), hashToken(token)); err != nil {
		return Tokens{}, err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM tokens WHERE device_id=? AND kind='access'`, deviceID); err != nil {
		return Tokens{}, err
	}
	t, err := s.issue(ctx, tx, deviceID)
	if err != nil {
		return Tokens{}, err
	}
	return t, tx.Commit()
}

func (s *Store) DeleteDevice(ctx context.Context, userID, deviceID string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM devices WHERE id=? AND user_id=?`, deviceID, userID)
	return affected(res, err)
}

func (s *Store) ListDevices(ctx context.Context, userID string) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,name,platform,COALESCE(push_token,''),created_at,last_seen_at FROM devices WHERE user_id=? ORDER BY last_seen_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Device
	for rows.Next() {
		d := Device{UserID: userID}
		if err := rows.Scan(&d.ID, &d.Name, &d.Platform, &d.PushToken, &d.CreatedAt, &d.LastSeenAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// SetPush registers a push token. A token belongs to one device: an app reinstall or a
// different user signing in on the same phone must not keep receiving the old pushes.
func (s *Store) SetPush(ctx context.Context, deviceID, provider, token string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if token != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE devices SET push_provider=NULL, push_token=NULL WHERE push_token=? AND id<>?`, token, deviceID); err != nil {
			return err
		}
	}
	var p, t any
	if token != "" {
		p, t = provider, token
	}
	if _, err := tx.ExecContext(ctx, `UPDATE devices SET push_provider=?, push_token=? WHERE id=?`, p, t, deviceID); err != nil {
		return err
	}
	return tx.Commit()
}

// ClearPushToken drops a token FCM reported as unregistered.
func (s *Store) ClearPushToken(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE devices SET push_provider=NULL, push_token=NULL WHERE push_token=?`, token)
	return err
}

func (s *Store) PurgeExpired(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM tokens WHERE expires_at<=?`, s.unix())
	if err == nil {
		// Devices whose refresh tokens all expired are dead sessions.
		_, err = s.db.ExecContext(ctx, `DELETE FROM devices WHERE NOT EXISTS (SELECT 1 FROM tokens t WHERE t.device_id=devices.id)`)
	}
	return err
}

// ---- accounts ----

type Account struct {
	ID          string
	UserID      string
	Email       string
	DisplayName string
	Username    string
	Settings    model.Settings
	SecretKID   string
	Secret      []byte
	LastError   string
}

const accountCols = `id,user_id,email,display_name,username,incoming_protocol,incoming_host,incoming_port,incoming_security,
	smtp_host,smtp_port,smtp_security,caldav_url,carddav_url,secret_kid,secret,last_error`

func scanAccount(sc interface{ Scan(...any) error }) (Account, error) {
	var a Account
	in, out := &a.Settings.Incoming, &a.Settings.Outgoing
	err := sc.Scan(&a.ID, &a.UserID, &a.Email, &a.DisplayName, &a.Username, &in.Protocol, &in.Host, &in.Port, &in.Security,
		&out.Host, &out.Port, &out.Security, &a.Settings.CalDAVURL, &a.Settings.CardDAVURL, &a.SecretKID, &a.Secret, &a.LastError)
	return a, err
}

// SaveAccount inserts the account or, if the user already has one for this email,
// replaces its settings and secret (used on re-login after a password change).
func (s *Store) SaveAccount(ctx context.Context, a Account) (Account, error) {
	now := s.unix()
	in, out := a.Settings.Incoming, a.Settings.Outgoing
	err := s.db.QueryRowContext(ctx, `INSERT INTO accounts(`+accountCols+`,created_at,updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'',?,?)
		ON CONFLICT(user_id,email) DO UPDATE SET display_name=excluded.display_name, username=excluded.username,
		  incoming_protocol=excluded.incoming_protocol, incoming_host=excluded.incoming_host, incoming_port=excluded.incoming_port,
		  incoming_security=excluded.incoming_security, smtp_host=excluded.smtp_host, smtp_port=excluded.smtp_port,
		  smtp_security=excluded.smtp_security, caldav_url=excluded.caldav_url, carddav_url=excluded.carddav_url,
		  secret_kid=excluded.secret_kid, secret=excluded.secret, last_error='', updated_at=excluded.updated_at
		RETURNING id`,
		a.ID, a.UserID, strings.ToLower(a.Email), a.DisplayName, a.Username, in.Protocol, in.Host, in.Port, in.Security,
		out.Host, out.Port, out.Security, a.Settings.CalDAVURL, a.Settings.CardDAVURL, a.SecretKID, a.Secret, now, now).Scan(&a.ID)
	return a, err
}

func (s *Store) GetAccount(ctx context.Context, userID, accountID string) (Account, error) {
	a, err := scanAccount(s.db.QueryRowContext(ctx, `SELECT `+accountCols+` FROM accounts WHERE id=? AND user_id=?`, accountID, userID))
	if errors.Is(err, sql.ErrNoRows) {
		return a, ErrNotFound
	}
	return a, err
}

func (s *Store) ListAccounts(ctx context.Context, userID string) ([]Account, error) {
	return s.queryAccounts(ctx, `SELECT `+accountCols+` FROM accounts WHERE user_id=? ORDER BY created_at`, userID)
}

// WatchedAccounts are accounts whose user has at least one live device; nobody needs
// push for the rest.
func (s *Store) WatchedAccounts(ctx context.Context) ([]Account, error) {
	return s.queryAccounts(ctx, `SELECT `+accountCols+` FROM accounts a WHERE EXISTS (SELECT 1 FROM devices d WHERE d.user_id=a.user_id)`)
}

func (s *Store) queryAccounts(ctx context.Context, q string, args ...any) ([]Account, error) {
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Account
	for rows.Next() {
		a, err := scanAccount(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (s *Store) DeleteAccount(ctx context.Context, userID, accountID string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM accounts WHERE id=? AND user_id=?`, accountID, userID)
	return affected(res, err)
}

func (s *Store) SetAccountError(ctx context.Context, accountID, msg string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE accounts SET last_error=?, updated_at=? WHERE id=?`, msg, s.unix(), accountID)
	return err
}

// ---- POP3 index ----

type Pop3Message struct {
	ID      int64
	UIDL    string
	From    model.Address
	Subject string
	SentAt  time.Time
	Size    int64
	Seen    bool
	Flagged bool
}

func (s *Store) Pop3UIDLs(ctx context.Context, accountID string) (map[string]int64, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT uidl,id FROM pop3_messages WHERE account_id=?`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int64{}
	for rows.Next() {
		var u string
		var id int64
		if err := rows.Scan(&u, &id); err != nil {
			return nil, err
		}
		out[u] = id
	}
	return out, rows.Err()
}

func (s *Store) Pop3Insert(ctx context.Context, accountID string, m Pop3Message) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO pop3_messages(account_id,uidl,from_name,from_email,subject,sent_at,size) VALUES(?,?,?,?,?,?,?)
		ON CONFLICT(account_id,uidl) DO NOTHING`, accountID, m.UIDL, m.From.Name, m.From.Email, m.Subject, m.SentAt.Unix(), m.Size)
	return err
}

func (s *Store) Pop3Remove(ctx context.Context, accountID string, ids []int64) error {
	for _, id := range ids {
		if _, err := s.db.ExecContext(ctx, `DELETE FROM pop3_messages WHERE account_id=? AND id=?`, accountID, id); err != nil {
			return err
		}
	}
	return nil
}

const pop3Cols = `id,uidl,from_name,from_email,subject,sent_at,size,seen,flagged`

func scanPop3(sc interface{ Scan(...any) error }) (Pop3Message, error) {
	var m Pop3Message
	var sent int64
	err := sc.Scan(&m.ID, &m.UIDL, &m.From.Name, &m.From.Email, &m.Subject, &sent, &m.Size, &m.Seen, &m.Flagged)
	m.SentAt = time.Unix(sent, 0).UTC()
	return m, err
}

// Pop3List pages newest first; before=0 means from the top.
func (s *Store) Pop3List(ctx context.Context, accountID string, before int64, limit int) ([]Pop3Message, error) {
	if before <= 0 {
		before = 1 << 62
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+pop3Cols+` FROM pop3_messages WHERE account_id=? AND id<? ORDER BY id DESC LIMIT ?`,
		accountID, before, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Pop3Message
	for rows.Next() {
		m, err := scanPop3(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) Pop3Get(ctx context.Context, accountID string, id int64) (Pop3Message, error) {
	m, err := scanPop3(s.db.QueryRowContext(ctx, `SELECT `+pop3Cols+` FROM pop3_messages WHERE account_id=? AND id=?`, accountID, id))
	if errors.Is(err, sql.ErrNoRows) {
		return m, ErrNotFound
	}
	return m, err
}

func (s *Store) Pop3Counts(ctx context.Context, accountID string) (total, unread int, err error) {
	err = s.db.QueryRowContext(ctx, `SELECT COUNT(*), COALESCE(SUM(1-seen),0) FROM pop3_messages WHERE account_id=?`, accountID).Scan(&total, &unread)
	return
}

func (s *Store) Pop3SetFlags(ctx context.Context, accountID string, id int64, seen, flagged *bool) error {
	res, err := s.db.ExecContext(ctx, `UPDATE pop3_messages SET seen=COALESCE(?,seen), flagged=COALESCE(?,flagged) WHERE account_id=? AND id=?`,
		seen, flagged, accountID, id)
	return affected(res, err)
}

// ---- DAV change detection ----

func (s *Store) SwapDigest(ctx context.Context, accountID, kind, digest string) (changed bool, err error) {
	var old string
	err = s.db.QueryRowContext(ctx, `SELECT digest FROM dav_state WHERE account_id=? AND kind=?`, accountID, kind).Scan(&old)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	first := errors.Is(err, sql.ErrNoRows)
	if old == digest && !first {
		return false, nil
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO dav_state(account_id,kind,digest) VALUES(?,?,?) ON CONFLICT(account_id,kind) DO UPDATE SET digest=excluded.digest`,
		accountID, kind, digest)
	return !first && err == nil, err
}

// ---- audit ----

func (s *Store) Audit(ctx context.Context, userID, deviceID, event, ip string) {
	_, _ = s.db.ExecContext(ctx, `INSERT INTO audit_log(user_id,device_id,event,ip,created_at) VALUES(?,?,?,?,?)`,
		userID, deviceID, event, ip, s.unix())
}

func affected(res sql.Result, err error) error {
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}
