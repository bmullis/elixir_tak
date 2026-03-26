import { create } from "zustand";
import type { ChatMessage, Client, CotEvent, EmergencyAlert, GeofenceAlert, Metrics, Snapshot, VideoStream } from "./types";
import type {
  MapMarker,
  MapShape,
  MapRoute,
  MapGeofence,
  Vertex,
} from "./components/Map/types";

/** Entity type classification for selection */
export type EntityType = "sa" | "marker" | "shape" | "route" | "geofence" | "video";

/** Currently selected entity info */
export interface SelectedEntity {
  uid: string;
  entityType: EntityType;
  /** The Cesium entity ID (may differ from uid for prefixed entities) */
  cesiumId: string;
}

/** Basemap style options */
export type BasemapStyle = "dark" | "satellite" | "hybrid";

/** Track point from the history API */
export interface TrackPoint {
  lat: number;
  lon: number;
  hae: number | null;
  speed: number | null;
  course: number | null;
  time: string;
}

/** Time window options for track history */
export type TrackWindow = "1h" | "4h" | "12h" | "24h";

/** Layer key for entity visibility/opacity control */
export type LayerKey =
  | "sa-friendly"
  | "sa-hostile"
  | "sa-neutral"
  | "sa-unknown"
  | "marker"
  | "shape"
  | "route"
  | "geofence"
  | "track"
  | "emergency"
  | "video";

/** Per-layer visibility and opacity */
export interface LayerTypeState {
  visible: boolean;
  opacity: number;
}

/** Full layer filter state */
export interface LayerState {
  types: Record<LayerKey, LayerTypeState>;
  /** Selected group names (only used when allGroups is false) */
  groups: Record<string, boolean>;
  /** When true, all groups pass the filter */
  allGroups: boolean;
  /** When set, only this layer is shown */
  soloLayer: LayerKey | null;
}

// ── Measurement Mode Types ───────────────────────────────────────────────────

/** Measurement tool modes */
export type MeasureMode = "distance" | "path" | "area";

/** Distance/area display units */
export type MeasureUnit = "metric" | "imperial" | "nautical";

/** A completed or in-progress measurement */
export interface MeasurementState {
  /** Which measurement tool is active (null = inactive) */
  mode: MeasureMode | null;
  /** Accumulated vertices for the current measurement */
  vertices: Vertex[];
  /** Current display unit system */
  unit: MeasureUnit;
  /** Completed measurements (persisted until cleared) */
  results: MeasurementResult[];
  /** Live cursor position for rubber-band preview (not stored as vertex) */
  cursorPosition: Vertex | null;
}

/** A completed measurement result */
export interface MeasurementResult {
  id: string;
  mode: MeasureMode;
  vertices: Vertex[];
  /** Total distance in meters (for distance/path) or area in sq meters (for area) */
  value: number;
  /** Per-segment distances in meters (for path mode) */
  segments: number[];
}

// ── Drawing Mode Types ──────────────────────────────────────────────────────

/** Drawing tool modes */
export type DrawingMode = "marker" | "polygon" | "rectangle" | "circle" | "route";

/** State of an in-progress drawing operation */
export interface DrawingState {
  /** Which tool is active (null = no drawing in progress) */
  mode: DrawingMode | null;
  /** Accumulated vertices for the current drawing */
  vertices: Vertex[];
  /** For circles: the center point (first click) */
  center: Vertex | null;
  /** For circles: radius in meters (computed from center + edge click) */
  radius: number | null;
  /** Name/callsign for the drawn feature */
  name: string;
  /** Optional remarks */
  remarks: string;
  /** Color for stroke (CSS rgba) */
  color: string;
}

/** Dashboard operator identity */
export interface DashboardIdentity {
  callsign: string;
  uid: string;
}

const IDENTITY_STORAGE_KEY = "elixir_tak_dashboard_identity";

function loadIdentity(): DashboardIdentity {
  try {
    const raw = localStorage.getItem(IDENTITY_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed.callsign && parsed.uid) return parsed;
    }
  } catch {
    // ignore
  }
  // Generate a stable UID for this browser
  const uid = "dashboard-" + crypto.randomUUID().slice(0, 8);
  const identity = { callsign: "Dashboard", uid };
  try {
    localStorage.setItem(IDENTITY_STORAGE_KEY, JSON.stringify(identity));
  } catch {
    // ignore
  }
  return identity;
}

function saveIdentity(identity: DashboardIdentity) {
  try {
    localStorage.setItem(IDENTITY_STORAGE_KEY, JSON.stringify(identity));
  } catch {
    // ignore
  }
}

const MEASURE_UNIT_KEY = "elixir_tak_measure_unit";

const VALID_MEASURE_UNITS: MeasureUnit[] = ["metric", "imperial", "nautical"];

function loadMeasureUnit(): MeasureUnit {
  try {
    const stored = localStorage.getItem(MEASURE_UNIT_KEY);
    if (stored && VALID_MEASURE_UNITS.includes(stored as MeasureUnit)) {
      return stored as MeasureUnit;
    }
  } catch {
    // ignore
  }
  return "metric";
}

const DEFAULT_MEASUREMENT_STATE: MeasurementState = {
  mode: null,
  vertices: [],
  unit: loadMeasureUnit(),
  results: [],
  cursorPosition: null,
};

const DEFAULT_DRAWING_STATE: DrawingState = {
  mode: null,
  vertices: [],
  center: null,
  radius: null,
  name: "",
  remarks: "",
  color: "rgba(0, 188, 212, 1)",
};

const LAYER_KEYS: LayerKey[] = [
  "sa-friendly",
  "sa-hostile",
  "sa-neutral",
  "sa-unknown",
  "marker",
  "shape",
  "route",
  "geofence",
  "track",
  "emergency",
  "video",
];

const STORAGE_KEY = "elixir_tak_layer_prefs";
const BASEMAP_STORAGE_KEY = "elixir_tak_basemap";

function defaultLayerState(): LayerState {
  const types = {} as Record<LayerKey, LayerTypeState>;
  for (const k of LAYER_KEYS) {
    types[k] = { visible: true, opacity: 1.0 };
  }
  return { types, groups: {}, allGroups: true, soloLayer: null };
}

function loadLayerState(): LayerState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      // Merge with defaults to handle new keys
      const defaults = defaultLayerState();
      return {
        types: { ...defaults.types, ...parsed.types },
        groups: parsed.groups ?? {},
        allGroups: parsed.allGroups ?? true,
        soloLayer: parsed.soloLayer ?? null,
      };
    }
  } catch {
    // Ignore parse errors
  }
  return defaultLayerState();
}

function saveLayerState(state: LayerState) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // Ignore storage errors
  }
}

export interface DashboardState {
  /** Channel connection status */
  status: "connecting" | "connected" | "disconnected" | "error";

  /** SA positions keyed by UID */
  positions: Map<string, CotEvent>;

  /** User-placed markers keyed by UID (raw CotEvent) */
  markers: Map<string, CotEvent>;

  /** Shapes/drawings keyed by UID (raw CotEvent) */
  shapes: Map<string, CotEvent>;

  /** Routes keyed by UID (raw CotEvent) */
  routes: Map<string, CotEvent>;

  /** Geofences keyed by UID (raw CotEvent) */
  geofences: Map<string, CotEvent>;

  /** Pre-parsed markers for map display */
  parsedMarkers: Map<string, MapMarker>;

  /** Pre-parsed shapes for map display */
  parsedShapes: Map<string, MapShape>;

  /** Pre-parsed routes for map display */
  parsedRoutes: Map<string, MapRoute>;

  /** Pre-parsed geofences for map display */
  parsedGeofences: Map<string, MapGeofence>;

  /** Chat messages (ordered, raw CotEvent for events feed) */
  chat: CotEvent[];

  /** Parsed chat messages for the chat panel */
  chatMessages: ChatMessage[];

  /** Known chatroom names */
  chatrooms: Set<string>;

  /** Selected chatroom filter (null = All Chat Rooms) */
  selectedChatroom: string | null;

  /** Which left-side panel is open (null = none) */
  leftPanel: "layers" | null;

  /** Whether the right-side chat panel is open */
  chatOpen: boolean;

  /** Unread message count (increments when chat panel is closed) */
  unreadCount: number;

  /** Connected clients keyed by UID */
  clients: Map<string, Client>;

  /** Server metrics (updated every 1s) */
  metrics: Metrics;

  /** Recent CoT events for the events feed */
  recentEvents: CotEvent[];

  /** Currently selected entity (null = nothing selected) */
  selectedEntity: SelectedEntity | null;

  /** Track history data keyed by UID */
  tracks: Map<string, TrackPoint[]>;

  /** UIDs with visible track lines */
  trackVisible: Set<string>;

  /** Track loading state */
  trackLoading: boolean;

  /** Selected time window for track queries */
  trackWindow: TrackWindow;

  /** Active emergencies keyed by client UID */
  emergencies: Map<string, EmergencyAlert>;

  /** Recent geofence trigger alerts (kept for flash animation, auto-expire) */
  geofenceAlerts: GeofenceAlert[];

  /** Layer visibility/opacity/group filter state */
  layerState: LayerState;

  /** Current basemap style */
  basemap: BasemapStyle;

  /** Drawing mode state */
  drawing: DrawingState;

  /** Measurement tool state */
  measurement: MeasurementState;

  /** Dashboard operator identity */
  identity: DashboardIdentity;

  /** Registered video streams keyed by UID */
  videoStreams: Map<string, VideoStream>;

  /* Actions */
  setStatus: (status: DashboardState["status"]) => void;
  loadSnapshot: (snapshot: Snapshot) => void;
  updateMetrics: (metrics: Metrics) => void;
  addClient: (client: Client) => void;
  removeClient: (uid: string) => void;
  handleCotEvent: (event: CotEvent) => void;

  /* Chat actions */
  addChatMessage: (msg: ChatMessage) => void;
  setChatroom: (room: string | null) => void;
  resetUnread: () => void;
  toggleChat: () => void;

  /* Left panel actions (layers only) */
  setLeftPanel: (panel: "layers" | null) => void;
  toggleLeftPanel: (panel: "layers") => void;

  /* Selection actions */
  selectEntity: (entity: SelectedEntity | null) => void;
  setTrackWindow: (window: TrackWindow) => void;
  toggleTrack: (uid: string) => void;
  setTrackData: (uid: string, points: TrackPoint[]) => void;
  setTrackLoading: (loading: boolean) => void;
  clearTrack: (uid: string) => void;

  /* Basemap actions */
  setBasemap: (style: BasemapStyle) => void;

  /* Layer filter actions */
  setLayerVisibility: (key: LayerKey, visible: boolean) => void;
  setLayerOpacity: (key: LayerKey, opacity: number) => void;
  setSoloLayer: (key: LayerKey | null) => void;
  setGroupFilter: (group: string, enabled: boolean) => void;
  setAllGroups: (allGroups: boolean) => void;
  showAllLayers: () => void;
  hideAllLayers: () => void;

  /* Emergency actions */
  addEmergency: (alert: EmergencyAlert) => void;
  cancelEmergency: (uid: string) => void;
  addGeofenceAlert: (alert: GeofenceAlert) => void;

  /* Drawing actions */
  setDrawingMode: (mode: DrawingMode | null) => void;
  addDrawingVertex: (vertex: Vertex) => void;
  setDrawingCenter: (center: Vertex) => void;
  setDrawingRadius: (radius: number) => void;
  setDrawingName: (name: string) => void;
  setDrawingRemarks: (remarks: string) => void;
  setDrawingColor: (color: string) => void;
  undoDrawingVertex: () => void;
  clearDrawing: () => void;

  /* Measurement actions */
  setMeasureMode: (mode: MeasureMode | null) => void;
  addMeasureVertex: (vertex: Vertex) => void;
  undoMeasureVertex: () => void;
  setMeasureUnit: (unit: MeasureUnit) => void;
  setMeasureCursor: (position: Vertex | null) => void;
  completeMeasurement: (result: MeasurementResult) => void;
  removeMeasurement: (id: string) => void;
  clearMeasurements: () => void;
  clearActiveMeasurement: () => void;

  /* Identity actions */
  setCallsign: (callsign: string) => void;

  /* Video stream actions */
  setVideoStreams: (streams: VideoStream[]) => void;
  addVideoStream: (stream: VideoStream) => void;
  updateVideoStream: (stream: VideoStream) => void;
  removeVideoStream: (uid: string) => void;
  updateHlsStatus: (uid: string, status: string) => void;

  /* Parsed overlay actions (from channel) */
  upsertParsedMarker: (marker: MapMarker) => void;
  removeParsedMarker: (uid: string) => void;
  upsertParsedShape: (shape: MapShape) => void;
  removeParsedShape: (uid: string) => void;
  upsertParsedRoute: (route: MapRoute) => void;
  removeParsedRoute: (uid: string) => void;
  upsertParsedGeofence: (geofence: MapGeofence) => void;
  removeParsedGeofence: (uid: string) => void;
  loadParsedOverlays: (overlays: ParsedOverlaySnapshot) => void;
}

export interface ParsedOverlaySnapshot {
  markers: MapMarker[];
  shapes: MapShape[];
  routes: MapRoute[];
  geofences: MapGeofence[];
}

const MAX_RECENT_EVENTS = 100;
const MAX_CHAT = 200;

const emptyMetrics: Metrics = {
  total_events: 0,
  events_per_second: 0,
  events_per_minute: 0,
  connected_clients: 0,
  sa_cached: 0,
  chat_cached: 0,
  uptime_seconds: 0,
  memory_mb: 0,
};

export const useDashboardStore = create<DashboardState>((set) => ({
  status: "connecting",
  positions: new Map(),
  markers: new Map(),
  shapes: new Map(),
  routes: new Map(),
  geofences: new Map(),
  parsedMarkers: new Map(),
  parsedShapes: new Map(),
  parsedRoutes: new Map(),
  parsedGeofences: new Map(),
  chat: [],
  chatMessages: [],
  chatrooms: new Set<string>(),
  selectedChatroom: null,
  leftPanel: null,
  chatOpen: false,
  unreadCount: 0,
  clients: new Map(),
  metrics: emptyMetrics,
  emergencies: new Map(),
  geofenceAlerts: [],
  recentEvents: [],
  selectedEntity: null,
  tracks: new Map(),
  trackVisible: new Set(),
  trackLoading: false,
  trackWindow: "4h",
  layerState: loadLayerState(),
  basemap: (localStorage.getItem(BASEMAP_STORAGE_KEY) as BasemapStyle) || "dark",
  drawing: { ...DEFAULT_DRAWING_STATE },
  measurement: { ...DEFAULT_MEASUREMENT_STATE },
  identity: loadIdentity(),
  videoStreams: new Map(),

  setStatus: (status) => set({ status }),

  loadSnapshot: (snapshot) => {
    const chatMessages = snapshot.chat_messages ?? [];
    const chatrooms = new Set<string>();
    for (const msg of chatMessages) {
      if (msg.chatroom) chatrooms.add(msg.chatroom);
    }
    set({
      positions: new Map(
        snapshot.sa
          .filter((e) => e.type.startsWith("a-"))
          .map((e) => [e.uid, e])
      ),
      markers: new Map(snapshot.markers.map((e) => [e.uid, e])),
      shapes: new Map(snapshot.shapes.map((e) => [e.uid, e])),
      routes: new Map(snapshot.routes.map((e) => [e.uid, e])),
      geofences: new Map(snapshot.geofences.map((e) => [e.uid, e])),
      chat: snapshot.chat,
      chatMessages,
      chatrooms,
      clients: new Map(snapshot.clients.map((c) => [c.uid, c])),
      metrics: snapshot.metrics,
      videoStreams: new Map((snapshot.video_streams ?? []).map((s) => [s.uid, s])),
    });
  },

  updateMetrics: (metrics) => set({ metrics }),

  addClient: (client) =>
    set((state) => {
      const next = new Map(state.clients);
      next.set(client.uid, client);
      return { clients: next };
    }),

  removeClient: (uid) =>
    set((state) => {
      const next = new Map(state.clients);
      next.delete(uid);
      return { clients: next };
    }),

  handleCotEvent: (event) =>
    set((state) => {
      const updates: Partial<DashboardState> = {};

      // Route event to appropriate cache based on type
      const type = event.type;

      if (type.startsWith("a-")) {
        // SA position update
        const next = new Map(state.positions);
        next.set(event.uid, event);
        updates.positions = next;
      } else if (type.startsWith("b-t-f")) {
        // Chat message
        const next = [...state.chat, event];
        if (next.length > MAX_CHAT) next.splice(0, next.length - MAX_CHAT);
        updates.chat = next;
      } else if (type.startsWith("b-m-p")) {
        // Marker (raw CotEvent kept for events feed)
        const next = new Map(state.markers);
        next.set(event.uid, event);
        updates.markers = next;
      } else if (type === "b-m-r") {
        // Route
        const next = new Map(state.routes);
        next.set(event.uid, event);
        updates.routes = next;
      } else if (type.startsWith("u-d-")) {
        // Shape/drawing
        const next = new Map(state.shapes);
        next.set(event.uid, event);
        updates.shapes = next;
      } else if (type.startsWith("b-a-g")) {
        // Geofence
        const next = new Map(state.geofences);
        next.set(event.uid, event);
        updates.geofences = next;
      }

      // Always add to recent events feed
      const recentEvents = [event, ...state.recentEvents].slice(
        0,
        MAX_RECENT_EVENTS
      );
      updates.recentEvents = recentEvents;

      return updates;
    }),

  // ── Chat actions ────────────────────────────────────────────────────

  addChatMessage: (msg) =>
    set((state) => {
      const next = [...state.chatMessages, msg];
      if (next.length > MAX_CHAT) next.splice(0, next.length - MAX_CHAT);
      const chatrooms = new Set(state.chatrooms);
      if (msg.chatroom) chatrooms.add(msg.chatroom);
      return {
        chatMessages: next,
        chatrooms,
        unreadCount: state.chatOpen ? state.unreadCount : state.unreadCount + 1,
      };
    }),

  setChatroom: (room) => set({ selectedChatroom: room }),

  resetUnread: () => set({ unreadCount: 0 }),

  toggleChat: () =>
    set((state) => ({
      chatOpen: !state.chatOpen,
      unreadCount: !state.chatOpen ? 0 : state.unreadCount,
    })),

  setLeftPanel: (panel) => set({ leftPanel: panel }),

  toggleLeftPanel: (panel) =>
    set((state) => ({
      leftPanel: state.leftPanel === panel ? null : panel,
    })),

  // ── Selection & track actions ────────────────────────────────────────

  selectEntity: (entity) => set({ selectedEntity: entity }),

  setTrackWindow: (window) => set({ trackWindow: window }),

  toggleTrack: (uid) =>
    set((state) => {
      const next = new Set(state.trackVisible);
      if (next.has(uid)) {
        next.delete(uid);
      } else {
        next.add(uid);
      }
      return { trackVisible: next };
    }),

  setTrackData: (uid, points) =>
    set((state) => {
      const next = new Map(state.tracks);
      next.set(uid, points);
      return { tracks: next };
    }),

  setTrackLoading: (loading) => set({ trackLoading: loading }),

  clearTrack: (uid) =>
    set((state) => {
      const nextTracks = new Map(state.tracks);
      nextTracks.delete(uid);
      const nextVisible = new Set(state.trackVisible);
      nextVisible.delete(uid);
      return { tracks: nextTracks, trackVisible: nextVisible };
    }),

  // ── Basemap actions ──────────────────────────────────────────────────

  setBasemap: (style) => {
    try { localStorage.setItem(BASEMAP_STORAGE_KEY, style); } catch { /* ignore */ }
    set({ basemap: style });
  },

  // ── Layer filter actions ────────────────────────────────────────────

  setLayerVisibility: (key, visible) =>
    set((state) => {
      const next: LayerState = {
        ...state.layerState,
        types: { ...state.layerState.types, [key]: { ...state.layerState.types[key], visible } },
        soloLayer: state.layerState.soloLayer === key && !visible ? null : state.layerState.soloLayer,
      };
      saveLayerState(next);
      return { layerState: next };
    }),

  setLayerOpacity: (key, opacity) =>
    set((state) => {
      const next: LayerState = {
        ...state.layerState,
        types: { ...state.layerState.types, [key]: { ...state.layerState.types[key], opacity } },
      };
      saveLayerState(next);
      return { layerState: next };
    }),

  setSoloLayer: (key) =>
    set((state) => {
      const next: LayerState = {
        ...state.layerState,
        soloLayer: state.layerState.soloLayer === key ? null : key,
      };
      saveLayerState(next);
      return { layerState: next };
    }),

  setGroupFilter: (group, enabled) =>
    set((state) => {
      const groups = { ...state.layerState.groups };
      if (enabled) {
        groups[group] = true;
      } else {
        delete groups[group];
      }
      const next: LayerState = { ...state.layerState, groups, allGroups: false };
      saveLayerState(next);
      return { layerState: next };
    }),

  setAllGroups: (allGroups) =>
    set((state) => {
      const next: LayerState = {
        ...state.layerState,
        allGroups,
        groups: allGroups ? {} : state.layerState.groups,
      };
      saveLayerState(next);
      return { layerState: next };
    }),

  showAllLayers: () =>
    set((state) => {
      const types = { ...state.layerState.types };
      for (const k of LAYER_KEYS) {
        types[k] = { ...types[k], visible: true };
      }
      const next: LayerState = { ...state.layerState, types, soloLayer: null };
      saveLayerState(next);
      return { layerState: next };
    }),

  hideAllLayers: () =>
    set((state) => {
      const types = { ...state.layerState.types };
      for (const k of LAYER_KEYS) {
        types[k] = { ...types[k], visible: false };
      }
      const next: LayerState = { ...state.layerState, types, soloLayer: null };
      saveLayerState(next);
      return { layerState: next };
    }),

  // ── Emergency actions ──────────────────────────────────────────────

  addEmergency: (alert) =>
    set((state) => {
      const next = new Map(state.emergencies);
      next.set(alert.uid, alert);
      return { emergencies: next };
    }),

  cancelEmergency: (uid) =>
    set((state) => {
      const next = new Map(state.emergencies);
      next.delete(uid);
      return { emergencies: next };
    }),

  addGeofenceAlert: (alert) =>
    set((state) => {
      const next = [alert, ...state.geofenceAlerts].slice(0, 20);
      return { geofenceAlerts: next };
    }),

  // ── Drawing actions ────────────────────────────────────────────────

  setDrawingMode: (mode) =>
    set((state) => ({
      drawing: mode
        ? { ...DEFAULT_DRAWING_STATE, mode, color: state.drawing.color }
        : { ...DEFAULT_DRAWING_STATE },
      // Clear measurement mode if drawing activates
      measurement: mode
        ? { ...state.measurement, mode: null, vertices: [], cursorPosition: null }
        : state.measurement,
    })),

  addDrawingVertex: (vertex) =>
    set((state) => ({
      drawing: { ...state.drawing, vertices: [...state.drawing.vertices, vertex] },
    })),

  setDrawingCenter: (center) =>
    set((state) => ({ drawing: { ...state.drawing, center } })),

  setDrawingRadius: (radius) =>
    set((state) => ({ drawing: { ...state.drawing, radius } })),

  setDrawingName: (name) =>
    set((state) => ({ drawing: { ...state.drawing, name } })),

  setDrawingRemarks: (remarks) =>
    set((state) => ({ drawing: { ...state.drawing, remarks } })),

  setDrawingColor: (color) =>
    set((state) => ({ drawing: { ...state.drawing, color } })),

  undoDrawingVertex: () =>
    set((state) => ({
      drawing: {
        ...state.drawing,
        vertices: state.drawing.vertices.slice(0, -1),
      },
    })),

  clearDrawing: () => set({ drawing: { ...DEFAULT_DRAWING_STATE } }),

  // ── Measurement actions ─────────────────────────────────────────────

  setMeasureMode: (mode) =>
    set((state) => ({
      measurement: mode
        ? { ...state.measurement, mode, vertices: [], cursorPosition: null }
        : { ...state.measurement, mode: null, vertices: [], cursorPosition: null },
      // Clear drawing mode if measurement activates
      drawing: mode ? { ...DEFAULT_DRAWING_STATE } : state.drawing,
    })),

  addMeasureVertex: (vertex) =>
    set((state) => ({
      measurement: { ...state.measurement, vertices: [...state.measurement.vertices, vertex] },
    })),

  undoMeasureVertex: () =>
    set((state) => ({
      measurement: {
        ...state.measurement,
        vertices: state.measurement.vertices.slice(0, -1),
      },
    })),

  setMeasureUnit: (unit) => {
    try { localStorage.setItem(MEASURE_UNIT_KEY, unit); } catch { /* ignore */ }
    set((state) => ({ measurement: { ...state.measurement, unit } }));
  },

  setMeasureCursor: (position) =>
    set((state) => ({
      measurement: { ...state.measurement, cursorPosition: position },
    })),

  completeMeasurement: (result) =>
    set((state) => ({
      measurement: {
        ...state.measurement,
        results: [...state.measurement.results, result],
        vertices: [],
        cursorPosition: null,
      },
    })),

  removeMeasurement: (id) =>
    set((state) => ({
      measurement: {
        ...state.measurement,
        results: state.measurement.results.filter((r) => r.id !== id),
      },
    })),

  clearMeasurements: () =>
    set((state) => ({
      measurement: { ...DEFAULT_MEASUREMENT_STATE, unit: state.measurement.unit },
    })),

  clearActiveMeasurement: () =>
    set((state) => ({
      measurement: { ...state.measurement, vertices: [], cursorPosition: null },
    })),

  // ── Identity actions ──────────────────────────────────────────────

  setCallsign: (callsign) =>
    set((state) => {
      const identity = { ...state.identity, callsign };
      saveIdentity(identity);
      return { identity };
    }),

  // ── Video stream actions ───────────────────────────────────────────

  setVideoStreams: (streams) =>
    set({ videoStreams: new Map(streams.map((s) => [s.uid, s])) }),

  addVideoStream: (stream) =>
    set((state) => {
      const next = new Map(state.videoStreams);
      next.set(stream.uid, stream);
      return { videoStreams: next };
    }),

  updateVideoStream: (stream) =>
    set((state) => {
      const next = new Map(state.videoStreams);
      next.set(stream.uid, stream);
      return { videoStreams: next };
    }),

  removeVideoStream: (uid) =>
    set((state) => {
      const next = new Map(state.videoStreams);
      next.delete(uid);
      return { videoStreams: next };
    }),

  updateHlsStatus: (uid, status) =>
    set((state) => {
      const existing = state.videoStreams.get(uid);
      if (!existing) return state;
      const next = new Map(state.videoStreams);
      next.set(uid, { ...existing, hls_status: status as VideoStream["hls_status"] });
      return { videoStreams: next };
    }),

  // ── Parsed overlay actions ──────────────────────────────────────────

  loadParsedOverlays: (overlays) =>
    set({
      parsedMarkers: new Map(overlays.markers.map((m) => [m.uid, m])),
      parsedShapes: new Map(overlays.shapes.map((s) => [s.uid, s])),
      parsedRoutes: new Map(overlays.routes.map((r) => [r.uid, r])),
      parsedGeofences: new Map(overlays.geofences.map((g) => [g.uid, g])),
    }),

  upsertParsedMarker: (marker) =>
    set((state) => {
      const next = new Map(state.parsedMarkers);
      next.set(marker.uid, marker);
      return { parsedMarkers: next };
    }),

  removeParsedMarker: (uid) =>
    set((state) => {
      const next = new Map(state.parsedMarkers);
      next.delete(uid);
      return { parsedMarkers: next };
    }),

  upsertParsedShape: (shape) =>
    set((state) => {
      const next = new Map(state.parsedShapes);
      next.set(shape.uid, shape);
      return { parsedShapes: next };
    }),

  removeParsedShape: (uid) =>
    set((state) => {
      const next = new Map(state.parsedShapes);
      next.delete(uid);
      return { parsedShapes: next };
    }),

  upsertParsedRoute: (route) =>
    set((state) => {
      const next = new Map(state.parsedRoutes);
      next.set(route.uid, route);
      return { parsedRoutes: next };
    }),

  removeParsedRoute: (uid) =>
    set((state) => {
      const next = new Map(state.parsedRoutes);
      next.delete(uid);
      return { parsedRoutes: next };
    }),

  upsertParsedGeofence: (geofence) =>
    set((state) => {
      const next = new Map(state.parsedGeofences);
      next.set(geofence.uid, geofence);
      return { parsedGeofences: next };
    }),

  removeParsedGeofence: (uid) =>
    set((state) => {
      const next = new Map(state.parsedGeofences);
      next.delete(uid);
      return { parsedGeofences: next };
    }),
}));
