-- Analytics counts without a provider (docs/decisions/0010-analytics-provider.md, proposed): POST
-- /metrics adds a phone's integer counts to the day's totals. 0001–0007 may already be applied, so
-- they stay as they are and everything new is here.
--
-- Nothing here can name a person, an account, a device or an IP address: a row is a UTC day, an
-- event name from fixtures/analytics/events.json and a running total. The tables reference nothing,
-- and account deletion has nothing to remove from them.

CREATE TABLE metrics_daily (
  day   TEXT    NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  event TEXT    NOT NULL CHECK (length(event) BETWEEN 3 AND 64),
  count INTEGER NOT NULL CHECK (count >= 0),
  PRIMARY KEY (day, event)
);

-- How many batches arrived each UTC day. The daily cap reads it (src/metrics.ts), so a flood of
-- posts can't use up D1's writes for the API. The app is to send at most one batch a day, so it's
-- also roughly how many phones opened Lockin that day.
CREATE TABLE metrics_batches (
  day     TEXT    PRIMARY KEY CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  batches INTEGER NOT NULL CHECK (batches >= 0)
);
