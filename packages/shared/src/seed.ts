import { Commodity, Port, Route, MarketRow } from './types.js';
import { WORLD_CONFIG, WorldEconomyConfig } from './config.js';

export const COMMODITIES_SEED: readonly Commodity[] = [
  { id: 1, code: 'pala', base_price: 70n },
  { id: 2, code: 'cengkeh', base_price: 90n },
  { id: 3, code: 'garam', base_price: 20n },
  { id: 4, code: 'kain', base_price: 45n },
] as const;

export function buildPortsSeed(config: WorldEconomyConfig = WORLD_CONFIG): Port[] {
  const basePorts = [
    { id: 1, code: 'banda', name: 'Banda' },
    { id: 2, code: 'ternate', name: 'Ternate' },
    { id: 3, code: 'surabaya', name: 'Surabaya' },
    { id: 4, code: 'malaka', name: 'Malaka' },
    { id: 5, code: 'makassar', name: 'Makassar' },
    { id: 6, code: 'batavia', name: 'Batavia' },
  ] as const;

  return basePorts.map((p) => ({
    id: p.id,
    code: p.code,
    name: p.name,
    treasury: config.INITIAL_PORT_TREASURY,
    initial_treasury: config.INITIAL_PORT_TREASURY,
  }));
}

export const PORTS_SEED: readonly Port[] = buildPortsSeed(WORLD_CONFIG);

const BASE_ROUTES = [
  { from_port: 1, to_port: 2, ticks: 5 }, // Banda - Ternate
  { from_port: 1, to_port: 5, ticks: 6 }, // Banda - Makassar
  { from_port: 2, to_port: 5, ticks: 5 }, // Ternate - Makassar
  { from_port: 5, to_port: 3, ticks: 4 }, // Makassar - Surabaya
  { from_port: 3, to_port: 6, ticks: 3 }, // Surabaya - Batavia
  { from_port: 6, to_port: 4, ticks: 4 }, // Batavia - Malaka
  { from_port: 5, to_port: 6, ticks: 6 }, // Makassar - Batavia
] as const;

export const ROUTES_SEED: readonly Route[] = [
  ...BASE_ROUTES,
  ...BASE_ROUTES.map((r) => ({
    from_port: r.to_port,
    to_port: r.from_port,
    ticks: r.ticks,
  })),
];

export function buildMarketSeed(config: WorldEconomyConfig = WORLD_CONFIG): MarketRow[] {
  const rows: MarketRow[] = [];

  for (const port of PORTS_SEED) {
    for (const com of COMMODITIES_SEED) {
      let production = 0n;
      let consumption = 3n;

      if (port.code === 'banda') {
        if (com.code === 'pala') production = 20n;
      } else if (port.code === 'ternate') {
        if (com.code === 'cengkeh') production = 20n;
      } else if (port.code === 'surabaya') {
        if (com.code === 'garam') production = 20n;
      } else if (port.code === 'malaka') {
        if (com.code === 'kain') production = 20n;
      } else if (port.code === 'makassar') {
        production = 3n;
        consumption = 3n;
      } else if (port.code === 'batavia') {
        production = 0n;
        consumption = 8n;
      }

      rows.push({
        port_id: port.id,
        commodity_id: com.id,
        stock: config.DEFAULT_TARGET,
        target: config.DEFAULT_TARGET,
        production,
        consumption,
        capacity: config.DEFAULT_CAPACITY,
        price: com.base_price,
      });
    }
  }

  return rows;
}

export const MARKET_SEED: readonly MarketRow[] = buildMarketSeed(WORLD_CONFIG);
