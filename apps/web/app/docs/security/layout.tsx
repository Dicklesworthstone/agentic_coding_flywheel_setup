import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Security Best Practices",
  description:
    "Secure your agentic coding setup with Google SSO strategy. Interactive checklist for 2FA, recovery setup, app permissions, and password management.",
  openGraph: {
    title: "Security Best Practices | Agent Flywheel",
    description:
      "Google SSO strategy for securing your agentic coding environment. Interactive security checklist.",
    type: "article",
    url: "https://agent-flywheel.com/docs/security",
    siteName: "Agent Flywheel",
  },
  twitter: {
    card: "summary_large_image",
    title: "Security Best Practices | Agent Flywheel",
    description:
      "Google SSO strategy and interactive security checklist for agentic coding.",
    creator: "@jeffreyemanuel",
  },
};

export default function SecurityLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
