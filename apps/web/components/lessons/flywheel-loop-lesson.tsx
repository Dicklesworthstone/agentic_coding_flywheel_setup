"use client";

import { motion } from "@/components/motion";
import {
  RefreshCw,
  Cpu,
  Mail,
  Shield,
  Search,
  Brain,
  LayoutDashboard,
  Users,
  Zap,
  Play,
  Terminal,
  Sparkles,
  ArrowRight,
  CheckCircle2,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  InlineCode,
} from "./lesson-components";

export function FlywheelLoopLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand how all the tools work together.
      </GoalBanner>

      {/* The ACFS Flywheel */}
      <Section
        title="The ACFS Flywheel"
        icon={<RefreshCw className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          This isn&apos;t just a collection of tools. It&apos;s a{" "}
          <Highlight>compounding loop</Highlight>:
        </Paragraph>

        <div className="mt-8">
          <FlywheelDiagram />
        </div>

        <Paragraph>Each cycle makes the next one better.</Paragraph>
      </Section>

      <Divider />

      {/* The Eight Tools */}
      <Section
        title="The Eight Tools (And When To Use Them)"
        icon={<Zap className="h-5 w-5" />}
        delay={0.15}
      >
        <div className="space-y-6">
          <ToolCard
            number={1}
            name="NTM"
            subtitle="Your Cockpit"
            command="ntm"
            icon={<Cpu className="h-5 w-5" />}
            gradient="from-violet-500/20 to-purple-500/20"
            useCases={[
              "Spawn agent sessions",
              "Send prompts to multiple agents",
              "Orchestrate parallel work",
            ]}
          />

          <ToolCard
            number={2}
            name="MCP Agent Mail"
            subtitle="Coordination"
            command="am"
            icon={<Mail className="h-5 w-5" />}
            gradient="from-sky-500/20 to-blue-500/20"
            useCases={[
              "Multiple agents need to share context",
              'You want agents to "talk" to each other',
              "Coordinating complex multi-agent workflows",
            ]}
          />

          <ToolCard
            number={3}
            name="UBS"
            subtitle="Quality Guardrails"
            command="ubs"
            icon={<Shield className="h-5 w-5" />}
            gradient="from-emerald-500/20 to-teal-500/20"
            useCases={[
              "Scan code for bugs before committing",
              "Run comprehensive static analysis",
              "Catch issues early",
            ]}
            example="ubs .  # Scan current directory"
          />

          <ToolCard
            number={4}
            name="CASS"
            subtitle="Session Search"
            command="cass"
            icon={<Search className="h-5 w-5" />}
            gradient="from-amber-500/20 to-orange-500/20"
            useCases={[
              "Search across all agent session history",
              "Find previous solutions",
              "Review what agents have done",
            ]}
            example="cass  # Opens TUI"
          />

          <ToolCard
            number={5}
            name="CASS Memory (CM)"
            subtitle="Procedural Memory"
            command="cm"
            icon={<Brain className="h-5 w-5" />}
            gradient="from-rose-500/20 to-pink-500/20"
            useCases={[
              "Build persistent agent memory",
              "Distill learnings from sessions",
              "Give agents context from past work",
            ]}
            example={`cm context "Building an API"  # Get relevant memories
cm reflect                     # Update procedural memory`}
          />

          <ToolCard
            number={6}
            name="Beads Viewer"
            subtitle="Task Management"
            command="bv"
            icon={<LayoutDashboard className="h-5 w-5" />}
            gradient="from-indigo-500/20 to-violet-500/20"
            useCases={[
              "Track tasks and issues",
              "Kanban view of work",
              "Keep agents focused on goals",
            ]}
            example="bv  # Opens TUI"
          />

          <ToolCard
            number={7}
            name="CAAM"
            subtitle="Account Switching"
            command="caam"
            icon={<Users className="h-5 w-5" />}
            gradient="from-teal-500/20 to-cyan-500/20"
            useCases={[
              "You hit rate limits",
              "You want to switch between accounts",
              "Testing with different credentials",
            ]}
            example={`caam status         # See current accounts
caam activate claude backup-account`}
          />

          <ToolCard
            number={8}
            name="SLB"
            subtitle="Safety Guardrails"
            command="slb"
            icon={<Shield className="h-5 w-5" />}
            gradient="from-red-500/20 to-rose-500/20"
            useCases={[
              "Dangerous commands (when you want them reviewed)",
              "Two-person rule for destructive operations",
              "Optional safety layer",
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* A Complete Workflow */}
      <Section
        title="A Complete Workflow"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>Here&apos;s how a real session might look:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# 1. Plan your work
bv                              # Check tasks
bd ready                        # See what's ready to work on

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
bd close <task-id>`}
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* The Flywheel Effect */}
      <Section
        title="The Flywheel Effect"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>With each cycle:</Paragraph>

        <div className="mt-6">
          <FlywheelEffectList />
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
        title="Your First Real Task"
        icon={<Play className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          You&apos;re ready! Here&apos;s how to start your first project:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# 1. Create a project directory
mkcd /data/projects/my-first-project

# 2. Initialize git
git init

# 3. Initialize beads for task tracking
bd init

# (Recommended) Create a dedicated Beads sync branch
# Beads uses git worktrees for syncing; syncing to your current branch (often \`main\`)
# can cause worktree conflicts. Once you have a \`main\` branch and a remote, run:
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync

# 4. Spawn your agents
ntm spawn my-first-project --cc=2 --cod=1 --gmi=1

# 5. Start building!
ntm send my-first-project "Let's build something awesome.
What kind of project should we create?"`}
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* Getting Help */}
      <Section
        title="Getting Help"
        icon={<Zap className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="grid gap-4 sm:grid-cols-3">
          <HelpCard
            command="acfs doctor"
            description="Check everything is working"
            gradient="from-emerald-500/20 to-teal-500/20"
          />
          <HelpCard
            command="ntm --help"
            description="NTM help"
            gradient="from-violet-500/20 to-purple-500/20"
          />
          <HelpCard
            command="onboard"
            description="Re-run this tutorial anytime"
            gradient="from-amber-500/20 to-orange-500/20"
          />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// FLYWHEEL DIAGRAM - Visual representation of the flywheel
// =============================================================================
function FlywheelDiagram() {
  return (
    <div className="relative p-8 rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glow effects */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/10 rounded-full blur-3xl" />

      <div className="relative">
        {/* Main flow */}
        <div className="flex flex-col md:flex-row items-center justify-center gap-4 md:gap-6 flex-wrap">
          <FlywheelNode
            label="Plan"
            sublabel="Beads"
            icon={<LayoutDashboard className="h-5 w-5" />}
            color="from-violet-500 to-purple-500"
            delay={0.1}
          />
          <ArrowRight className="h-5 w-5 text-white/30 hidden md:block" />
          <FlywheelNode
            label="Coordinate"
            sublabel="Agent Mail"
            icon={<Mail className="h-5 w-5" />}
            color="from-sky-500 to-blue-500"
            delay={0.2}
          />
          <ArrowRight className="h-5 w-5 text-white/30 hidden md:block" />
          <FlywheelNode
            label="Execute"
            sublabel="NTM + Agents"
            icon={<Cpu className="h-5 w-5" />}
            color="from-emerald-500 to-teal-500"
            delay={0.3}
          />
        </div>

        {/* Return flow */}
        <div className="flex flex-col md:flex-row items-center justify-center gap-4 md:gap-6 mt-6 flex-wrap">
          <FlywheelNode
            label="Remember"
            sublabel="CASS Memory"
            icon={<Brain className="h-5 w-5" />}
            color="from-rose-500 to-pink-500"
            delay={0.4}
          />
          <ArrowRight className="h-5 w-5 text-white/30 rotate-180 hidden md:block" />
          <FlywheelNode
            label="Scan"
            sublabel="UBS"
            icon={<Shield className="h-5 w-5" />}
            color="from-amber-500 to-orange-500"
            delay={0.5}
          />
        </div>

        {/* Circular arrow indicator */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.6 }}
          className="absolute -right-4 top-1/2 -translate-y-1/2 hidden lg:block"
        >
          <RefreshCw className="h-12 w-12 text-primary/30" />
        </motion.div>
      </div>
    </div>
  );
}

function FlywheelNode({
  label,
  sublabel,
  icon,
  color,
  delay,
}: {
  label: string;
  sublabel: string;
  icon: React.ReactNode;
  color: string;
  delay: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay }}
      className={`flex items-center gap-3 px-5 py-3 rounded-2xl bg-gradient-to-br ${color} bg-opacity-20 border border-white/[0.1]`}
    >
      <div className="text-white">{icon}</div>
      <div>
        <span className="font-bold text-white text-sm">{label}</span>
        <span className="block text-xs text-white/50">{sublabel}</span>
      </div>
    </motion.div>
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
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: number * 0.05 }}
      className={`relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl overflow-hidden`}
    >
      <div className="flex items-start gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/10 text-white">
          {icon}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 mb-1">
            <h4 className="font-bold text-white">
              {number}. {name}
            </h4>
            <span className="text-xs text-white/40">- {subtitle}</span>
          </div>
          <code className="inline-block px-2 py-1 rounded bg-black/30 border border-white/[0.08] text-xs font-mono text-primary mb-3">
            {command}
          </code>

          <p className="text-sm text-white/60 mb-3">Use it to:</p>
          <ul className="space-y-1">
            {useCases.map((useCase, i) => (
              <li
                key={i}
                className="text-sm text-white/50 flex items-center gap-2"
              >
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
    { tool: "Agent Mail", effect: "improves coordination" },
    { tool: "NTM", effect: "sessions become more effective" },
  ];

  return (
    <div className="space-y-3">
      {effects.map((item, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.1 }}
          className="flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02]"
        >
          <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0" />
          <span className="text-white/70">
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
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className={`relative rounded-xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-4 backdrop-blur-xl text-center`}
    >
      <code className="block px-3 py-2 rounded-lg bg-black/30 border border-white/[0.08] text-sm font-mono text-primary mb-2">
        {command}
      </code>
      <span className="text-sm text-white/60">{description}</span>
    </motion.div>
  );
}
