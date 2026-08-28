import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "The Agentic Coding Flywheel - TL;DR",
  description:
    "A comprehensive overview of 13 open-source tools that work together to supercharge multi-agent AI coding workflows. NTM, SLB, Agent Mail, Beads Viewer, UBS, CASS Memory, CASS Search, and more.",
  alternates: {
    canonical: "/tldr",
  },
};

export default function TldrLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // Dark-only surface: keep dark tokens even when the wizard's light theme
  // is active (the catalog cards and hero use white text on black).
  return <div className="dark bg-background text-foreground">{children}</div>;
}
