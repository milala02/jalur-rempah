import pg from 'pg';
import {
  WORLD_CONFIG,
  WorldEconomyConfig,
  COMMODITIES_SEED,
  PORTS_SEED,
  ShipStatus,
} from '@jalur-rempah/shared';
import {
  WorldState,
  WorldPlayerState,
  WorldPortState,
  WorldShipState,
  ShipRuleDecider,
  TickActionEvent,
  stepWorld,
  hitungHarga,
  createSeededRng,
  computeCanonicalStateHash,
} from '@jalur-rempah/econ';
import {
  CompiledDslProgram,
  createDslShipRuleDecider,
} from '@jalur-rempah/dsl';

export const DEFAULT_WORKER_ADVISORY_LOCK_KEY = 91508421;

export interface WorkerMetrics {
  tick_duration_ms: number;
  tick_lag_ms: number;
  ticks_completed_total: number;
  rules_skipped_total: Record<string, number>;
  actions_total: Record<string, number>;
  ships_grounded: number;
  invariant_failures_total: number;
  rescue_granted_total: number;
}

export function createInitialWorkerMetrics(): WorkerMetrics {
  return {
    tick_duration_ms: 0,
    tick_lag_ms: 0,
    ticks_completed_total: 0,
    rules_skipped_total: {},
    actions_total: {},
    ships_grounded: 0,
    invariant_failures_total: 0,
    rescue_granted_total: 0,
  };
}

export interface AdvisoryLockHandle {
  readonly client: pg.PoolClient;
  readonly lockKey: number;
  verifyAlive(): Promise<boolean>;
  release(): Promise<void>;
}

/**
 * Membuka satu koneksi khusus dari pool yang memegang pg_try_advisory_lock(lockKey)
 * selama hidup worker (docs/09 v0.2). Jika kunci sudah dipegang proses lain, mengembalikan null.
 */
export async function acquireWorkerAdvisoryLock(
  pool: pg.Pool,
  lockKey: number = DEFAULT_WORKER_ADVISORY_LOCK_KEY,
): Promise<AdvisoryLockHandle | null> {
  const client = await pool.connect();
  try {
    const res = await client.query<{ locked: boolean }>(
      `SELECT pg_try_advisory_lock($1) AS locked`,
      [lockKey],
    );
    if (!res.rows[0]?.locked) {
      client.release();
      return null;
    }

    let released = false;
    return {
      client,
      lockKey,
      async verifyAlive(): Promise<boolean> {
        if (released) return false;
        try {
          const check = await client.query<{ ok: number }>('SELECT 1 AS ok');
          return check.rows[0]?.ok === 1;
        } catch {
          return false;
        }
      },
      async release(): Promise<void> {
        if (released) return;
        released = true;
        try {
          await client.query(`SELECT pg_advisory_unlock($1)`, [lockKey]);
        } catch {
          // ignore unlock error on broken connection
        } finally {
          client.release();
        }
      },
    };
  } catch (err) {
    client.release();
    throw err;
  }
}

const PORT_CODE_BY_ID = new Map(PORTS_SEED.map((p) => [p.id, p.code]));
const PORT_NAME_BY_ID = new Map(PORTS_SEED.map((p) => [p.id, p.name]));
const COM_CODE_BY_ID = new Map(COMMODITIES_SEED.map((c) => [c.id, c.code]));
const COM_BASE_PRICE_BY_ID = new Map(
  COMMODITIES_SEED.map((c) => [c.id, c.base_price]),
);

/**
 * Menghitung Level Pemain (Fase 5 — Progressive Unlocking) berdasarkan Net Worth:
 * - Level 1: < 5.000 koin
 * - Level 2: 5.000 - 20.000
 * - Level 3: 20.001 - 50.000
 * - Level 4: 50.001 - 150.000
 * - Level 5: 150.001 - 500.000
 * - Level 6: 500.001 - 1.000.000
 * - Level 7: > 1.000.000
 */
export function calculatePlayerLevel(netWorth: number | bigint): number {
  const nw = Number(netWorth);
  if (nw < 5000) return 1;
  if (nw <= 20000) return 2;
  if (nw <= 50000) return 3;
  if (nw <= 150000) return 4;
  if (nw <= 500000) return 5;
  if (nw <= 1000000) return 6;
  return 7;
}

export interface PirateNpcSpec {
  readonly name: string;
  readonly attackPower: number;
  readonly defensePower: number;
  readonly bountyCoins: number;
}

export const PIRATE_NPCS_SEED: readonly PirateNpcSpec[] = [
  {
    name: 'Bajak Laut Selat Malaka',
    attackPower: 35,
    defensePower: 80,
    bountyCoins: 200,
  },
  {
    name: 'Perompak Laut Banda',
    attackPower: 30,
    defensePower: 70,
    bountyCoins: 160,
  },
  {
    name: 'Lanun Laut Sulawesi',
    attackPower: 40,
    defensePower: 90,
    bountyCoins: 250,
  },
] as const;

/**
 * Mengundi ancaman pencegatan NPC Bajak Laut pada tick ini (default peluang 2% per tick).
 */
export function spawnPirateThreat(
  tickNo: number,
  worldSeed: number = 101,
  chancePerTick: number = 0.02,
): PirateNpcSpec | null {
  if (tickNo <= 0 || chancePerTick <= 0) {
    return null;
  }
  const rng = createSeededRng(`${worldSeed}:pirate_threat:${tickNo}`);
  const roll = rng.nextFloat();
  if (roll >= chancePerTick) {
    return null;
  }
  const idx = rng.nextInt(0, PIRATE_NPCS_SEED.length - 1);
  return PIRATE_NPCS_SEED[idx] ?? PIRATE_NPCS_SEED[0]!;
}

export interface NavalCombatInput {
  readonly shipId: number | bigint;
  readonly playerId: number | bigint;
  readonly shipName?: string;
  readonly shipAttackPower: number;
  readonly shipDefensePower: number;
  readonly pirate?: PirateNpcSpec;
  readonly cargo?: ReadonlyMap<number, bigint>;
}

export interface NavalCombatResult {
  readonly shipId: number;
  readonly defenderId: number;
  readonly pirateName: string;
  readonly isPirate: true;
  readonly outcome: 'player_victory' | 'pirate_victory';
  readonly damage: number;
  readonly shipAttackPower: number;
  readonly shipDefenseBefore: number;
  readonly shipDefenseAfter: number;
  readonly lootedCommodityId: number | null;
  readonly lootedCommodityCode: string | null;
  readonly lootedQty: bigint;
  readonly bountyCoins: bigint;
  readonly detail: string;
}

/**
 * Menghitung hasil pertempuran laut secara Server-Authoritative:
 * attack_power (Meriam/Katana kapal) vs defense_power (HP Lambung Kapal) melawan NPC Bajak Laut.
 */
export function resolveNavalCombat(input: NavalCombatInput): NavalCombatResult {
  const pirate = input.pirate ?? PIRATE_NPCS_SEED[0]!;
  const shipAtk = Math.max(0, Math.trunc(input.shipAttackPower));
  const shipDefBefore = Math.max(1, Math.trunc(input.shipDefensePower));

  const playerCombatScore = shipAtk * 2 + shipDefBefore;
  const pirateCombatScore =
    pirate.attackPower * 2 + Math.floor(pirate.defensePower * 0.5);

  const playerWins = playerCombatScore >= pirateCombatScore;
  const mitigation = Math.floor(shipAtk * 0.35);
  const rawDamage = Math.max(6, pirate.attackPower - mitigation);
  const damage = playerWins
    ? Math.max(5, Math.floor(rawDamage * 0.5))
    : Math.max(10, rawDamage);

  const shipDefAfter = Math.max(5, shipDefBefore - damage);

  let lootedComId: number | null = null;
  let lootedComCode: string | null = null;
  let lootedQty = 0n;
  let bountyCoins = 0n;

  if (playerWins) {
    bountyCoins = BigInt(pirate.bountyCoins);
  } else if (input.cargo) {
    for (const [cid, qty] of input.cargo.entries()) {
      if (qty > 0n) {
        lootedComId = cid;
        lootedComCode = COM_CODE_BY_ID.get(cid) ?? `komoditas_${cid}`;
        const calcLoot = (qty * 40n) / 100n;
        lootedQty = calcLoot >= 1n ? calcLoot : 1n;
        break;
      }
    }
  }

  const shipLabel = input.shipName ?? `Kapal #${String(input.shipId)}`;
  const detail = playerWins
    ? `${shipLabel} (ATK ${shipAtk}, HP ${shipDefBefore}->${shipDefAfter}) berhasil memukul mundur ${pirate.name} (kerusakan -${damage} HP) dan meraih hadiah ${bountyCoins.toString()} koin!`
    : lootedQty > 0n
      ? `${pirate.name} menyergap ${shipLabel}! Lambung rusak -${damage} HP (${shipDefBefore}->${shipDefAfter}) dan ${lootedQty.toString()} unit ${lootedComCode} dirampas.`
      : `${pirate.name} menyerang ${shipLabel}! Lambung kapal mengalami kerusakan -${damage} HP (${shipDefBefore}->${shipDefAfter}).`;

  return {
    shipId: Number(input.shipId),
    defenderId: Number(input.playerId),
    pirateName: pirate.name,
    isPirate: true,
    outcome: playerWins ? 'player_victory' : 'pirate_victory',
    damage,
    shipAttackPower: shipAtk,
    shipDefenseBefore: shipDefBefore,
    shipDefenseAfter: shipDefAfter,
    lootedCommodityId: lootedComId,
    lootedCommodityCode: lootedComCode,
    lootedQty,
    bountyCoins,
    detail,
  };
}

export type WorldEventKind =
  | 'WABAH_HAMA'
  | 'EMBARGO_PERANG'
  | 'ANGIN_MUSON_KENCANG';

export interface WorldEventTriggerInput {
  readonly kind: WorldEventKind;
  readonly portId?: number;
  readonly commodityId?: number;
  readonly durationTicks?: number;
}

export interface TriggeredWorldEventRecord {
  readonly eventCode: string;
  readonly title: string;
  readonly description: string;
  readonly portId: number | null;
  readonly commodityId: number | null;
  readonly activeUntilTick: number | null;
  readonly isActive: boolean;
  readonly effectMeta: Record<string, unknown>;
}

/**
 * Mengundi apakah event acak dunia ("Wabah Hama", "Embargo/Perang", atau "Angin Muson Kencang")
 * terpicu pada tick ini berdasarkan peluang tertentu (default 5% per 100 tick).
 */
export function rollRandomWorldEventForTick(
  tickNo: number,
  worldSeed: number,
  chancePer100Ticks: number = 0.05,
): WorldEventTriggerInput | null {
  if (tickNo <= 0 || tickNo % 100 !== 0) {
    return null;
  }
  const rng = createSeededRng(`${worldSeed}:world_event:${tickNo}`);
  const roll = rng.nextFloat();
  if (roll >= chancePer100Ticks) {
    return null;
  }
  const kinds: readonly WorldEventKind[] = [
    'WABAH_HAMA',
    'EMBARGO_PERANG',
    'ANGIN_MUSON_KENCANG',
  ];
  const kindIdx = rng.nextInt(0, kinds.length - 1);
  const kind = kinds[kindIdx] ?? 'WABAH_HAMA';
  const portId = rng.nextInt(1, 6);
  const commodityId = rng.nextInt(1, 4);
  return {
    kind,
    portId,
    commodityId,
    durationTicks: 25,
  };
}

export interface SeasonDescriptor {
  readonly seasonId: 1 | 2 | 3;
  readonly seasonCode: 'muson_barat' | 'muson_timur' | 'pancaroba';
  readonly eventCode: string;
  readonly title: string;
  readonly description: string;
}

export function getSeasonForTick(tickNo: number): SeasonDescriptor {
  const idx = Math.floor(Math.max(0, tickNo) / 24) % 3;
  if (idx === 0) {
    return {
      seasonId: 1,
      seasonCode: 'muson_barat',
      eventCode: 'MUSON_BARAT',
      title: 'Angin Muson Barat',
      description:
        'Angin bertiup dari barat ke timur Nusantara; pelayaran dari Malaka dan Batavia menuju Maluku lebih ramai.',
    };
  }
  if (idx === 1) {
    return {
      seasonId: 2,
      seasonCode: 'muson_timur',
      eventCode: 'MUSON_TIMUR',
      title: 'Angin Muson Timur',
      description:
        'Angin bertiup dari timur ke barat Nusantara; armada rempah dari Banda dan Ternate berlayar cepat menuju Jawa dan Malaka.',
    };
  }
  return {
    seasonId: 3,
    seasonCode: 'pancaroba',
    eventCode: 'PANCAROBA',
    title: 'Musim Pancaroba',
    description:
      'Peralihan angin muson di perairan Nusantara; pasar pelabuhan menyesuaikan cadangan komoditas.',
  };
}

function reviveBigIntsInAst(obj: unknown): unknown {
  if (Array.isArray(obj)) {
    return obj.map((item) => reviveBigIntsInAst(item));
  }
  if (obj !== null && typeof obj === 'object') {
    const rec = obj as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(rec)) {
      if (
        k === 'value' &&
        rec['kind'] === 'number_literal' &&
        (typeof v === 'string' || typeof v === 'number')
      ) {
        out[k] = BigInt(v);
      } else {
        out[k] = reviveBigIntsInAst(v);
      }
    }
    return out;
  }
  return obj;
}

function formatActionEventSummary(ev: TickActionEvent): {
  actionText: string;
  detailText: string;
} {
  const comCode =
    ev.commodityId !== undefined
      ? (COM_CODE_BY_ID.get(ev.commodityId) ?? String(ev.commodityId))
      : '';
  const destCode =
    ev.destPortId !== undefined
      ? (PORT_CODE_BY_ID.get(ev.destPortId) ?? String(ev.destPortId))
      : '';

  let actionText: string = ev.actionType;
  if (ev.actionType === 'buy') {
    actionText = `beli(${comCode},${(ev.executedQty ?? 0n).toString()})`;
  } else if (ev.actionType === 'sell') {
    actionText = `jual(${comCode},${(ev.executedQty ?? 0n).toString()})`;
  } else if (ev.actionType === 'sail') {
    actionText = `berlayar(${destCode})`;
  } else if (ev.actionType === 'wait') {
    actionText = 'tunggu()';
  } else if (ev.actionType === 'skip') {
    actionText = `lewati(${ev.failureCode ?? 'SKIP'})`;
  }

  const detailText =
    ev.detail ??
    (ev.failureCode
      ? `[${ev.ruleName}] ${actionText} -> ${ev.result} (${ev.failureCode})`
      : `[${ev.ruleName}] ${actionText} -> ${ev.result}`);

  return { actionText, detailText };
}

export interface ExecuteTickOptions {
  readonly config?: WorldEconomyConfig;
  readonly worldSeed?: number;
  readonly customRuleDecider?: ShipRuleDecider;
  readonly flushUpkeepImmediately?: boolean;
  readonly metrics?: WorkerMetrics;
  readonly triggerWorldEvent?: WorldEventTriggerInput;
  readonly worldEventChancePer100Ticks?: number;
  readonly triggerPirateEncounter?: {
    readonly shipId?: number | bigint;
    readonly pirate?: PirateNpcSpec;
  };
  readonly pirateChancePerTick?: number;
  readonly beforeCommitHook?: (
    tickNo: number,
    txClient: pg.PoolClient,
  ) => Promise<void> | void;
}

export interface ExecuteTickResult {
  readonly tickNo: number;
  readonly stateHash: string;
  readonly durationMs: number;
  readonly state: WorldState;
  readonly triggeredEvent?: TriggeredWorldEventRecord | null;
  readonly combatResults?: readonly NavalCombatResult[];
}

/**
 * Menjalankan tepat satu tick dunia di dalam satu transaksi READ COMMITTED menggunakan
 * fungsi murni stepWorld dari @jalur-rempah/econ (docs/09 v0.2) + World Events Engine (Fase 3).
 */
export async function executeSingleWorldTick(
  pool: pg.Pool,
  options?: ExecuteTickOptions,
): Promise<ExecuteTickResult> {
  const config = options?.config ?? WORLD_CONFIG;
  const worldSeed = options?.worldSeed ?? 101;
  const flushImmediately = options?.flushUpkeepImmediately ?? false;
  const metrics = options?.metrics;

  const startedAt = new Date();
  const startMs = Date.now();
  const client = await pool.connect();

  try {
    await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');

    // Langkah 1: Muat keadaan dunia & nomor tick terakhir
    const tickRes = await client.query<{ max_tick: string }>(
      `SELECT COALESCE(MAX(tick_no), 0)::text AS max_tick FROM public.tick_state`,
    );
    const prevTickNo = Number(tickRes.rows[0]?.max_tick ?? '0');

    const portsRes = await client.query<{
      id: number;
      code: string;
      name: string;
      treasury: string;
      initial_treasury: string;
    }>(
      `SELECT id, code, name, treasury::text, initial_treasury::text
       FROM public.ports
       WHERE id <= 6
       ORDER BY id ASC
       FOR UPDATE`,
    );
    const ports = new Map<number, WorldPortState>();
    for (const r of portsRes.rows) {
      ports.set(Number(r.id), {
        id: Number(r.id),
        code: r.code,
        name: r.name,
        treasury: BigInt(r.treasury),
        initialTreasury: BigInt(r.initial_treasury),
      });
    }

    const marketRes = await client.query<{
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
       FROM public.market
       ORDER BY port_id ASC, commodity_id ASC
       FOR UPDATE`,
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

    const playersRes = await client.query<{
      id: string;
      coins: string;
      unflushed_upkeep: string;
      cumulative_upkeep_paid: string;
      account_status: string;
    }>(
      `SELECT id::text, coins::text, unflushed_upkeep::text, cumulative_upkeep_paid::text, account_status
       FROM public.players
       ORDER BY id ASC
       FOR UPDATE`,
    );

    const starterByPlayerRes = await client.query<{
      player_id: string;
      starter_sum: string;
    }>(
      `SELECT player_id::text, COALESCE(SUM(delta), 0)::text AS starter_sum
       FROM public.ledger
       WHERE reason = 'starter'
       GROUP BY player_id`,
    );
    const starterMap = new Map<bigint, bigint>();
    for (const r of starterByPlayerRes.rows) {
      starterMap.set(BigInt(r.player_id), BigInt(r.starter_sum));
    }

    const ledgerSumRes = await client.query<{
      player_id: string;
      total_delta: string;
    }>(
      `SELECT player_id::text, COALESCE(SUM(delta), 0)::text AS total_delta
       FROM public.ledger
       GROUP BY player_id`,
    );
    const ledgerSumMap = new Map<bigint, bigint>();
    for (const r of ledgerSumRes.rows) {
      ledgerSumMap.set(BigInt(r.player_id), BigInt(r.total_delta));
    }

    const rescueStatsRes = await client.query<{
      player_id: string;
      last_tick: string | null;
      cnt: string;
    }>(
      `SELECT player_id::text, MAX(tick_no)::text AS last_tick, COUNT(*)::text AS cnt
       FROM public.ledger
       WHERE reason = 'rescue'
       GROUP BY player_id`,
    );
    const rescueStatsMap = new Map<
      bigint,
      { lastTick: number | null; count: number }
    >();
    for (const r of rescueStatsRes.rows) {
      rescueStatsMap.set(BigInt(r.player_id), {
        lastTick: r.last_tick !== null ? Number(r.last_tick) : null,
        count: Number(r.cnt),
      });
    }

    const players = new Map<bigint, WorldPlayerState>();
    const coinsBeforeByPlayer = new Map<bigint, bigint>();
    const unflushedBeforeByPlayer = new Map<bigint, bigint>();
    const cumUpkeepBeforeByPlayer = new Map<bigint, bigint>();
    const statusByPlayer = new Map<bigint, string>();

    for (const pl of playersRes.rows) {
      const pid = BigInt(pl.id);
      const coins = BigInt(pl.coins);
      const unflushed = BigInt(pl.unflushed_upkeep);
      const cumUpkeep = BigInt(pl.cumulative_upkeep_paid);
      const initialCoins = starterMap.get(pid) ?? config.STARTER_COINS;
      const rawLedgerSum = ledgerSumMap.get(pid) ?? coins + unflushed;
      const effectiveLedgerSum = rawLedgerSum - unflushed;
      const rStat = rescueStatsMap.get(pid);

      coinsBeforeByPlayer.set(pid, coins);
      unflushedBeforeByPlayer.set(pid, unflushed);
      cumUpkeepBeforeByPlayer.set(pid, cumUpkeep);
      statusByPlayer.set(pid, pl.account_status ?? 'active');

      players.set(pid, {
        id: pid,
        coins,
        initialCoins,
        ledgerSum: effectiveLedgerSum,
        lastRescueTick: rStat?.lastTick ?? null,
        rescueCount: rStat?.count ?? 0,
      });
    }

    const shipsRes = await client.query<{
      id: string;
      player_id: string;
      name: string;
      capacity: number;
      status: ShipStatus;
      port_id: number | null;
      dest_port: number | null;
      arrive_tick: string | null;
      attack_power: number;
      defense_power: number;
    }>(
      `SELECT id::text, player_id::text, name, capacity, status, port_id, dest_port, arrive_tick::text, attack_power, defense_power
       FROM public.ships
       ORDER BY id ASC
       FOR UPDATE`,
    );
    const shipCombatStats = new Map<
      bigint,
      { name: string; attackPower: number; defensePower: number }
    >();
    for (const sr of shipsRes.rows) {
      shipCombatStats.set(BigInt(sr.id), {
        name: sr.name,
        attackPower: Number(sr.attack_power ?? 0),
        defensePower: Number(sr.defense_power ?? 100),
      });
    }

    const cargoRes = await client.query<{
      ship_id: string;
      commodity_id: number;
      qty: string;
    }>(
      `SELECT ship_id::text, commodity_id, qty::text
       FROM public.ship_cargo
       FOR UPDATE`,
    );
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

    const ships = new Map<bigint, WorldShipState>();
    const shipsSnapshotBefore = new Map<
      bigint,
      {
        status: ShipStatus;
        portId: number;
        destPort: number | null;
        arriveTick: number | null;
      }
    >();
    const shipMemories = new Map<bigint, Map<number, bigint>>();
    for (const sh of shipsRes.rows) {
      const sid = BigInt(sh.id);
      shipMemories.set(sid, new Map<number, bigint>());
      const cmap =
        cargoByShip.get(sid) ??
        new Map<number, bigint>([
          [1, 0n],
          [2, 0n],
          [3, 0n],
          [4, 0n],
        ]);
      const pId = Number(sh.port_id ?? 1);
      const dPort = sh.dest_port !== null ? Number(sh.dest_port) : null;
      const aTick = sh.arrive_tick !== null ? Number(sh.arrive_tick) : null;
      shipsSnapshotBefore.set(sid, {
        status: sh.status,
        portId: pId,
        destPort: dPort,
        arriveTick: aTick,
      });
      ships.set(sid, {
        id: sid,
        playerId: BigInt(sh.player_id),
        capacity: Number(sh.capacity),
        status: sh.status,
        portId: pId,
        destPort: dPort,
        arriveTick: aTick,
        cargo: cmap,
      });
    }

    // Muat memori kapal antar-tick (Phase 2: ship_memory) dan intelijen pelabuhan (Phase 2: port_intel)
    const memRes = await client.query<{
      ship_id: string;
      slot: number;
      val: string;
    }>(`SELECT ship_id::text, slot, val::text FROM public.ship_memory FOR UPDATE`);
    for (const mr of memRes.rows) {
      const sid = BigInt(mr.ship_id);
      let m = shipMemories.get(sid);
      if (!m) {
        m = new Map<number, bigint>();
        shipMemories.set(sid, m);
      }
      m.set(Number(mr.slot), BigInt(mr.val));
    }

    const intelRes = await client.query<{
      player_id: string;
      port_id: number;
      commodity_id: number;
      price: string;
      stock: string;
      tick_seen: string;
    }>(
      `SELECT player_id::text, port_id, commodity_id, price::text, stock::text, tick_seen::text
       FROM public.port_intel`,
    );
    const playerIntelByPlayerId = new Map<
      bigint,
      Map<string, { price: bigint; stock: bigint; tickSeen: number }>
    >();
    for (const ir of intelRes.rows) {
      const pid = BigInt(ir.player_id);
      let pmap = playerIntelByPlayerId.get(pid);
      if (!pmap) {
        pmap = new Map();
        playerIntelByPlayerId.set(pid, pmap);
      }
      pmap.set(`${ir.port_id}:${ir.commodity_id}`, {
        price: BigInt(ir.price),
        stock: BigInt(ir.stock),
        tickSeen: Number(ir.tick_seen),
      });
    }

    // Muat kumulatif sink & source saat ini dari view economy_money_supply_audit
    const auditBeforeRes = await client.query<{
      cumulative_upkeep_sink: string;
      cumulative_source: string;
    }>(
      `SELECT cumulative_upkeep_sink::text, cumulative_source::text FROM public.economy_money_supply_audit`,
    );
    const cumulativeUpkeepSinkBefore = BigInt(
      auditBeforeRes.rows[0]?.cumulative_upkeep_sink ?? '0',
    );
    const cumulativeSourceBefore = BigInt(
      auditBeforeRes.rows[0]?.cumulative_source ?? '0',
    );

    // Muat versi aturan aktif tertinggi per kapal bila customRuleDecider tidak disediakan
    // Kapal milik pemain berstatus 'banned' tidak mengeksekusi aturan (Anti-Cheat Pilar 5)
    let decider: ShipRuleDecider;
    if (options?.customRuleDecider) {
      decider = options.customRuleDecider;
    } else {
      const rulesRes = await client.query<{
        ship_id: string;
        compiled: unknown;
      }>(
        `SELECT DISTINCT ON (ship_id) ship_id::text, compiled
         FROM public.rule_sets
         ORDER BY ship_id ASC, version DESC`,
      );
      const programsByShip = new Map<bigint, CompiledDslProgram>();
      for (const r of rulesRes.rows) {
        const sid = BigInt(r.ship_id);
        const shipObj = ships.get(sid);
        const ownerStatus = shipObj
          ? (statusByPlayer.get(shipObj.playerId) ?? 'active')
          : 'active';
        if (ownerStatus === 'banned') {
          continue;
        }
        const revived = reviveBigIntsInAst(r.compiled) as CompiledDslProgram;
        if (revived && Array.isArray(revived.rules)) {
          programsByShip.set(sid, revived);
        }
      }
      decider = createDslShipRuleDecider(programsByShip, undefined, {
        shipMemories,
        playerIntelByPlayerId,
      });
    }

    const worldState: WorldState = {
      tickNo: prevTickNo,
      players,
      ports,
      markets,
      ships,
      cumulativeUpkeepSink: cumulativeUpkeepSinkBefore,
      cumulativeSource: cumulativeSourceBefore,
      stateHash: '',
    };

    // Langkah 2-8: Jalankan fungsi murni stepWorld (satu-satunya implementasi tick!)
    const { state: nextState, events } = stepWorld(
      worldState,
      decider,
      config,
      worldSeed,
      true,
    );
    const t = nextState.tickNo;

    // Langkah 8: Periksa invarian cepat; jika gagal -> ROLLBACK & hentikan worker!
    if (!events.invariantCheck.valid) {
      await client.query('ROLLBACK');
      if (metrics) {
        metrics.invariant_failures_total += 1;
      }
      throw new Error(
        `Invarian ekonomi gagal pada tick ${t}: ${events.invariantCheck.violations.join('; ')}`,
      );
    }

    // Langkah 8b (Fase 3): World Events Engine ("Wabah Hama", "Embargo/Perang", "Angin Muson Kencang")
    // 1. Nonaktifkan event lama yang sudah melewati batas active_until_tick
    await client.query(
      `UPDATE public.world_events
       SET is_active = false
       WHERE is_active = true
         AND active_until_tick IS NOT NULL
         AND active_until_tick < $1`,
      [t],
    );

    // 2. Cek apakah ada pelabuhan yang sedang berada dalam status Embargo/Perang aktif
    const activeEmbargoRes = await client.query<{ port_id: number }>(
      `SELECT DISTINCT port_id
       FROM public.world_events
       WHERE is_active = true
         AND event_code = 'EMBARGO_PERANG'
         AND port_id IS NOT NULL
         AND (active_until_tick IS NULL OR active_until_tick >= $1)`,
      [t],
    );
    const activeEmbargoPortIds = new Set<number>(
      activeEmbargoRes.rows.map((r) => Number(r.port_id)),
    );

    // 3. Periksa pemicu event dunia baru (opsi eksplisit atau peluang 5% per 100 tick)
    const triggeredInput =
      options?.triggerWorldEvent ??
      rollRandomWorldEventForTick(
        t,
        worldSeed,
        options?.worldEventChancePer100Ticks ?? 0.05,
      );

    let triggeredEventRecord: TriggeredWorldEventRecord | null = null;
    let stateMutatedByWorldEvent = false;

    if (triggeredInput) {
      const durationTicks = Math.max(1, triggeredInput.durationTicks ?? 25);
      const activeUntilTick = t + durationTicks;

      if (triggeredInput.kind === 'WABAH_HAMA') {
        const targetPortId = triggeredInput.portId ?? 1;
        const targetComId = triggeredInput.commodityId ?? 1;
        const m = nextState.markets.get(`${targetPortId}:${targetComId}`);
        const basePrice = COM_BASE_PRICE_BY_ID.get(targetComId) ?? 40n;
        const portName = PORT_NAME_BY_ID.get(targetPortId) ?? 'Banda';
        const comCode = COM_CODE_BY_ID.get(targetComId) ?? 'pala';

        let stockBefore = 0n;
        let stockAfter = 0n;
        let priceBefore = 0n;
        let priceAfter = 0n;

        if (m) {
          stockBefore = m.stock;
          priceBefore = m.price;
          // Stok berkurang drastis (-50%, minimal 1) sehingga harga naik otomatis melalui hitungHarga
          const halved = m.stock / 2n;
          stockAfter = halved >= 1n ? halved : 1n;
          priceAfter = hitungHarga(stockAfter, m.target, basePrice, config);
          if (priceAfter <= priceBefore && stockAfter < stockBefore) {
            priceAfter = priceBefore + 1n;
          }
          m.stock = stockAfter;
          m.price = priceAfter;
          stateMutatedByWorldEvent = true;
        }

        triggeredEventRecord = {
          eventCode: 'WABAH_HAMA',
          title: 'Wabah Hama',
          description: `Wabah hama menyerang perkebunan ${comCode} di ${portName}! Stok merosot dari ${stockBefore.toString()} menjadi ${stockAfter.toString()} dan harga melonjak dari ${priceBefore.toString()} ke ${priceAfter.toString()} koin.`,
          portId: targetPortId,
          commodityId: targetComId,
          activeUntilTick,
          isActive: true,
          effectMeta: {
            kind: 'WABAH_HAMA',
            port_id: targetPortId,
            commodity_id: targetComId,
            stock_before: Number(stockBefore),
            stock_after: Number(stockAfter),
            price_before: Number(priceBefore),
            price_after: Number(priceAfter),
          },
        };
      } else if (triggeredInput.kind === 'EMBARGO_PERANG') {
        const targetPortId = triggeredInput.portId ?? 3;
        const portName = PORT_NAME_BY_ID.get(targetPortId) ?? 'Batavia';
        activeEmbargoPortIds.add(targetPortId);

        triggeredEventRecord = {
          eventCode: 'EMBARGO_PERANG',
          title: 'Embargo/Perang',
          description: `Blokade & embargo laut diberlakukan di pelabuhan ${portName}! Seluruh rute pelayaran keluar dan masuk ${portName} ditutup sementara hingga tick ${activeUntilTick}.`,
          portId: targetPortId,
          commodityId: null,
          activeUntilTick,
          isActive: true,
          effectMeta: {
            kind: 'EMBARGO_PERANG',
            port_id: targetPortId,
            closed_routes: true,
            active_until_tick: activeUntilTick,
          },
        };
      } else if (triggeredInput.kind === 'ANGIN_MUSON_KENCANG') {
        let affectedShips = 0;
        for (const sh of nextState.ships.values()) {
          if (
            sh.status === 'sailing' &&
            sh.arriveTick !== null &&
            sh.arriveTick > t
          ) {
            const eta = sh.arriveTick - t;
            const newEta = Math.max(1, Math.floor(eta * 0.5));
            sh.arriveTick = t + newEta;
            affectedShips += 1;
            stateMutatedByWorldEvent = true;
          }
        }

        triggeredEventRecord = {
          eventCode: 'ANGIN_MUSON_KENCANG',
          title: 'Angin Muson Kencang',
          description: `Angin Muson Kencang berhembus di jalur pelayaran Nusantara! Waktu tempuh kapal (ETA) berkurang 50% untuk ${affectedShips} kapal yang sedang berlayar.`,
          portId: null,
          commodityId: null,
          activeUntilTick,
          isActive: true,
          effectMeta: {
            kind: 'ANGIN_MUSON_KENCANG',
            eta_multiplier: 0.5,
            affected_ships: affectedShips,
          },
        };
      }
    }

    // 4. Terapkan penutupan rute untuk semua pelabuhan yang sedang terkena Embargo/Perang aktif:
    //    Kapal tidak dapat keluar dari pelabuhan embargo maupun masuk/berlayar menuju pelabuhan embargo.
    if (activeEmbargoPortIds.size > 0) {
      for (const sh of nextState.ships.values()) {
        const prevSh = shipsSnapshotBefore.get(sh.id);
        if (!prevSh) continue;

        const leavingEmbargoPort =
          activeEmbargoPortIds.has(prevSh.portId) && sh.status === 'sailing';
        const enteringEmbargoPort =
          sh.status === 'sailing' &&
          sh.destPort !== null &&
          activeEmbargoPortIds.has(sh.destPort);
        const arrivedAtEmbargoPort =
          prevSh.status === 'sailing' &&
          prevSh.destPort !== null &&
          activeEmbargoPortIds.has(prevSh.destPort) &&
          sh.status === 'docked' &&
          activeEmbargoPortIds.has(sh.portId);

        if (leavingEmbargoPort || enteringEmbargoPort || arrivedAtEmbargoPort) {
          sh.status = 'docked';
          sh.portId = prevSh.portId;
          sh.destPort = null;
          sh.arriveTick = null;
          stateMutatedByWorldEvent = true;

          const sList = eventsByShipFromStep(events.actionEvents, sh.id);
          sList.push({
            shipId: sh.id,
            playerId: sh.playerId,
            tickNo: t,
            portId: sh.portId,
            ruleName: 'embargo_laut',
            actionType: 'skip',
            result: 'dilewati',
            failureCode: 'EMBARGO_PORT_CLOSED',
            detail: `[embargo_laut] Rute pelayaran ke/dari pelabuhan ditutup sementara akibat Embargo/Perang`,
          });
        }
      }
    }

    // Langkah 8c (Fase 6): Engine Bajak Laut & Pertempuran Laut (Server-Authoritative)
    const combatResultsThisTick: NavalCombatResult[] = [];
    const pirateBountyByPlayer = new Map<bigint, { coins: bigint; shipId: bigint; pirateName: string }>();

    const explicitPirate = options?.triggerPirateEncounter;
    const autoPirate =
      !explicitPirate && t > 20
        ? spawnPirateThreat(t, worldSeed, options?.pirateChancePerTick ?? 0.02)
        : null;

    if (explicitPirate || autoPirate) {
      const pirateSpec =
        explicitPirate?.pirate ?? autoPirate ?? PIRATE_NPCS_SEED[0]!;
      let targetShip: WorldShipState | undefined;

      if (explicitPirate?.shipId !== undefined) {
        targetShip = nextState.ships.get(BigInt(explicitPirate.shipId));
      } else {
        const sailingShips = Array.from(nextState.ships.values()).filter(
          (s) => s.status === 'sailing',
        );
        targetShip =
          sailingShips[0] ?? Array.from(nextState.ships.values())[0];
      }

      if (targetShip) {
        const st = shipCombatStats.get(targetShip.id) ?? {
          name: `Kapal #${targetShip.id.toString()}`,
          attackPower: 0,
          defensePower: 100,
        };
        const combatOut = resolveNavalCombat({
          shipId: targetShip.id,
          playerId: targetShip.playerId,
          shipName: st.name,
          shipAttackPower: st.attackPower,
          shipDefensePower: st.defensePower,
          pirate: pirateSpec,
          cargo: targetShip.cargo,
        });

        st.defensePower = combatOut.shipDefenseAfter;
        shipCombatStats.set(targetShip.id, st);
        combatResultsThisTick.push(combatOut);

        if (
          combatOut.outcome === 'pirate_victory' &&
          combatOut.lootedCommodityId !== null &&
          combatOut.lootedQty > 0n
        ) {
          const prevQty =
            targetShip.cargo.get(combatOut.lootedCommodityId) ?? 0n;
          const nextQty =
            prevQty > combatOut.lootedQty ? prevQty - combatOut.lootedQty : 0n;
          targetShip.cargo.set(combatOut.lootedCommodityId, nextQty);
          stateMutatedByWorldEvent = true;
        } else if (
          combatOut.outcome === 'player_victory' &&
          combatOut.bountyCoins > 0n
        ) {
          // Hadiah koin dari menumpas Bajak Laut dibayarkan dari kas pelabuhan terdekat (zero-sum conservation)
          const nearPort =
            nextState.ports.get(targetShip.portId) ??
            nextState.ports.get(1);
          const ownerPl = nextState.players.get(targetShip.playerId);
          if (nearPort && ownerPl && nearPort.treasury >= combatOut.bountyCoins) {
            nearPort.treasury -= combatOut.bountyCoins;
            ownerPl.coins += combatOut.bountyCoins;
            ownerPl.ledgerSum += combatOut.bountyCoins;
            pirateBountyByPlayer.set(ownerPl.id, {
              coins: combatOut.bountyCoins,
              shipId: targetShip.id,
              pirateName: combatOut.pirateName,
            });
            stateMutatedByWorldEvent = true;
          }
        }

        await client.query(
          `INSERT INTO public.combat_logs (
             tick_no, attacker_id, defender_id, ship_id, pirate_name,
             damage, is_pirate, outcome, ship_attack_power,
             ship_defense_before, ship_defense_after,
             looted_commodity_code, looted_qty, bounty_coins, detail
           )
           VALUES ($1, NULL, $2, $3, $4, $5, true, $6, $7, $8, $9, $10, $11, $12, $13)`,
          [
            t,
            targetShip.playerId.toString(),
            targetShip.id.toString(),
            combatOut.pirateName,
            combatOut.damage,
            combatOut.outcome,
            combatOut.shipAttackPower,
            combatOut.shipDefenseBefore,
            combatOut.shipDefenseAfter,
            combatOut.lootedCommodityCode,
            combatOut.lootedQty.toString(),
            combatOut.bountyCoins.toString(),
            combatOut.detail,
          ],
        );

        (events.actionEvents as TickActionEvent[]).push({
          shipId: targetShip.id,
          playerId: targetShip.playerId,
          tickNo: t,
          ruleName: 'pertempuran_laut',
          actionType: 'wait',
          result: combatOut.outcome === 'player_victory' ? 'ok' : 'gagal',
          portId: targetShip.portId,
          detail: combatOut.detail,
        });
      }
    }

    if (stateMutatedByWorldEvent) {
      nextState.stateHash = computeCanonicalStateHash(nextState);
    }

    // Simpan perubahan pasar & riwayat harga
    for (const m of nextState.markets.values()) {
      await client.query(
        `UPDATE public.market
         SET stock = $1, price = $2
         WHERE port_id = $3 AND commodity_id = $4`,
        [m.stock.toString(), m.price.toString(), m.port_id, m.commodity_id],
      );
      await client.query(
        `INSERT INTO public.market_history (tick_no, port_id, commodity_id, price, stock)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (tick_no, port_id, commodity_id) DO UPDATE
         SET price = EXCLUDED.price, stock = EXCLUDED.stock`,
        [t, m.port_id, m.commodity_id, m.price.toString(), m.stock.toString()],
      );
    }

    // Simpan perubahan kas pelabuhan
    for (const p of nextState.ports.values()) {
      await client.query(
        `UPDATE public.ports SET treasury = $1 WHERE id = $2`,
        [p.treasury.toString(), p.id],
      );
    }

    // Catat sumber & pengurang kas pelabuhan di economy_sources_sinks
    if (events.portIncomeAddedTotal > 0n) {
      await client.query(
        `INSERT INTO public.economy_sources_sinks (tick_no, kind, reason, amount)
         VALUES ($1, 'source', 'port_income', $2)`,
        [t, events.portIncomeAddedTotal.toString()],
      );
    }
    if (events.portProducerPayoutTotal > 0n) {
      await client.query(
        `INSERT INTO public.economy_sources_sinks (tick_no, kind, reason, amount)
         VALUES ($1, 'sink', 'port_producer_payout', $2)`,
        [t, events.portProducerPayoutTotal.toString()],
      );
    }

    // Kelompokkan event aksi per pemain dan per kapal
    const okTradesByPlayer = new Map<bigint, TickActionEvent[]>();
    const eventsByShip = new Map<bigint, TickActionEvent[]>();

    for (const ev of events.actionEvents) {
      if (
        (ev.actionType === 'buy' || ev.actionType === 'sell') &&
        ev.result === 'ok'
      ) {
        const list = okTradesByPlayer.get(ev.playerId) ?? [];
        list.push(ev);
        okTradesByPlayer.set(ev.playerId, list);
      }
      const sList = eventsByShip.get(ev.shipId) ?? [];
      sList.push(ev);
      eventsByShip.set(ev.shipId, sList);

      if (metrics) {
        if (ev.result === 'dilewati' && ev.failureCode) {
          metrics.rules_skipped_total[ev.failureCode] =
            (metrics.rules_skipped_total[ev.failureCode] ?? 0) + 1;
        }
        const actKey = `${ev.result}:${ev.failureCode ?? 'NONE'}`;
        metrics.actions_total[actKey] =
          (metrics.actions_total[actKey] ?? 0) + 1;
      }
    }

    // Simpan perubahan saldo pemain & ledger (termasuk agregasi blok upkeep A5)
    const shouldBatchFlush =
      flushImmediately ||
      config.UPKEEP_LEDGER_BATCH_TICKS <= 1 ||
      t % config.UPKEEP_LEDGER_BATCH_TICKS === 0;

    for (const pl of nextState.players.values()) {
      const coinsBefore = coinsBeforeByPlayer.get(pl.id) ?? pl.coins;
      const unflushedBefore = unflushedBeforeByPlayer.get(pl.id) ?? 0n;
      const cumUpkeepBefore = cumUpkeepBeforeByPlayer.get(pl.id) ?? 0n;

      const playerTrades = okTradesByPlayer.get(pl.id) ?? [];
      const tradeDelta = playerTrades.reduce(
        (acc, ev) => acc + (ev.netPlayerDelta ?? 0n),
        0n,
      );
      const rescuedThisTick = pl.lastRescueTick === t;
      const rescueDelta = rescuedThisTick ? config.RESCUE_COINS : 0n;
      const bountyInfo = pirateBountyByPlayer.get(pl.id);
      const bountyDelta = bountyInfo ? bountyInfo.coins : 0n;

      // Hitung eksak perawatan kapal yang dibayar pemain pada tick ini
      const upkeepPaidThisTick =
        coinsBefore - pl.coins + tradeDelta + rescueDelta + bountyDelta;

      let newUnflushed =
        unflushedBefore + (upkeepPaidThisTick > 0n ? upkeepPaidThisTick : 0n);
      const newCumUpkeep =
        cumUpkeepBefore + (upkeepPaidThisTick > 0n ? upkeepPaidThisTick : 0n);

      const hasNonUpkeepLedgerEvent =
        playerTrades.length > 0 || rescuedThisTick || bountyDelta > 0n;

      if (
        newUnflushed > 0n &&
        (shouldBatchFlush || hasNonUpkeepLedgerEvent)
      ) {
        await client.query(
          `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
           VALUES ($1, $2, $3, 'upkeep', $4::jsonb)`,
          [
            pl.id.toString(),
            t,
            (-newUnflushed).toString(),
            JSON.stringify({ flushed_at_tick: t }),
          ],
        );
        newUnflushed = 0n;
      }

      for (const tr of playerTrades) {
        await client.query(
          `INSERT INTO public.ledger (player_id, tick_no, delta, reason, ref_ship, meta)
           VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
          [
            pl.id.toString(),
            t,
            (tr.netPlayerDelta ?? 0n).toString(),
            tr.actionType === 'buy' ? 'buy' : 'sell',
            tr.shipId.toString(),
            JSON.stringify({
              commodity_id: tr.commodityId,
              port_id: tr.portId,
              qty: (tr.executedQty ?? 0n).toString(),
              gross: (tr.grossValue ?? 0n).toString(),
              fee: (tr.fee ?? 0n).toString(),
            }),
          ],
        );
      }

      if (rescuedThisTick && rescueDelta > 0n) {
        await client.query(
          `INSERT INTO public.ledger (player_id, tick_no, delta, reason, meta)
           VALUES ($1, $2, $3, 'rescue', $4::jsonb)`,
          [
            pl.id.toString(),
            t,
            rescueDelta.toString(),
            JSON.stringify({ rescue_count: pl.rescueCount }),
          ],
        );
      }

      if (bountyInfo && bountyDelta > 0n) {
        await client.query(
          `INSERT INTO public.ledger (player_id, tick_no, delta, reason, ref_ship, meta)
           VALUES ($1, $2, $3, 'sell', $4, $5::jsonb)`,
          [
            pl.id.toString(),
            t,
            bountyDelta.toString(),
            bountyInfo.shipId.toString(),
            JSON.stringify({
              pirate_bounty: true,
              pirate_name: bountyInfo.pirateName,
            }),
          ],
        );

        // Fase 7: Progres Misi Harian "Pemburu Bajak Laut" (combat_win)
        await client.query(
          `INSERT INTO public.player_quests (player_id, quest_id, assigned_date, progress, is_completed, is_claimed)
           SELECT $1, q.id, CURRENT_DATE, 0, false, false
           FROM public.quests q
           ON CONFLICT (player_id, quest_id, assigned_date) DO NOTHING`,
          [pl.id.toString()],
        );
        await client.query(
          `UPDATE public.player_quests pq
           SET progress = LEAST(q.target_value, pq.progress + 1),
               is_completed = (pq.progress + 1 >= q.target_value)
           FROM public.quests q
           WHERE pq.quest_id = q.id
             AND pq.player_id = $1
             AND pq.assigned_date = CURRENT_DATE
             AND q.type = 'combat_win'`,
          [pl.id.toString()],
        );
      }

      // Fase 7: Progres Misi Harian "Perdagangan Pertama" (trade) bila ada transaksi beli/jual pada tick ini
      if (playerTrades.length > 0) {
        const tradedUnits = playerTrades.reduce(
          (acc, tr) => acc + Number(tr.executedQty ?? 0n),
          0,
        );
        if (tradedUnits > 0) {
          await client.query(
            `INSERT INTO public.player_quests (player_id, quest_id, assigned_date, progress, is_completed, is_claimed)
             SELECT $1, q.id, CURRENT_DATE, 0, false, false
             FROM public.quests q
             ON CONFLICT (player_id, quest_id, assigned_date) DO NOTHING`,
            [pl.id.toString()],
          );
          await client.query(
            `UPDATE public.player_quests pq
             SET progress = LEAST(q.target_value, pq.progress + $1),
                 is_completed = (pq.progress + $1 >= q.target_value)
             FROM public.quests q
             WHERE pq.quest_id = q.id
               AND pq.player_id = $2
               AND pq.assigned_date = CURRENT_DATE
               AND q.type = 'trade'`,
            [tradedUnits, pl.id.toString()],
          );
        }
      }

      // Hitung Net Worth pemain (Koin + Nilai Kapal Tambahan + Nilai Muatan) & perbarui Level Pemain (Fase 5)
      let playerShipCount = 0;
      let playerCargoVal = 0n;
      for (const sh of nextState.ships.values()) {
        if (sh.playerId === pl.id) {
          playerShipCount += 1;
          for (const [cid, cqty] of sh.cargo.entries()) {
            const bp = COM_BASE_PRICE_BY_ID.get(cid) ?? 0n;
            playerCargoVal += cqty * bp;
          }
        }
      }
      const addShipVal = BigInt(Math.max(0, playerShipCount - 1)) * 1500n;
      const playerNetWorth = pl.coins + addShipVal + playerCargoVal;
      const newPlayerLevel = calculatePlayerLevel(playerNetWorth);

      await client.query(
        `UPDATE public.players
         SET coins = $1,
             unflushed_upkeep = $2,
             cumulative_upkeep_paid = $3,
             level = $4
         WHERE id = $5`,
        [
          pl.coins.toString(),
          newUnflushed.toString(),
          newCumUpkeep.toString(),
          newPlayerLevel,
          pl.id.toString(),
        ],
      );
    }

    // Simpan perubahan kapal, kargo, memori kapal, kabut informasi (port_intel), dan action_log
    let groundedShipsCount = 0;
    for (const sh of nextState.ships.values()) {
      if (sh.status === 'grounded') {
        groundedShipsCount += 1;
      }

      const updatedDef =
        shipCombatStats.get(sh.id)?.defensePower ?? 100;
      await client.query(
        `UPDATE public.ships
         SET status = $1,
             port_id = $2,
             dest_port = $3,
             arrive_tick = $4,
             defense_power = $5
         WHERE id = $6`,
        [
          sh.status,
          sh.status === 'sailing' ? sh.portId : sh.portId,
          sh.destPort,
          sh.arriveTick !== null ? sh.arriveTick : null,
          updatedDef,
          sh.id.toString(),
        ],
      );

      for (const [comId, qty] of sh.cargo.entries()) {
        await client.query(
          `INSERT INTO public.ship_cargo (ship_id, commodity_id, qty)
           VALUES ($1, $2, $3)
           ON CONFLICT (ship_id, commodity_id) DO UPDATE
           SET qty = EXCLUDED.qty`,
          [sh.id.toString(), comId, qty.toString()],
        );
      }

      // Simpan memori kapal antar-tick (Phase 2: simpan/ambil)
      const memMap = shipMemories.get(sh.id);
      if (memMap) {
        for (const [slot, val] of memMap.entries()) {
          if (slot >= 0 && slot <= 7) {
            await client.query(
              `INSERT INTO public.ship_memory (ship_id, slot, val, updated_at)
               VALUES ($1, $2, $3, now())
               ON CONFLICT (ship_id, slot) DO UPDATE
               SET val = EXCLUDED.val, updated_at = now()`,
              [sh.id.toString(), slot, val.toString()],
            );
          }
        }
      }

      // Perbarui Kabut Informasi Harga (ADR-012: port_intel) bila kapal sandar/grounded di pelabuhan
      if (
        (sh.status === 'docked' || sh.status === 'grounded') &&
        sh.portId >= 1 &&
        sh.portId <= 6
      ) {
        for (const com of COMMODITIES_SEED) {
          const m = nextState.markets.get(`${sh.portId}:${com.id}`);
          if (m) {
            await client.query(
              `INSERT INTO public.port_intel (player_id, port_id, commodity_id, price, stock, tick_seen, updated_at)
               VALUES ($1, $2, $3, $4, $5, $6, now())
               ON CONFLICT (player_id, port_id, commodity_id) DO UPDATE
               SET price = EXCLUDED.price,
                   stock = EXCLUDED.stock,
                   tick_seen = EXCLUDED.tick_seen,
                   updated_at = now()`,
              [
                sh.playerId.toString(),
                sh.portId,
                com.id,
                m.price.toString(),
                m.stock.toString(),
                t,
              ],
            );
          }
        }
      }

      const shEvents = eventsByShip.get(sh.id) ?? [];
      if (shEvents.length > 0) {
        const lastEv = shEvents[shEvents.length - 1]!;
        const formatted = shEvents.map((e) => formatActionEventSummary(e));
        const terminalFormatted = formatted[formatted.length - 1]!;
        const combinedDetail = formatted.map((f) => f.detailText).join(' | ');

        await client.query(
          `INSERT INTO public.action_log (ship_id, tick_no, rule_name, action, result, detail)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [
            sh.id.toString(),
            t,
            lastEv.ruleName,
            terminalFormatted.actionText,
            lastEv.result,
            combinedDetail,
          ],
        );
      } else if (sh.status === 'sailing') {
        const destName =
          sh.destPort !== null
            ? (PORT_CODE_BY_ID.get(sh.destPort) ?? String(sh.destPort))
            : '';
        await client.query(
          `INSERT INTO public.action_log (ship_id, tick_no, rule_name, action, result, detail)
           VALUES ($1, $2, 'berlayar', $3, 'berlayar', $4)`,
          [
            sh.id.toString(),
            t,
            `berlayar(${destName})`,
            `dalam pelayaran menuju ${destName} (tiba tick ${sh.arriveTick ?? t})`,
          ],
        );
      }
    }

    // Sistem Kedaluwarsa P2P Trading (Detail 2B: otomatis batal setelah 1.440 tick / 24 jam & kembalikan aset ke penjual)
    const expiredP2pRes = await client.query<{
      id: string;
      ship_id: string;
      commodity_id: number;
      qty: string;
    }>(
      `SELECT id::text, ship_id::text, commodity_id, qty::text
       FROM public.p2p_orders
       WHERE status = 'open' AND expires_tick <= $1
       ORDER BY id ASC
       FOR UPDATE`,
      [t],
    );
    for (const expOrder of expiredP2pRes.rows) {
      const shId = BigInt(expOrder.ship_id);
      const shState = nextState.ships.get(shId);
      if (shState) {
        let totalCargo = 0n;
        for (const q of shState.cargo.values()) totalCargo += q;
        const freeSpace = BigInt(shState.capacity) - totalCargo;
        const returnQty =
          freeSpace > 0n
            ? BigInt(expOrder.qty) <= freeSpace
              ? BigInt(expOrder.qty)
              : freeSpace
            : 0n;
        if (returnQty > 0n) {
          const prevQty = shState.cargo.get(expOrder.commodity_id) ?? 0n;
          const nextQty = prevQty + returnQty;
          shState.cargo.set(expOrder.commodity_id, nextQty);
          await client.query(
            `INSERT INTO public.ship_cargo (ship_id, commodity_id, qty)
             VALUES ($1, $2, $3)
             ON CONFLICT (ship_id, commodity_id) DO UPDATE
             SET qty = EXCLUDED.qty`,
            [shId.toString(), expOrder.commodity_id, nextQty.toString()],
          );
        }
      }
      await client.query(
        `UPDATE public.p2p_orders
         SET status = 'expired', updated_at = now()
         WHERE id = $1`,
        [expOrder.id],
      );
    }

    // Fase 8: Integrasi Combat World Boss ("Bajak Laut Armada Besar") untuk Aliansi dengan kas > 10.000 koin
    const richGuildsRes = await client.query<{
      id: string;
      code: string;
      name: string;
      treasury_coins: string;
      boss_active: boolean;
      boss_name: string;
      boss_hp: number;
      boss_max_hp: number;
      boss_port_id: number | null;
      boss_spawned_tick: string | null;
    }>(
      `SELECT
         id::text, code, name, treasury_coins::text,
         boss_active, boss_name, boss_hp, boss_max_hp, boss_port_id, boss_spawned_tick::text
       FROM public.guilds
       WHERE treasury_coins > 10000
       ORDER BY id ASC
       FOR UPDATE`,
    );

    for (const rg of richGuildsRes.rows) {
      let isBossActive = Boolean(rg.boss_active);
      let currentBossHp = Number(rg.boss_hp ?? 0);
      const bossMaxHp = Number(rg.boss_max_hp || 500);
      const bossPortId = rg.boss_port_id !== null ? Number(rg.boss_port_id) : 1;

      if (!isBossActive && rg.boss_spawned_tick === null) {
        isBossActive = true;
        currentBossHp = bossMaxHp;
        await client.query(
          `UPDATE public.guilds
           SET boss_active = true,
               boss_name = 'Bajak Laut Armada Besar',
               boss_hp = $1,
               boss_max_hp = $2,
               boss_port_id = $3,
               boss_spawned_tick = $4
           WHERE id = $5`,
          [currentBossHp, bossMaxHp, bossPortId, t, rg.id],
        );

        if (!triggeredEventRecord) {
          triggeredEventRecord = {
            eventCode: 'WORLD_BOSS_BAJAK_LAUT',
            title: 'Bajak Laut Armada Besar',
            description: `Kas Aliansi ${rg.name} melampaui 10.000 koin! "Bajak Laut Armada Besar" muncul di perairan Banda menantang seluruh armada aliansi!`,
            portId: bossPortId,
            commodityId: null,
            activeUntilTick: t + 50,
            isActive: true,
            effectMeta: {
              kind: 'WORLD_BOSS_BAJAK_LAUT',
              guild_id: Number(rg.id),
              guild_code: rg.code,
              guild_name: rg.name,
              boss_name: 'Bajak Laut Armada Besar',
              boss_hp: currentBossHp,
              boss_max_hp: bossMaxHp,
              port_id: bossPortId,
            },
          };
        }
      }

      // Kapal anggota Guild yang memiliki senjata (attack_power > 0) ikut menembaki World Boss secara kolektif
      if (isBossActive && currentBossHp > 0) {
        const guildShipsRes = await client.query<{
          ship_id: string;
          ship_name: string;
          player_id: string;
          attack_power: number;
        }>(
          `SELECT s.id::text AS ship_id, s.name AS ship_name, s.player_id::text, s.attack_power
           FROM public.guild_members gm
           JOIN public.ships s ON s.player_id = gm.player_id
           WHERE gm.guild_id = $1 AND s.attack_power > 0
           ORDER BY s.id ASC`,
          [rg.id],
        );

        for (const gs of guildShipsRes.rows) {
          if (currentBossHp <= 0) break;
          const salvoDmg = Math.min(50, Math.max(10, Number(gs.attack_power)));
          currentBossHp = Math.max(0, currentBossHp - salvoDmg);
          const bossDefeated = currentBossHp === 0;

          await client.query(
            `INSERT INTO public.combat_logs (
               tick_no, attacker_id, defender_id, ship_id, damage, is_pirate, outcome, bounty_coins, loot_summary, detail
             )
             VALUES ($1, $2, NULL, $3, $4, true, $5, 0, '{}'::jsonb, $6)`,
            [
              t,
              gs.player_id,
              gs.ship_id,
              salvoDmg,
              bossDefeated ? 'player_win' : 'boss_hit',
              bossDefeated
                ? `Armada Aliansi (${gs.ship_name}) menumpas World Boss Bajak Laut Armada Besar!`
                : `Serangan bersama Aliansi (${gs.ship_name}) menghantam Bajak Laut Armada Besar (-${salvoDmg} HP, sisa ${currentBossHp}/${bossMaxHp} HP).`,
            ],
          );
        }

        await client.query(
          `UPDATE public.guilds
           SET boss_hp = $1,
               boss_active = $2
           WHERE id = $3`,
          [currentBossHp, currentBossHp > 0, rg.id],
        );
      }
    }

    // Catat musim & event dunia pada tick ini (Phase 2 & Fase 3: world_events)
    const seasonInfo = getSeasonForTick(t);
    const evCode = triggeredEventRecord
      ? triggeredEventRecord.eventCode
      : seasonInfo.eventCode;
    const evTitle = triggeredEventRecord
      ? triggeredEventRecord.title
      : seasonInfo.title;
    const evDesc = triggeredEventRecord
      ? triggeredEventRecord.description
      : seasonInfo.description;
    const evPortId = triggeredEventRecord ? triggeredEventRecord.portId : null;
    const evComId = triggeredEventRecord
      ? triggeredEventRecord.commodityId
      : null;
    const evActiveUntil = triggeredEventRecord
      ? triggeredEventRecord.activeUntilTick
      : t;
    const evIsActive = triggeredEventRecord
      ? triggeredEventRecord.isActive
      : true;
    const evMeta = triggeredEventRecord
      ? triggeredEventRecord.effectMeta
      : { kind: 'SEASON', season_code: seasonInfo.seasonCode };

    await client.query(
      `INSERT INTO public.world_events (
         tick_no, season, event_code, title, description,
         port_id, commodity_id, active_until_tick, is_active, effect_meta
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
       ON CONFLICT (tick_no) DO UPDATE
       SET season = EXCLUDED.season,
           event_code = EXCLUDED.event_code,
           title = EXCLUDED.title,
           description = EXCLUDED.description,
           port_id = EXCLUDED.port_id,
           commodity_id = EXCLUDED.commodity_id,
           active_until_tick = EXCLUDED.active_until_tick,
           is_active = EXCLUDED.is_active,
           effect_meta = EXCLUDED.effect_meta`,
      [
        t,
        seasonInfo.seasonCode,
        evCode,
        evTitle,
        evDesc,
        evPortId,
        evComId,
        evActiveUntil,
        evIsActive,
        JSON.stringify(evMeta),
      ],
    );

    // Prune riwayat lebih tua dari 2.000 tick (docs/07)
    if (t > 2000 && t % 100 === 0) {
      const cutoff = t - 2000;
      await client.query(
        `DELETE FROM public.action_log WHERE tick_no < $1`,
        [cutoff],
      );
      await client.query(
        `DELETE FROM public.market_history WHERE tick_no < $1`,
        [cutoff],
      );
      await client.query(
        `DELETE FROM public.world_events WHERE tick_no < $1`,
        [cutoff],
      );
    }

    if (options?.beforeCommitHook) {
      await options.beforeCommitHook(t, client);
    }

    const finishedAt = new Date();
    const durationMs = Math.max(0, Date.now() - startMs);

    // Langkah 9: Tulis tick_state dengan state_hash dan durasi, lalu COMMIT
    await client.query(
      `INSERT INTO public.tick_state (tick_no, started_at, finished_at, duration_ms, state_hash)
       VALUES ($1, $2, $3, $4, $5)`,
      [t, startedAt, finishedAt, durationMs, nextState.stateHash],
    );

    await client.query('COMMIT');

    if (metrics) {
      metrics.tick_duration_ms = durationMs;
      metrics.ticks_completed_total += 1;
      metrics.ships_grounded = groundedShipsCount;
      metrics.rescue_granted_total += events.rescueGrantedCount;
      const budgetMs = config.TICK_SECONDS * 1000 * 0.8;
      if (durationMs > budgetMs) {
        metrics.tick_lag_ms = Math.round(durationMs - budgetMs);
      }
    }

    return {
      tickNo: t,
      stateHash: nextState.stateHash,
      durationMs,
      state: nextState,
      triggeredEvent: triggeredEventRecord,
      combatResults: combatResultsThisTick,
    };
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore rollback error
    }
    throw err;
  } finally {
    client.release();
  }
}

function eventsByShipFromStep(
  actionEvents: readonly TickActionEvent[],
  shipId: bigint,
): TickActionEvent[] {
  return actionEvents.filter((e) => e.shipId === shipId);
}

export interface WorkerLoopController {
  readonly metrics: WorkerMetrics;
  stop(): Promise<void>;
}

/**
 * Menjalankan loop worker dengan kunci advisory pada koneksi khusus dan penjadwal
 * terkoreksi drift (nextRun = start + n * interval) sesuai docs/09 v0.2.
 */
export async function startWorkerLoop(
  pool: pg.Pool,
  options?: {
    lockKey?: number;
    config?: WorldEconomyConfig;
    worldSeed?: number;
    intervalMs?: number;
  },
): Promise<WorkerLoopController | null> {
  const config = options?.config ?? WORLD_CONFIG;
  const intervalMs = options?.intervalMs ?? config.TICK_SECONDS * 1000;
  const lockHandle = await acquireWorkerAdvisoryLock(
    pool,
    options?.lockKey ?? DEFAULT_WORKER_ADVISORY_LOCK_KEY,
  );
  if (!lockHandle) {
    return null;
  }

  const metrics = createInitialWorkerMetrics();
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let activeTickPromise: Promise<void> | null = null;
  const loopStartMs = Date.now();
  let stepIndex = 0;

  async function scheduleNext(): Promise<void> {
    if (stopped) return;
    stepIndex += 1;
    const targetMs = loopStartMs + stepIndex * intervalMs;
    const now = Date.now();
    const delayMs = Math.max(0, targetMs - now);

    if (now > targetMs) {
      metrics.tick_lag_ms = now - targetMs;
      // Lewati jadwal yang terlewat agar tidak menumpuk antrean (docs/09)
      const skippedSteps = Math.floor((now - targetMs) / intervalMs);
      stepIndex += skippedSteps;
    }

    timer = setTimeout(async () => {
      if (stopped) return;
      const alive = await lockHandle!.verifyAlive();
      if (!alive) {
        stopped = true;
        await lockHandle!.release();
        return;
      }

      activeTickPromise = (async () => {
        try {
          await executeSingleWorldTick(pool, {
            config,
            ...(options?.worldSeed !== undefined
              ? { worldSeed: options.worldSeed }
              : {}),
            metrics,
          });
        } catch (err) {
          console.error('[WORKER] Tick gagal, menghentikan worker:', err);
          stopped = true;
          await lockHandle!.release();
          return;
        }
      })();

      await activeTickPromise;
      activeTickPromise = null;

      if (!stopped) {
        void scheduleNext();
      }
    }, delayMs);
  }

  void scheduleNext();

  return {
    metrics,
    async stop(): Promise<void> {
      stopped = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      if (activeTickPromise) {
        await activeTickPromise;
      }
      await lockHandle.release();
    },
  };
}
