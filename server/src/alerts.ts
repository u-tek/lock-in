// "X is locking in" (docs/milestones/M4.md, SPEC.md §4.5 step 1, §5.7, §7): when someone opens a
// squad's room, the rest of the squad gets an alert with Join 25 and Join 50 (the app's LK_LOCKIN
// category). Sent after the response (`Context.waitUntil`), to every member who
//
// - hasn't muted the squad;
// - hasn't blocked the opener, and isn't blocked by them;
// - isn't in a session already;
// - and on each of their phones that isn't in its quiet hours, in its own time zone;
//
// within the limits: one per squad per recipient every 30 minutes, six per recipient in any 24
// hours, and nothing at all when the opener opened another room in the squad in the last 10 minutes
// (open, end, open again). The limits are checked and recorded in one statement per recipient
// (`Database.reserveAlerts`), so two rooms opening at once can't both slip under them; a
// recipient none of whose phones took the alert is struck off again.
//
// APNs answering 410, or 400 BadDeviceToken, deletes that device. Logs carry the session id and
// counts only.

import { type ApnsResult, isGoneToken } from "./apns.ts";
import type { Context } from "./context.ts";
import type { AlertDeviceRow } from "./db.ts";
import { workerApns } from "./push.ts";

/** Minutes after local midnight; `start` > `end` crosses midnight. */
export interface QuietHours {
  start: number;
  end: number;
}

/** 22:00–07:00: what a phone gets until it says otherwise (SPEC.md §5.7). */
export const DEFAULT_QUIET_HOURS: Readonly<QuietHours> = { start: 22 * 60, end: 7 * 60 };
export const MINUTES_PER_DAY = 24 * 60;

/** One alert per squad per recipient this often. */
export const SQUAD_ALERT_INTERVAL_SECONDS = 30 * 60;
/** At most this many alerts per recipient in any `DAILY_ALERT_WINDOW_SECONDS`, across squads. */
export const DAILY_ALERT_LIMIT = 6;
export const DAILY_ALERT_WINDOW_SECONDS = 24 * 60 * 60;
/** An opener who opened another room in the squad this recently alerts nobody. */
export const REOPEN_SILENCE_SECONDS = 10 * 60;
/** APNs stops trying to deliver an alert after this: by then the room may well be over. */
export const ALERT_EXPIRY_SECONDS = 30 * 60;
/** The `alerts` log keeps this much; the limits look back 24 hours at most. */
export const ALERT_LOG_KEPT_SECONDS = 2 * 24 * 60 * 60;

/** The app's notification category with the Join 25 and Join 50 actions. */
export const LOCKIN_CATEGORY = "LK_LOCKIN";

/** Whole minutes 0–1439, `start` ≠ `end`. */
export function isQuietHours(value: unknown): value is QuietHours {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const { start, end } = value as Record<string, unknown>;
  const minute = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n) && n >= 0 && n < MINUTES_PER_DAY;
  return minute(start) && minute(end) && start !== end;
}

/** Whether `minute` (after local midnight) is quiet: from `start` up to, not including, `end`. */
export function inQuietHours(hours: QuietHours, minute: number): boolean {
  return hours.start < hours.end ? minute >= hours.start && minute < hours.end : minute >= hours.start || minute < hours.end;
}

// Formatters are slow to make, and there are only so many time zones.
const formatters = new Map<string, Intl.DateTimeFormat>();
const MAX_FORMATTERS = 512;

function formatter(timeZone: string): Intl.DateTimeFormat {
  let cached = formatters.get(timeZone);
  if (cached !== undefined) return cached;
  const options: Intl.DateTimeFormatOptions = { hour: "numeric", minute: "numeric", hourCycle: "h23" };
  try {
    cached = new Intl.DateTimeFormat("en-GB", { ...options, timeZone });
  } catch {
    // POST /devices checks the shape of a zone name, not that the runtime knows it. Rather than
    // ignoring quiet hours, an unknown zone counts as UTC.
    cached = new Intl.DateTimeFormat("en-GB", { ...options, timeZone: "UTC" });
  }
  if (formatters.size >= MAX_FORMATTERS) formatters.clear();
  formatters.set(timeZone, cached);
  return cached;
}

/** Minutes after midnight at `unixSeconds` in the IANA zone `timeZone` (UTC if it's unknown). */
export function localMinute(timeZone: string, unixSeconds: number): number {
  let hour = 0;
  let minute = 0;
  for (const part of formatter(timeZone).formatToParts(new Date(unixSeconds * 1000))) {
    if (part.type === "hour") hour = Number(part.value) % 24;
    else if (part.type === "minute") minute = Number(part.value);
  }
  return hour * 60 + minute;
}

/** Whether the phone is in its quiet hours at `now`. Both columns null is off. */
export function deviceIsQuiet(device: Pick<AlertDeviceRow, "tz" | "quiet_start" | "quiet_end">, now: number): boolean {
  if (device.quiet_start === null || device.quiet_end === null) return false;
  return inQuietHours({ start: device.quiet_start, end: device.quiet_end }, localMinute(device.tz, now));
}

/** A room that was just opened, and by whom. */
export interface LockinAlert {
  squadId: string;
  sessionId: string;
  openerId: string;
  /** The opener's Live Activity name: display name, else handle, else "Lockling" (src/sessions.ts). */
  openerName: string;
}

export interface LockinAlertPayload {
  aps: {
    alert: { title: string; body: string };
    sound: "default";
    category: typeof LOCKIN_CATEGORY;
    "thread-id": string;
    "interruption-level": "active";
  };
  /** What the app routes on: the room to join and its squad. */
  lk: { type: "lockin"; sid: string; sq: string };
}

/** The APNs body, exactly as M4.md has it: the squad's name as the title. */
export function lockinAlertPayload(alert: LockinAlert & { squadName: string }): LockinAlertPayload {
  return {
    aps: {
      alert: { title: alert.squadName, body: `${alert.openerName} is locking in 🔒` },
      sound: "default",
      category: LOCKIN_CATEGORY,
      "thread-id": `squad-${alert.squadId}`,
      "interruption-level": "active",
    },
    lk: { type: "lockin", sid: alert.sessionId, sq: alert.squadId },
  };
}

type Outcome = { recipientId: string; token: string } & ({ result: ApnsResult } | { error: string });

/**
 * Alerts the squad that `alert.openerId` just opened a room. Runs after the response; never throws
 * (a failure is logged), so it can go straight to `waitUntil`.
 */
export async function sendLockinAlerts(context: Context, alert: LockinAlert): Promise<void> {
  const { db, now } = context;
  const label = `alerts ${alert.sessionId}`;
  try {
    const apns = workerApns(context.env, context.deps);
    if (apns === null) return;
    if (await db.openedAnotherRoomSince(alert.squadId, alert.openerId, alert.sessionId, now - REOPEN_SILENCE_SECONDS)) {
      console.log(`${label}: none sent (the opener opened another room in the last 10 minutes)`);
      return;
    }
    const squad = await db.squadById(alert.squadId);
    if (squad === null) return;

    // Each recipient's phones that aren't in their quiet hours.
    const phones = new Map<string, AlertDeviceRow[]>();
    const everyone = new Set<string>();
    for (const device of await db.alertCandidates(alert.squadId, alert.openerId)) {
      everyone.add(device.user_id);
      if (deviceIsQuiet(device, now)) continue;
      phones.set(device.user_id, [...(phones.get(device.user_id) ?? []), device]);
    }
    const quiet = everyone.size - phones.size;

    const candidates = [...phones.keys()];
    const reserved = await db.reserveAlerts(
      candidates.map((recipientId) => ({ recipientId, squadId: alert.squadId, senderId: alert.openerId, sessionId: alert.sessionId, sentAt: now })),
      { squadSince: now - SQUAD_ALERT_INTERVAL_SECONDS, daySince: now - DAILY_ALERT_WINDOW_SECONDS, dailyLimit: DAILY_ALERT_LIMIT },
    );
    const recipients = candidates.filter((_, index) => reserved[index]);

    const payload = lockinAlertPayload({ ...alert, squadName: squad.name });
    const outcomes = await Promise.all(
      recipients.flatMap((recipientId) =>
        (phones.get(recipientId) ?? []).map(async (device): Promise<Outcome> => {
          const target = { recipientId, token: device.apns_token };
          try {
            const result = await apns.sendAlert({
              deviceToken: device.apns_token,
              environment: device.apns_env,
              payload,
              collapseId: `lk-${alert.sessionId}`,
              expiration: now + ALERT_EXPIRY_SECONDS,
            });
            return { ...target, result };
          } catch (error) {
            return { ...target, error: error instanceof Error ? error.name : typeof error };
          }
        }),
      ),
    );

    const delivered = new Set<string>();
    const gone: string[] = [];
    let refused = 0;
    let failed = 0;
    for (const outcome of outcomes) {
      if ("error" in outcome) {
        failed += 1;
      } else if (outcome.result.ok) {
        delivered.add(outcome.recipientId);
      } else {
        refused += 1;
        if (isGoneToken(outcome.result)) gone.push(outcome.token);
      }
    }
    await db.afterAlerts({
      sessionId: alert.sessionId,
      undelivered: recipients.filter((id) => !delivered.has(id)),
      goneTokens: gone,
      trimBefore: now - ALERT_LOG_KEPT_SECONDS,
    });
    console.log(
      `${label}: ${delivered.size} alerted, ${quiet} in quiet hours, ${candidates.length - recipients.length} over a limit; ` +
        `${outcomes.length - refused - failed} pushes accepted, ${refused} refused, ${failed} failed, ${gone.length} devices removed`,
    );
  } catch (error) {
    console.error(`${label}: failed (${error instanceof Error ? error.name : typeof error})`);
  }
}
