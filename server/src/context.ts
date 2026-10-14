// What every route gets: the request, the bindings, D1 and the injectable world (fetch, clock,
// randomness and work after the response), so tests can drive the Worker with a fake Apple, a fixed
// clock and known ids, and wait for what it does once it has answered.

import type { Database, UserRow } from "./db.ts";
import type { Env } from "./env.ts";
import { base64url } from "./jwt.ts";

/** Injected by tests; the Worker uses the real `fetch`, clock and `crypto.getRandomValues`. */
export interface Dependencies {
  fetch?: typeof fetch;
  /** Unix seconds. */
  now?: () => number;
  /** `length` random bytes. */
  random?: (length: number) => Uint8Array;
  /**
   * Keeps the Worker running for `promise` after the response has gone: the runtime's
   * `ExecutionContext.waitUntil`. Tests collect the promises to await them.
   */
  waitUntil?: (promise: Promise<unknown>) => void;
}

export interface Context {
  request: Request;
  url: URL;
  env: Env;
  deps: Dependencies;
  db: Database;
  /** Whole Unix seconds, read once per request. */
  now: number;
  fetch: typeof fetch;
  random: (length: number) => Uint8Array;
  /** Work to finish after the response (M4's alerts). It must catch its own errors. */
  waitUntil: (promise: Promise<unknown>) => void;
}

/** A route behind the bearer token: `user` is whoever it belongs to. */
export interface AuthedContext extends Context {
  user: UserRow;
}

export function makeContext(request: Request, env: Env, deps: Dependencies, db: Database): Context {
  const fetcher = deps.fetch ?? fetch;
  return {
    request,
    url: new URL(request.url),
    env,
    deps,
    db,
    now: Math.floor((deps.now ?? (() => Date.now() / 1000))()),
    // Wrapped: called as a method, the global fetch would get the context as `this`, which Workers
    // refuse ("Illegal invocation").
    fetch: (input, init) => fetcher(input, init),
    random: deps.random ?? ((length) => crypto.getRandomValues(new Uint8Array(length))),
    // Without the runtime's (a test calling `handle` bare), the work still runs; nothing waits for it.
    waitUntil: deps.waitUntil ?? ((promise) => void promise.catch(() => undefined)),
  };
}

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/** A 10-character base62 id (users, devices, reports), unbiased: bytes from 248 up are skipped. */
export function newShortID(random: (length: number) => Uint8Array): string {
  let id = "";
  for (let round = 0; id.length < 10; round++) {
    if (round === 32) throw new Error("The random source keeps returning bytes over 247");
    for (const byte of random(16)) {
      if (byte < 248 && id.length < 10) id += BASE62[byte % 62];
    }
  }
  return id;
}

/** Friend codes: no 0/O or 1/I, so a code read off a screen types back in correctly. */
export const FRIEND_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const FRIEND_CODE_LENGTH = 8;

/** 8 characters from the 32-letter alphabet: one byte's low 5 bits each, so no bias. */
export function newFriendCode(random: (length: number) => Uint8Array): string {
  return [...random(FRIEND_CODE_LENGTH)].map((byte) => FRIEND_CODE_ALPHABET[byte & 31]).join("");
}

/** A session token: 32 random bytes, base64url (43 characters). */
export function newSessionToken(random: (length: number) => Uint8Array): string {
  return base64url(random(32));
}
