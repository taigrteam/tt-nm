// Shared types for the dynamic map layer configuration.
// Populated by the /map Server Component from data_dictionary tables.

export interface ColumnSpec {
  alias: string;        // JSONB key (from view_column_spec.alias)
  displayName: string;  // Human label (from view_column_spec.display_name)
}

export interface ViewLayer {
  viewName: string;        // SQL-safe name — used as tile source ID and layer ID
  displayName: string;     // UI label shown in the layer sidebar
  geometryType: "line" | "circle";
  color: string;           // Primary hex colour for map paint
  radius: number;          // Circle radius in pixels (circle layers only)
  dashed: boolean;         // Dash pattern applied to line layers
  columnSpecs: ColumnSpec[]; // Display-name mapping for attributes JSONB keys
}

export interface NamespaceGroup {
  namespace: string;       // Namespace key (e.g. 'ELECTRICITY')
  displayName: string;     // UI label shown as folder heading
  views: ViewLayer[];
}

// Passed from the map click handler to the attribute inspector.
export interface SelectedFeature {
  properties: Record<string, string | number | boolean | null | undefined>;
  columnSpecs: ColumnSpec[];
}
