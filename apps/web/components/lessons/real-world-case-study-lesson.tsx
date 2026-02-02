"use client";

import { type ReactNode } from "react";
import { motion } from "@/components/motion";
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
            href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/PLAN_FOR_CASS_MEMORY_SYSTEM.md"
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
              href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/PLAN_FOR_CASS_MEMORY_SYSTEM.md"
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
ntm spawn cass-memory --cc=6 --cod=3 --gmi=2

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
the project to understand what we're doing. Use ultrathink."

# Step 2: Commit in logical groupings
cc "Based on your knowledge of the project, commit all
changed files now in a series of logically connected
groupings with super detailed commit messages for each
and then push.

Take your time to do it right. Don't edit the code at all.
Don't commit ephemeral files. Use ultrathink."`}
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
ntm spawn myproject --cc=3 --cod=2 --gmi=1

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
            <div className="font-semibold text-white text-sm">Gemini CLI</div>
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
