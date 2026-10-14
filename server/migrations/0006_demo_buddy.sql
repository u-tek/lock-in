-- Demo Buddy, the App Review bot (docs/launch/app-review-notes.md §3, SPEC.md §7). 0001–0005 may
-- already be applied, so they stay as they are and everything new is here.

-- Accounts the server runs itself. A bot never signs in (no apple_sub, so no Sign in with Apple
-- token can reach it), earns no coins, isn't counted in a squad's streak, mood or leaderboard, and
-- GET /squads labels it (`isBot`).
ALTER TABLE users ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0 CHECK (is_bot IN (0, 1));

-- A Review Squad: made by redeeming the review code (DEMO_BUDDY_CODE), with the redeemer and Demo
-- Buddy in it. It doesn't count against anyone's squad limit, and it's deleted when its last person
-- (not bot) leaves.
ALTER TABLE squads ADD COLUMN review INTEGER NOT NULL DEFAULT 0 CHECK (review IN (0, 1));

-- Demo Buddy itself. Its id, name and Lockling are also constants in src/demoBuddy.ts (a test checks
-- they match). The handle and both words of the name are reserved in fixtures/moderation/words.json,
-- so nobody else can take or copy them; this insert is the only way past that filter.
INSERT INTO users (id, apple_sub, handle, display_name, avatar_code, coins, created_at, is_bot)
VALUES ('DemoBuddy0', NULL, 'demobuddy', 'Demo Buddy', 'b2.c5.e4.h3', 0, 1792000000, 1);

-- One row per redemption of the review code: the global limit (10 an hour) reads it. Nothing about
-- who redeemed; trimmed to a day as codes are redeemed.
CREATE TABLE review_redemptions (
  at INTEGER NOT NULL
);
CREATE INDEX review_redemptions_at ON review_redemptions (at);
