-- 10_neso_gsp_zones.sql
-- NESO GSP (Grid Supply Point) region data: data_dictionary, materialized view, and Martin tile function.
--
-- Data source: NESO GSP Regions 4326 20251204.
-- Data loaded via: tsx scripts/load-neso-gsp-zones.ts
-- Namespace: ELECTRICITY.
--
-- Sections:
--   I.   data_dictionary — class, attributes, view definition, column specs
--   II.  network_views   — materialized view (DROP/CREATE pattern — safe to re-run)
--   III. network_views   — Martin tile function (CREATE OR REPLACE)

-- ─── I. DATA DICTIONARY ───────────────────────────────────────────────────────

-- No namespace INSERT needed — ELECTRICITY is already registered in 05_seed.sql.

INSERT INTO data_dictionary.class_definition
    (namespace, class_name, parent_namespace, parent_class_name, term_type, is_abstract)
VALUES
  ('ELECTRICITY', 'GSPZone', NULL, NULL, 'OBJECT', FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO data_dictionary.attr_definition
    (namespace, class_name, attribute_name, display_name, data_type, is_required)
VALUES
  ('ELECTRICITY', 'GSPZone', 'GSPs',     'GSP Code',  'text', FALSE),
  ('ELECTRICITY', 'GSPZone', 'GSPGroup', 'GSP Group', 'text', FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO data_dictionary.view_definition
    (namespace, view_name, display_name, is_materialized,
     class_namespace, class_name,
     show_on_map, map_geometry_type, map_color, map_radius, map_dashed)
VALUES
  ('ELECTRICITY', 'vw_gsp_zones', 'GSP ZONES', TRUE,
   'ELECTRICITY', 'GSPZone',
   TRUE, 'fill', '#6C3483', NULL, FALSE)
ON CONFLICT DO NOTHING;

-- view_column_spec has no unique constraint — delete before re-inserting to stay idempotent
DELETE FROM data_dictionary.view_column_spec
WHERE namespace = 'ELECTRICITY' AND view_name = 'vw_gsp_zones' AND valid_to IS NULL;

INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
VALUES
  ('ELECTRICITY', 'vw_gsp_zones', 'GSPs',     'gsps',      'GSP Code',  'text'),
  ('ELECTRICITY', 'vw_gsp_zones', 'GSPGroup', 'gsp_group', 'GSP Group', 'text');

-- ─── II. MATERIALIZED VIEW ────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_gsp_zones CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_gsp_zones AS
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
  AND o.class_name = 'GSPZone'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_gsp_zones (uuid);
CREATE INDEX ON network_views.vw_gsp_zones USING GIST (geo_geometry);
ANALYZE network_views.vw_gsp_zones;

-- ─── III. MARTIN TILE FUNCTION ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_gsp_zones(
    z            integer,
    x            integer,
    y            integer,
    query_params json DEFAULT '{}'::json
)
RETURNS bytea
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
    bounds  geometry;
    result  bytea;
BEGIN
    bounds := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'vw_gsp_zones') INTO result
    FROM (
        SELECT
            v.uuid::text        AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes::text  AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_gsp_zones v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;
