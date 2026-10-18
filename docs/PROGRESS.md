# PROGRESS — Log Kemajuan & Keputusan

Perbarui di akhir setiap sesi. Terbaru di atas.

## Status saat ini
- Milestone aktif: **M0 — Fondasi repo**
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
### 2026-10-18 — Milestone M0: Fondasi repo
- Dikerjakan:
  - Setup struktur monorepo pnpm (`packages/shared`, `packages/econ`, `packages/dsl`, `apps/api`, `apps/worker`).
  - Konfigurasi TypeScript strict (`tsconfig.base.json`), ESLint flat config (`eslint.config.js`), Prettier, dan Vitest.
  - Setup CI GitHub Actions (`.github/workflows/ci.yml`) dengan Node 20 dan PostgreSQL 16 service container.
  - Implementasi data seed deterministik di `packages/shared` (komoditas, pelabuhan, rute 2 arah, pasar awal setimbang).
  - Pembuatan skema migrasi `db/migrations/0001_init.sql` (`citext`, tabel inti, serta trigger append-only level baris dan level statement `BEFORE TRUNCATE` pada tabel `ledger`).
  - Runner migrasi DB (`apps/api/src/db/migrate.ts`) dan eksekutor seed idempoten (`apps/api/src/db/seed.ts`).
  - Pembuatan rangkaian tes skema komprehensif (`apps/api/test/schema.test.ts`).
- Keputusan:
  - Lingkungan eksekusi: VM sandbox tidak memiliki koneksi internet dan tidak memiliki binary Postgres/PGlite/pnpm/tsc/vitest bawaan; pengujian dan verifikasi M0 didelegasikan ke CI GitHub Actions (`ci.yml`).
  - Flat config ESLint (`eslint.config.js`) digunakan menggantikan `.eslintrc.cjs`.
  - Node engine ditetapkan `>=20` dengan `.nvmrc` disetel ke `20`.
  - Penyeimbangan seed pasar: total produksi per komoditas disamakan dengan total konsumsi (23 per tick) dengan rincian: pelabuhan unggulan (20/3), Makassar (3/3), Batavia (0/8).
  - Pengamanan tabel `ledger`: dipasang trigger `BEFORE UPDATE OR DELETE` (per baris) dan `BEFORE TRUNCATE` (per statement) yang melempar exception demi menegakkan aturan append-only.
- Masalah terbuka:
  - Menunggu output mentah CI GitHub Actions untuk verifikasi akhir M0 sebelum melangkah ke M1.
- Langkah berikut:
  - Penerimaan log CI dan perbaikan bila ditemukan kegagalan.
  - Persiapan M1 (ekonomi, `hitungHarga`, transaksi slippage, simulasi bot).
