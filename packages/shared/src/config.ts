export interface WorldEconomyConfig {
  readonly DEFAULT_TARGET: bigint;
  readonly DEFAULT_CAPACITY: bigint;
  readonly PRICE_ELASTICITY: number;
  readonly MIN_PRICE_FACTOR: number;
  readonly MAX_PRICE_FACTOR: number;
  readonly PORT_FEE_PERCENT: number;
  readonly PORT_FEE_MIN: bigint;
  readonly UPKEEP_PER_TICK: bigint;
  readonly STARTER_COINS: bigint;
  readonly STARTER_SHIP_CAPACITY: number;
  readonly INITIAL_PORT_TREASURY: bigint;
  readonly TICK_SECONDS: number;
}

/**
 * Parameter baseline awal sebelum tuning M1 (disimpan untuk reproduksibilitas perbandingan).
 */
export const UNTUNED_WORLD_CONFIG: WorldEconomyConfig = {
  DEFAULT_TARGET: 400n,
  DEFAULT_CAPACITY: 1600n,
  PRICE_ELASTICITY: 0.6,
  MIN_PRICE_FACTOR: 0.25,
  MAX_PRICE_FACTOR: 4.0,
  PORT_FEE_PERCENT: 2,
  PORT_FEE_MIN: 1n,
  UPKEEP_PER_TICK: 1n,
  STARTER_COINS: 1000n,
  STARTER_SHIP_CAPACITY: 20,
  INITIAL_PORT_TREASURY: 50000n,
  TICK_SECONDS: 30,
} as const;

/**
 * Parameter dunia hasil tuning M1 (50 bot x 10.000 tick x 5 seed lulus semua gerbang).
 * - STARTER_SHIP_CAPACITY: 20 -> 45 (agar kapasitas angkut armada 50 kapal >= 68 unit/tick surplus produksi)
 * - INITIAL_PORT_TREASURY: 50.000 -> 25.000.000 (agar likuiditas pelabuhan konsumen murni seperti Batavia cukup menyerap impor selama >= 10.000 tick)
 */
export const WORLD_CONFIG: WorldEconomyConfig = {
  DEFAULT_TARGET: 400n,
  DEFAULT_CAPACITY: 1600n,
  PRICE_ELASTICITY: 0.6,
  MIN_PRICE_FACTOR: 0.25,
  MAX_PRICE_FACTOR: 4.0,
  PORT_FEE_PERCENT: 2,
  PORT_FEE_MIN: 1n,
  UPKEEP_PER_TICK: 1n,
  STARTER_COINS: 1000n,
  STARTER_SHIP_CAPACITY: 45,
  INITIAL_PORT_TREASURY: 25000000n,
  TICK_SECONDS: 30,
} as const;
