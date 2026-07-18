import type { Metadata } from "next";
import { ogVersion } from "@/lib/og-version";

const alt = "The Flywheel Approach to Planning & Beads Creation";

export const metadata: Metadata = {
  title: "The Complete Flywheel Guide - Planning, Beads & Agent Swarms",
  description:
    "The July 2026 guide to Jeffrey Emanuel's methodology for frontier-model planning, beads-based task management, validated ACFS tooling, and coordinated agent swarms.",
  alternates: {
    canonical: "/complete-guide",
  },
  openGraph: {
    type: "article",
    url: "https://agent-flywheel.com/complete-guide",
    siteName: "Agent Flywheel",
    locale: "en_US",
    images: [{ url: `/complete-guide/opengraph-image?v=${ogVersion}`, width: 1200, height: 630, alt }],
  },
  twitter: {
    card: "summary_large_image",
    creator: "@doodlestein",
    images: [{ url: `/complete-guide/twitter-image?v=${ogVersion}`, width: 1200, height: 600, alt }],
  },
};

export default function CompleteGuideLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}
