# Analisis A1 — Parameter Ekonomi, Kapasitas Kapal, dan Sensitivitas Jumlah Bot

**Tanggal:** 2026-10-19  
**Lingkungan Eksekusi:** VM lokal (`Node.js v18.20.4`, x86_64 Debian GNU/Linux 12, transpilasi `@babel/preset-typescript`)  
**Berkas Data Pendukung:**
- `docs/analisis/data/a1-parameter-sweep.json` (sweep elastisitas, biaya pelabuhan, kapasitas kapal, dan perawatan)
- `docs/analisis/data/d-bot-sensitivity.json` (sensitivitas 10, 25, 50, 100 bot x 3 seed untuk kapasitas 20, 45, dan 35 adaptif)
- `docs/analisis/data/m1-10seeds-50bots.json` (5 seed tuning `101-505` + 5 seed validasi `1001-1005` pada 50 bot, 10.000 tick)
- `docs/analisis/data/horizon-200k-seed101.json` (stabilitas horizon panjang 200.000 tick, 15 bot, seed `101`)

---

## 1. Rumusan Masalah

Temuan revisi M1 menunjukkan dua masalah utama pada konfigurasi awal:
1. `STARTER_SHIP_CAPACITY = 45` sebelumnya dihitung khusus untuk 50 kapal (surplus global 68 unit/tick x siklus rata-rata ~16 tick $\approx 1.088$ unit di laut, atau ~22-35 unit/kapal), tetapi belum diuji pada 10–25 kapal (target beta awal `docs/01` adalah 10–50 pemain) maupun 100 kapal.
2. Perlu diukur sensitivitas parameter inti (`ELASTICITY`, `PORT_FEE_PERCENT`, `UPKEEP_PER_TICK` + pajak logistik kekayaan, `STARTER_COINS`, `STARTER_SHIP_CAPACITY`, dan kapasitas/target gudang) terhadap:
   - Persentase tick harga menempel di batas clamp (`pctTicksAtBounds`),
   - Volatilitas harga per komoditas (`volatilityPct`),
   - Persentase bot grounded (`bankruptBotPct`),
   - Margin rata-rata per rute dan per transaksi (`avgMarginPerTx`),
   - Kecepatan bot menjadi kaya (`avgTicksToDoubleCoins`, waktu mencapai modal $2\times = 2.000$ koin),
   - Stabilitas jangka panjang hingga 200.000 tick (`relativeDriftPct` kuartal 3 vs kuartal 4).

---

## 2. Metodologi & Pemisahan Seed Tuning vs Validasi

- **Seed Tuning (`101, 202, 303, 404, 505`)**: Dipakai untuk mengeksplorasi ruang parameter dan memilih titik operasi.
- **Seed Validasi (`1001, 1002, 1003, 1004, 1005`)**: Disimpan terpisah dan hanya dijalankan setelah konfigurasi kandidat ditetapkan untuk memastikan tidak ada *overfitting* pada lintasan PRNG tertentu.
- **Perintah VM untuk mereproduksi**:
  ```bash
  # Transpilasi paket shared & econ ke /tmp/jr-build lalu jalankan sim-cli:
  NODE_PATH=/tmp/jr-build/node_modules node /tmp/jr-build/worker/sim-cli.js \
    --ticks 10000 --bots 50 --seed 101,202,303,404,505,1001,1002,1003,1004,1005 \
    --out docs/analisis/data/m1-10seeds-50bots.json
  ```

---

## 3. Hasil Sweep Parameter Terkendali (`a1-parameter-sweep.json`)

Tabel berikut merangkum hasil rata-rata pada **Seed Tuning (`101, 202, 303`)** dan **Seed Validasi (`1001, 1002, 1003`)** (50 bot, 5.000 tick):

| Konfigurasi Kandidat | Set Seed | Lulus Gerbang | Max Clamp Bounds (%) | Volatilitas Pala (%) | Bot Grounded (%) | Max Pangsa Strategi (%) | Gradien Keahlian (Smart/Naive) | Margin/Tx Cerdas (koin) | Waktu 2x Modal Cerdas (tick) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`baseline_recommended`** ($\gamma=0,6$, fee $2\%$, cap $35$, $\tau_{wealth}=4\text{ bps}$) | Tuning | **YA** | **0,00%** | 30,52% | 20,00% | 31,67% | **3,34x** | 437,86 | 56 |
| **`baseline_recommended`** ($\gamma=0,6$, fee $2\%$, cap $35$, $\tau_{wealth}=4\text{ bps}$) | Validasi | **YA** | **0,00%** | 29,21% | 19,33% | 32,05% | **3,56x** | 440,59 | 49 |
| `elasticity_0.4` ($\gamma=0,4$) | Tuning | YA | 0,00% | 20,38% | 20,00% | 31,80% | 3,34x | 396,87 | 65 |
| `elasticity_0.4` ($\gamma=0,4$) | Validasi | YA | 0,00% | 19,70% | 19,33% | 32,12% | 3,48x | 398,74 | 54 |
| `elasticity_0.8` ($\gamma=0,8$) | Tuning | YA | 0,00% | 40,26% | 20,00% | 32,18% | 3,47x | 476,12 | 51 |
| `elasticity_0.8` ($\gamma=0,8$) | Validasi | YA | 0,01% | 39,10% | 19,33% | 31,94% | 3,61x | 482,05 | 46 |
| `fee_1pct` (biaya pelabuhan 1%) | Tuning | YA | 0,00% | 30,44% | 19,33% | 31,42% | 3,22x | 462,10 | 53 |
| `fee_4pct` (biaya pelabuhan 4%) | Tuning | YA | 0,00% | 30,61% | 20,00% | 32,48% | 3,68x | 389,45 | 64 |
| `ship_cap_20` (kapasitas 20, adaptif) | Tuning | YA | 0,00% | 28,90% | 20,00% | 33,19% | 4,76x | 298,14 | 81 |
| `ship_cap_45` (kapasitas 45, adaptif) | Tuning | YA | 0,00% | 31,15% | 20,00% | 32,59% | 3,41x | 512,40 | 48 |
| `upkeep_flat_1_no_wealth_tax` ($\tau_{wealth}=0$) | Tuning | **TIDAK** (drift > 15%) | 0,00% | 30,48% | 20,00% | 32,19% | 4,50x | 645,10 | 56 |

### Temuan Kunci dari Sweep Parameter
1. **Elastisitas ($\gamma = 0,6$) adalah titik manis**:
   - Pada $\gamma = 0,4$, volatilitas rempah utama turun ke ~20% sehingga selisih harga antar pelabuhan menyempit dan waktu balik modal melambat (~65 tick).
   - Pada $\gamma = 0,8$, volatilitas melonjak ke ~40% dan mulai menyentuh batas clamp atas (`0,01%` pada seed validasi).
   - Pada $\gamma = 0,6$, harga rempah bergerak dinamis di rentang `49–177` koin (Pala, dasar 70) dan `63–228` koin (Cengkeh, dasar 90) dengan **`0,00%` tick menempel di batas clamp**.
2. **Biaya Pelabuhan (`PORT_FEE_PERCENT = 2%`, `PORT_FEE_MIN = 1n`)**:
   - Menjamin setiap siklus beli-lalu-jual instan di pelabuhan yang sama selalu rugi tepat $2 \times F(G)$ koin (`profitableExploitsFound = 0` dari >120.000 percobaan eksploit per run).
   - Pada 4%, rute jarak pendek untuk komoditas murah (`garam`, `kain`) kehilangan kelayakan margin bagi pedagang pemula (`naive`).
3. **Perawatan Kapal & Pajak Logistik Kekayaan (`UPKEEP_PER_TICK = 1n`, `WEALTH_UPKEEP_BPS = 4`)**:
   - Dengan perawatan dasar 1 koin/tick saja (`WEALTH_UPKEEP_BPS = 0`), uang beredar pemain tumbuh linier tanpa batas (~1.425 koin/tick) karena surplus dagang melebihi pengurang tetap 50 koin/tick.
   - Dengan `WEALTH_UPKEEP_BPS = 4` (0,04%/tick di atas `STARTER_COINS = 1.000`), total koin pemain mencapai ekuilibrium stasioner $M^* \approx 2,85\text{–}3,25\text{ juta}$ koin dengan konstanta waktu relaksasi $\tau = 2.500$ tick, tanpa membebani pemain baru yang koinnya $\le 1.000$.

---

## 4. Analisis Sensitivitas Jumlah Bot & Kapasitas Kapal (`Tugas d` & `Tugas g`)

Tabel berikut membandingkan tiga rezim kapasitas kapal pada **10, 25, 50, dan 100 bot** (rata-rata 3 seed: `101, 202, 303`, 5.000 tick, data lengkap di `docs/analisis/data/d-bot-sensitivity.json`):

| Rezim & Kapasitas | Jumlah Bot | Lulus Semua Gerbang | Max Clamp Bounds (%) | Bot Grounded (%) | Kas Pelabuhan Terendah (koin) | Max Pangsa Strategi (%) | Gradien Keahlian | Kekayaan Rata-Rata / Margin per Tx (`hoarder` / `margin_hunter` / `adversarial` / `naive` / `random`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `static_cap20` (tanpa penskalaan pasar) | 10 | **GAGAL** | **68,77%** | 0,00% | 33.566 | 35,94% | 4,07x | H: 983k (3.606) / MH: 722k (3.083) / Adv: 697k (2.982) / N: 242k (990) / R: 92k (1.366) |
| `static_cap20` (tanpa penskalaan pasar) | 25 | **GAGAL** | **49,36%** | 0,00% | 19.680 | 31,70% | 3,07x | H: 446k (1.774) / MH: 371k (1.513) / Adv: 369k (1.563) / N: 145k (602) / R: 77k (873) |
| `static_cap20` (tanpa penskalaan pasar) | 50 | **GAGAL** | **35,31%** | 0,00% | 17.145 | 31,65% | 4,82x | H: 349k (1.469) / MH: 317k (1.345) / Adv: 320k (1.431) / N: 72k (335) / R: 45k (473) |
| `static_cap20` (tanpa penskalaan pasar) | 100 | LULUS | 0,00% | 19,33% | 34.075 | 35,66% | 3,00x | H: 32k (327) / MH: 37k (272) / Adv: 46k (232) / N: 16k (96) / R: 2 (15) |
| `static_cap45` (tanpa penskalaan pasar) | 10 | **GAGAL** | **53,87%** | 0,00% | 9.258 | 33,57% | 11,84x | H: 1.013k (4.003) / MH: 912k (3.570) / Adv: 981k (3.877) / N: 88k (402) / R: 83k (990) |
| `static_cap45` (tanpa penskalaan pasar) | 25 | **GAGAL** | **38,89%** | 1,33% | 12.683 | 32,20% | 5,71x | H: 570k (2.508) / MH: 533k (2.400) / Adv: 533k (2.452) / N: 100k (425) / R: 35k (381) |
| `static_cap45` (tanpa penskalaan pasar) | 50 | LULUS | 0,14% | 20,00% | 20.107 | 31,71% | 3,74x | H: 69k (569) / MH: 72k (443) / Adv: 69k (370) / N: 20k (130) / R: 0 (-3,5) |
| `static_cap45` (tanpa penskalaan pasar) | 100 | **GAGAL** | 0,00% | 26,00% | 27.978 | **49,83%** | 4,56x | H: 7,3k (235) / MH: 8,9k (191) / Adv: 20,6k (144) / N: 4,5k (39) / R: 0 (-10,7) |
| **`adaptive_cap35` (`SCALE_MARKET_WITH_FLEET=true`)** | **10** | **LULUS** | **0,00%** | **10,00%** | **34.249** | **31,68%** | **4,27x** | H: 355k (1.575) / MH: 348k (1.511) / Adv: 332k (1.557) / N: 84k (338) / R: 2,7k (48) |
| **`adaptive_cap35` (`SCALE_MARKET_WITH_FLEET=true`)** | **25** | **LULUS** | **0,00%** | **9,33%** | **29.207** | **32,23%** | **4,79x** | H: 214k (935) / MH: 203k (866) / Adv: 201k (905) / N: 45k (188) / R: 1,4k (34) |
| **`adaptive_cap35` (`SCALE_MARKET_WITH_FLEET=true`)** | **50** | **LULUS** | **0,00%** | **20,00%** | **28.844** | **31,67%** | **3,34x** | H: 78k (576) / MH: 83k (438) / Adv: 87k (427) / N: 26k (148) / R: 0 (-2,9) |
| **`adaptive_cap35` (`SCALE_MARKET_WITH_FLEET=true`)** | **100** | **LULUS** | **0,02%** | **23,33%** | **10.147** | **32,92%** | **3,36x** | H: 79k (578) / MH: 84k (445) / Adv: 89k (431) / N: 27k (151) / R: 0 (-3,1) |

### Mengapa Pasar Statis Hanya Sehat pada Satu Titik Jumlah Bot?
- Pada pasar statis (`SCALE_MARKET_WITH_FLEET = false`), surplus bersih seluruh pelabuhan produsen adalah konstan **68 unit/tick**.
- Dengan `STARTER_SHIP_CAPACITY = 20`, daya angkut hanya cukup jika ada **100 kapal**; pada 10–50 kapal, stok produsen menumpuk hingga kapasitas gudang penuh dan stok konsumen habis ke 0, membuat harga menempel di batas clamp 0,25x dan 4,0x selama **35%–69% tick**.
- Dengan `STARTER_SHIP_CAPACITY = 45`, daya angkut pas untuk **50 kapal**, tetapi pada 10–25 kapal masih kurang (`38%–54%` tick di batas clamp), sedangkan pada 100 kapal terjadi perebutan stok ekstrem yang membuat strategi anti-kongesti (`adversarial`) memonopoli **49,83%** kekayaan (> ambang 40%).
- **Solusi Terpilih (`adaptive_cap35` + `SCALE_MARKET_WITH_FLEET = true`)**:
  1. Menetapkan `STARTER_SHIP_CAPACITY = 35`.
  2. Saat ukuran armada aktif di atas 50 kapal (`fleetSize > 50`), laju produksi dan konsumsi efektif diskalakan proporsional `effectiveRate = (baseRate * fleetSize) / 50` (tetap menjaga keseimbangan produksi = konsumsi global karena kedua sisi dikalikan faktor yang sama).
  3. Saat stok menyimpang ekstrem akibat armada kecil (10–25 kapal), peredam karavan pesisir domestik menyerap kelebihan stok di atas `target + 220` dan memasok darurat di bawah `140` unit, sehingga harga mencapai ekuilibrium tinggi/rendah alami (`~0,55x` hingga `~2,5x` harga dasar) tanpa membentur clamp keras `0,25x` / `4,0x`.

---

## 5. Validasi 10 Seed (5 Tuning + 5 Validasi) pada 10.000 Tick & Horizon Panjang 200.000 Tick

### 5.1. Ringkasan 10 Seed (50 Bot, 10.000 Tick, `docs/analisis/data/m1-10seeds-50bots.json`)

| Kelompok | Seed | Lulus Gerbang | Max Clamp Bounds (%) | Kas Terendah (koin) | Bot Grounded (%) | Max Pangsa Strategi (%) | Gradien Keahlian | Drift Koin Q3->Q4 (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Tuning | `101` | **LULUS** | 0,00% | 30.130 (Batavia) | 18,00% | 33,06% (`adversarial`) | 3,52x | 13,45% |
| Tuning | `202` | **LULUS** | 0,00% | 28.844 (Batavia) | 20,00% | 35,30% (`adversarial`) | 3,56x | 6,24% |
| Tuning | `303` | **LULUS** | 0,00% | 25.149 (Batavia) | 20,00% | 32,76% (`adversarial`) | 3,29x | 6,41% |
| Tuning | `404` | **LULUS** | 0,00% | 29.666 (Batavia) | 18,00% | 33,30% (`adversarial`) | 3,49x | 6,88% |
| Tuning | `505` | **LULUS** | 0,00% | 29.098 (Batavia) | 20,00% | 33,31% (`adversarial`) | 3,40x | 4,25% |
| **Validasi** | `1001` | **LULUS** | 0,00% | 29.538 (Batavia) | 18,00% | 34,90% (`adversarial`) | 3,87x | 7,17% |
| **Validasi** | `1002` | **LULUS** | 0,00% | 24.205 (Batavia) | 18,00% | 31,14% (`adversarial`) | 3,43x | 3,58% |
| **Validasi** | `1003` | **LULUS** | 0,00% | 27.648 (Batavia) | 20,00% | 33,12% (`adversarial`) | 3,66x | 9,85% |
| **Validasi** | `1004` | **LULUS** | 0,00% | 29.365 (Batavia) | 18,00% | 34,13% (`adversarial`) | 3,45x | 1,96% |
| **Validasi** | `1005` | **LULUS** | 0,00% | 31.610 (Batavia) | 20,00% | 31,42% (`adversarial`) | 3,60x | 2,16% |

### 5.2. Horizon Panjang 200.000 Tick (`15` Bot, Seed `101`, `docs/analisis/data/horizon-200k-seed101.json`)
- **Invarian & Konservasi Uang**: `0` pelanggaran selama 200.000 tick; `lhsTotalAccounted == rhsTotalExpected == 258.508.573` koin.
- **Kas Pelabuhan**: Tidak pernah menyentuh 0 dan tidak meledak (`minPortTreasuryCoins = 28.820` koin di Batavia pada tick 109.766; kas akhir ke-6 pelabuhan di tick 200.000 berada di rentang `48.204–51.555` koin).
- **Stabilitas Total Koin Pemain**: Rata-rata koin pemain pada Kuartal 3 (`tick 100.001–150.000`) adalah `2.860.570` koin dan pada Kuartal 4 (`tick 150.001–200.000`) adalah `2.852.407` koin (**pergeseran relatif hanya `0,29%`**, atau `1,65%` pada sampel waktu, jauh di bawah batas `15%`).

---

## 6. Rekomendasi, Risiko, dan Ketidakpastian

- **Rekomendasi**: Gunakan `STARTER_SHIP_CAPACITY = 35`, `ELASTICITY = 0,6`, `PORT_FEE_PERCENT = 2`, `UPKEEP_PER_TICK = 1n`, `WEALTH_UPKEEP_BPS = 4`, dan `SCALE_MARKET_WITH_FLEET = true`.
- **Risiko**: Peredam karavan pesisir domestik (`SCALE_MARKET_WITH_FLEET`) membatasi keuntungan ekstrem pada dunia yang sangat sepi (<10 pemain), sehingga pemain solo tidak bisa memonopoli harga 4,0x selamanya.
- **Apa yang Belum Diketahui**: Pola kedatangan pemain manusia yang tidak seragam berdasarkan jam sibuk (siang vs malam WIB) dapat menciptakan fluktuasi jumlah kapal aktif harian yang lebih tajam daripada simulasi jumlah bot tetap.
