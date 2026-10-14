-- M5: the squad pet, streaks, the weekly leaderboard and coins (docs/milestones/M5.md). 0001–0004
-- may already be applied, so they stay as they are and everything new is here.

-- The squad's time zone (IANA name): its days, streak and Monday reset (M5 "Squad time zone"). The
-- creator's phone's zone when the squad is made, and the owner's whenever they register a phone in
-- a new one. Existing squads take their owner's most recently registered phone's zone, else UTC.
ALTER TABLE squads ADD COLUMN tz TEXT NOT NULL DEFAULT 'UTC';
UPDATE squads SET tz = coalesce(
  (SELECT d.tz FROM devices d WHERE d.user_id = squads.owner_id ORDER BY d.updated_at DESC, d.id LIMIT 1),
  'UTC');

-- When the egg hatched: the first time two members finished in one of its rooms. NULL while it's an
-- egg. pet_species is set from the start now (so the egg has its colour); this is what says
-- whether it has hatched.
ALTER TABLE squads ADD COLUMN hatched_at INTEGER;

-- The latest slip or early leave in one of the squad's rooms: the pet is sad for 30 minutes after.
ALTER TABLE squads ADD COLUMN last_sad_at INTEGER;

-- Whether the coins and items earned signed out were brought over (POST /me/coins/import). Only
-- ever 0 or 1, so adding 1 to a 1 fails the CHECK: that's how the import happens at most once,
-- whatever races it.
ALTER TABLE users ADD COLUMN coins_imported INTEGER NOT NULL DEFAULT 0 CHECK (coins_imported IN (0, 1));

-- Every timer that stopped in a room (finished, left early or slipped), with what it earned. Written
-- by the room in the same transaction as the coins and XP it credits, and those updates only apply
-- while this row doesn't exist yet: a room that writes again after a failure (or a write that
-- succeeded without the room hearing so) never credits anything twice.
--
-- Also what streaks (finished sessions of 20+ minutes per member per day) and the weekly leaderboard
-- (minutes per member per week) read: a participants row holds only someone's latest timer in a
-- room, and they can finish, join again and leave in the same room.
CREATE TABLE focus_log (
  session_id  TEXT    NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
  user_id     TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  -- The timer's start: participants.started_at as it was. With the session and user, the key.
  started_at  REAL    NOT NULL,
  -- When it stopped (REAL Unix seconds, like participants). The day and week it counts in.
  ended_at    REAL    NOT NULL,
  -- The squad whose room it was; NULL for solo sessions (or once the squad is gone).
  squad_id    TEXT    REFERENCES squads (id) ON DELETE SET NULL,
  focused_sec INTEGER NOT NULL CHECK (focused_sec >= 0),
  -- 1 when the timer ran out (done), 0 when they left early or slipped.
  completed   INTEGER NOT NULL CHECK (completed IN (0, 1)),
  -- What was credited: coins to users.coins, XP to the squad's pet_xp.
  coins       INTEGER NOT NULL CHECK (coins >= 0),
  xp          INTEGER NOT NULL CHECK (xp >= 0),
  PRIMARY KEY (session_id, user_id, started_at),
  CHECK (ended_at >= started_at)
);
-- Finished sessions (and minutes) per user per day or week: streaks, moods and the leaderboard.
CREATE INDEX focus_log_user ON focus_log (user_id, ended_at);
CREATE INDEX focus_log_squad ON focus_log (squad_id);
