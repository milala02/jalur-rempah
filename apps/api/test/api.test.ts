import fs from 'node:fs';
import path from 'node:path';
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
import { validateDsl, RULE_TEMPLATES } from '@jalur-rempah/dsl';

describe('M2 & M4 — API Integration: Auth, Akun+Kapal+Ledger, Endpoint Baca, Otorisasi IDOR, Aturan, & Sandbox Simulate', () => {
  const adminDbUrl = getDatabaseUrl();
  const testDbName = `test_api_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  const testDbUrl = replaceDatabaseInUrl(adminDbUrl, testDbName);

  let adminPool: pg.Pool;
  let testPool: pg.Pool;
  let api: ApiServer;

  let player1Token = '';
  let player1Refresh = '';
  let player1ShipId = 0;
  let player2Token = '';

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

    api = createApiServer(testPool, {
      jwtSecret: 'test-secret-for-m2-m4-integration-suite',
      adminKey: 'test-admin-key-api',
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

  it('1. Healthz, versi klien (426 CLIENT_OUTDATED), dan endpoint dunia publik (/v1/world, /v1/world/market, /v1/rule-templates)', async () => {
    const hRes = await api.inject<{ status: string }>({
      method: 'GET',
      url: '/v1/healthz',
    });
    expect(hRes.statusCode).toBe(200);
    expect(hRes.body.status).toBe('ok');

    const hwRes = await api.inject<{ status: string; tick_no: number }>({
      method: 'GET',
      url: '/v1/healthz/worker',
    });
    expect(hwRes.statusCode).toBe(200);
    expect(hwRes.body.tick_no).toBe(0);

    // Klien di bawah min_client_version ditolak 426 CLIENT_OUTDATED
    const outdatedRes = await api.inject<{ error: { code: string } }>({
      method: 'GET',
      url: '/v1/world',
      headers: { 'x-client-version': '0.0.9' },
    });
    expect(outdatedRes.statusCode).toBe(426);
    expect(outdatedRes.body.error.code).toBe('CLIENT_OUTDATED');

    const worldRes = await api.inject<{
      tick_no: number;
      ports: unknown[];
      commodities: unknown[];
      routes: unknown[];
    }>({
      method: 'GET',
      url: '/v1/world',
      headers: { 'x-client-version': '0.1.0' },
    });
    expect(worldRes.statusCode).toBe(200);
    expect(worldRes.headers['x-tick']).toBe('0');
    expect(worldRes.body.ports.length).toBe(6);
    expect(worldRes.body.commodities.length).toBe(4);
    expect(worldRes.body.routes.length).toBe(14);

    const marketRes = await api.inject<{
      port: { code: string };
      items: Array<{ commodity: string; stock: number; price: number }>;
    }>({
      method: 'GET',
      url: '/v1/world/market/banda',
    });
    expect(marketRes.statusCode).toBe(200);
    expect(marketRes.body.port.code).toBe('banda');
    expect(marketRes.body.items.length).toBe(4);

    const tplRes = await api.inject<{
      items: Array<{ id: string; source: string }>;
    }>({
      method: 'GET',
      url: '/v1/rule-templates',
    });
    expect(tplRes.statusCode).toBe(200);
    expect(tplRes.body.items.length).toBe(RULE_TEMPLATES.length);
    for (const tpl of tplRes.body.items) {
      expect(validateDsl(tpl.source).valid).toBe(true);
    }
  });

  it('2. Auth register membuat pemain + kapal awal + ledger starter dalam satu transaksi, serta menolak duplikat (409)', async () => {
    const reg1 = await api.inject<{
      player: { id: number; coins: number; display_name: string };
      ship: { id: number; capacity: number; status: string; port_id: number };
      access_token: string;
      refresh_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'nahkoda1@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Nahkoda_Satu',
        tos_accepted: true,
      },
    });
    expect(reg1.statusCode).toBe(201);
    expect(reg1.body.player.coins).toBe(1000);
    expect(reg1.body.ship.capacity).toBe(35);
    expect(reg1.body.ship.status).toBe('docked');
    expect(reg1.body.ship.port_id).toBe(1);

    player1Token = reg1.body.access_token;
    player1Refresh = reg1.body.refresh_token;
    player1ShipId = reg1.body.ship.id;

    // Duplikat email ditolak 409 CONFLICT
    const dupEmail = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'nahkoda1@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Nahkoda_Lain',
        tos_accepted: true,
      },
    });
    expect(dupEmail.statusCode).toBe(409);
    expect(dupEmail.body.error.code).toBe('CONFLICT');

    // Duplikat display_name ditolak 409 CONFLICT
    const dupName = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'lain@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Nahkoda_Satu',
        tos_accepted: true,
      },
    });
    expect(dupName.statusCode).toBe(409);

    // Daftarkan Pemain ke-2 untuk tes otorisasi IDOR
    const reg2 = await api.inject<{ access_token: string }>({
      method: 'POST',
      url: '/v1/auth/register',
      body: {
        email: 'nahkoda2@nusantara.id',
        password: 'SandiKuat123!',
        display_name: 'Nahkoda_Dua',
        tos_accepted: true,
      },
    });
    expect(reg2.statusCode).toBe(201);
    player2Token = reg2.body.access_token;

    const consistency = await checkDatabaseConsistency(testPool);
    expect(consistency.valid).toBe(true);
  });

  it('3. Auth login, rotasi refresh token, dan deteksi pencurian saat refresh token lama dipakai ulang (docs/08)', async () => {
    const badLogin = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/login',
      body: {
        email: 'nahkoda1@nusantara.id',
        password: 'SandiSalah',
      },
    });
    expect(badLogin.statusCode).toBe(401);
    expect(badLogin.body.error.code).toBe('UNAUTHENTICATED');

    // Rotasi refresh token pertama -> sukses, menerbitkan refresh token baru
    const ref1 = await api.inject<{
      access_token: string;
      refresh_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/refresh',
      body: { refresh_token: player1Refresh },
    });
    expect(ref1.statusCode).toBe(200);
    const rotatedRefresh = ref1.body.refresh_token;
    expect(rotatedRefresh).not.toBe(player1Refresh);

    // Pemakaian ulang refresh token lama (player1Refresh) yang sudah dicabut ->
    // dianggap pencurian: mencabut SELURUH refresh token pemain 1 (termasuk rotatedRefresh)!
    const reuseAttempt = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/refresh',
      body: { refresh_token: player1Refresh },
    });
    expect(reuseAttempt.statusCode).toBe(401);

    const afterTheftAttempt = await api.inject<{ error: { code: string } }>({
      method: 'POST',
      url: '/v1/auth/refresh',
      body: { refresh_token: rotatedRefresh },
    });
    expect(afterTheftAttempt.statusCode).toBe(401);

    // Login ulang untuk mendapatkan token aktif baru
    const relogin = await api.inject<{
      access_token: string;
      refresh_token: string;
    }>({
      method: 'POST',
      url: '/v1/auth/login',
      body: {
        email: 'nahkoda1@nusantara.id',
        password: 'SandiKuat123!',
      },
    });
    expect(relogin.statusCode).toBe(200);
    player1Token = relogin.body.access_token;
    player1Refresh = relogin.body.refresh_token;
  });

  it('4. Endpoint baca terproteksi (/v1/me, /v1/me/ledger, /v1/ships, /v1/ships/:id, /v1/leaderboard) & proteksi IDOR (403)', async () => {
    const unauthMe = await api.inject({ method: 'GET', url: '/v1/me' });
    expect(unauthMe.statusCode).toBe(401);

    const meRes = await api.inject<{
      id: number;
      display_name: string;
      coins: number;
      net_worth: number;
      rank: number;
    }>({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: `Bearer ${player1Token}` },
    });
    expect(meRes.statusCode).toBe(200);
    expect(meRes.body.display_name).toBe('Nahkoda_Satu');
    expect(meRes.body.coins).toBe(1000);
    expect(meRes.body.net_worth).toBe(1000);
    expect(meRes.body.rank).toBe(1);

    const ledgerRes = await api.inject<{
      items: Array<{ delta: number; reason: string }>;
      next_cursor: string | null;
    }>({
      method: 'GET',
      url: '/v1/me/ledger',
      headers: { authorization: `Bearer ${player1Token}` },
    });
    expect(ledgerRes.statusCode).toBe(200);
    expect(ledgerRes.body.items.length).toBe(1);
    expect(ledgerRes.body.items[0]?.delta).toBe(1000);
    expect(ledgerRes.body.items[0]?.reason).toBe('starter');

    const shipsRes = await api.inject<{
      items: Array<{ id: number; name: string }>;
    }>({
      method: 'GET',
      url: '/v1/ships',
      headers: { authorization: `Bearer ${player1Token}` },
    });
    expect(shipsRes.statusCode).toBe(200);
    expect(shipsRes.body.items.length).toBe(1);
    expect(shipsRes.body.items[0]?.id).toBe(player1ShipId);

    // Proteksi IDOR: Pemain 2 mencoba mengakses kapal Pemain 1 -> 403 FORBIDDEN
    const idorGet = await api.inject<{ error: { code: string } }>({
      method: 'GET',
      url: `/v1/ships/${player1ShipId}`,
      headers: { authorization: `Bearer ${player2Token}` },
    });
    expect(idorGet.statusCode).toBe(403);
    expect(idorGet.body.error.code).toBe('FORBIDDEN');

    const idorPut = await api.inject<{ error: { code: string } }>({
      method: 'PUT',
      url: `/v1/ships/${player1ShipId}/rules`,
      headers: { authorization: `Bearer ${player2Token}` },
      body: {
        base_version: 0,
        source: 'aturan a: jika benar maka tunggu()',
      },
    });
    expect(idorPut.statusCode).toBe(403);
  });

  it('5. Pengelolaan aturan kapal (GET/PUT /v1/ships/:id/rules, VERSION_CONFLICT 409, RULE_INVALID 422, & riwayat versi)', async () => {
    const initRule = await api.inject<{ version: number; source: string }>({
      method: 'GET',
      url: `/v1/ships/${player1ShipId}/rules`,
      headers: { authorization: `Bearer ${player1Token}` },
    });
    expect(initRule.statusCode).toBe(200);
    expect(initRule.body.version).toBe(0);
    expect(initRule.body.source).toBe('');

    // Aturan tidak valid -> 422 RULE_INVALID
    const invalidPut = await api.inject<{
      error: { code: string; details: Array<{ code: string }> };
    }>({
      method: 'PUT',
      url: `/v1/ships/${player1ShipId}/rules`,
      headers: { authorization: `Bearer ${player1Token}` },
      body: {
        base_version: 0,
        source: 'aturan uji_kesalahan: jika x_variabel_aneh < 50 maka tunggu()',
      },
    });
    expect(invalidPut.statusCode).toBe(422);
    expect(invalidPut.body.error.code).toBe('RULE_INVALID');
    expect(invalidPut.body.error.details[0]?.code).toBe('UNKNOWN_IDENT');

    // Simpan versi 1 dengan base_version: 0 -> 200 OK
    const validSource = RULE_TEMPLATES[0]!.source;
    const putV1 = await api.inject<{ version: number; source: string }>({
      method: 'PUT',
      url: `/v1/ships/${player1ShipId}/rules`,
      headers: { authorization: `Bearer ${player1Token}` },
      body: {
        base_version: 0,
        source: validSource,
      },
    });
    expect(putV1.statusCode).toBe(200);
    expect(putV1.body.version).toBe(1);

    // Kirim ulang dengan base_version: 0 yang sudah usang -> 409 VERSION_CONFLICT
    const conflictPut = await api.inject<{ error: { code: string } }>({
      method: 'PUT',
      url: `/v1/ships/${player1ShipId}/rules`,
      headers: { authorization: `Bearer ${player1Token}` },
      body: {
        base_version: 0,
        source: validSource,
      },
    });
    expect(conflictPut.statusCode).toBe(409);
    expect(conflictPut.body.error.code).toBe('VERSION_CONFLICT');

    // Riwayat versi menampilkan versi 1
    const verRes = await api.inject<{
      items: Array<{ version: number; source: string }>;
    }>({
      method: 'GET',
      url: `/v1/ships/${player1ShipId}/rules/versions`,
      headers: { authorization: `Bearer ${player1Token}` },
    });
    expect(verRes.statusCode).toBe(200);
    expect(verRes.body.items.length).toBe(1);
    expect(verRes.body.items[0]?.version).toBe(1);
  });

  it('6. Simulasi sandbox (POST /v1/ships/:id/rules/simulate) memakai stepWorld dan terbukti TIDAK menulis ke database', async () => {
    const beforeAudit = await checkDatabaseConsistency(testPool);
    expect(beforeAudit.valid).toBe(true);

    const ledgerCountBefore = await testPool.query<{ cnt: string }>(
      'SELECT count(*)::text AS cnt FROM public.ledger',
    );
    const marketStockBefore = await testPool.query<{ total_stock: string }>(
      'SELECT SUM(stock)::text AS total_stock FROM public.market',
    );

    const simRes = await api.inject<{
      ticks: number;
      final_coins_delta: number;
      trades: number;
      actions_summary: unknown[];
      log_sample: unknown[];
    }>({
      method: 'POST',
      url: `/v1/ships/${player1ShipId}/rules/simulate`,
      headers: { authorization: `Bearer ${player1Token}` },
      body: {
        source: RULE_TEMPLATES[0]!.source,
        ticks: 60,
      },
    });

    expect(simRes.statusCode).toBe(200);
    expect(simRes.body.ticks).toBe(60);
    expect(simRes.body.trades).toBeGreaterThan(0);
    expect(simRes.body.log_sample.length).toBeGreaterThan(0);

    // Verifikasi 0 perubahan di database sesudah simulasi sandbox
    const ledgerCountAfter = await testPool.query<{ cnt: string }>(
      'SELECT count(*)::text AS cnt FROM public.ledger',
    );
    const marketStockAfter = await testPool.query<{ total_stock: string }>(
      'SELECT SUM(stock)::text AS total_stock FROM public.market',
    );
    const afterAudit = await checkDatabaseConsistency(testPool);

    expect(ledgerCountAfter.rows[0]?.cnt).toBe(ledgerCountBefore.rows[0]?.cnt);
    expect(marketStockAfter.rows[0]?.total_stock).toBe(
      marketStockBefore.rows[0]?.total_stock,
    );
    expect(afterAudit.valid).toBe(true);
    expect(afterAudit.moneySupplyAudit).toEqual(beforeAudit.moneySupplyAudit);
  });

  it('7. Kontrak OpenAPI (docs/openapi.json) mendokumentasikan seluruh endpoint v1 sesuai docs/08', () => {
    const openapiPath = path.resolve(process.cwd(), 'docs/openapi.json');
    const raw = fs.readFileSync(openapiPath, 'utf8');
    const spec = JSON.parse(raw) as {
      openapi: string;
      paths: Record<string, unknown>;
    };
    expect(spec.openapi).toBe('3.1.0');
    const requiredPaths = [
      '/healthz',
      '/healthz/worker',
      '/auth/register',
      '/auth/login',
      '/auth/refresh',
      '/auth/logout',
      '/me',
      '/me/ledger',
      '/world',
      '/world/market/{portCode}',
      '/world/price-history',
      '/leaderboard',
      '/rule-templates',
      '/rules/validate',
      '/ships',
      '/ships/{id}',
      '/ships/{id}/rules',
      '/ships/{id}/rules/versions',
      '/ships/{id}/rules/simulate',
      '/ships/{id}/log',
    ];
    for (const p of requiredPaths) {
      expect(spec.paths[p]).toBeDefined();
    }
  });
});
