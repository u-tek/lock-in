// The squad pet's numbers and the arithmetic on them (docs/milestones/M5.md, "Rules"): stages from
// XP, progress, mood, the streak's share of the squad, and coins.
//
// The numbers are imported straight from fixtures/pet/rules.json, which Model's `PetRules` tests
// against too, so the app and the server can't drift. wrangler's bundler inlines the JSON (as it
// does the moderation word list).

import rules from "../../fixtures/pet/rules.json";

export interface PetRulesFile {
  /** The species a new squad's egg is picked from. Names are a wire format (`Pet.k`). */
  species: string[];
  /** The XP each stage starts at: 0 egg, 1 baby, 2 teen, 3 adult, 4+ prestige. */
  stageXp: number[];
  /** A finished session counts towards the streak from this many focused minutes. */
  streakMinMinutes: number;
  /** The share of the squad (rounded up, at least one) whose day has to count. */
  streakShare: number;
  /** The pet is sad this long after a slip or an early leave. */
  sadMinutes: number;
  coinsPerMinute: number;
  /** Coins for finishing, on top of the minutes. */
  completionBonus: number;
}

export const PET_RULES: Readonly<PetRulesFile> = rules;

/** The highest stage there is: stages past the table's end don't exist yet. */
export const LAST_STAGE = PET_RULES.stageXp.length - 1;

export const PetMood = {
  /** Someone slipped or left early in the squad's room within the last `sadMinutes`. */
  sad: 0,
  /** Nobody in the squad has finished a session today. */
  hungry: 1,
  /** Someone has, but today doesn't count for the streak yet. */
  content: 2,
  /** Today counts. */
  happy: 3,
} as const;
export type PetMood = (typeof PetMood)[keyof typeof PetMood];

/** The stage: 0 until it hatches, then the highest `n` with `xp >= stageXp[n]`, never below 1. */
export function petStage(xp: number, hatched: boolean): number {
  if (!hatched) return 0;
  let stage = 1;
  PET_RULES.stageXp.forEach((start, index) => {
    if (xp >= start) stage = Math.max(stage, index);
  });
  return stage;
}

/** How far from `stage` to the next, 0–1: 0 for an egg, 1 at the last stage. */
export function petProgress(xp: number, stage: number): number {
  if (stage < 1) return 0;
  if (stage >= LAST_STAGE) return 1;
  const start = PET_RULES.stageXp[stage] ?? 0;
  const end = PET_RULES.stageXp[stage + 1] ?? start;
  if (end <= start) return 1;
  return Math.min(Math.max((xp - start) / (end - start), 0), 1);
}

/** Today's mood: sad trumps everything, then whether anyone finished and whether the day counts. */
export function petMood(today: { sad: boolean; finished: number; counted: boolean }): PetMood {
  if (today.sad) return PetMood.sad;
  if (today.counted) return PetMood.happy;
  return today.finished > 0 ? PetMood.content : PetMood.hungry;
}

/** How many members must finish a counting session for the day to count: half, rounded up, at least 1. */
export function streakNeeded(squadSize: number): number {
  return Math.max(1, Math.ceil(squadSize * PET_RULES.streakShare));
}

/** Whole focused minutes: what XP and coins are counted in. */
export function wholeMinutes(focusedSec: number): number {
  return Math.max(0, Math.floor(focusedSec / 60));
}

/** Coins for one timer: per whole focused minute, plus the bonus for finishing (as SessionRecord has it). */
export function sessionCoins(focusedSec: number, completed: boolean): number {
  return wholeMinutes(focusedSec) * PET_RULES.coinsPerMinute + (completed ? PET_RULES.completionBonus : 0);
}

/** A species for a new egg, uniformly: bytes past the last whole multiple are skipped. */
export function pickSpecies(random: (length: number) => Uint8Array): string {
  const count = PET_RULES.species.length;
  const limit = 256 - (256 % count);
  for (let round = 0; round < 32; round++) {
    for (const byte of random(8)) {
      if (byte < limit) return PET_RULES.species[byte % count] as string;
    }
  }
  throw new Error("The random source keeps returning bytes over the limit");
}
