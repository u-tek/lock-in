// The Worker's bindings, as wrangler.toml declares them. Secrets are optional here because a fresh
// deployment runs without them until `wrangler secret put`; the routes that need them say so.

export interface Env {
  /** D1: the schema in migrations/. Accounts and friends from M2. */
  DB: D1Database;
  /** One `Room` Durable Object per session (src/room.ts), named by the session id. */
  ROOMS: DurableObjectNamespace;
  /**
   * The one `ApnsAuth` Durable Object (src/apnsAuth.ts), named "global": it signs the APNs provider
   * token every room presents, so they all present the same one (docs/decisions/0004).
   */
  APNS_AUTH: DurableObjectNamespace;

  /**
   * The app's bundle ID (LK_BUNDLE_ID). The APNs topic is `<this>.push-type.liveactivity`, it's the
   * audience of Sign in with Apple identity tokens, and universal links name `<team id>.<this>`.
   */
  APNS_BUNDLE_ID: string;
  /** "development" or "production". Production turns off the /admin routes. */
  ENVIRONMENT: string;
  /**
   * The host invite links use, e.g. "lockin.app" (`https://<this>/j/<code>`). Unset, links use the
   * Worker's own host, which serves the landing page too.
   */
  INVITE_HOST?: string;

  /** The Apple Developer team ID: APNs, the Sign in with Apple client secret and universal links. */
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  /** The contents of the .p8 file. */
  APNS_PRIVATE_KEY?: string;
  /** 32+ random characters. Unset or shorter, and /admin/push-test doesn't exist. */
  ADMIN_TOKEN?: string;

  /**
   * The Sign in with Apple key's 10-character ID. With SIWA_PRIVATE_KEY, sign-in swaps Apple's
   * authorisation code for a refresh token, which account deletion revokes. Without them, sign-in
   * still works but nothing is revoked.
   */
  SIWA_KEY_ID?: string;
  /** The contents of the Sign in with Apple key's .p8 file. */
  SIWA_PRIVATE_KEY?: string;
}
