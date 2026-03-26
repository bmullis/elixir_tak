import * as Cesium from "cesium";
import type { MeasurementState, MeasurementResult, MeasureUnit } from "../../store";
import { useDashboardStore } from "../../store";
import type { Vertex } from "./types";

const MEASURE_PREFIX = "measure-";
const ACTIVE_PREFIX = "measure-active-";

// ── Geodesic Math ───────────────────────────────────────────────────────────

const EARTH_RADIUS = 6_371_008.8; // meters (mean radius)

/** Haversine distance between two points in meters */
export function haversineDistance(a: Vertex, b: Vertex): number {
  const toRad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * toRad;
  const dLon = (b.lon - a.lon) * toRad;
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const h =
    sinLat * sinLat +
    Math.cos(a.lat * toRad) * Math.cos(b.lat * toRad) * sinLon * sinLon;
  return 2 * EARTH_RADIUS * Math.asin(Math.sqrt(h));
}

/** Total path distance across an array of vertices */
export function pathDistance(vertices: Vertex[]): { total: number; segments: number[] } {
  const segments: number[] = [];
  let total = 0;
  for (let i = 1; i < vertices.length; i++) {
    const d = haversineDistance(vertices[i - 1], vertices[i]);
    segments.push(d);
    total += d;
  }
  return { total, segments };
}

/** Geodesic polygon area using the spherical trapezoidal rule (square meters) */
export function polygonArea(vertices: Vertex[]): number {
  if (vertices.length < 3) return 0;
  const toRad = Math.PI / 180;
  let sum = 0;
  const n = vertices.length;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    sum +=
      (vertices[j].lon - vertices[i].lon) * toRad *
      (2 + Math.sin(vertices[i].lat * toRad) + Math.sin(vertices[j].lat * toRad));
  }
  return Math.abs(sum * EARTH_RADIUS * EARTH_RADIUS) / 2;
}

// ── Unit Formatting ─────────────────────────────────────────────────────────

const M_TO_FT = 3.28084;
const M_TO_NM = 0.000539957;
const M_TO_MI = 0.000621371;
const SQM_TO_SQFT = 10.7639;
const SQM_TO_ACRES = 0.000247105;
const SQM_TO_SQMI = 3.861e-7;
const SQM_TO_SQNM = 2.916e-7;

export function formatDistance(meters: number, unit: MeasureUnit): string {
  switch (unit) {
    case "metric":
      return meters >= 1000
        ? `${(meters / 1000).toFixed(2)} km`
        : `${meters.toFixed(1)} m`;
    case "imperial": {
      const ft = meters * M_TO_FT;
      const mi = meters * M_TO_MI;
      return mi >= 0.1 ? `${mi.toFixed(2)} mi` : `${ft.toFixed(0)} ft`;
    }
    case "nautical": {
      const nm = meters * M_TO_NM;
      return nm >= 0.1
        ? `${nm.toFixed(2)} NM`
        : `${meters.toFixed(1)} m`;
    }
  }
}

export function formatArea(sqMeters: number, unit: MeasureUnit): string {
  switch (unit) {
    case "metric":
      return sqMeters >= 1_000_000
        ? `${(sqMeters / 1_000_000).toFixed(2)} km\u00B2`
        : `${sqMeters.toFixed(0)} m\u00B2`;
    case "imperial": {
      const sqMi = sqMeters * SQM_TO_SQMI;
      const acres = sqMeters * SQM_TO_ACRES;
      const sqFt = sqMeters * SQM_TO_SQFT;
      if (sqMi >= 1) return `${sqMi.toFixed(2)} mi\u00B2`;
      if (acres >= 1) return `${acres.toFixed(1)} acres`;
      return `${sqFt.toFixed(0)} ft\u00B2`;
    }
    case "nautical": {
      const sqNm = sqMeters * SQM_TO_SQNM;
      return sqNm >= 0.01
        ? `${sqNm.toFixed(3)} NM\u00B2`
        : `${sqMeters.toFixed(0)} m\u00B2`;
    }
  }
}

/** Format a measurement result as a copyable string */
export function formatResult(result: MeasurementResult, unit: MeasureUnit): string {
  if (result.mode === "area") {
    return formatArea(result.value, unit);
  }
  return formatDistance(result.value, unit);
}

// ── Click Handling ──────────────────────────────────────────────────────────

export function handleMeasurementClick(
  store: ReturnType<typeof useDashboardStore.getState>,
  measurement: MeasurementState,
  lat: number,
  lon: number
) {
  const vertex = { lat, lon };

  switch (measurement.mode) {
    case "distance": {
      // Two-point distance: first click sets start, second completes
      if (measurement.vertices.length === 0) {
        store.addMeasureVertex(vertex);
      } else {
        store.addMeasureVertex(vertex);
        // Complete immediately
        const allVerts = [...measurement.vertices, vertex];
        const dist = haversineDistance(allVerts[0], allVerts[1]);
        store.completeMeasurement({
          id: crypto.randomUUID(),
          mode: "distance",
          vertices: allVerts,
          value: dist,
          segments: [dist],
        });
      }
      break;
    }

    case "path": {
      // Multi-point path: accumulate vertices, user confirms to complete
      store.addMeasureVertex(vertex);
      break;
    }

    case "area": {
      // Polygon area: accumulate vertices, user confirms to complete
      store.addMeasureVertex(vertex);
      break;
    }
  }
}

// ── Cesium Entity Sync ──────────────────────────────────────────────────────

const MEASURE_COLOR = Cesium.Color.fromCssColorString("#fbbf24"); // amber
const MEASURE_COLOR_DIM = MEASURE_COLOR.withAlpha(0.15);

/** Remove all entities with a given prefix */
function removeByPrefix(viewer: Cesium.Viewer, prefix: string) {
  const toRemove: string[] = [];
  const entities = viewer.entities.values;
  for (let i = 0; i < entities.length; i++) {
    if (entities[i].id.startsWith(prefix)) {
      toRemove.push(entities[i].id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));
}

/** Sync the active (in-progress) measurement preview */
export function syncActiveMeasurement(viewer: Cesium.Viewer, measurement: MeasurementState) {
  removeByPrefix(viewer, ACTIVE_PREFIX);

  if (!measurement.mode || measurement.vertices.length === 0) return;

  const unit = measurement.unit;

  // Build vertex list including cursor for rubber-band
  const verts = [...measurement.vertices];
  if (measurement.cursorPosition) {
    verts.push(measurement.cursorPosition);
  }

  // Draw dots at each vertex
  measurement.vertices.forEach((v, i) => {
    viewer.entities.add({
      id: ACTIVE_PREFIX + "dot-" + i,
      position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
      point: {
        pixelSize: 7,
        color: MEASURE_COLOR,
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 1,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  });

  if (measurement.mode === "distance" || measurement.mode === "path") {
    // Draw polyline including cursor position
    if (verts.length >= 2) {
      const coords = verts.flatMap((v) => [v.lon, v.lat]);
      viewer.entities.add({
        id: ACTIVE_PREFIX + "line",
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(coords),
          width: 2,
          material: new Cesium.PolylineDashMaterialProperty({
            color: MEASURE_COLOR,
            dashLength: 12,
          }),
          clampToGround: true,
        },
      });

      // Show running distance label at the last point
      const lastV = verts[verts.length - 1];
      const { total } = pathDistance(verts);
      viewer.entities.add({
        id: ACTIVE_PREFIX + "label",
        position: Cesium.Cartesian3.fromDegrees(lastV.lon, lastV.lat),
        label: {
          text: formatDistance(total, unit),
          font: "bold 12px sans-serif",
          fillColor: MEASURE_COLOR,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          showBackground: true,
          backgroundColor: Cesium.Color.BLACK.withAlpha(0.7),
          backgroundPadding: new Cesium.Cartesian2(8, 4),
          pixelOffset: new Cesium.Cartesian2(0, -16),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });

      // Per-segment midpoint labels for path mode with 2+ segments
      if (measurement.mode === "path" && measurement.vertices.length >= 2) {
        for (let i = 1; i < measurement.vertices.length; i++) {
          const a = measurement.vertices[i - 1];
          const b = measurement.vertices[i];
          const d = haversineDistance(a, b);
          const midLat = (a.lat + b.lat) / 2;
          const midLon = (a.lon + b.lon) / 2;
          viewer.entities.add({
            id: ACTIVE_PREFIX + "seg-" + i,
            position: Cesium.Cartesian3.fromDegrees(midLon, midLat),
            label: {
              text: formatDistance(d, unit),
              font: "11px sans-serif",
              fillColor: Cesium.Color.WHITE.withAlpha(0.8),
              style: Cesium.LabelStyle.FILL_AND_OUTLINE,
              outlineColor: Cesium.Color.BLACK,
              outlineWidth: 2,
              showBackground: true,
              backgroundColor: Cesium.Color.BLACK.withAlpha(0.5),
              backgroundPadding: new Cesium.Cartesian2(6, 3),
              pixelOffset: new Cesium.Cartesian2(0, 10),
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scale: 0.9,
            },
          });
        }
      }
    }
  }

  if (measurement.mode === "area") {
    // Draw polygon outline + fill
    if (verts.length >= 2) {
      const closedCoords = verts.flatMap((v) => [v.lon, v.lat]);
      // Closing line
      viewer.entities.add({
        id: ACTIVE_PREFIX + "outline",
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray([
            ...closedCoords,
            verts[0].lon,
            verts[0].lat,
          ]),
          width: 2,
          material: new Cesium.PolylineDashMaterialProperty({
            color: MEASURE_COLOR,
            dashLength: 12,
          }),
          clampToGround: true,
        },
      });
    }

    if (verts.length >= 3) {
      viewer.entities.add({
        id: ACTIVE_PREFIX + "polygon",
        polygon: {
          hierarchy: Cesium.Cartesian3.fromDegreesArray(
            verts.flatMap((v) => [v.lon, v.lat])
          ),
          material: MEASURE_COLOR_DIM,
          outline: false,
        },
      });

      // Area label at centroid
      const centroid = getCentroid(verts);
      const area = polygonArea(verts);
      viewer.entities.add({
        id: ACTIVE_PREFIX + "area-label",
        position: Cesium.Cartesian3.fromDegrees(centroid.lon, centroid.lat),
        label: {
          text: formatArea(area, unit),
          font: "bold 12px sans-serif",
          fillColor: MEASURE_COLOR,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          showBackground: true,
          backgroundColor: Cesium.Color.BLACK.withAlpha(0.7),
          backgroundPadding: new Cesium.Cartesian2(8, 4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });
    }
  }
}

/** Sync completed measurement results as persistent entities */
export function syncCompletedMeasurements(viewer: Cesium.Viewer, results: MeasurementResult[], unit: MeasureUnit) {
  removeByPrefix(viewer, MEASURE_PREFIX + "r-");

  results.forEach((result) => {
    const prefix = MEASURE_PREFIX + "r-" + result.id + "-";
    const color = MEASURE_COLOR.withAlpha(0.7);
    const fillColor = MEASURE_COLOR_DIM;

    // Dots
    result.vertices.forEach((v, vi) => {
      viewer.entities.add({
        id: prefix + "dot-" + vi,
        position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
        point: {
          pixelSize: 5,
          color,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 1,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });
    });

    if (result.mode === "distance" || result.mode === "path") {
      // Line
      if (result.vertices.length >= 2) {
        viewer.entities.add({
          id: prefix + "line",
          polyline: {
            positions: Cesium.Cartesian3.fromDegreesArray(
              result.vertices.flatMap((v) => [v.lon, v.lat])
            ),
            width: 2,
            material: color,
            clampToGround: true,
          },
        });

        // Label at midpoint of full line
        const midIdx = Math.floor(result.vertices.length / 2);
        const midV = result.vertices.length % 2 === 0
          ? {
              lat: (result.vertices[midIdx - 1].lat + result.vertices[midIdx].lat) / 2,
              lon: (result.vertices[midIdx - 1].lon + result.vertices[midIdx].lon) / 2,
            }
          : result.vertices[midIdx];
        viewer.entities.add({
          id: prefix + "label",
          position: Cesium.Cartesian3.fromDegrees(midV.lon, midV.lat),
          label: {
            text: formatDistance(result.value, unit),
            font: "bold 11px sans-serif",
            fillColor: MEASURE_COLOR,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            showBackground: true,
            backgroundColor: Cesium.Color.BLACK.withAlpha(0.7),
            backgroundPadding: new Cesium.Cartesian2(8, 4),
            pixelOffset: new Cesium.Cartesian2(0, -12),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        });
      }
    }

    if (result.mode === "area" && result.vertices.length >= 3) {
      // Filled polygon
      viewer.entities.add({
        id: prefix + "polygon",
        polygon: {
          hierarchy: Cesium.Cartesian3.fromDegreesArray(
            result.vertices.flatMap((v) => [v.lon, v.lat])
          ),
          material: fillColor,
          outline: true,
          outlineColor: color,
          outlineWidth: 2,
        },
      });

      // Area label
      const centroid = getCentroid(result.vertices);
      viewer.entities.add({
        id: prefix + "label",
        position: Cesium.Cartesian3.fromDegrees(centroid.lon, centroid.lat),
        label: {
          text: formatArea(result.value, unit),
          font: "bold 11px sans-serif",
          fillColor: MEASURE_COLOR,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          showBackground: true,
          backgroundColor: Cesium.Color.BLACK.withAlpha(0.7),
          backgroundPadding: new Cesium.Cartesian2(8, 4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      });
    }
  });
}

/** Simple centroid of a polygon's vertices */
function getCentroid(vertices: Vertex[]): Vertex {
  let lat = 0;
  let lon = 0;
  for (const v of vertices) {
    lat += v.lat;
    lon += v.lon;
  }
  return { lat: lat / vertices.length, lon: lon / vertices.length };
}
