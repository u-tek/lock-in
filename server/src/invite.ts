// Invite links (SPEC.md §1.7): `https://<invite host>/j/<code>` opens the app when it's installed
// (universal links, once the invite domain exists in M9), and otherwise lands here: a small page
// that offers to open Lockin and shows the code to type in after installing it from the App Store.
// Deferred deep linking is out of scope for v1.
//
//   GET /j/:code                                 -> the landing page (HTML)
//   GET /.well-known/apple-app-site-association  -> universal links for /j/*
//
// The page is public: it shows a friend code's creator's display name, or a squad code's squad name,
// and nothing else about them.
// Everything is escaped and nothing loads from anywhere else (src/http.ts sets the CSP). The page's
// shell and styles are shared with the home and policy pages (src/web.ts).

import type { Context } from "./context.ts";
import { canonicalFriendCode } from "./friends.ts";
import { escapeHTML, html, json, notFound } from "./http.ts";
import { appStoreURL, htmlDocument } from "./web.ts";

/**
 * Where "Get it on the App Store" goes until `APP_STORE_URL` is set (src/web.ts): the app's page
 * once it has an App Store ID (M9).
 */
export const APP_STORE_URL = "https://apps.apple.com/app/lockin/id0000000000";

type Landing =
  | { kind: "invite"; code: string; name: string | null }
  | { kind: "squad"; code: string; squad: string }
  | { kind: "expired" }
  | { kind: "unknown" };

// GET /j/:code

export async function invitePage(context: Context, rawCode: string): Promise<Response> {
  const code = canonicalFriendCode(rawCode);
  const invite = code === undefined ? null : await context.db.inviteCode(code);
  const store = appStoreURL(context.env) ?? APP_STORE_URL;
  if (code === undefined || invite === null) return html(landingPage({ kind: "unknown" }, store), 404);
  if (invite.expires_at !== null && invite.expires_at <= context.now) return html(landingPage({ kind: "expired" }, store), 410);
  if (invite.kind === "squad") {
    // M3: a squad code shows the squad's name (moderated like display names), nothing about its members.
    const squad = await context.db.squadById(invite.target_id);
    if (squad === null) return html(landingPage({ kind: "unknown" }, store), 404);
    return html(landingPage({ kind: "squad", code, squad: squad.name }, store));
  }
  const creator = await context.db.userById(invite.created_by);
  if (creator === null) return html(landingPage({ kind: "unknown" }, store), 404);
  return html(landingPage({ kind: "invite", code, name: creator.display_name }, store));
}

export function landingPage(landing: Landing, storeURL: string = APP_STORE_URL): string {
  const store = escapeHTML(storeURL);
  let title: string;
  let body: string;
  if (landing.kind === "invite") {
    const code = escapeHTML(landing.code);
    title = landing.name === null ? "You're invited to lock in" : `${landing.name} wants to lock in with you`;
    body = `<h1>${escapeHTML(title)}</h1>
  <p class="lede">Focus together. Your friends' timers sit right on your Lock Screen while you all work.</p>
  <a class="button" href="lockin://j/${code}">Open in Lockin</a>
  <div class="card">
    <p class="step">New to Lockin? <a href="${store}">Get it on the App Store</a>, then add your friend with this code:</p>
    <p class="code" aria-label="Friend code ${code.split("").join(" ")}">${code.slice(0, 4)} ${code.slice(4)}</p>
  </div>`;
  } else if (landing.kind === "squad") {
    const code = escapeHTML(landing.code);
    title = `Join ${landing.squad} on Lockin`;
    body = `<h1>${escapeHTML(title)}</h1>
  <p class="lede">Lock in together. Your squad's timers sit right on your Lock Screen while you all work.</p>
  <a class="button" href="lockin://j/${code}">Open in Lockin</a>
  <div class="card">
    <p class="step">New to Lockin? <a href="${store}">Get it on the App Store</a>, then join the squad with this code:</p>
    <p class="code" aria-label="Squad code ${code.split("").join(" ")}">${code.slice(0, 4)} ${code.slice(4)}</p>
  </div>`;
  } else {
    title = landing.kind === "expired" ? "This invite has expired" : "This invite link doesn't work";
    body = `<h1>${escapeHTML(title)}</h1>
  <p class="lede">Ask your friend for a new link. Their code is on the Friends screen in Lockin.</p>
  <a class="button secondary" href="${store}">Get Lockin on the App Store</a>`;
  }
  return htmlDocument({
    title: `${title} · Lockin`,
    shareTitle: title,
    description: "Lockin: focus with friends, live on your Lock Screen.",
    body,
    // An invite is for the person it was sent to, never for search results.
    noindex: true,
  });
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
