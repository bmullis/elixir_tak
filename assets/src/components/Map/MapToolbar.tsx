import { useCallback } from "react";
import { useDashboardStore, type DrawingMode, type MeasureMode } from "../../store";
import { IconButton, Tooltip } from "../ui";
import {
  MapPin,
  Triangle,
  Square,
  Circle,
  Route,
  Ruler,
  Waypoints,
  Pentagon,
  type LucideIcon,
} from "lucide-react";
import styles from "./MapToolbar.module.css";

const DRAW_TOOLS: { mode: DrawingMode; icon: LucideIcon; label: string }[] = [
  { mode: "marker", icon: MapPin, label: "Marker" },
  { mode: "polygon", icon: Triangle, label: "Polygon" },
  { mode: "rectangle", icon: Square, label: "Rectangle" },
  { mode: "circle", icon: Circle, label: "Circle" },
  { mode: "route", icon: Route, label: "Route" },
];

const MEASURE_TOOLS: { mode: MeasureMode; icon: LucideIcon; label: string }[] = [
  { mode: "distance", icon: Ruler, label: "Distance" },
  { mode: "path", icon: Waypoints, label: "Path" },
  { mode: "area", icon: Pentagon, label: "Area" },
];

/**
 * Unified idle toolbar shown at bottom center of the map.
 * Contains drawing tools + measurement tools in one strip.
 * Hidden when any tool is active (replaced by that tool's options panel).
 */
export default function MapToolbar() {
  const drawingMode = useDashboardStore((s) => s.drawing.mode);
  const measureMode = useDashboardStore((s) => s.measurement.mode);
  const identity = useDashboardStore((s) => s.identity);
  const setDrawingMode = useDashboardStore((s) => s.setDrawingMode);
  const setMeasureMode = useDashboardStore((s) => s.setMeasureMode);

  const handleDrawTool = useCallback(
    (mode: DrawingMode) => setDrawingMode(mode),
    [setDrawingMode]
  );

  const handleMeasureTool = useCallback(
    (mode: MeasureMode) => setMeasureMode(mode),
    [setMeasureMode]
  );

  // Hide when any tool is active (active panels take over)
  if (drawingMode || measureMode) return null;

  return (
    <div className={styles.toolbar}>
      {/* Callsign */}
      <span className={styles.callsignLabel} title="Dashboard callsign">
        {identity.callsign}
      </span>

      <div className={styles.separator} />

      {/* Drawing tools */}
      {DRAW_TOOLS.map(({ mode, icon: Icon, label }) => (
        <Tooltip key={mode} content={label} side="top">
          <IconButton
            size="sm"
            label={label}
            onClick={() => handleDrawTool(mode)}
          >
            <Icon size={16} />
          </IconButton>
        </Tooltip>
      ))}

      <div className={styles.separator} />

      {/* Measurement tools */}
      {MEASURE_TOOLS.map(({ mode, icon: Icon, label }) => (
        <Tooltip key={mode} content={label} side="top">
          <IconButton
            size="sm"
            label={label}
            onClick={() => handleMeasureTool(mode)}
          >
            <Icon size={16} />
          </IconButton>
        </Tooltip>
      ))}
    </div>
  );
}
