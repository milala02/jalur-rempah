# 09 — Spesifikasi Tick Loop v0.1

Worker adalah satu-satunya penulis dunia. Dokumen ini menentukan urutan deterministik per tick.

## Penjadwalan
- Interval produksi: `TICK_SECONDS` (awal 30). Mode simulasi: tanpa jeda.
- Penjadwal: loop dengan koreksi drift (`nextRun = start + n * interval`), bukan `setInterval` polos.
- **Satu worker aktif:** `pg_try_advisory_lock(<kunci>)` saat mulai; gagal = keluar.
- Tick tidak boleh tumpang tindih. Jika tick melebihi interval: lewati jadwal tick berikut, catat `tick_lag`, tidak menumpuk antrean.

## Pemulihan setelah restart
- Baca `max(tick_no)` dari `tick_state`; lanjutkan dari `tick_no + 1`.
- **Tidak ada catch-up** untuk waktu mati: dunia membeku selama worker mati (tick tidak dihitung ulang). Alasan: adil bagi semua pemain, dan sederhana.
- Tick yang tidak sempat commit **tidak meninggalkan efek** (satu transaksi).

## Urutan satu tick `t`
Semua langkah dalam **satu transaksi** (`BEGIN ... COMMIT`), isolasi `SERIALIZABLE` atau `REPEATABLE READ` dengan penguncian eksplisit; worker adalah satu-satunya penulis tabel dunia sehingga konflik tidak diharapkan.

1. **Ambil snapshot:** `market`, `ships`, `ship_cargo`, `players.coins`, aturan aktif.
2. **Produksi dan konsumsi** per (pelabuhan, komoditas) → stok baru.
3. **Hitung ulang harga** dengan `hitungHarga` (satu-satunya sumber harga).
4. **Kedatangan:** kapal `sailing` dengan `arrive_tick <= t` → `docked` di `dest_port`.
5. **Evaluasi aturan per kapal**, urutan **deterministik dan adil**:
   - daftar kapal berstatus `docked` diurutkan `ship_id`, lalu diputar sebanyak `t mod N` (N = jumlah kapal) supaya tidak ada kapal yang selalu duluan
   - tiap kapal: jalankan program → hasil `Aksi` atau `tidak ada`
   - **terapkan aksi langsung** ke keadaan (pasar berubah, harga dihitung ulang setelah transaksi), sehingga kapal berikutnya melihat dampaknya
   - tulis `ledger`, `ship_cargo`, `action_log`
6. **Biaya perawatan:** untuk semua kapal; koin kurang → `grounded` (dan dicatat); koin cukup + kapal `grounded` → kembali `docked`.
7. **Berangkat:** aksi `berlayar` menetapkan `sailing`, `dest_port`, `arrive_tick = t + jarak`.
8. **Harga akhir tick:** hitung ulang untuk pasar yang berubah; simpan `market_history` bila perlu.
9. **Invarian cepat** (dalam transaksi, murah): tidak ada koin/stok negatif; muatan <= kapasitas. Gagal → **rollback seluruh tick**, catat galat keras, hentikan worker (jangan loncat).
10. **Tulis `tick_state`** dengan `state_hash` (hash deterministik dari tabel dunia) dan durasi.
11. `COMMIT`.

## Pembatasan kerja
- Evaluasi aturan satu kapal dibatasi anggaran 500 node (lihat `05`). Galat satu kapal tidak membatalkan tick: aturan dilewati, dicatat.
- Batas waktu per tick: 80% dari interval; terlampaui → peringatan metrik.
- Batas ukuran batch: kapal diproses berurutan di MVP.

## Idempotensi dan pengulangan
- `tick_state.tick_no` PRIMARY KEY mencegah tick ganda.
- Efek tick hanya terjadi di transaksi akhir; pengulangan setelah crash aman.

## Determinisme
Keadaan setelah tick `t` hanya bergantung pada (keadaan sebelum, aturan aktif, konfigurasi, seed). Seed RNG (jika dipakai di masa depan) = `hash(world_seed, t)`.

## Perubahan aturan di tengah jalan
Aturan baru dari api dipakai dari tick **berikutnya setelah commit**; worker membaca versi aktif di langkah 1 dan memakainya sepanjang tick.

## Kasus tepi
| Kasus | Perlakuan |
|---|---|
| Dua kapal mengejar stok terakhir | Yang lebih dulu di urutan putar mendapat; yang kedua `gagal: stok habis` |
| Kapal tanpa aturan cocok | `tunggu`, log "tidak ada aturan cocok" |
| Pemain menghapus semua aturan | Kapal menganggur, tetap kena perawatan |
| Akun dihapus | Kapal dan muatan dibuang, ledger dipertahankan (anonimisasi) |
| Worker mati lama | Dunia beku; tidak ada catch-up |
| Tick melebihi batas waktu | Metrik `tick_lag`; tidak menumpuk |

## Metrik
`tick_duration_ms`, `tick_lag_ms`, `rules_skipped_total{reason}`, `actions_total{result}`, `ships_grounded`, `invariant_failures_total`.
