# Contributing — jalur-rempah

Proyek masih draf awal v0.1. Baca dulu `docs/00-README.md` dan `docs/13-ROADMAP.md`.

## Cara kontribusi
1. Buka issue dulu — jelaskan apa yang mau diubah dan kenapa.
2. Fork repo, buat branch `fix/<nama-singkat>` atau `feat/<nama-singkat>`.
3. Jalankan sebelum PR:
   ```bash
   pnpm install
   pnpm typecheck
   pnpm lint
   pnpm test
   ```
4. Satu PR = satu perubahan. Ikuti spec di `docs/` — angka ekonomi adalah parameter tuning, ubah lewat konfigurasi dan catat di `docs/PROGRESS.md`.

## Yang dicari
- Perbaikan docs / spec yang bertentangan.
- Test untuk DSL aturan, ekonomi, dan ledger.
- Bug kecil yang sudah ada issue-nya.

## Yang tidak diterima
- Fitur besar tanpa diskusi di issue dulu.
- Perubahan format massal.
