"use client";

import { useState, useCallback, useEffect, useRef, type ReactNode } from "react";
import { Copy, Check, Terminal } from "lucide-react";
import { cn, copyTextToClipboard } from "@/lib/utils";

// =============================================================================
// COPY-TO-CLIPBOARD HOOK
// =============================================================================

function useCopyToClipboard(resetMs = 2000) {
  const [copied, setCopied] = useState(false);
  const resetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (resetTimerRef.current) {
        clearTimeout(resetTimerRef.current);
      }
    };
  }, []);

  const copy = useCallback(
    async (text: string) => {
      const copiedOk = await copyTextToClipboard(text);
      if (!copiedOk) {
        return;
      }

      setCopied(true);
      if (resetTimerRef.current) {
        clearTimeout(resetTimerRef.current);
      }
      resetTimerRef.current = setTimeout(() => {
        setCopied(false);
        resetTimerRef.current = null;
      }, resetMs);
    },
    [resetMs],
  );

  return { copied, copy } as const;
}

// =============================================================================
// COPY BUTTON
// =============================================================================

function CopyButton({
  text,
  className,
  compact = false,
}: {
  text: string;
  className?: string;
  compact?: boolean;
}) {
  const { copied, copy } = useCopyToClipboard();

  return (
    <button
      type="button"
      onClick={() => copy(text)}
      aria-label={copied ? "Copied!" : "Copy to clipboard"}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg text-xs font-medium",
        "transition duration-200",
        // Minimum touch target for mobile (44px when compact)
        compact
          ? "min-h-[44px] min-w-[44px] justify-center p-2 text-muted-foreground hover:text-foreground hover:bg-muted active:scale-95"
          : "px-3 py-2 text-white/60 hover:text-white hover:bg-white/10 active:scale-95",
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
              compact ? "text-[oklch(0.72_0.19_145)]" : "text-emerald-400",
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

  if (variant === "compact") {
    return (
      <div className={cn("group relative inline-flex w-full", className)}>
        <code className="block w-full overflow-x-auto rounded-lg bg-muted px-3 py-2 pr-10 font-mono text-sm">
          {children ?? displayCode}
        </code>
        {copyable && (
          <div className="absolute right-1 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity">
            <CopyButton text={displayCode} compact />
          </div>
        )}
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
      <div className="relative z-10 flex items-center justify-between px-4 py-3 border-b border-white/10 bg-[#1a1b1e]/80 backdrop-blur-md">
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
        {copyable && <CopyButton text={displayCode} className="opacity-0 group-hover:opacity-100 transition-opacity bg-white/10 border border-white/5 text-white hover:bg-white/20" />}
      </div>

      {/* Code content */}
      <div className="relative z-10 p-5 overflow-x-auto">
        <pre className="font-mono text-[0.85rem] leading-[1.7] selection:bg-cyan-900/40 selection:text-white">
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
    </div>
  );
}

// =============================================================================
// RE-EXPORT CopyButton for use in custom layouts
// =============================================================================
export { CopyButton, useCopyToClipboard };
