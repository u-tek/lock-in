# Lockin API

The Cloudflare Worker behind Lockin (SPEC.md §4). M0 gave it the **APNs spike**, proving that a
deployed Worker can push a Live Activity update to a TestFlight build on a real iPhone (SPEC.md
§4.2, `docs/spikes/apns-worker.md`). M2 adds **accounts and friends** on D1: Sign in with Apple,
handles and names, friend codes and invite links, blocks, reports and account deletion. The
contract the app is written against is `docs/milestones/M2.md`.

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
| `GET /j/:code` | | The invite landing page (HTML): open in Lockin, or get it and type the code |
| `GET /.well-known/apple-app-site-association` | | Universal links for `/j/*` (used once the invite domain exists, M9) |

Everything else answers `404`. Errors are `{"error": "<a sentence>", "code": "<machine code>"}`;
the app switches on `code`. The codes per route are in `docs/milestones/M2.md`; on top of those,
any route can answer `400 bad_request` (a body that isn't a JSON object), `413 too_large` (a body
over 16 KB) and `500 internal`, and `POST /auth/apple` answers `502 apple_unavailable` when Apple's
keys can't be fetched.

| Path | What's there |
|---|---|
| `src/index.ts` | The Worker's entry point and router (`handle`, which the tests call with a fake `fetch`, clock and random source) |
| `src/accounts.ts` | `/auth/apple`, `/me`, `/handles/:handle`, `/devices` |
| `src/friends.ts` | `/friends…`, `/blocks…`, `/reports` |
| `src/invite.ts` | `/j/:code` and the apple-app-site-association file |
| `src/appleAuth.ts` | Sign in with Apple: identity-token verification (RS256 against Apple's cached keys), the code-for-refresh-token exchange and revocation (ES256 client secret) |
| `src/auth.ts` | Session tokens (32 random bytes; only the SHA-256 is stored) and the bearer check |
| `src/moderation.ts` | The handle and name check in `fixtures/moderation/README.md`, with the shared word list |
| `src/db.ts` | Every D1 query, typed |
| `src/admin.ts` | `POST /admin/push-test` |
| `src/liveActivity.ts` | The Live Activity wire format (SPEC.md §4.3): strict parsing, canonical encoding, the 3.5 KB budget, `stale-date`, APNs payloads for `update`, `end` and push-to-start, within APNs' 4 KB body limit |
| `src/apns.ts` | The APNs sender: token auth with a cached ES256 JWT, one retry on `ExpiredProviderToken` (never on a 429), bodies over 4 KB refused before sending |
| `src/jwt.ts` | ES256 signing with Web Crypto, from a `.p8` file |
| `src/demo.ts` | The spike's scenarios: `squad`, `join`, `cheer`, `end` |
| `src/room.ts` | The `Room` Durable Object, a stub until M3 |
| `migrations/` | The D1 schema (SPEC.md §4.6); `0002_accounts.sql` adds sessions, Apple's refresh token and report notes |
| `test/` | vitest. Route tests run real SQL on an in-memory SQLite behind a D1 stand-in (`test/d1.ts`), against a fake Apple with generated keys (`test/app.ts`). The shared fixtures in `fixtures/live-activity/` and `fixtures/moderation/` are tested here and by the Swift tests |

The moderation word list is imported straight from `fixtures/moderation/words.json`: wrangler
bundles it into the Worker like any other import, so there is one copy, and a word added there
reaches the server and the app's tests together. Deploy from a full checkout of the repository
(it is outside `server/`).

Logs say what happened, never who: no tokens, ids, handles or names, only counts and outcomes.

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
`/admin/push-test` only works against the deployed Worker.

## Turning the admin route off

Set `ENVIRONMENT = "production"` in `wrangler.toml` and deploy, or
`npx wrangler secret delete ADMIN_TOKEN`. Either way `/admin/push-test` answers `404`.
