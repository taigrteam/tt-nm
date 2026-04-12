"use client";

import { useState, useCallback } from "react";
import NetworkMap from "./network-map";
import LayerSidebar from "./layer-sidebar";
import AttributeInspector, { type FeatureProperties } from "./attribute-inspector";
import type { NamespaceGroup } from "@/lib/map-types";

interface MapShellProps {
  namespaces: NamespaceGroup[];
}

export default function MapShell({ namespaces }: MapShellProps) {
  const [selectedFeature, setSelectedFeature] =
    useState<FeatureProperties | null>(null);

  const handleLayerToggle = useCallback((layerId: string, visible: boolean) => {
    const container = document.querySelector("[data-map-container]") as
      | (HTMLDivElement & { __toggleLayer?: (id: string, v: boolean) => void })
      | null;
    container?.__toggleLayer?.(layerId, visible);
  }, []);

  const handleFeatureSelect = useCallback(
    (properties: FeatureProperties | null) => {
      setSelectedFeature((prev) => {
        if (properties && prev && properties.id === prev.id) {
          return null;
        }
        return properties;
      });
    },
    [],
  );

  return (
    <div className="flex flex-1 overflow-hidden relative">
      <LayerSidebar namespaces={namespaces} onLayerToggle={handleLayerToggle} />
      <NetworkMap namespaces={namespaces} onFeatureSelect={handleFeatureSelect} />
      <AttributeInspector
        feature={selectedFeature}
        onClose={() => setSelectedFeature(null)}
      />
    </div>
  );
}
