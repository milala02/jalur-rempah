-- Migrasi 0002: Kas Pelabuhan (Treasury) dan Audit Konservasi Uang Global
-- Berdasarkan ADR-009, docs/06-SPEC-EKONOMI.md, dan docs/07-DATA-MODEL.md

ALTER TABLE public.ports
  ADD COLUMN IF NOT EXISTS treasury BIGINT NOT NULL DEFAULT 0 CHECK (treasury >= 0),
  ADD COLUMN IF NOT EXISTS initial_treasury BIGINT NOT NULL DEFAULT 0 CHECK (initial_treasury >= 0);

CREATE OR REPLACE VIEW public.economy_money_supply_audit AS
SELECT
  COALESCE((SELECT SUM(coins) FROM public.players), 0)::BIGINT AS total_player_coins,
  COALESCE((SELECT SUM(treasury) FROM public.ports), 0)::BIGINT AS total_port_treasury,
  COALESCE((SELECT SUM(-delta) FROM public.ledger WHERE reason = 'upkeep'), 0)::BIGINT AS cumulative_upkeep_sink,
  (
    COALESCE((SELECT SUM(delta) FROM public.ledger WHERE reason = 'starter'), 0)
    + COALESCE((SELECT SUM(initial_treasury) FROM public.ports), 0)
  )::BIGINT AS total_initial_money;
