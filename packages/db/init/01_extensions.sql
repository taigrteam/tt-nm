-- 01_extensions.sql
-- Run once on database initialisation.
-- pgrouting must be installed AFTER postgis.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
