import type { Metadata, Viewport } from "next";
import { Suspense } from "react";
import { JetBrains_Mono, Instrument_Sans } from "next/font/google";
import { QueryProvider } from "@/components/query-provider";
import { AnalyticsProvider } from "@/components/analytics-provider";
import { ThirdPartyScripts } from "@/components/third-party-scripts";
import { MotionProvider } from "@/components/motion/motion-provider";
import "./globals.css";

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains",
  subsets: ["latin"],
  display: "swap",
});

const instrumentSans = Instrument_Sans({
  variable: "--font-instrument",
  subsets: ["latin"],
  display: "swap",
});

const siteUrl = "https://agent-flywheel.com";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Agent Flywheel - AI Agents Coding For You",
    template: "%s | Agent Flywheel",
  },
  description:
    "Transform a fresh cloud server into a fully-configured agentic coding environment in ~30 minutes. Claude Code, OpenAI Codex, Google Antigravity: all pre-configured with 30+ modern developer tools. Free & open-source.",
  keywords: [
    "VPS setup",
    "AI coding",
    "Claude Code",
    "Codex CLI",
    "Antigravity CLI",
    "developer tools",
    "agentic coding",
    "Agent Flywheel",
    "AI agents",
    "coding automation",
    "Ubuntu VPS",
    "dev environment",
  ],
  authors: [{ name: "Jeffrey Emanuel", url: "https://jeffreyemanuel.com/" }],
  creator: "Jeffrey Emanuel",
  publisher: "Agent Flywheel",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    siteName: "Agent Flywheel",
    locale: "en_US",
    url: siteUrl,
  },
  twitter: {
    card: "summary_large_image",
    creator: "@doodlestein",
  },
  // Icons are auto-generated from icon.tsx and apple-icon.tsx
  // favicon.ico is also available as a fallback
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0a12",
  colorScheme: "dark light",
  viewportFit: "cover", // Enable safe area insets for notch/home bar
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <head>
        {/* Flash-prevention: apply stored theme before first paint */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var s=localStorage.getItem("acfs-theme")||"dark";var r=s==="system"?matchMedia("(prefers-color-scheme:light)").matches?"light":"dark":s;var d=document.documentElement;d.classList.remove("dark","light");d.classList.add(r==="light"?"light":"dark")}catch(e){}})()`,
          }}
        />
      </head>
      <body
        className={`${jetbrainsMono.variable} ${instrumentSans.variable} font-sans antialiased`}
      >
        {/* Noise texture overlay */}
        <div className="pointer-events-none fixed inset-0 z-50 bg-noise" />
        <Suspense fallback={null}>
          <ThirdPartyScripts />
        </Suspense>
        <QueryProvider>
          <MotionProvider>
            <AnalyticsProvider>{children}</AnalyticsProvider>
          </MotionProvider>
        </QueryProvider>
      </body>
    </html>
  );
}
