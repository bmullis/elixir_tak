import { Socket, Channel } from "phoenix";

let socket: Socket | null = null;
let channel: Channel | null = null;

export type ChannelStatus = "connecting" | "connected" | "disconnected" | "error";

export interface ChannelCallbacks {
  onStatus: (status: ChannelStatus) => void;
  onSnapshot: (payload: Record<string, unknown>) => void;
  onCotEvent: (payload: Record<string, unknown>) => void;
  onClientConnected: (payload: Record<string, unknown>) => void;
  onClientDisconnected: (payload: { uid: string }) => void;
  onMetrics: (payload: Record<string, unknown>) => void;
}

export function connectChannel(callbacks: ChannelCallbacks): () => void {
  // In dev with Vite proxy, the socket URL is relative.
  // In production, it's served from the same origin.
  const wsUrl =
    window.location.protocol === "https:"
      ? `wss://${window.location.host}/socket/dashboard`
      : `ws://${window.location.host}/socket/dashboard`;

  socket = new Socket(wsUrl);
  socket.connect();

  callbacks.onStatus("connecting");

  channel = socket.channel("dashboard:cop", {});

  channel.on("snapshot", (payload) => callbacks.onSnapshot(payload));
  channel.on("cot_event", (payload) => callbacks.onCotEvent(payload));
  channel.on("client_connected", (payload) => callbacks.onClientConnected(payload));
  channel.on("client_disconnected", (payload) =>
    callbacks.onClientDisconnected(payload as { uid: string })
  );
  channel.on("metrics", (payload) => callbacks.onMetrics(payload));

  channel
    .join()
    .receive("ok", () => {
      callbacks.onStatus("connected");
    })
    .receive("error", () => {
      callbacks.onStatus("error");
    });

  // Return cleanup function
  return () => {
    channel?.leave();
    socket?.disconnect();
    channel = null;
    socket = null;
  };
}
