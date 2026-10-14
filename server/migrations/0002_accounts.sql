-- M2: accounts and friends (docs/milestones/M2.md). 0001 may already be applied, so it stays as it
-- is and everything new is here.

-- The app's sessions. The bearer token is 32 random bytes the app keeps in the Keychain; only its
-- SHA-256 (lowercase hex) is stored, so a copy of the database can't sign anyone in.
CREATE TABLE auth_tokens (
  token_hash   TEXT    PRIMARY KEY CHECK (length(token_hash) = 64),
  user_id      TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  -- Updated at most hourly (src/auth.ts), so a busy app doesn't write on every request.
  last_used_at INTEGER NOT NULL
);
-- Deleting a user cascades here.
CREATE INDEX auth_tokens_user ON auth_tokens (user_id);

-- Sign in with Apple's refresh token, from swapping the app's authorisation code (src/appleAuth.ts).
-- Kept only so account deletion can revoke it, as Apple requires. NULL without the SIWA_* secrets.
ALTER TABLE users ADD COLUMN apple_refresh_token TEXT;

-- POST /reports takes an optional note for whoever reviews it. It goes to moderators only, never to
-- another user.
ALTER TABLE reports ADD COLUMN note TEXT CHECK (note IS NULL OR length(note) BETWEEN 1 AND 500);

-- "My current friend code" (POST /friends/code) is invite_codes_creator plus a filter on kind and
-- expiry; the creator's handful of rows doesn't need more.
