#!/usr/bin/env bash
# Skrip Uji Pemulihan (Restore Verification) & Pemeriksaan Konsistensi (M6 — docs/12 & docs/13)
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Pemakaian: $0 <path_ke_file_backup.dump> [admin_db_url]" >&2
  exit 1
fi

DUMP_FILE="$1"
ADMIN_DB_URL="${2:-${DATABASE_URL:-postgres://127.0.0.1:5432/postgres}}"
TEMP_DB="jr_restore_verify_$(date +%s)"

echo "[RESTORE-VERIFY] Membuat database sementara ${TEMP_DB}..."
psql "${ADMIN_DB_URL}" -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${TEMP_DB};"

cleanup() {
  echo "[RESTORE-VERIFY] Membersihkan database sementara ${TEMP_DB}..."
  psql "${ADMIN_DB_URL}" -c "DROP DATABASE IF EXISTS ${TEMP_DB};" >/dev/null 2>&1 || true
}
trap cleanup EXIT

TARGET_URL="$(echo "${ADMIN_DB_URL}" | sed -E "s|/[^/?]+(\?.*)?$|/${TEMP_DB}\1|")"
echo "[RESTORE-VERIFY] Memulihkan dump ${DUMP_FILE} ke ${TEMP_DB}..."
pg_restore --no-owner --no-privileges -d "${TARGET_URL}" "${DUMP_FILE}"

echo "[RESTORE-VERIFY] Memeriksa invarian konservasi uang global (economy_money_supply_audit)..."
MISMATCH_COUNT="$(psql "${TARGET_URL}" -t -A -c "
  SELECT count(*)
  FROM public.economy_money_supply_audit
  WHERE (total_player_coins + total_port_treasury + cumulative_upkeep_sink)
     <> (total_initial_money + cumulative_source);
")"

if [ "${MISMATCH_COUNT}" != "0" ]; then
  echo "[RESTORE-VERIFY] GAGAL: Ditemukan ketidakcocokan konservasi uang!" >&2
  exit 1
fi

echo "[RESTORE-VERIFY] LULUS: Cadangan berhasil dipulihkan dan seluruh invarian konsisten."
