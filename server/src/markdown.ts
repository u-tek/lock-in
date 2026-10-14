// A small Markdown renderer for the policy and support pages (src/pages.ts), which are the drafts in
// docs/launch/ bundled as text. It covers what those drafts use and no more:
//
//   blocks:  # headings (1–6), paragraphs, - * + and 1. lists (nested by indenting), > quotes,
//            GFM tables, --- *** ___ rules
//   inline:  **bold**, *italic* and _italic_, `code`, [links](https://…), <https://…> and
//            <name@example.com>, bare email addresses, \ escapes, hard breaks (a trailing \ or
//            two trailing spaces)
//
// Not covered (they render as text): raw HTML (always escaped), images, code blocks, setext
// headings, link references and footnotes.
//
// Safety: every character of the source reaches the page escaped, and a link is only made for
// http(s), mailto and same-site paths ("/support"). Anything else (javascript:, data:, "//host")
// shows its text without a link.
//
// `[OWNER: …]` placeholders render highlighted, so a page that still has one looks unfinished;
// `placeholderCount` lets the routes keep such a page out of search engines.

import { escapeHTML } from "./http.ts";

export interface RenderedMarkdown {
  /** The body, ready to go inside `<article>`. */
  html: string;
  /** The first level-1 heading as plain text, or null without one. */
  title: string | null;
}

/** The Markdown as HTML, and its title. */
export function renderMarkdown(source: string): RenderedMarkdown {
  const lines = source.replace(/\r\n?/g, "\n").replace(/\t/g, "    ").split("\n");
  const blocks = parseBlocks(lines);
  const slugs = new Map<string, number>();
  const html = blocks.map((block) => renderBlock(block, slugs)).join("\n");
  const heading = findTitle(blocks);
  return { html, title: heading === null ? null : plainText(renderInline(heading)) };
}

/** How many `[OWNER: …]` placeholders the source still has, anywhere (code spans included). */
export function placeholderCount(source: string): number {
  return source.match(/\[OWNER:/g)?.length ?? 0;
}

/** The text of rendered inline HTML: tags dropped, this renderer's entities decoded. */
export function plainText(html: string): string {
  return html
    .replace(/<[^>]*>/g, "")
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCharCode(Number(code)))
    .replace(/\s+/g, " ")
    .trim();
}

// Blocks

type Align = "left" | "center" | "right" | null;

type Block =
  | { kind: "heading"; level: number; text: string }
  | { kind: "paragraph"; text: string }
  | { kind: "rule" }
  | { kind: "quote"; blocks: Block[] }
  | { kind: "list"; ordered: boolean; start: number; loose: boolean; items: Block[][] }
  | { kind: "table"; align: Align[]; head: string[]; rows: string[][] };

const BLANK = /^\s*$/;
const RULE = /^ {0,3}([-*_])(?:[ ]*\1){2,}[ ]*$/;
const HEADING = /^ {0,3}(#{1,6})(?:[ ]+(.*?))?(?:[ ]+#+)?[ ]*$/;
const QUOTE = /^ {0,3}>/;
/** "- ", "* ", "+ ", or "1. " / "1) ": indent, bullet or number and delimiter, spaces, text. */
const LIST_ITEM = /^( {0,3})(?:([-*+])|(\d{1,9})([.)]))( +|$)(.*)$/;

interface ListMarker {
  ordered: boolean;
  start: number;
  /** Spaces before the marker. */
  indent: number;
  /** The column the item's text starts at; continuation lines are indented this far. */
  content: number;
  /** The rest of the first line. */
  text: string;
}

function listMarker(line: string): ListMarker | null {
  const match = LIST_ITEM.exec(line);
  if (match === null) return null;
  const [, indent = "", bullet, digits = "", delimiter = "", spaces = "", rest = ""] = match;
  const ordered = bullet === undefined;
  // 1–4 spaces after the marker set the content column; more than that, or none, count as one.
  const gap = spaces.length >= 1 && spaces.length <= 4 && rest.length > 0 ? spaces.length : 1;
  return {
    ordered,
    start: ordered ? Number(digits) : 1,
    indent: indent.length,
    content: indent.length + (ordered ? digits.length + delimiter.length : 1) + gap,
    text: spaces.length > 4 ? `${" ".repeat(spaces.length - 1)}${rest}` : rest,
  };
}

/** Whether `line` starts a block that ends a paragraph above it. */
function interruptsParagraph(line: string): boolean {
  if (RULE.test(line) || HEADING.test(line) || QUOTE.test(line)) return true;
  const marker = listMarker(line);
  // As in CommonMark, an ordered list interrupts a paragraph only from 1, so a wrapped line that
  // happens to start "2026." stays text; neither interrupts with an empty item.
  return marker !== null && marker.text.trim().length > 0 && (!marker.ordered || marker.start === 1);
}

function parseBlocks(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    if (BLANK.test(line)) {
      i += 1;
      continue;
    }
    if (RULE.test(line)) {
      blocks.push({ kind: "rule" });
      i += 1;
      continue;
    }
    const heading = HEADING.exec(line);
    if (heading !== null) {
      blocks.push({ kind: "heading", level: heading[1]!.length, text: heading[2] ?? "" });
      i += 1;
      continue;
    }
    if (QUOTE.test(line)) {
      const inner: string[] = [];
      while (i < lines.length && QUOTE.test(lines[i]!)) {
        inner.push(lines[i]!.replace(/^ {0,3}> ?/, ""));
        i += 1;
      }
      blocks.push({ kind: "quote", blocks: parseBlocks(inner) });
      continue;
    }
    if (listMarker(line) !== null) {
      const list = parseList(lines, i);
      blocks.push(list.block);
      i = list.next;
      continue;
    }
    const table = parseTable(lines, i);
    if (table !== null) {
      blocks.push(table.block);
      i = table.next;
      continue;
    }
    const paragraph: string[] = [line];
    i += 1;
    while (i < lines.length && !BLANK.test(lines[i]!) && !interruptsParagraph(lines[i]!)) {
      paragraph.push(lines[i]!);
      i += 1;
    }
    blocks.push({ kind: "paragraph", text: paragraphText(paragraph) });
  }
  return blocks;
}

/** A paragraph's lines joined: leading spaces go, trailing ones stay (two make a hard break). */
function paragraphText(lines: string[]): string {
  return lines
    .map((line) => line.replace(/^\s+/, ""))
    .join("\n")
    .replace(/\s+$/, "");
}

function parseList(lines: string[], from: number): { block: Block; next: number } {
  const first = listMarker(lines[from]!)!;
  const items: string[][] = [];
  let loose = false;
  let i = from;
  let marker: ListMarker | null = first;
  while (marker !== null) {
    const item: string[] = [marker.text];
    const content = marker.content;
    i += 1;
    let blankBefore = false;
    marker = null;
    while (i < lines.length) {
      const line = lines[i]!;
      if (BLANK.test(line)) {
        item.push("");
        blankBefore = true;
        i += 1;
        continue;
      }
      const indent = /^ */.exec(line)![0].length;
      if (indent >= content) {
        // A blank line between two parts of one item makes the list loose.
        if (blankBefore) loose = true;
        item.push(line.slice(content));
        blankBefore = false;
        i += 1;
        continue;
      }
      const next = listMarker(line);
      if (next !== null && next.ordered === first.ordered && next.indent < content) {
        if (blankBefore) loose = true;
        marker = next;
        break;
      }
      // A lazy continuation: unindented text straight after the item's text, as long as it
      // doesn't start a block of its own.
      if (!blankBefore && !interruptsParagraph(line) && !(next !== null)) {
        item.push(line.trimStart());
        i += 1;
        continue;
      }
      break;
    }
    while (item.length > 0 && BLANK.test(item[item.length - 1]!)) item.pop();
    items.push(item);
  }
  return {
    block: { kind: "list", ordered: first.ordered, start: first.start, loose, items: items.map((item) => parseBlocks(item)) },
    next: i,
  };
}

/** GFM: a header row, a delimiter row with as many cells, then rows until a blank line. */
function parseTable(lines: string[], from: number): { block: Block; next: number } | null {
  const headLine = lines[from]!;
  const delimiterLine = lines[from + 1];
  if (!headLine.includes("|") || delimiterLine === undefined) return null;
  if (!/^ {0,3}\|?[ ]*:?-+:?[ ]*(\|[ ]*:?-+:?[ ]*)*\|?[ ]*$/.test(delimiterLine) || !delimiterLine.includes("-")) return null;
  const head = splitRow(headLine);
  const delimiters = splitRow(delimiterLine);
  if (head.length !== delimiters.length) return null;
  const align: Align[] = delimiters.map((cell) => {
    const left = cell.startsWith(":");
    const right = cell.endsWith(":");
    return left && right ? "center" : right ? "right" : left ? "left" : null;
  });
  const rows: string[][] = [];
  let i = from + 2;
  while (i < lines.length && !BLANK.test(lines[i]!) && !interruptsParagraph(lines[i]!)) {
    const cells = splitRow(lines[i]!);
    rows.push(head.map((_, column) => cells[column] ?? ""));
    i += 1;
  }
  return { block: { kind: "table", align, head, rows }, next: i };
}

/** A table row's cells: split on `|` outside code spans; `\|` is a literal bar. */
function splitRow(line: string): string[] {
  let text = line.trim();
  if (text.startsWith("|")) text = text.slice(1);
  if (text.endsWith("|") && !text.endsWith("\\|")) text = text.slice(0, -1);
  const cells: string[] = [];
  let cell = "";
  for (let i = 0; i < text.length; i++) {
    const character = text[i]!;
    if (character === "\\" && text[i + 1] === "|") {
      cell += "|";
      i += 1;
    } else if (character === "`") {
      const run = /^`+/.exec(text.slice(i))![0];
      const close = text.indexOf(run, i + run.length);
      const end = close === -1 ? i + run.length : close + run.length;
      cell += text.slice(i, end);
      i = end - 1;
    } else if (character === "|") {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += character;
    }
  }
  cells.push(cell.trim());
  return cells;
}

function findTitle(blocks: Block[]): string | null {
  for (const block of blocks) {
    if (block.kind === "heading" && block.level === 1) return block.text;
  }
  return null;
}

// Rendering blocks

function renderBlock(block: Block, slugs: Map<string, number>, tight = false): string {
  switch (block.kind) {
    case "heading": {
      const inline = renderInline(block.text);
      const id = uniqueSlug(plainText(inline), slugs);
      return `<h${block.level}${id === "" ? "" : ` id="${id}"`}>${inline}</h${block.level}>`;
    }
    case "paragraph":
      return tight ? renderInline(block.text) : `<p>${renderInline(block.text)}</p>`;
    case "rule":
      return "<hr>";
    case "quote":
      return `<blockquote>\n${block.blocks.map((inner) => renderBlock(inner, slugs)).join("\n")}\n</blockquote>`;
    case "list": {
      const tag = block.ordered ? "ol" : "ul";
      const start = block.ordered && block.start !== 1 ? ` start="${block.start}"` : "";
      const items = block.items.map((item) => `<li>${item.map((inner) => renderBlock(inner, slugs, !block.loose)).join("\n")}</li>`);
      return `<${tag}${start}>\n${items.join("\n")}\n</${tag}>`;
    }
    case "table": {
      const cell = (tag: string, text: string, column: number) => {
        const align = block.align[column];
        return `<${tag}${align === null || align === undefined ? "" : ` class="align-${align}"`}>${renderInline(text)}</${tag}>`;
      };
      const head = `<tr>${block.head.map((text, column) => cell("th", text, column)).join("")}</tr>`;
      const rows = block.rows.map((row) => `<tr>${row.map((text, column) => cell("td", text, column)).join("")}</tr>`);
      // The wrapper scrolls sideways on a narrow phone instead of the page.
      return `<div class="table"><table>\n<thead>${head}</thead>\n<tbody>\n${rows.join("\n")}\n</tbody>\n</table></div>`;
    }
  }
}

/** "Deleting your account" → "deleting-your-account", made unique on the page. */
function uniqueSlug(text: string, slugs: Map<string, number>): string {
  const base = text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (base === "") return "";
  const seen = slugs.get(base) ?? 0;
  slugs.set(base, seen + 1);
  return seen === 0 ? base : `${base}-${seen + 1}`;
}

// Inline

const PUNCTUATION = /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/;
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g;
const PLACEHOLDER = "[OWNER:";

/**
 * Inline Markdown as HTML. Everything that isn't markup comes out escaped. `autolinks` is false
 * inside a link's text, so an email address there doesn't become a link within a link.
 */
export function renderInline(source: string, autolinks = true): string {
  let html = "";
  let text = "";
  const flush = () => {
    html += autolinks ? textHTML(text) : escapeHTML(text);
    text = "";
  };

  let i = 0;
  while (i < source.length) {
    const character = source[i]!;

    if (character === "\\") {
      const next = source[i + 1];
      if (next === "\n") {
        flush();
        html += "<br>\n";
        i += 2;
        continue;
      }
      if (next !== undefined && PUNCTUATION.test(next)) {
        text += next;
        i += 2;
        continue;
      }
    }

    if (character === "\n") {
      // Two or more spaces before a line break make it a hard break.
      if (/ {2,}$/.test(text)) {
        text = text.replace(/ +$/, "");
        flush();
        html += "<br>\n";
      } else {
        text = text.replace(/ +$/, "");
        text += "\n";
      }
      i += 1;
      continue;
    }

    if (character === "`") {
      const run = /^`+/.exec(source.slice(i))![0];
      const close = findCodeClose(source, i + run.length, run.length);
      if (close === -1) {
        text += run;
        i += run.length;
        continue;
      }
      let code = source.slice(i + run.length, close).replace(/\n/g, " ");
      if (code.length > 2 && code.startsWith(" ") && code.endsWith(" ") && code.trim().length > 0) code = code.slice(1, -1);
      flush();
      html += `<code>${escapeHTML(code)}</code>`;
      i = close + run.length;
      continue;
    }

    if (source.startsWith(PLACEHOLDER, i)) {
      const close = matchingBracket(source, i);
      if (close !== -1) {
        flush();
        html += `<mark class="owner">[OWNER:${renderInline(source.slice(i + PLACEHOLDER.length, close), autolinks)}]</mark>`;
        i = close + 1;
        continue;
      }
    }

    if (character === "[") {
      const close = matchingBracket(source, i);
      if (close !== -1 && source[close + 1] === "(") {
        const end = matchingParenthesis(source, close + 1);
        if (end !== -1) {
          flush();
          html += link(source.slice(i + 1, close), source.slice(close + 2, end), autolinks);
          i = end + 1;
          continue;
        }
      }
    }

    if (character === "<") {
      const autolink = /^<([^\s<>]+)>/.exec(source.slice(i));
      if (autolink !== null && autolinks) {
        // As in CommonMark: a URL with a scheme, or an email address. Never a path: "</b>" is text.
        const target = autolink[1]!;
        const email = /^[^@\s:/]+@[^@\s:/]+\.[A-Za-z]{2,}$/.test(target);
        const href = email ? `mailto:${target}` : target;
        if ((email || /^[A-Za-z][A-Za-z0-9+.-]{1,31}:/.test(target)) && safeHref(href) !== null) {
          flush();
          html += `<a href="${escapeHTML(href)}">${escapeHTML(target)}</a>`;
          i += autolink[0].length;
          continue;
        }
      }
    }

    if (character === "*" || character === "_") {
      const emphasis = parseEmphasis(source, i, autolinks);
      if (emphasis !== null) {
        flush();
        html += emphasis.html;
        i = emphasis.next;
        continue;
      }
      const run = character === "*" ? /^\*+/.exec(source.slice(i))![0] : /^_+/.exec(source.slice(i))![0];
      text += run;
      i += run.length;
      continue;
    }

    text += character;
    i += 1;
  }
  flush();
  return html;
}

/** Plain text, escaped, with bare email addresses made into mailto links. */
function textHTML(text: string): string {
  let html = "";
  let last = 0;
  for (const match of text.matchAll(EMAIL)) {
    const start = match.index;
    html += escapeHTML(text.slice(last, start));
    html += `<a href="mailto:${escapeHTML(match[0])}">${escapeHTML(match[0])}</a>`;
    last = start + match[0].length;
  }
  return html + escapeHTML(text.slice(last));
}

/** The index of the backtick run of exactly `length` closing a code span, or -1. */
function findCodeClose(source: string, from: number, length: number): number {
  let i = from;
  while (i < source.length) {
    const next = source.indexOf("`", i);
    if (next === -1) return -1;
    const run = /^`+/.exec(source.slice(next))![0];
    if (run.length === length) return next;
    i = next + run.length;
  }
  return -1;
}

/** The `]` matching the `[` at `open` (nesting and `\]` respected), or -1. */
function matchingBracket(source: string, open: number): number {
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    const character = source[i];
    if (character === "\\") {
      i += 1;
    } else if (character === "[") {
      depth += 1;
    } else if (character === "]") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** The `)` matching the `(` at `open`, on the same line, or -1. */
function matchingParenthesis(source: string, open: number): number {
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    const character = source[i];
    if (character === "\n") return -1;
    if (character === "\\") {
      i += 1;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/**
 * `[text](destination "title")`. A destination that isn't http(s), mailto or a path on this site
 * shows the text without a link; one that's still an `[OWNER: …]` placeholder shows it too,
 * highlighted, after the text.
 */
function link(label: string, inside: string, autolinks: boolean): string {
  let destination = inside.trim();
  const titled = /^(\S+)\s+(?:"[^"]*"|'[^']*'|\([^)]*\))$/.exec(destination);
  if (titled !== null) destination = titled[1]!;
  if (destination.startsWith("<") && destination.endsWith(">")) destination = destination.slice(1, -1);
  if (destination.startsWith(PLACEHOLDER)) return `${renderInline(label, autolinks)} ${renderInline(destination, autolinks)}`;
  const href = safeHref(destination);
  // Inside another link's text (or with nowhere safe to point), the text alone.
  if (href === null || !autolinks) return renderInline(label, autolinks);
  return `<a href="${escapeHTML(href)}">${renderInline(label, false)}</a>`;
}

/** The destination if a link may point at it: http(s), mailto, or a path on this site. */
export function safeHref(destination: string): string | null {
  // A path here, like "/support" or "/privacy#deleting-your-account". Not "//host" (another site)
  // or anything with a backslash, which browsers read as a slash.
  if (/^\/(?![/\\])[^\s\\<>"'`]*$/.test(destination)) return destination;
  if (/^#[A-Za-z0-9-]+$/.test(destination)) return destination;
  if (!/^(https?:\/\/|mailto:)/i.test(destination) || /[\s<>"'`\\]/.test(destination)) return null;
  try {
    const url = new URL(destination);
    if (url.protocol === "mailto:") return url.pathname.includes("@") ? destination : null;
    return (url.protocol === "https:" || url.protocol === "http:") && url.hostname.length > 0 ? destination : null;
  } catch {
    return null;
  }
}

/**
 * `**strong**`, `*em*` or `_em_` starting at `at`, or null if the run there doesn't open one.
 * An opener has text straight after it, a closer text straight before it; `_` also has to sit at a
 * word's edge, so snake_case stays as it is.
 */
function parseEmphasis(source: string, at: number, autolinks: boolean): { html: string; next: number } | null {
  const delimiter = source[at]!;
  const width = (delimiter === "*" ? /^\*+/ : /^_+/).exec(source.slice(at))![0].length;
  // Only runs of one or two: "***both***" isn't used, and stays as text.
  if (width > 2) return null;
  const after = source[at + width];
  if (after === undefined || /\s/.test(after)) return null;
  if (delimiter === "_" && at > 0 && /[A-Za-z0-9]/.test(source[at - 1]!)) return null;
  const close = findEmphasisClose(source, at + width, delimiter, width);
  if (close === -1) return null;
  const tag = width === 2 ? "strong" : "em";
  return { html: `<${tag}>${renderInline(source.slice(at + width, close), autolinks)}</${tag}>`, next: close + width };
}

/** Where a closing run of exactly `width` delimiters is, skipping code spans and other runs. */
function findEmphasisClose(source: string, from: number, delimiter: string, width: number): number {
  let i = from;
  while (i < source.length) {
    const character = source[i]!;
    if (character === "\\") {
      i += 2;
      continue;
    }
    if (character === "`") {
      const run = /^`+/.exec(source.slice(i))![0];
      const close = findCodeClose(source, i + run.length, run.length);
      i = close === -1 ? i + run.length : close + run.length;
      continue;
    }
    if (character === delimiter) {
      const run = (delimiter === "*" ? /^\*+/ : /^_+/).exec(source.slice(i))![0].length;
      const before = source[i - 1];
      const after = source[i + run];
      const closes = i > from && before !== undefined && !/\s/.test(before) && (delimiter === "*" || after === undefined || !/[A-Za-z0-9]/.test(after));
      if (closes && run === width) return i;
      i += run;
      continue;
    }
    i += 1;
  }
  return -1;
}
