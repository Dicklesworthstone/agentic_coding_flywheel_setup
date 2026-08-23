"use client";

import { useCallback, useState } from "react";
import { Check, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Terminal-style command card with a copy button and transient "copied"
 * feedback. Used for the ACFS install one-liner on the Omarchy page.
 */
export default function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard unavailable (permissions/insecure context) — leave state untouched
    }
  }, [command]);

  return (
    <div className="terminal-window w-full max-w-2xl text-left shadow-2xl">
      <div className="terminal-header">
        <div className="terminal-dot terminal-dot-red" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-yellow" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-green" aria-hidden="true" />
        <span className="ml-3 font-mono text-xs text-muted-foreground">omarchy ~</span>
      </div>
      <div className="flex items-center gap-3 p-5">
        <code className="min-w-0 flex-1 overflow-x-auto font-mono text-sm whitespace-nowrap">
          <span className="mr-2 select-none text-[#9ece6a]">$</span>
          {command}
        </code>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={copy}
          className="shrink-0 border-[#9ece6a]/40 hover:bg-[#9ece6a]/10"
          aria-label={copied ? "Copied to clipboard" : "Copy install command"}
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
      </div>
    </div>
  );
}
