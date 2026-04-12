"use client";

import { useState } from "react";
import { Layers, ChevronLeft, ChevronRight, ChevronDown, ChevronRight as FolderChevron, Eye, EyeOff } from "lucide-react";
import type { NamespaceGroup } from "@/lib/map-types";

interface LayerSidebarProps {
  namespaces: NamespaceGroup[];
  onLayerToggle: (layerId: string, visible: boolean) => void;
}

export default function LayerSidebar({ namespaces, onLayerToggle }: LayerSidebarProps) {
  const [collapsed, setCollapsed] = useState(false);

  // Visibility state: viewName → boolean (all visible by default)
  const [visibility, setVisibility] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {};
    for (const ns of namespaces) {
      for (const view of ns.views) {
        init[view.viewName] = true;
      }
    }
    return init;
  });

  // Collapsed namespace folders: namespace key → boolean (all expanded by default)
  const [folderCollapsed, setFolderCollapsed] = useState<Record<string, boolean>>({});

  // Per-namespace snapshot of individual layer visibility captured just before
  // the namespace was toggled off — restored when the namespace is toggled back on.
  const [nsSnapshot, setNsSnapshot] = useState<Record<string, Record<string, boolean>>>({});

  function toggleLayer(viewName: string) {
    const next = !visibility[viewName];
    setVisibility((prev) => ({ ...prev, [viewName]: next }));
    onLayerToggle(viewName, next);
  }

  function toggleNamespace(ns: NamespaceGroup) {
    const anyOn = ns.views.some((v) => visibility[v.viewName] !== false);

    if (anyOn) {
      // Save current per-layer state, then hide everything.
      const snap: Record<string, boolean> = {};
      for (const v of ns.views) snap[v.viewName] = visibility[v.viewName] !== false;
      setNsSnapshot((prev) => ({ ...prev, [ns.namespace]: snap }));

      const updates: Record<string, boolean> = {};
      for (const v of ns.views) {
        updates[v.viewName] = false;
        onLayerToggle(v.viewName, false);
      }
      setVisibility((prev) => ({ ...prev, ...updates }));
    } else {
      // Restore from snapshot; fall back to all-on if no snapshot exists.
      const snap = nsSnapshot[ns.namespace];
      const updates: Record<string, boolean> = {};
      for (const v of ns.views) {
        const restore = snap ? (snap[v.viewName] !== false) : true;
        updates[v.viewName] = restore;
        onLayerToggle(v.viewName, restore);
      }
      setVisibility((prev) => ({ ...prev, ...updates }));
    }
  }

  function toggleFolder(namespace: string) {
    setFolderCollapsed((prev) => ({ ...prev, [namespace]: !prev[namespace] }));
  }

  return (
    <div
      className="absolute left-0 top-0 bottom-0 z-10 flex flex-col transition-[width] duration-200 ease-in-out"
      style={{
        width: collapsed ? 40 : 220,
        backgroundColor: "var(--card-bg)",
        borderRight: "1px solid var(--border-col)",
        boxShadow: "4px 0 0 var(--shadow-col)",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-3 py-2 flex-shrink-0"
        style={{ borderBottom: "1px solid var(--border-col)" }}
      >
        {!collapsed && (
          <span
            className="flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-[0.14em]"
            style={{ color: "var(--text-muted)" }}
          >
            <Layers size={14} />
            Layers
          </span>
        )}
        <button
          onClick={() => setCollapsed((c) => !c)}
          className="cursor-pointer p-0.5 transition-opacity hover:opacity-85"
          style={{
            color: "var(--text-muted)",
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

      {/* Namespace folders */}
      {!collapsed && (
        <div className="flex flex-col overflow-y-auto flex-1">
          {namespaces.map((ns) => {
            const isFolderOpen = !folderCollapsed[ns.namespace];
            const nsAnyOn = ns.views.some((v) => visibility[v.viewName] !== false);
            return (
              <div key={ns.namespace}>
                {/* Folder header */}
                <div
                  className="flex items-center"
                  style={{ borderBottom: "1px solid var(--border-col)" }}
                >
                  {/* Expand/collapse */}
                  <button
                    onClick={() => toggleFolder(ns.namespace)}
                    className="flex-1 flex items-center gap-2 px-3 py-1.5 cursor-pointer"
                    style={{
                      fontFamily: "'Roboto', sans-serif",
                      fontSize: "0.65rem",
                      fontWeight: 700,
                      textTransform: "uppercase",
                      letterSpacing: "0.12em",
                      color: "var(--text)",
                      background: "transparent",
                      border: "none",
                    }}
                  >
                    {isFolderOpen ? (
                      <ChevronDown size={12} style={{ flexShrink: 0 }} />
                    ) : (
                      <FolderChevron size={12} style={{ flexShrink: 0 }} />
                    )}
                    <span className="truncate">{ns.displayName}</span>
                  </button>

                  {/* Namespace visibility toggle */}
                  <button
                    onClick={() => toggleNamespace(ns)}
                    className="px-2 py-1.5 cursor-pointer transition-opacity hover:opacity-70"
                    style={{ background: "transparent", border: "none", flexShrink: 0 }}
                    aria-label={nsAnyOn ? `Hide all ${ns.displayName} layers` : `Show all ${ns.displayName} layers`}
                  >
                    {nsAnyOn ? (
                      <Eye size={13} style={{ color: "var(--accent)" }} />
                    ) : (
                      <EyeOff size={13} style={{ color: "var(--text-muted)" }} />
                    )}
                  </button>
                </div>

                {/* View layer rows */}
                {isFolderOpen && (
                  <div className="flex flex-col gap-0.5 px-2 py-1">
                    {ns.views.map((view) => {
                      const isVisible = visibility[view.viewName] ?? true;
                      return (
                        <button
                          key={view.viewName}
                          onClick={() => toggleLayer(view.viewName)}
                          className="flex items-center gap-2.5 px-2 py-1.5 text-left cursor-pointer transition-colors"
                          style={{
                            fontFamily: "'Roboto', sans-serif",
                            fontSize: "0.68rem",
                            fontWeight: 700,
                            textTransform: "uppercase",
                            letterSpacing: "0.1em",
                            color: isVisible ? "var(--text)" : "var(--text-muted)",
                            background: isVisible ? "var(--row-hover)" : "transparent",
                            border: "none",
                          }}
                        >
                          {isVisible ? (
                            <Eye size={14} style={{ color: "var(--accent)", flexShrink: 0 }} />
                          ) : (
                            <EyeOff size={14} style={{ color: "var(--text-muted)", flexShrink: 0 }} />
                          )}
                          <span className="truncate">{view.displayName}</span>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
