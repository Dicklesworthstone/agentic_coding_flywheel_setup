import type { Metadata } from "next";
import type { ReactNode } from "react";

/**
 * Server-owned metadata for the /claude-code-web route. The page itself is a
 * client component (site convention — see app/page.tsx) because it renders
 * framer-motion variants directly.
 */
const TITLE = "ACFS for Claude Code on the web";
const DESCRIPTION =
  "One setup script puts br, bv, Agent Mail, ubs, cass, and the rest of the agent-facing flywheel stack into every Claude Code cloud session, verified against the same checksums as install.sh.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: {
    canonical: "/claude-code-web",
  },
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    url: "/claude-code-web",
    siteName: "Agent Flywheel",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

export default function ClaudeCodeWebLayout({ children }: { children: ReactNode }) {
  return children;
}
