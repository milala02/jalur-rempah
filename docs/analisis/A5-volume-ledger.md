# Analisis A5 — Volume Tabel `ledger` dari Perawatan Kapal & Desain Agregasi Audit-Safe

**Tanggal:** 2026-10-19  
**Lingkungan Eksekusi:** VM lokal (`Node.js v18.20.4`, x86_64 Debian GNU/Linux 12)  
**Berkas Data Pendukung:** `docs/analisis/data/a5-ledger-volume.json`

---

## 1. Rumusan Masalah

Jika perawatan kapal (`upkeep`) dicatat **satu baris per kapal per tick** ke tabel `public.ledger`, maka pada `TICK_SECONDS = 30` detik:
- 1 hari = `2.880` tick; 1 bulan kalender (30 hari) = **`86.400` tick**; 1 bulan uji beban panjang (sesuai prompt M1) = **`250.000` tick**.
- Sementara itu, kapal rata-rata hanya melakukan transaksi beli/jual setiap ~8 tick (`0,125` transaksi dagang per kapal per tick).
- Akibatnya, baris `'upkeep'` mendominasi **88,89%** dari seluruh isi tabel `ledger`, memperlambat kueri riwayat pemain (`GET /me/ledger`) dan kueri audit konsistensi saldo (`SUM(ledger.delta) == players.coins`).

---

## 2. Perhitungan Kuantitatif Pertumbuhan Baris & Ukuran Tabel (`a5-ledger-volume.json`)

Asumsi ukuran fisik PostgreSQL 16 (berdasarkan struktur kolom `public.ledger` di `0001_init.sql`: `id BIGINT`, `player_id BIGINT`, `tick_no BIGINT`, `delta BIGINT`, `reason TEXT`, `meta JSONB`, `created_at TIMESTAMPTZ` + tuple header 23 byte + alignment = **~136 byte/baris**, ditambah 2 indeks B-Tree `PRIMARY KEY (id)` dan `idx_ledger_player_tick (player_id, tick_no DESC)` = **~56 byte/baris**, total **~192 byte/baris**):

| Skenario Armada & Horizon | Metrik | Opsi 1: Satu Baris per Kapal per Tick (`rowPerTick`) | Opsi 2: Agregasi per Blok 120 Tick / 1 Jam (`batch120Ticks`) | Opsi 3: Penghitung Kumulatif di `players` + Ringkasan Berkala 1.000 Tick (`counterPlusSummary`) |
| :--- | :--- | :---: | :---: | :---: |
| **50 Kapal — 1 Bulan Kalender (`86.400` tick)** | Baris Upkeep / Bulan | `4.320.000` | `36.000` | `4.320` |
| | Total Baris Ledger / Bulan (termasuk `540.000` baris dagang) | `4.860.000` | `576.000` (**-88,15%**) | `544.320` (**-88,80%**) |
| | Ukuran Tabel + Indeks / Bulan | **889,89 MB** | **105,47 MB** | **99,67 MB** |
| | Ukuran Tabel + Indeks / Tahun | **10,43 GB** | **1,24 GB** | **1,17 GB** |
| **500 Kapal — 1 Bulan Kalender (`86.400` tick)** | Baris Upkeep / Bulan | `43.200.000` | `360.000` | `43.200` |
| | Total Baris Ledger / Bulan (termasuk `5.400.000` baris dagang) | `48.600.000` | `5.760.000` (**-88,15%**) | `5.443.200` (**-88,80%**) |
| | Ukuran Tabel + Indeks / Bulan | **8.898,93 MB (~8,69 GB)** | **1.054,69 MB (~1,03 GB)** | **996,68 MB (~0,97 GB)** |
| | Ukuran Tabel + Indeks / Tahun | **104,28 GB** | **12,36 GB** | **11,68 GB** |
| **500 Kapal — Horizon 250.000 Tick** | Baris Upkeep / Periode | `125.000.000` | `1.041.667` | `125.000` |
| | Total Baris Ledger / Periode | `140.625.000` | `16.666.667` (**-88,15%**) | `15.750.000` (**-88,80%**) |
| | Ukuran Tabel + Indeks / Periode | **25,15 GB** | **2,98 GB** | **2,82 GB** |

### Dampak pada Kueri `/me/ledger` dan Audit Konsistensi
1. **`GET /me/ledger?limit=50`**:
   - Pada Opsi 1, 50 baris terakhir seorang pemain hampir seluruhnya berisi `-1 koin (upkeep)` sehingga transaksi jual/beli yang bermakna tenggelam.
   - Dengan indeks parsial `idx_ledger_player_non_upkeep ON public.ledger (player_id, id DESC) WHERE reason <> 'upkeep'` ditambah agregasi blok, kueri histori perdagangan menjadi $O(\log N_{\text{trade}})$ (< 0,2 ms) dan tidak perlu memindai jutaan baris perawatan.
2. **Audit Konsistensi (`SUM(ledger.delta) == players.coins`)**:
   - Pada 500 kapal dengan Opsi 1, full-table aggregate scan `GROUP BY player_id` harus memindai **48,6 juta baris/bulan** (~15–25 detik di VPS 1–2 vCPU).
   - Pada desain hibrida Opsi 2+3 (agregasi blok `UPKEEP_LEDGER_BATCH_TICKS = 120` tick dengan kolom `players.unflushed_upkeep`), jumlah baris turun **8,4x lipat** (`5,76 juta` baris/bulan pada 500 kapal, atau `576 ribu` baris/bulan pada 50 kapal).

---

## 3. Perbandingan Desain & Keputusan Arsitektur (`ADR-011`)

| Kriteria | Opsi 1: Baris per Tick Murni | Opsi 2: Agregasi per Blok 120 Tick Saja (Tanpa Kolom Akumulator) | **Desain Hibrida Terpilih (Opsi 2 + Opsi 3): Penghitung `unflushed_upkeep` & `cumulative_upkeep_paid` di `players` + Flush Ringkasan Berkala Tiap `120` Tick / Saat Transaksi** |
| :--- | :--- | :--- | :--- |
| **Pengurangan Volume Baris** | 0% (baseline) | -88,15% | **-88,15% s.d. -88,80%** (baris upkeep turun **99,17%**) |
| **Invarian `players.coins == SUM(ledger.delta)` pada saat flush / transaksi** | Eksak setiap tick | Hanya eksak pada batas blok 120 tick | **Eksak setiap tick melalui `players.coins + players.unflushed_upkeep == SUM(ledger.delta)`, dan `players.coins == SUM(ledger.delta)` setiap kali di-flush (`unflushed_upkeep = 0`)!** |
| **Invarian Konservasi Uang Global (`economy_money_supply_audit`)** | Eksak setiap tick | Meleset di tengah blok jika belum di-flush | **Eksak di setiap tick** karena `economy_money_supply_audit` menjumlahkan `SUM(-delta WHERE reason='upkeep') + SUM(players.unflushed_upkeep)` |
| **Jejak Audit (`meta` JSONB)** | 1 baris/tick | 1 baris/120 tick | Menyimpan `{"from_tick": t0, "to_tick": t1, "ticks_count": k}` pada baris ringkasan `ledger` serta `cumulative_upkeep_paid` di `players` |

---

## 4. Implementasi di Migrasi `0003` & Pembaruan `docs/07`

Diimplementasikan di `db/migrations/0003_port_income_and_ledger_compaction.sql` dan diuji di `apps/api/test/schema.test.ts` (Tes 7.4):
1. Menambahkan kolom `unflushed_upkeep BIGINT NOT NULL DEFAULT 0 CHECK (unflushed_upkeep >= 0)` dan `cumulative_upkeep_paid BIGINT NOT NULL DEFAULT 0 CHECK (cumulative_upkeep_paid >= 0)` pada tabel `public.players`.
2. Menambahkan indeks parsial `idx_ledger_player_non_upkeep ON public.ledger (player_id, id DESC) WHERE reason <> 'upkeep'`.
3. Memperbarui view `public.economy_money_supply_audit` agar menyertakan `SUM(players.unflushed_upkeep)` di dalam `cumulative_upkeep_sink`.
4. Menetapkan aturan flush: worker meng-flush `unflushed_upkeep` menjadi satu baris `ledger` (`reason = 'upkeep', delta = -unflushed_upkeep`) setiap `UPKEEP_LEDGER_BATCH_TICKS = 120` tick (1 jam waktu nyata), atau segera sebelum mencatat transaksi `buy`/`sell`/`rescue` pemain tersebut, sehingga setiap kali terjadi perubahan saldo non-upkeep atau snapshot audit, `unflushed_upkeep = 0` dan `players.coins == SUM(ledger.delta)` terpenuhi secara harfiah.

---

## 5. Risiko & Ketidakpastian

- **Risiko**: Jika kueri eksternal memeriksa `players.coins == SUM(ledger.delta)` tepat di tengah blok 120 tick tanpa membaca `players.unflushed_upkeep` atau tanpa memanggil flush lebih dulu, akan tampak selisih sebesar `unflushed_upkeep` (maksimal ~120 koin). Karena itu `docs/07` mendokumentasikan kedua kueri (kueri pasca-flush `p.coins <> COALESCE(l.s, 0)` dan kueri lintas-tick `(p.coins + p.unflushed_upkeep) <> COALESCE(l.s, 0)`).
- **Apa yang Belum Diketahui**: Apakah di M3/M5 pemain menginginkan filter khusus di UI untuk menyembunyikan/menampilkan baris ringkasan perawatan per jam pada layar riwayat koin (`/me/ledger`).
