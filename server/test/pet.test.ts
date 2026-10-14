// The pet's rules (fixtures/pet/rules.json, shared with Model's PetRules), the shop's catalogue
// (fixtures/shop/catalogue.json, shared with the app) and calendar days in a time zone: the pure
// parts of M5. Through the Worker and the rooms: test/progress.test.ts and test/shop.test.ts.

import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { addDays, dayRange, isDay, isTimeZoneName, localDay, mondayOf, startOfDay } from "../src/days.ts";
import { LAST_STAGE, PET_RULES, PetMood, petMood, petProgress, petStage, pickSpecies, sessionCoins, streakNeeded, wholeMinutes } from "../src/pet.ts";
import { SHOP_ITEMS, avatarItemIds, shopItem } from "../src/shop.ts";
import { T0 } from "./app.ts";

const fixture = (path: string) => JSON.parse(readFileSync(new URL(`../../fixtures/${path}`, import.meta.url), "utf8")) as Record<string, any>;

describe("fixtures/pet/rules.json", () => {
  test("is what the server runs on, every number of it", () => {
    expect(PET_RULES).toEqual(fixture("pet/rules.json"));
    expect(PET_RULES).toEqual({
      species: ["puff", "sprout", "ember", "pebble"],
      stageXp: [0, 0, 600, 3000, 10000, 25000],
      streakMinMinutes: 20,
      streakShare: 0.5,
      sadMinutes: 30,
      coinsPerMinute: 1,
      completionBonus: 5,
    });
    expect(LAST_STAGE).toBe(5);
  });

  test("species are pet codes the Live Activity takes", () => {
    for (const species of PET_RULES.species) expect(species).toMatch(/^[a-z]{1,10}$/);
  });
});

describe("stages", () => {
  test("an egg until it hatches, whatever its XP", () => {
    for (const xp of [0, 599, 600, 25_000, 1_000_000]) expect(petStage(xp, false)).toBe(0);
  });

  test.each([
    [0, 1],
    [599, 1],
    [600, 2],
    [2999, 2],
    [3000, 3],
    [9999, 3],
    [10_000, 4],
    [24_999, 4],
    [25_000, 5],
    [10_000_000, 5],
  ])("hatched with %i XP: stage %i (never below 1, never past the table)", (xp, stage) => {
    expect(petStage(xp, true)).toBe(stage);
  });

  test("progress runs 0–1 within a stage: 0 for an egg, 1 at the last stage", () => {
    expect(petProgress(500, 0)).toBe(0);
    expect(petProgress(0, 1)).toBe(0);
    expect(petProgress(300, 1)).toBe(0.5);
    expect(petProgress(1800, 2)).toBe(0.5);
    expect(petProgress(1350, 2)).toBe(0.3125);
    expect(petProgress(17_500, 4)).toBe(0.5);
    expect(petProgress(25_000, 5)).toBe(1);
    expect(petProgress(99_999, 5)).toBe(1);
    // Clamped, should a stage and its XP ever disagree.
    expect(petProgress(100, 2)).toBe(0);
    expect(petProgress(5000, 2)).toBe(1);
  });
});

describe("mood", () => {
  test("sad trumps everything, then happy when today counts, content when someone finished, else hungry", () => {
    expect(petMood({ sad: true, finished: 3, counted: true })).toBe(PetMood.sad);
    expect(petMood({ sad: false, finished: 0, counted: false })).toBe(PetMood.hungry);
    expect(petMood({ sad: false, finished: 1, counted: false })).toBe(PetMood.content);
    expect(petMood({ sad: false, finished: 2, counted: true })).toBe(PetMood.happy);
    expect([PetMood.sad, PetMood.hungry, PetMood.content, PetMood.happy]).toEqual([0, 1, 2, 3]);
  });
});

describe("streaks and coins", () => {
  test.each([
    [0, 1],
    [1, 1],
    [2, 1],
    [3, 2],
    [4, 2],
    [5, 3],
    [6, 3],
  ])("a squad of %i needs %i to finish for the day to count", (size, needed) => {
    expect(streakNeeded(size)).toBe(needed);
  });

  test("a coin per whole focused minute, plus 5 for finishing (SessionRecord's numbers)", () => {
    expect(sessionCoins(25 * 60, true)).toBe(30);
    expect(sessionCoins(25 * 60, false)).toBe(25);
    expect(sessionCoins(24 * 60 + 59, false)).toBe(24);
    expect(sessionCoins(59, false)).toBe(0);
    expect(sessionCoins(0, true)).toBe(5);
    expect(wholeMinutes(-5)).toBe(0);
  });
});

describe("species", () => {
  test("picked uniformly from the rules", () => {
    let byte = 0;
    const counts = new Map<string, number>();
    for (let n = 0; n < 256; n++) {
      const species = pickSpecies(() => new Uint8Array([byte++ % 256]));
      counts.set(species, (counts.get(species) ?? 0) + 1);
    }
    expect([...counts.keys()].sort()).toEqual([...PET_RULES.species].sort());
    for (const count of counts.values()) expect(count).toBe(256 / PET_RULES.species.length);
  });
});

describe("fixtures/shop/catalogue.json", () => {
  // CreatureCatalogue.swift: the options of each part, in avatar-code order; 0 is the free default.
  const parts = {
    body: { options: ["classic", "round", "tall", "chunky", "heart"], plus: [4] },
    colour: { options: ["indigo", "blue", "teal", "mint", "green", "orange", "pink", "purple"], plus: [6, 7] },
    eyes: { options: ["dots", "happy", "sleepy", "sparkly", "wink"], plus: [3] },
    hat: { options: ["noHat", "beanie", "headphones", "cap", "flower", "crown"], plus: [2, 5] },
    // M7, Squad Boost: the squad pet's accessories, all Plus (drawn by the app's PetView).
    pet: { options: ["none", "scarf", "partyHat", "flowerCrown", "glasses", "bow", "starClip"], plus: [1, 2, 3, 4, 5, 6] },
  };

  test("is what the server sells", () => {
    expect(SHOP_ITEMS).toEqual(fixture("shop/catalogue.json").items);
  });

  test("lists every option but the default of every part, Plus ones free and marked", () => {
    const expected = Object.entries(parts).flatMap(([part, { options, plus }]) =>
      options.slice(1).map((_, index) => ({ id: `${part}.${index + 1}`, part, option: index + 1, plus: plus.includes(index + 1) })),
    );
    expect(SHOP_ITEMS.map(({ id, part, option, plus }) => ({ id, part, option, plus }))).toEqual(expected);
    for (const item of SHOP_ITEMS) {
      expect(Object.keys(item)).toEqual(["id", "part", "option", "price", "plus"]);
      if (item.plus) expect(item.price).toBe(0);
      else expect(item.price).toBeGreaterThan(0);
    }
  });

  test("a 25-minute session (30 coins) buys a colour in about two", () => {
    const colours = SHOP_ITEMS.filter((item) => item.part === "colour" && !item.plus).map((item) => item.price);
    expect(Math.max(...colours)).toBeLessThanOrEqual(2 * sessionCoins(25 * 60, true));
    expect(Math.min(...colours)).toBeGreaterThan(sessionCoins(25 * 60, true));
  });

  test("avatar codes name items by part letter: b body, c colour, e eyes, h hat", () => {
    expect([...avatarItemIds("b3.c7.e2.h4")]).toEqual([
      ["body", "body.3"],
      ["colour", "colour.7"],
      ["eyes", "eyes.2"],
      ["hat", "hat.4"],
    ]);
    expect([...avatarItemIds("b0.c0.e0.h0")]).toEqual([]);
    expect([...avatarItemIds("b0.c2.e0.h0")]).toEqual([["colour", "colour.2"]]);
    expect(shopItem("hat.5")).toEqual({ id: "hat.5", part: "hat", option: 5, price: 0, plus: true });
    expect(shopItem("hat.0")).toBeUndefined();
    expect(shopItem("hat.99")).toBeUndefined();
  });
});

describe("days in a time zone", () => {
  test("the same instant is a different day in Sydney and Los Angeles", () => {
    // T0 is Wednesday 2026-10-14, 17:46 UTC.
    expect(localDay("UTC", T0)).toBe("2026-10-14");
    expect(localDay("Australia/Sydney", T0)).toBe("2026-10-15");
    expect(localDay("America/Los_Angeles", T0)).toBe("2026-10-14");
    // A zone the runtime doesn't know counts as UTC.
    expect(localDay("Mars/Olympus_Mons", T0)).toBe("2026-10-14");
  });

  test("a day starts at local midnight, and lasts 23 or 25 hours on a clock change", () => {
    expect(startOfDay("UTC", "2026-10-14")).toBe(Date.UTC(2026, 9, 14) / 1000);
    // Sydney is UTC+11 in October (daylight saving began on the 4th).
    expect(startOfDay("Australia/Sydney", "2026-10-15")).toBe(Date.UTC(2026, 9, 14, 13) / 1000);
    expect(startOfDay("America/Los_Angeles", "2026-10-14")).toBe(Date.UTC(2026, 9, 14, 7) / 1000);
    const sydneySpring = dayRange("Australia/Sydney", "2026-10-04");
    expect(sydneySpring.end - sydneySpring.start).toBe(23 * 3600);
    const angelesFall = dayRange("America/Los_Angeles", "2026-11-01");
    expect(angelesFall.end - angelesFall.start).toBe(25 * 3600);
    // Where midnight itself is skipped (Santiago springs forward 00:00 -> 01:00), the day starts at 01:00.
    const santiago = startOfDay("America/Santiago", "2026-09-06");
    expect(localDay("America/Santiago", santiago)).toBe("2026-09-06");
    expect(localDay("America/Santiago", santiago - 1)).toBe("2026-09-05");
  });

  test("weeks start on Monday; dates are checked for real", () => {
    expect(mondayOf("2026-10-14")).toBe("2026-10-12");
    expect(mondayOf("2026-10-12")).toBe("2026-10-12");
    expect(mondayOf("2026-10-18")).toBe("2026-10-12");
    expect(mondayOf("2026-01-01")).toBe("2025-12-29");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
    for (const day of ["2026-10-14", "2024-02-29"]) expect(isDay(day)).toBe(true);
    for (const day of ["2026-02-30", "2026-13-01", "2026-1-14", "14/10/2026", "2026-10-14T00:00", "", 20261014, null]) expect(isDay(day)).toBe(false);
    expect(isTimeZoneName("Australia/Sydney")).toBe(true);
    expect(isTimeZoneName("../etc")).toBe(false);
  });
});
