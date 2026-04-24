#!/usr/bin/env bash
# setup-native-db.sh
# Initialises (or re-initialises) the ttdb database on the native WSL2 PostgreSQL
# instance. Mirrors what the Docker init container previously did automatically.
#
# Usage:
#   bash scripts/setup-native-db.sh           # uses DATABASE_URL from env / .env.local
#   DATABASE_URL=postgresql://... bash scripts/setup-native-db.sh
#
# The script creates the database if it does not already exist, then runs all
# init SQL files in order. Existing objects are replaced (DROP IF EXISTS is used
# in the SQL files where needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INIT_DIR="${REPO_ROOT}/packages/db/init"
ENV_FILE="${REPO_ROOT}/apps/web/.env.local"

# ── Resolve DATABASE_URL ──────────────────────────────────────────────────────

if [[ -z "${DATABASE_URL:-}" && -f "${ENV_FILE}" ]]; then
  DATABASE_URL="$(grep -E '^DATABASE_URL=' "${ENV_FILE}" | head -1 | cut -d= -f2-)"
fi
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:devpassword@localhost:5432/ttdb}"

# Parse connection components from the URL.
# URL format: postgresql://user:password@host:port/dbname
DB_USER="$(echo "${DATABASE_URL}" | sed -E 's|postgresql://([^:@]+).*|\1|')"
DB_HOST="$(echo "${DATABASE_URL}" | sed -E 's|postgresql://[^@]+@([^:/]+).*|\1|')"
DB_PORT="$(echo "${DATABASE_URL}" | sed -E 's|.*:([0-9]+)/.*|\1|')"
DB_NAME="$(echo "${DATABASE_URL}" | sed -E 's|.*/([^?]+).*|\1|')"
DB_PASS="$(echo "${DATABASE_URL}" | sed -E 's|postgresql://[^:]+:([^@]+)@.*|\1|')"

export PGPASSWORD="${DB_PASS}"

PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER}"

# ── Pre-flight check ──────────────────────────────────────────────────────────

echo "Connecting to PostgreSQL at ${DB_HOST}:${DB_PORT} as ${DB_USER} ..."

if ! ${PSQL} -c '\q' postgres 2>/dev/null; then
  cat <<'EOF'

ERROR: Cannot connect to PostgreSQL. Common fixes for WSL2 native PostgreSQL:

  1. Ensure PostgreSQL is running:
       sudo service postgresql start

  2. Set a password for the postgres user:
       sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'devpassword';"

  3. To allow Martin (Docker) to connect, add to postgresql.conf:
       listen_addresses = '*'
     and to pg_hba.conf:
       host  all  all  172.16.0.0/12  md5
     then restart:
       sudo service postgresql restart

  4. Check your DATABASE_URL in apps/web/.env.local matches the above.

EOF
  exit 1
fi

# ── Create database ───────────────────────────────────────────────────────────

if ${PSQL} -lqt postgres | cut -d'|' -f1 | grep -qw "${DB_NAME}"; then
  echo "Database '${DB_NAME}' exists — dropping for clean re-initialisation ..."
  ${PSQL} -c "DROP DATABASE ${DB_NAME};" postgres
fi
echo "Creating database '${DB_NAME}' ..."
${PSQL} -c "CREATE DATABASE ${DB_NAME};" postgres
echo "✓ Database created."

# ── Run init SQL files in order ───────────────────────────────────────────────

SQL_FILES=(
  "01_extensions.sql"
  "02_schemas.sql"
  "03_iam_ddl.sql"
  "04_network_model_ddl.sql"
  "05_seed.sql"
  "06_function_sources.sql"
  "07_materialized_views.sql"
  "08_highways.sql"
)

echo ""
echo "Running init SQL files against '${DB_NAME}' ..."
echo ""

ALL_OK=true

for sql_file in "${SQL_FILES[@]}"; do
  file_path="${INIT_DIR}/${sql_file}"
  if [[ ! -f "${file_path}" ]]; then
    echo "  ✗ MISSING: ${sql_file}"
    ALL_OK=false
    continue
  fi

  start_ms=$(date +%s%3N)
  # Use `if` so set -e does not fire on psql failure before we can capture output
  if err_out=$(${PSQL} -v ON_ERROR_STOP=1 -f "${file_path}" "${DB_NAME}" 2>&1); then
    elapsed=$(( $(date +%s%3N) - start_ms ))
    printf "  ✓ %-40s %dms\n" "${sql_file}" "${elapsed}"
  else
    elapsed=$(( $(date +%s%3N) - start_ms ))
    printf "  ✗ %-40s %dms\n" "${sql_file}" "${elapsed}"
    echo ""
    echo "${err_out}"
    echo ""
    ALL_OK=false
    break
  fi
done

echo ""

if [[ "${ALL_OK}" == "true" ]]; then
  echo "✓ Database '${DB_NAME}' initialised successfully."
  echo ""
  echo "Next steps:"
  echo "  docker compose up -d          # start Martin"
  echo "  cd apps/web && pnpm dev       # start Next.js"
else
  echo "✗ Initialisation failed. See error output above."
  exit 1
fi
