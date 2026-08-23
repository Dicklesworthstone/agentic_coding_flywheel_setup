import type { Metadata } from "next";
import type { ReactNode } from "react";

/**
 * Server-owned metadata for the /omarchy route. The page itself is a client
 * component (site convention — see app/page.tsx) because it renders
 * framer-motion variants directly.
 */
export const metadata: Metadata = {
  title: "ACFS on Omarchy — The Flywheel, Native on Arch",
  description:
    "The Agentic Coding Flywheel Setup runs natively on Omarchy and Arch Linux: pacman-native packages, your starship prompt untouched, oh-my-zsh skipped by design, doctor-verified with zero failures. One command.",
  alternates: {
    canonical: "/omarchy",
  },
  openGraph: {
    title: "ACFS on Omarchy — The Flywheel, Native on Arch",
    description:
      "72 modules · 3 AI agents · 30+ tools · 1 command. The full agentic coding flywheel, native on Arch — no apt, no oh-my-zsh, no compromises.",
    url: "/omarchy",
    siteName: "Agent Flywheel",
    type: "website",
  },
};

export default function OmarchyLayout({ children }: { children: ReactNode }) {
  return children;
}
