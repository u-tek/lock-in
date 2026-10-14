// The Lockin API (Cloudflare Worker).
//
//   GET    /health                 -> {"ok": true, "environment": "development"}
//   POST   /admin/push-test        sends a made-up squad to one Live Activity: the M0 APNs spike
//                                  (src/admin.ts). Development only, behind ADMIN_TOKEN (README.md).
//   M2, accounts and friends (docs/milestones/M2.md):
//   POST   /auth/apple             Sign in with Apple -> { token, user, isNew }   (src/accounts.ts)
//   GET    /me  PATCH /me  DELETE /me
//   GET    /handles/:handle
//   POST   /devices
//   GET    /friends  POST /friends/code  POST /friends/redeem/:code  DELETE /friends/:id   (src/friends.ts)
//   GET    /blocks  POST /blocks  DELETE /blocks/:userId
//   POST   /reports
//   GET    /j/:code                the invite landing page (src/invite.ts)
//   GET    /.well-known/apple-app-site-association
//
// Every M2 route but /auth/apple, /j/:code and /.well-known/* needs `Authorization: Bearer <token>`.
// M3 adds rooms (the `Room` Durable Object) and the push fan-out.
//
// The runtime treats every named export of this module as an entrypoint and refuses to start if
// one isn't a function or class, so constants and helpers live in the other modules.

import { deleteMe, getMe, handleAvailability, patchMe, registerDevice, signInWithApple } from "./accounts.ts";
import { pushTest } from "./admin.ts";
import { authenticate } from "./auth.ts";
import { type AuthedContext, type Context, type Dependencies, makeContext } from "./context.ts";
import { Database } from "./db.ts";
import type { Env } from "./env.ts";
import { blockUser, fileReport, friendCode, listBlocks, listFriends, redeemFriendCode, removeFriend, unblockUser } from "./friends.ts";
import { HttpError, errorResponse, json, notFound } from "./http.ts";
import { appSiteAssociation, invitePage } from "./invite.ts";

export { Room } from "./room.ts";
export type { Env } from "./env.ts";
export type { Dependencies } from "./context.ts";

interface Route {
  method: string;
  /** For logs: the pattern, never the path itself, which can hold a handle, a code or an id. */
  name: string;
  pattern: RegExp;
  run: (context: Context, params: string[]) => Promise<Response>;
}

/** A route anyone can call. `:name` matches one path segment. */
function open(method: string, path: string, run: Route["run"]): Route {
  const pattern = new RegExp(`^${path.replace(/:[a-zA-Z]+/g, "([^/]+)").replace(/\./g, "\\.")}$`);
  return { method, name: `${method} ${path}`, pattern, run };
}

/** A route behind the bearer token: 401 `unauthorised` without a valid one. */
function authed(method: string, path: string, run: (context: AuthedContext, params: string[]) => Promise<Response>): Route {
  return open(method, path, async (context, params) => run(await authenticate(context), params));
}

const ROUTES: Route[] = [
  open("GET", "/health", async ({ env }) => json({ ok: true, environment: env.ENVIRONMENT })),
  open("POST", "/admin/push-test", ({ request, env, deps }) => pushTest(request, env, deps)),

  open("POST", "/auth/apple", signInWithApple),
  authed("GET", "/me", getMe),
  authed("PATCH", "/me", patchMe),
  authed("DELETE", "/me", deleteMe),
  authed("GET", "/handles/:handle", (context, [handle = ""]) => handleAvailability(context, handle)),
  authed("POST", "/devices", registerDevice),

  authed("GET", "/friends", listFriends),
  authed("POST", "/friends/code", friendCode),
  authed("POST", "/friends/redeem/:code", (context, [code = ""]) => redeemFriendCode(context, code)),
  authed("DELETE", "/friends/:id", (context, [id = ""]) => removeFriend(context, id)),
  authed("GET", "/blocks", listBlocks),
  authed("POST", "/blocks", blockUser),
  authed("DELETE", "/blocks/:userId", (context, [userId = ""]) => unblockUser(context, userId)),
  authed("POST", "/reports", fileReport),

  open("GET", "/j/:code", (context, [code = ""]) => invitePage(context, code)),
  open("GET", "/.well-known/apple-app-site-association", async (context) => appSiteAssociation(context)),
];

export async function handle(request: Request, env: Env, deps: Dependencies = {}): Promise<Response> {
  const { pathname } = new URL(request.url);
  let route: Route | undefined;
  let params: string[] = [];
  for (const candidate of ROUTES) {
    if (candidate.method !== request.method) continue;
    const match = candidate.pattern.exec(pathname);
    if (match === null) continue;
    route = candidate;
    params = match.slice(1);
    break;
  }
  if (route === undefined) return notFound();

  try {
    return await route.run(makeContext(request, env, deps, new Database(env.DB)), params);
  } catch (error) {
    if (error instanceof HttpError) return errorResponse(error);
    // The route's pattern and the error's name only: a path or a message could quote a person.
    console.error(`${route.name}: unhandled ${error instanceof Error ? error.name : typeof error}`);
    return json({ error: "Something went wrong", code: "internal" }, 500);
  }
}

export default {
  fetch: (request, env) => handle(request, env),
} satisfies ExportedHandler<Env>;
