-- 07_materialized_views.sql
-- Materialized views in the network_views schema.
--
-- Each view is driven by a record in data_dictionary.view_definition and
-- flattens the JSONB attributes column into typed columns based on the
-- attr_definition entries for that class's inheritance lineage.
--
-- Attribute lineage (resolved via recursive CTE at design time):
--   OverheadLine    ← Conductor:  voltage_kv, length_m, cost_data
--   UndergroundCable← Conductor:  voltage_kv, length_m, cost_data
--   PrimarySubstation   ← Substation: voltage_kv, rating_mva, cost_data, status
--   SecondarySubstation ← Substation: voltage_kv, rating_mva, cost_data, status
--
-- Common columns on every view:
--   uuid, namespace, identity, class_name, discriminator,
--   geo_geometry, valid_from, valid_to, hash
--
-- Refresh: use scripts/refresh-views.sh or call REFRESH MATERIALIZED VIEW
-- CONCURRENTLY on each view. Indexes on geo_geometry support CONCURRENTLY.
--
-- Active-record filter (valid_to IS NULL) is baked in — these views always
-- represent the current state of the network. Point-in-time queries use
-- the base network_model.object table directly.

-- ── OVERHEAD LINES ────────────────────────────────────────────────────────────

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
    (o.attributes->>'voltage_kv')::numeric AS voltage_kv,
    (o.attributes->>'length_m')::numeric   AS length_m,
    (o.attributes->>'cost_data')::numeric  AS cost_data
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'OverheadLine'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_overhead_line (uuid);
CREATE INDEX ON network_views.vw_overhead_line USING GIST (geo_geometry);
ANALYZE network_views.vw_overhead_line;

-- ── UNDERGROUND CABLES ────────────────────────────────────────────────────────

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
    (o.attributes->>'voltage_kv')::numeric AS voltage_kv,
    (o.attributes->>'length_m')::numeric   AS length_m,
    (o.attributes->>'cost_data')::numeric  AS cost_data
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'UndergroundCable'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_underground_cable (uuid);
CREATE INDEX ON network_views.vw_underground_cable USING GIST (geo_geometry);
ANALYZE network_views.vw_underground_cable;

-- ── PRIMARY SUBSTATIONS ───────────────────────────────────────────────────────

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
    (o.attributes->>'voltage_kv')::numeric AS voltage_kv,
    (o.attributes->>'rating_mva')::numeric AS rating_mva,
    (o.attributes->>'cost_data')::numeric  AS cost_data,
    (o.attributes->>'status')             AS status
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'PrimarySubstation'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_primary_substation (uuid);
CREATE INDEX ON network_views.vw_primary_substation USING GIST (geo_geometry);
ANALYZE network_views.vw_primary_substation;

-- ── SECONDARY SUBSTATIONS ─────────────────────────────────────────────────────

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
    (o.attributes->>'voltage_kv')::numeric AS voltage_kv,
    (o.attributes->>'rating_mva')::numeric AS rating_mva,
    (o.attributes->>'cost_data')::numeric  AS cost_data,
    (o.attributes->>'status')             AS status
FROM network_model.object o
WHERE o.namespace  = 'ELECTRICITY'
  AND o.class_name = 'SecondarySubstation'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_secondary_substation (uuid);
CREATE INDEX ON network_views.vw_secondary_substation USING GIST (geo_geometry);
ANALYZE network_views.vw_secondary_substation;
