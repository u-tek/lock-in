// The Worker's own APNs client (M4): "X is locking in" alerts (src/alerts.ts) and push-to-start
// (src/pushToStart.ts) go out from the route that caused them, not from a room.
//
// Like the rooms, it presents the one provider token the `ApnsAuth` Durable Object hands out
// (docs/decisions/0004): Cloudflare may carry the Worker's and the rooms' requests on one
// connection to APNs, which answers 429 TooManyProviderTokenUpdates if it sees a new token more
// than once in 20 minutes.
//
// Without the APNs secrets nothing is sent: the routes work as before, and the isolate says so once.

import { ApnsClient } from "./apns.ts";
import { SharedProviderToken } from "./apnsAuth.ts";
import type { Dependencies } from "./context.ts";
import type { Env } from "./env.ts";

// One client per isolate and APNS_AUTH binding, so its provider token is reused between requests.
// Keyed by the binding (each test app has its own) and checked against the bundle ID, fetch and
// clock it was made with.
const clients = new WeakMap<object, { bundleId: string; fetch: Dependencies["fetch"]; now: Dependencies["now"]; client: ApnsClient }>();
let warned = false;

/** What's missing for the Worker to send pushes: secrets, the bundle ID or the ApnsAuth binding. */
function missingApnsSettings(env: Env): string[] {
  return [
    env.APNS_BUNDLE_ID?.trim() ? undefined : "APNS_BUNDLE_ID",
    env.APNS_TEAM_ID?.trim() ? undefined : "APNS_TEAM_ID",
    env.APNS_KEY_ID?.trim() ? undefined : "APNS_KEY_ID",
    env.APNS_PRIVATE_KEY?.trim() ? undefined : "APNS_PRIVATE_KEY",
    env.APNS_AUTH === undefined ? "the APNS_AUTH binding" : undefined,
  ].filter((name) => name !== undefined);
}

/** The client, or null (logged once per isolate) when APNs isn't set up. */
export function workerApns(env: Env, deps: Dependencies): ApnsClient | null {
  const missing = missingApnsSettings(env);
  if (missing.length > 0) {
    if (!warned) {
      warned = true;
      console.warn(`push: APNs isn't set up (${missing.join(", ")} missing), so squad alerts and push-to-start are off (server/README.md)`);
    }
    return null;
  }
  const bundleId = (env.APNS_BUNDLE_ID ?? "").trim();
  const cached = clients.get(env.APNS_AUTH);
  if (cached !== undefined && cached.bundleId === bundleId && cached.fetch === deps.fetch && cached.now === deps.now) return cached.client;

  const now = deps.now ?? (() => Date.now() / 1000);
  const client = new ApnsClient({ bundleId, tokens: new SharedProviderToken(env.APNS_AUTH, now) }, { fetch: deps.fetch, now });
  clients.set(env.APNS_AUTH, { bundleId, fetch: deps.fetch, now: deps.now, client });
  return client;
}
