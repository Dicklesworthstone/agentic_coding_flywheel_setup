"use client";

import { useRef, type ReactNode, type RefObject } from "react";
import { Copy, Check, Terminal } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  COPY_FAILURE_MESSAGE,
  COPY_SUCCESS_MESSAGE,
  useCopyFeedback,
  type CopyFeedbackState,
  type CopyOptions,
} from "@/lib/hooks/useCopyFeedback";

// =============================================================================
// COPY-TO-CLIPBOARD HOOK (compat wrapper over lib/hooks/useCopyFeedback)
// =============================================================================

function useCopyToClipboard(resetMs = 2000) {
  const feedback = useCopyFeedback({ resetMs });
  return {
    copied: feedback.copied,
    failed: feedback.failed,
    state: feedback.state,
    copy: feedback.copy,
  } as const;
}

// =============================================================================
// COPY STATUS — live region shared by every copy affordance
// =============================================================================

/**
 * A single always-mounted `role="status"` live region so screen readers hear
 * "Copied to clipboard", and sighted visitors SEE the failure instruction
 * (the button alone cannot tell them the clipboard was refused).
 */
function CopyStatus({
  state,
  className,
}: {
  state: CopyFeedbackState;
  className?: string;
}) {
  const failed = state === "failed";
  return (
    <span
      role="status"
      aria-live="polite"
      className={cn(
        failed
          ? cn("block text-xs font-medium text-destructive", className)
          : "sr-only",
      )}
    >
      {state === "copied" ? COPY_SUCCESS_MESSAGE : failed ? COPY_FAILURE_MESSAGE : ""}
    </span>
  );
}

// =============================================================================
// COPY BUTTON
// =============================================================================

interface CopyButtonProps {
  text: string;
  className?: string;
  compact?: boolean;
  /**
   * Controlled mode: the parent owns `useCopyFeedback` (so it can place the
   * status message and select the code element on failure). When omitted the
   * button runs its own feedback state and renders its own status region.
   */
  state?: CopyFeedbackState;
  onCopy?: () => void;
  /** Element to select when the copy fails (uncontrolled mode only). */
  selectOnFailureRef?: RefObject<HTMLElement | null>;
}

function CopyButton({
  text,
  className,
  compact = false,
  state: controlledState,
  onCopy,
  selectOnFailureRef,
}: CopyButtonProps) {
  const own = useCopyToClipboard();
  const controlled = controlledState !== undefined;
  const state = controlled ? controlledState : own.state;
  const copied = state === "copied";

  const handleClick = () => {
    if (onCopy) {
      onCopy();
      return;
    }
    const options: CopyOptions = { selectOnFailure: selectOnFailureRef?.current ?? null };
    void own.copy(text, options);
  };

  const button = (
    <button
      type="button"
      onClick={handleClick}
      aria-label={copied ? "Copied!" : "Copy to clipboard"}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg text-xs font-medium",
        "transition duration-200",
        // Minimum touch target for mobile (44px in both variants)
        compact
          ? "min-h-[44px] min-w-[44px] justify-center p-2 text-muted-foreground hover:text-foreground hover:bg-muted active:scale-95"
          : "min-h-11 px-3 py-2 text-white/60 hover:text-white hover:bg-white/10 active:scale-95",
        // Focus ring for keyboard navigation
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        className,
      )}
    >
      {copied ? (
        <>
          <Check
            className={cn(
              "h-4 w-4",
              compact ? "text-green" : "text-emerald-400",
            )}
          />
          {!compact && <span className="text-emerald-400">Copied!</span>}
        </>
      ) : (
        <>
          <Copy className="h-4 w-4" />
          {!compact && <span>Copy</span>}
        </>
      )}
    </button>
  );

  if (controlled) {
    return button;
  }

  return (
    <>
      {button}
      <CopyStatus state={own.state} className="mt-1" />
    </>
  );
}

// =============================================================================
// CODE BLOCK - Two variants: "terminal" (dark, with header) and "compact" (inline-block)
// =============================================================================

export interface CodeBlockProps {
  /** The code/command text to display */
  code: string;
  /** Programming language label (shown in terminal header) */
  language?: string;
  /** Filename to display instead of language label */
  filename?: string;
  /** Show line numbers */
  showLineNumbers?: boolean;
  /** Visual variant: "terminal" for full dark block, "compact" for inline muted block */
  variant?: "terminal" | "compact";
  /** Whether to show the copy button (defaults to true) */
  copyable?: boolean;
  /** Additional className */
  className?: string;
  /** Optional children to render instead of code prop (for compact variant) */
  children?: ReactNode;
}

export function CodeBlock({
  code,
  language = "bash",
  filename,
  showLineNumbers = false,
  variant = "terminal",
  copyable = true,
  className,
  children,
}: CodeBlockProps) {
  const displayCode = code.trim();
  const codeRef = useRef<HTMLElement | null>(null);
  const { state, copy } = useCopyFeedback();
  const handleCopy = () => {
    void copy(displayCode, { selectOnFailure: codeRef.current });
  };

  if (variant === "compact") {
    return (
      <div className={cn("group relative w-full", className)}>
        <code
          ref={codeRef}
          className="block w-full overflow-x-auto rounded-lg bg-muted px-3 py-2 pr-12 font-mono text-sm"
        >
          {children ?? displayCode}
        </code>
        {copyable && (
          // Hidden until hover, but touch devices never hover: reveal there
          // unconditionally (same rule as the terminal header button).
          <div className="absolute right-1 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-within:opacity-100 [@media(hover:none)]:opacity-100 transition-opacity">
            <CopyButton text={displayCode} compact state={state} onCopy={handleCopy} />
          </div>
        )}
        {copyable && <CopyStatus state={state} className="mt-1" />}
      </div>
    );
  }

  // Terminal variant
  const lines = displayCode.split("\n");

  return (
    <div
      className={cn(
        "group relative rounded-xl border border-white/10 bg-[#09090b] overflow-hidden shadow-2xl transition duration-500 hover:border-white/20 hover:shadow-[0_0_30px_-5px_rgba(34,211,238,0.15)] ring-1 ring-inset ring-white/5",
        className,
      )}
    >
      {/* Noise Texture */}
      <div className="absolute inset-0 bg-noise opacity-[0.03] pointer-events-none mix-blend-overlay" />

      {/* Terminal header */}
      <div className="relative z-10 flex items-center justify-between px-4 py-2 border-b border-white/10 bg-[#1a1b1e]/80 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#ff5f56] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
            <div className="w-3 h-3 rounded-full bg-[#ffbd2e] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
            <div className="w-3 h-3 rounded-full bg-[#27c93f] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
          </div>
          {filename ? (
            <span className="ml-2 text-xs text-white/50 font-mono tracking-wide">{filename}</span>
          ) : (
            <div className="ml-2 flex items-center gap-1.5 text-white/50">
              <Terminal className="h-3.5 w-3.5" />
              <span className="text-xs font-mono tracking-wide">{language}</span>
            </div>
          )}
        </div>
        {/* Hidden until hover, but a keyboard user must be able to see what
            they focused: reveal on focus-visible and on touch (no hover). */}
        {copyable && (
          <CopyButton
            text={displayCode}
            state={state}
            onCopy={handleCopy}
            className="opacity-0 group-hover:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-100 transition-opacity bg-white/10 border border-white/5 text-white hover:bg-white/20"
          />
        )}
      </div>

      {/* Code content (focusable so long lines can be panned by keyboard) */}
      <div
        className="relative z-10 p-5 overflow-x-auto outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-cyan-400/60"
        tabIndex={0}
      >
        {/* overflow-visible: the focusable wrapper above is the one scroll
            region; globals.css otherwise makes every <pre> scroll on its own,
            nesting a second, non-focusable scroller. */}
        <pre
          ref={codeRef as RefObject<HTMLPreElement | null>}
          className="overflow-visible font-mono text-[0.85rem] leading-[1.7] selection:bg-cyan-900/40 selection:text-white"
        >
          {lines.map((line, i) => (
            <div
              key={i}
              className={cn(
                "flex -mx-5 px-5 transition-colors duration-150",
                // Line highlight on hover for better readability
                "hover:bg-white/[0.03]"
              )}
            >
              {showLineNumbers && (
                <span className="select-none w-8 text-white/20 text-right pr-4 shrink-0">
                  {i + 1}
                </span>
              )}
              <code className="text-[#a1a1aa]">
                {line.startsWith("$") ? (
                  <>
                    <span className="text-cyan-400 font-semibold">$</span>
                    <span className="text-white/90">{line.slice(1)}</span>
                  </>
                ) : line.startsWith("#") ? (
                  <span className="text-white/40 italic">{line}</span>
                ) : (
                  line
                )}
              </code>
            </div>
          ))}
        </pre>
      </div>

      {/* Visible only on failure; announced on success. Lives on the dark
          island so it stays readable in both themes. */}
      {copyable && (
        <CopyStatus
          state={state}
          className="relative z-10 border-t border-white/10 px-5 py-2 text-red-300"
        />
      )}
    </div>
  );
}

// =============================================================================
// RE-EXPORT CopyButton / CopyStatus for use in custom layouts
// =============================================================================
export { CopyButton, CopyStatus, useCopyToClipboard };
