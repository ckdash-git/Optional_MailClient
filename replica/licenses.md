# Licences: what we use, borrow and avoid (verified 2026-10-18)

Every licence below was read from the project's own LICENSE file (raw.githubusercontent)
or its pub.dev or Go module record, not from memory. The full Go dependency closure is
re-checked on every build by `server/scripts/check-licenses.sh`, which fails on anything
GPL, LGPL, AGPL, MPL, SSPL or BUSL.

## Shipped in our product

**Master (Go).** 25 modules, all permissive: MIT, BSD-2/3, ISC, Apache-2.0 and public
domain.
- emersion go-imap/v2, go-smtp, go-sasl, go-message, go-webdav, go-ical and go-vcard are MIT.
- bluemonday is BSD-3.
- modernc.org/sqlite is BSD-3; SQLite itself is public domain.
- coder/websocket is ISC.
- golang.org/x/* is BSD-3.
- cloud.google.com/go/compute/metadata is Apache-2.0 and needs a NOTICE.

The Docker image ships `/THIRD_PARTY_NOTICES.txt`.

**App (Flutter).** Only MIT, BSD and Apache packages: http, web_socket_channel,
flutter_secure_storage, flutter_widget_from_html_core, firebase_messaging (the plugin is
BSD; the native Firebase SDKs fall under Google's terms) and similar. The About screen
shows every package licence through Flutter's `LicenseRegistry`. Because protocols live
in the master, the app needs **no** MPL code such as enough_mail.

## Code we may borrow, with attribution

- **thunderbird/thunderbird-android** (Apache-2.0): IMAP edge cases, autoconfig and
  folder-sync logic, to port. Keep the NOTICE. **Do not use the Thunderbird or K-9 names
  or logos**; the Apache licence grants no trademark rights.
- **thunderbird/thunderbird-ios** (MPL-2.0): any file we copy stays MPL and its
  modifications must be published. Prefer reading it to copying it.
- **linagora/jmap-dart-client** (MIT): a reference for a future JMAP adapter.

## UX reference only; never copy code

These are GPL, AGPL or proprietary:
- FairEmail (GPL-3)
- Mailspring (GPL-3)
- Tuta (GPL-3)
- Proton Mail (GPL-3)
- K-9 forks under GPL
- DAVx5 (GPL-3)
- Etar (GPL-3)
- Fossify Calendar and Contacts (GPL-3)
- Nextcloud Mail (AGPL)
- tmail-flutter (AGPL)
- Maily / enough_mail_app (GPL-3)
- Syncfusion calendar (proprietary; needs a paid licence above $1M revenue or 5 developers)

## Why not fork Thunderbird for Android or iOS?

The Android app is Apache-2.0, so a fork would be legal. It is also a large native Kotlin
codebase that does mail only and holds IDLE on the device, which is the push model users
complain about. The iOS app is MPL-2.0, young, and also mail only. Building a thin
Flutter client on a small Go master gave us mail, calendar, contacts and server-side push
on every platform with less code than either fork.

Not verified from here: Ltt.rs's origin licence (the GitHub repo returns 404), Mozilla's
trademark policy text, and Google's Firebase SDK terms.
