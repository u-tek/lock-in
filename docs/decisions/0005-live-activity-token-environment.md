# 0005: Store the APNs environment with each Live Activity token

Status: **implemented in M3** (migration `0003_squads.sql`, `POST /sessions/:id/la-token { token, env }`), awaiting the owner's sign-off.

Affects: M3 (squad sessions). Nothing in M0 uses `participants.la_token` yet.

## Context

- CLAUDE.md, "Live Activity rules": *"TestFlight/App Store builds use **production** APNs; debug
  builds use sandbox. Store the environment per token."*
- SPEC.md §4.6 stores the environment per **device** (`devices.apns_env`), but the Live Activity
  token lives on `participants.la_token` with no environment, and `POST /sessions/:id/la-token`
  (§4.7) sends only `{ token }`.

## Finding

A Live Activity token belongs to one APNs environment: sending it to the other host fails with
`400 BadDeviceToken` (research notes, `docs/spikes/apns-worker.md`). A user can have more than one
device, so the server can't reliably look the environment up from `devices` for a given
participant row. Without it, M3's fan-out has to guess the host.

## Proposal

1. `participants` gains `la_env TEXT CHECK (la_env IN ('sandbox', 'production'))` and
   `CHECK ((la_token IS NULL) = (la_env IS NULL))`.
2. `POST /sessions/:id/la-token` takes `{ token, env }`. The app already knows its environment
   (Core's `APNsEnvironment.current`, which the APNs spike screen shows).
3. SPEC.md §4.6 and §4.7 change to match.

Alternative: a `device_id` column on `participants` pointing at `devices` (ON DELETE SET NULL),
and the environment read from there. It's more normalised but adds a join to every fan-out and
breaks when a device row is replaced.

`wrangler.toml` still has a placeholder D1 id, so if the owner agrees before the first deploy,
the column can go straight into `0001_init.sql`; otherwise it ships as migration `0002` in M3.
