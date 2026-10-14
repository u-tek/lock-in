// The web pages (src/pages.ts): the home page and the policy pages made from docs/launch/.

import { readFileSync } from "node:fs";
import { beforeEach, describe, expect, test } from "vitest";
import { PAGE_CSP } from "../src/http.ts";
import { APP_STORE_URL } from "../src/invite.ts";
import { safeHref } from "../src/markdown.ts";
import { markdownDocument } from "../src/pages.ts";
import { type TestApp, read, testApp } from "./app.ts";

let app: TestApp;

beforeEach(async () => {
  app = await testApp();
});

const page = async (path: string, method = "GET") => {
  const response = await app.request(method, path);
  return { status: response.status, headers: response.headers, text: await response.text() };
};

const draft = (file: string) => readFileSync(new URL(`../../docs/launch/${file}`, import.meta.url), "utf8");

/** What every page shares with the invite landing page: the CSP and nothing loaded from elsewhere. */
function expectLockedDown(headers: Headers, text: string) {
  expect(headers.get("content-type")).toBe("text/html; charset=utf-8");
  expect(headers.get("content-security-policy")).toBe(PAGE_CSP);
  expect(PAGE_CSP).toContain("default-src 'none'");
  expect(headers.get("referrer-policy")).toBe("no-referrer");
  expect(headers.get("x-content-type-options")).toBe("nosniff");
  expect(text).toMatch(/^<!doctype html>/);
  expect(text).toContain('<meta name="viewport"');
  expect(text).not.toMatch(/<script|<link|<img|<iframe|<object|<embed|src=|url\(|@import|\son[a-z]+=/i);
  for (const [, href] of text.matchAll(/href="([^"]*)"/g)) expect(safeHref(href!.replace(/&#38;/g, "&")), href).not.toBeNull();
}

describe("GET /privacy, /terms, /support", () => {
  for (const [path, file, title] of [
    ["/privacy", "privacy-policy.md", "Lockin Privacy Policy"],
    ["/terms", "terms.md", "Lockin Terms of Use"],
    ["/support", "support.md", "Lockin Support"],
  ] as const) {
    test(`${path} is ${file}, with its title, under the CSP`, async () => {
      const { status, headers, text } = await page(path);
      expect(status).toBe(200);
      expectLockedDown(headers, text);
      expect(text).toContain(`<title>${title}</title>`);
      expect(text).toContain(`<h1 id="${title.toLowerCase().replace(/ /g, "-")}">${title}</h1>`);
      expect(text.split("<title>")).toHaveLength(2);
      expect(headers.get("cache-control")).toBe("public, max-age=300");
      // The footer reaches the other pages.
      for (const other of ["/", "/support", "/privacy", "/terms"]) expect(text).toContain(`href="${other}"`);
    });

    test(`${path} is marked as a draft and not indexed while it has placeholders`, async () => {
      const placeholders = draft(file).match(/\[OWNER:/g)?.length ?? 0;
      // The drafts aren't finished yet: if this fails, they are, and the test below takes over.
      expect(placeholders).toBeGreaterThan(0);
      const { headers, text } = await page(path);
      expect(headers.get("x-robots-tag")).toBe("noindex");
      expect(text).toContain('<meta name="robots" content="noindex">');
      expect(text).toContain(`<strong>Draft.</strong> ${placeholders} placeholders are still to fill in`);
      expect(text).toContain('<mark class="owner">[OWNER:');
    });

    test(`HEAD ${path} answers like GET, without the page`, async () => {
      const get = await page(path);
      const head = await page(path, "HEAD");
      expect(head.status).toBe(200);
      expect(head.text).toBe("");
      expect(Object.fromEntries(head.headers)).toEqual(Object.fromEntries(get.headers));
    });
  }

  test("a finished page is indexed and has no draft banner", () => {
    const { document, drafts } = markdownDocument("# Lockin Privacy Policy\n\nAll done. Email <privacy@lockin.app>.", "Fallback", "About privacy.");
    expect(drafts).toBe(0);
    expect(document).not.toContain("noindex");
    expect(document).not.toContain("Draft.");
    expect(document).toContain('<a href="mailto:privacy@lockin.app">privacy@lockin.app</a>');

    const untitled = markdownDocument("Just text with [OWNER: one].", "Fallback title", "About.");
    expect(untitled.drafts).toBe(1);
    expect(untitled.document).toContain("<title>Fallback title</title>");
    expect(untitled.document).toContain("1 placeholder is still to fill in");
    expect(untitled.document).toContain('<meta name="robots" content="noindex">');
  });

  test("other methods and paths aren't pages", async () => {
    for (const [method, path] of [
      ["POST", "/privacy"],
      ["DELETE", "/terms"],
      ["GET", "/privacy.md"],
      ["GET", "/support/"],
      ["GET", "/docs/launch/privacy-policy.md"],
    ]) {
      expect((await app.request(method!, path!)).status, `${method} ${path}`).toBe(404);
    }
  });
});

describe("GET /", () => {
  test("the name, one line and the App Store link's placeholder until APP_STORE_URL is set", async () => {
    const { status, headers, text } = await page("/");
    expect(status).toBe(200);
    expectLockedDown(headers, text);
    expect(text).toContain("<title>Lockin</title>");
    expect(text).toContain("<h1>Focus with friends, live on your Lock Screen.</h1>");
    expect(text).toContain('<mark class="owner">[OWNER: App Store link]</mark>');
    expect(text).not.toContain("apps.apple.com");
    expect(headers.get("x-robots-tag")).toBe("noindex");
    for (const path of ["/support", "/privacy", "/terms"]) expect(text).toContain(`href="${path}"`);
  });

  test("links to the App Store once APP_STORE_URL is set, and may be indexed", async () => {
    const store = "https://apps.apple.com/app/lockin/id1234567890";
    app.env.APP_STORE_URL = ` ${store}\n`;
    const { headers, text } = await page("/");
    expect(text).toContain(`<a class="button" href="${store}">Get Lockin on the App Store</a>`);
    expect(text).not.toContain("[OWNER:");
    expect(text).not.toContain("noindex");
    expect(headers.get("x-robots-tag")).toBeNull();
    expect(headers.get("content-security-policy")).toBe(PAGE_CSP);
  });

  test("ignores an APP_STORE_URL that isn't https", async () => {
    for (const value of ["javascript:alert(1)", "http://apps.apple.com/app/id1", "apps.apple.com/app/id1", ""]) {
      app.env.APP_STORE_URL = value;
      const { text } = await page("/");
      expect(text, value).toContain("[OWNER: App Store link]");
      expect(text, value).not.toContain(`href="${value}"`);
    }
  });

  test("HEAD / has no body", async () => {
    const head = await page("/", "HEAD");
    expect(head.status).toBe(200);
    expect(head.text).toBe("");
    expect(head.headers.get("content-security-policy")).toBe(PAGE_CSP);
  });
});

describe("the invite page's App Store link", () => {
  test("follows APP_STORE_URL once it's set", async () => {
    const ava = await app.user("ava", "Ava");
    const code = (await read(await app.request("POST", "/friends/code", { token: ava.token }))).body.code as string;
    expect((await page(`/j/${code}`)).text).toContain(`href="${APP_STORE_URL}"`);
    app.env.APP_STORE_URL = "https://apps.apple.com/app/lockin/id1234567890";
    const { text } = await page(`/j/${code}`);
    expect(text).toContain('href="https://apps.apple.com/app/lockin/id1234567890"');
    expect(text).not.toContain(APP_STORE_URL);
    // Invites are never indexed, finished or not.
    expect(text).toContain('<meta name="robots" content="noindex">');
  });
});
