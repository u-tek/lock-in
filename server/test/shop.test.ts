// The coin shop, cosmetics, the one-off coins import and PATCH /me's ownership check (M5), through
// the whole Worker on a real (in-memory) D1.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { MAX_IMPORTED_COINS } from "../src/accounts.ts";
import { Database } from "../src/db.ts";
import { SHOP_ITEMS } from "../src/shop.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;
let ava: SignedIn;
let logs: string[];

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  app = await testApp();
  ava = await app.user("ava", "Ava");
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toMatch(/\b(ava|Ava)\b|hat\.|colour\.|body\.|eyes\./);
  }
});

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));
const setCoins = (who: SignedIn, coins: number) => app.sqlite.prepare("UPDATE users SET coins = ? WHERE id = ?").run(coins, who.user.id);
const coins = (who: SignedIn) => app.value("SELECT coins FROM users WHERE id = ?", who.user.id);
const plus = (who: SignedIn, until = T0 + 30 * 86_400) => app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(until, who.user.id);
const buy = (who: SignedIn, itemId: unknown) => call(who, "POST", "/shop/buy", { itemId });
const PLUS_ITEMS = SHOP_ITEMS.filter((item) => item.plus).map((item) => item.id);

describe("GET /shop", () => {
  test("the catalogue, to anyone", async () => {
    expect(await read(await app.request("GET", "/shop"))).toEqual({ status: 200, body: { items: SHOP_ITEMS } });
    expect(SHOP_ITEMS).toContainEqual({ id: "hat.1", part: "hat", option: 1, price: 80, plus: false });
  });
});

describe("POST /shop/buy", () => {
  test("takes the price and adds the item", async () => {
    setCoins(ava, 100);
    expect(await buy(ava, "hat.1")).toEqual({ status: 200, body: { coins: 20, owned: ["hat.1"] } });
    expect(await buy(ava, "colour.1")).toEqual({ status: 402, body: { error: expect.any(String), code: "not_enough_coins" } });
    setCoins(ava, 60);
    expect((await buy(ava, "colour.1")).body).toEqual({ coins: 20, owned: ["colour.1", "hat.1"] });
    expect((await call(ava, "GET", "/me")).body.user.coins).toBe(20);
    expect(logs).toContain("shop: bought an item");
  });

  test("errors: 404 item_not_found, 409 already_owned, 402 not_enough_coins, 402 plus_required", async () => {
    setCoins(ava, 1000);
    for (const itemId of ["hat.0", "hat.99", "crown", ""]) {
      expect(await buy(ava, itemId), itemId).toEqual({ status: 404, body: { error: expect.any(String), code: "item_not_found" } });
    }
    expect((await buy(ava, 7)).status).toBe(400);
    await buy(ava, "body.3");
    expect(await buy(ava, "body.3")).toEqual({ status: 409, body: { error: expect.any(String), code: "already_owned" } });
    expect(await buy(ava, "hat.5")).toEqual({ status: 402, body: { error: expect.any(String), code: "plus_required" } });
    setCoins(ava, 79);
    expect(await buy(ava, "hat.1")).toEqual({ status: 402, body: { error: expect.any(String), code: "not_enough_coins" } });
    expect(coins(ava)).toBe(79);
    expect(app.count("SELECT count(*) FROM cosmetics")).toBe(1);
  });

  test("Plus items are yours while Plus lasts, and never bought", async () => {
    plus(ava);
    expect((await buy(ava, "hat.5")).body.code).toBe("already_owned");
    expect((await call(ava, "GET", "/me/cosmetics")).body).toEqual({ owned: PLUS_ITEMS });
    plus(ava, T0);
    expect((await call(ava, "GET", "/me/cosmetics")).body).toEqual({ owned: [] });
    expect(app.count("SELECT count(*) FROM cosmetics")).toBe(0);
  });

  test("two purchases racing: the database keeps the coins and the item straight", async () => {
    setCoins(ava, 100);
    const db = new Database(app.env.DB);
    expect(await db.buyItem(ava.user.id, "hat.1", 80, T0)).toBe(20);
    // The second got past the route's checks with the old balance: too few coins now.
    await expect(db.buyItem(ava.user.id, "hat.3", 100, T0)).rejects.toThrow(/CHECK constraint failed: coins/);
    // …or for an item it already has.
    setCoins(ava, 500);
    await expect(db.buyItem(ava.user.id, "hat.1", 80, T0)).rejects.toThrow(/UNIQUE constraint failed: cosmetics\.user_id/);
    expect(coins(ava)).toBe(500);
    expect(app.count("SELECT count(*) FROM cosmetics")).toBe(1);
  });
});

describe("GET /me/cosmetics", () => {
  test("what you bought, in catalogue order; defaults aren't listed", async () => {
    expect((await call(ava, "GET", "/me/cosmetics")).body).toEqual({ owned: [] });
    setCoins(ava, 500);
    await buy(ava, "hat.3");
    await buy(ava, "body.1");
    expect(await call(ava, "GET", "/me/cosmetics")).toEqual({ status: 200, body: { owned: ["body.1", "hat.3"] } });
    expect((await read(await app.request("GET", "/me/cosmetics"))).status).toBe(401);
  });
});

describe("POST /me/coins/import", () => {
  test("brings over coins and free items once; 409 already_imported after", async () => {
    setCoins(ava, 12);
    const imported = await call(ava, "POST", "/me/coins/import", { coins: 140, owned: ["hat.1", "colour.2", "hat.1"] });
    expect(imported.status).toBe(200);
    expect(imported.body.user).toMatchObject({ id: ava.user.id, coins: 152 });
    expect(imported.body.owned).toEqual(["colour.2", "hat.1"]);
    expect(await call(ava, "POST", "/me/coins/import", { coins: 140, owned: ["hat.3"] })).toEqual({
      status: 409,
      body: { error: expect.any(String), code: "already_imported" },
    });
    expect(coins(ava)).toBe(152);
    expect((await call(ava, "GET", "/me/cosmetics")).body.owned).toEqual(["colour.2", "hat.1"]);
  });

  test("coins are capped; only free items that exist come over; ones you have are kept", async () => {
    setCoins(ava, 200);
    await buy(ava, "hat.1");
    const imported = await call(ava, "POST", "/me/coins/import", { coins: 1_000_000, owned: ["hat.1", "hat.5", "hat.0", "hat.99", "eyes.4", "nonsense"] });
    expect(imported.body.user.coins).toBe(120 + MAX_IMPORTED_COINS);
    expect(imported.body.owned).toEqual(["eyes.4", "hat.1"]);
  });

  test("nothing to bring over still counts as the import", async () => {
    expect((await call(ava, "POST", "/me/coins/import", { coins: 0, owned: [] })).status).toBe(200);
    expect((await call(ava, "POST", "/me/coins/import", { coins: 5, owned: [] })).body.code).toBe("already_imported");
  });

  test("422 import_invalid for anything but a whole number of coins and a list of ids", async () => {
    for (const body of [{ coins: -1, owned: [] }, { coins: 2.5, owned: [] }, { coins: "5", owned: [] }, { owned: [] }, { coins: 5 }, { coins: 5, owned: [7] }, { coins: 5, owned: "hat.1" }, { coins: 5, owned: Array(101).fill("hat.1") }]) {
      expect(await call(ava, "POST", "/me/coins/import", body), JSON.stringify(body)).toEqual({ status: 422, body: { error: expect.any(String), code: "import_invalid" } });
    }
    expect(app.value("SELECT coins_imported FROM users WHERE id = ?", ava.user.id)).toBe(0);
  });

  test("two imports racing: the database lets one through", async () => {
    const db = new Database(app.env.DB);
    await db.importCoins(ava.user.id, 10, ["hat.1"], T0);
    await expect(db.importCoins(ava.user.id, 10, ["hat.3"], T0)).rejects.toThrow(/CHECK constraint failed: coins_imported/);
    expect(coins(ava)).toBe(10);
    expect(app.count("SELECT count(*) FROM cosmetics")).toBe(1);
  });
});

describe("PATCH /me avatarCode", () => {
  const patch = (avatarCode: string) => call(ava, "PATCH", "/me", { avatarCode });

  test("defaults are always yours; other parts once you own them", async () => {
    expect((await patch("b0.c0.e0.h0")).status).toBe(200);
    expect(await patch("b0.c0.e0.h1")).toEqual({ status: 403, body: { error: expect.any(String), code: "item_not_owned", itemId: "hat.1" } });
    expect(app.value("SELECT avatar_code FROM users WHERE id = ?", ava.user.id)).toBe("b0.c0.e0.h0");
    setCoins(ava, 80);
    await buy(ava, "hat.1");
    expect((await patch("b0.c0.e0.h1")).body.user.avatarCode).toBe("b0.c0.e0.h1");
    // Options the catalogue doesn't have can't be owned.
    expect((await patch("b0.c0.e0.h99")).body).toMatchObject({ code: "item_not_owned", itemId: "hat.99" });
  });

  test("Plus parts need Plus", async () => {
    expect((await patch("b4.c0.e0.h0")).body).toMatchObject({ code: "item_not_owned", itemId: "body.4" });
    plus(ava);
    expect((await patch("b4.c7.e3.h5")).status).toBe(200);
  });

  test("a code saved before the shop is left alone: parts you're wearing stay yours", async () => {
    app.sqlite.prepare("UPDATE users SET avatar_code = 'b2.c5.e1.h4' WHERE id = ?").run(ava.user.id);
    // Changing the colour back to the default keeps the rest.
    expect((await patch("b2.c0.e1.h4")).status).toBe(200);
    // But a part taken off can't come back unbought.
    expect((await patch("b2.c5.e1.h4")).body).toMatchObject({ code: "item_not_owned", itemId: "colour.5" });
    // Other changes to the profile don't touch the code at all.
    expect((await call(ava, "PATCH", "/me", { displayName: "Avery" })).body.user.avatarCode).toBe("b2.c0.e1.h4");
  });
});
