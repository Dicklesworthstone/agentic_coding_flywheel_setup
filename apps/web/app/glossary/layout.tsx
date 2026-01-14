import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Glossary",
  description:
    "Plain-English definitions for agentic coding terms. SSH, VPS, tmux, MCP, and 50+ more terms explained simply.",
  openGraph: {
    title: "Glossary | Agent Flywheel",
    description:
      "Plain-English definitions for shell, networking, and agentic coding terms. 50+ terms explained simply.",
    type: "website",
    url: "https://agent-flywheel.com/glossary",
    siteName: "Agent Flywheel",
  },
  twitter: {
    card: "summary_large_image",
    title: "Glossary | Agent Flywheel",
    description:
      "Plain-English definitions for agentic coding terms. SSH, VPS, tmux, and more.",
    creator: "@jeffreyemanuel",
  },
};

export default function GlossaryLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
