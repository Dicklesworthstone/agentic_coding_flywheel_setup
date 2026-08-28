import type { Metadata } from "next";

const siteUrl = "https://agent-flywheel.com";

export const metadata: Metadata = {
  title: "Learning Hub",
  description:
    "Master agentic coding with interactive lessons covering Linux basics, tmux, git, AI agents, and the complete Agent Flywheel stack. From zero to autonomous coding workflows.",
  alternates: {
    canonical: `${siteUrl}/learn`,
  },
};

export default function LearnLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // The Learning Hub is a dark-only surface (hardcoded black + white/NN
  // text). The `dark` wrapper re-applies the dark tokens so a visitor who
  // chose the light theme in the wizard does not get dark headings on black.
  return <div className="dark contents">{children}</div>;
}
