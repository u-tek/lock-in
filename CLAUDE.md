# CLAUDE.md — Lockin

Read `SPEC.md` first. It is the source of truth for what we're building and why. This file is how to build it.

## What this is
An iPhone app where friends' live focus timers appear in each other's Dynamic Island and Lock Screen, with a shared squad pet. Swift/SwiftUI app + widget extension, Cloudflare Workers backend.

## The owner's setup (important)
- The owner works on **Windows** and has no Mac. Every iOS build, test and snapshot runs on **GitHub Actions macOS runners**. Never assume local Xcode.
- Follow the conventions of the owner's `screenshot-brain` repo: XcodeGen `project.yml` (the `.xcodeproj` is generated, not committed), a `Makefile` (`make project`, `make build`, `make test`), one Swift package with a target per module, CI that commits screen snapshots on request.
- Real-device testing goes through **TestFlight** (paid Apple Developer account). Upload from CI with an App Store Connect API key stored as repo secrets.
- Pushes can't be tested in the simulator from CI. Use the `/admin/push-test` endpoint plus a TestFlight build on a real phone.

## How to work
- Build milestone by milestone, in the order in `SPEC.md` §6. Don't start a milestone until the previous one meets its "done when".
- At the start of each milestone, write a short plan in `docs/milestones/Mx.md` (scope, files, risks). Update it at the end with what shipped and what didn't.
- Keep CI green on every push. Every module gets unit tests; the server gets tests too (vitest).
- Spikes (M0 APNs-from-Worker, M4 push-to-start) get a write-up in `docs/spikes/` with the result and the decision.
- When something in `SPEC.md` turns out to be wrong or impossible, stop, write down what you found in `docs/decisions/`, propose the change, and update the spec once the owner agrees.
- Prefer small commits with clear messages.

## Layout
```
App/                 app target: entry point, screens, app model
Widgets/             Live Activity, Home/Lock Screen widgets, Control Center control
Packages/LKKit/      Core, Model, DesignSystem, Creature, SessionEngine, LiveActivity,
                     API, Social, Progress, ShareCards, Paywall, DeepFocus, Notifications
server/              Cloudflare Worker (TypeScript): API, Durable Object rooms, D1, APNs sender
Config/              xcconfig files; Local.xcconfig is gitignored
design/              references, exported screens, App Store screenshots
docs/                milestones/, spikes/, decisions/, app-review-notes.md
scripts/             build and snapshot helpers
```
Dependencies run one way: `Core` ← `Model` ← feature modules ← app/extension. `Model` and `Creature` must compile for the widget extension (no UIKit-only or network code in them).

## Live Activity rules (these are where bugs come from)
- **4 KB max** for attributes + content-state combined. Keep the short keys in `SPEC.md` §4.3. The server rejects payloads over 3.5 KB and unit-tests the largest possible squad.
- **Times are `Double` Unix seconds.** Content-state is decoded with Apple's default JSON strategies; `Date` fields or custom encoders will silently break push updates. Server and Swift key names must match exactly — share a fixture JSON file tested on both sides.
- **No network, no location, no remote images** inside the Live Activity. Creatures are SwiftUI shapes in `Creature`.
- **Animation modifiers are ignored.** Use content transitions only. Countdowns use `Text(timerInterval:countsDown:)` so they tick without pushes. Nothing animates in Always-On; check `isLuminanceReduced`.
- **Support every presentation:** compact leading/trailing, minimal, expanded, Lock Screen (also the banner on iPhones without the island), StandBy (`isActivityFullscreen`). Keep the Lock Screen view under 160 pt tall.
- **8-hour cap.** Sessions max 4 h. End activities explicitly with a final state. On launch, find and end orphaned activities.
- **Push tokens arrive asynchronously** via `pushTokenUpdates` and can change; upload every new one. Push-to-start tokens come from `pushToStartTokenUpdates`.
- **Push priority 5 by default;** 10 only for joins, finishes, early leaves, slips and `end`. Never push timer ticks. Coalesce per room.
- APNs headers: `apns-push-type: liveactivity`, `apns-topic: <bundle id>.push-type.liveactivity`. TestFlight/App Store builds use **production** APNs; debug builds use sandbox. Store the environment per token.
- Push-to-start payloads must include `alert`, `attributes-type` and `attributes` (and `input-push-token: 1` on iOS 18+).
- Starting an activity needs the app in the foreground, except from a `LiveActivityIntent` or push-to-start.
- Handle Live Activities being disabled in Settings (`areActivitiesEnabled`, `activityEnablementUpdates`) with a clear in-app prompt.

## Product rules
- Original creatures, name and art. Do not imitate Focus Friend's bean, Pixel Pals or Widgetable.
- Solo mode must be good on its own; most new users have no friends on the app yet.
- Everything that spreads the app (squads, Live Activity with friends, invites, share cards) stays free.
- No free-text chat, no public rooms, no contact upload, no location in v1.
- Analytics are integer event counts only; no content, names or ids of friends.
- Notifications: per-squad mute, quiet hours, at most ~2 non-session notifications a day.

## Apple admin the owner must do (remind them at the right milestone)
- M0: paid Developer Program; App ID + Push; App Group; APNs `.p8` key; App Store Connect API key for CI uploads; **submit the Family Controls distribution request** for the app and each planned extension.
- M3: enable push on the production App ID config; TestFlight group of real friends.
- M7: RevenueCat project, App Store subscription products, tax/banking set up in App Store Connect.
- M9: privacy policy and support URLs, age rating questionnaire, review notes with demo accounts.

## Secrets
Never commit keys. `.p8`, Team ID, Key ID, App Store Connect API key and RevenueCat keys live in GitHub Actions secrets and Cloudflare Worker secrets. `Config/Local.xcconfig` is gitignored; ship `Local.xcconfig.example`.

## Definition of done for any change
- Builds and tests pass in CI.
- New screens have snapshot routes and render on iPhone 16 Pro and iPhone SE.
- Live Activity changes are visible in the Live Activity Lab screen across every presentation and state.
- `SPEC.md` still matches reality.
