// The Lockin API (Cloudflare Worker).
//
//   GET  /health            -> {"ok": true, "environment": "development"}
//   POST /admin/push-test   sends a made-up squad to one Live Activity: the M0 APNs spike
//                           (src/admin.ts). Development only, behind ADMIN_TOKEN (README.md).
//
// M2 adds accounts and friends (D1); M3 adds rooms (the `Room` Durable Object) and the push fan-out.
//
// The runtime treats every named export of this module as an entrypoint and refuses to start if
// one isn't a function or class, so constants and helpers live in the other modules.

import { pushTest } from "./admin.ts";
import type { ApnsDependencies } from "./apns.ts";
import type { Env } from "./env.ts";
import { HttpError, json, notFound } from "./http.ts";

export { Room } from "./room.ts";
export type { Env } from "./env.ts";

/** Injected by tests; the Worker uses the real `fetch` and clock. */
export type Dependencies = ApnsDependencies;

export async function handle(request: Request, env: Env, deps: Dependencies = {}): Promise<Response> {
  const { pathname } = new URL(request.url);
  try {
    if (pathname === "/health" && request.method === "GET") {
      return json({ ok: true, environment: env.ENVIRONMENT });
    }
    if (pathname === "/admin/push-test" && request.method === "POST") {
      return await pushTest(request, env, deps);
    }
    return notFound();
  } catch (error) {
    if (error instanceof HttpError) return json({ error: error.message }, error.status);
    // The name only: a message could quote a request.
    console.error(`${pathname}: unhandled ${error instanceof Error ? error.name : typeof error}`);
    return json({ error: "Something went wrong" }, 500);
  }
}

export default {
  fetch: (request, env) => handle(request, env),
} satisfies ExportedHandler<Env>;
