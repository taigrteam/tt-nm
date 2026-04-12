-- 02_schemas.sql
-- Creates all application schemas.
--
--   iam             — identity and access management (users, roles, permissions)
--   network_model   — instance data (objects, relationships, states)
--   data_dictionary — metamodel (class hierarchy, attribute catalogue, view specs)
--   network_views   — PostgreSQL materialized views generated from view_definition specs
--
-- All application tables must be created inside one of these schemas.
-- Never create tables in the public schema.

CREATE SCHEMA IF NOT EXISTS iam;
CREATE SCHEMA IF NOT EXISTS network_model;
CREATE SCHEMA IF NOT EXISTS data_dictionary;
CREATE SCHEMA IF NOT EXISTS network_views;

GRANT ALL ON SCHEMA iam TO postgres;
GRANT ALL ON SCHEMA network_model TO postgres;
GRANT ALL ON SCHEMA data_dictionary TO postgres;
GRANT ALL ON SCHEMA network_views TO postgres;
