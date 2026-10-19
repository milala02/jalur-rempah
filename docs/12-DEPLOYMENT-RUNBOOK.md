# 12 — Deployment & Runbook v0.2

`[ASUMSI & PERLU VERIFIKASI PEMILIK]` Satu VPS Linux, domain sendiri, nginx, PM2. Sesuaikan seluruh nama, port, dan jalur dengan lingkungan nyata dan **periksa dulu layanan lain yang sudah berjalan** (`ss -tulpn`, `psql -l`, `nginx -T`, `pm2 list`) agar tidak bentrok.

## Lingkungan
| Lingkungan | Tujuan | Catatan |
|---|---|---|
| lokal/dev | pengembangan | DB terpisah, tick cepat |
| staging (opsional) | uji sebelum rilis | DB dan port terpisah `[PERLU VERIFIKASI PEMILIK]` |
| production | pemain | cadangan wajib |

## Komponen di VPS `[PERLU VERIFIKASI PEMILIK]`
- PostgreSQL 16 (database `jalurrempah` `[PERLU VERIFIKASI PEMILIK]`, role `api_rw`, `worker_rw`, `migrator`)
- Dua proses PM2: `jr-api`, `jr-worker`
- nginx sebagai reverse proxy + TLS (Let's Encrypt) `[PERLU VERIFIKASI PEMILIK]`
- Firewall: hanya 80/443 dan SSH terbatas; DB hanya localhost (`127.0.0.1`)

## Variabel lingkungan (contoh, jangan commit nilainya)
```ini
NODE_ENV=production
DATABASE_URL_API=postgres://api_rw:***@127.0.0.1:5432/jalurrempah       # [PERLU VERIFIKASI PEMILIK: port & nama DB]
DATABASE_URL_WORKER=postgres://worker_rw:***@127.0.0.1:5432/jalurrempah # [PERLU VERIFIKASI PEMILIK: port & nama DB]
JWT_SECRET=***            # panjang minimal 32 byte acak kriptografis
TICK_SECONDS=30           # [KEPUTUSAN PEMILIK]
WORLD_SEED=***
PORT_API=3100             # [PERLU VERIFIKASI PEMILIK: pastikan port bebas dengan ss -tulpn]
```

## PM2 (contoh `ecosystem.config.cjs`)
```js
module.exports = {
  apps: [
    {
      name: 'jr-api',
      script: 'apps/api/dist/main.js',
      exec_mode: 'cluster', // diperlukan agar `pm2 reload jr-api` berjalan zero-downtime
      instances: 1,         // [PERLU VERIFIKASI PEMILIK: 1 atau 2 sesuai vCPU VPS]
      wait_ready: true,
      listen_timeout: 10000,
      kill_timeout: 10000,
      max_memory_restart: '400M',
    },
    {
      name: 'jr-worker',
      script: 'apps/worker/dist/main.js',
      exec_mode: 'fork',    // WAJIB fork dengan tepat 1 instance (writer tunggal)
      instances: 1,
      max_memory_restart: '600M',
      kill_timeout: 20000,
    },
  ],
};
```
- **Worker:** **Wajib tepat satu instance (`exec_mode: 'fork'`, `instances: 1`)** ditambah `pg_try_advisory_xact_lock` di DB. `kill_timeout: 20000` memberi waktu agar transaksi tick yang sedang berjalan selesai atau rollback dengan bersih saat `SIGTERM`.
- **API:** Jika menggunakan `exec_mode: 'fork'` (bukan `cluster`), gunakan `pm2 restart jr-api` karena `pm2 reload` hanya berlaku pada mode `cluster`. Pastikan `apps/api` menangani sinyal `SIGTERM`/`SIGINT` dengan memanggil `fastify.close()`.

## nginx (sketsa) `[PERLU VERIFIKASI PEMILIK]`
```nginx
# [PERLU VERIFIKASI PEMILIK: lokasi blok limit_req_zone di http {} dan port upstream]
limit_req_zone $binary_remote_addr zone=jr_auth:10m rate=10r/m;

location /v1/ {
    client_max_body_size 64k;
    proxy_read_timeout 15s;
    proxy_pass http://127.0.0.1:3100; # [PERLU VERIFIKASI PEMILIK: sesuaikan dengan PORT_API]
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```
- **Penting (`trustProxy`):** `apps/api` (Fastify) wajib dikonfigurasi dengan `trustProxy: '127.0.0.1'` agar membaca IP klien dari `X-Real-IP`/`X-Forwarded-For` yang disetel nginx lokal, bukan menganggap semua request berasal dari `127.0.0.1`.
- **Rate Limit:** Batas laju `/v1/auth/*` dipasang di nginx (`jr_auth`) DAN di lapis aplikasi (`IP + email`), sedangkan batas laju berbasis pemain (`/v1/simulate` `10/menit/player_id`, `PUT /v1/ships/:id/rules` `30/menit/player_id`) ditegakkan di dalam `apps/api` setelah verifikasi JWT (`docs/08`).

## Prosedur rilis (backend)
1. CI hijau di `main`
2. `git pull` di VPS, `pnpm install --frozen-lockfile`, `pnpm build`
3. **Cadangan DB** (lihat bawah)
4. `pnpm db:migrate`
5. `pm2 reload jr-api` (atau `pm2 restart jr-api` jika mode `fork`) lalu `pm2 restart jr-worker` (graceful)
6. Pemeriksaan: `/v1/healthz` dan `/v1/healthz/worker`, lihat log satu-dua tick
7. Catat di `PROGRESS.md`

## Rilis APK (GitHub Actions)
- Workflow `build-apk`: membangun APK rilis dan menandatangani memakai keystore dari GitHub Secrets
- Hasil: artefak/Release GitHub, diunduh dan dipasang di HP uji
- Keystore **tidak boleh** hilang atau masuk repo; cadangkan terpisah

## Cadangan dan pemulihan
- **Harian (dengan proteksi izin berkas & rotasi otomatis):**
  ```bash
  umask 077
  mkdir -p /var/backups/jalurrempah && chmod 700 /var/backups/jalurrempah
  pg_dump -Fc jalurrempah > /var/backups/jalurrempah/backup_$(date +%Y%m%d).dump
  test -s /var/backups/jalurrempah/backup_$(date +%Y%m%d).dump
  find /var/backups/jalurrempah -name "backup_*.dump" -mtime +14 -delete
  ```
  Salin berkas cadangan ke lokasi luar VPS `[PERLU VERIFIKASI PEMILIK: target offsite storage]`.
- Sebelum migrasi: cadangan manual wajib dilakukan dan diverifikasi ukurannya `> 0`.
- **Uji restore** ke DB sementara tiap bulan; cadangan yang belum pernah diuji dianggap tidak ada.
- Pemulihan: hentikan `jr-worker` dan `jr-api` → `pg_restore` → jalankan pemeriksaan konsistensi (`docs/07`, termasuk view `economy_money_supply_audit`) → nyalakan kembali.

## Rollback
- Kode: `git checkout <tag sebelumnya>`, build, `pm2 restart jr-api jr-worker`
- Skema: migrasi maju saja (`0001`, `0002`, `0003`); rollback = pulihkan cadangan atau tulis migrasi korektif baru
- Jika integritas ekonomi diragukan: `pm2 stop jr-worker` lebih dulu

## Pemantauan
- `pm2 logs`, `pm2 monit`
- Cek berkala: usia tick terakhir `< 2 x TICK_SECONDS` (`/v1/healthz/worker` mengembalikan `503` jika tertinggal)
- Peringatan sederhana (skrip cron atau webhook): worker mati, tick tertinggal, disk > 80%, cadangan gagal

## Daftar periksa keamanan server `[PERLU VERIFIKASI PEMILIK]`
SSH hanya kunci, nonaktifkan login sandi, fail2ban, pembaruan keamanan otomatis, DB tidak terbuka ke publik (`listen_addresses = '127.0.0.1'`), `.env` izin `0600`.

## Runbook insiden umum
| Gejala | Tindakan |
|---|---|
| Tick berhenti | `pm2 logs jr-worker`; cek lock DB; jika invarian gagal, **jangan** restart paksa berulang; investigasi dulu |
| Tick lambat | Cek beban DB/CPU, jumlah kapal, indeks (`idx_ledger_player_non_upkeep`); turunkan `TICK_SECONDS` hanya bila yakin |
| Harga aneh / kas habis | Jalankan kueri `economy_money_supply_audit` (`docs/07`) dan `pnpm sim:run`; cek konfigurasi ekonomi |
| Disk penuh | Pangkas `action_log`/`market_history`, pastikan flush `unflushed_upkeep` aktif, putar log PM2/nginx |
| Pemain melaporkan koin hilang | Telusuri `ledger` dan `unflushed_upkeep` pemain; koreksi lewat entri kompensasi append-only |
