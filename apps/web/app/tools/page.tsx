"use client";

import { useState, useMemo, useCallback } from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import {
  Search,
  ExternalLink,
  Terminal,
  Filter,
  X,
  Star,
  // Tool icons
  FileText,
  ListTodo,
  GitBranch,
  FlaskConical,
  KeyRound,
  Brain,
  ShieldAlert,
  Sparkles,
  Mail,
  LayoutGrid,
  Activity,
  Cpu,
  RefreshCw,
  ShieldCheck,
  Shield,
  Bug,
  Monitor,
  Image,
  FileCode,
  Archive,
  Box,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import { manifestTools, type ManifestWebTool } from "@/lib/generated/manifest-web-index";

// =============================================================================
// ICON MAP - Maps icon names from manifest to Lucide icons
// =============================================================================

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  "file-text": FileText,
  "list-todo": ListTodo,
  "git-branch": GitBranch,
  "flask-conical": FlaskConical,
  "key-round": KeyRound,
  search: Search,
  brain: Brain,
  "shield-alert": ShieldAlert,
  sparkles: Sparkles,
  mail: Mail,
  "layout-grid": LayoutGrid,
  activity: Activity,
  cpu: Cpu,
  "refresh-cw": RefreshCw,
  "shield-check": ShieldCheck,
  shield: Shield,
  bug: Bug,
  monitor: Monitor,
  image: Image,
  "file-code": FileCode,
  archive: Archive,
};

function DynamicIcon({ name, className }: { name: string; className?: string }) {
  const IconComponent = iconMap[name] || Box;
  return <IconComponent className={className} />;
}

// =============================================================================
// HELPERS
// =============================================================================

function getCategory(tool: ManifestWebTool): string {
  if (tool.moduleId.startsWith("stack.")) return "Flywheel Stack";
  if (tool.moduleId.startsWith("utils.")) return "Utilities";
  return "Other";
}

function getCategoryColor(category: string): string {
  switch (category) {
    case "Flywheel Stack":
      return "from-violet-500 to-purple-600";
    case "Utilities":
      return "from-slate-500 to-gray-600";
    default:
      return "from-blue-500 to-indigo-600";
  }
}

function formatStarCount(count: number): string {
  if (count >= 1000) {
    return `${(count / 1000).toFixed(1)}k`;
  }
  return count.toString();
}

// =============================================================================
// TOOL CARD COMPONENT
// =============================================================================

interface ToolCardProps {
  tool: ManifestWebTool;
  index: number;
}

function ToolCard({ tool, index }: ToolCardProps) {
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const category = getCategory(tool);

  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        duration: reducedMotion ? 0 : 0.3,
        delay: reducedMotion ? 0 : index * 0.03,
      }}
      className="group"
    >
      <div
        className={cn(
          "relative h-full overflow-hidden rounded-xl",
          "border border-border/50 bg-card/50 backdrop-blur-sm",
          "transition-all duration-300",
          "hover:border-border hover:bg-card/70 hover:shadow-lg"
        )}
      >
        {/* Top accent bar */}
        <div
          className={cn(
            "absolute inset-x-0 top-0 h-1 bg-gradient-to-r opacity-60 group-hover:opacity-100 transition-opacity",
            getCategoryColor(category)
          )}
        />

        <div className="p-4 sm:p-5">
          {/* Header */}
          <div className="flex items-start gap-3">
            {/* Icon */}
            <div
              className={cn(
                "flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br",
                getCategoryColor(category)
              )}
            >
              <DynamicIcon name={tool.icon} className="h-5 w-5 text-white" />
            </div>

            {/* Title and meta */}
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h3 className="truncate text-base font-bold text-white">
                  {tool.displayName}
                </h3>
                {tool.stars && tool.stars > 100 && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-accent/20 px-2 py-0.5 text-xs font-medium text-accent">
                    <Star className="h-3 w-3 fill-current" />
                    {formatStarCount(tool.stars)}
                  </span>
                )}
              </div>
              <p className="mt-0.5 text-xs text-muted-foreground">
                {tool.shortName}
                {tool.cliName && (
                  <span className="ml-2 rounded bg-white/10 px-1.5 py-0.5 font-mono text-xs">
                    {tool.cliName}
                  </span>
                )}
              </p>
            </div>

            {/* External link */}
            {tool.href && (
              <Link
                href={tool.href}
                target="_blank"
                rel="noopener noreferrer"
                className="flex h-10 w-10 items-center justify-center rounded-lg bg-white/5 text-muted-foreground ring-1 ring-white/10 transition-all hover:bg-white/10 hover:text-white focus-visible:ring-2 focus-visible:ring-ring outline-none"
                aria-label={`View ${tool.displayName} on GitHub`}
              >
                <ExternalLink className="h-4 w-4" />
              </Link>
            )}
          </div>

          {/* Description */}
          <p className="mt-3 text-sm leading-relaxed text-foreground/80">
            {tool.tagline}
          </p>

          {/* Features */}
          {tool.features.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {tool.features.slice(0, 3).map((feature) => (
                <span
                  key={feature}
                  className="rounded-md bg-white/5 px-2 py-1 text-xs text-muted-foreground ring-1 ring-white/10"
                >
                  {feature}
                </span>
              ))}
              {tool.features.length > 3 && (
                <span className="rounded-md bg-white/5 px-2 py-1 text-xs text-muted-foreground">
                  +{tool.features.length - 3} more
                </span>
              )}
            </div>
          )}

          {/* Command example */}
          {tool.commandExample && (
            <div className="mt-3 flex items-center gap-2 rounded-lg bg-black/20 px-3 py-2 font-mono text-xs text-primary">
              <Terminal className="h-3.5 w-3.5 shrink-0" />
              <code className="truncate">{tool.commandExample}</code>
            </div>
          )}

          {/* Tech stack */}
          {tool.techStack.length > 0 && (
            <div className="mt-3 flex items-center gap-2">
              <span className="text-xs text-muted-foreground">Built with:</span>
              <div className="flex flex-wrap gap-1">
                {tool.techStack.slice(0, 4).map((tech) => (
                  <span
                    key={tech}
                    className="rounded bg-primary/10 px-1.5 py-0.5 text-xs font-medium text-primary"
                  >
                    {tech}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CATEGORY FILTER
// =============================================================================

interface CategoryFilterProps {
  categories: string[];
  selected: string | null;
  onSelect: (category: string | null) => void;
}

function CategoryFilter({ categories, selected, onSelect }: CategoryFilterProps) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        onClick={() => onSelect(null)}
        className={cn(
          "rounded-full px-4 py-2 text-sm font-medium transition-all",
          selected === null
            ? "bg-primary text-white"
            : "bg-white/5 text-muted-foreground hover:bg-white/10 hover:text-white"
        )}
      >
        All
      </button>
      {categories.map((category) => (
        <button
          key={category}
          onClick={() => onSelect(category)}
          className={cn(
            "rounded-full px-4 py-2 text-sm font-medium transition-all",
            selected === category
              ? "bg-primary text-white"
              : "bg-white/5 text-muted-foreground hover:bg-white/10 hover:text-white"
          )}
        >
          {category}
        </button>
      ))}
    </div>
  );
}

// =============================================================================
// SEARCH INPUT
// =============================================================================

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
}

function SearchInput({ value, onChange }: SearchInputProps) {
  return (
    <div className="relative">
      <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="Search tools..."
        aria-label="Search tools"
        className={cn(
          "w-full rounded-xl bg-card/50 py-3 pl-10 pr-10 text-sm",
          "border border-border/50 backdrop-blur-sm",
          "placeholder:text-muted-foreground",
          "focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20",
          "transition-all duration-200"
        )}
      />
      {value && (
        <button
          onClick={() => onChange("")}
          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-white"
          aria-label="Clear search"
        >
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}

// =============================================================================
// HERO SECTION
// =============================================================================

function ToolsHero({ toolCount }: { toolCount: number }) {
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  return (
    <section className="relative overflow-hidden py-16 md:py-24">
      {/* Background gradient */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-primary/5 via-transparent to-transparent" />

      <div className="container relative mx-auto px-4 sm:px-6">
        <motion.div
          initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: reducedMotion ? 0 : 0.5 }}
          className="text-center"
        >
          <h1 className="text-3xl font-bold text-white sm:text-4xl md:text-5xl">
            ACFS Tool Status
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base text-muted-foreground sm:text-lg">
            All {toolCount} tools installed by the Agentic Coding Flywheel Setup.
            Search, filter, and explore the complete toolkit.
          </p>
        </motion.div>
      </div>
    </section>
  );
}

// =============================================================================
// STATS BAR
// =============================================================================

function StatsBar({
  total,
  filtered,
  categories,
}: {
  total: number;
  filtered: number;
  categories: Record<string, number>;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl bg-card/30 px-4 py-3 ring-1 ring-border/50">
      <div className="flex items-center gap-2">
        <Filter className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">
          Showing <span className="font-medium text-white">{filtered}</span> of{" "}
          <span className="font-medium text-white">{total}</span> tools
        </span>
      </div>
      <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
        {Object.entries(categories).map(([cat, count]) => (
          <span key={cat}>
            {cat}: <span className="text-white">{count}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

// =============================================================================
// MAIN PAGE COMPONENT
// =============================================================================

export default function ToolsPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);

  // Get unique categories
  const categories = useMemo(() => {
    const cats = new Set<string>();
    manifestTools.forEach((tool) => cats.add(getCategory(tool)));
    return Array.from(cats).sort();
  }, []);

  // Category counts
  const categoryCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    manifestTools.forEach((tool) => {
      const cat = getCategory(tool);
      counts[cat] = (counts[cat] || 0) + 1;
    });
    return counts;
  }, []);

  // Filter tools based on search and category
  const filteredTools = useMemo(() => {
    return manifestTools.filter((tool) => {
      // Category filter
      if (selectedCategory && getCategory(tool) !== selectedCategory) {
        return false;
      }

      // Search filter
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        return (
          tool.displayName.toLowerCase().includes(query) ||
          tool.shortName.toLowerCase().includes(query) ||
          tool.tagline.toLowerCase().includes(query) ||
          (tool.cliName && tool.cliName.toLowerCase().includes(query)) ||
          tool.features.some((f) => f.toLowerCase().includes(query)) ||
          tool.techStack.some((t) => t.toLowerCase().includes(query))
        );
      }

      return true;
    });
  }, [searchQuery, selectedCategory]);

  const handleSearchChange = useCallback((value: string) => {
    setSearchQuery(value);
  }, []);

  const handleCategorySelect = useCallback((category: string | null) => {
    setSelectedCategory(category);
  }, []);

  return (
    <ErrorBoundary>
      <main className="min-h-screen overflow-x-hidden">
        {/* Hero */}
        <ToolsHero toolCount={manifestTools.length} />

        {/* Main content */}
        <section className="pb-16 md:pb-24">
          <div className="container mx-auto px-4 sm:px-6">
            {/* Filters */}
            <div className="mb-6 space-y-4">
              <SearchInput value={searchQuery} onChange={handleSearchChange} />
              <CategoryFilter
                categories={categories}
                selected={selectedCategory}
                onSelect={handleCategorySelect}
              />
            </div>

            {/* Stats */}
            <div className="mb-6">
              <StatsBar
                total={manifestTools.length}
                filtered={filteredTools.length}
                categories={categoryCounts}
              />
            </div>

            {/* Tools grid */}
            {filteredTools.length > 0 ? (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {filteredTools.map((tool, index) => (
                  <ToolCard key={tool.id} tool={tool} index={index} />
                ))}
              </div>
            ) : (
              <div className="py-16 text-center">
                <Search className="mx-auto h-12 w-12 text-muted-foreground/50" />
                <h3 className="mt-4 text-lg font-medium text-white">
                  No tools found
                </h3>
                <p className="mt-2 text-sm text-muted-foreground">
                  Try adjusting your search or filter criteria.
                </p>
                <button
                  onClick={() => {
                    setSearchQuery("");
                    setSelectedCategory(null);
                  }}
                  className="mt-4 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary/90 transition-colors"
                >
                  Clear filters
                </button>
              </div>
            )}
          </div>
        </section>
      </main>
    </ErrorBoundary>
  );
}
