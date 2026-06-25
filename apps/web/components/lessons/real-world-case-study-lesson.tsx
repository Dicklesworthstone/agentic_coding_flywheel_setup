"use client";

import { type ReactNode, useState, useCallback, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Rocket,
  FileText,
  Bot,
  GitBranch,
  Users,
  Mail,
  LayoutDashboard,
  Brain,
  Layers,
  Play,
  TrendingUp,
  BookOpen,
  ExternalLink,
  CheckCircle,
  Code,
  Database,
  Terminal,
  Lightbulb,
  Shield,
  Trophy,
  Merge,
  Grid3X3,
  AlertTriangle,
  Pause,
  SkipForward,
  Clock,
  Zap,
  ArrowRight,
  ChevronDown,
  ChevronUp,
  MessageSquare,
  Hash,
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

export function RealWorldCaseStudyLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Learn the full flywheel workflow through a real project: 693 beads, 282
        commits on day one, 85% complete in hours.
      </GoalBanner>

      {/* Introduction */}
      <Section
        title="The Challenge: Building a Memory System"
        icon={<Brain className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          On December 7, 2025, a new project was conceived:{" "}
          <Highlight>cass-memory</Highlight> - a procedural memory system for
          coding agents. The goal? Go from zero to a fully functional CLI tool
          in a single day using the flywheel workflow.
        </Paragraph>

        <div className="mt-8">
          <ResultsCard />
        </div>

        <div className="mt-8">
          <InteractiveSwarmTimeline />
        </div>

        <Paragraph>
          This lesson walks you through exactly how it was done, so you can
          replicate this workflow on your own projects.
        </Paragraph>
      </Section>

      <Divider />

      {/* Phase 1: Multi-Model Planning */}
      <Section
        title="Phase 1: Multi-Model Planning"
        icon={<FileText className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          The first step isn&apos;t to start coding. It&apos;s to{" "}
          <Highlight>gather diverse perspectives</Highlight> on the problem.
        </Paragraph>

        <div className="mt-8">
          <PhaseCard
            phase={1}
            title="Collect Competing Proposals"
            description="Ask multiple frontier models to propose implementation plans"
          >
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <ModelCard
                name="GPT 5.1 Pro"
                color="from-emerald-500/20 to-teal-500/20"
                focus="Scientific validation approach"
              />
              <ModelCard
                name="Gemini 3 Ultra"
                color="from-blue-500/20 to-indigo-500/20"
                focus="Search pointers & tombstones"
              />
              <ModelCard
                name="Grok 4.1"
                color="from-violet-500/20 to-purple-500/20"
                focus="Cross-agent enrichment"
              />
              <ModelCard
                name="Claude Opus 4.5"
                color="from-amber-500/20 to-orange-500/20"
                focus="ACE pipeline design"
              />
            </div>
          </PhaseCard>
        </div>

        <div className="mt-6">
          <Paragraph>
            Each model received the same prompt with minimal guidance - just 2-3
            messages to clarify the goal. The key instruction: &quot;Design a
            memory system that works for{" "}
            <em>all</em> coding agents, not just Claude.&quot;
          </Paragraph>
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Save each conversation as markdown. The{" "}
            <InlineCode>chat_shared_conversation_to_file</InlineCode> tool makes
            this easy.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Phase 2: Synthesis */}
      <Section
        title="Phase 2: Plan Synthesis"
        icon={<Layers className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          Now comes the crucial step: have one model synthesize the best ideas
          from all proposals into a single master plan.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Put all proposal files in the project folder
competing_proposal_plans/
  2025-12-07-gemini-*.md
  2025-12-07-grok-*.md
  gpt_pro_version.md
  claude_version/

# Ask Opus 4.5 to create the hybrid plan
cc "Read all the files in competing_proposal_plans/.
Create a hybrid plan that takes the best parts of each.
Write it to PLAN_FOR_CASS_MEMORY_SYSTEM.md"`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <SynthesisResultCard />
        </div>

        <Paragraph>
          The resulting plan was <strong>5,600+ lines</strong> - a comprehensive
          blueprint covering architecture, data models, CLI commands, the
          reflection pipeline, storage, and implementation roadmap.
        </Paragraph>
      </Section>

      <Divider />

      {/* Anatomy of a Great Plan */}
      <Section
        title="Anatomy of a Great Plan"
        icon={<BookOpen className="h-5 w-5" />}
        delay={0.22}
      >
        <Paragraph>
          The plan is the bedrock of a successful agentic project. Let&apos;s
          dissect what makes{" "}
          <a
            href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/docs/planning/PLAN_FOR_CASS_MEMORY_SYSTEM.md"
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary underline inline-flex items-center gap-1"
          >
            the actual 5,600+ line plan
            <ExternalLink className="h-3 w-3" />
          </a>{" "}
          so effective.
        </Paragraph>

        {/* Document Structure */}
        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Layers className="h-5 w-5 text-violet-400" />
            Document Structure: 11 Major Sections
          </h4>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <PlanSectionCard
              number={1}
              title="Executive Summary"
              description="Problem statement, three-layer solution, key innovations table"
              icon={<Rocket className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={2}
              title="Core Architecture"
              description="Cognitive model, ACE pipeline, 7 design principles"
              icon={<Brain className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={3}
              title="Data Models"
              description="TypeScript schemas, confidence decay algorithm, validation rules"
              icon={<Database className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={4}
              title="CLI Commands"
              description="15+ commands with usage examples and JSON outputs"
              icon={<Terminal className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={5}
              title="Reflection Pipeline"
              description="Generator, Reflector, Validator, Curator phases"
              icon={<Layers className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={6}
              title="Integration"
              description="Search wrapper, error handling, secret sanitization"
              icon={<Code className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={7}
              title="LLM Integration"
              description="Provider abstraction, Zod schemas, prompt templates"
              icon={<Bot className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={8}
              title="Storage & Persistence"
              description="Directory structure, cascading config, embeddings"
              icon={<Database className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={9}
              title="Agent Integration"
              description="AGENTS.md template, MCP server design"
              icon={<Users className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={10}
              title="Implementation Roadmap"
              description="Phased delivery with ROI priorities"
              icon={<TrendingUp className="h-4 w-4" />}
            />
            <PlanSectionCard
              number={11}
              title="Comparison Matrix"
              description="Feature checklist against competing proposals"
              icon={<CheckCircle className="h-4 w-4" />}
            />
          </div>
        </div>

        {/* Key Patterns */}
        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Lightbulb className="h-5 w-5 text-amber-400" />
            Patterns That Make Plans Effective
          </h4>
          <div className="space-y-4">
            <PlanPatternCard
              title="Theory-First Approach"
              description="Each major feature includes: schema definition → algorithm → usage examples → implementation notes. Never jumps to code before explaining the why."
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <PlanPatternCard
              title="Progressive Elaboration"
              description="Simple concepts expand into nested detail. 'Bullet maturity' starts as a concept, becomes a state machine, then includes transition rules and decay calculations."
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <PlanPatternCard
              title="Concrete Examples Throughout"
              description="Not just 'validate inputs' but actual TypeScript interfaces, JSON outputs, bash command examples, and ASCII diagrams showing data flow."
              gradient="from-sky-500/20 to-blue-500/20"
            />
            <PlanPatternCard
              title="Edge Cases Anticipated"
              description="The plan addresses error handling for cass timeouts, toxic bullet blocking, stale rule detection, and secret sanitization before implementation begins."
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <PlanPatternCard
              title="Comparison Tables"
              description="Key decisions contextualized against alternatives. Shows trade-offs between approaches from different model proposals."
              gradient="from-rose-500/20 to-pink-500/20"
            />
          </div>
        </div>

        {/* Distinctive Innovations */}
        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Shield className="h-5 w-5 text-emerald-400" />
            Distinctive Innovations in This Plan
          </h4>
          <div className="grid gap-4 sm:grid-cols-2">
            <InnovationCard
              title="Confidence Decay Half-Life"
              description="Rules lose credibility over time. Harmful events weighted 4× helpful ones. Full algorithm with decay factors specified."
            />
            <InnovationCard
              title="Anti-Pattern Inversion"
              description="Harmful rules converted to 'DON'T do X' instead of deleted, preserving the learning while inverting the advice."
            />
            <InnovationCard
              title="Evidence-Count Gate"
              description="Pre-LLM heuristic filter that saves API calls. Rules need minimum evidence before promotion."
            />
            <InnovationCard
              title="Cascading Config"
              description="Global user playbooks + repo-level playbooks merged intelligently with conflict resolution."
            />
          </div>
        </div>

        {/* What to Include Checklist */}
        <div className="mt-8">
          <TipBox variant="tip">
            <strong>What Your Plans Should Include:</strong>
            <ul className="mt-2 space-y-1 text-sm">
              <li>• <strong>Executive summary</strong> - Problem + solution in 1 page</li>
              <li>• <strong>Data models</strong> - TypeScript/Zod schemas for all entities</li>
              <li>• <strong>CLI/API surface</strong> - Every command with examples</li>
              <li>• <strong>Architecture diagrams</strong> - ASCII boxes showing data flow</li>
              <li>• <strong>Error handling</strong> - What can go wrong, how to recover</li>
              <li>• <strong>Implementation roadmap</strong> - Prioritized phases with dependencies</li>
              <li>• <strong>Comparison tables</strong> - Why this approach over alternatives</li>
            </ul>
          </TipBox>
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            The full plan is available at{" "}
            <a
              href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/docs/planning/PLAN_FOR_CASS_MEMORY_SYSTEM.md"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary underline"
            >
              github.com/Dicklesworthstone/cass_memory_system
            </a>
            . Study it as a template for your own project plans.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Phase 3: Beads Transformation */}
      <Section
        title="Phase 3: From Plan to Beads"
        icon={<LayoutDashboard className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          A 5,600-line markdown file is great for humans, but agents need{" "}
          <Highlight>structured, trackable tasks</Highlight>. This is where
          beads comes in.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Initialize beads in the project
br init

# Have an agent transform the plan into beads
cc "Read PLAN_FOR_CASS_MEMORY_SYSTEM.md carefully.

Transform each section, feature, and implementation detail
into individual beads using the br CLI.

Create epics for major phases, then break them into tasks.
Set up dependencies so blockers are clear.
Use priorities: P0 for foundation, P1-P2 for core features,
P3-P4 for polish and future work.

Create at least 300 beads covering the full implementation."`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <BeadsTransformationCard />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            This transformation took multiple passes to refine. The agents
            reviewed and improved the beads structure several times.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Phase 4: Swarm Execution */}
      <Section
        title="Phase 4: Swarm Execution"
        icon={<Users className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          With 350+ beads ready, it&apos;s time to{" "}
          <Highlight>unleash the swarm</Highlight>. Multiple agents work in
          parallel, each picking up tasks based on what&apos;s ready.
        </Paragraph>

        <div className="mt-6">
          <SwarmSetupCard />
        </div>

        <div className="mt-8">
          <CodeBlock
            code={`# Launch the swarm with NTM
ntm spawn cass-memory --cc=6 --cod=3 --agy=2

# Each agent runs this workflow:
# 1. Check what's ready
bv --robot-triage

# 2. Claim a task
br update <id> --status in_progress

# 3. Implement
# (agent does the work)

# 4. Close when done
br close <id>

# 5. Repeat`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <Paragraph>
            The agents coordinate using <strong>bv</strong> (beads viewer) to
            see what&apos;s ready, avoiding conflicts and ensuring the most
            important blockers get cleared first.
          </Paragraph>
        </div>
      </Section>

      <Divider />

      {/* Agent Coordination */}
      <Section
        title="Agent Coordination with Agent Mail"
        icon={<Mail className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          When agents need to share context or coordinate on overlapping work,{" "}
          <Highlight>Agent Mail</Highlight> provides the communication layer.
        </Paragraph>

        <div className="mt-6">
          <BulletList
            items={[
              <span key="1">
                <strong>File reservations:</strong> Agents claim files before
                editing to avoid conflicts
              </span>,
              <span key="2">
                <strong>Status updates:</strong> Agents report progress so
                others know what&apos;s happening
              </span>,
              <span key="3">
                <strong>Handoffs:</strong> When one agent finishes a blocker,
                dependent agents get notified
              </span>,
              <span key="4">
                <strong>Review requests:</strong> Agents can ask each other to
                review their work
              </span>,
            ]}
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Example Agent Mail coordination

# Agent "BlueLake" reserves files before editing
mcp.file_reservation_paths(
  project_key="/data/projects/cass-memory",
  agent_name="BlueLake",
  paths=["src/playbook/*.ts"],
  ttl_seconds=3600,
  exclusive=true
)

# Agent "GreenCastle" messages about a blocker being cleared
mcp.send_message(
  project_key="/data/projects/cass-memory",
  sender_name="GreenCastle",
  to=["BlueLake", "RedFox"],
  subject="Types foundation complete",
  body_md="Zod schemas are done. You can now work on playbook and CLI."
)`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            The full Agent Mail archive from this project was{" "}
            <a
              href="https://dicklesworthstone.github.io/cass-memory-system-agent-mailbox-viewer/viewer/"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary underline"
            >
              published as a static site
            </a>{" "}
            so you can see the actual agent-to-agent communication.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* The Commit Cadence */}
      <Section
        title="The Commit Cadence"
        icon={<GitBranch className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>
          With many agents working simultaneously, commits need careful
          orchestration. A dedicated{" "}
          <Highlight>commit agent</Highlight> runs continuously.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# The commit agent pattern (runs every 15-20 minutes)

# Step 1: Understand the project
cc "First read AGENTS.md, read the README, and explore
the project to understand what we're doing. Use /effort max."

# Step 2: Commit in logical groupings
cc "Based on your knowledge of the project, commit all
changed files now in a series of logically connected
groupings with super detailed commit messages for each
and then push.

Take your time to do it right. Don't edit the code at all.
Don't commit ephemeral files. Use /effort max."`}
            showLineNumbers
          />
        </div>

        <div className="mt-8">
          <CommitStatsCard />
        </div>

        <Paragraph>
          This pattern ensures atomic, well-documented commits even when 10+
          agents are making changes simultaneously.
        </Paragraph>
      </Section>

      <Divider />

      {/* Results & Lessons */}
      <Section
        title="Results & Key Lessons"
        icon={<TrendingUp className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          After one day of flywheel-powered development, the cass-memory project
          achieved:
        </Paragraph>

        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            value="11K+"
            label="Lines of Code"
            gradient="from-emerald-500/20 to-teal-500/20"
          />
          <StatCard
            value="282"
            label="Day 1 Commits"
            gradient="from-sky-500/20 to-blue-500/20"
          />
          <StatCard
            value="151"
            label="Tests Passing"
            gradient="from-violet-500/20 to-purple-500/20"
          />
          <StatCard
            value="85-90%"
            label="Complete"
            gradient="from-amber-500/20 to-orange-500/20"
          />
        </div>

        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4">Key Lessons</h4>
          <StepList
            steps={[
              {
                title: "Planning is 80% of the work",
                description:
                  "A detailed plan makes agent execution predictable and fast",
              },
              {
                title: "Multi-model synthesis beats single-model planning",
                description:
                  "Each model brought unique insights that improved the final design",
              },
              {
                title: "Beads enable parallelism",
                description:
                  "Structured tasks with dependencies let many agents work without conflicts",
              },
              {
                title: "Coordination tools are essential",
                description:
                  "Agent Mail and file reservations prevent agents from stepping on each other",
              },
              {
                title: "Dedicated commit agent keeps history clean",
                description:
                  "Separating commit responsibility from coding ensures atomic commits",
              },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Yourself */}
      <Section
        title="Try It Yourself"
        icon={<Play className="h-5 w-5" />}
        delay={0.5}
      >
        <Paragraph>
          Ready to try this workflow on your own project? Here&apos;s the
          quickstart:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# 1. Gather proposals from multiple models
# (Use GPT Pro, Gemini, Claude, Grok - whichever you have access to)
# Save each as markdown in competing_proposal_plans/

# 2. Synthesize into a master plan
cc "Read all files in competing_proposal_plans/.
Create a hybrid plan taking the best of each.
Write to PLAN.md"

# 3. Transform plan into beads
br init
cc "Read PLAN.md. Transform into 100+ beads with
dependencies and priorities. Use br CLI."

# 4. Launch the swarm
ntm spawn myproject --cc=3 --cod=2 --agy=1

# 5. Monitor with bv
bv --robot-triage  # See what's ready

# 6. Watch the magic happen
ntm attach myproject

# 7. (Every 15-20 min) Run the commit agent
cc "Commit all changes in logical groupings with
detailed messages. Don't edit code. Push when done."`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Start smaller than the cass-memory example. Try this workflow with a
            project that would normally take you a day or two manually. Build
            your confidence before tackling larger projects.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// RESULTS CARD - Day 1 results summary
// =============================================================================
function ResultsCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2 }}
      className="relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden"
    >
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/20 rounded-full blur-3xl" />

      <div className="relative">
        <div className="flex items-center gap-3 mb-4">
          <Rocket className="h-6 w-6 text-emerald-400" />
          <h4 className="text-lg font-bold text-white">Day 1 Results</h4>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="text-center">
            <div className="text-3xl font-bold text-emerald-400">693</div>
            <div className="text-sm text-white/60">Total Beads</div>
          </div>
          <div className="text-center">
            <div className="text-3xl font-bold text-emerald-400">282</div>
            <div className="text-sm text-white/60">Day 1 Commits</div>
          </div>
          <div className="text-center">
            <div className="text-3xl font-bold text-emerald-400">25+</div>
            <div className="text-sm text-white/60">Agents Involved</div>
          </div>
          <div className="text-center">
            <div className="text-3xl font-bold text-emerald-400">~5hrs</div>
            <div className="text-sm text-white/60">To 85% Complete</div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// PHASE CARD - Workflow phase container
// =============================================================================
function PhaseCard({
  phase,
  title,
  description,
  children,
}: {
  phase: number;
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15]"
    >
      <div className="flex items-center gap-4 mb-4">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white font-bold">
          {phase}
        </div>
        <div>
          <h4 className="font-bold text-white">{title}</h4>
          <p className="text-sm text-white/50">{description}</p>
        </div>
      </div>
      {children}
    </motion.div>
  );
}

// =============================================================================
// MODEL CARD - Individual AI model proposal
// =============================================================================
function ModelCard({
  name,
  color,
  focus,
}: {
  name: string;
  color: string;
  focus: string;
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
        <span className="font-semibold text-white text-sm">{name}</span>
      </div>
      <p className="text-xs text-white/60 group-hover:text-white/80 transition-colors">{focus}</p>
    </motion.div>
  );
}

// =============================================================================
// SYNTHESIS RESULT CARD
// =============================================================================
function SynthesisResultCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-violet-500/30 bg-gradient-to-br from-violet-500/10 to-purple-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-violet-500/50"
    >
      <h4 className="font-bold text-white mb-3 flex items-center gap-2">
        <FileText className="h-5 w-5 text-violet-400" />
        PLAN_FOR_CASS_MEMORY_SYSTEM.md
      </h4>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="text-sm text-white/70">
          <span className="text-violet-400 font-semibold">5,600+</span> lines
        </div>
        <div className="text-sm text-white/70">
          <span className="text-violet-400 font-semibold">11</span> major
          sections
        </div>
        <div className="text-sm text-white/70">
          <span className="text-violet-400 font-semibold">Best ideas</span> from
          4 models
        </div>
        <div className="text-sm text-white/70">
          <span className="text-violet-400 font-semibold">Complete</span>{" "}
          implementation roadmap
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// BEADS TRANSFORMATION CARD
// =============================================================================
function BeadsTransformationCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-sky-500/30 bg-gradient-to-br from-sky-500/10 to-blue-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-sky-500/50"
    >
      <div className="flex items-center gap-3 mb-4">
        <LayoutDashboard className="h-5 w-5 text-sky-400" />
        <h4 className="font-bold text-white">Beads Structure</h4>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">14</div>
          <div className="text-xs text-white/60">Epics</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">350+</div>
          <div className="text-xs text-white/60">Tasks</div>
        </div>
        <div className="text-center p-4 rounded-xl bg-black/20">
          <div className="text-2xl font-bold text-sky-400">13h</div>
          <div className="text-xs text-white/60">Avg Lead Time</div>
        </div>
      </div>

      <p className="mt-4 text-sm text-white/60">
        Tasks linked with dependencies so blockers are visible and agents know
        what to work on next.
      </p>
    </motion.div>
  );
}

// =============================================================================
// SWARM SETUP CARD
// =============================================================================
function SwarmSetupCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-amber-500/50"
    >
      <div className="flex items-center gap-3 mb-4">
        <Users className="h-5 w-5 text-amber-400" />
        <h4 className="font-bold text-white">The Agent Swarm</h4>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <div className="flex items-center gap-3 p-3 rounded-xl bg-black/20">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-br from-orange-500 to-amber-500">
            <Bot className="h-5 w-5 text-white" />
          </div>
          <div>
            <div className="font-semibold text-white text-sm">Claude Code</div>
            <div className="text-xs text-white/50">5-6 agents (Opus 4.5)</div>
          </div>
        </div>
        <div className="flex items-center gap-3 p-3 rounded-xl bg-black/20">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-br from-emerald-500 to-teal-500">
            <Bot className="h-5 w-5 text-white" />
          </div>
          <div>
            <div className="font-semibold text-white text-sm">Codex CLI</div>
            <div className="text-xs text-white/50">3 agents (5.1 Max)</div>
          </div>
        </div>
        <div className="flex items-center gap-3 p-3 rounded-xl bg-black/20">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-br from-blue-500 to-indigo-500">
            <Bot className="h-5 w-5 text-white" />
          </div>
          <div>
            <div className="font-semibold text-white text-sm">Antigravity CLI</div>
            <div className="text-xs text-white/50">2 agents (review duty)</div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// COMMIT STATS CARD
// =============================================================================
function CommitStatsCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-rose-500/30 bg-gradient-to-br from-rose-500/10 to-pink-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-rose-500/50"
    >
      <div className="flex items-center gap-3 mb-4">
        <GitBranch className="h-5 w-5 text-rose-400" />
        <h4 className="font-bold text-white">Commit Statistics</h4>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="text-center">
          <div className="text-2xl font-bold text-rose-400">282</div>
          <div className="text-xs text-white/60">Day 1 Commits</div>
        </div>
        <div className="text-center">
          <div className="text-2xl font-bold text-rose-400">~12</div>
          <div className="text-xs text-white/60">Per Hour</div>
        </div>
        <div className="text-center">
          <div className="text-2xl font-bold text-rose-400">Detailed</div>
          <div className="text-xs text-white/60">Messages</div>
        </div>
      </div>

      <p className="mt-4 text-sm text-white/60">
        The commit agent ran every 15-20 minutes, grouping changes logically and
        writing detailed commit messages.
      </p>
    </motion.div>
  );
}

// =============================================================================
// STAT CARD
// =============================================================================
function StatCard({
  value,
  label,
  gradient,
}: {
  value: string;
  label: string;
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ scale: 1.05 }}
      className={`relative rounded-xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-4 text-center backdrop-blur-xl`}
    >
      <div className="text-2xl font-bold text-white">{value}</div>
      <div className="text-xs text-white/60">{label}</div>
    </motion.div>
  );
}

// =============================================================================
// PLAN SECTION CARD - Shows a section from the plan document
// =============================================================================
function PlanSectionCard({
  number,
  title,
  description,
  icon,
}: {
  number: number;
  title: string;
  description: string;
  icon: ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: number * 0.03 }}
      whileHover={{ y: -2, scale: 1.02 }}
      className="group relative rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 backdrop-blur-xl transition-all duration-300 hover:border-violet-500/30 hover:bg-violet-500/5"
    >
      <div className="flex items-center gap-3 mb-2">
        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-violet-500/20 text-violet-400 text-xs font-bold group-hover:bg-violet-500/30 transition-colors">
          {number}
        </div>
        <div className="text-violet-400 group-hover:scale-110 transition-transform">
          {icon}
        </div>
      </div>
      <h5 className="font-semibold text-white text-sm mb-1 group-hover:text-violet-300 transition-colors">
        {title}
      </h5>
      <p className="text-xs text-white/50 group-hover:text-white/70 transition-colors">
        {description}
      </p>
    </motion.div>
  );
}

// =============================================================================
// PLAN PATTERN CARD - Shows a pattern that makes plans effective
// =============================================================================
function PlanPatternCard({
  title,
  description,
  gradient,
}: {
  title: string;
  description: string;
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className={`group relative rounded-xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-5 backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]`}
    >
      <h5 className="font-semibold text-white mb-2 group-hover:text-white/90 transition-colors">
        {title}
      </h5>
      <p className="text-sm text-white/60 group-hover:text-white/80 transition-colors">
        {description}
      </p>
    </motion.div>
  );
}

// =============================================================================
// INNOVATION CARD - Shows distinctive innovations from the plan
// =============================================================================
function InnovationCard({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -2, scale: 1.02 }}
      className="group relative rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-5 backdrop-blur-xl transition-all duration-300 hover:border-emerald-500/40 hover:bg-emerald-500/10"
    >
      <div className="flex items-center gap-2 mb-2">
        <Lightbulb className="h-4 w-4 text-emerald-400 group-hover:scale-110 transition-transform" />
        <h5 className="font-semibold text-white group-hover:text-emerald-300 transition-colors">
          {title}
        </h5>
      </div>
      <p className="text-sm text-white/60 group-hover:text-white/80 transition-colors">
        {description}
      </p>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE SWARM TIMELINE - Multi-agent swarm case study replay
// =============================================================================

// -- Agent Definitions --------------------------------------------------------

interface SwarmAgent {
  id: string;
  name: string;
  platform: "cc" | "codex" | "gemini";
  color: string;
  borderColor: string;
  bgColor: string;
  textColor: string;
}

const SWARM_AGENTS: SwarmAgent[] = [
  { id: "a1", name: "BlueLake", platform: "cc", color: "bg-blue-500", borderColor: "border-blue-500/40", bgColor: "bg-blue-500/10", textColor: "text-blue-400" },
  { id: "a2", name: "RedFox", platform: "cc", color: "bg-rose-500", borderColor: "border-rose-500/40", bgColor: "bg-rose-500/10", textColor: "text-rose-400" },
  { id: "a3", name: "GreenCastle", platform: "cc", color: "bg-emerald-500", borderColor: "border-emerald-500/40", bgColor: "bg-emerald-500/10", textColor: "text-emerald-400" },
  { id: "a4", name: "GoldPeak", platform: "cc", color: "bg-amber-500", borderColor: "border-amber-500/40", bgColor: "bg-amber-500/10", textColor: "text-amber-400" },
  { id: "a5", name: "SilverWind", platform: "cc", color: "bg-slate-400", borderColor: "border-slate-400/40", bgColor: "bg-slate-400/10", textColor: "text-slate-300" },
  { id: "a6", name: "VioletStar", platform: "cc", color: "bg-violet-500", borderColor: "border-violet-500/40", bgColor: "bg-violet-500/10", textColor: "text-violet-400" },
  { id: "a7", name: "CodBot-1", platform: "codex", color: "bg-teal-500", borderColor: "border-teal-500/40", bgColor: "bg-teal-500/10", textColor: "text-teal-400" },
  { id: "a8", name: "CodBot-2", platform: "codex", color: "bg-cyan-500", borderColor: "border-cyan-500/40", bgColor: "bg-cyan-500/10", textColor: "text-cyan-400" },
  { id: "a9", name: "CodBot-3", platform: "codex", color: "bg-sky-500", borderColor: "border-sky-500/40", bgColor: "bg-sky-500/10", textColor: "text-sky-400" },
  { id: "a10", name: "GmiReview-1", platform: "gemini", color: "bg-orange-500", borderColor: "border-orange-500/40", bgColor: "bg-orange-500/10", textColor: "text-orange-400" },
  { id: "a11", name: "GmiReview-2", platform: "gemini", color: "bg-pink-500", borderColor: "border-pink-500/40", bgColor: "bg-pink-500/10", textColor: "text-pink-400" },
];

// -- Timeline Event Definitions -----------------------------------------------

type EventKind = "kickoff" | "assignment" | "parallel" | "conflict" | "resolution" | "integration" | "testing" | "deployment";

interface TimelineEvent {
  id: number;
  time: string;
  minuteOffset: number;
  title: string;
  kind: EventKind;
  icon: ReactNode;
  description: string;
  agentIds: string[];
  files: string[];
  command: string;
  detail: string;
}

const EVENT_KIND_STYLES: Record<EventKind, { gradient: string; ring: string }> = {
  kickoff:     { gradient: "from-blue-500/20 to-indigo-500/20",   ring: "ring-blue-500/30" },
  assignment:  { gradient: "from-violet-500/20 to-purple-500/20", ring: "ring-violet-500/30" },
  parallel:    { gradient: "from-emerald-500/20 to-teal-500/20",  ring: "ring-emerald-500/30" },
  conflict:    { gradient: "from-rose-500/20 to-red-500/20",      ring: "ring-rose-500/30" },
  resolution:  { gradient: "from-amber-500/20 to-orange-500/20",  ring: "ring-amber-500/30" },
  integration: { gradient: "from-sky-500/20 to-blue-500/20",      ring: "ring-sky-500/30" },
  testing:     { gradient: "from-teal-500/20 to-cyan-500/20",     ring: "ring-teal-500/30" },
  deployment:  { gradient: "from-emerald-500/20 to-green-500/20", ring: "ring-emerald-500/30" },
};

const TIMELINE_EVENTS: TimelineEvent[] = [
  {
    id: 1,
    time: "0:00",
    minuteOffset: 0,
    title: "Project Kickoff",
    kind: "kickoff",
    icon: <Rocket className="h-4 w-4" />,
    description: "Master plan loaded, beads initialized. 693 beads with 14 epics ready for assignment. NTM session spawned.",
    agentIds: [],
    files: ["PLAN_FOR_CASS_MEMORY_SYSTEM.md", ".beads/issues.jsonl"],
    command: "ntm spawn cass-memory --cc=6 --cod=3 --agy=2",
    detail: "The 5,600-line hybrid plan from 4 competing AI proposals is loaded as the project source of truth. Beads are initialized with dependency chains so agents always know what is unblocked.",
  },
  {
    id: 2,
    time: "0:05",
    minuteOffset: 5,
    title: "Agent Assignment",
    kind: "assignment",
    icon: <Users className="h-4 w-4" />,
    description: "11 agents claim their first beads based on priority and dependencies. Foundation work distributed.",
    agentIds: ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11"],
    files: ["src/types/index.ts", "src/schemas/bullet.ts", "src/config/defaults.ts"],
    command: "bv --robot-triage  # each agent picks top-priority unblocked bead",
    detail: "BlueLake takes Zod schemas, RedFox takes CLI scaffolding, GreenCastle takes storage layer. CodBot agents handle infrastructure (CI, Docker, test harness). Antigravity agents begin review duty.",
  },
  {
    id: 3,
    time: "0:30",
    minuteOffset: 30,
    title: "Parallel Development",
    kind: "parallel",
    icon: <Zap className="h-4 w-4" />,
    description: "All 11 agents coding simultaneously. File reservations prevent collisions. 47 beads completed in first 30 min.",
    agentIds: ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9"],
    files: ["src/playbook/*.ts", "src/cli/*.ts", "src/storage/*.ts", "src/reflect/*.ts"],
    command: "br close BEAD-042 && br update BEAD-043 --status in_progress",
    detail: "Peak parallelism achieved. Each agent works on an independent subtree of the dependency graph. Agent Mail file reservations ensure no two agents edit the same module simultaneously.",
  },
  {
    id: 4,
    time: "1:15",
    minuteOffset: 75,
    title: "First Conflict Detected",
    kind: "conflict",
    icon: <AlertTriangle className="h-4 w-4" />,
    description: "BlueLake and RedFox both modify src/types/index.ts. GmiReview-1 detects the merge conflict during review.",
    agentIds: ["a1", "a2", "a10"],
    files: ["src/types/index.ts"],
    command: "# GmiReview-1 flags: conflicting type definitions in BulletSchema",
    detail: "BlueLake added confidence decay fields while RedFox added CLI output types. Both touched the BulletSchema interface. The Gemini review agent caught the divergence before it reached main.",
  },
  {
    id: 5,
    time: "1:20",
    minuteOffset: 80,
    title: "Conflict Resolution via Agent Mail",
    kind: "resolution",
    icon: <MessageSquare className="h-4 w-4" />,
    description: "Agent Mail coordinates: BlueLake rebases, RedFox waits. Conflict resolved in 5 minutes with zero human intervention.",
    agentIds: ["a1", "a2", "a10"],
    files: ["src/types/index.ts", ".agent-mail/inbox/RedFox/"],
    command: 'mcp.send_message(to=["RedFox"], subject="Types conflict resolved", body_md="Merged decay fields. You can rebase now.")',
    detail: "GmiReview-1 instructs BlueLake to finalize the type merge (its changes are more foundational). RedFox receives an Agent Mail message to rebase. The reservation on src/types/index.ts is released 5 minutes later.",
  },
  {
    id: 6,
    time: "2:30",
    minuteOffset: 150,
    title: "Integration Checkpoint",
    kind: "integration",
    icon: <Merge className="h-4 w-4" />,
    description: "Commit agent groups 87 pending changes into 34 atomic commits. All modules integrate cleanly. 240 beads done.",
    agentIds: ["a5", "a10", "a11"],
    files: ["*"],
    command: 'cc "Commit all changed files in logically connected groupings with detailed messages. Push when done."',
    detail: "SilverWind acts as the dedicated commit agent, running every 15-20 minutes. It reads the project context, groups related changes, writes detailed commit messages, and pushes. No code editing -- just clean git hygiene.",
  },
  {
    id: 7,
    time: "3:45",
    minuteOffset: 225,
    title: "Test Suite Green",
    kind: "testing",
    icon: <CheckCircle className="h-4 w-4" />,
    description: "151 tests passing across unit, integration, and CLI tests. Coverage at 78%. GmiReview-2 validates edge cases.",
    agentIds: ["a8", "a9", "a11"],
    files: ["tests/**/*.test.ts", "src/**/*.test.ts"],
    command: "bun test --coverage  # 151 passing, 0 failing",
    detail: "CodBot-2 and CodBot-3 wrote tests in parallel as features landed. GmiReview-2 did a final sweep adding edge-case tests for confidence decay, toxic bullet blocking, and stale rule detection.",
  },
  {
    id: 8,
    time: "5:00",
    minuteOffset: 300,
    title: "Deployment Ready",
    kind: "deployment",
    icon: <Trophy className="h-4 w-4" />,
    description: "282 commits pushed. 11K+ lines of code. 85-90% of all beads complete. CLI tool fully functional.",
    agentIds: ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11"],
    files: ["package.json", "dist/**", "README.md"],
    command: "bv --robot-triage  # remaining: polish, docs, advanced features",
    detail: "From zero to a fully functional procedural memory CLI in 5 hours. The remaining 10-15% consists of documentation polish, advanced embedding search, and performance optimization -- all tracked as P3-P4 beads.",
  },
];

// -- Gantt Chart Data ---------------------------------------------------------

interface GanttRow {
  agentId: string;
  segments: { startMin: number; endMin: number; label: string; kind: EventKind }[];
}

const GANTT_DATA: GanttRow[] = [
  { agentId: "a1", segments: [
    { startMin: 5, endMin: 75, label: "Zod schemas", kind: "parallel" },
    { startMin: 75, endMin: 85, label: "Conflict fix", kind: "conflict" },
    { startMin: 85, endMin: 200, label: "Reflection pipeline", kind: "parallel" },
    { startMin: 200, endMin: 300, label: "Enrichment engine", kind: "integration" },
  ]},
  { agentId: "a2", segments: [
    { startMin: 5, endMin: 75, label: "CLI scaffolding", kind: "parallel" },
    { startMin: 80, endMin: 85, label: "Rebase", kind: "resolution" },
    { startMin: 85, endMin: 220, label: "CLI commands", kind: "parallel" },
    { startMin: 220, endMin: 300, label: "Output formatting", kind: "integration" },
  ]},
  { agentId: "a3", segments: [
    { startMin: 5, endMin: 150, label: "Storage layer", kind: "parallel" },
    { startMin: 155, endMin: 300, label: "Cascading config", kind: "parallel" },
  ]},
  { agentId: "a4", segments: [
    { startMin: 10, endMin: 120, label: "LLM provider", kind: "parallel" },
    { startMin: 125, endMin: 250, label: "Prompt templates", kind: "parallel" },
    { startMin: 255, endMin: 300, label: "Error handling", kind: "integration" },
  ]},
  { agentId: "a5", segments: [
    { startMin: 30, endMin: 50, label: "Commit round 1", kind: "integration" },
    { startMin: 70, endMin: 90, label: "Commit round 2", kind: "integration" },
    { startMin: 130, endMin: 155, label: "Commit round 3", kind: "integration" },
    { startMin: 190, endMin: 210, label: "Commit round 4", kind: "integration" },
    { startMin: 250, endMin: 275, label: "Commit round 5", kind: "integration" },
    { startMin: 285, endMin: 300, label: "Final push", kind: "deployment" },
  ]},
  { agentId: "a6", segments: [
    { startMin: 10, endMin: 140, label: "MCP server", kind: "parallel" },
    { startMin: 145, endMin: 280, label: "Agent integration", kind: "parallel" },
    { startMin: 280, endMin: 300, label: "AGENTS.md", kind: "deployment" },
  ]},
  { agentId: "a7", segments: [
    { startMin: 5, endMin: 100, label: "CI pipeline", kind: "parallel" },
    { startMin: 105, endMin: 200, label: "Docker setup", kind: "parallel" },
    { startMin: 205, endMin: 300, label: "Build scripts", kind: "integration" },
  ]},
  { agentId: "a8", segments: [
    { startMin: 30, endMin: 180, label: "Unit tests", kind: "testing" },
    { startMin: 185, endMin: 300, label: "Integration tests", kind: "testing" },
  ]},
  { agentId: "a9", segments: [
    { startMin: 20, endMin: 120, label: "Test harness", kind: "parallel" },
    { startMin: 125, endMin: 300, label: "CLI tests", kind: "testing" },
  ]},
  { agentId: "a10", segments: [
    { startMin: 15, endMin: 80, label: "Schema review", kind: "assignment" },
    { startMin: 75, endMin: 85, label: "Conflict detect", kind: "conflict" },
    { startMin: 90, endMin: 200, label: "Code review", kind: "assignment" },
    { startMin: 205, endMin: 300, label: "Final review", kind: "testing" },
  ]},
  { agentId: "a11", segments: [
    { startMin: 20, endMin: 150, label: "Security review", kind: "assignment" },
    { startMin: 155, endMin: 250, label: "Edge case tests", kind: "testing" },
    { startMin: 255, endMin: 300, label: "Validation sweep", kind: "deployment" },
  ]},
];

// -- Terminal Command Log Data ------------------------------------------------

const TERMINAL_COMMANDS: { time: string; cmd: string; agent: string }[] = [
  { time: "0:00", cmd: "ntm spawn cass-memory --cc=6 --cod=3 --agy=2", agent: "operator" },
  { time: "0:02", cmd: "bv --robot-triage", agent: "BlueLake" },
  { time: "0:03", cmd: "br update BEAD-001 --status in_progress", agent: "BlueLake" },
  { time: "0:04", cmd: "bv --robot-triage  # picking first unblocked bead", agent: "RedFox" },
  { time: "0:05", cmd: "mcp.file_reservation_paths(paths=[\"src/types/*.ts\"], agent_name=\"BlueLake\")", agent: "BlueLake" },
  { time: "0:05", cmd: "br update BEAD-014 --status in_progress  # CLI scaffolding", agent: "RedFox" },
  { time: "0:06", cmd: "br update BEAD-022 --status in_progress  # storage layer", agent: "GreenCastle" },
  { time: "0:08", cmd: "mcp.file_reservation_paths(paths=[\"src/cli/*.ts\"], agent_name=\"RedFox\")", agent: "RedFox" },
  { time: "0:10", cmd: "br update BEAD-035 --status in_progress  # LLM provider abstraction", agent: "GoldPeak" },
  { time: "0:12", cmd: "br update BEAD-050 --status in_progress  # MCP server skeleton", agent: "VioletStar" },
  { time: "0:15", cmd: "mcp.file_reservation_paths(paths=[\"src/storage/*.ts\"], agent_name=\"GreenCastle\")", agent: "GreenCastle" },
  { time: "0:20", cmd: "br update BEAD-060 --status in_progress  # CI pipeline", agent: "CodBot-1" },
  { time: "0:25", cmd: "br close BEAD-001  # Zod base types done", agent: "BlueLake" },
  { time: "0:28", cmd: "br update BEAD-002 --status in_progress  # BulletSchema", agent: "BlueLake" },
  { time: "0:30", cmd: "br close BEAD-002 && br close BEAD-003", agent: "BlueLake" },
  { time: "0:35", cmd: "bun test src/types  # 12 passing", agent: "CodBot-2" },
  { time: "0:45", cmd: "git add -A && git commit -m \"feat(types): add Zod schemas for Bullet, Playbook\"", agent: "SilverWind" },
  { time: "0:50", cmd: "git commit -m \"feat(cli): scaffold commander.js entry point\"", agent: "SilverWind" },
  { time: "0:55", cmd: "git commit -m \"feat(storage): SQLite adapter with migrations\"", agent: "SilverWind" },
  { time: "1:00", cmd: "git push origin main  # 18 commits pushed", agent: "SilverWind" },
  { time: "1:05", cmd: "br close BEAD-014 BEAD-015 BEAD-016  # CLI commands done", agent: "RedFox" },
  { time: "1:10", cmd: "mcp.send_message(to=[\"GoldPeak\"], subject=\"Types ready for LLM integration\")", agent: "BlueLake" },
  { time: "1:15", cmd: "# CONFLICT: src/types/index.ts modified by BlueLake AND RedFox", agent: "GmiReview-1" },
  { time: "1:17", cmd: "mcp.send_message(to=[\"RedFox\"], subject=\"Hold: types conflict\")", agent: "GmiReview-1" },
  { time: "1:18", cmd: "mcp.release_file_reservation(agent_name=\"RedFox\", paths=[\"src/types/*.ts\"])", agent: "GmiReview-1" },
  { time: "1:20", cmd: "mcp.send_message(to=[\"RedFox\"], subject=\"Resolved. Rebase now.\")", agent: "BlueLake" },
  { time: "1:25", cmd: "git rebase main  # clean merge after BlueLake's fix", agent: "RedFox" },
  { time: "1:30", cmd: "br close BEAD-022 BEAD-023  # storage layer complete", agent: "GreenCastle" },
  { time: "1:45", cmd: "bun test  # 67 passing, 0 failing", agent: "CodBot-2" },
  { time: "2:00", cmd: "br close BEAD-035 BEAD-036 BEAD-037  # LLM provider done", agent: "GoldPeak" },
  { time: "2:15", cmd: "mcp.send_message(to=[\"all\"], subject=\"Halfway checkpoint: 240 beads done\")", agent: "SilverWind" },
  { time: "2:30", cmd: "git log --oneline | wc -l  # => 134 commits", agent: "SilverWind" },
  { time: "2:45", cmd: "br close BEAD-050 BEAD-051  # MCP server operational", agent: "VioletStar" },
  { time: "3:00", cmd: "bv --robot-triage  # 380/693 beads done, 55%", agent: "operator" },
  { time: "3:15", cmd: "br close BEAD-060 BEAD-061  # CI pipeline green", agent: "CodBot-1" },
  { time: "3:30", cmd: "bun test --coverage  # 128 passing, 72% coverage", agent: "CodBot-2" },
  { time: "3:45", cmd: "bun test --coverage  # 151 passing, 0 failing, 78% coverage", agent: "CodBot-2" },
  { time: "4:00", cmd: "git push origin main  # 218 commits total", agent: "SilverWind" },
  { time: "4:15", cmd: "mcp.send_message(to=[\"all\"], subject=\"Test suite fully green, 151 tests\")", agent: "GmiReview-2" },
  { time: "4:30", cmd: "br close BEAD-070..BEAD-085  # reflection pipeline done", agent: "BlueLake" },
  { time: "4:45", cmd: "git commit -m \"docs: generate README and AGENTS.md\"", agent: "VioletStar" },
  { time: "5:00", cmd: "bv --robot-triage  # 590/693 beads done (85%)", agent: "operator" },
];

// -- Agent Accomplishment Details ---------------------------------------------

interface AgentAccomplishment {
  agentId: string;
  beadsClosed: number;
  linesWritten: number;
  filesCreated: number;
  keyContributions: string[];
}

const AGENT_ACCOMPLISHMENTS: AgentAccomplishment[] = [
  {
    agentId: "a1",
    beadsClosed: 72,
    linesWritten: 2140,
    filesCreated: 12,
    keyContributions: [
      "Zod schemas for all data models",
      "Confidence decay algorithm",
      "Reflection pipeline (Generator, Reflector, Validator)",
      "Anti-pattern inversion logic",
      "Enrichment engine with cross-agent context",
    ],
  },
  {
    agentId: "a2",
    beadsClosed: 64,
    linesWritten: 1890,
    filesCreated: 9,
    keyContributions: [
      "CLI entry point with Commander.js",
      "15 CLI commands with --json flag",
      "Output formatting (table, JSON, verbose)",
      "Interactive prompts for destructive ops",
    ],
  },
  {
    agentId: "a3",
    beadsClosed: 58,
    linesWritten: 1650,
    filesCreated: 8,
    keyContributions: [
      "SQLite storage adapter with migrations",
      "Cascading config (global + repo-level)",
      "Search index with prefix matching",
      "Tombstone management for deleted rules",
    ],
  },
  {
    agentId: "a4",
    beadsClosed: 45,
    linesWritten: 1320,
    filesCreated: 7,
    keyContributions: [
      "LLM provider abstraction layer",
      "Prompt templates with variable injection",
      "Zod-validated structured outputs",
      "Error handling with retry logic",
    ],
  },
  {
    agentId: "a5",
    beadsClosed: 15,
    linesWritten: 280,
    filesCreated: 0,
    keyContributions: [
      "282 atomic commits in logical groupings",
      "Detailed multi-line commit messages",
      "Regular push cadence every 15-20 min",
      "Zero merge conflicts in committed code",
    ],
  },
  {
    agentId: "a6",
    beadsClosed: 52,
    linesWritten: 1480,
    filesCreated: 11,
    keyContributions: [
      "MCP server with tool definitions",
      "Agent integration endpoints",
      "AGENTS.md template generation",
      "Search wrapper with caching",
    ],
  },
  {
    agentId: "a7",
    beadsClosed: 38,
    linesWritten: 890,
    filesCreated: 6,
    keyContributions: [
      "CI pipeline with GitHub Actions",
      "Docker multi-stage build",
      "Build scripts for TypeScript compilation",
      "Dependency lockfile management",
    ],
  },
  {
    agentId: "a8",
    beadsClosed: 48,
    linesWritten: 1420,
    filesCreated: 14,
    keyContributions: [
      "78 unit tests covering core modules",
      "Integration tests for storage layer",
      "Mock fixtures for LLM responses",
      "Test coverage reporting setup",
    ],
  },
  {
    agentId: "a9",
    beadsClosed: 42,
    linesWritten: 1180,
    filesCreated: 9,
    keyContributions: [
      "Test harness utilities",
      "CLI end-to-end tests (73 tests)",
      "Snapshot testing for JSON outputs",
      "Performance benchmarks",
    ],
  },
  {
    agentId: "a10",
    beadsClosed: 22,
    linesWritten: 340,
    filesCreated: 2,
    keyContributions: [
      "Schema review and validation",
      "Conflict detection (types/index.ts)",
      "Code review for 180+ changes",
      "API surface consistency checks",
    ],
  },
  {
    agentId: "a11",
    beadsClosed: 34,
    linesWritten: 657,
    filesCreated: 5,
    keyContributions: [
      "Security review (secret sanitization)",
      "Edge-case tests for decay algorithm",
      "Toxic bullet blocking validation",
      "Final acceptance sweep",
    ],
  },
];

// -- Metrics ------------------------------------------------------------------

interface MetricDef {
  label: string;
  value: string;
  icon: ReactNode;
  color: string;
}

const FINAL_METRICS: MetricDef[] = [
  { label: "Wall Clock", value: "5 hrs", icon: <Clock className="h-4 w-4" />, color: "text-blue-400" },
  { label: "Lines of Code", value: "11,247", icon: <Code className="h-4 w-4" />, color: "text-emerald-400" },
  { label: "Commits", value: "282", icon: <GitBranch className="h-4 w-4" />, color: "text-violet-400" },
  { label: "Agents Used", value: "11", icon: <Bot className="h-4 w-4" />, color: "text-amber-400" },
  { label: "Beads Closed", value: "590 / 693", icon: <Grid3X3 className="h-4 w-4" />, color: "text-rose-400" },
  { label: "Tests Passing", value: "151", icon: <CheckCircle className="h-4 w-4" />, color: "text-teal-400" },
];

// -- Before/After Comparison --------------------------------------------------

interface ComparisonItem {
  label: string;
  before: string;
  after: string;
}

const COMPARISONS: ComparisonItem[] = [
  { label: "Source Files", before: "0", after: "67" },
  { label: "Test Files", before: "0", after: "23" },
  { label: "CLI Commands", before: "0", after: "15" },
  { label: "Type Definitions", before: "0", after: "42" },
  { label: "Beads Completed", before: "0 / 693", after: "590 / 693" },
  { label: "Test Coverage", before: "0%", after: "78%" },
];

// -- View Tabs ----------------------------------------------------------------

type ViewTab = "timeline" | "gantt" | "agents" | "conflict" | "metrics" | "before-after" | "terminal";

const VIEW_TABS: { key: ViewTab; label: string; icon: ReactNode }[] = [
  { key: "timeline", label: "Timeline", icon: <Clock className="h-3.5 w-3.5" /> },
  { key: "gantt", label: "Gantt", icon: <Layers className="h-3.5 w-3.5" /> },
  { key: "agents", label: "Agents", icon: <Bot className="h-3.5 w-3.5" /> },
  { key: "conflict", label: "Conflict", icon: <AlertTriangle className="h-3.5 w-3.5" /> },
  { key: "metrics", label: "Metrics", icon: <TrendingUp className="h-3.5 w-3.5" /> },
  { key: "before-after", label: "Before / After", icon: <ArrowRight className="h-3.5 w-3.5" /> },
  { key: "terminal", label: "Terminal", icon: <Terminal className="h-3.5 w-3.5" /> },
];

// =============================================================================
// MAIN COMPONENT
// =============================================================================

function InteractiveSwarmTimeline() {
  const [activeView, setActiveView] = useState<ViewTab>("timeline");
  const [activeEventId, setActiveEventId] = useState<number | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playheadMin, setPlayheadMin] = useState(0);
  const animRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isPlayingRef = useRef(false);

  // Keep ref in sync
  useEffect(() => {
    isPlayingRef.current = isPlaying;
  }, [isPlaying]);

  // Auto-play logic
  useEffect(() => {
    if (!isPlaying) return;
    const tick = () => {
      if (!isPlayingRef.current) return;
      setPlayheadMin((prev) => {
        if (prev >= 300) {
          setTimeout(() => setIsPlaying(false), 0);
          return 300;
        }
        return prev + 2;
      });
      animRef.current = setTimeout(tick, 80);
    };
    animRef.current = setTimeout(tick, 80);
    return () => {
      if (animRef.current) clearTimeout(animRef.current);
    };
  }, [isPlaying]);

  // When playhead moves, auto-select the latest passed event
  useEffect(() => {
    if (!isPlaying) return;
    const passedEvents = TIMELINE_EVENTS.filter((e) => e.minuteOffset <= playheadMin);
    if (passedEvents.length > 0) {
      const latest = passedEvents[passedEvents.length - 1];
      setTimeout(() => setActiveEventId(latest.id), 0);
    }
  }, [playheadMin, isPlaying]);

  const handlePlayPause = useCallback(() => {
    if (isPlaying) {
      setIsPlaying(false);
    } else {
      if (playheadMin >= 300) {
        setPlayheadMin(0);
        setTimeout(() => setActiveEventId(null), 0);
      }
      setIsPlaying(true);
    }
  }, [isPlaying, playheadMin]);

  const handleSkipToEnd = useCallback(() => {
    setIsPlaying(false);
    setPlayheadMin(300);
    setTimeout(() => setActiveEventId(8), 0);
  }, []);

  const handleEventClick = useCallback((id: number) => {
    setIsPlaying(false);
    const evt = TIMELINE_EVENTS.find((e) => e.id === id);
    if (evt) setPlayheadMin(evt.minuteOffset);
    setTimeout(() => setActiveEventId((prev) => (prev === id ? null : id)), 0);
  }, []);

  const agentForId = useCallback((id: string) => SWARM_AGENTS.find((a) => a.id === id), []);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-5 pb-0">
        <h4 className="text-lg font-bold text-white flex items-center gap-2">
          <Rocket className="h-5 w-5 text-primary" />
          Swarm Replay: Zero to 85% in 5 Hours
        </h4>
        <div className="flex items-center gap-2">
          <button
            onClick={handlePlayPause}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-white/[0.12] bg-white/[0.04] text-white/70 hover:bg-white/[0.08] hover:text-white transition-colors"
            aria-label={isPlaying ? "Pause replay" : "Play replay"}
          >
            {isPlaying ? <Pause className="h-3.5 w-3.5" /> : <Play className="h-3.5 w-3.5" />}
          </button>
          <button
            onClick={handleSkipToEnd}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-white/[0.12] bg-white/[0.04] text-white/70 hover:bg-white/[0.08] hover:text-white transition-colors"
            aria-label="Skip to end"
          >
            <SkipForward className="h-3.5 w-3.5" />
          </button>
          <span className="ml-2 font-mono text-xs text-white/40">
            {Math.floor(playheadMin / 60)}h{String(playheadMin % 60).padStart(2, "0")}m / 5h00m
          </span>
        </div>
      </div>

      {/* Progress bar */}
      <div className="px-5 pt-3">
        <div className="relative h-1.5 w-full rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-blue-500 via-violet-500 to-emerald-500"
            animate={{ width: `${(playheadMin / 300) * 100}%` }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
          />
          {/* Event markers */}
          {TIMELINE_EVENTS.map((evt) => (
            <button
              key={evt.id}
              onClick={() => handleEventClick(evt.id)}
              className={`absolute top-1/2 -translate-y-1/2 h-3 w-3 rounded-full border-2 transition-all duration-200 ${
                activeEventId === evt.id
                  ? "border-white bg-primary scale-125 z-10"
                  : evt.minuteOffset <= playheadMin
                    ? "border-white/40 bg-white/20 hover:scale-125"
                    : "border-white/10 bg-white/5 hover:scale-110"
              }`}
              style={{ left: `${(evt.minuteOffset / 300) * 100}%` }}
              aria-label={evt.title}
            />
          ))}
        </div>
        {/* Time labels */}
        <div className="flex justify-between mt-1">
          {["0h", "1h", "2h", "3h", "4h", "5h"].map((t) => (
            <span key={t} className="text-[9px] text-white/25 font-mono">{t}</span>
          ))}
        </div>
      </div>

      {/* View tabs */}
      <div className="flex gap-1 px-5 pt-4 pb-2 overflow-x-auto scrollbar-none">
        {VIEW_TABS.map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveView(tab.key)}
            className={`flex items-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-1.5 text-xs font-medium transition-all duration-200 ${
              activeView === tab.key
                ? "bg-primary/20 text-primary border border-primary/30"
                : "text-white/40 hover:text-white/60 hover:bg-white/[0.04] border border-transparent"
            }`}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* View content */}
      <div className="p-5 pt-2">
        <AnimatePresence mode="wait">
          {activeView === "timeline" && (
            <motion.div
              key="timeline"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <SwarmTimelineView
                activeEventId={activeEventId}
                playheadMin={playheadMin}
                onEventClick={handleEventClick}
                agentForId={agentForId}
              />
            </motion.div>
          )}
          {activeView === "gantt" && (
            <motion.div
              key="gantt"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <GanttChartView playheadMin={playheadMin} agentForId={agentForId} />
            </motion.div>
          )}
          {activeView === "agents" && (
            <motion.div
              key="agents"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <AgentActivityView playheadMin={playheadMin} />
            </motion.div>
          )}
          {activeView === "conflict" && (
            <motion.div
              key="conflict"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <ConflictResolutionView playheadMin={playheadMin} />
            </motion.div>
          )}
          {activeView === "metrics" && (
            <motion.div
              key="metrics"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <MetricsDashboardView playheadMin={playheadMin} />
            </motion.div>
          )}
          {activeView === "before-after" && (
            <motion.div
              key="before-after"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <BeforeAfterView playheadMin={playheadMin} />
            </motion.div>
          )}
          {activeView === "terminal" && (
            <motion.div
              key="terminal"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <TerminalReplayView playheadMin={playheadMin} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}

// =============================================================================
// VIEW: Timeline (event list)
// =============================================================================

function SwarmTimelineView({
  activeEventId,
  playheadMin,
  onEventClick,
  agentForId,
}: {
  activeEventId: number | null;
  playheadMin: number;
  onEventClick: (id: number) => void;
  agentForId: (id: string) => SwarmAgent | undefined;
}) {
  return (
    <div className="space-y-3">
      {TIMELINE_EVENTS.map((evt, i) => {
        const reached = evt.minuteOffset <= playheadMin;
        const isActive = activeEventId === evt.id;
        const styles = EVENT_KIND_STYLES[evt.kind];
        return (
          <motion.div
            key={evt.id}
            initial={{ opacity: 0, x: -16 }}
            animate={{
              opacity: reached ? 1 : 0.35,
              x: 0,
            }}
            transition={{
              type: "spring",
              stiffness: 200,
              damping: 25,
              delay: i * 0.04,
            }}
          >
            <button
              onClick={() => onEventClick(evt.id)}
              className={`w-full text-left rounded-xl border p-4 transition-all duration-200 ${
                isActive
                  ? `bg-gradient-to-br ${styles.gradient} border-white/[0.15] ring-1 ${styles.ring}`
                  : "border-white/[0.06] bg-white/[0.01] hover:border-white/[0.12] hover:bg-white/[0.03]"
              }`}
            >
              <div className="flex items-start gap-3">
                {/* Time + icon column */}
                <div className="flex flex-col items-center gap-1 pt-0.5">
                  <div className={`flex h-8 w-8 items-center justify-center rounded-lg ${
                    reached ? "bg-primary/20 text-primary" : "bg-white/[0.05] text-white/30"
                  }`}>
                    {evt.icon}
                  </div>
                  <span className="text-[10px] font-mono text-white/30">{evt.time}</span>
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <h5 className={`font-semibold text-sm ${reached ? "text-white" : "text-white/40"}`}>
                      {evt.title}
                    </h5>
                    <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-medium ${
                      reached ? "bg-white/10 text-white/60" : "bg-white/[0.03] text-white/20"
                    }`}>
                      {evt.kind}
                    </span>
                  </div>
                  <p className={`text-xs leading-relaxed ${reached ? "text-white/60" : "text-white/25"}`}>
                    {evt.description}
                  </p>

                  {/* Agent pills */}
                  {evt.agentIds.length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-2">
                      {evt.agentIds.slice(0, 5).map((aid) => {
                        const ag = agentForId(aid);
                        if (!ag) return null;
                        return (
                          <span
                            key={aid}
                            className={`text-[9px] px-1.5 py-0.5 rounded-full border ${ag.borderColor} ${ag.bgColor} ${ag.textColor}`}
                          >
                            {ag.name}
                          </span>
                        );
                      })}
                      {evt.agentIds.length > 5 && (
                        <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-white/[0.04] text-white/30">
                          +{evt.agentIds.length - 5} more
                        </span>
                      )}
                    </div>
                  )}

                  {/* Expanded detail */}
                  <AnimatePresence>
                    {isActive && (
                      <motion.div
                        initial={{ opacity: 0, height: 0 }}
                        animate={{ opacity: 1, height: "auto" }}
                        exit={{ opacity: 0, height: 0 }}
                        transition={{ type: "spring", stiffness: 200, damping: 25 }}
                        className="overflow-hidden"
                      >
                        <div className="mt-3 pt-3 border-t border-white/[0.06] space-y-3">
                          <p className="text-xs text-white/50 leading-relaxed">{evt.detail}</p>

                          {/* Files touched */}
                          <div>
                            <span className="text-[10px] text-white/30 uppercase tracking-wider font-semibold">Files</span>
                            <div className="flex flex-wrap gap-1 mt-1">
                              {evt.files.map((f) => (
                                <span key={f} className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-black/30 text-white/40 border border-white/[0.06]">
                                  {f}
                                </span>
                              ))}
                            </div>
                          </div>

                          {/* Command */}
                          <div className="rounded-lg bg-black/30 border border-white/[0.06] px-3 py-2 font-mono text-[11px] text-white/60 overflow-x-auto">
                            <span className="text-emerald-400/70 select-none">$ </span>
                            {evt.command}
                          </div>
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>

                {/* Expand indicator */}
                <div className="pt-1 text-white/20">
                  {isActive ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                </div>
              </div>
            </button>
          </motion.div>
        );
      })}
    </div>
  );
}

// =============================================================================
// VIEW: Gantt Chart
// =============================================================================

function GanttChartView({
  playheadMin,
  agentForId,
}: {
  playheadMin: number;
  agentForId: (id: string) => SwarmAgent | undefined;
}) {
  const totalMin = 300;
  const [hoveredSegment, setHoveredSegment] = useState<{ agentId: string; segIdx: number } | null>(null);

  // Count active agents at current playhead
  const activeAgentCount = GANTT_DATA.filter((row) =>
    row.segments.some((s) => s.startMin <= playheadMin && s.endMin > playheadMin)
  ).length;

  // Count completed segments
  const completedSegmentCount = GANTT_DATA.reduce(
    (sum, row) => sum + row.segments.filter((s) => s.endMin <= playheadMin).length,
    0
  );

  const totalSegmentCount = GANTT_DATA.reduce((sum, row) => sum + row.segments.length, 0);

  return (
    <div className="space-y-3">
      <p className="text-xs text-white/40 mb-2">
        Animated Gantt view showing overlapping agent activities across the 5-hour session. Hover segments for details.
      </p>

      {/* Status summary bar */}
      <div className="flex gap-4 mb-3">
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
          <span className="text-[10px] text-white/40">
            <span className="text-emerald-400 font-semibold">{activeAgentCount}</span> agents active
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-full bg-primary" />
          <span className="text-[10px] text-white/40">
            <span className="text-primary font-semibold">{completedSegmentCount}</span>/{totalSegmentCount} tasks done
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <Clock className="h-2.5 w-2.5 text-white/30" />
          <span className="text-[10px] font-mono text-white/30">
            T+{Math.floor(playheadMin / 60)}h{String(playheadMin % 60).padStart(2, "0")}m
          </span>
        </div>
      </div>

      <div className="overflow-x-auto">
        <div className="min-w-[600px]">
          {/* Time axis */}
          <div className="flex items-center mb-2 pl-24">
            <div className="flex-1 flex justify-between">
              {["0:00", "0:30", "1:00", "1:30", "2:00", "2:30", "3:00", "3:30", "4:00", "4:30", "5:00"].map((t) => (
                <span key={t} className="text-[8px] font-mono text-white/20">{t}</span>
              ))}
            </div>
          </div>

          {/* Agent rows */}
          {GANTT_DATA.map((row, rowIdx) => {
            const ag = agentForId(row.agentId);
            if (!ag) return null;
            const isRowActive = row.segments.some(
              (s) => s.startMin <= playheadMin && s.endMin > playheadMin
            );
            return (
              <motion.div
                key={row.agentId}
                initial={{ opacity: 0, x: -12 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25, delay: rowIdx * 0.03 }}
                className="flex items-center gap-2 mb-1.5"
              >
                {/* Agent name */}
                <div className="w-22 shrink-0 flex items-center gap-1.5">
                  <div className={`h-2 w-2 rounded-full ${ag.color} ${isRowActive ? "animate-pulse" : ""}`} />
                  <span className={`text-[10px] font-medium ${isRowActive ? ag.textColor : "text-white/30"} truncate transition-colors`}>
                    {ag.name}
                  </span>
                </div>

                {/* Gantt bar area */}
                <div className="flex-1 relative h-6 rounded bg-white/[0.02] border border-white/[0.04]">
                  {/* Playhead line */}
                  <motion.div
                    className="absolute top-0 bottom-0 w-px bg-primary/50 z-10"
                    animate={{ left: `${(playheadMin / totalMin) * 100}%` }}
                    transition={{ type: "spring", stiffness: 300, damping: 30 }}
                  />

                  {/* Segments */}
                  {row.segments.map((seg, segIdx) => {
                    const left = (seg.startMin / totalMin) * 100;
                    const width = ((seg.endMin - seg.startMin) / totalMin) * 100;
                    const reached = seg.startMin <= playheadMin;
                    const segProgress = reached
                      ? Math.min(1, (playheadMin - seg.startMin) / (seg.endMin - seg.startMin))
                      : 0;
                    const isHovered = hoveredSegment?.agentId === row.agentId && hoveredSegment?.segIdx === segIdx;
                    const isComplete = seg.endMin <= playheadMin;
                    return (
                      <motion.div
                        key={segIdx}
                        initial={{ scaleX: 0 }}
                        animate={{ scaleX: 1 }}
                        transition={{ type: "spring", stiffness: 150, damping: 20, delay: 0.1 + segIdx * 0.05 }}
                        style={{ left: `${left}%`, width: `${width}%`, originX: 0 }}
                        className={`absolute top-0.5 bottom-0.5 rounded-sm overflow-hidden group cursor-pointer transition-all duration-200 ${
                          isHovered ? "z-20 ring-1 ring-white/30" : ""
                        }`}
                        onMouseEnter={() => setHoveredSegment({ agentId: row.agentId, segIdx })}
                        onMouseLeave={() => setHoveredSegment(null)}
                      >
                        {/* Background */}
                        <div className={`absolute inset-0 ${ag.bgColor} border ${ag.borderColor} rounded-sm`} />

                        {/* Fill progress */}
                        <motion.div
                          className={`absolute inset-y-0 left-0 ${ag.color} ${isComplete ? "opacity-40" : "opacity-25"} rounded-sm`}
                          animate={{ width: `${segProgress * 100}%` }}
                          transition={{ type: "spring", stiffness: 300, damping: 30 }}
                        />

                        {/* Completion checkmark */}
                        {isComplete && (
                          <div className="absolute right-0.5 top-1/2 -translate-y-1/2">
                            <CheckCircle className="h-2.5 w-2.5 text-emerald-400/60" />
                          </div>
                        )}

                        {/* Label */}
                        <span className="relative z-[1] px-1 text-[7px] font-medium text-white/50 whitespace-nowrap leading-5 group-hover:text-white/80 transition-colors">
                          {width > 8 ? seg.label : ""}
                        </span>

                        {/* Hover tooltip */}
                        {isHovered && (
                          <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 z-30 pointer-events-none">
                            <div className="rounded-lg bg-black/90 border border-white/[0.15] px-2.5 py-1.5 shadow-xl whitespace-nowrap">
                              <div className={`text-[9px] font-semibold ${ag.textColor}`}>{ag.name}</div>
                              <div className="text-[9px] text-white/70 font-medium">{seg.label}</div>
                              <div className="text-[8px] text-white/30 font-mono mt-0.5">
                                {Math.floor(seg.startMin / 60)}:{String(seg.startMin % 60).padStart(2, "0")} - {Math.floor(seg.endMin / 60)}:{String(seg.endMin % 60).padStart(2, "0")}
                                {" "}({seg.endMin - seg.startMin}m)
                              </div>
                              <div className="text-[8px] text-white/25 mt-0.5">
                                {isComplete ? "Complete" : reached ? `${Math.round(segProgress * 100)}% done` : "Pending"}
                              </div>
                            </div>
                          </div>
                        )}
                      </motion.div>
                    );
                  })}
                </div>
              </motion.div>
            );
          })}

          {/* Legend */}
          <div className="flex flex-wrap gap-3 mt-4 pl-24">
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-6 rounded-sm bg-gradient-to-r from-emerald-500/30 to-emerald-500/10 border border-emerald-500/20" />
              <span className="text-[8px] text-white/25">Development</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-6 rounded-sm bg-gradient-to-r from-rose-500/30 to-rose-500/10 border border-rose-500/20" />
              <span className="text-[8px] text-white/25">Conflict</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-6 rounded-sm bg-gradient-to-r from-sky-500/30 to-sky-500/10 border border-sky-500/20" />
              <span className="text-[8px] text-white/25">Integration</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-6 rounded-sm bg-gradient-to-r from-teal-500/30 to-teal-500/10 border border-teal-500/20" />
              <span className="text-[8px] text-white/25">Testing</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-6 rounded-sm bg-gradient-to-r from-orange-500/30 to-orange-500/10 border border-orange-500/20" />
              <span className="text-[8px] text-white/25">Review</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// VIEW: Agent Activity Cards
// =============================================================================

function AgentActivityView({ playheadMin }: { playheadMin: number }) {
  const [expandedAgent, setExpandedAgent] = useState<string | null>(null);
  const progress = Math.min(playheadMin / 300, 1);

  const platformGroups = [
    { label: "Claude Code (Opus 4.5)", platform: "cc" as const, agents: SWARM_AGENTS.filter((a) => a.platform === "cc") },
    { label: "Codex CLI (5.1 Max)", platform: "codex" as const, agents: SWARM_AGENTS.filter((a) => a.platform === "codex") },
    { label: "Antigravity CLI (Review)", platform: "gemini" as const, agents: SWARM_AGENTS.filter((a) => a.platform === "gemini") },
  ];

  const handleAgentToggle = useCallback((agentId: string) => {
    setTimeout(() => setExpandedAgent((prev) => (prev === agentId ? null : agentId)), 0);
  }, []);

  return (
    <div className="space-y-5">
      {/* Platform summary bar */}
      <div className="grid gap-2 sm:grid-cols-3">
        {platformGroups.map((group) => {
          const totalBeads = AGENT_ACCOMPLISHMENTS
            .filter((a) => SWARM_AGENTS.find((s) => s.id === a.agentId)?.platform === group.platform)
            .reduce((sum, a) => sum + a.beadsClosed, 0);
          const totalLines = AGENT_ACCOMPLISHMENTS
            .filter((a) => SWARM_AGENTS.find((s) => s.id === a.agentId)?.platform === group.platform)
            .reduce((sum, a) => sum + a.linesWritten, 0);
          return (
            <motion.div
              key={group.label}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 text-center"
            >
              <span className="text-[10px] text-white/40 font-semibold uppercase tracking-wider">{group.label}</span>
              <div className="flex justify-center gap-4 mt-2">
                <div>
                  <div className="text-sm font-bold text-white">{Math.round(progress * totalBeads)}</div>
                  <div className="text-[8px] text-white/25">beads</div>
                </div>
                <div>
                  <div className="text-sm font-bold text-white">{Math.round(progress * totalLines).toLocaleString()}</div>
                  <div className="text-[8px] text-white/25">lines</div>
                </div>
                <div>
                  <div className="text-sm font-bold text-white">{group.agents.length}</div>
                  <div className="text-[8px] text-white/25">agents</div>
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>

      {/* Agent cards by platform */}
      {platformGroups.map((group) => (
        <div key={group.label}>
          <h5 className="text-xs font-semibold text-white/50 uppercase tracking-wider mb-3 flex items-center gap-2">
            <Bot className="h-3.5 w-3.5" />
            {group.label}
          </h5>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {group.agents.map((ag, idx) => {
              const ganttRow = GANTT_DATA.find((g) => g.agentId === ag.id);
              const accomplishment = AGENT_ACCOMPLISHMENTS.find((a) => a.agentId === ag.id);
              const activeSegments = ganttRow?.segments.filter(
                (s) => s.startMin <= playheadMin && s.endMin > playheadMin
              ) ?? [];
              const completedSegments = ganttRow?.segments.filter(
                (s) => s.endMin <= playheadMin
              ) ?? [];
              const isActive = activeSegments.length > 0;
              const isExpanded = expandedAgent === ag.id;

              return (
                <motion.div
                  key={ag.id}
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25, delay: idx * 0.04 }}
                  className={`rounded-xl border p-3 transition-all duration-300 cursor-pointer ${
                    isActive
                      ? `${ag.borderColor} ${ag.bgColor}`
                      : isExpanded
                        ? `${ag.borderColor} bg-white/[0.03]`
                        : "border-white/[0.06] bg-white/[0.01] hover:border-white/[0.1]"
                  }`}
                  onClick={() => handleAgentToggle(ag.id)}
                >
                  <div className="flex items-center gap-2 mb-2">
                    <div className={`h-2.5 w-2.5 rounded-full ${ag.color} ${isActive ? "animate-pulse" : ""}`} />
                    <span className={`text-xs font-semibold ${ag.textColor}`}>{ag.name}</span>
                    {isActive && (
                      <span className="text-[8px] px-1.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-medium ml-auto">
                        ACTIVE
                      </span>
                    )}
                    {!isActive && playheadMin > 0 && (
                      <span className="text-[8px] px-1.5 py-0.5 rounded-full bg-white/[0.05] text-white/25 font-medium ml-auto">
                        IDLE
                      </span>
                    )}
                    <span className="text-white/15">
                      {isExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                    </span>
                  </div>

                  {/* Current activity */}
                  {activeSegments.map((s, i) => (
                    <p key={i} className="text-[10px] text-white/50">
                      Working on: <span className="text-white/70 font-medium">{s.label}</span>
                    </p>
                  ))}
                  {completedSegments.length > 0 && (
                    <p className="text-[10px] text-white/30 mt-1">
                      Completed: {completedSegments.length} task{completedSegments.length !== 1 ? "s" : ""}
                    </p>
                  )}

                  {/* Quick stats */}
                  {accomplishment && (
                    <div className="flex gap-3 mt-2">
                      <span className="text-[9px] text-white/20">
                        {Math.round(progress * accomplishment.beadsClosed)} beads
                      </span>
                      <span className="text-[9px] text-white/20">
                        {Math.round(progress * accomplishment.linesWritten).toLocaleString()} lines
                      </span>
                      <span className="text-[9px] text-white/20">
                        {Math.round(progress * accomplishment.filesCreated)} files
                      </span>
                    </div>
                  )}

                  {/* Expanded detail */}
                  <AnimatePresence>
                    {isExpanded && accomplishment && (
                      <motion.div
                        initial={{ opacity: 0, height: 0 }}
                        animate={{ opacity: 1, height: "auto" }}
                        exit={{ opacity: 0, height: 0 }}
                        transition={{ type: "spring", stiffness: 200, damping: 25 }}
                        className="overflow-hidden"
                      >
                        <div className="mt-3 pt-3 border-t border-white/[0.06]">
                          <span className="text-[9px] text-white/30 uppercase tracking-wider font-semibold">Key Contributions</span>
                          <ul className="mt-1.5 space-y-1">
                            {accomplishment.keyContributions.map((c, ci) => (
                              <motion.li
                                key={ci}
                                initial={{ opacity: 0, x: -8 }}
                                animate={{ opacity: 1, x: 0 }}
                                transition={{ type: "spring", stiffness: 200, damping: 25, delay: ci * 0.04 }}
                                className="flex items-start gap-1.5 text-[10px] text-white/40"
                              >
                                <CheckCircle className="h-2.5 w-2.5 text-emerald-400/60 mt-0.5 shrink-0" />
                                {c}
                              </motion.li>
                            ))}
                          </ul>

                          {/* Agent stats bar */}
                          <div className="grid grid-cols-3 gap-2 mt-3">
                            <div className="text-center p-1.5 rounded-lg bg-black/20">
                              <div className={`text-xs font-bold ${ag.textColor}`}>
                                {Math.round(progress * accomplishment.beadsClosed)}
                              </div>
                              <div className="text-[7px] text-white/20">Beads</div>
                            </div>
                            <div className="text-center p-1.5 rounded-lg bg-black/20">
                              <div className={`text-xs font-bold ${ag.textColor}`}>
                                {Math.round(progress * accomplishment.linesWritten).toLocaleString()}
                              </div>
                              <div className="text-[7px] text-white/20">Lines</div>
                            </div>
                            <div className="text-center p-1.5 rounded-lg bg-black/20">
                              <div className={`text-xs font-bold ${ag.textColor}`}>
                                {Math.round(progress * accomplishment.filesCreated)}
                              </div>
                              <div className="text-[7px] text-white/20">Files</div>
                            </div>
                          </div>
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </motion.div>
              );
            })}
          </div>
        </div>
      ))}

      {/* Leaderboard */}
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
        <h5 className="text-xs font-semibold text-white/50 uppercase tracking-wider mb-3 flex items-center gap-2">
          <Trophy className="h-3.5 w-3.5 text-amber-400" />
          Agent Leaderboard (by beads closed)
        </h5>
        <div className="space-y-1.5">
          {[...AGENT_ACCOMPLISHMENTS]
            .sort((a, b) => b.beadsClosed - a.beadsClosed)
            .slice(0, 6)
            .map((acc, i) => {
              const ag = SWARM_AGENTS.find((a) => a.id === acc.agentId);
              if (!ag) return null;
              const barWidth = (acc.beadsClosed / 72) * 100;
              return (
                <motion.div
                  key={acc.agentId}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.05 }}
                  className="flex items-center gap-2"
                >
                  <span className="text-[9px] text-white/20 w-4 text-right font-mono">{i + 1}</span>
                  <div className={`h-2 w-2 rounded-full ${ag.color}`} />
                  <span className={`text-[10px] font-medium ${ag.textColor} w-20 truncate`}>{ag.name}</span>
                  <div className="flex-1 h-3 rounded-full bg-white/[0.04] overflow-hidden">
                    <motion.div
                      className={`h-full rounded-full ${ag.color} opacity-40`}
                      animate={{ width: `${progress * barWidth}%` }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    />
                  </div>
                  <span className="text-[9px] font-mono text-white/30 w-8 text-right">
                    {Math.round(progress * acc.beadsClosed)}
                  </span>
                </motion.div>
              );
            })}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// VIEW: Conflict Resolution Replay
// =============================================================================

function ConflictResolutionView({ playheadMin }: { playheadMin: number }) {
  const conflictReached = playheadMin >= 75;
  const resolutionReached = playheadMin >= 80;
  const resolvedReached = playheadMin >= 85;

  const steps = [
    {
      time: "1:15",
      label: "Conflict Detected",
      reached: conflictReached,
      icon: <AlertTriangle className="h-4 w-4" />,
      color: "text-rose-400",
      borderColor: "border-rose-500/30",
      bgColor: "bg-rose-500/10",
      content: (
        <div className="space-y-2">
          <p className="text-xs text-white/60">
            GmiReview-1 detects that both <span className="text-blue-400 font-medium">BlueLake</span> and{" "}
            <span className="text-rose-400 font-medium">RedFox</span> have modified <code className="text-[10px] bg-black/30 px-1 rounded">src/types/index.ts</code>.
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            <div className="rounded-lg bg-blue-500/5 border border-blue-500/20 p-2">
              <span className="text-[9px] text-blue-400 font-semibold">BlueLake&apos;s changes:</span>
              <pre className="text-[9px] text-white/40 mt-1 font-mono">+ confidenceDecay: number;{"\n"}+ halfLifeDays: number;{"\n"}+ harmfulWeight: number;</pre>
            </div>
            <div className="rounded-lg bg-rose-500/5 border border-rose-500/20 p-2">
              <span className="text-[9px] text-rose-400 font-semibold">RedFox&apos;s changes:</span>
              <pre className="text-[9px] text-white/40 mt-1 font-mono">+ outputFormat: &quot;json&quot; | &quot;table&quot;;{"\n"}+ verboseMode: boolean;{"\n"}+ colorOutput: boolean;</pre>
            </div>
          </div>
        </div>
      ),
    },
    {
      time: "1:17",
      label: "Agent Mail Coordination",
      reached: resolutionReached,
      icon: <Mail className="h-4 w-4" />,
      color: "text-amber-400",
      borderColor: "border-amber-500/30",
      bgColor: "bg-amber-500/10",
      content: (
        <div className="space-y-2">
          <div className="rounded-lg bg-black/30 border border-white/[0.06] p-3">
            <div className="flex items-center gap-2 mb-2">
              <MessageSquare className="h-3 w-3 text-orange-400" />
              <span className="text-[10px] font-semibold text-orange-400">GmiReview-1 &rarr; RedFox</span>
            </div>
            <p className="text-[10px] text-white/50 font-mono">
              Subject: Hold on types changes{"\n"}
              Body: BlueLake is merging decay fields into BulletSchema.{"\n"}
              Please hold your CLI output types until the merge is done.{"\n"}
              Will notify when clear.
            </p>
          </div>
          <div className="rounded-lg bg-black/30 border border-white/[0.06] p-3 mt-2">
            <div className="flex items-center gap-2 mb-2">
              <MessageSquare className="h-3 w-3 text-blue-400" />
              <span className="text-[10px] font-semibold text-blue-400">BlueLake &rarr; GmiReview-1</span>
            </div>
            <p className="text-[10px] text-white/50 font-mono">
              Subject: Types merge complete{"\n"}
              Body: Decay fields merged cleanly into BulletSchema.{"\n"}
              RedFox can rebase and add output types now.
            </p>
          </div>
        </div>
      ),
    },
    {
      time: "1:20",
      label: "Conflict Resolved",
      reached: resolvedReached,
      icon: <CheckCircle className="h-4 w-4" />,
      color: "text-emerald-400",
      borderColor: "border-emerald-500/30",
      bgColor: "bg-emerald-500/10",
      content: (
        <div className="space-y-2">
          <p className="text-xs text-white/60">
            RedFox rebases onto BlueLake&apos;s merge. Both sets of fields now coexist cleanly.
            Total resolution time: <span className="text-emerald-400 font-semibold">5 minutes</span>,
            zero human intervention.
          </p>
          <div className="rounded-lg bg-emerald-500/5 border border-emerald-500/20 p-2">
            <span className="text-[9px] text-emerald-400 font-semibold">Final merged schema:</span>
            <pre className="text-[9px] text-white/40 mt-1 font-mono">
{`interface BulletSchema {
  // ... existing fields
  confidenceDecay: number;   // BlueLake
  halfLifeDays: number;      // BlueLake
  harmfulWeight: number;     // BlueLake
  outputFormat: OutputFmt;   // RedFox
  verboseMode: boolean;      // RedFox
  colorOutput: boolean;      // RedFox
}`}
            </pre>
          </div>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-3">
      <p className="text-xs text-white/40 mb-4">
        Watch how Agent Mail resolved a real file conflict between two agents without any human intervention.
      </p>
      {steps.map((step, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -12 }}
          animate={{ opacity: step.reached ? 1 : 0.25, x: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.1 }}
          className={`rounded-xl border p-4 transition-all duration-300 ${
            step.reached ? `${step.borderColor} ${step.bgColor}` : "border-white/[0.04] bg-white/[0.01]"
          }`}
        >
          <div className="flex items-center gap-3 mb-2">
            <div className={`flex h-7 w-7 items-center justify-center rounded-lg ${step.reached ? step.bgColor : "bg-white/[0.03]"} ${step.reached ? step.color : "text-white/20"}`}>
              {step.icon}
            </div>
            <div>
              <h5 className={`text-sm font-semibold ${step.reached ? "text-white" : "text-white/30"}`}>
                {step.label}
              </h5>
              <span className="text-[10px] font-mono text-white/30">{step.time}</span>
            </div>
            {step.reached && i === steps.length - 1 && (
              <span className="ml-auto text-[9px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-semibold">
                RESOLVED
              </span>
            )}
          </div>
          {step.reached && step.content}
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// VIEW: Metrics Dashboard
// =============================================================================

function MetricsDashboardView({ playheadMin }: { playheadMin: number }) {
  const progress = Math.min(playheadMin / 300, 1);

  const interpolatedMetrics = FINAL_METRICS.map((m) => {
    const numericVal = parseFloat(m.value.replace(/[^0-9.]/g, ""));
    if (m.label === "Wall Clock") {
      const hours = Math.floor((progress * 5 * 60) / 60);
      const mins = Math.round((progress * 5 * 60) % 60);
      return { ...m, liveValue: `${hours}h ${mins}m` };
    }
    if (m.label === "Beads Closed") {
      return { ...m, liveValue: `${Math.round(progress * 590)} / 693` };
    }
    return { ...m, liveValue: isNaN(numericVal) ? m.value : String(Math.round(progress * numericVal)) };
  });

  return (
    <div className="space-y-4">
      <p className="text-xs text-white/40 mb-2">
        Live metrics updating as the replay progresses through the 5-hour session.
      </p>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {interpolatedMetrics.map((m, i) => (
          <motion.div
            key={m.label}
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.05 }}
            className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 text-center"
          >
            <div className={`flex items-center justify-center gap-1.5 mb-2 ${m.color}`}>
              {m.icon}
              <span className="text-[10px] font-semibold uppercase tracking-wider">{m.label}</span>
            </div>
            <motion.div
              key={m.liveValue}
              initial={{ opacity: 0.5, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ type: "spring", stiffness: 300, damping: 25 }}
              className="text-2xl font-bold text-white"
            >
              {m.liveValue}
            </motion.div>
            <div className="text-[10px] text-white/25 mt-1">
              Final: {m.value}
            </div>
          </motion.div>
        ))}
      </div>

      {/* Completion progress */}
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs font-semibold text-white/60">Overall Completion</span>
          <span className="text-xs font-mono text-primary">{Math.round(progress * 85)}%</span>
        </div>
        <div className="h-3 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="h-full rounded-full bg-gradient-to-r from-blue-500 via-violet-500 to-emerald-500"
            animate={{ width: `${progress * 85}%` }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
          />
        </div>
        <div className="flex justify-between mt-2">
          <span className="text-[9px] text-white/20">0%</span>
          <span className="text-[9px] text-white/20">85% target</span>
          <span className="text-[9px] text-white/20">100%</span>
        </div>
      </div>

      {/* Throughput chart */}
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
        <h5 className="text-xs font-semibold text-white/60 mb-3 flex items-center gap-2">
          <Hash className="h-3.5 w-3.5 text-white/40" />
          Commits Per Hour
        </h5>
        <div className="flex items-end gap-1 h-20">
          {[18, 34, 52, 68, 62, 48].map((val, i) => {
            const hourReached = i * 60 <= playheadMin;
            const scaledHeight = hourReached ? (val / 68) * 100 : 5;
            return (
              <div key={i} className="flex-1 flex flex-col items-center gap-1">
                <motion.div
                  className={`w-full rounded-t ${hourReached ? "bg-gradient-to-t from-violet-500 to-blue-400" : "bg-white/[0.04]"}`}
                  animate={{ height: `${scaledHeight}%` }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                />
                <span className="text-[7px] text-white/20 font-mono">{i}h</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// VIEW: Before / After Comparison
// =============================================================================

function BeforeAfterView({ playheadMin }: { playheadMin: number }) {
  const progress = Math.min(playheadMin / 300, 1);

  return (
    <div className="space-y-4">
      <p className="text-xs text-white/40 mb-2">
        Project state at the start versus end of the 5-hour swarm session.
      </p>

      <div className="grid gap-3 sm:grid-cols-2">
        {/* Before */}
        <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
          <h5 className="text-xs font-semibold text-white/60 uppercase tracking-wider mb-3 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-white/20" />
            Before (0h)
          </h5>
          <div className="space-y-2">
            {COMPARISONS.map((c) => (
              <div key={c.label} className="flex justify-between items-center py-1 border-b border-white/[0.04] last:border-0">
                <span className="text-[11px] text-white/40">{c.label}</span>
                <span className="text-[11px] font-mono text-white/20">{c.before}</span>
              </div>
            ))}
          </div>
        </div>

        {/* After */}
        <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4">
          <h5 className="text-xs font-semibold text-emerald-400 uppercase tracking-wider mb-3 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-emerald-400 animate-pulse" />
            After (5h)
          </h5>
          <div className="space-y-2">
            {COMPARISONS.map((c) => {
              const afterNum = parseFloat(c.after.replace(/[^0-9.]/g, ""));
              const displayVal = isNaN(afterNum)
                ? c.after
                : c.after.includes("/")
                  ? `${Math.round(progress * 590)} / 693`
                  : c.after.includes("%")
                    ? `${Math.round(progress * 78)}%`
                    : String(Math.round(progress * afterNum));
              return (
                <div key={c.label} className="flex justify-between items-center py-1 border-b border-emerald-500/10 last:border-0">
                  <span className="text-[11px] text-white/60">{c.label}</span>
                  <motion.span
                    key={displayVal}
                    initial={{ opacity: 0.5 }}
                    animate={{ opacity: 1 }}
                    className="text-[11px] font-mono text-emerald-400 font-semibold"
                  >
                    {displayVal}
                  </motion.span>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* Visual diff */}
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
        <h5 className="text-xs font-semibold text-white/60 mb-3">Project Structure Growth</h5>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <span className="text-[10px] text-white/30 uppercase tracking-wider">T=0h</span>
            <div className="mt-2 rounded-lg bg-black/30 border border-white/[0.06] p-3 font-mono text-[9px] text-white/30 leading-relaxed">
              <div>cass-memory/</div>
              <div className="ml-3">package.json</div>
              <div className="ml-3">PLAN.md</div>
              <div className="ml-3 text-white/15">(empty project)</div>
            </div>
          </div>
          <div>
            <span className="text-[10px] text-emerald-400/60 uppercase tracking-wider">T=5h</span>
            <div className="mt-2 rounded-lg bg-black/30 border border-emerald-500/10 p-3 font-mono text-[9px] text-emerald-400/60 leading-relaxed">
              <div>cass-memory/</div>
              <div className="ml-3 text-white/40">src/</div>
              <div className="ml-5 text-emerald-400/50">types/ cli/ storage/</div>
              <div className="ml-5 text-emerald-400/50">reflect/ playbook/</div>
              <div className="ml-5 text-emerald-400/50">mcp/ config/ llm/</div>
              <div className="ml-3 text-white/40">tests/</div>
              <div className="ml-5 text-teal-400/50">unit/ integration/</div>
              <div className="ml-3 text-white/40">dist/ docs/</div>
              <div className="ml-3 text-amber-400/50">67 source files</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// VIEW: Terminal Replay
// =============================================================================

function TerminalReplayView({ playheadMin }: { playheadMin: number }) {
  const visibleCommands = TERMINAL_COMMANDS.filter((c) => {
    const parts = c.time.split(":");
    const mins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    return mins <= playheadMin;
  });

  return (
    <div className="space-y-3">
      <p className="text-xs text-white/40 mb-2">
        Real-time terminal output showing the coordination commands used during the session.
      </p>

      <div className="rounded-xl border border-white/[0.08] bg-black/40 backdrop-blur-xl overflow-hidden">
        {/* Terminal header */}
        <div className="flex items-center gap-2 px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.02]">
          <div className="flex gap-1.5">
            <div className="h-2.5 w-2.5 rounded-full bg-rose-500/60" />
            <div className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
            <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
          </div>
          <span className="text-[10px] text-white/30 font-mono ml-2">cass-memory - agent swarm session</span>
        </div>

        {/* Command log */}
        <div className="p-4 max-h-[360px] overflow-y-auto space-y-2 font-mono text-[11px]">
          {visibleCommands.length === 0 && (
            <div className="text-white/20 text-center py-8">
              Press play or advance the timeline to see commands...
            </div>
          )}
          {visibleCommands.map((c, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ type: "spring", stiffness: 300, damping: 25 }}
            >
              <div className="flex items-start gap-2">
                <span className="text-white/15 shrink-0 w-10 text-right">{c.time}</span>
                <span className={`shrink-0 text-[9px] px-1.5 py-0.5 rounded ${
                  c.agent === "operator" ? "bg-primary/20 text-primary" :
                  c.agent === "BlueLake" ? "bg-blue-500/20 text-blue-400" :
                  c.agent === "RedFox" ? "bg-rose-500/20 text-rose-400" :
                  c.agent === "GreenCastle" ? "bg-emerald-500/20 text-emerald-400" :
                  c.agent === "SilverWind" ? "bg-slate-400/20 text-slate-300" :
                  c.agent === "GmiReview-1" ? "bg-orange-500/20 text-orange-400" :
                  c.agent === "CodBot-2" ? "bg-cyan-500/20 text-cyan-400" :
                  "bg-white/10 text-white/40"
                }`}>
                  {c.agent}
                </span>
              </div>
              <div className="ml-12 mt-0.5">
                {c.cmd.startsWith("#") ? (
                  <span className="text-amber-400/60">{c.cmd}</span>
                ) : (
                  <>
                    <span className="text-emerald-400/50 select-none">$ </span>
                    <span className="text-white/50">{c.cmd}</span>
                  </>
                )}
              </div>
            </motion.div>
          ))}
          {visibleCommands.length > 0 && (
            <div className="flex items-center gap-1 ml-12 mt-2">
              <motion.span
                animate={{ opacity: [0.2, 0.8, 0.2] }}
                transition={{ duration: 1.2, repeat: Infinity }}
                className="text-emerald-400/50"
              >
                _
              </motion.span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
