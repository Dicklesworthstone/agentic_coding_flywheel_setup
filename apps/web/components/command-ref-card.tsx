"use client";

import { useState, useCallback } from "react";
import Link from "next/link";
import { Check, Copy, Terminal } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { CommandRef } from "@/lib/commands";

interface CommandRefCardProps {
  command: CommandRef;
  categoryLabel: string;
}

export function CommandRefCard({ command, categoryLabel }: CommandRefCardProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(command.name);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = command.name;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [command.name]);

  return (
    <Card
      id={command.name}
      className="group relative overflow-hidden border-border/50 bg-card/50 p-5 backdrop-blur-sm transition-all hover:border-primary/30 hover:shadow-lg hover:shadow-primary/5"
    >
      <div className="flex flex-col gap-4">
        <div className="flex items-start justify-between gap-4">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center gap-1 rounded-full border border-border/50 bg-muted/40 px-2.5 py-1 text-xs text-muted-foreground">
                {categoryLabel}
              </span>
              {command.aliases && command.aliases.length > 0 ? (
                <span className="text-xs text-muted-foreground">
                  aliases: {command.aliases.join(", ")}
                </span>
              ) : null}
            </div>
            <div className="flex items-center gap-2">
              <Terminal className="h-4 w-4 text-primary" />
              <h3 className="text-lg font-semibold text-foreground">
                {command.name}
              </h3>
              <span className="text-sm text-muted-foreground">
                {command.fullName}
              </span>
            </div>
            <p className="text-sm text-muted-foreground">
              {command.description}
            </p>
          </div>

          <Button
            variant="ghost"
            size="icon"
            className={cn(
              "h-9 w-9 shrink-0",
              copied &&
                "bg-[oklch(0.72_0.19_145/0.1)] text-[oklch(0.72_0.19_145)]"
            )}
            onClick={handleCopy}
            aria-label={copied ? "Copied!" : "Copy command"}
            disableMotion
          >
            {copied ? (
              <Check className="h-4 w-4" />
            ) : (
              <Copy className="h-4 w-4" />
            )}
          </Button>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <code className="rounded-lg border border-border/60 bg-muted/40 px-3 py-2 text-sm text-foreground">
            {command.example}
          </code>
          {command.docsUrl ? (
            <Link
              href={command.docsUrl}
              className="text-sm text-primary transition-colors hover:text-primary/80"
            >
              Full docs →
            </Link>
          ) : null}
        </div>
      </div>
    </Card>
  );
}
