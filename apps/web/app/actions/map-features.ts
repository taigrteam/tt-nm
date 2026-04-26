"use server";

import { sql } from "@/lib/db";

/**
 * Returns [minLng, minLat, maxLng, maxLat] for the given network_model.object UUID,
 * or null if the object has no geometry or does not exist.
 */
export async function getFeatureBounds(
  uuid: string,
): Promise<[number, number, number, number] | null> {
  const rows = await sql<
    { min_lng: number; min_lat: number; max_lng: number; max_lat: number }[]
  >`
    SELECT
      ST_XMin(geo_geometry) AS min_lng,
      ST_YMin(geo_geometry) AS min_lat,
      ST_XMax(geo_geometry) AS max_lng,
      ST_YMax(geo_geometry) AS max_lat
    FROM network_model.object
    WHERE uuid = ${uuid}::uuid
  `;

  if (rows.length === 0 || rows[0].min_lng == null) return null;
  const { min_lng, min_lat, max_lng, max_lat } = rows[0];
  return [min_lng, min_lat, max_lng, max_lat];
}
