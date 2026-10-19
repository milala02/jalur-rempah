# 03 — Arsitektur v0.1

## Diagram konseptual
```
 [Flutter App] --HTTPS/JSON--> [nginx] --> [api (Fastify)] --\
                                                              >--> [PostgreSQL]
                              [worker (tick loop)] ----------/
```
- `api`: autentikasi, baca dunia, kelola aturan, endpoint simulasi (dieksekusi di worker thread, bukan di event loop HTTP)
- `worker`: **satu-satunya penulis** keadaan dunia (stok, harga, kapal, ledger)
- PostgreSQL: sumber kebenaran tunggal

## Prinsip
1. **Server-authoritative**: klien tidak pernah menghitung hasil game.
2. **Satu penulis dunia**: hanya worker yang menjalankan simulasi; api hanya menulis data akun dan aturan.
3. **Inti murni**: `packages/dsl` dan `packages/econ` tanpa I/O supaya mudah dites dan deterministik.
4. **Diskret**: dunia maju per tick; tidak ada logika real-time.
5. **Satu implementasi tick**: fungsi murni `stepWorld(state, rules, config)` di `packages/econ` dipakai oleh worker (memuat state dari DB, memanggil, menyimpan hasil), simulator `sim:run`, dan sandbox API. Dilarang menduplikasi logika tick, harga, atau transaksi di tempat lain; tes kesetaraan menjaganya.

## Komponen
| Komponen | Tanggung jawab | Catatan |
|---|---|---|
| api | HTTP, auth JWT, validasi zod, rate limit | stateless, bisa direstart kapan saja |
| worker | tick loop, evaluasi aturan, terapkan aksi, update pasar | satu instance, dikunci advisory lock |
| packages/dsl | parse, validasi, evaluasi aturan | deterministik, ada batas anggaran |
| packages/econ | harga, produksi, konsumsi, biaya | integer, deterministik |
| db | PostgreSQL 16 | migrasi maju saja |
| mobile | UI Flutter | cache lokal baca-saja |

## Alur data utama
**Menyimpan aturan:** app → `PUT /v1/ships/:id/rules` → api memvalidasi dengan `packages/dsl` → simpan `rule_sets` (sumber + AST terkompilasi + versi) → worker memakai versi terbaru mulai tick berikutnya.

**Satu tick:** worker kunci → baca keadaan → produksi/konsumsi → harga → kedatangan kapal → evaluasi aturan per kapal → terapkan aksi + ledger → biaya → commit. Rinci di `09`.

**Menampilkan pasar:** app → `GET /v1/world/market/:portId` → baca langsung dari tabel pasar (snapshot tick terakhir).

## Konkurensi dan konsistensi
- Satu transaksi DB per tick; semua-atau-tidak-sama-sekali
- `tick_state.tick_no` unik; worker menolak memproses tick yang sudah ada
- API tidak pernah mengubah `ships`, `market`, atau `ledger`
- Baca dari api memakai isolasi `READ COMMITTED` pada snapshot tick yang sudah commit

## Skala (target MVP)
100 kapal, 6 pelabuhan, 4 komoditas, tick 30 detik. Satu VPS cukup. Jika kapal > 5.000, evaluasi aturan dipecah antar thread worker (di luar MVP).

## Struktur repo
Monorepo pnpm. Lihat `CLAUDE.md` untuk pohon folder.

## Observabilitas
- Log JSON terstruktur (pino) dengan `tick_no`, `ship_id`
- Metrik: durasi tick, lag tick, jumlah aksi gagal, jumlah aturan dilewati karena error
- Endpoint `/healthz` (api) dan `/healthz/worker` (usia tick terakhir)

## Keputusan terkait
Lihat `04-ADR.md`.
