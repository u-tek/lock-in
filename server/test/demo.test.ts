import { describe, expect, test } from "vitest";
import { DEMO_ME, DEMO_SCENARIOS, demoScenario } from "../src/demo.ts";
import { MemberState, assertPayloadBudget, buildLiveActivityPayload, parseContentState } from "../src/liveActivity.ts";

const NOW = 1_791_900_000.75;

describe("demo scenarios", () => {
  test.each(DEMO_SCENARIOS)("%s is valid, within budget and puts me first", (scenario) => {
    const demo = demoScenario(scenario, { me: "Av4Nq8sT2b", sid: "r7Kq2xP9aL", now: NOW });
    expect(parseContentState(demo.state)).toEqual(demo.state);
    expect(assertPayloadBudget(demo.attributes, demo.state)).toBeLessThan(1024);
    expect(demo.attributes).toMatchObject({ sid: "r7Kq2xP9aL", me: "Av4Nq8sT2b" });
    expect(demo.state.m[0]?.i).toBe("Av4Nq8sT2b");
    expect(demo.state.v).toBe(Math.floor(NOW));
    expect(() => buildLiveActivityPayload({ event: demo.event, state: demo.state, timestamp: NOW })).not.toThrow();
  });

  test("squad: me and three friends focusing, with a pet", () => {
    const { state, event, priority } = demoScenario("squad", { now: NOW });
    expect(state.m).toHaveLength(4);
    expect(state.m.every((member) => member.s === MemberState.focusing && member.b <= NOW && member.e > NOW)).toBe(true);
    expect(new Set(state.m.map((member) => member.e)).size).toBe(4);
    expect(state.p).toBeDefined();
    expect(state.c).toBeUndefined();
    expect([event, priority]).toEqual(["update", 10]);
    expect(state.m[0]?.i).toBe(DEMO_ME);
  });

  test("join: a friend who just started", () => {
    const { state, priority } = demoScenario("join", { now: NOW });
    expect(state.m).toHaveLength(2);
    expect(state.m[1]?.b).toBe(Math.floor(NOW));
    expect(priority).toBe(10);
  });

  test("cheer: a cheer to me, at the low priority", () => {
    const { state, priority } = demoScenario("cheer", { me: "Av4Nq8sT2b", now: NOW });
    expect(state.c).toMatchObject({ t: "Av4Nq8sT2b", at: Math.floor(NOW) });
    expect(state.m.some((member) => member.i === state.c?.f)).toBe(true);
    expect(priority).toBe(5);
  });

  test("end: everyone done, sent as an end event", () => {
    const { state, event, priority } = demoScenario("end", { now: NOW });
    expect(state.m.every((member) => member.s === MemberState.done && member.e <= NOW)).toBe(true);
    expect([event, priority]).toEqual(["end", 10]);
  });

  test("versions go up with the clock", () => {
    expect(demoScenario("squad", { now: NOW + 1 }).state.v).toBeGreaterThan(demoScenario("squad", { now: NOW }).state.v);
  });
});
