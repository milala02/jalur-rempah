-- Migrasi 0010: Simpan ringkasan loot untuk log serangan World Boss Guild.
ALTER TABLE public.combat_logs
  ADD COLUMN IF NOT EXISTS loot_summary TEXT;
