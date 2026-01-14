import type { Metadata } from "next";

export const metadata: Metadata = {
  title: {
    template: "%s | Docs | Agent Flywheel",
    default: "Documentation",
  },
  description:
    "Comprehensive guides for securing your agentic coding environment. Security best practices, Google SSO strategy, and 2FA setup.",
  openGraph: {
    title: "Documentation | Agent Flywheel",
    description:
      "Security, architecture, and best practices for agentic coding environments.",
    type: "website",
    url: "https://agent-flywheel.com/docs",
    siteName: "Agent Flywheel",
  },
  twitter: {
    card: "summary_large_image",
    title: "Documentation | Agent Flywheel",
    description:
      "Security, architecture, and best practices for agentic coding.",
    creator: "@jeffreyemanuel",
  },
};

export default function DocsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
