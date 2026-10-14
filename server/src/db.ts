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
  now: number;
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
}

export interface SessionRow {
  id: string;
  squad_id: string | null;
  host_id: string | null;
  status: "open" | "ended";
  created_at: number;
  ended_at: number | null;
}

/** What the room knows of its squad: the name for `sq`, the pet, and today's activity for its mood. */
export interface SquadSnapshotRow {
  name: string;
  pet_species: string | null;
  pet_stage: number;
  pet_xp: number;
  /** Members now. */
  size: number;
  /** Members with a session since `since` that's running or completed (not left or slipped). */
  focused: number;
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
   * deleted with its codes.
   */
  async deleteUser(id: string): Promise<void> {
    await this.d1.batch([
      this.d1
        .prepare(
          `UPDATE squads SET owner_id = (
             SELECT m.user_id FROM squad_members m WHERE m.squad_id = squads.id AND m.user_id <> ?
             ORDER BY m.joined_at, m.user_id LIMIT 1)
           WHERE owner_id = ?`,
        )
        .bind(id, id),
      this.d1
        .prepare(
          `DELETE FROM invite_codes WHERE kind = 'squad'
             AND target_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
             AND NOT EXISTS (SELECT 1 FROM squad_members m WHERE m.squad_id = invite_codes.target_id AND m.user_id <> ?)`,
        )
        .bind(id, id),
      this.d1
        .prepare(
          `DELETE FROM squads WHERE id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
             AND NOT EXISTS (SELECT 1 FROM squad_members m WHERE m.squad_id = squads.id AND m.user_id <> ?)`,
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
    await this.d1
      .prepare(
        `INSERT INTO devices (id, user_id, apns_token, apns_env, push_to_start_token, la_enabled, frequent_pushes, tz, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (apns_token) DO UPDATE SET
           user_id = excluded.user_id,
           apns_env = excluded.apns_env,
           push_to_start_token = excluded.push_to_start_token,
           la_enabled = excluded.la_enabled,
           frequent_pushes = excluded.frequent_pushes,
           tz = excluded.tz,
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
        device.now,
      )
      .run();
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

  /** The squad's members, longest-standing first. */
  async membersOfSquad(squadId: string): Promise<SquadMemberRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT m.squad_id, u.id, u.handle, u.display_name, u.avatar_code, m.joined_at
         FROM squad_members m JOIN users u ON u.id = m.user_id
         WHERE m.squad_id = ? ORDER BY m.joined_at, u.id`,
      )
      .bind(squadId)
      .all<SquadMemberRow>();
    return results;
  }

  /** Members of every squad `userId` is in, longest-standing first within each squad. */
  async membersOfSquadsOf(userId: string): Promise<SquadMemberRow[]> {
    const { results } = await this.d1
      .prepare(
        `SELECT m.squad_id, u.id, u.handle, u.display_name, u.avatar_code, m.joined_at
         FROM squad_members m JOIN users u ON u.id = m.user_id
         WHERE m.squad_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?)
         ORDER BY m.joined_at, u.id`,
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

  /** How many squads the user is in, owned or not. */
  async squadCount(userId: string): Promise<number> {
    return (await this.d1.prepare("SELECT count(*) AS n FROM squad_members WHERE user_id = ?").bind(userId).first<number>("n")) ?? 0;
  }

  async squadSize(squadId: string): Promise<number> {
    return (await this.d1.prepare("SELECT count(*) AS n FROM squad_members WHERE squad_id = ?").bind(squadId).first<number>("n")) ?? 0;
  }

  /**
   * Creates a squad with its owner as the first member, unless the owner is already in `maxSquads`
   * squads: false then. Checked and written in one transaction, so two requests can't both slip
   * under the limit. A taken id throws D1's unique error on `squads.id`.
   */
  async insertSquad(squad: { id: string; name: string; ownerId: string; now: number; maxSquads: number }): Promise<boolean> {
    const [inserted] = await this.d1.batch([
      this.d1
        .prepare(
          `INSERT INTO squads (id, name, owner_id, created_at)
           SELECT ?, ?, ?, ? WHERE (SELECT count(*) FROM squad_members WHERE user_id = ?) < ?`,
        )
        .bind(squad.id, squad.name, squad.ownerId, squad.now, squad.ownerId, squad.maxSquads),
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
   * Adds the user to the squad unless they're in `maxSquads` squads already or it has `maxMembers`
   * members: false then. One statement, so the limits hold however many people join at once.
   * Already a member throws D1's unique error on `squad_members.squad_id`.
   */
  async joinSquad(join: { squadId: string; userId: string; now: number; maxSquads: number; maxMembers: number }): Promise<boolean> {
    const result = await this.d1
      .prepare(
        `INSERT INTO squad_members (squad_id, user_id, joined_at)
         SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM squads WHERE id = ?)
           AND (SELECT count(*) FROM squad_members WHERE user_id = ?) < ?
           AND (SELECT count(*) FROM squad_members WHERE squad_id = ?) < ?`,
      )
      .bind(join.squadId, join.userId, join.now, join.squadId, join.userId, join.maxSquads, join.squadId, join.maxMembers)
      .run();
    return result.meta.changes > 0;
  }

  /**
   * Takes the user out of the squad, in one transaction: the squad codes they made for it stop
   * working; if they owned it, it goes to the longest-standing member left; if nobody is left, the
   * squad and its codes are deleted. Not a member: nothing changes.
   */
  async leaveSquad(squadId: string, userId: string): Promise<void> {
    await this.d1.batch([
      this.d1.prepare("DELETE FROM squad_members WHERE squad_id = ? AND user_id = ?").bind(squadId, userId),
      this.d1.prepare("DELETE FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND created_by = ?").bind(squadId, userId),
      this.d1
        .prepare(
          `UPDATE squads SET owner_id = (
             SELECT user_id FROM squad_members WHERE squad_id = ? ORDER BY joined_at, user_id LIMIT 1)
           WHERE id = ? AND (owner_id = ? OR owner_id IS NULL)`,
        )
        .bind(squadId, squadId, userId),
      this.d1
        .prepare("DELETE FROM invite_codes WHERE kind = 'squad' AND target_id = ? AND NOT EXISTS (SELECT 1 FROM squad_members WHERE squad_id = ?)")
        .bind(squadId, squadId),
      this.d1.prepare("DELETE FROM squads WHERE id = ? AND NOT EXISTS (SELECT 1 FROM squad_members WHERE squad_id = ?)").bind(squadId, squadId),
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
   * has an open session.
   */
  async insertRoom(session: { id: string; squadId: string | null; hostId: string; createdAt: number }, host: ParticipantWrite, event: EventWrite): Promise<void> {
    await this.d1.batch([
      this.d1
        .prepare("INSERT INTO sessions (id, squad_id, host_id, status, created_at) VALUES (?, ?, ?, 'open', ?)")
        .bind(session.id, session.squadId, session.hostId, session.createdAt),
      this.participantUpsert(host),
      this.eventInsert(event),
    ]);
  }

  /** A member joining (or joining again): throws D1's unique error on `participants.user_id` when they have another open session. */
  async upsertParticipant(participant: ParticipantWrite, event: EventWrite): Promise<void> {
    await this.d1.batch([this.participantUpsert(participant), this.eventInsert(event)]);
  }

  /** The room's state since its last write, in one transaction. Rows of deleted users are skipped. */
  async syncRoom(sync: { participants: ParticipantWrite[]; ended?: { sessionId: string; endedAt: number }; events: EventWrite[] }): Promise<void> {
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
    if (statements.length > 0) await this.d1.batch(statements);
  }

  /**
   * The squad's name and pet, its size, and how many members focused since `since` (a session
   * that's running or completed). Null once the squad is gone.
   */
  squadSnapshot(squadId: string, since: number): Promise<SquadSnapshotRow | null> {
    return this.d1
      .prepare(
        `SELECT s.name, s.pet_species, s.pet_stage, s.pet_xp,
           (SELECT count(*) FROM squad_members m WHERE m.squad_id = s.id) AS size,
           (SELECT count(DISTINCT p.user_id) FROM participants p JOIN squad_members m ON m.user_id = p.user_id
              WHERE m.squad_id = s.id AND p.started_at >= ? AND p.state IN (0, 1, 2, 3)) AS focused
         FROM squads s WHERE s.id = ?`,
      )
      .bind(since, squadId)
      .first<SquadSnapshotRow>();
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
