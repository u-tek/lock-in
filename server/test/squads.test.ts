// Squads through the whole Worker, on a real (in-memory) D1.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { FRIEND_CODE_ALPHABET } from "../src/context.ts";
import { EXPIRED_CODE_RETENTION_SECONDS, FRIEND_CODE_LIFETIME_SECONDS } from "../src/friends.ts";
import { PET_RULES } from "../src/pet.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;
let ava: SignedIn;
let noor: SignedIn;
let kai: SignedIn;
let logs: string[];

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  app = await testApp();
  ava = await app.user("ava", "Ava");
  noor = await app.user("noor", "Noor");
  kai = await app.user("kai", "Kai");
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toMatch(/\b(ava|noor|kai|Ava|Noor|Kai|Goblins)\b/);
  }
});

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));
const create = async (who: SignedIn, name = "Library Goblins") => call(who, "POST", "/squads", { name });
const codeFor = async (who: SignedIn, squadId: string) => (await call(who, "POST", `/squads/${squadId}/invite`)).body.code as string;
const plus = (who: SignedIn, until = T0 + 30 * 86_400) => app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(until, who.user.id);

/** `owner`'s new squad, with `members` joined in order a second apart. */
async function squadWith(owner: SignedIn, ...members: SignedIn[]): Promise<string> {
  const id = (await create(owner)).body.squad.id as string;
  const code = await codeFor(owner, id);
  for (const member of members) {
    app.clock.now += 1;
    const joined = await call(member, "POST", `/squads/join/${code}`);
    expect(joined.status, JSON.stringify(joined.body)).toBe(200);
  }
  return id;
}

const memberView = (who: SignedIn, joinedAt: number) => ({
  id: who.user.id,
  handle: who.user.handle,
  displayName: who.user.displayName,
  avatarCode: "b0.c0.e0.h0",
  joinedAt,
  isBot: false,
});

describe("POST /squads", () => {
  test("creates a squad with you as owner and only member", async () => {
    const { status, body } = await create(ava, "  Library Goblins ");
    expect(status).toBe(200);
    expect(body).toEqual({
      squad: {
        id: expect.stringMatching(/^[0-9A-Za-z]{10}$/),
        name: "Library Goblins",
        ownerId: ava.user.id,
        members: [memberView(ava, T0)],
        openSessionId: null,
        muted: false,
        // M5: an egg (its species kept back until it hatches), hungry, and no streak yet.
        pet: { species: expect.any(String), stage: 0, xp: 0, mood: 1, progress: 0, accessory: null },
        // M7: no frozen days, and no freezes without Plus.
        streak: { count: 0, countedToday: false, doneToday: 0, needed: 1, frozenDays: [], freezes: 0 },
        tz: "UTC",
        boosted: false,
      },
    });
    // The species is picked now, so the egg has its colour.
    expect(PET_RULES.species).toContain(app.value("SELECT pet_species FROM squads"));
    expect(logs).toContain("squads: created");
  });

  test("names follow the display-name rules, up to 20 code points", async () => {
    expect((await create(ava, "🔒".repeat(20))).status).toBe(200);
    plus(noor);
    for (const name of ["", "   ", "x".repeat(21), "🔒".repeat(21), "tab\there"]) {
      expect(await create(noor, name), JSON.stringify(name)).toEqual({ status: 422, body: { error: expect.any(String), code: "name_invalid" } });
    }
    expect((await call(noor, "POST", "/squads", { name: 42 })).body.code).toBe("name_invalid");
    expect((await call(noor, "POST", "/squads", {})).body.code).toBe("name_invalid");
    expect((await create(noor, "Lockin Official")).body.code).toBe("name_not_allowed");
    expect(app.count("SELECT count(*) FROM squads")).toBe(1);
  });

  test("free: one squad; Plus: three. 402 plus_required with limit squads", async () => {
    expect((await create(ava)).status).toBe(200);
    expect(await create(ava)).toEqual({ status: 402, body: { error: expect.any(String), code: "plus_required", limit: "squads" } });

    plus(ava);
    expect((await create(ava, "Two")).status).toBe(200);
    expect((await create(ava, "Three")).status).toBe(200);
    expect((await create(ava, "Four")).body).toMatchObject({ code: "plus_required", limit: "squads" });
    // Lapsed Plus keeps its squads but can't add another.
    plus(ava, T0);
    expect((await create(ava, "Four")).body.code).toBe("plus_required");
    expect((await call(ava, "GET", "/squads")).body.squads).toHaveLength(3);
  });

  test("being in someone else's squad counts towards the limit", async () => {
    await squadWith(ava, noor);
    expect((await create(noor)).body).toMatchObject({ code: "plus_required", limit: "squads" });
  });
});

describe("GET /squads", () => {
  test("your squads, first joined first, members longest-standing first, with the open room", async () => {
    plus(noor);
    const first = await squadWith(ava, noor, kai);
    app.clock.now += 10;
    const second = (await create(noor, "Night Owls")).body.squad.id;
    const { body } = await call(noor, "GET", "/squads");
    expect(body.squads.map((squad: { id: string }) => squad.id)).toEqual([first, second]);
    expect(body.squads[0]).toEqual({
      id: first,
      name: "Library Goblins",
      ownerId: ava.user.id,
      members: [memberView(ava, T0), memberView(noor, T0 + 1), memberView(kai, T0 + 2)],
      openSessionId: null,
      muted: false,
      pet: { species: expect.any(String), stage: 0, xp: 0, mood: 1, progress: 0, accessory: null },
      // Noor has Plus: the squad is boosted (M7), and she has her two freezes.
      streak: { count: 0, countedToday: false, doneToday: 0, needed: 2, frozenDays: [], freezes: 2 },
      tz: "UTC",
      boosted: true,
    });
    expect(body.squads[1].members.map((member: { id: string }) => member.id)).toEqual([noor.user.id]);

    const sid = (await call(kai, "POST", "/sessions", { squadId: first, minutes: 25 })).body.session.id;
    expect((await call(ava, "GET", "/squads")).body.squads[0].openSessionId).toBe(sid);
    expect((await call(kai, "GET", "/squads")).body.squads).toHaveLength(1);
  });

  test("none yet: an empty list", async () => {
    expect(await call(ava, "GET", "/squads")).toEqual({ status: 200, body: { squads: [] } });
  });
});

describe("PATCH /squads/:id", () => {
  test("the owner renames it; anyone else can't", async () => {
    const id = await squadWith(ava, noor);
    const renamed = await call(ava, "PATCH", `/squads/${id}`, { name: " Night Owls " });
    expect(renamed.status).toBe(200);
    expect(renamed.body.squad.name).toBe("Night Owls");
    expect(await call(noor, "PATCH", `/squads/${id}`, { name: "Mine now" })).toEqual({ status: 403, body: { error: expect.any(String), code: "not_owner" } });
    expect((await call(kai, "PATCH", `/squads/${id}`, { name: "Mine now" })).body.code).toBe("not_member");
    expect((await call(ava, "PATCH", `/squads/${id}`, { name: "x".repeat(21) })).body.code).toBe("name_invalid");
    expect((await call(ava, "PATCH", "/squads/Zz00000000", { name: "Hi" })).body.code).toBe("not_member");
    expect(app.value("SELECT name FROM squads WHERE id = ?", id)).toBe("Night Owls");
  });
});

describe("POST /squads/:id/invite", () => {
  test("a week-long squad code, the same one until it expires, per member", async () => {
    const id = await squadWith(ava, noor);
    const { status, body } = await call(ava, "POST", `/squads/${id}/invite`);
    expect(status).toBe(200);
    expect(body).toEqual({
      code: expect.stringMatching(new RegExp(`^[${FRIEND_CODE_ALPHABET}]{8}$`)),
      url: `https://lockin-api.example.workers.dev/j/${body.code}`,
      // squadWith made it, before Noor joined.
      expiresAt: T0 + FRIEND_CODE_LIFETIME_SECONDS,
    });
    expect({ ...(app.sqlite.prepare("SELECT kind, target_id, created_by FROM invite_codes WHERE code = ?").get(body.code) as object) }).toEqual({
      kind: "squad",
      target_id: id,
      created_by: ava.user.id,
    });
    expect((await call(ava, "POST", `/squads/${id}/invite`)).body).toEqual(body);
    // Noor gets her own.
    expect((await call(noor, "POST", `/squads/${id}/invite`)).body.code).not.toBe(body.code);

    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS + 10;
    const next = (await call(ava, "POST", `/squads/${id}/invite`)).body;
    expect(next.code).not.toBe(body.code);
    app.clock.now += EXPIRED_CODE_RETENTION_SECONDS + 10;
    await call(ava, "POST", `/squads/${id}/invite`);
    expect(app.count("SELECT count(*) FROM invite_codes WHERE code = ?", body.code)).toBe(0);
  });

  test("403 not_member for a squad you're not in", async () => {
    const id = await squadWith(ava);
    expect(await call(noor, "POST", `/squads/${id}/invite`)).toEqual({ status: 403, body: { error: expect.any(String), code: "not_member" } });
    expect((await call(noor, "POST", "/squads/nope/invite")).body.code).toBe("not_member");
  });
});

describe("POST /squads/join/:code", () => {
  test("joins the squad, however the code is typed", async () => {
    const id = await squadWith(ava);
    const code = await codeFor(ava, id);
    app.clock.now += 1;
    const joined = await call(noor, "POST", `/squads/join/${code.slice(0, 4).toLowerCase()}-${code.slice(4)}`);
    expect(joined.status).toBe(200);
    expect(joined.body.squad.members.map((member: { id: string }) => member.id)).toEqual([ava.user.id, noor.user.id]);
    expect(joined.body.squad.muted).toBe(false);
    expect(await call(noor, "POST", `/squads/join/${code}`)).toEqual({ status: 409, body: { error: expect.any(String), code: "already_member" } });
    expect((await call(ava, "POST", `/squads/join/${code}`)).body.code).toBe("already_member");
  });

  test("404 for unknown codes, 410 for expired ones, 422 friend_code for a friend code", async () => {
    const id = await squadWith(ava);
    const code = await codeFor(ava, id);
    for (const unknown of ["ZZZZZZZZ", "abc", "%E0%A4%A"]) {
      expect(await call(noor, "POST", `/squads/join/${unknown}`), unknown).toEqual({ status: 404, body: { error: expect.any(String), code: "code_not_found" } });
    }
    const friendCode = (await call(kai, "POST", "/friends/code")).body.code;
    expect(await call(noor, "POST", `/squads/join/${friendCode}`)).toEqual({ status: 422, body: { error: expect.any(String), code: "friend_code" } });
    // And the friends route still says a squad code isn't a friend code (M2).
    expect((await call(noor, "POST", `/friends/redeem/${code}`)).body.code).toBe("code_not_found");

    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS;
    expect(await call(noor, "POST", `/squads/join/${code}`)).toEqual({ status: 410, body: { error: expect.any(String), code: "code_expired" } });
  });

  test("403 blocked when anyone in the squad blocked you, or you them", async () => {
    const id = await squadWith(ava, noor);
    const code = await codeFor(ava, id);
    await call(noor, "POST", "/blocks", { userId: kai.user.id });
    expect(await call(kai, "POST", `/squads/join/${code}`)).toEqual({ status: 403, body: { error: expect.any(String), code: "blocked" } });
    await call(noor, "DELETE", `/blocks/${kai.user.id}`);
    await call(kai, "POST", "/blocks", { userId: ava.user.id });
    expect((await call(kai, "POST", `/squads/join/${code}`)).body.code).toBe("blocked");
    await call(kai, "DELETE", `/blocks/${ava.user.id}`);
    expect((await call(kai, "POST", `/squads/join/${code}`)).status).toBe(200);
  });

  test("free squads hold 4; a Plus owner's 6; 402 plus_required with limit members", async () => {
    const id = await squadWith(ava, noor, kai);
    const code = await codeFor(ava, id);
    const mila = await app.user("mila");
    const omar = await app.user("omar");
    expect((await call(mila, "POST", `/squads/join/${code}`)).status).toBe(200);
    expect(await call(omar, "POST", `/squads/join/${code}`)).toEqual({ status: 402, body: { error: expect.any(String), code: "plus_required", limit: "members" } });

    plus(ava);
    expect((await call(omar, "POST", `/squads/join/${code}`)).status).toBe(200);
    const zed = await app.user("zed");
    const yui = await app.user("yui");
    expect((await call(zed, "POST", `/squads/join/${code}`)).status).toBe(200);
    expect((await call(yui, "POST", `/squads/join/${code}`)).body).toMatchObject({ code: "plus_required", limit: "members" });
    plus(yui);
    // Plus doesn't go past 6.
    expect((await call(yui, "POST", `/squads/join/${code}`)).body).toMatchObject({ code: "plus_required", limit: "members" });
    expect(app.count("SELECT count(*) FROM squad_members WHERE squad_id = ?", id)).toBe(6);
  });

  test("a Plus joiner can be the fifth in a free owner's squad", async () => {
    const id = await squadWith(ava, noor, kai);
    const code = await codeFor(ava, id);
    await call(await app.user("mila"), "POST", `/squads/join/${code}`);
    const omar = await app.user("omar");
    plus(omar);
    expect((await call(omar, "POST", `/squads/join/${code}`)).status).toBe(200);
  });

  test("402 plus_required with limit squads when you're in your one free squad", async () => {
    const id = await squadWith(ava);
    await create(noor, "Night Owls");
    expect(await call(noor, "POST", `/squads/join/${await codeFor(ava, id)}`)).toEqual({
      status: 402,
      body: { error: expect.any(String), code: "plus_required", limit: "squads" },
    });
  });

  test("joining at the same moment can't overfill a squad", async () => {
    const id = await squadWith(ava, noor);
    const code = await codeFor(ava, id);
    const people = await Promise.all(["mila", "omar", "zed"].map((handle) => app.user(handle)));
    const results = await Promise.all(people.map((person) => call(person, "POST", `/squads/join/${code}`)));
    expect(results.map((result) => result.status).sort()).toEqual([200, 200, 402]);
    expect(app.count("SELECT count(*) FROM squad_members WHERE squad_id = ?", id)).toBe(4);
  });

  test("a code for a squad that's gone is not found", async () => {
    const id = await squadWith(ava, noor);
    const code = await codeFor(noor, id);
    // Noor leaving takes her code with her.
    await call(noor, "DELETE", `/squads/${id}/members/me`);
    expect((await call(kai, "POST", `/squads/join/${code}`)).body.code).toBe("code_not_found");
    const avas = await codeFor(ava, id);
    await call(ava, "DELETE", `/squads/${id}/members/me`);
    expect((await call(kai, "POST", `/squads/join/${avas}`)).body.code).toBe("code_not_found");
  });
});

describe("PATCH /squads/:id/members/me", () => {
  test("mutes and unmutes the squad for you only", async () => {
    const id = await squadWith(ava, noor);
    const muted = await call(noor, "PATCH", `/squads/${id}/members/me`, { muted: true });
    expect(muted.status).toBe(200);
    expect(muted.body.squad.muted).toBe(true);
    expect((await call(ava, "GET", "/squads")).body.squads[0].muted).toBe(false);
    expect(app.value("SELECT muted FROM squad_members WHERE squad_id = ? AND user_id = ?", id, noor.user.id)).toBe(1);
    expect((await call(noor, "PATCH", `/squads/${id}/members/me`, { muted: false })).body.squad.muted).toBe(false);

    expect((await call(noor, "PATCH", `/squads/${id}/members/me`, { muted: "yes" })).status).toBe(400);
    expect((await call(kai, "PATCH", `/squads/${id}/members/me`, { muted: true })).body.code).toBe("not_member");
  });
});

describe("DELETE /squads/:id/members/me", () => {
  test("a member leaves", async () => {
    const id = await squadWith(ava, noor, kai);
    expect((await call(kai, "DELETE", `/squads/${id}/members/me`)).status).toBe(204);
    expect((await call(ava, "GET", "/squads")).body.squads[0].members.map((member: { id: string }) => member.id)).toEqual([ava.user.id, noor.user.id]);
    expect((await call(kai, "GET", "/squads")).body.squads).toEqual([]);
    // Not in it (any more), or no such squad: already done.
    expect((await call(kai, "DELETE", `/squads/${id}/members/me`)).status).toBe(204);
    expect((await call(kai, "DELETE", "/squads/nope/members/me")).status).toBe(204);
  });

  test("the owner leaving hands the squad to the longest-standing member", async () => {
    const id = await squadWith(ava, noor, kai);
    await call(ava, "DELETE", `/squads/${id}/members/me`);
    expect(app.value("SELECT owner_id FROM squads WHERE id = ?", id)).toBe(noor.user.id);
    expect((await call(noor, "PATCH", `/squads/${id}`, { name: "Noor's now" })).status).toBe(200);
  });

  test("the last one out deletes the squad and its codes", async () => {
    const id = await squadWith(ava, noor);
    await codeFor(ava, id);
    await codeFor(noor, id);
    await call(ava, "DELETE", `/squads/${id}/members/me`);
    await call(noor, "DELETE", `/squads/${id}/members/me`);
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
    expect(app.count("SELECT count(*) FROM invite_codes WHERE kind = 'squad'")).toBe(0);
    // And frees the place: Noor can make her own.
    expect((await create(noor)).status).toBe(200);
  });

  test("leaving doesn't end your session in the squad's room", async () => {
    const id = await squadWith(ava, noor);
    const sid = (await call(noor, "POST", "/sessions", { squadId: id, minutes: 25 })).body.session.id;
    await call(noor, "DELETE", `/squads/${id}/members/me`);
    expect((await call(noor, "POST", `/sessions/${sid}/pause`)).status).toBe(200);
  });
});

describe("DELETE /me", () => {
  test("hands each squad you own to its longest-standing member, and deletes those only you were in", async () => {
    plus(ava);
    plus(noor);
    const shared = await squadWith(ava, noor, kai);
    const alone = (await create(ava, "Just Me")).body.squad.id;
    const theirs = await squadWith(noor);
    await call(ava, "POST", `/squads/join/${await codeFor(noor, theirs)}`);
    await codeFor(ava, shared);
    await codeFor(ava, alone);

    expect((await app.request("DELETE", "/me", { token: ava.token })).status).toBe(204);
    expect(app.value("SELECT owner_id FROM squads WHERE id = ?", shared)).toBe(noor.user.id);
    expect(app.count("SELECT count(*) FROM squads WHERE id = ?", alone)).toBe(0);
    expect(app.value("SELECT owner_id FROM squads WHERE id = ?", theirs)).toBe(noor.user.id);
    expect(app.count("SELECT count(*) FROM squad_members WHERE user_id = ?", ava.user.id)).toBe(0);
    // Ava's codes went with her; Noor's for her own squad stays.
    expect(app.count("SELECT count(*) FROM invite_codes WHERE created_by = ? OR target_id = ?", ava.user.id, alone)).toBe(0);
    expect(app.count("SELECT count(*) FROM invite_codes WHERE kind = 'squad'")).toBe(1);
    expect((await call(noor, "GET", "/squads")).body.squads.map((squad: { members: unknown[] }) => squad.members.length)).toEqual([2, 1]);
  });
});

describe("GET /j/:code for a squad code", () => {
  test("invites you to the squad by name, escaped, and nothing about its members", async () => {
    const id = (await create(ava, `<b>"Goblins"</b>`)).body.squad.id;
    const code = await codeFor(ava, id);
    const response = await app.request("GET", `/j/${code}`);
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).toContain("<h1>Join &#60;b&#62;&#34;Goblins&#34;&#60;/b&#62; on Lockin</h1>");
    expect(text).toContain(`<a class="button" href="lockin://j/${code}">Open in Lockin</a>`);
    expect(text).toContain(`aria-label="Squad code ${code.split("").join(" ")}"`);
    expect(text).not.toMatch(/<b>|Ava/);

    await call(ava, "DELETE", `/squads/${id}/members/me`);
    expect((await app.request("GET", `/j/${code}`)).status).toBe(404);
  });
});
