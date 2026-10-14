// Friends (docs/milestones/M2.md, SPEC.md §1.6): added by code, QR or link only, never by search.
//
//   GET    /friends                -> { friends: [Friend] }
//   POST   /friends/code           -> FriendCode (the current one, or a new one if it expired)
//   POST   /friends/redeem/:code   -> { friend: Friend }
//   DELETE /friends/:id            -> 204
//   GET    /blocks                 -> { blocked: [Friend] }
//   POST   /blocks                 { userId } -> 204 (also ends the friendship)
//   DELETE /blocks/:userId         -> 204
//   POST   /reports                { userId, reason, note? } -> 204
//
// Friendships are stored in both directions and always written or removed in pairs (src/db.ts).

import type { AuthedContext, Context } from "./context.ts";
import { FRIEND_CODE_ALPHABET, FRIEND_CODE_LENGTH, newFriendCode, newShortID } from "./context.ts";
import type { FriendRow, InviteCodeRow } from "./db.ts";
import { HttpError, apiError, json, noContent, readObject } from "./http.ts";
import { isShortID } from "./liveActivity.ts";

/** Another user, as the friends list and the blocked list show them. `since` is Unix seconds. */
export interface Friend {
  id: string;
  /** Null until they pick one in the handle picker. */
  handle: string | null;
  /** Null until they pick one. */
  displayName: string | null;
  avatarCode: string;
  since: number;
}

export interface FriendCode {
  code: string;
  /** `https://<invite host>/j/<code>`. */
  url: string;
  /** Unix seconds. */
  expiresAt: number;
}

/** Friend codes last a week. */
export const FRIEND_CODE_LIFETIME_SECONDS = 7 * 24 * 60 * 60;
/** Expired codes are kept this long, so an old link says "expired" rather than "not found". */
export const EXPIRED_CODE_RETENTION_SECONDS = 30 * 24 * 60 * 60;

export const REPORT_REASONS = ["name", "spam", "harassment", "other"] as const;
export const MAX_REPORT_NOTE_LENGTH = 500;

const FRIEND_CODE = new RegExp(`^[${FRIEND_CODE_ALPHABET}]{${FRIEND_CODE_LENGTH}}$`);

export function publicFriend(row: FriendRow): Friend {
  return { id: row.id, handle: row.handle, displayName: row.display_name, avatarCode: row.avatar_code, since: row.since };
}

/**
 * A code as typed or linked, in canonical form (uppercase), or undefined if it can't be one.
 * Matching ignores case, so `abcd2345` finds `ABCD2345`.
 */
export function canonicalFriendCode(raw: string): string | undefined {
  let decoded: string;
  try {
    decoded = decodeURIComponent(raw);
  } catch {
    return undefined;
  }
  const code = decoded.trim().toUpperCase();
  return FRIEND_CODE.test(code) ? code : undefined;
}

/** The host invite links point at: INVITE_HOST, or this Worker's own host until the domain exists. */
export function inviteHost(context: Context): string {
  const configured = (context.env.INVITE_HOST ?? "")
    .trim()
    .replace(/^https?:\/\//i, "")
    .replace(/\/+$/, "");
  return configured || context.url.host;
}

export function friendCodeView(context: Context, row: InviteCodeRow): FriendCode {
  return { code: row.code, url: `https://${inviteHost(context)}/j/${row.code}`, expiresAt: row.expires_at ?? 0 };
}

// GET /friends

export async function listFriends(context: AuthedContext): Promise<Response> {
  const friends = await context.db.friendsOf(context.user.id);
  return json({ friends: friends.map(publicFriend) });
}

// POST /friends/code

export async function friendCode(context: AuthedContext): Promise<Response> {
  const { db, user, now } = context;
  const current = await db.currentFriendCode(user.id, now);
  if (current !== null) return json(friendCodeView(context, current));

  const expiresAt = now + FRIEND_CODE_LIFETIME_SECONDS;
  // 32^8 codes: a collision is rare, five in a row means the random source is broken.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newFriendCode(context.random);
    if (await db.insertFriendCode(code, user.id, expiresAt, now - EXPIRED_CODE_RETENTION_SECONDS)) {
      return json(friendCodeView(context, { code, kind: "friend", target_id: user.id, created_by: user.id, expires_at: expiresAt }));
    }
  }
  throw new HttpError(500, "Couldn't make a friend code. Try again.");
}

// POST /friends/redeem/:code

export async function redeemFriendCode(context: AuthedContext, rawCode: string): Promise<Response> {
  const { db, user, now } = context;
  const notFound = () => apiError(404, "code_not_found", "That code doesn't exist. Check it and try again.");

  const code = canonicalFriendCode(rawCode);
  if (code === undefined) throw notFound();
  const invite = await db.inviteCode(code);
  if (invite === null || invite.kind !== "friend") throw notFound();
  if (invite.target_id === user.id) throw apiError(422, "own_code", "That's your own code. Share it with a friend instead.");
  if (invite.expires_at !== null && invite.expires_at <= now) {
    throw apiError(410, "code_expired", "That code has expired. Ask your friend for a new one.");
  }
  // No foreign key on target_id (migrations/0001_init.sql), so check they're still here.
  const target = await db.userById(invite.target_id);
  if (target === null) throw notFound();
  if (await db.isBlockedEitherWay(user.id, target.id)) throw apiError(403, "blocked", "You can't add this person.");
  if (await db.areFriends(user.id, target.id)) throw apiError(409, "already_friends", "You're already friends.");

  await db.befriend(user.id, target.id, now);
  console.log("friends: code redeemed");
  return json({
    friend: publicFriend({ id: target.id, handle: target.handle, display_name: target.display_name, avatar_code: target.avatar_code, since: now }),
  });
}

// DELETE /friends/:id

/** Ends the friendship both ways. Not friends (or no such user) is already the result: 204. */
export async function removeFriend(context: AuthedContext, friendId: string): Promise<Response> {
  if (isShortID(friendId)) await context.db.unfriend(context.user.id, friendId);
  return noContent();
}

// GET /blocks

export async function listBlocks(context: AuthedContext): Promise<Response> {
  const blocked = await context.db.blockedBy(context.user.id);
  return json({ blocked: blocked.map(publicFriend) });
}

// POST /blocks

export async function blockUser(context: AuthedContext): Promise<Response> {
  const body = await readObject(context.request);
  const userId = body.userId;
  const notFound = () => apiError(404, "user_not_found", "That person isn't on Lockin any more.");
  if (!isShortID(userId)) throw notFound();
  if (userId === context.user.id) throw new HttpError(400, "You can't block yourself");
  if ((await context.db.userById(userId)) === null) throw notFound();
  await context.db.block(context.user.id, userId, context.now);
  console.log("blocks: blocked someone");
  return noContent();
}

// DELETE /blocks/:userId

/** Unblocks. The friendship the block ended doesn't come back: that takes a new code. */
export async function unblockUser(context: AuthedContext, userId: string): Promise<Response> {
  if (isShortID(userId)) await context.db.unblock(context.user.id, userId);
  return noContent();
}

// POST /reports

/**
 * Files a report for moderation (SPEC.md §7). Anything malformed, an unknown reason, a note over
 * 500 characters, yourself or someone who doesn't exist is 422 `report_invalid`.
 */
export async function fileReport(context: AuthedContext): Promise<Response> {
  const body = await readObject(context.request);
  const invalid = (what: string) => apiError(422, "report_invalid", what);

  const { userId, reason } = body;
  if (!isShortID(userId) || userId === context.user.id) throw invalid("userId must be another person's id");
  if (typeof reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(reason)) {
    throw invalid(`reason must be one of ${REPORT_REASONS.join(", ")}`);
  }
  let note: string | null = null;
  if (body.note !== undefined && body.note !== null) {
    if (typeof body.note !== "string") throw invalid("note must be text");
    const trimmed = body.note.trim();
    if ([...trimmed].length > MAX_REPORT_NOTE_LENGTH) throw invalid(`note must be at most ${MAX_REPORT_NOTE_LENGTH} characters`);
    note = trimmed.length > 0 ? trimmed : null;
  }
  if ((await context.db.userById(userId)) === null) throw invalid("That person isn't on Lockin any more");

  await context.db.insertReport({ id: newShortID(context.random), reporterId: context.user.id, targetUserId: userId, reason, note, now: context.now });
  // The reason is one of four words; nothing about who.
  console.log(`reports: new report (${reason})`);
  return noContent();
}
