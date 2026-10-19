import pg from 'pg';
import { fileURLToPath } from 'node:url';

export interface BetaEvaluationReport {
  readonly current_tick: number;
  readonly active_players: number;
  readonly anonymized_players: number;
  readonly total_ships: number;
  readonly grounded_ships: number;
  readonly retention_active_200t: number;
  readonly retention_rate_pct: number;
  readonly gini_coefficient: number;
  readonly money_conservation_diff: string;
  readonly guilds_total: number;
  readonly contracts_open: number;
  readonly contracts_fulfilled: number;
}

function computeGini(values: readonly number[]): number {
  if (values.length <= 1) return 0;
  const sorted = [...values].map((v) => Math.max(0, v)).sort((a, b) => a - b);
  const n = sorted.length;
  const mean = sorted.reduce((acc, v) => acc + v, 0) / n;
  if (mean <= 0) return 0;

  let diffSum = 0;
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      diffSum += Math.abs((sorted[i] ?? 0) - (sorted[j] ?? 0));
    }
  }
  const gini = diffSum / (2 * n * n * mean);
  return Math.round(gini * 10000) / 10000;
}

/**
 * Mengevaluasi data beta (kesehatan ekonomi, ketimpangan Gini, konservasi uang,
 * retensi pemain aktif, serikat dagang, dan kontrak pengiriman) sesuai docs/13 Setelah MVP #1.
 */
export async function evaluateBetaMetrics(
  pool: pg.Pool,
): Promise<BetaEvaluationReport> {
  const tickRes = await pool.query<{ max_tick: string }>(
    `SELECT COALESCE(MAX(tick_no), 0)::text AS max_tick FROM public.tick_state`,
  );
  const currentTick = Number(tickRes.rows[0]?.max_tick ?? '0');

  const pCountRes = await pool.query<{
    active_cnt: string;
    anon_cnt: string;
  }>(
    `SELECT
       COUNT(*) FILTER (WHERE is_deleted = false)::text AS active_cnt,
       COUNT(*) FILTER (WHERE is_deleted = true)::text AS anon_cnt
     FROM public.players`,
  );
  const activePlayers = Number(pCountRes.rows[0]?.active_cnt ?? '0');
  const anonymizedPlayers = Number(pCountRes.rows[0]?.anon_cnt ?? '0');

  const sCountRes = await pool.query<{
    total_cnt: string;
    grounded_cnt: string;
  }>(
    `SELECT
       COUNT(*)::text AS total_cnt,
       COUNT(*) FILTER (WHERE status = 'grounded')::text AS grounded_cnt
     FROM public.ships`,
  );
  const totalShips = Number(sCountRes.rows[0]?.total_cnt ?? '0');
  const groundedShips = Number(sCountRes.rows[0]?.grounded_cnt ?? '0');

  const cutoffTick = Math.max(0, currentTick - 200);
  const retRes = await pool.query<{ active_200t: string }>(
    `SELECT COUNT(DISTINCT s.player_id)::text AS active_200t
     FROM public.action_log al
     JOIN public.ships s ON s.id = al.ship_id
     JOIN public.players p ON p.id = s.player_id
     WHERE p.is_deleted = false AND al.tick_no >= $1`,
    [cutoffTick],
  );
  const retentionActive200t = Number(retRes.rows[0]?.active_200t ?? '0');
  const retentionRatePct =
    activePlayers > 0
      ? Math.round((retentionActive200t / activePlayers) * 10000) / 100
      : 0;

  const nwRes = await pool.query<{ net_worth: string }>(
    `SELECT (p.coins + COALESCE(SUM(sc.qty * c.base_price), 0))::text AS net_worth
     FROM public.players p
     LEFT JOIN public.ships s ON s.player_id = p.id
     LEFT JOIN public.ship_cargo sc ON sc.ship_id = s.id
     LEFT JOIN public.commodities c ON c.id = sc.commodity_id
     WHERE p.is_deleted = false
     GROUP BY p.id, p.coins`,
  );
  const netWorths = nwRes.rows.map((r) => Number(r.net_worth));
  const giniCoefficient = computeGini(netWorths);

  const auditRes = await pool.query<{ diff: string }>(
    `SELECT ((total_player_coins + total_port_treasury + cumulative_upkeep_sink) - (total_initial_money + cumulative_source))::text AS diff
     FROM public.economy_money_supply_audit`,
  );
  const moneyConservationDiff = auditRes.rows[0]?.diff ?? '0';

  const guildRes = await pool.query<{ cnt: string }>(
    `SELECT COUNT(*)::text AS cnt FROM public.guilds`,
  );
  const guildsTotal = Number(guildRes.rows[0]?.cnt ?? '0');

  const contractRes = await pool.query<{
    open_cnt: string;
    fulfilled_cnt: string;
  }>(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'open')::text AS open_cnt,
       COUNT(*) FILTER (WHERE status = 'fulfilled')::text AS fulfilled_cnt
     FROM public.trade_contracts`,
  );
  const contractsOpen = Number(contractRes.rows[0]?.open_cnt ?? '0');
  const contractsFulfilled = Number(contractRes.rows[0]?.fulfilled_cnt ?? '0');

  return {
    current_tick: currentTick,
    active_players: activePlayers,
    anonymized_players: anonymizedPlayers,
    total_ships: totalShips,
    grounded_ships: groundedShips,
    retention_active_200t: retentionActive200t,
    retention_rate_pct: retentionRatePct,
    gini_coefficient: giniCoefficient,
    money_conservation_diff: moneyConservationDiff,
    guilds_total: guildsTotal,
    contracts_open: contractsOpen,
    contracts_fulfilled: contractsFulfilled,
  };
}

async function runCli(): Promise<void> {
  const connectionString =
    process.env['DATABASE_URL'] ??
    'postgres://postgres:postgres@127.0.0.1:5432/jalur_rempah';
  const pool = new pg.Pool({ connectionString, max: 2 });
  try {
    const report = await evaluateBetaMetrics(pool);
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await pool.end();
  }
}

const currentPath = fileURLToPath(import.meta.url);
if (process.argv[1] && process.argv[1] === currentPath) {
  runCli().catch((err) => {
    console.error('[BETA-EVAL] Gagal mengevaluasi metrik beta:', err);
    process.exit(1);
  });
}
