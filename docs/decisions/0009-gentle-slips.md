# 0009: A slip shows for 5 minutes; it doesn't end your timer

Status: **proposed**, awaiting the owner.

Affects: M3 (the room's slip, as first built), M8 (Deep Focus).

## Context

SPEC.md §1.4: *"Ending early or pausing too long counts as breaking focus: your creature shows it
to the squad, and the pet's mood dips slightly. Never punishing — gently social."* §5.8: *"Choosing
'open anyway' on a shield records a slip: the creature shows it to the squad and the pet's mood
dips."*

M3 built `POST /sessions/:id/slip` like leaving early: state 5, timer stopped. With Deep Focus,
"Open anyway" lifts the shield for that app for 5 minutes and the session carries on (decision
0008), so stopping the timer on the server made the app and the room disagree, and it turned a
glance at a message into losing the session.

## Decision (as built)

- A slip shows you as slipped (state 5, the sheepish Lockling with a sweat drop) for 5 minutes
  while your timer keeps running, then you're back to focusing. Another slip in those 5 minutes
  starts the 5 minutes again.
- The squad sees it (a priority-10 push) and the pet has a short sad spell, as before.
- Coins and XP are credited when the timer really stops, as for anyone else.
- In the Live Activity a slipped member keeps their countdown, in the slipped colour.

No SPEC.md change is needed: it never said a slip ends the timer. M3.md's "As built" changes.
