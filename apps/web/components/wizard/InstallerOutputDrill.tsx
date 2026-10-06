"use client";

/**
 * "Keep waiting or act?" drill for reading installer output (bd-hjbld).
 * Scenarios live in lib/installerOutputDrill.ts and quote install.sh verbatim.
 */

import { CheckCircle2, ChevronDown, RotateCcw, XCircle } from "lucide-react";
import { useId, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  INSTALLER_OUTPUT_DRILL,
  isDrillAnswerCorrect,
  type DrillChoice,
  type DrillLineKind,
} from "@/lib/installerOutputDrill";
import { cn } from "@/lib/utils";

const LINE_STYLES: Record<DrillLineKind, string> = {
  step: "text-primary",
  success: "text-green",
  warning: "text-amber",
  error: "text-destructive",
  info: "text-foreground",
  ssh: "text-muted-foreground",
  narration: "italic text-muted-foreground",
};

const CHOICE_LABELS: Record<DrillChoice, string> = {
  wait: "Keep waiting",
  act: "I need to act",
};

const CHOICES: DrillChoice[] = ["wait", "act"];

export function InstallerOutputDrill() {
  const [open, setOpen] = useState(false);
  const [index, setIndex] = useState(0);
  const [choices, setChoices] = useState<Array<DrillChoice | null>>(() =>
    INSTALLER_OUTPUT_DRILL.map(() => null),
  );
  const panelId = useId();
  const nextRef = useRef<HTMLButtonElement>(null);
  const startRef = useRef<HTMLButtonElement>(null);

  const total = INSTALLER_OUTPUT_DRILL.length;
  const scenario = index < total ? INSTALLER_OUTPUT_DRILL[index] : null;
  const choice = scenario ? choices[index] : null;
  const correct = INSTALLER_OUTPUT_DRILL.filter((item, i) => {
    const picked = choices[i];
    return picked !== null && isDrillAnswerCorrect(item, picked);
  }).length;

  const answer = (picked: DrillChoice) => {
    if (choice) return;
    setChoices((current) => current.map((value, i) => (i === index ? picked : value)));
    requestAnimationFrame(() => nextRef.current?.focus());
  };

  const next = () => {
    setIndex((value) => value + 1);
    if (index + 1 >= total) requestAnimationFrame(() => startRef.current?.focus());
  };

  const restart = () => {
    setIndex(0);
    setChoices(INSTALLER_OUTPUT_DRILL.map(() => null));
  };

  return (
    <div className="space-y-3">
      <Button
        type="button"
        variant="outline"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        onClick={() => setOpen((value) => !value)}
      >
        {open ? "Hide the practice questions" : "Practice reading installer output"}
        <ChevronDown
          aria-hidden="true"
          className={cn("h-4 w-4 transition-transform", open && "rotate-180")}
        />
      </Button>

      {open && (
        <div id={panelId} className="space-y-3 rounded-xl border border-border/60 bg-card/50 p-4">
          {scenario ? (
            <>
              <p className="text-sm font-medium">
                Question {index + 1} of {total}: keep waiting, or do you need to act?
              </p>
              <div
                role="group"
                aria-label="Installer output"
                className="dark rounded-lg bg-[oklch(0.08_0.015_260)] p-3 font-mono text-sm"
              >
                {scenario.lines.map((line) => (
                  <p
                    key={line.text}
                    className={cn("whitespace-pre-wrap break-words", LINE_STYLES[line.kind])}
                  >
                    {line.text}
                  </p>
                ))}
              </div>
              <div className="flex flex-wrap gap-2">
                {CHOICES.map((option) => (
                  <Button
                    key={option}
                    type="button"
                    size="sm"
                    variant={choice === option ? "default" : "secondary"}
                    aria-pressed={choice === option}
                    aria-disabled={choice !== null}
                    onClick={() => answer(option)}
                  >
                    {CHOICE_LABELS[option]}
                  </Button>
                ))}
              </div>
            </>
          ) : (
            <p className="text-sm font-medium">
              You got {correct} of {total} right. You&apos;re ready to read the real thing.
            </p>
          )}

          {/* Always rendered so screen readers hear each verdict. */}
          <div aria-live="polite" className="text-sm">
            {scenario && choice && (
              <p className="flex gap-2">
                {isDrillAnswerCorrect(scenario, choice) ? (
                  <CheckCircle2 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-green" />
                ) : (
                  <XCircle aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
                )}
                <span>
                  <strong>
                    {isDrillAnswerCorrect(scenario, choice)
                      ? "Right."
                      : `Not quite: ${CHOICE_LABELS[scenario.answer].toLowerCase()}.`}
                  </strong>{" "}
                  {scenario.explanation}
                </span>
              </p>
            )}
          </div>

          {scenario && choice && (
            <Button ref={nextRef} type="button" size="sm" onClick={next}>
              {index + 1 < total ? "Next question" : "See my result"}
            </Button>
          )}
          {!scenario && (
            <Button ref={startRef} type="button" size="sm" variant="ghost" onClick={restart}>
              <RotateCcw aria-hidden="true" className="h-4 w-4" />
              Start over
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
