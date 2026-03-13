"use client";

import { useState, useMemo, useCallback, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  ListTodo,
  GitBranch,
  Terminal,
  BarChart,
  Target,
  Workflow,
  CheckCircle,
  Zap,
  Network,
  Play,
  RotateCcw,
  ChevronRight,
  AlertTriangle,
  Clock,
  ArrowRight,
  Circle,
  Lock,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  CommandList,
  FeatureCard,
  FeatureGrid,
} from "./lesson-components";

export function BeadsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Track issues with dependencies and let graph analysis guide your work.
      </GoalBanner>

      {/* What Is Beads */}
      <Section
        title="What Is beads_rust (br)?"
        icon={<ListTodo className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>beads_rust</Highlight> (<code>br</code>) is a graph-aware issue tracking system
          designed for agent workflows. It tracks dependencies between tasks
          and uses graph algorithms to tell you what to work on next.
        </Paragraph>
        <Paragraph>
          <Highlight>BV (Beads Viewer)</Highlight> is the TUI and CLI for
          working with beads. It provides both interactive views and
          machine-readable outputs for agents.
        </Paragraph>
        <TipBox variant="info">
          <code>br</code> is the CLI for the beads_rust issue tracker.
          Use <code>br --help</code> for all available commands.
        </TipBox>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<GitBranch className="h-5 w-5" />}
              title="Dependency Tracking"
              description="Issues can block other issues"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<BarChart className="h-5 w-5" />}
              title="Graph Metrics"
              description="PageRank, betweenness, critical path"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Target className="h-5 w-5" />}
              title="Smart Triage"
              description="Know what to work on next"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Network className="h-5 w-5" />}
              title="Git Integration"
              description="All data lives in .beads/"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Core Commands */}
      <Section
        title="Core br Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          <code>br</code> is the CLI for managing beads issues:
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "br ready",
                description: "Show issues ready to work (no blockers)",
              },
              {
                command: "br list --status=open",
                description: "All open issues",
              },
              {
                command: "br show <id>",
                description: "Detailed view with dependencies",
              },
              {
                command: 'br create "..." -t task -p 2',
                description: "Create a new issue",
              },
              {
                command: "br update <id> --status=in_progress",
                description: "Claim work",
              },
              {
                command: "br close <id>",
                description: "Mark complete",
              },
              {
                command: "br dep add <issue> <depends-on>",
                description: "Add a dependency",
              },
              {
                command: "br sync",
                description: "Sync with git remote",
              },
            ]}
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <strong>Important:</strong> Never run bare <code>bv</code>—it
            launches a TUI. Use <code>bv --robot-*</code> flags for agent
            output.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* BV Robot Commands */}
      <Section
        title="BV Robot Commands"
        icon={<Zap className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          BV provides machine-readable outputs with precomputed graph metrics:
        </Paragraph>

        <div className="mt-6 space-y-6">
          <RobotCommand
            command="bv --robot-triage"
            description="THE mega-command: recommendations, quick wins, blockers to clear"
            output={["quick_ref", "recommendations", "quick_wins", "blockers_to_clear", "project_health"]}
            primary
          />

          <RobotCommand
            command="bv --robot-next"
            description="Just the single top pick + claim command"
            output={["next_item", "claim_command"]}
          />

          <RobotCommand
            command="bv --robot-plan"
            description="Parallel execution tracks with unblocks lists"
            output={["tracks", "dependencies", "critical_path"]}
          />

          <RobotCommand
            command="bv --robot-insights"
            description="Full graph metrics"
            output={["PageRank", "betweenness", "HITS", "eigenvector", "critical_path", "cycles", "k-core"]}
          />
        </div>
      </Section>

      <Divider />

      {/* Issue Types & Priorities */}
      <Section
        title="Issue Types & Priorities"
        icon={<ListTodo className="h-5 w-5" />}
        delay={0.25}
      >
        <div className="grid gap-6 md:grid-cols-2">
          {/* Types */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5">
            <h4 className="font-bold text-white mb-4">Types</h4>
            <div className="space-y-2">
              <TypeRow type="bug" description="Something broken" color="text-red-400" />
              <TypeRow type="feature" description="New functionality" color="text-emerald-400" />
              <TypeRow type="task" description="Work to do" color="text-primary" />
              <TypeRow type="epic" description="Large initiative" color="text-violet-400" />
              <TypeRow type="chore" description="Maintenance" color="text-white/60" />
            </div>
          </div>

          {/* Priorities */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5">
            <h4 className="font-bold text-white mb-4">Priorities (0-4)</h4>
            <div className="space-y-2">
              <PriorityRow priority="0" label="Critical" description="Security, data loss, broken builds" color="text-red-400" />
              <PriorityRow priority="1" label="High" description="Important work" color="text-amber-400" />
              <PriorityRow priority="2" label="Medium" description="Default priority" color="text-primary" />
              <PriorityRow priority="3" label="Low" description="Nice to have" color="text-white/60" />
              <PriorityRow priority="4" label="Backlog" description="Future consideration" color="text-white/60" />
            </div>
          </div>
        </div>
      </Section>

      <Divider />

      {/* The Agent Workflow */}
      <Section
        title="The Agent Workflow"
        icon={<Workflow className="h-5 w-5" />}
        delay={0.3}
      >
        <InteractiveDependencyGraph />
      </Section>

      <Divider />

      {/* Understanding Graph Metrics */}
      <Section
        title="Understanding Graph Metrics"
        icon={<BarChart className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          BV calculates graph metrics to help prioritize work:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <MetricCard
            name="PageRank"
            description="How central is this issue? High PageRank = many things depend on it"
            usage="Focus on high PageRank blockers first"
          />
          <MetricCard
            name="Betweenness"
            description="How often does this issue sit on critical paths?"
            usage="Clearing high betweenness issues unblocks the most work"
          />
          <MetricCard
            name="Critical Path"
            description="The longest chain of dependencies"
            usage="Prioritize work on the critical path to reduce total time"
          />
          <MetricCard
            name="Cycles"
            description="Circular dependencies (A blocks B, B blocks A)"
            usage="Must be resolved—they create deadlocks"
          />
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.4}
      >
        <div className="space-y-4">
          <BestPractice
            title="Start with br ready"
            description="Find work that has no blockers—you can start immediately"
          />
          <BestPractice
            title="Use br dep add for dependencies"
            description="Explicit dependencies enable smart prioritization"
          />
          <BestPractice
            title="Claim work with --status=in_progress"
            description="Prevents duplicate work by other agents"
          />
          <BestPractice
            title="Close issues promptly"
            description="Unblocks dependent work faster"
          />
          <BestPractice
            title="Run br sync at session end"
            description="Keeps .beads/ in sync across agents and machines"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Always commit <code>.beads/</code> with your code changes. It&apos;s
            the authoritative source of truth for issue state.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Play className="h-5 w-5" />}
        delay={0.45}
      >
        <CodeBlock
          code={`# See what's ready to work on
$ br ready

# Get smart triage recommendations
$ bv --robot-triage | jq '.quick_ref'

# Create a task
$ br create "Add login page" -t feature -p 2

# Start working on it
$ br update bd-1 --status=in_progress

# Sync when done
$ br sync`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// TYPE ROW
// =============================================================================
function TypeRow({
  type,
  description,
  color,
}: {
  type: string;
  description: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-3 p-2 rounded-lg transition-all duration-200 hover:bg-white/[0.04]"
    >
      <code className={`text-sm font-mono font-medium px-2 py-1 rounded bg-white/5 ${color}`}>{type}</code>
      <span className="text-sm text-white/50 group-hover:text-white/70 transition-colors">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// PRIORITY ROW
// =============================================================================
function PriorityRow({
  priority,
  label,
  description,
  color,
}: {
  priority: string;
  label: string;
  description: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-3 p-2 rounded-lg transition-all duration-200 hover:bg-white/[0.04]"
    >
      <span className={`text-sm font-mono font-bold w-6 text-center ${color}`}>{priority}</span>
      <span className={`text-sm font-medium ${color}`}>{label}</span>
      <span className="text-xs text-white/50">{"\u2014"}</span>
      <span className="text-xs text-white/60 group-hover:text-white/80 transition-colors">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// ROBOT COMMAND
// =============================================================================
function RobotCommand({
  command,
  description,
  output,
  primary,
}: {
  command: string;
  description: string;
  output: string[];
  primary?: boolean;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className={`group relative rounded-2xl border ${primary ? "border-primary/30 bg-primary/5" : "border-white/[0.08] bg-white/[0.02]"} p-5 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15]`}
    >
      {/* Subtle glow on hover */}
      <div className={`absolute inset-0 ${primary ? "bg-primary/5" : "bg-white/[0.02]"} opacity-0 group-hover:opacity-100 transition-opacity duration-300`} />

      <code className={`relative text-sm font-medium ${primary ? "text-primary" : "text-emerald-400"}`}>
        {command}
      </code>
      <p className="relative text-sm text-white/60 mt-2">{description}</p>
      <div className="relative flex flex-wrap gap-2 mt-3">
        {output.map((field) => (
          <span
            key={field}
            className="px-2 py-1 rounded bg-white/[0.05] text-xs text-white/50 font-mono group-hover:bg-white/[0.08] group-hover:text-white/70 transition-all"
          >
            {field}
          </span>
        ))}
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE DEPENDENCY GRAPH (Dramatically Enhanced)
// =============================================================================

type BeadStatus = "open" | "in_progress" | "closed";
type BeadType = "bug" | "feature" | "task" | "epic" | "chore";
type BeadPriority = 0 | 1 | 2 | 3 | 4;

interface BeadNode {
  id: string;
  title: string;
  status: BeadStatus;
  type: BeadType;
  priority: BeadPriority;
  x: number;
  y: number;
  deps: string[];
  description: string;
}

const WORKFLOW_STEPS = [
  {
    id: "create",
    title: "Create Bead",
    description: "Create a new issue with type and priority",
    command: 'br create "Setup DB schema" -t task -p 1',
    icon: "plus",
  },
  {
    id: "deps",
    title: "Add Dependencies",
    description: "Link issues that block each other",
    command: "br dep add bd-5 bd-3",
    icon: "link",
  },
  {
    id: "ready",
    title: "Check Ready Work",
    description: "Find unblocked issues to work on",
    command: "br ready",
    icon: "check",
  },
  {
    id: "claim",
    title: "Claim & Start",
    description: "Mark an issue as in-progress",
    command: "br update bd-3 --status=in_progress",
    icon: "play",
  },
  {
    id: "complete",
    title: "Complete & Close",
    description: "Mark done, unblocking dependents",
    command: "br close bd-3",
    icon: "done",
  },
  {
    id: "sync",
    title: "Sync to JSONL",
    description: "Persist state to .beads/issues.jsonl",
    command: "br sync",
    icon: "sync",
  },
] as const;

const INITIAL_BEADS: BeadNode[] = [
  {
    id: "bd-1",
    title: "Setup DB schema",
    status: "closed",
    type: "task",
    priority: 1,
    x: 60,
    y: 60,
    deps: [],
    description: "Create PostgreSQL schema with migrations",
  },
  {
    id: "bd-2",
    title: "Create API routes",
    status: "closed",
    type: "task",
    priority: 1,
    x: 60,
    y: 180,
    deps: [],
    description: "REST endpoints for core resources",
  },
  {
    id: "bd-3",
    title: "Auth middleware",
    status: "open",
    type: "feature",
    priority: 0,
    x: 250,
    y: 60,
    deps: ["bd-1"],
    description: "JWT validation and session management",
  },
  {
    id: "bd-4",
    title: "User endpoints",
    status: "open",
    type: "feature",
    priority: 2,
    x: 250,
    y: 180,
    deps: ["bd-1", "bd-2"],
    description: "CRUD for user profiles and settings",
  },
  {
    id: "bd-5",
    title: "Admin dashboard",
    status: "open",
    type: "epic",
    priority: 2,
    x: 450,
    y: 60,
    deps: ["bd-3", "bd-4"],
    description: "Admin panel with role-based access",
  },
  {
    id: "bd-6",
    title: "Email service",
    status: "open",
    type: "task",
    priority: 3,
    x: 450,
    y: 180,
    deps: ["bd-4"],
    description: "Transactional email via SendGrid",
  },
  {
    id: "bd-7",
    title: "Fix login bug",
    status: "open",
    type: "bug",
    priority: 0,
    x: 450,
    y: 290,
    deps: ["bd-3"],
    description: "Login fails when session cookie expires",
  },
  {
    id: "bd-8",
    title: "Integration tests",
    status: "open",
    type: "chore",
    priority: 2,
    x: 650,
    y: 120,
    deps: ["bd-5", "bd-6"],
    description: "E2E test suite for all endpoints",
  },
  {
    id: "bd-9",
    title: "Deploy pipeline",
    status: "open",
    type: "task",
    priority: 1,
    x: 650,
    y: 260,
    deps: ["bd-8", "bd-7"],
    description: "CI/CD pipeline with staging and prod",
  },
];

const CRITICAL_PATH_IDS = ["bd-1", "bd-3", "bd-5", "bd-8", "bd-9"];

const NODE_W = 140;
const NODE_H = 58;
const SVG_W = 820;
const SVG_H = 370;

function beadStatusColor(s: BeadStatus): {
  fill: string;
  stroke: string;
  text: string;
  badge: string;
  label: string;
  glow: string;
} {
  switch (s) {
    case "closed":
      return {
        fill: "#22c55e",
        stroke: "#16a34a",
        text: "#fff",
        badge: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30",
        label: "Closed",
        glow: "rgba(34,197,94,0.15)",
      };
    case "in_progress":
      return {
        fill: "#f59e0b",
        stroke: "#d97706",
        text: "#fff",
        badge: "bg-amber-500/20 text-amber-400 border-amber-500/30",
        label: "In Progress",
        glow: "rgba(245,158,11,0.15)",
      };
    case "open":
      return {
        fill: "#6b7280",
        stroke: "#4b5563",
        text: "#9ca3af",
        badge: "bg-white/10 text-white/50 border-white/[0.12]",
        label: "Open",
        glow: "rgba(107,114,128,0.1)",
      };
  }
}

function beadTypeInfo(t: BeadType): { color: string; label: string } {
  switch (t) {
    case "bug":
      return { color: "text-red-400", label: "Bug" };
    case "feature":
      return { color: "text-emerald-400", label: "Feature" };
    case "task":
      return { color: "text-primary", label: "Task" };
    case "epic":
      return { color: "text-violet-400", label: "Epic" };
    case "chore":
      return { color: "text-white/60", label: "Chore" };
  }
}

function priorityInfo(p: BeadPriority): {
  color: string;
  bgColor: string;
  label: string;
  urgency: string;
} {
  switch (p) {
    case 0:
      return {
        color: "text-red-400",
        bgColor: "bg-red-500/20",
        label: "P0",
        urgency: "Critical",
      };
    case 1:
      return {
        color: "text-amber-400",
        bgColor: "bg-amber-500/20",
        label: "P1",
        urgency: "High",
      };
    case 2:
      return {
        color: "text-primary",
        bgColor: "bg-primary/20",
        label: "P2",
        urgency: "Medium",
      };
    case 3:
      return {
        color: "text-white/50",
        bgColor: "bg-white/10",
        label: "P3",
        urgency: "Low",
      };
    case 4:
      return {
        color: "text-white/30",
        bgColor: "bg-white/5",
        label: "P4",
        urgency: "Backlog",
      };
  }
}

/** Determine if a bead is "ready" -- all deps are closed */
function isBeadReady(bead: BeadNode, beadMap: Map<string, BeadNode>): boolean {
  if (bead.status === "closed" || bead.status === "in_progress") return false;
  return bead.deps.every((d) => beadMap.get(d)?.status === "closed");
}

/** Compute transitive dependents count for importance scoring */
function computeImportanceScores(
  beads: BeadNode[]
): Record<string, number> {
  const dependents: Record<string, Set<string>> = {};
  for (const b of beads) dependents[b.id] = new Set();
  for (const b of beads) {
    for (const dep of b.deps) {
      dependents[dep]?.add(b.id);
    }
  }
  const scores: Record<string, number> = {};
  for (const b of beads) {
    const visited = new Set<string>();
    const queue = [b.id];
    while (queue.length) {
      const cur = queue.shift()!;
      for (const d of dependents[cur] ?? []) {
        if (!visited.has(d)) {
          visited.add(d);
          queue.push(d);
        }
      }
    }
    scores[b.id] = visited.size;
  }
  return scores;
}

function InteractiveDependencyGraph() {
  const [beads, setBeads] = useState<BeadNode[]>(INITIAL_BEADS);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [showCriticalPath, setShowCriticalPath] = useState(false);
  const [activeStep, setActiveStep] = useState(0);
  const [terminalLines, setTerminalLines] = useState<string[]>([
    "$ br ready",
    "  bd-3  P0  Auth middleware        (feature)",
    "  bd-4  P2  User endpoints         (feature)",
    "  bd-7  P0  Fix login bug          (bug)",
    "",
    "3 issues ready to work on.",
  ]);
  const [isAutoPlaying, setIsAutoPlaying] = useState(false);
  const autoPlayRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const beadMap = useMemo(
    () => new Map(beads.map((b) => [b.id, b])),
    [beads]
  );

  const importance = useMemo(
    () => computeImportanceScores(beads),
    [beads]
  );
  const maxImportance = useMemo(
    () => Math.max(1, ...Object.values(importance)),
    [importance]
  );

  // Reverse deps: what does each bead unblock?
  const unblocksMap = useMemo(() => {
    const m: Record<string, string[]> = {};
    for (const b of beads) m[b.id] = [];
    for (const b of beads) {
      for (const dep of b.deps) {
        m[dep]?.push(b.id);
      }
    }
    return m;
  }, [beads]);

  // Ready beads: open + all deps closed
  const readyBeads = useMemo(
    () => beads.filter((b) => isBeadReady(b, beadMap)),
    [beads, beadMap]
  );

  // Blocked beads: open + at least one dep not closed
  const blockedBeads = useMemo(
    () =>
      beads.filter(
        (b) =>
          b.status === "open" &&
          !isBeadReady(b, beadMap)
      ),
    [beads, beadMap]
  );

  // Stats
  const stats = useMemo(() => {
    const closed = beads.filter((b) => b.status === "closed").length;
    const inProgress = beads.filter((b) => b.status === "in_progress").length;
    return {
      total: beads.length,
      closed,
      inProgress,
      ready: readyBeads.length,
      blocked: blockedBeads.length,
      progress: Math.round((closed / beads.length) * 100),
    };
  }, [beads, readyBeads, blockedBeads]);

  const addTerminalLine = useCallback((line: string) => {
    setTerminalLines((prev) => [...prev.slice(-8), line]);
  }, []);

  const recalcBeadStatuses = useCallback(
    (updated: BeadNode[]): BeadNode[] => {
      const byId = new Map(updated.map((b) => [b.id, b]));
      return updated.map((b) => {
        if (b.status === "closed" || b.status === "in_progress") return b;
        const allDepsClosed = b.deps.every(
          (d) => byId.get(d)?.status === "closed"
        );
        // Keep open status -- readiness is computed separately
        return allDepsClosed ? b : b;
      });
    },
    []
  );

  const handleNodeClick = useCallback(
    (id: string) => {
      setSelectedId(id);
      const bead = beadMap.get(id);
      if (!bead) return;

      const ready = isBeadReady(bead, beadMap);

      if (bead.status === "open" && ready) {
        // Start working on it
        setBeads((prev) =>
          prev.map((b) =>
            b.id === id ? { ...b, status: "in_progress" as BeadStatus } : b
          )
        );
        addTerminalLine(`$ br update ${id} --status=in_progress`);
        addTerminalLine(`  Updated ${id}: open -> in_progress`);
        setTimeout(() => {
          setActiveStep(3); // claim step
        }, 0);
      } else if (bead.status === "in_progress") {
        // Complete it
        setBeads((prev) => {
          const closed = prev.map((b) =>
            b.id === id ? { ...b, status: "closed" as BeadStatus } : b
          );
          return recalcBeadStatuses(closed);
        });
        addTerminalLine(`$ br close ${id}`);
        addTerminalLine(`  Closed ${id}: ${bead.title}`);

        // Check what gets unblocked
        const unblocked = unblocksMap[id] ?? [];
        if (unblocked.length > 0) {
          setTimeout(() => {
            addTerminalLine(
              `  Unblocked: ${unblocked.join(", ")}`
            );
          }, 0);
        }
        setTimeout(() => {
          setActiveStep(4); // complete step
        }, 0);
      }
    },
    [beadMap, recalcBeadStatuses, addTerminalLine, unblocksMap]
  );

  const handleReset = useCallback(() => {
    setBeads(INITIAL_BEADS);
    setSelectedId(null);
    setHoveredId(null);
    setShowCriticalPath(false);
    setActiveStep(0);
    setIsAutoPlaying(false);
    if (autoPlayRef.current) {
      clearTimeout(autoPlayRef.current);
      autoPlayRef.current = null;
    }
    setTerminalLines([
      "$ br ready",
      "  bd-3  P0  Auth middleware        (feature)",
      "  bd-4  P2  User endpoints         (feature)",
      "  bd-7  P0  Fix login bug          (bug)",
      "",
      "3 issues ready to work on.",
    ]);
  }, []);

  const autoPlayTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearAutoPlayTimers = useCallback(() => {
    for (const t of autoPlayTimersRef.current) clearTimeout(t);
    autoPlayTimersRef.current.length = 0;
    if (autoPlayRef.current) {
      clearTimeout(autoPlayRef.current);
      autoPlayRef.current = null;
    }
  }, []);

  // Auto-play demo: walk through workflow steps
  const handleAutoPlay = useCallback(() => {
    if (isAutoPlaying) {
      setIsAutoPlaying(false);
      clearAutoPlayTimers();
      return;
    }
    handleReset();
    setIsAutoPlaying(true);
    clearAutoPlayTimers();

    // Step 0: create (already done, just show)
    const step0 = setTimeout(() => {
      setActiveStep(0);
      setTerminalLines([
        '$ br create "Setup DB schema" -t task -p 1',
        "  Created bd-1: Setup DB schema",
        '$ br create "Auth middleware" -t feature -p 0',
        "  Created bd-3: Auth middleware",
      ]);
    }, 0);
    autoPlayTimersRef.current.push(step0);
    autoPlayRef.current = step0;

    // Step 1: deps
    const t1 = setTimeout(() => {
      setActiveStep(1);
      addTerminalLine("$ br dep add bd-3 bd-1");
      addTerminalLine("  bd-3 now depends on bd-1");
      addTerminalLine("$ br dep add bd-5 bd-3");
      addTerminalLine("  bd-5 now depends on bd-3");
    }, 2500);
    autoPlayTimersRef.current.push(t1);

    // Step 2: ready
    const t2 = setTimeout(() => {
      setActiveStep(2);
      addTerminalLine("$ br ready");
      addTerminalLine("  bd-3  P0  Auth middleware");
      addTerminalLine("  bd-4  P2  User endpoints");
    }, 5000);
    autoPlayTimersRef.current.push(t2);

    // Step 3: claim bd-3
    const t3 = setTimeout(() => {
      setActiveStep(3);
      setSelectedId("bd-3");
      setBeads((prev) =>
        prev.map((b) =>
          b.id === "bd-3"
            ? { ...b, status: "in_progress" as BeadStatus }
            : b
        )
      );
      addTerminalLine("$ br update bd-3 --status=in_progress");
      addTerminalLine("  Updated bd-3: open -> in_progress");
    }, 7500);
    autoPlayTimersRef.current.push(t3);

    // Step 4: close bd-3
    const t4 = setTimeout(() => {
      setActiveStep(4);
      setBeads((prev) =>
        prev.map((b) =>
          b.id === "bd-3"
            ? { ...b, status: "closed" as BeadStatus }
            : b
        )
      );
      addTerminalLine("$ br close bd-3");
      addTerminalLine("  Closed bd-3: Auth middleware");
      addTerminalLine("  Unblocked: bd-5, bd-7");
    }, 10000);
    autoPlayTimersRef.current.push(t4);

    // Step 5: sync
    const step5 = setTimeout(() => {
      setActiveStep(5);
      addTerminalLine("$ br sync");
      addTerminalLine("  Synced 9 issues to .beads/issues.jsonl");
      addTerminalLine("  Committed to git.");
      const tEnd = setTimeout(() => {
        setIsAutoPlaying(false);
      }, 0);
      autoPlayTimersRef.current.push(tEnd);
    }, 12500);
    autoPlayTimersRef.current.push(step5);
    autoPlayRef.current = step5;
  }, [isAutoPlaying, handleReset, addTerminalLine, clearAutoPlayTimers]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearAutoPlayTimers();
    };
  }, [clearAutoPlayTimers]);

  const activeId = selectedId ?? hoveredId;
  const activeBead = activeId ? beadMap.get(activeId) : null;

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-primary/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-40 h-40 bg-amber-500/5 rounded-full blur-3xl pointer-events-none" />

      {/* ================================================================ */}
      {/* TOP: Workflow Steps Timeline */}
      {/* ================================================================ */}
      <div className="relative px-5 pt-5 pb-3">
        <div className="flex items-center gap-2 mb-3">
          <Workflow className="h-4 w-4 text-primary" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            Workflow Steps
          </span>
          <div className="flex-1" />
          <button
            onClick={handleAutoPlay}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-all duration-200 ${
              isAutoPlaying
                ? "border-amber-500/50 bg-amber-500/20 text-amber-300"
                : "border-primary/30 bg-primary/10 text-primary hover:bg-primary/20"
            }`}
          >
            <Play className="h-3 w-3" />
            {isAutoPlaying ? "Playing..." : "Auto Demo"}
          </button>
        </div>

        <div className="flex items-start gap-1 overflow-x-auto pb-2">
          {WORKFLOW_STEPS.map((step, i) => {
            const isActive = activeStep === i;
            const isPast = activeStep > i;
            return (
              <motion.button
                key={step.id}
                onClick={() => {
                  if (!isAutoPlaying) {
                    setActiveStep(i);
                  }
                }}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{
                  type: "spring",
                  stiffness: 200,
                  damping: 25,
                  delay: i * 0.05,
                }}
                className={`relative flex-shrink-0 flex flex-col items-center gap-1.5 px-3 py-2 rounded-xl text-center transition-all duration-300 min-w-[100px] ${
                  isActive
                    ? "bg-primary/15 border border-primary/40"
                    : isPast
                      ? "bg-emerald-500/10 border border-emerald-500/20"
                      : "bg-white/[0.03] border border-white/[0.06] hover:bg-white/[0.06]"
                }`}
              >
                {/* Step number */}
                <div
                  className={`flex h-6 w-6 items-center justify-center rounded-full text-[10px] font-bold ${
                    isActive
                      ? "bg-primary text-white"
                      : isPast
                        ? "bg-emerald-500 text-white"
                        : "bg-white/10 text-white/40"
                  }`}
                >
                  {isPast ? (
                    <CheckCircle className="h-3.5 w-3.5" />
                  ) : (
                    i + 1
                  )}
                </div>
                <span
                  className={`text-[10px] font-medium leading-tight ${
                    isActive
                      ? "text-primary"
                      : isPast
                        ? "text-emerald-400"
                        : "text-white/40"
                  }`}
                >
                  {step.title}
                </span>
                {/* Connector arrow */}
                {i < WORKFLOW_STEPS.length - 1 && (
                  <ChevronRight className="absolute -right-2 top-1/2 -translate-y-1/2 h-3 w-3 text-white/20" />
                )}
              </motion.button>
            );
          })}
        </div>

        {/* Active step description */}
        <AnimatePresence mode="wait">
          <motion.div
            key={activeStep}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -10 }}
            transition={{ duration: 0.2 }}
            className="mt-2 flex items-center gap-3 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/[0.06]"
          >
            <ArrowRight className="h-3 w-3 text-primary shrink-0" />
            <span className="text-xs text-white/60">
              {WORKFLOW_STEPS[activeStep].description}
            </span>
            <code className="ml-auto text-[10px] text-primary/80 font-mono whitespace-nowrap">
              {WORKFLOW_STEPS[activeStep].command}
            </code>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* ================================================================ */}
      {/* PROGRESS BAR & STATS */}
      {/* ================================================================ */}
      <div className="relative px-5 pb-3">
        <div className="flex items-center gap-4 flex-wrap">
          {/* Progress bar */}
          <div className="flex-1 min-w-[120px]">
            <div className="flex items-center justify-between mb-1">
              <span className="text-[10px] text-white/40 uppercase tracking-wider">
                Project Progress
              </span>
              <span className="text-xs font-mono text-primary">
                {stats.progress}%
              </span>
            </div>
            <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
              <motion.div
                className="h-full rounded-full bg-gradient-to-r from-primary to-emerald-500"
                initial={{ width: 0 }}
                animate={{ width: `${stats.progress}%` }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
              />
            </div>
          </div>

          {/* Stat pills */}
          <div className="flex items-center gap-2 flex-wrap">
            <StatPill
              icon={<CheckCircle className="h-3 w-3" />}
              label="Closed"
              value={stats.closed}
              color="text-emerald-400"
            />
            <StatPill
              icon={<Clock className="h-3 w-3" />}
              label="In Progress"
              value={stats.inProgress}
              color="text-amber-400"
            />
            <StatPill
              icon={<Play className="h-3 w-3" />}
              label="Ready"
              value={stats.ready}
              color="text-primary"
            />
            <StatPill
              icon={<Lock className="h-3 w-3" />}
              label="Blocked"
              value={stats.blocked}
              color="text-white/40"
            />
          </div>
        </div>
      </div>

      {/* ================================================================ */}
      {/* MAIN CONTENT: Graph + Sidebar */}
      {/* ================================================================ */}
      <div className="relative flex flex-col lg:flex-row">
        {/* SVG Dependency Graph */}
        <div className="flex-1 px-3 pb-2 min-w-0">
          {/* Toolbar */}
          <div className="flex items-center justify-between gap-3 px-2 py-2 flex-wrap">
            <p className="text-xs text-white/40">
              Click a{" "}
              <span className="text-primary font-medium">ready</span>{" "}
              node to start, click{" "}
              <span className="text-amber-400 font-medium">
                in-progress
              </span>{" "}
              to close.
            </p>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setShowCriticalPath((v) => !v)}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-all duration-200 ${
                  showCriticalPath
                    ? "border-amber-500/50 bg-amber-500/20 text-amber-300"
                    : "border-white/[0.1] bg-white/[0.04] text-white/60 hover:bg-white/[0.08] hover:text-white/80"
                }`}
              >
                {showCriticalPath ? "Hide" : "Show"} Critical Path
              </button>
              <button
                onClick={handleReset}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border border-white/[0.1] bg-white/[0.04] text-white/60 hover:bg-white/[0.08] hover:text-white/80 transition-all duration-200"
              >
                <RotateCcw className="h-3 w-3" /> Reset
              </button>
            </div>
          </div>

          <svg
            viewBox={`0 0 ${SVG_W} ${SVG_H}`}
            className="w-full h-auto"
            style={{ minHeight: 250 }}
          >
            <defs>
              {/* Arrowhead markers */}
              <marker
                id="bead-arrow-closed"
                viewBox="0 0 10 10"
                refX="10"
                refY="5"
                markerWidth="6"
                markerHeight="6"
                orient="auto-start-reverse"
              >
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#22c55e" />
              </marker>
              <marker
                id="bead-arrow-open"
                viewBox="0 0 10 10"
                refX="10"
                refY="5"
                markerWidth="6"
                markerHeight="6"
                orient="auto-start-reverse"
              >
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#4b5563" />
              </marker>
              <marker
                id="bead-arrow-in_progress"
                viewBox="0 0 10 10"
                refX="10"
                refY="5"
                markerWidth="6"
                markerHeight="6"
                orient="auto-start-reverse"
              >
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#f59e0b" />
              </marker>
              <marker
                id="bead-arrow-ready"
                viewBox="0 0 10 10"
                refX="10"
                refY="5"
                markerWidth="6"
                markerHeight="6"
                orient="auto-start-reverse"
              >
                <path
                  d="M 0 0 L 10 5 L 0 10 z"
                  fill="hsl(var(--primary))"
                />
              </marker>
              <marker
                id="bead-arrow-critical"
                viewBox="0 0 10 10"
                refX="10"
                refY="5"
                markerWidth="6"
                markerHeight="6"
                orient="auto-start-reverse"
              >
                <path d="M 0 0 L 10 5 L 0 10 z" fill="#fbbf24" />
              </marker>
              {/* Glow filter for ready nodes */}
              <filter id="bead-glow-ready">
                <feGaussianBlur stdDeviation="4" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
              {/* Glow filter for in-progress */}
              <filter id="bead-glow-progress">
                <feGaussianBlur stdDeviation="3" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            {/* Dependency edges */}
            {beads.map((bead) =>
              bead.deps.map((depId) => {
                const src = beadMap.get(depId);
                if (!src) return null;
                const srcX = src.x + NODE_W;
                const srcY = src.y + NODE_H / 2;
                const tgtX = bead.x;
                const tgtY = bead.y + NODE_H / 2;
                const midX = (srcX + tgtX) / 2;

                const isCritical =
                  showCriticalPath &&
                  CRITICAL_PATH_IDS.includes(depId) &&
                  CRITICAL_PATH_IDS.includes(bead.id);

                const ready = isBeadReady(bead, beadMap);
                const edgeStatus =
                  src.status === "closed" && ready
                    ? "ready"
                    : src.status;

                const arrowColor = isCritical
                  ? "#fbbf24"
                  : edgeStatus === "ready"
                    ? "hsl(var(--primary))"
                    : beadStatusColor(src.status).stroke;
                const markerId = isCritical
                  ? "bead-arrow-critical"
                  : edgeStatus === "ready"
                    ? "bead-arrow-ready"
                    : `bead-arrow-${src.status}`;

                // Highlight connected edges
                const isConnected =
                  activeId === bead.id || activeId === depId;

                return (
                  <path
                    key={`${depId}->${bead.id}`}
                    d={`M ${srcX} ${srcY} C ${midX} ${srcY}, ${midX} ${tgtY}, ${tgtX} ${tgtY}`}
                    fill="none"
                    stroke={arrowColor}
                    strokeWidth={
                      isCritical ? 2.5 : isConnected ? 2 : 1.5
                    }
                    strokeOpacity={
                      isCritical
                        ? 0.9
                        : isConnected
                          ? 0.8
                          : 0.4
                    }
                    markerEnd={`url(#${markerId})`}
                    className="transition-all duration-300"
                  />
                );
              })
            )}

            {/* Bead nodes */}
            {beads.map((bead) => {
              const sc = beadStatusColor(bead.status);
              const pi = priorityInfo(bead.priority);
              const ready = isBeadReady(bead, beadMap);
              const isActive = activeId === bead.id;
              const isCritical =
                showCriticalPath &&
                CRITICAL_PATH_IDS.includes(bead.id);
              const imp = importance[bead.id] ?? 0;
              const barH = Math.max(4, (imp / maxImportance) * 28);

              const isClickable =
                (bead.status === "open" && ready) ||
                bead.status === "in_progress";

              // Determine node visual state
              const nodeStroke = ready
                ? "hsl(var(--primary))"
                : sc.stroke;
              const nodeStrokeOpacity =
                bead.status === "open" && !ready ? 0.25 : 0.7;

              const dashArray = ready
                ? "6 3"
                : bead.status === "open"
                  ? "2 3"
                  : "none";

              return (
                <g
                  key={bead.id}
                  onClick={() => handleNodeClick(bead.id)}
                  onMouseEnter={() => setHoveredId(bead.id)}
                  onMouseLeave={() => setHoveredId(null)}
                  style={{
                    cursor: isClickable ? "pointer" : "default",
                  }}
                >
                  {/* Ready glow pulse */}
                  {ready && bead.status === "open" && (
                    <rect
                      x={bead.x - 3}
                      y={bead.y - 3}
                      width={NODE_W + 6}
                      height={NODE_H + 6}
                      rx={14}
                      fill="none"
                      stroke="hsl(var(--primary))"
                      strokeOpacity={0.3}
                      filter="url(#bead-glow-ready)"
                    >
                      <animate
                        attributeName="stroke-opacity"
                        values="0.15;0.5;0.15"
                        dur="2s"
                        repeatCount="indefinite"
                      />
                    </rect>
                  )}

                  {/* In-progress glow */}
                  {bead.status === "in_progress" && (
                    <rect
                      x={bead.x - 3}
                      y={bead.y - 3}
                      width={NODE_W + 6}
                      height={NODE_H + 6}
                      rx={14}
                      fill="none"
                      stroke="#f59e0b"
                      strokeOpacity={0.3}
                      filter="url(#bead-glow-progress)"
                    >
                      <animate
                        attributeName="stroke-opacity"
                        values="0.2;0.6;0.2"
                        dur="1.5s"
                        repeatCount="indefinite"
                      />
                    </rect>
                  )}

                  {/* Critical path ring */}
                  {isCritical && (
                    <rect
                      x={bead.x - 4}
                      y={bead.y - 4}
                      width={NODE_W + 8}
                      height={NODE_H + 8}
                      rx={15}
                      fill="none"
                      stroke="#fbbf24"
                      strokeWidth={2}
                      strokeOpacity={0.6}
                      strokeDasharray="8 4"
                    >
                      <animate
                        attributeName="stroke-dashoffset"
                        values="0;24"
                        dur="1.5s"
                        repeatCount="indefinite"
                      />
                    </rect>
                  )}

                  {/* Node body */}
                  <rect
                    x={bead.x}
                    y={bead.y}
                    width={NODE_W}
                    height={NODE_H}
                    rx={12}
                    fill={
                      isActive ? sc.fill : "rgba(255,255,255,0.03)"
                    }
                    fillOpacity={isActive ? 0.15 : 1}
                    stroke={nodeStroke}
                    strokeWidth={isActive ? 2 : 1.2}
                    strokeOpacity={nodeStrokeOpacity}
                    strokeDasharray={dashArray}
                  >
                    {ready && bead.status === "open" && (
                      <animate
                        attributeName="stroke-dashoffset"
                        values="0;18"
                        dur="1s"
                        repeatCount="indefinite"
                      />
                    )}
                  </rect>

                  {/* Status indicator icon */}
                  <g
                    transform={`translate(${bead.x + 10}, ${bead.y + NODE_H / 2})`}
                  >
                    {bead.status === "closed" && (
                      <g transform="translate(-5,-5)">
                        <circle
                          cx="5"
                          cy="5"
                          r="5"
                          fill="#22c55e"
                          fillOpacity={0.25}
                        />
                        <path
                          d="M 2.5 5 L 4.5 7 L 7.5 3.5"
                          stroke="#22c55e"
                          strokeWidth="1.5"
                          fill="none"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        />
                      </g>
                    )}
                    {bead.status === "open" && ready && (
                      <g transform="translate(-5,-5)">
                        <polygon
                          points="3,1.5 8.5,5 3,8.5"
                          fill="hsl(var(--primary))"
                          fillOpacity={0.8}
                        />
                      </g>
                    )}
                    {bead.status === "in_progress" && (
                      <g transform="translate(-5,-5)">
                        <circle
                          cx="5"
                          cy="5"
                          r="4"
                          fill="none"
                          stroke="#f59e0b"
                          strokeWidth="1.5"
                          strokeDasharray="6 6"
                        >
                          <animateTransform
                            attributeName="transform"
                            type="rotate"
                            from="0 5 5"
                            to="360 5 5"
                            dur="1s"
                            repeatCount="indefinite"
                          />
                        </circle>
                      </g>
                    )}
                    {bead.status === "open" && !ready && (
                      <g transform="translate(-5,-6)">
                        <rect
                          x="1.5"
                          y="5"
                          width="7"
                          height="5.5"
                          rx="1"
                          fill="#6b7280"
                          fillOpacity={0.5}
                        />
                        <path
                          d="M 3 5 V 3.5 A 2 2 0 0 1 7 3.5 V 5"
                          stroke="#6b7280"
                          strokeWidth="1.2"
                          fill="none"
                        />
                      </g>
                    )}
                  </g>

                  {/* Priority badge */}
                  <g
                    transform={`translate(${bead.x + NODE_W - 26}, ${bead.y + 6})`}
                  >
                    <rect
                      x="0"
                      y="0"
                      width="20"
                      height="13"
                      rx="4"
                      fill={
                        bead.priority === 0
                          ? "#ef4444"
                          : bead.priority === 1
                            ? "#f59e0b"
                            : "rgba(255,255,255,0.08)"
                      }
                      fillOpacity={
                        bead.priority <= 1 ? 0.3 : 1
                      }
                    />
                    <text
                      x="10"
                      y="10"
                      fill={
                        bead.priority === 0
                          ? "#fca5a5"
                          : bead.priority === 1
                            ? "#fcd34d"
                            : "rgba(255,255,255,0.4)"
                      }
                      fontSize="7"
                      fontWeight="700"
                      fontFamily="monospace"
                      textAnchor="middle"
                    >
                      {pi.label}
                    </text>
                  </g>

                  {/* Bead ID */}
                  <text
                    x={bead.x + 22}
                    y={bead.y + 18}
                    fill={sc.text}
                    fillOpacity={
                      bead.status === "open" && !ready
                        ? 0.35
                        : 0.55
                    }
                    fontSize="8"
                    fontFamily="monospace"
                  >
                    {bead.id}
                  </text>

                  {/* Bead title */}
                  <text
                    x={bead.x + 22}
                    y={bead.y + 34}
                    fill={sc.text}
                    fillOpacity={
                      bead.status === "open" && !ready
                        ? 0.45
                        : 0.9
                    }
                    fontSize="10"
                    fontWeight="600"
                  >
                    {bead.title.length > 15
                      ? bead.title.slice(0, 14) + "\u2026"
                      : bead.title}
                  </text>

                  {/* Type label */}
                  <text
                    x={bead.x + 22}
                    y={bead.y + 48}
                    fill={
                      bead.type === "bug"
                        ? "#f87171"
                        : bead.type === "feature"
                          ? "#34d399"
                          : bead.type === "epic"
                            ? "#a78bfa"
                            : "rgba(255,255,255,0.3)"
                    }
                    fontSize="8"
                    fontStyle="italic"
                  >
                    {bead.type}
                  </text>

                  {/* Importance bar */}
                  <rect
                    x={bead.x + NODE_W + 4}
                    y={bead.y + NODE_H - barH}
                    width={5}
                    height={barH}
                    rx={2}
                    fill={ready ? "hsl(var(--primary))" : sc.fill}
                    fillOpacity={0.5}
                  />
                  {imp > 0 && (
                    <text
                      x={bead.x + NODE_W + 6.5}
                      y={bead.y + NODE_H - barH - 3}
                      fill={sc.text}
                      fillOpacity={0.4}
                      fontSize="7"
                      textAnchor="middle"
                    >
                      {imp}
                    </text>
                  )}
                </g>
              );
            })}

            {/* Legend */}
            <g transform="translate(10, 340)">
              {(
                [
                  ["closed", "#22c55e", "Closed"],
                  ["ready", "hsl(var(--primary))", "Ready"],
                  ["in_progress", "#f59e0b", "In Progress"],
                  ["blocked", "#6b7280", "Blocked"],
                ] as const
              ).map(([, color, label], i) => (
                <g
                  key={label}
                  transform={`translate(${i * 120}, 0)`}
                >
                  <circle
                    cx={6}
                    cy={6}
                    r={5}
                    fill={color}
                    fillOpacity={0.6}
                  />
                  <text
                    x={16}
                    y={10}
                    fill="white"
                    fillOpacity={0.5}
                    fontSize="9"
                  >
                    {label}
                  </text>
                </g>
              ))}
              <g transform="translate(490, 0)">
                <rect
                  x={0}
                  y={1}
                  width={12}
                  height={10}
                  rx={2}
                  fill="transparent"
                  stroke="#fbbf24"
                  strokeWidth={1.5}
                  strokeDasharray="4 2"
                />
                <text
                  x={18}
                  y={10}
                  fill="white"
                  fillOpacity={0.5}
                  fontSize="9"
                >
                  Critical Path
                </text>
              </g>
              <g transform="translate(610, 0)">
                <rect
                  x={0}
                  y={2}
                  width={5}
                  height={8}
                  rx={1}
                  fill="white"
                  fillOpacity={0.3}
                />
                <text
                  x={10}
                  y={10}
                  fill="white"
                  fillOpacity={0.5}
                  fontSize="9"
                >
                  Importance
                </text>
              </g>
            </g>
          </svg>
        </div>

        {/* ================================================================ */}
        {/* SIDEBAR: Ready Queue + Mini Terminal */}
        {/* ================================================================ */}
        <div className="lg:w-72 shrink-0 border-t lg:border-t-0 lg:border-l border-white/[0.06] p-4 space-y-4">
          {/* Ready Work Queue */}
          <div>
            <div className="flex items-center gap-2 mb-3">
              <Target className="h-3.5 w-3.5 text-primary" />
              <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
                Ready Queue
              </span>
              <span className="ml-auto text-[10px] font-mono text-primary">
                {readyBeads.length}
              </span>
            </div>

            <div className="space-y-2">
              <AnimatePresence mode="popLayout">
                {readyBeads.length === 0 ? (
                  <motion.div
                    key="empty"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="text-xs text-white/30 italic px-2 py-3 text-center"
                  >
                    No beads ready. Close blockers first.
                  </motion.div>
                ) : (
                  [...readyBeads]
                    .sort((a, b) => a.priority - b.priority)
                    .map((bead) => {
                      const pi = priorityInfo(bead.priority);
                      const ti = beadTypeInfo(bead.type);
                      return (
                        <motion.button
                          key={bead.id}
                          initial={{ opacity: 0, x: 20 }}
                          animate={{ opacity: 1, x: 0 }}
                          exit={{ opacity: 0, x: -20 }}
                          transition={{
                            type: "spring",
                            stiffness: 200,
                            damping: 25,
                          }}
                          onClick={() => handleNodeClick(bead.id)}
                          onMouseEnter={() =>
                            setHoveredId(bead.id)
                          }
                          onMouseLeave={() =>
                            setHoveredId(null)
                          }
                          className={`w-full text-left px-3 py-2 rounded-lg border transition-all duration-200 ${
                            activeId === bead.id
                              ? "border-primary/40 bg-primary/10"
                              : "border-white/[0.06] bg-white/[0.02] hover:bg-white/[0.05]"
                          }`}
                        >
                          <div className="flex items-center gap-2">
                            <span
                              className={`text-[10px] font-mono font-bold ${pi.color}`}
                            >
                              {pi.label}
                            </span>
                            <code className="text-[10px] text-white/40 font-mono">
                              {bead.id}
                            </code>
                            <span
                              className={`ml-auto text-[9px] ${ti.color}`}
                            >
                              {ti.label}
                            </span>
                          </div>
                          <p className="text-xs text-white/70 mt-1 truncate">
                            {bead.title}
                          </p>
                        </motion.button>
                      );
                    })
                )}
              </AnimatePresence>
            </div>
          </div>

          {/* Blocked Queue */}
          <div>
            <div className="flex items-center gap-2 mb-2">
              <Lock className="h-3.5 w-3.5 text-white/30" />
              <span className="text-xs font-semibold text-white/50 uppercase tracking-wider">
                Blocked
              </span>
              <span className="ml-auto text-[10px] font-mono text-white/30">
                {blockedBeads.length}
              </span>
            </div>
            <div className="space-y-1">
              {blockedBeads.slice(0, 4).map((bead) => {
                const blockerIds = bead.deps.filter(
                  (d) => beadMap.get(d)?.status !== "closed"
                );
                return (
                  <div
                    key={bead.id}
                    className="flex items-center gap-2 px-2 py-1.5 rounded text-[10px]"
                    onMouseEnter={() => setHoveredId(bead.id)}
                    onMouseLeave={() => setHoveredId(null)}
                  >
                    <code className="text-white/30 font-mono">
                      {bead.id}
                    </code>
                    <span className="text-white/40 truncate flex-1">
                      {bead.title}
                    </span>
                    <span className="text-red-400/60 whitespace-nowrap">
                      {"\u2190"} {blockerIds.join(", ")}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Mini Terminal */}
          <div>
            <div className="flex items-center gap-2 mb-2">
              <Terminal className="h-3.5 w-3.5 text-emerald-400/70" />
              <span className="text-xs font-semibold text-white/50 uppercase tracking-wider">
                Terminal
              </span>
            </div>
            <MiniTerminal lines={terminalLines} />
          </div>
        </div>
      </div>

      {/* ================================================================ */}
      {/* DETAIL PANEL */}
      {/* ================================================================ */}
      <AnimatePresence mode="wait">
        {activeBead && (
          <motion.div
            key={activeBead.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={{ duration: 0.15 }}
            className="relative mx-4 mb-4 rounded-xl border border-white/[0.08] bg-white/[0.03] backdrop-blur-xl overflow-hidden"
          >
            {/* Status color bar */}
            <div
              className="h-1"
              style={{
                background: `linear-gradient(90deg, ${beadStatusColor(activeBead.status).fill}, transparent)`,
              }}
            />

            <div className="p-4">
              {/* Header row */}
              <div className="flex items-start justify-between gap-4 flex-wrap">
                <div className="space-y-2">
                  <div className="flex items-center gap-2 flex-wrap">
                    <code className="text-xs text-white/50 font-mono">
                      {activeBead.id}
                    </code>
                    <span
                      className={`px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider border ${beadStatusColor(activeBead.status).badge}`}
                    >
                      {isBeadReady(activeBead, beadMap) &&
                      activeBead.status === "open"
                        ? "Ready"
                        : beadStatusColor(activeBead.status)
                            .label}
                    </span>
                    <span
                      className={`px-1.5 py-0.5 rounded text-[10px] font-mono font-bold ${priorityInfo(activeBead.priority).color} ${priorityInfo(activeBead.priority).bgColor}`}
                    >
                      {priorityInfo(activeBead.priority).label}{" "}
                      {priorityInfo(activeBead.priority).urgency}
                    </span>
                    <span
                      className={`text-[10px] italic ${beadTypeInfo(activeBead.type).color}`}
                    >
                      {beadTypeInfo(activeBead.type).label}
                    </span>
                  </div>
                  <p className="text-sm font-semibold text-white">
                    {activeBead.title}
                  </p>
                  <p className="text-xs text-white/40">
                    {activeBead.description}
                  </p>
                </div>
                <div className="flex items-center gap-1 text-xs text-white/30">
                  <BarChart className="h-3 w-3" />
                  <span>
                    Importance:{" "}
                    {importance[activeBead.id] ?? 0}
                  </span>
                </div>
              </div>

              {/* Deps & Unblocks */}
              <div className="grid grid-cols-2 gap-4 mt-3">
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-white/30 mb-1">
                    Depends on
                  </p>
                  {activeBead.deps.length === 0 ? (
                    <p className="text-xs text-white/40 italic">
                      None (root bead)
                    </p>
                  ) : (
                    <div className="flex flex-wrap gap-1">
                      {activeBead.deps.map((d) => {
                        const dep = beadMap.get(d);
                        const isClosed =
                          dep?.status === "closed";
                        return (
                          <span
                            key={d}
                            className={`px-1.5 py-0.5 rounded text-[10px] font-mono flex items-center gap-1 ${
                              dep
                                ? beadStatusColor(dep.status)
                                    .badge
                                : "bg-white/10 text-white/40"
                            }`}
                          >
                            {isClosed ? (
                              <CheckCircle className="h-2.5 w-2.5" />
                            ) : (
                              <AlertTriangle className="h-2.5 w-2.5" />
                            )}
                            {d}
                          </span>
                        );
                      })}
                    </div>
                  )}
                </div>
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-white/30 mb-1">
                    Unblocks
                  </p>
                  {(unblocksMap[activeBead.id] ?? []).length ===
                  0 ? (
                    <p className="text-xs text-white/40 italic">
                      None (leaf bead)
                    </p>
                  ) : (
                    <div className="flex flex-wrap gap-1">
                      {(
                        unblocksMap[activeBead.id] ?? []
                      ).map((bId) => {
                        const bt = beadMap.get(bId);
                        return (
                          <span
                            key={bId}
                            className={`px-1.5 py-0.5 rounded text-[10px] font-mono ${bt ? beadStatusColor(bt.status).badge : "bg-white/10 text-white/40"}`}
                          >
                            {bId}
                          </span>
                        );
                      })}
                    </div>
                  )}
                </div>
              </div>

              {/* Action hints */}
              {activeBead.status === "open" &&
                isBeadReady(activeBead, beadMap) && (
                  <div className="mt-3 flex items-center gap-2 px-3 py-2 rounded-lg bg-primary/10 border border-primary/20">
                    <Play className="h-3 w-3 text-primary" />
                    <p className="text-[10px] text-primary font-medium">
                      Click to claim and start working on this
                      bead
                    </p>
                    <code className="ml-auto text-[9px] text-primary/60 font-mono">
                      br update {activeBead.id}{" "}
                      --status=in_progress
                    </code>
                  </div>
                )}
              {activeBead.status === "in_progress" && (
                <div className="mt-3 flex items-center gap-2 px-3 py-2 rounded-lg bg-amber-500/10 border border-amber-500/20">
                  <CheckCircle className="h-3 w-3 text-amber-400" />
                  <p className="text-[10px] text-amber-400 font-medium">
                    Click to mark complete and unblock
                    downstream beads
                  </p>
                  <code className="ml-auto text-[9px] text-amber-400/60 font-mono">
                    br close {activeBead.id}
                  </code>
                </div>
              )}
              {activeBead.status === "open" &&
                !isBeadReady(activeBead, beadMap) && (
                  <div className="mt-3 flex items-center gap-2 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/[0.06]">
                    <Lock className="h-3 w-3 text-white/30" />
                    <p className="text-[10px] text-white/40 font-medium">
                      Blocked by unfinished dependencies
                    </p>
                  </div>
                )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// STAT PILL
// =============================================================================
function StatPill({
  icon,
  label,
  value,
  color,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  color: string;
}) {
  return (
    <div
      className={`flex items-center gap-1.5 px-2 py-1 rounded-lg bg-white/[0.03] border border-white/[0.06] ${color}`}
    >
      {icon}
      <span className="text-[10px] font-medium">{label}</span>
      <span className="text-[10px] font-mono font-bold">{value}</span>
    </div>
  );
}

// =============================================================================
// MINI TERMINAL
// =============================================================================
function MiniTerminal({ lines }: { lines: string[] }) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      const el = scrollRef.current;
      // Wrap in setTimeout to avoid synchronous state in useEffect
      setTimeout(() => {
        el.scrollTop = el.scrollHeight;
      }, 0);
    }
  }, [lines]);

  return (
    <div className="rounded-lg border border-white/[0.08] bg-black/40 overflow-hidden">
      {/* Title bar */}
      <div className="flex items-center gap-1.5 px-3 py-1.5 bg-white/[0.04] border-b border-white/[0.06]">
        <Circle className="h-2 w-2 text-red-400/60" />
        <Circle className="h-2 w-2 text-amber-400/60" />
        <Circle className="h-2 w-2 text-emerald-400/60" />
        <span className="ml-2 text-[9px] text-white/30 font-mono">
          br terminal
        </span>
      </div>
      {/* Output */}
      <div
        ref={scrollRef}
        className="px-3 py-2 max-h-40 overflow-y-auto"
        style={{ scrollBehavior: "smooth" }}
      >
        <AnimatePresence mode="popLayout">
          {lines.map((line, i) => (
            <motion.div
              key={`${i}-${line}`}
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className={`text-[10px] font-mono leading-relaxed ${
                line.startsWith("$")
                  ? "text-emerald-400"
                  : line.startsWith("  Unblocked")
                    ? "text-primary"
                    : line.startsWith("  Updated") ||
                        line.startsWith("  Created") ||
                        line.startsWith("  Closed") ||
                        line.startsWith("  Synced")
                      ? "text-amber-300"
                      : "text-white/50"
              }`}
            >
              {line || "\u00A0"}
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// METRIC CARD
// =============================================================================
function MetricCard({
  name,
  description,
  usage,
}: {
  name: string;
  description: string;
  usage: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-primary/30"
    >
      {/* Gradient overlay on hover */}
      <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-violet-500/5 opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <h4 className="relative font-bold text-white flex items-center gap-3">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20 text-primary shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
          <BarChart className="h-4 w-4" />
        </div>
        <span className="group-hover:text-primary transition-colors">{name}</span>
      </h4>
      <p className="relative text-sm text-white/60 mt-3">{description}</p>
      <p className="relative text-sm text-primary/80 mt-3 font-medium">{"\u2192"} {usage}</p>
    </motion.div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-emerald-500/20 bg-emerald-500/5 backdrop-blur-xl transition-all duration-300 hover:border-emerald-500/40 hover:bg-emerald-500/10"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400 shadow-lg shadow-emerald-500/10 group-hover:shadow-emerald-500/20 transition-shadow">
        <CheckCircle className="h-5 w-5" />
      </div>
      <div>
        <p className="font-semibold text-white group-hover:text-emerald-300 transition-colors">{title}</p>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}
