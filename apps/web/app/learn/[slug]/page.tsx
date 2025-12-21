import { notFound } from "next/navigation";
import { Metadata } from "next";
import fs from "fs/promises";
import path from "path";
import { LESSONS, getLessonBySlug } from "@/lib/lessonProgress";
import { LessonContent } from "./lesson-content";

interface Props {
  params: Promise<{ slug: string }>;
}

// Generate static paths for all lessons
export async function generateStaticParams() {
  return LESSONS.map((lesson) => ({
    slug: lesson.slug,
  }));
}

// Generate metadata for each lesson
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);

  if (!lesson) {
    return { title: "Lesson Not Found" };
  }

  return {
    title: `${lesson.title} | ACFS Learning Hub`,
    description: lesson.description,
  };
}

// Load markdown content at build time
async function loadLessonContent(filename: string): Promise<string> {
  const lessonsDir = path.join(process.cwd(), "..", "..", "acfs", "onboard", "lessons");
  const filePath = path.join(lessonsDir, filename);

  try {
    const content = await fs.readFile(filePath, "utf-8");
    return content;
  } catch {
    // Fallback: try from project root
    const altPath = path.join(process.cwd(), "../../acfs/onboard/lessons", filename);
    try {
      return await fs.readFile(altPath, "utf-8");
    } catch {
      return `# Content Not Found\n\nThe lesson content file \`${filename}\` could not be loaded.`;
    }
  }
}

export default async function LessonPage({ params }: Props) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);

  if (!lesson) {
    notFound();
  }

  const content = await loadLessonContent(lesson.file);

  return <LessonContent lesson={lesson} content={content} />;
}
