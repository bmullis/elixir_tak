import { useEffect, useRef } from "react";
import { Socket, Channel } from "phoenix";
import { useDashboardStore, type ParsedOverlaySnapshot } from "../store";
import type { ChatMessage, Client, CotEvent, EmergencyAlert, GeofenceAlert, Metrics, Snapshot, VideoStream } from "../types";
import type {
  MapMarker,
  MapShape,
  MapRoute,
  MapGeofence,
} from "../components/Map/types";

/** Singleton channel ref so components can push messages */
let _channelRef: Channel | null = null;

/** Get the current channel instance (for pushing messages) */
export function getChannel(): Channel | null {
  return _channelRef;
}

/**
 * Manages the Phoenix Channel lifecycle. Connects on mount,
 * wires all events into the Zustand store, cleans up on unmount.
 *
 * Call once at the app root.
 */
export function useChannel() {
  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);

  const {
    setStatus,
    loadSnapshot,
    updateMetrics,
    addClient,
    removeClient,
    handleCotEvent,
    addChatMessage,
    loadParsedOverlays,
    upsertParsedMarker,
    removeParsedMarker,
    upsertParsedShape,
    removeParsedShape,
    upsertParsedRoute,
    removeParsedRoute,
    upsertParsedGeofence,
    removeParsedGeofence,
    addEmergency,
    cancelEmergency,
    addGeofenceAlert,
    addVideoStream,
    updateVideoStream,
    removeVideoStream,
    updateHlsStatus,
  } = useDashboardStore();

  useEffect(() => {
    const wsUrl =
      window.location.protocol === "https:"
        ? `wss://${window.location.host}/socket/dashboard`
        : `ws://${window.location.host}/socket/dashboard`;

    const socket = new Socket(wsUrl);
    socket.connect();
    socketRef.current = socket;

    setStatus("connecting");

    const channel = socket.channel("dashboard:cop", {});
    channelRef.current = channel;
    _channelRef = channel;

    channel.on("snapshot", (payload: Snapshot) => {
      loadSnapshot(payload);
    });

    channel.on("parsed_overlays", (payload: ParsedOverlaySnapshot) => {
      loadParsedOverlays(payload);
    });

    channel.on("cot_event", (payload: CotEvent) => {
      handleCotEvent(payload);
    });

    channel.on("chat_message", (payload: ChatMessage) => {
      addChatMessage(payload);
    });

    channel.on("client_connected", (payload: Client) => {
      addClient(payload);
    });

    channel.on("client_disconnected", (payload: { uid: string }) => {
      removeClient(payload.uid);
    });

    channel.on("metrics", (payload: Metrics) => {
      updateMetrics(payload);
    });

    // Pre-parsed overlay events
    channel.on("upsert_marker", (payload: MapMarker) => {
      upsertParsedMarker(payload);
    });

    channel.on("remove_marker", (payload: { uid: string }) => {
      removeParsedMarker(payload.uid);
      const s = useDashboardStore.getState();
      if (s.markers.has(payload.uid)) {
        const next = new Map(s.markers);
        next.delete(payload.uid);
        useDashboardStore.setState({ markers: next });
      }
    });

    channel.on("upsert_shape", (payload: MapShape) => {
      upsertParsedShape(payload);
    });

    channel.on("remove_shape", (payload: { uid: string }) => {
      removeParsedShape(payload.uid);
      const s = useDashboardStore.getState();
      if (s.shapes.has(payload.uid)) {
        const next = new Map(s.shapes);
        next.delete(payload.uid);
        useDashboardStore.setState({ shapes: next });
      }
    });

    channel.on("upsert_route", (payload: MapRoute) => {
      upsertParsedRoute(payload);
    });

    channel.on("remove_route", (payload: { uid: string }) => {
      removeParsedRoute(payload.uid);
      const s = useDashboardStore.getState();
      if (s.routes.has(payload.uid)) {
        const next = new Map(s.routes);
        next.delete(payload.uid);
        useDashboardStore.setState({ routes: next });
      }
    });

    channel.on("upsert_geofence", (payload: MapGeofence) => {
      upsertParsedGeofence(payload);
    });

    channel.on("remove_geofence", (payload: { uid: string }) => {
      removeParsedGeofence(payload.uid);
    });

    // Emergency events
    channel.on("emergency_alert", (payload: EmergencyAlert) => {
      console.log("[TAK] emergency_alert received:", payload);
      addEmergency(payload);
    });

    channel.on("cancel_emergency", (payload: { uid: string }) => {
      console.log("[TAK] cancel_emergency received:", payload);
      cancelEmergency(payload.uid);
    });

    channel.on("geofence_triggered", (payload: GeofenceAlert) => {
      console.log("[TAK] geofence_triggered received:", payload);
      addGeofenceAlert(payload);
    });

    // Video stream events
    channel.on("video_stream_added", (payload: VideoStream) => {
      addVideoStream(payload);
    });

    channel.on("video_stream_updated", (payload: VideoStream) => {
      updateVideoStream(payload);
    });

    channel.on("video_stream_removed", (payload: { uid: string }) => {
      removeVideoStream(payload.uid);
    });

    channel.on("hls_status", (payload: { uid: string; status: string }) => {
      updateHlsStatus(payload.uid, payload.status);
    });

    channel
      .join()
      .receive("ok", () => setStatus("connected"))
      .receive("error", () => setStatus("error"));

    socket.onClose(() => setStatus("disconnected"));

    return () => {
      channel.leave();
      socket.disconnect();
      channelRef.current = null;
      socketRef.current = null;
      _channelRef = null;
    };
  }, [
    setStatus,
    loadSnapshot,
    updateMetrics,
    addClient,
    removeClient,
    handleCotEvent,
    addChatMessage,
    loadParsedOverlays,
    upsertParsedMarker,
    removeParsedMarker,
    upsertParsedShape,
    removeParsedShape,
    upsertParsedRoute,
    removeParsedRoute,
    upsertParsedGeofence,
    removeParsedGeofence,
    addEmergency,
    cancelEmergency,
    addGeofenceAlert,
    addVideoStream,
    updateVideoStream,
    removeVideoStream,
  ]);
}
