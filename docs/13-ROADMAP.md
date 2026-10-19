# 13 — Roadmap & Pemecahan Tugas v0.3

Tiap milestone punya **gerbang lulus** terukur. Jangan mulai milestone berikut sebelum gerbang lulus. Satu tugas = satu sesi AI.

## M0 — Fondasi repo
- [x] Monorepo pnpm, TypeScript strict, ESLint/Prettier, Vitest
- [x] CI GitHub Actions (lint, typecheck, test)
- [x] Koneksi DB, runner migrasi, migrasi 0001 (skema `07`)
- [x] Seed dunia dari `packages/shared`
- **Gerbang:** CI hijau; `pnpm db:migrate` dari DB kosong sukses; tes skema lulus (LULUS — CI Hijau)

## M1 — Ekonomi dan dunia tanpa pemain
- [x] `packages/econ`: `hitungHarga`, produksi/konsumsi (tes properti dulu)
- [x] Eksekusi transaksi dengan slippage dan biaya (`N = G - F <= treasury`, `ZERO_PROCEEDS`)
- [x] Simulator `sim:run` dengan bot beragam strategi & adversarial
- [x] Tuning parameter awal (`06`) + mekanisme pendapatan pelabuhan konsumen (`sumber_kumulatif`, Migrasi `0003`)
- **Gerbang (diterapkan sebagai kode di `sim-cli`):** 50 bot x 10.000 tick x 5 seed tuning + 5 seed validasi lulus semua invarian; run panjang 200.000 tick (kas pelabuhan tidak habis, total koin pemain stabil); sensitivitas 10, 25, 50, 100 bot; harga hidup dan tidak menempel di batas; hasil dicatat di PROGRESS dan artifact CI (LULUS — CI #14 Hijau)

## M2 — Akun, kapal, ledger
- [x] Auth (`POST /v1/auth/register`, `login`, `refresh` dengan rotasi & deteksi pencurian token, `logout`) + tes otorisasi (`apps/api/src/auth/crypto.ts`, `apps/api/src/app.ts`)
- [x] Pembuatan pemain + kapal awal + ledger starter dalam satu transaksi DB
- [x] Endpoint baca: `/v1/me`, `/v1/me/ledger`, `/v1/world`, `/v1/world/market/:portCode`, `/v1/world/price-history`, `/v1/leaderboard`, `/v1/rule-templates`, `/v1/ships`, `/v1/ships/:id`
- [x] Skrip & fungsi pemeriksaan konsistensi (`apps/api/src/db/consistency.ts`)
- **Gerbang:** tes integrasi `apps/api/test/api.test.ts`; konsistensi ledger 0 pelanggaran (LULUS — CI Hijau)

## M3 — Bahasa Aturan
- [x] Lexer (`packages/dsl/src/lexer.ts`) + tes baris/kolom & komentar `#`
- [x] Parser EBNF (`packages/dsl/src/parser.ts`) + galat berlokasi + 32 golden tests
- [x] Validator statis (`packages/dsl/src/validator.ts`: 11 kode galat statis, saran Levenshtein, batas aturan/node/panjang/kedalaman)
- [x] Evaluator deterministik (`packages/dsl/src/evaluator.ts`: anggaran 500 node, galat runtime `DIV_ZERO`, `OVERFLOW`, `BUDGET_EXCEEDED`, adapter `createDslShipRuleDecider`)
- [x] Fuzz + adversarial + determinisme (`packages/dsl/test/dsl.test.ts`)
- **Gerbang:** semua tes wajib di `05` lulus di CI (LULUS — CI Hijau)

## M4 — Tick loop dan integrasi aturan
- [x] Worker: penjadwal anti-drift, koneksi khusus `pg_try_advisory_lock`, pemulihan restart dari `max(tick_no) + 1` (`apps/worker/src/worker.ts`)
- [x] Tick: urutan `09` v0.2 lengkap dalam satu transaksi `READ COMMITTED`, aksi nyata ke DB, `unflushed_upkeep`, `action_log`
- [x] `GET/PUT /v1/ships/:id/rules` (dengan `VERSION_CONFLICT`), `GET /v1/ships/:id/rules/versions`, `POST /v1/rules/validate`, `POST /v1/ships/:id/rules/simulate` (sandbox dengan batas antrean/concurrency)
- [x] Invarian cepat (rollback jika gagal) dan metrik `WorkerMetrics`
- [x] Satu implementasi tick: `stepWorld` murni dipakai worker, simulator, dan sandbox (tanpa logika tick ganda)
- **Gerbang:** tes pemulihan crash/rollback, 100 kapal bot tick lag p95 < 20%, tes sandbox 0 DB writes, dan tes kesetaraan `state_hash` worker DB == simulator di `apps/worker/test/worker.test.ts` (LULUS — CI Hijau)

## M5 — Klien Flutter dan APK
- [x] Login/daftar, penyimpanan token sesi (`apps/mobile/lib/main.dart`)
- [x] Peta/daftar pelabuhan, layar pasar, grafik harga 24 jam (`CustomPainter`)
- [x] Editor aturan (validasi real-time, pemilih templat, uji sandbox 200 tick)
- [x] Layar kapal dan log aksi, peringkat kekayaan bersih
- [x] Widget test (`apps/mobile/test/widget_test.dart`) & workflow `.github/workflows/build-apk.yml`
- **Gerbang:** workflow `build-apk` menjalankan `flutter analyze`, `flutter test`, dan `flutter build apk --release` (LULUS — CI Hijau)

## M6 — Pengerasan dan beta tertutup
- [x] Rate limit per kelompok (`apps/api/src/rate-limit.ts`), batas ukuran payload `64 KB`, header `X-Tick`, pemeriksaan `X-Client-Version` (`426 CLIENT_OUTDATED`)
- [x] Skema kontrak OpenAPI 3.1 (`docs/openapi.json`) + tes kontrak di `apps/api/test/api.test.ts`
- [x] Skrip cadangan harian (`scripts/backup-db.sh` dengan `umask 077` & retensi 14 hari) + skrip uji restore otomatis (`scripts/restore-verify.sh`)
- [x] Skrip tes muat k6 untuk 100–500 pemain (`scripts/load-test.mjs`)
- [x] Templat aturan siap pakai (`RULE_TEMPLATES` di `packages/dsl/src/templates.ts`)
- **Gerbang:** seluruh kriteria teknis MVP di `02` lulus di CI GitHub Actions (LULUS — CI Hijau)

## Setelah MVP / Fase 2 (Selesai Diimplementasikan — Migrasi `0004` & `ADR-012`)
- [x] 1. Evaluasi data beta (ekonomi, Gini, konservasi uang, retensi 200 tick): `apps/worker/src/beta-eval-cli.ts` (`pnpm --filter @jalur-rempah/worker beta:eval`)
- [x] 2. Kabut informasi (`ADR-012`): tabel `public.port_intel`, endpoint `GET /v1/intel`, fungsi DSL `harga_terakhir(p, k)`
- [x] 3. Banyak kapal & memori kapal: endpoint `POST /v1/ships/buy` (hingga 5 kapal/pemain dengan konservasi kas pelabuhan), tabel `public.ship_memory` (`simpan(slot, nilai)` & `ambil(slot)`), dan variabel lokal `biar <ident> = <ekspr>`
- [x] 4. Fitur sosial ringan (kontrak & serikat dagang): tabel `public.guilds`, `public.guild_members`, `public.trade_contracts`, endpoint `/v1/guilds`, `/v1/guilds/:code/join`, `/v1/contracts`, `/v1/contracts/:id/fulfill`, serta penghapusan/anonimisasi akun `DELETE /v1/me`
- [x] 5. Event, musim, SSE, & kesiapan produksi VPS: tabel `public.world_events`, fungsi DSL `musim()`, endpoint `GET /v1/events`, `GET /v1/stream` (SSE), dukungan `ETag`/`304 Not Modified`, entrypoint produksi `apps/api/src/main.ts` & `apps/worker/src/main.ts`, `ecosystem.config.cjs` (PM2), serta `scripts/setup-db-roles.sql`

## Aturan pergantian scope
Fitur baru butuh: tujuan, dampak ekonomi, perubahan dokumen, tes. Catat di ADR bila mengubah arsitektur.

## Definisi Release Candidate (siap CI dan build test)
Satu commit dengan semua job CI hijau:
1. `lint`, `typecheck`, `test` (unit, properti, integrasi dengan Postgres nyata)
2. `sim:short` dengan semua gerbang kualitas
3. `build` backend (`tsc -b`) dan smoke test `db:migrate` pada database kosong
4. Workflow Flutter: `flutter analyze`, `flutter test`, `flutter build apk --release` menghasilkan artifact APK
5. Simulasi penuh (`workflow_dispatch`) hijau pada commit yang sama, artifact tersimpan
6. Tidak ada tes `skip`/`todo`, tidak ada rahasia di repo, `docs/PROGRESS.md` mutakhir
