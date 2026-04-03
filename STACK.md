# STACK.md: 

This document defines the 2026 software components and dependencies for the High-Performance Spatial Graph System. This stack is optimized for **Next.js 16**, **PostgreSQL 17**
---

## 1. Core Framework & Identity
* **Next.js (v16+)**: Core application framework using **App Router**. Handles React Server Components (RSC) for metadata and Route Handlers for tile proxying.
* **Auth.js (v5 Beta)**: Primary OIDC integration for **Microsoft Entra ID** and **Google**. Provides the `signIn` callback for Just-In-Time (JIT) user provisioning.
* **jose**: Lightweight JWT utility for manual verification and signing of internal service tokens with zero-dependency overhead.

## 2. Database Layer (PostgreSQL & PostGIS)
The database is the "Source of Truth" for both identity and geometry.

### 2.1 Core Database Components
* **PostgreSQL (v17+)**: Utilizing native JSONB for OIDC claims and partitioned tables for time-series logs.
* **PostGIS (v3.5+)**: 
    * `ST_AsMVT`: Used within **Function Sources** to generate vector tiles dynamically.
    * `ST_TileEnvelope`: For efficient spatial indexing during tile requests.
    * `pg_routing`: For graph-pathfinding logic on the server side. Requires explicit installation: `CREATE EXTENSION pgrouting;` (must be run after PostGIS).

### 2.2 Data Access & ORM
* **Drizzle ORM**: TypeScript ORM used exclusively for the `iam` schema (users, roles, permissions). Provides type-safe RBAC lookups with generated TypeScript types from the schema.
* **postgres.js**: The high-performance SQL client for Node.js, used for all `network_model` queries (property graph, JSONB, recursive CTEs, spatial). Preferred over `pg` for its memory management and native `camelCase`↔`snake_case` transformation.
* **Drizzle Kit**: CLI for generating and running migrations against the `iam` schema only. `network_model` migrations are handled via raw SQL files.

## 3. Spatial & Tile Engine
* **Martin (Rust)**: The dynamic tile server. It connects to PostGIS and serves MVTs. It is kept internal to the network, accessible only via the Next.js proxy.
* **MapLibre GL JS (v5)**: Client-side engine using **WebGPU**. Optimized for rendering "Spider-web" graph topologies at 60fps.
* **Zod**: Used to validate `z/x/y` tile coordinates and incoming spatial GeoJSON fragments to prevent SQL injection in custom PostGIS queries.

## 4. UI & Visualization
* **Tailwind CSS**: Utility-first styling.
* **Lucide React**: Icon set for GIS toolbars (Layers, Zoom, Measure, Filter).
* **shadcn/ui**: Radix-based components for high-accessibility sidebars and attribute tables.
* **Turf.js**: For client-side spatial calculations (buffers, intersections, and distance) to reduce server round-trips.

---

## 5. Summary Dependency List
Copy these into your `package.json` to initialize the project:

| Category | Dependency | Purpose |
| :--- | :--- | :--- |
| **Auth** | `next-auth@beta` | OIDC Handshake & JIT Provisioning. |
| **Identity** | `jose` | Secure JWT handling. |
| **ORM** | `drizzle-orm` | Type-safe SQL for `iam` schema. |
| **Driver** | `postgres` | Fastest Node.js PostgreSQL client. |
| **Map** | `maplibre-gl` | WebGPU-powered rendering. |
| **Spatial** | `@turf/turf` | Client-side geometry logic. |
| **Validation** | `zod` | RBAC and Coordinate validation. |
| **Icons** | `lucide-react` | GIS Interface icons. |

---

## 6. Implementation Notes for Claude Code
1.  **Schema Namespacing**: All identity and access management tables MUST use the `iam` schema. All network model tables (objects, relationships, states, data dictionary) MUST use the `network_model` schema. Never mix tables across schemas.
2.  **Proxying**: Always use Next.js Route Handlers (`app/api/tiles/[...path]/route.ts`) to wrap Martin requests. This is where `iam` roles are injected into the PostGIS query.
3.  **Strict Typing**: Generate Drizzle schemas from the SQL provided in `APPLICATION.md` to ensure full type-safety between the DB and the Map UI.