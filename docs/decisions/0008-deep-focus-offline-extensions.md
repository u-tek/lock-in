# 0008: Deep Focus extensions work offline; slips sync from the app

Status: **proposed**, awaiting the owner. Answers SPEC.md §9 question 3 as far as the docs go.

Affects: M8.

## Finding

- Apple's `ShieldConfigurationDataSource` documentation says its sandbox "prevents your extension
  from making network requests or moving sensitive content outside the extension's address
  space". Nothing is documented either way for the shield action and activity monitor
  extensions.
- DeviceActivity intervals must be at least 15 minutes long. A session resumed late, or a short
  one, has less than that left.
- `intervalDidEnd` arrives only once the phone is in use, and also when monitoring stops mid
  interval, so callbacks can be late or come from our own reschedules.

## Decision (as built)

- **No network in any of the three extensions.** "Open anyway" writes a slip line to a file in
  the App Group; the app sends it (`POST /sessions/:id/slip`) the next time it runs. The squad
  sees the slip when the app next opens rather than at once. Because the configuration extension
  can't move app names out either, a slip never says which app it was.
- **Short sessions get a backdated interval**: 16 minutes long, ending exactly when the session
  does. If iOS refuses even that, the shields stay up and the app lifts them itself when the
  session ends or on the next launch.
- **"Open anyway" lifts the shield for that app for 5 minutes.** An app shielded through its
  category gets the category's token, so the whole category opens for those 5 minutes.
- **Callbacks don't act blindly.** Every extension callback re-reads the session state in the App
  Group and does what it says, so a late or self-caused `intervalDidEnd` is harmless.

## To check on a phone (needs Apple's approval first)

1. Does iOS act on the backdated interval?
2. Can the shield action extension reach the network after all? If it can, slips can go
   straight to the server and SPEC.md §5.8 can drop "sync on next launch".
3. Does the activity monitor stay under its memory limit (about 6 MB reported) with the
   `DeepFocus` module linked? If not, split out a smaller module for it.

## Proposed SPEC change

§9 question 3 gets the answer above; §5.8 keeps "if not, sync on next launch" as the design.
