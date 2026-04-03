export { auth as middleware } from "@/auth";

export const config = {
  // Protect all routes except Auth.js internals, static assets, and the sign-in page itself.
  matcher: ["/((?!api/auth|_next/static|_next/image|favicon.ico|signin).*)"],
};
