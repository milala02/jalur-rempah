# Analisis A8 — Audit `docs/01-GDD.md`, `docs/02-PRD-MVP.md`, & Studi Kelayakan Klien M5

**Tanggal:** 2026-10-19  
**Cakupan Audit:**
1. Evaluasi klaim dan ambang di `docs/01-GDD.md` dan `docs/02-PRD-MVP.md` terhadap bukti empiris simulasi M1 (`A1–A4`).
2. Analisis kelayakan teknis **Milestone M5 (Klien Android)** mengingat lingkungan kerja agen tidak memiliki SDK Flutter/Android dan tidak memiliki akses internet, sehingga seluruh kompilasi APK hanya dapat diverifikasi melalui GitHub Actions CI milik pemilik.  
**Aturan Keras:** Hanya memberikan **REKOMENDASI** berbasis data dan risiko; **tidak mengubah `ADR-007`** (Keputusan teknologi klien adalah milik pemilik).

---

## 1. Evaluasi Klaim & Ambang `docs/01` dan `docs/02` terhadap Data `A1–A4`

| Klaim / Ambang di `docs/01` & `docs/02` | Penilaian Berbasis Data `A1–A4` | Apa yang Sembarang / Kurang Tepat | Usulan Pengganti Berbasis Data |
| :--- | :--- | :--- | :--- |
| **`docs/02`: "10–50 pemain uji"** | **Terbukti Kritis di `A1` / `Tugas d`**: Pada pasar statis tanpa penskalaan (`SCALE_MARKET_WITH_FLEET = false`), dunia yang disetel untuk 50 kapal mengalami **38%–69% tick harga menempel di batas clamp** saat hanya diisi 10–25 pemain! | Mengasumsikan satu set angka produksi/konsumsi statis otomatis bekerja untuk 10 maupun 50 pemain. | Tetapkan rentang dukungan resmi **10–100 kapal aktif** dengan mengaktifkan `SCALE_MARKET_WITH_FLEET = true` dan `STARTER_SHIP_CAPACITY = 35` (terbukti di `d-bot-sensitivity.json`: `pctTicksAtBounds = 0%–0,02%` pada 10, 25, 50, dan 100 kapal). |
| **`docs/01`: "Aturan pertama bisa ditulis dalam 1 menit"** vs **`docs/02`: "Pemain baru bisa menulis aturan pertama yang valid dalam < 3 menit"** | **Tidak konsisten antar dokumen (`1 menit` vs `< 3 menit`)**: Di `docs/05` v0.2, satu set aturan lengkap membutuhkan minimal 3 baris (`beli`, `jual`, `berlayar` saat muatan penuh/kosong). Mengetik DSL dari nol di layar ponsel dalam 1 menit tidak realistis dan memicu salah ketik yang berujung bangkrut (seperti bot `random` di `A3`). | Angka "1 menit" di `docs/01` terlalu agresif jika pemain mengetik teks mentah dari layar kosong. | Samakan menjadi **"< 3 menit menggunakan Templat Awal (Starter Template) 1-Ketuk + Dropdown Parameter"** (sejalan dengan `docs/02` S1 dinaikkan menjadi bagian alur onboarding M5, sehingga pemain baru memulai dari aturan setara `naive` yang terbukti bertahan hidup 100% di `A4`, bukan aturan kosong/`random`). |
| **`docs/02` Kriteria Selesai #2: "Harga setiap komoditas tetap dalam [25%, 400%] harga dasar dan tidak mati (tidak konstan) selama simulasi"** | **Terlalu longgar**: Harga हमेशा berada dalam `[25%, 400%]` hanya karena fungsi `hitungHarga` memiliki `clamp(0.25, 4.0)`! Bahkan ketika ekonomi rusak parah (kas Batavia habis di tick 45 pada `A2`), kriteria #2 lama tetap "lulus" karena harga menempel di 25% dan 400%. | Memeriksa apakah harga berada di dalam rentang `clamp` tidak menguji kesehatan pasar, melainkan hanya menguji fungsi `Math.min/max`. | Ganti kriteria #2 di `docs/02` dengan ambang Gerbang M1 (`docs/06` & `Tugas f`):<br>1. `pctTicksAtBounds <= 20%` per komoditas (di dunia sehat kita: `0,00%`),<br>2. `stdDevPrice > 0` (volatilitas terukur `8%–32%`),<br>3. `minPortTreasury > 0` sepanjang 10.000 tick,<br>4. `bankruptBotPct <= 30%`,<br>5. `skillGradientRatio >= 1,3x` dan `maxStrategyWealthSharePct <= 40%`. |
| **`docs/01`: "Menang dengan satu aturan terbaik: strategi tunggal mendominasi" & Ambang `<= 40%` pangsa kekayaan di `docs/10`** | **Terverifikasi di `A4`**: Pada 5 Strategi (masing-masing 20% populasi kapal), strategi cerdas terbaik (`adversarial`, `margin_hunter`, `hoarder`) masing-masing meraih pangsa **26%–35%** (total ~90% dibagi bertiga), sedangkan `naive` meraih **~9,5%** dan `random` **~0%**. | Ambang `<= 40%` hanya bermakna jika populasi strategi didistribusikan merata (5 keluarga strategi x 20% populasi) DAN disertai batas bawah **Gradien Keahlian `>= 1,3x`**. Tanpa syarat `skillGradient >= 1,3x`, semua strategi yang sama-sama mendapat 20% (termasuk `naive` menang) akan dianggap "lulus". | Pertahankan batas atas monopoli `maxStrategyWealthSharePct <= 40%` DAN tambahkan syarat wajib pasangan **`skillGradientRatio (BestSmart / Naive) >= 1,3x`** (tercapai `3,29x–3,87x` di 10 seed). |
| **`docs/02`: "Metrik pantauan beta: Retensi hari-7, jumlah revisi aturan per pemain, distribusi kekayaan (Gini)..."** | **Kurang ambang kuantitatif**: Data `A1–A4` menunjukkan bahwa di ekonomi sehat dengan 50 pemain (40 aktif cerdas/naif + 10 bangkrut acak), koefisien **Gini kekayaan stabil di rentang `0,34–0,38`** dan waktu menggandakan modal awal (`1.000 -> 2.000` koin) bagi aturan cerdas adalah **50–65 tick (~25–33 menit waktu nyata pada 30 detik/tick)**. | Belum ada angka acuan sehat untuk Gini dan laju progres awal. | Gunakan data simulasi sebagai acuan telemetri beta:<br>- **Waktu mencapai 2x modal awal**: ~30 menit bagi aturan cerdas (~55 tick), ~90 menit bagi aturan naif (~180 tick).<br>- **Gini kekayaan sehat**: `0,25–0,50` (jika Gini $> 0,65$, indikasi monopoli atau eksploitasi baru). |

---

## 2. Analisis Kelayakan Milestone M5 (Klien Android) Tanpa SDK Flutter di Lingkungan Agen

### 2.1. Kendala Fakta Lingkungan Kerja
1. Lingkungan VM agen **tidak memiliki SDK Flutter, Dart, Android SDK/NDK, maupun Gradle**, dan **tidak memiliki koneksi internet** untuk mengunduhnya.
2. Akibatnya, jika klien ditulis dalam **Flutter/Dart**:
   - Agen menulis 100% kode Dart secara *blind coding* (tanpa `dart analyze`, tanpa `flutter test`, dan tanpa bisa merender/menjalankan UI di VM).
   - Setiap kesalahan kecil (tipe data Dart, *null safety*, ketidakcocokan versi paket `pubspec.yaml`, konfigurasi Gradle/Kotlin di `android/app/build.gradle`) baru akan ketahuan saat pemilik membawa zip ke GitHub dan menjalankan GitHub Actions (`build-apk`).
   - Satu siklus perbaikan membutuhkan bolak-balik penuh antara pemilik dan agen (**biaya putaran sangat tinggi**).
3. Sebaliknya, lingkungan VM agen **memiliki `Node.js v18.20.4`, `@babel/core`, `@babel/preset-typescript`, dan Python 3** yang dapat mentranspilasi dan menguji seluruh logika TypeScript secara lokal sebelum diserahkan ke pemilik!

### 2.2. Perbandingan 3 Opsi Arsitektur Klien M5

| Kriteria Evaluasi | Opsi A: Flutter Murni dalam Irisan Kecil (*Small CI-Verified Slices*, sesuai `ADR-007` saat ini) | Opsi B: Klien Web Responsif TypeScript (PWA / SPA) + Pembungkus Android Tipis (Capacitor / WebView Shell) di CI | Opsi C: Inti Logika Klien (`client-sdk` TypeScript) Teruji Penuh di VM + UI Flutter Minimal tanpa Paket Eksternal Rumit |
| :--- | :--- | :--- | :--- |
| **Keterujian Lokal di VM Agen (Sebelum Masuk CI)** | **0% (Nol)** — Agen tidak bisa menjalankan `dart analyze` atau `flutter test` di VM. | **95%–100%** — Seluruh state management, pemanggilan API, validasi editor aturan (langsung memakai `@jalur-rempah/dsl`!), dan komponen UI dapat ditranspilasi & diuji di Node.js VM. | **~70%** — Seluruh klien HTTP, cache state, dan validasi editor aturan diuji di Node.js VM; hanya lapisan widget Dart (5 layar standar `MaterialApp` + `http` bawaan) yang diverifikasi di CI. |
| **Berbagi Kode (*Code Sharing*) dengan Monorepo TypeScript** | **Tidak bisa** — Harus menulis ulang atau memanggil endpoint server untuk validasi DSL; model tipe respons API harus disalin manual ke Dart. | **100% Berbagi Langsung** — Klien langsung mengimpor `@jalur-rempah/shared` dan `@jalur-rempah/dsl` (validasi aturan real-time di editor berjalan 0 ms secara offline di ponsel tanpa round-trip ke server!). | **Sebagian** — Dokumentasi kontrak disinkronkan via tes skema di Node, tetapi UI Dart tetap terpisah. |
| **Risiko Gagal Build APK di GitHub Actions CI** | **Tinggi (3–5 putaran revisi)** — Rawan konflik versi Gradle/AGP, Kotlin, dan `pubspec.lock` karena agen tidak bisa membuat `pubspec.lock` tanpa internet. | **Sangat Rendah (1 putaran)** — Aplikasi web dapat langsung dibuka di browser ponsel Android (PWA) pada putaran pertama, DAN dibungkus menjadi APK standar lewat Capacitor/WebView di CI. | **Sedang (1–2 putaran)** — Jika Flutter hanya memakai SDK `flutter` murni + paket `http` (tanpa state library pihak ketiga), risiko konflik dependensi jauh lebih kecil, tetapi tetap butuh pembuatan `pubspec.lock` di CI. |
| **Biaya Putaran bagi Pemilik** | Tinggi (pemilik harus bolak-balik mengirim log error compiler Dart/Gradle). | **Paling Rendah** (pemilik bisa langsung menguji UI di browser lokal/ponsel bahkan sebelum build APK selesai). | Sedang. |
| **Kesesuaian dengan `ADR-007` & `docs/02` Kriteria #6 ("APK terpasang di 2 HP")** | Sesuai penuh dengan `ADR-007` tanpa perubahan. | Memenuhi Kriteria #6 (menghasilkan APK Android yang bisa dipasang di 2 HP + bonus bisa diakses via browser), namun memerlukan revisi `ADR-007` oleh pemilik. | Memenuhi `ADR-007` (tetap Flutter APK) sekaligus meminimalkan kode Dart yang tidak teruji di VM. |

---

## 3. Rekomendasi untuk Pemilik (Tanpa Mengubah `ADR-007`)

1. **Rekomendasi Utama (Opsi B — Web/PWA TypeScript + Pembungkus APK Android di CI)**:
   - Mengingat kendala tanpa internet dan tanpa Flutter SDK di lingkungan agen, serta fakta bahwa game ini berbasis **peta 2D sederhana, tabel pasar, editor teks aturan DSL, dan log tick** (`docs/01`: *"UI berbasis peta 2D sederhana dan daftar"*), membangun klien dengan **TypeScript** memungkinkan:
     - **100% kode klien diverifikasi di VM agen** sebelum diserahkan ke pemilik,
     - **Penggunaan langsung paket `@jalur-rempah/dsl`** di dalam editor aturan klien untuk penyorotan sintaks dan validasi instan 0 ms,
     - Pemilik tetap mendapatkan **berkas `.apk` Android** yang siap dipasang di 2 HP uji melalui pembungkus Capacitor / Android WebView di workflow `build-apk.yml`.
2. **Rekomendasi Alternatif jika Pemilik Tetap Memilih Flutter Murni (`ADR-007` Tetap, Opsi A/C)**:
   - Jika pemilik mempertahankan Flutter, kami merekomendasikan aturan ketat berikut untuk M5:
     - **Nol paket pihak ketiga selain `http` (atau bahkan murni `dart:io` `HttpClient` + `dart:convert` + `ValueNotifier` bawaan Flutter SDK!)**: Dengan hanya memakai pustaka standar bawaan SDK Flutter (`flutter/material.dart`, `dart:convert`, `dart:async`), proyek Flutter **tidak memerlukan pengunduhan paket eksternal yang rawan gagal resolusi versi** dan hanya bergantung pada SDK Flutter standar di GitHub Actions (`subosito/flutter-action@v2`).
     - Kerjakan M5 dalam **2 irisan terpisah**: Irisan 5a (kerangka proyek Flutter + layar Login & Peta/Pasar, pastikan APK terbangun hijau di CI lebih dulu), baru lanjut Irisan 5b (Editor Aturan, Sandbox, Log, Leaderboard).
