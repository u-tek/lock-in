// The public web pages (M9 launch checklist §2): a one-screen home page, and the privacy policy,
// terms of use and support page that App Store Connect and the app link to.
//
//   GET /          -> the home page: the name, one line, the App Store link
//   GET /privacy   -> docs/launch/privacy-policy.md
//   GET /terms     -> docs/launch/terms.md
//   GET /support   -> docs/launch/support.md
//
// (HEAD too, for link checkers.) The three drafts in docs/launch/ are bundled as text at build
// time (the `[[rules]]` in wrangler.toml; vitest.config.ts loads them the same way), so the pages
// are always the drafts as committed: edit the Markdown and deploy. They render with
// src/markdown.ts in the invite page's shell (src/web.ts), under the same CSP.
//
// While a page still has an `[OWNER: …]` placeholder it says so at the top, every placeholder is
// highlighted, and it's served with `x-robots-tag: noindex`, so a draft can't be found by search or
// pass for finished. The home page counts as a draft until `APP_STORE_URL` is set.

import privacyPolicy from "../../docs/launch/privacy-policy.md";
import support from "../../docs/launch/support.md";
import terms from "../../docs/launch/terms.md";
import type { Context } from "./context.ts";
import { escapeHTML, html } from "./http.ts";
import { placeholderCount, renderMarkdown } from "./markdown.ts";
import { appStoreURL, htmlDocument } from "./web.ts";

/** The pages made from Markdown, by path. */
export const MARKDOWN_PAGES = {
  "/privacy": { source: privacyPolicy, fallbackTitle: "Lockin Privacy Policy", description: "What Lockin collects, why, where it's kept and how to delete it." },
  "/terms": { source: terms, fallbackTitle: "Lockin Terms of Use", description: "The terms for using Lockin and Lockin Plus." },
  "/support": { source: support, fallbackTitle: "Lockin Support", description: "Help with Lockin: Live Activities, friends and squads, Plus, your account and safety." },
} as const;

export type MarkdownPath = keyof typeof MARKDOWN_PAGES;

/** Cache-friendly but quick to change: a deploy shows up within five minutes. */
const CACHE = "public, max-age=300";

const FOOTER = `<footer><nav class="links" aria-label="Lockin">
    <a href="/">Home</a><a href="/support">Support</a><a href="/privacy">Privacy Policy</a><a href="/terms">Terms of Use</a>
  </nav></footer>`;

/** A policy page from its Markdown, and how many placeholders it still has. */
export function markdownDocument(source: string, fallbackTitle: string, description: string): { document: string; drafts: number } {
  const { html: article, title } = renderMarkdown(source);
  const drafts = placeholderCount(source);
  const banner =
    drafts === 0
      ? ""
      : `<p class="draft" role="note"><strong>Draft.</strong> ${drafts} ${drafts === 1 ? "placeholder is" : "placeholders are"} still to fill in (highlighted below), so search engines are asked not to index this page yet.</p>\n  `;
  const document = htmlDocument({
    title: title ?? fallbackTitle,
    description,
    body: `${banner}<article>\n${article}\n</article>\n  ${FOOTER}`,
    noindex: drafts > 0,
    prose: true,
    brandLinksHome: true,
  });
  return { document, drafts };
}

// Rendered once per isolate: the sources never change while it runs.
const rendered = new Map<MarkdownPath, { document: string; drafts: number }>();

// GET /privacy, /terms, /support

export async function markdownPage(context: Context, path: MarkdownPath): Promise<Response> {
  let page = rendered.get(path);
  if (page === undefined) {
    const { source, fallbackTitle, description } = MARKDOWN_PAGES[path];
    page = markdownDocument(source, fallbackTitle, description);
    rendered.set(path, page);
  }
  return withoutBodyForHead(context, html(page.document, 200, { index: page.drafts === 0, cacheControl: CACHE }));
}

// GET /

export async function homePage(context: Context): Promise<Response> {
  const store = appStoreURL(context.env);
  const download =
    store === undefined
      ? `<p class="card">Get it on the App Store: <mark class="owner">[OWNER: App Store link]</mark> (set <code>APP_STORE_URL</code> on the Worker)</p>`
      : `<a class="button" href="${escapeHTML(store)}">Get Lockin on the App Store</a>`;
  const document = htmlDocument({
    title: "Lockin",
    shareTitle: "Lockin: focus with friends",
    description: "A focus timer you share with friends: everyone's live timer sits in your Dynamic Island and on your Lock Screen.",
    body: `<h1>Focus with friends, live on your Lock Screen.</h1>
  ${download}
  <nav class="links" aria-label="Lockin">
    <a href="/support">Support</a><a href="/privacy">Privacy Policy</a><a href="/terms">Terms of Use</a>
  </nav>`,
    noindex: store === undefined,
  });
  return withoutBodyForHead(context, html(document, 200, { index: store !== undefined, cacheControl: CACHE }));
}

/** A HEAD request gets the same status and headers, and no body. */
function withoutBodyForHead(context: Context, response: Response): Response {
  if (context.request.method !== "HEAD") return response;
  return new Response(null, { status: response.status, headers: response.headers });
}
