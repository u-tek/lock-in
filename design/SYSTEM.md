# Lockin design system: native Apple

Lockin should look like an app Apple could have shipped in iOS 26: system colours that follow
light and dark mode, SF Pro text styles, the standard containers and controls, Liquid Glass where
the system provides it. The brand lives in one tint colour, the creatures (M1) and the Live
Activity, not in custom chrome. When in doubt, do what Settings, Fitness, Clock and the Focus
screens do.

This replaces the first "desk lamp at midnight" palette (amber on deep indigo, dark-first, SF
Rounded everywhere).

## Colour

Only system colours. They adapt to light and dark mode, Increase Contrast and the Dynamic Island,
and people already know what they mean.

| Role | Colour | Notes |
|---|---|---|
| Tint | `.indigo` (`UIColor.systemIndigo`) | Set once at the root with `.tint(.indigo)`; `AccentColor` in the asset catalogue matches it. Indigo is the colour of Focus and Sleep in iOS: calm, and distinct from the default blue |
| Backgrounds | `systemGroupedBackground`, `secondarySystemGroupedBackground` | Lists and forms provide them; don't paint screen backgrounds by hand |
| Text | `.primary`, `.secondary`, `.tertiary` (hierarchical foreground styles) | Never hard-coded text colours: these keep vibrancy on materials and the Lock Screen |
| Separators, fills | `.separator`, `.quaternary` fills | |
| Destructive | `.red` via `role: .destructive` | |

Member states, one system colour each (the SF Symbol carries the meaning too, so colour is never
the only signal):

| State | Colour | Symbol |
|---|---|---|
| Focusing | `.indigo` | `lock.fill` |
| On a break | `.teal` | `cup.and.saucer.fill` |
| Paused | `.orange` | `pause.fill` |
| Done | `.green` | `checkmark` |
| Left | `.gray` | `hand.wave.fill` |
| Slipped (Deep Focus) | `.pink` | `drop.fill` |

Pet mood 0–3 (0 lowest): `.gray`, `.orange`, `.mint`, `.green`.

## Type

SF Pro (the system font, default design) through Dynamic Type text styles: `.largeTitle`,
`.title2`, `.headline`, `.body`, `.subheadline`, `.footnote`, `.caption`. Weights only from the
style or `.fontWeight(_:)`. Every number that counts down or changes uses `.monospacedDigit()`.
No SF Rounded: the Lockling carries the playfulness.

Live Activity countdowns: `.title2.weight(.semibold).monospacedDigit()` on the Lock Screen, a
large `.system(size:weight: .semibold)` hero in StandBy, `.body.weight(.semibold)` in the island.

## Layout and components

- `NavigationStack` with large titles on top-level screens and inline titles on pushed ones.
- `List` with `.insetGrouped` style, `Section` headers and footers, `LabeledContent` for
  key/value rows, `NavigationLink` rows with chevrons. Forms for anything with controls.
- Settings-style row icons: a white SF Symbol on a rounded square filled with a system colour
  (`LKIconTile`).
- Buttons: the system styles. Primary actions use `.glassProminent` on iOS 26 and
  `.borderedProminent` before; secondary actions `.glass` / `.bordered`. `controlSize(.large)` for
  a screen's main call to action. Destructive buttons use `role: .destructive`.
- Materials (`.regularMaterial`) for anything floating over content; Liquid Glass comes free with
  system bars, toolbars and the glass button styles. No custom shadows, no custom blurs.
- Corner radii: let containers choose; when drawing a card by hand, use a continuous 26 pt
  radius (Live Activity cards) or the list's own.
- Spacing on a 4 pt grid; standard margins come from the containers.

## Live Activity

- Follows the system appearance. The Lock Screen card uses the system's default background (no
  `activityBackgroundTint`), so it sits on the wallpaper like Apple's own activities; StandBy
  stays full-bleed black. The Dynamic Island is always dark, and system colours resolve to their
  dark variants there by themselves.
- Text uses hierarchical styles (`.primary`, `.secondary`) so it stays vibrant on the Lock Screen,
  at medium weight or heavier (the HIG's rule for Live Activities): the small styles add
  `.weight(.medium)`.
- Your own countdown takes your state colour only in the dark appearance (island, StandBy,
  Always-On, a dark Lock Screen). On a light Lock Screen it's `.primary`; the Lockling and the
  progress bar carry the colour, because tinted text on white is hard to read.
- Lock Screen side margins are 14 pt, Apple's value: the one exception to the 4 pt grid.
- Dynamic Type is capped per presentation so nothing passes 160 pt: up to xLarge on the Lock
  Screen, Large in the island, StandBy and the Smart Stack.
- Every member is their Lockling (the `Creature` module), in the pose for their state: reading
  while focusing, a mug on a break, asleep when paused, cheering when done, faded and waving when
  they've left, sweating when they slipped. Below 28 pt it drops props and thickens its lines;
  in Always-On it's an outline.
- A cheer for you shows while the room holds it (about 10 seconds): its SF Symbol in its own
  system colour (`LKColor.cheer(_:)`: orange applause, red fire, yellow star, pink heart, cyan
  lightning, indigo thumbs up, purple party, mint sparkles) in the compact island, and with "Noor
  cheered you on" in place of the squad name (expanded island) or the status line (Lock Screen,
  StandBy, the Watch). In Always-On the symbol is its outline in the secondary style.
- Keyline tint is the tint colour. No custom animation (the system ignores it); content
  transitions only.

## Checking it

Snapshots render every screen in light and dark (`design/screens/`, `design/lab/`). Both must
look like they belong on the same phone as Settings.
