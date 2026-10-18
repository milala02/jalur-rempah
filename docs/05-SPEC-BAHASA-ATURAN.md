# 05 — Spesifikasi Bahasa Aturan v0.1

Ini dokumen paling kritis. Perubahan di sini wajib disertai tes golden baru.

## Model eksekusi
- Setiap kapal punya satu **program** = daftar aturan berurutan (prioritas dari atas).
- Tiap tick: evaluasi aturan dari atas. **Aturan pertama yang kondisinya benar** dijalankan, sisanya diabaikan. Tidak ada yang cocok = `tunggu()`.
- Maksimal **satu aksi per tick**.
- Jika aksi gagal (koin kurang, muatan penuh, stok habis): dicatat `gagal` dengan alasan, kapal menganggur tick itu, **tanpa lanjut ke aturan berikutnya**.
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
`angka` (integer 53-bit aman), `bool`, `komoditas`, `pelabuhan`. Tidak ada konversi implisit. Perbandingan hanya antar tipe sama. `==`/`!=` boleh untuk `komoditas` dan `pelabuhan`.

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
- Batas ukuran (di bawah)
Hasil validasi: daftar galat `{baris, kolom, kode, pesan}`; pesan dalam Indonesia dan spesifik.

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
Tanpa waktu, tanpa acak, tanpa urutan iterasi yang tak tentu. Hasil evaluasi hanya fungsi dari (program, snapshot keadaan).

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
