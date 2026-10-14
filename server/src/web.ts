// The web pages' shared shell: one look for the invite landing page (src/invite.ts), the home
// page and the policy and support pages (src/pages.ts). System fonts, light and dark, inline styles
// only: http.ts serves every page with a CSP under which nothing else may load.

import type { Env } from "./env.ts";
import { escapeHTML } from "./http.ts";

export interface Document {
  /** The `<title>`. */
  title: string;
  /** og:title, if it differs from the title. */
  shareTitle?: string;
  description: string;
  /** What goes in `<main>`, after the brand. */
  body: string;
  /** Adds `<meta name="robots" content="noindex">`. */
  noindex: boolean;
  /** Reading width and prose styles, for the policy pages. */
  prose?: boolean;
  /** The brand links home (not on the invite page, which is about the invite only). */
  brandLinksHome?: boolean;
}

/** The App Store page from `APP_STORE_URL`, if it's set to an https URL; undefined until then. */
export function appStoreURL(env: Env): string | undefined {
  const value = env.APP_STORE_URL?.trim() ?? "";
  if (value.length === 0) return undefined;
  try {
    return new URL(value).protocol === "https:" ? value : undefined;
  } catch {
    return undefined;
  }
}

export function htmlDocument(page: Document): string {
  const brand = `<span class="mark" aria-hidden="true"></span>Lockin`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
${page.noindex ? `<meta name="robots" content="noindex">\n` : ""}<title>${escapeHTML(page.title)}</title>
<meta name="description" content="${escapeHTML(page.description)}">
<meta property="og:title" content="${escapeHTML(page.shareTitle ?? page.title)}">
<meta property="og:description" content="${escapeHTML(page.description)}">
<meta property="og:site_name" content="Lockin">
<style>
${BASE_CSS}${page.prose === true ? PROSE_CSS : ""}</style>
</head>
<body>
<main${page.prose === true ? ` class="prose"` : ""}>
  ${page.brandLinksHome === true ? `<a class="brand" href="/">${brand}</a>` : `<div class="brand">${brand}</div>`}
  ${page.body}
</main>
</body>
</html>
`;
}

const BASE_CSS = `  :root {
    --bg: #f2f2f7; --card: #ffffff; --text: #1c1c1e; --muted: #6c6c70; --accent: #5e5ce6; --on-accent: #ffffff;
    --line: rgba(60, 60, 67, 0.18); --owner: #ffd60a; --on-owner: #1c1c1e;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #000000; --card: #1c1c1e; --text: #f2f2f7; --muted: #a1a1a6; --accent: #7d7aff; --line: rgba(84, 84, 88, 0.6); }
  }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0; min-height: 100vh; background: var(--bg); color: var(--text);
    font: 17px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    display: flex; justify-content: center;
    padding: max(32px, env(safe-area-inset-top)) 16px max(32px, env(safe-area-inset-bottom));
  }
  main { width: 100%; max-width: 420px; display: flex; flex-direction: column; gap: 20px; }
  .brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 20px; letter-spacing: -0.01em; color: inherit; text-decoration: none; }
  .mark { width: 32px; height: 32px; border-radius: 9px; background: var(--accent); position: relative; flex: none; }
  .mark::before, .mark::after { content: ""; position: absolute; top: 12px; width: 5px; height: 7px; border-radius: 3px; background: var(--on-accent); }
  .mark::before { left: 9px; } .mark::after { right: 9px; }
  h1 { margin: 12px 0 0; font-size: 30px; line-height: 1.15; letter-spacing: -0.02em; overflow-wrap: anywhere; }
  .lede { margin: 0; color: var(--muted); }
  .button {
    display: block; text-align: center; text-decoration: none; font-weight: 600; font-size: 17px;
    padding: 15px 20px; border-radius: 14px; background: var(--accent); color: var(--on-accent);
  }
  .button.secondary { background: var(--card); color: var(--accent); border: 1px solid var(--line); }
  .card { background: var(--card); border-radius: 16px; padding: 18px; border: 1px solid var(--line); }
  .step { margin: 0 0 12px; color: var(--muted); font-size: 15px; }
  .step a { color: var(--accent); font-weight: 600; text-decoration: none; }
  .code {
    margin: 0; text-align: center; font: 700 34px/1.2 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    letter-spacing: 0.14em; padding-left: 0.14em; white-space: nowrap; user-select: all; -webkit-user-select: all;
  }
  mark.owner { background: var(--owner); color: var(--on-owner); border-radius: 4px; padding: 0 3px; font-weight: 600; box-decoration-break: clone; -webkit-box-decoration-break: clone; }
  .links { margin: 8px 0 0; display: flex; flex-wrap: wrap; gap: 6px 18px; font-size: 15px; }
  .links a { color: var(--accent); text-decoration: none; font-weight: 600; }
`;

const PROSE_CSS = `  main.prose { max-width: 680px; gap: 0; }
  .prose article { overflow-wrap: break-word; }
  .prose h1 { margin: 28px 0 16px; }
  .prose h2 { margin: 36px 0 10px; font-size: 22px; line-height: 1.25; letter-spacing: -0.01em; }
  .prose h3 { margin: 26px 0 8px; font-size: 18px; line-height: 1.3; }
  .prose h4, .prose h5, .prose h6 { margin: 20px 0 6px; font-size: 17px; }
  .prose p, .prose ul, .prose ol, .prose blockquote, .prose .table { margin: 0 0 14px; }
  .prose ul, .prose ol { padding-left: 24px; }
  .prose li { margin: 4px 0; }
  .prose li > p { margin: 0 0 8px; }
  .prose a { color: var(--accent); }
  .prose code { font: 0.9em ui-monospace, "SF Mono", Menlo, Consolas, monospace; background: var(--card); border: 1px solid var(--line); border-radius: 5px; padding: 0 4px; }
  .prose hr { border: 0; border-top: 1px solid var(--line); margin: 28px 0; }
  .prose blockquote { background: var(--card); border: 1px solid var(--line); border-left: 4px solid var(--owner); border-radius: 12px; padding: 14px 16px; }
  .prose blockquote > :last-child { margin-bottom: 0; }
  .prose .table { overflow-x: auto; -webkit-overflow-scrolling: touch; }
  .prose table { border-collapse: collapse; width: 100%; min-width: 520px; font-size: 15px; background: var(--card); }
  .prose th, .prose td { border: 1px solid var(--line); padding: 8px 10px; text-align: left; vertical-align: top; }
  .prose th { font-weight: 600; }
  .prose .align-center { text-align: center; } .prose .align-right { text-align: right; }
  .draft { margin: 20px 0 0; padding: 12px 14px; border-radius: 12px; background: var(--owner); color: var(--on-owner); font-size: 15px; }
  .prose footer { margin-top: 36px; padding-top: 16px; border-top: 1px solid var(--line); }
`;
