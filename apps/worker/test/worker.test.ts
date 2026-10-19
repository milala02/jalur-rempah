import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import pg from 'pg';
import { WORLD_CONFIG } from '@jalur-rempah/shared';
import {
  stepWorld,
  WorldState,
  computeCanonicalStateHash,
} from '@jalur-rempah/econ';
import {
  compileDsl,
  createDslShipRuleDecider,
  RULE_TEMPLATES,
} from '@jalur-rempah/dsl';
import {
  createPool,
  getDatabaseUrl,
  replaceDatabaseInUrl,
  runMigrations,
  seedWorld,
  checkDatabaseConsistency,
  createApiServer,
  loadWorldSnapshotFromDb,
} from '../../api/src/index.js';
import {
  acquireWorkerAdvisoryLock,
  executeSingleWorldTick,
  createInitialWorkerMetrics,
} from '../src/index.js';

describe('M4 — Worker Tick Loop: Advisory Lock, Kesetaraan state_hash Worker DB == Simulator, Crash Recovery, & Benchmark 100 Kapal', () => {
  const adminDbUrl = getDatabaseUrl();
  const testDbName = `test_worker_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const testDbUrl = replaceDatabaseInUrl(adminDbUrl, testDbName);

  let adminPool: pg.Pool;
  let testPool: pg.Pool;

  beforeAll(async () => {
    adminPool = createPool(adminDbUrl);
    await adminPool.query(`CREATE DATABASE ${testDbName};`);
    testPool = createPool(testDbUrl);

    const dbRes = await testPool.query<{ db_name: string }>(
      'SELECT current_database() AS db_name',
    );
    expect(dbRes.rows[0]?.db_name).toBe(testDbName);

    await runMigrations(testPool);
    await seedWorld(testPool);
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

  it('1. Kunci worker tunggal (pg_try_advisory_lock pada koneksi khusus): worker kedua ditolak saat kunci dipegang', async () => {
    const lockKey = 77889911;
    const handle1 = await acquireWorkerAdvisoryLock(testPool, lockKey);
    expect(handle1).not.toBeNull();
    expect(await handle1!.verifyAlive()).toBe(true);

    // Worker kedua mencoba mengambil kunci yang sama -> harus mengembalikan null
    const handle2 = await acquireWorkerAdvisoryLock(testPool, lockKey);
    expect(handle2).toBeNull();

    // Setelah handle1 dilepas, worker kedua berhasil memperoleh kunci
    await handle1!.release();
    const handle3 = await acquireWorkerAdvisoryLock(testPool, lockKey);
    expect(handle3).not.toBeNull();
    await handle3!.release();
  });

  it('2. Kesetaraan state_hash (docs/09 & docs/10): hasil tick Worker (via PostgreSQL) == hasil stepWorld murni di memori selama 20 tick', async () => {
    const api = createApiServer(testPool);

    // Buat 2 pemain beserta kapal dan simpan aturan DSL aktif
    const r1 = await api.inject<{
      ship: { id: number };
      access_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'w1@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Kapten_Satu',
      },
    });
    const r2 = await api.inject<{
      ship: { id: number };
      access_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'w2@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Kapten_Dua',
      },
    });
    expect(r1.statusCode).toBe(201);
    expect(r2.statusCode).toBe(201);

    const put1 = await api.inject({
      method: 'PUT',
      url: `/v1/ships/${r1.body.ship.id}/rules`,
      headers: { authorization: `Bearer ${r1.body.access_token}` },
      body: { base_version: 0, source: RULE_TEMPLATES[0]!.source },
    });
    const put2 = await api.inject({
      method: 'PUT',
      url: `/v1/ships/${r2.body.ship.id}/rules`,
      headers: { authorization: `Bearer ${r2.body.access_token}` },
      body: { base_version: 0, source: RULE_TEMPLATES[1]!.source },
    });
    expect(put1.statusCode).toBe(200);
    expect(put2.statusCode).toBe(200);

    // Ambil keadaan awal dari DB untuk dijalankan paralel di simulator memori murni
    const pureState: WorldState = await loadWorldSnapshotFromDb(testPool);
    const prog1 = compileDsl(RULE_TEMPLATES[0]!.source).ast!;
    const prog2 = compileDsl(RULE_TEMPLATES[1]!.source).ast!;
    const pureDecider = createDslShipRuleDecider(
      new Map([
        [BigInt(r1.body.ship.id), prog1],
        [BigInt(r2.body.ship.id), prog2],
      ]),
    );

    const metrics = createInitialWorkerMetrics();
    for (let tick = 1; tick <= 20; tick++) {
      // 1. Jalankan di simulator memori murni
      const { state: expectedState } = stepWorld(
        pureState,
        pureDecider,
        WORLD_CONFIG,
        101,
        true,
      );

      // 2. Jalankan di Worker PostgreSQL
      const dbTick = await executeSingleWorldTick(testPool, {
        config: WORLD_CONFIG,
        worldSeed: 101,
        metrics,
      });

      expect(dbTick.tickNo).toBe(tick);
      expect(dbTick.stateHash).toBe(expectedState.stateHash);
    }

    // Verifikasi konsistensi database (ledger, muatan, konservasi uang global)
    const consistency = await checkDatabaseConsistency(testPool);
    expect(consistency.valid).toBe(true);
    expect(metrics.ticks_completed_total).toBe(20);
    expect(metrics.invariant_failures_total).toBe(0);
  });

  it('3. Pemulihan setelah kegagalan / crash di tengah tick: rollback transaksi menjaga DB utuh dan tick berikutnya lanjut dari max(tick_no) + 1', async () => {
    const hashBeforeRes = await testPool.query<{
      tick_no: string;
      state_hash: string;
    }>(
      `SELECT tick_no::text, state_hash FROM public.tick_state ORDER BY tick_no DESC LIMIT 1`,
    );
    const tickBefore = Number(hashBeforeRes.rows[0]?.tick_no ?? '0');

    // Simulasikan crash mendadak tepat sebelum COMMIT pada tick ke-21
    await expect(
      executeSingleWorldTick(testPool, {
        config: WORLD_CONFIG,
        worldSeed: 101,
        beforeCommitHook: () => {
          throw new Error('SIMULATED_KILL_9_BEFORE_COMMIT');
        },
      }),
    ).rejects.toThrow(/SIMULATED_KILL_9_BEFORE_COMMIT/);

    // Pastikan tidak ada efek setengah jalan dan konsistensi DB tetap 100% valid
    const consistencyAfterCrash = await checkDatabaseConsistency(testPool);
    expect(consistencyAfterCrash.valid).toBe(true);

    const tickAfterCrashRes = await testPool.query<{ max_tick: string }>(
      `SELECT COALESCE(MAX(tick_no), 0)::text AS max_tick FROM public.tick_state`,
    );
    expect(Number(tickAfterCrashRes.rows[0]?.max_tick)).toBe(tickBefore);

    // Jalankan kembali tick normal -> harus lanjut tepat di tickBefore + 1
    const recoveredTick = await executeSingleWorldTick(testPool, {
      config: WORLD_CONFIG,
      worldSeed: 101,
      flushUpkeepImmediately: true,
    });
    expect(recoveredTick.tickNo).toBe(tickBefore + 1);

    const finalConsistency = await checkDatabaseConsistency(testPool);
    expect(finalConsistency.valid).toBe(true);
    expect(finalConsistency.ledgerMismatchPlayerIds).toEqual([]);
  });

  it('4. Benchmark performa 100 kapal dengan aturan DSL: durasi p95 jauh di bawah 20% durasi tick (< 6.000 ms)', () => {
    const players = new Map();
    const ships = new Map();
    const programsByShip = new Map();

    const compiledTemplates = RULE_TEMPLATES.map(
      (t) => compileDsl(t.source).ast!,
    );

    for (let i = 1; i <= 100; i++) {
      const id = BigInt(i);
      players.set(id, {
        id,
        coins: 1000n,
        initialCoins: 1000n,
        ledgerSum: 1000n,
        lastRescueTick: null,
        rescueCount: 0,
      });
      ships.set(id, {
        id,
        playerId: id,
        capacity: 35,
        status: 'docked' as const,
        portId: ((i - 1) % 6) + 1,
        destPort: null,
        arriveTick: null,
        cargo: new Map([
          [1, 0n],
          [2, 0n],
          [3, 0n],
          [4, 0n],
        ]),
      });
      programsByShip.set(
        id,
        compiledTemplates[(i - 1) % compiledTemplates.length]!,
      );
    }

    const ports = new Map();
    for (let p = 1; p <= 6; p++) {
      ports.set(p, {
        id: p,
        code: `port_${p}`,
        name: `Port ${p}`,
        treasury: 50000n,
        initialTreasury: 50000n,
      });
    }

    const markets = new Map();
    const basePrices: Record<number, bigint> = {
      1: 70n,
      2: 90n,
      3: 20n,
      4: 45n,
    };
    for (let p = 1; p <= 6; p++) {
      for (let c = 1; c <= 4; c++) {
        markets.set(`${p}:${c}`, {
          port_id: p,
          commodity_id: c,
          stock: 400n,
          target: 400n,
          production: 5n,
          consumption: 5n,
          capacity: 1600n,
          price: basePrices[c]!,
        });
      }
    }

    const state: WorldState = {
      tickNo: 0,
      players,
      ports,
      markets,
      ships,
      cumulativeUpkeepSink: 0n,
      cumulativeSource: 0n,
      stateHash: '',
    };
    state.stateHash = computeCanonicalStateHash(state);

    const decider = createDslShipRuleDecider(programsByShip);
    const durations: number[] = [];

    for (let t = 0; t < 50; t++) {
      const t0 = Date.now();
      const { events } = stepWorld(state, decider, WORLD_CONFIG, 101, true);
      durations.push(Date.now() - t0);
      expect(events.invariantCheck.valid).toBe(true);
    }

    durations.sort((a, b) => a - b);
    const p95 = durations[Math.floor(durations.length * 0.95)] ?? 0;
    const maxAllowedMs = WORLD_CONFIG.TICK_SECONDS * 1000 * 0.2; // 6.000 ms
    expect(p95).toBeLessThanOrEqual(maxAllowedMs);
  });
});
