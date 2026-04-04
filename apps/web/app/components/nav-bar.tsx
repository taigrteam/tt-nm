import { auth, signOut } from "@/auth";
import { LogOut } from "lucide-react";

export default async function NavBar() {
  const session = await auth();

  return (
    <nav
      className="flex items-center justify-between px-5 py-2.5"
      style={{
        backgroundColor: "var(--text)",
        borderBottom: "3px solid var(--accent)",
      }}
    >
      {/* Brand */}
      <div
        className="whitespace-nowrap text-sm font-black tracking-wide"
        style={{
          fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
          color: "var(--bg)",
        }}
      >
        t<span style={{ color: "var(--accent)" }}>ai</span>grteam
        <span
          className="mx-2.5"
          style={{ color: "rgba(240,246,247,0.35)" }}
        >
          |
        </span>
        <span className="text-xs" style={{ color: "var(--bg)" }}>
          network model
        </span>
      </div>

      {/* User + sign out */}
      {session?.user && (
        <div className="flex items-center gap-3">
          <span
            className="text-xs"
            style={{ color: "rgba(240,246,247,0.65)" }}
          >
            {session.user.name}
          </span>
          <span
            className="px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-widest"
            style={{
              border: "2px solid var(--accent)",
              color: "var(--accent)",
            }}
          >
            {session.user.role}
          </span>
          <form
            action={async () => {
              "use server";
              await signOut({ redirectTo: "/signin" });
            }}
          >
            <button
              type="submit"
              className="flex items-center gap-1.5 cursor-pointer px-2 py-1 text-xs font-bold tracking-wide transition-opacity hover:opacity-85"
              style={{
                border: "2px solid transparent",
                color: "rgba(240,246,247,0.65)",
                background: "transparent",
              }}
            >
              <LogOut size={14} />
              Sign out
            </button>
          </form>
        </div>
      )}
    </nav>
  );
}
