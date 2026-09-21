import { ImageResponse } from "next/og";

export const runtime = "edge";

export const size = {
  width: 180,
  height: 180,
};
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "linear-gradient(145deg, #0a0a12 0%, #0f1419 50%, #0d1117 100%)",
        borderRadius: 36,
      }}
    >
      {/* Subtle glow behind icon */}
      <div
        style={{
          position: "absolute",
          width: 120,
          height: 120,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(34,211,238,0.25) 0%, transparent 70%)",
          display: "flex",
        }}
      />

      {/* Flywheel icon */}
      <svg
        width="120"
        height="120"
        viewBox="0 0 100 100"
        fill="none"
        style={{ filter: "drop-shadow(0 0 8px rgba(34,211,238,0.4))" }}
      >
        <defs>
          <linearGradient id="appleRingGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#22d3ee" />
            <stop offset="50%" stopColor="#a855f7" />
            <stop offset="100%" stopColor="#f472b6" />
          </linearGradient>
          <linearGradient id="appleCenterGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#22d3ee" />
            <stop offset="100%" stopColor="#06b6d4" />
          </linearGradient>
        </defs>

        {/* Outer ring */}
        <circle
          cx="50"
          cy="50"
          r="44"
          stroke="url(#appleRingGrad)"
          strokeWidth="4"
          fill="none"
          opacity="0.9"
        />

        {/* Inner ring */}
        <circle
          cx="50"
          cy="50"
          r="34"
          stroke="#22d3ee"
          strokeWidth="1.5"
          fill="none"
          opacity="0.4"
        />

        {/* Center hub */}
        <circle cx="50" cy="50" r="14" fill="url(#appleCenterGrad)" opacity="0.95" />
        <circle cx="50" cy="50" r="9" fill="rgba(255,255,255,0.2)" />

        {/* Flywheel nodes - 8 nodes */}
        {[0, 45, 90, 135, 180, 225, 270, 315].map((angle, i) => {
          const rad = (angle * Math.PI) / 180;
          const x = 50 + 39 * Math.cos(rad);
          const y = 50 + 39 * Math.sin(rad);
          const colors = [
            "#22d3ee",
            "#a855f7",
            "#f472b6",
            "#22c55e",
            "#f59e0b",
            "#22d3ee",
            "#a855f7",
            "#f472b6",
          ];
          return (
            <g key={i}>
              {/* Connection line */}
              <line
                x1="50"
                y1="50"
                x2={x}
                y2={y}
                stroke={colors[i]}
                strokeWidth="2"
                opacity="0.5"
              />
              {/* Node */}
              <circle cx={x} cy={y} r="6" fill={colors[i]} opacity="0.95" />
              <circle cx={x} cy={y} r="3.5" fill="rgba(255,255,255,0.3)" />
            </g>
          );
        })}
      </svg>
    </div>,
    {
      ...size,
    },
  );
}
