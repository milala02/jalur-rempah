# Analisis A2 — Diagnosis Kas Pelabuhan & Mekanisme Pendapatan Pelabuhan (`sumber_kumulatif`)

**Tanggal:** 2026-10-19  
**Lingkungan Eksekusi:** VM lokal (`Node.js v18.20.4`, x86_64 Debian GNU/Linux 12)  
**Berkas Data Pendukung:**
- `docs/analisis/data/a2-port-income-diagnosis.json` (diagnosis kas 50.000 tanpa pemasukan, kurva Batavia 200.000 tick pada kas 25.000.000, dan perbandingan 3 mekanisme pada seed tuning & validasi)
- `docs/analisis/data/horizon-200k-seed101.json` (verifikasi 200.000 tick dengan mekanisme terpilih)

---

## 1. Diagnosis Berdata (`Tugas a`)

### 1.1. Perilaku pada Kas Awal 50.000 Tanpa Pendapatan Pelabuhan (`PORT_INCOME_ENABLED = false`)
Simulasi dijalankan pada konfigurasi awal (`INITIAL_PORT_TREASURY = 50.000`, 50 bot, seed `101`, tanpa pendapatan pelabuhan). Hasil terukur (`docs/analisis/data/a2-port-income-diagnosis.json`):

| Pelabuhan | Peran Ekonomi | Kas Awal (koin) | Tick Pertama Kas Habis (< 15 koin / gagal beli kargo) | Kas Minimum (koin) | Kas Akhir (tick 2.000) | Dampak pada Pasar & Bot |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Batavia** | Konsumen murni rempah & garam (konsumsi 32 unit/tick, produksi 0) | 50.000 | **Tick 45** (menyentuh `1` koin pada tick 968) | `1` | `8` | Bot tidak lagi bisa menjual rempah di Batavia; kargo macet di kapal |
| **Malaka** | Konsumen bersih (konsumsi 28 unit/tick, produksi kain 10 unit/tick) | 50.000 | **Tick 185** (menyentuh `6` koin) | `6` | `9` | Jalur ekspor barat lumpuh total sebelum tick 200 |
| **Surabaya** | Konsumen rempah / produsen garam & kain | 50.000 | **Tick 200** (menyentuh `11` koin) | `5` | `8` | Hanya mampu membeli sebagian kecil muatan kapal |
| **Makassar** | Hub transit & produsen garam | 50.000 | **Tick 325** (menyentuh `14` koin) | `1` | `14` | Kehabisan kas akibat limpahan kapal yang gagal jual di Batavia/Surabaya |
| **Banda** | Produsen murni Pala (produksi 20 unit/tick) | 50.000 | Tidak habis | `50.000` | `86.412` | Menyerap seluruh koin pemain tanpa pernah mengembalikannya ke sirkulasi |
| **Ternate** | Produsen murni Cengkeh (produksi 20 unit/tick) | 50.000 | Tidak habis | `50.000` | `84.918` | Menyerap koin bersama Banda; perdagangan dunia membeku |

**Efek berantai saat kas konsumen habis:**
1. Kapal pedagang penuh muatan Pala/Cengkeh tertahan di Batavia, Malaka, dan Surabaya karena `eksekusiJual` mengembalikan `qty = 0` (`PORT_TREASURY_LOW`).
2. Karena kargo kapal penuh, kapal tidak bisa membeli komoditas lain; sementara perawatan kapal (`1` koin/tick) terus menguras saldo koin pemain.
3. Stok Pala dan Cengkeh di Banda dan Ternate menumpuk ke kapasitas maksimum (`1.600` unit -> clamp bawah `0,25x`), sedangkan stok di Batavia dan Malaka jatuh ke `0` unit (-> clamp atas `4,0x`). Persentase tick di batas clamp melonjak ke **65,86%** hanya dalam 2.000 tick.

### 1.2. Kurva Kas Batavia Sampai 200.000 Tick pada `INITIAL_PORT_TREASURY = 25.000.000` Tanpa Pendapatan Pelabuhan
Ketika kas awal dinaikkan 500x lipat menjadi `25.000.000` koin per pelabuhan tanpa mekanisme pemasukan (`diagnosis_25M_bataviaCurve_200k` di `a2-port-income-diagnosis.json`), kas Batavia tetap terkuras secara linier sebesar **~1.925 koin/tick** pada fase aktif dan habis total sebelum tick 40.000:

| Tick | Kas Batavia (koin) | Total Koin Pemain (koin) | Status Perdagangan |
| :---: | :---: | :---: | :--- |
| `0` | `25.000.000` | `50.000` | Normal |
| `5.000` | `15.375.000` | `9.675.000` | Normal (kas Batavia turun ~1.925 koin/tick) |
| `10.000` | `5.750.000` | `19.300.000` | Normal (kas Batavia tersisa 23%) |
| `20.000` | `1.199.139` | `32.518.420` | Melambat (Malaka & Surabaya mulai kehabisan kas) |
| `40.000` | **`14`** | `28.410.112` | **LUMPUH TOTAL** (kas Batavia habis, `N > 14` ditolak) |
| `60.000` | `14` | `27.410.112` | Membeku (koin pemain hanya berkurang karena upkeep) |
| `100.000` | `14` | `25.410.112` | Membeku |
| `160.000` | `9` | `22.410.112` | Membeku |
| `200.000` | `9` | `20.410.112` | Membeku |

Kesimpulan: menaikkan `INITIAL_PORT_TREASURY` tanpa mekanisme pendapatan pelabuhan konsumen hanya menggeser waktu kehancuran ekonomi.

---

## 2. Perbandingan 3 Mekanisme Pendapatan Pelabuhan (`A2` & `Tugas b`)

Kami merancang, mengimplementasikan, dan menguji 3 mekanisme kandidat pada `INITIAL_PORT_TREASURY = 50.000` (`6x` total modal awal 50 pemain, memenuhi syarat $\le 10\times$):

1. **Mekanisme M1 — Injeksi Konsumsi Murni Tanpa Kliring Produsen (`m1_consumption_faucet_only`)**:
   - Setiap tick, pelabuhan menerima koin baru sebesar nilai konsumsi domestiknya (`actualConsumed * base_price`), tanpa arus keluar kas pada pelabuhan produsen.
   - **Kelemahan fatal**: Menjadi keran uang satu arah. Kas Banda dan Ternate membengkak terus-menerus (`cumulativeSource = +8.579.307` koin dalam 10.000 tick), dan total koin pemain mengalami inflasi cepat (`relativeDriftPct = 17,97% > 15%` pada seed tuning dan `18,40%` pada seed validasi -> **GAGAL gerbang stabilitas**).
2. **Mekanisme M2 — Kliring Domestik Seimbang + Restorasi Kas Target (`m2_balanced_domestic_clearing`, TERPILIH)**:
   - Di dunia nyata, warga lokal di pelabuhan konsumen (Batavia, Malaka) membayar pajak/pembelian ritel atas barang yang dikonsumsi (`consVal = actualConsumed * base_price`, menambah kas pelabuhan), sedangkan di pelabuhan produsen (Banda, Ternate), kas pelabuhan membayar petani/penambang lokal atas komoditas yang diproduksi ke gudang pasar (`prodVal = actualProduced * base_price`, mengurangi kas pelabuhan hingga batas aman `PORT_TREASURY_FLOOR = 22.000`), ditambah pemulihan proporsional menuju kas target `(INITIAL_PORT_TREASURY - treasury) / PORT_TREASURY_RESTORE_DIVISOR`.
   - Karena secara global $\sum \text{production} = \sum \text{consumption} = 23$ unit/tick per komoditas, arus masuk domestik dan arus keluar domestik **secara struktural seimbang**!
   - Setiap penambahan kas dicatat eksplisit ke `sumber_kumulatif` (`economy_sources_sinks` dengan `kind = 'source', reason = 'port_income'`), dan setiap pembayaran ke produsen lokal dicatat ke `pengurang_kumulatif` (`kind = 'sink', reason = 'port_producer_payout'`).
3. **Mekanisme M3 — Daur Ulang Upkeep + Redistribusi Pajak Antar-Pelabuhan (`m3_upkeep_tax_recycling_tight`)**:
   - Mengandalkan pemulihan lambat (`PORT_TREASURY_RESTORE_DIVISOR = 15`) dan pajak kekayaan tinggi (`WEALTH_UPKEEP_BPS = 8`).
   - **Kelemahan**: Meskipun stabil, margin pemain tertekan terlalu keras sehingga kekayaan ekuilibrium turun separuhnya (`~1,74 juta` koin).

### Tabel Perbandingan Data (50 Bot, 5.000 Tick, `a2-port-income-diagnosis.json`)

| Mekanisme | Set Seed | Lulus Gerbang | Kas Pelabuhan Terendah (koin) | Total Kas Akhir 6 Pelabuhan (koin) | Total Koin Pemain Akhir (koin) | Drift Koin Q3->Q4 (%) | Max Clamp Bounds (%) | Konservasi Uang (`lhs == rhs`) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `m1_consumption_faucet_only` | Tuning | **GAGAL** | 50.000 | 1.984.120 (meledak) | 2.612.885 | **17,97%** (>15%) | 0,00% | Valid |
| `m1_consumption_faucet_only` | Validasi | **GAGAL** | 50.000 | 1.991.405 (meledak) | 2.648.110 | **18,40%** (>15%) | 0,00% | Valid |
| **`m2_balanced_domestic_clearing` (Terpilih)** | **Tuning** | **LULUS** | **28.844** | **295.706** (stabil ~300k) | **2.695.212** | **11,01%** (<=15%) | **0,00%** | **Valid (100%)** |
| **`m2_balanced_domestic_clearing` (Terpilih)** | **Validasi** | **LULUS** | **24.205** | **296.418** (stabil ~300k) | **2.718.904** | **10,42%** (<=15%) | **0,00%** | **Valid (100%)** |
| `m3_upkeep_tax_recycling_tight` | Tuning | LULUS | 19.412 | 291.104 | 1.742.118 | 4,12% | 0,00% | Valid |
| `m3_upkeep_tax_recycling_tight` | Validasi | LULUS | 18.890 | 292.015 | 1.755.390 | 3,89% | 0,00% | Valid |

---

## 3. Persamaan Invarian Konservasi Uang Baru (`Tugas b`)

Dengan hadirnya sumber koin eksplisit yang tercatat (`sumber_kumulatif`), persamaan konservasi uang global di `packages/econ/src/invariants.ts`, `db/migrations/0003_port_income_and_ledger_compaction.sql` (`economy_money_supply_audit`), `docs/06`, dan `docs/07` adalah:

```text
total_koin_pemain + total_kas_pelabuhan + pengurang_kumulatif == total_awal + sumber_kumulatif
```

Di mana:
- `total_awal = SUM(players.initial_coins) + SUM(ports.initial_treasury)` (`50.000 + 300.000 = 350.000` koin pada 50 pemain),
- `sumber_kumulatif = SUM(economy_sources_sinks.amount WHERE kind = 'source') + SUM(ledger.delta WHERE reason = 'rescue')`,
- `pengurang_kumulatif = SUM(-ledger.delta WHERE reason = 'upkeep') + SUM(players.unflushed_upkeep) + SUM(economy_sources_sinks.amount WHERE kind = 'sink')`.

---

## 4. Rekomendasi, Risiko, dan Ketidakpastian

- **Rekomendasi**: Tetapkan **Mekanisme M2 (`m2_balanced_domestic_clearing`)** dengan `INITIAL_PORT_TREASURY = 50.000n` (`6x` modal awal 50 pemain), `PORT_TREASURY_FLOOR = 22.000n`, dan `PORT_TREASURY_RESTORE_DIVISOR = 2n`, serta catat seluruh mutasi sumber/pengurang pelabuhan di tabel append-only `public.economy_sources_sinks` (Migrasi `0003`).
- **Risiko**: Jika semua pemain berhenti berdagang sama sekali selama ribuan tick, pelabuhan konsumen tetap memiliki kas sekitar `50.000` koin; ini disengaja agar pasar siap menerima kargo begitu pemain kembali aktif.
- **Apa yang Belum Diketahui**: Pada M2/M4 saat ratusan pemain manusia melakukan aksi jual terkoordinasi pada tick yang sama di satu pelabuhan konsumen, kas pelabuhan tersebut dapat turun sementara ke dekat `PORT_TREASURY_FLOOR` selama 1–2 tick sebelum pulih pada tick berikutnya.
