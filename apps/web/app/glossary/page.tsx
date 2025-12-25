"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { BookOpen, ChevronDown, Home, Search, Terminal, X } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { jargonDictionary } from "@/lib/jargon";
import { cn } from "@/lib/utils";

type GlossaryCategory = "all" | "shell" | "networking" | "tools" | "concepts";

const CATEGORY_LABELS: Record<GlossaryCategory, string> = {
  all: "All",
  shell: "Shell",
  networking: "Networking",
  tools: "Tools",
  concepts: "Concepts",
};

const CATEGORY_ORDER: GlossaryCategory[] = [
  "all",
  "networking",
  "shell",
  "tools",
  "concepts",
];

type LearnMoreLink = {
  href: string;
  label: string;
};

const LEARN_MORE: Partial<Record<string, LearnMoreLink>> = {
  ssh: { href: "/learn/ssh-basics", label: "Learn: SSH basics" },
  "ssh-key": { href: "/wizard/generate-ssh-key", label: "Wizard: Generate SSH key" },
  vps: { href: "/wizard/rent-vps", label: "Wizard: Rent a VPS" },
  tmux: { href: "/learn/tmux-basics", label: "Learn: tmux basics" },
  ntm: { href: "/learn/ntm-core", label: "Learn: NTM command center" },
  "agent-mail": { href: "/learn/flywheel-loop", label: "Learn: The flywheel loop" },
  beads: { href: "/learn/flywheel-loop", label: "Learn: The flywheel loop" },
  codex: { href: "/learn/agent-commands", label: "Learn: Agent commands" },
  "claude-code": { href: "/learn/agent-commands", label: "Learn: Agent commands" },
  "gemini-cli": { href: "/learn/agent-commands", label: "Learn: Agent commands" },
};

type GlossaryEntry = {
  key: string;
  category: Exclude<GlossaryCategory, "all">;
  term: string;
  short: string;
  long: string;
  analogy?: string;
  why?: string;
  related?: string[];
  learnMore?: LearnMoreLink;
  searchable: string;
};

function categorizeKey(key: string): Exclude<GlossaryCategory, "all"> {
  const k = key.toLowerCase();

  if (
    /(ssh|vps|ip-address|hostname|port|tailscale|dns|firewall|fingerprint)/.test(k)
  ) {
    return "networking";
  }

  if (
    /(terminal|command-line|shell|zsh|bash|oh-my-zsh|p10k|powerlevel10k|alias|path|env|tmux|session|zoxide|atuin|fzf)/.test(
      k
    )
  ) {
    return "shell";
  }

  if (
    /(git|github|repo|repository|clone|branch|commit|pull-request)/.test(k) ||
    /(bun|uv|rust|cargo|go|docker|wrangler|supabase|convex|vercel|vault|jq|rg|ripgrep|lazygit|ast-grep)/.test(k)
  ) {
    return "tools";
  }

  return "concepts";
}

function buildSearchable(entry: Omit<GlossaryEntry, "searchable">): string {
  return [
    entry.key,
    entry.term,
    entry.short,
    entry.long,
    entry.analogy ?? "",
    entry.why ?? "",
    ...(entry.related ?? []),
  ]
    .join(" ")
    .toLowerCase();
}

export default function GlossaryPage() {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<GlossaryCategory>("all");

  const entries = useMemo<GlossaryEntry[]>(() => {
    const all: GlossaryEntry[] = Object.entries(jargonDictionary).map(
      ([key, value]) => {
        const base: Omit<GlossaryEntry, "searchable"> = {
          key,
          category: categorizeKey(key),
          term: value.term,
          short: value.short,
          long: value.long,
          analogy: value.analogy,
          why: value.why,
          related: value.related,
          learnMore: LEARN_MORE[key],
        };
        return { ...base, searchable: buildSearchable(base) };
      }
    );

    all.sort((a, b) =>
      a.term.localeCompare(b.term, undefined, { sensitivity: "base" })
    );

    return all;
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return entries.filter((entry) => {
      if (category !== "all" && entry.category !== category) {
        return false;
      }
      if (q.length === 0) return true;
      return entry.searchable.includes(q);
    });
  }, [entries, query, category]);

  const clearQuery = useCallback(() => setQuery(""), []);

  // If the user lands on /glossary#some-key, scroll to it and open the entry.
  useEffect(() => {
    const openFromHash = () => {
      const raw = window.location.hash.replace(/^#/, "");
      if (!raw) return;

      const key = decodeURIComponent(raw);
      const target = document.getElementById(key);
      if (!target) return;

      // Open the <details> element if the id is set on the wrapper.
      if (target instanceof HTMLDetailsElement) {
        target.open = true;
      } else {
        const details = target.closest("details");
        if (details) details.open = true;
      }

      target.scrollIntoView({ behavior: "smooth", block: "start" });
    };

    openFromHash();
    window.addEventListener("hashchange", openFromHash);
    return () => window.removeEventListener("hashchange", openFromHash);
  }, []);

  return (
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      <div className="relative mx-auto max-w-5xl px-6 py-8 md:px-12 md:py-12">
        {/* Header */}
        <div className="mb-8 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Home className="h-4 w-4" />
            <span className="text-sm">Home</span>
          </Link>
          <Link
            href="/wizard/os-selection"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Terminal className="h-4 w-4" />
            <span className="text-sm">Setup Wizard</span>
          </Link>
        </div>

        {/* Hero */}
        <div className="mb-10 text-center">
          <div className="mb-4 flex justify-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 shadow-lg shadow-primary/20">
              <BookOpen className="h-8 w-8 text-primary" />
            </div>
          </div>
          <h1 className="mb-3 text-3xl font-bold tracking-tight md:text-4xl">
            Glossary
          </h1>
          <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
            Search and browse plain‑English definitions for terms you see in the
            wizard and learning hub.
          </p>
          <p className="mt-3 text-sm text-muted-foreground">
            Tip: Many{" "}
            <span className="decoration-primary/40 decoration-dotted underline underline-offset-4">
              dotted‑underline
            </span>{" "}
            terms link here from the tooltip.
          </p>
        </div>

        {/* Search + filters */}
        <Card className="mb-8 border-border/50 bg-card/60 p-5">
          <div className="flex flex-col gap-4 md:flex-row md:items-center">
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search terms (e.g., SSH, tmux, API key)…"
                className="w-full rounded-xl border border-border/50 bg-background px-9 py-2 text-sm outline-none transition-colors focus:border-primary/50 focus:ring-2 focus:ring-primary/20"
              />
              {query.length > 0 && (
                <button
                  type="button"
                  onClick={clearQuery}
                  className="absolute right-2 top-1/2 flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted/40 hover:text-foreground"
                  aria-label="Clear search"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>

            <div className="flex flex-wrap gap-2">
              {CATEGORY_ORDER.map((cat) => (
                <Button
                  key={cat}
                  size="sm"
                  variant={category === cat ? "default" : "outline"}
                  onClick={() => setCategory(cat)}
                  disableMotion
                >
                  {CATEGORY_LABELS[cat]}
                </Button>
              ))}
            </div>
          </div>

          <div className="mt-4 text-sm text-muted-foreground">
            Showing <span className="font-medium text-foreground">{filtered.length}</span>{" "}
            of{" "}
            <span className="font-medium text-foreground">{entries.length}</span>{" "}
            terms
          </div>
        </Card>

        {/* Results */}
        <div className="space-y-3">
          {filtered.length === 0 ? (
            <Card className="border-border/50 bg-card/60 p-6 text-center">
              <p className="text-sm text-muted-foreground">
                No matches. Try a different search or switch back to{" "}
                <span className="font-medium text-foreground">All</span>.
              </p>
            </Card>
          ) : (
            filtered.map((entry) => (
              <details
                key={entry.key}
                id={entry.key}
                className="group overflow-hidden rounded-2xl border border-border/50 bg-card/60"
              >
                <summary className="flex cursor-pointer list-none items-start justify-between gap-4 p-5 transition-colors hover:bg-muted/20">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <h2 className="text-lg font-semibold text-foreground">
                        {entry.term}
                      </h2>
                      <span className="rounded-full border border-border/60 bg-muted/30 px-2 py-0.5 text-[11px] text-muted-foreground">
                        #{entry.key}
                      </span>
                      <span className="rounded-full border border-border/60 bg-muted/30 px-2 py-0.5 text-[11px] text-muted-foreground">
                        {CATEGORY_LABELS[entry.category]}
                      </span>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {entry.short}
                    </p>
                  </div>
                  <ChevronDown className="mt-1 h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
                </summary>

                <div className="space-y-4 border-t border-border/40 p-5">
                  <div>
                    <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
                      What it means
                    </h3>
                    <p className="mt-2 text-sm leading-relaxed text-foreground">
                      {entry.long}
                    </p>
                  </div>

                  {entry.why && (
                    <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4">
                      <p className="mb-1 text-xs font-bold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">
                        Why we use it
                      </p>
                      <p className="text-sm leading-relaxed text-foreground">
                        {entry.why}
                      </p>
                    </div>
                  )}

                  {entry.analogy && (
                    <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
                      <p className="mb-1 text-xs font-bold uppercase tracking-wider text-primary">
                        Think of it like…
                      </p>
                      <p className="text-sm leading-relaxed text-foreground">
                        {entry.analogy}
                      </p>
                    </div>
                  )}

                  {(entry.related?.length ?? 0) > 0 && (
                    <div>
                      <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
                        Related terms
                      </h3>
                      <div className="mt-2 flex flex-wrap gap-2">
                        {entry.related!.map((key) => (
                          <Link
                            key={key}
                            href={`/glossary#${encodeURIComponent(key)}`}
                            className="rounded-full border border-border/60 bg-muted/30 px-3 py-1 text-xs font-medium text-muted-foreground hover:border-primary/40 hover:text-foreground"
                          >
                            {key}
                          </Link>
                        ))}
                      </div>
                    </div>
                  )}

                  {entry.learnMore && (
                    <div className="pt-1">
                      <Link
                        href={entry.learnMore.href}
                        className={cn(
                          "text-sm font-medium text-primary underline-offset-4 hover:underline",
                          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm"
                        )}
                      >
                        {entry.learnMore.label} →
                      </Link>
                    </div>
                  )}
                </div>
              </details>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
