"use client";

import { useState, useTransition, useRef } from "react";
import { Layers, ChevronLeft, ChevronRight, ChevronDown, ChevronRight as FolderChevron, Eye, EyeOff } from "lucide-react";
import type { NamespaceGroup } from "@/lib/map-types";
import { saveLayerVisibility } from "@/app/actions/layer-state";

interface LayerSidebarProps {
  namespaces: NamespaceGroup[];
  onLayerToggle: (layerId: string, visible: boolean) => void;
  initialVisibleLayers: string[];
}

export default function LayerSidebar({ namespaces, onLayerToggle, initialVisibleLayers }: LayerSidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [, startTransition] = useTransition();

  // Visibility state: seeded from persisted state; missing entries default to false (off).
  const [visibility, setVisibility] = useState<Record<string, boolean>>(() => {
    const visible = new Set(initialVisibleLayers);
    const init: Record<string, boolean> = {};
    for (const ns of namespaces) {
      for (const view of ns.views) {
        init[view.viewName] = visible.has(view.viewName);
      }
    }
    return init;
  });

  // Collapsed namespace folders: namespace key → boolean (all collapsed by default)
  const [folderCollapsed, setFolderCollapsed] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {};
    for (const ns of namespaces) {
      init[ns.namespace] = true;
    }
    return init;
  });

  // Per-namespace snapshot of individual layer visibility captured just before
  // the namespace was toggled off — restored when the namespace is toggled back on.
  const [nsSnapshot, setNsSnapshot] = useState<Record<string, Record<string, boolean>>>({});

  // Explicit namespace on/off state — drives the eye icon independently of sublayer visibility.
  // A namespace can be "on" (enabled) even when all its sublayers are off.
  const [nsEnabled, setNsEnabled] = useState<Record<string, boolean>>(() => {
    const visibleSet = new Set(initialVisibleLayers);
    const init: Record<string, boolean> = {};
    for (const ns of namespaces) {
      init[ns.namespace] = ns.views.some((v) => visibleSet.has(v.viewName));
    }
    return init;
  });

  function toggleLayer(viewName: string) {
    const next = !visibility[viewName];
    setVisibility((prev) => ({ ...prev, [viewName]: next }));
    onLayerToggle(viewName, next);
    if (next) {
      const ns = namespaces.find((n) => n.views.some((v) => v.viewName === viewName));
      if (ns) setNsEnabled((prev) => ({ ...prev, [ns.namespace]: true }));
    }
    startTransition(() => { saveLayerVisibility([{ viewName, visible: next }]); });
  }

  function toggleNamespace(ns: NamespaceGroup) {
    if (nsEnabled[ns.namespace]) {
      // Turning off: save current sublayer state, hide all layers.
      const snap: Record<string, boolean> = {};
      for (const v of ns.views) snap[v.viewName] = visibility[v.viewName] !== false;
      setNsSnapshot((prev) => ({ ...prev, [ns.namespace]: snap }));

      const updates: Record<string, boolean> = {};
      for (const v of ns.views) {
        updates[v.viewName] = false;
        onLayerToggle(v.viewName, false);
      }
      setVisibility((prev) => ({ ...prev, ...updates }));
      setNsEnabled((prev) => ({ ...prev, [ns.namespace]: false }));
      startTransition(() => {
        saveLayerVisibility(ns.views.map((v) => ({ viewName: v.viewName, visible: false })));
      });
    } else {
      // Turning on: restore sublayer state from snapshot (may be all-off); fall back to all-off.
      const snap = nsSnapshot[ns.namespace];
      const updates: Record<string, boolean> = {};
      for (const v of ns.views) {
        const restore = snap ? (snap[v.viewName] !== false) : false;
        updates[v.viewName] = restore;
        onLayerToggle(v.viewName, restore);
      }
      setVisibility((prev) => ({ ...prev, ...updates }));
      setNsEnabled((prev) => ({ ...prev, [ns.namespace]: true }));
      startTransition(() => {
        saveLayerVisibility(ns.views.map((v) => ({ viewName: v.viewName, visible: updates[v.viewName] })));
      });
    }
  }

  function toggleFolder(namespace: string) {
    setFolderCollapsed((prev) => ({ ...prev, [namespace]: !prev[namespace] }));
  }

  // Double-click: always turn the namespace and all sublayers off, save state.
  // Also writes an all-false snapshot so single-click re-enable restores with all layers off.
  function forceNamespaceOff(ns: NamespaceGroup) {
    const snap: Record<string, boolean> = {};
    for (const v of ns.views) snap[v.viewName] = false;
    setNsSnapshot((prev) => ({ ...prev, [ns.namespace]: snap }));

    const updates: Record<string, boolean> = {};
    for (const v of ns.views) {
      updates[v.viewName] = false;
      onLayerToggle(v.viewName, false);
    }
    setVisibility((prev) => ({ ...prev, ...updates }));
    setNsEnabled((prev) => ({ ...prev, [ns.namespace]: false }));
    startTransition(() => {
      saveLayerVisibility(ns.views.map((v) => ({ viewName: v.viewName, visible: false })));
    });
  }

  // Disambiguate single-click (toggleNamespace) from double-click (forceNamespaceAll).
  // Browsers fire two click events before dblclick, so we delay the single-click action.
  const nsClickTimers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  function handleNsEyeClick(ns: NamespaceGroup) {
    if (nsClickTimers.current[ns.namespace]) return; // second click of a dblclick — ignore
    nsClickTimers.current[ns.namespace] = setTimeout(() => {
      delete nsClickTimers.current[ns.namespace];
      toggleNamespace(ns);
    }, 250);
  }

  function handleNsEyeDblClick(ns: NamespaceGroup) {
    if (nsClickTimers.current[ns.namespace]) {
      clearTimeout(nsClickTimers.current[ns.namespace]);
      delete nsClickTimers.current[ns.namespace];
    }
    forceNamespaceOff(ns);
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
            const nsOn = nsEnabled[ns.namespace] ?? false;
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

                  {/* Namespace visibility toggle: single-click preserves sub-layer state, double-click forces all on/off */}
                  <button
                    onClick={() => handleNsEyeClick(ns)}
                    onDoubleClick={() => handleNsEyeDblClick(ns)}
                    className="px-2 py-1.5 cursor-pointer transition-opacity hover:opacity-70"
                    style={{ background: "transparent", border: "none", flexShrink: 0 }}
                    aria-label={nsOn ? `Hide all ${ns.displayName} layers` : `Show all ${ns.displayName} layers`}
                  >
                    {nsOn ? (
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
                      const isVisible = visibility[view.viewName] ?? false;
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
