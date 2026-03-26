import { useCallback, useRef } from "react";
import { useDashboardStore, type DrawingMode } from "../../store";
import { getChannel } from "../../hooks/useChannel";
import { IconButton, Button, Input } from "../ui";
import { MapPin, Triangle, Square, Circle, Route, X, type LucideIcon } from "lucide-react";
import styles from "./DrawingToolbar.module.css";

/** Lucide icon + label for each drawing tool */
const TOOL_ICONS: Record<DrawingMode, { icon: LucideIcon; label: string }> = {
  marker: { icon: MapPin, label: "Marker" },
  polygon: { icon: Triangle, label: "Polygon" },
  rectangle: { icon: Square, label: "Rectangle" },
  circle: { icon: Circle, label: "Circle" },
  route: { icon: Route, label: "Route" },
};

/** Hint text shown for each active drawing mode */
function getHint(mode: DrawingMode, vertexCount: number): string {
  switch (mode) {
    case "marker":
      return "Click map to place marker";
    case "polygon":
      return vertexCount < 3
        ? `Click to add vertices (${vertexCount}/3 min)`
        : `${vertexCount} vertices - click more or confirm`;
    case "rectangle":
      return vertexCount === 0
        ? "Click first corner"
        : "Click opposite corner";
    case "circle":
      return vertexCount === 0
        ? "Click center point"
        : "Click edge to set radius";
    case "route":
      return vertexCount < 2
        ? `Click to add waypoints (${vertexCount}/2 min)`
        : `${vertexCount} waypoints - click more or confirm`;
  }
}

/** Check if the current drawing can be submitted */
function canConfirm(mode: DrawingMode, drawing: { vertices: { lat: number; lon: number }[]; center: { lat: number; lon: number } | null; radius: number | null }): boolean {
  switch (mode) {
    case "marker":
      return drawing.vertices.length >= 1;
    case "polygon":
      return drawing.vertices.length >= 3;
    case "rectangle":
      return drawing.vertices.length >= 2;
    case "circle":
      return drawing.center != null && drawing.radius != null;
    case "route":
      return drawing.vertices.length >= 2;
  }
}

/**
 * Drawing options panel - only renders when a drawing tool is active.
 * The idle tool buttons live in MapToolbar.
 */
export default function DrawingToolbar() {
  const drawing = useDashboardStore((s) => s.drawing);
  const identity = useDashboardStore((s) => s.identity);
  const setDrawingName = useDashboardStore((s) => s.setDrawingName);
  const setDrawingColor = useDashboardStore((s) => s.setDrawingColor);
  const undoDrawingVertex = useDashboardStore((s) => s.undoDrawingVertex);
  const clearDrawing = useDashboardStore((s) => s.clearDrawing);
  const colorInputRef = useRef<HTMLInputElement>(null);

  const handleConfirm = useCallback(() => {
    if (!drawing.mode) return;

    const channel = getChannel();
    if (!channel) return;

    const mode = drawing.mode;
    const name = drawing.name || identity.callsign + "'s " + mode;

    if (mode === "marker") {
      const v = drawing.vertices[0];
      if (!v) return;
      channel.push("place_marker", {
        lat: v.lat,
        lon: v.lon,
        callsign: name,
        remarks: drawing.remarks || null,
      });
    } else if (mode === "polygon") {
      channel.push("draw_shape", {
        name,
        shape_type: "polygon",
        vertices: drawing.vertices.map((v) => ({ lat: v.lat, lon: v.lon })),
        color: drawing.color,
        remarks: drawing.remarks || null,
      });
    } else if (mode === "rectangle") {
      const [a, b] = drawing.vertices;
      const rectVerts = [
        { lat: a.lat, lon: a.lon },
        { lat: a.lat, lon: b.lon },
        { lat: b.lat, lon: b.lon },
        { lat: b.lat, lon: a.lon },
      ];
      channel.push("draw_shape", {
        name,
        shape_type: "rectangle",
        vertices: rectVerts,
        color: drawing.color,
        remarks: drawing.remarks || null,
      });
    } else if (mode === "circle") {
      if (!drawing.center || drawing.radius == null) return;
      channel.push("draw_shape", {
        name,
        shape_type: "circle",
        vertices: drawing.vertices.map((v) => ({ lat: v.lat, lon: v.lon })),
        center: { lat: drawing.center.lat, lon: drawing.center.lon },
        radius: drawing.radius,
        color: drawing.color,
        remarks: drawing.remarks || null,
      });
    } else if (mode === "route") {
      channel.push("draw_route", {
        name,
        waypoints: drawing.vertices.map((v) => ({ lat: v.lat, lon: v.lon })),
        color: drawing.color,
        remarks: drawing.remarks || null,
      });
    }

    clearDrawing();
  }, [drawing, identity.callsign, clearDrawing]);

  const handleColorChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const hex = e.target.value;
      const r = parseInt(hex.slice(1, 3), 16);
      const g = parseInt(hex.slice(3, 5), 16);
      const b = parseInt(hex.slice(5, 7), 16);
      setDrawingColor(`rgba(${r}, ${g}, ${b}, 1)`);
    },
    [setDrawingColor]
  );

  const currentHex = (() => {
    const m = drawing.color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) return "#00bcd4";
    const r = parseInt(m[1]).toString(16).padStart(2, "0");
    const g = parseInt(m[2]).toString(16).padStart(2, "0");
    const b = parseInt(m[3]).toString(16).padStart(2, "0");
    return `#${r}${g}${b}`;
  })();

  const activeMode = drawing.mode;
  if (!activeMode) return null;

  const ActiveIcon = TOOL_ICONS[activeMode].icon;

  return (
    <div className={styles.optionsPanel}>
      {/* Left group: tool identity + naming */}
      <div className={styles.group}>
        <IconButton size="sm" label={TOOL_ICONS[activeMode].label} active>
          <ActiveIcon size={16} />
        </IconButton>
        <Input
          inputSize="sm"
          value={drawing.name}
          onChange={(e) => setDrawingName(e.target.value)}
          placeholder={`${TOOL_ICONS[activeMode].label} name`}
          className={styles.nameInput}
        />
        {activeMode !== "marker" && (
          <>
            <button
              className={styles.colorSwatch}
              style={{ backgroundColor: currentHex }}
              onClick={() => colorInputRef.current?.click()}
              title="Stroke color"
            />
            <input
              ref={colorInputRef}
              type="color"
              className={styles.colorInput}
              value={currentHex}
              onChange={handleColorChange}
            />
          </>
        )}
      </div>

      <div className={styles.separator} />

      {/* Center: contextual hint */}
      <div className={styles.hintGroup}>
        <span className={styles.hintText}>
          {getHint(activeMode, drawing.vertices.length)}
        </span>
      </div>

      <div className={styles.separator} />

      {/* Right group: actions */}
      <div className={styles.group}>
        {drawing.vertices.length > 0 && activeMode !== "marker" && (
          <Button variant="ghost" size="sm" onClick={undoDrawingVertex}>
            Undo
          </Button>
        )}
        <Button
          variant="primary"
          size="sm"
          onClick={handleConfirm}
          disabled={!canConfirm(activeMode, drawing)}
        >
          Confirm
        </Button>
        <button
          className={styles.closeButton}
          onClick={clearDrawing}
          title="Cancel drawing"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
}
