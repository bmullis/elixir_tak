import { useCallback } from "react";
import { useDashboardStore, type LayerKey, type BasemapStyle } from "../../store";
import { Button, PanelHeader } from "../ui";
import { Layers } from "lucide-react";
import styles from "./LayerPanel.module.css";

interface LayerDef {
  key: LayerKey;
  label: string;
  color: string;
}

interface GroupDef {
  name: string;
  color: string;
}

const LAYER_DEFS: LayerDef[] = [
  { key: "sa-friendly", label: "Friendly SA", color: "#2196F3" },
  { key: "sa-hostile", label: "Hostile SA", color: "#F44336" },
  { key: "sa-neutral", label: "Neutral SA", color: "#4CAF50" },
  { key: "sa-unknown", label: "Unknown SA", color: "#4CAF50" },
  { key: "marker", label: "Markers", color: "#FF9800" },
  { key: "shape", label: "Shapes", color: "#00BCD4" },
  { key: "route", label: "Routes", color: "#00BCD4" },
  { key: "geofence", label: "Geofences", color: "#FF9800" },
  { key: "track", label: "Track History", color: "#00BCD4" },
  { key: "emergency", label: "Emergencies", color: "#F44336" },
  { key: "video", label: "Video Feeds", color: "#AB47BC" },
];

const GROUP_DEFS: GroupDef[] = [
  { name: "Cyan", color: "#00BCD4" },
  { name: "Yellow", color: "#FFEB3B" },
  { name: "Magenta", color: "#E040FB" },
  { name: "Green", color: "#4CAF50" },
  { name: "Red", color: "#F44336" },
  { name: "Blue", color: "#2196F3" },
  { name: "White", color: "#FAFAFA" },
  { name: "Orange", color: "#FF9800" },
  { name: "Maroon", color: "#8D1C1C" },
  { name: "Purple", color: "#9C27B0" },
  { name: "Dark Green", color: "#2E7D32" },
  { name: "Teal", color: "#009688" },
];

/** Collapsible left-side panel for layer visibility, opacity, and group filtering */
export default function LayerPanel() {
  const open = useDashboardStore((s) => s.leftPanel === "layers");
  const toggleLeftPanel = useDashboardStore((s) => s.toggleLeftPanel);

  const layerState = useDashboardStore((s) => s.layerState);
  const setLayerVisibility = useDashboardStore((s) => s.setLayerVisibility);
  const setLayerOpacity = useDashboardStore((s) => s.setLayerOpacity);
  const setSoloLayer = useDashboardStore((s) => s.setSoloLayer);
  const setGroupFilter = useDashboardStore((s) => s.setGroupFilter);
  const setAllGroups = useDashboardStore((s) => s.setAllGroups);
  const showAllLayers = useDashboardStore((s) => s.showAllLayers);
  const hideAllLayers = useDashboardStore((s) => s.hideAllLayers);

  const basemap = useDashboardStore((s) => s.basemap);
  const setBasemap = useDashboardStore((s) => s.setBasemap);

  const toggle = useCallback(() => toggleLeftPanel("layers"), [toggleLeftPanel]);

  const handleGroupToggle = useCallback(
    (name: string, checked: boolean) => {
      if (checked) {
        // Check if all groups would now be enabled
        const allEnabled =
          GROUP_DEFS.every((g) =>
            g.name === name ? true : layerState.groups[g.name]
          );
        if (allEnabled) {
          setAllGroups(true);
        } else {
          setGroupFilter(name, true);
        }
      } else {
        setGroupFilter(name, false);
      }
    },
    [layerState.groups, setGroupFilter, setAllGroups]
  );

  const handleAllGroupsToggle = useCallback(
    (checked: boolean) => {
      setAllGroups(checked);
    },
    [setAllGroups]
  );

  return (
    <>
      {/* Toggle FAB */}
      {!open && (
        <button
          className={styles.fab}
          onClick={toggle}
          aria-label="Open layer panel"
        >
          <Layers size={22} />
        </button>
      )}

      {/* Panel */}
      <div className={`${styles.panel} ${open ? styles.panelOpen : ""}`}>
        <PanelHeader title="Layers" onClose={toggle} />
        <div className={styles.content}>
          {/* Basemap */}
          <div className={styles.sectionLabel}>Basemap</div>
          <div className={styles.basemapRow}>
            {(["dark", "satellite", "hybrid"] as BasemapStyle[]).map((s) => (
              <button
                key={s}
                className={`${styles.basemapBtn} ${basemap === s ? styles.basemapBtnActive : ""}`}
                onClick={() => setBasemap(s)}
              >
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>

          {/* Entity Layers */}
          <div className={styles.sectionLabel}>Entity Layers</div>
          {LAYER_DEFS.map((def) => (
            <LayerRow
              key={def.key}
              def={def}
              visible={layerState.types[def.key].visible}
              opacity={layerState.types[def.key].opacity}
              isSolo={layerState.soloLayer === def.key}
              onToggle={(v) => setLayerVisibility(def.key, v)}
              onOpacity={(o) => setLayerOpacity(def.key, o)}
              onSolo={() => setSoloLayer(def.key)}
            />
          ))}

          {/* Bulk actions */}
          <div className={styles.bulkRow}>
            <Button variant="secondary" size="sm" mono fullWidth onClick={showAllLayers}>
              Show All
            </Button>
            <Button variant="secondary" size="sm" mono fullWidth onClick={hideAllLayers}>
              Hide All
            </Button>
          </div>

          {/* Group Filter */}
          <div className={styles.sectionLabel}>Group Filter</div>
          <div className={styles.sectionNote}>Affects SA markers only</div>

          <label className={styles.allGroupRow}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={layerState.allGroups}
              onChange={(e) => handleAllGroupsToggle(e.target.checked)}
            />
            <span className={styles.allGroupLabel}>All Groups</span>
          </label>

          <div className={styles.groupGrid}>
            {GROUP_DEFS.map((gd) => {
              const isChecked =
                layerState.allGroups || !!layerState.groups[gd.name];
              return (
                <label key={gd.name} className={styles.groupRow}>
                  <input
                    type="checkbox"
                    className={styles.checkbox}
                    checked={isChecked}
                    onChange={(e) =>
                      handleGroupToggle(gd.name, e.target.checked)
                    }
                  />
                  <span
                    className={styles.groupSwatch}
                    style={{ backgroundColor: gd.color }}
                  />
                  <span className={styles.groupLabel}>{gd.name}</span>
                </label>
              );
            })}
          </div>
        </div>
      </div>
    </>
  );
}

/** Single layer row with checkbox, label, opacity slider, and solo button */
function LayerRow({
  def,
  visible,
  opacity,
  isSolo,
  onToggle,
  onOpacity,
  onSolo,
}: {
  def: LayerDef;
  visible: boolean;
  opacity: number;
  isSolo: boolean;
  onToggle: (v: boolean) => void;
  onOpacity: (o: number) => void;
  onSolo: () => void;
}) {
  return (
    <div className={styles.layerRow}>
      <span className={styles.dot} style={{ backgroundColor: def.color }} />
      <input
        type="checkbox"
        className={styles.checkbox}
        checked={visible}
        onChange={(e) => onToggle(e.target.checked)}
      />
      <span className={styles.layerLabel}>{def.label}</span>
      <input
        type="range"
        className={styles.slider}
        min="0.1"
        max="1.0"
        step="0.1"
        value={opacity}
        onChange={(e) => onOpacity(parseFloat(e.target.value))}
      />
      <button
        className={`${styles.soloBtn} ${isSolo ? styles.soloBtnActive : ""}`}
        onClick={onSolo}
        title="Solo this layer"
      >
        S
      </button>
    </div>
  );
}
