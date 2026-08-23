import type { Metadata } from "next";
import type { ReactNode } from "react";
import { manifestModules } from "@/lib/generated/manifest-modules";

/**
 * Server-owned metadata for the /omarchy route. The page itself is a client
 * component (site convention — see app/page.tsx) because it renders
 * framer-motion variants directly.
 *
 * The module count derives from the generated manifest data so the share-card
 * copy cannot drift from the installer; "35+" matches the page's own tool
 * index (cornerstone + flywheel tiers).
 */
const SHARE_STATS = `${manifestModules.length} modules · 3 AI agents · 35+ tools · 1 command`;

export const metadata: Metadata = {
  title: "ACFS on Omarchy: the Flywheel, native on Arch",
  description:
    "The Agentic Coding Flywheel Setup runs natively on Omarchy and Arch Linux: system packages from pacman, your starship prompt left alone, oh-my-zsh skipped, and acfs doctor passing clean. One command.",
  alternates: {
    canonical: "/omarchy",
  },
  openGraph: {
    title: "ACFS on Omarchy: the Flywheel, native on Arch",
    description: `${SHARE_STATS}. The full agentic coding flywheel on Arch, installed with pacman and without oh-my-zsh.`,
    url: "/omarchy",
    siteName: "Agent Flywheel",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "ACFS on Omarchy: the Flywheel, native on Arch",
    description: `${SHARE_STATS}. The full agentic coding flywheel, native on Arch.`,
  },
};

export default function OmarchyLayout({ children }: { children: ReactNode }) {
  return children;
}
