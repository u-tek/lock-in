// The app's sessions: an opaque bearer token (32 random bytes, base64url) handed out by
// POST /auth/apple. The server stores only its SHA-256, so the tokens can't be read back out of D1.
// Tokens don't expire; deleting the account deletes them.

import type { AuthedContext, Context } from "./context.ts";
import { newSessionToken } from "./context.ts";
import type { UserRow } from "./db.ts";
import { apiError, bearerToken } from "./http.ts";

/** `last_used_at` is written at most this often per token. */
export const TOUCH_INTERVAL_SECONDS = 60 * 60;

/** 43 base64url characters: what `newSessionToken` makes. Anything else isn't looked up. */
const SESSION_TOKEN = /^[A-Za-z0-9_-]{43}$/;

/** Lowercase hex SHA-256: what auth_tokens.token_hash holds. */
export async function hashToken(token: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Starts a session for `user` and returns its bearer token. */
export async function createSession(context: Context, user: UserRow): Promise<string> {
  const token = newSessionToken(context.random);
  await context.db.insertAuthToken(await hashToken(token), user.id, context.now);
  return token;
}

/** The user behind the request's bearer token, or 401 `unauthorised`. */
export async function authenticate(context: Context): Promise<AuthedContext> {
  const token = bearerToken(context.request);
  if (!SESSION_TOKEN.test(token)) throw unauthorised();
  const hash = await hashToken(token);
  const session = await context.db.userForToken(hash);
  if (session === null) throw unauthorised();
  if (context.now - session.lastUsedAt >= TOUCH_INTERVAL_SECONDS) await context.db.touchAuthToken(hash, context.now);
  return { ...context, user: session.user };
}

function unauthorised() {
  return apiError(401, "unauthorised", "Sign in again");
}
