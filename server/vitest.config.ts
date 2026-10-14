import { defineConfig } from "vitest/config";

// The tests run in plain Node: the Worker's code sticks to Web APIs that Node has too (fetch,
// Request, Response, Web Crypto), so it needs no Workers runtime to test.
export default defineConfig({
  plugins: [
    {
      // Markdown imports are the file's text, as wrangler bundles them (the "Text" rule in
      // wrangler.toml): the policy pages render from the drafts in docs/launch/ (src/pages.ts).
      name: "markdown-as-text",
      enforce: "pre",
      transform(code, id) {
        if (!id.split("?")[0]!.endsWith(".md")) return null;
        return { code: `export default ${JSON.stringify(code)};`, map: null };
      },
    },
  ],
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
