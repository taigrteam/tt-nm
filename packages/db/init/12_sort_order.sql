-- ─── MIGRATION: add sort_order to view_definition ────────────────────────────
-- Adds explicit display ordering for the layer sidebar.
-- DEFAULT 100 means any future views not listed here sort to the bottom,
-- then fall back to display_name alphabetically.

ALTER TABLE data_dictionary.view_definition
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 100;

-- ELECTRICITY namespace — desired sidebar order
UPDATE data_dictionary.view_definition SET sort_order = 10 WHERE view_name = 'vw_dno_license_zones'    AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 20 WHERE view_name = 'vw_gsp_zones'            AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 30 WHERE view_name = 'vw_primary_zones'        AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 40 WHERE view_name = 'vw_overhead_line'        AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 50 WHERE view_name = 'vw_primary_substation'   AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 60 WHERE view_name = 'vw_secondary_substation' AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 70 WHERE view_name = 'vw_supports'             AND valid_to IS NULL;
UPDATE data_dictionary.view_definition SET sort_order = 80 WHERE view_name = 'vw_underground_cable'    AND valid_to IS NULL;
