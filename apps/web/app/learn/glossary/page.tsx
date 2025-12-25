"use client";

import Link from "next/link";
import { useMemo, useState, type ReactNode } from "react";
import { ArrowLeft, BookOpen, Home, Search, Wrench, ShieldCheck, Type, FileQuestion } from "lucide-react";
import { Card } from "@/components/ui/card";
import { getAllTerms, type JargonTerm } from "@/lib/jargon";
import { motion, springs, staggerContainer, fadeUp } from "@/components/motion";
import { useScrollReveal } from "@/lib/hooks/useScrollReveal";

type GlossaryCategory = "concepts" | "tools" | "protocols" | "acronyms";
type CategoryFilter = "all" | GlossaryCategory;

function toAnchorId(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

const TOOL_TERMS = new Set([
  "tmux",
  "zsh",
  "bash",
  "bun",
  "uv",
  "cargo",
  "rust",
  "go",
  "git",
  "gh",
  "lazygit",
  "rg",
  "ripgrep",
  "fzf",
  "direnv",
  "zoxide",
  "atuin",
  "ntm",
  "bv",
  "bd",
  "ubs",
  "cass",
  "cm",
  "caam",
  "slb",
  "vault",
  "wrangler",
  "supabase",
  "convex",
  "vercel",
  "postgres",
]);

const PROTOCOL_TERMS = new Set([
  "ssh",
  "mcp",
  "oauth",
  "jwt",
  "api",
  "http",
  "https",
  "dns",
  "tcp",
  "udp",
  "tls",
]);

function categorizeTerm(term: JargonTerm): GlossaryCategory {
  const anchor = toAnchorId(term.term);

  if (PROTOCOL_TERMS.has(anchor)) return "protocols";
  if (TOOL_TERMS.has(anchor)) return "tools";

  const plain = term.term.replace(/[^a-zA-Z0-9]/g, "");
  if (plain.length >= 2 && plain.length <= 5) {
    if (plain === plain.toUpperCase()) return "acronyms";
    if (plain === plain.toLowerCase()) return "acronyms";
    if (/[A-Z]/.test(plain) && /[a-z]/.test(plain) && plain.length <= 4) {
      return "acronyms";
    }
  }

  return "concepts";
}

function matchesQuery(term: JargonTerm, query: string): boolean {
  const haystack = `${term.term} ${term.short} ${term.long}`.toLowerCase();
  return haystack.includes(query);
}

const CATEGORY_META: Array<{
  id: GlossaryCategory;
  label: string;
  icon: ReactNode;
  description: string;
}> = [
  {
    id: "concepts",
    label: "Concepts",
    icon: <BookOpen className="h-4 w-4" />,
    description: "Core ideas and mental models",
  },
  {
    id: "tools",
    label: "Tools",
    icon: <Wrench className="h-4 w-4" />,
    description: "Programs and CLIs you’ll use",
  },
  {
    id: "protocols",
    label: "Protocols",
    icon: <ShieldCheck className="h-4 w-4" />,
    description: "How systems talk to each other",
  },
  {
    id: "acronyms",
    label: "Acronyms",
    icon: <Type className="h-4 w-4" />,
    description: "Short words you’ll see everywhere",
  },
];

function CategoryChip({
  label,
  isSelected,
  onClick,
}: {
  label: string;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      transition={springs.snappy}
      className={`min-h-[44px] rounded-full border px-4 py-2 text-sm transition-colors ${
        isSelected
          ? "border-primary/40 bg-primary/10 text-primary"
          : "border-border/50 bg-card/40 text-muted-foreground hover:border-primary/30 hover:bg-primary/5 hover:text-foreground"
      }`}
    >
      {label}
    </motion.button>
  );
}

export default function GlossaryPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [category, setCategory] = useState<CategoryFilter>("all");
  const { ref: heroRef, isInView: heroInView } = useScrollReveal({ threshold: 0.1 });
  const { ref: contentRef, isInView: contentInView } = useScrollReveal({ threshold: 0.05 });

  const allTerms = useMemo(() => {
    const terms = getAllTerms();
    return [...terms].sort((a, b) => a.term.localeCompare(b.term));
  }, []);

  const normalizedQuery = searchQuery.trim().toLowerCase();

  const filteredTerms = useMemo(() => {
    return allTerms.filter((t) => {
      if (category !== "all" && categorizeTerm(t) !== category) {
        return false;
      }
      if (!normalizedQuery) return true;
      return matchesQuery(t, normalizedQuery);
    });
  }, [allTerms, category, normalizedQuery]);

  const groupedTerms = useMemo(() => {
    const groups = new Map<string, JargonTerm[]>();

    for (const term of filteredTerms) {
      const letter = term.term.charAt(0).toUpperCase();
      const bucket = groups.get(letter);
      if (bucket) {
        bucket.push(term);
      } else {
        groups.set(letter, [term]);
      }
    }

    return [...groups.entries()]
      .map(([letter, terms]) => [letter, terms.sort((a, b) => a.term.localeCompare(b.term))] as const)
      .sort(([a], [b]) => a.localeCompare(b));
  }, [filteredTerms]);

  return (
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />
      {/* Floating orbs - hidden on mobile for performance */}
      <div className="pointer-events-none fixed -left-40 top-1/4 hidden h-80 w-80 rounded-full bg-[oklch(0.75_0.18_195/0.08)] blur-[100px] sm:block" />
      <div className="pointer-events-none fixed -right-40 bottom-1/3 hidden h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[100px] sm:block" />

      <div className="relative mx-auto max-w-4xl px-6 py-8 md:px-12 md:py-12">
        {/* Header - 48px touch targets */}
        <div className="mb-8 flex items-center justify-between">
          <Link
            href="/learn"
            className="flex min-h-[48px] items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm">Learning Hub</span>
          </Link>
          <Link
            href="/"
            className="flex min-h-[48px] items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Home className="h-4 w-4" />
            <span className="text-sm">Home</span>
          </Link>
        </div>

        {/* Hero with animation */}
        <motion.div
          ref={heroRef as React.RefObject<HTMLDivElement>}
          className="mb-10 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={heroInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          <motion.div
            className="mb-4 flex justify-center"
            whileHover={{ scale: 1.05, rotate: 5 }}
            transition={springs.snappy}
          >
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 shadow-lg shadow-primary/20">
              <BookOpen className="h-8 w-8 text-primary" />
            </div>
          </motion.div>
          <h1 className="mb-3 text-3xl font-bold tracking-tight md:text-4xl">
            Glossary
          </h1>
          <p className="mx-auto max-w-xl text-lg text-muted-foreground">
            Every term used throughout ACFS, explained in plain English.
          </p>
        </motion.div>

        {/* Search */}
        <div className="relative mb-6">
          <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search terms..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-xl border border-border/50 bg-card/50 py-3 pl-12 pr-4 text-foreground placeholder:text-muted-foreground focus:border-primary/40 focus:outline-none focus:ring-2 focus:ring-primary/20"
          />
        </div>

        {/* Category filter */}
        <div className="mb-6 flex flex-wrap gap-2">
          <CategoryChip
            label="All"
            isSelected={category === "all"}
            onClick={() => setCategory("all")}
          />
          {CATEGORY_META.map((c) => (
            <CategoryChip
              key={c.id}
              label={c.label}
              isSelected={category === c.id}
              onClick={() => setCategory(c.id)}
            />
          ))}
        </div>

        <p className="mb-8 text-sm text-muted-foreground">
          Showing{" "}
          <span className="font-mono text-foreground">
            {filteredTerms.length}
          </span>{" "}
          of{" "}
          <span className="font-mono text-foreground">{allTerms.length}</span>{" "}
          terms.
        </p>

        {/* Terms with animation */}
        <motion.div
          ref={contentRef as React.RefObject<HTMLDivElement>}
          className="space-y-4"
          initial="hidden"
          animate={contentInView ? "visible" : "hidden"}
          variants={staggerContainer}
        >
          {filteredTerms.length > 0 ? (
            groupedTerms.map(([letter, terms]) => (
              <div key={letter} className="space-y-4">
                <motion.div
                  className="sticky top-16 z-10 rounded-xl border border-border/50 bg-background/70 px-4 py-2 backdrop-blur-sm"
                  variants={fadeUp}
                >
                  <span className="font-mono text-sm font-bold text-primary">
                    {letter}
                  </span>
                </motion.div>
                {terms.map((term) => {
                  const anchorId = toAnchorId(term.term);
                  const inferredCategory = categorizeTerm(term);
                  const categoryMeta = CATEGORY_META.find((c) => c.id === inferredCategory);

                  return (
                    <motion.div
                      key={term.term}
                      variants={fadeUp}
                      whileHover={{ y: -2, boxShadow: "0 10px 30px -10px oklch(0.75 0.18 195 / 0.1)" }}
                      transition={springs.snappy}
                    >
                      <Card
                        id={anchorId}
                        className="border-border/50 bg-card/50 p-5 backdrop-blur-sm scroll-mt-28 transition-colors hover:border-primary/20"
                      >
                      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <h2 className="font-mono text-lg font-bold text-foreground">
                              {term.term}
                            </h2>
                            {categoryMeta && (
                              <span className="inline-flex items-center gap-1 rounded-full border border-border/50 bg-muted/30 px-2 py-0.5 text-xs text-muted-foreground">
                                {categoryMeta.icon}
                                {categoryMeta.label}
                              </span>
                            )}
                          </div>
                          <p className="mt-1 text-sm text-muted-foreground">
                            {term.short}
                          </p>
                        </div>
                        <Link
                          href={`#${anchorId}`}
                          className="text-xs text-muted-foreground hover:text-foreground"
                        >
                          #{anchorId}
                        </Link>
                      </div>

                      <details className="mt-4">
                        <summary className="cursor-pointer text-sm font-medium text-primary/90">
                          Read more
                        </summary>
                        <div className="mt-3 space-y-4 text-sm leading-relaxed text-muted-foreground">
                          <p>{term.long}</p>

                          {term.analogy && (
                            <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
                              <p className="mb-1 font-medium text-foreground">
                                Think of it like…
                              </p>
                              <p>{term.analogy}</p>
                            </div>
                          )}

                          {term.why && (
                            <div className="rounded-xl border border-border/40 bg-muted/30 p-4">
                              <p className="mb-1 font-medium text-foreground">
                                Why it matters
                              </p>
                              <p>{term.why}</p>
                            </div>
                          )}

                          {term.related && term.related.length > 0 && (
                            <div>
                              <p className="mb-2 font-medium text-foreground">
                                Related
                              </p>
                              <div className="flex flex-wrap gap-2">
                                {term.related.map((related) => {
                                  const relatedAnchor = toAnchorId(related);
                                  return (
                                    <Link
                                      key={related}
                                      href={`#${relatedAnchor}`}
                                      className="rounded-full border border-border/50 bg-card/40 px-3 py-1 text-xs text-muted-foreground hover:border-primary/30 hover:bg-primary/5 hover:text-foreground"
                                    >
                                      {related}
                                    </Link>
                                  );
                                })}
                              </div>
                            </div>
                          )}
                        </div>
                      </details>
                    </Card>
                    </motion.div>
                  );
                })}
              </div>
            ))
          ) : (
            <motion.div
              className="py-16 text-center"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={springs.smooth}
            >
              <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center rounded-2xl bg-muted/30">
                <FileQuestion className="h-12 w-12 text-muted-foreground/50" />
              </div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                No terms found
              </h3>
              <p className="mx-auto max-w-sm text-muted-foreground">
                Try adjusting your search or category filter to find what you&apos;re looking for.
              </p>
              <motion.button
                onClick={() => {
                  setSearchQuery("");
                  setCategory("all");
                }}
                className="mt-6 rounded-full border border-primary/30 bg-primary/10 px-4 py-2 text-sm text-primary transition-colors hover:bg-primary/20"
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={springs.snappy}
              >
                Clear filters
              </motion.button>
            </motion.div>
          )}
        </motion.div>
      </div>
    </div>
  );
}
