import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getLessonBySlug, LESSONS } from "@/lib/lessons";
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

export default async function LessonPage({ params }: Props) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);

  if (!lesson) {
    notFound();
  }

  return <LessonContent key={lesson.slug} lesson={lesson} />;
}
