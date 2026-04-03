// Drizzle schema for the `iam` schema — read-only subset used by Auth.js callbacks.
// Only the tables needed for JIT provisioning and role lookup are declared here.

import {
  pgTable,
  pgSchema,
  uuid,
  text,
  timestamp,
  integer,
  serial,
  primaryKey,
} from "drizzle-orm/pg-core";

const iam = pgSchema("iam");

export const users = iam.table("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  sub: text("sub").unique().notNull(),
  email: text("email").unique().notNull(),
  idpSource: text("idp_source").notNull(),
  lastLogin: timestamp("last_login", { withTimezone: true }).notNull().defaultNow(),
});

export const roles = iam.table("roles", {
  id: serial("id").primaryKey(),
  name: text("name").unique().notNull(),
});

export const permissions = iam.table("permissions", {
  id: serial("id").primaryKey(),
  slug: text("slug").unique().notNull(),
  description: text("description").notNull(),
});

export const rolePermissions = iam.table(
  "role_permissions",
  {
    roleId: integer("role_id")
      .notNull()
      .references(() => roles.id, { onDelete: "cascade" }),
    permissionId: integer("permission_id")
      .notNull()
      .references(() => permissions.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.roleId, t.permissionId] })],
);

export const userRoles = iam.table(
  "user_roles",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    roleId: integer("role_id")
      .notNull()
      .references(() => roles.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.userId, t.roleId] })],
);

export const idpGroupMappings = iam.table("idp_group_mappings", {
  idpGroupId: text("idp_group_id").primaryKey(),
  roleId: integer("role_id").references(() => roles.id, { onDelete: "set null" }),
});
