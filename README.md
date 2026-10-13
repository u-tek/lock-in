# Lockin

Lock in with your friends: their live focus timers sit in your Dynamic Island and on your Lock
Screen while you work, and your squad's shared pet only grows when everyone stays focused.

iPhone only, iOS 18+, Swift and SwiftUI, with a Cloudflare Worker backend. `SPEC.md` is the source
of truth for what we're building and why; `CLAUDE.md` is how to build it.

## Status

**M0: foundations and admin** (`docs/milestones/M0.md`). The project, the M0 modules, CI, the
TestFlight lane and the server skeleton are in place. Two things wait on the owner:

- the one-time Apple and Cloudflare setup in `docs/apple-setup.md`;
- the APNs spike, which decides whether pushes can go straight from the Worker:
  `docs/spikes/apns-worker.md`.

## Getting started (Windows, no Mac)

No Mac is needed. Every iOS build, test and snapshot runs on GitHub Actions macOS runners, and a
real iPhone gets builds through TestFlight.

| Where | What runs there |
|---|---|
| Your PC | The server: tests, type-check, bundle, local dev server, deploys (`wrangler`) |
| GitHub Actions | Every iOS build and test, design snapshots, TestFlight uploads, the push-test workflow |
| Your iPhone | TestFlight builds. The only place a Live Activity push can be seen |

The server needs Node 22.13 or later (`node --version`):

```powershell
cd server
npm ci
npm test            # vitest
npm run typecheck   # tsc
npm run build       # bundles the Worker without deploying it
```

`npm run dev` serves the Worker at `http://localhost:8787`, but it can't reach APNs: the local
runtime has no HTTP/2. Pushes only work from the deployed Worker. Deploying, secrets and the
admin route are in `server/README.md`.

Before the first TestFlight build, work through `docs/apple-setup.md`. Never put a key or token in
the repo, a commit message or a chat. Keys live in GitHub Actions secrets and Worker secrets only.

On a Mac (optional): `brew install xcodegen`, then `make project` generates `Lockin.xcodeproj` from
`project.yml` (the project file is generated, never committed). `make test` runs the module tests and
`make build` builds the app for the simulator.

## CI

`.github/workflows/ios.yml` runs on every push to any branch and on pull requests. Pushes that only
touch Markdown files or `design/` don't start it.

| Job | Runs on | When | What it does |
|---|---|---|---|
| API server | Linux | Every run | `npm ci`, type-check, tests and a dry-run bundle of `server/` |
| Build and test | macOS | Every run | `LKKit` module tests on a simulator, generates the project, builds the app and UI tests unsigned, uploads `Lockin-simulator` (not for pull requests) |
| Opt-ins | Linux | Manual runs, and pushes whose message mentions `[snapshots` or `[testflight]` | Reads the tags below |
| Design snapshots | macOS | `[snapshots]` | Renders screens on simulators and commits the PNGs to the branch |
| TestFlight | macOS | `[testflight]` | Archives a Release build, signs it and uploads it to App Store Connect |

`.github/workflows/push-test.yml` (**Push test**) is manual only. It sends one test Live Activity
update through the deployed Worker, for the APNs spike.

### Tags

Put the tag in the **first line** of the commit message. A tag in the commit body is ignored, so a
commit can mention one without starting it. Case doesn't matter.

| Tag | Does |
|---|---|
| `[snapshots]` | Every route, on iPhone 16 Pro and iPhone SE (3rd generation), dark mode |
| `[snapshots: home,spike]` | Only those routes, iPhone 16 Pro only: a quick check |
| `[light]` | Light mode as well as dark, together with one of the above |
| `[testflight]` | Archive, sign and upload to TestFlight |

A commit that changes only Markdown files doesn't run CI at all, so a tag in it does nothing. Use a
manual run instead: **Actions → iOS → Run workflow**. The GitHub app can do this too. Tick
*snapshots* or *testflight*, or type routes into *screens*; naming any route turns snapshots on.
Manual snapshot runs render dark mode only.

**Snapshots.** Routes are listed in `scripts/snapshot-routes.txt`: `home`, `developer`, `spike`,
`lab.tokens` and `lab.liveactivity`. `lab.*` routes render on the iPhone 16 Pro only. CI commits
the renders back to the branch as `github-actions[bot]` with `[skip ci]`, so pull before your next
push:

| Path | What's there |
|---|---|
| `design/screens/iphone-16-pro/<route>-<appearance>.png` | App screens on the iPhone 16 Pro |
| `design/screens/iphone-se-3rd-generation/<route>-<appearance>.png` | App screens on the iPhone SE |
| `design/lab/<name>-<appearance>.png` | Design lab pages: the design tokens and the Live Activity Lab |

The same files are also kept for 7 days as the run's `design-snapshots` artifact. CI creates both
simulators itself and caches a booted-once iPhone 16 Pro between runs, so a narrowed run is quicker.

**TestFlight.** The build number is the workflow's run number, or `<run>.<attempt>` when a run is
re-run. The build shows up in the TestFlight app once Apple has processed it, usually within 15
minutes of the upload. The job checks the secrets first and fails within seconds, naming any that
are missing. If signing or the upload fails, it prints a checklist and keeps the raw logs as the
`testflight-logs` artifact. A newer push to the same branch cancels a TestFlight job that's still
running, so wait for it to finish or push to another branch.

**Simulator build.** Every push (not pull requests) uploads the app as the `Lockin-simulator`
artifact, kept for 14 days: open the run in **Actions**, then go to **Artifacts**. It only runs in
the iOS Simulator on a Mac (unzip it, then `xcrun simctl install booted Lockin.app`). On Windows,
use TestFlight.

## Layout

| Path | What's there |
|---|---|
| `App/` | The app target: entry point, home, the Developer menu (APNs spike, Live Activity Lab), snapshot mode |
| `Widgets/` | The widget extension: the Live Activity's `ActivityConfiguration`. Later, Home and Lock Screen widgets and the Control Center control |
| `UITests/` | `SnapshotExportTests`, which exports screens as PNGs for design review |
| `Packages/LKKit/` | Every module, as one Swift package with a target per module |
| `server/` | The Cloudflare Worker: APNs sender, Live Activity wire format, D1 schema, `Room` Durable Object (`server/README.md`) |
| `fixtures/live-activity/` | Live Activity JSON shared by the Swift and server tests: the wire format's single source of truth |
| `Config/` | xcconfig files. `Local.xcconfig` is gitignored, and CI writes it from secrets |
| `scripts/` | Simulator, snapshot and TestFlight helpers |
| `.github/` | The CI workflows and the shared Xcode setup action |
| `docs/` | `milestones/`, `spikes/`, `decisions/` and `apple-setup.md` |
| `design/` | Exported screens and lab pages, written by CI (created by the first snapshot run) |

### Modules

| Module | Responsibility | Milestone | Now |
|---|---|---|---|
| `Core` | Config, ids, App Group paths, logging, analytics (event counts only) | M0 | Here |
| `Model` | Domain types and `LockinAttributes`, linked by the app and the widget extension | M0 | Here |
| `DesignSystem` | Tokens, typography, components | M0 | Here |
| `LiveActivity` | Start/update/end, push-token streams, the presentation views, `LiveActivityIntent`s | M1 | Started: what the spike needs, plus the views (`docs/decisions/0001`) |
| `Creature` | Avatar codes to SwiftUI-drawn creatures and pets, every state, sized per presentation | M1 | Not yet |
| `SessionEngine` | Local session state machine, timers, persistence, reconciliation | M1 | Not yet |
| `API` | REST client, Keychain token, WebSocket | M2 | Not yet |
| `Social` | Friends, squads, codes, QR, report/block | M2 | Not yet |
| `Notifications` | Categories/actions, local reminders | M4 | Not yet |
| `Progress` | Coins, XP, streak display, leaderboard | M5 | Not yet |
| `ShareCards` | `ImageRenderer` cards, 9:16 and 1:1 | M6 | Not yet |
| `Paywall` | RevenueCat, entitlements, Squad Boost | M7 | Not yet |
| `DeepFocus` | Family Controls picker, shields, slips | M8 | Not yet |

Dependencies run one way: `Core` ← `Model` ← feature modules ← the app and extension. The widget
extension links `Core`, `Model`, `DesignSystem` and `LiveActivity`, so those stay extension-safe:
no UIKit-only APIs and no networking.

## Rules the code relies on

- The Live Activity's wire format is SPEC.md §4.3, key for key, and is pinned by
  `fixtures/live-activity/`. Change `Model`, `server/src/liveActivity.ts` and the fixtures in the
  same commit.
- Attributes + content-state stay within 3,584 bytes of compact JSON. The server refuses anything
  bigger, which leaves headroom under the system's 4 KB limit.
- Times are `Double` Unix seconds, optional keys are left out (never `null`), and decoding uses
  Apple's default strategies.
- The Live Activity has no network, no location and no remote images. Everything is drawn from the
  payload.
- Analytics are integer event counts only.

## Docs

| Path | What's there |
|---|---|
| `SPEC.md` | Product and technical spec |
| `CLAUDE.md` | How to build: conventions, Live Activity rules, the owner's Apple admin by milestone |
| `docs/apple-setup.md` | The owner's Apple and Cloudflare checklist for M0, and the secrets |
| `docs/milestones/` | One plan per milestone, updated with what shipped |
| `docs/spikes/apns-worker.md` | The M0 spike: can a deployed Worker push a Live Activity update? |
| `docs/decisions/` | Where the spec turned out to be wrong or incomplete, and what we propose instead |
| `server/README.md` | Deploying the Worker, its secrets and the push-test endpoint |
