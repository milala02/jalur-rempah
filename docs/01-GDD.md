# 01 — Game Design Document (GDD) v0.1

## Konsep satu kalimat
Dunia perdagangan rempah yang terus hidup di server; pemain tidak mengemudikan kapal, melainkan **menulis aturan** yang mengendalikan kapal dagangnya, dan bersaing di pasar bersama.

## Pilar desain
1. **Pemain adalah programmer, bukan operator.** Kemenangan datang dari aturan yang cerdas, bukan kecepatan jari.
2. **Dunia hidup tanpa pemain.** Pasar, harga, dan kapal terus berjalan saat offline.
3. **Ekonomi adil dan terbaca.** Semua harga bergerak karena penawaran dan permintaan yang bisa dipahami.
4. **Mudah masuk, dalam di ujung.** Aturan pertama bisa ditulis dalam 1 menit; strategi tingkat lanjut butuh pemikiran.

## Audiens
Pemain mobile yang suka strategi, optimasi, dan logika (gaya Screeps, EVE, Factorio) tapi ingin sesi singkat.

## Dunia (MVP)
- 6 pelabuhan di kepulauan fiktif-realistis: Banda, Ternate, Makassar, Surabaya, Batavia, Malaka
- 4 komoditas: pala, cengkeh, garam, kain
- Pelabuhan terhubung dalam graf berbobot (jarak dalam tick)

## Loop inti
1. Pemain menulis/mengedit **aturan** kapal di editor.
2. Server menjalankan aturan tiap tick: beli, jual, berlayar, atau tunggu.
3. Pemain melihat **log** dan hasil (koin, rute, margin).
4. Pemain menyadari kelemahan aturan (rugi, antre, harga anjlok), lalu memperbaiki.
5. Ulangi, naik peringkat, buka kapal dan fitur baru.

## Progres pemain (MVP)
- Mulai: 1 kapal, modal 1.000 koin
- Peringkat berdasarkan kekayaan bersih (koin + nilai muatan pada harga pasar)

## Umpan balik yang dirasakan pemain
- Log setiap tick yang menjelaskan **mengapa** aturan terpilih ("aturan jual_lada cocok: harga 74 > 70")
- Simulasi sandbox: uji aturan pada snapshot pasar tanpa risiko

## Non-goals (sengaja tidak dibuat di MVP)
- Pertempuran, bajak laut, cuaca acak
- Chat, guild, perdagangan langsung antarpemain
- Pembelian dalam aplikasi, iklan
- Skrip bebas (JavaScript/Lua) dari pemain
- Grafis 3D atau animasi kompleks (UI berbasis peta 2D sederhana dan daftar)
- Kapal lebih dari 1 per pemain (masuk Fase 2)

## Risiko desain utama
- **Terlalu teknis**: kurva belajar bahasa aturan. Mitigasi: editor dengan templat, validasi real-time, tutorial 3 aturan.
- **Ekonomi runtuh**: inflasi, monopoli, eksploit. Mitigasi: dokumen 06 dan simulasi massal sebelum beta.
- **Menang dengan satu aturan terbaik**: strategi tunggal mendominasi. Mitigasi: dampak pasar (slippage) membuat strategi populer kehilangan margin.

## Ide Fase 2 (belum terikat)
Kabut informasi (harga hanya diketahui dari kunjungan terakhir), banyak kapal, upgrade pelabuhan, kontrak antarpemain, event musiman.
