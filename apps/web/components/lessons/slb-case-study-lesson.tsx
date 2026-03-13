"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Lightbulb,
  FileText,
  Bot,
  GitBranch,
  Shield,
  MessageSquare,
  LayoutDashboard,
  Clock,
  ArrowRight,
  CheckCircle2,
  Terminal,
  Play,
  Zap,
  Key,
  RefreshCw,
  AlertTriangle,
  Lock,
  Unlock,
  XCircle,
  Database,
  Cloud,
  RotateCcw,
  Gauge,
  FileKey,
  Trash2,
  ChevronRight,
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
  BulletList,
  StepList,
} from "./lesson-components";

export function SlbCaseStudyLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        See how a tweet becomes working code in one evening: 76 beads, 268
        commits, from idea to ~70% complete in hours.
      </GoalBanner>

      {/* The Spark */}
      <Section
        title="The Spark: From Tweet to Tool"
        icon={<Lightbulb className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          On December 13, 2025, a conversation on X about AI agents
          accidentally deleting Kubernetes nodes sparked an idea: what if
          dangerous commands required{" "}
          <Highlight>peer review from another agent</Highlight>?
        </Paragraph>

        <div className="mt-8">
          <IdeaCard />
        </div>

        <Paragraph>
          The idea was simple: like the &quot;two-person rule&quot; for nuclear
          launch codes, agents should need a second opinion before running
          destructive commands like <InlineCode>rm -rf</InlineCode>,{" "}
          <InlineCode>kubectl delete</InlineCode>, or{" "}
          <InlineCode>DROP TABLE</InlineCode>.
        </Paragraph>
      </Section>

      <Divider />

      {/* Immediate Action */}
      <Section
        title="Immediate Action: The First Hour"
        icon={<Zap className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          Instead of just noting the idea for later, the flywheel approach is to{" "}
          <Highlight>start immediately</Highlight> while the idea is fresh.
        </Paragraph>

        <div className="mt-6">
          <TimelineCard />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            The key insight: an initial plan within the first hour, even if
            rough, is worth more than a perfect plan days later. The agents will
            help refine it.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Multi-Model Feedback */}
      <Section
        title="The Feedback Loop: Four Models, One Plan"
        icon={<MessageSquare className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          Once the initial plan existed, it was sent to multiple frontier models
          for review and improvement:
        </Paragraph>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <FeedbackCard
            model="Claude Opus 4.5"
            focus="Architecture refinement"
            color="from-amber-500/20 to-orange-500/20"
          />
          <FeedbackCard
            model="Gemini 3 Deep Think"
            focus="Edge case analysis"
            color="from-blue-500/20 to-indigo-500/20"
          />
          <FeedbackCard
            model="GPT 5.2 Pro"
            focus="Security considerations"
            color="from-emerald-500/20 to-teal-500/20"
          />
          <FeedbackCard
            model="Claude (synthesis)"
            focus="Combining all feedback"
            color="from-violet-500/20 to-purple-500/20"
          />
        </div>

        <div className="mt-6">
          <Paragraph>
            The feedback was then integrated by Claude Code, with{" "}
            <strong>multiple verification passes</strong> to ensure nothing was
            missed:
          </Paragraph>
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# First pass: Integrate all feedback
cc "Revise the plan document using all the feedback.
Make sure ALL changes are reflected properly."

# Second pass: Verification
cc "Go over everything again. Did we miss anything?"
# Result: Found small oversights

# Third pass: Final check
cc "One more careful review. Any remaining gaps?"
# Result: Found 2 more edge cases`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Each verification pass found something. This is why multiple passes
            are critical - they catch problems in the planning phase when
            they&apos;re easiest to fix.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Converting to Beads */}
      <Section
        title="Plan to Beads: Making It Executable"
        icon={<LayoutDashboard className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          The refined plan was then transformed into structured, trackable
          beads. The prompt was carefully crafted to ensure thoroughness:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`cc "First read ALL of the AGENTS.md file and
PLAN_TO_MAKE_SLB.md file super carefully.
Understand ALL of both! Use /effort max.

Take ALL of that and elaborate on it more, then create
a comprehensive and granular set of beads with:
- Tasks and subtasks
- Dependency structure
- Detailed comments making everything self-contained
- Background, reasoning, justification
- Anything our 'future self' would need to know

Use the br tool repeatedly to create the actual beads."`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <BeadsResultCard />
        </div>

        <div className="mt-6">
          <Paragraph>
            Then, just like the plan itself, the beads went through verification
            passes:
          </Paragraph>
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Beads verification prompt
cc "Check over each bead super carefully:
- Does it make sense?
- Is it optimal?
- Could we change anything to make the system work better?

If so, revise the beads. It's a lot easier and faster
to operate in 'plan space' before implementing!"`}
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* What SLB Does */}
      <Section
        title="What SLB Does"
        icon={<Shield className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          The Simultaneous Launch Button implements a{" "}
          <Highlight>two-person rule</Highlight> for AI coding agents:
        </Paragraph>

        <div className="mt-6">
          <RiskTierCard />
        </div>

        <div className="mt-8">
          <BulletList
            items={[
              <span key="1">
                <strong>Client-side execution:</strong> Commands run in the
                user&apos;s shell, inheriting all credentials
              </span>,
              <span key="2">
                <strong>Command hash binding:</strong> Approvals tied to exact
                commands via SHA-256
              </span>,
              <span key="3">
                <strong>Pre-flight validation:</strong> Automatic dry-runs for
                supported commands
              </span>,
              <span key="4">
                <strong>Rollback capture:</strong> System state saved before
                dangerous operations
              </span>,
              <span key="5">
                <strong>Agent Mail integration:</strong> Reviewers notified
                automatically
              </span>,
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* The Implementation Sprint */}
      <Section
        title="The Implementation Sprint"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          With beads ready, the agent swarm began implementation. The project
          was smaller than cass-memory, but the workflow was identical:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Launch agents
ntm spawn slb --cc=3 --cod=2

# Each agent runs:
bv --robot-triage        # What's ready?
br update <id> --status in_progress
# ... implement ...
br close <id>

# Commit agent runs every 15-20 min
cc "Commit all changes in logical groupings with
detailed messages. Don't edit code. Push when done."`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <ResultsCard />
        </div>

        <Paragraph>
          By dinner time, about two-thirds of the project was complete. The
          agent swarm continued working while the developer ate, pushing commits
          autonomously.
        </Paragraph>

        <div className="mt-8">
          <InteractiveBuildTimeline />
        </div>
      </Section>

      <Divider />

      {/* Key Differences from Large Projects */}
      <Section
        title="Small vs Large Projects"
        icon={<RefreshCw className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>
          Compared to the 693-bead cass-memory project, SLB&apos;s 76 beads
          allowed for some workflow optimizations:
        </Paragraph>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <ComparisonCard
            title="Small Project (SLB)"
            items={[
              "76 beads (14 epics, 62 tasks)",
              "3-5 agents sufficient",
              "Faster verification passes",
              "Easier to track in bv",
              "One evening to ~70%",
            ]}
            gradient="from-emerald-500/20 to-teal-500/20"
          />
          <ComparisonCard
            title="Large Project (cass-memory)"
            items={[
              "693 beads (14 epics, 350+ tasks)",
              "10+ agents needed",
              "Multiple planning sessions",
              "Graph analysis critical",
              "One day to ~85%",
            ]}
            gradient="from-violet-500/20 to-purple-500/20"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Start with smaller projects to learn the workflow. Once
            you&apos;re comfortable with 50-100 beads, scale up to larger
            projects.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Lessons Learned */}
      <Section
        title="Lessons Learned"
        icon={<CheckCircle2 className="h-5 w-5" />}
        delay={0.45}
      >
        <StepList
          steps={[
            {
              title: "Act immediately on good ideas",
              description:
                "An hour from idea to initial plan keeps momentum high",
            },
            {
              title: "Multi-model feedback finds blind spots",
              description:
                "Each model brings different perspectives and catches different issues",
            },
            {
              title: "Multiple verification passes are essential",
              description:
                "Each pass found something - never skip this step",
            },
            {
              title: "Smaller projects are great for learning",
              description:
                "76 beads is manageable while still demonstrating the full workflow",
            },
            {
              title: "Document everything",
              description:
                "The conversation transcripts become valuable learning resources",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Try It Yourself */}
      <Section
        title="Try It Yourself: Weekend Project"
        icon={<Play className="h-5 w-5" />}
        delay={0.5}
      >
        <Paragraph>
          Pick a small tool idea (something that would take you a day or two
          manually) and try this workflow:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Hour 1: Draft initial plan
cc "I want to build [your idea]. Help me create a
detailed plan document covering architecture,
features, and implementation approach."

# Hour 2: Multi-model feedback
# Send plan to 2-3 different frontier models
# Collect their suggestions and improvements

# Hour 3: Synthesize and create beads
cc "Read the plan and all feedback. Create a
revised plan incorporating the best suggestions."

cc "Convert the plan into 50-100 beads with
dependencies. Use br CLI."

# Hour 4+: Implementation
ntm spawn myproject --cc=2 --cod=1
# Let the swarm work!

# Every 15-20 min: Commit agent
cc "Commit all changes with detailed messages."`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            For your first flywheel project, aim for something with 50-100 beads.
            CLI tools, utilities, and small libraries are perfect candidates.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// IDEA CARD - The tweet inspiration
// =============================================================================
function IdeaCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-amber-500/50"
    >
      <div className="flex items-start gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-amber-500 to-orange-500">
          <Lightbulb className="h-6 w-6 text-white" />
        </div>
        <div>
          <h4 className="font-bold text-white mb-2">The WarGames Insight</h4>
          <p className="text-white/70 text-sm italic">
            &quot;You know how in movies like WarGames they show how the two
            guys have to turn the keys at the same time to arm the nuclear
            warheads? I want to make something like that where for potentially
            damaging commands, the agents have to get one other agent to agree
            with their reasoning and sign off on the command.&quot;
          </p>
          <div className="mt-3 flex items-center gap-2 text-xs text-white/50">
            <Key className="h-3 w-3" />
            <span>Two-person rule for AI agents</span>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// TIMELINE CARD
// =============================================================================
function TimelineCard() {
  const steps = [
    { time: "3:55 PM", event: "Idea sparked from tweet", icon: Lightbulb },
    { time: "~4:30 PM", event: "Initial plan drafted with Claude Code", icon: FileText },
    { time: "5:25 PM", event: "Plan document published", icon: GitBranch },
    { time: "Evening", event: "Multi-model feedback gathered", icon: MessageSquare },
    { time: "Night", event: "Beads created, implementation started", icon: LayoutDashboard },
  ];

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      whileHover={{ y: -2 }}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15]"
    >
      <h4 className="font-bold text-white mb-4 flex items-center gap-2">
        <Clock className="h-5 w-5 text-primary" />
        December 13, 2025 Timeline
      </h4>

      <div className="space-y-4">
        {steps.map((step, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.1 }}
            whileHover={{ x: 6 }}
            className="group flex items-center gap-4 p-2 -mx-2 rounded-lg transition-all duration-300 hover:bg-white/[0.02]"
          >
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary/20 group-hover:bg-primary/30 group-hover:shadow-lg group-hover:shadow-primary/20 transition-all">
              <step.icon className="h-4 w-4 text-primary" />
            </div>
            <div className="flex-1 flex items-center gap-3">
              <span className="text-xs font-mono text-white/50 w-20">
                {step.time}
              </span>
              <ArrowRight className="h-3 w-3 text-white/50 group-hover:text-primary/60 transition-colors" />
              <span className="text-sm text-white/70 group-hover:text-white/90 transition-colors">{step.event}</span>
            </div>
          </motion.div>
        ))}
      </div>
    </motion.div>
  );
}

// =============================================================================
// FEEDBACK CARD
// =============================================================================
function FeedbackCard({
  model,
  focus,
  color,
}: {
  model: string;
  focus: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group rounded-xl border border-white/[0.08] bg-gradient-to-br ${color} p-4 backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]`}
    >
      <div className="flex items-center gap-2 mb-2">
        <Bot className="h-4 w-4 text-white/80 group-hover:scale-110 transition-transform" />
        <span className="font-semibold text-white text-sm">{model}</span>
      </div>
      <p className="text-xs text-white/60 group-hover:text-white/80 transition-colors">{focus}</p>
    </motion.div>
  );
}

// =============================================================================
// BEADS RESULT CARD
// =============================================================================
function BeadsResultCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-sky-500/30 bg-gradient-to-br from-sky-500/10 to-blue-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-sky-500/50"
    >
      <div className="flex items-center gap-3 mb-4">
        <LayoutDashboard className="h-5 w-5 text-sky-400" />
        <h4 className="font-bold text-white">Final Beads Structure</h4>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">14</div>
          <div className="text-xs text-white/60">Epics</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">62</div>
          <div className="text-xs text-white/60">Tasks</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">76</div>
          <div className="text-xs text-white/60">Total Beads</div>
        </div>
      </div>

      <p className="mt-4 text-sm text-white/60">
        Smaller than cass-memory&apos;s 693 beads, but still comprehensive
        enough to capture the full implementation.
      </p>
    </motion.div>
  );
}

// =============================================================================
// RISK TIER CARD
// =============================================================================
function RiskTierCard() {
  const tiers = [
    {
      name: "CRITICAL",
      approvals: "2+",
      examples: "System destruction, database drops",
      color: "from-red-500/20 to-rose-500/20",
      border: "border-red-500/30",
    },
    {
      name: "DANGEROUS",
      approvals: "1",
      examples: "rm -rf, git push --force",
      color: "from-orange-500/20 to-amber-500/20",
      border: "border-orange-500/30",
    },
    {
      name: "CAUTION",
      approvals: "Auto (30s)",
      examples: "Single file delete, branch remove",
      color: "from-yellow-500/20 to-amber-500/20",
      border: "border-yellow-500/30",
    },
    {
      name: "SAFE",
      approvals: "Skip",
      examples: "Temp file cleanup, cache clear",
      color: "from-emerald-500/20 to-teal-500/20",
      border: "border-emerald-500/30",
    },
  ];

  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {tiers.map((tier, i) => (
        <motion.div
          key={tier.name}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: i * 0.1 }}
          whileHover={{ y: -2, scale: 1.02 }}
          className={`group rounded-xl border ${tier.border} bg-gradient-to-br ${tier.color} p-4 backdrop-blur-xl transition-all duration-300 hover:border-opacity-80`}
        >
          <div className="flex items-center justify-between mb-2">
            <span className="font-bold text-white text-sm">{tier.name}</span>
            <span className="text-xs px-2 py-1 rounded bg-black/30 text-white/70 group-hover:bg-black/40 transition-colors">
              {tier.approvals}{/^\d/.test(tier.approvals) ? (tier.approvals === "1" ? " approval" : " approvals") : ""}
            </span>
          </div>
          <p className="text-xs text-white/60 group-hover:text-white/80 transition-colors">{tier.examples}</p>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// RESULTS CARD
// =============================================================================
function ResultsCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-emerald-500/50"
    >
      <div className="flex items-center gap-3 mb-4">
        <CheckCircle2 className="h-5 w-5 text-emerald-400" />
        <h4 className="font-bold text-white">Implementation Results</h4>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-emerald-400">268</div>
          <div className="text-xs text-white/60">Total Commits</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-emerald-400">Go 1.21+</div>
          <div className="text-xs text-white/60">Built In</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-emerald-400">~70%</div>
          <div className="text-xs text-white/60">Day 1 Complete</div>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// COMPARISON CARD
// =============================================================================
function ComparisonCard({
  title,
  items,
  gradient,
}: {
  title: string;
  items: string[];
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group rounded-xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-5 backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]`}
    >
      <h4 className="font-bold text-white mb-3 group-hover:text-primary transition-colors">{title}</h4>
      <ul className="space-y-2">
        {items.map((item, i) => (
          <li key={i} className="text-sm text-white/70 flex items-center gap-2 group-hover:text-white/80 transition-colors">
            <div className="h-1.5 w-1.5 rounded-full bg-white/40 shrink-0 group-hover:bg-primary/60 transition-colors" />
            {item}
          </li>
        ))}
      </ul>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE BUILD TIMELINE - Two-Person Rule Launch Console
// =============================================================================

type RiskLevel = "CRITICAL" | "DANGEROUS" | "CAUTION";
type ScenarioPhase = "idle" | "initiating" | "reviewing" | "countdown" | "executing" | "complete" | "denied" | "aborted";

interface LaunchScenario {
  id: string;
  title: string;
  command: string;
  risk: RiskLevel;
  icon: React.ComponentType<{ className?: string }>;
  agentA: string;
  agentB: string;
  reasoning: string;
  reviewComment: string;
  outcome: "approved" | "denied";
  auditEntries: string[];
  terminalOutput: string[];
  denyReason?: string;
}

const RISK_CONFIG: Record<RiskLevel, { color: string; bgColor: string; borderColor: string; glowColor: string; gaugePercent: number }> = {
  CRITICAL: {
    color: "text-red-500",
    bgColor: "bg-red-500/10",
    borderColor: "border-red-500/30",
    glowColor: "shadow-red-500/30",
    gaugePercent: 95,
  },
  DANGEROUS: {
    color: "text-orange-500",
    bgColor: "bg-orange-500/10",
    borderColor: "border-orange-500/30",
    glowColor: "shadow-orange-500/30",
    gaugePercent: 70,
  },
  CAUTION: {
    color: "text-yellow-500",
    bgColor: "bg-yellow-500/10",
    borderColor: "border-yellow-500/30",
    glowColor: "shadow-yellow-500/30",
    gaugePercent: 40,
  },
};

const LAUNCH_SCENARIOS: LaunchScenario[] = [
  {
    id: "db-migration",
    title: "Database Migration",
    command: "psql -c 'ALTER TABLE users DROP COLUMN legacy_auth;'",
    risk: "CRITICAL",
    icon: Database,
    agentA: "claude-cc-1",
    agentB: "claude-cc-2",
    reasoning: "Legacy auth column is no longer referenced after migration to OAuth2. All 847 references have been updated. Backup verified at snapshot-2025-12-13-1845.",
    reviewComment: "Confirmed: grep shows 0 references to legacy_auth. Backup snapshot verified. Approve.",
    outcome: "approved",
    auditEntries: [
      "[18:45:03] Agent claude-cc-1 initiated SLB request",
      "[18:45:03] Command hash: sha256:a3f8c2...e91d",
      "[18:45:04] Risk classification: CRITICAL (schema drop)",
      "[18:45:04] Notified reviewer claude-cc-2 via agent-mail",
      "[18:45:07] Reviewer claude-cc-2 opened review",
      "[18:45:12] Pre-flight: dry-run passed",
      "[18:45:15] Reviewer APPROVED with comment",
      "[18:45:15] Countdown initiated: 5s",
      "[18:45:20] Command executed successfully",
      "[18:45:21] Rollback point saved: rb-20251213-184520",
    ],
    terminalOutput: [
      "$ slb request --cmd 'psql -c \"ALTER TABLE users DROP COLUMN legacy_auth;\"'",
      "SLB: Risk level CRITICAL detected",
      "SLB: Command hash: sha256:a3f8c2...e91d",
      "SLB: Awaiting peer review from claude-cc-2...",
      "SLB: Review APPROVED",
      "SLB: Executing in 5...4...3...2...1...",
      "ALTER TABLE",
      "SLB: Command completed. Rollback: rb-20251213-184520",
    ],
  },
  {
    id: "prod-deploy",
    title: "Production Deploy",
    command: "kubectl apply -f deploy/production.yaml --namespace=prod",
    risk: "CRITICAL",
    icon: Cloud,
    agentA: "claude-cc-2",
    agentB: "codex-1",
    reasoning: "Deploying v2.3.1 with the new rate limiter. All 47 tests pass. Staging verified for 2 hours with no errors. Canary showed 0% error rate.",
    reviewComment: "Test suite green, staging clean, canary clean. Image sha matches build. Approve deploy.",
    outcome: "approved",
    auditEntries: [
      "[20:12:01] Agent claude-cc-2 initiated SLB request",
      "[20:12:01] Command hash: sha256:7b2e1a...f43c",
      "[20:12:02] Risk classification: CRITICAL (prod namespace)",
      "[20:12:02] Pre-flight: image exists, namespace valid",
      "[20:12:03] Notified reviewer codex-1 via agent-mail",
      "[20:12:08] Reviewer codex-1 opened review",
      "[20:12:14] Reviewer APPROVED with comment",
      "[20:12:14] Countdown initiated: 5s",
      "[20:12:19] kubectl apply completed (3 resources updated)",
      "[20:12:20] Rollback manifest saved: rb-20251213-201219",
    ],
    terminalOutput: [
      "$ slb request --cmd 'kubectl apply -f deploy/production.yaml --namespace=prod'",
      "SLB: Risk level CRITICAL detected (production namespace)",
      "SLB: Pre-flight: image sha256:9c4f... verified",
      "SLB: Awaiting peer review from codex-1...",
      "SLB: Review APPROVED",
      "SLB: Executing in 5...4...3...2...1...",
      "deployment.apps/api-server configured",
      "service/api-service unchanged",
      "SLB: Deploy complete. Rollback: rb-20251213-201219",
    ],
  },
  {
    id: "force-push",
    title: "Force Push to Main",
    command: "git push --force origin main",
    risk: "DANGEROUS",
    icon: GitBranch,
    agentA: "codex-2",
    agentB: "claude-cc-3",
    reasoning: "Need to force push to fix corrupted merge commit. Interactive rebase cleaned history. 3 commits affected, all authored by us in last hour.",
    reviewComment: "DENIED: Force push to main is blocked by policy. Use a revert commit instead. This would destroy CI history.",
    outcome: "denied",
    denyReason: "Force push to protected branch 'main' violates repository policy. Reviewer recommends git revert instead.",
    auditEntries: [
      "[21:30:45] Agent codex-2 initiated SLB request",
      "[21:30:45] Command hash: sha256:e4d2f8...b17a",
      "[21:30:46] Risk classification: DANGEROUS (force push)",
      "[21:30:46] WARNING: Target branch 'main' is protected",
      "[21:30:47] Notified reviewer claude-cc-3 via agent-mail",
      "[21:30:52] Reviewer claude-cc-3 opened review",
      "[21:30:58] Reviewer DENIED with reason",
      "[21:30:58] Command BLOCKED - no execution",
      "[21:30:58] Incident logged: INC-20251213-001",
    ],
    terminalOutput: [
      "$ slb request --cmd 'git push --force origin main'",
      "SLB: Risk level DANGEROUS detected",
      "SLB: WARNING: Protected branch 'main' targeted",
      "SLB: Awaiting peer review from claude-cc-3...",
      "SLB: Review DENIED",
      "SLB: BLOCKED - Command will not execute",
      "SLB: Reason: Force push to protected branch violates policy",
      "SLB: Suggestion: Use 'git revert <sha>' instead",
    ],
  },
  {
    id: "infra-teardown",
    title: "Infrastructure Teardown",
    command: "terraform destroy -auto-approve -target=module.staging",
    risk: "CRITICAL",
    icon: Trash2,
    agentA: "claude-cc-1",
    agentB: "claude-cc-3",
    reasoning: "Staging environment rebuild required after config drift. All staging data has been archived. No active staging users. Rebuild plan in bead SLB-47.",
    reviewComment: "Verified: no active sessions in staging. Archive confirmed. Rebuild bead exists. Approve teardown.",
    outcome: "approved",
    auditEntries: [
      "[22:05:11] Agent claude-cc-1 initiated SLB request",
      "[22:05:11] Command hash: sha256:1c9f3e...d82b",
      "[22:05:12] Risk classification: CRITICAL (terraform destroy)",
      "[22:05:12] Pre-flight: 7 resources will be destroyed",
      "[22:05:13] Notified reviewer claude-cc-3 via agent-mail",
      "[22:05:18] Reviewer claude-cc-3 opened review",
      "[22:05:24] Pre-flight: no active connections confirmed",
      "[22:05:28] Reviewer APPROVED with comment",
      "[22:05:28] Countdown initiated: 5s",
      "[22:05:33] terraform destroy completed (7 resources)",
      "[22:05:34] State backup: tf-state-20251213-220533",
    ],
    terminalOutput: [
      "$ slb request --cmd 'terraform destroy -auto-approve -target=module.staging'",
      "SLB: Risk level CRITICAL detected",
      "SLB: Pre-flight: 7 resources targeted for destruction",
      "SLB: Awaiting peer review from claude-cc-3...",
      "SLB: Review APPROVED",
      "SLB: Executing in 5...4...3...2...1...",
      "module.staging.aws_instance.web: Destroying...",
      "module.staging.aws_db_instance.main: Destroying...",
      "Destroy complete! Resources: 7 destroyed.",
      "SLB: State backup saved: tf-state-20251213-220533",
    ],
  },
  {
    id: "secret-rotation",
    title: "Secret Rotation",
    command: "vault write -f sys/rotate && vault write auth/token/tidy",
    risk: "DANGEROUS",
    icon: FileKey,
    agentA: "claude-cc-3",
    agentB: "claude-cc-1",
    reasoning: "Scheduled quarterly key rotation. All services use dynamic secrets. Rotation window is 15 minutes. Monitoring alerts suppressed for rotation period.",
    reviewComment: "Rotation schedule confirmed. Dynamic secret renewal verified. Approve rotation.",
    outcome: "approved",
    auditEntries: [
      "[23:00:01] Agent claude-cc-3 initiated SLB request",
      "[23:00:01] Command hash: sha256:5a8b7c...f29e",
      "[23:00:02] Risk classification: DANGEROUS (secret rotation)",
      "[23:00:02] Pre-flight: vault status healthy",
      "[23:00:03] Notified reviewer claude-cc-1 via agent-mail",
      "[23:00:07] Reviewer claude-cc-1 opened review",
      "[23:00:11] Reviewer APPROVED with comment",
      "[23:00:11] Countdown initiated: 5s",
      "[23:00:16] vault rotate completed successfully",
      "[23:00:17] vault tidy completed (12 tokens revoked)",
    ],
    terminalOutput: [
      "$ slb request --cmd 'vault write -f sys/rotate && vault write auth/token/tidy'",
      "SLB: Risk level DANGEROUS detected",
      "SLB: Pre-flight: vault status: sealed=false",
      "SLB: Awaiting peer review from claude-cc-1...",
      "SLB: Review APPROVED",
      "SLB: Executing in 5...4...3...2...1...",
      "Success! Data written to: sys/rotate",
      "Success! Tidied 12 expired tokens",
      "SLB: Rotation complete. Next rotation: 2026-03-13",
    ],
  },
  {
    id: "emergency-rollback",
    title: "Emergency Rollback",
    command: "kubectl rollout undo deployment/api-server --namespace=prod",
    risk: "CAUTION",
    icon: RotateCcw,
    agentA: "codex-1",
    agentB: "claude-cc-2",
    reasoning: "Error rate spiked to 12% after v2.3.1 deploy. P95 latency at 4.2s (normal: 200ms). Rolling back to previous stable revision.",
    reviewComment: "Error rate confirmed at 12%. Previous revision was stable for 48h. Approve immediate rollback.",
    outcome: "approved",
    auditEntries: [
      "[20:18:44] Agent codex-1 initiated SLB request",
      "[20:18:44] Command hash: sha256:d3f1a9...c45b",
      "[20:18:45] Risk classification: CAUTION (rollout undo)",
      "[20:18:45] FAST-TRACK: Emergency rollback detected",
      "[20:18:46] Notified reviewer claude-cc-2 via agent-mail",
      "[20:18:48] Reviewer claude-cc-2 opened review",
      "[20:18:50] Reviewer APPROVED (fast-tracked)",
      "[20:18:50] Countdown: 3s (reduced for emergency)",
      "[20:18:53] Rollback executed successfully",
      "[20:18:55] Error rate dropping: 12% -> 3% -> 0.1%",
    ],
    terminalOutput: [
      "$ slb request --cmd 'kubectl rollout undo deployment/api-server --namespace=prod' --emergency",
      "SLB: Risk level CAUTION (emergency rollback)",
      "SLB: FAST-TRACK enabled for emergency",
      "SLB: Awaiting peer review from claude-cc-2...",
      "SLB: Review APPROVED (fast-tracked)",
      "SLB: Executing in 3...2...1...",
      "deployment.apps/api-server rolled back",
      "SLB: Rollback complete. Monitoring error rate...",
      "SLB: Error rate: 12% -> 0.1% (stable)",
    ],
  },
];

function InteractiveBuildTimeline() {
  const [selectedScenario, setSelectedScenario] = useState(0);
  const [phase, setPhase] = useState<ScenarioPhase>("idle");
  const [countdownValue, setCountdownValue] = useState(5);
  const [auditIndex, setAuditIndex] = useState(0);
  const [terminalIndex, setTerminalIndex] = useState(0);
  const [keyARotation, setKeyARotation] = useState(0);
  const [keyBRotation, setKeyBRotation] = useState(0);
  const phaseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const auditTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const simTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const scenario = LAUNCH_SCENARIOS[selectedScenario];

  // Cleanup timers
  useEffect(() => {
    const pRef = phaseTimerRef;
    const aRef = auditTimerRef;
    const sRef = simTimersRef;
    return () => {
      if (pRef.current) clearTimeout(pRef.current);
      if (aRef.current) clearTimeout(aRef.current);
      for (const t of sRef.current) clearTimeout(t);
    };
  }, []);

  // Audit trail auto-advance
  useEffect(() => {
    if (phase === "idle" || phase === "initiating") return;
    if (auditIndex < scenario.auditEntries.length) {
      auditTimerRef.current = setTimeout(() => {
        setAuditIndex((prev) => prev + 1);
        setTerminalIndex((prev) =>
          prev < scenario.terminalOutput.length ? prev + 1 : prev
        );
      }, 400);
    }
    return () => {
      if (auditTimerRef.current) clearTimeout(auditTimerRef.current);
    };
  }, [phase, auditIndex, scenario.auditEntries.length, scenario.terminalOutput.length]);

  // Countdown timer
  useEffect(() => {
    if (phase !== "countdown") return;
    if (countdownValue <= 0) {
      setTimeout(() => {
        setPhase("executing");
        phaseTimerRef.current = setTimeout(() => {
          setPhase("complete");
        }, 1500);
      }, 0);
      return;
    }
    const timer = setTimeout(() => {
      setCountdownValue((prev) => prev - 1);
    }, 1000);
    return () => clearTimeout(timer);
  }, [phase, countdownValue]);

  const resetSimulation = useCallback(() => {
    if (phaseTimerRef.current) clearTimeout(phaseTimerRef.current);
    if (auditTimerRef.current) clearTimeout(auditTimerRef.current);
    // simTimersRef cleared in startSimulation before use
    setPhase("idle");
    setCountdownValue(5);
    setAuditIndex(0);
    setTerminalIndex(0);
    setKeyARotation(0);
    setKeyBRotation(0);
  }, []);

  const startSimulation = useCallback(() => {
    resetSimulation();
    // Clear previous simulation timers
    while (simTimersRef.current.length > 0) {
      const t = simTimersRef.current.pop();
      if (t) clearTimeout(t);
    }

    // Use setTimeout to avoid synchronous setState in sequence
    const t0 = setTimeout(() => {
      setPhase("initiating");
      setKeyARotation(90);
    }, 50);
    simTimersRef.current.push(t0);

    const t1 = setTimeout(() => {
      setPhase("reviewing");
    }, 2000);
    simTimersRef.current.push(t1);
    phaseTimerRef.current = t1;

    const t2 = setTimeout(() => {
      if (scenario.outcome === "denied") {
        const t3 = setTimeout(() => {
          setPhase("denied");
          const t4 = setTimeout(() => {
            setPhase("aborted");
          }, 1500);
          simTimersRef.current.push(t4);
        }, 4000);
        simTimersRef.current.push(t3);
        phaseTimerRef.current = t3;
      } else {
        const t3 = setTimeout(() => {
          setKeyBRotation(90);
          setPhase("countdown");
          setCountdownValue(scenario.id === "emergency-rollback" ? 3 : 5);
        }, 4000);
        simTimersRef.current.push(t3);
        phaseTimerRef.current = t3;
      }
    }, 100);
    simTimersRef.current.push(t2);
  }, [resetSimulation, scenario]);

  const handleScenarioChange = useCallback(
    (index: number) => {
      resetSimulation();
      setSelectedScenario(index);
    },
    [resetSimulation]
  );

  const phaseLabel = getPhaseLabel(phase);
  const riskConfig = RISK_CONFIG[scenario.risk];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* Console Header */}
      <div className="flex items-center gap-3 px-5 py-3.5 border-b border-white/[0.06] bg-white/[0.01]">
        <div className="flex items-center gap-1.5">
          <div className="h-3 w-3 rounded-full bg-red-500/80" />
          <div className="h-3 w-3 rounded-full bg-yellow-500/80" />
          <div className="h-3 w-3 rounded-full bg-green-500/80" />
        </div>
        <div className="flex items-center gap-2 ml-2">
          <Shield className="h-4 w-4 text-primary" />
          <span className="text-sm font-mono font-bold text-white/90">
            SLB Launch Console
          </span>
        </div>
        <span className="ml-auto text-[10px] font-mono text-white/30">
          slb v1.0.0 | two-person-rule
        </span>
      </div>

      {/* Scenario Selector */}
      <div className="px-5 py-3 border-b border-white/[0.06] overflow-x-auto">
        <div className="flex gap-2 min-w-max">
          {LAUNCH_SCENARIOS.map((s, i) => {
            const ScenarioIcon = s.icon;
            const rc = RISK_CONFIG[s.risk];
            const isSelected = i === selectedScenario;
            return (
              <button
                key={s.id}
                onClick={() => handleScenarioChange(i)}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-mono transition-all duration-200 border ${
                  isSelected
                    ? `${rc.borderColor} ${rc.bgColor} ${rc.color}`
                    : "border-white/[0.06] bg-white/[0.01] text-white/50 hover:text-white/70 hover:border-white/[0.12]"
                }`}
              >
                <ScenarioIcon className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">{s.title}</span>
                <span className="sm:hidden">{s.title.split(" ")[0]}</span>
              </button>
            );
          })}
        </div>
      </div>

      <div className="p-5 space-y-5">
        {/* Top row: Risk Gauge + Key-Turn SVG + Status */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* Risk Assessment Gauge */}
          <div className={`rounded-xl border ${riskConfig.borderColor} ${riskConfig.bgColor} p-4`}>
            <div className="flex items-center gap-2 mb-3">
              <Gauge className="h-4 w-4 text-white/60" />
              <span className="text-xs font-mono text-white/60 uppercase tracking-wider">
                Risk Assessment
              </span>
            </div>
            <RiskGauge percent={riskConfig.gaugePercent} risk={scenario.risk} />
            <div className="mt-2 text-center">
              <span className={`text-sm font-bold font-mono ${riskConfig.color}`}>
                {scenario.risk}
              </span>
            </div>
          </div>

          {/* Key-Turn SVG Diagram */}
          <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 flex flex-col items-center justify-center">
            <span className="text-xs font-mono text-white/40 uppercase tracking-wider mb-3">
              Dual-Key Authorization
            </span>
            <KeyTurnSVG
              keyARotation={keyARotation}
              keyBRotation={keyBRotation}
              phase={phase}
              risk={scenario.risk}
            />
          </div>

          {/* Launch Status */}
          <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
            <div className="flex items-center gap-2 mb-3">
              <Shield className="h-4 w-4 text-white/60" />
              <span className="text-xs font-mono text-white/60 uppercase tracking-wider">
                Launch Status
              </span>
            </div>
            <div className="space-y-2">
              <StatusRow label="Phase" value={phaseLabel} phase={phase} />
              <StatusRow
                label="Initiator"
                value={scenario.agentA}
                phase={phase}
              />
              <StatusRow
                label="Reviewer"
                value={scenario.agentB}
                phase={phase}
              />
              <StatusRow
                label="Outcome"
                value={
                  phase === "complete"
                    ? "EXECUTED"
                    : phase === "aborted"
                      ? "BLOCKED"
                      : phase === "denied"
                        ? "DENIED"
                        : "PENDING"
                }
                phase={phase}
              />
            </div>
          </div>
        </div>

        {/* Dual Console View */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {/* Agent A Console */}
          <AgentConsole
            agentName={scenario.agentA}
            role="INITIATOR"
            phase={phase}
            command={scenario.command}
            reasoning={scenario.reasoning}
            isActive={phase !== "idle"}
            accentColor="text-sky-400"
            borderColor="border-sky-500/20"
          />

          {/* Agent B Console */}
          <AgentConsole
            agentName={scenario.agentB}
            role="REVIEWER"
            phase={phase}
            command={scenario.command}
            reasoning={
              phase === "denied" || phase === "aborted"
                ? scenario.denyReason || "Request denied."
                : scenario.reviewComment
            }
            isActive={
              phase === "reviewing" ||
              phase === "countdown" ||
              phase === "executing" ||
              phase === "complete" ||
              phase === "denied" ||
              phase === "aborted"
            }
            accentColor={
              phase === "denied" || phase === "aborted"
                ? "text-red-400"
                : "text-emerald-400"
            }
            borderColor={
              phase === "denied" || phase === "aborted"
                ? "border-red-500/20"
                : "border-emerald-500/20"
            }
          />
        </div>

        {/* Countdown / Abort Animation */}
        <AnimatePresence mode="wait">
          {phase === "countdown" && (
            <CountdownDisplay value={countdownValue} risk={scenario.risk} />
          )}
          {(phase === "denied" || phase === "aborted") && (
            <AbortDisplay reason={scenario.denyReason} />
          )}
          {phase === "executing" && <ExecutingDisplay />}
          {phase === "complete" && (
            <CompleteDisplay command={scenario.command} />
          )}
        </AnimatePresence>

        {/* Bottom panels: Audit Trail + Terminal */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Audit Trail */}
          <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 max-h-56 overflow-y-auto">
            <div className="flex items-center gap-2 mb-3">
              <FileText className="h-4 w-4 text-white/50" />
              <span className="text-xs font-mono text-white/50 uppercase tracking-wider">
                Audit Trail
              </span>
            </div>
            <div className="space-y-1 font-mono text-[11px]">
              {phase === "idle" ? (
                <span className="text-white/30">
                  Waiting for launch sequence...
                </span>
              ) : (
                scenario.auditEntries
                  .slice(0, auditIndex)
                  .map((entry, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0, x: -8 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ type: "spring", stiffness: 300, damping: 25 }}
                      className={`leading-relaxed ${
                        entry.includes("DENIED") || entry.includes("BLOCKED")
                          ? "text-red-400/90"
                          : entry.includes("APPROVED")
                            ? "text-emerald-400/90"
                            : entry.includes("WARNING")
                              ? "text-yellow-400/90"
                              : "text-white/50"
                      }`}
                    >
                      {entry}
                    </motion.div>
                  ))
              )}
            </div>
          </div>

          {/* Mini Terminal */}
          <div className="rounded-xl border border-white/[0.08] bg-black/40 p-4 max-h-56 overflow-y-auto">
            <div className="flex items-center gap-2 mb-3">
              <Terminal className="h-4 w-4 text-emerald-400/60" />
              <span className="text-xs font-mono text-white/50 uppercase tracking-wider">
                Terminal Output
              </span>
            </div>
            <div className="space-y-0.5 font-mono text-[11px]">
              {phase === "idle" ? (
                <span className="text-emerald-400/40">
                  $ <span className="animate-pulse">_</span>
                </span>
              ) : (
                scenario.terminalOutput
                  .slice(0, terminalIndex)
                  .map((line, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ duration: 0.15 }}
                      className={`leading-relaxed ${
                        line.startsWith("$")
                          ? "text-emerald-400/80"
                          : line.includes("BLOCKED") || line.includes("DENIED")
                            ? "text-red-400/80"
                            : line.includes("SLB:")
                              ? "text-sky-400/70"
                              : "text-white/50"
                      }`}
                    >
                      {line}
                    </motion.div>
                  ))
              )}
            </div>
          </div>
        </div>

        {/* Control Bar */}
        <div className="flex items-center justify-between pt-2 border-t border-white/[0.06]">
          <div className="flex items-center gap-2 text-xs text-white/40 font-mono">
            <ChevronRight className="h-3 w-3" />
            <span>
              {scenario.title} | {scenario.risk} | {scenario.outcome === "approved" ? "Will approve" : "Will deny"}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={resetSimulation}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] text-xs font-mono text-white/50 hover:text-white/80 hover:border-white/[0.15] transition-all duration-200"
            >
              <RotateCcw className="h-3 w-3" />
              Reset
            </button>
            <button
              onClick={startSimulation}
              disabled={phase !== "idle"}
              className={`flex items-center gap-1.5 px-4 py-1.5 rounded-lg border text-xs font-mono font-bold transition-all duration-200 ${
                phase !== "idle"
                  ? "border-white/[0.06] bg-white/[0.01] text-white/30 cursor-not-allowed"
                  : `${riskConfig.borderColor} ${riskConfig.bgColor} ${riskConfig.color} hover:brightness-125`
              }`}
            >
              <Key className="h-3 w-3" />
              Initiate Launch Sequence
            </button>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// RISK GAUGE - SVG arc gauge showing danger level
// =============================================================================
function RiskGauge({ percent, risk }: { percent: number; risk: RiskLevel }) {
  const colorMap: Record<RiskLevel, string> = {
    CRITICAL: "#ef4444",
    DANGEROUS: "#f97316",
    CAUTION: "#eab308",
  };
  const strokeColor = colorMap[risk];

  return (
    <div className="flex justify-center">
      <svg width="100" height="60" viewBox="0 0 100 60">
        {/* Background arc */}
        <path
          d="M 10 55 A 40 40 0 0 1 90 55"
          fill="none"
          stroke="rgba(255,255,255,0.08)"
          strokeWidth="6"
          strokeLinecap="round"
        />
        {/* Filled arc */}
        <motion.path
          d="M 10 55 A 40 40 0 0 1 90 55"
          fill="none"
          stroke={strokeColor}
          strokeWidth="6"
          strokeLinecap="round"
          initial={{ pathLength: 0 }}
          animate={{ pathLength: percent / 100 }}
          transition={{ type: "spring", stiffness: 100, damping: 20, delay: 0.3 }}
          style={{ filter: `drop-shadow(0 0 6px ${strokeColor}40)` }}
        />
        {/* Percentage text */}
        <text
          x="50"
          y="50"
          textAnchor="middle"
          fill={strokeColor}
          fontSize="16"
          fontFamily="monospace"
          fontWeight="bold"
        >
          {percent}%
        </text>
      </svg>
    </div>
  );
}

// =============================================================================
// KEY-TURN SVG - Animated dual-key launch sequence
// =============================================================================
function KeyTurnSVG({
  keyARotation,
  keyBRotation,
  phase,
  risk,
}: {
  keyARotation: number;
  keyBRotation: number;
  phase: ScenarioPhase;
  risk: RiskLevel;
}) {
  const colorMap: Record<RiskLevel, string> = {
    CRITICAL: "#ef4444",
    DANGEROUS: "#f97316",
    CAUTION: "#eab308",
  };
  const activeColor = colorMap[risk];
  const isActive = phase !== "idle";
  const bothTurned = keyARotation > 0 && keyBRotation > 0;

  return (
    <svg width="160" height="80" viewBox="0 0 160 80">
      {/* Connection line */}
      <motion.line
        x1="40"
        y1="40"
        x2="120"
        y2="40"
        stroke={bothTurned ? activeColor : "rgba(255,255,255,0.1)"}
        strokeWidth="2"
        strokeDasharray="4 4"
        animate={{
          opacity: isActive ? 1 : 0.3,
        }}
        transition={{ duration: 0.3 }}
      />

      {/* Key A */}
      <g>
        {/* Key slot */}
        <circle
          cx="40"
          cy="40"
          r="18"
          fill="none"
          stroke={keyARotation > 0 ? activeColor : "rgba(255,255,255,0.15)"}
          strokeWidth="2"
        />
        {/* Key shape */}
        <motion.g
          animate={{ rotate: keyARotation }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          style={{ originX: "40px", originY: "40px" }}
        >
          <rect
            x="36"
            y="26"
            width="8"
            height="28"
            rx="2"
            fill={keyARotation > 0 ? activeColor : "rgba(255,255,255,0.3)"}
          />
          <circle
            cx="40"
            cy="30"
            r="4"
            fill="none"
            stroke={keyARotation > 0 ? activeColor : "rgba(255,255,255,0.3)"}
            strokeWidth="1.5"
          />
        </motion.g>
        {/* Label */}
        <text
          x="40"
          y="72"
          textAnchor="middle"
          fill="rgba(255,255,255,0.4)"
          fontSize="8"
          fontFamily="monospace"
        >
          KEY A
        </text>
      </g>

      {/* Key B */}
      <g>
        <circle
          cx="120"
          cy="40"
          r="18"
          fill="none"
          stroke={keyBRotation > 0 ? activeColor : "rgba(255,255,255,0.15)"}
          strokeWidth="2"
        />
        <motion.g
          animate={{ rotate: keyBRotation }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          style={{ originX: "120px", originY: "40px" }}
        >
          <rect
            x="116"
            y="26"
            width="8"
            height="28"
            rx="2"
            fill={keyBRotation > 0 ? activeColor : "rgba(255,255,255,0.3)"}
          />
          <circle
            cx="120"
            cy="30"
            r="4"
            fill="none"
            stroke={keyBRotation > 0 ? activeColor : "rgba(255,255,255,0.3)"}
            strokeWidth="1.5"
          />
        </motion.g>
        <text
          x="120"
          y="72"
          textAnchor="middle"
          fill="rgba(255,255,255,0.4)"
          fontSize="8"
          fontFamily="monospace"
        >
          KEY B
        </text>
      </g>

      {/* Center status indicator */}
      <motion.circle
        cx="80"
        cy="40"
        r="6"
        fill={
          bothTurned
            ? activeColor
            : isActive
              ? "rgba(255,255,255,0.2)"
              : "rgba(255,255,255,0.08)"
        }
        animate={{
          scale: bothTurned ? [1, 1.3, 1] : 1,
        }}
        transition={{ duration: 0.6, repeat: bothTurned ? Infinity : 0, repeatDelay: 0.8 }}
        style={{ filter: bothTurned ? `drop-shadow(0 0 8px ${activeColor})` : "none" }}
      />
    </svg>
  );
}

// =============================================================================
// AGENT CONSOLE - Shows agent's perspective
// =============================================================================
function AgentConsole({
  agentName,
  role,
  phase,
  command,
  reasoning,
  isActive,
  accentColor,
  borderColor,
}: {
  agentName: string;
  role: "INITIATOR" | "REVIEWER";
  phase: ScenarioPhase;
  command: string;
  reasoning: string;
  isActive: boolean;
  accentColor: string;
  borderColor: string;
}) {
  const RoleIcon = role === "INITIATOR" ? Unlock : Lock;

  return (
    <motion.div
      animate={{
        borderColor: isActive ? undefined : "rgba(255,255,255,0.08)",
      }}
      className={`rounded-xl border ${isActive ? borderColor : "border-white/[0.08]"} bg-black/20 p-4 transition-colors duration-500`}
    >
      <div className="flex items-center gap-2 mb-3">
        <RoleIcon className={`h-3.5 w-3.5 ${isActive ? accentColor : "text-white/30"}`} />
        <span className={`text-xs font-mono font-bold ${isActive ? accentColor : "text-white/30"}`}>
          {agentName}
        </span>
        <span className="text-[10px] font-mono text-white/20 uppercase ml-auto">
          {role}
        </span>
      </div>

      <AnimatePresence mode="wait">
        {!isActive ? (
          <motion.div
            key="waiting"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-xs font-mono text-white/20 py-4 text-center"
          >
            {role === "INITIATOR" ? "Ready to initiate..." : "Awaiting review request..."}
          </motion.div>
        ) : (
          <motion.div
            key="active"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="space-y-2"
          >
            {role === "INITIATOR" && (
              <div className="rounded-lg bg-black/30 px-3 py-2">
                <span className="text-[10px] font-mono text-white/30 uppercase block mb-1">
                  Command
                </span>
                <span className="text-[11px] font-mono text-emerald-400/80 break-all">
                  {command}
                </span>
              </div>
            )}
            <div className="rounded-lg bg-black/20 px-3 py-2">
              <span className="text-[10px] font-mono text-white/30 uppercase block mb-1">
                {role === "INITIATOR" ? "Reasoning" : phase === "denied" || phase === "aborted" ? "Denial Reason" : "Review Comment"}
              </span>
              <span className="text-[11px] text-white/50 leading-relaxed block">
                {reasoning}
              </span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

// =============================================================================
// COUNTDOWN DISPLAY
// =============================================================================
function CountdownDisplay({
  value,
  risk,
}: {
  value: number;
  risk: RiskLevel;
}) {
  const colorMap: Record<RiskLevel, string> = {
    CRITICAL: "text-red-400",
    DANGEROUS: "text-orange-400",
    CAUTION: "text-yellow-400",
  };
  const bgMap: Record<RiskLevel, string> = {
    CRITICAL: "from-red-500/10 to-red-900/10",
    DANGEROUS: "from-orange-500/10 to-orange-900/10",
    CAUTION: "from-yellow-500/10 to-yellow-900/10",
  };

  return (
    <motion.div
      key="countdown"
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 1.1 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className={`rounded-xl border border-white/[0.08] bg-gradient-to-r ${bgMap[risk]} p-6 text-center`}
    >
      <div className="flex items-center justify-center gap-3 mb-2">
        <AlertTriangle className={`h-5 w-5 ${colorMap[risk]}`} />
        <span className="text-sm font-mono font-bold text-white/70 uppercase tracking-wider">
          Executing in
        </span>
      </div>
      <AnimatePresence mode="wait">
        <motion.div
          key={value}
          initial={{ opacity: 0, scale: 2, y: -20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.5, y: 20 }}
          transition={{ type: "spring", stiffness: 300, damping: 20 }}
          className={`text-5xl font-mono font-bold ${colorMap[risk]}`}
          style={{
            textShadow:
              risk === "CRITICAL"
                ? "0 0 30px rgba(239,68,68,0.5)"
                : risk === "DANGEROUS"
                  ? "0 0 30px rgba(249,115,22,0.5)"
                  : "0 0 30px rgba(234,179,8,0.5)",
          }}
        >
          {value}
        </motion.div>
      </AnimatePresence>
    </motion.div>
  );
}

// =============================================================================
// ABORT DISPLAY
// =============================================================================
function AbortDisplay({ reason }: { reason?: string }) {
  return (
    <motion.div
      key="abort"
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.95 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="rounded-xl border border-red-500/30 bg-gradient-to-r from-red-500/10 to-red-900/10 p-5 text-center"
    >
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 300, damping: 20, delay: 0.1 }}
        className="flex items-center justify-center gap-3 mb-3"
      >
        <XCircle className="h-8 w-8 text-red-400" />
        <span className="text-lg font-mono font-bold text-red-400 uppercase tracking-wider">
          LAUNCH ABORTED
        </span>
      </motion.div>
      {reason && (
        <motion.p
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          className="text-sm text-red-400/70 font-mono max-w-md mx-auto"
        >
          {reason}
        </motion.p>
      )}
    </motion.div>
  );
}

// =============================================================================
// EXECUTING DISPLAY
// =============================================================================
function ExecutingDisplay() {
  return (
    <motion.div
      key="executing"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="rounded-xl border border-amber-500/20 bg-gradient-to-r from-amber-500/5 to-orange-500/5 p-5 text-center"
    >
      <div className="flex items-center justify-center gap-3">
        <motion.div
          animate={{ rotate: 360 }}
          transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
        >
          <Zap className="h-5 w-5 text-amber-400" />
        </motion.div>
        <span className="text-sm font-mono font-bold text-amber-400/80 uppercase tracking-wider">
          Executing command...
        </span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// COMPLETE DISPLAY
// =============================================================================
function CompleteDisplay({ command }: { command: string }) {
  return (
    <motion.div
      key="complete"
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.95 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="rounded-xl border border-emerald-500/30 bg-gradient-to-r from-emerald-500/10 to-teal-500/10 p-5 text-center"
    >
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 300, damping: 20, delay: 0.1 }}
        className="flex items-center justify-center gap-3 mb-2"
      >
        <CheckCircle2 className="h-6 w-6 text-emerald-400" />
        <span className="text-sm font-mono font-bold text-emerald-400 uppercase tracking-wider">
          Execution Complete
        </span>
      </motion.div>
      <p className="text-xs font-mono text-emerald-400/50 break-all max-w-lg mx-auto">
        {command}
      </p>
    </motion.div>
  );
}

// =============================================================================
// STATUS ROW - Key-value display in launch status panel
// =============================================================================
function StatusRow({
  label,
  value,
  phase,
}: {
  label: string;
  value: string;
  phase: ScenarioPhase;
}) {
  const valueColor =
    value === "EXECUTED"
      ? "text-emerald-400"
      : value === "BLOCKED" || value === "DENIED"
        ? "text-red-400"
        : phase === "idle"
          ? "text-white/30"
          : "text-white/60";

  return (
    <div className="flex items-center justify-between">
      <span className="text-[10px] font-mono text-white/30 uppercase">
        {label}
      </span>
      <span className={`text-[11px] font-mono font-bold ${valueColor}`}>
        {value}
      </span>
    </div>
  );
}

// =============================================================================
// PHASE LABEL HELPER
// =============================================================================
function getPhaseLabel(phase: ScenarioPhase): string {
  switch (phase) {
    case "idle":
      return "STANDBY";
    case "initiating":
      return "KEY A TURNED";
    case "reviewing":
      return "AWAITING KEY B";
    case "countdown":
      return "COUNTDOWN";
    case "executing":
      return "EXECUTING";
    case "complete":
      return "COMPLETE";
    case "denied":
      return "DENIED";
    case "aborted":
      return "ABORTED";
    default:
      return "UNKNOWN";
  }
}
