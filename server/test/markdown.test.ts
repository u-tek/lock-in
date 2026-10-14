// The Markdown renderer behind the policy and support pages (src/markdown.ts).

import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { placeholderCount, plainText, renderInline, renderMarkdown, safeHref } from "../src/markdown.ts";

const render = (source: string) => renderMarkdown(source).html;

describe("escaping", () => {
  test("raw HTML is text, everywhere", () => {
    const hostile = `<script>alert(1)</script> <img src=x onerror=alert(1)> & "quotes" 'single' \`tick\``;
    for (const source of [hostile, `# ${hostile}`, `- ${hostile}`, `> ${hostile}`, `| a |\n|---|\n| ${hostile} |`, `**${hostile}**`]) {
      const html = render(source);
      expect(html, source).not.toMatch(/<script|<img|onerror=alert\(1\)>/);
      expect(html, source).toContain("&#60;script&#62;");
    }
    expect(renderInline(`a & b < c > d " e ' f`)).toBe("a &#38; b &#60; c &#62; d &#34; e &#39; f");
  });

  test("code spans are escaped and not parsed", () => {
    expect(renderInline("Run `<b>**not bold**</b>` now")).toBe("Run <code>&#60;b&#62;**not bold**&#60;/b&#62;</code> now");
    expect(renderInline("``a ` b``")).toBe("<code>a &#96; b</code>");
    expect(renderInline("an `unclosed span")).toBe("an &#96;unclosed span");
  });

  test("backslash escapes punctuation", () => {
    expect(renderInline("\\*not em\\* and \\[not a link\\](https://example.com)")).toBe("*not em* and [not a link](https://example.com)");
    expect(renderInline("a \\b c")).toBe("a \\b c");
  });

  test("a link's text and destination are escaped", () => {
    expect(renderInline(`[<i>x</i>](https://example.com/?a=1&b="2")`)).toBe("&#60;i&#62;x&#60;/i&#62;");
    expect(renderInline(`[<i>x</i>](https://example.com/?a=1&b=2)`)).toBe('<a href="https://example.com/?a=1&#38;b=2">&#60;i&#62;x&#60;/i&#62;</a>');
  });
});

describe("links", () => {
  test("http, https, mailto and paths on this site become links", () => {
    expect(renderInline("[OAIC](https://www.oaic.gov.au)")).toBe('<a href="https://www.oaic.gov.au">OAIC</a>');
    expect(renderInline("[old](http://example.com/a_b_c)")).toBe('<a href="http://example.com/a_b_c">old</a>');
    expect(renderInline("[email](mailto:support@example.com)")).toBe('<a href="mailto:support@example.com">email</a>');
    expect(renderInline("[terms](/terms)")).toBe('<a href="/terms">terms</a>');
    expect(renderInline("[deleting](/privacy#deleting-your-account)")).toBe('<a href="/privacy#deleting-your-account">deleting</a>');
    expect(renderInline('[titled](https://example.com "A title")')).toBe('<a href="https://example.com">titled</a>');
    expect(renderInline("[angle](<https://example.com/x>)")).toBe('<a href="https://example.com/x">angle</a>');
  });

  test("anything else shows its text without a link", () => {
    for (const destination of [
      "javascript:alert(1)",
      "JavaScript:alert(1)",
      " javascript:alert(1)",
      "data:text/html,<script>alert(1)</script>",
      "vbscript:x",
      "//evil.example/x",
      "/\\evil.example",
      "file:///etc/passwd",
      "lockin://j/ABCDEFGH",
      "https://",
      "mailto:nobody",
      "relative/path",
      "",
    ]) {
      const html = renderInline(`[click](${destination})`);
      expect(html, destination).not.toContain("<a");
      expect(html, destination).toContain("click");
    }
    expect(safeHref("https://example.com/x y")).toBeNull();
    expect(safeHref("https://example.com/x\"onmouseover=\"y")).toBeNull();
  });

  test("autolinks and bare email addresses", () => {
    expect(renderInline("<https://example.com>")).toBe('<a href="https://example.com">https://example.com</a>');
    expect(renderInline("<support@lockin.app>")).toBe('<a href="mailto:support@lockin.app">support@lockin.app</a>');
    expect(renderInline("Email support@lockin.app today.")).toBe('Email <a href="mailto:support@lockin.app">support@lockin.app</a> today.');
    expect(renderInline("<javascript:alert(1)>")).toBe("&#60;javascript:alert(1)&#62;");
    expect(renderInline("</b> and </privacy>")).toBe("&#60;/b&#62; and &#60;/privacy&#62;");
    // No link inside a link.
    expect(renderInline("[support@lockin.app](mailto:support@lockin.app)")).toBe('<a href="mailto:support@lockin.app">support@lockin.app</a>');
    // The drafts' example addresses have no domain ending, and stay text.
    expect(renderInline("privacy@yourdomain")).toBe("privacy@yourdomain");
  });

  test("brackets that aren't links stay as they are", () => {
    expect(renderInline("Settings → [your name] → Subscriptions")).toBe("Settings → [your name] → Subscriptions");
    expect(renderInline("[unclosed (x)")).toBe("[unclosed (x)");
  });
});

describe("emphasis", () => {
  test("bold, italic and both nested", () => {
    expect(renderInline("**bold** and *italic* and _also_")).toBe("<strong>bold</strong> and <em>italic</em> and <em>also</em>");
    expect(renderInline("*a **b** c*")).toBe("<em>a <strong>b</strong> c</em>");
    expect(renderInline("**a *b* c**")).toBe("<strong>a <em>b</em> c</strong>");
    expect(renderInline("**Settings → [your name] → Subscriptions**")).toBe("<strong>Settings → [your name] → Subscriptions</strong>");
  });

  test("stray stars and underscores stay text", () => {
    expect(renderInline("2 * 3 * 4")).toBe("2 * 3 * 4");
    expect(renderInline("snake_case_name and a_b")).toBe("snake_case_name and a_b");
    expect(renderInline("**unclosed")).toBe("**unclosed");
    expect(renderInline("* not em*")).toBe("* not em*");
  });

  test("emphasis can wrap a line", () => {
    expect(renderInline("*Allow Access When\nLocked*")).toBe("<em>Allow Access When\nLocked</em>");
  });
});

describe("blocks", () => {
  test("headings, with ids for linking", () => {
    expect(render("# Title\n## Deleting your account\n### It's #3 ###\n#### Four")).toBe(
      '<h1 id="title">Title</h1>\n<h2 id="deleting-your-account">Deleting your account</h2>\n<h3 id="it-s-3">It&#39;s #3</h3>\n<h4 id="four">Four</h4>',
    );
    expect(render("## Contact\n\n## Contact")).toBe('<h2 id="contact">Contact</h2>\n<h2 id="contact-2">Contact</h2>');
    expect(render("#hashtag")).toBe("<p>#hashtag</p>");
  });

  test("paragraphs: lines join, blank lines split, hard breaks", () => {
    expect(render("one\ntwo\n\nthree")).toBe("<p>one\ntwo</p>\n<p>three</p>");
    expect(render("Name\\\nEmail: x  \nWebsite")).toBe("<p>Name<br>\nEmail: x<br>\nWebsite</p>");
  });

  test("unordered lists, tight and loose, with continuation lines", () => {
    expect(render("- one\n  more\n- **two**\n* three")).toBe("<ul>\n<li>one\nmore</li>\n<li><strong>two</strong></li>\n<li>three</li>\n</ul>");
    expect(render("- one\n\n- two")).toBe("<ul>\n<li><p>one</p></li>\n<li><p>two</p></li>\n</ul>");
    // A lazy continuation line, not indented.
    expect(render("- one\nmore")).toBe("<ul>\n<li>one\nmore</li>\n</ul>");
  });

  test("ordered lists, nested lists", () => {
    expect(render("1. Open Settings\n2. In **Face ID**, under *Allow\n   Locked*\n3. Done")).toBe(
      "<ol>\n<li>Open Settings</li>\n<li>In <strong>Face ID</strong>, under <em>Allow\nLocked</em></li>\n<li>Done</li>\n</ol>",
    );
    expect(render("3. three\n4. four")).toBe('<ol start="3">\n<li>three</li>\n<li>four</li>\n</ol>');
    expect(render("- a\n  - b\n  - c\n- d")).toBe("<ul>\n<li>a\n<ul>\n<li>b</li>\n<li>c</li>\n</ul></li>\n<li>d</li>\n</ul>");
  });

  test("a list ends at a heading; a wrapped number doesn't start one", () => {
    expect(render("- a\n## Next")).toBe('<ul>\n<li>a</li>\n</ul>\n<h2 id="next">Next</h2>');
    expect(render("Founded in\n2026. Since then")).toBe("<p>Founded in\n2026. Since then</p>");
  });

  test("tables, with inline markup, alignment and escaped bars", () => {
    expect(render("| What | Why |\n|---|:---:|\n| **ID** | `a|b` and \\| |\n| short |")).toBe(
      '<div class="table"><table>\n<thead><tr><th>What</th><th class="align-center">Why</th></tr></thead>\n<tbody>\n' +
        '<tr><td><strong>ID</strong></td><td class="align-center"><code>a|b</code> and |</td></tr>\n' +
        '<tr><td>short</td><td class="align-center"></td></tr>\n</tbody>\n</table></div>',
    );
    // Not a table without a delimiter row.
    expect(render("a | b\nc | d")).toBe("<p>a | b\nc | d</p>");
  });

  test("quotes hold blocks, rules split", () => {
    expect(render("> **Note.** One\n> two\n>\n> - a\n> - b\n\n---\n\n***")).toBe(
      "<blockquote>\n<p><strong>Note.</strong> One\ntwo</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>\n<hr>\n<hr>",
    );
  });

  test("Windows line endings and tabs", () => {
    expect(render("# A\r\n\r\n- b\r\n\tc")).toBe('<h1 id="a">A</h1>\n<ul>\n<li>b\nc</li>\n</ul>');
  });
});

describe("placeholders", () => {
  test("[OWNER: …] is highlighted, inline markup and all", () => {
    expect(renderInline("Email [OWNER: support email, e.g. support@yourdomain] now")).toBe(
      'Email <mark class="owner">[OWNER: support email, e.g. support@yourdomain]</mark> now',
    );
    expect(renderInline("**[OWNER: minimum age, e.g. 13]**")).toBe('<strong><mark class="owner">[OWNER: minimum age, e.g. 13]</mark></strong>');
    expect(renderInline('[OWNER: add "Quiet hours (10 pm\nto 7 am)".]')).toBe('<mark class="owner">[OWNER: add &#34;Quiet hours (10 pm\nto 7 am)&#34;.]</mark>');
    expect(renderInline("[OWNER: <b>x</b>]")).toBe('<mark class="owner">[OWNER: &#60;b&#62;x&#60;/b&#62;]</mark>');
  });

  test("a link still pointing at a placeholder shows it, unlinked", () => {
    expect(renderInline("our [privacy policy]([OWNER: https://yourdomain/privacy])")).toBe(
      'our privacy policy <mark class="owner">[OWNER: https://yourdomain/privacy]</mark>',
    );
  });

  test("are counted anywhere in the source", () => {
    expect(placeholderCount("no placeholders")).toBe(0);
    expect(placeholderCount("[OWNER: a] and `[OWNER: b]`\n> [OWNER: c]")).toBe(3);
  });
});

describe("the drafts in docs/launch/", () => {
  for (const [file, title] of [
    ["privacy-policy.md", "Lockin Privacy Policy"],
    ["terms.md", "Lockin Terms of Use"],
    ["support.md", "Lockin Support"],
  ] as const) {
    test(`${file} renders, with its title and nothing left as raw Markdown`, () => {
      const source = readFileSync(new URL(`../../docs/launch/${file}`, import.meta.url), "utf8");
      const { html, title: rendered } = renderMarkdown(source);
      expect(rendered).toBe(title);
      expect(html.match(/<h1\b/g)).toHaveLength(1);
      const text = plainText(html);
      // Bold markers, link syntax and list markers all became markup.
      expect(text).not.toMatch(/\*\*|\]\(|^\s*[-*] /m);
      expect(html).not.toMatch(/<(script|img|iframe|style)\b/);
      // Every placeholder is highlighted.
      expect(html.match(/<mark class="owner">/g)?.length ?? 0).toBeGreaterThanOrEqual(placeholderCount(source) - (source.match(/`[^`]*\[OWNER:[^`]*`/g)?.length ?? 0));
      // Links go only where links may go.
      for (const [, href] of html.matchAll(/href="([^"]*)"/g)) expect(safeHref(href!.replace(/&#38;/g, "&")), href).not.toBeNull();
    });
  }
});
