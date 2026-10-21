# Master (gateway server)

One static Go binary. It holds the connections to your users' mail, calendar and
contacts servers (IMAP IDLE, POP3, SMTP, CalDAV, CardDAV) and serves the app over a
small JSON + WebSocket API ([docs/API.md](../docs/API.md)).

## Run it

```bash
go build -o master ./cmd/master          # Go 1.26+
./master genkey                          # prints a vault key: k<id>:<base64>
export MASTER_VAULT_KEYS='<output of genkey>'
export MASTER_TLS_CERT=/etc/master/tls.crt MASTER_TLS_KEY=/etc/master/tls.key
./master
```

With Docker, behind a TLS-terminating reverse proxy:

```bash
docker build -t master .
docker run -d --name master -p 127.0.0.1:8443:8443 -v master-data:/data \
  -e MASTER_VAULT_KEYS="$KEYS" -e MASTER_BEHIND_PROXY=true \
  -e MASTER_TRUSTED_PROXIES=172.17.0.1/32 master
```

The image is distroless, has no shell and runs as uid 65532. It ships
`/THIRD_PARTY_NOTICES.txt`. If the licence check finds a non-permissive dependency, the
build fails.

## Configuration

| variable | default | meaning |
| --- | --- | --- |
| `MASTER_VAULT_KEYS` | **required** | `kid:base64key[,kid:base64key…]`. The first key encrypts; every listed key can decrypt. Keep this in a secret manager. |
| `MASTER_TLS_CERT`, `MASTER_TLS_KEY` | | Serve HTTPS directly. |
| `MASTER_BEHIND_PROXY` | `false` | Set to `true` to serve plain HTTP behind a TLS proxy. Without TLS or this flag the master refuses to start. |
| `MASTER_TRUSTED_PROXIES` | | CIDRs whose `X-Forwarded-For` header is believed (for rate limits and audit IPs). |
| `MASTER_LISTEN` | `:8443` | Listen address. |
| `MASTER_DB` | `data/master.db` | SQLite file, created with mode 0600. |
| `MASTER_PROFILES` | | JSON file mapping domains to server settings (this is your *server config*; see `deploy/profiles.example.json`). A profile always wins over autodiscovery and over settings the user types. |
| `MASTER_ALLOW_CUSTOM_SERVERS` | `true` | Set to `false` to allow only domains in the profiles file (a locked-down enterprise deployment). |
| `MASTER_ALLOW_NETWORKS` | | CIDRs the master may connect to even though they are private (an on-prem mail server on `10.0.0.0/8`). Plaintext (`security: none`) is only allowed to these hosts. |
| `MASTER_FCM_CREDENTIALS` | | Google service-account JSON with the Firebase Messaging scope. Without it, devices get updates only while the app is open. |
| `MASTER_CORS_ORIGINS` | | Comma-separated https origins of a web client. |
| `MASTER_POP3_INTERVAL` | `2m` | POP3 poll interval (minimum 30s). |
| `MASTER_DAV_INTERVAL` | `5m` | CalDAV/CardDAV change-poll interval (minimum 30s). |

## Security model

- **Credentials**: mail passwords are sealed with AES-256-GCM. The ciphertext is bound
  to its account id, so it cannot be moved to another row. To rotate keys, put the new
  key first and restart. Accounts are re-sealed with it at their next login. Remove the
  old key once no rows reference it.
- **Identity**: a user is *the login name that authenticated, on a specific incoming
  server*, not the email address typed next to it. Claiming `ceo@corp.com` with your
  own username, or through a server you control, gives you a different, empty user.
- **Tokens**: random 256-bit values that are stored only as SHA-256 hashes. Access
  tokens live 15 minutes. Refresh tokens are single-use and rotate; reusing one revokes
  the device.
- **SSRF**: every outbound connection goes through a dialer that refuses loopback,
  private, link-local, CGNAT and metadata addresses. The check runs on the *resolved*
  IP, so DNS rebinding does not get around it.
- **TLS**: upstream connections need TLS 1.2+ with certificate verification. STARTTLS
  is mandatory when selected and is never downgraded.
- **HTML mail**: sanitised with an allowlist (bluemonday). Remote images, which are
  usually tracking pixels, are removed. Attachments are always served as
  `application/octet-stream` with `Content-Disposition: attachment`.
- **Rate limits**: login, refresh, discovery and stream connects are limited per client
  IP. Login is also limited per address, which protects users' mailboxes from lockout.
  The API is limited per user.
- **Logs**: method, route pattern, status and duration only. No query strings, bodies,
  addresses or tokens.
- **Push payloads**: they carry ids only, never subjects or senders.

## Scaling notes

One node handles thousands of accounts, at about one goroutine and one TCP connection per
IMAP account. Beyond that, shard accounts across nodes and move the store to Postgres.
The SQL is plain and portable.

## Tests

```bash
go test -race ./...            # in-process IMAP, SMTP, POP3, CalDAV, CardDAV servers; no network
./scripts/check-licenses.sh    # fails on any non-permissive dependency
```
