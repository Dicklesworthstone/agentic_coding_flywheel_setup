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
        "group relative flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-all duration-200",
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
          "relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-medium transition-all duration-300",
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
        // Can click if step is completed or if it's the next step after the
        // highest contiguous completion point.
        const isClickable = isCompleted || step.id <= highestCompleted + 1;
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
  const progress = (currentStep / WIZARD_STEPS.length) * 100;
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
      {/* Progress bar with animated gradient */}
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <motion.div
          className="h-full bg-gradient-to-r from-primary via-[oklch(0.7_0.2_330)] to-primary"
          initial={false}
          animate={{ width: `${progress}%` }}
          transition={{ type: "spring", stiffness: 300, damping: 30 }}
          style={{ backgroundSize: "200% 100%" }}
        />
      </div>

      {/* Touch-friendly step dots - 44px minimum touch targets */}
      <div className="mt-3 flex items-center justify-center">
        {WIZARD_STEPS.map((step) => {
          const isActive = step.id === currentStep;
          const isCompleted = completedSteps.includes(step.id);
          const showCompletedState = isCompleted && !isActive;
          const isClickable = isCompleted || step.id <= highestCompleted + 1;

          return (
            <motion.button
              key={step.id}
              type="button"
              onClick={isClickable && onStepClick ? () => onStepClick(step.id) : undefined}
              disabled={!isClickable}
              className={cn(
                "relative flex items-center justify-center touch-target",
                isClickable && "cursor-pointer",
                !isClickable && "cursor-not-allowed opacity-50"
              )}
              style={{ minWidth: 44, minHeight: 44 }}
              aria-label={`Go to step ${step.id}: ${step.title}`}
              aria-current={isActive ? "step" : undefined}
              whileTap={isClickable ? { scale: 0.9 } : undefined}
            >
              {/* The visible dot */}
              <motion.div
                className={cn(
                  "rounded-full transition-colors",
                  showCompletedState && "bg-[oklch(0.72_0.19_145)]",
                  isActive && "bg-primary",
                  !isActive && !showCompletedState && "bg-muted-foreground/30"
                )}
                initial={false}
                animate={{
                  width: isActive ? 14 : 10,
                  height: isActive ? 14 : 10,
                }}
                transition={{ type: "spring", stiffness: 400, damping: 25 }}
              />

              {/* Active step pulse ring (respects reduced motion) */}
              {isActive && !prefersReducedMotion && (
                <motion.div
                  className="absolute rounded-full border-2 border-primary/50"
                  initial={{ width: 14, height: 14, opacity: 0.8 }}
                  animate={{
                    width: [14, 28, 14],
                    height: [14, 28, 14],
                    opacity: [0.8, 0, 0.8],
                  }}
                  transition={{
                    duration: 2,
                    repeat: Infinity,
                    ease: "easeInOut",
                  }}
                />
              )}

              {/* Completed checkmark overlay */}
              {showCompletedState && (
                <motion.div
                  className="absolute flex items-center justify-center"
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", stiffness: 500, damping: 25 }}
                >
                  <Check
                    className="h-2.5 w-2.5 text-[oklch(0.15_0.02_145)]"
                    strokeWidth={3}
                  />
                </motion.div>
              )}
            </motion.button>
          );
        })}
      </div>

      {/* Current step label and swipe hint */}
      {currentStepData && (
        <div className="mt-2 text-center">
          <motion.span
            key={currentStepData.id}
            className="text-sm font-medium text-foreground"
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ type: "spring", stiffness: 300, damping: 25 }}
          >
            {currentStepData.title}
          </motion.span>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Step {currentStep} of {WIZARD_STEPS.length}
            <span className="mx-1.5 opacity-50">|</span>
            <span className="opacity-70">Swipe to navigate</span>
          </p>
        </div>
      )}
    </div>
  );
}

export type { WizardStep };
