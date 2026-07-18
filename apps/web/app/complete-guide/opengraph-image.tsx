import { ImageResponse } from "next/og";
import {
  COMPLETE_GUIDE_PHASE_COUNT,
  COMPLETE_GUIDE_PROMPT_COUNT,
  VALIDATION_GATES,
} from "@/lib/complete-guide";

export const runtime = "edge";
export const alt = "The Flywheel Approach to Planning & Beads Creation";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

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
          justifyContent: "center",
          background: "linear-gradient(145deg, #09090b 0%, #0f1218 35%, #1a1b26 65%, #09090b 100%)",
          fontFamily: "system-ui, -apple-system, sans-serif",
          padding: "40px 60px",
          gap: 60,
          position: "relative",
          overflow: "hidden",
        }}
      >
        {/* Subtle grid pattern background */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            opacity: 0.03,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%2322d3ee' stroke-width='1'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`,
            display: "flex",
          }}
        />

        {/* Ambient Top Glow */}
        <div
          style={{
            position: "absolute",
            top: -200,
            left: "50%",
            transform: "translateX(-50%)",
            width: 800,
            height: 400,
            borderRadius: "50%",
            background: "radial-gradient(circle, rgba(34,211,238,0.15) 0%, transparent 70%)",
            display: "flex",
          }}
        />

        {/* Bottom Gradient Accent */}
        <div
          style={{
            position: "absolute",
            bottom: 0,
            left: 0,
            right: 0,
            height: 6,
            background: "linear-gradient(90deg, transparent 0%, #22d3ee 25%, #a855f7 50%, #f472b6 75%, transparent 100%)",
            display: "flex",
          }}
        />

        {/* Top Right URL */}
        <div
          style={{
            position: "absolute",
            top: 40,
            right: 50,
            fontSize: 16,
            fontWeight: 500,
            color: "#64748b",
            display: "flex",
            letterSpacing: "0.05em",
          }}
        >
          <span style={{ display: "flex" }}>agent-flywheel.com/complete-guide</span>
        </div>

        {/* Left Side: Visual Flywheel Diagram */}
        <div style={{ display: "flex", position: "relative", alignItems: "center", justifyContent: "center" }}>
          {/* Intense center glow behind diagram */}
          <div
            style={{
              position: "absolute",
              width: 320,
              height: 320,
              borderRadius: "50%",
              background: "radial-gradient(circle, rgba(168,85,247,0.2) 0%, transparent 60%)",
              display: "flex",
            }}
          />
          
          <svg
            width="340"
            height="340"
            viewBox="0 0 100 100"
            fill="none"
            style={{ filter: "drop-shadow(0 0 30px rgba(34,211,238,0.3))", display: "flex" }}
          >
            <defs>
              <linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#22d3ee" />
                <stop offset="50%" stopColor="#a855f7" />
                <stop offset="100%" stopColor="#f472b6" />
              </linearGradient>
            </defs>

            {/* Outer ring */}
            <circle cx="50" cy="50" r="42" stroke="url(#ringGrad)" strokeWidth="2" fill="none" opacity="0.8" />
            <circle cx="50" cy="50" r="32" stroke="#22d3ee" strokeWidth="1" fill="none" opacity="0.3" />

            {/* Center hub */}
            <circle cx="50" cy="50" r="14" fill="url(#ringGrad)" opacity="0.9" />
            <circle cx="50" cy="50" r="6" fill="rgba(255,255,255,0.3)" />

            {/* Hub radiating lines */}
            <line x1="50" y1="50" x2="88" y2="50" stroke="#22d3ee" strokeWidth="1.5" opacity="0.6" />
            <line x1="50" y1="50" x2="69" y2="82.9" stroke="#a855f7" strokeWidth="1.5" opacity="0.6" />
            <line x1="50" y1="50" x2="31" y2="82.9" stroke="#f472b6" strokeWidth="1.5" opacity="0.6" />
            <line x1="50" y1="50" x2="12" y2="50" stroke="#22d3ee" strokeWidth="1.5" opacity="0.6" />
            <line x1="50" y1="50" x2="31" y2="17.1" stroke="#f59e0b" strokeWidth="1.5" opacity="0.6" />
            <line x1="50" y1="50" x2="69" y2="17.1" stroke="#22d3ee" strokeWidth="1.5" opacity="0.6" />

            {/* Orbiting Nodes */}
            <circle cx="88" cy="50" r="6" fill="#22d3ee" opacity="0.95" />
            <circle cx="69" cy="82.9" r="6" fill="#a855f7" opacity="0.95" />
            <circle cx="31" cy="82.9" r="6" fill="#f472b6" opacity="0.95" />
            <circle cx="12" cy="50" r="6" fill="#22d3ee" opacity="0.95" />
            <circle cx="31" cy="17.1" r="6" fill="#f59e0b" opacity="0.95" />
            <circle cx="69" cy="17.1" r="6" fill="#22d3ee" opacity="0.95" />

            {/* Node Highlights */}
            <circle cx="88" cy="50" r="2.5" fill="#fff" opacity="0.8" />
            <circle cx="69" cy="82.9" r="2.5" fill="#fff" opacity="0.8" />
            <circle cx="31" cy="82.9" r="2.5" fill="#fff" opacity="0.8" />
            <circle cx="12" cy="50" r="2.5" fill="#fff" opacity="0.8" />
            <circle cx="31" cy="17.1" r="2.5" fill="#fff" opacity="0.8" />
            <circle cx="69" cy="17.1" r="2.5" fill="#fff" opacity="0.8" />
          </svg>
        </div>

        {/* Right Side: Text Content */}
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 640 }}>
          {/* Top Badge */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              alignSelf: "flex-start",
              padding: "8px 18px",
              borderRadius: 100,
              background: "rgba(34,211,238,0.1)",
              border: "1px solid rgba(34,211,238,0.3)",
              marginBottom: 24,
            }}
          >
            <span style={{ color: "#22d3ee", fontWeight: 700, fontSize: 16, display: "flex", letterSpacing: "0.05em" }}>
              THE COMPLETE METHODOLOGY
            </span>
          </div>

          {/* Main Title */}
          <h1
            style={{
              fontSize: 72,
              fontWeight: 800,
              lineHeight: 1.1,
              letterSpacing: "-0.03em",
              color: "#ffffff",
              display: "flex",
              flexDirection: "column",
              margin: 0,
              marginBottom: 16,
            }}
          >
            <span style={{ display: "flex" }}>The Flywheel Approach to</span>
            <span
              style={{
                background: "linear-gradient(135deg, #22d3ee 0%, #a855f7 50%, #f472b6 100%)",
                backgroundClip: "text",
                color: "transparent",
                display: "flex",
                paddingBottom: 8,
              }}
            >
              Planning &amp; Beads
            </span>
          </h1>

          {/* Subtitle / Description */}
          <p
            style={{
              fontSize: 28,
              lineHeight: 1.5,
              color: "#94a3b8",
              margin: 0,
              marginBottom: 48,
              display: "flex",
              maxWidth: 580,
              fontWeight: 400,
            }}
          >
            Master the recursive system for operating AI agent swarms from human intent to flawless execution.
          </p>

          {/* Bottom Info Tags */}
          <div style={{ display: "flex", gap: 24, alignItems: "center" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#f472b6", display: "flex" }} />
              <span style={{ color: "#cbd5e1", fontSize: 20, fontWeight: 500, display: "flex" }}>{COMPLETE_GUIDE_PROMPT_COUNT} Copyable Prompts</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#a855f7", display: "flex" }} />
              <span style={{ color: "#cbd5e1", fontSize: 20, fontWeight: 500, display: "flex" }}>{VALIDATION_GATES.length} Validation Gates</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#22d3ee", display: "flex" }} />
              <span style={{ color: "#cbd5e1", fontSize: 20, fontWeight: 500, display: "flex" }}>{COMPLETE_GUIDE_PHASE_COUNT} Phases</span>
            </div>
          </div>
        </div>
      </div>
    ),
    { ...size }
  );
}
