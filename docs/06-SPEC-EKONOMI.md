# 06 — Spesifikasi Ekonomi v0.1

Semua angka adalah **parameter awal** di `packages/shared/config`. Tuning lewat simulasi (lihat `10`), bukan tebakan.

## Prinsip
1. Uang dan stok integer (ADR-005).
2. Harga ditentukan **hanya** oleh stok pelabuhan relatif target, bukan oleh pemain secara langsung.
3. Setiap koin yang masuk atau keluar sistem punya sumber/pengurang yang tercatat.
4. Strategi populer harus kehilangan margin (slippage dan kejenuhan).

## Dunia awal
Komoditas dan harga dasar (koin per unit):
| Komoditas | Harga dasar |
|---|---|
| pala | 70 |
| cengkeh | 90 |
| garam | 20 |
| kain | 45 |

Pelabuhan, produksi unggulan, dan jarak (tick pelayaran, dua arah):
| Pelabuhan | Produksi unggulan |
|---|---|
| Banda | pala |
| Ternate | cengkeh |
| Surabaya | garam |
| Malaka | kain |
| Makassar | (campuran kecil) |
| Batavia | (pusat konsumsi) |

| Rute | Tick |
|---|---|
| Banda – Ternate | 5 |
| Banda – Makassar | 6 |
| Ternate – Makassar | 5 |
| Makassar – Surabaya | 4 |
| Surabaya – Batavia | 3 |
| Batavia – Malaka | 4 |
| Makassar – Batavia | 6 |

`[ASUMSI]` Durasi tick produksi 30 detik (di simulasi: 0 detik, loncat). Pelayaran 3-6 tick = 1,5-3 menit.

## Model pasar per (pelabuhan, komoditas)
Variabel: `stok`, `target` (stok setimbang), `produksi` per tick, `konsumsi` per tick.

**Harga:**
```
rasio  = target / max(stok, 1)
harga  = round(dasar * clamp(rasio ^ e, 0.25, 4.0))
```
- `e = 0.6` (elastisitas awal)
- `round` ke integer terdekat, minimal 1
- Fungsi `hitungHarga(stok, target, dasar)` adalah **satu-satunya** tempat harga dihitung

**Produksi/konsumsi tiap tick:**
```
stok += produksi
stok -= min(konsumsi, stok)
stok  = min(stok, kapasitasGudang)
```
Pelabuhan unggulan: `produksi` besar untuk komoditasnya, `konsumsi` kecil. Pusat konsumsi: kebalikannya. Semua pelabuhan punya `konsumsi` kecil untuk semua komoditas supaya selalu ada permintaan.

`[ASUMSI]` Parameter awal (diuji di simulasi M1):
- `target` = 400
- `kapasitasGudang` = 1.600
- Pelabuhan unggulan (Banda: pala, Ternate: cengkeh, Surabaya: garam, Malaka: kain): komoditas unggulan `produksi = 20, konsumsi = 3`; tiga komoditas lainnya `produksi = 0, konsumsi = 3`.
- Makassar: keempat komoditas `produksi = 3, konsumsi = 3`.
- Batavia: keempat komoditas `produksi = 0, konsumsi = 8`.
- Stok awal semua baris pasar = 400 (`target`), dan harga awal = `harga_dasar`. Total produksi global per komoditas (20 + 3 = 23) setimbang dengan total konsumsi global (3 + 3 + 3 + 3 + 3 + 8 = 23).

## Eksekusi transaksi (slippage)
Beli/jual dieksekusi **unit demi unit** pada harga yang dihitung ulang setelah tiap unit (atau pada langkah blok kecil, setara hasilnya):
- **Beli n unit:** untuk tiap unit, bayar `harga(stok)` lalu `stok -= 1`
- **Jual n unit:** untuk tiap unit, terima `harga(stok)` lalu `stok += 1`
- Total dibulatkan per unit (tidak ada pecahan koin)
- `beli(k, maks)`: n = min(muatan_bebas, stok pelabuhan, jumlah yang terbeli dengan koin saat ini setelah biaya)
- Transaksi bersifat **atomik per aksi**: gagal sebagian = gagal seluruhnya, kecuali `maks`/`semua` yang menghitung n lebih dulu

**Biaya pelabuhan:** 2% dari nilai transaksi tiap sisi, dibulatkan ke atas, minimal 1 koin. Itu **pengurang uang** (koin hilang dari sirkulasi).

## Sumber dan pengurang uang (money faucets & sinks)
**Sumber (koin masuk):**
- Modal awal akun: 1.000 koin (satu kali)
- *Tidak ada* sumber lain di MVP

**Pengurang:**
- Biaya pelabuhan 2%
- Perawatan kapal: 1 koin per tick (kapal berlayar maupun sandar)
- Pembelian kapal tambahan (Fase 2): 100% pengurang

**Penting:** barang diciptakan oleh produksi pelabuhan, bukan oleh pemain. Pemain tidak menciptakan koin dari barang selain lewat penjualan ke pasar yang sebelumnya dibayar pemain lain atau modal awal. Jadi **total koin pemain tidak pernah bertambah** selain modal awal; ekonomi pemain adalah permainan zero-sum dikurangi biaya.

`[ASUMSI]` Masalah yang harus diwaspadai: karena tidak ada sumber koin, jumlah koin total menurun terus. Opsi penyeimbang yang diuji di simulasi: (a) pelabuhan NPC membeli/menjual dari kas NPC yang tidak terbatas (menciptakan koin), (b) subsidi harian kecil. **Putuskan lewat simulasi** dan catat di ADR.

## Perawatan tidak terbayar
Jika koin pemain < biaya perawatan: kapal **sandar paksa** (aturan tidak dievaluasi) sampai koin cukup. Kapal tidak dihapus dan koin tidak menjadi negatif.

## Kekayaan bersih (peringkat)
```
kekayaan = koin + sum(stok_kapal[k] * harga_dasar[k])
```
Pakai harga dasar (bukan harga pasar) supaya tidak bisa dimanipulasi dengan mendorong harga di pelabuhan.

## Invarian (harus selalu benar; dites otomatis)
1. Tidak ada koin atau stok negatif
2. `players.koin == sum(ledger.delta per pemain)`
3. Total koin pemain = modal awal total - pengurang kumulatif (+ sumber opsional bila diputuskan)
4. Harga dalam [dasar*0.25, dasar*4] dan bilangan bulat >= 1
5. Muatan kapal <= kapasitas
6. Stok pelabuhan dalam [0, kapasitasGudang]

## Pemeriksaan eksploit
- **Arbitrase siklus:** beli A → jual A di tempat yang sama pada tick yang sama harus selalu rugi (slippage + biaya)
- **Pembulatan:** beli lalu jual 1 unit berulang tidak boleh menghasilkan untung
- **Dorong harga:** menguras stok untuk menaikkan harga lalu menjual di sana harus tidak menguntungkan setelah biaya

## Metrik simulasi yang dipantau
Harga rata-rata dan volatilitas per komoditas, Gini kekayaan, total koin vs waktu, margin rata-rata per rute, persentase bot yang bangkrut (sandar paksa).
