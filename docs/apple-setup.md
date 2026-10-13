# Apple and Cloudflare setup (M0)

The one-time admin that M0 needs from the owner, in order. Everything happens in a browser or in
PowerShell on Windows; nothing needs a Mac. Expect about an hour of clicking, plus waiting on Apple.

**Start the two slow steps first.** Both wait on Apple, so start them on day one even though they
appear later in this list:

- **App Store Connect API access** (step 10): Apple approves the first request "case by case".
- **Family Controls (Distribution)** (step 7): reported waits run from a day to several weeks.

**Secrets never go into the repo, a commit message, an issue or a chat.** Not even a "redacted"
copy. They go into GitHub's repository secrets (step 12) and the Worker's secrets (step 11), and
nowhere else. Both `.p8` files below are named `AuthKey_<id>.p8`; they are different keys for
different places.

## What you'll collect

| Value | Looks like | Goes into | Secret? |
|---|---|---|---|
| Team ID | `ABCDE12345` | GitHub `APPLE_TEAM_ID`, Worker `APNS_TEAM_ID` | Keep it out of chats |
| Bundle ID | `com.yourname.lockin` | GitHub `LK_BUNDLE_ID`, `APNS_BUNDLE_ID` in `server/wrangler.toml` | No |
| APNs key: Key ID and `.p8` | `XYZ9876543`, `AuthKey_XYZ9876543.p8` | Worker `APNS_KEY_ID`, `APNS_PRIVATE_KEY` | **Yes** |
| App Store Connect API key: Key ID, Issuer ID and `.p8` | `2X9R4HXF34`, a UUID, `AuthKey_2X9R4HXF34.p8` | GitHub `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | **Yes** |
| Admin token | 64 hex characters you generate | Worker `ADMIN_TOKEN`, GitHub `LOCKIN_ADMIN_TOKEN` | **Yes** |
| Worker address | `https://lockin-api.yourname.workers.dev` | GitHub `LOCKIN_API_URL`, and optionally `LK_API_HOST` (host only) | No |

## 1. Join the Apple Developer Program

Pushes, TestFlight and the Family Controls entitlement all need the paid program (A$149 a year).
Free sideloaded builds can't receive pushes (SPEC.md §3).

1. Enrol at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/).
   Enrolling as an individual is quickest. An organisation needs a D-U-N-S number and takes longer,
   but its name shows as the seller on the App Store instead of yours. Either works for Lockin.
2. Once you're in, open [App Store Connect](https://appstoreconnect.apple.com) → **Business** and
   accept any agreement waiting there. Apple won't let you create an app record (step 9) until the
   Account Holder has. The Paid Apps agreement and the banking and tax forms can wait until M7.
3. Find your **Team ID**: [developer.apple.com/account](https://developer.apple.com/account) →
   **Membership details**. It's 10 characters.

Several steps below need the **Account Holder** role, which you have if you enrolled yourself.

## 2. Choose the bundle ID

Reverse-DNS, lowercase, for example `com.yourname.lockin`. It's permanent once the first build is
uploaded, so choose carefully. Every other identifier derives from it:

| Identifier | For | Registered in |
|---|---|---|
| `<bundle id>` | The app | Step 4 |
| `<bundle id>.widgets` | The widget extension (the Live Activity) | Step 5 |
| `group.<bundle id>` | The App Group shared by the app and its extensions | Step 3 |
| `<bundle id>.shieldconfig` | M8: the ShieldConfiguration extension | Step 7 |
| `<bundle id>.shieldaction` | M8: the ShieldAction extension | Step 7 |
| `<bundle id>.activitymonitor` | M8: the DeviceActivityMonitor extension | Step 7 |

The first three come from `project.yml` and `Config/Shared.xcconfig`. The M8 three are proposals
made now because Family Controls is approved per bundle ID (step 7). When M8 adds those targets,
they must use exactly these IDs. `<bundle id>.uitests` is the UI test runner; it only runs in the
simulator and is never registered.

## 3. Register the App Group

[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
→ **Identifiers** → **+** → **App Groups** → Continue.

- Description: `Lockin`
- Identifier: `group.<bundle id>`

Continue, then Register.

## 4. Register the app's App ID

**Identifiers** → **+** → **App IDs** → Continue → **App** → Continue.

- Description: `Lockin`
- Bundle ID: **Explicit**, `<bundle id>`
- Capabilities, tick:
  - **App Groups**.
  - **Push Notifications**, and **Broadcast Capability** under it. Broadcast (iOS 18 channels) isn't
    used yet; SPEC.md §6 asks for it now so a later move to channels is server-only.
  - **Sign in with Apple** (leave it as a primary App ID). M2 needs it; turning it on now saves a
    trip.

Continue, then Register. Then open the new App ID from the list, click **Configure** (or **Edit**)
next to App Groups, tick `group.<bundle id>` and save. Do this even if registering didn't ask.

Lockin authenticates to APNs with a key (step 8), not a certificate, so ignore the certificate
buttons next to Push Notifications.

## 5. Register the widget extension's App ID

**Identifiers** → **+** → **App IDs** → **App**.

- Description: `Lockin Widgets`
- Bundle ID: **Explicit**, `<bundle id>.widgets`
- Capabilities: **App Groups**, then configure it with `group.<bundle id>` as in step 4.

It doesn't need Push Notifications: Live Activity pushes go to the app's topic,
`<bundle id>.push-type.liveactivity`.

## 6. Register your iPhone

You install builds through TestFlight, not by cable, but Apple won't make the development profile
that CI's archive step signs with unless the team has at least one registered device.

1. Find the phone's UDID. Connect the iPhone to the PC with a cable and open iTunes, or the newer
   Apple Devices app. On the phone's summary, click the serial number until it shows the UDID
   (on recent iPhones it looks like `00008110-001A2B3C4D5E801E`), then copy it.
2. [Devices](https://developer.apple.com/account/resources/devices/list) → **+** → platform iOS,
   a name such as "My iPhone", and the UDID → Continue → Register.

## 7. Request Family Controls (Distribution): start now

Deep Focus (M8) needs Screen Time APIs, and shipping them needs a distribution entitlement that
Apple approves **per App ID**: the app and each extension separately. Extension approvals are often
reported to lag the app's by weeks, which is why SPEC.md §6 asks for this in M0. Only the
**Account Holder** can request it.

1. Register the three M8 extension App IDs from step 2, as in step 5: **Identifiers** → **+** →
   **App IDs** → **App**, Explicit, with App Groups configured with `group.<bundle id>`:

   | Description | Bundle ID |
   |---|---|
   | `Lockin Shield Configuration` | `<bundle id>.shieldconfig` |
   | `Lockin Shield Action` | `<bundle id>.shieldaction` |
   | `Lockin Activity Monitor` | `<bundle id>.activitymonitor` |

2. For **each of the four** App IDs (the app and the three above): **Identifiers** → click it →
   **Capability Requests** tab → **Family Controls (Distribution)** → **Request**, and submit the
   form. Apple's steps:
   [Request access to managed capabilities](https://developer.apple.com/help/account/capabilities/capability-requests/).
   If your account doesn't show that tab, the older request form is at
   [developer.apple.com/contact/request/family-controls-distribution](https://developer.apple.com/contact/request/family-controls-distribution).

   A description you can adapt for the form:

   > Lockin is a focus timer for studying with friends. In Deep Focus, an optional feature, the
   > user chooses their own distracting apps with FamilyActivityPicker, using individual
   > authorization on their own device. During a focus session those apps are shielded with
   > ManagedSettings. The DeviceActivityMonitor extension applies and removes the shield with the
   > session, the ShieldConfiguration extension draws the shield, and the ShieldAction extension
   > records when the user chooses to open an app anyway. That only counts a "slip" shown to their
   > study group. The selection stays on the device as opaque tokens; we never learn which apps
   > were chosen.

3. Check progress on the same **Capability Requests** tab (**Status**). Note each request's date
   here or in `docs/milestones/M0.md`. If one sits in "Submitted" for more than about two weeks, open
   a code-level support request with Apple Developer Technical Support, quoting the Team ID and the
   App IDs.

Approval gates M8 only. Nothing in M0 to M7 waits on it. If M8 adds a DeviceActivityReport
extension, that App ID needs its own request.

## 8. Create the APNs key

[Keys](https://developer.apple.com/account/resources/authkeys/list) → **+**.

1. Key name: `Lockin APNs`. Tick **Apple Push Notifications service (APNs)** and click
   **Configure** next to it.
2. Environment: **Production**. TestFlight and App Store builds get production push tokens, and
   without a Mac every build you run is a TestFlight build. If the page offers
   **Sandbox & Production**, that works too and also covers Xcode builds later. Don't choose Sandbox
   alone: every push to a TestFlight build would fail with `403 BadEnvironmentKeyIdInToken`.
   See `docs/decisions/0002-apns-key-environment.md`.
3. Key type: **Team Scoped** (all topics).
4. Save, Continue, then Register or Confirm. **Download** `AuthKey_<Key ID>.p8` now: Apple lets
   you download it once only. Note the **Key ID** (10 characters).

Keep the `.p8` somewhere safe outside the repo. `.gitignore` ignores `*.p8`, but don't rely on it.
It goes into the Worker in step 11 and nowhere else. M2 makes a separate key for Sign in with Apple.

Apple's steps:
[Create a private key](https://developer.apple.com/help/account/keys/create-a-private-key/).

## 9. Create the app in App Store Connect and a TestFlight group

The first upload fails unless an app record with the bundle ID exists.

1. [App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → **+** → **New App**:
   - Platform: **iOS**
   - Name: must be unique on the App Store. If "Lockin" is taken, use a working name; it can be
     changed before release (SPEC.md: name still to be checked).
   - Primary language: your choice
   - Bundle ID: pick `<bundle id>` from the list. It appears once step 4 is done.
   - SKU: `lockin`
   - User Access: Full Access

   Then **Create**.
2. In the new app: **TestFlight** → **+** next to **Internal Testing** → name the group `Owner`,
   tick **Enable automatic distribution** → Create → **Invite Testers** → tick yourself → Add.
3. On the iPhone, install **TestFlight** from the App Store, signed in with the same Apple ID. The
   invitation arrives once the first build has been processed.

Export compliance is already answered: the app declares it uses no non-exempt encryption
(`ITSAppUsesNonExemptEncryption` in `project.yml`), so builds don't wait on that question.

## 10. Create the App Store Connect API key for CI

CI signs and uploads with this key (`scripts/testflight.sh`).

1. [Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api) →
   **App Store Connect API**. The first time, click **Request Access**, agree and submit. Only the
   Account Holder can, and Apple reviews it before you can make keys, so do this on day one.
2. Once access is granted: **Team Keys** → **Generate API Key** (or **+**).
   - Name: `Lockin CI`
   - Access: **Admin**. The export step signs with a cloud-managed distribution certificate, and only
     Admin keys may create one. Lower roles fail at signing.
3. **Download** the key's `.p8`, once only. Note its **Key ID** (in the table) and the
   **Issuer ID** (shown above the table).

A key's role can't be changed later; revoke it and make a new one instead. Apple's steps:
[App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).

There's a known risk with automatic signing on fresh CI machines (a new development certificate on
every run). It's written up, with the fix to apply if it bites, in
`docs/decisions/0003-ci-development-certificate.md`.

## 11. Deploy the Worker (Cloudflare)

A free Cloudflare account is enough for M0 to M3: it includes D1 and SQLite-backed Durable Objects.
Sign up at [dash.cloudflare.com](https://dash.cloudflare.com/sign-up). You need Node 22.13 or later.
These are the commands from `server/README.md`, which also covers troubleshooting.

```powershell
cd server
npm ci
npx wrangler login
npx wrangler d1 create lockin
```

`d1 create` prints a `database_id`. In `server/wrangler.toml`:

- paste it over the all-zero `database_id`;
- set `APNS_BUNDLE_ID = "<bundle id>"` under `[vars]`. Use the app's bundle ID, not `.widgets`.

Neither is a secret: commit both. Then create the tables and deploy:

```powershell
npx wrangler d1 migrations apply lockin --remote
npx wrangler deploy
```

The first deploy may ask you to choose a `workers.dev` subdomain; it becomes part of the address.
Note the address it prints, for example `https://lockin-api.yourname.workers.dev`.

Add the secrets. Use your own values; each command updates the live Worker straight away:

```powershell
"ABCDE12345" | npx wrangler secret put APNS_TEAM_ID       # Team ID (step 1)
"XYZ9876543" | npx wrangler secret put APNS_KEY_ID        # the APNs key's ID (step 8)
Get-Content AuthKey_XYZ9876543.p8 -Raw | npx wrangler secret put APNS_PRIVATE_KEY   # the APNs .p8
$adminToken = node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
$adminToken | npx wrangler secret put ADMIN_TOKEN
$adminToken   # copy it for LOCKIN_ADMIN_TOKEN in step 12, then close the window
```

Check it's up. The answer should be `ok: True` and `environment: development`:

```powershell
Invoke-RestMethod https://lockin-api.yourname.workers.dev/health
```

Leave `ENVIRONMENT = "development"` in `wrangler.toml` until the spike is done: `"production"`
turns `/admin/push-test` off.

If PowerShell says *running scripts is disabled on this system*, run
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, or type `npx.cmd` instead of `npx`.

## 12. Add the GitHub secrets

On github.com, in a browser: the repository → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**. Use one secret per row, with exactly these names. To copy a
`.p8`, open it in Notepad, press Ctrl+A, then Ctrl+C.

| Secret | Value | Used by |
|---|---|---|
| `APPLE_TEAM_ID` | Team ID (step 1) | TestFlight |
| `LK_BUNDLE_ID` | The bundle ID (step 2) | TestFlight |
| `ASC_KEY_ID` | The **API key's** Key ID (step 10) | TestFlight |
| `ASC_ISSUER_ID` | The Issuer ID (step 10) | TestFlight |
| `ASC_KEY_P8` | The whole **API key's** `.p8`, `BEGIN` and `END` lines included (step 10) | TestFlight |
| `LK_API_HOST` | Optional. The Worker's host only, e.g. `lockin-api.yourname.workers.dev`. It can also be a repository *variable* of the same name | TestFlight builds. The spike doesn't need it |
| `LOCKIN_API_URL` | `https://` plus the Worker's host (step 11) | Push test |
| `LOCKIN_ADMIN_TOKEN` | The admin token (step 11) | Push test |

The **APNs** `.p8` (step 8) belongs to the Worker only. The **API key's** `.p8` (step 10) belongs to
GitHub only. You don't need `Config/Local.xcconfig`: CI writes it from these secrets.

## 13. First TestFlight build

GitHub → **Actions** → **iOS** → **Run workflow**. Tick *Archive a Release build and upload it to
TestFlight* and run it. The GitHub app can do this too. Alternatively, push a commit with
`[testflight]` in its first line, as long as it changes something other than Markdown.

The build and upload take about 20 to 30 minutes. Apple then processes the build, usually within 15
minutes, and it appears in the TestFlight app.

- If a secret is missing, the job fails within seconds and names it.
- If signing or the upload fails, the job prints a checklist. Download the `testflight-logs`
  artifact from the run page.
- If a **later** run fails with *"Your account already has an Apple Development signing
  certificate for this machine, but its private key is not installed in your keychain"*, that's the
  risk in `docs/decisions/0003-ci-development-certificate.md`. Tell Claude.

Then run the spike: `docs/spikes/apns-worker.md`.

## What to send back

Tell Claude, in the chat, **without any secret values**:

- the bundle ID;
- the Worker's address;
- that `database_id` and `APNS_BUNDLE_ID` are committed in `server/wrangler.toml`;
- the APNs key's environment and type, e.g. "Production, Team Scoped". Not its ID or the file;
- which secrets are set, by name: the GitHub ones and the four Worker ones;
- the App Store Connect app name, if it isn't "Lockin";
- the Family Controls requests: which App IDs, and the dates; later, each approval;
- the first TestFlight build number, and whether it installed;
- the spike's results, or a commit that fills in the table in `docs/spikes/apns-worker.md`.

Never paste a `.p8`, the admin token or any other secret, even partly. If one leaks, revoke it
(Keys or Integrations page), make a new one and update the secret.
