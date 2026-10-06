"use client";

/**
 * Practice terminal for the first SSH login (bd-hjbld). Scripted by
 * lib/sshRehearsal.ts: nothing connects anywhere, and the practice password
 * is never kept.
 */

import { ChevronDown, ClipboardPaste, CornerDownLeft, RotateCcw } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  isSshRehearsalSecret,
  sshRehearsalCommand,
  sshRehearsalPrompt,
  startSshRehearsal,
  stepSshRehearsal,
  type SshRehearsalLineKind,
} from "@/lib/sshRehearsal";
import { cn } from "@/lib/utils";

const LINE_STYLES: Record<SshRehearsalLineKind, string> = {
  input: "text-foreground",
  output: "text-muted-foreground",
  warning: "text-amber",
  error: "text-destructive",
  success: "text-green",
  note: "text-primary",
};

export function SshRehearsal({ target, host }: { target: string; host: string }) {
  const [open, setOpen] = useState(false);
  const [state, setState] = useState(() => startSshRehearsal(target, host));
  const [input, setInput] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const logRef = useRef<HTMLDivElement>(null);
  const panelId = useId();
  const inputId = useId();
  const hintId = useId();

  // The parent keys this component by target, so a changed IP starts fresh.
  useEffect(() => {
    const log = logRef.current;
    if (log) log.scrollTop = log.scrollHeight;
  }, [state.lines.length]);

  const secret = isSshRehearsalSecret(state);
  const prompt = sshRehearsalPrompt(state);

  const submit = () => {
    setState((current) => stepSshRehearsal(current, input));
    setInput("");
    inputRef.current?.focus();
  };

  const restart = () => {
    setState(startSshRehearsal(target, host));
    setInput("");
    inputRef.current?.focus();
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
        {open ? "Hide the practice terminal" : "Practice this login first"}
        <ChevronDown
          aria-hidden="true"
          className={cn("h-4 w-4 transition-transform", open && "rotate-180")}
        />
      </Button>

      {open && (
        <div id={panelId} className="space-y-3 rounded-xl border border-border/60 bg-card/50 p-4">
          <p className="text-sm text-muted-foreground">
            Practice only: this connects nowhere. At the password prompt, type anything except
            your real password.
          </p>

          <div
            ref={logRef}
            role="log"
            aria-live="polite"
            aria-label="Practice terminal output"
            tabIndex={0}
            className="dark max-h-72 overflow-y-auto rounded-lg bg-[oklch(0.08_0.015_260)] p-3 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {state.lines.map((line, index) => (
              <p
                key={index}
                className={cn("whitespace-pre-wrap break-words", LINE_STYLES[line.kind])}
              >
                {line.text}
              </p>
            ))}
          </div>

          <form
            className="space-y-2"
            onSubmit={(event) => {
              event.preventDefault();
              submit();
            }}
          >
            <label htmlFor={inputId} className="block break-words font-mono text-sm">
              {prompt}
            </label>
            <div className="flex gap-2">
              <input
                ref={inputRef}
                id={inputId}
                type={secret ? "password" : "text"}
                value={input}
                onChange={(event) => setInput(event.target.value)}
                autoComplete="off"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                enterKeyHint="send"
                data-1p-ignore=""
                data-lpignore="true"
                aria-describedby={secret ? hintId : undefined}
                className={cn(
                  "min-w-0 flex-1 rounded-lg border border-border bg-background px-3 py-2 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring",
                  // A real terminal shows nothing at all for a typed password.
                  secret && "text-transparent caret-transparent",
                )}
              />
              <Button type="submit" size="sm" className="h-auto shrink-0">
                <CornerDownLeft aria-hidden="true" className="h-4 w-4" />
                Enter
              </Button>
            </div>
            {secret && (
              <p id={hintId} className="text-xs text-muted-foreground">
                Nothing appears as you type a password, not even dots. That&apos;s normal: type it
                and press Enter.
              </p>
            )}
          </form>

          <div className="flex flex-wrap gap-2">
            {state.stage === "local" && (
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => {
                  setInput(sshRehearsalCommand(state));
                  inputRef.current?.focus();
                }}
              >
                <ClipboardPaste aria-hidden="true" className="h-4 w-4" />
                Paste the ssh command
              </Button>
            )}
            <Button type="button" variant="ghost" size="sm" onClick={restart}>
              <RotateCcw aria-hidden="true" className="h-4 w-4" />
              Restart
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
