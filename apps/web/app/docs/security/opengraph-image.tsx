import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Security Best Practices - Google SSO Strategy for Agentic Coding";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

// Checklist items to display
const CHECKLIST = [
  { item: "Google 2FA", done: true },
  { item: "Recovery Setup", done: true },
  { item: "App Permissions", done: true },
  { item: "Password Manager", done: false },
  { item: "GitHub 2FA", done: false },
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
        {/* Grid pattern overlay - indigo/green theme */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%2322c55e' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Glowing orbs - indigo/green theme */}
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
              "radial-gradient(circle, rgba(34,197,94,0.15) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(16,185,129,0.08) 0%, transparent 60%)",
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
          {/* Left side - Shield with lock visual */}
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
                  "radial-gradient(circle, rgba(34,197,94,0.25) 0%, rgba(99,102,241,0.15) 50%, transparent 70%)",
                filter: "blur(30px)",
                display: "flex",
              }}
            />

            {/* Security SVG - shield with checkmarks */}
            <svg
              width="220"
              height="220"
              viewBox="0 0 100 100"
              fill="none"
              style={{
                filter: "drop-shadow(0 0 30px rgba(34,197,94,0.4))",
              }}
            >
              <defs>
                <linearGradient id="secGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#6366f1" />
                  <stop offset="50%" stopColor="#22c55e" />
                  <stop offset="100%" stopColor="#10b981" />
                </linearGradient>
                <linearGradient id="shieldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#22c55e" />
                  <stop offset="100%" stopColor="#10b981" />
                </linearGradient>
              </defs>

              {/* Main shield */}
              <path
                d="M50 8 L85 18 L85 45 C85 70 68 85 50 92 C32 85 15 70 15 45 L15 18 Z"
                fill="rgba(34,197,94,0.1)"
                stroke="url(#secGrad)"
                strokeWidth="2.5"
              />

              {/* Inner shield glow */}
              <path
                d="M50 15 L78 23 L78 45 C78 65 64 78 50 84 C36 78 22 65 22 45 L22 23 Z"
                fill="rgba(34,197,94,0.05)"
                stroke="#22c55e"
                strokeWidth="1"
                opacity="0.5"
              />

              {/* Lock icon */}
              <g transform="translate(35, 32)">
                <rect
                  x="5"
                  y="12"
                  width="20"
                  height="16"
                  rx="2"
                  fill="rgba(34,197,94,0.3)"
                  stroke="#22c55e"
                  strokeWidth="2"
                />
                <path
                  d="M10 12 L10 8 C10 4 12 2 15 2 C18 2 20 4 20 8 L20 12"
                  fill="none"
                  stroke="#22c55e"
                  strokeWidth="2"
                  strokeLinecap="round"
                />
                <circle cx="15" cy="20" r="2" fill="#22c55e" />
                <line x1="15" y1="22" x2="15" y2="25" stroke="#22c55e" strokeWidth="2" strokeLinecap="round" />
              </g>

              {/* Checkmark badge */}
              <g transform="translate(58, 55)">
                <circle cx="12" cy="12" r="12" fill="#22c55e" />
                <path
                  d="M6 12 L10 16 L18 8"
                  fill="none"
                  stroke="white"
                  strokeWidth="2.5"
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
                background: "rgba(34,197,94,0.1)",
                border: "1px solid rgba(34,197,94,0.3)",
              }}
            >
              {/* Shield icon */}
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#22c55e"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              <span
                style={{
                  fontSize: 14,
                  color: "#22c55e",
                  fontWeight: 600,
                  letterSpacing: "0.05em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Security
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
              Security Best Practices
            </h1>

            {/* Subtitle */}
            <p
              style={{
                fontSize: 24,
                fontWeight: 600,
                background:
                  "linear-gradient(90deg, #6366f1 0%, #22c55e 50%, #10b981 100%)",
                backgroundClip: "text",
                color: "transparent",
                margin: 0,
                marginBottom: 24,
                display: "flex",
              }}
            >
              Google SSO Strategy
            </p>

            {/* Checklist preview */}
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: 10,
                marginBottom: 24,
              }}
            >
              {CHECKLIST.map((item, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                  }}
                >
                  <div
                    style={{
                      width: 20,
                      height: 20,
                      borderRadius: 4,
                      background: item.done
                        ? "rgba(34,197,94,0.2)"
                        : "rgba(100,116,139,0.2)",
                      border: item.done
                        ? "2px solid #22c55e"
                        : "2px solid #64748b",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    {item.done && (
                      <svg
                        width="12"
                        height="12"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="#22c55e"
                        strokeWidth="3"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                  </div>
                  <span
                    style={{
                      fontSize: 15,
                      color: item.done ? "#22c55e" : "#64748b",
                      fontWeight: 500,
                      display: "flex",
                    }}
                  >
                    {item.item}
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
              <span style={{ display: "flex" }}>Interactive checklist</span>
              <span style={{ color: "#374151", display: "flex" }}>•</span>
              <span style={{ display: "flex" }}>Progress saved</span>
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
              "linear-gradient(90deg, transparent 0%, #6366f1 25%, #22c55e 50%, #10b981 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/docs/security</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
