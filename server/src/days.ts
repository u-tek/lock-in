// Calendar days in a time zone (M5): a squad's "today", its streak days and its Monday reset all
// follow the squad's IANA zone (`squads.tz`), so the whole squad shares one midnight.
//
// Days are 'YYYY-MM-DD' strings, which sort and compare as dates. Instants are Unix seconds. A zone
// the runtime doesn't know counts as UTC, as quiet hours do (src/alerts.ts).

const SECONDS_PER_DAY = 24 * 60 * 60;
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

// Formatters are slow to make, and there are only so many time zones.
const formatters = new Map<string, Intl.DateTimeFormat>();
const MAX_FORMATTERS = 512;

function formatter(timeZone: string): Intl.DateTimeFormat {
  let cached = formatters.get(timeZone);
  if (cached !== undefined) return cached;
  const options: Intl.DateTimeFormatOptions = {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    hourCycle: "h23",
  };
  try {
    cached = new Intl.DateTimeFormat("en-GB", { ...options, timeZone });
  } catch {
    cached = new Intl.DateTimeFormat("en-GB", { ...options, timeZone: "UTC" });
  }
  if (formatters.size >= MAX_FORMATTERS) formatters.clear();
  formatters.set(timeZone, cached);
  return cached;
}

/** The wall-clock time in `timeZone` at `unixSeconds`, as if it were UTC (Unix seconds). */
function wallClock(timeZone: string, unixSeconds: number): number {
  const parts: Record<string, number> = {};
  for (const part of formatter(timeZone).formatToParts(new Date(Math.floor(unixSeconds) * 1000))) {
    if (part.type !== "literal") parts[part.type] = Number(part.value);
  }
  const { year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0 } = parts;
  return Date.UTC(year, month - 1, day, hour % 24, minute, second) / 1000;
}

/** The date in `timeZone` at `unixSeconds`: '2026-10-14'. */
export function localDay(timeZone: string, unixSeconds: number): string {
  return utcDay(wallClock(timeZone, unixSeconds));
}

/** Whether `value` is a real calendar date written 'YYYY-MM-DD'. */
export function isDay(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = DAY.exec(value);
  if (match === null) return false;
  const [, year, month, day] = match.map(Number) as [number, number, number, number];
  // Rejects 2026-02-30 and the like: they come back as another date.
  return year >= 1970 && utcDay(Date.UTC(year, month - 1, day) / 1000) === value;
}

/** `day` moved by `count` days (negative goes back). */
export function addDays(day: string, count: number): string {
  return utcDay(utcMidnight(day) + count * SECONDS_PER_DAY);
}

/** The Monday of `day`'s week (ISO weeks start on Monday). */
export function mondayOf(day: string): string {
  const weekday = new Date(utcMidnight(day) * 1000).getUTCDay(); // 0 Sunday … 6 Saturday
  return addDays(day, -((weekday + 6) % 7));
}

/**
 * When `day` begins in `timeZone`, as Unix seconds: its first instant, local midnight. Where a
 * clock change skips midnight, the day begins when the clocks go forward.
 */
export function startOfDay(timeZone: string, day: string): number {
  const target = utcMidnight(day);
  // The zone's offset at a nearby instant, then again at the result, which settles it unless a
  // clock change sits between them.
  let start = target - (wallClock(timeZone, target) - target);
  start = target - (wallClock(timeZone, start) - start);
  // A clock change at midnight: walk in quarter hours (every offset is a multiple of them) to the
  // first instant whose date is `day`.
  for (let step = 0; step < 16 && localDay(timeZone, start - 900) >= day; step++) start -= 900;
  for (let step = 0; step < 16 && localDay(timeZone, start) < day; step++) start += 900;
  return start;
}

/** `[start, end)` of `day` in `timeZone`, Unix seconds: usually 86,400 seconds, 82,800 or 90,000 on a clock change. */
export function dayRange(timeZone: string, day: string): { start: number; end: number } {
  return { start: startOfDay(timeZone, day), end: startOfDay(timeZone, addDays(day, 1)) };
}

function utcMidnight(day: string): number {
  const [year = 1970, month = 1, date = 1] = day.split("-").map(Number);
  return Date.UTC(year, month - 1, date) / 1000;
}

function utcDay(unixSeconds: number): string {
  return new Date(unixSeconds * 1000).toISOString().slice(0, 10);
}
