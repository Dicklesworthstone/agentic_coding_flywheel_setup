import type { Metadata } from "next";
import { ogVersion } from "@/lib/og-version";

const alt = "The Core Flywheel - Agent Mail, Beads & bv";

export const metadata: Metadata = {
  title: "The Core Flywheel - Agent Mail, Beads & bv",
  description:
    "The focused, beginner-friendly version of the Agentic Coding Flywheel. Learn the three-tool core loop: Agent Mail for coordination, br for task management, and bv for graph-aware triage.",
  alternates: {
    canonical: "/core-flywheel",
  },
  openGraph: {
    type: "article",
    url: "https://agent-flywheel.com/core-flywheel",
    siteName: "Agent Flywheel",
    locale: "en_US",
    images: [{ url: `/core-flywheel/opengraph-image?v=${ogVersion}`, width: 1200, height: 630, alt }],
  },
  twitter: {
    card: "summary_large_image",
    creator: "@doodlestein",
    images: [{ url: `/core-flywheel/twitter-image?v=${ogVersion}`, width: 1200, height: 600, alt }],
  },
};

export default function CoreFlywheelLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // Dark-only editorial surface (#020408 background, white text): keep the
  // dark tokens even when the wizard's light theme is active.
  return <div className="dark bg-background text-foreground">{children}</div>;
}
