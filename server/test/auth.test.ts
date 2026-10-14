// Session tokens and the ids the server makes. The bearer middleware itself is tested through the
// routes (test/accounts.test.ts, test/index.test.ts).

import { expect, test } from "vitest";
import { hashToken } from "../src/auth.ts";
import { newSessionToken, newShortID } from "../src/context.ts";
import { fromBase64url } from "../src/jwt.ts";

test("tokens are stored as lowercase hex SHA-256", async () => {
  // FIPS 180-2's test vector.
  expect(await hashToken("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

test("a session token is 32 random bytes as base64url", () => {
  const requested: number[] = [];
  const token = newSessionToken((length) => {
    requested.push(length);
    return new Uint8Array(length).fill(0xfb);
  });
  expect(requested).toEqual([32]);
  expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(fromBase64url(token)).toEqual(new Uint8Array(32).fill(0xfb));

  const real = (length: number) => crypto.getRandomValues(new Uint8Array(length));
  const tokens = new Set(Array.from({ length: 100 }, () => newSessionToken(real)));
  expect(tokens.size).toBe(100);
  for (const each of tokens) expect(each).toMatch(/^[A-Za-z0-9_-]{43}$/);
});

test("short ids are 10 base62 characters, skipping bytes that would bias them", () => {
  const bytes = [248, 255, 0, 1, 61, 62, 247, 9, 10, 35, 36, 200, 100, 100, 100, 100];
  // 248 and 255 are skipped; the rest are byte % 62 in 0-9A-Za-z: 62 -> 0, 247 -> 61, 200 -> 14.
  expect(newShortID(() => Uint8Array.from(bytes))).toBe("01z0z9AZaE");
  expect(() => newShortID(() => new Uint8Array(16).fill(255))).toThrow(/over 247/);
  const real = (length: number) => crypto.getRandomValues(new Uint8Array(length));
  for (let i = 0; i < 100; i++) expect(newShortID(real)).toMatch(/^[0-9A-Za-z]{10}$/);
});
