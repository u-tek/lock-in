// POST /metrics (src/metrics.ts): the app's integer event counts, as daily totals in D1.

import { readFileSync } from "node:fs";
import { beforeEach, describe, expect, test, vi } from "vitest";
import events from "../../fixtures/analytics/events.json";
import { HttpError, errorResponse } from "../src/http.ts";
import { DAILY_BATCH_LIMIT, MAX_COUNT, METRIC_EVENTS, utcDay } from "../src/metrics.ts";
import { T0, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;

beforeEach(async () => {
  app = await testApp();
});

const post = (body: unknown, headers: Record<string, string> = {}) => app.request("POST", "/metrics", { body, headers });

/** Every row of the day's totals, as { event: count }. */
const totals = (day = utcDay(T0)) =>
  Object.fromEntries(
    (app.sqlite.prepare("SELECT event, count FROM metrics_daily WHERE day = ? ORDER BY event").all(day) as Array<{ event: string; count: number }>).map(
      (row) => [row.event, row.count],
    ),
  );

const batches = (day = utcDay(T0)) => app.value("SELECT batches FROM metrics_batches WHERE day = ?", day) ?? 0;

describe("the event list", () => {
  test("is the app's AnalyticsEvent, name for name", () => {
    // CoreTests checks the same from the Swift side; this keeps the server honest without a Mac.
    const swift = readFileSync(new URL("../../Packages/LKKit/Sources/Core/Analytics.swift", import.meta.url), "utf8");
    const enumBody = /enum AnalyticsEvent[^{]*\{([\s\S]*?)\n\}/.exec(swift)?.[1] ?? "";
    const names = [...enumBody.matchAll(/case \w+ = "([^"]+)"/g)].map((match) => match[1]);
    expect(names.length).toBeGreaterThan(10);
    expect(events.events).toEqual(names);
    expect([...METRIC_EVENTS]).toEqual(names);
  });
});

describe("POST /metrics", () => {
  test("adds the counts to today's totals (UTC), signed out", async () => {
    expect((await post({ counts: { "app.opened": 2, "session.completed": 1 } })).status).toBe(204);
    expect((await post({ counts: { "app.opened": 1, "paywall.shown": 3 } })).status).toBe(204);
    expect(totals()).toEqual({ "app.opened": 3, "paywall.shown": 3, "session.completed": 1 });
    expect(batches()).toBe(2);

    // The next UTC day starts new totals.
    app.clock.now = Math.ceil(T0 / 86_400) * 86_400 + 5;
    expect((await post({ counts: { "app.opened": 1 } })).status).toBe(204);
    expect(totals(utcDay(app.clock.now))).toEqual({ "app.opened": 1 });
    expect(totals()).toEqual({ "app.opened": 3, "paywall.shown": 3, "session.completed": 1 });
  });

  test("keeps nothing about who sent them, even when signed in", async () => {
    const ava = await app.user("ava", "Ava");
    const logs: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => void logs.push(args.map(String).join(" ")));
    const response = await app.request("POST", "/metrics", {
      token: ava.token,
      body: { counts: { "invite.shared": 1 } },
      headers: { "cf-connecting-ip": "203.0.113.7" },
    });
    expect(response.status).toBe(204);
    expect(totals()).toEqual({ "invite.shared": 1 });
    // A row is a day, an event and a total: no column could hold a person, a device or an address.
    const columns = (table: string) => (app.sqlite.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>).map((column) => column.name);
    expect(columns("metrics_daily")).toEqual(["day", "event", "count"]);
    expect(columns("metrics_batches")).toEqual(["day", "batches"]);
    const everything = JSON.stringify([app.sqlite.prepare("SELECT * FROM metrics_daily").all(), app.sqlite.prepare("SELECT * FROM metrics_batches").all(), logs]);
    for (const secret of [ava.user.id, ava.token, "203.0.113.7", "ava"]) expect(everything).not.toContain(secret);
  });

  test("takes only the app's event names and whole counts from 1 to the maximum, all or nothing", async () => {
    const bad: unknown[] = [
      { counts: { "app.opened": 1, "app.closed": 1 } },
      { counts: { "Ava's squad": 1 } },
      '{"counts": {"__proto__": 1}}',
      '{"counts": {"constructor": 1}}',
      { counts: { "app.opened": 0 } },
      { counts: { "app.opened": -1 } },
      { counts: { "app.opened": 1.5 } },
      { counts: { "app.opened": "1" } },
      { counts: { "app.opened": null } },
      { counts: { "app.opened": MAX_COUNT + 1 } },
      { counts: { "app.opened": 1e308 } },
      { counts: {} },
      { counts: [] },
      { counts: [["app.opened", 1]] },
      { counts: "app.opened" },
      {},
      { counts: { "app.opened": 1 }, userId: "Av4Nq8sT2b" },
      { counts: { "app.opened": 1 }, day: "2026-01-01" },
    ];
    for (const body of bad) {
      const { status, body: answer } = await read(await post(body));
      expect(status, JSON.stringify(body)).toBe(422);
      expect(answer.code).toBe("metrics_invalid");
    }
    // A name that isn't the app's is never repeated back.
    expect(JSON.stringify((await read(await post({ counts: { "Ava's squad": 1 } }))).body)).not.toContain("Ava");
    expect((await read(await post([{ "app.opened": 1 }]))).status).toBe(400);
    expect((await read(await post("not json"))).status).toBe(400);
    expect(totals()).toEqual({});
    expect(batches()).toBe(0);

    expect((await post({ counts: { "app.opened": MAX_COUNT, "deepFocus.slip": 1 } })).status).toBe(204);
    expect(totals()).toEqual({ "app.opened": MAX_COUNT, "deepFocus.slip": 1 });
  });

  test("every event the app knows is accepted in one batch", async () => {
    const counts = Object.fromEntries(events.events.map((name, index) => [name, index + 1]));
    expect((await post({ counts })).status).toBe(204);
    expect(totals()).toEqual(counts);
  });

  test("stops for the day at the daily cap, with Retry-After until UTC midnight", async () => {
    const day = utcDay(T0);
    app.sqlite.prepare("INSERT INTO metrics_batches (day, batches) VALUES (?, ?)").run(day, DAILY_BATCH_LIMIT - 1);
    expect((await post({ counts: { "app.opened": 1 } })).status).toBe(204);
    expect(batches()).toBe(DAILY_BATCH_LIMIT);

    const response = await post({ counts: { "app.opened": 1 } });
    const midnight = Date.parse(`${day}T00:00:00Z`) / 1000 + 86_400;
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe(String(midnight - T0));
    expect(await response.json()).toEqual({ error: expect.any(String), code: "rate_limited", retryAfter: midnight - T0 });
    expect(totals()).toEqual({ "app.opened": 1 });
    expect(batches()).toBe(DAILY_BATCH_LIMIT);

    app.clock.now = midnight;
    expect((await post({ counts: { "app.opened": 1 } })).status).toBe(204);
  });

  test("Cloudflare's per-address limit comes first, keyed by the address it never stores", async () => {
    const keys: string[] = [];
    let allow = true;
    app.env.METRICS_LIMITER = {
      async limit({ key }) {
        keys.push(key);
        return { success: allow };
      },
    };
    expect((await post({ counts: { "app.opened": 1 } }, { "cf-connecting-ip": "198.51.100.4" })).status).toBe(204);
    allow = false;
    const response = await post({ counts: { "app.opened": 1 } }, { "cf-connecting-ip": "198.51.100.4" });
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("60");
    expect(((await response.json()) as { code: string }).code).toBe("rate_limited");
    // Refused before the body is read or anything is written.
    expect((await post("not json", { "cf-connecting-ip": "198.51.100.4" })).status).toBe(429);
    expect(keys).toEqual(["metrics:198.51.100.4", "metrics:198.51.100.4", "metrics:198.51.100.4"]);
    expect(totals()).toEqual({ "app.opened": 1 });
    expect(batches()).toBe(1);
  });
});

describe("Retry-After", () => {
  test("every error with a retryAfter carries the header too", () => {
    const response = errorResponse(new HttpError(429, "Slow down", "cheer_too_soon", { retryAfter: 7.2 }));
    expect(response.headers.get("retry-after")).toBe("8");
    expect(errorResponse(new HttpError(404, "Nope")).headers.get("retry-after")).toBeNull();
  });
});
