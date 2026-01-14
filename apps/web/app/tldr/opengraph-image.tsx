import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "The Agentic Coding Flywheel - 13 Tools for Multi-Agent AI Coding";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

// All 13 tools with their colors
const TOOLS = [
  { name: "NTM", color: "#38bdf8" },
  { name: "Mail", color: "#8b5cf6" },
  { name: "UBS", color: "#f43f5e" },
  { name: "Beads", color: "#34d399" },
  { name: "CASS", color: "#22d3ee" },
  { name: "CM", color: "#d946ef" },
  { name: "CAAM", color: "#fb923c" },
  { name: "SLB", color: "#fbbf24" },
  { name: "DCG", color: "#ef4444" },
  { name: "RU", color: "#6366f1" },
  { name: "Claude", color: "#fb923c" },
  { name: "Codex", color: "#34d399" },
  { name: "Gemini", color: "#3b82f6" },
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
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%2322d3ee' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - multi-colored */}
        <div
          style={{
            position: "absolute",
            top: -150,
            left: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(34,211,238,0.15) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(168,85,247,0.1) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 100,
            right: 200,
            width: 300,
            height: 300,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(244,114,182,0.08) 0%, transparent 60%)",
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
            gap: 50,
            zIndex: 10,
            padding: "40px 60px",
            width: "100%",
          }}
        >
          {/* Left side - Expanded Flywheel */}
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
                width: 320,
                height: 320,
                borderRadius: "50%",
                background:
                  "radial-gradient(circle, rgba(34,211,238,0.2) 0%, rgba(168,85,247,0.12) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Flywheel SVG with all 13 tools */}
            <svg
              width="280"
              height="280"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 25px rgba(34,211,238,0.3))",
              }}
            >
              <defs>
                <linearGradient id="tldrRingGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#22d3ee" />
                  <stop offset="33%" stopColor="#a855f7" />
                  <stop offset="66%" stopColor="#f472b6" />
                  <stop offset="100%" stopColor="#22d3ee" />
                </linearGradient>
              </defs>

              {/* Outer ring */}
              <circle
                cx="50"
                cy="50"
                r="47"
                stroke="url(#tldrRingGrad)"
                strokeWidth="1.5"
                fill="none"
                opacity="0.6"
              />

              {/* Middle ring */}
              <circle
                cx="50"
                cy="50"
                r="38"
                stroke="#22d3ee"
                strokeWidth="1"
                fill="none"
                opacity="0.3"
              />

              {/* Center hub */}
              <circle cx="50" cy="50" r="10" fill="#22d3ee" opacity="0.8" />
              <circle cx="50" cy="50" r="6" fill="rgba(255,255,255,0.3)" />

              {/* 13 tool nodes around the circle */}
              {TOOLS.map((tool, i) => {
                const angle = (i * 360) / 13 - 90; // Start from top
                const rad = (angle * Math.PI) / 180;
                const x = 50 + 42 * Math.cos(rad);
                const y = 50 + 42 * Math.sin(rad);
                return (
                  <g key={i}>
                    <line
                      x1="50"
                      y1="50"
                      x2={x}
                      y2={y}
                      stroke={tool.color}
                      strokeWidth="1.2"
                      opacity="0.4"
                    />
                    <circle cx={x} cy={y} r="4.5" fill={tool.color} opacity="0.9" />
                    <circle cx={x} cy={y} r="2.5" fill="rgba(255,255,255,0.25)" />
                  </g>
                );
              })}

              {/* Motion arrows */}
              <path d="M50 5 L54 11 L46 11 Z" fill="#22d3ee" opacity="0.6" />
              <path d="M95 50 L89 54 L89 46 Z" fill="#a855f7" opacity="0.6" />
              <path d="M50 95 L46 89 L54 89 Z" fill="#f472b6" opacity="0.6" />
              <path d="M5 50 L11 46 L11 54 Z" fill="#22c55e" opacity="0.6" />
            </svg>
          </div>

          {/* Right side - Content */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "flex-start",
              justifyContent: "center",
              maxWidth: 580,
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
                background: "rgba(34,211,238,0.1)",
                border: "1px solid rgba(34,211,238,0.3)",
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
                  color: "#22d3ee",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Quick Overview
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
                marginBottom: 8,
                letterSpacing: "-0.03em",
                lineHeight: 1.1,
                display: "flex",
              }}
            >
              The Agentic Coding Flywheel
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 26,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #22d3ee 0%, #a855f7 50%, #f472b6 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
                display: "flex",
              }}
            >
              13 Tools. Infinite Velocity.
            </p>

            {/* Tool pills - first row */}
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                gap: 10,
                marginBottom: 12,
              }}
            >
              {TOOLS.slice(0, 7).map((tool, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    padding: "5px 12px",
                    borderRadius: 6,
                    background: `${tool.color}18`,
                    border: `1px solid ${tool.color}40`,
                  }}
                >
                  <div
                    style={{
                      width: 6,
                      height: 6,
                      borderRadius: "50%",
                      background: tool.color,
                      display: "flex",
                    }}
                  />
                  <span
                    style={{
                      fontSize: 12,
                      color: tool.color,
                      fontWeight: 600,
                      display: "flex",
                    }}
                  >
                    {tool.name}
                  </span>
                </div>
              ))}
            </div>

            {/* Tool pills - second row */}
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                gap: 10,
                marginBottom: 24,
              }}
            >
              {TOOLS.slice(7).map((tool, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    padding: "5px 12px",
                    borderRadius: 6,
                    background: `${tool.color}18`,
                    border: `1px solid ${tool.color}40`,
                  }}
                >
                  <div
                    style={{
                      width: 6,
                      height: 6,
                      borderRadius: "50%",
                      background: tool.color,
                      display: "flex",
                    }}
                  />
                  <span
                    style={{
                      fontSize: 12,
                      color: tool.color,
                      fontWeight: 600,
                      display: "flex",
                    }}
                  >
                    {tool.name}
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
                fontSize: 15,
                color: "#64748b",
              }}
            >
              <span style={{ display: "flex" }}>13 Tools</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Open Source</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Multi-Agent Ready</span>
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
              "linear-gradient(90deg, transparent 0%, #22d3ee 25%, #a855f7 50%, #f472b6 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/tldr</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
