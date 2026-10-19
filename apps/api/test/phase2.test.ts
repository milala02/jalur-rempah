import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import pg from 'pg';
import {
  createPool,
  getDatabaseUrl,
  replaceDatabaseInUrl,
  runMigrations,
  seedWorld,
  checkDatabaseConsistency,
  createApiServer,
  ApiServer,
} from '../src/index.js';
import {
  executeSingleWorldTick,
  evaluateBetaMetrics,
} from '../../worker/src/index.js';

describe('Phase 2 (Setelah MVP) — Multi-Kapal, Kabut Informasi (ADR-012), Memori Kapal, Serikat Dagang, Kontrak, Musim/SSE/ETag, & Anonimisasi Akun', () => {
  const adminDbUrl = getDatabaseUrl();
  const testDbName = `test_phase2_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const testDbUrl = replaceDatabaseInUrl(adminDbUrl, testDbName);

  let adminPool: pg.Pool;
  let testPool: pg.Pool;
  let api: ApiServer;

  let tokenA = '';
  let shipA1 = 0;
  let tokenB = '';
  let shipB1 = 0;

  beforeAll(async () => {
    adminPool = createPool(adminDbUrl);
    await adminPool.query(`CREATE DATABASE ${testDbName};`);
    testPool = createPool(testDbUrl);

    await runMigrations(testPool);
    await seedWorld(testPool);

    api = createApiServer(testPool, {
      jwtSecret: 'test-secret-for-phase2-suite',
      minClientVersion: '0.1.0',
    });
  });

  afterAll(async () => {
    if (api) {
      await api.close();
    }
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

  it('1. ETag / If-None-Match (304 Not Modified), SSE /v1/stream, dan Musim/Event Dunia (/v1/events)', async () => {
    const worldRes = await api.inject<{
      tick_no: number;
      season: { season_code: string };
    }>({
      method: 'GET',
      url: '/v1/world',
    });
    expect(worldRes.statusCode).toBe(200);
    expect(worldRes.headers['etag']).toBeDefined();
    expect(worldRes.body.season.season_code).toBe('muson_barat');

    // Permintaan ulang dengan If-None-Match yang sama menghasilkan 304 Not Modified
    const cachedRes = await api.inject({
      method: 'GET',
      url: '/v1/world',
      headers: { 'if-none-match': worldRes.headers['etag'] },
    });
    expect(cachedRes.statusCode).toBe(304);
    expect(cachedRes.rawBody).toBe('');

    // Endpoint SSE /v1/stream mengembalikan format text/event-stream
    const sseRes = await api.inject<{ event: string }>({
      method: 'GET',
      url: '/v1/stream',
    });
    expect(sseRes.statusCode).toBe(200);
    expect(sseRes.headers['content-type']).toContain('text/event-stream');
    expect(sseRes.rawBody).toContain('event: tick');

    // Endpoint /v1/events
    const evRes = await api.inject<{
      current_season: { season_code: string };
      items: unknown[];
    }>({
      method: 'GET',
      url: '/v1/events',
    });
    expect(evRes.statusCode).toBe(200);
    expect(evRes.body.current_season.season_code).toBe('muson_barat');
  });

  it('2. Kabut Informasi (GET /v1/intel), Ekstensi DSL (biar, simpan/ambil, harga_terakhir, musim) pada Worker Tick', async () => {
    const regA = await api.inject<{
      access_token: string;
      ship: { id: number };
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'nahkoda_a@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Nahkoda_A',
      },
    });
    expect(regA.statusCode).toBe(201);
    tokenA = regA.body.access_token;
    shipA1 = regA.body.ship.id;

    const regB = await api.inject<{
      access_token: string;
      ship: { id: number };
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'nahkoda_b@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Nahkoda_B',
      },
    });
    expect(regB.statusCode).toBe(201);
    tokenB = regB.body.access_token;
    shipB1 = regB.body.ship.id;

    // Saat daftar, pemain A langsung memiliki intel awal untuk pelabuhan Banda (port_id = 1, 4 komoditas)
    const intel0 = await api.inject<{
      items: Array<{ port_code: string; commodity_code: string; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/intel',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(intel0.statusCode).toBe(200);
    expect(intel0.body.items.length).toBe(4);
    expect(intel0.body.items.every((i) => i.port_code === 'banda')).toBe(true);

    // Simpan aturan Phase 2 pada kapal A1 menggunakan `biar`, `simpan/ambil`, `harga_terakhir`, dan `musim()`
    const ruleSrc = `
      aturan catat_memori:
        biar h_pala = harga(pala)
        jika di(Banda) dan ambil(0) == 0 dan musim() >= 1
        maka simpan(0, h_pala)

      aturan beli_dengan_memori:
        biar patokan = ambil(0)
        biar target = harga_terakhir(Banda, pala)
        jika di(Banda) dan patokan > 0 dan target <= patokan
        maka beli(pala, 5)
    `;
    const putRule = await api.inject<{ version: number }>({
      method: 'PUT',
      url: `/v1/ships/${shipA1}/rules`,
      headers: { authorization: `Bearer ${tokenA}` },
      body: { source: ruleSrc, base_version: 0 },
    });
    expect(putRule.statusCode).toBe(200);
    expect(putRule.body.version).toBe(1);

    // Tick 1: aturan catat_memori cocok -> menyimpan harga pala Banda ke slot 0
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });

    const memCheck = await testPool.query<{ slot: number; val: string }>(
      `SELECT slot, val::text FROM public.ship_memory WHERE ship_id = $1`,
      [shipA1],
    );
    expect(memCheck.rows.length).toBe(1);
    expect(Number(memCheck.rows[0]?.val ?? '0')).toBeGreaterThan(0);

    // Tick 2: ambil(0) > 0 -> aturan beli_dengan_memori dieksekusi -> membeli 5 pala!
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });

    const shipRes = await api.inject<{
      cargo: Array<{ commodity: string; qty: number }>;
    }>({
      method: 'GET',
      url: `/v1/ships/${shipA1}`,
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(shipRes.statusCode).toBe(200);
    const palaCargo = shipRes.body.cargo.find((c) => c.commodity === 'pala');
    expect(palaCargo?.qty).toBe(5);
  });

  it('3. Serikat Dagang Ringan (/v1/guilds) & Kontrak Pengiriman (/v1/contracts) dengan Escrow Konservasi Uang', async () => {
    // Pemain A mendirikan serikat dagang
    const createGuild = await api.inject<{
      id: number;
      code: string;
      role: string;
    }>({
      method: 'POST',
      url: '/v1/guilds',
      headers: { authorization: `Bearer ${tokenA}` },
      body: {
        code: 'rempah_jaya',
        name: 'Serikat Rempah Jaya',
        description: 'Armada niaga Maluku-Jawa',
      },
    });
    expect(createGuild.statusCode).toBe(201);
    expect(createGuild.body.code).toBe('rempah_jaya');

    // Pemain B bergabung ke serikat dagang tersebut
    const joinGuild = await api.inject<{ code: string; role: string }>({
      method: 'POST',
      url: '/v1/guilds/rempah_jaya/join',
      headers: { authorization: `Bearer ${tokenB}` },
    });
    expect(joinGuild.statusCode).toBe(200);
    expect(joinGuild.body.role).toBe('member');

    const listGuilds = await api.inject<{
      items: Array<{ code: string; member_count: number }>;
    }>({
      method: 'GET',
      url: '/v1/guilds',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(listGuilds.statusCode).toBe(200);
    expect(listGuilds.body.items[0]?.member_count).toBe(2);

    // Pemain B membuat kontrak pengiriman 3 unit pala di Banda (port_id = 1) dengan imbalan 300 koin
    const createContract = await api.inject<{
      id: number;
      status: string;
      reward_coins: number;
    }>({
      method: 'POST',
      url: '/v1/contracts',
      headers: { authorization: `Bearer ${tokenB}` },
      body: {
        port_id: 1,
        commodity_id: 1, // pala
        qty: 3,
        reward_coins: 300,
      },
    });
    expect(createContract.statusCode).toBe(201);
    const contractId = createContract.body.id;

    // Pastikan konservasi uang tetap eksak saat kontrak masih berstatus 'open' (escrow di kas pelabuhan)
    const consDuringEscrow = await checkDatabaseConsistency(testPool);
    expect(consDuringEscrow.valid).toBe(true);

    // Pemain A (yang punya 5 pala di kapal shipA1 di Banda) memenuhi kontrak tersebut
    const fulfillRes = await api.inject<{
      id: number;
      status: string;
      reward_coins: number;
    }>({
      method: 'POST',
      url: `/v1/contracts/${contractId}/fulfill`,
      headers: { authorization: `Bearer ${tokenA}` },
      body: { ship_id: shipA1 },
    });
    expect(fulfillRes.statusCode).toBe(200);
    expect(fulfillRes.body.status).toBe('fulfilled');
    expect(fulfillRes.body.reward_coins).toBe(300);

    // Pastikan konservasi uang tetap eksak setelah kontrak selesai
    const consAfterFulfill = await checkDatabaseConsistency(testPool);
    expect(consAfterFulfill.valid).toBe(true);
  });

  it('4. Multi-Kapal (POST /v1/ships/buy) & Penghapusan/Anonimisasi Akun (DELETE /v1/me) Tanpa Merusak Invarian', async () => {
    // Hadiah kontrak harus sesuai sisa saldo Pemain B setelah escrow 300 koin sebelumnya.
    const c2 = await api.inject<{ id: number }>({
      method: 'POST',
      url: '/v1/contracts',
      headers: { authorization: `Bearer ${tokenB}` },
      body: {
        port_id: 1,
        commodity_id: 1,
        qty: 2,
        reward_coins: 600,
      },
    });
    expect(c2.statusCode).toBe(201);

    const f2 = await api.inject({
      method: 'POST',
      url: `/v1/contracts/${c2.body.id}/fulfill`,
      headers: { authorization: `Bearer ${tokenA}` },
      body: { ship_id: shipA1 },
    });
    expect(f2.statusCode).toBe(200);

    // Sekarang Pemain A membeli kapal ke-2 di Ternate (port_id = 2)
    const buyShipRes = await api.inject<{
      ship: { id: number; name: string; port_id: number };
      cost: number;
    }>({
      method: 'POST',
      url: '/v1/ships/buy',
      headers: { authorization: `Bearer ${tokenA}` },
      body: {
        name: 'Pinisi Nusantara II',
        port_id: 2,
      },
    });
    expect(buyShipRes.statusCode).toBe(201);
    expect(buyShipRes.body.ship.name).toBe('Pinisi Nusantara II');
    expect(buyShipRes.body.ship.port_id).toBe(2);

    const listShipsA = await api.inject<{ items: unknown[] }>({
      method: 'GET',
      url: '/v1/ships',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(listShipsA.body.items.length).toBe(2);

    // Jalankan 1 tick dunia dengan 2 kapal milik Pemain A dan 1 kapal milik Pemain B
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });
    const consMultiShip = await checkDatabaseConsistency(testPool);
    expect(consMultiShip.valid).toBe(true);

    // Pemain B menghapus akunnya (DELETE /v1/me)
    const delRes = await api.inject<{
      ok: boolean;
      anonymized_player_id: number;
    }>({
      method: 'DELETE',
      url: '/v1/me',
      headers: { authorization: `Bearer ${tokenB}` },
    });
    expect(delRes.statusCode).toBe(200);
    expect(delRes.body.ok).toBe(true);

    // Kapal Pemain B sudah terhapus, tetapi ledger tetap utuh dan invarian konservasi uang diff == 0!
    const bShips = await testPool.query(
      `SELECT id FROM public.ships WHERE id = $1`,
      [shipB1],
    );
    expect(bShips.rows.length).toBe(0);

    // Jalankan 1 tick lagi pasca penghapusan akun untuk memastikan worker tetap berjalan mulus
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });
    const consAfterDelete = await checkDatabaseConsistency(testPool);
    expect(consAfterDelete.valid).toBe(true);

    // Evaluasi metrik beta (docs/13 Setelah MVP #1)
    const betaReport = await evaluateBetaMetrics(testPool);
    expect(betaReport.active_players).toBe(1);
    expect(betaReport.anonymized_players).toBe(1);
    expect(betaReport.total_ships).toBe(2);
    expect(betaReport.money_conservation_diff).toBe('0');
    expect(betaReport.contracts_fulfilled).toBe(2);
  });
});
