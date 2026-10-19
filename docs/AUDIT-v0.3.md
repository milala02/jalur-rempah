# AUDIT v0.3 — Temuan Dokumen dan Keputusan Terbuka

Tujuan: dokumen cukup akurat agar agen bekerja otomatis dan hasil akhirnya siap CI dan build test. Audit ini mencari kontradiksi dan celah desain sebelum milestone terkait dikerjakan.

## Sudah terbukti salah dan diperbaiki (v0.2, lewat pengujian M1)
1. Eksekusi jual/beli tidak simetris (celah untung di satu pelabuhan): diperbaiki, ADR-009.
2. Produksi seed tidak seimbang (15 vs 23 per komoditas): diperbaiki.
3. Tidak jelas siapa membayar pemain saat menjual: diperbaiki lewat kas pelabuhan.

## Ditemukan pada audit v0.3
| # | Dokumen | Masalah | Perbaikan |
|---|---|---|---|
| 1 | 05 | Aksi gagal menghentikan evaluasi, sehingga kapal macet (misal `beli` terus gagal menghalangi `berlayar`) | Aksi gagal jatuh ke aturan berikutnya; kode kegagalan ditetapkan |
| 2 | 09 | Perawatan ditagih setelah aksi; `beli(maks)` menghabiskan koin, kapal langsung `grounded`, dan `grounded` tidak dievaluasi sehingga tidak bisa menjual: macet permanen | Perawatan sebelum aksi; `grounded` tetap bisa `jual`/`tunggu`; tunggakan tidak diakumulasi |
| 3 | 09 | Akun tanpa koin dan tanpa muatan tidak bisa pulih | Pemulihan darurat diusulkan (keputusan terbuka di bawah) |
| 4 | 03, 08, 09 | Simulator, sandbox API, dan worker berisiko memiliki logika tick berbeda | Satu fungsi `stepWorld`; tes kesetaraan `state_hash` |
| 5 | 08 | Sandbox simulasi di event loop API dapat memblokir semua permintaan | Worker thread, antrean terbatas, 503 `BUSY` |
| 6 | 09 | Kunci advisory pada koneksi pool bisa lepas diam-diam, memungkinkan dua worker | Koneksi khusus yang diperiksa tiap tick |
| 7 | 05 | Evaluator integer aman vs `bigint` di econ tidak terdefinisi | Adapter dan galat `OVERFLOW` |
| 8 | 05 | Kata kunci `maks`/`semua` bisa dipakai di tempat salah; kode galat tak tetap | Validasi dan tabel kode galat |
| 9 | 05 | "Snapshot keadaan" ambigu terhadap dampak kapal lain pada tick yang sama | Dinyatakan: keadaan pada giliran kapal |
| 10 | 08 | Penimpaan aturan dari dua perangkat; refresh token dicuri tanpa deteksi; klien lama tidak bisa dipaksa update | `base_version`, deteksi pemakaian ulang, `min_client_version` |
| 11 | 08 | Aturan awal pemain, templat, health check, format angka tidak terdefinisi | Ditambahkan |
| 12 | 10 | Menyebut Testcontainers; praktik nyata: service container dan database per file tes | Disesuaikan |
| 13 | 13 | Tidak ada definisi "siap CI dan build test" | Definisi Release Candidate |

## Keputusan terbuka (perlu keputusan pemilik)
- [ ] Pemulihan darurat (09 langkah 7): aktifkan atau tidak, dan nilainya
- [ ] Mekanisme pendapatan pelabuhan (06): ditetapkan di revisi M1
- [ ] Verifikasi email di MVP atau ditunda
- [ ] Nama game dan `TICK_SECONDS`
- [ ] Port, database, dan nginx di VPS (12) agar tidak bentrok

## Belum diaudit
`01`, `02`, `11`, `12`. Bagian ini lebih rendah risikonya untuk M2 sampai M5, tetapi tetap perlu ditinjau sebelum M6.

## Batas audit
Audit membaca dokumen, belum menjalankan apa pun. Masalah lain hanya akan muncul saat milestone dikerjakan dan diuji. Gerbang CI per milestone adalah jaring pengaman yang sebenarnya.
