# Design

World: **Timetable**. Mid-century transit timetables: charcoal on white, one signal red, exact
columns and hairlines. Adaptive: iOS gets native widgets and a liquid-glass tab bar, Android gets
Material 3. The tokens live in `lib/ui/design.dart`; nothing else hard-codes a colour.

## Colour

| role | light | dark |
| --- | --- | --- |
| ink (text) | `#1D1D1F` | `#F5F5F7` |
| muted text | `#6E6E73` | `#98989D` |
| ground | `#FFFFFF` | `#000000` |
| grouped (fields, chips, selected) | `#F2F2F7` | `#1C1C1E` |
| hairline | `#D1D1D6` | `#38383A` |
| signal red (tint, unread, primary action) | `#D6001C` | `#FF453A` |
| text on signal red | white | black (white is only 3.4:1 on the dark red) |

Red does three jobs only: the tint, the unread marker and the primary action. Accounts and
calendars are colour-coded with the **iOS system colours** (blue, green, orange, purple, teal,
pink), stable per account or calendar, so two of them are never told apart by red.
Contrast is pinned by `test/design_test.dart` (body 7:1, muted and red 4.5:1, both modes).

## Type

System fonts: San Francisco on iOS, Roboto on Android. Times and counts use tabular figures so
columns line up. Unread rows are bold; read rows are regular.

## Shape and components

- iOS: 12 pt rounded fields and buttons, grouped-grey inputs, green system switch, centred
  navigation titles, edge-swipe back, a stadium FAB.
- Android: Material 3 `NavigationBar`, 24 pt pill buttons, left-aligned titles, rounded-square FAB.
- Hairline dividers (0.5 pt) separate rows; there are no card shadows on lists.

## Signature moves

1. **The liquid-glass tab bar (iOS).** A floating capsule that blurs the content under it, with a
   bright specular rim and a lighter glass capsule behind the selected tab. It falls back to a
   near-opaque fill under high contrast, and the content scrolls beneath it.
2. **The timetable agenda.** Each event is a row: start time bold, end time muted, a 3 pt vertical
   rule in the calendar's colour, then title and place.

## Structure (iOS phones)

Mail starts at **Mailboxes**, as in iOS Mail: a large collapsing title, an inset grouped list of
accounts (colour-coded avatar, unread count, delivery status), then **Recents**, a merged
newest-first list across accounts with a 3 pt edge bar in each account's colour. An account opens
its folder list (large title, "‹ Mailboxes" back chevron); a folder opens the inbox as a pushed
screen with the system back gesture. Settings has a large title; Calendar keeps an inline title,
as Apple Calendar does. The delivery status is truthful: "Instant" for IMAP accounts without an error,
"Checks every few minutes" for POP3, and the error text when the master reports one.

Android and wide layouts keep the folder drawer or side pane and the Material 3 bars.

## Filters and large titles

Mail shows capsule filters (All, Unread with the folder's unread count, Starred) above the list.
A filter belongs to one folder view and resets when the folder or account changes. It applies to
the pages already loaded and fetches older pages until something matches. On iOS, Contacts has a
large collapsing title like Settings; Android keeps its app bar. Widget tests run both platforms at
200% text size to catch overflow.

## iOS polish (round 3)

- The pushed Inbox, Contacts and Calendar use the large collapsing title with a labelled back
  ("Mailboxes"). Pull to refresh replaces the refresh button.
- Unread is the red dot plus bold text; dates stay muted. The star shows only on starred rows
  on iOS; Android keeps it on every row.
- Message and search screens use Cupertino icons, a chevron back and a pill-style search field
  with Cancel. Outlined buttons are quiet filled pills on iOS and hairline outlines on Android.
- Fields have no focus ring on iOS; Android keeps the charcoal ring.
- Compose is an icon-only round button on iOS and an extended Compose button on Android.

Recents on the Mailboxes screen is a merged, paged list (`RecentsFeed`): a message is shown only
once no account can still hold a newer one, so the order is always right while pages load as you
scroll.

Screens: `design/screens-v2/` (iOS and Android, light and dark).

## Not built yet

Dynamic Type verification on a real device, and real Simulator / emulator captures (needs a Mac
and the Android SDK; commands are in docs/CLIENT.md).
