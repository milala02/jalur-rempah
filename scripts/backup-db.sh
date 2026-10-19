#!/usr/bin/env bash
# Skrip Cadangan Harian Database Jalur Rempah (M6 — docs/12-DEPLOYMENT-RUNBOOK.md)
set -euo pipefail

umask 077
BACKUP_DIR="${BACKUP_DIR:-/var/backups/jalurrempah}"
DB_URL="${DATABASE_URL:-postgres://127.0.0.1:5432/jalurrempah}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.dump"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

echo "[BACKUP] Memulai pg_dump ke ${DUMP_FILE}..."
pg_dump -Fc "${DB_URL}" > "${DUMP_FILE}"

if [ ! -s "${DUMP_FILE}" ]; then
  echo "[BACKUP] ERROR: Berkas dump kosong!" >&2
  exit 1
fi

echo "[BACKUP] Berhasil membuat dump ($(wc -c < "${DUMP_FILE}") byte). Menghapus cadangan > ${RETENTION_DAYS} hari..."
find "${BACKUP_DIR}" -name "backup_*.dump" -mtime "+${RETENTION_DAYS}" -delete
echo "[BACKUP] Selesai."
