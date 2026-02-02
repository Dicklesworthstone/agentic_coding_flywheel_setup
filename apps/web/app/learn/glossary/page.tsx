"use client";

import Link from "next/link";
import { useMemo, useState, type ReactNode } from "react";
import { ArrowLeft, BookOpen, Home, Search, Wrench, ShieldCheck, Type, FileQuestion, Sparkles, ChevronDown, ChevronRight } from "lucide-react";
import { getAllTerms, type JargonTerm } from "@/lib/jargon";
import { motion, springs, staggerContainer, fadeUp } from "@/components/motion";

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
  "tmux", "zsh", "bash", "bun", "uv", "cargo", "rust", "go", "git", "gh",
  "lazygit", "rg", "ripgrep", "fzf", "direnv", "zoxide", "atuin", "ntm",
  "bv", "br", "ubs", "cass", "cm", "caam", "slb", "dcg", "vault", "wrangler",
  "supabase", "vercel", "postgres",
]);

const PROTOCOL_TERMS = new Set([
  "ssh", "mcp", "oauth", "jwt", "api", "http", "https", "dns", "tcp", "udp", "tls",
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
  gradient: string;
}> = [
  {
    id: "concepts",
    label: "Concepts",
    icon: <BookOpen className="h-4 w-4" />,
    description: "Core ideas and mental models",
    gradient: "from-primary/20 to-blue-500/20",
  },
  {
    id: "tools",
    label: "Tools",
    icon: <Wrench className="h-4 w-4" />,
    description: "Programs and CLIs you'll use",
    gradient: "from-emerald-500/20 to-teal-500/20",
  },
  {
    id: "protocols",
    label: "Protocols",
    icon: <ShieldCheck className="h-4 w-4" />,
    description: "How systems talk to each other",
    gradient: "from-violet-500/20 to-purple-500/20",
  },
  {
    id: "acronyms",
    label: "Acronyms",
    icon: <Type className="h-4 w-4" />,
    description: "Short words you'll see everywhere",
    gradient: "from-amber-500/20 to-orange-500/20",
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
      whileHover={{ scale: 1.03 }}
      whileTap={{ scale: 0.97 }}
      transition={springs.snappy}
      className={`min-h-[44px] rounded-full border px-5 py-2.5 text-sm font-medium transition-all duration-300 ${
        isSelected
          ? "border-primary/50 bg-gradient-to-r from-primary/20 to-violet-500/20 text-white shadow-[0_0_20px_rgba(var(--primary-rgb),0.3)]"
          : "border-white/[0.08] bg-white/[0.03] text-white/60 hover:border-white/20 hover:bg-white/[0.06] hover:text-white/80"
      }`}
    >
      {label}
    </motion.button>
  );
}

function TermCard({ term }: { term: JargonTerm }) {
  const [isOpen, setIsOpen] = useState(false);
  const anchorId = toAnchorId(term.term);
  const inferredCategory = categorizeTerm(term);
  const categoryMeta = CATEGORY_META.find((c) => c.id === inferredCategory);

  return (
    <motion.div
      variants={fadeUp}
      whileHover={{ y: -2 }}
      transition={springs.snappy}
    >
      <div
        id={anchorId}
        className="group relative overflow-hidden rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl scroll-mt-28 transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
      >
        {/* Hover gradient */}
        {categoryMeta && (
          <div className={`absolute inset-0 bg-gradient-to-br ${categoryMeta.gradient} opacity-0 group-hover:opacity-100 transition-opacity duration-500`} />
        )}

        <div className="relative p-5">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2 mb-2">
                <h2 className="font-mono text-lg font-bold text-white">
                  {term.term}
                </h2>
                {categoryMeta && (
                  <span className={`inline-flex items-center gap-1.5 rounded-full bg-gradient-to-r ${categoryMeta.gradient} border border-white/[0.08] px-2.5 py-0.5 text-xs text-white/80`}>
                    {categoryMeta.icon}
                    {categoryMeta.label}
                  </span>
                )}
              </div>
              <p className="text-sm text-white/50 leading-relaxed">
                {term.short}
              </p>
            </div>
            <Link
              href={`#${anchorId}`}
              className="text-xs text-white/30 hover:text-white/60 transition-colors font-mono shrink-0"
            >
              #{anchorId}
            </Link>
          </div>

          <button
            onClick={() => setIsOpen(!isOpen)}
            className="mt-4 flex items-center gap-2 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
          >
            {isOpen ? (
              <>
                <ChevronDown className="h-4 w-4" />
                <span>Show less</span>
              </>
            ) : (
              <>
                <ChevronRight className="h-4 w-4" />
                <span>Read more</span>
              </>
            )}
          </button>

          {isOpen && (
            <motion.div
              className="mt-4 space-y-4 text-sm leading-relaxed text-white/60"
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              transition={springs.smooth}
            >
              <p>{term.long}</p>

              {term.analogy && (
                <div className="rounded-xl border border-primary/30 bg-gradient-to-br from-primary/10 to-violet-500/5 p-4">
                  <p className="mb-1 font-semibold text-white">
                    Think of it like…
                  </p>
                  <p className="text-white/70">{term.analogy}</p>
                </div>
              )}

              {term.why && (
                <div className="rounded-xl border border-white/[0.08] bg-white/[0.03] p-4">
                  <p className="mb-1 font-semibold text-white">
                    Why it matters
                  </p>
                  <p>{term.why}</p>
                </div>
              )}

              {term.related && term.related.length > 0 && (
                <div>
                  <p className="mb-3 font-semibold text-white">
                    Related terms
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {term.related.map((related) => {
                      const relatedAnchor = toAnchorId(related);
                      return (
                        <Link
                          key={related}
                          href={`#${relatedAnchor}`}
                          className="rounded-full border border-white/[0.08] bg-white/[0.03] px-3 py-1.5 text-xs text-white/60 transition-all duration-300 hover:border-primary/30 hover:bg-primary/10 hover:text-primary"
                        >
                          {related}
                        </Link>
                      );
                    })}
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </div>
      </div>
    </motion.div>
  );
}

export default function GlossaryPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [category, setCategory] = useState<CategoryFilter>("all");

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
    <div className="min-h-screen bg-black relative overflow-x-hidden">
      {/* Dramatic ambient background */}
      <div className="fixed inset-0 pointer-events-none">
        {/* Large primary orb */}
        <div className="absolute w-[700px] h-[700px] bg-primary/10 blur-[180px] rounded-full -top-48 left-1/4 animate-float" />
        {/* Secondary orb */}
        <div className="absolute w-[500px] h-[500px] bg-emerald-500/10 blur-[150px] rounded-full top-1/2 -right-32 animate-float" style={{ animationDelay: "2s" }} />
        {/* Tertiary orb */}
        <div className="absolute w-[400px] h-[400px] bg-violet-500/8 blur-[120px] rounded-full bottom-0 left-0 animate-float" style={{ animationDelay: "4s" }} />
        {/* Grid */}
        <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:80px_80px]" />
      </div>

      <div className="relative mx-auto max-w-5xl px-5 py-8 sm:px-8 md:px-12 lg:py-12">
        {/* Header navigation */}
        <motion.header
          className="mb-10 flex items-center justify-between"
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={springs.smooth}
        >
          <Link
            href="/learn"
            className="group flex items-center gap-3 text-white/50 transition-all duration-300 hover:text-white"
          >
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition-all duration-300 group-hover:scale-110 group-hover:bg-white/[0.1]">
              <ArrowLeft className="h-4 w-4" />
            </div>
            <span className="text-sm font-medium">Learning Hub</span>
          </Link>
          <Link
            href="/"
            className="group flex items-center gap-3 text-white/50 transition-all duration-300 hover:text-white"
          >
            <span className="text-sm font-medium">Home</span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition-all duration-300 group-hover:scale-110 group-hover:bg-white/[0.1]">
              <Home className="h-4 w-4" />
            </div>
          </Link>
        </motion.header>

        {/* Hero section */}
        <motion.section
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...springs.smooth, delay: 0.1 }}
        >
          {/* Icon with glow */}
          <motion.div
            className="mb-6 inline-flex"
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ ...springs.snappy, delay: 0.2 }}
          >
            <div className="relative">
              <div className="absolute inset-0 bg-gradient-to-br from-primary to-emerald-500 rounded-2xl blur-xl opacity-50" />
              <div className="relative flex h-18 w-18 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/30 to-emerald-500/30 border border-white/20 shadow-2xl shadow-primary/20">
                <BookOpen className="h-9 w-9 text-white drop-shadow-lg" />
              </div>
              <Sparkles className="absolute -right-2 -top-2 h-5 w-5 text-primary animate-pulse" />
            </div>
          </motion.div>

          <h1 className="mb-4 text-4xl sm:text-5xl font-bold tracking-tight">
            <span className="bg-gradient-to-br from-white via-white to-white/50 bg-clip-text text-transparent">
              Glossary
            </span>
          </h1>
          <p className="mx-auto max-w-2xl text-lg text-white/50 leading-relaxed">
            Every term used throughout ACFS, explained in plain English.
          </p>
        </motion.section>

        {/* Search - stunning glassmorphic */}
        <motion.div
          className="relative mb-8"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...springs.smooth, delay: 0.2 }}
        >
          <div className="group relative">
            {/* Glow on focus */}
            <div className="absolute -inset-1 rounded-2xl bg-gradient-to-r from-primary/30 via-emerald-500/20 to-primary/30 blur-lg opacity-0 group-focus-within:opacity-100 transition-opacity duration-500" />

            <div className="relative">
              <Search className="absolute left-5 top-1/2 h-5 w-5 -translate-y-1/2 text-white/30 transition-colors group-focus-within:text-primary" />
              <input
                type="text"
                placeholder="Search terms..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full rounded-xl border border-white/[0.08] bg-white/[0.03] py-4 pl-14 pr-5 text-white placeholder:text-white/30 backdrop-blur-xl transition-all duration-300 focus:border-primary/50 focus:bg-white/[0.05] focus:outline-none focus:shadow-[0_0_30px_rgba(var(--primary-rgb),0.15)]"
              />
            </div>
          </div>
        </motion.div>

        {/* Category filters */}
        <motion.div
          className="mb-8 flex flex-wrap gap-2 justify-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ ...springs.smooth, delay: 0.3 }}
        >
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
        </motion.div>

        {/* Count display */}
        <motion.p
          className="mb-10 text-center text-sm text-white/40"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ ...springs.smooth, delay: 0.4 }}
        >
          Showing{" "}
          <span className="font-mono text-white font-medium">
            {filteredTerms.length}
          </span>{" "}
          of{" "}
          <span className="font-mono text-white font-medium">{allTerms.length}</span>{" "}
          terms
        </motion.p>

        {/* Terms */}
        <motion.div
          className="space-y-4"
          initial="hidden"
          animate="visible"
          variants={staggerContainer}
        >
          {filteredTerms.length > 0 ? (
            groupedTerms.map(([letter, terms]) => (
              <div key={letter} className="space-y-4">
                {/* Letter header */}
                <motion.div
                  className="sticky top-16 z-10"
                  variants={fadeUp}
                >
                  <div className="relative overflow-hidden rounded-xl border border-white/[0.08] bg-black/80 backdrop-blur-xl px-5 py-3">
                    <div className="absolute inset-0 bg-gradient-to-r from-primary/10 via-transparent to-transparent" />
                    <span className="relative font-mono text-lg font-bold bg-gradient-to-r from-primary to-emerald-400 bg-clip-text text-transparent">
                      {letter}
                    </span>
                  </div>
                </motion.div>
                {terms.map((term) => (
                  <TermCard key={term.term} term={term} />
                ))}
              </div>
            ))
          ) : (
            <motion.div
              className="py-20 text-center"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={springs.smooth}
            >
              <div className="relative inline-flex mb-6">
                <div className="absolute inset-0 bg-white/10 rounded-2xl blur-xl" />
                <div className="relative flex h-20 w-20 items-center justify-center rounded-2xl bg-white/[0.05] border border-white/[0.08]">
                  <FileQuestion className="h-10 w-10 text-white/30" />
                </div>
              </div>
              <h3 className="mb-3 text-xl font-bold text-white">
                No terms found
              </h3>
              <p className="mx-auto max-w-sm text-white/50 mb-6">
                Try adjusting your search or category filter to find what you&apos;re looking for.
              </p>
              <motion.button
                onClick={() => {
                  setSearchQuery("");
                  setCategory("all");
                }}
                className="rounded-full bg-gradient-to-r from-primary/20 to-violet-500/20 border border-primary/30 px-6 py-3 text-sm font-medium text-white transition-all duration-300 hover:from-primary/30 hover:to-violet-500/30 hover:shadow-[0_0_30px_rgba(var(--primary-rgb),0.3)]"
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={springs.snappy}
              >
                Clear filters
              </motion.button>
            </motion.div>
          )}
        </motion.div>

        {/* Footer spacer */}
        <div className="h-20" />
      </div>
    </div>
  );
}
