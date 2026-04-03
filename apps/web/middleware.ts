export { auth as middleware } from "@/auth";

export const config = {
  // Only run middleware on page routes — not API routes or static assets.
  // API routes (including /api/tiles) handle auth themselves and must return 401, not redirect.
  matcher: ["/((?!api/|_next/static|_next/image|favicon.ico|signin).*)"],
};
