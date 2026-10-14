// A thin typed layer over D1 (migrations/). Every query the routes run is here, so the SQL can be
// read in one place and the routes deal in rows, not statements.
//
// D1 has no BEGIN/COMMIT: statements that must happen together go through `batch`, which D1 runs as
// one transaction (all or nothing). D1 enforces foreign keys, so deleting a user cascades
// (migrations/0001_init.sql).

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

/** Whether `error` is D1 refusing a duplicate in `column` (e.g. `users.handle`). */
export function isUniqueViolation(error: unknown, column: string): boolean {
  return error instanceof Error && error.message.includes(`UNIQUE constraint failed: ${column}`);
}

const FRIEND_COLUMNS = "u.id, u.handle, u.display_name, u.avatar_code";

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
   * blocks (both directions), friend codes, squad memberships and reports about them; reports they
   * filed stay, with reporter_id set to NULL.
   */
  async deleteUser(id: string): Promise<void> {
    await this.d1.prepare("DELETE FROM users WHERE id = ?").bind(id).run();
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
}
