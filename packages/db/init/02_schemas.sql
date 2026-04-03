-- 02_schemas.sql
-- Creates the two application schemas.
--
--   iam           — identity and access management (users, roles, permissions)
--   network_model — property graph (objects, relationships, states, data dictionary)
--
-- All application tables must be created inside one of these schemas.
-- Never create tables in the public schema.

CREATE SCHEMA IF NOT EXISTS iam;
CREATE SCHEMA IF NOT EXISTS network_model;

GRANT ALL ON SCHEMA iam TO postgres;
GRANT ALL ON SCHEMA network_model TO postgres;
