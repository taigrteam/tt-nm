"use client";

import { useEffect, useRef, useState } from "react";
import { X, Info } from "lucide-react";
import type { SelectedFeature } from "@/lib/map-types";

interface AttributeInspectorProps {
  feature: SelectedFeature | null;
  onClose: () => void;
}

interface Toast {
  x: number;
  y: number;
  visible: boolean;
}

export default function AttributeInspector({
  feature,
  onClose,
}: AttributeInspectorProps) {
  const [width, setWidth] = useState(280);
  const isDragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const [toast, setToast] = useState<Toast | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const removeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const onMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      const delta = startX.current - e.clientX;
      setWidth(Math.max(200, Math.min(640, startWidth.current + delta)));
    };
    const onMouseUp = () => {
      isDragging.current = false;
    };
    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
    return () => {
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    };
  }, []);

  const handleCopy = (e: React.MouseEvent, value: unknown) => {
    void navigator.clipboard.writeText(String(value)).catch(() => undefined);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    if (removeTimer.current) clearTimeout(removeTimer.current);
    setToast({ x: e.clientX, y: e.clientY, visible: true });
    hideTimer.current = setTimeout(
      () => setToast((t) => (t ? { ...t, visible: false } : null)),
      1400,
    );
    removeTimer.current = setTimeout(() => setToast(null), 2100);
  };

  if (!feature) return null;

  const { properties, columnSpecs } = feature;

  const rawAttrs: Record<string, unknown> =
    typeof properties.attributes === "string"
      ? (JSON.parse(properties.attributes) as Record<string, unknown>)
      : {};

  const labelFor = new Map(columnSpecs.map((s) => [s.alias, s.displayName]));

  const entries = Object.entries(rawAttrs).filter(
    ([, v]) => v !== null && v !== undefined && v !== "",
  );

  return (
    <>
      {/* Clipboard toast — fixed so it escapes overflow:hidden on the panel */}
      {toast && (
        <div
          style={{
            position: "fixed",
            left: toast.x + 14,
            top: toast.y - 18,
            opacity: toast.visible ? 1 : 0,
            transition: "opacity 0.7s ease",
            pointerEvents: "none",
            zIndex: 9999,
            background: "var(--accent)",
            color: "var(--accent-fg)",
            padding: "2px 8px",
            fontSize: "0.65rem",
            fontWeight: 700,
            letterSpacing: "0.1em",
          }}
        >
          COPIED
        </div>
      )}

      <div
        className="flex flex-col"
        style={{
          width,
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
        {/* Drag handle */}
        <div
          onMouseDown={(e) => {
            isDragging.current = true;
            startX.current = e.clientX;
            startWidth.current = width;
            e.preventDefault();
          }}
          style={{
            position: "absolute",
            left: -4,
            top: 0,
            bottom: 0,
            width: 8,
            cursor: "ew-resize",
            zIndex: 20,
          }}
        />

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
          className="px-3 py-2 flex items-center gap-2"
          style={{ borderBottom: "1px solid var(--border-col)", cursor: "copy" }}
          title="Double-click to copy identity"
          onDoubleClick={(e) => handleCopy(e, properties.identity ?? "")}
        >
          {properties.class_name && (
            <span
              className="inline-block flex-shrink-0 px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-widest"
              style={{
                border: "2px solid var(--accent2)",
                color: "var(--accent2)",
              }}
            >
              {properties.class_name}
            </span>
          )}
          <div
            className="text-sm font-black tracking-wide ml-auto min-w-0 overflow-hidden text-ellipsis whitespace-nowrap text-right"
            style={{
              fontFamily: "var(--font-orbitron), Orbitron, sans-serif",
              color: "var(--text)",
            }}
          >
            {properties.identity ?? "Unknown"}
          </div>
        </div>

        {/* Properties table */}
        <div className="flex-1 overflow-y-auto">
          <table className="w-full" style={{ tableLayout: "fixed" }}>
            <tbody>
              {entries.map(([key, value]) => {
                const registeredLabel = labelFor.get(key);
                return (
                  <tr
                    key={key}
                    className="transition-colors"
                    style={{
                      borderBottom: "1px solid var(--border-col)",
                      cursor: "copy",
                    }}
                    title="Double-click to copy value"
                    onDoubleClick={(e) => handleCopy(e, value)}
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
                        textTransform: "uppercase",
                        whiteSpace: "nowrap",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                      }}
                    >
                      {registeredLabel ?? key}
                    </td>
                    <td
                      className="px-3 py-1.5 text-right text-sm"
                      style={{
                        fontFamily: "'Courier New', monospace",
                        color: "var(--text)",
                        fontWeight: 500,
                        whiteSpace: "nowrap",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
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
    </>
  );
}
