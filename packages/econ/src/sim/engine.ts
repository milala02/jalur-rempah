import {
  COMMODITIES_SEED,
  ROUTES_SEED,
  WORLD_CONFIG,
  WorldEconomyConfig,
  buildPortsSeed,
  buildMarketSeed,
} from '@jalur-rempah/shared';
import { createSeededRng, SeededRng } from '../rng.js';
import { batasHargaAtas, batasHargaBawah } from '../price.js';
import {
  eksekusiBeli,
  eksekusiJual,
  hitungJumlahBeliMaks,
  hitungNilaiKotorJual,
  hitungBiayaPelabuhan,
} from '../trade.js';
import {
  WorldState,
  WorldShipState,
  WorldPlayerState,
  WorldPortState,
  CandidateAction,
  stepWorld,
  getShortestDistanceTicks,
  getShipTotalCargo,
  computeCanonicalStateHash,
} from '../step-world.js';
import {
  BotStrategyName,
  SimulationOptions,
  SimulationResult,
  CommodityMetrics,
  StrategyMetrics,
  RouteMarginMetrics,
  PortTreasuryStats,
  TimeSeriesSample,
} from './types.js';

const STRATEGIES: readonly BotStrategyName[] = [
  'adversarial',
  'naive',
  'margin_hunter',
  'hoarder',
  'random',
] as const;

interface BotMeta {
  readonly id: bigint;
  readonly strategy: BotStrategyName;
  targetPortId: number | null;
  firstDoubledTick: number | null;
  tradesCompleted: number;
  totalNetTradeProfit: bigint;
  lastBuyByCommodity: Map<
    number,
    { portId: number; costPaid: bigint; unitCost: bigint }
  >;
}

interface PriceAcc {
  count: number;
  sum: number;
  sumSq: number;
  minObserved: bigint;
  maxObserved: bigint;
  atLowerBoundCount: number;
  atUpperBoundCount: number;
}

interface PortAcc {
  code: string;
  initialTreasury: bigint;
  minTreasury: bigint;
  minTreasuryTick: number;
  maxTreasury: bigint;
  sumTreasury: number;
  count: number;
  firstZeroTick: number | null;
}

interface RouteAcc {
  fromPort: string;
  toPort: string;
  ticks: number;
  trips: number;
  totalNetProfit: bigint;
}

function computeGini(values: readonly number[]): number {
  if (values.length <= 1) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  let total = 0;
  for (const v of sorted) total += v;
  if (total <= 0) return 0;

  let weightedSum = 0;
  for (let i = 0; i < n; i++) {
    const val = sorted[i] ?? 0;
    weightedSum += (2 * (i + 1) - n - 1) * val;
  }
  return Number((weightedSum / (n * total)).toFixed(4));
}

export function runEconomySimulation(
  options: SimulationOptions,
): SimulationResult {
  const config: WorldEconomyConfig = options.config ?? WORLD_CONFIG;
  const rng: SeededRng = createSeededRng(options.seed);

  const portsSeed = buildPortsSeed(config);
  const ports = new Map<number, WorldPortState>();
  const portAccById = new Map<number, PortAcc>();

  for (const p of portsSeed) {
    ports.set(p.id, {
      id: p.id,
      code: p.code,
      name: p.name,
      treasury: p.treasury,
      initialTreasury: p.initial_treasury,
    });
    portAccById.set(p.id, {
      code: p.code,
      initialTreasury: p.initial_treasury,
      minTreasury: p.treasury,
      minTreasuryTick: 0,
      maxTreasury: p.treasury,
      sumTreasury: 0,
      count: 0,
      firstZeroTick: p.treasury <= 0n ? 0 : null,
    });
  }

  const commoditiesById = new Map(COMMODITIES_SEED.map((c) => [c.id, c]));
  const neighborsByPort = new Map<
    number,
    { toPort: number; ticks: number }[]
  >();
  for (const r of ROUTES_SEED) {
    const list = neighborsByPort.get(r.from_port) ?? [];
    list.push({ toPort: r.to_port, ticks: r.ticks });
    neighborsByPort.set(r.from_port, list);
  }

  const marketSeed = buildMarketSeed(config);
  const markets = new Map<string, (typeof marketSeed)[number]>();
  for (const m of marketSeed) {
    markets.set(`${m.port_id}:${m.commodity_id}`, { ...m });
  }

  const players = new Map<bigint, WorldPlayerState>();
  const ships = new Map<bigint, WorldShipState>();
  const botMetaById = new Map<bigint, BotMeta>();

  for (let i = 0; i < options.bots; i++) {
    const id = BigInt(i + 1);
    const strategy =
      STRATEGIES[i % STRATEGIES.length] ?? ('naive' as BotStrategyName);
    const startPortId = (i % portsSeed.length) + 1;
    const cargo = new Map<number, bigint>();
    for (const c of COMMODITIES_SEED) {
      cargo.set(c.id, 0n);
    }

    players.set(id, {
      id,
      coins: config.STARTER_COINS,
      initialCoins: config.STARTER_COINS,
      ledgerSum: config.STARTER_COINS,
      lastRescueTick: null,
      rescueCount: 0,
    });

    ships.set(id, {
      id,
      playerId: id,
      capacity: config.STARTER_SHIP_CAPACITY,
      status: 'docked',
      portId: startPortId,
      destPort: null,
      arriveTick: null,
      cargo,
    });

    botMetaById.set(id, {
      id,
      strategy,
      targetPortId: null,
      firstDoubledTick: null,
      tradesCompleted: 0,
      totalNetTradeProfit: 0n,
      lastBuyByCommodity: new Map(),
    });
  }

  const worldState: WorldState = {
    tickNo: 0,
    players,
    ports,
    markets,
    ships,
    cumulativeUpkeepSink: 0n,
    cumulativeSource: 0n,
    stateHash: '',
  };
  worldState.stateHash = computeCanonicalStateHash(worldState);

  const priceAccByCom = new Map<number, PriceAcc>();
  for (const c of COMMODITIES_SEED) {
    priceAccByCom.set(c.id, {
      count: 0,
      sum: 0,
      sumSq: 0,
      minObserved: 1_000_000n,
      maxObserved: 0n,
      atLowerBoundCount: 0,
      atUpperBoundCount: 0,
    });
  }

  const routeAccByKey = new Map<string, RouteAcc>();
  for (const p1 of portsSeed) {
    for (const p2 of portsSeed) {
      if (p1.id === p2.id) continue;
      const d = getShortestDistanceTicks(p1.id, p2.id) ?? 1;
      const key = `${p1.code}->${p2.code}`;
      routeAccByKey.set(key, {
        fromPort: p1.code,
        toPort: p2.code,
        ticks: d,
        trips: 0,
        totalNetProfit: 0n,
      });
    }
  }

  let cycleAttempts = 0;
  let roundingAttempts = 0;
  let pumpDumpAttempts = 0;
  let rescueFarmingAttempts = 0;
  let profitableExploitsFound = 0;
  let bestCycleNetDelta: bigint | null = null;
  let worstCycleNetDelta: bigint | null = null;

  let cumulativePortIncomeSource = 0n;
  let cumulativeRescueSource = 0n;
  let cumulativeShipUpkeepSink = 0n;
  let cumulativePortProducerPayoutSink = 0n;
  let rescueGrantedTotal = 0;

  let invariantViolations = 0;
  const invariantViolationDetails: string[] = [];

  const sampleCountTarget = options.sampleCount ?? 40;
  const sampleInterval = Math.max(
    1,
    Math.floor(options.ticks / sampleCountTarget),
  );
  const timeSeriesSamples: TimeSeriesSample[] = [];
  let q3CoinsSum = 0;
  let q3CoinsCount = 0;
  let q4CoinsSum = 0;
  let q4CoinsCount = 0;

  // Fungsi pembuat keputusan kandidat aturan per kapal (dipanggil oleh stepWorld)
  const decideShipActions = (
    ship: Readonly<WorldShipState>,
    player: Readonly<WorldPlayerState>,
    state: Readonly<WorldState>,
  ): readonly CandidateAction[] => {
    const meta = botMetaById.get(ship.id);
    if (!meta) return [{ type: 'wait', ruleName: 'no_meta' }];
    const portId = ship.portId;
    const port = state.ports.get(portId);
    if (!port) return [{ type: 'wait', ruleName: 'no_port' }];
    const neighbors = neighborsByPort.get(portId) ?? [];

    // Jika kapal grounded: hanya jual muatan jika ada, atau tunggu (menguji aturan grounded di stepWorld)
    if (ship.status === 'grounded') {
      const actions: CandidateAction[] = [];
      for (const com of COMMODITIES_SEED) {
        const held = ship.cargo.get(com.id) ?? 0n;
        if (held > 0n) {
          actions.push({
            ruleName: 'jual_darurat_grounded',
            type: 'sell',
            commodityId: com.id,
            qty: 'semua',
          });
        }
      }
      actions.push({ ruleName: 'tunggu_grounded', type: 'wait' });
      return actions;
    }

    // Jika bot adalah adversarial: jalankan audit eksploit terlebih dahulu
    if (meta.strategy === 'adversarial' && (state.tickNo + Number(ship.id)) % 5 === 0) {
      // Uji 4: Rescue Farming Exploit Check (apakah sengaja bangkrut untuk RESCUE_COINS = 200 per 2880 tick menguntungkan?)
      rescueFarmingAttempts += 1;
      const rescueRatePerTick =
        config.RESCUE_ENABLED && config.RESCUE_COOLDOWN_TICKS > 0
          ? Number(config.RESCUE_COINS) / config.RESCUE_COOLDOWN_TICKS
          : 0;
      if (rescueRatePerTick > Number(config.UPKEEP_PER_TICK)) {
        profitableExploitsFound += 1;
      }

      for (const com of COMMODITIES_SEED) {
        const m = state.markets.get(`${portId}:${com.id}`);
        if (!m || m.stock <= 0n) continue;

        for (const testQty of [1n, 5n, 15n]) {
          if (m.stock < testQty) continue;
          const simBuy = eksekusiBeli({
            stock: m.stock,
            target: m.target,
            basePrice: com.base_price,
            capacity: m.capacity,
            playerCoins: 1_000_000n,
            shipCargoQty: 0n,
            shipTotalCargo: 0n,
            shipCapacity: 500,
            portTreasury: port.treasury + 1_000_000n,
            requestedQty: testQty,
            config,
          });
          if (simBuy.ok) {
            const simSell = eksekusiJual({
              stock: simBuy.newStock,
              target: m.target,
              basePrice: com.base_price,
              capacity: m.capacity,
              playerCoins: simBuy.newPlayerCoins,
              shipCargoQty: simBuy.newShipCargoQty,
              shipTotalCargo: simBuy.newShipCargoQty,
              shipCapacity: 500,
              portTreasury: simBuy.newPortTreasury,
              requestedQty: testQty,
              config,
            });
            if (simSell.ok) {
              cycleAttempts++;
              if (testQty === 1n) roundingAttempts++;
              const netDelta = simSell.newPlayerCoins - 1_000_000n;
              if (bestCycleNetDelta === null || netDelta > bestCycleNetDelta) {
                bestCycleNetDelta = netDelta;
              }
              if (
                worstCycleNetDelta === null ||
                netDelta < worstCycleNetDelta
              ) {
                worstCycleNetDelta = netDelta;
              }
              if (netDelta > 0n) {
                profitableExploitsFound++;
              }
            }
          }
        }

        if (m.stock >= 3n) {
          pumpDumpAttempts++;
          let s = m.stock;
          let c = 1_000_000n;
          let tr = port.treasury + 1_000_000n;
          let held = 0n;
          let allOk = true;
          for (let step = 0; step < 3; step++) {
            const bStep = eksekusiBeli({
              stock: s,
              target: m.target,
              basePrice: com.base_price,
              capacity: m.capacity,
              playerCoins: c,
              shipCargoQty: held,
              shipTotalCargo: held,
              shipCapacity: 500,
              portTreasury: tr,
              requestedQty: 1n,
              config,
            });
            if (!bStep.ok) {
              allOk = false;
              break;
            }
            s = bStep.newStock;
            c = bStep.newPlayerCoins;
            tr = bStep.newPortTreasury;
            held = bStep.newShipCargoQty;
          }
          if (allOk && held === 3n) {
            const dumpRes = eksekusiJual({
              stock: s,
              target: m.target,
              basePrice: com.base_price,
              capacity: m.capacity,
              playerCoins: c,
              shipCargoQty: held,
              shipTotalCargo: held,
              shipCapacity: 500,
              portTreasury: tr,
              requestedQty: 3n,
              config,
            });
            if (dumpRes.ok) {
              const netDelta = dumpRes.newPlayerCoins - 1_000_000n;
              if (bestCycleNetDelta === null || netDelta > bestCycleNetDelta) {
                bestCycleNetDelta = netDelta;
              }
              if (
                worstCycleNetDelta === null ||
                netDelta < worstCycleNetDelta
              ) {
                worstCycleNetDelta = netDelta;
              }
              if (netDelta > 0n) {
                profitableExploitsFound++;
              }
            }
          }
        }
      }
    }

    const totalCargo = getShipTotalCargo(ship.cargo);
    const candidateRules: CandidateAction[] = [];

    // === KASUS 1: SEDANG MEMBAWA MUATAN ===
    if (totalCargo > 0n) {
      // Strategi NAIVE: hanya melihat harga lokal > base_price dan hanya berlayar ke tetangga 1-hop berurutan
      if (meta.strategy === 'naive') {
        for (const com of COMMODITIES_SEED) {
          const held = ship.cargo.get(com.id) ?? 0n;
          if (held <= 0n) continue;
          const m = state.markets.get(`${portId}:${com.id}`);
          if (m && m.price > com.base_price) {
            candidateRules.push({
              ruleName: `naive_jual_${com.code}`,
              type: 'sell',
              commodityId: com.id,
              qty: 'semua',
            });
          }
        }
        const nextNb =
          neighbors[(state.tickNo + Number(ship.id)) % neighbors.length];
        if (nextNb) {
          candidateRules.push({
            ruleName: 'naive_layar_tetangga',
            type: 'sail',
            destPortId: nextNb.toPort,
          });
        }
        return candidateRules;
      }

      // Strategi CERDAS (margin_hunter, hoarder, adversarial) & random
      for (const com of COMMODITIES_SEED) {
        const held = ship.cargo.get(com.id) ?? 0n;
        if (held <= 0n) continue;
        const m = state.markets.get(`${portId}:${com.id}`);
        if (!m) continue;
        const buyInfo = meta.lastBuyByCommodity.get(com.id);
        const minProfitPrice = buyInfo
          ? (buyInfo.unitCost * 114n) / 100n
          : (com.base_price * 110n) / 100n;

        if (
          meta.targetPortId === portId ||
          (m.price >= minProfitPrice && m.stock < m.target)
        ) {
          candidateRules.push({
            ruleName: `jual_${com.code}`,
            type: 'sell',
            commodityId: com.id,
            qty: 'semua',
          });
        }
      }

      // Jika belum sampai di targetPortId (atau jual gagal), berlayar menuju pelabuhan dengan penerimaan bersih tertinggi
      let bestDest = meta.targetPortId;
      if (!bestDest || bestDest === portId) {
        let bestScore = -1_000_000n;
        for (const destP of portsSeed) {
          if (destP.id === portId) continue;
          const dTicks = getShortestDistanceTicks(portId, destP.id) ?? 10;
          let score = 0n;
          for (const com of COMMODITIES_SEED) {
            const qty = ship.cargo.get(com.id) ?? 0n;
            if (qty <= 0n) continue;
            const destM = state.markets.get(`${destP.id}:${com.id}`);
            if (destM) {
              const gross = qty * destM.price;
              const fee = hitungBiayaPelabuhan(gross, config);
              score += gross - fee - BigInt(dTicks) * 3n;
            }
          }
          if (score > bestScore) {
            bestScore = score;
            bestDest = destP.id;
          }
        }
        meta.targetPortId = bestDest ?? null;
      }

      if (meta.targetPortId && meta.targetPortId !== portId) {
        candidateRules.push({
          ruleName: 'berlayar_ke_tujuan_jual',
          type: 'sail',
          destPortId: meta.targetPortId,
        });
      }
      return candidateRules;
    }

    // === KASUS 2: MUATAN KOSONG ===
    // 2A. Strategi NAIVE: beli ukuran tetap kecil (12 unit) jika harga < base_price tanpa hitung slippage/backhaul
    if (meta.strategy === 'naive') {
      for (const com of COMMODITIES_SEED) {
        const m = state.markets.get(`${portId}:${com.id}`);
        if (m && m.price < com.base_price && m.stock >= 10n) {
          candidateRules.push({
            ruleName: `naive_beli_${com.code}`,
            type: 'buy',
            commodityId: com.id,
            qty: 10n,
            reserveCoins: 15n,
          });
        }
      }
      const nextNb =
        neighbors[(state.tickNo + Number(ship.id)) % neighbors.length];
      if (nextNb) {
        candidateRules.push({
          ruleName: 'naive_cari_pelabuhan',
          type: 'sail',
          destPortId: nextNb.toPort,
        });
      }
      return candidateRules;
    }

    // 2B. Strategi RANDOM: pilih acak dengan RNG ber-seed
    if (meta.strategy === 'random') {
      if (rng.nextInt(0, 2) === 0) {
        const com = COMMODITIES_SEED[rng.nextInt(0, COMMODITIES_SEED.length - 1)];
        if (com) {
          candidateRules.push({
            ruleName: `random_beli_${com.code}`,
            type: 'buy',
            commodityId: com.id,
            qty: 15n,
            reserveCoins: 20n,
          });
        }
      }
      if (neighbors.length > 0) {
        const nb = neighbors[rng.nextInt(0, neighbors.length - 1)];
        if (nb) {
          candidateRules.push({
            ruleName: 'random_layar',
            type: 'sail',
            destPortId: nb.toPort,
          });
        }
      }
      return candidateRules;
    }

    // 2C. Strategi CERDAS (margin_hunter, hoarder, adversarial):
    // Evaluasi pasangan (komoditas, pelabuhan_tujuan) menggunakan kalkulasi slippage eksak, backhaul, & anti-kongesti
    const inboundShipsByPort = new Map<number, number>();
    for (const otherShip of state.ships.values()) {
      if (otherShip.id === ship.id) continue;
      const targetP =
        otherShip.status === 'sailing' && otherShip.destPort !== null
          ? otherShip.destPort
          : otherShip.portId;
      inboundShipsByPort.set(
        targetP,
        (inboundShipsByPort.get(targetP) ?? 0) + 1,
      );
    }

    interface SmartOption {
      comId: number;
      destPortId: number;
      score: bigint;
    }
    const smartOptions: SmartOption[] = [];

    const reserveCoins = 20n;
    const usableCoins =
      player.coins > reserveCoins ? player.coins - reserveCoins : 0n;

    for (const com of COMMODITIES_SEED) {
      const m = state.markets.get(`${portId}:${com.id}`);
      if (!m || m.stock + 10n < m.target || usableCoins <= 0n) continue;

      const maxCapQty = BigInt(ship.capacity);
      const availStock = m.stock > 10n ? m.stock - 10n : m.stock;
      const estUnitBuy = m.price > 0n ? m.price : 1n;
      const affordableQty = usableCoins / (estUnitBuy + 2n);
      const estQty =
        availStock < maxCapQty
          ? availStock < affordableQty
            ? availStock
            : affordableQty
          : maxCapQty < affordableQty
            ? maxCapQty
            : affordableQty;
      if (estQty <= 0n) continue;

      const estGrossBuy = estQty * m.price;
      const estBuyCost = estGrossBuy + hitungBiayaPelabuhan(estGrossBuy, config);

      for (const destP of portsSeed) {
        if (destP.id === portId) continue;
        const destM = state.markets.get(`${destP.id}:${com.id}`);
        const destPortState = state.ports.get(destP.id);
        if (!destM || !destPortState || destPortState.treasury <= 500n) {
          continue;
        }

        const estGrossSell = estQty * destM.price;
        const sellFee = hitungBiayaPelabuhan(estGrossSell, config);
        const netSell = estGrossSell - sellFee;
        if (netSell > destPortState.treasury) continue;

        const netProfit = netSell - estBuyCost;
        if (netProfit <= 15n) continue;

        const dTicks = getShortestDistanceTicks(portId, destP.id) ?? 10;

        // Periksa potensi backhaul (apakah di destP ada komoditas yang surplus untuk dibawa pulang)
        let backhaulBonus = 0n;
        for (const backCom of COMMODITIES_SEED) {
          const bm = state.markets.get(`${destP.id}:${backCom.id}`);
          if (bm && bm.stock > bm.target + 30n) {
            backhaulBonus = 180n;
            break;
          }
        }

        const congestionCount = inboundShipsByPort.get(destP.id) ?? 0;
        const congestionPenalty = BigInt(congestionCount) * 55n;
        const diversityBonus =
          (Number(ship.id) + com.id) % 4 === 0 ? 60n : 0n;

        let score = 0n;
        if (meta.strategy === 'margin_hunter') {
          // Margin bersih per tick + backhaul + anti-kongesti
          score =
            ((netProfit + backhaulBonus + diversityBonus - congestionPenalty) *
              10n) /
            BigInt(dTicks + 2);
        } else if (meta.strategy === 'hoarder') {
          // Hoarder mengincar kelangkaan di pelabuhan tujuan + diskon stok asal
          const discountBonus =
            m.stock > m.target
              ? ((m.stock - m.target) * com.base_price) / 60n
              : 0n;
          score =
            ((netProfit + discountBonus + diversityBonus - congestionPenalty) *
              10n) /
            BigInt(dTicks + 2);
        } else {
          // Adversarial: Arbitrase ROI persentase + anti-kongesti
          const roiBonus = (netProfit * 50n) / com.base_price;
          score =
            ((netProfit + roiBonus + diversityBonus - congestionPenalty) * 9n) /
            BigInt(dTicks + 3);
        }

        if (score > 0n) {
          smartOptions.push({
            comId: com.id,
            destPortId: destP.id,
            score,
          });
        }
      }
    }

    if (smartOptions.length > 0) {
      smartOptions.sort((a, b) =>
        b.score > a.score ? 1 : b.score < a.score ? -1 : 0,
      );
      const best = smartOptions[0];
      if (best) {
        meta.targetPortId = best.destPortId;
        candidateRules.push({
          ruleName: `smart_beli_${best.comId}`,
          type: 'buy',
          commodityId: best.comId,
          qty: 'maks',
          reserveCoins,
        });
      }
    }

    // Fallback aturan ke-2 (menguji mekanisme jatuh ke aturan berikutnya jika beli gagal!):
    // Berlayar ke pelabuhan penghasil terdekat yang memiliki stok surplus tertinggi
    let bestProdPort: number | null = null;
    let bestProdScore = -1_000_000n;
    for (const prodP of portsSeed) {
      if (prodP.id === portId) continue;
      const dTicks = getShortestDistanceTicks(portId, prodP.id) ?? 10;
      let surplus = 0n;
      for (const com of COMMODITIES_SEED) {
        const pm = state.markets.get(`${prodP.id}:${com.id}`);
        if (pm && pm.stock > pm.target) {
          surplus += (pm.stock - pm.target) * com.base_price;
        }
      }
      if (surplus > 0n) {
        const congestion = BigInt(inboundShipsByPort.get(prodP.id) ?? 0) * 800n;
        const sc = surplus / BigInt(dTicks + 1) - congestion;
        if (sc > bestProdScore) {
          bestProdScore = sc;
          bestProdPort = prodP.id;
        }
      }
    }

    if (bestProdPort !== null) {
      candidateRules.push({
        ruleName: 'berlayar_ke_produsen',
        type: 'sail',
        destPortId: bestProdPort,
      });
    }

    return candidateRules;
  };

  // Jalankan simulasi menggunakan stepWorld tunggal
  const q3StartTick = Math.floor(options.ticks * 0.5);
  const q4StartTick = Math.floor(options.ticks * 0.75);

  for (let tick = 1; tick <= options.ticks; tick++) {
    const { events } = stepWorld(
      worldState,
      decideShipActions,
      config,
      options.seed,
      tick === options.ticks,
    );

    cumulativePortIncomeSource += events.portIncomeAddedTotal;
    cumulativeRescueSource += events.rescueCoinsAddedTotal;
    cumulativeShipUpkeepSink += events.upkeepPaidTotal;
    cumulativePortProducerPayoutSink += events.portProducerPayoutTotal;
    rescueGrantedTotal += events.rescueGrantedCount;

    if (!events.invariantCheck.valid) {
      invariantViolations += events.invariantCheck.violations.length;
      for (const v of events.invariantCheck.violations) {
        if (invariantViolationDetails.length < 25) {
          invariantViolationDetails.push(`tick ${tick}: ${v}`);
        }
      }
    }

    // Rekam statistik transaksi per bot & per rute dari events.actionEvents
    for (const ev of events.actionEvents) {
      if (ev.result !== 'ok') continue;
      const meta = botMetaById.get(ev.shipId);
      if (!meta) continue;

      if (
        ev.actionType === 'buy' &&
        ev.commodityId !== undefined &&
        ev.executedQty !== undefined &&
        ev.executedQty > 0n &&
        ev.netPlayerDelta !== undefined
      ) {
        const costPaid = -ev.netPlayerDelta;
        meta.lastBuyByCommodity.set(ev.commodityId, {
          portId: ev.portId,
          costPaid,
          unitCost: costPaid / ev.executedQty,
        });
      } else if (
        ev.actionType === 'sell' &&
        ev.commodityId !== undefined &&
        ev.netPlayerDelta !== undefined
      ) {
        const buyInfo = meta.lastBuyByCommodity.get(ev.commodityId);
        const ship = worldState.ships.get(ev.shipId);
        const remainingQty = ship?.cargo.get(ev.commodityId) ?? 0n;
        if (buyInfo && remainingQty === 0n) {
          const netProfit = ev.netPlayerDelta - buyInfo.costPaid;
          meta.tradesCompleted += 1;
          meta.totalNetTradeProfit += netProfit;

          if (buyInfo.portId !== ev.portId) {
            const fromCode =
              worldState.ports.get(buyInfo.portId)?.code ??
              String(buyInfo.portId);
            const toCode =
              worldState.ports.get(ev.portId)?.code ?? String(ev.portId);
            const rAcc = routeAccByKey.get(`${fromCode}->${toCode}`);
            if (rAcc) {
              rAcc.trips += 1;
              rAcc.totalNetProfit += netProfit;
            }
          }
          meta.lastBuyByCommodity.delete(ev.commodityId);
        }
      }
    }

    // Periksa waktu sampai koin 2x modal awal & hitung total koin pemain
    let currentTotalPlayerCoins = 0n;
    for (const pl of worldState.players.values()) {
      currentTotalPlayerCoins += pl.coins;
      const meta = botMetaById.get(pl.id);
      if (
        meta &&
        meta.firstDoubledTick === null &&
        pl.coins >= pl.initialCoins * 2n
      ) {
        meta.firstDoubledTick = tick;
      }
    }

    if (tick > q3StartTick && tick <= q4StartTick) {
      q3CoinsSum += Number(currentTotalPlayerCoins);
      q3CoinsCount += 1;
    } else if (tick > q4StartTick) {
      q4CoinsSum += Number(currentTotalPlayerCoins);
      q4CoinsCount += 1;
    }

    // Rekam statistik kas pelabuhan setiap tick
    let currentTotalPortTreasury = 0n;
    for (const p of worldState.ports.values()) {
      currentTotalPortTreasury += p.treasury;
      const pAcc = portAccById.get(p.id);
      if (!pAcc) continue;
      pAcc.count += 1;
      pAcc.sumTreasury += Number(p.treasury);
      if (p.treasury < pAcc.minTreasury) {
        pAcc.minTreasury = p.treasury;
        pAcc.minTreasuryTick = tick;
      }
      if (p.treasury > pAcc.maxTreasury) {
        pAcc.maxTreasury = p.treasury;
      }
      if (p.treasury <= 0n && pAcc.firstZeroTick === null) {
        pAcc.firstZeroTick = tick;
      }
    }

    // Rekam statistik harga pasar setiap tick
    for (const m of worldState.markets.values()) {
      const com = commoditiesById.get(m.commodity_id);
      const acc = priceAccByCom.get(m.commodity_id);
      if (!com || !acc) continue;

      const minP = batasHargaBawah(com.base_price, config);
      const maxP = batasHargaAtas(com.base_price, config);
      const pNum = Number(m.price);

      acc.count += 1;
      acc.sum += pNum;
      acc.sumSq += pNum * pNum;
      if (m.price < acc.minObserved) acc.minObserved = m.price;
      if (m.price > acc.maxObserved) acc.maxObserved = m.price;
      if (m.price <= minP) acc.atLowerBoundCount += 1;
      if (m.price >= maxP) acc.atUpperBoundCount += 1;
    }

    // Simpan sampel deret waktu tiap sampleInterval tick (dan di tick terakhir)
    if (tick % sampleInterval === 0 || tick === options.ticks) {
      const portSnap: Record<string, string> = {};
      for (const p of worldState.ports.values()) {
        portSnap[p.code] = p.treasury.toString();
      }
      const meanPriceByCom: Record<string, number> = {};
      for (const com of COMMODITIES_SEED) {
        let sPrice = 0;
        let cnt = 0;
        for (const p of portsSeed) {
          const m = worldState.markets.get(`${p.id}:${com.id}`);
          if (m) {
            sPrice += Number(m.price);
            cnt += 1;
          }
        }
        meanPriceByCom[com.code] =
          cnt > 0 ? Number((sPrice / cnt).toFixed(2)) : 0;
      }

      timeSeriesSamples.push({
        tick,
        totalPlayerCoins: currentTotalPlayerCoins.toString(),
        totalPortTreasury: currentTotalPortTreasury.toString(),
        portTreasuries: portSnap,
        meanPriceByCommodity: meanPriceByCom,
      });
    }
  }

  // Hitung kekayaan bersih akhir tiap bot
  const botWealths = new Map<bigint, bigint>();
  const wealthNumbers: number[] = [];

  for (const pl of worldState.players.values()) {
    const sh = worldState.ships.get(pl.id);
    let cargoVal = 0n;
    if (sh) {
      for (const [comId, qty] of sh.cargo.entries()) {
        const baseP = commoditiesById.get(comId)?.base_price ?? 0n;
        cargoVal += qty * baseP;
      }
    }
    const netWorth = pl.coins + cargoVal;
    botWealths.set(pl.id, netWorth);
    wealthNumbers.push(Number(netWorth));
  }

  const totalBotWealth = Array.from(botWealths.values()).reduce(
    (a, b) => a + b,
    0n,
  );
  const giniWealth = computeGini(wealthNumbers);

  // Metrik per strategi & Gradien Keahlian (A4)
  const strategyMetrics: StrategyMetrics[] = [];
  let maxStrategyWealthSharePct = 0;
  let dominantStrategy: BotStrategyName = 'naive';

  for (const strat of STRATEGIES) {
    const stratBotIds = Array.from(botMetaById.values())
      .filter((bm) => bm.strategy === strat)
      .map((bm) => bm.id);

    let stratWealth = 0n;
    let bankruptCount = 0;
    let tradesCompleted = 0;
    let totalNetTradeProfit = 0n;
    let doubledSum = 0;
    let doubledCount = 0;

    for (const bid of stratBotIds) {
      stratWealth += botWealths.get(bid) ?? 0n;
      const sh = worldState.ships.get(bid);
      if (sh?.status === 'grounded') bankruptCount += 1;
      const bm = botMetaById.get(bid);
      if (bm) {
        tradesCompleted += bm.tradesCompleted;
        totalNetTradeProfit += bm.totalNetTradeProfit;
        if (bm.firstDoubledTick !== null) {
          doubledSum += bm.firstDoubledTick;
          doubledCount += 1;
        }
      }
    }

    const sharePct =
      totalBotWealth > 0n
        ? Number(
            ((Number(stratWealth) / Number(totalBotWealth)) * 100).toFixed(2),
          )
        : 0;
    if (sharePct > maxStrategyWealthSharePct) {
      maxStrategyWealthSharePct = sharePct;
      dominantStrategy = strat;
    }

    const avgWealth =
      stratBotIds.length > 0
        ? Number((Number(stratWealth) / stratBotIds.length).toFixed(2))
        : 0;
    const avgMarginPerTx =
      tradesCompleted > 0
        ? Number((Number(totalNetTradeProfit) / tradesCompleted).toFixed(2))
        : 0;

    strategyMetrics.push({
      strategy: strat,
      botCount: stratBotIds.length,
      totalWealth: stratWealth.toString(),
      avgWealth,
      wealthSharePct: sharePct,
      bankruptCount,
      tradesCompleted,
      avgMarginPerTx,
      avgTicksToDoubleCoins:
        doubledCount > 0 ? Math.round(doubledSum / doubledCount) : null,
    });
  }

  const naiveMetric = strategyMetrics.find((s) => s.strategy === 'naive');
  const naiveAvgWealth = naiveMetric?.avgWealth ?? 1;
  let bestSmartStrategy: BotStrategyName = 'margin_hunter';
  let bestSmartAvgWealth = 0;
  for (const sm of strategyMetrics) {
    if (
      (sm.strategy === 'margin_hunter' ||
        sm.strategy === 'hoarder' ||
        sm.strategy === 'adversarial') &&
      sm.avgWealth > bestSmartAvgWealth
    ) {
      bestSmartAvgWealth = sm.avgWealth;
      bestSmartStrategy = sm.strategy;
    }
  }
  const skillGradientRatio =
    naiveAvgWealth > 0
      ? Number((bestSmartAvgWealth / naiveAvgWealth).toFixed(2))
      : 0;

  // Metrik komoditas & % tick di batas harga
  const commodityMetrics: CommodityMetrics[] = [];
  let totalPriceObs = 0;
  let totalBoundObs = 0;
  let maxCommodityPctTicksAtBounds = 0;

  for (const com of COMMODITIES_SEED) {
    const acc = priceAccByCom.get(com.id);
    if (!acc || acc.count === 0) continue;
    const mean = acc.sum / acc.count;
    const variance = Math.max(0, acc.sumSq / acc.count - mean * mean);
    const stdDev = Math.sqrt(variance);
    const lowerPct = (acc.atLowerBoundCount / acc.count) * 100;
    const upperPct = (acc.atUpperBoundCount / acc.count) * 100;
    const boundsPct = Number(
      (((acc.atLowerBoundCount + acc.atUpperBoundCount) / acc.count) * 100).toFixed(
        2,
      ),
    );

    if (boundsPct > maxCommodityPctTicksAtBounds) {
      maxCommodityPctTicksAtBounds = boundsPct;
    }
    totalPriceObs += acc.count;
    totalBoundObs += acc.atLowerBoundCount + acc.atUpperBoundCount;

    commodityMetrics.push({
      commodityId: com.id,
      code: com.code,
      basePrice: Number(com.base_price),
      minBoundPrice: Number(batasHargaBawah(com.base_price, config)),
      maxBoundPrice: Number(batasHargaAtas(com.base_price, config)),
      meanPrice: Number(mean.toFixed(2)),
      stdDevPrice: Number(stdDev.toFixed(2)),
      volatilityPct: Number(((stdDev / mean) * 100).toFixed(2)),
      minObservedPrice: Number(acc.minObserved),
      maxObservedPrice: Number(acc.maxObserved),
      pctTicksAtLowerBound: Number(lowerPct.toFixed(2)),
      pctTicksAtUpperBound: Number(upperPct.toFixed(2)),
      pctTicksAtBounds: boundsPct,
    });
  }

  const overallPctTicksAtBounds =
    totalPriceObs > 0
      ? Number(((totalBoundObs / totalPriceObs) * 100).toFixed(2))
      : 0;

  // Statistik kas pelabuhan sepanjang simulasi
  const portTreasuries: Record<string, string> = {};
  const portTreasuryStats: Record<string, PortTreasuryStats> = {};
  let minPortTreasuryCoins = 1_000_000_000_000n;
  let minPortTreasuryPort = 'banda';
  let minPortTreasuryTick = 0;

  for (const p of worldState.ports.values()) {
    portTreasuries[p.code] = p.treasury.toString();
    const pAcc = portAccById.get(p.id);
    if (!pAcc) continue;
    if (pAcc.minTreasury < minPortTreasuryCoins) {
      minPortTreasuryCoins = pAcc.minTreasury;
      minPortTreasuryPort = p.code;
      minPortTreasuryTick = pAcc.minTreasuryTick;
    }
    portTreasuryStats[p.code] = {
      portCode: p.code,
      initialTreasury: pAcc.initialTreasury.toString(),
      finalTreasury: p.treasury.toString(),
      minTreasury: pAcc.minTreasury.toString(),
      minTreasuryTick: pAcc.minTreasuryTick,
      maxTreasury: pAcc.maxTreasury.toString(),
      meanTreasury:
        pAcc.count > 0 ? Math.round(pAcc.sumTreasury / pAcc.count) : 0,
      firstZeroTick: pAcc.firstZeroTick,
    };
  }

  // Metrik rute
  const routeMargins: RouteMarginMetrics[] = [];
  for (const [rKey, rAcc] of routeAccByKey.entries()) {
    if (rAcc.trips === 0) continue;
    const avgTrip = Number(rAcc.totalNetProfit) / rAcc.trips;
    routeMargins.push({
      routeKey: rKey,
      fromPort: rAcc.fromPort,
      toPort: rAcc.toPort,
      ticks: rAcc.ticks,
      tripsCompleted: rAcc.trips,
      avgNetProfitPerTrip: Number(avgTrip.toFixed(2)),
      avgNetProfitPerTick: Number((avgTrip / rAcc.ticks).toFixed(2)),
    });
  }

  // Konservasi uang akhir
  const totalInitialPlayerCoins = Array.from(
    worldState.players.values(),
  ).reduce((s, pl) => s + pl.initialCoins, 0n);
  const totalInitialPortTreasury = Array.from(
    worldState.ports.values(),
  ).reduce((s, p) => s + p.initialTreasury, 0n);
  const finalPlayerCoins = Array.from(worldState.players.values()).reduce(
    (s, pl) => s + pl.coins,
    0n,
  );
  const finalPortTreasury = Array.from(worldState.ports.values()).reduce(
    (s, p) => s + p.treasury,
    0n,
  );
  const totalInitialMoney = totalInitialPlayerCoins + totalInitialPortTreasury;
  const lhsTotalAccounted =
    finalPlayerCoins + finalPortTreasury + worldState.cumulativeUpkeepSink;
  const rhsTotalExpected = totalInitialMoney + worldState.cumulativeSource;

  // Stabilitas koin pemain (kuartal 3 vs kuartal 4)
  const q3Mean = q3CoinsCount > 0 ? q3CoinsSum / q3CoinsCount : 0;
  const q4Mean = q4CoinsCount > 0 ? q4CoinsSum / q4CoinsCount : 0;
  const relativeDriftPct =
    q3Mean > 0
      ? Number(((Math.abs(q4Mean - q3Mean) / q3Mean) * 100).toFixed(2))
      : 0;
  const maxAllowedDriftPct = 15;
  const isPlayerCoinsStable =
    options.ticks < 10000 ? true : relativeDriftPct <= maxAllowedDriftPct;

  let bankruptBotCount = 0;
  let permanentlyDeadBotCount = 0;
  for (const sh of worldState.ships.values()) {
    if (sh.status === 'grounded') {
      bankruptBotCount += 1;
      const pl = worldState.players.get(sh.playerId);
      if (
        getShipTotalCargo(sh.cargo) === 0n &&
        (pl?.coins ?? 0n) < config.UPKEEP_PER_TICK
      ) {
        permanentlyDeadBotCount += 1;
      }
    }
  }
  const bankruptBotPct =
    options.bots > 0
      ? Number(((bankruptBotCount / options.bots) * 100).toFixed(2))
      : 0;

  // Evaluasi Gerbang Kualitas M1 (docs/06 & Tugas f)
  const failedGates: string[] = [];
  if (invariantViolations > 0) {
    failedGates.push(`invariantViolations=${invariantViolations} (> 0)`);
  }
  if (lhsTotalAccounted !== rhsTotalExpected) {
    failedGates.push(
      `moneyConservation invalid (${lhsTotalAccounted.toString()} != ${rhsTotalExpected.toString()})`,
    );
  }
  if (profitableExploitsFound > 0) {
    failedGates.push(`profitableExploitsFound=${profitableExploitsFound} (> 0)`);
  }
  if (maxStrategyWealthSharePct > 40) {
    failedGates.push(
      `maxStrategyWealthSharePct=${maxStrategyWealthSharePct}% (> 40%)`,
    );
  }
  for (const cm of commodityMetrics) {
    if (cm.pctTicksAtBounds > 20) {
      failedGates.push(
        `komoditas ${cm.code} pctTicksAtBounds=${cm.pctTicksAtBounds}% (> 20%)`,
      );
    }
    if (cm.stdDevPrice <= 0) {
      failedGates.push(`komoditas ${cm.code} harga konstan (stdDevPrice=0)`);
    }
  }
  if (minPortTreasuryCoins <= 0n) {
    failedGates.push(
      `kas pelabuhan ${minPortTreasuryPort} menyentuh 0 pada tick ${minPortTreasuryTick}`,
    );
  }
  if (bankruptBotPct > 30) {
    failedGates.push(`bankruptBotPct=${bankruptBotPct}% (> 30%)`);
  }
  if (!isPlayerCoinsStable) {
    failedGates.push(
      `total koin pemain tidak stabil (relativeDriftPct=${relativeDriftPct}% > ${maxAllowedDriftPct}%)`,
    );
  }

  return {
    seed: options.seed,
    ticks: options.ticks,
    bots: options.bots,
    stateHash: worldState.stateHash,
    invariantViolations,
    invariantViolationDetails,
    giniWealth,
    bankruptBotCount,
    bankruptBotPct,
    permanentlyDeadBotCount,
    rescueGrantedTotal,
    maxStrategyWealthSharePct,
    dominantStrategy,
    overallPctTicksAtBounds,
    maxCommodityPctTicksAtBounds,
    minPortTreasuryCoins: minPortTreasuryCoins.toString(),
    minPortTreasuryPort,
    minPortTreasuryTick,
    skillGradient: {
      naiveAvgWealth,
      bestSmartStrategy,
      bestSmartAvgWealth,
      skillGradientRatio,
    },
    playerCoinsStability: {
      q3MeanCoins: Number(q3Mean.toFixed(2)),
      q4MeanCoins: Number(q4Mean.toFixed(2)),
      relativeDriftPct,
      maxAllowedDriftPct,
      isStable: isPlayerCoinsStable,
    },
    gates: {
      passed: failedGates.length === 0,
      failedGates,
    },
    moneyConservation: {
      valid: lhsTotalAccounted === rhsTotalExpected,
      totalInitialPlayerCoins: totalInitialPlayerCoins.toString(),
      totalInitialPortTreasury: totalInitialPortTreasury.toString(),
      totalInitialMoney: totalInitialMoney.toString(),
      cumulativeSource: worldState.cumulativeSource.toString(),
      cumulativePortIncomeSource: cumulativePortIncomeSource.toString(),
      cumulativeRescueSource: cumulativeRescueSource.toString(),
      finalPlayerCoins: finalPlayerCoins.toString(),
      finalPortTreasury: finalPortTreasury.toString(),
      cumulativeUpkeepSink: worldState.cumulativeUpkeepSink.toString(),
      cumulativeShipUpkeepSink: cumulativeShipUpkeepSink.toString(),
      cumulativePortProducerPayoutSink:
        cumulativePortProducerPayoutSink.toString(),
      lhsTotalAccounted: lhsTotalAccounted.toString(),
      rhsTotalExpected: rhsTotalExpected.toString(),
    },
    portTreasuries,
    portTreasuryStats,
    commodityMetrics,
    strategyMetrics,
    routeMargins,
    adversarial: {
      cycleAttempts,
      roundingAttempts,
      pumpDumpAttempts,
      rescueFarmingAttempts,
      totalExploitAttempts:
        cycleAttempts + pumpDumpAttempts + rescueFarmingAttempts,
      profitableExploitsFound,
      bestCycleNetDeltaCoins: (bestCycleNetDelta ?? 0n).toString(),
      worstCycleNetDeltaCoins: (worstCycleNetDelta ?? 0n).toString(),
    },
    timeSeriesSamples,
  };
}
