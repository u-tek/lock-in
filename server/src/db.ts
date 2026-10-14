// A thin typed layer over D1 (migrations/). Every query the routes run is here, so the SQL can be
// read in one place and the routes deal in rows, not statements.
//
// D1 has no BEGIN/COMMIT: statements that must happen together go through `batch`, which D1 runs as
// one transaction (all or nothing). D1 enforces foreign keys, so deleting a user cascades
// (migrations/0001_init.sql).
//
// Limits that two requests could race past (squads per user, members per squad, one open room per
// squad, one open session per user) are enforced inside a single statement or by a unique index,
// never by a read followed by a write.

import type { ApnsEnvironment } from "./apns.ts";
import { addDays } from "./days.ts";
import { PET_RULES } from "./pet.ts";

/** A `users` row as stored. Never sent as is: `publicUser` picks what the app sees. */
export interface UserRow {
  id: string;
  apple_sub: string | null;
  handle: string | null;
  display_name: string | null;
  avatar_code: string;
  coins: number;
  plus_until: number | null;
  created_at: number;
  deleted_at: number | null;
  apple_refresh_token: string | null;
  /** 1 once POST /me/coins/import has run (M5). */
  coins_imported: number;
  /** 1 for an account the server runs itself: Demo Buddy (migrations/0006_demo_buddy.sql). */
  is_bot: number;
  /** RevenueCat's time (ms) of the last purchase event applied to `plus_until` (M7). */
  plus_event_ms: number | null;
}

/** Another user as a friend (or a blocked person): `since` is when the friendship (or block) began. */
export interface FriendRow {
  id: string;
  handle: string | null;
  display_name: string | null;
  avatar_code: string;
  since: number;
}

export interface InviteCodeRow {
  code: string;
  kind: "friend" | "squad";
  target_id: string;
  created_by: string;
  expires_at: number | null;
}

export interface DeviceInput {
  id: string;
  userId: string;
  apnsToken: string;
  apnsEnv: "sandbox" | "production";
  pushToStartToken: string | null;
  laEnabled: boolean;
  frequentPushes: boolean;
  tz: string;
  /** Minutes after local midnight (M4); null is off. */
  quietHours: { start: number; end: number } | null;
  /** An existing row keeps its quiet hours rather than taking `quietHours` (the app left them out). */
  keepQuietHours: boolean;
  now: number;
}

/** One phone of a squadmate who may get "X is locking in" (M4), before quiet hours and limits. */
export interface AlertDeviceRow {
  user_id: string;
  apns_token: string;
  apns_env: ApnsEnvironment;
  tz: string;
  quiet_start: number | null;
  quiet_end: number | null;
}

/** An `alerts` row (M4): one recipient alerted about one room. */
export interface AlertWrite {
  recipientId: string;
  squadId: string;
  senderId: string;
  sessionId: string;
  /** Unix seconds. */
  sentAt: number;
}

export interface ReportInput {
  id: string;
  reporterId: string;
  targetUserId: string;
  reason: string;
  note: string | null;
  now: number;
}

export interface ProfileChanges {
  handle?: string;
  displayName?: string;
  avatarCode?: string;
}

export interface SquadRow {
  id: string;
  name: string;
  owner_id: string | null;
  pet_species: string | null;
  pet_xp: number;
  pet_stage: number;
  streak_count: number;
  streak_last_day: string | null;
  created_at: number;
  /** IANA zone: the squad's days and Monday (M5). */
  tz: string;
  /** Unix seconds; null while the pet is an egg (M5). */
  hatched_at: number | null;
  /** The latest slip or early leave in one of its rooms, Unix seconds (M5). */
  last_sad_at: number | null;
  /** 1 for a Review Squad, made with the review code: Demo Buddy is in it (migrations/0006_demo_buddy.sql). */
  review: number;
  /** The pet accessory picked while boosted (`pet.<n>`), M7; shown only while the squad is boosted. */
  pet_accessory: number | null;
}

/** A squad as one of its members sees it: their own mute switch and when they joined. */
export interface MySquadRow extends SquadRow {
  muted: number;
  my_joined_at: number;
}

export interface SquadMemberRow {
  squad_id: string;
  id: string;
  handle: string | null;
  display_name: string | null;
  avatar_code: string;
  joined_at: number;
  /** 1 for Demo Buddy. */
  is_bot: number;
}

export interface SessionRow {
  id: string;
  squad_id: string | null;
  host_id: string | null;
  status: "open" | "ended";
  created_at: number;
  ended_at: number | null;
}

/** A squad's day so far (M5): its size, and how many members finished a session in it. */
export interface SquadDayRow {
  /** Members now. */
  size: number;
  /** Members who finished (done) at least one session, solo or squad. */
  finished: number;
  /** Members who finished one of `streakMinMinutes` or more: the streak's count. */
  counting: number;
}

/** One of a user's squads, its zone and its open room: whose streak and mood a finish may change (M5). */
export interface SquadZoneRow {
  squad_id: string;
  tz: string;
  open_session: string | null;
}

/** A member's week for the leaderboard (M5). */
export interface LeaderboardRow {
  id: string;
  handle: string | null;
  display_name: string | null;
  minutes: number;
  sessions: number;
}

/**
 * What one timer earned, credited when it stopped (M5): coins to the member, XP (and a sad spell)
 * to the room's squad, and a `focus_log` row. Credited at most once: see `syncRoom`.
 */
export interface CreditWrite {
  sessionId: string;
  userId: string;
  /** The timer's start, REAL Unix seconds: with the session and user, what makes it this timer. */
  startedAt: number;
  endedAt: number;
  /** The room's squad; null when solo. */
  squadId: string | null;
  focusedSec: number;
  completed: boolean;
  coins: number;
  xp: number;
  /** A slip or an early leave in a squad's room: the pet is sad from `endedAt`. */
  sad: boolean;
}

/** A squad's day that may now count for its streak (M5). Days are 'YYYY-MM-DD' in the squad's zone. */
export interface StreakDayWrite {
  squadId: string;
  day: string;
  yesterday: string;
  /** `day` as Unix seconds, `[start, end)`. */
  start: number;
  end: number;
  /**
   * M7: when set, a one-day gap before `yesterday` is filled with a Plus member's freeze first, at
   * this time (Unix seconds), so the day can carry the streak on (`freezeStatements`).
   */
  freezeAt?: number;
}

/** M7: a missed day a Plus member's freeze may fill. Days are 'YYYY-MM-DD' in the squad's zone. */
export interface FreezeCheck {
  squadId: string;
  /** The squad's today. */
  day: string;
  /** Unix seconds: when, and whose Plus counts (`plus_until` after it). */
  now: number;
}

/** What a squad's streak freezes look like to one member (M7). */
export interface FreezeRow {
  /** Frozen days of the squad on or after the day asked for, oldest first. */
  days: string[];
  /** Freezes the member used in the month asked for, in any squad. */
  used: number;
}

/** A RevenueCat event's effect on one user's `plus_until` (M7, src/plus.ts). */
export interface PlusWrite {
  userId: string;
  /**
   * `set`: plus_until becomes `until`. `subscription`: the same, except a lifetime Plus stays (a
   * subscription event can't take away what a one-time purchase gave). `raise`: plus_until becomes
   * `until` only if that's later (a transfer in). `clear`: no Plus (a transfer out).
   */
  mode: "set" | "subscription" | "raise" | "clear";
  until: number | null;
}

/** One `participants` row, written whole by its room (src/room.ts). Times are REAL Unix seconds. */
export interface ParticipantWrite {
  sessionId: string;
  userId: string;
  state: number;
  plannedMin: number;
  startedAt: number;
  endsAt: number;
  pausedAt: number | null;
  endedAt: number | null;
  focusedSec: number;
  laToken: string | null;
  laEnv: ApnsEnvironment | null;
  slips: number;
}

/** An `events` row: stats and debugging (SPEC.md §4.6). Never names or tokens in `meta`. */
export interface EventWrite {
  sessionId: string;
  userId: string | null;
  type: string;
  /** Unix seconds. */
  at: number;
  meta?: Record<string, number | string | boolean>;
}

/** Whether `error` is D1 refusing a duplicate in `column` (e.g. `users.handle`). */
export function isUniqueViolation(error: unknown, column: string): boolean {
  return error instanceof Error && error.message.includes(`UNIQUE constraint failed: ${column}`);
}

/** Whether `error` is D1 refusing a row because a CHECK on `column` failed (e.g. `coins`). */
export function isCheckViolation(error: unknown, column: string): boolean {
  return error instanceof Error && new RegExp(`CHECK constraint failed: [^:]*\\b${column}\\b`).test(error.message);
}

const FRIEND_COLUMNS = "u.id, u.handle, u.display_name, u.avatar_code";

const PARTICIPANT_UPDATE = `UPDATE participants SET
  state = ?, planned_min = ?, started_at = ?, ends_at = ?, paused_at = ?, ended_at = ?, focused_sec = ?,
  la_token = ?, la_env = ?, slips = ?
  WHERE session_id = ? AND user_id = ?`;

const PARTICIPANT_UPSERT = `INSERT INTO participants
  (session_id, user_id, state, planned_min, started_at, ends_at, paused_at, ended_at, focused_sec, la_token, la_env, slips)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT (session_id, user_id) DO UPDATE SET
    state = excluded.state, planned_min = excluded.planned_min, started_at = excluded.started_at,
    ends_at = excluded.ends_at, paused_at = excluded.paused_at, ended_at = excluded.ended_at,
    focused_sec = excluded.focused_sec, la_token = excluded.la_token, la_env = excluded.la_env,
    slips = excluded.slips`;

// A credit not yet written: its focus_log row doesn't exist. Binds the session, user and start.
const UNCREDITED = "NOT EXISTS (SELECT 1 FROM focus_log WHERE session_id = ? AND user_id = ? AND started_at = ?)";

/**
 * The stage as SQL, from the shared rules: 0 until hatched, then the highest stage whose XP the pet
 * has, never below 1 (src/pet.ts `petStage`).
 */
const STAGE_SQL = `CASE WHEN hatched_at IS NULL THEN 0 ${PET_RULES.stageXp
  .map((xp, stage) => ({ xp, stage }))
  .filter(({ stage }) => stage >= 2)
  .reverse()
  .map(({ xp, stage }) => `WHEN pet_xp >= ${xp} THEN ${stage}`)
  .join(" ")} ELSE 1 END`;

// "Someone other than the user bound here is in the squad `$squad`": a person, not a bot. Bots
// (Demo Buddy) never keep a squad alive or take it over.
const OTHER_PEOPLE = `SELECT 1 FROM squad_members m JOIN users u ON u.id = m.user_id
  WHERE m.squad_id = $squad AND m.user_id <> ? AND u.is_bot = 0`;

// The squads that count against a user's limit (bound: the user): Review Squads don't.
const COUNTED_SQUADS = `SELECT count(*) FROM squad_members cm JOIN squads cs ON cs.id = cm.squad_id
  WHERE cm.user_id = ? AND cs.review = 0`;

// The squad's people (bound: the squad), for "half the squad": bots aren't counted.
const SQUAD_PEOPLE = `SELECT count(*) FROM squad_members pm JOIN users pu ON pu.id = pm.user_id
  WHERE pm.squad_id = ? AND pu.is_bot = 0`;

/** A lifetime purchase's `plus_until`: the last second of year 9999 (M7). */
export const LIFETIME_PLUS_UNTIL = 253_402_300_799;

/** Streak freezes per Plus member per calendar month (M7, SPEC.md §2). */
export const STREAK_FREEZES_PER_MONTH = 2;

// Skipped rather than failing the whole batch when the user has just deleted their account.
const EVENT_INSERT = `INSERT INTO events (session_id, user_id, type, at, meta_json)
  SELECT ?, ?, ?, ?, ? WHERE ? IS NULL OR EXISTS (SELECT 1 FROM users WHERE id = ?)`;

export class Database {
  readonly d1: D1Database;

  constructor(d1: D1Database) {
    this.d1 = d1;
  }

  // Users

  userById(id: string): Promise<UserRow | null> {
    return this.d1.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();
  }

  userByAppleSub(sub: string): Promise<UserRow | null> {
    return this.d1.prepare("SELECT * FROM users WHERE apple_sub = ?").bind(sub).first<UserRow>();
  }

  /** Creates the user unless the Apple ID (or, vanishingly rarely, the id) already has a row. */
  async insertUserIfNew(user: { id: string; appleSub: string; displayName: string | null; now: number }): Promise<boolean> {
    const result = await this.d1
      .prepare("INSERT OR IGNORE INTO users (id, apple_sub, display_name, created_at) VALUES (?, ?, ?, ?)")
      .bind(user.id, user.appleSub, user.displayName, user.now)
      .run();
    return result.meta.changes > 0;
  }

  /** Who has this handle (stored lowercased; the column also compares ignoring case). */
  async handleOwner(handle: string): Promise<string | null> {
    return this.d1.prepare("SELECT id FROM users WHERE handle = ?").bind(handle).first<string>("id");
  }

  /**
   * Applies the changes that are present and returns the updated row. A handle someone else took in
   * the meantime throws D1's unique error (`isUniqueViolation(error, "users.handle")`).
   */
  async updateProfile(id: string, changes: ProfileChanges): Promise<UserRow | null> {
    return this.d1
      .prepare(
        `UPDATE users SET
           handle = coalesce(?, handle),
           display_name = coalesce(?, display_name),
           avatar_code = coalesce(?, avatar_code)
         WHERE id = ? RETURNING *`,
      )
      .bind(changes.handle ?? null, changes.displayName ?? null, changes.avatarCode ?? null, id)
      .first<UserRow>();
  }

  async setAppleRefreshToken(id: string, token: string): Promise<void> {
    await this.d1.prepare("UPDATE users SET apple_refresh_token = ? WHERE id = ?").bind(token, id).run();
  }

  /**
   * Deletes the user. Foreign keys take their sessions, devices, friendships (both directions),
   * blocks (both directions), friend and squad codes they made, squad memberships, participations
   * and reports about them; reports they filed stay, with reporter_id set to NULL.
   *
   * Their squads are handed on first, in the same transaction, as if they'd left each one: a squad
   * they own goes to its longest-standing other member, and a squad with nobody else in it is
   * deleted with its codes. Bots don't count: a Review Squad goes with its last person.
   */
  async deleteUser(id: string): Promise<void> {
    await this.d1.batch([
      this.d1
        .prepare(
          `UPDATE squads SET owner_id = (
             SELECT m.user_id FROM squad_members m JOIN users u ON u.id = m.user_id
             WHERE m.squad_id = squads.id AND m.user_id <> ? AND u.is_bot = 0
             ORDER BY m.joined_at, m.user_id LIMIT 1)
           WHERE owner_id = ?`,
        )
        .bind(id, id),
      this.d1
        .prepare(
          `DELETE FROM invite_codes WHERE kind = 'squad'
             AND target_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
             AND NOT EXISTS (${OTHER_PEOPLE.replace("$squad", "invite_codes.target_id")})`,
        )
        .bind(id, id),
      this.d1
        .prepare(
          `DELETE FROM squads WHERE id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
             AND NOT EXISTS (${OTHER_PEOPLE.replace("$squad", "squads.id")})`,
        )
        .bind(id, id),
      this.d1.prepare("DELETE FROM users WHERE id = ?").bind(id),
    ]);
  }

  // Sessions

  async insertAuthToken(tokenHash: string, userId: string, now: number): Promise<void> {
    await this.d1
      .prepare("INSERT INTO auth_tokens (token_hash, user_id, created_at, last_used_at) VALUES (?, ?, ?, ?)")
      .bind(tokenHash, userId, now, now)
      .run();
  }

  async userForToken(tokenHash: string): Promise<{ user: UserRow; lastUsedAt: number } | null> {
    const row = await this.d1
      .prepare("SELECT u.*, t.last_used_at AS token_last_used_at FROM auth_tokens t JOIN users u ON u.id = t.user_id WHERE t.token_hash = ?")
      .bind(tokenHash)
      .first<UserRow & { token_last_used_at: number }>();
    if (row === null) return null;
    const { token_last_used_at: lastUsedAt, ...user } = row;
    return { user, lastUsedAt };
  }

  async touchAuthToken(tokenHash: string, now: number): Promise<void> {
    await this.d1.prepare("UPDATE auth_tokens SET last_used_at = ? WHERE token_hash = ?").bind(now, tokenHash).run();
  }

  /** Signs one session out: the token stops working at once. */
  async deleteAuthToken(tokenHash: string): Promise<void> {
    await this.d1.prepare("DELETE FROM auth_tokens WHERE token_hash = ?").bind(tokenHash).run();
  }

  // Devices

  /** One row per APNs token: a phone that signs into another account moves its row with it. */
  async upsertDevice(device: DeviceInput): Promise<void> {
    const update = device.keepQuietHours ? 0 : 1;
    await this.d1
      .prepare(
        `INSERT INTO devices (id, user_id, apns_token, apns_env, push_to_start_token, la_enabled, frequent_pushes, tz, quiet_start, quiet_end, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (apns_token) DO UPDATE SET
           user_id = excluded.user_id,
           apns_env = excluded.apns_env,
           push_to_start_token = excluded.push_to_start_token,
           la_enabled = excluded.la_enabled,
           frequent_pushes = excluded.frequent_pushes,
           tz = excluded.tz,
           quiet_start = CASE WHEN ? THEN excluded.quiet_start ELSE quiet_start END,
           quiet_end = CASE WHEN ? THEN excluded.quiet_end ELSE quiet_end END,
           updated_at = excluded.updated_at`,
      )
      .bind(
        device.id,
        device.userId,
        device.apnsToken,
        device.apnsEnv,
        device.pushToStartToken,
        device.laEnabled ? 1 : 0,
        device.frequentPushes ? 1 : 0,
        device.tz,
        device.quietHours?.start ?? null,
        device.quietHours?.end ?? null,
        device.now,
        update,
        update,
      )
      .run();
  }

  /** APNs says this push-to-start token is gone: forget it wherever it's stored (M4). */
  async clearPushToStartToken(token: string): Promise<void> {
    await this.d1.prepare("UPDATE devices SET push_to_start_token = NULL WHERE push_to_start_token = ?").bind(token).run();
  }

  // Friends

  /** Newest friend first. */
  async friendsOf(userId: string): Promise<FriendRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT ${FRIEND_COLUMNS}, f.created_at AS since FROM friendships f JOIN users u ON u.id = f.friend_id
         WHERE f.user_id = ? ORDER BY f.created_at DESC, u.id`,
      )
      .bind(userId)
      .all<FriendRow>();
    return results;
  }

  async areFriends(userId: string, otherId: string): Promise<boolean> {
    const row = await this.d1.prepare("SELECT 1 AS yes FROM friendships WHERE user_id = ? AND friend_id = ?").bind(userId, otherId).first();
    return row !== null;
  }

  /** Both directions in one transaction. Already there is fine (a concurrent redeem). */
  async befriend(userId: string, otherId: string, now: number): Promise<void> {
    const insert = "INSERT OR IGNORE INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)";
    await this.d1.batch([this.d1.prepare(insert).bind(userId, otherId, now), this.d1.prepare(insert).bind(otherId, userId, now)]);
  }

  async unfriend(userId: string, otherId: string): Promise<void> {
    await this.d1
      .prepare("DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)")
      .bind(userId, otherId, otherId, userId)
      .run();
  }

  // Friend codes

  /** The friend code `userId` made that's still valid at `now`, the longest-lived if there are several. */
  currentFriendCode(userId: string, now: number): Promise<InviteCodeRow | null> {
    return this.d1
      .prepare(
        `SELECT * FROM invite_codes WHERE created_by = ? AND kind = 'friend' AND expires_at > ?
         ORDER BY expires_at DESC LIMIT 1`,
      )
      .bind(userId, now)
      .first<InviteCodeRow>();
  }

  /**
   * Stores a new friend code, and forgets the user's codes that expired before `forgetBefore` (kept
   * until then so an old link says "expired" rather than "not found"). False when the code exists.
   */
  async insertFriendCode(code: string, userId: string, expiresAt: number, forgetBefore: number): Promise<boolean> {
    const [, inserted] = await this.d1.batch([
      this.d1
        .prepare("DELETE FROM invite_codes WHERE created_by = ? AND kind = 'friend' AND expires_at < ?")
        .bind(userId, forgetBefore),
      this.d1
        .prepare("INSERT OR IGNORE INTO invite_codes (code, kind, target_id, created_by, expires_at) VALUES (?, 'friend', ?, ?, ?)")
        .bind(code, userId, userId, expiresAt),
    ]);
    return (inserted?.meta.changes ?? 0) > 0;
  }

  inviteCode(code: string): Promise<InviteCodeRow | null> {
    return this.d1.prepare("SELECT * FROM invite_codes WHERE code = ?").bind(code).first<InviteCodeRow>();
  }

  // Blocks

  /** Newest block first; `since` is when they were blocked. */
  async blockedBy(userId: string): Promise<FriendRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT ${FRIEND_COLUMNS}, b.created_at AS since FROM blocks b JOIN users u ON u.id = b.blocked_id
         WHERE b.user_id = ? ORDER BY b.created_at DESC, u.id`,
      )
      .bind(userId)
      .all<FriendRow>();
    return results;
  }

  /** Whether either has blocked the other. */
  async isBlockedEitherWay(userId: string, otherId: string): Promise<boolean> {
    const row = await this.d1
      .prepare("SELECT 1 AS yes FROM blocks WHERE (user_id = ? AND blocked_id = ?) OR (user_id = ? AND blocked_id = ?) LIMIT 1")
      .bind(userId, otherId, otherId, userId)
      .first();
    return row !== null;
  }

  /** Blocks and ends the friendship (both directions), in one transaction. */
  async block(userId: string, blockedId: string, now: number): Promise<void> {
    await this.d1.batch([
      this.d1.prepare("INSERT OR IGNORE INTO blocks (user_id, blocked_id, created_at) VALUES (?, ?, ?)").bind(userId, blockedId, now),
      this.d1
        .prepare("DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)")
        .bind(userId, blockedId, blockedId, userId),
    ]);
  }

  async unblock(userId: string, blockedId: string): Promise<void> {
    await this.d1.prepare("DELETE FROM blocks WHERE user_id = ? AND blocked_id = ?").bind(userId, blockedId).run();
  }

  // Reports

  async insertReport(report: ReportInput): Promise<void> {
    await this.d1
      .prepare("INSERT INTO reports (id, reporter_id, target_user_id, reason, note, created_at) VALUES (?, ?, ?, ?, ?, ?)")
      .bind(report.id, report.reporterId, report.targetUserId, report.reason, report.note, report.now)
      .run();
  }
  // Squads

  /** The user's squads, the one they joined first first. */
  async squadsOf(userId: string): Promise<MySquadRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT s.*, m.muted, m.joined_at AS my_joined_at FROM squad_members m JOIN squads s ON s.id = m.squad_id
         WHERE m.user_id = ? ORDER BY m.joined_at, s.id`,
      )
      .bind(userId)
      .all<MySquadRow>();
    return results;
  }

  /** The squad as `userId` sees it, or null when there's no such squad or they aren't in it. */
  mySquad(squadId: string, userId: string): Promise<MySquadRow | null> {
    return this.d1
      .prepare(
        `SELECT s.*, m.muted, m.joined_at AS my_joined_at FROM squads s JOIN squad_members m ON m.squad_id = s.id
         WHERE s.id = ? AND m.user_id = ?`,
      )
      .bind(squadId, userId)
      .first<MySquadRow>();
  }

  squadById(squadId: string): Promise<SquadRow | null> {
    return this.d1.prepare("SELECT * FROM squads WHERE id = ?").bind(squadId).first<SquadRow>();
  }

  async isSquadMember(squadId: string, userId: string): Promise<boolean> {
    const row = await this.d1.prepare("SELECT 1 AS yes FROM squad_members WHERE squad_id = ? AND user_id = ?").bind(squadId, userId).first();
    return row !== null;
  }

  /** The squad's members, longest-standing first (a bot after people who joined with it). */
  async membersOfSquad(squadId: string): Promise<SquadMemberRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT m.squad_id, u.id, u.handle, u.display_name, u.avatar_code, m.joined_at, u.is_bot
         FROM squad_members m JOIN users u ON u.id = m.user_id
         WHERE m.squad_id = ? ORDER BY m.joined_at, u.is_bot, u.id`,
      )
      .bind(squadId)
      .all<SquadMemberRow>();
    return results;
  }

  /** Members of every squad `userId` is in, longest-standing first within each squad. */
  async membersOfSquadsOf(userId: string): Promise<SquadMemberRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT m.squad_id, u.id, u.handle, u.display_name, u.avatar_code, m.joined_at, u.is_bot
         FROM squad_members m JOIN users u ON u.id = m.user_id
         WHERE m.squad_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
         ORDER BY m.joined_at, u.is_bot, u.id`,
      )
      .bind(userId)
      .all<SquadMemberRow>();
    return results;
  }

  /** Open rooms of every squad `userId` is in: squad id -> session id. */
  async openSessionsOfSquadsOf(userId: string): Promise<Map<string, string>> {
    const { results } = await this.d1
      .prepare(
        `SELECT id, squad_id FROM sessions
         WHERE status = 'open' AND squad_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)`,
      )
      .bind(userId)
      .all<{ id: string; squad_id: string }>();
    return new Map(results.map((row) => [row.squad_id, row.id]));
  }

  /** How many squads the user is in, owned or not, against their limit: Review Squads don't count. */
  async squadCount(userId: string): Promise<number> {
    return (await this.d1.prepare(`SELECT (${COUNTED_SQUADS}) AS n`).bind(userId).first<number>("n")) ?? 0;
  }

  async squadSize(squadId: string): Promise<number> {
    return (await this.d1.prepare("SELECT count(*) AS n FROM squad_members WHERE squad_id = ?").bind(squadId).first<number>("n")) ?? 0;
  }

  /**
   * Creates a squad with its owner as the first member, unless the owner is already in `maxSquads`
   * squads: false then. Checked and written in one transaction, so two requests can't both slip
   * under the limit. A taken id throws D1's unique error on `squads.id`. M5: the egg's species and
   * the squad's time zone are set from the start.
   */
  async insertSquad(squad: { id: string; name: string; ownerId: string; now: number; maxSquads: number; species: string; tz: string }): Promise<boolean> {
    const [inserted] = await this.d1.batch([
      this.d1
        .prepare(
          `INSERT INTO squads (id, name, owner_id, created_at, pet_species, tz)
           SELECT ?, ?, ?, ?, ?, ? WHERE (${COUNTED_SQUADS}) < ?`,
        )
        .bind(squad.id, squad.name, squad.ownerId, squad.now, squad.species, squad.tz, squad.ownerId, squad.maxSquads),
      this.d1
        .prepare(
          `INSERT INTO squad_members (squad_id, user_id, joined_at)
           SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM squads WHERE id = ? AND owner_id = ?)
             AND NOT EXISTS (SELECT 1 FROM squad_members WHERE squad_id = ?)`,
        )
        .bind(squad.id, squad.ownerId, squad.now, squad.id, squad.ownerId, squad.id),
    ]);
    return (inserted?.meta.changes ?? 0) > 0;
  }

  async renameSquad(squadId: string, name: string): Promise<void> {
    await this.d1.prepare("UPDATE squads SET name = ? WHERE id = ?").bind(name, squadId).run();
  }

  async setSquadMuted(squadId: string, userId: string, muted: boolean): Promise<void> {
    await this.d1.prepare("UPDATE squad_members SET muted = ? WHERE squad_id = ? AND user_id = ?").bind(muted ? 1 : 0, squadId, userId).run();
  }

  /**
   * Adds the user to the squad unless they're in `maxSquads` squads already (a Review Squad never
   * counts, joining one or already in one) or it has `maxMembers` members: false then. One
   * statement, so the limits hold however many people join at once. Already a member throws D1's
   * unique error on `squad_members.squad_id`.
   */
  async joinSquad(join: { squadId: string; userId: string; now: number; maxSquads: number; maxMembers: number }): Promise<boolean> {
    const result = await this.d1
      .prepare(
        `INSERT INTO squad_members (squad_id, user_id, joined_at)
         SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM squads WHERE id = ?)
           AND ((SELECT review FROM squads WHERE id = ?) = 1 OR (${COUNTED_SQUADS}) < ?)
           AND (SELECT count(*) FROM squad_members WHERE squad_id = ?) < ?`,
      )
      .bind(join.squadId, join.userId, join.now, join.squadId, join.squadId, join.userId, join.maxSquads, join.squadId, join.maxMembers)
      .run();
    return result.meta.changes > 0;
  }

  /**
   * Takes the user out of the squad, in one transaction: the squad codes they made for it stop
   * working; if they owned it, it goes to the longest-standing person left; if no person is left
   * (a bot doesn't count: Demo Buddy in a Review Squad), the squad and its codes are deleted. Not a
   * member: nothing changes.
   */
  async leaveSquad(squadId: string, userId: string): Promise<void> {
    const people = `SELECT 1 FROM squad_members m JOIN users u ON u.id = m.user_id WHERE m.squad_id = ? AND u.is_bot = 0`;
    await this.d1.batch([
      this.d1.prepare("DELETE FROM squad_members WHERE squad_id = ? AND user_id = ?").bind(squadId, userId),
      this.d1.prepare("DELETE FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND created_by = ?").bind(squadId, userId),
      this.d1
        .prepare(
          `UPDATE squads SET owner_id = (
             SELECT m.user_id FROM squad_members m JOIN users u ON u.id = m.user_id
             WHERE m.squad_id = ? AND u.is_bot = 0 ORDER BY m.joined_at, m.user_id LIMIT 1)
           WHERE id = ? AND (owner_id = ? OR owner_id IS NULL)`,
        )
        .bind(squadId, squadId, userId),
      this.d1.prepare(`DELETE FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND NOT EXISTS (${people})`).bind(squadId, squadId),
      this.d1.prepare(`DELETE FROM squads WHERE id = ? AND NOT EXISTS (${people})`).bind(squadId, squadId),
    ]);
  }

  /** Whether the user has blocked anyone in the squad, or anyone in it has blocked them. */
  async isBlockedWithinSquad(userId: string, squadId: string): Promise<boolean> {
    const row = await this.d1
      .prepare(
        `SELECT 1 AS yes FROM squad_members m JOIN blocks b
           ON (b.user_id = ? AND b.blocked_id = m.user_id) OR (b.blocked_id = ? AND b.user_id = m.user_id)
         WHERE m.squad_id = ? LIMIT 1`,
      )
      .bind(userId, userId, squadId)
      .first();
    return row !== null;
  }

  /** The squad code `userId` made for the squad that's still valid at `now`, if any. */
  currentSquadCode(squadId: string, userId: string, now: number): Promise<InviteCodeRow | null> {
    return this.d1
      .prepare(
        `SELECT * FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND created_by = ? AND expires_at > ?
         ORDER BY expires_at DESC LIMIT 1`,
      )
      .bind(squadId, userId, now)
      .first<InviteCodeRow>();
  }

  /** Like `insertFriendCode`, for a squad: false when the code exists. */
  async insertSquadCode(code: string, squadId: string, userId: string, expiresAt: number, forgetBefore: number): Promise<boolean> {
    const [, inserted] = await this.d1.batch([
      this.d1
        .prepare("DELETE FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND created_by = ? AND expires_at < ?")
        .bind(squadId, userId, forgetBefore),
      this.d1
        .prepare("INSERT OR IGNORE INTO invite_codes (code, kind, target_id, created_by, expires_at) VALUES (?, 'squad', ?, ?, ?)")
        .bind(code, squadId, userId, expiresAt),
    ]);
    return (inserted?.meta.changes ?? 0) > 0;
  }

  // Sessions (rooms)

  sessionById(sessionId: string): Promise<SessionRow | null> {
    return this.d1.prepare("SELECT * FROM sessions WHERE id = ?").bind(sessionId).first<SessionRow>();
  }

  /** The squad's open room, if it has one (at most one: sessions_open_squad). */
  openSessionOfSquad(squadId: string): Promise<SessionRow | null> {
    return this.d1.prepare("SELECT * FROM sessions WHERE squad_id = ? AND status = 'open'").bind(squadId).first<SessionRow>();
  }

  /** The session where the user's timer is still running, if any (at most one: participants_user_open). */
  async openParticipation(userId: string): Promise<string | null> {
    return this.d1.prepare("SELECT session_id FROM participants WHERE user_id = ? AND ended_at IS NULL LIMIT 1").bind(userId).first<string>("session_id");
  }

  /** Open rooms the user is in, running or not (a member who finished stays in the room until it ends). */
  async openRoomsOf(userId: string): Promise<string[]> {
    const { results } = await this.d1
      .prepare("SELECT p.session_id FROM participants p JOIN sessions s ON s.id = p.session_id WHERE p.user_id = ? AND s.status = 'open'")
      .bind(userId)
      .all<{ session_id: string }>();
    return results.map((row) => row.session_id);
  }

  async isParticipant(sessionId: string, userId: string): Promise<boolean> {
    const row = await this.d1.prepare("SELECT 1 AS yes FROM participants WHERE session_id = ? AND user_id = ?").bind(sessionId, userId).first();
    return row !== null;
  }

  /**
   * A new room and its host, in one transaction. Throws D1's unique error on `sessions.squad_id`
   * when the squad already has an open room, and on `participants.user_id` when the host already
   * has an open session. Demo Buddy hosting has no `participants` row (null): its timers live in
   * the room only.
   */
  async insertRoom(
    session: { id: string; squadId: string | null; hostId: string; createdAt: number },
    host: ParticipantWrite | null,
    event: EventWrite | null,
  ): Promise<void> {
    await this.d1.batch([
      this.d1
        .prepare("INSERT INTO sessions (id, squad_id, host_id, status, created_at) VALUES (?, ?, ?, 'open', ?)")
        .bind(session.id, session.squadId, session.hostId, session.createdAt),
      ...(host === null ? [] : [this.participantUpsert(host)]),
      ...(event === null ? [] : [this.eventInsert(event)]),
    ]);
  }

  /** A member joining (or joining again): throws D1's unique error on `participants.user_id` when they have another open session. */
  async upsertParticipant(participant: ParticipantWrite, event: EventWrite): Promise<void> {
    await this.d1.batch([this.participantUpsert(participant), this.eventInsert(event)]);
  }

  /**
   * The room's state since its last write, in one transaction. Rows of deleted users are skipped.
   *
   * M5: with it, what stopped timers earned (`credits`), the squad's egg hatching, its stage, and
   * the streak days the finishes may have made count. Each credit's coins and XP are added only
   * while its `focus_log` row doesn't exist, and the row is written last, so writing the same
   * credit again (the room retrying, or a write that succeeded without the room hearing so) adds
   * nothing. Hatching and streak days are guarded the same way: by `hatched_at` and
   * `streak_last_day`.
   */
  async syncRoom(sync: {
    participants: ParticipantWrite[];
    ended?: { sessionId: string; endedAt: number };
    events: EventWrite[];
    credits?: CreditWrite[];
    /** The room's squad hatched at this time, unless it already has. */
    hatch?: { squadId: string; at: number };
    /** The room's squad: its stage follows its XP and hatching. */
    stageOf?: string;
    streakDays?: StreakDayWrite[];
    /** A slip in the room's squad at this time (Unix seconds): the pet's sad spell starts (M5, gentle slips). */
    sad?: { squadId: string; at: number };
  }): Promise<void> {
    const statements = sync.participants.map((p) =>
      this.d1
        .prepare(PARTICIPANT_UPDATE)
        .bind(p.state, p.plannedMin, p.startedAt, p.endsAt, p.pausedAt, p.endedAt, p.focusedSec, p.laToken, p.laEnv, p.slips, p.sessionId, p.userId),
    );
    if (sync.ended !== undefined) {
      statements.push(
        this.d1.prepare("UPDATE sessions SET status = 'ended', ended_at = ? WHERE id = ? AND status = 'open'").bind(sync.ended.endedAt, sync.ended.sessionId),
      );
    }
    for (const event of sync.events) statements.push(this.eventInsert(event));
    for (const credit of sync.credits ?? []) statements.push(...this.creditStatements(credit));
    if (sync.hatch !== undefined) {
      statements.push(this.d1.prepare("UPDATE squads SET hatched_at = ? WHERE id = ? AND hatched_at IS NULL").bind(Math.floor(sync.hatch.at), sync.hatch.squadId));
    }
    if (sync.stageOf !== undefined) statements.push(this.d1.prepare(`UPDATE squads SET pet_stage = ${STAGE_SQL} WHERE id = ?`).bind(sync.stageOf));
    if (sync.sad !== undefined) {
      statements.push(
        this.d1.prepare("UPDATE squads SET last_sad_at = max(coalesce(last_sad_at, 0), ?) WHERE id = ?").bind(Math.floor(sync.sad.at), sync.sad.squadId),
      );
    }
    // Oldest day first, each one's freeze (M7) before it: a freeze fills the day before it only.
    for (const day of [...(sync.streakDays ?? [])].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0))) {
      if (day.freezeAt !== undefined) statements.push(...this.freezeStatements({ squadId: day.squadId, day: day.day, now: day.freezeAt }));
      statements.push(this.streakStatement(day));
    }
    if (statements.length > 0) await this.d1.batch(statements);
  }

  // The pet, streaks, the leaderboard and coins (M5, src/progress.ts, src/shop.ts)

  /** Gives a squad from before M5 its egg's species. The first to set it wins; returns the squad as it is then. */
  async assignSpecies(squadId: string, species: string): Promise<SquadRow | null> {
    await this.d1.prepare("UPDATE squads SET pet_species = ? WHERE id = ? AND pet_species IS NULL").bind(species, squadId).run();
    return this.squadById(squadId);
  }

  /**
   * The squad's size, and how many members finished a session (and one long enough to count) in
   * `[start, end)`. People only: a bot (Demo Buddy) isn't counted in any of them.
   */
  async squadDay(squadId: string, start: number, end: number): Promise<SquadDayRow> {
    const finishedIn = `SELECT count(DISTINCT f.user_id) FROM focus_log f JOIN squad_members m ON m.user_id = f.user_id
       JOIN users u ON u.id = f.user_id AND u.is_bot = 0
       WHERE m.squad_id = ? AND f.completed = 1 AND f.ended_at >= ? AND f.ended_at < ?`;
    const row = await this.d1
      .prepare(
        `SELECT (${SQUAD_PEOPLE}) AS size,
           (${finishedIn}) AS finished,
           (${finishedIn} AND f.focused_sec >= ?) AS counting`,
      )
      .bind(squadId, squadId, start, end, squadId, start, end, PET_RULES.streakMinMinutes * 60)
      .first<SquadDayRow>();
    return row ?? { size: 0, finished: 0, counting: 0 };
  }

  /** Counts `day` for the squad's streak if enough members finished in it (`countStreakDay`). Returns the squad after. */
  async countStreakDay(write: StreakDayWrite): Promise<SquadRow | null> {
    await this.streakStatement(write).run();
    return this.squadById(write.squadId);
  }

  /** The user's squads, their zones and open rooms: whose streak and mood a finished session touches. */
  async squadZonesOf(userId: string): Promise<SquadZoneRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT m.squad_id, s.tz, (SELECT id FROM sessions WHERE squad_id = s.id AND status = 'open') AS open_session
         FROM squad_members m JOIN squads s ON s.id = m.squad_id WHERE m.user_id = ? ORDER BY m.joined_at, s.id`,
      )
      .bind(userId)
      .all<SquadZoneRow>();
    return results;
  }

  /** The squads the user owns move to `tz` (they registered a phone there). */
  async setOwnedSquadsZone(userId: string, tz: string): Promise<void> {
    await this.d1.prepare("UPDATE squads SET tz = ? WHERE owner_id = ? AND tz <> ?").bind(tz, userId, tz).run();
  }

  /** The zone of the user's most recently registered phone, if they have one. */
  latestDeviceZone(userId: string): Promise<string | null> {
    return this.d1.prepare("SELECT tz FROM devices WHERE user_id = ? ORDER BY updated_at DESC, id LIMIT 1").bind(userId).first<string>("tz");
  }

  /**
   * Every member's whole focused minutes and finished sessions with timers that stopped in
   * `[start, end)`. People only: a bot (Demo Buddy) is never on a leaderboard.
   */
  async leaderboard(squadId: string, start: number, end: number): Promise<LeaderboardRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT u.id, u.handle, u.display_name,
           coalesce(sum(f.focused_sec / 60), 0) AS minutes, coalesce(sum(f.completed), 0) AS sessions
         FROM squad_members m JOIN users u ON u.id = m.user_id
         LEFT JOIN focus_log f ON f.user_id = m.user_id AND f.ended_at >= ? AND f.ended_at < ?
         WHERE m.squad_id = ? AND u.is_bot = 0 GROUP BY u.id`,
      )
      .bind(start, end, squadId)
      .all<LeaderboardRow>();
    return results;
  }

  /** The items the user bought (or imported), first acquired first. */
  async cosmeticsOf(userId: string): Promise<string[]> {
    const { results } = await this.d1
      .prepare("SELECT item_id FROM cosmetics WHERE user_id = ? ORDER BY acquired_at, item_id")
      .bind(userId)
      .all<{ item_id: string }>();
    return results.map((row) => row.item_id);
  }

  /**
   * Takes `price` coins and adds the item, in one transaction, and returns the coins left. Both
   * limits are the database's, so two purchases racing can't get past them: too few coins fails
   * the CHECK on `users.coins` (`isCheckViolation(error, "coins")`), and an item already owned the
   * primary key on `cosmetics` (`isUniqueViolation(error, "cosmetics.user_id")`). Either way
   * nothing changes.
   */
  async buyItem(userId: string, itemId: string, price: number, now: number): Promise<number> {
    const [paid] = await this.d1.batch([
      this.d1.prepare("UPDATE users SET coins = coins - ? WHERE id = ? RETURNING coins").bind(price, userId),
      this.d1.prepare("INSERT INTO cosmetics (user_id, item_id, acquired_at) VALUES (?, ?, ?)").bind(userId, itemId, now),
    ]);
    return (paid?.results[0] as { coins: number } | undefined)?.coins ?? 0;
  }

  /**
   * Adds coins and items earned signed out, once per account, in one transaction. A second import
   * fails the CHECK on `users.coins_imported` (`isCheckViolation(error, "coins_imported")`) and
   * changes nothing. Items already owned are skipped. Returns the user after.
   */
  async importCoins(userId: string, coins: number, items: string[], now: number): Promise<UserRow | null> {
    const [updated] = await this.d1.batch([
      this.d1.prepare("UPDATE users SET coins = coins + ?, coins_imported = coins_imported + 1 WHERE id = ? RETURNING *").bind(coins, userId),
      ...items.map((itemId) => this.d1.prepare("INSERT OR IGNORE INTO cosmetics (user_id, item_id, acquired_at) VALUES (?, ?, ?)").bind(userId, itemId, now)),
    ]);
    return (updated?.results[0] as UserRow | undefined) ?? null;
  }

  // Analytics counts (src/metrics.ts, migrations/0008_metrics.sql)

  /**
   * Counts one metrics batch for `day` unless `limit` batches already arrived that day: false then.
   * One statement, so racing batches can't get past the cap.
   */
  async reserveMetricsBatch(day: string, limit: number): Promise<boolean> {
    const result = await this.d1
      .prepare(
        `INSERT INTO metrics_batches (day, batches) VALUES (?, 1)
         ON CONFLICT (day) DO UPDATE SET batches = batches + 1 WHERE batches < ?`,
      )
      .bind(day, limit)
      .run();
    return result.meta.changes > 0;
  }

  /** Adds each count to the day's total for its event, in one transaction. */
  async addMetrics(day: string, counts: ReadonlyMap<string, number>): Promise<void> {
    if (counts.size === 0) return;
    await this.d1.batch(
      [...counts].map(([event, count]) =>
        this.d1
          .prepare("INSERT INTO metrics_daily (day, event, count) VALUES (?, ?, ?) ON CONFLICT (day, event) DO UPDATE SET count = count + excluded.count")
          .bind(day, event, count),
      ),
    );
  }

  // Demo Buddy and Review Squads (src/reviewSquad.ts, docs/launch/app-review-notes.md §3)

  /**
   * Records one redemption of the review code unless `limit` happened since `since`: false then.
   * One statement, so redemptions racing can't get past the limit. Trims the log to `trimBefore`.
   */
  async reserveReviewRedemption(now: number, since: number, limit: number, trimBefore: number): Promise<boolean> {
    const [, inserted] = await this.d1.batch([
      this.d1.prepare("DELETE FROM review_redemptions WHERE at < ?").bind(trimBefore),
      this.d1
        .prepare("INSERT INTO review_redemptions (at) SELECT ? WHERE (SELECT count(*) FROM review_redemptions WHERE at > ?) < ?")
        .bind(now, since, limit),
    ]);
    return (inserted?.meta.changes ?? 0) > 0;
  }

  /** The oldest redemption after `since`: when the limit lets the next one through. */
  oldestReviewRedemption(since: number): Promise<number | null> {
    return this.d1.prepare("SELECT min(at) AS at FROM review_redemptions WHERE at > ?").bind(since).first<number>("at");
  }

  /**
   * A Review Squad: the redeemer owns it, and they and the bot are its members, in one transaction.
   * It doesn't count against the redeemer's squad limit. A taken id throws D1's unique error on
   * `squads.id`.
   */
  async insertReviewSquad(squad: { id: string; name: string; ownerId: string; botId: string; now: number; species: string; tz: string }): Promise<void> {
    const member = "INSERT INTO squad_members (squad_id, user_id, joined_at) VALUES (?, ?, ?)";
    await this.d1.batch([
      this.d1
        .prepare("INSERT INTO squads (id, name, owner_id, created_at, pet_species, tz, review) VALUES (?, ?, ?, ?, ?, ?, 1)")
        .bind(squad.id, squad.name, squad.ownerId, squad.now, squad.species, squad.tz),
      this.d1.prepare(member).bind(squad.id, squad.ownerId, squad.now),
      this.d1.prepare(member).bind(squad.id, squad.botId, squad.now),
    ]);
  }

  // Lockin Plus (M7, src/plus.ts)

  /** Squad Boost: whether any member of the squad has Plus at `now`. */
  async squadBoosted(squadId: string, now: number): Promise<boolean> {
    const row = await this.d1
      .prepare("SELECT 1 AS yes FROM squad_members m JOIN users u ON u.id = m.user_id WHERE m.squad_id = ? AND u.plus_until > ? LIMIT 1")
      .bind(squadId, now)
      .first();
    return row !== null;
  }

  async setPetAccessory(squadId: string, accessory: number | null): Promise<void> {
    await this.d1.prepare("UPDATE squads SET pet_accessory = ? WHERE id = ?").bind(accessory, squadId).run();
  }

  /** Fills a one-day gap with a freeze if one may (`freezeStatements`). Returns the squad after. */
  async freezeStreakGap(check: FreezeCheck): Promise<SquadRow | null> {
    await this.d1.batch(this.freezeStatements(check));
    return this.squadById(check.squadId);
  }

  /** The squad's frozen days from `sinceDay` on, and how many freezes `userId` used in `month` ('YYYY-MM'). */
  async streakFreezes(squadId: string, sinceDay: string, userId: string, month: string): Promise<FreezeRow> {
    const [days, used] = await this.d1.batch([
      this.d1.prepare("SELECT day FROM streak_freezes WHERE squad_id = ? AND day >= ? ORDER BY day").bind(squadId, sinceDay),
      this.d1.prepare("SELECT count(*) AS n FROM streak_freezes WHERE user_id = ? AND substr(day, 1, 7) = ?").bind(userId, month),
    ]);
    return {
      days: ((days?.results ?? []) as Array<{ day: string }>).map((row) => row.day),
      used: Number((used?.results[0] as { n?: number } | undefined)?.n ?? 0),
    };
  }

  /** People (not bots) among `ids`. */
  async peopleAmong(ids: string[]): Promise<UserRow[]> {
    if (ids.length === 0) return [];
    const { results } = await this.d1
      .prepare(`SELECT * FROM users WHERE is_bot = 0 AND id IN (${ids.map(() => "?").join(", ")})`)
      .bind(...ids)
      .all<UserRow>();
    return results;
  }

  async revenueCatEventSeen(eventId: string): Promise<boolean> {
    return (await this.d1.prepare("SELECT 1 AS yes FROM revenuecat_events WHERE id = ?").bind(eventId).first()) !== null;
  }

  /**
   * Applies one RevenueCat event, in one transaction: each write to `plus_until`, then the event's
   * row. Every write applies only while that row doesn't exist (so the same event twice counts
   * once, however it races) and only to a user whose last applied event isn't newer than this one
   * (`eventMs`), so events arriving out of order can't undo a later one. Trims the event log to
   * `trimBefore`. Returns how many users' rows it changed.
   */
  async applyRevenueCatEvent(event: { id: string; type: string; eventMs: number; receivedAt: number; trimBefore: number; writes: PlusWrite[] }): Promise<number> {
    const unseen = "NOT EXISTS (SELECT 1 FROM revenuecat_events WHERE id = ?)";
    const inOrder = "(plus_event_ms IS NULL OR plus_event_ms <= ?)";
    const statements = event.writes.map((write) => {
      const value =
        write.mode === "clear"
          ? "NULL"
          : write.mode === "raise"
            ? "max(coalesce(plus_until, 0), ?)"
            : write.mode === "subscription"
              ? `CASE WHEN plus_until = ${LIFETIME_PLUS_UNTIL} THEN plus_until ELSE ? END`
              : "?";
      const binds: Array<number | string | null> = write.mode === "clear" ? [] : [write.until];
      return this.d1
        .prepare(`UPDATE users SET plus_until = ${value}, plus_event_ms = ? WHERE id = ? AND is_bot = 0 AND ${inOrder} AND ${unseen}`)
        .bind(...binds, event.eventMs, write.userId, event.eventMs, event.id);
    });
    statements.push(
      this.d1.prepare("DELETE FROM revenuecat_events WHERE received_at < ?").bind(event.trimBefore),
      this.d1.prepare("INSERT OR IGNORE INTO revenuecat_events (id, type, received_at) VALUES (?, ?, ?)").bind(event.id, event.type, event.receivedAt),
    );
    const results = await this.d1.batch(statements);
    return results.slice(0, event.writes.length).reduce((sum, result) => sum + (result?.meta.changes ?? 0), 0);
  }

  /** What RevenueCat's REST API says (POST /me/plus/refresh): authoritative as of `atMs`. Returns the user after. */
  setPlusUntil(userId: string, until: number | null, atMs: number): Promise<UserRow | null> {
    return this.d1
      .prepare("UPDATE users SET plus_until = ?, plus_event_ms = max(coalesce(plus_event_ms, 0), ?) WHERE id = ? RETURNING *")
      .bind(until, atMs, userId)
      .first<UserRow>();
  }

  // "X is locking in" (M4, src/alerts.ts)

  /** Whether `hostId` opened another room in the squad after `since`: open, end, open again. */
  async openedAnotherRoomSince(squadId: string, hostId: string, sessionId: string, since: number): Promise<boolean> {
    const row = await this.d1
      .prepare("SELECT 1 AS yes FROM sessions WHERE squad_id = ? AND host_id = ? AND id <> ? AND created_at > ? LIMIT 1")
      .bind(squadId, hostId, sessionId, since)
      .first();
    return row !== null;
  }

  /**
   * Every phone of every squadmate who may be told `openerId` is locking in: not the opener, not
   * muted, no block either way, not in a session (a running timer anywhere). Quiet hours and the
   * limits come after.
   */
  async alertCandidates(squadId: string, openerId: string): Promise<AlertDeviceRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT d.user_id, d.apns_token, d.apns_env, d.tz, d.quiet_start, d.quiet_end
         FROM squad_members m JOIN devices d ON d.user_id = m.user_id
         WHERE m.squad_id = ? AND m.user_id <> ? AND m.muted = 0
           AND NOT EXISTS (SELECT 1 FROM blocks b
             WHERE (b.user_id = m.user_id AND b.blocked_id = ?) OR (b.user_id = ? AND b.blocked_id = m.user_id))
           AND NOT EXISTS (SELECT 1 FROM participants p WHERE p.user_id = m.user_id AND p.ended_at IS NULL)
         ORDER BY m.joined_at, m.user_id, d.id`,
      )
      .bind(squadId, openerId, openerId, openerId)
      .all<AlertDeviceRow>();
    return results;
  }

  /**
   * Records each alert unless it would break a limit: one per squad per recipient since
   * `squadSince`, fewer than `dailyLimit` per recipient since `daySince`. Each check and write is one
   * statement, so two rooms opening at once can't both slip under a limit. Whether each was recorded.
   */
  async reserveAlerts(alerts: AlertWrite[], limits: { squadSince: number; daySince: number; dailyLimit: number }): Promise<boolean[]> {
    if (alerts.length === 0) return [];
    const results = await this.d1.batch(
      alerts.map((alert) =>
        this.d1
          .prepare(
            `INSERT INTO alerts (recipient_id, squad_id, sender_id, session_id, sent_at)
             SELECT ?, ?, ?, ?, ?
             WHERE NOT EXISTS (SELECT 1 FROM alerts WHERE recipient_id = ? AND squad_id = ? AND sent_at > ?)
               AND (SELECT count(*) FROM alerts WHERE recipient_id = ? AND sent_at > ?) < ?`,
          )
          .bind(
            alert.recipientId,
            alert.squadId,
            alert.senderId,
            alert.sessionId,
            alert.sentAt,
            alert.recipientId,
            alert.squadId,
            limits.squadSince,
            alert.recipientId,
            limits.daySince,
            limits.dailyLimit,
          ),
      ),
    );
    return results.map((result) => (result?.meta.changes ?? 0) > 0);
  }

  /**
   * After the sends, in one transaction: strikes off recipients none of whose phones took the
   * alert, deletes devices APNs says are gone, and trims the log to `trimBefore`.
   */
  async afterAlerts(done: { sessionId: string; undelivered: string[]; goneTokens: string[]; trimBefore: number }): Promise<void> {
    await this.d1.batch([
      ...done.undelivered.map((recipientId) =>
        this.d1.prepare("DELETE FROM alerts WHERE session_id = ? AND recipient_id = ?").bind(done.sessionId, recipientId),
      ),
      ...done.goneTokens.map((token) => this.d1.prepare("DELETE FROM devices WHERE apns_token = ?").bind(token)),
      this.d1.prepare("DELETE FROM alerts WHERE sent_at < ?").bind(done.trimBefore),
    ]);
  }

  /** Coins, then XP and sadness, then the log row that stops them being added again. */
  private creditStatements(credit: CreditWrite): D1PreparedStatement[] {
    const key = [credit.sessionId, credit.userId, credit.startedAt];
    const statements = [
      this.d1.prepare(`UPDATE users SET coins = coins + ? WHERE id = ? AND ${UNCREDITED}`).bind(credit.coins, credit.userId, ...key),
    ];
    if (credit.squadId !== null && (credit.xp > 0 || credit.sad)) {
      statements.push(
        this.d1
          .prepare(
            `UPDATE squads SET pet_xp = pet_xp + ?,
               last_sad_at = CASE WHEN ? = 1 THEN max(coalesce(last_sad_at, 0), ?) ELSE last_sad_at END
             WHERE id = ? AND EXISTS (SELECT 1 FROM users WHERE id = ?) AND ${UNCREDITED}`,
          )
          .bind(credit.xp, credit.sad ? 1 : 0, Math.floor(credit.endedAt), credit.squadId, credit.userId, ...key),
      );
    }
    statements.push(
      this.d1
        .prepare(
          `INSERT INTO focus_log (session_id, user_id, started_at, ended_at, squad_id, focused_sec, completed, coins, xp)
           SELECT ?, ?, ?, ?, (SELECT id FROM squads WHERE id = ?), ?, ?, ?, ?
           WHERE EXISTS (SELECT 1 FROM users WHERE id = ?) AND ${UNCREDITED}`,
        )
        .bind(...key, credit.endedAt, credit.squadId, credit.focusedSec, credit.completed ? 1 : 0, credit.coins, credit.xp, credit.userId, ...key),
    );
    return statements;
  }

  /**
   * Counts `day` for the squad's streak when enough members (half, rounded up, at least one)
   * finished a session of `streakMinMinutes` or more in it: one more than yesterday's count if
   * yesterday counted, else 1. Only once per day, and never for a day before the last counted one.
   */
  private streakStatement(write: StreakDayWrite): D1PreparedStatement {
    return this.d1
      .prepare(
        `UPDATE squads SET
           streak_count = CASE WHEN streak_last_day = ? THEN streak_count + 1 ELSE 1 END,
           streak_last_day = ?
         WHERE id = ? AND (streak_last_day IS NULL OR streak_last_day < ?)
           AND (SELECT count(DISTINCT f.user_id) FROM focus_log f JOIN squad_members m ON m.user_id = f.user_id
                JOIN users u ON u.id = f.user_id AND u.is_bot = 0
                WHERE m.squad_id = squads.id AND f.completed = 1 AND f.focused_sec >= ? AND f.ended_at >= ? AND f.ended_at < ?)
             >= max(1, (${SQUAD_PEOPLE.replace("pm.squad_id = ?", "pm.squad_id = squads.id")}) * ?)`,
      )
      .bind(write.yesterday, write.day, write.squadId, write.day, PET_RULES.streakMinMinutes * 60, write.start, write.end, PET_RULES.streakShare);
  }

  /**
   * M7: fills a one-day gap in the squad's streak with a Plus member's freeze. When the squad's last
   * counted day is the day before yesterday (of `check.day`), yesterday is frozen: a row in
   * `streak_freezes` naming the member whose freeze it was, and yesterday becomes the last counted
   * day, so the streak lives on with its count unchanged. The member is a person with Plus at
   * `check.now` who has used fewer than STREAK_FREEZES_PER_MONTH in yesterday's calendar month (in
   * any squad); the one with the most left, then the longest-standing. At most one gap per check,
   * and each check and write is one statement, so two checks racing can't freeze twice or overspend.
   */
  private freezeStatements(check: FreezeCheck): D1PreparedStatement[] {
    const gap = addDays(check.day, -1);
    const before = addDays(check.day, -2);
    const month = gap.slice(0, 7);
    const used = "(SELECT count(*) FROM streak_freezes f WHERE f.user_id = m.user_id AND substr(f.day, 1, 7) = ?)";
    return [
      this.d1
        .prepare(
          `INSERT OR IGNORE INTO streak_freezes (squad_id, day, user_id, used_at)
           SELECT m.squad_id, ?, m.user_id, ?
           FROM squad_members m JOIN users u ON u.id = m.user_id JOIN squads s ON s.id = m.squad_id
           WHERE m.squad_id = ? AND s.streak_last_day = ? AND s.streak_count > 0 AND u.is_bot = 0 AND u.plus_until > ?
             AND ${used} < ?
           ORDER BY ${used}, m.joined_at, m.user_id LIMIT 1`,
        )
        .bind(gap, Math.floor(check.now), check.squadId, before, Math.floor(check.now), month, STREAK_FREEZES_PER_MONTH, month),
      this.d1
        .prepare(
          `UPDATE squads SET streak_last_day = ?
           WHERE id = ? AND streak_last_day = ? AND EXISTS (SELECT 1 FROM streak_freezes WHERE squad_id = squads.id AND day = ?)`,
        )
        .bind(gap, check.squadId, before, gap),
    ];
  }

  private participantUpsert(p: ParticipantWrite): D1PreparedStatement {
    return this.d1
      .prepare(PARTICIPANT_UPSERT)
      .bind(p.sessionId, p.userId, p.state, p.plannedMin, p.startedAt, p.endsAt, p.pausedAt, p.endedAt, p.focusedSec, p.laToken, p.laEnv, p.slips);
  }

  private eventInsert(event: EventWrite): D1PreparedStatement {
    const meta = event.meta === undefined ? null : JSON.stringify(event.meta);
    return this.d1
      .prepare(EVENT_INSERT)
      .bind(event.sessionId, event.userId, event.type, Math.floor(event.at), meta, event.userId, event.userId);
  }
}
