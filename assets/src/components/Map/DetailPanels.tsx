import { useCallback } from "react";
import type { EntityType } from "../../store";
import type { CotEvent, VideoStream } from "../../types";
import { getChannel } from "../../hooks/useChannel";
import { useHlsPlayer } from "../../hooks/useHlsPlayer";
import { affiliationFromType, affiliationCssColor } from "./icons";
import { parseEmbeddedVideo, formatTime } from "../../utils/formatting";
import { Button } from "../ui";
import styles from "./DetailSidebar.module.css";

// ── Field ───────────────────────────────────────────────────────────────────

export function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className={styles.field}>
      <span className={styles.fieldLabel}>{label}</span>
      <span className={styles.fieldValue}>{value}</span>
    </div>
  );
}

// ── Remarks block (shared by Marker, Shape, Route, Geofence) ────────────────

function Remarks({ text }: { text: string }) {
  return (
    <div className={styles.fieldGroup}>
      <div className={styles.fieldGroupLabel}>Remarks</div>
      <p
        style={{
          font: "400 12px/1.5 var(--font-mono)",
          color: "var(--color-text-muted)",
          margin: "4px 0 0",
          whiteSpace: "pre-wrap",
        }}
      >
        {text}
      </p>
    </div>
  );
}

// ── SA Detail ───────────────────────────────────────────────────────────────

export function SaDetail({ event }: { event: CotEvent }) {
  const callsign = event.detail?.contact?.callsign || event.uid;
  const group = event.detail?.group?.name || "Unknown";
  const role = event.detail?.group?.role || "";
  const speed = event.detail?.track?.speed;
  const course = event.detail?.track?.course;
  const affiliation = affiliationFromType(event.type);
  const color = affiliationCssColor(affiliation);

  const embeddedVideo = parseEmbeddedVideo(event.raw_detail);

  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span
          className={styles.affiliationDot}
          style={{ background: color }}
        />
        <span className={styles.callsign}>{callsign}</span>
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Position</div>
        <Field label="Lat" value={event.point?.lat?.toFixed(6) ?? "-"} />
        <Field label="Lon" value={event.point?.lon?.toFixed(6) ?? "-"} />
        {event.point?.hae != null && (
          <Field label="Alt" value={`${event.point.hae.toFixed(0)} m`} />
        )}
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Movement</div>
        <Field
          label="Speed"
          value={speed != null ? `${(speed * 2.237).toFixed(1)} mph` : "-"}
        />
        <Field
          label="Course"
          value={course != null ? `${course.toFixed(0)}\u00B0` : "-"}
        />
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Identity</div>
        <Field label="Group" value={group} />
        {role && <Field label="Role" value={role} />}
        <Field label="Affiliation" value={affiliation} />
        <Field label="Type" value={event.type} />
        <Field label="How" value={event.how ?? "-"} />
      </div>
      {event.stale && (
        <div className={styles.fieldGroup}>
          <div className={styles.fieldGroupLabel}>Timing</div>
          <Field label="Last seen" value={formatTime(event.time)} />
          <Field label="Stale" value={formatTime(event.stale)} />
        </div>
      )}
      {embeddedVideo && (
        <EmbeddedVideoPlayer
          url={embeddedVideo.url}
          protocol={embeddedVideo.protocol}
        />
      )}
    </div>
  );
}

// ── Marker Detail ───────────────────────────────────────────────────────────

export function MarkerDetail({
  marker,
}: {
  marker: { uid: string; lat: number; lon: number; callsign: string; remarks: string | null };
}) {
  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span
          className={styles.affiliationDot}
          style={{ background: "#FF9800" }}
        />
        <span className={styles.callsign}>{marker.callsign}</span>
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Position</div>
        <Field label="Lat" value={marker.lat.toFixed(6)} />
        <Field label="Lon" value={marker.lon.toFixed(6)} />
      </div>
      {marker.remarks && <Remarks text={marker.remarks} />}
    </div>
  );
}

// ── Shape Detail ────────────────────────────────────────────────────────────

export function ShapeDetail({
  shape,
}: {
  shape: {
    uid: string;
    name: string | null;
    shape_type: string;
    remarks: string | null;
    radius: number | null;
    vertices: { lat: number; lon: number }[];
  };
}) {
  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span className={styles.callsign}>{shape.name || "Shape"}</span>
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Properties</div>
        <Field label="Type" value={shape.shape_type} />
        {shape.radius != null && (
          <Field label="Radius" value={`${shape.radius.toFixed(0)} m`} />
        )}
        <Field label="Vertices" value={String(shape.vertices.length)} />
      </div>
      {shape.remarks && <Remarks text={shape.remarks} />}
    </div>
  );
}

// ── Route Detail ────────────────────────────────────────────────────────────

export function RouteDetail({
  route,
}: {
  route: {
    uid: string;
    name: string | null;
    waypoint_count: number;
    total_distance_m: number;
    remarks: string | null;
  };
}) {
  const distKm = (route.total_distance_m / 1000).toFixed(1);
  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span className={styles.callsign}>{route.name || "Route"}</span>
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Properties</div>
        <Field label="Waypoints" value={String(route.waypoint_count)} />
        <Field label="Distance" value={`${distKm} km`} />
      </div>
      {route.remarks && <Remarks text={route.remarks} />}
    </div>
  );
}

// ── Geofence Detail ─────────────────────────────────────────────────────────

export function GeofenceDetail({
  geofence,
}: {
  geofence: {
    uid: string;
    name: string | null;
    shape_type: string;
    trigger: string | null;
    monitor_type: string | null;
    boundary_type: string | null;
    remarks: string | null;
    radius: number | null;
    vertices: { lat: number; lon: number }[];
  };
}) {
  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span className={styles.callsign}>
          {geofence.name || "Geofence"}
        </span>
      </div>
      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Properties</div>
        <Field label="Type" value={geofence.shape_type} />
        {geofence.trigger && (
          <Field label="Trigger" value={geofence.trigger} />
        )}
        {geofence.monitor_type && (
          <Field label="Monitor" value={geofence.monitor_type} />
        )}
        {geofence.boundary_type && (
          <Field label="Boundary" value={geofence.boundary_type} />
        )}
        {geofence.radius != null && (
          <Field label="Radius" value={`${geofence.radius.toFixed(0)} m`} />
        )}
        <Field label="Vertices" value={String(geofence.vertices.length)} />
      </div>
      {geofence.remarks && <Remarks text={geofence.remarks} />}
    </div>
  );
}

// ── Embedded Video Player (for SA entities with <__video>) ──────────────────

function EmbeddedVideoPlayer({
  url,
  protocol,
}: {
  url: string;
  protocol: string;
}) {
  const { videoRef, playing, canPlay } = useHlsPlayer({ url, protocol });

  return (
    <div className={styles.fieldGroup}>
      <div className={styles.fieldGroupLabel}>Video Feed</div>
      <div
        style={{
          position: "relative",
          width: "100%",
          aspectRatio: "16/9",
          background: "#000",
          borderRadius: 4,
          overflow: "hidden",
          marginTop: 4,
        }}
      >
        <video
          ref={videoRef}
          playsInline
          muted
          autoPlay
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
        {!playing && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "var(--color-text-dim)",
              fontSize: "0.75rem",
            }}
          >
            {canPlay ? (
              <span>Connecting...</span>
            ) : (
              <span>{protocol.toUpperCase()} - no browser playback</span>
            )}
          </div>
        )}
      </div>
      <div
        style={{
          font: "400 10px/1.3 var(--font-mono)",
          color: "var(--color-text-dim)",
          wordBreak: "break-all",
          marginTop: 2,
        }}
      >
        {url}
      </div>
    </div>
  );
}

// ── Video Detail (standalone video stream entity) ───────────────────────────

export function VideoDetail({ stream }: { stream: VideoStream }) {
  const { videoRef, playing, canPlay } = useHlsPlayer({
    url: stream.url ?? "",
    protocol: stream.protocol,
  });

  return (
    <div className={styles.body} style={{ flex: "none" }}>
      <div className={styles.titleRow}>
        <span
          className={styles.affiliationDot}
          style={{ background: "#AB47BC" }}
        />
        <span className={styles.callsign}>{stream.alias}</span>
      </div>

      <div
        style={{
          position: "relative",
          width: "100%",
          aspectRatio: "16/9",
          background: "#000",
          borderRadius: 4,
          overflow: "hidden",
          margin: "8px 0",
        }}
      >
        <video
          ref={videoRef}
          playsInline
          muted
          autoPlay
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
        {!playing && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              color: "var(--color-text-dim)",
              fontSize: "0.75rem",
            }}
          >
            {canPlay ? (
              <span>Connecting...</span>
            ) : (
              <span>{stream.protocol.toUpperCase()} - no browser playback</span>
            )}
          </div>
        )}
      </div>

      <div className={styles.fieldGroup}>
        <div className={styles.fieldGroupLabel}>Stream Info</div>
        <Field label="Protocol" value={stream.protocol.toUpperCase()} />
        {stream.lat != null && (
          <Field label="Lat" value={stream.lat.toFixed(6)} />
        )}
        {stream.lon != null && (
          <Field label="Lon" value={stream.lon.toFixed(6)} />
        )}
      </div>
      <div
        style={{
          font: "400 11px/1.4 var(--font-mono)",
          color: "var(--color-text-dim)",
          wordBreak: "break-all",
          marginTop: 4,
        }}
      >
        {stream.url}
      </div>
    </div>
  );
}

// ── Delete Button ───────────────────────────────────────────────────────────

export function DeleteButton({
  uid,
  entityType,
  onDelete,
}: {
  uid: string;
  entityType: EntityType;
  onDelete: () => void;
}) {
  const handleDelete = useCallback(() => {
    const channel = getChannel();
    if (!channel) return;
    channel.push("delete_cop_event", { uid, type: entityType });
    onDelete();
  }, [uid, entityType, onDelete]);

  return (
    <Button
      variant="danger"
      size="sm"
      fullWidth
      onClick={handleDelete}
      style={{ marginTop: 8 }}
    >
      Delete {entityType}
    </Button>
  );
}
