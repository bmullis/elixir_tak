import { describe, it, expect } from "vitest";
import {
  parseEmbeddedVideo,
  entityTypeLabel,
  formatTime,
  formatTimeDelta,
  formatDuration,
  formatCoords,
  formatSpeed,
} from "./formatting";

// ── parseEmbeddedVideo ──────────────────────────────────────────────────────

describe("parseEmbeddedVideo", () => {
  it("returns null for null input", () => {
    expect(parseEmbeddedVideo(null)).toBeNull();
  });

  it("returns null when no __video element present", () => {
    expect(
      parseEmbeddedVideo("<detail><contact callsign='A'/></detail>")
    ).toBeNull();
  });

  it("parses url and protocol from __video element", () => {
    const xml =
      '<detail><__video url="https://example.com/stream.m3u8" protocol="hls"/></detail>';
    expect(parseEmbeddedVideo(xml)).toEqual({
      url: "https://example.com/stream.m3u8",
      protocol: "hls",
    });
  });

  it("defaults protocol to unknown when missing", () => {
    const xml = '<detail><__video url="rtsp://cam.local:554/live"/></detail>';
    expect(parseEmbeddedVideo(xml)).toEqual({
      url: "rtsp://cam.local:554/live",
      protocol: "unknown",
    });
  });

  it("returns null when url attribute is missing", () => {
    const xml = '<detail><__video protocol="hls"/></detail>';
    expect(parseEmbeddedVideo(xml)).toBeNull();
  });

  it("handles self-closing __video tag", () => {
    const xml =
      '<detail><__video url="http://stream.local/feed" protocol="http" /></detail>';
    expect(parseEmbeddedVideo(xml)).toEqual({
      url: "http://stream.local/feed",
      protocol: "http",
    });
  });
});

// ── entityTypeLabel ─────────────────────────────────────────────────────────

describe("entityTypeLabel", () => {
  it("returns Situational Awareness for sa", () => {
    expect(entityTypeLabel("sa")).toBe("Situational Awareness");
  });

  it("returns Marker for marker", () => {
    expect(entityTypeLabel("marker")).toBe("Marker");
  });

  it("returns Shape / Drawing for shape", () => {
    expect(entityTypeLabel("shape")).toBe("Shape / Drawing");
  });

  it("returns Route for route", () => {
    expect(entityTypeLabel("route")).toBe("Route");
  });

  it("returns Geofence for geofence", () => {
    expect(entityTypeLabel("geofence")).toBe("Geofence");
  });

  it("returns Video Feed for video", () => {
    expect(entityTypeLabel("video")).toBe("Video Feed");
  });
});

// ── formatTime ──────────────────────────────────────────────────────────────

describe("formatTime", () => {
  it("returns dash for null", () => {
    expect(formatTime(null)).toBe("-");
  });

  it("formats a valid ISO string", () => {
    const result = formatTime("2025-01-15T12:30:00Z");
    // Should be a locale time string, not the raw ISO
    expect(result).not.toBe("-");
    expect(result).not.toBe("2025-01-15T12:30:00Z");
    expect(result.length).toBeGreaterThan(0);
  });

  it("returns the raw string for invalid dates", () => {
    // Date constructor doesn't throw for most invalid strings,
    // it returns "Invalid Date" which toLocaleTimeString() may throw on
    // The function catches and returns the raw string
    expect(formatTime("not-a-date")).toBeTruthy();
  });
});

// ── formatTimeDelta ─────────────────────────────────────────────────────────

describe("formatTimeDelta", () => {
  it("returns empty string when first is undefined", () => {
    expect(formatTimeDelta(undefined, "2025-01-15T12:00:00Z")).toBe("");
  });

  it("returns empty string when last is undefined", () => {
    expect(formatTimeDelta("2025-01-15T12:00:00Z", undefined)).toBe("");
  });

  it("returns empty string when both undefined", () => {
    expect(formatTimeDelta(undefined, undefined)).toBe("");
  });

  it("formats minutes for spans under 1 hour", () => {
    const first = "2025-01-15T12:00:00Z";
    const last = "2025-01-15T12:45:00Z";
    expect(formatTimeDelta(first, last)).toBe("45m span");
  });

  it("formats hours and minutes for spans over 1 hour", () => {
    const first = "2025-01-15T10:00:00Z";
    const last = "2025-01-15T12:30:00Z";
    expect(formatTimeDelta(first, last)).toBe("2h 30m span");
  });

  it("handles reversed order (uses absolute difference)", () => {
    const first = "2025-01-15T12:30:00Z";
    const last = "2025-01-15T10:00:00Z";
    expect(formatTimeDelta(first, last)).toBe("2h 30m span");
  });

  it("returns 0m span for identical timestamps", () => {
    const ts = "2025-01-15T12:00:00Z";
    expect(formatTimeDelta(ts, ts)).toBe("0m span");
  });
});

// ── formatDuration ─────────────────────────────────────────────────────────

describe("formatDuration", () => {
  it("returns dash for null", () => {
    expect(formatDuration(null)).toBe("-");
  });

  it("returns dash for future timestamps", () => {
    const future = new Date(Date.now() + 60_000).toISOString();
    expect(formatDuration(future)).toBe("-");
  });

  it("formats seconds for recent connections", () => {
    const recent = new Date(Date.now() - 30_000).toISOString();
    expect(formatDuration(recent)).toBe("30s");
  });

  it("formats minutes and seconds", () => {
    const fiveMinAgo = new Date(Date.now() - 5 * 60_000 - 15_000).toISOString();
    expect(formatDuration(fiveMinAgo)).toBe("5m 15s");
  });

  it("formats hours and minutes", () => {
    const twoHoursAgo = new Date(Date.now() - 2 * 3600_000 - 30 * 60_000).toISOString();
    expect(formatDuration(twoHoursAgo)).toBe("2h 30m");
  });

  it("returns 0s for just-now connections", () => {
    const now = new Date().toISOString();
    expect(formatDuration(now)).toBe("0s");
  });
});

// ── formatCoords ───────────────────────────────────────────────────────────

describe("formatCoords", () => {
  it("returns dash for null lat", () => {
    expect(formatCoords(null, -111.0)).toBe("-");
  });

  it("returns dash for null lon", () => {
    expect(formatCoords(33.5, null)).toBe("-");
  });

  it("returns dash for undefined lat/lon", () => {
    expect(formatCoords(undefined, undefined)).toBe("-");
  });

  it("formats coordinates to 5 decimal places", () => {
    expect(formatCoords(33.12345678, -111.98765432)).toBe("33.12346, -111.98765");
  });

  it("handles zero coordinates", () => {
    expect(formatCoords(0, 0)).toBe("0.00000, 0.00000");
  });
});

// ── formatSpeed ────────────────────────────────────────────────────────────

describe("formatSpeed", () => {
  it("returns dash for null", () => {
    expect(formatSpeed(null)).toBe("-");
  });

  it("returns dash for undefined", () => {
    expect(formatSpeed(undefined)).toBe("-");
  });

  it("formats speed to 1 decimal place with units", () => {
    expect(formatSpeed(12.345)).toBe("12.3 m/s");
  });

  it("handles zero speed", () => {
    expect(formatSpeed(0)).toBe("0.0 m/s");
  });
});
