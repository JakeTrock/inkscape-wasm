import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 180000,
  use: { viewport: { width: 1280, height: 800 }, baseURL: 'http://127.0.0.1:8823' },
  webServer: {
    command: 'python3 -m http.server 8823 --directory ../build',
    url: 'http://127.0.0.1:8823',
    reuseExistingServer: true,
  },
});
