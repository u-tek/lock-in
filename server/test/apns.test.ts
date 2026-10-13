import { describe, expect, test } from "vitest";
import { ApnsClient, ApnsConfigError, PROVIDER_TOKEN_REFRESH_SECONDS, isDeviceToken } from "../src/apns.ts";
import { DEVICE_TOKEN, decodeJWT, fakeAPNs, makeKey, verifyES256 } from "./helpers.ts";

const T0 = 1_791_900_000;
const payload = { aps: { timestamp: T0, event: "update", "content-state": { v: 1, m: [] } } };

async function client(fake: ReturnType<typeof fakeAPNs>, clock = { now: T0 }) {
  const { pem, publicKey } = await makeKey();
  const apns = new ApnsClient(
    { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: pem, bundleId: "com.example.lockin" },
    { fetch: fake.fetch, now: () => clock.now },
  );
  return { apns, publicKey, clock };
}

describe("ApnsClient", () => {
  test("posts a liveactivity push to the right host with the right headers", async () => {
    const fake = fakeAPNs({ status: 200, apnsId: "8E1F3F0C-0000-4000-8000-000000000001" });
    const { apns, publicKey } = await client(fake);

    const result = await apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN.toUpperCase(), environment: "production", priority: 10, payload });
    expect(result).toEqual({ ok: true, status: 200, apnsId: "8E1F3F0C-0000-4000-8000-000000000001" });

    const [request] = fake.requests;
    expect(request?.method).toBe("POST");
    expect(request?.url).toBe(`https://api.push.apple.com/3/device/${DEVICE_TOKEN}`);
    expect(request?.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-topic": "com.example.lockin.push-type.liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    });
    expect(request?.headers).not.toHaveProperty("apns-expiration");
    expect(JSON.parse(request?.body ?? "")).toEqual(payload);

    const authorization = request?.headers.authorization ?? "";
    expect(authorization.startsWith("bearer ")).toBe(true);
    const jwt = decodeJWT(authorization.slice("bearer ".length));
    expect(jwt.header).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(jwt.claims).toEqual({ iss: "TEAM123456", iat: T0 });
    expect(await verifyES256(jwt, publicKey)).toBe(true);
  });

  test("uses the sandbox host for sandbox tokens, and passes priority and expiration through", async () => {
    const fake = fakeAPNs({ status: 200 });
    const { apns } = await client(fake);
    await apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 5, payload, expiration: T0 + 3600.7 });

    expect(fake.requests[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${DEVICE_TOKEN}`);
    expect(fake.requests[0]?.headers["apns-priority"]).toBe("5");
    expect(fake.requests[0]?.headers["apns-expiration"]).toBe(String(T0 + 3600));
  });

  test("reuses the provider token, and signs a new one after 40 minutes", async () => {
    const fake = fakeAPNs({ status: 200 });
    const { apns, clock } = await client(fake);
    const send = () => apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 5, payload });
    const tokenOf = (index: number) => fake.requests[index]?.headers.authorization;

    await send();
    clock.now = T0 + PROVIDER_TOKEN_REFRESH_SECONDS - 1;
    await send();
    expect(tokenOf(1)).toBe(tokenOf(0));

    clock.now = T0 + 40 * 60;
    await send();
    expect(tokenOf(2)).not.toBe(tokenOf(0));
    expect(decodeJWT((tokenOf(2) ?? "").slice(7)).claims.iat).toBe(T0 + 40 * 60);
    expect(await apns.providerToken()).toBe((tokenOf(2) ?? "").slice(7));
  });

  test("requests that arrive together share one signature", async () => {
    const fake = fakeAPNs({ status: 200 });
    const { apns } = await client(fake);
    const tokens = await Promise.all([apns.providerToken(), apns.providerToken(), apns.providerToken()]);
    expect(new Set(tokens).size).toBe(1);
  });

  test("on ExpiredProviderToken it signs a new token and retries once", async () => {
    const fake = fakeAPNs({ status: 403, body: { reason: "ExpiredProviderToken" } }, { status: 200, apnsId: "second" });
    const { apns } = await client(fake);
    const result = await apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "production", priority: 10, payload });

    expect(result).toEqual({ ok: true, status: 200, apnsId: "second" });
    expect(fake.requests).toHaveLength(2);
    expect(fake.requests[1]?.headers.authorization).not.toBe(fake.requests[0]?.headers.authorization);
  });

  test("retries only once", async () => {
    const fake = fakeAPNs({ status: 403, body: { reason: "ExpiredProviderToken" } });
    const { apns } = await client(fake);
    const result = await apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "production", priority: 10, payload });
    expect(result).toMatchObject({ ok: false, status: 403, reason: "ExpiredProviderToken" });
    expect(fake.requests).toHaveLength(2);
  });

  test("surfaces APNs' reason and doesn't retry other refusals", async () => {
    const badToken = fakeAPNs({ status: 400, body: { reason: "BadDeviceToken" }, apnsId: "a1" });
    const result = await (await client(badToken)).apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 10, payload });
    expect(result).toEqual({ ok: false, status: 400, apnsId: "a1", reason: "BadDeviceToken" });
    expect(badToken.requests).toHaveLength(1);

    const gone = fakeAPNs({ status: 410, body: { reason: "Unregistered", timestamp: 1_791_899_000_000 }, apnsId: "a2" });
    const goneResult = await (await client(gone)).apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 10, payload });
    expect(goneResult).toEqual({ ok: false, status: 410, apnsId: "a2", reason: "Unregistered", timestamp: 1_791_899_000_000 });

    const invalidKey = fakeAPNs({ status: 403, body: { reason: "InvalidProviderToken" } });
    await (await client(invalidKey)).apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 10, payload });
    expect(invalidKey.requests).toHaveLength(1);
  });

  test("copes with a refusal that isn't JSON", async () => {
    const fake = fakeAPNs({ status: 500, body: undefined });
    const result = await (await client(fake)).apns.sendLiveActivity({ deviceToken: DEVICE_TOKEN, environment: "sandbox", priority: 10, payload });
    expect(result).toMatchObject({ ok: false, status: 500 });
    expect(result.reason).toBeUndefined();
  });

  test("refuses tokens that aren't hex before calling APNs", async () => {
    const fake = fakeAPNs({ status: 200 });
    const { apns } = await client(fake);
    for (const deviceToken of ["", "xyz", `${DEVICE_TOKEN}0`, "../../3/device/abcd", `${DEVICE_TOKEN} `]) {
      await expect(apns.sendLiveActivity({ deviceToken, environment: "sandbox", priority: 10, payload })).rejects.toThrow(TypeError);
    }
    expect(fake.requests).toHaveLength(0);
    expect(isDeviceToken(DEVICE_TOKEN)).toBe(true);
    expect(isDeviceToken(DEVICE_TOKEN.toUpperCase())).toBe(true);
  });

  test("an unusable key is a set-up error", async () => {
    const fake = fakeAPNs({ status: 200 });
    const apns = new ApnsClient({ teamId: "T", keyId: "K", privateKey: "nope", bundleId: "com.example.lockin" }, { fetch: fake.fetch });
    await expect(apns.providerToken()).rejects.toThrow(ApnsConfigError);
    expect(() => new ApnsClient({ teamId: "T", keyId: "K", privateKey: "x", bundleId: " " })).toThrow(ApnsConfigError);
    expect(fake.requests).toHaveLength(0);
  });
});
