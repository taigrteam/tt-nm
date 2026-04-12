"use client";

import { useEffect, useRef, useCallback } from "react";
import { Map, Popup, type StyleSpecification, type MapMouseEvent, type MapGeoJSONFeature } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { FeatureProperties } from "./attribute-inspector";
import type { NamespaceGroup, ViewLayer } from "@/lib/map-types";

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

const INITIAL_CENTER: [number, number] = [-1.9001, 52.4801];
const INITIAL_ZOOM = 13;

interface NetworkMapProps {
  namespaces: NamespaceGroup[];
  onFeatureSelect: (properties: FeatureProperties | null) => void;
}

export default function NetworkMap({ namespaces, onFeatureSelect }: NetworkMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Map | null>(null);

  // Flatten all view layers for interaction setup
  const allViews = namespaces.flatMap((ns) => ns.views);
  const interactiveLayerIds = allViews.map((v) => v.viewName);

  const toggleLayer = useCallback((layerId: string, visible: boolean) => {
    const map = mapRef.current;
    if (!map) return;
    map.setLayoutProperty(layerId, "visibility", visible ? "visible" : "none");
  }, []);

  useEffect(() => {
    const el = containerRef.current;
    if (el) {
      (el as HTMLDivElement & { __toggleLayer?: typeof toggleLayer }).__toggleLayer = toggleLayer;
    }
  }, [toggleLayer]);

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

      // Add line layers before circle layers so substations render on top
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

      // Feature click → inspector
      map.on("click", (e: MapMouseEvent) => {
        const features = map.queryRenderedFeatures(e.point, {
          layers: interactiveLayerIds,
        });
        if (features.length > 0) {
          onFeatureSelect(features[0].properties as FeatureProperties);
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
        map.on("mouseenter", layerId, (e: MapMouseEvent & { features?: MapGeoJSONFeature[] }) => {
          map.getCanvas().style.cursor = "pointer";
          const f = e.features?.[0];
          if (!f) return;
          const props = f.properties as Record<string, unknown>;
          const title = [props.identity, props.class_name]
            .filter(Boolean)
            .map((v) => escapeHtml(String(v)))
            .join(" — ");
          if (!title) return;

          const details: string[] = [];
          if (props.voltage_kv) details.push(`${escapeHtml(String(props.voltage_kv))} kV`);
          if (props.status) details.push(escapeHtml(String(props.status)));
          if (props.rating_mva) details.push(`${escapeHtml(String(props.rating_mva))} MVA`);
          if (props.length_m) details.push(`${escapeHtml(String(props.length_m))} m`);

          const html = `<div style="font-family:Roboto,sans-serif;">
            <div style="font-size:0.75rem;font-weight:700;color:var(--text);">${title}</div>
            ${details.length ? `<div style="font-size:0.65rem;color:var(--text-muted);margin-top:2px;">${details.join(" · ")}</div>` : ""}
          </div>`;

          hoverPopup.setLngLat(e.lngLat).setHTML(html).addTo(map);
        });

        map.on("mousemove", layerId, (e: MapMouseEvent) => {
          if (hoverPopup.isOpen()) hoverPopup.setLngLat(e.lngLat);
        });

        map.on("mouseleave", layerId, () => {
          map.getCanvas().style.cursor = "";
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
  if (view.geometryType === "line") {
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
