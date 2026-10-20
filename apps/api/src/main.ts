import { getPool, closePool } from './db/connection.js';
import { createApiServer } from './app.js';

async function bootstrapApi(): Promise<void> {
  const port = Number(process.env['PORT_API'] ?? '3100');
  const host = process.env['HOST_API'] ?? '0.0.0.0';
  const pool = getPool();
  const app = createApiServer(pool);

  await app.listen(port, host);
  console.log(
    JSON.stringify({
      level: 'info',
      service: 'jr-api',
      msg: `API server berjalan pada http://${host}:${port}`,
      port,
    }),
  );

  if (typeof process.send === 'function') {
    process.send('ready');
  }

  let shuttingDown = false;
  async function shutdown(signal: string): Promise<void> {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(
      JSON.stringify({
        level: 'info',
        service: 'jr-api',
        msg: `Menerima sinyal ${signal}, menutup koneksi HTTP dan DB...`,
      }),
    );
    try {
      await app.close();
      await closePool();
      process.exit(0);
    } catch (err) {
      console.error('[JR-API] Gagal menutup server dengan bersih:', err);
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

bootstrapApi().catch((err) => {
  console.error('[JR-API] Kegagalan fatal saat startup:', err);
  process.exit(1);
});
