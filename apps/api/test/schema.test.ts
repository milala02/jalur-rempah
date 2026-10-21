import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import pg from 'pg';
import {
  createPool,
  getDatabaseUrl,
  getDatabaseNameFromUrl,
  replaceDatabaseInUrl,
} from '../src/db/connection.js';
import { runMigrations } from '../src/db/migrate.js';
import { seedWorld } from '../src/db/seed.js';
import {
  COMMODITIES_SEED,
  PORTS_SEED,
  ROUTES_SEED,
  MARKET_SEED,
  WORLD_CONFIG,
} from '@jalur-rempah/shared';

const EXPECTED_GAME_TABLES = [
  'countries',
  'commodities',
  'ports',
  'routes',
  'market',
  'market_history',
  'players',
  'ships',
  'ship_cargo',
  'rule_sets',
  'ledger',
  'action_log',
  'tick_state',
  'refresh_tokens',
  'economy_sources_sinks',
  'port_intel',
  'ship_memory',
  'guilds',
  'guild_members',
  'trade_contracts',
  'world_events',
  'p2p_orders',
  'anomaly_alerts',
  'combat_logs',
  'quests',
  'player_quests',
  'schema_migrations',
] as const;

async function verifyAndLogActiveDatabase(
  pool: pg.Pool,
  testLabel: string,
  expectedDbName: string,
): Promise<string> {
  const res = await pool.query<{ db_name: string }>(
    'SELECT current_database() AS db_name',
  );
  const actualDbName = res.rows[0]?.db_name ?? '';
  console.log(`[TEST-DB] ${testLabel} -> berjalan di database: ${actualDbName}`);
  expect(actualDbName).toBe(expectedDbName);
  return actualDbName;
}

describe('M0 & M1 — Database Schema, Migrations (0001 + 0002), Seed, & Isolasi DB', () => {
  const adminDbUrl = getDatabaseUrl();
  const adminDbName = getDatabaseNameFromUrl(adminDbUrl);
  const testDbName = `test_m0_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const testDbUrl = replaceDatabaseInUrl(adminDbUrl, testDbName);

  let adminPool: pg.Pool;
  let testPool: pg.Pool;
  let mainGameTablesBefore: string[] = [];

  beforeAll(async () => {
    adminPool = createPool(adminDbUrl);
    const baselineTables = await adminPool.query<{ table_name: string }>(
      `SELECT table_name
       FROM information_schema.tables
       WHERE table_schema = 'public'
         AND table_name = ANY($1::text[])
       ORDER BY table_name`,
      [EXPECTED_GAME_TABLES as unknown as string[]],
    );
    mainGameTablesBefore = baselineTables.rows.map((row) => row.table_name);
    await adminPool.query(`CREATE DATABASE ${testDbName};`);
    testPool = createPool(testDbUrl);
  });

  afterAll(async () => {
    if (testPool) {
      await testPool.end();
    }
    if (adminPool) {
      try {
        await adminPool.query(
          `SELECT pg_terminate_backend(pid)
           FROM pg_stat_activity
           WHERE datname = $1 AND pid <> pg_backend_pid();`,
          [testDbName],
        );
        await adminPool.query(`DROP DATABASE IF EXISTS ${testDbName};`);
      } finally {
        await adminPool.end();
      }
    }
  });

  it('1. Variasi tanpa tabel public: query dan seedWorld gagal eksplisit (42P01) sebelum migrasi', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 1 (Variasi tanpa tabel public)',
      testDbName,
    );

    const tablesBefore = await testPool.query<{ table_name: string }>(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public';
    `);
    expect(tablesBefore.rows.length).toBe(0);

    let capturedCode = '';
    let capturedMessage = '';
    try {
      await testPool.query('SELECT count(*) FROM public.commodities');
    } catch (err) {
      const pgErr = err as { code?: string; message?: string };
      capturedCode = pgErr.code ?? '';
      capturedMessage = pgErr.message ?? '';
    }

    console.log(
      `[VARIASI-TANPA-PUBLIC] db=${testDbName} code=${capturedCode} message="${capturedMessage}"`,
    );
    expect(capturedCode).toBe('42P01');
    expect(capturedMessage).toMatch(/public\.commodities/i);

    await expect(seedWorld(testPool)).rejects.toThrow(/public\.commodities/i);
  });

  it('2. Sukses menjalankan migrasi 0001 dan 0002 pada database tes bersih serta idempoten saat diulang', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 2 (Migrasi 0001 + 0002 & idempotensi)',
      testDbName,
    );

    const appliedFirst = await runMigrations(testPool);
    expect(appliedFirst).toContain('0001_init');
    expect(appliedFirst).toContain('0002_port_treasury_and_sinks');
    expect(appliedFirst).toContain('0003_port_income_and_ledger_compaction');
    expect(appliedFirst).toContain('0004_phase2_features');
    expect(appliedFirst).toContain('0005_legal_status_p2p_anticheat');
    expect(appliedFirst).toContain('0006_global_expansion_and_levels');
    expect(appliedFirst).toContain('0007_naval_combat_and_pirates');
    expect(appliedFirst).toContain('0008_quests_and_tutorial');
    expect(appliedFirst).toContain('0009_guilds_treasury_and_world_boss');
    expect(appliedFirst).toContain('0010_add_loot_summary_to_combat_logs');

    // Eksekusi ulang migrasi pada DB yang sama harus menghasilkan [] (idempoten)
    const appliedSecond = await runMigrations(testPool);
    expect(appliedSecond).toEqual([]);

    const tablesRes = await testPool.query<{ table_name: string }>(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public';
    `);
    const tableNames = tablesRes.rows.map((r) => r.table_name);

    for (const expectedTable of EXPECTED_GAME_TABLES) {
      expect(tableNames).toContain(expectedTable);
    }
  });

  it('3. Pembuktian isolasi: setelah migrasi di DB tes, tabel tidak ada di DB utama', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 3a (Verifikasi sisi DB tes)',
      testDbName,
    );
    await verifyAndLogActiveDatabase(
      adminPool,
      'Tes 3b (Verifikasi sisi DB utama)',
      adminDbName,
    );

    expect(testDbName).not.toBe(adminDbName);

    const mainTablesRes = await adminPool.query<{ table_name: string }>(
      `SELECT table_name
       FROM information_schema.tables
       WHERE table_schema = 'public'
         AND table_name = ANY($1::text[])
       ORDER BY table_name;`,
      [EXPECTED_GAME_TABLES as unknown as string[]],
    );

    console.log(
      `[ISOLASI-DB] DB utama (${adminDbName}) baseline=${mainGameTablesBefore.length}, sekarang=${mainTablesRes.rows.length}; DB tes (${testDbName}) terisolasi penuh.`,
    );
    expect(mainTablesRes.rows.map((row) => row.table_name)).toEqual(
      mainGameTablesBefore,
    );
  });

  it('4. Sukses melakukan seed dunia (termasuk kas pelabuhan) dan idempoten jika dijalankan ulang', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 4 (Seed dunia & kas pelabuhan)',
      testDbName,
    );

    await seedWorld(testPool);

    const comCount = await testPool.query<{ count: string }>(
      'SELECT count(*) AS count FROM public.commodities WHERE id <= 4',
    );
    expect(Number(comCount.rows[0]?.count)).toBe(COMMODITIES_SEED.length);

    const portRes = await testPool.query<{
      id: number;
      treasury: string;
      initial_treasury: string;
    }>('SELECT id, treasury, initial_treasury FROM public.ports WHERE id <= 6 ORDER BY id ASC');
    expect(portRes.rows.length).toBe(PORTS_SEED.length);
    for (const row of portRes.rows) {
      expect(BigInt(row.treasury)).toBe(WORLD_CONFIG.INITIAL_PORT_TREASURY);
      expect(BigInt(row.initial_treasury)).toBe(WORLD_CONFIG.INITIAL_PORT_TREASURY);
    }

    const routeCount = await testPool.query<{ count: string }>(
      'SELECT count(*) AS count FROM public.routes',
    );
    expect(Number(routeCount.rows[0]?.count)).toBe(ROUTES_SEED.length);
    expect(Number(routeCount.rows[0]?.count)).toBe(14);

    const marketCount = await testPool.query<{ count: string }>(
      'SELECT count(*) AS count FROM public.market',
    );
    expect(Number(marketCount.rows[0]?.count)).toBe(MARKET_SEED.length);
    expect(Number(marketCount.rows[0]?.count)).toBe(24);

    // Verifikasi keseimbangan produksi = konsumsi global per komoditas (total_prod = 23, total_cons = 23)
    const balanceRes = await testPool.query<{
      commodity_id: number;
      total_prod: string;
      total_cons: string;
    }>(`
      SELECT commodity_id,
             SUM(production) AS total_prod,
             SUM(consumption) AS total_cons
      FROM public.market
      GROUP BY commodity_id
      ORDER BY commodity_id ASC;
    `);
    expect(balanceRes.rows.length).toBe(COMMODITIES_SEED.length);
    for (const row of balanceRes.rows) {
      expect(Number(row.total_prod)).toBe(23);
      expect(Number(row.total_cons)).toBe(23);
    }

    // Jalankan seed kedua untuk menguji idempotensi
    await seedWorld(testPool);

    const comCount2 = await testPool.query<{ count: string }>(
      'SELECT count(*) AS count FROM public.commodities WHERE id <= 4',
    );
    expect(Number(comCount2.rows[0]?.count)).toBe(COMMODITIES_SEED.length);

    const marketCount2 = await testPool.query<{ count: string }>(
      'SELECT count(*) AS count FROM public.market',
    );
    expect(Number(marketCount2.rows[0]?.count)).toBe(24);
  });

  it('5. Menegakkan check constraint integer (termasuk ports.treasury >= 0) dan batas validitas data', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 5 (Check constraints & validitas data)',
      testDbName,
    );

    // 5.1. Komoditas: base_price > 0
    await expect(
      testPool.query(
        `INSERT INTO public.commodities (id, code, base_price) VALUES (99, 'emas', 0)`,
      ),
    ).rejects.toThrow();

    // 5.2. Pelabuhan: treasury >= 0
    await expect(
      testPool.query(`UPDATE public.ports SET treasury = -1 WHERE id = 1`),
    ).rejects.toThrow();

    // 5.3. Rute: ticks > 0
    await expect(
      testPool.query(
        `INSERT INTO public.routes (from_port, to_port, ticks) VALUES (1, 3, 0)`,
      ),
    ).rejects.toThrow();

    // 5.4. Pasar: stock >= 0
    await expect(
      testPool.query(`
        INSERT INTO public.market (port_id, commodity_id, stock, target, production, consumption, capacity, price)
        VALUES (1, 1, -1, 400, 20, 3, 1600, 70)
      `),
    ).rejects.toThrow();

    // 5.5. Pasar: stock <= capacity
    await expect(
      testPool.query(`
        INSERT INTO public.market (port_id, commodity_id, stock, target, production, consumption, capacity, price)
        VALUES (1, 1, 1601, 400, 20, 3, 1600, 70)
      `),
    ).rejects.toThrow();

    // 5.6. Pemain: coins >= 0
    await expect(
      testPool.query(`
        INSERT INTO public.players (email, password_hash, display_name, coins)
        VALUES ('bad@example.com', 'hash', 'BadPlayer', -10)
      `),
    ).rejects.toThrow();

    // 5.7. Kapal: status harus salah satu dari ('docked', 'sailing', 'grounded')
    const playerRes = await testPool.query<{ id: string }>(`
      INSERT INTO public.players (email, password_hash, display_name, coins)
      VALUES ('valid@example.com', 'hash', 'ValidPlayer', 1000)
      RETURNING id;
    `);
    const playerId = playerRes.rows[0]?.id;
    expect(playerId).toBeDefined();

    await expect(
      testPool.query(
        `INSERT INTO public.ships (player_id, name, capacity, status)
         VALUES ($1, 'Kapal Terbang', 20, 'flying')`,
        [playerId],
      ),
    ).rejects.toThrow();

    // 5.8. Kargo: qty >= 0
    const shipRes = await testPool.query<{ id: string }>(
      `INSERT INTO public.ships (player_id, name, capacity, status)
       VALUES ($1, 'Kapal Dagang 1', 20, 'docked')
       RETURNING id;`,
      [playerId],
    );
    const shipId = shipRes.rows[0]?.id;
    expect(shipId).toBeDefined();

    await expect(
      testPool.query(
        `INSERT INTO public.ship_cargo (ship_id, commodity_id, qty)
         VALUES ($1, 1, -5)`,
        [shipId],
      ),
    ).rejects.toThrow();
  });

  it('6. Menegakkan sifat append-only tabel ledger (tolak UPDATE, DELETE, dan TRUNCATE)', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 6 (Trigger append-only ledger)',
      testDbName,
    );

    const playerRes = await testPool.query<{ id: string }>(`
      SELECT id FROM public.players WHERE email = 'valid@example.com' LIMIT 1;
    `);
    const playerId = playerRes.rows[0]?.id;
    expect(playerId).toBeDefined();

    const ledgerRes = await testPool.query<{ id: string }>(
      `INSERT INTO public.ledger (player_id, tick_no, delta, reason)
       VALUES ($1, 1, 1000, 'starter')
       RETURNING id;`,
      [playerId],
    );
    const ledgerId = ledgerRes.rows[0]?.id;
    expect(ledgerId).toBeDefined();

    // Tolak UPDATE (row-level trigger)
    await expect(
      testPool.query(`UPDATE public.ledger SET delta = 2000 WHERE id = $1`, [
        ledgerId,
      ]),
    ).rejects.toThrow(/append-only/i);

    // Tolak DELETE (row-level trigger)
    await expect(
      testPool.query(`DELETE FROM public.ledger WHERE id = $1`, [ledgerId]),
    ).rejects.toThrow(/append-only/i);

    // Tolak TRUNCATE (statement-level trigger)
    await expect(
      testPool.query(`TRUNCATE TABLE public.ledger;`),
    ).rejects.toThrow(/append-only/i);

    const verifyRes = await testPool.query<{ count: string }>(
      `SELECT count(*) AS count FROM public.ledger WHERE id = $1`,
      [ledgerId],
    );
    expect(Number(verifyRes.rows[0]?.count)).toBe(1);
  });

  it('7. Pemeriksaan konsistensi saldo vs ledger, muatan vs kapasitas, dan konservasi uang global (ADR-009)', async () => {
    await verifyAndLogActiveDatabase(
      testPool,
      'Tes 7 (Kueri konsistensi saldo, muatan, & konservasi uang)',
      testDbName,
    );

    const playerRes = await testPool.query<{ id: string }>(`
      SELECT id FROM public.players WHERE email = 'valid@example.com' LIMIT 1;
    `);
    const playerId = playerRes.rows[0]?.id;
    expect(playerId).toBeDefined();

    // Simulasikan 1 transaksi beli (gross 70 + fee 2 = 72 pindah dari player ke kas pelabuhan 1)
    // dan 1 biaya perawatan kapal (upkeep 1 koin keluar sebagai sink)
    await testPool.query('BEGIN');
    await testPool.query(
      `UPDATE public.players SET coins = coins - 72 WHERE id = $1`,
      [playerId],
    );
    await testPool.query(
      `UPDATE public.ports SET treasury = treasury + 72 WHERE id = 1`,
    );
    await testPool.query(
      `INSERT INTO public.ledger (player_id, tick_no, delta, reason)
       VALUES ($1, 2, -72, 'buy')`,
      [playerId],
    );

    await testPool.query(
      `UPDATE public.players SET coins = coins - 1 WHERE id = $1`,
      [playerId],
    );
    await testPool.query(
      `INSERT INTO public.ledger (player_id, tick_no, delta, reason)
       VALUES ($1, 2, -1, 'upkeep')`,
      [playerId],
    );
    await testPool.query('COMMIT');

    // 7.1. Konsistensi Saldo: players.coins == SUM(ledger.delta)
    const auditSaldoQuery = `
      SELECT p.id FROM public.players p
      LEFT JOIN (SELECT player_id, SUM(delta) s FROM public.ledger GROUP BY 1) l ON l.player_id = p.id
      WHERE p.coins <> COALESCE(l.s, 0);
    `;
    const auditSaldoRes = await testPool.query(auditSaldoQuery);
    expect(auditSaldoRes.rows.length).toBe(0);

    // 7.2. Konsistensi Muatan: SUM(ship_cargo.qty) <= ships.capacity
    const shipRes = await testPool.query<{ id: string }>(`
      SELECT id FROM public.ships WHERE name = 'Kapal Dagang 1' LIMIT 1;
    `);
    const shipId = shipRes.rows[0]?.id;
    expect(shipId).toBeDefined();

    await testPool.query(
      `INSERT INTO public.ship_cargo (ship_id, commodity_id, qty)
       VALUES ($1, 1, 15);`,
      [shipId],
    );

    const auditCargoQuery = `
      SELECT s.id FROM public.ships s JOIN public.ship_cargo c ON c.ship_id = s.id
      GROUP BY s.id, s.capacity HAVING SUM(c.qty) > s.capacity;
    `;
    const auditCargoRes = await testPool.query(auditCargoQuery);
    expect(auditCargoRes.rows.length).toBe(0);

    // Simulasikan pendapatan pelabuhan (source = 500) ke kas pelabuhan 6 (Batavia)
    await testPool.query('BEGIN');
    await testPool.query(
      `UPDATE public.ports SET treasury = treasury + 500 WHERE id = 6`,
    );
    await testPool.query(
      `INSERT INTO public.economy_sources_sinks (tick_no, kind, reason, port_id, amount)
       VALUES (2, 'source', 'port_income', 6, 500)`,
    );
    await testPool.query('COMMIT');

    // 7.3. Konservasi Uang Global (ADR-009 & ADR-010):
    // total_player_coins + total_port_treasury + cumulative_upkeep_sink == total_initial_money + cumulative_source
    const moneyAuditRes = await testPool.query<{
      total_player_coins: string;
      total_port_treasury: string;
      cumulative_upkeep_sink: string;
      total_initial_money: string;
      cumulative_source: string;
    }>(`SELECT * FROM public.economy_money_supply_audit`);
    const auditRow = moneyAuditRes.rows[0];
    expect(auditRow).toBeDefined();

    const lhs =
      BigInt(auditRow?.total_player_coins ?? '0') +
      BigInt(auditRow?.total_port_treasury ?? '0') +
      BigInt(auditRow?.cumulative_upkeep_sink ?? '0');
    const rhs =
      BigInt(auditRow?.total_initial_money ?? '0') +
      BigInt(auditRow?.cumulative_source ?? '0');
    expect(lhs).toBe(rhs);

    // 7.4. Pengujian agregasi blok upkeep (A5 / ADR-011):
    // Akumulasi 5 tick upkeep pada unflushed_upkeep tetap menjaga konservasi uang global,
    // dan saat di-flush sebagai satu baris ringkasan ke ledger, players.coins == SUM(ledger.delta) eksak.
    await testPool.query('BEGIN');
    await testPool.query(
      `UPDATE public.players
       SET coins = coins - 5,
           unflushed_upkeep = unflushed_upkeep + 5,
           cumulative_upkeep_paid = cumulative_upkeep_paid + 5
       WHERE id = $1`,
      [playerId],
    );
    await testPool.query('COMMIT');

    // Sebelum flush: p.coins + p.unflushed_upkeep == SUM(ledger.delta)
    const midBatchRes = await testPool.query(
      `SELECT p.id FROM public.players p
       LEFT JOIN (SELECT player_id, SUM(delta) s FROM public.ledger GROUP BY 1) l ON l.player_id = p.id
       WHERE (p.coins + p.unflushed_upkeep) <> COALESCE(l.s, 0);`,
    );
    expect(midBatchRes.rows.length).toBe(0);

    // Flush ringkasan blok ke ledger dan reset unflushed_upkeep = 0
    await testPool.query('BEGIN');
    await testPool.query(
      `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
       VALUES ($1, 7, -5, 'upkeep', '{"from_tick":3,"to_tick":7,"ticks_count":5}'::jsonb)`,
      [playerId],
    );
    await testPool.query(
      `UPDATE public.players SET unflushed_upkeep = 0 WHERE id = $1`,
      [playerId],
    );
    await testPool.query('COMMIT');

    // Setelah flush: invarian p.coins == SUM(ledger.delta) kembali terpenuhi
    const afterFlushRes = await testPool.query(auditSaldoQuery);
    expect(afterFlushRes.rows.length).toBe(0);
  });
});
