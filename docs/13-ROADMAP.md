# 13 — Roadmap & Pemecahan Tugas v0.1

Tiap milestone punya **gerbang lulus** terukur. Jangan mulai milestone berikut sebelum gerbang lulus. Satu tugas = satu sesi AI.

## M0 — Fondasi repo
- [ ] Monorepo pnpm, TypeScript strict, ESLint/Prettier, Vitest
- [ ] CI GitHub Actions (lint, typecheck, test)
- [ ] Koneksi DB, runner migrasi, migrasi 0001 (skema `07`)
- [ ] Seed dunia dari `packages/shared`
- **Gerbang:** CI hijau; `pnpm db:migrate` dari DB kosong sukses; tes skema lulus

## M1 — Ekonomi dan dunia tanpa pemain
- [ ] `packages/econ`: `hitungHarga`, produksi/konsumsi (tes properti dulu)
- [ ] Eksekusi transaksi dengan slippage dan biaya
- [ ] Simulator `sim:run` dengan bot sederhana
- [ ] Tuning parameter awal (`06`)
- **Gerbang:** simulasi 50 bot x 10.000 tick lulus semua invarian; harga hidup dan terbatas; catat hasil di PROGRESS

## M2 — Akun, kapal, ledger
- [ ] Auth (daftar, login, refresh, logout) + tes otorisasi
- [ ] Pembuatan pemain + kapal awal + ledger starter (satu transaksi)
- [ ] Endpoint baca: `/me`, `/world`, `/world/market`, `/ships`
- [ ] Skrip pemeriksaan konsistensi (`07`)
- **Gerbang:** tes integrasi hijau; konsistensi ledger 0 pelanggaran

## M3 — Bahasa Aturan
- [ ] Lexer + tes
- [ ] Parser + galat berlokasi + golden test
- [ ] Validator statis (tipe, nama, batas)
- [ ] Evaluator + anggaran + galat runtime
- [ ] Fuzz + adversarial + determinisme
- **Gerbang:** semua tes wajib di `05` lulus; fuzz 1 juta input tanpa crash/hang

## M4 — Tick loop dan integrasi aturan
- [ ] Worker: penjadwal, advisory lock, pemulihan restart
- [ ] Tick: urutan `09` lengkap, aksi nyata ke DB, log aksi
- [ ] `PUT rules`, `validate`, `simulate` (sandbox)
- [ ] Invarian cepat dan metrik
- **Gerbang:** tes kill -9 lulus; 100 kapal bot tick lag p95 < 20%; tes sandbox tidak menulis ke DB

## M5 — Klien Flutter dan APK
- [ ] Login/daftar, penyimpanan token aman
- [ ] Peta/daftar pelabuhan, layar pasar, grafik harga
- [ ] Editor aturan (validasi real-time, templat)
- [ ] Layar kapal dan log, peringkat
- [ ] Workflow `build-apk` di GitHub Actions
- **Gerbang:** APK terpasang di HP uji; pemain baru menulis aturan valid pertama < 3 menit

## M6 — Pengerasan dan beta tertutup
- [ ] Rate limit, pemantauan, peringatan
- [ ] Cadangan harian + uji restore
- [ ] Tes muat (k6), pass keseimbangan ekonomi
- [ ] Tutorial awal dan templat aturan
- [ ] Beta 10-50 pemain
- **Gerbang:** semua kriteria MVP di `02` terpenuhi

## Setelah MVP (urutan usulan)
1. Evaluasi data beta (ekonomi, retensi)
2. Kabut informasi (ubah ADR-008)
3. Banyak kapal
4. Fitur sosial ringan (kontrak, guild)
5. Event dan musim

## Aturan pergantian scope
Fitur baru butuh: tujuan, dampak ekonomi, perubahan dokumen, tes. Catat di ADR bila mengubah arsitektur.
