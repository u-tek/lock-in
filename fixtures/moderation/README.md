# Moderation fixtures

Handles and display names are user-generated content (SPEC.md §1.6, §7). The server is the
authority (`server/src/moderation.ts`); the app's `Social` module runs the same check for instant
feedback in the handle picker. Both test every case in `cases.json`, so they can't drift.

## The check

1. **Valid?** Handles: 3–20 characters of `a-z 0-9 _ .` starting with a letter, after
   lowercasing. Names: 1–12 Unicode code points after trimming whitespace, no control characters.
   Otherwise `invalid`.
2. **Normalise** the (lowercased) input: replace each character in `leet` with its letter, then
   split on anything that isn't `a-z` into **tokens**; the **compact** form is the tokens joined.
3. **Not allowed** if the compact form contains any `anywhere` word; or any token, or the compact
   form, equals a `token` word (these turn up inside innocent words: "class", "grape"); or, for
   handles and names alike, any token or the compact form equals a `reserved` word.
4. Otherwise `ok`.

The list is a floor, not a guarantee: reports catch what it misses. Add words and a case here,
and both test suites pick them up.
