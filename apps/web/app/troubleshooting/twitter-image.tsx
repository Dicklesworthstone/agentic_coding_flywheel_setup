import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Troubleshooting - Quick Fixes for Common Issues";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

// Categories to display
const CATEGORIES = [
  { name: "SSH", color: "#22d3ee" },
  { name: "Installation", color: "#facc15" },
  { name: "Agents", color: "#f472b6" },
  { name: "Network", color: "#22c55e" },
];

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "space-between",
          background:
            "linear-gradient(145deg, #0a0a12 0%, #0f1419 40%, #0d1117 70%, #0a0a12 100%)",
          fontFamily: "system-ui, -apple-system, sans-serif",
          position: "relative",
          overflow: "hidden",
          padding: "50px 70px",
        }}
      >
        {/* Grid pattern overlay */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.025,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%23facc15' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs */}
        <div
          style={{
            position: "absolute",
            top: -120,
            right: -80,
            width: 400,
            height: 400,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(250,204,21,0.2) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -150,
            left: -100,
            width: 450,
            height: 450,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(34,197,94,0.12) 0%, transparent 60%)",
            display: "flex",
          }}
        />

        {/* Left content */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            zIndex: 10,
            maxWidth: "58%",
          }}
        >
          {/* Badge */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: 18,
              padding: "6px 14px",
              borderRadius: 16,
              background: "rgba(250,204,21,0.1)",
              border: "1px solid rgba(250,204,21,0.25)",
            }}
          >
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#facc15"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <line x1="9" y1="18" x2="15" y2="18" />
              <line x1="10" y1="22" x2="14" y2="22" />
              <path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14" />
            </svg>
            <span
              style={{
                fontSize: 12,
                color: "#facc15",
                fontWeight: 600,
                letterSpacing: "0.08em",
                textTransform: "uppercase",
                display: "flex",
              }}
            >
              Help Center
            </span>
          </div>

          {/* Title */}
          <h1
            style={{
              fontSize: 52,
              fontWeight: 800,
              background:
                "linear-gradient(135deg, #ffffff 0%, #e2e8f0 50%, #94a3b8 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 6,
              letterSpacing: "-0.03em",
              lineHeight: 1.1,
              display: "flex",
            }}
          >
            Troubleshooting
          </h1>

          {/* Subtitle */}
          <p
            style={{
              fontSize: 22,
              fontWeight: 600,
              background:
                "linear-gradient(90deg, #facc15 0%, #f59e0b 50%, #22c55e 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 20,
              display: "flex",
            }}
          >
            Quick Fixes for Common Issues
          </p>

          {/* Category pills */}
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 10,
              marginBottom: 24,
            }}
          >
            {CATEGORIES.map((cat, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "6px 14px",
                  borderRadius: 6,
                  background: `${cat.color}15`,
                  border: `1px solid ${cat.color}35`,
                }}
              >
                <div
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: "50%",
                    background: cat.color,
                    display: "flex",
                  }}
                />
                <span
                  style={{
                    fontSize: 13,
                    color: cat.color,
                    fontWeight: 600,
                    display: "flex",
                  }}
                >
                  {cat.name}
                </span>
              </div>
            ))}
          </div>

          {/* Stats */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 16,
              fontSize: 14,
              color: "#64748b",
            }}
          >
            <span style={{ display: "flex" }}>Step-by-step solutions</span>
            <span style={{ color: "#374151", display: "flex" }}>•</span>
            <span style={{ display: "flex" }}>Copy-paste commands</span>
          </div>
        </div>

        {/* Right - Visual */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 10,
            position: "relative",
          }}
        >
          {/* Outer glow */}
          <div
            style={{
              position: "absolute",
              width: 260,
              height: 260,
              borderRadius: "50%",
              background:
                "radial-gradient(circle, rgba(250,204,21,0.25) 0%, rgba(34,197,94,0.12) 40%, transparent 70%)",
              filter: "blur(35px)",
              display: "flex",
            }}
          />

          {/* SVG */}
          <svg
            width="200"
            height="200"
            viewBox="0 0 100 100"
            fill="none"
            style={{
              filter: "drop-shadow(0 0 25px rgba(250,204,21,0.35))",
            }}
          >
            <defs>
              <linearGradient id="tWarnGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#facc15" />
                <stop offset="50%" stopColor="#f59e0b" />
                <stop offset="100%" stopColor="#22c55e" />
              </linearGradient>
              <linearGradient id="tSuccessGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#22c55e" />
                <stop offset="100%" stopColor="#10b981" />
              </linearGradient>
            </defs>

            {/* Warning triangle */}
            <g opacity="0.55" transform="translate(2, 18)">
              <path
                d="M22 48 L38 15 L54 48 Z"
                fill="none"
                stroke="#facc15"
                strokeWidth="3"
              />
              <line x1="38" y1="26" x2="38" y2="36" stroke="#facc15" strokeWidth="3" strokeLinecap="round" />
              <circle cx="38" cy="42" r="2.5" fill="#facc15" />
            </g>

            {/* Arrow */}
            <g transform="translate(46, 40)">
              <line x1="0" y1="10" x2="16" y2="10" stroke="url(#tWarnGrad)" strokeWidth="2.5" strokeLinecap="round" />
              <path d="M13 4 L20 10 L13 16" fill="none" stroke="#22c55e" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            </g>

            {/* Success circle */}
            <g transform="translate(60, 18)">
              <circle cx="22" cy="27" r="25" fill="none" stroke="url(#tSuccessGrad)" strokeWidth="3" />
              <path
                d="M10 27 L18 35 L34 18"
                fill="none"
                stroke="#22c55e"
                strokeWidth="3.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </g>

            {/* Decorative dots */}
            <circle cx="12" cy="78" r="4" fill="#facc15" opacity="0.45" />
            <circle cx="88" cy="12" r="4" fill="#22c55e" opacity="0.45" />
          </svg>
        </div>

        {/* Bottom gradient accent */}
        <div
          style={{
            position: "absolute",
            bottom: 0,
            left: 0,
            right: 0,
            height: 4,
            background:
              "linear-gradient(90deg, transparent 0%, #facc15 25%, #f59e0b 50%, #22c55e 75%, transparent 100%)",
            display: "flex",
          }}
        />

        {/* URL */}
        <div
          style={{
            position: "absolute",
            top: 24,
            right: 30,
            display: "flex",
            fontSize: 13,
            color: "#4b5563",
          }}
        >
          <span style={{ display: "flex" }}>agent-flywheel.com/troubleshooting</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
