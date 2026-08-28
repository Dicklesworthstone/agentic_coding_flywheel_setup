"use client";

import Link from "next/link";
import { useRef, useState, useCallback, useMemo } from "react";
import { motion, useReducedMotion } from "@/components/motion";
import {
  ArrowUpRight,
  Star,
  ExternalLink,
  Box,
  LayoutGrid,
  Rocket,
  Mail,
  GitBranch,
  Bug,
  Brain,
  Search,
  ShieldAlert,
  ShieldCheck,
  GitPullRequest,
  Archive,
  FileCode,
  RefreshCw,
  Cog,
  Image,
  ChevronRight,
  Terminal,
  Activity,
  BarChart,
  Cpu,
  FileJson,
  FileText,
  FlaskConical,
  Globe,
  KeyRound,
  ListTodo,
  Monitor,
  Network,
  PenTool,
  Radio,
  Shield,
  Sparkles,
  Bot,
  HardDrive,
  Package,
  Power,
  Repeat,
  Save,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { formatStarCount, formatStarCountFull } from "@/lib/format-stars";
import { getColorDefinition } from "@/lib/colors";
import type { TldrFlywheelTool } from "@/lib/tldr-content";

// =============================================================================
// TYPES
// =============================================================================

interface TldrToolCardProps {
  tool: TldrFlywheelTool;
  allTools: TldrFlywheelTool[];
}

// =============================================================================
// ICON MAP
// =============================================================================

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  LayoutGrid,
  Rocket,
  Mail,
  GitBranch,
  Bug,
  Brain,
  Search,
  ShieldAlert,
  ShieldCheck,
  GitPullRequest,
  Archive,
  FileCode,
  RefreshCw,
  Cog,
  Image,
  Box,
  // Every icon name used in lib/tldr-content.ts must appear here; anything
  // missing silently renders as the generic Box fallback.
  Activity,
  BarChart,
  Cpu,
  FileJson,
  FileText,
  FlaskConical,
  Globe,
  KeyRound,
  ListTodo,
  Monitor,
  Network,
  PenTool,
  Radio,
  Shield,
  Sparkles,
  // Icons used by manifest-only tools auto-appended in lib/tldr-content.ts
  // (kebab-case manifest names converted to these component names).
  Bot,
  HardDrive,
  Package,
  Power,
  Repeat,
  Save,
};

// =============================================================================
// HELPER COMPONENTS
// =============================================================================

function DynamicIcon({
  name,
  className,
}: {
  name: string;
  className?: string;
}) {
  const IconComponent = iconMap[name] || Box;
  return <IconComponent className={className} />;
}

function SynergyPill({
  synergy,
  allTools,
}: {
  synergy: { toolId: string; description: string };
  allTools: TldrFlywheelTool[];
}) {
  const linkedTool = allTools.find((t) => t.id === synergy.toolId);
  if (!linkedTool) return null;

  const colorDef = getColorDefinition(linkedTool.color);

  return (
    <div
      className="group/synergy relative flex items-center gap-2 rounded-xl bg-white/5 px-2 py-1.5 ring-1 ring-white/10 transition duration-300 hover:bg-white/10 hover:ring-white/20 sm:px-3 sm:py-2"
      style={{
        boxShadow: "0 2px 8px rgba(0, 0, 0, 0.1)",
      }}
    >
      {/* Subtle color glow on hover */}
      <div
        className="pointer-events-none absolute inset-0 rounded-xl opacity-0 transition-opacity duration-300 group-hover/synergy:opacity-100"
        style={{
          background: `radial-gradient(circle at center, rgba(${colorDef.rgb}, 0.1), transparent 70%)`,
        }}
      />

      <div
        className={cn(
          "relative flex h-5 w-5 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br shadow-md sm:h-6 sm:w-6",
          linkedTool.color
        )}
      >
        <DynamicIcon name={linkedTool.icon} className="h-2.5 w-2.5 text-white sm:h-3 sm:w-3" />
      </div>
      <div className="relative min-w-0 flex-1">
        <span className="block text-xs font-semibold text-white sm:text-xs">
          {linkedTool.shortName}
        </span>
        <span className="block truncate text-xs text-muted-foreground transition-colors duration-200 group-hover/synergy:text-foreground/70 sm:text-xs">
          {synergy.description}
        </span>
      </div>
      <ChevronRight className="h-3 w-3 shrink-0 text-muted-foreground opacity-0 transition duration-200 group-hover/synergy:translate-x-0.5 group-hover/synergy:opacity-100" />
    </div>
  );
}

// =============================================================================
// FEATURE LIST ITEM
// =============================================================================

function FeatureItem({ feature }: { feature: string }) {
  return (
    <li className="group/feature flex items-start gap-2 text-xs text-foreground/80 transition-colors duration-200 hover:text-foreground sm:text-sm">
      <div className="mt-1 flex h-4 w-4 shrink-0 items-center justify-center rounded bg-primary/10 text-primary transition-colors duration-200 group-hover/feature:bg-primary/20">
        <ArrowUpRight className="h-2.5 w-2.5" aria-hidden="true" />
      </div>
      {feature}
    </li>
  );
}

// =============================================================================
// TECH BADGE
// =============================================================================

function TechBadge({ tech }: { tech: string }) {
  return (
    <span className="rounded-lg bg-white/5 px-2 py-1 text-xs font-medium text-muted-foreground ring-1 ring-white/10 transition duration-200 hover:bg-white/10 hover:text-foreground/80">
      {tech}
    </span>
  );
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

export function TldrToolCard({
  tool,
  allTools,
}: TldrToolCardProps) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [spotlightOpacity, setSpotlightOpacity] = useState(0);
  const [isHovered, setIsHovered] = useState(false);
  const isTouchDevice = useMemo(
    () => typeof window !== "undefined" && window.matchMedia("(hover: none)").matches,
    []
  );
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (!cardRef.current || reducedMotion || isTouchDevice) return;
      const rect = cardRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      requestAnimationFrame(() => {
        cardRef.current?.style.setProperty("--mouse-x", `${x}px`);
        cardRef.current?.style.setProperty("--mouse-y", `${y}px`);
      });
    },
    [reducedMotion, isTouchDevice]
  );

  const colorDef = getColorDefinition(tool.color);

  return (
    <motion.div
      layout={!reducedMotion}
      className="group h-full"
      initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: reducedMotion ? 0 : 0.4 }}
      data-testid="tool-card"
    >
      <div
        ref={cardRef}
        onMouseMove={handleMouseMove}
        onMouseEnter={() => {
          setSpotlightOpacity(1);
          setIsHovered(true);
        }}
        onMouseLeave={() => {
          setSpotlightOpacity(0);
          setIsHovered(false);
        }}
        className={cn(
          "relative h-full flex flex-col overflow-hidden rounded-xl sm:rounded-2xl",
          "border border-border/50 bg-card/50 backdrop-blur-sm",
          "transition duration-300",
          "hover:border-border hover:bg-card/70",
          "active:scale-[0.98]"
        )}
        style={{
          boxShadow: isHovered
            ? `0 0 40px -10px rgba(${colorDef.rgb}, 0.3), 0 20px 40px -15px rgba(0, 0, 0, 0.4)`
            : "0 4px 20px -5px rgba(0, 0, 0, 0.2)",
          transition: "box-shadow 0.3s ease, border-color 0.3s ease, background-color 0.3s ease",
        }}
      >
        {/* Top border glow on hover */}
        <div
          className="pointer-events-none absolute inset-x-0 top-0 h-px transition-opacity duration-300"
          style={{
            background: `linear-gradient(90deg, transparent, rgba(${colorDef.rgb}, ${isHovered ? 0.5 : 0}), transparent)`,
          }}
        />

        {/* Gradient background */}
        <div
          className={cn(
            "absolute inset-0 bg-gradient-to-br opacity-[0.05] transition-opacity duration-300 group-hover:opacity-[0.1]",
            tool.color
          )}
          aria-hidden="true"
        />

        {/* Spotlight effect */}
        <div
          className="pointer-events-none absolute -inset-px transition-opacity duration-500"
          style={{
            opacity: spotlightOpacity,
            background: `radial-gradient(500px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), rgba(${colorDef.rgb}, 0.15), transparent 40%)`,
          }}
          aria-hidden="true"
        />

        {/* Content */}
        <div className="relative z-10 flex flex-1 flex-col">
          {/* Header */}
          <div className="p-4 sm:p-5">
            <div className="flex items-start justify-between gap-3 sm:gap-4">
              {/* Icon and title */}
              <div className="flex items-start gap-3 sm:gap-4">
                <div
                  className={cn(
                    "relative flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br sm:h-12 sm:w-12",
                    tool.color
                  )}
                  style={{
                    boxShadow: isHovered
                      ? `0 0 25px -5px rgba(${colorDef.rgb}, 0.5), 0 8px 20px -5px rgba(0, 0, 0, 0.3)`
                      : "0 4px 15px -3px rgba(0, 0, 0, 0.3)",
                    transition: "box-shadow 0.3s ease",
                  }}
                >
                  <DynamicIcon name={tool.icon} className="h-5 w-5 text-white drop-shadow sm:h-6 sm:w-6" />
                  {/* Inner highlight */}
                  <div className="pointer-events-none absolute inset-0 rounded-xl bg-gradient-to-t from-transparent to-white/20" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-base font-bold text-white sm:text-lg">
                      {tool.shortName}
                    </h3>
                    {tool.category === "core" && (
                      <span
                        className="rounded-full bg-primary/20 px-2 py-0.5 text-xs font-bold uppercase tracking-wider text-primary ring-1 ring-primary/30"
                        style={{
                          boxShadow: "0 0 10px -2px rgba(var(--primary-rgb, 139, 92, 246), 0.3)",
                        }}
                      >
                        Core
                      </span>
                    )}
                    {tool.cliName && (
                      <code
                        className="rounded-md bg-white/5 px-1.5 py-0.5 font-mono text-xs text-foreground/80 ring-1 ring-inset ring-white/10"
                        title="Command name on your PATH"
                      >
                        {tool.cliName}
                      </code>
                    )}
                  </div>
                  <p className="mt-0.5 truncate text-xs text-muted-foreground sm:text-sm">{tool.name}</p>
                </div>
              </div>

              {/* Stars and link */}
              <div className="flex shrink-0 items-center gap-1.5 sm:gap-2">
                {tool.stars && (
                  <span
                    className="relative inline-flex items-center gap-1 overflow-hidden rounded-full bg-gradient-to-r from-accent/20 via-accent/15 to-accent/20 px-2 py-1 text-xs font-bold text-accent ring-1 ring-inset ring-accent/30 transition duration-300 hover:ring-accent/50 sm:gap-1.5 sm:px-3 sm:py-1.5 sm:text-xs"
                    style={{
                      boxShadow: "0 0 15px -3px rgba(251, 191, 36, 0.3)",
                    }}
                    aria-label={`${formatStarCountFull(tool.stars)} GitHub stars`}
                    title={`${formatStarCountFull(tool.stars)} stars`}
                  >
                    {/* Shimmer effect */}
                    <span className="absolute inset-0 -translate-x-full bg-gradient-to-r from-transparent via-white/10 to-transparent transition-transform duration-[1500ms] ease-in-out motion-reduce:transition-none motion-safe:group-hover:translate-x-full" aria-hidden="true" />
                    <Star className="relative h-3 w-3 fill-accent text-accent drop-shadow-[0_0_3px_rgba(251,191,36,0.5)] sm:h-3.5 sm:w-3.5" aria-hidden="true" />
                    <span className="relative font-mono tracking-tight">{formatStarCount(tool.stars)}</span>
                  </span>
                )}
                <Link
                  href={tool.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/5 text-muted-foreground ring-1 ring-white/10 transition duration-200 hover:bg-white/10 hover:text-white hover:ring-white/20 sm:h-11 sm:w-11"
                  aria-label={`View ${tool.name} on GitHub`}
                >
                  <ExternalLink className="h-4 w-4" />
                </Link>
              </div>
            </div>

            {/* What it does */}
            <p className="mt-3 text-xs leading-relaxed text-foreground/80 sm:mt-4 sm:text-sm">
              {tool.whatItDoes}
            </p>

            {/* Representative command (from the manifest) */}
            {tool.commandExample && (
              <div
                className="mt-3 flex items-center gap-2 overflow-x-auto rounded-lg bg-black/30 px-3 py-2 ring-1 ring-inset ring-white/10 outline-none focus-visible:ring-primary/60"
                tabIndex={0}
              >
                <Terminal className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden="true" />
                <code className="whitespace-nowrap font-mono text-xs text-primary">
                  {tool.commandExample}
                </code>
              </div>
            )}
          </div>

          {/* Full content */}
          <div className="flex-1 border-t border-border/50">
            <div className="space-y-4 p-4 sm:space-y-5 sm:p-5">
              {/* Why it's useful */}
              <div>
                <h4 className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  <span className="h-px flex-1 bg-gradient-to-r from-border to-transparent" />
                  Why It&apos;s Useful
                  <span className="h-px flex-1 bg-gradient-to-l from-border to-transparent" />
                </h4>
                <p className="text-xs leading-relaxed text-foreground/80 sm:text-sm">
                  {tool.whyItsUseful}
                </p>
              </div>

              {/* Key features */}
              <div>
                <h4 className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  <span className="h-px flex-1 bg-gradient-to-r from-border to-transparent" />
                  Key Features
                  <span className="h-px flex-1 bg-gradient-to-l from-border to-transparent" />
                </h4>
                <ul className="space-y-1.5 sm:space-y-2">
                  {tool.keyFeatures.map((feature) => (
                    <FeatureItem key={feature} feature={feature} />
                  ))}
                </ul>
              </div>

              {/* Tech stack */}
              <div>
                <h4 className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  <span className="h-px flex-1 bg-gradient-to-r from-border to-transparent" />
                  Tech Stack
                  <span className="h-px flex-1 bg-gradient-to-l from-border to-transparent" />
                </h4>
                <div className="flex flex-wrap gap-1.5 sm:gap-2">
                  {tool.techStack.map((tech) => (
                    <TechBadge key={tech} tech={tech} />
                  ))}
                </div>
              </div>

              {/* Synergies */}
              {tool.synergies.length > 0 && (
                <div>
                  <h4 className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                    <span className="h-px flex-1 bg-gradient-to-r from-border to-transparent" />
                    Synergies
                    <span className="h-px flex-1 bg-gradient-to-l from-border to-transparent" />
                  </h4>
                  {/* minmax(0,1fr) lets a pill shrink below its text width so
                      the description truncates instead of the pill overflowing
                      the card on phones. */}
                  <div className="grid grid-cols-[minmax(0,1fr)] gap-1.5 sm:grid-cols-[repeat(2,minmax(0,1fr))] sm:gap-2">
                    {tool.synergies.map((synergy) => (
                      <SynergyPill
                        key={synergy.toolId}
                        synergy={synergy}
                        allTools={allTools}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

export default TldrToolCard;
