import { useCallback, useEffect } from "react";
import {
  useDashboardStore,
  type TrackWindow,
  type TrackPoint,
} from "../../store";
import { useEscapeKey } from "../../hooks/useEscapeKey";
import { entityTypeLabel, formatTimeDelta } from "../../utils/formatting";
import {
  SaDetail,
  MarkerDetail,
  ShapeDetail,
  RouteDetail,
  GeofenceDetail,
  VideoDetail,
  DeleteButton,
} from "./DetailPanels";
import { Button, PanelHeader, Toggle } from "../ui";
import styles from "./DetailSidebar.module.css";

const TRACK_WINDOWS: TrackWindow[] = ["1h", "4h", "12h", "24h"];

const WINDOW_HOURS: Record<TrackWindow, number> = {
  "1h": 1,
  "4h": 4,
  "12h": 12,
  "24h": 24,
};

/** Flyout sidebar showing details for the selected map entity */
export default function DetailSidebar() {
  const selectedEntity = useDashboardStore((s) => s.selectedEntity);
  const positions = useDashboardStore((s) => s.positions);
  const parsedMarkers = useDashboardStore((s) => s.parsedMarkers);
  const parsedShapes = useDashboardStore((s) => s.parsedShapes);
  const parsedRoutes = useDashboardStore((s) => s.parsedRoutes);
  const parsedGeofences = useDashboardStore((s) => s.parsedGeofences);
  const trackWindow = useDashboardStore((s) => s.trackWindow);
  const trackVisible = useDashboardStore((s) => s.trackVisible);
  const trackLoading = useDashboardStore((s) => s.trackLoading);
  const tracks = useDashboardStore((s) => s.tracks);
  const videoStreams = useDashboardStore((s) => s.videoStreams);

  const selectEntity = useDashboardStore((s) => s.selectEntity);
  const setTrackWindow = useDashboardStore((s) => s.setTrackWindow);
  const toggleTrack = useDashboardStore((s) => s.toggleTrack);
  const setTrackData = useDashboardStore((s) => s.setTrackData);
  const setTrackLoading = useDashboardStore((s) => s.setTrackLoading);

  const isOpen = selectedEntity !== null;
  const uid = selectedEntity?.uid ?? "";
  const entityType = selectedEntity?.entityType ?? "sa";

  const close = useCallback(() => selectEntity(null), [selectEntity]);

  useEscapeKey(close, isOpen);

  // Fetch track when toggled on or window changes
  const isTrackVisible = trackVisible.has(uid);

  const fetchTrack = useCallback(
    async (targetUid: string, window: TrackWindow) => {
      setTrackLoading(true);
      try {
        const since = new Date(
          Date.now() - WINDOW_HOURS[window] * 3600_000
        ).toISOString();
        const resp = await fetch(
          `/api/admin/track/${encodeURIComponent(targetUid)}?since=${since}&limit=500`
        );
        if (resp.ok) {
          const data = await resp.json();
          setTrackData(targetUid, data.points ?? []);
        }
      } finally {
        setTrackLoading(false);
      }
    },
    [setTrackData, setTrackLoading]
  );

  useEffect(() => {
    if (isTrackVisible && uid) {
      fetchTrack(uid, trackWindow);
    }
  }, [isTrackVisible, uid, trackWindow, fetchTrack]);

  const handleToggleTrack = useCallback(() => {
    if (!uid) return;
    toggleTrack(uid);
  }, [uid, toggleTrack]);

  const handleWindowChange = useCallback(
    (w: TrackWindow) => {
      setTrackWindow(w);
    },
    [setTrackWindow]
  );

  // Resolve entity data
  const saEvent = entityType === "sa" ? positions.get(uid) : null;
  const marker = entityType === "marker" ? parsedMarkers.get(uid) : null;
  const shape = entityType === "shape" ? parsedShapes.get(uid) : null;
  const route = entityType === "route" ? parsedRoutes.get(uid) : null;
  const geofence = entityType === "geofence" ? parsedGeofences.get(uid) : null;
  const videoStream = entityType === "video" ? videoStreams.get(uid) : null;

  const trackPoints: TrackPoint[] = tracks.get(uid) ?? [];

  return (
    <div className={styles.overlay}>
      <div className={`${styles.sidebar} ${isOpen ? styles.open : ""}`}>
        {isOpen && (
          <>
            <PanelHeader title={entityTypeLabel(entityType)} onClose={close} />

            {saEvent && <SaDetail event={saEvent} />}
            {marker && <MarkerDetail marker={marker} />}
            {shape && <ShapeDetail shape={shape} />}
            {route && <RouteDetail route={route} />}
            {geofence && <GeofenceDetail geofence={geofence} />}
            {videoStream && <VideoDetail stream={videoStream} />}

            {/* Track section for SA entities */}
            {entityType === "sa" && (
              <div className={styles.body}>
                <div className={styles.trackSection}>
                  <div className={styles.trackHeader}>
                    <span className={styles.trackTitle}>Track History</span>
                    <div className={styles.windowSelector}>
                      {TRACK_WINDOWS.map((w) => (
                        <Toggle
                          key={w}
                          size="sm"
                          mono
                          pressed={w === trackWindow}
                          onPressedChange={() => handleWindowChange(w)}
                        >
                          {w}
                        </Toggle>
                      ))}
                    </div>
                  </div>
                  <Button
                    variant={isTrackVisible ? "primary" : "secondary"}
                    size="sm"
                    mono
                    fullWidth
                    onClick={handleToggleTrack}
                    disabled={trackLoading}
                  >
                    {trackLoading
                      ? "Loading..."
                      : isTrackVisible
                        ? "Hide Track"
                        : "Show Track"}
                  </Button>
                  {isTrackVisible && trackPoints.length > 0 && (
                    <div className={styles.trackStats}>
                      <span>{trackPoints.length} points</span>
                      <span>
                        {formatTimeDelta(trackPoints[0]?.time, trackPoints[trackPoints.length - 1]?.time)}
                      </span>
                    </div>
                  )}
                </div>
                <div className={styles.uid}>{uid}</div>
              </div>
            )}

            {entityType !== "sa" && (
              <div className={styles.body}>
                <div className={styles.uid}>{uid}</div>
                {uid.startsWith("dashboard-") && (
                  <DeleteButton uid={uid} entityType={entityType} onDelete={close} />
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
