import pg from 'pg';
import {
  COMMODITIES_SEED,
  PORTS_SEED,
  ROUTES_SEED,
  MARKET_SEED,
} from '@jalur-rempah/shared';
import { getPool, closePool } from './connection.js';

export async function seedWorld(pool: pg.Pool = getPool()): Promise<void> {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // 1. Seed Commodities
    for (const com of COMMODITIES_SEED) {
      await client.query(
        `INSERT INTO public.commodities (id, code, base_price)
         VALUES ($1, $2, $3)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code, base_price = EXCLUDED.base_price;`,
        [com.id, com.code, com.base_price.toString()],
      );
    }

    // 2. Seed Ports
    for (const port of PORTS_SEED) {
      await client.query(
        `INSERT INTO public.ports (id, code, name)
         VALUES ($1, $2, $3)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code, name = EXCLUDED.name;`,
        [port.id, port.code, port.name],
      );
    }

    // 3. Seed Routes
    for (const route of ROUTES_SEED) {
      await client.query(
        `INSERT INTO public.routes (from_port, to_port, ticks)
         VALUES ($1, $2, $3)
         ON CONFLICT (from_port, to_port) DO UPDATE
         SET ticks = EXCLUDED.ticks;`,
        [route.from_port, route.to_port, route.ticks],
      );
    }

    // 4. Seed Market
    for (const market of MARKET_SEED) {
      await client.query(
        `INSERT INTO public.market (port_id, commodity_id, stock, target, production, consumption, capacity, price)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (port_id, commodity_id) DO UPDATE
         SET stock = EXCLUDED.stock,
             target = EXCLUDED.target,
             production = EXCLUDED.production,
             consumption = EXCLUDED.consumption,
             capacity = EXCLUDED.capacity,
             price = EXCLUDED.price;`,
        [
          market.port_id,
          market.commodity_id,
          market.stock.toString(),
          market.target.toString(),
          market.production.toString(),
          market.consumption.toString(),
          market.capacity.toString(),
          market.price.toString(),
        ],
      );
    }

    await client.query('COMMIT');
    console.log(
      `[SEED] Berhasil seed dunia: ${COMMODITIES_SEED.length} komoditas, ${PORTS_SEED.length} pelabuhan, ${ROUTES_SEED.length} rute, ${MARKET_SEED.length} pasar.`,
    );
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[SEED] Gagal seed dunia:', err);
    throw err;
  } finally {
    client.release();
  }
}

if (
  process.argv[1] &&
  (process.argv[1].endsWith('seed.ts') || process.argv[1].endsWith('seed.js'))
) {
  seedWorld()
    .then(() => {
      console.log('[SEED] Selesai.');
      return closePool();
    })
    .catch((err) => {
      console.error('[SEED] Error fatal:', err);
      process.exit(1);
    });
}
