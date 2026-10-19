# 05 — Spesifikasi Bahasa Aturan v0.2

Ini dokumen paling kritis. Perubahan di sini wajib disertai tes golden baru.

## Model eksekusi
- Setiap kapal punya satu **program** = daftar aturan berurutan (prioritas dari atas).
- Tiap tick: evaluasi aturan dari atas. **Aturan pertama yang kondisinya benar** dijalankan, sisanya diabaikan. Tidak ada yang cocok = `tunggu()`.
- Maksimal **satu aksi berhasil per tick**.
- Jika prasyarat sebuah aksi gagal (koin kurang, muatan penuh, stok habis, jumlah nol, dan seterusnya; daftar kode di bagian *Kode galat*): kegagalan dicatat di log (`gagal` + kode alasan), lalu evaluasi **berlanjut ke aturan berikutnya** pada tick yang sama. Hanya aksi yang berhasil, atau `tunggu()`, mengakhiri tick. Ini mencegah kapal macet oleh satu aturan yang terus gagal (misalnya `beli` saat stok habis tidak boleh menghalangi `berlayar` di bawahnya).
- Jumlah percobaan dalam satu tick dibatasi oleh anggaran evaluasi dan batas 16 aturan.
- Keadaan yang dibaca aturan adalah keadaan dunia **pada giliran kapal itu**, termasuk dampak aksi kapal lain yang bergiliran lebih dulu di tick yang sama (urutan giliran: lihat `09`).
- Kapal berstatus `grounded` (lihat `09`) tetap dievaluasi, tetapi hanya `jual` dan `tunggu` yang diizinkan; aksi lain gagal dengan kode `GROUNDED` dan evaluasi berlanjut.
- Saat kapal sedang berlayar, tidak ada evaluasi (hanya log "dalam pelayaran").

## Contoh
```
aturan beli_pala:
  jika di(Banda) dan harga(pala) < 40 dan muatan_bebas() > 0
  maka beli(pala, maks)

aturan jual_pala:
  jika di(Batavia) dan stok_kapal(pala) > 0 dan harga(pala) > 70
  maka jual(pala, semua)

aturan ke_batavia:
  jika stok_kapal(pala) > 0 maka berlayar(Batavia)

aturan ke_banda:
  jika stok_kapal(pala) == 0 maka berlayar(Banda)
```

## Leksikal
- Komentar: `#` sampai akhir baris
- Spasi dan baris baru tidak bermakna kecuali pemisah token
- Pengenal: `[a-zA-Z_][a-zA-Z0-9_]*`, tidak peka huruf besar-kecil
- Angka: integer desimal non-negatif (`0`, `42`); negatif lewat operator `-`
- Kata kunci: `aturan jika maka dan atau bukan maks semua benar salah`
- Konstanta dunia: nama pelabuhan dan komoditas (dari `packages/shared`)

## Tata bahasa (EBNF)
```
program    = { aturan } ;
aturan     = "aturan" ident ":" "jika" ekspr "maka" aksi ;
ekspr      = atau ;
atau       = dan { "atau" dan } ;
dan        = tidak { "dan" tidak } ;
tidak      = [ "bukan" ] bandingan ;
bandingan  = tambah [ ( "<" | "<=" | ">" | ">=" | "==" | "!=" ) tambah ] ;
tambah     = kali { ( "+" | "-" ) kali } ;
kali       = unari { ( "*" | "/" | "%" ) unari } ;
unari      = [ "-" ] primer ;
primer     = angka | "benar" | "salah" | konstanta | panggilan | "(" ekspr ")" ;
panggilan  = ident "(" [ ekspr { "," ekspr } ] ")" ;
aksi       = ident "(" [ arg { "," arg } ] ")" ;
arg        = ekspr | "maks" | "semua" ;
```

## Tipe
`angka` (integer aman JavaScript, |x| <= 2^53-1), `bool`, `komoditas`, `pelabuhan`. Tidak ada konversi implisit. Perbandingan hanya antar tipe sama. `==`/`!=` boleh untuk `komoditas` dan `pelabuhan`.

## Representasi angka dan adapter
Paket `packages/econ` memakai `bigint` untuk koin dan stok, sedangkan evaluator DSL memakai integer aman. Adapter mengonversi di batas keduanya. Nilai di luar rentang aman = galat runtime `OVERFLOW` (aturan itu dilewati). Batas ekonomi dijaga agar nilai normal berada jauh di bawah 2^53.

## Semantik aritmetika
- `/` adalah pembagian integer ke arah nol; `%` sisa bagi
- Pembagian atau modulo dengan nol = **galat runtime**
- Overflow melebihi 2^53-1 = galat runtime

## Fungsi baca (tanpa efek samping)
| Fungsi | Tipe hasil | Arti |
|---|---|---|
| `di(p)` | bool | Kapal sandar di pelabuhan p |
| `koin()` | angka | Koin pemain |
| `muatan_bebas()` | angka | Sisa kapasitas muatan |
| `kapasitas()` | angka | Kapasitas total kapal |
| `stok_kapal(k)` | angka | Jumlah komoditas k di kapal |
| `stok_pelabuhan(k)` | angka | Stok k di pelabuhan saat ini |
| `harga(k)` | angka | Harga k di pelabuhan saat ini |
| `harga_di(p, k)` | angka | Harga k di pelabuhan p (MVP: real-time, lihat ADR-008) |
| `jarak(p)` | angka | Tick pelayaran dari posisi sekarang ke p (rute terpendek) |
| `tick()` | angka | Nomor tick global |

## Aksi
| Aksi | Efek |
|---|---|
| `beli(k, n)` / `beli(k, maks)` | Beli n unit k di pelabuhan saat ini; `maks` = sebanyak mungkin yang muat dan terbeli dengan koin |
| `jual(k, n)` / `jual(k, semua)` | Jual n unit k; `semua` = seluruh stok k di kapal |
| `berlayar(p)` | Berangkat ke p lewat rute terpendek; hanya valid jika sedang sandar dan p berbeda dari posisi sekarang |
| `tunggu()` | Tidak melakukan apa-apa |

Pembelian/penjualan dieksekusi **pada harga yang bergerak** (slippage), lihat `06`.

## Validasi statis (saat menyimpan, bukan saat tick)
- Sintaks valid sesuai EBNF
- Semua nama fungsi/aksi/konstanta dikenal
- Jumlah dan tipe argumen benar
- Ekspresi kondisi bertipe `bool`
- Nama aturan unik
- Tidak ada `berlayar` ke pelabuhan yang tidak ada
- `maks` hanya boleh menjadi argumen kedua `beli`; `semua` hanya boleh menjadi argumen kedua `jual`
- Nama aturan bukan kata kunci, nama fungsi/aksi, atau konstanta dunia
- Batas ukuran (di bawah)
Hasil validasi: daftar galat `{baris, kolom, kode, pesan}`; pesan dalam Indonesia dan spesifik.

## Kode galat (tetap; dipakai golden test dan API)
**Validasi statis** (saat menyimpan): `SYNTAX_ERROR`, `UNKNOWN_IDENT`, `ARITY_MISMATCH`, `TYPE_MISMATCH`, `DUPLICATE_RULE`, `RESERVED_NAME`, `BAD_KEYWORD_ARG`, `LIMIT_RULES`, `LIMIT_NODES`, `LIMIT_LENGTH`, `LIMIT_DEPTH`.

**Galat runtime** (aturan dilewati, dicatat): `DIV_ZERO`, `OVERFLOW`, `BUDGET_EXCEEDED`.

**Kegagalan aksi** (dicatat `gagal`, evaluasi berlanjut ke aturan berikutnya):
| Kode | Arti |
|---|---|
| `ZERO_QUANTITY` | jumlah eksplisit <= 0, atau `maks`/`semua` tidak menghasilkan kuantitas yang dapat dieksekusi karena batas fisik/kas |
| `ZERO_PROCEEDS` | penjualan menghasilkan pembayaran bersih `N = G - F = 0`; transaksi ditolak tanpa perubahan stok, muatan, koin, atau kas |
| `INSUFFICIENT_COINS` | koin tidak cukup untuk jumlah eksplisit + biaya |
| `CARGO_FULL` | muatan melebihi kapasitas kapal |
| `OUT_OF_STOCK` | stok pelabuhan atau kapal tidak cukup untuk jumlah eksplisit |
| `PORT_TREASURY_LOW` | kas pelabuhan tidak cukup membayar penjualan eksplisit |
| `PORT_WAREHOUSE_FULL` | gudang pelabuhan tidak muat |
| `NOT_DOCKED` | aksi butuh kapal sandar |
| `SAME_PORT` | `berlayar` ke pelabuhan tempat kapal berada |
| `NO_ROUTE` | tidak ada rute ke tujuan |
| `GROUNDED` | kapal `grounded` mencoba aksi selain `jual`/`tunggu` |

Jumlah eksplisit bersifat atomik: kurang dari yang diminta = gagal seluruhnya. `maks`/`semua` menghitung jumlah terbesar yang memenuhi semua batas lebih dulu; hasil 0 = `ZERO_QUANTITY`.

## Batas (parameter, dapat diubah di konfigurasi)
| Batas | Nilai awal |
|---|---|
| Aturan per program | 16 |
| Node AST per aturan | 64 |
| Panjang sumber | 4.000 karakter |
| Anggaran evaluasi per kapal per tick | 500 node |
| Kedalaman ekspresi | 12 |

Anggaran habis di tengah evaluasi = aturan itu **dilewati** (dicatat `anggaran_habis`), evaluasi lanjut ke aturan berikut.

## Galat runtime
Galat runtime pada satu aturan (misal bagi nol) = aturan itu dilewati dan dicatat; **tidak** menghentikan tick atau kapal lain.

## Determinisme
Tanpa waktu, tanpa acak, tanpa urutan iterasi yang tak tentu. Hasil evaluasi hanya fungsi dari (program, keadaan dunia pada giliran kapal itu). Dalam simulasi sandbox, keadaan dunia adalah snapshot yang hanya dimodifikasi oleh kapal yang disimulasikan.

## Representasi terkompilasi
AST JSON tervalidasi disimpan bersama sumber (`rule_sets.compiled`). Versi AST (`ast_version`) naik jika format berubah; ada migrasi AST.

## Rencana ekstensi (bukan MVP)
Variabel lokal `biar x = ...`, memori antar-tick (`simpan/ambil` dengan kuota), fungsi pengguna tanpa rekursi, kabut informasi (`harga_terakhir`).

## Tes wajib untuk dokumen ini
1. Golden test: sumber → AST untuk 30+ program
2. Galat sintaks: lokasi baris/kolom tepat
3. Evaluator: tabel kebenaran, prioritas operator, pembagian bagi nol
4. Fuzz parser: tidak pernah crash atau hang pada input acak
5. Anggaran: program adversarial tidak melebihi anggaran
6. Determinisme: program dan state sama → hasil identik
7. Jatuh ke aturan berikutnya: aksi yang gagal tidak menghentikan evaluasi; contoh `beli` gagal lalu `berlayar` tetap berlayar
8. Kode galat: setiap kode di tabel punya minimal satu golden test
9. Kapal `grounded`: `jual`/`tunggu` diizinkan, aksi lain gagal `GROUNDED`
