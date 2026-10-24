-- 0012_daily_rewards.sql
-- Fitur Daily Login Rewards (Streak 7 Hari)

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS last_daily_claim_at TIMESTAMPTZ NULL;

CREATE TABLE IF NOT EXISTS public.daily_rewards_log (
  id BIGSERIAL PRIMARY KEY,
  player_id BIGINT REFERENCES public.players(id) ON DELETE CASCADE,
  day_streak INT NOT NULL,
  coins_awarded BIGINT NOT NULL,
  claimed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_daily_rewards_log_player_claimed
  ON public.daily_rewards_log (player_id, claimed_at DESC);
