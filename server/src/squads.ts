// Squads (docs/milestones/M3.md, SPEC.md §1.6, §2): 2–4 people free, up to 6 with Plus; one squad
// free, three with Plus. Joined by code, QR or link only, like friends.
//
//   GET    /squads                     -> { squads: [Squad] }
//   POST   /squads                     { name } -> { squad }
//   PATCH  /squads/:id                 { name } -> { squad }   (the owner only)
//   POST   /squads/:id/invite          -> FriendCode (a squad code: the current one, or a new one if it expired)
//   POST   /squads/join/:code          -> { squad }
//   PATCH  /squads/:id/members/me      { muted } -> { squad }
//   DELETE /squads/:id/members/me      -> 204 (an owner leaving hands the squad on; the last one out deletes it)
//   GET    /squads/:id/leaderboard?week=YYYY-MM-DD -> the week's minutes per member (M5)
//
// A squad you're not in looks the same as one that doesn't exist: 403 `not_member`.
//
// M5: every squad has a pet (an egg until two members finish together), a streak and a time zone
// (src/progress.ts). The egg's species is picked when the squad is made, and its zone is the
// creator's.

import type { AuthedContext } from "./context.ts";
import { newFriendCode, newShortID } from "./context.ts";
import type { LeaderboardRow, MySquadRow, SquadMemberRow, UserRow } from "./db.ts";
import { isUniqueViolation } from "./db.ts";
import { addDays, isDay, isTimeZoneName, localDay, mondayOf, startOfDay } from "./days.ts";
import { EXPIRED_CODE_RETENTION_SECONDS, FRIEND_CODE_LIFETIME_SECONDS, canonicalFriendCode, friendCodeView } from "./friends.ts";
import { HttpError, apiError, json, noContent, readObject } from "./http.ts";
import { MAX_SQUAD_NAME_LENGTH, isShortID } from "./liveActivity.ts";
import { moderate, normaliseName } from "./moderation.ts";
import { pickSpecies } from "./pet.ts";
import { type SquadProgress, type SquadStreak, squadProgress } from "./progress.ts";
import { FALLBACK_MEMBER_NAME } from "./sessions.ts";

export const FREE_SQUAD_LIMIT = 1;
export const PLUS_SQUAD_LIMIT = 3;
export const FREE_MEMBER_LIMIT = 4;
export const PLUS_MEMBER_LIMIT = 6;

export interface SquadMember {
  id: string;
  handle: string | null;
  displayName: string | null;
  avatarCode: string;
  /** Unix seconds. */
  joinedAt: number;
}

export interface Squad {
  id: string;
  name: string;
  /** Null only for a moment while an owner's account is deleted. */
  ownerId: string | null;
  /** Longest-standing first. */
  members: SquadMember[];
  /** The squad's room while someone's locked in: POST /sessions with this squad joins it. */
  openSessionId: string | null;
  /** Your own mute switch for "X is locking in" (M4). */
  muted: boolean;
  /** The egg is tinted by its `species` (stage 0) before it hatches. Mood 0–3; progress towards the next stage, 0–1. */
  pet: { species: string; stage: number; xp: number; mood: number; progress: number };
  streak: SquadStreak;
  /** The IANA zone the squad's days and Monday follow. */
  tz: string;
}

/** A member's week (GET /squads/:id/leaderboard). */
export interface LeaderboardEntry {
  userId: string;
  /** Whole focused minutes from every timer that stopped in the week: finished, left early or slipped. */
  minutes: number;
  /** Sessions finished in the week. */
  sessions: number;
}

/** Lockin Plus is active (SPEC.md §2). Set by M7's purchases; nothing sets it before then. */
export function hasPlus(user: Pick<UserRow, "plus_until">, now: number): boolean {
  return user.plus_until !== null && user.plus_until > now;
}

/** How many squads the user may be in. */
export function squadLimit(user: Pick<UserRow, "plus_until">, now: number): number {
  return hasPlus(user, now) ? PLUS_SQUAD_LIMIT : FREE_SQUAD_LIMIT;
}

/** How many members a squad may have with this joiner: 6 if the owner or the joiner has Plus. */
export function memberLimit(owner: Pick<UserRow, "plus_until"> | null, joiner: Pick<UserRow, "plus_until">, now: number): number {
  return (owner !== null && hasPlus(owner, now)) || hasPlus(joiner, now) ? PLUS_MEMBER_LIMIT : FREE_MEMBER_LIMIT;
}

function squadView(row: MySquadRow, members: SquadMemberRow[], openSessionId: string | null, progress: SquadProgress): Squad {
  return {
    id: row.id,
    name: row.name,
    ownerId: row.owner_id,
    members: members.map((member) => ({
      id: member.id,
      handle: member.handle,
      displayName: member.display_name,
      avatarCode: member.avatar_code,
      joinedAt: member.joined_at,
    })),
    openSessionId,
    muted: row.muted === 1,
    pet: {
      species: progress.species,
      stage: progress.stage,
      xp: progress.xp,
      mood: progress.mood,
      progress: progress.progress,
    },
    streak: progress.streak,
    tz: progress.tz,
  };
}

/** One squad as the caller sees it, or 403 `not_member`. */
async function loadSquad(context: AuthedContext, squadId: string): Promise<Squad> {
  const row = isShortID(squadId) ? await context.db.mySquad(squadId, context.user.id) : null;
  if (row === null) throw notMember();
  const [members, open, progress] = await Promise.all([
    context.db.membersOfSquad(squadId),
    context.db.openSessionOfSquad(squadId),
    squadProgress(context.db, row, context.now, context.random),
  ]);
  return squadView(row, members, open?.id ?? null, progress);
}

function notMember(): HttpError {
  return apiError(403, "not_member", "You're not in this squad");
}

function plusRequired(limit: "squads" | "members"): HttpError {
  const message = limit === "squads" ? "Lockin Plus lets you be in up to 3 squads" : "This squad is full. Lockin Plus squads hold up to 6.";
  return apiError(402, "plus_required", message, { limit });
}

/** A squad name: the display-name rules (fixtures/moderation/README.md), up to 20 code points. */
function squadName(value: unknown): string {
  const invalid = () => apiError(422, "name_invalid", `Squad names are 1–${MAX_SQUAD_NAME_LENGTH} characters`);
  if (typeof value !== "string") throw invalid();
  const verdict = moderate("name", value, { maxNameLength: MAX_SQUAD_NAME_LENGTH });
  if (verdict === "invalid") throw invalid();
  if (verdict === "not_allowed") throw apiError(422, "name_not_allowed", "That name isn't allowed. Try another.");
  return normaliseName(value);
}

// GET /squads

export async function listSquads(context: AuthedContext): Promise<Response> {
  const { db, user } = context;
  const [rows, members, open] = await Promise.all([db.squadsOf(user.id), db.membersOfSquadsOf(user.id), db.openSessionsOfSquadsOf(user.id)]);
  const progress = await Promise.all(rows.map((row) => squadProgress(db, row, context.now, context.random)));
  const squads = rows.map((row, index) =>
    squadView(
      row,
      members.filter((member) => member.squad_id === row.id),
      open.get(row.id) ?? null,
      progress[index] as SquadProgress,
    ),
  );
  return json({ squads });
}

// POST /squads

/**
 * `{ name, tz? }`. The squad's zone (M5) is `tz` if the app sends it, else that of the creator's most
 * recently registered phone, else UTC. The egg's species is picked now, so it has its colour.
 */
export async function createSquad(context: AuthedContext): Promise<Response> {
  const { db, user, now } = context;
  const body = await readObject(context.request);
  const name = squadName(body.name);
  if (body.tz !== undefined && body.tz !== null && !isTimeZoneName(body.tz)) {
    throw apiError(422, "tz_invalid", "tz must be an IANA time zone name like Australia/Sydney");
  }
  const tz = isTimeZoneName(body.tz) ? body.tz : ((await db.latestDeviceZone(user.id)) ?? "UTC");
  const species = pickSpecies(context.random);
  const maxSquads = squadLimit(user, now);
  // A fresh id collides with an existing one about never; the retry is for that.
  for (let attempt = 0; attempt < 3; attempt++) {
    const id = newShortID(context.random);
    try {
      if (!(await db.insertSquad({ id, name, ownerId: user.id, now, maxSquads, species, tz }))) throw plusRequired("squads");
    } catch (error) {
      if (isUniqueViolation(error, "squads.id")) continue;
      throw error;
    }
    console.log("squads: created");
    return json({ squad: await loadSquad(context, id) });
  }
  throw new HttpError(500, "Couldn't create the squad. Try again.");
}

// PATCH /squads/:id

export async function renameSquad(context: AuthedContext, squadId: string): Promise<Response> {
  const body = await readObject(context.request);
  const squad = await loadSquad(context, squadId);
  if (squad.ownerId !== context.user.id) throw apiError(403, "not_owner", "Only the squad's owner can rename it");
  await context.db.renameSquad(squadId, squadName(body.name));
  return json({ squad: await loadSquad(context, squadId) });
}

// POST /squads/:id/invite

/** The caller's code for this squad: the current one, or a new one once it expires (7 days, like friend codes). */
export async function squadInvite(context: AuthedContext, squadId: string): Promise<Response> {
  const { db, user, now } = context;
  await loadSquad(context, squadId);
  const current = await db.currentSquadCode(squadId, user.id, now);
  if (current !== null) return json(friendCodeView(context, current));

  const expiresAt = now + FRIEND_CODE_LIFETIME_SECONDS;
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newFriendCode(context.random);
    if (await db.insertSquadCode(code, squadId, user.id, expiresAt, now - EXPIRED_CODE_RETENTION_SECONDS)) {
      return json(friendCodeView(context, { code, kind: "squad", target_id: squadId, created_by: user.id, expires_at: expiresAt }));
    }
  }
  throw new HttpError(500, "Couldn't make a squad code. Try again.");
}

// POST /squads/join/:code

export async function joinSquadByCode(context: AuthedContext, rawCode: string): Promise<Response> {
  const { db, user, now } = context;
  const notFound = () => apiError(404, "code_not_found", "That code doesn't exist. Check it and try again.");

  const code = canonicalFriendCode(rawCode);
  if (code === undefined) throw notFound();
  const invite = await db.inviteCode(code);
  if (invite === null) throw notFound();
  if (invite.kind === "friend") throw apiError(422, "friend_code", "That's a friend code. Add your friend on the Friends screen.");
  if (invite.expires_at !== null && invite.expires_at <= now) {
    throw apiError(410, "code_expired", "That code has expired. Ask for a new one.");
  }
  // No foreign key on target_id (migrations/0001_init.sql), so check the squad is still here.
  const squad = await db.squadById(invite.target_id);
  if (squad === null) throw notFound();
  if (await db.isSquadMember(squad.id, user.id)) throw apiError(409, "already_member", "You're already in this squad.");
  if (await db.isBlockedWithinSquad(user.id, squad.id)) throw apiError(403, "blocked", "You can't join this squad.");

  const owner = squad.owner_id === null ? null : await db.userById(squad.owner_id);
  const maxSquads = squadLimit(user, now);
  const maxMembers = memberLimit(owner, user, now);
  if ((await db.squadCount(user.id)) >= maxSquads) throw plusRequired("squads");
  if ((await db.squadSize(squad.id)) >= maxMembers) throw plusRequired("members");
  let joined: boolean;
  try {
    joined = await db.joinSquad({ squadId: squad.id, userId: user.id, now, maxSquads, maxMembers });
  } catch (error) {
    if (isUniqueViolation(error, "squad_members.squad_id")) throw apiError(409, "already_member", "You're already in this squad.");
    throw error;
  }
  // Someone else got in first and took the last place (or the squad went).
  if (!joined) throw (await db.squadCount(user.id)) >= maxSquads ? plusRequired("squads") : plusRequired("members");
  console.log("squads: joined by code");
  return json({ squad: await loadSquad(context, squad.id) });
}

// PATCH /squads/:id/members/me

export async function updateMyMembership(context: AuthedContext, squadId: string): Promise<Response> {
  const body = await readObject(context.request);
  if (typeof body.muted !== "boolean") throw new HttpError(400, "muted must be true or false");
  await loadSquad(context, squadId);
  await context.db.setSquadMuted(squadId, context.user.id, body.muted);
  return json({ squad: await loadSquad(context, squadId) });
}

// DELETE /squads/:id/members/me

/** Leaves the squad. Not in it (or no such squad) is already the result: 204. */
export async function leaveSquad(context: AuthedContext, squadId: string): Promise<Response> {
  if (isShortID(squadId)) await context.db.leaveSquad(squadId, context.user.id);
  console.log("squads: left");
  return noContent();
}

// GET /squads/:id/leaderboard?week=YYYY-MM-DD

/**
 * The week's focused minutes and finished sessions of every member, most minutes first, ties by name
 * (M5). The week runs from Monday 00:00 to the next Monday in the squad's zone, solo and squad
 * sessions alike: a timer counts in the week it stopped. `week` is any day in it; left out, this
 * week. 422 `week_invalid` for anything but a real 'YYYY-MM-DD' date.
 */
export async function squadLeaderboard(context: AuthedContext, squadId: string): Promise<Response> {
  const row = isShortID(squadId) ? await context.db.mySquad(squadId, context.user.id) : null;
  if (row === null) throw notMember();
  const week = context.url.searchParams.get("week");
  if (week !== null && !isDay(week)) throw apiError(422, "week_invalid", "week must be a date: YYYY-MM-DD");
  const weekStart = mondayOf(week ?? localDay(row.tz, context.now));
  const startsAt = startOfDay(row.tz, weekStart);
  const endsAt = startOfDay(row.tz, addDays(weekStart, 7));
  const rows = await context.db.leaderboard(squadId, startsAt, endsAt);
  const entries: LeaderboardEntry[] = rows.sort(byMinutesThenName).map((entry) => ({ userId: entry.id, minutes: entry.minutes, sessions: entry.sessions }));
  return json({ weekStart, startsAt, endsAt, entries });
}

/** Most minutes first; ties by the name the Live Activity shows, ignoring case, then by id. */
function byMinutesThenName(a: LeaderboardRow, b: LeaderboardRow): number {
  if (a.minutes !== b.minutes) return b.minutes - a.minutes;
  const nameA = (a.display_name ?? a.handle ?? FALLBACK_MEMBER_NAME).toLowerCase();
  const nameB = (b.display_name ?? b.handle ?? FALLBACK_MEMBER_NAME).toLowerCase();
  if (nameA !== nameB) return nameA < nameB ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}
