-- 11_layer_visibility.sql
-- Per-user layer visibility state for the map UI.
--
-- One row per visible layer per user — absence of a row means the layer is off.
-- This means newly added layers default to off without any data migration.
--
-- user_sub: OIDC providerAccountId, matching iam.users.sub (logical FK — not enforced).
-- view_name: matches data_dictionary.view_definition.view_name.

CREATE TABLE IF NOT EXISTS network_views.layer_visibility_state (
    user_sub  TEXT NOT NULL,
    view_name TEXT NOT NULL,
    PRIMARY KEY (user_sub, view_name)
);
