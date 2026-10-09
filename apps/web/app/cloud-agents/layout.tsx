import type { Metadata } from "next";
import type { ReactNode } from "react";

/**
 * Server-owned metadata for the /cloud-agents route. The page itself is a
 * client component because its provider switcher and copy controls are interactive.
 */
const TITLE = "Flywheel tools for cloud agents";
const DESCRIPTION =
  "Step-by-step cloud agent setup with real screenshots and copy-ready scripts. Claude Code, ChatGPT / Codex, Amp Orbs, Devin, Grok Bot and other Linux agents.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: {
    canonical: "/cloud-agents",
  },
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    url: "/cloud-agents",
    siteName: "Agent Flywheel",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

export default function CloudAgentsLayout({ children }: { children: ReactNode }) {
  return children;
}
