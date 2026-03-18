import * as Cesium from "cesium";
import { useDashboardStore, type LayerState } from "../../store";
import { classifyEntityToLayer } from "../../utils/entityClassification";

/** Apply layer visibility, opacity, group filtering, and solo mode to all entities */
export function applyLayerFilters(viewer: Cesium.Viewer, layerState: LayerState) {
  const positions = useDashboardStore.getState().positions;
  const entities = viewer.entities.values;

  for (let i = 0; i < entities.length; i++) {
    const entity = entities[i];
    const layerKey = classifyEntityToLayer(entity.id, positions);
    if (!layerKey) continue;

    const conf = layerState.types[layerKey];
    if (!conf) continue;

    let show = conf.visible;

    // Group filter (SA entities only)
    if (show && layerKey.startsWith("sa-") && !layerState.allGroups) {
      const hasSelectedGroups = Object.keys(layerState.groups).length > 0;
      if (hasSelectedGroups) {
        const group = entity.properties?.group?.getValue
          ? entity.properties.group.getValue(Cesium.JulianDate.now())
          : null;
        show = !!group && !!layerState.groups[group];
      } else {
        show = false;
      }
    }

    // Solo mode override
    if (layerState.soloLayer && layerKey !== layerState.soloLayer) {
      show = false;
    }

    entity.show = show;

    if (show && conf.opacity < 1.0) {
      applyOpacity(entity, conf.opacity);
    }
  }
}

/** Adjust entity visual opacity */
function applyOpacity(entity: Cesium.Entity, opacity: number) {
  // Billboard entities (SA, markers)
  if (entity.billboard) {
    const orig = entity.billboard.color?.getValue(Cesium.JulianDate.now());
    if (orig) {
      entity.billboard.color = new Cesium.ConstantProperty(orig.withAlpha(opacity));
    } else {
      entity.billboard.color = new Cesium.ConstantProperty(
        Cesium.Color.WHITE.withAlpha(opacity)
      );
    }
  }

  // Point entities (route waypoints, track dots)
  if (entity.point) {
    const orig = entity.point.color?.getValue(Cesium.JulianDate.now());
    if (orig) {
      entity.point.color = new Cesium.ConstantProperty(orig.withAlpha(opacity));
    }
  }

  // Label entities
  if (entity.label) {
    const orig = entity.label.fillColor?.getValue(Cesium.JulianDate.now());
    if (orig) {
      entity.label.fillColor = new Cesium.ConstantProperty(orig.withAlpha(opacity));
    }
  }

  // Polygon entities (shapes, geofences)
  if (entity.polygon) {
    const mat = entity.polygon.material as any;
    if (mat?.color) {
      const c = mat.color.getValue?.(Cesium.JulianDate.now());
      if (c) entity.polygon.material = new Cesium.ColorMaterialProperty(c.withAlpha(c.alpha * opacity));
    }
    const oc = entity.polygon.outlineColor?.getValue(Cesium.JulianDate.now());
    if (oc) entity.polygon.outlineColor = new Cesium.ConstantProperty(oc.withAlpha(opacity));
  }

  // Ellipse entities (circle shapes/geofences)
  if (entity.ellipse) {
    const mat = entity.ellipse.material as any;
    if (mat?.color) {
      const c = mat.color.getValue?.(Cesium.JulianDate.now());
      if (c) entity.ellipse.material = new Cesium.ColorMaterialProperty(c.withAlpha(c.alpha * opacity));
    }
    const oc = entity.ellipse.outlineColor?.getValue(Cesium.JulianDate.now());
    if (oc) entity.ellipse.outlineColor = new Cesium.ConstantProperty(oc.withAlpha(opacity));
  }

  // Polyline entities (routes, tracks)
  if (entity.polyline) {
    const mat = entity.polyline.material as any;
    if (mat?.color) {
      const c = mat.color.getValue?.(Cesium.JulianDate.now());
      if (c) entity.polyline.material = new Cesium.ColorMaterialProperty(c.withAlpha(opacity));
    }
  }
}
