-- Skrip Pemisahan Role Database Hak Akses Minimal (docs/07-DATA-MODEL.md & docs/12-DEPLOYMENT-RUNBOOK.md)
-- [PERLU VERIFIKASI PEMILIK: ganti kata sandi placeholder sebelum dijalankan oleh superuser PostgreSQL]

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migrator') THEN
    CREATE ROLE migrator LOGIN PASSWORD 'GANTI_SANDI_MIGRATOR';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_rw') THEN
    CREATE ROLE api_rw LOGIN PASSWORD 'GANTI_SANDI_API_RW';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'worker_rw') THEN
    CREATE ROLE worker_rw LOGIN PASSWORD 'GANTI_SANDI_WORKER_RW';
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO api_rw, worker_rw;

-- api_rw: baca semua; tulis akun, kapal awal/tambahan, aturan, refresh_tokens, guild, dan kontrak
GRANT SELECT ON ALL TABLES IN SCHEMA public TO api_rw;
GRANT INSERT, UPDATE ON public.players, public.ships, public.ship_cargo, public.rule_sets, public.refresh_tokens TO api_rw;
GRANT INSERT ON public.ledger, public.economy_sources_sinks TO api_rw;
GRANT INSERT, UPDATE, DELETE ON public.guilds, public.guild_members, public.trade_contracts TO api_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO api_rw;

-- worker_rw: baca semua; tulis keadaan dunia, pasar, kas, ledger, log aksi, intel, memori kapal, dan tick_state
GRANT SELECT ON ALL TABLES IN SCHEMA public TO worker_rw;
GRANT INSERT, UPDATE, DELETE ON public.market, public.market_history, public.ports, public.economy_sources_sinks,
  public.players, public.ships, public.ship_cargo, public.ledger, public.action_log, public.tick_state,
  public.port_intel, public.ship_memory, public.world_events, public.trade_contracts TO worker_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO worker_rw;
