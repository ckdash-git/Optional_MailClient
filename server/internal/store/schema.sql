-- Master database. SQLite (WAL), one file. All ids are random UUIDv4 text, all times are
-- unix seconds UTC. Authorisation: every query in store.go that touches user data takes
-- the user id and filters on it (no row-level security in SQLite).
PRAGMA foreign_keys = ON;

-- A user is *a login name as verified by one specific incoming server*. Keying on the
-- email address would let anyone with a server of their own (or their own username on
-- the real server) "log in" as ceo@corp.com and inherit the real owner's accounts.
CREATE TABLE IF NOT EXISTS users (
  id          TEXT PRIMARY KEY,
  email       TEXT NOT NULL,                 -- lower-cased
  identity    TEXT NOT NULL UNIQUE,          -- username + protocol + host + port
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  platform      TEXT NOT NULL CHECK (platform IN ('android','ios','macos','windows','linux','web')),
  push_provider TEXT CHECK (push_provider IN ('fcm')),
  push_token    TEXT,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);

-- Only SHA-256 hashes of tokens are stored. A refresh token is single use: used_at is set
-- when it is exchanged; presenting it again revokes the whole device (theft detection).
CREATE TABLE IF NOT EXISTS tokens (
  hash        BLOB PRIMARY KEY,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('access','refresh')),
  expires_at  INTEGER NOT NULL,
  used_at     INTEGER
);
CREATE INDEX IF NOT EXISTS tokens_device ON tokens(device_id);
CREATE INDEX IF NOT EXISTS tokens_expiry ON tokens(expires_at);

CREATE TABLE IF NOT EXISTS accounts (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email             TEXT NOT NULL,
  display_name      TEXT NOT NULL DEFAULT '',
  username          TEXT NOT NULL,
  incoming_protocol TEXT NOT NULL CHECK (incoming_protocol IN ('imap','pop3')),
  incoming_host     TEXT NOT NULL,
  incoming_port     INTEGER NOT NULL CHECK (incoming_port BETWEEN 1 AND 65535),
  incoming_security TEXT NOT NULL CHECK (incoming_security IN ('tls','starttls','none')),
  smtp_host         TEXT NOT NULL,
  smtp_port         INTEGER NOT NULL CHECK (smtp_port BETWEEN 1 AND 65535),
  smtp_security     TEXT NOT NULL CHECK (smtp_security IN ('tls','starttls','none')),
  caldav_url        TEXT NOT NULL DEFAULT '',
  carddav_url       TEXT NOT NULL DEFAULT '',
  secret_kid        TEXT NOT NULL,
  secret            BLOB NOT NULL,           -- vault-sealed password, AAD = account id
  last_error        TEXT NOT NULL DEFAULT '',
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  UNIQUE (user_id, email)
);
CREATE INDEX IF NOT EXISTS accounts_user ON accounts(user_id);

-- POP3 has no server-side flags or stable ids beyond UIDL; the master keeps both.
CREATE TABLE IF NOT EXISTS pop3_messages (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id   TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  uidl         TEXT NOT NULL,
  from_name    TEXT NOT NULL DEFAULT '',
  from_email   TEXT NOT NULL DEFAULT '',
  subject      TEXT NOT NULL DEFAULT '',
  sent_at      INTEGER NOT NULL,
  size         INTEGER NOT NULL,
  seen         INTEGER NOT NULL DEFAULT 0,
  flagged      INTEGER NOT NULL DEFAULT 0,
  UNIQUE (account_id, uidl)
);
CREATE INDEX IF NOT EXISTS pop3_account_id ON pop3_messages(account_id, id DESC);

-- Change detection for CalDAV/CardDAV collections (sync token, ctag or etag digest).
CREATE TABLE IF NOT EXISTS dav_state (
  account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('calendar','contacts')),
  digest      TEXT NOT NULL,
  PRIMARY KEY (account_id, kind)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT,
  device_id   TEXT,
  event       TEXT NOT NULL,
  ip          TEXT NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS audit_user ON audit_log(user_id, created_at);
