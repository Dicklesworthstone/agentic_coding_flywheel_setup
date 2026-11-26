import { notFound } from "next/navigation";
import { createSocialImage } from "@/lib/social-image";
import { toolSocialData } from "@/lib/social-image-routes";
import type { ToolId } from "./tool-data";
import { TOOLS } from "./tool-data";

export const runtime = "edge";
export const alt =
  "Agent Flywheel tool deep dive card: the tool's name, what it does, and an example command";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ tool: string }> }) {
  const { tool } = await params;
  const doc = TOOLS[tool as ToolId];
  if (!doc) notFound();
  return createSocialImage(toolSocialData(doc), "opengraph");
}
