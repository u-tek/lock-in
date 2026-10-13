// Shared test helpers: throwaway keys, JWT decoding, the shared fixtures and a fake APNs.

import { readFileSync, readdirSync } from "node:fs";

/** A throwaway P-256 key, as a .p8 file would hold it (64-character lines), and its public half. */
export async function makeKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  // Cast because the Workers types (which win over Node's) type these loosely.
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const base64 = btoa(String.fromCharCode(...pkcs8));
  const lines = base64.match(/.{1,64}/g) ?? [];
  const pem = `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey: pair.publicKey };
}

export function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

export interface DecodedJWT {
  header: Record<string, unknown>;
  claims: Record<string, unknown>;
  signature: Uint8Array<ArrayBuffer>;
  signingInput: string;
}

export function decodeJWT(jwt: string): DecodedJWT {
  const [header = "", claims = "", signature = ""] = jwt.split(".");
  const decode = (part: string) => JSON.parse(new TextDecoder().decode(fromBase64url(part))) as Record<string, unknown>;
  return { header: decode(header), claims: decode(claims), signature: fromBase64url(signature), signingInput: `${header}.${claims}` };
}

export function verifyES256(jwt: DecodedJWT, publicKey: CryptoKey): Promise<boolean> {
  return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, jwt.signature, new TextEncoder().encode(jwt.signingInput));
}

// The wire-format fixtures shared with the Swift tests.
const FIXTURES = new URL("../../fixtures/live-activity/", import.meta.url);

/** Every fixture pair in fixtures/live-activity, by name (`squad-6`, `solo`, …). */
export function fixtureNames(): string[] {
  return readdirSync(FIXTURES)
    .filter((file) => file.endsWith(".content-state.json"))
    .map((file) => file.replace(/\.content-state\.json$/, ""))
    .sort();
}

export function readFixture(name: string, part: "attributes" | "content-state"): { text: string; value: unknown } {
  const text = readFileSync(new URL(`${name}.${part}.json`, FIXTURES), "utf8");
  return { text, value: JSON.parse(text) as unknown };
}

export interface RecordedRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
}

export interface FakeResponse {
  status: number;
  body?: unknown;
  apnsId?: string;
}

/**
 * A stand-in for APNs that records each request and answers with the next response in the list
 * (the last one repeats).
 */
export function fakeAPNs(...responses: FakeResponse[]): { fetch: typeof fetch; requests: RecordedRequest[] } {
  const requests: RecordedRequest[] = [];
  const fetcher = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = new Request(input, init);
    const headers: Record<string, string> = {};
    request.headers.forEach((value, key) => {
      headers[key] = value;
    });
    requests.push({ url: request.url, method: request.method, headers, body: await request.text() });
    const next = responses[Math.min(requests.length - 1, responses.length - 1)] ?? { status: 200 };
    const body = next.body === undefined ? null : JSON.stringify(next.body);
    return new Response(body, { status: next.status, headers: { "apns-id": next.apnsId ?? `apns-${requests.length}` } });
  };
  return { fetch: fetcher as typeof fetch, requests };
}

/** 64 hex characters: the shape of a real device or activity push token. */
export const DEVICE_TOKEN = "80f1c5e2a9b34d7e8c1f0a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f";
