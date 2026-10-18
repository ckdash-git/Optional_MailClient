# Recon: what we are building

This file stands in for a recon map. We are not cloning one app. We are building a
lightweight, commercial, any-server mail + calendar + contacts suite, using
Thunderbird for Android/iOS as the feature reference.

## Requirements from the product owner

1. Mail works with **whatever protocol the server config specifies**: IMAP, POP3 and
   SMTP today. JMAP and Exchange/Graph are later adapters behind the same API.
2. **Calendar** (CalDAV) and **address book** (CardDAV) inside the same app.
3. **Real-time push notifications.**
4. **As light as possible**, on a **master/slave architecture**.
5. **Commercial use**: every dependency and every borrowed line of code must have a
   licence that allows a closed-source product.
6. Good UI/UX, production grade, strict security.

## Interpretation of "master/slave"

We could not access the earlier discussion: the shared link sits behind a bot check and
no memory files exist in this environment. So this is our interpretation, and it should
be confirmed:

- **Master**: one small server binary that the operator (us or an enterprise customer)
  runs. It holds the *server config*: which domains use which protocol, host, port and
  security. It also keeps the long-lived upstream connections (IMAP IDLE, POP3 polling,
  CalDAV/CardDAV sync) and pushes changes to devices.
- **Slaves**: thin client apps (Android, iOS, desktop, web). They only talk to the
  master, keep no mail-server credentials, and hold no protocol code.

Real-time push needs the master. iOS does not let an app hold an IMAP IDLE socket in the
background, and Android battery optimisation kills such sockets too. That is the main
complaint about on-device clients (see `feedback.md`). A server that holds IDLE and wakes
the device with FCM/APNs is how commercial "push for any IMAP" clients work.

## Feature inventory (reference: Thunderbird Android / iOS feature set)

| area | screens | data |
| --- | --- | --- |
| Onboarding | S1 server URL, S2 email + password, S3 manual server settings | user, device, account |
| Mail | S4 folder drawer, S5 message list, S6 message view, S7 compose / reply / forward | folders, summaries, messages, attachments |
| Calendar | S8 agenda (by day), S9 event editor | calendars, events |
| Contacts | S10 contact list + search, S11 contact editor | address books, contacts |
| Settings | S12 accounts, S13 devices (sessions), sign out | devices |
| Push | system notification → opens S5 | push tokens |

Hard constraints found:

- IMAP UIDs are only stable within one UIDVALIDITY, so message ids carry it.
- POP3 has no folders or flags. The master stores the read and flagged state per UIDL.
- CalDAV/CardDAV updates must send `If-Match` with the ETag, or a concurrent edit is
  overwritten silently.
- Users can type any host name, so the master must refuse to connect to private or
  internal addresses (SSRF).
