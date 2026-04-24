#!/usr/bin/env bash
# load-ukpn-data.sh
# Loads all UKPN GeoJSON files into network_model.object then refreshes views.
#
# Usage:
#   bash scripts/load-ukpn-data.sh
#
# DATABASE_URL is read from apps/web/.env.local or the environment.
# Existing records are silently skipped (safe to re-run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

load() {
  local file="$1" prefix="$2" class="$3" disc="$4"
  local full_path="${REPO_ROOT}/${file}"
  if [[ ! -f "${full_path}" ]]; then
    echo "SKIP (not found): ${file}"
    return
  fi
  echo ""
  echo "── ${file} ──"
  pnpm tsx "${SCRIPT_DIR}/load-ukpn.ts" \
    --file "${file}" \
    --prefix "${prefix}" \
    --class "${class}" \
    --discriminator "${disc}"
}

# ── Overhead lines ────────────────────────────────────────────────────────────

load "data/ukpn-132kv-overhead-lines.geojson"          UKPN-OHL-132 OverheadLine 132kV
load "data/ukpn-hv-overhead-lines-shapefile.geojson"   UKPN-OHL-33  OverheadLine 33kV
load "data/ukpn-lv-overhead-lines-shapefile.geojson"   UKPN-OHL-415 OverheadLine 415
load "data/ukpn-66kv-overhead-lines-shapefile.geojson" UKPN-OHL-66  OverheadLine 66kV

# ── Poles and towers ──────────────────────────────────────────────────────────

load "data/ukpn-132kv-poles-towers.geojson" UKPN-SUP-132  Support 132kV
load "data/ukpn-hv-poles.geojson"           UKPN-SUP-33   Support 33kV
load "data/ukpn-33kv-poles-towers.geojson"  UKPN-SUP-33B  Support 33kV
load "data/ukpn-lv-poles.geojson"           UKPN-SUP-415  Support 415

# ── Refresh views ─────────────────────────────────────────────────────────────

echo ""
echo "Refreshing materialized views ..."
bash "${SCRIPT_DIR}/refresh-views.sh" --view vw_overhead_line --view vw_supports

echo ""
echo "Done. OVERHEAD LINES and SUPPORTS are ready on the map."
