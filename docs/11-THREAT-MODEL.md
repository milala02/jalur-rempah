# 11 — Threat Model v0.2

## Aset
1. Integritas ekonomi (koin pemain, kas pelabuhan `ports.treasury`, stok pasar, `ledger`, `economy_sources_sinks`)
2. Akun pemain (email, hash sandi, token)
3. Ketersediaan dunia (tick tetap berjalan tepat waktu)
4. Server dan VPS (tidak boleh jadi pijakan)

## Aktor
Pemain jujur, pemain curang (eksploit/multi-akun), penyerang anonim, bot, pencuri token, orang dalam/bug sendiri.

## Permukaan serangan
HTTP API, editor aturan (input pemain yang dieksekusi), klien Android (dapat dibongkar), database, VPS (SSH, nginx, PM2), rantai pasok (dependensi, GitHub Actions).

## Ancaman dan mitigasi
| # | Ancaman | Dampak | Mitigasi |
|---|---|---|---|
| T1 | **DoS lewat aturan** (ekspresi dalam, anggaran besar) | Tick melambat | Batas ukuran/kedalaman/anggaran (`05`: maks 20 aturan, kedalaman AST 6, 200 node/kapal/tick), parser iteratif dengan batas, fuzz test |
| T2 | **Sandbox escape** | Eksekusi kode di server | Tidak ada `eval`/JS; hanya AST yang dievaluasi interpreter murni sendiri; tanpa akses I/O |
| T3 | **Eksploit ekonomi** (arbitrase siklus, pembulatan, dorong harga, rescue farming) | Inflasi, kekayaan palsu | Aritmetika integer `BIGINT`, eksekusi beli/jual simetris (ADR-009), biaya 2% dua arah, syarat kas bersih `N <= treasury` (ADR-010), simulasi adversarial 4 vektor, audit `economy_money_supply_audit` tiap tick |
| T4 | **Race condition** pada saldo/stok | Duplikasi koin/barang | Worker penulis tunggal (`pg_try_advisory_xact_lock`), satu transaksi per tick, CHECK constraint DB |
| T5 | **Multi-akun / Sybil** (farming modal awal atau manipulasi stok tipis) | Modal awal berlipat / subsidi silang via pasar | **Wajib MVP (tanpa ketergantungan SMTP):** tidak ada transfer koin/barang langsung antar-pemain, biaya pelabuhan 2% dua sisi (membuat *wash trading* rugi bersih >= 4%), rate limit pendaftaran per IP (`5/jam/IP`) + deteksi korelasi pasangan akun yang berdagang berlawanan arah berulang di pelabuhan yang sama.<br>**Opsional (Keputusan Pemilik):** verifikasi email di balik flag `REQUIRE_EMAIL_VERIFICATION` |
| T6 | **Brute-force / credential stuffing** | Pengambilalihan akun | `argon2id`, rate limit `/v1/auth/login` (`10/15m` per kombinasi `IP + email` agar aman terhadap CGNAT seluler), penundaan progresif, pesan galat generik |
| T7 | **Pencurian token** | Penyalahgunaan akun | JWT umur pendek (`15m`), refresh token (`30d`) dirotasi dan dicabut di DB, HTTPS wajib, simpan di Keystore Android |
| T8 | **Manipulasi klien** | Data palsu | Klien tipis, semua logika di server, tidak ada kepercayaan pada input klien |
| T9 | **Injeksi SQL** | Kebocoran/penghapusan data | Query berparameter, role DB minimal (`api_rw` tidak bisa menulis tabel pasar/kas/ledger tick) |
| T10 | **IDOR** (akses kapal orang lain) | Pencurian strategi, sabotase | Cek kepemilikan (`ship.player_id == jwt.sub`) di setiap endpoint kapal, tes otorisasi otomatis |
| T11 | **Kebocoran rahasia** | Pengambilalihan sistem | `.env` di luar repo (izin `0600`), rahasia di GitHub Secrets, pemindaian rahasia di CI |
| T12 | **Dependensi berbahaya** | Eksekusi kode | Lockfile `--frozen-lockfile`, audit rutin, pin versi, review sebelum menambah paket |
| T13 | **Kehilangan data / kebocoran file backup** | Dunia hilang / hash bocor | Backup harian `pg_dump` dengan `umask 077` di direktori `0700`, retensi otomatis 14 hari, salin terenkripsi ke luar VPS, uji restore bulanan |
| T14 | **Spam/penyalahgunaan simulasi (`/v1/simulate`)** | Beban CPU API | Rate limit ditegakkan **per `player_id`** di lapis aplikasi (`10/menit/pemain`), batas waktu eksekusi, dan *concurrency semaphore* (maksimal 2 simulasi paralel di proses API) |
| T15 | **Pembocoran info pemain** | Privasi | Leaderboard hanya menampilkan `display_name`; tanpa email di respons publik |
| T16 | **Serangan lewat nama tampilan** (XSS/penghinaan) | UI rusak | Validasi panjang (`3..24` karakter alfanumerik/garis bawah), escape di klien, filter dasar |

## Prinsip pertahanan
Server tidak percaya klien; hak akses minimal per proses/role DB; gagal dengan aman (rollback tick, jangan loncat); batasi semuanya (ukuran body HTTP `64KB`, waktu, laju per IP dan per `player_id`); catat dan pantau.

## Pemantauan keamanan
Log gagal login, lonjakan pendaftaran, pola perdagangan abnormal (profit/tick ekstrem atau pasangan akun yang selalu bertransaksi di tick yang sama), pelanggaran invarian (`economy_money_supply_audit`), tick lag.

## Respons insiden (ringkas)
1. Hentikan worker (`pm2 stop jr-worker`) jika integritas ekonomi diragukan
2. Ambil cadangan dan snapshot DB
3. Audit `ledger` dan `economy_sources_sinks` untuk menemukan akun/pola
4. Perbaiki dan tambah tes regresi
5. Koreksi lewat entri `ledger` / `economy_sources_sinks` kompensasi (bukan edit langsung karena dijaga trigger append-only)
6. Catat di `PROGRESS.md` dan ADR bila ada keputusan

## Di luar cakupan MVP
Anti-cheat tingkat klien, deteksi bot lanjutan, kepatuhan privasi formal (tinjau sebelum rilis publik).
