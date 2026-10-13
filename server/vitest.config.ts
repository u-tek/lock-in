import { defineConfig } from "vitest/config";

// The tests run in plain Node: the Worker's code sticks to Web APIs that Node has too (fetch,
// Request, Response, Web Crypto), so it needs no Workers runtime to test.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
