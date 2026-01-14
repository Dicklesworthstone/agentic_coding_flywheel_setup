import { ImageResponse } from "next/og";
import { TOOLS, type ToolId } from "./tool-data";
import { TOOL_COLORS, DARK_GRADIENT, GRID_PATTERN, getOrbGradient } from "@/lib/og-utils";

export const runtime = "edge";

export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

export const alt = "ACFS Tool Guide";

// Get icon path for each tool
function getToolIconPath(toolId: ToolId): string {
  switch (toolId) {
    case "claude-code":
    case "codex-cli":
    case "gemini-cli":
      // Bot/AI icon
      return "M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7h1a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1H2a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1h1a7 7 0 0 1 7-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 0 1 2-2M7.5 13A2.5 2.5 0 0 0 5 15.5A2.5 2.5 0 0 0 7.5 18a2.5 2.5 0 0 0 2.5-2.5A2.5 2.5 0 0 0 7.5 13m9 0a2.5 2.5 0 0 0-2.5 2.5a2.5 2.5 0 0 0 2.5 2.5a2.5 2.5 0 0 0 2.5-2.5a2.5 2.5 0 0 0-2.5-2.5";
    case "ntm":
      // Grid/layout icon
      return "M3 3h7v7H3V3m11 0h7v7h-7V3m0 11h7v7h-7v-7m-11 0h7v7H3v-7";
    case "beads":
    case "ru":
      // Git branch icon
      return "M6 3v12M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 9a9 9 0 0 1-9 9";
    case "agent-mail":
      // Key/mail icon
      return "M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4";
    case "ubs":
    case "slb":
    case "dcg":
      // Shield icon
      return "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z";
    case "cass":
      // Search icon
      return "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.35-4.35";
    case "cm":
    case "caam":
      // Wrench icon
      return "M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z";
    default:
      return "M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5";
  }
}

export default async function Image({ params }: { params: { tool: string } }) {
  const toolId = params.tool as ToolId;
  const tool = TOOLS[toolId];
  const colors = TOOL_COLORS[toolId] || { primary: "#22d3ee", secondary: "#a855f7" };

  // Fallback for unknown tools
  const title = tool?.title || "Tool";
  const tagline = tool?.tagline || "ACFS Tool";
  const quickCommand = tool?.quickCommand;
  const iconPath = getToolIconPath(toolId);

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
            backgroundImage: GRID_PATTERN(colors.primary),
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
            background: getOrbGradient(colors.primary, 0.18),
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
            background: getOrbGradient(colors.secondary, 0.12),
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
            maxWidth: "56%",
          }}
        >
          {/* Badge */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: 16,
              padding: "5px 12px",
              borderRadius: 14,
              background: `rgba(${parseInt(colors.primary.slice(1, 3), 16)},${parseInt(colors.primary.slice(3, 5), 16)},${parseInt(colors.primary.slice(5, 7), 16)},0.1)`,
              border: `1px solid ${colors.primary}40`,
            }}
          >
            <svg
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke={colors.primary}
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d={iconPath} />
            </svg>
            <span
              style={{
                fontSize: 11,
                color: colors.primary,
                fontWeight: 600,
                letterSpacing: "0.08em",
                textTransform: "uppercase",
                display: "flex",
              }}
            >
              Tool
            </span>
          </div>

          {/* Title */}
          <h1
            style={{
              fontSize: 50,
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

          {/* Tagline */}
          <p
            style={{
              fontSize: 18,
              color: "#94a3b8",
              margin: 0,
              marginBottom: quickCommand ? 20 : 0,
              lineHeight: 1.5,
              display: "flex",
              maxWidth: 450,
            }}
          >
            {tagline}
          </p>

          {/* Quick command */}
          {quickCommand && (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                padding: "10px 14px",
                borderRadius: 8,
                background: "rgba(15,20,25,0.8)",
                border: "1px solid rgba(100,116,139,0.3)",
              }}
            >
              <span style={{ fontSize: 13, color: "#64748b", display: "flex" }}>$</span>
              <span
                style={{
                  fontSize: 14,
                  color: colors.primary,
                  fontFamily: "monospace",
                  fontWeight: 500,
                  display: "flex",
                }}
              >
                {quickCommand}
              </span>
            </div>
          )}
        </div>

        {/* Right - Tool visual */}
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
              background: getOrbGradient(colors.primary, 0.3),
              filter: "blur(45px)",
              display: "flex",
            }}
          />

          {/* Tool icon container */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 160,
              height: 160,
              borderRadius: 26,
              background: `linear-gradient(145deg, rgba(${parseInt(colors.primary.slice(1, 3), 16)},${parseInt(colors.primary.slice(3, 5), 16)},${parseInt(colors.primary.slice(5, 7), 16)},0.2), rgba(15,20,25,0.9))`,
              border: `3px solid ${colors.primary}60`,
              position: "relative",
            }}
          >
            <svg
              width="80"
              height="80"
              viewBox="0 0 24 24"
              fill="none"
              stroke={colors.primary}
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              style={{
                filter: `drop-shadow(0 0 18px ${colors.primary})`,
              }}
            >
              <path d={iconPath} />
            </svg>

            {/* Corner decoration */}
            <div
              style={{
                position: "absolute",
                top: -7,
                right: -7,
                width: 28,
                height: 28,
                borderRadius: "50%",
                background: `linear-gradient(135deg, ${colors.primary}, ${colors.secondary})`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <svg
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="white"
                strokeWidth="3"
              >
                <polyline points="20 6 9 17 4 12" />
              </svg>
            </div>
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
            background: `linear-gradient(90deg, transparent 0%, ${colors.primary} 25%, ${colors.secondary} 50%, ${colors.primary} 75%, transparent 100%)`,
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
          <span style={{ display: "flex" }}>agent-flywheel.com/learn/tools/{toolId}</span>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}
