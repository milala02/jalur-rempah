# 04 — Architecture Decision Records (ADR)

Format: Konteks → Keputusan → Konsekuensi. Status: Diterima / Diganti / Ditolak. Tambahkan record baru di bawah, jangan menulis ulang yang lama (tandai "Diganti oleh ADR-X").

## ADR-001 — Bahasa Aturan buatan sendiri, bukan JavaScript sandbox
- **Status:** Diterima
- **Konteks:** Pemain menulis logika yang berjalan di server. Menjalankan JS/Lua bebas berisiko (sandbox escape, loop tak hingga, nondeterminisme).
- **Keputusan:** DSL deklaratif berbasis aturan (`jika ... maka ...`), tanpa loop, tanpa rekursi, tanpa I/O, aritmetika integer, dengan anggaran evaluasi.
- **Konsekuensi:** Aman dan deterministik; evaluasi murah. Ekspresivitas terbatas; kelas strategi tertentu butuh fitur DSL baru. Parser dan evaluator harus kita bangun dan tes sendiri.

## ADR-002 — Simulasi server-authoritative dengan tick diskret
- **Status:** Diterima
- **Konteks:** Dunia persisten dan adil, banyak pemain, klien tidak dipercaya.
- **Keputusan:** Worker tunggal menjalankan tick tiap N detik; semua efek lewat satu transaksi.
- **Konsekuensi:** Determinisme dan kemudahan debug; latensi aksi = durasi tick; satu worker = satu titik gagal (dimitigasi restart aman).

## ADR-003 — PostgreSQL sebagai satu-satunya penyimpanan
- **Status:** Diterima
- **Konteks:** Butuh transaksi ACID untuk ekonomi dan ledger.
- **Keputusan:** PostgreSQL 16 untuk semua data; tanpa Redis di MVP.
- **Konsekuensi:** Sederhana dan konsisten; cache baca ditunda sampai terbukti perlu.

## ADR-004 — Backend TypeScript strict, monorepo pnpm
- **Status:** Diterima
- **Konteks:** Pengembang sudah akrab dengan Node/Fastify; tipe bersama antara api, worker, dan skema.
- **Keputusan:** TypeScript strict, pnpm workspace.
- **Konsekuensi:** Tipe dan validasi bisa dibagi; klien Flutter tidak berbagi tipe langsung (kontrak lewat `08`).

## ADR-005 — Uang dan jumlah barang integer
- **Status:** Diterima
- **Konteks:** Float menimbulkan galat pembulatan yang bisa dieksploitasi dan merusak invarian.
- **Keputusan:** Koin dan stok integer; harga turunan dibulatkan di satu fungsi.
- **Konsekuensi:** Perlu aturan pembulatan eksplisit di `06`.

## ADR-006 — Ledger append-only
- **Status:** Diterima
- **Konteks:** Perlu audit dan deteksi eksploit.
- **Keputusan:** Setiap perubahan koin tercatat di `ledger`; saldo pemain di-cache dan harus sama dengan jumlah ledger.
- **Konsekuensi:** Tes invarian rutin; sedikit overhead tulis (dioptimalkan oleh ADR-011).

## ADR-007 — Klien Flutter sebagai tampilan tipis
- **Status:** Diterima (lihat evaluasi kelayakan M5 di `docs/analisis/A8-audit-gdd-prd-kelayakan-m5.md` untuk keputusan pemilik)
- **Konteks:** Pengembangan hanya via VPS + build GitHub, tes di HP sendiri.
- **Keputusan:** Flutter untuk Android; tidak ada logika game di klien.
- **Konsekuensi:** Klien mudah diganti; semua fitur butuh endpoint.

## ADR-008 — Informasi pasar real-time global di MVP
- **Status:** Diterima untuk MVP, diperluas oleh ADR-012 di Fase 2
- **Konteks:** Kabut informasi menambah kedalaman tapi juga kompleksitas data.
- **Keputusan:** MVP: harga semua pelabuhan terlihat real-time oleh aturan (`harga_di(p, k)`).
- **Konsekuensi:** Arbitrase lebih mudah; di Fase 2 ditambahkan `harga_terakhir(p, k)` berbasis tabel `port_intel` (ADR-012).

## ADR-009 — Eksekusi transaksi simetris dan kas pelabuhan (treasury) tertutup
- **Status:** Diterima (diperluas oleh ADR-010 untuk mekanisme pendapatan pelabuhan konsumen dan syarat kas bersih $N \le \text{treasury}$)
- **Konteks:**
  1. Jika jual 1 unit memakai `harga(stok)` sebelum `stok += 1` sedangkan beli 1 unit memakai `harga(stok)` sebelum `stok -= 1`, maka beli $n$ unit dari stok $S$ lalu jual $n$ unit dari stok $S-n$ mengevaluasi kurva harga pada indeks stok yang bergeser satu langkah, yang membuka celah arbitrase siklus di pelabuhan yang sama.
  2. Tanpa kas pelabuhan (`treasury`) yang terbatas dan dengan biaya pelabuhan 2% sebagai pemusnah koin, dunia kehabisan uang beredar (deflasi) atau sebaliknya pelabuhan membeli barang tanpa batas likuiditas.
- **Keputusan:**
  1. **Eksekusi Simetris**: Beli 1 unit membayar `hitungHarga(stok)` lalu `stok -= 1`. Jual 1 unit melakukan `stok += 1` **lebih dulu**, lalu menerima `hitungHarga(stok)` (stok baru).
  2. **Kas Pelabuhan (`ports.treasury`)**: Setiap pelabuhan memiliki `treasury BIGINT NOT NULL CHECK (treasury >= 0)`. Pembelian pemain menambah kas pelabuhan sebesar nilai kotor + biaya 2%; penjualan pemain dibayar dari kas pelabuhan, sementara biaya 2% masuk/tetap di kas pelabuhan tempat transaksi.
  3. **Invarian Konservasi Uang**: Berlaku invarian konservasi uang yang diperluas dengan suku `sumber_kumulatif` pada ADR-010.
- **Konsekuensi:** Arbitrase siklus beli-jual di pelabuhan yang sama mustahil menghasilkan untung pada seluruh rezim stok (termasuk batas clamp `0.25x` dan `4.0x`).

## ADR-010 — Mekanisme pendapatan pelabuhan konsumen (`sumber_kumulatif`), syarat kas jual `N <= treasury`, dan penskalaan pasar adaptif
- **Status:** Diterima (Berdasarkan Analisis `A1`, `A2`, `A3`, `A4`)
- **Konteks:**
  1. Pelabuhan konsumen murni (Batavia, konsumsi 32 unit/tick, produksi 0) dan konsumen bersih (Malaka, Surabaya) hanya membeli kargo dari pemain tanpa pemasukan eksternal. Pada `INITIAL_PORT_TREASURY = 50.000` tanpa pemasukan, kas Batavia habis pada tick 45; pada `25.000.000`, kas Batavia tetap terkuras ~1.925 koin/tick dan habis sebelum tick 40.000 (`docs/analisis/A2-pendapatan-pelabuhan.md`).
  2. Syarat kas pada penjualan di dokumen lama ditulis `G <= treasury`, padahal kas pelabuhan berkurang bersih sebesar `N = G - F` karena biaya `F` tinggal di dalam kas pelabuhan.
  3. Kapasitas kapal statis (`20` atau `45`) tanpa penskalaan pasar membuat harga menempel di batas clamp (`38%–69%` tick) pada 10–25 kapal atau memicu kongesti monopoli (`49,8%` pangsa) pada 100 kapal (`docs/analisis/A1-parameter-ekonomi.md`).
  4. Pada pasar yang terlalu tenang tanpa pergeseran permintaan, strategi `naive` menyamai strategi cerdas (gradien keahlian `1,00x`, `docs/analisis/A4-gradien-keahlian.md`).
- **Keputusan:**
  1. **Kliring Domestik Seimbang (`PORT_INCOME_ENABLED = true`)**: Kas awal tiap pelabuhan ditetapkan `INITIAL_PORT_TREASURY = 50.000` koin (`6x` total modal awal 50 pemain, memenuhi batas `<= 10x`). Setiap tick pada Langkah 3, pelabuhan menerima nilai konsumsi ritel warga lokal (`actualConsumed * base_price`) dan membayar produsen lokal atas komoditas yang diproduksi (`actualProduced * base_price`, dibatasi agar kas tidak turun di bawah `PORT_TREASURY_FLOOR = 22.000`), ditambah pemulihan proporsional menuju kas target `(INITIAL_PORT_TREASURY - treasury) / PORT_TREASURY_RESTORE_DIVISOR`.
  2. **Pencatatan Eksplisit & Invarian Konservasi Uang (`sumber_kumulatif`)**: Semua penambahan kas pelabuhan (`port_income`) dan pemulihan darurat (`rescue`) dicatat sebagai sumber (`cumulativeSource`), sedangkan perawatan kapal (`upkeep`, termasuk pajak logistik kekayaan `WEALTH_UPKEEP_BPS = 4` di atas `STARTER_COINS`) dan pembayaran produsen lokal (`port_producer_payout`) dicatat sebagai pengurang (`cumulativeUpkeepSink`) di tabel append-only `public.economy_sources_sinks` (Migrasi `0003`). Persamaan konservasi uang menjadi:
     `total_koin_pemain + total_kas_pelabuhan + pengurang_kumulatif == total_awal + sumber_kumulatif`.
  3. **Syarat Kas Jual Bersih**: Penjualan $n$ unit sah jika dan hanya jika pembayaran bersih $N(n) = G(n) - F(G(n)) \le \text{treasury}$ dan $N(n) > 0$.
  4. **Kapasitas Kapal `35` & Dinamika Pasar (`SCALE_MARKET_WITH_FLEET`, `DEMAND_SHOCK_ENABLED`)**: `STARTER_SHIP_CAPACITY` ditetapkan `35`, disertai peredam karavan pesisir domestik dan penskalaan produksi/konsumsi untuk armada $> 50$ kapal, serta guncangan permintaan terjadwal deterministik *zero-sum* setiap `40` tick (`+5` konsumsi di satu pelabuhan dan `+5` produksi di pelabuhan lain pada komoditas yang sama).
- **Konsekuensi:** Ekonomi stabil selama $\ge 200.000$ tick (drift koin pemain Q3->Q4 hanya `1,65% <= 15%`), lulus seluruh gerbang pada 10, 25, 50, dan 100 kapal, serta menghasilkan gradien keahlian `3,29x–4,79x` (`>= 1,3x`) dengan pangsa strategi tertinggi `31%–35%` (`<= 40%`).

## ADR-011 — Optimasi volume ledger perawatan kapal (`unflushed_upkeep` + agregasi blok) dan fungsi murni `stepWorld` v0.2
- **Status:** Diterima (Berdasarkan Analisis `A5` dan `docs/09` v0.2)
- **Konteks:**
  1. Mencatat perawatan kapal 1 baris per kapal per tick menghasilkan `4,32 juta` baris/bulan pada 50 kapal dan `43,2 juta` baris/bulan (`~8,9 GB/bulan`, `88,89%` dari seluruh isi `ledger`) pada 500 kapal (`docs/analisis/A5-volume-ledger.md`).
  2. `docs/03` v0.2 dan `docs/09` v0.2 menetapkan fungsi murni `stepWorld` dengan perawatan dipotong **sebelum** aksi, kapal `grounded` diizinkan `jual` dan `tunggu` (aksi `beli`/`berlayar` gagal dengan `GROUNDED` dan jatuh ke aturan berikutnya pada tick yang sama), serta tunggakan tidak diakumulasi saat `sailing`.
- **Keputusan:**
  1. **Desain Hibrida Agregasi Blok Upkeep (Migrasi `0003`)**: Menambahkan kolom `unflushed_upkeep BIGINT NOT NULL DEFAULT 0 CHECK (unflushed_upkeep >= 0)` dan `cumulative_upkeep_paid BIGINT NOT NULL DEFAULT 0 CHECK (cumulative_upkeep_paid >= 0)` pada `public.players`, serta indeks parsial `idx_ledger_player_non_upkeep ON public.ledger (player_id, id DESC) WHERE reason <> 'upkeep'`. Di antara waktu flush, pemotongan upkeep per tick mengurangi `players.coins` dan menambah `players.unflushed_upkeep`. Setiap `UPKEEP_LEDGER_BATCH_TICKS = 120` tick (atau tepat sebelum pemain melakukan transaksi `buy`/`sell`/`rescue` atau snapshot audit), `unflushed_upkeep` di-flush menjadi satu baris ringkasan `ledger` (`reason = 'upkeep', delta = -unflushed_upkeep, meta = {"from_tick", "to_tick", "ticks_count"}`) dan di-reset ke `0`.
  2. **Fungsi Murni `stepWorld`**: Mengimplementasikan seluruh 9 langkah tick `docs/09` v0.2 di `packages/econ/src/step-world.ts` sebagai fungsi murni deterministik yang digunakan oleh simulator M1, endpoint `/v1/simulate` M2, dan worker M4.
- **Konsekuensi:** Volume baris `ledger` berkurang **88,15%** (baris upkeep turun **99,17%**) tanpa mengorbankan invarian `players.coins + players.unflushed_upkeep == SUM(ledger.delta)` di setiap tick maupun `players.coins == SUM(ledger.delta)` pada setiap batas flush/transaksi.

## ADR-012 — Kabut Informasi Harga (`port_intel`), Memori Kapal Antar-Tick (`ship_memory`), Multi-Kapal, Serikat Dagang, Kontrak Escrow, dan Anonimisasi Akun (Fase 2)
- **Status:** Diterima (Fase 2 Pasca-MVP, Migrasi `0004`)
- **Konteks:**
  1. Setelah seluruh milestone MVP (`M0–M6`) hijau di CI, peta jalan Fase 2 (`docs/01`, `docs/05`, `docs/08`, `docs/09`, `docs/13`) mengamanatkan kabut informasi harga (`harga_terakhir`), variabel lokal (`biar x = ...`), memori kapal antar-tick (`simpan`/`ambil`), banyak kapal per pemain, serikat dagang ringan, kontrak pengiriman komoditas, musim angin muson (`musim()`), serta penghapusan akun (`DELETE /v1/me`).
  2. Seluruh fitur ekonomi baru di Fase 2 (pembelian kapal baru, jaminan kontrak pengiriman, dan penghapusan akun) wajib mempertahankan invarian konservasi uang global `economy_money_supply_audit` (`diff == 0`) dan sifat *append-only* pada `public.ledger`.
- **Keputusan:**
  1. **Kabut Informasi (`public.port_intel` & `harga_terakhir(p, k)`)**: Setiap kali kapal pemain bersandar (`docked`/`grounded`) di suatu pelabuhan pada tick $t$, worker memperbarui `port_intel(player_id, port_id, commodity_id, price, stock, tick_seen = t)`. Fungsi DSL `harga_terakhir(p, k)` membaca harga langsung bila kapal sedang berada di pelabuhan $p$, atau membaca rekaman `port_intel` terakhir pemain untuk $(p, k)$. `harga_di(p, k)` tetap dipertahankan demi kompatibilitas mundur penuh dengan program aturan versi 1.
  2. **Memori Kapal Antar-Tick (`public.ship_memory`) & Variabel Lokal (`biar`)**: Setiap kapal memiliki kuota 8 slot integer (`0..7`) yang dibaca dengan `ambil(slot)` dan ditulis dengan aksi `simpan(slot, nilai)`. Aturan juga mendukung deklarasi `biar <ident> = <ekspresi>` sebelum `jika`.
  3. **Transaksi Fase 2 Tanpa Pelanggaran Konservasi Uang**:
     - Pembelian kapal baru (`POST /v1/ships/buy`, maks 5 kapal/pemain, biaya `1.500` koin) memindahkan koin dari `players.coins` ke `ports.treasury` pelabuhan galangan dengan entri `ledger` (`reason = 'buy'`).
     - Pembuatan kontrak pengiriman (`POST /v1/contracts`) mengunci `reward_coins` dari `players.coins` pembuat kontrak ke `ports.treasury` pelabuhan tujuan sebagai *escrow* (`reason = 'buy'`), dan pemenuhan kontrak (`POST /v1/contracts/:id/fulfill`) membayarkan `reward_coins` dari `ports.treasury` ke pemenuh kontrak (`reason = 'sell'`).
     - Penghapusan akun (`DELETE /v1/me`) membatalkan kontrak terbuka milik pemain, mencatat sisa koin sebagai pengurang penutupan akun (`reason = 'upkeep'`), menghapus kapal/kargo/aturan/token sesi, serta menganonimkan baris `players` (`is_deleted = true`, `email = 'anon_<id>@deleted.local'`) setelah melepas FK `ledger_ref_ship_fkey` sehingga tabel `ledger` tetap 100% *append-only* dan `economy_money_supply_audit` tetap bernilai `diff == 0`.
- **Konsekuensi:** Seluruh fitur Fase 2 berjalan secara deterministik, kompatibel mundur dengan AST v1, dan mempertahankan 0 pelanggaran invarian konservasi uang di setiap titik waktu.

## Template
```
## ADR-XXX — Judul
- Status: Diusulkan
- Konteks:
- Keputusan:
- Konsekuensi:
```
