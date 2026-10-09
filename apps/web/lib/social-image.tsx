import { ImageResponse } from "next/og";

export type SocialImageVariant = "opengraph" | "twitter";
export type SocialImageTheme =
  | "default"
  | "flywheel"
  | "learn"
  | "wizard"
  | "tools"
  | "workflow"
  | "security"
  | "support"
  | "omarchy";

export type SocialImageData = {
  badge: string;
  title: string;
  description: string;
  path: string;
  tags?: string[];
  theme?: SocialImageTheme;
};

type Palette = {
  bgStart: string;
  bgMid: string;
  bgEnd: string;
  grid: string;
  orbA: string;
  orbB: string;
  accent: string;
  accentSoft: string;
  titleStart: string;
  titleEnd: string;
  body: string;
  badgeBg: string;
  badgeBorder: string;
  badgeText: string;
  tagBg: string;
  tagBorder: string;
  tagText: string;
};

const PALETTES: Record<SocialImageTheme, Palette> = {
  default: {
    bgStart: "#070b14",
    bgMid: "#0d1628",
    bgEnd: "#0a0f1b",
    grid: "#22d3ee",
    orbA: "rgba(34,211,238,0.16)",
    orbB: "rgba(168,85,247,0.14)",
    accent: "#22d3ee",
    accentSoft: "#60a5fa",
    titleStart: "#f8fafc",
    titleEnd: "#a5f3fc",
    body: "#94a3b8",
    badgeBg: "rgba(34,211,238,0.12)",
    badgeBorder: "rgba(34,211,238,0.28)",
    badgeText: "#67e8f9",
    tagBg: "rgba(15,23,42,0.62)",
    tagBorder: "rgba(56,189,248,0.34)",
    tagText: "#bae6fd",
  },
  flywheel: {
    bgStart: "#080714",
    bgMid: "#13132a",
    bgEnd: "#0b1022",
    grid: "#a855f7",
    orbA: "rgba(168,85,247,0.18)",
    orbB: "rgba(244,114,182,0.14)",
    accent: "#a855f7",
    accentSoft: "#22d3ee",
    titleStart: "#ffffff",
    titleEnd: "#ddd6fe",
    body: "#a1a1aa",
    badgeBg: "rgba(168,85,247,0.13)",
    badgeBorder: "rgba(168,85,247,0.32)",
    badgeText: "#c4b5fd",
    tagBg: "rgba(24,24,37,0.68)",
    tagBorder: "rgba(196,181,253,0.36)",
    tagText: "#ddd6fe",
  },
  learn: {
    bgStart: "#061114",
    bgMid: "#0b1d27",
    bgEnd: "#08141d",
    grid: "#14b8a6",
    orbA: "rgba(20,184,166,0.17)",
    orbB: "rgba(59,130,246,0.12)",
    accent: "#14b8a6",
    accentSoft: "#22d3ee",
    titleStart: "#f0fdfa",
    titleEnd: "#99f6e4",
    body: "#9ca3af",
    badgeBg: "rgba(20,184,166,0.13)",
    badgeBorder: "rgba(20,184,166,0.31)",
    badgeText: "#5eead4",
    tagBg: "rgba(13,23,31,0.67)",
    tagBorder: "rgba(45,212,191,0.34)",
    tagText: "#99f6e4",
  },
  wizard: {
    bgStart: "#0f0b07",
    bgMid: "#1f170d",
    bgEnd: "#120d08",
    grid: "#f59e0b",
    orbA: "rgba(245,158,11,0.17)",
    orbB: "rgba(249,115,22,0.13)",
    accent: "#f59e0b",
    accentSoft: "#fb7185",
    titleStart: "#fff7ed",
    titleEnd: "#fdba74",
    body: "#a8b0be",
    badgeBg: "rgba(245,158,11,0.13)",
    badgeBorder: "rgba(245,158,11,0.32)",
    badgeText: "#fdba74",
    tagBg: "rgba(28,25,23,0.66)",
    tagBorder: "rgba(251,146,60,0.34)",
    tagText: "#fed7aa",
  },
  tools: {
    bgStart: "#061014",
    bgMid: "#0c1f29",
    bgEnd: "#07141d",
    grid: "#38bdf8",
    orbA: "rgba(56,189,248,0.18)",
    orbB: "rgba(34,197,94,0.11)",
    accent: "#38bdf8",
    accentSoft: "#22c55e",
    titleStart: "#f8fafc",
    titleEnd: "#bae6fd",
    body: "#97a6b8",
    badgeBg: "rgba(56,189,248,0.13)",
    badgeBorder: "rgba(56,189,248,0.32)",
    badgeText: "#7dd3fc",
    tagBg: "rgba(12,23,35,0.66)",
    tagBorder: "rgba(125,211,252,0.33)",
    tagText: "#bae6fd",
  },
  workflow: {
    bgStart: "#08100f",
    bgMid: "#0f211f",
    bgEnd: "#091716",
    grid: "#22c55e",
    orbA: "rgba(34,197,94,0.17)",
    orbB: "rgba(20,184,166,0.12)",
    accent: "#22c55e",
    accentSoft: "#14b8a6",
    titleStart: "#f0fdf4",
    titleEnd: "#86efac",
    body: "#9da8b8",
    badgeBg: "rgba(34,197,94,0.13)",
    badgeBorder: "rgba(34,197,94,0.32)",
    badgeText: "#86efac",
    tagBg: "rgba(10,24,20,0.67)",
    tagBorder: "rgba(74,222,128,0.34)",
    tagText: "#bbf7d0",
  },
  security: {
    bgStart: "#12080c",
    bgMid: "#24111a",
    bgEnd: "#150a10",
    grid: "#f43f5e",
    orbA: "rgba(244,63,94,0.17)",
    orbB: "rgba(236,72,153,0.12)",
    accent: "#f43f5e",
    accentSoft: "#fb7185",
    titleStart: "#fff1f2",
    titleEnd: "#fda4af",
    body: "#abb3c1",
    badgeBg: "rgba(244,63,94,0.13)",
    badgeBorder: "rgba(244,63,94,0.34)",
    badgeText: "#fda4af",
    tagBg: "rgba(38,10,18,0.66)",
    tagBorder: "rgba(251,113,133,0.34)",
    tagText: "#fecdd3",
  },
  support: {
    bgStart: "#0b0a15",
    bgMid: "#151330",
    bgEnd: "#0c1020",
    grid: "#6366f1",
    orbA: "rgba(99,102,241,0.17)",
    orbB: "rgba(168,85,247,0.12)",
    accent: "#6366f1",
    accentSoft: "#a855f7",
    titleStart: "#eef2ff",
    titleEnd: "#c7d2fe",
    body: "#a3adc2",
    badgeBg: "rgba(99,102,241,0.13)",
    badgeBorder: "rgba(99,102,241,0.32)",
    badgeText: "#a5b4fc",
    tagBg: "rgba(19,19,46,0.67)",
    tagBorder: "rgba(129,140,248,0.35)",
    tagText: "#c7d2fe",
  },
  // Tokyo Night, matching the /omarchy hero (Omarchy's default theme).
  omarchy: {
    bgStart: "#0a0e1a",
    bgMid: "#16182a",
    bgEnd: "#1a1b26",
    grid: "#9ece6a",
    orbA: "rgba(158,206,106,0.18)",
    orbB: "rgba(187,154,247,0.16)",
    accent: "#9ece6a",
    accentSoft: "#7dcfff",
    titleStart: "#ffffff",
    titleEnd: "#9ece6a",
    body: "#a9b1d6",
    badgeBg: "rgba(158,206,106,0.12)",
    badgeBorder: "rgba(158,206,106,0.32)",
    badgeText: "#9ece6a",
    tagBg: "rgba(26,27,38,0.7)",
    tagBorder: "rgba(125,207,255,0.35)",
    tagText: "#7dcfff",
  },
};

function trimText(text: string, maxLength: number): string {
  const normalized = text.trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength - 1).trimEnd()}…`;
}

function titleFontSize(title: string, variant: SocialImageVariant): number {
  const length = title.length;
  if (variant === "twitter") {
    if (length > 58) return 54;
    if (length > 46) return 60;
    if (length > 34) return 66;
    return 74;
  }
  if (length > 58) return 60;
  if (length > 46) return 66;
  if (length > 34) return 72;
  return 80;
}

function CloudToolBadge({ label, top, left, color }: { label: string; top: number; left: number; color: string }) {
  return <div style={{ display: "flex", position: "absolute", top, left, width: 100, height: 48, alignItems: "center", justifyContent: "center", borderRadius: 12, background: "#0b1923", border: `1px solid ${color}`, color, fontSize: 28, fontWeight: 700, fontFamily: "monospace" }}>{label}</div>;
}

/** Route-specific art: a cloud surrounded by the tools in its flywheel. */
function createCloudAgentSocialImage(variant: SocialImageVariant): ImageResponse {
  const height = variant === "twitter" ? 600 : 630;
  return new ImageResponse(
    <div style={{ display: "flex", position: "relative", width: "100%", height: "100%", overflow: "hidden", background: "linear-gradient(135deg, #071018 0%, #0b1723 52%, #101329 100%)", color: "#f4f8ff", fontFamily: "sans-serif" }}>
      <div style={{ display: "flex", position: "absolute", right: -100, top: -80, width: 650, height: 700, background: "radial-gradient(circle, rgba(75,199,213,0.16) 0%, rgba(128,98,232,0.08) 45%, transparent 70%)" }} />
      <div style={{ display: "flex", position: "absolute", left: 58, top: 43, alignItems: "center", gap: 12 }}>
        <svg width="34" height="34" viewBox="0 0 34 34" fill="none"><circle cx="17" cy="17" r="14" stroke="#50ddcf" strokeWidth="2" /><path d="M12 11 L19 17 L12 23 M21 23 H26" stroke="#50ddcf" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
        <div style={{ display: "flex", fontSize: 23, fontWeight: 700, letterSpacing: "-0.02em" }}>Agent Flywheel</div>
      </div>
      <div style={{ display: "flex", position: "absolute", right: 54, top: 49, fontSize: 16, letterSpacing: "0.14em", color: "#9cb5c9" }}>CLOUD AGENT SETUP</div>
      <div style={{ display: "flex", position: "absolute", left: 58, top: 131, flexDirection: "column", width: 650 }}>
        <div style={{ display: "flex", fontSize: 76, fontWeight: 700, letterSpacing: "-0.045em", lineHeight: 1.06 }}>Give your</div>
        <div style={{ display: "flex", fontSize: 76, fontWeight: 700, letterSpacing: "-0.045em", lineHeight: 1.06 }}>cloud agent</div>
        <div style={{ display: "flex", fontSize: 76, fontWeight: 700, letterSpacing: "-0.045em", lineHeight: 1.06, color: "#50ddcf" }}>a flywheel.</div>
        <div style={{ display: "flex", marginTop: 25, fontSize: 24, lineHeight: 1.35, color: "#a9bdcf" }}>Real screenshots. Exact steps. Copy-ready scripts.</div>
      </div>
      <div style={{ display: "flex", position: "absolute", left: 58, top: 477, gap: 10 }}>
        <div style={{ display: "flex", alignItems: "center", padding: "10px 15px", borderRadius: 9, border: "1px solid #34555b", background: "#11272d", color: "#ddf9f4", fontSize: 18 }}>Claude Code</div>
        <div style={{ display: "flex", alignItems: "center", padding: "10px 15px", borderRadius: 9, border: "1px solid #354564", background: "#172337", color: "#e1eaff", fontSize: 18 }}>ChatGPT / Codex</div>
        <div style={{ display: "flex", alignItems: "center", padding: "10px 15px", borderRadius: 9, border: "1px solid #343953", color: "#b4c2d3", fontSize: 18 }}>More Linux agents</div>
      </div>
      <div style={{ display: "flex", position: "absolute", left: 720, top: 109, width: 420, height: 420 }}>
        <svg width="420" height="420" viewBox="0 0 420 420" fill="none" style={{ display: "flex", position: "absolute", left: 0, top: 0 }}>
          <defs><linearGradient id="cloud-wheel" x1="0" y1="0" x2="420" y2="420" gradientUnits="userSpaceOnUse"><stop stopColor="#50ddcf" /><stop offset="1" stopColor="#9b87ff" /></linearGradient></defs>
          <circle cx="210" cy="210" r="172" stroke="url(#cloud-wheel)" strokeWidth="2" opacity="0.6" />
          <circle cx="210" cy="210" r="130" stroke="url(#cloud-wheel)" strokeWidth="1" opacity="0.22" />
          <line x1="210" y1="210" x2="210" y2="38" stroke="#50ddcf" opacity="0.25" />
          <line x1="210" y1="210" x2="360" y2="124" stroke="#9b87ff" opacity="0.25" />
          <line x1="210" y1="210" x2="360" y2="296" stroke="#9b87ff" opacity="0.25" />
          <line x1="210" y1="210" x2="210" y2="382" stroke="#50ddcf" opacity="0.25" />
          <line x1="210" y1="210" x2="60" y2="296" stroke="#50ddcf" opacity="0.25" />
          <line x1="210" y1="210" x2="60" y2="124" stroke="#50ddcf" opacity="0.25" />
          <circle cx="210" cy="210" r="91" fill="#0b1e29" stroke="#335563" strokeWidth="1" />
          <path d="M166 228 H260 C282 228 296 211 291 191 C288 178 277 169 264 168 C257 146 238 132 216 132 C188 132 166 151 161 175 C142 177 130 189 131 204 C132 218 145 228 166 228 Z" stroke="#6ce6db" strokeWidth="4" fill="#122e37" strokeLinejoin="round" />
          <path d="M205 157 L222 170 L205 183 M228 183 H244" stroke="#a5f7ef" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M338 68 L350 84 L330 84 Z" fill="#8e90ff" />
          <path d="M76 345 L63 330 L83 330 Z" fill="#50ddcf" />
        </svg>
        <div style={{ display: "flex", position: "absolute", top: 240, left: 141, width: 138, justifyContent: "center", fontSize: 23, fontWeight: 700 }}>Flywheel</div>
        <CloudToolBadge label="br" top={14} left={160} color="#50ddcf" />
        <CloudToolBadge label="bv" top={100} left={310} color="#a697ff" />
        <CloudToolBadge label="am" top={272} left={310} color="#a697ff" />
        <CloudToolBadge label="ubs" top={358} left={160} color="#50ddcf" />
        <CloudToolBadge label="cass" top={272} left={10} color="#50ddcf" />
        <CloudToolBadge label="jsm" top={100} left={10} color="#50ddcf" />
      </div>
      <div style={{ display: "flex", position: "absolute", left: 58, bottom: 30, color: "#82a5b4", fontSize: 18 }}>agent-flywheel.com/cloud-agents</div>
      <div style={{ display: "flex", position: "absolute", right: 58, bottom: 30, color: "#a9bdcf", fontSize: 18 }}>11 executables · 10 prebuilt bundles</div>
      <div style={{ display: "flex", position: "absolute", left: 0, right: 0, bottom: 0, height: 4, background: "linear-gradient(90deg, #50ddcf, #7cbafa, #9b87ff)" }} />
    </div>,
    { width: 1200, height },
  );
}

export function createSocialImage(
  data: SocialImageData,
  variant: SocialImageVariant,
): ImageResponse {
  if (data.path === "/cloud-agents") return createCloudAgentSocialImage(variant);
  const width = 1200;
  const height = variant === "twitter" ? 600 : 630;
  const palette = PALETTES[data.theme ?? "default"];
  const safeDescription = trimText(data.description, variant === "twitter" ? 128 : 150);
  const safeTags = (data.tags ?? []).slice(0, 3);
  const safePath = trimText(data.path, 66);

  return new ImageResponse(
    <div
      style={{
        height: "100%",
        width: "100%",
        display: "flex",
        position: "relative",
        overflow: "hidden",
        alignItems: "stretch",
        justifyContent: "flex-start",
        background: `linear-gradient(140deg, ${palette.bgStart} 0%, ${palette.bgMid} 56%, ${palette.bgEnd} 100%)`,
        fontFamily: "Inter, system-ui, -apple-system, Segoe UI, sans-serif",
      }}
    >
      <div
        style={{
          display: "flex",
          position: "absolute",
          inset: 0,
          opacity: 0.05,
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='44' height='44' viewBox='0 0 44 44' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='${encodeURIComponent(
            palette.grid,
          )}' stroke-width='0.55'%3E%3Cpath d='M0 22h44M22 0v44'/%3E%3C/g%3E%3C/svg%3E")`,
        }}
      />

      <div
        style={{
          display: "flex",
          position: "absolute",
          top: -140,
          left: -120,
          width: 430,
          height: 430,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${palette.orbA} 0%, transparent 66%)`,
        }}
      />

      <div
        style={{
          display: "flex",
          position: "absolute",
          right: -140,
          bottom: -170,
          width: 520,
          height: 520,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${palette.orbB} 0%, transparent 70%)`,
        }}
      />

      <div
        style={{
          display: "flex",
          position: "absolute",
          right: 36,
          top: 32,
          color: "#64748b",
          fontSize: 22,
          letterSpacing: "0.02em",
          opacity: 0.9,
        }}
      >
        {`agent-flywheel.com${safePath}`}
      </div>

      <div
        style={{
          display: "flex",
          width: "100%",
          height: "100%",
          alignItems: "center",
          justifyContent: "center",
          gap: variant === "twitter" ? 44 : 52,
          padding: variant === "twitter" ? "56px 58px 60px 58px" : "58px 64px 62px 64px",
          zIndex: 2,
        }}
      >
        <div
          style={{
            display: "flex",
            width: variant === "twitter" ? 268 : 286,
            height: variant === "twitter" ? 268 : 286,
            alignItems: "center",
            justifyContent: "center",
            position: "relative",
            flexShrink: 0,
          }}
        >
          <div
            style={{
              display: "flex",
              position: "absolute",
              width: "100%",
              height: "100%",
              borderRadius: "50%",
              background: `radial-gradient(circle, ${palette.orbA} 0%, transparent 72%)`,
            }}
          />

          <div
            style={{
              display: "flex",
              position: "absolute",
              width: variant === "twitter" ? 190 : 204,
              height: variant === "twitter" ? 190 : 204,
              borderRadius: "50%",
              border: `3px solid ${palette.accent}`,
              boxShadow: `0 0 0 1px ${palette.accentSoft}`,
              opacity: 0.86,
            }}
          />

          <div
            style={{
              display: "flex",
              position: "absolute",
              width: variant === "twitter" ? 138 : 150,
              height: variant === "twitter" ? 138 : 150,
              borderRadius: "50%",
              border: `1.5px solid ${palette.accentSoft}`,
              opacity: 0.48,
            }}
          />

          <div
            style={{
              display: "flex",
              position: "absolute",
              width: variant === "twitter" ? 10 : 12,
              height: variant === "twitter" ? 10 : 12,
              borderRadius: "50%",
              background: palette.accent,
              boxShadow: `0 0 18px ${palette.accent}`,
            }}
          />

          <div
            style={{
              display: "flex",
              position: "absolute",
              width: 2,
              height: variant === "twitter" ? 154 : 168,
              background: palette.accentSoft,
              opacity: 0.4,
            }}
          />

          <div
            style={{
              display: "flex",
              position: "absolute",
              width: variant === "twitter" ? 154 : 168,
              height: 2,
              background: palette.accentSoft,
              opacity: 0.4,
            }}
          />
        </div>

        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "flex-start",
            justifyContent: "center",
            flex: 1,
            minWidth: 0,
            maxWidth: 760,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              borderRadius: 999,
              padding: "8px 18px",
              background: palette.badgeBg,
              border: `1px solid ${palette.badgeBorder}`,
              marginBottom: 18,
            }}
          >
            <span
              style={{
                display: "flex",
                color: palette.badgeText,
                fontSize: 22,
                letterSpacing: "0.1em",
                fontWeight: 600,
                textTransform: "uppercase",
              }}
            >
              {data.badge}
            </span>
          </div>

          <h1
            style={{
              display: "flex",
              margin: 0,
              marginBottom: 16,
              fontSize: titleFontSize(data.title, variant),
              lineHeight: 1.14,
              letterSpacing: "-0.03em",
              fontWeight: 700,
              color: "transparent",
              background: `linear-gradient(118deg, ${palette.titleStart} 0%, ${palette.titleEnd} 100%)`,
              backgroundClip: "text",
              maxWidth: "100%",
            }}
          >
            {data.title}
          </h1>

          <p
            style={{
              display: "flex",
              margin: 0,
              marginBottom: safeTags.length > 0 ? 26 : 0,
              fontSize: variant === "twitter" ? 38 : 40,
              lineHeight: 1.45,
              color: palette.body,
              maxWidth: "100%",
            }}
          >
            {safeDescription}
          </p>

          {safeTags.length > 0 ? (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 14,
              }}
            >
              {safeTags.map((tag) => (
                <div
                  key={tag}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    borderRadius: 14,
                    padding: "8px 14px",
                    background: palette.tagBg,
                    border: `1px solid ${palette.tagBorder}`,
                  }}
                >
                  <span
                    style={{
                      display: "flex",
                      color: palette.tagText,
                      fontSize: 24,
                      fontWeight: 500,
                      lineHeight: 1.2,
                    }}
                  >
                    {tag}
                  </span>
                </div>
              ))}
            </div>
          ) : null}
        </div>
      </div>

      <div
        style={{
          display: "flex",
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 4,
          background: `linear-gradient(90deg, transparent 0%, ${palette.accent} 25%, ${palette.accentSoft} 50%, ${palette.accent} 75%, transparent 100%)`,
        }}
      />
    </div>,
    { width, height },
  );
}
