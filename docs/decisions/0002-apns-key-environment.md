# 0002: APNs keys are tied to an environment

Status: **proposed**, awaiting the owner.

Affects: M0 (the key the owner creates now, and the spike). The CLAUDE.md wording also affects M3.

## Context

- SPEC.md §4.2: *"TestFlight and App Store builds use the **production** APNs host; Xcode debug
  builds use sandbox. Store the environment per device token."* That's right, but it says nothing
  about the key.
- CLAUDE.md, "Apple admin the owner must do": *"M3: enable push on the production App ID config."*
- `server/` holds one APNs key (`APNS_KEY_ID`, `APNS_PRIVATE_KEY`) and uses it for both hosts
  (`server/src/apns.ts`).

## Finding

Apple changed APNs keys in 2025. A key is now created with an **environment** and a **type**, and a
key used against the other environment's host is refused:

- *"Team-scoped keys … restrict usage to either Sandbox or Production … Each environment can have a
  maximum of two keys. … existing team-scoped keys that work in both the Sandbox and Production
  environments \[will\] continue to be supported."*
  ([Establishing a token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns))
- Creating a key: *"Click Configure next to 'Apple Push Notification service.' On the next page,
  choose the environment configuration and type of key (Team Scoped or Topic Specific)."*
  ([Create a private key](https://developer.apple.com/help/account/keys/create-a-private-key/))
- `403 BadEnvironmentKeyIdInToken`: *"The key ID in the provider token doesn't match the
  environment."*
  ([Handling notification responses from APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns))

Apple's older help page still says *"The signing key works for both the development and production
environments"*
([Communicate with APNs using authentication tokens](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/)).
That describes keys made before the change. Some third-party guides still mention a
"Sandbox & Production" choice for team-scoped keys.

There's also no separate "production App ID config" for push. With token authentication, the App
ID's Push Notifications capability covers both environments; the per-environment settings next to
it are for TLS certificates, which Lockin doesn't use. What decides whether production pushes work
is the key's environment.

The owner has no Mac, so every build on a phone is a TestFlight build with **production** tokens. A
Sandbox-only key would fail every push in the spike with `403 BadEnvironmentKeyIdInToken`, which
could be misread as the Worker failing.

## Proposal

1. **M0:** create the APNs key as **Team Scoped, Production**, or "Sandbox & Production" if the
   portal offers it. This is already what `docs/apple-setup.md` step 8 says.
2. **SPEC.md §4.2:** add "APNs keys are tied to an environment. The Worker's key must work in
   Production (TestFlight and App Store). A Sandbox key is only needed for builds run from Xcode;
   with two keys, the server picks one by the token's stored environment."
3. **CLAUDE.md**, Apple admin, M3: replace "enable push on the production App ID config" with "if
   builds run from Xcode ever need pushes, add a Sandbox APNs key and give the server one key per
   environment".
4. **Server:** no change for M0. If a second key is ever added (M3 or later), the Worker gets a
   second pair of key secrets and `ApnsClient` is chosen per environment.

The owner's agreement is needed for the SPEC.md and CLAUDE.md edits.
