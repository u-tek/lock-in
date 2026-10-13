# 0001: Live Activity views live in the `LiveActivity` module

Status: **adopted**. Consistent with SPEC.md §5.2 and CLAUDE.md's layout; no spec change needed.

## Context

The Live Activity has to look right in every presentation: compact leading and trailing, minimal,
expanded, Lock Screen (also the banner on iPhones without the island), and StandBy (SPEC.md §1.3).
Two places need to draw those views:

- **The widget extension** (`Widgets/`), where the system shows them. Its `ActivityConfiguration`
  maps the views onto the Dynamic Island's regions and the Lock Screen.
- **The app's Live Activity Lab** (Developer menu, snapshot route `lab.liveactivity`), which
  renders every presentation and state with made-up squads so CI can export them as PNGs
  (SPEC.md §6 M1, CLAUDE.md "Definition of done"). CI can't show a real Live Activity: it can't
  receive pushes, and UI tests can't reliably capture the Dynamic Island or the Lock Screen. The
  owner has no Mac, so the Lab's snapshots are how a design change gets reviewed before it reaches
  a phone.

The app target can't import code from the widget extension, so views written in `Widgets/` would be
out of the Lab's reach.

## Decision

- The SwiftUI views for each presentation live in the `LiveActivity` package module
  (`Packages/LKKit/Sources/LiveActivity`). They're public and built from `LockinAttributes` and its
  `ContentState` (from `Model`).
- `Widgets/` keeps only the system wiring: the widget bundle and the `ActivityConfiguration` that
  places those views in the Dynamic Island's regions and on the Lock Screen, plus the system-only
  modifiers (`activityBackgroundTint`, `keylineTint`, links).
- The Lab renders the same views at each presentation's size, so what CI exports is what the
  extension draws.
- Anything a view needs from the system environment (whether it's the StandBy/fullscreen
  presentation, Always-On's reduced luminance, the activity family) reaches it as a plain parameter.
  `Widgets/` reads the real environment value and passes it in; the Lab passes each value in turn.
  The Lab can't always fake the system's own environment values, and a view that reads them directly
  could never be shown in every state.

In M0 the views are spike-grade (initials rather than creatures). `Creature` (M1) supplies the
drawings later without moving anything.

## Consequences

- `LiveActivity` must stay extension-safe: the widget extension is built with
  `APPLICATION_EXTENSION_API_ONLY`, so no UIKit-only APIs and no networking. That already applies to
  `Core`, `Model` and `DesignSystem`, which it depends on, and to `Creature` when it arrives.
- The Lab can't reproduce the system's chrome: the island's cut-out, the Lock Screen wallpaper and
  dimming, the system background behind `activityBackgroundTint`, or Always-On rendering. Those are
  checked on a real phone through TestFlight.
- M1's `LiveActivityIntent`s (Pause, End, Cheer, Start solo) belong in the same module (SPEC.md
  §5.2), so they're compiled into both the app and the widget extension. That's what lets the
  system run them in the app's process. Developers report that an intent compiled only into the
  extension runs there, where starting or updating activities fails
  ([Apple Developer Forums 735382](https://developer.apple.com/forums/thread/735382)).

## Alternatives considered

- **Views in `Widgets/`, also compiled into the app for the Lab.** The same files would be members
  of two targets. XcodeGen allows it, but it's easy to break, and the app would compile extension
  code.
- **Snapshotting a real Live Activity in the simulator.** It can't be pushed to from CI, and the
  Lock Screen and island aren't reliably capturable in UI tests.
- **A separate `LiveActivityUI` module.** It adds a module for no gain yet. It's worth splitting off
  only if the ActivityKit side of `LiveActivity` ever needs to stay out of somewhere the views must
  go.
