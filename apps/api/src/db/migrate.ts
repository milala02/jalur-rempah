import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { getPool, closePool } from './connection.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function runMigrations(
  pool: pg.Pool = getPool(),
  migrationsDir?: string,
): Promise<string[]> {
  const dir =
    migrationsDir ||
    path.resolve(__dirname, '../../../../db/migrations');

  if (!fs.existsSync(dir)) {
    throw new Error(`Direktori migrasi tidak ditemukan: ${dir}`);
  }

  const client = await pool.connect();
  const applied: string[] = [];

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
    `);

    const { rows: existingRows } = await client.query<{ version: string }>(
      'SELECT version FROM public.schema_migrations ORDER BY version ASC',
    );
    const existingVersions = new Set(existingRows.map((r) => r.version));

    const files = fs
      .readdirSync(dir)
      .filter((f) => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      const version = file.replace(/\.sql$/, '');
      if (existingVersions.has(version)) {
        continue;
      }

      const filePath = path.join(dir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');

      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query(
          'INSERT INTO public.schema_migrations (version) VALUES ($1)',
          [version],
        );
        await client.query('COMMIT');
        applied.push(version);
        console.log(`[MIGRATE] Berhasil menerapkan migrasi: ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`[MIGRATE] Gagal menerapkan migrasi ${file}:`, err);
        throw err;
      }
    }

    return applied;
  } finally {
    client.release();
  }
}

if (
  process.argv[1] &&
  (process.argv[1].endsWith('migrate.ts') || process.argv[1].endsWith('migrate.js'))
) {
  runMigrations()
    .then((applied) => {
      console.log(`[MIGRATE] Selesai. Total migrasi baru: ${applied.length}`);
      return closePool();
    })
    .catch((err) => {
      console.error('[MIGRATE] Error fatal:', err);
      process.exit(1);
    });
}
