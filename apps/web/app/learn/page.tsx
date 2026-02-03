"use client";

import { useCallback, useEffect, useState, useRef } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Book,
  BookOpen,
  Check,
  ChevronRight,
  Clock,
  GraduationCap,
  Home,
  List,
  Lock,
  Play,
  Terminal,
  Sparkles,
  Zap,
} from "lucide-react";
import { motion } from "@/components/motion";
import { Button } from "@/components/ui/button";
import {
  LESSONS,
  TOTAL_LESSONS,
  useCompletedLessons,
  getCompletionPercentage,
  getNextUncompletedLesson,
} from "@/lib/lessonProgress";
import { springs } from "@/lib/design-tokens";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import { sendEvent, initLessonFunnel, getLessonFunnelData } from "@/lib/analytics";

type LessonStatus = "completed" | "current" | "locked";

function getLessonStatus(
  lessonId: number,
  completedLessons: number[]
): LessonStatus {
  if (completedLessons.includes(lessonId)) {
    return "completed";
  }
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
  index,
  isSelected,
  prefersReducedMotion,
}: {
  lesson: (typeof LESSONS)[0];
  status: LessonStatus;
  index: number;
  isSelected?: boolean;
  prefersReducedMotion?: boolean;
}) {
  const isAccessible = status !== "locked";

  const cardContent = (
    <motion.div
      initial={prefersReducedMotion ? false : { opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: index * 0.04 }}
      whileHover={isAccessible && !prefersReducedMotion ? { y: -6, scale: 1.02 } : undefined}
      whileTap={isAccessible && !prefersReducedMotion ? { scale: 0.98 } : undefined}
      className="h-full"
    >
      <div
        className={`group relative h-full overflow-hidden rounded-2xl border p-5 transition-all duration-500 ${
          status === "completed"
            ? "border-[oklch(0.72_0.19_145/0.4)] bg-[oklch(0.72_0.19_145/0.08)]"
            : status === "current"
              ? "border-primary/50 bg-primary/10"
              : "border-white/[0.06] bg-white/[0.02] opacity-60"
        } ${isAccessible ? "cursor-pointer hover:border-primary/60 hover:bg-white/[0.06]" : "cursor-not-allowed"} ${
          isSelected ? "ring-2 ring-primary ring-offset-2 ring-offset-black" : ""
        } backdrop-blur-xl`}
      >
        {/* Ambient glow on hover */}
        {isAccessible && (
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-primary/10 via-transparent to-emerald-500/5 opacity-0 transition-opacity duration-500 group-hover:opacity-100 group-focus-within:opacity-100" />
        )}

        {/* Top gradient line */}
        {status === "current" && (
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary to-transparent" />
        )}

        {/* Status indicator */}
        <div className="absolute right-4 top-4">
          {status === "completed" ? (
            <motion.div
              className="flex h-7 w-7 items-center justify-center rounded-full bg-[oklch(0.72_0.19_145)] shadow-lg shadow-[oklch(0.72_0.19_145/0.4)]"
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={springs.bouncy}
            >
              <Check className="h-4 w-4 text-white" />
            </motion.div>
          ) : status === "current" ? (
            <motion.div
              className="flex h-7 w-7 items-center justify-center rounded-full bg-primary shadow-lg shadow-primary/40"
              animate={prefersReducedMotion ? undefined : { scale: [1, 1.15, 1] }}
              transition={prefersReducedMotion ? undefined : { duration: 2, repeat: Infinity }}
            >
              <Play className="h-3.5 w-3.5 text-primary-foreground" />
            </motion.div>
          ) : (
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-white/[0.06] backdrop-blur">
              <Lock className="h-3.5 w-3.5 text-muted-foreground/60" />
            </div>
          )}
        </div>

        {/* Lesson number with glow */}
        <div className={`mb-4 flex h-10 w-10 items-center justify-center rounded-xl font-mono text-sm font-bold transition-all duration-300 ${
          status === "completed"
            ? "bg-[oklch(0.72_0.19_145/0.2)] text-[oklch(0.72_0.19_145)]"
            : status === "current"
              ? "bg-primary/20 text-primary shadow-lg shadow-primary/20"
              : "bg-white/[0.04] text-muted-foreground/60"
        } group-hover:bg-primary/20 group-hover:text-primary`}>
          {lesson.id + 1}
        </div>

        {/* Title */}
        <h3
          className={`mb-2 text-lg font-semibold transition-colors ${status === "locked" ? "text-muted-foreground/60" : "text-foreground group-hover:text-primary"}`}
        >
          {lesson.title}
        </h3>

        {/* Description */}
        <p className="mb-4 text-sm leading-relaxed text-muted-foreground/80">{lesson.description}</p>

        {/* Duration with icon */}
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground/60">
          <Clock className="h-3.5 w-3.5" />
          <span>{lesson.duration}</span>
        </div>

        {/* Hover arrow */}
        {isAccessible && (
          <ChevronRight className="absolute bottom-4 right-4 h-5 w-5 text-primary/40 opacity-0 transition-all duration-300 group-hover:translate-x-1 group-hover:text-primary group-hover:opacity-100 group-focus-within:translate-x-1 group-focus-within:text-primary group-focus-within:opacity-100" />
        )}
      </div>
    </motion.div>
  );

  if (isAccessible) {
    return <Link href={`/learn/${lesson.slug}`} className="block h-full">{cardContent}</Link>;
  }

  return cardContent;
}

export default function LearnDashboard() {
  const [completedLessons] = useCompletedLessons();
  const completionPercentage = getCompletionPercentage(completedLessons);
  const nextLesson = getNextUncompletedLesson(completedLessons);
  const router = useRouter();
  const prefersReducedMotion = useReducedMotion();
  const hasTrackedPageView = useRef(false);

  // Track learning hub page view
  useEffect(() => {
    if (hasTrackedPageView.current) return;
    hasTrackedPageView.current = true;

    // Initialize lesson funnel if not already started
    if (!getLessonFunnelData()) {
      initLessonFunnel(TOTAL_LESSONS);
    }

    // Track learning hub visit with context
    sendEvent('learning_hub_visit', {
      completed_lessons: completedLessons.length,
      total_lessons: TOTAL_LESSONS,
      completion_percentage: completionPercentage,
      next_lesson: nextLesson?.slug || 'all_complete',
    });
  }, [completedLessons.length, completionPercentage, nextLesson]);

  // Keyboard navigation state
  const [selectedIndex, setSelectedIndex] = useState(-1);
  const accessibleLessons = LESSONS.filter((_, i) => {
    const status = getLessonStatus(i, completedLessons);
    return status !== "locked";
  });

  // Keyboard navigation handler
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      switch (e.key) {
        case "j":
        case "ArrowDown":
          e.preventDefault();
          setSelectedIndex((prev) =>
            prev < accessibleLessons.length - 1 ? prev + 1 : prev
          );
          break;
        case "k":
        case "ArrowUp":
          e.preventDefault();
          setSelectedIndex((prev) => (prev > 0 ? prev - 1 : 0));
          break;
        case "Enter":
          if (selectedIndex >= 0 && selectedIndex < accessibleLessons.length) {
            const lesson = accessibleLessons[selectedIndex];
            router.push(`/learn/${lesson.slug}`);
          }
          break;
        case "Escape":
          setSelectedIndex(-1);
          break;
      }
    },
    [accessibleLessons, selectedIndex, router]
  );

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  return (
    <div className="relative min-h-screen bg-black">
      {/* Ambient background effects */}
      <div className="pointer-events-none fixed inset-0">
        {/* Primary glow - top left */}
        <div className="absolute -left-32 -top-32 h-[600px] w-[600px] rounded-full bg-primary/8 blur-[150px]" />
        {/* Secondary glow - bottom right */}
        <div className="absolute -bottom-32 -right-32 h-[500px] w-[500px] rounded-full bg-emerald-500/6 blur-[120px]" />
        {/* Accent glow - center */}
        <div className="absolute left-1/2 top-1/3 h-[400px] w-[400px] -translate-x-1/2 rounded-full bg-violet-500/4 blur-[100px]" />
      </div>

      <div className="relative mx-auto max-w-6xl px-4 py-6 sm:px-6 md:px-8 lg:px-12 lg:py-10">
        {/* Header navigation */}
        <motion.header
          className="mb-8 flex items-center justify-between lg:mb-12"
          initial={prefersReducedMotion ? false : { opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={prefersReducedMotion ? { duration: 0 } : springs.smooth}
        >
          <Link
            href="/"
            className="group flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/[0.04] backdrop-blur transition-colors group-hover:bg-white/[0.08]">
              <Home className="h-4 w-4" />
            </div>
            <span className="hidden text-sm sm:block">Home</span>
          </Link>

          <div className="flex items-center gap-3 sm:gap-4">
            <span className="hidden text-xs text-muted-foreground/60 lg:block">
              <kbd className="rounded border border-white/10 bg-white/[0.04] px-1.5 py-0.5 font-mono text-xs">j</kbd>
              /
              <kbd className="rounded border border-white/10 bg-white/[0.04] px-1.5 py-0.5 font-mono text-xs">k</kbd>
              {" "}to navigate
            </span>
            <Link
              href="/wizard/os-selection"
              className="group flex items-center gap-2 rounded-lg bg-white/[0.04] px-3 py-2 text-muted-foreground backdrop-blur transition-all hover:bg-white/[0.08] hover:text-foreground"
            >
              <Terminal className="h-4 w-4" />
              <span className="text-sm">Setup Wizard</span>
            </Link>
          </div>
        </motion.header>

        {/* Hero section */}
        <motion.section
          className="mb-10 text-center lg:mb-14"
          initial={prefersReducedMotion ? false : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.1 }}
        >
          {/* Icon with glow */}
          <motion.div
            className="mb-5 inline-flex"
            initial={prefersReducedMotion ? false : { scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={prefersReducedMotion ? { duration: 0 } : { ...springs.bouncy, delay: 0.2 }}
          >
            <div className="relative">
              <div className="absolute inset-0 rounded-2xl bg-primary/30 blur-xl" />
              <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl border border-primary/20 bg-primary/10 backdrop-blur-xl lg:h-20 lg:w-20">
                <GraduationCap className="h-8 w-8 text-primary lg:h-10 lg:w-10" />
              </div>
              <Sparkles className={`absolute -right-1 -top-1 h-5 w-5 text-primary ${prefersReducedMotion ? "" : "animate-pulse"}`} />
            </div>
          </motion.div>

          <h1 className="mb-4 bg-gradient-to-b from-white via-white to-white/60 bg-clip-text font-mono text-3xl font-bold tracking-tight text-transparent sm:text-4xl lg:text-5xl">
            Learning Hub
          </h1>
          <p className="mx-auto max-w-2xl text-base text-muted-foreground/80 sm:text-lg">
            Master your agentic coding environment with hands-on lessons.
            <span className="hidden sm:inline"> Start from the basics and progress to advanced workflows.</span>
          </p>
        </motion.section>

        {/* Progress card - glassmorphic */}
        <motion.section
          initial={prefersReducedMotion ? false : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.2 }}
        >
          <div className="group relative mb-10 overflow-hidden rounded-2xl border border-primary/20 bg-primary/5 p-5 backdrop-blur-xl transition-all duration-500 hover:border-primary/30 sm:p-6 lg:mb-14 lg:p-8">
            {/* Inner glow */}
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-primary/10 via-transparent to-emerald-500/5" />

            {/* Top shimmer line */}
            <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/50 to-transparent" />

            <div className="relative flex flex-col gap-6 lg:flex-row lg:items-center lg:justify-between">
              <div className="flex-1">
                <div className="mb-2 flex items-center gap-2">
                  <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
                    <BookOpen className="h-4 w-4 text-primary" />
                  </div>
                  <h2 className="text-lg font-semibold">Your Progress</h2>
                </div>
                <p className="text-sm text-muted-foreground/80 sm:text-base">
                  {completedLessons.length === TOTAL_LESSONS
                    ? "🎉 Congratulations! You've mastered all lessons."
                    : nextLesson
                      ? `Up next: ${nextLesson.title}`
                      : "Begin your learning journey"}
                </p>
              </div>

              <div className="flex items-center gap-5 lg:gap-6">
                {/* Circular progress with glow */}
                <motion.div
                  className="relative h-18 w-18 sm:h-20 sm:w-20"
                  initial={prefersReducedMotion ? false : { scale: 0.8, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={prefersReducedMotion ? { duration: 0 } : { ...springs.bouncy, delay: 0.3 }}
                >
                  {/* Glow behind progress ring */}
                  <div className="absolute inset-0 rounded-full bg-primary/20 blur-lg" />
                  <svg className="relative h-full w-full -rotate-90" viewBox="0 0 36 36">
                    <path
                      d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                      fill="none"
                      className="stroke-white/[0.08]"
                      strokeWidth="2.5"
                    />
                    <motion.path
                      d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                      fill="none"
                      className="stroke-primary"
                      strokeWidth="2.5"
                      strokeLinecap="round"
                      initial={prefersReducedMotion ? { strokeDasharray: `${completionPercentage}, 100` } : { strokeDasharray: "0, 100" }}
                      animate={{ strokeDasharray: `${completionPercentage}, 100` }}
                      transition={prefersReducedMotion ? { duration: 0 } : { duration: 1, delay: 0.5, ease: "easeOut" }}
                      style={{ filter: "drop-shadow(0 0 6px oklch(0.7 0.2 280 / 0.5))" }}
                    />
                  </svg>
                  <div className="absolute inset-0 flex items-center justify-center">
                    <span className="font-mono text-base font-bold text-primary sm:text-lg">
                      {completionPercentage}%
                    </span>
                  </div>
                </motion.div>

                {/* Stats */}
                <div>
                  <motion.div
                    className="font-mono text-3xl font-bold text-primary sm:text-4xl"
                    initial={prefersReducedMotion ? false : { opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.4 }}
                    style={{ textShadow: "0 0 30px oklch(0.7 0.2 280 / 0.3)" }}
                  >
                    {completedLessons.length}/{TOTAL_LESSONS}
                  </motion.div>
                  <div className="text-sm text-muted-foreground/60">lessons complete</div>
                </div>
              </div>
            </div>

            {/* Progress bar with shimmer */}
            <div className="relative mt-5 lg:mt-6">
              <div className="h-2 overflow-hidden rounded-full bg-white/[0.06]">
                <motion.div
                  className="relative h-full bg-gradient-to-r from-primary via-primary to-emerald-400"
                  initial={prefersReducedMotion ? { width: `${completionPercentage}%` } : { width: 0 }}
                  animate={{ width: `${completionPercentage}%` }}
                  transition={prefersReducedMotion ? { duration: 0 } : { duration: 0.8, delay: 0.5, ease: "easeOut" }}
                  style={{ boxShadow: "0 0 20px oklch(0.7 0.2 280 / 0.5)" }}
                >
                  {/* Shimmer effect */}
                  <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/25 to-transparent -translate-x-full animate-[shimmer_2s_infinite]" />
                </motion.div>
              </div>
            </div>

            {/* Continue button */}
            {nextLesson && (
              <motion.div
                className="mt-5 lg:mt-6"
                initial={prefersReducedMotion ? false : { opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.6 }}
              >
                <Button asChild size="lg" className="group w-full gap-2 sm:w-auto">
                  <Link href={`/learn/${nextLesson.slug}`}>
                    <Zap className="h-4 w-4" />
                    Continue Learning
                    <ChevronRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
                  </Link>
                </Button>
              </motion.div>
            )}
          </div>
        </motion.section>

        {/* Lessons grid */}
        <motion.section
          className="mb-10 lg:mb-14"
          initial={prefersReducedMotion ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.3 }}
        >
          <h2 className="mb-5 text-xl font-semibold lg:mb-6 lg:text-2xl">All Lessons</h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 lg:gap-5">
            {LESSONS.map((lesson, index) => {
              const status = getLessonStatus(lesson.id, completedLessons);
              const accessibleIndex = accessibleLessons.findIndex(
                (l) => l.id === lesson.id
              );
              return (
                <LessonCard
                  key={lesson.id}
                  lesson={lesson}
                  status={status}
                  index={index}
                  isSelected={accessibleIndex === selectedIndex}
                  prefersReducedMotion={prefersReducedMotion}
                />
              );
            })}
          </div>
        </motion.section>

        {/* Quick reference links - glassmorphic */}
        <motion.section
          initial={prefersReducedMotion ? false : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.5 }}
        >
          <div className="relative overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl sm:p-6 lg:p-8">
            {/* Subtle gradient */}
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-white/[0.03] via-transparent to-transparent" />

            <h2 className="relative mb-5 text-lg font-semibold lg:mb-6 lg:text-xl">Quick Reference</h2>
            <div className="relative grid gap-3 sm:grid-cols-2 sm:gap-4">
              {[
                {
                  href: "/learn/agent-commands",
                  icon: Terminal,
                  title: "Agent Commands",
                  desc: "Claude, Codex, Gemini shortcuts",
                  gradient: "from-violet-500/10 to-violet-500/5",
                },
                {
                  href: "/learn/ntm-palette",
                  icon: BookOpen,
                  title: "NTM Commands",
                  desc: "Session management reference",
                  gradient: "from-blue-500/10 to-blue-500/5",
                },
                {
                  href: "/learn/commands",
                  icon: List,
                  title: "Command Reference",
                  desc: "Searchable list of key commands",
                  gradient: "from-emerald-500/10 to-emerald-500/5",
                },
                {
                  href: "/learn/glossary",
                  icon: Book,
                  title: "Glossary",
                  desc: "Definitions for all jargon terms",
                  gradient: "from-amber-500/10 to-amber-500/5",
                },
              ].map((item, index) => (
                <motion.div
                  key={item.href}
                  initial={prefersReducedMotion ? false : { opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.6 + index * 0.05 }}
                  whileHover={prefersReducedMotion ? undefined : { y: -3, scale: 1.01 }}
                >
                  <Link
                    href={item.href}
                    className={`group flex items-center gap-4 rounded-xl border border-white/[0.06] bg-gradient-to-br ${item.gradient} p-4 backdrop-blur transition-all duration-300 hover:border-white/[0.12] hover:bg-white/[0.04]`}
                  >
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-white/[0.06] transition-colors group-hover:bg-white/[0.1]">
                      <item.icon className="h-5 w-5 text-muted-foreground transition-colors group-hover:text-foreground" />
                    </div>
                    <div className="min-w-0">
                      <div className="font-medium transition-colors group-hover:text-primary">{item.title}</div>
                      <div className="truncate text-sm text-muted-foreground/60">
                        {item.desc}
                      </div>
                    </div>
                    <ChevronRight className="ml-auto h-4 w-4 shrink-0 text-muted-foreground/40 opacity-0 transition-all group-hover:translate-x-0.5 group-hover:opacity-100 group-focus-within:translate-x-0.5 group-focus-within:opacity-100" />
                  </Link>
                </motion.div>
              ))}
            </div>
          </div>
        </motion.section>

        {/* Footer */}
        <motion.footer
          className="mt-10 pb-28 text-center text-sm text-muted-foreground/60 sm:pb-0 lg:mt-14"
          initial={prefersReducedMotion ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.8 }}
        >
          <p>
            Need to set up your VPS first?{" "}
            <Link href="/wizard/os-selection" className="text-primary transition-colors hover:text-primary/80 hover:underline">
              Start the setup wizard →
            </Link>
          </p>
        </motion.footer>
      </div>

      {/* Mobile fixed bottom bar - glassmorphic */}
      {nextLesson && (
        <motion.div
          className="fixed inset-x-0 bottom-0 z-50 border-t border-white/[0.08] bg-black/80 p-4 pb-safe backdrop-blur-xl sm:hidden"
          initial={prefersReducedMotion ? false : { y: 100 }}
          animate={{ y: 0 }}
          transition={prefersReducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.5 }}
        >
          {/* Top glow line */}
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/30 to-transparent" />

          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0 flex-1">
              <p className="truncate text-xs text-muted-foreground/60">Up next</p>
              <p className="truncate text-sm font-medium">{nextLesson.title}</p>
            </div>
            <Button asChild size="lg" className="shrink-0 gap-1.5">
              <Link href={`/learn/${nextLesson.slug}`}>
                Continue
                <ChevronRight className="h-4 w-4" />
              </Link>
            </Button>
          </div>
        </motion.div>
      )}
    </div>
  );
}
