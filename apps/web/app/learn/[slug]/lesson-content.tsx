"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { renderLessonComponent } from "@/components/lessons";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  GraduationCap,
  Home,
  Lock,
  Sparkles,
  Zap,
  BookOpen,
  Star,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import {
  type Lesson,
  LESSONS,
  getNextLesson,
  getNextUncompletedLesson,
  getPreviousLesson,
  getLessonStatus,
  isLessonAccessible,
  useCompletedLessons,
} from "@/lib/lessonProgress";
import {
  getStepBySlug,
  TOTAL_STEPS as TOTAL_WIZARD_STEPS,
  useCompletedSteps,
} from "@/lib/wizardSteps";
import {
  useConfetti,
  getCompletionMessage,
  CompletionToast,
  FinalCelebrationModal,
} from "@/components/learn/confetti-celebration";
import { useLessonAnalytics } from "@/lib/hooks/useLessonAnalytics";
import { isInteractiveKeyboardTarget } from "@/lib/utils";

interface Props {
  lesson: Lesson;
}

// Sidebar scroll persistence (#356). sessionStorage keeps the lesson list where
// the reader left it for the lifetime of the tab, without leaking into new tabs.
const SIDEBAR_SCROLL_KEY = "acfs-learning-hub-sidebar-scroll-top";

function readSidebarScrollTop(): number | null {
  try {
    const raw = window.sessionStorage.getItem(SIDEBAR_SCROLL_KEY);
    if (raw === null) return null;
    const value = Number(raw);
    return Number.isFinite(value) && value >= 0 ? value : null;
  } catch {
    // Storage can be blocked (private mode, hardened browsers). Persistence is
    // a convenience; never let it break the page.
    return null;
  }
}

function saveSidebarScrollTop(scrollTop: number): void {
  try {
    window.sessionStorage.setItem(
      SIDEBAR_SCROLL_KEY,
      String(Math.max(0, Math.round(scrollTop)))
    );
  } catch {
    // Same rationale as readSidebarScrollTop: storage failures are non-fatal.
  }
}

// Reading progress hook
function useReadingProgress() {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const updateProgress = () => {
      const scrollTop = window.scrollY;
      const docHeight = document.documentElement.scrollHeight - window.innerHeight;
      const scrollPercent = docHeight > 0 ? (scrollTop / docHeight) * 100 : 0;
      setProgress(Math.min(100, Math.max(0, scrollPercent)));
    };

    window.addEventListener("scroll", updateProgress, { passive: true });
    updateProgress();
    return () => window.removeEventListener("scroll", updateProgress);
  }, []);

  return progress;
}

// Animated orb component
function FloatingOrb({
  className,
  delay = 0
}: {
  className: string;
  delay?: number;
}) {
  return (
    <div
      className={`absolute rounded-full pointer-events-none animate-float ${className}`}
      style={{ animationDelay: `${delay}s` }}
    />
  );
}

// Stunning sidebar with depth and premium feel
function LessonSidebar({
  completedLessons,
  currentLessonId,
}: {
  completedLessons: number[];
  currentLessonId: number;
}) {
  const progressPercent = Math.round((completedLessons.length / LESSONS.length) * 100);
  const navRef = useRef<HTMLElement | null>(null);
  const currentLessonRef = useRef<HTMLLIElement | null>(null);

  // Restore the lesson list's scroll position before paint, and persist it as
  // the reader scrolls, so switching lessons never loses their place (#356).
  useLayoutEffect(() => {
    const nav = navRef.current;
    if (!nav) return;

    const savedScrollTop = readSidebarScrollTop();
    if (savedScrollTop !== null) {
      nav.scrollTop = savedScrollTop;
    } else {
      // First visit in this tab: reveal the current lesson instead of showing
      // the top of a 60+ entry list.
      const currentLesson = currentLessonRef.current;
      if (currentLesson) {
        const offsetWithinList =
          currentLesson.getBoundingClientRect().top -
          nav.getBoundingClientRect().top +
          nav.scrollTop;
        nav.scrollTop = Math.max(
          0,
          offsetWithinList - (nav.clientHeight - currentLesson.offsetHeight) / 2
        );
      }
    }

    let pendingFrame: number | null = null;
    const persist = () => saveSidebarScrollTop(nav.scrollTop);
    const schedulePersist = () => {
      if (pendingFrame !== null) return;
      pendingFrame = window.requestAnimationFrame(() => {
        pendingFrame = null;
        persist();
      });
    };

    nav.addEventListener("scroll", schedulePersist, { passive: true });
    window.addEventListener("pagehide", persist);

    return () => {
      nav.removeEventListener("scroll", schedulePersist);
      window.removeEventListener("pagehide", persist);
      if (pendingFrame !== null) {
        window.cancelAnimationFrame(pendingFrame);
      }
      // Client-side lesson navigation does not fire pagehide, so record the
      // position once more when this lesson goes away.
      persist();
    };
  }, [currentLessonId]);

  return (
    <aside
      data-testid="lesson-sidebar"
      className="fixed inset-y-0 left-0 z-30 hidden w-80 xl:block"
    >
      {/* Multi-layer glass effect */}
      <div className="relative h-full">
        {/* Background layer */}
        <div className="absolute inset-0 bg-gradient-to-b from-black via-black/95 to-black" />

        {/* Glass layer */}
        <div className="absolute inset-0 backdrop-blur-3xl" />

        {/* Gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-br from-primary/[0.08] via-transparent to-emerald-500/[0.05]" />

        {/* Border */}
        <div className="absolute inset-y-0 right-0 w-px bg-gradient-to-b from-white/[0.15] via-white/[0.08] to-white/[0.15]" />

        <div className="relative flex h-full flex-col">
          {/* Header with dramatic glow */}
          <div className="relative p-8 pb-6">
            {/* Ambient orbs */}
            <FloatingOrb className="w-32 h-32 bg-primary/30 blur-[60px] -top-10 -left-10" />
            <FloatingOrb className="w-24 h-24 bg-violet-500/20 blur-[50px] top-10 right-0" delay={1} />

            <Link
              href="/learn"
              className="group relative flex items-center gap-4 transition-transform duration-500 hover:translate-x-1"
            >
              {/* Icon with 3D effect */}
              <div className="relative">
                {/* Glow */}
                <div className="absolute inset-0 bg-gradient-to-br from-primary to-violet-500 rounded-2xl blur-xl opacity-50 group-hover:opacity-80 transition-opacity duration-500 scale-110" />
                {/* Shadow */}
                <div className="absolute inset-0 bg-primary/20 rounded-2xl blur-md translate-y-2" />
                {/* Icon container */}
                <div className="relative flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/30 via-primary/20 to-violet-500/20 border border-white/20 shadow-2xl shadow-primary/20 transition duration-500 group-hover:scale-110 group-hover:shadow-primary/40">
                  <GraduationCap className="h-7 w-7 text-white drop-shadow-lg" />
                </div>
              </div>

              <div>
                <span className="block text-lg font-bold tracking-tight bg-gradient-to-r from-white via-white to-white/60 bg-clip-text text-transparent">
                  Learning Hub
                </span>
                <span className="text-xs text-white/60 uppercase tracking-[0.2em] font-medium">
                  ACFS Academy
                </span>
              </div>
            </Link>
          </div>

          {/* Premium progress card */}
          <div className="mx-6 mb-8">
            <div className="relative overflow-hidden rounded-2xl border border-white/10 bg-white/[0.03] p-5 backdrop-blur-xl">
              {/* Inner glow */}
              <div className="absolute inset-0 bg-gradient-to-br from-primary/10 via-transparent to-emerald-500/5" />

              <div className="relative">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Star className="h-4 w-4 text-primary" />
                    <span className="text-sm font-medium text-white/80">Progress</span>
                  </div>
                  <span className="font-mono text-xl font-bold bg-gradient-to-r from-primary to-emerald-400 bg-clip-text text-transparent">
                    {progressPercent}%
                  </span>
                </div>

                {/* Multi-layer progress bar */}
                <div className="relative h-3 rounded-full overflow-hidden">
                  {/* Track */}
                  <div className="absolute inset-0 bg-white/[0.06]" />
                  {/* Glow layer */}
                  <div
                    className="absolute inset-y-0 left-0 bg-gradient-to-r from-primary via-violet-500 to-emerald-400 blur-sm opacity-70 transition-[width] duration-1000"
                    style={{ width: `${progressPercent}%` }}
                  />
                  {/* Fill */}
                  <div
                    className="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-primary via-violet-500 to-emerald-400 transition-[width] duration-1000"
                    style={{ width: `${progressPercent}%` }}
                  />
                  {/* Shimmer */}
                  <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent -translate-x-full animate-[shimmer_2s_infinite]" />
                  {/* Leading glow dot */}
                  {progressPercent > 0 && progressPercent < 100 && (
                    <div
                      className="absolute top-1/2 -translate-y-1/2 w-4 h-4 bg-white rounded-full shadow-[0_0_15px_5px_rgba(255,255,255,0.8)] animate-pulse transition-[left] duration-1000"
                      style={{ left: `calc(${progressPercent}% - 8px)` }}
                    />
                  )}
                </div>

                <div className="flex items-center justify-between mt-4 text-xs">
                  <span className="text-white/60">{completedLessons.length} of {LESSONS.length}</span>
                  <span className="text-emerald-400/80">{LESSONS.length - completedLessons.length} remaining</span>
                </div>
              </div>
            </div>
          </div>

          {/* Lesson list with timeline */}
          <nav
            ref={navRef}
            aria-label="Lessons"
            className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 scrollbar-hide"
          >
            <div className="relative">
              {/* Timeline track. Kept outside the <ul> so the list markup stays valid. */}
              <div
                aria-hidden="true"
                className="pointer-events-none absolute left-[34px] top-6 bottom-6 w-0.5 bg-gradient-to-b from-primary/30 via-white/[0.08] to-emerald-500/30"
              />

              <ul className="relative space-y-1 py-2">
              {LESSONS.map((lesson) => {
                const status = getLessonStatus(lesson.id, completedLessons);
                const isCompleted = status === "completed";
                const isCurrent = lesson.id === currentLessonId;
                const isAccessible = status !== "locked";

                return (
                  <li
                    key={lesson.id}
                    ref={isCurrent ? currentLessonRef : undefined}
                    className="relative"
                  >
                    <Link
                      href={isAccessible ? `/learn/${lesson.slug}` : "#"}
                      aria-disabled={!isAccessible}
                      aria-current={isCurrent ? "page" : undefined}
                      tabIndex={isAccessible ? 0 : -1}
                      className={`group relative flex items-center gap-4 rounded-xl px-4 py-4 transition duration-500 ${
                        isCurrent
                          ? "bg-gradient-to-r from-primary/20 via-primary/10 to-transparent shadow-[inset_0_0_30px_rgba(var(--primary-rgb),0.1)]"
                          : isAccessible
                            ? "hover:bg-white/[0.03]"
                            : "cursor-not-allowed opacity-60"
                      }`}
                      onClick={(event) => {
                        if (!isAccessible) {
                          event.preventDefault();
                        }
                      }}
                    >
                      {/* Timeline node */}
                      <div className="relative z-10">
                        {/* Outer glow ring */}
                        {(isCurrent || isCompleted) && (
                          <div className={`absolute -inset-1 rounded-full ${
                            isCompleted
                              ? "bg-gradient-to-br from-emerald-400 to-emerald-600"
                              : "bg-gradient-to-br from-primary to-violet-500"
                          } opacity-50 blur-md animate-pulse`} />
                        )}

                        <div
                          className={`relative flex h-8 w-8 items-center justify-center rounded-full text-xs font-bold border-2 transition duration-500 ${
                            isCompleted
                              ? "bg-gradient-to-br from-emerald-400 to-emerald-600 border-emerald-400/50 text-white shadow-[0_0_20px_rgba(16,185,129,0.5)]"
                              : isCurrent
                                ? "bg-gradient-to-br from-primary to-violet-500 border-primary/50 text-white shadow-[0_0_20px_rgba(var(--primary-rgb),0.5)]"
                                : "bg-white/[0.05] border-white/10 text-white/60 group-hover:border-white/30 group-hover:bg-white/[0.08] group-hover:text-white/80"
                          }`}
                        >
                          {isCompleted ? (
                            <Check className="h-4 w-4 drop-shadow-lg" strokeWidth={3} />
                          ) : (
                            <span className="tabular-nums">{lesson.id + 1}</span>
                          )}
                        </div>
                      </div>

                      {/* Content */}
                      <div className="flex-1 min-w-0">
                        <span className={`block truncate text-sm font-medium transition duration-300 ${
                          isCurrent
                            ? "text-white"
                            : isCompleted
                              ? "text-white/70"
                              : "text-white/50 group-hover:text-white/80"
                        }`}>
                          {lesson.title}
                        </span>
                        <span className="flex items-center gap-1.5 text-xs text-white/60 mt-1">
                          <Clock className="h-3 w-3" />
                          {lesson.duration}
                        </span>
                      </div>

                      {/* Active indicator */}
                      {isCurrent && (
                        <div className="flex items-center gap-1 text-xs font-medium text-primary">
                          <span className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse" />
                          NOW
                        </div>
                      )}
                    </Link>
                  </li>
                );
              })}
              </ul>
            </div>
          </nav>

          {/* Footer */}
          <div className="p-6 border-t border-white/[0.05]">
            <Link
              href="/"
              className="group flex items-center gap-4 text-sm text-white/60 transition duration-500 hover:text-white/90"
            >
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/[0.03] border border-white/[0.08] transition duration-500 group-hover:scale-110 group-hover:bg-white/[0.08] group-hover:border-white/20">
                <Home className="h-5 w-5 transition-transform duration-500 group-hover:-translate-y-0.5" />
              </div>
              <span className="font-medium">Back to Home</span>
            </Link>
          </div>
        </div>
      </div>
    </aside>
  );
}

export function LessonContent({ lesson }: Props) {
  const router = useRouter();
  const { completedLessons, hasLoaded, markComplete } = useCompletedLessons();
  const [completedSteps] = useCompletedSteps();
  const readingProgress = useReadingProgress();
  const lessonStatus = hasLoaded
    ? getLessonStatus(lesson.id, completedLessons)
    : "current";
  const isLocked = hasLoaded && lessonStatus === "locked";
  const isCompleted = hasLoaded && completedLessons.includes(lesson.id);
  const prevLesson = getPreviousLesson(lesson.id);
  const nextLesson = getNextLesson(lesson.id);
  const accessiblePrevLesson =
    hasLoaded && prevLesson && isLessonAccessible(prevLesson.id, completedLessons)
      ? prevLesson
      : undefined;
  const accessibleNextLesson =
    hasLoaded && nextLesson && isLessonAccessible(nextLesson.id, completedLessons)
      ? nextLesson
      : undefined;
  const nextAvailableLesson =
    hasLoaded
      ? getNextUncompletedLesson(completedLessons) ?? LESSONS[LESSONS.length - 1]
      : undefined;
  const isWizardComplete = completedSteps.length === TOTAL_WIZARD_STEPS;
  const [showToast, setShowToast] = useState(false);
  const [toastMessage, setToastMessage] = useState("");
  const [showFinalCelebration, setShowFinalCelebration] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isMarkingComplete, setIsMarkingComplete] = useState(false);
  const { celebrate } = useConfetti();

  // Analytics tracking for lesson funnel
  const { markComplete: markAnalyticsComplete } = useLessonAnalytics({ lesson });

  const timeoutsRef = useRef<NodeJS.Timeout[]>([]);

  useEffect(() => {
    const timeouts = timeoutsRef.current;
    return () => {
      timeouts.forEach(clearTimeout);
    };
  }, []);

  const lessonContent = renderLessonComponent(lesson.slug);

  const wizardStepSlugByLesson: Record<string, string> = {
    welcome: "launch-onboarding",
    "ssh-basics": "ssh-connect",
    "agent-commands": "accounts",
  };
  const wizardStepSlug = wizardStepSlugByLesson[lesson.slug] ?? "os-selection";
  const wizardStep = getStepBySlug(wizardStepSlug);
  const wizardStepTitle = wizardStep?.title ?? "Setup Wizard";

  const handleMarkComplete = useCallback(async () => {
    if (!hasLoaded || isLocked || isMarkingComplete) {
      return;
    }

    if (isCompleted) {
      if (accessibleNextLesson) {
        router.push(`/learn/${accessibleNextLesson.slug}`);
      }
      return;
    }

    setSaveError(null);
    setIsMarkingComplete(true);

    try {
      await markComplete(lesson.id);

      // Track in GA4 analytics only after persistence succeeds.
      markAnalyticsComplete({ is_final_lesson: !nextLesson });

      const isFinalLesson = !nextLesson;

      celebrate(isFinalLesson);
      setToastMessage(getCompletionMessage(isFinalLesson));
      setShowToast(true);

      timeoutsRef.current.push(setTimeout(() => setShowToast(false), 2500));

      if (isFinalLesson) {
        timeoutsRef.current.push(setTimeout(() => setShowFinalCelebration(true), 500));
      } else {
        timeoutsRef.current.push(setTimeout(() => {
          router.push(`/learn/${nextLesson.slug}`);
        }, 1500));
      }
    } catch (error) {
      console.error("Failed to save lesson progress", error);
      setSaveError(
        "Unable to save lesson progress. Check your browser storage settings and try again."
      );
    } finally {
      setIsMarkingComplete(false);
    }
  }, [
    accessibleNextLesson,
    hasLoaded,
    isLocked,
    isMarkingComplete,
    lesson.id,
    markComplete,
    markAnalyticsComplete,
    nextLesson,
    router,
    celebrate,
    isCompleted,
  ]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!hasLoaded) {
        return;
      }
      if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.altKey) {
        return;
      }
      if (isInteractiveKeyboardTarget(e.target)) {
        return;
      }

      switch (e.key) {
        case "ArrowLeft":
        case "h":
          if (accessiblePrevLesson) router.push(`/learn/${accessiblePrevLesson.slug}`);
          break;
        case "ArrowRight":
        case "l":
          if (accessibleNextLesson) router.push(`/learn/${accessibleNextLesson.slug}`);
          break;
        case "c":
          if (!isLocked && !isCompleted) {
            void handleMarkComplete();
          }
          break;
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [accessiblePrevLesson, accessibleNextLesson, hasLoaded, isCompleted, isLocked, handleMarkComplete, router]);

  if (isLocked) {
    return (
      <div className="min-h-screen bg-black relative overflow-x-hidden">
        <div className="fixed inset-0 pointer-events-none">
          <FloatingOrb className="w-[700px] h-[700px] bg-primary/10 blur-[180px] -top-48 left-1/4" />
          <FloatingOrb className="w-[420px] h-[420px] bg-violet-500/10 blur-[120px] bottom-0 right-0" delay={2} />
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,_rgba(var(--primary-rgb),0.15),_transparent)]" />
        </div>

        <div className="relative mx-auto flex min-h-screen max-w-3xl items-center justify-center px-6 py-16">
          <div className="w-full rounded-3xl border border-amber-500/20 bg-gradient-to-br from-white/[0.08] via-white/[0.03] to-white/[0.05] p-10 backdrop-blur-2xl">
            <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl border border-amber-500/30 bg-amber-500/10 text-amber-300 shadow-[0_0_40px_rgba(245,158,11,0.2)]">
              <Lock className="h-7 w-7" />
            </div>
            <p className="mb-3 text-sm font-semibold uppercase tracking-[0.25em] text-amber-300/80">
              Lesson Locked
            </p>
            <h1 className="mb-4 text-4xl font-bold tracking-tight text-white">
              {lesson.title}
            </h1>
            <p className="mb-8 text-lg leading-relaxed text-white/65">
              Finish <span className="font-semibold text-white">{nextAvailableLesson?.title ?? "the current lesson"}</span> first
              to keep the curriculum in sequence. The learning hub only unlocks one new lesson at a time.
            </p>
            <div className="flex flex-col gap-3 sm:flex-row">
              <Link
                href={`/learn/${nextAvailableLesson?.slug ?? lesson.slug}`}
                className="inline-flex items-center justify-center gap-2 rounded-xl border border-primary/40 bg-primary/15 px-5 py-3 font-semibold text-white transition duration-300 hover:bg-primary/25"
              >
                Go to Current Lesson
                <ArrowRight className="h-4 w-4" />
              </Link>
              <Link
                href="/learn"
                className="inline-flex items-center justify-center gap-2 rounded-xl border border-white/10 bg-white/[0.04] px-5 py-3 font-semibold text-white/80 transition duration-300 hover:bg-white/[0.08] hover:text-white"
              >
                <ArrowLeft className="h-4 w-4" />
                Back to Learning Hub
              </Link>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-black relative overflow-x-hidden">
      {/* Dramatic ambient background */}
      <div className="fixed inset-0 pointer-events-none">
        {/* Large primary orb */}
        <FloatingOrb className="w-[800px] h-[800px] bg-primary/10 blur-[200px] -top-64 left-1/4" />
        {/* Secondary orb */}
        <FloatingOrb className="w-[600px] h-[600px] bg-violet-500/10 blur-[150px] top-1/3 -right-32" delay={2} />
        {/* Emerald accent */}
        <FloatingOrb className="w-[400px] h-[400px] bg-emerald-500/8 blur-[100px] bottom-0 left-0" delay={4} />
        {/* Center gradient */}
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,_rgba(var(--primary-rgb),0.15),_transparent)]" />
        {/* Grid pattern */}
        <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:100px_100px]" />
      </div>

      {/* Premium reading progress bar */}
      <div className="fixed left-0 right-0 top-0 z-50 h-1.5">
        <div className="h-full bg-black/80 backdrop-blur-sm" />
        {/* Glow track */}
        <div
          className="absolute inset-y-0 left-0 bg-gradient-to-r from-primary via-violet-500 to-emerald-400 blur-sm opacity-80 transition-[width] duration-200"
          style={{ width: `${readingProgress}%` }}
        />
        {/* Main bar */}
        <div
          className="absolute inset-y-0 left-0 bg-gradient-to-r from-primary via-violet-500 to-emerald-400 transition-[width] duration-200"
          style={{ width: `${readingProgress}%` }}
        />
        {/* Leading glow */}
        {readingProgress > 0 && readingProgress < 100 && (
          <div
            className="absolute top-1/2 -translate-y-1/2 w-5 h-5 bg-white rounded-full shadow-[0_0_20px_10px_rgba(255,255,255,0.9)] transition-[left] duration-200"
            style={{ left: `calc(${readingProgress}% - 10px)` }}
          />
        )}
      </div>

      <CompletionToast message={toastMessage} isVisible={showToast} />
      <FinalCelebrationModal
        isOpen={showFinalCelebration}
        onClose={() => setShowFinalCelebration(false)}
        onGoToDashboard={() => {
          setShowFinalCelebration(false);
          router.push("/learn");
        }}
      />

      {/* The sidebar is position: fixed on xl screens (the page root's
          overflow-x-hidden broke position: sticky by making it a clipping
          ancestor), so reserve its width here to keep the article clear. */}
      <div className="relative flex xl:pl-80">
        <LessonSidebar
          completedLessons={completedLessons}
          currentLessonId={lesson.id}
        />

        <main className="flex-1 min-w-0">
          {/* Mobile header - ultra premium */}
          <div className="sticky top-0 z-20 xl:hidden">
            <div className="relative border-b border-white/[0.08]">
              <div className="absolute inset-0 bg-black/80 backdrop-blur-2xl" />
              <div className="relative flex items-center justify-between px-5 py-4">
                <Link
                  href="/learn"
                  className="group flex items-center gap-3 text-white/60 transition duration-300 hover:text-white"
                >
                  <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition duration-300 group-hover:scale-110 group-hover:bg-white/[0.1]">
                    <ArrowLeft className="h-4 w-4" />
                  </div>
                  <span className="text-sm font-medium">Back</span>
                </Link>
                <div className="flex items-center gap-3">
                  <div className="flex items-center gap-2 px-3 py-2 rounded-full bg-white/[0.05] border border-white/[0.08]">
                    <span className="text-sm font-bold text-primary tabular-nums">{lesson.id + 1}</span>
                    <span className="text-white/50">/</span>
                    <span className="text-sm text-white/60 tabular-nums">{LESSONS.length}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Main content area */}
          <div className="px-6 py-12 md:px-12 md:py-20 lg:px-24 lg:py-28">
            <div className="mx-auto max-w-[760px]">
              {/* Stunning lesson hero */}
              <header className="relative mb-20">
                {/* Decorative elements */}
                <div className="absolute -top-32 -right-32 w-64 h-64 bg-gradient-to-br from-primary/20 to-transparent rounded-full blur-3xl pointer-events-none" />

                {/* Meta badges */}
                <div className="flex flex-wrap items-center gap-3 mb-8">
                  <div className="group flex items-center gap-2.5 px-4 py-2 rounded-full bg-gradient-to-r from-primary/20 to-violet-500/20 border border-primary/30 shadow-[0_0_30px_-5px_rgba(var(--primary-rgb),0.3)] transition duration-500 hover:scale-105 hover:shadow-[0_0_40px_-5px_rgba(var(--primary-rgb),0.5)]">
                    <BookOpen className="h-4 w-4 text-primary" />
                    <span className="text-sm font-semibold text-white">Lesson {lesson.id + 1}</span>
                  </div>
                  <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-white/[0.03] border border-white/[0.08] text-white/50">
                    <Clock className="h-4 w-4" />
                    <span className="text-sm">{lesson.duration}</span>
                  </div>
                  {isCompleted && (
                    <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-gradient-to-r from-emerald-500/20 to-emerald-600/20 border border-emerald-500/30 shadow-[0_0_20px_-5px_rgba(16,185,129,0.5)]">
                      <Check className="h-4 w-4 text-emerald-400" />
                      <span className="text-sm font-semibold text-emerald-400">Completed</span>
                    </div>
                  )}
                </div>

                {/* Title with dramatic gradient */}
                <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight mb-8 leading-[1.1]">
                  <span className="bg-gradient-to-br from-white via-white to-white/50 bg-clip-text text-transparent">
                    {lesson.title}
                  </span>
                </h1>

                {/* Description with premium typography */}
                <p className="text-xl lg:text-2xl text-white/50 leading-relaxed font-light">
                  {lesson.description}
                </p>

                {/* Decorative line */}
                <div className="mt-12 h-px bg-gradient-to-r from-primary/50 via-white/10 to-transparent" />
              </header>

              {/* Setup prompt - stunning glassmorphic card */}
              {!isWizardComplete && (
                <div className="group relative mb-16">
                  {/* Outer glow */}
                  <div className="absolute -inset-1 rounded-3xl bg-gradient-to-r from-amber-500/30 via-orange-500/20 to-amber-500/30 blur-xl opacity-50 group-hover:opacity-80 transition-opacity duration-500" />

                  <div className="relative overflow-hidden rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 via-black/40 to-orange-500/5 backdrop-blur-2xl p-8">
                    {/* Animated accent */}
                    <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-amber-400/70 to-transparent" />
                    <div className="absolute inset-0 bg-gradient-to-r from-amber-500/5 via-transparent to-orange-500/5 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity duration-500" />

                    <div className="relative flex gap-6">
                      <div className="relative shrink-0">
                        {/* Glow */}
                        <div className="absolute inset-0 bg-gradient-to-br from-amber-400 to-orange-500 rounded-2xl blur-xl opacity-40 group-hover:opacity-70 transition-opacity duration-500 scale-110" />
                        <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-amber-400/30 to-orange-500/30 border border-amber-400/40 shadow-2xl shadow-amber-500/20 transition-transform duration-500 group-hover:scale-110">
                          <Sparkles className="h-7 w-7 text-amber-300 drop-shadow-lg" />
                        </div>
                      </div>
                      <div className="flex-1">
                        <h2 className="text-xl font-bold text-white mb-2">
                          New to ACFS?
                        </h2>
                        <p className="text-white/50 mb-6 leading-relaxed">
                          Complete the setup wizard first to get the most from these lessons.
                        </p>
                        <Link
                          href={`/wizard/${wizardStepSlug}`}
                          className="inline-flex items-center gap-3 px-5 py-3 rounded-xl bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-400/30 text-amber-300 font-semibold transition duration-300 hover:from-amber-500/30 hover:to-orange-500/30 hover:scale-105 hover:shadow-[0_0_30px_rgba(245,158,11,0.3)]"
                        >
                          <span>Go to {wizardStepTitle}</span>
                          <ArrowRight className="h-5 w-5" />
                        </Link>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Custom lesson content with error boundary */}
              <article>
                <ErrorBoundary
                  backLink="/learn"
                  backLinkLabel="Learning Hub"
                >
                  {lessonContent ? (
                    lessonContent
                  ) : (
                    <div className="rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-8 text-center">
                      <p className="text-white/70">Lesson content not found for: {lesson.slug}</p>
                    </div>
                  )}
                </ErrorBoundary>
              </article>

              {/* Jaw-dropping completion card */}
              <div className="mt-28 relative group">
                {/* Multi-layer glow */}
                <div className={`absolute -inset-2 rounded-[28px] transition duration-700 ${
                  isCompleted
                    ? "bg-gradient-to-r from-emerald-500/40 via-emerald-400/30 to-emerald-500/40 blur-2xl opacity-100"
                    : "bg-gradient-to-r from-primary/40 via-violet-500/30 to-primary/40 blur-2xl opacity-0 group-hover:opacity-100 group-focus-within:opacity-100"
                }`} />

                <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-br from-white/[0.08] via-white/[0.03] to-white/[0.05] backdrop-blur-2xl p-10">
                  {/* Animated gradient border */}
                  <div className="absolute inset-0 rounded-3xl bg-gradient-to-r from-primary via-violet-500 to-emerald-400 opacity-20 blur-3xl animate-[spin_10s_linear_infinite]" />

                  {/* Top accent line */}
                  <div className={`absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent ${
                    isCompleted ? "via-emerald-400/80" : "via-primary/80"
                  } to-transparent`} />

                  <div className="relative flex flex-col sm:flex-row sm:items-center sm:justify-between gap-8">
                    <div className="flex items-start gap-6">
                      {/* Stunning icon */}
                      <div className="relative shrink-0">
                        <div className={`absolute inset-0 rounded-2xl blur-xl transition-opacity duration-500 ${
                          isCompleted
                            ? "bg-gradient-to-br from-emerald-400 to-emerald-600 opacity-60"
                            : "bg-gradient-to-br from-primary to-violet-500 opacity-50 group-hover:opacity-80"
                        }`} />
                        <div className={`relative flex h-16 w-16 items-center justify-center rounded-2xl border-2 transition duration-500 ${
                          isCompleted
                            ? "bg-gradient-to-br from-emerald-400/20 to-emerald-600/20 border-emerald-400/50 shadow-[0_0_40px_rgba(16,185,129,0.5)]"
                            : "bg-gradient-to-br from-primary/20 to-violet-500/20 border-primary/50 shadow-[0_0_40px_rgba(var(--primary-rgb),0.3)] group-hover:shadow-[0_0_50px_rgba(var(--primary-rgb),0.5)]"
                        }`}>
                          {isCompleted ? (
                            <Check className="h-7 w-7 text-emerald-400 drop-shadow-[0_0_10px_rgba(16,185,129,0.8)]" strokeWidth={3} />
                          ) : (
                            <Zap className="h-7 w-7 text-primary drop-shadow-[0_0_10px_rgba(var(--primary-rgb),0.8)]" />
                          )}
                        </div>
                      </div>

                      <div>
                        <h3 className="text-2xl font-bold text-white mb-2">
                          {isCompleted ? "Lesson mastered!" : "Ready to level up?"}
                        </h3>
                        <p className="text-white/50 text-lg">
                          {isCompleted
                            ? accessibleNextLesson
                              ? "Outstanding work! Continue to the next lesson."
                              : "You've completed the entire curriculum!"
                            : "Mark complete to track your learning progress."}
                        </p>
                        {saveError && (
                          <div className="mt-4 rounded-2xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
                            {saveError}
                          </div>
                        )}
                      </div>
                    </div>

                    <Button
                      onClick={() => {
                        void handleMarkComplete();
                      }}
                      disabled={isMarkingComplete || (isCompleted && !accessibleNextLesson)}
                      size="lg"
                      className={`shrink-0 h-14 px-8 text-lg font-semibold rounded-xl transition duration-500 ${
                        isCompleted
                          ? "bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-400 hover:to-emerald-500 shadow-[0_0_40px_rgba(16,185,129,0.5)] hover:shadow-[0_0_50px_rgba(16,185,129,0.7)] hover:scale-105"
                          : "bg-gradient-to-r from-primary to-violet-500 hover:from-primary/90 hover:to-violet-400 shadow-[0_0_40px_rgba(var(--primary-rgb),0.4)] hover:shadow-[0_0_50px_rgba(var(--primary-rgb),0.6)] hover:scale-105"
                      }`}
                    >
                      {isCompleted ? (
                        accessibleNextLesson ? (
                          <span className="flex items-center gap-3">
                            Next Lesson
                            <ArrowRight className="h-5 w-5" />
                          </span>
                        ) : (
                          <span className="flex items-center gap-3">
                            All Complete
                            <Star className="h-5 w-5" />
                          </span>
                        )
                        ) : (
                          <span className="flex items-center gap-3">
                            {isMarkingComplete ? "Saving..." : "Mark Complete"}
                            <Check className="h-5 w-5" />
                          </span>
                        )}
                    </Button>
                  </div>
                </div>
              </div>

              {/* Beautiful navigation cards */}
              <nav className="hidden lg:grid grid-cols-2 gap-6 mt-16">
                {accessiblePrevLesson ? (
                  <Link
                    href={`/learn/${accessiblePrevLesson.slug}`}
                    className="group relative overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 transition duration-500 hover:bg-white/[0.05] hover:border-white/20 hover:shadow-[0_0_40px_rgba(255,255,255,0.05)] hover:-translate-y-1 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background outline-none"
                  >
                    <div className="absolute inset-0 bg-gradient-to-r from-white/[0.05] to-transparent opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 transition-opacity duration-500" />
                    <div className="relative flex items-center gap-5">
                      <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition duration-500 group-hover:scale-110 group-hover:bg-white/[0.1] group-hover:border-white/20">
                        <ChevronLeft className="h-6 w-6 text-white/60 transition duration-500 group-hover:text-white group-hover:-translate-x-1" />
                      </div>
                      <div>
                        <div className="text-xs text-white/50 mb-1 uppercase tracking-wider font-medium">Previous</div>
                        <div className="text-lg font-semibold text-white/80 transition-colors group-hover:text-white">{accessiblePrevLesson.title}</div>
                      </div>
                    </div>
                  </Link>
                ) : (
                  <div />
                )}
                {accessibleNextLesson ? (
                  <Link
                    href={`/learn/${accessibleNextLesson.slug}`}
                    className="group relative overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 transition duration-500 hover:bg-white/[0.05] hover:border-white/20 hover:shadow-[0_0_40px_rgba(255,255,255,0.05)] hover:-translate-y-1 text-right focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background outline-none"
                  >
                    <div className="absolute inset-0 bg-gradient-to-l from-white/[0.05] to-transparent opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 transition-opacity duration-500" />
                    <div className="relative flex items-center justify-end gap-5">
                      <div>
                        <div className="text-xs text-white/50 mb-1 uppercase tracking-wider font-medium">Next</div>
                        <div className="text-lg font-semibold text-white/80 transition-colors group-hover:text-white">{accessibleNextLesson.title}</div>
                      </div>
                      <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition duration-500 group-hover:scale-110 group-hover:bg-white/[0.1] group-hover:border-white/20">
                        <ChevronRight className="h-6 w-6 text-white/60 transition duration-500 group-hover:text-white group-hover:translate-x-1" />
                      </div>
                    </div>
                  </Link>
                ) : (
                  <div />
                )}
              </nav>
            </div>
          </div>

          <div className="h-32 xl:hidden" />
        </main>
      </div>

      {/* Premium mobile navigation */}
      <div className="fixed inset-x-0 bottom-0 z-30 xl:hidden pb-safe">
        <div className="relative">
          {/* Glow backdrop */}
          <div className="absolute inset-0 bg-gradient-to-t from-black via-black/95 to-transparent backdrop-blur-2xl" />
          {/* Top accent */}
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-white/20 to-transparent" />

          <div className="relative flex items-center gap-4 p-5">
            <Button
              variant="ghost"
              size="icon"
              className="h-14 w-14 shrink-0 rounded-2xl border border-white/[0.08] bg-white/[0.03] hover:bg-white/[0.08] hover:border-white/20 transition duration-300 hover:scale-105"
              disabled={!accessiblePrevLesson}
              asChild={!!accessiblePrevLesson}
              aria-label="Previous lesson"
            >
              {accessiblePrevLesson ? (
                <Link href={`/learn/${accessiblePrevLesson.slug}`} aria-label="Previous lesson">
                  <ChevronLeft className="h-6 w-6" />
                </Link>
              ) : (
                <ChevronLeft className="h-6 w-6" />
              )}
            </Button>

            <Button
              className={`h-14 flex-1 rounded-2xl text-lg font-semibold transition duration-500 ${
                isCompleted
                  ? "bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-400 hover:to-emerald-500 shadow-[0_0_30px_rgba(16,185,129,0.5)]"
                  : "bg-gradient-to-r from-primary to-violet-500 hover:from-primary/90 hover:to-violet-400 shadow-[0_0_30px_rgba(var(--primary-rgb),0.5)]"
              }`}
              onClick={() => {
                void handleMarkComplete();
              }}
              disabled={isMarkingComplete || (isCompleted && !accessibleNextLesson)}
            >
              {isCompleted ? (
                accessibleNextLesson ? (
                  <span className="flex items-center gap-2">Next<ArrowRight className="h-5 w-5" /></span>
                ) : (
                  <span className="flex items-center gap-2">Done<Star className="h-5 w-5" /></span>
                )
              ) : (
                <span className="flex items-center gap-2">
                  {isMarkingComplete ? "Saving..." : "Complete"}
                  <Check className="h-5 w-5" />
                </span>
              )}
            </Button>

            <Button
              variant="ghost"
              size="icon"
              className="h-14 w-14 shrink-0 rounded-2xl border border-white/[0.08] bg-white/[0.03] hover:bg-white/[0.08] hover:border-white/20 transition duration-300 hover:scale-105"
              disabled={!accessibleNextLesson}
              asChild={!!accessibleNextLesson}
              aria-label="Next lesson"
            >
              {accessibleNextLesson ? (
                <Link href={`/learn/${accessibleNextLesson.slug}`} aria-label="Next lesson">
                  <ChevronRight className="h-6 w-6" />
                </Link>
              ) : (
                <ChevronRight className="h-6 w-6" />
              )}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
