// Accounts (docs/milestones/M2.md): Sign in with Apple, the profile, handle availability, account
// deletion and device registration.
//
//   POST   /auth/apple        { identityToken, authorizationCode?, displayName? } -> { token, user, isNew }
//   GET    /me                -> { user }
//   PATCH  /me                { handle?, displayName?, avatarCode? } -> { user }
//   DELETE /me                -> 204
//   DELETE /auth/session      -> 204 (signs this token out, M3)
//   GET    /handles/:handle   -> { available, reason? }
//   POST   /devices           { apnsToken, env, pushToStartToken?, laEnabled, frequentPushes, tz, quietHours? } -> 204
//   POST   /me/coins/import   { coins, owned: [itemId] } -> { user, owned }   (M5, once per account)
//
// Logs say what happened, never who: no ids, handles, names or tokens.

import { DEFAULT_QUIET_HOURS, type QuietHours, isQuietHours } from "./alerts.ts";
import { isDeviceToken } from "./apns.ts";
import {
  AppleRequestError,
  AppleTokenError,
  AppleUnavailableError,
  type ExchangeResult,
  appleKeys,
  exchangeAuthorizationCode,
  revokeRefreshToken,
  siwaConfig,
  verifyIdentityToken,
} from "./appleAuth.ts";
import { createSession, hashToken } from "./auth.ts";
import { type AuthedContext, type Context, newShortID } from "./context.ts";
import { type ProfileChanges, type UserRow, isCheckViolation, isUniqueViolation } from "./db.ts";
import { isTimeZoneName } from "./days.ts";
import { HttpError, apiError, bearerToken, json, noContent, readObject } from "./http.ts";
import { moderate, normaliseHandle, normaliseName } from "./moderation.ts";
import { leaveRoomsForDeletion } from "./sessions.ts";
import { checkAvatarOwnership, ownedItems, shopItem } from "./shop.ts";

/** The app's view of an account. Times are Unix seconds. */
export interface User {
  id: string;
  handle: string | null;
  displayName: string | null;
  avatarCode: string;
  coins: number;
  plusUntil: number | null;
  createdAt: number;
}

export function publicUser(row: UserRow): User {
  return {
    id: row.id,
    handle: row.handle,
    displayName: row.display_name,
    avatarCode: row.avatar_code,
    coins: row.coins,
    plusUntil: row.plus_until,
    createdAt: row.created_at,
  };
}

/**
 * `b<body>.c<colour>.e<eyes>.h<hat>`, as Model's AvatarCode writes it. A subset of what the Live
 * Activity's `a` accepts (src/liveActivity.ts), so a saved code always fits the content-state.
 */
const AVATAR_CODE = /^b[0-9]{1,2}\.c[0-9]{1,2}\.e[0-9]{1,2}\.h[0-9]{1,2}$/;

/** POST /me/coins/import brings over at most this many coins (M5). */
export const MAX_IMPORTED_COINS = 5000;
/** …and looks at no more than this many items: the catalogue has 20. */
const MAX_IMPORTED_ITEMS = 100;

/** Apple's authorisation codes are short; this only keeps junk out of the form we post. */
const MAX_AUTHORIZATION_CODE_LENGTH = 1024;

// POST /auth/apple

export async function signInWithApple(context: Context): Promise<Response> {
  const { env, db } = context;
  const body = await readObject(context.request);
  if (typeof body.identityToken !== "string") throw appleTokenInvalid();

  const audience = env.APNS_BUNDLE_ID?.trim() ?? "";
  if (audience.length === 0) throw new HttpError(500, "APNS_BUNDLE_ID isn't set (server/README.md)");
  let sub: string;
  try {
    ({ sub } = await verifyIdentityToken(body.identityToken, { audience, keys: appleKeys(context.deps), now: context.now }));
  } catch (error) {
    if (error instanceof AppleTokenError) throw appleTokenInvalid();
    if (error instanceof AppleUnavailableError) throw apiError(502, "apple_unavailable", "Couldn't reach Apple. Try again in a minute.");
    throw error;
  }

  // Apple shares the name only the first time someone signs in, and it may not suit the Live
  // Activity (12 characters, the filter): then it's left for the app's name picker.
  const name = typeof body.displayName === "string" && moderate("name", body.displayName) === "ok" ? normaliseName(body.displayName) : null;

  let user: UserRow | null = null;
  let isNew = false;
  // A fresh id collides with an existing one about never; the retry is for that, not for races.
  for (let attempt = 0; attempt < 3 && user === null; attempt++) {
    isNew = await db.insertUserIfNew({ id: newShortID(context.random), appleSub: sub, displayName: name, now: context.now });
    user = await db.userByAppleSub(sub);
  }
  if (user === null) throw new Error("Couldn't create the account");
  if (!isNew && user.display_name === null && name !== null) user = (await db.updateProfile(user.id, { displayName: name })) ?? user;

  if (typeof body.authorizationCode === "string" && body.authorizationCode.length > 0) {
    await keepRefreshToken(context, user, sub, body.authorizationCode);
  }

  const token = await createSession(context, user);
  console.log(`auth/apple: ${isNew ? "new account" : "signed in"}`);
  return json({ token, user: publicUser(user), isNew });
}

function appleTokenInvalid(): HttpError {
  return apiError(401, "apple_token_invalid", "Sign in with Apple didn't work. Try again.");
}

/**
 * Swaps the authorisation code for a refresh token so deleting the account can revoke it. Only with
 * the Sign in with Apple key; a failure is logged and sign-in carries on.
 */
async function keepRefreshToken(context: Context, user: UserRow, sub: string, code: string): Promise<void> {
  const config = siwaConfig(context.env);
  if (config === undefined || code.length > MAX_AUTHORIZATION_CODE_LENGTH) return;
  let result: ExchangeResult;
  try {
    result = await exchangeAuthorizationCode(config, code, { fetch: context.fetch, now: () => context.now });
  } catch (error) {
    // Anything but Apple's answer comes from signing the client secret: the key, not Apple.
    const reason = error instanceof AppleRequestError ? error.message : "SIWA_PRIVATE_KEY isn't a usable .p8 key";
    console.error(`auth/apple: token exchange failed (${reason})`);
    return;
  }
  if (result.sub !== undefined && result.sub !== sub) {
    console.warn("auth/apple: the authorisation code was for another Apple ID; not kept");
    return;
  }
  await context.db.setAppleRefreshToken(user.id, result.refreshToken);
  user.apple_refresh_token = result.refreshToken;
}

// GET /me

export async function getMe(context: AuthedContext): Promise<Response> {
  return json({ user: publicUser(context.user) });
}

// PATCH /me

/**
 * M5: an `avatarCode` may only change parts to ones you own (src/shop.ts): 403 `item_not_owned`
 * otherwise, with nothing saved.
 */
export async function patchMe(context: AuthedContext): Promise<Response> {
  const body = await readObject(context.request);
  const changes: ProfileChanges = {};

  if (body.handle !== undefined) {
    if (typeof body.handle !== "string") throw apiError(422, "handle_invalid", handleInvalidMessage);
    const verdict = moderate("handle", body.handle);
    if (verdict === "invalid") throw apiError(422, "handle_invalid", handleInvalidMessage);
    if (verdict === "not_allowed") throw apiError(422, "handle_not_allowed", "That handle isn't allowed. Try another.");
    changes.handle = normaliseHandle(body.handle);
  }
  if (body.displayName !== undefined) {
    if (typeof body.displayName !== "string") throw apiError(422, "name_invalid", nameInvalidMessage);
    const verdict = moderate("name", body.displayName);
    if (verdict === "invalid") throw apiError(422, "name_invalid", nameInvalidMessage);
    if (verdict === "not_allowed") throw apiError(422, "name_not_allowed", "That name isn't allowed. Try another.");
    changes.displayName = normaliseName(body.displayName);
  }
  if (body.avatarCode !== undefined) {
    if (typeof body.avatarCode !== "string" || !AVATAR_CODE.test(body.avatarCode)) {
      throw apiError(422, "avatar_invalid", "That Lockling can't be saved");
    }
    changes.avatarCode = body.avatarCode;
  }

  if (changes.avatarCode !== undefined) await checkAvatarOwnership(context, changes.avatarCode);
  if (changes.handle !== undefined) {
    const owner = await context.db.handleOwner(changes.handle);
    if (owner !== null && owner !== context.user.id) throw handleTaken();
  }
  let updated: UserRow | null;
  try {
    updated = await context.db.updateProfile(context.user.id, changes);
  } catch (error) {
    // Someone took it between the check and the update.
    if (isUniqueViolation(error, "users.handle")) throw handleTaken();
    throw error;
  }
  return json({ user: publicUser(updated ?? context.user) });
}

const handleInvalidMessage = "Handles are 3–20 letters, numbers, _ and ., starting with a letter";
const nameInvalidMessage = "Names are 1–12 characters";

function handleTaken(): HttpError {
  return apiError(409, "handle_taken", "That handle is taken");
}

// GET /handles/:handle

export async function handleAvailability(context: AuthedContext, rawHandle: string): Promise<Response> {
  let handle: string;
  try {
    handle = decodeURIComponent(rawHandle);
  } catch {
    return json({ available: false, reason: "invalid" });
  }
  const verdict = moderate("handle", handle);
  if (verdict !== "ok") return json({ available: false, reason: verdict });
  const owner = await context.db.handleOwner(normaliseHandle(handle));
  // Your own handle is available to you: saving it again changes nothing.
  if (owner !== null && owner !== context.user.id) return json({ available: false, reason: "taken" });
  return json({ available: true });
}

// DELETE /me

/**
 * Deletes the account (App Review 5.1.1(v)): every row that's only theirs goes with it (src/db.ts),
 * reports they filed stay without their name on them, and Apple's refresh token is revoked. A
 * revocation Apple refuses is logged; the account is gone either way.
 *
 * M3: they leave any room that's still open first, so they vanish from their squadmates' Live
 * Activities, and their squads are handed on as if they'd left each one (`Database.deleteUser`).
 */
export async function deleteMe(context: AuthedContext): Promise<Response> {
  const refreshToken = context.user.apple_refresh_token;
  await leaveRoomsForDeletion(context.env, context.db, context.user.id);
  await context.db.deleteUser(context.user.id);

  let revoked = "no Apple token to revoke";
  if (refreshToken !== null) {
    const config = siwaConfig(context.env);
    if (config === undefined) {
      revoked = "Apple token not revoked: no Sign in with Apple key";
    } else {
      try {
        await revokeRefreshToken(config, refreshToken, { fetch: context.fetch, now: () => context.now });
        revoked = "Apple token revoked";
      } catch (error) {
        revoked = `Apple token not revoked (${error instanceof AppleRequestError ? error.message : "SIWA_PRIVATE_KEY isn't a usable .p8 key"})`;
      }
    }
  }
  console.log(`me: account deleted, ${revoked}`);
  return noContent();
}

// DELETE /auth/session

/** Signs out: the bearer token that made this request stops working. Other devices stay signed in. */
export async function signOut(context: AuthedContext): Promise<Response> {
  await context.db.deleteAuthToken(await hashToken(bearerToken(context.request)));
  console.log("auth: signed out");
  return noContent();
}

// POST /devices

/**
 * Registers the phone for pushes (M3, M4). Upserted by APNs token, so a phone that signs into
 * another account moves rather than doubling up. Anything malformed is 422 `device_invalid`.
 *
 * M4: `quietHours` is `{ start, end }` in minutes after local midnight (in `tz`), or null for none.
 * Left out, a new phone gets 22:00–07:00 and a known one keeps what it had.
 */
export async function registerDevice(context: AuthedContext): Promise<Response> {
  const body = await readObject(context.request);
  const invalid = (what: string) => apiError(422, "device_invalid", what);

  if (!isDeviceToken(body.apnsToken)) throw invalid("apnsToken must be the APNs device token in hex");
  if (body.env !== "sandbox" && body.env !== "production") throw invalid('env must be "sandbox" or "production"');
  let pushToStartToken: string | null = null;
  if (body.pushToStartToken !== undefined && body.pushToStartToken !== null) {
    if (!isDeviceToken(body.pushToStartToken)) throw invalid("pushToStartToken must be hex");
    pushToStartToken = body.pushToStartToken.toLowerCase();
  }
  if (typeof body.laEnabled !== "boolean") throw invalid("laEnabled must be true or false");
  if (typeof body.frequentPushes !== "boolean") throw invalid("frequentPushes must be true or false");
  if (!isTimeZoneName(body.tz)) throw invalid("tz must be an IANA time zone name like Australia/Sydney");
  let quietHours: QuietHours | null | undefined;
  if (body.quietHours === null) {
    quietHours = null;
  } else if (body.quietHours !== undefined) {
    if (!isQuietHours(body.quietHours)) {
      throw invalid("quietHours must be null or { start, end }: different whole minutes after midnight, 0–1439");
    }
    quietHours = { start: body.quietHours.start, end: body.quietHours.end };
  }

  await context.db.upsertDevice({
    id: newShortID(context.random),
    userId: context.user.id,
    apnsToken: body.apnsToken.toLowerCase(),
    apnsEnv: body.env,
    pushToStartToken,
    laEnabled: body.laEnabled,
    frequentPushes: body.frequentPushes,
    tz: body.tz,
    quietHours: quietHours === undefined ? DEFAULT_QUIET_HOURS : quietHours,
    keepQuietHours: quietHours === undefined,
    now: context.now,
  });
  // M5: the squads they own follow them to a new time zone.
  await context.db.setOwnedSquadsZone(context.user.id, body.tz);
  return noContent();
}

// POST /me/coins/import

/**
 * Brings over what the app earned while signed out (M5), once per account: `coins` (a whole number,
 * at most MAX_IMPORTED_COINS are added) and `owned`, the items bought with them. Items that aren't
 * in the catalogue, or are Plus items, are skipped; so are ones already owned. 409
 * `already_imported` the second time, with nothing changed.
 */
export async function importCoins(context: AuthedContext): Promise<Response> {
  const body = await readObject(context.request);
  const invalid = () => apiError(422, "import_invalid", "Expected { coins: a whole number from 0, owned: [item ids] }");
  if (typeof body.coins !== "number" || !Number.isInteger(body.coins) || body.coins < 0) throw invalid();
  if (!Array.isArray(body.owned) || body.owned.length > MAX_IMPORTED_ITEMS || !body.owned.every((id) => typeof id === "string")) throw invalid();
  const items = [...new Set(body.owned as string[])].filter((id) => shopItem(id)?.plus === false);
  if (context.user.coins_imported !== 0) throw alreadyImported();

  let updated: UserRow | null;
  try {
    updated = await context.db.importCoins(context.user.id, Math.min(body.coins, MAX_IMPORTED_COINS), items, context.now);
  } catch (error) {
    // Another import got there first.
    if (isCheckViolation(error, "coins_imported")) throw alreadyImported();
    throw error;
  }
  const user = updated ?? context.user;
  console.log("me: coins imported");
  return json({ user: publicUser(user), owned: await ownedItems(context, user) });
}

function alreadyImported(): HttpError {
  return apiError(409, "already_imported", "Your coins are already here");
}
