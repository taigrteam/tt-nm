# tt-nm — Network Model & Viewer

A spatial network modelling and visualisation platform built by taigrteam. The primary focus is representing complex physical and logical networks (such as electrical grids) in a structured database and rendering them on an interactive map with enterprise-grade access control.

## What it does

**Network modelling**
- Represents networks as a property graph — objects (nodes), relationships (edges), and their attributes — stored in PostgreSQL/PostGIS
- Uses a metadata-driven schema (the Data Dictionary) that is self-describing and supports recursive class inheritance

**Visualisation**
- Renders the network spatially on an interactive WebGPU-accelerated map (MapLibre GL JS v5)
- Tiles are served by a high-performance Rust tile server (Martin) via PostGIS function sources

**Security & access control**
- Attribute-level security enforced at the database level — roles and permissions govern which attributes are visible per user before tiles are encoded
- Users authenticate via OIDC (Google / Microsoft Entra ID) with Just-In-Time provisioning; IdP groups map to internal roles

The schema is bitemporal (every record carries `valid_from`/`valid_to`) as a foundation for point-in-time reconstruction, though the current focus is on accurate network representation and visualisation. Historical querying may be extended in future.

## Structure

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Session brief — stack decisions, security invariants, coding rules |
| `apps/web/` | Next.js 16 app — frontend, Auth.js, tile proxy Route Handler |
| `packages/db/init/` | Authoritative DDL — extensions, both schemas, seed data, PostGIS function sources |
| `docker-compose.yml` | PostgreSQL 17 + PostGIS + Martin (Martin is internal-only, no host port) |
| `docker/` | `Dockerfile.db` and `martin-config.yaml` |

## Stack

- **PostGIS** — spatial relational database; nodes and edges modelled as points and linestrings
- **Martin (Rust)** — vector tile server; serves PostGIS function sources with attribute-level security
- **Next.js 16** — frontend, auth (Auth.js v5), and secure tile proxy (Route Handlers)
- **MapLibre GL JS v5** — WebGPU map renderer
- **pnpm monorepo** — `apps/web`, `packages/db`; deployable to Docker/WSL2 locally and AKS
