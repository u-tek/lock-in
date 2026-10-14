-- M4: invites and joining (docs/milestones/M4.md). 0001–0003 may already be applied, so they stay
-- as they are and everything new is here.

-- Quiet hours: "X is locking in" isn't sent to this phone between quiet_start and quiet_end,
-- minutes after midnight in the device's own `tz`. quiet_start > quiet_end crosses midnight (the
-- default, 22:00–07:00); both NULL is off. Phones registered before M4 get the default, as a new
-- one does when it leaves quietHours out of POST /devices.
--
-- As in 0003: SQLite can't add a table CHECK with ALTER TABLE, but a CHECK on an added column may
-- name the columns before it, and SQLite tests it against the rows already there. So the pair rule
-- sits on quiet_end, added second.
ALTER TABLE devices ADD COLUMN quiet_start INTEGER DEFAULT 1320
  CHECK (quiet_start BETWEEN 0 AND 1439);
ALTER TABLE devices ADD COLUMN quiet_end INTEGER DEFAULT 420
  CHECK (quiet_end BETWEEN 0 AND 1439)
  CHECK ((quiet_start IS NULL) = (quiet_end IS NULL))
  CHECK (quiet_start <> quiet_end);

-- Every "X is locking in" a member was sent: the log the limits read (SPEC.md §7, App Review
-- 4.5.3). One row per recipient alerted, however many of their phones got it. At most one per squad
-- per recipient every 30 minutes and six per recipient in any 24 hours; the Worker trims rows over
-- 2 days old as it sends.
--
-- No foreign keys to squads or sessions: it's a short-lived log, and a squad or session that's gone
-- simply stops mattering. The people in it go with their accounts.
CREATE TABLE alerts (
  recipient_id TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  squad_id     TEXT    NOT NULL,
  sender_id    TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  session_id   TEXT    NOT NULL,
  sent_at      INTEGER NOT NULL
);
-- Both limits: a recipient's rows in a time range (at most a dozen in two days), filtered by squad
-- for the 30-minute one.
CREATE INDEX alerts_recipient ON alerts (recipient_id, sent_at);
-- The trim, and deleting an account that sent alerts.
CREATE INDEX alerts_sent ON alerts (sent_at);
CREATE INDEX alerts_sender ON alerts (sender_id);

-- "Did this opener open another room in the squad in the last 10 minutes?" is sessions_squad
-- (squad_id, created_at) from 0001.
