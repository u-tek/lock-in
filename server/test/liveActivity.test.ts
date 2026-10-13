import { describe, expect, test } from "vitest";
import {
  type Attributes,
  type ContentState,
  END_DISMISSAL_SECONDS,
  LiveActivityError,
  MAX_MEMBERS,
  type Member,
  MemberState,
  PAYLOAD_BUDGET_BYTES,
  assertPayloadBudget,
  buildLiveActivityPayload,
  encodeAttributes,
  encodeContentState,
  parseAttributes,
  parseContentState,
  payloadByteCount,
  staleDateFor,
  textLength,
} from "../src/liveActivity.ts";
import { fixtureNames, readFixture } from "./helpers.ts";

const compact = (text: string) => JSON.stringify(JSON.parse(text));
const squad6 = () => readFixture("squad-6", "content-state").value as ContentState;
const solo = () => readFixture("solo", "content-state").value as ContentState;

describe("the shared fixtures", () => {
  test("are all here", () => {
    expect(fixtureNames()).toEqual(expect.arrayContaining(["largest", "solo", "squad-6"]));
  });

  test.each(fixtureNames())("%s parses and re-encodes byte for byte", (name) => {
    const state = readFixture(name, "content-state");
    const parsed = parseContentState(state.value);
    expect(parsed).toEqual(state.value);
    // Same keys, same order, same numbers: what the server sends is what the Swift tests decode.
    expect(encodeContentState(parsed)).toBe(compact(state.text));

    const attributes = readFixture(name, "attributes");
    const parsedAttributes = parseAttributes(attributes.value);
    expect(parsedAttributes).toEqual(attributes.value);
    expect(encodeAttributes(parsedAttributes)).toBe(compact(attributes.text));

    expect(assertPayloadBudget(parsedAttributes, parsed)).toBe(payloadByteCount(parsedAttributes, parsed));
  });

  test("squad-6 has a member in every state", () => {
    expect(squad6().m.map((member) => member.s)).toEqual(Object.values(MemberState));
  });

  test("solo leaves the optional keys out rather than sending null", () => {
    const encoded = encodeContentState(parseContentState(solo()));
    expect(encoded).not.toContain("null");
    expect(JSON.parse(encoded)).not.toHaveProperty("p");
    expect(JSON.parse(encoded)).not.toHaveProperty("c");
    expect(encodeAttributes(parseAttributes(readFixture("solo", "attributes").value))).toBe('{"sid":"s0LoRun123","me":"Av4Nq8sT2b"}');
  });
});

describe("the payload budget", () => {
  test("the largest fixture fits, counted as compact UTF-8", () => {
    const attributes = readFixture("largest", "attributes");
    const state = readFixture("largest", "content-state");
    const bytes = payloadByteCount(attributes.value as Attributes, state.value as ContentState);
    expect(bytes).toBe(new TextEncoder().encode(compact(attributes.text) + compact(state.text)).length);
    expect(bytes).toBeLessThanOrEqual(PAYLOAD_BUDGET_BYTES);
  });

  test("the worst case the validators allow fits too", () => {
    // Every string at its limit in 4-byte characters, every optional key, the longest numbers.
    const time = 4_102_444_799.999_999_5; // 18 characters as JSON
    const id = (n: number) => `zZ9yY8xX7${n}`;
    const worst: ContentState = {
      v: Number.MAX_SAFE_INTEGER,
      m: Array.from({ length: MAX_MEMBERS }, (_, n): Member => ({
        i: id(n),
        n: "🦊".repeat(12),
        a: "b99.c99.e99.h99",
        s: MemberState.paused,
        b: time - 2,
        e: time,
        q: time - 1,
      })),
      p: { k: "dragonling.99", md: 3, x: 1.234_567_890_123_456_7e-7 },
      c: { f: id(1), t: id(0), k: 99, at: time },
    };
    const attributes: Attributes = { sid: id(9), me: id(0), sq: "🔒".repeat(20) };
    expect(parseContentState(worst)).toEqual(worst);
    expect(parseAttributes(attributes)).toEqual(attributes);
    expect(payloadByteCount(attributes, worst)).toBeLessThan(PAYLOAD_BUDGET_BYTES);
  });

  test("anything over 3584 bytes throws", () => {
    const state = squad6();
    const oversize: ContentState = { ...state, m: state.m.map((member) => ({ ...member, n: "x".repeat(600) })) };
    const attributes: Attributes = { sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b" };
    expect(payloadByteCount(attributes, oversize)).toBeGreaterThan(PAYLOAD_BUDGET_BYTES);
    expect(() => assertPayloadBudget(attributes, oversize)).toThrow(LiveActivityError);
    expect(() => assertPayloadBudget(attributes, oversize)).toThrow(/budget is 3584/);
  });
});

describe("strict parsing", () => {
  const rejects = (mutate: (state: Record<string, any>) => void, message: RegExp) => {
    const state = structuredClone(squad6()) as Record<string, any>;
    mutate(state);
    expect(() => parseContentState(state)).toThrow(LiveActivityError);
    expect(() => parseContentState(state)).toThrow(message);
  };

  test("refuses keys the Swift type doesn't have", () => {
    rejects((s) => (s.extra = 1), /contentState\.extra isn't part of the wire format/);
    rejects((s) => (s.m[0].name = "Ava"), /contentState\.m\[0\]\.name isn't part/);
    rejects((s) => (s.p.mood = 1), /contentState\.p\.mood/);
    rejects((s) => (s.c.emoji = 1), /contentState\.c\.emoji/);
    expect(() => parseAttributes({ sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b", squad: "x" })).toThrow(/attributes\.squad/);
  });

  test("refuses null where a key should be left out", () => {
    rejects((s) => (s.p = null), /contentState\.p is null: leave optional keys out/);
    rejects((s) => (s.c = null), /contentState\.c is null/);
    rejects((s) => (s.m[0].q = null), /contentState\.m\[0\]\.q is null/);
    rejects((s) => (s.v = null), /contentState\.v is null/);
    expect(() => parseAttributes({ sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b", sq: null })).toThrow(/attributes\.sq is null/);
  });

  test("refuses missing keys and wrong types", () => {
    rejects((s) => delete s.v, /contentState\.v is missing/);
    rejects((s) => delete s.m[1].e, /contentState\.m\[1\]\.e is missing/);
    rejects((s) => (s.v = "42"), /contentState\.v must be a whole number/);
    rejects((s) => (s.v = 1.5), /contentState\.v must be a whole number/);
    rejects((s) => (s.m = {}), /contentState\.m must be an array/);
    rejects((s) => (s.m[0].s = "0"), /contentState\.m\[0\]\.s/);
    rejects((s) => (s.m[0].s = 6), /contentState\.m\[0\]\.s must be a whole number from 0 to 5/);
    rejects((s) => (s.m[0].b = "1791900000"), /contentState\.m\[0\]\.b must be a finite number/);
    rejects((s) => (s.m[0].i = "short"), /contentState\.m\[0\]\.i must be a 10-character base62 id/);
    rejects((s) => (s.m[0].a = "<script>"), /contentState\.m\[0\]\.a must look like/);
    rejects((s) => (s.p.md = 4), /contentState\.p\.md/);
    rejects((s) => (s.p.x = 1.01), /contentState\.p\.x must be a number from 0 to 1/);
    rejects((s) => (s.c.k = -1), /contentState\.c\.k/);
    expect(() => parseContentState([])).toThrow(/must be an object/);
    expect(() => parseContentState("{}")).toThrow(/must be an object/);
  });

  test("refuses numbers JSON can't carry, and times that aren't Unix seconds", () => {
    rejects((s) => (s.m[0].e = Number.POSITIVE_INFINITY), /finite/);
    rejects((s) => (s.m[0].b = Number.NaN), /finite/);
    rejects((s) => (s.p.x = Number.NaN), /contentState\.p\.x/);
    rejects((s) => (s.m[0].b = 1_791_900_000_000), /milliseconds/);
    rejects((s) => (s.m[0].b = 1500), /Unix seconds between 2000 and 2100/);
  });

  test("refuses more than six members, and none", () => {
    rejects((s) => s.m.push({ ...s.m[0], i: "Zz0000000x" }), /must have 1–6 members, got 7/);
    rejects((s) => (s.m = []), /got 0/);
    rejects((s) => (s.m[1].i = s.m[0].i), /contentState\.m\[1\]\.i repeats member id/);
  });

  test("keeps paused-at for paused members only", () => {
    rejects((s) => delete s.m[2].q, /contentState\.m\[2\]\.q is missing: a paused member/);
    rejects((s) => (s.m[0].q = 1_791_900_100), /contentState\.m\[0\]\.q is only for paused members/);
    rejects((s) => (s.m[2].q = s.m[2].e + 1), /must be between b and e/);
    rejects((s) => (s.m[0].e = s.m[0].b - 1), /contentState\.m\[0\]\.e is before b/);
  });

  test("names: 1–12 code points, squad names 1–20", () => {
    rejects((s) => (s.m[0].n = "Bartholomew12"), /contentState\.m\[0\]\.n must be 1–12 characters \(code points\), got 13/);
    rejects((s) => (s.m[0].n = ""), /got 0/);
    rejects((s) => (s.m[0].n = "Ava\u0000"), /control characters/);
    rejects((s) => (s.m[0].n = "Ava\uD83E"), /broken surrogate/);
    rejects((s) => (s.m[0].n = "🦊".repeat(13)), /got 13/);
    rejects((s) => (s.m[0].n = 12), /must be a string/);

    const accepts = (n: string) => expect(parseContentState({ ...solo(), m: [{ ...solo().m[0], n }] }).m[0]?.n).toBe(n);
    accepts("Bartholomew1");
    accepts("🦊".repeat(12));
    // A flag is one Character in Swift but two code points here: six fit, seven don't.
    accepts("🇦🇺".repeat(6));
    expect(textLength("🇦🇺".repeat(7))).toBe(14);
    rejects((s) => (s.m[0].n = "🇦🇺".repeat(7)), /got 14/);

    const attributes = (sq: string) => ({ sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b", sq });
    expect(parseAttributes(attributes("x".repeat(20))).sq).toHaveLength(20);
    expect(() => parseAttributes(attributes("x".repeat(21)))).toThrow(/attributes\.sq must be 1–20 characters/);
    expect(() => parseAttributes({ sid: "r7Kq2xP9aL" })).toThrow(/attributes\.me is missing/);
  });

  test("treats undefined as absent, as JSON.stringify does", () => {
    const state = { ...solo(), p: undefined, c: undefined, m: [{ ...solo().m[0], q: undefined }] };
    expect(encodeContentState(parseContentState(state))).toBe(encodeContentState(solo()));
  });

  test("returns a canonical copy, whatever order the keys came in", () => {
    const shuffled = { c: squad6().c, m: squad6().m.map(({ q, e, b, s, a, n, i }) => ({ q, e, b, s, a, n, i })), p: squad6().p, v: 42 };
    expect(encodeContentState(parseContentState(shuffled))).toBe(compact(readFixture("squad-6", "content-state").text));
  });
});

describe("staleDateFor", () => {
  test("is the latest end plus five minutes", () => {
    // Jules (slipped) ends last at 1791903060.
    expect(staleDateFor(squad6(), 1_791_900_650)).toBe(1_791_903_060 + 300);
  });

  test("counts a paused member as now plus the time they have left", () => {
    // Kai paused with 780 s left; at this point that outlasts everyone else.
    const now = 1_791_903_000;
    expect(staleDateFor(squad6(), now)).toBe(now + 780 + 300);
  });

  test("rounds up to whole seconds", () => {
    expect(staleDateFor({ v: 1, m: [{ ...solo().m[0]!, e: 1_791_901_500.25 }] }, 1_791_900_000)).toBe(1_791_901_801);
  });
});

describe("buildLiveActivityPayload", () => {
  test("update: timestamp, event, content-state and the optional dates", () => {
    const payload = buildLiveActivityPayload({
      event: "update",
      state: squad6(),
      timestamp: 1_791_900_650.9,
      staleDate: staleDateFor(squad6(), 1_791_900_650),
      relevanceScore: 50,
    });
    expect(Object.keys(payload.aps)).toEqual(["timestamp", "event", "content-state", "stale-date", "relevance-score"]);
    expect(payload.aps.timestamp).toBe(1_791_900_650);
    expect(payload.aps["stale-date"]).toBe(1_791_903_360);
    expect(JSON.stringify(payload.aps["content-state"])).toBe(compact(readFixture("squad-6", "content-state").text));
  });

  test("end: dismissal defaults to 30 minutes after the timestamp", () => {
    const payload = buildLiveActivityPayload({ event: "end", state: solo(), timestamp: 1_791_901_500 });
    expect(payload.aps).toMatchObject({ event: "end", "dismissal-date": 1_791_901_500 + END_DISMISSAL_SECONDS });
    const now = buildLiveActivityPayload({ event: "end", state: solo(), timestamp: 1_791_901_500, dismissalDate: 1_791_901_500 });
    expect(now.aps["dismissal-date"]).toBe(1_791_901_500);
  });

  test("start: push-to-start needs an alert and the attributes", () => {
    const attributes = readFixture("squad-6", "attributes").value as Attributes;
    const alert = { title: "Ava is locking in 🔒", body: "Joined for 25 minutes" };
    const payload = buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes, inputPushToken: true });
    expect(payload.aps).toMatchObject({
      event: "start",
      alert,
      "attributes-type": "LockinAttributes",
      attributes,
      "input-push-token": 1,
    });

    expect(() => buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, attributes })).toThrow(/alert is required/);
    expect(() => buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert })).toThrow(/attributes are required/);
    expect(() =>
      buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes: { ...attributes, sid: "bad" } }),
    ).toThrow(/attributes\.sid/);
  });

  test("keeps start-only and end-only fields where they belong", () => {
    const attributes = readFixture("squad-6", "attributes").value as Attributes;
    expect(() => buildLiveActivityPayload({ event: "update", state: solo(), timestamp: 1_791_900_000, attributes })).toThrow(/for start/);
    expect(() => buildLiveActivityPayload({ event: "update", state: solo(), timestamp: 1_791_900_000, inputPushToken: true })).toThrow(/for start/);
    expect(() => buildLiveActivityPayload({ event: "update", state: solo(), timestamp: 1_791_900_000, dismissalDate: 1_791_900_000 })).toThrow(
      /only for end/,
    );
  });

  test("validates the state and the dates on the way out", () => {
    const invalid = { ...solo(), m: [] } as ContentState;
    expect(() => buildLiveActivityPayload({ event: "update", state: invalid, timestamp: 1_791_900_000 })).toThrow(LiveActivityError);
    expect(() => buildLiveActivityPayload({ event: "update", state: solo(), timestamp: Date.now() })).toThrow(/milliseconds/);
    expect(() => buildLiveActivityPayload({ event: "update", state: solo(), timestamp: 1_791_900_000, relevanceScore: Number.NaN })).toThrow(
      /relevanceScore/,
    );
  });
});
