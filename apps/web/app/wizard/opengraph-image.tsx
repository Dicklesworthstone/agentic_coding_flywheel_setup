import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Setup Wizard - From Laptop to Agentic Powerhouse in 13 Steps";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

// Wizard steps for the visual
const STEPS = [
  "OS Selection",
  "Terminal",
  "SSH Key",
  "Rent VPS",
  "Create VPS",
  "SSH Connect",
  "Run Installer",
  "Reconnect",
  "Status Check",
  "Key Verify",
  "Onboarding",
  "Accounts",
  "Complete",
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
        {/* Grid pattern overlay */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%23f59e0b' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - amber theme */}
        <div
          style={{
            position: "absolute",
            top: -150,
            left: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(245,158,11,0.18) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(251,146,60,0.12) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 150,
            right: 300,
            width: 300,
            height: 300,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(251,191,36,0.08) 0%, transparent 60%)",
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
          {/* Left side - Terminal/Rocket visual */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              position: "relative",
            }}
          >
            {/* Outer glow ring */}
            <div
              style={{
                position: "absolute",
                width: 260,
                height: 260,
                borderRadius: "50%",
                background:
                  "radial-gradient(circle, rgba(245,158,11,0.25) 0%, rgba(251,146,60,0.15) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Terminal SVG icon */}
            <svg
              width="200"
              height="200"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 30px rgba(245,158,11,0.4))",
              }}
            >
              <defs>
                <linearGradient id="termGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#f59e0b" />
                  <stop offset="50%" stopColor="#fb923c" />
                  <stop offset="100%" stopColor="#fbbf24" />
                </linearGradient>
              </defs>

              {/* Terminal window frame */}
              <rect
                x="15"
                y="20"
                width="70"
                height="55"
                rx="6"
                fill="rgba(15,20,25,0.9)"
                stroke="url(#termGrad)"
                strokeWidth="2"
              />

              {/* Title bar */}
              <rect
                x="15"
                y="20"
                width="70"
                height="12"
                rx="6"
                fill="rgba(245,158,11,0.15)"
              />
              <circle cx="24" cy="26" r="2.5" fill="#ef4444" />
              <circle cx="32" cy="26" r="2.5" fill="#f59e0b" />
              <circle cx="40" cy="26" r="2.5" fill="#22c55e" />

              {/* Terminal prompt lines */}
              <text
                x="22"
                y="44"
                fill="#f59e0b"
                fontSize="8"
                fontFamily="monospace"
              >
                $ curl | bash
              </text>
              <text
                x="22"
                y="54"
                fill="#94a3b8"
                fontSize="7"
                fontFamily="monospace"
              >
                Installing...
              </text>
              <text
                x="22"
                y="64"
                fill="#22c55e"
                fontSize="7"
                fontFamily="monospace"
              >
                Done!
              </text>

              {/* Rocket launching from terminal */}
              <g transform="translate(60, 5)">
                <path
                  d="M10 30 L15 20 L20 30 L17 30 L17 38 L13 38 L13 30 Z"
                  fill="url(#termGrad)"
                />
                <path
                  d="M13 38 L15 42 L17 38"
                  fill="#fb923c"
                  opacity="0.8"
                />
                {/* Flame */}
                <path
                  d="M13 42 L15 50 L17 42"
                  fill="#ef4444"
                  opacity="0.6"
                />
              </g>
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
                background: "rgba(245,158,11,0.1)",
                border: "1px solid rgba(245,158,11,0.3)",
              }}
            >
              <div
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: "50%",
                  background: "#22c55e",
                  display: "flex",
                }}
              />
              <span
                style={{
                  fontSize: 14,
                  color: "#f59e0b",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Guided Setup
              </span>
            </div>

            {/* Title */}
            <h1
              style={{
                fontSize: 58,
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
              Setup Wizard
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 24,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #f59e0b 0%, #fb923c 50%, #fbbf24 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
                display: "flex",
              }}
            >
              From Laptop to Agentic Powerhouse
            </p>

            {/* Description */}
            <p
              style={{
                fontSize: 18,
                color: "#94a3b8",
                margin: 0,
                marginBottom: 28,
                lineHeight: 1.5,
                display: "flex",
              }}
            >
              13 guided steps to configure your VPS with Claude, Codex, Gemini,
              and 30+ developer tools
            </p>

            {/* Progress visualization */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 6,
              }}
            >
              {STEPS.slice(0, 8).map((_, i) => (
                <div
                  key={i}
                  style={{
                    width: 32,
                    height: 6,
                    borderRadius: 3,
                    background:
                      i < 3
                        ? "linear-gradient(90deg, #f59e0b, #fb923c)"
                        : "rgba(100,116,139,0.3)",
                    display: "flex",
                  }}
                />
              ))}
              <span
                style={{
                  marginLeft: 8,
                  fontSize: 14,
                  color: "#64748b",
                  display: "flex",
                }}
              >
                +5 more
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
              "linear-gradient(90deg, transparent 0%, #f59e0b 25%, #fb923c 50%, #fbbf24 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/wizard</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
