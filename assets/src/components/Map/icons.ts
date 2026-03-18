/**
 * Canvas-based icon rendering for CesiumJS billboard entities.
 * Cached per affiliation/state to avoid re-rendering.
 */

export type Affiliation = "friendly" | "hostile" | "neutral" | "unknown" | "emergency";

const AFFILIATION_COLORS: Record<string, string> = {
  friendly: "#2196F3",
  hostile: "#F44336",
  neutral: "#4CAF50",
  unknown: "#4CAF50",
  emergency: "#FF1744",
};

const saIconCache: Record<string, HTMLCanvasElement> = {};

/** Render a 32x32 SA icon (48x48 for emergency): square for friendly/neutral/unknown, diamond for hostile/emergency */
export function getSaIcon(affiliation: Affiliation): HTMLCanvasElement {
  if (saIconCache[affiliation]) return saIconCache[affiliation];

  if (affiliation === "emergency") {
    return _renderEmergencyIcon();
  }

  const s = 32;
  const c = document.createElement("canvas");
  c.width = s;
  c.height = s;
  const ctx = c.getContext("2d")!;
  const color = AFFILIATION_COLORS[affiliation] || AFFILIATION_COLORS.unknown;

  ctx.fillStyle = color;
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.lineWidth = 2;

  if (affiliation === "hostile") {
    const mid = s / 2;
    const pad = 3;
    ctx.beginPath();
    ctx.moveTo(mid, pad);
    ctx.lineTo(s - pad, mid);
    ctx.lineTo(mid, s - pad);
    ctx.lineTo(pad, mid);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  } else {
    const pad = 6;
    ctx.fillRect(pad, pad, s - 2 * pad, s - 2 * pad);
    ctx.strokeRect(pad, pad, s - 2 * pad, s - 2 * pad);
  }

  saIconCache[affiliation] = c;
  return c;
}

/** Render a 48x48 bright emergency diamond icon */
function _renderEmergencyIcon(): HTMLCanvasElement {
  const s = 48;
  const c = document.createElement("canvas");
  c.width = s;
  c.height = s;
  const ctx = c.getContext("2d")!;
  const mid = s / 2;
  const pad = 3;

  // Bright red glow behind diamond
  ctx.shadowColor = "#FF1744";
  ctx.shadowBlur = 10;

  // Diamond shape - bright red
  ctx.fillStyle = "#FF1744";
  ctx.beginPath();
  ctx.moveTo(mid, pad);
  ctx.lineTo(s - pad, mid);
  ctx.lineTo(mid, s - pad);
  ctx.lineTo(pad, mid);
  ctx.closePath();
  ctx.fill();

  // Yellow border
  ctx.shadowBlur = 0;
  ctx.strokeStyle = "#FFD600";
  ctx.lineWidth = 2.5;
  ctx.stroke();

  // Bold yellow "!"
  ctx.fillStyle = "#FFD600";
  ctx.font = "bold 24px sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("!", mid, mid);

  saIconCache["emergency"] = c;
  return c;
}

const pinIconCache: Record<string, HTMLCanvasElement> = {};

/** Render an 18x24 teardrop pin icon for markers */
export function getPinIcon(stale: boolean): HTMLCanvasElement {
  const key = stale ? "stale" : "active";
  if (pinIconCache[key]) return pinIconCache[key];

  const w = 18;
  const h = 24;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d")!;
  const color = "#FF9800";

  ctx.beginPath();
  ctx.moveTo(w / 2, h - 1);
  ctx.bezierCurveTo(w / 2 - 1, h * 0.6, 1, h * 0.42, 1, h * 0.33);
  ctx.arc(w / 2, h * 0.33, w / 2 - 1, Math.PI, 0);
  ctx.bezierCurveTo(w - 1, h * 0.42, w / 2 + 1, h * 0.6, w / 2, h - 1);
  ctx.closePath();
  ctx.fillStyle = color;
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.lineWidth = 1;
  ctx.stroke();

  ctx.beginPath();
  ctx.arc(w / 2, h * 0.33, 3, 0, Math.PI * 2);
  ctx.fillStyle = "#fff";
  ctx.fill();

  pinIconCache[key] = c;
  return c;
}

const videoIconCache: Record<string, HTMLCanvasElement> = {};

/** Render a 28x28 video camera icon for video feed entities */
export function getVideoIcon(active: boolean): HTMLCanvasElement {
  const key = active ? "active" : "inactive";
  if (videoIconCache[key]) return videoIconCache[key];

  const s = 28;
  const c = document.createElement("canvas");
  c.width = s;
  c.height = s;
  const ctx = c.getContext("2d")!;
  const color = active ? "#AB47BC" : "#7B1FA2";

  // Camera body (rounded rect)
  const bx = 2, by = 7, bw = 18, bh = 14, r = 3;
  ctx.beginPath();
  ctx.moveTo(bx + r, by);
  ctx.lineTo(bx + bw - r, by);
  ctx.arcTo(bx + bw, by, bx + bw, by + r, r);
  ctx.lineTo(bx + bw, by + bh - r);
  ctx.arcTo(bx + bw, by + bh, bx + bw - r, by + bh, r);
  ctx.lineTo(bx + r, by + bh);
  ctx.arcTo(bx, by + bh, bx, by + bh - r, r);
  ctx.lineTo(bx, by + r);
  ctx.arcTo(bx, by, bx + r, by, r);
  ctx.closePath();
  ctx.fillStyle = color;
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // Lens triangle (viewfinder)
  ctx.beginPath();
  ctx.moveTo(20, 10);
  ctx.lineTo(26, 7);
  ctx.lineTo(26, 21);
  ctx.lineTo(20, 18);
  ctx.closePath();
  ctx.fillStyle = color;
  ctx.fill();
  ctx.stroke();

  // Small lens circle
  ctx.beginPath();
  ctx.arc(11, 14, 3.5, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(255,255,255,0.7)";
  ctx.lineWidth = 1;
  ctx.stroke();

  videoIconCache[key] = c;
  return c;
}

/** Get the Cesium-compatible CSS color for an affiliation label */
export function affiliationCssColor(affiliation: Affiliation): string {
  return AFFILIATION_COLORS[affiliation] || AFFILIATION_COLORS.unknown;
}

/** Derive affiliation from CoT type string */
export function affiliationFromType(type: string): Affiliation {
  if (type.startsWith("a-f-")) return "friendly";
  if (type.startsWith("a-h-")) return "hostile";
  if (type.startsWith("a-n-")) return "neutral";
  if (type.startsWith("a-u-")) return "unknown";
  return "unknown";
}
