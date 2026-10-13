// The Worker's bindings, as wrangler.toml declares them. Secrets are optional here because a fresh
// deployment runs without them until `wrangler secret put`; the routes that need them say so.

export interface Env {
  /** D1: the schema in migrations/. Unused until M2. */
  DB: D1Database;
  /** One `Room` Durable Object per live session. Stubbed until M3. */
  ROOMS: DurableObjectNamespace;

  /** The app's bundle ID (LK_BUNDLE_ID). The APNs topic is `<this>.push-type.liveactivity`. */
  APNS_BUNDLE_ID: string;
  /** "development" or "production". Production turns off the /admin routes. */
  ENVIRONMENT: string;

  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  /** The contents of the .p8 file. */
  APNS_PRIVATE_KEY?: string;
  /** 32+ random characters. Unset or shorter, and /admin/push-test doesn't exist. */
  ADMIN_TOKEN?: string;
}
