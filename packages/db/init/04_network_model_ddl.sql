-- 04_network_model_ddl.sql
-- Property graph schema split across data_dictionary and network_model.
--
-- Design notes (see CLAUDE.md §4 for domain rules):
--   • Bitemporal: every table carries valid_from / valid_to.
--   • Active record filter: WHERE valid_to IS NULL
--   • PostgreSQL treats NULLs as distinct in UNIQUE constraints — the
--     unique_active_* constraints do NOT enforce single-active-row at DB level.
--     Application logic must ensure only one active row per natural key.
--   • sch_geometry is reserved for future schematic layouts — do NOT query it.
--   • DB-level FK constraints from instance tables to data_dictionary tables are
--     omitted: bitemporal tables cannot expose a simple UNIQUE(namespace, class_name)
--     constraint that a FK could reference. Referential integrity for class_name and
--     attribute_name is enforced logically by the application layer.
--   • Referential integrity between network_model instance tables (object ↔
--     relationship ↔ state) is enforced at DB level via UUID FKs as before.
--
-- Schema sections:
--   I.  data_dictionary — class hierarchy and attribute catalogue (the metamodel)
--   II. data_dictionary — view specs (instructions for building materialized views)
--   III.network_model   — instance data (objects, relationships, states)

SET search_path TO network_model, public;

-- ─── I. DATA DICTIONARY — CLASS HIERARCHY ────────────────────────────────────

-- Class hierarchy. term_type controls which instance table holds the class's records:
--   'OBJECT'       → network_model.object
--   'RELATIONSHIP' → network_model.relationship
--   'STATE'        → network_model.state
--
-- Natural key: (namespace, class_name). UUIDs removed — use text names directly.
-- Parent reference: (parent_namespace, parent_class_name) — supports cross-namespace
-- class hierarchies. Inheritance within a namespace is the common case.
-- Self-referential FK is logical only (see design notes above).
CREATE TABLE data_dictionary.class_definition (
    namespace           TEXT        NOT NULL,
    class_name          TEXT        NOT NULL,
    parent_namespace    TEXT,
    parent_class_name   TEXT,
    -- Logical self-ref: (parent_namespace, parent_class_name)
    --   → data_dictionary.class_definition (namespace, class_name) WHERE valid_to IS NULL
    term_type           TEXT        NOT NULL CHECK (term_type IN ('OBJECT', 'RELATIONSHIP', 'STATE')),
    is_abstract         BOOLEAN     NOT NULL DEFAULT FALSE,
    valid_from          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to            TIMESTAMPTZ,
    -- Bitemporal uniqueness: NULL valid_to marks the active record.
    -- PostgreSQL treats NULLs as distinct, so (ns, name, NULL) is unique per active version.
    CONSTRAINT unique_class_bitemporal UNIQUE (namespace, class_name, valid_to)
);

-- ─── I. DATA DICTIONARY — ATTRIBUTE CATALOGUE ────────────────────────────────

-- Unified attribute table: merges attribute_definition + class_attribute_config.
-- Each row defines an attribute owned by a specific class in the hierarchy.
-- Subclasses inherit attributes from ancestor classes via recursive CTE traversal.
-- A child-class row for the same attribute_name overrides the ancestor's config.
--
-- Natural key: (namespace, class_name, attribute_name).
-- Logical FK: (namespace, class_name) → data_dictionary.class_definition WHERE valid_to IS NULL
CREATE TABLE data_dictionary.attr_definition (
    namespace       TEXT        NOT NULL,
    class_name      TEXT        NOT NULL,
    attribute_name  TEXT        NOT NULL,
    display_name    TEXT        NOT NULL,   -- Short human-readable label for UI
    data_type       TEXT        NOT NULL CHECK (data_type IN ('numeric', 'text', 'boolean')),
    is_required     BOOLEAN     NOT NULL DEFAULT FALSE,
    default_value   TEXT,
    valid_from      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to        TIMESTAMPTZ,
    CONSTRAINT unique_attr_bitemporal UNIQUE (namespace, class_name, attribute_name, valid_to)
);

-- ─── II. DATA DICTIONARY — VIEW SPECIFICATIONS ───────────────────────────────

-- Describes a spatial view: which class to flatten and how to present it.
-- display_name is shown in UI legends — decoupled from SQL-safe view_name.
-- Actual materialized views are created in the network_views schema by the
-- application migration process; this table holds the spec only.
-- map_geometry_type: 'line' or 'circle' — controls which MapLibre layer type is added.
-- map_color:         primary hex colour used for the layer's paint property.
-- map_radius:        circle radius in pixels (circle layers only; ignored for lines).
-- map_dashed:        whether to apply a dash pattern (line layers only).
--
-- Logical FK: (class_namespace, class_name) → data_dictionary.class_definition WHERE valid_to IS NULL
CREATE TABLE data_dictionary.view_definition (
    namespace            TEXT        NOT NULL,
    view_name            TEXT        NOT NULL,      -- SQL-safe identifier
    display_name         TEXT        NOT NULL,      -- UI legend label
    is_materialized      BOOLEAN     NOT NULL DEFAULT FALSE,
    refresh_group        TEXT,                      -- Orchestration batch key
    class_namespace      TEXT,
    class_name           TEXT,
    discriminator_filter TEXT,                      -- Optional WHERE clause fragment
    show_on_map          BOOLEAN     NOT NULL DEFAULT TRUE,
    map_geometry_type    TEXT,                      -- 'line' | 'circle'
    map_color            TEXT,                      -- Hex colour for map rendering
    map_radius           INTEGER,                   -- Circle radius (circle layers only)
    map_dashed           BOOLEAN     NOT NULL DEFAULT FALSE,
    valid_from           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to             TIMESTAMPTZ,
    CONSTRAINT unique_view_bitemporal UNIQUE (namespace, view_name, valid_to)
);

-- Namespace registry — controls which namespaces appear in the map layer sidebar.
-- viewable: FALSE hides the namespace from the UI without deleting its data.
CREATE TABLE data_dictionary.namespace (
    namespace    TEXT    PRIMARY KEY,
    display_name TEXT    NOT NULL,
    viewable     BOOLEAN NOT NULL DEFAULT TRUE
);

-- Specifies how to extract a column from the JSONB attributes blob.
-- source_path: dot-notation path into attributes JSONB (e.g. 'voltage_kv').
-- Logical FK: (namespace, view_name) → data_dictionary.view_definition WHERE valid_to IS NULL
CREATE TABLE data_dictionary.view_column_spec (
    namespace    TEXT        NOT NULL,
    view_name    TEXT        NOT NULL,
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
-- attributes:   JSONB payload; shape defined by the class's attr_definition entries.
-- hash:         MD5 of attributes::text — used for change detection during ingestion.
-- class_name:   denormalised class name — readable without joining data_dictionary.
--   Logical FK: (namespace, class_name) → data_dictionary.class_definition WHERE valid_to IS NULL
CREATE TABLE object (
    uuid             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace        TEXT        NOT NULL,
    identity         TEXT        NOT NULL,   -- Natural key within namespace
    class_name       TEXT        NOT NULL,
    discriminator    TEXT,                   -- Sub-type hint (e.g. 'PRIMARY', 'SECONDARY')
    geo_geometry     GEOMETRY(Geometry, 4326),  -- WGS84; mixed types (Point/LineString)
    sch_geometry     GEOMETRY(Geometry, 4326),  -- Reserved — do not query
    attributes       JSONB       NOT NULL DEFAULT '{}',
    hash             TEXT,
    valid_from       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to         TIMESTAMPTZ,
    -- Uniqueness of active records is enforced at application level, not DB level.
    -- PostgreSQL treats NULLs as distinct, so (namespace, identity, NULL) does not
    -- prevent duplicate active rows. The application must set valid_to on the
    -- previous version before inserting a new one.
    CONSTRAINT unique_active_object UNIQUE (namespace, identity, valid_to)
);

-- Topological connections between objects.
-- relationship_type 'edge'        → functional flow (electricity, data, fluid)
-- relationship_type 'composition' → physical containment (feeder inside a substation bay)
-- Logical FK: (class_namespace, class_name) → data_dictionary.class_definition WHERE valid_to IS NULL
CREATE TABLE relationship (
    relationship_uuid UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_uuid       UUID        NOT NULL REFERENCES object(uuid),
    target_uuid       UUID        NOT NULL REFERENCES object(uuid),
    class_namespace   TEXT        NOT NULL,
    class_name        TEXT        NOT NULL,
    relationship_type TEXT        NOT NULL CHECK (relationship_type IN ('edge', 'composition')),
    attributes        JSONB       NOT NULL DEFAULT '{}',
    valid_from        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to          TIMESTAMPTZ
);

-- Operational state snapshots (decoupled from master asset data).
-- Storing state separately prevents version explosion in the object table when
-- volatile values (e.g. switch open/closed) change frequently.
-- PK: (namespace, identity, valid_from) — natural bitemporal key; no surrogate UUID.
-- Logical FK: (class_namespace, class_name) → data_dictionary.class_definition WHERE valid_to IS NULL
CREATE TABLE state (
    object_uuid      UUID        NOT NULL REFERENCES object(uuid),
    class_namespace  TEXT        NOT NULL,
    class_name       TEXT        NOT NULL,
    namespace        TEXT        NOT NULL,
    identity         TEXT        NOT NULL,
    state_data       JSONB       NOT NULL,
    valid_from       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to         TIMESTAMPTZ,
    PRIMARY KEY (namespace, identity, valid_from)
);

-- ─── INDEXES ─────────────────────────────────────────────────────────────────

-- data_dictionary.class_definition
-- Enforce at-most-one active record per class (supplement to bitemporal UNIQUE constraint)
CREATE UNIQUE INDEX idx_class_active
    ON data_dictionary.class_definition (namespace, class_name) WHERE valid_to IS NULL;
-- Recursive CTE parent traversal
CREATE INDEX idx_class_parent
    ON data_dictionary.class_definition (parent_namespace, parent_class_name) WHERE valid_to IS NULL;

-- data_dictionary.attr_definition
CREATE UNIQUE INDEX idx_attr_active
    ON data_dictionary.attr_definition (namespace, class_name, attribute_name) WHERE valid_to IS NULL;

-- data_dictionary.view_definition
CREATE UNIQUE INDEX idx_view_active
    ON data_dictionary.view_definition (namespace, view_name) WHERE valid_to IS NULL;

-- data_dictionary.view_column_spec
CREATE INDEX idx_view_col_active
    ON data_dictionary.view_column_spec (namespace, view_name) WHERE valid_to IS NULL;

-- network_model.object
CREATE INDEX idx_object_active_identity
    ON object (namespace, identity) WHERE valid_to IS NULL;
-- Class-based filtering (e.g. show only OverheadLine objects on a layer)
CREATE INDEX idx_object_active_class
    ON object (class_name) WHERE valid_to IS NULL;
-- Spatial index — essential for tile generation performance
CREATE INDEX idx_object_geometry
    ON object USING GIST (geo_geometry) WHERE valid_to IS NULL;

-- network_model.relationship
CREATE INDEX idx_rel_source
    ON relationship (source_uuid) WHERE valid_to IS NULL;
CREATE INDEX idx_rel_target
    ON relationship (target_uuid) WHERE valid_to IS NULL;
CREATE INDEX idx_rel_class
    ON relationship (class_namespace, class_name) WHERE valid_to IS NULL;

-- network_model.state
CREATE INDEX idx_state_object
    ON state (object_uuid) WHERE valid_to IS NULL;

RESET search_path;
