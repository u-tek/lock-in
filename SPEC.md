# Lockin — Product & Technical Spec

> Working name. "Lock in" is slang for getting focused. Check App Store name and domain availability before launch (see `NAMES.md` once it exists).

**One line:** Lock in with your friends — their live focus timers sit in your Dynamic Island and on your Lock Screen while you work, and your squad's shared pet only grows when everyone stays focused.

**Who it's for:** students and young workers (roughly 15–25) who already study with friends on FaceTime/Discord, watch "study with me" content, and use focus timers.

**Why it can win:**
- Focus apps with a cute character are proven: Focus Friend (Hank Green) reached #1 on the US App Store in 2025.
- Many focus timers show *your own* session in the Dynamic Island. None we found show *your friends'* live sessions there. That's the gap, and it's the screenshot/TikTok moment.
- Widgetable proved people will co-parent a pet with friends on their Lock Screen and pay for it.

---

## 1. The experience

### 1.1 First run (target: lock in within 60 seconds)
1. Splash → "Lock in with your friends." One-screen pitch showing the Dynamic Island with three friends.
2. Pick your creature (body shape, colour, eyes). No account needed yet.
3. Ask for notification permission with context ("so you know when your squad locks in").
4. Start a first solo 25-minute session immediately. The Live Activity appears. Tell them to lock the phone and look.
5. On completion: coins, creature celebrates, then **"Lock in with friends?"** → Sign in with Apple → create squad → share invite.

Solo must be satisfying on its own — most users arrive with zero friends on the app.

### 1.2 Core loops
| Loop | Cadence | What happens |
|---|---|---|
| Session | Each use | Start (solo or squad) → Live Activity shows you + friends → finish → coins, pet XP, share card |
| Social | Each session | Starting a squad session notifies the squad ("Ava is locking in 🔒 — join?"). Joining puts everyone in everyone's island. |
| Daily | Daily | Squad streak: the day counts if at least half the squad completes a session ≥ 20 min (tunable). Pet mood reflects today. |
| Weekly | Weekly | Squad leaderboard by focused minutes, reset Monday (user's local time). Weekly recap notification. |
| Collection | Ongoing | Coins buy cosmetics for creature and squad pet. Pet evolves through stages. |

### 1.3 The Live Activity (the product's centrepiece)
Shown during every session. Must support every presentation:

- **Compact (one Live Activity in the island):** leading = your creature in its current state; trailing = number of squadmates focusing right now (e.g. "+3") or your remaining time when solo.
- **Minimal (several apps' activities):** your creature only.
- **Expanded (long-press, and briefly on important updates):** up to 4 squad members as creatures with names and their own countdowns; squad pet with progress bar; buttons: Pause, End, Cheer.
- **Lock Screen / banner (all devices, and the only view on iPhones without the island):** full squad row (up to 6) with individual countdowns, pet, squad name, streak.
- **StandBy ("desk mode"):** the Lock Screen presentation scales to fill the screen when the phone is charging on its side. Design for this — it's the "study with me" shot people will film.
- **Apple Watch Smart Stack / Mac:** the system mirrors Live Activities to paired devices; make sure they look acceptable there.

Member states, each with a distinct creature pose:
`focusing` (eyes down, working) · `break` (stretching) · `paused` · `done` (celebrating) · `left` (greyed, waving) · `slipped` (sheepish, sweat drop — Deep Focus only).

### 1.4 Sessions
- Presets: 25 / 50 / 90 minutes, plus custom (Plus). Optional Pomodoro breaks.
- Hard cap: 4 hours per session (Live Activities are limited to 8 hours active).
- **Squad session = a room.** Each member runs their own timer inside the shared room; others can join at any time while it's open. The room ends when the last member finishes or leaves.
- Ending early or pausing too long counts as breaking focus: your creature shows it to the squad, and the pet's mood dips slightly. Never punishing — gently social.

### 1.5 Squad pet
- Each squad has one pet. It hatches from an egg on the squad's first completed group session.
- Grows from squad XP (focused minutes). Four stages: egg → baby → teen → adult, then cosmetic "prestige" forms.
- Mood 0–3 from today's squad activity: happy when people focused today, hungry when nobody has, sad briefly when someone breaks focus mid-session.
- Lives in the Live Activity during sessions and in Home/Lock Screen widgets the rest of the time.

### 1.6 Friends & squads
- Friends are added by **code, QR or invite link** only. No contact upload, no search for strangers, no public rooms in v1.
- A squad is 2–4 people (free) or up to 6 (Plus). A user can be in 1 squad (free) or 3 (Plus).
- **No free-text chat in v1.** Interaction is limited to "cheers" (a small set of emoji reactions) that appear briefly on the recipient's Live Activity. This keeps moderation tiny and suits a young audience.
- Handles and display names are user-generated content: profanity filter, report, block (see §7).

### 1.7 Viral surfaces
- **Share card** at session end: the squad's creatures, total time, streak, invite code. Rendered in-app at 9:16 (Stories) and 1:1. One tap to share.
- **Invite link**: `https://<domain>/j/<code>` opens the app if installed, otherwise a landing page with the App Store link and the code to enter after install. (Deferred deep linking is out of scope for v1.)
- **Desk mode** (StandBy) and the island itself are the filmable moments — the onboarding should teach both.
- **Widgets**: squad pet + streak (Home and Lock Screen); a "Lock in" interactive widget and a Control Center control that start a solo session.

---

## 2. Monetisation

Everything that makes the app spread stays free. Plus sells depth, cosmetics and control.

| Free | Plus |
|---|---|
| Unlimited solo and squad sessions | Up to 3 squads |
| 1 squad, up to 4 members | Squads up to 6 members |
| Live Activity with friends | Full cosmetics catalogue + monthly drops |
| Squad pet, streaks, weekly leaderboard | Deep Focus: block distracting apps during sessions (§5.8) |
| Base creatures and cosmetics bought with coins | Custom session lengths, full stats history, yearly recap |
| | 2 streak freezes a month |
| | **Squad Boost:** one Plus member unlocks premium pet accessories for the whole squad |

**Starting price to test:** A$3.99/month, A$24.99/year with a 7-day free trial, A$49.99 lifetime. Benchmark: Focus Friend charges US$1.99/month, US$14.99/year, US$29.99 lifetime. Run pricing experiments through RevenueCat.

**Paywall moments** (never at launch, never blocking the core loop):
1. After the first completed *squad* session (highest emotion).
2. Creating a second squad or adding a 5th member.
3. Tapping a Plus cosmetic or Deep Focus.

---

## 3. Platform constraints that shape the design

These come from Apple's documentation and are non-negotiable:

| Constraint | Consequence |
|---|---|
| A Live Activity is active for at most 8 hours, then leaves the Dynamic Island; it can stay on the Lock Screen up to 4 more hours. | Sessions capped at 4 h. Always end activities explicitly. |
| A Live Activity runs in its own sandbox and **cannot access the network or location**. | All art (creatures, pets) must be drawn in the widget extension from data in the payload. No remote images. Friends' updates arrive only via ActivityKit pushes or from the app. |
| Static + dynamic Live Activity data combined **must not exceed 4 KB**. | Compact payload with short keys; server asserts < 3.5 KB. |
| The system **ignores SwiftUI animation modifiers** in Live Activities; only built-in content transitions animate (text, images, SF Symbols, view insert/remove), and nothing animates in Always-On. | Creatures change *pose* between states; countdowns use `Text(timerInterval:)` so they tick on-device with zero pushes. |
| ActivityKit pushes have an hourly budget. Priority `10` counts against it; priority `5` doesn't. | Priority 5 by default; 10 only for meaningful squad events. Coalesce bursts. |
| The app must be in the foreground to start a Live Activity, except via a `LiveActivityIntent` (widgets, controls, Shortcuts) or a push-to-start push (iOS 17.2+). | Join flows open the app, or use push-to-start (spike in M4). |
| Push-to-start payloads must include an `alert`. Broadcast channels cannot start Live Activities. | Any remote start is visible and announced to the user. |
| Image assets larger than the presentation can stop the activity from starting (minimal ≤ 45 × 36.67 pt). Content taller than 160 pt may be truncated. | Creatures are SwiftUI shapes, sized per presentation. |
| Content-state is decoded with the system's **default** JSON strategies; custom encoders break updates. | Times are `Double` Unix seconds, not `Date`. Keys must match the Swift type exactly. |
| Screen Time APIs (Family Controls) need a **distribution entitlement Apple must approve** — for the app and each extension — and approval can take weeks. | Request it in M0. Deep Focus ships later (M8) and is Plus-only. |
| Pushes need the paid Apple Developer Program. Free sideloaded builds can't receive them. | Paid account from day one; test pushes on real devices via TestFlight. |

---

## 4. Architecture

```
iPhone app (SwiftUI)                         Backend (Cloudflare)
 ├─ App target                                ├─ Worker: REST API + auth
 ├─ Widget extension                          ├─ Durable Object per live session ("room")
 │   ├─ Live Activity (all presentations)     │    holds room state, computes content-state,
 │   ├─ Home/Lock Screen widgets              │    coalesces events, fans out APNs pushes,
 │   └─ Control Center control                │    serves WebSocket for the in-app live view
 ├─ (M8) Screen Time extensions               ├─ D1 (SQLite): users, friends, squads, sessions…
 └─ Packages/LKKit (shared modules)           └─ APNs sender (token auth, .p8 key)
            │                                              │
            └──────── HTTPS + WebSocket ───────────────────┘
                          APNs ──▶ each member's Live Activity push token
```

### 4.1 Why token pushes, not broadcast channels (v1)
Squads are 2–6 people, so the server sends one push per member per event — a handful of requests. That avoids channel management and the cap of about 10,000 active broadcast channels per app (reported by third-party docs; confirm on Apple's channel-management page). Keep the content-state identical for every recipient (see §4.3) so a move to broadcast channels for large public rooms later is a server-only change.

### 4.2 Backend choice
Cloudflare Workers + Durable Objects + D1 (you've already shipped a Worker for Screenshot Brain). APNs only speaks HTTP/2. There's a Workers-compatible APNs client and open-source relays sending APNs from Workers, but **prove it with a deployed Worker in the M0 spike**. If APNs rejects requests from the Worker, move only the sender to a tiny Node service using `node:http2` and keep everything else on Cloudflare.

APNs auth: token-based (ES256 JWT from the `.p8` key, Team ID, Key ID). Cache the JWT and refresh it every 20–50 minutes. TestFlight and App Store builds use the **production** APNs host; Xcode debug builds use sandbox — store the environment per device token.

### 4.3 Live Activity model (shared by app, widget extension and server)

```swift
struct LockinAttributes: ActivityAttributes {
    // Static — set when this device starts the activity.
    let sid: String        // session (room) id, short
    let me: String         // this device owner's member id, so one payload serves everyone
    let sq: String?        // squad name, ≤ 20 chars; nil for solo

    struct ContentState: Codable, Hashable {
        var v: Int         // monotonically increasing state version
        var m: [Member]    // ≤ 6, server order (host first); views put `me` first
        var p: Pet?        // squad pet snapshot; nil when solo
        var c: Cheer?      // most recent cheer, shown briefly

        struct Member: Codable, Hashable {
            var i: String  // member id (short)
            var n: String  // display name, ≤ 12 chars
            var a: String  // avatar code, e.g. "b3.c7.e2.h4" (body, colour, eyes, hat)
            var s: Int     // 0 focusing, 1 break, 2 paused, 3 done, 4 left, 5 slipped
            var b: Double  // started at (Unix seconds)
            var e: Double  // ends at (Unix seconds); while paused, remaining = e - pausedAt
            var q: Double? // paused at (Unix seconds)
        }
        struct Pet: Codable, Hashable {
            var k: String  // species/stage code, e.g. "sprout.2"
            var md: Int    // mood 0–3
            var x: Double  // progress to next stage, 0–1
        }
        struct Cheer: Codable, Hashable {
            var f: String  // from member id
            var t: String  // to member id
            var k: Int     // cheer kind (emoji index)
            var at: Double // Unix seconds
        }
    }
}
```

Six members ≈ 600–700 bytes of JSON — far inside 4 KB. The server rejects anything over 3.5 KB.

### 4.4 Push rules
| Event | Priority | Alert? |
|---|---|---|
| Member joins, finishes, leaves early, slips | 10 | No — alerts light up the screen and would break everyone's focus |
| Pause / resume, pet progress, cheers | 5 | No |
| Last member finishes → `end` with final state, `dismissal-date` = now + 30 min | 10 | No |
| Timer ticks | **never** — rendered locally | — |

- Coalesce events per room within a 2–3 second window; send only the latest state.
- Set `stale-date` = latest member end + 5 min, advanced with each update.
- Also update the activity from the app whenever it's running (Apple recommends both, because pushes can be missed).
- Headers: `apns-push-type: liveactivity`, `apns-topic: <bundle id>.push-type.liveactivity`, `apns-priority: 5|10`. Payload `aps`: `timestamp` (Unix seconds), `event` (`update`/`end`), `content-state`, optional `stale-date`, `dismissal-date`, `relevance-score`.
- Log push counts per room so budget problems show up in metrics, not reviews.

### 4.5 Joining a squad session
1. A starts a squad session → server creates the room and sends a normal alert push to squad members who haven't muted it: "Ava is locking in 🔒" with actions **Join 25** / **Join 50**.
2. **v1:** the action opens the app (foreground), which joins via the API and starts the Live Activity locally with `pushType: .token`, then uploads the activity's push token.
3. **M4 spike:** a background action asks the server to push-to-start the activity (payload with `event: start`, `alert`, `attributes-type`, `attributes`, and on iOS 18 `input-push-token: 1`). The system starts the activity and wakes the app to receive its update token. Ship only if it's reliable.

### 4.6 Data model (D1)
```
users(id PK, apple_sub UNIQUE, handle UNIQUE, display_name, avatar_code, coins,
      plus_until, created_at, deleted_at)
friendships(user_id, friend_id, created_at)              -- stored both directions
blocks(user_id, blocked_id, created_at)
reports(id PK, reporter_id, target_user_id, reason, created_at)
squads(id PK, name, owner_id, pet_species, pet_xp, pet_stage,
       streak_count, streak_last_day, created_at)
squad_members(squad_id, user_id, joined_at, muted)
invite_codes(code PK, kind['friend'|'squad'], target_id, created_by, expires_at)
devices(id PK, user_id, apns_token, apns_env, push_to_start_token,
        la_enabled, frequent_pushes, tz, updated_at)
sessions(id PK, squad_id NULL, host_id, status, created_at, ended_at)
participants(session_id, user_id, state, planned_min, started_at, ends_at,
             paused_at, ended_at, focused_sec, la_token, slips)
events(id PK, session_id, user_id, type, at, meta_json)   -- for stats & debugging
cosmetics(user_id, item_id, acquired_at)
```

### 4.7 API (JSON over HTTPS; bearer token after Sign in with Apple)
```
POST   /auth/apple                      → { token, user }
GET    /me      PATCH /me     DELETE /me (account deletion, required by App Review)
POST   /devices                         { apnsToken, env, pushToStartToken?, laEnabled, tz }
GET    /friends   POST /friends/redeem/:code   DELETE /friends/:id
POST   /blocks    POST /reports
GET    /squads    POST /squads   POST /squads/:id/invite   POST /squads/join/:code
PATCH  /squads/:id/members/me           { muted }
POST   /sessions                        { squadId?, minutes } → { session, contentState }
POST   /sessions/:id/join               { minutes }
POST   /sessions/:id/la-token           { token }
POST   /sessions/:id/{pause|resume|end|slip}
POST   /sessions/:id/cheer              { to, kind }
GET    /sessions/:id                    → snapshot
WS     /sessions/:id/live               → room state stream for the in-app view
GET    /leaderboard/:squadId?week=…
POST   /admin/push-test                 (dev only) send a test update to a session
```
The server is authoritative for squads, streaks, XP and coins. The app is authoritative for its own timer while offline and reconciles on reconnect.

---

## 5. iOS app structure

Mirror the Screenshot Brain layout: XcodeGen `project.yml`, `Makefile`, one Swift package with a target per module, CI on GitHub Actions macOS runners.

### 5.1 Targets
- `App` — the app.
- `Widgets` — Live Activity, Home/Lock Screen widgets, Control Center control.
- (M8) `ShieldConfiguration`, `ShieldAction`, `DeviceActivityMonitor` extensions.
- Shared App Group for my member id, cached squad info and widget data.

### 5.2 Modules (`Packages/LKKit`)
| Module | Responsibility | Milestone |
|---|---|---|
| `Core` | Config, ids, App Group paths, logging, analytics (event counts only) | M0 |
| `Model` | Domain types and `LockinAttributes` (linked by app **and** widget extension) | M0 |
| `DesignSystem` | Tokens, typography, components | M0 |
| `Creature` | Avatar codes → SwiftUI-drawn creatures and pets, every state, sized per presentation | M1 |
| `SessionEngine` | Local session state machine, timers, persistence, reconciliation | M1 |
| `LiveActivity` | Start/update/end, push-token streams, `LiveActivityIntent`s (Pause, End, Cheer, Start solo) | M1 |
| `API` | REST client, Keychain token, WebSocket | M2 |
| `Social` | Friends, squads, codes, QR, report/block | M2 |
| `Progress` | Coins, XP, streak display, leaderboard | M5 |
| `ShareCards` | `ImageRenderer` cards 9:16 and 1:1 | M6 |
| `Paywall` | RevenueCat, entitlements, Squad Boost | M7 |
| `DeepFocus` | Family Controls picker, shields, slips | M8 |
| `Notifications` | Categories/actions, local reminders | M4 |

### 5.3 Creatures
- **Original design only.** Don't imitate Focus Friend's bean, Pixel Pals, Widgetable's pets or any known character.
- Drawn with SwiftUI shapes (no bitmap assets), so they scale cleanly, stay tiny in the payload, and work inside the network-less extension.
- Must read clearly at ~20 pt in the compact island and in Always-On (rendered dark, no animation).
- Avatar code grammar: `b<body>.c<colour>.e<eyes>.h<hat>`; unknown parts fall back to defaults so old app versions never crash on new cosmetics.

### 5.4 Minimum iOS
iOS 18.0: push-to-start with `input-push-token`, interactive widgets/controls, and broadcast channels if needed later. Use Liquid Glass styling where available.

### 5.5 Persistence
GRDB in the App Group container (as in Screenshot Brain) for sessions, history and cached social data. Keychain for the auth token.

### 5.6 Analytics
Event counts only, no content. Track: onboarding steps, first session completed, Live Activity started/failed, squad created, invite shared, invite redeemed, squad session joined, pushes per room, D1/D7/D30 retention, paywall shown/started trial/converted.

### 5.7 Notifications
- "X is locking in" (per-squad mute, quiet hours 22:00–07:00 local by default).
- Streak at risk (local, once, at a user-chosen time, only if the squad's day isn't counted yet).
- Weekly recap (Monday).
- Never more than ~2 non-session notifications a day.

### 5.8 Deep Focus (Plus, M8)
User picks distracting apps with the Family Controls picker; during a session they're shielded. Choosing "open anyway" on a shield records a **slip**: the creature shows it to the squad and the pet's mood dips. The extensions write slips to the App Group; the app syncs them (check whether the extensions may call the network — if not, sync on next launch).

---

## 6. Milestones

Each milestone ends with CI green, a simulator build artifact, and screens exported for review.

**M0 — Foundations and admin**
- Repo, XcodeGen, Makefile, LKKit modules, CI (build + tests), server skeleton with tests.
- Apple setup: App ID with Push Notifications (+ Broadcast capability enabled on developer.apple.com for later), App Group, APNs `.p8` key.
- **Submit the Family Controls distribution request now** (app and each planned extension bundle ID).
- **Spike:** a deployed Worker sends a Live Activity update to a TestFlight build on a real iPhone. Record the result in `docs/spikes/apns-worker.md`.

**M1 — Solo lock-in (no backend)**
- Creature picker, 25/50/90 sessions, local history, coins.
- Live Activity in every presentation with `Text(timerInterval:)` countdown; Pause/End via `LiveActivityIntent`; StandBy layout.
- A debug "Live Activity Lab" screen that renders every presentation × state with fake squads, so CI can snapshot them.
- Done when: all presentations render on iPhone 16 Pro and iPhone SE simulators; graceful handling when Live Activities are disabled; orphaned activities cleaned on launch.

**M2 — Accounts and friends**
- Sign in with Apple, handle picker with profanity filter, friend codes/QR/links, friends list, block/report, in-app account deletion.

**M3 — Squad sessions (the core)**
- Squads, rooms (Durable Objects), join/leave/pause/end, token push fan-out with the rules in §4.4, WebSocket live view in-app, reconciliation on foreground.
- Done when: three real iPhones in one squad see each other's joins and finishes in the island within ~5 s; payloads asserted < 3.5 KB; per-room push counts logged.

**M4 — Invites and joining**
- "X is locking in" notifications with Join actions, mute and quiet hours.
- Spike push-to-start joining (§4.5 step 3); ship only if reliable.

**M5 — Pet, streaks, leaderboard, cosmetics**
- Egg hatching, XP, stages, moods, streak rules, weekly leaderboard, coin shop.

**M6 — Viral surfaces**
- Share cards, Home/Lock Screen widgets, Control Center control, onboarding polish, App Store screenshots generated from real screens.

**M7 — Plus**
- RevenueCat paywall, entitlements, Squad Boost, streak freezes, the three paywall moments.

**M8 — Deep Focus** (needs the approved entitlement)
- App picker, shields during sessions, slips.

**M9 — Launch**
- Privacy policy, support URL, App Review notes, demo accounts, TestFlight with 20+ real students across several squads, analytics review, launch content plan (desk-mode and island videos).

---

## 7. App Review and safety checklist
- **Spam (4.3):** focus timers are a crowded category. Screenshots, description and review notes must make the live-squad Live Activity the obvious difference.
- **Push and Live Activity abuse (4.5.3):** invites only go to squad members, are rate-limited and mutable; remote starts always carry an alert.
- **User-generated content (1.2):** handles/display names filtered; report and block in-app; contact info published.
- **Account deletion (5.1.1(v)):** in-app, deletes server data.
- **Subscriptions (3.1.2):** state exactly what Plus includes and the price before purchase.
- **Demo access (2.1):** review account plus a clearly labelled "Demo Buddy" server bot that joins the reviewer's squad sessions so the social Live Activity can be seen.
- **Young users:** honest age rating; no open chat, no strangers, no location, minimal data. Check privacy obligations for teenage users in your launch countries.
- **Originality (4.1):** original creatures, name and art.

## 8. Costs to plan for
- Apple Developer Program (A$149/year) — required for push.
- Cloudflare Workers / Durable Objects / D1 — check current plan limits; start on the cheapest tier that includes Durable Objects.
- RevenueCat — free to start.
- A domain for invite links and the privacy policy.

## 9. Open questions (verify before building the affected part)
1. APNs from a deployed Worker (M0 spike).
2. Push-to-start joins from a background notification action (M4 spike).
3. Whether Screen Time extensions can make network requests (M8).
4. Exact compact/minimal island dimensions per device (Apple HIG Live Activity specs).
5. Current broadcast channel limit, if public rooms are ever added.
6. Final name, App Store availability, domain.

## Sources
- Apple: Displaying live data with Live Activities — limits (8 h, 4 KB, no network), presentations, StandBy, animation rules.
- Apple: Starting and updating Live Activities with ActivityKit push notifications — headers, payloads, push-to-start, priority budget, default JSON decoding.
- Apple: App Review Guidelines (updated June 8, 2026).
- Apple Developer Forums: Family Controls distribution entitlement approval process and timelines.
- Focus Friend App Store listing and press coverage (pricing, #1 ranking).
- Widgetable and Pixel Pals App Store listings (existing pet and Dynamic Island apps).
