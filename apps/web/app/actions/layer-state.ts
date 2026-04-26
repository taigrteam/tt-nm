"use server";

import { auth } from "@/auth";
import { sql } from "@/lib/db";

export async function saveLayerVisibility(
  updates: Array<{ viewName: string; visible: boolean }>,
): Promise<void> {
  if (updates.length === 0) return;

  const session = await auth();
  const sub = session?.user?.sub;
  if (!sub) return;

  const toAdd    = updates.filter((u) => u.visible).map((u) => u.viewName);
  const toRemove = updates.filter((u) => !u.visible).map((u) => u.viewName);

  if (toAdd.length > 0) {
    await sql`
      INSERT INTO network_views.layer_visibility_state (user_sub, view_name)
      SELECT ${sub}, unnest(${toAdd}::text[])
      ON CONFLICT DO NOTHING
    `;
  }
  if (toRemove.length > 0) {
    await sql`
      DELETE FROM network_views.layer_visibility_state
      WHERE user_sub  = ${sub}
        AND view_name = ANY(${toRemove}::text[])
    `;
  }
}
