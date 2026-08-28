"use client";

import { useState, useCallback, useRef, useEffect, useMemo } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  RefreshCw,
  Cpu,
  Mail,
  Shield,
  ShieldAlert,
  Search,
  Brain,
  LayoutDashboard,
  Users,
  Zap,
  Play,
  Terminal,
  Sparkles,
  CheckCircle2,
  GitMerge,
  Pause,
  RotateCw,
  ChevronRight,
  Target,
  FileCode,
  TestTube,
  Eye,
  Rocket,
  Activity,
  BookOpen,
  Clock,
  TrendingUp,
  Bot,
  type LucideIcon,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
} from "./lesson-components";

export function FlywheelLoopLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand how all the tools work together.
      </GoalBanner>

      {/* The ACFS Flywheel */}
      <Section
        {...{
          title: "The ACFS Flywheel",
          icon: <RefreshCw className="h-5 w-5" />,
          delay: 0.1,
        }}
      >
        <Paragraph>
          This isn&apos;t just a collection of tools. It&apos;s a{" "}
          <Highlight>compounding loop</Highlight>:
        </Paragraph>

        <div className="mt-8">
          <AnimatedFlywheel />
        </div>

        <Paragraph>Each cycle makes the next one better.</Paragraph>
      </Section>

      <Divider />

      {/* The Twenty Tools */}
      <Section
        {...{
          title: "The Twenty Tools (And When To Use Them)",
          icon: <Zap className="h-5 w-5" />,
          delay: 0.15,
        }}
      >
        <div className="space-y-6">
          <ToolCard
            {...{
              number: 1,
              name: "NTM",
              subtitle: "Your Cockpit",
              command: "ntm",
              icon: <Cpu className="h-5 w-5" />,
              gradient: "from-violet-500/20 to-purple-500/20",
              useCases: [
                "Spawn agent sessions",
                "Send prompts to multiple agents",
                "Orchestrate parallel work",
              ],
            }}
          />

          <ToolCard
            {...{
              number: 2,
              name: "MCP Agent Mail",
              subtitle: "Coordination",
              command: "am",
              icon: <Mail className="h-5 w-5" />,
              gradient: "from-sky-500/20 to-blue-500/20",
              useCases: [
                "Multiple agents need to share context",
                'You want agents to "talk" to each other',
                "Coordinating complex multi-agent workflows",
              ],
            }}
          />

          <ToolCard
            {...{
              number: 3,
              name: "UBS",
              subtitle: "Quality Guardrails",
              command: "ubs",
              icon: <Shield className="h-5 w-5" />,
              gradient: "from-emerald-500/20 to-teal-500/20",
              useCases: [
                "Scan code for bugs before committing",
                "Run comprehensive static analysis",
                "Catch issues early",
              ],
              example: "ubs .  # Scan current directory",
            }}
          />

          <ToolCard
            {...{
              number: 4,
              name: "CASS",
              subtitle: "Session Search",
              command: "cass",
              icon: <Search className="h-5 w-5" />,
              gradient: "from-amber-500/20 to-orange-500/20",
              useCases: [
                "Search across all agent session history",
                "Find previous solutions",
                "Review what agents have done",
              ],
              example: 'cass search "authentication error" --robot --limit 5',
            }}
          />

          <ToolCard
            {...{
              number: 5,
              name: "CASS Memory (CM)",
              subtitle: "Procedural Memory",
              command: "cm",
              icon: <Brain className="h-5 w-5" />,
              gradient: "from-rose-500/20 to-pink-500/20",
              useCases: [
                "Build persistent agent memory",
                "Distill learnings from sessions",
                "Give agents context from past work",
              ],
              example: `cm context "Building an API"  # Get relevant memories
cm reflect                     # Update procedural memory`,
            }}
          />

          <ToolCard
            {...{
              number: 6,
              name: "Beads Viewer",
              subtitle: "Task Management",
              command: "bv",
              icon: <LayoutDashboard className="h-5 w-5" />,
              gradient: "from-indigo-500/20 to-violet-500/20",
              useCases: [
                "Track tasks and issues",
                "Kanban view of work",
                "Keep agents focused on goals",
              ],
              example: "bv --robot-triage  # Deterministic triage output",
            }}
          />

          <ToolCard
            {...{
              number: 7,
              name: "CAAM",
              subtitle: "Account Switching",
              command: "caam",
              icon: <Users className="h-5 w-5" />,
              gradient: "from-teal-500/20 to-cyan-500/20",
              useCases: [
                "You hit rate limits",
                "You want to switch between accounts",
                "Testing with different credentials",
              ],
              example: `caam status         # See current accounts
caam activate claude backup-account`,
            }}
          />

          <ToolCard
            {...{
              number: 8,
              name: "SLB",
              subtitle: "Safety Guardrails",
              command: "slb",
              icon: <Shield className="h-5 w-5" />,
              gradient: "from-red-500/20 to-rose-500/20",
              useCases: [
                "Dangerous commands (when you want them reviewed)",
                "Two-person rule for destructive operations",
                "Optional safety layer",
              ],
            }}
          />

          <ToolCard
            {...{
              number: 9,
              name: "RU",
              subtitle: "Multi-Repo Sync",
              command: "ru",
              icon: <GitMerge className="h-5 w-5" />,
              gradient: "from-indigo-500/20 to-blue-500/20",
              useCases: [
                "Sync dozens of repos with one command",
                "AI-driven commit automation",
                "Parallel workflow management",
              ],
              example: `ru sync -j4                  # Parallel sync
ru agent-sweep --dry-run    # Preview AI commits`,
            }}
          />

          <ToolCard
            {...{
              number: 10,
              name: "DCG",
              subtitle: "Pre-Execution Guard",
              command: "dcg",
              icon: <ShieldAlert className="h-5 w-5" />,
              gradient: "from-rose-500/20 to-red-500/20",
              useCases: [
                "Blocks dangerous commands before execution",
                "Protects git, filesystem, and databases",
                "Automatic - no manual calls needed",
              ],
              example: `dcg test "rm -rf /" --explain  # Test if blocked
dcg doctor                     # Check status`,
            }}
          />
        </div>
      </Section>

      <Divider />

      {/* A Complete Workflow */}
      <Section
        {...{
          title: "A Complete Workflow",
          icon: <Terminal className="h-5 w-5" />,
          delay: 0.2,
        }}
      >
        <Paragraph>Here&apos;s how a real session might look:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            {...{
              code: `# 1. Plan your work
bv --robot-triage                # Check tasks
br ready                        # See what's ready to work on

# 2. Start your agents
ntm spawn myproject --cc=2 --cod=1

# 3. Set context
cm context "Implementing user authentication" --json

# 4. Send initial prompt
ntm send myproject "Let's implement user authentication.
Here's the context: [paste cm output]"

# 5. Monitor and guide
ntm attach myproject            # Watch progress

# 6. Scan before committing
ubs .                           # Check for bugs

# 7. Update memory
cm reflect                      # Distill learnings

# 8. Close the task
br close <task-id>`,
              showLineNumbers: true,
            }}
          />
        </div>
      </Section>

      <Divider />

      {/* The Flywheel Effect */}
      <Section
        {...{
          title: "The Flywheel Effect",
          icon: <Sparkles className="h-5 w-5" />,
          delay: 0.25,
        }}
      >
        <Paragraph>With each cycle:</Paragraph>

        <div className="mt-6">
          <FlywheelEffectList />
        </div>

        <div className="mt-8">
          <InteractiveFlywheelCycle />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            This is why it&apos;s called a <strong>flywheel</strong> - it gets
            better the more you use it.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Your First Real Task */}
      <Section
        {...{
          title: "Your First Real Task",
          icon: <Play className="h-5 w-5" />,
          delay: 0.3,
        }}
      >
        <Paragraph>
          You&apos;re ready! Here&apos;s how to start your first project:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            {...{
              code: `# 1. Create a project directory
mkcd /data/projects/my-first-project

# 2. Initialize git
git init

# 3. Initialize beads for task tracking
br init

# (Recommended) Create a dedicated Beads sync branch
# Beads uses git worktrees for syncing; syncing to your current branch (often \`main\`)
# can cause worktree conflicts. Once you have a \`main\` branch and a remote, run:
git branch beads-sync main
git push -u origin beads-sync
br config set sync.branch=beads-sync

# 4. Spawn your agents
ntm spawn my-first-project --cc=2 --cod=1 --agy=1

# 5. Start building!
ntm send my-first-project "Let's build something awesome.
What kind of project should we create?"`,
              showLineNumbers: true,
            }}
          />
        </div>
      </Section>

      <Divider />

      {/* Getting Help */}
      <Section
        {...{
          title: "Getting Help",
          icon: <Zap className="h-5 w-5" />,
          delay: 0.35,
        }}
      >
        <div className="grid gap-4 sm:grid-cols-3">
          <HelpCard
            {...{
              command: "acfs doctor",
              description: "Check everything is working",
              gradient: "from-emerald-500/20 to-teal-500/20",
            }}
          />
          <HelpCard
            {...{
              command: "ntm --help",
              description: "NTM help",
              gradient: "from-violet-500/20 to-purple-500/20",
            }}
          />
          <HelpCard
            {...{
              command: "onboard",
              description: "Re-run this tutorial anytime",
              gradient: "from-amber-500/20 to-orange-500/20",
            }}
          />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// ANIMATED FLYWHEEL - Spectacular spinning visualization
// =============================================================================

interface FlywheelToolNode {
  label: string;
  sublabel: string;
  command: string;
  cases: string[];
  color: string;
  glowColor: string;
}

const FLYWHEEL_NODES: FlywheelToolNode[] = [
  {
    label: "Plan",
    sublabel: "Beads",
    command: "bv / br",
    cases: ["Track tasks", "Find ready work", "Manage dependencies"],
    color: "#8b5cf6",
    glowColor: "rgba(139,92,246,0.6)",
  },
  {
    label: "Coordinate",
    sublabel: "Agent Mail",
    command: "am",
    cases: ["Agent messaging", "File reservations", "Thread tracking"],
    color: "#0ea5e9",
    glowColor: "rgba(14,165,233,0.6)",
  },
  {
    label: "Execute",
    sublabel: "NTM + Agents",
    command: "ntm",
    cases: ["Spawn agents", "Send prompts", "Monitor progress"],
    color: "#10b981",
    glowColor: "rgba(16,185,129,0.6)",
  },
  {
    label: "Scan",
    sublabel: "UBS",
    command: "ubs",
    cases: ["Bug detection", "Code quality", "Pre-commit checks"],
    color: "#f59e0b",
    glowColor: "rgba(245,158,11,0.6)",
  },
  {
    label: "Remember",
    sublabel: "CASS Memory",
    command: "cm / cass",
    cases: ["Session search", "Procedural memory", "Pattern reuse"],
    color: "#f43f5e",
    glowColor: "rgba(244,63,94,0.6)",
  },
  {
    label: "Guard",
    sublabel: "DCG + SLB",
    command: "dcg / slb",
    cases: [
      "Block dangerous commands",
      "Two-person rule",
      "Account switching",
    ],
    color: "#ef4444",
    glowColor: "rgba(239,68,68,0.6)",
  },
];

const CX = 250;
const CY = 250;
const RADIUS = 160;
const NODE_COUNT = FLYWHEEL_NODES.length;

/** Get the position of node i on the circle (in degrees, 0 = top) */
function nodeAngleDeg(i: number): number {
  return (360 / NODE_COUNT) * i - 90;
}

function nodePos(i: number): { x: number; y: number } {
  const angle = (nodeAngleDeg(i) * Math.PI) / 180;
  return { x: CX + RADIUS * Math.cos(angle), y: CY + RADIUS * Math.sin(angle) };
}

/** Build a quadratic Bezier arc between adjacent nodes, curving through the circle */
function arcPath(fromIdx: number, toIdx: number): string {
  const from = nodePos(fromIdx);
  const to = nodePos(toIdx);
  // Control point pulled toward center for a nice curve
  const midAngle =
    (((nodeAngleDeg(fromIdx) + nodeAngleDeg(toIdx)) / 2) * Math.PI) / 180;
  const cpRadius = RADIUS * 0.72;
  const cx = CX + cpRadius * Math.cos(midAngle);
  const cy = CY + cpRadius * Math.sin(midAngle);
  return `M ${from.x} ${from.y} Q ${cx} ${cy} ${to.x} ${to.y}`;
}

function AnimatedFlywheel() {
  const [hoveredIdx, setHoveredIdx] = useState<number | null>(null);
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  const activeIdx = selectedIdx ?? hoveredIdx;
  const isPaused = activeIdx !== null;

  const handleNodeClick = useCallback(
    (idx: number) => {
      setSelectedIdx((prev) => (prev === idx ? null : idx));
    },
    []
  );

  const handleBackgroundClick = useCallback(() => {
    setSelectedIdx(null);
  }, []);

  // Build connection paths between adjacent nodes (0->1, 1->2, ... 5->0)
  const connections = Array.from({ length: NODE_COUNT }, (_, i) => ({
    from: i,
    to: (i + 1) % NODE_COUNT,
    path: arcPath(i, (i + 1) % NODE_COUNT),
  }));

  // Determine active node data for detail card
  const activeNode = activeIdx !== null ? FLYWHEEL_NODES[activeIdx] : null;

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glow effects */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/10 rounded-full blur-3xl" />

      {/* Inline keyframes for CSS-driven continuous rotation and dash animation */}
      <style>{`
        @keyframes flywheel-spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        @keyframes flywheel-counter-spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(-360deg); }
        }
        @keyframes dash-flow {
          to { stroke-dashoffset: -24; }
        }
        @keyframes particle-travel {
          0% { offset-distance: 0%; opacity: 0; }
          10% { opacity: 1; }
          90% { opacity: 1; }
          100% { offset-distance: 100%; opacity: 0; }
        }
        @keyframes center-pulse {
          0%, 100% { r: 38; opacity: 0.18; }
          50% { r: 48; opacity: 0.28; }
        }
        .flywheel-ring {
          transform-origin: ${CX}px ${CY}px;
          animation: flywheel-spin 30s linear infinite;
        }
        .flywheel-ring.paused {
          animation-play-state: paused;
        }
        .flywheel-label {
          animation: flywheel-counter-spin 30s linear infinite;
        }
        .flywheel-label.paused {
          animation-play-state: paused;
        }
        .flywheel-dash {
          stroke-dasharray: 8 16;
          animation: dash-flow 1.2s linear infinite;
        }
        .flywheel-dash.paused {
          animation-play-state: paused;
        }
      `}</style>

      <div className="relative flex flex-col items-center p-4 sm:p-8">
        <svg
          ref={svgRef}
          viewBox="0 0 500 500"
          className="w-full max-w-[500px] aspect-square"
          onClick={handleBackgroundClick}
        >
          <defs>
            {/* Glow filter for hovered nodes */}
            <filter id="flywheel-glow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="6" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
            {/* Per-node glow filters with their color */}
            {FLYWHEEL_NODES.map((node, i) => (
              <filter key={`glow-${i}`} id={`node-glow-${i}`} x="-80%" y="-80%" width="260%" height="260%">
                <feDropShadow dx="0" dy="0" stdDeviation="8" floodColor={node.glowColor} floodOpacity="0.9" />
              </filter>
            ))}
          </defs>

          {/* ---- Pulsing center hub ---- */}
          <circle cx={CX} cy={CY} r={38} fill="none" stroke="hsl(var(--primary))" strokeOpacity="0.18" strokeWidth="2">
            <animate attributeName="r" values="38;48;38" dur="3s" repeatCount="indefinite" />
            <animate attributeName="stroke-opacity" values="0.18;0.28;0.18" dur="3s" repeatCount="indefinite" />
          </circle>
          <circle cx={CX} cy={CY} r={30} fill="hsl(var(--primary))" fillOpacity="0.08" stroke="hsl(var(--primary))" strokeOpacity="0.3" strokeWidth="1.5" />
          <text x={CX} y={CY - 6} textAnchor="middle" fill="white" fontSize="11" fontWeight="700" opacity="0.9">
            ACFS
          </text>
          <text x={CX} y={CY + 10} textAnchor="middle" fill="hsl(var(--primary))" fontSize="9" fontWeight="500" opacity="0.7">
            Flywheel
          </text>

          {/* ---- Rotating group: connections + nodes ---- */}
          <g className={`flywheel-ring ${isPaused ? "paused" : ""}`}>
            {/* Connection arcs (dim lines + animated dashes) */}
            {connections.map((conn, i) => {
              const isAdjacentToActive =
                activeIdx !== null &&
                (conn.from === activeIdx || conn.to === activeIdx);
              const baseOpacity = activeIdx !== null ? (isAdjacentToActive ? 0.5 : 0.08) : 0.2;
              const dashOpacity = activeIdx !== null ? (isAdjacentToActive ? 0.8 : 0.1) : 0.4;

              return (
                <g key={`conn-${i}`}>
                  {/* Base arc */}
                  <path
                    d={conn.path}
                    fill="none"
                    stroke="white"
                    strokeOpacity={baseOpacity}
                    strokeWidth="1.5"
                    style={{ transition: "stroke-opacity 0.3s" }}
                  />
                  {/* Animated dashes showing flow direction */}
                  <path
                    d={conn.path}
                    fill="none"
                    stroke="white"
                    strokeOpacity={dashOpacity}
                    strokeWidth="1.5"
                    className={`flywheel-dash ${isPaused ? "paused" : ""}`}
                    style={{ transition: "stroke-opacity 0.3s" }}
                  />
                </g>
              );
            })}

            {/* Energy particles traveling along paths */}
            {connections.map((conn, i) =>
              [0, 1, 2].map((particleIdx) => {
                const particleOpacity = activeIdx !== null
                  ? (conn.from === activeIdx || conn.to === activeIdx ? 0.9 : 0.1)
                  : 0.7;
                return (
                  <circle
                    key={`particle-${i}-${particleIdx}`}
                    r="2.5"
                    fill="white"
                    opacity={particleOpacity}
                    style={{
                      offsetPath: `path('${conn.path}')`,
                      animation: `particle-travel 3s linear infinite`,
                      animationDelay: `${particleIdx * 1}s`,
                      animationPlayState: isPaused ? "paused" : "running",
                      transition: "opacity 0.3s",
                    }}
                  />
                );
              })
            )}

            {/* ---- Tool nodes ---- */}
            {FLYWHEEL_NODES.map((node, i) => {
              const pos = nodePos(i);
              const isActive = activeIdx === i;
              const isDimmed = activeIdx !== null && !isActive;
              const nodeOpacity = isDimmed ? 0.3 : 1;
              const scale = isActive ? 1.2 : 1;

              return (
                <g
                  key={`node-${i}`}
                  style={{
                    cursor: "pointer",
                    transition: "opacity 0.3s, transform 0.3s",
                    opacity: nodeOpacity,
                    transform: `translate(${pos.x}px, ${pos.y}px) scale(${scale})`,
                    transformOrigin: "0 0",
                  }}
                  onMouseEnter={() => setHoveredIdx(i)}
                  onMouseLeave={() => setHoveredIdx(null)}
                  onClick={(e) => {
                    e.stopPropagation();
                    handleNodeClick(i);
                  }}
                  filter={isActive ? `url(#node-glow-${i})` : undefined}
                >
                  {/* Node circle */}
                  <circle
                    cx={0}
                    cy={0}
                    r={28}
                    fill={node.color}
                    fillOpacity={0.15}
                    stroke={node.color}
                    strokeWidth={isActive ? 2.5 : 1.5}
                    strokeOpacity={isActive ? 1 : 0.6}
                  />
                  {/* Inner highlight */}
                  <circle
                    cx={0}
                    cy={0}
                    r={20}
                    fill={node.color}
                    fillOpacity={isActive ? 0.3 : 0.1}
                  />

                  {/* Counter-rotating label group so text stays readable */}
                  <g className={`flywheel-label ${isPaused ? "paused" : ""}`}>
                    <text
                      x={0}
                      y={-3}
                      textAnchor="middle"
                      fill="white"
                      fontSize="10"
                      fontWeight="700"
                    >
                      {node.label}
                    </text>
                    <text
                      x={0}
                      y={9}
                      textAnchor="middle"
                      fill={node.color}
                      fontSize="7.5"
                      fontWeight="500"
                      opacity="0.9"
                    >
                      {node.sublabel}
                    </text>
                  </g>
                </g>
              );
            })}
          </g>
        </svg>

        {/* ---- Detail card for hovered/selected node ---- */}
        <AnimatePresence>
          {activeNode && activeIdx !== null && (
            <motion.div
              {...{
                key: activeIdx,
                initial: { opacity: 0, y: 10, scale: 0.95 },
                animate: { opacity: 1, y: 0, scale: 1 },
                exit: { opacity: 0, y: 10, scale: 0.95 },
                transition: { duration: 0.2 },
                className:
                  "w-full max-w-sm mt-2 rounded-2xl border border-white/[0.1] bg-black/40 backdrop-blur-xl p-5",
              }}
            >
              <div className="flex items-center gap-3 mb-3">
                <div
                  className="h-3 w-3 rounded-full"
                  style={{ backgroundColor: activeNode.color }}
                />
                <h4 className="font-bold text-white text-sm">
                  {activeNode.label}{" "}
                  <span className="font-normal text-white/50">
                    ({activeNode.sublabel})
                  </span>
                </h4>
              </div>
              <code className="inline-block px-2 py-1 rounded bg-black/30 border border-white/[0.08] text-xs font-mono text-primary mb-3">
                {activeNode.command}
              </code>
              <ul className="space-y-1.5">
                {activeNode.cases.map((c, ci) => (
                  <li
                    key={ci}
                    className="text-sm text-white/60 flex items-center gap-2"
                  >
                    <div
                      className="h-1.5 w-1.5 rounded-full shrink-0"
                      style={{ backgroundColor: activeNode.color, opacity: 0.7 }}
                    />
                    {c}
                  </li>
                ))}
              </ul>
              {selectedIdx !== null && (
                <p className="mt-3 text-[11px] text-white/30">
                  Click node again or background to deselect
                </p>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// TOOL CARD - Display a tool with its use cases
// =============================================================================
function ToolCard({
  number,
  name,
  subtitle,
  command,
  icon,
  gradient,
  useCases,
  example,
}: {
  number: number;
  name: string;
  subtitle: string;
  command: string;
  icon: React.ReactNode;
  gradient: string;
  useCases: string[];
  example?: string;
}) {
  return (
    <motion.div
      {...{
        initial: { opacity: 0, x: -20 },
        animate: { opacity: 1, x: 0 },
        transition: { delay: number * 0.05 },
        whileHover: { x: 4, scale: 1.01 },
        className: `group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl overflow-hidden transition duration-300 hover:border-white/[0.15]`,
      }}
    >
      <div className="flex items-start gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/10 text-white shadow-lg group-hover:bg-white/20 group-hover:shadow-xl group-hover:scale-110 transition duration-300">
          {icon}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 mb-1">
            <h4 className="font-bold text-white">
              {number}. {name}
            </h4>
            <span className="text-xs text-white/60">- {subtitle}</span>
          </div>
          <code className="inline-block px-2 py-1 rounded bg-black/30 border border-white/[0.08] text-xs font-mono text-primary mb-3">
            {command}
          </code>

          <p className="text-sm text-white/60 mb-3">Use it to:</p>
          <ul className="space-y-1">
            {useCases.map((useCase, i) => (
              <li key={i} className="text-sm text-white/50 flex items-center gap-2">
                <div className="h-1 w-1 rounded-full bg-white/40 shrink-0" />
                {useCase}
              </li>
            ))}
          </ul>

          {example && (
            <div className="mt-4 rounded-xl bg-black/20 border border-white/[0.06] overflow-hidden">
              <pre className="p-3 text-xs font-mono text-white/70 overflow-x-auto">
                {example}
              </pre>
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FLYWHEEL EFFECT LIST
// =============================================================================
function FlywheelEffectList() {
  const effects = [
    { tool: "CASS", effect: "remembers what worked" },
    { tool: "CM", effect: "distills reusable patterns" },
    { tool: "UBS", effect: "catches more issues" },
    { tool: "DCG", effect: "blocks before damage happens" },
    { tool: "Agent Mail", effect: "improves coordination" },
    { tool: "NTM", effect: "sessions become more effective" },
  ];

  return (
    <div className="space-y-3">
      {effects.map((item, i) => (
        <motion.div key={i}
          {...{
            initial: { opacity: 0, x: -20 },
            animate: { opacity: 1, x: 0 },
            transition: { delay: i * 0.1 },
            whileHover: { x: 6, scale: 1.01 },
            className:
              "group flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]",
          }}
        >
          <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0 group-hover:scale-110 transition-transform" />
          <span className="text-white/70 group-hover:text-white/90 transition-colors">
            <strong className="text-primary">{item.tool}</strong> {item.effect}
          </span>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// HELP CARD
// =============================================================================
function HelpCard({
  command,
  description,
  gradient,
}: {
  command: string;
  description: string;
  gradient: string;
}) {
  return (
    <motion.div
      {...{
        initial: { opacity: 0, y: 10 },
        animate: { opacity: 1, y: 0 },
        whileHover: { y: -4, scale: 1.02 },
        className: `group relative rounded-xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-4 backdrop-blur-xl text-center transition duration-300 hover:border-white/[0.15]`,
      }}
    >
      <code className="block px-3 py-2 rounded-lg bg-black/30 border border-white/[0.08] text-sm font-mono text-primary mb-2 group-hover:bg-black/40 transition-colors">
        {command}
      </code>
      <span className="text-sm text-white/60 group-hover:text-white/80 transition-colors">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE FLYWHEEL CYCLE - Dramatically enhanced animated flywheel
// =============================================================================

interface FlywheelStageData {
  id: string;
  label: string;
  shortLabel: string;
  icon: LucideIcon;
  color: string;
  warmColor: string;
  tools: string[];
  agent: string;
  description: string;
  commands: string[];
}

const FLYWHEEL_STAGES_V2: FlywheelStageData[] = [
  {
    id: "identify",
    label: "Identify Task",
    shortLabel: "Identify",
    icon: Target,
    color: "#f43f5e",
    warmColor: "#fb923c",
    tools: ["Beads Viewer (bv)", "br ready"],
    agent: "Brenner",
    description:
      "Scan the backlog, triage issues by priority, and pick the highest-impact task. Beads keeps everything ranked and visible.",
    commands: ["acfs bv list --priority high", "acfs br ready"],
  },
  {
    id: "plan",
    label: "Plan Approach",
    shortLabel: "Plan",
    icon: Brain,
    color: "#8b5cf6",
    warmColor: "#c084fc",
    tools: ["CM reflect", "CLAUDE.md"],
    agent: "Context Master",
    description:
      "Review procedural memory, outline the approach, and decide which agents to spawn for parallel work.",
    commands: ["acfs cm reflect --task $TASK_ID", "cat CLAUDE.md"],
  },
  {
    id: "implement",
    label: "Implement",
    shortLabel: "Code",
    icon: FileCode,
    color: "#3b82f6",
    warmColor: "#60a5fa",
    tools: ["NTM spawn", "Agent Mail (am)"],
    agent: "NTM Swarm",
    description:
      "Spawn parallel coding agents with NTM. Each agent works on a slice of the task, coordinating via Agent Mail.",
    commands: [
      "acfs ntm spawn --agents 3 --task $TASK_ID",
      "acfs am send @agent-2 'merge ready'",
    ],
  },
  {
    id: "test",
    label: "Test & Verify",
    shortLabel: "Test",
    icon: TestTube,
    color: "#06b6d4",
    warmColor: "#22d3ee",
    tools: ["UBS scan", "CAUT check"],
    agent: "UBS Scanner",
    description:
      "Run automated bug scanning, check test coverage, and verify the changes pass all quality gates.",
    commands: ["acfs ubs scan --deep", "acfs caut check --all"],
  },
  {
    id: "review",
    label: "Code Review",
    shortLabel: "Review",
    icon: Eye,
    color: "#10b981",
    warmColor: "#34d399",
    tools: ["DCG guard", "APR review"],
    agent: "DCG Guardian",
    description:
      "DCG blocks dangerous commands. APR provides automated pull request review with context-aware suggestions.",
    commands: ["acfs dcg guard --strict", "acfs apr review --pr $PR_NUM"],
  },
  {
    id: "deploy",
    label: "Deploy & Ship",
    shortLabel: "Deploy",
    icon: Rocket,
    color: "#f59e0b",
    warmColor: "#fbbf24",
    tools: ["RU sync", "git push"],
    agent: "RU Deployer",
    description:
      "RU handles multi-repo sync, AI-driven commit messages, and coordinated deployments across all projects.",
    commands: ["acfs ru sync --all", "git push origin main"],
  },
  {
    id: "monitor",
    label: "Monitor & Observe",
    shortLabel: "Monitor",
    icon: Activity,
    color: "#ec4899",
    warmColor: "#f472b6",
    tools: ["DSR report", "acfs status"],
    agent: "DSR Reporter",
    description:
      "Track deployment health, generate daily status reports, and surface any regressions or anomalies immediately.",
    commands: ["acfs dsr report --today", "acfs status --verbose"],
  },
  {
    id: "learn",
    label: "Learn & Improve",
    shortLabel: "Learn",
    icon: BookOpen,
    color: "#a855f7",
    warmColor: "#d946ef",
    tools: ["CASS search", "CM distill"],
    agent: "CASS Indexer",
    description:
      "CASS indexes session history for future retrieval. CM distills reusable patterns into procedural memory for the next cycle.",
    commands: ["acfs cass index --session $SID", "acfs cm distill --patterns"],
  },
];

const STAGE_COUNT = FLYWHEEL_STAGES_V2.length;

/** Cycle velocity data: shows improvement over time */
const CYCLE_METRICS = [
  { cycle: 1, duration: "4 hrs", tasks: 1, bugs: 3, label: "Cold start" },
  { cycle: 2, duration: "2 hrs", tasks: 2, bugs: 1, label: "Warming up" },
  { cycle: 3, duration: "45 min", tasks: 3, bugs: 0, label: "In the zone" },
  { cycle: 4, duration: "20 min", tasks: 5, bugs: 0, label: "Peak velocity" },
  { cycle: 5, duration: "12 min", tasks: 8, bugs: 0, label: "Compound mode" },
];

/** Duration in ms for one full rotation at each cycle number */
function getCycleDuration(cycle: number): number {
  return Math.max(2000, 10000 - (cycle - 1) * 2000);
}

/** Interpolate between cool and warm hex colors */
function lerpHexColor(cool: string, warm: string, t: number): string {
  const parse = (hex: string) => {
    const h = hex.replace("#", "");
    return [
      parseInt(h.slice(0, 2), 16),
      parseInt(h.slice(2, 4), 16),
      parseInt(h.slice(4, 6), 16),
    ];
  };
  const c = parse(cool);
  const w = parse(warm);
  const r = Math.round(c[0] + (w[0] - c[0]) * t);
  const g = Math.round(c[1] + (w[1] - c[1]) * t);
  const b = Math.round(c[2] + (w[2] - c[2]) * t);
  return `rgb(${r},${g},${b})`;
}

/** Get position on a circle */
function getCirclePoint(
  cx: number,
  cy: number,
  radius: number,
  angleDeg: number
) {
  const rad = ((angleDeg - 90) * Math.PI) / 180;
  return { x: cx + radius * Math.cos(rad), y: cy + radius * Math.sin(rad) };
}

// ---- Particle sub-component (no random in render) ----
function EnergyParticle({
  pathId,
  duration,
  delay,
  color,
  size,
}: {
  pathId: string;
  duration: number;
  delay: number;
  color: string;
  size: number;
}) {
  return (
    <circle r={size} fill={color} opacity={0.8}>
      <animateMotion
        dur={`${duration}ms`}
        begin={`${delay}ms`}
        repeatCount="indefinite"
        rotate="auto"
      >
        <mpath href={`#${pathId}`} />
      </animateMotion>
      <animate
        attributeName="opacity"
        values="0;0.9;0.9;0"
        dur={`${duration}ms`}
        begin={`${delay}ms`}
        repeatCount="indefinite"
      />
      <animate
        attributeName="r"
        values={`${size * 0.5};${size};${size * 0.5}`}
        dur={`${duration}ms`}
        begin={`${delay}ms`}
        repeatCount="indefinite"
      />
    </circle>
  );
}

// ---- Mini terminal sub-component ----
function MiniTerminal({
  commands,
  stageName,
  color,
}: {
  commands: string[];
  stageName: string;
  color: string;
}) {
  const [visibleLines, setVisibleLines] = useState(0);

  useEffect(() => {
    const timers: ReturnType<typeof setTimeout>[] = [];
    timers.push(setTimeout(() => setVisibleLines(0), 0));
    commands.forEach((_, i) => {
      timers.push(
        setTimeout(() => {
          setVisibleLines(i + 1);
        }, (i + 1) * 600)
      );
    });
    return () => timers.forEach(clearTimeout);
  }, [commands]);

  return (
    <div className="rounded-lg border border-white/[0.08] bg-black/50 overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-1.5 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex gap-1.5">
          <div className="w-2 h-2 rounded-full bg-red-500/60" />
          <div className="w-2 h-2 rounded-full bg-yellow-500/60" />
          <div className="w-2 h-2 rounded-full bg-green-500/60" />
        </div>
        <span className="text-[10px] text-white/30 font-mono ml-1">
          {stageName}
        </span>
      </div>
      <div className="p-3 space-y-1.5 font-mono text-xs min-h-[60px]">
        {commands.map((cmd, i) => (
          <div
            key={`${stageName}-${i}`}
            className="flex items-start gap-2 transition duration-300"
            style={{
              opacity: i < visibleLines ? 1 : 0,
              transform: i < visibleLines ? "translateX(0)" : "translateX(-8px)",
            }}
          >
            <span style={{ color }} className="shrink-0 select-none">
              $
            </span>
            <span className="text-white/70">{cmd}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---- Velocity bar for metrics dashboard ----
function VelocityBar({
  metric,
  index,
  currentCycle,
  maxCycle,
}: {
  metric: (typeof CYCLE_METRICS)[number];
  index: number;
  currentCycle: number;
  maxCycle: number;
}) {
  const isReached = metric.cycle <= currentCycle;
  const isCurrent = metric.cycle === currentCycle;
  const barWidth = isReached
    ? `${100 - (metric.cycle - 1) * 18}%`
    : "10%";
  const warmth = Math.min((metric.cycle - 1) / (maxCycle - 1), 1);
  const barColor = lerpHexColor("#6366f1", "#f97316", warmth);

  return (
    <motion.div
      {...{
        initial: { opacity: 0, x: -20 },
        animate: { opacity: 1, x: 0 },
        transition: {
          type: "spring",
          stiffness: 200,
          damping: 25,
          delay: index * 0.08,
        },
        className: `flex items-center gap-3 ${isCurrent ? "scale-[1.02]" : ""}`,
      }}
    >
      <div className="w-16 shrink-0 text-right">
        <span
          className={`text-xs font-mono ${isCurrent ? "text-white font-bold" : "text-white/40"}`}
        >
          C{metric.cycle}
        </span>
      </div>
      <div className="flex-1 h-6 rounded-md bg-white/[0.03] border border-white/[0.06] overflow-hidden relative">
        <motion.div
          {...{
            initial: { width: "0%" },
            animate: { width: isReached ? barWidth : "5%" },
            transition: { duration: 0.8, delay: index * 0.15 },
            className: "h-full rounded-md relative overflow-hidden",
            style: {
              background: isReached
                ? `linear-gradient(90deg, ${barColor}, ${barColor}88)`
                : "rgba(255,255,255,0.03)",
            },
          }}
        >
          {isReached && (
            <div className="absolute inset-0 bg-gradient-to-r from-white/0 via-white/10 to-white/0 animate-pulse" />
          )}
        </motion.div>
        <div className="absolute inset-0 flex items-center justify-between px-2">
          <span
            className={`text-[10px] font-mono ${isReached ? "text-white/90" : "text-white/20"}`}
          >
            {metric.duration}
          </span>
          <span
            className={`text-[10px] ${isReached ? "text-white/60" : "text-white/15"}`}
          >
            {metric.tasks} task{metric.tasks !== 1 ? "s" : ""} &middot;{" "}
            {metric.bugs} bugs
          </span>
        </div>
      </div>
      <div className="w-20 shrink-0">
        <span
          className={`text-[10px] ${isCurrent ? "text-white/80 font-medium" : "text-white/30"}`}
        >
          {metric.label}
        </span>
      </div>
    </motion.div>
  );
}

// ---- Stage node for the SVG wheel ----
function StageNode({
  stage,
  index,
  isActive,
  isHighlighted,
  stageColor,
  cx,
  cy,
  onClick,
}: {
  stage: FlywheelStageData;
  index: number;
  isActive: boolean;
  isHighlighted: boolean;
  stageColor: string;
  cx: number;
  cy: number;
  onClick: () => void;
}) {
  const nodeRadius = isActive ? 28 : isHighlighted ? 26 : 24;

  return (
    <g
      style={{ cursor: "pointer" }}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
    >
      {/* Outer glow ring */}
      {isActive && (
        <circle cx={cx} cy={cy} r={nodeRadius + 6} fill="none" stroke={stageColor} strokeWidth="1" opacity="0.3">
          <animate attributeName="r" values={`${nodeRadius + 4};${nodeRadius + 8};${nodeRadius + 4}`} dur="2s" repeatCount="indefinite" />
          <animate attributeName="opacity" values="0.3;0.1;0.3" dur="2s" repeatCount="indefinite" />
        </circle>
      )}

      {/* Background circle */}
      <circle
        cx={cx}
        cy={cy}
        r={nodeRadius}
        fill={stageColor}
        fillOpacity={isActive ? 0.2 : 0.08}
        stroke={stageColor}
        strokeWidth={isActive ? 2.5 : 1}
        strokeOpacity={isActive ? 1 : 0.35}
        style={{ transition: "all 0.3s ease" }}
      />

      {/* Icon - rendered as text placeholder since SVG can't use React components inline */}
      <text
        x={cx}
        y={cy - 4}
        textAnchor="middle"
        fill="white"
        fontSize="11"
        fontWeight="700"
        opacity={isActive ? 1 : 0.7}
        dominantBaseline="central"
      >
        {stage.shortLabel.slice(0, 3)}
      </text>

      {/* Index number */}
      <text
        x={cx}
        y={cy + 10}
        textAnchor="middle"
        fill={stageColor}
        fontSize="7"
        fontWeight="600"
        opacity={0.7}
      >
        {index + 1}/{STAGE_COUNT}
      </text>
    </g>
  );
}

// ---- Tabs for the bottom panel ----
type FlywheelTab = "details" | "terminal" | "metrics" | "agents";

function FlywheelTabButton({
  tab,
  activeTab,
  label,
  icon: Icon,
  onClick,
}: {
  tab: FlywheelTab;
  activeTab: FlywheelTab;
  label: string;
  icon: LucideIcon;
  onClick: () => void;
}) {
  const isActive = tab === activeTab;
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition duration-200 ${
        isActive
          ? "bg-white/[0.08] text-white border border-white/[0.12]"
          : "text-white/40 hover:text-white/60 hover:bg-white/[0.04] border border-transparent"
      }`}
    >
      <Icon className="h-3 w-3" />
      {label}
    </button>
  );
}

// ---- Energy accumulation rings ----
function EnergyRings({
  cycle,
  maxCycle,
  ringCx,
  ringCy,
  baseRadius,
}: {
  cycle: number;
  maxCycle: number;
  ringCx: number;
  ringCy: number;
  baseRadius: number;
}) {
  return (
    <>
      {Array.from({ length: maxCycle }, (_, i) => {
        const isReached = i < cycle;
        const ringRadius = baseRadius + 20 + i * 10;
        const warmth = Math.min(i / (maxCycle - 1), 1);
        const ringColor = lerpHexColor("#6366f1", "#f97316", warmth);
        return (
          <circle
            key={`energy-ring-${i}`}
            cx={ringCx}
            cy={ringCy}
            r={ringRadius}
            fill="none"
            stroke={ringColor}
            strokeWidth={isReached ? 1 : 0.5}
            strokeDasharray={isReached ? "none" : "3 6"}
            opacity={isReached ? 0.2 + i * 0.05 : 0.05}
            style={{ transition: "all 0.8s ease" }}
          >
            {isReached && (
              <animate
                attributeName="opacity"
                values={`${0.15 + i * 0.05};${0.25 + i * 0.05};${0.15 + i * 0.05}`}
                dur={`${3 - i * 0.3}s`}
                repeatCount="indefinite"
              />
            )}
          </circle>
        );
      })}
    </>
  );
}

// ---- Main component ----
function InteractiveFlywheelCycle() {
  const [isPlaying, setIsPlaying] = useState(true);
  const [cycle, setCycle] = useState(1);
  const [activeStageIdx, setActiveStageIdx] = useState(0);
  const [selectedStageIdx, setSelectedStageIdx] = useState<number | null>(null);
  const [rotation, setRotation] = useState(0);
  const [activeTab, setActiveTab] = useState<FlywheelTab>("details");

  // Stable initial particle offsets (no Math.random in render)
  const [particleOffsets] = useState<number[]>(() =>
    Array.from({ length: STAGE_COUNT * 3 }, () => Math.random())
  );

  const animFrameRef = useRef<number>(0);
  const lastTimeRef = useRef<number>(0);
  const isPlayingRef = useRef(isPlaying);
  const cycleRef = useRef(cycle);

  useEffect(() => {
    isPlayingRef.current = isPlaying;
  }, [isPlaying]);

  useEffect(() => {
    cycleRef.current = cycle;
  }, [cycle]);

  const maxCycle = 5;
  const warmth = useMemo(
    () => Math.min((cycle - 1) / (maxCycle - 1), 1),
    [cycle]
  );

  const stageColors = useMemo(
    () =>
      FLYWHEEL_STAGES_V2.map((s) =>
        lerpHexColor(s.color, s.warmColor, warmth)
      ),
    [warmth]
  );

  // Animation loop
  useEffect(() => {
    let mounted = true;

    const animate = (time: number) => {
      if (!mounted) return;
      if (lastTimeRef.current === 0) {
        lastTimeRef.current = time;
      }
      const delta = time - lastTimeRef.current;
      lastTimeRef.current = time;

      if (isPlayingRef.current) {
        const dur = getCycleDuration(cycleRef.current);
        const degreesPerMs = 360 / dur;
        setRotation((prev) => prev + degreesPerMs * delta);
      }

      animFrameRef.current = requestAnimationFrame(animate);
    };

    animFrameRef.current = requestAnimationFrame(animate);

    return () => {
      mounted = false;
      cancelAnimationFrame(animFrameRef.current);
    };
  }, []);

  const normalizedRotation = rotation % 360;
  const derivedStageIdx =
    Math.floor((normalizedRotation / 360) * STAGE_COUNT) % STAGE_COUNT;
  const derivedCycle = Math.min(Math.floor(rotation / 360) + 1, maxCycle);

  useEffect(() => {
    if (derivedStageIdx !== activeStageIdx) {
      const t = setTimeout(() => setActiveStageIdx(derivedStageIdx), 0);
      return () => clearTimeout(t);
    }
  }, [derivedStageIdx, activeStageIdx]);

  useEffect(() => {
    if (derivedCycle !== cycle) {
      const t = setTimeout(() => setCycle(derivedCycle), 0);
      return () => clearTimeout(t);
    }
  }, [derivedCycle, cycle]);

  const handleTogglePlay = useCallback(() => {
    setIsPlaying((prev) => !prev);
  }, []);

  const handleReset = useCallback(() => {
    setRotation(0);
    lastTimeRef.current = 0;
    const t1 = setTimeout(() => setCycle(1), 0);
    const t2 = setTimeout(() => setActiveStageIdx(0), 0);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, []);

  const handleStageClick = useCallback((idx: number) => {
    setSelectedStageIdx((prev) => (prev === idx ? null : idx));
  }, []);

  const handleBackgroundClick = useCallback(() => {
    setSelectedStageIdx(null);
  }, []);

  const displayStageIdx = selectedStageIdx ?? activeStageIdx;
  const displayStage = FLYWHEEL_STAGES_V2[displayStageIdx];

  // SVG parameters
  const viewSize = 500;
  const ringCx = viewSize / 2;
  const ringCy = viewSize / 2;
  const ringR = 170;
  const arcAngle = 360 / STAGE_COUNT;

  const stagePositions = useMemo(
    () =>
      FLYWHEEL_STAGES_V2.map((_, i) => {
        const angle = i * arcAngle;
        return getCirclePoint(ringCx, ringCy, ringR, angle);
      }),
    [arcAngle, ringCx, ringCy, ringR]
  );

  // Build arc paths for energy particles
  const arcPaths = useMemo(() => {
    return FLYWHEEL_STAGES_V2.map((_, i) => {
      const from = stagePositions[i];
      const to = stagePositions[(i + 1) % STAGE_COUNT];
      const midAngle = (i * arcAngle + (i + 1) * arcAngle) / 2;
      const mid = getCirclePoint(ringCx, ringCy, ringR, midAngle);
      return `M ${from.x} ${from.y} Q ${mid.x} ${mid.y} ${to.x} ${to.y}`;
    });
  }, [stagePositions, arcAngle, ringCx, ringCy, ringR]);

  // Build ring arc segments for background
  const ringSegments = useMemo(() => {
    return FLYWHEEL_STAGES_V2.map((_, i) => {
      const startAngle = i * arcAngle;
      const endAngle = startAngle + arcAngle;
      const gap = 2;
      const s = startAngle + gap / 2;
      const e = endAngle - gap / 2;
      const start = getCirclePoint(ringCx, ringCy, ringR, s);
      const end = getCirclePoint(ringCx, ringCy, ringR, e);
      const largeArc = e - s > 180 ? 1 : 0;
      return `M ${start.x} ${start.y} A ${ringR} ${ringR} 0 ${largeArc} 1 ${end.x} ${end.y}`;
    });
  }, [arcAngle, ringCx, ringCy, ringR]);

  const speedLabel = useMemo(() => {
    const dur = getCycleDuration(cycle);
    if (dur >= 9000) return "Cold start";
    if (dur >= 7000) return "Building momentum";
    if (dur >= 5000) return "Accelerating";
    if (dur >= 3000) return "High velocity";
    return "Peak flywheel!";
  }, [cycle]);

  const particleDuration = useMemo(
    () => getCycleDuration(cycle) / STAGE_COUNT,
    [cycle]
  );

  return (
    <motion.div
      {...{
        initial: { opacity: 0, y: 20 },
        animate: { opacity: 1, y: 0 },
        transition: { type: "spring", stiffness: 200, damping: 25 },
        className:
          "relative rounded-3xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden",
      }}
    >
      {/* Multi-layer background glow */}
      <div
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 rounded-full blur-3xl pointer-events-none transition duration-1000"
        style={{
          backgroundColor: lerpHexColor("#6366f1", "#f97316", warmth),
          opacity: 0.06 + warmth * 0.06,
        }}
      />
      <div
        className="absolute top-1/3 left-1/3 w-64 h-64 rounded-full blur-3xl pointer-events-none transition duration-1000"
        style={{
          backgroundColor: lerpHexColor("#3b82f6", "#ec4899", warmth),
          opacity: 0.04 + warmth * 0.03,
        }}
      />

      <div className="relative p-4 sm:p-6 lg:p-8">
        {/* Header with controls */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <RotateCw
              className="h-4 w-4 text-white/60"
              style={{
                animation: isPlaying
                  ? `spin ${getCycleDuration(cycle)}ms linear infinite`
                  : "none",
              }}
            />
            <span className="text-sm font-medium text-white/70">
              The Flywheel in Action
            </span>
            <span className="hidden sm:inline text-[10px] px-2 py-0.5 rounded-full bg-white/[0.06] text-white/30 border border-white/[0.08]">
              {STAGE_COUNT} stages
            </span>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleReset}
              className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-white/[0.08] bg-white/[0.03] text-white/50 text-xs font-medium hover:bg-white/[0.06] hover:text-white/70 transition duration-200"
            >
              <RefreshCw className="h-3 w-3" /> Reset
            </button>
            <button
              type="button"
              onClick={handleTogglePlay}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-white/[0.08] bg-white/[0.04] text-white/70 text-xs font-medium hover:bg-white/[0.08] hover:text-white/90 transition duration-200"
            >
              {isPlaying ? (
                <>
                  <Pause className="h-3 w-3" /> Pause
                </>
              ) : (
                <>
                  <Play className="h-3 w-3" /> Play
                </>
              )}
            </button>
          </div>
        </div>

        {/* Cycle progress + speed indicator */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-6 mb-5">
          <div className="flex items-center gap-2">
            {Array.from({ length: maxCycle }, (_, i) => {
              const dotWarmth = Math.min(i / (maxCycle - 1), 1);
              return (
                <motion.div
                  key={i}
                  {...{
                    animate: {
                      scale: i < cycle ? 1 : 0.6,
                      opacity: i < cycle ? 1 : 0.25,
                    },
                    transition: {
                      type: "spring",
                      stiffness: 200,
                      damping: 25,
                    },
                    className:
                      "h-3 w-3 rounded-full transition-colors duration-700 relative",
                    style: {
                      backgroundColor:
                        i < cycle
                          ? lerpHexColor("#6366f1", "#f97316", dotWarmth)
                          : "rgba(255,255,255,0.12)",
                    },
                  }}
                >
                  {i === cycle - 1 && (
                    <span
                      className="absolute inset-0 rounded-full animate-ping"
                      style={{
                        backgroundColor: lerpHexColor(
                          "#6366f1",
                          "#f97316",
                          dotWarmth
                        ),
                        opacity: 0.4,
                      }}
                    />
                  )}
                </motion.div>
              );
            })}
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-white/60">
              Cycle {cycle}
            </span>
            <span className="text-white/20">&middot;</span>
            <span
              className="text-xs font-medium"
              style={{
                color: lerpHexColor("#6366f1", "#f97316", warmth),
              }}
            >
              {speedLabel}
            </span>
          </div>
        </div>

        {/* SVG Flywheel Diagram */}
        <div
          className="flex justify-center mb-5"
          onClick={handleBackgroundClick}
        >
          <svg
            viewBox={`0 0 ${viewSize} ${viewSize}`}
            className="w-full max-w-[480px] aspect-square"
          >
            <defs>
              {/* Glow filters for each stage */}
              {FLYWHEEL_STAGES_V2.map((_, i) => (
                <filter
                  key={`ifc-glow-${i}`}
                  id={`ifc-glow-${i}`}
                  x="-80%"
                  y="-80%"
                  width="260%"
                  height="260%"
                >
                  <feDropShadow
                    dx="0"
                    dy="0"
                    stdDeviation="8"
                    floodColor={stageColors[i]}
                    floodOpacity="0.7"
                  />
                </filter>
              ))}
              {/* Define arc paths for particle motion */}
              {arcPaths.map((d, i) => (
                <path key={`particle-path-${i}`} id={`pp-${i}`} d={d} />
              ))}
              {/* Radial gradient for center hub */}
              <radialGradient id="ifc-hub-grad" cx="50%" cy="50%" r="50%">
                <stop
                  offset="0%"
                  stopColor={lerpHexColor("#6366f1", "#f97316", warmth)}
                  stopOpacity="0.12"
                />
                <stop offset="100%" stopColor="transparent" stopOpacity="0" />
              </radialGradient>
            </defs>

            {/* Energy accumulation rings */}
            <EnergyRings
              cycle={cycle}
              maxCycle={maxCycle}
              ringCx={ringCx}
              ringCy={ringCy}
              baseRadius={ringR}
            />

            {/* Ring arc segments */}
            {ringSegments.map((d, i) => {
              const isActive = displayStageIdx === i;
              const isHighlighted =
                activeStageIdx === i && selectedStageIdx === null;
              return (
                <path
                  key={`ring-seg-${i}`}
                  d={d}
                  fill="none"
                  stroke={stageColors[i]}
                  strokeWidth={isActive ? 6 : isHighlighted ? 4 : 2.5}
                  strokeLinecap="round"
                  opacity={isActive ? 0.9 : isHighlighted ? 0.6 : 0.25}
                  filter={
                    isActive ? `url(#ifc-glow-${i})` : undefined
                  }
                  style={{ transition: "stroke-width 0.3s, opacity 0.3s" }}
                />
              );
            })}

            {/* Connector lines from center to each node */}
            {stagePositions.map((pos, i) => {
              const isActive = displayStageIdx === i;
              return (
                <line
                  key={`conn-${i}`}
                  x1={ringCx}
                  y1={ringCy}
                  x2={pos.x}
                  y2={pos.y}
                  stroke={stageColors[i]}
                  strokeWidth={0.5}
                  opacity={isActive ? 0.2 : 0.06}
                  style={{ transition: "opacity 0.3s" }}
                />
              );
            })}

            {/* Center hub */}
            <circle
              cx={ringCx}
              cy={ringCy}
              r={55}
              fill="url(#ifc-hub-grad)"
              stroke={lerpHexColor("#6366f1", "#f97316", warmth)}
              strokeWidth="1"
              strokeOpacity={0.2}
            >
              <animate
                attributeName="r"
                values="55;62;55"
                dur={`${getCycleDuration(cycle)}ms`}
                repeatCount="indefinite"
              />
            </circle>
            <circle
              cx={ringCx}
              cy={ringCy}
              r={45}
              fill={lerpHexColor("#6366f1", "#f97316", warmth)}
              fillOpacity={0.05}
              stroke={lerpHexColor("#6366f1", "#f97316", warmth)}
              strokeOpacity={0.25}
              strokeWidth="1.5"
            />

            {/* Center text */}
            <text
              x={ringCx}
              y={ringCy - 12}
              textAnchor="middle"
              fill="white"
              fontSize="14"
              fontWeight="800"
              opacity="0.9"
            >
              Cycle {cycle}
            </text>
            <text
              x={ringCx}
              y={ringCy + 5}
              textAnchor="middle"
              fill={lerpHexColor("#6366f1", "#f97316", warmth)}
              fontSize="9"
              fontWeight="600"
              opacity="0.7"
            >
              {speedLabel}
            </text>
            <text
              x={ringCx}
              y={ringCy + 20}
              textAnchor="middle"
              fill="white"
              fontSize="8"
              opacity="0.35"
            >
              {CYCLE_METRICS[cycle - 1]?.duration ?? ""}
            </text>

            {/* Animated position indicator */}
            <g
              style={{
                transform: `rotate(${normalizedRotation}deg)`,
                transformOrigin: `${ringCx}px ${ringCy}px`,
              }}
            >
              <circle cx={ringCx} cy={ringCy - ringR} r={4} fill="white" opacity={0.95}>
                <animate
                  attributeName="r"
                  values="3;5;3"
                  dur="1.2s"
                  repeatCount="indefinite"
                />
              </circle>
              {/* Trailing glow */}
              <circle
                cx={ringCx}
                cy={ringCy - ringR}
                r={10}
                fill="white"
                opacity={0.15}
              >
                <animate
                  attributeName="r"
                  values="8;14;8"
                  dur="1.2s"
                  repeatCount="indefinite"
                />
                <animate
                  attributeName="opacity"
                  values="0.15;0.05;0.15"
                  dur="1.2s"
                  repeatCount="indefinite"
                />
              </circle>
            </g>

            {/* Energy particles flowing between stages */}
            {arcPaths.map((_, i) =>
              Array.from({ length: 2 + Math.min(cycle - 1, 3) }, (__, pi) => {
                const offsetIdx = i * 3 + (pi % 3);
                const delayOffset = particleOffsets[offsetIdx] ?? 0;
                return (
                  <EnergyParticle
                    key={`ep-${i}-${pi}`}
                    pathId={`pp-${i}`}
                    duration={particleDuration}
                    delay={delayOffset * particleDuration}
                    color={stageColors[i]}
                    size={1.5 + Math.min(cycle * 0.3, 1.5)}
                  />
                );
              })
            )}

            {/* Direction arrows between nodes */}
            {stagePositions.map((pos, i) => {
              const nextPos = stagePositions[(i + 1) % STAGE_COUNT];
              const midX = (pos.x + nextPos.x) / 2;
              const midY = (pos.y + nextPos.y) / 2;
              // Push slightly outward
              const midAngle = (i * arcAngle + (i + 1) * arcAngle) / 2;
              const outward = getCirclePoint(
                ringCx,
                ringCy,
                ringR + 2,
                midAngle
              );
              const ax = (midX + outward.x) / 2;
              const ay = (midY + outward.y) / 2;
              const angle = Math.atan2(
                nextPos.y - pos.y,
                nextPos.x - pos.x
              );
              const angleDeg = (angle * 180) / Math.PI;

              return (
                <g
                  key={`arrow-${i}`}
                  style={{
                    transform: `translate(${ax}px, ${ay}px) rotate(${angleDeg}deg)`,
                    transformOrigin: "0 0",
                  }}
                >
                  <polygon
                    points="-4,-3 4,0 -4,3"
                    fill={stageColors[i]}
                    opacity={0.3}
                  />
                </g>
              );
            })}

            {/* Stage nodes */}
            {FLYWHEEL_STAGES_V2.map((stage, i) => (
              <StageNode
                key={stage.id}
                stage={stage}
                index={i}
                isActive={displayStageIdx === i}
                isHighlighted={
                  activeStageIdx === i && selectedStageIdx === null
                }
                stageColor={stageColors[i]}
                cx={stagePositions[i].x}
                cy={stagePositions[i].y}
                onClick={() => handleStageClick(i)}
              />
            ))}
          </svg>
        </div>

        {/* Tab navigation */}
        <div className="flex flex-wrap items-center gap-1.5 mb-3">
          <FlywheelTabButton
            tab="details"
            activeTab={activeTab}
            label="Details"
            icon={Sparkles}
            onClick={() => setActiveTab("details")}
          />
          <FlywheelTabButton
            tab="terminal"
            activeTab={activeTab}
            label="Terminal"
            icon={Terminal}
            onClick={() => setActiveTab("terminal")}
          />
          <FlywheelTabButton
            tab="metrics"
            activeTab={activeTab}
            label="Velocity"
            icon={TrendingUp}
            onClick={() => setActiveTab("metrics")}
          />
          <FlywheelTabButton
            tab="agents"
            activeTab={activeTab}
            label="Agents"
            icon={Bot}
            onClick={() => setActiveTab("agents")}
          />
        </div>

        {/* Tab content */}
        <AnimatePresence mode="wait">
          {activeTab === "details" && (
            <motion.div
              {...{
                key: `details-${displayStageIdx}`,
                initial: { opacity: 0, y: 10, scale: 0.97 },
                animate: { opacity: 1, y: 0, scale: 1 },
                exit: { opacity: 0, y: -10, scale: 0.97 },
                transition: { type: "spring", stiffness: 200, damping: 25 },
                className:
                  "rounded-2xl border border-white/[0.08] bg-black/30 backdrop-blur-xl p-5",
              }}
            >
              <div className="flex items-center gap-3 mb-3">
                <div
                  className="flex items-center justify-center h-8 w-8 rounded-lg"
                  style={{
                    backgroundColor: `${stageColors[displayStageIdx]}20`,
                    border: `1px solid ${stageColors[displayStageIdx]}40`,
                  }}
                >
                  {(() => {
                    const StageIcon = displayStage.icon;
                    return (
                      <StageIcon
                        className="h-4 w-4"
                        style={{ color: stageColors[displayStageIdx] }}
                      />
                    );
                  })()}
                </div>
                <div>
                  <h4 className="font-bold text-white text-sm">
                    {displayStage.label}
                  </h4>
                  <span className="text-[10px] text-white/30">
                    Stage {displayStageIdx + 1} of {STAGE_COUNT}
                  </span>
                </div>
                {selectedStageIdx !== null && (
                  <span className="ml-auto text-[10px] text-white/30">
                    click again to deselect
                  </span>
                )}
              </div>
              <p className="text-sm text-white/60 mb-4 leading-relaxed">
                {displayStage.description}
              </p>
              <div className="flex flex-wrap gap-2">
                {displayStage.tools.map((tool) => (
                  <code
                    key={tool}
                    className="inline-flex items-center gap-1 px-2.5 py-1 rounded-md bg-black/30 border border-white/[0.08] text-xs font-mono text-primary"
                  >
                    <ChevronRight className="h-3 w-3 opacity-50" />
                    {tool}
                  </code>
                ))}
              </div>
            </motion.div>
          )}

          {activeTab === "terminal" && (
            <motion.div
              {...{
                key: `terminal-${displayStageIdx}`,
                initial: { opacity: 0, y: 10, scale: 0.97 },
                animate: { opacity: 1, y: 0, scale: 1 },
                exit: { opacity: 0, y: -10, scale: 0.97 },
                transition: { type: "spring", stiffness: 200, damping: 25 },
              }}
            >
              <MiniTerminal
                commands={displayStage.commands}
                stageName={displayStage.label}
                color={stageColors[displayStageIdx]}
              />
            </motion.div>
          )}

          {activeTab === "metrics" && (
            <motion.div
              {...{
                key: "metrics",
                initial: { opacity: 0, y: 10, scale: 0.97 },
                animate: { opacity: 1, y: 0, scale: 1 },
                exit: { opacity: 0, y: -10, scale: 0.97 },
                transition: { type: "spring", stiffness: 200, damping: 25 },
                className:
                  "rounded-2xl border border-white/[0.08] bg-black/30 backdrop-blur-xl p-5",
              }}
            >
              <div className="flex items-center gap-2 mb-4">
                <Clock className="h-4 w-4 text-white/40" />
                <h4 className="text-sm font-bold text-white">
                  Velocity Over Cycles
                </h4>
                <span className="ml-auto text-[10px] text-white/30">
                  Time per iteration
                </span>
              </div>
              <div className="space-y-2">
                {CYCLE_METRICS.map((metric, i) => (
                  <VelocityBar
                    key={metric.cycle}
                    metric={metric}
                    index={i}
                    currentCycle={cycle}
                    maxCycle={maxCycle}
                  />
                ))}
              </div>
              <div className="mt-4 pt-3 border-t border-white/[0.06] flex items-center justify-between">
                <span className="text-[10px] text-white/30">
                  Each cycle compounds improvements
                </span>
                <div className="flex items-center gap-1.5">
                  <TrendingUp className="h-3 w-3 text-emerald-400/60" />
                  <span className="text-[10px] text-emerald-400/60 font-medium">
                    {cycle >= 3 ? "20x faster" : cycle >= 2 ? "2x faster" : "Baseline"}
                  </span>
                </div>
              </div>
            </motion.div>
          )}

          {activeTab === "agents" && (
            <motion.div
              {...{
                key: `agents-${displayStageIdx}`,
                initial: { opacity: 0, y: 10, scale: 0.97 },
                animate: { opacity: 1, y: 0, scale: 1 },
                exit: { opacity: 0, y: -10, scale: 0.97 },
                transition: { type: "spring", stiffness: 200, damping: 25 },
                className:
                  "rounded-2xl border border-white/[0.08] bg-black/30 backdrop-blur-xl p-5",
              }}
            >
              <div className="flex items-center gap-2 mb-4">
                <Users className="h-4 w-4 text-white/40" />
                <h4 className="text-sm font-bold text-white">
                  Agent Assignment
                </h4>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {FLYWHEEL_STAGES_V2.map((stage, i) => {
                  const isActive = displayStageIdx === i;
                  const StageIcon = stage.icon;
                  return (
                    <motion.button
                      type="button"
                      key={stage.id}
                      {...{
                        initial: { opacity: 0, y: 8 },
                        animate: { opacity: 1, y: 0 },
                        transition: {
                          type: "spring",
                          stiffness: 200,
                          damping: 25,
                          delay: i * 0.04,
                        },
                        onClick: () => handleStageClick(i),
                        className: `flex items-center gap-3 p-3 rounded-xl border text-left transition duration-200 ${
                          isActive
                            ? "border-white/[0.15] bg-white/[0.05]"
                            : "border-white/[0.06] bg-white/[0.01] hover:bg-white/[0.03]"
                        }`,
                      }}
                    >
                      <div
                        className="flex items-center justify-center h-7 w-7 rounded-md shrink-0"
                        style={{
                          backgroundColor: `${stageColors[i]}15`,
                          border: `1px solid ${stageColors[i]}30`,
                        }}
                      >
                        <StageIcon
                          className="h-3.5 w-3.5"
                          style={{ color: stageColors[i] }}
                        />
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-medium text-white/80 truncate">
                          {stage.shortLabel}
                        </div>
                        <div
                          className="text-[10px] truncate"
                          style={{ color: stageColors[i] }}
                        >
                          {stage.agent}
                        </div>
                      </div>
                      {isActive && (
                        <div className="ml-auto shrink-0">
                          <div
                            className="h-2 w-2 rounded-full animate-pulse"
                            style={{
                              backgroundColor: stageColors[i],
                            }}
                          />
                        </div>
                      )}
                    </motion.button>
                  );
                })}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}
