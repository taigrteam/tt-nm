"use client";

import { useEffect, useRef, useCallback } from "react";
import { Map, Popup, type StyleSpecification, type MapMouseEvent, type MapGeoJSONFeature } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { FeatureProperties } from "./attribute-inspector";

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
const INTERACTIVE_LAYERS = [
  "primary-substations",
  "secondary-substations",
  "overhead-lines",
  "underground-cables",
];

interface NetworkMapProps {
  onFeatureSelect: (properties: FeatureProperties | null) => void;
}

export default function NetworkMap({ onFeatureSelect }: NetworkMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Map | null>(null);

  // Expose toggleLayer for the sidebar
  const toggleLayer = useCallback((layerId: string, visible: boolean) => {
    const map = mapRef.current;
    if (!map) return;
    map.setLayoutProperty(layerId, "visibility", visible ? "visible" : "none");
  }, []);

  // Store toggleLayer on the container so the parent can call it
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

    // Disable keyboard rotation (Shift+arrow keys).
    map.keyboard.disableRotation();

    map.on("load", () => {
      map.addSource("network", {
        type: "vector",
        tiles: [
          `${window.location.origin}/api/tiles/network_objects/{z}/{x}/{y}`,
        ],
        minzoom: 0,
        maxzoom: 22,
      });

      // --- Line layers (split for dash support) ---

      map.addLayer({
        id: "overhead-lines",
        type: "line",
        source: "network",
        "source-layer": "network_objects",
        filter: [
          "all",
          ["==", ["geometry-type"], "LineString"],
          ["==", ["get", "class_name"], "OverheadLine"],
        ],
        paint: {
          "line-color": "#EC6D26",
          "line-width": 3,
          "line-opacity": 0.9,
          "line-dasharray": [4, 3],
        },
      });

      map.addLayer({
        id: "underground-cables",
        type: "line",
        source: "network",
        "source-layer": "network_objects",
        filter: [
          "all",
          ["==", ["geometry-type"], "LineString"],
          ["==", ["get", "class_name"], "UndergroundCable"],
        ],
        paint: {
          "line-color": "#7B4DB5",
          "line-width": 3,
          "line-opacity": 0.9,
        },
      });

      // --- Point layers (primary + secondary substations) ---

      map.addLayer({
        id: "primary-substations",
        type: "circle",
        source: "network",
        "source-layer": "network_objects",
        filter: [
          "all",
          ["==", ["geometry-type"], "Point"],
          ["==", ["get", "class_name"], "PrimarySubstation"],
        ],
        paint: {
          "circle-radius": 10,
          "circle-color": "#EC6D26",
          "circle-stroke-color": "#05100E",
          "circle-stroke-width": 1.5,
        },
      });

      map.addLayer({
        id: "secondary-substations",
        type: "circle",
        source: "network",
        "source-layer": "network_objects",
        filter: [
          "all",
          ["==", ["geometry-type"], "Point"],
          ["==", ["get", "class_name"], "SecondarySubstation"],
        ],
        paint: {
          "circle-radius": 8,
          "circle-color": "#0D8C80",
          "circle-stroke-color": "#05100E",
          "circle-stroke-width": 1.5,
        },
      });

      // Feature click → inspector
      map.on("click", (e: MapMouseEvent) => {
        const features = map.queryRenderedFeatures(e.point, {
          layers: INTERACTIVE_LAYERS,
        });
        if (features.length > 0) {
          onFeatureSelect(features[0].properties as FeatureProperties);
        } else {
          onFeatureSelect(null);
        }
      });

      // Hover tooltip showing identity + class name
      const hoverPopup = new Popup({
        closeButton: false,
        closeOnClick: false,
        offset: 12,
        className: "tt-hover-popup",
      });

      for (const layerId of INTERACTIVE_LAYERS) {
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
          if (hoverPopup.isOpen()) {
            hoverPopup.setLngLat(e.lngLat);
          }
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
  }, [onFeatureSelect]);

  return (
    <div
      ref={containerRef}
      data-map-container
      className="flex-1 relative"
    />
  );
}
