import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { WORLD_CONFIG } from '@jalur-rempah/shared';
import {
  hitungHarga,
  hitungBiayaPelabuhan,
  hitungJumlahBeliMaks,
  hitungJumlahJualMaks,
  eksekusiBeli,
  eksekusiJual,
  periksaInvarianEkonomi,
} from '../src/index.js';

describe('M1 — packages/econ: Transaksi Simetris, Beli(maks)/Jual(semua), & Konservasi Uang', () => {
  it('1. Properti Simetri Beli-lalu-Jual: untuk n acak 1..500 dan stok awal acak, beli n lalu jual n selalu memakai kumpulan harga identik dan rugi tepat 2x biaya', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 1n, max: 500n }),
        fc.bigInt({ min: 0n, max: 2500n }),
        fc.bigInt({ min: 50n, max: 1000n }),
        fc.bigInt({ min: 1n, max: 200n }),
        (n, extraStock, target, basePrice) => {
          const initialStock = n + extraStock;
          const capacity = initialStock + 1000n;
          const initialCoins = 10_000_000n;
          const initialTreasury = 10_000_000n;

          const buyRes = eksekusiBeli({
            stock: initialStock,
            target,
            basePrice,
            capacity,
            playerCoins: initialCoins,
            shipCargoQty: 0n,
            shipTotalCargo: 0n,
            shipCapacity: 1000,
            portTreasury: initialTreasury,
            requestedQty: n,
            config: WORLD_CONFIG,
          });

          expect(buyRes.ok).toBe(true);
          expect(buyRes.executedQty).toBe(n);
          expect(buyRes.newStock).toBe(initialStock - n);

          const sellRes = eksekusiJual({
            stock: buyRes.newStock,
            target,
            basePrice,
            capacity,
            playerCoins: buyRes.newPlayerCoins,
            shipCargoQty: buyRes.newShipCargoQty,
            shipTotalCargo: buyRes.newShipCargoQty,
            shipCapacity: 1000,
            portTreasury: buyRes.newPortTreasury,
            requestedQty: n,
            config: WORLD_CONFIG,
          });

          expect(sellRes.ok).toBe(true);
          expect(sellRes.executedQty).toBe(n);
          expect(sellRes.newStock).toBe(initialStock);

          // Kumpulan harga identik -> nilai kotor beli == nilai kotor jual
          expect(sellRes.grossValue).toBe(buyRes.grossValue);
          expect(sellRes.fee).toBe(buyRes.fee);

          // Selalu rugi tepat sebesar biaya beli + biaya jual (>= 2 koin)
          const totalLoss = initialCoins - sellRes.newPlayerCoins;
          expect(totalLoss).toBe(buyRes.fee + sellRes.fee);
          expect(totalLoss >= 2n).toBe(true);

          // Konservasi uang: kehilangan pemain == kenaikan kas pelabuhan
          const treasuryGain = sellRes.newPortTreasury - initialTreasury;
          expect(treasuryGain).toBe(totalLoss);
        },
      ),
      { numRuns: 500 },
    );
  });

  it('2. Kasus Tepi Simetri di Batas Clamp Harga (0.25x dan 4.0x) serta Pembulatan Integer untuk n = 1..500', () => {
    // Rezim 4.0x (stok sangat rendah relatif target besar) & rezim 0.25x (stok sangat tinggi relatif target kecil)
    const edgeCases = [
      { stock: 500n, target: 50000n, basePrice: 17n, n: 500n }, // Semua unit menempel di clamp 4.0x
      { stock: 5000n, target: 10n, basePrice: 19n, n: 500n }, // Semua unit menempel di clamp 0.25x
      { stock: 600n, target: 400n, basePrice: 70n, n: 500n }, // Melintasi tengah kurva hingga dekat clamp 4.0x
      { stock: 1n, target: 400n, basePrice: 1n, n: 1n }, // Harga dasar minimum 1 koin, 1 unit
    ];

    for (const tc of edgeCases) {
      const buyRes = eksekusiBeli({
        stock: tc.stock,
        target: tc.target,
        basePrice: tc.basePrice,
        capacity: 10000n,
        playerCoins: 50_000_000n,
        shipCargoQty: 0n,
        shipTotalCargo: 0n,
        shipCapacity: 1000,
        portTreasury: 50_000_000n,
        requestedQty: tc.n,
        config: WORLD_CONFIG,
      });
      expect(buyRes.ok).toBe(true);

      const sellRes = eksekusiJual({
        stock: buyRes.newStock,
        target: tc.target,
        basePrice: tc.basePrice,
        capacity: 10000n,
        playerCoins: buyRes.newPlayerCoins,
        shipCargoQty: buyRes.newShipCargoQty,
        shipTotalCargo: buyRes.newShipCargoQty,
        shipCapacity: 1000,
        portTreasury: buyRes.newPortTreasury,
        requestedQty: tc.n,
        config: WORLD_CONFIG,
      });
      expect(sellRes.ok).toBe(true);
      expect(sellRes.grossValue).toBe(buyRes.grossValue);
      expect(sellRes.newPlayerCoins).toBe(
        50_000_000n - buyRes.fee - sellRes.fee,
      );
      expect(sellRes.newPlayerCoins < 50_000_000n).toBe(true);
    }
  });

  it('3. Kasus Tepi beli(maks) dan jual(semua): koin kurang, muatan penuh, stok habis, kas pelabuhan kosong/terbatas', () => {
    // 3.1 Koin kurang untuk 1 unit pun (harga pala di stok 400 = 70, biaya = 2, butuh 72 koin; pemain hanya punya 71)
    const kurangKoin = eksekusiBeli({
      stock: 400n,
      target: 400n,
      basePrice: 70n,
      capacity: 1600n,
      playerCoins: 71n,
      shipCargoQty: 0n,
      shipTotalCargo: 0n,
      shipCapacity: 20,
      portTreasury: 50000n,
      requestedQty: 'maks',
      config: WORLD_CONFIG,
    });
    expect(kurangKoin.ok).toBe(false);
    expect(kurangKoin.executedQty).toBe(0n);
    expect(kurangKoin.newPlayerCoins).toBe(71n);

    // 3.2 Koin pas untuk tepat 1 unit (72 koin)
    const pasSatuUnit = eksekusiBeli({
      stock: 400n,
      target: 400n,
      basePrice: 70n,
      capacity: 1600n,
      playerCoins: 72n,
      shipCargoQty: 0n,
      shipTotalCargo: 0n,
      shipCapacity: 20,
      portTreasury: 50000n,
      requestedQty: 'maks',
      config: WORLD_CONFIG,
    });
    expect(pasSatuUnit.ok).toBe(true);
    expect(pasSatuUnit.executedQty).toBe(1n);
    expect(pasSatuUnit.newPlayerCoins).toBe(0n);

    // 3.3 Muatan kapal sudah penuh (shipTotalCargo == shipCapacity)
    const muatanPenuh = eksekusiBeli({
      stock: 400n,
      target: 400n,
      basePrice: 70n,
      capacity: 1600n,
      playerCoins: 10000n,
      shipCargoQty: 20n,
      shipTotalCargo: 20n,
      shipCapacity: 20,
      portTreasury: 50000n,
      requestedQty: 'maks',
      config: WORLD_CONFIG,
    });
    expect(muatanPenuh.ok).toBe(false);
    expect(muatanPenuh.executedQty).toBe(0n);

    // 3.4 Kas pelabuhan kosong (portTreasury == 0) saat jual(semua)
    const kasKosong = eksekusiJual({
      stock: 400n,
      target: 400n,
      basePrice: 70n,
      capacity: 1600n,
      playerCoins: 500n,
      shipCargoQty: 10n,
      shipTotalCargo: 10n,
      shipCapacity: 20,
      portTreasury: 0n,
      requestedQty: 'semua',
      config: WORLD_CONFIG,
    });
    expect(kasKosong.ok).toBe(false);
    expect(kasKosong.executedQty).toBe(0n);
    expect(kasKosong.newPortTreasury).toBe(0n);
    expect(kasKosong.newShipCargoQty).toBe(10n);

    // 3.5 Kas pelabuhan terbatas (hanya cukup membeli sebagian muatan kapal)
    const hargaUnitPertama = hitungHarga(401n, 400n, 70n, WORLD_CONFIG);
    const hargaUnitKedua = hitungHarga(402n, 400n, 70n, WORLD_CONFIG);
    const kasPasDuaUnit = hargaUnitPertama + hargaUnitKedua;

    const kasTerbatas = eksekusiJual({
      stock: 400n,
      target: 400n,
      basePrice: 70n,
      capacity: 1600n,
      playerCoins: 500n,
      shipCargoQty: 10n,
      shipTotalCargo: 10n,
      shipCapacity: 20,
      portTreasury: kasPasDuaUnit,
      requestedQty: 'semua',
      config: WORLD_CONFIG,
    });
    expect(kasTerbatas.ok).toBe(true);
    expect(kasTerbatas.executedQty).toBe(2n);
    expect(kasTerbatas.newShipCargoQty).toBe(8n);
    expect(kasTerbatas.newPortTreasury >= 0n).toBe(true);
  });

  it('4. Properti Optimality Binary Search beli(maks) dan jual(semua): n yang dipilih selalu maksimal yang sah', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 800n }),
        fc.bigInt({ min: 0n, max: 20000n }),
        fc.integer({ min: 1, max: 100 }),
        fc.bigInt({ min: 0n, max: 50n }),
        (stock, playerCoins, shipCapacity, currentCargo) => {
          const cargo =
            currentCargo > BigInt(shipCapacity)
              ? BigInt(shipCapacity)
              : currentCargo;
          const res = hitungJumlahBeliMaks({
            stock,
            target: 400n,
            basePrice: 70n,
            capacity: 1600n,
            playerCoins,
            shipCargoQty: cargo,
            shipTotalCargo: cargo,
            shipCapacity,
            portTreasury: 50000n,
            config: WORLD_CONFIG,
          });

          const maxPhysical =
            stock < BigInt(shipCapacity) - cargo
              ? stock
              : BigInt(shipCapacity) - cargo;
          expect(res.qty <= maxPhysical).toBe(true);
          expect(res.totalCost <= playerCoins).toBe(true);

          // Jika masih ada ruang fisik (res.qty < maxPhysical), maka menambah 1 unit lagi PASTI melebihi playerCoins
          if (res.qty < maxPhysical) {
            const nextPrice = hitungHarga(
              stock - res.qty,
              400n,
              70n,
              WORLD_CONFIG,
            );
            const nextGross = res.grossValue + nextPrice;
            const nextTotal =
              nextGross + hitungBiayaPelabuhan(nextGross, WORLD_CONFIG);
            expect(nextTotal > playerCoins).toBe(true);
          }
        },
      ),
      { numRuns: 300 },
    );

    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 1550n }),
        fc.bigInt({ min: 0n, max: 15000n }),
        fc.bigInt({ min: 0n, max: 80n }),
        (stock, portTreasury, shipCargoQty) => {
          const res = hitungJumlahJualMaks({
            stock,
            target: 400n,
            basePrice: 70n,
            capacity: 1600n,
            playerCoins: 1000n,
            shipCargoQty,
            shipTotalCargo: shipCargoQty,
            shipCapacity: 100,
            portTreasury,
            config: WORLD_CONFIG,
          });

          const freeWarehouse = 1600n - stock;
          const maxPhysical =
            shipCargoQty < freeWarehouse ? shipCargoQty : freeWarehouse;
          expect(res.qty <= maxPhysical).toBe(true);
          expect(res.grossValue <= portTreasury).toBe(true);

          if (res.qty < maxPhysical) {
            const nextPrice = hitungHarga(
              stock + res.qty + 1n,
              400n,
              70n,
              WORLD_CONFIG,
            );
            const nextGross = res.grossValue + nextPrice;
            expect(nextGross > portTreasury).toBe(true);
          }
        },
      ),
      { numRuns: 300 },
    );
  });

  it('5. Properti Konservasi Uang Global: untuk urutan acak beli, jual, dan perawatan kapal (upkeep), total_koin_pemain + total_kas_pelabuhan + upkeep_kumulatif == total_awal', () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            kind: fc.constantFrom('buy', 'sell', 'upkeep'),
            qty: fc.bigInt({ min: 1n, max: 15n }),
          }),
          { minLength: 1, maxLength: 60 },
        ),
        (ops) => {
          const initialPlayerCoins = 5000n;
          const initialPortTreasury = 50000n;
          let playerCoins = initialPlayerCoins;
          let portTreasury = initialPortTreasury;
          let cumulativeUpkeep = 0n;
          let ledgerSum = initialPlayerCoins;
          let stock = 400n;
          let cargo = 0n;
          const shipCapacity = 50;

          for (const op of ops) {
            if (op.kind === 'buy') {
              const res = eksekusiBeli({
                stock,
                target: 400n,
                basePrice: 70n,
                capacity: 1600n,
                playerCoins,
                shipCargoQty: cargo,
                shipTotalCargo: cargo,
                shipCapacity,
                portTreasury,
                requestedQty: op.qty,
                config: WORLD_CONFIG,
              });
              if (res.ok) {
                playerCoins = res.newPlayerCoins;
                portTreasury = res.newPortTreasury;
                stock = res.newStock;
                cargo = res.newShipCargoQty;
                ledgerSum += res.netPlayerDelta;
              }
            } else if (op.kind === 'sell') {
              const res = eksekusiJual({
                stock,
                target: 400n,
                basePrice: 70n,
                capacity: 1600n,
                playerCoins,
                shipCargoQty: cargo,
                shipTotalCargo: cargo,
                shipCapacity,
                portTreasury,
                requestedQty: op.qty,
                config: WORLD_CONFIG,
              });
              if (res.ok) {
                playerCoins = res.newPlayerCoins;
                portTreasury = res.newPortTreasury;
                stock = res.newStock;
                cargo = res.newShipCargoQty;
                ledgerSum += res.netPlayerDelta;
              }
            } else {
              if (playerCoins >= WORLD_CONFIG.UPKEEP_PER_TICK) {
                playerCoins -= WORLD_CONFIG.UPKEEP_PER_TICK;
                cumulativeUpkeep += WORLD_CONFIG.UPKEEP_PER_TICK;
                ledgerSum -= WORLD_CONFIG.UPKEEP_PER_TICK;
              }
            }

            // Periksa invarian setiap langkah
            const check = periksaInvarianEkonomi({
              players: [
                {
                  id: 1n,
                  coins: playerCoins,
                  initialCoins: initialPlayerCoins,
                },
              ],
              ports: [
                {
                  id: 1,
                  treasury: portTreasury,
                  initialTreasury: initialPortTreasury,
                },
              ],
              markets: [
                {
                  portId: 1,
                  commodityId: 1,
                  stock,
                  target: 400n,
                  capacity: 1600n,
                  price: hitungHarga(stock, 400n, 70n, WORLD_CONFIG),
                  basePrice: 70n,
                },
              ],
              ships: [
                {
                  id: 1n,
                  playerId: 1n,
                  capacity: shipCapacity,
                  cargoByCommodity: new Map([[1, cargo]]),
                },
              ],
              ledgerDeltasByPlayer: new Map([[1n, ledgerSum]]),
              cumulativeUpkeepSink: cumulativeUpkeep,
            });

            expect(check.valid).toBe(true);
            expect(check.violations).toEqual([]);
          }
        },
      ),
      { numRuns: 200 },
    );
  });
});
