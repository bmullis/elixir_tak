import type { EntityType, LayerKey } from "../store";
import type { CotEvent } from "../types";

/**
 * Extract callsign from a CotEvent's detail, with a fallback.
 */
export function getCallsign(event: CotEvent, fallback: string): string {
  const d = event.detail;
  if (!d) return fallback;
  if (d.contact?.callsign) return d.contact.callsign;
  if (typeof d.callsign === "string" && d.callsign) return d.callsign;
  return fallback;
}

/**
 * Classify a Cesium entity ID into a uid + entityType pair.
 * Returns null for sub-entities (labels, waypoints, rings) that aren't selectable.
 */
export function classifyEntity(
  cesiumId: string
): { uid: string; entityType: EntityType } | null {
  // Skip label/waypoint/ring sub-entities
  if (cesiumId.startsWith("shape-label-")) return null;
  if (cesiumId.startsWith("route-label-")) return null;
  if (cesiumId.startsWith("geofence-label-")) return null;
  if (cesiumId.startsWith("emergency-ring-")) return null;
  if (cesiumId.includes("_wp_")) return null;

  if (cesiumId.startsWith("marker-")) {
    return { uid: cesiumId.replace("marker-", ""), entityType: "marker" };
  }
  if (cesiumId.startsWith("shape-")) {
    return { uid: cesiumId.replace("shape-", ""), entityType: "shape" };
  }
  if (cesiumId.startsWith("route-")) {
    return { uid: cesiumId.replace("route-", ""), entityType: "route" };
  }
  if (cesiumId.startsWith("geofence-")) {
    return { uid: cesiumId.replace("geofence-", ""), entityType: "geofence" };
  }
  // Video entities
  if (cesiumId.startsWith("video-fov-")) return null; // FOV cone not selectable
  if (cesiumId.startsWith("video-")) {
    return { uid: cesiumId.replace("video-", ""), entityType: "video" };
  }
  // Track entities are not selectable
  if (cesiumId.startsWith("track-")) return null;

  // No prefix = SA entity (uid directly)
  return { uid: cesiumId, entityType: "sa" };
}

/**
 * Derive affiliation from CoT type string (pure reimplementation for utility use).
 */
export type Affiliation = "friendly" | "hostile" | "neutral" | "unknown";

export function affiliationFromType(type: string): Affiliation {
  if (type.startsWith("a-f-")) return "friendly";
  if (type.startsWith("a-h-")) return "hostile";
  if (type.startsWith("a-n-")) return "neutral";
  if (type.startsWith("a-u-")) return "unknown";
  return "unknown";
}

/**
 * Check if a CotEvent has an active (non-cancelled) emergency in its raw_detail.
 */
export function hasActiveEmergency(rawDetail: string | null): boolean {
  if (!rawDetail) return false;
  return /<emergency[\s>]/.test(rawDetail) && !rawDetail.includes('cancel="true"');
}

/**
 * Classify a Cesium entity ID to a LayerKey for filter purposes.
 * SA entities need the positions map to determine affiliation.
 */
export function classifyEntityToLayer(
  entityId: string,
  positions: Map<string, CotEvent>
): LayerKey | null {
  if (entityId.startsWith("emergency-ring-")) return "emergency";
  if (entityId.startsWith("track-line-") || entityId.startsWith("track-dot-"))
    return "track";
  if (entityId.startsWith("geofence-") || entityId.startsWith("geofence-label-"))
    return "geofence";
  if (entityId.startsWith("route-") || entityId.startsWith("route-label-") || entityId.includes("_wp_"))
    return "route";
  if (entityId.startsWith("shape-") || entityId.startsWith("shape-label-"))
    return "shape";
  if (entityId.startsWith("marker-"))
    return "marker";
  if (entityId.startsWith("video-") || entityId.startsWith("video-fov-"))
    return "video";

  // SA entities (no prefix, uid directly)
  const saEvent = positions.get(entityId);
  if (saEvent) {
    if (hasActiveEmergency(saEvent.raw_detail)) {
      return "emergency";
    }
    const aff = affiliationFromType(saEvent.type);
    switch (aff) {
      case "friendly":
        return "sa-friendly";
      case "hostile":
        return "sa-hostile";
      case "neutral":
        return "sa-neutral";
      default:
        return "sa-unknown";
    }
  }

  return null;
}
