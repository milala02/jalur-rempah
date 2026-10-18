-- Migrasi 0001: Skema Awal Dunia Jalur Rempah
-- Berdasarkan docs/07-DATA-MODEL.md

CREATE EXTENSION IF NOT EXISTS citext;

-- Referensi dunia (di-seed dari packages/shared)
CREATE TABLE IF NOT EXISTS commodities (
  id          SMALLINT PRIMARY KEY,
  code        TEXT UNIQUE NOT NULL,        -- 'pala', 'cengkeh', 'garam', 'kain'
  base_price  BIGINT NOT NULL CHECK (base_price > 0)
);

CREATE TABLE IF NOT EXISTS ports (
  id    SMALLINT PRIMARY KEY,
  code  TEXT UNIQUE NOT NULL,              -- 'banda', 'ternate', dst.
  name  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS routes (
  from_port SMALLINT REFERENCES ports(id),
  to_port   SMALLINT REFERENCES ports(id),
  ticks     INT NOT NULL CHECK (ticks > 0),
  PRIMARY KEY (from_port, to_port)
);

-- Pasar: satu baris per (pelabuhan, komoditas)
CREATE TABLE IF NOT EXISTS market (
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

CREATE TABLE IF NOT EXISTS market_history (
  tick_no      BIGINT,
  port_id      SMALLINT,
  commodity_id SMALLINT,
  price        BIGINT,
  stock        BIGINT,
  PRIMARY KEY (tick_no, port_id, commodity_id)
);

-- Akun dan pemain
CREATE TABLE IF NOT EXISTS players (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         CITEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,             -- argon2id
  display_name  TEXT UNIQUE NOT NULL,
  coins         BIGINT NOT NULL CHECK (coins >= 0),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ships (
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

CREATE TABLE IF NOT EXISTS ship_cargo (
  ship_id      BIGINT REFERENCES ships(id) ON DELETE CASCADE,
  commodity_id SMALLINT REFERENCES commodities(id),
  qty          BIGINT NOT NULL CHECK (qty >= 0),
  PRIMARY KEY (ship_id, commodity_id)
);

CREATE TABLE IF NOT EXISTS rule_sets (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ship_id     BIGINT NOT NULL REFERENCES ships(id),
  version     INT NOT NULL,
  source      TEXT NOT NULL,
  compiled    JSONB NOT NULL,              -- AST tervalidasi
  ast_version INT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ship_id, version)
);

-- Ledger append-only
CREATE TABLE IF NOT EXISTS ledger (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  tick_no    BIGINT,
  delta      BIGINT NOT NULL,              -- + masuk, - keluar
  reason     TEXT NOT NULL,                -- 'starter','buy','sell','port_fee','upkeep'
  ref_ship   BIGINT REFERENCES ships(id),
  meta       JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_player_id_id_desc ON ledger (player_id, id DESC);

-- Log aksi (penjelasan untuk pemain), di-prune
CREATE TABLE IF NOT EXISTS action_log (
  id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ship_id   BIGINT NOT NULL REFERENCES ships(id),
  tick_no   BIGINT NOT NULL,
  rule_name TEXT,
  action    TEXT NOT NULL,                 -- 'beli(pala,12)'
  result    TEXT NOT NULL,                 -- 'ok','gagal','dilewati','menunggu','berlayar'
  detail    TEXT,                          -- alasan terbaca manusia
  UNIQUE (ship_id, tick_no)
);
CREATE INDEX IF NOT EXISTS idx_action_log_ship_id_tick_desc ON action_log (ship_id, tick_no DESC);

CREATE TABLE IF NOT EXISTS tick_state (
  tick_no     BIGINT PRIMARY KEY,
  started_at  TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ NOT NULL,
  duration_ms INT NOT NULL,
  state_hash  TEXT                         -- untuk tes determinisme
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked    BOOLEAN NOT NULL DEFAULT false
);

-- Pengamanan append-only pada tabel ledger:
-- 1. Trigger per-baris untuk mencegah UPDATE dan DELETE
CREATE OR REPLACE FUNCTION prevent_ledger_update_or_delete()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Tabel ledger bersifat append-only: UPDATE atau DELETE dilarang.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ledger_prevent_update_delete ON ledger;
CREATE TRIGGER trg_ledger_prevent_update_delete
BEFORE UPDATE OR DELETE ON ledger
FOR EACH ROW
EXECUTE FUNCTION prevent_ledger_update_or_delete();

-- 2. Trigger per-statement untuk mencegah TRUNCATE
CREATE OR REPLACE FUNCTION prevent_ledger_truncate()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Tabel ledger bersifat append-only: TRUNCATE dilarang.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ledger_prevent_truncate ON ledger;
CREATE TRIGGER trg_ledger_prevent_truncate
BEFORE TRUNCATE ON ledger
FOR EACH STATEMENT
EXECUTE FUNCTION prevent_ledger_truncate();
