"use client";

import { useCallback } from "react";
import { Check, Circle } from "lucide-react";
import { useDrag } from "@use-gesture/react";
import { cn } from "@/lib/utils";
import {
  WIZARD_STEPS,
  getHighestContiguousCompletedStep,
  useCompletedSteps,
  type WizardStep,
} from "@/lib/wizardSteps";
import { motion } from "@/components/motion";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

export interface StepperProps {
  /** Current active step (1-indexed) */
  currentStep: number;
  /** Callback when a step is clicked */
  onStepClick?: (step: number) => void;
  /** Additional class names for the container */
  className?: string;
}

interface StepItemProps {
  step: WizardStep;
  isActive: boolean;
  isCompleted: boolean;
  isClickable: boolean;
  showConnector: boolean;
  onClick?: () => void;
}

function StepItem({
  step,
  isActive,
  isCompleted,
  isClickable,
  showConnector,
  onClick,
}: StepItemProps) {
  const showCompletedState = isCompleted && !isActive;

  return (
    <button
      type="button"
      onClick={isClickable ? onClick : undefined}
      disabled={!isClickable}
      className={cn(
        "group relative flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition duration-200",
        isActive && "bg-primary/10 shadow-sm",
        isClickable && !isActive && "hover:bg-muted/50",
        !isClickable && "cursor-not-allowed opacity-40"
      )}
      aria-current={isActive ? "step" : undefined}
    >
      {/* Connection line to next step */}
      {showConnector && (
        <div className="absolute left-[22px] top-[42px] h-[calc(100%-16px)] w-px bg-gradient-to-b from-border/50 to-transparent" />
      )}

      {/* Step indicator */}
      <div
        className={cn(
          "relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-medium transition duration-300",
          showCompletedState && "bg-[oklch(0.72_0.19_145)] text-[oklch(0.15_0.02_145)] shadow-sm shadow-[oklch(0.72_0.19_145/0.3)]",
          isActive && "bg-primary text-primary-foreground shadow-sm shadow-primary/30 animate-glow-pulse",
          !isActive && !showCompletedState && "bg-muted text-muted-foreground"
        )}
      >
        {showCompletedState ? (
          <Check className="h-4 w-4" strokeWidth={2.5} />
        ) : isActive ? (
          <Circle className="h-3 w-3 fill-current" />
        ) : (
          <span className="font-mono text-xs">{step.id}</span>
        )}
      </div>

      {/* Step text */}
      <div className="min-w-0 flex-1">
        <div
          className={cn(
            "truncate text-sm font-medium transition-colors",
            isActive && "text-foreground",
            showCompletedState && "text-muted-foreground",
            !isActive && !showCompletedState && "text-muted-foreground"
          )}
        >
          {step.title}
        </div>
        {isActive && (
          <div className="mt-0.5 text-xs text-primary">In progress</div>
        )}
        {showCompletedState && (
          <div className="mt-0.5 text-xs text-[oklch(0.72_0.19_145)]">Complete</div>
        )}
      </div>

      {/* Hover effect */}
      {isClickable && !isActive && (
        <div className="absolute inset-0 rounded-xl border border-transparent transition-colors group-hover:border-border/50" />
      )}
    </button>
  );
}

/**
 * Stepper component for wizard navigation.
 *
 * Shows all wizard steps in a vertical list with:
 * - Current step highlighted with glow
 * - Completed steps with green checkmarks
 * - Connection lines between steps
 * - Click navigation to completed steps only
 */
export function Stepper({ currentStep, onStepClick, className }: StepperProps) {
  const [completedSteps] = useCompletedSteps();
  const highestCompleted = getHighestContiguousCompletedStep(completedSteps);

  const handleStepClick = useCallback(
    (stepId: number) => {
      if (onStepClick) {
        onStepClick(stepId);
      }
    },
    [onStepClick]
  );

  return (
    <nav
      className={cn("flex flex-col", className)}
      aria-label="Wizard steps"
    >
      {WIZARD_STEPS.map((step, index) => {
        const isActive = step.id === currentStep;
        const isCompleted = completedSteps.includes(step.id);
        // Must match canAccessWizardStep (the layout's navigation gate):
        // only steps up to the highest CONTIGUOUS completion point + 1 are
        // reachable. A completed step beyond a gap would render clickable
        // here but be silently rejected by the layout's click handler.
        const isClickable = step.id <= highestCompleted + 1;
        const isLastStep = index === WIZARD_STEPS.length - 1;

        return (
          <div key={step.id} className={cn(!isLastStep && "pb-1")}>
            <StepItem
              step={step}
              isActive={isActive}
              isCompleted={isCompleted}
              isClickable={isClickable}
              showConnector={!isLastStep}
              onClick={() => handleStepClick(step.id)}
            />
          </div>
        );
      })}
    </nav>
  );
}

/**
 * Mobile-friendly bottom navigation version of the stepper.
 * Shows a compact progress bar with touch-friendly dots (44px targets).
 * Supports swipe gestures to navigate between steps.
 */
export function StepperMobile({
  currentStep,
  onStepClick,
  className,
}: StepperProps) {
  const [completedSteps] = useCompletedSteps();
  const prefersReducedMotion = useReducedMotion();

  const currentStepData = WIZARD_STEPS.find((s) => s.id === currentStep);
  const highestCompleted = getHighestContiguousCompletedStep(completedSteps);

  // Swipe gesture handler
  const bind = useDrag(
    ({ direction: [dx], velocity: [vx], active, movement: [mx] }) => {
      // Only trigger on release with sufficient velocity or distance
      if (!active && (Math.abs(vx) > 0.3 || Math.abs(mx) > 50)) {
        if (dx > 0 && currentStep > 1) {
          // Swipe right = go back
          const prevStep = currentStep - 1;
          if (completedSteps.includes(prevStep) || prevStep <= highestCompleted + 1) {
            onStepClick?.(prevStep);
          }
        } else if (dx < 0 && currentStep < WIZARD_STEPS.length) {
          // Swipe left = go forward
          const nextStep = currentStep + 1;
          if (completedSteps.includes(nextStep) || nextStep <= highestCompleted + 1) {
            onStepClick?.(nextStep);
          }
        }
      }
    },
    {
      axis: "x",
      filterTaps: true,
      threshold: 10,
      // Prevent the gesture library from calling preventDefault() on touch
      // events, which breaks native scrolling and tap handling on Mobile Safari
      preventScrollAxis: "y",
      pointer: { touch: true },
    }
  );

  return (
    <div {...bind()} className={cn("select-none", className)} style={{ touchAction: "pan-x pan-y" }}>
      {/* Segmented progress track: one segment per step. Thirteen 44px
          tap targets cannot fit in a phone-width dock (steps 10-13 were
          clipped off-screen), so on mobile the track is purely visual and
          navigation is Back/Next, swipe, or the desktop sidebar. */}
      <div
        className="flex h-1.5 w-full gap-1"
        role="progressbar"
        aria-valuemin={1}
        aria-valuemax={WIZARD_STEPS.length}
        aria-valuenow={currentStep}
        aria-valuetext={`Step ${currentStep} of ${WIZARD_STEPS.length}`}
      >
        {WIZARD_STEPS.map((step) => {
          const isActive = step.id === currentStep;
          const showCompletedState = completedSteps.includes(step.id) && !isActive;
          return (
            <div
              key={step.id}
              className={cn(
                "h-full flex-1 overflow-hidden rounded-full transition-colors duration-300",
                showCompletedState ? "bg-[oklch(0.72_0.19_145)]" : "bg-muted"
              )}
            >
              {isActive && (
                <motion.div
                  className="h-full w-full bg-gradient-to-r from-primary via-[oklch(0.7_0.2_330)] to-primary"
                  initial={prefersReducedMotion ? false : { scaleX: 0, originX: 0 }}
                  animate={{ scaleX: 1 }}
                  transition={{ type: "spring", stiffness: 300, damping: 30 }}
                />
              )}
            </div>
          );
        })}
      </div>

      {/* Current step label, step count, and swipe hint on one line */}
      {currentStepData && (
        <p className="mt-2.5 flex items-baseline justify-between gap-3 text-xs text-muted-foreground">
          <motion.span
            key={currentStepData.id}
            className="truncate text-sm font-medium text-foreground"
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ type: "spring", stiffness: 300, damping: 25 }}
          >
            {currentStepData.title}
          </motion.span>
          <span className="shrink-0 whitespace-nowrap">
            {currentStep}/{WIZARD_STEPS.length}
            <span className="mx-1.5 opacity-50">|</span>
            <span className="opacity-70">Swipe to navigate</span>
          </span>
        </p>
      )}
    </div>
  );
}

export type { WizardStep };
