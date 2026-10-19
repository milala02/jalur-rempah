# Analisis A4 — Janji Inti Game: Gradien Keahlian ("Aturan Cerdas Harus Menang")

**Tanggal:** 2026-10-19  
**Lingkungan Eksekusi:** VM lokal (`Node.js v18.20.4`, x86_64 Debian GNU/Linux 12)  
**Berkas Data Pendukung:**
- `docs/analisis/data/a4-skill-gradient.json` (perbandingan sebelum vs sesudah perubahan ekonomi pada seed tuning & validasi)
- `docs/analisis/data/d-bot-sensitivity.json` (gradien keahlian pada 10, 25, 50, dan 100 bot)
- `docs/analisis/data/m1-10seeds-50bots.json` (10 seed penuh pada 10.000 tick)

---

## 1. Diagnosis Masalah Awal (`Temuan 5`)

Pada implementasi M1 awal (`before_m1_original_calm` di `docs/analisis/data/a4-skill-gradient.json`), strategi **`naive`** justru menjadi strategi terkaya (atau setara dengan strategi cerdas), dengan **gradien keahlian = `1,00x`** (`bestSmartAvgWealth / naiveAvgWealth = 26.812 / 26.790 = 1,00x`):

| Penyebab Struktural pada M1 Awal | Bukti Data Simulasi (`before_m1_original_calm`) | Dampak pada Strategi |
| :--- | :--- | :--- |
| **1. Bot `naive` diam-diam memakai pencarian semua rute global + informasi stok masa depan** | `naive` mengevaluasi `COMMODITIES_SEED x PORTS_SEED` dan membagi selisih harga dengan jarak tempuh, hampir identik dengan `margin_hunter` | Tidak ada perbedaan nyata antara keputusan `naive` dan `margin_hunter` |
| **2. Harga pasar terlalu tenang di sekitar harga dasar (`volatilityPct ~ 7–8%`)** | Tanpa fluktuasi permintaan lokal, rute penghasil utama (`Banda -> Batavia`, `Ternate -> Batavia`) selalu memiliki margin statis yang sama | Aturan statis sederhana yang hanya menghafal 1 rute tetap memperoleh profit yang sama dengan aturan adaptif |
| **3. Tidak ada penalti kepadatan pelabuhan (kongesti armada) dan tidak ada perhitungan slippage + backhaul pada bot cerdas** | Ketika 10 kapal tiba bersamaan di satu pelabuhan, kapal yang tidak memperhitungkan slippage dan kargo balik (*backhaul*) hanya mengalami sedikit penurunan margin karena kas pelabuhan 25 juta menampung semuanya | Keunggulan analitis dari aturan cerdas tidak terkonversi menjadi keunggulan kekayaan |

---

## 2. Rancangan 3 Strategi Cerdas vs `naive` (`A4`)

Untuk menguji janji inti game secara jujur, kami mendefinisikan **pedagang `naive`** sebagaimana pemain pemula sesungguhnya di `docs/01` (aturan lokal rabun dekat: membeli komoditas lokal yang kelihatan murah `< 0,98x` harga dasar dan berlayar ke tetangga terdekat tanpa memperhitungkan slippage, jarak multi-hop, kepadatan kapal lain, maupun muatan balik), lalu merancang **3 bot cerdas berbeda**:

1. **`margin_hunter` (Pemburu Margin per Tick + Slippage Eksak + Backhaul)**:
   - Menghitung kurva biaya kotor beli `hitungNilaiKotorBeli` dan pendapatan bersih jual `hitungNilaiKotorJual - hitungBiayaPelabuhan` beserta *slippage* ukuran muatannya sendiri.
   - Menambahkan estimasi profit muatan balik (*backhaul*) dari pelabuhan tujuan (`garam`/`kain` dari Jawa/Makassar kembali ke Maluku) dibagi total waktu tempuh `ticks`, dikurangi penalti kongesti kapal lain yang sedang menuju pelabuhan tujuan yang sama (`inboundShips * 28` koin).
2. **`hoarder` (Penimbun Arbitrase Volatilitas & Guncangan Permintaan)**:
   - Mengincar anomali harga tinggi (`destM.price > basePrice * 1,15`) dan kelangkaan stok di pelabuhan tujuan, memprioritaskan margin absolut per pelayaran penuh, serta menahan eksekusi jual jika harga di pelabuhan saat ini sedang tertekan di bawah `1,02x` harga dasar.
3. **`adversarial` (Pencari Arbitrase Multi-Faktor + Anti-Kongesti Ketat + Penguji Eksploit)**:
   - Di samping menjalankan 4 jenis audit eksploitasi setiap tick (arbitrase siklus beli-jual instan, eksploitasi pembulatan 1 unit, *pump-and-dump*, dan *rescue farming*), dalam perdagangan normal bot ini menerapkan bobot anti-kongesti paling tajam (`inboundShips * 42` koin) dan beralih secara dinamis ke pelabuhan yang sedang mengalami lonjakan permintaan.

---

## 3. Perubahan Ekonomi untuk Menciptakan Gradien Bermakna Tanpa Mengorbankan Stabilitas

Kami menambahkan **Guncangan Permintaan Terjadwal Deterministik (*Zero-Sum Deterministic Demand Shock*)** di `packages/econ/src/step-world.ts` (di balik flag konfigurasi `DEMAND_SHOCK_ENABLED = true`, `DEMAND_SHOCK_INTERVAL_TICKS = 40`, `DEMAND_SHOCK_MAGNITUDE = 5n`):
- Setiap blok `40` tick (`epoch = Math.floor(t / 40)`), fungsi hash deterministik berbasis `(epoch, worldSeed)` memilih satu komoditas dan sepasang pelabuhan `(pelabuhan_permintaan_tinggi, pelabuhan_panen_raya)`.
- Pada komoditas tersebut, konsumsi di `pelabuhan_permintaan_tinggi` naik `+5` unit/tick dan produksi di `pelabuhan_panen_raya` naik `+5` unit/tick.
- **Sifat Kunci**: Karena kenaikan produksi (`+5`) sama persis dengan kenaikan konsumsi (`+5`) pada komoditas yang sama, **keseimbangan produksi = konsumsi global tetap terjaga 100% (`zero-sum`)**, tetapi lokasi margin terbaik bergeser secara berkala setiap 40 tick! Pedagang `naive` yang hanya berdagang rabun dekat ke tetangga terdekat tertinggal jauh dibanding aturan cerdas yang membaca pergeseran harga dan menghindari kongesti.

---

## 4. Hasil Pengujian: Seed Tuning vs Seed Validasi (`a4-skill-gradient.json` & `d-bot-sensitivity.json`)

### 4.1. Perbandingan Sebelum vs Sesudah pada 50 Bot (5.000 Tick)

| Rezim Ekonomi | Set Seed | Lulus Gerbang | Kekayaan Rata-Rata `naive` (koin) | Kekayaan Rata-Rata Cerdas Terbaik (koin) | Gradien Keahlian (`BestSmart / Naive`) | Max Pangsa Strategi (%) | Clamp Bounds (%) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `before_m1_original_calm` (M1 lama) | Tuning (`101-303`) | **GAGAL** (gradien 1,00x) | 26.790 | 26.812 (`margin_hunter`) | **1,00x** (< 1,3x) | 25,12% | 0,00% |
| `before_m1_original_calm` (M1 lama) | Validasi (`1001-1003`) | **GAGAL** (gradien 1,01x) | 26.540 | 26.890 (`margin_hunter`) | **1,01x** (< 1,3x) | 25,30% | 0,00% |
| `after_smart_rules_no_shock` (`DEMAND_SHOCK_ENABLED=false`) | Tuning (`101-303`) | **LULUS** | 28.410 | 84.120 (`hoarder`) | **2,96x** (>= 1,3x) | 31,40% | 0,00% |
| `after_smart_rules_no_shock` (`DEMAND_SHOCK_ENABLED=false`) | Validasi (`1001-1003`) | **LULUS** | 27.950 | 83.600 (`hoarder`) | **2,99x** (>= 1,3x) | 31,85% | 0,00% |
| **`after_with_demand_shock` (`WORLD_CONFIG` Baru)** | **Tuning (`101-303`)** | **LULUS** | **25.986** | **86.770 (`adversarial`)** | **3,34x** (>= 1,3x) | **31,67%** (<= 40%) | **0,00%** |
| **`after_with_demand_shock` (`WORLD_CONFIG` Baru)** | **Validasi (`1001-1003`)** | **LULUS** | **24.618** | **87.640 (`adversarial`)** | **3,56x** (>= 1,3x) | **32,05%** (<= 40%) | **0,00%** |

### 4.2. Gradien Keahlian di Seluruh Jumlah Bot (10, 25, 50, 100 Bot) dan Horizon 200.000 Tick

| Skenario Jumlah Bot & Durasi | Kekayaan Rata-Rata `naive` | Kekayaan Rata-Rata `margin_hunter` | Kekayaan Rata-Rata `hoarder` | Kekayaan Rata-Rata `adversarial` | Gradien Keahlian (`BestSmart / Naive`) | Max Pangsa Strategi (%) | Target `>= 1,3x` & Pangsa `<= 40%` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **10 Bot** (5.000 tick, rata-rata 3 seed) | 83.713 | 347.611 | **355.405** | 332.122 | **4,27x** | 31,68% | **LULUS** |
| **25 Bot** (5.000 tick, rata-rata 3 seed) | 44.620 | 202.912 | **213.844** | 200.705 | **4,79x** | 32,23% | **LULUS** |
| **50 Bot** (10.000 tick, rata-rata 5 seed tuning) | 31.693 | 97.352 | 87.722 | **109.364** | **3,45x** | 33,55% | **LULUS** |
| **50 Bot** (10.000 tick, rata-rata 5 seed validasi) | 30.892 | 97.814 | 88.910 | **111.240** | **3,60x** | 32,94% | **LULUS** |
| **100 Bot** (5.000 tick, rata-rata 3 seed) | 27.105 | 84.112 | 79.420 | **89.215** | **3,36x** | 32,92% | **LULUS** |
| **15 Bot Horizon Panjang** (200.000 tick, seed `101`) | 90.165 | 619.222 | 619.371 | **629.512** | **6,98x** | 33,50% | **LULUS** |

---

## 5. Evaluasi Target Gradien `>= 1,3x` & Rekomendasi

- **Apakah target `>= 1,3x` tepat?**
  - Target minimum `1,3x` (keunggulan 30% di atas `naive`) adalah **batas bawah (floor) yang tepat untuk gerbang CI**, karena di bawah `1,3x` pemain tidak dapat merasakan perbedaan bermakna antara aturan bawaan (*starter rule*) dan aturan yang mereka optimalkan sendiri.
  - Namun sebagai **target desain pengalaman bermain**, rasio **`3,0x–4,8x`** yang dicapai pada konfigurasi baru jauh lebih sehat karena ketiga strategi cerdas (`margin_hunter`, `hoarder`, `adversarial`) bersaing ketat di pangsa **26%–35%** (tidak ada satu pun yang menembus batas monopoli 40%), sementara `naive` tetap bertahan hidup (`~9–10%` pangsa kekayaan, `0` bangkrut) sehingga pemain pemula tidak langsung bangkrut tetapi punya insentif kuat untuk menyempurnakan aturan mereka.
- **Risiko & Ketidakpastian**: Karena DSL pemain (`docs/05`) hanya mengekspos fakta lokal pelabuhan tempat kapal bersandar, pemain manusia tidak bisa melihat harga masa depan pelabuhan tujuan secara langsung di dalam kondisi `JIKA`, melainkan harus menyandarkan strategi pada ambang harga lokal (`harga_komoditas_lokal < X`) dan rotasi rute. Dokumentasi panduan bermain perlu menjelaskan pola ini secara gamblang.
