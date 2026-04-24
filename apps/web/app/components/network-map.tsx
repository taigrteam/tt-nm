"use client";

import { useEffect, useRef, useCallback } from "react";
import { Map, Popup, type StyleSpecification, type MapMouseEvent, type MapGeoJSONFeature, type FilterSpecification } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { NamespaceGroup, SelectedFeature, ViewLayer } from "@/lib/map-types";

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const MAP_STYLE: StyleSpecification = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    },
  },
  layers: [
    {
      id: "osm-background",
      type: "raster",
      source: "osm",
    },
  ],
};

const INITIAL_CENTER: [number, number] = [-3.5, 54.6];
const INITIAL_ZOOM = 7;

interface NetworkMapProps {
  namespaces: NamespaceGroup[];
  onFeatureSelect: (feature: SelectedFeature | null) => void;
  selectedFeature: SelectedFeature | null;
}

export default function NetworkMap({ namespaces, onFeatureSelect, selectedFeature }: NetworkMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Map | null>(null);
  const prevHighlightRef = useRef<{ viewName: string } | null>(null);

  // Flatten all view layers for interaction setup
  const allViews = namespaces.flatMap((ns) => ns.views);
  const interactiveLayerIds = allViews.map((v) => v.viewName);

  const toggleLayer = useCallback((layerId: string, visible: boolean) => {
    const map = mapRef.current;
    if (!map) return;
    const v = visible ? "visible" : "none";
    map.setLayoutProperty(layerId, "visibility", v);
    for (const suffix of ["--outline", "--highlight", "--highlight-outline"]) {
      if (map.getLayer(`${layerId}${suffix}`)) {
        map.setLayoutProperty(`${layerId}${suffix}`, "visibility", v);
      }
    }
  }, []);

  useEffect(() => {
    const el = containerRef.current;
    if (el) {
      (el as HTMLDivElement & { __toggleLayer?: typeof toggleLayer }).__toggleLayer = toggleLayer;
    }
  }, [toggleLayer]);

  // Sync selected feature highlight with the map.
  // Runs whenever selectedFeature changes, including when the inspector is closed (null).
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const emptyFilter: FilterSpecification = ["==", ["get", "id"], ""];

    // Clear previous highlight
    if (prevHighlightRef.current) {
      const prev = prevHighlightRef.current.viewName;
      if (map.getLayer(`${prev}--highlight`)) map.setFilter(`${prev}--highlight`, emptyFilter);
      if (map.getLayer(`${prev}--highlight-outline`)) map.setFilter(`${prev}--highlight-outline`, emptyFilter);
      prevHighlightRef.current = null;
    }

    if (selectedFeature) {
      const { viewName } = selectedFeature;
      const featureId = String(selectedFeature.properties.id ?? "");
      const activeFilter: FilterSpecification = ["==", ["get", "id"], featureId];
      if (map.getLayer(`${viewName}--highlight`)) map.setFilter(`${viewName}--highlight`, activeFilter);
      if (map.getLayer(`${viewName}--highlight-outline`)) map.setFilter(`${viewName}--highlight-outline`, activeFilter);
      prevHighlightRef.current = { viewName };
    }
  }, [selectedFeature]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = new Map({
      container: containerRef.current,
      style: MAP_STYLE,
      center: INITIAL_CENTER,
      zoom: INITIAL_ZOOM,
      maxPitch: 0,
      dragRotate: false,
      touchZoomRotate: true,
      pitchWithRotate: false,
    });

    map.keyboard.disableRotation();

    map.on("load", () => {
      // Add sources for all views first
      for (const ns of namespaces) {
        for (const view of ns.views) {
          addViewSource(map, view);
        }
      }

      // Render order: fill → fill outlines → line → circle
      for (const ns of namespaces) {
        for (const view of ns.views) {
          if (view.geometryType === "fill") addViewLayer(map, view);
        }
      }
      for (const ns of namespaces) {
        for (const view of ns.views) {
          if (view.geometryType === "fill") addFillOutlineLayer(map, view);
        }
      }
      for (const ns of namespaces) {
        for (const view of ns.views) {
          if (view.geometryType === "line") addViewLayer(map, view);
        }
      }
      for (const ns of namespaces) {
        for (const view of ns.views) {
          if (view.geometryType === "circle") addViewLayer(map, view);
        }
      }

      // Highlight layers — added last so they render above everything
      for (const view of allViews) {
        addHighlightLayer(map, view);
      }

      // Feature click → inspector
      map.on("click", (e: MapMouseEvent) => {
        const features = map.queryRenderedFeatures(e.point, {
          layers: interactiveLayerIds,
        });
        if (features.length > 0) {
          const feature = features[0];
          const viewName = feature.layer.id;
          const view = allViews.find((v) => v.viewName === viewName);
          onFeatureSelect({
            viewName,
            properties: feature.properties as SelectedFeature["properties"],
            columnSpecs: view?.columnSpecs ?? [],
          });
        } else {
          onFeatureSelect(null);
        }
      });

      // Hover tooltip per layer
      const hoverPopup = new Popup({
        closeButton: false,
        closeOnClick: false,
        offset: 12,
        className: "tt-hover-popup",
      });

      for (const layerId of interactiveLayerIds) {
        let lastFeatureId: unknown = undefined;

        map.on("mouseenter", layerId, () => {
          map.getCanvas().style.cursor = "pointer";
        });

        map.on("mousemove", layerId, (e: MapMouseEvent & { features?: MapGeoJSONFeature[] }) => {
          const f = e.features?.[0];
          if (!f) return;

          // Only rebuild the popup HTML when the feature under the cursor changes.
          const featureId = (f.properties as Record<string, unknown>)?.id ?? f.id;
          if (featureId !== lastFeatureId) {
            lastFeatureId = featureId;
            const props = f.properties as Record<string, unknown>;
            const title = [props.identity, props.class_name]
              .filter(Boolean)
              .map((v) => escapeHtml(String(v)))
              .join(" — ");
            if (!title) { hoverPopup.remove(); return; }
            const html = `<div style="font-family:Roboto,sans-serif;">
              <div style="font-size:0.75rem;font-weight:700;color:var(--text);">${title}</div>
            </div>`;
            hoverPopup.setHTML(html);
            if (!hoverPopup.isOpen()) hoverPopup.addTo(map);
          }

          hoverPopup.setLngLat(e.lngLat);
        });

        map.on("mouseleave", layerId, () => {
          map.getCanvas().style.cursor = "";
          lastFeatureId = undefined;
          hoverPopup.remove();
        });
      }
    });

    mapRef.current = map;
    if (process.env.NODE_ENV === "development") {
      (window as unknown as Record<string, unknown>).__map = map;
    }

    return () => {
      map.remove();
      mapRef.current = null;
      if (process.env.NODE_ENV === "development") {
        delete (window as unknown as Record<string, unknown>).__map;
      }
    };
    // namespaces is stable (from server); onFeatureSelect is useCallback-stable
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onFeatureSelect]);

  return (
    <div
      ref={containerRef}
      data-map-container
      className="flex-1 relative"
    />
  );
}

const EMPTY_FILTER: FilterSpecification = ["==", ["get", "id"], ""];
const HIGHLIGHT_COLOR = "#FF0000";

function addHighlightLayer(map: Map, view: ViewLayer): void {
  if (view.geometryType === "fill") {
    map.addLayer({
      id: `${view.viewName}--highlight`,
      type: "fill",
      source: view.viewName,
      "source-layer": view.viewName,
      filter: EMPTY_FILTER,
      paint: {
        "fill-color": HIGHLIGHT_COLOR,
        "fill-opacity": 0.45,
      },
    });
    map.addLayer({
      id: `${view.viewName}--highlight-outline`,
      type: "line",
      source: view.viewName,
      "source-layer": view.viewName,
      filter: EMPTY_FILTER,
      paint: {
        "line-color": HIGHLIGHT_COLOR,
        "line-width": 3,
        "line-opacity": 1,
      },
    });
  } else if (view.geometryType === "line") {
    map.addLayer({
      id: `${view.viewName}--highlight`,
      type: "line",
      source: view.viewName,
      "source-layer": view.viewName,
      filter: EMPTY_FILTER,
      paint: {
        "line-color": HIGHLIGHT_COLOR,
        "line-width": 7,
        "line-opacity": 1,
      },
    });
  } else {
    map.addLayer({
      id: `${view.viewName}--highlight`,
      type: "circle",
      source: view.viewName,
      "source-layer": view.viewName,
      filter: EMPTY_FILTER,
      paint: {
        "circle-radius": view.radius,
        "circle-color": view.color,
        "circle-stroke-color": HIGHLIGHT_COLOR,
        "circle-stroke-width": 3,
      },
    });
  }
}

function addFillOutlineLayer(map: Map, view: ViewLayer): void {
  map.addLayer({
    id: `${view.viewName}--outline`,
    type: "line",
    source: view.viewName,
    "source-layer": view.viewName,
    paint: {
      "line-color": view.color,
      "line-width": 1.5,
      "line-opacity": 0.8,
    },
  });
}

function addViewSource(map: Map, view: ViewLayer): void {
  map.addSource(view.viewName, {
    type: "vector",
    tiles: [
      `${window.location.origin}/api/tiles/${view.viewName}/{z}/{x}/{y}`,
    ],
    minzoom: 0,
    maxzoom: 22,
  });
}

function addViewLayer(map: Map, view: ViewLayer): void {
  if (view.geometryType === "fill") {
    map.addLayer({
      id: view.viewName,
      type: "fill",
      source: view.viewName,
      "source-layer": view.viewName,
      paint: {
        "fill-color": view.color,
        "fill-opacity": 0.25,
      },
    });
  } else if (view.geometryType === "line") {
    map.addLayer({
      id: view.viewName,
      type: "line",
      source: view.viewName,
      "source-layer": view.viewName,
      paint: {
        "line-color": view.color,
        "line-width": 3,
        "line-opacity": 0.9,
        ...(view.dashed ? { "line-dasharray": [4, 3] } : {}),
      },
    });
  } else {
    map.addLayer({
      id: view.viewName,
      type: "circle",
      source: view.viewName,
      "source-layer": view.viewName,
      paint: {
        "circle-radius": view.radius,
        "circle-color": view.color,
        "circle-stroke-color": "#05100E",
        "circle-stroke-width": 1.5,
      },
    });
  }
}
