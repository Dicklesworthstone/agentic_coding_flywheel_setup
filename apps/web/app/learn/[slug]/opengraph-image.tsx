import { ImageResponse } from "next/og";
import { LESSONS, getLessonBySlug } from "@/lib/lessons";
import { getLessonColor, DARK_GRADIENT, GRID_PATTERN, getOrbGradient } from "@/lib/og-utils";

export const runtime = "edge";

export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export const alt = "ACFS Learning Hub Lesson";

export default async function Image({ params }: { params: { slug: string } }) {
  const lesson = getLessonBySlug(params.slug);
  const lessonIndex = LESSONS.findIndex((l) => l.slug === params.slug);
  const lessonNumber = lessonIndex + 1;
  const totalLessons = LESSONS.length;
  const primaryColor = getLessonColor(params.slug);

  // Fallback for unknown lessons
  const title = lesson?.title || "Lesson";
  const description = lesson?.description || "Learn agentic coding";
  const duration = lesson?.duration || "5 min";

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
          background: DARK_GRADIENT,
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
            opacity: 0.03,
            backgroundImage: GRID_PATTERN(primaryColor),
            display: "flex",
          }}
        />

        {/* Glowing orbs */}
        <div
          style={{
            position: "absolute",
            top: -150,
            right: -100,
            width: 500,
            height: 500,
            borderRadius: "50%",
            background: getOrbGradient(primaryColor, 0.2),
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -200,
            left: -150,
            width: 550,
            height: 550,
            borderRadius: "50%",
            background: getOrbGradient("#22d3ee", 0.12),
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
            maxWidth: "60%",
          }}
        >
          {/* Badge */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              marginBottom: 18,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                padding: "6px 14px",
                borderRadius: 16,
                background: `rgba(${parseInt(primaryColor.slice(1, 3), 16)},${parseInt(primaryColor.slice(3, 5), 16)},${parseInt(primaryColor.slice(5, 7), 16)},0.1)`,
                border: `1px solid ${primaryColor}40`,
              }}
            >
              <svg
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke={primaryColor}
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
                <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
              </svg>
              <span
                style={{
                  fontSize: 12,
                  color: primaryColor,
                  fontWeight: 600,
                  letterSpacing: "0.08em",
                  textTransform: "uppercase",
                  display: "flex",
                }}
              >
                Lesson {lessonNumber}
              </span>
            </div>
            {/* Duration badge */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 5,
                padding: "6px 12px",
                borderRadius: 12,
                background: "rgba(100,116,139,0.15)",
                border: "1px solid rgba(100,116,139,0.25)",
              }}
            >
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#64748b"
                strokeWidth="2"
              >
                <circle cx="12" cy="12" r="10" />
                <polyline points="12 6 12 12 16 14" />
              </svg>
              <span
                style={{
                  fontSize: 11,
                  color: "#64748b",
                  fontWeight: 500,
                  display: "flex",
                }}
              >
                {duration}
              </span>
            </div>
          </div>

          {/* Title */}
          <h1
            style={{
              fontSize: 48,
              fontWeight: 800,
              background:
                "linear-gradient(135deg, #ffffff 0%, #e2e8f0 50%, #94a3b8 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 12,
              letterSpacing: "-0.03em",
              lineHeight: 1.1,
              display: "flex",
            }}
          >
            {title}
          </h1>

          {/* Description */}
          <p
            style={{
              fontSize: 18,
              color: "#94a3b8",
              margin: 0,
              marginBottom: 24,
              lineHeight: 1.5,
              display: "flex",
              maxWidth: 500,
            }}
          >
            {description}
          </p>

          {/* Progress bar */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 8,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                fontSize: 12,
                color: "#64748b",
              }}
            >
              <span style={{ display: "flex" }}>Progress</span>
              <span style={{ display: "flex", color: primaryColor }}>
                {lessonNumber} / {totalLessons}
              </span>
            </div>
            <div
              style={{
                display: "flex",
                width: 300,
                height: 6,
                borderRadius: 3,
                background: "rgba(100,116,139,0.2)",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  width: `${(lessonNumber / totalLessons) * 100}%`,
                  height: "100%",
                  borderRadius: 3,
                  background: `linear-gradient(90deg, ${primaryColor}, #22d3ee)`,
                  display: "flex",
                }}
              />
            </div>
          </div>
        </div>

        {/* Right - Visual */}
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
              background: getOrbGradient(primaryColor, 0.3),
              filter: "blur(40px)",
              display: "flex",
            }}
          />

          {/* Lesson number circle */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 200,
              height: 200,
              borderRadius: "50%",
              background: `linear-gradient(145deg, rgba(${parseInt(primaryColor.slice(1, 3), 16)},${parseInt(primaryColor.slice(3, 5), 16)},${parseInt(primaryColor.slice(5, 7), 16)},0.15), rgba(15,20,25,0.9))`,
              border: `3px solid ${primaryColor}`,
              position: "relative",
            }}
          >
            <span
              style={{
                fontSize: 80,
                fontWeight: 800,
                color: primaryColor,
                display: "flex",
              }}
            >
              {lessonNumber}
            </span>

            {/* Rotating dashes around circle */}
            <svg
              width="220"
              height="220"
              viewBox="0 0 220 220"
              fill="none"
              style={{
                position: "absolute",
                top: -10,
                left: -10,
              }}
            >
              <circle
                cx="110"
                cy="110"
                r="105"
                stroke={primaryColor}
                strokeWidth="2"
                strokeDasharray="8 12"
                opacity="0.4"
              />
            </svg>
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
            background: `linear-gradient(90deg, transparent 0%, ${primaryColor} 25%, #22d3ee 50%, #a855f7 75%, transparent 100%)`,
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
          <span style={{ display: "flex" }}>agent-flywheel.com/learn/{params.slug}</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
