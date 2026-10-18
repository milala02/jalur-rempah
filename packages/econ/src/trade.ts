import { WORLD_CONFIG, WorldEconomyConfig } from '@jalur-rempah/shared';
import { hitungHarga } from './price.js';

export interface BuyInput {
  readonly stock: bigint;
  readonly target: bigint;
  readonly basePrice: bigint;
  readonly capacity: bigint;
  readonly playerCoins: bigint;
  readonly shipCargoQty: bigint;
  readonly shipTotalCargo: bigint;
  readonly shipCapacity: number;
  readonly portTreasury: bigint;
  readonly requestedQty: bigint | 'maks';
  readonly config?: WorldEconomyConfig;
}

export interface SellInput {
  readonly stock: bigint;
  readonly target: bigint;
  readonly basePrice: bigint;
  readonly capacity: bigint;
  readonly playerCoins: bigint;
  readonly shipCargoQty: bigint;
  readonly shipTotalCargo: bigint;
  readonly shipCapacity: number;
  readonly portTreasury: bigint;
  readonly requestedQty: bigint | 'semua' | 'maks';
  readonly config?: WorldEconomyConfig;
}

export interface TradeOutcome {
  readonly ok: boolean;
  readonly reason?: string;
  readonly executedQty: bigint;
  readonly grossValue: bigint;
  readonly fee: bigint;
  readonly netPlayerDelta: bigint;
  readonly netTreasuryDelta: bigint;
  readonly newStock: bigint;
  readonly newPrice: bigint;
  readonly newPlayerCoins: bigint;
  readonly newShipCargoQty: bigint;
  readonly newPortTreasury: bigint;
}

/**
 * Biaya pelabuhan 2% dari nilai kotor transaksi, dibulatkan ke atas dalam
 * aritmetika integer murni (tanpa float), minimal PORT_FEE_MIN (1 koin).
 */
export function hitungBiayaPelabuhan(
  nilaiKotor: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  if (nilaiKotor <= 0n) {
    return 0n;
  }
  const pct = BigInt(config.PORT_FEE_PERCENT);
  const ceilFee = (nilaiKotor * pct + 99n) / 100n;
  return ceilFee > config.PORT_FEE_MIN ? ceilFee : config.PORT_FEE_MIN;
}

/**
 * Menghitung kumpulan harga beli n unit secara simetris:
 * Unit ke-i (i = 0..n-1) membayar hitungHarga(stock - i), lalu stok berkurang 1.
 */
export function hitungNilaiKotorBeli(
  stock: bigint,
  n: bigint,
  target: bigint,
  basePrice: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  let gross = 0n;
  for (let i = 0n; i < n; i++) {
    gross += hitungHarga(stock - i, target, basePrice, config);
  }
  return gross;
}

/**
 * Menghitung kumpulan harga jual n unit secara simetris (ADR-009):
 * Untuk tiap unit, stok += 1 lebih dulu, lalu terima hitungHarga(stok baru).
 * Unit ke-i (i = 1..n) menerima hitungHarga(stock + i).
 */
export function hitungNilaiKotorJual(
  stock: bigint,
  n: bigint,
  target: bigint,
  basePrice: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  let gross = 0n;
  for (let i = 1n; i <= n; i++) {
    gross += hitungHarga(stock + i, target, basePrice, config);
  }
  return gross;
}

/**
 * Algoritma deterministik pencarian biner (binary search) untuk beli(maks).
 * Mencari jumlah unit k terbesar dalam [0, min(stock, muatan_bebas)]
 * sehingga gross(k) + fee(gross(k)) <= playerCoins.
 */
export function hitungJumlahBeliMaks(
  input: Omit<BuyInput, 'requestedQty'>,
): { qty: bigint; grossValue: bigint; fee: bigint; totalCost: bigint } {
  const config = input.config ?? WORLD_CONFIG;
  const freeCargo = BigInt(input.shipCapacity) - input.shipTotalCargo;
  if (freeCargo <= 0n || input.stock <= 0n || input.playerCoins <= 0n) {
    return { qty: 0n, grossValue: 0n, fee: 0n, totalCost: 0n };
  }

  const maxPhysical = input.stock < freeCargo ? input.stock : freeCargo;
  const maxUnits = Number(maxPhysical);

  // Bangun tabel prefix sum nilai kotor untuk 1..maxUnits
  const grossPrefix: bigint[] = new Array<bigint>(maxUnits + 1);
  grossPrefix[0] = 0n;
  for (let k = 1; k <= maxUnits; k++) {
    const prev = grossPrefix[k - 1] ?? 0n;
    const unitPrice = hitungHarga(
      input.stock - BigInt(k - 1),
      input.target,
      input.basePrice,
      config,
    );
    grossPrefix[k] = prev + unitPrice;
  }

  // Karena grossPrefix[k] + fee(grossPrefix[k]) monoton naik tegas terhadap k,
  // binary search menemukan k terbesar yang <= playerCoins secara eksak.
  let low = 0;
  let high = maxUnits;
  let bestK = 0;

  while (low <= high) {
    const mid = (low + high) >>> 1;
    if (mid === 0) {
      low = 1;
      continue;
    }
    const g = grossPrefix[mid] ?? 0n;
    const f = hitungBiayaPelabuhan(g, config);
    const total = g + f;

    if (total <= input.playerCoins) {
      bestK = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (bestK === 0) {
    return { qty: 0n, grossValue: 0n, fee: 0n, totalCost: 0n };
  }

  const finalGross = grossPrefix[bestK] ?? 0n;
  const finalFee = hitungBiayaPelabuhan(finalGross, config);
  return {
    qty: BigInt(bestK),
    grossValue: finalGross,
    fee: finalFee,
    totalCost: finalGross + finalFee,
  };
}

/**
 * Algoritma deterministik pencarian biner (binary search) untuk jual(semua)/jual(maks).
 * Mencari jumlah unit k terbesar dalam [0, min(shipCargoQty, capacity - stock)]
 * sehingga gross(k) <= portTreasury.
 */
export function hitungJumlahJualMaks(
  input: Omit<SellInput, 'requestedQty'>,
): { qty: bigint; grossValue: bigint; fee: bigint; netPayout: bigint } {
  const config = input.config ?? WORLD_CONFIG;
  const freeWarehouse = input.capacity - input.stock;
  if (
    input.shipCargoQty <= 0n ||
    freeWarehouse <= 0n ||
    input.portTreasury <= 0n
  ) {
    return { qty: 0n, grossValue: 0n, fee: 0n, netPayout: 0n };
  }

  const maxPhysical =
    input.shipCargoQty < freeWarehouse ? input.shipCargoQty : freeWarehouse;
  const maxUnits = Number(maxPhysical);

  // Bangun tabel prefix sum nilai kotor jual (simetris: stok + k)
  const grossPrefix: bigint[] = new Array<bigint>(maxUnits + 1);
  grossPrefix[0] = 0n;
  for (let k = 1; k <= maxUnits; k++) {
    const prev = grossPrefix[k - 1] ?? 0n;
    const unitPrice = hitungHarga(
      input.stock + BigInt(k),
      input.target,
      input.basePrice,
      config,
    );
    grossPrefix[k] = prev + unitPrice;
  }

  // Karena grossPrefix[k] monoton naik tegas terhadap k, binary search
  // menemukan k terbesar dengan grossPrefix[k] <= portTreasury secara eksak.
  let low = 0;
  let high = maxUnits;
  let bestK = 0;

  while (low <= high) {
    const mid = (low + high) >>> 1;
    if (mid === 0) {
      low = 1;
      continue;
    }
    const g = grossPrefix[mid] ?? 0n;
    if (g <= input.portTreasury) {
      bestK = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (bestK === 0) {
    return { qty: 0n, grossValue: 0n, fee: 0n, netPayout: 0n };
  }

  const finalGross = grossPrefix[bestK] ?? 0n;
  const finalFee = hitungBiayaPelabuhan(finalGross, config);
  const netPayout = finalGross - finalFee;
  return {
    qty: BigInt(bestK),
    grossValue: finalGross,
    fee: finalFee,
    netPayout,
  };
}

export function eksekusiBeli(input: BuyInput): TradeOutcome {
  const config = input.config ?? WORLD_CONFIG;
  const currentPrice = hitungHarga(
    input.stock,
    input.target,
    input.basePrice,
    config,
  );

  const reject = (reason: string): TradeOutcome => ({
    ok: false,
    reason,
    executedQty: 0n,
    grossValue: 0n,
    fee: 0n,
    netPlayerDelta: 0n,
    netTreasuryDelta: 0n,
    newStock: input.stock,
    newPrice: currentPrice,
    newPlayerCoins: input.playerCoins,
    newShipCargoQty: input.shipCargoQty,
    newPortTreasury: input.portTreasury,
  });

  const freeCargo = BigInt(input.shipCapacity) - input.shipTotalCargo;
  if (freeCargo <= 0n) {
    return reject('muatan kapal penuh');
  }
  if (input.stock <= 0n) {
    return reject('stok pelabuhan habis');
  }

  let qty: bigint;
  let grossValue: bigint;
  let fee: bigint;

  if (input.requestedQty === 'maks') {
    const maxCalc = hitungJumlahBeliMaks(input);
    if (maxCalc.qty <= 0n) {
      return reject('koin tidak cukup untuk membeli 1 unit');
    }
    qty = maxCalc.qty;
    grossValue = maxCalc.grossValue;
    fee = maxCalc.fee;
  } else {
    if (input.requestedQty <= 0n) {
      return reject('jumlah beli harus > 0');
    }
    if (input.requestedQty > freeCargo) {
      return reject('melebihi kapasitas muatan kapal');
    }
    if (input.requestedQty > input.stock) {
      return reject('stok pelabuhan tidak mencukupi');
    }
    qty = input.requestedQty;
    grossValue = hitungNilaiKotorBeli(
      input.stock,
      qty,
      input.target,
      input.basePrice,
      config,
    );
    fee = hitungBiayaPelabuhan(grossValue, config);
    if (grossValue + fee > input.playerCoins) {
      return reject('koin pemain tidak mencukupi');
    }
  }

  const totalCost = grossValue + fee;
  const newStock = input.stock - qty;
  const newPrice = hitungHarga(newStock, input.target, input.basePrice, config);

  return {
    ok: true,
    executedQty: qty,
    grossValue,
    fee,
    netPlayerDelta: -totalCost,
    netTreasuryDelta: totalCost,
    newStock,
    newPrice,
    newPlayerCoins: input.playerCoins - totalCost,
    newShipCargoQty: input.shipCargoQty + qty,
    newPortTreasury: input.portTreasury + totalCost,
  };
}

export function eksekusiJual(input: SellInput): TradeOutcome {
  const config = input.config ?? WORLD_CONFIG;
  const currentPrice = hitungHarga(
    input.stock,
    input.target,
    input.basePrice,
    config,
  );

  const reject = (reason: string): TradeOutcome => ({
    ok: false,
    reason,
    executedQty: 0n,
    grossValue: 0n,
    fee: 0n,
    netPlayerDelta: 0n,
    netTreasuryDelta: 0n,
    newStock: input.stock,
    newPrice: currentPrice,
    newPlayerCoins: input.playerCoins,
    newShipCargoQty: input.shipCargoQty,
    newPortTreasury: input.portTreasury,
  });

  if (input.shipCargoQty <= 0n) {
    return reject('tidak ada muatan untuk dijual');
  }
  const freeWarehouse = input.capacity - input.stock;
  if (freeWarehouse <= 0n) {
    return reject('gudang pelabuhan penuh');
  }
  if (input.portTreasury <= 0n) {
    return reject('kas pelabuhan kosong');
  }

  let qty: bigint;
  let grossValue: bigint;
  let fee: bigint;

  if (input.requestedQty === 'semua' || input.requestedQty === 'maks') {
    const maxCalc = hitungJumlahJualMaks(input);
    if (maxCalc.qty <= 0n) {
      return reject('kas pelabuhan tidak cukup untuk membeli 1 unit');
    }
    qty = maxCalc.qty;
    grossValue = maxCalc.grossValue;
    fee = maxCalc.fee;
  } else {
    if (input.requestedQty <= 0n) {
      return reject('jumlah jual harus > 0');
    }
    if (input.requestedQty > input.shipCargoQty) {
      return reject('melebihi muatan kapal yang dimiliki');
    }
    if (input.requestedQty > freeWarehouse) {
      return reject('melebihi sisa kapasitas gudang pelabuhan');
    }
    qty = input.requestedQty;
    grossValue = hitungNilaiKotorJual(
      input.stock,
      qty,
      input.target,
      input.basePrice,
      config,
    );
    if (grossValue > input.portTreasury) {
      return reject('kas pelabuhan tidak mencukupi');
    }
    fee = hitungBiayaPelabuhan(grossValue, config);
  }

  const netPayout = grossValue - fee;
  const newStock = input.stock + qty;
  const newPrice = hitungHarga(newStock, input.target, input.basePrice, config);

  return {
    ok: true,
    executedQty: qty,
    grossValue,
    fee,
    netPlayerDelta: netPayout,
    netTreasuryDelta: -netPayout,
    newStock,
    newPrice,
    newPlayerCoins: input.playerCoins + netPayout,
    newShipCargoQty: input.shipCargoQty - qty,
    newPortTreasury: input.portTreasury - netPayout,
  };
}
