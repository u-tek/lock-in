// Handle and display-name moderation (SPEC.md §1.6, §7): exactly the check in
// fixtures/moderation/README.md. The app's Social module runs the same check for instant feedback;
// both test every case in fixtures/moderation/cases.json, so they can't drift. The server is the
// authority.
//
// The word list is imported straight from fixtures/: wrangler's bundler inlines it into the Worker
// (it resolves the path like any other import), so there's one copy and nothing to keep in sync.

import words from "../../fixtures/moderation/words.json";

export type ModerationKind = "handle" | "name";
export type ModerationVerdict = "ok" | "invalid" | "not_allowed";

interface WordList {
  leet: Record<string, string>;
  anywhere: string[];
  token: string[];
  reserved: string[];
}

const LIST: WordList = words;
const TOKEN_WORDS = new Set(LIST.token);
const RESERVED_WORDS = new Set(LIST.reserved);

/** 3–20 of `a-z 0-9 _ .`, starting with a letter, after lowercasing. */
const HANDLE = /^[a-z][a-z0-9_.]{2,19}$/;
export const MAX_DISPLAY_NAME_LENGTH = 12;
// Control characters, and lone surrogates (which JSON can carry as `\ud800` escapes), as the Live
// Activity's validator refuses them in `n` (src/liveActivity.ts).
const UNPRINTABLE = /[\p{Cc}\p{Cs}]/u;

/** What a handle is stored as. */
export function normaliseHandle(input: string): string {
  return input.toLowerCase();
}

/** What a display name is stored as. */
export function normaliseName(input: string): string {
  return input.trim();
}

/** Step 1: the shape alone. */
export function isValid(kind: ModerationKind, input: string): boolean {
  if (kind === "handle") return HANDLE.test(normaliseHandle(input));
  const name = normaliseName(input);
  const length = [...name].length;
  return length >= 1 && length <= MAX_DISPLAY_NAME_LENGTH && !UNPRINTABLE.test(name);
}

/** Step 2: the tokens and the compact form of the (lowercased) input. */
export function normalise(input: string): { tokens: string[]; compact: string } {
  let replaced = "";
  for (const character of input.toLowerCase()) replaced += LIST.leet[character] ?? character;
  const tokens = replaced.split(/[^a-z]+/).filter((token) => token.length > 0);
  return { tokens, compact: tokens.join("") };
}

/** Step 3: whether the words are allowed, whatever the shape. */
export function isAllowed(input: string): boolean {
  const { tokens, compact } = normalise(input);
  if (LIST.anywhere.some((word) => compact.includes(word))) return false;
  for (const candidate of [...tokens, compact]) {
    if (TOKEN_WORDS.has(candidate) || RESERVED_WORDS.has(candidate)) return false;
  }
  return true;
}

/** The whole check. Names are checked as stored, i.e. trimmed. */
export function moderate(kind: ModerationKind, input: string): ModerationVerdict {
  if (!isValid(kind, input)) return "invalid";
  const stored = kind === "handle" ? normaliseHandle(input) : normaliseName(input);
  return isAllowed(stored) ? "ok" : "not_allowed";
}
