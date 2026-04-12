// Shared types for the dynamic map layer configuration.
// Populated by the /map Server Component from data_dictionary tables.

export interface ViewLayer {
  viewName: string;        // SQL-safe name — used as tile source ID and layer ID
  displayName: string;     // UI label shown in the layer sidebar
  geometryType: "line" | "circle";
  color: string;           // Primary hex colour for map paint
  radius: number;          // Circle radius in pixels (circle layers only)
  dashed: boolean;         // Dash pattern applied to line layers
}

export interface NamespaceGroup {
  namespace: string;       // Namespace key (e.g. 'ELECTRICITY')
  displayName: string;     // UI label shown as folder heading
  views: ViewLayer[];
}
