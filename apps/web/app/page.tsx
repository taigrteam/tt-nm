import Link from "next/link";

export default function Home() {
  return (
    <main
      className="flex flex-col items-center justify-center min-h-screen gap-8 px-6"
      style={{ backgroundColor: "var(--bg)" }}
    >
      <div className="flex flex-col items-center gap-3 text-center">
        <h1
          style={{
            fontFamily: "'Orbitron', sans-serif",
            fontSize: "clamp(1.6rem, 4vw, 2.8rem)",
            fontWeight: 900,
            color: "var(--text)",
            letterSpacing: "0.08em",
          }}
        >
          tt-nm
        </h1>
        <p
          style={{
            fontFamily: "'Roboto', sans-serif",
            fontSize: "0.95rem",
            color: "var(--text-muted)",
            maxWidth: "30ch",
          }}
        >
          Network model &amp; spatial visualisation platform
        </p>
      </div>

      <Link href="/map" className="btn-accent-cta">
        Open Map
      </Link>
    </main>
  );
}
