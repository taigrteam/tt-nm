# CLAUDE.md — tt-nm Project Brief

This file is read by Claude Code at the start of every session. Follow all instructions here without being asked.

---

## 1. What this project is

A spatial network modelling and visualisation platform for taigrteam. It models physical/logical networks (e.g. electrical grids) as a property graph in PostgreSQL/PostGIS and renders them on an interactive map via MapLibre GL JS v5. The primary concern is accurate network representation and real-time visualisation with role-based attribute security.

**Spec documents — read these before working on the relevant area:**
- `DATABASE.md` — property graph schema, data dictionary, bitemporality, DDL reference
- `APPLICATION.md` — RBAC design, auth/proxy pattern, DDL for `iam` schema
- `STACK.md` — full dependency list, schema namespacing rules, implementation notes
- `TILE_AUTH.md` — tile authentication flow, tile proxy code, Auth.js session callbacks, security guardrails
- `tt-ui-style/APPLY-STYLE.md` — step-by-step design system application instructions
- `tt-ui-style/style.html` — canonical Phantom component reference

---

## 2. Monorepo layout

```
tt-nm/
├── apps/
│   └── web/                  # Next.js 16 — frontend + auth + tile proxy (one app, no separate API service)
├── packages/
│   └── db/                   # Both schemas, Martin SQL function sources, seed data
├── docker-compose.yml         # PostgreSQL 17 + PostGIS + Martin (internal network only)
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
| Styling | Tailwind CSS + shadcn/ui + Phantom tokens | See Section 7 |
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

### `network_model` — the property graph
All network data, data dictionary, and view specs. Queried via raw `postgres.js`.
```
network_model.class_definition
network_model.attribute_definition
network_model.class_attribute_config
network_model.view_definition
network_model.view_column_spec
network_model.object
network_model.relationship
network_model.state
```

**Never** write `public.object` or `data.object`. Always qualify: `network_model.object`.

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

See `TILE_AUTH.md` for the complete Route Handler implementation and Auth.js session callback code.

---

## 7. Auth.js session setup

Auth.js does not include application roles in the session by default. The `jwt` and `session` callbacks in `auth.ts` must look up the role from `iam.user_roles` and attach it. The TypeScript type for `Session` must be augmented in `types/next-auth.d.ts`.

Full implementation is in `TILE_AUTH.md` Section 5. Do not skip this — without it, `session.user.role` is undefined and the tile proxy will reject all requests.

JIT provisioning runs in the `signIn` callback: check `iam.users` for the OIDC `sub` claim; if absent, insert the user and assign the default role.

---

## 8. Next.js 16 conventions

- **Default to Server Components.** Add `'use client'` only when the component needs interactivity or browser APIs (MapLibre, event handlers, hooks).
- **Push `'use client'` as far down the tree as possible.** The map component is `'use client'`; its parent layout is not.
- **All request APIs are async:** `await cookies()`, `await headers()`, `await params`, `await searchParams`.
- **Data mutations use Server Actions** (`'use server'`), not Route Handlers (except the tile proxy and any public API endpoints).
- **Proxy file:** `proxy.ts` at the same level as `app/` (or inside `src/` if using src dir), not `middleware.ts`.

---

## 9. Design system — Phantom

The UI uses the taigrteam "Phantom" design system built on shadcn/ui + Tailwind CSS.

**Setup order (must be followed exactly):**
1. `npx shadcn@latest init` — choose CSS variables mode
2. Immediately replace generated CSS variables in `globals.css` with Phantom tokens (before adding any component)
3. Set `borderRadius: '0'` in `tailwind.config`
4. Add Orbitron + Roboto Google Fonts to the layout
5. Then `npx shadcn add <component>` — components inherit correct tokens from the start

**Canonical tokens:**
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

**Rules:**
- `border-radius: 0` on all interactive and container elements — no exceptions
- Elevated elements: `box-shadow: 6px 6px 0 var(--shadow-col)` — no blur/spread shadows
- Headings: `font-family: 'Orbitron', sans-serif`
- Body/UI/labels: `font-family: 'Roboto', sans-serif`
- Code/mono: `font-family: 'Courier New', monospace`
- `--text-muted` opacity must be ≥ 0.65 — values below this fail WCAG AA contrast

See `tt-ui-style/APPLY-STYLE.md` for the full checklist. See `tt-ui-style/style.html` for the live component reference.

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
- **Docker compose.** The `martin` service must never have a `ports` mapping. The `postgres` service exposes port 5432 to the host for local development only.
- **No speculative features.** Build exactly what is asked. Do not add error boundaries, loading states, or utility helpers that are not needed for the current phase.
