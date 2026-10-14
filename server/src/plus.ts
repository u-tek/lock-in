// Lockin Plus on the server (docs/milestones/M7.md, SPEC.md §2): who has it, from RevenueCat.
//
//   POST /webhooks/revenuecat   RevenueCat's event -> 200 { ok: true, result }
//   POST /me/plus/refresh       -> { user }   (asks RevenueCat's REST API about the caller)
//
// `users.plus_until` is the one fact: Plus is active while it's in the future (`hasPlus`,
// src/squads.ts). The app logs in to RevenueCat with our user id, so RevenueCat's `app_user_id` is
// ours; anonymous ids (`$RCAnonymousID:…`) belong to nobody here and are ignored.
//
// The webhook is authorised by its `Authorization` header, which must equal REVENUECAT_WEBHOOK_AUTH
// (compared in constant time). Each event counts once however often RevenueCat retries it, and an
// event older than the last one applied to that user (`event_timestamp_ms`) changes nothing, so
// events arriving out of order can't undo a later one (`Database.applyRevenueCatEvent`).
//
// Logs carry the event type and what happened, never an id.

import { publicUser } from "./accounts.ts";
import type { AuthedContext, Context } from "./context.ts";
import { LIFETIME_PLUS_UNTIL, type PlusWrite } from "./db.ts";
import { HttpError, apiError, isRecord, json, readJSON, sameSecret } from "./http.ts";
import { isShortID } from "./liveActivity.ts";
import { refreshRoomPets } from "./sessions.ts";

export const REVENUECAT_API = "https://api.revenuecat.com";
/** The RevenueCat entitlement that is Lockin Plus. */
export const PLUS_ENTITLEMENT = "plus";
/** Handled events are remembered this long: RevenueCat retries for much less. */
export const REVENUECAT_EVENTS_KEPT_SECONDS = 90 * 24 * 60 * 60;
/** RevenueCat's events are a few KB; this is plenty. */
const MAX_WEBHOOK_BYTES = 64 * 1024;

/** Events that give Plus until `expiration_at_ms` (or for life, for a one-time purchase). */
const GRANTS = new Set(["INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_EXTENDED"]);
/** A CANCELLATION with one of these is a refund: Plus ends now. Any other reason (turning off renewal) keeps it to the end of the period. */
const REFUND_REASONS = new Set(["CUSTOMER_SUPPORT", "REFUND"]);

type Plan = { writes: PlusWrite[]; affected: string[] } | { ignored: string };

// POST /webhooks/revenuecat

export async function revenueCatWebhook(context: Context): Promise<Response> {
  const { db, now } = context;
  const secret = (context.env.REVENUECAT_WEBHOOK_AUTH ?? "").trim();
  if (secret.length === 0) throw apiError(503, "not_configured", "The RevenueCat webhook isn't set up (REVENUECAT_WEBHOOK_AUTH)");
  if (!(await sameSecret(context.request.headers.get("authorization") ?? "", secret))) {
    throw apiError(401, "unauthorised", "Wrong Authorization for the RevenueCat webhook");
  }
  const body = await readJSON(context.request, MAX_WEBHOOK_BYTES);
  const event = isRecord(body) ? body.event : undefined;
  if (!isRecord(event) || typeof event.id !== "string" || event.id.length === 0 || event.id.length > 200 || typeof event.type !== "string" || event.type.length > 64) {
    throw new HttpError(400, "Expected RevenueCat's { event: { id, type, … } }");
  }
  const { id, type } = event;
  const answer = (result: string) => {
    console.log(`revenuecat: ${/^[A-Z_]+$/.test(type) ? type : "unknown type"} ${result}`);
    return json({ ok: true, result });
  };
  if (type === "TEST") return answer("test");
  if (await db.revenueCatEventSeen(id)) return answer("duplicate");

  const plan = await planEvent(context, event);
  const writes = "writes" in plan ? plan.writes : [];
  const eventMs = typeof event.event_timestamp_ms === "number" && Number.isFinite(event.event_timestamp_ms) ? Math.floor(event.event_timestamp_ms) : now * 1000;
  // Recorded even when it changes nothing, so a retry is a duplicate.
  const changed = await db.applyRevenueCatEvent({ id, type, eventMs, receivedAt: now, trimBefore: now - REVENUECAT_EVENTS_KEPT_SECONDS, writes });
  if ("ignored" in plan) return answer(`ignored (${plan.ignored})`);
  if (changed === 0) return answer("unchanged (an older event, or already so)");
  // Squad Boost may have started or stopped: rooms show the pet's accessory, or stop.
  context.waitUntil(refreshPetsOf(context, plan.affected));
  return answer("applied");
}

/** What the event does to whose `plus_until`. */
async function planEvent(context: Context, event: Record<string, unknown>): Promise<Plan> {
  const { db, now } = context;
  const type = event.type as string;

  if (type === "TRANSFER") {
    // Purchases moved from one RevenueCat customer to another (a restore under another account):
    // Plus goes with them, from our users among `transferred_from` to ours among `transferred_to`.
    const from = await db.peopleAmong(ourIds(event.transferred_from));
    const fromIds = new Set(from.map((user) => user.id));
    const to = (await db.peopleAmong(ourIds(event.transferred_to))).filter((user) => !fromIds.has(user.id));
    if (from.length === 0 && to.length === 0) return { ignored: "nobody of ours" };
    const moved = Math.max(0, ...from.map((user) => (user.plus_until !== null && user.plus_until > now ? user.plus_until : 0)));
    const writes: PlusWrite[] = from.map((user) => ({ userId: user.id, mode: "clear", until: null }));
    if (moved > 0) for (const user of to) writes.push({ userId: user.id, mode: "raise", until: moved });
    if (writes.length === 0) return { ignored: "nothing to move" };
    return { writes, affected: writes.map((write) => write.userId) };
  }

  if (!GRANTS.has(type) && type !== "EXPIRATION" && type !== "CANCELLATION") return { ignored: "not a Plus change" };
  const entitlements = Array.isArray(event.entitlement_ids)
    ? event.entitlement_ids.filter((each): each is string => typeof each === "string")
    : typeof event.entitlement_id === "string"
      ? [event.entitlement_id]
      : [];
  if (entitlements.length > 0 && !entitlements.includes(PLUS_ENTITLEMENT)) return { ignored: "another entitlement" };

  // Ours, in RevenueCat's order of preference: the id it's using now, then the first, then aliases.
  const candidates = ourIds([event.app_user_id, event.original_app_user_id, ...(Array.isArray(event.aliases) ? event.aliases : [])]);
  const people = new Set((await db.peopleAmong(candidates)).map((user) => user.id));
  const userId = candidates.find((id) => people.has(id));
  if (userId === undefined) return { ignored: "nobody of ours" };

  const expiration = typeof event.expiration_at_ms === "number" && Number.isFinite(event.expiration_at_ms) ? Math.floor(event.expiration_at_ms / 1000) : null;
  let write: PlusWrite;
  if (GRANTS.has(type)) {
    // A one-time purchase (no expiration) is Plus for life.
    const until = type === "NON_RENEWING_PURCHASE" || expiration === null ? LIFETIME_PLUS_UNTIL : expiration;
    write = { userId, mode: until === LIFETIME_PLUS_UNTIL ? "set" : "subscription", until };
  } else if (type === "EXPIRATION") {
    write = { userId, mode: "subscription", until: Math.min(expiration ?? now, now) };
  } else {
    if (typeof event.cancel_reason !== "string" || !REFUND_REASONS.has(event.cancel_reason)) return { ignored: "cancelled, Plus lasts to the end of the period" };
    // A refunded one-time purchase (no expiration) ends a lifetime Plus; a refunded subscription doesn't.
    write = { userId, mode: expiration === null ? "set" : "subscription", until: now };
  }
  return { writes: [write], affected: [userId] };
}

/** Our user ids among RevenueCat's: 10 base62 characters; anonymous ids and anything else are left out. */
function ourIds(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.filter((value): value is string => isShortID(value)))];
}

/** Tells the open rooms of these users' squads to look at their pet again (Squad Boost). Never throws. */
async function refreshPetsOf(context: Context, userIds: string[]): Promise<void> {
  try {
    for (const userId of new Set(userIds)) {
      const rooms = (await context.db.squadZonesOf(userId)).map((zone) => zone.open_session).filter((id): id is string => id !== null);
      await refreshRoomPets(context.env, rooms, userId);
    }
  } catch (error) {
    console.error(`plus: couldn't tell the rooms (${error instanceof Error ? error.name : typeof error})`);
  }
}

// POST /me/plus/refresh

/**
 * Asks RevenueCat what the caller has (`GET /v1/subscribers/<our user id>`) and sets `plus_until`
 * from the `plus` entitlement's `expires_date` (null: for life; no entitlement: no Plus). For the
 * app right after a purchase or a restore, without waiting for the webhook. 503 `not_configured`
 * without REVENUECAT_SECRET_KEY, 503 `try_again` when RevenueCat can't be reached or makes no sense.
 */
export async function refreshPlus(context: AuthedContext): Promise<Response> {
  const { db, user, now } = context;
  const key = (context.env.REVENUECAT_SECRET_KEY ?? "").trim();
  if (key.length === 0) throw apiError(503, "not_configured", "Purchases can't be checked yet (REVENUECAT_SECRET_KEY)");
  const tryAgain = () => apiError(503, "try_again", "Couldn't check your purchases. Try again in a minute.");

  let response: Response;
  try {
    response = await context.fetch(`${REVENUECAT_API}/v1/subscribers/${encodeURIComponent(user.id)}`, {
      headers: { authorization: `Bearer ${key}`, accept: "application/json" },
    });
  } catch (error) {
    console.error(`plus: RevenueCat unreachable (${error instanceof Error ? error.name : typeof error})`);
    throw tryAgain();
  }
  if (!response.ok) {
    console.error(`plus: RevenueCat answered ${response.status}`);
    throw tryAgain();
  }
  const until = plusUntilFromSubscriber(await response.json().catch(() => undefined));
  if (until === undefined) {
    console.error("plus: RevenueCat's answer had no subscriber");
    throw tryAgain();
  }
  const updated = (await db.setPlusUntil(user.id, until, now * 1000)) ?? user;
  if (updated.plus_until !== user.plus_until) context.waitUntil(refreshPetsOf(context, [user.id]));
  console.log("plus: refreshed");
  return json({ user: publicUser(updated) });
}

/**
 * `plus_until` from RevenueCat's subscriber JSON: the `plus` entitlement's `expires_date` (or its
 * billing grace period's, if later); LIFETIME_PLUS_UNTIL when it's null (a one-time purchase); null
 * without the entitlement. Undefined when it isn't a subscriber at all.
 */
export function plusUntilFromSubscriber(body: unknown): number | null | undefined {
  if (!isRecord(body) || !isRecord(body.subscriber)) return undefined;
  const entitlements = body.subscriber.entitlements;
  if (entitlements === undefined || entitlements === null) return null;
  if (!isRecord(entitlements)) return undefined;
  const plus = entitlements[PLUS_ENTITLEMENT];
  if (plus === undefined || plus === null) return null;
  if (!isRecord(plus)) return undefined;
  if (plus.expires_date === null) return LIFETIME_PLUS_UNTIL;
  const expires = unixSeconds(plus.expires_date);
  if (expires === undefined) return undefined;
  const grace = unixSeconds(plus.grace_period_expires_date);
  return grace === undefined ? expires : Math.max(expires, grace);
}

function unixSeconds(value: unknown): number | undefined {
  if (typeof value !== "string") return undefined;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : undefined;
}
