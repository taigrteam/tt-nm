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
-- RBAC: the `user_role` key in query_params controls cost_data redaction.
-- The tile proxy injects this from the server-side session — never from the client.
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
    bounds    geometry;
    user_role text;
    result    bytea;
BEGIN
    user_role := COALESCE(query_params->>'user_role', 'viewer');
    IF user_role NOT IN ('admin', 'viewer') THEN
        user_role := 'viewer';
    END IF;

    bounds := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'vw_overhead_line') INTO result
    FROM (
        SELECT
            v.uuid::text                         AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.voltage_kv,
            v.length_m,
            CASE WHEN user_role = 'admin' THEN v.cost_data ELSE NULL END AS cost_data,
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
    bounds    geometry;
    user_role text;
    result    bytea;
BEGIN
    user_role := COALESCE(query_params->>'user_role', 'viewer');
    IF user_role NOT IN ('admin', 'viewer') THEN
        user_role := 'viewer';
    END IF;

    bounds := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'vw_underground_cable') INTO result
    FROM (
        SELECT
            v.uuid::text                         AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.voltage_kv,
            v.length_m,
            CASE WHEN user_role = 'admin' THEN v.cost_data ELSE NULL END AS cost_data,
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
    bounds    geometry;
    user_role text;
    result    bytea;
BEGIN
    user_role := COALESCE(query_params->>'user_role', 'viewer');
    IF user_role NOT IN ('admin', 'viewer') THEN
        user_role := 'viewer';
    END IF;

    bounds := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'vw_primary_substation') INTO result
    FROM (
        SELECT
            v.uuid::text                         AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.voltage_kv,
            v.rating_mva,
            v.status,
            CASE WHEN user_role = 'admin' THEN v.cost_data ELSE NULL END AS cost_data,
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
    bounds    geometry;
    user_role text;
    result    bytea;
BEGIN
    user_role := COALESCE(query_params->>'user_role', 'viewer');
    IF user_role NOT IN ('admin', 'viewer') THEN
        user_role := 'viewer';
    END IF;

    bounds := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'vw_secondary_substation') INTO result
    FROM (
        SELECT
            v.uuid::text                         AS id,
            v.identity,
            v.class_name,
            v.discriminator,
            v.voltage_kv,
            v.rating_mva,
            v.status,
            CASE WHEN user_role = 'admin' THEN v.cost_data ELSE NULL END AS cost_data,
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
