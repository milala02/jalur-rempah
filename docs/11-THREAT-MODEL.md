# 11 — Threat Model v0.1

## Aset
1. Integritas ekonomi (koin, stok, ledger)
2. Akun pemain (email, hash sandi, token)
3. Ketersediaan dunia (tick tetap berjalan)
4. Server dan VPS (tidak boleh jadi pijakan)

## Aktor
Pemain jujur, pemain curang (eksploit/multi-akun), penyerang anonim, bot, pencuri token, orang dalam/bug sendiri.

## Permukaan serangan
HTTP API, editor aturan (input pemain yang dieksekusi), klien Android (dapat dibongkar), database, VPS (SSH, nginx, PM2), rantai pasok (dependensi, GitHub Actions).

## Ancaman dan mitigasi
| # | Ancaman | Dampak | Mitigasi |
|---|---|---|---|
| T1 | **DoS lewat aturan** (ekspresi dalam, anggaran besar) | Tick melambat | Batas ukuran/kedalaman/anggaran (`05`), parser iteratif dengan batas, fuzz test |
| T2 | **Sandbox escape** | Eksekusi kode di server | Tidak ada eval/JS; hanya AST yang dievaluasi interpreter sendiri; tanpa akses I/O |
| T3 | **Eksploit ekonomi** (arbitrase siklus, pembulatan, dorong harga) | Inflasi, kekayaan palsu | Integer, slippage, biaya 2%, simulasi adversarial, invarian tiap tick |
| T4 | **Race condition** pada saldo/stok | Duplikasi koin/barang | Worker penulis tunggal, satu transaksi per tick, CHECK constraint DB, advisory lock |
| T5 | **Multi-akun** (farming modal awal) | Modal awal berlipat | Verifikasi email, rate limit pendaftaran per IP, modal awal bukan sumber bernilai tinggi; pantau pola |
| T6 | **Brute-force / credential stuffing** | Pengambilalihan akun | argon2id, rate limit `/auth`, penundaan progresif, pesan galat generik |
| T7 | **Pencurian token** | Penyalahgunaan akun | JWT umur pendek, refresh dirotasi dan dicabut, HTTPS wajib, simpan di Keystore Android |
| T8 | **Manipulasi klien** | Data palsu | Klien tipis, semua logika di server, tidak ada kepercayaan pada input klien |
| T9 | **Injeksi SQL** | Kebocoran/penghapusan data | Query berparameter, role DB minimal (api tidak bisa menulis dunia) |
| T10 | **IDOR** (akses kapal orang lain) | Pencurian strategi, sabotase | Cek kepemilikan di setiap endpoint kapal, tes otorisasi |
| T11 | **Kebocoran rahasia** | Pengambilalihan sistem | `.env` di luar repo, rahasia di GitHub Secrets, pemindaian rahasia di CI |
| T12 | **Dependensi berbahaya** | Eksekusi kode | Lockfile, audit rutin, pin versi, review sebelum menambah paket |
| T13 | **Kehilangan data** | Dunia hilang | Backup harian `pg_dump`, uji restore berkala |
| T14 | **Spam/penyalahgunaan simulasi** | Beban CPU api | Rate limit simulate, timeout 2 detik, antrean dengan batas |
| T15 | **Pembocoran info pemain** | Privasi | Leaderboard hanya nama tampilan; tanpa email di respons publik |
| T16 | **Serangan lewat nama tampilan** (XSS/penghinaan) | UI rusak | Validasi panjang/karakter, escape di klien, filter dasar |

## Prinsip pertahanan
Server tidak percaya klien; hak akses minimal per proses/role DB; gagal dengan aman (rollback tick, jangan loncat); batasi semuanya (ukuran, waktu, laju); catat dan pantau.

## Pemantauan keamanan
Log gagal login, lonjakan pendaftaran, pola perdagangan abnormal (profit/tick ekstrem), pelanggaran invarian, tick lag.

## Respons insiden (ringkas)
1. Hentikan worker (`pm2 stop worker`) jika integritas ekonomi diragukan
2. Ambil cadangan dan snapshot DB
3. Audit `ledger` untuk menemukan akun/pola
4. Perbaiki dan tambah tes regresi
5. Koreksi lewat entri ledger kompensasi (bukan edit langsung)
6. Catat di `PROGRESS.md` dan ADR bila ada keputusan

## Di luar cakupan MVP
Anti-cheat tingkat klien, deteksi bot lanjutan, kepatuhan privasi formal (tinjau sebelum rilis publik).
