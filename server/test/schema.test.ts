// Applies migrations/ to an in-memory SQLite (Node's built-in node:sqlite, the same engine D1 runs)
// with foreign keys on, as D1 has them, and checks the constraints do their job.

import type { DatabaseSync } from "node:sqlite";
import { beforeEach, describe, expect, test } from "vitest";
import { migratedSQLite as migrated } from "./d1.ts";

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

  test("a session's end and its status agree", () => {
    const insert = "INSERT INTO sessions (id, host_id, status, created_at, ended_at) VALUES (?, 'Av4Nq8sT2b', ?, 1, ?)";
    expect(() => run(insert, "s1", "ended", null)).toThrow(/CHECK/);
    expect(() => run(insert, "s2", "open", 2)).toThrow(/CHECK/);
    expect(() => run(insert, "s3", "paused", null)).toThrow(/CHECK/);
    run(insert, "s4", "ended", 2);
  });
});
