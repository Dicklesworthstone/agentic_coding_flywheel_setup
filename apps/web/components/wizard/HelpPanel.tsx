"use client";

/**
 * HelpPanel — Contextual "Need help?" dialog for the wizard.
 *
 * Shows step-specific troubleshooting, tips, and a debug info export.
 * Uses the native <dialog> element for built-in focus trap and Escape handling.
 *
 * @see bd-1yfv
 */

import { useCallback, useEffect, useId, useRef, useState } from "react";
import {
  HelpCircle,
  X,
  Copy,
  Check,
  ChevronRight,
  Lightbulb,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { copyTextToClipboard } from "@/lib/utils";
import { STEP_HELP, getDebugInfo, type StepHelp } from "@/lib/stepHelp";

const DEFAULT_HELP: StepHelp = {
  commonIssues: [],
  tips: [
    "Make sure you're following the steps in order.",
    "If a command fails, try running it again — transient errors are common.",
    "Check that you're running commands in the right place (local terminal vs. VPS).",
  ],
};

interface HelpPanelProps {
  currentStep: number;
  /**
   * Dialog heading. Defaults to "Step N Help"; the optional bonus route
   * (windows-terminal-setup) passes its own so the panel does not claim to
   * be a numbered step.
   */
  title?: string;
}

type CopyState = "idle" | "copied" | "failed";

export function HelpPanel({ currentStep, title }: HelpPanelProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [copyState, setCopyState] = useState<CopyState>("idle");
  const headingId = useId();
  const dialogTitle = title ?? `Step ${currentStep} Help`;
  // Mount the dialog body only while open: the panel renders above the page
  // content, so keeping the help text permanently in the DOM (hidden inside
  // the closed <dialog>) makes it shadow text queries and selectors that
  // expect the page's own visible content to come first.
  const [isOpen, setIsOpen] = useState(false);
  const copyResetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (copyResetTimerRef.current) {
        clearTimeout(copyResetTimerRef.current);
      }
    };
  }, []);

  const help = STEP_HELP[currentStep] ?? DEFAULT_HELP;
  const hasIssues = help.commonIssues.length > 0;
  const hasTips = help.tips.length > 0;

  const openDialog = useCallback(() => {
    setIsOpen(true);
    dialogRef.current?.showModal();
  }, []);

  const closeDialog = useCallback(() => {
    dialogRef.current?.close();
  }, []);

  const copyDebugInfo = useCallback(async () => {
    const info = getDebugInfo(currentStep);
    const copiedOk = await copyTextToClipboard(info);
    if (copyResetTimerRef.current) {
      clearTimeout(copyResetTimerRef.current);
      copyResetTimerRef.current = null;
    }
    if (!copiedOk) {
      // Clipboard blocked (strict privacy modes, some in-app webviews):
      // say so, and keep the message until the next attempt — the debug
      // text is rendered below so it can be selected and copied by hand.
      setCopyState("failed");
      return;
    }
    setCopyState("copied");
    copyResetTimerRef.current = setTimeout(() => {
      setCopyState("idle");
      copyResetTimerRef.current = null;
    }, 2000);
  }, [currentStep]);

  return (
    <>
      {/* Trigger button */}
      <Button
        variant="ghost"
        size="sm"
        onClick={openDialog}
        // Below `sm` the label is hidden and this is an icon-only control in
        // the mobile header, so it takes the 44px icon-button footprint there.
        className="h-11 w-11 gap-1.5 px-0 text-muted-foreground hover:text-foreground sm:h-9 sm:w-auto sm:px-4"
        aria-label="Need help?"
      >
        <HelpCircle className="h-4 w-4" />
        <span className="hidden sm:inline">Need help?</span>
      </Button>

      {/* Dialog */}
      <dialog
        ref={dialogRef}
        aria-labelledby={headingId}
        className="m-auto w-full max-w-lg rounded-xl border border-border bg-background p-0 text-foreground shadow-2xl backdrop:bg-black/50 backdrop:backdrop-blur-sm"
        onClick={(e) => {
          // Close on backdrop click
          if (e.target === dialogRef.current) closeDialog();
        }}
        onClose={() => setIsOpen(false)}
      >
        {isOpen && (
        <div className="flex max-h-[80vh] flex-col">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-border/50 px-6 py-4">
            <h2 id={headingId} className="flex items-center gap-2 text-lg font-semibold">
              <HelpCircle className="h-5 w-5 text-primary" />
              {dialogTitle}
            </h2>
            <button
              onClick={closeDialog}
              className="flex h-10 w-10 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background outline-none"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Scrollable content */}
          <div className="flex-1 overflow-y-auto px-6 py-4 space-y-6">
            {/* Common Issues */}
            {hasIssues && (
              <section>
                <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Common Issues
                </h3>
                <div className="space-y-3">
                  {help.commonIssues.map((issue) => (
                    <details
                      key={issue.symptom}
                      className="group rounded-lg border border-border/50 bg-muted/30"
                    >
                      <summary className="flex cursor-pointer items-center gap-2 px-4 py-3 text-sm font-medium text-foreground rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset">
                        <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-90" />
                        {issue.symptom}
                      </summary>
                      <div className="border-t border-border/30 px-4 py-3 text-sm text-muted-foreground">
                        {issue.solution}
                      </div>
                    </details>
                  ))}
                </div>
              </section>
            )}

            {/* Tips */}
            {hasTips && (
              <section>
                <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Tips
                </h3>
                <ul className="space-y-2">
                  {help.tips.map((tip) => (
                    <li
                      key={tip}
                      className="flex items-start gap-2 text-sm text-muted-foreground"
                    >
                      <Lightbulb className="mt-0.5 h-4 w-4 shrink-0 text-amber" />
                      {tip}
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {/* Debug Info */}
            <section className="rounded-lg border border-border/50 bg-muted/20 p-4">
              <h3 className="mb-2 text-sm font-semibold text-muted-foreground">
                Share Debug Info
              </h3>
              <p className="mb-3 text-xs text-muted-foreground">
                Copy this information when asking for help — it helps us
                diagnose the issue faster.
              </p>
              <Button
                variant="outline"
                size="sm"
                onClick={copyDebugInfo}
                className="gap-1.5"
              >
                {copyState === "copied" ? (
                  <>
                    <Check className="h-3.5 w-3.5 text-green" />
                    Copied
                  </>
                ) : (
                  <>
                    <Copy className="h-3.5 w-3.5" />
                    Copy Debug Info
                  </>
                )}
              </Button>
              {/* Live region: announces the outcome to screen readers and
                  gives a visible failure path when the clipboard is blocked. */}
              <p role="status" className={copyState === "failed" ? "mt-2 text-xs" : "sr-only"}>
                {copyState === "copied" && (
                  <span className="text-muted-foreground">Copied to clipboard.</span>
                )}
                {copyState === "failed" && (
                  <span className="text-destructive">
                    Copy failed — select the text and copy it manually.
                  </span>
                )}
              </p>
              {copyState === "failed" && (
                <pre className="mt-2 max-h-40 overflow-auto rounded-md border border-border/50 bg-background px-3 py-2 font-mono text-xs text-foreground select-all">
                  {getDebugInfo(currentStep)}
                </pre>
              )}
            </section>
          </div>
        </div>
        )}
      </dialog>
    </>
  );
}
