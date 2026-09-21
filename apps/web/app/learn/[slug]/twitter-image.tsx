import { notFound } from "next/navigation";
import { getLessonBySlug } from "@/lib/lessons";
import { createSocialImage } from "@/lib/social-image";

export const runtime = "edge";

export const alt = "ACFS Lesson";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);

  if (!lesson) {
    notFound();
  }

  return createSocialImage(
    {
      badge: `Lesson ${lesson.id + 1}`,
      title: lesson.title,
      description: lesson.description,
      path: `/learn/${lesson.slug}`,
      theme: "learn",
      tags: [lesson.duration, "Learning Hub", "ACFS"],
    },
    "twitter",
  );
}
