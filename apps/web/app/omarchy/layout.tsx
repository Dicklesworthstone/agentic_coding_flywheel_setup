import type { Metadata } from "next";
import type { ReactNode } from "react";

/**
 * Server-owned metadata for the /omarchy route. The page itself is a client
 * component (site convention — see app/page.tsx) because it renders
 * framer-motion variants directly.
 *
 * og:image / twitter:image come from the sibling opengraph-image.tsx and
 * twitter-image.tsx file conventions (a dedicated Tokyo-Night card), so no
 * `images` field is needed here.
 */
const TITLE = "Native on Omarchy & Arch";
const DESCRIPTION =
  "The Agentic Coding Flywheel runs natively on Omarchy and Arch Linux: pacman packages, your starship prompt untouched, oh-my-zsh skipped by design. One command.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  keywords: [
    "Omarchy",
    "Arch Linux",
    "Hyprland",
    "pacman",
    "starship",
    "agentic coding",
    "Claude Code",
    "Codex CLI",
    "ACFS installer",
  ],
  alternates: {
    canonical: "/omarchy",
  },
  openGraph: {
    title: "The Flywheel, native on Omarchy",
    description:
      "72 modules · 3 AI agents · 30+ tools · 1 command. The full agentic coding flywheel on Arch — pacman-native, prompt preserved, no oh-my-zsh.",
    url: "/omarchy",
    siteName: "Agent Flywheel",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "The Flywheel, native on Omarchy",
    description:
      "One command installs the full agentic coding stack on Omarchy and Arch Linux — pacman-native, your starship prompt untouched.",
  },
};

export default function OmarchyLayout({ children }: { children: ReactNode }) {
  return children;
}
