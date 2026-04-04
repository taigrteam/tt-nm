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
-- UUIDs are hardcoded for stable cross-references in tests and Phase 6 queries.
-- Class UUIDs:  11111111-0000-4000-8000-00000000000x
-- Attr UUIDs:   22222222-0000-4000-8000-00000000000x
-- Object UUIDs: 33333333-0000-4000-8000-00000000000x
--
-- cost_data is included in attributes to enable RBAC redaction testing (Phase 6).

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

-- ─── DATA DICTIONARY ─────────────────────────────────────────────────────────
-- Insert parents before children (self-referential FK checked per-row).

INSERT INTO network_model.class_definition
    (class_uuid, parent_class_uuid, namespace, name, term_type, is_abstract)
VALUES
  -- Root
  ('11111111-0000-4000-8000-000000000001', NULL,
   'ELEC', 'Asset', 'OBJECT', TRUE),

  -- Node branch
  ('11111111-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000001',
   'ELEC', 'Node', 'OBJECT', TRUE),
  ('11111111-0000-4000-8000-000000000003', '11111111-0000-4000-8000-000000000002',
   'ELEC', 'Substation', 'OBJECT', TRUE),
  ('11111111-0000-4000-8000-000000000009', '11111111-0000-4000-8000-000000000003',
   'ELEC', 'PrimarySubstation', 'OBJECT', FALSE),
  ('11111111-0000-4000-8000-00000000000a', '11111111-0000-4000-8000-000000000003',
   'ELEC', 'SecondarySubstation', 'OBJECT', FALSE),
  ('11111111-0000-4000-8000-000000000004', '11111111-0000-4000-8000-000000000002',
   'ELEC', 'Switch', 'OBJECT', FALSE),
  ('11111111-0000-4000-8000-000000000007', '11111111-0000-4000-8000-000000000002',
   'ELEC', 'Transformer', 'OBJECT', FALSE),

  -- Conductor branch (stored as OBJECT — needs LINESTRING geometry)
  ('11111111-0000-4000-8000-000000000005', '11111111-0000-4000-8000-000000000001',
   'ELEC', 'Conductor', 'OBJECT', TRUE),
  ('11111111-0000-4000-8000-000000000006', '11111111-0000-4000-8000-000000000005',
   'ELEC', 'OverheadLine', 'OBJECT', FALSE),
  ('11111111-0000-4000-8000-000000000008', '11111111-0000-4000-8000-000000000005',
   'ELEC', 'UndergroundCable', 'OBJECT', FALSE),

  -- Relationship class (topological edge — no geometry)
  ('11111111-0000-4000-8000-000000000010', NULL,
   'ELEC', 'ConnectedTo', 'RELATIONSHIP', FALSE);

INSERT INTO network_model.attribute_definition
    (attr_uuid, namespace, name, data_type)
VALUES
  ('22222222-0000-4000-8000-000000000001', 'ELEC', 'voltage_kv', 'numeric'),
  ('22222222-0000-4000-8000-000000000002', 'ELEC', 'rating_mva', 'numeric'),
  ('22222222-0000-4000-8000-000000000003', 'ELEC', 'status',     'text'),
  ('22222222-0000-4000-8000-000000000004', 'ELEC', 'length_m',   'numeric'),
  ('22222222-0000-4000-8000-000000000005', 'ELEC', 'cost_data',  'numeric'),
  ('22222222-0000-4000-8000-000000000006', 'ELEC', 'ratio',      'text');

-- ─── NETWORK OBJECTS ─────────────────────────────────────────────────────────
-- All geometry: WGS84, SRID 4326. Coordinates: POINT(longitude latitude).
-- Active records: valid_to IS NULL.
-- hash: MD5 of the attributes JSON string (for ingestion change-detection).

-- ── Substations ──────────────────────────────────────────────────────────────

-- Primary substation (PSS-001) — 33kV, central node
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000001',
  'ELEC', 'PSS-001',
  '11111111-0000-4000-8000-000000000009',
  '33kV',
  ST_SetSRID(ST_MakePoint(-1.9001, 52.4801), 4326),
  '{"voltage_kv": 33, "rating_mva": 40, "cost_data": 850000}',
  md5('{"voltage_kv": 33, "rating_mva": 40, "cost_data": 850000}')
);

-- Secondary substation A (SSA-001) — 11kV, north-east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000002',
  'ELEC', 'SSA-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8901, 52.4901), 4326),
  '{"voltage_kv": 11, "rating_mva": 5, "cost_data": 120000}',
  md5('{"voltage_kv": 11, "rating_mva": 5, "cost_data": 120000}')
);

-- Secondary substation B (SSB-001) — 11kV, south-west
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000003',
  'ELEC', 'SSB-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9151, 52.4751), 4326),
  '{"voltage_kv": 11, "rating_mva": 3, "cost_data": 95000}',
  md5('{"voltage_kv": 11, "rating_mva": 3, "cost_data": 95000}')
);

-- Secondary substation C (SSC-001) — 11kV, north-west
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000009',
  'ELEC', 'SSC-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9201, 52.4901), 4326),
  '{"voltage_kv": 11, "rating_mva": 4, "cost_data": 105000}',
  md5('{"voltage_kv": 11, "rating_mva": 4, "cost_data": 105000}')
);

-- Secondary substation D (SSD-001) — 11kV, south
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000a',
  'ELEC', 'SSD-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9101, 52.4651), 4326),
  '{"voltage_kv": 11, "rating_mva": 2, "cost_data": 78000}',
  md5('{"voltage_kv": 11, "rating_mva": 2, "cost_data": 78000}')
);

-- Secondary substation E (SSE-001) — 11kV, east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000b',
  'ELEC', 'SSE-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8751, 52.4851), 4326),
  '{"voltage_kv": 11, "rating_mva": 3, "cost_data": 92000}',
  md5('{"voltage_kv": 11, "rating_mva": 3, "cost_data": 92000}')
);

-- Secondary substation F (SSF-001) — 11kV, far east
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000c',
  'ELEC', 'SSF-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8601, 52.4801), 4326),
  '{"voltage_kv": 11, "rating_mva": 2, "cost_data": 68000}',
  md5('{"voltage_kv": 11, "rating_mva": 2, "cost_data": 68000}')
);

-- ── Secondary substations (formerly switches — co-located at conductor junctions) ─

-- SSG-001 — between PSS and SSA
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000004',
  'ELEC', 'SSG-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8951, 52.4851), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}')
);

-- SSH-001 — between PSS and SSB
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000005',
  'ELEC', 'SSH-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9071, 52.4771), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 45000}')
);

-- SSI-001 — between SSA and SSC
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000d',
  'ELEC', 'SSI-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9051, 52.4921), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}')
);

-- SSJ-001 — between SSB and SSD
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000e',
  'ELEC', 'SSJ-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9131, 52.4701), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 42000}')
);

-- SSK-001 — between SSA and SSE
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-00000000000f',
  'ELEC', 'SSK-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8821, 52.4871), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 43000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 43000}')
);

-- SSL-001 — between SSC and PSS (ring feeder)
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000010',
  'ELEC', 'SSL-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.9121, 52.4861), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 44000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 44000}')
);

-- SSM-001 — between SSE and SSF
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000011',
  'ELEC', 'SSM-001',
  '11111111-0000-4000-8000-00000000000a',
  '11kV',
  ST_SetSRID(ST_MakePoint(-1.8671, 52.4831), 4326),
  '{"voltage_kv": 11, "rating_mva": 1, "cost_data": 41000}',
  md5('{"voltage_kv": 11, "rating_mva": 1, "cost_data": 41000}')
);

-- ── Overhead Lines ───────────────────────────────────────────────────────────

-- OHL-001 — PSS → SSG → SSA
INSERT INTO network_model.object
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000006',
  'ELEC', 'OHL-001',
  '11111111-0000-4000-8000-000000000006',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000007',
  'ELEC', 'OHL-002',
  '11111111-0000-4000-8000-000000000006',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000012',
  'ELEC', 'OHL-003',
  '11111111-0000-4000-8000-000000000006',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000013',
  'ELEC', 'OHL-004',
  '11111111-0000-4000-8000-000000000006',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000016',
  'ELEC', 'OHL-005',
  '11111111-0000-4000-8000-000000000006',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000014',
  'ELEC', 'UGC-001',
  '11111111-0000-4000-8000-000000000008',
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
    (uuid, namespace, identity, class_uuid, discriminator, geo_geometry, attributes, hash)
VALUES (
  '33333333-0000-4000-8000-000000000015',
  'ELEC', 'UGC-002',
  '11111111-0000-4000-8000-000000000008',
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
    (source_uuid, target_uuid, class_uuid, rel_type)
VALUES
  -- PSS-001 → SSG-001
  ('33333333-0000-4000-8000-000000000001',
   '33333333-0000-4000-8000-000000000004',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSG-001 → SSA-001
  ('33333333-0000-4000-8000-000000000004',
   '33333333-0000-4000-8000-000000000002',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- PSS-001 → SSH-001
  ('33333333-0000-4000-8000-000000000001',
   '33333333-0000-4000-8000-000000000005',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSH-001 → SSB-001
  ('33333333-0000-4000-8000-000000000005',
   '33333333-0000-4000-8000-000000000003',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSA-001 → SSI-001
  ('33333333-0000-4000-8000-000000000002',
   '33333333-0000-4000-8000-00000000000d',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSI-001 → SSC-001
  ('33333333-0000-4000-8000-00000000000d',
   '33333333-0000-4000-8000-000000000009',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSB-001 → SSJ-001
  ('33333333-0000-4000-8000-000000000003',
   '33333333-0000-4000-8000-00000000000e',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSJ-001 → SSD-001
  ('33333333-0000-4000-8000-00000000000e',
   '33333333-0000-4000-8000-00000000000a',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSA-001 → SSK-001
  ('33333333-0000-4000-8000-000000000002',
   '33333333-0000-4000-8000-00000000000f',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSK-001 → SSE-001
  ('33333333-0000-4000-8000-00000000000f',
   '33333333-0000-4000-8000-00000000000b',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSC-001 → SSL-001 (ring feeder)
  ('33333333-0000-4000-8000-000000000009',
   '33333333-0000-4000-8000-000000000010',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSL-001 → PSS-001 (ring feeder completion)
  ('33333333-0000-4000-8000-000000000010',
   '33333333-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSE-001 → SSM-001
  ('33333333-0000-4000-8000-00000000000b',
   '33333333-0000-4000-8000-000000000011',
   '11111111-0000-4000-8000-000000000010', 'edge'),

  -- SSM-001 → SSF-001
  ('33333333-0000-4000-8000-000000000011',
   '33333333-0000-4000-8000-00000000000c',
   '11111111-0000-4000-8000-000000000010', 'edge');
