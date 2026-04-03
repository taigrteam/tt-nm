-- 03_iam_ddl.sql
-- Identity and Access Management schema.
--
-- Tables:
--   iam.users             — OIDC-provisioned user accounts (JIT on first login)
--   iam.roles             — named roles (e.g. admin, viewer)
--   iam.permissions       — namespaced permission slugs (service:resource:action)
--   iam.role_permissions  — many-to-many: roles → permissions
--   iam.user_roles        — many-to-many: users → roles
--   iam.idp_group_mappings — maps IdP group IDs to internal roles

SET search_path TO iam;

-- ─── Identity ────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    sub         TEXT        UNIQUE NOT NULL,  -- OIDC Subject claim (immutable per IdP)
    email       TEXT        UNIQUE NOT NULL,
    idp_source  TEXT        NOT NULL CHECK (idp_source IN ('google', 'microsoft')),
    last_login  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── RBAC ────────────────────────────────────────────────────────────────────

CREATE TABLE permissions (
    id          SERIAL  PRIMARY KEY,
    slug        TEXT    UNIQUE NOT NULL,  -- Format: 'service:resource:action'
    description TEXT    NOT NULL          -- Human-readable; used to infer intent in code
);

CREATE TABLE roles (
    id   SERIAL  PRIMARY KEY,
    name TEXT    UNIQUE NOT NULL
);

CREATE TABLE role_permissions (
    role_id       INT NOT NULL REFERENCES roles(id)       ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INT  NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- ─── IdP Group Mapping ───────────────────────────────────────────────────────

-- Maps Azure/Google group IDs to internal roles for JIT provisioning.
-- idp_group_id is the GUID / Object ID from the identity provider.
CREATE TABLE idp_group_mappings (
    idp_group_id TEXT PRIMARY KEY,
    role_id      INT  REFERENCES roles(id) ON DELETE SET NULL
);

RESET search_path;
