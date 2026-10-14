// Analytics without a provider (docs/decisions/0010-analytics-provider.md, proposed): the app's
// integer event counts, added to daily totals in D1.
//
//   POST /metrics   { "counts": { "<event>": <whole number>, … } }  -> 204
//
// Anyone can call it, signed in or not: most people use Lockin solo, without an account. Nothing
// about the caller is read or kept: not the bearer token (even if one is sent), not a device, not
// the IP address (the per-IP limit below is Cloudflare's counter, never stored by us). A row is a
// UTC day, an event name and a total, so nothing in it is linked to anyone.
//
// Event names must be in fixtures/analytics/events.json, the app's `AnalyticsEvent` list, which
// CoreTests checks against the Swift enum. Each count is a whole number from 1 to MAX_COUNT.
//
// Limits: METRICS_LIMITER (wrangler.toml, Cloudflare's rate-limiting binding) allows a few batches
// a minute from one IP address; DAILY_BATCH_LIMIT batches a day in all, so a flood can't use up
// D1's daily writes, which the rest of the API needs. Over either: 429 `rate_limited` with
// `retryAfter` and a Retry-After header. The app is to keep its counts and try again later.

import events from "../../fixtures/analytics/events.json";
import type { Context } from "./context.ts";
import { apiError, noContent, readObject, isRecord } from "./http.ts";

/** Every event name the app can send. */
export const METRIC_EVENTS: ReadonlySet<string> = new Set(events.events);

/** The most one batch can add to one event: a phone that was offline for weeks sends several. */
export const MAX_COUNT = 250;

/**
 * Batches a day, from everyone. The app sends at most one a day, so this is roughly the daily
 * phones it allows for; each batch writes one row per event in it, plus one.
 */
export const DAILY_BATCH_LIMIT = 10_000;

/** The UTC day, `YYYY-MM-DD`, of a time in Unix seconds. */
export function utcDay(seconds: number): string {
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}

// POST /metrics

export async function recordMetrics(context: Context): Promise<Response> {
  const limiter = context.env.METRICS_LIMITER;
  if (limiter !== undefined) {
    const address = context.request.headers.get("cf-connecting-ip") ?? "unknown";
    const { success } = await limiter.limit({ key: `metrics:${address}` });
    if (!success) throw apiError(429, "rate_limited", "Too many analytics batches from here just now. Try again in a minute.", { retryAfter: 60 });
  }

  const counts = parseCounts(await readObject(context.request));
  const day = utcDay(context.now);
  if (!(await context.db.reserveMetricsBatch(day, DAILY_BATCH_LIMIT))) {
    // Until the next UTC day.
    const retryAfter = Math.max(1, Math.ceil(Date.parse(`${day}T00:00:00Z`) / 1000) + 86_400 - context.now);
    throw apiError(429, "rate_limited", "Analytics are full for today. Try again tomorrow.", { retryAfter });
  }
  await context.db.addMetrics(day, counts);
  return noContent();
}

/** `{ counts: { event: n } }`, checked strictly: 422 `metrics_invalid` saying what's wrong. */
export function parseCounts(body: Record<string, unknown>): Map<string, number> {
  const invalid = (message: string) => apiError(422, "metrics_invalid", message);
  const extra = Object.keys(body).filter((key) => key !== "counts");
  if (extra.length > 0) throw invalid("The body takes `counts` only");
  const counts = body.counts;
  if (!isRecord(counts)) throw invalid("`counts` must be an object of event names and whole numbers");
  const entries = Object.entries(counts);
  if (entries.length === 0) throw invalid("`counts` is empty");
  const parsed = new Map<string, number>();
  for (const [event, count] of entries) {
    // The name isn't quoted back: the message says which rule, not what was sent.
    if (!METRIC_EVENTS.has(event)) throw invalid("An event name isn't one the app sends (fixtures/analytics/events.json)");
    if (typeof count !== "number" || !Number.isInteger(count) || count < 1 || count > MAX_COUNT) {
      throw invalid(`Each count must be a whole number from 1 to ${MAX_COUNT}`);
    }
    parsed.set(event, count);
  }
  return parsed;
}
