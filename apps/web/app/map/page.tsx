import NavBar from "@/app/components/nav-bar";
import MapShell from "@/app/components/map-shell";
import { auth } from "@/auth";
import { sql } from "@/lib/db";
import type { ColumnSpec, NamespaceGroup, ViewLayer } from "@/lib/map-types";

interface ViewDefinitionRow {
  namespace: string;
  display_name_ns: string;
  view_name: string;
  display_name_view: string;
  map_geometry_type: string;
  map_color: string;
  map_radius: number | null;
  map_dashed: boolean;
}

interface ColumnSpecRow {
  view_name: string;
  alias: string;
  display_name: string;
}

async function getNamespaceGroups(): Promise<NamespaceGroup[]> {
  const [rows, specRows] = await Promise.all([
    sql<ViewDefinitionRow[]>`
      SELECT
        n.namespace,
        n.display_name  AS display_name_ns,
        vd.view_name,
        vd.display_name AS display_name_view,
        vd.map_geometry_type,
        vd.map_color,
        vd.map_radius,
        vd.map_dashed
      FROM data_dictionary.namespace n
      JOIN data_dictionary.view_definition vd
        ON vd.namespace = n.namespace
      WHERE n.viewable = TRUE
        AND vd.show_on_map = TRUE
        AND vd.valid_to IS NULL
      ORDER BY n.namespace, vd.display_name
    `,
    sql<ColumnSpecRow[]>`
      SELECT view_name, alias, display_name
      FROM data_dictionary.view_column_spec
      WHERE valid_to IS NULL
      ORDER BY view_name, alias
    `,
  ]);

  const specsMap = new Map<string, ColumnSpec[]>();
  for (const row of specRows) {
    if (!specsMap.has(row.view_name)) specsMap.set(row.view_name, []);
    specsMap.get(row.view_name)!.push({ alias: row.alias, displayName: row.display_name });
  }

  const grouped = new Map<string, NamespaceGroup>();
  for (const row of rows) {
    if (!grouped.has(row.namespace)) {
      grouped.set(row.namespace, {
        namespace: row.namespace,
        displayName: row.display_name_ns,
        views: [],
      });
    }
    const view: ViewLayer = {
      viewName: row.view_name,
      displayName: row.display_name_view,
      geometryType: row.map_geometry_type as "line" | "circle",
      color: row.map_color,
      radius: row.map_radius ?? 8,
      dashed: row.map_dashed,
      columnSpecs: specsMap.get(row.view_name) ?? [],
    };
    grouped.get(row.namespace)!.views.push(view);
  }

  return Array.from(grouped.values());
}

async function getVisibleLayers(sub: string): Promise<string[]> {
  const rows = await sql<{ view_name: string }[]>`
    SELECT view_name
    FROM network_views.layer_visibility_state
    WHERE user_sub = ${sub}
  `;
  return rows.map((r) => r.view_name);
}

export default async function MapPage() {
  const session = await auth();
  const sub = session?.user?.sub ?? "";

  const [namespaces, initialVisibleLayers] = await Promise.all([
    getNamespaceGroups(),
    sub ? getVisibleLayers(sub) : Promise.resolve([]),
  ]);

  return (
    <div className="flex flex-col h-screen w-screen">
      <NavBar />
      <MapShell namespaces={namespaces} initialVisibleLayers={initialVisibleLayers} />
    </div>
  );
}
