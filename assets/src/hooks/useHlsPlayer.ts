import { useCallback, useEffect, useRef, useState } from "react";
import Hls from "hls.js";

interface HlsPlayerOptions {
  url: string;
  protocol: string;
}

interface HlsPlayerResult {
  videoRef: React.RefObject<HTMLVideoElement | null>;
  playing: boolean;
  canPlay: boolean;
}

/** Manages HLS/HTTP video playback with auto-play and cleanup. */
export function useHlsPlayer({ url, protocol }: HlsPlayerOptions): HlsPlayerResult {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const [playing, setPlaying] = useState(false);

  const isHls = protocol === "hls" || url.includes(".m3u8");
  const canPlay =
    isHls || (url.startsWith("http") && protocol !== "rtsp" && protocol !== "rtmp");

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

  useEffect(() => cleanup, [cleanup]);

  const play = useCallback(() => {
    const video = videoRef.current;
    if (!video || !url) return;

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
        hls.loadSource(url);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          video.play().catch(() => {});
          setPlaying(true);
        });
        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal) cleanup();
        });
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
        video.src = url;
        video.addEventListener("loadedmetadata", () => {
          video.play().catch(() => {});
          setPlaying(true);
        });
      }
    } else if (canPlay) {
      video.src = url;
      video.addEventListener("loadedmetadata", () => {
        video.play().catch(() => {});
        setPlaying(true);
      });
    }
  }, [url, isHls, canPlay, cleanup]);

  useEffect(() => {
    if (canPlay) {
      const timer = requestAnimationFrame(() => play());
      return () => cancelAnimationFrame(timer);
    }
  }, [canPlay, play]);

  return { videoRef, playing, canPlay };
}
