"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import {
  ArrowLeft,
  ArrowRight,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  GraduationCap,
  Home,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  type Lesson,
  LESSONS,
  getNextLesson,
  getPreviousLesson,
  useCompletedLessons,
} from "@/lib/lessonProgress";

interface Props {
  lesson: Lesson;
  content: string;
}

function LessonSidebar({
  currentLessonId,
  completedLessons,
}: {
  currentLessonId: number;
  completedLessons: number[];
}) {
  return (
    <aside className="sticky top-0 hidden h-screen w-72 shrink-0 overflow-y-auto border-r border-border/50 bg-sidebar/80 backdrop-blur-sm lg:block">
      <div className="flex h-full flex-col">
        {/* Header */}
        <div className="flex items-center gap-3 border-b border-border/50 px-6 py-5">
          <Link
            href="/learn"
            className="flex items-center gap-2 transition-opacity hover:opacity-80"
          >
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
              <GraduationCap className="h-4 w-4 text-primary" />
            </div>
            <span className="font-mono text-sm font-bold tracking-tight">
              Learning Hub
            </span>
          </Link>
        </div>

        {/* Lesson list */}
        <nav className="flex-1 px-4 py-4">
          <ul className="space-y-1">
            {LESSONS.map((lesson) => {
              const isCompleted = completedLessons.includes(lesson.id);
              const isCurrent = lesson.id === currentLessonId;

              return (
                <li key={lesson.id}>
                  <Link
                    href={`/learn/${lesson.slug}`}
                    className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors ${
                      isCurrent
                        ? "bg-primary/10 text-primary"
                        : "text-muted-foreground hover:bg-muted hover:text-foreground"
                    }`}
                  >
                    <div
                      className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-mono ${
                        isCompleted
                          ? "bg-[oklch(0.72_0.19_145)] text-white"
                          : isCurrent
                            ? "bg-primary text-primary-foreground"
                            : "bg-muted text-muted-foreground"
                      }`}
                    >
                      {isCompleted ? (
                        <Check className="h-3 w-3" />
                      ) : (
                        lesson.id + 1
                      )}
                    </div>
                    <span className="line-clamp-1">{lesson.title}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        {/* Footer */}
        <div className="border-t border-border/50 p-4">
          <Button
            asChild
            variant="ghost"
            size="sm"
            className="w-full justify-start text-muted-foreground hover:text-foreground"
          >
            <Link href="/">
              <Home className="mr-2 h-4 w-4" />
              Back to Home
            </Link>
          </Button>
        </div>
      </div>
    </aside>
  );
}

export function LessonContent({ lesson, content }: Props) {
  const router = useRouter();
  const [completedLessons, markComplete] = useCompletedLessons();
  const isCompleted = completedLessons.includes(lesson.id);
  const prevLesson = getPreviousLesson(lesson.id);
  const nextLesson = getNextLesson(lesson.id);

  const handleMarkComplete = () => {
    markComplete(lesson.id);
    if (nextLesson) {
      router.push(`/learn/${nextLesson.slug}`);
    }
  };

  return (
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      <div className="relative flex">
        {/* Desktop sidebar */}
        <LessonSidebar
          currentLessonId={lesson.id}
          completedLessons={completedLessons}
        />

        {/* Main content */}
        <main className="flex-1 pb-32 lg:pb-8">
          {/* Mobile header */}
          <div className="sticky top-0 z-20 flex items-center justify-between border-b border-border/50 bg-background/80 px-4 py-3 backdrop-blur-sm lg:hidden">
            <Link
              href="/learn"
              className="flex items-center gap-2 text-muted-foreground"
            >
              <ArrowLeft className="h-4 w-4" />
              <span className="text-sm">All Lessons</span>
            </Link>
            <div className="text-xs text-muted-foreground">
              <span className="font-mono text-primary">{lesson.id + 1}</span> of{" "}
              {LESSONS.length}
            </div>
          </div>

          {/* Content area */}
          <div className="px-6 py-8 md:px-12 md:py-12">
            <div className="mx-auto max-w-2xl">
              {/* Lesson header */}
              <div className="mb-8">
                <div className="mb-4 flex items-center gap-4 text-sm text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <BookOpen className="h-4 w-4" />
                    Lesson {lesson.id + 1}
                  </span>
                  <span className="flex items-center gap-1">
                    <Clock className="h-4 w-4" />
                    {lesson.duration}
                  </span>
                  {isCompleted && (
                    <span className="flex items-center gap-1 text-[oklch(0.72_0.19_145)]">
                      <Check className="h-4 w-4" />
                      Completed
                    </span>
                  )}
                </div>
                <h1 className="text-3xl font-bold tracking-tight">
                  {lesson.title}
                </h1>
                <p className="mt-2 text-lg text-muted-foreground">
                  {lesson.description}
                </p>
              </div>

              {/* Markdown content */}
              <article className="prose prose-invert max-w-none prose-headings:font-bold prose-headings:tracking-tight prose-h1:text-2xl prose-h2:mt-8 prose-h2:text-xl prose-h3:text-lg prose-p:text-muted-foreground prose-a:text-primary prose-a:no-underline hover:prose-a:underline prose-code:rounded prose-code:bg-muted prose-code:px-1.5 prose-code:py-0.5 prose-code:font-mono prose-code:text-sm prose-code:before:content-none prose-code:after:content-none prose-pre:rounded-lg prose-pre:border prose-pre:border-border/50 prose-pre:bg-muted/50 prose-li:text-muted-foreground">
                <ReactMarkdown
                  remarkPlugins={[remarkGfm]}
                  rehypePlugins={[rehypeHighlight]}
                >
                  {content}
                </ReactMarkdown>
              </article>

              {/* Mark complete button */}
              <Card className="mt-12 border-primary/20 bg-primary/5 p-6">
                <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <h3 className="font-semibold">
                      {isCompleted ? "Lesson completed!" : "Finished this lesson?"}
                    </h3>
                    <p className="text-sm text-muted-foreground">
                      {isCompleted
                        ? nextLesson
                          ? "Ready to move on to the next one?"
                          : "You've completed all lessons!"
                        : "Mark it complete to track your progress."}
                    </p>
                  </div>
                  <Button
                    onClick={handleMarkComplete}
                    disabled={isCompleted && !nextLesson}
                    className={
                      isCompleted
                        ? "bg-[oklch(0.72_0.19_145)] hover:bg-[oklch(0.65_0.19_145)]"
                        : ""
                    }
                  >
                    {isCompleted ? (
                      nextLesson ? (
                        <>
                          Next Lesson
                          <ArrowRight className="ml-1 h-4 w-4" />
                        </>
                      ) : (
                        <>
                          <Check className="mr-1 h-4 w-4" />
                          All Done!
                        </>
                      )
                    ) : (
                      <>
                        <Check className="mr-1 h-4 w-4" />
                        Mark Complete
                      </>
                    )}
                  </Button>
                </div>
              </Card>

              {/* Navigation (desktop) */}
              <div className="mt-8 hidden items-center justify-between lg:flex">
                {prevLesson ? (
                  <Button variant="ghost" asChild>
                    <Link href={`/learn/${prevLesson.slug}`}>
                      <ChevronLeft className="mr-1 h-4 w-4" />
                      {prevLesson.title}
                    </Link>
                  </Button>
                ) : (
                  <div />
                )}
                {nextLesson && (
                  <Button asChild>
                    <Link href={`/learn/${nextLesson.slug}`}>
                      {nextLesson.title}
                      <ChevronRight className="ml-1 h-4 w-4" />
                    </Link>
                  </Button>
                )}
              </div>
            </div>
          </div>
        </main>
      </div>

      {/* Mobile navigation */}
      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-border/50 bg-background/95 p-4 backdrop-blur-md lg:hidden">
        <div className="flex items-center gap-3">
          <Button
            variant="outline"
            className="flex-1"
            disabled={!prevLesson}
            asChild={!!prevLesson}
          >
            {prevLesson ? (
              <Link href={`/learn/${prevLesson.slug}`}>
                <ChevronLeft className="mr-1 h-5 w-5" />
                Previous
              </Link>
            ) : (
              <>
                <ChevronLeft className="mr-1 h-5 w-5" />
                Previous
              </>
            )}
          </Button>
          <Button
            className="flex-1"
            disabled={!nextLesson}
            asChild={!!nextLesson}
          >
            {nextLesson ? (
              <Link href={`/learn/${nextLesson.slug}`}>
                Next
                <ChevronRight className="ml-1 h-5 w-5" />
              </Link>
            ) : (
              <>
                Next
                <ChevronRight className="ml-1 h-5 w-5" />
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
