# Gates: rebuild as a master/slave mail suite

The completion ledger for this rebuild (unlazy format). A runnable gate is met only
when its command exits 0 **and** its output contains the EXPECT token. Commands run from
the repository root, in bash.

## Master (server/)

- [x] G1 The master builds as a static, cgo-free binary.
  CHECK: cd server && CGO_ENABLED=0 go build -trimpath -o /dev/null ./cmd/master && echo GATE_BUILD_OK
  EXPECT: GATE_BUILD_OK
- [x] G2 Go code is gofmt-clean and passes go vet.
  CHECK: cd server && test -z "$(gofmt -l .)" && go vet ./... && echo GATE_VET_OK
  EXPECT: GATE_VET_OK
- [x] G3 All server tests pass under the race detector. They cover IMAP, POP3, SMTP,
  CalDAV, CardDAV, vault, SSRF guard, tokens and the API end to end.
  CHECK: cd server && CGO_ENABLED=1 go test -race -count=1 ./... && echo GATE_TESTS_OK
  EXPECT: GATE_TESTS_OK
- [x] G4 The end-to-end flow passes: login, mail, send, calendar, contacts, WebSocket
  push, FCM for offline devices, refresh-token reuse revoking the device, and the
  identity-spoof regression.
  CHECK: cd server && go test -count=1 -v -run 'TestEndToEnd|TestLoginCannotClaimAnotherUsersAddress|TestLoginRateLimit' ./internal/api 2>&1 | grep -c -- '--- PASS' | grep -qx 3 && echo GATE_E2E_OK
  EXPECT: GATE_E2E_OK
- [x] G5 Every module linked into the master is permissively licensed. Negative control:
  a GPL module makes the script exit 1, verified on 2026-10-18.
  CHECK: cd server && ./scripts/check-licenses.sh /tmp/notices.txt
  EXPECT: LICENSES_OK
- [ ] G6 govulncheck reports no reachable vulnerabilities. (MANUAL: vuln.go.dev is
  blocked from this sandbox. CI runs it on push; record the CI run here.)

## App (lib/)

- [x] G7 `flutter analyze` is clean under strict analysis options.
  CHECK: /opt/sdk/flutter/bin/flutter analyze --suppress-analytics 2>&1 | tail -1
  EXPECT: No issues found!
- [x] G8 Flutter unit and widget tests pass.
  CHECK: /opt/sdk/flutter/bin/flutter test --suppress-analytics 2>&1 | tail -1
  EXPECT: All tests passed!
- [x] G9 Every pub.dev package in pubspec.lock is permissively licensed.
  CHECK: ./scripts/check-app-licenses.sh
  EXPECT: APP_LICENSES_OK

## Repository

- [x] G10 No secrets or the old hard-coded OAuth client id are tracked.
  CHECK: ! git grep -nIE '527193526235|googleusercontent\.com|BEGIN [A-Z ]*PRIVATE KEY|AIza[0-9A-Za-z_-]{35}' -- . ':!GATES.md' && echo GATE_NOSECRETS_OK
  EXPECT: GATE_NOSECRETS_OK
- [x] G11 The obsolete Gmail-API prototype is gone from lib/.
  CHECK: ! grep -rlE 'googleapis|google_sign_in|gmail' lib pubspec.yaml && echo GATE_OLD_CODE_GONE
  EXPECT: GATE_OLD_CODE_GONE

## Owner decisions (manual, open)

- [ ] M1 The owner confirms the master/slave interpretation in `replica/architecture.md`.
- [ ] M2 The owner decides who runs the master: SaaS, self-hosted, or both.
- [ ] M3 The owner provides the brand name, bundle ids, a Firebase project and OAuth clients.

## Last run

2026-10-18: all 10 runnable gates met (G1–G5, G7–G11); G6 is manual, pending CI; M1–M3 are open with the owner.
