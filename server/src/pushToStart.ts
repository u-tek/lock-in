// Push-to-start, the M4 spike (SPEC.md §4.5 step 3, docs/milestones/M4.md): Join 25 / Join 50 run
// in the background, so the app can't start the Live Activity itself; it sends its push-to-start
// token with the join, and the server asks iOS to start the activity:
//
//   apns-push-type: liveactivity   apns-topic: <bundle id>.push-type.liveactivity   apns-priority: 10
//   { "aps": { "timestamp", "event": "start", "content-state", "attributes-type": "LockinAttributes",
//              "attributes": { sid, me, sq }, "alert": { title, body }, "input-push-token": 1, "stale-date" } }
//
// iOS then wakes the app with the new activity's update token, which it uploads with
// POST /sessions/:id/la-token as usual. Squad rooms only: the alert's title is the squad's name.
//
// A 410, or 400 BadDeviceToken, means the push-to-start token is gone: it's cleared from `devices`.

import { type ApnsEnvironment, isDeviceToken, isGoneToken } from "./apns.ts";
import type { Context } from "./context.ts";
import { apiError, isRecord } from "./http.ts";
import {
  type Attributes,
  type ContentState,
  type LiveActivityAlert,
  type LiveActivityPayload,
  MemberState,
  buildLiveActivityPayload,
  staleDateFor,
} from "./liveActivity.ts";
import { workerApns } from "./push.ts";

/** Where to start the activity: the app's push-to-start token (`pushToStartTokenUpdates`) and its APNs environment. */
export interface PushToStartTarget {
  token: string;
  env: ApnsEnvironment;
}

/** `pushToStart` from a join's body: undefined when left out (or null), 422 `token_invalid` when malformed. */
export function parsePushToStart(value: unknown): PushToStartTarget | undefined {
  if (value === undefined || value === null) return undefined;
  if (!isRecord(value) || !isDeviceToken(value.token) || (value.env !== "sandbox" && value.env !== "production")) {
    throw apiError(422, "token_invalid", 'Expected pushToStart: { token: "<push-to-start token, hex>", env: "sandbox" | "production" }');
  }
  return { token: value.token.toLowerCase(), env: value.env };
}

const RUNNING: readonly number[] = [MemberState.focusing, MemberState.break, MemberState.paused];

/**
 * "You're locked in with Ava": whoever else is running, host first. Two are named ("Ava and Noor"),
 * more are counted ("Ava and 3 others"), and with nobody else it's "You're locked in".
 */
export function lockedInWith(state: ContentState, me: string): string {
  const others = state.m.filter((member) => member.i !== me && RUNNING.includes(member.s)).map((member) => member.n);
  const [first, second] = others;
  if (first === undefined) return "You're locked in";
  if (second === undefined) return `You're locked in with ${first}`;
  if (others.length === 2) return `You're locked in with ${first} and ${second}`;
  return `You're locked in with ${first} and ${others.length - 1} others`;
}

/**
 * The push-to-start body for `me` in this room, or null for a solo session (no squad name for the
 * title). Throws `LiveActivityError` if it's over the 3,584-byte budget or APNs' 4,096-byte body.
 */
export function pushToStartPayload(attributes: Attributes, state: ContentState, now: number): LiveActivityPayload | null {
  if (attributes.sq === undefined) return null;
  const alert: LiveActivityAlert = { title: attributes.sq, body: lockedInWith(state, attributes.me) };
  return buildLiveActivityPayload({ event: "start", state, timestamp: now, staleDate: staleDateFor(state, now), alert, attributes });
}

/**
 * Sends the push-to-start for a join and says whether APNs took it. False, never an error, when it
 * couldn't be built, APNs isn't set up or can't be reached, or refused it: the app then starts the
 * activity itself next time it's in the foreground.
 */
export async function sendPushToStart(
  context: Context,
  joined: { attributes: Attributes; contentState: ContentState },
  target: PushToStartTarget,
): Promise<boolean> {
  const label = `push-to-start ${joined.attributes.sid}`;
  let payload: LiveActivityPayload | null;
  try {
    payload = pushToStartPayload(joined.attributes, joined.contentState, context.now);
  } catch (error) {
    // The validators bound every field, so this means a bug: say so without quoting the state.
    console.error(`${label}: payload refused (${error instanceof Error ? error.name : typeof error})`);
    return false;
  }
  if (payload === null) return false;
  const apns = workerApns(context.env, context.deps);
  if (apns === null) return false;

  try {
    const result = await apns.sendLiveActivity({ deviceToken: target.token, environment: target.env, priority: 10, payload });
    console.log(`${label}: ${target.env} -> APNs ${result.status}${result.reason === undefined ? "" : ` ${result.reason}`}`);
    if (!result.ok && isGoneToken(result)) await context.db.clearPushToStartToken(target.token);
    return result.ok;
  } catch (error) {
    console.error(`${label}: push failed (${error instanceof Error ? error.name : typeof error})`);
    return false;
  }
}
