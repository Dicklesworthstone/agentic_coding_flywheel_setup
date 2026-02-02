"use client";

import { motion } from "@/components/motion";
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
              <PriorityRow priority="4" label="Backlog" description="Future consideration" color="text-white/40" />
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
        <AgentWorkflow />
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
      <span className="text-xs text-white/40">—</span>
      <span className="text-xs text-white/40 group-hover:text-white/60 transition-colors">{description}</span>
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
// AGENT WORKFLOW
// =============================================================================
function AgentWorkflow() {
  const steps = [
    { icon: <Target className="h-5 w-5" />, title: "br ready", desc: "Find unblocked work" },
    { icon: <ListTodo className="h-5 w-5" />, title: "br show <id>", desc: "Review issue details" },
    { icon: <Play className="h-5 w-5" />, title: "br update --status=in_progress", desc: "Claim the work" },
    { icon: <Zap className="h-5 w-5" />, title: "Implement + test", desc: "Do the actual work" },
    { icon: <CheckCircle className="h-5 w-5" />, title: "br close <id>", desc: "Mark complete" },
    { icon: <GitBranch className="h-5 w-5" />, title: "br sync", desc: "Sync with remote" },
  ];

  return (
    <div className="relative p-6 rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Decorative glow */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-emerald-500/10 rounded-full blur-3xl" />

      <div className="relative space-y-5">
        <div className="absolute left-5 top-5 bottom-5 w-px bg-gradient-to-b from-primary/50 via-violet-500/50 to-emerald-500/50" />

        {steps.map((step, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.08 }}
            whileHover={{ x: 4 }}
            className="relative flex items-start gap-4 pl-2 group"
          >
            <div className="relative z-10 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white shadow-lg shadow-primary/30 group-hover:shadow-xl group-hover:shadow-primary/40 transition-shadow duration-300">
              {step.icon}
            </div>
            <div className="pt-1.5">
              <code className="text-sm text-primary font-medium group-hover:text-white transition-colors">{step.title}</code>
              <p className="text-sm text-white/50">{step.desc}</p>
            </div>
          </motion.div>
        ))}
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
      <p className="relative text-sm text-primary/80 mt-3 font-medium">→ {usage}</p>
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
