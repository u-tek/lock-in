# 0003: CI signing may need a stored development certificate

Status: **proposed**, awaiting the owner. Act on it only if the second TestFlight run fails as
described below.

Affects: M0 (the TestFlight lane).

## Context

CLAUDE.md: *"Upload from CI with an App Store Connect API key stored as repo secrets."*
`docs/milestones/M0.md` (Risks): *"TestFlight upload uses automatic signing with an App Store
Connect API key; the key needs the Admin role so Xcode can create the distribution certificate in
the cloud."*

`scripts/testflight.sh` does exactly that. It runs `xcodebuild archive` with `-allowProvisioningUpdates`
and the API key, then `-exportArchive` with `method = app-store-connect` and automatic signing.
There are no certificates on the runner.

## Finding

The export step is covered. It signs with a cloud-managed **distribution** certificate, which Admin
keys may create
([Cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/),
[Roles](https://developer.apple.com/help/account/access/roles/)).

The archive step is not. Under automatic signing, `archive` first signs with an **Apple
Development** certificate, which isn't cloud-managed. On a fresh runner, xcodebuild creates one
through the API key, with a private key that exists only on that runner. Reports from GitHub Actions
and Bitrise, 2021 to 2024, with Admin keys, describe this sequence:

1. The first run succeeds.
2. The next run on a clean machine fails with *"Revoke certificate: Your account already has an
   Apple Development signing certificate for this machine, but its private key is not installed in
   your keychain."*
3. Revoking the certificate makes one more run pass. Development certificates pile up on the
   portal.

Apple Support told one reporter it *"didn't have a solution"* (Xcode 15.4). The workaround everyone
uses is a development certificate supplied to CI.
[Apple Developer Forums 695759](https://developer.apple.com/forums/thread/695759),
[760819](https://developer.apple.com/forums/thread/760819),
[fastlane discussion 19973](https://github.com/fastlane/fastlane/discussions/19973).

Whether Xcode 26 on `macos-26` runners still behaves this way is unknown. Nobody has been able to
try it without the Apple account.

## Proposal

1. **Keep the lane as it is for the first uploads.** It costs nothing if the problem has gone away.
   Watch two things: whether a **second** `[testflight]` run fails with the message above, and
   whether the [Certificates](https://developer.apple.com/account/resources/certificates/list) list
   gains an Apple Development certificate on every run.
2. **If it bites,** give CI one long-lived Apple Development certificate. Automatic signing then uses
   it instead of making a new one, and the export still uses the cloud-managed distribution
   certificate. All of it can be done from Windows: Git for Windows includes `openssl`.

   ```sh
   # In Git Bash. dev.key never leaves the PC except inside the .p12. MSYS_NO_PATHCONV stops Git
   # Bash turning "/emailAddress=…" into a Windows path.
   MSYS_NO_PATHCONV=1 openssl req -new -newkey rsa:2048 -nodes -keyout dev.key -out dev.csr \
     -subj "/emailAddress=you@example.com/CN=Lockin CI/C=AU"
   # Certificates → + → Apple Development → upload dev.csr → download development.cer
   openssl x509 -inform DER -in development.cer -out dev.pem
   openssl pkcs12 -export -legacy -inkey dev.key -in dev.pem -out dev.p12   # asks for a password
   base64 -w0 dev.p12   # the value for the first secret below
   ```

   Two new repository secrets (proposed names): `APPLE_DEV_CERT_P12` (the base64 of `dev.p12`) and
   `APPLE_DEV_CERT_PASSWORD`. The TestFlight job gets one new step before *Archive and upload*. That
   step creates and unlocks a temporary keychain, runs `security import` on the `.p12`, runs
   `security set-key-partition-list` so `codesign` can use it without a prompt, and deletes the
   keychain at the end. Revoke the stray certificates that earlier runs left behind. This doesn't
   affect builds already in TestFlight, which are distribution-signed.

   `-legacy` matters: OpenSSL 3's default `.p12` encryption isn't readable by the macOS keychain.

3. **Alternative:** manual signing, with a stored Apple Distribution certificate and App Store
   provisioning profiles for the app and the widget extension. It avoids development signing
   altogether, but there are more secrets to renew every year, and every new extension (M8) needs its
   own profile. Prefer option 2.

Whoever applies option 2 should also update the comment at the top of `scripts/testflight.sh` and
the M0 risk note.
