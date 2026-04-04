-- 06_function_sources.sql
-- PostGIS function sources for Martin tile server.
--
-- Each function accepts (z, x, y, query_params) and returns MVT bytea.
-- Martin auto-discovers these when configured to scan the network_model schema.
--
-- RBAC: the `user_role` key in query_params controls attribute redaction.
-- The tile proxy injects this from the server-side session — never from the client.

SET search_path TO network_model, public;

CREATE OR REPLACE FUNCTION network_objects(
    z integer,
    x integer,
    y integer,
    query_params json DEFAULT '{}'::json
)
RETURNS bytea
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
    bounds geometry;
    user_role text;
    result bytea;
BEGIN
    -- Role is injected by the Next.js tile proxy from the server-side session.
    -- Validate against known roles; unknown values fall back to viewer.
    user_role := COALESCE(query_params->>'user_role', 'viewer');
    IF user_role NOT IN ('admin', 'viewer') THEN
        user_role := 'viewer';
    END IF;

    -- Tile envelope in EPSG:3857 (Web Mercator).
    bounds := ST_TileEnvelope(z, x, y);

    IF user_role = 'admin' THEN
        -- Admin: full attributes including cost_data.
        SELECT ST_AsMVT(tile, 'network_objects') INTO result
        FROM (
            SELECT
                o.uuid::text                          AS id,
                o.identity,
                o.discriminator,
                cd.name                               AS class_name,
                (o.attributes->>'voltage_kv')::float  AS voltage_kv,
                (o.attributes->>'rating_mva')::float  AS rating_mva,
                (o.attributes->>'status')             AS status,
                (o.attributes->>'length_m')::float    AS length_m,
                (o.attributes->>'cost_data')::float   AS cost_data,
                ST_AsMVTGeom(
                    ST_Transform(o.geo_geometry, 3857),
                    bounds
                ) AS geom
            FROM network_model.object o
            JOIN network_model.class_definition cd
              ON cd.class_uuid = o.class_uuid
            WHERE o.valid_to IS NULL
              AND cd.valid_to IS NULL
              AND ST_Intersects(
                    o.geo_geometry,
                    ST_Transform(bounds, 4326)
                  )
        ) AS tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        -- Viewer (and any unknown role): cost_data is redacted.
        SELECT ST_AsMVT(tile, 'network_objects') INTO result
        FROM (
            SELECT
                o.uuid::text                          AS id,
                o.identity,
                o.discriminator,
                cd.name                               AS class_name,
                (o.attributes->>'voltage_kv')::float  AS voltage_kv,
                (o.attributes->>'rating_mva')::float  AS rating_mva,
                (o.attributes->>'status')             AS status,
                (o.attributes->>'length_m')::float    AS length_m,
                ST_AsMVTGeom(
                    ST_Transform(o.geo_geometry, 3857),
                    bounds
                ) AS geom
            FROM network_model.object o
            JOIN network_model.class_definition cd
              ON cd.class_uuid = o.class_uuid
            WHERE o.valid_to IS NULL
              AND cd.valid_to IS NULL
              AND ST_Intersects(
                    o.geo_geometry,
                    ST_Transform(bounds, 4326)
                  )
        ) AS tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN COALESCE(result, ''::bytea);
END;
$$;

RESET search_path;
