import {
  WORLD_CONFIG,
  WorldEconomyConfig,
  COMMODITIES_SEED,
  PORTS_SEED,
} from '@jalur-rempah/shared';
import {
  WorldState,
  stepWorld,
  computeCanonicalStateHash,
} from '@jalur-rempah/econ';
import {
  CompiledDslProgram,
  createDslShipRuleDecider,
} from '@jalur-rempah/dsl';

export interface SandboxSimulationResult {
  readonly ticks: number;
  readonly final_coins_delta: number;
  readonly final_coins: number;
  readonly trades: number;
  readonly actions_summary: readonly {
    readonly action: string;
    readonly result: string;
    readonly count: number;
  }[];
  readonly log_sample: readonly {
    readonly tick_no: number;
    readonly rule_name: string;
    readonly action: string;
    readonly result: string;
    readonly detail: string;
  }[];
  readonly disclaimer: string;
}

const PORT_CODE_BY_ID = new Map(PORTS_SEED.map((p) => [p.id, p.code]));
const COM_CODE_BY_ID = new Map(COMMODITIES_SEED.map((c) => [c.id, c.code]));

export function cloneWorldStateForSandbox(
  sourceState: Readonly<WorldState>,
  targetShipId: bigint,
): WorldState | null {
  const ship = sourceState.ships.get(targetShipId);
  if (!ship) return null;
  const player = sourceState.players.get(ship.playerId);
  if (!player) return null;

  const players = new Map([
    [
      player.id,
      {
        id: player.id,
        coins: player.coins,
        initialCoins: player.coins,
        ledgerSum: player.coins,
        lastRescueTick: player.lastRescueTick,
        rescueCount: player.rescueCount,
      },
    ],
  ]);

  const ports = new Map();
  for (const [pId, p] of sourceState.ports.entries()) {
    ports.set(pId, {
      id: p.id,
      code: p.code,
      name: p.name,
      treasury: p.treasury,
      initialTreasury: p.treasury,
    });
  }

  const markets = new Map();
  for (const [mKey, m] of sourceState.markets.entries()) {
    markets.set(mKey, { ...m });
  }

  const cargoClone = new Map<number, bigint>();
  for (const [cId, qty] of ship.cargo.entries()) {
    cargoClone.set(cId, qty);
  }

  const ships = new Map([
    [
      ship.id,
      {
        id: ship.id,
        playerId: ship.playerId,
        capacity: ship.capacity,
        status: ship.status,
        portId: ship.portId,
        destPort: ship.destPort,
        arriveTick: ship.arriveTick,
        cargo: cargoClone,
      },
    ],
  ]);

  const cloned: WorldState = {
    tickNo: sourceState.tickNo,
    players,
    ports,
    markets,
    ships,
    cumulativeUpkeepSink: 0n,
    cumulativeSource: 0n,
    stateHash: '',
  };
  cloned.stateHash = computeCanonicalStateHash(cloned);
  return cloned;
}

/**
 * Menjalankan simulasi sandbox hingga 300 tick menggunakan fungsi stepWorld yang sama
 * dengan worker dan simulator, pada salinan state di memori tanpa menulis ke DB (docs/08 & docs/09).
 */
export function runSandboxSimulation(
  snapshot: Readonly<WorldState>,
  shipId: bigint,
  compiledProgram: CompiledDslProgram,
  ticks: number,
  config: WorldEconomyConfig = WORLD_CONFIG,
  worldSeed: number = 101,
): SandboxSimulationResult {
  const cloned = cloneWorldStateForSandbox(snapshot, shipId);
  if (!cloned) {
    throw new Error(`Kapal ${shipId.toString()} tidak ditemukan pada snapshot.`);
  }

  const ship = cloned.ships.get(shipId)!;
  const player = cloned.players.get(ship.playerId)!;
  const initialCoins = player.coins;

  const shipMemories = new Map<bigint, Map<number, bigint>>([
    [shipId, new Map<number, bigint>()],
  ]);
  const decider = createDslShipRuleDecider(
    new Map([[shipId, compiledProgram]]),
    undefined,
    { shipMemories },
  );

  let tradesCount = 0;
  const summaryMap = new Map<
    string,
    { action: string; result: string; count: number }
  >();
  const logSample: Array<{
    tick_no: number;
    rule_name: string;
    action: string;
    result: string;
    detail: string;
  }> = [];

  const startMs = Date.now();
  const safeTicks = Math.min(Math.max(1, ticks), 300);

  for (let i = 0; i < safeTicks; i++) {
    if (Date.now() - startMs > 2000) {
      break;
    }

    const { events } = stepWorld(cloned, decider, config, worldSeed, false);

    for (const ev of events.actionEvents) {
      if (
        (ev.actionType === 'buy' || ev.actionType === 'sell') &&
        ev.result === 'ok'
      ) {
        tradesCount += 1;
      }

      const key = `${ev.actionType}:${ev.result}`;
      const cur = summaryMap.get(key);
      if (cur) {
        cur.count += 1;
      } else {
        summaryMap.set(key, {
          action: ev.actionType,
          result: ev.result,
          count: 1,
        });
      }

      if (logSample.length < 100) {
        const comName =
          ev.commodityId !== undefined
            ? (COM_CODE_BY_ID.get(ev.commodityId) ?? String(ev.commodityId))
            : '';
        const destName =
          ev.destPortId !== undefined
            ? (PORT_CODE_BY_ID.get(ev.destPortId) ?? String(ev.destPortId))
            : '';
        let actionLabel: string = ev.actionType;
        if (ev.actionType === 'buy') {
          actionLabel = `beli(${comName}, ${(ev.executedQty ?? 0n).toString()})`;
        } else if (ev.actionType === 'sell') {
          actionLabel = `jual(${comName}, ${(ev.executedQty ?? 0n).toString()})`;
        } else if (ev.actionType === 'sail') {
          actionLabel = `berlayar(${destName})`;
        } else if (ev.actionType === 'wait') {
          actionLabel = 'tunggu()';
        }

        const detailText =
          ev.detail ??
          (ev.failureCode
            ? `${ev.failureCode}: aksi ${ev.actionType} gagal`
            : `aksi ${actionLabel} (${ev.result})`);

        logSample.push({
          tick_no: ev.tickNo,
          rule_name: ev.ruleName,
          action: actionLabel,
          result: ev.result,
          detail: detailText,
        });
      }
    }
  }

  const finalCoins = cloned.players.get(ship.playerId)?.coins ?? initialCoins;
  const delta = finalCoins - initialCoins;

  return {
    ticks: safeTicks,
    final_coins_delta: Number(delta),
    final_coins: Number(finalCoins),
    trades: tradesCount,
    actions_summary: Array.from(summaryMap.values()),
    log_sample: logSample,
    disclaimer:
      'Simulasi sandbox menggunakan snapshot pasar saat ini tanpa pergerakan kapal pemain lain; hasil adalah perkiraan.',
  };
}
