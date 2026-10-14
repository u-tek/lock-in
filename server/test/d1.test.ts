// The node:sqlite stand-in for D1 behaves like D1 where src/ relies on it.

import { describe, expect, test } from "vitest";
import { TestD1, migrationFiles } from "./d1.ts";

describe("TestD1", () => {
  test("applies every migration in order", () => {
    expect(migrationFiles()).toEqual(["0001_init.sql", "0002_accounts.sql", "0003_squads.sql"]);
    const d1 = new TestD1();
    const tables = d1.sqlite.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as Array<{ name: string }>;
    expect(tables.map((row) => row.name)).toContain("auth_tokens");
  });

  test("first, all, run and raw", async () => {
    const d1 = new TestD1();
    const insert = d1.prepare("INSERT INTO users (id, apple_sub, created_at) VALUES (?, ?, ?)");
    const result = await insert.bind("Av4Nq8sT2b", "sub.ava", 1).run();
    expect(result.meta.changes).toBe(1);
    await insert.bind("Nr2Kx7pQ1m", "sub.noor", 2).run();

    const ava = await d1.prepare("SELECT id, avatar_code FROM users WHERE id = ?").bind("Av4Nq8sT2b").first();
    expect(ava).toEqual({ id: "Av4Nq8sT2b", avatar_code: "b0.c0.e0.h0" });
    expect(Object.getPrototypeOf(ava)).toBe(Object.prototype);
    expect(await d1.prepare("SELECT id FROM users WHERE id = ?").bind("Av4Nq8sT2b").first("id")).toBe("Av4Nq8sT2b");
    expect(await d1.prepare("SELECT id FROM users WHERE id = ?").bind("nobody0000").first()).toBeNull();

    const { results } = await d1.prepare("SELECT id FROM users ORDER BY created_at").all();
    expect(results).toEqual([{ id: "Av4Nq8sT2b" }, { id: "Nr2Kx7pQ1m" }]);
    expect(await d1.prepare("SELECT id, created_at FROM users ORDER BY created_at").raw()).toEqual([
      ["Av4Nq8sT2b", 1],
      ["Nr2Kx7pQ1m", 2],
    ]);

    const updated = await d1.prepare("UPDATE users SET coins = 5 WHERE id = ? RETURNING coins").bind("Av4Nq8sT2b").first();
    expect(updated).toEqual({ coins: 5 });
  });

  test("refuses undefined and turns booleans into 1/0, as D1 does", async () => {
    const d1 = new TestD1();
    expect(() => d1.prepare("SELECT ?").bind(undefined)).toThrow(/D1_TYPE_ERROR/);
    expect(await d1.prepare("SELECT ? AS yes, ? AS no").bind(true, false).first()).toEqual({ yes: 1, no: 0 });
  });

  test("errors read like D1's and foreign keys are enforced", async () => {
    const d1 = new TestD1();
    const insert = d1.prepare("INSERT INTO users (id, apple_sub, handle, created_at) VALUES (?, ?, ?, 1)");
    await insert.bind("Av4Nq8sT2b", "sub.ava", "ava").run();
    await expect(insert.bind("Nr2Kx7pQ1m", "sub.noor", "AVA").run()).rejects.toThrow(
      /^D1_ERROR: UNIQUE constraint failed: users\.handle: SQLITE_CONSTRAINT$/,
    );
    await expect(
      d1.prepare("INSERT INTO auth_tokens (token_hash, user_id, created_at, last_used_at) VALUES (?, 'nobody0000', 1, 1)").bind("a".repeat(64)).run(),
    ).rejects.toThrow(/FOREIGN KEY/);
  });

  test("a batch is one transaction: all or nothing", async () => {
    const d1 = new TestD1();
    const insert = (id: string) => d1.prepare("INSERT INTO users (id, apple_sub, created_at) VALUES (?, ?, 1)").bind(id, `sub.${id}`);
    await expect(d1.batch([insert("Av4Nq8sT2b"), insert("Av4Nq8sT2b")])).rejects.toThrow(/UNIQUE/);
    expect(d1.sqlite.prepare("SELECT count(*) AS n FROM users").get()).toEqual({ n: 0 });

    const results = await d1.batch([insert("Av4Nq8sT2b"), d1.prepare("SELECT count(*) AS n FROM users")]);
    expect(results[0]?.meta.changes).toBe(1);
    expect(results[1]?.results).toEqual([{ n: 1 }]);
  });
});
