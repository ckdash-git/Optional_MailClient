# Architecture

Product: a lightweight, commercial mail + calendar + contacts suite that works with
whatever servers an organisation runs (IMAP or POP3 + SMTP, CalDAV, CardDAV), with real-time
push. Inputs: `recon.md`, `features.csv`, `feedback.md` / `fixes.md` (170 real reviews),
and `licenses.md`.

## The shape: master and slaves

```
                 ┌───────────────────────── master (one Go binary) ─────────────────────────┐
  slave apps     │  REST + WebSocket API  ──  auth / devices / rate limits / audit         │      users' servers
 (Flutter:       │        │                                                                │
  Android, iOS,  │  mail adapters ── IMAP (IDLE) ─ POP3 (own client) ─ SMTP submission ────┼──► IMAP / POP3 / SMTP
  desktop, web)  │  dav adapters  ── CalDAV ─ CardDAV (ETag-conditional writes) ───────────┼──► CalDAV / CardDAV
      ▲   ▲      │  watcher       ── 1 IDLE per account · POP3 poll · DAV digest poll       │
      │   │      │  push hub      ── WebSocket fan-out ─ FCM (content-free) ───────────────┼──► FCM ──► APNs
      │   └──────┤  vault (AES-256-GCM) · SQLite store · SSRF-guarded dialer               │
      └ HTTPS ───┴──────────────────────────────────────────────────────────────────────────┘
```

**Why a master at all?** Real-time push. iOS does not let an app keep an IMAP IDLE
socket open in the background. Android's battery optimisation kills such sockets. That
is the #1 complaint in the review research: 37 reviews across 7 sources, plus 14 reviews
across 6 sources about the iPhone gap. The master keeps the socket open and wakes the
phone. A second benefit: the apps contain no protocol code, so they stay small, and
adding JMAP or Exchange later is a server-only change.

**What "server config" means here.** The operator's `MASTER_PROFILES` file maps each
domain to its protocol, host, port and security. A profile always wins over
autodiscovery and over anything the user types. `MASTER_ALLOW_CUSTOM_SERVERS=false`
locks the deployment to those domains. Domains without a profile are autodiscovered from
the domain's autoconfig, the Thunderbird ISPDB, or DNS SRV records.

**Unconfirmed interpretation.** The earlier master/slave discussion could not be
retrieved (see `recon.md`). Please confirm this reading or correct it.

## Stack

| layer | choice | why |
| --- | --- | --- |
| master | Go 1.26, single static binary, distroless image | ~20 MB, no runtime; goroutine-per-connection suits thousands of IDLE sockets |
| protocols | emersion go-imap v2, go-smtp, go-message, go-webdav, go-ical, go-vcard (all MIT) | one coherent, maintained family; v2 beta pinned |
| POP3 | own ~200-line client | the available libraries lack STLS and custom TLS settings |
| HTML sanitising | bluemonday (BSD-3) | allowlist-based; remote images stripped |
| storage | SQLite via modernc.org/sqlite (pure Go, BSD-3) | zero-ops, one file; the SQL ports to Postgres when we shard |
| realtime | coder/websocket (ISC) + FCM HTTP v1 over x/oauth2 | no Firebase SDK, which has a very large dependency tree |
| client | Flutter (one codebase: Android, iOS, macOS, Windows, Linux, web) | the existing repo was Flutter; thin client; permissive packages only |
| CI | GitHub Actions: vet, race tests, govulncheck, licence gates, flutter analyze/test | |

There are no microservices, no message queue and no Redis. One database.

## Schema

`server/internal/store/schema.sql`: 7 tables (`users`, `devices`, `tokens`, `accounts`,
`pop3_messages`, `dav_state`, `audit_log`). Notes:

- **Access rule**: there is no row-level security in SQLite. Instead, every store method
  that touches user data takes the user id and filters on it, and the tests check that
  another user's account is not visible.
- A user's identity is `authenticated username + protocol + host + port`, not the email
  address. Keyed on the address, anyone with a server of their own, or with their own
  login on the same server, could claim `ceo@corp.com`. A regression test checks this.
- Tokens are stored as SHA-256 hashes only. A refresh token can be used once; reusing it
  revokes the device.
- Account passwords are sealed in a vault with the account id as AAD, and a key id
  allows rotation.
- The master stores **no message bodies**. IMAP is proxied live. For POP3 it keeps only
  the UIDL index plus from, subject, date and the read/flagged state, because POP3 has
  nowhere to store them.

## API

`docs/API.md` is the contract: 28 routes, plus the WebSocket stream and two health checks.

| area | routes |
| --- | --- |
| auth / devices | login, refresh, logout, me, devices list/revoke, push token set/clear, discover |
| accounts | list, add (verified), remove |
| mail | folders, messages page, message, attachment, flags, move, delete, send |
| calendar | calendars, events (range), put event, delete event |
| contacts | address books, contacts, put contact, delete contact |
| realtime | `GET /v1/stream` (first-frame auth) |
| ops | `/healthz`, `/readyz` |

Background jobs (in-process): the watcher reconciles every minute (one IDLE per account,
a POP3 poll every 2 minutes, a DAV digest every 5 minutes), the pool is swept every
minute, and expired tokens are purged hourly. There are no inbound webhooks.

## The parts that bite

| topic | how it is handled |
| --- | --- |
| SSRF | Users type host names, so every dial checks the *resolved* IP against private, loopback, link-local, CGNAT and metadata ranges. Operators allowlist on-prem networks explicitly. |
| Identity spoofing | Users are keyed on the authenticated login plus the verifying server (above). |
| TLS downgrade | STARTTLS is mandatory when chosen, TLS 1.2+ is required, certificates are verified, and plaintext is allowed only to allowlisted hosts. |
| UIDVALIDITY | Message ids are `uidvalidity.uid`, so a stale id returns 404 instead of the wrong message. |
| Lost updates | CalDAV/CardDAV writes send `If-Match` / `If-None-Match: *` and return 409 on conflict. Updates edit the stored object in place, so alarms, attendees and photos survive. |
| Time zones | Everything is UTC on the wire. All-day events use DATE values. Recurring events are expanded server-side for the requested window, which is half-open. |
| Idempotency | Send is not retried by the server. If saving to Sent fails after a successful send, that is logged but not reported as an error, so the client never re-sends. |
| Rate limits / lockout | Limits apply per IP, per address and per user. An IMAP auth failure backs off for 15 minutes so a changed password cannot get the mailbox locked. |
| Push reliability | One IDLE per account (no per-folder storms), reconnect with jittered backoff, and a NOOP poll when the server lacks IDLE. Three failures in a row set `last_error` and publish `account.error`, so the app can show push health (F29). |
| Privacy | Push payloads carry no content. Telemetry: none. Logs hold no queries, bodies or addresses. |
| HTML mail | An allowlist sanitiser. Scripts, handlers, styles and remote images are removed, and `remote_content_blocked` is set. |
| Large mail | Message bodies are streamed from the IMAP literal and never buffered whole. Attachments stream straight to the client. |
| GDPR deletion | Deleting the account cascades to its POP3 index, DAV state and sealed secret. Deleting a device cascades to its tokens. |
| Scale ceiling | One node is roughly thousands of accounts. Beyond that, shard by account and move to Postgres. |

## Build order and status

| milestone | contents | status |
| --- | --- | --- |
| M1 vertical slice | F01–F13, F20, F29, F30 (IDLE + watchdog), F42 | **built and tested**. The master and its e2e tests are done. The app is in `lib/` |
| M2 | F14–F19 calendar/contacts/multi-account, F31 content-free iOS push, F33 iMIP | calendar, contacts and multi-account are built. iMIP is not started |
| M3 | F21 search, F22 OAuth (XOAUTH2), F23 offline cache, F24 unified inbox, F32 UnifiedPush, F35–F41 | not started |
| M4 | JMAP and Exchange adapters, recurring-event editing, direct APNs, HTML signatures | not started |

## Decisions needed from the owner

1. **Is the master/slave reading above correct?** The rest depends on it.
2. **Who runs the master?** We could host it (SaaS), customers could self-host it (it is
   one container), or both. Reviewers trust self-hostable relays (fixes.md #3).
3. **FCM vs. no-Google push** on Android. FCM is built. UnifiedPush/ntfy (F32) is a
   small addition later.
4. **OAuth for Gmail and Microsoft 365** (F22). Both providers are phasing out
   passwords for IMAP. This needs registered OAuth clients in your company's name.
5. **Brand name and bundle ids.** The Android `applicationId` and iOS bundle id are
   still placeholders.
