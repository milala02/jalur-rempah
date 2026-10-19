# PROGRESS — Log Kemajuan & Keputusan

Perbarui di akhir setiap sesi. Terbaru di atas.

### 2026-10-19 (Sesi 7) — Perbaikan regresi tes integrasi API & worker
- `apps/api/test/api.test.ts`: ubah nama aturan invalid dari `salah` (kata kunci DSL) ke `contoh` agar kegagalan yang diuji memang `UNKNOWN_IDENT`.
- `apps/api/test/phase2.test.ts`: hadiah kontrak kedua disesuaikan ke saldo pembuat yang tersisa setelah escrow kontrak pertama; endpoint dan invarian produksi tidak diubah.
- `apps/worker/test/worker.test.ts`: gabungkan uji kesetaraan 20 tick dan crash/rollback dalam satu tes karena keduanya memakai DB fixture yang sama dan pembacaan dapat tumpang-tindih. Tes kini membuktikan semua 20 tick, tick/hash tidak berubah setelah rollback, tick selanjutnya pulih, serta konsistensi ledger. Jumlah total berkurang satu karena dua skenario menjadi satu tes; assertion inti tetap ada.
- Verifikasi VM lokal: `DATABASE_URL` menuju PostgreSQL sementara; `pnpm -w test` lulus (8 file, 43 tes), `pnpm lint` dan `pnpm typecheck` lulus. Belum diverifikasi di CI GitHub Actions.

## Status saat ini
- Milestone selesai & lulus CI GitHub Actions (`https://github.com/milala02/jalur-rempah`):
  - **M0 — Fondasi repo** (LULUS — CI Hijau)
  - **M1 — Ekonomi dan dunia tanpa pemain + Revisi v0.3 & Analisis A1–A8** (LULUS — CI Hijau)
  - **M2 — Akun, kapal, ledger, & endpoint baca** (LULUS — CI Hijau)
  - **M3 — Bahasa Aturan (`packages/dsl`)** (LULUS — CI Hijau)
  - **M4 — Tick loop worker, integrasi aturan, & sandbox `/v1/ships/:id/rules/simulate`** (LULUS — CI Hijau)
  - **M5 — Klien Flutter (`apps/mobile`) & workflow `.github/workflows/build-apk.yml`** (LULUS — CI Hijau)
  - **M6 — Pengerasan, kontrak OpenAPI (`docs/openapi.json`), skrip backup/restore, & skrip uji beban k6** (LULUS — CI Hijau)
- Selesai diimplementasikan & diverifikasi di VM pada sesi ini (siap di-push ke GitHub):
  - **Release Candidate Production Readiness (`docs/12` & `docs/13`)**: Entrypoint produksi `apps/api/src/main.ts` (`jr-api`), `apps/worker/src/main.ts` (`jr-worker`), `ecosystem.config.cjs` (PM2), dan `scripts/setup-db-roles.sql` (`api_rw`, `worker_rw`, `migrator`).
  - **Fase 2 Pasca-MVP Lengkap (`ADR-012`, Migrasi `0004_phase2_features.sql`)**:
    1. Evaluasi Data Beta (`apps/worker/src/beta-eval-cli.ts`)
    2. Kabut Informasi Harga (`public.port_intel`, `GET /v1/intel`, fungsi DSL `harga_terakhir(p, k)`)
    3. Ekstensi Bahasa Aturan & Memori Kapal (`biar x = ...`, `simpan(slot, nilai)`, `ambil(slot)`, `musim()`, `public.ship_memory`)
    4. Multi-Kapal (`POST /v1/ships/buy` hingga 5 kapal/pemain dengan konservasi kas pelabuhan)
    5. Serikat Dagang Ringan (`public.guilds`, `public.guild_members`, `GET/POST /v1/guilds`, `POST /v1/guilds/:code/join`)
    6. Kontrak Pengiriman Komoditas (`public.trade_contracts`, `GET/POST /v1/contracts`, `POST /v1/contracts/:id/fulfill` dengan mekanisme *escrow* kas pelabuhan)
    7. Musim Angin Muson, Event Dunia, SSE Stream, ETag, & Penghapusan Akun (`public.world_events`, `GET /v1/events`, `GET /v1/stream`, `ETag`/`304 Not Modified`, dan `DELETE /v1/me` dengan anonimisasi akun serta pelestarian `ledger` *append-only*).

## Log sesi
### 2026-10-19 (Sesi 6) — Penyelesaian Release Candidate Produksi & Ekspansi Penuh Fase 2 ("Setelah MVP")
- **Ringkasan Pekerjaan:**
  1. **Kesiapan Produksi VPS (`apps/api/src/main.ts`, `apps/worker/src/main.ts`, `ecosystem.config.cjs`, `scripts/setup-db-roles.sql`, commit `e2af03c`)**:
     - Menyediakan entrypoint executable `jr-api` dan `jr-worker` dengan dukungan sinyal PM2 `process.send('ready')`, *graceful shutdown* (`SIGTERM`/`SIGINT`), dan konfigurasi PM2 `ecosystem.config.cjs` sesuai `docs/12-OPERATIONS-RUNBOOK.md`.
     - Menyediakan skrip pemisahan role PostgreSQL `scripts/setup-db-roles.sql` (`api_rw`, `worker_rw`, `migrator`) sesuai matriks hak akses `docs/07-DATA-MODEL.md`.
  2. **Migrasi Skema Fase 2 (`db/migrations/0004_phase2_features.sql`, commit `e2af03c` & `14ef2c5`)**:
     - Menambahkan kolom anonimisasi akun pada `public.players` (`is_deleted`, `deleted_at`) dan melepas FK `ledger_ref_ship_fkey` agar penghapusan kapal pada `DELETE /v1/me` tidak melanggar trigger *append-only* pada `public.ledger`.
     - Membuat 6 tabel baru Fase 2: `public.port_intel`, `public.ship_memory`, `public.guilds`, `public.guild_members`, `public.trade_contracts`, dan `public.world_events`.
  3. **Ekstensi Bahasa Aturan Fase 2 (`packages/dsl`, commit `0aea61e`)**:
     - Menambahkan variabel lokal `biar <ident> = <ekspresi>` di dalam blok aturan sebelum `jika`.
     - Menambahkan fungsi baca `harga_terakhir(pelabuhan, komoditas)` (`ADR-012`), `ambil(slot)` (`0..7`), `musim()` (`1` Muson Barat, `2` Muson Timur, `3` Pancaroba), serta aksi memori `simpan(slot, nilai)`.
     - Menambahkan pengujian unit & integrasi ekstensi DSL Fase 2 di `packages/dsl/test/dsl.test.ts`.
  4. **Implementasi API, Worker Tick, & Analitik Beta Fase 2 (`apps/api` & `apps/worker`, commit `14ef2c5`)**:
     - Mengintegrasikan pembacaan/penulisan `ship_memory`, pembaruan otomatis `port_intel` bagi kapal yang bersandar, dan pencatatan musim `world_events` di dalam `executeSingleWorldTick` (`apps/worker/src/worker.ts`).
     - Mengimplementasikan `ETag` / `If-None-Match` (`304 Not Modified`), `GET /v1/stream` (SSE), `DELETE /v1/me`, `POST /v1/ships/buy`, `GET /v1/intel`, `GET /v1/events`, `GET/POST /v1/guilds`, `POST /v1/guilds/:code/join`, `GET/POST /v1/contracts`, dan `POST /v1/contracts/:id/fulfill` di `apps/api/src/app.ts`.
     - Membuat CLI evaluasi data beta `apps/worker/src/beta-eval-cli.ts` (`evaluateBetaMetrics`) dan suite tes integrasi `apps/api/test/phase2.test.ts`.
  5. **Pembaruan Klien Flutter & Dokumentasi (`apps/mobile`, `docs/04-ADR.md`, `docs/openapi.json`)**:
     - Memperbarui `apps/mobile/lib/main.dart` dan `apps/mobile/test/widget_test.dart` dengan banner musim/kabut informasi, ekspansi armada multi-kapal, dan kartu serikat dagang/kontrak.
     - Mendokumentasikan keputusan arsitektur Fase 2 di `ADR-012` (`docs/04-ADR.md`) dan memperbarui `docs/openapi.json` v0.3.0.

### 2026-10-19 (Sesi 5) — Eksekusi Otomatis Penuh Milestone M2, M3, M4, M5, dan M6
- Seluruh milestone M2, M3, M4, M5, dan M6 selesai dan terverifikasi **Hijau di CI GitHub Actions**.

### 2026-10-19 (Sesi 4) — Misi Otomatis: Revisi M1 (`P1 a–k`), Analisis Berbasis Data (`A1–A5`), & Audit Dokumen (`A6–A8`)
- Seluruh tugas P1 (`a–k`), P2 (`A1–A5`), P3 (`A6–A8`), dan P4 selesai; **CI #14 Hijau di GitHub Actions**.
