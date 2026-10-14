# 0006: Sessions in a JSON file until history needs queries

Status: **proposed**, awaiting the owner.

Affects: M1 (shipped this way), M5 (when it should change).

## Context

SPEC.md §5.5: *"GRDB in the App Group container (as in Screenshot Brain) for sessions, history
and cached social data."*

## Finding

M1 needs to keep a handful of things on the phone: the session in progress, the last few hundred
sessions, coins, the avatar and a member id. Nothing queries them beyond "today's minutes" and
"the streak", which are a pass over a short array. A Codable JSON file in the App Group
(`SessionEngine/SessionStore.swift`, atomic writes, capped at 500 sessions) does that with no
dependency, no schema migrations, and nothing for CI to fetch.

## Proposal

Keep the JSON store through M4. Move to GRDB in M5, when the weekly leaderboard, full stats
history (a Plus feature) and cached squad data need real queries; the store is behind
`SessionStore`, so only that type changes. SPEC.md §5.5 would then read "GRDB from M5; a JSON
file before".

## Update (M5)

M5 put the weekly leaderboard and streaks on the server, so the phone still only keeps its own
recent sessions. The JSON store stays through M5; the move to GRDB waits for full stats history
(Plus, M7) or cached squad data that needs queries, whichever comes first.
