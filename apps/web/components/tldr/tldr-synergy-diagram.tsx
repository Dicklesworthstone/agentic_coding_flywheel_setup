"use client";

import { useRef, useMemo, useState, useCallback } from "react";
import { motion, useReducedMotion, useInView } from "@/components/motion";
import { cn } from "@/lib/utils";
import { getColorDefinition } from "@/lib/colors";
import type { TldrFlywheelTool } from "@/lib/tldr-content";

// =============================================================================
// TYPES
// =============================================================================

interface TldrSynergyDiagramProps {
  tools: TldrFlywheelTool[];
  className?: string;
}

interface NodePosition {
  x: number;
  y: number;
}

// =============================================================================
// CONSTANTS - Two-tier concentric layout with refined proportions
// =============================================================================

const DIAGRAM_CONFIG = {
  viewBoxSize: 520,
  center: 260,
  innerRadius: 105,
  innerNodeRadius: 28,
  outerRadius: 195,
  outerNodeRadius: 24,
  centerRadius: 44,
};

// Primary tools shown in the inner ring (most connected/important)
const PRIMARY_TOOL_IDS = new Set([
  "mail",   // Agent Mail - coordination hub
  "bv",     // Beads Viewer - task management hub
  "cass",   // Session Search - memory hub
  "cm",     // Memory System
  "ubs",    // Bug Scanner
  "ntm",    // Named Tmux Manager
]);

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

function getCirclePosition(
  index: number,
  total: number,
  radius: number,
  center: number,
  startAngle: number = -Math.PI / 2
): NodePosition {
  const angle = startAngle + (index / total) * 2 * Math.PI;
  return {
    x: center + Math.cos(angle) * radius,
    y: center + Math.sin(angle) * radius,
  };
}

function classifyTools(tools: TldrFlywheelTool[]): {
  primary: TldrFlywheelTool[];
  secondary: TldrFlywheelTool[];
} {
  const coreTools = tools.filter((t) => t.category === "core");
  const primary: TldrFlywheelTool[] = [];
  const secondary: TldrFlywheelTool[] = [];

  for (const tool of coreTools) {
    if (PRIMARY_TOOL_IDS.has(tool.id)) {
      primary.push(tool);
    } else {
      secondary.push(tool);
    }
  }

  return { primary, secondary };
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

export function TldrSynergyDiagram({
  tools,
  className,
}: TldrSynergyDiagramProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(containerRef, { once: true, margin: "-50px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [hoveredNode, setHoveredNode] = useState<string | null>(null);

  // Classify tools into two tiers
  const { primary, secondary } = useMemo(() => classifyTools(tools), [tools]);

  // Calculate node positions for both rings
  const nodePositions = useMemo(() => {
    const positions: Record<string, NodePosition> = {};
    const { center, innerRadius, outerRadius } = DIAGRAM_CONFIG;

    // Inner ring (primary tools)
    primary.forEach((tool, index) => {
      positions[tool.id] = getCirclePosition(index, primary.length, innerRadius, center);
    });

    // Outer ring (secondary tools)
    secondary.forEach((tool, index) => {
      positions[tool.id] = getCirclePosition(index, secondary.length, outerRadius, center);
    });

    return positions;
  }, [primary, secondary]);

  // Generate connection lines between synergistic tools
  const connections = useMemo(() => {
    const allCoreTools = [...primary, ...secondary];
    const lines: Array<{
      from: string;
      to: string;
      fromPos: NodePosition;
      toPos: NodePosition;
    }> = [];
    const seen = new Set<string>();

    allCoreTools.forEach((tool) => {
      tool.synergies.forEach((synergy) => {
        const targetTool = allCoreTools.find((t) => t.id === synergy.toolId);
        if (targetTool && nodePositions[tool.id] && nodePositions[synergy.toolId]) {
          const key = [tool.id, synergy.toolId].sort().join("-");
          if (!seen.has(key)) {
            seen.add(key);
            lines.push({
              from: tool.id,
              to: synergy.toolId,
              fromPos: nodePositions[tool.id],
              toPos: nodePositions[synergy.toolId],
            });
          }
        }
      });
    });

    return lines;
  }, [primary, secondary, nodePositions]);

  // Check if a connection should be highlighted
  const isConnectionHighlighted = useCallback((from: string, to: string) => {
    if (!hoveredNode) return false;
    return from === hoveredNode || to === hoveredNode;
  }, [hoveredNode]);

  const totalCoreTools = primary.length + secondary.length;

  return (
    <div ref={containerRef} className={cn("relative", className)}>
      <motion.div
        initial={reducedMotion ? {} : { opacity: 0, scale: 0.95 }}
        animate={isInView ? { opacity: 1, scale: 1 } : {}}
        transition={{ duration: reducedMotion ? 0 : 0.6 }}
        className="mx-auto max-w-md"
      >
        <svg
          viewBox={`0 0 ${DIAGRAM_CONFIG.viewBoxSize} ${DIAGRAM_CONFIG.viewBoxSize}`}
          className="h-auto w-full"
          aria-label="Flywheel tool synergy diagram showing connections between core tools"
        >
          {/* Definitions */}
          <defs>
            {/* Center glow gradient */}
            <radialGradient id="tldr-centerGlow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.3" />
              <stop offset="60%" stopColor="hsl(var(--primary))" stopOpacity="0.1" />
              <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
            </radialGradient>

            {/* Ambient outer glow */}
            <radialGradient id="tldr-ambientGlow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.08" />
              <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
            </radialGradient>

            {/* Line gradient */}
            <linearGradient id="tldr-lineGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.5" />
              <stop offset="50%" stopColor="hsl(var(--primary))" stopOpacity="0.8" />
              <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0.5" />
            </linearGradient>

            {/* Highlighted line gradient */}
            <linearGradient id="tldr-lineGradientHighlight" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.8" />
              <stop offset="50%" stopColor="#fff" stopOpacity="0.9" />
              <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0.8" />
            </linearGradient>

            {/* Tool-specific gradients */}
            {[...primary, ...secondary].map((tool) => (
              <linearGradient
                key={`tldr-gradient-${tool.id}`}
                id={`tldr-gradient-${tool.id}`}
                x1="0%"
                y1="0%"
                x2="100%"
                y2="100%"
              >
                <stop offset="0%" stopColor={getColorDefinition(tool.color).from} />
                <stop offset="100%" stopColor={getColorDefinition(tool.color).to} />
              </linearGradient>
            ))}

            {/* Glow filter for highlighted state */}
            <filter id="tldr-glow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Background ambient glow */}
          <circle
            cx={DIAGRAM_CONFIG.center}
            cy={DIAGRAM_CONFIG.center}
            r={DIAGRAM_CONFIG.outerRadius + 50}
            fill="url(#tldr-ambientGlow)"
          />

          {/* Center glow effect */}
          <circle
            cx={DIAGRAM_CONFIG.center}
            cy={DIAGRAM_CONFIG.center}
            r={DIAGRAM_CONFIG.innerRadius * 0.85}
            fill="url(#tldr-centerGlow)"
          />

          {/* Decorative orbital rings with animation */}
          <circle
            cx={DIAGRAM_CONFIG.center}
            cy={DIAGRAM_CONFIG.center}
            r={DIAGRAM_CONFIG.innerRadius}
            fill="none"
            stroke="hsl(var(--primary) / 0.15)"
            strokeWidth="1.5"
            strokeDasharray="6 8"
          />
          <circle
            cx={DIAGRAM_CONFIG.center}
            cy={DIAGRAM_CONFIG.center}
            r={DIAGRAM_CONFIG.outerRadius}
            fill="none"
            stroke="hsl(var(--primary) / 0.08)"
            strokeWidth="1"
            strokeDasharray="4 10"
          />

          {/* Connection lines */}
          <g className="connections">
            {connections.map((conn, index) => {
              const isHighlighted = isConnectionHighlighted(conn.from, conn.to);
              return (
                <g key={`${conn.from}-${conn.to}`}>
                  {/* Glow layer when highlighted */}
                  {isHighlighted && (
                    <motion.line
                      x1={conn.fromPos.x}
                      y1={conn.fromPos.y}
                      x2={conn.toPos.x}
                      y2={conn.toPos.y}
                      stroke="url(#tldr-lineGradientHighlight)"
                      strokeWidth="6"
                      strokeLinecap="round"
                      style={{ filter: "blur(4px)", opacity: 0.5 }}
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 0.5 }}
                    />
                  )}
                  {/* Main line */}
                  <motion.line
                    x1={conn.fromPos.x}
                    y1={conn.fromPos.y}
                    x2={conn.toPos.x}
                    y2={conn.toPos.y}
                    stroke={isHighlighted ? "url(#tldr-lineGradientHighlight)" : "url(#tldr-lineGradient)"}
                    strokeWidth={isHighlighted ? 2 : 1}
                    strokeLinecap="round"
                    initial={reducedMotion ? {} : { opacity: 0 }}
                    animate={isInView ? { opacity: isHighlighted ? 1 : 0.5 } : {}}
                    transition={{
                      duration: reducedMotion ? 0 : 0.6,
                      delay: reducedMotion ? 0 : 0.3 + index * 0.02,
                    }}
                  />
                  {/* Animated flow particles */}
                  <motion.line
                    x1={conn.fromPos.x}
                    y1={conn.fromPos.y}
                    x2={conn.toPos.x}
                    y2={conn.toPos.y}
                    stroke={isHighlighted ? "url(#tldr-lineGradientHighlight)" : "url(#tldr-lineGradient)"}
                    strokeWidth={isHighlighted ? 1.5 : 0.75}
                    strokeLinecap="round"
                    strokeDasharray={isHighlighted ? "4 14" : "3 18"}
                    initial={reducedMotion ? {} : { opacity: 0 }}
                    animate={isInView ? { opacity: isHighlighted ? 0.9 : 0.4 } : {}}
                    transition={{
                      duration: reducedMotion ? 0 : 0.6,
                      delay: reducedMotion ? 0 : 0.3 + index * 0.02,
                    }}
                    style={{
                      animation: reducedMotion ? "none" : `tldr-flow ${isHighlighted ? 1.5 : 2.5}s linear infinite`,
                    }}
                  />
                </g>
              );
            })}
          </g>

          {/* Center "Flywheel" label */}
          <motion.g
            initial={reducedMotion ? {} : { opacity: 0, scale: 0.8 }}
            animate={isInView ? { opacity: 1, scale: 1 } : {}}
            transition={{
              duration: reducedMotion ? 0 : 0.5,
              delay: reducedMotion ? 0 : 0.2,
            }}
          >
            {/* Outer ring */}
            <circle
              cx={DIAGRAM_CONFIG.center}
              cy={DIAGRAM_CONFIG.center}
              r={DIAGRAM_CONFIG.centerRadius + 4}
              fill="none"
              stroke="hsl(var(--primary) / 0.2)"
              strokeWidth="1"
              style={{
                animation: reducedMotion ? "none" : "tldr-pulse-ring 3s ease-in-out infinite",
              }}
            />
            {/* Main circle */}
            <circle
              cx={DIAGRAM_CONFIG.center}
              cy={DIAGRAM_CONFIG.center}
              r={DIAGRAM_CONFIG.centerRadius}
              fill="hsl(var(--card))"
              stroke="hsl(var(--primary) / 0.4)"
              strokeWidth="2"
              filter="url(#tldr-glow)"
            />
            {/* Inner glow */}
            <circle
              cx={DIAGRAM_CONFIG.center}
              cy={DIAGRAM_CONFIG.center}
              r={DIAGRAM_CONFIG.centerRadius - 6}
              fill="hsl(var(--primary) / 0.1)"
            />
            <text
              x={DIAGRAM_CONFIG.center}
              y={DIAGRAM_CONFIG.center - 4}
              textAnchor="middle"
              className="fill-primary text-xs font-bold uppercase tracking-wider"
            >
              Flywheel
            </text>
            <text
              x={DIAGRAM_CONFIG.center}
              y={DIAGRAM_CONFIG.center + 12}
              textAnchor="middle"
              className="fill-muted-foreground text-xs"
            >
              {totalCoreTools} Core Tools
            </text>
          </motion.g>

          {/* Primary tools (inner ring) - larger nodes */}
          {primary.map((tool, index) => {
            const pos = nodePositions[tool.id];
            if (!pos) return null;
            const nodeRadius = DIAGRAM_CONFIG.innerNodeRadius;
            const ringRadius = nodeRadius - 3;
            const isHovered = hoveredNode === tool.id;
            const color = getColorDefinition(tool.color);

            return (
              <motion.g
                key={tool.id}
                initial={reducedMotion ? {} : { opacity: 0, scale: 0 }}
                animate={isInView ? { opacity: 1, scale: 1 } : {}}
                transition={{
                  duration: reducedMotion ? 0 : 0.4,
                  delay: reducedMotion ? 0 : 0.4 + index * 0.05,
                  type: "spring",
                  stiffness: 200,
                }}
                onMouseEnter={() => setHoveredNode(tool.id)}
                onMouseLeave={() => setHoveredNode(null)}
                style={{ cursor: "pointer" }}
              >
                {/* Glow effect on hover */}
                {isHovered && (
                  <circle
                    cx={pos.x}
                    cy={pos.y}
                    r={nodeRadius + 8}
                    fill={color.from}
                    opacity="0.25"
                    style={{ filter: "blur(8px)" }}
                  />
                )}

                {/* Node background with shadow */}
                <circle
                  cx={pos.x}
                  cy={pos.y}
                  r={nodeRadius}
                  fill="hsl(var(--card))"
                  stroke={isHovered ? color.from : "hsl(var(--border) / 0.5)"}
                  strokeWidth={isHovered ? 2 : 1}
                  style={{
                    filter: isHovered ? `drop-shadow(0 4px 12px ${color.from}40)` : "drop-shadow(0 2px 4px rgba(0,0,0,0.2))",
                    transition: "all 0.3s ease-out",
                  }}
                />

                {/* Gradient ring */}
                <circle
                  cx={pos.x}
                  cy={pos.y}
                  r={ringRadius}
                  fill="none"
                  stroke={`url(#tldr-gradient-${tool.id})`}
                  strokeWidth={isHovered ? 3.5 : 2.5}
                  opacity={isHovered ? 1 : 0.75}
                  style={{ transition: "all 0.3s ease-out" }}
                />

                {/* Inner glow */}
                <circle
                  cx={pos.x}
                  cy={pos.y}
                  r={ringRadius - 6}
                  fill={color.from}
                  opacity={isHovered ? 0.2 : 0.1}
                />

                {/* Tool label */}
                <text
                  x={pos.x}
                  y={pos.y + 4}
                  textAnchor="middle"
                  className="fill-white font-bold text-[10px] drop-shadow-sm"
                  style={{ textShadow: "0 1px 2px rgba(0,0,0,0.5)" }}
                >
                  {tool.shortName}
                </text>
              </motion.g>
            );
          })}

          {/* Secondary tools (outer ring) - smaller nodes */}
          {secondary.map((tool, index) => {
            const pos = nodePositions[tool.id];
            if (!pos) return null;
            const nodeRadius = DIAGRAM_CONFIG.outerNodeRadius;
            const ringRadius = nodeRadius - 3;
            const isHovered = hoveredNode === tool.id;
            const color = getColorDefinition(tool.color);

            return (
              <motion.g
                key={tool.id}
                initial={reducedMotion ? {} : { opacity: 0, scale: 0 }}
                animate={isInView ? { opacity: 1, scale: 1 } : {}}
                transition={{
                  duration: reducedMotion ? 0 : 0.4,
                  delay: reducedMotion ? 0 : 0.5 + index * 0.04,
                  type: "spring",
                  stiffness: 200,
                }}
                onMouseEnter={() => setHoveredNode(tool.id)}
                onMouseLeave={() => setHoveredNode(null)}
                style={{ cursor: "pointer" }}
              >
                {/* Glow effect on hover */}
                {isHovered && (
                  <circle
                    cx={pos.x}
                    cy={pos.y}
                    r={nodeRadius + 6}
                    fill={color.from}
                    opacity="0.2"
                    style={{ filter: "blur(6px)" }}
                  />
                )}

                {/* Node background */}
                <circle
                  cx={pos.x}
                  cy={pos.y}
                  r={nodeRadius}
                  fill="hsl(var(--card))"
                  stroke={isHovered ? color.from : "hsl(var(--border) / 0.4)"}
                  strokeWidth={isHovered ? 1.5 : 1}
                  style={{
                    filter: isHovered ? `drop-shadow(0 3px 10px ${color.from}30)` : "drop-shadow(0 1px 3px rgba(0,0,0,0.15))",
                    transition: "all 0.3s ease-out",
                  }}
                />

                {/* Gradient ring */}
                <circle
                  cx={pos.x}
                  cy={pos.y}
                  r={ringRadius}
                  fill="none"
                  stroke={`url(#tldr-gradient-${tool.id})`}
                  strokeWidth={isHovered ? 2.5 : 2}
                  opacity={isHovered ? 0.9 : 0.6}
                  style={{ transition: "all 0.3s ease-out" }}
                />

                {/* Tool label */}
                <text
                  x={pos.x}
                  y={pos.y + 3}
                  textAnchor="middle"
                  className="fill-white font-bold text-[8px] drop-shadow-sm"
                  style={{ textShadow: "0 1px 2px rgba(0,0,0,0.5)" }}
                >
                  {tool.shortName}
                </text>
              </motion.g>
            );
          })}

          {/* CSS animations embedded in SVG */}
          <style>
            {`
              @keyframes tldr-flow {
                from { stroke-dashoffset: 0; }
                to { stroke-dashoffset: -36; }
              }
              @keyframes tldr-pulse-ring {
                0%, 100% { opacity: 0.2; transform-origin: center; transform: scale(1); }
                50% { opacity: 0.5; transform-origin: center; transform: scale(1.05); }
              }
            `}
          </style>
        </svg>

        {/* Legend */}
        <motion.div
          initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.8 }}
          className="mt-6 text-center"
        >
          <p className="text-xs text-muted-foreground">
            {hoveredNode ? (
              <span className="text-primary font-medium">
                Showing connections for {[...primary, ...secondary].find(t => t.id === hoveredNode)?.shortName ?? hoveredNode}
              </span>
            ) : (
              "Hover over tools to see connections"
            )}
          </p>
        </motion.div>
      </motion.div>
    </div>
  );
}

export default TldrSynergyDiagram;
