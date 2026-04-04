-- 04_network_model_ddl.sql
-- Property graph schema for network model data.
--
-- Design notes (see CLAUDE.md §4 for domain rules):
--   • Bitemporal: every table carries valid_from / valid_to.
--   • Active record filter: WHERE valid_to IS NULL
--   • PostgreSQL treats NULLs as distinct in UNIQUE constraints — the
--     unique_active_* constraints do NOT enforce single-active-row at DB level.
--     Application logic must ensure only one active row per natural key.
--   • sch_geometry is reserved for future schematic layouts — do NOT query it.
--
-- Schema sections:
--   I.  Data Dictionary  — class and attribute definitions (the metamodel)
--   II. View Specs       — instructions for flattening JSONB into spatial views
--   III.Instance Data    — the actual network objects, relationships, and states

SET search_path TO network_model, public;

-- ─── I. DATA DICTIONARY ──────────────────────────────────────────────────────

-- Class hierarchy. term_type controls which instance table holds the class's records:
--   'OBJECT'       → network_model.object
--   'RELATIONSHIP' → network_model.relationship
--   'STATE'        → network_model.state
CREATE TABLE class_definition (
    class_uuid        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_class_uuid UUID        REFERENCES class_definition(class_uuid),
    namespace         TEXT        NOT NULL,
    name              TEXT        NOT NULL,
    term_type         TEXT        NOT NULL CHECK (term_type IN ('OBJECT', 'RELATIONSHIP', 'STATE')),
    is_abstract       BOOLEAN     NOT NULL DEFAULT FALSE,
    valid_from        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to          TIMESTAMPTZ,
    CONSTRAINT unique_active_class UNIQUE (namespace, name, term_type, valid_to)
);

-- Reusable attribute catalogue. data_type is a string descriptor (e.g. 'numeric', 'text', 'boolean').
CREATE TABLE attribute_definition (
    attr_uuid  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace  TEXT        NOT NULL,
    name       TEXT        NOT NULL,
    data_type  TEXT        NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to   TIMESTAMPTZ,
    CONSTRAINT unique_active_attr UNIQUE (namespace, name, valid_to)
);

-- Attaches attributes to classes with override capability.
-- Child class configs override parent configs for the same attr_uuid (resolved in application).
CREATE TABLE class_attribute_config (
    config_uuid   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    class_uuid    UUID        NOT NULL REFERENCES class_definition(class_uuid),
    attr_uuid     UUID        NOT NULL REFERENCES attribute_definition(attr_uuid),
    is_required   BOOLEAN     NOT NULL DEFAULT FALSE,
    default_value TEXT,
    valid_from    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to      TIMESTAMPTZ
);

-- ─── II. VIEW SPECIFICATIONS ──────────────────────────────────────────────────

-- Describes a spatial view: which class to flatten and how to present it.
-- display_name is shown in UI legends — decoupled from SQL-safe view_name.
CREATE TABLE view_definition (
    view_uuid            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace            TEXT        NOT NULL,
    view_name            TEXT        NOT NULL,      -- SQL-safe identifier
    display_name         TEXT        NOT NULL,      -- UI legend label
    is_materialized      BOOLEAN     NOT NULL DEFAULT FALSE,
    refresh_group        TEXT,                      -- Orchestration batch key
    class_uuid           UUID        REFERENCES class_definition(class_uuid),
    discriminator_filter TEXT,                      -- Optional WHERE clause fragment
    valid_from           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to             TIMESTAMPTZ,
    CONSTRAINT unique_active_view UNIQUE (namespace, view_name, valid_to)
);

-- Specifies how to extract a column from the JSONB attributes blob.
-- source_path: dot-notation path into attributes JSONB (e.g. 'voltage_kv')
CREATE TABLE view_column_spec (
    column_uuid  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    view_uuid    UUID        NOT NULL REFERENCES view_definition(view_uuid),
    source_path  TEXT        NOT NULL,   -- JSONB path expression
    alias        TEXT        NOT NULL,   -- SQL column alias
    display_name TEXT        NOT NULL,   -- UI column header
    cast_type    TEXT,                   -- PostgreSQL cast (e.g. 'numeric', 'text')
    valid_from   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to     TIMESTAMPTZ
);

-- ─── III. INSTANCE DATA ───────────────────────────────────────────────────────

-- Network assets and conductors.
-- geo_geometry: real-world WGS84 coordinates (SRID 4326) — use this for all spatial queries.
-- sch_geometry: schematic layout — RESERVED, do not use.
-- attributes:   JSONB payload; shape defined by the class's attribute_definition entries.
-- hash:         MD5 of attributes::text — used for change detection during ingestion.
CREATE TABLE object (
    uuid         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace    TEXT        NOT NULL,
    identity     TEXT        NOT NULL,   -- Natural key within namespace
    class_uuid   UUID        NOT NULL REFERENCES class_definition(class_uuid),
    discriminator TEXT,                  -- Sub-type hint (e.g. 'PRIMARY', 'SECONDARY')
    geo_geometry GEOMETRY(Geometry, 4326),  -- WGS84; mixed types (Point/LineString)
    sch_geometry GEOMETRY(Geometry, 4326), -- Reserved — do not query
    attributes   JSONB       NOT NULL DEFAULT '{}',
    hash         TEXT,
    valid_from   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to     TIMESTAMPTZ,
    -- Uniqueness of active records is enforced at application level, not DB level.
    -- PostgreSQL treats NULLs as distinct, so (namespace, identity, NULL) does not
    -- prevent duplicate active rows. The application must set valid_to on the
    -- previous version before inserting a new one.
    CONSTRAINT unique_active_object UNIQUE (namespace, identity, valid_to)
);

-- Topological connections between objects.
-- rel_type 'edge'        → functional flow (electricity, data, fluid)
-- rel_type 'composition' → physical containment (a feeder inside a substation bay)
CREATE TABLE relationship (
    rel_uuid   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_uuid UUID       NOT NULL REFERENCES object(uuid),
    target_uuid UUID       NOT NULL REFERENCES object(uuid),
    class_uuid  UUID       NOT NULL REFERENCES class_definition(class_uuid),
    rel_type    TEXT       NOT NULL CHECK (rel_type IN ('edge', 'composition')),
    attributes  JSONB      NOT NULL DEFAULT '{}',
    valid_from  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to    TIMESTAMPTZ
);

-- Operational state snapshots (decoupled from master asset data).
-- Storing state separately prevents version explosion in the object table when
-- volatile values (e.g. switch open/closed) change frequently.
CREATE TABLE state (
    state_uuid  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    object_uuid UUID        NOT NULL REFERENCES object(uuid),
    class_uuid  UUID        NOT NULL REFERENCES class_definition(class_uuid),
    namespace   TEXT        NOT NULL,
    identity    TEXT        NOT NULL,
    state_data  JSONB       NOT NULL,
    valid_from  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to    TIMESTAMPTZ
);

-- ─── INDEXES ─────────────────────────────────────────────────────────────────

-- Data dictionary
CREATE INDEX idx_class_namespace_name
    ON class_definition(namespace, name) WHERE valid_to IS NULL;

-- Object lookups (most queries filter on active records only)
CREATE INDEX idx_object_active_identity
    ON object(namespace, identity) WHERE valid_to IS NULL;

CREATE INDEX idx_object_active_class
    ON object(class_uuid) WHERE valid_to IS NULL;

-- Spatial index — essential for tile generation performance
CREATE INDEX idx_object_geometry
    ON object USING GIST(geo_geometry) WHERE valid_to IS NULL;

-- Relationship traversal
CREATE INDEX idx_rel_source
    ON relationship(source_uuid) WHERE valid_to IS NULL;

CREATE INDEX idx_rel_target
    ON relationship(target_uuid) WHERE valid_to IS NULL;

-- State lookups
CREATE INDEX idx_state_object
    ON state(object_uuid) WHERE valid_to IS NULL;

RESET search_path;
