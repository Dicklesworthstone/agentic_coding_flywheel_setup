import type { Metadata } from "next";
import { instrumentSerif } from "@/app/fonts/instrument-serif";

// Share images come from opengraph-image.tsx and twitter-image.tsx: Next gives
// file-based images precedence over `images` here, and versions their URLs by
// the route file's content hash.
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
  },
  twitter: {
    card: "summary_large_image",
    creator: "@doodlestein",
  },
};

export default function CoreFlywheelLayout({ children }: { children: React.ReactNode }) {
  // Dark-only editorial surface (#020408 background, white text): keep the
  // dark tokens even when the wizard's light theme is active.
  return (
    <div className={`${instrumentSerif.variable} dark bg-background text-foreground`}>
      {children}
    </div>
  );
}
