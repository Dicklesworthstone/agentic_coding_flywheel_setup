import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Glossary - Plain-English Definitions for Agentic Coding Terms";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

// Sample terms to display
const TERMS = [
  { term: "SSH", color: "#0ea5e9" },
  { term: "VPS", color: "#22d3ee" },
  { term: "tmux", color: "#06b6d4" },
  { term: "MCP", color: "#0284c7" },
  { term: "LLM", color: "#38bdf8" },
  { term: "CLI", color: "#7dd3fc" },
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
        {/* Grid pattern overlay - sky blue */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%230ea5e9' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - sky/cyan theme */}
        <div
          style={{
            position: "absolute",
            top: -150,
            left: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(14,165,233,0.18) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(34,211,238,0.12) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(6,182,212,0.08) 0%, transparent 60%)",
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
          {/* Left side - Book/Dictionary visual */}
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
                  "radial-gradient(circle, rgba(14,165,233,0.25) 0%, rgba(34,211,238,0.15) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Book/Dictionary SVG */}
            <svg
              width="220"
              height="220"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 30px rgba(14,165,233,0.4))",
              }}
            >
              <defs>
                <linearGradient id="bookGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#0ea5e9" />
                  <stop offset="50%" stopColor="#22d3ee" />
                  <stop offset="100%" stopColor="#06b6d4" />
                </linearGradient>
              </defs>

              {/* Book spine */}
              <path
                d="M20 15 L20 85 Q20 90 25 90 L75 90 Q80 90 80 85 L80 15 Q80 10 75 10 L25 10 Q20 10 20 15"
                fill="rgba(15,20,25,0.9)"
                stroke="url(#bookGrad)"
                strokeWidth="2"
              />

              {/* Book cover highlight */}
              <path
                d="M25 15 L25 85 L30 85 L30 15 Z"
                fill="rgba(14,165,233,0.2)"
              />

              {/* Page lines */}
              <line x1="35" y1="25" x2="70" y2="25" stroke="#0ea5e9" strokeWidth="1.5" opacity="0.6" />
              <line x1="35" y1="35" x2="65" y2="35" stroke="#22d3ee" strokeWidth="1" opacity="0.4" />
              <line x1="35" y1="43" x2="68" y2="43" stroke="#06b6d4" strokeWidth="1" opacity="0.4" />
              <line x1="35" y1="51" x2="60" y2="51" stroke="#0284c7" strokeWidth="1" opacity="0.4" />
              <line x1="35" y1="59" x2="67" y2="59" stroke="#38bdf8" strokeWidth="1" opacity="0.4" />
              <line x1="35" y1="67" x2="55" y2="67" stroke="#7dd3fc" strokeWidth="1" opacity="0.4" />
              <line x1="35" y1="75" x2="62" y2="75" stroke="#0ea5e9" strokeWidth="1" opacity="0.4" />

              {/* Magnifying glass */}
              <circle cx="72" cy="28" r="10" stroke="url(#bookGrad)" strokeWidth="2" fill="rgba(14,165,233,0.1)" />
              <line x1="79" y1="35" x2="88" y2="44" stroke="url(#bookGrad)" strokeWidth="3" strokeLinecap="round" />
              <text x="68" y="32" fontSize="10" fill="#0ea5e9" fontWeight="bold">A</text>
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
                background: "rgba(14,165,233,0.1)",
                border: "1px solid rgba(14,165,233,0.3)",
              }}
            >
              {/* Book icon */}
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#0ea5e9"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
              </svg>
              <span
                style={{
                  fontSize: 14,
                  color: "#0ea5e9",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Reference
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
              Glossary
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 26,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #0ea5e9 0%, #22d3ee 50%, #06b6d4 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
                display: "flex",
              }}
            >
              Plain-English Definitions
            </p>

            {/* Term pills */}
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                gap: 12,
                marginBottom: 28,
              }}
            >
              {TERMS.map((item, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    padding: "8px 16px",
                    borderRadius: 8,
                    background: `${item.color}15`,
                    border: `1px solid ${item.color}35`,
                  }}
                >
                  <span
                    style={{
                      fontSize: 15,
                      color: item.color,
                      fontWeight: 600,
                      fontFamily: "monospace",
                      display: "flex",
                    }}
                  >
                    {item.term}
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
              <span
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                }}
              >
                <span
                  style={{
                    color: "#0ea5e9",
                    fontWeight: 700,
                    display: "flex",
                  }}
                >
                  50+
                </span>
                Terms
              </span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Shell</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Networking</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Tools</span>
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
              "linear-gradient(90deg, transparent 0%, #0ea5e9 25%, #22d3ee 50%, #06b6d4 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/glossary</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
