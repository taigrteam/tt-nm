-- 05_seed.sql
-- Development seed data for local testing.
--
-- IAM:  2 roles (admin, viewer), 4 permissions, 1 test user (viewer role).
--
-- Network: Fictional 11kV distribution network, Birmingham area, WGS84.
--
--   PSS-001 (Primary 33kV Substation)
--   ├── OHL-001 ──── SSG-001 ──── SSA-001 (Secondary 11kV, NE)
--   │                              ├── OHL-003 ──── SSI-001 ──── SSC-001 (Secondary 11kV, NW)
--   │                              │                              └── UGC-002 ──── SSL-001 ──── PSS-001 (ring)
--   │                              └── UGC-001 ──── SSK-001 ──── SSE-001 (Secondary 11kV, E)
--   │                                                             └── OHL-005 ──── SSM-001 ──── SSF-001 (Secondary 11kV, far E)
--   ├── OHL-002 ──── SSH-001 ──── SSB-001 (Secondary 11kV, SW)
--   │                              └── OHL-004 ──── SSJ-001 ──── SSD-001 (Secondary 11kV, S)
--
-- 20 objects (substations + conductors), 14 relationships.
-- Object UUIDs: 33333333-0000-4000-8000-00000000000x (stable for test references)
-- Class and attribute natural keys replace all UUID references.
--
-- cost_data is included in attributes to enable RBAC redaction testing.

-- ─── IAM ─────────────────────────────────────────────────────────────────────

INSERT INTO iam.permissions (slug, description) VALUES
  ('map:*',             'Full access to all map layers and attributes'),
  ('map:read',          'Read-only access to network map layers'),
  ('map:tiles:network', 'Access to network topology tile layers'),
  ('map:tiles:cost',    'Access to cost data overlay — restricted to admin role');

INSERT INTO iam.roles (name) VALUES
  ('admin'),
  ('viewer');

-- admin receives all permissions
INSERT INTO iam.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM iam.roles r CROSS JOIN iam.permissions p
WHERE r.name = 'admin';

-- viewer receives network access only — cost data excluded
INSERT INTO iam.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM iam.roles r JOIN iam.permissions p ON TRUE
WHERE r.name = 'viewer'
  AND p.slug IN ('map:read', 'map:tiles:network');

-- Dev test user (will be overwritten by JIT provisioning on real OIDC login)
INSERT INTO iam.users (sub, email, idp_source)
VALUES ('dev-test-sub-001', 'developer@example.com', 'google');

INSERT INTO iam.user_roles (user_id, role_id)
SELECT u.id, r.id
FROM iam.users u JOIN iam.roles r ON r.name = 'viewer'
WHERE u.email = 'developer@example.com';

-- ─── DATA DICTIONARY — NAMESPACE REGISTRY ────────────────────────────────────

INSERT INTO data_dictionary.namespace (namespace, display_name, viewable)
VALUES ('ELECTRICITY', 'ELECTRICITY', TRUE);

-- ─── DATA DICTIONARY — CLASS HIERARCHY ───────────────────────────────────────
-- Insert parents before children (logical self-referential FK checked per-row).

INSERT INTO data_dictionary.class_definition
    (namespace, class_name, parent_namespace, parent_class_name, term_type, is_abstract)
VALUES
  -- Root
  ('ELECTRICITY', 'Asset',               NULL,          NULL,          'OBJECT',       TRUE),

  -- Node branch
  ('ELECTRICITY', 'Node',                'ELECTRICITY', 'Asset',       'OBJECT',       TRUE),
  ('ELECTRICITY', 'Substation',          'ELECTRICITY', 'Node',        'OBJECT',       TRUE),
  ('ELECTRICITY', 'PrimarySubstation',   'ELECTRICITY', 'Substation',  'OBJECT',       FALSE),
  ('ELECTRICITY', 'SecondarySubstation', 'ELECTRICITY', 'Substation',  'OBJECT',       FALSE),
  ('ELECTRICITY', 'Switch',              'ELECTRICITY', 'Node',        'OBJECT',       FALSE),
  ('ELECTRICITY', 'Transformer',         'ELECTRICITY', 'Node',        'OBJECT',       FALSE),

  -- Conductor branch (stored as OBJECT — needs LINESTRING geometry)
  ('ELECTRICITY', 'Conductor',           'ELECTRICITY', 'Asset',       'OBJECT',       TRUE),
  ('ELECTRICITY', 'OverheadLine',        'ELECTRICITY', 'Conductor',   'OBJECT',       FALSE),
  ('ELECTRICITY', 'UndergroundCable',    'ELECTRICITY', 'Conductor',   'OBJECT',       FALSE),

  -- Support branch — poles and towers that carry overhead conductors
  ('ELECTRICITY', 'Support',             'ELECTRICITY', 'Asset',       'OBJECT',       FALSE),

  -- Relationship class (topological edge — no geometry)
  ('ELECTRICITY', 'ConnectedTo',         NULL,          NULL,          'RELATIONSHIP', FALSE);

-- ─── DATA DICTIONARY — ATTRIBUTE CATALOGUE ───────────────────────────────────
-- Attributes are defined at the appropriate class level in the hierarchy.
-- Subclasses inherit attributes from ancestor classes via recursive CTE traversal.
-- A child-class row for the same attribute_name overrides the ancestor's config.

INSERT INTO data_dictionary.attr_definition
    (namespace, class_name, attribute_name, display_name, data_type, is_required)
VALUES
  -- Substation hierarchy attributes (inherited by PrimarySubstation, SecondarySubstation)
  ('ELECTRICITY', 'Substation', 'voltage_kv', 'Voltage (kV)',  'numeric', TRUE),
  ('ELECTRICITY', 'Substation', 'rating_mva', 'Rating (MVA)',  'numeric', FALSE),
  ('ELECTRICITY', 'Substation', 'cost_data',  'Cost Data',     'numeric', FALSE),
  ('ELECTRICITY', 'Substation', 'status',     'Status',        'text',    FALSE),

  -- Conductor hierarchy attributes (inherited by OverheadLine, UndergroundCable)
  ('ELECTRICITY', 'Conductor',  'voltage_kv', 'Voltage (kV)',  'numeric', TRUE),
  ('ELECTRICITY', 'Conductor',  'length_m',   'Length (m)',    'numeric', FALSE),
  ('ELECTRICITY', 'Conductor',  'cost_data',  'Cost Data',     'numeric', FALSE),

  -- Transformer-specific
  ('ELECTRICITY', 'Transformer', 'ratio', 'Ratio', 'text', FALSE);

-- ─── DATA DICTIONARY — VIEW DEFINITIONS ──────────────────────────────────────
-- One record per materialized view layer shown on the map.
-- map_geometry_type: controls MapLibre layer type ('line' | 'circle').
-- map_color:         primary paint colour.
-- map_radius:        circle radius in pixels (circle layers only).
-- map_dashed:        dash pattern applied to line layers.

INSERT INTO data_dictionary.view_definition
    (namespace, view_name, display_name, is_materialized, class_namespace, class_name,
     show_on_map, map_geometry_type, map_color, map_radius, map_dashed)
VALUES
  ('ELECTRICITY', 'vw_overhead_line',        'OVERHEAD LINES',        TRUE, 'ELECTRICITY', 'OverheadLine',       TRUE, 'line',   '#EC6D26', NULL, TRUE),
  ('ELECTRICITY', 'vw_underground_cable',    'UNDERGROUND CABLES',    TRUE, 'ELECTRICITY', 'UndergroundCable',   TRUE, 'line',   '#7B4DB5', NULL, FALSE),
  ('ELECTRICITY', 'vw_primary_substation',   'PRIMARY SUBSTATIONS',   TRUE, 'ELECTRICITY', 'PrimarySubstation',  TRUE, 'circle', '#EC6D26', 10,   FALSE),
  ('ELECTRICITY', 'vw_secondary_substation', 'SECONDARY SUBSTATIONS', TRUE, 'ELECTRICITY', 'SecondarySubstation',TRUE, 'circle', '#0D8C80', 8,    FALSE),
  ('ELECTRICITY', 'vw_supports',             'SUPPORTS',              TRUE, 'ELECTRICITY', 'Support',            TRUE, 'circle', '#78909C', 4,    FALSE);

-- ─── DATA DICTIONARY — VIEW COLUMN SPECS ─────────────────────────────────────

-- Conductor views: voltage_kv, length_m, cost_data
INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
SELECT 'ELECTRICITY', v.view_name, col.source_path, col.alias, col.display_name, col.cast_type
FROM (VALUES
    ('vw_overhead_line'),
    ('vw_underground_cable')
) AS v(view_name)
CROSS JOIN (VALUES
    ('voltage_kv', 'voltage_kv', 'Voltage (kV)', 'numeric'),
    ('length_m',   'length_m',   'Length (m)',   'numeric'),
    ('cost_data',  'cost_data',  'Cost Data',    'numeric')
) AS col(source_path, alias, display_name, cast_type);

-- Substation views: voltage_kv, rating_mva, cost_data, status
INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
SELECT 'ELECTRICITY', v.view_name, col.source_path, col.alias, col.display_name, col.cast_type
FROM (VALUES
    ('vw_primary_substation'),
    ('vw_secondary_substation')
) AS v(view_name)
CROSS JOIN (VALUES
    ('voltage_kv', 'voltage_kv', 'Voltage (kV)', 'numeric'),
    ('rating_mva', 'rating_mva', 'Rating (MVA)', 'numeric'),
    ('cost_data',  'cost_data',  'Cost Data',    'numeric'),
    ('status',     'status',     'Status',       'text')
) AS col(source_path, alias, display_name, cast_type);

-- Support view column specs
INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
VALUES
  ('ELECTRICITY', 'vw_supports', 'dno',            'dno',            'DNO',            'text'),
  ('ELECTRICITY', 'vw_supports', 'route_fl',        'route_fl',        'Route',          'text'),
  ('ELECTRICITY', 'vw_supports', 'asset_ref',       'asset_ref',       'Asset Ref',      'text'),
  ('ELECTRICITY', 'vw_supports', 'local_authority', 'local_authority', 'Local Authority', 'text');

-- ─── DATA DICTIONARY — SPEN PRIMARY ZONES ─────────────────────────────────

INSERT INTO data_dictionary.view_definition
    (namespace, view_name, display_name, is_materialized, class_namespace, class_name,
     show_on_map, map_geometry_type, map_color, map_radius, map_dashed)
VALUES
  ('ELECTRICITY', 'vw_primary_zones', 'PRIMARY ZONES', TRUE, 'ELECTRICITY',
   'PrimaryZone', TRUE, 'fill', '#0D8C80', NULL, FALSE);

INSERT INTO data_dictionary.view_column_spec
    (namespace, view_name, source_path, alias, display_name, cast_type)
VALUES
  ('ELECTRICITY', 'vw_primary_zones', 'objectid',            'objectid',            'Object ID',               'text'),
  ('ELECTRICITY', 'vw_primary_zones', 'primary',             'primary',             'Primary Area',            'text'),
  ('ELECTRICITY', 'vw_primary_zones', 'psgroup',             'psgroup',             'Primary Name',            'text'),
  ('ELECTRICITY', 'vw_primary_zones', 'lv_reading_coverage', 'lv_reading_coverage', 'LV Reading Coverage (%)', 'numeric'),
  ('ELECTRICITY', 'vw_primary_zones', 'geo_point_2d',        'geo_point_2d',        'Geo Point',               'text');

-- ─── NETWORK OBJECTS ─────────────────────────────────────────────────────────
-- All geometry: WGS84, SRID 4326. Coordinates: POINT(longitude latitude).
-- Active records: valid_to IS NULL.
-- hash: MD5 of the attributes JSON string (for ingestion change-detection).
-- Object UUIDs (33333333-...) are retained for stable test cross-references.

-- ── Substations ──────────────────────────────────────────────────────────────

-- Primary substation (PSS-001) — 33kV, central node
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000001',
  'ELECTRICITY', 'PSS-001',
  'PrimarySubstation',
  '33kV',
  ST_SetSRID(ST_MakePoint(-1.9001, 52.4801), 4326),
  '{"voltage_kv": 33, "rating_mva": 40, "cost_data": 850000}',
  md5('{"voltage_kv": 33, "rating_mva": 40, "cost_data": 850000}')
);

-- Secondary substation A (SSA-001) — 11kV, north-east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000002',
  'ELECTRICITY', 'SSA-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8901, 52.4901), 4326),
  '{"voltage_kv": 11, "rating_mva": 5, "cost_data": 120000}',
  md5('{"voltage_kv": 11, "rating_mva": 5, "cost_data": 120000}')
);

-- Secondary substation B (SSB-001) — 11kV, south-west
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000003',
  'ELECTRICITY', 'SSB-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9151, 52.4751), 4326),
  '{"voltage_kv": 11, "rating_mva": 3, "cost_data": 95000}',
  md5('{"voltage_kv": 11, "rating_mva": 3, "cost_data": 95000}')
);

-- Secondary substation C (SSC-001) — 11kV, north-west
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000009',
  'ELECTRICITY', 'SSC-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9201, 52.4901), 4326),
  '{"voltage_kv": 11, "rating_mva": 4, "cost_data": 105000}',
  md5('{"voltage_kv": 11, "rating_mva": 4, "cost_data": 105000}')
);

-- Secondary substation D (SSD-001) — 11kV, south
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000a',
  'ELECTRICITY', 'SSD-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9101, 52.4651), 4326),
  '{"voltage_kv": 11, "rating_mva": 2, "cost_data": 78000}',
  md5('{"voltage_kv": 11, "rating_mva": 2, "cost_data": 78000}')
);

-- Secondary substation E (SSE-001) — 11kV, east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000b',
  'ELECTRICITY', 'SSE-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8751, 52.4851), 4326),
  '{"voltage_kv": 11, "rating_mva": 3, "cost_data": 92000}',
  md5('{"voltage_kv": 11, "rating_mva": 3, "cost_data": 92000}')
);

-- Secondary substation F (SSF-001) — 11kV, far east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000c',
  'ELECTRICITY', 'SSF-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8601, 52.4801), 4326),
  '{"voltage_kv": 11, "rating_mva": 2, "cost_data": 68000}',
  md5('{"voltage_kv": 11, "rating_mva": 2, "cost_data": 68000}')
);

-- ── Secondary substations (co-located at conductor junctions) ─────────────────

-- SSG-001 — between PSS and SSA
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000004',
  'ELECTRICITY', 'SSG-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8951, 52.4851), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}')
);

-- SSH-001 — between PSS and SSB
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000005',
  'ELECTRICITY', 'SSH-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9071, 52.4771), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}')
);

-- SSI-001 — between SSA and SSC
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000d',
  'ELECTRICITY', 'SSI-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9051, 52.4921), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}')
);

-- SSJ-001 — between SSB and SSD
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000e',
  'ELECTRICITY', 'SSJ-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9131, 52.4701), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}')
);

-- SSK-001 — between SSA and SSE
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000f',
  'ELECTRICITY', 'SSK-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8821, 52.4871), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 43000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 43000}')
);

-- SSL-001 — between SSC and PSS (ring feeder)
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000010',
  'ELECTRICITY', 'SSL-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9121, 52.4861), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 44000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 44000}')
);

-- SSM-001 — between SSE and SSF
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000011',
  'ELECTRICITY', 'SSM-001',
  'SecondarySubstation',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8671, 52.4831), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 41000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 41000}')
);

-- ── Overhead Lines ───────────────────────────────────────────────────────────

-- OHL-001 — PSS → SSG → SSA
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000006',
  'ELECTRICITY', 'OHL-001',
  'OverheadLine',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.9001, 52.4801),
    ST_MakePoint(-1.8951, 52.4851),
    ST_MakePoint(-1.8901, 52.4901)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1420, "cost_data": 28400}',
  md5('{"voltage_kv": 11, "length_m": 1420, "cost_data": 28400}')
);

-- OHL-002 — PSS → SSH → SSB
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000007',
  'ELECTRICITY', 'OHL-002',
  'OverheadLine',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.9001, 52.4801),
    ST_MakePoint(-1.9071, 52.4771),
    ST_MakePoint(-1.9151, 52.4751)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1650, "cost_data": 33000}',
  md5('{"voltage_kv": 11, "length_m": 1650, "cost_data": 33000}')
);

-- OHL-003 — SSA → SSI → SSC
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000012',
  'ELECTRICITY', 'OHL-003',
  'OverheadLine',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.8901, 52.4901),
    ST_MakePoint(-1.9051, 52.4921),
    ST_MakePoint(-1.9201, 52.4901)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 2180, "cost_data": 43600}',
  md5('{"voltage_kv": 11, "length_m": 2180, "cost_data": 43600}')
);

-- OHL-004 — SSB → SSJ → SSD
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000013',
  'ELECTRICITY', 'OHL-004',
  'OverheadLine',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.9151, 52.4751),
    ST_MakePoint(-1.9131, 52.4701),
    ST_MakePoint(-1.9101, 52.4651)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1180, "cost_data": 23600}',
  md5('{"voltage_kv": 11, "length_m": 1180, "cost_data": 23600}')
);

-- OHL-005 — SSE → SSM → SSF
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000016',
  'ELECTRICITY', 'OHL-005',
  'OverheadLine',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.8751, 52.4851),
    ST_MakePoint(-1.8671, 52.4831),
    ST_MakePoint(-1.8601, 52.4801)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1250, "cost_data": 25000}',
  md5('{"voltage_kv": 11, "length_m": 1250, "cost_data": 25000}')
);

-- ── Underground Cables ───────────────────────────────────────────────────────

-- UGC-001 — SSA → SSK → SSE (urban section)
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000014',
  'ELECTRICITY', 'UGC-001',
  'UndergroundCable',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.8901, 52.4901),
    ST_MakePoint(-1.8821, 52.4871),
    ST_MakePoint(-1.8751, 52.4851)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1340, "cost_data": 67000}',
  md5('{"voltage_kv": 11, "length_m": 1340, "cost_data": 67000}')
);

-- UGC-002 — SSC → SSL → PSS (ring feeder completion)
INSERT INTO network_model.object
    (uuid, namespace, identity, class_name, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000015',
  'ELECTRICITY', 'UGC-002',
  'UndergroundCable',
  NULL,
  ST_SetSRID(ST_MakeLine(ARRAY[
    ST_MakePoint(-1.9201, 52.4901),
    ST_MakePoint(-1.9121, 52.4861),
    ST_MakePoint(-1.9001, 52.4801)
  ]), 4326),
  '{"voltage_kv": 11, "length_m": 1680, "cost_data": 84000}',
  md5('{"voltage_kv": 11, "length_m": 1680, "cost_data": 84000}')
);

-- ─── RELATIONSHIPS ────────────────────────────────────────────────────────────
-- Topological edges (functional flow direction: source → target).

INSERT INTO network_model.relationship
    (source_uuid, target_uuid, class_namespace, class_name, relationship_type)
VALUES
  -- PSS-001 → SSG-001
  ('33333333-0000-4000-8000-000000000001',
   '33333333-0000-4000-8000-000000000004',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSG-001 → SSA-001
  ('33333333-0000-4000-8000-000000000004',
   '33333333-0000-4000-8000-000000000002',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- PSS-001 → SSH-001
  ('33333333-0000-4000-8000-000000000001',
   '33333333-0000-4000-8000-000000000005',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSH-001 → SSB-001
  ('33333333-0000-4000-8000-000000000005',
   '33333333-0000-4000-8000-000000000003',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSA-001 → SSI-001
  ('33333333-0000-4000-8000-000000000002',
   '33333333-0000-4000-8000-00000000000d',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSI-001 → SSC-001
  ('33333333-0000-4000-8000-00000000000d',
   '33333333-0000-4000-8000-000000000009',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSB-001 → SSJ-001
  ('33333333-0000-4000-8000-000000000003',
   '33333333-0000-4000-8000-00000000000e',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSJ-001 → SSD-001
  ('33333333-0000-4000-8000-00000000000e',
   '33333333-0000-4000-8000-00000000000a',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSA-001 → SSK-001
  ('33333333-0000-4000-8000-000000000002',
   '33333333-0000-4000-8000-00000000000f',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSK-001 → SSE-001
  ('33333333-0000-4000-8000-00000000000f',
   '33333333-0000-4000-8000-00000000000b',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSC-001 → SSL-001 (ring feeder)
  ('33333333-0000-4000-8000-000000000009',
   '33333333-0000-4000-8000-000000000010',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSL-001 → PSS-001 (ring feeder completion)
  ('33333333-0000-4000-8000-000000000010',
   '33333333-0000-4000-8000-000000000001',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSE-001 → SSM-001
  ('33333333-0000-4000-8000-00000000000b',
   '33333333-0000-4000-8000-000000000011',
   'ELECTRICITY', 'ConnectedTo', 'edge'),

  -- SSM-001 → SSF-001
  ('33333333-0000-4000-8000-000000000011',
   '33333333-0000-4000-8000-00000000000c',
   'ELECTRICITY', 'ConnectedTo', 'edge');
