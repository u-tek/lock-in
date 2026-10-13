# Live Activity fixtures

The single source of truth for the Live Activity wire format (SPEC.md §4.3). Both sides test
against these files, so the Swift `LockinAttributes` type and the server's TypeScript types can't
drift apart:

- `Packages/LKKit/Tests/ModelTests` decodes each file with Apple's **default** `JSONDecoder`
  (exactly what ActivityKit does with a push), re-encodes it, and checks nothing was lost.
- `server/test` validates each file with the server's strict parser, rebuilds it with the
  server's encoder, and checks it comes out the same.

| File | What it covers |
|---|---|
| `squad-6.*` | Six members, one in every state (focusing, break, paused, done, left, slipped), a pet and a cheer |
| `solo.*` | A solo session: no squad name, pet or cheer (optional keys absent, never `null`) |
| `largest.*` | The worst case the server allows: every optional key, the longest strings in 4-byte characters, long fractional times. Must stay under 3.5 KB of compact UTF-8 JSON (attributes + content-state) |

Rules (CLAUDE.md, "Live Activity rules"):

- Keys are the short names in SPEC.md §4.3 and match the Swift property names exactly.
- Times are Unix seconds as JSON numbers (`Double` in Swift). Never ISO dates.
- Optional values are left out rather than sent as `null`.

Change a key here, in `Model`, and in `server/src/liveActivity.ts` in the same commit.
