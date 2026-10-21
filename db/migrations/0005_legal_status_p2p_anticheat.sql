-- Migrasi 0005: Fondasi Hukum (UU PDP / ToS), Status Moderasi Akun, P2P Trading (Auction House & Direct Trade), Anti-Cheat, & World Events Engine (Fase 3)
-- Berdasarkan Pilar 3 (P2P Trading), Pilar 5 (Anti-Cheat & Anomaly Detection), Pilar 6 (UU PDP No. 27/2022, ToS/EULA), dan Fase 3 (World Events Engine)

-- 1. Kolom Persetujuan Hukum (ToS/UU PDP) dan Status Moderasi Akun pada tabel players
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS tos_accepted_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS tos_version VARCHAR(10) NULL,
  ADD COLUMN IF NOT EXISTS account_status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (account_status IN ('active', 'shadowbanned', 'banned'));

CREATE INDEX IF NOT EXISTS idx_players_account_status
  ON public.players (account_status);

-- 2. Tabel P2P Trading: Auction House (Bursa Lelang Publik) & Direct Trade (Tukar Langsung Antar Pemain dengan Escrow)
--    - Harga per unit wajib 50%..200% dari harga pasar saat pembuatan (Anti-RMT).
--    - Barang dikunci dari ship_cargo penjual saat order dibuat (Escrow).
--    - Kedaluwarsa otomatis setelah 1.440 tick (24 jam) jika belum diambil.
CREATE TABLE IF NOT EXISTS public.p2p_orders (
  id                       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_type               VARCHAR(16) NOT NULL CHECK (order_type IN ('auction', 'direct')),
  seller_id                BIGINT NOT NULL REFERENCES public.players(id),
  target_player_id         BIGINT NULL REFERENCES public.players(id),
  buyer_id                 BIGINT NULL REFERENCES public.players(id),
  ship_id                  BIGINT NOT NULL REFERENCES public.ships(id) ON DELETE CASCADE,
  port_id                  SMALLINT NOT NULL REFERENCES public.ports(id),
  commodity_id             SMALLINT NOT NULL REFERENCES public.commodities(id),
  qty                      BIGINT NOT NULL CHECK (qty > 0),
  unit_price               BIGINT NOT NULL CHECK (unit_price >= 1),
  total_price              BIGINT NOT NULL CHECK (total_price >= 1),
  market_price_at_creation BIGINT NOT NULL CHECK (market_price_at_creation >= 1),
  status                   VARCHAR(16) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'completed', 'cancelled', 'expired')),
  created_tick             BIGINT NOT NULL DEFAULT 0,
  expires_tick             BIGINT NOT NULL DEFAULT 1440,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_p2p_orders_status_port
  ON public.p2p_orders (status, port_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_p2p_orders_expires_tick
  ON public.p2p_orders (status, expires_tick)
  WHERE status = 'open';

-- 3. Tabel Anti-Cheat & Anomaly Detection (Deteksi Otomatis -> Shadowban -> Tinjauan Manual Admin)
CREATE TABLE IF NOT EXISTS public.anomaly_alerts (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id         BIGINT NOT NULL REFERENCES public.players(id),
  alert_type        VARCHAR(40) NOT NULL,
  severity          VARCHAR(16) NOT NULL DEFAULT 'high',
  detail            TEXT NOT NULL,
  auto_action       VARCHAR(20) NOT NULL DEFAULT 'shadowbanned',
  resolved          BOOLEAN NOT NULL DEFAULT false,
  resolved_by       TEXT NULL,
  resolution_status VARCHAR(20) NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_anomaly_alerts_player_unresolved
  ON public.anomaly_alerts (player_id, resolved, created_at DESC);

-- 4. Perluasan Tabel world_events untuk Fase 3 (World Events Engine: Wabah Hama, Embargo/Perang, Angin Muson Kencang)
ALTER TABLE public.world_events
  ADD COLUMN IF NOT EXISTS port_id SMALLINT NULL REFERENCES public.ports(id),
  ADD COLUMN IF NOT EXISTS commodity_id SMALLINT NULL REFERENCES public.commodities(id),
  ADD COLUMN IF NOT EXISTS active_until_tick BIGINT NULL,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS effect_meta JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_world_events_active
  ON public.world_events (is_active, active_until_tick DESC);
