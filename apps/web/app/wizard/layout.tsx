"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Terminal, Home, ChevronLeft, ChevronRight, AlertCircle } from "lucide-react";
import { useDrag } from "@use-gesture/react";
import { Button } from "@/components/ui/button";
import { Stepper, StepperMobile } from "@/components/stepper";
import { HelpPanel } from "@/components/wizard/HelpPanel";
import { ThemeToggle } from "@/components/ui/theme-toggle";
import {
  WIZARD_STEPS,
  WizardForwardNavContext,
  canAccessWizardStep,
  getCompletedSteps,
  getNextReachableWizardStep,
  getStepBySlug,
  useCompletedSteps,
  type WizardForwardAction,
  type WizardForwardNavRegistry,
} from "@/lib/wizardSteps";
import { useStepValidation } from "@/lib/hooks/useStepValidation";
import { getUserOS, getVPSIP, useUserOS } from "@/lib/userPreferences";
import { cn, withCurrentSearch } from "@/lib/utils";

export default function WizardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const currentSlug = pathname?.split("/").pop() || "";
  const isBonusRoute = currentSlug === "windows-terminal-setup";

  // Extract current step from URL path
  const currentStep = useMemo(() => {
    const step = getStepBySlug(currentSlug);
    return step?.id ?? 1;
  }, [currentSlug]);
  const hideSharedStepChrome = isBonusRoute;

  // Linux users skip step 2 (they already have a terminal), so from step 3
  // the previous step is 1. Deriving it from step ids alone sent Back to
  // install-terminal, which immediately bounced forward again — a dead
  // control. useUserOS is the SSR-safe (query-backed) read of the same
  // preference the forward skip below checks with getUserOS().
  const [userOS] = useUserOS();
  const prevStepId =
    currentStep === 3 && userOS === "linux" ? 1 : currentStep - 1;
  const prevStep = WIZARD_STEPS.find((s) => s.id === prevStepId);
  const nextStep = WIZARD_STEPS.find((s) => s.id === currentStep + 1);
  const [completedSteps, markCompletedStep] = useCompletedSteps();

  const { validate, showErrors, validationErrors, clearErrors } = useStepValidation();

  // The current step page registers its own forward action here (see
  // useWizardForwardNav). The mobile dock's "Next" delegates to it so the
  // dock and the page's inline Continue are one behavior, not two.
  const [forwardAction, setForwardAction] = useState<WizardForwardAction | null>(null);
  const forwardNavRegistry = useMemo<WizardForwardNavRegistry>(
    () => ({ register: setForwardAction }),
    []
  );

  useEffect(() => {
    clearErrors();
  }, [pathname, clearErrors]);

  useEffect(() => {
    if (hideSharedStepChrome) return;

    // Treat known preferences as completing the step that produces them, so a
    // returning visitor (or a `?os=` deep link) is not bounced to step 1 when
    // the completed-steps list is empty: a known OS implies step 1
    // (os-selection), and a stored valid VPS IP implies steps 1-5 (the IP is
    // entered on create-vps, step 5). The IP is never imported from a `?ip=`
    // query parameter (lib/userPreferences.ts scrubs it for privacy), so an
    // OS-known / IP-missing deep link lands on the next reachable step.
    const impliedComplete = new Set(getCompletedSteps());
    if (getUserOS() !== null) {
      impliedComplete.add(1);
    }
    if (getVPSIP() !== null) {
      for (let step = 1; step <= 5; step += 1) {
        impliedComplete.add(step);
      }
    }
    const persistedSteps = [...impliedComplete];
    if (canAccessWizardStep(persistedSteps, currentStep)) {
      return;
    }

    const redirectStep = getNextReachableWizardStep(persistedSteps);
    router.replace(withCurrentSearch(`/wizard/${redirectStep.slug}`));
  }, [currentStep, hideSharedStepChrome, router]);

  const handleStepClick = useCallback(
    (stepId: number) => {
      const step = WIZARD_STEPS.find((s) => s.id === stepId);
      if (!step) return;

      // Advancing to the immediate next step completes the current one: the
      // mobile Next button has no other way to record progress, and without
      // this the canAccessWizardStep gate below silently rejects the click.
      const isImmediateNext = stepId === currentStep + 1;
      const reachableSteps = isImmediateNext
        ? [...completedSteps, currentStep]
        : completedSteps;

      if (stepId > currentStep) {
        // Locked sidebar steps stay clickable (aria-disabled, not disabled)
        // so a click can explain the gate instead of doing nothing.
        if (!canAccessWizardStep(reachableSteps, stepId)) {
          // Count the current step as in progress so the message names the
          // first step that is still out of reach, not the page they're on.
          const nextReachable = getNextReachableWizardStep([...completedSteps, currentStep]);
          showErrors([
            `Finish the steps in order — step ${nextReachable.id} (${nextReachable.title}) is next.`,
          ]);
          return;
        }

        // Validate the current step before allowing forward navigation.
        // Backward navigation is always allowed (don't block exploration).
        const result = validate(currentStep);
        if (!result.valid) return;
      } else if (!canAccessWizardStep(reachableSteps, stepId)) {
        return;
      }

      if (isImmediateNext) {
        markCompletedStep(currentStep);
      }

      clearErrors();

      // Linux users already have a terminal, so the shared Next button must
      // make the same jump the OS-selection page's own Continue makes:
      // skip step 2 and record it as done so the step gate stays consistent.
      if (currentStep === 1 && stepId === 2 && getUserOS() === "linux") {
        markCompletedStep(2);
        const sshKeyStep = WIZARD_STEPS.find((s) => s.id === 3);
        if (sshKeyStep) {
          router.push(withCurrentSearch(`/wizard/${sshKeyStep.slug}`));
          return;
        }
      }

      router.push(withCurrentSearch(`/wizard/${step.slug}`));
    },
    [router, currentStep, validate, showErrors, clearErrors, completedSteps, markCompletedStep]
  );

  const progress = (currentStep / WIZARD_STEPS.length) * 100;

  // Phones showed two forward controls at once: the page's own affirmative
  // button ("I saved my public key") and, ~150px below it, the dock's "Next".
  // The dock now (a) hides its copy while the page button is on screen above
  // the dock, and (b) otherwise repeats the page button's label, so there is
  // one forward action with one name wherever the visitor is on the page.
  const [ctaInView, setCtaInView] = useState(false);
  const forwardCtaEl = forwardAction?.ctaElement ?? null;
  useEffect(() => {
    // State only changes from the observer callback (an IntersectionObserver
    // reports the initial intersection as soon as `observe` is called); a
    // step with no registered button is handled by the `forwardCtaEl &&`
    // guard below rather than by resetting state here.
    if (!forwardCtaEl || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => setCtaInView(entry?.isIntersecting ?? false),
      // The bottom inset is the dock's height: a button hidden under the
      // dock is not "on screen" for this purpose.
      { threshold: 0.5, rootMargin: "0px 0px -168px 0px" }
    );
    observer.observe(forwardCtaEl);
    return () => observer.disconnect();
  }, [forwardCtaEl]);

  const hasNextStep = Boolean(nextStep) && !hideSharedStepChrome;
  const showDockNext = hasNextStep && !(forwardCtaEl && ctaInView);
  const dockNextLabel = forwardAction?.label ?? "Next";
  const dockNextBlocked = Boolean(forwardAction?.disabled) || Boolean(forwardAction?.loading);
  const handleDockNext = useCallback(() => {
    if (forwardAction) {
      if (forwardAction.loading) return;
      if (forwardAction.disabled) {
        // Not `disabled`: a greyed button that does nothing explains nothing.
        // The step validator names the blocker and scrolls to it.
        validate(currentStep);
        return;
      }
      forwardAction.onContinue();
      return;
    }
    if (nextStep) handleStepClick(nextStep.id);
  }, [forwardAction, nextStep, handleStepClick, validate, currentStep]);

  // "Swipe to navigate" (the hint in StepperMobile) is bound to the whole
  // fixed dock — progress strip and Back/Next row — not just the 60px strip.
  // Swipe-forward runs the same registered forward action as the dock
  // "Next", and honors its disabled/loading state, so there is exactly one
  // forward behavior per step regardless of the control used.
  const bindDockSwipe = useDrag(
    ({ direction: [dx], velocity: [vx], active, movement: [mx] }) => {
      // Only trigger on release with sufficient velocity or distance
      if (active || (Math.abs(vx) <= 0.3 && Math.abs(mx) <= 50)) return;
      if (dx > 0) {
        // Swipe right = go back
        if (prevStep) handleStepClick(prevStep.id);
      } else if (dx < 0) {
        // Swipe left = go forward (also while the page button is on screen)
        if (hasNextStep && !dockNextBlocked) handleDockNext();
      }
    },
    {
      enabled: !hideSharedStepChrome,
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
    <WizardForwardNavContext.Provider value={forwardNavRegistry}>
    <div className="relative min-h-screen overflow-x-clip bg-background">
      {/* Subtle background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      {/* Desktop layout with sidebar */}
      <div className="relative mx-auto flex max-w-7xl">
        {/* Stepper sidebar - hidden on mobile */}
        <aside className="sticky top-0 hidden h-dvh w-72 shrink-0 border-r border-border/50 bg-sidebar/80 backdrop-blur-sm md:block">
          <div className="flex h-full flex-col">
            {/* Logo */}
            <div className="flex items-center gap-3 border-b border-border/50 px-6 py-5">
              <Link href="/" className="flex items-center gap-2 transition-opacity hover:opacity-80">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
                  <Terminal className="h-4 w-4 text-primary" />
                </div>
                <span className="font-mono text-sm font-bold tracking-tight">Agent Flywheel</span>
              </Link>
            </div>

            {/* Progress indicator */}
            {hideSharedStepChrome ? (
              <div className="px-6 py-4 text-xs text-muted-foreground">Optional guide</div>
            ) : (
              <div className="px-6 py-4">
                <div className="mb-2 flex items-center justify-between text-xs">
                  <span className="text-muted-foreground">Progress</span>
                  <span className="font-mono text-primary">{currentStep}/{WIZARD_STEPS.length}</span>
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                  <div
                    className="h-full bg-gradient-to-r from-primary to-magenta transition-[width] duration-500"
                    style={{ width: `${progress}%` }}
                  />
                </div>
              </div>
            )}

            {/* Step list */}
            <div className="flex-1 overflow-y-auto px-4 py-2">
              {hideSharedStepChrome ? (
                <div className="rounded-xl border border-border/50 bg-card/40 px-4 py-3 text-sm text-muted-foreground">
                  This is an optional detour, not a numbered wizard step.
                </div>
              ) : (
                <Stepper currentStep={currentStep} onStepClick={handleStepClick} />
              )}
            </div>

            {/* Sidebar footer */}
            <div className="border-t border-border/50 p-4 space-y-1">
              <div className="flex items-center justify-between">
                <Button
                  asChild
                  variant="ghost"
                  size="sm"
                  className="justify-start text-muted-foreground hover:text-foreground"
                >
                  <Link href="/">
                    <Home className="mr-2 h-4 w-4" />
                    Back to Home
                  </Link>
                </Button>
                <ThemeToggle />
              </div>
            </div>
          </div>
        </aside>

        {/* Main content. Bottom padding on phones must clear the fixed dock
            (progress strip + label + 48px buttons + safe-area inset ≈ 168px
            on notched iPhones), otherwise the last control sits under it. */}
        <main
          id="main-content"
          tabIndex={-1}
          className="flex-1 pb-[calc(10.5rem+env(safe-area-inset-bottom))] md:pb-8"
        >
          {/* Mobile header. The logo link is the Home control; a second
              icon-only Home link next to it was a duplicate at 32px. */}
          <div className="sticky top-0 z-20 flex items-center justify-between border-b border-border/50 bg-background/80 px-4 py-3 backdrop-blur-sm md:hidden">
            <Link href="/" className="flex items-center gap-2">
              <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/20">
                <Terminal className="h-3.5 w-3.5 text-primary" />
              </div>
              <span className="font-mono text-sm font-bold">Agent Flywheel</span>
            </Link>
            <div className="flex items-center gap-1.5">
              <HelpPanel
                currentStep={currentStep}
                title={hideSharedStepChrome ? "Optional guide help" : undefined}
              />
              <ThemeToggle />
              <div className="text-xs text-muted-foreground">
                {hideSharedStepChrome ? (
                  <span>Optional</span>
                ) : (
                  <>
                    <span className="font-mono text-primary">{currentStep}</span>/{WIZARD_STEPS.length}
                  </>
                )}
              </div>
            </div>
          </div>

          {/* Content area */}
          <div className="px-6 py-8 md:px-12 md:py-12">
            <div className="mx-auto max-w-2xl">
              {/* Step indicator (mobile) — the desktop block below is hidden
                  on small screens, so without this mobile users get no
                  "where am I" signal at the top of the page. No HelpPanel
                  here: its collapsed content would precede the page content
                  in DOM order and shadow text queries for on-page content. */}
              {!hideSharedStepChrome && (
                <div className="mb-4 text-sm text-muted-foreground md:hidden">
                  <span>Step</span> <span>{currentStep}</span>{" "}
                  <span>of {WIZARD_STEPS.length}</span>
                </div>
              )}

              {/* Step title (desktop) */}
              <div className="mb-8 hidden md:block">
                <div className="mb-2 flex items-center justify-between">
                  {hideSharedStepChrome ? (
                    <div className="text-sm text-muted-foreground">Optional guide</div>
                  ) : (
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/20 font-mono text-xs text-primary">
                        {currentStep}
                      </span>
                      <span>Step {currentStep} of {WIZARD_STEPS.length}</span>
                    </div>
                  )}
                  <HelpPanel
                    currentStep={currentStep}
                    title={hideSharedStepChrome ? "Optional guide help" : undefined}
                  />
                </div>
              </div>

              {/* Validation error banner */}
              {validationErrors.length > 0 && (
                <div
                  role="alert"
                  className="mb-4 flex items-start gap-2 rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive animate-in fade-in slide-in-from-top-2 duration-200"
                >
                  <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                  <div>
                    {validationErrors.map((err) => (
                      <p key={err}>{err}</p>
                    ))}
                  </div>
                </div>
              )}

              {/* Page content */}
              <div className="animate-scale-in">{children}</div>

              {/* Back link (desktop). Forward navigation belongs to the
                  page's own contextual Continue button, which sits directly
                  above this row; a second "Next" here competed with it. */}
              {!hideSharedStepChrome && prevStep && (
                <div className="mt-12 hidden items-center md:flex">
                  <Button
                    variant="ghost"
                    onClick={() => handleStepClick(prevStep.id)}
                    className="text-muted-foreground hover:text-foreground"
                  >
                    <ChevronLeft className="mr-1 h-4 w-4" />
                    {prevStep.title}
                  </Button>
                </div>
              )}
            </div>
          </div>
        </main>
      </div>

      {/* Mobile dock - shown only on mobile. The swipe gesture is bound to
          the progress strip, not the whole dock: with the gesture on the
          container, touch taps on the Back/Next buttons were consumed by the
          gesture layer and never became clicks (Mobile Chrome e2e). */}
      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-border/50 bg-background/95 px-4 pt-4 backdrop-blur-md bottom-nav-safe md:hidden">
        {!hideSharedStepChrome && (
          <div
            {...bindDockSwipe()}
            className="select-none"
            style={{ touchAction: "pan-x pan-y" }}
          >
            <StepperMobile currentStep={currentStep} />
          </div>
        )}

        {/* Mobile navigation - 48px buttons for proper touch targets.
            "Next" runs the page's registered forward action (validation,
            analytics, special routing included); it only falls back to the
            plain step advance for pages that register nothing. */}
        {!hideSharedStepChrome && (
          <div className="mt-4 flex items-center gap-3">
          <Button
            variant="outline"
            size="lg"
            onClick={() => prevStep && handleStepClick(prevStep.id)}
            disabled={!prevStep}
            // Compact next to a labelled forward action; full width when the
            // forward control is the page's own button.
            className={showDockNext ? "shrink-0" : "w-full"}
          >
            <ChevronLeft className="mr-1 h-5 w-5" />
            Back
          </Button>
          {showDockNext && (
            <Button
              size="lg"
              onClick={handleDockNext}
              aria-disabled={dockNextBlocked || undefined}
              aria-busy={Boolean(forwardAction?.loading) || undefined}
              data-testid="wizard-dock-next"
              // The mirrored label can be long ("I saved my public key"):
              // let it take the row, constrain the Button's inner content
              // wrapper so the label can shrink and ellipsize instead of
              // overflowing (centred overflow clipped both ends of the text).
              className={cn(
                "flex-1 min-w-0 [&>span]:min-w-0 [&>span]:max-w-full",
                dockNextLabel.length > 14 && "text-sm",
                dockNextBlocked && "opacity-60"
              )}
            >
              <span className="min-w-0 truncate">
                {forwardAction?.loading ? "Loading..." : dockNextLabel}
              </span>
              <ChevronRight className="ml-1 h-5 w-5 shrink-0" />
            </Button>
          )}
          </div>
        )}
      </div>
    </div>
    </WizardForwardNavContext.Provider>
  );
}
