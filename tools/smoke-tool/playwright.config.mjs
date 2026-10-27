import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  reporter: 'line',
  use: { baseURL: 'http://127.0.0.1:1436', viewport: { width: 1040, height: 820 } },
  webServer: { command: 'npx vite preview --host 127.0.0.1 --port 1436 --strictPort', url: 'http://127.0.0.1:1436', reuseExistingServer: false },
});
