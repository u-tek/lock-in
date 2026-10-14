// Sessions (docs/milestones/M3.md, SPEC.md §1.4, §4.7): the Worker side of the rooms.
//
//   POST /sessions                    { squadId?, minutes, pushToStart? } -> Joined (solo, or the squad's room: joined, or opened)
//   POST /sessions/:id/join           { minutes, pushToStart? } -> Joined
//   POST /sessions/:id/la-token       { token, env } -> 204
//   POST /sessions/:id/pause|resume|end|slip -> { contentState }
//   POST /sessions/:id/cheer          { to, kind } -> 204
//   GET  /sessions/:id                -> { session, contentState }
//   GET  /sessions/:id/live           WebSocket: { "type": "state", "status", "contentState" } messages
//
// The Worker authenticates the bearer token, checks what only D1 knows (squad membership, the user's
// other sessions), and forwards to the session's `Room` (src/room.ts) with the user's id in a header
// the room trusts. It never forwards the client's own request, so a client can't set that header.
//
// M4: opening a squad's room tells the rest of the squad "X is locking in" once the response has
// gone (src/alerts.ts). A join with `pushToStart` also asks iOS to start the joiner's Live Activity
// (src/pushToStart.ts, the spike) and answers `Joined` plus `pushedToStart`.

import { sendLockinAlerts } from "./alerts.ts";
import { isDeviceToken } from "./apns.ts";
import type { AuthedContext } from "./context.ts";
import { newShortID } from "./context.ts";
import type { UserRow } from "./db.ts";
import type { Env } from "./env.ts";
import { HttpError, apiError, isRecord, json, readObject } from "./http.ts";
import { MAX_NAME_LENGTH, isShortID, textLength } from "./liveActivity.ts";
import { type PushToStartTarget, parsePushToStart, sendPushToStart } from "./pushToStart.ts";
import { type Joined, ROOM_SESSION_HEADER, ROOM_USER_HEADER, type RoomProfile, plannedMinutes } from "./room.ts";

/** What a member is called in the Live Activity when they haven't picked a name. */
export const FALLBACK_MEMBER_NAME = "Lockling";

const ROOM_ORIGIN = "https://room";

/** The room's Durable Object: one per session id. */
function roomStub(env: Env, sessionId: string): DurableObjectStub {
  return env.ROOMS.get(env.ROOMS.idFromName(sessionId));
}

/**
 * A request to the session's room, as `userId`. POSTs always carry a JSON body (`{}` when there's
 * nothing to say), which the room insists on.
 */
export function callRoom(env: Env, sessionId: string, userId: string, action: string, body?: Record<string, unknown>, headers: Record<string, string> = {}): Promise<Response> {
  const init: RequestInit = {
    method: body === undefined ? "GET" : "POST",
    headers: { ...headers, [ROOM_USER_HEADER]: userId, [ROOM_SESSION_HEADER]: sessionId },
  };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
    (init.headers as Record<string, string>)["content-type"] = "application/json";
  }
  return roomStub(env, sessionId).fetch(new Request(`${ROOM_ORIGIN}/${action}`, init));
}

/** The member as the Live Activity shows them: their name (or handle, or "Lockling") and Lockling. */
export function memberProfile(user: UserRow): RoomProfile {
  let name = user.display_name ?? user.handle ?? FALLBACK_MEMBER_NAME;
  if (textLength(name) > MAX_NAME_LENGTH) name = [...name].slice(0, MAX_NAME_LENGTH).join("");
  return { name, avatar: user.avatar_code };
}

function sessionNotFound(): HttpError {
  return apiError(404, "session_not_found", "There's no such session");
}

function notMember(): HttpError {
  return apiError(403, "not_member", "You're not in this squad");
}

async function alreadyInSession(context: AuthedContext): Promise<HttpError | null> {
  const sessionId = await context.db.openParticipation(context.user.id);
  if (sessionId === null) return null;
  return apiError(409, "already_in_session", "You're already in a session. End it first.", { sessionId });
}

/** The room's answer's error code, if it's an error. */
async function errorCode(response: Response): Promise<string | undefined> {
  if (response.ok) return undefined;
  const body = (await response.clone().json().catch(() => null)) as unknown;
  return isRecord(body) && typeof body.code === "string" ? body.code : undefined;
}

/**
 * The room's answer to a join or open, as the app gets it. With a push-to-start target and a
 * successful join, the push goes out first and the answer gains `pushedToStart` (M4 spike).
 */
async function answerJoin(context: AuthedContext, response: Response, pushToStart: PushToStartTarget | undefined): Promise<Response> {
  if (pushToStart === undefined || !response.ok) return response;
  const joined = (await response.json()) as Joined;
  const pushedToStart = await sendPushToStart(context, joined, pushToStart);
  return json({ ...joined, pushedToStart });
}

// POST /sessions

/**
 * Starts a session. Solo without `squadId`. With one, joins the squad's open room, or opens it if
 * there's none: a squad has one room at a time (migrations/0003_squads.sql), so two members locking
 * in together end up in the same one. Opening one (not joining) alerts the rest of the squad, after
 * the response (M4).
 */
export async function startSession(context: AuthedContext): Promise<Response> {
  const { db, user, env } = context;
  const body = await readObject(context.request);
  const minutes = plannedMinutes(body.minutes);
  const pushToStart = parsePushToStart(body.pushToStart);
  let squadId: string | null = null;
  if (body.squadId !== undefined && body.squadId !== null) {
    if (!isShortID(body.squadId) || !(await db.isSquadMember(body.squadId, user.id))) throw notMember();
    squadId = body.squadId;
  }
  const busy = await alreadyInSession(context);
  if (busy !== null) throw busy;
  const profile = memberProfile(user);

  if (squadId === null) {
    return answerJoin(context, await callRoom(env, newShortID(context.random), user.id, "open", { squadId: null, minutes, profile }), pushToStart);
  }
  // Join the open room, or open one. Each lost race (the room ended as we joined, or someone else
  // opened one as we did) goes round again; three in a row means something's stuck.
  for (let attempt = 0; attempt < 3; attempt++) {
    const open = await db.openSessionOfSquad(squadId);
    if (open !== null) {
      const joined = await callRoom(env, open.id, user.id, "join", { minutes, profile });
      if ((await errorCode(joined)) !== "session_ended") return answerJoin(context, joined, pushToStart);
    }
    const sessionId = newShortID(context.random);
    const opened = await callRoom(env, sessionId, user.id, "open", { squadId, minutes, profile });
    if ((await errorCode(opened)) === "room_exists") continue;
    if (opened.ok) context.waitUntil(sendLockinAlerts(context, { squadId, sessionId, openerId: user.id, openerName: profile.name }));
    return answerJoin(context, opened, pushToStart);
  }
  throw apiError(503, "try_again", "Couldn't start the session. Try again.");
}

// POST /sessions/:id/join

export async function joinSession(context: AuthedContext, sessionId: string): Promise<Response> {
  const { db, user, env } = context;
  const body = await readObject(context.request);
  const minutes = plannedMinutes(body.minutes);
  const pushToStart = parsePushToStart(body.pushToStart);
  const session = isShortID(sessionId) ? await db.sessionById(sessionId) : null;
  if (session === null) throw sessionNotFound();
  if (session.status === "ended") throw apiError(410, "session_ended", "This session has ended");
  // A squad's room is for its members; a solo session only for whoever started it.
  const allowed = session.squad_id === null ? session.host_id === user.id : await db.isSquadMember(session.squad_id, user.id);
  if (!allowed) throw notMember();
  const elsewhere = await db.openParticipation(user.id);
  if (elsewhere !== null && elsewhere !== sessionId) {
    throw apiError(409, "already_in_session", "You're already in a session. End it first.", { sessionId: elsewhere });
  }
  return answerJoin(context, await callRoom(env, sessionId, user.id, "join", { minutes, profile: memberProfile(user) }), pushToStart);
}

// POST /sessions/:id/la-token

export async function uploadLiveActivityToken(context: AuthedContext, sessionId: string): Promise<Response> {
  if (!isShortID(sessionId)) throw sessionNotFound();
  const body = await readObject(context.request);
  const { token, env } = body;
  if (!isDeviceToken(token) || (env !== "sandbox" && env !== "production")) {
    throw apiError(422, "token_invalid", 'Expected { token: "<the activity\'s push token, hex>", env: "sandbox" | "production" }');
  }
  return callRoom(context.env, sessionId, context.user.id, "la-token", { token: token.toLowerCase(), env });
}

// POST /sessions/:id/pause, resume, end, slip

export function memberAction(action: "pause" | "resume" | "end" | "slip") {
  return async (context: AuthedContext, sessionId: string): Promise<Response> => {
    if (!isShortID(sessionId)) throw sessionNotFound();
    return callRoom(context.env, sessionId, context.user.id, action, {});
  };
}

// POST /sessions/:id/cheer

export async function cheer(context: AuthedContext, sessionId: string): Promise<Response> {
  if (!isShortID(sessionId)) throw sessionNotFound();
  const body = await readObject(context.request);
  const { to, kind } = body;
  if (!isShortID(to) || typeof kind !== "number" || !Number.isInteger(kind) || kind < 0 || kind > 7) {
    throw apiError(422, "cheer_invalid", "Expected { to: <member id>, kind: 0–7 }");
  }
  return callRoom(context.env, sessionId, context.user.id, "cheer", { to, kind });
}

/** Whether the user may watch the session: they're in it, or in its squad. */
async function mayWatch(context: AuthedContext, sessionId: string): Promise<void> {
  const session = isShortID(sessionId) ? await context.db.sessionById(sessionId) : null;
  if (session === null) throw sessionNotFound();
  if (await context.db.isParticipant(sessionId, context.user.id)) return;
  if (session.squad_id !== null && (await context.db.isSquadMember(session.squad_id, context.user.id))) return;
  throw apiError(403, "not_member", "You're not in this session");
}

// GET /sessions/:id

/**
 * The session and its current content-state, for reconciling on foreground. `contentState` is null
 * once an ended room has been cleared away (a day after it ended); the session still says "ended".
 */
export async function getSession(context: AuthedContext, sessionId: string): Promise<Response> {
  await mayWatch(context, sessionId);
  const response = await callRoom(context.env, sessionId, context.user.id, "state");
  if (response.status !== 404) return response;
  const session = await context.db.sessionById(sessionId);
  if (session === null) throw sessionNotFound();
  return json({
    session: { id: session.id, squadId: session.squad_id, hostId: session.host_id, status: session.status, createdAt: session.created_at },
    contentState: null,
  });
}

// GET /sessions/:id/live

/** The live view: a WebSocket to the room, which sends the state on connect and after every change. */
export async function liveSession(context: AuthedContext, sessionId: string): Promise<Response> {
  if (context.request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    throw apiError(426, "upgrade_required", "Connect with a WebSocket");
  }
  await mayWatch(context, sessionId);
  return callRoom(context.env, sessionId, context.user.id, "live", undefined, { upgrade: "websocket" });
}

/**
 * Takes a user out of every room that's still open, before their account is deleted: their
 * squadmates' Live Activities stop showing them. Failures are logged; the deletion goes ahead.
 */
export async function leaveRoomsForDeletion(env: Env, db: AuthedContext["db"], userId: string): Promise<void> {
  for (const sessionId of await db.openRoomsOf(userId)) {
    try {
      const response = await callRoom(env, sessionId, userId, "forget", {});
      if (!response.ok && response.status !== 404) console.error(`me: room ${sessionId} answered ${response.status} to forget`);
    } catch (error) {
      console.error(`me: couldn't reach room ${sessionId} (${error instanceof Error ? error.name : typeof error})`);
    }
  }
}
