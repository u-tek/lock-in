import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { MIN_ADMIN_TOKEN_LENGTH } from "../src/admin.ts";
import worker, { type Env, handle } from "../src/index.ts";
import { PAYLOAD_BUDGET_BYTES, parseContentState, payloadByteCount } from "../src/liveActivity.ts";
import { testApp } from "./app.ts";
import { DEVICE_TOKEN, decodeJWT, fakeAPNs, makeKey, readFixture } from "./helpers.ts";

const ADMIN_TOKEN = "a".repeat(20) + "0123456789abcdef0123";
const NOW = 1_791_900_000.5;
let PEM = "";

beforeEach(async () => {
  PEM ||= (await makeKey()).pem;
});

function env(overrides: Partial<Env> = {}): Env {
  return {
    DB: {} as D1Database,
    ROOMS: {} as DurableObjectNamespace,
    APNS_AUTH: {} as DurableObjectNamespace,
    APNS_BUNDLE_ID: "com.example.lockin",
    ENVIRONMENT: "development",
    APNS_TEAM_ID: "TEAM123456",
    APNS_KEY_ID: "KEY1234567",
    APNS_PRIVATE_KEY: PEM,
    ADMIN_TOKEN,
    ...overrides,
  };
}

function pushTest(body: unknown, authorization: string | null = `Bearer ${ADMIN_TOKEN}`): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (authorization !== null) headers.authorization = authorization;
  return new Request("https://lockin-api.example.workers.dev/admin/push-test", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

// What the app's APNs spike screen copies.
const BLOB = { token: DEVICE_TOKEN, env: "production", me: "Av4Nq8sT2b", sid: "r7Kq2xP9aL" };

describe("routes", () => {
  test("GET /health", async () => {
    const response = await handle(new Request("https://x.example/health"), env());
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect(await response.json()).toEqual({ ok: true, environment: "development" });
  });

  test("anything else is a JSON 404", async () => {
    for (const request of [
      new Request("https://x.example/index.html"),
      new Request("https://x.example/privacy/"),
      new Request("https://x.example/", { method: "POST" }),
      new Request("https://x.example/metrics"),
      new Request("https://x.example/rooms/abc"),
      new Request("https://x.example/sessions"),
      new Request("https://x.example/health", { method: "POST" }),
      new Request("https://x.example/admin/push-test"),
    ]) {
      const response = await handle(request, env());
      expect(response.status).toBe(404);
      expect(await response.json()).toEqual({ error: "Not found", code: "not_found" });
    }
  });

  test("every account and friends route needs a bearer token", async () => {
    const authed: Array<[string, string]> = [
      ["GET", "/me"],
      ["PATCH", "/me"],
      ["DELETE", "/me"],
      ["GET", "/handles/ava"],
      ["POST", "/devices"],
      ["GET", "/friends"],
      ["POST", "/friends/code"],
      ["POST", "/friends/redeem/ABCDEFGH"],
      ["DELETE", "/friends/Av4Nq8sT2b"],
      ["GET", "/blocks"],
      ["POST", "/blocks"],
      ["DELETE", "/blocks/Av4Nq8sT2b"],
      ["POST", "/reports"],
      ["DELETE", "/auth/session"],
      ["GET", "/squads"],
      ["POST", "/squads"],
      ["PATCH", "/squads/Sq00000001"],
      ["POST", "/squads/Sq00000001/invite"],
      ["POST", "/squads/join/ABCDEFGH"],
      ["PATCH", "/squads/Sq00000001/members/me"],
      ["DELETE", "/squads/Sq00000001/members/me"],
      ["POST", "/sessions"],
      ["POST", "/sessions/r7Kq2xP9aL/join"],
      ["POST", "/sessions/r7Kq2xP9aL/la-token"],
      ["POST", "/sessions/r7Kq2xP9aL/pause"],
      ["POST", "/sessions/r7Kq2xP9aL/resume"],
      ["POST", "/sessions/r7Kq2xP9aL/end"],
      ["POST", "/sessions/r7Kq2xP9aL/slip"],
      ["POST", "/sessions/r7Kq2xP9aL/cheer"],
      ["GET", "/sessions/r7Kq2xP9aL"],
      ["GET", "/sessions/r7Kq2xP9aL/live"],
      ["GET", "/squads/Sq00000001/leaderboard"],
      ["GET", "/me/cosmetics"],
      ["POST", "/me/coins/import"],
      ["POST", "/shop/buy"],
      ["POST", "/me/plus/refresh"],
      ["PATCH", "/squads/Sq00000001/pet"],
      ["POST", "/squads/Sq00000001/demo-buddy/lock-in"],
    ];
    const app = await testApp();
    for (const [method, path] of authed) {
      const response = await app.request(method, path, { body: method === "GET" || method === "DELETE" ? undefined : {} });
      expect(response.status, `${method} ${path}`).toBe(401);
      expect(await response.json()).toEqual({ error: expect.any(String), code: "unauthorised" });
    }
    // These don't. (The RevenueCat webhook has its own Authorization: without its secret, 503.)
    for (const path of ["/health", "/j/ABCDEFGH", "/.well-known/apple-app-site-association", "/shop", "/", "/privacy", "/terms", "/support"]) {
      expect((await app.request("GET", path)).status, path).not.toBe(401);
    }
    expect((await app.request("POST", "/metrics", { body: { counts: { "app.opened": 1 } } })).status).toBe(204);
    expect((await app.request("POST", "/webhooks/revenuecat", { body: {} })).status).toBe(503);
  });

  test("an unexpected failure is a JSON 500 whose log names the route, not the path", async () => {
    const errors: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => errors.push(args.map(String).join(" ")));
    const broken = {
      prepare() {
        throw new Error("D1_ERROR: something about secret.handle");
      },
    } as unknown as D1Database;
    const app = await testApp({ DB: broken });
    const response = await app.request("GET", "/j/ABCDEFGH");
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "Something went wrong", code: "internal" });
    expect(errors).toEqual(["GET /j/:code: unhandled Error"]);
    vi.restoreAllMocks();
  });

  test("the default export serves the same routes, with the runtime's waitUntil", async () => {
    const kept: Array<Promise<unknown>> = [];
    const ctx = { waitUntil: (promise: Promise<unknown>) => kept.push(promise), passThroughOnException() {} } as unknown as ExecutionContext;
    const response = await worker.fetch(new Request("https://x.example/health") as Parameters<typeof worker.fetch>[0], env(), ctx);
    expect(await response.json()).toEqual({ ok: true, environment: "development" });
    expect(kept).toHaveLength(0);
  });
});

describe("POST /admin/push-test", () => {
  let logs: string[];

  beforeEach(() => {
    logs = [];
    const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
    vi.spyOn(console, "log").mockImplementation(capture);
    vi.spyOn(console, "error").mockImplementation(capture);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    // Whatever happened, no secret or device token reached a log.
    for (const line of logs) {
      expect(line).not.toContain(DEVICE_TOKEN);
      expect(line).not.toContain(ADMIN_TOKEN);
      expect(line).not.toContain("PRIVATE KEY");
      expect(line).not.toMatch(/bearer/i);
    }
  });

  test("doesn't exist in production, even with the right token", async () => {
    const apns = fakeAPNs({ status: 200 });
    const response = await handle(pushTest(BLOB), env({ ENVIRONMENT: "production" }), { fetch: apns.fetch, now: () => NOW });
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "Not found", code: "not_found" });
    expect(apns.requests).toHaveLength(0);
  });

  test("doesn't exist without an ADMIN_TOKEN of 32+ characters", async () => {
    const apns = fakeAPNs({ status: 200 });
    const deps = { fetch: apns.fetch, now: () => NOW };
    expect((await handle(pushTest(BLOB), env({ ADMIN_TOKEN: undefined }), deps)).status).toBe(404);
    expect((await handle(pushTest(BLOB, "Bearer "), env({ ADMIN_TOKEN: "" }), deps)).status).toBe(404);
    const short = "s".repeat(MIN_ADMIN_TOKEN_LENGTH - 1);
    expect((await handle(pushTest(BLOB, `Bearer ${short}`), env({ ADMIN_TOKEN: short }), deps)).status).toBe(404);
    expect(apns.requests).toHaveLength(0);
  });

  test("looks the same as a missing route without the right bearer token", async () => {
    const apns = fakeAPNs({ status: 200 });
    const deps = { fetch: apns.fetch, now: () => NOW };
    for (const authorization of [null, "", `Bearer ${ADMIN_TOKEN}x`, `Bearer ${ADMIN_TOKEN.slice(1)}`, `Basic ${ADMIN_TOKEN}`, ADMIN_TOKEN]) {
      const response = await handle(pushTest(BLOB, authorization), env(), deps);
      expect(response.status).toBe(404);
      expect(await response.json()).toEqual({ error: "Not found", code: "not_found" });
    }
    expect(apns.requests).toHaveLength(0);
  });

  test("tolerates a trailing newline on the stored token (PowerShell pipes add one)", async () => {
    const apns = fakeAPNs({ status: 200 });
    const response = await handle(pushTest(BLOB), env({ ADMIN_TOKEN: `${ADMIN_TOKEN}\r\n` }), { fetch: apns.fetch, now: () => NOW });
    expect(response.status).toBe(200);
  });

  test("400s with a useful message", async () => {
    const apns = fakeAPNs({ status: 200 });
    const deps = { fetch: apns.fetch, now: () => NOW };
    const cases: Array<[unknown, RegExp]> = [
      ["not json", /isn't valid JSON/],
      ["", /Expected a JSON body/],
      [[BLOB], /JSON object/],
      [{ ...BLOB, token: "not-hex" }, /token must be the Live Activity push token in hex/],
      [{ ...BLOB, token: undefined }, /token must be/],
      [{ ...BLOB, env: "development" }, /env must be "sandbox".*or "production"/],
      [{ ...BLOB, me: "me" }, /me must be a 10-character base62 id/],
      [{ ...BLOB, sid: null }, /sid must be a 10-character base62 id/],
      [{ ...BLOB, scenario: "party" }, /scenario must be one of squad, join, cheer, end/],
      [{ ...BLOB, priority: 1 }, /priority must be 5 or 10/],
      [{ ...BLOB, enviroment: "sandbox" }, /Unknown enviroment/],
      [{ ...BLOB, contentState: { v: 1, m: [] } }, /contentState\.m must have 1–6 members/],
      [{ ...BLOB, contentState: { ...parseContentState(readFixture("solo", "content-state").value), p: null } }, /contentState\.p is null/],
    ];
    for (const [body, message] of cases) {
      const response = await handle(pushTest(body), env(), deps);
      expect(response.status, JSON.stringify(body)).toBe(400);
      expect(((await response.json()) as { error: string }).error).toMatch(message);
    }
    expect(apns.requests).toHaveLength(0);
  });

  test("sends the squad scenario to APNs and reports what happened", async () => {
    const apns = fakeAPNs({ status: 200, apnsId: "0C5A4C3E-1111-4000-8000-000000000042" });
    const response = await handle(pushTest(BLOB), env(), { fetch: apns.fetch, now: () => NOW });
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, any>;

    expect(apns.requests).toHaveLength(1);
    const [request] = apns.requests;
    expect(request?.url).toBe(`https://api.push.apple.com/3/device/${DEVICE_TOKEN}`);
    expect(request?.headers).toMatchObject({
      "apns-topic": "com.example.lockin.push-type.liveactivity",
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
    });
    expect(decodeJWT((request?.headers.authorization ?? "").slice(7)).claims).toEqual({ iss: "TEAM123456", iat: Math.floor(NOW) });

    const sent = JSON.parse(request?.body ?? "{}") as { aps: Record<string, any> };
    expect(sent.aps).toMatchObject({ timestamp: Math.floor(NOW), event: "update" });
    expect(sent.aps["stale-date"]).toBeGreaterThan(NOW);
    expect(sent.aps["content-state"].m[0].i).toBe("Av4Nq8sT2b");

    expect(body).toEqual({
      status: 200,
      apnsId: "0C5A4C3E-1111-4000-8000-000000000042",
      environment: "production",
      bytes: payloadByteCount({ sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b", sq: "Spike Squad" }, sent.aps["content-state"]),
      event: "update",
      contentState: sent.aps["content-state"],
    });
    expect(body.bytes).toBeLessThan(PAYLOAD_BUDGET_BYTES);
    expect(logs.join("\n")).toMatch(/push-test: production update p10 \d+ bytes -> APNs 200/);
  });

  test("cheer goes at priority 5, end as an end event, and both honour an explicit priority", async () => {
    const deps = () => {
      const apns = fakeAPNs({ status: 200 });
      return { apns, deps: { fetch: apns.fetch, now: () => NOW } };
    };

    const cheer = deps();
    await handle(pushTest({ ...BLOB, env: "sandbox", scenario: "cheer" }), env(), cheer.deps);
    expect(cheer.apns.requests[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${DEVICE_TOKEN}`);
    expect(cheer.apns.requests[0]?.headers["apns-priority"]).toBe("5");

    const end = deps();
    const response = await handle(pushTest({ ...BLOB, scenario: "end", priority: 5 }), env(), end.deps);
    expect(((await response.json()) as { event: string }).event).toBe("end");
    const sent = JSON.parse(end.apns.requests[0]?.body ?? "{}") as { aps: Record<string, unknown> };
    expect(sent.aps).toMatchObject({ event: "end", "dismissal-date": Math.floor(NOW) + 1800 });
    expect(sent.aps).not.toHaveProperty("stale-date");
    expect(end.apns.requests[0]?.headers["apns-priority"]).toBe("5");
  });

  test("an explicit contentState replaces the scenario's", async () => {
    const apns = fakeAPNs({ status: 200 });
    const contentState = readFixture("squad-6", "content-state").value;
    const response = await handle(pushTest({ ...BLOB, contentState }), env(), { fetch: apns.fetch, now: () => NOW });
    expect(response.status).toBe(200);
    expect(((await response.json()) as { contentState: unknown }).contentState).toEqual(contentState);
    expect((JSON.parse(apns.requests[0]?.body ?? "{}") as { aps: Record<string, unknown> }).aps["content-state"]).toEqual(contentState);
  });

  test("passes APNs' refusal back as a 502 with the reason", async () => {
    const apns = fakeAPNs({ status: 400, body: { reason: "BadDeviceToken" }, apnsId: "refused" });
    const response = await handle(pushTest(BLOB), env(), { fetch: apns.fetch, now: () => NOW });
    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ status: 400, apnsId: "refused", reason: "BadDeviceToken", environment: "production" });
    expect(logs.join("\n")).toContain("APNs 400 BadDeviceToken");
  });

  test("says when APNs can't be reached, without echoing the token", async () => {
    const unreachable = (async (input: RequestInfo | URL) => {
      throw new Error(`connection reset fetching ${String(input)}`);
    }) as typeof fetch;
    const response = await handle(pushTest(BLOB), env(), { fetch: unreachable, now: () => NOW });
    expect(response.status).toBe(502);
    const body = (await response.json()) as { error: string };
    expect(body.error).toMatch(/^Couldn't reach APNs: connection reset/);
    expect(body.error).not.toContain(DEVICE_TOKEN);
  });

  test("names the APNs secrets that are missing, and a key that won't load", async () => {
    const apns = fakeAPNs({ status: 200 });
    const deps = { fetch: apns.fetch, now: () => NOW };
    const missing = await handle(pushTest(BLOB), env({ APNS_KEY_ID: undefined, APNS_PRIVATE_KEY: " " }), deps);
    expect(missing.status).toBe(500);
    expect(((await missing.json()) as { error: string }).error).toBe("APNs isn't set up: APNS_KEY_ID, APNS_PRIVATE_KEY missing (server/README.md)");

    const broken = await handle(pushTest(BLOB), env({ APNS_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----" }), deps);
    expect(broken.status).toBe(500);
    expect(((await broken.json()) as { error: string }).error).toMatch(/isn't a usable \.p8 key/);
    expect(apns.requests).toHaveLength(0);
  });
});
