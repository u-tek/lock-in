# Spike: APNs from a deployed Worker (M0)

Status: **PENDING**. Waiting on the owner's Apple setup (`docs/apple-setup.md`) and a run on a real
iPhone.

## Question

Can the Cloudflare Worker, deployed, send a Live Activity update through APNs that a TestFlight
build on a real iPhone shows in the Dynamic Island and on the Lock Screen?

## Why it matters

APNs only speaks HTTP/2. A Worker's outbound `fetch` doesn't let us choose the protocol. SPEC.md
§4.2 plans for the whole backend on Cloudflare, with the APNs sender inside the Worker and, from M3,
inside each `Room` Durable Object. If the Worker can't reach APNs, only the sender moves to a small
Node service that uses `node:http2`, and everything else stays on Cloudflare. M3's push fan-out is
built on whichever answer this spike gives, so it has to be settled before M3.

## What research found (October 2026)

**Very likely yes, but no Cloudflare document promises it.**

- The local runtime (`workerd`, behind `npm run dev`) has **no HTTP/2**, so APNs calls fail locally
  ("Network connection lost"). The same code works when deployed. Cloudflare's Workers lead on why:
  *"`workerd` doesn't have HTTP/2 support, but in production it sends requests through Cloudflare's
  proxy stack"*, which speaks HTTP/2 to the origin. There are *"no active plans"* to add HTTP/2 to
  `workerd` itself.
  [cloudflare/workerd#4841](https://github.com/cloudflare/workerd/issues/4841) (open).
- Several open-source projects in 2026 moved their APNs senders from `node:http2` to plain Worker
  `fetch`, for example [frink#139](https://github.com/benord-labs/frink/pull/139) (Live Activity
  pushes), [rawkoon#180](https://github.com/samuelloranger/rawkoon/pull/180) and
  [loylo-oss#3](https://github.com/AdrienADV/loylo-oss/pull/3). Most verified with mocks or a fake
  token, not delivery to a real phone, which is what this spike adds.
- The Workers-compatible APNs library
  ([FiveSheepCo/cloudflare-apns2](https://github.com/FiveSheepCo/cloudflare-apns2)) is plain `fetch`
  plus an ES256 JWT, the same approach as `server/src/apns.ts`. It wouldn't add anything.
- Cloudflare's docs never state the HTTP version of subrequests to third-party hosts
  ([Workers protocols](https://developers.cloudflare.com/workers/reference/protocols/)).

**Implications**

- The spike must run against the **deployed** Worker. A failure from `npm run dev` tells us
  nothing.
- The likeliest problems are configuration, not transport: the key's environment, the topic (bundle
  ID), or the token's environment.
- Apple refuses a *new* provider token more than once every 20 minutes **on the same connection**
  (`429 TooManyProviderTokenUpdates`) ([Apple](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)).
  Cloudflare, not our code, owns the connections to APNs, and each Worker isolate signs its own
  token. If this 429 shows up, transport works and `docs/decisions/0004-shared-apns-provider-token.md`
  applies.
- APNs response codes are listed in
  [Handling notification responses from APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns).

## What's already built

| Piece | Where |
|---|---|
| APNs sender: ES256 provider token from the `.p8`, cached and signed again after 40 minutes, one retry on `ExpiredProviderToken` | `server/src/apns.ts`, `server/src/jwt.ts` |
| `POST /admin/push-test`: sends a made-up squad to one Live Activity token | `server/src/admin.ts`, `server/src/demo.ts` |
| The Live Activity payload, checked against the 3,584-byte budget | `server/src/liveActivity.ts` |
| The **Push test** workflow, which calls the endpoint from the GitHub app | `.github/workflows/push-test.yml` |
| The APNs spike screen in the app's Developer menu: starts a Live Activity and copies `{"token","env","me","sid"}` | `App/` |
| The Live Activity itself (spike-grade: initials, not creatures) | `Widgets/`, `Packages/LKKit/Sources/LiveActivity` |

The scenarios (times are relative to the moment of sending, so the countdowns on the phone are live):

| Scenario | Event | Default priority | What the phone should show |
|---|---|---|---|
| `squad` | `update` | 10 | You, Noor, Kai and Mila focusing (about 20, 38, 23 and 60 minutes left), the pet at 42% |
| `join` | `update` | 10 | You (22 minutes left) and Noor, who has just started 50 minutes |
| `cheer` | `update` | 5 | The squad, plus a cheer from Noor to you |
| `end` | `end` | 10 | Everyone done. The activity ends, leaves the Dynamic Island and stays on the Lock Screen for up to 30 minutes |

The squad name, "Spike Squad", comes from the phone's own attributes, set when the spike screen
started the activity, not from the push.

## Procedure

Before you start: `docs/apple-setup.md` steps 1 to 12 are done, the Worker is deployed with its four
secrets and `ENVIRONMENT = "development"`, and the GitHub secrets `LOCKIN_API_URL` and
`LOCKIN_ADMIN_TOKEN` are set.

### 1. Transport check: no phone needed

This shows whether the deployed Worker reaches APNs at all, before any build exists. Send a fake
token, either from PowerShell:

```powershell
$adminToken = "…"   # the admin token
$body = '{"token":"' + ("00" * 32) + '","env":"production"}'
Invoke-RestMethod -Method Post -Uri https://lockin-api.yourname.workers.dev/admin/push-test `
  -Headers @{ Authorization = "Bearer $adminToken" } -ContentType "application/json" -Body $body
```

The expected answer is a refusal, which the Worker sends as HTTP 502, so `Invoke-RestMethod`
reports an error. Windows PowerShell shows the response body in the error message. On
PowerShell 7, add `-SkipHttpErrorCheck` to see it as a normal result.

Or use the GitHub app: **Actions** → **Push test** → **Run workflow**, with the field labelled
*Paste what the APNs spike screen copies…* set to
`{"token":"0000000000000000000000000000000000000000000000000000000000000000","env":"production"}`.
The run goes red because APNs refused the token. Its summary page shows APNs's answer.

| Answer | Means |
|---|---|
| `status` 400 `BadDeviceToken`, or 410 `Unregistered` | **Transport works.** The Worker reached APNs over HTTP/2, and APNs refused the fake token, as it should |
| `status` 403 with a reason (`InvalidProviderToken`, `BadEnvironmentKeyIdInToken`, …) | Transport works, but the key, Key ID or Team ID is wrong. Fix it before the phone test (table below) |
| `status` 429 `TooManyProviderTokenUpdates` | Transport works. See `docs/decisions/0004-shared-apns-provider-token.md` |
| `{"error": "Couldn't reach APNs: …"}`, HTTP 502 | Transport failed. Try again a few times over an hour before concluding anything |

Do this once or twice, not in a loop: APNs drops connections that keep producing errors.

### 2. Get a TestFlight build onto the phone

GitHub → **Actions** → **iOS** → **Run workflow**, tick *Archive a Release build and upload it to
TestFlight*. Or push a commit with `[testflight]` in its first line that changes more than
Markdown. Wait for the upload, then up to about 15 minutes of processing, and install the build
from the TestFlight app.

### 3. Start the Live Activity

On the iPhone, open Lockin → **Developer** → **APNs spike** → **Start a 25-minute activity**. Wait
until the push token appears. **APNs environment** must start with `production`, since TestFlight
builds get production tokens. Tap **Copy for the Push test**. That copies
`{"env":"production","me":"…","sid":"…","token":"…"}`, a complete request body. **Share** sends the
same text to your PC instead (by email to yourself, for example).

Make sure Live Activities are allowed: Settings → Lockin → Live Activities.

### 4. Send `squad`

In the GitHub app: **Actions** → **Push test** → **Run workflow**, then fill in the three fields:

- *Paste what the APNs spike screen copies…*: paste what the app copied. Curly quotes from the
  keyboard are fixed for you.
- *squad (you and three friends focusing), join …*: `squad`
- *APNs priority. …*: `default`

Run it, and keep the run open. Lockin is in the background now, so the Live Activity sits in the
Dynamic Island above the GitHub app: you can watch the **Send** step finish and the island change at
the same time. Then lock the phone and look at the Lock Screen too. The run's summary page shows the
Worker's status, APNs's status, the `apns-id`, the reason (if any), the environment and the payload
size.

Prefer the PC? The PowerShell command in step 1 does the same, and leaves the phone free to watch.
Send the blob to the PC with **Share** on the spike screen, then set `$body = '<blob>'` (single
quotes, since the blob contains double quotes). It sends `squad`; for the others, add a key such as
`"scenario":"join"` inside the braces.

### 5. Then `join`, `cheer` and `end`

Repeat step 4 with each scenario, in that order, and fill in a row of the table below for each.

- `cheer` goes at priority 5, which APNs may deliver later to save power. A delay of some seconds
  is normal; record it.
- `end` ends the activity. Start a new one on the spike screen, and copy again, before sending
  anything else.

### 6. Optional: an hour later

Send `squad` once more after at least an hour (start and copy a new activity first if the old one
has gone). This checks that a push still goes through long after the first one. It can't show the
Worker's 40-minute re-sign of its provider token: a Worker isolate that sat idle for an hour has
usually been replaced, so this push most likely signs a fresh token, as the first one did. The
answer doesn't say which token was used either, and the one retry on `ExpiredProviderToken` would
hide a stale one. `server/test/apns.test.ts` covers the re-sign.

## Reading the answer

| What you see | Means | Do |
|---|---|---|
| Worker HTTP 200, APNs 200 with an `apns-id`, and the phone changes within a few seconds | **Success** | Record it |
| APNs 200, but nothing changes on the phone | APNs accepted the push and the phone dropped it or hasn't shown it. Not a transport problem | Check Live Activities are on for Lockin. Try `"priority"` 5 in case iOS is throttling priority 10 for this activity. If it still fails, the phone couldn't decode the content-state (it drops those silently): compare `Model`'s `LockinAttributes` with `fixtures/live-activity/` |
| `Couldn't reach APNs: …` (HTTP 502, no `status`) | The Worker couldn't talk to APNs | Repeat over an hour. If it's consistent, that's the negative result (decision rule below) |
| 403 `InvalidProviderToken` | The key, Key ID and Team ID don't belong together | Check the Worker's `APNS_TEAM_ID`, `APNS_KEY_ID` and `APNS_PRIVATE_KEY` |
| 403 `BadEnvironmentKeyIdInToken` | The APNs key is Sandbox-only | Make a Production key (`docs/decisions/0002-apns-key-environment.md`) |
| 403 `ExpiredProviderToken` | The provider token is over an hour old by Apple's clock, even after the Worker's one retry | Unexpected: record it |
| 400 `BadDeviceToken` | The token doesn't belong to the environment named in `env`, or it's mistyped | TestFlight is `production`. Copy the token again |
| 400 `DeviceTokenNotForTopic`, `BadTopic`, `TopicDisallowed` | `APNS_BUNDLE_ID` in `wrangler.toml` isn't the app's bundle ID | Fix it (not `.widgets`) and deploy |
| 410 `Unregistered` or `ExpiredToken` | The activity has ended or been dismissed | Start a new one and copy again |
| 429 `TooManyRequests` | Too many pushes to this token in a row | Wait a minute |
| 429 `TooManyProviderTokenUpdates` | Transport works; two isolates presented different provider tokens on one connection | Record it; `docs/decisions/0004-shared-apns-provider-token.md` |
| 404 from the Worker | The route is hidden: `ENVIRONMENT` is `"production"`, `ADMIN_TOKEN` is unset or under 32 characters, `LOCKIN_ADMIN_TOKEN` doesn't match it, or the URL is wrong | `server/README.md` |
| 400 from the Worker, with a message | The request was refused before reaching APNs; the message names the field | Usually a mangled paste |
| 500 naming `APNS_…` | A Worker secret is missing, or `APNS_PRIVATE_KEY` isn't the `.p8` file's contents | Set it again (`docs/apple-setup.md` step 11) |

**To separate the app from the Worker** when APNs says 200 and nothing shows: send a Live Activity
push to the same token from Apple's own
[Push Notifications Console](https://icloud.developer.apple.com/dashboard). It runs in a browser on
Windows; production sends need the Admin or Account Holder role.

- Choose the app's bundle ID, the production environment and the push type `liveactivity`.
- For the payload, wrap the `contentState` from the Worker's response:
  `{"aps":{"timestamp":<now>,"event":"update","content-state":<contentState>}}`. Use the current
  Unix time for `<now>` (in PowerShell: `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`). The phone
  ignores an update older than the last one it showed.

If Apple's push shows and ours doesn't, the difference is in the Worker. If neither shows, the
problem is in the app.
[Apple's guide](https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console).

## Decision rule

- **The Worker works.** `squad`, `join`, `cheer` and `end` are accepted (APNs 200) and show on the
  phone. Keep the sender in the Worker. Close SPEC.md §9 open question 1. M3 builds the fan-out on
  `server/src/apns.ts`, after `docs/decisions/0004-shared-apns-provider-token.md` is settled.
- **The Worker reaches APNs, but APNs refuses.** Any answer with a `status`, such as 400 or 403.
  That's configuration, not the Worker. Fix it and run again.
- **APNs accepts, but the phone shows nothing.** Not a transport problem: debug the app and the
  wire format (see above). The Worker stays.
- **The Worker can't reach APNs.** `Couldn't reach APNs` every time, over at least an hour, for
  the transport check and the real token alike. Move **only the sender** to a small Node service
  using `node:http2`, behind the same `sendLiveActivity` interface. The Worker signs each request
  to it with a shared secret (HMAC). That service holds one long-lived HTTP/2 connection per APNs
  environment and one cached provider token. Hosting options:
  - [Cloudflare Containers](https://developers.cloudflare.com/containers/pricing/), which keeps
    everything on Cloudflare but needs the Workers Paid plan (US$5 a month);
  - any small Node host.

  Write the choice up in `docs/decisions/` before building it. SPEC.md §8 asks for the cheapest
  tier.

## Result

**PENDING.** The owner fills this in; Claude records the decision.

### Transport check

| Date | `env` | Worker HTTP | APNs status | Reason | Notes |
|---|---|---|---|---|---|
| | production | | | | |

### Phone

| Date | Build | iPhone model | iOS | Scenario | Priority | Worker HTTP | APNs status | `apns-id` | Reason | Seen in island (Y/N) | Seen on Lock Screen (Y/N) | Latency (s, rough) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | squad | default (10) | | | | | | | | |
| | | | | join | default (10) | | | | | | | | |
| | | | | cheer | default (5) | | | | | | | | |
| | | | | end | default (10) | | | | | | | | |
| | | | | squad (after 1 h) | default (10) | | | | | | | | |

An iPhone without a Dynamic Island shows only the Lock Screen view and banners: put "n/a" in the
island column. Latency is from the run's **Send** step finishing to the phone changing.

### Decision

**PENDING.**
