import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Setup Wizard - From Laptop to Agentic Powerhouse";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

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
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%23f59e0b' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orb - amber */}
        <div
          style={{
            position: "absolute",
            top: -120,
            right: -80,
            width: 400,
            height: 400,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(245,158,11,0.2) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(251,146,60,0.12) 0%, transparent 60%)",
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
              marginBottom: 20,
              padding: "6px 14px",
              borderRadius: 16,
              background: "rgba(245,158,11,0.1)",
              border: "1px solid rgba(245,158,11,0.25)",
            }}
          >
            <div
              style={{
                width: 6,
                height: 6,
                borderRadius: "50%",
                background: "#22c55e",
                display: "flex",
              }}
            />
            <span
              style={{
                fontSize: 12,
                color: "#f59e0b",
                fontWeight: 600,
                letterSpacing: "0.08em",
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
            Setup Wizard
          </h1>

          {/* Subtitle */}
          <p
            style={{
              fontSize: 22,
              fontWeight: 600,
              background:
                "linear-gradient(90deg, #f59e0b 0%, #fb923c 50%, #fbbf24 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 20,
              display: "flex",
            }}
          >
            From Laptop to Agentic Powerhouse
          </p>

          {/* Description */}
          <p
            style={{
              fontSize: 16,
              color: "#94a3b8",
              margin: 0,
              marginBottom: 24,
              lineHeight: 1.5,
              display: "flex",
            }}
          >
            13 guided steps • VPS setup • Agent configuration • 30+ tools
          </p>

          {/* Step indicators */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 5,
            }}
          >
            {[...Array(13)].map((_, i) => (
              <div
                key={i}
                style={{
                  width: 24,
                  height: 5,
                  borderRadius: 2.5,
                  background:
                    i < 4
                      ? "linear-gradient(90deg, #f59e0b, #fb923c)"
                      : "rgba(100,116,139,0.3)",
                  display: "flex",
                }}
              />
            ))}
          </div>
        </div>

        {/* Right - Terminal Visual */}
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
              width: 280,
              height: 280,
              borderRadius: "50%",
              background:
                "radial-gradient(circle, rgba(245,158,11,0.25) 0%, rgba(251,146,60,0.15) 40%, transparent 70%)",
              filter: "blur(35px)",
              display: "flex",
            }}
          />

          {/* Terminal SVG */}
          <svg
            width="220"
            height="220"
            viewBox="0 0 100 100"
            fill="none"
            style={{
              filter: "drop-shadow(0 0 25px rgba(245,158,11,0.35))",
            }}
          >
            <defs>
              <linearGradient id="tTermGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#f59e0b" />
                <stop offset="50%" stopColor="#fb923c" />
                <stop offset="100%" stopColor="#fbbf24" />
              </linearGradient>
            </defs>

            {/* Terminal frame */}
            <rect
              x="12"
              y="18"
              width="76"
              height="58"
              rx="8"
              fill="rgba(15,20,25,0.9)"
              stroke="url(#tTermGrad)"
              strokeWidth="2.5"
            />

            {/* Title bar */}
            <rect
              x="12"
              y="18"
              width="76"
              height="14"
              rx="8"
              fill="rgba(245,158,11,0.12)"
            />
            <circle cx="22" cy="25" r="3" fill="#ef4444" />
            <circle cx="31" cy="25" r="3" fill="#f59e0b" />
            <circle cx="40" cy="25" r="3" fill="#22c55e" />

            {/* Terminal lines */}
            <text x="20" y="46" fill="#f59e0b" fontSize="9" fontFamily="monospace">
              $ acfs install
            </text>
            <text x="20" y="58" fill="#94a3b8" fontSize="8" fontFamily="monospace">
              [======&gt;    ] 60%
            </text>
            <text x="20" y="68" fill="#22c55e" fontSize="8" fontFamily="monospace">
              Ready!
            </text>

            {/* Rocket */}
            <g transform="translate(65, 2)">
              <path
                d="M8 28 L13 16 L18 28 L15 28 L15 38 L11 38 L11 28 Z"
                fill="url(#tTermGrad)"
              />
              <path d="M11 38 L13 44 L15 38" fill="#fb923c" opacity="0.8" />
              <path d="M11 44 L13 52 L15 44" fill="#ef4444" opacity="0.5" />
            </g>
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
              "linear-gradient(90deg, transparent 0%, #f59e0b 25%, #fb923c 50%, #fbbf24 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/wizard</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
