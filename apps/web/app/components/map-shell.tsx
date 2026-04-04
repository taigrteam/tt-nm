"use client";

import { useState, useCallback, useRef } from "react";
import NetworkMap from "./network-map";
import LayerSidebar from "./layer-sidebar";
import AttributeInspector, { type FeatureProperties } from "./attribute-inspector";

export default function MapShell() {
  const [selectedFeature, setSelectedFeature] =
    useState<FeatureProperties | null>(null);
  const mapContainerRef = useRef<HTMLDivElement>(null);

  const handleLayerToggle = useCallback((layerId: string, visible: boolean) => {
    const container = document.querySelector("[data-map-container]") as
      | (HTMLDivElement & { __toggleLayer?: (id: string, v: boolean) => void })
      | null;
    container?.__toggleLayer?.(layerId, visible);
  }, []);

  const handleFeatureSelect = useCallback(
    (properties: FeatureProperties | null) => {
      setSelectedFeature(properties);
    },
    [],
  );

  return (
    <div
      ref={mapContainerRef}
      className="flex flex-1 overflow-hidden relative"
    >
      <LayerSidebar onLayerToggle={handleLayerToggle} />
      <NetworkMap onFeatureSelect={handleFeatureSelect} />
      <AttributeInspector
        feature={selectedFeature}
        onClose={() => setSelectedFeature(null)}
      />
    </div>
  );
}
