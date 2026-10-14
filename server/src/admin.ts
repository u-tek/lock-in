// POST /admin/push-test: the M0 APNs spike (SPEC.md §6). Sends a made-up squad to one Live
// Activity so a TestFlight build on a real iPhone can show whether a deployed Worker reaches APNs.
// Development only, behind ADMIN_TOKEN (README.md).

import {
  ApnsClient,
  ApnsConfigError,
  type ApnsCredentials,
  type ApnsDependencies,
  type ApnsEnvironment,
  type ApnsPriority,
  type ApnsResult,
  isDeviceToken,
} from "./apns.ts";
import { SharedProviderToken } from "./apnsAuth.ts";
import { DEMO_SCENARIOS, type DemoScenario, demoScenario } from "./demo.ts";
import type { Env } from "./env.ts";
import { HttpError, hasBearerToken, json, notFound, readJSON } from "./http.ts";
import {
  type ContentState,
  LiveActivityError,
  assertPayloadBudget,
  buildLiveActivityPayload,
  isShortID,
  parseContentState,
  staleDateFor,
} from "./liveActivity.ts";

/** Shorter than this and the admin token counts as unset. */
export const MIN_ADMIN_TOKEN_LENGTH = 32;

interface PushTestRequest {
  token: string;
  env: ApnsEnvironment;
  me?: string;
  sid?: string;
  scenario: DemoScenario;
  priority?: ApnsPriority;
  contentState?: ContentState;
}

const PUSH_TEST_KEYS = ["token", "env", "me", "sid", "scenario", "priority", "contentState"];

/**
 * Sends one Live Activity update (or end) to the token in the body. The app's APNs spike screen
 * copies `{"token", "env", "me", "sid"}`, which is a complete body; add `scenario` for the others.
 *
 * The route doesn't exist (404, like any unknown path) in production, without a long enough
 * ADMIN_TOKEN, or without the right bearer token: nothing to find by probing.
 */
export async function pushTest(request: Request, env: Env, deps: ApnsDependencies): Promise<Response> {
  const adminToken = env.ADMIN_TOKEN?.trim() ?? "";
  if (env.ENVIRONMENT === "production" || adminToken.length < MIN_ADMIN_TOKEN_LENGTH) return notFound();
  if (!(await hasBearerToken(request, adminToken))) return notFound();

  const input = parsePushTestRequest(await readJSON(request));
  const now = (deps.now ?? (() => Date.now() / 1000))();
  const demo = demoScenario(input.scenario, { me: input.me, sid: input.sid, now });
  const state = input.contentState ?? demo.state;
  const priority = input.priority ?? demo.priority;
  const { event } = demo;

  let bytes: number;
  let payload: ReturnType<typeof buildLiveActivityPayload>;
  try {
    bytes = assertPayloadBudget(demo.attributes, state);
    payload = buildLiveActivityPayload({
      event,
      state,
      timestamp: now,
      ...(event === "update" ? { staleDate: staleDateFor(state, now) } : {}),
    });
  } catch (error) {
    if (error instanceof LiveActivityError) throw new HttpError(400, error.message);
    throw error;
  }

  const client = apnsClient(apnsCredentials(env), env, deps);
  let result: ApnsResult;
  try {
    result = await client.sendLiveActivity({ deviceToken: input.token, environment: input.env, priority, payload });
  } catch (error) {
    const message = redact(error instanceof Error ? error.message : String(error));
    if (error instanceof ApnsConfigError) {
      console.error(`push-test: ${message}`);
      throw new HttpError(500, `${message}. Check the APNS_* secrets (server/README.md).`);
    }
    console.error(`push-test: couldn't reach APNs (${message})`);
    return json({ error: `Couldn't reach APNs: ${message}`, environment: input.env, bytes, event }, 502);
  }

  // Status and size only: never the device token or the provider token.
  console.log(
    `push-test: ${input.env} ${event} p${priority} ${bytes} bytes -> APNs ${result.status}${result.reason ? ` ${result.reason}` : ""}`,
  );
  const body = {
    status: result.status,
    apnsId: result.apnsId,
    ...(result.reason !== undefined ? { reason: result.reason } : {}),
    environment: input.env,
    bytes,
    event,
    contentState: payload.aps["content-state"],
  };
  // A refusal is still a well-formed answer, but not a success: 502 makes `curl --fail` notice.
  return json(body, result.ok ? 200 : 502);
}

function parsePushTestRequest(body: unknown): PushTestRequest {
  const bad = (message: string) => new HttpError(400, message);
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw bad('Expected a JSON object like {"token": "<hex>", "env": "sandbox"}');
  }
  const record = body as Record<string, unknown>;
  const unknown = Object.keys(record).filter((key) => !PUSH_TEST_KEYS.includes(key));
  if (unknown.length > 0) throw bad(`Unknown ${unknown.join(", ")}: the keys are ${PUSH_TEST_KEYS.join(", ")}`);

  if (!isDeviceToken(record.token)) {
    throw bad("token must be the Live Activity push token in hex, as the app's APNs spike screen copies it");
  }
  if (record.env !== "sandbox" && record.env !== "production") {
    throw bad('env must be "sandbox" (Xcode builds) or "production" (TestFlight and App Store builds)');
  }
  const request: PushTestRequest = { token: record.token, env: record.env, scenario: "squad" };

  for (const key of ["me", "sid"] as const) {
    if (record[key] === undefined) continue;
    if (!isShortID(record[key])) throw bad(`${key} must be a 10-character base62 id, as the app's APNs spike screen copies it`);
    request[key] = record[key];
  }
  if (record.scenario !== undefined) {
    if (!DEMO_SCENARIOS.includes(record.scenario as DemoScenario)) throw bad(`scenario must be one of ${DEMO_SCENARIOS.join(", ")}`);
    request.scenario = record.scenario as DemoScenario;
  }
  if (record.priority !== undefined) {
    if (record.priority !== 5 && record.priority !== 10) throw bad("priority must be 5 or 10");
    request.priority = record.priority;
  }
  if (record.contentState !== undefined) {
    try {
      request.contentState = parseContentState(record.contentState, "contentState");
    } catch (error) {
      if (error instanceof LiveActivityError) throw bad(error.message);
      throw error;
    }
  }
  return request;
}

function apnsCredentials(env: Env): ApnsCredentials {
  const credentials = {
    teamId: env.APNS_TEAM_ID?.trim() ?? "",
    keyId: env.APNS_KEY_ID?.trim() ?? "",
    privateKey: env.APNS_PRIVATE_KEY ?? "",
    bundleId: env.APNS_BUNDLE_ID?.trim() ?? "",
  };
  const missing = [
    credentials.teamId ? undefined : "APNS_TEAM_ID",
    credentials.keyId ? undefined : "APNS_KEY_ID",
    credentials.privateKey.trim() ? undefined : "APNS_PRIVATE_KEY",
    credentials.bundleId ? undefined : "APNS_BUNDLE_ID",
  ].filter((name) => name !== undefined);
  if (missing.length > 0) throw new HttpError(500, `APNs isn't set up: ${missing.join(", ")} missing (server/README.md)`);
  return credentials;
}

// One client per isolate. Deployed, it presents the provider token every room presents, from the
// `ApnsAuth` Durable Object: APNs answers 429 TooManyProviderTokenUpdates when one connection sees a
// new token more than once in 20 minutes, and Cloudflare may share connections between isolates
// (docs/decisions/0004). Tests inject `fetch` and get a fresh client that signs its own token.
let sharedClient: { credentials: string; client: ApnsClient } | undefined;

function apnsClient(credentials: ApnsCredentials, env: Env, deps: ApnsDependencies): ApnsClient {
  if (deps.fetch !== undefined || deps.now !== undefined) return new ApnsClient(credentials, deps);
  const key = JSON.stringify(credentials);
  if (sharedClient?.credentials !== key) {
    const client =
      env.APNS_AUTH === undefined
        ? new ApnsClient(credentials)
        : new ApnsClient({ bundleId: credentials.bundleId, tokens: new SharedProviderToken(env.APNS_AUTH) });
    sharedClient = { credentials: key, client };
  }
  return sharedClient.client;
}

/** Error messages go to logs and responses; long hex runs could be a device token. */
function redact(message: string): string {
  return message.replace(/[0-9a-fA-F]{16,}/g, "<redacted>");
}
