// The invite landing page (GET /j/:code) and universal links (the apple-app-site-association file).

import { beforeEach, describe, expect, test, vi } from "vitest";
import { FRIEND_CODE_LIFETIME_SECONDS } from "../src/friends.ts";
import { APP_STORE_URL } from "../src/invite.ts";
import { BUNDLE_ID, type SignedIn, T0, TEAM_ID, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;
let ava: SignedIn;
let code: string;

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => {});
  app = await testApp();
  ava = await app.user("ava", "Ava");
  code = (await read(await app.request("POST", "/friends/code", { token: ava.token }))).body.code;
});

/** The page, with no bearer token: it's public. */
const page = async (path: string) => {
  const response = await app.request("GET", path);
  return { status: response.status, headers: response.headers, text: await response.text() };
};

describe("GET /j/:code", () => {
  test("invites you to lock in with whoever made the code", async () => {
    const { status, headers, text } = await page(`/j/${code}`);
    expect(status).toBe(200);
    expect(headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(text).toMatch(/^<!doctype html>/);
    expect(text).toContain('<meta name="viewport"');
    expect(text).toContain("Lockin");
    expect(text).toContain("<h1>Ava wants to lock in with you</h1>");
    expect(text).toContain(`<meta property="og:title" content="Ava wants to lock in with you">`);
    expect(text).toContain(`<a class="button" href="lockin://j/${code}">Open in Lockin</a>`);
    // Split in two for reading, as the app shows it; the app drops the space when it's typed in.
    expect(text).toContain(`<p class="code" aria-label="Friend code ${code.split("").join(" ")}">${code.slice(0, 4)} ${code.slice(4)}</p>`);
    expect(text).toContain(`href="${APP_STORE_URL}"`);
  });

  test("loads nothing from anywhere else", async () => {
    const { text } = await page(`/j/${code}`);
    expect(text).not.toMatch(/<script|<link|<img|<iframe|src=|url\(|@import/i);
    const links = [...text.matchAll(/href="([^"]*)"/g)].map((match) => match[1]);
    expect(links).toEqual([`lockin://j/${code}`, APP_STORE_URL]);
  });

  test("ignores the code's case, spaces and dashes", async () => {
    for (const typed of [code.toLowerCase(), `${code.slice(0, 4)}-${code.slice(4)}`, `${code.slice(0, 4)}%20${code.slice(4)}`]) {
      expect((await page(`/j/${typed}`)).text, typed).toContain(`href="lockin://j/${code}"`);
    }
  });

  test("escapes a hostile display name", async () => {
    for (const name of ["<script>", `"'><b>&`, "</title>", "`${x}`", "&lt;b&gt;"]) {
      const patched = await read(await app.request("PATCH", "/me", { token: ava.token, body: { displayName: name } }));
      expect(patched.status, name).toBe(200);
      const { text } = await page(`/j/${code}`);
      // The name shows up only as entities: no raw markup characters, no bare ampersands.
      const shown = [/<title>(.*) wants to lock in/.exec(text)?.[1], /<h1>(.*) wants to lock in/.exec(text)?.[1], /og:title" content="(.*) wants/.exec(text)?.[1]];
      for (const part of shown) {
        expect(part, name).toBeDefined();
        expect(part, name).not.toMatch(/[<>"'`]|&(?!#\d+;)/);
      }
      expect(text).not.toMatch(/<script|<b>/);
      expect(text.split("</title>")).toHaveLength(2);
    }
    await app.request("PATCH", "/me", { token: ava.token, body: { displayName: `"'><b>&` } });
    const { text } = await page(`/j/${code}`);
    expect(text).toContain("<h1>&#34;&#39;&#62;&#60;b&#62;&#38; wants to lock in with you</h1>");
    expect(text).toContain('content="&#34;&#39;&#62;&#60;b&#62;&#38; wants to lock in with you"');
  });

  test("without a display name, the invite is from a friend", async () => {
    const newcomer = await app.signIn("sub.newcomer");
    const theirs = (await read(await app.request("POST", "/friends/code", { token: newcomer.token }))).body.code;
    const { status, text } = await page(`/j/${theirs}`);
    expect(status).toBe(200);
    expect(text).toContain("<h1>You&#39;re invited to lock in</h1>");
    expect(text).toContain(`href="lockin://j/${theirs}"`);
  });

  test("says when a code has expired or doesn't exist, without offering it", async () => {
    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS;
    const expired = await page(`/j/${code}`);
    expect(expired.status).toBe(410);
    expect(expired.text).toContain("This invite has expired");
    expect(expired.text).not.toContain(code);
    expect(expired.text).not.toContain("Ava");

    for (const path of ["/j/ZZZZZZZZ", "/j/nope", "/j/%3Cscript%3E", "/j/%E0%A4%A"]) {
      const unknown = await page(path);
      expect(unknown.status, path).toBe(404);
      expect(unknown.headers.get("content-type")).toBe("text/html; charset=utf-8");
      expect(unknown.text).toContain("This invite link doesn&#39;t work");
      expect(unknown.text).not.toContain("<script");
    }
  });
});

describe("GET /.well-known/apple-app-site-association", () => {
  test("opens /j/* links in the app", async () => {
    const response = await app.request("GET", "/.well-known/apple-app-site-association");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(await response.json()).toEqual({
      applinks: { details: [{ appIDs: [`${TEAM_ID}.${BUNDLE_ID}`], components: [{ "/": "/j/*", comment: "Friend invites" }] }] },
    });
  });

  test("trims the team ID, and is a 404 without one", async () => {
    app.env.APNS_TEAM_ID = ` ${TEAM_ID}\r\n`;
    expect(((await read(await app.request("GET", "/.well-known/apple-app-site-association"))).body as any).applinks.details[0].appIDs).toEqual([
      `${TEAM_ID}.${BUNDLE_ID}`,
    ]);
    app.env.APNS_TEAM_ID = undefined;
    expect((await app.request("GET", "/.well-known/apple-app-site-association")).status).toBe(404);
  });
});
