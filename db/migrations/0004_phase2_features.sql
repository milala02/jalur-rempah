-- Migrasi 0004: Fitur Fase 2 Pasca-MVP (Kabut Informasi, Memori Kapal, Serikat Dagang, Kontrak, Musim/Event, & Anonimisasi Akun)
-- Berdasarkan docs/01-GDD.md, docs/05-SPEC-BAHASA-ATURAN.md, docs/08-API-CONTRACT.md, docs/09-SPEC-TICK-LOOP.md, docs/13-ROADMAP.md, dan ADR-012

-- 1. Dukungan penghapusan/anonimisasi akun (DELETE /v1/me, docs/08 & docs/09):
--    Kapal dan muatan dihapus, tetapi baris players dianonimkan dan ledger dipertahankan agar invarian append-only tetap utuh.
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Lepas FK ref_ship pada ledger agar kapal dapat dihapus pada DELETE /v1/me tanpa melanggar sifat append-only ledger
ALTER TABLE public.ledger
  DROP CONSTRAINT IF EXISTS ledger_ref_ship_fkey;

-- 2. Kabut Informasi (Fog of War — ADR-012):
--    Menyimpan harga dan stok terakhir yang diketahui pemain dari kunjungan kapalnya ke pelabuhan tersebut.
CREATE TABLE IF NOT EXISTS public.port_intel (
  player_id     BIGINT NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  port_id       SMALLINT NOT NULL REFERENCES public.ports(id),
  commodity_id  SMALLINT NOT NULL REFERENCES public.commodities(id),
  price         BIGINT NOT NULL CHECK (price >= 1),
  stock         BIGINT NOT NULL CHECK (stock >= 0),
  tick_seen     BIGINT NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, port_id, commodity_id)
);

-- 3. Memori Antar-Tick per Kapal (simpan/ambil dengan kuota 8 slot: 0..7, docs/05 Rencana Ekstensi):
CREATE TABLE IF NOT EXISTS public.ship_memory (
  ship_id     BIGINT NOT NULL REFERENCES public.ships(id) ON DELETE CASCADE,
  slot        SMALLINT NOT NULL CHECK (slot >= 0 AND slot < 8),
  val         BIGINT NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (ship_id, slot)
);

-- 4. Serikat Dagang Ringan (Guilds — docs/13 Setelah MVP #4):
CREATE TABLE IF NOT EXISTS public.guilds (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        TEXT UNIQUE NOT NULL,
  name        TEXT UNIQUE NOT NULL,
  leader_id   BIGINT NOT NULL REFERENCES public.players(id),
  description TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.guild_members (
  guild_id   BIGINT NOT NULL REFERENCES public.guilds(id) ON DELETE CASCADE,
  player_id  BIGINT NOT NULL UNIQUE REFERENCES public.players(id) ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'officer', 'member')),
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (guild_id, player_id)
);

-- 5. Kontrak Pengiriman Komoditas (Contracts — docs/13 Setelah MVP #4):
CREATE TABLE IF NOT EXISTS public.trade_contracts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  creator_id      BIGINT NOT NULL REFERENCES public.players(id),
  fulfilled_by    BIGINT REFERENCES public.players(id),
  port_id         SMALLINT NOT NULL REFERENCES public.ports(id),
  commodity_id    SMALLINT NOT NULL REFERENCES public.commodities(id),
  qty             BIGINT NOT NULL CHECK (qty > 0),
  reward_coins    BIGINT NOT NULL CHECK (reward_coins > 0),
  status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'fulfilled', 'cancelled')),
  created_tick    BIGINT NOT NULL DEFAULT 0,
  fulfilled_tick  BIGINT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_trade_contracts_status_port
  ON public.trade_contracts (status, port_id);

-- 6. Musim Angin Muson & Event Nusantara (docs/13 Setelah MVP #5):
CREATE TABLE IF NOT EXISTS public.world_events (
  tick_no       BIGINT PRIMARY KEY,
  season        TEXT NOT NULL CHECK (season IN ('muson_barat', 'muson_timur', 'pancaroba')),
  event_code    TEXT NOT NULL,
  title         TEXT NOT NULL,
  description   TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
