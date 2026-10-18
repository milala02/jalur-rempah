# 08 — API Contract v0.1

Base URL: `https://<domain>/v1`. JSON, UTF-8. Waktu ISO 8601 UTC. Autentikasi: `Authorization: Bearer <access_token>` kecuali endpoint publik.

## Format error (seragam)
```json
{ "error": { "code": "RULE_INVALID", "message": "Pesan terbaca manusia", "details": [] } }
```
Kode umum: `VALIDATION_ERROR` 400, `UNAUTHENTICATED` 401, `FORBIDDEN` 403, `NOT_FOUND` 404, `CONFLICT` 409, `RATE_LIMITED` 429, `INTERNAL` 500.

## Autentikasi
| Metode | Path | Keterangan |
|---|---|---|
| POST | `/auth/register` | `{email, password, display_name}` → buat akun, kapal awal, ledger starter. 201 |
| POST | `/auth/login` | `{email, password}` → `{access_token, refresh_token, expires_in}` |
| POST | `/auth/refresh` | `{refresh_token}` → pasangan token baru (rotasi, token lama dicabut) |
| POST | `/auth/logout` | cabut refresh token |

Access token JWT berumur 15 menit; refresh token 30 hari, disimpan hash-nya.

## Pemain
| Metode | Path | Hasil |
|---|---|---|
| GET | `/me` | `{id, display_name, coins, net_worth, rank}` |
| GET | `/me/ledger?cursor=&limit=` | riwayat koin (paginasi kursor) |

## Dunia (baca saja)
| Metode | Path | Hasil |
|---|---|---|
| GET | `/world` | `{tick_no, tick_seconds, ports[], commodities[], routes[]}` |
| GET | `/world/market/:portCode` | `[{commodity, stock, target, price}]` + `tick_no` |
| GET | `/world/price-history?port=&commodity=&ticks=` | deret harga (maks 500 titik) |
| GET | `/leaderboard?limit=50` | `[{rank, display_name, net_worth}]` |

## Kapal dan aturan
| Metode | Path | Keterangan |
|---|---|---|
| GET | `/ships` | kapal milik pemain |
| GET | `/ships/:id` | status, posisi, muatan, ETA |
| GET | `/ships/:id/rules` | versi aktif: `{version, source}` |
| PUT | `/ships/:id/rules` | `{source}` → validasi + simpan versi baru; 422 `RULE_INVALID` + daftar galat jika gagal |
| GET | `/ships/:id/rules/versions` | riwayat versi (maks 20) |
| POST | `/rules/validate` | `{source}` → `{valid, errors[]}` tanpa menyimpan |
| POST | `/ships/:id/rules/simulate` | `{source, ticks<=300}` → hasil simulasi sandbox (lihat bawah) |
| GET | `/ships/:id/log?cursor=&limit=` | log aksi dengan alasan |

### Galat validasi aturan
```json
{ "valid": false, "errors": [ { "line": 3, "column": 7, "code": "UNKNOWN_FUNCTION", "message": "Fungsi 'hargaa' tidak dikenal. Maksud Anda 'harga'?" } ] }
```

### Simulasi sandbox
- Memakai **snapshot** pasar saat ini dan **klon** kapal pemain, dijalankan di proses api (modul murni `packages/dsl` + `packages/econ`), **tidak menulis** ke dunia nyata
- Tanpa pemain lain bergerak (pasar hanya bereaksi pada kapal ini) → hasil adalah perkiraan, dikatakan jelas di respons
- Respons: `{ticks, final_coins_delta, trades, actions_summary[], log_sample[]}`
- Batas: 300 tick, timeout 2 detik, 1 simulasi per pemain per 5 detik

## Real-time (Fase 2)
`GET /v1/stream` (WebSocket/SSE) untuk tick baru dan peristiwa kapal. MVP memakai polling tiap tick (30 detik) dengan `If-None-Match`.

## Konvensi
- Paginasi kursor: `?cursor=<opaque>&limit=<=100`, respons `{items, next_cursor}`
- Idempotensi: endpoint `PUT` idempoten; `POST /auth/register` menolak duplikat dengan 409
- Header `X-Tick: <tick_no>` pada semua respons dunia
- Versi: path `/v1`; perubahan yang merusak = `/v2`

## Rate limit (awal)
| Kelompok | Batas |
|---|---|
| Umum | 60 req/menit/pemain |
| `/auth/*` | 10 req/menit/IP |
| `PUT rules` | 10/menit/pemain |
| `simulate` | 1/5 detik/pemain |

## Keamanan
HTTPS wajib; validasi semua input dengan zod; tidak membocorkan apakah email terdaftar saat login gagal; semua endpoint kapal memeriksa kepemilikan.

## Kontrak dan tes
Skema OpenAPI dihasilkan dari skema zod dan disimpan di `docs/openapi.json`. Tes kontrak memastikan respons sesuai skema.
