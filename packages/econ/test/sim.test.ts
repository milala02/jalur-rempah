import { describe, it, expect } from 'vitest';
import {
  WORLD_CONFIG,
  buildPortsSeed,
  buildMarketSeed,
} from '@jalur-rempah/shared';
import {
  runEconomySimulation,
  stepWorld,
  WorldState,
  computeCanonicalStateHash,
} from '../src/index.js';

function createSingleShipWorld(
  initialCoins: bigint,
  status: 'docked' | 'sailing' | 'grounded',
  cargoPala: bigint,
): WorldState {
  const portsSeed = buildPortsSeed(WORLD_CONFIG);
  const ports = new Map(
    portsSeed.map((p) => [
      p.id,
      {
        id: p.id,
        code: p.code,
        name: p.name,
        treasury: p.treasury,
        initialTreasury: p.initial_treasury,
      },
    ]),
  );
  const marketSeed = buildMarketSeed(WORLD_CONFIG);
  const markets = new Map(
    marketSeed.map((m) => [`${m.port_id}:${m.commodity_id}`, { ...m }]),
  );

  const players = new Map([
    [
      1n,
      {
        id: 1n,
        coins: initialCoins,
        initialCoins,
        ledgerSum: initialCoins,
        lastRescueTick: null,
        rescueCount: 0,
      },
    ],
  ]);

  const ships = new Map([
    [
      1n,
      {
        id: 1n,
        playerId: 1n,
        capacity: 35,
        status,
        portId: 6,
        destPort: status === 'sailing' ? 3 : null,
        arriveTick: status === 'sailing' ? 5 : null,
        cargo: new Map([
          [1, cargoPala],
          [2, 0n],
          [3, 0n],
          [4, 0n],
        ]),
      },
    ],
  ]);

  const state: WorldState = {
    tickNo: 0,
    players,
    ports,
    markets,
    ships,
    cumulativeUpkeepSink: 0n,
    cumulativeSource: 0n,
    stateHash: '',
  };
  state.stateHash = computeCanonicalStateHash(state);
  return state;
}

describe('M1 — packages/econ: stepWorld (docs/09 v0.2), Simulator Determinisme, & Gerbang Kualitas', () => {
  it('1. Determinisme penuh: seed yang sama menghasilkan stateHash dan metrik yang 100% identik di 2 kali jalan', () => {
    const run1 = runEconomySimulation({
      ticks: 500,
      bots: 20,
      seed: 42,
    });
    const run2 = runEconomySimulation({
      ticks: 500,
      bots: 20,
      seed: 42,
    });

    expect(run1.stateHash).toBe(run2.stateHash);
    expect(run1.invariantViolations).toBe(0);
    expect(run2.invariantViolations).toBe(0);
    expect(run1.moneyConservation.valid).toBe(true);
    expect(run1.adversarial.profitableExploitsFound).toBe(0);
    expect(run1.adversarial.cycleAttempts).toBeGreaterThan(0);
  });

  it('2. Seed berbeda menghasilkan simulasi berbeda tetapi tetap 0 pelanggaran invarian dan lulus semua gerbang', () => {
    const runA = runEconomySimulation({
      ticks: 1000,
      bots: 15,
      seed: 101,
    });
    const runB = runEconomySimulation({
      ticks: 1000,
      bots: 15,
      seed: 202,
    });

    expect(runA.stateHash).not.toBe(runB.stateHash);
    expect(runA.invariantViolations).toBe(0);
    expect(runB.invariantViolations).toBe(0);
    expect(runA.adversarial.profitableExploitsFound).toBe(0);
    expect(runB.adversarial.profitableExploitsFound).toBe(0);
    expect(runA.gates.passed).toBe(true);
    expect(runB.gates.passed).toBe(true);
  });

  it('3. Aturan tick docs/09 v0.2: perawatan sebelum aksi, kapal grounded ditolak beli/berlayar (GROUNDED), jatuh ke aturan jual, lalu pulih pada tick berikutnya', () => {
    // Mulai dengan 0 koin, status docked, dan 5 unit pala di kapal
    const world = createSingleShipWorld(0n, 'docked', 5n);

    // Tick 1: Langkah 5 menagih perawatan sebelum aksi -> karena koin 0 < 1, kapal menjadi grounded.
    // Langkah 6 mengevaluasi aturan: aturan 1 (buy) gagal GROUNDED, aturan 2 (sail) gagal GROUNDED,
    // jatuh ke aturan 3 (sell) yang DIIZINKAN saat grounded -> berhasil menjual 5 pala!
    const { events: ev1 } = stepWorld(
      world,
      () => [
        { ruleName: 'coba_beli', type: 'buy', commodityId: 1, qty: 1n },
        { ruleName: 'coba_layar', type: 'sail', destPortId: 3 },
        { ruleName: 'jual_darurat', type: 'sell', commodityId: 1, qty: 'semua' },
      ],
      { ...WORLD_CONFIG, RESCUE_ENABLED: false },
    );

    expect(ev1.invariantCheck.valid).toBe(true);
    expect(ev1.actionEvents.length).toBe(3);
    expect(ev1.actionEvents[0]?.result).toBe('gagal');
    expect(ev1.actionEvents[0]?.failureCode).toBe('GROUNDED');
    expect(ev1.actionEvents[1]?.result).toBe('gagal');
    expect(ev1.actionEvents[1]?.failureCode).toBe('GROUNDED');
    expect(ev1.actionEvents[2]?.result).toBe('ok');
    expect(ev1.actionEvents[2]?.actionType).toBe('sell');

    const playerAfterT1 = world.players.get(1n);
    expect((playerAfterT1?.coins ?? 0n) > 300n).toBe(true);

    // Tick 2: Karena koin sekarang >= UPKEEP_PER_TICK, pada Langkah 5 kapal membayar upkeep 1 koin
    // (tanpa akumulasi tunggakan dari tick 1!) dan langsung kembali 'docked' lalu berhasil berlayar!
    const coinsBeforeT2 = playerAfterT1?.coins ?? 0n;
    const { events: ev2 } = stepWorld(
      world,
      () => [{ ruleName: 'berlayar_normal', type: 'sail', destPortId: 3 }],
      { ...WORLD_CONFIG, RESCUE_ENABLED: false },
    );

    expect(ev2.upkeepPaidTotal).toBe(1n);
    expect(world.players.get(1n)?.coins).toBe(coinsBeforeT2 - 1n);
    expect(world.ships.get(1n)?.status).toBe('sailing');
    expect(ev2.actionEvents[0]?.result).toBe('berlayar');
  });

  it('4. Aturan tick docs/09 v0.2: kapal sailing dengan koin 0 tetap berlayar tanpa akumulasi tunggakan, dan pemulihan darurat (rescue) bekerja sesuai cooldown', () => {
    const world = createSingleShipWorld(0n, 'sailing', 0n);

    // Tick 1: kapal sedang sailing (arriveTick = 5) dengan koin 0 -> tetap sailing, upkeepPaid = 0
    const { events: ev1 } = stepWorld(
      world,
      () => [{ type: 'wait' }],
      { ...WORLD_CONFIG, RESCUE_ENABLED: true },
    );
    expect(world.ships.get(1n)?.status).toBe('sailing');
    expect(ev1.upkeepPaidTotal).toBe(0n);
    expect(ev1.rescueGrantedCount).toBe(0);

    // Set kapal menjadi grounded dengan muatan kosong dan koin 0
    const ship = world.ships.get(1n);
    if (ship) {
      ship.status = 'grounded';
      ship.destPort = null;
      ship.arriveTick = null;
    }

    // Tick 2: Langkah 7 memberikan RESCUE_COINS (200n) dan mencatatnya ke cumulativeSource
    const { events: ev2 } = stepWorld(
      world,
      () => [{ type: 'wait' }],
      { ...WORLD_CONFIG, RESCUE_ENABLED: true, RESCUE_COINS: 200n, RESCUE_COOLDOWN_TICKS: 2880 },
    );
    expect(ev2.rescueGrantedCount).toBe(1);
    expect(ev2.rescueCoinsAddedTotal).toBe(200n);
    expect(world.players.get(1n)?.coins).toBe(200n);
    expect(ev2.invariantCheck.valid).toBe(true);
  });
});
