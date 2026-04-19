-- 08_highways.sql
-- Materialised views, tile functions, and data-dictionary entries for the
-- National Highways (HIGHWAYS) namespace.
--
-- Sections:
--   I.   data_dictionary — namespace + view_definition + view_column_spec
--   II.  network_views   — CREATE MATERIALIZED VIEW (8 views)
--   III. network_views   — CREATE FUNCTION tile sources for Martin (8 functions)
--
-- Drop/recreate pattern is used so this file is safe to re-run against a live DB.
-- Functions use CREATE OR REPLACE; views use DROP … IF EXISTS CASCADE then CREATE.
--
-- Colours (Standard UK highway palette):
--   Motorways     #0070C0   Nodes (all types)  #0D8C80
--   A roads       #00703C
--   B roads       #F0A500
--   Unclassified  #888888

-- ─── I. DATA DICTIONARY ───────────────────────────────────────────────────────

INSERT INTO data_dictionary.namespace (namespace, display_name, viewable)
VALUES ('HIGHWAYS', 'National Highways', TRUE)
ON CONFLICT (namespace) DO NOTHING;

INSERT INTO data_dictionary.view_definition
    (namespace, view_name, display_name, is_materialized,
     class_namespace, class_name, discriminator_filter,
     show_on_map, map_geometry_type, map_color, map_radius, map_dashed)
VALUES
  ('HIGHWAYS', 'vw_motorways',          'MOTORWAYS',       TRUE, 'HIGHWAYS', 'Link', 'M',  TRUE, 'line',   '#0070C0', NULL, FALSE),
  ('HIGHWAYS', 'vw_a_roads',            'A ROADS',         TRUE, 'HIGHWAYS', 'Link', 'A',  TRUE, 'line',   '#00703C', NULL, FALSE),
  ('HIGHWAYS', 'vw_b_roads',            'B ROADS',         TRUE, 'HIGHWAYS', 'Link', 'B',  TRUE, 'line',   '#F0A500', NULL, FALSE),
  ('HIGHWAYS', 'vw_unclassified_roads', 'U ROADS',         TRUE, 'HIGHWAYS', 'Link', 'U',  TRUE, 'line',   '#888888', NULL, FALSE),
  ('HIGHWAYS', 'vw_junction',           'JUNCTIONS',       TRUE, 'HIGHWAYS', 'Node', 'J',  TRUE, 'circle', '#0D8C80', 6,    FALSE),
  ('HIGHWAYS', 'vw_property_change',    'PROPERTY CHANGE', TRUE, 'HIGHWAYS', 'Node', 'P',  TRUE, 'circle', '#0D8C80', 6,    FALSE),
  ('HIGHWAYS', 'vw_reference',          'REFERENCE',       TRUE, 'HIGHWAYS', 'Node', 'R',  TRUE, 'circle', '#0D8C80', 6,    FALSE),
  ('HIGHWAYS', 'vw_road_end',           'ROAD END',        TRUE, 'HIGHWAYS', 'Node', 'RE', TRUE, 'circle', '#0D8C80', 6,    FALSE)
ON CONFLICT DO NOTHING;

-- Link view columns (roadname through operationalstate)
INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
SELECT
    'HIGHWAYS',
    v.view_name,
    col.source_path,
    col.alias,
    col.display_name,
    col.cast_type
FROM (VALUES
    ('vw_motorways'),
    ('vw_a_roads'),
    ('vw_b_roads'),
    ('vw_unclassified_roads')
) AS v(view_name)
CROSS JOIN (VALUES
    ('roadname',        'roadname',        'Road Name',        'text'),
    ('linkref',         'linkref',         'Link Ref',         'text'),
    ('linkcategory',    'linkcategory',    'Category',         'text'),
    ('linkdesc',        'linkdesc',        'Description',      'text'),
    ('direction',       'direction',       'Direction',        'text'),
    ('numberoflanes',   'numberoflanes',   'Lanes',            'numeric'),
    ('operationalstate','operationalstate','State',            'text')
) AS col(source_path, alias, display_name, cast_type);

-- Node view columns (nodetype, toid, startdate)
INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
SELECT
    'HIGHWAYS',
    v.view_name,
    col.source_path,
    col.alias,
    col.display_name,
    col.cast_type
FROM (VALUES
    ('vw_junction'),
    ('vw_property_change'),
    ('vw_reference'),
    ('vw_road_end')
) AS v(view_name)
CROSS JOIN (VALUES
    ('nodetype',  'nodetype',  'Node Type',  'text'),
    ('toid',      'toid',      'TOID',       'text'),
    ('startdate', 'startdate', 'Start Date', 'text')
) AS col(source_path, alias, display_name, cast_type);

-- ─── II. MATERIALISED VIEWS ───────────────────────────────────────────────────
--
-- Each view stores a single `attributes JSONB` column — a direct copy of
-- network_model.object.attributes. No per-class typed columns are present.
-- The tile function serialises attributes as a JSON string inside the MVT;
-- the frontend inspector parses it and renders all keys.
-- Active-record filter (valid_to IS NULL) is baked in.
-- GIST index on geo_geometry is required for CONCURRENTLY refresh and tile queries.

-- ── vw_motorways ──────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_motorways CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_motorways AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Link'
  AND o.discriminator = 'M'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_motorways (uuid);
CREATE INDEX ON network_views.vw_motorways USING GIST (geo_geometry);
ANALYZE network_views.vw_motorways;

-- ── vw_a_roads ────────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_a_roads CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_a_roads AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Link'
  AND o.discriminator = 'A'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_a_roads (uuid);
CREATE INDEX ON network_views.vw_a_roads USING GIST (geo_geometry);
ANALYZE network_views.vw_a_roads;

-- ── vw_b_roads ────────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_b_roads CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_b_roads AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Link'
  AND o.discriminator = 'B'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_b_roads (uuid);
CREATE INDEX ON network_views.vw_b_roads USING GIST (geo_geometry);
ANALYZE network_views.vw_b_roads;

-- ── vw_unclassified_roads ─────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_unclassified_roads CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_unclassified_roads AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Link'
  AND o.discriminator = 'U'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_unclassified_roads (uuid);
CREATE INDEX ON network_views.vw_unclassified_roads USING GIST (geo_geometry);
ANALYZE network_views.vw_unclassified_roads;

-- ── vw_junction ───────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_junction CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_junction AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Node'
  AND o.discriminator = 'J'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_junction (uuid);
CREATE INDEX ON network_views.vw_junction USING GIST (geo_geometry);
ANALYZE network_views.vw_junction;

-- ── vw_property_change ────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_property_change CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_property_change AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Node'
  AND o.discriminator = 'P'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_property_change (uuid);
CREATE INDEX ON network_views.vw_property_change USING GIST (geo_geometry);
ANALYZE network_views.vw_property_change;

-- ── vw_reference ──────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_reference CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_reference AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Node'
  AND o.discriminator = 'R'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_reference (uuid);
CREATE INDEX ON network_views.vw_reference USING GIST (geo_geometry);
ANALYZE network_views.vw_reference;

-- ── vw_road_end ───────────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS network_views.vw_road_end CASCADE;

CREATE MATERIALIZED VIEW network_views.vw_road_end AS
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
WHERE o.namespace    = 'HIGHWAYS'
  AND o.class_name   = 'Node'
  AND o.discriminator = 'RE'
  AND o.valid_to IS NULL;

CREATE UNIQUE INDEX ON network_views.vw_road_end (uuid);
CREATE INDEX ON network_views.vw_road_end USING GIST (geo_geometry);
ANALYZE network_views.vw_road_end;

-- ─── III. MARTIN TILE FUNCTIONS ───────────────────────────────────────────────
--
-- One function per view. Signature matches Martin's expected interface:
--   (z integer, x integer, y integer, query_params json) RETURNS bytea
--
-- query_params is accepted for API compatibility but not used — HIGHWAYS data
-- has no role-gated fields. The full attributes JSONB blob is passed through;
-- PostGIS serialises it as a JSON text string inside the MVT.
--
-- source-layer name in ST_AsMVT matches the function name so MapLibre
-- source-layer references align automatically.

-- ── vw_motorways ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_motorways(
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

    SELECT ST_AsMVT(tile, 'vw_motorways') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_motorways v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_a_roads ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_a_roads(
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

    SELECT ST_AsMVT(tile, 'vw_a_roads') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_a_roads v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_b_roads ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_b_roads(
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

    SELECT ST_AsMVT(tile, 'vw_b_roads') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_b_roads v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_unclassified_roads ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_unclassified_roads(
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

    SELECT ST_AsMVT(tile, 'vw_unclassified_roads') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_unclassified_roads v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_junction ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_junction(
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

    SELECT ST_AsMVT(tile, 'vw_junction') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_junction v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_property_change ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_property_change(
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

    SELECT ST_AsMVT(tile, 'vw_property_change') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_property_change v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_reference ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_reference(
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

    SELECT ST_AsMVT(tile, 'vw_reference') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_reference v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_road_end ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_road_end(
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

    SELECT ST_AsMVT(tile, 'vw_road_end') INTO result
    FROM (
        SELECT
            v.uuid::text  AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.attributes #>> '{}' AS attributes,
            ST_AsMVTGeom(
                ST_Transform(v.geo_geometry, 3857),
                bounds
            ) AS geom
        FROM network_views.vw_road_end v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;
