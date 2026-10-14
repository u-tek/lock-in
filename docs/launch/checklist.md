# M9 launch checklist

SPEC.md §6, M9: *privacy policy, support URL, App Review notes, demo accounts, TestFlight with 20+
real students across several squads, analytics review, launch content plan (desk-mode and island
videos).*

**Who:** **Owner** is you, in a browser on Windows. **Eng** is Claude, working in this repo and CI.
**Both** means Eng prepares it and you do the part that needs your accounts.

**Where things stand** (14 October 2026, updated): M1 and M2 are done; M3 to M7 are built and green,
waiting on phones and the owner's setup; M8 is built and switched off until Family Controls is
approved (`docs/milestones/`). Items done by Eng are ticked or marked **Eng done**; the owner's are
unchanged. The drafts are in this folder:

| File | What it's for | Published at |
|---|---|---|
| `privacy-policy.md` | Privacy policy | `https://<domain>/privacy` (served by the Worker) |
| `terms.md` | Terms of use (alongside Apple's standard licence agreement) | `https://<domain>/terms` (served by the Worker) |
| `support.md` | Support page and FAQs | `https://<domain>/support` (served by the Worker) |
| `app-review-notes.md` | Notes for App Review, Demo Buddy, the age rating and App Privacy drafts | Pasted into App Store Connect |
| `app-store-listing.md` | Name, subtitle, description, keywords, categories, screenshot plan | Pasted into App Store Connect |

## 0. Carried over from earlier milestones

These come from CLAUDE.md's "Apple admin the owner must do". They're repeated here because the
launch can't happen without them.

- [ ] **Owner. M0:** Developer Program, App IDs, App Group, APNs key, App Store Connect API key and
  the **Family Controls (Distribution)** requests for the app and its three extensions
  (`docs/apple-setup.md`).
- [ ] **Owner. M2:** a Sign in with Apple key as Worker secrets `SIWA_KEY_ID` and
  `SIWA_PRIVATE_KEY`. Without it, account deletion can't revoke the Apple token, and App Review
  checks that (`docs/milestones/M2.md`).
- [ ] **Owner. M3:** push enabled on the production App ID configuration, and a TestFlight group of
  real friends.
- [ ] **Owner. M7:** RevenueCat project, App Store subscription products, and tax and banking in
  App Store Connect (section 4).
- [ ] **Owner. M8:** Family Controls approved for all four App IDs. If it isn't approved by launch,
  ship without Deep Focus and take it off the paywall and the listing.

## 1. Name, domain and email (Owner)

- [ ] **Owner.** Settle the name. SPEC.md calls "Lockin" a working name and asks for `NAMES.md`
  (it doesn't exist yet; **Eng** can draft it with candidates). Check the App Store (try creating
  the name in App Store Connect), the domain, and TikTok, Instagram and YouTube handles.
- [ ] **Owner.** Buy the domain. Cloudflare Registrar sells at cost in the same account as the
  Worker, so the DNS is already in the right place. Budget about A$15 to A$30 a year (SPEC.md §8
  lists the domain as a cost but gives no figure).
- [ ] **Owner.** Email: set up `support@` and `privacy@` the domain. Cloudflare Email Routing
  forwards them to your existing inbox for free. These addresses go into every `[OWNER: …]` email
  placeholder.
- [ ] **Both.** Hostnames. Suggested: `<domain>` serves the web pages, invite links (`/j/<code>`)
  and `/.well-known/apple-app-site-association`; the API stays on `workers.dev` or moves to
  `api.<domain>`. Eng sets the Worker routes; you click through the Cloudflare dashboard.

## 2. Policy and support pages

- [ ] **Owner.** Fill in every `[OWNER: …]` in `privacy-policy.md`, `terms.md` and `support.md`,
  and decide the minimum age (open question 2). With a teenage audience, it's worth paying a
  privacy or consumer lawyer to read them once.
- [x] **Eng.** Publish them as pages on the domain (served by the Worker next to the invite landing
  page, or with Cloudflare Pages), plus a one-screen home page with the App Store link.
  *Done:* the Worker serves `GET /`, `/privacy`, `/terms` and `/support`, rendered from these drafts
  at build time (`server/src/pages.ts`, `server/README.md` "Web pages"). Edit a draft and deploy to
  change a page. Until every `[OWNER: …]` is filled in, a page shows them highlighted, says it's a
  draft and answers `noindex`; the home page does the same until `APP_STORE_URL` is set. They're on
  the domain once it points at the Worker (§1).
- [x] **Eng.** Replace the `example.com` Terms and Privacy links in
  `Packages/LKKit/Sources/Paywall/PaywallView.swift`. Add Support, Privacy and Terms rows under
  Settings → About. *Done:* both go to `<web host>/terms`, `/privacy` and `/support`, from the new
  `LK_WEB_HOST` build setting (optional secret of the same name), or the API host when it's empty.
  With neither, the links are hidden, and CI warns that App Review needs them. Add `LK_WEB_HOST`
  once the domain exists.
- [ ] **Owner.** Put the Privacy Policy URL, Support URL and (optionally) Marketing URL into App
  Store Connect.

## 3. App Store Connect metadata (Owner)

All the text is in `app-store-listing.md` and `app-review-notes.md`.

- [ ] **App Information:** name, subtitle, primary category Productivity, secondary Education.
  Content rights: no third-party content.
- [ ] **Age rating questionnaire:** use the draft answers in `app-review-notes.md` §7 and write
  down the rating Apple gives.
- [ ] **App Privacy:** use the draft in `app-review-notes.md` §8. **Eng** re-checks it against the
  code and the privacy manifest first.
- [ ] **The version:** description, keywords, promotional text, screenshots (the 6.9-inch set from
  `design/appstore/`), copyright, and App Review Information (contact details, notes, sign-in).
  Under version release, choose **Manually release this version** and turn on **phased release**.
- [ ] **Pricing and availability:** free, with in-app purchases. Countries: consider Australia and
  New Zealand first (open question 2).
- [ ] **In-app purchases:** attach the three Plus products to this version. An app's first in-app
  purchases must be submitted together with an app version.

## 4. Money: subscriptions, tax, banking, RevenueCat (Owner)

- [ ] **Business:** accept the Paid Apps Agreement, and fill in the tax forms (as an Australian
  individual, usually a US W-8BEN plus your Australian details) and the bank account. Apple collects
  and pays GST on App Store sales in Australia. Ask an accountant about income tax.
- [ ] **Products:** the subscription group "Lockin Plus", Monthly and Yearly (auto-renewable), and
  Lifetime (non-consumable), using the IDs, prices and 7-day free trial in `app-review-notes.md`
  §6. Each needs a display name, a description and a review screenshot (the paywall). Decide on
  Family Sharing.
- [ ] **RevenueCat** (SPEC.md §2, M7): create the project and its iOS app. Create an In-App Purchase
  key (App Store Connect → Users and Access → Integrations) and upload it to RevenueCat. Point App
  Store Server Notifications at RevenueCat's URL. Create an entitlement `plus` with the three
  products. The SDK key goes into the GitHub secrets, never into the repo (CLAUDE.md, "Secrets").
- [ ] **Both.** A RevenueCat webhook to the Worker, so the server knows who has Plus for squad
  limits (open question 5). Eng builds it; you add the webhook's shared secret to RevenueCat and to
  the Worker's secrets. **Eng done (M7):** `POST /webhooks/revenuecat` and `POST /me/plus/refresh`;
  the secrets are `REVENUECAT_WEBHOOK_AUTH` and `REVENUECAT_SECRET_KEY` (`server/README.md`, "Lockin
  Plus").

## 5. TestFlight with real students (Both)

- [ ] **Owner.** An external TestFlight group, "Students". Its first build goes through Beta App
  Review, and the notes in `app-review-notes.md` §1 work there too.
- [ ] **Owner.** Recruit **20 or more students in at least 5 squads of 3 to 6**. Mix the phones:
  with and without a Dynamic Island, an iPhone SE, iOS 18 and iOS 26. Put at least one squad on
  Plus (TestFlight purchases are free) to try 5 and 6-person squads and Squad Boost. For testers
  under 18, get a parent's OK.
- [ ] **Owner.** A feedback channel: TestFlight's screenshot feedback, plus somewhere to talk, such
  as a group chat or Discord server. "No chat" applies inside the app, not to the beta.
- [ ] **Owner.** Run it for at least 2 weeks, including a real assignment or exam week. Check
  muting and quiet hours at night, and check what happens when Live Activities are switched off.
- [ ] **Eng.** Measure and report: Live Activities started against failed; how many people have
  Live Activities switched off; how long a join takes to reach the island (target 5 s or less, from
  M3's "done when"); pushes per room; APNs errors; the largest payload sent (under 3.5 KB);
  TestFlight crash reports; whether testers come back after 1 and 7 days; and how many shared
  invites get redeemed.
- [ ] **Eng.** Turn the findings into a fix list and a release candidate.

## 6. Review account and submission (Both)

- [ ] **Eng.** Demo Buddy, as specified in `app-review-notes.md` §3, deployed to the production
  Worker with its tests green. **Built and green (M7);** the deploy is yours: `npx wrangler deploy`
  with `DEMO_BUDDY_ENABLED = "true"` (`server/README.md`, "Demo Buddy").
- [ ] **Owner.** Set the review code (`DEMO_BUDDY_CODE`) on the Worker. Test the whole flow from
  the notes on a fresh install, signed in with a second Apple Account (a family member's works).
- [ ] **Owner.** Paste the notes and fill in the contact details. Optionally set up a review Apple
  Account (`app-review-notes.md` §2).
- [ ] **Owner.** Submit, and answer App Review's messages within a day. Keep Demo Buddy running for
  every later update.

## 7. Engineering before submission (Eng)

**Release build**

- [ ] **`LK_DEVELOPER_TOOLS = NO`** for the build you submit. It's `YES` in
  `Config/Shared.xcconfig`, and TestFlight and the App Store share the same binary, so the release
  candidate has to be built with `NO` (a CI input, or `Config/Release.xcconfig`). Testers lose the
  Developer menu from then on.
- [ ] `MARKETING_VERSION` to `1.0.0` in `project.yml`.
- [ ] The production Worker gets `ENVIRONMENT = "production"`, which turns off
  `/admin/push-test`. Keep a separate development Worker (a `wrangler` environment) for push tests
  after launch.
- [ ] Remove the "Squads are coming soon" copy (Squads screen and Finished screen) once M3 ships.

**Privacy**

- [ ] Update `App/Resources/PrivacyInfo.xcprivacy` with `NSPrivacyCollectedDataTypes` matching
  `app-review-notes.md` §8: Name, Other User Content, User ID, Device ID, Product Interaction,
  Purchase History, Other Data Types (linked, not tracking), and Other Diagnostic Data (not
  linked). The file's own comment says to do this from M2 on. Re-check the required-reason APIs
  (more are needed if GRDB arrives). Make sure the RevenueCat and analytics SDKs ship their own
  privacy manifests.
- [ ] Sign in with Apple asks for the name scope only, never email (open question 12).
- [ ] Retention jobs (a Worker Cron Trigger) that do what the privacy policy promises: purge
  deleted accounts, expired invite codes, old events and closed reports.
- [ ] Sign in with Apple server-to-server notifications (consent revoked, Apple Account deleted)
  delete the Lockin account or sign it out. **Owner** enters the endpoint URL on the App ID in the
  developer portal.

**Analytics review** (SPEC.md §5.6, CLAUDE.md "integer event counts only")

- [ ] **Both.** Choose the analytics provider: Eng writes the options up in `docs/decisions/` and
  you decide. **Eng done:** `docs/decisions/0010-analytics-provider.md` recommends no third-party
  provider (App Store Connect for retention, the app's counts as daily totals on our own Worker,
  `POST /metrics`, already built); TelemetryDeck is the fallback. Requirements: integer counts only, nothing linked to the Lockin account, a privacy
  manifest, a free tier. Options include a privacy-first service such as TelemetryDeck, or no
  provider at all, using App Store Connect's App Analytics for retention (opted-in users only) and
  the server's own counts (open question 11). Then write the sink in `AppServices.analytics`.
- [ ] Check every `track` call. `AnalyticsKey` only accepts string literals and the counts are
  integers, so names and IDs can't leak by construction, but check that every event in
  `AnalyticsEvent` is actually sent where SPEC.md §5.6 expects it.

**Demo Buddy**

- [x] Build it as specified in `app-review-notes.md` §3. *Done (M7):* `server/src/demoBuddy.ts`,
  `reviewSquad.ts` and the rooms; deploying it is in §6.

**Rate limits on the API**

- [ ] Per-user and per-IP limits, using Cloudflare's Workers rate-limiting binding or a counter in
  a Durable Object, on: `POST /auth/apple`; `POST /friends/redeem/:code` and
  `POST /squads/join/:code` (to stop code guessing); `POST /friends/code`,
  `POST /squads/:id/invite`, `POST /reports`, `PATCH /me` and `GET /handles/:handle`; and
  `POST /sessions`, which fans out the invite alerts. Cheers already return `429 cheer_too_soon`.
- [ ] Caps on invite alerts per squad and per person (open question 10).
- [ ] Every limit answers `429 { error, code: "rate_limited" }` with `Retry-After`, and the app
  shows a friendly message. (Every 429 with a `retryAfter` now also sends the `Retry-After`
  header; `POST /metrics` has its limits. The routes above still need theirs.)

**Universal links** (once the domain exists)

- [ ] **Owner** turns on Associated Domains on the App ID. **Eng** adds `applinks:<domain>` to the
  app's entitlements in `project.yml`.
- [ ] The Worker serves `/.well-known/apple-app-site-association` (the route exists from M2) for
  `<Team ID>.<bundle id>` and `/j/*`, and the invite URL host becomes `<domain>`.
- [ ] The `/j/:code` landing page gets the real App Store link (it needs the app's App Store ID).
  It now reads the `APP_STORE_URL` Worker var, the same one as the home page: set it under `[vars]`
  in `wrangler.toml` once the app has its App Store page.
- [ ] The app opens `https://<domain>/j/<code>` the same way it opens `lockin://j/<code>`.

**Moderation** (Guideline 1.2: act on reports in a timely way)

- [ ] Tools to act within the promised [OWNER: 24 hours]: list open reports, change or clear a
  handle, display name or squad name, and suspend or delete an account. A documented
  `wrangler d1 execute` script is enough at first. Add a daily summary of new reports.
- [ ] Report and block from squad members, not just friends (open question 9).

**Paywall and Guideline 3.1.2**

- [ ] The paywall lists exactly the Plus features in the build: fix the "6 friends" wording, add
  custom session lengths, and remove anything that hasn't shipped (open question 3).
- [x] The server's Plus status comes from RevenueCat (section 4). *Done (M7):* the webhook and the
  refresh route set `users.plus_until`.

**Screenshots and monitoring**

- [ ] `store.*` routes for the 6.9-inch set (M6, `app-store-listing.md`). **Owner** uploads them.
- [ ] Alerts for Worker errors and APNs failures, and a view of push counts per room (Workers
  Observability).

## 8. Launch content plan (Owner, with testers; Eng supports)

SPEC.md §1.7: the Dynamic Island and desk mode are the moments people will film. All videos are
9:16, 15 to 30 seconds, for TikTok, Instagram Reels and YouTube Shorts, with captions on. Use music
from each platform's own library.

**Videos to make**

| # | Idea | Shot | Needs |
|---|---|---|---|
| 1 | "POV: your friends' timers live in your Dynamic Island" | Phone in hand. Friends join one by one (+1, +2, +3), then a long-press shows everyone's countdown | A real squad of 3 or 4 |
| 2 | Desk mode, study with me | Phone on its side on a charger beside a laptop and notes, in StandBy, with the squad row counting down. A 50-minute timelapse cut to 20 seconds, ending with everyone "Done" | StandBy, a tidy desk, good light or a night-time setup |
| 3 | "We hatched a pet by studying" | The egg hatching after the first group session, then later stages over a few weeks | M5 |
| 4 | Make your Lockling | A quick montage of building Locklings: "which one are you?" | M1 (works today) |
| 5 | "I slipped" | Opening a blocked app and your Lockling sweating in front of the whole squad | Deep Focus (M8) |
| 6 | Share card | The end-of-session card posted to a story, with the squad's invite code | M6 |

**Steps**

- [ ] **Owner.** Recruit 3 to 5 student creators from the TestFlight group. Get their written OK to
  post (and a parent's for anyone under 18). Show only names and handles they're happy with; faces
  aren't needed.
- [ ] **Owner.** Claim the social handles from step 1.
- [ ] **Owner.** Bank 10 to 15 videos before launch. Post daily in launch week, then 3 to 5 a week
  for the first month.
- [ ] **Owner.** Time it to the Australian calendar: Year 12 exams in October and November,
  university exams in June and November, Semester 1 from late February. Launch for the start of a
  semester or the run-up to exams, when "study with me" is in season. [OWNER: pick the date.]
- [ ] **Owner.** Use App Store Connect campaign links (a `ct=` token in the App Store URL in each
  bio) to see which platform brings installs.
- [ ] **Eng.** Report weekly: invites shared and redeemed, squads created, D1 and D7 retention, and
  paywall views against trials. All counts only.

## Open questions

Where the code and SPEC.md disagree, or a decision is still missing. Each one affects something in
the launch drafts.

1. **Name.** SPEC.md calls "Lockin" a working name and asks for `NAMES.md`, which doesn't exist.
   The availability check hasn't been done. (Owner)
2. **Minimum age.** The audience is 15 to 25, and no minimum age is set anywhere. The drafts suggest
   13. Get advice on Australia's social media minimum age of 16 (does Lockin count as an
   "age-restricted social media platform"?) and on the OAIC's Children's Online Privacy Code.
   Launching in the US or EU adds COPPA, state app store age laws and GDPR's ages of consent
   (13 to 16). (Owner)
3. **The paywall doesn't match SPEC.md §2.** `PlusFeature.all` in `PaywallView.swift` lists five
   features. SPEC.md also has custom session lengths (already Plus-only on Home but missing from the
   paywall), full stats history and a yearly recap (no milestone builds them). "Up to 6 friends, in
   3 squads" reads as 7 people, but SPEC.md means squads of 6 including you. Deep Focus, Squad
   Boost, streak freezes and monthly drops don't exist yet. M1.md suggests "coming soon" labels;
   the drafts suggest leaving features off until they ship, which is safer under 3.1.2.
4. **The paywall's Terms and Privacy links** ~~still go to `example.com`~~. *Resolved:* they go to
   the Worker's `/terms` and `/privacy` (`LK_WEB_HOST`, or the API host), and hide in a build with
   neither.
5. **How does the server learn about Plus?** M3 enforces the free limits on the server
   (`402 plus_required`, `users.plus_until`), but Plus lives only in StoreKit on the phone
   (`PlusStore`). RevenueCat doesn't arrive until M7. Lifetime has no end date, so what goes in
   `plus_until`?
6. **The schema against M2.md.** `0001_init.sql` had no table for sign-in tokens, no column for
   the Sign in with Apple refresh token and no `note` on `reports`. The M2 work in progress (not yet
   committed when this was written) adds all three in `server/migrations/0002_accounts.sql`.
   `la_env` (decision 0005) is still missing for M3. The privacy policy assumes report notes are
   stored, up to 500 characters, for moderators only.
7. **Deletion and retention.** The M2 code in progress deletes the `users` row outright
   (`DELETE FROM users`, cascading), which matches the privacy policy's "straight away". The comment
   in `0001_init.sql` about keeping the row "while it waits to be purged" is now out of date.
   Reports *about* a user are deleted when that user deletes their account
   (`reports.target_user_id ON DELETE CASCADE`), so someone who's been reported can wipe the
   reports. Consider SET NULL plus a copy of the reported name. Squads whose owner deletes their
   account are left with `owner_id` NULL. M3 hands a squad on when its owner leaves, and deletion
   should do the same. No retention period is set yet for events, closed reports or logs.
8. **Signed-in solo sessions.** SPEC.md §4.6 and §4.7 allow solo sessions on the server
   (`sessions.squad_id` NULL, `squadId` optional on `POST /sessions`). M1 keeps solo sessions on
   the phone. The privacy policy says signed-in users' "focus sessions" are stored. If solo
   sessions won't sync, narrow that row to squad sessions.
9. **Report and block for squadmates.** M2 puts report and block in the Friends list only. M3's
   squad detail has mute and leave, but no report, no block and no way for an owner to remove a
   member, and squad names (also user-generated) can't be reported. It's also undefined what
   blocking someone who shares your squad does: the block check runs only when someone joins.
   SPEC.md §7 and Guideline 1.2 need all of these.
10. **Invite rate limit and the "about 2 a day" rule.** SPEC.md §7 says invites are rate-limited,
    but no number is set anywhere (M4). Do "locking in" alerts count towards CLAUDE.md's limit of
    about 2 non-session notifications a day, or are they session notifications? The review notes
    need the number.
11. **Retention analytics versus "counts only".** SPEC.md §5.6 wants D1, D7 and D30 retention, which
    a provider can only work out with an ID for each install. `Core/Analytics.swift` sends event
    names and integer counts only, and no provider has been chosen. Decide on a provider with an
    anonymous install ID (and declare it), or use App Store Connect's retention numbers and no
    provider. *Written up:* `docs/decisions/0010-analytics-provider.md` (proposed: no provider,
    with optional ID-free retention events).
12. **Email.** There's no email column, and the drafts say we never collect email. The M2 server
    in progress ignores the email in Apple's identity token (`src/appleAuth.ts`). Still to confirm:
    the app's Sign in with Apple request asks for the name scope only.
13. **The expanded island (SPEC.md §1.3 against decision 0007).** SPEC.md still puts the pet and a
    Cheer button in the expanded island. The shipped island has no pet (decision 0007, awaiting
    you) and has Pause, Resume and End buttons. The listing and screenshots don't promise the pet
    in the island. Update SPEC.md once you agree.
14. **Quiet hours.** SPEC.md §5.7 sets a default of 22:00 to 07:00, but no setting or server field
    exists yet (`devices` has only `tz`). The support page and policy mention quiet hours with
    placeholders.
15. **Developer tools.** `LK_DEVELOPER_TOOLS` is `YES` for every build, and TestFlight and the App
    Store share one binary. Decide when testers lose the Developer menu: at the release candidate,
    or with a CI switch.
16. **Universal links.** There's no Associated Domains entitlement in `project.yml` yet, and the
    invite host is waiting on the domain. Until then, invite links can only be `lockin://` or the
    `workers.dev` landing page.
17. **Where the review notes live.** CLAUDE.md's layout lists `docs/app-review-notes.md`, but they're
    in `docs/launch/app-review-notes.md`. Move the file or update the layout.
18. **Smaller decisions for the drafts:** Family Sharing for Plus; the D1 database's region (the
    privacy policy names it; `docs/apple-setup.md` creates the database without `--location`, so it lands near whoever runs the command); how long to keep
    server logs, events and closed reports; whether inactive accounts are deleted.
