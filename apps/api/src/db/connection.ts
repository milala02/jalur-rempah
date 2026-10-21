import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const { Pool } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let poolInstance: pg.Pool | null = null;

function loadDotenvIfNeeded(): void {
  if (process.env['DATABASE_URL']) return;
  const candidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(__dirname, '../../../../.env'),
    path.resolve(__dirname, '../../../.env'),
    path.resolve(__dirname, '../../.env'),
  ];
  for (const file of candidates) {
    if (fs.existsSync(file)) {
      try {
        const text = fs.readFileSync(file, 'utf8');
        for (const line of text.split('\n')) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith('#')) continue;
          const eq = trimmed.indexOf('=');
          if (eq > 0) {
            const key = trimmed.slice(0, eq).trim();
            let val = trimmed.slice(eq + 1).trim();
            if (
              (val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))
            ) {
              val = val.slice(1, -1);
            }
            if (process.env[key] === undefined) {
              process.env[key] = val;
            }
          }
        }
        if (process.env['DATABASE_URL']) break;
      } catch {
        // ignore read error
      }
    }
  }
}

export function getDatabaseUrl(): string {
  loadDotenvIfNeeded();
  return (
    process.env['DATABASE_URL'] ||
    'postgres://jalur_rempah_test:test_password@localhost:5432/jalur_rempah_test'
  );
}

export function getDatabaseNameFromUrl(connectionString: string = getDatabaseUrl()): string {
  const url = new URL(connectionString);
  const dbName = url.pathname.replace(/^\/+/, '');
  if (!dbName) {
    throw new Error(`Nama database tidak ditemukan pada URL koneksi: ${connectionString}`);
  }
  return decodeURIComponent(dbName);
}

export function replaceDatabaseInUrl(connectionString: string, dbName: string): string {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(dbName)) {
    throw new Error(`Nama database tidak valid: ${dbName}`);
  }
  const url = new URL(connectionString);
  url.pathname = `/${encodeURIComponent(dbName)}`;
  return url.toString();
}

export function createPool(connectionString?: string): pg.Pool {
  return new Pool({
    connectionString: connectionString || getDatabaseUrl(),
  });
}

export function getPool(): pg.Pool {
  if (!poolInstance) {
    poolInstance = createPool();
  }
  return poolInstance;
}

export async function closePool(): Promise<void> {
  if (poolInstance) {
    await poolInstance.end();
    poolInstance = null;
  }
}
