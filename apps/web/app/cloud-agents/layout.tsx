import type { Metadata } from "next";
import type { ReactNode } from "react";

/**
 * Server-owned metadata for the /cloud-agents route. The page itself is a
 * client component (site convention — see app/page.tsx) because it renders
 * framer-motion variants directly.
 */
const TITLE = "Flywheel tools for cloud agents";
const DESCRIPTION =
  "Verified prebuilt Flywheel tools for Claude Code and ChatGPT / Codex, with researched setup recipes for Amp Orbs, Devin, Grok Bot and other Linux cloud agents.";

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
