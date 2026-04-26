#!/usr/bin/env bash
# load-spen-primary-data.sh
# Loads a SPEN primary area GeoJSON file into network_model.object and refreshes the view.
#
# Usage:
#   bash scripts/load-spen-primary-data.sh --file data/SPD_primary.geojson --prefix SPD
#   bash scripts/load-spen-primary-data.sh --file data/SPM_primary.geojson --prefix SPM
#
# DATABASE_URL is read from apps/web/.env.local or the environment.
# Existing records are silently skipped (safe to re-run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Parse arguments ───────────────────────────────────────────────────────────

DATA_FILE=""
IDENTITY_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)   DATA_FILE="$2";       shift 2 ;;
    --prefix) IDENTITY_PREFIX="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2
       echo "Usage: $0 --file <path> --prefix <prefix>" >&2
       exit 1 ;;
  esac
done

if [[ -z "$DATA_FILE" || -z "$IDENTITY_PREFIX" ]]; then
  echo "ERROR: --file and --prefix are both required." >&2
  echo "Usage: $0 --file <path> --prefix <prefix>" >&2
  exit 1
fi

# Resolve relative paths against repo root
if [[ "$DATA_FILE" != /* ]]; then
  DATA_FILE="${REPO_ROOT}/${DATA_FILE}"
fi

if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: data file not found: ${DATA_FILE}" >&2
  exit 1
fi

# ── Load and refresh ──────────────────────────────────────────────────────────

echo "Loading ${DATA_FILE} (prefix: ${IDENTITY_PREFIX}) ..."
pnpm tsx "${SCRIPT_DIR}/load-spen-primary.ts" --file "${DATA_FILE}" --prefix "${IDENTITY_PREFIX}"

echo ""
echo "Refreshing materialized view ..."
bash "${SCRIPT_DIR}/refresh-views.sh" --view vw_primary_zones

echo ""
echo "Done. PRIMARY ZONES are ready on the map."
