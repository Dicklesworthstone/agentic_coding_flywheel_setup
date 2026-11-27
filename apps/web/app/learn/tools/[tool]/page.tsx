import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getTool, TOOL_IDS } from "./tool-data";
import { ToolPageContent } from "./tool-page-content";

interface Props {
  params: Promise<{ tool: string }>;
}

/**
 * Generate static paths for all tool pages at build time.
 * This enables ISR and better performance.
 */
export function generateStaticParams(): { tool: string }[] {
  return TOOL_IDS.map((tool) => ({ tool }));
}

/**
 * Generate SEO metadata for each tool page.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { tool } = await params;
  const doc = getTool(tool);

  if (!doc) {
    return {
      title: "Tool Not Found | ACFS Learning Hub",
    };
  }

  return {
    title: `${doc.title} | ACFS Learning Hub`,
    description: doc.tagline,
  };
}

export default async function ToolCardPage({ params }: Props) {
  const { tool } = await params;
  const doc = getTool(tool);

  if (!doc) {
    notFound();
  }

  return <ToolPageContent tool={doc} />;
}
