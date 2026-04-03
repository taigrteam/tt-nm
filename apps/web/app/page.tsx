import { auth, signOut } from "@/auth";
import { redirect } from "next/navigation";

export default async function Home() {
  const session = await auth();

  if (!session?.user) {
    redirect("/signin");
  }

  return (
    <main
      style={{
        minHeight: "100vh",
        padding: "2.5rem",
        backgroundColor: "var(--bg)",
        fontFamily: "var(--font-roboto), Roboto, sans-serif",
      }}
    >
      <h1
        style={{
          fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
          fontSize: "1.25rem",
          fontWeight: 700,
          letterSpacing: "0.05em",
          marginBottom: "2rem",
          color: "var(--text)",
        }}
      >
        tt-nm
      </h1>

      {/* Phase 3 verification — session dump */}
      <div
        style={{
          maxWidth: "600px",
          padding: "1.5rem",
          border: "1px solid var(--border-col)",
          boxShadow: "6px 6px 0 var(--shadow-col)",
          backgroundColor: "var(--card-bg)",
          marginBottom: "1.5rem",
        }}
      >
        <p style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginBottom: "0.75rem" }}>
          Phase 3 — session verification
        </p>
        <pre
          style={{
            fontFamily: "Courier New, monospace",
            fontSize: "0.8rem",
            backgroundColor: "var(--code-bg)",
            padding: "1rem",
            overflowX: "auto",
            whiteSpace: "pre-wrap",
            wordBreak: "break-all",
          }}
        >
          {JSON.stringify(
            {
              name: session.user.name,
              email: session.user.email,
              role: session.user.role,
            },
            null,
            2,
          )}
        </pre>
      </div>

      <form
        action={async () => {
          "use server";
          await signOut({ redirectTo: "/signin" });
        }}
      >
        <button
          type="submit"
          style={{
            padding: "0.5rem 1.25rem",
            backgroundColor: "var(--bg)",
            color: "var(--text)",
            border: "1px solid var(--border-col)",
            borderRadius: 0,
            fontFamily: "var(--font-roboto), Roboto, sans-serif",
            fontSize: "0.875rem",
            cursor: "pointer",
          }}
        >
          Sign out
        </button>
      </form>
    </main>
  );
}
