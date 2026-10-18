import crypto from 'node:crypto';
import {
  COMMODITIES_SEED,
  ROUTES_SEED,
  WORLD_CONFIG,
  WorldEconomyConfig,
  ShipStatus,
  buildPortsSeed,
  buildMarketSeed,
} from '@jalur-rempah/shared';
import { createSeededRng, SeededRng } from '../rng.js';
import { batasHargaAtas, batasHargaBawah } from '../price.js';
import { stepProduksiKonsumsi } from '../production.js';
import {
  eksekusiBeli,
  eksekusiJual,
  hitungBiayaPelabuhan,
} from '../trade.js';
import { periksaInvarianEkonomi } from '../invariants.js';
import {
  BotStrategyName,
  SimulationOptions,
  SimulationResult,
  CommodityMetrics,
  StrategyMetrics,
  RouteMarginMetrics,
} from './types.js';

const STRATEGIES: readonly BotStrategyName[] = [
  'adversarial',
  'naive',
  'margin_hunter',
  'hoarder',
  'random',
] as const;

interface SimBotState {
  id: bigint;
  strategy: BotStrategyName;
  coins: bigint;
  initialCoins: bigint;
  ledgerSum: bigint;
  shipId: bigint;
  capacity: number;
  status: ShipStatus;
  portId: number;
  destPort: number | null;
  arriveTick: number | null;
  targetPortId: number | null;
  cargo: Map<number, bigint>;
  lastBuyPortByCommodity: Map<
    number,
    { portId: number; costPaid: bigint; unitPrice: bigint }
  >;
}

interface SimPortState {
  id: number;
  code: string;
  name: string;
  treasury: bigint;
  initialTreasury: bigint;
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

interface RouteAcc {
  fromPort: string;
  toPort: string;
  ticks: number;
  trips: number;
  totalNetProfit: bigint;
}

function getTotalCargo(cargo: ReadonlyMap<number, bigint>): bigint {
  let sum = 0n;
  for (const qty of cargo.values()) {
    sum += qty;
  }
  return sum;
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
  const ports = new Map<number, SimPortState>();
  for (const p of portsSeed) {
    ports.set(p.id, {
      id: p.id,
      code: p.code,
      name: p.name,
      treasury: p.treasury,
      initialTreasury: p.initial_treasury,
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

  // Tabel jarak terpendek & nextHop antar semua pasangan pelabuhan (Floyd-Warshall)
  const shortestDist = new Map<string, number>();
  const nextHopMap = new Map<string, number>();
  for (const p1 of portsSeed) {
    for (const p2 of portsSeed) {
      const k = `${p1.id}:${p2.id}`;
      shortestDist.set(k, p1.id === p2.id ? 0 : 999);
      nextHopMap.set(k, p1.id);
    }
  }
  for (const r of ROUTES_SEED) {
    const k = `${r.from_port}:${r.to_port}`;
    shortestDist.set(k, r.ticks);
    nextHopMap.set(k, r.to_port);
  }
  for (const kPort of portsSeed) {
    for (const iPort of portsSeed) {
      for (const jPort of portsSeed) {
        const ik = shortestDist.get(`${iPort.id}:${kPort.id}`) ?? 999;
        const kj = shortestDist.get(`${kPort.id}:${jPort.id}`) ?? 999;
        const ij = shortestDist.get(`${iPort.id}:${jPort.id}`) ?? 999;
        if (ik + kj < ij) {
          shortestDist.set(`${iPort.id}:${jPort.id}`, ik + kj);
          const hop = nextHopMap.get(`${iPort.id}:${kPort.id}`) ?? kPort.id;
          nextHopMap.set(`${iPort.id}:${jPort.id}`, hop);
        }
      }
    }
  }

  const getStepToward = (
    fromPort: number,
    targetPort: number,
  ): { toPort: number; ticks: number } | null => {
    if (fromPort === targetPort) return null;
    const hop = nextHopMap.get(`${fromPort}:${targetPort}`);
    if (!hop || hop === fromPort) return null;
    const nbs = neighborsByPort.get(fromPort) ?? [];
    return nbs.find((n) => n.toPort === hop) ?? null;
  };

  const marketSeed = buildMarketSeed(config);
  const markets = new Map<string, (typeof marketSeed)[number]>();
  for (const m of marketSeed) {
    markets.set(`${m.port_id}:${m.commodity_id}`, { ...m });
  }

  const bots: SimBotState[] = [];
  for (let i = 0; i < options.bots; i++) {
    const id = BigInt(i + 1);
    const strategy =
      STRATEGIES[i % STRATEGIES.length] ?? ('naive' as BotStrategyName);
    const startPortId = (i % portsSeed.length) + 1;
    const cargo = new Map<number, bigint>();
    for (const c of COMMODITIES_SEED) {
      cargo.set(c.id, 0n);
    }

    bots.push({
      id,
      strategy,
      coins: config.STARTER_COINS,
      initialCoins: config.STARTER_COINS,
      ledgerSum: config.STARTER_COINS,
      shipId: id,
      capacity: config.STARTER_SHIP_CAPACITY,
      status: 'docked',
      portId: startPortId,
      destPort: null,
      arriveTick: null,
      targetPortId: null,
      cargo,
      lastBuyPortByCommodity: new Map(),
    });
  }

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
      const d = shortestDist.get(`${p1.id}:${p2.id}`) ?? 1;
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
  let profitableExploitsFound = 0;
  let bestCycleNetDelta: bigint | null = null;
  let worstCycleNetDelta: bigint | null = null;

  let cumulativeUpkeepSink = 0n;
  let invariantViolations = 0;
  const invariantViolationDetails: string[] = [];

  const executeBotBuy = (
    bot: SimBotState,
    portId: number,
    commodityId: number,
    requestedQty: bigint | 'maks',
    reserveCoins: bigint = 25n,
  ): boolean => {
    const mKey = `${portId}:${commodityId}`;
    const m = markets.get(mKey);
    const port = ports.get(portId);
    const com = commoditiesById.get(commodityId);
    if (!m || !port || !com) return false;

    const usableCoins =
      bot.coins > reserveCoins ? bot.coins - reserveCoins : 0n;
    if (usableCoins <= 0n) return false;

    const currentCargoQty = bot.cargo.get(commodityId) ?? 0n;
    const totalCargo = getTotalCargo(bot.cargo);

    const res = eksekusiBeli({
      stock: m.stock,
      target: m.target,
      basePrice: com.base_price,
      capacity: m.capacity,
      playerCoins: usableCoins,
      shipCargoQty: currentCargoQty,
      shipTotalCargo: totalCargo,
      shipCapacity: bot.capacity,
      portTreasury: port.treasury,
      requestedQty,
      config,
    });

    if (!res.ok || res.executedQty <= 0n) return false;

    m.stock = res.newStock;
    m.price = res.newPrice;
    port.treasury = res.newPortTreasury;
    bot.coins += res.netPlayerDelta;
    bot.ledgerSum += res.netPlayerDelta;
    bot.cargo.set(commodityId, res.newShipCargoQty);
    bot.lastBuyPortByCommodity.set(commodityId, {
      portId,
      costPaid: -res.netPlayerDelta,
      unitPrice: (-res.netPlayerDelta) / res.executedQty,
    });
    return true;
  };

  const executeBotSell = (
    bot: SimBotState,
    portId: number,
    commodityId: number,
    requestedQty: bigint | 'semua',
  ): boolean => {
    const mKey = `${portId}:${commodityId}`;
    const m = markets.get(mKey);
    const port = ports.get(portId);
    const com = commoditiesById.get(commodityId);
    if (!m || !port || !com) return false;

    const currentCargoQty = bot.cargo.get(commodityId) ?? 0n;
    if (currentCargoQty <= 0n) return false;
    const totalCargo = getTotalCargo(bot.cargo);

    const res = eksekusiJual({
      stock: m.stock,
      target: m.target,
      basePrice: com.base_price,
      capacity: m.capacity,
      playerCoins: bot.coins,
      shipCargoQty: currentCargoQty,
      shipTotalCargo: totalCargo,
      shipCapacity: bot.capacity,
      portTreasury: port.treasury,
      requestedQty,
      config,
    });

    if (!res.ok || res.executedQty <= 0n) return false;

    m.stock = res.newStock;
    m.price = res.newPrice;
    port.treasury = res.newPortTreasury;
    bot.coins += res.netPlayerDelta;
    bot.ledgerSum += res.netPlayerDelta;
    bot.cargo.set(commodityId, res.newShipCargoQty);

    const buyInfo = bot.lastBuyPortByCommodity.get(commodityId);
    if (buyInfo && buyInfo.portId !== portId && res.newShipCargoQty === 0n) {
      const fromCode = ports.get(buyInfo.portId)?.code ?? String(buyInfo.portId);
      const toCode = port.code;
      const rKey = `${fromCode}->${toCode}`;
      const rAcc = routeAccByKey.get(rKey);
      if (rAcc) {
        rAcc.trips += 1;
        rAcc.totalNetProfit += res.netPlayerDelta - buyInfo.costPaid;
      }
      bot.lastBuyPortByCommodity.delete(commodityId);
    }

    return true;
  };

  for (let tick = 1; tick <= options.ticks; tick++) {
    // Langkah 2 & 3: Produksi/konsumsi dan hitung ulang harga
    for (const [mKey, m] of markets.entries()) {
      const com = commoditiesById.get(m.commodity_id);
      if (!com) continue;
      markets.set(mKey, stepProduksiKonsumsi(m, com.base_price, config));
    }

    // Langkah 4: Kedatangan kapal yang selesai berlayar
    for (const bot of bots) {
      if (
        bot.status === 'sailing' &&
        bot.arriveTick !== null &&
        bot.arriveTick <= tick &&
        bot.destPort !== null
      ) {
        bot.status = 'docked';
        bot.portId = bot.destPort;
        bot.destPort = null;
        bot.arriveTick = null;
      }
    }

    // Langkah 5: Evaluasi aturan per kapal docked (urutan putar adil: t mod N)
    const dockedBots = bots
      .filter((b) => b.status === 'docked')
      .sort((a, b) => (a.shipId < b.shipId ? -1 : a.shipId > b.shipId ? 1 : 0));

    const nDocked = dockedBots.length;
    const rotatedDocked: SimBotState[] = [];
    if (nDocked > 0) {
      const offset = tick % nDocked;
      for (let i = 0; i < nDocked; i++) {
        const b = dockedBots[(i + offset) % nDocked];
        if (b) rotatedDocked.push(b);
      }
    }

    const pendingDepartures: {
      bot: SimBotState;
      destPort: number;
      arriveTick: number;
    }[] = [];

    for (const bot of rotatedDocked) {
      const portId = bot.portId;
      const port = ports.get(portId);
      if (!port) continue;

      // Uji eksploit satu-pelabuhan oleh bot adversarial
      if (bot.strategy === 'adversarial') {
        for (const com of COMMODITIES_SEED) {
          const m = markets.get(`${portId}:${com.id}`);
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

      const totalCargo = getTotalCargo(bot.cargo);

      // 1. Jika membawa muatan: jual jika sudah sampai di targetPortId ATAU harga di pelabuhan ini sudah menguntungkan
      if (totalCargo > 0n) {
        let soldAny = false;
        for (const com of COMMODITIES_SEED) {
          const heldQty = bot.cargo.get(com.id) ?? 0n;
          if (heldQty <= 0n) continue;
          const m = markets.get(`${portId}:${com.id}`);
          if (!m) continue;
          const buyInfo = bot.lastBuyPortByCommodity.get(com.id);
          const minProfitablePrice = buyInfo
            ? (buyInfo.unitPrice * 106n) / 100n
            : com.base_price;

          if (
            bot.targetPortId === portId ||
            (m.price >= minProfitablePrice && m.stock < m.target)
          ) {
            if (executeBotSell(bot, portId, com.id, 'semua')) {
              soldAny = true;
              bot.targetPortId = null;
              break;
            }
          }
        }
        if (soldAny) continue;

        // Jika masih membawa muatan, cari pelabuhan tujuan terbaik di seluruh kepulauan dan berlayar 1 hop ke sana
        let bestDestPort = bot.targetPortId;
        if (!bestDestPort || bestDestPort === portId) {
          let bestScore = -1_000_000n;
          for (const destP of portsSeed) {
            if (destP.id === portId) continue;
            const dTicks = shortestDist.get(`${portId}:${destP.id}`) ?? 10;
            let score = 0n;
            for (const com of COMMODITIES_SEED) {
              const qty = bot.cargo.get(com.id) ?? 0n;
              if (qty <= 0n) continue;
              const destM = markets.get(`${destP.id}:${com.id}`);
              if (destM) {
                score += qty * destM.price - BigInt(dTicks) * 2n;
              }
            }
            if (score > bestScore) {
              bestScore = score;
              bestDestPort = destP.id;
            }
          }
          bot.targetPortId = bestDestPort ?? null;
        }

        if (bot.targetPortId && bot.targetPortId !== portId) {
          const step = getStepToward(portId, bot.targetPortId);
          if (step) {
            pendingDepartures.push({
              bot,
              destPort: step.toPort,
              arriveTick: tick + step.ticks,
            });
            continue;
          }
        }
      }

      // 2. Jika muatan kosong: cari komoditas di pelabuhan ini yang punya margin positif ke salah satu pelabuhan tujuan
      interface TradeCandidate {
        comId: number;
        destPortId: number;
        score: bigint;
      }
      const candidates: TradeCandidate[] = [];

      for (const com of COMMODITIES_SEED) {
        const m = markets.get(`${portId}:${com.id}`);
        if (!m || m.stock <= 25n) continue;

        // Batas harga beli tergantung strategi
        const maxBuyRatioPct =
          bot.strategy === 'hoarder'
            ? 90n
            : bot.strategy === 'naive'
              ? 100n
              : 105n;
        if (m.price > (com.base_price * maxBuyRatioPct) / 100n) continue;

        for (const destP of portsSeed) {
          if (destP.id === portId) continue;
          const destM = markets.get(`${destP.id}:${com.id}`);
          const destPortState = ports.get(destP.id);
          if (!destM || !destPortState || destPortState.treasury <= 500n) {
            continue;
          }

          const dTicks = shortestDist.get(`${portId}:${destP.id}`) ?? 10;
          const estFee =
            hitungBiayaPelabuhan(m.price, config) +
            hitungBiayaPelabuhan(destM.price, config);
          const spreadPerUnit = destM.price - m.price - estFee;
          if (spreadPerUnit <= 2n) continue;

          // Skor disesuaikan dengan karakter strategi agar semua 5 strategi punya spesialisasi rute berbeda
          let score = spreadPerUnit;
          if (bot.strategy === 'margin_hunter') {
            score = (spreadPerUnit * 12n) / BigInt(dTicks);
          } else if (bot.strategy === 'hoarder') {
            // Penimbun menyukai barang yang stok tujuannya sangat langka
            score = spreadPerUnit + (destM.target - destM.stock) / 4n;
          } else if (bot.strategy === 'naive') {
            // Pedagang naif menyukai rute dekat (ticks kecil)
            score = spreadPerUnit - BigInt(dTicks) * 2n;
          } else if (bot.strategy === 'adversarial') {
            // Adversarial menyeimbangkan spread dan likuiditas stok asal
            score = spreadPerUnit + (m.stock - m.target) / 8n;
          }

          if (score > 0n) {
            candidates.push({
              comId: com.id,
              destPortId: destP.id,
              score,
            });
          }
        }
      }

      if (candidates.length > 0) {
        candidates.sort((a, b) =>
          b.score > a.score ? 1 : b.score < a.score ? -1 : 0,
        );
        const chosen =
          bot.strategy === 'random'
            ? candidates[rng.nextInt(0, candidates.length - 1)]
            : candidates[0];

        if (chosen) {
          bot.targetPortId = chosen.destPortId;
          if (executeBotBuy(bot, portId, chosen.comId, 'maks', 25n)) {
            continue;
          }
        }
      }

      // 3. Jika di pelabuhan ini tidak ada komoditas yang murah untuk dibeli (misal di Batavia),
      // berlayar menuju pelabuhan produsen yang memiliki surplus stok terbesar
      let bestProducerPortId: number | null = null;
      let bestProducerScore = -1_000_000n;

      for (const prodP of portsSeed) {
        if (prodP.id === portId) continue;
        const dTicks = shortestDist.get(`${portId}:${prodP.id}`) ?? 10;
        let maxSurplus = 0n;
        for (const com of COMMODITIES_SEED) {
          const pm = markets.get(`${prodP.id}:${com.id}`);
          if (pm && pm.stock > pm.target) {
            const diff = pm.stock - pm.target;
            if (diff > maxSurplus) maxSurplus = diff;
          }
        }
        if (maxSurplus > 0n) {
          const jitter =
            bot.strategy === 'random'
              ? BigInt(rng.nextInt(0, 120))
              : BigInt((( Number(bot.id) + tick) % 5) * 15);
          const score = maxSurplus - BigInt(dTicks) * 18n + jitter;
          if (score > bestProducerScore) {
            bestProducerScore = score;
            bestProducerPortId = prodP.id;
          }
        }
      }

      if (bestProducerPortId !== null) {
        const step = getStepToward(portId, bestProducerPortId);
        if (step) {
          pendingDepartures.push({
            bot,
            destPort: step.toPort,
            arriveTick: tick + step.ticks,
          });
        }
      }
    }

    // Langkah 6: Biaya perawatan (upkeep) untuk semua kapal
    for (const bot of bots) {
      if (bot.coins >= config.UPKEEP_PER_TICK) {
        bot.coins -= config.UPKEEP_PER_TICK;
        bot.ledgerSum -= config.UPKEEP_PER_TICK;
        cumulativeUpkeepSink += config.UPKEEP_PER_TICK;
        if (bot.status === 'grounded') {
          bot.status = 'docked';
        }
      } else {
        bot.status = 'grounded';
      }
    }

    // Langkah 7: Berangkat (sailing)
    for (const dep of pendingDepartures) {
      if (dep.bot.status === 'docked') {
        dep.bot.status = 'sailing';
        dep.bot.destPort = dep.destPort;
        dep.bot.arriveTick = dep.arriveTick;
      }
    }

    // Langkah 8: Catat statistik harga & batas clamp
    for (const m of markets.values()) {
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

    // Langkah 9: Pemeriksaan invarian setiap tick
    const invCheck = periksaInvarianEkonomi(
      {
        players: bots.map((b) => ({
          id: b.id,
          coins: b.coins,
          initialCoins: b.initialCoins,
        })),
        ports: Array.from(ports.values()).map((p) => ({
          id: p.id,
          treasury: p.treasury,
          initialTreasury: p.initialTreasury,
        })),
        markets: Array.from(markets.values()).map((m) => ({
          portId: m.port_id,
          commodityId: m.commodity_id,
          stock: m.stock,
          target: m.target,
          capacity: m.capacity,
          price: m.price,
          basePrice: commoditiesById.get(m.commodity_id)?.base_price ?? 1n,
        })),
        ships: bots.map((b) => ({
          id: b.shipId,
          playerId: b.id,
          capacity: b.capacity,
          cargoByCommodity: b.cargo,
        })),
        ledgerDeltasByPlayer: new Map(bots.map((b) => [b.id, b.ledgerSum])),
        cumulativeUpkeepSink,
      },
      config,
    );

    if (!invCheck.valid) {
      invariantViolations += invCheck.violations.length;
      for (const v of invCheck.violations) {
        if (invariantViolationDetails.length < 25) {
          invariantViolationDetails.push(`tick ${tick}: ${v}`);
        }
      }
    }
  }

  const botWealths = new Map<bigint, bigint>();
  const wealthNumbers: number[] = [];

  for (const bot of bots) {
    let cargoVal = 0n;
    for (const [comId, qty] of bot.cargo.entries()) {
      const baseP = commoditiesById.get(comId)?.base_price ?? 0n;
      cargoVal += qty * baseP;
    }
    const netWorth = bot.coins + cargoVal;
    botWealths.set(bot.id, netWorth);
    wealthNumbers.push(Number(netWorth));
  }

  const totalBotWealth = Array.from(botWealths.values()).reduce(
    (a, b) => a + b,
    0n,
  );
  const giniWealth = computeGini(wealthNumbers);

  const strategyMetrics: StrategyMetrics[] = [];
  let maxStrategyWealthSharePct = 0;
  let dominantStrategy: BotStrategyName = 'naive';

  for (const strat of STRATEGIES) {
    const stratBots = bots.filter((b) => b.strategy === strat);
    let stratWealth = 0n;
    let bankruptCount = 0;
    for (const b of stratBots) {
      stratWealth += botWealths.get(b.id) ?? 0n;
      if (b.status === 'grounded') bankruptCount += 1;
    }
    const sharePct =
      totalBotWealth > 0n
        ? Number(((Number(stratWealth) / Number(totalBotWealth)) * 100).toFixed(2))
        : 0;
    if (sharePct > maxStrategyWealthSharePct) {
      maxStrategyWealthSharePct = sharePct;
      dominantStrategy = strat;
    }
    strategyMetrics.push({
      strategy: strat,
      botCount: stratBots.length,
      totalWealth: stratWealth.toString(),
      avgWealth:
        stratBots.length > 0
          ? Number((Number(stratWealth) / stratBots.length).toFixed(2))
          : 0,
      wealthSharePct: sharePct,
      bankruptCount,
    });
  }

  const commodityMetrics: CommodityMetrics[] = [];
  let totalPriceObs = 0;
  let totalBoundObs = 0;

  for (const com of COMMODITIES_SEED) {
    const acc = priceAccByCom.get(com.id);
    if (!acc || acc.count === 0) continue;
    const mean = acc.sum / acc.count;
    const variance = Math.max(0, acc.sumSq / acc.count - mean * mean);
    const stdDev = Math.sqrt(variance);
    const lowerPct = (acc.atLowerBoundCount / acc.count) * 100;
    const upperPct = (acc.atUpperBoundCount / acc.count) * 100;
    const boundsPct =
      ((acc.atLowerBoundCount + acc.atUpperBoundCount) / acc.count) * 100;

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
      pctTicksAtBounds: Number(boundsPct.toFixed(2)),
    });
  }

  const overallPctTicksAtBounds =
    totalPriceObs > 0
      ? Number(((totalBoundObs / totalPriceObs) * 100).toFixed(2))
      : 0;

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

  const totalInitialPlayerCoins = bots.reduce(
    (s, b) => s + b.initialCoins,
    0n,
  );
  const totalInitialPortTreasury = Array.from(ports.values()).reduce(
    (s, p) => s + p.initialTreasury,
    0n,
  );
  const finalPlayerCoins = bots.reduce((s, b) => s + b.coins, 0n);
  const finalPortTreasury = Array.from(ports.values()).reduce(
    (s, p) => s + p.treasury,
    0n,
  );
  const totalInitialMoney = totalInitialPlayerCoins + totalInitialPortTreasury;
  const finalAccountedMoney =
    finalPlayerCoins + finalPortTreasury + cumulativeUpkeepSink;

  const canonicalState = JSON.stringify({
    seed: options.seed,
    ticks: options.ticks,
    cumulativeUpkeepSink: cumulativeUpkeepSink.toString(),
    ports: Array.from(ports.values()).map((p) => ({
      id: p.id,
      treasury: p.treasury.toString(),
    })),
    markets: Array.from(markets.values()).map((m) => ({
      p: m.port_id,
      c: m.commodity_id,
      s: m.stock.toString(),
      pr: m.price.toString(),
    })),
    bots: bots.map((b) => ({
      id: b.id.toString(),
      coins: b.coins.toString(),
      status: b.status,
      portId: b.portId,
      destPort: b.destPort,
      arriveTick: b.arriveTick,
      cargo: Array.from(b.cargo.entries()).map(([k, v]) => [k, v.toString()]),
    })),
  });
  const stateHash = crypto
    .createHash('sha256')
    .update(canonicalState)
    .digest('hex');

  const bankruptBotCount = bots.filter((b) => b.status === 'grounded').length;
  const portTreasuries: Record<string, string> = {};
  for (const p of ports.values()) {
    portTreasuries[p.code] = p.treasury.toString();
  }

  return {
    seed: options.seed,
    ticks: options.ticks,
    bots: options.bots,
    stateHash,
    invariantViolations,
    invariantViolationDetails,
    giniWealth,
    bankruptBotCount,
    bankruptBotPct:
      options.bots > 0
        ? Number(((bankruptBotCount / options.bots) * 100).toFixed(2))
        : 0,
    maxStrategyWealthSharePct,
    dominantStrategy,
    overallPctTicksAtBounds,
    moneyConservation: {
      valid: finalAccountedMoney === totalInitialMoney,
      totalInitialPlayerCoins: totalInitialPlayerCoins.toString(),
      totalInitialPortTreasury: totalInitialPortTreasury.toString(),
      totalInitialMoney: totalInitialMoney.toString(),
      finalPlayerCoins: finalPlayerCoins.toString(),
      finalPortTreasury: finalPortTreasury.toString(),
      cumulativeUpkeepSink: cumulativeUpkeepSink.toString(),
      finalAccountedMoney: finalAccountedMoney.toString(),
    },
    portTreasuries,
    commodityMetrics,
    strategyMetrics,
    routeMargins,
    adversarial: {
      cycleAttempts,
      roundingAttempts,
      pumpDumpAttempts,
      totalExploitAttempts: cycleAttempts + pumpDumpAttempts,
      profitableExploitsFound,
      bestCycleNetDeltaCoins: (bestCycleNetDelta ?? 0n).toString(),
      worstCycleNetDeltaCoins: (worstCycleNetDelta ?? 0n).toString(),
    },
  };
}
