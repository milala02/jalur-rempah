# 02 — PRD / Scope MVP v0.1

## Tujuan MVP
Membuktikan bahwa loop "tulis aturan → dunia berjalan → perbaiki aturan" menyenangkan dan ekonomi bersama stabil, dengan 10-50 pemain uji.

## Prioritas fitur
**WAJIB (Must)**
- M1. Akun (daftar, masuk, token)
- M2. Dunia statis: 6 pelabuhan, 4 komoditas, graf rute
- M3. Pasar dinamis per pelabuhan (harga dari stok)
- M4. 1 kapal per pemain dengan muatan terbatas
- M5. Bahasa Aturan: simpan, validasi, jalankan tiap tick
- M6. Simulasi tick di server, persisten, aman saat restart
- M7. Log aksi per kapal yang menjelaskan alasan
- M8. Peringkat kekayaan bersih
- M9. Klien Android: login, peta/daftar pelabuhan, pasar, editor aturan, log, peringkat
- M10. Endpoint simulasi sandbox untuk menguji aturan

**SEBAIKNYA (Should)**
- S1. Templat aturan siap pakai dan tutorial singkat
- S2. Grafik harga 24 jam terakhir per komoditas
- S3. Notifikasi saat kapal rugi beruntun atau sandar

**NANTI (Could/Won't di MVP)**
- Banyak kapal, kabut informasi, guild, pertukaran antarpemain, kosmetik

## Kriteria selesai MVP (terukur)
1. Simulasi 50 bot x 10.000 tick: tidak ada stok negatif, saldo negatif, atau invarian uang yang rusak.
2. Harga setiap komoditas tetap dalam [25%, 400%] harga dasar dan tidak mati (tidak konstan) selama simulasi.
3. Tick lag server p95 < 20% dari durasi tick pada 100 kapal.
4. Pemain baru bisa menulis aturan pertama yang valid dalam < 3 menit (uji manual 5 orang).
5. Restart paksa worker di tengah tick tidak merusak data (uji kill -9 otomatis).
6. APK terpasang dan berfungsi di minimal 2 HP berbeda.

## Cerita pengguna inti
- Sebagai pemain, saya menulis aturan "beli pala di Banda jika murah, jual di Batavia jika mahal" dan melihat kapal saya menjalankannya.
- Sebagai pemain, saya melihat log mengapa kapal saya menunggu.
- Sebagai pemain, saya menguji aturan baru di sandbox 200 tick sebelum menyimpannya.
- Sebagai pemain, saya melihat posisi saya di peringkat.

## Metrik pantauan beta
Retensi hari-7, jumlah revisi aturan per pemain, distribusi kekayaan (Gini), volatilitas harga, jumlah aturan yang gagal validasi.

## Batasan
- Satu region server, satu dunia
- Dukungan Android saja
- Offline total = klien hanya baca cache
