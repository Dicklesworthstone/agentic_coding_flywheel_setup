"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { copyTextToClipboard } from "@/lib/utils";

/**
 * Terminal-style command card with a copy button and transient "copied"
 * feedback. Used for the ACFS install one-liner on the Omarchy page.
 *
 * The terminal chrome is always dark (it is a terminal), so every colour in
 * here is explicit rather than theme-token based — the page can be viewed in
 * the site's light theme without the text disappearing.
 */
export default function CopyCommand({
  command,
  prompt = "omarchy ~",
}: {
  command: string;
  prompt?: string;
}) {
  const [copied, setCopied] = useState(false);
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (resetTimer.current) clearTimeout(resetTimer.current);
    };
  }, []);

  const copy = useCallback(async () => {
    // Shared helper: async Clipboard API with an execCommand fallback for
    // http:// dev servers and browsers that block the permission.
    const ok = await copyTextToClipboard(command);
    if (!ok) return;
    setCopied(true);
    if (resetTimer.current) clearTimeout(resetTimer.current);
    resetTimer.current = setTimeout(() => setCopied(false), 2000);
  }, [command]);

  return (
    <div className="terminal-window w-full max-w-2xl text-left shadow-2xl ring-1 ring-[#9ece6a]/10">
      <div className="terminal-header">
        <div
          className={`terminal-dot transition-colors duration-300 ${copied ? "bg-[#9ece6a]!" : "terminal-dot-red"}`}
          aria-hidden="true"
        />
        <div className="terminal-dot terminal-dot-yellow" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-green" aria-hidden="true" />
        <span className="ml-3 font-mono text-xs text-[#a9b1d6]/70">{prompt}</span>
      </div>
      <div className="flex items-center gap-3 p-5">
        <div className="flex min-w-0 flex-1 items-baseline font-mono text-sm text-[#c0caf5]">
          <span className="mr-2 shrink-0 select-none text-[#9ece6a]" aria-hidden="true">
            $
          </span>
          <code tabIndex={0} role="region" aria-label="Install command" className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#9ece6a]/60">{command}</code>
        </div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={copy}
          className="shrink-0 border-[#9ece6a]/40 bg-transparent text-[#c0caf5] hover:bg-[#9ece6a]/10 hover:text-[#c0caf5]"
          aria-label="Copy install command"
        >
          {copied ? (
            <>
              <Check className="h-4 w-4 text-[#9ece6a]" />
              <span className="text-[#9ece6a]">Copied</span>
            </>
          ) : (
            <>
              <Copy className="h-4 w-4" />
              Copy
            </>
          )}
        </Button>
        {/* Screen readers don't announce aria-label changes; use a live region. */}
        <span role="status" aria-live="polite" className="sr-only">
          {copied ? "Install command copied to clipboard" : ""}
        </span>
      </div>
    </div>
  );
}
