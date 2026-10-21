# Optional Mail

A lightweight mail, calendar and contacts suite for any standards-based server: IMAP or
POP3 with SMTP for mail, CalDAV for calendars, CardDAV for contacts. It delivers
real-time push to Android, iOS, desktop and web.

```
 apps (Flutter, thin)  ──HTTPS + WebSocket──►  master (one Go binary)  ──►  IMAP / POP3 / SMTP
        ▲                                       IDLE · polling · vault       CalDAV / CardDAV
        └──────────── FCM wake-up (no content) ─┘
```

- **`server/`**: the *master*. It holds connections to mail servers, keeps one IMAP IDLE
  per account, encrypts credentials, sanitises HTML, and pushes changes to devices.
  See [server/README.md](server/README.md).
- **`lib/`**: the *slave* app. It talks only to the master and contains no protocol
  code. See [docs/CLIENT.md](docs/CLIENT.md).
- **`docs/API.md`**: the contract between the two.
- **`replica/`**: the product research and design: requirements, 170 real user reviews
  of today's clients, the architecture, and licence decisions.

## Quick start (development)

```bash
# master
cd server
export MASTER_VAULT_KEYS=$(go run ./cmd/master genkey) MASTER_BEHIND_PROXY=true MASTER_LISTEN=127.0.0.1:8443
go run ./cmd/master

# app (another terminal, repository root)
flutter pub get
flutter run        # sign in with server URL http://10.0.2.2:8443 (Android emulator) or http://localhost:8443
```

In release builds the app accepts only `https://` master URLs. In production, run the
master behind TLS (see `server/README.md`).

## Checks

```bash
(cd server && go vet ./... && go test -race ./... && ./scripts/check-licenses.sh)
flutter analyze && flutter test && ./scripts/check-app-licenses.sh
```

CI (`.github/workflows/ci.yml`) also runs these checks, plus gofmt, `dart format` and
`govulncheck`.

## Licensing

The product is closed source. Every dependency is permissively licensed (MIT, BSD,
Apache-2.0, ISC); both licence scripts fail the build otherwise. See
[replica/licenses.md](replica/licenses.md), including the list of projects that are
for UX reference only.
