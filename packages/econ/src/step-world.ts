import crypto from 'node:crypto';
import {
  COMMODITIES_SEED,
  ROUTES_SEED,
  WORLD_CONFIG,
  WorldEconomyConfig,
  ShipStatus,
  MarketRow,
} from '@jalur-rempah/shared';
import { stepProduksiKonsumsi } from './production.js';
import { eksekusiBeli, eksekusiJual, TradeFailureCode } from './trade.js';
import { periksaInvarianEkonomi, InvariantCheckResult } from './invariants.js';

export type RuleRuntimeErrorCode =
  | 'DIV_ZERO'
  | 'OVERFLOW'
  | 'BUDGET_EXCEEDED';

export type RuleActionFailureCode =
  | TradeFailureCode
  | RuleRuntimeErrorCode
  | 'NOT_DOCKED'
  | 'SAME_PORT'
  | 'NO_ROUTE'
  | 'GROUNDED';

export type CandidateAction =
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'buy';
      readonly commodityId: number;
      readonly qty: bigint | 'maks';
      readonly reserveCoins?: bigint;
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'sell';
      readonly commodityId: number;
      readonly qty: bigint | 'semua' | 'maks';
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'sail';
      readonly destPortId: number;
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'wait';
    }
  | {
      readonly ruleName?: string;
      readonly detail?: string;
      readonly type: 'skip';
      readonly skipCode: RuleRuntimeErrorCode;
    };

export interface WorldPlayerState {
  id: bigint;
  coins: bigint;
  initialCoins: bigint;
  ledgerSum: bigint;
  lastRescueTick: number | null;
  rescueCount: number;
}

export interface WorldPortState {
  id: number;
  code: string;
  name: string;
  treasury: bigint;
  initialTreasury: bigint;
}

export interface WorldShipState {
  id: bigint;
  playerId: bigint;
  capacity: number;
  status: ShipStatus;
  portId: number;
  destPort: number | null;
  arriveTick: number | null;
  cargo: Map<number, bigint>;
}

export interface WorldState {
  tickNo: number;
  players: Map<bigint, WorldPlayerState>;
  ports: Map<number, WorldPortState>;
  markets: Map<string, MarketRow>;
  ships: Map<bigint, WorldShipState>;
  cumulativeUpkeepSink: bigint;
  cumulativeSource: bigint;
  stateHash: string;
}

export interface TickActionEvent {
  readonly shipId: bigint;
  readonly playerId: bigint;
  readonly tickNo: number;
  readonly ruleName: string;
  readonly actionType: 'buy' | 'sell' | 'sail' | 'wait' | 'skip';
  readonly result: 'ok' | 'gagal' | 'dilewati' | 'menunggu' | 'berlayar';
  readonly failureCode?: RuleActionFailureCode;
  readonly detail?: string;
  readonly commodityId?: number;
  readonly portId: number;
  readonly destPortId?: number;
  readonly executedQty?: bigint;
  readonly grossValue?: bigint;
  readonly fee?: bigint;
  readonly netPlayerDelta?: bigint;
}

export interface TickEvents {
  readonly tickNo: number;
  readonly actionEvents: readonly TickActionEvent[];
  readonly upkeepPaidTotal: bigint;
  readonly portIncomeAddedTotal: bigint;
  readonly portProducerPayoutTotal: bigint;
  readonly rescueGrantedCount: number;
  readonly rescueCoinsAddedTotal: bigint;
  readonly invariantCheck: InvariantCheckResult;
}

export type ShipRuleDecider = (
  ship: Readonly<WorldShipState>,
  player: Readonly<WorldPlayerState>,
  state: Readonly<WorldState>,
) => Iterable<CandidateAction>;

const COMMODITIES_BY_ID = new Map(COMMODITIES_SEED.map((c) => [c.id, c]));

// Precompute shortest-path hop & ticks across ROUTES_SEED
const SHORTEST_DIST = new Map<string, number>();
const NEXT_HOP = new Map<string, number>();
const DIRECT_ROUTES = new Map<string, number>();

function initRouteTables(): void {
  const portIds = [1, 2, 3, 4, 5, 6];
  for (const p1 of portIds) {
    for (const p2 of portIds) {
      const k = `${p1}:${p2}`;
      SHORTEST_DIST.set(k, p1 === p2 ? 0 : 999);
      NEXT_HOP.set(k, p1);
    }
  }
  for (const r of ROUTES_SEED) {
    const k = `${r.from_port}:${r.to_port}`;
    SHORTEST_DIST.set(k, r.ticks);
    NEXT_HOP.set(k, r.to_port);
    DIRECT_ROUTES.set(k, r.ticks);
  }
  for (const kPort of portIds) {
    for (const iPort of portIds) {
      for (const jPort of portIds) {
        const ik = SHORTEST_DIST.get(`${iPort}:${kPort}`) ?? 999;
        const kj = SHORTEST_DIST.get(`${kPort}:${jPort}`) ?? 999;
        const ij = SHORTEST_DIST.get(`${iPort}:${jPort}`) ?? 999;
        if (ik + kj < ij) {
          SHORTEST_DIST.set(`${iPort}:${jPort}`, ik + kj);
          const hop = NEXT_HOP.get(`${iPort}:${kPort}`) ?? kPort;
          NEXT_HOP.set(`${iPort}:${jPort}`, hop);
        }
      }
    }
  }
}
initRouteTables();

export function getShortestDistanceTicks(
  fromPort: number,
  toPort: number,
): number | null {
  const d = SHORTEST_DIST.get(`${fromPort}:${toPort}`);
  if (d === undefined || d >= 999) return null;
  return d;
}

export function getNextHopPort(
  fromPort: number,
  targetPort: number,
): { hopPortId: number; hopTicks: number } | null {
  if (fromPort === targetPort) return null;
  const hop = NEXT_HOP.get(`${fromPort}:${targetPort}`);
  if (hop === undefined || hop === fromPort) return null;
  const ticks = DIRECT_ROUTES.get(`${fromPort}:${hop}`);
  if (ticks === undefined) return null;
  return { hopPortId: hop, hopTicks: ticks };
}

export function getShipTotalCargo(cargo: ReadonlyMap<number, bigint>): bigint {
  let sum = 0n;
  for (const qty of cargo.values()) {
    sum += qty;
  }
  return sum;
}

/**
 * Menghitung state_hash kanonik sesuai docs/09 v0.2:
 * SHA-256 dari JSON kanonik dengan kunci & array terurut tetap, semua bigint sebagai string.
 */
export function computeCanonicalStateHash(state: Readonly<WorldState>): string {
  const sortedPorts = Array.from(state.ports.values())
    .sort((a, b) => a.id - b.id)
    .map((p) => ({
      id: p.id,
      initialTreasury: p.initialTreasury.toString(),
      treasury: p.treasury.toString(),
    }));

  const sortedMarkets = Array.from(state.markets.values())
    .sort((a, b) =>
      a.port_id !== b.port_id
        ? a.port_id - b.port_id
        : a.commodity_id - b.commodity_id,
    )
    .map((m) => ({
      commodityId: m.commodity_id,
      portId: m.port_id,
      price: m.price.toString(),
      stock: m.stock.toString(),
    }));

  const sortedPlayers = Array.from(state.players.values())
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((pl) => ({
      coins: pl.coins.toString(),
      id: pl.id.toString(),
      lastRescueTick: pl.lastRescueTick,
      rescueCount: pl.rescueCount,
    }));

  const sortedShips = Array.from(state.ships.values())
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((s) => ({
      arriveTick: s.arriveTick,
      cargo: [1, 2, 3, 4].map((cid) => [
        cid,
        (s.cargo.get(cid) ?? 0n).toString(),
      ]),
      destPort: s.destPort,
      id: s.id.toString(),
      playerId: s.playerId.toString(),
      portId: s.portId,
      status: s.status,
    }));

  const canonicalObj = {
    cumulativeSource: state.cumulativeSource.toString(),
    cumulativeUpkeepSink: state.cumulativeUpkeepSink.toString(),
    markets: sortedMarkets,
    players: sortedPlayers,
    ports: sortedPorts,
    ships: sortedShips,
    tickNo: state.tickNo,
  };

  return crypto
    .createHash('sha256')
    .update(JSON.stringify(canonicalObj))
    .digest('hex');
}

/**
 * Satu implementasi murni logika tick dunia (docs/03 & docs/09 v0.2).
 */
export function stepWorld(
  state: WorldState,
  decideShipActions: ShipRuleDecider,
  config: WorldEconomyConfig = WORLD_CONFIG,
  worldSeed: number = 1,
  computeHash: boolean = true,
): { state: WorldState; events: TickEvents } {
  const t = state.tickNo + 1;
  state.tickNo = t;

  let upkeepPaidTotal = 0n;
  let portIncomeAddedTotal = 0n;
  let portProducerPayoutTotal = 0n;
  let rescueGrantedCount = 0;
  let rescueCoinsAddedTotal = 0n;
  const actionEvents: TickActionEvent[] = [];

  // Hitung jumlah kapal aktif untuk penskalaan opsional pasar (SCALE_MARKET_WITH_FLEET)
  const fleetSize = state.ships.size;

  // Guncangan permintaan terjadwal deterministik (zero-sum antar pelabuhan pada komoditas yang dipilih)
  let shockCommodityId = 0;
  let shockHighDemandPortId = 0;
  let shockHarvestPortId = 0;
  if (
    config.DEMAND_SHOCK_ENABLED &&
    config.DEMAND_SHOCK_INTERVAL_TICKS > 0 &&
    config.DEMAND_SHOCK_MAGNITUDE > 0n
  ) {
    const epoch = Math.floor(t / config.DEMAND_SHOCK_INTERVAL_TICKS);
    const h = Math.imul(epoch ^ (worldSeed * 2654435761), 1597334677) >>> 0;
    shockCommodityId = (h % 4) + 1;
    shockHighDemandPortId = ((h >>> 4) % 6) + 1;
    shockHarvestPortId = ((shockHighDemandPortId + ((h >>> 8) % 5)) % 6) + 1;
  }

  // Langkah 2: Produksi dan konsumsi per (pelabuhan, komoditas) + hitungHarga murni
  const domesticConsumptionValueByPort = new Map<number, bigint>();
  const domesticProductionValueByPort = new Map<number, bigint>();

  for (const [mKey, m] of state.markets.entries()) {
    const com = COMMODITIES_BY_ID.get(m.commodity_id);
    if (!com) continue;

    let effectiveProd = m.production;
    let effectiveCons = m.consumption;

    if (config.DEMAND_SHOCK_ENABLED && m.commodity_id === shockCommodityId) {
      if (m.port_id === shockHighDemandPortId) {
        effectiveCons += config.DEMAND_SHOCK_MAGNITUDE;
      } else if (m.port_id === shockHarvestPortId) {
        effectiveProd += config.DEMAND_SHOCK_MAGNITUDE;
      }
    }

    // Jika SCALE_MARKET_WITH_FLEET aktif, peredam perdagangan pesisir/karavan domestik
    // menyerap sebagian surplus ekstrem (stok > target + 220) dan memasok darurat saat langka (stok < 140)
    // sehingga pasar stabil di seluruh ukuran armada (10, 25, 50, 100 kapal) tanpa menempel di batas clamp.
    if (config.SCALE_MARKET_WITH_FLEET) {
      if (fleetSize > 50) {
        const scaleNum = BigInt(fleetSize);
        effectiveProd = (effectiveProd * scaleNum) / 50n;
        effectiveCons = (effectiveCons * scaleNum) / 50n;
      }
      const upperThreshold = m.target + 220n;
      const lowerThreshold = 140n;
      if (m.stock > upperThreshold) {
        const caravanExport = (m.stock - upperThreshold) / 6n + 1n;
        effectiveCons += caravanExport;
      } else if (m.stock < lowerThreshold) {
        const caravanImport = (lowerThreshold - m.stock) / 5n + 2n;
        effectiveProd += caravanImport;
      }
    }

    const rowWithEffectiveRates: MarketRow = {
      ...m,
      production: effectiveProd,
      consumption: effectiveCons,
    };

    const updated = stepProduksiKonsumsi(
      rowWithEffectiveRates,
      com.base_price,
      config,
    );
    // Kembalikan laju dasar pada objek pasar agar definisi pasar tidak berubah permanen
    updated.production = m.production;
    updated.consumption = m.consumption;
    state.markets.set(mKey, updated);

    const afterProd = m.stock + effectiveProd;
    const actualConsumed =
      effectiveCons < afterProd ? effectiveCons : afterProd;
    const actualProduced =
      afterProd <= m.capacity
        ? effectiveProd
        : m.capacity > m.stock
          ? m.capacity - m.stock
          : 0n;

    domesticConsumptionValueByPort.set(
      m.port_id,
      (domesticConsumptionValueByPort.get(m.port_id) ?? 0n) +
        actualConsumed * com.base_price,
    );
    domesticProductionValueByPort.set(
      m.port_id,
      (domesticProductionValueByPort.get(m.port_id) ?? 0n) +
        actualProduced * com.base_price,
    );
  }

  // Langkah 3: Pendapatan pelabuhan & Kliring Domestik (ADR-010, docs/09 v0.2 langkah 3)
  if (config.PORT_INCOME_ENABLED) {
    const divisor =
      config.PORT_TREASURY_RESTORE_DIVISOR > 0n
        ? config.PORT_TREASURY_RESTORE_DIVISOR
        : 20n;

    for (const port of state.ports.values()) {
      const consVal = domesticConsumptionValueByPort.get(port.id) ?? 0n;
      const prodVal = domesticProductionValueByPort.get(port.id) ?? 0n;
      const netDomestic = consVal - prodVal;
      const targetGap =
        (config.INITIAL_PORT_TREASURY - port.treasury) / divisor;
      const desiredDelta = netDomestic + targetGap;

      if (desiredDelta > 0n) {
        port.treasury += desiredDelta;
        state.cumulativeSource += desiredDelta;
        portIncomeAddedTotal += desiredDelta;
      } else if (desiredDelta < 0n) {
        const wantedOutflow = -desiredDelta;
        const maxOutflow =
          port.treasury > config.PORT_TREASURY_FLOOR
            ? port.treasury - config.PORT_TREASURY_FLOOR
            : 0n;
        const actualOutflow =
          wantedOutflow < maxOutflow ? wantedOutflow : maxOutflow;
        if (actualOutflow > 0n) {
          port.treasury -= actualOutflow;
          state.cumulativeUpkeepSink += actualOutflow;
          portProducerPayoutTotal += actualOutflow;
        }
      }
    }
  }

  // Langkah 4: Kedatangan kapal yang selesai berlayar (arrive_tick <= t)
  for (const ship of state.ships.values()) {
    if (
      ship.status === 'sailing' &&
      ship.arriveTick !== null &&
      ship.arriveTick <= t &&
      ship.destPort !== null
    ) {
      ship.status = 'docked';
      ship.portId = ship.destPort;
      ship.destPort = null;
      ship.arriveTick = null;
    }
  }

  // Langkah 5: Perawatan kapal (SEBELUM aksi), urutan ship_id naik (docs/09 v0.2 langkah 5)
  const sortedShipsAsc = Array.from(state.ships.values()).sort((a, b) =>
    a.id < b.id ? -1 : a.id > b.id ? 1 : 0,
  );

  for (const ship of sortedShipsAsc) {
    const player = state.players.get(ship.playerId);
    if (!player) continue;

    const wealthSurcharge =
      config.WEALTH_UPKEEP_BPS > 0 && player.coins > config.STARTER_COINS
        ? ((player.coins - config.STARTER_COINS) *
            BigInt(config.WEALTH_UPKEEP_BPS)) /
          10000n
        : 0n;
    const upkeepDue = config.UPKEEP_PER_TICK + wealthSurcharge;

    if (ship.status === 'docked' || ship.status === 'sailing') {
      if (player.coins >= upkeepDue) {
        player.coins -= upkeepDue;
        player.ledgerSum -= upkeepDue;
        state.cumulativeUpkeepSink += upkeepDue;
        upkeepPaidTotal += upkeepDue;
      } else {
        // Tunggakan tidak diakumulasi; kapal docked menjadi grounded, kapal sailing tetap berlayar
        if (ship.status === 'docked') {
          ship.status = 'grounded';
        }
      }
    } else if (ship.status === 'grounded') {
      // Kapal grounded tidak ditagih jika koin kurang; jika cukup, bayar dan kembali docked pada tick yang sama
      if (player.coins >= upkeepDue) {
        player.coins -= upkeepDue;
        player.ledgerSum -= upkeepDue;
        state.cumulativeUpkeepSink += upkeepDue;
        upkeepPaidTotal += upkeepDue;
        ship.status = 'docked';
      }
    }
  }

  // Langkah 6: Evaluasi aturan per kapal docked atau grounded, urutan adil (diputar t mod N)
  const evaluableShips = sortedShipsAsc.filter(
    (s) => s.status === 'docked' || s.status === 'grounded',
  );
  const nEval = evaluableShips.length;
  const rotatedShips: WorldShipState[] = [];
  if (nEval > 0) {
    const offset = t % nEval;
    for (let i = 0; i < nEval; i++) {
      const sh = evaluableShips[(i + offset) % nEval];
      if (sh) rotatedShips.push(sh);
    }
  }

  for (const ship of rotatedShips) {
    const player = state.players.get(ship.playerId);
    if (!player) continue;
    const portId = ship.portId;
    const port = state.ports.get(portId);
    if (!port) continue;

    const candidateIterable = decideShipActions(ship, player, state);
    let anySucceeded = false;
    let idx = 0;

    for (const act of candidateIterable) {
      if (idx >= 16) break;
      idx += 1;
      const ruleName = act.ruleName ?? `aturan_${idx}`;

      if (act.type === 'skip') {
        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: 'skip',
          result: 'dilewati',
          failureCode: act.skipCode,
          ...(act.detail !== undefined ? { detail: act.detail } : {}),
          portId,
        });
        continue;
      }

      // Kapal grounded hanya boleh 'sell' (jual) dan 'wait' (tunggu) (docs/05 & docs/09 v0.2)
      if (
        ship.status === 'grounded' &&
        act.type !== 'sell' &&
        act.type !== 'wait'
      ) {
        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: act.type,
          result: 'gagal',
          failureCode: 'GROUNDED',
          portId,
        });
        continue;
      }

      if (act.type === 'wait') {
        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: 'wait',
          result: 'menunggu',
          portId,
        });
        anySucceeded = true;
        break;
      }

      if (act.type === 'buy') {
        const mKey = `${portId}:${act.commodityId}`;
        const m = state.markets.get(mKey);
        const com = COMMODITIES_BY_ID.get(act.commodityId);
        if (!m || !com) continue;

        const reserve = act.reserveCoins ?? 0n;
        const usableCoins =
          player.coins > reserve ? player.coins - reserve : 0n;
        const heldQty = ship.cargo.get(act.commodityId) ?? 0n;
        const totalCargo = getShipTotalCargo(ship.cargo);

        const buyRes = eksekusiBeli({
          stock: m.stock,
          target: m.target,
          basePrice: com.base_price,
          capacity: m.capacity,
          playerCoins: usableCoins,
          shipCargoQty: heldQty,
          shipTotalCargo: totalCargo,
          shipCapacity: ship.capacity,
          portTreasury: port.treasury,
          requestedQty: act.qty,
          config,
        });

        if (!buyRes.ok) {
          actionEvents.push({
            shipId: ship.id,
            playerId: player.id,
            tickNo: t,
            ruleName,
            actionType: 'buy',
            result: 'gagal',
            ...(buyRes.code !== undefined ? { failureCode: buyRes.code } : {}),
            commodityId: act.commodityId,
            portId,
          });
          // Jatuh ke aturan berikutnya pada tick yang sama (docs/05 v0.2)
          continue;
        }

        m.stock = buyRes.newStock;
        m.price = buyRes.newPrice;
        port.treasury = buyRes.newPortTreasury;
        player.coins += buyRes.netPlayerDelta;
        player.ledgerSum += buyRes.netPlayerDelta;
        ship.cargo.set(act.commodityId, buyRes.newShipCargoQty);

        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: 'buy',
          result: 'ok',
          commodityId: act.commodityId,
          portId,
          executedQty: buyRes.executedQty,
          grossValue: buyRes.grossValue,
          fee: buyRes.fee,
          netPlayerDelta: buyRes.netPlayerDelta,
        });
        anySucceeded = true;
        break;
      }

      if (act.type === 'sell') {
        const mKey = `${portId}:${act.commodityId}`;
        const m = state.markets.get(mKey);
        const com = COMMODITIES_BY_ID.get(act.commodityId);
        if (!m || !com) continue;

        const heldQty = ship.cargo.get(act.commodityId) ?? 0n;
        const totalCargo = getShipTotalCargo(ship.cargo);

        const sellRes = eksekusiJual({
          stock: m.stock,
          target: m.target,
          basePrice: com.base_price,
          capacity: m.capacity,
          playerCoins: player.coins,
          shipCargoQty: heldQty,
          shipTotalCargo: totalCargo,
          shipCapacity: ship.capacity,
          portTreasury: port.treasury,
          requestedQty: act.qty,
          config,
        });

        if (!sellRes.ok) {
          actionEvents.push({
            shipId: ship.id,
            playerId: player.id,
            tickNo: t,
            ruleName,
            actionType: 'sell',
            result: 'gagal',
            ...(sellRes.code !== undefined
              ? { failureCode: sellRes.code }
              : {}),
            commodityId: act.commodityId,
            portId,
          });
          continue;
        }

        m.stock = sellRes.newStock;
        m.price = sellRes.newPrice;
        port.treasury = sellRes.newPortTreasury;
        player.coins += sellRes.netPlayerDelta;
        player.ledgerSum += sellRes.netPlayerDelta;
        ship.cargo.set(act.commodityId, sellRes.newShipCargoQty);

        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: 'sell',
          result: 'ok',
          commodityId: act.commodityId,
          portId,
          executedQty: sellRes.executedQty,
          grossValue: sellRes.grossValue,
          fee: sellRes.fee,
          netPlayerDelta: sellRes.netPlayerDelta,
        });
        anySucceeded = true;
        break;
      }

      if (act.type === 'sail') {
        if (act.destPortId === portId) {
          actionEvents.push({
            shipId: ship.id,
            playerId: player.id,
            tickNo: t,
            ruleName,
            actionType: 'sail',
            result: 'gagal',
            failureCode: 'SAME_PORT',
            portId,
            destPortId: act.destPortId,
          });
          continue;
        }

        const hop = getNextHopPort(portId, act.destPortId);
        if (!hop) {
          actionEvents.push({
            shipId: ship.id,
            playerId: player.id,
            tickNo: t,
            ruleName,
            actionType: 'sail',
            result: 'gagal',
            failureCode: 'NO_ROUTE',
            portId,
            destPortId: act.destPortId,
          });
          continue;
        }

        ship.status = 'sailing';
        ship.destPort = hop.hopPortId;
        ship.arriveTick = t + hop.hopTicks;

        actionEvents.push({
          shipId: ship.id,
          playerId: player.id,
          tickNo: t,
          ruleName,
          actionType: 'sail',
          result: 'berlayar',
          portId,
          destPortId: hop.hopPortId,
        });
        anySucceeded = true;
        break;
      }
    }

    if (!anySucceeded) {
      actionEvents.push({
        shipId: ship.id,
        playerId: player.id,
        tickNo: t,
        ruleName: 'default_tunggu',
        actionType: 'wait',
        result: 'menunggu',
        portId,
      });
    }
  }

  // Langkah 7: Pemulihan darurat (docs/09 v0.2 langkah 7, di balik flag RESCUE_ENABLED)
  if (config.RESCUE_ENABLED && config.RESCUE_COINS > 0n) {
    for (const ship of sortedShipsAsc) {
      if (ship.status !== 'grounded') continue;
      const totalCargo = getShipTotalCargo(ship.cargo);
      if (totalCargo > 0n) continue;
      const player = state.players.get(ship.playerId);
      if (!player || player.coins >= config.UPKEEP_PER_TICK) continue;

      const cooldownOk =
        player.lastRescueTick === null ||
        t - player.lastRescueTick >= config.RESCUE_COOLDOWN_TICKS;

      if (cooldownOk) {
        player.coins += config.RESCUE_COINS;
        player.ledgerSum += config.RESCUE_COINS;
        player.lastRescueTick = t;
        player.rescueCount += 1;
        state.cumulativeSource += config.RESCUE_COINS;
        rescueGrantedCount += 1;
        rescueCoinsAddedTotal += config.RESCUE_COINS;
      }
    }
  }

  // Langkah 8: Invarian cepat
  const invariantCheck = periksaInvarianEkonomi(
    {
      players: Array.from(state.players.values()).map((pl) => ({
        id: pl.id,
        coins: pl.coins,
        initialCoins: pl.initialCoins,
      })),
      ports: Array.from(state.ports.values()).map((p) => ({
        id: p.id,
        treasury: p.treasury,
        initialTreasury: p.initialTreasury,
      })),
      markets: Array.from(state.markets.values()).map((m) => ({
        portId: m.port_id,
        commodityId: m.commodity_id,
        stock: m.stock,
        target: m.target,
        capacity: m.capacity,
        price: m.price,
        basePrice: COMMODITIES_BY_ID.get(m.commodity_id)?.base_price ?? 1n,
      })),
      ships: Array.from(state.ships.values()).map((s) => ({
        id: s.id,
        playerId: s.playerId,
        capacity: s.capacity,
        cargoByCommodity: s.cargo,
      })),
      ledgerDeltasByPlayer: new Map(
        Array.from(state.players.values()).map((pl) => [pl.id, pl.ledgerSum]),
      ),
      cumulativeUpkeepSink: state.cumulativeUpkeepSink,
      cumulativeSource: state.cumulativeSource,
    },
    config,
  );

  // Langkah 9: Hitung state_hash kanonik
  if (computeHash) {
    state.stateHash = computeCanonicalStateHash(state);
  }

  return {
    state,
    events: {
      tickNo: t,
      actionEvents,
      upkeepPaidTotal,
      portIncomeAddedTotal,
      portProducerPayoutTotal,
      rescueGrantedCount,
      rescueCoinsAddedTotal,
      invariantCheck,
    },
  };
}
