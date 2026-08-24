"use client";

import { useState, useMemo, useRef, useEffect, memo } from "react";
import { motion, useReducedMotion, AnimatePresence } from "@/components/motion";
import { Layers, Wrench, Search, X, Sparkles } from "lucide-react";
import { cn, isInteractiveKeyboardTarget } from "@/lib/utils";
import { TldrToolCard } from "./tldr-tool-card";
import type { TldrFlywheelTool } from "@/lib/tldr-content";

// =============================================================================
// TYPES
// =============================================================================

interface TldrToolGridProps {
  tools: TldrFlywheelTool[];
  className?: string;
}

// =============================================================================
// SEARCH BAR COMPONENT - Enhanced with focus glow and animations
// =============================================================================

const ToolSearchBar = memo(function ToolSearchBar({
  query,
  onQueryChange,
  resultCount,
  totalCount,
  inputRef,
  reducedMotion,
}: {
  query: string;
  onQueryChange: (query: string) => void;
  resultCount: number;
  totalCount: number;
  inputRef: React.RefObject<HTMLInputElement | null>;
  reducedMotion: boolean;
}) {
  const [isFocused, setIsFocused] = useState(false);

  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: reducedMotion ? 0 : 0.3 }}
      className="mb-8 sm:mb-10"
    >
      <div className="relative mx-auto max-w-2xl">
        {/* Glass morphism search container */}
        <div
          className={cn(
            "relative rounded-2xl border bg-card/50 backdrop-blur-md transition-all duration-300",
            isFocused
              ? "border-primary/50 bg-card/70"
              : "border-border/50 hover:border-border"
          )}
          style={{
            boxShadow: isFocused
              ? "0 0 40px -10px rgba(139, 92, 246, 0.3), 0 8px 30px -10px rgba(0, 0, 0, 0.3)"
              : "0 4px 20px -5px rgba(0, 0, 0, 0.2)",
          }}
        >
          {/* Focus glow ring */}
          <div
            className={cn(
              "pointer-events-none absolute -inset-px rounded-2xl transition-opacity duration-300",
              isFocused ? "opacity-100" : "opacity-0"
            )}
            style={{
              background: "linear-gradient(90deg, transparent, rgba(139, 92, 246, 0.2), transparent)",
            }}
          />

          {/* Search icon */}
          <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 sm:pl-5">
            <Search
              className={cn(
                "h-5 w-5 transition-colors duration-200",
                isFocused ? "text-primary" : "text-muted-foreground"
              )}
              aria-hidden="true"
            />
          </div>

          {/* Input field */}
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => onQueryChange(e.target.value)}
            onFocus={() => setIsFocused(true)}
            onBlur={() => setIsFocused(false)}
            placeholder="Search tools by name, feature, or technology..."
            aria-label="Search flywheel tools"
            className="w-full rounded-2xl bg-transparent py-4 pl-12 pr-20 text-sm text-white placeholder-muted-foreground focus:outline-none sm:py-5 sm:pl-14 sm:pr-24 sm:text-base"
          />

          {/* Clear button and keyboard hint */}
          <div className="absolute inset-y-0 right-0 flex items-center gap-2 pr-4 sm:gap-3 sm:pr-5">
            <AnimatePresence>
              {query && (
                <motion.button
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.8 }}
                  onClick={() => onQueryChange("")}
                  className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground ring-1 ring-white/10 transition-all duration-200 hover:bg-white/10 hover:text-white hover:ring-white/20"
                  aria-label="Clear search"
                >
                  <X className="h-4 w-4" />
                </motion.button>
              )}
            </AnimatePresence>
            <kbd className="hidden rounded-lg border border-border bg-card/50 px-2.5 py-1.5 text-xs font-medium text-muted-foreground shadow-sm sm:inline-block">
              /
            </kbd>
          </div>
        </div>

        {/* Results count */}
        <AnimatePresence>
          {query && (
            <motion.div
              initial={reducedMotion ? {} : { opacity: 0, y: -5 }}
              animate={{ opacity: 1, y: 0 }}
              exit={reducedMotion ? {} : { opacity: 0, y: -5 }}
              className="mt-3 text-center sm:mt-4"
              role="status"
              aria-live="polite"
            >
              <span className="inline-flex items-center gap-2 rounded-full bg-card/50 px-4 py-2 text-xs text-muted-foreground ring-1 ring-border/50 backdrop-blur-sm sm:text-sm">
                {resultCount === 0 ? (
                  <>
                    <X className="h-3.5 w-3.5 text-destructive" />
                    No tools match your search
                  </>
                ) : (
                  <>
                    <Sparkles className="h-3.5 w-3.5 text-primary" />
                    Showing{" "}
                    <span className="font-semibold text-white">
                      {resultCount}
                    </span>{" "}
                    of{" "}
                    <span className="font-semibold text-white">
                      {totalCount}
                    </span>{" "}
                    tools
                  </>
                )}
              </span>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
});

// =============================================================================
// EMPTY STATE COMPONENT
// =============================================================================

const EmptySearchState = memo(function EmptySearchState({
  query,
  onClear,
  reducedMotion,
}: {
  query: string;
  onClear: () => void;
  reducedMotion: boolean;
}) {
  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: reducedMotion ? 0 : 0.3 }}
      className="py-16 text-center"
    >
      <div
        className="mx-auto flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br from-primary/20 to-primary/5 ring-1 ring-primary/20"
        style={{
          boxShadow: "0 0 40px -10px rgba(139, 92, 246, 0.3)",
        }}
      >
        <Search className="h-10 w-10 text-primary" />
      </div>
      <h3 className="mt-6 text-xl font-bold text-white">
        No tools match &quot;{query}&quot;
      </h3>
      <p className="mt-2 text-sm text-muted-foreground">
        Try searching for &quot;session&quot;, &quot;memory&quot;, or
        &quot;search&quot;
      </p>
      <button
        onClick={onClear}
        className="mt-6 inline-flex items-center gap-2 rounded-xl bg-primary/10 px-5 py-2.5 text-sm font-medium text-primary ring-1 ring-primary/20 transition-all duration-200 hover:bg-primary/20 hover:ring-primary/30"
      >
        <X className="h-4 w-4" />
        Clear search
      </button>
    </motion.div>
  );
});

// =============================================================================
// SECTION HEADER COMPONENT - Enhanced with better visual hierarchy
// =============================================================================

const SectionHeader = memo(function SectionHeader({
  title,
  description,
  icon: Icon,
  count,
  reducedMotion,
  accentColor = "primary",
}: {
  title: string;
  description: string;
  icon: React.ComponentType<{ className?: string }>;
  count: number;
  reducedMotion: boolean;
  accentColor?: "primary" | "accent" | "success";
}) {
  const colorClasses = {
    primary: "from-primary to-primary/60 text-primary bg-primary/20 ring-primary/30",
    accent: "from-accent to-accent/60 text-accent bg-accent/20 ring-accent/30",
    success: "from-success to-success/60 text-success bg-success/20 ring-success/30",
  };

  const colors = colorClasses[accentColor];
  const [iconBg] = colors.split(" ").slice(0, 2);

  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-50px" }}
      transition={{ duration: reducedMotion ? 0 : 0.5 }}
      className="mb-8 sm:mb-10"
    >
      <div className="flex items-center gap-3 sm:gap-4">
        {/* Icon container with gradient and glow */}
        <div
          className={cn(
            "relative flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br shadow-lg sm:h-14 sm:w-14",
            iconBg
          )}
          style={{
            boxShadow: accentColor === "primary"
              ? "0 0 30px -5px rgba(139, 92, 246, 0.4)"
              : accentColor === "accent"
              ? "0 0 30px -5px rgba(251, 191, 36, 0.4)"
              : "0 0 30px -5px rgba(34, 197, 94, 0.4)",
          }}
        >
          <Icon className={cn("h-6 w-6 text-white drop-shadow sm:h-7 sm:w-7")} />
          {/* Inner glow */}
          <div className="pointer-events-none absolute inset-0 rounded-2xl bg-gradient-to-t from-transparent to-white/20" />
        </div>

        <div className="flex-1">
          <div className="flex flex-wrap items-center gap-2 sm:gap-3">
            <h2 className="text-xl font-bold text-white sm:text-2xl md:text-3xl">
              {title}
            </h2>
            <span
              className={cn(
                "rounded-full px-2.5 py-1 text-xs font-bold ring-1 sm:px-3 sm:text-sm",
                colors.split(" ").slice(2).join(" ")
              )}
            >
              {count}
            </span>
          </div>
          <p className="mt-1 max-w-3xl text-sm leading-relaxed text-muted-foreground sm:mt-2 sm:text-base">
            {description}
          </p>
        </div>
      </div>

      {/* Decorative line */}
      <div className="mt-6 flex items-center gap-4">
        <div
          className="h-px flex-1"
          style={{
            background: accentColor === "primary"
              ? "linear-gradient(90deg, rgba(139, 92, 246, 0.5), transparent)"
              : accentColor === "accent"
              ? "linear-gradient(90deg, rgba(251, 191, 36, 0.5), transparent)"
              : "linear-gradient(90deg, rgba(34, 197, 94, 0.5), transparent)",
          }}
        />
      </div>
    </motion.div>
  );
});

// =============================================================================
// SIMPLE FILTER FUNCTION (no fuse.js dependency)
// =============================================================================

function filterTools(tools: TldrFlywheelTool[], query: string): TldrFlywheelTool[] {
  const normalizedQuery = query.toLowerCase().trim();
  if (!normalizedQuery) return tools;

  return tools.filter((tool) => {
    const searchFields = [
      tool.name,
      tool.shortName,
      tool.cliName ?? "",
      tool.commandExample ?? "",
      tool.whatItDoes,
      tool.whyItsUseful,
      ...tool.techStack,
      ...tool.keyFeatures,
    ].map(s => s.toLowerCase());

    return searchFields.some(field => field.includes(normalizedQuery));
  });
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

export function TldrToolGrid({ tools, className }: TldrToolGridProps) {
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Search state
  const [searchQuery, setSearchQuery] = useState("");

  // Filter tools based on search query (simple filter)
  const filteredTools = useMemo(() => {
    return filterTools(tools, searchQuery);
  }, [searchQuery, tools]);

  // Group filtered tools by category
  const { coreTools, supportingTools } = useMemo(() => {
    return {
      coreTools: filteredTools.filter((t) => t.category === "core"),
      supportingTools: filteredTools.filter((t) => t.category === "supporting"),
    };
  }, [filteredTools]);

  // Keyboard shortcut: "/" to focus search
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Leave browser/IME chords and typing inside other controls alone:
      // Cmd+/ and Ctrl+/ are user shortcuts, and contenteditable/select
      // targets are not caught by a tagName check.
      if (e.isComposing || e.metaKey || e.ctrlKey || e.altKey) return;
      const insideControl = isInteractiveKeyboardTarget(e.target);
      // Focus search on "/" key (when not in an input)
      if (e.key === "/" && !insideControl) {
        e.preventDefault();
        searchInputRef.current?.focus();
      }
      // Clear search on Escape, but only from the search box itself
      if (
        e.key === "Escape" &&
        searchQuery &&
        e.target === searchInputRef.current
      ) {
        setSearchQuery("");
        searchInputRef.current?.blur();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [searchQuery]);

  const hasResults = filteredTools.length > 0;
  const isSearching = searchQuery.trim().length > 0;

  return (
    <div className={cn("space-y-16 sm:space-y-20", className)}>
      {/* Search Bar */}
      <ToolSearchBar
        query={searchQuery}
        onQueryChange={setSearchQuery}
        resultCount={filteredTools.length}
        totalCount={tools.length}
        inputRef={searchInputRef}
        reducedMotion={reducedMotion}
      />

      {/* Empty State */}
      {isSearching && !hasResults && (
        <EmptySearchState
          query={searchQuery}
          onClear={() => setSearchQuery("")}
          reducedMotion={reducedMotion}
        />
      )}

      {/* Core Tools Section */}
      {coreTools.length > 0 && (
        <section id="core-tools">
          <SectionHeader
            title="Core Flywheel Tools"
            description="The backbone of multi-agent development: session management, communication, task tracking, static analysis, memory, search, safety guards, multi-repo sync, and automated setup. These tools form a self-reinforcing loop where each makes the others more powerful."
            icon={Layers}
            count={coreTools.length}
            reducedMotion={reducedMotion}
            accentColor="primary"
          />
          <div className="grid grid-cols-1 gap-4 sm:gap-6 md:grid-cols-2 lg:grid-cols-3">
            <AnimatePresence mode="popLayout">
              {coreTools.map((tool, index) => (
                <motion.div
                  key={tool.id}
                  layout={!reducedMotion}
                  initial={reducedMotion ? {} : { opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={reducedMotion ? {} : { opacity: 0, scale: 0.9 }}
                  transition={{
                    duration: reducedMotion ? 0 : 0.3,
                    delay: reducedMotion ? 0 : index * 0.03,
                  }}
                  className="h-full"
                >
                  <TldrToolCard
                    tool={tool}
                    allTools={tools}
                  />
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </section>
      )}

      {/* Supporting Tools Section */}
      {supportingTools.length > 0 && (
        <section id="supporting-tools">
          <SectionHeader
            title="Supporting Tools"
            description="Extend the ecosystem with GitHub issue sync, archive search, and prompt crafting utilities. These tools enhance the core flywheel for specialized workflows."
            icon={Wrench}
            count={supportingTools.length}
            reducedMotion={reducedMotion}
            accentColor="accent"
          />
          <div className="grid grid-cols-1 gap-4 sm:gap-6 md:grid-cols-2 lg:grid-cols-3">
            <AnimatePresence mode="popLayout">
              {supportingTools.map((tool, index) => (
                <motion.div
                  key={tool.id}
                  layout={!reducedMotion}
                  initial={reducedMotion ? {} : { opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={reducedMotion ? {} : { opacity: 0, scale: 0.9 }}
                  transition={{
                    duration: reducedMotion ? 0 : 0.3,
                    delay: reducedMotion ? 0 : index * 0.03,
                  }}
                  className="h-full"
                >
                  <TldrToolCard
                    tool={tool}
                    allTools={tools}
                  />
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </section>
      )}
    </div>
  );
}

export default TldrToolGrid;
