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
const COM_CODE_BY_ID = new Map(COMMODITIES_SEED.map((c) => [c.id, c.code]));

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
}

/**
 * Menjalankan tepat satu tick dunia di dalam satu transaksi READ COMMITTED menggunakan
 * fungsi murni stepWorld dari @jalur-rempah/econ (docs/09 v0.2).
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
    }>(
      `SELECT id::text, coins::text, unflushed_upkeep::text, cumulative_upkeep_paid::text
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
      capacity: number;
      status: ShipStatus;
      port_id: number | null;
      dest_port: number | null;
      arrive_tick: string | null;
    }>(
      `SELECT id::text, player_id::text, capacity, status, port_id, dest_port, arrive_tick::text
       FROM public.ships
       ORDER BY id ASC
       FOR UPDATE`,
    );

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
        const revived = reviveBigIntsInAst(r.compiled) as CompiledDslProgram;
        if (revived && Array.isArray(revived.rules)) {
          programsByShip.set(BigInt(r.ship_id), revived);
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

      // Hitung eksak perawatan kapal yang dibayar pemain pada tick ini
      const upkeepPaidThisTick =
        coinsBefore - pl.coins + tradeDelta + rescueDelta;

      let newUnflushed =
        unflushedBefore + (upkeepPaidThisTick > 0n ? upkeepPaidThisTick : 0n);
      const newCumUpkeep =
        cumUpkeepBefore + (upkeepPaidThisTick > 0n ? upkeepPaidThisTick : 0n);

      const hasNonUpkeepLedgerEvent =
        playerTrades.length > 0 || rescuedThisTick;

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

      await client.query(
        `UPDATE public.players
         SET coins = $1,
             unflushed_upkeep = $2,
             cumulative_upkeep_paid = $3
         WHERE id = $4`,
        [
          pl.coins.toString(),
          newUnflushed.toString(),
          newCumUpkeep.toString(),
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

      await client.query(
        `UPDATE public.ships
         SET status = $1,
             port_id = $2,
             dest_port = $3,
             arrive_tick = $4
         WHERE id = $5`,
        [
          sh.status,
          sh.status === 'sailing' ? sh.portId : sh.portId,
          sh.destPort,
          sh.arriveTick !== null ? sh.arriveTick : null,
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

    // Catat musim & event dunia pada tick ini (Phase 2: world_events)
    const seasonInfo = getSeasonForTick(t);
    await client.query(
      `INSERT INTO public.world_events (tick_no, season, event_code, title, description)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (tick_no) DO UPDATE
       SET season = EXCLUDED.season,
           event_code = EXCLUDED.event_code,
           title = EXCLUDED.title,
           description = EXCLUDED.description`,
      [
        t,
        seasonInfo.seasonCode,
        seasonInfo.eventCode,
        seasonInfo.title,
        seasonInfo.description,
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
