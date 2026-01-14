import { ImageResponse } from "next/og";
import { LESSONS, getLessonBySlug } from "@/lib/lessons";
import { getLessonColor, DARK_GRADIENT, GRID_PATTERN, getOrbGradient } from "@/lib/og-utils";

export const runtime = "edge";

export const size = {
  width: 1200,
  height: 600,
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
          padding: "40px 60px",
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
            backgroundImage: GRID_PATTERN(primaryColor),
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
            background: getOrbGradient(primaryColor, 0.18),
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
            background: getOrbGradient("#22d3ee", 0.1),
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
              gap: 10,
              marginBottom: 16,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                padding: "5px 12px",
                borderRadius: 14,
                background: `rgba(${parseInt(primaryColor.slice(1, 3), 16)},${parseInt(primaryColor.slice(3, 5), 16)},${parseInt(primaryColor.slice(5, 7), 16)},0.1)`,
                border: `1px solid ${primaryColor}40`,
              }}
            >
              <svg
                width="12"
                height="12"
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
                  fontSize: 11,
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
                gap: 4,
                padding: "5px 10px",
                borderRadius: 10,
                background: "rgba(100,116,139,0.15)",
                border: "1px solid rgba(100,116,139,0.25)",
              }}
            >
              <svg
                width="10"
                height="10"
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
                  fontSize: 10,
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
              fontSize: 44,
              fontWeight: 800,
              background:
                "linear-gradient(135deg, #ffffff 0%, #e2e8f0 50%, #94a3b8 100%)",
              backgroundClip: "text",
              color: "transparent",
              margin: 0,
              marginBottom: 10,
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
              fontSize: 16,
              color: "#94a3b8",
              margin: 0,
              marginBottom: 20,
              lineHeight: 1.5,
              display: "flex",
              maxWidth: 450,
            }}
          >
            {description}
          </p>

          {/* Progress bar */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 6,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 6,
                fontSize: 11,
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
                width: 250,
                height: 5,
                borderRadius: 2.5,
                background: "rgba(100,116,139,0.2)",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  width: `${(lessonNumber / totalLessons) * 100}%`,
                  height: "100%",
                  borderRadius: 2.5,
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
              width: 240,
              height: 240,
              borderRadius: "50%",
              background: getOrbGradient(primaryColor, 0.28),
              filter: "blur(35px)",
              display: "flex",
            }}
          />

          {/* Lesson number circle */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 170,
              height: 170,
              borderRadius: "50%",
              background: `linear-gradient(145deg, rgba(${parseInt(primaryColor.slice(1, 3), 16)},${parseInt(primaryColor.slice(3, 5), 16)},${parseInt(primaryColor.slice(5, 7), 16)},0.15), rgba(15,20,25,0.9))`,
              border: `3px solid ${primaryColor}`,
              position: "relative",
            }}
          >
            <span
              style={{
                fontSize: 70,
                fontWeight: 800,
                color: primaryColor,
                display: "flex",
              }}
            >
              {lessonNumber}
            </span>

            {/* Rotating dashes around circle */}
            <svg
              width="190"
              height="190"
              viewBox="0 0 190 190"
              fill="none"
              style={{
                position: "absolute",
                top: -10,
                left: -10,
              }}
            >
              <circle
                cx="95"
                cy="95"
                r="90"
                stroke={primaryColor}
                strokeWidth="2"
                strokeDasharray="7 10"
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
            top: 22,
            right: 28,
            display: "flex",
            fontSize: 12,
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
