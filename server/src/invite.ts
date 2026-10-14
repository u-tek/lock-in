// Invite links (SPEC.md §1.7): `https://<invite host>/j/<code>` opens the app when it's installed
// (universal links, once the invite domain exists in M9), and otherwise lands here: a small page
// that offers to open Lockin and shows the code to type in after installing it from the App Store.
// Deferred deep linking is out of scope for v1.
//
//   GET /j/:code                                 -> the landing page (HTML)
//   GET /.well-known/apple-app-site-association  -> universal links for /j/*
//
// The page is public: it shows the code's creator's display name and nothing else about them.
// Everything is escaped and nothing loads from anywhere else (src/http.ts sets the CSP).

import type { Context } from "./context.ts";
import { canonicalFriendCode } from "./friends.ts";
import { escapeHTML, html, json, notFound } from "./http.ts";

/** M9: the app's App Store page once it has one. */
export const APP_STORE_URL = "https://apps.apple.com/app/lockin/id0000000000";

type Landing =
  | { kind: "invite"; code: string; name: string | null }
  | { kind: "expired" }
  | { kind: "unknown" };

// GET /j/:code

export async function invitePage(context: Context, rawCode: string): Promise<Response> {
  const code = canonicalFriendCode(rawCode);
  const invite = code === undefined ? null : await context.db.inviteCode(code);
  if (code === undefined || invite === null || invite.kind !== "friend") return html(landingPage({ kind: "unknown" }), 404);
  if (invite.expires_at !== null && invite.expires_at <= context.now) return html(landingPage({ kind: "expired" }), 410);
  const creator = await context.db.userById(invite.created_by);
  if (creator === null) return html(landingPage({ kind: "unknown" }), 404);
  return html(landingPage({ kind: "invite", code, name: creator.display_name }));
}

export function landingPage(landing: Landing): string {
  let title: string;
  let body: string;
  if (landing.kind === "invite") {
    const code = escapeHTML(landing.code);
    title = landing.name === null ? "You're invited to lock in" : `${landing.name} wants to lock in with you`;
    body = `
      <h1>${escapeHTML(title)}</h1>
      <p class="lede">Focus together. Your friends' timers sit right on your Lock Screen while you all work.</p>
      <a class="button" href="lockin://j/${code}">Open in Lockin</a>
      <div class="card">
        <p class="step">New to Lockin? <a href="${escapeHTML(APP_STORE_URL)}">Get it on the App Store</a>, then add your friend with this code:</p>
        <p class="code" aria-label="Friend code ${code.split("").join(" ")}">${code}</p>
      </div>`;
  } else {
    title = landing.kind === "expired" ? "This invite has expired" : "This invite link doesn't work";
    body = `
      <h1>${escapeHTML(title)}</h1>
      <p class="lede">Ask your friend for a new link. Their code is on the Friends screen in Lockin.</p>
      <a class="button secondary" href="${escapeHTML(APP_STORE_URL)}">Get Lockin on the App Store</a>`;
  }
  const description = "Lockin: focus with friends, live on your Lock Screen.";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<meta name="robots" content="noindex">
<title>${escapeHTML(title)} · Lockin</title>
<meta property="og:title" content="${escapeHTML(title)}">
<meta property="og:description" content="${escapeHTML(description)}">
<meta property="og:site_name" content="Lockin">
<style>
  :root {
    --bg: #f2f2f7; --card: #ffffff; --text: #1c1c1e; --muted: #6c6c70; --accent: #5e5ce6; --on-accent: #ffffff;
    --line: rgba(60, 60, 67, 0.18);
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
  .brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 20px; letter-spacing: -0.01em; }
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
    letter-spacing: 0.18em; padding-left: 0.18em; user-select: all; -webkit-user-select: all;
  }
</style>
</head>
<body>
<main>
  <div class="brand"><span class="mark" aria-hidden="true"></span>Lockin</div>
  ${body.trim()}
</main>
</body>
</html>
`;
}

// GET /.well-known/apple-app-site-association

/**
 * Universal links for invites: `/j/*` opens the app (`<team id>.<bundle id>`). Apple fetches this
 * through its CDN from the invite domain (M9). Without APNS_TEAM_ID there's no app to name: 404.
 */
export function appSiteAssociation(context: Context): Response {
  const teamId = context.env.APNS_TEAM_ID?.trim() ?? "";
  const bundleId = context.env.APNS_BUNDLE_ID?.trim() ?? "";
  if (teamId.length === 0 || bundleId.length === 0) return notFound();
  return json(
    {
      applinks: {
        details: [{ appIDs: [`${teamId}.${bundleId}`], components: [{ "/": "/j/*", comment: "Friend invites" }] }],
      },
    },
    200,
    { "content-type": "application/json", "cache-control": "public, max-age=3600" },
  );
}
