import { notFound } from "next/navigation";
import { createSocialImage } from "@/lib/social-image";
import { toolSocialData } from "@/lib/social-image-routes";
import { getTool } from "./tool-data";

// The card shows the tool's example command only when it is one short
// invocation; pipelines and long examples fall back to tags (toolSocialData).
export const alt =
  "Agent Flywheel tool deep dive card: the tool's name, what it does, and an example command";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
// Share card design 2: see SOCIAL_CARD_DESIGN in lib/social-image.tsx.

export default async function Image({ params }: { params: Promise<{ tool: string }> }) {
  const { tool } = await params;
  const doc = getTool(tool);
  if (!doc) notFound();
  return createSocialImage(toolSocialData(doc), "opengraph");
}
