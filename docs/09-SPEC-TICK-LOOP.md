# 09 — Spesifikasi Tick Loop v0.2

Worker adalah satu-satunya penulis keadaan dunia. Dokumen ini menentukan urutan deterministik per tick. Perubahan v0.2: aksi gagal jatuh ke aturan berikutnya (`05`), perawatan dibayar sebelum aksi, kapal `grounded` tetap bisa menjual, satu implementasi tick, kunci advisory pada koneksi khusus.

## Satu implementasi tick
Logika tick adalah fungsi murni `stepWorld(state, rules, config) -> { state, events }` di `packages/econ`. Tiga pemakai:
1. **Worker:** memuat state dari DB, memanggil `stepWorld`, menyimpan hasil dalam satu transaksi.
2. **Simulator `sim:run`:** memanggilnya berulang dengan bot yang menghasilkan program aturan.
3. **Sandbox API:** memanggilnya pada snapshot dengan satu kapal.
Tidak boleh ada logika tick, harga, atau transaksi yang diduplikasi di luar fungsi ini. Tes kesetaraan (`10`) membandingkan `state_hash` ketiganya.

## Penjadwalan
- Interval produksi: `TICK_SECONDS` (awal 30). Mode simulasi: tanpa jeda.
- Penjadwal dengan koreksi drift (`nextRun = start + n * interval`), bukan `setInterval` polos.
- Tick tidak boleh tumpang tindih. Jika tick melebihi interval: lewati jadwal berikutnya, catat `tick_lag`, jangan menumpuk antrean.

## Kunci worker tunggal
- Worker membuka **satu koneksi khusus** yang memegang `pg_try_advisory_lock(<kunci>)` selama hidupnya (bukan dari pool umum, karena kunci sesi hilang saat koneksi dikembalikan atau terputus).
- Gagal mendapat kunci = keluar. Setiap tick, worker memastikan koneksi kunci masih hidup; jika hilang, worker berhenti **sebelum** memulai tick berikutnya.

## Pemulihan setelah restart
- Lanjut dari `max(tick_no) + 1` di `tick_state`.
- **Tidak ada catch-up** untuk waktu mati: dunia membeku selama worker mati. Alasan: adil bagi semua pemain dan sederhana.
- Tick yang tidak sempat commit tidak meninggalkan efek (satu transaksi).

## Urutan satu tick `t`
Semua langkah dalam **satu transaksi** (`READ COMMITTED`; konsistensi dijamin oleh penulis tunggal dan kunci advisory, bukan oleh isolasi SERIALIZABLE).

1. **Muat keadaan:** `market` (termasuk kas pelabuhan), `ships`, `ship_cargo`, `players.coins`, versi aturan aktif.
2. **Produksi dan konsumsi** per (pelabuhan, komoditas). Harga adalah fungsi murni dari stok (`hitungHarga`); kolom `price` diperbarui setiap kali stok berubah, sehingga tidak ada langkah "hitung ulang harga" terpisah.
3. **Pendapatan pelabuhan:** diterapkan di sini hanya jika `06` mendefinisikannya (ditetapkan pada revisi M1). Dicatat sebagai sumber koin.
4. **Kedatangan:** kapal `sailing` dengan `arrive_tick <= t` menjadi `docked` di `dest_port`.
5. **Perawatan kapal (sebelum aksi)**, urutan `ship_id` naik:
   - kapal `docked` atau `sailing` yang tidak `grounded`: jika koin >= `UPKEEP_PER_TICK`, bayar (ledger `upkeep`). Jika koin kurang: kapal `docked` menjadi `grounded`; kapal `sailing` tetap berlayar dan perawatan tick itu dilewati (**tunggakan tidak diakumulasi**)
   - kapal `grounded` tidak ditagih. Jika koin pemain >= `UPKEEP_PER_TICK`, kapal membayar dan kembali `docked` pada tick yang sama
6. **Evaluasi aturan per kapal `docked` atau `grounded`** (termasuk yang baru tiba), urutan adil: daftar diurutkan `ship_id`, lalu diputar sebanyak `t mod N` (N = jumlah kapal). Untuk tiap kapal:
   - evaluasi aturan dari atas; aksi yang gagal dicatat dengan kode (`05`) dan evaluasi lanjut ke aturan berikutnya pada tick yang sama. Penjualan dengan pembayaran bersih `N = G - F = 0` gagal dengan `ZERO_PROCEEDS`, tanpa mengubah stok, muatan, koin, atau kas; aturan berikutnya tetap dievaluasi.
   - kapal `grounded` hanya boleh `jual` dan `tunggu`
   - aksi berhasil **langsung diterapkan** (stok, kas, koin, harga), sehingga kapal berikutnya melihat dampaknya
   - tulis `ledger`, `ship_cargo`, `action_log`
   - `berlayar` menetapkan `sailing`, `dest_port`, `arrive_tick = t + jarak`
7. **Pemulihan darurat** `[ASUMSI, KEPUTUSAN TERBUKA]`: pemain dengan kapal `grounded`, muatan kosong, dan koin < `UPKEEP_PER_TICK` akan macet permanen (tidak bisa jual, tidak bisa beli). Usulan: beri `RESCUE_COINS` (awal 200) maksimal sekali per `RESCUE_COOLDOWN_TICKS` (awal 2.880, sekitar 1 hari), ledger `rescue`, dihitung sebagai sumber koin pada invarian konservasi. Diaktifkan lewat konfigurasi (`RESCUE_ENABLED`); tanpa ini akun yang bangkrut tidak bisa pulih.
8. **Invarian cepat** (dalam transaksi): tidak ada koin, stok, atau kas negatif; muatan <= kapasitas; konservasi uang (`06`). Gagal = **rollback seluruh tick**, catat galat keras, hentikan worker (jangan loncat).
9. Tulis `tick_state` (dengan `state_hash` dan durasi), lalu `COMMIT`.

## `state_hash`
SHA-256 dari JSON kanonik: kunci terurut, array terurut tetap (`market` per port lalu komoditas; `ships`, `ship_cargo`, `players`, `ports` per id), semua `bigint` ditulis sebagai string. Tidak memuat waktu nyata atau ID yang bergantung urutan penyisipan.

## Pembatasan kerja
- Anggaran evaluasi satu kapal 500 node (`05`). Galat satu kapal tidak membatalkan tick.
- Batas waktu per tick: 80% dari interval; terlampaui memicu metrik `tick_lag`.
- Kapal diproses berurutan di MVP.

## Idempotensi dan pengulangan
`tick_state.tick_no` adalah PRIMARY KEY (mencegah tick ganda). Efek tick hanya terjadi di transaksi akhir; pengulangan setelah crash aman.

## Determinisme
Keadaan setelah tick `t` hanya bergantung pada (keadaan sebelum, aturan aktif, konfigurasi, seed). Seed RNG, jika dipakai, = `hash(world_seed, t)`.

## Perubahan aturan di tengah jalan
Aturan baru dari api dipakai mulai tick berikutnya setelah commit; worker membaca versi aktif di langkah 1 dan memakainya sepanjang tick.

## Kasus tepi
| Kasus | Perlakuan |
|---|---|
| Dua kapal mengejar stok terakhir | Yang lebih dulu di urutan putar mendapat; yang kedua `gagal: OUT_OF_STOCK`, lanjut ke aturan berikutnya |
| Kapal tanpa aturan cocok atau semua aksi gagal | `tunggu`, log "tidak ada aturan berhasil" |
| Pemain menghapus semua aturan | Kapal menganggur, tetap kena perawatan |
| Koin habis, muatan masih ada | `grounded`, tetap bisa `jual`, lalu pulih |
| Koin habis, muatan kosong | Butuh pemulihan darurat (langkah 7) |
| Akun dihapus (Fase 2) | Kapal dan muatan dibuang; ledger dipertahankan dan dianonimkan |
| Worker mati lama | Dunia beku; tidak ada catch-up |
| Koneksi kunci advisory hilang | Worker berhenti sebelum tick berikutnya |

## Metrik
`tick_duration_ms`, `tick_lag_ms`, `rules_skipped_total{reason}`, `actions_total{result,code}`, `ships_grounded`, `invariant_failures_total`, `rescue_granted_total`.
