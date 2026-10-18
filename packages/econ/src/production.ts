import {
  MarketRow,
  WORLD_CONFIG,
  WorldEconomyConfig,
} from '@jalur-rempah/shared';
import { hitungHarga } from './price.js';

/**
 * Produksi dan konsumsi per tick (docs/06):
 * stok += produksi
 * stok -= min(konsumsi, stok)
 * stok  = min(stok, kapasitasGudang)
 */
export function stepProduksiKonsumsi(
  row: MarketRow,
  dasar: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): MarketRow {
  const afterProd = row.stock + row.production;
  const consumed = row.consumption < afterProd ? row.consumption : afterProd;
  const afterCons = afterProd - consumed;
  const newStock = afterCons < row.capacity ? afterCons : row.capacity;
  const newPrice = hitungHarga(newStock, row.target, dasar, config);

  return {
    ...row,
    stock: newStock,
    price: newPrice,
  };
}
