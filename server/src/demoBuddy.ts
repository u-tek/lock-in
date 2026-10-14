// Demo Buddy (docs/launch/app-review-notes.md §3, SPEC.md §7): a clearly labelled server bot that
// joins App Review's squad sessions, so the social Live Activity can be seen with one phone.
//
// It's a `users` row (migrations/0006_demo_buddy.sql, `is_bot = 1`) that never signs in. It lives
// only in Review Squads, made by redeeming the review code (src/reviewSquad.ts). In a Review
// Squad's room (src/room.ts) it joins a few seconds after a person opens or joins the room, runs a
// 3-minute timer and a fixed script on the room's alarm, and leaves when nobody else is running.
//
// This module is the constants and the switch only, so the room can import it without the routes.

import type { Env } from "./env.ts";
import { canonicalFriendCode } from "./friends.ts";
import type { RoomProfile } from "./room.ts";

/** Its user id (10 base62 characters, like every id). Also in migrations/0006_demo_buddy.sql. */
export const DEMO_BUDDY_ID = "DemoBuddy0";
export const DEMO_BUDDY_HANDLE = "demobuddy";
/** 10 characters: within the Live Activity's 12. */
export const DEMO_BUDDY_NAME = "Demo Buddy";
/** Its own Lockling: tall, orange, winking, in a cap. */
export const DEMO_BUDDY_AVATAR = "b2.c5.e4.h3";
export const DEMO_BUDDY_PROFILE: Readonly<RoomProfile> = { name: DEMO_BUDDY_NAME, avatar: DEMO_BUDDY_AVATAR };

/** What a redemption calls the squad it makes. */
export const REVIEW_SQUAD_NAME = "Review Squad";

/** Its timer: 3 minutes, plus the 30-second pause in its script. */
export const DEMO_BUDDY_MINUTES = 3;
/** It joins this long after a person opens or joins the room (5–10 s in the review notes). */
export const DEMO_BUDDY_JOIN_DELAY_SECONDS = 6;
/** The script, timed from when its timer started. */
export const DEMO_BUDDY_CHEER_AFTER_SECONDS = 60;
export const DEMO_BUDDY_PAUSE_AFTER_SECONDS = 90;
export const DEMO_BUDDY_RESUME_AFTER_SECONDS = 120;
/** The cheer it sends: the app's first emoji. */
export const DEMO_BUDDY_CHEER_KIND = 0;

/** The review code works this many times in any hour, for everyone together. */
export const REVIEW_REDEMPTIONS_PER_WINDOW = 10;
export const REVIEW_REDEMPTION_WINDOW_SECONDS = 60 * 60;
/** The redemption log keeps a day. */
export const REVIEW_REDEMPTION_KEPT_SECONDS = 24 * 60 * 60;

export function isDemoBuddy(userId: string): boolean {
  return userId === DEMO_BUDDY_ID;
}

/** The kill switch: Demo Buddy works only while DEMO_BUDDY_ENABLED is "true" (or "1", "yes", "on"). */
export function demoBuddyEnabled(env: Pick<Env, "DEMO_BUDDY_ENABLED">): boolean {
  return ["true", "1", "yes", "on"].includes((env.DEMO_BUDDY_ENABLED ?? "").trim().toLowerCase());
}

let warnedAboutCode = false;

/**
 * The review code, canonical (as `canonicalFriendCode` makes a typed code), while Demo Buddy is on
 * and the code is one the app can type: undefined otherwise. A malformed code is logged once.
 */
export function reviewCode(env: Pick<Env, "DEMO_BUDDY_ENABLED" | "DEMO_BUDDY_CODE">): string | undefined {
  if (!demoBuddyEnabled(env)) return undefined;
  const raw = env.DEMO_BUDDY_CODE?.trim() ?? "";
  const code = raw.length === 0 ? undefined : canonicalFriendCode(raw);
  if (code === undefined && !warnedAboutCode) {
    warnedAboutCode = true;
    console.warn("demo buddy: DEMO_BUDDY_CODE isn't 8 characters of ABCDEFGHJKLMNPQRSTUVWXYZ23456789, so the review code is off");
  }
  return code;
}

/** Whether `rawCode` (as typed or linked) is the review code, with Demo Buddy on. */
export function isReviewCode(env: Pick<Env, "DEMO_BUDDY_ENABLED" | "DEMO_BUDDY_CODE">, rawCode: string): boolean {
  const code = reviewCode(env);
  return code !== undefined && canonicalFriendCode(rawCode) === code;
}
