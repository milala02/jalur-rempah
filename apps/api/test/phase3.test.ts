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
  createMockGoogleIdToken,
  V1_RATE_LIMIT_MESSAGE,
  getPlayerRankTitle,
  calculatePlayerNetWorth,
  calculatePlayerLevel,
  calculateXpToNextLevel,
  compileBlocksToDsl,
} from '../src/index.js';
import {
  executeSingleWorldTick,
  spawnPirateThreat,
  resolveNavalCombat,
} from '../../worker/src/index.js';

describe('Fase 1 (UU PDP/ToS & Status Akun), Detail 2 (P2P Trading), Detail 3 (Anti-Cheat), & Fase 3 (World Events, Rank System, Block Builder Compiler API)', () => {
  const adminDbUrl = getDatabaseUrl();
  const testDbName = `test_phase3_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const testDbUrl = replaceDatabaseInUrl(adminDbUrl, testDbName);
  const ADMIN_SECRET = 'test-admin-secret-key-p3';

  let adminPool: pg.Pool;
  let testPool: pg.Pool;
  let api: ApiServer;

  let tokenP1 = '';
  let idP1 = 0;
  let shipP1 = 0;

  let tokenP2 = '';
  let idP2 = 0;
  let shipP2 = 0;

  let tokenP3 = '';
  let idP3 = 0;
  let shipP3 = 0;

  beforeAll(async () => {
    adminPool = createPool(adminDbUrl);
    await adminPool.query(`CREATE DATABASE ${testDbName};`);
    testPool = createPool(testDbUrl);

    await runMigrations(testPool);
    await seedWorld(testPool);

    api = createApiServer(testPool, {
      jwtSecret: 'test-secret-for-phase3-suite',
      adminKey: ADMIN_SECRET,
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

  it('1. Fondasi Hukum (Pilar 6): menolak registrasi tanpa tos_accepted (400), mencatat tos_accepted_at & tos_version="v1.0", dan menyediakan GET /v1/legal', async () => {
    const legalRes = await api.inject<{
      tos_version: string;
      terms_of_service: string;
      privacy_policy_uupdp: string;
      code_of_conduct: string;
    }>({
      method: 'GET',
      url: '/v1/legal',
    });
    expect(legalRes.statusCode).toBe(200);
    expect(legalRes.body.tos_version).toBe('v1.0');
    expect(legalRes.body.privacy_policy_uupdp).toContain('UU PDP');

    // Registrasi dengan tos_accepted: false wajib ditolak HTTP 400 "Anda harus menyetujui Syarat & Ketentuan"
    const regNoTos = await api.inject<{ error: { code: string; message: string } }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'tanpa_tos@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Tanpa_ToS',
        tos_accepted: false,
      },
    });
    expect(regNoTos.statusCode).toBe(400);
    expect(regNoTos.body.error.message).toBe(
      'Anda harus menyetujui Syarat & Ketentuan',
    );

    // Registrasi dengan tos_accepted: true berhasil & mencatat tos_accepted_at, tos_version = 'v1.0', account_status = 'active'
    const reg1 = await api.inject<{
      player: {
        id: number;
        email: string;
        tos_version: string;
        tos_accepted_at: string;
        account_status: string;
      };
      ship: { id: number };
      access_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'juragan1@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Juragan_Satu',
        tos_accepted: true,
      },
    });
    expect(reg1.statusCode).toBe(201);
    expect(reg1.body.player.tos_version).toBe('v1.0');
    expect(reg1.body.player.account_status).toBe('active');
    tokenP1 = reg1.body.access_token;
    idP1 = reg1.body.player.id;
    shipP1 = reg1.body.ship.id;

    // Verifikasi query langsung ke tabel players
    const checkPlayerRow = await testPool.query<{
      id: string;
      email: string;
      tos_accepted_at: Date | null;
      tos_version: string | null;
      account_status: string;
    }>(
      `SELECT id::text, email, tos_accepted_at, tos_version, account_status FROM public.players LIMIT 1`,
    );
    expect(checkPlayerRow.rows[0]?.email).toBe('juragan1@nusantara.id');
    expect(checkPlayerRow.rows[0]?.tos_accepted_at).not.toBeNull();
    expect(checkPlayerRow.rows[0]?.tos_version).toBe('v1.0');
    expect(checkPlayerRow.rows[0]?.account_status).toBe('active');

    // Registrasi Pemain 2 dan Pemain 3 untuk pengujian P2P & Anti-Cheat
    const reg2 = await api.inject<{
      player: { id: number };
      ship: { id: number };
      access_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'juragan2@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Juragan_Dua',
        tos_accepted: true,
      },
    });
    expect(reg2.statusCode).toBe(201);
    tokenP2 = reg2.body.access_token;
    idP2 = reg2.body.player.id;
    shipP2 = reg2.body.ship.id;

    const reg3 = await api.inject<{
      player: { id: number };
      ship: { id: number };
      access_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'juragan3@nusantara.id',
        password: 'PasswordAman123!',
        display_name: 'Juragan_Tiga',
        tos_accepted: true,
      },
    });
    expect(reg3.statusCode).toBe(201);
    tokenP3 = reg3.body.access_token;
    idP3 = reg3.body.player.id;
    shipP3 = reg3.body.ship.id;
  });

  it('2. P2P Trading (Detail 2A & 2B): batas harga Anti-RMT (50%..200%), Escrow barang, pembatalan (cancel), Direct Trade, dan kedaluwarsa 1.440 tick', async () => {
    // Berikan muatan awal pala ke kapal Pemain 1 melalui aturan beli + 1 tick dunia
    await api.inject({
      method: 'PUT',
      url: `/v1/ships/${shipP1}/rules`,
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        base_version: 0,
        source: `aturan beli_awal: jika di(Banda) dan stok_kapal(pala) == 0 maka beli(pala, 10)`,
      },
    });
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });

    // Cek harga pasar pala di Banda saat ini (sekitar 70 koin)
    const mktRes = await api.inject<{
      items: Array<{ commodity: string; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/world/market/banda',
    });
    const palaPrice =
      mktRes.body.items.find((i) => i.commodity === 'pala')?.price ?? 70;

    // 2.1. Uji batas harga Anti-RMT: harga terlalu murah (< 50%) atau terlalu mahal (> 200%) wajib ditolak 422 PRICE_OUT_OF_RANGE
    const tooCheap = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        order_type: 'auction',
        ship_id: shipP1,
        commodity_id: 1,
        qty: 2,
        unit_price: Math.max(1, Math.floor(palaPrice * 0.2)),
      },
    });
    expect(tooCheap.statusCode).toBe(422);
    expect(tooCheap.body.error.code).toBe('PRICE_OUT_OF_RANGE');

    const tooExpensive = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        order_type: 'auction',
        ship_id: shipP1,
        commodity_id: 1,
        qty: 2,
        unit_price: Math.ceil(palaPrice * 3.0),
      },
    });
    expect(tooExpensive.statusCode).toBe(422);
    expect(tooExpensive.body.error.code).toBe('PRICE_OUT_OF_RANGE');

    // 2.2. Buat tawaran Auction House yang sah (dalam rentang 50%..200%) -> mengunci 2 pala di Escrow, lalu batalkan (Cancel)
    const validUnitPrice = palaPrice;
    const createAuction = await api.inject<{ id: number; status: string }>({
      method: 'POST',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        order_type: 'auction',
        ship_id: shipP1,
        commodity_id: 1,
        qty: 2,
        unit_price: validUnitPrice,
      },
    });
    expect(createAuction.statusCode).toBe(201);
    const cancelOrderId = createAuction.body.id;

    // Batalkan tawaran sebelum ada pembeli -> barang kembali ke kapal Pemain 1
    const cancelRes = await api.inject<{
      id: number;
      status: string;
      returned_qty: number;
    }>({
      method: 'POST',
      url: `/v1/p2p/orders/${cancelOrderId}/cancel`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(cancelRes.statusCode).toBe(200);
    expect(cancelRes.body.status).toBe('cancelled');
    expect(cancelRes.body.returned_qty).toBe(2);

    // Adu cepat (Race Condition): jika Pemain 2 mencoba membeli order yang sudah dibatalkan -> ditolak 409 CONFLICT
    const lateBuy = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: `/v1/p2p/orders/${cancelOrderId}/accept`,
      headers: { authorization: `Bearer ${tokenP2}` },
      body: { ship_id: shipP2 },
    });
    expect(lateBuy.statusCode).toBe(409);
    expect(lateBuy.body.error.code).toBe('CONFLICT');

    // 2.3. Direct Trade (khusus ke Pemain 2): Pemain 3 tidak boleh menyerobot (403 FORBIDDEN)
    const createDirect = await api.inject<{ id: number }>({
      method: 'POST',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        order_type: 'direct',
        target_player_id: idP2,
        ship_id: shipP1,
        commodity_id: 1,
        qty: 2,
        unit_price: validUnitPrice,
      },
    });
    expect(createDirect.statusCode).toBe(201);
    const directOrderId = createDirect.body.id;

    const wrongBuyer = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: `/v1/p2p/orders/${directOrderId}/accept`,
      headers: { authorization: `Bearer ${tokenP3}` },
      body: { ship_id: shipP3 },
    });
    expect(wrongBuyer.statusCode).toBe(403);

    // Pemain 2 menerima Direct Trade -> berhasil!
    const acceptDirect = await api.inject<{
      id: number;
      status: string;
      qty: number;
    }>({
      method: 'POST',
      url: `/v1/p2p/orders/${directOrderId}/accept`,
      headers: { authorization: `Bearer ${tokenP2}` },
      body: { ship_id: shipP2 },
    });
    expect(acceptDirect.statusCode).toBe(200);
    expect(acceptDirect.body.status).toBe('completed');

    // 2.4. Kedaluwarsa otomatis 1.440 tick: buat order baru, simulasikan expires_tick <= tick saat ini, jalankan tick worker
    const expCreate = await api.inject<{ id: number }>({
      method: 'POST',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        order_type: 'auction',
        ship_id: shipP1,
        commodity_id: 1,
        qty: 1,
        unit_price: validUnitPrice,
      },
    });
    expect(expCreate.statusCode).toBe(201);
    await testPool.query(
      `UPDATE public.p2p_orders SET expires_tick = 1 WHERE id = $1`,
      [expCreate.body.id],
    );

    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });

    const expCheck = await testPool.query<{ status: string }>(
      `SELECT status FROM public.p2p_orders WHERE id = $1`,
      [expCreate.body.id],
    );
    expect(expCheck.rows[0]?.status).toBe('expired');

    const consCheck = await checkDatabaseConsistency(testPool);
    expect(consCheck.valid).toBe(true);
  });

  it('3. Anti-Cheat & Anomaly Detection (Detail 3A, 3B, 3C): deteksi otomatis wash trading -> shadowbanned (403 pada P2P & Leaderboard) -> tinjauan manual Admin', async () => {
    const mktRes = await api.inject<{
      items: Array<{ commodity: string; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/world/market/banda',
    });
    const palaPrice =
      mktRes.body.items.find((i) => i.commodity === 'pala')?.price ?? 70;

    // Transaksi P2P ke-2 dan ke-3 antara Pemain 1 dan Pemain 2 memicu deteksi otomatis WASH_TRADING (>= 3 transaksi berulang)
    for (let i = 0; i < 2; i++) {
      const ord = await api.inject<{ id: number }>({
        method: 'POST',
        url: '/v1/p2p/orders',
        headers: { authorization: `Bearer ${tokenP1}` },
        body: {
          order_type: 'direct',
          target_player_id: idP2,
          ship_id: shipP1,
          commodity_id: 1,
          qty: 1,
          unit_price: palaPrice,
        },
      });
      expect(ord.statusCode).toBe(201);

      const acc = await api.inject<{ anomaly_flagged: boolean }>({
        method: 'POST',
        url: `/v1/p2p/orders/${ord.body.id}/accept`,
        headers: { authorization: `Bearer ${tokenP2}` },
        body: { ship_id: shipP2 },
      });
      expect(acc.statusCode).toBe(200);
      if (i === 1) {
        expect(acc.body.anomaly_flagged).toBe(true);
      }
    }

    // Sekarang Pemain 1 & Pemain 2 otomatis berstatus 'shadowbanned':
    // - Tetap bisa login dan melihat kapal sendiri (/v1/ships)
    const loginShadow = await api.inject<{ account_status: string }>({
      method: 'POST',
      url: '/v1/auth/login',
      body: {
        email: 'juragan1@nusantara.id',
        password: 'PasswordAman123!',
      },
    });
    expect(loginShadow.statusCode).toBe(200);
    expect(loginShadow.body.account_status).toBe('shadowbanned');

    // - Diblokir dari P2P Trading & Leaderboard dengan HTTP 403 "Akun Anda sedang dalam peninjauan" (Langkah 6)
    const blockedP2p = await api.inject<{
      error: { code: string; message: string };
    }>({
      method: 'GET',
      url: '/v1/p2p/orders',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(blockedP2p.statusCode).toBe(403);
    expect(blockedP2p.body.error.message).toBe(
      'Akun Anda sedang dalam peninjauan',
    );

    const blockedLb = await api.inject<{
      error: { code: string; message: string };
    }>({
      method: 'GET',
      url: '/v1/leaderboard',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(blockedLb.statusCode).toBe(403);
    expect(blockedLb.body.error.message).toBe(
      'Akun Anda sedang dalam peninjauan',
    );

    // - Saat pemain aktif (Pemain 3) melihat Leaderboard, Pemain 1 & 2 yang shadowbanned tidak muncul!
    const publicLb = await api.inject<{
      items: Array<{ display_name: string }>;
    }>({
      method: 'GET',
      url: '/v1/leaderboard',
      headers: { authorization: `Bearer ${tokenP3}` },
    });
    expect(publicLb.statusCode).toBe(200);
    expect(
      publicLb.body.items.some((x) => x.display_name === 'Juragan_Satu'),
    ).toBe(false);

    // Detail 3C: Admin meninjau daftar anomali dan memulihkan Pemain 1 & Pemain 2 ke 'active'
    const adminAlerts = await api.inject<{
      items: Array<{ player_id: number; alert_type: string }>;
    }>({
      method: 'GET',
      url: '/v1/admin/anomalies',
      headers: { 'x-admin-key': ADMIN_SECRET },
    });
    expect(adminAlerts.statusCode).toBe(200);
    expect(adminAlerts.body.items.length).toBeGreaterThanOrEqual(2);
    expect(adminAlerts.body.items[0]?.alert_type).toBe('WASH_TRADING');

    const restoreP1 = await api.inject<{ account_status: string }>({
      method: 'POST',
      url: `/v1/admin/players/${idP1}/status`,
      headers: { 'x-admin-key': ADMIN_SECRET },
      body: { account_status: 'active' },
    });
    expect(restoreP1.statusCode).toBe(200);
    expect(restoreP1.body.account_status).toBe('active');

    const restoreP2 = await api.inject<{ account_status: string }>({
      method: 'POST',
      url: `/v1/admin/players/${idP2}/status`,
      headers: { 'x-admin-key': ADMIN_SECRET },
      body: { account_status: 'active' },
    });
    expect(restoreP2.statusCode).toBe(200);
  });

  it('4. Hapus Akun UU PDP (DELETE /v1/me — Langkah 5): mengubah email menjadi deleted_<id>@anonymous.com, menghapus password_hash, dan account_status="banned"', async () => {
    const delRes = await api.inject<{
      ok: boolean;
      anonymized_player_id: number;
      email: string;
      account_status: string;
    }>({
      method: 'DELETE',
      url: '/v1/me',
      headers: { authorization: `Bearer ${tokenP3}` },
    });
    expect(delRes.statusCode).toBe(200);
    expect(delRes.body.ok).toBe(true);
    expect(delRes.body.email).toBe(`deleted_${idP3}@anonymous.com`);
    expect(delRes.body.account_status).toBe('banned');

    const dbRow = await testPool.query<{
      email: string;
      password_hash: string;
      account_status: string;
    }>(
      `SELECT email, password_hash, account_status FROM public.players WHERE id = $1`,
      [idP3],
    );
    expect(dbRow.rows[0]?.email).toBe(`deleted_${idP3}@anonymous.com`);
    expect(dbRow.rows[0]?.password_hash).toBe('');
    expect(dbRow.rows[0]?.account_status).toBe('banned');

    const consAfter = await checkDatabaseConsistency(testPool);
    expect(consAfter.valid).toBe(true);
  });

  it('5. World Events Engine (Fase 3 Langkah 1): Wabah Hama (stok turun & harga naik), Embargo/Perang (rute ditutup sementara), Angin Muson Kencang (ETA -50%), dan GET /v1/world/events', async () => {
    // 5.1. Cek stok & harga pala di Banda sebelum Wabah Hama
    const mktBefore = await api.inject<{
      items: Array<{ commodity: string; stock: number; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/world/market/banda',
    });
    const palaBefore = mktBefore.body.items.find((i) => i.commodity === 'pala')!;
    expect(palaBefore).toBeDefined();

    // Picu event "Wabah Hama" pada Pala (commodityId: 1) di Banda (portId: 1)
    const tickWabah = await executeSingleWorldTick(testPool, {
      flushUpkeepImmediately: true,
      triggerWorldEvent: {
        kind: 'WABAH_HAMA',
        portId: 1,
        commodityId: 1,
        durationTicks: 10,
      },
    });
    expect(tickWabah.triggeredEvent?.eventCode).toBe('WABAH_HAMA');

    const mktAfter = await api.inject<{
      items: Array<{ commodity: string; stock: number; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/world/market/banda',
    });
    const palaAfter = mktAfter.body.items.find((i) => i.commodity === 'pala')!;
    expect(palaAfter.stock).toBeLessThan(palaBefore.stock);
    expect(palaAfter.price).toBeGreaterThan(palaBefore.price);

    // 5.2. Picu event "Embargo/Perang" di Ternate (portId: 2) dan pastikan kapal Pemain 1 tertahan saat mencoba berlayar ke Ternate
    await api.inject({
      method: 'PUT',
      url: `/v1/ships/${shipP1}/rules`,
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        base_version: 1,
        source: `aturan layar_ternate: jika di(Banda) maka berlayar(Ternate)`,
      },
    });

    const tickEmbargo = await executeSingleWorldTick(testPool, {
      flushUpkeepImmediately: true,
      triggerWorldEvent: {
        kind: 'EMBARGO_PERANG',
        portId: 2,
        durationTicks: 1,
      },
    });
    expect(tickEmbargo.triggeredEvent?.eventCode).toBe('EMBARGO_PERANG');

    const shDuringEmbargo = await api.inject<{
      status: string;
      port_id: number;
    }>({
      method: 'GET',
      url: `/v1/ships/${shipP1}`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(shDuringEmbargo.body.status).toBe('docked');
    expect(shDuringEmbargo.body.port_id).toBe(1);

    // 5.3. Arahkan kapal Pemain 2 berlayar ke Makassar (portId: 3, jarak 4 tick dari Banda) lalu picu "Angin Muson Kencang"
    await api.inject({
      method: 'PUT',
      url: `/v1/ships/${shipP2}/rules`,
      headers: { authorization: `Bearer ${tokenP2}` },
      body: {
        base_version: 0,
        source: `aturan layar_makassar: jika di(Banda) maka berlayar(Makassar)`,
      },
    });

    const tickMuson = await executeSingleWorldTick(testPool, {
      flushUpkeepImmediately: true,
      triggerWorldEvent: {
        kind: 'ANGIN_MUSON_KENCANG',
        durationTicks: 10,
      },
    });
    expect(tickMuson.triggeredEvent?.eventCode).toBe('ANGIN_MUSON_KENCANG');

    const sh2AfterMuson = await api.inject<{
      status: string;
      eta_ticks: number;
    }>({
      method: 'GET',
      url: `/v1/ships/${shipP2}`,
      headers: { authorization: `Bearer ${tokenP2}` },
    });
    expect(sh2AfterMuson.body.status).toBe('sailing');
    // Rute Banda -> Makassar adalah 6 tick di data seed; muson memotong ETA menjadi 3 tick.
    expect(sh2AfterMuson.body.eta_ticks).toBe(3);

    // 5.4. Pastikan GET /v1/world/events mengembalikan daftar event yang sedang aktif
    const worldEventsRes = await api.inject<{
      tick_no: number;
      active_events: Array<{ event_code: string; title: string; is_active: boolean }>;
      items: Array<{ event_code: string; title: string }>;
    }>({
      method: 'GET',
      url: '/v1/world/events',
    });
    expect(worldEventsRes.statusCode).toBe(200);
    expect(worldEventsRes.body.active_events.length).toBeGreaterThanOrEqual(2);
    expect(
      worldEventsRes.body.items.some((e) => e.event_code === 'WABAH_HAMA'),
    ).toBe(true);
    expect(
      worldEventsRes.body.items.some(
        (e) => e.event_code === 'ANGIN_MUSON_KENCANG',
      ),
    ).toBe(true);
  });

  it('6. Rank & Title System (Fase 3 Langkah 2): kalkulasi Net Worth dan 4 tingkat Gelar (Awak Baru, Juragan, Nahkoda, Sultan Rempah) pada GET /v1/me & GET /v1/leaderboard', async () => {
    // 6.1. Unit test langsung fungsi getPlayerRankTitle & calculatePlayerNetWorth
    expect(getPlayerRankTitle(0)).toBe('Awak Baru');
    expect(getPlayerRankTitle(999)).toBe('Awak Baru');
    expect(getPlayerRankTitle(1000)).toBe('Juragan');
    expect(getPlayerRankTitle(10000)).toBe('Juragan');
    expect(getPlayerRankTitle(10001)).toBe('Nahkoda');
    expect(getPlayerRankTitle(100000)).toBe('Nahkoda');
    expect(getPlayerRankTitle(100001)).toBe('Sultan Rempah');
    expect(getPlayerRankTitle(250000)).toBe('Sultan Rempah');

    expect(
      calculatePlayerNetWorth({
        coins: 5000,
        shipCount: 2, // 1 kapal tambahan bernilai 1.500 koin
        cargoValue: 4000,
      }),
    ).toBe(10500);

    // 6.2. Verifikasi pada endpoint GET /v1/me dan GET /v1/leaderboard
    const meRes = await api.inject<{
      display_name: string;
      net_worth: number;
      title: string;
    }>({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(meRes.statusCode).toBe(200);
    expect(['Awak Baru', 'Juragan', 'Nahkoda', 'Sultan Rempah']).toContain(
      meRes.body.title,
    );

    const lbRes = await api.inject<{
      tick_no: number;
      items: Array<{
        rank: number;
        display_name: string;
        net_worth: number;
        title: string;
      }>;
    }>({
      method: 'GET',
      url: '/v1/leaderboard',
    });
    expect(lbRes.statusCode).toBe(200);
    expect(lbRes.body.items.length).toBeGreaterThanOrEqual(2);
    for (const row of lbRes.body.items) {
      expect(row.title).toBe(getPlayerRankTitle(row.net_worth));
    }
  });

  it('7. Block Builder Compiler API (Fase 3 Langkah 3): POST /v1/dsl/compile-blocks menerjemahkan JSON terstruktur menjadi teks Bahasa Aturan yang valid', async () => {
    // 7.1. Uji contoh persis dari spesifikasi tugas
    const samplePayload = {
      type: 'IF',
      condition: { func: 'di', args: ['Batavia'] },
      action: { func: 'beli', args: ['pala'] },
    };

    const unitOut = compileBlocksToDsl(samplePayload);
    expect(unitOut.dsl).toBe('jika di(Batavia) maka beli(pala)');

    const res1 = await api.inject<{
      dsl: string;
      source: string;
      full_rule_source: string;
    }>({
      method: 'POST',
      url: '/v1/dsl/compile-blocks',
      body: samplePayload,
    });
    expect(res1.statusCode).toBe(200);
    expect(res1.body.dsl).toBe('jika di(Batavia) maka beli(pala)');
    expect(res1.body.source).toBe('jika di(Batavia) maka beli(pala)');

    // 7.2. Uji kondisi majemuk (AND) dengan operator perbandingan dan multi-argumen
    const res2 = await api.inject<{ dsl: string }>({
      method: 'POST',
      url: '/v1/dsl/compile-blocks',
      body: {
        type: 'IF',
        condition: {
          type: 'AND',
          conditions: [
            { func: 'di', args: ['Banda'] },
            { func: 'harga', args: ['pala'], op: '<=', value: 55 },
          ],
        },
        action: { func: 'beli', args: ['pala', 10] },
      },
    });
    expect(res2.statusCode).toBe(200);
    expect(res2.body.dsl).toBe(
      'jika di(Banda) dan harga(pala) <= 55 maka beli(pala, 10)',
    );

    // 7.3. Uji input blok tidak valid -> 400 VALIDATION_ERROR
    const badRes = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/dsl/compile-blocks',
      body: {
        type: 'UNKNOWN_BLOCK',
      },
    });
    expect(badRes.statusCode).toBe(400);
    expect(badRes.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('8. Fase 5 — Ekspansi Global (8 Negara) & Progressive Unlocking (Level 1..7, GET /v1/world/ports, GET /v1/world/commodities, GET /v1/me)', async () => {
    // 8.1. Unit test batas ambang Level 1..7 & xp_to_next_level
    expect(calculatePlayerLevel(1000)).toBe(1);
    expect(calculatePlayerLevel(4999)).toBe(1);
    expect(calculateXpToNextLevel(1000)).toBe(4000);

    expect(calculatePlayerLevel(5000)).toBe(2);
    expect(calculatePlayerLevel(20000)).toBe(2);
    expect(calculateXpToNextLevel(20000)).toBe(1);

    expect(calculatePlayerLevel(20001)).toBe(3);
    expect(calculatePlayerLevel(50000)).toBe(3);

    expect(calculatePlayerLevel(50001)).toBe(4);
    expect(calculatePlayerLevel(150000)).toBe(4);

    expect(calculatePlayerLevel(150001)).toBe(5);
    expect(calculatePlayerLevel(500000)).toBe(5);

    expect(calculatePlayerLevel(500001)).toBe(6);
    expect(calculatePlayerLevel(1000000)).toBe(6);

    expect(calculatePlayerLevel(1000001)).toBe(7);
    expect(calculateXpToNextLevel(1500000)).toBe(0);

    // 8.2. Verifikasi GET /v1/me menyertakan level dan xp_to_next_level
    const meRes = await api.inject<{
      level: number;
      net_worth: number;
      xp_to_next_level: number;
    }>({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(meRes.statusCode).toBe(200);
    expect(meRes.body.level).toBe(1);
    expect(meRes.body.xp_to_next_level).toBe(5000 - meRes.body.net_worth);

    // 8.3. Verifikasi GET /v1/world/ports sebagai Pemain Level 1 -> Lisbon (Level 6) memiliki is_locked: true
    const portsRes = await api.inject<{
      player_level: number;
      items: Array<{
        code: string;
        name: string;
        country_code: string;
        min_level_required: number;
        is_locked: boolean;
      }>;
    }>({
      method: 'GET',
      url: '/v1/world/ports',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(portsRes.statusCode).toBe(200);
    expect(portsRes.body.player_level).toBe(1);

    const banda = portsRes.body.items.find((p) => p.code === 'banda');
    const mekkah = portsRes.body.items.find((p) => p.code === 'mekkah');
    const sakai = portsRes.body.items.find((p) => p.code === 'sakai');
    const lisbon = portsRes.body.items.find((p) => p.code === 'lisbon');
    const kairo = portsRes.body.items.find((p) => p.code === 'kairo');

    expect(banda?.is_locked).toBe(false);
    expect(mekkah?.min_level_required).toBe(4);
    expect(mekkah?.is_locked).toBe(true);
    expect(sakai?.min_level_required).toBe(5);
    expect(sakai?.is_locked).toBe(true);
    expect(lisbon?.name).toBe('Lisbon');
    expect(lisbon?.min_level_required).toBe(6);
    expect(lisbon?.is_locked).toBe(true);
    expect(kairo?.min_level_required).toBe(7);
    expect(kairo?.is_locked).toBe(true);

    // 8.4. Verifikasi GET /v1/world/commodities mengembalikan 8 komoditas internasional dengan is_locked: true untuk pemain Level 1
    const comsRes = await api.inject<{
      player_level: number;
      items: Array<{
        code: string;
        name: string;
        country_code: string;
        origin_port_code: string;
        min_level_required: number;
        is_locked: boolean;
      }>;
    }>({
      method: 'GET',
      url: '/v1/world/commodities',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(comsRes.statusCode).toBe(200);
    const meriam = comsRes.body.items.find((c) => c.code === 'meriam');
    const emas = comsRes.body.items.find((c) => c.code === 'emas_batangan');
    expect(meriam?.origin_port_code).toBe('lisbon');
    expect(meriam?.min_level_required).toBe(6);
    expect(meriam?.is_locked).toBe(true);
    expect(emas?.origin_port_code).toBe('kairo');
    expect(emas?.min_level_required).toBe(7);
    expect(emas?.is_locked).toBe(true);
  });

  it('9. Fase 6 — Sistem Pertempuran Dasar & Bajak Laut (spawnPirateThreat, resolveNavalCombat, POST /v1/ships/repair, POST /v1/ships/equip, GET /v1/logs)', async () => {
    // 9.1. Unit test langsung fungsi kalkulasi kerusakan (resolveNavalCombat) & spawnPirateThreat
    const pirateThreat = spawnPirateThreat(50, 101, 1.0);
    expect(pirateThreat).not.toBeNull();

    // Skenario A: Kapal tanpa senjata (attack_power: 0, defense_power: 100) dicegat Bajak Laut (attack: 35, defense: 80) -> Bajak Laut menang, merampas 40% muatan pala & mengurangi HP kapal
    const lossOutcome = resolveNavalCombat({
      shipId: 1,
      playerId: 1,
      shipName: 'Kapal Perintis',
      shipAttackPower: 0,
      shipDefensePower: 100,
      pirate: {
        name: 'Bajak Laut Selat Malaka',
        attackPower: 35,
        defensePower: 80,
        bountyCoins: 200,
      },
      cargo: new Map([[1, 10n]]),
    });
    expect(lossOutcome.outcome).toBe('pirate_victory');
    expect(lossOutcome.damage).toBe(35);
    expect(lossOutcome.shipDefenseAfter).toBe(65);
    expect(lossOutcome.lootedCommodityCode).toBe('pala');
    expect(lossOutcome.lootedQty).toBe(4n);

    // Skenario B: Kapal dipersenjatai Meriam (attack_power: 35, defense_power: 100) -> Pemain menang, meraih hadiah 200 koin & kerusakan tereduksi
    const winOutcome = resolveNavalCombat({
      shipId: 1,
      playerId: 1,
      shipName: 'Kapal Perintis',
      shipAttackPower: 35,
      shipDefensePower: 100,
      pirate: {
        name: 'Bajak Laut Selat Malaka',
        attackPower: 35,
        defensePower: 80,
        bountyCoins: 200,
      },
      cargo: new Map([[1, 10n]]),
    });
    expect(winOutcome.outcome).toBe('player_victory');
    expect(winOutcome.damage).toBe(11);
    expect(winOutcome.shipDefenseAfter).toBe(89);
    expect(winOutcome.bountyCoins).toBe(200n);
    expect(winOutcome.lootedQty).toBe(0n);

    // 9.2. Integration test: Bajak Laut menyerang kapal Pemain 1 di tick worker -> HP berkurang -> Perbaiki kapal (POST /v1/ships/repair) -> Pasang Meriam (POST /v1/ships/equip) -> Menang lawan Bajak Laut!
    const tickPirateAttack = await executeSingleWorldTick(testPool, {
      flushUpkeepImmediately: true,
      triggerPirateEncounter: {
        shipId: shipP1,
        pirate: {
          name: 'Bajak Laut Selat Malaka',
          attackPower: 35,
          defensePower: 80,
          bountyCoins: 200,
        },
      },
    });
    expect(tickPirateAttack.combatResults?.[0]?.outcome).toBe('pirate_victory');
    expect(tickPirateAttack.combatResults?.[0]?.damage).toBe(35);

    // Perbaiki HP lambung kapal menggunakan POST /v1/ships/repair
    const repairRes = await api.inject<{
      ship_id: number;
      defense_power: number;
      restored_hp: number;
      repair_cost: number;
    }>({
      method: 'POST',
      url: '/v1/ships/repair',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: { ship_id: shipP1 },
    });
    expect(repairRes.statusCode).toBe(200);
    expect(repairRes.body.defense_power).toBe(100);
    expect(repairRes.body.restored_hp).toBe(35);

    // Pasang Meriam ke kapal menggunakan POST /v1/ships/equip
    const equipRes = await api.inject<{
      ship_id: number;
      weapon: string;
      attack_power_added: number;
      attack_power: number;
    }>({
      method: 'POST',
      url: '/v1/ships/equip',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: { ship_id: shipP1, weapon: 'meriam', qty: 1 },
    });
    expect(equipRes.statusCode).toBe(200);
    expect(equipRes.body.attack_power).toBe(35);

    // Serangan Bajak Laut ke-2: sekarang kapal memiliki Meriam (attack_power: 35) -> Pemain menang!
    const tickPirateWin = await executeSingleWorldTick(testPool, {
      flushUpkeepImmediately: true,
      triggerPirateEncounter: {
        shipId: shipP1,
        pirate: {
          name: 'Bajak Laut Selat Malaka',
          attackPower: 35,
          defensePower: 80,
          bountyCoins: 200,
        },
      },
    });
    expect(tickPirateWin.combatResults?.[0]?.outcome).toBe('player_victory');
    expect(tickPirateWin.combatResults?.[0]?.bountyCoins).toBe(200n);

    // Verifikasi GET /v1/logs mengembalikan log pertempuran dan notifikasi banner
    const logsRes = await api.inject<{
      notifications: Array<{ type: string; title: string; message: string }>;
      combat_logs: Array<{
        pirate_name: string;
        damage: number;
        is_pirate: boolean;
        outcome: string;
      }>;
    }>({
      method: 'GET',
      url: '/v1/logs',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(logsRes.statusCode).toBe(200);
    expect(logsRes.body.combat_logs.length).toBeGreaterThanOrEqual(2);
    expect(logsRes.body.notifications.length).toBeGreaterThanOrEqual(2);

    // Pastikan konservasi uang global tetap 100% valid
    const consAfterCombat = await checkDatabaseConsistency(testPool);
    expect(consAfterCombat.valid).toBe(true);
  });

  it('10. Fase 7 — Sistem Quest (Misi Harian) & Tutorial Onboarding (GET /v1/quests, POST /v1/quests/:id/claim, POST /v1/tutorial/advance, GET /v1/me)', async () => {
    // 10.1. Verifikasi tutorial_step awal = 0 pada GET /v1/me lalu naikkan dengan POST /v1/tutorial/advance
    const meBefore = await api.inject<{ tutorial_step: number }>({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(meBefore.statusCode).toBe(200);
    expect(meBefore.body.tutorial_step).toBe(0);

    const advRes = await api.inject<{ tutorial_step: number }>({
      method: 'POST',
      url: '/v1/tutorial/advance',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(advRes.statusCode).toBe(200);
    expect(advRes.body.tutorial_step).toBe(1);

    // 10.2. Ambil daftar Misi Harian (GET /v1/quests) -> ketiga misi sudah memiliki progres dari aksi Pemain 1 sebelumnya
    const questsRes = await api.inject<{
      assigned_date: string;
      items: Array<{
        id: number;
        quest_id: number;
        code: string;
        title: string;
        progress: number;
        target_value: number;
        reward_coins: number;
        reward_xp: number;
        is_completed: boolean;
        is_claimed: boolean;
      }>;
    }>({
      method: 'GET',
      url: '/v1/quests',
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(questsRes.statusCode).toBe(200);
    expect(questsRes.body.items.length).toBe(3);

    const pirateQuest = questsRes.body.items.find(
      (q) => q.code === 'pirate_hunter',
    )!;
    expect(pirateQuest.is_completed).toBe(true);
    expect(pirateQuest.is_claimed).toBe(false);

    // 10.3. Klaim hadiah Misi Harian (POST /v1/quests/:id/claim)
    const claimRes = await api.inject<{
      is_claimed: boolean;
      reward_coins: number;
      reward_xp: number;
    }>({
      method: 'POST',
      url: `/v1/quests/${pirateQuest.id}/claim`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(claimRes.statusCode).toBe(200);
    expect(claimRes.body.is_claimed).toBe(true);
    expect(claimRes.body.reward_coins).toBe(200);
    expect(claimRes.body.reward_xp).toBe(250);

    // Klaim ulang wajib ditolak 409 ALREADY_CLAIMED
    const dupClaim = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: `/v1/quests/${pirateQuest.id}/claim`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(dupClaim.statusCode).toBe(409);
    expect(dupClaim.body.error.code).toBe('ALREADY_CLAIMED');

    // Pastikan konservasi uang global tetap 100% valid pasca klaim hadiah misi
    const consAfterQuest = await checkDatabaseConsistency(testPool);
    expect(consAfterQuest.valid).toBe(true);
  });

  it('11. Fase 8 — Sistem Aliansi Dagang (POST /v1/guilds 5.000 Koin, join/leave, POST /v1/guilds/donate, GET /v1/guilds/:id, & World Boss Bajak Laut Armada Besar)', async () => {
    // Transfer 12.500 koin dari port dengan saldo cukup, dicatat sebagai penjualan fixture.
    await testPool.query('BEGIN');
    const treasuryRes = await testPool.query<{ id: number; treasury: string }>(
      'SELECT id, treasury::text FROM public.ports WHERE id <= 6 AND treasury >= 12500 ORDER BY treasury DESC LIMIT 1 FOR UPDATE',
    );
    const treasuryPort = treasuryRes.rows[0];
    expect(treasuryPort).toBeDefined();
    await testPool.query(
      'UPDATE public.ports SET treasury = treasury - 12500 WHERE id = $1',
      [treasuryPort!.id],
    );
    await testPool.query(
      'UPDATE public.players SET coins = coins + 12500 WHERE id = $1',
      [idP1],
    );
    const tickRes = await testPool.query<{ tick_no: string }>(
      'SELECT COALESCE(MAX(tick_no), 0)::text AS tick_no FROM public.tick_state',
    );
    await testPool.query(
      `INSERT INTO public.ledger (player_id, tick_no, delta, reason)
       VALUES ($1, $2, 12500, 'sell')`,
      [idP1, Number(tickRes.rows[0]?.tick_no ?? '0')],
    );
    await testPool.query('COMMIT');

    // 11.1. Pemain 1 mendirikan Aliansi Baru (biaya 5.000 koin dipotong dari pemain & masuk ke treasury_coins + ledger)
    const createGuildRes = await api.inject<{
      id: number;
      code: string;
      name: string;
      treasury_coins: number;
      fee_paid: number;
      role: string;
    }>({
      method: 'POST',
      url: '/v1/guilds',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: {
        code: 'nusantara_emas',
        name: 'Aliansi Nusantara Emas',
        description: 'Kongsi dagang rempah samudra raya',
      },
    });
    expect(createGuildRes.statusCode).toBe(201);
    expect(createGuildRes.body.code).toBe('nusantara_emas');
    expect(createGuildRes.body.treasury_coins).toBe(5000);
    expect(createGuildRes.body.fee_paid).toBe(5000);
    expect(createGuildRes.body.role).toBe('leader');

    const guildId = createGuildRes.body.id;

    // 11.2. Pemain 2 bergabung ke Aliansi (POST /v1/guilds/:id/join)
    const joinRes = await api.inject<{
      guild_id: number;
      code: string;
      role: string;
      treasury_coins: number;
    }>({
      method: 'POST',
      url: `/v1/guilds/${guildId}/join`,
      headers: { authorization: `Bearer ${tokenP2}` },
    });
    expect(joinRes.statusCode).toBe(200);
    expect(joinRes.body.guild_id).toBe(guildId);
    expect(joinRes.body.role).toBe('member');

    // 11.3. Pemain 1 menyetor donasi 7.500 koin ke Kas Guild (POST /v1/guilds/donate) sehingga kas > 10.000 koin (12.500 koin)
    const donateRes = await api.inject<{
      guild_id: number;
      donated_amount: number;
      treasury_coins: number;
      world_boss_eligible: boolean;
    }>({
      method: 'POST',
      url: '/v1/guilds/donate',
      headers: { authorization: `Bearer ${tokenP1}` },
      body: { amount: 7500 },
    });
    expect(donateRes.statusCode).toBe(200);
    expect(donateRes.body.donated_amount).toBe(7500);
    expect(donateRes.body.treasury_coins).toBe(12500);
    expect(donateRes.body.world_boss_eligible).toBe(true);

    // 11.4. Jalankan 1 tick Worker -> otomatis memunculkan World Boss "Bajak Laut Armada Besar" karena treasury_coins > 10.000
    await executeSingleWorldTick(testPool, { flushUpkeepImmediately: true });

    // 11.5. Verifikasi GET /v1/guilds/:id (Profil Guild, Kas, Anggota, & Status World Boss)
    const guildProfileRes = await api.inject<{
      id: number;
      code: string;
      name: string;
      treasury_coins: number;
      total_guild_wealth: number;
      member_count: number;
      world_boss: {
        is_active: boolean;
        name: string;
        hp: number;
        max_hp: number;
      };
      members: Array<{
        player_id: number;
        display_name: string;
        role: string;
      }>;
    }>({
      method: 'GET',
      url: `/v1/guilds/${guildId}`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(guildProfileRes.statusCode).toBe(200);
    expect(guildProfileRes.body.treasury_coins).toBe(12500);
    expect(guildProfileRes.body.member_count).toBe(2);
    expect(guildProfileRes.body.world_boss.name).toBe('Bajak Laut Armada Besar');
    expect(guildProfileRes.body.world_boss.is_active).toBe(true);

    // 11.6. Anggota Guild mengirim kapal menyerang World Boss bersama-sama (POST /v1/guilds/:id/attack-boss)
    const attackBossRes = await api.inject<{
      guild_id: number;
      boss_name: string;
      damage_dealt: number;
      boss_hp_after: number;
    }>({
      method: 'POST',
      url: `/v1/guilds/${guildId}/attack-boss`,
      headers: { authorization: `Bearer ${tokenP1}` },
    });
    expect(attackBossRes.statusCode).toBe(200);
    expect(attackBossRes.body.damage_dealt).toBeGreaterThan(0);

    // 11.7. Pemain 2 keluar dari Aliansi (POST /v1/guilds/:id/leave)
    const leaveRes = await api.inject<{ ok: boolean; left: boolean }>({
      method: 'POST',
      url: `/v1/guilds/${guildId}/leave`,
      headers: { authorization: `Bearer ${tokenP2}` },
    });
    expect(leaveRes.statusCode).toBe(200);
    expect(leaveRes.body.left).toBe(true);

    // 11.8. Pastikan konservasi uang global & saldo ledger 100% eksak!
    const consAfterGuild = await checkDatabaseConsistency(testPool);
    expect(consAfterGuild.valid).toBe(true);
  });

  it('12. Fase 9 — Persiapan Rilis Publik: Google Auth (POST /v1/auth/google auto-register & login) dan Security Rate Limiting (/v1/* 100 req/15 menit per IP -> 429)', async () => {
    const testGoogleClientId = '1234567890-testclient.apps.googleusercontent.com';
    const googleApi = createApiServer(testPool, {
      jwtSecret: 'test-secret-for-phase3-suite',
      googleClientId: testGoogleClientId,
      minClientVersion: '0.1.0',
    });

    // 12.1. Token Google tidak valid ditolak 401 UNAUTHENTICATED
    const badGoogleRes = await googleApi.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/google',
      remoteAddress: '198.51.100.10',
      body: { id_token: 'token.palsu.tidak_valid' },
    });
    expect(badGoogleRes.statusCode).toBe(401);

    // 12.2. Login Google pertama kali untuk email baru -> Auto-Register pemain baru (tanpa password, tos_accepted_at otomatis, kapal awal + ledger starter)
    const validIdToken = createMockGoogleIdToken({
      email: 'kapten.google@nusantara.id',
      name: 'Kapten Google Nusantara',
      aud: testGoogleClientId,
    });

    const firstGoogleLogin = await googleApi.inject<{
      is_new_player: boolean;
      access_token: string;
      player: {
        id: number;
        email: string;
        display_name: string;
        coins: number;
        tos_accepted_at: string;
      };
      ship: { id: number; name: string; capacity: number };
    }>({
      method: 'POST',
      url: '/v1/auth/google',
      remoteAddress: '198.51.100.10',
      body: { id_token: validIdToken },
    });
    expect(firstGoogleLogin.statusCode).toBe(201);
    expect(firstGoogleLogin.body.is_new_player).toBe(true);
    expect(firstGoogleLogin.body.player.email).toBe('kapten.google@nusantara.id');
    expect(firstGoogleLogin.body.player.coins).toBe(1000);
    expect(firstGoogleLogin.body.player.tos_accepted_at).toBeTruthy();
    expect(firstGoogleLogin.body.ship.name).toBe('Kapal Perintis');
    expect(firstGoogleLogin.body.access_token).toBeTruthy();

    // 12.3. Login Google kedua kali dengan email yang sama -> langsung login (200 OK, is_new_player = false)
    const secondGoogleLogin = await googleApi.inject<{
      is_new_player: boolean;
      access_token: string;
      player: { id: number; email: string };
    }>({
      method: 'POST',
      url: '/v1/auth/google',
      remoteAddress: '198.51.100.10',
      body: { id_token: validIdToken },
    });
    expect(secondGoogleLogin.statusCode).toBe(200);
    expect(secondGoogleLogin.body.is_new_player).toBe(false);
    expect(secondGoogleLogin.body.player.id).toBe(firstGoogleLogin.body.player.id);
    expect(secondGoogleLogin.body.access_token).toBeTruthy();

    // Pastikan konservasi uang global tetap 100% eksak pasca auto-register Google Auth
    const consAfterGoogle = await checkDatabaseConsistency(testPool);
    expect(consAfterGoogle.valid).toBe(true);

    // 12.4. Uji Security Rate Limiting /v1/*: Maksimal 100 request per 15 menit per IP Address
    const burstIp = '203.0.113.250';
    for (let i = 1; i <= 100; i++) {
      const okRes = await googleApi.inject({
        method: 'GET',
        url: '/v1/healthz',
        headers: { 'x-real-ip': burstIp },
      });
      expect(okRes.statusCode).toBe(200);
    }

    // Request ke-101 dari IP yang sama dalam jendela 15 menit wajib dikembalikan HTTP 429
    const blockedRes = await googleApi.inject<{
      message: string;
      error: { code: string; message: string };
    }>({
      method: 'GET',
      url: '/v1/world',
      headers: { 'x-real-ip': burstIp },
    });
    expect(blockedRes.statusCode).toBe(429);
    expect(blockedRes.body.message).toBe(
      'Terlalu banyak permintaan. Silakan coba lagi nanti.',
    );
    expect(blockedRes.body.error.message).toBe(V1_RATE_LIMIT_MESSAGE);
  });
});
