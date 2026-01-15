"use client";

import Link from "next/link";
import { useRef, useState, useCallback, useMemo } from "react";
import { motion, useReducedMotion } from "framer-motion";
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

  return (
    <div className="group/synergy relative flex items-center gap-2 rounded-lg bg-white/5 px-2 py-1.5 transition-colors hover:bg-white/10 sm:px-3 sm:py-2">
      <div
        className={cn(
          "flex h-5 w-5 shrink-0 items-center justify-center rounded-md bg-gradient-to-br sm:h-6 sm:w-6",
          linkedTool.color
        )}
      >
        <DynamicIcon name={linkedTool.icon} className="h-2.5 w-2.5 text-white sm:h-3 sm:w-3" />
      </div>
      <div className="min-w-0 flex-1">
        <span className="block text-xs font-semibold text-white sm:text-xs">
          {linkedTool.shortName}
        </span>
        <span className="block truncate text-xs text-muted-foreground group-hover/synergy:text-foreground/70 sm:text-xs">
          {synergy.description}
        </span>
      </div>
    </div>
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

  const spotlightRgb = getColorDefinition(tool.color).rgb;

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
        onMouseEnter={() => setSpotlightOpacity(1)}
        onMouseLeave={() => setSpotlightOpacity(0)}
        className={cn(
          "relative h-full flex flex-col overflow-hidden rounded-xl sm:rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm",
          "transition-all duration-300",
          "hover:border-border hover:bg-card/70",
          "active:scale-[0.98] active:border-border"
        )}
      >
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
            background: `radial-gradient(400px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), rgba(${spotlightRgb}, 0.15), transparent 40%)`,
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
                    "flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg sm:h-12 sm:w-12",
                    tool.color
                  )}
                >
                  <DynamicIcon name={tool.icon} className="h-5 w-5 text-white sm:h-6 sm:w-6" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-base font-bold text-white sm:text-lg">
                      {tool.shortName}
                    </h3>
                    {tool.category === "core" && (
                      <span className="rounded-full bg-primary/20 px-2 py-0.5 text-xs font-bold uppercase tracking-wider text-primary sm:text-xs">
                        Core
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 truncate text-xs text-muted-foreground sm:text-sm">{tool.name}</p>
                </div>
              </div>

              {/* Stars and link */}
              <div className="flex shrink-0 items-center gap-1.5 sm:gap-2">
                {tool.stars && (
                  <span
                    className="relative inline-flex items-center gap-1 overflow-hidden rounded-full bg-gradient-to-r from-accent/20 via-accent/15 to-accent/20 px-2 py-1 text-xs font-bold text-accent shadow-lg shadow-accent/10 ring-1 ring-inset ring-accent/30 transition-all duration-300 hover:ring-accent/50 hover:shadow-accent/20 sm:gap-1.5 sm:px-3 sm:py-1.5 sm:text-xs"
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
                  className="flex h-10 w-10 items-center justify-center rounded-lg bg-white/5 text-muted-foreground transition-colors hover:bg-white/10 hover:text-white sm:h-11 sm:w-11"
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
          </div>

          {/* Full content */}
          <div className="flex-1 border-t border-border/50">
            <div className="space-y-4 p-4 sm:space-y-5 sm:p-5">
              {/* Why it's useful */}
              <div>
                <h4 className="mb-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  Why It&apos;s Useful
                </h4>
                <p className="text-xs leading-relaxed text-foreground/80 sm:text-sm">
                  {tool.whyItsUseful}
                </p>
              </div>

              {/* Key features */}
              <div>
                <h4 className="mb-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  Key Features
                </h4>
                <ul className="space-y-1 sm:space-y-1.5">
                  {tool.keyFeatures.map((feature) => (
                    <li
                      key={feature}
                      className="flex items-start gap-2 text-xs text-foreground/80 sm:text-sm"
                    >
                      <ArrowUpRight className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground sm:h-4 sm:w-4" aria-hidden="true" />
                      {feature}
                    </li>
                  ))}
                </ul>
              </div>

              {/* Tech stack */}
              <div>
                <h4 className="mb-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                  Tech Stack
                </h4>
                <div className="flex flex-wrap gap-1.5 sm:gap-2">
                  {tool.techStack.map((tech) => (
                    <span
                      key={tech}
                      className="rounded-md bg-white/5 px-1.5 py-0.5 text-xs font-medium text-muted-foreground sm:px-2 sm:py-1 sm:text-xs"
                    >
                      {tech}
                    </span>
                  ))}
                </div>
              </div>

              {/* Synergies */}
              {tool.synergies.length > 0 && (
                <div>
                  <h4 className="mb-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground sm:mb-2 sm:text-xs">
                    Synergies
                  </h4>
                  <div className="grid gap-1.5 sm:gap-2 sm:grid-cols-2">
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
