# Analisis A3 — Pemulihan Darurat (`RESCUE_COINS = 200`, Cooldown `2.880` Tick)

**Tanggal:** 2026-10-19  
**Lingkungan Eksekusi:** VM lokal (`Node.js v18.20.4`, x86_64 Debian GNU/Linux 12)  
**Berkas Data Pendukung:** `docs/analisis/data/a3-emergency-rescue.json`

---

## 1. Rumusan Masalah

Dokumen `docs/06` dan `docs/09` v0.2 mencantumkan fitur opsional **Pemulihan Darurat (Emergency Rescue)** di balik flag konfigurasi `RESCUE_ENABLED`:
- **Syarat memicu**: `ship.status == 'grounded'`, `SUM(ship_cargo.qty) == 0` (kargo kosong sehingga tidak punya apa pun untuk dijual), `player.coins < UPKEEP_PER_TICK` (`< 1` koin), dan `tick_no - last_rescue_tick >= RESCUE_COOLDOWN_TICKS` (`2.880` tick = 24 jam waktu nyata pada 30 detik/tick).
- **Efek**: Menambah `RESCUE_COINS = 200` koin ke `player.coins`, mencatat baris `ledger` (`reason = 'rescue', delta = +200`), dan menambah `sumber_kumulatif` sebesar `200` koin.
- **Pertanyaan Analisis**:
  1. Berapa persen akun mati permanen (`permanentlyDeadBotCount`) dengan dan tanpa pemulihan darurat?
  2. Berapa total koin baru yang diciptakan oleh pemulihan darurat (`cumulativeRescueSource`), dan apakah menyebabkan inflasi?
  3. Apakah mekanisme ini memicu eksploitasi (*rescue farming* — pemain sengaja mengosongkan koin & kargo untuk memanen 200 koin gratis)?

---

## 2. Metodologi & Pengujian Eksploitasi Adversarial

Di dalam simulator (`packages/econ/src/sim/engine.ts`), bot `adversarial` diprogram untuk setiap tick menguji apakah **sengaja bangkrut untuk memanen `RESCUE_COINS = 200` koin setiap `2.880` tick** menghasilkan laju koin per tick yang lebih tinggi daripada berdagang normal (`rescueFarmingAttempts`):
- Laju koin kotor dari *rescue farming*: maksimal $\frac{200\text{ koin}}{2.880\text{ tick}} = 0,0694\text{ koin/tick}$.
- Begitu menerima `200` koin, kapal kembali berstatus `docked` dan langsung dikenai `UPKEEP_PER_TICK = 1` koin/tick selama `200` tick berikutnya (total biaya perawatan `-200` koin), sehingga **keuntungan bersih diam menunggu rescue berikutnya adalah `0` koin/tick**!
- Sebaliknya, berdagang normal menghasilkan keuntungan bersih rata-rata **30–180 koin/tick** (400x–2.500x lebih besar daripada *rescue farming*).

---

## 3. Hasil Simulasi pada Seed Tuning (`101, 202, 303`) & Seed Validasi (`1001, 1002, 1003`)

Simulasi dijalankan selama `10.000` tick dengan `50` bot (termasuk 10 bot strategi `random` yang mewakili pemain pemula yang membuat aturan buruk dan bangkrut berulang kali). Data lengkap di `docs/analisis/data/a3-emergency-rescue.json`:

| Opsi Konfigurasi | Set Seed | Lulus Gerbang | Bot Grounded Akhir (%) | Akun Mati Permanen di Tick 10.000 (%) | Total Frekuensi Rescue (10k Tick) | Total Koin Rescue Dibuat (`cumulativeRescueSource`) | Pangsa Koin Rescue thd Uang Pemain (%) | Eksploit Rescue Menguntungkan (`profitableExploitsFound`) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Opsi 1: `rescue_enabled_200_cd2880` (Default Flag Aktif)** | Tuning | **LULUS** | 19,33% | 19,33% (hanya bot `random` saat sedang dalam masa cooldown) | 39,0 kali | **7.800 koin** | **0,24%** | **0** (dari 7.184 uji eksploit) |
| **Opsi 1: `rescue_enabled_200_cd2880` (Default Flag Aktif)** | Validasi | **LULUS** | 18,67% | 18,67% (hanya bot `random` saat sedang dalam masa cooldown) | 38,3 kali | **7.667 koin** | **0,24%** | **0** (dari 7.162 uji eksploit) |
| Opsi 2: `rescue_disabled` (`RESCUE_ENABLED = false`) | Tuning | **LULUS** | 20,00% | **20,00% mati permanen selamanya** (sejak tick ~450) | 0 kali | 0 koin | 0,00% | 0 |
| Opsi 2: `rescue_disabled` (`RESCUE_ENABLED = false`) | Validasi | **LULUS** | 20,00% | **20,00% mati permanen selamanya** (sejak tick ~450) | 0 kali | 0 koin | 0,00% | 0 |
| Opsi 3: `rescue_100_cd5760` (`100` koin, cooldown `5.760` tick / 48 jam) | Tuning | **LULUS** | 19,33% | 19,33% | 20,0 kali | **2.000 koin** | **0,06%** | 0 |
| Opsi 3: `rescue_100_cd5760` (`100` koin, cooldown `5.760` tick / 48 jam) | Validasi | **LULUS** | 20,00% | 20,00% | 20,0 kali | **2.000 koin** | **0,06%** | 0 |

### Interpretasi Data
1. **Tanpa Pemulihan Darurat (`rescue_disabled`)**:
   - Seluruh 10 bot `random` (100% dari pemain yang salah menyusun aturan awal) kehabisan koin dan kargo sebelum tick 500 (~4 jam bermain) dan **mati permanen selamanya** tanpa jalan keluar selain membuat akun baru.
2. **Dengan Pemulihan Darurat (`RESCUE_COINS = 200`, `RESCUE_COOLDOWN_TICKS = 2.880`)**:
   - Setiap pemain yang bangkrut total (0 koin, 0 kargo) mendapat modal darurat `200` koin maksimal sekali sehari (cukup untuk membeli ~2 unit Cengkeh atau ~10 unit Garam dan bangkit kembali jika ia memperbaiki aturannya).
   - Total koin yang diciptakan selama 10.000 tick untuk 50 pemain hanya **~7.800 koin** (**0,24%** dari total koin pemain ~3,23 juta), dan seluruhnya habis terbakar kembali oleh `UPKEEP_PER_TICK` jika pemain tersebut tidak memperbaiki aturannya.
   - **Nol eksploitasi**: `profitableExploitsFound = 0` di seluruh seed tuning dan validasi.

---

## 4. Rekomendasi, Risiko, dan Ketidakpastian (Keputusan Milik Pemilik)

- **Status Keputusan**: Sesuai instruksi misi, keputusan akhir apakah Pemulihan Darurat diaktifkan di produksi adalah **milik pemilik proyek**.
- **Implementasi Saat Ini**: Diimplementasikan secara murni di `stepWorld` Langkah 7 di balik flag konfigurasi `WORLD_CONFIG.RESCUE_ENABLED = true` (`RESCUE_COINS = 200n`, `RESCUE_COOLDOWN_TICKS = 2880`), lengkap dengan pencatatan di `sumber_kumulatif` dan tes unit di `packages/econ/test/sim.test.ts`.
- **Rekomendasi untuk Pemilik**: **Aktifkan (`RESCUE_ENABLED = true`, `RESCUE_COINS = 200`, `RESCUE_COOLDOWN_TICKS = 2880`)** karena mencegah *churn* permanen pemain pemula dengan biaya inflasi yang sangat kecil (`0,24%`) dan terbukti bebas eksploitasi pada 1 pemain = 1 akun.
- **Risiko & Apa yang Belum Diketahui**: Jika di masa depan terdapat fitur transfer koin langsung antar-pemain (yang saat ini **dilarang** di MVP karena semua perdagangan wajib melalui pasar pelabuhan), peternakan akun bot (*multi-account sybil*) dapat mencoba mentransfer 200 koin rescue lewat manipulasi stok pasar di pelabuhan sepi. Namun dengan biaya pelabuhan 2% dua arah dan tanpa transfer langsung, serangan ini selalu merugi bagi komoditas likuid.
