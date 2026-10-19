import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import {
  WORLD_CONFIG,
  COMMODITIES_SEED,
  MARKET_SEED,
} from '@jalur-rempah/shared';
import {
  hitungHarga,
  batasHargaBawah,
  batasHargaAtas,
  stepProduksiKonsumsi,
} from '../src/index.js';

describe('M1 — packages/econ: hitungHarga, Produksi/Konsumsi, & Keseimbangan Seed', () => {
  it('1. Properti: hitungHarga selalu menghasilkan integer >= 1 dan berada dalam [round(dasar*0.25), round(dasar*4.0)]', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 100000n }),
        fc.bigInt({ min: 1n, max: 10000n }),
        fc.bigInt({ min: 1n, max: 5000n }),
        (stok, target, dasar) => {
          const harga = hitungHarga(stok, target, dasar, WORLD_CONFIG);
          const minPrice = batasHargaBawah(dasar, WORLD_CONFIG);
          const maxPrice = batasHargaAtas(dasar, WORLD_CONFIG);

          expect(typeof harga).toBe('bigint');
          expect(harga >= 1n).toBe(true);
          expect(harga >= minPrice).toBe(true);
          expect(harga <= maxPrice).toBe(true);
        },
      ),
      { numRuns: 500 },
    );
  });

  it('2. Properti: hitungHarga monoton tak-naik terhadap kenaikan stok (stok naik -> harga tidak naik)', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 5000n }),
        fc.bigInt({ min: 1n, max: 2000n }),
        fc.bigInt({ min: 1n, max: 5000n }),
        fc.bigInt({ min: 1n, max: 1000n }),
        (stok, deltaStok, target, dasar) => {
          const h1 = hitungHarga(stok, target, dasar, WORLD_CONFIG);
          const h2 = hitungHarga(stok + deltaStok, target, dasar, WORLD_CONFIG);
          expect(h2 <= h1).toBe(true);
        },
      ),
      { numRuns: 500 },
    );
  });

  it('3. Kasus tepi harga: stok == target menghasilkan dasar, stok == 0 menyentuh clamp atas (4.0x), stok sangat besar menyentuh clamp bawah (0.25x)', () => {
    for (const dasar of [20n, 45n, 70n, 90n]) {
      expect(hitungHarga(400n, 400n, dasar, WORLD_CONFIG)).toBe(dasar);
      expect(hitungHarga(0n, 400n, dasar, WORLD_CONFIG)).toBe(
        batasHargaAtas(dasar, WORLD_CONFIG),
      );
      expect(hitungHarga(100000n, 400n, dasar, WORLD_CONFIG)).toBe(
        batasHargaBawah(dasar, WORLD_CONFIG),
      );
    }
  });

  it('4. Properti stepProduksiKonsumsi: stok baru selalu dalam [0, capacity] dan harga diperbarui konsisten', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 1600n }),
        fc.bigInt({ min: 0n, max: 200n }),
        fc.bigInt({ min: 0n, max: 200n }),
        fc.bigInt({ min: 10n, max: 200n }),
        (stock, production, consumption, basePrice) => {
          const updated = stepProduksiKonsumsi(
            {
              port_id: 1,
              commodity_id: 1,
              stock,
              target: 400n,
              production,
              consumption,
              capacity: 1600n,
              price: basePrice,
            },
            basePrice,
            WORLD_CONFIG,
          );

          expect(updated.stock >= 0n).toBe(true);
          expect(updated.stock <= updated.capacity).toBe(true);
          expect(updated.price).toBe(
            hitungHarga(updated.stock, updated.target, basePrice, WORLD_CONFIG),
          );
        },
      ),
      { numRuns: 500 },
    );
  });

  it('5. Keseimbangan produksi dan konsumsi global pada seed dunia (packages/shared): total_prod == total_cons == 23 untuk tiap komoditas', () => {
    expect(MARKET_SEED.length).toBe(24);
    for (const com of COMMODITIES_SEED) {
      const rows = MARKET_SEED.filter((m) => m.commodity_id === com.id);
      expect(rows.length).toBe(6);
      const totalProd = rows.reduce((acc, r) => acc + r.production, 0n);
      const totalCons = rows.reduce((acc, r) => acc + r.consumption, 0n);
      expect(totalProd).toBe(23n);
      expect(totalCons).toBe(23n);
      expect(totalProd).toBe(totalCons);
    }
  });
});
