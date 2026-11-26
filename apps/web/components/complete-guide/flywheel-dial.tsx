import { cn } from "@/lib/utils";

// The flywheel dial: the visual signature of the guides (their covers,
// closing call to action, and the guide covers on the landing page).

const DIAL_CENTER = 400;
const BEZEL_RADIUS = 334;

/** A point on the dial; 0° is three o'clock and angles grow clockwise. */
function dialPoint(radius: number, deg: number) {
  const rad = (deg * Math.PI) / 180;
  return {
    x: Number((DIAL_CENTER + Math.cos(rad) * radius).toFixed(1)),
    y: Number((DIAL_CENTER + Math.sin(rad) * radius).toFixed(1)),
  };
}

function dialTicks(): string {
  const parts: string[] = [];
  for (let i = 0; i < 120; i++) {
    const deg = (i / 120) * 360;
    const inner = dialPoint(i % 10 === 0 ? 312 : 322, deg);
    const outer = dialPoint(BEZEL_RADIUS, deg);
    parts.push(`M${inner.x} ${inner.y}L${outer.x} ${outer.y}`);
  }
  return parts.join("");
}

function arcPath(radius: number, fromDeg: number, toDeg: number): string {
  const from = dialPoint(radius, fromDeg);
  const to = dialPoint(radius, toDeg);
  const large = toDeg - fromDeg > 180 ? 1 : 0;
  return `M${from.x} ${from.y}A${radius} ${radius} 0 ${large} 1 ${to.x} ${to.y}`;
}

const TICKS = dialTicks();

/**
 * A tick-marked bezel, three rings, the three nodes of the core loop, and a
 * momentum arc sweeping clockwise from `arc[0]` to `arc[1]` degrees, fading in
 * from its tail. When `animated`, the dial spins up on first paint and the arc
 * draws itself in (motion-safe only: see .guide-dial in globals.css).
 */
export function FlywheelDial({
  id,
  arc,
  nodes = true,
  outerRing = true,
  animated = true,
  className,
}: {
  /** Unique on the page: names the arc's gradient. */
  id: string;
  arc: readonly [number, number];
  /** The three node dots; off where they would land on running text. */
  nodes?: boolean;
  /** The hairline outside the bezel; off where it would cross a control. */
  outerRing?: boolean;
  /** Off for a dial that starts out of view, where the spin-up would be missed. */
  animated?: boolean;
  className?: string;
}) {
  const [from, to] = arc;
  const tail = dialPoint(BEZEL_RADIUS, from);
  const head = dialPoint(BEZEL_RADIUS, to);
  const gradientId = `${id}-momentum`;
  return (
    <svg viewBox="0 0 800 800" fill="none" aria-hidden="true" className={cn(animated && "guide-dial", className)}>
      <defs>
        <linearGradient
          id={gradientId}
          gradientUnits="userSpaceOnUse"
          x1={tail.x}
          y1={tail.y}
          x2={head.x}
          y2={head.y}
        >
          <stop offset="0" stopColor="#FF5500" stopOpacity="0" />
          <stop offset="0.6" stopColor="#FF5500" stopOpacity="0.5" />
          <stop offset="1" stopColor="#FF7A33" stopOpacity="0.95" />
        </linearGradient>
      </defs>
      {outerRing && <circle cx="400" cy="400" r="396" stroke="currentColor" strokeWidth="1" />}
      <path d={TICKS} stroke="currentColor" strokeWidth="1.5" />
      <circle cx="400" cy="400" r="250" stroke="currentColor" strokeWidth="1" />
      <circle cx="400" cy="400" r="160" stroke="currentColor" strokeWidth="1" />
      <circle cx="400" cy="400" r="70" stroke="currentColor" strokeWidth="1" />
      <path
        className={animated ? "guide-dial-arc" : undefined}
        d={arcPath(BEZEL_RADIUS, from, to)}
        pathLength={1}
        stroke={`url(#${gradientId})`}
        strokeWidth="3"
        strokeLinecap="round"
      />
      <g className={animated ? "guide-dial-head" : undefined}>
        <circle cx={head.x} cy={head.y} r="22" fill="#FF5500" fillOpacity="0.12" />
        <circle cx={head.x} cy={head.y} r="7" fill="#FF5500" />
      </g>
      {nodes && (
        <>
          <circle cx="400" cy="150" r="5" fill="currentColor" />
          <circle cx="616.5" cy="525" r="5" fill="currentColor" />
          <circle cx="183.5" cy="525" r="5" fill="currentColor" />
        </>
      )}
    </svg>
  );
}
