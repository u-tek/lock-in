// A squad's pet and streak as of now (docs/milestones/M5.md): what GET /squads shows and what the
// squad's room puts in the content-state's `p`. The rules' arithmetic is in src/pet.ts; this reads
// D1 for the squad's day.
//
// "Today" is the squad's calendar day in its own time zone (`squads.tz`). The streak is stored
// (`streak_count`, `streak_last_day`) and moved on by the rooms as finishes come in
// (`Database.syncRoom`); reading it only works out whether it's still alive.
//
// M7: reading it is also when a streak freeze fills a one-day gap (`Database.freezeStatements`), as
// is a finish being written; and the pet wears its accessory while the squad is boosted.

import { addDays, dayRange, localDay } from "./days.ts";
import { type Database, STREAK_FREEZES_PER_MONTH, type SquadRow, type StreakDayWrite, type UserRow } from "./db.ts";
import { PET_RULES, type PetMood, petMood, petProgress, petStage, pickSpecies, streakNeeded } from "./pet.ts";

/** `frozenDays` covers this many days, today included. */
export const FROZEN_DAYS_SHOWN = 30;

export interface SquadStreak {
  /** Days in a row; 0 once broken (the last counted day is before yesterday). */
  count: number;
  /** Whether today counts already. */
  countedToday: boolean;
  /** Members who finished a session of `streakMinMinutes` or more today. */
  doneToday: number;
  /** How many have to for the day to count: half the squad, rounded up, at least 1. */
  needed: number;
  /** M7: days in the last 30 (today included) a Plus member's freeze filled, oldest first. */
  frozenDays: string[];
  /** M7: the viewer's freezes left this calendar month (the squad's): 0 without Plus. */
  freezes: number;
}

export interface SquadProgress {
  /** Picked when the squad was made; the app only hears it once the egg hatches. */
  species: string;
  hatched: boolean;
  stage: number;
  xp: number;
  /** Towards the next stage, 0–1. */
  progress: number;
  mood: PetMood;
  streak: SquadStreak;
  tz: string;
  /** When the mood next changes by itself (Unix seconds): a sad spell ending, or the squad's midnight. */
  changesAt: number;
  /** M7, Squad Boost: a member has Plus. */
  boosted: boolean;
  /** M7: the pet's accessory (`pet.<n>`) while boosted; null otherwise. */
  accessory: number | null;
}

/** The squad's day containing `at`, in its time zone: what a finish then may make count. */
export function streakDay(squadId: string, tz: string, at: number): StreakDayWrite {
  const day = localDay(tz, at);
  return { squadId, day, yesterday: addDays(day, -1), ...dayRange(tz, day) };
}

/**
 * The squad's pet and streak now. A squad from before M5 gets its species here, on first read. If
 * yesterday was missed but the day before counted, a Plus member's freeze fills yesterday (M7). If
 * today counts but the stored streak hasn't heard (the squad got smaller since the last finish, so
 * fewer are needed), it's counted now.
 *
 * `viewer` is whoever's asking (GET /squads): `streak.freezes` is theirs. Rooms leave it out.
 */
export async function squadProgress(
  db: Database,
  row: SquadRow,
  now: number,
  random: (length: number) => Uint8Array,
  viewer?: Pick<UserRow, "id" | "plus_until">,
): Promise<SquadProgress> {
  let squad = row;
  if (squad.pet_species === null) squad = (await db.assignSpecies(squad.id, pickSpecies(random))) ?? squad;
  const today = streakDay(squad.id, squad.tz, now);
  if (squad.streak_last_day === addDays(today.day, -2)) squad = (await db.freezeStreakGap({ squadId: squad.id, day: today.day, now })) ?? squad;
  const [day, boosted, freezes] = await Promise.all([
    db.squadDay(squad.id, today.start, today.end),
    db.squadBoosted(squad.id, now),
    db.streakFreezes(squad.id, addDays(today.day, 1 - FROZEN_DAYS_SHOWN), viewer?.id ?? "", today.day.slice(0, 7)),
  ]);
  const needed = streakNeeded(day.size);
  if (day.counting >= needed && (squad.streak_last_day === null || squad.streak_last_day < today.day)) {
    squad = (await db.countStreakDay(today)) ?? squad;
  }

  const lastDay = squad.streak_last_day;
  const countedToday = lastDay === today.day || day.counting >= needed;
  const hatched = squad.hatched_at !== null;
  const stage = petStage(squad.pet_xp, hatched);
  const sadUntil = squad.last_sad_at === null ? null : squad.last_sad_at + PET_RULES.sadMinutes * 60;
  const sad = sadUntil !== null && now < sadUntil;
  return {
    species: squad.pet_species ?? PET_RULES.species[0] ?? "puff",
    hatched,
    stage,
    xp: squad.pet_xp,
    progress: petProgress(squad.pet_xp, stage),
    mood: petMood({ sad, finished: day.finished, counted: countedToday }),
    streak: {
      // Alive while the last counted day is today or yesterday (a later one means the zone moved west).
      count: lastDay !== null && lastDay >= today.yesterday ? squad.streak_count : 0,
      countedToday,
      doneToday: day.counting,
      needed,
      frozenDays: freezes.days,
      freezes: viewer !== undefined && viewer.plus_until !== null && viewer.plus_until > now ? Math.max(0, STREAK_FREEZES_PER_MONTH - freezes.used) : 0,
    },
    tz: squad.tz,
    changesAt: sad && sadUntil !== null ? Math.min(sadUntil, today.end) : today.end,
    boosted,
    accessory: boosted ? squad.pet_accessory : null,
  };
}
