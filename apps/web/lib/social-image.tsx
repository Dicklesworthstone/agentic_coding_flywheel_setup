import { ImageResponse } from "next/og";

// One share-card system for every route: a near-black editorial canvas, the
// flywheel dial from the guide covers bleeding off the right edge, and the
// guides' type (Instrument Serif titles, Instrument Sans body, JetBrains Mono
// labels). Each section changes only its accent and what sits on the dial.
//
// Satori rules this file follows (a violation renders an empty 200 response):
// every element is display:flex (or block for clamped text), no .map() or
// conditional children inside <svg>, no <text>/<polygon>/strokeDasharray, and
// colors are hex or rgba strings.

/**
 * The card design's version. Platforms cache a card by its URL, and Next
 * versions that URL by the content of the route file alone (not of this
 * template), so every opengraph-image.tsx and twitter-image.tsx carries a
 * "Share card design N" line. After a visible change to the cards, bump this
 * and those lines together; lib/social-image-routes.test.ts checks they agree.
 */
export const SOCIAL_CARD_DESIGN = 2;

export type SocialImageVariant = "opengraph" | "twitter";
export type SocialImageTheme =
  | "default"
  | "guide"
  | "flywheel"
  | "learn"
  | "wizard"
  | "tools"
  | "workflow"
  | "security"
  | "support"
  | "omarchy";

export type SocialImageStat = { value: string; label: string };

export type SocialImageData = {
  /** Mono eyebrow above the title. */
  badge: string;
  title: string;
  /** Words set after the title in the accent italic. */
  accent?: string;
  description: string;
  path: string;
  theme?: SocialImageTheme;
  /** Up to three figures under the description (takes precedence over tags). */
  stats?: SocialImageStat[];
  /** A wizard position: draws a progress rail and fills the dial's arc. */
  step?: { current: number; total: number };
  /** One shell command, shown as a terminal line (takes precedence over tags). */
  command?: string;
  tags?: string[];
  /** A short mark at the dial's hub: a step or lesson number, or a command. */
  hub?: string;
  hubLabel?: string;
  /** Labels placed around the visible half of the dial (up to six). */
  nodes?: string[];
};

type Palette = {
  /** Strokes, dots and rules. */
  accent: string;
  /** Accent text on the dark canvas (lighter, for contrast). */
  ink: string;
  /** Three stops for the dial's live arc. */
  arc: [string, string, string];
  /** Soft light behind the copy (the dial's glow is drawn from `accent`). */
  haze: string;
  background: string;
};

const PALETTES: Record<SocialImageTheme, Palette> = {
  // The landing page: cyan primary with the "cosmic" gradient.
  default: {
    accent: "#22D3EE",
    ink: "#67E8F9",
    arc: ["#22D3EE", "#C084FC", "#FBBF24"],
    haze: "rgba(192,132,252,0.07)",
    background: "#04070B",
  },
  // The two long-form guides.
  guide: {
    accent: "#FF5500",
    ink: "#FF7A3D",
    arc: ["#FF8A4C", "#FF5500", "#FF5500"],
    haze: "rgba(255,85,0,0.06)",
    background: "#05070B",
  },
  flywheel: {
    accent: "#A78BFA",
    ink: "#C4B5FD",
    arc: ["#22D3EE", "#A78BFA", "#F472B6"],
    haze: "rgba(34,211,238,0.06)",
    background: "#06060C",
  },
  learn: {
    accent: "#2DD4BF",
    ink: "#5EEAD4",
    arc: ["#5EEAD4", "#2DD4BF", "#14B8A6"],
    haze: "rgba(45,212,191,0.06)",
    background: "#03080A",
  },
  wizard: {
    accent: "#F59E0B",
    ink: "#FBBF24",
    arc: ["#FCD34D", "#F59E0B", "#F97316"],
    haze: "rgba(249,115,22,0.06)",
    background: "#070605",
  },
  tools: {
    accent: "#38BDF8",
    ink: "#7DD3FC",
    arc: ["#7DD3FC", "#38BDF8", "#818CF8"],
    haze: "rgba(56,189,248,0.06)",
    background: "#04070B",
  },
  workflow: {
    accent: "#34D399",
    ink: "#6EE7B7",
    arc: ["#6EE7B7", "#34D399", "#2DD4BF"],
    haze: "rgba(52,211,153,0.06)",
    background: "#040806",
  },
  security: {
    accent: "#F43F5E",
    ink: "#FB7185",
    arc: ["#FDA4AF", "#F43F5E", "#E11D48"],
    haze: "rgba(244,63,94,0.06)",
    background: "#090507",
  },
  support: {
    accent: "#818CF8",
    ink: "#A5B4FC",
    arc: ["#A5B4FC", "#818CF8", "#C084FC"],
    haze: "rgba(192,132,252,0.06)",
    background: "#05060C",
  },
  // Tokyo Night, matching the /omarchy hero (Omarchy's default theme).
  omarchy: {
    accent: "#9ECE6A",
    ink: "#9ECE6A",
    arc: ["#7DCFFF", "#9ECE6A", "#BB9AF7"],
    haze: "rgba(122,162,247,0.09)",
    background: "#0B0D16",
  },
};

// -----------------------------------------------------------------------------
// Fonts: static TTFs bundled with the route (Satori cannot read WOFF2).
// -----------------------------------------------------------------------------
type OgFont = {
  name: string;
  data: ArrayBuffer;
  weight: 400 | 500 | 600;
  style: "normal" | "italic";
};

async function readFont(url: URL): Promise<ArrayBuffer> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`[social-image] font ${url.pathname}: HTTP ${response.status}`);
  return response.arrayBuffer();
}

let fontCache: Promise<OgFont[]> | undefined;

function loadFonts(): Promise<OgFont[]> {
  fontCache ??= Promise.all([
    readFont(new URL("../app/fonts/og/InstrumentSerif-Regular.ttf", import.meta.url)),
    readFont(new URL("../app/fonts/og/InstrumentSerif-Italic.ttf", import.meta.url)),
    readFont(new URL("../app/fonts/og/InstrumentSans-Regular.ttf", import.meta.url)),
    readFont(new URL("../app/fonts/og/InstrumentSans-SemiBold.ttf", import.meta.url)),
    readFont(new URL("../app/fonts/og/JetBrainsMono-Medium.ttf", import.meta.url)),
  ]).then(
    ([serif, serifItalic, sans, sansSemiBold, mono]): OgFont[] => [
      { name: "Instrument Serif", data: serif, weight: 400, style: "normal" },
      { name: "Instrument Serif", data: serifItalic, weight: 400, style: "italic" },
      { name: "Instrument Sans", data: sans, weight: 400, style: "normal" },
      { name: "Instrument Sans", data: sansSemiBold, weight: 600, style: "normal" },
      { name: "JetBrains Mono", data: mono, weight: 500, style: "normal" },
    ],
    (error: unknown) => {
      // Let the next request retry instead of caching the failure.
      fontCache = undefined;
      throw error;
    },
  );
  return fontCache;
}

// -----------------------------------------------------------------------------
// Geometry
// -----------------------------------------------------------------------------
const WIDTH = 1200;
const DIAL_SIZE = 600;
const DIAL_HALF = DIAL_SIZE / 2;
/** Dial centre on the canvas: bleeds off the right edge like the guide covers. */
const DIAL_X = 1010;
const BEZEL_RADIUS = 276;
const NODE_RADIUS = 214;
const TEXT_LEFT = 72;
const TEXT_WIDTH = 620;

function polar(radius: number, degrees: number, cx = DIAL_HALF, cy = DIAL_HALF) {
  const radians = (degrees * Math.PI) / 180;
  return { x: cx + Math.cos(radians) * radius, y: cy + Math.sin(radians) * radius };
}

function tickPath(major: boolean): string {
  const parts: string[] = [];
  for (let index = 0; index < 120; index++) {
    if ((index % 10 === 0) !== major) continue;
    const degrees = (index / 120) * 360;
    const inner = polar(major ? 248 : 262, degrees);
    const outer = polar(BEZEL_RADIUS, degrees);
    parts.push(
      `M${inner.x.toFixed(1)} ${inner.y.toFixed(1)}L${outer.x.toFixed(1)} ${outer.y.toFixed(1)}`,
    );
  }
  return parts.join("");
}

const MINOR_TICKS = tickPath(false);
const MAJOR_TICKS = tickPath(true);

/** A full 360° arc has no SVG path (start equals end), and 0° has no end dot. */
function clampSweep(sweep: number): number {
  return Math.min(Math.max(sweep, 2), 359.5);
}

/** The bezel ticks the arc has swept over, as [minor, major] paths. */
function litTickPaths(fromDegrees: number, sweep: number): [string, string] {
  const minor: string[] = [];
  const major: string[] = [];
  for (let index = 0; index < 120; index++) {
    const degrees = (index / 120) * 360;
    // Clockwise distance from the arc's start to this tick.
    const along = (((degrees - fromDegrees) % 360) + 360) % 360;
    if (along > sweep) continue;
    const isMajor = index % 10 === 0;
    const inner = polar(isMajor ? 248 : 262, degrees);
    const outer = polar(BEZEL_RADIUS, degrees);
    (isMajor ? major : minor).push(
      `M${inner.x.toFixed(1)} ${inner.y.toFixed(1)}L${outer.x.toFixed(1)} ${outer.y.toFixed(1)}`,
    );
  }
  return [minor.join("") || "M0 0", major.join("") || "M0 0"];
}

/** Spokes from the hub's rim out to the node ring, one per angle. */
function spokePath(angles: number[], hubRadius: number): string {
  return (
    angles
      .map((degrees) => {
        const inner = polar(hubRadius + 10, degrees);
        const outer = polar(NODE_RADIUS, degrees);
        return `M${inner.x.toFixed(1)} ${inner.y.toFixed(1)}L${outer.x.toFixed(1)} ${outer.y.toFixed(1)}`;
      })
      .join("") || "M0 0"
  );
}

/** Where a plain card's three nodes sit: the triangle of the guides' dial. */
const QUIET_NODE_ANGLES = [150, 270, 30];

/** Clockwise arc on the bezel (screen angles: 90 is down, 180 left, 270 up). */
function arcPath(fromDegrees: number, sweep: number): string {
  const clamped = clampSweep(sweep);
  const start = polar(BEZEL_RADIUS, fromDegrees);
  const end = polar(BEZEL_RADIUS, fromDegrees + clamped);
  const large = clamped > 180 ? 1 : 0;
  return `M${start.x.toFixed(1)} ${start.y.toFixed(1)}A${BEZEL_RADIUS} ${BEZEL_RADIUS} 0 ${large} 1 ${end.x.toFixed(1)} ${end.y.toFixed(1)}`;
}

/** Spread labels over the visible (left) half of the dial, top to bottom. */
function nodeAngles(count: number): number[] {
  if (count <= 1) return [180];
  const first = 256;
  const last = 104;
  return Array.from({ length: count }, (_, index) => first - (index * (first - last)) / (count - 1));
}

// -----------------------------------------------------------------------------
// Text helpers
// -----------------------------------------------------------------------------
function trimText(text: string, maxLength: number): string {
  const normalized = text.trim().replace(/\s+/g, " ");
  if (normalized.length <= maxLength) return normalized;
  const cut = normalized.slice(0, maxLength - 1);
  const lastSpace = cut.lastIndexOf(" ");
  return `${(lastSpace > maxLength * 0.6 ? cut.slice(0, lastSpace) : cut).replace(/[\s,.;:–—-]+$/, "")}…`;
}

/**
 * Lines a greedy wrap would use, from Instrument Serif's average advance (a
 * slight overestimate). Satori never breaks inside a word, so one word wider
 * than the column would overflow into the dial: that counts as too many lines.
 */
function wrappedLines(words: string[], size: number): number {
  const charWidth = size * 0.43;
  const space = size * 0.22;
  const line = TEXT_WIDTH - 12;
  let lines = 1;
  let used = 0;
  for (const word of words) {
    const width = word.length * charWidth;
    if (width > line) return Number.POSITIVE_INFINITY;
    if (used > 0 && used + space + width > line) {
      lines += 1;
      used = width;
    } else {
      used += (used > 0 ? space : 0) + width;
    }
  }
  return lines;
}

/**
 * The largest display size (short titles get bigger) that keeps two lines.
 * A stats row is the tallest footer, so a card with one is capped lower.
 */
function titleSize(words: string[], variant: SocialImageVariant, hasStats: boolean): number {
  const characters = words.join(" ").length;
  let size = characters <= 12 ? 118 : characters <= 18 ? 106 : characters <= 26 ? 94 : 84;
  if (hasStats) size = Math.min(size, 90);
  while (size > 56 && wrappedLines(words, size) > 2) size -= 4;
  return variant === "twitter" ? Math.round(size * 0.95) : size;
}

function hubFontSize(hub: string, numeric: boolean): number {
  if (numeric) return hub.length <= 2 ? 96 : 76;
  return Math.max(24, Math.min(52, Math.floor(118 / (0.6 * hub.length))));
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------
/**
 * The dial. A free-running arc is a momentum trail: it fades in from its tail
 * and lights the bezel ticks it has swept. A wizard arc is a progress gauge
 * from six o'clock, solid along its length. Spokes join the hub to the nodes.
 */
function dialSvg(
  palette: Palette,
  top: number,
  arc: { from: number; sweep: number; trail: boolean },
  hasHub: boolean,
  spokeAngles: number[],
) {
  const sweep = clampSweep(arc.sweep);
  const path = arcPath(arc.from, sweep);
  const tail = polar(BEZEL_RADIUS, arc.from);
  const end = polar(BEZEL_RADIUS, arc.from + sweep);
  const hubRadius = hasHub ? 92 : 64;
  const [litMinor, litMajor] = litTickPaths(arc.from, sweep);
  // A trail's gradient runs from its tail to its head; a gauge's sweeps the
  // whole dial diagonally so a long arc still shows all three stops.
  const gradient = arc.trail
    ? { x1: tail.x.toFixed(1), y1: tail.y.toFixed(1), x2: end.x.toFixed(1), y2: end.y.toFixed(1) }
    : { x1: "0", y1: "600", x2: "600", y2: "0" };
  const tailOpacity = arc.trail ? "0" : "1";
  return (
    <svg
      width={DIAL_SIZE}
      height={DIAL_SIZE}
      viewBox={`0 0 ${DIAL_SIZE} ${DIAL_SIZE}`}
      fill="none"
      style={{ display: "flex", position: "absolute", left: DIAL_X - DIAL_HALF, top }}
    >
      <defs>
        {/* A trail burns brightest at its head, in the accent of the head dot. */}
        <linearGradient id="af-arc" {...gradient} gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor={palette.arc[0]} stopOpacity={tailOpacity} />
          <stop offset="0.5" stopColor={palette.arc[1]} />
          <stop offset="1" stopColor={arc.trail ? palette.ink : palette.arc[2]} />
        </linearGradient>
        <linearGradient id="af-arc-glow" {...gradient} gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor={palette.accent} stopOpacity={arc.trail ? "0" : "0.16"} />
          <stop offset="1" stopColor={palette.accent} stopOpacity={arc.trail ? "0.24" : "0.16"} />
        </linearGradient>
        <radialGradient id="af-glow" cx="300" cy="300" r="300" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor={palette.accent} stopOpacity="0.2" />
          <stop offset="0.55" stopColor={palette.accent} stopOpacity="0.07" />
          <stop offset="1" stopColor={palette.accent} stopOpacity="0" />
        </radialGradient>
      </defs>
      <circle cx="300" cy="300" r="300" fill="url(#af-glow)" />
      <circle cx="300" cy="300" r="297" stroke="#FFFFFF" strokeOpacity="0.07" strokeWidth="1" />
      <path d={MINOR_TICKS} stroke="#FFFFFF" strokeOpacity="0.13" strokeWidth="1.5" />
      <path d={MAJOR_TICKS} stroke="#FFFFFF" strokeOpacity="0.32" strokeWidth="2" />
      <path d={litMinor} stroke={palette.accent} strokeOpacity="0.5" strokeWidth="1.5" />
      <path d={litMajor} stroke={palette.ink} strokeOpacity="0.9" strokeWidth="2" />
      <circle cx="300" cy="300" r={NODE_RADIUS} stroke="#FFFFFF" strokeOpacity="0.09" strokeWidth="1" />
      <circle cx="300" cy="300" r="146" stroke="#FFFFFF" strokeOpacity="0.06" strokeWidth="1" />
      <path d={spokePath(spokeAngles, hubRadius)} stroke="#FFFFFF" strokeOpacity="0.1" strokeWidth="1" />
      <circle
        cx="300"
        cy="300"
        r={hubRadius}
        fill={hasHub ? "#080A10" : "none"}
        stroke="#FFFFFF"
        strokeOpacity="0.14"
        strokeWidth="1"
      />
      {/* An empty hub shows the axle: an accent ring round the pivot (r=0 draws nothing). */}
      <circle
        cx="300"
        cy="300"
        r={hasHub ? 0 : 24}
        fill="#080A10"
        stroke={palette.accent}
        strokeOpacity="0.6"
        strokeWidth="1.5"
      />
      <circle cx="300" cy="300" r={hasHub ? 0 : 6} fill={palette.accent} />
      <path d={path} stroke="url(#af-arc-glow)" strokeWidth="18" strokeLinecap="round" />
      <path d={path} stroke="url(#af-arc)" strokeWidth="4" strokeLinecap="round" />
      <circle cx={end.x.toFixed(1)} cy={end.y.toFixed(1)} r="17" fill={palette.accent} fillOpacity="0.2" />
      <circle cx={end.x.toFixed(1)} cy={end.y.toFixed(1)} r="7.5" fill={palette.accent} />
    </svg>
  );
}

function brandLockup(palette: Palette) {
  return (
    <div style={{ display: "flex", alignItems: "center" }}>
      <svg width="30" height="30" viewBox="0 0 24 24" fill="none" style={{ display: "flex" }}>
        <circle cx="12" cy="12" r="9" stroke="#E4E4E7" strokeWidth="1.75" />
        <circle cx="12" cy="12" r="3.5" stroke="#E4E4E7" strokeWidth="1.75" />
        <circle cx="12" cy="3" r="2.7" fill={palette.accent} />
      </svg>
      <div
        style={{
          display: "flex",
          marginLeft: 14,
          fontFamily: "Instrument Sans",
          fontWeight: 600,
          fontSize: 25,
          letterSpacing: "-0.01em",
          color: "#F4F4F5",
        }}
      >
        Agent Flywheel
      </div>
    </div>
  );
}

function titleBlock(data: SocialImageData, palette: Palette, variant: SocialImageVariant) {
  const plain = data.title.split(/\s+/).filter(Boolean);
  const accented = (data.accent ?? "").split(/\s+/).filter(Boolean);
  const size = titleSize([...plain, ...accented], variant, (data.stats ?? []).length > 0);
  const space = Math.round(size * 0.22);
  const words = [
    ...plain.map((text) => ({ text, accent: false })),
    ...accented.map((text) => ({ text, accent: true })),
  ];
  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        width: TEXT_WIDTH,
        marginTop: 22,
        fontFamily: "Instrument Serif",
        fontSize: size,
        lineHeight: 1,
        letterSpacing: "-0.012em",
        color: "#FAFAFA",
      }}
    >
      {words.map((word, index) => (
        <span
          key={`${word.text}-${index}`}
          style={{
            display: "flex",
            marginRight: index === words.length - 1 ? 0 : space,
            paddingRight: word.accent ? Math.round(size * 0.05) : 0,
            fontStyle: word.accent ? "italic" : "normal",
            color: word.accent ? palette.ink : "#FAFAFA",
          }}
        >
          {word.text}
        </span>
      ))}
    </div>
  );
}

function statsRow(stats: SocialImageStat[]) {
  const shown = stats.slice(0, 3);
  return (
    <div style={{ display: "flex", alignItems: "stretch" }}>
      {shown.map((stat, index) => (
        <div
          key={stat.label}
          style={{
            display: "flex",
            flexDirection: "column",
            paddingLeft: index === 0 ? 0 : 30,
            paddingRight: 30,
            borderLeft: index === 0 ? "none" : "1px solid rgba(255,255,255,0.12)",
          }}
        >
          <div
            style={{
              display: "flex",
              fontFamily: "Instrument Serif",
              fontSize: 54,
              lineHeight: 1,
              color: "#FAFAFA",
            }}
          >
            {stat.value}
          </div>
          <div
            style={{
              display: "flex",
              marginTop: 10,
              fontFamily: "JetBrains Mono",
              fontSize: 14,
              letterSpacing: "0.16em",
              color: "#8A8A93",
            }}
          >
            {stat.label.toUpperCase()}
          </div>
        </div>
      ))}
    </div>
  );
}

function stepRail(step: { current: number; total: number }, palette: Palette) {
  const total = Math.max(1, step.total);
  const gap = 6;
  const segment = Math.floor((520 - (total - 1) * gap) / total);
  const slots = Array.from({ length: total }, (_, index) => index + 1);
  return (
    <div style={{ display: "flex", alignItems: "center" }}>
      {slots.map((slot) => (
        <div
          key={slot}
          style={{
            display: "flex",
            width: segment,
            height: slot === step.current ? 8 : 6,
            marginRight: slot === total ? 0 : gap,
            borderRadius: 4,
            background: slot <= step.current ? palette.accent : "rgba(255,255,255,0.1)",
            opacity: slot < step.current ? 0.45 : 1,
          }}
        />
      ))}
      <div
        style={{
          display: "flex",
          marginLeft: 18,
          fontFamily: "JetBrains Mono",
          fontSize: 15,
          letterSpacing: "0.12em",
          color: "#A1A1AA",
        }}
      >
        {`${String(step.current).padStart(2, "0")} / ${String(total).padStart(2, "0")}`}
      </div>
    </div>
  );
}

function commandLine(command: string, palette: Palette) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        alignSelf: "flex-start",
        maxWidth: TEXT_WIDTH,
        padding: "12px 20px",
        borderRadius: 12,
        border: "1px solid rgba(255,255,255,0.12)",
        background: "rgba(255,255,255,0.035)",
        fontFamily: "JetBrains Mono",
        fontSize: 21,
        color: "#E4E4E7",
      }}
    >
      <span style={{ display: "flex", color: palette.ink, marginRight: 14 }}>$</span>
      <span style={{ display: "flex" }}>{trimText(command, 40)}</span>
    </div>
  );
}

function tagRow(tags: string[]) {
  const shown = tags.slice(0, 4);
  return (
    <div style={{ display: "flex", alignItems: "center" }}>
      {shown.map((tag, index) => (
        <div
          key={tag}
          style={{
            display: "flex",
            alignItems: "center",
            marginRight: index === shown.length - 1 ? 0 : 10,
            padding: "8px 16px",
            borderRadius: 999,
            border: "1px solid rgba(255,255,255,0.14)",
            background: "rgba(255,255,255,0.03)",
            fontFamily: "JetBrains Mono",
            fontSize: 16,
            color: "#D4D4D8",
          }}
        >
          {trimText(tag, 22)}
        </div>
      ))}
    </div>
  );
}

function extrasBlock(data: SocialImageData, palette: Palette) {
  if (data.stats && data.stats.length > 0) return statsRow(data.stats);
  if (data.step) return stepRail(data.step, palette);
  if (data.command) return commandLine(data.command, palette);
  if (data.tags && data.tags.length > 0) return tagRow(data.tags);
  return null;
}

// -----------------------------------------------------------------------------
// Renderer
// -----------------------------------------------------------------------------
export async function renderSocialImage(
  data: SocialImageData,
  variant: SocialImageVariant,
): Promise<ImageResponse> {
  const fonts = await loadFonts();
  const height = variant === "twitter" ? 600 : 630;
  const centerY = height / 2;
  const palette = PALETTES[data.theme ?? "default"];
  const twitter = variant === "twitter";

  const step = data.step;
  const arc = step
    ? { from: 90, sweep: (360 * Math.min(step.current, step.total)) / Math.max(1, step.total), trail: false }
    : { from: 164, sweep: 102, trail: true };

  const hub = data.hub ? data.hub.trim() : "";
  const numericHub = /^\d+$/.test(hub);
  const nodes = (data.nodes ?? []).slice(0, 6);
  const chipAngles = nodeAngles(nodes.length);
  const nodeSpots = chipAngles.map((degrees) => polar(NODE_RADIUS, degrees, DIAL_X, centerY));
  const quietAngles = nodes.length === 0 ? QUIET_NODE_ANGLES : [];
  const quietDots = quietAngles.map((degrees) => polar(NODE_RADIUS, degrees, DIAL_X, centerY));

  const extras = extrasBlock(data, palette);
  // The copy is budgeted to two lines (see social-image-routes.test.ts); the
  // trim and the line clamp only guard dynamic lesson and tool text.
  const description = trimText(data.description, 104);
  const domainPath = data.path === "/" ? "" : trimText(data.path, 44);

  return new ImageResponse(
    <div
      style={{
        display: "flex",
        position: "relative",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        background: palette.background,
        color: "#FAFAFA",
        fontFamily: "Instrument Sans",
      }}
    >
      {/* Atmosphere: a faint dot field, a haze behind the copy and a glow at the dial. */}
      <div
        style={{
          display: "flex",
          position: "absolute",
          inset: 0,
          backgroundImage:
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='28' height='28'%3E%3Ccircle cx='1.5' cy='1.5' r='1' fill='white' fill-opacity='0.07'/%3E%3C/svg%3E\")",
        }}
      />
      {/* Satori clips gradients on boxes that overhang the canvas, so the haze
          box stays inside it and the dial glow lives in the dial's SVG. */}
      <div
        style={{
          display: "flex",
          position: "absolute",
          left: 0,
          top: 0,
          width: WIDTH,
          height,
          background: `radial-gradient(circle at 8% 0%, ${palette.haze} 0%, rgba(0,0,0,0) 48%)`,
        }}
      />

      {dialSvg(palette, centerY - DIAL_HALF, arc, hub.length > 0, nodes.length > 0 ? chipAngles : quietAngles)}

      {quietDots.map((spot, index) => (
        <div
          key={`dot-${index}`}
          style={{
            display: "flex",
            position: "absolute",
            left: spot.x - 5,
            top: spot.y - 5,
            width: 10,
            height: 10,
            borderRadius: 999,
            background: "#3F3F46",
          }}
        />
      ))}

      {nodes.map((label, index) => (
        <div
          key={`${label}-${index}`}
          style={{
            display: "flex",
            position: "absolute",
            left: nodeSpots[index].x - 110,
            top: nodeSpots[index].y - 19,
            width: 220,
            height: 38,
            justifyContent: "center",
            alignItems: "center",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              padding: "0 14px",
              height: 36,
              borderRadius: 999,
              border: `1px solid ${palette.accent}`,
              background: "#0A0D14",
              fontFamily: "JetBrains Mono",
              fontSize: 17,
              color: palette.ink,
            }}
          >
            {trimText(label, 16)}
          </div>
        </div>
      ))}

      {hub ? (
        <div
          style={{
            display: "flex",
            position: "absolute",
            left: DIAL_X - 92,
            top: centerY - 92,
            width: 184,
            height: 184,
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              display: "flex",
              fontFamily: numericHub ? "Instrument Serif" : "JetBrains Mono",
              fontSize: hubFontSize(hub, numericHub),
              lineHeight: 1,
              color: numericHub ? "#FAFAFA" : palette.ink,
            }}
          >
            {hub}
          </div>
          {data.hubLabel ? (
            <div
              style={{
                display: "flex",
                marginTop: numericHub ? 6 : 12,
                fontFamily: "JetBrains Mono",
                fontSize: 13,
                letterSpacing: "0.22em",
                color: "#8A8A93",
              }}
            >
              {data.hubLabel.toUpperCase()}
            </div>
          ) : null}
        </div>
      ) : null}

      {/* Copy column */}
      <div
        style={{
          display: "flex",
          position: "absolute",
          left: TEXT_LEFT,
          top: twitter ? 46 : 54,
          bottom: twitter ? 42 : 50,
          width: TEXT_WIDTH,
          flexDirection: "column",
          justifyContent: "space-between",
        }}
      >
        {brandLockup(palette)}

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", alignItems: "center" }}>
            <div style={{ display: "flex", width: 28, height: 2, background: palette.accent }} />
            <div
              style={{
                display: "flex",
                marginLeft: 14,
                fontFamily: "JetBrains Mono",
                fontSize: 17,
                letterSpacing: "0.2em",
                color: palette.ink,
              }}
            >
              {trimText(data.badge, 40).toUpperCase()}
            </div>
          </div>

          {titleBlock(data, palette, variant)}

          <div
            style={{
              display: "block",
              lineClamp: 2,
              width: TEXT_WIDTH,
              marginTop: twitter ? 20 : 24,
              fontSize: 24,
              lineHeight: 1.42,
              color: "#A1A1AA",
            }}
          >
            {description}
          </div>

          {extras ? (
            <div style={{ display: "flex", marginTop: twitter ? 26 : 32 }}>{extras}</div>
          ) : null}
        </div>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            fontFamily: "JetBrains Mono",
            fontSize: 16,
            letterSpacing: "0.04em",
          }}
        >
          <span style={{ display: "flex", color: "#71717A" }}>agent-flywheel.com</span>
          {domainPath ? <span style={{ display: "flex", color: "#D4D4D8" }}>{domainPath}</span> : null}
        </div>
      </div>

      <div
        style={{
          display: "flex",
          position: "absolute",
          left: 0,
          bottom: 0,
          width: WIDTH,
          height: 3,
          background: `linear-gradient(90deg, ${palette.arc[0]} 0%, ${palette.arc[1]} 22%, rgba(0,0,0,0) 62%)`,
        }}
      />
    </div>,
    { width: WIDTH, height, fonts },
  );
}

function createCloudAgentSocialImage(variant: SocialImageVariant): Response {
  // /cloud-agents serves pre-rendered PNGs (regenerate them with
  // `bun run generate:cloud-social-images` after changing its card data or
  // this template). Lazy loading keeps the art out of other routes' hot paths.
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        const { default: images } = await import("./cloud-social-images.json");
        controller.enqueue(Uint8Array.from(atob(images[variant]), (character) => character.charCodeAt(0)));
        controller.close();
      } catch (error) {
        controller.error(error);
      }
    },
  });
  return new Response(body, {
    headers: {
      "content-type": "image/png",
      "cache-control": process.env.NODE_ENV === "development"
        ? "no-cache, no-store"
        : "public, max-age=0, must-revalidate",
    },
  });
}

export async function createSocialImage(
  data: SocialImageData,
  variant: SocialImageVariant,
): Promise<Response> {
  if (data.path === "/cloud-agents") return createCloudAgentSocialImage(variant);
  return renderSocialImage(data, variant);
}
