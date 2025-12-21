"use client";

import Link from "next/link";
import {
  BookOpen,
  Check,
  ChevronRight,
  Clock,
  GraduationCap,
  Home,
  Lock,
  Play,
  Terminal,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  LESSONS,
  TOTAL_LESSONS,
  useCompletedLessons,
  getCompletionPercentage,
  getNextUncompletedLesson,
} from "@/lib/lessonProgress";

type LessonStatus = "completed" | "current" | "locked";

function getLessonStatus(
  lessonId: number,
  completedLessons: number[]
): LessonStatus {
  if (completedLessons.includes(lessonId)) {
    return "completed";
  }
  // First uncompleted lesson is "current"
  const firstUncompleted = LESSONS.find(
    (l) => !completedLessons.includes(l.id)
  );
  if (firstUncompleted?.id === lessonId) {
    return "current";
  }
  return "locked";
}

function LessonCard({
  lesson,
  status,
}: {
  lesson: (typeof LESSONS)[0];
  status: LessonStatus;
}) {
  const isAccessible = status !== "locked";

  const cardContent = (
    <Card
      className={`group relative overflow-hidden p-5 transition-all ${
        status === "completed"
          ? "border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.05)]"
          : status === "current"
            ? "border-primary/50 bg-primary/5 ring-2 ring-primary/20"
            : "border-border/50 bg-muted/30 opacity-60"
      } ${isAccessible ? "cursor-pointer hover:border-primary/40 hover:shadow-md" : "cursor-not-allowed"}`}
    >
      {/* Status indicator */}
      <div className="absolute right-3 top-3">
        {status === "completed" ? (
          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-[oklch(0.72_0.19_145)]">
            <Check className="h-4 w-4 text-white" />
          </div>
        ) : status === "current" ? (
          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-primary">
            <Play className="h-3 w-3 text-primary-foreground" />
          </div>
        ) : (
          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-muted">
            <Lock className="h-3 w-3 text-muted-foreground" />
          </div>
        )}
      </div>

      {/* Lesson number */}
      <div className="mb-3 flex h-8 w-8 items-center justify-center rounded-lg bg-muted font-mono text-sm font-bold text-muted-foreground">
        {lesson.id + 1}
      </div>

      {/* Title */}
      <h3
        className={`mb-1 font-semibold ${status === "locked" ? "text-muted-foreground" : "text-foreground"}`}
      >
        {lesson.title}
      </h3>

      {/* Description */}
      <p className="mb-3 text-sm text-muted-foreground">{lesson.description}</p>

      {/* Duration */}
      <div className="flex items-center gap-1 text-xs text-muted-foreground">
        <Clock className="h-3 w-3" />
        <span>{lesson.duration}</span>
      </div>

      {/* Hover arrow */}
      {isAccessible && (
        <ChevronRight className="absolute bottom-4 right-4 h-5 w-5 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" />
      )}
    </Card>
  );

  if (isAccessible) {
    return <Link href={`/learn/${lesson.slug}`}>{cardContent}</Link>;
  }

  return cardContent;
}

export default function LearnDashboard() {
  const [completedLessons] = useCompletedLessons();
  const completionPercentage = getCompletionPercentage(completedLessons);
  const nextLesson = getNextUncompletedLesson(completedLessons);

  return (
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      <div className="relative mx-auto max-w-5xl px-6 py-8 md:px-12 md:py-12">
        {/* Header */}
        <div className="mb-8 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Home className="h-4 w-4" />
            <span className="text-sm">Home</span>
          </Link>
          <Link
            href="/wizard/os-selection"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Terminal className="h-4 w-4" />
            <span className="text-sm">Setup Wizard</span>
          </Link>
        </div>

        {/* Hero section */}
        <div className="mb-12 text-center">
          <div className="mb-4 flex justify-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 shadow-lg shadow-primary/20">
              <GraduationCap className="h-8 w-8 text-primary" />
            </div>
          </div>
          <h1 className="mb-3 text-3xl font-bold tracking-tight md:text-4xl">
            Learning Hub
          </h1>
          <p className="mx-auto max-w-xl text-lg text-muted-foreground">
            Master your new agentic coding environment with these hands-on
            lessons. Start from the basics and work your way to advanced
            workflows.
          </p>
        </div>

        {/* Progress card */}
        <Card className="mb-10 border-primary/20 bg-primary/5 p-6">
          <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="mb-2 flex items-center gap-2">
                <BookOpen className="h-5 w-5 text-primary" />
                <h2 className="font-semibold">Your Progress</h2>
              </div>
              <p className="text-sm text-muted-foreground">
                {completedLessons.length === TOTAL_LESSONS
                  ? "Congratulations! You've completed all lessons."
                  : nextLesson
                    ? `Up next: ${nextLesson.title}`
                    : "Start your learning journey"}
              </p>
            </div>

            <div className="flex items-center gap-4">
              {/* Circular progress */}
              <div className="relative h-16 w-16">
                <svg className="h-full w-full -rotate-90" viewBox="0 0 36 36">
                  <path
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    fill="none"
                    className="stroke-muted"
                    strokeWidth="3"
                  />
                  <path
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    fill="none"
                    className="stroke-primary"
                    strokeWidth="3"
                    strokeDasharray={`${completionPercentage}, 100`}
                    strokeLinecap="round"
                  />
                </svg>
                <div className="absolute inset-0 flex items-center justify-center">
                  <span className="font-mono text-sm font-bold">
                    {completionPercentage}%
                  </span>
                </div>
              </div>

              {/* Stats */}
              <div className="text-sm">
                <div className="font-mono text-2xl font-bold text-primary">
                  {completedLessons.length}/{TOTAL_LESSONS}
                </div>
                <div className="text-muted-foreground">lessons complete</div>
              </div>
            </div>
          </div>

          {/* Progress bar */}
          <div className="mt-4">
            <div className="h-2 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full bg-gradient-to-r from-primary to-[oklch(0.7_0.2_330)] transition-all duration-500"
                style={{ width: `${completionPercentage}%` }}
              />
            </div>
          </div>

          {/* Continue button */}
          {nextLesson && (
            <div className="mt-4">
              <Button asChild className="w-full sm:w-auto">
                <Link href={`/learn/${nextLesson.slug}`}>
                  Continue Learning
                  <ChevronRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
            </div>
          )}
        </Card>

        {/* Lessons grid */}
        <div className="mb-8">
          <h2 className="mb-4 text-xl font-semibold">All Lessons</h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {LESSONS.map((lesson) => (
              <LessonCard
                key={lesson.id}
                lesson={lesson}
                status={getLessonStatus(lesson.id, completedLessons)}
              />
            ))}
          </div>
        </div>

        {/* Quick reference links */}
        <Card className="p-6">
          <h2 className="mb-4 text-lg font-semibold">Quick Reference</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Link
              href="/learn/agent-commands"
              className="flex items-center gap-3 rounded-lg border border-border/50 p-4 transition-colors hover:border-primary/40 hover:bg-primary/5"
            >
              <Terminal className="h-5 w-5 text-muted-foreground" />
              <div>
                <div className="font-medium">Agent Commands</div>
                <div className="text-sm text-muted-foreground">
                  Claude, Codex, Gemini shortcuts
                </div>
              </div>
            </Link>
            <Link
              href="/learn/ntm-palette"
              className="flex items-center gap-3 rounded-lg border border-border/50 p-4 transition-colors hover:border-primary/40 hover:bg-primary/5"
            >
              <BookOpen className="h-5 w-5 text-muted-foreground" />
              <div>
                <div className="font-medium">NTM Commands</div>
                <div className="text-sm text-muted-foreground">
                  Session management reference
                </div>
              </div>
            </Link>
          </div>
        </Card>

        {/* Footer */}
        <div className="mt-12 text-center text-sm text-muted-foreground">
          <p>
            Need to set up your VPS first?{" "}
            <Link href="/wizard/os-selection" className="text-primary hover:underline">
              Start the setup wizard →
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
