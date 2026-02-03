"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useMemo } from "react";
import { Terminal, Home, ChevronLeft, ChevronRight, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Stepper, StepperMobile } from "@/components/stepper";
import { HelpPanel } from "@/components/wizard/HelpPanel";
import { ThemeToggle } from "@/components/ui/theme-toggle";
import { WIZARD_STEPS, getStepBySlug } from "@/lib/wizardSteps";
import { useStepValidation } from "@/lib/hooks/useStepValidation";
import { withCurrentSearch } from "@/lib/utils";

export default function WizardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();

  // Extract current step from URL path
  const currentStep = useMemo(() => {
    const slug = pathname.split("/").pop() || "";
    const step = getStepBySlug(slug);
    return step?.id ?? 1;
  }, [pathname]);

  const prevStep = WIZARD_STEPS.find((s) => s.id === currentStep - 1);
  const nextStep = WIZARD_STEPS.find((s) => s.id === currentStep + 1);

  const { validate, validationErrors, clearErrors } = useStepValidation();

  const handleStepClick = useCallback(
    (stepId: number) => {
      const step = WIZARD_STEPS.find((s) => s.id === stepId);
      if (!step) return;

      // Validate the current step before allowing forward navigation.
      // Backward navigation is always allowed (don't block exploration).
      if (stepId > currentStep) {
        const result = validate(currentStep);
        if (!result.valid) return;
      }

      clearErrors();
      router.push(withCurrentSearch(`/wizard/${step.slug}`));
    },
    [router, currentStep, validate, clearErrors]
  );

  const progress = (currentStep / WIZARD_STEPS.length) * 100;

  return (
    <div className="relative min-h-screen overflow-x-hidden bg-background">
      {/* Subtle background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      {/* Desktop layout with sidebar */}
      <div className="relative mx-auto flex max-w-7xl">
        {/* Stepper sidebar - hidden on mobile */}
        <aside className="sticky top-0 hidden h-screen w-72 shrink-0 border-r border-border/50 bg-sidebar/80 backdrop-blur-sm md:block">
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
            <div className="px-6 py-4">
              <div className="mb-2 flex items-center justify-between text-xs">
                <span className="text-muted-foreground">Progress</span>
                <span className="font-mono text-primary">{currentStep}/{WIZARD_STEPS.length}</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full bg-gradient-to-r from-primary to-[oklch(0.7_0.2_330)] transition-all duration-500"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>

            {/* Step list */}
            <div className="flex-1 overflow-y-auto px-4 py-2">
              <Stepper currentStep={currentStep} onStepClick={handleStepClick} />
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

        {/* Main content */}
        <main className="flex-1 pb-52 md:pb-8">
          {/* Mobile header */}
          <div className="sticky top-0 z-20 flex items-center justify-between border-b border-border/50 bg-background/80 px-4 py-3 backdrop-blur-sm md:hidden">
            <Link href="/" className="flex items-center gap-2">
              <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/20">
                <Terminal className="h-3.5 w-3.5 text-primary" />
              </div>
              <span className="font-mono text-sm font-bold">Agent Flywheel</span>
            </Link>
            <div className="flex items-center gap-1.5">
              <HelpPanel currentStep={currentStep} />
              <ThemeToggle />
              <Link
                href="/"
                className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
                aria-label="Home"
              >
                <Home className="h-4 w-4" />
              </Link>
              <div className="text-xs text-muted-foreground">
                <span className="font-mono text-primary">{currentStep}</span>/{WIZARD_STEPS.length}
              </div>
            </div>
          </div>

          {/* Content area */}
          <div className="px-6 py-8 md:px-12 md:py-12">
            <div className="mx-auto max-w-2xl">
              {/* Step title (desktop) */}
              <div className="mb-8 hidden md:block">
                <div className="mb-2 flex items-center justify-between">
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <span className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/20 font-mono text-xs text-primary">
                      {currentStep}
                    </span>
                    <span>Step {currentStep} of {WIZARD_STEPS.length}</span>
                  </div>
                  <HelpPanel currentStep={currentStep} />
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

              {/* Navigation buttons (desktop) */}
              <div className="mt-12 hidden items-center justify-between md:flex">
                {prevStep ? (
                  <Button
                    variant="ghost"
                    onClick={() => handleStepClick(prevStep.id)}
                    className="text-muted-foreground hover:text-foreground"
                  >
                    <ChevronLeft className="mr-1 h-4 w-4" />
                    {prevStep.title}
                  </Button>
                ) : (
                  <div />
                )}
                {/* Hide Next button on step 5 - page has its own validated Continue button */}
                {nextStep && currentStep !== 5 && (
                  <Button
                    onClick={() => handleStepClick(nextStep.id)}
                    className="bg-primary text-primary-foreground"
                  >
                    {nextStep.title}
                    <ChevronRight className="ml-1 h-4 w-4" />
                  </Button>
                )}
              </div>
            </div>
          </div>
        </main>
      </div>

      {/* Mobile stepper - shown only on mobile */}
      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-border/50 bg-background/95 px-4 pt-4 backdrop-blur-md bottom-nav-safe md:hidden">
        <StepperMobile currentStep={currentStep} onStepClick={handleStepClick} />

        {/* Mobile navigation - 48px buttons for proper touch targets */}
        <div className="mt-4 flex items-center gap-3">
          <Button
            variant="outline"
            size="lg"
            onClick={() => prevStep && handleStepClick(prevStep.id)}
            disabled={!prevStep}
            className={currentStep === 5 ? "w-full" : "flex-1"}
          >
            <ChevronLeft className="mr-1 h-5 w-5" />
            Back
          </Button>
          {/* Hide Next button on step 5 - page has its own validated Continue button */}
          {currentStep !== 5 && (
            <Button
              size="lg"
              onClick={() => nextStep && handleStepClick(nextStep.id)}
              disabled={!nextStep}
              className="flex-1"
            >
              Next
              <ChevronRight className="ml-1 h-5 w-5" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
