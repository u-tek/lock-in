import { describe, expect, test } from "vitest";
import { APNS_BODY_LIMIT_BYTES } from "../src/apns.ts";
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
  isPetCode,
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
const bodyBytes = (payload: unknown) => new TextEncoder().encode(JSON.stringify(payload)).length;

/** The worst case the validators allow: every string at its limit in 4-byte characters, every optional key, the longest numbers. */
function worstCase(): { state: ContentState; attributes: Attributes; time: number } {
  const time = 4_102_444_799.999_999_5; // 18 characters as JSON
  const id = (n: number) => `zZ9yY8xX7${n}`;
  const state: ContentState = {
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
    // M7: the longest pet code, accessory included.
    p: { k: "dragonling.99.a99", md: 3, x: 1.234_567_890_123_456_7e-7 },
    c: { f: id(1), t: id(0), k: 99, at: time },
  };
  return { state, attributes: { sid: id(9), me: id(0), sq: "🔒".repeat(20) }, time };
}

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
    const { state: worst, attributes } = worstCase();
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

  test("pet codes: <species>.<stage>, with an accessory after the stage from M7", () => {
    for (const k of ["sprout.2", "puff.0", "dragonling.99", "sprout.2.a3", "ember.1.a99"]) expect(isPetCode(k), k).toBe(true);
    for (const k of ["sprout", "sprout.2.", "sprout.2.3", "sprout.2.a", "sprout.2.a100", "sprout.2.b3", "sprout.2.a3.a4", "Sprout.2"]) {
      expect(isPetCode(k), k).toBe(false);
    }
    const state = { ...squad6(), p: { k: "sprout.2.a3", md: 2, x: 0.64 } };
    expect(parseContentState(state).p?.k).toBe("sprout.2.a3");
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
  // The same moments as ModelTests' squadStaleDatesMatchTheServer: both sides must agree.
  test("is the latest end of the running members plus five minutes", () => {
    // Jules (slipped: still running, decision 0009) ends last at 1791903060, after Noor (on a break,
    // 1791902700). The others, done or left, don't hold the activity open.
    expect(staleDateFor(squad6(), 1_791_900_650)).toBe(1_791_903_360);
    // Without Jules, Noor is the last.
    expect(staleDateFor({ ...squad6(), m: squad6().m.slice(0, 5) }, 1_791_900_650)).toBe(1_791_903_000);
  });

  test("uses everyone's end when nobody is running", () => {
    const base = solo().m[0]!;
    const state = {
      v: 1,
      m: [
        { ...base, s: MemberState.done, b: 1000, e: 1000 },
        { ...base, i: "Nr2Kx7pQ1m", s: MemberState.left, b: 1000, e: 3000 },
        { ...base, i: "Jl3Bt8Gc2f", s: MemberState.done, b: 1000, e: 2000 },
      ],
    };
    expect(staleDateFor(state, 1_791_900_000)).toBe(3300);
  });

  test("a slipped member is running: their end holds the activity open (decision 0009)", () => {
    const base = solo().m[0]!;
    const state = {
      v: 1,
      m: [
        { ...base, s: MemberState.done, b: 1000, e: 1000 },
        { ...base, i: "Nr2Kx7pQ1m", s: MemberState.left, b: 1000, e: 3000 },
        { ...base, i: "Jl3Bt8Gc2f", s: MemberState.slipped, b: 1000, e: 2000 },
      ],
    };
    expect(staleDateFor(state, 1_791_900_000)).toBe(2300);
  });

  test("counts a paused member as now plus the time they have left", () => {
    // Kai paused with 780 s left; at this point that outlasts everyone else.
    const now = 1_791_903_000;
    expect(staleDateFor(squad6(), now)).toBe(1_791_904_080);
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
    const payload = buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes });
    expect(payload.aps).toMatchObject({
      event: "start",
      alert,
      "attributes-type": "LockinAttributes",
      attributes,
      "input-push-token": 1,
    });
    // On by default (every supported iOS needs it for the update token); off only when asked.
    const explicit = buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes, inputPushToken: true });
    expect(explicit).toEqual(payload);
    const withoutToken = buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes, inputPushToken: false });
    expect(withoutToken.aps).not.toHaveProperty("input-push-token");

    expect(() => buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, attributes })).toThrow(/alert is required/);
    expect(() => buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert })).toThrow(/attributes are required/);
    expect(() =>
      buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert, attributes: { ...attributes, sid: "bad" } }),
    ).toThrow(/attributes\.sid/);
  });

  test("the largest start the validators allow fits APNs' 4096-byte body", () => {
    const { state, attributes, time } = worstCase();
    // A generous alert, in 4-byte characters: 40 for the title, 120 for the body.
    const alert = { title: "🔒".repeat(40), body: "🦊".repeat(120), sound: "default" };
    const payload = buildLiveActivityPayload({
      event: "start",
      state,
      timestamp: time,
      staleDate: time,
      relevanceScore: 1.234_567_890_123_456_7e-7,
      alert,
      attributes,
    });
    expect(payload.aps).toHaveProperty("input-push-token", 1);
    expect(bodyBytes(payload)).toBeLessThanOrEqual(APNS_BODY_LIMIT_BYTES);
  });

  test("anything whose whole body is over 4096 bytes throws, alert included", () => {
    const attributes = readFixture("squad-6", "attributes").value as Attributes;
    const start = (body: string) =>
      buildLiveActivityPayload({ event: "start", state: squad6(), timestamp: 1_791_900_000, alert: { title: "Ava", body }, attributes });
    // Fill the alert to exactly the limit with 2-byte characters: bytes count, not string length.
    const room = APNS_BODY_LIMIT_BYTES - bodyBytes(start("x"));
    const exact = `x${"é".repeat(Math.floor(room / 2))}${"x".repeat(room % 2)}`;
    expect(bodyBytes(start(exact))).toBe(APNS_BODY_LIMIT_BYTES);
    expect(() => start(`${exact}x`)).toThrow(LiveActivityError);
    expect(() => start(`${exact}x`)).toThrow(`The APNs body is ${APNS_BODY_LIMIT_BYTES + 1} bytes; APNs takes at most 4096`);
    // Well under the 3584-byte attributes + content-state budget, but the alert takes it over.
    expect(payloadByteCount(attributes, squad6())).toBeLessThan(PAYLOAD_BUDGET_BYTES);

    const update = { event: "update", state: squad6(), timestamp: 1_791_900_000 } as const;
    expect(() => buildLiveActivityPayload({ ...update, alert: { title: "Ava", body: "x".repeat(APNS_BODY_LIMIT_BYTES) } })).toThrow(/APNs body/);
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
