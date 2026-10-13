// Rules the Workers runtime enforces that neither tsc nor `wrangler deploy --dry-run` catches.

import { readFileSync, readdirSync } from "node:fs";
import { expect, test } from "vitest";
import * as entry from "../src/index.ts";

test("the entry module exports only handlers and classes", () => {
  // workerd refuses to start when a named export of the main module isn't a function or class
  // ("Incorrect type for map entry"), so constants belong in other modules.
  for (const [name, value] of Object.entries(entry)) {
    if (name === "default") expect(typeof (value as { fetch?: unknown }).fetch).toBe("function");
    else expect(typeof value, name).toBe("function");
  }
  expect(entry.Room).toBeTypeOf("function");
});

test("src/ uses Web APIs only", () => {
  // The Worker doesn't enable nodejs_compat. Node's types are in the shared tsconfig for the
  // tests, so tsc wouldn't notice a Node API creeping into the Worker.
  const directory = new URL("../src/", import.meta.url);
  for (const file of readdirSync(directory).filter((name) => name.endsWith(".ts"))) {
    const code = readFileSync(new URL(file, directory), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    expect(code, file).not.toMatch(/(from\s+|import\(\s*)["'](node:|cloudflare:)/);
    expect(code, file).not.toMatch(/\b(Buffer|process|require)\s*[.(]/);
  }
});
