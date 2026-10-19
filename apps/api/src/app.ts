import http from 'node:http';
import crypto from 'node:crypto';
import pg from 'pg';
import {
  WORLD_CONFIG,
  WorldEconomyConfig,
  PORTS_SEED,
  ShipStatus,
} from '@jalur-rempah/shared';
import { WorldState, computeCanonicalStateHash } from '@jalur-rempah/econ';
import { validateDsl, RULE_TEMPLATES } from '@jalur-rempah/dsl';
import {
  hashPassword,
  verifyPassword,
  signAccessToken,
  verifyAccessToken,
  generateRefreshToken,
  hashRefreshToken,
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  REFRESH_TOKEN_TTL_MS,
  AccessTokenPayload,
} from './auth/crypto.js';
import {
  InMemoryRateLimiter,
  RATE_LIMIT_GROUPS,
  SandboxConcurrencyQueue,
} from './rate-limit.js';
import { runSandboxSimulation } from './sandbox.js';

export const MAX_SHIPS_PER_PLAYER = 5;
export const SHIP_PURCHASE_COST = 1500n;

export interface ApiErrorResponse {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly details: readonly unknown[];
  };
}

export interface ApiInjectRequest {
  readonly method: string;
  readonly url: string;
  readonly headers?: Readonly<Record<string, string | undefined>>;
  readonly body?: unknown;
  readonly remoteAddress?: string;
}

export interface ApiInjectResponse<T = unknown> {
  readonly statusCode: number;
  readonly headers: Record<string, string>;
  readonly body: T;
  readonly rawBody: string;
}

export interface ApiServerOptions {
  readonly jwtSecret?: string;
  readonly config?: WorldEconomyConfig;
  readonly worldSeed?: number;
  readonly minClientVersion?: string;
  readonly maxBodyBytes?: number;
  readonly maxConcurrentSimulations?: number;
  readonly maxSimulationQueue?: number;
  readonly trustProxy?: boolean;
}

export interface ApiServer {
  inject<T = unknown>(req: ApiInjectRequest): Promise<ApiInjectResponse<T>>;
  listen(port: number, host?: string): Promise<http.Server>;
  close(): Promise<void>;
  readonly rateLimiter: InMemoryRateLimiter;
}

function compareSemver(a: string, b: string): number {
  const pa = a.split('.').map((x) => parseInt(x, 10) || 0);
  const pb = b.split('.').map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const va = pa[i] ?? 0;
    const vb = pb[i] ?? 0;
    if (va < vb) return -1;
    if (va > vb) return 1;
  }
  return 0;
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 120;
}

function isValidDisplayName(name: string): boolean {
  return /^[a-zA-Z0-9_]{3,24}$/.test(name);
}

function getSeasonSummary(tickNo: number): {
  season_id: 1 | 2 | 3;
  season_code: 'muson_barat' | 'muson_timur' | 'pancaroba';
  title: string;
  description: string;
} {
  const idx = Math.floor(Math.max(0, tickNo) / 24) % 3;
  if (idx === 0) {
    return {
      season_id: 1,
      season_code: 'muson_barat',
      title: 'Angin Muson Barat',
      description:
        'Angin bertiup dari barat ke timur Nusantara; pelayaran dari Malaka dan Batavia menuju Maluku lebih ramai.',
    };
  }
  if (idx === 1) {
    return {
      season_id: 2,
      season_code: 'muson_timur',
      title: 'Angin Muson Timur',
      description:
        'Angin bertiup dari timur ke barat Nusantara; armada rempah dari Banda dan Ternate berlayar cepat menuju Jawa dan Malaka.',
    };
  }
  return {
    season_id: 3,
    season_code: 'pancaroba',
    title: 'Musim Pancaroba',
    description:
      'Peralihan angin muson di perairan Nusantara; pasar pelabuhan menyesuaikan cadangan komoditas.',
  };
}

export async function loadWorldSnapshotFromDb(
  pool: pg.Pool,
): Promise<WorldState> {
  const tickRes = await pool.query<{ max_tick: string }>(
    `SELECT COALESCE(MAX(tick_no), 0)::text AS max_tick FROM public.tick_state`,
  );
  const tickNo = Number(tickRes.rows[0]?.max_tick ?? '0');

  const portsRes = await pool.query<{
    id: number;
    code: string;
    name: string;
    treasury: string;
    initial_treasury: string;
  }>(
    `SELECT id, code, name, treasury::text, initial_treasury::text FROM public.ports ORDER BY id ASC`,
  );
  const ports = new Map();
  if (portsRes.rows.length > 0) {
    for (const r of portsRes.rows) {
      ports.set(Number(r.id), {
        id: Number(r.id),
        code: r.code,
        name: r.name,
        treasury: BigInt(r.treasury),
        initialTreasury: BigInt(r.initial_treasury),
      });
    }
  } else {
    for (const p of PORTS_SEED) {
      ports.set(p.id, {
        id: p.id,
        code: p.code,
        name: p.name,
        treasury: p.treasury,
        initialTreasury: p.initial_treasury,
      });
    }
  }

  const marketRes = await pool.query<{
    port_id: number;
    commodity_id: number;
    stock: string;
    target: string;
    production: string;
    consumption: string;
    capacity: string;
    price: string;
  }>(
    `SELECT port_id, commodity_id, stock::text, target::text, production::text, consumption::text, capacity::text, price::text
     FROM public.market ORDER BY port_id ASC, commodity_id ASC`,
  );
  const markets = new Map();
  for (const m of marketRes.rows) {
    markets.set(`${m.port_id}:${m.commodity_id}`, {
      port_id: Number(m.port_id),
      commodity_id: Number(m.commodity_id),
      stock: BigInt(m.stock),
      target: BigInt(m.target),
      production: BigInt(m.production),
      consumption: BigInt(m.consumption),
      capacity: BigInt(m.capacity),
      price: BigInt(m.price),
    });
  }

  const playersRes = await pool.query<{
    id: string;
    coins: string;
  }>(`SELECT id::text, coins::text FROM public.players ORDER BY id ASC`);
  const players = new Map();
  for (const pl of playersRes.rows) {
    const pid = BigInt(pl.id);
    const c = BigInt(pl.coins);
    players.set(pid, {
      id: pid,
      coins: c,
      initialCoins: c,
      ledgerSum: c,
      lastRescueTick: null,
      rescueCount: 0,
    });
  }

  const shipsRes = await pool.query<{
    id: string;
    player_id: string;
    capacity: number;
    status: ShipStatus;
    port_id: number | null;
    dest_port: number | null;
    arrive_tick: string | null;
  }>(
    `SELECT id::text, player_id::text, capacity, status, port_id, dest_port, arrive_tick::text
     FROM public.ships ORDER BY id ASC`,
  );
  const cargoRes = await pool.query<{
    ship_id: string;
    commodity_id: number;
    qty: string;
  }>(`SELECT ship_id::text, commodity_id, qty::text FROM public.ship_cargo`);

  const cargoByShip = new Map<bigint, Map<number, bigint>>();
  for (const cr of cargoRes.rows) {
    const sid = BigInt(cr.ship_id);
    let cmap = cargoByShip.get(sid);
    if (!cmap) {
      cmap = new Map<number, bigint>([
        [1, 0n],
        [2, 0n],
        [3, 0n],
        [4, 0n],
      ]);
      cargoByShip.set(sid, cmap);
    }
    cmap.set(Number(cr.commodity_id), BigInt(cr.qty));
  }

  const ships = new Map();
  for (const sh of shipsRes.rows) {
    const sid = BigInt(sh.id);
    const cmap =
      cargoByShip.get(sid) ??
      new Map<number, bigint>([
        [1, 0n],
        [2, 0n],
        [3, 0n],
        [4, 0n],
      ]);
    ships.set(sid, {
      id: sid,
      playerId: BigInt(sh.player_id),
      capacity: Number(sh.capacity),
      status: sh.status,
      portId: Number(sh.port_id ?? 1),
      destPort: sh.dest_port !== null ? Number(sh.dest_port) : null,
      arriveTick: sh.arrive_tick !== null ? Number(sh.arrive_tick) : null,
      cargo: cmap,
    });
  }

  const auditRes = await pool.query<{
    cumulative_upkeep_sink: string;
    cumulative_source: string;
  }>(
    `SELECT cumulative_upkeep_sink::text, cumulative_source::text FROM public.economy_money_supply_audit`,
  );
  const cumulativeUpkeepSink = BigInt(
    auditRes.rows[0]?.cumulative_upkeep_sink ?? '0',
  );
  const cumulativeSource = BigInt(
    auditRes.rows[0]?.cumulative_source ?? '0',
  );

  const state: WorldState = {
    tickNo,
    players,
    ports,
    markets,
    ships,
    cumulativeUpkeepSink,
    cumulativeSource,
    stateHash: '',
  };
  state.stateHash = computeCanonicalStateHash(state);
  return state;
}

export function createApiServer(
  pool: pg.Pool,
  options?: ApiServerOptions,
): ApiServer {
  const config = options?.config ?? WORLD_CONFIG;
  const worldSeed = options?.worldSeed ?? 101;
  const minClientVersion = options?.minClientVersion ?? '0.1.0';
  const maxBodyBytes = options?.maxBodyBytes ?? 65536;
  const trustProxy = options?.trustProxy ?? true;

  const rateLimiter = new InMemoryRateLimiter();
  const sandboxQueue = new SandboxConcurrencyQueue(
    options?.maxConcurrentSimulations ?? 2,
    options?.maxSimulationQueue ?? 10,
  );

  let httpServer: http.Server | null = null;

  function makeError<T = unknown>(
    statusCode: number,
    code: string,
    message: string,
    details: readonly unknown[] = [],
    extraHeaders?: Record<string, string>,
  ): ApiInjectResponse<T> {
    const bodyObj: ApiErrorResponse = {
      error: { code, message, details },
    };
    const rawBody = JSON.stringify(bodyObj);
    return {
      statusCode,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        ...(extraHeaders ?? {}),
      },
      body: bodyObj as unknown as T,
      rawBody,
    };
  }

  function makeJson<T = unknown>(
    statusCode: number,
    payload: T,
    extraHeaders?: Record<string, string>,
    ifNoneMatchHeader?: string,
  ): ApiInjectResponse<T> {
    const rawBody = JSON.stringify(payload);
    const hash = crypto
      .createHash('sha1')
      .update(rawBody)
      .digest('hex')
      .slice(0, 16);
    const tickVal = extraHeaders?.['x-tick'];
    const etag = tickVal ? `W/"t${tickVal}-${hash}"` : `W/"${hash}"`;
    const headers: Record<string, string> = {
      'content-type': 'application/json; charset=utf-8',
      etag,
      ...(extraHeaders ?? {}),
    };

    if (
      statusCode === 200 &&
      ifNoneMatchHeader &&
      (ifNoneMatchHeader === etag || ifNoneMatchHeader === `W/"tick-${tickVal}"`)
    ) {
      return {
        statusCode: 304,
        headers,
        body: null as unknown as T,
        rawBody: '',
      };
    }

    return {
      statusCode,
      headers,
      body: payload,
      rawBody,
    };
  }

  async function getCurrentTickNo(): Promise<number> {
    try {
      const res = await pool.query<{ max_tick: string }>(
        `SELECT COALESCE(MAX(tick_no), 0)::text AS max_tick FROM public.tick_state`,
      );
      return Number(res.rows[0]?.max_tick ?? '0');
    } catch {
      return 0;
    }
  }

  function extractBearerToken(
    headers: Readonly<Record<string, string | undefined>>,
  ): AccessTokenPayload | null {
    const authHeader =
      headers['authorization'] ?? headers['Authorization'] ?? '';
    if (!authHeader.startsWith('Bearer ')) return null;
    const rawToken = authHeader.slice('Bearer '.length).trim();
    if (!rawToken) return null;
    return verifyAccessToken(
      rawToken,
      options?.jwtSecret !== undefined ? { secret: options.jwtSecret } : {},
    );
  }

  async function flushPlayerUpkeepInTx(
    client: pg.PoolClient,
    playerId: string,
    tickNo: number,
  ): Promise<void> {
    const pRes = await client.query<{ unflushed_upkeep: string }>(
      `SELECT unflushed_upkeep::text FROM public.players WHERE id = $1 FOR UPDATE`,
      [playerId],
    );
    const unflushed = BigInt(pRes.rows[0]?.unflushed_upkeep ?? '0');
    if (unflushed > 0n) {
      await client.query(
        `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
         VALUES ($1, $2, $3, 'upkeep', $4::jsonb)`,
        [
          playerId,
          tickNo,
          (-unflushed).toString(),
          JSON.stringify({ flushed_at_tick: tickNo }),
        ],
      );
      await client.query(
        `UPDATE public.players SET unflushed_upkeep = 0 WHERE id = $1`,
        [playerId],
      );
    }
  }

  async function seedPortIntelInTx(
    client: pg.PoolClient,
    playerId: string,
    portId: number,
    tickNo: number,
  ): Promise<void> {
    await client.query(
      `INSERT INTO public.port_intel (player_id, port_id, commodity_id, price, stock, tick_seen, updated_at)
       SELECT $1, m.port_id, m.commodity_id, m.price, m.stock, $3, now()
       FROM public.market m
       WHERE m.port_id = $2
       ON CONFLICT (player_id, port_id, commodity_id) DO UPDATE
       SET price = EXCLUDED.price,
           stock = EXCLUDED.stock,
           tick_seen = EXCLUDED.tick_seen,
           updated_at = now()`,
      [playerId, portId, tickNo],
    );
  }

  async function handleRequest<T = unknown>(
    req: ApiInjectRequest,
  ): Promise<ApiInjectResponse<T>> {
    const method = req.method.toUpperCase();
    const headersLower: Record<string, string | undefined> = {};
    if (req.headers) {
      for (const [k, v] of Object.entries(req.headers)) {
        headersLower[k.toLowerCase()] = v;
      }
    }
    const ifNoneMatch = headersLower['if-none-match'];

    const clientIp =
      trustProxy && headersLower['x-real-ip']
        ? headersLower['x-real-ip']!
        : (req.remoteAddress ?? '127.0.0.1');

    // Check payload size if raw string body is large
    const rawBodyCheck =
      typeof req.body === 'string'
        ? req.body
        : req.body !== undefined
          ? JSON.stringify(req.body)
          : '';
    if (Buffer.byteLength(rawBodyCheck, 'utf8') > maxBodyBytes) {
      return makeError(
        400,
        'VALIDATION_ERROR',
        `Ukuran body melebihi batas maksimal ${maxBodyBytes} byte.`,
      );
    }

    // Parse URL and normalize optional /v1 prefix
    const parsedUrl = new URL(req.url, 'http://localhost');
    const rawPath = parsedUrl.pathname.replace(/\/+$/, '') || '/';
    const path = rawPath.startsWith('/v1/')
      ? rawPath.slice(3)
      : rawPath === '/v1'
        ? '/'
        : rawPath;

    // Client version check (docs/08: CLIENT_OUTDATED 426)
    const clientVersionHeader = headersLower['x-client-version'];
    if (
      clientVersionHeader &&
      compareSemver(clientVersionHeader, minClientVersion) < 0
    ) {
      return makeError(
        426,
        'CLIENT_OUTDATED',
        `Versi klien (${clientVersionHeader}) lebih rendah dari versi minimum (${minClientVersion}). Silakan perbarui aplikasi.`,
      );
    }

    const bodyObj =
      typeof req.body === 'string' && req.body.length > 0
        ? (() => {
            try {
              return JSON.parse(req.body) as Record<string, unknown>;
            } catch {
              return null;
            }
          })()
        : ((req.body ?? {}) as Record<string, unknown>);

    if (bodyObj === null) {
      return makeError(400, 'VALIDATION_ERROR', 'Format JSON tidak valid.');
    }

    try {
      // 1. Health checks (public, no auth)
      if (method === 'GET' && path === '/healthz') {
        await pool.query('SELECT 1');
        return makeJson(200, { status: 'ok' } as unknown as T);
      }

      if (method === 'GET' && path === '/healthz/worker') {
        const tickRes = await pool.query<{
          tick_no: string;
          finished_at: Date;
        }>(
          `SELECT tick_no::text, finished_at FROM public.tick_state ORDER BY tick_no DESC LIMIT 1`,
        );
        const row = tickRes.rows[0];
        if (!row) {
          return makeJson(200, {
            status: 'idle',
            tick_no: 0,
            age_seconds: 0,
          } as unknown as T);
        }
        const ageSec = Math.max(
          0,
          Math.floor((Date.now() - new Date(row.finished_at).getTime()) / 1000),
        );
        const healthy = ageSec <= config.TICK_SECONDS * 2;
        return makeJson(healthy ? 200 : 503, {
          status: healthy ? 'ok' : 'stale',
          tick_no: Number(row.tick_no),
          age_seconds: ageSec,
        } as unknown as T);
      }

      // 2. Auth endpoints (/auth/*)
      if (path.startsWith('/auth/')) {
        const rl = rateLimiter.check('auth', clientIp, RATE_LIMIT_GROUPS.auth);
        if (!rl.allowed) {
          return makeError(
            429,
            'RATE_LIMITED',
            'Terlalu banyak permintaan autentikasi. Silakan tunggu sebentar.',
            [],
            { 'retry-after': String(rl.retryAfterSec) },
          );
        }

        if (method === 'POST' && path === '/auth/register') {
          const email =
            typeof bodyObj['email'] === 'string'
              ? bodyObj['email'].trim().toLowerCase()
              : '';
          const password =
            typeof bodyObj['password'] === 'string' ? bodyObj['password'] : '';
          const displayName =
            typeof bodyObj['display_name'] === 'string'
              ? bodyObj['display_name'].trim()
              : '';

          if (
            !isValidEmail(email) ||
            password.length < 8 ||
            password.length > 128 ||
            !isValidDisplayName(displayName)
          ) {
            return makeError(
              400,
              'VALIDATION_ERROR',
              'Email harus valid, kata sandi minimal 8 karakter, dan nama tampilan 3-24 karakter alfanumerik/garis bawah.',
            );
          }

          const passwordHash = await hashPassword(password);
          const client = await pool.connect();
          try {
            await client.query('BEGIN');

            const dupCheck = await client.query<{ id: string }>(
              `SELECT id::text FROM public.players WHERE lower(email) = lower($1) OR lower(display_name) = lower($2) LIMIT 1`,
              [email, displayName],
            );
            if (dupCheck.rows.length > 0) {
              await client.query('ROLLBACK');
              return makeError(
                409,
                'CONFLICT',
                'Email atau nama tampilan sudah terdaftar.',
              );
            }

            const starterCoins = config.STARTER_COINS;
            const playerIns = await client.query<{
              id: string;
              email: string;
              display_name: string;
              coins: string;
            }>(
              `INSERT INTO public.players (email, password_hash, display_name, coins)
               VALUES ($1, $2, $3, $4)
               RETURNING id::text, email, display_name, coins::text`,
              [email, passwordHash, displayName, starterCoins.toString()],
            );
            const playerRow = playerIns.rows[0]!;

            // Buat 1 kapal awal di Banda (port_id = 1) tanpa aturan aktif (docs/08)
            const shipIns = await client.query<{
              id: string;
              name: string;
              capacity: number;
              status: string;
              port_id: number;
            }>(
              `INSERT INTO public.ships (player_id, name, capacity, status, port_id)
               VALUES ($1, $2, $3, 'docked', 1)
               RETURNING id::text, name, capacity, status, port_id`,
              [
                playerRow.id,
                'Kapal Perintis',
                config.STARTER_SHIP_CAPACITY,
              ],
            );
            const shipRow = shipIns.rows[0]!;

            // Catat modal awal di ledger (reason = 'starter') dalam transaksi yang sama
            const curTick = await getCurrentTickNo();
            await client.query(
              `INSERT INTO public.ledger (player_id, tick_no, delta, reason, ref_ship)
               VALUES ($1, $2, $3, 'starter', $4)`,
              [
                playerRow.id,
                curTick,
                starterCoins.toString(),
                shipRow.id,
              ],
            );

            // Inisialisasi intelijen harga awal untuk pelabuhan Banda (port_id = 1, ADR-012)
            await seedPortIntelInTx(client, playerRow.id, 1, curTick);

            // Buat access_token dan refresh_token
            const accessToken = signAccessToken(
              {
                sub: playerRow.id,
                email: playerRow.email,
                display_name: playerRow.display_name,
              },
              options?.jwtSecret !== undefined
                ? { secret: options.jwtSecret }
                : {},
            );
            const { rawToken, tokenHash } = generateRefreshToken();
            const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);

            await client.query(
              `INSERT INTO public.refresh_tokens (player_id, token_hash, expires_at, revoked)
               VALUES ($1, $2, $3, false)`,
              [playerRow.id, tokenHash, expiresAt],
            );

            await client.query('COMMIT');

            return makeJson(201, {
              player: {
                id: Number(playerRow.id),
                email: playerRow.email,
                display_name: playerRow.display_name,
                coins: Number(playerRow.coins),
              },
              ship: {
                id: Number(shipRow.id),
                name: shipRow.name,
                capacity: Number(shipRow.capacity),
                status: shipRow.status,
                port_id: Number(shipRow.port_id),
              },
              access_token: accessToken,
              refresh_token: rawToken,
              expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
            } as unknown as T);
          } catch (err) {
            await client.query('ROLLBACK');
            const pgErr = err as { code?: string };
            if (pgErr.code === '23505') {
              return makeError(
                409,
                'CONFLICT',
                'Email atau nama tampilan sudah terdaftar.',
              );
            }
            throw err;
          } finally {
            client.release();
          }
        }

        if (method === 'POST' && path === '/auth/login') {
          const email =
            typeof bodyObj['email'] === 'string'
              ? bodyObj['email'].trim().toLowerCase()
              : '';
          const password =
            typeof bodyObj['password'] === 'string' ? bodyObj['password'] : '';

          if (!email || !password) {
            return makeError(
              400,
              'VALIDATION_ERROR',
              'Email dan kata sandi wajib diisi.',
            );
          }

          const res = await pool.query<{
            id: string;
            email: string;
            display_name: string;
            password_hash: string;
            is_deleted: boolean;
          }>(
            `SELECT id::text, email, display_name, password_hash, is_deleted FROM public.players WHERE lower(email) = lower($1) LIMIT 1`,
            [email],
          );
          const user = res.rows[0];
          if (!user || user.is_deleted) {
            return makeError(
              401,
              'UNAUTHENTICATED',
              'Email atau kata sandi tidak valid.',
            );
          }

          const ok = await verifyPassword(password, user.password_hash);
          if (!ok) {
            return makeError(
              401,
              'UNAUTHENTICATED',
              'Email atau kata sandi tidak valid.',
            );
          }

          const accessToken = signAccessToken(
            {
              sub: user.id,
              email: user.email,
              display_name: user.display_name,
            },
            options?.jwtSecret !== undefined
              ? { secret: options.jwtSecret }
              : {},
          );
          const { rawToken, tokenHash } = generateRefreshToken();
          const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);

          await pool.query(
            `INSERT INTO public.refresh_tokens (player_id, token_hash, expires_at, revoked)
             VALUES ($1, $2, $3, false)`,
            [user.id, tokenHash, expiresAt],
          );

          return makeJson(200, {
            access_token: accessToken,
            refresh_token: rawToken,
            expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
          } as unknown as T);
        }

        if (method === 'POST' && path === '/auth/refresh') {
          const rawRefresh =
            typeof bodyObj['refresh_token'] === 'string'
              ? bodyObj['refresh_token'].trim()
              : '';
          if (!rawRefresh) {
            return makeError(
              400,
              'VALIDATION_ERROR',
              'refresh_token wajib diisi.',
            );
          }

          const tokenHash = hashRefreshToken(rawRefresh);
          const client = await pool.connect();
          try {
            await client.query('BEGIN');

            const tokRes = await client.query<{
              id: string;
              player_id: string;
              expires_at: Date;
              revoked: boolean;
            }>(
              `SELECT id::text, player_id::text, expires_at, revoked
               FROM public.refresh_tokens
               WHERE token_hash = $1
               FOR UPDATE`,
              [tokenHash],
            );
            const tok = tokRes.rows[0];
            if (!tok) {
              await client.query('ROLLBACK');
              return makeError(
                401,
                'UNAUTHENTICATED',
                'Refresh token tidak valid.',
              );
            }

            // Deteksi pencurian: pemakaian ulang refresh token yang sudah dicabut
            // mencabut SELURUH refresh token pemain tersebut! (docs/08 baris 21)
            if (tok.revoked) {
              await client.query(
                `UPDATE public.refresh_tokens SET revoked = true WHERE player_id = $1`,
                [tok.player_id],
              );
              await client.query('COMMIT');
              return makeError(
                401,
                'UNAUTHENTICATED',
                'Refresh token telah dicabut. Demi keamanan, seluruh sesi Anda dihentikan.',
              );
            }

            if (new Date(tok.expires_at).getTime() <= Date.now()) {
              await client.query(
                `UPDATE public.refresh_tokens SET revoked = true WHERE id = $1`,
                [tok.id],
              );
              await client.query('COMMIT');
              return makeError(
                401,
                'UNAUTHENTICATED',
                'Refresh token telah kedaluwarsa.',
              );
            }

            // Cabut token lama dan terbitkan pasangan baru (rotasi)
            await client.query(
              `UPDATE public.refresh_tokens SET revoked = true WHERE id = $1`,
              [tok.id],
            );

            const userRes = await client.query<{
              id: string;
              email: string;
              display_name: string;
              is_deleted: boolean;
            }>(
              `SELECT id::text, email, display_name, is_deleted FROM public.players WHERE id = $1 LIMIT 1`,
              [tok.player_id],
            );
            const user = userRes.rows[0];
            if (!user || user.is_deleted) {
              await client.query('ROLLBACK');
              return makeError(
                401,
                'UNAUTHENTICATED',
                'Akun tidak ditemukan.',
              );
            }

            const newAccess = signAccessToken(
              {
                sub: user.id,
                email: user.email,
                display_name: user.display_name,
              },
              options?.jwtSecret !== undefined
                ? { secret: options.jwtSecret }
                : {},
            );
            const { rawToken: newRefresh, tokenHash: newHash } =
              generateRefreshToken();
            const newExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);

            await client.query(
              `INSERT INTO public.refresh_tokens (player_id, token_hash, expires_at, revoked)
               VALUES ($1, $2, $3, false)`,
              [user.id, newHash, newExpiresAt],
            );

            await client.query('COMMIT');

            return makeJson(200, {
              access_token: newAccess,
              refresh_token: newRefresh,
              expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
            } as unknown as T);
          } catch (err) {
            await client.query('ROLLBACK');
            throw err;
          } finally {
            client.release();
          }
        }

        if (method === 'POST' && path === '/auth/logout') {
          const rawRefresh =
            typeof bodyObj['refresh_token'] === 'string'
              ? bodyObj['refresh_token'].trim()
              : '';
          if (rawRefresh) {
            const tokenHash = hashRefreshToken(rawRefresh);
            await pool.query(
              `UPDATE public.refresh_tokens SET revoked = true WHERE token_hash = $1`,
              [tokenHash],
            );
          }
          return makeJson(200, { ok: true } as unknown as T);
        }
      }

      // 3. Public / Read-Only World & Templates endpoints (also work with or without Bearer token)
      const tickNo = await getCurrentTickNo();
      const tickHeaders = { 'x-tick': String(tickNo) };

      if (method === 'GET' && path === '/stream') {
        const season = getSeasonSummary(tickNo);
        const ssePayload = JSON.stringify({
          tick_no: tickNo,
          tick_seconds: config.TICK_SECONDS,
          season: season.season_code,
          season_title: season.title,
        });
        const rawSse = `event: tick\ndata: ${ssePayload}\n\n`;
        return {
          statusCode: 200,
          headers: {
            'content-type': 'text/event-stream; charset=utf-8',
            'cache-control': 'no-cache',
            connection: 'keep-alive',
            'x-tick': String(tickNo),
          },
          body: {
            event: 'tick',
            data: JSON.parse(ssePayload) as unknown,
          } as unknown as T,
          rawBody: rawSse,
        };
      }

      if (method === 'GET' && path === '/rule-templates') {
        return makeJson(
          200,
          { items: RULE_TEMPLATES } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'GET' && path === '/world') {
        const portsRes = await pool.query<{
          id: number;
          code: string;
          name: string;
          treasury: string;
        }>(
          `SELECT id, code, name, treasury::text FROM public.ports ORDER BY id ASC`,
        );
        const comRes = await pool.query<{
          id: number;
          code: string;
          base_price: string;
        }>(
          `SELECT id, code, base_price::text FROM public.commodities ORDER BY id ASC`,
        );
        const routesRes = await pool.query<{
          from_port: number;
          to_port: number;
          ticks: number;
        }>(
          `SELECT from_port, to_port, ticks FROM public.routes ORDER BY from_port ASC, to_port ASC`,
        );

        const season = getSeasonSummary(tickNo);

        return makeJson(
          200,
          {
            tick_no: tickNo,
            tick_seconds: config.TICK_SECONDS,
            min_client_version: minClientVersion,
            season,
            ports: portsRes.rows.map((p) => ({
              id: Number(p.id),
              code: p.code,
              name: p.name,
              treasury: Number(p.treasury),
            })),
            commodities: comRes.rows.map((c) => ({
              id: Number(c.id),
              code: c.code,
              base_price: Number(c.base_price),
            })),
            routes: routesRes.rows.map((r) => ({
              from_port: Number(r.from_port),
              to_port: Number(r.to_port),
              ticks: Number(r.ticks),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'GET' && path === '/events') {
        const season = getSeasonSummary(tickNo);
        const evRes = await pool.query<{
          tick_no: string;
          season: string;
          event_code: string;
          title: string;
          description: string;
        }>(
          `SELECT tick_no::text, season, event_code, title, description
           FROM public.world_events
           ORDER BY tick_no DESC
           LIMIT 20`,
        );

        return makeJson(
          200,
          {
            tick_no: tickNo,
            current_season: season,
            items: evRes.rows.map((r) => ({
              tick_no: Number(r.tick_no),
              season: r.season,
              event_code: r.event_code,
              title: r.title,
              description: r.description,
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'GET' && path.startsWith('/world/market/')) {
        const portCode = decodeURIComponent(
          path.slice('/world/market/'.length),
        ).toLowerCase();
        const portRes = await pool.query<{
          id: number;
          code: string;
          name: string;
          treasury: string;
        }>(
          `SELECT id, code, name, treasury::text FROM public.ports WHERE lower(code) = $1 OR id::text = $1 LIMIT 1`,
          [portCode],
        );
        const portRow = portRes.rows[0];
        if (!portRow) {
          return makeError(
            404,
            'NOT_FOUND',
            `Pelabuhan '${portCode}' tidak ditemukan.`,
          );
        }

        const mRes = await pool.query<{
          commodity: string;
          stock: string;
          target: string;
          price: string;
        }>(
          `SELECT c.code AS commodity, m.stock::text, m.target::text, m.price::text
           FROM public.market m
           JOIN public.commodities c ON c.id = m.commodity_id
           WHERE m.port_id = $1
           ORDER BY m.commodity_id ASC`,
          [portRow.id],
        );

        return makeJson(
          200,
          {
            tick_no: tickNo,
            port: {
              id: Number(portRow.id),
              code: portRow.code,
              name: portRow.name,
              treasury: Number(portRow.treasury),
            },
            items: mRes.rows.map((r) => ({
              commodity: r.commodity,
              stock: Number(r.stock),
              target: Number(r.target),
              price: Number(r.price),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'GET' && path === '/world/price-history') {
        const portParam = (
          parsedUrl.searchParams.get('port') ?? 'banda'
        ).toLowerCase();
        const comParam = (
          parsedUrl.searchParams.get('commodity') ?? 'pala'
        ).toLowerCase();
        const ticksParam = Math.min(
          Math.max(1, Number(parsedUrl.searchParams.get('ticks') ?? '100')),
          500,
        );

        const pRes = await pool.query<{ id: number; code: string }>(
          `SELECT id, code FROM public.ports WHERE lower(code) = $1 OR id::text = $1 LIMIT 1`,
          [portParam],
        );
        const cRes = await pool.query<{ id: number; code: string }>(
          `SELECT id, code FROM public.commodities WHERE lower(code) = $1 OR id::text = $1 LIMIT 1`,
          [comParam],
        );
        const pRow = pRes.rows[0];
        const cRow = cRes.rows[0];
        if (!pRow || !cRow) {
          return makeError(
            404,
            'NOT_FOUND',
            'Pelabuhan atau komoditas tidak ditemukan.',
          );
        }

        const histRes = await pool.query<{
          tick_no: string;
          price: string;
          stock: string;
        }>(
          `SELECT tick_no::text, price::text, stock::text
           FROM public.market_history
           WHERE port_id = $1 AND commodity_id = $2
           ORDER BY tick_no DESC
           LIMIT $3`,
          [pRow.id, cRow.id, ticksParam],
        );

        return makeJson(
          200,
          {
            tick_no: tickNo,
            port: pRow.code,
            commodity: cRow.code,
            points: histRes.rows.reverse().map((r) => ({
              tick_no: Number(r.tick_no),
              price: Number(r.price),
              stock: Number(r.stock),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'GET' && path === '/leaderboard') {
        const limit = Math.min(
          Math.max(1, Number(parsedUrl.searchParams.get('limit') ?? '50')),
          100,
        );
        const lbRes = await pool.query<{
          display_name: string;
          net_worth: string;
        }>(
          `SELECT
             p.display_name,
             (p.coins + COALESCE(SUM(sc.qty * c.base_price), 0))::text AS net_worth
           FROM public.players p
           LEFT JOIN public.ships s ON s.player_id = p.id
           LEFT JOIN public.ship_cargo sc ON sc.ship_id = s.id
           LEFT JOIN public.commodities c ON c.id = sc.commodity_id
           WHERE p.is_deleted = false
           GROUP BY p.id, p.display_name, p.coins
           ORDER BY (p.coins + COALESCE(SUM(sc.qty * c.base_price), 0)) DESC, p.id ASC
           LIMIT $1`,
          [limit],
        );

        return makeJson(
          200,
          {
            tick_no: tickNo,
            items: lbRes.rows.map((r, i) => ({
              rank: i + 1,
              display_name: r.display_name,
              net_worth: Number(r.net_worth),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      // 4. Protected endpoints (require valid Bearer access token)
      const authUser = extractBearerToken(headersLower);
      if (!authUser) {
        return makeError(
          401,
          'UNAUTHENTICATED',
          'Token akses tidak ada atau tidak valid.',
        );
      }

      // Rate limit per authenticated player (60 req/min general)
      const genRl = rateLimiter.check(
        'general',
        authUser.sub,
        RATE_LIMIT_GROUPS.general,
      );
      if (!genRl.allowed) {
        return makeError(
          429,
          'RATE_LIMITED',
          'Batas permintaan terlampaui.',
          [],
          { 'retry-after': String(genRl.retryAfterSec) },
        );
      }

      if (method === 'POST' && path === '/rules/validate') {
        const source =
          typeof bodyObj['source'] === 'string' ? bodyObj['source'] : '';
        const val = validateDsl(source);
        return makeJson(
          200,
          {
            valid: val.valid,
            errors: val.errors.map((e) => ({
              line: e.line,
              column: e.column,
              code: e.code,
              message: e.message,
            })),
          } as unknown as T,
          tickHeaders,
        );
      }

      if (method === 'GET' && path === '/me') {
        const meRes = await pool.query<{
          id: string;
          display_name: string;
          coins: string;
          net_worth: string;
          rank: string;
        }>(
          `WITH ranked AS (
             SELECT
               p.id,
               p.display_name,
               p.coins,
               (p.coins + COALESCE(SUM(sc.qty * c.base_price), 0)) AS net_worth,
               RANK() OVER (ORDER BY (p.coins + COALESCE(SUM(sc.qty * c.base_price), 0)) DESC, p.id ASC) AS rnk
             FROM public.players p
             LEFT JOIN public.ships s ON s.player_id = p.id
             LEFT JOIN public.ship_cargo sc ON sc.ship_id = s.id
             LEFT JOIN public.commodities c ON c.id = sc.commodity_id
             WHERE p.is_deleted = false
             GROUP BY p.id, p.display_name, p.coins
           )
           SELECT id::text, display_name, coins::text, net_worth::text, rnk::text AS rank
           FROM ranked
           WHERE id = $1`,
          [authUser.sub],
        );
        const me = meRes.rows[0];
        if (!me) {
          return makeError(404, 'NOT_FOUND', 'Pemain tidak ditemukan.');
        }

        return makeJson(
          200,
          {
            id: Number(me.id),
            display_name: me.display_name,
            coins: Number(me.coins),
            net_worth: Number(me.net_worth),
            rank: Number(me.rank),
          } as unknown as T,
          tickHeaders,
        );
      }

      if (method === 'DELETE' && path === '/me') {
        // Penghapusan & anonimisasi akun (docs/08 & docs/09 baris 71):
        // Kapal, kargo, aturan, dan refresh token dihapus; ledger dipertahankan dan akun dianonimkan
        // dengan menjaga invarian konservasi uang global (economy_money_supply_audit diff == 0).
        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          const pRes = await client.query<{
            id: string;
            coins: string;
            unflushed_upkeep: string;
            is_deleted: boolean;
          }>(
            `SELECT id::text, coins::text, unflushed_upkeep::text, is_deleted
             FROM public.players
             WHERE id = $1
             FOR UPDATE`,
            [authUser.sub],
          );
          const pRow = pRes.rows[0];
          if (!pRow || pRow.is_deleted) {
            await client.query('ROLLBACK');
            return makeError(404, 'NOT_FOUND', 'Akun tidak ditemukan.');
          }

          // Batalkan kontrak terbuka milik pemain dan kembalikan escrow dari kas pelabuhan
          const openContracts = await client.query<{
            id: string;
            port_id: number;
            reward_coins: string;
          }>(
            `SELECT id::text, port_id, reward_coins::text
             FROM public.trade_contracts
             WHERE creator_id = $1 AND status = 'open'
             FOR UPDATE`,
            [pRow.id],
          );
          let refundedEscrow = 0n;
          for (const oc of openContracts.rows) {
            const rw = BigInt(oc.reward_coins);
            refundedEscrow += rw;
            await client.query(
              `UPDATE public.ports SET treasury = treasury - $1 WHERE id = $2`,
              [rw.toString(), oc.port_id],
            );
            await client.query(
              `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
               VALUES ($1, $2, $3, 'sell', $4::jsonb)`,
              [
                pRow.id,
                tickNo,
                rw.toString(),
                JSON.stringify({ contract_refund: Number(oc.id) }),
              ],
            );
            await client.query(
              `UPDATE public.trade_contracts SET status = 'cancelled' WHERE id = $1`,
              [oc.id],
            );
          }

          const totalSink =
            BigInt(pRow.coins) + BigInt(pRow.unflushed_upkeep) + refundedEscrow;
          if (totalSink > 0n) {
            await client.query(
              `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
               VALUES ($1, $2, $3, 'upkeep', $4::jsonb)`,
              [
                pRow.id,
                tickNo,
                (-totalSink).toString(),
                JSON.stringify({ account_deleted: true }),
              ],
            );
          }

          // Hapus sesi, intel, keanggotaan serikat, log aksi, aturan, memori kapal, kargo, dan kapal
          await client.query(
            `DELETE FROM public.refresh_tokens WHERE player_id = $1`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.port_intel WHERE player_id = $1`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.guild_members WHERE player_id = $1`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.action_log WHERE ship_id IN (SELECT id FROM public.ships WHERE player_id = $1)`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.rule_sets WHERE ship_id IN (SELECT id FROM public.ships WHERE player_id = $1)`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.ship_memory WHERE ship_id IN (SELECT id FROM public.ships WHERE player_id = $1)`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.ship_cargo WHERE ship_id IN (SELECT id FROM public.ships WHERE player_id = $1)`,
            [pRow.id],
          );
          await client.query(
            `DELETE FROM public.ships WHERE player_id = $1`,
            [pRow.id],
          );

          // Anonimkan baris players agar FK pada ledger tetap valid
          const anonEmail = `anon_${pRow.id}@deleted.local`;
          const anonName = `anon_${pRow.id}`;
          await client.query(
            `UPDATE public.players
             SET email = $1,
                 display_name = $2,
                 password_hash = 'DELETED',
                 coins = 0,
                 unflushed_upkeep = 0,
                 cumulative_upkeep_paid = cumulative_upkeep_paid + $3,
                 is_deleted = true,
                 deleted_at = now()
             WHERE id = $4`,
            [
              anonEmail,
              anonName,
              (BigInt(pRow.coins) + refundedEscrow).toString(),
              pRow.id,
            ],
          );

          await client.query('COMMIT');
          return makeJson(
            200,
            {
              ok: true,
              anonymized_player_id: Number(pRow.id),
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          throw err;
        } finally {
          client.release();
        }
      }

      if (method === 'GET' && path === '/me/ledger') {
        const limit = Math.min(
          Math.max(1, Number(parsedUrl.searchParams.get('limit') ?? '50')),
          100,
        );
        const cursor = parsedUrl.searchParams.get('cursor');
        const cursorId = cursor ? BigInt(cursor) : null;

        const lRes =
          cursorId !== null
            ? await pool.query<{
                id: string;
                tick_no: string | null;
                delta: string;
                reason: string;
                ref_ship: string | null;
                meta: Record<string, unknown> | null;
                created_at: Date;
              }>(
                `SELECT id::text, tick_no::text, delta::text, reason, ref_ship::text, meta, created_at
                 FROM public.ledger
                 WHERE player_id = $1 AND id < $2
                 ORDER BY id DESC
                 LIMIT $3`,
                [authUser.sub, cursorId.toString(), limit + 1],
              )
            : await pool.query<{
                id: string;
                tick_no: string | null;
                delta: string;
                reason: string;
                ref_ship: string | null;
                meta: Record<string, unknown> | null;
                created_at: Date;
              }>(
                `SELECT id::text, tick_no::text, delta::text, reason, ref_ship::text, meta, created_at
                 FROM public.ledger
                 WHERE player_id = $1
                 ORDER BY id DESC
                 LIMIT $2`,
                [authUser.sub, limit + 1],
              );

        const hasMore = lRes.rows.length > limit;
        const slice = hasMore ? lRes.rows.slice(0, limit) : lRes.rows;
        const nextCursor = hasMore ? (slice[slice.length - 1]?.id ?? null) : null;

        return makeJson(
          200,
          {
            items: slice.map((r) => ({
              id: Number(r.id),
              tick_no: r.tick_no !== null ? Number(r.tick_no) : null,
              delta: Number(r.delta),
              reason: r.reason,
              ref_ship: r.ref_ship !== null ? Number(r.ref_ship) : null,
              meta: r.meta,
              created_at: new Date(r.created_at).toISOString(),
            })),
            next_cursor: nextCursor,
          } as unknown as T,
          tickHeaders,
        );
      }

      if (method === 'GET' && path === '/intel') {
        const intelRes = await pool.query<{
          port_id: number;
          port_code: string;
          commodity_id: number;
          commodity_code: string;
          price: string;
          stock: string;
          tick_seen: string;
        }>(
          `SELECT
             pi.port_id,
             p.code AS port_code,
             pi.commodity_id,
             c.code AS commodity_code,
             pi.price::text,
             pi.stock::text,
             pi.tick_seen::text
           FROM public.port_intel pi
           JOIN public.ports p ON p.id = pi.port_id
           JOIN public.commodities c ON c.id = pi.commodity_id
           WHERE pi.player_id = $1
           ORDER BY pi.port_id ASC, pi.commodity_id ASC`,
          [authUser.sub],
        );

        return makeJson(
          200,
          {
            tick_no: tickNo,
            items: intelRes.rows.map((r) => ({
              port_id: Number(r.port_id),
              port_code: r.port_code,
              commodity_id: Number(r.commodity_id),
              commodity_code: r.commodity_code,
              price: Number(r.price),
              stock: Number(r.stock),
              tick_seen: Number(r.tick_seen),
              age_ticks: Math.max(0, tickNo - Number(r.tick_seen)),
            })),
          } as unknown as T,
          tickHeaders,
        );
      }

      if (method === 'GET' && path === '/guilds') {
        const gRes = await pool.query<{
          id: string;
          code: string;
          name: string;
          description: string;
          leader_name: string;
          member_count: string;
        }>(
          `SELECT
             g.id::text,
             g.code,
             g.name,
             g.description,
             p.display_name AS leader_name,
             COUNT(gm.player_id)::text AS member_count
           FROM public.guilds g
           JOIN public.players p ON p.id = g.leader_id
           LEFT JOIN public.guild_members gm ON gm.guild_id = g.id
           GROUP BY g.id, g.code, g.name, g.description, p.display_name
           ORDER BY COUNT(gm.player_id) DESC, g.id ASC`,
        );

        return makeJson(
          200,
          {
            items: gRes.rows.map((r) => ({
              id: Number(r.id),
              code: r.code,
              name: r.name,
              description: r.description,
              leader_name: r.leader_name,
              member_count: Number(r.member_count),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'POST' && path === '/guilds') {
        const code =
          typeof bodyObj['code'] === 'string'
            ? bodyObj['code'].trim().toLowerCase()
            : '';
        const name =
          typeof bodyObj['name'] === 'string' ? bodyObj['name'].trim() : '';
        const description =
          typeof bodyObj['description'] === 'string'
            ? bodyObj['description'].trim()
            : '';

        if (!/^[a-z0-9_]{3,16}$/.test(code) || name.length < 3 || name.length > 40) {
          return makeError(
            400,
            'VALIDATION_ERROR',
            'Kode serikat harus 3-16 karakter alfanumerik/garis bawah dan nama 3-40 karakter.',
          );
        }

        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          const existingMember = await client.query<{ guild_id: string }>(
            `SELECT guild_id::text FROM public.guild_members WHERE player_id = $1 LIMIT 1`,
            [authUser.sub],
          );
          if (existingMember.rows.length > 0) {
            await client.query('ROLLBACK');
            return makeError(
              409,
              'CONFLICT',
              'Anda sudah tergabung dalam serikat dagang.',
            );
          }

          const gIns = await client.query<{
            id: string;
            code: string;
            name: string;
            description: string;
          }>(
            `INSERT INTO public.guilds (code, name, leader_id, description)
             VALUES ($1, $2, $3, $4)
             RETURNING id::text, code, name, description`,
            [code, name, authUser.sub, description],
          );
          const gRow = gIns.rows[0]!;

          await client.query(
            `INSERT INTO public.guild_members (guild_id, player_id, role)
             VALUES ($1, $2, 'leader')`,
            [gRow.id, authUser.sub],
          );

          await client.query('COMMIT');
          return makeJson(
            201,
            {
              id: Number(gRow.id),
              code: gRow.code,
              name: gRow.name,
              description: gRow.description,
              role: 'leader',
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          const pgErr = err as { code?: string };
          if (pgErr.code === '23505') {
            return makeError(
              409,
              'CONFLICT',
              'Kode atau nama serikat dagang sudah digunakan.',
            );
          }
          throw err;
        } finally {
          client.release();
        }
      }

      const guildJoinMatch = /^\/guilds\/([a-zA-Z0-9_]+)\/join$/.exec(path);
      if (method === 'POST' && guildJoinMatch) {
        const guildCode = guildJoinMatch[1]!.toLowerCase();
        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          const gRes = await client.query<{
            id: string;
            code: string;
            name: string;
          }>(
            `SELECT id::text, code, name FROM public.guilds WHERE lower(code) = $1 LIMIT 1`,
            [guildCode],
          );
          const gRow = gRes.rows[0];
          if (!gRow) {
            await client.query('ROLLBACK');
            return makeError(
              404,
              'NOT_FOUND',
              `Serikat dagang '${guildCode}' tidak ditemukan.`,
            );
          }

          await client.query(
            `DELETE FROM public.guild_members WHERE player_id = $1`,
            [authUser.sub],
          );
          await client.query(
            `INSERT INTO public.guild_members (guild_id, player_id, role)
             VALUES ($1, $2, 'member')`,
            [gRow.id, authUser.sub],
          );

          await client.query('COMMIT');
          return makeJson(
            200,
            {
              guild_id: Number(gRow.id),
              code: gRow.code,
              name: gRow.name,
              role: 'member',
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          throw err;
        } finally {
          client.release();
        }
      }

      if (method === 'GET' && path === '/contracts') {
        const statusFilter = parsedUrl.searchParams.get('status') ?? 'open';
        const cRes = await pool.query<{
          id: string;
          creator_id: string;
          creator_name: string;
          port_id: number;
          port_code: string;
          commodity_id: number;
          commodity_code: string;
          qty: string;
          reward_coins: string;
          status: string;
          created_tick: string;
        }>(
          `SELECT
             tc.id::text,
             tc.creator_id::text,
             p.display_name AS creator_name,
             tc.port_id,
             pr.code AS port_code,
             tc.commodity_id,
             cm.code AS commodity_code,
             tc.qty::text,
             tc.reward_coins::text,
             tc.status,
             tc.created_tick::text
           FROM public.trade_contracts tc
           JOIN public.players p ON p.id = tc.creator_id
           JOIN public.ports pr ON pr.id = tc.port_id
           JOIN public.commodities cm ON cm.id = tc.commodity_id
           WHERE tc.status = $1
           ORDER BY tc.id DESC
           LIMIT 50`,
          [statusFilter],
        );

        return makeJson(
          200,
          {
            items: cRes.rows.map((r) => ({
              id: Number(r.id),
              creator_id: Number(r.creator_id),
              creator_name: r.creator_name,
              port_id: Number(r.port_id),
              port_code: r.port_code,
              commodity_id: Number(r.commodity_id),
              commodity_code: r.commodity_code,
              qty: Number(r.qty),
              reward_coins: Number(r.reward_coins),
              status: r.status,
              created_tick: Number(r.created_tick),
            })),
          } as unknown as T,
          tickHeaders,
          ifNoneMatch,
        );
      }

      if (method === 'POST' && path === '/contracts') {
        const portId =
          typeof bodyObj['port_id'] === 'number' ? Math.trunc(bodyObj['port_id']) : 0;
        const commodityId =
          typeof bodyObj['commodity_id'] === 'number'
            ? Math.trunc(bodyObj['commodity_id'])
            : 0;
        const qty =
          typeof bodyObj['qty'] === 'number' ? Math.trunc(bodyObj['qty']) : 0;
        const rewardCoins =
          typeof bodyObj['reward_coins'] === 'number'
            ? Math.trunc(bodyObj['reward_coins'])
            : 0;

        if (
          portId < 1 ||
          portId > 6 ||
          commodityId < 1 ||
          commodityId > 4 ||
          qty <= 0 ||
          qty > 500 ||
          rewardCoins <= 0
        ) {
          return makeError(
            400,
            'VALIDATION_ERROR',
            'Parameter kontrak (port_id, commodity_id, qty, reward_coins) tidak valid.',
          );
        }

        const rewardBig = BigInt(rewardCoins);
        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          await flushPlayerUpkeepInTx(client, authUser.sub, tickNo);

          const pRes = await client.query<{ coins: string }>(
            `SELECT coins::text FROM public.players WHERE id = $1 FOR UPDATE`,
            [authUser.sub],
          );
          const currentCoins = BigInt(pRes.rows[0]?.coins ?? '0');
          if (currentCoins < rewardBig) {
            await client.query('ROLLBACK');
            return makeError(
              422,
              'INSUFFICIENT_COINS',
              'Koin tidak cukup untuk menjaminkan imbalan kontrak pengiriman.',
            );
          }

          // Pindahkan imbalan kontrak sebagai escrow ke kas pelabuhan tujuan agar konservasi uang 100% terjaga
          await client.query(
            `UPDATE public.players SET coins = coins - $1 WHERE id = $2`,
            [rewardBig.toString(), authUser.sub],
          );
          await client.query(
            `UPDATE public.ports SET treasury = treasury + $1 WHERE id = $2`,
            [rewardBig.toString(), portId],
          );

          const cIns = await client.query<{ id: string }>(
            `INSERT INTO public.trade_contracts (creator_id, port_id, commodity_id, qty, reward_coins, status, created_tick)
             VALUES ($1, $2, $3, $4, $5, 'open', $6)
             RETURNING id::text`,
            [
              authUser.sub,
              portId,
              commodityId,
              qty,
              rewardBig.toString(),
              tickNo,
            ],
          );
          const contractId = cIns.rows[0]!.id;

          await client.query(
            `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
             VALUES ($1, $2, $3, 'buy', $4::jsonb)`,
            [
              authUser.sub,
              tickNo,
              (-rewardBig).toString(),
              JSON.stringify({
                contract_escrow: Number(contractId),
                port_id: portId,
                commodity_id: commodityId,
                qty,
              }),
            ],
          );

          await client.query('COMMIT');
          return makeJson(
            201,
            {
              id: Number(contractId),
              port_id: portId,
              commodity_id: commodityId,
              qty,
              reward_coins: rewardCoins,
              status: 'open',
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          throw err;
        } finally {
          client.release();
        }
      }

      const contractFulfillMatch = /^\/contracts\/(\d+)\/fulfill$/.exec(path);
      if (method === 'POST' && contractFulfillMatch) {
        const contractIdStr = contractFulfillMatch[1]!;
        const shipIdNum =
          typeof bodyObj['ship_id'] === 'number'
            ? Math.trunc(bodyObj['ship_id'])
            : 0;
        if (shipIdNum <= 0) {
          return makeError(
            400,
            'VALIDATION_ERROR',
            'ship_id wajib diisi untuk memenuhi kontrak pengiriman.',
          );
        }

        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          const tcRes = await client.query<{
            id: string;
            port_id: number;
            commodity_id: number;
            qty: string;
            reward_coins: string;
            status: string;
          }>(
            `SELECT id::text, port_id, commodity_id, qty::text, reward_coins::text, status
             FROM public.trade_contracts
             WHERE id = $1
             FOR UPDATE`,
            [contractIdStr],
          );
          const tc = tcRes.rows[0];
          if (!tc || tc.status !== 'open') {
            await client.query('ROLLBACK');
            return makeError(
              404,
              'NOT_FOUND',
              'Kontrak pengiriman terbuka tidak ditemukan.',
            );
          }

          const shRes = await client.query<{
            id: string;
            player_id: string;
            status: string;
            port_id: number | null;
          }>(
            `SELECT id::text, player_id::text, status, port_id
             FROM public.ships
             WHERE id = $1
             FOR UPDATE`,
            [String(shipIdNum)],
          );
          const sh = shRes.rows[0];
          if (!sh || sh.player_id !== authUser.sub) {
            await client.query('ROLLBACK');
            return makeError(
              403,
              'FORBIDDEN',
              'Kapal bukan milik Anda atau tidak ditemukan.',
            );
          }
          if (
            (sh.status !== 'docked' && sh.status !== 'grounded') ||
            Number(sh.port_id) !== Number(tc.port_id)
          ) {
            await client.query('ROLLBACK');
            return makeError(
              422,
              'NOT_DOCKED',
              'Kapal harus sedang bersandar di pelabuhan tujuan kontrak.',
            );
          }

          const cargoRes = await client.query<{ qty: string }>(
            `SELECT qty::text FROM public.ship_cargo
             WHERE ship_id = $1 AND commodity_id = $2
             FOR UPDATE`,
            [sh.id, tc.commodity_id],
          );
          const haveQty = BigInt(cargoRes.rows[0]?.qty ?? '0');
          const needQty = BigInt(tc.qty);
          if (haveQty < needQty) {
            await client.query('ROLLBACK');
            return makeError(
              422,
              'OUT_OF_STOCK',
              `Muatan komoditas di kapal (${haveQty.toString()}) kurang dari jumlah kontrak (${needQty.toString()}).`,
            );
          }

          await flushPlayerUpkeepInTx(client, authUser.sub, tickNo);

          const rewardBig = BigInt(tc.reward_coins);

          // Kurangi kargo kapal & serahkan ke pasar pelabuhan (dibatasi kapasitas gudang)
          await client.query(
            `UPDATE public.ship_cargo SET qty = qty - $1 WHERE ship_id = $2 AND commodity_id = $3`,
            [needQty.toString(), sh.id, tc.commodity_id],
          );
          await client.query(
            `UPDATE public.market
             SET stock = LEAST(capacity, stock + $1)
             WHERE port_id = $2 AND commodity_id = $3`,
            [needQty.toString(), tc.port_id, tc.commodity_id],
          );

          // Bayarkan escrow dari kas pelabuhan ke pemain yang menyelesaikan kontrak
          await client.query(
            `UPDATE public.ports SET treasury = treasury - $1 WHERE id = $2`,
            [rewardBig.toString(), tc.port_id],
          );
          await client.query(
            `UPDATE public.players SET coins = coins + $1 WHERE id = $2`,
            [rewardBig.toString(), authUser.sub],
          );
          await client.query(
            `INSERT INTO public.ledger (player_id, tick_no, delta, reason, ref_ship, meta)
             VALUES ($1, $2, $3, 'sell', $4, $5::jsonb)`,
            [
              authUser.sub,
              tickNo,
              rewardBig.toString(),
              sh.id,
              JSON.stringify({
                contract_fulfilled: Number(tc.id),
                port_id: tc.port_id,
                commodity_id: tc.commodity_id,
                qty: Number(needQty),
              }),
            ],
          );

          await client.query(
            `UPDATE public.trade_contracts
             SET status = 'fulfilled',
                 fulfilled_by = $1,
                 fulfilled_tick = $2
             WHERE id = $3`,
            [authUser.sub, tickNo, tc.id],
          );

          await client.query('COMMIT');
          return makeJson(
            200,
            {
              id: Number(tc.id),
              status: 'fulfilled',
              reward_coins: Number(rewardBig),
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          throw err;
        } finally {
          client.release();
        }
      }

      if (method === 'GET' && path === '/ships') {
        const sRes = await pool.query<{
          id: string;
          name: string;
          capacity: number;
          status: string;
          port_id: number | null;
          dest_port: number | null;
          arrive_tick: string | null;
        }>(
          `SELECT id::text, name, capacity, status, port_id, dest_port, arrive_tick::text
           FROM public.ships
           WHERE player_id = $1
           ORDER BY id ASC`,
          [authUser.sub],
        );

        const items = [];
        for (const sh of sRes.rows) {
          const cRes = await pool.query<{
            commodity: string;
            qty: string;
          }>(
            `SELECT c.code AS commodity, sc.qty::text
             FROM public.ship_cargo sc
             JOIN public.commodities c ON c.id = sc.commodity_id
             WHERE sc.ship_id = $1 AND sc.qty > 0
             ORDER BY sc.commodity_id ASC`,
            [sh.id],
          );
          items.push({
            id: Number(sh.id),
            name: sh.name,
            capacity: Number(sh.capacity),
            status: sh.status,
            port_id: sh.port_id !== null ? Number(sh.port_id) : null,
            dest_port: sh.dest_port !== null ? Number(sh.dest_port) : null,
            arrive_tick:
              sh.arrive_tick !== null ? Number(sh.arrive_tick) : null,
            cargo: cRes.rows.map((c) => ({
              commodity: c.commodity,
              qty: Number(c.qty),
            })),
          });
        }

        return makeJson(200, { items } as unknown as T, tickHeaders);
      }

      if (method === 'POST' && path === '/ships/buy') {
        const shipName =
          typeof bodyObj['name'] === 'string' ? bodyObj['name'].trim() : '';
        const portId =
          typeof bodyObj['port_id'] === 'number'
            ? Math.trunc(bodyObj['port_id'])
            : 1;

        if (shipName.length < 3 || shipName.length > 32 || portId < 1 || portId > 6) {
          return makeError(
            400,
            'VALIDATION_ERROR',
            'Nama kapal harus 3-32 karakter dan port_id harus pelabuhan valid (1..6).',
          );
        }

        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          await flushPlayerUpkeepInTx(client, authUser.sub, tickNo);

          const pRes = await client.query<{ coins: string }>(
            `SELECT coins::text FROM public.players WHERE id = $1 FOR UPDATE`,
            [authUser.sub],
          );
          const coins = BigInt(pRes.rows[0]?.coins ?? '0');

          const cntRes = await client.query<{ cnt: string }>(
            `SELECT COUNT(*)::text AS cnt FROM public.ships WHERE player_id = $1`,
            [authUser.sub],
          );
          const currentShipCount = Number(cntRes.rows[0]?.cnt ?? '0');
          if (currentShipCount >= MAX_SHIPS_PER_PLAYER) {
            await client.query('ROLLBACK');
            return makeError(
              422,
              'FLEET_LIMIT_REACHED',
              `Jumlah kapal maksimal per pemain adalah ${MAX_SHIPS_PER_PLAYER}.`,
            );
          }

          if (coins < SHIP_PURCHASE_COST) {
            await client.query('ROLLBACK');
            return makeError(
              422,
              'INSUFFICIENT_COINS',
              `Koin tidak cukup untuk membeli kapal baru (biaya ${SHIP_PURCHASE_COST.toString()} koin).`,
            );
          }

          const sIns = await client.query<{
            id: string;
            name: string;
            capacity: number;
            status: string;
            port_id: number;
          }>(
            `INSERT INTO public.ships (player_id, name, capacity, status, port_id)
             VALUES ($1, $2, $3, 'docked', $4)
             RETURNING id::text, name, capacity, status, port_id`,
            [authUser.sub, shipName, config.STARTER_SHIP_CAPACITY, portId],
          );
          const sRow = sIns.rows[0]!;

          // Pembayaran pembelian kapal masuk ke kas pelabuhan galangan kapal sehingga konservasi uang tetap utuh
          await client.query(
            `UPDATE public.players SET coins = coins - $1 WHERE id = $2`,
            [SHIP_PURCHASE_COST.toString(), authUser.sub],
          );
          await client.query(
            `UPDATE public.ports SET treasury = treasury + $1 WHERE id = $2`,
            [SHIP_PURCHASE_COST.toString(), portId],
          );
          await client.query(
            `INSERT INTO public.ledger (player_id, tick_no, delta, reason, ref_ship, meta)
             VALUES ($1, $2, $3, 'buy', $4, $5::jsonb)`,
            [
              authUser.sub,
              tickNo,
              (-SHIP_PURCHASE_COST).toString(),
              sRow.id,
              JSON.stringify({
                ship_purchase: true,
                port_id: portId,
                ship_name: shipName,
              }),
            ],
          );

          await seedPortIntelInTx(client, authUser.sub, portId, tickNo);

          await client.query('COMMIT');
          return makeJson(
            201,
            {
              ship: {
                id: Number(sRow.id),
                name: sRow.name,
                capacity: Number(sRow.capacity),
                status: sRow.status,
                port_id: Number(sRow.port_id),
                cargo: [],
              },
              cost: Number(SHIP_PURCHASE_COST),
              remaining_coins: Number(coins - SHIP_PURCHASE_COST),
            } as unknown as T,
            tickHeaders,
          );
        } catch (err) {
          await client.query('ROLLBACK');
          const pgErr = err as { code?: string };
          if (pgErr.code === '23505') {
            return makeError(
              409,
              'CONFLICT',
              'Nama kapal sudah digunakan di armada Anda.',
            );
          }
          throw err;
        } finally {
          client.release();
        }
      }

      // Routes matching /ships/:id...
      const shipMatch = /^\/ships\/(\d+)(?:\/(.*))?$/.exec(path);
      if (shipMatch) {
        const shipIdStr = shipMatch[1]!;
        const subPath = shipMatch[2] ?? '';

        const shRes = await pool.query<{
          id: string;
          player_id: string;
          name: string;
          capacity: number;
          status: string;
          port_id: number | null;
          dest_port: number | null;
          arrive_tick: string | null;
        }>(
          `SELECT id::text, player_id::text, name, capacity, status, port_id, dest_port, arrive_tick::text
           FROM public.ships
           WHERE id = $1
           LIMIT 1`,
          [shipIdStr],
        );
        const ship = shRes.rows[0];
        if (!ship) {
          return makeError(404, 'NOT_FOUND', 'Kapal tidak ditemukan.');
        }

        // Cek kepemilikan (IDOR protection, docs/08 & docs/11 T10)
        if (ship.player_id !== authUser.sub) {
          return makeError(
            403,
            'FORBIDDEN',
            'Anda tidak memiliki akses ke kapal pemain lain.',
          );
        }

        if (method === 'GET' && subPath === '') {
          const cRes = await pool.query<{
            commodity: string;
            qty: string;
          }>(
            `SELECT c.code AS commodity, sc.qty::text
             FROM public.ship_cargo sc
             JOIN public.commodities c ON c.id = sc.commodity_id
             WHERE sc.ship_id = $1 AND sc.qty > 0
             ORDER BY sc.commodity_id ASC`,
            [ship.id],
          );
          return makeJson(
            200,
            {
              id: Number(ship.id),
              name: ship.name,
              capacity: Number(ship.capacity),
              status: ship.status,
              port_id: ship.port_id !== null ? Number(ship.port_id) : null,
              dest_port:
                ship.dest_port !== null ? Number(ship.dest_port) : null,
              arrive_tick:
                ship.arrive_tick !== null ? Number(ship.arrive_tick) : null,
              eta_ticks:
                ship.arrive_tick !== null
                  ? Math.max(0, Number(ship.arrive_tick) - tickNo)
                  : 0,
              cargo: cRes.rows.map((c) => ({
                commodity: c.commodity,
                qty: Number(c.qty),
              })),
            } as unknown as T,
            tickHeaders,
          );
        }

        if (method === 'GET' && subPath === 'rules') {
          const rRes = await pool.query<{
            version: number;
            source: string;
          }>(
            `SELECT version, source
             FROM public.rule_sets
             WHERE ship_id = $1
             ORDER BY version DESC
             LIMIT 1`,
            [ship.id],
          );
          const rule = rRes.rows[0];
          return makeJson(
            200,
            {
              version: rule ? Number(rule.version) : 0,
              source: rule ? rule.source : '',
            } as unknown as T,
            tickHeaders,
          );
        }

        if (method === 'PUT' && subPath === 'rules') {
          const rlPut = rateLimiter.check(
            'putRules',
            authUser.sub,
            RATE_LIMIT_GROUPS.putRules,
          );
          if (!rlPut.allowed) {
            return makeError(
              429,
              'RATE_LIMITED',
              'Terlalu sering menyimpan aturan. Silakan tunggu sebentar.',
              [],
              { 'retry-after': String(rlPut.retryAfterSec) },
            );
          }

          const source =
            typeof bodyObj['source'] === 'string' ? bodyObj['source'] : '';
          const baseVersion =
            typeof bodyObj['base_version'] === 'number'
              ? bodyObj['base_version']
              : -1;

          if (baseVersion < 0) {
            return makeError(
              400,
              'VALIDATION_ERROR',
              'base_version wajib berupa angka non-negatif.',
            );
          }

          const val = validateDsl(source);
          if (!val.valid || !val.ast) {
            return makeError(
              422,
              'RULE_INVALID',
              'Aturan tidak lolos validasi.',
              val.errors.map((e) => ({
                line: e.line,
                column: e.column,
                code: e.code,
                message: e.message,
              })),
            );
          }

          const client = await pool.connect();
          try {
            await client.query('BEGIN');

            const curVerRes = await client.query<{ version: number }>(
              `SELECT version FROM public.rule_sets WHERE ship_id = $1 ORDER BY version DESC LIMIT 1 FOR UPDATE`,
              [ship.id],
            );
            const activeVersion = curVerRes.rows[0]
              ? Number(curVerRes.rows[0].version)
              : 0;

            if (baseVersion !== activeVersion) {
              await client.query('ROLLBACK');
              return makeError(
                409,
                'VERSION_CONFLICT',
                `Versi dasar (${baseVersion}) tidak cocok dengan versi aktif saat ini (${activeVersion}).`,
              );
            }

            const newVersion = activeVersion + 1;
            const compiledJson = JSON.stringify(val.ast, (_k, v) =>
              typeof v === 'bigint' ? v.toString() : (v as unknown),
            );

            await client.query(
              `INSERT INTO public.rule_sets (ship_id, version, source, compiled, ast_version)
               VALUES ($1, $2, $3, $4::jsonb, 1)`,
              [ship.id, newVersion, source, compiledJson],
            );

            // Simpan maksimal 20 riwayat versi terakhir (docs/08)
            await client.query(
              `DELETE FROM public.rule_sets
               WHERE ship_id = $1 AND version <= $2`,
              [ship.id, newVersion - 20],
            );

            await client.query('COMMIT');

            return makeJson(
              200,
              {
                version: newVersion,
                source,
              } as unknown as T,
              tickHeaders,
            );
          } catch (err) {
            await client.query('ROLLBACK');
            throw err;
          } finally {
            client.release();
          }
        }

        if (method === 'GET' && subPath === 'rules/versions') {
          const vRes = await pool.query<{
            version: number;
            source: string;
            created_at: Date;
          }>(
            `SELECT version, source, created_at
             FROM public.rule_sets
             WHERE ship_id = $1
             ORDER BY version DESC
             LIMIT 20`,
            [ship.id],
          );
          return makeJson(
            200,
            {
              items: vRes.rows.map((r) => ({
                version: Number(r.version),
                source: r.source,
                created_at: new Date(r.created_at).toISOString(),
              })),
            } as unknown as T,
            tickHeaders,
          );
        }

        if (method === 'POST' && subPath === 'rules/simulate') {
          const rlSim = rateLimiter.check(
            'simulate',
            authUser.sub,
            RATE_LIMIT_GROUPS.simulate,
          );
          if (!rlSim.allowed) {
            return makeError(
              429,
              'RATE_LIMITED',
              'Simulasi sandbox dibatasi maksimal 1 kali setiap 5 detik.',
              [],
              { 'retry-after': String(rlSim.retryAfterSec) },
            );
          }

          const source =
            typeof bodyObj['source'] === 'string' ? bodyObj['source'] : '';
          const reqTicks =
            typeof bodyObj['ticks'] === 'number' ? bodyObj['ticks'] : 200;

          if (reqTicks < 1 || reqTicks > 300) {
            return makeError(
              400,
              'VALIDATION_ERROR',
              'Jumlah ticks simulasi harus antara 1 dan 300.',
            );
          }

          const val = validateDsl(source);
          if (!val.valid || !val.ast) {
            return makeError(
              422,
              'RULE_INVALID',
              'Aturan tidak lolos validasi.',
              val.errors.map((e) => ({
                line: e.line,
                column: e.column,
                code: e.code,
                message: e.message,
              })),
            );
          }

          try {
            const simResult = await sandboxQueue.run(async () => {
              const snapshot = await loadWorldSnapshotFromDb(pool);
              return runSandboxSimulation(
                snapshot,
                BigInt(ship.id),
                val.ast!,
                reqTicks,
                config,
                worldSeed,
              );
            });
            return makeJson(200, simResult as unknown as T, tickHeaders);
          } catch (err) {
            const code = (err as { code?: string }).code;
            if (code === 'BUSY') {
              return makeError(
                503,
                'BUSY',
                'Antrean simulasi sandbox sedang penuh. Silakan coba lagi.',
              );
            }
            throw err;
          }
        }

        if (method === 'GET' && subPath === 'log') {
          const limit = Math.min(
            Math.max(1, Number(parsedUrl.searchParams.get('limit') ?? '50')),
            100,
          );
          const cursor = parsedUrl.searchParams.get('cursor');
          const cursorId = cursor ? BigInt(cursor) : null;

          const logRes =
            cursorId !== null
              ? await pool.query<{
                  id: string;
                  tick_no: string;
                  rule_name: string | null;
                  action: string;
                  result: string;
                  detail: string | null;
                }>(
                  `SELECT id::text, tick_no::text, rule_name, action, result, detail
                   FROM public.action_log
                   WHERE ship_id = $1 AND id < $2
                   ORDER BY tick_no DESC, id DESC
                   LIMIT $3`,
                  [ship.id, cursorId.toString(), limit + 1],
                )
              : await pool.query<{
                  id: string;
                  tick_no: string;
                  rule_name: string | null;
                  action: string;
                  result: string;
                  detail: string | null;
                }>(
                  `SELECT id::text, tick_no::text, rule_name, action, result, detail
                   FROM public.action_log
                   WHERE ship_id = $1
                   ORDER BY tick_no DESC, id DESC
                   LIMIT $2`,
                  [ship.id, limit + 1],
                );

          const hasMore = logRes.rows.length > limit;
          const slice = hasMore ? logRes.rows.slice(0, limit) : logRes.rows;
          const nextCursor = hasMore
            ? (slice[slice.length - 1]?.id ?? null)
            : null;

          return makeJson(
            200,
            {
              items: slice.map((r) => ({
                id: Number(r.id),
                tick_no: Number(r.tick_no),
                rule_name: r.rule_name,
                action: r.action,
                result: r.result,
                detail: r.detail,
              })),
              next_cursor: nextCursor,
            } as unknown as T,
            tickHeaders,
          );
        }
      }

      return makeError(404, 'NOT_FOUND', `Endpoint ${method} ${path} tidak ditemukan.`);
    } catch (err) {
      console.error('[API-ERROR]', err);
      return makeError(500, 'INTERNAL', 'Terjadi kesalahan internal pada server.');
    }
  }

  return {
    rateLimiter,
    inject: handleRequest,
    async listen(port: number, host: string = '0.0.0.0'): Promise<http.Server> {
      const server = http.createServer(async (req, res) => {
        const chunks: Buffer[] = [];
        let totalBytes = 0;
        let overflowed = false;

        for await (const chunk of req) {
          const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
          totalBytes += buf.length;
          if (totalBytes > maxBodyBytes) {
            overflowed = true;
            break;
          }
          chunks.push(buf);
        }

        if (overflowed) {
          const errResp = makeError(
            400,
            'VALIDATION_ERROR',
            `Ukuran body melebihi batas maksimal ${maxBodyBytes} byte.`,
          );
          res.writeHead(errResp.statusCode, errResp.headers);
          res.end(errResp.rawBody);
          return;
        }

        const rawBody = Buffer.concat(chunks).toString('utf8');
        const reqHeaders: Record<string, string | undefined> = {};
        for (const [k, v] of Object.entries(req.headers)) {
          reqHeaders[k] = Array.isArray(v) ? v.join(', ') : v;
        }

        const out = await handleRequest({
          method: req.method ?? 'GET',
          url: req.url ?? '/',
          headers: reqHeaders,
          body: rawBody.length > 0 ? rawBody : undefined,
          remoteAddress: req.socket.remoteAddress ?? '127.0.0.1',
        });

        res.writeHead(out.statusCode, out.headers);
        res.end(out.rawBody);
      });

      await new Promise<void>((resolve) => {
        server.listen(port, host, () => resolve());
      });
      httpServer = server;
      return server;
    },
    async close(): Promise<void> {
      if (httpServer) {
        const s = httpServer;
        httpServer = null;
        await new Promise<void>((resolve, reject) => {
          s.close((err) => (err ? reject(err) : resolve()));
        });
      }
    },
  };
}
