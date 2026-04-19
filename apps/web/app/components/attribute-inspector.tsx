"use client";

import { X, Info } from "lucide-react";
import type { SelectedFeature } from "@/lib/map-types";

interface AttributeInspectorProps {
  feature: SelectedFeature | null;
  onClose: () => void;
}

export default function AttributeInspector({
  feature,
  onClose,
}: AttributeInspectorProps) {
  if (!feature) return null;

  const { properties, columnSpecs } = feature;

  // Parse the attributes JSON string that PostGIS serialises into the MVT.
  const rawAttrs: Record<string, unknown> =
    typeof properties.attributes === "string"
      ? (JSON.parse(properties.attributes) as Record<string, unknown>)
      : {};

  const labelFor = new Map(columnSpecs.map((s) => [s.alias, s.displayName]));

  const entries = Object.entries(rawAttrs).filter(
    ([, v]) => v !== null && v !== undefined && v !== "",
  );

  return (
    <div
      className="flex flex-col"
      style={{
        width: 280,
        position: "absolute",
        top: 0,
        right: 0,
        bottom: 0,
        zIndex: 10,
        backgroundColor: "var(--card-bg)",
        borderLeft: "1px solid var(--border-col)",
        boxShadow: "-4px 0 0 var(--shadow-col)",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-3 py-2"
        style={{ borderBottom: "1px solid var(--border-col)" }}
      >
        <span
          className="flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-[0.14em]"
          style={{ color: "var(--text-muted)" }}
        >
          <Info size={14} />
          Attributes
        </span>
        <button
          onClick={onClose}
          className="cursor-pointer p-0.5 transition-opacity hover:opacity-85"
          style={{
            color: "var(--text-muted)",
            background: "transparent",
            border: "none",
          }}
          aria-label="Close inspector"
        >
          <X size={16} />
        </button>
      </div>

      {/* Feature identity */}
      <div
        className="px-3 py-2"
        style={{ borderBottom: "1px solid var(--border-col)" }}
      >
        <div
          className="text-sm font-black tracking-wide"
          style={{
            fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
            color: "var(--text)",
          }}
        >
          {properties.identity ?? "Unknown"}
        </div>
        {properties.class_name && (
          <span
            className="mt-1 inline-block px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-widest"
            style={{
              border: "2px solid var(--accent2)",
              color: "var(--accent2)",
            }}
          >
            {properties.class_name}
          </span>
        )}
      </div>

      {/* Properties table */}
      <div className="flex-1 overflow-y-auto">
        <table className="w-full">
          <tbody>
            {entries.map(([key, value]) => {
              const registeredLabel = labelFor.get(key);
              return (
                <tr
                  key={key}
                  className="transition-colors"
                  style={{ borderBottom: "1px solid var(--border-col)" }}
                  onMouseEnter={(e) =>
                    (e.currentTarget.style.background = "var(--row-hover)")
                  }
                  onMouseLeave={(e) =>
                    (e.currentTarget.style.background = "transparent")
                  }
                >
                  <td
                    className="px-3 py-1.5 text-[0.68rem] font-bold tracking-[0.1em]"
                    style={{
                      color: "var(--text-muted)",
                      textTransform: registeredLabel ? "uppercase" : "none",
                    }}
                  >
                    {registeredLabel ?? key}
                  </td>
                  <td
                    className="px-3 py-1.5 text-right text-xs"
                    style={{
                      fontFamily: "'Courier New', monospace",
                      color: "var(--text)",
                      fontWeight: 500,
                    }}
                  >
                    {String(value)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
