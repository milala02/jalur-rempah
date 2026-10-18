# Jalur Rempah — Paket Dokumen

Judul kerja: **Jalur Rempah**. Ganti kapan saja.

## Daftar dokumen
| No | File | Isi | Status |
|---|---|---|---|
| 01 | GDD | Konsep, loop permainan, non-goals | Draf v0.1 |
| 02 | PRD-MVP | Scope MVP, kriteria selesai | Draf v0.1 |
| 03 | ARSITEKTUR | Komponen, alur data, deployment | Draf v0.1 |
| 04 | ADR | Catatan keputusan arsitektur | Hidup |
| 05 | SPEC-BAHASA-ATURAN | Tata bahasa, tipe, fungsi, batas | Draf v0.1 |
| 06 | SPEC-EKONOMI | Rumus harga, sumber dan pengurang uang | Draf v0.1, angka perlu tuning |
| 07 | DATA-MODEL | Skema PostgreSQL | Draf v0.1 |
| 08 | API-CONTRACT | Endpoint REST | Draf v0.1 |
| 09 | SPEC-TICK-LOOP | Urutan simulasi per tick | Draf v0.1 |
| 10 | TESTING | Strategi tes dan simulasi | Draf v0.1 |
| 11 | THREAT-MODEL | Ancaman dan mitigasi | Draf v0.1 |
| 12 | DEPLOYMENT-RUNBOOK | Deploy, backup, rollback | Draf v0.1 |
| 13 | ROADMAP | Milestone dan kriteria lulus | Draf v0.1 |
| - | PROGRESS | Log kemajuan dan keputusan | Hidup |
| - | ../CLAUDE.md | Aturan untuk AI agent | Hidup |

## Cara memakai bersama AI
1. Taruh `CLAUDE.md` di root repo, folder `docs/` di repo yang sama.
2. Mulai sesi dengan: "Baca CLAUDE.md, docs/PROGRESS.md, dan tugas M? di docs/13-ROADMAP.md. Tulis rencana dulu."
3. Sebutkan dokumen spesifik yang relevan (misal untuk tugas parser: `docs/05`).
4. Minta tes lebih dulu untuk DSL, ekonomi, dan ledger.
5. Akhiri sesi dengan memperbarui `PROGRESS.md`.

## Prinsip
- Dokumen adalah sumber kebenaran, bukan percakapan.
- Angka di dokumen ekonomi adalah **parameter tuning**, bukan hukum. Ubah lewat konfigurasi, catat di PROGRESS.
- Bagian bertanda `[ASUMSI]` perlu kamu putuskan atau konfirmasi.
