"use client";

import { useState, useCallback } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, Copy, Terminal, CheckCircle2, Server, Monitor } from "lucide-react";
import { motion, AnimatePresence } from "@/components/motion";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { cn, safeGetItem, safeSetItem } from "@/lib/utils";
import { useDetectedOS, useUserOS } from "@/lib/userPreferences";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import { springs } from "@/components/motion";

export interface CommandCardProps {
  /** The default command to display */
  command: string;
  /** Mac-specific command (if different from default) */
  macCommand?: string;
  /** Windows-specific command (if different from default) */
  windowsCommand?: string;
  /** Description text shown above the command */
  description?: string;
  /** Whether to show the "I ran this" checkbox */
  showCheckbox?: boolean;
  /** Unique ID for persisting checkbox state in localStorage */
  persistKey?: string;
  /** Callback when checkbox is checked */
  onComplete?: () => void;
  /** Where the command should be run - "vps" or "local" (your computer) */
  runLocation?: "vps" | "local";
  /** Additional class names */
  className?: string;
}

type OS = "mac" | "windows" | "linux";

type CheckedState = boolean | "indeterminate";

const COMPLETION_KEY_PREFIX = "acfs-command-";

// Query keys for TanStack Query
export const commandCompletionKeys = {
  completion: (key: string) => ["commandCompletion", key] as const,
};

function getCompletionKey(persistKey: string | undefined): string | null {
  return persistKey ? `${COMPLETION_KEY_PREFIX}${persistKey}` : null;
}

function getCompletionFromStorage(key: string | null): boolean {
  if (!key) return false;
  return safeGetItem(key) === "true";
}

function setCompletionInStorage(key: string, completed: boolean): void {
  safeSetItem(key, completed ? "true" : "false");
}

/**
 * Badge showing whether a command runs on VPS or locally
 */
function LocationBadge({ location }: { location: "vps" | "local" }) {
  if (location === "vps") {
    return (
      <div className="inline-flex items-center gap-1.5 rounded-md border border-[oklch(0.72_0.19_195/0.3)] bg-[oklch(0.72_0.19_195/0.12)] px-2 py-1 text-xs font-medium text-[oklch(0.72_0.19_195)]">
        <Server className="h-3 w-3" aria-hidden="true" />
        <span>Run on VPS</span>
      </div>
    );
  }
  return (
    <div className="inline-flex items-center gap-1.5 rounded-md border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.12)] px-2 py-1 text-xs font-medium text-[oklch(0.78_0.16_75)]">
      <Monitor className="h-3 w-3" aria-hidden="true" />
      <span>Run on your computer</span>
    </div>
  );
}

export function CommandCard({
  command,
  macCommand,
  windowsCommand,
  description,
  showCheckbox = false,
  persistKey,
  onComplete,
  runLocation,
  className,
}: CommandCardProps) {
  const [copied, setCopied] = useState(false);
  const [copyAnimation, setCopyAnimation] = useState(false);
  const queryClient = useQueryClient();

  const [storedOS] = useUserOS();
  const detectedOS = useDetectedOS();
  const os: OS = storedOS ?? detectedOS ?? "mac";
  const prefersReducedMotion = useReducedMotion();

  // Use TanStack Query for completion state
  const completionKey = getCompletionKey(persistKey);

  const { data: completed = false } = useQuery({
    queryKey: completionKey ? commandCompletionKeys.completion(completionKey) : ["disabled"],
    queryFn: () => getCompletionFromStorage(completionKey),
    enabled: !!completionKey,
    staleTime: Infinity,
    gcTime: Infinity,
  });

  const completionMutation = useMutation({
    mutationFn: async (isChecked: boolean) => {
      if (completionKey) {
        setCompletionInStorage(completionKey, isChecked);
      }
      return isChecked;
    },
    onSuccess: (isChecked) => {
      if (completionKey) {
        queryClient.setQueryData(commandCompletionKeys.completion(completionKey), isChecked);
      }
      if (isChecked && onComplete) {
        onComplete();
      }
    },
  });

  // Get the appropriate command for the current OS
  const displayCommand = (() => {
    if (os === "mac" && macCommand) return macCommand;
    if (os === "windows" && windowsCommand) return windowsCommand;
    return command;
  })();

  const handleCopy = useCallback(async () => {
    setCopyAnimation(true);
    try {
      await navigator.clipboard.writeText(displayCommand);
      setCopied(true);
      setTimeout(() => {
        setCopied(false);
        setCopyAnimation(false);
      }, 2000);
    } catch {
      // Fallback for older browsers
      const textarea = document.createElement("textarea");
      textarea.value = displayCommand;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => {
        setCopied(false);
        setCopyAnimation(false);
      }, 2000);
    }
  }, [displayCommand]);

  const handleCheckboxChange = useCallback(
    (checked: CheckedState) => {
      const isChecked = checked === true;
      completionMutation.mutate(isChecked);
    },
    [completionMutation]
  );

  return (
    <div
      className={cn(
        "group overflow-hidden rounded-xl border border-border/50 bg-card/50 backdrop-blur-sm transition-all duration-300",
        completed && "border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.05)]",
        !completed && "hover:border-primary/30 hover:shadow-lg hover:shadow-primary/5",
        className
      )}
    >
      {/* Description and Location Badge */}
      {(description || runLocation) && (
        <div className="border-b border-border/30 px-4 py-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            {description && (
              <p className="text-sm text-muted-foreground">{description}</p>
            )}
            {runLocation && <LocationBadge location={runLocation} />}
          </div>
        </div>
      )}

      {/* Command area */}
      <div className="relative flex items-stretch min-h-[52px]">
        {/* Terminal icon */}
        <div className="flex items-center justify-center border-r border-border/30 bg-muted/30 px-4">
          <Terminal className="h-4 w-4 text-primary" />
        </div>

        {/* Command text with scroll fade indicators */}
        <div className="relative flex-1 overflow-hidden">
          <div className="flex items-center overflow-x-auto px-4 py-3 scrollbar-hide">
            <code className="whitespace-nowrap font-mono text-sm text-foreground">
              {displayCommand}
            </code>
          </div>
          {/* Left fade indicator */}
          <div className="pointer-events-none absolute inset-y-0 left-0 w-6 bg-gradient-to-r from-card/80 to-transparent" />
          {/* Right fade indicator */}
          <div className="pointer-events-none absolute inset-y-0 right-0 w-6 bg-gradient-to-l from-card/80 to-transparent" />
        </div>

        {/* Copy button - 52px touch target */}
        <motion.div
          className="shrink-0"
          whileTap={{ scale: 0.95 }}
          transition={springs.snappy}
        >
          <Button
            variant="ghost"
            size="icon"
            className={cn(
              "h-[52px] w-14 rounded-none border-l border-border/30",
              copied && "bg-[oklch(0.72_0.19_145/0.1)] text-[oklch(0.72_0.19_145)]"
            )}
            onClick={handleCopy}
            aria-label={copied ? "Copied!" : "Copy command"}
            disableMotion
          >
            <AnimatePresence mode="wait">
              {copied ? (
                <motion.div
                  key="check"
                  initial={{ scale: 0, rotate: -45 }}
                  animate={{ scale: 1, rotate: 0 }}
                  exit={{ scale: 0, rotate: 45 }}
                  transition={springs.snappy}
                >
                  <Check className="h-4 w-4" />
                </motion.div>
              ) : (
                <motion.div
                  key="copy"
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  exit={{ scale: 0 }}
                  transition={springs.snappy}
                >
                  <Copy className="h-4 w-4" />
                </motion.div>
              )}
            </AnimatePresence>
          </Button>
        </motion.div>

        {/* Shimmer effect on copy - respects reduced motion preference */}
        <AnimatePresence>
          {copyAnimation && !prefersReducedMotion && (
            <motion.div
              className="pointer-events-none absolute inset-0 bg-gradient-to-r from-transparent via-primary/20 to-transparent"
              initial={{ x: "-100%" }}
              animate={{ x: "100%" }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.5, ease: "easeOut" }}
            />
          )}
        </AnimatePresence>
      </div>

      {/* Checkbox area */}
      {showCheckbox && (
        <div
          className={cn(
            "flex items-center gap-3 border-t border-border/30 px-4 py-3 transition-colors",
            completed && "bg-[oklch(0.72_0.19_145/0.05)]"
          )}
        >
          <Checkbox
            id={persistKey || "command-completed"}
            checked={completed}
            onCheckedChange={handleCheckboxChange}
            className={cn(
              "transition-all",
              completed && "border-[oklch(0.72_0.19_145)] bg-[oklch(0.72_0.19_145)] text-[oklch(0.15_0.02_145)]"
            )}
          />
          <label
            htmlFor={persistKey || "command-completed"}
            className={cn(
              "flex cursor-pointer items-center gap-2 text-sm transition-colors",
              completed ? "text-[oklch(0.72_0.19_145)]" : "text-muted-foreground hover:text-foreground"
            )}
          >
            {completed ? (
              <>
                <CheckCircle2 className="h-4 w-4" />
                <span>Command completed</span>
              </>
            ) : (
              <span>I ran this command</span>
            )}
          </label>
        </div>
      )}
    </div>
  );
}

/**
 * A variant of CommandCard specifically for displaying multi-line code blocks
 */
export function CodeBlock({
  code,
  language = "bash",
  className,
}: {
  code: string;
  language?: string;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      const textarea = document.createElement("textarea");
      textarea.value = code;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [code]);

  return (
    <div
      className={cn(
        "group relative overflow-hidden rounded-xl border border-border/50 bg-[oklch(0.08_0.015_260)]",
        className
      )}
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-border/30 bg-muted/20 px-4 py-2">
        <span className="font-mono text-xs text-muted-foreground">{language}</span>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 gap-1.5 px-2 text-xs text-muted-foreground hover:text-foreground"
          onClick={handleCopy}
        >
          {copied ? (
            <>
              <Check className="h-3 w-3 text-[oklch(0.72_0.19_145)]" />
              <span className="text-[oklch(0.72_0.19_145)]">Copied</span>
            </>
          ) : (
            <>
              <Copy className="h-3 w-3" />
              <span>Copy</span>
            </>
          )}
        </Button>
      </div>

      {/* Code content */}
      <pre className="overflow-x-auto p-4">
        <code className="font-mono text-sm leading-relaxed text-foreground">
          {code}
        </code>
      </pre>
    </div>
  );
}
