-- Migrasi 0006: Fase 5 - Ekspansi Global (8 Negara, Pelabuhan Internasional, Komoditas Langka) & Sistem Progressive Unlocking (Level Pemain)
-- Bersifat 100% additive tanpa menghapus data lama.

-- 1. Tambah kolom level pada tabel players
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS level INT NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 7);

-- 2. Buat tabel countries dengan kolom min_level_required
CREATE TABLE IF NOT EXISTS public.countries (
  id                 SMALLINT PRIMARY KEY,
  code               TEXT UNIQUE NOT NULL,
  name               TEXT NOT NULL,
  region             TEXT NOT NULL DEFAULT 'Nusantara',
  min_level_required INT NOT NULL DEFAULT 1 CHECK (min_level_required >= 1)
);

ALTER TABLE public.countries
  ADD COLUMN IF NOT EXISTS min_level_required INT DEFAULT 1 NOT NULL;

-- 3. Tambah kolom min_level_required, country_code, dan koordinat peta (map_x, map_y) pada tabel ports
ALTER TABLE public.ports
  ADD COLUMN IF NOT EXISTS min_level_required INT DEFAULT 1 NOT NULL CHECK (min_level_required >= 1),
  ADD COLUMN IF NOT EXISTS country_code TEXT NOT NULL DEFAULT 'nusantara',
  ADD COLUMN IF NOT EXISTS map_x DOUBLE PRECISION NOT NULL DEFAULT 0.50,
  ADD COLUMN IF NOT EXISTS map_y DOUBLE PRECISION NOT NULL DEFAULT 0.50;

-- 4. Tambah kolom min_level_required, name, country_code, category, dan origin_port pada tabel commodities
ALTER TABLE public.commodities
  ADD COLUMN IF NOT EXISTS min_level_required INT DEFAULT 1 NOT NULL CHECK (min_level_required >= 1),
  ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS country_code TEXT NOT NULL DEFAULT 'nusantara',
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'Rempah',
  ADD COLUMN IF NOT EXISTS origin_port_id SMALLINT NULL REFERENCES public.ports(id),
  ADD COLUMN IF NOT EXISTS origin_port_code TEXT NOT NULL DEFAULT 'banda';

-- 5. Seed 8 Negara (4 Negara Awal/Regional + 4 Negara Baru: Arab Level 4, Jepang Level 5, Eropa Level 6, Mesir Level 7)
INSERT INTO public.countries (id, code, name, region, min_level_required)
VALUES
  (1, 'nusantara', 'Kepulauan Nusantara', 'Asia Tenggara', 1),
  (2, 'malaka_sultanate', 'Kesultanan Malaka', 'Selat Malaka', 1),
  (3, 'india', 'India (Pantai Malabar)', 'Samudra Hindia', 2),
  (4, 'tiongkok', 'Tiongkok (Jalur Sutra Laut)', 'Asia Timur', 3),
  (5, 'arab', 'Arab', 'Timur Tengah', 4),
  (6, 'jepang', 'Jepang', 'Asia Timur', 5),
  (7, 'eropa', 'Eropa', 'Atlantik & Mediterania', 6),
  (8, 'mesir', 'Mesir', 'Laut Merah & Afrika Utara', 7)
ON CONFLICT (id) DO UPDATE
SET code = EXCLUDED.code,
    name = EXCLUDED.name,
    region = EXCLUDED.region,
    min_level_required = EXCLUDED.min_level_required;
