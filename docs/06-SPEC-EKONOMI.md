# 06 — Spesifikasi Ekonomi v0.2

Semua angka adalah **parameter awal** di `packages/shared/config`. Tuning lewat simulasi (lihat `10`), bukan tebakan.

## Prinsip
1. Uang dan stok integer (ADR-005). Tidak ada float di jalur uang; satu-satunya fungsi pembulatan berada di `hitungHarga` (`packages/econ`).
2. Harga ditentukan **hanya** oleh stok pelabuhan relatif target, bukan oleh pemain secara langsung.
3. Eksekusi transaksi beli dan jual bersifat **simetris** (ADR-009).
4. Setiap pelabuhan memiliki **kas (`treasury`)** terbatas (`>= 0`). Biaya pelabuhan 2% masuk ke kas pelabuhan tempat transaksi; perawatan kapal (`upkeep`) adalah satu-satunya pengurang koin sistem (ADR-009).

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
- `round` ke integer terdekat, minimal 1 (satu-satunya fungsi pembulatan di seluruh sistem)
- Fungsi `hitungHarga(stok, target, dasar)` adalah **satu-satunya** tempat harga dihitung

**Produksi/konsumsi tiap tick:**
```
stok += produksi
stok -= min(konsumsi, stok)
stok  = min(stok, kapasitasGudang)
```
Pelabuhan unggulan: `produksi` besar untuk komoditasnya, `konsumsi` kecil. Pusat konsumsi: kebalikannya. Semua pelabuhan punya `konsumsi` kecil untuk semua komoditas supaya selalu ada permintaan.

`[ASUMSI]` Parameter awal (diuji dan di-tuning di simulasi M1):
- `target` = 400
- `kapasitasGudang` = 1.600
- Pelabuhan unggulan (Banda: pala, Ternate: cengkeh, Surabaya: garam, Malaka: kain): komoditas unggulan `produksi = 20, konsumsi = 3`; tiga komoditas lainnya `produksi = 0, konsumsi = 3`.
- Makassar: keempat komoditas `produksi = 3, konsumsi = 3`.
- Batavia: keempat komoditas `produksi = 0, konsumsi = 8`.
- Stok awal semua baris pasar = 400 (`target`), dan harga awal = `harga_dasar`.
- Kas awal tiap pelabuhan (`INITIAL_PORT_TREASURY`) berasal dari konfigurasi `packages/shared/config`.

## Eksekusi transaksi simetris (slippage, biaya, dan kas pelabuhan)
Beli/jual dieksekusi **unit demi unit secara simetris** (ADR-009):
- **Beli 1 unit:** bayar `hitungHarga(stok)` lalu `stok -= 1`.
  - Untuk $n$ unit dari stok awal $S$: nilai kotor $G = \sum_{i=0}^{n-1} 	ext{hitungHarga}(S - i)$, dan stok akhir $S - n$.
- **Jual 1 unit:** `stok += 1` **lebih dulu**, lalu terima `hitungHarga(stok)` (stok yang baru).
  - Untuk $n$ unit dari stok awal $S'$: nilai kotor $G = \sum_{i=1}^{n} 	ext{hitungHarga}(S' + i)$, dan stok akhir $S' + n$.
- **Sifat Simetri:** Membeli $n$ unit dari stok $S$ (stok turun ke $S - n$) lalu menjual $n$ unit dari stok $S - n$ (stok naik kembali ke $S$) mengevaluasi himpunan harga satuan yang **identik** ($\{S, S-1, \dots, S-n+1\}$), sehingga nilai kotor beli dan jual sama persis ($G_{	ext{beli}} = G_{	ext{jual}}$).
- **Biaya pelabuhan:** 2% dari nilai kotor transaksi $G$ tiap sisi, dibulatkan ke atas dalam aritmetika integer (`max(1n, (G * 2n + 99n) / 100n)` untuk $G > 0$). Biaya pelabuhan **masuk ke kas pelabuhan (`ports.treasury`)** tempat transaksi berlangsung:
  - Pada **Beli $n$ unit**: pemain membayar total $T = G + F$ (`players.coins -= T`), dan kas pelabuhan bertambah $T$ (`ports.treasury += T`).
  - Pada **Jual $n$ unit**: pemain menerima bersih $N = G - F$ (`players.coins += N`), dan kas pelabuhan berkurang bersih sebesar $N$ (`ports.treasury -= N`, karena pelabuhan mengeluarkan $G$ untuk barang dan menerima kembali biaya $F$ ke dalam kasnya; dengan syarat kas pelabuhan mencukupi $G \le 	ext{treasury}$).
- **Algoritma Deterministik `beli(k, maks)` dan `jual(k, semua)`:**
  - `beli(k, maks)`: Batas fisik $U_{	ext{maks}} = \min(	ext{muatan\_bebas}, 	ext{stok\_pelabuhan})$. Karena total bayar $T(n) = G(n) + F(n)$ monoton naik tegas terhadap $n$, jumlah unit $n \in [0, U_{	ext{maks}}]$ terbesar yang memenuhi $T(n) \le 	ext{koin\_pemain}$ dicari dengan **pencarian biner (binary search)** pada array prefix sum harga satuan.
  - `jual(k, semua)`: Batas fisik $U_{	ext{maks}} = \min(	ext{stok\_kapal}, 	ext{kapasitasGudang} - 	ext{stok\_pelabuhan})$. Karena nilai kotor pembelian oleh pelabuhan $G(n)$ monoton naik tegas terhadap $n$, jumlah unit $n \in [0, U_{	ext{maks}}]$ terbesar yang memenuhi $G(n) \le 	ext{treasury\_pelabuhan}$ dicari dengan **pencarian biner (binary search)** pada array prefix sum harga satuan.
- Transaksi eksplisit (`beli(k, n)` / `jual(k, n)`) bersifat **atomik per aksi**: gagal sebagian = gagal seluruhnya, kecuali `maks`/`semua` yang menghitung $n$ deterministik lebih dulu.

## Sumber, sirkulasi, dan pengurang uang (money conservation)
**Modal awal sistem:**
- Modal awal tiap akun pemain: `STARTER_COINS` (1.000 koin, tercatat di `ledger` dengan `reason = 'starter'`)
- Kas awal tiap pelabuhan: `INITIAL_PORT_TREASURY` (tercatat di `ports.initial_treasury`)

**Sirkulasi internal (zero-sum antara pemain dan kas pelabuhan):**
- Pembelian dan penjualan komoditas beserta biaya pelabuhan 2% hanya memindahkan koin antara `players.coins` dan `ports.treasury` ($\Delta 	ext{coins} + \Delta 	ext{treasury} = 0$).

**Pengurang satu-satunya (money sink):**
- Perawatan kapal (`upkeep`): `UPKEEP_PER_TICK` (1 koin per tick untuk kapal berlayar maupun sandar), dicatat eksplisit di `ledger` (`reason = 'upkeep'`, `delta = -1`).

## Perawatan tidak terbayar
Jika koin pemain < biaya perawatan: kapal **sandar paksa (`grounded`)** (aturan tidak dievaluasi) sampai koin cukup. Kapal tidak dihapus dan koin tidak menjadi negatif.

## Kekayaan bersih (peringkat)
```
kekayaan = koin + sum(stok_kapal[k] * harga_dasar[k])
```
Pakai harga dasar (bukan harga pasar) supaya tidak bisa dimanipulasi dengan mendorong harga di pelabuhan.

## Invarian (harus selalu benar; dites otomatis)
1. Tidak ada koin pemain (`players.coins`), kas pelabuhan (`ports.treasury`), atau stok (`market.stock`, `ship_cargo.qty`) yang negatif.
2. `players.coins == sum(ledger.delta per pemain)`.
3. **Konservasi Uang Global (ADR-009):**
   `sum(players.coins) + sum(ports.treasury) + pengurang_kumulatif_upkeep == total_modal_awal_pemain + total_kas_awal_pelabuhan`.
4. Harga dalam `[round(dasar*0.25), round(dasar*4.0)]` dan bilangan bulat `>= 1`.
5. Muatan kapal `<= kapasitas`.
6. Stok pelabuhan dalam `[0, kapasitasGudang]`.

## Pemeriksaan eksploit
- **Arbitrase siklus:** beli $n$ unit A → jual $n$ unit A di pelabuhan yang sama pada tick yang sama selalu menghasilkan rugi bersih tepat sebesar $F_{	ext{beli}} + F_{	ext{jual}} \ge 2$ koin (termasuk di batas harga clamp `0.25x` dan `4.0x`).
- **Pembulatan:** beli lalu jual 1 unit berulang tidak pernah menghasilkan untung.
- **Dorong harga:** menguras stok untuk menaikkan harga lalu menjual kembali di pelabuhan yang sama selalu rugi sebesar biaya dua sisi.

## Metrik simulasi yang dipantau
Harga rata-rata dan volatilitas per komoditas, persentase tick di batas harga (`0.25x` / `4.0x`), Gini kekayaan, pangsa kekayaan maksimum per strategi, total koin pemain, total kas pelabuhan, pengurang kumulatif (`upkeep`), margin rata-rata per rute, persentase bot yang bangkrut (`grounded`), dan laporan upaya eksploit bot adversarial.
