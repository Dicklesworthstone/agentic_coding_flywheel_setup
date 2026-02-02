"use client";

import { motion } from "@/components/motion";
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
Understand ALL of both! Use ultrathink.

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
              <ArrowRight className="h-3 w-3 text-white/30 group-hover:text-primary/50 transition-colors" />
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
