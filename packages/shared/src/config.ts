export interface WorldEconomyConfig {
  readonly DEFAULT_TARGET: bigint;
  readonly DEFAULT_CAPACITY: bigint;
  readonly PRICE_ELASTICITY: number;
  readonly MIN_PRICE_FACTOR: number;
  readonly MAX_PRICE_FACTOR: number;
  readonly PORT_FEE_PERCENT: number;
  readonly PORT_FEE_MIN: bigint;
  readonly UPKEEP_PER_TICK: bigint;
  readonly WEALTH_UPKEEP_BPS: number;
  readonly STARTER_COINS: bigint;
  readonly STARTER_SHIP_CAPACITY: number;
  readonly INITIAL_PORT_TREASURY: bigint;
  readonly PORT_INCOME_ENABLED: boolean;
  readonly PORT_TREASURY_FLOOR: bigint;
  readonly PORT_TREASURY_RESTORE_DIVISOR: bigint;
  readonly RESCUE_ENABLED: boolean;
  readonly RESCUE_COINS: bigint;
  readonly RESCUE_COOLDOWN_TICKS: number;
  readonly DEMAND_SHOCK_ENABLED: boolean;
  readonly DEMAND_SHOCK_INTERVAL_TICKS: number;
  readonly DEMAND_SHOCK_MAGNITUDE: bigint;
  readonly SCALE_MARKET_WITH_FLEET: boolean;
  readonly UPKEEP_LEDGER_BATCH_TICKS: number;
  readonly TICK_SECONDS: number;
}

/**
 * Parameter baseline awal sebelum revisi M1 (tanpa pendapatan pelabuhan, kas 50.000, kapasitas 20).
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
  WEALTH_UPKEEP_BPS: 0,
  STARTER_COINS: 1000n,
  STARTER_SHIP_CAPACITY: 20,
  INITIAL_PORT_TREASURY: 50000n,
  PORT_INCOME_ENABLED: false,
  PORT_TREASURY_FLOOR: 10000n,
  PORT_TREASURY_RESTORE_DIVISOR: 20n,
  RESCUE_ENABLED: false,
  RESCUE_COINS: 200n,
  RESCUE_COOLDOWN_TICKS: 2880,
  DEMAND_SHOCK_ENABLED: false,
  DEMAND_SHOCK_INTERVAL_TICKS: 40,
  DEMAND_SHOCK_MAGNITUDE: 12n,
  SCALE_MARKET_WITH_FLEET: false,
  UPKEEP_LEDGER_BATCH_TICKS: 120,
  TICK_SECONDS: 30,
} as const;

/**
 * Parameter dunia hasil revisi M1 (kas awal pelabuhan wajar 50.000 = 6x modal 50 pemain <= 10x,
 * pendapatan domestik pelabuhan aktif, aturan tick v0.2, stabil pada horizon 200.000+ tick).
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
  WEALTH_UPKEEP_BPS: 4,
  STARTER_COINS: 1000n,
  STARTER_SHIP_CAPACITY: 35,
  INITIAL_PORT_TREASURY: 50000n,
  PORT_INCOME_ENABLED: true,
  PORT_TREASURY_FLOOR: 22000n,
  PORT_TREASURY_RESTORE_DIVISOR: 2n,
  RESCUE_ENABLED: true,
  RESCUE_COINS: 200n,
  RESCUE_COOLDOWN_TICKS: 2880,
  DEMAND_SHOCK_ENABLED: true,
  DEMAND_SHOCK_INTERVAL_TICKS: 40,
  DEMAND_SHOCK_MAGNITUDE: 5n,
  SCALE_MARKET_WITH_FLEET: true,
  UPKEEP_LEDGER_BATCH_TICKS: 120,
  TICK_SECONDS: 30,
} as const;
