// Markdown files imported as their text: wrangler bundles them through the "Text" rule in
// wrangler.toml, and vitest.config.ts loads them the same way for the tests (src/pages.ts).
declare module "*.md" {
  const text: string;
  export default text;
}
