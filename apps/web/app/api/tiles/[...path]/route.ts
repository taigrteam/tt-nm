import { auth } from "@/auth";
import { NextResponse } from "next/server";
import { z } from "zod";
import { sql } from "@/lib/db";

// Tile coordinate schema — validates the last three path segments.
const tileCoordSchema = z.object({
  z: z.coerce.number().int().min(0).max(30),
  x: z.coerce.number().int().min(0),
  y: z.coerce.number().int().min(0),
});

// In-memory cache of valid Martin source names, loaded from data_dictionary.view_definition.
// Refreshed every 60 seconds so new views are picked up without restarting the server.
let validSourcesCache: Set<string> = new Set();
let cacheLoadedAt = 0;
const CACHE_TTL_MS = 60_000;

async function getValidSources(): Promise<Set<string>> {
  const now = Date.now();
  if (validSourcesCache.size > 0 && now - cacheLoadedAt < CACHE_TTL_MS) {
    return validSourcesCache;
  }
  const rows = await sql<{ view_name: string }[]>`
    SELECT view_name
    FROM data_dictionary.view_definition
    WHERE show_on_map = TRUE
      AND valid_to IS NULL
  `;
  validSourcesCache = new Set(rows.map((r) => r.view_name));
  cacheLoadedAt = now;
  return validSourcesCache;
}

// In-memory rate limiter: per-IP sliding window.
//
// Budget calculation: sources × tiles-per-viewport × viewport-changes-per-minute
//   ≈ 12 sources × 16 tiles × 15 changes = 2,880 → ceiling at 3,000.
// This handles normal interactive map usage without false positives.
// Note: in local dev all requests share key "unknown" (no x-forwarded-for),
// so the budget is effectively per-browser-session rather than per-IP.
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 3_000;
const requestLog = new Map<string, number[]>();

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps = requestLog.get(ip) ?? [];
  const recent = timestamps.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  recent.push(now);
  // Evict the entry once it empties to prevent unbounded map growth.
  if (recent.length === 0) {
    requestLog.delete(ip);
  } else {
    requestLog.set(ip, recent);
  }
  return recent.length > RATE_LIMIT_MAX;
}

const MARTIN_TIMEOUT_MS = 10_000;

export async function GET(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (isRateLimited(ip)) {
    return new NextResponse("Too Many Requests", { status: 429 });
  }

  const session = await auth();
  if (!session?.user?.role) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const { path: segments } = await params;

  if (segments.length < 4) {
    return new NextResponse("Bad Request", { status: 400 });
  }

  // Validate source name against DB-driven allowlist — blocks path traversal.
  const source = segments[0];
  const validSources = await getValidSources();
  if (!validSources.has(source)) {
    return new NextResponse("Bad Request", { status: 400 });
  }

  const [zRaw, xRaw, yRaw] = segments.slice(-3);
  const coordResult = tileCoordSchema.safeParse({ z: zRaw, x: xRaw, y: yRaw });
  if (!coordResult.success) {
    return new NextResponse("Bad Request — invalid tile coordinates", { status: 400 });
  }

  const martinBase = process.env.MARTIN_INTERNAL_URL;
  if (!martinBase) {
    return new NextResponse("Internal Server Error", { status: 500 });
  }

  // Role is injected from the server-side session only — never forwarded from the client.
  const tilePath = segments.join("/");
  const martinUrl = `${martinBase}/${tilePath}?user_role=${session.user.role}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), MARTIN_TIMEOUT_MS);

  let martinRes: Response;
  try {
    martinRes = await fetch(martinUrl, { signal: controller.signal });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") {
      return new NextResponse(null, { status: 504 });
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }

  if (!martinRes.ok) {
    return new NextResponse(null, { status: martinRes.status });
  }

  return new NextResponse(martinRes.body, {
    status: 200,
    headers: {
      "Content-Type": "application/x-protobuf",
      "Cache-Control": "private, max-age=300",
      "Vary": "Cookie",
    },
  });
}
