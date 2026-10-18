# Fixes and positioning

Everything here comes from `feedback.md`, which is built on **170 verbatim review rows from 13 platforms** (see `reviews.csv`). Counts are rows coded to a theme, and one row can carry more than one theme. "Sources" counts distinct platforms. THIN means fewer than 3 reviews, or only 1 source.

## 1. What they hate (complaints about things the apps do)

| # | Problem | Reviews | Sources |
|---|---|---|---|
| 1 | Push silently stops or arrives minutes to hours late on Android, even with every permission granted | 37 | 7 |
| 2 | UI is either overwhelming (too many settings) or redesigned without asking; users call it dated, cluttered or confusing | 33 | 12 |
| 3 | Updates break things: crashes, infinite loading, "Optimizing database" loops, failed sends with no error | 17 | 5 |
| 4 | Switching accounts and finding unified folders takes too many taps; accounts are hard to tell apart | 20 | 8 |
| 5 | Mail state doesn't sync: deletes don't reach the server, mail reappears, weeks of mail missing | 12 | 5 |
| 6 | Privacy: telemetry on by default, a vendor's cloud holds your credentials, policies allow your mail to be processed | 10 | 7 |
| 7 | Account setup and settings import fail or lose settings | 7 | 5 |
| 8 | Pricing: basics paywalled (spam filtering, AI), a "Sent with" tagline, charges after cancelling | 6 | 3 |
| 9 | Support is unresponsive | 5 | 2 |
| 10 | Search misses obvious results | 4 | 3 |
| 11 | Microsoft/Google login and OAuth changes lock accounts out (**THIN**) | 3 | 1 |

**Quotes:**

- #1: "Push works fine but after some hours or days I don’t get any new mails. The background process is still up and running." ([K-9 forum](https://forum.k9mail.app/t/push-feature-doesnt-work/11126/24))
- #2: "I find the UI difficult to navigate and the controls non-intuitive." ([Hacker News](https://news.ycombinator.com/item?id=40888180))
- #3: "Now I'm suffering buyers remorse as the performance has gone downhill steadily the past few months." ([Google Play, Spark](https://play.google.com/store/apps/details?id=com.readdle.spark&hl=en_US))
- #4: "The change to a separate "Unified Account" means my unified inbox is always several taps away from wherever I am." ([GitHub #9568](https://github.com/thunderbird/thunderbird-android/issues/9568))
- #6: "Why don't you or Mozilla just announce what data they collect?" ([GitHub #8199](https://github.com/thunderbird/thunderbird-android/issues/8199))

## 2. What is missing (features asked for by name)

| # | Feature | Reviews | Sources |
|---|---|---|---|
| 1 | Everyday essentials: send later, undo, offline access, select all, app PIN, keyboard shortcuts, move between accounts, notification sounds | 18 | 6 |
| 2 | Calendar, contacts and tasks in the mail app, including accepting invitations | 12 | 6 |
| 3 | Subfolders, tags, labels, favourite folders, tag sync with desktop | 11 | 5 |
| 4 | Rules, filters and spam blocking on mobile | 7 | 2 |
| 5 | Rich compose and HTML signatures | 4 | 2 |
| 6 | Push without Google FCM (ntfy, UnifiedPush) | 3 of the 37 push rows (reviews.csv lines 47, 60, 62) | 2 |

**Quotes:**

- #2: "It would be great if Thunderbird mobile supports calendars like the desktop applications supports calendars." ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android))
- #1: "Im here to request a serious UNDO button." ([App Store, Spark](https://apps.apple.com/us/app/spark-mail-ai-email-inbox/id997102246?see-all=reviews))

## 3. What is unsolved (whole jobs or groups the apps ignore)

| # | Group and job | Evidence |
|---|---|---|
| 1 | **iPhone users on their own domain or a privacy-focused provider** (Posteo, mailbox.org, self-hosted) who need instant mail. iOS gives them no IMAP push. Third-party apps that do push require handing credentials to a vendor's servers. | iOS theme: 14 reviews, 6 sources. Privacy theme: 10 reviews, 7 sources. |
| 2 | **People who rely on email notifications for work** (people who "need immediate push notifications for my work") on any server, with no Google services. | Push theme: 37 reviews, 7 sources, 23 of them from 2025-26 |
| 3 | **People running their own CalDAV/CardDAV server** (Nextcloud, Radicale and similar) who want one app instead of a mail client, plus DAVx5, plus a calendar app | Calendar/contacts theme: 12 reviews, 6 sources |
| 4 | **People with several accounts** who want accounts both kept separate and viewed together | Multi-account theme: 20 reviews, 8 sources |
| 5 | **Non-technical users** who leave powerful clients because of the settings ("too complex for standard-users like me") | 6 rows inside the UI theme (reviews.csv lines 160, 163, 165, 167, 169, 171), 5 platforms |

**Quotes:**

- #2: "A 15-minute polling frequency may be okay for casual use, but that is not acceptable for professionals such as myself." ([GitHub #9239](https://github.com/thunderbird/thunderbird-android/issues/9239))
- #1: "I switched to IOS for my primary phone a year ago and it has been a challenge to find an alternative that doesn’t suck." ([Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/))

## 4. Fix plan (top 8, ranked by evidence and how cheap the fix is)

| # | What to build or change | Size | Evidence |
|---|---|---|---|
| 1 | **Push you can see and trust (Android).** Details below. | L | Push theme: 37 reviews, 7 sources (#11442, #9239, #8434, K-9 forum thread, Aqua Mail Play review) |
| 2 | **Push health in the UI (all platforms).** Details below. Small and cheap, so ship it first. | S | Push 37/7 and sync state 12/5. Users say "Waiting for new emails" is shown while nothing arrives. |
| 3 | **iOS push without handing over passwords.** Details below. | L | iOS theme 14/6 plus privacy theme 10/7 |
| 4 | **Mail, calendar and contacts in one app** over CalDAV and CardDAV. Details below. | L | Calendar/contacts 12/6. DAVx5 reviewers use a separate app as the workaround. |
| 5 | **Calm defaults with progressive disclosure.** Details below. | M | UI theme 33/12, the largest number of sources |
| 6 | **Multi-account model done right.** Details below. | M | Multi-account 20/8 (#9568 thread, Play beta review) |
| 7 | **Setup that just works.** Details below. | M | Setup 7/5; OAuth 3/1 (THIN) |
| 8 | **Everyday essentials.** Details below. | M | Missing features 18/6; filters 7/2; signatures 4/2 |

**1. Push you can see and trust (Android).**
- One IMAP connection per account, using NOTIFY (RFC 5465) when the server supports it and IDLE on INBOX when it doesn't. This avoids the per-folder IDLE storms behind the provider "Authentication Limit Exceeded" lockouts reported in #826.
- Adaptive keep-alive, reconnect when the network changes, and a watchdog that notices a dead IDLE connection and falls back to a poll.
- Optional UnifiedPush or ntfy distributor, and no FCM dependency.
- One setting per account: Instant / Every N min / Manual. This replaces the separate per-folder Sync and Push toggles.
- Guided setup for battery, alarm and notification permissions, with a self-test that sends a test mail.

**2. Push health in the UI (all platforms).**
- A per-account status line: "Instant – last event 2 min ago" or "Not instant: battery restriction / server lacks IDLE / auth failed", with a one-tap fix.
- Errors appear in the app, not just as system notifications.

**3. iOS push without handing over passwords.** iOS does not allow background IMAP IDLE, so a relay is unavoidable on iOS. To make it acceptable:
- A content-free wake-up push. The relay sends only "account X changed" and never subject or sender.
- An open-source relay users can self-host (for example, a Docker container next to their mail server).
- A hosted relay that keeps credentials encrypted, prefers OAuth tokens or app passwords, and can be deleted with one tap.
- JMAP push or Web Push used directly where the server supports it.
- Say all of this plainly in onboarding.

**4. Mail, calendar and contacts in one app.**
- Sync over CalDAV and CardDAV, with discovery via .well-known and SRV records.
- Read, accept and decline iMIP invitations directly from the mail (#930).
- Optionally expose calendars and contacts to the OS (Android sync adapter; EventKit and Contacts on iOS) so users don't also need DAVx5.

**5. Calm defaults with progressive disclosure.**
- A simple default screen with an "Advanced" section.
- Never remove a layout without an option to keep it.
- Account colours and avatars, a dark widget, native components, and accessibility (VoiceOver and TalkBack) tested from day one.

**6. Multi-account model done right.**
- A persistent account rail, one tap to switch.
- Unified Inbox, Sent, Drafts, Trash and Spam.
- Optional "keep accounts separate" mode.
- Move and copy between accounts.

**7. Setup that just works.**
- Autoconfig from Mozilla ISPDB, `.well-known/autoconfig`, SRV records and MX lookup.
- OAuth for Google and Microsoft.
- When a server check fails, say which step failed and why ("IMAP login rejected: app password required").
- Import settings from other clients without silently disabling notifications (#9326).

**8. Everyday essentials.**
- Send later, undo send, select all, an offline cache, and an app PIN or biometric lock.
- Local rules plus Sieve (server-side filtering) where the server supports it.
- HTML signatures.
- Keyboard shortcuts.

### Notes for replica-launch (pricing, not engineering)

- Don't paywall spam filtering or rules. Users call that out: "This shouldn't be a paid feature either."
- Don't add a "Sent with..." tagline to free users' mail.
- Make cancellation clean and visible. One user reports being charged after cancelling: "After ending your subscription they keep charging your creditcard."
- Telemetry should be opt-in (#8199).

## 5. Positioning options

**A. Instant push on any server**

For people who run email on their own domain or an independent provider and need it right away, who are tired of push that silently stops on Android and doesn't exist for IMAP on iPhone, our app delivers instant IMAP notifications on Android and iOS. It also shows, in the app, whether push is healthy and how to fix it when it isn't.

Evidence: push notifications unreliable, 37 reviews across 7 sources. Supported by the iOS IMAP push gap: 14 reviews across 6 sources.

**B. One app for mail, calendar and contacts on your own server**

For people with several accounts on their own servers, who juggle a mail app, a separate sync app and a calendar app just to see their own calendar and contacts, our app syncs mail, calendar and contacts over open standards (IMAP, CalDAV, CardDAV) in one lightweight app.

Evidence: calendar and contacts missing or separate, 12 reviews across 6 sources.

**C. Push without handing over your password**

For privacy-minded people who don't want telemetry on by default or a vendor's cloud holding their mailbox password just to get notifications, our app connects straight to your server. On iOS, where a relay is unavoidable, it lets you self-host the relay or uses content-free wake-ups.

Evidence: privacy and data on servers, 10 reviews across 7 sources. Supported by the iOS IMAP push gap: 14 reviews across 6 sources.

### Recommendation: A

- **Largest and most recent evidence.** Push is the biggest theme: 37 reviews, 23 of them from 2025-2026.
- **No sign of being solved.** The leading open-source client's own April 2026 progress report calls it "our users' biggest pain point".
- **Matches what the product already promises.** "Real-time push" with "any server" is the stated differentiator.
- **Absorbs the other options.** The privacy angle (C) becomes the proof point for how iOS push is done, and the calendar and contacts angle (B) is the follow-on.

**Caveat:** the push evidence leans toward one ecosystem's tracker and forum (see the bias note in `feedback.md`). Before committing the brand, validate with a Reddit pass once Reddit can be reached, and with a few interviews with people who run their own mail servers.

The app name should not contain any competitor's name. Pick it in /replica-brand.
