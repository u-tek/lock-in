// Stand-ins for the Durable Objects runtime, so rooms run in plain Node: storage with one alarm a
// test can fire, accepted WebSockets that record what they're sent, a namespace that creates one
// object per name (and can evict it, as the runtime does), and an APNs that records every push and
// answers per token.

import type { RecordedRequest } from "./helpers.ts";

/** Durable Object storage in memory. Values are cloned on the way in and out, as real storage serialises them. */
export class FakeStorage {
  readonly data = new Map<string, unknown>();
  /** Milliseconds since the epoch, or null. */
  alarm: number | null = null;

  async get<T>(key: string): Promise<T | undefined> {
    const value = this.data.get(key);
    return value === undefined ? undefined : (structuredClone(value) as T);
  }

  async put<T>(key: string, value: T): Promise<void> {
    this.data.set(key, structuredClone(value));
  }

  async delete(key: string): Promise<boolean> {
    return this.data.delete(key);
  }

  async deleteAll(): Promise<void> {
    this.data.clear();
  }

  async getAlarm(): Promise<number | null> {
    return this.alarm;
  }

  async setAlarm(scheduledTime: number | Date): Promise<void> {
    this.alarm = typeof scheduledTime === "number" ? scheduledTime : scheduledTime.getTime();
  }

  async deleteAlarm(): Promise<void> {
    this.alarm = null;
  }
}

/** The room's end of a WebSocket: what it sends is what the app would receive. */
export class FakeWebSocket {
  readonly sent: string[] = [];
  closed: { code?: number; reason?: string } | undefined;

  send(message: string): void {
    if (this.closed !== undefined) throw new TypeError("WebSocket is closed");
    this.sent.push(message);
  }

  close(code?: number, reason?: string): void {
    if (this.closed !== undefined) throw new TypeError("WebSocket is already closed");
    this.closed = { code, reason };
  }

  /** Everything sent, parsed. */
  get messages(): any[] {
    return this.sent.map((message) => JSON.parse(message));
  }
}

export interface FakeID {
  name: string;
  toString(): string;
  equals(other: FakeID): boolean;
}

export class FakeState {
  readonly id: FakeID;
  storage = new FakeStorage();
  readonly sockets: FakeWebSocket[] = [];

  constructor(name: string) {
    this.id = { name, toString: () => `id(${name})`, equals: (other) => other.name === name };
  }

  acceptWebSocket(socket: FakeWebSocket): void {
    this.sockets.push(socket);
  }

  getWebSockets(): FakeWebSocket[] {
    return this.sockets.filter((socket) => socket.closed === undefined);
  }
}

interface FetchHandler {
  fetch(request: Request): Promise<Response>;
}

/** A Durable Object namespace: `get(idFromName(name)).fetch(…)` reaches the one object for `name`. */
export class FakeNamespace<T extends FetchHandler> {
  readonly objects = new Map<string, { object: T; state: FakeState }>();
  /** Every request any object received, in order: `{ name, path }`. */
  readonly calls: Array<{ name: string; path: string }> = [];
  private readonly create: (state: FakeState) => T;

  constructor(create: (state: FakeState) => T) {
    this.create = create;
  }

  idFromName(name: string): FakeID {
    return { name, toString: () => `id(${name})`, equals: (other) => other.name === name };
  }

  get(id: FakeID): { fetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> } {
    return {
      fetch: async (input, init) => {
        const request = new Request(input, init);
        this.calls.push({ name: id.name, path: new URL(request.url).pathname });
        return this.entry(id.name).object.fetch(request);
      },
    };
  }

  entry(name: string): { object: T; state: FakeState } {
    let entry = this.objects.get(name);
    if (entry === undefined) {
      const state = new FakeState(name);
      entry = { object: this.create(state), state };
      this.objects.set(name, entry);
    }
    return entry;
  }

  /** As the runtime may at any moment: a fresh object over the same storage and WebSockets. */
  evict(name: string): void {
    const entry = this.objects.get(name);
    if (entry !== undefined) this.objects.set(name, { object: this.create(entry.state), state: entry.state });
  }

  get binding(): DurableObjectNamespace {
    return this as unknown as DurableObjectNamespace;
  }
}

export interface APNsRequest extends RecordedRequest {
  token: string;
  environment: "sandbox" | "production";
  priority: number;
  /** The provider token (JWT) from `authorization: bearer …`. */
  jwt: string;
  aps: Record<string, any>;
}

export interface APNsAnswer {
  status: number;
  reason?: string;
}

/** APNs: records every push and answers 200 unless a token has another answer set. */
export class FakeAPNs {
  readonly requests: APNsRequest[] = [];
  /** By device token. */
  readonly answers = new Map<string, APNsAnswer>();
  /** By provider token (JWT): checked first, e.g. 403 ExpiredProviderToken for an old one. */
  readonly answersForJWT = new Map<string, APNsAnswer>();
  /** Thrown for every request while set: APNs can't be reached. */
  unreachable = false;

  readonly fetch = (async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = new Request(input, init);
    const headers: Record<string, string> = {};
    request.headers.forEach((value, key) => {
      headers[key] = value;
    });
    const body = await request.text();
    const url = new URL(request.url);
    const token = url.pathname.replace("/3/device/", "");
    this.requests.push({
      url: request.url,
      method: request.method,
      headers,
      body,
      token,
      environment: url.host === "api.push.apple.com" ? "production" : "sandbox",
      priority: Number(headers["apns-priority"]),
      jwt: (headers.authorization ?? "").replace(/^bearer /, ""),
      aps: (JSON.parse(body) as { aps: Record<string, any> }).aps,
    });
    if (this.unreachable) throw new TypeError("Network connection lost");
    const jwt = (headers.authorization ?? "").replace(/^bearer /, "");
    const answer = this.answersForJWT.get(jwt) ?? this.answers.get(token) ?? { status: 200 };
    const responseBody = answer.reason === undefined ? null : JSON.stringify({ reason: answer.reason });
    return new Response(responseBody, { status: answer.status, headers: { "apns-id": `apns-${this.requests.length}` } });
  }) as typeof fetch;

  /** Requests to one token. */
  to(token: string): APNsRequest[] {
    return this.requests.filter((request) => request.token === token);
  }

  clear(): void {
    this.requests.length = 0;
  }
}

/** A Live Activity push token per name: 64 hex characters, distinct and recognisable in a failure. */
export function laToken(seed: number): string {
  return seed.toString(16).padStart(2, "0").repeat(32);
}
