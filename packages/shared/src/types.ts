export type CommodityCode = 'pala' | 'cengkeh' | 'garam' | 'kain';

export type PortCode = 'banda' | 'ternate' | 'surabaya' | 'malaka' | 'makassar' | 'batavia';

export type ShipStatus = 'docked' | 'sailing' | 'grounded';

export type LedgerReason = 'starter' | 'buy' | 'sell' | 'port_fee' | 'upkeep';

export type ActionResult = 'ok' | 'gagal' | 'dilewati' | 'menunggu' | 'berlayar';

export interface Commodity {
  id: number;
  code: CommodityCode;
  base_price: bigint;
}

export interface Port {
  id: number;
  code: PortCode;
  name: string;
  treasury: bigint;
  initial_treasury: bigint;
}

export interface Route {
  from_port: number;
  to_port: number;
  ticks: number;
}

export interface MarketRow {
  port_id: number;
  commodity_id: number;
  stock: bigint;
  target: bigint;
  production: bigint;
  consumption: bigint;
  capacity: bigint;
  price: bigint;
}

export interface MarketHistoryRow {
  tick_no: bigint;
  port_id: number;
  commodity_id: number;
  price: bigint;
  stock: bigint;
}

export interface Player {
  id: bigint;
  email: string;
  password_hash: string;
  display_name: string;
  coins: bigint;
  created_at: Date;
}

export interface Ship {
  id: bigint;
  player_id: bigint;
  name: string;
  capacity: number;
  status: ShipStatus;
  port_id: number | null;
  dest_port: number | null;
  arrive_tick: bigint | null;
}

export interface ShipCargo {
  ship_id: bigint;
  commodity_id: number;
  qty: bigint;
}

export interface RuleSet {
  id: bigint;
  ship_id: bigint;
  version: number;
  source: string;
  compiled: Record<string, unknown>;
  ast_version: number;
  created_at: Date;
}

export interface LedgerEntry {
  id: bigint;
  player_id: bigint;
  tick_no: bigint | null;
  delta: bigint;
  reason: LedgerReason | string;
  ref_ship: bigint | null;
  meta: Record<string, unknown> | null;
  created_at: Date;
}

export interface ActionLogEntry {
  id: bigint;
  ship_id: bigint;
  tick_no: bigint;
  rule_name: string | null;
  action: string;
  result: ActionResult;
  detail: string | null;
}

export interface TickState {
  tick_no: bigint;
  started_at: Date;
  finished_at: Date;
  duration_ms: number;
  state_hash: string | null;
}

export interface RefreshToken {
  id: bigint;
  player_id: bigint;
  token_hash: string;
  expires_at: Date;
  revoked: boolean;
}
