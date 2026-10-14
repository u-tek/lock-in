// Pushes to APNs, with token-based auth: an ES256 JWT signed with the .p8 key. Live Activity
// updates (M0, M3) and, from M4, push-to-start (the same call) and ordinary alerts ("X is locking
// in", `sendAlert`).
//
// APNs only speaks HTTP/2. Whether a Worker's outbound fetch gets through to it is exactly what
// the M0 spike proves (SPEC.md §4.2, docs/spikes/apns-worker.md). If it doesn't, the fallback is a
// tiny Node service using node:http2 behind this same interface (`sendLiveActivity`), and nothing
// else in the Worker changes.
//
// Nothing here logs. Device tokens, provider tokens and the key must never reach a log: a device
// token plus our key is a way onto someone's Lock Screen.

import { importP8, signES256 } from "./jwt.ts";

export type ApnsEnvironment = "sandbox" | "production";
export type ApnsPriority = 5 | 10;

/** Xcode builds get sandbox tokens; TestFlight and App Store builds get production ones. */
export const APNS_HOSTS: Readonly<Record<ApnsEnvironment, string>> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

/**
 * How old the provider token gets before it's signed again. Apple asks for a new token no more than
 * every 20 minutes and no less than every 60, and a token whose `iat` is over an hour old gets 403
 * ExpiredProviderToken. APNs enforces the 20-minute floor per connection: a connection that sees a
 * new token more than once in 20 minutes gets 429 TooManyProviderTokenUpdates. Cloudflare, not our
 * code, owns the connections to APNs and may carry several isolates' requests on one, so from M3
 * every room asks one `ApnsAuth` Durable Object for the token (src/apnsAuth.ts,
 * docs/decisions/0004): one token for everyone, changing every 40 minutes.
 */
export const PROVIDER_TOKEN_REFRESH_SECONDS = 40 * 60;

/**
 * The largest request body APNs takes: the whole `{"aps": …}` JSON, alert included, in UTF-8 bytes.
 * Anything bigger gets 413 PayloadTooLarge, so it's refused here before it's sent.
 */
export const APNS_BODY_LIMIT_BYTES = 4096;

export interface ApnsCredentials {
  /** The Apple Developer team ID. */
  teamId: string;
  /** The APNs key's 10-character ID. */
  keyId: string;
  /** The contents of AuthKey_XXXXXXXXXX.p8. */
  privateKey: string;
  /** The app's bundle ID, not the widget extension's. */
  bundleId: string;
}

/** A provider token and when it was signed (its `iat`, Unix seconds). */
export interface ProviderToken {
  token: string;
  issuedAt: number;
}

/** Where an `ApnsClient` gets the provider token for its `authorization` header. */
export interface ProviderTokenSource {
  /** The token to send now. */
  token(): Promise<string>;
  /** APNs answered 403 ExpiredProviderToken to `token`: replace it, unless that's already happened. */
  expired(token: string): Promise<void>;
}

/** A client that takes its provider token from elsewhere (the rooms: `SharedProviderToken`). */
export interface ApnsTokenConfig {
  /** The app's bundle ID, not the widget extension's. */
  bundleId: string;
  tokens: ProviderTokenSource;
}

export interface ApnsDependencies {
  fetch?: typeof fetch;
  /** Unix seconds. */
  now?: () => number;
}

export interface LiveActivityPush {
  /** The activity's push token (from `pushTokenUpdates`), as hex. */
  deviceToken: string;
  environment: ApnsEnvironment;
  /** 10 counts against the activity's hourly budget; 5 doesn't (SPEC.md §4.4). */
  priority: ApnsPriority;
  /** The whole APNs body, `{ aps: { … } }`. */
  payload: unknown;
  /** Unix seconds after which APNs stops trying to deliver; 0 means one attempt. */
  expiration?: number;
}

/** An ordinary notification (`apns-push-type: alert`), always at priority 10. */
export interface AlertPush {
  /** The app's device token (from `registerForRemoteNotifications`), as hex. */
  deviceToken: string;
  environment: ApnsEnvironment;
  /** The whole APNs body, `{ aps: { alert, … }, … }`. */
  payload: unknown;
  /** `apns-collapse-id`: a newer alert with the same id replaces this one. At most 64 bytes. */
  collapseId?: string;
  /** Unix seconds after which APNs stops trying to deliver; 0 means one attempt. */
  expiration?: number;
}

/** Apple's limit on `apns-collapse-id`, in bytes. */
export const COLLAPSE_ID_LIMIT_BYTES = 64;

export interface ApnsResult {
  ok: boolean;
  status: number;
  /** APNs' id for the notification (the `apns-id` response header). */
  apnsId: string | null;
  /** Why APNs refused, e.g. `BadDeviceToken`. */
  reason?: string;
  /** On 410: when APNs learnt the token was no longer valid, in milliseconds since the epoch. */
  timestamp?: number;
}

/** The credentials or the key are unusable: a set-up problem, not a delivery one. */
export class ApnsConfigError extends Error {
  override name = "ApnsConfigError";
}

// Tokens are 32 bytes today, but Apple says not to rely on a length. The bound keeps the path sane.
const DEVICE_TOKEN = /^(?:[0-9a-fA-F]{2}){8,256}$/;

export function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" && DEVICE_TOKEN.test(value);
}

/**
 * Signs provider tokens with the `.p8` key and keeps each one for `PROVIDER_TOKEN_REFRESH_SECONDS`.
 * Requests that arrive together share one signature. Used by `ApnsAuth`, which hands its token to
 * every room, and by `/admin/push-test` under test.
 */
export class ProviderTokenSigner implements ProviderTokenSource {
  private readonly credentials: Pick<ApnsCredentials, "teamId" | "keyId" | "privateKey">;
  private readonly now: () => number;
  private key: CryptoKey | undefined;
  private cached: ProviderToken | undefined;
  private signing: Promise<ProviderToken> | undefined;

  constructor(credentials: Pick<ApnsCredentials, "teamId" | "keyId" | "privateKey">, now: () => number = () => Date.now() / 1000) {
    for (const field of ["teamId", "keyId", "privateKey"] as const) {
      if (credentials[field].trim().length === 0) throw new ApnsConfigError(`APNs ${field} is empty`);
    }
    this.credentials = credentials;
    this.now = now;
  }

  /** The cached token, or a new one once it's 40 minutes old. */
  async current(): Promise<ProviderToken> {
    const cached = this.cached;
    if (cached !== undefined && this.now() - cached.issuedAt < PROVIDER_TOKEN_REFRESH_SECONDS) return cached;
    // Requests that arrive together share one signature: a connection that sees a new token more
    // than once in 20 minutes gets 429 TooManyProviderTokenUpdates.
    this.signing ??= this.sign().finally(() => {
      this.signing = undefined;
    });
    return this.signing;
  }

  async token(): Promise<string> {
    return (await this.current()).token;
  }

  /** Forgets `token` if it's still the current one, so the next request signs again. */
  async expired(token: string): Promise<void> {
    if (this.cached?.token === token) this.cached = undefined;
  }

  /** Starts from a token signed earlier (by this key), e.g. one `ApnsAuth` kept in storage. */
  restore(token: ProviderToken): void {
    this.cached = { token: token.token, issuedAt: token.issuedAt };
  }

  private async sign(): Promise<ProviderToken> {
    if (this.key === undefined) {
      try {
        this.key = await importP8(this.credentials.privateKey);
      } catch (error) {
        throw new ApnsConfigError(`The APNs key isn't a usable .p8 key (${error instanceof Error ? error.message : "unknown error"})`);
      }
    }
    const issuedAt = Math.floor(this.now());
    const token = await signES256({ kid: this.credentials.keyId }, { iss: this.credentials.teamId, iat: issuedAt }, this.key);
    this.cached = { token, issuedAt };
    return this.cached;
  }
}

export class ApnsClient {
  /** `<bundle id>.push-type.liveactivity`: Live Activity pushes. */
  readonly topic: string;
  /** The bundle ID itself: alerts. */
  readonly alertTopic: string;

  private readonly tokens: ProviderTokenSource;
  private readonly fetcher: typeof fetch;

  /**
   * With credentials, the client signs its own provider tokens (`ProviderTokenSigner`); with a
   * token source, it asks that instead (the rooms ask `ApnsAuth`, docs/decisions/0004).
   */
  constructor(config: ApnsCredentials | ApnsTokenConfig, dependencies: ApnsDependencies = {}) {
    if (config.bundleId.trim().length === 0) throw new ApnsConfigError("APNs bundleId is empty");
    this.topic = `${config.bundleId}.push-type.liveactivity`;
    this.alertTopic = config.bundleId;
    this.tokens = "tokens" in config ? config.tokens : new ProviderTokenSigner(config, dependencies.now);
    // Wrapped: stored bare and called as `this.fetcher(…)`, the global fetch would get the client as
    // `this`, which Workers refuse ("Illegal invocation").
    const fetcher = dependencies.fetch ?? fetch;
    this.fetcher = (input, init) => fetcher(input, init);
  }

  /** The provider token for the `authorization` header, from the client's token source. */
  providerToken(): Promise<string> {
    return this.tokens.token();
  }

  /**
   * Sends one Live Activity push: an update, an end or a push-to-start. Resolves with APNs' answer,
   * refusals included; rejects when the push itself is malformed (`TypeError`, or `RangeError` for a
   * body over `APNS_BODY_LIMIT_BYTES`), when the key is unusable (`ApnsConfigError`) or when APNs
   * can't be reached at all.
   */
  async sendLiveActivity(push: LiveActivityPush): Promise<ApnsResult> {
    if (push.priority !== 5 && push.priority !== 10) throw new TypeError("priority must be 5 or 10");
    const headers: Record<string, string> = {
      "apns-push-type": "liveactivity",
      "apns-topic": this.topic,
      "apns-priority": String(push.priority),
    };
    if (push.expiration !== undefined) headers["apns-expiration"] = String(Math.floor(push.expiration));
    return this.send(push.deviceToken, push.environment, push.payload, headers);
  }

  /**
   * Sends one alert to the app (M4's "X is locking in"), at priority 10 to the bundle ID's topic.
   * Resolves and rejects as `sendLiveActivity` does; a collapse id over 64 bytes is a `TypeError`.
   */
  async sendAlert(push: AlertPush): Promise<ApnsResult> {
    const headers: Record<string, string> = {
      "apns-push-type": "alert",
      "apns-topic": this.alertTopic,
      "apns-priority": "10",
    };
    if (push.collapseId !== undefined) {
      const bytes = new TextEncoder().encode(push.collapseId).length;
      if (bytes === 0 || bytes > COLLAPSE_ID_LIMIT_BYTES) throw new TypeError(`collapseId must be 1–${COLLAPSE_ID_LIMIT_BYTES} bytes`);
      headers["apns-collapse-id"] = push.collapseId;
    }
    if (push.expiration !== undefined) headers["apns-expiration"] = String(Math.floor(push.expiration));
    return this.send(push.deviceToken, push.environment, push.payload, headers);
  }

  /** Checks the token, environment and size, then posts with the provider token, retrying once if it expired. */
  private async send(deviceToken: string, environment: ApnsEnvironment, payload: unknown, headers: Record<string, string>): Promise<ApnsResult> {
    if (!isDeviceToken(deviceToken)) throw new TypeError("deviceToken must be the push token as hex");
    if (!Object.hasOwn(APNS_HOSTS, environment)) throw new TypeError("environment must be sandbox or production");

    const url = `${APNS_HOSTS[environment]}/3/device/${deviceToken.toLowerCase()}`;
    const body = JSON.stringify(payload);
    const bytes = new TextEncoder().encode(body).length;
    if (bytes > APNS_BODY_LIMIT_BYTES) throw new RangeError(`The payload is ${bytes} bytes; APNs takes at most ${APNS_BODY_LIMIT_BYTES}`);
    const token = await this.providerToken();
    const result = await this.post(url, token, headers, body);
    // Only an expired token is worth signing again. A 429 TooManyProviderTokenUpdates means a
    // connection saw new tokens too often: another one would make it worse, so it's returned as is.
    if (result.status !== 403 || result.reason !== "ExpiredProviderToken") return result;

    // Our clock and Apple's disagree about the token's age. Sign a new one (unless a concurrent
    // request already has) and try once more.
    await this.tokens.expired(token);
    return this.post(url, await this.providerToken(), headers, body);
  }

  private async post(url: string, token: string, pushHeaders: Record<string, string>, body: string): Promise<ApnsResult> {
    const headers: Record<string, string> = {
      authorization: `bearer ${token}`,
      ...pushHeaders,
      "content-type": "application/json",
    };

    const response = await this.fetcher(url, { method: "POST", headers, body });
    const apnsId = response.headers.get("apns-id");
    // Success has an empty body; failures have {"reason": …} and, for 410, {"timestamp": …}.
    const text = await response.text();
    if (response.status === 200) return { ok: true, status: 200, apnsId };

    const result: ApnsResult = { ok: false, status: response.status, apnsId };
    try {
      const error = JSON.parse(text) as { reason?: unknown; timestamp?: unknown };
      if (typeof error.reason === "string") result.reason = error.reason;
      if (typeof error.timestamp === "number") result.timestamp = error.timestamp;
    } catch {
      // Not JSON: the status alone will have to do.
    }
    return result;
  }
}

/** APNs says the token is gone for good: 410 Unregistered, or 400 BadDeviceToken (M3, M4). Stop using it. */
export function isGoneToken(result: ApnsResult): boolean {
  return result.status === 410 || result.reason === "BadDeviceToken";
}
