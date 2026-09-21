import { notFound } from "next/navigation";
import { createSocialImage } from "@/lib/social-image";
import type { ToolId } from "./tool-data";
import { TOOLS } from "./tool-data";

export const runtime = "edge";

export const alt = "ACFS Tool";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ tool: string }> }) {
  const { tool } = await params;
  const doc = TOOLS[tool as ToolId];

  if (!doc) {
    notFound();
  }

  return createSocialImage(
    {
      badge: "Tool Deep Dive",
      title: doc.title,
      description: doc.tagline,
      path: `/learn/tools/${tool}`,
      theme: "tools",
      tags: [doc.id.toUpperCase(), "Learning Hub", "ACFS"],
    },
    "opengraph",
  );
}
