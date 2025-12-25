/**
 * Lesson Progress Configuration
 *
 * Defines the lessons of the ACFS Learning Hub.
 * The actual count is derived from the LESSONS array (see TOTAL_LESSONS).
 * Each lesson teaches a core concept for agentic development.
 * Uses TanStack Query for React state management with localStorage persistence.
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";
import { safeGetJSON, safeSetJSON } from "./utils";

export interface Lesson {
  /** Lesson number (0-indexed) */
  id: number;
  /** URL slug for routing */
  slug: string;
  /** Display title */
  title: string;
  /** Brief description */
  description: string;
  /** Estimated reading time */
  duration: string;
  /** Source markdown file name */
  file: string;
}

export const LESSONS: Lesson[] = [
  {
    id: 0,
    slug: "welcome",
    title: "Welcome & Overview",
    description: "Understand what you have and what you're about to learn",
    duration: "5 min",
    file: "00_welcome.md",
  },
  {
    id: 1,
    slug: "linux-basics",
    title: "Linux Navigation",
    description: "Navigate the filesystem with confidence",
    duration: "8 min",
    file: "01_linux_basics.md",
  },
  {
    id: 2,
    slug: "ssh-basics",
    title: "SSH & Persistence",
    description: "Master secure connections and stay connected",
    duration: "6 min",
    file: "02_ssh_basics.md",
  },
  {
    id: 3,
    slug: "tmux-basics",
    title: "tmux Basics",
    description: "Keep your work running when you disconnect",
    duration: "7 min",
    file: "03_tmux_basics.md",
  },
  {
    id: 4,
    slug: "git-basics",
    title: "Git Essentials",
    description: "Version control and recognizing dangerous operations",
    duration: "10 min",
    file: "04_git_basics.md",
  },
  {
    id: 5,
    slug: "github-cli",
    title: "GitHub CLI",
    description: "Manage issues, PRs, releases, and actions",
    duration: "8 min",
    file: "05_github_cli.md",
  },
  {
    id: 6,
    slug: "agent-commands",
    title: "Agent Commands",
    description: "Talk to Claude, Codex, and Gemini",
    duration: "10 min",
    file: "06_agents_login.md",
  },
  {
    id: 7,
    slug: "ntm-core",
    title: "NTM Command Center",
    description: "Orchestrate your terminal sessions",
    duration: "8 min",
    file: "07_ntm_core.md",
  },
  {
    id: 8,
    slug: "ntm-palette",
    title: "NTM Prompt Palette",
    description: "Quick access to common commands",
    duration: "6 min",
    file: "08_ntm_command_palette.md",
  },
  {
    id: 9,
    slug: "flywheel-loop",
    title: "The Flywheel Loop",
    description: "Put it all together for maximum velocity",
    duration: "10 min",
    file: "09_flywheel_loop.md",
  },
  {
    id: 10,
    slug: "keeping-updated",
    title: "Keeping Updated",
    description: "Maintain and upgrade your environment",
    duration: "4 min",
    file: "10_keeping_updated.md",
  },
  {
    id: 11,
    slug: "ubs",
    title: "UBS: Code Quality Guardrails",
    description: "Catch bugs before they reach production",
    duration: "8 min",
    file: "11_ubs.md",
  },
  {
    id: 12,
    slug: "agent-mail",
    title: "Agent Mail Coordination",
    description: "Multi-agent messaging and file reservations",
    duration: "10 min",
    file: "12_agent_mail.md",
  },
  {
    id: 13,
    slug: "cass",
    title: "CASS: Learning from History",
    description: "Search across all past agent sessions",
    duration: "8 min",
    file: "13_cass.md",
  },
  {
    id: 14,
    slug: "cm",
    title: "The Memory System",
    description: "Build procedural memory for agents",
    duration: "8 min",
    file: "14_cm.md",
  },
  {
    id: 15,
    slug: "beads",
    title: "Beads: Issue Tracking",
    description: "Graph-aware task management with dependencies",
    duration: "8 min",
    file: "15_beads.md",
  },
  {
    id: 16,
    slug: "safety-tools",
    title: "Safety Tools: SLB & CAAM",
    description: "Two-person rule and account management",
    duration: "6 min",
    file: "16_safety_tools.md",
  },
  {
    id: 17,
    slug: "prompt-engineering",
    title: "The Art of Agent Direction",
    description: "Prompting patterns that produce excellent results",
    duration: "12 min",
    file: "17_prompt_engineering.md",
  },
  {
    id: 18,
    slug: "real-world-case-study",
    title: "Case Study: cass-memory",
    description: "Build a complex project in one day with agent swarms",
    duration: "15 min",
    file: "18_real_world_case_study.md",
  },
  {
    id: 19,
    slug: "slb-case-study",
    title: "Case Study: SLB",
    description: "From tweet to working tool in one evening",
    duration: "12 min",
    file: "19_slb_case_study.md",
  },
];

/** Total number of lessons */
export const TOTAL_LESSONS = LESSONS.length;

/** Get a lesson by its ID (0-indexed) */
export function getLessonById(id: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === id);
}

/** Get a lesson by its URL slug */
export function getLessonBySlug(slug: string): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.slug === slug);
}

/** Get the next lesson after the current one */
export function getNextLesson(currentId: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === currentId + 1);
}

/** Get the previous lesson before the current one */
export function getPreviousLesson(currentId: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === currentId - 1);
}

/** localStorage key for storing completed lessons */
export const COMPLETED_LESSONS_KEY = "acfs-learning-hub-completed-lessons";

// Query keys for TanStack Query
export const lessonProgressKeys = {
  completedLessons: ["lessonProgress", "completed"] as const,
};

/** Get completed lesson IDs from localStorage */
export function getCompletedLessons(): number[] {
  const parsed = safeGetJSON<unknown[]>(COMPLETED_LESSONS_KEY);
  if (Array.isArray(parsed)) {
    // Filter to only valid lesson numbers (0..TOTAL_LESSONS-1)
    return parsed.filter(
      (n): n is number =>
        typeof n === "number" && n >= 0 && n < TOTAL_LESSONS
    );
  }
  return [];
}

/** Save completed lessons to localStorage */
export function setCompletedLessons(lessons: number[]): void {
  // Validate lessons before saving
  const validLessons = lessons.filter((n) => n >= 0 && n < TOTAL_LESSONS);
  safeSetJSON(COMPLETED_LESSONS_KEY, validLessons);
}

/** Mark a lesson as completed (pure function, returns new array) */
export function addCompletedLesson(
  currentLessons: number[],
  lessonId: number
): number[] {
  if (currentLessons.includes(lessonId)) {
    return currentLessons;
  }
  const newLessons = [...currentLessons, lessonId];
  newLessons.sort((a, b) => a - b);
  return newLessons;
}

/** Calculate completion percentage */
export function getCompletionPercentage(completedLessons: number[]): number {
  if (TOTAL_LESSONS === 0) return 0;
  return Math.round((completedLessons.length / TOTAL_LESSONS) * 100);
}

/** Get the suggested next lesson to work on */
export function getNextUncompletedLesson(
  completedLessons: number[]
): Lesson | undefined {
  return LESSONS.find((lesson) => !completedLessons.includes(lesson.id));
}

// --- React Hooks using TanStack Query ---

/**
 * Hook to get and manage completed lessons.
 * Uses TanStack Query for state management with localStorage persistence.
 */
export function useCompletedLessons(): [number[], (lessonId: number) => void] {
  const queryClient = useQueryClient();

  const { data: lessons } = useQuery({
    queryKey: lessonProgressKeys.completedLessons,
    queryFn: getCompletedLessons,
    staleTime: Infinity,
    gcTime: Infinity,
  });

  const mutation = useMutation({
    mutationFn: async (lessonId: number) => {
      const currentLessons = getCompletedLessons();
      const newLessons = addCompletedLesson(currentLessons, lessonId);
      setCompletedLessons(newLessons);
      return newLessons;
    },
    onSuccess: (newLessons) => {
      queryClient.setQueryData(lessonProgressKeys.completedLessons, newLessons);
    },
  });

  const markComplete = useCallback(
    (lessonId: number) => {
      mutation.mutate(lessonId);
    },
    [mutation]
  );

  return [lessons ?? [], markComplete];
}

/**
 * Imperatively mark a lesson as complete (for use outside React components).
 * Note: If used, you should invalidate the query in components that depend on it.
 */
export function markLessonComplete(lessonId: number): number[] {
  const completed = getCompletedLessons();
  const newLessons = addCompletedLesson(completed, lessonId);
  if (newLessons !== completed) {
    setCompletedLessons(newLessons);
  }
  return newLessons;
}
