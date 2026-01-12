import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "ACFS Learning Hub - Master Agentic Coding with Interactive Lessons";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

// Lesson categories
const categories = [
  { name: "Linux Basics", color: "#22d3ee" },
  { name: "SSH & Tmux", color: "#a855f7" },
  { name: "Git & GitHub", color: "#f472b6" },
  { name: "AI Agents", color: "#22c55e" },
  { name: "NTM & Tools", color: "#f59e0b" },
  { name: "The Flywheel", color: "#3b82f6" },
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
        {/* Grid pattern */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='32' height='32' viewBox='0 0 32 32' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%2322d3ee' stroke-width='0.5'%3E%3Crect x='0' y='0' width='32' height='32'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs */}
        <div
          style={{
            position: "absolute",
            top: -100,
            left: -50,
            width: 400,
            height: 400,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(34,211,238,0.15) 0%, transparent 60%)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -150,
            right: -50,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(168,85,247,0.12) 0%, transparent 60%)",
            display: "flex",
          }}
        />

        {/* Main content */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 10,
            padding: "40px 60px",
          }}
        >
          {/* Header */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              marginBottom: 35,
            }}
          >
            {/* Badge */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                marginBottom: 18,
                padding: "8px 18px",
                borderRadius: 20,
                background: "rgba(34,211,238,0.1)",
                border: "1px solid rgba(34,211,238,0.25)",
              }}
            >
              {/* Book icon */}
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#22d3ee"
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
                  color: "#22d3ee",
                  fontWeight: 600,
                  letterSpacing: "0.06em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Interactive Learning
              </span>
            </div>

            {/* Title */}
            <h1
              style={{
                fontSize: 56,
                fontWeight: 800,
                background:
                  "linear-gradient(135deg, #ffffff 0%, #e2e8f0 50%, #94a3b8 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 10,
                letterSpacing: "-0.03em",
                display: "flex",
              }}
            >
              ACFS Learning Hub
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 24,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #22d3ee 0%, #a855f7 50%, #f472b6 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                display: "flex",
              }}
            >
              Master Agentic Coding
            </p>
          </div>

          {/* Categories grid */}
          <div
            style={{
              display: "flex",
              flexDirection: "row",
              flexWrap: "wrap",
              justifyContent: "center",
              gap: 14,
              maxWidth: 800,
              marginBottom: 30,
            }}
          >
            {categories.map((cat, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                  padding: "12px 20px",
                  borderRadius: 12,
                  background: `linear-gradient(135deg, ${cat.color}12 0%, ${cat.color}06 100%)`,
                  border: `1px solid ${cat.color}35`,
                }}
              >
                {/* Category icon placeholder */}
                <div
                  style={{
                    width: 24,
                    height: 24,
                    borderRadius: 6,
                    background: `${cat.color}25`,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <div
                    style={{
                      width: 10,
                      height: 10,
                      borderRadius: "50%",
                      background: cat.color,
                      display: "flex",
                    }}
                  />
                </div>
                <span
                  style={{
                    fontSize: 15,
                    fontWeight: 600,
                    color: cat.color,
                    display: "flex",
                  }}
                >
                  {cat.name}
                </span>
              </div>
            ))}
          </div>

          {/* Footer stats */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 24,
              fontSize: 16,
              color: "#64748b",
            }}
          >
            <span
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
              }}
            >
              <span
                style={{
                  color: "#22d3ee",
                  fontWeight: 700,
                  display: "flex",
                }}
              >
                11+
              </span>
              Lessons
            </span>
            <span style={{ color: "#374151", display: "flex" }}>•</span>
            <span style={{ display: "flex" }}>Hands-on exercises</span>
            <span style={{ color: "#374151", display: "flex" }}>•</span>
            <span style={{ display: "flex" }}>Progress tracking</span>
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

        {/* Bottom gradient accent */}
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

        {/* URL */}
        <div
          style={{
            position: "absolute",
            top: 28,
            right: 35,
            display: "flex",
            fontSize: 13,
            color: "#4b5563",
          }}
        >
          <span style={{ display: "flex" }}>agent-flywheel.com/learn</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
