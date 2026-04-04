import { auth } from "@/auth";
import { NextResponse } from "next/server";
import { z } from "zod";

// Tile coordinate schema — validates the last three path segments.
// Coordinates must be non-negative integers; z is capped at 30.
const tileCoordSchema = z.object({
  z: z.coerce.number().int().min(0).max(30),
  x: z.coerce.number().int().min(0),
  y: z.coerce.number().int().min(0),
});

// Allowlist of valid Martin function sources. Requests for any other source
// are rejected — this prevents path traversal and access to unintended endpoints.
const VALID_SOURCES = new Set(["network_objects"]);

// In-memory rate limiter: per-IP sliding window (1 minute, 300 requests).
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 300;
const requestLog = new Map<string, number[]>();

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps = requestLog.get(ip) ?? [];
  const recent = timestamps.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  recent.push(now);
  requestLog.set(ip, recent);
  return recent.length > RATE_LIMIT_MAX;
}

// Fetch timeout for Martin requests (10 seconds).
const MARTIN_TIMEOUT_MS = 10_000;

export async function GET(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  // Rate limit by IP.
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (isRateLimited(ip)) {
    return new NextResponse("Too Many Requests", { status: 429 });
  }

  const session = await auth();

  if (!session?.user?.role) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const { path: segments } = await params;

  // Path format from Martin: /{source}/{z}/{x}/{y}
  if (segments.length < 4) {
    return new NextResponse("Bad Request", { status: 400 });
  }

  // Validate source name against allowlist — blocks path traversal and unknown sources.
  const source = segments[0];
  if (!VALID_SOURCES.has(source)) {
    return new NextResponse("Bad Request", { status: 400 });
  }

  // Validate that the last three segments are valid tile coordinates.
  const [zRaw, xRaw, yRaw] = segments.slice(-3);
  const coordResult = tileCoordSchema.safeParse({ z: zRaw, x: xRaw, y: yRaw });

  if (!coordResult.success) {
    return new NextResponse("Bad Request — invalid tile coordinates", { status: 400 });
  }

  const martinBase = process.env.MARTIN_INTERNAL_URL;
  if (!martinBase) {
    return new NextResponse("Internal Server Error", { status: 500 });
  }

  // Reconstruct the clean path — never forward any client-supplied query params.
  // Role is injected exclusively from the server-side session.
  const tilePath = segments.join("/");
  const martinUrl = `${martinBase}/${tilePath}?user_role=${session.user.role}`;

  // Fetch with timeout to prevent hanging connections.
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
