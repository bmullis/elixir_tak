import { describe, it, expect } from "vitest";
import {
  getCallsign,
  classifyEntity,
  affiliationFromType,
  hasActiveEmergency,
  classifyEntityToLayer,
} from "./entityClassification";
import type { CotEvent } from "../types";

// ── getCallsign ─────────────────────────────────────────────────────────────

describe("getCallsign", () => {
  const base: CotEvent = {
    uid: "uid-1",
    type: "a-f-G-U-C",
    how: "m-g",
    time: null,
    start: null,
    stale: null,
    point: null,
    detail: null,
    raw_detail: null,
    group: null,
  };

  it("returns fallback when detail is null", () => {
    expect(getCallsign(base, "FALLBACK")).toBe("FALLBACK");
  });

  it("returns contact.callsign when present", () => {
    const event = { ...base, detail: { contact: { callsign: "Alpha-1" } } };
    expect(getCallsign(event, "FALLBACK")).toBe("Alpha-1");
  });

  it("returns top-level callsign when contact.callsign is missing", () => {
    const event = { ...base, detail: { callsign: "Bravo-2" } };
    expect(getCallsign(event, "FALLBACK")).toBe("Bravo-2");
  });

  it("returns fallback when detail exists but has no callsign", () => {
    const event = { ...base, detail: {} };
    expect(getCallsign(event, "FALLBACK")).toBe("FALLBACK");
  });

  it("returns fallback when callsign is empty string", () => {
    const event = { ...base, detail: { callsign: "" } };
    expect(getCallsign(event, "FALLBACK")).toBe("FALLBACK");
  });
});

// ── classifyEntity ──────────────────────────────────────────────────────────

describe("classifyEntity", () => {
  it("classifies marker entities", () => {
    expect(classifyEntity("marker-abc123")).toEqual({
      uid: "abc123",
      entityType: "marker",
    });
  });

  it("classifies shape entities", () => {
    expect(classifyEntity("shape-xyz")).toEqual({
      uid: "xyz",
      entityType: "shape",
    });
  });

  it("classifies route entities", () => {
    expect(classifyEntity("route-r1")).toEqual({
      uid: "r1",
      entityType: "route",
    });
  });

  it("classifies geofence entities", () => {
    expect(classifyEntity("geofence-g1")).toEqual({
      uid: "g1",
      entityType: "geofence",
    });
  });

  it("classifies video entities", () => {
    expect(classifyEntity("video-v1")).toEqual({
      uid: "v1",
      entityType: "video",
    });
  });

  it("classifies bare uid as SA entity", () => {
    expect(classifyEntity("ANDROID-abc123")).toEqual({
      uid: "ANDROID-abc123",
      entityType: "sa",
    });
  });

  // Sub-entities that should return null
  it("returns null for shape-label", () => {
    expect(classifyEntity("shape-label-xyz")).toBeNull();
  });

  it("returns null for route-label", () => {
    expect(classifyEntity("route-label-r1")).toBeNull();
  });

  it("returns null for geofence-label", () => {
    expect(classifyEntity("geofence-label-g1")).toBeNull();
  });

  it("returns null for emergency-ring", () => {
    expect(classifyEntity("emergency-ring-e1")).toBeNull();
  });

  it("returns null for waypoint entities", () => {
    expect(classifyEntity("route1_wp_3")).toBeNull();
  });

  it("returns null for video-fov", () => {
    expect(classifyEntity("video-fov-v1")).toBeNull();
  });

  it("returns null for track entities", () => {
    expect(classifyEntity("track-line-uid1")).toBeNull();
    expect(classifyEntity("track-dot-uid1-5")).toBeNull();
  });
});

// ── affiliationFromType ─────────────────────────────────────────────────────

describe("affiliationFromType", () => {
  it("identifies friendly", () => {
    expect(affiliationFromType("a-f-G-U-C")).toBe("friendly");
  });

  it("identifies hostile", () => {
    expect(affiliationFromType("a-h-G")).toBe("hostile");
  });

  it("identifies neutral", () => {
    expect(affiliationFromType("a-n-G")).toBe("neutral");
  });

  it("identifies unknown", () => {
    expect(affiliationFromType("a-u-G")).toBe("unknown");
  });

  it("defaults to unknown for non-atom types", () => {
    expect(affiliationFromType("b-m-p-s-m")).toBe("unknown");
  });
});

// ── hasActiveEmergency ──────────────────────────────────────────────────────

describe("hasActiveEmergency", () => {
  it("returns false for null", () => {
    expect(hasActiveEmergency(null)).toBe(false);
  });

  it("returns false for no emergency tag", () => {
    expect(hasActiveEmergency("<detail><contact callsign='A'/></detail>")).toBe(false);
  });

  it("returns true for active emergency", () => {
    expect(hasActiveEmergency('<detail><emergency type="911">help</emergency></detail>')).toBe(true);
  });

  it("returns true for self-closing emergency", () => {
    expect(hasActiveEmergency('<detail><emergency type="911"/></detail>')).toBe(true);
  });

  it("returns false for cancelled emergency", () => {
    expect(
      hasActiveEmergency('<detail><emergency cancel="true" type="911"/></detail>')
    ).toBe(false);
  });
});

// ── classifyEntityToLayer ───────────────────────────────────────────────────

describe("classifyEntityToLayer", () => {
  const positions = new Map<string, CotEvent>();

  it("classifies emergency-ring entities", () => {
    expect(classifyEntityToLayer("emergency-ring-e1", positions)).toBe("emergency");
  });

  it("classifies track entities", () => {
    expect(classifyEntityToLayer("track-line-uid1", positions)).toBe("track");
    expect(classifyEntityToLayer("track-dot-uid1-3", positions)).toBe("track");
  });

  it("classifies geofence entities", () => {
    expect(classifyEntityToLayer("geofence-g1", positions)).toBe("geofence");
    expect(classifyEntityToLayer("geofence-label-g1", positions)).toBe("geofence");
  });

  it("classifies route entities", () => {
    expect(classifyEntityToLayer("route-r1", positions)).toBe("route");
    expect(classifyEntityToLayer("route-label-r1", positions)).toBe("route");
    expect(classifyEntityToLayer("r1_wp_0", positions)).toBe("route");
  });

  it("classifies shape entities", () => {
    expect(classifyEntityToLayer("shape-s1", positions)).toBe("shape");
    expect(classifyEntityToLayer("shape-label-s1", positions)).toBe("shape");
  });

  it("classifies marker entities", () => {
    expect(classifyEntityToLayer("marker-m1", positions)).toBe("marker");
  });

  it("classifies video entities", () => {
    expect(classifyEntityToLayer("video-v1", positions)).toBe("video");
    expect(classifyEntityToLayer("video-fov-v1", positions)).toBe("video");
  });

  it("classifies SA entities by affiliation", () => {
    const saEvent: CotEvent = {
      uid: "sa-uid-1",
      type: "a-f-G-U-C",
      how: "m-g",
      time: null,
      start: null,
      stale: null,
      point: { lat: 33.49, lon: -111.93, hae: null, ce: null, le: null },
      detail: null,
      raw_detail: null,
      group: null,
    };

    const positionsWithSa = new Map<string, CotEvent>([["sa-uid-1", saEvent]]);

    expect(classifyEntityToLayer("sa-uid-1", positionsWithSa)).toBe("sa-friendly");
  });

  it("classifies SA entity with hostile type", () => {
    const hostile: CotEvent = {
      uid: "h1",
      type: "a-h-G",
      how: null,
      time: null,
      start: null,
      stale: null,
      point: null,
      detail: null,
      raw_detail: null,
      group: null,
    };
    const m = new Map([["h1", hostile]]);
    expect(classifyEntityToLayer("h1", m)).toBe("sa-hostile");
  });

  it("classifies SA entity with emergency as emergency layer", () => {
    const emergency: CotEvent = {
      uid: "e1",
      type: "a-f-G-U-C",
      how: null,
      time: null,
      start: null,
      stale: null,
      point: null,
      detail: null,
      raw_detail: '<detail><emergency type="911">help</emergency></detail>',
      group: null,
    };
    const m = new Map([["e1", emergency]]);
    expect(classifyEntityToLayer("e1", m)).toBe("emergency");
  });

  it("returns null for unknown entity ids", () => {
    expect(classifyEntityToLayer("unknown-id", positions)).toBeNull();
  });
});
