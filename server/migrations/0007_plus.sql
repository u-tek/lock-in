-- M7: Lockin Plus end to end (docs/milestones/M7.md): RevenueCat's webhook, Squad Boost's pet
-- accessories and streak freezes. 0001–0006 may already be applied, so they stay as they are and
-- everything new is here.

-- RevenueCat's `event_timestamp_ms` of the last purchase event applied to users.plus_until (or the
-- time of the last POST /me/plus/refresh). An event older than that arrived late and is ignored, so
-- an old EXPIRATION can't undo a newer RENEWAL.
ALTER TABLE users ADD COLUMN plus_event_ms INTEGER;

-- RevenueCat events already handled: the webhook is retried, and the same event twice must count
-- once. Kept 90 days.
CREATE TABLE revenuecat_events (
  id          TEXT    PRIMARY KEY,
  type        TEXT    NOT NULL,
  received_at INTEGER NOT NULL
);
CREATE INDEX revenuecat_events_received ON revenuecat_events (received_at);

-- Squad Boost: the pet accessory a member of a boosted squad picked (`pet.<n>` in
-- fixtures/shop/catalogue.json). Kept when the boost lapses; shown again when it's back.
ALTER TABLE squads ADD COLUMN pet_accessory INTEGER CHECK (pet_accessory BETWEEN 1 AND 99);

-- Streak freezes: a day a squad missed, filled with a Plus member's freeze (2 per member per
-- calendar month) so the streak didn't break. One per squad per day; `day` is the squad's
-- calendar day, like streak_last_day. A member who deletes their account leaves the frozen day
-- in place, without them.
CREATE TABLE streak_freezes (
  squad_id TEXT    NOT NULL REFERENCES squads (id) ON DELETE CASCADE,
  day      TEXT    NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  user_id  TEXT    REFERENCES users (id) ON DELETE SET NULL,
  used_at  INTEGER NOT NULL,
  PRIMARY KEY (squad_id, day)
);
-- "How many has this member used this month?"
CREATE INDEX streak_freezes_user ON streak_freezes (user_id, day);
