# PROGRESS — Log Kemajuan & Keputusan

Perbarui di akhir setiap sesi. Terbaru di atas.

## Status saat ini
- Milestone aktif: **M1 — Ekonomi dan dunia tanpa pemain** (`m1-ekonomi`, siap diverifikasi di CI GitHub Actions)
- Milestone selesai: **M0 — Fondasi repo** (LULUS — CI Hijau)
- Dokumen: `docs/04-ADR.md` (ditambah **ADR-009**), `docs/06-SPEC-EKONOMI.md` (v0.2), dan `docs/07-DATA-MODEL.md` (v0.2) diperbarui.

## Keputusan terbuka (perlu diputuskan pemilik)
- [ ] Nama final game (judul kerja: Jalur Rempah)
- [ ] Durasi tick produksi (`TICK_SECONDS`, awal 30)
- [ ] Port/jalur dan nama database yang tidak bentrok dengan layanan lain di VPS (`12`)
- [ ] Verifikasi email di MVP atau ditunda

## Asumsi yang dipakai (tandai `[ASUMSI]` di dokumen)
- Dunia 6 pelabuhan, 4 komoditas
- Parameter ekonomi hasil tuning M1 (`WORLD_CONFIG`): `DEFAULT_TARGET = 400n`, `DEFAULT_CAPACITY = 1600n`, `PRICE_ELASTICITY = 0.6`, `PORT_FEE_PERCENT = 2`, `UPKEEP_PER_TICK = 1n`, `STARTER_COINS = 1000n`, `STARTER_SHIP_CAPACITY = 45`, `INITIAL_PORT_TREASURY = 25000000n`.
- Pangsa kekayaan maksimum satu strategi bot pada simulasi 50 bot <= 40% (`[ASUMSI X=40%]`).
- Tick 30 detik; dunia beku saat worker mati.

## Log sesi
### 2026-10-18 (Sesi 3) — Milestone M1: Ekonomi, Kas Pelabuhan, Simulator, & Tuning Parameter
- Dikerjakan (dalam commit terpisah per bagian di branch `m1-ekonomi`):
  1. `docs(m1)`: Menambahkan **ADR-009** (Eksekusi Transaksi Simetris & Kas Pelabuhan Tertutup) di `docs/04-ADR.md`, memperbarui `docs/06-SPEC-EKONOMI.md` (rumus jual simetris `stok += 1` lalu `hitungHarga(stok)`, biaya 2% masuk `ports.treasury`, invarian konservasi uang global), dan memperbarui `docs/07-DATA-MODEL.md`.
  2. `feat(db)`: Membuat migrasi `db/migrations/0002_port_treasury_and_sinks.sql` (tanpa mengubah `0001_init.sql`) yang menambahkan `treasury` dan `initial_treasury` (`BIGINT NOT NULL DEFAULT 0 CHECK >= 0`) pada `public.ports` serta view `public.economy_money_supply_audit`. Memperbarui `packages/shared` dan `apps/api/test/schema.test.ts`.
  3. `test(econ)`: Menulis tes unit dan properti (`fast-check`) lebih dulu di `packages/econ/test/{price.property.test.ts,trade.property.test.ts,sim.test.ts}` (batas harga, monotonisitas, simetri beli-lalu-jual $n \in [1..500]$ di seluruh rezim termasuk batas clamp `0.25x`/`4.0x`, kasus tepi `beli(maks)`/`jual(semua)` saat koin kurang/muatan penuh/kas kosong, konservasi uang global, dan determinisme `state_hash`).
  4. `feat(econ)`: Mengimplementasikan `packages/econ/src/{rng.ts,price.ts,production.ts,trade.ts,invariants.ts}` secara murni dan deterministik (tanpa `Date.now()`, `Math.random()`, atau I/O; satu fungsi pembulatan `bulatkanHarga` di `price.ts`; pencarian biner deterministik untuk `beli(maks)` dan `jual(semua)`).
  5. `feat(sim)`: Mengimplementasikan mesin simulasi `packages/econ/src/sim/{types.ts,engine.ts}` dengan navigasi graf terpendek multi-hop (Floyd-Warshall), 5 strategi bot (`adversarial`, `naive`, `margin_hunter`, `hoarder`, `random`), metrik lengkap, dan CLI `apps/worker/src/sim-cli.ts` (`pnpm sim:run`).
  6. `tune(econ)`: Menjalankan simulasi 50 bot x 10.000 tick pada 5 seed (`101, 202, 303, 404, 505`) sebelum dan sesudah tuning, lalu memperbarui `WORLD_CONFIG` (`STARTER_SHIP_CAPACITY`: `20 -> 45`, `INITIAL_PORT_TREASURY`: `50_000n -> 25_000_000n`).
  7. `ci(m1)`: Menambahkan `pnpm sim:short` (2.000 tick, 10 bot, 2 seed: `11,29`) pada `.github/workflows/ci.yml` di setiap push/PR, serta membuat `.github/workflows/sim-full.yml` (`workflow_dispatch`, 50 bot x 10.000 tick x 5 seed) yang mencetak JSON metrik ke log dan mengunggahnya sebagai artifact.
- Analisis & Data Tuning Parameter (50 Bot x 10.000 Tick, Seed `101, 202, 303, 404, 505`):
  - **Diagnosis Ekonomi Sebelum Tuning (`STARTER_SHIP_CAPACITY = 20`, `INITIAL_PORT_TREASURY = 50_000n`)**:
    1. *Bottleneck Kapasitas Angkut Armada*: Surplus produksi bersih di 4 pelabuhan penghasil adalah $4 \times (20 - 3) = 68$ unit/tick. Dengan rata-rata siklus pelayaran pulang-pergi $T_{\text{cycle}} \approx 16$ tick dan kapasitas kapal $C = 20$, kapasitas angkut maksimum teoritis 50 kapal hanya $\Theta_{\text{max}} = 50 \times 20 / 16 = 62,5 < 68$ unit/tick. Akibatnya stok di pelabuhan konsumen terkuras ke `0` dan harga menempel di batas `4.0x` selama **63,61%–64,14%** tick.
    2. *Kuras Likuiditas Pelabuhan Konsumen*: Batavia (`produksi = 0, konsumsi = 8` untuk keempat komoditas) adalah pengimpor murni tanpa ekspor. Dengan kas awal hanya `50.000` koin, kas Batavia habis ke `12–16` koin dalam `< 800` tick, menyebabkan **88%–96%** bot gagal menjual muatan dan bangkrut (`grounded`), serta pangsa strategi tunggal menembus **44,56%–52,36%** (> batas 40%).
  - **Perubahan Parameter (`packages/shared/src/config.ts`)**:
    1. `STARTER_SHIP_CAPACITY`: diubah dari `20` menjadi `45` (sehingga kapasitas angkut armada $\Theta_{\text{max}} = 50 \times 45 / 16 \approx 140,6 > 68$ unit/tick, cukup untuk mendistribusikan seluruh surplus produksi ke seluruh pelabuhan).
    2. `INITIAL_PORT_TREASURY`: diubah dari `50_000n` menjadi `25_000_000n` (sehingga pelabuhan pengimpor murni seperti Batavia memiliki likuiditas cukup untuk menyerap impor selama `>= 10.000` tick dan menyisakan kas sehat `~5,72–5,78 juta` koin di tick ke-10.000).
  - **Tabel Perbandingan Hasil Sebelum vs Sesudah Tuning (Seed Sama)**:
    | Seed | Metrik | Sebelum Tuning (`C=20, Kas=50rb`) | Sesudah Tuning (`C=45, Kas=25jt`) | Status Gerbang |
    |---|---|---|---|---|
    | **101** | Pelanggaran Invarian / Eksploit Adversarial | `0` / `0` | `0` / `0` (dari `611.024` uji) | LULUS |
    | **101** | % Tick di Batas Harga (`0.25x`/`4.0x`) | `64,14%` (GAGAL) | **`0,00%`** | LULUS |
    | **101** | Pangsa Strategi Maks / % Bot Bangkrut | `34,12%` / `88%` | **`28,53%`** (`naive`) / **`0%`** | LULUS |
    | **101** | Gini Kekayaan / State Hash (2x jalan identik) | `0,4193` | **`0,2092`** / `bb2834fd1466f01e...` | LULUS |
    | **202** | Pelanggaran Invarian / Eksploit Adversarial | `0` / `0` | `0` / `0` (dari `611.968` uji) | LULUS |
    | **202** | % Tick di Batas Harga (`0.25x`/`4.0x`) | `63,99%` (GAGAL) | **`0,00%`** | LULUS |
    | **202** | Pangsa Strategi Maks / % Bot Bangkrut | `44,56%` (GAGAL) / `94%` | **`25,60%`** (`naive`) / **`0%`** | LULUS |
    | **202** | Gini Kekayaan / State Hash (2x jalan identik) | `0,4338` | **`0,1790`** / `f381cacbee84366c...` | LULUS |
    | **303** | Pelanggaran Invarian / Eksploit Adversarial | `0` / `0` | `0` / `0` (dari `607.360` uji) | LULUS |
    | **303** | % Tick di Batas Harga (`0.25x`/`4.0x`) | `64,12%` (GAGAL) | **`0,00%`** | LULUS |
    | **303** | Pangsa Strategi Maks / % Bot Bangkrut | `36,01%` / `92%` | **`27,07%`** (`naive`) / **`0%`** | LULUS |
    | **303** | Gini Kekayaan / State Hash (2x jalan identik) | `0,3659` | **`0,1948`** / `9eb29cfe3c0674ef...` | LULUS |
    | **404** | Pelanggaran Invarian / Eksploit Adversarial | `0` / `0` | `0` / `0` (dari `610.064` uji) | LULUS |
    | **404** | % Tick di Batas Harga (`0.25x`/`4.0x`) | `63,92%` (GAGAL) | **`0,00%`** | LULUS |
    | **404** | Pangsa Strategi Maks / % Bot Bangkrut | `52,36%` (GAGAL) / `96%` | **`27,28%`** (`hoarder`) / **`0%`** | LULUS |
    | **404** | Gini Kekayaan / State Hash (2x jalan identik) | `0,4644` | **`0,1678`** / `2229ad2354a92f4d...` | LULUS |
    | **505** | Pelanggaran Invarian / Eksploit Adversarial | `0` / `0` | `0` / `0` (dari `609.072` uji) | LULUS |
    | **505** | % Tick di Batas Harga (`0.25x`/`4.0x`) | `63,61%` (GAGAL) | **`0,00%`** | LULUS |
    | **505** | Pangsa Strategi Maks / % Bot Bangkrut | `29,10%` / `96%` | **`28,66%`** (`naive`) / **`0%`** | LULUS |
    | **505** | Gini Kekayaan / State Hash (2x jalan identik) | `0,3525` | **`0,2344`** / `d8f3de4e277c206f...` | LULUS |
- Masalah terbuka:
  - Menunggu eksekusi CI GitHub Actions untuk branch `m1-ekonomi` (`pnpm lint`, `pnpm typecheck`, `pnpm -w test`, dan `pnpm sim:short`).

### 2026-10-18 (Sesi 2) — Perbaikan Isolasi Database & CI M0
- Dikerjakan: Isolasi penuh per database baru (`CREATE DATABASE test_m0_<acak>`), penghapusan `SET search_path`, kualifikasi eksplisit `public.schema_migrations`, dan pemindahan smoke test `pnpm db:migrate` ke DB kosong terpisah sesudah tes. Status: **LULUS (CI Hijau)**.
