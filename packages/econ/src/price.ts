import { WORLD_CONFIG, WorldEconomyConfig } from '@jalur-rempah/shared';

/**
 * Satu-satunya fungsi pembulatan ke integer di seluruh codebase (ADR-005).
 * Hanya dipanggil oleh hitungHarga, batasHargaBawah, dan batasHargaAtas.
 */
export function bulatkanHarga(nilai: number): bigint {
  if (!Number.isFinite(nilai) || nilai <= 1) {
    return 1n;
  }
  const rounded = Math.round(nilai);
  return rounded >= 1 ? BigInt(rounded) : 1n;
}

export function batasHargaBawah(
  dasar: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  if (dasar <= 0n) {
    throw new Error(`Harga dasar harus > 0, diterima: ${dasar.toString()}`);
  }
  return bulatkanHarga(Number(dasar) * config.MIN_PRICE_FACTOR);
}

export function batasHargaAtas(
  dasar: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  if (dasar <= 0n) {
    throw new Error(`Harga dasar harus > 0, diterima: ${dasar.toString()}`);
  }
  return bulatkanHarga(Number(dasar) * config.MAX_PRICE_FACTOR);
}

/**
 * Satu-satunya sumber perhitungan harga komoditas di pelabuhan (docs/06).
 * rasio = target / max(stok, 1)
 * harga = round(dasar * clamp(rasio ^ e, MIN_PRICE_FACTOR, MAX_PRICE_FACTOR))
 */
export function hitungHarga(
  stok: bigint,
  target: bigint,
  dasar: bigint,
  config: WorldEconomyConfig = WORLD_CONFIG,
): bigint {
  if (stok < 0n) {
    throw new Error(`Stok tidak boleh negatif: ${stok.toString()}`);
  }
  if (target <= 0n) {
    throw new Error(`Target harus > 0: ${target.toString()}`);
  }
  if (dasar <= 0n) {
    throw new Error(`Harga dasar harus > 0: ${dasar.toString()}`);
  }

  const efektifStok = stok > 1n ? stok : 1n;
  const rasio = Number(target) / Number(efektifStok);
  const pangkat = Math.pow(rasio, config.PRICE_ELASTICITY);
  const faktor = Math.min(
    config.MAX_PRICE_FACTOR,
    Math.max(config.MIN_PRICE_FACTOR, pangkat),
  );

  return bulatkanHarga(Number(dasar) * faktor);
}
