// One APNs provider token for every isolate (docs/decisions/0004).
//
// APNs refuses a *new* provider token more than once every 20 minutes on one connection (429
// TooManyProviderTokenUpdates). Cloudflare owns the connections to APNs, every Room may run in its
// own isolate, and two isolates signing the same claims get different tokens (ECDSA signatures are
// randomised). So no isolate signs for itself: a single `ApnsAuth` Durable Object, named "global",
// signs the token, keeps it in storage, and hands the same one to everyone for 40 minutes. Each room
// keeps its copy until 5 minutes before that mark (`SharedProviderToken`), then asks again.
//
// It never signs again because of a 429, only when the token is 40 minutes old or when a room
// reports 403 ExpiredProviderToken for the token that's current.
//
//   GET  https://apns-auth/token                       -> { token, issuedAt }
//   POST https://apns-auth/token  { "expired": token } -> { token, issuedAt }, a new one if `token` was current
//
// Only the Worker's own code can reach a Durable Object (through the APNS_AUTH binding), never the
// internet. The token is never logged.
//
// A plain class rather than `extends DurableObject` from "cloudflare:workers", so the tests can
// load it in Node; the runtime accepts a plain class with a `fetch` handler.

import {
  ApnsConfigError,
  PROVIDER_TOKEN_REFRESH_SECONDS,
  type ProviderToken,
  type ProviderTokenSource,
  ProviderTokenSigner,
} from "./apns.ts";
import type { Env } from "./env.ts";
import { HttpError, errorResponse, isRecord, json, notFound, readJSON } from "./http.ts";

/** The one instance's name: `env.APNS_AUTH.idFromName(APNS_AUTH_NAME)`. */
export const APNS_AUTH_NAME = "global";

/** Rooms keep a token this long after it was signed, then ask again: 5 minutes before ApnsAuth replaces it. */
export const SHARED_TOKEN_REUSE_SECONDS = PROVIDER_TOKEN_REFRESH_SECONDS - 5 * 60;

const STORAGE_KEY = "providerToken";
const ENDPOINT = "https://apns-auth/token";

/** What ApnsAuth keeps, so a restart reuses the token instead of signing a new one early. */
interface StoredToken extends ProviderToken {
  teamId: string;
  keyId: string;
}

/** The part of `DurableObjectState` ApnsAuth uses, so tests can pass a fake. */
export interface ApnsAuthState {
  readonly storage: {
    get<T>(key: string): Promise<T | undefined>;
    put<T>(key: string, value: T): Promise<void>;
  };
}

export interface ApnsAuthDependencies {
  /** Unix seconds. */
  now?: () => number;
}

export class ApnsAuth {
  private readonly state: ApnsAuthState;
  private readonly env: Env;
  private readonly now: () => number;
  private signer: { signer: ProviderTokenSigner; teamId: string; keyId: string; privateKey: string } | undefined;
  private stored: StoredToken | null | undefined;

  constructor(state: ApnsAuthState, env: Env, dependencies: ApnsAuthDependencies = {}) {
    this.state = state;
    this.env = env;
    this.now = dependencies.now ?? (() => Date.now() / 1000);
  }

  async fetch(request: Request): Promise<Response> {
    if (new URL(request.url).pathname !== "/token") return notFound();
    try {
      if (request.method === "GET") return json(await this.current());
      if (request.method === "POST") {
        const body = await readJSON(request);
        if (!isRecord(body) || typeof body.expired !== "string") throw new HttpError(400, 'Expected {"expired": "<token>"}');
        const signer = await this.loadSigner();
        await signer.expired(body.expired);
        return json(await this.current());
      }
      return notFound();
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error);
      if (error instanceof ApnsConfigError) {
        console.error(`apns-auth: ${error.message}`);
        return json({ error: error.message, code: "apns_not_configured" }, 500);
      }
      throw error;
    }
  }

  /** The current token, signed now if there's none or it's 40 minutes old; kept in storage. */
  private async current(): Promise<ProviderToken> {
    const signer = await this.loadSigner();
    const token = await signer.current();
    if (this.stored?.token !== token.token) {
      const { teamId, keyId } = this.signer ?? { teamId: "", keyId: "" };
      this.stored = { token: token.token, issuedAt: token.issuedAt, teamId, keyId };
      await this.state.storage.put(STORAGE_KEY, this.stored);
      console.log("apns-auth: signed a new provider token");
    }
    return { token: token.token, issuedAt: token.issuedAt };
  }

  /** The signer for the current secrets, primed with the stored token if it was signed with the same key. */
  private async loadSigner(): Promise<ProviderTokenSigner> {
    const teamId = this.env.APNS_TEAM_ID?.trim() ?? "";
    const keyId = this.env.APNS_KEY_ID?.trim() ?? "";
    const privateKey = this.env.APNS_PRIVATE_KEY ?? "";
    const missing = [teamId ? undefined : "APNS_TEAM_ID", keyId ? undefined : "APNS_KEY_ID", privateKey.trim() ? undefined : "APNS_PRIVATE_KEY"].filter(
      (name) => name !== undefined,
    );
    if (missing.length > 0) throw new ApnsConfigError(`APNs isn't set up: ${missing.join(", ")} missing (server/README.md)`);

    const current = this.signer;
    if (current !== undefined && current.teamId === teamId && current.keyId === keyId && current.privateKey === privateKey) return current.signer;

    // A new isolate, or the secrets changed: start from the stored token if it's from this key.
    const signer = new ProviderTokenSigner({ teamId, keyId, privateKey }, this.now);
    if (this.stored === undefined) this.stored = (await this.state.storage.get<StoredToken>(STORAGE_KEY)) ?? null;
    if (this.stored !== null && this.stored.teamId === teamId && this.stored.keyId === keyId) signer.restore(this.stored);
    this.signer = { signer, teamId, keyId, privateKey };
    return signer;
  }
}

/**
 * The rooms' token source: asks `ApnsAuth` and keeps the answer until 5 minutes before ApnsAuth
 * would replace it, so every room presents the token ApnsAuth is handing out.
 */
export class SharedProviderToken implements ProviderTokenSource {
  private readonly namespace: DurableObjectNamespace;
  private readonly now: () => number;
  private cached: ProviderToken | undefined;
  private asking: Promise<ProviderToken> | undefined;

  constructor(namespace: DurableObjectNamespace, now: () => number = () => Date.now() / 1000) {
    this.namespace = namespace;
    this.now = now;
  }

  async token(): Promise<string> {
    const cached = this.cached;
    if (cached !== undefined && this.now() - cached.issuedAt < SHARED_TOKEN_REUSE_SECONDS) return cached.token;
    this.asking ??= this.ask({ method: "GET" }).finally(() => {
      this.asking = undefined;
    });
    return (await this.asking).token;
  }

  async expired(token: string): Promise<void> {
    if (this.cached !== undefined && this.cached.token !== token) return;
    this.cached = undefined;
    await this.ask({ method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ expired: token }) });
  }

  private async ask(init: RequestInit): Promise<ProviderToken> {
    const stub = this.namespace.get(this.namespace.idFromName(APNS_AUTH_NAME));
    const response = await stub.fetch(ENDPOINT, init);
    const body = (await response.json().catch(() => null)) as unknown;
    if (!response.ok || !isRecord(body) || typeof body.token !== "string" || typeof body.issuedAt !== "number") {
      const message = isRecord(body) && typeof body.error === "string" ? body.error : `ApnsAuth answered ${response.status}`;
      throw new ApnsConfigError(message);
    }
    this.cached = { token: body.token, issuedAt: body.issuedAt };
    return this.cached;
  }
}
