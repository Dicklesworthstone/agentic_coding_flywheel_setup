import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Agent Flywheel Documentation - Security, Architecture & Best Practices";
export const size = {
  width: 1200,
  height: 630,
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
        {/* Grid pattern overlay - indigo theme */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%236366f1' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - indigo/blue theme */}
        <div
          style={{
            position: "absolute",
            top: -150,
            left: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background:
              "radial-gradient(circle, rgba(99,102,241,0.18) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(59,130,246,0.12) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(139,92,246,0.08) 0%, transparent 60%)",
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
          {/* Left side - Document visual */}
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
                  "radial-gradient(circle, rgba(99,102,241,0.25) 0%, rgba(59,130,246,0.15) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Documents SVG */}
            <svg
              width="220"
              height="220"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 30px rgba(99,102,241,0.4))",
              }}
            >
              <defs>
                <linearGradient id="docGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#6366f1" />
                  <stop offset="50%" stopColor="#3b82f6" />
                  <stop offset="100%" stopColor="#8b5cf6" />
                </linearGradient>
              </defs>

              {/* Back document */}
              <rect
                x="25"
                y="10"
                width="55"
                height="70"
                rx="4"
                fill="rgba(15,20,25,0.7)"
                stroke="#3b82f6"
                strokeWidth="1.5"
                opacity="0.5"
              />

              {/* Middle document */}
              <rect
                x="20"
                y="15"
                width="55"
                height="70"
                rx="4"
                fill="rgba(15,20,25,0.85)"
                stroke="#6366f1"
                strokeWidth="1.5"
                opacity="0.7"
              />

              {/* Front document */}
              <rect
                x="15"
                y="20"
                width="55"
                height="70"
                rx="4"
                fill="rgba(15,20,25,0.95)"
                stroke="url(#docGrad)"
                strokeWidth="2"
              />

              {/* Document content lines */}
              <line x1="22" y1="32" x2="62" y2="32" stroke="#6366f1" strokeWidth="2" opacity="0.6" />
              <line x1="22" y1="42" x2="55" y2="42" stroke="#3b82f6" strokeWidth="1.5" opacity="0.4" />
              <line x1="22" y1="50" x2="58" y2="50" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.4" />
              <line x1="22" y1="58" x2="50" y2="58" stroke="#6366f1" strokeWidth="1.5" opacity="0.4" />
              <line x1="22" y1="66" x2="56" y2="66" stroke="#3b82f6" strokeWidth="1.5" opacity="0.4" />
              <line x1="22" y1="74" x2="48" y2="74" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.4" />
              <line x1="22" y1="82" x2="52" y2="82" stroke="#6366f1" strokeWidth="1.5" opacity="0.4" />

              {/* Shield icon overlay */}
              <g transform="translate(55, 55)">
                <path
                  d="M15 5 L25 8 L25 18 C25 24 20 28 15 30 C10 28 5 24 5 18 L5 8 Z"
                  fill="rgba(99,102,241,0.2)"
                  stroke="#6366f1"
                  strokeWidth="2"
                />
                <path
                  d="M11 16 L14 19 L20 13"
                  fill="none"
                  stroke="#22c55e"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
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
                background: "rgba(99,102,241,0.1)",
                border: "1px solid rgba(99,102,241,0.3)",
              }}
            >
              {/* Document icon */}
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#6366f1"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <polyline points="14 2 14 8 20 8" />
                <line x1="16" y1="13" x2="8" y2="13" />
                <line x1="16" y1="17" x2="8" y2="17" />
                <polyline points="10 9 9 9 8 9" />
              </svg>
              <span
                style={{
                  fontSize: 14,
                  color: "#6366f1",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Documentation
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
              Documentation
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 26,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #6366f1 0%, #3b82f6 50%, #8b5cf6 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
                display: "flex",
              }}
            >
              Security, Architecture & Best Practices
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
              Comprehensive guides for securing your agentic coding environment
              and following best practices
            </p>

            {/* Topics */}
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
                    width: 8,
                    height: 8,
                    borderRadius: "50%",
                    background: "#22c55e",
                    display: "flex",
                  }}
                />
                Security Checklist
              </span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Google SSO Strategy</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>2FA Setup</span>
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
              "linear-gradient(90deg, transparent 0%, #6366f1 25%, #3b82f6 50%, #8b5cf6 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/docs</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
