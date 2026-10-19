# PROGRESS — Log Kemajuan & Keputusan

Perbarui di akhir setiap sesi. Terbaru di atas.

## Status saat ini
- Milestone aktif: **M1 — Ekonomi dan dunia tanpa pemain (Revisi v0.3 + Analisis A1–A8)** (`m1-ekonomi`, siap dibawa ke GitHub Actions CI; gerbang M1 **BELUM dinyatakan lulus** sebelum CI hijau)
- Milestone selesai: **M0 — Fondasi repo** (LULUS — CI Hijau)
- Dokumen diperbarui:
  - Paket v0.3 diterapkan (`CLAUDE.md`, `docs/00, 03, 05, 08, 09, 10, 13`, `docs/AUDIT-v0.3.md`)
  - `docs/04-ADR.md` (ditambah **ADR-010** & **ADR-011**)
  - `docs/06-SPEC-EKONOMI.md` (v0.3: rumus blok kode teks biasa, syarat kas jual `N <= treasury`, mekanisme pendapatan pelabuhan `sumber_kumulatif`, aturan `grounded` sesuai `docs/09` v0.2, ambang gerbang `sim-cli`)
  - `docs/07-DATA-MODEL.md` (v0.3: skema Migrasi `0003`, `economy_sources_sinks`, `unflushed_upkeep`, `idx_ledger_player_non_upkeep`, kueri konsistensi baru)
  - `docs/11-THREAT-MODEL.md` (v0.2) & `docs/12-DEPLOYMENT-RUNBOOK.md` (v0.2 dengan penanda `[PERLU VERIFIKASI PEMILIK]`)
  - Laporan Analisis & Audit: `docs/analisis/A1..A8.md` beserta data mentah ringkas di `docs/analisis/data/*.json`

## Rencana putaran ini (Revisi M1 + Analisis v0.3 — SELESAI DI VM, SIAP UJI CI)
1. **P0 — Sinkronisasi Dokumen v0.3 & Rencana**: Diterapkan pada commit `83ea532`.
2. **P1 — Revisi M1 (Tugas `a` s.d. `k`)**: Diterapkan pada commit `c14a933`, `8a2686e`, `3b9144f`, dan sinkronisasi dokumen P4.
3. **P2 — Analisis Berbasis Data (`A1` s.d. `A5`)**: Diterapkan pada commit `1a3a8c9` (`docs/analisis/A1..A5.md` + `docs/analisis/data/*.json`).
4. **P3 — Audit Dokumen (`A6` s.d. `A8`)**: Diterapkan pada commit `d87f246` (`docs/analisis/A6..A8.md`).
5. **P4 — Sinkronisasi Dokumen & Laporan Akhir**: Diterapkan pada commit akhir branch `m1-ekonomi`.

## Keputusan terbuka (milik pemilik — disediakan opsi, rekomendasi berdata, dan flag konfigurasi)
- [ ] **1. Pemulihan Darurat (`RESCUE_ENABLED`)**: Default saat ini `true` (`RESCUE_COINS = 200n`, `RESCUE_COOLDOWN_TICKS = 2880` di `packages/shared/src/config.ts`). **Rekomendasi (`A3`):** Aktifkan (`true`), karena mencegah *churn* permanen akun pemula yang salah menulis aturan awal dengan inflasi hanya `0,24%` dalam 10.000 tick dan `0` eksploitasi menguntungkan.
- [ ] **2. Verifikasi Email di MVP (`REQUIRE_EMAIL_VERIFICATION`)**: **Rekomendasi (`A7`):** Tunda verifikasi email SMTP di MVP (agar target onboarding `< 3 menit` tercapai tanpa ketergantungan layanan email pihak ketiga) dan andalkan mitigasi struktural (tanpa transfer langsung antar-pemain, biaya pelabuhan 2% dua arah, rate limit pendaftaran `5/jam/IP`, serta deteksi korelasi pasangan akun di `ledger`).
- [ ] **3. Nama Game & `TICK_SECONDS`**: Judul kerja `Jalur Rempah`, `TICK_SECONDS = 30`. **Rekomendasi (`A1`):** Pertahankan `TICK_SECONDS = 30` (waktu pelayaran 1,5–3 menit dan waktu balik modal 2x bagi aturan cerdas ~28 menit).
- [ ] **4. Teknologi Klien M5 (`ADR-007` — lihat `docs/analisis/A8-audit-gdd-prd-kelayakan-m5.md`)**: Lingkungan VM tidak memiliki SDK Flutter/Android maupun internet. **Rekomendasi Utama (`A8`):** Gunakan Klien Web/PWA TypeScript yang berbagi langsung `@jalur-rempah/dsl` (100% teruji di VM Node.js sebelum masuk CI) lalu dibungkus menjadi APK Android di GitHub Actions CI (Capacitor/WebView). **Rekomendasi Alternatif jika tetap Flutter Murni:** Gunakan hanya pustaka standar bawaan SDK Flutter tanpa paket pihak ketiga yang rawan konflik resolusi versi, dan bagi M5 menjadi 2 irisan CI kecil.
- [ ] **5. Port, Database, dan Konfigurasi nginx di VPS (`docs/12`)**: Seluruh asumsi (`PORT_API=3100`, port PostgreSQL `5432`, nama DB `jalurrempah`, vhost nginx, lokasi offsite backup) ditandai `[PERLU VERIFIKASI PEMILIK]` di `docs/12-DEPLOYMENT-RUNBOOK.md`.

## Asumsi yang dipakai (tandai `[ASUMSI]` di dokumen)
- Dunia 6 pelabuhan, 4 komoditas, keseimbangan produksi = konsumsi global (`total_prod == total_cons == 23` unit/tick per komoditas).
- Parameter ekonomi hasil analisis A1–A4 (`WORLD_CONFIG` di `packages/shared/src/config.ts`):
  - `DEFAULT_TARGET = 400n`, `DEFAULT_CAPACITY = 1600n`, `ELASTICITY = 0.6`, `PORT_FEE_PERCENT = 2`, `PORT_FEE_MIN = 1n`
  - `STARTER_COINS = 1000n`, `STARTER_SHIP_CAPACITY = 35`
  - `INITIAL_PORT_TREASURY = 50000n` (`6x` total modal awal 50 pemain <= batas `10x`)
  - `PORT_INCOME_ENABLED = true`, `PORT_TREASURY_FLOOR = 22000n`, `PORT_TREASURY_RESTORE_DIVISOR = 2n`
  - `UPKEEP_PER_TICK = 1n`, `WEALTH_UPKEEP_BPS = 4`
  - `RESCUE_ENABLED = true`, `RESCUE_COINS = 200n`, `RESCUE_COOLDOWN_TICKS = 2880`
  - `DEMAND_SHOCK_ENABLED = true`, `DEMAND_SHOCK_INTERVAL_TICKS = 40`, `DEMAND_SHOCK_MAGNITUDE = 5n`
  - `SCALE_MARKET_WITH_FLEET = true`, `UPKEEP_LEDGER_BATCH_TICKS = 120`

## Log sesi
### 2026-10-19 (Sesi 4) — Misi Otomatis: Revisi M1 (`P1 a–k`), Analisis Berbasis Data (`A1–A5`), & Audit Dokumen (`A6–A8`)
- **Status Tugas P1 (`a` s.d. `k`):**
  | Tugas | Deskripsi | Status | Bukti File / Data |
  | :---: | :--- | :---: | :--- |
  | **a** | Diagnosis berdata kas 50.000 (kapan habis, efek ke harga & bot) + kurva kas Batavia sampai 200.000 tick pada konfigurasi 25.000.000 | **SELESAI** | `docs/analisis/A2-pendapatan-pelabuhan.md`, `docs/analisis/data/a2-port-income-diagnosis.json` |
  | **b** | Mekanisme pendapatan pelabuhan eksplisit (`sumber_kumulatif`), `INITIAL_PORT_TREASURY = 50.000` (`6x <= 10x`), migrasi `0003` (tanpa ubah `0001`/`0002`) | **SELESAI** | `packages/econ/src/invariants.ts`, `db/migrations/0003_port_income_and_ledger_compaction.sql`, `apps/api/test/schema.test.ts` |
  | **c** | Horizon panjang 200.000 tick (`15` bot, seed `101`) dengan sampel deret waktu kas pelabuhan, koin pemain, & harga rata-rata | **SELESAI** | `docs/analisis/data/horizon-200k-seed101.json`, `.github/workflows/sim-full.yml` |
  | **d** | Sensitivitas jumlah bot `10, 25, 50, 100` (3 seed `101, 202, 303`) membandingkan kapasitas `20`, `45`, dan `35` adaptif (`SCALE_MARKET_WITH_FLEET`) | **SELESAI** | `docs/analisis/A1-parameter-ekonomi.md`, `docs/analisis/data/d-bot-sensitivity.json` |
  | **e** | Pulihkan cek keseimbangan produksi = konsumsi global (`23 == 23`) di `schema.test.ts` dan tambah tes unit langsung pada `MARKET_SEED` | **SELESAI** | `apps/api/test/schema.test.ts`, `packages/econ/test/price.property.test.ts` |
  | **f** | Gerbang kualitas ketat di `sim-cli.ts` (`pctTicksAtBounds <= 20%`, `stdDevPrice > 0`, `minPortTreasury > 0`, `bankruptBotPct <= 30%`, `maxStrategyShare <= 40%`, `skillGradient >= 1.3x`, `relativeDriftPct <= 15%`) | **SELESAI** | `packages/econ/src/sim/engine.ts`, `apps/worker/src/sim-cli.ts`, `docs/06-SPEC-EKONOMI.md` |
  | **g** | Laporan kekayaan rata-rata dan margin per transaksi (`avgMarginPerTx`) tiap strategi pada tiap konfigurasi | **SELESAI** | `docs/analisis/A1-parameter-ekonomi.md`, `docs/analisis/A4-gradien-keahlian.md`, `docs/analisis/data/d-bot-sensitivity.json` |
  | **h** | Perbaiki rumus LaTeX rusak di `docs/06` menjadi teks biasa dalam blok kode | **SELESAI** | `docs/06-SPEC-EKONOMI.md` |
  | **i** | Samakan syarat kas jual `N = G - F <= treasury` antara kode & `docs/06`, tambah tes batas tepat (`G = treasury`, `N = treasury`, `N - 1`) | **SELESAI** | `packages/econ/src/trade.ts`, `packages/econ/test/trade.property.test.ts`, `docs/06-SPEC-EKONOMI.md` |
  | **j** | Perbaiki `.github/workflows/sim-full.yml` (`if: always()` pada upload artifact, `timeout-minutes: 60`, nilai `inputs` lewat `env`) | **SELESAI** | `.github/workflows/sim-full.yml` |
  | **k** | Terapkan `docs/09` v0.2 pada fungsi murni `stepWorld` (perawatan sebelum aksi, `grounded` boleh jual + fallthrough `GROUNDED`, tunggakan tidak diakumulasi saat `sailing`, rescue di balik flag) | **SELESAI** (integrasi ke worker DB dicatat sebagai tugas M4) | `packages/econ/src/step-world.ts`, `packages/econ/test/sim.test.ts` |

- **Pemisahan Hasil Verifikasi VM vs CI:**
  - **Perintah CI yang BELUM DIJALANKAN di VM (karena tidak ada `pnpm`/`vitest`/`eslint`/`tsc`/`postgres` dan tidak ada internet di VM):**
    - `pnpm lint` -> **BELUM DIJALANKAN** (menunggu CI GitHub Actions)
    - `pnpm typecheck` -> **BELUM DIJALANKAN** (menunggu CI GitHub Actions)
    - `pnpm -w test` (termasuk `apps/api/test/schema.test.ts` yang membutuhkan PostgreSQL 16 aktif) -> **BELUM DIJALANKAN** (menunggu CI GitHub Actions)
  - **Hasil Verifikasi VM (`Node.js v18.20.4`, transpilasi TypeScript via `@babel/core` + `@babel/preset-typescript` di `/usr/share/nodejs`):**
    - Eksekusi seluruh suite tes `packages/econ/test/{price.property.test.ts,trade.property.test.ts,sim.test.ts}` (15/15 tes unit & properti): **LULUS di VM**.
    - Eksekusi `sim-cli.js --ticks 10000 --bots 50 --seed 101,202,303,404,505,1001,1002,1003,1004,1005`: **10/10 seed LULUS seluruh gerbang di VM** (exit code `0`).
    - Eksekusi `sim-cli.js --ticks 200000 --bots 15 --seed 101`: **LULUS seluruh gerbang di VM** (`invariantViolations = 0`, `minPortTreasury = 28.820`, `relativeDriftPct = 1,65% <= 15%`, `skillGradientRatio = 6,98x`).

### 2026-10-18 (Sesi 3) — Milestone M1 Awal (Digantikan oleh Revisi Sesi 4 di Atas)
- Lihat riwayat commit `e02318e` dan `a299e0e`; temuan bahwa `INITIAL_PORT_TREASURY = 25.000.000` hanya menunda kehabisan kas Batavia dan `STARTER_SHIP_CAPACITY = 45` hanya cocok untuk 50 kapal telah diperbaiki secara struktural pada Sesi 4 melalui **ADR-010** dan **ADR-011**.

### 2026-10-18 (Sesi 2) — Perbaikan Isolasi Database & CI M0
- Dikerjakan: Isolasi penuh per database baru (`CREATE DATABASE test_m0_<acak>`), penghapusan `SET search_path`, kualifikasi eksplisit `public.schema_migrations`, dan pemindahan smoke test `pnpm db:migrate` ke DB kosong terpisah sesudah tes. Status: **LULUS (CI Hijau)**.
