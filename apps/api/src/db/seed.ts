import pg from 'pg';
import {
  COMMODITIES_SEED,
  PORTS_SEED,
  ROUTES_SEED,
  MARKET_SEED,
} from '@jalur-rempah/shared';
import { getPool, closePool } from './connection.js';

export interface CountrySeedRow {
  readonly id: number;
  readonly code: string;
  readonly name: string;
  readonly region: string;
  readonly min_level_required: number;
}

export interface GlobalPortSeedRow {
  readonly id: number;
  readonly code: string;
  readonly name: string;
  readonly country_code: string;
  readonly min_level_required: number;
  readonly map_x: number;
  readonly map_y: number;
}

export interface GlobalCommoditySeedRow {
  readonly id: number;
  readonly code: string;
  readonly name: string;
  readonly base_price: bigint;
  readonly country_code: string;
  readonly category: string;
  readonly origin_port_id: number;
  readonly origin_port_code: string;
  readonly min_level_required: number;
}

export interface LegendarySeaRouteSeed {
  readonly code: 'jalur_rempah' | 'jalur_sutra_laut';
  readonly name: string;
  readonly ports: readonly string[];
}

export const LEGENDARY_SEA_ROUTES: Readonly<
  Record<'jalur_rempah' | 'jalur_sutra_laut', readonly string[]>
> = {
  jalur_rempah: ['banda', 'batavia', 'malaka', 'calicut', 'mekkah', 'lisbon'],
  jalur_sutra_laut: ['canton', 'malaka', 'calicut', 'kairo'],
} as const;

export const COUNTRIES_GLOBAL_SEED: readonly CountrySeedRow[] = [
  {
    id: 1,
    code: 'nusantara',
    name: 'Kepulauan Nusantara',
    region: 'Asia Tenggara',
    min_level_required: 1,
  },
  {
    id: 2,
    code: 'malaka_sultanate',
    name: 'Kesultanan Malaka',
    region: 'Selat Malaka',
    min_level_required: 1,
  },
  {
    id: 3,
    code: 'india',
    name: 'India (Pantai Malabar)',
    region: 'Samudra Hindia',
    min_level_required: 2,
  },
  {
    id: 4,
    code: 'tiongkok',
    name: 'Tiongkok (Jalur Sutra Laut)',
    region: 'Asia Timur',
    min_level_required: 3,
  },
  {
    id: 5,
    code: 'arab',
    name: 'Arab',
    region: 'Timur Tengah',
    min_level_required: 4,
  },
  {
    id: 6,
    code: 'jepang',
    name: 'Jepang',
    region: 'Asia Timur',
    min_level_required: 5,
  },
  {
    id: 7,
    code: 'eropa',
    name: 'Eropa',
    region: 'Atlantik & Mediterania',
    min_level_required: 6,
  },
  {
    id: 8,
    code: 'mesir',
    name: 'Mesir',
    region: 'Laut Merah & Afrika Utara',
    min_level_required: 7,
  },
] as const;

export const NUSANTARA_PORT_COORDS: Readonly<
  Record<number, { country_code: string; map_x: number; map_y: number }>
> = {
  1: { country_code: 'nusantara', map_x: 0.8608, map_y: 0.5251 }, // Banda
  2: { country_code: 'nusantara', map_x: 0.8538, map_y: 0.4956 }, // Ternate
  3: { country_code: 'nusantara', map_x: 0.8132, map_y: 0.5403 }, // Surabaya
  4: { country_code: 'malaka_sultanate', map_x: 0.7840, map_y: 0.4878 }, // Malaka
  5: { country_code: 'nusantara', map_x: 0.8318, map_y: 0.5286 }, // Makassar
  6: { country_code: 'nusantara', map_x: 0.7967, map_y: 0.5343 }, // Batavia
};

export const INTERNATIONAL_PORTS_SEED: readonly GlobalPortSeedRow[] = [
  {
    id: 7,
    code: 'mekkah',
    name: 'Mekkah',
    country_code: 'arab',
    min_level_required: 4,
    map_x: 0.6106,
    map_y: 0.3810,
  },
  {
    id: 8,
    code: 'sakai',
    name: 'Sakai',
    country_code: 'jepang',
    min_level_required: 5,
    map_x: 0.8763,
    map_y: 0.3079,
  },
  {
    id: 9,
    code: 'lisbon',
    name: 'Lisbon',
    country_code: 'eropa',
    min_level_required: 6,
    map_x: 0.4746,
    map_y: 0.2849,
  },
  {
    id: 10,
    code: 'kairo',
    name: 'Kairo',
    country_code: 'mesir',
    min_level_required: 7,
    map_x: 0.5868,
    map_y: 0.3331,
  },
  {
    id: 11,
    code: 'calicut',
    name: 'Calicut',
    country_code: 'india',
    min_level_required: 2,
    map_x: 0.7105,
    map_y: 0.4375,
  },
  {
    id: 12,
    code: 'canton',
    name: 'Canton',
    country_code: 'tiongkok',
    min_level_required: 3,
    map_x: 0.8146,
    map_y: 0.3715,
  },
] as const;

export const INTERNATIONAL_COMMODITIES_SEED: readonly GlobalCommoditySeedRow[] =
  [
    {
      id: 5,
      code: 'kuda_arab',
      name: 'Kuda Arab',
      base_price: 350n,
      country_code: 'arab',
      category: 'Mewah',
      origin_port_id: 7,
      origin_port_code: 'mekkah',
      min_level_required: 4,
    },
    {
      id: 6,
      code: 'kemenyan',
      name: 'Kemenyan',
      base_price: 180n,
      country_code: 'arab',
      category: 'Aromatik',
      origin_port_id: 7,
      origin_port_code: 'mekkah',
      min_level_required: 4,
    },
    {
      id: 7,
      code: 'katana',
      name: 'Katana',
      base_price: 520n,
      country_code: 'jepang',
      category: 'Senjata',
      origin_port_id: 8,
      origin_port_code: 'sakai',
      min_level_required: 5,
    },
    {
      id: 8,
      code: 'tembaga',
      name: 'Tembaga',
      base_price: 240n,
      country_code: 'jepang',
      category: 'Tambang',
      origin_port_id: 8,
      origin_port_code: 'sakai',
      min_level_required: 5,
    },
    {
      id: 9,
      code: 'meriam',
      name: 'Meriam',
      base_price: 850n,
      country_code: 'eropa',
      category: 'Senjata',
      origin_port_id: 9,
      origin_port_code: 'lisbon',
      min_level_required: 6,
    },
    {
      id: 10,
      code: 'kaca',
      name: 'Kaca',
      base_price: 420n,
      country_code: 'eropa',
      category: 'Mewah',
      origin_port_id: 9,
      origin_port_code: 'lisbon',
      min_level_required: 6,
    },
    {
      id: 11,
      code: 'kapas_mesir',
      name: 'Kapas Mesir',
      base_price: 600n,
      country_code: 'mesir',
      category: 'Tekstil',
      origin_port_id: 10,
      origin_port_code: 'kairo',
      min_level_required: 7,
    },
    {
      id: 12,
      code: 'emas_batangan',
      name: 'Emas Batangan',
      base_price: 1500n,
      country_code: 'mesir',
      category: 'Tambang',
      origin_port_id: 10,
      origin_port_code: 'kairo',
      min_level_required: 7,
    },
  ] as const;

export async function seedWorld(pool: pg.Pool = getPool()): Promise<void> {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // 1. Seed Core Commodities terlebih dahulu (menjaga perilaku error 42P01 pada public.commodities bila belum dimigrasi)
    for (const com of COMMODITIES_SEED) {
      await client.query(
        `INSERT INTO public.commodities (id, code, base_price)
         VALUES ($1, $2, $3)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code, base_price = EXCLUDED.base_price;`,
        [com.id, com.code, com.base_price.toString()],
      );
    }

    // 2. Seed 8 Negara (Fase 5: countries)
    for (const c of COUNTRIES_GLOBAL_SEED) {
      await client.query(
        `INSERT INTO public.countries (id, code, name, region, min_level_required)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code,
             name = EXCLUDED.name,
             region = EXCLUDED.region,
             min_level_required = EXCLUDED.min_level_required;`,
        [c.id, c.code, c.name, c.region, c.min_level_required],
      );
    }

    // 3. Seed Ports Nusantara (id 1..6) beserta koordinat Equirectangular X/Y dan min_level_required = 1
    for (const port of PORTS_SEED) {
      const meta = NUSANTARA_PORT_COORDS[port.id] ?? {
        country_code: 'nusantara',
        map_x: 0.5,
        map_y: 0.5,
      };
      await client.query(
        `INSERT INTO public.ports (id, code, name, treasury, initial_treasury, country_code, min_level_required, map_x, map_y)
         VALUES ($1, $2, $3, $4, $5, $6, 1, $7, $8)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code,
             name = EXCLUDED.name,
             treasury = EXCLUDED.treasury,
             initial_treasury = EXCLUDED.initial_treasury,
             country_code = EXCLUDED.country_code,
             min_level_required = EXCLUDED.min_level_required,
             map_x = EXCLUDED.map_x,
             map_y = EXCLUDED.map_y;`,
        [
          port.id,
          port.code,
          port.name,
          port.treasury.toString(),
          port.initial_treasury.toString(),
          meta.country_code,
          meta.map_x,
          meta.map_y,
        ],
      );
    }

    // 4. Seed Pelabuhan Internasional (Mekkah, Sakai, Lisbon, Kairo, Calicut, Canton)
    //    treasury = 0 & initial_treasury = 0 agar audit konservasi uang simulasi Nusantara (id 1..6) tetap utuh
    for (const ip of INTERNATIONAL_PORTS_SEED) {
      await client.query(
        `INSERT INTO public.ports (id, code, name, treasury, initial_treasury, country_code, min_level_required, map_x, map_y)
         VALUES ($1, $2, $3, 0, 0, $4, $5, $6, $7)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code,
             name = EXCLUDED.name,
             country_code = EXCLUDED.country_code,
             min_level_required = EXCLUDED.min_level_required,
             map_x = EXCLUDED.map_x,
             map_y = EXCLUDED.map_y;`,
        [
          ip.id,
          ip.code,
          ip.name,
          ip.country_code,
          ip.min_level_required,
          ip.map_x,
          ip.map_y,
        ],
      );
    }

    // 5. Lengkapi metadata komoditas Nusantara (id 1..4) & seed 8 Komoditas Eksklusif Internasional (id 5..12)
    const coreComMeta: Readonly<
      Record<
        number,
        {
          name: string;
          country_code: string;
          category: string;
          origin_port_id: number;
          origin_port_code: string;
        }
      >
    > = {
      1: {
        name: 'Pala',
        country_code: 'nusantara',
        category: 'Rempah',
        origin_port_id: 1,
        origin_port_code: 'banda',
      },
      2: {
        name: 'Cengkeh',
        country_code: 'nusantara',
        category: 'Rempah',
        origin_port_id: 2,
        origin_port_code: 'ternate',
      },
      3: {
        name: 'Garam',
        country_code: 'nusantara',
        category: 'Pangan',
        origin_port_id: 3,
        origin_port_code: 'surabaya',
      },
      4: {
        name: 'Kain',
        country_code: 'malaka_sultanate',
        category: 'Tekstil',
        origin_port_id: 4,
        origin_port_code: 'malaka',
      },
    };

    for (const com of COMMODITIES_SEED) {
      const m = coreComMeta[com.id]!;
      await client.query(
        `UPDATE public.commodities
         SET name = $1,
             country_code = $2,
             category = $3,
             origin_port_id = $4,
             origin_port_code = $5,
             min_level_required = 1
         WHERE id = $6`,
        [
          m.name,
          m.country_code,
          m.category,
          m.origin_port_id,
          m.origin_port_code,
          com.id,
        ],
      );
    }

    for (const ic of INTERNATIONAL_COMMODITIES_SEED) {
      await client.query(
        `INSERT INTO public.commodities (
           id, code, name, base_price, country_code, category,
           origin_port_id, origin_port_code, min_level_required
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code,
             name = EXCLUDED.name,
             base_price = EXCLUDED.base_price,
             country_code = EXCLUDED.country_code,
             category = EXCLUDED.category,
             origin_port_id = EXCLUDED.origin_port_id,
             origin_port_code = EXCLUDED.origin_port_code,
             min_level_required = EXCLUDED.min_level_required;`,
        [
          ic.id,
          ic.code,
          ic.name,
          ic.base_price.toString(),
          ic.country_code,
          ic.category,
          ic.origin_port_id,
          ic.origin_port_code,
          ic.min_level_required,
        ],
      );
    }

    // 6. Seed Routes
    for (const route of ROUTES_SEED) {
      await client.query(
        `INSERT INTO public.routes (from_port, to_port, ticks)
         VALUES ($1, $2, $3)
         ON CONFLICT (from_port, to_port) DO UPDATE
         SET ticks = EXCLUDED.ticks;`,
        [route.from_port, route.to_port, route.ticks],
      );
    }

    // 7. Seed Market
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

    // 8. Seed Daily Quests (Fase 7: quests)
    const dailyQuests = [
      {
        id: 1,
        code: 'first_trade',
        title: 'Perdagangan Pertama',
        description: 'Beli atau jual total 10 unit komoditas di pasar atau bursa.',
        type: 'trade',
        target_value: 10,
        reward_coins: 120,
        reward_xp: 150,
      },
      {
        id: 2,
        code: 'pirate_hunter',
        title: 'Pemburu Bajak Laut',
        description: 'Menangkan 1 pertempuran laut melawan armada Bajak Laut.',
        type: 'combat_win',
        target_value: 1,
        reward_coins: 200,
        reward_xp: 250,
      },
      {
        id: 3,
        code: 'first_code',
        title: 'Kode Pertama',
        description: 'Simpan 1 aturan otomatisasi Bahasa Aturan (DSL) pada kapalmu.',
        type: 'save_dsl',
        target_value: 1,
        reward_coins: 100,
        reward_xp: 120,
      },
    ];
    for (const q of dailyQuests) {
      await client.query(
        `INSERT INTO public.quests (id, code, title, description, type, target_value, reward_coins, reward_xp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (id) DO UPDATE
         SET code = EXCLUDED.code,
             title = EXCLUDED.title,
             description = EXCLUDED.description,
             type = EXCLUDED.type,
             target_value = EXCLUDED.target_value,
             reward_coins = EXCLUDED.reward_coins,
             reward_xp = EXCLUDED.reward_xp;`,
        [q.id, q.code, q.title, q.description, q.type, q.target_value, q.reward_coins, q.reward_xp],
      );
    }

    await client.query('COMMIT');
    console.log(
      `[SEED] Berhasil seed dunia: ${COUNTRIES_GLOBAL_SEED.length} negara, ${COMMODITIES_SEED.length + INTERNATIONAL_COMMODITIES_SEED.length} komoditas, ${PORTS_SEED.length + INTERNATIONAL_PORTS_SEED.length} pelabuhan, ${ROUTES_SEED.length} rute, ${MARKET_SEED.length} pasar.`,
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