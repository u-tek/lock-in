# App Review notes

What to give App Review, and the answers for the App Store Connect forms that go with it (SPEC.md
§7). Part 1 is pasted into **App Store Connect → the version → App Review Information → Notes**.
The rest is for you: what has to be true before you press Submit, and draft answers for the
age rating and App Privacy forms.

Every `[OWNER: …]` must be filled in or removed before submitting. Anything marked *planned* has to
ship first, or its line comes out of the notes.

## 1. Notes to paste (under 4,000 characters)

```text
WHAT LOCKIN IS
Lockin is a focus timer for studying with friends. When a squad locks in, every member's live countdown shows in everyone's Dynamic Island and on their Lock Screen through one Live Activity, and the squad raises a shared pet that only grows when they all stay focused.

WHY IT'S NOT ANOTHER TIMER (4.3)
The core feature is a multi-person Live Activity: your friends' timers, not just yours. Our server sends ActivityKit push updates to every member within seconds when someone joins, pauses, finishes or leaves. The creatures, pets and art are original. In StandBy, the squad fills the screen as a desk clock.

HOW TO TEST
Solo, no account:
1. Go through onboarding (4 screens). Your first 25-minute session starts with its Live Activity. Lock the phone to see it on the Lock Screen; long-press the Dynamic Island to expand it. End stops the session early.

With friends, using Demo Buddy:
2. Home > "Lock in with friends" > Sign in with Apple (any Apple Account works), then pick a handle.
3. Squads > Join with code > [OWNER: REVIEW CODE]. This makes a private "Review Squad" with Demo Buddy, a test bot run by our server and labelled as one.
4. On Home, choose Review Squad and tap Lock in. Within about 10 seconds Demo Buddy joins and the island shows +1. Long-press it to see both timers, or lock the phone. Over the next 3 minutes Demo Buddy sends a cheer, pauses, resumes and finishes.
5. To see the invite notification: end your session, open Review Squad, tap "Ask Demo Buddy to lock in" and lock the phone. You'll get "Demo Buddy is locking in" with Join actions.
Demo Buddy only ever joins squads made with the review code.

ACCOUNTS AND SAFETY
- Sign in with Apple is the only sign-in. Solo mode needs no account.
- Delete account: Settings > Account > Delete account. This deletes the user's server data and revokes the Sign in with Apple token.
- Report or block: Friends > swipe left on a person, or open a squad and tap a member. Blocked people are in Settings > Account > Blocked. Support contact: [OWNER: support email].
- No chat (cheers are a fixed set of emoji), no public rooms, no search for strangers, no contact upload, no location. Friends connect only by code, QR code or link. Names are filtered; reports are reviewed within [OWNER: 24 hours].

NOTIFICATIONS AND LIVE ACTIVITIES (4.5.3, 4.5.4)
- "Locking in" alerts go only to members of that squad. They're rate-limited ([OWNER: the limit, e.g. one per squad every 10 minutes]), can be muted per squad, and respect quiet hours (10 pm to 7 am local by default). We never send promotional notifications.
- Live Activity updates go only to people in the session. They use priority 5, except joins, finishes, early leaves, slips and the final end (priority 10). They never make a sound or show an alert, and timer ticks are never pushed: countdowns run on the device.
- [OWNER: keep only if push-to-start shipped] A Live Activity started remotely always arrives with a visible alert.
- Notifications are optional. The app works fully without them.

LOCKIN PLUS (3.1.2)
Optional. Monthly A$3.99, Yearly A$24.99 with a 7-day free trial, or Lifetime A$49.99 (one-time purchase). Plus adds [OWNER: the exact list on the paywall]. The paywall shows what's included, the price and the renewal terms before purchase, with Restore, Terms and Privacy links. Squads and the Live Activity with friends are free. Coins are earned by focusing and can't be bought.

[OWNER: keep only if Deep Focus shipped] DEEP FOCUS uses Family Controls with individual authorization. The user picks their own apps to shield during a session. The selection stays on the device as opaque tokens.
```

Check the length after filling it in. App Store Connect refuses notes over 4,000 characters.

## 2. Demo access

**The approach.** Lockin signs in only with Sign in with Apple, so there's no username and password
to hand over: the reviewer signs in with their own Apple Account. The social side needs other
people, and a reviewer has only one phone, so **Demo Buddy** (section 3) plays the friend.

In **App Review Information**:

- **Sign-in required:** leave it unticked. The app opens and works without an account. The notes
  explain how to sign in.
- **Contact:** [OWNER: your name, phone number with +61, email]. Keep the phone nearby while the
  app is in review.
- **If App Review asks for credentials anyway**, give them a dedicated review Apple Account:
  [OWNER: review Apple Account email] / [OWNER: password]. Apple Accounts need two-factor
  authentication, so keep its trusted device with you and approve the code when App Review signs
  in. Sign this account into the review squad in advance, so it's ready.

## 3. Demo Buddy (planned, M9)

SPEC.md §7: a clearly labelled server bot that joins the reviewer's squad sessions, so the social
Live Activity can be seen with one phone. It's also how you test squads alone on TestFlight.

**What it must do**

| Area | Requirement |
|---|---|
| Identity | A server-side user named **Demo Buddy** (10 characters, within the Live Activity's 12-character `n`), handle `demobuddy`, with its own Lockling. Both words are already reserved in `fixtures/moderation/words.json`, so no real person can take or copy them. An admin script or migration creates the user and skips the name filter |
| Labelled | Wherever the app lists squad members, Demo Buddy shows a "Test bot" label. In the Live Activity, its name says enough |
| Where it lives | Only in squads made by redeeming the **review code**. Each redemption creates a fresh private "Review Squad" with the redeemer and Demo Buddy, so two reviewers never share one. The code never expires and is rate-limited (e.g. 10 redemptions an hour). It's set by Worker variables (`DEMO_BUDDY_CODE`, and `DEMO_BUDDY_ENABLED` as a kill switch), so it can be changed for each submission |
| Never | Joins real squads, accepts or redeems friend codes, appears in real squads' leaderboards, or counts in analytics |
| Joining | When a Review Squad member opens or joins a session, Demo Buddy joins 5 to 10 seconds later with a 3-minute timer. That's a priority-10 push, through the same Room code path as a real member, so the reviewer sees real pushes |
| Script | At +60 s it cheers the reviewer (priority 5; the room clears the cheer about 10 s later). At +90 s it pauses, and at +120 s it resumes (priority 5). When its timer runs out it's done (priority 10). The room ends as usual when the reviewer finishes or leaves. If the reviewer locks in again, Demo Buddy joins again |
| On request | `POST /squads/:id/demo-buddy/lock-in` (squads with Demo Buddy only), behind an **Ask Demo Buddy to lock in** button in the squad. Demo Buddy opens a session and sends the normal "Demo Buddy is locking in" alert, with the normal Join actions. It respects mute and the rate limit, but not quiet hours, because the reviewer asked for it |
| Limits | It obeys every rule in SPEC.md §4.4: coalescing, priorities, no tick pushes, the 3.5 KB payload limit. Its pushes are counted per room like any other |
| Tests | vitest for the timeline (using the fake clock `handle` already takes), isolation from real squads, a fresh squad on every redemption, the kill switch and the rate limit |
| After approval | Keep it running. Every update goes through review again |

## 4. Where things are (for the notes, and to check before submitting)

| Requirement | Where in the app | Status |
|---|---|---|
| Account deletion (5.1.1(v)) | Settings → Account → Delete account | M2, planned |
| Report and block a friend (1.2) | Friends → swipe left → Report / Block | M2, planned |
| Report and block a squadmate (1.2) | Squad → tap a member → Report / Block | **Not in the M3 plan yet**; see the checklist's open questions |
| Blocked list | Settings → Account → Blocked | M2, planned |
| Mute a squad | Squad → Mute | M3, planned |
| Quiet hours | [OWNER: where the setting lives] | M4, planned |
| Restore purchases | Paywall → Restore (Settings → Lockin Plus opens the paywall) | Shipped (M1) |
| Terms and Privacy links | Paywall footer | Shipped, but the links still point at `example.com` (`PaywallView.swift`) |
| Support contact | Support URL, and [OWNER: Settings → About → Support, once added] | M9 |

## 5. Notifications and Live Activities (4.5.3, 4.5.4)

Background for the notes above. These are SPEC.md §4.4 and §5.7 and CLAUDE.md's push rules.

- **Who gets what.** "Locking in" alerts go only to members of the squad who haven't muted it. Live
  Activity updates go only to the push tokens of people in that session's room. Nobody outside a
  squad can trigger a push to anyone.
- **How often.** Joins, finishes, early leaves, slips and `end` are priority 10. Everything else
  (pause, resume, pet progress, cheers) is priority 5, which doesn't use Apple's hourly budget.
  Changes are coalesced per room for 2 seconds, and only the latest state is sent. Timer ticks are
  never pushed: `Text(timerInterval:)` counts down on the phone. Cheers are rate-limited (M3:
  `429 cheer_too_soon`).
- **Invites.** Rate-limited per squad [OWNER: the number M4 settles], mutable per squad, quiet
  hours 22:00 to 07:00 local by default, and at most about 2 non-session notifications a day
  (streak at risk, weekly recap).
- **Remote starts.** If push-to-start ships (the M4 spike), every remote start carries an `alert`,
  as Apple requires, so it's always visible and announced.
- **Frequent updates.** The app declares `NSSupportsLiveActivitiesFrequentUpdates` so squad events
  arrive within seconds. The person can switch it off in Settings, and the server stores the
  setting (`devices.frequent_pushes`).
- **Optional.** Notifications and Live Activities can both be switched off. The app explains what
  you'd be missing, with a button to Settings, and solo sessions still work.

## 6. Lockin Plus (3.1.2)

**Products** (App Store Connect → Monetization). The IDs are fixed by `PlusPlan.productID`:

| Product | Type | ID | Price (Australia) | Notes |
|---|---|---|---|---|
| Lockin Plus Monthly | Auto-renewable, 1 month | `<bundle id>.plus.monthly` | A$3.99 | Subscription group "Lockin Plus" |
| Lockin Plus Yearly | Auto-renewable, 1 year | `<bundle id>.plus.yearly` | A$24.99 | Introductory offer: free, 1 week. The app shows "Try it free" only when the person is eligible |
| Lockin Plus Lifetime | Non-consumable | `<bundle id>.plus.lifetime` | A$49.99 | One-time purchase |

App Store prices include GST. Apple sets prices in other countries from the Australian price,
unless you set them yourself.

For each product: a display name, a description, and a review screenshot of the paywall (the
`paywall` snapshot route, `design/screens/iphone-16-pro/paywall-light.png`).
[OWNER: decide whether Plus supports Family Sharing.]

**What Plus includes.** This must match the paywall exactly, and list only features that work in
the build under review:

| Feature | SPEC.md §2 | On the paywall today | Ships in |
|---|---|---|---|
| Up to 3 squads, squads of up to 6 | Yes | "Bigger squads: Up to 6 friends, in 3 squads". "6 friends" reads as 7 people, so fix the wording | M3 |
| Full cosmetics catalogue and monthly drops | Yes | "Every cosmetic: Plus a new drop every month" | M5 (coin shop) |
| Deep Focus | Yes | "Deep Focus: Block distracting apps" | M8, needs Apple's Family Controls approval |
| Squad Boost | Yes | "Squad Boost: Unlock pet gear for your whole squad" | M7 |
| 2 streak freezes a month | Yes | "Streak freezes" | M7 |
| Custom session lengths | Yes | **Missing**, but Home already puts Custom behind Plus | Shipped (M1) |
| Full stats history, yearly recap | Yes | **Missing** | Not planned in any milestone |

**Already in the paywall** (M1): plans with prices from the App Store, the period, a renewal line
under the button ("7 days free, then A$24.99/year. Renews automatically until you cancel in
Settings."), Restore, and Terms and Privacy links. **Still to do:** real Terms and Privacy URLs, and
the Terms (EULA) and Privacy links in the App Store description (`app-store-listing.md` has them).

**Squad Boost** (in case App Review asks): while a Plus member is in a squad, the squad's pet can
wear premium gear. Nobody else is charged and nothing is transferred.

**Paywall moments** (SPEC.md §2): never at launch and never in the way of a session. They appear
after the first squad session, when you hit a free squad limit, and when you tap a Plus cosmetic or
Deep Focus.

## 7. Age rating: draft answers

Apple's questionnaire (App Store Connect → App Information → Age Rating) changed in 2025 and now
has 13+, 16+ and 18+ ratings. [OWNER: match these to the questions App Store Connect shows, and
record the rating it gives.]

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | |
| Realistic violence; prolonged graphic or sadistic violence | None | |
| Profanity or crude humour | None | Names are filtered |
| Mature or suggestive themes | None | |
| Horror or fear themes | None | |
| Sexual content or nudity; graphic sexual content | None | |
| Alcohol, tobacco or drug use or references | None | |
| Medical or treatment information | None | |
| Health or wellness topics | No | A focus timer, not a health app |
| Simulated gambling; gambling; contests | None / No | |
| Loot boxes or paid random items | No | Cosmetics are chosen, never random |
| Unrestricted web access | No | No web views to the open web |
| User-generated content | **Yes** | Handles, display names and squad names, seen only by friends and squadmates. Filtered, with report and block |
| Messaging and chat | No | No free text. Cheers are a fixed set of emoji |
| Advertising | No | |
| Parental controls | No | |
| Age assurance | No | [OWNER: change this if you add an age check] |

**Expected result:** 9+ or 13+, depending on how Apple weighs the friends features. If App Store
Connect offers a higher rating than the computed one, choose the one that matches the minimum age
in the terms ([OWNER: 13]).

## 8. App Privacy ("nutrition label"): draft

App Store Connect → App Privacy. This is based on `server/migrations/0001_init.sql`, M2.md, M3.md
and `Core/Analytics.swift`. Re-check it against the code at M9. The privacy manifest
(`App/Resources/PrivacyInfo.xcprivacy`, `NSPrivacyCollectedDataTypes`) must say the same.

**Tracking:** No. No data is used to track, there's no IDFA and no App Tracking Transparency prompt.

**Data linked to you** (all only for signed-in users):

| Apple data type | What it is in Lockin | Purpose |
|---|---|---|
| Contact Info → Name | Display name, and the name Apple shares at sign-in if the person allows it (used only as a suggestion) | App Functionality |
| User Content → Other User Content | Handle, squad names, notes in reports | App Functionality |
| Identifiers → User ID | Lockin user ID, Sign in with Apple identifier | App Functionality |
| Identifiers → Device ID | APNs device, Live Activity and push-to-start tokens. Declared to be careful, because they're per-device | App Functionality |
| Usage Data → Product Interaction | Focus sessions (times, minutes, states, slips), cheers, the server event log, coins | App Functionality, Analytics |
| Purchases → Purchase History | Plus status (`users.plus_until`), and RevenueCat's records from M7 | App Functionality |
| Other Data → Other Data Types | Time zone, used for quiet hours, streak days and the Monday reset | App Functionality |

**Data not linked to you:**

| Apple data type | What it is | Purpose |
|---|---|---|
| Diagnostics → Other Diagnostic Data | `liveActivity.failed` counts | Analytics |

Analytics counts are Product Interaction, which is already declared as linked because of the
server's session data. The analytics provider's copy needs no separate declaration, but must not be
linkable to the account. [OWNER: once the analytics provider is chosen, check what its SDK collects
and what its privacy manifest says. If it adds an install ID, that's Identifiers → Device ID, not
linked.]

**Not collected:** location (precise or coarse), contacts, email address, phone number, physical
address, health and fitness, financial info (Apple handles payment), sensitive info, browsing and
search history, photos and videos (QR scanning happens on the device), audio, emails or text
messages, crash data (beyond Apple's own reports), advertising data.

**Privacy policy URL:** [OWNER: https://yourdomain/privacy]
