// Made-up squads for the APNs spike (POST /admin/push-test). Times are relative to now, so the
// countdowns on the phone are live, and the version is now in whole seconds, so each push is newer
// than the last. The first member is always `me`: the phone that receives the push.

import { type Attributes, type ContentState, type Member, MemberState } from "./liveActivity.ts";

export const DEMO_SCENARIOS = ["squad", "join", "cheer", "end"] as const;
export type DemoScenario = (typeof DEMO_SCENARIOS)[number];

/** Used when the caller doesn't pass the ids from the app's spike screen. */
export const DEMO_ME = "me00000000";
export const DEMO_SID = "spike00000";

export interface Demo {
  event: "update" | "end";
  /** SPEC.md §4.4: joins, finishes and the end are 10; cheers are 5. */
  priority: 5 | 10;
  /** What the phone would have started the activity with: only used to count bytes. */
  attributes: Attributes;
  state: ContentState;
}

export interface DemoOptions {
  me?: string;
  sid?: string;
  /** Unix seconds. */
  now: number;
}

type Person = Pick<Member, "i" | "n" | "a">;

const NOOR: Person = { i: "noor000001", n: "Noor", a: "b1.c2.e5.h0" };
const KAI: Person = { i: "kai0000002", n: "Kai", a: "b2.c4.e1.h2" };
const MILA: Person = { i: "mila000003", n: "Mila", a: "b4.c1.e3.h1" };

const MINUTE = 60;

export function demoScenario(scenario: DemoScenario, options: DemoOptions): Demo {
  const now = Math.floor(options.now);
  const me = options.me ?? DEMO_ME;
  const you: Person = { i: me, n: "You", a: "b3.c7.e2.h4" };
  // Must match APNsSpikeModel.squadName in App/Sources/Developer/APNsSpikeScreen.swift: the phone
  // shows the squad name from its own attributes, never from a push.
  const attributes: Attributes = { sid: options.sid ?? DEMO_SID, me, sq: "Spike Squad" };

  const focusing = (person: Person, startedMinutesAgo: number, minutes: number): Member => {
    const b = now - startedMinutesAgo * MINUTE;
    return { ...person, s: MemberState.focusing, b, e: b + minutes * MINUTE };
  };
  const done = (person: Person, finishedMinutesAgo: number, minutes: number): Member => {
    const e = now - finishedMinutesAgo * MINUTE;
    return { ...person, s: MemberState.done, b: e - minutes * MINUTE, e };
  };
  const squad = (): Member[] => [focusing(you, 5, 25), focusing(NOOR, 12, 50), focusing(KAI, 2, 25), focusing(MILA, 30, 90)];

  switch (scenario) {
    case "squad":
      return { event: "update", priority: 10, attributes, state: { v: now, m: squad(), p: { k: "fox.1", md: 2, x: 0.42 } } };
    case "join":
      return {
        event: "update",
        priority: 10,
        attributes,
        state: { v: now, m: [focusing(you, 3, 25), focusing(NOOR, 0, 50)], p: { k: "fox.1", md: 2, x: 0.4 } },
      };
    case "cheer":
      return {
        event: "update",
        priority: 5,
        attributes,
        state: { v: now, m: squad(), p: { k: "fox.1", md: 3, x: 0.43 }, c: { f: NOOR.i, t: me, k: 2, at: now } },
      };
    case "end":
      return {
        event: "end",
        priority: 10,
        attributes,
        state: {
          v: now,
          m: [done(you, 0, 25), done(NOOR, 1, 50), done(KAI, 2, 25), done(MILA, 0, 90)],
          p: { k: "fox.2", md: 3, x: 0.05 },
        },
      };
  }
}
