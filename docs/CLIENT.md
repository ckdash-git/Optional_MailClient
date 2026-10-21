# Client app

The Flutter app is a thin client of the master. It talks only to the master's
REST and WebSocket API ([API.md](API.md)) over HTTPS. It contains no IMAP, POP3,
SMTP or DAV code. The mail password goes to the master once, at sign-in or when an
account is added. After that the app keeps only master tokens.

## Layout

| path | what |
| --- | --- |
| `lib/api/models.dart` | Typed wire models. JSON is parsed by hand. Request bodies leave out unset fields, because the master rejects unknown fields. |
| `lib/api/client.dart` | `ApiClient`, `ApiException` and `parseServerUrl` (HTTPS enforcement). |
| `lib/api/session.dart` | Tokens, the user and preferences in `flutter_secure_storage`, plus the sign-out wipe. |
| `lib/api/realtime.dart` | The one WebSocket to `/v1/stream`: first-frame auth, backoff and lifecycle handling. |
| `lib/api/push.dart` | Optional Firebase Cloud Messaging. |
| `lib/ui/` | Screens for sign-in, mail, calendar, contacts and settings. Shared widgets are in `lib/ui/widgets/`. |

State is handled with `ChangeNotifier` and `InheritedWidget`. The app uses no state-management package.

## Security behaviour

- Only `https://` master URLs are accepted. Debug builds also accept `http://` for
  `localhost`, `127.0.0.1`, `::1` and `10.0.2.2`, which covers the Android emulator.
  Android release builds also set `usesCleartextTraffic=false`. iOS has no ATS
  exceptions.
- Tokens are stored only in the Keychain or Keystore (`flutter_secure_storage`).
  They never appear in URLs or logs.
- Access tokens are refreshed 60 s before they expire. A request that gets
  `401 unauthorized` triggers one more refresh. Refreshing is single-flight:
  concurrent requests share one `POST /v1/auth/refresh`, because reusing a
  rotated refresh token revokes the device. If the refresh is rejected, or a
  request still gets 401 after a successful refresh, the app signs out.
- Signing out, or being signed out, wipes secure storage and the downloaded
  attachments, and deletes the FCM token. Only the master URL and the theme
  choice are kept.
- Message HTML, which the master has already sanitised, is rendered with
  `flutter_widget_from_html_core`. There is no web view and no JavaScript. The app
  loads no network, `file:` or asset images; only inline `data:` images are shown.
  When the master reports blocked remote content, the app shows a banner. Before a
  link opens in the external browser, a dialog shows its real address.
- Android: `allowBackup=false` and `dataExtractionRules` exclude all app data
  from backups and from device-to-device transfer.

## Building

Install Flutter (stable) and run `flutter pub get`. Then:

| platform | command | notes |
| --- | --- | --- |
| Android | `flutter build apk --release` / `flutter build appbundle` | minSdk 24. Before you publish, set `applicationId` and `namespace` in `android/app/build.gradle.kts` and add a release signing config. |
| iOS | `flutter build ipa` | Set the bundle id and team in Xcode (`ios/Runner.xcworkspace`). |
| macOS | `flutter build macos` | Turn on Keychain Sharing in Xcode so that `flutter_secure_storage` works. The entitlements include `network.client` and `keychain-access-groups`. |
| Windows / Linux | `flutter build windows` / `flutter build linux` | Linux needs `libsecret-1-dev` to build and a running Secret Service, such as GNOME Keyring or KWallet. |
| Web | `flutter build web` | Serve it over HTTPS. Web builds have no push. |

CI builds an unsigned release APK (Android) and an unsigned `Runner.app` (iOS, on a macOS
runner) on every push and uploads them as workflow artifacts. Signing and store upload stay
with whoever owns the developer accounts.

Checks: `flutter analyze` (strict options in `analysis_options.yaml`), `flutter test`
and `./scripts/check-app-licenses.sh`.

## Enabling push notifications (FCM)

Push is optional. If no Firebase config is present, `Firebase.initializeApp()`
fails. The app catches the failure, logs `Push disabled`, and uses the WebSocket
only, which delivers events while the app is in the foreground. With FCM set up,
the master sends `mail.new` to devices that have no open stream. The notification
text is generic, and tapping it opens that account's inbox.

1. Create a Firebase project. Use the same project whose service account the master
   uses to send FCM messages.
2. **Android**: register the app with your `applicationId` and download
   `google-services.json` into `android/app/`. The Google Services Gradle plugin is
   applied only when that file exists, so builds work without it.
3. **iOS**: register the bundle id and add `GoogleService-Info.plist` to the
   `Runner` target in Xcode. Add the *Push Notifications* capability. The
   *remote-notification* background mode is already in `Info.plist`. Upload an APNs
   auth key to Firebase (Project settings → Cloud Messaging).
4. **macOS** (optional): the same steps as iOS, using the macOS Runner target.
5. Do not commit these files if they belong to a customer. Supply them at build time.

At sign-in, the app asks for notification permission and sends the FCM
registration token with `PUT /v1/devices/current/push`. When the token rotates,
the app sends the new one.

## Third-party notices

All dependencies are MIT, BSD or Apache-2.0. `./scripts/check-app-licenses.sh`
checks every package in `pubspec.lock`. Flutter's `LicenseRegistry` collects the
license texts of the engine and of every package. **Settings → About →
Open-source licenses** shows them with `showLicensePage`, which meets the
attribution requirement inside the app. A standalone NOTICE file for a store
listing or legal review can be taken from a build: `flutter build web` writes the
plain text to `build/web/assets/NOTICES`, and mobile builds bundle the same text
zlib-compressed as `flutter_assets/NOTICES.Z`. Regenerate the file after every
dependency change.

## Offline, search and invitations

- **Offline cache** (`lib/api/cache.dart`). Each folder page the user has seen (newest 200)
  and each message they have opened (newest 100 per account, already sanitised by the master)
  is kept in the app's private support directory (`path_provider`), one file per entry. Lists
  and opened messages show from it when the master is unreachable, with an "Offline" banner.
  Attachments, passwords and tokens are never cached. The cache is wiped on sign-out, when an
  account is removed, and by `Session.wipeHooks`. On web it lives in memory only. The OS
  sandbox protects the files; use full-disk encryption (the default on current iOS and
  Android) for the rest.
- **Search** (`SearchScreen`) matches words against subject, sender and recipients of the
  saved messages, across accounts, with `is:unread`, `is:starred` and `has:attachment`.
- **Meeting invitations** (`InviteCard`). A `text/calendar` attachment is parsed on the
  device and shown as a card with an "Add to calendar" button (CalDAV, through
  `PUT /v1/accounts/{aid}/events`).
- **New-mail banner.** A `mail.new` event for a folder the user isn't looking at shows
  "New mail in <account>" with an Open action. Notifications while the app is closed come
  from FCM (see below).

## Known limits (v1)

- The app's text is in English only; dates use the `en_US` format.
- A forwarded message includes the original text but not its attachments.
- Search covers only messages saved on this device (see "Offline, search and invitations").
  The master has no search endpoint yet.
- Meeting invitations can be added to the calendar, but Accept / Decline replies need a
  master endpoint that does not exist yet. Times sent in a named time zone (`TZID`) are
  read on the device's clock and the card warns the user.
- Repeat rules of recurring events are shown but can't be edited (a v1 API limit).
- A swipe to archive or delete is sent to the server once its Undo snack bar
  closes. If the app is killed within those seconds, the action is lost.


## iOS Simulator and Android emulator screenshots

The design is adaptive, so check both on real runtimes (a Mac with Xcode is required for iOS):

```bash
flutter run -d "iPhone 16"                      # liquid-glass tab bar, iOS controls
xcrun simctl io booted screenshot ios-inbox.png
xcrun simctl ui booted appearance dark          # then screenshot again for Dark Mode
flutter run -d emulator-5554                    # Material 3 on Android
adb exec-out screencap -p > android-inbox.png
```

On the web build, `?platform=ios` or `?platform=android` previews each design in a browser
(for quick looks only; fonts and blur differ from a device).
