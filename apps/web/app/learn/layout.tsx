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
  return children;
}
