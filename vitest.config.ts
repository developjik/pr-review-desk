import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

export default defineConfig({
  test: {
    include: [
      "src/**/*.test.ts",
      "daemon/src/**/*.test.ts",
      "shared/src/**/*.test.ts",
    ],
    environment: "node",
  },
  resolve: {
    alias: {
      "@pr-review/shared": resolve(__dirname, "shared/src"),
    },
  },
});
