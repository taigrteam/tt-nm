#!/usr/bin/env bash
# load-highways-data.sh
# Loads National Highways GeoJSON (links + nodes) into network_model.object.
# Runs the TypeScript loader twice — once for links, once for nodes.
#
# Usage:
#   bash scripts/load-highways-data.sh
#
# DATABASE_URL is read from apps/web/.env.local or the environment.
# Existing records are silently skipped (safe to re-run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${REPO_ROOT}/data"

LINKS_FILE="${DATA_DIR}/all-links.geojson"
NODES_FILE="${DATA_DIR}/all-nodes.geojson"

for f in "${LINKS_FILE}" "${NODES_FILE}"; do
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: data file not found: ${f}"
    exit 1
  fi
done

echo "Loading highway links ..."
pnpm tsx "${SCRIPT_DIR}/load-highways.ts" --link "${LINKS_FILE}"

echo ""
echo "Loading highway nodes ..."
pnpm tsx "${SCRIPT_DIR}/load-highways.ts" --node "${NODES_FILE}"

echo ""
echo "Done. Refreshing materialized views ..."
bash "${SCRIPT_DIR}/refresh-views.sh" --namespace HIGHWAYS

echo ""
echo "✓ Highways data loaded and views refreshed."
