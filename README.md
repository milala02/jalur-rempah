# Jalur Rempah

Game strategi dagang rempah. Pemain tidak mengemudikan kapal — pemain **menulis aturan** yang mengendalikan kapal dagangnya, lalu bersaing di pasar yang terus hidup.

> Status: draf awal v0.1. Dokumen desain sudah lengkap, implementasi masih awal. Lihat `docs/`.

## Konsep singkat

- 6 pelabuhan: Banda, Ternate, Makassar, Surabaya, Batavia, Malaka
- 4 komoditas: pala, cengkeh, garam, kain
- Tiap tick, server menjalankan aturan kapalmu: beli, jual, berlayar, atau tunggu
- Harga bergerak karena penawaran dan permintaan — bukan acak
- Menang dengan aturan yang cerdas, bukan kecepatan jari
- Terinspirasi gaya Screeps / EVE / Factorio, tapi sesi singkat dan mobile-friendly

## Teknologi

- TypeScript monorepo, pnpm workspace, Node >= 20
- Vitest untuk test, ESLint + Prettier, PostgreSQL untuk data model (lihat `docs/07-DATA-MODEL.md`)

## Cara jalan (development)

```bash
pnpm install
pnpm test
pnpm typecheck
pnpm lint
```

## Dokumen

Semua ada di `docs/` — mulai dari `docs/00-README.md`:

- `01-GDD.md` — konsep dan loop permainan
- `02-PRD-MVP.md` — scope MVP
- `03-ARSITEKTUR.md` — komponen dan alur data
- `05-SPEC-BAHASA-ATURAN.md` — bahasa aturan kapal
- `06-SPEC-EKONOMI.md` — rumus harga
- `08-API-CONTRACT.md` — endpoint REST
- `13-ROADMAP.md` — milestone

## Kontribusi

Proyek masih draf awal. Kalau mau ikut, baca dulu `docs/00-README.md` dan `docs/13-ROADMAP.md`, lalu buka issue sebelum kirim PR.

## Lisensi

MIT — lihat `LICENSE`.
