// Review Squads and Demo Buddy's routes (docs/launch/app-review-notes.md §3, SPEC.md §7).
//
//   POST /squads/join/<review code>            -> { squad }: a fresh private "Review Squad" with Demo Buddy
//   POST /squads/:id/demo-buddy/lock-in        -> { session }: Demo Buddy locks in, and the squad hears
//
// The review code is a Worker variable (DEMO_BUDDY_CODE), not an `invite_codes` row: it never
// expires and is changed for each submission. It works while DEMO_BUDDY_ENABLED is on (the kill
// switch), at most REVIEW_REDEMPTIONS_PER_WINDOW times an hour for everyone together; switched off,
// it's an unknown code like any other (404). Each redemption makes a new squad, so two reviewers
// never share one, and a Review Squad doesn't count against the redeemer's squad limit: App Review
// never meets a paywall on the way to the social Live Activity.
//
// Demo Buddy never joins any other squad: it has no session token, so no route can act as it, and
// these routes only ever put it in a squad they make or find it in. Its part in the rooms is
// src/room.ts.

import { sendLockinAlerts } from "./alerts.ts";
import type { AuthedContext } from "./context.ts";
import { newShortID } from "./context.ts";
import { isUniqueViolation } from "./db.ts";
import {
  DEMO_BUDDY_ID,
  DEMO_BUDDY_MINUTES,
  DEMO_BUDDY_NAME,
  DEMO_BUDDY_PROFILE,
  REVIEW_REDEMPTIONS_PER_WINDOW,
  REVIEW_REDEMPTION_KEPT_SECONDS,
  REVIEW_REDEMPTION_WINDOW_SECONDS,
  REVIEW_SQUAD_NAME,
  demoBuddyEnabled,
} from "./demoBuddy.ts";
import { HttpError, apiError, json } from "./http.ts";
import { isShortID } from "./liveActivity.ts";
import { pickSpecies } from "./pet.ts";
import type { Joined, SessionView } from "./room.ts";
import { callRoom, errorCode } from "./sessions.ts";
import { loadSquad, notMember } from "./squads.ts";

// POST /squads/join/<review code>

/**
 * Makes a Review Squad: the redeemer (its owner) and Demo Buddy, private like any squad. Its zone is
 * the redeemer's latest phone's, else UTC. 403 `blocked` if the redeemer blocked Demo Buddy; 429
 * `rate_limited` with `retryAfter` (seconds) over the hourly limit.
 */
export async function redeemReviewCode(context: AuthedContext): Promise<Response> {
  const { db, user, now } = context;
  if (await db.isBlockedEitherWay(user.id, DEMO_BUDDY_ID)) throw apiError(403, "blocked", "You can't join this squad.");
  const since = now - REVIEW_REDEMPTION_WINDOW_SECONDS;
  if (!(await db.reserveReviewRedemption(now, since, REVIEW_REDEMPTIONS_PER_WINDOW, now - REVIEW_REDEMPTION_KEPT_SECONDS))) {
    const oldest = (await db.oldestReviewRedemption(since)) ?? now;
    const retryAfter = Math.max(1, oldest + REVIEW_REDEMPTION_WINDOW_SECONDS - now);
    console.log("squads: review code over its hourly limit");
    throw apiError(429, "rate_limited", "That code has been used a lot just now. Try again in a few minutes.", { retryAfter });
  }

  const tz = (await db.latestDeviceZone(user.id)) ?? "UTC";
  const species = pickSpecies(context.random);
  // A fresh id collides with an existing one about never; the retry is for that.
  for (let attempt = 0; attempt < 3; attempt++) {
    const id = newShortID(context.random);
    try {
      await db.insertReviewSquad({ id, name: REVIEW_SQUAD_NAME, ownerId: user.id, botId: DEMO_BUDDY_ID, now, species, tz });
    } catch (error) {
      if (isUniqueViolation(error, "squads.id")) continue;
      throw error;
    }
    console.log("squads: review squad made");
    return json({ squad: await loadSquad(context, id) });
  }
  throw new HttpError(500, "Couldn't make the squad. Try again.");
}

// POST /squads/:id/demo-buddy/lock-in

/**
 * "Ask Demo Buddy to lock in": with the squad's room open, Demo Buddy joins it (unless it's running
 * there already); otherwise it opens one with a 3-minute timer and the squad gets the usual
 * "Demo Buddy is locking in" alert after the response, with Join actions. The alert respects mute,
 * blocks, busy members and every limit, but not quiet hours: the reviewer asked for it.
 *
 * 403 `not_member` outside the squad; 404 `not_found` for a squad without Demo Buddy, or with Demo
 * Buddy switched off.
 */
export async function askDemoBuddy(context: AuthedContext, squadId: string): Promise<Response> {
  const { db, user, env } = context;
  const row = isShortID(squadId) ? await db.mySquad(squadId, user.id) : null;
  if (row === null) throw notMember();
  if (!demoBuddyEnabled(env) || row.review !== 1 || !(await db.isSquadMember(squadId, DEMO_BUDDY_ID))) {
    throw apiError(404, "not_found", "Demo Buddy isn't in this squad");
  }

  // Join the open room, or open one. Each lost race (the room ended as we joined, or someone else
  // opened one as we did) goes round again, as for POST /sessions.
  for (let attempt = 0; attempt < 3; attempt++) {
    const open = await db.openSessionOfSquad(squadId);
    if (open !== null) {
      const joined = await callRoom(env, open.id, DEMO_BUDDY_ID, "buddy", {});
      if ((await errorCode(joined)) !== "session_ended") return joined;
    }
    const sessionId = newShortID(context.random);
    const opened = await callRoom(env, sessionId, DEMO_BUDDY_ID, "open", { squadId, minutes: DEMO_BUDDY_MINUTES, profile: DEMO_BUDDY_PROFILE });
    if ((await errorCode(opened)) === "room_exists") continue;
    if (!opened.ok) return opened;
    context.waitUntil(sendLockinAlerts(context, { squadId, sessionId, openerId: DEMO_BUDDY_ID, openerName: DEMO_BUDDY_NAME, ignoreQuietHours: true }));
    console.log(`room ${sessionId}: Demo Buddy locked in on request`);
    const session: SessionView = ((await opened.json()) as Joined).session;
    return json({ session });
  }
  throw apiError(503, "try_again", "Couldn't start the session. Try again.");
}
