import type { EntityType } from "../store";

/** Parse __video element from raw_detail XML */
export function parseEmbeddedVideo(
  rawDetail: string | null
): { url: string; protocol: string } | null {
  if (!rawDetail) return null;
  const match = rawDetail.match(/<__video\s([^>]*)\/?>/);
  if (!match) return null;
  const attrs = match[1];
  const urlMatch = attrs.match(/url="([^"]*)"/);
  const protocolMatch = attrs.match(/protocol="([^"]*)"/);
  if (!urlMatch) return null;
  return {
    url: urlMatch[1],
    protocol: protocolMatch?.[1] ?? "unknown",
  };
}

export function entityTypeLabel(t: EntityType): string {
  switch (t) {
    case "sa":
      return "Situational Awareness";
    case "marker":
      return "Marker";
    case "shape":
      return "Shape / Drawing";
    case "route":
      return "Route";
    case "geofence":
      return "Geofence";
    case "video":
      return "Video Feed";
  }
}

export function formatTime(
  iso: string | null,
  opts?: Intl.DateTimeFormatOptions
): string {
  if (!iso) return "-";
  try {
    return new Date(iso).toLocaleTimeString(undefined, opts);
  } catch {
    return iso;
  }
}

export function formatDuration(isoString: string | null): string {
  if (!isoString) return "-";
  const connectedAt = new Date(isoString).getTime();
  const elapsed = Math.floor((Date.now() - connectedAt) / 1000);
  if (elapsed < 0) return "-";
  const h = Math.floor(elapsed / 3600);
  const m = Math.floor((elapsed % 3600) / 60);
  const s = elapsed % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

export function formatCoords(
  lat: number | null | undefined,
  lon: number | null | undefined
): string {
  if (lat == null || lon == null) return "-";
  return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
}

export function formatSpeed(speed: number | null | undefined): string {
  if (speed == null) return "-";
  return `${speed.toFixed(1)} m/s`;
}

export function formatTimeDelta(
  first: string | undefined,
  last: string | undefined
): string {
  if (!first || !last) return "";
  const ms = Math.abs(
    new Date(last).getTime() - new Date(first).getTime()
  );
  const mins = Math.floor(ms / 60_000);
  if (mins < 60) return `${mins}m span`;
  const hrs = Math.floor(mins / 60);
  const rem = mins % 60;
  return `${hrs}h ${rem}m span`;
}
