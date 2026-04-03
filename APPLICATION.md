# APPLICATION.md

## 1. Project Overview & Background
The application is a high-performance, spatial-graph visualization and reporting platform. The core challenge is to visualize complex, network topologies spatially with enterprise-grade security (RBAC) and modern identity integration (OIDC). 

The solution utilizes a **Decoupled Spatial Stack** to ensure maximum performance on a 32GB RAM workstation and seamless scalability to Azure Kubernetes Service (AKS). By moving away from monolithic GIS frameworks (like GeoNode), we gain granular control over data flow and minimize the "token noise" for AI-assisted development.

### 1.1 Rationale for the Stack
* **PostGIS:** The industry standard for spatial data. It handles the "Graph" logic by treating points as nodes and linestrings as edges.
* **Martin (Rust):** A blazing-fast tile server that replaces GeoServer. It has a negligible memory footprint ($<500$MB) and supports modern vector tile features like WebGPU-optimized MVT.
* **Fastify (Node.js):** A low-overhead framework chosen for its speed and its ability to act as a high-concurrency proxy between the frontend and the tile server.
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
* **Mechanism:** The Fastify proxy injects the `user_role` into Martin's request via query parameters. Martin passes these to PostGIS **Function Sources**, which return different data (redacted columns) based on the user's rights before the tile is ever encoded.

---

## 3. Implementation Instructions for Claude Sonnet

### 3.1 Workspace Setup
1.  Initialize a **pnpm monorepo** with two main apps: `apps/api` (Fastify) and `apps/web` (MapLibre/React).
2.  Create a shared package `packages/db` for schema definitions and migrations.
3.  Use **Docker Engine** (native on WSL2) to run Postgres 17 and Martin.

### 3.2 Database Implementation
1.  Apply the schema provided in **Section 4.1**.
2.  Ensure PostGIS is enabled (`CREATE EXTENSION postgis;`).
3.  Implement the **Function Source** pattern for Martin (Section 4.3). Martin should point to these functions rather than raw tables to ensure security.

### 3.3 Auth/Proxy Implementation
1.  Use `openid-client` to handle the OIDC handshake.
2.  Implement a Fastify `preHandler` hook that extracts the JWT, identifies the user, and fetches their permission slugs.
3.  Implement a proxy route (`/tiles/*`) that forwards requests to Martin. It must append the user's role/ID to the internal query string.

### 3.4 Frontend Implementation
1.  Configure MapLibre to use the Vector Tile source provided by the Proxy.
2.  Implement "Feature State" for hover effects (Section 4.2) to ensure the GPU handles styling changes without re-downloading tiles.
3.  Use the `description` field from the permissions table to generate dynamic tooltips or "Access Denied" overlays.

---

## 4. Technical Specifications & Code Reference

### 4.1 Database Schema (DDL)
Refer to this schema for all JIT and RBAC logic.

```sql
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
