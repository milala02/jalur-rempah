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
- **Konsekuensi:** Tes invarian rutin; sedikit overhead tulis.

## ADR-007 — Klien Flutter sebagai tampilan tipis
- **Status:** Diterima
- **Konteks:** Pengembangan hanya via VPS + build GitHub, tes di HP sendiri.
- **Keputusan:** Flutter untuk Android; tidak ada logika game di klien.
- **Konsekuensi:** Klien mudah diganti; semua fitur butuh endpoint.

## ADR-008 — Informasi pasar real-time global di MVP
- **Status:** Diterima (bisa diganti di Fase 2)
- **Konteks:** Kabut informasi menambah kedalaman tapi juga kompleksitas data.
- **Keputusan:** MVP: harga semua pelabuhan terlihat real-time oleh aturan.
- **Konsekuensi:** Arbitrase lebih mudah; evaluasi dampaknya di beta sebelum menambah kabut.

## ADR-009 — Eksekusi transaksi simetris dan kas pelabuhan (treasury) tertutup
- **Status:** Diterima
- **Konteks:**
  1. Jika jual 1 unit memakai `harga(stok)` sebelum `stok += 1` sedangkan beli 1 unit memakai `harga(stok)` sebelum `stok -= 1`, maka beli $n$ unit dari stok $S$ lalu jual $n$ unit dari stok $S-n$ mengevaluasi kurva harga pada indeks stok yang bergeser satu langkah ($\{S, \dots, S-n+1\}$ vs $\{S-n, \dots, S-1\}$), yang membuka celah arbitrase siklus di pelabuhan yang sama.
  2. Tanpa kas pelabuhan (`treasury`) yang terbatas dan dengan biaya pelabuhan 2% sebagai pemusnah koin, dunia kehabisan uang beredar (deflasi) atau sebaliknya pelabuhan membeli barang tanpa batas likuiditas.
- **Keputusan:**
  1. **Eksekusi Simetris**: Beli 1 unit membayar `hitungHarga(stok)` lalu `stok -= 1`. Jual 1 unit melakukan `stok += 1` **lebih dulu**, lalu menerima `hitungHarga(stok)` (stok baru). Dengan demikian beli $n$ lalu jual $n$ di pelabuhan yang sama mengevaluasi himpunan harga satuan yang identik ($\{S, S-1, \dots, S-n+1\}$) sehingga nilai kotor pembelian dan penjualan selalu sama persis dan siklus beli-jual selalu rugi tepat sebesar biaya transaksi dua sisi.
  2. **Kas Pelabuhan (`ports.treasury`)**: Setiap pelabuhan memiliki `treasury BIGINT NOT NULL CHECK (treasury >= 0)` (dan `initial_treasury` dari konfigurasi). Pembelian pemain menambah kas pelabuhan sebesar nilai kotor + biaya 2%; penjualan pemain dibayar dari kas pelabuhan (dibatasi secara deterministik oleh kas tersedia dan ruang gudang), sementara biaya 2% masuk/tetap di kas pelabuhan tempat transaksi.
  3. **Invarian Konservasi Uang**: Biaya perawatan kapal (`upkeep`) adalah satu-satunya pengurang koin sistem (*money sink*) dan dicatat eksplisit di `ledger` (`reason = 'upkeep'`). Berlaku invarian ketat: `total koin pemain + total kas pelabuhan + pengurang kumulatif (upkeep) = total modal awal pemain + total kas awal pelabuhan`.
- **Konsekuensi:** Arbitrase siklus beli-jual di pelabuhan yang sama mustahil menghasilkan untung pada seluruh rezim stok (termasuk batas clamp `0.25x` dan `4.0x`). Likuiditas tiap pelabuhan menjadi variabel ekonomi nyata yang mencegah eksploitasi penjualan tak terbatas ke satu pelabuhan, dan konservasi uang dapat diaudit secara eksak setiap tick.

## Template
```
## ADR-XXX — Judul
- Status: Diusulkan
- Konteks:
- Keputusan:
- Konsekuensi:
```
