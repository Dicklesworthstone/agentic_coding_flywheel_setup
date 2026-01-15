"use client";

import { useCallback, useEffect } from "react";
import confetti from "canvas-confetti";
import { PartyPopper, Sparkles, Trophy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

// Encouraging messages for lesson completion
const COMPLETION_MESSAGES = [
  "Great job!",
  "You're crushing it!",
  "Nicely done!",
  "Keep it up!",
  "Excellent work!",
  "You're on fire!",
] as const;

// Special messages for completing all lessons
const FINAL_MESSAGES = [
  "You did it! All lessons complete!",
  "Congratulations! You're now an agent pro!",
  "Amazing! You've mastered the fundamentals!",
] as const;


/**
 * Fire a confetti burst from the center of the screen
 */
function fireConfetti() {
  const count = 200;
  const defaults = {
    origin: { y: 0.7 },
    zIndex: 9999,
  };

  function fire(particleRatio: number, opts: confetti.Options) {
    confetti({
      ...defaults,
      ...opts,
      particleCount: Math.floor(count * particleRatio),
    });
  }

  // Staggered burst for more visual impact
  fire(0.25, {
    spread: 26,
    startVelocity: 55,
  });
  fire(0.2, {
    spread: 60,
  });
  fire(0.35, {
    spread: 100,
    decay: 0.91,
    scalar: 0.8,
  });
  fire(0.1, {
    spread: 120,
    startVelocity: 25,
    decay: 0.92,
    scalar: 1.2,
  });
  fire(0.1, {
    spread: 120,
    startVelocity: 45,
  });
}

/**
 * Fire an extra celebratory confetti for completing all lessons
 */
function fireFinalConfetti() {
  const duration = 3000;
  const animationEnd = Date.now() + duration;
  const defaults = { startVelocity: 30, spread: 360, ticks: 60, zIndex: 9999 };

  function randomInRange(min: number, max: number) {
    return Math.random() * (max - min) + min;
  }

  const interval = setInterval(() => {
    const timeLeft = animationEnd - Date.now();

    if (timeLeft <= 0) {
      clearInterval(interval);
      return;
    }

    const particleCount = 50 * (timeLeft / duration);

    // Fire from both sides
    confetti({
      ...defaults,
      particleCount,
      origin: { x: randomInRange(0.1, 0.3), y: Math.random() - 0.2 },
    });
    confetti({
      ...defaults,
      particleCount,
      origin: { x: randomInRange(0.7, 0.9), y: Math.random() - 0.2 },
    });
  }, 250);
}

/**
 * Hook to trigger confetti celebration
 */
export function useConfetti() {
  const prefersReducedMotion = useReducedMotion();

  const celebrate = useCallback(
    (isFinalLesson = false) => {
      if (prefersReducedMotion) {
        // Skip animation but still provide feedback (handled by caller)
        return;
      }

      if (isFinalLesson) {
        fireFinalConfetti();
      } else {
        fireConfetti();
      }
    },
    [prefersReducedMotion]
  );

  return { celebrate, prefersReducedMotion };
}

/**
 * Get a random completion message
 */
export function getCompletionMessage(isFinalLesson = false): string {
  const messages = isFinalLesson ? FINAL_MESSAGES : COMPLETION_MESSAGES;
  return messages[Math.floor(Math.random() * messages.length)];
}

interface FinalCelebrationModalProps {
  isOpen: boolean;
  onClose: () => void;
  onGoToDashboard: () => void;
}

/**
 * Special celebration modal for completing all lessons
 */
export function FinalCelebrationModal({
  isOpen,
  onClose,
  onGoToDashboard,
}: FinalCelebrationModalProps) {
  const prefersReducedMotion = useReducedMotion();

  useEffect(() => {
    if (isOpen) {
      // Escape key closes modal
      const handleEscape = (e: KeyboardEvent) => {
        if (e.key === "Escape") onClose();
      };
      window.addEventListener("keydown", handleEscape);
      return () => window.removeEventListener("keydown", handleEscape);
    }
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-background/80 backdrop-blur-sm"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-labelledby="celebration-title"
    >
      <div
        className={`mx-4 max-w-md rounded-2xl border border-primary/30 bg-card/95 p-8 text-center shadow-2xl ${
          prefersReducedMotion ? "" : "animate-in fade-in zoom-in-95 duration-300"
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-6 flex justify-center">
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-amber-400 to-orange-500">
            <Trophy className="h-10 w-10 text-white" />
          </div>
        </div>

        <h2
          id="celebration-title"
          className="mb-2 text-2xl font-bold tracking-tight"
        >
          <span className="text-gradient-cosmic">Congratulations!</span>
        </h2>

        <p className="mb-2 text-lg text-foreground">
          You&apos;ve completed all lessons!
        </p>

        <p className="mb-6 text-muted-foreground">
          You now have a solid foundation in agentic coding. Time to put your
          knowledge into practice!
        </p>

        <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
          <Button
            onClick={onGoToDashboard}
            className="bg-primary text-primary-foreground"
          >
            <Sparkles className="mr-2 h-4 w-4" />
            Back to Dashboard
          </Button>
          <Button variant="outline" onClick={onClose}>
            Stay Here
          </Button>
        </div>
      </div>
    </div>
  );
}

interface CompletionToastProps {
  message: string;
  isVisible: boolean;
}

/**
 * Brief toast notification for lesson completion
 */
export function CompletionToast({ message, isVisible }: CompletionToastProps) {
  const prefersReducedMotion = useReducedMotion();

  if (!isVisible) return null;

  return (
    <div
      className={`fixed left-1/2 top-20 z-[90] -translate-x-1/2 rounded-full border border-primary/30 bg-card/95 px-6 py-3 shadow-lg backdrop-blur-sm ${
        prefersReducedMotion
          ? ""
          : "animate-in fade-in slide-in-from-top-4 duration-300"
      }`}
      role="status"
      aria-live="polite"
    >
      <div className="flex items-center gap-2">
        <PartyPopper className="h-5 w-5 text-primary" />
        <span className="font-medium text-foreground">{message}</span>
      </div>
    </div>
  );
}
