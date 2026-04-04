# CLAUDE.md — tt-nm Project Brief

This file is read by Claude Code at the start of every session. Follow all instructions here without being asked.

---

## 1. What this project is

A spatial network modelling and visualisation platform for taigrteam. It models physical/logical networks (e.g. electrical grids) as a property graph in PostgreSQL/PostGIS and renders them on an interactive map via MapLibre GL JS v5. The primary concern is accurate network representation and real-time visualisation with role-based attribute security.

**DDL reference:** `packages/db/init/` contains the authoritative SQL (extensions, both schemas, seed data, function sources).

---

## 2. Monorepo layout

```
tt-nm/
├── apps/
│   └── web/                          # Next.js 16 — frontend + auth + tile proxy
│       ├── app/
│       │   ├── api/tiles/[...path]/  # Secure tile proxy Route Handler
│       │   ├── components/           # map-shell, network-map, layer-sidebar, attribute-inspector, nav-bar
│       │   ├── signin/               # Sign-in page
│       │   └── layout.tsx / page.tsx
│       ├── auth.ts                   # Auth.js config (JIT provisioning, jwt/session callbacks)
│       ├── middleware.ts             # Route protection via Auth.js authorized callback
│       ├── lib/db.ts                 # Drizzle client
│       ├── lib/schema.ts             # Drizzle schema for iam tables
│       └── types/next-auth.d.ts     # Session type augmentation (session.user.role)
├── packages/
│   └── db/
│       └── init/                    # Postgres init SQL (runs at container start)
│           ├── 01_extensions.sql    # postgis, pgrouting
│           ├── 02_schemas.sql       # CREATE SCHEMA iam / network_model
│           ├── 03_iam_ddl.sql
│           ├── 04_network_model_ddl.sql
│           ├── 05_seed.sql          # Roles, test user, sample network objects
│           └── 06_function_sources.sql  # PostGIS function sources for Martin
├── docker/
│   ├── Dockerfile.db                # PostgreSQL 17 + PostGIS image
│   └── martin-config.yaml           # Martin tile server config
├── docker-compose.yml               # db + martin (Martin has NO host port mapping)
└── CLAUDE.md
```

There is **no** `apps/api`. Next.js Route Handlers handle all server-side logic including the tile proxy. Do not create a separate Fastify or Express service.

---

## 3. Technology decisions (non-negotiable)

| Concern | Choice | Notes |
|---|---|---|
| Framework | Next.js 16, App Router | Server Components by default |
| Auth | Auth.js v5 (`next-auth@beta`) | Google + Microsoft Entra ID |
| DB client — `iam` schema | Drizzle ORM + `postgres` driver | Type-safe RBAC lookups |
| DB client — `network_model` schema | `postgres.js` raw SQL only | JSONB, recursive CTEs, spatial queries |
| Tile server | Martin (Rust) | Internal network only — never exposed to host |
| Map renderer | MapLibre GL JS v5 | WebGPU, client-side only |
| Styling | Tailwind CSS v4 + `@base-ui/react` + Phantom tokens | See Section 9 |
| Validation | Zod | Tile coordinates + spatial GeoJSON inputs |
| Client-side spatial | Turf.js | Buffers, intersections, distance |
| Icons | Lucide React | GIS toolbar icons |

---

## 4. Database schemas — CRITICAL

There are exactly two application schemas. Never create tables outside them. Never reference a table without its schema prefix.

### `iam` — identity and access management
All user, role, and permission tables. Managed by Drizzle ORM.
```
iam.users
iam.roles
iam.permissions
iam.role_permissions
iam.user_roles
iam.idp_group_mappings
```

**Permission slug convention:** `service:resource:action` — e.g. `map:network:read`, `map:cost_data:read`. Supports wildcard matching (`map:*`). The `description` field on `iam.permissions` is the human-readable label used in UI overlays and access-denied messages. IdP groups (Azure/Google group GUIDs) map to internal roles via `iam.idp_group_mappings` — identity stays in the IdP, permissions stay in the app.

### `network_model` — the property graph
All network data, data dictionary, and view specs. Queried via raw `postgres.js`.
```
network_model.class_definition       -- class inheritance tree (recursive, nullable parent_class_uuid)
network_model.attribute_definition   -- attribute registry
network_model.class_attribute_config -- per-class attribute rules; child config overrides parent for same attr
network_model.view_definition        -- view specs (flattened JSONB → columns); materialized views refreshed externally
network_model.view_column_spec       -- column mapping: source_path → alias + display_name
network_model.object                 -- asset instances; natural key is (namespace, identity)
network_model.relationship           -- edges between objects; rel_type: 'edge' (flow) | 'composition' (hierarchy)
network_model.state                  -- volatile operational state (e.g. switch open/closed); decoupled from object
```

**Never** write `public.object` or `data.object`. Always qualify: `network_model.object`.

**Key domain rules:**
- **Natural key:** `(namespace, identity)` is the immutable asset identifier across its entire life. The `uuid` changes with each version; `(namespace, identity)` does not.
- **Class inheritance:** Attribute configs are inherited up the class tree. A config on a child class overrides the same attribute on any ancestor. Resolve via recursive CTE (`WITH RECURSIVE lineage AS ...`).
- **Relationship types:** `edge` = functional flow between assets (e.g. current path). `composition` = physical containment hierarchy (e.g. substation contains feeder).
- **Update pattern (Terminate-and-Insert):** To update an object, compute MD5 of incoming `attributes` JSONB. If it differs from the active record: set `valid_to = NOW()` on the old record, insert a new version. Never UPDATE in place.
- **State table:** `network_model.state` stores volatile operational values (switch position, alarm status). Kept separate from `network_model.object` to avoid version explosion on master data.

### PostgreSQL extensions (must be installed in this order)
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;  -- must come after postgis
```

---

## 5. Bitemporality

Every `network_model` table has `valid_from TIMESTAMPTZ` and `valid_to TIMESTAMPTZ` columns.

- **Active record filter** (use this unless a specific time is requested):
  ```sql
  valid_to IS NULL
  ```
- **Point-in-time filter** (future use):
  ```sql
  valid_from <= :T AND (valid_to > :T OR valid_to IS NULL)
  ```

The current focus is active-record queries. Do not build point-in-time query UI unless explicitly asked. The `sch_geometry` column on `network_model.object` is reserved — it exists in the schema but must not be used in any query, Martin function source, or MapLibre layer. Use `geo_geometry` only.

---

## 6. Tile security — CRITICAL INVARIANTS

These rules must never be violated. They are the security boundary of the entire application.

1. **Martin is internal-only.** In `docker-compose.yml`, the `martin` service has no `ports` mapping to the host. In Kubernetes, its Service is `ClusterIP`. A direct `curl` to Martin from outside the Docker network must fail.

2. **Role comes from the server-side session exclusively.** The Next.js Route Handler at `app/api/tiles/[...path]/route.ts` calls `auth()` to get the session. It strips any `user_role` or `role` parameters from the incoming client request before constructing the Martin URL. The role appended to Martin's URL is **only** `session.user.role`.

3. **Unauthenticated tile requests return 401.** No tile data is ever served without a valid session.

4. **Next.js 16 — `params` is async.** Route Handler params must be awaited:
   ```typescript
   // CORRECT
   export async function GET(req: Request, { params }: { params: Promise<{ path: string[] }> }) {
     const { path } = await params;
   }
   // WRONG — will throw at runtime
   export async function GET(req: Request, { params }: { params: { path: string[] } }) {
     const path = params.path; // ❌
   }
   ```

---

## 7. Auth.js session setup

Auth.js does not include application roles in the session by default. The `jwt` and `session` callbacks in `auth.ts` must look up the role from `iam.user_roles` and attach it. The TypeScript type for `Session` must be augmented in `types/next-auth.d.ts`.

The jwt callback looks up the role via Drizzle (joining `iam.users → iam.user_roles → iam.roles`) using the OIDC `providerAccountId` (sub). The session callback exposes `token.role` as `session.user.role`. TypeScript augmentation lives in `types/next-auth.d.ts`.

JIT provisioning runs in the `signIn` callback: check `iam.users` for the OIDC `sub` claim; if absent, insert the user and assign the default `viewer` role. `providerAccountId` is the immutable identifier — never rely on email alone.

---

## 8. Next.js 16 conventions

- **Default to Server Components.** Add `'use client'` only when the component needs interactivity or browser APIs (MapLibre, event handlers, hooks).
- **Push `'use client'` as far down the tree as possible.** The map component is `'use client'`; its parent layout is not.
- **All request APIs are async:** `await cookies()`, `await headers()`, `await params`, `await searchParams`.
- **Data mutations use Server Actions** (`'use server'`), not Route Handlers (except the tile proxy and any public API endpoints).
- **Route protection** is handled by `middleware.ts` (Auth.js `authorized` callback). The tile proxy is a Route Handler at `app/api/tiles/[...path]/route.ts`.

---

## 9. Design system — Phantom

The UI uses the taigrteam "Phantom" design system. Component primitives come from `@base-ui/react` (not Radix/shadcn). Styling uses Tailwind CSS v4.

**Canonical tokens** (defined in `globals.css` `:root`):**
```css
--bg:         #F0F6F7
--text:       #05100E
--text-muted: rgba(5,16,14,0.65)   /* must be 0.65 or higher — WCAG AA */
--border-col: #05100E
--accent:     #EC6D26              /* orange — primary CTA, focus rings */
--accent-fg:  #F0F6F7
--accent2:    #0D8C80              /* teal — secondary / info */
--shadow-col: #EC6D26
--input-bg:   #F0F6F7
--card-bg:    #F0F6F7
--code-bg:    #E4EDEF
--error:      #C0392B
--success:    #2D9E72
--row-hover:  rgba(236,109,38,0.06)
```

**Typography:**
- Headings (h1–h3): `font-family: 'Orbitron', sans-serif`; fluid sizing — h1: `clamp(1.6rem, 4vw, 2.8rem)`, h2: `clamp(1.1rem, 2.5vw, 1.6rem)`
- Body/UI/labels: `font-family: 'Roboto', sans-serif`
- Code/mono: `font-family: 'Courier New', monospace`
- Google Fonts loaded via `<link>` in layout: Orbitron (700, 900) + Roboto (400, 700)

**Borders, corners, shadows:**
- `border-radius: 0` on all interactive and container elements — no exceptions
- Elevated elements: `box-shadow: 6px 6px 0 var(--shadow-col)` — no blur/spread shadows
- Borders use `var(--border-col)` or `var(--accent)` — never grey system colours
- Button borders: `3px solid` (default/large), `2px solid` (sm)

**Button variants:**

| Variant | Background | Text | Border |
|---|---|---|---|
| primary | `var(--text)` | `var(--bg)` | `3px solid var(--border-col)` |
| accent | `var(--accent)` | `var(--accent-fg)` | `3px solid var(--accent)` |
| outline | `transparent` | `var(--text)` | `3px solid var(--border-col)` |
| ghost | `transparent` | `var(--text)` | `3px solid transparent` |

Hover: primary/outline/ghost → `opacity: 0.85`. Accent → `opacity: 1; box-shadow: 4px 4px 0 var(--text)`.
Disabled: `opacity: 0.4; cursor: not-allowed; pointer-events: none`.
All buttons: `font-weight: 700; letter-spacing: 0.05em; transition: opacity 0.15s ease, box-shadow 0.15s ease`.

**Inputs / selects:**
- `border-radius: 0; border: 2px solid var(--border-col); background: var(--input-bg)`
- Focus: `box-shadow: 4px 4px 0 var(--accent); border-color: var(--accent); outline: none`

**Accessibility — CRITICAL:**
- `--text-muted` opacity must be ≥ 0.65. Values like `rgba(*,*,*,0.4)` fail WCAG AA — raise to 0.65 minimum.
- Never use `display: none` on toggle/switch `<input>` — use the visually-hidden pattern (`position: absolute; width: 1px; height: 1px; clip: rect(0,0,0,0)`).
- Every `<label>` must have a `for` attribute matched to an input `id`.
- Error fields: `aria-invalid="true"` + `aria-describedby="[error-id]"` on the input; matching `id` on the error message.
- Focus ring: `:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px }` — never suppress without replacement.

---

## 10. Map layer architecture

The MapLibre map has two distinct layer categories, always in this order:

1. **Background — OpenStreetMap raster tiles** (bottom)
2. **Network data — Martin vector tiles** (on top)

### OSM background setup
Configure the OSM layer as a named raster source so future visibility and opacity controls can target it by ID without restructuring the style:

```typescript
const MAP_STYLE: StyleSpecification = {
  version: 8,
  sources: {
    "osm": {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution: "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors",
    },
  },
  layers: [
    {
      id: "osm-background",   // ← must use this ID — future controls will target it
      type: "raster",
      source: "osm",
    },
  ],
};
```

Network vector layers are added on top of this base style at runtime via `map.addSource()` / `map.addLayer()`.

### Future toggle/transparency (do not implement yet)
When the time comes, the mechanisms are:
- **Visibility toggle:** `map.setLayoutProperty("osm-background", "visibility", "none" | "visible")`
- **Opacity/greyscale:** `map.setPaintProperty("osm-background", "raster-opacity", 0.0–1.0)`

Do not implement these controls until explicitly asked. The layer ID `"osm-background"` must be consistent from day one so adding controls later requires no refactoring.

### Attribution
OSM attribution (`© OpenStreetMap contributors`) must be visible on the map at all times. MapLibre renders `attribution` from the source definition automatically — do not suppress it.

---

## 11. General coding rules

- **Read before editing.** Always read a file before modifying it.
- **Schema prefix every SQL statement.** `iam.users` not `users`. `network_model.object` not `object`.
- **Drizzle for `iam`, `postgres.js` for `network_model`.** Do not use Drizzle to query `network_model` tables. Do not write raw SQL for `iam` tables.
- **Validate at boundaries.** Use Zod to validate tile coordinates (`z`, `x`, `y`) and any incoming GeoJSON. Do not validate internal function-to-function calls.
- **No `any` in TypeScript.** Type the Drizzle schema, the session augmentation, and the postgres.js query results.
- **Environment variables.** Never hardcode connection strings, secrets, or URLs. Use `.env.local` (gitignored). Required vars: `DATABASE_URL`, `MARTIN_INTERNAL_URL`, `AUTH_SECRET`, `AUTH_GOOGLE_ID`, `AUTH_GOOGLE_SECRET`, `AUTH_MICROSOFT_ENTRA_ID_ID`, `AUTH_MICROSOFT_ENTRA_ID_SECRET`, `AUTH_MICROSOFT_ENTRA_ID_ISSUER`.
- **Docker compose.** The `martin` service must never have a `ports` mapping in `docker-compose.yml`. Local dev access to Martin (if needed) goes in `docker-compose.override.yml`, which is gitignored. The `postgres` service exposes port 5432 to the host for local dev only.
- **No speculative features.** Build exactly what is asked. Do not add error boundaries, loading states, or utility helpers that are not needed for the task.
