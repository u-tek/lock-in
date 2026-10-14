# App Store listing

Draft metadata for **App Store Connect → the app → the version** (and **App Information** for name,
subtitle and categories). Character limits are Apple's, and every count here was checked. Re-count
after any edit.

The listing has one job beyond selling: Guideline 4.3 (spam). Focus timers are a crowded category,
so the name, the first screenshot and the first line of the description all lead with the thing
nobody else does: **your friends' live timers in your Dynamic Island** (SPEC.md §7).

## Name (30 characters max)

**Lockin** (6)

> **[OWNER: check availability before anything else.]** SPEC.md's header calls "Lockin" a working
> name and asks for a `NAMES.md` with the App Store and domain checks. That file doesn't exist yet.
> Search the App Store for "Lockin" and "Lock in", try to create the name in App Store Connect
> (it must be unique), and check the domain and the social handles you'd want. If the name is
> taken, these fit and keep the search words:
>
> - `Lockin: Study with Friends` (26)
> - `Lockin - Focus with Friends` (27)
>
> Whichever you use, the app's home-screen name stays `Lockin` (`CFBundleDisplayName` in
> `project.yml`).

## Subtitle (30 characters max)

**Focus timer with your friends** (29)

Alternatives:

- `Friends' timers in your Island` (30): the closest to the hook, but "Island" on its own may puzzle
  people who don't know the feature.
- `Study with friends, live` (24)

The App Store already searches the name and subtitle, so the keywords below don't repeat their
words.

## Promotional text (170 characters max, can change without a new build)

> Lock in with your squad: their live timers sit in your Dynamic Island while you study. Grow a pet
> together, keep your streak going and see who's still locked in.

(161.) Change it for the season, e.g. "Exam season? Lock in with your squad…" around October and
November, or for Semester 1 in February.

## Keywords (100 characters max, commas, no spaces)

```text
study,pomodoro,squad,productivity,homework,exam,revision,streak,pet,group,body,doubling,desk,uni
```

(96.) Notes:

- `body` and `doubling` cover "body doubling", a common way people describe studying alongside
  someone. The App Store combines separate keywords, so two short words beat one long phrase.
- `revision` and `uni` are how Australians, New Zealanders and Brits search. For the US storefront,
  [OWNER: consider swapping them for `studying,college`].
- Left out on purpose: other apps' names (Focus Friend, Forest, Widgetable) and Apple feature names
  (Dynamic Island, StandBy, Live Activity). Guideline 2.3.7 doesn't allow other apps' names, and
  Apple's trademarks are safer in the description than in keywords.

## Description (4,000 characters max)

```text
Your friends' focus timers, live in your Dynamic Island.

Lockin is a focus timer you share. Start a session with your squad and everyone's countdown sits in your Dynamic Island and on your Lock Screen while you work. Glance down to see who's still locked in, who's on a break and who just finished, without opening a thing.

LOCK IN TOGETHER
• Start a squad session and your friends get a nudge to join
• Everyone runs their own timer, side by side in one Live Activity
• Send a quick emoji cheer that pops up on a friend's Lock Screen
• No Dynamic Island? Your squad shows on the Lock Screen instead

RAISE A PET TOGETHER
• Your squad's pet hatches after your first group session
• It grows with every minute you focus, and it's happiest when everyone shows up
• Keep your streak alive: the day counts when half the squad locks in
• A weekly leaderboard for your squad, fresh every Monday

DESK MODE
Stand your iPhone on its side on a charger and StandBy turns your squad into a full-screen study clock. It's made for study-with-me videos.

GREAT SOLO, TOO
• 25, 50 or 90 minutes, one tap
• Make your Lockling, a little padlock with a face, and watch it lock in with you
• Earn coins for every focused minute and spend them on cosmetics
• No account needed to start

MADE FOR FOCUS, NOT FEEDS
• Add friends by code, QR code or link only. No contacts, no strangers, no public rooms
• No chat, no ads, no location
• Squads, the Live Activity with friends and invites are free

LOCKIN PLUS
Optional, for more: squads of up to 6 and up to 3 squads, every cosmetic plus monthly drops, Deep Focus to block distracting apps, Squad Boost for your squad's pet, streak freezes and custom session lengths.

Choose monthly, yearly (with a 7-day free trial) or a one-time lifetime purchase. Subscriptions are charged to your Apple Account and renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel them in Settings > [your name] > Subscriptions.

Terms of Use: [OWNER: https://yourdomain/terms]
Privacy Policy: [OWNER: https://yourdomain/privacy]
```

[OWNER: before submitting, make the Lockin Plus paragraph match the paywall exactly, and remove
anything that hasn't shipped. Deep Focus needs Apple's Family Controls approval (M8), and Squad
Boost and streak freezes are M7. Do the same for any free feature above that isn't in the build,
like the pet, streaks and leaderboard (M5).]

## Other fields

| Field | Value |
|---|---|
| Primary category | **Productivity** |
| Secondary category | **Education** (students search here). Lifestyle is the fallback |
| Avoid | **Social Networking.** It undersells the focus side, invites "is this a social network for teens?" questions in review, and doesn't help with Australia's social media minimum age (see the privacy policy's teenagers section) |
| Support URL | [OWNER: https://yourdomain/support] (from `support.md`) |
| Marketing URL | [OWNER: https://yourdomain] (optional) |
| Privacy Policy URL | [OWNER: https://yourdomain/privacy] (from `privacy-policy.md`) |
| EULA | Apple's standard licence agreement. Our own terms (`terms.md`) are linked from the description and the paywall |
| Copyright | `[OWNER: year] [OWNER: your name or business name]` |
| Age rating | See `app-review-notes.md` §7 |
| Price | Free, with in-app purchases (Lockin Plus) |
| Availability | [OWNER: countries. Australia and New Zealand first keeps US and EU obligations for later; see the checklist] |

## Screenshots: the 6.9-inch set

Apple needs one iPhone set, and 6.9-inch (1320 × 2868 portrait) is the size it scales down for
smaller phones. CI renders it: the `store.1`…`store.5` snapshot routes run on the **iPhone 16 Pro
Max** simulator, in light appearance, and land in `design/appstore/6.9-<n>-light.png`
(`scripts/export-snapshots.sh`, `scripts/collect-snapshots.sh`) when a commit subject says
`[snapshots: store]` (or names one, `[snapshots: store.2]`). Upload them in this order.

Each route renders the app's own views (the `LiveActivity` module's presentations, the widgets'
`WidgetViews`, the `Creature` views and the real screens) under a headline drawn by the route
(`App/Sources/Snapshot/StoreScreenshots.swift`): SF Pro Rounded Bold, white, with a short line
under it, on the tint deepening to purple, over a phone drawn round the screen. They're not
mock-ups, which keeps them honest under Guideline 2.3.3. Squads use the made-up friends the
onboarding already uses (Ava, Noor, Kai and so on), never real testers' names.

The first three show up in search results, so they carry the 4.3 story.

| # | Route | Headline | Line under it | What it shows | Built from |
|---|---|---|---|---|---|
| 1 | `store.1` | **Your friends, in your Dynamic Island** | See who's still locked in, without opening a thing. | The expanded island (you and three squadmates, all locked in, with their countdowns) over the Home Screen with the Squad pet and Lock in widgets | `ExpandedIslandPreview` (the Lab's frame round the `LiveActivity` views), `WidgetViews` |
| 2 | `store.2` | **Lock in together** | Your whole squad's timers, right on your Lock Screen. | A Lock Screen at night: the clock, the Squad pet's Lock Screen widgets, and the squad's Live Activity with five members (three locked in, one on a break, one done) | `LockScreenPreview`, `SquadPetWidgetView` |
| 3 | `store.3` | **Desk mode for study sessions** | Stand your phone on its side while it charges. | A phone on its side in StandBy on a stand on a desk: squad name, "4 of 4 locked in", the pet, your big countdown and everyone's Locklings with timers | The StandBy presentation (`lab.liveactivity.standby`) |
| 4 | `store.4` | **Grow a squad pet** | It grows with every minute you focus together. | The squad's page: the pet (teen sprout), its mood, the six-day streak and this week's leaderboard | `squads.detail` |
| 5 | `store.5` | **Works solo too** | Earn coins, keep a streak, dress up your Lockling. | Home, solo: your Lockling, coins, today's minutes, your streak and the session lengths | `home` |

Ideas for more, up to 10 (not built):

| Headline | What it shows |
|---|---|
| **Make your Lockling.** | The Lockling maker with a grid of other Locklings in different colours, hats and poses |
| **More squad, more style.** | Plus features (bigger squads, cosmetics, Squad Boost and so on), no prices |
| **Friends by code. No strangers.** | The Friends screen with your code and QR code, and the friends list with Locklings |
| **Cheer them on.** | Lock Screen card with a cheer popping on a squadmate |

Rules for all of them:

- Light appearance (the script exports light only). The island and StandBy stay dark as they are
  on a real phone, and the Lock Screen shot is a Lock Screen at night.
- The system status bar is hidden; the phones drawn in the shots say 9:41, as in the snapshots.
- Don't show prices or "free trial" in screenshots. The paywall shows the right local price.
- Re-render the set whenever the island, Lock Screen or StandBy views change, as part of the
  "visible in the Live Activity Lab" rule in CLAUDE.md.

### App Preview video (optional)

15 to 30 seconds, 9:16, recorded on a real phone, since CI can't film the island. Suggested cut:
lock in (2 s) → a friend joins and the island shows +1 (4 s) → long-press for the expanded view
(4 s) → lock the phone to see the squad on the Lock Screen (4 s) → StandBy on a desk (5 s) → a
squadmate finishes and their Lockling celebrates (4 s). App previews must show only the app and the
system UI it creates, with no hands or other phones. Film the hands-on versions for social media
instead (see the launch content plan in `checklist.md`).
