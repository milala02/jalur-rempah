-- Migrasi 0008: Fase 7 - Sistem Quest (Misi Harian) dan Tutorial Onboarding Pemain Baru
-- Bersifat 100% additive tanpa merusak sistem ekonomi maupun pertempuran.

-- 1. Tambahkan kolom tutorial_step (0..3) dan bonus_xp pada tabel players
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS tutorial_step INT NOT NULL DEFAULT 0 CHECK (tutorial_step >= 0 AND tutorial_step <= 3),
  ADD COLUMN IF NOT EXISTS bonus_xp BIGINT NOT NULL DEFAULT 0 CHECK (bonus_xp >= 0);

-- 2. Buat tabel quests (referensi misi harian)
CREATE TABLE IF NOT EXISTS public.quests (
  id           SMALLINT PRIMARY KEY,
  code         TEXT UNIQUE NOT NULL,
  title        TEXT NOT NULL,
  description  TEXT NOT NULL,
  type         TEXT NOT NULL CHECK (type IN ('trade', 'combat_win', 'save_dsl')),
  target_value INT NOT NULL CHECK (target_value > 0),
  reward_coins BIGINT NOT NULL DEFAULT 50 CHECK (reward_coins >= 0),
  reward_xp    INT NOT NULL DEFAULT 100 CHECK (reward_xp >= 0)
);

-- 3. Buat tabel player_quests (progres misi harian per pemain per hari server)
CREATE TABLE IF NOT EXISTS public.player_quests (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id     BIGINT NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  quest_id      SMALLINT NOT NULL REFERENCES public.quests(id) ON DELETE CASCADE,
  assigned_date DATE NOT NULL DEFAULT CURRENT_DATE,
  progress      INT NOT NULL DEFAULT 0 CHECK (progress >= 0),
  is_completed  BOOLEAN NOT NULL DEFAULT false,
  is_claimed    BOOLEAN NOT NULL DEFAULT false,
  assigned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (player_id, quest_id, assigned_date)
);

CREATE INDEX IF NOT EXISTS idx_player_quests_player_date
  ON public.player_quests (player_id, assigned_date DESC, quest_id ASC);

-- 4. Seed 3 Daily Quest Awal
INSERT INTO public.quests (id, code, title, description, type, target_value, reward_coins, reward_xp)
VALUES
  (1, 'first_trade', 'Perdagangan Pertama', 'Beli atau jual total 10 unit komoditas di pasar atau bursa.', 'trade', 10, 120, 150),
  (2, 'pirate_hunter', 'Pemburu Bajak Laut', 'Menangkan 1 pertempuran laut melawan armada Bajak Laut.', 'combat_win', 1, 200, 250),
  (3, 'first_code', 'Kode Pertama', 'Simpan 1 aturan otomatisasi Bahasa Aturan (DSL) pada kapalmu.', 'save_dsl', 1, 100, 120)
ON CONFLICT (id) DO UPDATE
SET code = EXCLUDED.code,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    type = EXCLUDED.type,
    target_value = EXCLUDED.target_value,
    reward_coins = EXCLUDED.reward_coins,
    reward_xp = EXCLUDED.reward_xp;
