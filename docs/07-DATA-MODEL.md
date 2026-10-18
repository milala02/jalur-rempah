# 07 — Data Model v0.1

PostgreSQL 16. Semua uang/jumlah `BIGINT`. Waktu `TIMESTAMPTZ`. ID internal `BIGINT GENERATED ALWAYS AS IDENTITY`; ID publik (jika perlu) UUID.

## Skema ringkas
```sql
-- Referensi dunia (di-seed dari packages/shared)
CREATE TABLE commodities (
  id          SMALLINT PRIMARY KEY,
  code        TEXT UNIQUE NOT NULL,        -- 'pala'
  base_price  BIGINT NOT NULL CHECK (base_price > 0)
);

CREATE TABLE ports (
  id    SMALLINT PRIMARY KEY,
  code  TEXT UNIQUE NOT NULL,              -- 'banda'
  name  TEXT NOT NULL
);

CREATE TABLE routes (
  from_port SMALLINT REFERENCES ports(id),
  to_port   SMALLINT REFERENCES ports(id),
  ticks     INT NOT NULL CHECK (ticks > 0),
  PRIMARY KEY (from_port, to_port)
);  -- simpan dua arah

-- Pasar: satu baris per (pelabuhan, komoditas)
CREATE TABLE market (
  port_id      SMALLINT REFERENCES ports(id),
  commodity_id SMALLINT REFERENCES commodities(id),
  stock        BIGINT NOT NULL CHECK (stock >= 0),
  target       BIGINT NOT NULL CHECK (target > 0),
  production   BIGINT NOT NULL CHECK (production >= 0),
  consumption  BIGINT NOT NULL CHECK (consumption >= 0),
  capacity     BIGINT NOT NULL CHECK (capacity > 0),
  price        BIGINT NOT NULL CHECK (price >= 1),
  PRIMARY KEY (port_id, commodity_id),
  CHECK (stock <= capacity)
);

CREATE TABLE market_history (            -- opsional, di-prune
  tick_no      BIGINT,
  port_id      SMALLINT,
  commodity_id SMALLINT,
  price        BIGINT,
  stock        BIGINT,
  PRIMARY KEY (tick_no, port_id, commodity_id)
);

-- Akun dan pemain
CREATE TABLE players (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         CITEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,             -- argon2id
  display_name  TEXT UNIQUE NOT NULL,
  coins         BIGINT NOT NULL CHECK (coins >= 0),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ships (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id   BIGINT NOT NULL REFERENCES players(id),
  name        TEXT NOT NULL,
  capacity    INT NOT NULL CHECK (capacity > 0),
  status      TEXT NOT NULL CHECK (status IN ('docked','sailing','grounded')),
  port_id     SMALLINT REFERENCES ports(id),     -- jika docked/grounded
  dest_port   SMALLINT REFERENCES ports(id),     -- jika sailing
  arrive_tick BIGINT,                            -- jika sailing
  UNIQUE (player_id, name)
);

CREATE TABLE ship_cargo (
  ship_id      BIGINT REFERENCES ships(id) ON DELETE CASCADE,
  commodity_id SMALLINT REFERENCES commodities(id),
  qty          BIGINT NOT NULL CHECK (qty >= 0),
  PRIMARY KEY (ship_id, commodity_id)
);

CREATE TABLE rule_sets (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ship_id     BIGINT NOT NULL REFERENCES ships(id),
  version     INT NOT NULL,
  source      TEXT NOT NULL,
  compiled    JSONB NOT NULL,              -- AST tervalidasi
  ast_version INT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ship_id, version)
);
-- Versi aktif = version tertinggi per ship_id

-- Ledger append-only
CREATE TABLE ledger (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  tick_no    BIGINT,
  delta      BIGINT NOT NULL,              -- + masuk, - keluar
  reason     TEXT NOT NULL,                -- 'starter','buy','sell','port_fee','upkeep'
  ref_ship   BIGINT REFERENCES ships(id),
  meta       JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON ledger (player_id, id DESC);

-- Log aksi (penjelasan untuk pemain), di-prune
CREATE TABLE action_log (
  id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ship_id   BIGINT NOT NULL REFERENCES ships(id),
  tick_no   BIGINT NOT NULL,
  rule_name TEXT,
  action    TEXT NOT NULL,                 -- 'beli(pala,12)'
  result    TEXT NOT NULL,                 -- 'ok','gagal','dilewati','menunggu','berlayar'
  detail    TEXT,                          -- alasan terbaca manusia
  UNIQUE (ship_id, tick_no)
);
CREATE INDEX ON action_log (ship_id, tick_no DESC);

CREATE TABLE tick_state (
  tick_no     BIGINT PRIMARY KEY,
  started_at  TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ NOT NULL,
  duration_ms INT NOT NULL,
  state_hash  TEXT                         -- untuk tes determinisme
);

CREATE TABLE refresh_tokens (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked    BOOLEAN NOT NULL DEFAULT false
);
```

## Aturan data
- `ledger` tidak pernah di-UPDATE atau DELETE (dijaga trigger atau izin role)
- `players.coins` hanya diubah worker dalam transaksi yang sama dengan insert `ledger`
- Kecuali pendaftaran: api membuat pemain + kapal awal + ledger `starter` dalam satu transaksi
- `ship_cargo` memakai upsert; baris qty=0 boleh dibiarkan
- `action_log` dan `market_history` di-prune (simpan 7 hari / 2.000 tick terakhir)

## Role database
- `api_rw`: baca semua; tulis `players` (akun), `rule_sets`, `refresh_tokens`
- `worker_rw`: tulis `market`, `ships`, `ship_cargo`, `ledger`, `action_log`, `tick_state`, `market_history`, `players.coins`
- Migrasi dijalankan role terpisah

## Migrasi
`db/migrations/NNNN_nama.sql`, maju saja. Perubahan destruktif butuh dua langkah (tambah dulu, hapus di rilis berikut).

## Pemeriksaan konsistensi (job terjadwal + tes)
```sql
-- Saldo = jumlah ledger
SELECT p.id FROM players p
LEFT JOIN (SELECT player_id, SUM(delta) s FROM ledger GROUP BY 1) l ON l.player_id = p.id
WHERE p.coins <> COALESCE(l.s, 0);

-- Muatan <= kapasitas
SELECT s.id FROM ships s JOIN ship_cargo c ON c.ship_id = s.id
GROUP BY s.id, s.capacity HAVING SUM(c.qty) > s.capacity;
```
Keduanya harus mengembalikan 0 baris.
