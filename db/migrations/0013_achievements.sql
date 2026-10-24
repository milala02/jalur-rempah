-- 0013_achievements.sql
-- Sistem Pencapaian (Achievements) & Dukungan Kontrak Dagang NPC

CREATE TABLE IF NOT EXISTS public.achievements (
  code VARCHAR(50) PRIMARY KEY,
  title VARCHAR(100),
  description TEXT,
  icon_emoji VARCHAR(10),
  requirement_type VARCHAR(30),
  requirement_value BIGINT,
  reward_coins BIGINT
);

CREATE TABLE IF NOT EXISTS public.player_achievements (
  player_id BIGINT REFERENCES public.players(id) ON DELETE CASCADE,
  achievement_code VARCHAR(50) REFERENCES public.achievements(code) ON DELETE CASCADE,
  unlocked_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (player_id, achievement_code)
);

INSERT INTO public.achievements (code, title, description, icon_emoji, requirement_type, requirement_value, reward_coins)
VALUES
  ('pelaut_pertama', 'Pelaut Pertama', 'Beli 1 kapal tambahan di galangan kapal.', '⛵', 'buy_ships', 1, 500),
  ('saudagar', 'Saudagar', 'Jual total 100 unit komoditas di pasar Nusantara.', '⚖️', 'sell_units', 100, 1000),
  ('juragan', 'Juragan', 'Kumpulkan saldo 10.000 koin di kas nakhoda.', '💰', 'coins', 10000, 500),
  ('sultan', 'Sultan', 'Kumpulkan saldo 1.000.000 koin di kas nakhoda.', '👑', 'coins', 1000000, 10000),
  ('penjelajah', 'Penjelajah', 'Kunjungi minimal 5 pelabuhan berbeda di Nusantara.', '🧭', 'visit_ports', 5, 1500),
  ('pemburu_bajak_laut', 'Pemburu Bajak Laut', 'Menangkan 5 pertempuran laut melawan perompak.', '⚔️', 'win_battles', 5, 1000),
  ('nahkoda_berpengalaman', 'Nahkoda Berpengalaman', 'Capai Level 5 sebagai kapten armada.', '🎖️', 'level', 5, 2000),
  ('programmer_handal', 'Programmer Handal', 'Simpan minimal 10 aturan otomasi DSL.', '📜', 'save_dsl', 10, 1500),
  ('kolektor', 'Kolektor Armada', 'Miliki 5 kapal sekaligus dalam armadamu.', '🚢', 'own_ships', 5, 3000),
  ('kaya_raya', 'Kaya Raya', 'Capai total kekayaan bersih (Net Worth) 100.000 koin.', '💎', 'net_worth', 100000, 5000),
  ('raja_rempah', 'Raja Rempah', 'Capai total kekayaan bersih (Net Worth) 1.000.000 koin.', '🏆', 'net_worth', 1000000, 20000),
  ('diplomat', 'Diplomat Nusantara', 'Bergabung atau dirikan sebuah Serikat Dagang (Aliansi).', '🤝', 'join_guild', 1, 500),
  ('filantropi', 'Filantropi Serikat', 'Donasikan total 10.000 koin ke kas aliansi.', '🏛️', 'donate_guild', 10000, 1000),
  ('penakluk_boss', 'Penakluk Armada VOC', 'Kalahkan World Boss bersama aliansi atau armadamu.', '🐉', 'defeat_boss', 1, 5000),
  ('veteran', 'Veteran Samudra', 'Bermain dan klaim hadiah harian selama 7 hari.', '🌟', 'play_days', 7, 1000)
ON CONFLICT (code) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  icon_emoji = EXCLUDED.icon_emoji,
  requirement_type = EXCLUDED.requirement_type,
  requirement_value = EXCLUDED.requirement_value,
  reward_coins = EXCLUDED.reward_coins;

-- Izinkan kontrak dagang NPC dibuat oleh sistem tanpa bergantung pada creator_id pemain
ALTER TABLE public.trade_contracts
  ALTER COLUMN creator_id DROP NOT NULL;

ALTER TABLE public.trade_contracts
  ADD COLUMN IF NOT EXISTS issuer_name TEXT NULL;
