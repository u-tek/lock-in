# Lockin API

The Cloudflare Worker behind Lockin (SPEC.md §4). M0 gave it the **APNs spike**, proving that a
deployed Worker can push a Live Activity update to a TestFlight build on a real iPhone (SPEC.md
§4.2, `docs/spikes/apns-worker.md`). M2 adds **accounts and friends** on D1: Sign in with Apple,
handles and names, friend codes and invite links, blocks, reports and account deletion. M3 adds
**squads and sessions**: each session is a `Room` Durable Object that runs everyone's timers,
pushes the squad's Live Activity to every member and serves a WebSocket live view, with one APNs
provider token for all of them from the `ApnsAuth` Durable Object. The contracts the app is written
against are `docs/milestones/M2.md` and `docs/milestones/M3.md`.

| Route | Auth | What it does |
|---|---|---|
| `GET /health` | | `{"ok": true, "environment": "development"}` |
| `POST /admin/push-test` | admin | Sends a made-up squad to one Live Activity. Development only, behind `ADMIN_TOKEN` |
| `POST /auth/apple` | | `{ identityToken, authorizationCode?, displayName? }` → `{ token, user, isNew }`. Verifies the identity token against Apple's keys, creates the account on first sign-in |
| `GET /me` | bearer | `{ user }` |
| `PATCH /me` | bearer | `{ handle?, displayName?, avatarCode? }` → `{ user }` |
| `DELETE /me` | bearer | Deletes the account and everything that's only theirs, revokes Apple's token → 204 |
| `GET /handles/:handle` | bearer | `{ available, reason? }` for the handle picker |
| `POST /devices` | bearer | `{ apnsToken, env, pushToStartToken?, laEnabled, frequentPushes, tz }` → 204 |
| `GET /friends` | bearer | `{ friends: [Friend] }`, newest first |
| `POST /friends/code` | bearer | Your friend code: the current one, or a new one once it expires (7 days) |
| `POST /friends/redeem/:code` | bearer | Befriends the code's owner (both ways) → `{ friend }` |
| `DELETE /friends/:id` | bearer | Ends a friendship (both ways) → 204 |
| `GET /blocks`, `POST /blocks`, `DELETE /blocks/:userId` | bearer | Who you've blocked; blocking also ends the friendship |
| `POST /reports` | bearer | `{ userId, reason, note? }` → 204, for moderation |
| `GET /j/:code` | | The invite landing page (HTML) for a friend or squad code: open in Lockin, or get it and type the code |
| `GET /.well-known/apple-app-site-association` | | Universal links for `/j/*` (used once the invite domain exists, M9) |
| `DELETE /auth/session` | bearer | Signs this token out (other devices stay signed in) → 204 |
| `GET /squads` | bearer | `{ squads: [Squad] }`, the one you joined first first |
| `POST /squads` | bearer | `{ name }` → `{ squad }`. Free: 1 squad; Plus: 3 |
| `PATCH /squads/:id` | bearer | `{ name }` → `{ squad }`, the owner only |
| `POST /squads/:id/invite` | bearer | Your code for the squad (`{ code, url, expiresAt }`), like a friend code |
| `POST /squads/join/:code` | bearer | → `{ squad }`. Free squads hold 4, a Plus owner's (or Plus joiner's) 6 |
| `PATCH /squads/:id/members/me` | bearer | `{ muted }` → `{ squad }` |
| `DELETE /squads/:id/members/me` | bearer | Leaves → 204. An owner hands the squad to the longest-standing member; the last one out deletes it |
| `POST /sessions` | bearer | `{ squadId?, minutes }` → `Joined`: solo, or the squad's room (joined, or opened) |
| `POST /sessions/:id/join` | bearer | `{ minutes }` → `Joined` |
| `POST /sessions/:id/la-token` | bearer | `{ token, env }` → 204: the Live Activity's push token and its APNs environment |
| `POST /sessions/:id/pause`, `resume`, `end`, `slip` | bearer | → `{ contentState }` |
| `POST /sessions/:id/cheer` | bearer | `{ to, kind }` (0–7) → 204, one per 10 s |
| `GET /sessions/:id` | bearer | `{ session, contentState }`, for reconciling on foreground |
| `GET /sessions/:id/live` | bearer | WebSocket: `{"type": "state", "status", "contentState"}` on connect and after every change |

Everything else answers `404`. Errors are `{"error": "<a sentence>", "code": "<machine code>"}`;
the app switches on `code`. A few carry one more field: `limit` on 402 `plus_required`, `sessionId`
on 409 `already_in_session`, `retryAfter` (seconds) on 429 `cheer_too_soon`. The codes per route are
in `docs/milestones/M2.md` and `docs/milestones/M3.md`; on top of those, any route can answer
`400 bad_request` (a body that isn't a JSON object), `413 too_large` (a body over 16 KB) and
`500 internal`, and `POST /auth/apple` answers `502 apple_unavailable` when Apple's keys can't be
fetched.

| Path | What's there |
|---|---|
| `src/index.ts` | The Worker's entry point and router (`handle`, which the tests call with a fake `fetch`, clock and random source) |
| `src/accounts.ts` | `/auth/apple`, `/me`, `/handles/:handle`, `/devices` |
| `src/friends.ts` | `/friends…`, `/blocks…`, `/reports` |
| `src/invite.ts` | `/j/:code` and the apple-app-site-association file |
| `src/squads.ts` | `/squads…`: limits, codes, joining, leaving and handing on |
| `src/sessions.ts` | `/sessions…`: checks what only D1 knows (squad membership, your other session), then forwards to the room |
| `src/room.ts` | The `Room` Durable Object: one per session ("The rooms" below) |
| `src/apnsAuth.ts` | The `ApnsAuth` Durable Object: the one APNs provider token every room presents, and the rooms' client for it |
| `src/appleAuth.ts` | Sign in with Apple: identity-token verification (RS256 against Apple's cached keys), the code-for-refresh-token exchange and revocation (ES256 client secret) |
| `src/auth.ts` | Session tokens (32 random bytes; only the SHA-256 is stored) and the bearer check |
| `src/moderation.ts` | The handle and name check in `fixtures/moderation/README.md`, with the shared word list |
| `src/db.ts` | Every D1 query, typed |
| `src/admin.ts` | `POST /admin/push-test` |
| `src/liveActivity.ts` | The Live Activity wire format (SPEC.md §4.3): strict parsing, canonical encoding, the 3.5 KB budget, `stale-date`, APNs payloads for `update`, `end` and push-to-start, within APNs' 4 KB body limit |
| `src/apns.ts` | The APNs sender: token auth with an ES256 JWT (signed itself, or from `ApnsAuth`), one retry on `ExpiredProviderToken` (never on a 429), bodies over 4 KB refused before sending |
| `src/jwt.ts` | ES256 signing with Web Crypto, from a `.p8` file |
| `src/demo.ts` | The spike's scenarios: `squad`, `join`, `cheer`, `end` |
| `migrations/` | The D1 schema (SPEC.md §4.6); `0002_accounts.sql` adds sessions, Apple's refresh token and report notes; `0003_squads.sql` adds `participants.la_env` and the indexes that keep one running timer per user and one open room per squad |
| `test/` | vitest. Route tests run real SQL on an in-memory SQLite behind a D1 stand-in (`test/d1.ts`), against a fake Apple with generated keys (`test/app.ts`). Rooms run on a fake Durable Objects runtime (`test/rooms.ts`: storage, alarms the test fires as its clock moves, WebSockets, eviction) and push to a fake APNs. The shared fixtures in `fixtures/live-activity/` and `fixtures/moderation/` are tested here and by the Swift tests |

The moderation word list is imported straight from `fixtures/moderation/words.json`: wrangler
bundles it into the Worker like any other import, so there is one copy, and a word added there
reaches the server and the app's tests together. Deploy from a full checkout of the repository
(it is outside `server/`).

Logs say what happened, never who: no tokens, ids, handles or names, only counts and outcomes. The
one id that appears is a room's (a session id), so a room's lines can be followed.

## Test

Node 22.13 or later, on any OS:

```sh
cd server
npm ci
npm test            # vitest
npm run typecheck   # tsc
npm run build       # bundles the Worker without deploying it (wrangler deploy --dry-run)
```

CI runs the same on Linux (`.github/workflows/ios.yml`).

## Deploy (Windows, PowerShell)

You need a Cloudflare account (the free plan is enough: it includes D1 and SQLite-backed Durable
Objects) and, from the Apple developer portal:

- an **APNs key**: Certificates, Identifiers & Profiles → Keys → **+** → Apple Push Notifications
  service (APNs). Download `AuthKey_XXXXXXXXXX.p8` once (Apple won't let you download it again)
  and note the Key ID;
- your **Team ID** (Membership details);
- the app's **bundle ID**, the same value as the `LK_BUNDLE_ID` repository secret
  (docs/apple-setup.md).

1. Install and sign in:

   ```powershell
   cd server
   npm ci
   npx wrangler login
   ```

2. Create the database, then paste the `database_id` it prints into `wrangler.toml` (it isn't a
   secret; commit it) and create the tables:

   ```powershell
   npx wrangler d1 create lockin
   npx wrangler d1 migrations apply lockin --remote
   ```

   `migrations apply` runs every migration the database hasn't had yet, so the same command later
   applies only the new ones (see "Upgrading to M2" below).

3. Set `APNS_BUNDLE_ID` under `[vars]` in `wrangler.toml` to the app's bundle ID (not the widget
   extension's), then deploy:

   ```powershell
   npx wrangler deploy
   ```

   It prints the Worker's address, e.g. `https://lockin-api.yourname.workers.dev`.

4. Add the secrets. Each command updates the deployed Worker straight away. (Or leave out the pipe
   and paste the value when asked; the `.p8` file is easiest piped, as below.)

   ```powershell
   "ABCDE12345" | npx wrangler secret put APNS_TEAM_ID      # your Team ID
   "XYZ9876543" | npx wrangler secret put APNS_KEY_ID       # the key's ID
   Get-Content AuthKey_XYZ9876543.p8 -Raw | npx wrangler secret put APNS_PRIVATE_KEY
   ```

   Then the admin token, 64 random hex characters (anything under 32 characters counts as unset):

   ```powershell
   $adminToken = node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   $adminToken | npx wrangler secret put ADMIN_TOKEN
   $adminToken    # keep it: it's also the LOCKIN_ADMIN_TOKEN repository secret below
   ```

5. Check it's up:

   ```powershell
   Invoke-RestMethod https://lockin-api.yourname.workers.dev/health
   ```

6. For accounts (M2), add the Sign in with Apple key ("Sign in with Apple" below).

7. Wire up the rest:
   - GitHub → Settings → Secrets and variables → Actions: `LOCKIN_API_URL` =
     `https://lockin-api.yourname.workers.dev` and `LOCKIN_ADMIN_TOKEN` = the admin token, for the
     push-test workflow; `LK_API_HOST` = `lockin-api.yourname.workers.dev` (host only, no
     `https://`), for TestFlight builds. CI writes it into `Config/Local.xcconfig`, so there's
     nothing to edit locally.

To watch requests as they happen: `npx wrangler tail`. The Worker logs the APNs status and the
payload size, never a token or the key.

## Sign in with Apple (M2)

Sign-in works with just `APNS_BUNDLE_ID` set: the Worker checks each identity token against Apple's
published keys (issuer `https://appleid.apple.com`, audience = the bundle ID, unexpired) and keys
accounts by Apple's `sub`. Apple also requires that deleting an account revokes the app's Sign in
with Apple token, which needs a **Sign in with Apple key**:

1. developer.apple.com → Certificates, Identifiers & Profiles → Keys → **+**. Tick **Sign in with
   Apple**, Configure, pick the app's App ID as the primary App ID, Save, Continue, Register.
   (One key can have both APNs and Sign in with Apple ticked; then it's the same `.p8` file and Key
   ID as the APNs secrets.) Download `AuthKey_XXXXXXXXXX.p8` and note the Key ID.
2. Add both as secrets (`APNS_TEAM_ID`, from step 4 above, is the team for this key too):

   ```powershell
   "KEY1234567" | npx wrangler secret put SIWA_KEY_ID
   Get-Content AuthKey_KEY1234567.p8 -Raw | npx wrangler secret put SIWA_PRIVATE_KEY
   ```

With them, each sign-in swaps the app's one-time authorisation code for a refresh token, stored
with the account; `DELETE /me` revokes it, then the account is gone either way. Without them,
sign-in still works, nothing is revoked, and the Worker logs once that `SIWA_KEY_ID,
SIWA_PRIVATE_KEY not set`. Accounts created before the key was set have no token to revoke until
they sign in again.

Apple's keys are cached for a day per isolate and fetched again early when a token names a key
that isn't cached (at most once a minute).

## Invite links

`POST /friends/code` returns `https://<INVITE_HOST>/j/<code>`. Until the invite domain exists (M9),
leave `INVITE_HOST` unset: links use the Worker's own host, which serves the landing page. Once the
domain points at the Worker, set it under `[vars]` in `wrangler.toml` (host only, no `https://`)
and deploy:

```toml
INVITE_HOST = "lockin.app"
```

The same host serves `/.well-known/apple-app-site-association` (`applinks` for
`<APNS_TEAM_ID>.<APNS_BUNDLE_ID>`, paths `/j/*`), so with the Associated Domains entitlement
`applinks:<INVITE_HOST>` in the app, links open Lockin directly. The landing page's App Store link
is a placeholder (`APP_STORE_URL` in `src/invite.ts`) until the app has its App Store page.

## The rooms (M3)

Every session, solo or squad, is a `Room` Durable Object named by its session id. The Worker
authenticates the caller, checks what only D1 knows (squad membership, the caller's other
session), and forwards to the room with the user's id in the `x-lockin-user` header. Only the
Worker's own code can reach a Durable Object, and it never forwards a client's request as it came,
so the room trusts that header.

The room holds each member's timer (`b`, `e`, `q`) and state (0 focusing, 2 paused, 3 done, 4 left,
5 slipped; 1, a break, isn't used yet) and builds the one content-state every member's Live
Activity shows: host first, then in the order people joined, at most 6, the squad pet and the
latest cheer, `v` one higher on every change. Then:

- **Pushes, coalesced.** The first change opens a 2-second window; when it closes, the latest
  state goes to every member's Live Activity token, at priority 10 if anything in the window was a
  join, finish, early leave or slip, and 5 if it was only pauses, resumes and cheers (SPEC.md §4.4).
  `stale-date` is five minutes after the last running timer should end. Each token goes to its own
  APNs host (`la_env`). APNs saying 410 or `BadDeviceToken` drops that token; the app's next
  upload brings it back. Timers never cause pushes: they tick on the phone.
- **Timers finish themselves.** An alarm at the next `e` marks that member done. A member still
  running 8 hours after joining (an abandoned pause, say) counts as having left: their activity
  has left the island by then anyway.
- **Cheers** show for 10 seconds, then a priority-5 push clears them. One per sender per 10 s.
- **The end.** When nobody's timer is running, the room ends: an `end` push with the final state
  and `dismissal-date` 30 minutes on, the session marked ended in D1, every member's focused time
  written, the tokens cleared, and one log line with the room's push counts:

  ```
  room r7Kq2xP9aL: ended after 51 min with 2 members; 6 pushes accepted (6 at priority 10, 0 at 5) in 3 batches, 0 refused, 0 failed, 0 tokens cleared
  ```

  The same counts go into `events` (`type = 'room_end'`). The final state is kept for a day for
  `GET /sessions/:id`, then the room deletes itself.
- **The live view.** `GET /sessions/:id/live` is a WebSocket (the hibernation API, so an idle room
  costs nothing). It gets `{"type": "state", "status": "open", "contentState": …}` on connect and
  after every change, straight away rather than after the push window, and a last one with
  `"status": "ended"` before the room closes it. Send `{"type": "ping"}` and it answers
  `{"type": "pong"}`. The app connects with the same `Authorization: Bearer` header as any route.

Everything the room knows is in its storage, so the runtime can evict it at any time. D1 is written
as things happen (participants, the session, `events` rows for stats); a write that fails is tried
again 30 seconds later, and the room carries on meanwhile. Two limits live in D1 indexes rather
than in code, so racing requests can't get past them: one running timer per user (409
`already_in_session`, naming the session so the app can end it) and one open room per squad (two
members locking in together end up in the same room).

Placeholders until M5: the pet is left out of the content-state until its egg hatches
(`squads.pet_species` set); its mood is 3 if at least half the squad has a running or finished
session in the last 24 hours, otherwise 1; its progress `x` is XP within a 600-XP stage.

## The APNs provider token (M3)

APNs refuses a *new* provider token more than once every 20 minutes on one connection (429
`TooManyProviderTokenUpdates`), and Cloudflare, not our code, owns the connections, which several
rooms may share (`docs/decisions/0004-shared-apns-provider-token.md`). So nobody signs for
themselves: the `ApnsAuth` Durable Object (one, named `global`) signs the token, keeps it in its
storage, and hands the same one to every room for 40 minutes. Each room keeps its copy until
5 minutes before that, then asks again. A token is signed again only when it's 40 minutes old, or
when APNs answers 403 `ExpiredProviderToken` to the current one, never because of a 429. Deployed,
`/admin/push-test` presents the same token.

`ApnsAuth` uses the same `APNS_TEAM_ID`, `APNS_KEY_ID` and `APNS_PRIVATE_KEY` secrets as before;
there's nothing new to set. If they're missing, rooms still work and log `push failed
(ApnsConfigError)` instead of pushing.

## Upgrading to M3

A Worker deployed for M2 needs the new migration and a deploy, which also creates the `ApnsAuth`
class (`[[migrations]]` tag `v2` in `wrangler.toml`). No new secrets.

```powershell
cd server
npx wrangler d1 migrations apply lockin --remote   # applies migrations/0003_squads.sql only
npx wrangler deploy
```

`0003_squads.sql` adds a unique index on running participations; it would fail if two were already
open for one user, which can't be the case before M3 (nothing wrote to `participants`).

To see rooms working, `npx wrangler tail` shows `room <id>: opened`, refusals from APNs, and the
push counts when each room ends. Or ask D1 for the latest rooms' counts:

```powershell
npx wrangler d1 execute lockin --remote --command "SELECT session_id, meta_json FROM events WHERE type = 'room_end' ORDER BY at DESC LIMIT 20"
```

## Upgrading to M2

A Worker deployed for M0 needs the new tables and, for revocation, the Sign in with Apple key:

```powershell
cd server
npx wrangler d1 migrations apply lockin --remote   # applies migrations/0002_accounts.sql only
"KEY1234567" | npx wrangler secret put SIWA_KEY_ID
Get-Content AuthKey_KEY1234567.p8 -Raw | npx wrangler secret put SIWA_PRIVATE_KEY
npx wrangler deploy
```

`npx wrangler d1 migrations list lockin --remote` shows what's applied. For `npm run dev`, the
same with `--local` instead of `--remote`.

## The APNs spike

1. Install the TestFlight build, open the APNs spike screen in the Developer menu, start the test
   Live Activity and copy its details: `{"token": "…", "env": "production", "me": "…", "sid": "…"}`.
   That's a complete request body.
2. Lock the phone and send it:

   ```powershell
   $adminToken = "…"   # the admin token from step 4, if this is a new PowerShell window
   $body = '{"token":"…","env":"production","me":"…","sid":"…"}'   # paste what the app copied
   Invoke-RestMethod -Method Post -Uri https://lockin-api.yourname.workers.dev/admin/push-test `
     -Headers @{ Authorization = "Bearer $adminToken" } -ContentType "application/json" -Body $body
   ```

   For another scenario, add it to the body: `"scenario":"cheer"`. In bash (or GitHub Actions):

   ```sh
   curl --fail-with-body -sS https://lockin-api.yourname.workers.dev/admin/push-test \
     -H "Authorization: Bearer $LOCKIN_ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d '{"token":"…","env":"production","me":"…","sid":"…","scenario":"squad"}'
   ```

   The push-test workflow (`.github/workflows/push-test.yml`) does the same from the GitHub app, so
   the whole spike can run from the phone.

### Request

| Key | Required | Meaning |
|---|---|---|
| `token` | yes | The Live Activity's push token, hex |
| `env` | yes | `sandbox` for Xcode builds, `production` for TestFlight and App Store builds |
| `me`, `sid` | no | The activity's member and session ids (10 base62 characters); `me` becomes the first member so the phone shows itself first |
| `scenario` | no | `squad` (default): you and three friends focusing, with a pet. `join`: a friend who just started. `cheer`: Noor cheers you. `end`: everyone done, sent as an `end` event that dismisses after 30 minutes |
| `priority` | no | `5` or `10`. Defaults follow SPEC.md §4.4: 10, except 5 for `cheer` |
| `contentState` | no | Your own content-state (SPEC.md §4.3), validated strictly. Replaces the scenario's state; the scenario still decides the event and the default priority |

Unknown keys are refused, so a typo can't be silently ignored. Times in the scenarios are relative to
now, so the countdowns on the phone are live.

### Response

`{ status, apnsId, reason?, environment, bytes, event, contentState }`: APNs' status and id, its
reason when it refused, the environment used, the size of attributes + content-state, and exactly
what was sent. The HTTP status is `200` when APNs accepted the push and `502` when it refused (same
body) or couldn't be reached (`{"error": "Couldn't reach APNs: …"}`), so `curl --fail` notices.
`Invoke-RestMethod` throws on a 502; on PowerShell 7, add `-SkipHttpErrorCheck` to see the body.

### When it doesn't work

| Answer | Likely cause |
|---|---|
| `404` | `ENVIRONMENT` is `production`, `ADMIN_TOKEN` isn't set (or is under 32 characters), or the bearer token doesn't match. All look the same on purpose |
| `400` | The message says which field is wrong |
| `500` naming `APNS_…` | A secret is missing, or `APNS_PRIVATE_KEY` isn't the `.p8` file's contents |
| `BadDeviceToken` | `env` doesn't match the build: TestFlight is `production` |
| `DeviceTokenNotForTopic`, `TopicDisallowed` | `APNS_BUNDLE_ID` isn't the app's bundle ID |
| `InvalidProviderToken` | `APNS_TEAM_ID` or `APNS_KEY_ID` doesn't belong to the `.p8` key |
| `ExpiredToken`, `Unregistered` (410) | The activity has ended: start a new one and copy again |
| `TooManyRequests` (429) | Too many pushes to this token in a row: wait a minute |
| `BadEnvironmentKeyIdInToken` (403) | The APNs key only works in Sandbox, and TestFlight builds are production: make a Team Scoped key for Production (docs/decisions/0002-apns-key-environment.md) |
| `TooManyProviderTokenUpdates` (429) | Transport works: the Worker reached APNs. Two isolates sent different provider tokens on one connection; record it (docs/decisions/0004-shared-apns-provider-token.md) |
| `Couldn't reach APNs` | From `npm run dev`: expected, the local runtime has no HTTP/2 (see Local development). From the deployed Worker: it couldn't talk HTTP/2 to APNs. Try a few times over an hour; if it keeps failing, that's the spike's failure case: write it up in docs/spikes/apns-worker.md. The fallback is a small Node relay using `node:http2` behind the same `sendLiveActivity` interface (SPEC.md §4.2) |
| `200` but nothing changes on the phone | Live Activities are off in Settings; iOS is throttling priority-10 pushes for this activity (its hourly budget, SPEC.md §3), so try `"priority": 5`; or the phone couldn't decode the content-state, which it drops silently: check the Swift `LockinAttributes` against `fixtures/live-activity/` |

## Local development

`npm run dev` serves the Worker on `http://localhost:8787` with a local D1
(`npx wrangler d1 migrations apply lockin --local` creates its tables). Secrets come from
`server/.dev.vars`, which is gitignored:

```
ADMIN_TOKEN=at-least-32-characters-of-anything-random
APNS_TEAM_ID=ABCDE12345
APNS_KEY_ID=XYZ9876543
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----"
SIWA_KEY_ID=KEY1234567
SIWA_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----"
```

`npm run dev` can't reach APNs: its local runtime (`workerd`) has no HTTP/2
([cloudflare/workerd#4841](https://github.com/cloudflare/workerd/issues/4841)), so
`/admin/push-test` only works against the deployed Worker. Rooms run locally too (squads, sessions
and the WebSocket all work), but their pushes fail and are logged as such.

## Turning the admin route off

Set `ENVIRONMENT = "production"` in `wrangler.toml` and deploy, or
`npx wrangler secret delete ADMIN_TOKEN`. Either way `/admin/push-test` answers `404`.
