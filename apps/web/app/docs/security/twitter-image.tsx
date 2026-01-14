import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt =
  "Security Best Practices - Google SSO Strategy for Agentic Coding";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

// Checklist items
const CHECKLIST = [
  { item: "Google 2FA", done: true },
  { item: "Recovery Setup", done: true },
  { item: "App Permissions", done: true },
  { item: "Password Manager", done: false },
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
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%2322c55e' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
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
              "radial-gradient(circle, rgba(34,197,94,0.2) 0%, transparent 60%)",
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
              "radial-gradient(circle, rgba(99,102,241,0.12) 0%, transparent 60%)",
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
            maxWidth: "55%",
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
              background: "rgba(34,197,94,0.1)",
              border: "1px solid rgba(34,197,94,0.25)",
            }}
          >
            <svg
              width="14"
              height="14"
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
                fontSize: 12,
                color: "#22c55e",
                fontWeight: 600,
                letterSpacing: "0.08em",
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
              fontSize: 44,
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
            Security Best Practices
          </h1>

          {/* Subtitle */}
          <p
            style={{
              fontSize: 20,
              fontWeight: 600,
              background:
                "linear-gradient(90deg, #6366f1 0%, #22c55e 50%, #10b981 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 20,
              display: "flex",
            }}
          >
            Google SSO Strategy
          </p>

          {/* Checklist */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 8,
              marginBottom: 20,
            }}
          >
            {CHECKLIST.map((item, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                }}
              >
                <div
                  style={{
                    width: 18,
                    height: 18,
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
                      width="10"
                      height="10"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#22c55e"
                      strokeWidth="3"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                </div>
                <span
                  style={{
                    fontSize: 13,
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
              gap: 16,
              fontSize: 14,
              color: "#64748b",
            }}
          >
            <span style={{ display: "flex" }}>Interactive checklist</span>
            <span style={{ color: "#374151", display: "flex" }}>•</span>
            <span style={{ display: "flex" }}>Progress saved</span>
          </div>
        </div>

        {/* Right - Shield Visual */}
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
                "radial-gradient(circle, rgba(34,197,94,0.25) 0%, rgba(99,102,241,0.12) 40%, transparent 70%)",
              filter: "blur(35px)",
              display: "flex",
            }}
          />

          {/* Shield SVG */}
          <svg
            width="200"
            height="200"
            viewBox="0 0 100 100"
            fill="none"
            style={{
              filter: "drop-shadow(0 0 25px rgba(34,197,94,0.35))",
            }}
          >
            <defs>
              <linearGradient id="tSecGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#6366f1" />
                <stop offset="50%" stopColor="#22c55e" />
                <stop offset="100%" stopColor="#10b981" />
              </linearGradient>
            </defs>

            {/* Main shield */}
            <path
              d="M50 6 L88 17 L88 47 C88 74 69 90 50 97 C31 90 12 74 12 47 L12 17 Z"
              fill="rgba(34,197,94,0.1)"
              stroke="url(#tSecGrad)"
              strokeWidth="3"
            />

            {/* Inner shield */}
            <path
              d="M50 14 L80 23 L80 47 C80 68 65 82 50 88 C35 82 20 68 20 47 L20 23 Z"
              fill="rgba(34,197,94,0.05)"
              stroke="#22c55e"
              strokeWidth="1.5"
              opacity="0.5"
            />

            {/* Lock */}
            <g transform="translate(33, 30)">
              <rect
                x="6"
                y="14"
                width="22"
                height="18"
                rx="3"
                fill="rgba(34,197,94,0.3)"
                stroke="#22c55e"
                strokeWidth="2.5"
              />
              <path
                d="M11 14 L11 9 C11 4 14 1 17 1 C20 1 23 4 23 9 L23 14"
                fill="none"
                stroke="#22c55e"
                strokeWidth="2.5"
                strokeLinecap="round"
              />
              <circle cx="17" cy="22" r="2.5" fill="#22c55e" />
              <line x1="17" y1="25" x2="17" y2="28" stroke="#22c55e" strokeWidth="2.5" strokeLinecap="round" />
            </g>

            {/* Checkmark badge */}
            <g transform="translate(60, 58)">
              <circle cx="14" cy="14" r="14" fill="#22c55e" />
              <path
                d="M7 14 L11 18 L21 8"
                fill="none"
                stroke="white"
                strokeWidth="3"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
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
              "linear-gradient(90deg, transparent 0%, #6366f1 25%, #22c55e 50%, #10b981 75%, transparent 100%)",
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
          <span style={{ display: "flex" }}>agent-flywheel.com/docs/security</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
