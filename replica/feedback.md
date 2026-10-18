# User feedback: IMAP mail, calendar and contacts clients

**Sample: 170 verbatim review rows from 13 platforms (27 platform-and-app combinations).** The rows are in `replica/reviews.csv`. Collection date: 2026-10-18.

- **Mix:** 131 critical comments or feature requests, 24 mixed ("love it, but..."), 15 positive.
- **Recency:** 56 rows are from 2026, 26 from 2025 and 48 from 2024. 30 are from 2015-2023, and 10 have no date.
- **Apps covered:** Thunderbird for Android / K-9 Mail (stable and beta), Spark, BlueMail, Aqua Mail, FairEmail, Edison Mail, Outlook, Gmail, DAVx5, Apple Mail (via Apple Community threads) and the planned Thunderbird for iOS (via blog comments).

## How this was collected and what it can't tell you

| Platform | Rows | Notes |
|---|---|---|
| GitHub issues (thunderbird-android) | 23 | Public issue pages, read one by one. Bug reports and feature requests with user comments act as a public feature board. |
| Hacker News | 23 | Threads 41995041, 41798615, 41705002, 40570183, 40888180 and 44836406 |
| App Store (Spark, Outlook, Edison, Gmail) | 25 | The "see all reviews" pages list the most helpful reviews first, so many of these are 2018-2023. |
| Google Play (9 listings) | 27 | The public listing page shows only 3 reviews per app. |
| Mozilla Connect ideas | 14 | The Thunderbird Android label listing and three individual ideas |
| K-9/Thunderbird forum | 14 | The "Push feature doesn't work" thread (2024-2026) and "New layout not OK" |
| Thunderbird blog comments | 13 | Comments on the Oct 2026 iOS preview post and the Sep 2025 post |
| Trustpilot (Spark, BlueMail) | 18 | |
| Apple Community, Ars Technica forum, /e/OS forum, Privacy Guides, XDA | 11 | |

**Blocked or not reached:**

- **Reddit was not reachable.** WebSearch refuses reddit.com, Exa fetch returned `SOURCE_NOT_AVAILABLE`, and Exa search returned no reddit results. There are no Reddit rows.
- **Apple's customer-reviews RSS feed failed.** `itunes.apple.com` returned DNS ENOTFOUND, so App Store rows come from the public "see all reviews" pages instead.
- **The GitHub REST API was blocked.** This session is bound to its own repo. Public issue pages were read instead. Reaction counts are only quoted where the issue page itself showed them (#930: 38 thumbs-up). The reaction numbers on the sorted issue list came through a summariser and were inconsistent, so they are not used.
- **Other pages that failed:** the Trustpilot page for Edison (fetch error), the App Store page for BlueMail (not found), and support.mozilla.org (client challenge). G2 and Capterra were not attempted.
- **Excluded on purpose:** third-party "what N reviews say" aggregator pages such as productivity-apps.com. They truncate and re-host store reviews, and the original review URL can't be checked.

**Limitations:**

- **No star ratings.** The fetched page text did not include per-review stars on Google Play, the App Store or Trustpilot, so the `rating` column is blank in every row. Instead of stars, each row was hand-labelled `critical` (complaint or request), `mixed` or `positive`.
- **Weighting.** Critical rows count 1.5, mixed 1.0 and positive 0.5. Rows from 2026 are multiplied by 1.5, 2025 by 1.25, and 2024 or undated by 1.0. Older rows count 0.75.
- **Excerpts.** Some long reviews are stored as verbatim excerpts: an exact substring with nothing reworded.
- **Bias.** The sample leans toward the Thunderbird/K-9 ecosystem, because its tracker, forum and ideas board were the most reachable. Treat the push theme's size partly as an artefact of that. It is still corroborated on 7 platforms and across 6 different apps.
- **Coding.** Themes were coded by hand, and one row can carry several themes.

## Themes, ranked by weighted score

THIN means fewer than 3 reviews, or only 1 source.

| # | Theme | Reviews | Sources | Weighted | 2025-26 rows | Flag |
|---|---|---|---|---|---|---|
| 1 | Push notifications unreliable or delayed (Android IMAP IDLE; battery and background limits) | 37 | 7 | 64.9 | 23 | |
| 2 | UI dated, cluttered, confusing, or redesigns users didn't ask for | 33 | 12 | 53.5 | 12 | |
| 3 | Performance, crashes, bugs after updates | 17 | 5 | 31.6 | 11 | |
| 4 | Missing everyday features / parity with the desktop version | 18 | 6 | 28.8 | 6 | |
| 5 | Multi-account handling / unified inbox navigation | 20 | 8 | 27.8 | 10 | |
| 6 | iOS: no IMAP push, no trustworthy IMAP client on iPhone | 14 | 6 | 21.4 | 5 | |
| 7 | Sync state unreliable (mail missing, deletes or moves not syncing) | 12 | 5 | 19.6 | 7 | |
| 8 | Folders, tags, labels | 11 | 5 | 19.0 | 6 | |
| 9 | Calendar, contacts, tasks missing or need a separate app | 12 | 6 | 15.4 | 4 | |
| 10 | Privacy: telemetry, data or credentials on company servers | 10 | 7 | 13.1 | 1 | |
| 11 | Support unresponsive | 5 | 2 | 9.8 | 3 | |
| 12 | Account setup / import / configuration failures | 7 | 5 | 9.6 | 1 | |
| 13 | Filters, rules, spam, blocking | 7 | 2 | 9.5 | 5 | |
| 14 | Pricing, paywalls, subscriptions | 6 | 3 | 8.4 | 2 | |
| 15 | Search unreliable | 4 | 3 | 5.9 | 1 | |
| 16 | OAuth / provider login breakage | 3 | 1 | 5.2 | 3 | **THIN** (1 source) |
| 17 | HTML rendering, rich compose, signatures | 4 | 2 | 4.5 | 1 | |

The tasks you asked about map to these themes as follows:

- **HTML rendering** is theme 17, and it is small in this sample.
- **Performance and heaviness** is theme 3, plus a few UI rows that call apps "heavy" or "slow".
- **Battery** is folded into theme 1.

### 1. Push notifications unreliable or delayed: 37 reviews, 7 sources

Apps: Thunderbird and K-9, Aqua Mail, Spark, Outlook iOS, iOS Mail and Edison.

The pattern: push works right after setup, then silently stops after hours or days while the "Waiting for new emails" notification stays up. Other complaints are confusing per-folder push and sync settings, Android battery and alarm permissions, and a 15-minute polling floor. People want push without Google's FCM (ntfy or UnifiedPush). Thunderbird's own April 2026 progress report calls push notifications "our users' biggest pain point". That is context from the vendor, not a counted review.

> 99% Push not working. Mails come randomly, after minutes or never and very rarely (1%) immediately K9 worked for 15 years without such issues ever. Push worked. Always. — [GitHub #11442](https://github.com/thunderbird/thunderbird-android/issues/11442)

> Yes, still see the problem. Android 16, K9 16.1. I’ve resorted to monitoring the imap connections on my server and restarting K9 when connection is lost. Happens every few days. — [K-9 forum](https://forum.k9mail.app/t/push-feature-doesnt-work/11126/32)

### 2. UI dated, cluttered, confusing, or unwanted redesigns: 33 reviews, 12 sources

There are two opposite complaints:

- **Too much:** the FairEmail settings are overwhelming, and K-9 had per-folder toggles.
- **Too changed:** redesigns in K-9/Thunderbird, BlueMail and Outlook moved controls, and users can't revert them.

Users also call several apps dated or ugly: Gmail, BlueMail desktop, and FairEmail.

> I agree that FairEmail's host of options can be confusing so ideally it, and Thunderbird, would take a leaf out of VLC's book and by default only show basic settings but have an 'Advanced Settings' button that shows the others if needed/desired. — [Mozilla Connect](https://connect.mozilla.org/t5/ideas/bring-all-features-in-fairemail-to-thunderbird-android/idi-p/74208)

> This email program was a solid 5 Stars for the longest time until they reformatted it and I went to open my email only to find that I couldn't read the font and all the smooth functionality was gone. — [Google Play, BlueMail](https://play.google.com/store/apps/details?id=me.bluemail.mail&hl=en_US)

### 3. Performance, crashes, bugs after updates: 17 reviews, 5 sources

Spark, Outlook Android and BlueMail have recent 2025-2026 regressions. Users report infinite loading, "Optimizing database" loops, freezes and failed sends with no feedback.

> I just want an email client that works :( is that too much to ask? — [Google Play, Thunderbird](https://play.google.com/store/apps/details?id=net.thunderbird.android&hl=en_US)

> Update in 2026: this app has completely stopped working. it won't sync email, it falsely claims there is no Internet connection — [Google Play, Spark](https://play.google.com/store/apps/details?id=com.readdle.spark&hl=en_US)

### 4. Missing everyday features / desktop parity: 18 reviews, 6 sources

Users name these features: send later, undo, offline access, select all, app PIN or lock, keyboard shortcuts, moving mail between accounts, and custom notification sounds.

> The "send later" function is in a LOT of Android email programs. It is a part of basic functionality. Thunderbird for Android needs it too. — [Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android)

> Either way, no offline access in an email app... pretty bad. — [Hacker News](https://news.ycombinator.com/item?id=41995041)

### 5. Multi-account handling and unified inbox: 20 reviews, 8 sources

Users want both: accounts kept clearly separate (colours, names, fast switching) and unified views. That means unified Sent, Trash and Spam as well as Inbox.

> I think many of us with multiple accounts don't want a unified mailbox jumbling the messages together. We want the accounts well separated and an easy path from one account to another. — [GitHub #9568](https://github.com/thunderbird/thunderbird-android/issues/9568)

> Why is there no unified outbox because it takes quite a few Presses to get from my unified inbox to the specific outbox that I'm looking for — [Google Play, Thunderbird Beta](https://play.google.com/store/apps/details?id=net.thunderbird.android.beta&hl=en_US)

### 6. iOS: no IMAP push, no trustworthy IMAP client: 14 reviews, 6 sources

iOS Mail does not support IMAP IDLE in the background. Third-party apps get push by running a vendor server that holds your credentials. Users are stuck between late mail and a privacy trade-off, and many are waiting for an open, IMAP-native iOS client.

> They explained that while macOS supports IMAP-IDLE, iOS does not support it, which is why my notifications from Posteo are not being received on iOS. It is unclear why push support is inconsistent within Apple's ecosystem. — [Apple Community](https://discussions.apple.com/thread/255342888)

> But for me, personally, I'm just not comfortable turning over my all my email credentials to any 3rd party developer. — [Ars Technica forum](https://arstechnica.com/civis/threads/does-ios-mail-support-standard-idle-push.1485686/)

### 7. Sync state unreliable: 12 reviews, 5 sources

Reports include deletes not reaching the server, mail reappearing, gaps of several weeks after a reinstall, folders that won't load, and state that differs between devices.

> Moving an item to the trash in Android TB (IMAP) doesn't seem to actually move it on the server. Webmail still shows it in the inbox. — [Hacker News](https://news.ycombinator.com/item?id=41995041)

> it does no more synchronize all mails, there are huge gaps in between, the mails of several weeks are missing. — [/e/OS forum](https://community.e.foundation/t/email-app-does-not-synchronize-all-emails/81734)

### 8. Folders, tags, labels: 11 reviews, 5 sources

> With it becoming Thunderbird branded my biggest wish is proper subfolder support. — [Hacker News](https://news.ycombinator.com/item?id=41995041)

> Tag synchronisation , desktop / app would be a game changer for me. — [Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/)

### 9. Calendar and contacts missing, or a separate app needed: 12 reviews, 6 sources

Three of these rows are positive. Two are DAVx5 users who praise a separate sync app because their mail client doesn't do calendar and contacts. They show the workaround users rely on today.

> not being able to have my calendar sync from my desktop app to my phone has been the only disappointment of switching to Thunderbird last year. — [Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/)

> Syncs the calendar and contacts from my mail server (which, despite it having an app, does not sync calender and contacts to my phone) right in to the calendar and contacts app in my device. — [Google Play, DAVx5](https://play.google.com/store/apps/details?id=at.bitfire.davdroid&hl=en_US)

### 10. Privacy, telemetry, data on company servers: 10 reviews, 7 sources

Complaints cover telemetry turned on by default, policies that allow processing of your mail, and credentials or tokens held by a vendor to provide push.

> Expected behavior Usage and technical data is unchecked by default Actual behavior Usage and technical data is checked by default — [GitHub #8199](https://github.com/thunderbird/thunderbird-android/issues/8199)

> By linking our Services to your email or other internet accounts, you authorize us to collect, process, and retain information, including personal information, from those accounts. — [App Store, Edison (quoting its policy)](https://apps.apple.com/us/app/edison-mail-spam-blocker/id922793622?see-all=reviews)

### 11. Support unresponsive: 5 reviews, 2 sources

> Even if you use their paid service they never answer your emails. After ending your subscription they keep charging your creditcard. — [Trustpilot, BlueMail](https://www.trustpilot.com/review/bluemail.me)

### 12. Setup, import and configuration failures: 7 reviews, 5 sources

> But the average user has likely never heard of IMAP and SMTP, and thus could have no idea what to do with all those fields you can fill in. — [XDA](https://xdaforums.com/t/closed-app-5-0-fairemail-fully-featured-open-source-privacy-oriented-email-app.3824168/page-22)

> This leads me to believe there may be something wrong with the settings import feature that prevents the notification settings from applying even if they are manually changed afterwards. — [GitHub #9326](https://github.com/thunderbird/thunderbird-android/issues/9326)

### 13. Filters, rules, spam: 7 reviews, 2 sources

> Two glaring ones are no support for filtering messages (for example to automatically sort incoming mail) and the other, related one, is no autoresponder support. — [Google Play, Thunderbird](https://play.google.com/store/apps/details?id=net.thunderbird.android&hl=en_US)

### 14. Pricing and paywalls: 6 reviews, 3 sources

> Nice features and good smart inbox. Although the ai features are locked behind a paywall. — [Trustpilot, Spark](https://www.trustpilot.com/review/sparkmailapp.com)

> 3. Add spam learning or filters. This is the most I've ever had to deal with spam mitigation. This shouldn't be a paid feature either. — [App Store, Spark](https://apps.apple.com/us/app/spark-mail-ai-email-inbox/id997102246?see-all=reviews)

### 15. Search: 4 reviews, 3 sources

> the search function straight up doesn't work and sometimes it will fail to send messages and will not give me any feedback and why the message failed to send. — [Google Play, Thunderbird](https://play.google.com/store/apps/details?id=net.thunderbird.android&hl=en_US)

### 16. OAuth and provider login breakage: 3 reviews, 1 source (THIN)

> With the switch to the Microsoft Graph API to log into O365 accounts, account admins have to explicitly allow apps / permissions. My company won't, and is forcing me on to Outlook Mobile, which sucks — [Google Play, Aqua Mail](https://play.google.com/store/apps/details?id=org.kman.AquaMail&hl=en_US)

### 17. HTML rendering, rich compose, signatures: 4 reviews, 2 sources

> Also a feature that I would love to see are fully fledged e-mail signatures (images, text, html). — [Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/)

## Feature requests in users' own words

These are copied verbatim from the rows in `reviews.csv`.

**Push and notifications:**
- "I would like a setting for the push service with ntfy." ([K-9 forum](https://forum.k9mail.app/t/push-feature-doesnt-work/11126/33))
- "true real-time message delivery (push) when synchronizing mail across accounts, rather than relying on polling" ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android))
- "If it works on macOS, it is urgently needed on iOS as well." ([Apple Community](https://discussions.apple.com/thread/255342888))
- "Custom notification sounds please!" ([Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/))

**Calendar, contacts and tasks:**
- "It would be great if Thunderbird mobile supports calendars like the desktop applications supports calendars." ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android))
- "Having the ability to view and accept (including sending a reply (!)) meetings on mobile would be a pretty great option." ([GitHub #930](https://github.com/thunderbird/thunderbird-android/issues/930))
- "I do wish MS would wrap the “To Do” app into Outlook and feature it as a tab at the bottom like the calendar, contacts and mail." ([App Store, Outlook](https://apps.apple.com/us/app/microsoft-outlook/id951937596?see-all=reviews))

**Accounts and organisation:**
- "why not incorporate a unified trash and spam as well." ([Google Play, Thunderbird Beta](https://play.google.com/store/apps/details?id=net.thunderbird.android.beta&hl=en_US))
- "my biggest wish is proper subfolder support" ([Hacker News](https://news.ycombinator.com/item?id=41995041))
- "Please add the ability to see tags on emails, add/remove them, and add tags to the side bar with folders." ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android))
- "allow moving emails between different accounts" is the Mozilla Connect idea title. The verbatim body: "the "Move" function only works within folders of the same account."
- "It’d amazing if we could have “rules”" ([App Store, Spark](https://apps.apple.com/us/app/spark-mail-ai-email-inbox/id997102246?see-all=reviews))
- "I wish we could setup and manage rules from mobile" ([App Store, Outlook](https://apps.apple.com/us/app/microsoft-outlook/id951937596?see-all=reviews))

**Compose and everyday actions:**
- "Im here to request a serious UNDO button." ([App Store, Spark](https://apps.apple.com/us/app/spark-mail-ai-email-inbox/id997102246?see-all=reviews))
- "Why on earth can you not select all to delete mass emails through the app?" ([App Store, Gmail](https://apps.apple.com/us/app/gmail-email-by-google/id422689480?see-all=reviews))
- "Please include a feature to set an app-specific PIN or passcode" ([Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/))
- "Please add support for physical keyboard shortcuts in the android app." ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/idb-p/ideas/label-name/thunderbird%20android))

**Look and settings:**
- "Please use native components for everything and focus on attention to detail in UI such as padding, sizing, contrast, etc." ([Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/))
- "No dark mode for the K9/TB widget is a dealbreaker." ([Hacker News](https://news.ycombinator.com/item?id=41995041))
- "by default only show basic settings but have an 'Advanced Settings' button" ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/bring-all-features-in-fairemail-to-thunderbird-android/idi-p/74208))

**Pricing:**
- "do wish they offered a student price" ([App Store, Spark](https://apps.apple.com/us/app/spark-mail-ai-email-inbox/id997102246?see-all=reviews))

## Critical reviews outside the main themes (read by hand)

Every critical row got at least one theme. These were folded into the catch-all "missing features" or "privacy" themes, but they are really separate needs:

- **Accessibility.** A blind VoiceOver user finds the Send button placement and the compose body hard to use: "As a blind person, whether using gestures or keyboard commands using this app is clunky." The quoted rows are in [App Store, Outlook](https://apps.apple.com/us/app/microsoft-outlook/id951937596?see-all=reviews), and the row starts "Also, as far as Outlook goes". No other row raises this, so it is THIN. It costs little to get right from day one.
- **Offline access** ([HN](https://news.ycombinator.com/item?id=41995041)).
- **AI quality versus external tools** ([Trustpilot, Spark](https://www.trustpilot.com/review/sparkmailapp.com)).
- **Uninstall leftovers and taskbar pinning** felt "unethical" ([Trustpilot, BlueMail](https://www.trustpilot.com/review/bluemail.me)).
- **Notification actions that don't work and notifications that reappear** ([GitHub #10936](https://github.com/thunderbird/thunderbird-android/issues/10936), [#10713](https://github.com/thunderbird/thunderbird-android/issues/10713)). These are coded under push, but the real problem is notification state correctness.
- **iPhone-first resentment.** Users ask why Android got the open client first ([Thunderbird blog](https://blog.thunderbird.net/2026/10/thunderbird-for-ios-a-first-look-at-the-native-iphone-email-app-in-development/)).

## Already shipped by competitors (don't market these as new)

Thunderbird for Android 24.0 added HTML signatures and a choice between Reply and Reply All (from its Play listing). It already has a unified inbox. The K-9 subfolder issue #630 is shown as closed in April 2025. Thunderbird for iOS is in TestFlight beta as of October 2026.
