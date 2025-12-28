'use client';

import { useEffect, useRef, useCallback } from 'react';
import {
  trackLessonEnter,
  trackLessonComplete,
  trackLessonDropoff,
} from '@/lib/analytics';
import { TOTAL_LESSONS, type Lesson } from '@/lib/lessons';

interface UseLessonAnalyticsOptions {
  lesson: Lesson;
  totalLessons?: number;
}

/**
 * Hook for tracking lesson analytics with full funnel instrumentation
 * Automatically tracks lesson views, time spent, and provides helpers for completion tracking
 */
export function useLessonAnalytics({
  lesson,
  totalLessons = TOTAL_LESSONS,
}: UseLessonAnalyticsOptions) {
  const startTime = useRef<number>(0);
  const trackedLessonId = useRef<number | null>(null);
  const isCompleted = useRef<boolean>(false);

  // Track lesson view on mount AND when lesson changes (client-side navigation)
  useEffect(() => {
    // Only track if this is a new lesson (prevents double-tracking on re-renders)
    if (trackedLessonId.current === lesson.id) return;

    // Reset state for new lesson
    trackedLessonId.current = lesson.id;
    isCompleted.current = false;
    startTime.current = Date.now();

    // Track lesson entry with full funnel tracking
    trackLessonEnter(lesson.id, lesson.slug, lesson.title, totalLessons);
  }, [lesson.id, lesson.slug, lesson.title, totalLessons]);

  // Calculate time spent
  const getTimeSpent = useCallback((): number => {
    return Math.floor((Date.now() - startTime.current) / 1000);
  }, []);

  // Track lesson completion
  const markComplete = useCallback((additionalData?: Record<string, unknown>) => {
    // Ensure we're marking complete for the currently tracked lesson
    if (isCompleted.current || trackedLessonId.current !== lesson.id) return;
    isCompleted.current = true;

    trackLessonComplete(
      lesson.id,
      lesson.slug,
      lesson.title,
      totalLessons,
      {
        time_spent_seconds: getTimeSpent(),
        ...additionalData,
      }
    );
  }, [lesson.id, lesson.slug, lesson.title, totalLessons, getTimeSpent]);

  // Track potential abandonment on unmount
  useEffect(() => {
    const handleBeforeUnload = () => {
      if (!isCompleted.current) {
        trackLessonDropoff('page_exit');
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);

    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  }, []);

  return {
    getTimeSpent,
    markComplete,
  };
}

export default useLessonAnalytics;
