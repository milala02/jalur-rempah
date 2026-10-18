# 12 — Deployment & Runbook v0.1

`[ASUMSI]` Satu VPS Linux, domain sendiri, nginx, PM2. Sesuaikan nama dan jalur dengan lingkungan nyata dan **periksa dulu layanan lain yang sudah berjalan** (port, database, nginx) agar tidak bentrok.

## Lingkungan
| Lingkungan | Tujuan | Catatan |
|---|---|---|
| lokal/dev | pengembangan | DB terpisah, tick cepat |
| staging (opsional) | uji sebelum rilis | DB dan port terpisah |
| production | pemain | cadangan wajib |

## Komponen di VPS
- PostgreSQL 16 (database `jalurrempah`, role `api_rw`, `worker_rw`, `migrator`)
- Dua proses PM2: `jr-api`, `jr-worker`
- nginx sebagai reverse proxy + TLS (Let's Encrypt)
- Firewall: hanya 80/443 dan SSH terbatas; DB hanya localhost

## Variabel lingkungan (contoh, jangan commit nilainya)
```
NODE_ENV=production
DATABASE_URL_API=postgres://api_rw:***@127.0.0.1:5432/jalurrempah
DATABASE_URL_WORKER=postgres://worker_rw:***@127.0.0.1:5432/jalurrempah
JWT_SECRET=***            # panjang, acak
TICK_SECONDS=30
WORLD_SEED=***
PORT_API=3100             # [ASUMSI] pilih port yang bebas
```

## PM2 (contoh `ecosystem.config.cjs`)
```js
module.exports = { apps: [
  { name: 'jr-api',    script: 'apps/api/dist/main.js',    instances: 1, max_memory_restart: '400M' },
  { name: 'jr-worker', script: 'apps/worker/dist/main.js', instances: 1, max_memory_restart: '600M', kill_timeout: 20000 }
]};
```
Worker: **tepat satu instance**. `kill_timeout` cukup agar tick yang berjalan sempat selesai atau rollback.

## nginx (sketsa)
```
location /v1/ { proxy_pass http://127.0.0.1:3100; proxy_set_header X-Forwarded-For $remote_addr; }
```
Aktifkan `limit_req` dasar untuk `/v1/auth/`.

## Prosedur rilis (backend)
1. CI hijau di `main`
2. `git pull` di VPS, `pnpm install --frozen-lockfile`, `pnpm build`
3. **Cadangan DB** (lihat bawah)
4. `pnpm db:migrate`
5. `pm2 reload jr-api` lalu `pm2 restart jr-worker` (graceful)
6. Pemeriksaan: `/healthz` dan `/healthz/worker`, lihat log satu-dua tick
7. Catat di `PROGRESS.md`

## Rilis APK (GitHub Actions)
- Workflow `build-apk`: Flutter build `apk --release`, tanda tangan memakai keystore dari GitHub Secrets
- Hasil: artefak/Release GitHub, diunduh dan dipasang di HP uji
- Keystore **tidak boleh** hilang atau masuk repo; cadangkan terpisah

## Cadangan dan pemulihan
- Harian: `pg_dump -Fc jalurrempah > backup_YYYYMMDD.dump`, simpan 14 hari, salin ke lokasi luar VPS
- Sebelum migrasi: cadangan manual
- **Uji restore** ke DB sementara tiap bulan; cadangan yang belum pernah diuji dianggap tidak ada
- Pemulihan: hentikan worker dan api → `pg_restore` → jalankan pemeriksaan konsistensi (`07`) → nyalakan

## Rollback
- Kode: `git checkout <tag sebelumnya>`, build, `pm2 restart`
- Skema: migrasi maju saja; rollback = pulihkan cadangan atau migrasi korektif
- Jika integritas ekonomi diragukan: `pm2 stop jr-worker` dulu

## Pemantauan
- `pm2 logs`, `pm2 monit`
- Cek berkala: usia tick terakhir `< 2 x TICK_SECONDS`
- Peringatan sederhana (skrip cron atau webhook): worker mati, tick tertinggal, disk > 80%, cadangan gagal

## Daftar periksa keamanan server
SSH hanya kunci, nonaktifkan login sandi, fail2ban, pembaruan keamanan otomatis, DB tidak terbuka ke publik, `.env` izin 600.

## Runbook insiden umum
| Gejala | Tindakan |
|---|---|
| Tick berhenti | `pm2 logs jr-worker`; cek lock DB; jika invarian gagal, **jangan** restart paksa berulang; investigasi dulu |
| Tick lambat | Cek beban DB/CPU, jumlah kapal, indeks; turunkan `TICK_SECONDS` hanya bila yakin |
| Harga aneh | Jalankan invarian dan `sim:run` dengan snapshot; cek konfigurasi ekonomi |
| Disk penuh | Pangkas `action_log`/`market_history`, putar log |
| Pemain melaporkan koin hilang | Telusuri `ledger` pemain; koreksi lewat entri kompensasi |
