import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Glossary - Plain-English Definitions for Agentic Coding Terms";
export const size = {
  width: 1200,
  height: 600,
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
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%230ea5e9' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
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
              "radial-gradient(circle, rgba(14,165,233,0.2) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(34,211,238,0.12) 0%, transparent 60%)",
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
              background: "rgba(14,165,233,0.1)",
              border: "1px solid rgba(14,165,233,0.25)",
            }}
          >
            <svg
              width="14"
              height="14"
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
                fontSize: 12,
                color: "#0ea5e9",
                fontWeight: 600,
                letterSpacing: "0.08em",
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
            Glossary
          </h1>

          {/* Subtitle */}
          <p
            style={{
              fontSize: 22,
              fontWeight: 600,
              background:
                "linear-gradient(90deg, #0ea5e9 0%, #22d3ee 50%, #06b6d4 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 20,
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
              gap: 10,
              marginBottom: 24,
            }}
          >
            {TERMS.map((item, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  padding: "6px 14px",
                  borderRadius: 6,
                  background: `${item.color}15`,
                  border: `1px solid ${item.color}35`,
                }}
              >
                <span
                  style={{
                    fontSize: 13,
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
              gap: 16,
              fontSize: 14,
              color: "#64748b",
            }}
          >
            <span
              style={{
                display: "flex",
                alignItems: "center",
                gap: 5,
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
            <span style={{ display: "flex" }}>Shell • Networking • Tools</span>
          </div>
        </div>

        {/* Right - Book Visual */}
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
                "radial-gradient(circle, rgba(14,165,233,0.25) 0%, rgba(34,211,238,0.12) 40%, transparent 70%)",
              filter: "blur(35px)",
              display: "flex",
            }}
          />

          {/* Book SVG */}
          <svg
            width="200"
            height="200"
            viewBox="0 0 100 100"
            fill="none"
            style={{
              filter: "drop-shadow(0 0 25px rgba(14,165,233,0.35))",
            }}
          >
            <defs>
              <linearGradient id="tBookGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#0ea5e9" />
                <stop offset="50%" stopColor="#22d3ee" />
                <stop offset="100%" stopColor="#06b6d4" />
              </linearGradient>
            </defs>

            {/* Book */}
            <path
              d="M18 12 L18 88 Q18 93 23 93 L77 93 Q82 93 82 88 L82 12 Q82 7 77 7 L23 7 Q18 7 18 12"
              fill="rgba(15,20,25,0.9)"
              stroke="url(#tBookGrad)"
              strokeWidth="2.5"
            />

            {/* Spine highlight */}
            <path
              d="M23 12 L23 88 L28 88 L28 12 Z"
              fill="rgba(14,165,233,0.2)"
            />

            {/* Lines */}
            <line x1="34" y1="22" x2="72" y2="22" stroke="#0ea5e9" strokeWidth="1.5" opacity="0.6" />
            <line x1="34" y1="34" x2="68" y2="34" stroke="#22d3ee" strokeWidth="1" opacity="0.4" />
            <line x1="34" y1="44" x2="70" y2="44" stroke="#06b6d4" strokeWidth="1" opacity="0.4" />
            <line x1="34" y1="54" x2="62" y2="54" stroke="#0284c7" strokeWidth="1" opacity="0.4" />
            <line x1="34" y1="64" x2="68" y2="64" stroke="#38bdf8" strokeWidth="1" opacity="0.4" />
            <line x1="34" y1="74" x2="56" y2="74" stroke="#7dd3fc" strokeWidth="1" opacity="0.4" />
            <line x1="34" y1="84" x2="64" y2="84" stroke="#0ea5e9" strokeWidth="1" opacity="0.4" />

            {/* Magnifying glass */}
            <circle cx="74" cy="26" r="12" stroke="url(#tBookGrad)" strokeWidth="2.5" fill="rgba(14,165,233,0.1)" />
            <line x1="82" y1="35" x2="92" y2="45" stroke="url(#tBookGrad)" strokeWidth="3.5" strokeLinecap="round" />
            <text x="69" y="31" fontSize="12" fill="#0ea5e9" fontWeight="bold">A</text>
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
              "linear-gradient(90deg, transparent 0%, #0ea5e9 25%, #22d3ee 50%, #06b6d4 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/glossary</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
