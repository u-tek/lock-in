# Lockin API

The Cloudflare Worker behind Lockin (SPEC.md §4). In M0 it has one real job: the **APNs spike**,
proving that a deployed Worker can push a Live Activity update to a TestFlight build on a real
iPhone (SPEC.md §4.2). The result goes in `docs/spikes/apns-worker.md`.

| Route | What it does |
|---|---|
| `GET /health` | `{"ok": true, "environment": "development"}` |
| `POST /admin/push-test` | Sends a made-up squad to one Live Activity. Development only, behind `ADMIN_TOKEN` |

Everything else answers `404`. Most of the code is groundwork for later milestones, tested now:

| Path | What's there |
|---|---|
| `src/index.ts` | The Worker's entry point and router (`handle`, which the tests call with a fake `fetch` and clock) |
| `src/admin.ts` | `POST /admin/push-test` |
| `src/liveActivity.ts` | The Live Activity wire format (SPEC.md §4.3): strict parsing, canonical encoding, the 3.5 KB budget, `stale-date`, APNs payloads for `update`, `end` and push-to-start |
| `src/apns.ts` | The APNs sender: token auth with a cached ES256 JWT, one retry on `ExpiredProviderToken` |
| `src/jwt.ts` | ES256 signing with Web Crypto, from the `.p8` file |
| `src/demo.ts` | The spike's scenarios: `squad`, `join`, `cheer`, `end` |
| `src/room.ts` | The `Room` Durable Object, a stub until M3 |
| `migrations/` | The D1 schema (SPEC.md §4.6), unused until M2 |
| `test/` | vitest, including every file in `fixtures/live-activity/` (the same files the Swift tests decode) |

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
- the app's **bundle ID**, the same as `LK_BUNDLE_ID` in `Config/Local.xcconfig`.

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

6. Wire up the rest:
   - `Config/Local.xcconfig`: `LK_API_HOST = lockin-api.yourname.workers.dev` (host only, no
     `https://`, because `//` starts a comment in xcconfig files).
   - GitHub → Settings → Secrets and variables → Actions: `LOCKIN_API_URL` =
     `https://lockin-api.yourname.workers.dev` and `LOCKIN_ADMIN_TOKEN` = the admin token, for the
     push-test workflow; `LK_API_HOST` = the host, for TestFlight builds.

To watch requests as they happen: `npx wrangler tail`. The Worker logs the APNs status and the
payload size, never a token or the key.

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
| `Couldn't reach APNs` | The Worker couldn't talk HTTP/2 to APNs: the spike's failure case. Write it up; the fallback is a small Node relay using `node:http2` behind the same `sendLiveActivity` interface (SPEC.md §4.2) |
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
```

## Turning the admin route off

Set `ENVIRONMENT = "production"` in `wrangler.toml` and deploy, or
`npx wrangler secret delete ADMIN_TOKEN`. Either way `/admin/push-test` answers `404`.
