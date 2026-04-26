"use client";

import { useState, useCallback } from "react";
import NetworkMap from "./network-map";
import LayerSidebar from "./layer-sidebar";
import AttributeInspector from "./attribute-inspector";
import type { NamespaceGroup, SelectedFeature } from "@/lib/map-types";

interface MapShellProps {
  namespaces: NamespaceGroup[];
  initialVisibleLayers: string[];
}

export default function MapShell({ namespaces, initialVisibleLayers }: MapShellProps) {
  const [selectedFeature, setSelectedFeature] =
    useState<SelectedFeature | null>(null);

  const handleLayerToggle = useCallback((layerId: string, visible: boolean) => {
    const container = document.querySelector("[data-map-container]") as
      | (HTMLDivElement & { __toggleLayer?: (id: string, v: boolean) => void })
      | null;
    container?.__toggleLayer?.(layerId, visible);
  }, []);

  const handleFeatureSelect = useCallback(
    (feature: SelectedFeature | null) => {
      setSelectedFeature((prev) => {
        if (feature && prev && feature.properties.id === prev.properties.id) {
          return null;
        }
        return feature;
      });
    },
    [],
  );

  return (
    <div className="flex flex-1 overflow-hidden relative">
      <LayerSidebar namespaces={namespaces} onLayerToggle={handleLayerToggle} initialVisibleLayers={initialVisibleLayers} />
      <NetworkMap namespaces={namespaces} onFeatureSelect={handleFeatureSelect} selectedFeature={selectedFeature} initialVisibleLayers={initialVisibleLayers} />
      <AttributeInspector
        feature={selectedFeature}
        onClose={() => setSelectedFeature(null)}
      />
    </div>
  );
}
