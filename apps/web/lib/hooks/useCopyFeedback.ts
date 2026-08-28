"use client";

/**
 * useCopyFeedback
 *
 * Shared copy-to-clipboard state machine with an explicit failure path.
 *
 * `copyTextToClipboard` (lib/utils) returns `false` when both the async
 * Clipboard API and the `execCommand("copy")` fallback fail (non-secure
 * contexts, permission denial, some iOS/in-app WebViews). Every copy button
 * used to swallow that `false` and simply not change, so the visitor pasted
 * an empty clipboard into a root shell. This hook surfaces the three states
 * so a caller can:
 *
 *   - announce "Copied to clipboard" through a `role="status"` live region,
 *   - show a VISIBLE "Copy failed — select the command and copy it manually"
 *     message on failure, and
 *   - select the command text programmatically on failure so a plain
 *     ⌘/Ctrl+C works as the manual fallback.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { copyTextToClipboard } from "@/lib/utils";

export type CopyFeedbackState = "idle" | "copied" | "failed";

/** How long the "copied" confirmation stays before returning to idle. */
export const COPY_FEEDBACK_RESET_MS = 2000;
/**
 * How long the failure instruction stays visible. Longer than the success
 * flash on purpose: the visitor has to read it and act on it.
 */
export const COPY_FEEDBACK_FAILURE_RESET_MS = 8000;

export const COPY_SUCCESS_MESSAGE = "Copied to clipboard";
export const COPY_FAILURE_MESSAGE =
  "Copy failed — select the command and copy it manually";

export interface CopyFeedbackOptions {
  /** Reset delay after a successful copy (default 2000ms). */
  resetMs?: number;
  /** Reset delay after a failed copy (default 8000ms). */
  failureResetMs?: number;
}

export interface CopyOptions {
  /**
   * Element whose text content should be selected when the copy fails, so
   * the visitor can press ⌘/Ctrl+C. Typically the `<code>` or `<pre>` that
   * displays the command.
   */
  selectOnFailure?: HTMLElement | null;
}

export interface CopyFeedback {
  state: CopyFeedbackState;
  /** `true` while the success confirmation is showing. */
  copied: boolean;
  /** `true` while the failure instruction is showing. */
  failed: boolean;
  /**
   * Copy `text`; resolves to `true` on success once the state has been
   * updated (callers that only need the state can ignore the value).
   */
  copy: (text: string, options?: CopyOptions) => Promise<boolean>;
  /** Return to idle immediately (clears the pending reset timer). */
  reset: () => void;
}

/**
 * Select all text inside `element` so the visitor can copy it with the
 * keyboard. Returns `false` when the Selection API is unavailable.
 */
export function selectElementText(element: HTMLElement | null | undefined): boolean {
  if (!element || typeof window === "undefined") return false;
  const selection = window.getSelection?.();
  if (!selection) return false;
  try {
    selection.removeAllRanges();
    selection.selectAllChildren(element);
    return true;
  } catch {
    return false;
  }
}

export function useCopyFeedback(options: CopyFeedbackOptions = {}): CopyFeedback {
  const {
    resetMs = COPY_FEEDBACK_RESET_MS,
    failureResetMs = COPY_FEEDBACK_FAILURE_RESET_MS,
  } = options;

  const [state, setState] = useState<CopyFeedbackState>("idle");
  const resetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mountedRef = useRef(true);

  const clearResetTimer = useCallback(() => {
    if (resetTimerRef.current) {
      clearTimeout(resetTimerRef.current);
      resetTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      clearResetTimer();
    };
  }, [clearResetTimer]);

  const reset = useCallback(() => {
    clearResetTimer();
    setState("idle");
  }, [clearResetTimer]);

  const copy = useCallback(
    async (text: string, copyOptions?: CopyOptions): Promise<boolean> => {
      const copiedOk = await copyTextToClipboard(text);
      if (!mountedRef.current) return copiedOk;

      if (!copiedOk) {
        selectElementText(copyOptions?.selectOnFailure);
      }

      const nextState: CopyFeedbackState = copiedOk ? "copied" : "failed";
      setState(nextState);

      clearResetTimer();
      resetTimerRef.current = setTimeout(
        () => {
          resetTimerRef.current = null;
          if (mountedRef.current) {
            setState("idle");
          }
        },
        copiedOk ? resetMs : failureResetMs,
      );
      return copiedOk;
    },
    [clearResetTimer, failureResetMs, resetMs],
  );

  return {
    state,
    copied: state === "copied",
    failed: state === "failed",
    copy,
    reset,
  };
}
