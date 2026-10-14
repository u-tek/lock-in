// A session's room: one Durable Object per session id (SPEC.md §1.4, §4; docs/milestones/M3.md).
//
// The room is the authority for everyone's timer in the session. Each member runs their own timer
// (b, e, q); the room builds the one content-state every member's Live Activity shows (host first,
// at most 6 members, the squad pet, the latest cheer), bumps `v` on every change, and:
//
// - coalesces changes for 2 seconds (an alarm), then pushes the latest state to every member's Live
//   Activity token, at priority 10 if anything in the batch was a join, finish, early leave or slip
//   and 5 otherwise (SPEC.md §4.4);
// - finishes timers itself: an alarm at the next `e` marks that member done;
// - clears a cheer 10 seconds after it arrives;
// - ends when nobody's timer is running any more: one `end` push with dismissal-date now + 30 min,
//   the session marked ended in D1, and the room's push counts logged;
// - serves the app's live view over a WebSocket (the hibernation API), sending the state on connect
//   and after every change.
//
// The Worker authenticates the caller and forwards to the room with the user's id in
// `x-lockin-user` (src/sessions.ts). Nothing but the Worker's own code can reach a Durable Object, so
// the room trusts that header; the Worker never forwards a client's request as it came.
//
// Every timed job shares the one alarm a Durable Object has: the next push, timer end, 8-hour cap,
// cheer to clear, D1 retry or clean-up, whichever is soonest. State lives in storage under "room",
// so the object can be evicted (and its WebSockets hibernate) at any time.
//
// Logs carry the room id and counts only: never tokens, names or user ids.
//
// A plain class rather than `extends DurableObject` from "cloudflare:workers", so the tests can
// load it in Node. It uses DurableObjectState through the small `RoomState` interface below, which
// tests fake.

import { ApnsClient, type ApnsEnvironment, type ApnsPriority, type ApnsResult, isDeviceToken } from "./apns.ts";
import { SharedProviderToken } from "./apnsAuth.ts";
import { Database, type EventWrite, type ParticipantWrite, type SquadSnapshotRow, isUniqueViolation } from "./db.ts";
import type { Env } from "./env.ts";
import { HttpError, apiError, errorResponse, isRecord, json, noContent, readJSON } from "./http.ts";
import {
  type Attributes,
  type Cheer,
  type ContentState,
  END_DISMISSAL_SECONDS,
  MAX_MEMBERS,
  type Member,
  MemberState,
  type Pet,
  assertPayloadBudget,
  buildLiveActivityPayload,
  isPetCode,
  isShortID,
  staleDateFor,
} from "./liveActivity.ts";

/** The member the Worker authenticated. Set by the Worker only. */
export const ROOM_USER_HEADER = "x-lockin-user";
/** The session (room) id, so the room knows its own name before it has any state. */
export const ROOM_SESSION_HEADER = "x-lockin-session";

/** Changes are pushed this long after the first one in a batch (SPEC.md §4.4: 2–3 s). */
export const COALESCE_SECONDS = 2;
/** A cheer shows for this long, then a priority-5 push clears it. */
export const CHEER_SHOWN_SECONDS = 10;
/** One cheer per sender this often (429 cheer_too_soon). */
export const CHEER_INTERVAL_SECONDS = 10;
/** Cheer kinds are indexes into the app's emoji set. */
export const MAX_CHEER_KIND = 7;
/**
 * A Live Activity lasts at most 8 hours (SPEC.md §3). A member whose timer is still running that
 * long after they joined (paused, mostly) has left: their activity is gone from the island anyway,
 * and it stops one abandoned pause from holding a room, and its owner, open for ever.
 */
export const MEMBER_MAX_SECONDS = 8 * 60 * 60;
/** A D1 write that failed is tried again this much later. */
export const D1_RETRY_SECONDS = 30;
/** An ended room keeps its final state this long for GET /sessions/:id, then deletes it. */
export const ENDED_ROOM_KEPT_SECONDS = 24 * 60 * 60;
/** Pet mood counts members who focused in this window (until M5 decides whose "today" it is). */
export const PET_MOOD_WINDOW_SECONDS = 24 * 60 * 60;
/** Pet mood: happy when at least half the squad focused in the window, otherwise low. */
export const PET_MOOD_HAPPY = 3;
export const PET_MOOD_LOW = 1;
/** Placeholder until M5's stage thresholds: progress `x` is XP within a 600-XP stage. */
export const PET_XP_PER_STAGE = 600;

/** The part of a WebSocket the room uses. */
export interface RoomSocket {
  send(message: string): void;
  close(code?: number, reason?: string): void;
}

/** The part of `DurableObjectState` the room uses, so tests can pass a fake. */
export interface RoomState {
  readonly id: { toString(): string };
  readonly storage: {
    get<T>(key: string): Promise<T | undefined>;
    put<T>(key: string, value: T): Promise<void>;
    deleteAll(): Promise<void>;
    getAlarm(): Promise<number | null>;
    setAlarm(scheduledTime: number): Promise<void>;
    deleteAlarm(): Promise<void>;
  };
  acceptWebSocket(socket: RoomSocket, tags?: string[]): void;
  getWebSockets(tag?: string): RoomSocket[];
}

/** Injected by tests; the runtime uses the real fetch, clock and WebSocketPair. */
export interface RoomDependencies {
  fetch?: typeof fetch;
  /** Unix seconds. */
  now?: () => number;
  /** A connected pair: the client end goes back to the caller, the room keeps the server end. */
  webSocketPair?: () => [client: unknown, server: RoomSocket];
  /** The 101 response that hands the client end to the caller. */
  upgradeResponse?: (client: unknown) => Response;
}

/** Who's joining, as the Worker read them from D1. `name` is 1–12 code points, `avatar` an avatar code. */
export interface RoomProfile {
  name: string;
  avatar: string;
}

/** The app's view of a session (docs/milestones/M3.md). */
export interface SessionView {
  id: string;
  squadId: string | null;
  hostId: string | null;
  status: "open" | "ended";
  createdAt: number;
}

/** What joining returns: ready for ActivityKit (docs/milestones/M3.md). */
export interface Joined {
  session: SessionView;
  attributes: Attributes;
  contentState: ContentState;
}

interface RoomMember {
  id: string;
  name: string;
  avatar: string;
  s: MemberState;
  b: number;
  e: number;
  q?: number;
  plannedMin: number;
  /** When they first joined this room: the order after the host. */
  joinedAt: number;
  /** When their current timer stopped: finished, left or slipped. */
  endedAt?: number;
  /** Seconds paused in the current timer, not counting a pause in progress. */
  pausedSec: number;
  /** Focused seconds from earlier timers in this room (joining again after finishing). */
  focusedBefore: number;
  /** Focused seconds in this room, written when a timer stops. */
  focusedSec: number;
  slips: number;
  laToken?: string;
  laEnv?: ApnsEnvironment;
}

interface PetSnapshot {
  species: string | null;
  stage: number;
  xp: number;
  mood: number;
}

interface PendingPush {
  event: "update" | "end";
  priority: ApnsPriority;
  /** Unix seconds. */
  flushAt: number;
}

interface PushCounts {
  /** Push batches sent (one per coalesced change). */
  batches: number;
  /** APNs requests accepted, by priority. */
  p10: number;
  p5: number;
  /** Refused by APNs (any non-200). */
  refused: number;
  /** Never got an answer (network or set-up errors). */
  failed: number;
  /** Tokens dropped because APNs said they're gone (410, BadDeviceToken). */
  cleared: number;
}

interface RoomRecord {
  sid: string;
  squadId: string | null;
  /** The squad's name when someone last joined: the attributes' `sq`. */
  squadName: string | null;
  hostId: string;
  createdAt: number;
  status: "open" | "ended";
  endedAt?: number;
  v: number;
  /** Host first, then in the order they joined. At most MAX_MEMBERS. */
  members: RoomMember[];
  /** Focused seconds and slips of members moved out to make room, should they come back. */
  former: Record<string, { focusedSec: number; slips: number }>;
  pet: PetSnapshot | null;
  cheer?: Cheer;
  cheerClearAt?: number;
  /** When each member last cheered. */
  lastCheer: Record<string, number>;
  pending?: PendingPush;
  pushes: PushCounts;
  /** Members whose D1 row is behind. */
  dirty: string[];
  /** The session's end isn't in D1 yet. */
  endDirty: boolean;
  /** `events` rows not written yet. */
  events: EventWrite[];
  syncRetryAt?: number;
  cleanupAt?: number;
}

interface PreparedPush {
  memberId: string;
  token: string;
  env: ApnsEnvironment;
  payload: unknown;
}

interface Batch {
  event: "update" | "end";
  priority: ApnsPriority;
  pushes: PreparedPush[];
}

type Outcome = { result: ApnsResult } | { error: string };

const STORAGE_KEY = "room";
const RUNNING: readonly MemberState[] = [MemberState.focusing, MemberState.break, MemberState.paused];

function isRunning(member: RoomMember): boolean {
  return RUNNING.includes(member.s);
}

function badState(message: string): HttpError {
  return apiError(409, "bad_state", message);
}

function sessionEnded(): HttpError {
  return apiError(410, "session_ended", "This session has ended");
}

function notMember(): HttpError {
  return apiError(403, "not_member", "You're not in this session");
}

export class Room {
  private readonly state: RoomState;
  private readonly env: Env;
  private readonly deps: RoomDependencies;
  private readonly db: Database;
  private readonly clock: () => number;
  private record: RoomRecord | null | undefined;
  private queue: Promise<unknown> = Promise.resolve();
  private apns: ApnsClient | null | undefined;

  constructor(state: RoomState, env: Env, deps: RoomDependencies = {}) {
    this.state = state;
    this.env = env;
    this.deps = deps;
    this.db = new Database(env.DB);
    this.clock = deps.now ?? (() => Date.now() / 1000);
  }

  /** Whole Unix seconds: the times in the content-state, in D1 and on alarms. */
  private now(): number {
    return Math.floor(this.clock());
  }

  // Requests from the Worker (src/sessions.ts)

  async fetch(request: Request): Promise<Response> {
    const action = new URL(request.url).pathname.slice(1);
    const userId = request.headers.get(ROOM_USER_HEADER) ?? "";
    const sessionId = request.headers.get(ROOM_SESSION_HEADER) ?? "";
    try {
      if (!isShortID(userId) || !isShortID(sessionId)) throw new HttpError(400, "Missing the user or session header");
      const body = request.method === "POST" ? await readJSON(request) : {};
      if (!isRecord(body)) throw new HttpError(400, "Expected a JSON object");
      return await this.exclusive(() => this.route(request, action, userId, sessionId, body));
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error);
      console.error(`room ${isShortID(sessionId) ? sessionId : "?"}: ${action} failed (${error instanceof Error ? error.name : typeof error})`);
      return json({ error: "Something went wrong", code: "internal" }, 500);
    }
  }

  private async route(request: Request, action: string, userId: string, sessionId: string, body: Record<string, unknown>): Promise<Response> {
    const post = request.method === "POST";
    if (post && action === "open") return json(await this.open(sessionId, userId, body));

    const room = await this.load();
    if (room === null) throw apiError(404, "session_not_found", "There's no such session");
    if (!post && action === "state") return json({ session: this.sessionView(room), contentState: this.contentState(room) });
    if (!post && action === "live") return this.live(request, room);
    if (!post) throw new HttpError(404, "Not found");

    switch (action) {
      case "join":
        return json(await this.join(room, userId, body));
      case "la-token":
        await this.laToken(room, userId, body);
        return noContent();
      case "pause":
      case "resume":
      case "end":
      case "slip":
        await this.memberAction(room, userId, action);
        return json({ contentState: this.contentState(room) });
      case "cheer":
        await this.cheer(room, userId, body);
        return noContent();
      case "forget":
        await this.forget(room, userId);
        return noContent();
      default:
        throw new HttpError(404, "Not found");
    }
  }

  /** Opens the room with its host (POST /sessions). */
  private async open(sid: string, userId: string, body: Record<string, unknown>): Promise<Joined> {
    if ((await this.load()) !== null) throw apiError(409, "room_exists", "This session already exists");
    const squadId = body.squadId === null || body.squadId === undefined ? null : body.squadId;
    if (squadId !== null && !isShortID(squadId)) throw new HttpError(400, "squadId must be a squad id or null");
    const minutes = plannedMinutes(body.minutes);
    const profile = roomProfile(body.profile);
    const now = this.now();

    let squad: SquadSnapshotRow | null = null;
    if (squadId !== null) {
      squad = await this.db.squadSnapshot(squadId, now - PET_MOOD_WINDOW_SECONDS);
      if (squad === null) throw apiError(403, "not_member", "You're not in this squad");
    }
    const host = newMember(userId, profile, minutes, now);
    const room: RoomRecord = {
      sid,
      squadId,
      squadName: squad?.name ?? null,
      hostId: userId,
      createdAt: now,
      status: "open",
      v: 1,
      members: [host],
      former: {},
      pet: null,
      lastCheer: {},
      pushes: { batches: 0, p10: 0, p5: 0, refused: 0, failed: 0, cleared: 0 },
      dirty: [],
      endDirty: false,
      events: [],
    };
    try {
      await this.db.insertRoom({ id: sid, squadId, hostId: userId, createdAt: now }, participantRow(room, host), joinEvent(room, host));
    } catch (error) {
      if (isUniqueViolation(error, "participants.user_id")) throw await this.alreadyInSession(userId);
      if (isUniqueViolation(error, "sessions.squad_id") || isUniqueViolation(error, "sessions.id")) {
        throw apiError(409, "room_exists", "The squad already has a session open");
      }
      throw error;
    }
    // After the host's row is written, so they count towards today's mood.
    if (squadId !== null) await this.refreshSquad(room, now);
    this.record = room;
    await this.commit(room, now, false);
    console.log(`room ${sid}: opened (${squadId === null ? "solo" : "squad"})`);
    return this.joined(room, userId);
  }

  /** Joins, or joins again after finishing (POST /sessions/:id/join, or POST /sessions with a squad). */
  private async join(room: RoomRecord, userId: string, body: Record<string, unknown>): Promise<Joined> {
    if (room.status === "ended") throw sessionEnded();
    const minutes = plannedMinutes(body.minutes);
    const profile = roomProfile(body.profile);
    const now = this.now();

    const existing = room.members.find((member) => member.id === userId);
    // Already running here: the same answer again, so a retry is harmless.
    if (existing !== undefined && isRunning(existing)) return this.joined(room, userId);

    let evicted: RoomMember | undefined;
    if (existing === undefined && room.members.length >= MAX_MEMBERS) {
      // Make room by moving out whoever left first; if nobody has, the room is full.
      evicted = room.members.find((member) => member.s === MemberState.left);
      if (evicted === undefined) throw apiError(409, "room_full", `A session holds ${MAX_MEMBERS} people`);
    }

    const member = newMember(userId, profile, minutes, now);
    if (existing !== undefined) {
      member.joinedAt = existing.joinedAt;
      member.focusedBefore = existing.focusedSec;
      member.focusedSec = existing.focusedSec;
      member.slips = existing.slips;
    } else if (room.former[userId] !== undefined) {
      const former = room.former[userId];
      member.focusedBefore = former.focusedSec;
      member.focusedSec = former.focusedSec;
      member.slips = former.slips;
    }
    try {
      await this.db.upsertParticipant(participantRow(room, member), joinEvent(room, member));
    } catch (error) {
      if (isUniqueViolation(error, "participants.user_id")) throw await this.alreadyInSession(userId);
      throw error;
    }

    if (evicted !== undefined) {
      room.former[evicted.id] = { focusedSec: evicted.focusedSec, slips: evicted.slips };
      room.members = room.members.filter((other) => other !== evicted);
      room.dirty = room.dirty.filter((id) => id !== evicted.id);
    }
    if (existing !== undefined) room.members[room.members.indexOf(existing)] = member;
    else room.members.push(member);
    delete room.former[userId];
    room.dirty = room.dirty.filter((id) => id !== userId);

    await this.refreshSquad(room, now);
    this.change(room, 10, now);
    await this.commit(room, now, true);
    return this.joined(room, userId);
  }

  /** Stores the member's Live Activity push token and its APNs environment. No push: they have the state. */
  private async laToken(room: RoomRecord, userId: string, body: Record<string, unknown>): Promise<void> {
    if (room.status === "ended") throw sessionEnded();
    const member = room.members.find((each) => each.id === userId);
    if (member === undefined) throw notMember();
    if (!isDeviceToken(body.token) || (body.env !== "sandbox" && body.env !== "production")) {
      throw apiError(422, "token_invalid", 'Expected { token: "<hex>", env: "sandbox" | "production" }');
    }
    const token = body.token.toLowerCase();
    if (member.laToken === token && member.laEnv === body.env) return;
    member.laToken = token;
    member.laEnv = body.env;
    markDirty(room, member);
    await this.commit(room, this.now(), false);
  }

  private async memberAction(room: RoomRecord, userId: string, action: "pause" | "resume" | "end" | "slip"): Promise<void> {
    if (room.status === "ended") throw sessionEnded();
    const member = room.members.find((each) => each.id === userId);
    if (member === undefined) throw notMember();
    const now = this.now();

    switch (action) {
      case "pause":
        if (member.s !== MemberState.focusing) throw badState("Only a running timer can be paused");
        if (now >= member.e) {
          // The time already ran out: that's a finish, not a pause (as SessionEngine has it).
          this.stopMember(room, member, MemberState.done, member.e);
        } else {
          member.s = MemberState.paused;
          member.q = now;
          room.events.push({ sessionId: room.sid, userId, type: "pause", at: now });
          markDirty(room, member);
          this.change(room, 5, now);
        }
        break;
      case "resume": {
        if (member.s !== MemberState.paused || member.q === undefined) throw badState("Only a paused timer can be resumed");
        const paused = Math.max(0, now - member.q);
        member.e += paused;
        member.pausedSec += paused;
        delete member.q;
        member.s = MemberState.focusing;
        room.events.push({ sessionId: room.sid, userId, type: "resume", at: now, meta: { sec: paused } });
        markDirty(room, member);
        this.change(room, 5, now);
        break;
      }
      case "end":
        if (!isRunning(member)) throw badState("This timer has already stopped");
        // A running timer whose time is up finished; anything else is leaving early.
        if (member.s !== MemberState.paused && now >= member.e) this.stopMember(room, member, MemberState.done, member.e);
        else this.stopMember(room, member, MemberState.left, now);
        break;
      case "slip":
        if (!isRunning(member)) throw badState("This timer has already stopped");
        member.slips += 1;
        this.stopMember(room, member, MemberState.slipped, now);
        break;
    }
    this.endIfIdle(room, now);
    await this.commit(room, now, true);
  }

  private async cheer(room: RoomRecord, userId: string, body: Record<string, unknown>): Promise<void> {
    if (room.status === "ended") throw sessionEnded();
    if (!room.members.some((member) => member.id === userId)) throw notMember();
    const { to, kind } = body;
    if (!isShortID(to) || to === userId || !room.members.some((member) => member.id === to)) {
      throw apiError(422, "cheer_invalid", "Cheer someone else in this session");
    }
    if (typeof kind !== "number" || !Number.isInteger(kind) || kind < 0 || kind > MAX_CHEER_KIND) {
      throw apiError(422, "cheer_invalid", `kind must be a whole number from 0 to ${MAX_CHEER_KIND}`);
    }
    const now = this.now();
    const last = room.lastCheer[userId];
    if (last !== undefined && now - last < CHEER_INTERVAL_SECONDS) {
      throw apiError(429, "cheer_too_soon", "One cheer every 10 seconds", { retryAfter: CHEER_INTERVAL_SECONDS - (now - last) });
    }
    room.lastCheer[userId] = now;
    room.cheer = { f: userId, t: to, k: kind, at: now };
    room.cheerClearAt = now + CHEER_SHOWN_SECONDS;
    room.events.push({ sessionId: room.sid, userId, type: "cheer", at: now, meta: { k: kind } });
    this.change(room, 5, now);
    await this.commit(room, now, true);
  }

  /** Takes a member out of the room entirely: their account is being deleted (DELETE /me). */
  private async forget(room: RoomRecord, userId: string): Promise<void> {
    const member = room.members.find((each) => each.id === userId);
    delete room.former[userId];
    delete room.lastCheer[userId];
    room.events = room.events.filter((event) => event.userId !== userId);
    if (member === undefined) return;
    const now = this.now();
    room.members = room.members.filter((each) => each !== member);
    room.dirty = room.dirty.filter((id) => id !== userId);
    if (room.cheer !== undefined && (room.cheer.f === userId || room.cheer.t === userId)) {
      delete room.cheer;
      delete room.cheerClearAt;
    }
    if (room.status === "open") {
      this.change(room, 10, now);
      this.endIfIdle(room, now);
    }
    await this.commit(room, now, true);
  }

  /** The live view (GET /sessions/:id/live): the state now, then after every change. */
  private live(request: Request, room: RoomRecord): Response {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      throw apiError(426, "upgrade_required", "Connect with a WebSocket");
    }
    const [client, server] = (this.deps.webSocketPair ?? defaultWebSocketPair)();
    this.state.acceptWebSocket(server);
    server.send(this.stateMessage(room));
    if (room.status === "ended") server.close(1000, "Session ended");
    return (this.deps.upgradeResponse ?? defaultUpgradeResponse)(client);
  }

  // The WebSocket hibernation API's handlers

  async webSocketMessage(socket: RoomSocket, message: string | ArrayBuffer): Promise<void> {
    // The app may ping to keep the connection warm; nothing else comes this way.
    if (typeof message !== "string") return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(message);
    } catch {
      return;
    }
    if (isRecord(parsed) && parsed.type === "ping") {
      try {
        socket.send(JSON.stringify({ type: "pong" }));
      } catch {
        // Already closed.
      }
    }
  }

  async webSocketClose(socket: RoomSocket, code: number, reason: string): Promise<void> {
    try {
      socket.close(code, reason);
    } catch {
      // The runtime already completed the close.
    }
  }

  async webSocketError(): Promise<void> {
    // Nothing to do: the socket is gone and the next broadcast skips it.
  }

  // The alarm: timers, the push batch, cheers, D1 retries and clean-up

  async alarm(): Promise<void> {
    const batch = await this.exclusive(async () => {
      const room = await this.load();
      if (room === null) return undefined;
      const now = this.now();
      if (room.cleanupAt !== undefined && now >= room.cleanupAt && room.pending === undefined) {
        for (const socket of this.state.getWebSockets()) closeQuietly(socket, 1000, "Session ended");
        await this.state.storage.deleteAll();
        await this.state.storage.deleteAlarm();
        this.record = null;
        return undefined;
      }
      const changed = this.tick(room, now);
      let taken: Batch | undefined;
      if (room.pending !== undefined && now >= room.pending.flushAt) taken = this.takeBatch(room, now);
      await this.commit(room, now, changed);
      return taken;
    });
    if (batch === undefined) return;

    // The APNs requests go out without holding the room, so members' requests aren't kept waiting.
    const outcomes = await this.send(batch);
    await this.exclusive(async () => {
      const room = await this.load();
      if (room === null) return;
      const now = this.now();
      this.applyOutcomes(room, batch, outcomes, now);
      await this.commit(room, now, false);
    });
  }

  /** Marks timers that ran out as done, enforces the 8-hour cap, clears an old cheer. Whether anything changed. */
  private tick(room: RoomRecord, now: number): boolean {
    if (room.status === "ended") return false;
    const before = room.v;
    for (const member of room.members) {
      if ((member.s === MemberState.focusing || member.s === MemberState.break) && member.e <= now) {
        this.stopMember(room, member, MemberState.done, member.e);
      } else if (isRunning(member) && now >= member.b + MEMBER_MAX_SECONDS) {
        this.stopMember(room, member, MemberState.left, now, { cap: true });
      }
    }
    if (room.cheer !== undefined && room.cheerClearAt !== undefined && now >= room.cheerClearAt) {
      delete room.cheer;
      delete room.cheerClearAt;
      this.change(room, 5, now);
    }
    this.endIfIdle(room, now);
    return room.v !== before;
  }

  /** Stops a member's timer: done, left early or slipped. Always a priority-10 change. */
  private stopMember(room: RoomRecord, member: RoomMember, state: MemberState, at: number, meta: Record<string, boolean> = {}): void {
    let focused: number;
    if (member.s === MemberState.paused && member.q !== undefined) {
      focused = member.q - member.b - member.pausedSec;
      member.pausedSec += Math.max(0, at - member.q);
    } else {
      focused = Math.min(at, member.e) - member.b - member.pausedSec;
    }
    const round = Math.max(0, Math.round(focused));
    member.focusedSec = member.focusedBefore + round;
    member.s = state;
    delete member.q;
    member.endedAt = at;
    const type = state === MemberState.done ? "done" : state === MemberState.slipped ? "slip" : "leave";
    room.events.push({ sessionId: room.sid, userId: member.id, type, at, meta: { sec: round, ...meta } });
    markDirty(room, member);
    this.change(room, 10, this.now());
  }

  /** Nobody's timer is running: the room ends, and its final state goes out as an `end` push now. */
  private endIfIdle(room: RoomRecord, now: number): void {
    if (room.status !== "open" || room.members.some(isRunning)) return;
    room.status = "ended";
    room.endedAt = now;
    room.endDirty = true;
    if (room.cheer !== undefined) {
      delete room.cheer;
      delete room.cheerClearAt;
      room.v += 1;
    }
    // Replaces any update still waiting: only the latest state goes out.
    room.pending = { event: "end", priority: 10, flushAt: now };
  }

  /** A change to the state: a new version, and a push within COALESCE_SECONDS at the highest priority asked for. */
  private change(room: RoomRecord, priority: ApnsPriority, now: number): void {
    room.v += 1;
    if (room.status !== "open") return;
    if (room.pending === undefined) room.pending = { event: "update", priority, flushAt: now + COALESCE_SECONDS };
    else if (priority > room.pending.priority) room.pending.priority = priority;
  }

  /** The pending push, ready to send: one request per member with a token. */
  private takeBatch(room: RoomRecord, now: number): Batch {
    const pending = room.pending as PendingPush;
    delete room.pending;
    room.pushes.batches += 1;
    const state = this.contentState(room);
    const pushes: PreparedPush[] = [];
    for (const member of room.members) {
      if (member.laToken === undefined || member.laEnv === undefined) continue;
      // Someone who left ended their activity themselves; the final `end` still goes to them, in
      // case it's still showing.
      if (pending.event === "update" && member.s === MemberState.left) continue;
      try {
        assertPayloadBudget(this.attributes(room, member.id), state);
        const payload = buildLiveActivityPayload({
          event: pending.event,
          state,
          timestamp: now,
          ...(pending.event === "update" ? { staleDate: staleDateFor(state, now) } : { dismissalDate: now + END_DISMISSAL_SECONDS }),
        });
        pushes.push({ memberId: member.id, token: member.laToken, env: member.laEnv, payload });
      } catch (error) {
        // The validators bound every field, so this means a bug: say so without quoting the state.
        console.error(`room ${room.sid}: payload refused (${error instanceof Error ? error.name : typeof error})`);
      }
    }
    return { event: pending.event, priority: pending.priority, pushes };
  }

  private async send(batch: Batch): Promise<Outcome[]> {
    if (batch.pushes.length === 0) return [];
    const client = this.apnsClient();
    if (client === null) return batch.pushes.map(() => ({ error: "APNs isn't set up (APNS_BUNDLE_ID)" }));
    return Promise.all(
      batch.pushes.map(async (push): Promise<Outcome> => {
        try {
          return {
            result: await client.sendLiveActivity({ deviceToken: push.token, environment: push.env, priority: batch.priority, payload: push.payload }),
          };
        } catch (error) {
          return { error: error instanceof Error ? error.name : typeof error };
        }
      }),
    );
  }

  /** Counts what APNs said, drops tokens it says are gone, and closes the books once the `end` is out. */
  private applyOutcomes(room: RoomRecord, batch: Batch, outcomes: Outcome[], now: number): void {
    const refusals = new Map<string, number>();
    const errors = new Set<string>();
    batch.pushes.forEach((push, index) => {
      const outcome = outcomes[index];
      if (outcome === undefined) return;
      if ("error" in outcome) {
        room.pushes.failed += 1;
        errors.add(outcome.error);
        return;
      }
      const { result } = outcome;
      if (result.ok) {
        if (batch.priority === 10) room.pushes.p10 += 1;
        else room.pushes.p5 += 1;
        return;
      }
      room.pushes.refused += 1;
      const label = `${result.status}${result.reason === undefined ? "" : ` ${result.reason}`}`;
      refusals.set(label, (refusals.get(label) ?? 0) + 1);
      if (result.status === 410 || result.reason === "BadDeviceToken") {
        const member = room.members.find((each) => each.id === push.memberId);
        // Only if it's still the token that failed: the app may have sent a new one meanwhile.
        if (member !== undefined && member.laToken === push.token) {
          delete member.laToken;
          delete member.laEnv;
          markDirty(room, member);
          room.pushes.cleared += 1;
        }
      }
    });
    for (const [label, count] of refusals) console.warn(`room ${room.sid}: APNs refused ${count} push${count === 1 ? "" : "es"} (${label})`);
    for (const error of errors) console.error(`room ${room.sid}: push failed (${error})`);

    if (batch.event !== "end") return;
    // The room is closed: no more pushes, so its tokens go, and its push counts are logged.
    for (const member of room.members) {
      if (member.laToken === undefined) continue;
      delete member.laToken;
      delete member.laEnv;
      markDirty(room, member);
    }
    const { batches, p10, p5, refused, failed, cleared } = room.pushes;
    const minutes = Math.round(((room.endedAt ?? now) - room.createdAt) / 60);
    console.log(
      `room ${room.sid}: ended after ${minutes} min with ${room.members.length} member${room.members.length === 1 ? "" : "s"}; ` +
        `${p10 + p5} pushes accepted (${p10} at priority 10, ${p5} at 5) in ${batches} batches, ${refused} refused, ${failed} failed, ${cleared} tokens cleared`,
    );
    room.events.push({ sessionId: room.sid, userId: null, type: "room_end", at: now, meta: { members: room.members.length, batches, p10, p5, refused, failed, cleared } });
    room.cleanupAt = now + ENDED_ROOM_KEPT_SECONDS;
  }

  // State, storage and D1

  private async load(): Promise<RoomRecord | null> {
    if (this.record === undefined) this.record = (await this.state.storage.get<RoomRecord>(STORAGE_KEY)) ?? null;
    return this.record;
  }

  /** Writes D1 if it's behind, saves the room, sets the next alarm, and tells the live views if `changed`. */
  private async commit(room: RoomRecord, now: number, changed: boolean): Promise<void> {
    await this.syncD1(room, now);
    await this.state.storage.put(STORAGE_KEY, room);
    await this.scheduleAlarm(room);
    if (changed) this.broadcast(room);
  }

  private async syncD1(room: RoomRecord, now: number): Promise<void> {
    if (room.dirty.length === 0 && !room.endDirty && room.events.length === 0) return;
    if (room.syncRetryAt !== undefined && now < room.syncRetryAt && !room.endDirty) return;
    const participants = room.dirty
      .map((id) => room.members.find((member) => member.id === id))
      .filter((member) => member !== undefined)
      .map((member) => participantRow(room, member));
    try {
      await this.db.syncRoom({
        participants,
        ...(room.endDirty ? { ended: { sessionId: room.sid, endedAt: room.endedAt ?? now } } : {}),
        events: room.events,
      });
      room.dirty = [];
      room.endDirty = false;
      room.events = [];
      delete room.syncRetryAt;
    } catch (error) {
      console.error(`room ${room.sid}: D1 write failed (${error instanceof Error ? error.name : typeof error}), trying again in ${D1_RETRY_SECONDS} s`);
      room.syncRetryAt = now + D1_RETRY_SECONDS;
    }
  }

  /** The soonest of every timed job, as the one alarm. */
  private async scheduleAlarm(room: RoomRecord): Promise<void> {
    const times: number[] = [];
    if (room.pending !== undefined) times.push(room.pending.flushAt);
    if (room.syncRetryAt !== undefined) times.push(room.syncRetryAt);
    if (room.status === "open") {
      for (const member of room.members) {
        if (member.s === MemberState.focusing || member.s === MemberState.break) times.push(member.e);
        if (isRunning(member)) times.push(member.b + MEMBER_MAX_SECONDS);
      }
      if (room.cheer !== undefined && room.cheerClearAt !== undefined) times.push(room.cheerClearAt);
    } else if (room.cleanupAt !== undefined) {
      times.push(room.cleanupAt);
    }
    const storage = this.state.storage;
    if (times.length === 0) {
      if ((await storage.getAlarm()) !== null) await storage.deleteAlarm();
      return;
    }
    const at = Math.ceil(Math.min(...times) * 1000);
    if ((await storage.getAlarm()) !== at) await storage.setAlarm(at);
  }

  private broadcast(room: RoomRecord): void {
    const message = this.stateMessage(room);
    for (const socket of this.state.getWebSockets()) {
      try {
        socket.send(message);
        if (room.status === "ended") socket.close(1000, "Session ended");
      } catch {
        // Closed while we weren't looking; the runtime drops it.
      }
    }
  }

  private stateMessage(room: RoomRecord): string {
    return JSON.stringify({ type: "state", status: room.status, contentState: this.contentState(room) });
  }

  /** The squad's name, pet and mood from D1, after a join. Unchanged if the squad is gone. */
  private async refreshSquad(room: RoomRecord, now: number): Promise<void> {
    if (room.squadId === null) return;
    const squad = await this.db.squadSnapshot(room.squadId, now - PET_MOOD_WINDOW_SECONDS);
    if (squad === null) return;
    room.squadName = squad.name;
    const happy = squad.size > 0 && squad.focused * 2 >= squad.size;
    room.pet = { species: squad.pet_species, stage: squad.pet_stage, xp: squad.pet_xp, mood: happy ? PET_MOOD_HAPPY : PET_MOOD_LOW };
  }

  private async alreadyInSession(userId: string): Promise<HttpError> {
    const sessionId = await this.db.openParticipation(userId);
    return apiError(409, "already_in_session", "You're already in a session. End it first.", sessionId === null ? {} : { sessionId });
  }

  private apnsClient(): ApnsClient | null {
    if (this.apns !== undefined) return this.apns;
    const bundleId = this.env.APNS_BUNDLE_ID?.trim() ?? "";
    this.apns =
      bundleId.length === 0 || this.env.APNS_AUTH === undefined
        ? null
        : new ApnsClient({ bundleId, tokens: new SharedProviderToken(this.env.APNS_AUTH, this.clock) }, { fetch: this.deps.fetch, now: this.clock });
    return this.apns;
  }

  // The views

  /** The content-state every member's Live Activity shows (SPEC.md §4.3). */
  private contentState(room: RoomRecord): ContentState {
    const m = room.members.slice(0, MAX_MEMBERS).map((member): Member => {
      const view: Member = { i: member.id, n: member.name, a: member.avatar, s: member.s, b: member.b, e: member.e };
      if (member.s === MemberState.paused && member.q !== undefined) view.q = member.q;
      return view;
    });
    const state: ContentState = { v: room.v, m };
    const pet = petView(room.pet);
    if (pet !== undefined) state.p = pet;
    if (room.cheer !== undefined) state.c = { ...room.cheer };
    return state;
  }

  private attributes(room: RoomRecord, me: string): Attributes {
    const attributes: Attributes = { sid: room.sid, me };
    if (room.squadName !== null) attributes.sq = room.squadName;
    return attributes;
  }

  private sessionView(room: RoomRecord): SessionView {
    return { id: room.sid, squadId: room.squadId, hostId: room.hostId, status: room.status, createdAt: room.createdAt };
  }

  private joined(room: RoomRecord, userId: string): Joined {
    const attributes = this.attributes(room, userId);
    const contentState = this.contentState(room);
    assertPayloadBudget(attributes, contentState);
    return { session: this.sessionView(room), attributes, contentState };
  }

  /** Runs `work` after everything queued before it: one change to the room at a time. */
  private exclusive<T>(work: () => Promise<T>): Promise<T> {
    const run = this.queue.then(work, work);
    this.queue = run.catch(() => undefined);
    return run;
  }
}

function newMember(id: string, profile: RoomProfile, minutes: number, now: number): RoomMember {
  return {
    id,
    name: profile.name,
    avatar: profile.avatar,
    s: MemberState.focusing,
    b: now,
    e: now + minutes * 60,
    plannedMin: minutes,
    joinedAt: now,
    pausedSec: 0,
    focusedBefore: 0,
    focusedSec: 0,
    slips: 0,
  };
}

function markDirty(room: RoomRecord, member: RoomMember): void {
  if (!room.dirty.includes(member.id)) room.dirty.push(member.id);
}

function participantRow(room: RoomRecord, member: RoomMember): ParticipantWrite {
  return {
    sessionId: room.sid,
    userId: member.id,
    state: member.s,
    plannedMin: member.plannedMin,
    startedAt: member.b,
    endsAt: member.e,
    pausedAt: member.q ?? null,
    endedAt: member.endedAt ?? null,
    focusedSec: member.focusedSec,
    laToken: member.laToken ?? null,
    laEnv: member.laToken === undefined ? null : (member.laEnv ?? null),
    slips: member.slips,
  };
}

function joinEvent(room: RoomRecord, member: RoomMember): EventWrite {
  return { sessionId: room.sid, userId: member.id, type: "join", at: member.b, meta: { min: member.plannedMin } };
}

function petView(pet: PetSnapshot | null): Pet | undefined {
  if (pet === null || pet.species === null) return undefined;
  const k = `${pet.species}.${pet.stage}`;
  if (!isPetCode(k)) return undefined;
  const x = Math.round(((pet.xp % PET_XP_PER_STAGE) / PET_XP_PER_STAGE) * 100) / 100;
  return { k, md: pet.mood, x };
}

/** Whole minutes, 1–240: sessions are capped at 4 hours (SPEC.md §1.4). The Worker checks first. */
export function plannedMinutes(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > 240) {
    throw apiError(422, "minutes_invalid", "minutes must be a whole number from 1 to 240");
  }
  return value;
}

function roomProfile(value: unknown): RoomProfile {
  if (!isRecord(value) || typeof value.name !== "string" || typeof value.avatar !== "string") {
    throw new HttpError(400, "Expected profile: { name, avatar }");
  }
  return { name: value.name, avatar: value.avatar };
}

function closeQuietly(socket: RoomSocket, code: number, reason: string): void {
  try {
    socket.close(code, reason);
  } catch {
    // Already closed.
  }
}

function defaultWebSocketPair(): [unknown, RoomSocket] {
  const pair = new WebSocketPair();
  return [pair[0], pair[1]];
}

function defaultUpgradeResponse(client: unknown): Response {
  return new Response(null, { status: 101, webSocket: client as WebSocket });
}
