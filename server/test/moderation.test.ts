// Every case in fixtures/moderation/cases.json: the same file the app's Social module tests, so the
// two checks can't drift.

import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { parseContentState } from "../src/liveActivity.ts";
import { type ModerationKind, type ModerationVerdict, isValid, moderate, normalise, normaliseHandle, normaliseName } from "../src/moderation.ts";

const FIXTURES = new URL("../../fixtures/moderation/", import.meta.url);

interface Case {
  kind: ModerationKind;
  input: string;
  expected: ModerationVerdict;
}

const cases = JSON.parse(readFileSync(new URL("cases.json", FIXTURES), "utf8")) as Case[];
const words = JSON.parse(readFileSync(new URL("words.json", FIXTURES), "utf8")) as {
  leet: Record<string, string>;
  anywhere: string[];
  token: string[];
  reserved: string[];
};

describe("fixtures/moderation/cases.json", () => {
  test("has cases of both kinds and every verdict", () => {
    for (const kind of ["handle", "name"]) {
      const verdicts = new Set(cases.filter((entry) => entry.kind === kind).map((entry) => entry.expected));
      expect([...verdicts].sort(), kind).toEqual(["invalid", "not_allowed", "ok"]);
    }
  });

  test.each(cases.map((entry) => [entry.kind, JSON.stringify(entry.input), entry.expected, entry] as const))(
    "%s %s is %s",
    (_kind, _input, _expected, entry) => {
      expect(moderate(entry.kind, entry.input)).toBe(entry.expected);
    },
  );
});

describe("the word list", () => {
  test("words are lowercase a-z, which is all the compact form can hold", () => {
    for (const word of [...words.anywhere, ...words.token, ...words.reserved]) expect(word).toMatch(/^[a-z]+$/);
    for (const [from, to] of Object.entries(words.leet)) {
      expect([...from]).toHaveLength(1);
      expect(to).toMatch(/^[a-z]$/);
    }
  });

  test("every word, however it's dressed up, is refused in handles and names", () => {
    for (const word of [...words.anywhere, ...words.token, ...words.reserved]) {
      expect(moderate("handle", `${word}_x`), word).toBe("not_allowed");
      if (word.length <= 12) expect(moderate("name", word.toUpperCase()), word).toBe("not_allowed");
    }
    expect(moderate("handle", "f.u.c.k")).toBe("not_allowed");
    expect(moderate("name", "B1tch")).toBe("not_allowed");
    expect(moderate("name", "N@zi")).toBe("not_allowed");
    expect(moderate("handle", "s3x")).toBe("not_allowed");
  });

  test("token words only match whole tokens", () => {
    expect(moderate("handle", "hello")).toBe("ok");
    expect(moderate("handle", "dickens_fan")).toBe("ok");
    expect(moderate("handle", "scunthorpe")).toBe("not_allowed"); // "cunt" is an anywhere word: a known false positive
  });
});

describe("the steps", () => {
  test("normalise: leet first, then tokens split on anything but a-z", () => {
    expect(normalise("Sh1t_Happens")).toEqual({ tokens: ["shit", "happens"], compact: "shithappens" });
    expect(normalise("🦊🦊")).toEqual({ tokens: [], compact: "" });
    expect(normalise("a.b-c d")).toEqual({ tokens: ["a", "b", "c", "d"], compact: "abcd" });
  });

  test("handles are stored lowercased and names trimmed", () => {
    expect(normaliseHandle("Ava_Smith")).toBe("ava_smith");
    expect(normaliseName("  Noor  ")).toBe("Noor");
  });

  test("names count code points and refuse control characters and lone surrogates", () => {
    expect(isValid("name", "🦊".repeat(12))).toBe(true);
    expect(isValid("name", "🦊".repeat(13))).toBe(false);
    expect(isValid("name", "Ava\n")).toBe(true); // trimmed
    expect(isValid("name", "A\tva")).toBe(false);
    expect(isValid("name", "Ava\ud800")).toBe(false);
  });

  test("every name it accepts fits the Live Activity's `n`", () => {
    const names = [...cases.filter((entry) => entry.kind === "name" && entry.expected === "ok").map((entry) => entry.input), "🦊".repeat(12), "Zoë", "李小龙"];
    for (const name of names) {
      expect(moderate("name", name), name).toBe("ok");
      const member = { i: "Av4Nq8sT2b", n: normaliseName(name), a: "b0.c0.e0.h0", s: 0, b: 1_792_000_000, e: 1_792_001_500 };
      expect(() => parseContentState({ v: 1, m: [member] })).not.toThrow();
    }
  });
});

describe("squad names (M3)", () => {
  test("follow the name rules with a longer limit", () => {
    expect(moderate("name", "x".repeat(13))).toBe("invalid");
    expect(moderate("name", "x".repeat(20), { maxNameLength: 20 })).toBe("ok");
    expect(moderate("name", " Library Goblins ", { maxNameLength: 20 })).toBe("ok");
    expect(moderate("name", "🔒".repeat(20), { maxNameLength: 20 })).toBe("ok");
    expect(moderate("name", "🔒".repeat(21), { maxNameLength: 20 })).toBe("invalid");
    expect(moderate("name", "Lockin Official", { maxNameLength: 20 })).toBe("not_allowed");
    expect(isValid("name", "line\nbreak", { maxNameLength: 20 })).toBe(false);
    // Handles ignore it.
    expect(isValid("handle", "a".repeat(21), { maxNameLength: 40 })).toBe(false);
  });
});
