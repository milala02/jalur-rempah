-- Migrasi 0007: Fase 6 - Sistem Pertempuran Dasar dan Bajak Laut (Naval Combat)
-- Bersifat 100% additive tanpa merusak sistem ekonomi, P2P, atau World Events.

-- 1. Tambahkan kolom attack_power, defense_power, dan max_defense_power pada tabel ships
ALTER TABLE public.ships
  ADD COLUMN IF NOT EXISTS attack_power INT NOT NULL DEFAULT 0 CHECK (attack_power >= 0),
  ADD COLUMN IF NOT EXISTS defense_power INT NOT NULL DEFAULT 100 CHECK (defense_power >= 0),
  ADD COLUMN IF NOT EXISTS max_defense_power INT NOT NULL DEFAULT 100 CHECK (max_defense_power >= 1);

-- 2. Buat tabel combat_logs untuk mencatat seluruh pertempuran laut (Server-Authoritative)
CREATE TABLE IF NOT EXISTS public.combat_logs (
  id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tick_no               BIGINT NOT NULL DEFAULT 0,
  attacker_id           BIGINT NULL REFERENCES public.players(id),
  defender_id           BIGINT NULL REFERENCES public.players(id),
  ship_id               BIGINT NOT NULL REFERENCES public.ships(id) ON DELETE CASCADE,
  pirate_name           TEXT NOT NULL DEFAULT 'Bajak Laut Selat Malaka',
  damage                INT NOT NULL DEFAULT 0 CHECK (damage >= 0),
  is_pirate             BOOLEAN NOT NULL DEFAULT true,
  outcome               TEXT NOT NULL DEFAULT 'pirate_victory'
    CHECK (outcome IN ('player_victory', 'pirate_victory')),
  ship_attack_power     INT NOT NULL DEFAULT 0,
  ship_defense_before   INT NOT NULL DEFAULT 100,
  ship_defense_after    INT NOT NULL DEFAULT 100,
  looted_commodity_code TEXT NULL,
  looted_qty            BIGINT NOT NULL DEFAULT 0,
  bounty_coins          BIGINT NOT NULL DEFAULT 0,
  detail                TEXT NOT NULL DEFAULT '',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_combat_logs_ship_tick
  ON public.combat_logs (ship_id, tick_no DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_combat_logs_defender_tick
  ON public.combat_logs (defender_id, tick_no DESC, id DESC);
