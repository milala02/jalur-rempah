-- Migrasi 0009: Fase 8 - Sistem Aliansi Dagang (Guilds), Kas Aliansi (treasury_coins), Peran Anggota (role VARCHAR(20)), & World Boss ("Bajak Laut Armada Besar")

-- 1. Pastikan tabel guilds memiliki kolom treasury_coins BIGINT DEFAULT 0 serta atribut World Boss Aliansi
ALTER TABLE public.guilds
  ADD COLUMN IF NOT EXISTS treasury_coins BIGINT NOT NULL DEFAULT 0 CHECK (treasury_coins >= 0),
  ADD COLUMN IF NOT EXISTS boss_active BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS boss_name TEXT NOT NULL DEFAULT 'Bajak Laut Armada Besar',
  ADD COLUMN IF NOT EXISTS boss_hp INT NOT NULL DEFAULT 0 CHECK (boss_hp >= 0),
  ADD COLUMN IF NOT EXISTS boss_max_hp INT NOT NULL DEFAULT 500 CHECK (boss_max_hp > 0),
  ADD COLUMN IF NOT EXISTS boss_port_id SMALLINT REFERENCES public.ports(id),
  ADD COLUMN IF NOT EXISTS boss_spawned_tick BIGINT;

-- 2. Pastikan tabel guild_members memiliki kolom role VARCHAR(20) DEFAULT 'member' ('leader', 'officer', 'member')
ALTER TABLE public.guild_members
  ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'member';

ALTER TABLE public.guild_members
  ALTER COLUMN role TYPE VARCHAR(20),
  ALTER COLUMN role SET DEFAULT 'member';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'guild_members_role_check'
  ) THEN
    ALTER TABLE public.guild_members
      ADD CONSTRAINT guild_members_role_check CHECK (role IN ('leader', 'officer', 'member'));
  END IF;
END $$;

-- 3. Perbarui view audit konservasi uang global agar kas Guild (treasury_coins) diperhitungkan dalam total kas institusi:
--    total_player_coins + total_port_treasury (ports.treasury + guilds.treasury_coins) + cumulative_upkeep_sink == total_initial_money + cumulative_source
CREATE OR REPLACE VIEW public.economy_money_supply_audit AS
SELECT
  COALESCE((SELECT SUM(coins) FROM public.players), 0)::BIGINT AS total_player_coins,
  (
    COALESCE((SELECT SUM(treasury) FROM public.ports), 0)
    + COALESCE((SELECT SUM(treasury_coins) FROM public.guilds), 0)
  )::BIGINT AS total_port_treasury,
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
