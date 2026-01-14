import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Troubleshooting",
  description:
    "Quick fixes for common SSH, installation, agent, and network issues. Step-by-step solutions with copy-paste commands.",
  openGraph: {
    title: "Troubleshooting | Agent Flywheel",
    description:
      "Quick fixes for common SSH, installation, agent, and network issues. Step-by-step solutions.",
    type: "website",
    url: "https://agent-flywheel.com/troubleshooting",
    siteName: "Agent Flywheel",
  },
  twitter: {
    card: "summary_large_image",
    title: "Troubleshooting | Agent Flywheel",
    description:
      "Quick fixes for common issues. SSH, installation, agents, and network problems solved.",
    creator: "@jeffreyemanuel",
  },
};

export default function TroubleshootingLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
