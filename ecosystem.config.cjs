require('dotenv').config({ path: __dirname + '/.env' });

// Konfigurasi PM2 Produksi Jalur Rempah (docs/12-DEPLOYMENT-RUNBOOK.md)
// [PERLU VERIFIKASI PEMILIK: sesuaikan PORT_API dan jumlah instances jr-api dengan vCPU VPS]
module.exports = {
  apps: [
    {
      name: 'jr-api',
      script: 'apps/api/dist/main.js',
      exec_mode: 'cluster',
      instances: 1,
      wait_ready: true,
      listen_timeout: 10000,
      kill_timeout: 10000,
      max_memory_restart: '400M',
      env: {
        NODE_ENV: 'production',
        PORT_API: '3100',
      },
    },
    {
      name: 'jr-worker',
      script: 'apps/worker/dist/main.js',
      exec_mode: 'fork', // WAJIB fork dengan tepat 1 instance (writer tunggal + advisory lock)
      instances: 1,
      kill_timeout: 20000,
      max_memory_restart: '600M',
      env: {
        NODE_ENV: 'production',
        TICK_SECONDS: '30',
      },
    },
  ],
};
