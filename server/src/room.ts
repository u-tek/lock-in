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
// - credits what each timer earned when it stops (M5): coins to the member, XP to the squad's pet,
//   a sad spell for an early leave, the egg hatching once two members finished, and the streak days
//   the finish makes count, all in the same D1 transaction as the room's own rows and each exactly
//   once (`Database.syncRoom`); then it reads the pet back and refreshes `p`, and tells the open
//   rooms of the member's other squads to do the same (their mood and streak can change);
// - shows a slip for 5 minutes (decision 0009): the member is state 5 while their timer keeps
//   running, the pet has a sad spell, and the alarm puts them back to focusing (or done, if their
//   time ran out meanwhile). Nothing is credited until the timer really stops;
// - looks at the pet again when its mood changes by itself: a sad spell ending, the squad's midnight;
// - in a Review Squad's room, runs Demo Buddy (src/demoBuddy.ts): it joins a few seconds after a
//   person opens or joins the room, with a 3-minute timer, cheers them at +60 s, pauses at +90 s,
//   resumes at +120 s and finishes when its time runs out, through the same changes and pushes as a
//   person; it leaves when nobody else is running any more. It has no `participants` row, no push
//   token and no events, and earns no coins (its minutes do feed the squad's pet);
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
// cheer to clear, slip to lift, Demo Buddy's next move, D1 retry or clean-up, whichever is soonest. State lives in storage under "room",
// so the object can be evicted (and its WebSockets hibernate) at any time.
//
// Logs carry the room id and counts only: never tokens, names or user ids.
//
// A plain class rather than `extends DurableObject` from "cloudflare:workers", so the tests can
// load it in Node. It uses DurableObjectState through the small `RoomState` interface below, which
// tests fake.

import { ApnsClient, type ApnsEnvironment, type ApnsPriority, type ApnsResult, isDeviceToken, isGoneToken } from "./apns.ts";
import { SharedProviderToken } from "./apnsAuth.ts";
import { type CreditWrite, Database, type EventWrite, type ParticipantWrite, type StreakDayWrite, isUniqueViolation } from "./db.ts";
import {
  DEMO_BUDDY_CHEER_AFTER_SECONDS,
  DEMO_BUDDY_CHEER_KIND,
  DEMO_BUDDY_ID,
  DEMO_BUDDY_JOIN_DELAY_SECONDS,
  DEMO_BUDDY_MINUTES,
  DEMO_BUDDY_PAUSE_AFTER_SECONDS,
  DEMO_BUDDY_PROFILE,
  DEMO_BUDDY_RESUME_AFTER_SECONDS,
  demoBuddyEnabled,
  isDemoBuddy,
} from "./demoBuddy.ts";
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
  assertPayloadBudget,
  buildLiveActivityPayload,
  canonicalContentState,
  isPetCode,
  isShortID,
  staleDateFor,
} from "./liveActivity.ts";
import { PET_RULES, sessionCoins, wholeMinutes } from "./pet.ts";
import { type SquadProgress, squadProgress, streakDay } from "./progress.ts";

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
/** A slip shows for this long while the timer keeps running (decision 0009); another slip starts it again. */
export const SLIP_SHOW_SECONDS = 5 * 60;
/** A D1 write that failed is tried again this much later. */
export const D1_RETRY_SECONDS = 30;
/** An ended room keeps its final state this long for GET /sessions/:id, then deletes it. */
export const ENDED_ROOM_KEPT_SECONDS = 24 * 60 * 60;
/** The pet's progress `x` is rounded to this many decimal places: plenty for a bar, and short. */
export const PET_PROGRESS_DECIMALS = 2;

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
  /** `length` random bytes: a species for a squad from before M5 that has none yet. */
  random?: (length: number) => Uint8Array;
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
  /** While slipped (state 5): when they go back to focusing. */
  slipUntil?: number;
  /** Demo Buddy: no participants row, no token, no events, no coins. */
  bot?: true;
}

/** Demo Buddy's next move in a Review Squad's room. */
interface BuddyPlan {
  step: "join" | "cheer" | "pause" | "resume";
  /** Unix seconds. */
  at: number;
  /** When its current timer started: the script is timed from it. */
  startedAt?: number;
  /** Whose lock-in brought it: the one it cheers, if they're still here. */
  forId: string | null;
}

/** The squad's pet as the room last read it (M5). */
interface PetSnapshot {
  /** The content-state's `p`: `<species>.<stage>` (an egg is stage 0), mood and progress. */
  k: string;
  md: number;
  x: number;
  hatched: boolean;
  /** When to look again: when a sad spell ends or the squad's day does, the mood changes by itself. */
  checkAt: number;
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
  /** The squad's pet; null for a solo room (or a squad room that couldn't read it yet). */
  pet: PetSnapshot | null;
  /** What stopped timers earned, not in D1 yet (M5). */
  credits: CreditWrite[];
  /** Members who finished a timer here: two of them hatch the squad's egg (M5). */
  finishers: string[];
  /** The egg hatched here at this time, and D1 hasn't heard yet. */
  hatchAt?: number;
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
  /** The room's squad is a Review Squad: Demo Buddy joins its sessions. */
  review?: boolean;
  /** Demo Buddy's next move, while it has one. */
  buddy?: BuddyPlan;
  /** A slip's sad spell for the squad's pet (Unix seconds), not in D1 yet. */
  sadAt?: number;
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

/** What a D1 write took with it (M5): the credits, whether the egg hatched, and a slip's sad spell. */
interface Synced {
  credits: CreditWrite[];
  hatched: boolean;
  sad: boolean;
}

const STORAGE_KEY = "room";
/** A slipped member's timer is running too (decision 0009). */
const RUNNING: readonly MemberState[] = [MemberState.focusing, MemberState.break, MemberState.paused, MemberState.slipped];
/** Running and not paused: the clock is going. */
const TICKING: readonly MemberState[] = [MemberState.focusing, MemberState.break, MemberState.slipped];

function isRunning(member: RoomMember): boolean {
  return RUNNING.includes(member.s);
}

function isTicking(member: RoomMember): boolean {
  return TICKING.includes(member.s);
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
  /** Other squads' open rooms to tell to look at their pet again, once this one is free: session id -> the member who finished. */
  private readonly pokes = new Map<string, string>();

  constructor(state: RoomState, env: Env, deps: RoomDependencies = {}) {
    this.state = state;
    this.env = env;
    this.deps = deps;
    this.db = new Database(env.DB);
    this.clock = deps.now ?? (() => Date.now() / 1000);
  }

  private random(length: number): Uint8Array {
    return (this.deps.random ?? ((count: number) => crypto.getRandomValues(new Uint8Array(count))))(length);
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
      const response = await this.exclusive(() => this.route(request, action, userId, sessionId, body));
      await this.sendPokes();
      return response;
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
      case "pet":
        await this.petChanged(room);
        return noContent();
      case "buddy":
        if (!isDemoBuddy(userId)) throw new HttpError(404, "Not found");
        await this.buddyNow(room);
        return json({ session: this.sessionView(room) });
      default:
        throw new HttpError(404, "Not found");
    }
  }

  /**
   * Opens the room with its host (POST /sessions). Demo Buddy opens one too, in a Review Squad
   * (POST /squads/:id/demo-buddy/lock-in), with no participants row and its script from the start.
   */
  private async open(sid: string, userId: string, body: Record<string, unknown>): Promise<Joined> {
    if ((await this.load()) !== null) throw apiError(409, "room_exists", "This session already exists");
    const squadId = body.squadId === null || body.squadId === undefined ? null : body.squadId;
    if (squadId !== null && !isShortID(squadId)) throw new HttpError(400, "squadId must be a squad id or null");
    const minutes = plannedMinutes(body.minutes);
    const profile = roomProfile(body.profile);
    const now = this.now();
    const bot = isDemoBuddy(userId);

    let squadName: string | null = null;
    let review = false;
    if (squadId !== null) {
      const squad = await this.db.squadById(squadId);
      if (squad === null) throw apiError(403, "not_member", "You're not in this squad");
      squadName = squad.name;
      review = squad.review === 1;
    }
    // Demo Buddy lives in Review Squads only.
    if (bot && !review) throw apiError(403, "not_member", "Demo Buddy isn't in this squad");
    const host = newMember(userId, profile, minutes, now);
    if (bot) host.bot = true;
    const room: RoomRecord = {
      sid,
      squadId,
      squadName,
      hostId: userId,
      createdAt: now,
      status: "open",
      v: 1,
      members: [host],
      former: {},
      pet: null,
      credits: [],
      finishers: [],
      lastCheer: {},
      pushes: { batches: 0, p10: 0, p5: 0, refused: 0, failed: 0, cleared: 0 },
      dirty: [],
      endDirty: false,
      events: [],
      review,
    };
    try {
      await this.db.insertRoom(
        { id: sid, squadId, hostId: userId, createdAt: now },
        bot ? null : participantRow(room, host),
        bot ? null : joinEvent(room, host),
      );
    } catch (error) {
      if (isUniqueViolation(error, "participants.user_id")) throw await this.alreadyInSession(userId);
      if (isUniqueViolation(error, "sessions.squad_id") || isUniqueViolation(error, "sessions.id")) {
        throw apiError(409, "room_exists", "The squad already has a session open");
      }
      throw error;
    }
    // The egg shows from the start (M5): `p` is in every squad room's state.
    if (squadId !== null) await this.refreshPet(room, now);
    if (bot) room.buddy = { step: "cheer", at: now + DEMO_BUDDY_CHEER_AFTER_SECONDS, startedAt: now, forId: null };
    else this.inviteBuddy(room, userId, now);
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

    const seat = this.seatFor(room, userId);
    if (seat === null) throw apiError(409, "room_full", `A session holds ${MAX_MEMBERS} people`);
    const member = this.timerFor(room, userId, profile, minutes, now);
    try {
      await this.db.upsertParticipant(participantRow(room, member), joinEvent(room, member));
    } catch (error) {
      if (isUniqueViolation(error, "participants.user_id")) throw await this.alreadyInSession(userId);
      throw error;
    }
    this.seat(room, member, seat);

    await this.refreshPet(room, now);
    this.change(room, 10, now);
    this.inviteBuddy(room, userId, now);
    await this.commit(room, now, true);
    return this.joined(room, userId);
  }

  /**
   * Where a new timer for `userId` goes: in place of their last one, at the end, or in place of
   * whoever left first when the room is full. Null when it's full and nobody has left.
   */
  private seatFor(room: RoomRecord, userId: string): { existing?: RoomMember; evicted?: RoomMember } | null {
    const existing = room.members.find((member) => member.id === userId);
    if (existing !== undefined) return { existing };
    if (room.members.length < MAX_MEMBERS) return {};
    // Make room by moving out whoever left first; if nobody has, the room is full.
    const evicted = room.members.find((member) => member.s === MemberState.left && member.bot !== true);
    return evicted === undefined ? null : { evicted };
  }

  /** A new timer for `userId`, carrying what their earlier timers in this room focused and slipped. */
  private timerFor(room: RoomRecord, userId: string, profile: RoomProfile, minutes: number, now: number): RoomMember {
    const member = newMember(userId, profile, minutes, now);
    const existing = room.members.find((each) => each.id === userId);
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
    return member;
  }

  /** Puts the new timer in its seat (`seatFor`). */
  private seat(room: RoomRecord, member: RoomMember, seat: { existing?: RoomMember; evicted?: RoomMember }): void {
    const { existing, evicted } = seat;
    if (evicted !== undefined) {
      room.former[evicted.id] = { focusedSec: evicted.focusedSec, slips: evicted.slips };
      room.members = room.members.filter((other) => other !== evicted);
      room.dirty = room.dirty.filter((id) => id !== evicted.id);
    }
    if (existing !== undefined) room.members[room.members.indexOf(existing)] = member;
    else room.members.push(member);
    delete room.former[member.id];
    room.dirty = room.dirty.filter((id) => id !== member.id);
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
        // A slipped timer is running like a focusing one (decision 0009).
        if (member.s !== MemberState.focusing && member.s !== MemberState.slipped) throw badState("Only a running timer can be paused");
        if (now >= member.e) {
          // The time already ran out: that's a finish, not a pause (as SessionEngine has it).
          this.stopMember(room, member, MemberState.done, member.e);
        } else {
          member.s = MemberState.paused;
          member.q = now;
          delete member.slipUntil;
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
        // Gentle (decision 0009): shown for SLIP_SHOW_SECONDS while the timer keeps running; a slip
        // while slipped starts that again. Only a running, unpaused timer can slip.
        if (member.s !== MemberState.focusing && member.s !== MemberState.slipped) throw badState("Only a running timer can slip");
        if (now >= member.e) {
          this.stopMember(room, member, MemberState.done, member.e);
          break;
        }
        member.s = MemberState.slipped;
        member.slipUntil = now + SLIP_SHOW_SECONDS;
        member.slips += 1;
        room.events.push({ sessionId: room.sid, userId, type: "slip", at: now, meta: { slips: member.slips } });
        // The pet's sad spell, as for an early leave (M5): a squad's room only.
        if (room.squadId !== null) room.sadAt = Math.max(room.sadAt ?? 0, now);
        markDirty(room, member);
        this.change(room, 10, now);
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
    room.credits = room.credits.filter((credit) => credit.userId !== userId);
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

  /**
   * Another room says this squad's pet may have changed: one of its members finished a session
   * elsewhere (solo, or in another squad's room), which can change today's mood and streak.
   */
  private async petChanged(room: RoomRecord): Promise<void> {
    if (room.status !== "open" || room.squadId === null) return;
    const now = this.now();
    const refreshed = await this.refreshPet(room, now);
    if (refreshed?.changed === true) this.change(room, refreshed.hatched ? 10 : 5, now);
    await this.commit(room, now, refreshed?.changed === true);
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
      // Demo Buddy's moves first, then timers: both at the time they were due.
      const moved = this.buddyStep(room, now);
      let changed = this.tick(room, now) || moved;
      // The mood changes by itself when a sad spell ends and at the squad's midnight.
      if (room.status === "open" && room.pet !== null && now >= room.pet.checkAt) {
        const refreshed = await this.refreshPet(room, now);
        if (refreshed?.changed === true) {
          this.change(room, refreshed.hatched ? 10 : 5, now);
          changed = true;
        }
      }
      // D1 first, so a push taken now carries what the finishes just earned (the hatch, say).
      if (await this.settle(room, now)) changed = true;
      let taken: Batch | undefined;
      if (room.pending !== undefined && now >= room.pending.flushAt) taken = this.takeBatch(room, now);
      await this.save(room, changed);
      return taken;
    });
    await this.sendPokes();
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

  /**
   * Marks timers that ran out as done (slipped ones too), enforces the 8-hour cap, ends slips that
   * have shown for long enough, clears an old cheer. Whether anything changed.
   */
  private tick(room: RoomRecord, now: number): boolean {
    if (room.status === "ended") return false;
    const before = room.v;
    for (const member of room.members) {
      if (isTicking(member) && member.e <= now) {
        this.stopMember(room, member, MemberState.done, member.e);
      } else if (isRunning(member) && now >= member.b + MEMBER_MAX_SECONDS) {
        this.stopMember(room, member, MemberState.left, now, { cap: true });
      } else if (member.s === MemberState.slipped && (member.slipUntil ?? 0) <= now) {
        // Back to focusing, quietly: priority 5.
        member.s = MemberState.focusing;
        delete member.slipUntil;
        markDirty(room, member);
        this.change(room, 5, now);
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
    delete member.slipUntil;
    member.endedAt = at;
    if (member.bot !== true) {
      room.events.push({ sessionId: room.sid, userId: member.id, type: state === MemberState.done ? "done" : "leave", at, meta: { sec: round, ...meta } });
    }
    this.credit(room, member, state, at, round, meta.cap === true);
    markDirty(room, member);
    this.change(room, 10, this.now());
  }

  /**
   * What the timer earned (M5): coins for every whole focused minute plus the bonus for finishing,
   * XP for the squad's pet, and a sad spell for an early leave (not the 8-hour cap, which nobody
   * chose). Two members finishing in a squad's room hatch its egg. Demo Buddy earns no coins, and its
   * leaving (when nobody else is running) isn't sad; its minutes feed the Review Squad's pet.
   */
  private credit(room: RoomRecord, member: RoomMember, state: MemberState, at: number, focusedSec: number, capped: boolean): void {
    const completed = state === MemberState.done;
    const squadId = room.squadId;
    const bot = member.bot === true;
    room.credits.push({
      sessionId: room.sid,
      userId: member.id,
      startedAt: member.b,
      endedAt: at,
      squadId,
      focusedSec,
      completed,
      coins: bot ? 0 : sessionCoins(focusedSec, completed),
      xp: squadId === null ? 0 : wholeMinutes(focusedSec),
      sad: !bot && squadId !== null && state === MemberState.left && !capped,
    });
    if (!completed) return;
    if (!room.finishers.includes(member.id)) room.finishers.push(member.id);
    if (squadId !== null && room.finishers.length >= 2 && room.hatchAt === undefined && room.pet?.hatched !== true) room.hatchAt = at;
  }

  /**
   * Nobody's timer is running: the room ends, and its final state goes out as an `end` push now.
   * Demo Buddy doesn't keep a room open by itself: once the people in it have all stopped, it leaves.
   */
  private endIfIdle(room: RoomRecord, now: number): void {
    if (room.status !== "open") return;
    this.buddyLeavesIfAlone(room, now);
    if (room.members.some(isRunning)) return;
    room.status = "ended";
    room.endedAt = now;
    room.endDirty = true;
    // Set again once the end push is out; set now too, so a room is cleared away even if that
    // never completes.
    room.cleanupAt = now + ENDED_ROOM_KEPT_SECONDS;
    if (room.cheer !== undefined) {
      delete room.cheer;
      delete room.cheerClearAt;
      room.v += 1;
    }
    // Replaces any update still waiting: only the latest state goes out.
    room.pending = { event: "end", priority: 10, flushAt: now };
  }

  // Demo Buddy (src/demoBuddy.ts)

  /**
   * A person opened or joined a Review Squad's room: Demo Buddy joins a few seconds later, unless
   * it's running here already or on its way, or it's switched off.
   */
  private inviteBuddy(room: RoomRecord, forId: string, now: number): void {
    if (room.review !== true || room.status !== "open" || !demoBuddyEnabled(this.env)) return;
    const bot = room.members.find((member) => member.bot === true);
    if ((bot !== undefined && isRunning(bot)) || room.buddy?.step === "join") return;
    room.buddy = { step: "join", at: now + DEMO_BUDDY_JOIN_DELAY_SECONDS, forId };
  }

  /** POST /squads/:id/demo-buddy/lock-in with the squad's room open: Demo Buddy joins now, unless it's running. */
  private async buddyNow(room: RoomRecord): Promise<void> {
    if (room.status === "ended") throw sessionEnded();
    if (room.review !== true) throw new HttpError(404, "Not found");
    const now = this.now();
    const changed = this.buddyJoins(room, now, null);
    await this.commit(room, now, changed);
  }

  /**
   * Demo Buddy starts a 3-minute timer here, through the same seat as a person (a new timer after
   * finishing, or the end of the row), and its script starts. Whether it joined: not when it's
   * running already, or the room is full.
   */
  private buddyJoins(room: RoomRecord, now: number, forId: string | null): boolean {
    const existing = room.members.find((member) => member.bot === true);
    if (existing !== undefined && isRunning(existing)) return false;
    const seat = this.seatFor(room, DEMO_BUDDY_ID);
    if (seat === null) {
      delete room.buddy;
      console.log(`room ${room.sid}: full, so Demo Buddy didn't join`);
      return false;
    }
    const member = this.timerFor(room, DEMO_BUDDY_ID, DEMO_BUDDY_PROFILE, DEMO_BUDDY_MINUTES, now);
    member.bot = true;
    this.seat(room, member, seat);
    room.buddy = { step: "cheer", at: now + DEMO_BUDDY_CHEER_AFTER_SECONDS, startedAt: now, forId };
    // A join, like anyone's: priority 10.
    this.change(room, 10, now);
    return true;
  }

  /** Demo Buddy's moves that are due: join, cheer, pause, resume (its timer ends by itself). Whether anything changed. */
  private buddyStep(room: RoomRecord, now: number): boolean {
    let changed = false;
    // At most the four moves; a late alarm makes the overdue ones one after the other.
    for (let move = 0; move < 4; move++) {
      const plan = room.buddy;
      if (plan === undefined || room.status !== "open" || now < plan.at) break;
      if (plan.step === "join") {
        if (!demoBuddyEnabled(this.env)) {
          delete room.buddy;
          break;
        }
        if (this.buddyJoins(room, now, plan.forId)) changed = true;
        else if (room.buddy === plan) delete room.buddy;
        continue;
      }
      const bot = room.members.find((member) => member.bot === true);
      if (bot === undefined || !isRunning(bot)) {
        delete room.buddy;
        break;
      }
      const startedAt = plan.startedAt ?? bot.b;
      switch (plan.step) {
        case "cheer": {
          const to = buddyCheerTarget(room, plan.forId);
          if (to !== undefined) {
            room.cheer = { f: bot.id, t: to, k: DEMO_BUDDY_CHEER_KIND, at: now };
            room.cheerClearAt = now + CHEER_SHOWN_SECONDS;
            room.lastCheer[bot.id] = now;
            this.change(room, 5, now);
            changed = true;
          }
          room.buddy = { ...plan, step: "pause", at: startedAt + DEMO_BUDDY_PAUSE_AFTER_SECONDS };
          break;
        }
        case "pause":
          if (isTicking(bot) && now < bot.e) {
            bot.s = MemberState.paused;
            bot.q = now;
            delete bot.slipUntil;
            this.change(room, 5, now);
            changed = true;
          }
          room.buddy = { ...plan, step: "resume", at: startedAt + DEMO_BUDDY_RESUME_AFTER_SECONDS };
          break;
        case "resume":
          if (bot.s === MemberState.paused && bot.q !== undefined) {
            const paused = Math.max(0, now - bot.q);
            bot.e += paused;
            bot.pausedSec += paused;
            delete bot.q;
            bot.s = MemberState.focusing;
            this.change(room, 5, now);
            changed = true;
          }
          // The rest is its timer running out, which the room does for everyone.
          delete room.buddy;
          break;
      }
    }
    return changed;
  }

  /**
   * Once the people in the room have all stopped, Demo Buddy stops too (left, without the sad
   * spell), and a join on its way is called off; so the room ends as it would without it. Not in a
   * room it opened itself that nobody has joined yet.
   */
  private buddyLeavesIfAlone(room: RoomRecord, now: number): void {
    if (room.buddy === undefined && !room.members.some((member) => member.bot === true && isRunning(member))) return;
    const people = room.members.filter((member) => member.bot !== true);
    if (people.some(isRunning)) return;
    if (people.length === 0 && isDemoBuddy(room.hostId)) return;
    delete room.buddy;
    const bot = room.members.find((member) => member.bot === true);
    if (bot !== undefined && isRunning(bot)) this.stopMember(room, bot, MemberState.left, now);
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
      if (isGoneToken(result)) {
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
    // People only: Demo Buddy is counted apart, so stats see real squads as they are.
    const people = room.members.filter((member) => member.bot !== true).length;
    const bots = room.members.length - people;
    console.log(
      `room ${room.sid}: ended after ${minutes} min with ${people} member${people === 1 ? "" : "s"}${bots > 0 ? " and Demo Buddy" : ""}; ` +
        `${p10 + p5} pushes accepted (${p10} at priority 10, ${p5} at 5) in ${batches} batches, ${refused} refused, ${failed} failed, ${cleared} tokens cleared`,
    );
    room.events.push({
      sessionId: room.sid,
      userId: null,
      type: "room_end",
      at: now,
      meta: { members: people, ...(bots > 0 ? { bots } : {}), batches, p10, p5, refused, failed, cleared },
    });
    room.cleanupAt = now + ENDED_ROOM_KEPT_SECONDS;
  }

  // State, storage and D1

  private async load(): Promise<RoomRecord | null> {
    if (this.record === undefined) {
      const stored = await this.state.storage.get<RoomRecord>(STORAGE_KEY);
      this.record = stored === undefined ? null : upgraded(stored);
    }
    return this.record;
  }

  /** Writes D1 if it's behind, saves the room, sets the next alarm, and tells the live views if `changed`. */
  private async commit(room: RoomRecord, now: number, changed: boolean): Promise<void> {
    const settled = await this.settle(room, now);
    await this.save(room, changed || settled);
  }

  /**
   * Writes D1 if it's behind. When that credited a squad's room (M5), reads the pet back and
   * refreshes `p`: priority 10 if the egg hatched, else 5. Whether the state changed.
   */
  private async settle(room: RoomRecord, now: number): Promise<boolean> {
    const synced = await this.syncD1(room, now);
    if (synced === null || room.squadId === null || (synced.credits.length === 0 && !synced.hatched && !synced.sad)) return false;
    const refreshed = await this.refreshPet(room, now);
    if (refreshed?.changed !== true) return false;
    this.change(room, refreshed.hatched ? 10 : 5, now);
    return true;
  }

  /** Saves the room, sets the next alarm, and tells the live views if `changed`. */
  private async save(room: RoomRecord, changed: boolean): Promise<void> {
    await this.state.storage.put(STORAGE_KEY, room);
    await this.scheduleAlarm(room);
    if (changed) this.broadcast(room);
  }

  /** What was written, or null when nothing was (nothing to write, or D1 failed and it's tried again later). */
  private async syncD1(room: RoomRecord, now: number): Promise<Synced | null> {
    if (room.dirty.length === 0 && !room.endDirty && room.events.length === 0 && room.credits.length === 0 && room.hatchAt === undefined && room.sadAt === undefined) {
      return null;
    }
    if (room.syncRetryAt !== undefined && now < room.syncRetryAt && !room.endDirty) return null;
    const participants = room.dirty
      .map((id) => room.members.find((member) => member.id === id))
      .filter((member) => member !== undefined)
      .map((member) => participantRow(room, member));
    const credits = room.credits;
    const hatch = room.squadId !== null && room.hatchAt !== undefined ? { squadId: room.squadId, at: room.hatchAt } : undefined;
    const sad = room.squadId !== null && room.sadAt !== undefined ? { squadId: room.squadId, at: room.sadAt } : undefined;
    try {
      const streakDays = (await this.streakDays(room, credits)).map((day) => ({ ...day, freezeAt: now }));
      await this.db.syncRoom({
        participants,
        ...(room.endDirty ? { ended: { sessionId: room.sid, endedAt: room.endedAt ?? now } } : {}),
        events: room.events,
        credits,
        ...(hatch === undefined ? {} : { hatch }),
        ...(room.squadId !== null && (hatch !== undefined || credits.some((credit) => credit.xp > 0)) ? { stageOf: room.squadId } : {}),
        streakDays,
        ...(sad === undefined ? {} : { sad }),
      });
      room.dirty = [];
      room.endDirty = false;
      room.events = [];
      room.credits = [];
      delete room.hatchAt;
      delete room.sadAt;
      delete room.syncRetryAt;
      return { credits, hatched: hatch !== undefined, sad: sad !== undefined };
    } catch (error) {
      console.error(`room ${room.sid}: D1 write failed (${error instanceof Error ? error.name : typeof error}), trying again in ${D1_RETRY_SECONDS} s`);
      room.syncRetryAt = now + D1_RETRY_SECONDS;
      return null;
    }
  }

  /**
   * The days finished timers may make count, in each of the member's squads (solo sessions count
   * too), each in its squad's zone on the day the timer stopped. Notes the other squads' open rooms
   * to tell afterwards: a finish changes today's mood there.
   */
  private async streakDays(room: RoomRecord, credits: CreditWrite[]): Promise<StreakDayWrite[]> {
    const days = new Map<string, StreakDayWrite>();
    const zones = new Map<string, Awaited<ReturnType<Database["squadZonesOf"]>>>();
    for (const credit of credits) {
      // Demo Buddy's finishes count for no streak, and touch no other squad.
      if (!credit.completed || isDemoBuddy(credit.userId)) continue;
      let mine = zones.get(credit.userId);
      if (mine === undefined) {
        mine = await this.db.squadZonesOf(credit.userId);
        zones.set(credit.userId, mine);
      }
      for (const zone of mine) {
        if (zone.open_session !== null && zone.open_session !== room.sid) this.pokes.set(zone.open_session, credit.userId);
        if (credit.focusedSec < PET_RULES.streakMinMinutes * 60) continue;
        const day = streakDay(zone.squad_id, zone.tz, credit.endedAt);
        days.set(`${day.squadId} ${day.day}`, day);
      }
    }
    return [...days.values()];
  }

  /** Tells other squads' open rooms to look at their pet again (`pet`). Best effort: failures are logged. */
  private async sendPokes(): Promise<void> {
    const pokes = [...this.pokes];
    this.pokes.clear();
    for (const [sessionId, userId] of pokes) {
      try {
        const stub = this.env.ROOMS.get(this.env.ROOMS.idFromName(sessionId));
        const response = await stub.fetch(
          new Request("https://room/pet", {
            method: "POST",
            headers: { [ROOM_USER_HEADER]: userId, [ROOM_SESSION_HEADER]: sessionId, "content-type": "application/json" },
            body: "{}",
          }),
        );
        if (!response.ok && response.status !== 404) console.error(`room ${sessionId}: answered ${response.status} to pet`);
      } catch (error) {
        console.error(`room ${sessionId}: couldn't be told about its pet (${error instanceof Error ? error.name : typeof error})`);
      }
    }
  }

  /** The soonest of every timed job, as the one alarm. */
  private async scheduleAlarm(room: RoomRecord): Promise<void> {
    const times: number[] = [];
    if (room.pending !== undefined) times.push(room.pending.flushAt);
    if (room.syncRetryAt !== undefined) times.push(room.syncRetryAt);
    if (room.status === "open") {
      for (const member of room.members) {
        if (isTicking(member)) times.push(member.e);
        if (isRunning(member)) times.push(member.b + MEMBER_MAX_SECONDS);
        if (member.s === MemberState.slipped && member.slipUntil !== undefined) times.push(member.slipUntil);
      }
      if (room.cheer !== undefined && room.cheerClearAt !== undefined) times.push(room.cheerClearAt);
      if (room.pet !== null) times.push(room.pet.checkAt);
      if (room.buddy !== undefined) times.push(room.buddy.at);
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

  /**
   * The squad's name and pet from D1 (src/progress.ts). Unchanged if the squad is gone; if D1 can't
   * be read, the pet stays as it was and is looked at again in D1_RETRY_SECONDS. Never throws:
   * whether `p` changed, and whether that was the egg hatching, or null if nothing was read.
   */
  private async refreshPet(room: RoomRecord, now: number): Promise<{ changed: boolean; hatched: boolean } | null> {
    if (room.squadId === null) return null;
    try {
      const squad = await this.db.squadById(room.squadId);
      if (squad === null) {
        // The squad is gone (its last member left): keep showing the pet as it was.
        if (room.pet !== null) room.pet.checkAt = now + ENDED_ROOM_KEPT_SECONDS;
        return null;
      }
      room.squadName = squad.name;
      room.review = squad.review === 1;
      const before = room.pet;
      const pet = petSnapshot(await squadProgress(this.db, squad, now, (length) => this.random(length)));
      // Never a check in the past, which would fire the alarm again at once.
      pet.checkAt = Math.max(pet.checkAt, now + 60);
      room.pet = pet;
      const changed = before === null || before.k !== pet.k || before.md !== pet.md || before.x !== pet.x;
      return { changed, hatched: before !== null && !before.hatched && pet.hatched };
    } catch (error) {
      console.error(`room ${room.sid}: couldn't read the squad's pet (${error instanceof Error ? error.name : typeof error}), trying again in ${D1_RETRY_SECONDS} s`);
      if (room.pet !== null) room.pet.checkAt = now + D1_RETRY_SECONDS;
      return null;
    }
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
    if (room.pet !== null && isPetCode(room.pet.k)) state.p = { k: room.pet.k, md: room.pet.md, x: room.pet.x };
    if (room.cheer !== undefined) state.c = room.cheer;
    // The shared encoder's key order, optional keys left out: what Swift's default decoder takes.
    return canonicalContentState(state);
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
  // Demo Buddy has no participants row to keep up to date.
  if (member.bot === true) return;
  if (!room.dirty.includes(member.id)) room.dirty.push(member.id);
}

/** Whom Demo Buddy cheers: whoever brought it, if they're still here, else someone running, else anyone here. */
function buddyCheerTarget(room: RoomRecord, forId: string | null): string | undefined {
  const people = room.members.filter((member) => member.bot !== true && member.s !== MemberState.left);
  return (people.find((member) => member.id === forId && isRunning(member)) ?? people.find(isRunning) ?? people[0])?.id;
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

/** The pet as the room keeps it: the content-state's `p`, whether it hatched, and when to look again. */
function petSnapshot(progress: SquadProgress): PetSnapshot {
  const scale = 10 ** PET_PROGRESS_DECIMALS;
  return {
    // M7: a boosted squad's pet wears its accessory, "sprout.2.a3" (PetCode ignores what follows the stage).
    k: `${progress.species}.${progress.stage}${progress.accessory === null ? "" : `.a${progress.accessory}`}`,
    md: progress.mood,
    x: Math.round(progress.progress * scale) / scale,
    hatched: progress.hatched,
    checkAt: progress.changesAt,
  };
}

/** A room saved by an earlier version, given what's new since (M5, decision 0009). */
function upgraded(room: RoomRecord): RoomRecord {
  room.credits ??= [];
  room.finishers ??= [];
  // Before gentle slips, a slip stopped the timer: such a member has left, and isn't running.
  for (const member of room.members) {
    if (member.s === MemberState.slipped && member.slipUntil === undefined && member.endedAt !== undefined) member.s = MemberState.left;
  }
  // M3 kept the pet as species, stage, XP and mood; it's read again at the room's next change.
  if (room.pet !== null && typeof (room.pet as Partial<PetSnapshot>).k !== "string") room.pet = null;
  return room;
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
