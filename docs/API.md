# Master API contract (v1)

The master is the only thing a slave (client app) talks to. Slaves never connect to
IMAP/POP3/SMTP/CalDAV/CardDAV servers directly and never see mail-server credentials
after login.

- Transport: HTTPS only. JSON bodies, `snake_case`, UTF-8. Request bodies are limited
  to 1 MiB, except `POST /send` (25 MiB).
- Unknown JSON fields are rejected with `400 bad_request`.
- Times are RFC 3339 in UTC (`2026-10-18T09:30:00Z`).
- Authenticated calls send `Authorization: Bearer <access_token>`.
- Errors always look like this:

```json
{ "error": { "code": "invalid_credentials", "message": "human readable" } }
```

| status | code | meaning |
| --- | --- | --- |
| 400 | `bad_request` | malformed or invalid input |
| 401 | `unauthorized` | missing, expired or revoked token (client should refresh once, then log out) |
| 401 | `invalid_credentials` | mail server rejected the login |
| 403 | `forbidden` | policy forbids this (e.g. custom servers disabled) |
| 404 | `not_found` | |
| 409 | `conflict` | ETag mismatch on calendar/contact update |
| 413 | `too_large` | |
| 422 | `discovery_failed` | could not work out server settings; send `server` explicitly |
| 429 | `rate_limited` | `Retry-After` header is set |
| 502 | `upstream_error` | the mail/DAV server failed or is unreachable |

## Shared types

```jsonc
// ServerSettings — what an account connects to. Never contains credentials.
{
  "incoming": { "protocol": "imap", "host": "imap.example.com", "port": 993, "security": "tls" },
  "outgoing": { "host": "smtp.example.com", "port": 465, "security": "tls" },
  "caldav_url": "https://dav.example.com/",   // optional
  "carddav_url": "https://dav.example.com/"   // optional
}
// protocol: "imap" | "pop3"; security: "tls" | "starttls"
// ("none" is only accepted if the master's policy allowlists the host).

// Account
{ "id": "uuid", "email": "a@example.com", "display_name": "Ana",
  "incoming_protocol": "imap", "has_calendar": true, "has_contacts": true,
  "last_error": "" }

// Address
{ "name": "Ana", "email": "a@example.com" }
```

## Auth and devices

Each slave is a **device**. Login verifies the password against the account's incoming
mail server. There is no separate master password. The access token lives 15 minutes.
The refresh token lives 60 days and rotates on every use. Reusing an old refresh token
revokes the device.

| method | path | body → response |
| --- | --- | --- |
| POST | `/v1/auth/login` | `{email, password, device:{name, platform}, server?: ServerSettings, username?: string}` → `Tokens + {user:{id,email}, account_id}` |
| POST | `/v1/auth/refresh` | `{refresh_token}` → `Tokens` |
| POST | `/v1/auth/logout` | → `204`, revokes this device |
| GET | `/v1/me` | → `{user:{id,email}, device_id, accounts:[Account]}` |
| GET | `/v1/devices` | → `[{id, name, platform, created_at, last_seen_at, current}]` |
| DELETE | `/v1/devices/{id}` | → `204` |
| PUT | `/v1/devices/current/push` | `{provider:"fcm", token}` → `204` |
| DELETE | `/v1/devices/current/push` | → `204` |
| POST | `/v1/discover` | `{email}` → `ServerSettings` (unauthenticated, rate limited) |

`Tokens = {access_token, access_expires_at, refresh_token}`.
`platform` is one of `android, ios, macos, windows, linux, web`.

## Accounts

| method | path | body → response |
| --- | --- | --- |
| GET | `/v1/accounts` | → `[Account]` |
| POST | `/v1/accounts` | `{email, password, display_name?, username?, server?}` → `Account` (credentials are verified first) |
| DELETE | `/v1/accounts/{aid}` | → `204` (you cannot delete the account you logged in with while it is your only account) |

## Mail

Folder names travel in the `folder` query parameter, URL-encoded. Message ids are
opaque, URL-safe strings: `<uidvalidity>.<uid>` for IMAP, a number for POP3. POP3
accounts expose a single folder, `INBOX`. The master keeps their read and flagged
state.

| method | path | body → response |
| --- | --- | --- |
| GET | `/v1/accounts/{aid}/folders` | → `[{name, role, unread, total}]`, where `role` is one of `inbox, sent, drafts, trash, junk, archive, ""` |
| GET | `/v1/accounts/{aid}/messages?folder=INBOX&before=<id>&limit=50` | → `{messages:[Summary], next_before?: id}`, newest first, `limit` 1..100 |
| GET | `/v1/accounts/{aid}/messages/{id}?folder=` | → `Message` (does **not** mark it read) |
| GET | `/v1/accounts/{aid}/messages/{id}/attachments/{index}?folder=` | → raw bytes, `Content-Disposition: attachment` |
| PATCH | `/v1/accounts/{aid}/messages/{id}?folder=` | `{seen?: bool, flagged?: bool}` → `204` |
| POST | `/v1/accounts/{aid}/messages/{id}/move?folder=` | `{to: "Archive"}` → `204` (IMAP only) |
| DELETE | `/v1/accounts/{aid}/messages/{id}?folder=` | → `204` (moves to Trash, or removes it permanently when already in Trash or on POP3) |
| POST | `/v1/accounts/{aid}/send` | `Outgoing` → `202 {message_id}` |

```jsonc
// Summary
{ "id": "1700000000.42", "folder": "INBOX", "from": Address, "to": [Address],
  "subject": "Hi", "date": "2026-10-18T09:30:00Z", "seen": false, "flagged": false,
  "answered": false, "has_attachments": true, "size": 20480 }

// Message = Summary + these fields
{ "cc": [Address], "reply_to": [Address], "message_id": "<x@y>", "in_reply_to": "<a@b>",
  "references": ["<a@b>"], "text": "plain body", "html": "sanitized html",
  "remote_content_blocked": true,
  "attachments": [{ "index": 0, "filename": "a.pdf", "content_type": "application/pdf", "size": 1234 }] }

// Outgoing
{ "to": [Address], "cc": [Address], "bcc": [Address], "subject": "Hi",
  "text": "body", "html": "<p>body</p>",          // html optional
  "in_reply_to": "<a@b>", "references": ["<a@b>"],
  "attachments": [{ "filename": "a.pdf", "content_type": "application/pdf", "data_base64": "..." }] }
```

The master sanitizes `html` with an allowlist. Scripts, forms, iframes, event handlers
and `style` attributes are removed. Remote images are stripped by default and
`remote_content_blocked` is set. Clients must render `html` without JavaScript.

## Calendar (CalDAV)

| method | path | body → response |
| --- | --- | --- |
| GET | `/v1/accounts/{aid}/calendars` | → `[{id, name, color}]` |
| GET | `/v1/accounts/{aid}/events?calendar=<id>&from=<t>&to=<t>` | → `[Event]` (range ≤ 366 days) |
| PUT | `/v1/accounts/{aid}/events` | `EventInput` → `Event` |
| DELETE | `/v1/accounts/{aid}/events?id=<id>&etag=<etag>` | → `204` |

```jsonc
// Event
{ "id": "/cal/work/abc.ics", "calendar": "/cal/work/", "etag": "\"123\"", "uid": "abc",
  "summary": "Standup", "description": "", "location": "",
  "start": "2026-10-19T09:00:00Z", "end": "2026-10-19T09:15:00Z", "all_day": false,
  "recurrence": "FREQ=DAILY" }   // recurrence is read-only in v1
// EventInput: {calendar, id?, etag?, summary, description?, location?, start, end, all_day}
// no id → create. id + etag → update (409 if the etag is stale).
```

## Contacts (CardDAV)

| method | path | body → response |
| --- | --- | --- |
| GET | `/v1/accounts/{aid}/addressbooks` | → `[{id, name}]` |
| GET | `/v1/accounts/{aid}/contacts?addressbook=<id>` | → `[Contact]` |
| PUT | `/v1/accounts/{aid}/contacts` | `ContactInput` → `Contact` |
| DELETE | `/v1/accounts/{aid}/contacts?id=<id>&etag=<etag>` | → `204` |

```jsonc
// Contact
{ "id": "/card/default/x.vcf", "addressbook": "/card/default/", "etag": "\"1\"", "uid": "x",
  "full_name": "Ana Lima", "emails": [{"type": "work", "value": "a@example.com"}],
  "phones": [{"type": "cell", "value": "+15550100"}], "org": "", "title": "", "note": "" }
// ContactInput: {addressbook, id?, etag?, full_name, emails?, phones?, org?, title?, note?}
```

## Realtime

`GET /v1/stream` upgrades to a WebSocket. The client's first text frame must be
`{"type":"auth","token":"<access_token>"}` and must arrive within 10 seconds. Otherwise
the server closes the socket with code 4401. Browsers cannot set headers on a WebSocket,
and a token in the URL would end up in logs. The server then sends events like these:

```jsonc
{ "type": "ready" }
{ "type": "mail.new",          "account_id": "uuid", "folder": "INBOX" }
{ "type": "mail.changed",      "account_id": "uuid", "folder": "INBOX" }
{ "type": "calendar.changed",  "account_id": "uuid" }
{ "type": "contacts.changed",  "account_id": "uuid" }
{ "type": "account.error",     "account_id": "uuid", "message": "login failed" }
```

Events are hints. They carry no message content, and the client re-fetches what it shows.
When a device has no open stream, `mail.new` goes out as an FCM data message with the
same JSON fields. The visible notification text is generic ("New mail in a@example.com"),
so no subject or sender passes through Google or Apple.

## Health

`GET /healthz` → `200 ok` (process up). `GET /readyz` → `200` once the database is open.

## Wanted by the client (not in v1)

The app works without these; each one would let it do more.

- `GET /v1/accounts/{aid}/messages?folder=&q=<text>`: server-side search. Today the app
  searches only what it has saved on the device.
- `POST /v1/accounts/{aid}/messages/{id}/invite/reply` with `{response: accepted|declined|tentative}`:
  sends the iTIP reply for a meeting invitation. Today the app can only add the event to
  the calendar.
- A `unread` count across accounts (for an app badge) on `GET /v1/me`.
