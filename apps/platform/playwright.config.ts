import { defineConfig } from "@playwright/test";

// Uses the browser bundled with the installed Playwright (never downloads one, never touches the network).
export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:3100" },
  webServer: {
    command: "npx next start -p 3100 -H 127.0.0.1",
    url: "http://127.0.0.1:3100",
    reuseExistingServer: false,
    timeout: 60_000,
  },
});
