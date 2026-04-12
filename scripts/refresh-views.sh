#!/usr/bin/env bash
# refresh-views.sh — Refresh network_views materialized views.
#
# Reads view_definition records from the database to determine which views
# to refresh, then runs REFRESH MATERIALIZED VIEW CONCURRENTLY on each.
#
# Usage:
#   ./scripts/refresh-views.sh
#   ./scripts/refresh-views.sh --namespace ELECTRICITY
#   ./scripts/refresh-views.sh --view vw_overhead_line
#   ./scripts/refresh-views.sh --namespace ELECTRICITY --view vw_overhead_line
#
# Multiple --namespace or --view flags are supported:
#   ./scripts/refresh-views.sh --namespace ELECTRICITY --namespace GAS
#
# DATABASE_URL is read from the environment or from apps/web/.env.local.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/apps/web/.env.local"

# ── Load DATABASE_URL from .env.local if not already set ─────────────────────

if [[ -z "${DATABASE_URL:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    DATABASE_URL="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'")"
    export DATABASE_URL
  fi
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set and could not be read from $ENV_FILE" >&2
  exit 1
fi

# ── Parse arguments ───────────────────────────────────────────────────────────

NAMESPACES=()
VIEWS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACES+=("$2")
      shift 2
      ;;
    --view)
      VIEWS+=("$2")
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Usage: $0 [--namespace NS] [--view VIEW_NAME]" >&2
      exit 1
      ;;
  esac
done

# ── Build SQL WHERE clause ────────────────────────────────────────────────────

WHERE="is_materialized = TRUE AND valid_to IS NULL"

if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
  NS_LIST=$(printf "'%s'," "${NAMESPACES[@]}")
  NS_LIST="${NS_LIST%,}"
  WHERE="$WHERE AND namespace IN ($NS_LIST)"
fi

if [[ ${#VIEWS[@]} -gt 0 ]]; then
  VIEW_LIST=$(printf "'%s'," "${VIEWS[@]}")
  VIEW_LIST="${VIEW_LIST%,}"
  WHERE="$WHERE AND view_name IN ($VIEW_LIST)"
fi

# ── Fetch matching view names ─────────────────────────────────────────────────

VIEW_NAMES=$(psql "$DATABASE_URL" --no-psqlrc --tuples-only --no-align \
  --command "SELECT view_name FROM data_dictionary.view_definition WHERE $WHERE ORDER BY namespace, view_name;")

if [[ -z "$VIEW_NAMES" ]]; then
  echo "No matching materialized views found."
  exit 0
fi

# ── Refresh each view ─────────────────────────────────────────────────────────

PASS=0
FAIL=0

while IFS= read -r view_name; do
  [[ -z "$view_name" ]] && continue
  echo -n "Refreshing network_views.$view_name ... "
  START=$(date +%s%N)

  if psql "$DATABASE_URL" --no-psqlrc --quiet \
       --command "REFRESH MATERIALIZED VIEW CONCURRENTLY network_views.$view_name; ANALYZE network_views.$view_name;" 2>&1; then
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    echo "OK (${ELAPSED}ms)"
    PASS=$(( PASS + 1 ))
  else
    echo "FAILED"
    FAIL=$(( FAIL + 1 ))
  fi
done <<< "$VIEW_NAMES"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Done: $PASS succeeded, $FAIL failed."
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
