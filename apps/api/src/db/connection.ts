import pg from 'pg';

const { Pool } = pg;

let poolInstance: pg.Pool | null = null;

export function getDatabaseUrl(): string {
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
