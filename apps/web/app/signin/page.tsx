import { signIn } from "@/auth";

export default function SignInPage() {
  return (
    <main
      className="flex min-h-screen items-center justify-center"
      style={{ backgroundColor: "var(--bg)" }}
    >
      <div
        className="w-full max-w-[400px] p-8"
        style={{
          border: "3px solid var(--border-col)",
          boxShadow: "6px 6px 0 var(--shadow-col)",
          backgroundColor: "var(--card-bg)",
        }}
      >
        {/* Brand */}
        <h1
          className="text-xl font-black tracking-wide"
          style={{
            fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
            color: "var(--text)",
          }}
        >
          t<span style={{ color: "var(--accent)" }}>ai</span>grteam
        </h1>
        <p
          className="mt-1 mb-8 text-sm"
          style={{ color: "var(--text-muted)" }}
        >
          Network Model &amp; Viewer — sign in to continue
        </p>

        <div className="flex flex-col gap-3">
          <form
            action={async () => {
              "use server";
              await signIn("google", { redirectTo: "/" });
            }}
          >
            <button
              type="submit"
              className="w-full cursor-pointer px-4 py-2.5 text-sm font-bold tracking-wide transition-all hover:shadow-[4px_4px_0_var(--text)]"
              style={{
                backgroundColor: "var(--accent)",
                color: "var(--accent-fg)",
                border: "3px solid var(--accent)",
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
              className="w-full cursor-pointer px-4 py-2.5 text-sm font-bold tracking-wide transition-opacity hover:opacity-85"
              style={{
                backgroundColor: "transparent",
                color: "var(--text)",
                border: "3px solid var(--border-col)",
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
