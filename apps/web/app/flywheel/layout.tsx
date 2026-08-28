import type { Metadata } from "next";
import { flywheelTools } from "@/lib/flywheel";

const siteUrl = "https://agent-flywheel.com";

export const metadata: Metadata = {
  title: "The Flywheel",
  // Derived from the same data the page renders so the share text cannot
  // drift from the catalog (it said "Twenty" while the page listed 39).
  description: `${flywheelTools.length} interconnected tools that enable multiple AI agents to work in parallel, review each other's work, and make incredible autonomous progress while you're away.`,
  alternates: {
    canonical: `${siteUrl}/flywheel`,
  },
};

export default function FlywheelLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // Dark-only surface: keep dark tokens even when the wizard's light theme
  // is active (the tool visualization uses white text on black).
  return <div className="dark bg-background text-foreground">{children}</div>;
}
