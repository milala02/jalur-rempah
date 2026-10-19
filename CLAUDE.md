# CLAUDE.md — Aturan Kerja untuk AI Agent (Jalur Rempah)

Baca file ini di awal setiap sesi. Dokumen rujukan ada di `docs/`. Jika kode bertentangan dengan dokumen, **dokumen menang**, kecuali kamu mengusulkan perubahan dokumen lebih dulu.

## Ringkasan proyek
Game Android: dunia ekonomi persisten (kepulauan perdagangan rempah) tempat pemain **memprogram kapal dagang** dengan Bahasa Aturan buatan sendiri. Dunia berjalan di server walau pemain offline. Server adalah satu-satunya sumber kebenaran.

## Stack
- Backend: Node.js 20+, TypeScript (strict), Fastify, PostgreSQL 16
- Dua proses: `apps/api` (HTTP) dan `apps/worker` (simulasi tick). Keduanya memakai `packages/*`
- Klien: Flutter (`apps/mobile`), hanya menampilkan data dan mengedit aturan
- Tes: Vitest, fast-check (property-based), Testcontainers untuk PostgreSQL
- Deploy: PM2 + nginx di VPS, build APK via GitHub Actions

## Struktur folder
```
apps/api        # Fastify, route, auth, validasi
apps/worker     # tick loop, penerapan aksi
apps/mobile     # Flutter
packages/dsl    # lexer, parser, validator, evaluator Bahasa Aturan (murni, tanpa I/O)
packages/econ   # rumus harga, produksi/konsumsi, biaya (murni, tanpa I/O)
packages/shared # tipe, konstanta dunia, skema zod
db/migrations   # SQL bermigrasi bernomor, maju saja
docs/           # spesifikasi
```

## Perintah
```
pnpm install
pnpm -w test            # semua tes
pnpm -w lint && pnpm -w typecheck
pnpm --filter api dev
pnpm --filter worker dev
pnpm db:migrate
pnpm sim:run --ticks 10000 --bots 50   # simulasi ekonomi
```

## Aturan keras (jangan dilanggar)
1. **Uang dan jumlah barang selalu integer.** Dilarang float untuk koin/stok. Harga turunan dibulatkan di satu tempat (`packages/econ`).
2. Setiap perubahan koin **wajib** lewat tabel `ledger` dalam transaksi DB yang sama dengan perubahan saldo.
3. Jangan ubah skema DB tanpa file migrasi baru. Jangan edit migrasi lama.
4. `packages/dsl` dan `packages/econ` harus **murni dan deterministik**: tanpa `Date.now()`, `Math.random()`, atau I/O. Acak hanya lewat RNG ber-seed yang di-inject.
5. Klien tidak dipercaya. Semua validasi dan aturan game dijalankan di server.
6. Jangan menjalankan kode pemain sebagai JavaScript. Hanya Bahasa Aturan (lihat `docs/05`).
7. Jangan menambah dependensi tanpa alasan tertulis di PR/commit.
8. Jangan menebak. Jika spesifikasi tidak jelas, **berhenti dan tanyakan**, atau tulis asumsi di `docs/PROGRESS.md`.

## Alur kerja per sesi
1. Baca `docs/PROGRESS.md` dan tugas aktif di `docs/13-ROADMAP.md`.
2. Tulis rencana singkat (file yang disentuh, risiko) sebelum mengubah kode.
3. **Tes dulu** untuk logika ekonomi, DSL, dan ledger. Lalu implementasi.
4. Satu sesi = satu tugas kecil yang bisa diuji sendiri. Commit kecil dengan pesan jelas.
5. Jalankan lint, typecheck, dan tes sebelum menyatakan selesai.
6. Perbarui `docs/PROGRESS.md` (apa yang selesai, keputusan baru, masalah terbuka). Keputusan arsitektur baru masuk `docs/04-ADR.md`.

## Pelajaran M0 dan M1 (aturan tetap)
1. Tes harus membuktikan lingkungannya sendiri: tes database memakai satu DATABASE baru per file tes dan memeriksa `current_database()`. Jangan bergantung pada `search_path` atau keadaan DB dari langkah CI sebelumnya.
2. Dilarang mengubah, menghapus, melonggarkan, atau `skip` tes dan gerbang agar hijau. Setiap tes yang diubah harus punya pasangan setara atau lebih ketat dan dicatat di `docs/PROGRESS.md` dengan alasan.
3. Gerbang kualitas adalah kode (`sim-cli`) dengan ambang tertulis di `docs/06`. Mengubah ambang butuh ADR dan data.
4. Tuning bukan alat meloloskan tes: parameter harus stabil pada horizon 250.000 tick (sekitar 1 bulan waktu nyata) dan pada 10-100 kapal. Jangan menyetel ke satu skenario uji.
5. Pisahkan hasil "dijalankan di VM" dari "dijalankan di CI", lengkap dengan perintah, versi, dan output mentah. Jangan menyatakan lulus tanpa CI.
6. Tidak ada logika tick ganda: worker, simulator, dan sandbox API memakai `stepWorld` yang sama.
7. Jika dokumen tampak salah atau kontradiktif: berhenti, tulis di `docs/PROGRESS.md` bagian "Temuan dokumen", usulkan koreksi. Jangan menyimpang diam-diam. Lihat juga `docs/AUDIT-v0.3.md`.

## Definition of Done
- Tes baru ada dan lulus; tes lama tidak rusak
- Lint dan typecheck bersih
- Invarian ekonomi tidak rusak (`pnpm sim:run` pendek lulus)
- Dokumen terkait diperbarui
- Tidak ada rahasia (kunci, token) di repo

## Gaya kode
- TypeScript strict, tanpa `any` kecuali dibenarkan komentar
- Fungsi kecil, nama dalam bahasa Inggris di kode, istilah game Indonesia di UI dan DSL
- Error dikembalikan sebagai hasil terstruktur di lapisan murni; exception hanya di batas I/O
