-- Migrasi 0003: Pencatatan Sumber/Pengurang Kas Pelabuhan (sumber_kumulatif) & Optimasi Volume Ledger Upkeep (A5)
-- Berdasarkan ADR-010, ADR-011, docs/06-SPEC-EKONOMI.md, dan docs/07-DATA-MODEL.md

-- 1. Tabel append-only pencatat sumber & pengurang kas pelabuhan (sumber_kumulatif & port_producer_payout)
CREATE TABLE IF NOT EXISTS public.economy_sources_sinks (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tick_no     BIGINT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('source', 'sink')),
  reason      TEXT NOT NULL CHECK (reason IN ('port_income', 'rescue', 'port_producer_payout')),
  port_id     SMALLINT REFERENCES public.ports(id),
  ref_player  BIGINT REFERENCES public.players(id),
  amount      BIGINT NOT NULL CHECK (amount > 0),
  meta        JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_economy_sources_sinks_kind_tick
  ON public.economy_sources_sinks (kind, tick_no DESC);

-- Trigger append-only pada economy_sources_sinks (seperti ledger)
DROP TRIGGER IF EXISTS trg_econ_sources_sinks_prevent_update_delete ON public.economy_sources_sinks;
CREATE TRIGGER trg_econ_sources_sinks_prevent_update_delete
BEFORE UPDATE OR DELETE ON public.economy_sources_sinks
FOR EACH ROW
EXECUTE FUNCTION prevent_ledger_update_or_delete();

DROP TRIGGER IF EXISTS trg_econ_sources_sinks_prevent_truncate ON public.economy_sources_sinks;
CREATE TRIGGER trg_econ_sources_sinks_prevent_truncate
BEFORE TRUNCATE ON public.economy_sources_sinks
FOR EACH STATEMENT
EXECUTE FUNCTION prevent_ledger_truncate();

-- 2. Kolom akuntansi agregasi blok upkeep pada players (Hasil Analisis A5 / ADR-011):
--    - unflushed_upkeep: akumulasi perawatan kapal sejak flush blok terakhir (di-flush ke ledger tiap UPKEEP_LEDGER_BATCH_TICKS atau sebelum transaksi jual/beli/audit sehingga players.coins == SUM(ledger.delta) - unflushed_upkeep selalu eksak, dan saat unflushed_upkeep = 0 berlaku players.coins == SUM(ledger.delta)).
--    - cumulative_upkeep_paid: penghitung monotonik total perawatan kapal sepanjang umur pemain.
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS unflushed_upkeep BIGINT NOT NULL DEFAULT 0 CHECK (unflushed_upkeep >= 0),
  ADD COLUMN IF NOT EXISTS cumulative_upkeep_paid BIGINT NOT NULL DEFAULT 0 CHECK (cumulative_upkeep_paid >= 0);

-- 3. Indeks parsial untuk mempercepat query /me/ledger pada transaksi perdagangan (di luar upkeep rutin, hasil A5)
CREATE INDEX IF NOT EXISTS idx_ledger_player_non_upkeep
  ON public.ledger (player_id, id DESC)
  WHERE reason <> 'upkeep';

-- 4. Perbarui view audit konservasi uang global dengan suku sumber_kumulatif (cumulative_source):
--    total_player_coins + total_port_treasury + cumulative_upkeep_sink == total_initial_money + cumulative_source
CREATE OR REPLACE VIEW public.economy_money_supply_audit AS
SELECT
  COALESCE((SELECT SUM(coins) FROM public.players), 0)::BIGINT AS total_player_coins,
  COALESCE((SELECT SUM(treasury) FROM public.ports), 0)::BIGINT AS total_port_treasury,
  (
    COALESCE((SELECT SUM(-delta) FROM public.ledger WHERE reason = 'upkeep'), 0)
    + COALESCE((SELECT SUM(unflushed_upkeep) FROM public.players), 0)
    + COALESCE((SELECT SUM(amount) FROM public.economy_sources_sinks WHERE kind = 'sink'), 0)
  )::BIGINT AS cumulative_upkeep_sink,
  (
    COALESCE((SELECT SUM(delta) FROM public.ledger WHERE reason = 'starter'), 0)
    + COALESCE((SELECT SUM(initial_treasury) FROM public.ports), 0)
  )::BIGINT AS total_initial_money,
  (
    COALESCE((SELECT SUM(delta) FROM public.ledger WHERE reason = 'rescue'), 0)
    + COALESCE((SELECT SUM(amount) FROM public.economy_sources_sinks WHERE kind = 'source'), 0)
  )::BIGINT AS cumulative_source;
