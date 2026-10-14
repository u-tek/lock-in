-- M3: squads and rooms (docs/milestones/M3.md). 0001 and 0002 may already be applied, so they stay
-- as they are and everything new is here.

-- Each Live Activity token belongs to one APNs environment: debug builds get sandbox tokens,
-- TestFlight and App Store builds production ones, and sending a token to the other host fails
-- with 400 BadDeviceToken. A user can have several devices, so it can't be looked up from
-- `devices`; POST /sessions/:id/la-token sends it with the token
-- (docs/decisions/0005-live-activity-token-environment.md).
--
-- SQLite can't add a table CHECK with ALTER TABLE, but a CHECK on an added column may name other
-- columns, and SQLite tests it against the rows already there. So no table rebuild: a token and
-- its environment are both set or both NULL.
ALTER TABLE participants ADD COLUMN la_env TEXT
  CHECK (la_env IN ('sandbox', 'production'))
  CHECK ((la_token IS NULL) = (la_env IS NULL));

-- A member's open participation: their timer in a room is still running (focusing, on a break or
-- paused). The room sets ended_at when they finish, leave, slip, or the room ends. One at a time
-- per user (409 already_in_session), enforced here so two requests racing can't both get in.
-- Creating it fails if two open rows already exist for one user; before M3 nothing wrote to
-- participants, so there are none.
CREATE UNIQUE INDEX participants_user_open ON participants (user_id) WHERE ended_at IS NULL;

-- One open room per squad: POST /sessions joins it rather than opening a second. Two members
-- opening at the same moment can't both succeed; the loser joins the winner's room.
CREATE UNIQUE INDEX sessions_open_squad ON sessions (squad_id) WHERE status = 'open' AND squad_id IS NOT NULL;

-- "My squads" and their members are squad_members' primary key and squad_members_user (0001);
-- codes by squad are invite_codes_target, by creator invite_codes_creator; open sessions by squad
-- are sessions_open_squad above. Pet mood reads participants_user (0001).
