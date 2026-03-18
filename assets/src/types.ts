/** Point coordinates from CoT events */
export interface Point {
  lat: number;
  lon: number;
  hae: number | null;
  ce: number | null;
  le: number | null;
}

/** Contact detail extracted from CoT */
export interface ContactDetail {
  callsign?: string;
  endpoint?: string;
}

/** Group detail extracted from CoT */
export interface GroupDetail {
  name?: string;
  role?: string;
}

/** Track detail extracted from CoT */
export interface TrackDetail {
  course?: number;
  speed?: number;
}

/** Structured detail fields parsed by the server */
export interface EventDetail {
  contact?: ContactDetail;
  group?: GroupDetail;
  track?: TrackDetail;
  [key: string]: unknown;
}

/** Serialized CoT event from the channel */
export interface CotEvent {
  uid: string;
  type: string;
  how: string | null;
  time: string | null;
  start: string | null;
  stale: string | null;
  point: Point | null;
  detail: EventDetail | null;
  raw_detail: string | null;
  group: string | null;
}

/** Parsed chat message from server */
export interface ChatMessage {
  sender: string;
  chatroom: string;
  message: string;
  sender_uid: string | null;
  time: string | null;
  uid: string;
  group: string | null;
}

/** Emergency alert pushed from server */
export interface EmergencyAlert {
  uid: string;
  callsign: string;
  lat: number | null;
  lon: number | null;
  type: string;
  emergency_type: string;
  time: string | null;
  message: string | null;
}

/** Geofence trigger alert pushed from server */
export interface GeofenceAlert {
  uid: string;
  trigger_uid: string;
  geofence_ref: string | null;
  callsign: string;
  lat: number | null;
  lon: number | null;
  time: string | null;
  remarks: string | null;
}

/** Connected client from ClientRegistry */
export interface Client {
  uid: string;
  callsign: string | null;
  group: string | null;
  group_color: string | null;
  peer: string | null;
  cert_cn: string | null;
  cert_serial: string | null;
  connected_at: string | null;
  protocol: "xml" | "protobuf";
}

/** Metrics stats pushed every 1s */
export interface Metrics {
  total_events: number;
  events_per_second: number;
  events_per_minute: number;
  connected_clients: number;
  sa_cached: number;
  chat_cached: number;
  uptime_seconds: number;
  memory_mb: number;
  federation_peers?: number;
  federation_connected?: number;
  federation_events_in?: number;
  federation_events_out?: number;
}

/** Registered video stream from the server */
export interface VideoStream {
  uid: string;
  url: string;
  alias: string;
  protocol: "rtsp" | "rtmp" | "hls" | "http" | "unknown";
  lat: number | null;
  lon: number | null;
  hae: number | null;
  created_at: string | null;
  updated_at: string | null;
  hls_url: string | null;
  hls_status: "starting" | "ready" | "error" | "stopped" | "restarting" | null;
}

/** Initial snapshot sent on channel join */
export interface Snapshot {
  sa: CotEvent[];
  markers: CotEvent[];
  shapes: CotEvent[];
  routes: CotEvent[];
  geofences: CotEvent[];
  chat: CotEvent[];
  chat_messages: ChatMessage[];
  clients: Client[];
  metrics: Metrics;
  video_streams: VideoStream[];
}

/** TAK group color names */
export type TakGroupColor =
  | "Cyan"
  | "Yellow"
  | "Magenta"
  | "Red"
  | "Green"
  | "Blue"
  | "Orange"
  | "White"
  | "Maroon"
  | "Purple"
  | "Dark Green"
  | "Teal";

/** Map of TAK group names to CSS custom property names */
export const TAK_GROUP_CSS: Record<string, string> = {
  Cyan: "var(--tak-cyan)",
  Yellow: "var(--tak-yellow)",
  Magenta: "var(--tak-magenta)",
  Red: "var(--tak-red)",
  Green: "var(--tak-green)",
  Blue: "var(--tak-blue)",
  Orange: "var(--tak-orange)",
  White: "var(--tak-white)",
  Maroon: "var(--tak-maroon)",
  Purple: "var(--tak-purple)",
  "Dark Green": "var(--tak-dark-green)",
  Teal: "var(--tak-teal)",
};

/** Get CSS color for a TAK group name, with fallback */
export function groupColor(group: string | null | undefined): string {
  if (!group) return "var(--color-text-dim)";
  return TAK_GROUP_CSS[group] ?? "var(--color-text-dim)";
}
