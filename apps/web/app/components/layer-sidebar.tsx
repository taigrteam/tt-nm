"use client";

import { useState } from "react";
import { Layers, ChevronLeft, ChevronRight, Eye, EyeOff } from "lucide-react";

interface LayerConfig {
  id: string;
  label: string;
  visible: boolean;
}

const INITIAL_LAYERS: LayerConfig[] = [
  { id: "overhead-lines", label: "Overhead Lines", visible: true },
  { id: "underground-cables", label: "Underground Cables", visible: true },
  { id: "network-points", label: "Substations & Switches", visible: true },
];

interface LayerSidebarProps {
  onLayerToggle: (layerId: string, visible: boolean) => void;
}

export default function LayerSidebar({ onLayerToggle }: LayerSidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [layers, setLayers] = useState(INITIAL_LAYERS);

  function toggle(layerId: string) {
    setLayers((prev) =>
      prev.map((l) => {
        if (l.id !== layerId) return l;
        const next = !l.visible;
        onLayerToggle(layerId, next);
        return { ...l, visible: next };
      }),
    );
  }

  return (
    <div
      className="flex flex-col transition-[width] duration-200 ease-in-out"
      style={{
        width: collapsed ? 40 : 220,
        backgroundColor: "var(--text)",
        borderRight: "1px solid rgba(240,246,247,0.15)",
        overflow: "hidden",
        flexShrink: 0,
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-3 py-2"
        style={{ borderBottom: "1px solid rgba(240,246,247,0.15)" }}
      >
        {!collapsed && (
          <span
            className="flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-[0.14em]"
            style={{ color: "rgba(240,246,247,0.65)" }}
          >
            <Layers size={14} />
            Layers
          </span>
        )}
        <button
          onClick={() => setCollapsed((c) => !c)}
          className="cursor-pointer p-0.5 transition-opacity hover:opacity-85"
          style={{
            color: "rgba(240,246,247,0.65)",
            background: "transparent",
            border: "none",
            marginLeft: collapsed ? "auto" : undefined,
            marginRight: collapsed ? "auto" : undefined,
          }}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
        </button>
      </div>

      {/* Layer toggles */}
      {!collapsed && (
        <div className="flex flex-col gap-0.5 p-2">
          {layers.map((layer) => (
            <button
              key={layer.id}
              onClick={() => toggle(layer.id)}
              className="flex items-center gap-2.5 px-2 py-1.5 text-left text-xs cursor-pointer transition-colors"
              style={{
                color: layer.visible
                  ? "var(--bg)"
                  : "rgba(240,246,247,0.4)",
                background: layer.visible
                  ? "rgba(236,109,38,0.12)"
                  : "transparent",
                border: "none",
              }}
            >
              {layer.visible ? (
                <Eye size={14} style={{ color: "var(--accent)" }} />
              ) : (
                <EyeOff size={14} />
              )}
              {layer.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
