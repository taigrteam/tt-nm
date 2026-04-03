"use client";

import { useEffect, useRef } from "react";
import { Map, type StyleSpecification } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";

/**
 * Base map style: OSM raster tiles.
 * The source ID "osm" and layer ID "osm-background" are stable —
 * future controls (visibility toggle, opacity slider) will target them by name.
 */
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

// Birmingham area — centred on the seed network data.
const INITIAL_CENTER: [number, number] = [-1.9001, 52.4801];
const INITIAL_ZOOM = 13;

export default function NetworkMap() {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Map | null>(null);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = new Map({
      container: containerRef.current,
      style: MAP_STYLE,
      center: INITIAL_CENTER,
      zoom: INITIAL_ZOOM,
    });

    map.on("load", () => {
      // Vector tile source from the authenticated tile proxy.
      // Uses the network_objects function source (RBAC-aware).
      // The browser sends the session cookie automatically (same origin).
      map.addSource("network", {
        type: "vector",
        tiles: [
          `${window.location.origin}/api/tiles/network_objects/{z}/{x}/{y}`,
        ],
        minzoom: 0,
        maxzoom: 22,
      });

      // Line layer — overhead lines (LineString geometry)
      map.addLayer({
        id: "network-lines",
        type: "line",
        source: "network",
        "source-layer": "network_objects",
        filter: ["==", ["geometry-type"], "LineString"],
        paint: {
          "line-color": "#EC6D26",
          "line-width": 3,
          "line-opacity": 0.9,
        },
      });

      // Point layer — substations, switches (Point geometry)
      map.addLayer({
        id: "network-points",
        type: "circle",
        source: "network",
        "source-layer": "network_objects",
        filter: ["==", ["geometry-type"], "Point"],
        paint: {
          "circle-radius": 7,
          "circle-color": "#0D8C80",
          "circle-stroke-color": "#05100E",
          "circle-stroke-width": 1.5,
        },
      });
    });

    mapRef.current = map;

    // Expose map on window for DevTools debugging (queryRenderedFeatures, etc.)
    (window as Record<string, unknown>).__map = map;

    return () => {
      map.remove();
      mapRef.current = null;
      delete (window as Record<string, unknown>).__map;
    };
  }, []);

  return (
    <div
      ref={containerRef}
      style={{ position: "absolute", inset: 0 }}
    />
  );
}
