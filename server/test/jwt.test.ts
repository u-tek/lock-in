import { describe, expect, test } from "vitest";
import { base64url, importP8, pemToPKCS8, signES256 } from "../src/jwt.ts";
import { decodeJWT, makeKey, verifyES256 } from "./helpers.ts";

describe("signES256", () => {
  test("signs a JWT that verifies with the key's public half", async () => {
    const { pem, publicKey } = await makeKey();
    const jwt = await signES256({ kid: "KEY1234567" }, { iss: "TEAM123456", iat: 1_791_900_000 }, await importP8(pem));

    const decoded = decodeJWT(jwt);
    // Exactly what APNs documents: alg and kid in the header, iss and iat in the claims.
    expect(decoded.header).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decoded.claims).toEqual({ iss: "TEAM123456", iat: 1_791_900_000 });
    // Raw r||s, which is what JWS wants: 64 bytes for P-256, not a longer DER sequence.
    expect(decoded.signature.length).toBe(64);
    expect(await verifyES256(decoded, publicKey)).toBe(true);
  });

  test("a tampered token doesn't verify", async () => {
    const { pem, publicKey } = await makeKey();
    const jwt = await signES256({ kid: "K" }, { iss: "T", iat: 1 }, await importP8(pem));
    const decoded = decodeJWT(jwt);
    decoded.signingInput = `${decoded.signingInput.split(".")[0]}.${base64url(JSON.stringify({ iss: "T", iat: 2 }))}`;
    expect(await verifyES256(decoded, publicKey)).toBe(false);
  });
});

describe("pemToPKCS8", () => {
  test("survives what Windows and secret stores do to a .p8 file", async () => {
    const { pem, publicKey } = await makeKey();
    const variants = [
      pem,
      pem.replace(/\n/g, "\r\n"), // Get-Content -Raw on Windows
      `﻿${pem}`, // a byte order mark
      pem.replace(/\n/g, "\\n"), // flattened to one line with literal \n
      `  ${pem}\n\n`,
    ];
    for (const variant of variants) {
      const jwt = await signES256({ kid: "K" }, { iss: "T", iat: 1 }, await importP8(variant));
      expect(await verifyES256(decodeJWT(jwt), publicKey)).toBe(true);
    }
  });

  test("refuses things that aren't a PKCS#8 key, without quoting them", () => {
    const secret = "not-a-key-but-maybe-a-secret";
    expect(() => pemToPKCS8(secret)).toThrow("The private key isn't a PEM .p8 file");
    expect(() => pemToPKCS8(secret)).not.toThrow(secret);
    expect(() => pemToPKCS8("")).toThrow("isn't a PEM .p8 file");
    expect(() => pemToPKCS8("-----BEGIN EC PRIVATE KEY-----\nAAAA\n-----END EC PRIVATE KEY-----")).toThrow("PKCS#8");
  });

  test("base64url has no padding or URL-unsafe characters", () => {
    expect(base64url(new Uint8Array([0xfb, 0xff, 0xfe]))).toBe("-__-");
    expect(base64url("a")).toBe("YQ");
  });
});
