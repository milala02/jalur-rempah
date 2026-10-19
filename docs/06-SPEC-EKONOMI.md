# 06 — Spesifikasi Ekonomi v0.3

Semua angka adalah **parameter terkonfigurasi** di `packages/shared/src/config.ts`. Perubahan nilai wajib didukung data simulasi pada seed tuning (`101-505`) dan seed validasi (`1001-1005`) (lihat `docs/10` dan `docs/analisis/A1-parameter-ekonomi.md`).

## Prinsip
1. Uang dan stok integer (`BIGINT`, ADR-005). Tidak ada float di jalur uang; satu-satunya fungsi pembulatan berada di `hitungHarga` (`packages/econ`).
2. Harga ditentukan **hanya** oleh stok pelabuhan relatif terhadap target, bukan oleh pemain secara langsung.
3. Eksekusi transaksi beli dan jual bersifat **simetris** (ADR-009).
4. Setiap pelabuhan memiliki **kas (`treasury`)** terbatas (`>= 0`). Biaya pelabuhan 2% masuk ke kas pelabuhan tempat transaksi; penambahan kas domestik pelabuhan dan pemulihan darurat tercatat sebagai `sumber_kumulatif`, sedangkan perawatan kapal (`upkeep`) dan pembayaran produsen lokal tercatat sebagai `pengurang_kumulatif` (ADR-009, ADR-010).

## Dunia awal
Komoditas dan harga dasar (koin per unit):
| Komoditas | Harga dasar | Batas bawah (`0.25x`) | Batas atas (`4.0x`) |
|---|---|---|---|
| pala | 70 | 18 | 280 |
| cengkeh | 90 | 23 | 360 |
| garam | 20 | 5 | 80 |
| kain | 45 | 11 | 180 |

Pelabuhan, produksi unggulan, dan jarak (tick pelayaran, dua arah):
| Pelabuhan | Produksi unggulan |
|---|---|
| Banda | pala |
| Ternate | cengkeh |
| Surabaya | garam |
| Malaka | kain |
| Makassar | (campuran seimbang) |
| Batavia | (pusat konsumsi murni) |

| Rute | Tick |
|---|---|
| Banda – Ternate | 5 |
| Banda – Makassar | 6 |
| Ternate – Makassar | 5 |
| Makassar – Surabaya | 4 |
| Surabaya – Batavia | 3 |
| Batavia – Malaka | 4 |
| Makassar – Batavia | 6 |

`[ASUMSI]` Durasi tick produksi 30 detik (di simulasi: 0 detik, loncat). Pelayaran 3–6 tick = 1,5–3 menit.

## Model pasar per (pelabuhan, komoditas)
Variabel: `stok`, `target` (stok setimbang), `produksi` per tick, `konsumsi` per tick.

**Harga (`hitungHarga`):**
```text
rasio = target / max(stok, 1)
harga = max(1, round(dasar * clamp(rasio ^ e, 0.25, 4.0)))
```
- `e = 0.6` (`ELASTICITY` di `WORLD_CONFIG`)
- `round` ke integer terdekat, minimal `1` (satu-satunya tempat pembulatan float-ke-integer di seluruh sistem)
- Fungsi `hitungHarga(stok, target, dasar, config)` di `packages/econ/src/price.ts` adalah **satu-satunya** tempat harga dihitung

**Produksi dan konsumsi tiap tick (`stepProduksiKonsumsi`):**
```text
stok_setelah_produksi = stok + produksi_efektif
konsumsi_aktual       = min(konsumsi_efektif, stok_setelah_produksi)
stok_baru             = min(stok_setelah_produksi - konsumsi_aktual, kapasitasGudang)
harga_baru            = hitungHarga(stok_baru, target, dasar, config)
```
Parameter dasar (`packages/shared/src/seed-data.ts` & `config.ts`):
- `target = 400`, `kapasitasGudang = 1.600`, stok awal = `400`, harga awal = `harga_dasar`.
- Pelabuhan unggulan (Banda: pala, Ternate: cengkeh, Surabaya: garam, Malaka: kain): komoditas unggulan `produksi = 20, konsumsi = 3`; tiga komoditas lainnya `produksi = 0, konsumsi = 3`.
- Makassar: keempat komoditas `produksi = 3, konsumsi = 3`.
- Batavia: keempat komoditas `produksi = 0, konsumsi = 8`.
- **Invarian Seed Global**: Untuk setiap komoditas, jumlah `produksi` dasar di seluruh 6 pelabuhan sama dengan jumlah `konsumsi` dasar di seluruh 6 pelabuhan (`total_prod == total_cons == 23` unit/tick).
- **Guncangan Permintaan Terjadwal Deterministik (`DEMAND_SHOCK_ENABLED = true`)**: Setiap blok `DEMAND_SHOCK_INTERVAL_TICKS = 40` tick, satu komoditas terpilih secara deterministik dari `(epoch, worldSeed)` mengalami tambahan konsumsi `+5` unit/tick di satu pelabuhan dan tambahan produksi `+5` unit/tick di pelabuhan lain (tetap *zero-sum* secara global).
- **Penskalaan & Peredam Pasar Adaptif (`SCALE_MARKET_WITH_FLEET = true`)**: Untuk armada $> 50$ kapal, laju produksi dan konsumsi efektif diskalakan dengan `fleetSize / 50`; untuk mencegah stok menempel di batas clamp pada armada kecil (10–25 kapal), karavan pesisir domestik menyerap sebagian kelebihan stok di atas `target + 220` dan memasok darurat saat stok di bawah `140`.

## Eksekusi transaksi simetris (slippage, biaya, dan syarat kas pelabuhan)
Beli dan jual dieksekusi **unit demi unit secara simetris** (ADR-009, ADR-010):

```text
Beli 1 unit dari stok S:
  bayar hitungHarga(S, target, dasar)
  stok_baru = S - 1

Beli n unit dari stok awal S:
  G_beli(S, n) = sum_{i = 0 .. n-1} hitungHarga(S - i, target, dasar)
  stok_akhir   = S - n

Jual 1 unit ke stok S':
  stok_baru = S' + 1
  terima hitungHarga(stok_baru, target, dasar)

Jual n unit ke stok awal S':
  G_jual(S', n) = sum_{i = 1 .. n} hitungHarga(S' + i, target, dasar)
  stok_akhir    = S' + n
```

- **Sifat Simetri Eksak:** Membeli `n` unit dari stok `S` (stok turun ke `S - n`) lalu menjual `n` unit dari stok `S - n` (stok naik kembali ke `S`) mengevaluasi himpunan harga satuan yang **identik** (`{S, S - 1, ..., S - n + 1}`), sehingga nilai kotor beli dan nilai kotor jual selalu sama persis:
  ```text
  G_beli(S, n) == G_jual(S - n, n)
  ```
- **Biaya Pelabuhan (`hitungBiayaPelabuhan`):** `2%` dari nilai kotor transaksi `G` tiap sisi, dibulatkan ke atas dalam aritmetika integer murni, minimal `1` koin untuk `G > 0`:
  ```text
  F(G) = 0                             jika G <= 0
  F(G) = max(1, (G * 2 + 99) / 100)    jika G > 0 (pembagian integer BigInt)
  ```
- **Mutasi Koin dan Syarat Kas Pelabuhan (Disamakan antara Kode & Dokumen — `Tugas i`):**
  ```text
  Transaksi BELI n unit:
    Total bayar pemain : T(n) = G(n) + F(G(n))
    Syarat sah         : n <= stok_pelabuhan
                         AND n <= kapasitas_kapal - total_muatan_kapal
                         AND T(n) <= koin_pemain
    Mutasi             : koin_pemain    -= T(n)
                         kas_pelabuhan  += T(n)

  Transaksi JUAL n unit:
    Penerimaan bersih  : N(n) = G(n) - F(G(n))
    Syarat sah         : n <= muatan_komoditas_di_kapal
                         AND stok_pelabuhan + n <= kapasitasGudang
                         AND N(n) > 0
                         AND N(n) <= kas_pelabuhan (ports.treasury)
    Mutasi             : koin_pemain    += N(n)
                         kas_pelabuhan  -= N(n)
  ```
  *Catatan batas kas jual:* Karena pelabuhan membayarkan `G(n)` kepada penjual dan pada saat yang sama memungut kembali biaya pelabuhan `F(G(n))` ke dalam kasnya sendiri, pengeluaran bersih kas pelabuhan adalah `N(n) = G(n) - F(G(n))`. Oleh sebab itu, penjualan sah selama `N(n) <= kas_pelabuhan` (termasuk saat `kas_pelabuhan == N(n)` meskipun `G(n) > kas_pelabuhan`). Jika `kas_pelabuhan == N(n) - 1`, transaksi ditolak dengan kode `PORT_TREASURY_LOW`.

- **Algoritma Deterministik `beli(k, maks)` dan `jual(k, semua)`:**
  ```text
  beli(k, maks):
    U_maks = min(muatan_bebas_kapal, stok_pelabuhan)
    Cari k terbesar dalam [0 .. U_maks] dengan pencarian biner (binary search)
    pada prefix sum G_beli(k) sehingga T(k) = G_beli(k) + F(G_beli(k)) <= koin_pemain.

  jual(k, semua):
    U_maks = min(stok_kapal[k], kapasitasGudang - stok_pelabuhan)
    Cari k terbesar dalam [0 .. U_maks] dengan pencarian biner (binary search)
    pada prefix sum G_jual(k) sehingga N(k) = G_jual(k) - F(G_jual(k)) <= kas_pelabuhan
    dan N(k) > 0.
  ```
- Transaksi dengan jumlah eksplisit (`beli(k, n)` / `jual(k, n)`) bersifat **atomik per aksi**: gagal sebagian = gagal seluruhnya (`ok: false` dengan `failureCode`), lalu evaluasi aturan jatuh ke aturan berikutnya pada tick yang sama (`docs/05` v0.2).

## Sumber, sirkulasi, dan pengurang uang (`sumber_kumulatif` & `pengurang_kumulatif`)
**Modal awal sistem (`total_awal`):**
- Modal awal tiap akun pemain: `STARTER_COINS = 1.000` koin (tercatat di `ledger` dengan `reason = 'starter'`).
- Kas awal tiap pelabuhan: `INITIAL_PORT_TREASURY = 50.000` koin per pelabuhan (`300.000` koin total untuk 6 pelabuhan = `6x` total modal awal 50 pemain, memenuhi syarat `<= 10x`).
- Kapasitas kapal awal: `STARTER_SHIP_CAPACITY = 35` unit.

**Sumber koin eksplisit (`sumber_kumulatif`):**
1. **Pendapatan Domestik Pelabuhan (`port_income`, Langkah 3 tick):** Setiap tick, kas pelabuhan menerima selisih nilai konsumsi ritel domestik terhadap produksi domestik ditambah pemulihan proporsional menuju kas target (`desiredDelta = (actualConsumed - actualProduced) * base_price + (INITIAL_PORT_TREASURY - treasury) / PORT_TREASURY_RESTORE_DIVISOR` bila `desiredDelta > 0`), tercatat di `economy_sources_sinks` (`kind = 'source', reason = 'port_income'`).
2. **Pemulihan Darurat (`rescue`, Langkah 7 tick, di balik flag `RESCUE_ENABLED`):** Memberikan `RESCUE_COINS = 200` koin kepada pemain yang kapalnya `grounded`, kargo total `0`, koin `< UPKEEP_PER_TICK`, dan telah melewati `RESCUE_COOLDOWN_TICKS = 2.880` tick, tercatat di `ledger` (`reason = 'rescue', delta = +200`).

**Sirkulasi internal (zero-sum antara pemain dan kas pelabuhan):**
- Pembelian dan penjualan komoditas beserta biaya pelabuhan 2% hanya memindahkan koin antara `players.coins` dan `ports.treasury`:
  ```text
  delta_koin_pemain + delta_kas_pelabuhan == 0
  ```

**Pengurang koin eksplisit (`pengurang_kumulatif`):**
1. **Perawatan Kapal & Pajak Logistik Kekayaan (`upkeep`, Langkah 5 tick):** Setiap kapal membayar perawatan dasar `UPKEEP_PER_TICK = 1` koin/tick ditambah surcharge logistik kekayaan `((coins - STARTER_COINS) * WEALTH_UPKEEP_BPS) / 10000` (untuk `coins > STARTER_COINS`, dengan `WEALTH_UPKEEP_BPS = 4`).
2. **Pembayaran Produsen Lokal Pelabuhan (`port_producer_payout`, Langkah 3 tick):** Ketika `desiredDelta < 0` pada pelabuhan produsen bersih, kas pelabuhan membayar produsen lokal hingga batas bawah aman `PORT_TREASURY_FLOOR = 22.000` koin, tercatat di `economy_sources_sinks` (`kind = 'sink', reason = 'port_producer_payout'`).

## Perawatan kapal & perilaku `grounded` (sesuai `docs/09` v0.2)
1. **Perawatan dipotong SEBELUM evaluasi aksi (Langkah 5 tick):**
   - Untuk kapal `docked` atau `sailing`: jika `players.coins >= upkeepDue`, potong `upkeepDue`.
   - Jika `players.coins < upkeepDue`:
     - Kapal `docked` berubah status menjadi **`grounded`** (koin tidak dipotong dan tidak menjadi negatif).
     - Kapal `sailing` **tetap berlayar** sampai tiba di pelabuhan tujuan; perawatan tick tersebut dilewati dan **tunggakan tidak diakumulasi**.
2. **Pemulihan dari `grounded`:**
   - Pada Langkah 5 tick, jika kapal berstatus `grounded` dan `players.coins >= upkeepDue`, pemain membayar `upkeepDue` dan status kapal langsung kembali menjadi **`docked`** pada tick yang sama (sehingga dapat berlayar pada Langkah 6 tick tersebut).
   - Pada Langkah 6 tick, kapal yang masih berstatus `grounded` **tetap dievaluasi aturannya**, tetapi **hanya aksi `jual` dan `tunggu` yang diizinkan**. Jika aturan memilih `beli` atau `berlayar`, aksi tersebut gagal dengan kode `GROUNDED` (dicatat di `action_log`) dan evaluasi **jatuh ke aturan berikutnya** pada tick yang sama (memungkinkan kapal menjual muatan darurat untuk mendapatkan koin).
3. **Pemulihan Darurat (Langkah 7 tick, di balik flag `RESCUE_ENABLED`):**
   - Jika setelah Langkah 6 kapal masih `grounded`, total muatan `0`, `players.coins < UPKEEP_PER_TICK`, dan `tick_no - last_rescue_tick >= RESCUE_COOLDOWN_TICKS` (`2.880` tick), sistem memberikan `RESCUE_COINS = 200` koin (`reason = 'rescue'`).

## Kekayaan bersih (peringkat)
```text
kekayaan = koin + sum_k (stok_kapal[k] * harga_dasar[k])
```
Menggunakan `harga_dasar` (bukan harga pasar lokal) agar peringkat tidak dapat dimanipulasi dengan menggoreng harga sesaat di satu pelabuhan.

## Invarian (harus selalu benar; dites otomatis setiap tick)
1. Tidak ada koin pemain (`players.coins`), kas pelabuhan (`ports.treasury`), atau stok (`market.stock`, `ship_cargo.qty`) yang negatif.
2. `players.coins + players.unflushed_upkeep == sum(ledger.delta per pemain)` di setiap tick, dan `players.coins == sum(ledger.delta per pemain)` setiap selesai flush blok upkeep / transaksi.
3. **Konservasi Uang Global (ADR-009 & ADR-010):**
   ```text
   total_koin_pemain + total_kas_pelabuhan + pengurang_kumulatif == total_awal + sumber_kumulatif
   ```
4. Harga selalu dalam `[round(dasar * 0.25), round(dasar * 4.0)]` dan bilangan bulat `>= 1`.
5. Total muatan kapal `<= kapasitas` (`ships.capacity`).
6. Stok pelabuhan selalu dalam `[0, kapasitasGudang]`.

## Gerbang kualitas otomatis `sim-cli` (`Tugas f`)
Perintah `pnpm sim:run` (`apps/worker/src/sim-cli.ts`) wajib keluar dengan **exit code non-nol (`1`)** jika salah satu ambang berikut dilanggar pada seed mana pun:
1. **Invarian & Konservasi Uang**: `invariantViolations == 0` dan `moneyConservation.valid == true`.
2. **Ketahanan Eksploit Adversarial**: `adversarial.profitableExploitsFound == 0`.
3. **Batas Harga Clamp**: Persentase tick di mana harga menempel di batas bawah (`0.25x`) atau batas atas (`4.0x`) pada komoditas mana pun **tidak boleh melebihi `20%`** (`pctTicksAtBounds <= 20%`).
4. **Harga Hidup (Tidak Konstan)**: Standar deviasi harga tiap komoditas harus positif (`stdDevPrice > 0`).
5. **Likuiditas Kas Pelabuhan**: Kas pelabuhan mana pun tidak boleh menyentuh `0` sebelum tick akhir (`minPortTreasuryCoins > 0`).
6. **Batas Kebangkrutan Bot**: Persentase bot berstatus `grounded` di akhir simulasi **tidak boleh melebihi `30%`** (`bankruptBotPct <= 30%`).
7. **Anti-Monopoli & Gradien Keahlian**: Pangsa kekayaan satu strategi tidak boleh melebihi **`40%`** (`maxStrategyWealthSharePct <= 40%`), dan pada simulasi $\ge 1.000$ tick rasio kekayaan rata-rata strategi cerdas terbaik terhadap `naive` minimal **`1,3x`** (`skillGradientRatio >= 1.3`).
8. **Stabilitas Koin Pemain Jangka Panjang**: Pada simulasi $\ge 10.000$ tick, pergeseran relatif rata-rata total koin pemain antara Kuartal 3 dan Kuartal 4 **tidak boleh melebihi `15%`** (`relativeDriftPct <= 15%`).
