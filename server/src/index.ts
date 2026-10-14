// The Lockin API (Cloudflare Worker).
//
//   GET    /health                 -> {"ok": true, "environment": "development"}
//   POST   /admin/push-test        sends a made-up squad to one Live Activity: the M0 APNs spike
//                                  (src/admin.ts). Development only, behind ADMIN_TOKEN (README.md).
//   POST   /admin/push-to-start-test   starts that squad's Live Activity by push: the M4 spike. Ditto.
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
//   M3, squad sessions (docs/milestones/M3.md):
//   DELETE /auth/session           signs this token out                          (src/accounts.ts)
//   GET    /squads  POST /squads  PATCH /squads/:id  POST /squads/:id/invite      (src/squads.ts)
//   POST   /squads/join/:code  PATCH /squads/:id/members/me  DELETE /squads/:id/members/me
//   POST   /sessions  POST /sessions/:id/join  POST /sessions/:id/la-token       (src/sessions.ts)
//   POST   /sessions/:id/pause|resume|end|slip  POST /sessions/:id/cheer
//   GET    /sessions/:id  GET /sessions/:id/live (WebSocket)
//   M4, invites and joining (docs/milestones/M4.md): POST /devices takes quiet hours; opening a
//   squad's room alerts the squad after the response (src/alerts.ts, through `ctx.waitUntil`); joins
//   take a push-to-start token (src/pushToStart.ts).
//   M5, pet, streaks, leaderboard, cosmetics (docs/milestones/M5.md): GET /squads gains the pet, the
//   streak and the zone; the rooms credit coins and XP (src/room.ts).
//   GET    /squads/:id/leaderboard                                               (src/squads.ts)
//   GET    /shop  POST /shop/buy  GET /me/cosmetics                              (src/shop.ts)
//   POST   /me/coins/import                                                      (src/accounts.ts)
//
// Every route but /health, /admin/*, /auth/apple, /shop, /j/:code and /.well-known/* needs
// `Authorization: Bearer <token>`. Each session is a `Room` Durable Object (src/room.ts); the APNs
// provider token comes from the one `ApnsAuth` Durable Object (src/apnsAuth.ts).
//
// The runtime treats every named export of this module as an entrypoint and refuses to start if
// one isn't a function or class, so constants and helpers live in the other modules.

import { deleteMe, getMe, handleAvailability, importCoins, patchMe, registerDevice, signInWithApple, signOut } from "./accounts.ts";
import { pushTest, pushToStartTest } from "./admin.ts";
import { authenticate } from "./auth.ts";
import { type AuthedContext, type Context, type Dependencies, makeContext } from "./context.ts";
import { Database } from "./db.ts";
import type { Env } from "./env.ts";
import { blockUser, fileReport, friendCode, listBlocks, listFriends, redeemFriendCode, removeFriend, unblockUser } from "./friends.ts";
import { HttpError, errorResponse, json, notFound } from "./http.ts";
import { appSiteAssociation, invitePage } from "./invite.ts";
import { cheer, getSession, joinSession, liveSession, memberAction, startSession, uploadLiveActivityToken } from "./sessions.ts";
import { buyItem, getShop, myCosmetics } from "./shop.ts";
import { createSquad, joinSquadByCode, leaveSquad, listSquads, renameSquad, squadInvite, squadLeaderboard, updateMyMembership } from "./squads.ts";

export { ApnsAuth } from "./apnsAuth.ts";
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
  open("POST", "/admin/push-to-start-test", ({ request, env, deps, db }) => pushToStartTest(request, env, deps, db)),

  open("POST", "/auth/apple", signInWithApple),
  authed("DELETE", "/auth/session", signOut),
  authed("GET", "/me", getMe),
  authed("PATCH", "/me", patchMe),
  authed("DELETE", "/me", deleteMe),
  authed("GET", "/handles/:handle", (context, [handle = ""]) => handleAvailability(context, handle)),
  authed("POST", "/devices", registerDevice),
  authed("GET", "/me/cosmetics", myCosmetics),
  authed("POST", "/me/coins/import", importCoins),

  authed("GET", "/friends", listFriends),
  authed("POST", "/friends/code", friendCode),
  authed("POST", "/friends/redeem/:code", (context, [code = ""]) => redeemFriendCode(context, code)),
  authed("DELETE", "/friends/:id", (context, [id = ""]) => removeFriend(context, id)),
  authed("GET", "/blocks", listBlocks),
  authed("POST", "/blocks", blockUser),
  authed("DELETE", "/blocks/:userId", (context, [userId = ""]) => unblockUser(context, userId)),
  authed("POST", "/reports", fileReport),

  authed("GET", "/squads", listSquads),
  authed("POST", "/squads", createSquad),
  authed("POST", "/squads/join/:code", (context, [code = ""]) => joinSquadByCode(context, code)),
  authed("PATCH", "/squads/:id", (context, [id = ""]) => renameSquad(context, id)),
  authed("POST", "/squads/:id/invite", (context, [id = ""]) => squadInvite(context, id)),
  authed("PATCH", "/squads/:id/members/me", (context, [id = ""]) => updateMyMembership(context, id)),
  authed("DELETE", "/squads/:id/members/me", (context, [id = ""]) => leaveSquad(context, id)),
  authed("GET", "/squads/:id/leaderboard", (context, [id = ""]) => squadLeaderboard(context, id)),

  // The catalogue is the same for everyone, and the app shows it signed out too.
  open("GET", "/shop", getShop),
  authed("POST", "/shop/buy", buyItem),

  authed("POST", "/sessions", startSession),
  authed("POST", "/sessions/:id/join", (context, [id = ""]) => joinSession(context, id)),
  authed("POST", "/sessions/:id/la-token", (context, [id = ""]) => uploadLiveActivityToken(context, id)),
  ...(["pause", "resume", "end", "slip"] as const).map((action) =>
    authed("POST", `/sessions/:id/${action}`, (context, [id = ""]) => memberAction(action)(context, id)),
  ),
  authed("POST", "/sessions/:id/cheer", (context, [id = ""]) => cheer(context, id)),
  authed("GET", "/sessions/:id", (context, [id = ""]) => getSession(context, id)),
  authed("GET", "/sessions/:id/live", (context, [id = ""]) => liveSession(context, id)),

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
  // The runtime's waitUntil keeps the Worker going for work after the response (M4's alerts).
  fetch: (request, env, ctx) => handle(request, env, { waitUntil: (promise) => ctx.waitUntil(promise) }),
} satisfies ExportedHandler<Env>;
