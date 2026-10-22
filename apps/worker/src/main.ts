import pg from 'pg';
import { WORLD_CONFIG } from '@jalur-rempah/shared';
import { startWorkerLoop } from './worker.js';

const { Pool } = pg;

async function bootstrapWorker(): Promise<void> {
  const dbUrl =
    process.env['DATABASE_URL_WORKER'] ??
    process.env['DATABASE_URL'] ??
    'postgres://jalur_rempah_test:test_password@localhost:5432/jalur_rempah_test';
  const tickSeconds = Number(
    process.env['TICK_SECONDS'] ?? String(WORLD_CONFIG.TICK_SECONDS),
  );
  const worldSeed = Number(process.env['WORLD_SEED'] ?? '101');

  const pool = new Pool({ connectionString: dbUrl });
  const config = {
    ...WORLD_CONFIG,
    TICK_SECONDS: tickSeconds > 0 ? tickSeconds : WORLD_CONFIG.TICK_SECONDS,
  };

  const controller = await startWorkerLoop(pool, {
    config,
    worldSeed,
    intervalMs: config.TICK_SECONDS * 1000,
  });

  if (!controller) {
    console.error(
      JSON.stringify({
        level: 'error',
        service: 'jr-worker',
        msg: 'Gagal memperoleh pg_try_advisory_lock: instance worker lain sedang aktif. Keluar.',
      }),
    );
    await pool.end();
    process.exit(1);
  }

  console.log(
    JSON.stringify({
      level: 'info',
      service: 'jr-worker',
      msg: 'Worker tick loop aktif dan memegang kunci advisory tunggal.',
      tick_seconds: config.TICK_SECONDS,
      world_seed: worldSeed,
    }),
  );

  let shuttingDown = false;
  async function shutdown(signal: string): Promise<void> {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(
      JSON.stringify({
        level: 'info',
        service: 'jr-worker',
        msg: `Menerima sinyal ${signal}, menunggu tick aktif selesai dan melepas kunci...`,
        metrics: controller?.metrics,
      }),
    );
    try {
      await controller?.stop();
      await pool.end();
      process.exit(0);
    } catch (err) {
      console.error('[JR-WORKER] Gagal menghentikan worker:', err);
      process.exit(1);
    }
  }

  process.on('SIGTERM', () => {
    void shutdown('SIGTERM');
  });
  process.on('SIGINT', () => {
    void shutdown('SIGINT');
  });
}

// Di bawah PM2, argv[1] adalah wrapper PM2 (bukan main.js), jadi deteksi lewat pm_id.
if (
  process.env['pm_id'] !== undefined ||
  (process.argv[1] &&
    (process.argv[1].endsWith('main.ts') || process.argv[1].endsWith('main.js')))
) {
  bootstrapWorker().catch((err) => {
    console.error('[JR-WORKER] Kegagalan fatal saat startup:', err);
    process.exit(1);
  });
}
