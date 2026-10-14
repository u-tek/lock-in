// Applies migrations/ to an in-memory SQLite (Node's built-in node:sqlite, the same engine D1 runs)
// with foreign keys on, as D1 has them, and checks the constraints do their job.

import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { beforeEach, describe, expect, test } from "vitest";
import { migrationFiles, migratedSQLite as migrated } from "./d1.ts";

let db: DatabaseSync;
const run = (sql: string, ...params: Array<string | number | null>) => db.prepare(sql).run(...params);
const count = (sql: string, ...params: Array<string | number | null>) =>
  Number((db.prepare(sql).get(...params) as { n: number }).n);

function addUser(id: string, handle: string | null = null) {
  run("INSERT INTO users (id, apple_sub, handle, display_name, created_at) VALUES (?, ?, ?, ?, 1791900000)", id, `sub.${id}`, handle, "Ava");
}

beforeEach(() => {
  db = migrated();
  addUser("Av4Nq8sT2b", "ava");
  addUser("Nr2Kx7pQ1m", "noor");
});

describe("the D1 schema", () => {
  test("has every table in SPEC.md §4.6", () => {
    const tables = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").all() as Array<{ name: string }>).map(
      (row) => row.name,
    );
    expect(tables).toEqual(
      expect.arrayContaining([
        "blocks",
        "cosmetics",
        "devices",
        "events",
        "friendships",
        "invite_codes",
        "participants",
        "reports",
        "sessions",
        "squad_members",
        "squads",
        "users",
        "auth_tokens",
        "alerts",
        "focus_log",
      ]),
    );
  });

  test("handles are unique ignoring case; names are counted in code points", () => {
    expect(() => addUser("Ka9Lm3Vx0c", "AVA")).toThrow(/UNIQUE/);
    expect(() => run("UPDATE users SET display_name = ? WHERE id = 'Av4Nq8sT2b'", "🦊".repeat(12))).not.toThrow();
    expect(() => run("UPDATE users SET display_name = ? WHERE id = 'Av4Nq8sT2b'", "🦊".repeat(13))).toThrow(/CHECK/);
  });

  test("composite keys refuse duplicates", () => {
    run("INSERT INTO friendships (user_id, friend_id, created_at) VALUES ('Av4Nq8sT2b', 'Nr2Kx7pQ1m', 1)");
    expect(() => run("INSERT INTO friendships (user_id, friend_id, created_at) VALUES ('Av4Nq8sT2b', 'Nr2Kx7pQ1m', 2)")).toThrow(/UNIQUE|PRIMARY/);
    expect(() => run("INSERT INTO friendships (user_id, friend_id, created_at) VALUES ('Av4Nq8sT2b', 'Av4Nq8sT2b', 2)")).toThrow(/CHECK/);
    run("INSERT INTO cosmetics (user_id, item_id, acquired_at) VALUES ('Av4Nq8sT2b', 'hat.crown', 1)");
    expect(() => run("INSERT INTO cosmetics (user_id, item_id, acquired_at) VALUES ('Av4Nq8sT2b', 'hat.crown', 2)")).toThrow(/UNIQUE|PRIMARY/);
  });

  test("enums are checked", () => {
    expect(() => run("INSERT INTO invite_codes (code, kind, target_id, created_by) VALUES ('c1', 'party', 'x', 'Av4Nq8sT2b')")).toThrow(/CHECK/);
    run("INSERT INTO invite_codes (code, kind, target_id, created_by) VALUES ('c1', 'friend', 'Av4Nq8sT2b', 'Av4Nq8sT2b')");

    const device = "INSERT INTO devices (id, user_id, apns_token, apns_env, tz, updated_at) VALUES (?, 'Av4Nq8sT2b', ?, ?, 'Australia/Sydney', 1)";
    expect(() => run(device, "d1", "abcd", "development")).toThrow(/CHECK/);
    run(device, "d1", "abcd", "production");
    run(device, "d2", "ef01", "sandbox");
    expect(() => run(device, "d3", "abcd", "sandbox")).toThrow(/UNIQUE/);
  });

  test("participants keep the Live Activity's rules", () => {
    run("INSERT INTO sessions (id, host_id, created_at) VALUES ('r7Kq2xP9aL', 'Av4Nq8sT2b', 1791900000)");
    const join = "INSERT INTO participants (session_id, user_id, state, planned_min, started_at, ends_at, paused_at) VALUES ('r7Kq2xP9aL', ?, ?, ?, ?, ?, ?)";
    // REAL keeps fractional seconds exactly.
    run(join, "Av4Nq8sT2b", 2, 25, 1791900000.125, 1791901500.125, 1791900600.125);
    expect(db.prepare("SELECT paused_at FROM participants WHERE user_id = 'Av4Nq8sT2b'").get()).toEqual({ paused_at: 1791900600.125 });
    expect(() => run(join, "Nr2Kx7pQ1m", 6, 25, 1791900000, 1791901500, null)).toThrow(/CHECK/);
    expect(() => run(join, "Nr2Kx7pQ1m", 0, 241, 1791900000, 1791901500, null)).toThrow(/CHECK/);
    expect(() => run(join, "Nr2Kx7pQ1m", 2, 25, 1791900000, 1791901500, null)).toThrow(/CHECK/);
    expect(() => run(join, "Nr2Kx7pQ1m", 0, 25, 1791900000, 1791901500, 1791900600)).toThrow(/CHECK/);
    expect(() => run(join, "Nobody0000", 0, 25, 1791900000, 1791901500, null)).toThrow(/FOREIGN KEY/);
  });

  test("deleting a user removes what's theirs and keeps shared history", () => {
    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000001', 'Library Goblins', 'Av4Nq8sT2b', 1)");
    run("INSERT INTO squad_members (squad_id, user_id, joined_at) VALUES ('Sq00000001', 'Av4Nq8sT2b', 1), ('Sq00000001', 'Nr2Kx7pQ1m', 1)");
    run("INSERT INTO friendships (user_id, friend_id, created_at) VALUES ('Av4Nq8sT2b', 'Nr2Kx7pQ1m', 1), ('Nr2Kx7pQ1m', 'Av4Nq8sT2b', 1)");
    run("INSERT INTO sessions (id, squad_id, host_id, created_at) VALUES ('r7Kq2xP9aL', 'Sq00000001', 'Av4Nq8sT2b', 1)");
    run("INSERT INTO events (session_id, user_id, type, at, meta_json) VALUES ('r7Kq2xP9aL', 'Av4Nq8sT2b', 'join', 1, '{\"min\":25}')");
    expect(() => run("INSERT INTO events (type, at, meta_json) VALUES ('push', 1, '{nope')")).toThrow(/CHECK/);

    run("DELETE FROM users WHERE id = 'Av4Nq8sT2b'");
    expect(count("SELECT count(*) AS n FROM friendships")).toBe(0);
    expect(count("SELECT count(*) AS n FROM squad_members")).toBe(1);
    expect(count("SELECT count(*) AS n FROM events")).toBe(0);
    expect(db.prepare("SELECT owner_id FROM squads").get()).toEqual({ owner_id: null });
    expect(db.prepare("SELECT host_id, squad_id FROM sessions").get()).toEqual({ host_id: null, squad_id: "Sq00000001" });
  });

  test("0002: sessions, the Apple refresh token and report notes", () => {
    const token = "INSERT INTO auth_tokens (token_hash, user_id, created_at, last_used_at) VALUES (?, ?, 1, 1)";
    run(token, "a".repeat(64), "Av4Nq8sT2b");
    expect(() => run(token, "a".repeat(64), "Nr2Kx7pQ1m")).toThrow(/UNIQUE|PRIMARY/);
    expect(() => run(token, "short", "Nr2Kx7pQ1m")).toThrow(/CHECK/);
    expect(() => run(token, "b".repeat(64), "Nobody0000")).toThrow(/FOREIGN KEY/);
    run("UPDATE users SET apple_refresh_token = 'r.1' WHERE id = 'Av4Nq8sT2b'");

    const report = "INSERT INTO reports (id, reporter_id, target_user_id, reason, note, created_at) VALUES (?, ?, ?, 'other', ?, 1)";
    run(report, "Rp00000001", "Av4Nq8sT2b", "Nr2Kx7pQ1m", "x".repeat(500));
    expect(() => run(report, "Rp00000002", "Av4Nq8sT2b", "Nr2Kx7pQ1m", "x".repeat(501))).toThrow(/CHECK/);
    expect(() => run(report, "Rp00000003", "Av4Nq8sT2b", "Nr2Kx7pQ1m", "")).toThrow(/CHECK/);
    run(report, "Rp00000004", "Nr2Kx7pQ1m", "Av4Nq8sT2b", null);

    // Deleting Ava takes her sessions and the report about her; the one she filed stays, anonymised.
    run("DELETE FROM users WHERE id = 'Av4Nq8sT2b'");
    expect(count("SELECT count(*) AS n FROM auth_tokens")).toBe(0);
    expect(db.prepare("SELECT id, reporter_id FROM reports").all().map((row) => ({ ...row }))).toEqual([{ id: "Rp00000001", reporter_id: null }]);
  });

  test("0003: a Live Activity token and its APNs environment come together", () => {
    run("INSERT INTO sessions (id, host_id, created_at) VALUES ('r7Kq2xP9aL', 'Av4Nq8sT2b', 1)");
    const join = "INSERT INTO participants (session_id, user_id, planned_min, started_at, ends_at, la_token, la_env) VALUES ('r7Kq2xP9aL', ?, 25, 1, 2, ?, ?)";
    expect(() => run(join, "Av4Nq8sT2b", "abcd", null)).toThrow(/CHECK/);
    expect(() => run(join, "Av4Nq8sT2b", null, "sandbox")).toThrow(/CHECK/);
    expect(() => run(join, "Av4Nq8sT2b", "abcd", "development")).toThrow(/CHECK/);
    run(join, "Av4Nq8sT2b", "abcd", "production");
    run(join, "Nr2Kx7pQ1m", null, null);
    expect(() => run("UPDATE participants SET la_token = NULL WHERE user_id = 'Av4Nq8sT2b'")).toThrow(/CHECK/);
    run("UPDATE participants SET la_token = NULL, la_env = NULL WHERE user_id = 'Av4Nq8sT2b'");
  });

  test("0003: one running timer per user, one open room per squad", () => {
    run("INSERT INTO sessions (id, host_id, created_at) VALUES ('s1', 'Av4Nq8sT2b', 1), ('s2', 'Av4Nq8sT2b', 1), ('s3', 'Av4Nq8sT2b', 1)");
    const join = "INSERT INTO participants (session_id, user_id, planned_min, started_at, ends_at, ended_at) VALUES (?, 'Av4Nq8sT2b', 25, 1, 2, ?)";
    run(join, "s1", 2);
    run(join, "s2", null);
    expect(() => run(join, "s3", null)).toThrow(/UNIQUE constraint failed: participants\.user_id/);
    run(join, "s3", 2);

    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000001', 'Goblins', 'Av4Nq8sT2b', 1)");
    const open = "INSERT INTO sessions (id, squad_id, host_id, status, created_at, ended_at) VALUES (?, ?, 'Av4Nq8sT2b', ?, 1, ?)";
    run(open, "q1", "Sq00000001", "ended", 2);
    run(open, "q2", "Sq00000001", "open", null);
    expect(() => run(open, "q3", "Sq00000001", "open", null)).toThrow(/UNIQUE constraint failed: sessions\.squad_id/);
    // Solo sessions aren't a squad's: any number may be open.
    run(open, "q4", null, "open", null);
    run(open, "q5", null, "open", null);
  });

  test("0004 gives phones registered before it 22:00–07:00", () => {
    // Up to 0003, a phone; then 0004 over it, as `wrangler d1 migrations apply` would.
    const before = new DatabaseSync(":memory:");
    before.exec("PRAGMA foreign_keys = ON");
    const sql = (file: string) => readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8");
    for (const file of migrationFiles().filter((name) => name < "0004")) before.exec(sql(file));
    before.exec("INSERT INTO users (id, apple_sub, created_at) VALUES ('Av4Nq8sT2b', 'sub.ava', 1)");
    before.exec("INSERT INTO devices (id, user_id, apns_token, apns_env, tz, updated_at) VALUES ('d1', 'Av4Nq8sT2b', 'abcd', 'production', 'UTC', 1)");
    before.exec(sql("0004_invites.sql"));
    expect({ ...(before.prepare("SELECT quiet_start, quiet_end FROM devices").get() as object) }).toEqual({ quiet_start: 1320, quiet_end: 420 });
  });

  test("0004: quiet hours are whole minutes of a day, both or neither, never empty", () => {
    const device = "INSERT INTO devices (id, user_id, apns_token, apns_env, tz, updated_at, quiet_start, quiet_end) VALUES (?, 'Av4Nq8sT2b', ?, 'sandbox', 'UTC', 1, ?, ?)";
    run(device, "d1", "a1", 1320, 420);
    run(device, "d2", "a2", null, null);
    run(device, "d3", "a3", 0, 1439);
    expect(() => run(device, "d4", "a4", 1320, null)).toThrow(/CHECK/);
    expect(() => run(device, "d5", "a5", null, 420)).toThrow(/CHECK/);
    expect(() => run(device, "d6", "a6", 1440, 420)).toThrow(/CHECK/);
    expect(() => run(device, "d7", "a7", 1320, -1)).toThrow(/CHECK/);
    expect(() => run(device, "d8", "a8", 600, 600)).toThrow(/CHECK/);
    // Left out, they're 22:00–07:00.
    run("INSERT INTO devices (id, user_id, apns_token, apns_env, tz, updated_at) VALUES ('d9', 'Av4Nq8sT2b', 'a9', 'sandbox', 'UTC', 1)");
    expect({ ...(db.prepare("SELECT quiet_start, quiet_end FROM devices WHERE id = 'd9'").get() as object) }).toEqual({ quiet_start: 1320, quiet_end: 420 });
  });

  test("0004: alerts go with the accounts of whoever sent or got them", () => {
    addUser("Ka9Lm3Vx0c", "kai");
    const alert = "INSERT INTO alerts (recipient_id, squad_id, sender_id, session_id, sent_at) VALUES (?, 'Sq00000001', ?, 'r7Kq2xP9aL', 1)";
    run(alert, "Nr2Kx7pQ1m", "Av4Nq8sT2b");
    run(alert, "Ka9Lm3Vx0c", "Av4Nq8sT2b");
    run(alert, "Av4Nq8sT2b", "Ka9Lm3Vx0c");
    expect(() => run(alert, "Nobody0000", "Av4Nq8sT2b")).toThrow(/FOREIGN KEY/);
    expect(() => run("INSERT INTO alerts (recipient_id, squad_id, sender_id, session_id) VALUES ('Nr2Kx7pQ1m', 's', 'Av4Nq8sT2b', 'r')")).toThrow(/NOT NULL/);

    run("DELETE FROM users WHERE id = 'Nr2Kx7pQ1m'");
    expect(count("SELECT count(*) AS n FROM alerts")).toBe(2);
    run("DELETE FROM users WHERE id = 'Av4Nq8sT2b'");
    expect(count("SELECT count(*) AS n FROM alerts")).toBe(0);
    // The limits' queries use the index.
    const plan = db.prepare("EXPLAIN QUERY PLAN SELECT count(*) FROM alerts WHERE recipient_id = ? AND sent_at > ?").all("x", 1);
    expect(JSON.stringify(plan)).toContain("alerts_recipient");
  });

  test("0005 gives existing squads their owner's latest phone's zone, else UTC", () => {
    const before = new DatabaseSync(":memory:");
    before.exec("PRAGMA foreign_keys = ON");
    const sql = (file: string) => readFileSync(new URL(`../migrations/${file}`, import.meta.url), "utf8");
    for (const file of migrationFiles().filter((name) => name < "0005")) before.exec(sql(file));
    before.exec(`
      INSERT INTO users (id, apple_sub, created_at) VALUES ('Av4Nq8sT2b', 'sub.ava', 1), ('Nr2Kx7pQ1m', 'sub.noor', 1);
      INSERT INTO devices (id, user_id, apns_token, apns_env, tz, updated_at) VALUES
        ('d1', 'Av4Nq8sT2b', 'a1', 'production', 'Europe/London', 1),
        ('d2', 'Av4Nq8sT2b', 'a2', 'production', 'Australia/Sydney', 2);
      INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000001', 'Goblins', 'Av4Nq8sT2b', 1),
        ('Sq00000002', 'Owls', 'Nr2Kx7pQ1m', 1), ('Sq00000003', 'Orphans', NULL, 1);`);
    before.exec(sql("0005_pet.sql"));
    const squads = before.prepare("SELECT id, tz, hatched_at, last_sad_at, pet_species FROM squads ORDER BY id").all().map((row) => ({ ...row }));
    expect(squads).toEqual([
      { id: "Sq00000001", tz: "Australia/Sydney", hatched_at: null, last_sad_at: null, pet_species: null },
      { id: "Sq00000002", tz: "UTC", hatched_at: null, last_sad_at: null, pet_species: null },
      { id: "Sq00000003", tz: "UTC", hatched_at: null, last_sad_at: null, pet_species: null },
    ]);
    expect({ ...(before.prepare("SELECT coins_imported FROM users WHERE id = 'Av4Nq8sT2b'").get() as object) }).toEqual({ coins_imported: 0 });
  });

  test("0005: coins are imported at most once; focus_log holds one row per timer", () => {
    run("UPDATE users SET coins_imported = coins_imported + 1 WHERE id = 'Av4Nq8sT2b'");
    expect(() => run("UPDATE users SET coins_imported = coins_imported + 1 WHERE id = 'Av4Nq8sT2b'")).toThrow(/CHECK constraint failed: coins_imported/);

    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000001', 'Goblins', 'Av4Nq8sT2b', 1)");
    run("INSERT INTO sessions (id, squad_id, host_id, created_at) VALUES ('r7Kq2xP9aL', 'Sq00000001', 'Av4Nq8sT2b', 1)");
    const log = `INSERT INTO focus_log (session_id, user_id, started_at, ended_at, squad_id, focused_sec, completed, coins, xp)
      VALUES ('r7Kq2xP9aL', ?, ?, ?, 'Sq00000001', ?, ?, ?, ?)`;
    run(log, "Av4Nq8sT2b", 1791900000, 1791901500, 1500, 1, 30, 25);
    expect(() => run(log, "Av4Nq8sT2b", 1791900000, 1791901500, 1500, 1, 30, 25)).toThrow(/UNIQUE|PRIMARY/);
    run(log, "Av4Nq8sT2b", 1791901600, 1791901700, 100, 0, 1, 1);
    expect(() => run(log, "Nr2Kx7pQ1m", 1791900000, 1791899999, 0, 0, 0, 0)).toThrow(/CHECK/);
    expect(() => run(log, "Nr2Kx7pQ1m", 1791900000, 1791900001, 0, 2, 0, 0)).toThrow(/CHECK/);
    expect(() => run(log, "Nr2Kx7pQ1m", 1791900000, 1791900001, -1, 0, 0, 0)).toThrow(/CHECK/);
    expect(() => run(log, "Nobody0000", 1791900000, 1791900001, 0, 0, 0, 0)).toThrow(/FOREIGN KEY/);
    // Streaks and the leaderboard read it by user and time.
    const plan = db.prepare("EXPLAIN QUERY PLAN SELECT count(*) FROM focus_log WHERE user_id = ? AND ended_at >= ? AND ended_at < ?").all("x", 1, 2);
    expect(JSON.stringify(plan)).toContain("focus_log_user");

    // A squad that goes leaves its members' history, without it; an account that goes takes its own.
    run("DELETE FROM squads WHERE id = 'Sq00000001'");
    expect(count("SELECT count(*) AS n FROM focus_log WHERE squad_id IS NULL")).toBe(2);
    run("DELETE FROM users WHERE id = 'Av4Nq8sT2b'");
    expect(count("SELECT count(*) AS n FROM focus_log")).toBe(0);
  });

  test("0006: Demo Buddy is the one bot; Review Squads are flagged; the redemption log is just times", () => {
    expect(db.prepare("SELECT id, handle, is_bot, apple_sub FROM users WHERE is_bot = 1").all().map((row) => ({ ...row }))).toEqual([
      { id: "DemoBuddy0", handle: "demobuddy", is_bot: 1, apple_sub: null },
    ]);
    expect(count("SELECT count(*) AS n FROM users WHERE is_bot = 0")).toBe(2);
    expect(() => run("UPDATE users SET is_bot = 2 WHERE id = 'Av4Nq8sT2b'")).toThrow(/CHECK/);
    // Nobody else can have its handle, whatever the case.
    expect(() => run("UPDATE users SET handle = 'DemoBuddy' WHERE id = 'Av4Nq8sT2b'")).toThrow(/UNIQUE/);
    run("INSERT INTO squads (id, name, owner_id, created_at, review) VALUES ('Sq00000001', 'Review Squad', 'Av4Nq8sT2b', 1, 1)");
    expect(() => run("INSERT INTO squads (id, name, owner_id, created_at, review) VALUES ('Sq00000002', 'Goblins', 'Av4Nq8sT2b', 1, 2)")).toThrow(/CHECK/);
    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000003', 'Goblins', 'Av4Nq8sT2b', 1)");
    expect(count("SELECT count(*) AS n FROM squads WHERE review = 0")).toBe(1);
    run("INSERT INTO review_redemptions (at) VALUES (1)");
    const plan = db.prepare("EXPLAIN QUERY PLAN SELECT count(*) FROM review_redemptions WHERE at > ?").all(0);
    expect(JSON.stringify(plan)).toContain("review_redemptions_at");
  });

  test("0007: one freeze per squad per day, kept when its member goes; events once; accessories 1–99", () => {
    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000001', 'Goblins', 'Av4Nq8sT2b', 1)");
    const freeze = "INSERT INTO streak_freezes (squad_id, day, user_id, used_at) VALUES ('Sq00000001', ?, ?, 1)";
    run(freeze, "2026-10-15", "Av4Nq8sT2b");
    expect(() => run(freeze, "2026-10-15", "Nr2Kx7pQ1m")).toThrow(/UNIQUE|PRIMARY/);
    expect(() => run(freeze, "15/10/2026", "Nr2Kx7pQ1m")).toThrow(/CHECK/);
    expect(() => run(freeze, "2026-10-16", "Nobody0000")).toThrow(/FOREIGN KEY/);
    run("DELETE FROM users WHERE id = 'Av4Nq8sT2b'");
    expect({ ...(db.prepare("SELECT day, user_id FROM streak_freezes").get() as object) }).toEqual({ day: "2026-10-15", user_id: null });
    run("DELETE FROM squads WHERE id = 'Sq00000001'");
    expect(count("SELECT count(*) AS n FROM streak_freezes")).toBe(0);

    run("INSERT INTO squads (id, name, owner_id, created_at) VALUES ('Sq00000002', 'Owls', 'Nr2Kx7pQ1m', 1)");
    expect(() => run("UPDATE squads SET pet_accessory = 0")).toThrow(/CHECK/);
    expect(() => run("UPDATE squads SET pet_accessory = 100")).toThrow(/CHECK/);
    run("UPDATE squads SET pet_accessory = 6");
    run("UPDATE squads SET pet_accessory = NULL");

    run("INSERT INTO revenuecat_events (id, type, received_at) VALUES ('evt-1', 'RENEWAL', 1)");
    expect(() => run("INSERT INTO revenuecat_events (id, type, received_at) VALUES ('evt-1', 'RENEWAL', 2)")).toThrow(/UNIQUE|PRIMARY/);
    run("UPDATE users SET plus_event_ms = 1792000000000 WHERE id = 'Nr2Kx7pQ1m'");
  });

  test("0008: metrics are a day, an event and a total; the batch counter stops at its cap", () => {
    const add = "INSERT INTO metrics_daily (day, event, count) VALUES (?, ?, ?) ON CONFLICT (day, event) DO UPDATE SET count = count + excluded.count";
    run(add, "2026-10-14", "app.opened", 2);
    run(add, "2026-10-14", "app.opened", 3);
    run(add, "2026-10-15", "app.opened", 1);
    expect(count("SELECT count AS n FROM metrics_daily WHERE day = '2026-10-14'")).toBe(5);
    expect(() => run(add, "14/10/2026", "app.opened", 1)).toThrow(/CHECK/);
    expect(() => run(add, "2026-10-14", "x", 1)).toThrow(/CHECK/);
    expect(() => run(add, "2026-10-16", "app.opened", -1)).toThrow(/CHECK/);

    // The same statement as Database.reserveMetricsBatch: no change once the cap is reached.
    const reserve = "INSERT INTO metrics_batches (day, batches) VALUES (?, 1) ON CONFLICT (day) DO UPDATE SET batches = batches + 1 WHERE batches < ?";
    expect(Number(run(reserve, "2026-10-14", 2).changes)).toBe(1);
    expect(Number(run(reserve, "2026-10-14", 2).changes)).toBe(1);
    expect(Number(run(reserve, "2026-10-14", 2).changes)).toBe(0);
    expect(count("SELECT batches AS n FROM metrics_batches WHERE day = '2026-10-14'")).toBe(2);

    // Nothing in them refers to anyone, so deleting everyone leaves them as they are.
    run("DELETE FROM users WHERE is_bot = 0");
    expect(count("SELECT count(*) AS n FROM metrics_daily")).toBe(2);
  });

  test("a session's end and its status agree", () => {
    const insert = "INSERT INTO sessions (id, host_id, status, created_at, ended_at) VALUES (?, 'Av4Nq8sT2b', ?, 1, ?)";
    expect(() => run(insert, "s1", "ended", null)).toThrow(/CHECK/);
    expect(() => run(insert, "s2", "open", 2)).toThrow(/CHECK/);
    expect(() => run(insert, "s3", "paused", null)).toThrow(/CHECK/);
    run(insert, "s4", "ended", 2);
  });
});
