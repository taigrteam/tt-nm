-- 06_function_sources.sql
-- PostGIS function sources for Martin tile server.
--
-- One function per materialized view in the network_views schema.
-- Martin is configured to auto-discover all functions in network_views.
--
-- Each function accepts (z, x, y, query_params) and returns MVT bytea.
-- The source-layer name in the MVT matches the function/view name so that
-- MapLibre source-layer references in the frontend align automatically.
--
-- Attributes: every tile includes an `attributes` field containing the full
-- JSONB blob from the materialized view, serialised as a JSON string inside
-- the MVT. The frontend inspector parses this string and displays all keys.
--
-- RBAC: disabled for now — the full attributes blob is passed through without
-- filtering. The query_params parameter is kept in all function signatures so
-- role-based redaction can be re-enabled later without changing the Martin
-- config or tile proxy.
--
-- Note: PL/pgSQL function bodies are not validated at CREATE time, so these
-- functions can be created before 07_materialized_views.sql runs.

-- ── vw_overhead_line ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_overhead_line(
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

    SELECT ST_AsMVT(tile, 'vw_overhead_line') INTO result
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
        FROM network_views.vw_overhead_line v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_underground_cable ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_underground_cable(
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

    SELECT ST_AsMVT(tile, 'vw_underground_cable') INTO result
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
        FROM network_views.vw_underground_cable v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_primary_substation ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_primary_substation(
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

    SELECT ST_AsMVT(tile, 'vw_primary_substation') INTO result
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
        FROM network_views.vw_primary_substation v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── vw_secondary_substation ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_secondary_substation(
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

    SELECT ST_AsMVT(tile, 'vw_secondary_substation') INTO result
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
        FROM network_views.vw_secondary_substation v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

-- ── PRIMARY AREAS ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_primary_areas(
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

    SELECT ST_AsMVT(tile, 'vw_primary_areas') INTO result
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
        FROM network_views.vw_primary_areas v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;


-- ── SUPPORTS ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION network_views.vw_supports(
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

    SELECT ST_AsMVT(tile, 'vw_supports') INTO result
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
        FROM network_views.vw_supports v
        WHERE ST_Intersects(v.geo_geometry, ST_Transform(bounds, 4326))
    ) AS tile
    WHERE tile.geom IS NOT NULL;

    RETURN COALESCE(result, ''::bytea);
END;
$$;
