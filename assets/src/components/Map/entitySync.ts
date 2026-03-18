import * as Cesium from "cesium";
import type { CotEvent, VideoStream, EmergencyAlert, GeofenceAlert } from "../../types";
import type { MapMarker, MapShape, MapRoute, MapGeofence } from "./types";
import type { TrackPoint } from "../../store";
import {
  getSaIcon,
  getPinIcon,
  getVideoIcon,
  affiliationFromType,
  type Affiliation,
} from "./icons";
import { getCallsign, hasActiveEmergency } from "../../utils/entityClassification";

// ── SA Position Sync ────────────────────────────────────────────────────────

export function syncPositions(
  viewer: Cesium.Viewer,
  positions: Map<string, CotEvent>,
  tracked: Set<string>
) {
  const currentUids = new Set<string>();

  for (const [uid, event] of positions) {
    if (!event.point) continue;
    currentUids.add(uid);
    upsertSaEntity(viewer, uid, event);
  }

  // Remove entities no longer in positions
  for (const uid of tracked) {
    if (!currentUids.has(uid)) {
      viewer.entities.removeById(uid);
    }
  }

  tracked.clear();
  for (const uid of currentUids) tracked.add(uid);
}

function upsertSaEntity(viewer: Cesium.Viewer, uid: string, event: CotEvent) {
  const lat = event.point!.lat;
  const lon = event.point!.lon;
  const position = Cesium.Cartesian3.fromDegrees(lon, lat);

  const callsign = getCallsign(event, uid);
  const group = event.detail?.group?.name || "Unknown";
  const speed = event.detail?.track?.speed || 0;
  const course = event.detail?.track?.course || 0;

  let affiliation: Affiliation;
  if (hasActiveEmergency(event.raw_detail)) {
    affiliation = "emergency";
  } else {
    affiliation = affiliationFromType(event.type);
  }

  const iconCanvas = getSaIcon(affiliation);

  const entity = viewer.entities.getById(uid);

  if (entity) {
    entity.position = new Cesium.ConstantPositionProperty(position);
    if (entity.label) {
      entity.label.text = new Cesium.ConstantProperty(callsign);
      entity.label.fillColor = new Cesium.ConstantProperty(Cesium.Color.WHITE);
    }
    if (entity.billboard) {
      entity.billboard.image = new Cesium.ConstantProperty(iconCanvas);
      const sz = affiliation === "emergency" ? 48 : 32;
      entity.billboard.width = new Cesium.ConstantProperty(sz);
      entity.billboard.height = new Cesium.ConstantProperty(sz);
    }
    if (entity.properties) {
      (entity.properties as any).speed = new Cesium.ConstantProperty(speed);
      (entity.properties as any).course = new Cesium.ConstantProperty(course);
      (entity.properties as any).affiliation = new Cesium.ConstantProperty(affiliation);
      (entity.properties as any).group = new Cesium.ConstantProperty(group);
    }
  } else {
    viewer.entities.add({
      id: uid,
      position: position,
      billboard: {
        image: iconCanvas as unknown as string,
        width: affiliation === "emergency" ? 48 : 32,
        height: affiliation === "emergency" ? 48 : 32,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: callsign,
        font: "bold 13px sans-serif",
        fillColor: Cesium.Color.WHITE,
        style: Cesium.LabelStyle.FILL,
        showBackground: true,
        backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
        backgroundPadding: new Cesium.Cartesian2(8, 4),
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        pixelOffset: new Cesium.Cartesian2(0, -20),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: {
        affiliation: affiliation,
        group: group,
        speed: speed,
        course: course,
      },
    });
  }
}

// ── Marker Sync (b-m-p-*) ──────────────────────────────────────────────────

export function syncMarkers(
  viewer: Cesium.Viewer,
  markers: Map<string, MapMarker>
) {
  const validIds = new Set<string>();
  for (const uid of markers.keys()) {
    validIds.add("marker-" + uid);
  }

  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (e.id.startsWith("marker-") && !validIds.has(e.id)) {
      toRemove.push(e.id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  for (const [, m] of markers) {
    upsertMarkerEntity(viewer, m);
  }
}

function upsertMarkerEntity(viewer: Cesium.Viewer, m: MapMarker) {
  const id = "marker-" + m.uid;
  const position = Cesium.Cartesian3.fromDegrees(m.lon, m.lat);
  const opacity = m.stale ? 0.4 : 1.0;
  const pinIcon = getPinIcon(m.stale);

  const entity = viewer.entities.getById(id);

  if (entity) {
    entity.position = new Cesium.ConstantPositionProperty(position);
    if (entity.label) {
      entity.label.text = new Cesium.ConstantProperty(m.callsign);
      entity.label.fillColor = new Cesium.ConstantProperty(
        Cesium.Color.WHITE.withAlpha(opacity)
      );
    }
    if (entity.billboard) {
      entity.billboard.image = new Cesium.ConstantProperty(pinIcon);
      entity.billboard.color = new Cesium.ConstantProperty(
        Cesium.Color.WHITE.withAlpha(opacity)
      );
    }
  } else {
    viewer.entities.add({
      id: id,
      position: position,
      billboard: {
        image: pinIcon as unknown as string,
        width: 18,
        height: 24,
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        color: Cesium.Color.WHITE.withAlpha(opacity),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: m.callsign,
        font: "bold 11px sans-serif",
        fillColor: Cesium.Color.WHITE.withAlpha(opacity),
        style: Cesium.LabelStyle.FILL,
        showBackground: true,
        backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
        backgroundPadding: new Cesium.Cartesian2(8, 4),
        verticalOrigin: Cesium.VerticalOrigin.TOP,
        pixelOffset: new Cesium.Cartesian2(0, 4),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: {
        entityType: "marker",
        remarks: m.remarks || "",
        stale: m.stale,
      },
    });
  }
}

// ── Video Feed Sync ─────────────────────────────────────────────────────────

export function syncVideoFeeds(
  viewer: Cesium.Viewer,
  videoStreams: Map<string, VideoStream>
) {
  const validIds = new Set<string>();
  for (const uid of videoStreams.keys()) {
    validIds.add("video-" + uid);
    validIds.add("video-fov-" + uid);
  }

  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (
      (e.id.startsWith("video-") || e.id.startsWith("video-fov-")) &&
      !validIds.has(e.id)
    ) {
      toRemove.push(e.id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  for (const [, stream] of videoStreams) {
    if (stream.lat != null && stream.lon != null) {
      upsertVideoEntity(viewer, stream);
    }
  }
}

function upsertVideoEntity(viewer: Cesium.Viewer, stream: VideoStream) {
  const id = "video-" + stream.uid;
  const fovId = "video-fov-" + stream.uid;
  const position = Cesium.Cartesian3.fromDegrees(stream.lon!, stream.lat!);
  const iconCanvas = getVideoIcon(true);

  const entity = viewer.entities.getById(id);

  if (entity) {
    entity.position = new Cesium.ConstantPositionProperty(position);
    if (entity.label) {
      entity.label.text = new Cesium.ConstantProperty(stream.alias);
    }
  } else {
    viewer.entities.add({
      id,
      position,
      billboard: {
        image: iconCanvas as unknown as string,
        width: 28,
        height: 28,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: stream.alias,
        font: "bold 11px sans-serif",
        fillColor: Cesium.Color.WHITE,
        style: Cesium.LabelStyle.FILL,
        showBackground: true,
        backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
        backgroundPadding: new Cesium.Cartesian2(8, 4),
        verticalOrigin: Cesium.VerticalOrigin.TOP,
        pixelOffset: new Cesium.Cartesian2(0, 4),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: {
        entityType: "video",
        protocol: stream.protocol,
        url: stream.url,
      },
    });
  }

  // Sensor FOV cone visualization
  const bearing = 0;
  const fovAngle = 90;
  const range = 200;
  const fovEntity = viewer.entities.getById(fovId);

  const conePositions = computeFovCone(
    stream.lat!,
    stream.lon!,
    bearing,
    fovAngle,
    range,
    16
  );

  if (fovEntity) {
    if (fovEntity.polygon) {
      fovEntity.polygon.hierarchy = new Cesium.ConstantProperty(
        new Cesium.PolygonHierarchy(conePositions)
      );
    }
  } else {
    viewer.entities.add({
      id: fovId,
      polygon: {
        hierarchy: new Cesium.PolygonHierarchy(conePositions),
        material: Cesium.Color.fromCssColorString("#AB47BC").withAlpha(0.15),
        outline: true,
        outlineColor: Cesium.Color.fromCssColorString("#AB47BC").withAlpha(0.5),
        outlineWidth: 1,
        height: 0,
      },
      properties: {
        entityType: "video-fov",
      },
    });
  }
}

/** Compute FOV cone polygon positions as an arc from a camera position */
function computeFovCone(
  lat: number,
  lon: number,
  bearing: number,
  fovAngle: number,
  range: number,
  segments: number
): Cesium.Cartesian3[] {
  const origin = Cesium.Cartesian3.fromDegrees(lon, lat);
  const positions: Cesium.Cartesian3[] = [origin];

  const startAngle = bearing - fovAngle / 2;
  const endAngle = bearing + fovAngle / 2;
  const step = (endAngle - startAngle) / segments;

  for (let i = 0; i <= segments; i++) {
    const angle = startAngle + step * i;
    const radAngle = Cesium.Math.toRadians(angle);
    const dx = range * Math.sin(radAngle);
    const dy = range * Math.cos(radAngle);
    const dLat = dy / 111320;
    const dLon = dx / (111320 * Math.cos(Cesium.Math.toRadians(lat)));
    positions.push(Cesium.Cartesian3.fromDegrees(lon + dLon, lat + dLat));
  }

  return positions;
}

// ── Shape Sync (u-d-*) ─────────────────────────────────────────────────────

export function syncShapes(
  viewer: Cesium.Viewer,
  shapes: Map<string, MapShape>
) {
  const validIds = new Set<string>();
  for (const uid of shapes.keys()) {
    validIds.add("shape-" + uid);
    validIds.add("shape-label-" + uid);
  }

  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (
      (e.id.startsWith("shape-") || e.id.startsWith("shape-label-")) &&
      !validIds.has(e.id)
    ) {
      toRemove.push(e.id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  for (const [, s] of shapes) {
    upsertShapeEntity(viewer, s);
  }
}

function upsertShapeEntity(viewer: Cesium.Viewer, s: MapShape) {
  const id = "shape-" + s.uid;
  const labelId = "shape-label-" + s.uid;
  const opacity = s.stale ? 0.4 : 1.0;
  const fillOpacity = s.stale ? 0.1 : 0.25;
  const strokeColor = s.stroke_color
    ? Cesium.Color.fromCssColorString(s.stroke_color).withAlpha(opacity)
    : Cesium.Color.CYAN.withAlpha(opacity);
  const fillColor = s.fill_color
    ? Cesium.Color.fromCssColorString(s.fill_color).withAlpha(fillOpacity)
    : Cesium.Color.CYAN.withAlpha(fillOpacity);

  // Remove existing for re-creation (shapes are complex)
  viewer.entities.removeById(id);
  viewer.entities.removeById(labelId);

  if (s.shape_type === "circle" && s.center && s.radius) {
    viewer.entities.add({
      id: id,
      position: Cesium.Cartesian3.fromDegrees(s.center.lon, s.center.lat),
      ellipse: {
        semiMajorAxis: s.radius,
        semiMinorAxis: s.radius,
        material: fillColor,
        outline: true,
        outlineColor: strokeColor,
        outlineWidth: 2,
      },
      properties: {
        entityType: "shape",
        shapeType: s.shape_type,
        name: s.name || "",
        remarks: s.remarks || "",
        vertexCount: 0,
        stale: s.stale,
      },
    });
  } else if (s.vertices && s.vertices.length >= 2) {
    const coords: number[] = [];
    s.vertices.forEach((v) => coords.push(v.lon, v.lat));

    if (s.vertices.length >= 3) {
      viewer.entities.add({
        id: id,
        polygon: {
          hierarchy: Cesium.Cartesian3.fromDegreesArray(coords),
          material: fillColor,
          outline: true,
          outlineColor: strokeColor,
          outlineWidth: 2,
        },
        properties: {
          entityType: "shape",
          shapeType: s.shape_type,
          name: s.name || "",
          remarks: s.remarks || "",
          vertexCount: s.vertices.length,
          stale: s.stale,
        },
      });
    } else {
      viewer.entities.add({
        id: id,
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(coords),
          material: strokeColor,
          width: 2,
        },
        properties: {
          entityType: "shape",
          shapeType: s.shape_type,
          name: s.name || "",
          remarks: s.remarks || "",
          vertexCount: s.vertices.length,
          stale: s.stale,
        },
      });
    }
  } else {
    return;
  }

  // Label at centroid
  if (s.name && s.center) {
    viewer.entities.add({
      id: labelId,
      position: Cesium.Cartesian3.fromDegrees(s.center.lon, s.center.lat),
      label: {
        text: s.name,
        font: "bold 11px sans-serif",
        fillColor: Cesium.Color.WHITE,
        style: Cesium.LabelStyle.FILL,
        showBackground: true,
        backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
        backgroundPadding: new Cesium.Cartesian2(8, 4),
        verticalOrigin: Cesium.VerticalOrigin.CENTER,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: { entityType: "shape-label" },
    });
  }
}

// ── Route Sync (b-m-r) ─────────────────────────────────────────────────────

export function syncRoutes(
  viewer: Cesium.Viewer,
  routes: Map<string, MapRoute>
) {
  const validPrefixes = new Set<string>();
  for (const uid of routes.keys()) {
    validPrefixes.add(uid);
  }

  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (e.id.startsWith("route-") || e.id.includes("_wp_")) {
      const baseUid = e.id.startsWith("route-label-")
        ? e.id.replace("route-label-", "")
        : e.id.startsWith("route-")
          ? e.id.replace("route-", "")
          : e.id.split("_wp_")[0];
      if (!validPrefixes.has(baseUid)) {
        toRemove.push(e.id);
      }
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  for (const [, r] of routes) {
    upsertRouteEntity(viewer, r);
  }
}

function upsertRouteEntity(viewer: Cesium.Viewer, r: MapRoute) {
  const id = "route-" + r.uid;
  const labelId = "route-label-" + r.uid;
  const opacity = r.stale ? 0.4 : 1.0;
  const strokeColor = r.stroke_color
    ? Cesium.Color.fromCssColorString(r.stroke_color).withAlpha(opacity)
    : Cesium.Color.CYAN.withAlpha(opacity);

  removeRouteEntities(viewer, r.uid);

  if (!r.waypoints || r.waypoints.length < 2) return;

  const flatCoords: number[] = [];
  r.waypoints.forEach((wp) => flatCoords.push(wp.lon, wp.lat));

  viewer.entities.add({
    id: id,
    polyline: {
      positions: Cesium.Cartesian3.fromDegreesArray(flatCoords),
      width: 3,
      material: strokeColor,
      clampToGround: true,
    },
    properties: {
      entityType: "route",
      name: r.name || "",
      remarks: r.remarks || "",
      waypointCount: r.waypoint_count || 0,
      totalDistanceM: r.total_distance_m || 0,
      stale: r.stale,
    },
  });

  const midIdx = Math.floor(r.waypoints.length / 2);
  const midWp = r.waypoints[midIdx];
  viewer.entities.add({
    id: labelId,
    position: Cesium.Cartesian3.fromDegrees(midWp.lon, midWp.lat),
    label: {
      text: r.name || "Route",
      font: "bold 11px sans-serif",
      fillColor: Cesium.Color.WHITE,
      style: Cesium.LabelStyle.FILL,
      showBackground: true,
      backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
      backgroundPadding: new Cesium.Cartesian2(8, 4),
      verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
      pixelOffset: new Cesium.Cartesian2(0, -10),
      disableDepthTestDistance: Number.POSITIVE_INFINITY,
    },
    properties: { entityType: "route-label" },
  });

  r.waypoints.forEach((wp, i) => {
    viewer.entities.add({
      id: r.uid + "_wp_" + i,
      position: Cesium.Cartesian3.fromDegrees(wp.lon, wp.lat),
      point: {
        pixelSize: 5,
        color: strokeColor,
        outlineColor: Cesium.Color.WHITE,
        outlineWidth: 1,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: { entityType: "route-wp" },
    });
  });
}

function removeRouteEntities(viewer: Cesium.Viewer, uid: string) {
  viewer.entities.removeById("route-" + uid);
  viewer.entities.removeById("route-label-" + uid);
  for (let i = 0; i < 100; i++) {
    if (!viewer.entities.removeById(uid + "_wp_" + i)) break;
  }
}

// ── Geofence Sync (u-d-* with __geofence) ──────────────────────────────────

export function syncGeofences(
  viewer: Cesium.Viewer,
  geofences: Map<string, MapGeofence>
) {
  const validIds = new Set<string>();
  for (const uid of geofences.keys()) {
    validIds.add("geofence-" + uid);
    validIds.add("geofence-label-" + uid);
  }

  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    const e = entities[i];
    if (
      (e.id.startsWith("geofence-") || e.id.startsWith("geofence-label-")) &&
      !validIds.has(e.id)
    ) {
      toRemove.push(e.id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  for (const [, g] of geofences) {
    upsertGeofenceEntity(viewer, g);
  }
}

export function upsertGeofenceEntity(viewer: Cesium.Viewer, g: MapGeofence) {
  const id = "geofence-" + g.uid;
  const labelId = "geofence-label-" + g.uid;
  const opacity = g.stale ? 0.4 : 1.0;
  const fillOpacity = g.stale ? 0.06 : 0.12;
  const strokeColor = g.stroke_color
    ? Cesium.Color.fromCssColorString(g.stroke_color).withAlpha(opacity)
    : Cesium.Color.fromCssColorString("#FF9800").withAlpha(opacity);
  const fillColor = g.fill_color
    ? Cesium.Color.fromCssColorString(g.fill_color).withAlpha(fillOpacity)
    : Cesium.Color.fromCssColorString("#FF9800").withAlpha(fillOpacity);

  viewer.entities.removeById(id);
  viewer.entities.removeById(labelId);

  const triggerLabel = g.trigger ? " [" + g.trigger + "]" : "";

  if (g.shape_type === "circle" && g.center && g.radius) {
    viewer.entities.add({
      id: id,
      position: Cesium.Cartesian3.fromDegrees(g.center.lon, g.center.lat),
      ellipse: {
        semiMajorAxis: g.radius,
        semiMinorAxis: g.radius,
        material: fillColor,
        outline: true,
        outlineColor: strokeColor,
        outlineWidth: 2,
      },
      properties: {
        entityType: "geofence",
        shapeType: g.shape_type,
        name: g.name || "",
        remarks: g.remarks || "",
        trigger: g.trigger || "",
        monitorType: g.monitor_type || "",
        boundaryType: g.boundary_type || "",
        vertexCount: 0,
        stale: g.stale,
      },
    });
  } else if (g.vertices && g.vertices.length >= 2) {
    const coords: number[] = [];
    g.vertices.forEach((v) => coords.push(v.lon, v.lat));

    const props = {
      entityType: "geofence",
      shapeType: g.shape_type,
      name: g.name || "",
      remarks: g.remarks || "",
      trigger: g.trigger || "",
      monitorType: g.monitor_type || "",
      boundaryType: g.boundary_type || "",
      vertexCount: g.vertices.length,
      stale: g.stale,
    };

    if (g.vertices.length >= 3) {
      viewer.entities.add({
        id: id,
        polygon: {
          hierarchy: Cesium.Cartesian3.fromDegreesArray(coords),
          material: fillColor,
          outline: true,
          outlineColor: strokeColor,
          outlineWidth: 2,
        },
        properties: props,
      });
    } else {
      viewer.entities.add({
        id: id,
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(coords),
          material: strokeColor,
          width: 2,
        },
        properties: props,
      });
    }
  } else {
    return;
  }

  if (g.center) {
    viewer.entities.add({
      id: labelId,
      position: Cesium.Cartesian3.fromDegrees(g.center.lon, g.center.lat),
      label: {
        text: (g.name || "Geofence") + triggerLabel,
        font: "bold 11px sans-serif",
        fillColor: Cesium.Color.WHITE,
        style: Cesium.LabelStyle.FILL,
        showBackground: true,
        backgroundColor: Cesium.Color.BLACK.withAlpha(0.6),
        backgroundPadding: new Cesium.Cartesian2(8, 4),
        verticalOrigin: Cesium.VerticalOrigin.CENTER,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: { entityType: "geofence-label" },
    });
  }
}

// ── Emergency Ring Sync (pixel-based, animated) ─────────────────────────────

const emergencyRingIds = new Set<string>();
const RING_CYCLE_MS = 2500;

let _staticRingImage: HTMLCanvasElement | null = null;
function getStaticRingImage(): HTMLCanvasElement {
  if (_staticRingImage) return _staticRingImage;
  const s = 128;
  const c = document.createElement("canvas");
  c.width = s;
  c.height = s;
  const ctx = c.getContext("2d")!;
  const mid = s / 2;

  const grad = ctx.createRadialGradient(mid, mid, 0, mid, mid, mid);
  grad.addColorStop(0, "rgba(255, 23, 68, 0.35)");
  grad.addColorStop(0.4, "rgba(255, 23, 68, 0.15)");
  grad.addColorStop(0.7, "rgba(255, 23, 68, 0.06)");
  grad.addColorStop(1, "rgba(255, 23, 68, 0)");
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, s, s);

  ctx.beginPath();
  ctx.arc(mid, mid, 40, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(255, 23, 68, 0.8)";
  ctx.lineWidth = 2.5;
  ctx.stroke();

  _staticRingImage = c;
  return c;
}

export function syncEmergencyRings(
  viewer: Cesium.Viewer,
  emergencies: Map<string, EmergencyAlert>
) {
  const wantedIds = new Set<string>();

  for (const [uid, alert] of emergencies) {
    if (alert.lat == null || alert.lon == null) continue;
    const id = "emergency-ring-" + uid;
    wantedIds.add(id);

    if (!viewer.entities.getById(id)) {
      const position = Cesium.Cartesian3.fromDegrees(alert.lon, alert.lat);

      viewer.entities.add({
        id: id,
        position: position,
        billboard: {
          image: getStaticRingImage() as unknown as string,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scale: new Cesium.CallbackProperty(() => {
            const t = (Date.now() % RING_CYCLE_MS) / RING_CYCLE_MS;
            return 0.6 + 0.6 * t;
          }, false),
          color: new Cesium.CallbackProperty(() => {
            const t = (Date.now() % RING_CYCLE_MS) / RING_CYCLE_MS;
            return Cesium.Color.WHITE.withAlpha(1.0 - t);
          }, false),
        },
        properties: { entityType: "emergency-ring" },
      });
      emergencyRingIds.add(id);
    }
  }

  for (const id of emergencyRingIds) {
    if (!wantedIds.has(id)) {
      viewer.entities.removeById(id);
      emergencyRingIds.delete(id);
    }
  }
}

// ── Geofence Alert Flash ────────────────────────────────────────────────────

const activeFlashes = new Set<string>();

export function flashGeofenceAlerts(
  viewer: Cesium.Viewer,
  alerts: GeofenceAlert[],
  geofences: Map<string, MapGeofence>
) {
  for (const alert of alerts) {
    if (!alert.geofence_ref) continue;
    const entityId = "geofence-" + alert.geofence_ref;
    if (activeFlashes.has(entityId)) continue;

    const entity = viewer.entities.getById(entityId);
    if (!entity) continue;

    activeFlashes.add(entityId);

    const origOutlineColor = entity.ellipse
      ? entity.ellipse.outlineColor?.getValue(Cesium.JulianDate.now())
      : entity.polygon
        ? entity.polygon.outlineColor?.getValue(Cesium.JulianDate.now())
        : null;

    const flashColor = Cesium.Color.fromCssColorString("#F44336");
    const flashFill = Cesium.Color.fromCssColorString("#F44336").withAlpha(0.3);

    let flashCount = 0;
    const maxFlashes = 6;
    const interval = setInterval(() => {
      if (viewer.isDestroyed()) {
        clearInterval(interval);
        activeFlashes.delete(entityId);
        return;
      }

      const isFlash = flashCount % 2 === 0;
      flashCount++;

      if (entity.ellipse) {
        entity.ellipse.outlineColor = new Cesium.ConstantProperty(
          isFlash ? flashColor : (origOutlineColor || flashColor)
        );
        if (isFlash) {
          entity.ellipse.material = new Cesium.ColorMaterialProperty(flashFill);
        }
      } else if (entity.polygon) {
        entity.polygon.outlineColor = new Cesium.ConstantProperty(
          isFlash ? flashColor : (origOutlineColor || flashColor)
        );
        if (isFlash) {
          entity.polygon.material = new Cesium.ColorMaterialProperty(flashFill);
        }
      }

      if (flashCount >= maxFlashes) {
        clearInterval(interval);
        activeFlashes.delete(entityId);
        const geoData = geofences.get(alert.geofence_ref!);
        if (geoData) {
          upsertGeofenceEntity(viewer, geoData);
        }
      }
    }, 500);
  }
}

// ── Track History Rendering ─────────────────────────────────────────────────

const renderedTrackIds = new Set<string>();

export function syncTracks(
  viewer: Cesium.Viewer,
  tracks: Map<string, TrackPoint[]>,
  visible: Set<string>
) {
  const wantedUids = new Set<string>();
  for (const uid of visible) {
    if (tracks.has(uid)) wantedUids.add(uid);
  }

  const toRemove: string[] = [];
  for (const id of renderedTrackIds) {
    const uid = id.startsWith("track-line-")
      ? id.replace("track-line-", "")
      : id.startsWith("track-dot-")
        ? id.slice("track-dot-".length, id.lastIndexOf("-"))
        : null;
    if (uid && !wantedUids.has(uid)) {
      toRemove.push(id);
    }
  }
  toRemove.forEach((id) => {
    viewer.entities.removeById(id);
    renderedTrackIds.delete(id);
  });

  for (const uid of wantedUids) {
    const points = tracks.get(uid)!;
    renderTrack(viewer, uid, points);
  }
}

function renderTrack(
  viewer: Cesium.Viewer,
  uid: string,
  points: TrackPoint[]
) {
  const lineId = "track-line-" + uid;

  viewer.entities.removeById(lineId);
  renderedTrackIds.delete(lineId);

  const dotPrefix = "track-dot-" + uid + "-";
  const entities = viewer.entities.values;
  for (let i = entities.length - 1; i >= 0; i--) {
    if (entities[i].id.startsWith(dotPrefix)) {
      const id = entities[i].id;
      viewer.entities.removeById(id);
      renderedTrackIds.delete(id);
    }
  }

  if (points.length < 2) return;

  const coords: number[] = [];
  for (const p of points) {
    coords.push(p.lon, p.lat);
  }

  viewer.entities.add({
    id: lineId,
    polyline: {
      positions: Cesium.Cartesian3.fromDegreesArray(coords),
      width: 3,
      material: new Cesium.PolylineGlowMaterialProperty({
        glowPower: 0.15,
        color: Cesium.Color.fromCssColorString("#00bcd4").withAlpha(0.8),
      }),
      clampToGround: true,
    },
    properties: { entityType: "track" },
  });
  renderedTrackIds.add(lineId);

  const maxDots = 60;
  const step = Math.max(1, Math.floor(points.length / maxDots));
  for (let i = 0; i < points.length; i += step) {
    const p = points[i];
    const dotId = dotPrefix + i;
    viewer.entities.add({
      id: dotId,
      position: Cesium.Cartesian3.fromDegrees(p.lon, p.lat),
      point: {
        pixelSize: 3,
        color: Cesium.Color.fromCssColorString("#00bcd4").withAlpha(0.6),
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 1,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      properties: { entityType: "track-dot" },
    });
    renderedTrackIds.add(dotId);
  }
}
