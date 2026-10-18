import { WORLD_CONFIG, WorldEconomyConfig } from '@jalur-rempah/shared';
import { batasHargaAtas, batasHargaBawah } from './price.js';

export interface EconomySnapshot {
  readonly players: readonly {
    readonly id: bigint;
    readonly coins: bigint;
    readonly initialCoins: bigint;
  }[];
  readonly ports: readonly {
    readonly id: number;
    readonly treasury: bigint;
    readonly initialTreasury: bigint;
  }[];
  readonly markets: readonly {
    readonly portId: number;
    readonly commodityId: number;
    readonly stock: bigint;
    readonly target: bigint;
    readonly capacity: bigint;
    readonly price: bigint;
    readonly basePrice: bigint;
  }[];
  readonly ships: readonly {
    readonly id: bigint;
    readonly playerId: bigint;
    readonly capacity: number;
    readonly cargoByCommodity: ReadonlyMap<number, bigint>;
  }[];
  readonly ledgerDeltasByPlayer: ReadonlyMap<bigint, bigint>;
  readonly cumulativeUpkeepSink: bigint;
}

export interface InvariantCheckResult {
  readonly valid: boolean;
  readonly violations: readonly string[];
}

export function periksaInvarianEkonomi(
  snapshot: EconomySnapshot,
  config: WorldEconomyConfig = WORLD_CONFIG,
): InvariantCheckResult {
  const violations: string[] = [];

  let totalPlayerCoins = 0n;
  let totalInitialPlayerCoins = 0n;

  for (const player of snapshot.players) {
    if (player.coins < 0n) {
      violations.push(
        `Pemain ${player.id.toString()} memiliki koin negatif: ${player.coins.toString()}`,
      );
    }
    const ledgerSum = snapshot.ledgerDeltasByPlayer.get(player.id) ?? 0n;
    if (player.coins !== ledgerSum) {
      violations.push(
        `Saldo pemain ${player.id.toString()} (${player.coins.toString()}) != jumlah ledger (${ledgerSum.toString()})`,
      );
    }
    totalPlayerCoins += player.coins;
    totalInitialPlayerCoins += player.initialCoins;
  }

  let totalPortTreasury = 0n;
  let totalInitialPortTreasury = 0n;

  for (const port of snapshot.ports) {
    if (port.treasury < 0n) {
      violations.push(
        `Pelabuhan ${port.id} memiliki treasury negatif: ${port.treasury.toString()}`,
      );
    }
    totalPortTreasury += port.treasury;
    totalInitialPortTreasury += port.initialTreasury;
  }

  if (snapshot.cumulativeUpkeepSink < 0n) {
    violations.push(
      `Pengurang kumulatif upkeep negatif: ${snapshot.cumulativeUpkeepSink.toString()}`,
    );
  }

  // Invarian Konservasi Uang Global (ADR-009):
  // total_koin_pemain + total_kas_pelabuhan + pengurang_kumulatif == total_awal
  const totalCurrentPlusSink =
    totalPlayerCoins + totalPortTreasury + snapshot.cumulativeUpkeepSink;
  const totalInitial = totalInitialPlayerCoins + totalInitialPortTreasury;

  if (totalCurrentPlusSink !== totalInitial) {
    violations.push(
      `Pelanggaran konservasi uang: (koin=${totalPlayerCoins.toString()} + kas=${totalPortTreasury.toString()} + upkeep=${snapshot.cumulativeUpkeepSink.toString()} = ${totalCurrentPlusSink.toString()}) != total_awal (${totalInitial.toString()})`,
    );
  }

  // Invarian Pasar & Harga
  for (const m of snapshot.markets) {
    if (m.stock < 0n || m.stock > m.capacity) {
      violations.push(
        `Stok pasar (${m.portId}, ${m.commodityId}) di luar batas [0, ${m.capacity.toString()}]: ${m.stock.toString()}`,
      );
    }
    const minP = batasHargaBawah(m.basePrice, config);
    const maxP = batasHargaAtas(m.basePrice, config);
    if (m.price < 1n || m.price < minP || m.price > maxP) {
      violations.push(
        `Harga pasar (${m.portId}, ${m.commodityId}) di luar batas [${minP.toString()}, ${maxP.toString()}]: ${m.price.toString()}`,
      );
    }
  }

  // Invarian Muatan Kapal
  for (const ship of snapshot.ships) {
    let sumCargo = 0n;
    for (const [comId, qty] of ship.cargoByCommodity.entries()) {
      if (qty < 0n) {
        violations.push(
          `Muatan kapal ${ship.id.toString()} komoditas ${comId} negatif: ${qty.toString()}`,
        );
      }
      sumCargo += qty;
    }
    if (sumCargo > BigInt(ship.capacity)) {
      violations.push(
        `Total muatan kapal ${ship.id.toString()} (${sumCargo.toString()}) melebihi kapasitas (${ship.capacity})`,
      );
    }
  }

  return {
    valid: violations.length === 0,
    violations,
  };
}
