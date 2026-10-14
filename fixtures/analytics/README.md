# Analytics fixtures

`events.json` lists every analytics event the app can send, by name: the raw values of
`AnalyticsEvent` in `Packages/LKKit/Sources/Core/Analytics.swift` (SPEC.md §5.6). Counts only,
never content (CLAUDE.md, "Analytics are integer event counts only").

- The server's `POST /metrics` accepts these names and nothing else (`server/src/metrics.ts`).
- `CoreTests` checks that `AnalyticsEvent.allCases` is exactly this list, and the server's tests
  check the route against it, so the two can't drift.

Add an event in both places in the same change. The provider decision is
`docs/decisions/0010-analytics-provider.md`.
