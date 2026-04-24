#!/usr/bin/env bash
# load-spen-primary-data.sh
# Loads SPEN primary polygon GeoJSON into network_model.object and refreshes the view.
#
# Usage:
#   bash scripts/load-spen-primary-data.sh
#
# DATABASE_URL is read from apps/web/.env.local or the environment.
# Existing records are silently skipped (safe to re-run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_FILE="${REPO_ROOT}/data/SPEN_primary.geojson"

if [[ ! -f "${DATA_FILE}" ]]; then
  echo "ERROR: data file not found: ${DATA_FILE}"
  exit 1
fi

echo "Loading SPEN primary polygons ..."
pnpm tsx "${SCRIPT_DIR}/load-spen-primary.ts"

echo ""
echo "Refreshing materialized view ..."
bash "${SCRIPT_DIR}/refresh-views.sh" --view vw_primary_polygons

echo ""
echo "Done. PRIMARY POLYGONS are ready on the map."
