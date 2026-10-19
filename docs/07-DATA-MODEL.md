# 07 — Data Model v0.3

PostgreSQL 16. Semua uang/jumlah `BIGINT`. Waktu `TIMESTAMPTZ`. ID internal `BIGINT GENERATED ALWAYS AS IDENTITY`; ID publik (jika perlu) UUID.

## Skema ringkas (Migrasi 0001 + 0002 + 0003)
```sql
-- Referensi dunia (di-seed dari packages/shared)
CREATE TABLE commodities (
  id          SMALLINT PRIMARY KEY,
  code        TEXT UNIQUE NOT NULL,        -- 'pala'
  base_price  BIGINT NOT NULL CHECK (base_price > 0)
);

CREATE TABLE ports (
  id               SMALLINT PRIMARY KEY,
  code             TEXT UNIQUE NOT NULL,   -- 'banda'
  name             TEXT NOT NULL,
  treasury         BIGINT NOT NULL DEFAULT 0 CHECK (treasury >= 0),
  initial_treasury BIGINT NOT NULL DEFAULT 0 CHECK (initial_treasury >= 0)
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

-- Akun dan pemain (diperluas di Migrasi 0003 untuk agregasi blok upkeep A5 / ADR-011)
CREATE TABLE players (
  id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email                  CITEXT UNIQUE NOT NULL,
  password_hash          TEXT NOT NULL,             -- argon2id
  display_name           TEXT UNIQUE NOT NULL,
  coins                  BIGINT NOT NULL CHECK (coins >= 0),
  unflushed_upkeep       BIGINT NOT NULL DEFAULT 0 CHECK (unflushed_upkeep >= 0),
  cumulative_upkeep_paid BIGINT NOT NULL DEFAULT 0 CHECK (cumulative_upkeep_paid >= 0),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
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

-- Ledger append-only pemain
CREATE TABLE ledger (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  tick_no    BIGINT,
  delta      BIGINT NOT NULL,              -- + masuk, - keluar
  reason     TEXT NOT NULL,                -- 'starter','buy'/'trade_buy','sell'/'trade_sell','upkeep','rescue'
  ref_ship   BIGINT REFERENCES ships(id),
  meta       JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON ledger (player_id, id DESC);
-- Indeks parsial untuk mempercepat query /me/ledger di luar baris perawatan rutin (Migrasi 0003 / A5)
CREATE INDEX idx_ledger_player_non_upkeep ON ledger (player_id, id DESC) WHERE reason <> 'upkeep';

-- Pencatat append-only sumber dan pengurang kas pelabuhan (Migrasi 0003 / ADR-010)
CREATE TABLE economy_sources_sinks (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tick_no     BIGINT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('source', 'sink')),
  reason      TEXT NOT NULL CHECK (reason IN ('port_income', 'rescue', 'port_producer_payout')),
  port_id     SMALLINT REFERENCES ports(id),
  ref_player  BIGINT REFERENCES players(id),
  amount      BIGINT NOT NULL CHECK (amount > 0),
  meta        JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_economy_sources_sinks_kind_tick ON economy_sources_sinks (kind, tick_no DESC);

-- Log aksi (penjelasan untuk pemain), di-prune
CREATE TABLE action_log (
  id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ship_id   BIGINT NOT NULL REFERENCES ships(id),
  tick_no   BIGINT NOT NULL,
  rule_name TEXT,
  action    TEXT NOT NULL,                 -- 'beli(pala,12)'
  result    TEXT NOT NULL,                 -- 'ok','gagal','menunggu','berlayar'
  detail    TEXT,                          -- kode kegagalan (GROUNDED, PORT_TREASURY_LOW, dst.) + alasan terbaca manusia
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

## Aturan data & optimasi volume ledger (ADR-010, ADR-011)
- `ledger` dan `economy_sources_sinks` tidak pernah di-UPDATE, DELETE, atau TRUNCATE (dijaga trigger per-baris dan per-statement `prevent_ledger_update_or_delete` serta `prevent_ledger_truncate`).
- **Agregasi Blok Perawatan Kapal (`UPKEEP_LEDGER_BATCH_TICKS = 120` tick / 1 jam)**:
  - Untuk mencegah pembengkakan `43,2 juta` baris/bulan pada 500 kapal (`docs/analisis/A5-volume-ledger.md`), pemotongan perawatan per tick dapat diakumulasikan ke kolom `players.unflushed_upkeep` (sambil mengurangi `players.coins` dan menambah `players.cumulative_upkeep_paid`).
  - Setiap batas blok `120` tick — atau segera sebelum mencatat transaksi `buy`/`sell`/`rescue` pemain tersebut dan sebelum snapshot audit akhir — nilai `unflushed_upkeep > 0` di-flush menjadi **satu baris ringkasan** di `ledger` (`reason = 'upkeep', delta = -unflushed_upkeep, meta = '{"from_tick": t0, "to_tick": t1, "ticks_count": k}'`) lalu `unflushed_upkeep` di-reset menjadi `0`.
  - Dengan desain ini, persamaan `players.coins + players.unflushed_upkeep == SUM(ledger.delta)` berlaku eksak di setiap tick, dan `players.coins == SUM(ledger.delta)` berlaku eksak setiap selesai flush atau transaksi.
- `ports.treasury` diubah worker dalam transaksi yang sama dengan pembelian/penjualan pemain atau kliring domestik pelabuhan (`economy_sources_sinks`).
- Kecuali pendaftaran: `api` membuat pemain + kapal awal + ledger `starter` dalam satu transaksi.
- `ship_cargo` memakai upsert; baris `qty = 0` boleh dibiarkan.
- `action_log` dan `market_history` di-prune (simpan 7 hari / 2.000 tick terakhir).

## Role database
- `api_rw`: baca semua; tulis `players` (akun), `rule_sets`, `refresh_tokens`
- `worker_rw`: tulis `market`, `ports.treasury`, `economy_sources_sinks`, `ships`, `ship_cargo`, `ledger`, `action_log`, `tick_state`, `market_history`, `players.coins`, `players.unflushed_upkeep`, `players.cumulative_upkeep_paid`
- Migrasi dijalankan role terpisah (`migrator`)

## Migrasi
`db/migrations/NNNN_nama.sql`, maju saja:
- `0001_init.sql` (skema dasar M0 — tidak boleh diubah)
- `0002_port_treasury_and_sinks.sql` (kas pelabuhan & trigger truncate — tidak boleh diubah)
- `0003_port_income_and_ledger_compaction.sql` (`economy_sources_sinks`, `unflushed_upkeep`, `cumulative_upkeep_paid`, `idx_ledger_player_non_upkeep`, dan view `economy_money_supply_audit` dengan `cumulative_source`)

## Pemeriksaan konsistensi (job terjadwal + tes otomatis di `apps/api/test/schema.test.ts`)
```sql
-- 1a. Saldo pemain = jumlah ledger (saat unflushed_upkeep telah di-flush = 0)
SELECT p.id FROM players p
LEFT JOIN (SELECT player_id, SUM(delta) s FROM ledger GROUP BY 1) l ON l.player_id = p.id
WHERE p.coins <> COALESCE(l.s, 0);

-- 1b. Saldo pemain + unflushed_upkeep = jumlah ledger (berlaku eksak di setiap tick termasuk tengah blok)
SELECT p.id FROM players p
LEFT JOIN (SELECT player_id, SUM(delta) s FROM ledger GROUP BY 1) l ON l.player_id = p.id
WHERE (p.coins + p.unflushed_upkeep) <> COALESCE(l.s, 0);

-- 2. Muatan <= kapasitas
SELECT s.id FROM ships s JOIN ship_cargo c ON c.ship_id = s.id
GROUP BY s.id, s.capacity HAVING SUM(c.qty) > s.capacity;

-- 3. Konservasi Uang Global (ADR-009 & ADR-010, melalui view economy_money_supply_audit):
-- total_player_coins + total_port_treasury + cumulative_upkeep_sink == total_initial_money + cumulative_source
SELECT *
FROM public.economy_money_supply_audit
WHERE (total_player_coins + total_port_treasury + cumulative_upkeep_sink)
   <> (total_initial_money + cumulative_source);
```
Seluruh kueri di atas harus mengembalikan `0` baris.
