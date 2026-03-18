import * as Cesium from "cesium";
import { useDashboardStore, type DrawingState } from "../../store";
import { getPinIcon } from "./icons";

const PREVIEW_PREFIX = "drawing-preview-";

/** Handle a map click during drawing mode */
export function handleDrawingClick(
  store: ReturnType<typeof useDashboardStore.getState>,
  drawing: DrawingState,
  lat: number,
  lon: number
) {
  const vertex = { lat, lon };

  switch (drawing.mode) {
    case "marker":
      store.addDrawingVertex(vertex);
      break;

    case "polygon":
    case "route":
      store.addDrawingVertex(vertex);
      break;

    case "rectangle":
      if (drawing.vertices.length === 0) {
        store.addDrawingVertex(vertex);
      } else if (drawing.vertices.length === 1) {
        store.addDrawingVertex(vertex);
      }
      break;

    case "circle":
      if (!drawing.center) {
        store.setDrawingCenter(vertex);
        store.addDrawingVertex(vertex);
      } else {
        const centerCart = Cesium.Cartesian3.fromDegrees(drawing.center.lon, drawing.center.lat);
        const edgeCart = Cesium.Cartesian3.fromDegrees(lon, lat);
        const radius = Cesium.Cartesian3.distance(centerCart, edgeCart);
        store.setDrawingRadius(radius);
        store.addDrawingVertex(vertex);
      }
      break;
  }
}

/** Sync drawing preview entities onto the Cesium viewer */
export function syncDrawingPreview(viewer: Cesium.Viewer, drawing: DrawingState) {
  // Remove all previous preview entities
  const entities = viewer.entities.values;
  const toRemove: string[] = [];
  for (let i = 0; i < entities.length; i++) {
    if (entities[i].id.startsWith(PREVIEW_PREFIX)) {
      toRemove.push(entities[i].id);
    }
  }
  toRemove.forEach((id) => viewer.entities.removeById(id));

  if (!drawing.mode || drawing.vertices.length === 0) return;

  const color = Cesium.Color.fromCssColorString(drawing.color).withAlpha(0.9);
  const fillColor = Cesium.Color.fromCssColorString(drawing.color).withAlpha(0.2);

  switch (drawing.mode) {
    case "marker": {
      const v = drawing.vertices[0];
      viewer.entities.add({
        id: PREVIEW_PREFIX + "marker",
        position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
        billboard: {
          image: getPinIcon(false) as unknown as string,
          width: 18,
          height: 24,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          color: Cesium.Color.WHITE.withAlpha(0.8),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: drawing.name || "Marker",
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
      });
      break;
    }

    case "polygon": {
      drawing.vertices.forEach((v, i) => {
        viewer.entities.add({
          id: PREVIEW_PREFIX + "dot-" + i,
          position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
          point: {
            pixelSize: 6,
            color: color,
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 1,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        });
      });

      if (drawing.vertices.length >= 2) {
        const coords: number[] = [];
        drawing.vertices.forEach((v) => coords.push(v.lon, v.lat));

        if (drawing.vertices.length >= 3) {
          coords.push(drawing.vertices[0].lon, drawing.vertices[0].lat);
          viewer.entities.add({
            id: PREVIEW_PREFIX + "polygon",
            polygon: {
              hierarchy: Cesium.Cartesian3.fromDegreesArray(
                drawing.vertices.flatMap((v) => [v.lon, v.lat])
              ),
              material: fillColor,
              outline: true,
              outlineColor: color,
              outlineWidth: 2,
            },
          });
        }

        viewer.entities.add({
          id: PREVIEW_PREFIX + "outline",
          polyline: {
            positions: Cesium.Cartesian3.fromDegreesArray(coords),
            width: 2,
            material: color,
          },
        });
      }
      break;
    }

    case "rectangle": {
      drawing.vertices.forEach((v, i) => {
        viewer.entities.add({
          id: PREVIEW_PREFIX + "dot-" + i,
          position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
          point: {
            pixelSize: 6,
            color: color,
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 1,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        });
      });

      if (drawing.vertices.length === 2) {
        const [a, b] = drawing.vertices;
        const corners = [
          { lon: a.lon, lat: a.lat },
          { lon: b.lon, lat: a.lat },
          { lon: b.lon, lat: b.lat },
          { lon: a.lon, lat: b.lat },
        ];
        const coords = corners.flatMap((c) => [c.lon, c.lat]);
        viewer.entities.add({
          id: PREVIEW_PREFIX + "rect",
          polygon: {
            hierarchy: Cesium.Cartesian3.fromDegreesArray(coords),
            material: fillColor,
            outline: true,
            outlineColor: color,
            outlineWidth: 2,
          },
        });
      }
      break;
    }

    case "circle": {
      if (drawing.center) {
        viewer.entities.add({
          id: PREVIEW_PREFIX + "center",
          position: Cesium.Cartesian3.fromDegrees(drawing.center.lon, drawing.center.lat),
          point: {
            pixelSize: 6,
            color: color,
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 1,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        });

        if (drawing.radius && drawing.radius > 0) {
          viewer.entities.add({
            id: PREVIEW_PREFIX + "circle",
            position: Cesium.Cartesian3.fromDegrees(drawing.center.lon, drawing.center.lat),
            ellipse: {
              semiMajorAxis: drawing.radius,
              semiMinorAxis: drawing.radius,
              material: fillColor,
              outline: true,
              outlineColor: color,
              outlineWidth: 2,
            },
          });
        }
      }
      break;
    }

    case "route": {
      drawing.vertices.forEach((v, i) => {
        viewer.entities.add({
          id: PREVIEW_PREFIX + "dot-" + i,
          position: Cesium.Cartesian3.fromDegrees(v.lon, v.lat),
          point: {
            pixelSize: 6,
            color: color,
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 1,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        });
      });

      if (drawing.vertices.length >= 2) {
        const coords = drawing.vertices.flatMap((v) => [v.lon, v.lat]);
        viewer.entities.add({
          id: PREVIEW_PREFIX + "route",
          polyline: {
            positions: Cesium.Cartesian3.fromDegreesArray(coords),
            width: 3,
            material: color,
            clampToGround: true,
          },
        });
      }
      break;
    }
  }
}
