import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Troubleshooting - Quick Fixes for Common Issues";
export const size = {
  width: 1200,
  height: 630,
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
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background:
            "linear-gradient(145deg, #0a0a12 0%, #0f1419 40%, #0d1117 70%, #0a0a12 100%)",
          fontFamily: "system-ui, -apple-system, sans-serif",
          position: "relative",
          overflow: "hidden",
        }}
      >
        {/* Grid pattern overlay - amber theme */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%23facc15' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - yellow/amber theme */}
        <div
          style={{
            position: "absolute",
            top: -150,
            left: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(250,204,21,0.18) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -200,
            right: -100,
            width: 600,
            height: 600,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(245,158,11,0.12) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 100,
            right: 250,
            width: 300,
            height: 300,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(34,197,94,0.08) 0%, transparent 60%)",
            display: "flex",
          }}
        />

        {/* Main content */}
        <div
          style={{
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            justifyContent: "center",
            gap: 60,
            zIndex: 10,
            padding: "40px 60px",
            width: "100%",
          }}
        >
          {/* Left side - Visual (warning to success transition) */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              position: "relative",
            }}
          >
            {/* Outer glow */}
            <div
              style={{
                position: "absolute",
                width: 280,
                height: 280,
                borderRadius: "50%",
                background:
                  "radial-gradient(circle, rgba(250,204,21,0.25) 0%, rgba(34,197,94,0.15) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Troubleshooting SVG - warning to checkmark */}
            <svg
              width="220"
              height="220"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 30px rgba(250,204,21,0.4))",
              }}
            >
              <defs>
                <linearGradient id="warnGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#facc15" />
                  <stop offset="50%" stopColor="#f59e0b" />
                  <stop offset="100%" stopColor="#22c55e" />
                </linearGradient>
                <linearGradient id="successGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#22c55e" />
                  <stop offset="100%" stopColor="#10b981" />
                </linearGradient>
              </defs>

              {/* Warning triangle (left side, fading) */}
              <g opacity="0.6" transform="translate(5, 20)">
                <path
                  d="M20 45 L35 15 L50 45 Z"
                  fill="none"
                  stroke="#facc15"
                  strokeWidth="2.5"
                />
                <line x1="35" y1="25" x2="35" y2="35" stroke="#facc15" strokeWidth="2.5" strokeLinecap="round" />
                <circle cx="35" cy="40" r="2" fill="#facc15" />
              </g>

              {/* Arrow connecting them */}
              <g transform="translate(45, 40)">
                <line x1="0" y1="10" x2="15" y2="10" stroke="url(#warnGrad)" strokeWidth="2" strokeLinecap="round" />
                <path d="M12 5 L18 10 L12 15" fill="none" stroke="#22c55e" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </g>

              {/* Success checkmark circle (right side, prominent) */}
              <g transform="translate(60, 20)">
                <circle cx="20" cy="25" r="22" fill="none" stroke="url(#successGrad)" strokeWidth="2.5" />
                <path
                  d="M10 25 L17 32 L30 18"
                  fill="none"
                  stroke="#22c55e"
                  strokeWidth="3"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </g>

              {/* Decorative elements */}
              <circle cx="15" cy="75" r="3" fill="#facc15" opacity="0.5" />
              <circle cx="85" cy="15" r="3" fill="#22c55e" opacity="0.5" />
              <circle cx="50" cy="85" r="2" fill="#f59e0b" opacity="0.4" />
            </svg>
          </div>

          {/* Right side - Text content */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "flex-start",
              justifyContent: "center",
              maxWidth: 600,
            }}
          >
            {/* Badge */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                marginBottom: 20,
                padding: "8px 16px",
                borderRadius: 20,
                background: "rgba(250,204,21,0.1)",
                border: "1px solid rgba(250,204,21,0.3)",
              }}
            >
              {/* Lightbulb icon */}
              <svg
                width="16"
                height="16"
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
                  fontSize: 14,
                  color: "#facc15",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
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
                fontSize: 60,
                fontWeight: 800,
                background:
                  "linear-gradient(135deg, #ffffff 0%, #e2e8f0 50%, #94a3b8 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 8,
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
                fontSize: 26,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #facc15 0%, #f59e0b 50%, #22c55e 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
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
                gap: 12,
                marginBottom: 28,
              }}
            >
              {CATEGORIES.map((cat, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    padding: "8px 16px",
                    borderRadius: 8,
                    background: `${cat.color}15`,
                    border: `1px solid ${cat.color}35`,
                  }}
                >
                  <div
                    style={{
                      width: 6,
                      height: 6,
                      borderRadius: "50%",
                      background: cat.color,
                      display: "flex",
                    }}
                  />
                  <span
                    style={{
                      fontSize: 14,
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
                gap: 20,
                fontSize: 16,
                color: "#64748b",
              }}
            >
              <span style={{ display: "flex" }}>Step-by-step solutions</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Copy-paste commands</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                }}
              >
                <span
                  style={{
                    width: 8,
                    height: 8,
                    borderRadius: "50%",
                    background: "#22c55e",
                    display: "flex",
                  }}
                />
                Free
              </span>
            </div>
          </div>
        </div>

        {/* Bottom gradient accent line */}
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

        {/* Corner URL */}
        <div
          style={{
            position: "absolute",
            top: 30,
            right: 40,
            display: "flex",
            fontSize: 14,
            color: "#475569",
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
