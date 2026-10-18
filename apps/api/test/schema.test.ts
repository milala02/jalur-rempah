import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import pg from 'pg';
import { createPool } from '../src/db/connection.js';
import { runMigrations } from '../src/db/migrate.js';
import { seedWorld } from '../src/db/seed.js';
import {
  COMMODITIES_SEED,
  PORTS_SEED,
  ROUTES_SEED,
  MARKET_SEED,
} from '@jalur-rempah/shared';

describe('M0 — Fondasi Repo: Database Schema, Migrations, & Seed', () => {
  let pool: pg.Pool;
  const testSchema = `test_m0_${Date.now()}_${Math.floor(Math.random() * 10000)}`;

  beforeAll(async () => {
    pool = createPool();

    const client = await pool.connect();
    try {
      await client.query(`CREATE SCHEMA ${testSchema};`);
      await client.query(`SET search_path TO ${testSchema}, public;`);
    } finally {
      client.release();
    }
  });

  afterAll(async () => {
    if (pool) {
      const client = await pool.connect();
      try {
        await client.query(`DROP SCHEMA IF EXISTS ${testSchema} CASCADE;`);
      } catch (err) {
        console.warn(`Gagal drop schema ${testSchema}:`, err);
      } finally {
        client.release();
      }
      await pool.end();
    }
  });

  it('1. Sukses menjalankan migrasi 0001 pada schema bersih', async () => {
    const client = await pool.connect();
    try {
      await client.query(`SET search_path TO ${testSchema}, public;`);
      const applied = await runMigrations(pool);
      expect(applied).toContain('0001_init');

      const tablesRes = await client.query<{ table_name: string }>(`
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = '${testSchema}';
      `);
      const tableNames = tablesRes.rows.map((r) => r.table_name);

      expect(tableNames).toContain('commodities');
      expect(tableNames).toContain('ports');
      expect(tableNames).toContain('routes');
      expect(tableNames).toContain('market');
      expect(tableNames).toContain('players');
      expect(tableNames).toContain('ships');
      expect(tableNames).toContain('ship_cargo');
      expect(tableNames).toContain('rule_sets');
      expect(tableNames).toContain('ledger');
      expect(tableNames).toContain('action_log');
      expect(tableNames).toContain('tick_state');
      expect(tableNames).toContain('refresh_tokens');
      expect(tableNames).toContain('schema_migrations');
    } finally {
      client.release();
    }
  });

  it('2. Sukses melakukan seed dunia dan idempoten jika dijalankan ulang', async () => {
    const client = await pool.connect();
    try {
      await client.query(`SET search_path TO ${testSchema}, public;`);

      await seedWorld(pool);

      const comCount = await client.query('SELECT count(*) FROM commodities');
      expect(Number(comCount.rows[0].count)).toBe(COMMODITIES_SEED.length);

      const portCount = await client.query('SELECT count(*) FROM ports');
      expect(Number(portCount.rows[0].count)).toBe(PORTS_SEED.length);

      const routeCount = await client.query('SELECT count(*) FROM routes');
      expect(Number(routeCount.rows[0].count)).toBe(ROUTES_SEED.length);
      expect(Number(routeCount.rows[0].count)).toBe(14); // 7 rute x 2 arah

      const marketCount = await client.query('SELECT count(*) FROM market');
      expect(Number(marketCount.rows[0].count)).toBe(MARKET_SEED.length);
      expect(Number(marketCount.rows[0].count)).toBe(24); // 6 pelabuhan x 4 komoditas

      // Jalankan seed kedua untuk menguji idempotensi
      await seedWorld(pool);

      const comCount2 = await client.query('SELECT count(*) FROM commodities');
      expect(Number(comCount2.rows[0].count)).toBe(COMMODITIES_SEED.length);
      const marketCount2 = await client.query('SELECT count(*) FROM market');
      expect(Number(marketCount2.rows[0].count)).toBe(24);
    } finally {
      client.release();
    }
  });

  it('3. Menegakkan check constraint integer dan batas validitas data', async () => {
    const client = await pool.connect();
    try {
      await client.query(`SET search_path TO ${testSchema}, public;`);

      // 3.1. Komoditas: base_price > 0
      await expect(
        client.query(`INSERT INTO commodities (id, code, base_price) VALUES (99, 'emas', 0)`),
      ).rejects.toThrow();

      // 3.2. Rute: ticks > 0
      await expect(
        client.query(`INSERT INTO routes (from_port, to_port, ticks) VALUES (1, 3, 0)`),
      ).rejects.toThrow();

      // 3.3. Pasar: stock >= 0
      await expect(
        client.query(`
          INSERT INTO market (port_id, commodity_id, stock, target, production, consumption, capacity, price)
          VALUES (1, 1, -1, 400, 20, 3, 1600, 70)
        `),
      ).rejects.toThrow();

      // 3.4. Pasar: stock <= capacity
      await expect(
        client.query(`
          INSERT INTO market (port_id, commodity_id, stock, target, production, consumption, capacity, price)
          VALUES (1, 1, 1601, 400, 20, 3, 1600, 70)
        `),
      ).rejects.toThrow();

      // 3.5. Pemain: coins >= 0
      await expect(
        client.query(`
          INSERT INTO players (email, password_hash, display_name, coins)
          VALUES ('bad@example.com', 'hash', 'BadPlayer', -10)
        `),
      ).rejects.toThrow();

      // 3.6. Kapal: status harus salah satu dari ('docked', 'sailing', 'grounded')
      const playerRes = await client.query<{ id: string }>(`
        INSERT INTO players (email, password_hash, display_name, coins)
        VALUES ('valid@example.com', 'hash', 'ValidPlayer', 1000)
        RETURNING id;
      `);
      const playerId = playerRes.rows[0].id;

      await expect(
        client.query(`
          INSERT INTO ships (player_id, name, capacity, status)
          VALUES (${playerId}, 'Kapal Terbang', 20, 'flying')
        `),
      ).rejects.toThrow();

      // 3.7. Kargo: qty >= 0
      const shipRes = await client.query<{ id: string }>(`
        INSERT INTO ships (player_id, name, capacity, status)
        VALUES (${playerId}, 'Kapal Dagang 1', 20, 'docked')
        RETURNING id;
      `);
      const shipId = shipRes.rows[0].id;

      await expect(
        client.query(`
          INSERT INTO ship_cargo (ship_id, commodity_id, qty)
          VALUES (${shipId}, 1, -5)
        `),
      ).rejects.toThrow();
    } finally {
      client.release();
    }
  });

  it('4. Menegakkan sifat append-only tabel ledger (tolak UPDATE, DELETE, dan TRUNCATE)', async () => {
    const client = await pool.connect();
    try {
      await client.query(`SET search_path TO ${testSchema}, public;`);

      const playerRes = await client.query<{ id: string }>(`
        SELECT id FROM players WHERE email = 'valid@example.com' LIMIT 1;
      `);
      const playerId = playerRes.rows[0].id;

      const ledgerRes = await client.query<{ id: string }>(`
        INSERT INTO ledger (player_id, tick_no, delta, reason)
        VALUES (${playerId}, 1, 1000, 'starter')
        RETURNING id;
      `);
      const ledgerId = ledgerRes.rows[0].id;
      expect(ledgerId).toBeDefined();

      // Tolak UPDATE
      await expect(
        client.query(`UPDATE ledger SET delta = 2000 WHERE id = ${ledgerId}`),
      ).rejects.toThrow(/append-only/i);

      // Tolak DELETE
      await expect(
        client.query(`DELETE FROM ledger WHERE id = ${ledgerId}`),
      ).rejects.toThrow(/append-only/i);

      // Tolak TRUNCATE
      await expect(
        client.query(`TRUNCATE TABLE ledger;`),
      ).rejects.toThrow(/append-only/i);

      const verifyRes = await client.query(`SELECT count(*) FROM ledger WHERE id = ${ledgerId}`);
      expect(Number(verifyRes.rows[0].count)).toBe(1);
    } finally {
      client.release();
    }
  });

  it('5. Pemeriksaan query konsistensi saldo vs ledger dan muatan vs kapasitas', async () => {
    const client = await pool.connect();
    try {
      await client.query(`SET search_path TO ${testSchema}, public;`);

      // 5.1. Konsistensi Saldo: players.coins == SUM(ledger.delta)
      const auditSaldoQuery = `
        SELECT p.id FROM players p
        LEFT JOIN (SELECT player_id, SUM(delta) s FROM ledger GROUP BY 1) l ON l.player_id = p.id
        WHERE p.coins <> COALESCE(l.s, 0);
      `;
      const auditSaldoRes = await client.query(auditSaldoQuery);
      expect(auditSaldoRes.rows.length).toBe(0);

      // 5.2. Konsistensi Muatan: SUM(ship_cargo.qty) <= ships.capacity
      const shipRes = await client.query<{ id: string }>(`
        SELECT id FROM ships WHERE name = 'Kapal Dagang 1' LIMIT 1;
      `);
      const shipId = shipRes.rows[0].id;

      await client.query(`
        INSERT INTO ship_cargo (ship_id, commodity_id, qty)
        VALUES (${shipId}, 1, 15);
      `);

      const auditCargoQuery = `
        SELECT s.id FROM ships s JOIN ship_cargo c ON c.ship_id = s.id
        GROUP BY s.id, s.capacity HAVING SUM(c.qty) > s.capacity;
      `;
      const auditCargoRes = await client.query(auditCargoQuery);
      expect(auditCargoRes.rows.length).toBe(0);
    } finally {
      client.release();
    }
  });
});
