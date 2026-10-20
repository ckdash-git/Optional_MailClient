# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter (existing app in `lib/`), one codebase for iOS, Android, desktop and web. Adaptive means the design language follows the OS: native iOS conventions on iPhone and iPad, Material on Android, and a desktop layout on wide screens.

## Users

Employees of organisations whose IT runs the mail server (and our "master" gateway in front of it). Many are not technical: they open the app dozens of times a day to read and answer mail, check where they need to be next, and look up a colleague. IT sets the server config, so users should never have to think about ports or protocols.

## Product Purpose

A calm, fast mail, calendar and contacts app that works with whatever standards-based server the organisation runs (IMAP or POP3 with SMTP, CalDAV, CardDAV), with instant push. Success: a user signs in with an email address and password and new mail arrives immediately, with no setup.

## Positioning

Instant, trustworthy push and one app for mail, calendar and contacts on the organisation's own servers. Passwords stay on the master and are not held on devices or by a third-party cloud. A neighbouring consumer mail app cannot truthfully say that.

## Operating Context

One-handed phone use between meetings; long reading sessions on desktop. Mail arrives all day. Calendar and contacts are reached from the same app. IT may lock the app to the company's domains (`MASTER_ALLOW_CUSTOM_SERVERS=false`), in which case the manual server settings are never needed.

## Capabilities and Constraints

- Mail: folders, list, read (sanitised HTML, remote images blocked), compose, reply, forward, attachments, star, archive, delete, move.
- Calendar: month and agenda, create, edit and delete events (recurrence shown, not editable).
- Contacts: list, search, create, edit, delete.
- Settings: accounts, devices (revoke), theme, licences, sign out.
- Realtime: WebSocket events and optional FCM; the sign-in and push health must be visible.
- Not available yet: search, offline cache, unified inbox, OAuth sign-in, invitations from email. Do not design screens that imply them.
- Existing terminology: master, account, device.

## Brand Commitments

No name, logo or brand identity exists yet; "Optional Mail" is a working title. The owner has not chosen one. Do not use the Thunderbird or K-9 names or marks.

## Evidence on Hand

170 verbatim user reviews of existing clients in `replica/reviews.csv` and `replica/feedback.md`. Top complaints: push silently stops (37), UI cluttered or redesigned without asking (33), accounts hard to tell apart (20), basics paywalled. No customer testimonials, metrics or logos exist.

## Product Principles

1. Calm by default: a simple screen first, advanced settings behind one clear door, and no layout removed without a way back.
2. Push you can see: show whether delivery is instant, and say plainly why not.
3. Say what happened: errors name the step that failed and what to do.
4. Privacy is visible: remote content is blocked, links are confirmed, and nothing is tracked.
5. One app, three jobs: mail, calendar and contacts feel like one system.

## Accessibility & Inclusion

Employees of any ability: support screen readers (VoiceOver, TalkBack), Dynamic Type and text scaling, 44pt targets on touch, sufficient contrast in light and dark, and reduced motion. No colour-only meaning.
