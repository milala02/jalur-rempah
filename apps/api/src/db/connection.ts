import pg from 'pg';

const { Pool } = pg;

let poolInstance: pg.Pool | null = null;

export function getDatabaseUrl(): string {
  return (
    process.env['DATABASE_URL'] ||
    'postgres://jalur_rempah_test:test_password@localhost:5432/jalur_rempah_test'
  );
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
