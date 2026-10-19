# 10 — Strategi Pengujian v0.2

## Prinsip
Logika game (DSL, ekonomi, ledger, tick) **wajib dites sebelum diimplementasi** (tes dulu). UI cukup tes jalur kritis.

## Piramida
| Level | Alat | Cakupan | Target |
|---|---|---|---|
| Unit | Vitest | `packages/dsl`, `packages/econ`, util | >= 90% baris pada paket murni |
| Properti | fast-check | invarian ekonomi, parser | tiap invarian di `06` |
| Integrasi | Vitest + Postgres nyata (service container di CI; **satu DATABASE baru per file tes**, tes memeriksa `current_database()`) | api, worker, migrasi, transaksi | jalur kritis |
| Simulasi | `pnpm sim:run` | ekonomi skala besar | gerbang rilis |
| Kontrak | skema OpenAPI | respons api | semua endpoint |
| Klien | Flutter widget/integration test | login, editor, pasar | jalur kritis |
| Muat | k6 | 100-500 pemain | sebelum beta |

## Tes DSL (rujuk `05`)
- **Golden:** 30+ program → AST/JSON hasil tetap; perubahan butuh persetujuan eksplisit
- **Galat:** kode, baris, kolom tepat; saran "maksud Anda?" deterministik
- **Fuzz:** string acak/malformed tidak crash atau hang (batas waktu per kasus)
- **Adversarial:** aturan dalam, ekspresi panjang, angka besar → ditolak atau dibatasi anggaran
- **Determinisme:** (program, snapshot) → hasil identik di 1.000 pengulangan

## Tes ekonomi (rujuk `06`)
Properti (fast-check) — untuk urutan transaksi acak apa pun:
1. stok >= 0 dan <= kapasitas
2. harga dalam batas dan integer
3. koin >= 0 dan saldo = jumlah ledger
4. beli lalu jual unit yang sama di pelabuhan yang sama selalu rugi
5. total koin tidak pernah bertambah (selain sumber yang diputuskan)

## Simulasi massal (gerbang kualitas)
`pnpm sim:run --ticks 10000 --bots 50 --seed N`
- Bot dengan strategi beragam: pedagang naif, pemburu margin, penimbun, acak, "adversarial" (mencari eksploit)
- Keluaran: JSON metrik (harga, volatilitas, Gini, total koin, % bangkrut) + grafik
- **Gerbang:** tidak ada pelanggaran invarian; harga hidup (bukan konstan) dan tidak menyentuh batas 25%/400% terus-menerus; tidak ada strategi tunggal yang menang > X% kekayaan total `[ASUMSI X=40%]`
- Jalankan dengan banyak seed; hasil tetap konsisten untuk seed yang sama
- CI menjalankan versi pendek (2.000 tick, 10 bot) di setiap PR; versi penuh sebelum rilis

## Tes kesetaraan (satu implementasi tick)
- Worker, simulator, dan sandbox API memakai `stepWorld` yang sama. Tes: untuk keadaan awal, aturan, dan seed yang sama, `state_hash` hasil worker (lewat database) sama dengan hasil simulator murni setelah N tick
- Dilarang ada logika tick atau harga yang diduplikasi di luar `packages/econ`

## Gerbang kualitas sebagai kode
Setiap gerbang (invarian, kas pelabuhan, harga di batas, bot bangkrut, kekayaan per strategi) diimplementasikan di `sim-cli` dan membuat proses keluar non-nol saat gagal. Ambang tertulis di `06`; mengubah ambang butuh ADR dan data.

## Tes tick dan ketahanan
- Kill -9 worker acak saat tick → data konsisten, tick tidak ganda
- Dua worker bersamaan → yang kedua keluar karena advisory lock
- Tes `state_hash`: sumber yang sama → hash sama
- Migrasi: maju dari skema kosong dan dari snapshot sebelumnya

## Tes api
- Auth: pendaftaran, login, refresh rotasi, pencabutan
- Otorisasi: tidak bisa membaca/mengubah kapal pemain lain
- Rate limit
- `PUT rules` memvalidasi dan menolak aturan jahat
- Simulasi sandbox tidak menulis ke database (verifikasi jumlah baris sebelum/sesudah)

## Tes keamanan dasar
SQL injection (parameterisasi), enumerasi akun, brute-force login, JWT kedaluwarsa/dimanipulasi, ukuran payload.

## Data uji
Seed dunia deterministik (`packages/shared/seed`). Fabrikasi pemain uji lewat helper, bukan SQL manual.

## CI (GitHub Actions)
`lint` → `typecheck` → `test` (unit + integrasi) → `sim:short`. Merge diblokir jika salah satu gagal.
