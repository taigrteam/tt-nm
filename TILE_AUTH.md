# TILE_AUTH.md: Secure Tile Authentication Specification

## 1. Executive Summary
This document outlines the preferred architectural pattern for authenticating **MapLibre GL JS** requests to the **Next.js Tile Proxy**. The goal is to ensure high performance for spatial "Graph" data while maintaining a "Zero-Trust" posture at the attribute level.

---

## 2. Preferred Option: HttpOnly Session Cookies
For a browser-based GIS, the system will use **SameSite HttpOnly Cookies** rather than manual JWT headers.

### 2.1 Rationale
* **Security (XSS Mitigation):** Because the cookie is marked `HttpOnly`, malicious scripts cannot access the session token.
* **Simplicity:** The browser automatically attaches the cookie to all outgoing `fetch` and `XHR` requests to the same origin, reducing the complexity of the MapLibre implementation.
* **Standardization:** This aligns with **Auth.js (v5)** and **Next.js** default security behaviors.

---

## 3. Technical Workflow

### 3.1 The Authentication Handshake
1.  **User Logs In:** User authenticates via OIDC (Google/Microsoft).
2.  **Session Creation:** Next.js creates an encrypted session and sets a cookie: `Set-Cookie: __Secure-authjs.session-token=...; HttpOnly; Secure; SameSite=Lax`.
3.  **JIT Check:** The `iam.users` table is checked; if the user is new, they are provisioned with default roles.

### 3.2 The Tile Request Loop
1.  **MapLibre Initiates:** MapLibre requests a tile from `/api/tiles/pipes/{z}/{x}/{y}`.
2.  **Automatic Attachment:** The browser automatically includes the session cookie.
3.  **Proxy Validation:**
    * The Next.js Route Handler calls `auth()`.
    * If no session exists, it returns `401 Unauthorized`.
    * If a session exists, it retrieves the `iam.role` associated with the user.
4.  **Martin Upstream:** The proxy fetches the tile from Martin, appending the role:
    `http://martin:3000/pipes/{z}/{x}/{y}?role=admin`
5.  **PostGIS Redaction:** The database filters columns (e.g., hiding `cost_data` from non-admins) before returning the binary MVT.

---

## 4. Implementation Details

### 4.1 Next.js Route Handler (The Guard)
```typescript
// app/api/tiles/[...path]/route.ts
import { auth } from "@/auth";
import { NextResponse } from "next/server";

export async function GET(req: Request, { params }: { params: Promise<{ path: string[] }> }) {
  const session = await auth();

  if (!session?.user?.role) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const martinBase = process.env.MARTIN_INTERNAL_URL;
  const { path: pathSegments } = await params; // Next.js 16: params is a Promise
  const path = pathSegments.join("/");

  // Forward request to Martin with internal role injection
  // IMPORTANT: role is derived exclusively from the server-side session — never from the client request
  const url = `${martinBase}/${path}?user_role=${session.user.role}`;

  const res = await fetch(url);
  return new NextResponse(res.body, {
    headers: {
      "Content-Type": "application/x-protobuf",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
```

---

## 5. Auth.js Session Callbacks (Role Injection)

Auth.js v5 does not include application roles in the session by default. The `jwt` and `session` callbacks in `auth.ts` must look up the user's role from `iam.user_roles` and attach it to the token on every sign-in.

```typescript
// auth.ts
import NextAuth from "next-auth";
import { db } from "@/packages/db"; // postgres.js client

export const { handlers, auth, signIn, signOut } = NextAuth({
  callbacks: {
    async jwt({ token, user }) {
      // On initial sign-in, user object is present — look up role
      if (user?.email) {
        const result = await db`
          SELECT r.name
          FROM iam.users u
          JOIN iam.user_roles ur ON ur.user_id = u.id
          JOIN iam.roles r ON r.id = ur.role_id
          WHERE u.email = ${user.email}
          LIMIT 1
        `;
        token.role = result[0]?.name ?? "viewer";
      }
      return token;
    },
    async session({ session, token }) {
      // Expose role on the session object for use in Route Handlers
      if (session.user) {
        session.user.role = token.role as string;
      }
      return session;
    },
  },
});
```

The `session.user.role` field referenced in the tile proxy (Section 4.1) is populated by these callbacks. The TypeScript type for `session.user` must be augmented to include `role`:

```typescript
// types/next-auth.d.ts
import { DefaultSession } from "next-auth";

declare module "next-auth" {
  interface Session {
    user: { role: string } & DefaultSession["user"];
  }
  interface JWT {
    role?: string;
  }
}
```

---

## 6. Actionable Guardrail for Claude Code Implementation

**CRITICAL SECURITY ENFORCEMENT:**
When generating infrastructure and proxy logic, Claude must adhere to the following "Internal-Only" pattern to prevent unauthorized role escalation:

1. **Network Isolation:** - In `docker-compose.yml`, the `martin` service must **NOT** have a `ports` mapping to the host (e.g., no `3000:3000`). It must only be reachable via the internal Docker bridge network by the `nextjs` service.
   - In Kubernetes manifests, the Martin `Service` must be type `ClusterIP`, never `LoadBalancer` or `NodePort`.

2. **Proxy Header Scrubbing:**
   - The Next.js Route Handler must **ignore and strip** any `user_role` or `role` parameters sent by the client's browser. 
   - The `user_role` sent to Martin must be derived **exclusively** from the server-side `auth()` session object.

3. **Validation Step:**
   - Before completing any tile-server task, Claude must verify that a direct `curl` to Martin from the host machine (outside the Docker network) fails, while a `curl` to the Next.js `/api/tiles` endpoint succeeds with a valid session cookie.