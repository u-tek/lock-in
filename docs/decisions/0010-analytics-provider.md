# 0010: Analytics without a provider: App Store Connect plus our own counts

Status: **proposed**, awaiting the owner. Answers launch checklist open question 11 and the
"Analytics review" item in `docs/launch/checklist.md` §7.

Affects: M9 (the analytics sink in `App/Sources/AppServices.swift`, the privacy policy's
"Analytics" section, the App Privacy answers in `docs/launch/app-review-notes.md` §8).

## Context

SPEC.md §5.6: *"Event counts only, no content. Track: onboarding steps, first session completed,
Live Activity started/failed, squad created, invite shared, invite redeemed, squad session joined,
pushes per room, D1/D7/D30 retention, paywall shown/started trial/converted."*

CLAUDE.md: *"Analytics are integer event counts only; no content, names or ids of friends."*

The app already sends nothing but that. `Core/Analytics.swift` takes an `AnalyticsEvent` (21 fixed
names, now also in `fixtures/analytics/events.json`) and integer counts under string-literal keys,
and hands them to a sink. The sink is `.debugLog`: the counts go to the phone's unified log and
nowhere else. Choosing a provider means choosing that sink.

The checklist's requirements for it:

1. **Integer event counts only.** Nothing the person typed, no names, no friends' ids.
2. **Nothing linked to the Lockin account.**
3. **A privacy manifest** for any SDK, so App Review and the App Privacy answers stay honest.
4. **A free tier** (SPEC.md §8 budgets only the developer account, Cloudflare, RevenueCat and a
   domain).

And the audience: mostly 15 to 25, with a suggested minimum age of 13. The OAIC's Children's
Online Privacy Code and Australia's under-16 rules are still open (checklist open question 2). Every
piece of data and every overseas processor we can avoid makes those answers simpler.

The one thing that pulls the other way is **retention** (D1, D7, D30). A provider can only work out
retention per install with an identifier for each install, which is more than a count.

## Options

### (a) TelemetryDeck

A privacy-focused analytics service from Germany, built for Apple platforms.

- **What leaves the phone:** each event as a "signal" with its name and our counts as string
  parameters (the same shape as our sink: `[String: String]`), plus metadata the SDK adds by default
  (app version and build, OS version, device model, locale and region, whether it's TestFlight or a
  simulator, and so on), plus a **pseudonymous user identifier**: by default a salted hash of the
  install's identifier, hashed again on their side. That identifier is what gives it retention,
  funnels and daily active users.
- **Requirements:** (1) mostly: the counts are, but the default metadata isn't counts and would need
  turning off where the SDK allows it. (2) Yes, if we never pass our user id as its identifier.
  (3) Its Swift SDK ships a privacy manifest. (4) Yes, a free tier (check the current monthly signal
  allowance; it has been 100,000 signals a month).
- **Good:** dashboards, retention, funnels and per-version breakdowns with no building on our side;
  a sink of a few lines; EU hosting.
- **Costs:** a third-party SDK in a teen app; a processor outside Australia to name in the privacy
  policy and keep up to date; an install identifier to declare (App Privacy: likely Identifiers →
  Device ID and Usage Data → Product Interaction, "not linked to you", per TelemetryDeck's own
  guidance at the time); its default metadata is more than "integer counts only"; and a free tier
  that a growing app can outgrow.

### (b) No provider: App Store Connect App Analytics + our own counts

- **Retention, installs, sessions, crashes:** App Store Connect → Analytics, from people who allow
  *Share With App Developers* in their iPhone settings (a minority of users, but a large enough
  sample once there are a few hundred installs). It reports retention by download date. Apple's own
  benchmarks use Day 1, Day 7 and Day 28, so read "D30" as D28 there; check which days the
  retention view offers when the app is live.
- **Purchases, trials and conversions:** App Store Connect's Sales and Trends and Subscriptions
  reports, and RevenueCat's dashboard (M7) when it's in use. Exact, for everyone, not a sample.
- **What the server already knows:** pushes per room (`events`, `room_end`), squads created,
  squad sessions joined, invites redeemed, and focus minutes for signed-in sessions (`focus_log`).
- **The rest:** the app's counts go to our own Worker, `POST /metrics`, which adds them to **daily
  totals** in D1: a row is a UTC day, an event name and a number. No account, no device, no
  identifier, no IP address is kept, and no third party sees them.
- **Requirements:** (1) Yes, literally: only event names and whole numbers leave the phone.
  (2) Yes: nothing in a row can be linked to anyone, by construction. (3) Nothing to declare: no SDK.
  (4) Free: a batch a day from each phone is a few D1 rows, well inside the free plan (the route has
  a daily cap so a flood can't use up D1's writes for the rest of the API).
- **Good:** the smallest privacy story we can tell ("counts go to our own server as daily totals"),
  no new processor or overseas transfer beyond Cloudflare, which the policy already names; no SDK,
  no manifest to maintain, no account to sign up for; the event list is checked on both sides.
- **Costs:** no dashboards (totals are read with `wrangler d1 execute`, or a small weekly report
  later); retention only for the opted-in sample unless we add the ID-free retention events below;
  no per-person funnels, by design; the counts are unauthenticated, so they're directional (the
  route is rate-limited and validated, but a determined person could inflate them).

**Retention without an identifier (optional, not built).** The phone already knows the day it was
first opened, and that never needs to leave it. Four more events would give D1, D7 and D30 for
everyone, as totals:

- `app.firstOpened`, once per install;
- `retention.day1`, `retention.day7`, `retention.day30`: sent once, when the app is opened on that
  day after its first open.

D7 retention for the people who installed on a given day is then `retention.day7` seven days later
divided by `app.firstOpened` that day: a ratio of two totals, with no install ID anywhere. Adding them
means four cases in `AnalyticsEvent` and the fixture, and a few lines in the sink.

### (c) Firebase (Google Analytics for Firebase), and the other mainstream services

- **Firebase** logs events per **app instance ID**, collects some events automatically (first open,
  sessions, screen views, in-app purchases), adds device, app and coarse location (from the IP
  address) to each, and keeps the data with Google in the US. It's free and capable, but every
  requirement is a fight: (1) and (2) need features turned off and its identifier is still on every
  event; its App Privacy declaration is larger; it's a Google SDK in an app for teenagers, where
  Google's own terms and child-directed settings come into play, and it would put Lockin in the
  same bucket as ad-supported apps in parents' and reviewers' eyes. **Not recommended.**
- **Mixpanel, Amplitude, PostHog:** product analytics built around per-person profiles and
  identifiers, which is what CLAUDE.md rules out; free tiers exist, but the model is wrong for us.
  PostHog can be self-hosted, which is too much to run for one person.
- **Aptabase** and similar small privacy-first services: much like (a), with smaller ecosystems.
  If the owner wants a hosted dashboard, TelemetryDeck is the more established choice.

## Comparison

| | (a) TelemetryDeck | (b) No provider | (c) Firebase |
|---|---|---|---|
| Only integer counts leave the phone | No (default metadata, a hashed ID) | **Yes** | No |
| Nothing linkable to the account | Yes, if we never pass our id | **Yes, by construction** | Instance ID on every event |
| Privacy manifest | The SDK's | **None needed** | The SDK's |
| Free | Free tier with a monthly cap | **Yes** (Cloudflare free plan) | Yes |
| New processor / overseas transfer | Yes (Germany) | **No** (Cloudflare, already named) | Yes (Google, US) |
| D1/D7/D30 retention | Yes, for everyone | Opted-in sample (ASC); everyone with the optional retention events | Yes |
| Dashboards | Yes | No (SQL, or a report later) | Yes |
| Work for us | A sink | A sink (the route is built) | A sink, and turning things off |

## Recommendation

**(b): no third-party provider.** Lockin's rule is "integer event counts only, nothing linked to the
account", and (b) is the only option that meets it without exceptions; the audience is teenagers,
where the cheapest data to defend is data we never collect; it's free and adds no SDK, manifest or
processor; and the numbers the launch checklist asks for (§5 "measure and report", §8 weekly
report) are mostly server-side or in App Store Connect already. Retention is the one gap, and App
Store Connect's sample covers it for launch; the ID-free retention events close it if the sample
turns out too thin.

If the owner would rather have dashboards and funnels from day one and accepts a pseudonymous
install identifier, **(a) TelemetryDeck** is the fallback. Because the app talks to a sink, changing
later in either direction is a one-line change in `AppServices.analytics` plus the policy text.

## What's built, and what isn't

Built (server only, tested), so (b) costs little to switch on:

- `POST /metrics` (`server/src/metrics.ts`): `{ "counts": { "<event>": n } }` → 204. No sign-in,
  and a bearer token, if sent, is never read. Names must be in `fixtures/analytics/events.json`
  (CoreTests checks it matches `AnalyticsEvent`; the server's tests check it too). Counts are whole
  numbers from 1 to 250. 20 batches a minute per IP address (Cloudflare's rate-limiting binding,
  never stored) and 10,000 batches a day in all; over either, 429 `rate_limited` with
  `Retry-After`.
- `migrations/0008_metrics.sql`: `metrics_daily (day, event, count)` and `metrics_batches (day,
  batches)`. Nothing in them refers to a user.
- `server/README.md`, "Analytics counts (proposed)", has the query to read them.

Not built, waiting for the decision:

- **The app's sink.** `AppServices.analytics` stays `.debugLog`. For (b): a small store in the App
  Group that adds up counts by event, and on the first launch of each day sends everything before
  today to `<API host>/metrics` without the bearer token, keeping it on failure and waiting out a
  `Retry-After`. Counts then land on the day they arrive, a day late, which is fine for weekly
  numbers. Signed-out phones send too; a build without an API host keeps logging.
- **The retention events** above, if wanted.
- **The privacy policy** "Analytics" paragraph (an `[OWNER: …]` placeholder today). Suggested text
  for (b): *"We don't use an analytics provider. The app sends these counts to our own server, which
  adds them to daily totals, like 'sessions completed on 14 October: 812'. Nothing about you or your
  phone is kept with them, not even an ID, and they're kept as totals only."* Delete the analytics
  provider line under "Who we share it with", and in the retention table write "Kept as daily
  totals, which can't identify anyone".
- **App Privacy** (`app-review-notes.md` §8): for (b), the counts are Usage Data → Product
  Interaction, which is already declared; nothing changes. For (a), add the install identifier as
  described above.

## Owner, to decide

1. (a), (b) or something else.
2. If (b): whether to add the four retention events now or wait for App Store Connect's sample.
3. Whether minutes per session (the `minutes` and `members` counts some events carry) matter
   beyond what the server already has for signed-in sessions. `POST /metrics` takes how many times
   each event happened, not those sums; they're easy to add as their own names if wanted.
