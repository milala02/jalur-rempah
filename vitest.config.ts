import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    testTimeout: 30000,
    env: {
      JWT_SECRET: 'test-global-jwt-secret-minimum-32-characters-for-testing',
      ADMIN_API_KEY: 'test-global-admin-api-key',
    },
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
});
