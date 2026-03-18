import { useCallback, useEffect, useRef, useState } from "react";
import Hls from "hls.js";
import { useDashboardStore } from "../../store";
import type { VideoStream } from "../../types";
import { Video } from "lucide-react";
import styles from "./VideoPage.module.css";

const PROTOCOL_CLASS: Record<string, string> = {
  hls: styles.protocolHls,
  rtsp: styles.protocolRtsp,
  rtmp: styles.protocolRtmp,
  http: styles.protocolHttp,
  unknown: styles.protocolUnknown,
};

type StreamStatus = "online" | "offline" | "checking";

function AddStreamModal({
  onClose,
  onSubmit,
}: {
  onClose: () => void;
  onSubmit: (data: {
    url: string;
    alias: string;
    lat: string;
    lon: string;
  }) => void;
}) {
  const [url, setUrl] = useState("");
  const [alias, setAlias] = useState("");
  const [lat, setLat] = useState("");
  const [lon, setLon] = useState("");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!url.trim()) return;
    onSubmit({ url: url.trim(), alias: alias.trim() || "Video Stream", lat, lon });
  };

  return (
    <div className={styles.modalBackdrop} onClick={onClose}>
      <form
        className={styles.modal}
        onClick={(e) => e.stopPropagation()}
        onSubmit={handleSubmit}
      >
        <h3 className={styles.modalTitle}>Add Video Stream</h3>

        <div className={styles.formGroup}>
          <label className={styles.formLabel}>Stream URL</label>
          <input
            className={styles.formInput}
            type="text"
            placeholder="rtsp://... or https://.../*.m3u8"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            autoFocus
          />
        </div>

        <div className={styles.formGroup}>
          <label className={styles.formLabel}>Alias</label>
          <input
            className={styles.formInput}
            type="text"
            placeholder="Camera name"
            value={alias}
            onChange={(e) => setAlias(e.target.value)}
          />
        </div>

        <div className={styles.formRow}>
          <div className={styles.formGroup}>
            <label className={styles.formLabel}>Latitude</label>
            <input
              className={styles.formInput}
              type="text"
              placeholder="33.4942"
              value={lat}
              onChange={(e) => setLat(e.target.value)}
            />
          </div>
          <div className={styles.formGroup}>
            <label className={styles.formLabel}>Longitude</label>
            <input
              className={styles.formInput}
              type="text"
              placeholder="-111.9261"
              value={lon}
              onChange={(e) => setLon(e.target.value)}
            />
          </div>
        </div>

        <div className={styles.modalActions}>
          <button
            type="button"
            className={styles.cancelBtn}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="submit"
            className={styles.submitBtn}
            disabled={!url.trim()}
          >
            Add Stream
          </button>
        </div>
      </form>
    </div>
  );
}

function VideoPlayer({
  stream,
  onStatusChange,
}: {
  stream: VideoStream;
  onStatusChange: (uid: string, status: StreamStatus) => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const [playing, setPlaying] = useState(false);
  const mountedRef = useRef(false);

  const cleanup = useCallback(() => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
    if (videoRef.current) {
      videoRef.current.pause();
      videoRef.current.removeAttribute("src");
      videoRef.current.load();
    }
    setPlaying(false);
  }, []);

  // Cleanup on unmount
  useEffect(() => cleanup, [cleanup]);

  const play = useCallback(() => {
    const video = videoRef.current;
    if (!video || !stream.url) return;

    onStatusChange(stream.uid, "checking");

    // Determine the playback URL: use HLS transcoded URL for RTSP/RTMP if available
    const hlsTranscoded =
      (stream.protocol === "rtsp" || stream.protocol === "rtmp") && stream.hls_url;
    const isHls =
      hlsTranscoded || stream.protocol === "hls" || stream.url.includes(".m3u8");
    const hlsUrl = hlsTranscoded ? stream.hls_url! : stream.url;

    if (isHls) {
      if (Hls.isSupported()) {
        const hls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
          liveSyncDurationCount: 1,
          liveMaxLatencyDurationCount: 3,
          maxBufferLength: 3,
          maxMaxBufferLength: 10,
        });
        hlsRef.current = hls;
        hls.loadSource(hlsUrl);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          video.play().catch(() => {});
          setPlaying(true);
          onStatusChange(stream.uid, "online");
        });
        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal) {
            onStatusChange(stream.uid, "offline");
            cleanup();
          }
        });
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
        // Native HLS (Safari)
        video.src = hlsUrl;
        video.addEventListener("loadedmetadata", () => {
          video.play().catch(() => {});
          setPlaying(true);
          onStatusChange(stream.uid, "online");
        });
        video.addEventListener("error", () => {
          onStatusChange(stream.uid, "offline");
        });
      }
    } else if (
      stream.url.startsWith("http") &&
      stream.protocol !== "rtsp" &&
      stream.protocol !== "rtmp"
    ) {
      // Direct HTTP video (MP4, WebM, etc.)
      video.src = stream.url;
      video.addEventListener("loadedmetadata", () => {
        video.play().catch(() => {});
        setPlaying(true);
        onStatusChange(stream.uid, "online");
      });
      video.addEventListener("error", () => {
        onStatusChange(stream.uid, "offline");
      });
    } else {
      // RTSP/RTMP without HLS transcoding available
      onStatusChange(stream.uid, "offline");
    }
  }, [stream, onStatusChange, cleanup]);

  const togglePip = useCallback(async () => {
    const video = videoRef.current;
    if (!video) return;
    try {
      if (document.pictureInPictureElement === video) {
        await document.exitPictureInPicture();
      } else if (document.pictureInPictureEnabled) {
        await video.requestPictureInPicture();
      }
    } catch {
      // PiP not supported or denied
    }
  }, []);

  const handleClick = useCallback(() => {
    if (playing) {
      cleanup();
    } else {
      play();
    }
  }, [playing, play, cleanup]);

  const canPlayInBrowser =
    stream.protocol === "hls" ||
    stream.protocol === "http" ||
    stream.url?.includes(".m3u8") ||
    !!stream.hls_url;

  const placeholderContent = () => {
    if (canPlayInBrowser) {
      if (stream.hls_status === "starting" || stream.hls_status === "restarting") {
        return (
          <>
            <span className={styles.placeholderIcon}>&#8987;</span>
            <span className={styles.placeholderText}>Transcoding...</span>
          </>
        );
      }
      return (
        <>
          <span className={styles.placeholderIcon}>&#9654;</span>
          <span className={styles.placeholderText}>Connecting...</span>
        </>
      );
    }
    return (
      <>
        <span className={styles.placeholderIcon}>&#128249;</span>
        <span className={styles.placeholderText}>
          {stream.protocol.toUpperCase()} - browser playback unavailable
        </span>
      </>
    );
  };

  return (
    <div className={styles.playerArea} onClick={handleClick}>
      <video
        ref={(el) => {
          videoRef.current = el;
          if (el && !mountedRef.current) {
            mountedRef.current = true;
            // Defer to next tick so play() can read videoRef
            requestAnimationFrame(() => play());
          }
        }}
        playsInline
        muted
        autoPlay
      />
      {!playing && (
        <div className={styles.placeholder}>
          {placeholderContent()}
        </div>
      )}
      {playing && (
        <div className={styles.playOverlay}>
          <button
            className={styles.playBtn}
            onClick={(e) => {
              e.stopPropagation();
              togglePip();
            }}
            title="Picture-in-Picture"
          >
            &#8862;
          </button>
        </div>
      )}
    </div>
  );
}

function StreamCard({
  stream,
  onDelete,
  statusMap,
  onStatusChange,
}: {
  stream: VideoStream;
  onDelete: (uid: string) => void;
  statusMap: Map<string, StreamStatus>;
  onStatusChange: (uid: string, status: StreamStatus) => void;
}) {
  const status = statusMap.get(stream.uid) ?? "checking";
  const statusClass =
    status === "online"
      ? styles.statusOnline
      : status === "offline"
        ? styles.statusOffline
        : styles.statusChecking;

  return (
    <div className={styles.card}>
      <VideoPlayer stream={stream} onStatusChange={onStatusChange} />
      <div className={styles.cardInfo}>
        <div className={styles.cardHeader}>
          <span className={styles.streamAlias}>{stream.alias}</span>
          <div className={styles.streamActions}>
            <button
              className={`${styles.iconBtn} ${styles.iconBtnDanger}`}
              onClick={() => onDelete(stream.uid)}
              title="Remove stream"
            >
              &#10005;
            </button>
          </div>
        </div>
        <div className={styles.cardMeta}>
          <span className={`${styles.statusDot} ${statusClass}`} />
          <span
            className={`${styles.protocolBadge} ${PROTOCOL_CLASS[stream.protocol] ?? PROTOCOL_CLASS.unknown}`}
          >
            {stream.protocol}
          </span>
          {stream.lat != null && stream.lon != null && (
            <span className={styles.coords}>
              {stream.lat.toFixed(4)}, {stream.lon.toFixed(4)}
            </span>
          )}
        </div>
        <div className={styles.streamUrl} title={stream.url}>
          {stream.url}
        </div>
      </div>
    </div>
  );
}

export default function VideoPage() {
  const videoStreams = useDashboardStore((s) => s.videoStreams);
  const [showAdd, setShowAdd] = useState(false);
  const [statusMap, setStatusMap] = useState<Map<string, StreamStatus>>(
    new Map()
  );

  const streams = Array.from(videoStreams.values());

  // Set initial status for streams on mount
  useEffect(() => {
    const initial = new Map<string, StreamStatus>();
    for (const s of streams) {
      if ((s.protocol === "rtsp" || s.protocol === "rtmp") && !s.hls_url) {
        initial.set(s.uid, "offline");
      } else {
        initial.set(s.uid, "checking");
      }
    }
    setStatusMap(initial);
    // Only run on stream UID list changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [videoStreams.size]);

  const handleStatusChange = useCallback(
    (uid: string, status: StreamStatus) => {
      setStatusMap((prev) => {
        const next = new Map(prev);
        next.set(uid, status);
        return next;
      });
    },
    []
  );

  const handleAdd = useCallback(
    async (data: { url: string; alias: string; lat: string; lon: string }) => {
      try {
        await fetch("/api/video", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            url: data.url,
            alias: data.alias,
            lat: data.lat || null,
            lon: data.lon || null,
          }),
        });
        setShowAdd(false);
      } catch (err) {
        console.error("Failed to add video stream:", err);
      }
    },
    []
  );

  const handleDelete = useCallback(async (uid: string) => {
    try {
      await fetch(`/api/video/${uid}`, { method: "DELETE" });
    } catch (err) {
      console.error("Failed to delete video stream:", err);
    }
  }, []);

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <h2 className={styles.title}>Video Streams</h2>
        <button className={styles.addBtn} onClick={() => setShowAdd(true)}>
          + Add Stream
        </button>
      </div>

      {streams.length === 0 ? (
        <div className={styles.empty}>
          <div className={styles.emptyIcon}><Video size={48} /></div>
          <div className={styles.emptyText}>No video streams registered</div>
          <div className={styles.emptyHint}>
            Add a stream via the button above or POST to /api/video
          </div>
        </div>
      ) : (
        <div className={styles.grid}>
          {streams.map((stream) => (
            <StreamCard
              key={stream.uid}
              stream={stream}
              onDelete={handleDelete}
              statusMap={statusMap}
              onStatusChange={handleStatusChange}
            />
          ))}
        </div>
      )}

      {showAdd && (
        <AddStreamModal
          onClose={() => setShowAdd(false)}
          onSubmit={handleAdd}
        />
      )}
    </div>
  );
}
