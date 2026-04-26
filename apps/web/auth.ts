import NextAuth from "next-auth";
import Google from "next-auth/providers/google";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";
import { db } from "@/lib/db";
import { users, roles, userRoles } from "@/lib/schema";
import { eq, asc } from "drizzle-orm";

export const { handlers, auth, signIn, signOut } = NextAuth({
  pages: {
    signIn: "/signin",
  },
  session: { maxAge: 3600 },
  providers: [
    ...(process.env.AUTH_GOOGLE_ID && process.env.AUTH_GOOGLE_SECRET
      ? [Google({
          clientId: process.env.AUTH_GOOGLE_ID,
          clientSecret: process.env.AUTH_GOOGLE_SECRET,
        })]
      : []),
    ...(process.env.AUTH_MICROSOFT_ENTRA_ID_ID &&
      process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET &&
      process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER
      ? [MicrosoftEntraID({
          clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID,
          clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET,
          issuer: process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER,
        })]
      : []),
  ],

  callbacks: {
    authorized({ auth: session }) {
      // Used by middleware: reject unauthenticated requests.
      return !!session?.user;
    },

    async signIn({ user, account }) {
      // JIT provisioning: insert user on first OIDC login if not already in iam.users.
      // The OIDC `sub` claim is the immutable identifier — never rely on email alone.
      const sub = account?.providerAccountId;
      const email = user.email;

      if (!sub || !email) {
        // Reject sign-in if the IdP did not supply the required claims.
        return false;
      }

      // Optional domain allowlist — reject emails outside permitted domains.
      const allowedDomains = process.env.ALLOWED_EMAIL_DOMAINS?.split(",").map(d => d.trim());
      if (allowedDomains && allowedDomains.length > 0) {
        const domain = email.split("@")[1];
        if (!domain || !allowedDomains.includes(domain)) {
          return false;
        }
      }

      const idpSource = account?.provider === "microsoft-entra-id" ? "microsoft" : "google";

      const existing = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.sub, sub))
        .limit(1);

      if (existing.length === 0) {
        // New user — provision with default 'viewer' role.
        const [viewerRole] = await db
          .select({ id: roles.id })
          .from(roles)
          .where(eq(roles.name, "viewer"))
          .limit(1);

        if (!viewerRole) {
          // Safety: viewer role must exist (seeded in 05_seed.sql).
          return false;
        }

        const [newUser] = await db
          .insert(users)
          .values({ sub, email, idpSource })
          .returning({ id: users.id });

        await db.insert(userRoles).values({ userId: newUser.id, roleId: viewerRole.id });
      } else {
        // Returning user — update last_login.
        await db
          .update(users)
          .set({ lastLogin: new Date() })
          .where(eq(users.sub, sub));
      }

      return true;
    },

    async jwt({ token, account }) {
      // Look up role on initial sign-in only (when account is present).
      // This callback also runs in the Edge runtime (middleware) where
      // postgres.js TCP connections are unavailable — so DB queries must
      // be limited to the Node.js sign-in flow. session.maxAge (1 hour)
      // bounds how long a stale role persists before re-authentication.
      if (account?.providerAccountId) {
        token.sub = account.providerAccountId;

        const result = await db
          .select({ name: roles.name })
          .from(users)
          .innerJoin(userRoles, eq(userRoles.userId, users.id))
          .innerJoin(roles, eq(roles.id, userRoles.roleId))
          .where(eq(users.sub, token.sub))
          .orderBy(asc(roles.name))
          .limit(1);

        token.role = result[0]?.name ?? "viewer";
      }
      return token;
    },

    async session({ session, token }) {
      // Expose role and sub on the session so server components and actions can read them.
      if (session.user) {
        session.user.role = token.role as string;
        session.user.sub  = token.sub  as string;
      }
      return session;
    },
  },
});
