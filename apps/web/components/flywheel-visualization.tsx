"use client";

import React, { useState, useMemo, useCallback, useEffect, useRef } from "react";
import {
  LayoutGrid,
  ShieldCheck,
  Mail,
  GitBranch,
  Bug,
  Brain,
  Search,
  KeyRound,
  X,
  ExternalLink,
  Zap,
  Star,
  Copy,
  Check,
  ChevronRight,
  ChevronLeft,
  Sparkles,
  Shield,
  GitMerge,
  Cloud,
  Terminal,
  Bot,
  BookOpen,
  Activity,
  Archive,
  FileText,
  ListTodo,
  ShieldAlert,
} from "lucide-react";
import { flywheelTools, flywheelDescription, getAllConnections, type FlywheelTool } from "@/lib/flywheel";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// =============================================================================
// ICON MAP - Extended for all tools
// =============================================================================

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  LayoutGrid,
  ShieldCheck,
  Mail,
  GitBranch,
  Bug,
  Brain,
  Search,
  KeyRound,
  Shield,
  GitMerge,
  Cloud,
  Terminal,
  Bot,
  BookOpen,
  Activity,
  Archive,
  FileText,
  ListTodo,
  ShieldAlert,
  Sparkles,
  Zap,
};

// =============================================================================
// DEDUPLICATED TOOLS - Remove duplicates and get unique tools
// =============================================================================

function getUniqueTools(): FlywheelTool[] {
  const seen = new Set<string>();
  const unique: FlywheelTool[] = [];
  for (const tool of flywheelTools) {
    if (!seen.has(tool.id)) {
      seen.add(tool.id);
      unique.push(tool);
    }
  }
  return unique;
}

// =============================================================================
// TIER CLASSIFICATION - Separate primary (hub) tools from secondary
// =============================================================================

const PRIMARY_TOOL_IDS = new Set([
  "ntm",    // Named Tmux Manager - orchestration hub
  "mail",   // Agent Mail - coordination hub
  "bv",     // Beads Viewer - task management hub
  "cass",   // Session Search - memory hub
  "cm",     // Memory System
  "ubs",    // Bug Scanner
  "slb",    // Safety Layer
  "dcg",    // Destructive Guard
]);

function classifyTools(tools: FlywheelTool[]): { primary: FlywheelTool[]; secondary: FlywheelTool[] } {
  const primary: FlywheelTool[] = [];
  const secondary: FlywheelTool[] = [];

  for (const tool of tools) {
    if (PRIMARY_TOOL_IDS.has(tool.id)) {
      primary.push(tool);
    } else {
      secondary.push(tool);
    }
  }

  return { primary, secondary };
}

// =============================================================================
// LAYOUT CONSTANTS - Refined for visual harmony
// =============================================================================

const DESKTOP_CONFIG = {
  containerSize: 640,
  innerRadius: 150,
  outerRadius: 260,
  innerNodeSize: 76,
  outerNodeSize: 58,
  centerSize: 88,
};

// =============================================================================
// POSITION CALCULATIONS
// =============================================================================

function getCirclePosition(
  index: number,
  total: number,
  radius: number,
  center: number,
  startAngle: number = -Math.PI / 2
) {
  const angle = startAngle + (index / total) * 2 * Math.PI;
  return {
    x: center + Math.cos(angle) * radius,
    y: center + Math.sin(angle) * radius,
  };
}

function getCurvedPath(from: { x: number; y: number }, to: { x: number; y: number }, center: number) {
  const midX = (from.x + to.x) / 2;
  const midY = (from.y + to.y) / 2;
  const pullFactor = 0.35;
  const controlX = midX + (center - midX) * pullFactor;
  const controlY = midY + (center - midY) * pullFactor;
  return `M ${from.x} ${from.y} Q ${controlX} ${controlY} ${to.x} ${to.y}`;
}

// =============================================================================
// COLOR UTILITIES
// =============================================================================

const colorMap: Record<string, string> = {
  "from-sky-400": "#38bdf8",
  "from-sky-500": "#0ea5e9",
  "from-violet-400": "#a78bfa",
  "from-violet-500": "#8b5cf6",
  "from-rose-400": "#fb7185",
  "from-rose-500": "#f43f5e",
  "from-emerald-400": "#34d399",
  "from-emerald-500": "#10b981",
  "from-cyan-400": "#22d3ee",
  "from-cyan-500": "#06b6d4",
  "from-pink-400": "#f472b6",
  "from-pink-500": "#ec4899",
  "from-amber-400": "#fbbf24",
  "from-amber-500": "#f59e0b",
  "from-yellow-400": "#facc15",
  "from-yellow-500": "#eab308",
  "from-teal-500": "#14b8a6",
  "from-indigo-400": "#818cf8",
  "from-indigo-500": "#6366f1",
  "from-blue-500": "#3b82f6",
  "from-red-400": "#f87171",
  "from-red-500": "#ef4444",
  "from-purple-500": "#a855f7",
  "from-orange-500": "#f97316",
};

function getColorFromGradient(colorClass: string): string {
  for (const [key, value] of Object.entries(colorMap)) {
    if (colorClass.includes(key)) return value;
  }
  return "#a78bfa";
}

// =============================================================================
// CONNECTION LINE COMPONENT - Desktop only (Enhanced with glow trails)
// =============================================================================

interface ConnectionLineProps {
  fromPos: { x: number; y: number };
  toPos: { x: number; y: number };
  isHighlighted: boolean;
  fromColor: string;
  toColor: string;
  connectionId: string;
  center: number;
}

function ConnectionLine({
  fromPos,
  toPos,
  isHighlighted,
  fromColor,
  toColor,
  connectionId,
  center,
}: ConnectionLineProps) {
  const path = getCurvedPath(fromPos, toPos, center);
  const gradientId = `gradient-${connectionId}`;
  const glowId = `glow-${connectionId}`;
  const color1 = getColorFromGradient(fromColor);
  const color2 = getColorFromGradient(toColor);

  return (
    <g
      className="transition-all duration-500 ease-out"
      style={{ opacity: isHighlighted ? 1 : 0.25 }}
    >
      <defs>
        <linearGradient
          id={gradientId}
          gradientUnits="userSpaceOnUse"
          x1={fromPos.x}
          y1={fromPos.y}
          x2={toPos.x}
          y2={toPos.y}
        >
          <stop offset="0%" stopColor={color1} stopOpacity={isHighlighted ? 1 : 0.4} />
          <stop offset="50%" stopColor={isHighlighted ? "#fff" : color1} stopOpacity={isHighlighted ? 0.6 : 0.2} />
          <stop offset="100%" stopColor={color2} stopOpacity={isHighlighted ? 1 : 0.4} />
        </linearGradient>
        <filter id={glowId} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation={isHighlighted ? "4" : "2"} result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      {/* Outer glow layer */}
      {isHighlighted && (
        <path
          d={path}
          fill="none"
          stroke={`url(#${gradientId})`}
          strokeWidth={10}
          strokeLinecap="round"
          style={{ filter: "blur(8px)", opacity: 0.4 }}
        />
      )}

      {/* Mid glow layer */}
      <path
        d={path}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={isHighlighted ? 6 : 3}
        strokeLinecap="round"
        style={{ filter: `blur(${isHighlighted ? 4 : 2}px)`, opacity: isHighlighted ? 0.6 : 0.3 }}
      />

      {/* Main line */}
      <path
        d={path}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={isHighlighted ? 2.5 : 1.5}
        strokeLinecap="round"
      />

      {/* Animated energy flow */}
      <path
        d={path}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={isHighlighted ? 2 : 1}
        strokeLinecap="round"
        strokeDasharray={isHighlighted ? "6 18" : "4 20"}
        style={{
          opacity: isHighlighted ? 0.9 : 0.5,
          animation: `flow ${isHighlighted ? 1.5 : 3}s linear infinite`,
        }}
      />
    </g>
  );
}

// =============================================================================
// DESKTOP TOOL NODE - Circular layout nodes (Enhanced with depth & glow)
// =============================================================================

interface DesktopToolNodeProps {
  tool: FlywheelTool;
  position: { x: number; y: number };
  size: number;
  isSelected: boolean;
  isConnected: boolean;
  isDimmed: boolean;
  onSelect: () => void;
  onHover: (hovering: boolean) => void;
  isPrimary: boolean;
  index: number;
}

function DesktopToolNode({
  tool,
  position,
  size,
  isSelected,
  isConnected,
  isDimmed,
  onSelect,
  onHover,
  isPrimary,
  index,
}: DesktopToolNodeProps) {
  const Icon = iconMap[tool.icon] || Zap;
  const iconSize = isPrimary ? "h-6 w-6" : "h-5 w-5";
  const fontSize = isPrimary ? "text-[11px]" : "text-[9px]";
  const color = getColorFromGradient(tool.color);

  return (
    <div
      className="absolute transition-all duration-500 ease-out"
      style={{
        left: position.x - size / 2,
        top: position.y - size / 2,
        width: size,
        height: size,
        opacity: isDimmed ? 0.3 : 1,
        transform: `scale(${isSelected ? 1.15 : isConnected ? 1.05 : 1})`,
        zIndex: isSelected ? 30 : isConnected ? 20 : 10,
        filter: isDimmed ? "grayscale(0.5)" : "none",
        // Subtle floating animation for primary tools
        animation: isPrimary && !isDimmed ? `float${index % 3} 4s ease-in-out infinite` : "none",
      }}
    >
      <button
        onClick={onSelect}
        onMouseEnter={() => onHover(true)}
        onMouseLeave={() => onHover(false)}
        aria-label={`${tool.name}: ${tool.tagline}`}
        aria-pressed={isSelected}
        className={cn(
          "group relative flex h-full w-full flex-col items-center justify-center gap-1.5 rounded-2xl border p-2",
          "transition-all duration-300 ease-out outline-none",
          "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background",
          isSelected
            ? "border-white/60 bg-white/20 shadow-2xl"
            : isConnected
            ? "border-white/40 bg-white/15 shadow-xl"
            : "border-white/15 bg-card/90 hover:border-white/30 hover:bg-white/10 shadow-lg"
        )}
        style={{
          // Color-coordinated shadow
          boxShadow: isSelected
            ? `0 0 40px ${color}50, 0 20px 40px rgba(0,0,0,0.3)`
            : isConnected
            ? `0 0 25px ${color}30, 0 10px 30px rgba(0,0,0,0.2)`
            : `0 8px 24px rgba(0,0,0,0.2)`,
        }}
      >
        {/* Animated gradient ring for selected state */}
        {isSelected && (
          <div
            className="absolute -inset-[2px] rounded-2xl opacity-80"
            style={{
              background: `conic-gradient(from 0deg, ${color}, transparent, ${color})`,
              animation: "spin 3s linear infinite",
            }}
          />
        )}

        {/* Inner container */}
        <div className="absolute inset-[1px] rounded-[14px] bg-card/95" />

        {/* Gradient glow background */}
        <div
          className={cn(
            "absolute inset-0 rounded-2xl blur-xl transition-opacity duration-500 bg-gradient-to-br",
            tool.color
          )}
          style={{ opacity: isSelected ? 0.7 : isConnected ? 0.4 : 0.15 }}
        />

        {/* Shine effect on hover */}
        <div
          className="absolute inset-0 rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500"
          style={{
            background: "linear-gradient(135deg, rgba(255,255,255,0.1) 0%, transparent 50%, rgba(255,255,255,0.05) 100%)",
          }}
        />

        {/* Icon container with glow */}
        <div className="relative z-10">
          <div
            className={cn(
              "relative flex items-center justify-center rounded-xl bg-gradient-to-br shadow-lg",
              tool.color,
              isPrimary ? "h-11 w-11" : "h-9 w-9"
            )}
            style={{
              boxShadow: `0 4px 16px ${color}40`,
            }}
          >
            <Icon className={cn("text-white drop-shadow-sm", iconSize)} />
          </div>
        </div>

        {/* Label */}
        <span className={cn(
          "relative z-10 font-bold uppercase tracking-wider text-white drop-shadow-sm",
          fontSize
        )}>
          {tool.shortName}
        </span>

        {/* Star badge with glow */}
        {tool.stars && tool.stars >= 50 && (
          <div
            className="absolute -right-1 -top-1 flex items-center gap-0.5 rounded-full bg-amber-500/30 px-1.5 py-0.5 text-[8px] font-bold text-amber-300 backdrop-blur-sm border border-amber-400/30"
            style={{ boxShadow: "0 2px 8px rgba(251,191,36,0.3)" }}
          >
            <Star className="h-2 w-2 fill-current" />
            {tool.stars >= 1000 ? `${(tool.stars / 1000).toFixed(0)}K` : tool.stars}
          </div>
        )}
      </button>
    </div>
  );
}

// =============================================================================
// CENTER HUB - Desktop only (Enhanced with animated rings)
// =============================================================================

function CenterHub({ size }: { size: number }) {
  return (
    <div
      className="absolute pointer-events-none"
      style={{
        left: DESKTOP_CONFIG.containerSize / 2 - size / 2,
        top: DESKTOP_CONFIG.containerSize / 2 - size / 2,
        width: size,
        height: size,
      }}
    >
      {/* Outer pulsing ring */}
      <div
        className="absolute inset-0 rounded-full border-2 border-primary/30"
        style={{ animation: "pulse-ring 2s ease-in-out infinite" }}
      />

      {/* Middle animated gradient ring */}
      <div
        className="absolute inset-2 rounded-full"
        style={{
          background: "conic-gradient(from 0deg, transparent, hsl(var(--primary) / 0.3), transparent, hsl(var(--primary) / 0.2), transparent)",
          animation: "spin 8s linear infinite",
        }}
      />

      {/* Inner glow */}
      <div
        className="absolute inset-3 rounded-full bg-primary/20 blur-md"
        style={{ animation: "glow-pulse 3s ease-in-out infinite" }}
      />

      {/* Core content */}
      <div className="absolute inset-3 flex flex-col items-center justify-center rounded-full border border-primary/40 bg-card/90 backdrop-blur-md shadow-xl">
        <div
          className="relative"
          style={{ animation: "float0 3s ease-in-out infinite" }}
        >
          <Sparkles className="h-8 w-8 text-primary drop-shadow-lg" />
          <div className="absolute inset-0 blur-sm">
            <Sparkles className="h-8 w-8 text-primary opacity-50" />
          </div>
        </div>
        <span className="mt-1.5 text-[10px] font-bold uppercase tracking-[0.15em] text-primary/90">
          Flywheel
        </span>
      </div>
    </div>
  );
}

// =============================================================================
// DESKTOP DETAIL PANEL (Enhanced with better visual hierarchy)
// =============================================================================

interface ToolDetailPanelProps {
  tool: FlywheelTool;
  onClose: () => void;
}

function ToolDetailPanel({ tool, onClose }: ToolDetailPanelProps) {
  const Icon = iconMap[tool.icon] || Zap;
  const [copied, setCopied] = useState(false);
  const uniqueTools = useMemo(() => getUniqueTools(), []);
  const color = getColorFromGradient(tool.color);

  const copyInstallCommand = async () => {
    if (!tool.installCommand) return;
    try {
      await navigator.clipboard.writeText(tool.installCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      const textArea = document.createElement("textarea");
      textArea.value = tool.installCommand;
      textArea.style.cssText = "position:fixed;opacity:0";
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // execCommand is deprecated; failure is acceptable as this is a fallback
      }
      document.body.removeChild(textArea);
    }
  };

  return (
    <div
      className="relative overflow-hidden rounded-2xl border border-border/50 bg-card/95 backdrop-blur-xl shadow-2xl"
      style={{
        animation: "panel-enter 0.4s cubic-bezier(0.16, 1, 0.3, 1)",
        boxShadow: `0 0 60px ${color}15, 0 25px 50px rgba(0,0,0,0.25)`,
      }}
    >
      {/* Animated gradient background */}
      <div
        className={cn("absolute inset-0 opacity-[0.08] bg-gradient-to-br", tool.color)}
        style={{ animation: "gradient-shift 8s ease-in-out infinite" }}
      />

      {/* Subtle pattern overlay */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: "radial-gradient(circle at 2px 2px, white 1px, transparent 0)",
          backgroundSize: "24px 24px",
        }}
      />

      <div className="relative p-6">
        {/* Header */}
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <div
              className={cn(
                "relative flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br shadow-xl",
                tool.color
              )}
              style={{ boxShadow: `0 8px 32px ${color}40` }}
            >
              <Icon className="h-8 w-8 text-white drop-shadow-md" />
              {/* Shine effect */}
              <div
                className="absolute inset-0 rounded-2xl"
                style={{
                  background: "linear-gradient(135deg, rgba(255,255,255,0.25) 0%, transparent 50%)",
                }}
              />
            </div>
            <div>
              <h3 className="text-xl font-bold text-foreground">{tool.name}</h3>
              <p className="text-sm text-muted-foreground">{tool.tagline}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="flex h-9 w-9 items-center justify-center rounded-xl text-muted-foreground transition-all hover:bg-muted hover:text-foreground hover:scale-105 active:scale-95"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Description */}
        <p className="mt-5 text-sm leading-relaxed text-muted-foreground">{tool.description}</p>

        {/* Stars badge */}
        {tool.stars && (
          <div
            className="mt-4 inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-4 py-1.5 text-sm font-semibold text-amber-400 border border-amber-400/20"
            style={{ boxShadow: "0 2px 12px rgba(251,191,36,0.15)" }}
          >
            <Star className="h-4 w-4 fill-current" />
            <span>{tool.stars.toLocaleString()} GitHub stars</span>
          </div>
        )}

        {/* Features */}
        <div className="mt-6">
          <h4 className="mb-3 text-xs font-bold uppercase tracking-wider text-muted-foreground">Key Features</h4>
          <ul className="space-y-2">
            {tool.features.slice(0, 4).map((feature, i) => (
              <li
                key={i}
                className="flex items-start gap-2.5 text-sm text-foreground"
                style={{ animation: `fade-in-up 0.3s ease-out ${i * 0.05}s both` }}
              >
                <div
                  className={cn("mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-md bg-gradient-to-br", tool.color)}
                  style={{ boxShadow: `0 2px 8px ${color}30` }}
                >
                  <Check className="h-3 w-3 text-white" />
                </div>
                <span>{feature}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* Install command */}
        {tool.installCommand && (
          <div className="mt-6">
            <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">Quick Install</h4>
            <div className="flex items-center gap-2 rounded-xl bg-black/30 p-3.5 font-mono text-xs border border-border/30 backdrop-blur-sm">
              <code className="flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-foreground">
                {tool.installCommand.length > 45 ? tool.installCommand.slice(0, 45) + "..." : tool.installCommand}
              </code>
              <button
                onClick={copyInstallCommand}
                className={cn(
                  "shrink-0 rounded-lg p-2 transition-all",
                  copied
                    ? "bg-primary/20 text-primary"
                    : "text-muted-foreground hover:bg-white/10 hover:text-foreground"
                )}
                aria-label="Copy install command"
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </button>
            </div>
          </div>
        )}

        {/* Action buttons */}
        <div className="mt-6 flex flex-wrap gap-3">
          <Button
            asChild
            size="sm"
            className={cn(
              "h-11 bg-gradient-to-r text-white shadow-lg hover:opacity-90 hover:shadow-xl transition-all hover:-translate-y-0.5",
              tool.color
            )}
            style={{ boxShadow: `0 4px 20px ${color}40` }}
          >
            <a href={tool.href} target="_blank" rel="noopener noreferrer">
              <ExternalLink className="mr-2 h-4 w-4" />
              View on GitHub
            </a>
          </Button>
          {tool.demoUrl && (
            <Button asChild size="sm" variant="outline" className="h-11 hover:-translate-y-0.5 transition-all">
              <a href={tool.demoUrl} target="_blank" rel="noopener noreferrer">
                Try Demo
                <ChevronRight className="ml-1 h-4 w-4" />
              </a>
            </Button>
          )}
        </div>

        {/* Connections */}
        {tool.connectsTo.length > 0 && (
          <div className="mt-7 border-t border-border/50 pt-6">
            <h4 className="mb-4 text-xs font-bold uppercase tracking-wider text-muted-foreground">Integrates With</h4>
            <div className="space-y-2.5">
              {tool.connectsTo.slice(0, 4).map((targetId, i) => {
                const targetTool = uniqueTools.find((t) => t.id === targetId);
                if (!targetTool) return null;
                const TargetIcon = iconMap[targetTool.icon] || Zap;
                const targetColor = getColorFromGradient(targetTool.color);

                return (
                  <div
                    key={targetId}
                    className="flex items-center gap-3 rounded-xl bg-white/5 p-3 border border-border/30 hover:bg-white/10 transition-colors cursor-default"
                    style={{ animation: `fade-in-up 0.3s ease-out ${i * 0.05}s both` }}
                  >
                    <div
                      className={cn(
                        "flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br shadow-md",
                        targetTool.color
                      )}
                      style={{ boxShadow: `0 4px 12px ${targetColor}30` }}
                    >
                      <TargetIcon className="h-5 w-5 text-white" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold text-foreground">{targetTool.shortName}</p>
                      <p className="text-xs text-muted-foreground line-clamp-1">
                        {tool.connectionDescriptions[targetId] || "Integration"}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// =============================================================================
// PLACEHOLDER PANEL - Desktop only (Enhanced)
// =============================================================================

function PlaceholderPanel() {
  return (
    <div
      className="rounded-2xl border border-border/50 bg-card/80 p-6 backdrop-blur-sm shadow-xl"
      style={{
        boxShadow: "0 0 40px rgba(var(--primary-rgb), 0.05), 0 20px 40px rgba(0,0,0,0.15)",
      }}
    >
      <div className="flex flex-col items-center justify-center py-10 text-center">
        <div
          className="relative mb-5"
          style={{ animation: "float0 3s ease-in-out infinite" }}
        >
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-primary/15 ring-2 ring-primary/30 shadow-lg">
            <Sparkles className="h-9 w-9 text-primary" />
          </div>
          <div className="absolute inset-0 rounded-full bg-primary/10 blur-xl" />
        </div>
        <h3 className="mb-2 text-lg font-semibold text-foreground">Explore the Flywheel</h3>
        <p className="text-sm text-muted-foreground">Click any tool to see details and integrations</p>
      </div>
      <div className="rounded-xl bg-white/5 p-5 border border-border/30">
        <p className="text-sm leading-relaxed text-muted-foreground">{flywheelDescription.description}</p>
      </div>
    </div>
  );
}

// =============================================================================
// MOBILE TOOL CARD - Horizontal carousel cards (Enhanced with depth)
// =============================================================================

interface MobileToolCardProps {
  tool: FlywheelTool;
  isActive: boolean;
  onSelect: () => void;
}

function MobileToolCard({ tool, isActive, onSelect }: MobileToolCardProps) {
  const Icon = iconMap[tool.icon] || Zap;
  const color = getColorFromGradient(tool.color);

  return (
    <button
      onClick={onSelect}
      className={cn(
        "relative flex h-full min-w-[280px] max-w-[280px] flex-col rounded-2xl border p-5 text-left transition-all duration-300 snap-center",
        "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2",
        "active:scale-[0.98]", // Touch feedback
        isActive
          ? "border-white/50 bg-white/15 shadow-2xl scale-[1.02]"
          : "border-white/15 bg-card/90 hover:border-white/25 shadow-lg"
      )}
      style={{
        boxShadow: isActive
          ? `0 0 40px ${color}25, 0 20px 40px rgba(0,0,0,0.3)`
          : "0 8px 24px rgba(0,0,0,0.2)",
      }}
    >
      {/* Active state gradient ring */}
      {isActive && (
        <div
          className="absolute -inset-[1px] rounded-2xl opacity-60"
          style={{
            background: `linear-gradient(135deg, ${color}60, transparent 50%, ${color}40)`,
          }}
        />
      )}

      {/* Inner background */}
      <div className="absolute inset-[1px] rounded-[15px] bg-card/95" style={{ display: isActive ? "block" : "none" }} />

      {/* Gradient glow */}
      <div
        className={cn("absolute inset-0 rounded-2xl blur-xl transition-opacity duration-300 bg-gradient-to-br", tool.color)}
        style={{ opacity: isActive ? 0.35 : 0.1 }}
      />

      {/* Header */}
      <div className="relative z-10 flex items-start gap-3.5">
        <div
          className={cn(
            "flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg",
            tool.color
          )}
          style={{ boxShadow: `0 4px 16px ${color}40` }}
        >
          <Icon className="h-7 w-7 text-white drop-shadow-sm" />
          {/* Shine */}
          <div
            className="absolute inset-0 rounded-xl"
            style={{
              background: "linear-gradient(135deg, rgba(255,255,255,0.2) 0%, transparent 50%)",
            }}
          />
        </div>
        <div className="min-w-0 flex-1 pt-0.5">
          <h3 className="font-bold text-foreground text-base">{tool.shortName}</h3>
          <p className="text-xs text-muted-foreground line-clamp-1 mt-0.5">{tool.tagline}</p>
        </div>
        {tool.stars && tool.stars >= 50 && (
          <div
            className="flex items-center gap-0.5 rounded-full bg-amber-500/25 px-2 py-1 text-[10px] font-bold text-amber-300 border border-amber-400/30"
            style={{ boxShadow: "0 2px 8px rgba(251,191,36,0.2)" }}
          >
            <Star className="h-2.5 w-2.5 fill-current" />
            {tool.stars >= 1000 ? `${(tool.stars / 1000).toFixed(0)}K` : tool.stars}
          </div>
        )}
      </div>

      {/* Description */}
      <p className="relative z-10 mt-4 text-sm leading-relaxed text-muted-foreground line-clamp-3">
        {tool.description}
      </p>

      {/* Footer */}
      <div className="relative z-10 mt-auto pt-4 flex items-center justify-between border-t border-border/30">
        <span className="text-[10px] uppercase tracking-wider text-muted-foreground font-medium">{tool.language}</span>
        <div className={cn(
          "flex items-center gap-1 text-xs font-medium transition-all",
          isActive ? "text-primary translate-x-1" : "text-muted-foreground"
        )}>
          <span>Details</span>
          <ChevronRight className="h-4 w-4" />
        </div>
      </div>
    </button>
  );
}

// =============================================================================
// MOBILE BOTTOM SHEET - Full detail view (Enhanced with gestures)
// =============================================================================

interface MobileBottomSheetProps {
  tool: FlywheelTool | null;
  onClose: () => void;
}

function MobileBottomSheet({ tool, onClose }: MobileBottomSheetProps) {
  const [copied, setCopied] = useState(false);
  const uniqueTools = useMemo(() => getUniqueTools(), []);
  const sheetRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [dragY, setDragY] = useState(0);
  const startY = useRef(0);

  // Reset drag state when tool changes
  const toolId = tool?.id;
  const prevToolId = useRef(toolId);
  if (toolId !== prevToolId.current) {
    prevToolId.current = toolId;
    // dragY will be reset naturally since we only set it during touch interactions
  }

  useEffect(() => {
    if (tool) {
      document.body.style.overflow = "hidden";

      // Handle escape key
      const handleEscape = (e: KeyboardEvent) => {
        if (e.key === "Escape") onClose();
      };
      document.addEventListener("keydown", handleEscape);

      return () => {
        document.body.style.overflow = "";
        document.removeEventListener("keydown", handleEscape);
      };
    }
    return;
  }, [tool, onClose]);

  // Touch gesture handling for swipe-to-dismiss
  const handleTouchStart = (e: React.TouchEvent) => {
    startY.current = e.touches[0].clientY;
    setIsDragging(true);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!isDragging) return;
    const deltaY = e.touches[0].clientY - startY.current;
    if (deltaY > 0) {
      setDragY(deltaY);
    }
  };

  const handleTouchEnd = () => {
    setIsDragging(false);
    if (dragY > 100) {
      onClose();
    }
    setDragY(0);
  };

  const copyInstallCommand = async () => {
    if (!tool?.installCommand) return;
    try {
      await navigator.clipboard.writeText(tool.installCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      const textArea = document.createElement("textarea");
      textArea.value = tool.installCommand;
      textArea.style.cssText = "position:fixed;opacity:0";
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // execCommand is deprecated; failure is acceptable as this is a fallback
      }
      document.body.removeChild(textArea);
    }
  };

  if (!tool) return null;

  const Icon = iconMap[tool.icon] || Zap;
  const color = getColorFromGradient(tool.color);

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md lg:hidden"
        onClick={onClose}
        aria-hidden="true"
        style={{
          animation: "fadeIn 200ms ease-out",
          opacity: isDragging ? 1 - dragY / 300 : 1,
        }}
      />

      {/* Sheet */}
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`${tool.name} details`}
        ref={sheetRef}
        className="fixed inset-x-0 bottom-0 z-50 lg:hidden touch-none"
        style={{
          animation: "slideUp 350ms cubic-bezier(0.16, 1, 0.3, 1)",
          transform: `translateY(${dragY}px)`,
          transition: isDragging ? "none" : "transform 0.3s cubic-bezier(0.16, 1, 0.3, 1)",
        }}
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
      >
        <div
          className="flex max-h-[90vh] flex-col rounded-t-3xl border-t border-border/50 bg-card/98 backdrop-blur-xl shadow-2xl"
          style={{ boxShadow: `0 -10px 60px ${color}20, 0 -20px 40px rgba(0,0,0,0.4)` }}
        >
          {/* Handle - larger touch target */}
          <div className="flex shrink-0 justify-center pt-4 pb-3">
            <div
              className={cn(
                "h-1.5 w-14 rounded-full transition-colors",
                isDragging ? "bg-muted-foreground/60" : "bg-muted-foreground/30"
              )}
            />
          </div>

          {/* Content */}
          <div
            className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-12"
            style={{ WebkitOverflowScrolling: "touch" }}
          >
            {/* Header */}
            <div className="flex items-center gap-4 py-4">
              <div
                className={cn(
                  "relative flex items-center justify-center rounded-2xl bg-gradient-to-br shadow-xl",
                  tool.color
                )}
                style={{
                  width: 72,
                  height: 72,
                  boxShadow: `0 8px 32px ${color}40`,
                }}
              >
                <Icon className="h-9 w-9 text-white drop-shadow-md" />
                <div
                  className="absolute inset-0 rounded-2xl"
                  style={{
                    background: "linear-gradient(135deg, rgba(255,255,255,0.25) 0%, transparent 50%)",
                  }}
                />
              </div>
              <div className="flex-1">
                <h3 className="text-xl font-bold text-foreground">{tool.name}</h3>
                <p className="text-sm text-muted-foreground mt-0.5">{tool.tagline}</p>
              </div>
              <button
                onClick={onClose}
                className="flex h-12 w-12 items-center justify-center rounded-full bg-muted/80 text-foreground active:scale-95 transition-transform"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            {/* Stars */}
            {tool.stars && (
              <div
                className="inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-4 py-2 text-sm font-semibold text-amber-400 border border-amber-400/20"
                style={{ boxShadow: "0 2px 12px rgba(251,191,36,0.15)" }}
              >
                <Star className="h-4 w-4 fill-current" />
                <span>{tool.stars.toLocaleString()} stars</span>
              </div>
            )}

            {/* Description */}
            <p className="mt-5 text-sm leading-relaxed text-muted-foreground">{tool.description}</p>

            {/* Install command */}
            {tool.installCommand && (
              <div className="mt-6">
                <h4 className="mb-3 text-xs font-bold uppercase tracking-wider text-muted-foreground">Install</h4>
                <button
                  onClick={copyInstallCommand}
                  className={cn(
                    "flex w-full items-center gap-3 rounded-xl p-4 font-mono text-xs text-left transition-all active:scale-[0.98]",
                    copied ? "bg-primary/20 border-primary/30" : "bg-black/30 border-border/30",
                    "border"
                  )}
                >
                  <code className="flex-1 text-foreground break-all">
                    {tool.installCommand.length > 55 ? tool.installCommand.slice(0, 55) + "..." : tool.installCommand}
                  </code>
                  {copied ? (
                    <Check className="h-5 w-5 text-primary shrink-0" />
                  ) : (
                    <Copy className="h-5 w-5 text-muted-foreground shrink-0" />
                  )}
                </button>
              </div>
            )}

            {/* Primary action */}
            <Button
              asChild
              className={cn(
                "mt-6 w-full h-14 bg-gradient-to-r text-white shadow-lg text-base font-semibold",
                tool.color
              )}
              style={{ boxShadow: `0 8px 32px ${color}40` }}
            >
              <a href={tool.href} target="_blank" rel="noopener noreferrer">
                View on GitHub
                <ExternalLink className="ml-2 h-5 w-5" />
              </a>
            </Button>

            {/* Features */}
            <div className="mt-8">
              <h4 className="mb-4 text-xs font-bold uppercase tracking-wider text-muted-foreground">Key Features</h4>
              <ul className="space-y-3">
                {tool.features.slice(0, 5).map((feature, i) => (
                  <li key={i} className="flex items-start gap-3 text-sm text-foreground">
                    <div
                      className={cn("mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br", tool.color)}
                      style={{ boxShadow: `0 2px 8px ${color}30` }}
                    >
                      <Check className="h-3.5 w-3.5 text-white" />
                    </div>
                    <span>{feature}</span>
                  </li>
                ))}
              </ul>
            </div>

            {/* Connections */}
            {tool.connectsTo.length > 0 && (
              <div className="mt-8 border-t border-border/50 pt-6">
                <h4 className="mb-4 text-xs font-bold uppercase tracking-wider text-muted-foreground">
                  Integrates With
                </h4>
                <div className="space-y-3">
                  {tool.connectsTo.slice(0, 5).map((targetId) => {
                    const targetTool = uniqueTools.find((t) => t.id === targetId);
                    if (!targetTool) return null;
                    const TargetIcon = iconMap[targetTool.icon] || Zap;
                    const targetColor = getColorFromGradient(targetTool.color);

                    return (
                      <div
                        key={targetId}
                        className="flex items-center gap-3 rounded-xl bg-white/5 p-3.5 border border-border/30"
                      >
                        <div
                          className={cn(
                            "flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br shadow-md",
                            targetTool.color
                          )}
                          style={{ boxShadow: `0 4px 12px ${targetColor}30` }}
                        >
                          <TargetIcon className="h-6 w-6 text-white" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-semibold text-foreground">{targetTool.shortName}</p>
                          <p className="text-xs text-muted-foreground mt-0.5">
                            {tool.connectionDescriptions[targetId] || "Integration"}
                          </p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

// =============================================================================
// STATS BADGE (Enhanced with glassmorphism)
// =============================================================================

function StatsBadge({ toolCount }: { toolCount: number }) {
  return (
    <div className="flex justify-center">
      <div
        className="inline-flex items-center gap-4 rounded-full border border-primary/25 bg-primary/10 px-5 py-2.5 backdrop-blur-md shadow-lg"
        style={{ boxShadow: "0 4px 24px rgba(var(--primary-rgb), 0.15)" }}
      >
        <div className="flex items-center gap-2">
          <div
            className="flex h-6 w-6 items-center justify-center rounded-full bg-primary/25"
            style={{ boxShadow: "0 2px 8px rgba(var(--primary-rgb), 0.2)" }}
          >
            <Zap className="h-3.5 w-3.5 text-primary" />
          </div>
          <span className="text-sm font-bold text-foreground">{toolCount}</span>
          <span className="text-xs text-muted-foreground">tools</span>
        </div>
        <div className="h-5 w-px bg-primary/30" />
        <div className="flex items-center gap-2">
          <Star className="h-4 w-4 text-amber-400 fill-current drop-shadow-sm" />
          <span className="text-sm font-bold text-foreground">{flywheelDescription.metrics.totalStars}</span>
          <span className="text-xs text-muted-foreground">stars</span>
        </div>
        <div className="h-5 w-px bg-primary/30" />
        <div className="flex items-center gap-1.5">
          <span className="relative flex h-2.5 w-2.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-green-500 shadow-sm" style={{ boxShadow: "0 0 8px rgba(34,197,94,0.5)" }} />
          </span>
          <span className="text-xs font-medium text-green-400">Active</span>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// DESKTOP VISUALIZATION - Two-tier concentric rings (Enhanced)
// =============================================================================

interface DesktopVisualizationProps {
  tools: FlywheelTool[];
  selectedToolId: string | null;
  hoveredToolId: string | null;
  onSelectTool: (id: string) => void;
  onHoverTool: (id: string | null) => void;
}

function DesktopVisualization({
  tools,
  selectedToolId,
  hoveredToolId,
  onSelectTool,
  onHoverTool,
}: DesktopVisualizationProps) {
  const { primary, secondary } = useMemo(() => classifyTools(tools), [tools]);
  const activeToolId = selectedToolId || hoveredToolId;
  const center = DESKTOP_CONFIG.containerSize / 2;

  const positions = useMemo(() => {
    const pos: Record<string, { x: number; y: number }> = {};

    primary.forEach((tool, index) => {
      pos[tool.id] = getCirclePosition(index, primary.length, DESKTOP_CONFIG.innerRadius, center);
    });

    secondary.forEach((tool, index) => {
      pos[tool.id] = getCirclePosition(index, secondary.length, DESKTOP_CONFIG.outerRadius, center);
    });

    return pos;
  }, [primary, secondary, center]);

  const connections = useMemo(() => getAllConnections(), []);

  const isConnectionHighlighted = useCallback(
    (from: string, to: string) => {
      if (!activeToolId) return false;
      const activeTool = tools.find((t) => t.id === activeToolId);
      if (!activeTool) return false;
      return (
        (from === activeToolId && activeTool.connectsTo.includes(to)) ||
        (to === activeToolId && activeTool.connectsTo.includes(from))
      );
    },
    [activeToolId, tools]
  );

  const isToolConnected = useCallback(
    (toolId: string) => {
      if (!activeToolId || toolId === activeToolId) return false;
      const activeTool = tools.find((t) => t.id === activeToolId);
      return activeTool?.connectsTo.includes(toolId) ?? false;
    },
    [activeToolId, tools]
  );

  return (
    <div
      className="relative mx-auto"
      style={{ width: DESKTOP_CONFIG.containerSize, height: DESKTOP_CONFIG.containerSize }}
    >
      {/* Ambient background glow */}
      <div
        className="absolute inset-0 rounded-full bg-primary/5 blur-3xl"
        style={{ transform: "scale(1.2)" }}
      />

      {/* SVG connections */}
      <svg
        className="absolute inset-0"
        width={DESKTOP_CONFIG.containerSize}
        height={DESKTOP_CONFIG.containerSize}
        aria-hidden="true"
      >
        <defs>
          {/* Ambient glow for center */}
          <radialGradient id="center-glow" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.15" />
            <stop offset="70%" stopColor="hsl(var(--primary))" stopOpacity="0.05" />
            <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
          </radialGradient>
        </defs>

        <style>
          {`
            @keyframes flow {
              from { stroke-dashoffset: 0; }
              to { stroke-dashoffset: -48; }
            }
            @keyframes spin {
              from { transform: rotate(0deg); }
              to { transform: rotate(360deg); }
            }
            @keyframes pulse-ring {
              0%, 100% { transform: scale(1); opacity: 0.3; }
              50% { transform: scale(1.05); opacity: 0.6; }
            }
            @keyframes glow-pulse {
              0%, 100% { opacity: 0.4; }
              50% { opacity: 0.7; }
            }
            @keyframes float0 {
              0%, 100% { transform: translateY(0px); }
              50% { transform: translateY(-4px); }
            }
            @keyframes float1 {
              0%, 100% { transform: translateY(0px); }
              50% { transform: translateY(-3px); }
            }
            @keyframes float2 {
              0%, 100% { transform: translateY(0px); }
              50% { transform: translateY(-5px); }
            }
            @keyframes panel-enter {
              from { opacity: 0; transform: translateX(10px); }
              to { opacity: 1; transform: translateX(0); }
            }
            @keyframes gradient-shift {
              0%, 100% { opacity: 0.08; }
              50% { opacity: 0.12; }
            }
            @keyframes fade-in-up {
              from { opacity: 0; transform: translateY(8px); }
              to { opacity: 1; transform: translateY(0); }
            }
          `}
        </style>

        {/* Center ambient glow */}
        <circle
          cx={center}
          cy={center}
          r={DESKTOP_CONFIG.innerRadius * 0.9}
          fill="url(#center-glow)"
        />

        {/* Decorative orbital rings */}
        <circle
          cx={center}
          cy={center}
          r={DESKTOP_CONFIG.innerRadius}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeDasharray="6 8"
          className="text-primary/15"
        />
        <circle
          cx={center}
          cy={center}
          r={DESKTOP_CONFIG.outerRadius}
          fill="none"
          stroke="currentColor"
          strokeWidth="1"
          strokeDasharray="4 10"
          className="text-primary/10"
        />

        {/* Connection lines */}
        {connections.map(({ from, to }) => {
          const fromTool = tools.find((t) => t.id === from);
          const toTool = tools.find((t) => t.id === to);
          const fromPos = positions[from];
          const toPos = positions[to];
          if (!fromPos || !toPos || !fromTool || !toTool) return null;

          return (
            <ConnectionLine
              key={`${from}-${to}`}
              fromPos={fromPos}
              toPos={toPos}
              isHighlighted={isConnectionHighlighted(from, to)}
              fromColor={fromTool.color}
              toColor={toTool.color}
              connectionId={`${from}-${to}`}
              center={center}
            />
          );
        })}
      </svg>

      {/* Center hub */}
      <CenterHub size={DESKTOP_CONFIG.centerSize} />

      {/* Primary tools (inner ring) */}
      {primary.map((tool, index) => (
        <DesktopToolNode
          key={tool.id}
          tool={tool}
          position={positions[tool.id]}
          size={DESKTOP_CONFIG.innerNodeSize}
          isSelected={tool.id === selectedToolId}
          isConnected={isToolConnected(tool.id)}
          isDimmed={!!activeToolId && tool.id !== activeToolId && !isToolConnected(tool.id)}
          onSelect={() => onSelectTool(tool.id)}
          onHover={(hovering) => onHoverTool(hovering ? tool.id : null)}
          isPrimary={true}
          index={index}
        />
      ))}

      {/* Secondary tools (outer ring) */}
      {secondary.map((tool, index) => (
        <DesktopToolNode
          key={tool.id}
          tool={tool}
          position={positions[tool.id]}
          size={DESKTOP_CONFIG.outerNodeSize}
          isSelected={tool.id === selectedToolId}
          isConnected={isToolConnected(tool.id)}
          isDimmed={!!activeToolId && tool.id !== activeToolId && !isToolConnected(tool.id)}
          onSelect={() => onSelectTool(tool.id)}
          onHover={(hovering) => onHoverTool(hovering ? tool.id : null)}
          isPrimary={false}
          index={index}
        />
      ))}
    </div>
  );
}

// =============================================================================
// MOBILE VISUALIZATION - Horizontal carousel (Enhanced)
// =============================================================================

interface MobileVisualizationProps {
  tools: FlywheelTool[];
  selectedToolId: string | null;
  onSelectTool: (id: string) => void;
}

function MobileVisualization({ tools, selectedToolId, onSelectTool }: MobileVisualizationProps) {
  const coreScrollRef = useRef<HTMLDivElement>(null);
  const supportingScrollRef = useRef<HTMLDivElement>(null);
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(true);
  const [activeSection, setActiveSection] = useState<"core" | "supporting">("core");
  const { primary, secondary } = useMemo(() => classifyTools(tools), [tools]);

  const checkScroll = useCallback(() => {
    const el = activeSection === "core" ? coreScrollRef.current : supportingScrollRef.current;
    if (!el) return;
    setCanScrollLeft(el.scrollLeft > 10);
    setCanScrollRight(el.scrollLeft < el.scrollWidth - el.clientWidth - 10);
  }, [activeSection]);

  useEffect(() => {
    const coreEl = coreScrollRef.current;
    const supportingEl = supportingScrollRef.current;

    const handleCoreScroll = () => {
      setActiveSection("core");
      checkScroll();
    };
    const handleSupportingScroll = () => {
      setActiveSection("supporting");
      checkScroll();
    };

    checkScroll();
    coreEl?.addEventListener("scroll", handleCoreScroll, { passive: true });
    supportingEl?.addEventListener("scroll", handleSupportingScroll, { passive: true });

    return () => {
      coreEl?.removeEventListener("scroll", handleCoreScroll);
      supportingEl?.removeEventListener("scroll", handleSupportingScroll);
    };
  }, [checkScroll]);

  const scroll = (direction: "left" | "right") => {
    const el = activeSection === "core" ? coreScrollRef.current : supportingScrollRef.current;
    if (!el) return;
    const scrollAmount = 300;
    el.scrollBy({ left: direction === "left" ? -scrollAmount : scrollAmount, behavior: "smooth" });
  };

  return (
    <div className="relative -mx-4 sm:-mx-6">
      {/* Navigation arrows - appear on interaction */}
      <button
        onClick={() => scroll("left")}
        disabled={!canScrollLeft}
        className={cn(
          "absolute left-2 top-1/2 z-20 -translate-y-1/2 flex h-11 w-11 items-center justify-center rounded-full bg-card/95 border border-border/50 backdrop-blur-md shadow-xl transition-all active:scale-95",
          canScrollLeft ? "opacity-100" : "opacity-0 pointer-events-none"
        )}
        style={{ boxShadow: canScrollLeft ? "0 4px 20px rgba(0,0,0,0.3)" : "none" }}
        aria-label="Scroll left"
      >
        <ChevronLeft className="h-5 w-5" />
      </button>
      <button
        onClick={() => scroll("right")}
        disabled={!canScrollRight}
        className={cn(
          "absolute right-2 top-1/2 z-20 -translate-y-1/2 flex h-11 w-11 items-center justify-center rounded-full bg-card/95 border border-border/50 backdrop-blur-md shadow-xl transition-all active:scale-95",
          canScrollRight ? "opacity-100" : "opacity-0 pointer-events-none"
        )}
        style={{ boxShadow: canScrollRight ? "0 4px 20px rgba(0,0,0,0.3)" : "none" }}
        aria-label="Scroll right"
      >
        <ChevronRight className="h-5 w-5" />
      </button>

      {/* Primary tools section */}
      <div className="mb-8">
        <div className="mb-4 px-4 sm:px-6 flex items-center gap-2">
          <div className="flex h-6 w-6 items-center justify-center rounded-lg bg-primary/20">
            <Sparkles className="h-3.5 w-3.5 text-primary" />
          </div>
          <h3 className="text-xs font-bold uppercase tracking-wider text-primary">Core Tools</h3>
          <span className="text-xs text-muted-foreground">({primary.length})</span>
        </div>
        <div
          ref={coreScrollRef}
          className="flex gap-4 overflow-x-auto px-4 sm:px-6 pb-3 snap-x snap-mandatory scrollbar-hide"
          style={{ WebkitOverflowScrolling: "touch" }}
          onFocus={() => setActiveSection("core")}
        >
          {primary.map((tool) => (
            <MobileToolCard
              key={tool.id}
              tool={tool}
              isActive={tool.id === selectedToolId}
              onSelect={() => onSelectTool(tool.id)}
            />
          ))}
        </div>
      </div>

      {/* Secondary tools section */}
      {secondary.length > 0 && (
        <div>
          <div className="mb-4 px-4 sm:px-6 flex items-center gap-2">
            <div className="flex h-6 w-6 items-center justify-center rounded-lg bg-muted">
              <Zap className="h-3.5 w-3.5 text-muted-foreground" />
            </div>
            <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Supporting Tools</h3>
            <span className="text-xs text-muted-foreground">({secondary.length})</span>
          </div>
          <div
            ref={supportingScrollRef}
            className="flex gap-4 overflow-x-auto px-4 sm:px-6 pb-3 snap-x snap-mandatory scrollbar-hide"
            style={{ WebkitOverflowScrolling: "touch" }}
            onFocus={() => setActiveSection("supporting")}
          >
            {secondary.map((tool) => (
              <MobileToolCard
                key={tool.id}
                tool={tool}
                isActive={tool.id === selectedToolId}
                onSelect={() => onSelectTool(tool.id)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

export default function FlywheelVisualization() {
  const [selectedToolId, setSelectedToolId] = useState<string | null>(null);
  const [hoveredToolId, setHoveredToolId] = useState<string | null>(null);

  const uniqueTools = useMemo(() => getUniqueTools(), []);
  const activeToolId = selectedToolId || hoveredToolId;
  const displayedTool = uniqueTools.find((t) => t.id === activeToolId) ?? null;
  const selectedTool = uniqueTools.find((t) => t.id === selectedToolId) ?? null;

  const handleSelectTool = useCallback((toolId: string) => {
    setSelectedToolId((prev) => (prev === toolId ? null : toolId));
  }, []);

  const handleCloseDetail = useCallback(() => {
    setSelectedToolId(null);
  }, []);

  return (
    <div className="relative">
      {/* Header with refined typography */}
      <div className="mb-10 md:mb-14 text-center">
        <div className="mb-5 flex items-center justify-center gap-3">
          <div className="h-px w-10 bg-gradient-to-r from-transparent via-primary/60 to-transparent" />
          <span className="text-[11px] font-bold uppercase tracking-[0.3em] text-primary">Ecosystem</span>
          <div className="h-px w-10 bg-gradient-to-l from-transparent via-primary/60 to-transparent" />
        </div>
        <h2 className="mb-5 font-mono text-2xl md:text-3xl lg:text-4xl font-bold tracking-tight text-foreground">
          {flywheelDescription.title}
        </h2>
        <p className="mx-auto max-w-2xl text-sm md:text-base text-muted-foreground leading-relaxed">
          {flywheelDescription.subtitle}
        </p>
      </div>

      {/* Desktop layout */}
      <div className="hidden lg:grid lg:grid-cols-[1fr,400px] xl:grid-cols-[1fr,440px] gap-10">
        <div className="flex flex-col items-center justify-center">
          <DesktopVisualization
            tools={uniqueTools}
            selectedToolId={selectedToolId}
            hoveredToolId={hoveredToolId}
            onSelectTool={handleSelectTool}
            onHoverTool={setHoveredToolId}
          />
          <div className="mt-10">
            <StatsBadge toolCount={uniqueTools.length} />
          </div>
        </div>

        <div className="flex flex-col">
          {displayedTool ? (
            <ToolDetailPanel key={displayedTool.id} tool={displayedTool} onClose={handleCloseDetail} />
          ) : (
            <PlaceholderPanel />
          )}
        </div>
      </div>

      {/* Mobile/Tablet layout */}
      <div className="lg:hidden">
        <MobileVisualization
          tools={uniqueTools}
          selectedToolId={selectedToolId}
          onSelectTool={handleSelectTool}
        />
        <div className="mt-10">
          <StatsBadge toolCount={uniqueTools.length} />
        </div>
      </div>

      {/* Mobile bottom sheet */}
      <MobileBottomSheet tool={selectedTool} onClose={handleCloseDetail} />

      {/* CSS animations */}
      <style jsx global>{`
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes slideUp {
          from { transform: translateY(100%); }
          to { transform: translateY(0); }
        }
        .scrollbar-hide {
          -ms-overflow-style: none;
          scrollbar-width: none;
        }
        .scrollbar-hide::-webkit-scrollbar {
          display: none;
        }
      `}</style>
    </div>
  );
}
