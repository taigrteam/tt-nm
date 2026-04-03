# APPLICATION.md

## 1. Project Overview & Background
The application is a high-performance, spatial-graph visualization and reporting platform. The core challenge is to visualize complex, network topologies spatially with enterprise-grade security (RBAC) and modern identity integration (OIDC). 

The solution utilizes a **Decoupled Spatial Stack** to ensure maximum performance on a 32GB RAM workstation and seamless scalability to Azure Kubernetes Service (AKS). By moving away from monolithic GIS frameworks (like GeoNode), we gain granular control over data flow and minimize the "token noise" for AI-assisted development.

### 1.1 Rationale for the Stack
* **PostGIS:** The industry standard for spatial data. It handles the "Graph" logic by treating points as nodes and linestrings as edges.
* **Martin (Rust):** A blazing-fast tile server that replaces GeoServer. It has a negligible memory footprint (<500MB) and serves standard Mapbox Vector Tiles (MVT). High-performance WebGPU rendering of those tiles is handled client-side by MapLibre GL JS.
* **Next.js (v16+):** Serves as both the React frontend (App Router / RSC) and the secure tile proxy (Route Handlers). Replaces a separate Fastify service — Route Handlers on the Node.js runtime handle high-concurrency tile proxying with no meaningful performance penalty over a dedicated proxy.
* **MapLibre GL JS v5:** Utilizes WebGPU for rendering massive datasets at 60fps, essential for interactive graph exploration and time-series animations.

---

## 2. Design Decisions
### 2.1 Identity & Provisioning
We utilize **Just-In-Time (JIT) Provisioning** via OIDC (Google and Microsoft Entra ID).
* **Decision:** Users are not manually created. The system creates or updates a user record upon their first successful login based on the `sub` claim.
* **Mapping:** IdP Groups (from Azure/Google) are mapped to internal Roles via a dedicated `idp_group_mappings` table, ensuring identity stays in the IdP while permissions stay in the App.

### 2.2 Namespaced RBAC (Convention over Configuration)
* **Decision:** Use a string-based convention for permissions: `service:resource:action`.
* **Benefit:** Allows for wildcard matching (e.g., `map:*`) and grouping without needing a complex nested category schema. This makes the system highly "AI-readable" for Claude Sonnet.

### 2.3 Attribute-Level Security
* **Decision:** Security is enforced at the Database/Proxy level, not the Map client.
* **Mechanism:** The Next.js Route Handler proxy injects the `user_role` into Martin's request via query parameters. The role is derived exclusively from the server-side Auth.js session — never from the client request. Martin passes these to PostGIS **Function Sources**, which return different data (redacted columns) based on the user's rights before the tile is ever encoded.

---

## 3. Implementation Instructions for Claude Sonnet

### 3.1 Workspace Setup
1.  Initialize a **pnpm monorepo** with one app: `apps/web` (Next.js 16 — handles frontend, auth, and tile proxy).
2.  Create a shared package `packages/db` for both schema definitions (`iam` and `network_model`) and Martin SQL function sources.
3.  Use **Docker Engine** (native on WSL2) to run Postgres 17 and Martin.

### 3.2 Database Implementation
1.  Apply the schema provided in **Section 4.1**.
2.  Ensure PostGIS is enabled (`CREATE EXTENSION postgis;`).
3.  Implement the **Function Source** pattern for Martin (Section 4.3). Martin should point to these functions rather than raw tables to ensure security.

### 3.3 Auth/Proxy Implementation
1.  Use **Auth.js v5** (`next-auth@beta`) for the OIDC handshake with Google and Microsoft Entra ID.
2.  Implement `jwt` and `session` callbacks in `auth.ts` to look up the user's role from `iam.user_roles` and attach it to the session token (see Section 4.2).
3.  Implement a tile proxy Route Handler at `app/api/tiles/[...path]/route.ts`. It must call `auth()` server-side, reject unauthenticated requests with `401`, and append the role exclusively from the session — never from the incoming client request.

### 3.4 Frontend Implementation
1.  Initialise MapLibre with an **OpenStreetMap raster tile background** as the base layer (layer ID: `"osm-background"`). Network data layers sit on top of this. OSM attribution must remain visible at all times.
2.  Configure the network vector tile source pointing at the Next.js tile proxy (`/api/tiles/...`). The browser session cookie is attached automatically — no `transformRequest` needed.
3.  Implement "Feature State" for hover effects to ensure the GPU handles styling changes without re-downloading tiles.
4.  Use the `description` field from the permissions table to generate dynamic tooltips or "Access Denied" overlays.

**Note on OSM layer:** The `"osm-background"` layer ID must be stable from day one. Future requirements include toggling visibility and adjusting opacity/greyscale — these are not implemented yet but the layer ID must not change when they are added.

---

## 4. Technical Specifications & Code Reference

### 4.1 Database Schema (DDL)
Refer to this schema for all JIT and RBAC logic.

```sql
CREATE SCHEMA IF NOT EXISTS iam;
SET search_path TO iam;

-- Identity Management
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sub TEXT UNIQUE NOT NULL,          -- OIDC Subject ID
    email TEXT UNIQUE NOT NULL,
    idp_source TEXT NOT NULL,          -- 'google' | 'microsoft'
    last_login TIMESTAMPTZ DEFAULT NOW()
);

-- Namespaced RBAC
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,         -- Format: 'service:resource:action'
    description TEXT NOT NULL          -- Used by Claude for logic inference
);

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE role_permissions (
    role_id INT REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id INT REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- JIT Mapping
CREATE TABLE idp_group_mappings (
    idp_group_id TEXT PRIMARY KEY,     -- The GUID/Object ID from the IdP
    role_id INT REFERENCES roles(id)
);
