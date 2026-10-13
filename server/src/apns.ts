// Live Activity pushes to APNs, with token-based auth: an ES256 JWT signed with the .p8 key.
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
 * How old the cached provider token gets before it's signed again. Apple rejects a token older
 * than an hour (ExpiredProviderToken) and one refreshed more than every 20 minutes
 * (TooManyProviderTokenUpdates), so 40 minutes sits safely between the two.
 */
export const PROVIDER_TOKEN_REFRESH_SECONDS = 40 * 60;

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

export class ApnsClient {
  /** `<bundle id>.push-type.liveactivity`. */
  readonly topic: string;

  private readonly credentials: ApnsCredentials;
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;
  private key: CryptoKey | undefined;
  private cached: { token: string; issuedAt: number } | undefined;
  private signing: Promise<string> | undefined;

  constructor(credentials: ApnsCredentials, dependencies: ApnsDependencies = {}) {
    for (const field of ["teamId", "keyId", "privateKey", "bundleId"] as const) {
      if (credentials[field].trim().length === 0) throw new ApnsConfigError(`APNs ${field} is empty`);
    }
    this.credentials = credentials;
    this.topic = `${credentials.bundleId}.push-type.liveactivity`;
    // Wrapped: stored bare and called as `this.fetcher(…)`, the global fetch would get the client as
    // `this`, which Workers refuse ("Illegal invocation").
    const fetcher = dependencies.fetch ?? fetch;
    this.fetcher = (input, init) => fetcher(input, init);
    this.now = dependencies.now ?? (() => Date.now() / 1000);
  }

  /** The provider token for the `authorization` header: cached, and signed again once it's 40 minutes old. */
  async providerToken(): Promise<string> {
    const cached = this.cached;
    if (cached !== undefined && this.now() - cached.issuedAt < PROVIDER_TOKEN_REFRESH_SECONDS) return cached.token;
    // Requests that arrive together share one signature: every new token counts towards Apple's
    // once-per-20-minutes limit.
    this.signing ??= this.signProviderToken().finally(() => {
      this.signing = undefined;
    });
    return this.signing;
  }

  private async signProviderToken(): Promise<string> {
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
    return token;
  }

  /**
   * Sends one Live Activity push. Resolves with APNs' answer, refusals included; rejects only when
   * the key is unusable (`ApnsConfigError`) or APNs can't be reached at all.
   */
  async sendLiveActivity(push: LiveActivityPush): Promise<ApnsResult> {
    if (!isDeviceToken(push.deviceToken)) throw new TypeError("deviceToken must be the push token as hex");
    if (!Object.hasOwn(APNS_HOSTS, push.environment)) throw new TypeError("environment must be sandbox or production");
    if (push.priority !== 5 && push.priority !== 10) throw new TypeError("priority must be 5 or 10");

    const url = `${APNS_HOSTS[push.environment]}/3/device/${push.deviceToken.toLowerCase()}`;
    const body = JSON.stringify(push.payload);
    const token = await this.providerToken();
    const result = await this.post(url, token, push, body);
    if (result.status !== 403 || result.reason !== "ExpiredProviderToken") return result;

    // Our clock and Apple's disagree about the token's age. Sign a new one (unless a concurrent
    // request already has) and try once more.
    if (this.cached?.token === token) this.cached = undefined;
    return this.post(url, await this.providerToken(), push, body);
  }

  private async post(url: string, token: string, push: LiveActivityPush, body: string): Promise<ApnsResult> {
    const headers: Record<string, string> = {
      authorization: `bearer ${token}`,
      "apns-push-type": "liveactivity",
      "apns-topic": this.topic,
      "apns-priority": String(push.priority),
      "content-type": "application/json",
    };
    if (push.expiration !== undefined) headers["apns-expiration"] = String(Math.floor(push.expiration));

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
