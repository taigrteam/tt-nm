import NextAuth from "next-auth";
import Google from "next-auth/providers/google";
import MicrosoftEntraID from "next-auth/providers/microsoft-entra-id";
import { db } from "@/lib/db";
import { users, roles, userRoles } from "@/lib/schema";
import { eq } from "drizzle-orm";

export const { handlers, auth, signIn, signOut } = NextAuth({
  pages: {
    signIn: "/signin",
  },
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
      // On initial sign-in, account is present. Look up the role by OIDC sub.
      if (account?.providerAccountId) {
        const sub = account.providerAccountId;

        const result = await db
          .select({ name: roles.name })
          .from(users)
          .innerJoin(userRoles, eq(userRoles.userId, users.id))
          .innerJoin(roles, eq(roles.id, userRoles.roleId))
          .where(eq(users.sub, sub))
          .limit(1);

        token.role = result[0]?.name ?? "viewer";
        token.sub = sub;
      }
      return token;
    },

    async session({ session, token }) {
      // Expose role on the session so the tile proxy can read it server-side.
      if (session.user) {
        session.user.role = token.role as string;
      }
      return session;
    },
  },
});
