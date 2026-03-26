import { useCallback, useState } from "react";
import { useDashboardStore, type MeasureMode, type MeasureUnit } from "../../store";
import { useEscapeKey } from "../../hooks/useEscapeKey";
import { IconButton, Button } from "../ui";
import { Ruler, Waypoints, Pentagon, X, Trash2, Copy, Check } from "lucide-react";
import { formatResult, pathDistance, polygonArea } from "./measurementHandlers";
import styles from "./MeasureToolbar.module.css";

const MEASURE_TOOLS: { mode: MeasureMode; icon: typeof Ruler; label: string }[] = [
  { mode: "distance", icon: Ruler, label: "Distance" },
  { mode: "path", icon: Waypoints, label: "Path" },
  { mode: "area", icon: Pentagon, label: "Area" },
];

const UNIT_OPTIONS: { value: MeasureUnit; label: string }[] = [
  { value: "metric", label: "m/km" },
  { value: "imperial", label: "ft/mi" },
  { value: "nautical", label: "NM" },
];

function getHint(mode: MeasureMode, vertexCount: number): string {
  switch (mode) {
    case "distance":
      return vertexCount === 0 ? "Click start point" : "Click end point";
    case "path":
      return vertexCount < 2
        ? `Click to add waypoints (${vertexCount}/2 min)`
        : `${vertexCount} points - click more or confirm`;
    case "area":
      return vertexCount < 3
        ? `Click to add vertices (${vertexCount}/3 min)`
        : `${vertexCount} vertices - click more or confirm`;
  }
}

function canConfirm(mode: MeasureMode, vertexCount: number): boolean {
  switch (mode) {
    case "distance":
      return false; // auto-completes on second click
    case "path":
      return vertexCount >= 2;
    case "area":
      return vertexCount >= 3;
  }
}

/**
 * Measurement active panel + results list.
 * Idle tool buttons live in MapToolbar.
 * Active panel replaces the bottom toolbar when a measure tool is selected.
 * Results panel floats bottom-right, above the toolbar line.
 */
export default function MeasureToolbar() {
  const measurement = useDashboardStore((s) => s.measurement);
  const setMeasureMode = useDashboardStore((s) => s.setMeasureMode);
  const setMeasureUnit = useDashboardStore((s) => s.setMeasureUnit);
  const undoMeasureVertex = useDashboardStore((s) => s.undoMeasureVertex);
  const completeMeasurement = useDashboardStore((s) => s.completeMeasurement);
  const removeMeasurement = useDashboardStore((s) => s.removeMeasurement);
  const clearMeasurements = useDashboardStore((s) => s.clearMeasurements);
  const clearActiveMeasurement = useDashboardStore((s) => s.clearActiveMeasurement);

  const [copiedId, setCopiedId] = useState<string | null>(null);

  // Escape key cancels measurement
  useEscapeKey(
    useCallback(() => setMeasureMode(null), [setMeasureMode]),
    !!measurement.mode
  );

  const activeMode = measurement.mode;
  const hasResults = measurement.results.length > 0;

  const handleConfirm = useCallback(() => {
    if (!measurement.mode) return;

    if (measurement.mode === "path") {
      const { total, segments } = pathDistance(measurement.vertices);
      completeMeasurement({
        id: crypto.randomUUID(),
        mode: "path",
        vertices: [...measurement.vertices],
        value: total,
        segments,
      });
    } else if (measurement.mode === "area") {
      const area = polygonArea(measurement.vertices);
      const perimeterInfo = pathDistance([...measurement.vertices, measurement.vertices[0]]);
      completeMeasurement({
        id: crypto.randomUUID(),
        mode: "area",
        vertices: [...measurement.vertices],
        value: area,
        segments: perimeterInfo.segments,
      });
    }
  }, [measurement, completeMeasurement]);

  const handleCopy = useCallback(
    (id: string, text: string) => {
      navigator.clipboard.writeText(text).catch(() => {});
      setCopiedId(id);
      setTimeout(() => setCopiedId(null), 1500);
    },
    []
  );

  const handleCancelActive = useCallback(() => {
    if (measurement.vertices.length > 0) {
      clearActiveMeasurement();
    } else {
      setMeasureMode(null);
    }
  }, [measurement.vertices.length, clearActiveMeasurement, setMeasureMode]);

  return (
    <>
      {/* Active measurement panel - bottom center, replaces idle toolbar */}
      {activeMode && (
        <div className={styles.activePanel}>
          {/* Tool identity */}
          <div className={styles.group}>
            {MEASURE_TOOLS.map(({ mode, icon: Icon }) =>
              mode === activeMode ? (
                <IconButton key={mode} size="sm" label={mode} active>
                  <Icon size={16} />
                </IconButton>
              ) : null
            )}
          </div>

          <div className={styles.separator} />

          {/* Hint */}
          <span className={styles.hintText}>
            {getHint(activeMode, measurement.vertices.length)}
          </span>

          <div className={styles.separator} />

          {/* Unit toggle */}
          <div className={styles.unitGroup}>
            {UNIT_OPTIONS.map(({ value, label }) => (
              <button
                key={value}
                className={`${styles.unitButton} ${
                  measurement.unit === value ? styles.unitActive : ""
                }`}
                onClick={() => setMeasureUnit(value)}
              >
                {label}
              </button>
            ))}
          </div>

          <div className={styles.separator} />

          {/* Actions */}
          <div className={styles.group}>
            {measurement.vertices.length > 0 && (
              <Button variant="ghost" size="sm" onClick={undoMeasureVertex}>
                Undo
              </Button>
            )}
            {canConfirm(activeMode, measurement.vertices.length) && (
              <Button variant="primary" size="sm" onClick={handleConfirm}>
                Confirm
              </Button>
            )}
            <button
              className={styles.closeButton}
              onClick={handleCancelActive}
              title="Cancel measurement"
            >
              <X size={14} />
            </button>
          </div>
        </div>
      )}

      {/* Results list - bottom-right, above toolbar line */}
      {hasResults && (
        <div className={styles.resultsPanel}>
          <div className={styles.resultsHeader}>
            <span className={styles.resultsTitle}>Measurements</span>
            <button
              className={styles.clearAll}
              onClick={clearMeasurements}
              title="Clear all"
            >
              <Trash2 size={12} />
            </button>
          </div>
          <div className={styles.resultsList}>
            {measurement.results.map((r) => {
              const text = formatResult(r, measurement.unit);
              return (
                <div key={r.id} className={styles.resultRow}>
                  <span className={styles.resultMode}>
                    {r.mode === "distance"
                      ? "Dist"
                      : r.mode === "path"
                        ? "Path"
                        : "Area"}
                  </span>
                  <span className={styles.resultValue}>{text}</span>
                  {r.mode === "path" && r.segments.length > 1 && (
                    <span className={styles.resultDetail}>
                      {r.segments.length} legs
                    </span>
                  )}
                  <button
                    className={styles.copyButton}
                    onClick={() => handleCopy(r.id, text)}
                    title="Copy to clipboard"
                  >
                    {copiedId === r.id ? <Check size={12} /> : <Copy size={12} />}
                  </button>
                  <button
                    className={styles.removeButton}
                    onClick={() => removeMeasurement(r.id)}
                    title="Remove"
                  >
                    <X size={12} />
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </>
  );
}
