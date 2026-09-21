import { ImageResponse } from "next/og";

export const runtime = "edge";

export const size = {
  width: 32,
  height: 32,
};
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "linear-gradient(135deg, #0a0a12 0%, #1a1a2e 100%)",
        borderRadius: 6,
      }}
    >
      {/* Simplified flywheel icon */}
      <svg width="24" height="24" viewBox="0 0 100 100" fill="none">
        <defs>
          <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#22d3ee" />
            <stop offset="50%" stopColor="#a855f7" />
            <stop offset="100%" stopColor="#f472b6" />
          </linearGradient>
        </defs>

        {/* Outer ring */}
        <circle cx="50" cy="50" r="42" stroke="url(#iconGrad)" strokeWidth="6" fill="none" />

        {/* Center */}
        <circle cx="50" cy="50" r="12" fill="#22d3ee" />

        {/* Spokes */}
        <line
          x1="50"
          y1="20"
          x2="50"
          y2="38"
          stroke="#22d3ee"
          strokeWidth="4"
          strokeLinecap="round"
        />
        <line
          x1="50"
          y1="62"
          x2="50"
          y2="80"
          stroke="#f472b6"
          strokeWidth="4"
          strokeLinecap="round"
        />
        <line
          x1="20"
          y1="50"
          x2="38"
          y2="50"
          stroke="#22c55e"
          strokeWidth="4"
          strokeLinecap="round"
        />
        <line
          x1="62"
          y1="50"
          x2="80"
          y2="50"
          stroke="#a855f7"
          strokeWidth="4"
          strokeLinecap="round"
        />
      </svg>
    </div>,
    {
      ...size,
    },
  );
}
