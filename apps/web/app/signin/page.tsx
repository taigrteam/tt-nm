import { signIn } from "@/auth";

export default function SignInPage() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "var(--bg)",
      }}
    >
      <div
        style={{
          width: "100%",
          maxWidth: "400px",
          padding: "2.5rem",
          border: "1px solid var(--border-col)",
          boxShadow: "6px 6px 0 var(--shadow-col)",
          backgroundColor: "var(--card-bg)",
        }}
      >
        <h1
          style={{
            fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
            fontSize: "1.25rem",
            fontWeight: 700,
            letterSpacing: "0.05em",
            marginBottom: "0.25rem",
            color: "var(--text)",
          }}
        >
          tt-nm
        </h1>
        <p
          style={{
            fontSize: "0.875rem",
            color: "var(--text-muted)",
            marginBottom: "2rem",
          }}
        >
          Network Model &amp; Viewer — sign in to continue
        </p>

        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          <form
            action={async () => {
              "use server";
              await signIn("google", { redirectTo: "/" });
            }}
          >
            <button
              type="submit"
              style={{
                width: "100%",
                padding: "0.625rem 1rem",
                backgroundColor: "var(--accent)",
                color: "var(--accent-fg)",
                border: "1px solid var(--border-col)",
                borderRadius: 0,
                fontFamily: "var(--font-roboto), Roboto, sans-serif",
                fontWeight: 500,
                fontSize: "0.875rem",
                cursor: "pointer",
                textAlign: "center",
              }}
            >
              Sign in with Google
            </button>
          </form>

          <form
            action={async () => {
              "use server";
              await signIn("microsoft-entra-id", { redirectTo: "/" });
            }}
          >
            <button
              type="submit"
              style={{
                width: "100%",
                padding: "0.625rem 1rem",
                backgroundColor: "var(--bg)",
                color: "var(--text)",
                border: "1px solid var(--border-col)",
                borderRadius: 0,
                fontFamily: "var(--font-roboto), Roboto, sans-serif",
                fontWeight: 500,
                fontSize: "0.875rem",
                cursor: "pointer",
                textAlign: "center",
              }}
            >
              Sign in with Microsoft
            </button>
          </form>
        </div>
      </div>
    </main>
  );
}
