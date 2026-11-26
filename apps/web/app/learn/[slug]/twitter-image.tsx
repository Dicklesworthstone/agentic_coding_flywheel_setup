import { notFound } from "next/navigation";
import { getLessonBySlug, LESSONS } from "@/lib/lessons";
import { createSocialImage } from "@/lib/social-image";
import { lessonSocialData } from "@/lib/social-image-routes";

export const runtime = "edge";
export const alt =
  "Agent Flywheel learning hub lesson card: the lesson title, what it covers, and how long it takes";
export const size = { width: 1200, height: 600 };
export const contentType = "image/png";
// Share card design 2: see SOCIAL_CARD_DESIGN in lib/social-image.tsx.

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);
  if (!lesson) notFound();
  return createSocialImage(lessonSocialData(lesson, LESSONS.length), "twitter");
}
