# PROGRESS — Log Kemajuan & Keputusan

Perbarui di akhir setiap sesi. Terbaru di atas.

## Status saat ini
- Milestone aktif: **M0 — Fondasi repo** (Perbaikan isolasi database & CI berdasarkan log CI pertama; menunggu verifikasi log CI kedua)
- Dokumen: draf v0.1 selesai (`docs/00`-`13`, `CLAUDE.md`); `docs/06-SPEC-EKONOMI.md` diperbarui dengan parameter pasar setimbang.

## Keputusan terbuka (perlu diputuskan pemilik)
- [ ] Nama final game (judul kerja: Jalur Rempah)
- [ ] Penyeimbang sumber koin (lihat `06`: kas NPC vs subsidi vs tanpa sumber)
- [ ] Durasi tick produksi (`TICK_SECONDS`, awal 30)
- [ ] Port/jalur dan nama database yang tidak bentrok dengan layanan lain di VPS (`12`)
- [ ] Verifikasi email di MVP atau ditunda

## Asumsi yang dipakai (tandai `[ASUMSI]` di dokumen)
- Dunia 6 pelabuhan, 4 komoditas
- Parameter ekonomi awal M0/M1: target = 400, kapasitas gudang = 1.600, e = 0.6, biaya pelabuhan = 2%. Produksi unggulan = 20, konsumsi dasar = 3, konsumsi Batavia = 8, produksi/konsumsi Makassar = 3. Total produksi global per komoditas (23) setimbang dengan total konsumsi global (23). Parameter awal ini akan di-tuning pada simulasi M1.
- Tick 30 detik; dunia beku saat worker mati
- Verifikasi M0 dijalankan via GitHub Actions CI (Node 20 + service container Postgres 16) karena sandbox VM dibatasi tanpa internet/outbound connection.

## Log sesi
### 2026-10-18 (Sesi 2) — Perbaikan Isolasi Database & CI M0
- Analisis Akar Masalah Kegagalan CI (`schema.test.ts:48`, `expected [] to include '0001_init'`):
  1. `.github/workflows/ci.yml` menjalankan `pnpm db:migrate` sebelum `pnpm -w test`, sehingga tabel dan `public.schema_migrations` (`'0001_init'`) sudah terisi di DB utama (`jalur_rempah_test`).
  2. `schema.test.ts` menjalankan `SET search_path TO testSchema, public` pada satu `client`, tetapi `runMigrations(pool)` dan `seedWorld(pool)` mengambil koneksi lain dari `pool` dengan `search_path` default (`"$user", public`). Akibatnya, `runMigrations(pool)` membaca `public.schema_migrations`, menganggap `0001_init` sudah dijalankan, mengembalikan `[]`, dan `testSchema` tidak pernah terisi.
  3. Kueri-kueri pada tes berikutnya tanpa kualifikasi schema (dengan `public` ada di `search_path`) jatuh ke tabel `public` yang dibuat oleh langkah `ci.yml`, sehingga semua tes sebenarnya menguji dan mengotori schema `public` pada DB utama.
  4. `client.release()` pada `pg.Pool` tidak mereset state sesi (`SET search_path`), sehingga pengaturan `search_path` dapat bocor antar koneksi di dalam pool.
- Dikerjakan ( dalam commit terpisah per perbaikan ):
  1. `fix(db)`: Menambahkan helper `getDatabaseNameFromUrl` dan `replaceDatabaseInUrl` di `apps/api/src/db/connection.ts`. Memperbarui `runMigrations` (`migrate.ts`) dan `seedWorld` (`seed.ts`) agar terikat ke `pool` database target dengan nama tabel eksplisit (`public.schema_migrations`, `public.commodities`, `public.ports`, `public.routes`, `public.market`) tanpa bergantung pada `search_path`.
  2. `fix(test)`: Mengganti isolasi schema di `apps/api/test/schema.test.ts` menjadi isolasi penuh per **database baru** (`CREATE DATABASE test_m0_<acak>` di `beforeAll` dan `DROP DATABASE` setelah `pg_terminate_backend` di `afterAll` menggunakan `adminPool` terpisah). Menghapus seluruh pemakaian `SET search_path`. Menambahkan:
     - Tes variasi saat tabel `public` sengaja belum ada (sebelum migrasi), membuktikan kueri dan `seedWorld` gagal eksplisit dengan kode PostgreSQL `42P01` (`relation "public.commodities" does not exist`).
     - Tes pembuktian isolasi yang memverifikasi bahwa setelah migrasi di `test_m0_<acak>`, DB utama (`jalur_rempah_test`) memiliki `0` tabel game dan tes lulus tanpa langkah `db:migrate` sebelumnya.
     - Pencatatan dan asersi `SELECT current_database()` pada setiap tes.
  3. `ci(m0)`: Mengubah instalasi dependensi di `.github/workflows/ci.yml` menjadi `pnpm install --frozen-lockfile`, menghapus langkah `pnpm db:migrate` sebelum tes, dan menambahkan langkah smoke test terpisah **sesudah** tes yang membuat database kosong baru (`jalur_rempah_smoke`) lalu menjalankan `pnpm db:migrate` terhadapnya.
- Keputusan:
  - Setiap file tes integrasi wajib membuat database tersendiri (`CREATE DATABASE test_<acak>`) melalui koneksi admin terpisah dan menghancurkannya di `afterAll`; dilarang memakai `SET search_path` pada koneksi `pg.Pool`.
- Masalah terbuka:
  - Menunggu hasil log mentah GitHub Actions CI untuk memverifikasi seluruh 7 tes di `schema.test.ts` dan smoke test `db:migrate`.

### 2026-10-18 (Sesi 1) — Milestone M0: Fondasi repo
- Dikerjakan:
  - Setup struktur monorepo pnpm (`packages/shared`, `packages/econ`, `packages/dsl`, `apps/api`, `apps/worker`).
  - Konfigurasi TypeScript strict (`tsconfig.base.json`), ESLint flat config (`eslint.config.js`), Prettier, dan Vitest.
  - Setup CI GitHub Actions (`.github/workflows/ci.yml`) dengan Node 20 dan PostgreSQL 16 service container.
  - Implementasi data seed deterministik di `packages/shared` (komoditas, pelabuhan, rute 2 arah, pasar awal setimbang).
  - Pembuatan skema migrasi `db/migrations/0001_init.sql` (`citext`, tabel inti, serta trigger append-only level baris dan level statement `BEFORE TRUNCATE` pada tabel `ledger`).
  - Runner migrasi DB (`apps/api/src/db/migrate.ts`) dan eksekutor seed idempoten (`apps/api/src/db/seed.ts`).
  - Pembuatan rangkaian tes skema (`apps/api/test/schema.test.ts`).
