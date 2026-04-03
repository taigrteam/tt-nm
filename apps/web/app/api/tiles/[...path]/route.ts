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

export async function GET(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const session = await auth();

  if (!session?.user?.role) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const { path: segments } = await params;

  // Validate that the last three segments are valid tile coordinates.
  // Path format from Martin: /{source}/{z}/{x}/{y}
  if (segments.length < 4) {
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

  // Reconstruct the clean path — never forward any client-supplied query params.
  // Role is injected exclusively from the server-side session.
  const tilePath = segments.join("/");
  const martinUrl = `${martinBase}/${tilePath}?user_role=${session.user.role}`;

  const martinRes = await fetch(martinUrl);

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
