"use client";

import React, { useState, useMemo, useCallback, useEffect } from "react";
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
  Sparkles,
} from "lucide-react";
import { flywheelTools, flywheelDescription, getAllConnections, type FlywheelTool } from "@/lib/flywheel";
import { Button } from "@/components/ui/button";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  LayoutGrid,
  ShieldCheck,
  Mail,
  GitBranch,
  Bug,
  Brain,
  Search,
  KeyRound,
};

// Layout constants
const CONTAINER_SIZE = 480;
const RADIUS = 170;
const CENTER = CONTAINER_SIZE / 2;
const NODE_SIZE = 80;

// Calculate node positions in a circle
function getNodePosition(index: number, total: number) {
  const angle = (index / total) * 2 * Math.PI - Math.PI / 2;
  return {
    x: CENTER + Math.cos(angle) * RADIUS,
    y: CENTER + Math.sin(angle) * RADIUS,
  };
}

// Generate a curved path between two points
function getCurvedPath(from: { x: number; y: number }, to: { x: number; y: number }) {
  const midX = (from.x + to.x) / 2;
  const midY = (from.y + to.y) / 2;
  const pullFactor = 0.35;
  const controlX = midX + (CENTER - midX) * pullFactor;
  const controlY = midY + (CENTER - midY) * pullFactor;
  return `M ${from.x} ${from.y} Q ${controlX} ${controlY} ${to.x} ${to.y}`;
}

// Connection line component
function ConnectionLine({
  fromPos,
  toPos,
  isHighlighted,
  fromColor,
  toColor,
  connectionId,
}: {
  fromPos: { x: number; y: number };
  toPos: { x: number; y: number };
  isHighlighted: boolean;
  fromColor: string;
  toColor: string;
  connectionId: string;
}) {
  const path = getCurvedPath(fromPos, toPos);
  const gradientId = `gradient-${connectionId}`;

  // Extract color for gradient
  const getColor = (colorClass: string) => {
    const colorMap: Record<string, string> = {
      "from-sky-400": "#38bdf8",
      "from-violet-400": "#a78bfa",
      "from-rose-400": "#fb7185",
      "from-emerald-400": "#34d399",
      "from-cyan-400": "#22d3ee",
      "from-pink-400": "#f472b6",
      "from-amber-400": "#fbbf24",
      "from-yellow-400": "#facc15",
    };
    for (const [key, value] of Object.entries(colorMap)) {
      if (colorClass.includes(key)) return value;
    }
    return "#a78bfa";
  };

  const color1 = getColor(fromColor);
  const color2 = getColor(toColor);

  return (
    <g>
      <defs>
        <linearGradient
          id={gradientId}
          gradientUnits="userSpaceOnUse"
          x1={fromPos.x}
          y1={fromPos.y}
          x2={toPos.x}
          y2={toPos.y}
        >
          <stop offset="0%" stopColor={color1} stopOpacity={isHighlighted ? 0.9 : 0.25} />
          <stop offset="100%" stopColor={color2} stopOpacity={isHighlighted ? 0.9 : 0.25} />
        </linearGradient>
      </defs>

      {/* Glow effect when highlighted */}
      {isHighlighted && (
        <path
          d={path}
          fill="none"
          stroke={`url(#${gradientId})`}
          strokeWidth={8}
          strokeLinecap="round"
          style={{ filter: "blur(6px)", opacity: 0.5 }}
        />
      )}

      {/* Main connection line */}
      <path
        d={path}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={isHighlighted ? 2.5 : 1.5}
        strokeLinecap="round"
        className="transition-all duration-300"
      />

      {/* Animated flowing dash */}
      <path
        d={path}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={isHighlighted ? 2 : 1}
        strokeLinecap="round"
        strokeDasharray="12 38"
        className="animate-flow"
        style={{
          opacity: isHighlighted ? 0.8 : 0.4,
          animation: `flow ${isHighlighted ? 2 : 4}s linear infinite`,
        }}
      />
    </g>
  );
}

// Tool node component
function ToolNode({
  tool,
  position,
  index,
  isSelected,
  isConnected,
  isDimmed,
  onSelect,
  onHover,
}: {
  tool: FlywheelTool;
  position: { x: number; y: number };
  index: number;
  isSelected: boolean;
  isConnected: boolean;
  isDimmed: boolean;
  onSelect: () => void;
  onHover: (hovering: boolean) => void;
}) {
  const Icon = iconMap[tool.icon] || Zap;

  return (
    <div
      className="absolute transition-all duration-300"
      style={{
        left: position.x - NODE_SIZE / 2,
        top: position.y - NODE_SIZE / 2,
        width: NODE_SIZE,
        height: NODE_SIZE,
        opacity: isDimmed ? 0.35 : 1,
        transform: `scale(${isSelected ? 1.1 : 1})`,
        animationDelay: `${index * 0.1}s`,
      }}
    >
      <button
        onClick={onSelect}
        onMouseEnter={() => onHover(true)}
        onMouseLeave={() => onHover(false)}
        aria-label={`${tool.name}: ${tool.tagline}`}
        aria-pressed={isSelected}
        className={`
          relative flex h-full w-full flex-col items-center justify-center gap-1.5 rounded-2xl border p-2
          transition-all duration-200 outline-none
          focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background
          ${
            isSelected
              ? "border-white/50 bg-white/20 shadow-xl"
              : isConnected
              ? "border-white/30 bg-white/10"
              : "border-white/10 bg-card/80 hover:border-white/25 hover:bg-white/10"
          }
        `}
      >
        {/* Glow background */}
        <div
          className={`absolute inset-0 rounded-2xl blur-xl bg-gradient-to-br ${tool.color} transition-opacity duration-300`}
          style={{ opacity: isSelected ? 0.6 : isConnected ? 0.35 : 0.15 }}
        />

        {/* Icon */}
        <div
          className={`relative z-10 flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg ${tool.color}`}
        >
          <Icon className="h-5 w-5 text-white" />
        </div>

        {/* Label */}
        <span className="relative z-10 text-xs font-bold uppercase tracking-wider text-white">
          {tool.shortName}
        </span>

        {/* Star count badge */}
        {tool.stars && tool.stars >= 100 && (
          <div className="absolute -right-1 -top-1 flex items-center gap-0.5 rounded-full bg-amber-500/20 px-1.5 py-0.5 text-[10px] font-bold text-amber-400">
            <Star className="h-2.5 w-2.5 fill-current" />
            {tool.stars >= 1000 ? `${(tool.stars / 1000).toFixed(0)}K` : tool.stars}
          </div>
        )}
      </button>
    </div>
  );
}

// Center hub component
function CenterHub() {
  return (
    <div
      className="absolute"
      style={{
        left: CENTER - 36,
        top: CENTER - 36,
        width: 72,
        height: 72,
      }}
    >
      <div className="flex h-full w-full items-center justify-center rounded-full border border-primary/40 bg-primary/20 animate-glow-pulse">
        <Sparkles className="h-8 w-8 text-primary" />
      </div>
    </div>
  );
}

// Tool detail panel
function ToolDetailPanel({
  tool,
  onClose,
}: {
  tool: FlywheelTool;
  onClose: () => void;
}) {
  const Icon = iconMap[tool.icon] || Zap;
  const [copied, setCopied] = useState(false);

  const copyInstallCommand = async () => {
    if (!tool.installCommand) return;

    try {
      await navigator.clipboard.writeText(tool.installCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for older browsers or when clipboard permission is denied
      const textArea = document.createElement("textarea");
      textArea.value = tool.installCommand;
      textArea.style.position = "fixed";
      textArea.style.opacity = "0";
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // Silent fail - user can manually copy
      }
      document.body.removeChild(textArea);
    }
  };

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border/50 bg-card/90 backdrop-blur-xl animate-scale-in">
      {/* Background gradient */}
      <div className={`absolute inset-0 opacity-10 bg-gradient-to-br ${tool.color}`} />

      <div className="relative p-6">
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-4">
            <div
              className={`flex h-14 w-14 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg ${tool.color}`}
            >
              <Icon className="h-7 w-7 text-white" />
            </div>
            <div>
              <h3 className="text-xl font-bold text-foreground">{tool.name}</h3>
              <p className="text-sm text-muted-foreground">{tool.tagline}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="hidden lg:flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Description */}
        <p className="mt-4 text-sm leading-relaxed text-muted-foreground">{tool.description}</p>

        {/* Stars badge */}
        {tool.stars && (
          <div className="mt-4 inline-flex items-center gap-1.5 rounded-full bg-amber-500/10 px-3 py-1 text-sm font-semibold text-amber-400">
            <Star className="h-4 w-4 fill-current" />
            <span>{tool.stars.toLocaleString()} GitHub stars</span>
          </div>
        )}

        {/* Features */}
        <div className="mt-5">
          <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">Key Features</h4>
          <ul className="space-y-1.5">
            {tool.features.slice(0, 4).map((feature, i) => (
              <li key={i} className="flex items-start gap-2 text-sm text-foreground">
                <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                <span>{feature}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* Install command */}
        {tool.installCommand && (
          <div className="mt-5">
            <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">Quick Install</h4>
            <div className="flex items-center gap-2 rounded-lg bg-muted/50 p-3 font-mono text-xs">
              <code className="flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-foreground">
                {tool.installCommand.length > 50 ? tool.installCommand.slice(0, 50) + "..." : tool.installCommand}
              </code>
              <button
                onClick={copyInstallCommand}
                className="shrink-0 rounded p-1.5 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                aria-label="Copy install command"
              >
                {copied ? <Check className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4" />}
              </button>
            </div>
          </div>
        )}

        {/* Action buttons */}
        <div className="mt-5 flex flex-wrap gap-2">
          <Button asChild size="sm" className={`bg-gradient-to-r ${tool.color} text-white hover:opacity-90`}>
            <a href={tool.href} target="_blank" rel="noopener noreferrer">
              <ExternalLink className="mr-1.5 h-4 w-4" />
              View on GitHub
            </a>
          </Button>
          {tool.demoUrl && (
            <Button asChild size="sm" variant="outline">
              <a href={tool.demoUrl} target="_blank" rel="noopener noreferrer">
                Try Demo
                <ChevronRight className="ml-1 h-4 w-4" />
              </a>
            </Button>
          )}
        </div>

        {/* Connections */}
        <div className="mt-6 border-t border-border/50 pt-5">
          <h4 className="mb-3 text-xs font-bold uppercase tracking-wider text-muted-foreground">Integrates With</h4>
          <div className="space-y-2">
            {tool.connectsTo.map((targetId) => {
              const targetTool = flywheelTools.find((t) => t.id === targetId);
              if (!targetTool) return null;
              const TargetIcon = iconMap[targetTool.icon] || Zap;

              return (
                <div
                  key={targetId}
                  className="flex items-center gap-3 rounded-xl bg-muted/30 p-3 border border-border/30"
                >
                  <div
                    className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${targetTool.color}`}
                  >
                    <TargetIcon className="h-4 w-4 text-white" />
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
      </div>
    </div>
  );
}

// Placeholder panel
function PlaceholderPanel() {
  return (
    <div className="rounded-2xl border border-border/50 bg-card/60 p-6 backdrop-blur-sm animate-scale-in">
      <div className="flex flex-col items-center justify-center py-8 text-center">
        <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-primary/10 ring-1 ring-primary/30">
          <Sparkles className="h-7 w-7 text-primary" />
        </div>
        <h3 className="mb-2 text-lg font-semibold text-foreground">Explore the Flywheel</h3>
        <p className="text-sm text-muted-foreground">Click a tool to see its connections and features</p>
      </div>
      <div className="rounded-xl bg-muted/30 p-4 border border-border/30">
        <p className="text-sm leading-relaxed text-muted-foreground">{flywheelDescription.description}</p>
      </div>
    </div>
  );
}

// Mobile bottom sheet
function MobileBottomSheet({
  tool,
  onClose,
}: {
  tool: FlywheelTool | null;
  onClose: () => void;
}) {
  useEffect(() => {
    if (tool) {
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = "";
      };
    }
    return;
  }, [tool]);

  if (!tool) return null;

  const Icon = iconMap[tool.icon] || Zap;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm lg:hidden animate-fade-in"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Sheet */}
      <div className="fixed inset-x-0 bottom-0 z-50 lg:hidden animate-slide-up">
        <div className="flex max-h-[70vh] flex-col rounded-t-3xl border-t border-border/50 bg-card/95 backdrop-blur-xl">
          {/* Handle */}
          <div className="flex shrink-0 justify-center pt-3 pb-2">
            <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
          </div>

          {/* Scrollable content - iOS needs overscroll-contain for proper scrolling */}
          <div
            className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-8"
            style={{ WebkitOverflowScrolling: 'touch' }}
          >
            {/* Header */}
            <div className="flex items-center gap-4 py-4">
              <div
                className={`flex h-14 w-14 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg ${tool.color}`}
              >
                <Icon className="h-7 w-7 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="text-xl font-bold text-foreground">{tool.name}</h3>
                <p className="text-sm text-muted-foreground">{tool.tagline}</p>
              </div>
              <button
                onClick={onClose}
                className="flex h-11 w-11 items-center justify-center rounded-full bg-muted text-foreground"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            {/* Description */}
            <p className="text-sm leading-relaxed text-muted-foreground">{tool.description}</p>

            {/* Action button */}
            <Button asChild className={`mt-5 w-full bg-gradient-to-r ${tool.color} text-white`}>
              <a href={tool.href} target="_blank" rel="noopener noreferrer">
                View on GitHub
                <ExternalLink className="ml-2 h-4 w-4" />
              </a>
            </Button>

            {/* Connections */}
            <div className="mt-6">
              <h4 className="mb-3 text-xs font-bold uppercase tracking-wider text-muted-foreground">Integrates With</h4>
              <div className="space-y-2">
                {tool.connectsTo.map((targetId) => {
                  const targetTool = flywheelTools.find((t) => t.id === targetId);
                  if (!targetTool) return null;
                  const TargetIcon = iconMap[targetTool.icon] || Zap;

                  return (
                    <div
                      key={targetId}
                      className="flex items-center gap-3 rounded-xl bg-muted/30 p-3 border border-border/30"
                    >
                      <div
                        className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${targetTool.color}`}
                      >
                        <TargetIcon className="h-5 w-5 text-white" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold text-foreground">{targetTool.shortName}</p>
                        <p className="text-xs text-muted-foreground">
                          {tool.connectionDescriptions[targetId] || "Integration"}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}

// Stats badge
function StatsBadge() {
  return (
    <div className="mt-6 flex justify-center">
      <div className="inline-flex items-center gap-3 rounded-full border border-primary/20 bg-primary/5 px-4 py-2 backdrop-blur-sm">
        <div className="flex items-center gap-1.5">
          <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/20">
            <Zap className="h-3 w-3 text-primary" />
          </div>
          <span className="text-sm font-semibold text-foreground">{flywheelDescription.metrics.toolCount}</span>
          <span className="text-xs text-muted-foreground">tools</span>
        </div>
        <div className="h-4 w-px bg-primary/30" />
        <div className="flex items-center gap-1.5">
          <Star className="h-4 w-4 text-amber-400 fill-current" />
          <span className="text-sm font-semibold text-foreground">{flywheelDescription.metrics.totalStars}</span>
          <span className="text-xs text-muted-foreground">stars</span>
        </div>
        <div className="h-4 w-px bg-primary/30" />
        <div className="flex items-center gap-1">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75"></span>
            <span className="relative inline-flex h-2 w-2 rounded-full bg-green-500"></span>
          </span>
          <span className="text-[12px] text-green-400">Active</span>
        </div>
      </div>
    </div>
  );
}

// Main component
export default function FlywheelVisualization() {
  const [selectedToolId, setSelectedToolId] = useState<string | null>(null);
  const [hoveredToolId, setHoveredToolId] = useState<string | null>(null);

  const activeToolId = selectedToolId || hoveredToolId;
  const displayedTool = flywheelTools.find((t) => t.id === activeToolId) ?? null;
  const selectedTool = flywheelTools.find((t) => t.id === selectedToolId) ?? null;

  // Calculate positions
  const positions = useMemo(() => {
    return flywheelTools.reduce((acc, tool, index) => {
      acc[tool.id] = getNodePosition(index, flywheelTools.length);
      return acc;
    }, {} as Record<string, { x: number; y: number }>);
  }, []);

  // Get connections
  const connections = useMemo(() => getAllConnections(), []);

  const isConnectionHighlighted = useCallback(
    (from: string, to: string) => {
      if (!activeToolId) return false;
      const activeTool = flywheelTools.find((t) => t.id === activeToolId);
      if (!activeTool) return false;
      return (
        (from === activeToolId && activeTool.connectsTo.includes(to)) ||
        (to === activeToolId && activeTool.connectsTo.includes(from))
      );
    },
    [activeToolId]
  );

  const isToolConnected = useCallback(
    (toolId: string) => {
      if (!activeToolId || toolId === activeToolId) return false;
      const activeTool = flywheelTools.find((t) => t.id === activeToolId);
      return activeTool?.connectsTo.includes(toolId) ?? false;
    },
    [activeToolId]
  );

  const handleSelectTool = useCallback((toolId: string) => {
    setSelectedToolId((prev) => (prev === toolId ? null : toolId));
  }, []);

  const handleCloseDetail = useCallback(() => {
    setSelectedToolId(null);
  }, []);

  return (
    <div className="relative">
      {/* Header */}
      <div className="mb-8 md:mb-12 text-center">
        <div className="mb-4 flex items-center justify-center gap-3">
          <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
          <span className="text-[12px] font-bold uppercase tracking-[0.25em] text-primary">Ecosystem</span>
          <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
        </div>
        <h2 className="mb-4 font-mono text-2xl md:text-3xl lg:text-4xl font-bold tracking-tight text-foreground">
          {flywheelDescription.title}
        </h2>
        <p className="mx-auto max-w-2xl text-sm md:text-base text-muted-foreground">
          {flywheelDescription.subtitle}
        </p>
      </div>

      <div className="grid gap-8 lg:grid-cols-[1fr,380px] xl:grid-cols-[1fr,420px]">
        {/* Flywheel visualization */}
        <div className="relative flex flex-col items-center justify-center">
          {/* Responsive wrapper - clip overflow on mobile */}
          <div className="w-full max-w-[312px] sm:max-w-[384px] md:max-w-[480px] aspect-square overflow-hidden">
            <div
              className="relative origin-top-left scale-[0.65] sm:scale-[0.8] md:scale-100"
              style={{ width: CONTAINER_SIZE, height: CONTAINER_SIZE }}
            >
            {/* SVG connections */}
            <svg className="absolute inset-0" width={CONTAINER_SIZE} height={CONTAINER_SIZE} aria-hidden="true">
              <style>
                {`
                  @keyframes flow {
                    from { stroke-dashoffset: 0; }
                    to { stroke-dashoffset: -100; }
                  }
                `}
              </style>

              {/* Decorative rings */}
              <circle
                cx={CENTER}
                cy={CENTER}
                r={RADIUS + 25}
                fill="none"
                stroke="currentColor"
                strokeWidth="1"
                strokeDasharray="8 6"
                className="text-primary/10"
              />
              <circle
                cx={CENTER}
                cy={CENTER}
                r={RADIUS * 0.45}
                fill="none"
                stroke="currentColor"
                strokeWidth="1"
                className="text-primary/5"
              />

              {/* Connection lines */}
              {connections.map(({ from, to }) => {
                const fromTool = flywheelTools.find((t) => t.id === from);
                const toTool = flywheelTools.find((t) => t.id === to);
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
                  />
                );
              })}
            </svg>

            {/* Center hub */}
            <CenterHub />

            {/* Tool nodes */}
            {flywheelTools.map((tool, index) => (
              <ToolNode
                key={tool.id}
                tool={tool}
                position={positions[tool.id]}
                index={index}
                isSelected={tool.id === selectedToolId}
                isConnected={isToolConnected(tool.id)}
                isDimmed={!!activeToolId && tool.id !== activeToolId && !isToolConnected(tool.id)}
                onSelect={() => handleSelectTool(tool.id)}
                onHover={(hovering) => setHoveredToolId(hovering ? tool.id : null)}
              />
            ))}
            </div>
          </div>

          {/* Stats badge */}
          <StatsBadge />
        </div>

        {/* Detail panel (desktop) */}
        <div className="hidden lg:flex lg:flex-col">
          {displayedTool ? (
            <ToolDetailPanel key={displayedTool.id} tool={displayedTool} onClose={handleCloseDetail} />
          ) : (
            <PlaceholderPanel />
          )}
        </div>
      </div>

      {/* Mobile bottom sheet */}
      <MobileBottomSheet tool={selectedTool} onClose={handleCloseDetail} />
    </div>
  );
}
