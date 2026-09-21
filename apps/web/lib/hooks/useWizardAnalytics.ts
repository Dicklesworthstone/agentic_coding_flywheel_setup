"use client";

import { useCallback, useEffect, useRef } from "react";
import {
  trackConversion,
  trackFunnelDropoff,
  trackFunnelStepComplete,
  trackFunnelStepEnter,
  trackWizardAbandonment,
  trackWizardStep,
  trackWizardStepComplete,
  type WizardStep,
} from "@/lib/analytics";
import { TOTAL_STEPS } from "@/lib/wizardSteps";

interface UseWizardAnalyticsOptions {
  step: WizardStep;
  stepNumber: number;
  stepTitle: string;
  totalSteps?: number;
}

/**
 * Hook for tracking wizard step analytics with full funnel instrumentation
 * Automatically tracks step views, time spent, funnel progression, and provides helpers
 */
export function useWizardAnalytics({
  step,
  stepNumber,
  stepTitle,
  totalSteps = TOTAL_STEPS,
}: UseWizardAnalyticsOptions) {
  const startTime = useRef<number>(0);
  const trackedStepNumber = useRef<number | null>(null);
  const isCompleted = useRef<boolean>(false);

  // Track step view on mount AND when step changes (client-side navigation)
  useEffect(() => {
    // Only track if this is a new step (prevents double-tracking on re-renders)
    if (trackedStepNumber.current === stepNumber) return;

    // Reset state for new step
    trackedStepNumber.current = stepNumber;
    isCompleted.current = false;
    startTime.current = Date.now();

    // Track legacy wizard step event
    trackWizardStep(step, stepNumber, {
      total_steps: totalSteps,
      progress_percentage: Math.round((stepNumber / totalSteps) * 100),
    });

    // Track funnel step entry (comprehensive funnel tracking)
    // Only track steps that are part of the core wizard funnel (1..TOTAL_STEPS).
    // Optional/bonus pages (e.g. Windows Terminal setup) should not mutate funnel state.
    if (stepNumber >= 1 && stepNumber <= totalSteps) {
      trackFunnelStepEnter(stepNumber, step, stepTitle);
    }

    // Track wizard start conversion on first step
    if (stepNumber === 1) {
      trackConversion("wizard_start");
    }
  }, [step, stepNumber, stepTitle, totalSteps]);

  // Calculate time spent
  const getTimeSpent = useCallback((): number => {
    return Math.floor((Date.now() - startTime.current) / 1000);
  }, []);

  // Track step completion
  const markComplete = useCallback(
    (additionalData?: Record<string, unknown>) => {
      // Ensure we're marking complete for the currently tracked step
      if (isCompleted.current || trackedStepNumber.current !== stepNumber) return;
      isCompleted.current = true;

      const timeSpent = getTimeSpent();

      // Track legacy event
      trackWizardStepComplete(step, stepNumber, timeSpent);

      // Track funnel step completion
      if (stepNumber >= 1 && stepNumber <= totalSteps) {
        trackFunnelStepComplete(stepNumber, step, {
          step_title: stepTitle,
          ...additionalData,
        });
      }
    },
    [step, stepNumber, stepTitle, totalSteps, getTimeSpent],
  );

  // Track abandonment
  const markAbandoned = useCallback(
    (reason?: string) => {
      trackWizardAbandonment(step, stepNumber, reason);
      if (stepNumber >= 1 && stepNumber <= totalSteps) {
        trackFunnelDropoff(reason);
      }
    },
    [step, stepNumber, totalSteps],
  );

  // Track potential abandonment on unmount
  useEffect(() => {
    const handleBeforeUnload = () => {
      if (!isCompleted.current) {
        if (stepNumber >= 1 && stepNumber <= totalSteps) {
          trackFunnelDropoff("page_exit");
        }
      }
    };

    window.addEventListener("beforeunload", handleBeforeUnload);

    return () => {
      window.removeEventListener("beforeunload", handleBeforeUnload);
    };
  }, [stepNumber, totalSteps]);

  return {
    getTimeSpent,
    markComplete,
    markAbandoned,
  };
}

export default useWizardAnalytics;
