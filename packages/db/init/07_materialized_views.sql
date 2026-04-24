-- 07_materialized_views.sql
-- Materialized views in the network_views schema.
--
-- Every view exposes the standard identity columns plus a single `attributes JSONB`
-- column that is a direct copy of network_model.object.attributes.
-- No per-class typed columns are present — the tile function serialises `attributes`
-- as a JSON string inside the MVT, and the frontend inspector renders all keys,
-- using data_dictionary.view_column_spec display_name values where registered.
--
-- RBAC: cost_data is a sensitive field in the ELECTRICITY namespace.
-- It is NOT stripped here (the full blob is stored in the view) — the tile
-- function applies the CASE WHEN user_role = 'admin' logic at serve time.
--
-- Common columns on every view:
--   uuid, namespace, identity, class_name, discriminator,
--   geo_geometry, valid_from, valid_to, hash, attributes
--
-- Refresh: scripts/refresh-views.sh or REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- Drop/recreate is used so this file is safe to re-run against a live DB.

-- ── OVERHEAD LINES ────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_overhead_line CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_overhead_line AS
SELECT
    o.uuid,
    o.namespace,
    o.identity,
    o.class_name,
    o.discriminator,
    o.geo_geometry,
    o.valid_from,
    o.valid_to,
    o.hash,
    o.attributes
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'OverheadLine'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_overhead_line (uuid);
CREATE INDEX ON network_views.vw_overhead_line USING GIST (geo_geometry);
ANALYZE network_views.vw_overhead_line;

-- ── UNDERGROUND CABLES ────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_underground_cable CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_underground_cable AS
SELECT
    o.uuid,
    o.namespace,
    o.identity,
    o.class_name,
    o.discriminator,
    o.geo_geometry,
    o.valid_from,
    o.valid_to,
    o.hash,
    o.attributes
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'UndergroundCable'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_underground_cable (uuid);
CREATE INDEX ON network_views.vw_underground_cable USING GIST (geo_geometry);
ANALYZE network_views.vw_underground_cable;

-- ── PRIMARY AREAS ─────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_primary_areas CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_primary_areas AS
SELECT
    o.uuid,
    o.namespace,
    o.identity,
    o.class_name,
    o.discriminator,
    o.geo_geometry,
    o.valid_from,
    o.valid_to,
    o.hash,
    o.attributes
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'PrimaryArea'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_primary_areas (uuid);
CREATE INDEX ON network_views.vw_primary_areas USING GIST (geo_geometry);
ANALYZE network_views.vw_primary_areas;

-- ── PRIMARY SUBSTATIONS ───────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_primary_substation CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_primary_substation AS
SELECT
    o.uuid,
    o.namespace,
    o.identity,
    o.class_name,
    o.discriminator,
    o.geo_geometry,
    o.valid_from,
    o.valid_to,
    o.hash,
    o.attributes
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'PrimarySubstation'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_primary_substation (uuid);
CREATE INDEX ON network_views.vw_primary_substation USING GIST (geo_geometry);
ANALYZE network_views.vw_primary_substation;

-- ── SECONDARY SUBSTATIONS ─────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_secondary_substation CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_secondary_substation AS
SELECT
    o.uuid,
    o.namespace,
    o.identity,
    o.class_name,
    o.discriminator,
    o.geo_geometry,
    o.valid_from,
    o.valid_to,
    o.hash,
    o.attributes
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'SecondarySubstation'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_secondary_substation (uuid);
CREATE INDEX ON network_views.vw_secondary_substation USING GIST (geo_geometry);
ANALYZE network_views.vw_secondary_substation;
