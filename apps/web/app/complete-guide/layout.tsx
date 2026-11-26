import type { Metadata } from "next";
import { instrumentSerif } from "@/app/fonts/instrument-serif";
import { COMPLETE_GUIDE_REVIEWED_ON } from "@/lib/complete-guide";

// Share images come from opengraph-image.tsx and twitter-image.tsx: Next gives
// file-based images precedence over `images` here, and versions their URLs by
// the route file's content hash.
export const metadata: Metadata = {
  title: "The Complete Flywheel Guide - Planning, Beads & Agent Swarms",
  description: `Jeffrey Emanuel's methodology for frontier-model planning, beads-based task management, validated ACFS tooling, and coordinated agent swarms. Reviewed ${COMPLETE_GUIDE_REVIEWED_ON}.`,
  alternates: {
    canonical: "/complete-guide",
  },
  openGraph: {
    type: "article",
    url: "https://agent-flywheel.com/complete-guide",
    siteName: "Agent Flywheel",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    creator: "@doodlestein",
  },
};

export default function CompleteGuideLayout({ children }: { children: React.ReactNode }) {
  // Dark-only editorial surface (#020408 background, white text): keep the
  // dark tokens even when the wizard's light theme is active.
  return (
    <div className={`${instrumentSerif.variable} dark bg-background text-foreground`}>
      {children}
    </div>
  );
}
