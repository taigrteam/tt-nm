import { auth, signOut } from "@/auth";
import { redirect } from "next/navigation";
import NetworkMap from "./components/network-map";

export default async function Home() {
  const session = await auth();

  if (!session?.user) {
    redirect("/signin");
  }

  return (
    <div style={{ position: "relative", width: "100vw", height: "100vh" }}>
      <NetworkMap />

      {/* Floating session bar — Phase 5 verification + sign-out */}
      <div
        style={{
          position: "absolute",
          top: "0.75rem",
          right: "0.75rem",
          zIndex: 10,
          display: "flex",
          alignItems: "center",
          gap: "0.75rem",
          padding: "0.5rem 0.75rem",
          backgroundColor: "var(--card-bg)",
          border: "1px solid var(--border-col)",
          boxShadow: "4px 4px 0 var(--shadow-col)",
          fontFamily: "var(--font-roboto), Roboto, sans-serif",
          fontSize: "0.8rem",
        }}
      >
        <span>
          {session.user.name}{" "}
          <span style={{ color: "var(--text-muted)" }}>
            ({session.user.role})
          </span>
        </span>
        <form
          action={async () => {
            "use server";
            await signOut({ redirectTo: "/signin" });
          }}
        >
          <button
            type="submit"
            style={{
              padding: "0.25rem 0.5rem",
              backgroundColor: "var(--bg)",
              color: "var(--text)",
              border: "1px solid var(--border-col)",
              borderRadius: 0,
              fontSize: "0.75rem",
              cursor: "pointer",
            }}
          >
            Sign out
          </button>
        </form>
      </div>
    </div>
  );
}
