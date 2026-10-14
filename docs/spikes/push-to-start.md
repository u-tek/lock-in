# Spike: joining from a notification button with push-to-start (M4)

Status: **PENDING**. Built behind a developer switch; waiting on a run with two TestFlight phones.

## Question

SPEC.md §4.5 step 3 and §9 question 2: when a squadmate locks in, can someone tap **Join 25** on
the "is locking in" alert, **without unlocking or opening the app**, and have the room's Live
Activity appear on their Lock Screen, live, within a few seconds?

## Why it matters

The v1 path (§4.5 step 2) is a foreground button: tapping Join 25 asks for Face ID, opens Lockin,
joins the room and starts the Live Activity in the app. It works, but it pulls people into their
phone at the exact moment they meant to put it down. A background button that joins from the Lock
Screen is the better product, if it's reliable. SPEC.md §4.5: "Ship only if it's reliable."

Apple only lets an app start a Live Activity while it's in the foreground, from a
`LiveActivityIntent`, or by push-to-start. A notification button running in the background is
none of those, so the server has to start the activity by push.

## What's built

| Piece | Where |
|---|---|
| The developer switch **Join without opening** (off by default), kept in the App Group (`LKJoinWithoutOpening`). Switching it registers `LK_LOCKIN` again with background buttons: no `.foreground`, no `.authenticationRequired` | `App/Sources/Developer/DeveloperMenu.swift`, `App/Sources/Notifications/SquadAlerts.swift`, `Packages/LKKit/Sources/Notifications/` |
| The push-to-start token saved to the App Group each time ActivityKit issues one, so a background launch (which runs no screen) has it | `LiveServices.watchPushToStartTokens()` in `App/Sources/AppServices.swift` |
| The background join: `POST /sessions/:id/join` with `pushToStart: { token, env }`. The notification centre's completion handler is called once the join has finished, or after 20 seconds at most | `LiveServices.joinWithoutOpening` |
| The server joins, sends the push-to-start ("You're locked in with Ava", no sound), then answers `Joined` plus `pushedToStart` | `server/src/sessions.ts`, `server/src/pushToStart.ts` |
| The session engine takes up the activity iOS starts: it watches `Activity<LockinAttributes>.activityUpdates` (and the running activities, for one that came before the answer) for the room's `sid`, makes it the room's activity and uploads its update token with `POST /sessions/:id/la-token`, as for one it started itself. A second activity for the same room ends at once | `SessionEngine.joinSquadSession`, `takeUp(pushed:)` in `Packages/LKKit/Sources/SessionEngine/SessionEngine+Squad.swift` |
| The fallback: when `pushedToStart` is false (or the push never arrives), the app starts the activity itself the next time it's in the foreground; at once if it already is | the same, through `reconcile()` |
| A relaunch finds the room's activity by `sid` if the app was killed before taking it up | `restoreActivity()` in `SessionEngine.swift` |
| **Last background join** in the Developer menu: pushed to start, not pushed, join failed or timed out, and how long it took | `DeveloperMenu.swift` |
| **Copy push-to-start token**: copies `{"token":"…","env":"production"}`, the body of `POST /admin/push-to-start-test`, which push-starts the demo squad on one phone | `DeveloperMenu.swift`, `server/src/admin.ts` |
| Analytics: `notifications.pushToStartJoin`, counted when the server says it pushed | `Packages/LKKit/Sources/Core/Analytics.swift` |

With the switch off, nothing here runs: Join 25 and Join 50 open the app (v1).

### What happens when B taps Join 25

1. A locks in with the squad. The server opens the room and alerts B: "Library Goblins: Ava is
   locking in 🔒".
2. B, phone locked, pulls the alert down (or long-presses it) and taps **Join 25**. iOS launches or
   wakes Lockin in the background, without unlocking.
3. Lockin sends `POST /sessions/:id/join` with `{ "minutes": 25, "pushToStart": { token, env } }`.
4. The server joins B, sends the push-to-start to B's token, and answers `pushedToStart: true`.
5. iOS starts the Live Activity on B's Lock Screen with the alert "You're locked in with Ava", and
   wakes Lockin to hand over the activity's update token. The engine takes the activity up and
   uploads the token, so the room's pushes (A pausing, A finishing) reach B.
6. Lockin tells iOS it's done, and goes back to sleep.

## Before you start

- Two iPhones (A and B) with the same TestFlight build, both signed in to Lockin with different
  accounts, in the same squad. Notifications and Live Activities allowed for Lockin on both.
- The Worker deployed with its APNs secrets. Watch its log with `npx wrangler tail` in `server/`
  if you can: each alert and push-to-start logs a line (`alerts <sid>: …`,
  `push-to-start <sid>: production -> APNs 200`).
- On **B**: open Lockin once after installing and leave it open for a few seconds, so iOS issues the
  push-to-start token and the app saves and registers it. Then Settings › tap the version five
  times › **Developer** › switch on **Join without opening**. The **Copy push-to-start token**
  button appears once a token is saved.
- On **B**: Settings › **Notifications**: squad alerts **On**, and make sure the test isn't inside
  quiet hours (switch them off for the test if need be).
- The server limits alerts (docs/milestones/M4.md): one per squad per person every 30 minutes, six a
  day per person, and none when the opener opened another room in that squad in the last
  10 minutes. Space the runs at least 30 minutes apart, or use a second squad.

### Optional: the push-to-start half on its own

On B, tap **Copy push-to-start token**, send it to the PC, then:

```powershell
$adminToken = "…"   # the admin token
$body = '<paste the copied text>'
Invoke-RestMethod -Method Post -Uri https://lockin-api.yourname.workers.dev/admin/push-to-start-test `
  -Headers @{ Authorization = "Bearer $adminToken" } -ContentType "application/json" -Body $body
```

The demo "Spike Squad" should appear on B's Lock Screen with "You're locked in with Noor and 2
others". This shows the token, the environment and APNs are right, independent of the join. Lockin
leaves this activity alone (it isn't B's room); the next time Lockin launches, it ends it as an
orphan.

## Procedure

1. Lock **B** and put it down, screen off.
2. On **A**: open Lockin, pick the squad on Home, tap **Lock in** (25 minutes).
3. On **B**, still locked: the alert arrives. Pull it down (or long-press it) and tap **Join 25**.
   Start a stopwatch at the tap.
4. Watch B's Lock Screen. Stop the stopwatch when the Live Activity appears.
5. On **A**: B should appear in A's Live Activity within about 5 seconds of the join.
6. After a minute, on **A**, pause. B's Live Activity should show A paused within a few seconds:
   that proves B's update token reached the server.
7. Unlock **B** and open Lockin. The session screen shows B in the room. There must be exactly
   **one** Lockin activity, on the Lock Screen and in the Dynamic Island.
8. On **B**: Developer › **Last background join**: note the outcome and the seconds.
9. End the session on both phones.

Repeat across these conditions:

- B on Wi-Fi, and B on cellular (Wi-Fi off).
- Lockin on B suspended (used recently), and killed (swiped away in the app switcher) before the
  alert arrives.
- B restarted and unlocked once since.
- B with Low Power Mode on.

### The fallback

On a run where **Last background join** says **Not pushed**, or **Timed out**, or the Live
Activity never appears: unlock B and open Lockin. The session screen should show B in the room and
the Live Activity should start then. Note whether it did.

## What to record

One row per run:

| # | Date and time | Network | Lockin on B before | Tap to activity on B (s) | Last background join | B shown on A (s) | A's pause reached B | Lockin activities on B | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | |

Also note anything odd: the alert's buttons missing on the Lock Screen, Face ID asked for, the
"You're locked in" alert arriving without the activity, a second activity, the server log saying
something other than APNs 200.

## Ship or not

SPEC.md §4.5: ship only if it's reliable. Proposed rule, for the owner to confirm:

**Ship** (background buttons become the default, with the foreground path as the fallback) if, in
at least 10 runs across both phones, including at least 3 on cellular and at least 3 with Lockin
killed beforehand:

- at least 9 show B's Live Activity within 10 seconds of the tap, without unlocking;
- every one of those gets A's later pause (B's update token reached the server);
- none leaves two Lockin activities on B, and every failure recovers when B opens Lockin.

**Otherwise, don't ship**: Join 25 and Join 50 stay foreground buttons (v1), the switch stays in
the Developer menu, and this write-up says which step failed: the join timing out, the
push-to-start not arriving, or the activity arriving without its update token reaching the server.

Either way, record the result below and in docs/milestones/M4.md. Shipping means a decision record
in docs/decisions/, flipping the switch's default (or removing it), and SPEC.md §4.5 step 3 moving
into v1.

## Known limits

- **Time.** iOS gives a background button about 30 seconds. The app waits at most 20 for the join,
  so a slow network ends as **Timed out**; the join can still finish if iOS lets the app run on.
  The server sends the push-to-start before it answers, so the wait includes one APNs round trip.
- **Late pushes.** The push-to-start has no `apns-expiration`, so a phone that's offline may get it
  much later. The engine only takes up an activity for the room it's in; a late one for a room it
  has left stays until Lockin next launches and ends it as an orphan.
- **Lost answers.** If the server pushed but its answer never reached the phone, the activity
  appears, but the app doesn't know it joined: the activity gets no updates and ends at the next
  launch.
- **The token.** ActivityKit issues one push-to-start token per app, and can change it. The app
  saves each one, but a reinstall starts without one until Lockin is opened.
- **System budgets.** iOS limits how often an app may start activities by push. Many tests in a
  short time may start failing silently; record when, and try again later.
- **Live Activities off.** With Live Activities switched off for Lockin, no token is sent and the
  join reports **Not pushed**.

## Result

PENDING. Fill in the table above.

## Decision

PENDING.
