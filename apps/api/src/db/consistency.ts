import pg from 'pg';
import { getPool } from './connection.js';

export interface DatabaseConsistencyReport {
  readonly valid: boolean;
  readonly ledgerMismatchPlayerIds: readonly string[];
  readonly midBatchMismatchPlayerIds: readonly string[];
  readonly cargoOverflowShipIds: readonly string[];
  readonly negativeBalanceCount: number;
  readonly moneyConservationValid: boolean;
  readonly moneySupplyAudit: {
    readonly totalPlayerCoins: string;
    readonly totalPortTreasury: string;
    readonly cumulativeUpkeepSink: string;
    readonly totalInitialMoney: string;
    readonly cumulativeSource: string;
  };
}

/**
 * Menjalankan seluruh pemeriksaan konsistensi database sesuai docs/07-DATA-MODEL.md.
 */
export async function checkDatabaseConsistency(
  pool: pg.Pool = getPool(),
): Promise<DatabaseConsistencyReport> {
  // 1a. Saldo pemain + unflushed_upkeep == SUM(ledger.delta) (berlaku eksak di setiap tick)
  const midBatchRes = await pool.query<{ id: string }>(`
    SELECT p.id::text AS id
    FROM public.players p
    LEFT JOIN (
      SELECT player_id, SUM(delta) AS s
      FROM public.ledger
      GROUP BY player_id
    ) l ON l.player_id = p.id
    WHERE (p.coins + p.unflushed_upkeep) <> COALESCE(l.s, 0);
  `);

  // 1b. Saldo pemain == SUM(ledger.delta) untuk pemain yang unflushed_upkeep == 0
  const flushedRes = await pool.query<{ id: string }>(`
    SELECT p.id::text AS id
    FROM public.players p
    LEFT JOIN (
      SELECT player_id, SUM(delta) AS s
      FROM public.ledger
      GROUP BY player_id
    ) l ON l.player_id = p.id
    WHERE p.unflushed_upkeep = 0 AND p.coins <> COALESCE(l.s, 0);
  `);

  // 2. Muatan <= kapasitas
  const cargoRes = await pool.query<{ id: string }>(`
    SELECT s.id::text AS id
    FROM public.ships s
    JOIN public.ship_cargo c ON c.ship_id = s.id
    GROUP BY s.id, s.capacity
    HAVING SUM(c.qty) > s.capacity;
  `);

  // 3. Cek nilai negatif
  const negRes = await pool.query<{ cnt: string }>(`
    SELECT (
      (SELECT count(*) FROM public.players WHERE coins < 0 OR unflushed_upkeep < 0)
      + (SELECT count(*) FROM public.ports WHERE treasury < 0)
      + (SELECT count(*) FROM public.market WHERE stock < 0 OR stock > capacity OR price < 1)
      + (SELECT count(*) FROM public.ship_cargo WHERE qty < 0)
    )::text AS cnt;
  `);
  const negativeBalanceCount = Number(negRes.rows[0]?.cnt ?? '0');

  // 4. Konservasi Uang Global (economy_money_supply_audit)
  const auditRes = await pool.query<{
    total_player_coins: string;
    total_port_treasury: string;
    cumulative_upkeep_sink: string;
    total_initial_money: string;
    cumulative_source: string;
  }>(`SELECT * FROM public.economy_money_supply_audit`);

  const row = auditRes.rows[0] ?? {
    total_player_coins: '0',
    total_port_treasury: '0',
    cumulative_upkeep_sink: '0',
    total_initial_money: '0',
    cumulative_source: '0',
  };

  const lhs =
    BigInt(row.total_player_coins) +
    BigInt(row.total_port_treasury) +
    BigInt(row.cumulative_upkeep_sink);
  const rhs = BigInt(row.total_initial_money) + BigInt(row.cumulative_source);
  const moneyConservationValid = lhs === rhs;

  const valid =
    midBatchRes.rows.length === 0 &&
    flushedRes.rows.length === 0 &&
    cargoRes.rows.length === 0 &&
    negativeBalanceCount === 0 &&
    moneyConservationValid;

  return {
    valid,
    ledgerMismatchPlayerIds: flushedRes.rows.map((r) => r.id),
    midBatchMismatchPlayerIds: midBatchRes.rows.map((r) => r.id),
    cargoOverflowShipIds: cargoRes.rows.map((r) => r.id),
    negativeBalanceCount,
    moneyConservationValid,
    moneySupplyAudit: {
      totalPlayerCoins: row.total_player_coins,
      totalPortTreasury: row.total_port_treasury,
      cumulativeUpkeepSink: row.cumulative_upkeep_sink,
      totalInitialMoney: row.total_initial_money,
      cumulativeSource: row.cumulative_source,
    },
  };
}
