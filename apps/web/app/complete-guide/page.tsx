"use client";

import { useRef, useState, useCallback, useEffect } from "react";
import { motion, useReducedMotion, useInView, useMotionTemplate, useMotionValue } from "framer-motion";
import {
  BookOpen,
  Brain,
  Cog,
  Copy,
  Check,
  FileText,
  GitBranch,
  Layers,
  Lightbulb,
  Rocket,
  Search,
  Shield,
  Sparkles,
  Target,
  Terminal,
  Users,
  Wrench,
  Zap,
  Repeat,
  Eye,
  Bug,
  Palette,
  Ship,
  Boxes,
  GraduationCap,
  ScrollText,
  Download,
  ChevronDown,
} from "lucide-react";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import { copyTextToClipboard } from "@/lib/utils";
import { Jargon } from "@/components/jargon";
import {
  GuideSection,
  SubSection,
  P,
  BlockQuote,
  PromptBlock,
  DataTable,
  TipBox,
  ToolPill,
  IC,
  Hl,
  BulletList,
  NumberedList,
  Divider,
  FlywheelDiagram,
  TableOfContents,
  CodeBlock,
  PrincipleCard,
  OperatorCard,
} from "@/components/complete-guide/guide-components";

// =============================================================================
// TOC DATA
// =============================================================================
const TOC_ITEMS = [
  { id: "mental-model", label: "15-Minute Mental Model", number: "0" },
  { id: "flywheel", label: "The Compounding Loop", number: "1" },
  { id: "philosophy", label: "Why Planning Dominates", number: "2" },
  { id: "infrastructure", label: "Infrastructure Setup", number: "3" },
  { id: "pre-planning", label: "Pre-Planning", number: "4" },
  { id: "initial-plan", label: "Creating the Plan", number: "5" },
  { id: "synthesis", label: "Multi-Model Synthesis", number: "6" },
  { id: "refinement", label: "Iterative Refinement", number: "7" },
  { id: "plan-to-beads", label: "Plan to Beads", number: "8" },
  { id: "bead-polishing", label: "Bead Polishing", number: "9" },
  { id: "idea-wizard", label: "Idea-Wizard Pipeline", number: "10" },
  { id: "agents-md", label: "The AGENTS.md File", number: "11" },
  { id: "swarm", label: "Agent Swarm Execution", number: "12" },
  { id: "single-branch", label: "Single-Branch Git", number: "13" },
  { id: "code-review", label: "Code Review Loops", number: "14" },
  { id: "testing", label: "Testing & QA", number: "15" },
  { id: "ui-polish", label: "UI/UX Polish", number: "16" },
  { id: "bug-hunting", label: "Deep Bug Hunting", number: "17" },
  { id: "shipping", label: "Committing & Shipping", number: "18" },
  { id: "toolchain", label: "Complete Toolchain", number: "19" },
  { id: "principles", label: "Key Principles", number: "20" },
  { id: "operationalizing", label: "Operators & Gates", number: "21" },
  { id: "patterns", label: "Observed Patterns", number: "22" },
  { id: "practical", label: "Practical Considerations", number: "23" },
  { id: "prompt-library", label: "Prompt Library", number: "24" },
];

// =============================================================================
// HERO SECTION
// =============================================================================
function Hero() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const mouseX = useMotionValue(0);
  const mouseY = useMotionValue(0);

  function handleMouseMove({ currentTarget, clientX, clientY }: React.MouseEvent) {
    const { left, top } = currentTarget.getBoundingClientRect();
    mouseX.set(clientX - left);
    mouseY.set(clientY - top);
  }

  return (
    <section
      ref={ref}
      onMouseMove={handleMouseMove}
      className="group relative overflow-hidden pb-16 pt-24 md:pb-24 md:pt-32 border-b border-white/[0.05]"
    >
      {/* Background effects */}
      <div className="absolute inset-0 bg-grid-pattern opacity-[0.03]" />
      <motion.div
        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-500 group-hover:opacity-100"
        style={{
          background: useMotionTemplate`radial-gradient(600px circle at ${mouseX}px ${mouseY}px, oklch(0.75 0.18 195 / 0.15), transparent 80%)`,
        }}
      />
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,oklch(0.75_0.18_195/0.1),transparent_50%)]" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_bottom_right,oklch(0.7_0.15_280/0.1),transparent_50%)]" />
      </div>

      <div className="container relative mx-auto px-4 sm:px-6">
        <motion.div
          initial={reducedMotion ? {} : { opacity: 0, y: 30 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: reducedMotion ? 0 : 0.6 }}
          className="mx-auto max-w-4xl text-center relative z-10"
        >
          <div className="inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-4 py-1.5 text-xs font-medium text-primary mb-8 shadow-[0_0_20px_-5px_var(--color-primary)] backdrop-blur-md">
            <BookOpen className="h-3.5 w-3.5" />
            Complete Methodology Guide
          </div>

          <h1 className="heading-display text-5xl sm:text-6xl md:text-7xl text-white tracking-tighter drop-shadow-2xl">
            The Flywheel Approach to{" "}
            <span className="block mt-2 bg-gradient-to-br from-primary via-violet-300 to-cyan-300 bg-clip-text text-transparent pb-2">
              Planning & Beads Creation
            </span>
          </h1>

          <p className="mx-auto mt-8 max-w-2xl text-lg text-white/60 sm:text-xl leading-relaxed font-light">
            The definitive system for operating <Jargon term="ai-agents">AI agent</Jargon> swarms. Master the methodology to transition from human intent to flawless execution.
          </p>
        </motion.div>
        
        {/* Scroll down indicator */}
        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1, duration: 1 }}
          className="absolute bottom-4 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2 text-white/30"
        >
          <span className="text-[10px] uppercase tracking-[0.2em] font-medium">Scroll</span>
          <motion.div 
            animate={{ y: [0, 5, 0] }} 
            transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
            className="w-[1px] h-8 bg-gradient-to-b from-white/30 to-transparent"
          />
        </motion.div>
      </div>
    </section>
  );
}

// =============================================================================

// =============================================================================
// MAIN PAGE COMPONENT
// =============================================================================
export default function CompleteGuidePage() {
  return (
    <ErrorBoundary>
      <main className="min-h-screen overflow-x-hidden">
        <Hero />

        <div className="container mx-auto px-4 sm:px-6 relative">
          {/* Subtle ambient lighting for the body */}
          <div className="absolute top-1/4 left-0 w-full h-[1000px] bg-primary/5 blur-[120px] rounded-[100%] pointer-events-none -z-10 mix-blend-screen" />

          {/* Download CTA */}
          <div className="flex justify-center pt-10 pb-2">
            <a
              href="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/docs/THE_FLYWHEEL_APPROACH_TO_PLANNING_AND_BEADS_CREATION.md"
              target="_blank"
              rel="noopener noreferrer"
              className="group inline-flex items-center gap-3 rounded-2xl border border-primary/40 bg-primary/10 px-6 py-3.5 text-sm font-semibold text-primary shadow-[0_0_30px_-8px_var(--color-primary)] backdrop-blur-md transition-all duration-300 hover:bg-primary/20 hover:border-primary/60 hover:shadow-[0_0_40px_-5px_var(--color-primary)] hover:scale-[1.02] active:scale-[0.98]"
            >
              <Download className="h-5 w-5 transition-transform duration-300 group-hover:-translate-y-0.5" />
              <span>Download This Article as Markdown for Your Agent</span>
              <ChevronDown className="h-4 w-4 opacity-50 transition-transform duration-300 group-hover:translate-y-0.5" />
            </a>
          </div>

          <div className="flex justify-center gap-8 lg:gap-16 pt-12">
            {/* Main content */}
            <div className="flex-1 max-w-[65ch] pb-32 space-y-24 w-full shrink-0 relative z-10">
              {/* HOW TO READ THIS GUIDE */}
              <GuideSection
                id="how-to-read"
                number=""
                title="How to Read This Guide"
                icon={<BookOpen className="h-5 w-5" />}
              >
                <P>
                  This document serves two different audiences at once:
                </P>
                <BulletList
                  items={[
                    <><Hl>New to the Flywheel:</Hl> Read Section 0 first, then Sections 1&ndash;15 in order. That gives you the mental movie, the core workflow, and the operating loop before the later reference material.</>,
                    <><Hl>Already using the tools:</Hl> Jump to Sections 8&ndash;15 if you mainly need the plan-to-beads-to-swarm workflow, or Section 24 if you want the prompt library.</>,
                    <><Hl>Adapting an existing project:</Hl> Focus on Sections 4&ndash;9, 11&ndash;14, and 20. That is where the reasoning about plans, beads, <IC>AGENTS.md</IC>, and swarm execution is most explicit.</>,
                  ]}
                />
                <P>
                  This document is intentionally comprehensive and exhaustive. That can feel overwhelming on a first encounter. The important thing to understand is that there is also a gentler on-ramp: a smaller &ldquo;core loop&rdquo; that captures most of the value with just three tools&mdash;<ToolPill>Agent Mail</ToolPill> for multi-agent coordination, <ToolPill>br</ToolPill> for task management, and <ToolPill>bv</ToolPill> for graph-aware triage so agents keep choosing the highest-leverage next bead.
                </P>
                <P highlight>
                  This guide is about moving the hardest thinking into representations that still fit into model <Jargon term="context-window">context windows</Jargon>. That is the whole game.
                </P>
              </GuideSection>

              <Divider />

              {/* SECTION 0 */}
<GuideSection
  id="mental-model"
  number="0"
  title="If You&rsquo;re New: The 15-Minute Mental Model"
  icon={<GraduationCap className="h-5 w-5" />}
>
  <P>
    Most first-time readers get confused because three things are changing at
    once: the <Hl>artifact</Hl> you are working in, the{" "}
    <Hl>entity doing the thinking</Hl>, and the <Hl>source of truth</Hl> for
    what happens next.
  </P>

  <SubSection title="Hold These Three Sentences">
    <NumberedList
      items={[
        <>
          The <Hl>markdown plan</Hl> is where the big thinking happens.
        </>,
        <>
          The <Hl><Jargon term="beads">beads</Jargon></Hl> are how that thinking gets packaged for execution
          by many agents.
        </>,
        <>
          The <Hl>swarm</Hl> is not there to invent the system; it is there to
          execute, review, test, and harden a system that was mostly designed
          already.
        </>,
      ]}
    />
  </SubSection>

  <SubSection title="Mental Model Glossary">
    <DataTable
      headers={["Term", "Plain-English Meaning", "Why It Matters"]}
      rows={[
        [
          <strong key="t0">Markdown plan</strong>,
          "A huge design document where the whole project still fits in context",
          "Where architecture, workflows, tradeoffs, and intent get worked out",
        ],
        [
          <strong key="t1">Bead</strong>,
          <>
            A self-contained work unit in <IC>br</IC> with context,
            dependencies, and test obligations
          </>,
          "What agents actually execute",
        ],
        [
          <strong key="t2">Bead graph</strong>,
          "The full dependency structure across all beads",
          <>
            What lets <IC>bv</IC> compute the right next work
          </>,
        ],
        [
          <strong key="t3">Plan space</strong>,
          "The reasoning mode where you are still shaping the whole system",
          "The cheapest place to buy correctness",
        ],
        [
          <strong key="t4">Bead space</strong>,
          "The reasoning mode where you are shaping executable work packets",
          "Where planning becomes swarm-ready",
        ],
        [
          <strong key="t5">Code space</strong>,
          "The implementation and verification layer inside the codebase",
          "Where local execution happens",
        ],
        [
          <strong key="t6">AGENTS.md</strong>,
          <>The operating manual every agent must reload after <Jargon term="context-window">compaction</Jargon></>,
          "Keeps the swarm from forgetting how to behave",
        ],
        [
          <strong key="t7">Skill</strong>,
          "A reusable instruction bundle that teaches agents how to use a tool or workflow well",
          "How methods become repeatable instead of tacit lore",
        ],
        [
          <strong key="t8">Agent Mail</strong>,
          "The shared messaging and file-reservation layer",
          "How agents coordinate without stepping on each other",
        ],
        [
          <strong key="t9">bv</strong>,
          "The graph-theory routing tool for beads",
          "Keeps agents from choosing work randomly",
        ],
        [
          <strong key="t10">Compaction</strong>,
          "Context compression inside a long-running agent session",
          <>
            Why re-reading <IC>AGENTS.md</IC> is mandatory
          </>,
        ],
        [
          <strong key="t11">Fungible agents</strong>,
          "Generalist agents that can replace one another",
          "Makes crashes and amnesia survivable",
        ],
        [
          <strong key="t12">CASS / CM</strong>,
          "Session history and procedural memory",
          "How the workflow learns from itself over time",
        ],
        [
          <strong key="t13">rch</strong>,
          "The offloading layer for heavy builds and tests",
          "Prevents local CPU contention from degrading the swarm",
        ],
      ]}
    />
  </SubSection>

  <SubSection title="One Complete Flywheel Run (Atlas Notes Case Study)">
    <NumberedList
      items={[
        <>
          <Hl>Human intent arrives.</Hl> &ldquo;I want a simple internal app for
          uploading and searching team notes.&rdquo;
        </>,
        <>
          <Hl>The first markdown plan gets expanded.</Hl> Spells out workflows:
          upload, parse, tag, search, admin review. Captures constraints.
        </>,
        <>
          <Hl>Competing models improve the plan.</Hl> GPT Pro, Claude, Gemini
          produce alternatives. Best ideas are merged.
        </>,
        <>
          <Hl>The plan turns into beads:</Hl> <IC>br-101</IC>: upload+parse,{" "}
          <IC>br-102</IC>: search index, <IC>br-103</IC>: ingestion failure
          dashboard, <IC>br-104</IC>: auth, <IC>br-105</IC>: e2e coverage.
        </>,
        <>
          <Hl>Beads get polished</Hl> before implementation.
        </>,
        <>
          <Hl>The swarm launches.</Hl> Agents read <IC>AGENTS.md</IC>, register
          with <Jargon term="agent-mail">Agent Mail</Jargon>, claim beads, and use <IC>bv</IC>.
        </>,
        <>
          <Hl>The human tends flow,</Hl> not code details.
        </>,
        <>
          <Hl>Reviews, tests, UBS, and shipping happen.</Hl> CASS captures
          session history.
        </>,
      ]}
    />
  </SubSection>

  <SubSection title="The Representation Ladder">
    <P>
      The easiest way to stay oriented is to know what artifact is &ldquo;in
      charge&rdquo; at each moment and what question that stage is answering.
    </P>
    <DataTable
      headers={[
        "Stage",
        "Primary Artifact",
        "Source of Truth",
        "Main Question",
        "Exit Signal",
        "What Comes Next",
      ]}
      rows={[
        [
          "Intent shaping",
          "Human notes / prompts",
          "Human&rsquo;s goals",
          "What are we building?",
          "Workflows explicit",
          "Markdown planning",
        ],
        [
          "Planning",
          "Markdown plan",
          "Plan document",
          "What should the system be?",
          "Plan comprehensive enough to translate",
          "Plan-to-beads",
        ],
        [
          "Translation",
          "Beads under construction",
          "Emerging bead graph",
          "How to convert design into work packets?",
          "Every plan element in beads",
          "Bead polishing",
        ],
        [
          "Execution prep",
          <>
            Polished bead graph + <IC>AGENTS.md</IC>
          </>,
          "Beads, dependencies, rules",
          "Can a fresh swarm execute without guessing?",
          "Beads self-contained and launch-ready",
          "Swarm launch",
        ],
        [
          "Swarm implementation",
          "Code + bead state + Agent Mail",
          "Current codebase + bead/thread state",
          "Is implementation progressing coherently?",
          "Reviews stop finding major issues",
          "Deep review and shipping",
        ],
        [
          "Hardening / shipping",
          "Tests, UBS results, commits",
          "Verified code + issue status",
          "Is it ready to land?",
          "Quality gates pass",
          "Memory / next cycle",
        ],
        [
          "Memory / improvement",
          "CASS sessions, CM rules",
          "Distilled lessons",
          "What should the next swarm inherit?",
          "Reusable artifacts updated",
          "Better next project",
        ],
      ]}
    />
  </SubSection>

  <SubSection title="Where the Rest of the Guide Zooms In">
    <DataTable
      headers={["If you want to understand\u2026", "Go to\u2026"]}
      rows={[
        [
          "Why planning dominates and why this is a flywheel",
          "Sections 1\u20132",
        ],
        ["How to bootstrap the environment", "Sections 3\u20134"],
        ["How the markdown planning loop works", "Sections 5\u20137"],
        [
          "How plans become beads and get polished",
          "Sections 8\u201310",
        ],
        [
          "How agents stay aligned during swarm execution",
          "Sections 11\u201315",
        ],
        [
          "How polish, deep review, and shipping work",
          "Sections 16\u201318",
        ],
        [
          "How tools, method contract, and prompts fit together",
          "Sections 19\u201324",
        ],
      ]}
    />
  </SubSection>

  <SubSection title="The Core Five Prompts">
    <DataTable
      headers={["Prompt Family", "What It Does", "Why It Matters"]}
      rows={[
        [
          <strong key="p0">Kickoff / marching orders</strong>,
          "Gets a fresh agent oriented, registered, and working",
          "Prevents passive agents and communication purgatory",
        ],
        [
          <strong key="p1">Plan to beads</strong>,
          "Converts the plan into executable work units",
          "Where planning becomes swarm-ready",
        ],
        [
          <strong key="p2">Bead polishing</strong>,
          "Expands and stress-tests the bead graph before coding",
          "Where a good project stops being fragile",
        ],
        [
          <strong key="p3">Self-review</strong>,
          "Forces the author to re-read its own code with fresh eyes",
          "Catches cheap bugs immediately",
        ],
        [
          <strong key="p4">Deep review</strong>,
          "Alternates cross-agent criticism with random exploration",
          "Catches bugs local review misses",
        ],
      ]}
    />
  </SubSection>
</GuideSection>

<Divider />

{/* SECTION 1 */}
<GuideSection
  id="flywheel"
  number="1"
  title="The Flywheel: A Compounding Loop"
  icon={<Repeat className="h-5 w-5" />}
>
  <P highlight>
    A compounding loop built around moving work through the right representation
    at the right time.
  </P>

  <FlywheelDiagram />

  <SubSection title="The Five Stages">
    <NumberedList
      items={[
        <>
          Human clarifies <Hl>goals, workflows, tradeoffs, and constraints</Hl>
        </>,
        <>
          Frontier models turn that into a coherent{" "}
          <Hl>markdown plan</Hl>
        </>,
        <>
          Plan converted into a <Hl>dependency-structured bead graph</Hl>
        </>,
        <>
          Fungible swarm executes beads using{" "}
          <Hl>Agent Mail + bv</Hl>
        </>,
        <>
          Reviews, tests, UBS, CASS, and memory{" "}
          <Hl>feed back into the next plan</Hl>
        </>,
      ]}
    />
  </SubSection>

  <SubSection title="Key Supporting Pieces">
    <BulletList
      items={[
        <>
          <Hl>Markdown plans</Hl> are the whole-system reasoning artifact
        </>,
        <>
          <ToolPill>br</ToolPill> beads are the executable task graph
        </>,
        <>
          <IC>AGENTS.md</IC> is the shared operating manual
        </>,
        <>
          <Hl>Agent Mail</Hl> is the coordination layer
        </>,
        <>
          <ToolPill>bv</ToolPill> is the graph-theoretic routing layer
        </>,
        <>
          <ToolPill>NTM</ToolPill> is the launch and lifecycle layer
        </>,
        <>
          <ToolPill>CASS</ToolPill> / <ToolPill>CM</ToolPill> /{" "}
          <ToolPill>UBS</ToolPill> are memory, pattern-extraction, and
          quality-feedback layers
        </>,
      ]}
    />
  </SubSection>

  <BlockQuote>
    &ldquo;More agents &rarr; more sessions &rarr; better memory &rarr; better
    coordination &rarr; safer speed &rarr; better output &rarr; more
    sessions.&rdquo;
  </BlockQuote>

  <SubSection title="Why It Compounds">
    <BulletList
      items={[
        <>
          <Hl>Planning quality compounds</Hl> &mdash; you reuse prompts,
          patterns, and reasoning structures that CASS proves worked.
        </>,
        <>
          <Hl>Execution quality compounds</Hl> &mdash; better beads make swarm
          behavior more deterministic.
        </>,
        <>
          <Hl>Tool quality compounds</Hl> &mdash; agents use the tools,
          complain about them, and then help improve them.
        </>,
        <>
          <Hl>Memory compounds</Hl> &mdash; the results of one swarm become
          training data for the next.
        </>,
      ]}
    />
  </SubSection>
</GuideSection>

<Divider />

{/* SECTION 2 */}
<GuideSection
  id="philosophy"
  number="2"
  title="Philosophy: Why Planning Dominates"
  icon={<Brain className="h-5 w-5" />}
>
  <TipBox variant="info">
    The central thesis:{" "}
    <strong>
      85%+ of your time, attention, and energy should go into planning
    </strong>
    , not implementation.
  </TipBox>

  <BlockQuote>
    &ldquo;The models are far smarter when reasoning about a plan that is very
    detailed and fleshed out but still trivially small enough to easily fit
    within their context window. This is really the key insight behind my
    obsessive focus on planning.&rdquo;
  </BlockQuote>

  <P>
    A markdown plan, even a 6,000-line one, is still vastly smaller than the
    codebase it describes. Planning is front-loaded because you are doing{" "}
    <Hl>global reasoning while global reasoning is still possible</Hl>.
  </P>

  <SubSection title="Human Leverage Is Front-Loaded">
    <BlockQuote>
      &ldquo;The planning is something I still do in a pretty manual way because
      I think it&rsquo;s where you have the biggest impact on the entire
      process. The plan creation is the most free form, creative, human part of
      the process.&rdquo;
    </BlockQuote>
    <P>
      The human injects intent, judgment, taste, product sense, and strategic
      direction. These are the inputs that no model can supply from the problem
      statement alone.
    </P>
  </SubSection>

  <SubSection title="Plan Space, Bead Space, and Code Space">
    <DataTable
      headers={["Space", "Primary Artifact", "What You Decide", "Why Here"]}
      rows={[
        [
          <strong key="s0">Plan space</strong>,
          "Large markdown plan",
          "Architecture, features, workflows, tradeoffs",
          "Whole system fits in context",
        ],
        [
          <strong key="s1">Bead space</strong>,
          <>
            <IC>br</IC> issues + dependencies
          </>,
          "Task boundaries, execution order, test obligations",
          "Agents need explicit, local work units",
        ],
        [
          <strong key="s2">Code space</strong>,
          "Source files + tests",
          "Actual implementation and verification",
          "Plan already constrained high-level decisions",
        ],
      ]}
    />
  </SubSection>

  <SubSection title="Why This Prevents Slop">
    <BlockQuote>
      &ldquo;This workflow is what prevents it from generating slop. I spend 85%
      of my time and energy in the planning phases.&rdquo;
    </BlockQuote>
    <P>
      Without front-loaded planning, agents improvise architecture from a narrow
      local window into the codebase. That is when you get placeholder
      abstractions, missing workflow details, and contradictory assumptions baked
      into the implementation.
    </P>
  </SubSection>

  <SubSection title="The Economic Argument">
    <P>
      Planning tokens are far fewer and cheaper than implementation tokens. Each
      planning round evaluates system-wide consequences, and each improvement
      gets amortized across every downstream bead.
    </P>
    <BlockQuote>
      &ldquo;The old woodworking maxim of &lsquo;Measure twice, cut once!&rsquo;
      is worth revising as &lsquo;Check your beads N times, implement once,&rsquo;
      where N is basically as many as you can stomach.&rdquo;
    </BlockQuote>
  </SubSection>

  <SubSection title="V1 Is Not Everything">
    <P>
      Once you have a functioning v1, adding new features follows the same
      process: create a detailed markdown plan, turn it into beads, and
      implement. The <Jargon term="flywheel">flywheel</Jargon> just spins again.
    </P>
    <TipBox variant="tip">
      Debates about architecture and approach belong in the planning stage so
      that agents can just execute the beads without re-litigating design
      decisions mid-implementation.
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

{/* SECTION 3 */}
<GuideSection
  id="infrastructure"
  number="3"
  title="Infrastructure: Setting Up the Environment"
  icon={<Terminal className="h-5 w-5" />}
>
  <P>
    ACFS is a &ldquo;Rails installer&rdquo; for <Jargon term="agentic">agentic</Jargon> engineering. A beginner
    with a credit card and a laptop can paste one{" "}
    <IC>curl | bash</IC> command and start vibe coding within minutes.
  </P>

  <SubSection title="ACFS: The One-Liner Bootstrapper">
    <NumberedList
      items={[
        <>
          Visit the wizard website at <IC>agent-flywheel.com</IC>
        </>,
        <>
          Follow the instructions to rent a <Jargon term="vps">VPS</Jargon>{" "}
          <span className="text-white/40">(~$40&ndash;56/month)</span>
        </>,
        <>
          Paste the one <IC>curl | bash</IC> command
        </>,
        <>
          Type <IC>onboard</IC> and learn the workflow interactively
        </>,
        <>Start vibe coding immediately</>,
      ]}
    />
    <TipBox variant="tip">
      The installer is <Jargon term="idempotent">idempotent</Jargon> and checkpointed &mdash; if your connection
      drops mid-install, re-running it picks up exactly where it left off.
    </TipBox>
  </SubSection>

  <SubSection title="VPS Environment">
    <DataTable
      headers={["Aspect", "Value"]}
      rows={[
        ["User", <IC key="v0">ubuntu</IC>],
        ["Shell", "zsh + oh-my-zsh + powerlevel10k"],
        ["Workspace", <IC key="v2">/data/projects</IC>],
        ["Sudo", "Passwordless (vibe mode)"],
        ["Tmux prefix", <IC key="v4">Ctrl-a</IC>],
      ]}
    />
  </SubSection>

  <SubSection title="Vibe Mode Aliases">
    <P>
      Three aliases ship by default that let agents run without permission
      interruptions:
    </P>
    <CodeBlock
      language="bash"
      code={`alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox'
alias gmi='gemini --yolo'`}
    />
  </SubSection>

  <SubSection title="Bootstrapping a New Project">
    <CodeBlock
      language="bash"
      code={`acfs newproj myproject --interactive
# Creates: .git/, .beads/, .claude/, AGENTS.md, .gitignore`}
    />
  </SubSection>
</GuideSection>

<Divider />

{/* SECTION 4 */}
<GuideSection
  id="pre-planning"
  number="4"
  title="Phase 0: Pre-Planning"
  icon={<Search className="h-5 w-5" />}
>
  <BlockQuote>
    &ldquo;When prompting the model to create the initial markdown plan, I spend
    a lot of time explaining the goals and intent of the project and detailing
    the workflows.&rdquo;
  </BlockQuote>

  <SubSection title="Define Goals, Intent, and Workflows">
    <P>
      Before writing a single line of the plan, you need clarity on what the
      product should feel like, which tradeoffs are acceptable, and which
      workflows matter most. This front-loaded thinking is the highest-leverage
      thing a human does in the entire process.
    </P>
  </SubSection>

  <SubSection title="Choose the Tech Stack">
    <BulletList
      items={[
        <>
          <Hl>Web apps:</Hl> TypeScript, Next.js 16, React 19, Tailwind,
          <Jargon term="supabase">Supabase</Jargon>, Rust/WASM for performance-critical parts
        </>,
        <>
          <Hl>CLI tools:</Hl> Golang or Rust
        </>,
      ]}
    />
    <P>
      Picking a stack is not a planning task &mdash; it is a pre-planning task.
      An incoherent stack creates a cascade of contradictory beads.
    </P>
  </SubSection>

  <SubSection title="Prepare Best Practices Guides">
    <P>
      Keep best practices guides in the project folder and reference them in{" "}
      <IC>AGENTS.md</IC>. These documents teach agents the norms of the
      codebase so they don&apos;t have to rediscover them from context alone.
    </P>
  </SubSection>

  <SubSection title="Build the Foundation Bundle">
    <P>
      You need everything in this bundle before planning begins in earnest:
    </P>
    <BulletList
      items={[
        "A coherent tech stack",
        "An initial architectural direction",
        <>
          A strong <IC>AGENTS.md</IC>
        </>,
        "Up-to-date best-practices guides",
        "Enough product and workflow explanation for models to understand what good looks like",
      ]}
    />
    <BlockQuote>
      &ldquo;You need a good foundation, a good and coherent tech stack and
      project architecture, a good AGENTS.md file, best practice guides, and
      good planning documents.&rdquo;
    </BlockQuote>
    <TipBox variant="warning">
      Weak foundations leak uncertainty into every later stage. If any piece is
      missing, the plan will silently absorb ambiguity that later shows up as
      bad beads and confused agents.
    </TipBox>
    <TipBox variant="tip">
      Bootstrap pattern: copy an existing repo&apos;s <IC>AGENTS.md</IC> into
      the new repo as a starting point, then replace project-specific content.
      This reuse keeps the operating manual consistent across projects.
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

{/* SECTION 5 */}
<GuideSection
  id="initial-plan"
  number="5"
  title="Phase 1: Creating the Initial Markdown Plan"
  icon={<ScrollText className="h-5 w-5" />}
>
  <SubSection title="The Human Part">
    <BlockQuote>
      &ldquo;The plan creation is the most free form, creative, human part of the
      process. I just usually start writing in a messy stream of thought way to convey the basic concept and then collaboratively work the agent to flesh it out in an initial draft.&rdquo;
    </BlockQuote>
    <P>
      You do not need to write the initial plan yourself line by line. You can simply explain what you want to make to a <Jargon term="llm">frontier model</Jargon>. The key is conveying the concept, goals, user workflows, and success criteria clearly.
    </P>
    <P>What remains manual is the <Hl>highest-leverage direction-setting</Hl>:</P>
    <BulletList items={[
      "What the product should feel like",
      "Which tradeoffs are acceptable",
      "Which workflows matter most",
      "Which ideas from model output are actually good versus merely plausible",
    ]} />
    <P>That is why the workflow still treats planning as the part where the human has the biggest impact on the final result.</P>
  </SubSection>

  <SubSection title="Using GPT Pro">
    <P>
      GPT Pro with <Jargon term="extended-thinking">Extended Reasoning</Jargon> is the recommended model for producing the
      first plan. When input fits comfortably in context &mdash; as a pre-planning
      prompt almost always does &mdash; it outperforms every alternative for
      structured, holistic plan generation.
    </P>
    <BlockQuote>
      &ldquo;No other model can touch Pro on the web when it&rsquo;s dealing
      with input that easily fits into its context window.&rdquo;
    </BlockQuote>
  </SubSection>

  <SubSection title="Multi-Model Initial Plans">
    <P>
      For the best raw material, ask multiple frontier models to independently
      create plans. Store the results as competing proposals for synthesis in the
      next phase:
    </P>
    <NumberedList
      items={[
        <>
          <Hl>GPT Pro</Hl> (Extended Reasoning)
        </>,
        <>
          <Hl>Claude Opus</Hl> (web app)
        </>,
        <>
          <Hl>Gemini</Hl> (Deep Think)
        </>,
        <>
          <Hl>Grok Heavy</Hl>
        </>,
      ]}
    />
    <P>
      Plans are typically stored as{" "}
      <IC>competing_proposal_plans/claude_version/</IC>,{" "}
      <IC>gpt_version/</IC>, and so on. This pattern has been observed across at least 10 sessions spanning 7+ projects including ntm, destructive_command_guard, vibe_cockpit, mcp_agent_mail_rust, and frankensqlite. Each model brings different strengths;
      the goal is diverse raw material for synthesis.
    </P>
    <TipBox variant="info">
      In the CASS Memory System project, the competing plans are publicly visible at{" "}
      <a href="https://github.com/Dicklesworthstone/cass_memory_system/tree/main/competing_proposal_plans" target="_blank" rel="noopener noreferrer" className="underline">github.com/Dicklesworthstone/cass_memory_system/tree/main/competing_proposal_plans</a>
    </TipBox>
  </SubSection>

  <SubSection title="Running Case Study: Atlas Notes">
    <P>
      The first plan for Atlas Notes would spell out:
    </P>
    <BulletList
      items={[
        "Users upload Markdown files through a drag-and-drop UI",
        "System parses frontmatter tags, stores upload failures for review",
        "Search supports keyword, tag, and date filtering with low latency",
        "Admins get a screen showing ingestion failures, parse reasons, and retry actions",
        "Auth is internal-only",
        <>
          End-to-end coverage for upload success, failure, search, filtering,
          and admin review
        </>,
      ]}
    />
    <TipBox variant="info">
      The key difference a good plan delivers: the whole product becomes{" "}
      <Hl>legible before any code exists</Hl>. Every workflow, edge case, and
      constraint is on paper &mdash; not locked inside someone&apos;s head or
      discovered at implementation time.
    </TipBox>
  </SubSection>
</GuideSection>


              <Divider />

              <GuideSection
  id="synthesis"
  number="6"
  title="Phase 2: Multi-Model Plan Synthesis"
  icon={<Layers className="h-5 w-5" />}
>
  <P>
    Once you have competing plans from multiple models, synthesize them into a single superior
    plan. GPT Pro serves as the <Hl>&ldquo;final arbiter&rdquo;</Hl>&mdash;its extended reasoning
    mode is uniquely suited to holding all the competing plans in context and performing genuine
    intellectual arbitration between them.
  </P>

  <PromptBlock
    title="The Synthesis Prompt"
    prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with\npretty different plans which you can read below. I want you to REALLY\ncarefully analyze their plans with an open mind and be intellectually honest\nabout what they did that's better than your plan. Then I want you to come up\nwith the best possible revisions to your plan that artfully and skillfully\nblends the "best of all worlds" to create a true, ultimate, superior hybrid\nversion of the plan that best achieves our stated goals and will work the\nbest in real-world practice to solve the problems we are facing and our\noverarching goals while ensuring the extreme success of the enterprise as\nbest as possible; you should provide me with a complete series of git-diff\nstyle changes to your original plan to turn it into the new, enhanced, much\nlonger and detailed plan that integrates the best of all the plans with\nevery good idea included (you don't need to mention which ideas came from\nwhich models in the final revised enhanced plan):`}
    where="GPT Pro web app with Extended Reasoning enabled"
    whyItWorks="GPT Pro can hold all competing plans in context simultaneously and perform genuine arbitration. The git-diff output format keeps the integration step mechanical and verifiable."
  />

  <TipBox variant="info">
    <strong>&ldquo;Best of all worlds&rdquo;</strong> is the signature phrase of this methodology.
    It appears in 10+ distinct sessions across 7+ projects. When you see it in a session log,
    you&apos;re in Phase 2.
  </TipBox>

  <SubSection title="How to Integrate the Synthesis">
    <P>
      Take GPT Pro&apos;s output and paste it into Claude Code with the following prompt.
      The agent will apply the revisions directly to the markdown plan file in-place and then
      give you a candid self-assessment of each change.
    </P>
    <PromptBlock
      title="Integration Prompt (Claude Code)"
      prompt={`OK, now integrate these revisions to the markdown plan in-place; be\nmeticulous. At the end, you can tell me which changes you wholeheartedly\nagree with, which you somewhat agree with, and which you disagree with:\n[Pasted synthesis output]`}
      where="Claude Code (Opus), applied to the markdown plan file"
      whyItWorks="Asking for a self-assessment at the end forces the agent to engage critically with the material rather than rubber-stamping every diff. You get a natural review layer built in."
    />
  </SubSection>

  <SubSection title="Real-World Pitfall">
    <TipBox variant="warning">
      In <IC>destructive_command_guard</IC> sessions, agents got stuck in a limbo between
      plan revision and bead operationalization. Always ensure the synthesis step
      concludes with an <strong>explicit transition statement</strong>&mdash;something like
      &ldquo;The plan is now final; next step is bead creation.&rdquo; Without that signal,
      agents may loop back into synthesis indefinitely.
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

<GuideSection
  id="refinement"
  number="7"
  title="Phase 3: Iterative Plan Refinement"
  icon={<Repeat className="h-5 w-5" />}
>
  <P>
    Synthesis produces a hybrid plan. Refinement makes it <Hl>great</Hl>. This phase runs
    in a loop: paste the current plan into a fresh GPT Pro conversation, receive proposed
    changes, integrate them into the file via Claude Code, and repeat. Each round finds
    things the previous round missed.
  </P>

  <PromptBlock
    title="The Refinement Prompt"
    prompt={`Carefully review this entire plan for me and come up with your best\nrevisions in terms of better architecture, new features, changed features,\netc. to make it better, more robust/reliable, more performant, more\ncompelling/useful, etc. For each proposed change, give me your detailed\nanalysis and rationale/justification for why it would make the project\nbetter along with the git-diff style changes relative to the original\nmarkdown plan shown below:\n<PASTE YOUR EXISTING COMPLETE PLAN HERE>`}
    where="GPT Pro web app, fresh conversation each round"
    whyItWorks="Fresh conversations prevent the model from anchoring on its own prior output. Each round starts cold and finds genuinely new problems."
  />

  <SubSection title="The Refinement Loop">
    <NumberedList
      items={[
        "Paste the current complete plan into a fresh GPT Pro conversation.",
        <>Take GPT Pro&apos;s output and have Claude Code integrate it in-place with the integration prompt from Phase 2.</>,
        "Repeat with a fresh conversation each time&mdash;never continue the same thread.",
      ]}
    />
    <BlockQuote>
      &ldquo;This has never failed to improve a plan significantly.&rdquo;
    </BlockQuote>
  </SubSection>

  <SubSection title='The &ldquo;Lie to Them&rdquo; Technique'>
    <P>
      Models tend to stop searching for problems after finding roughly 20&ndash;25. They
      self-satisfy. The solution is to lie about how many problems exist&mdash;claim a
      much larger number, and the model keeps searching exhaustively to close the gap.
    </P>
    <PromptBlock
      title="Overshoot Mismatch Hunt"
      prompt={`Do this again, and actually be super super careful: can you please check\nover the plan again and compare it to all that feedback I gave you? I am\npositive that you missed or screwed up at least 80 elements of that\ncomplex feedback.`}
      whyItWorks="By asserting 80+ errors exist, the model treats the problem as unsolved and continues scanning. The actual number doesn\u2019t matter\u2014the framing is what overrides the satisfaction signal."
    />
  </SubSection>

  <SubSection title="Convergence">
    <P>
      After 4&ndash;5 rounds, suggestions become very incremental. That is the convergence
      signal. Stay in plan refinement as long as whole-workflow questions are still moving.
      Switch to beads when the plan is mostly stable and the remaining improvements are
      about execution structure rather than design.
    </P>
    <TipBox variant="tip">
      For the Cass GitHub Pages export feature, the plan went through multiple rounds over
      approximately 3 hours and grew to <strong>~3,500 lines</strong>. Plans created this way routinely
      reach 3,000&ndash;6,000+ lines. They are the result of countless iterations and blending of ideas and feedback from many models, not slop. Example of a 6,000-line plan:{" "}
      <a href="https://github.com/Dicklesworthstone/jeffreysprompts.com/blob/main/PLAN_TO_MAKE_JEFFREYSPROMPTS_WEBAPP_AND_CLI_TOOL.md" target="_blank" rel="noopener noreferrer" className="underline">jeffreysprompts.com plan</a>
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

<GuideSection
  id="plan-to-beads"
  number="8"
  title="Phase 4: Converting the Plan into Beads"
  icon={<Boxes className="h-5 w-5" />}
>
  <TipBox variant="info">
    Beads are like Jira or Linear, but optimized for coding agents. They represent epics,
    tasks, and subtasks with an explicit dependency structure, stored locally in{" "}
    <IC>.beads/*.jsonl</IC> files backed by SQLite. The key difference from conventional
    task trackers: beads carry <strong>enough embedded context that a fresh agent can act
    immediately</strong> without loading the whole project.
  </TipBox>

  <PromptBlock
    title="The Conversion Prompt"
    prompt={`OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never nead to consult back to the original markdown plan document. Remember to ONLY use the \`br\` tool to create and modify the beads and add the dependencies.`}
    where="Claude Code (Opus)"
    whyItWorks="Forces the agent to treat plan-to-beads as a translation problem, not mere task extraction. The key sentence is requiring beads so detailed you never need to reopen the plan."
  />

  <SubSection title="The Two-Stage Process">
    <P>
      Planning and beads are separate problems. Never conflate them.
    </P>
    <BulletList
      items={[
        "The markdown plan is where architecture, tradeoffs, and intent get worked out. It lives in prose.",
        "Beads are how that thinking gets packaged for distributed execution. They live in structured data.",
        <>Never include <IC>br</IC> commands or bead syntax inside the markdown plan itself&mdash;go directly from plan prose to actual beads.</>,
        "Most decision-making should happen in plan space. Beads should embed conclusions, not open questions.",
      ]}
    />
    <BlockQuote>
      &ldquo;The planning is and should be prior to and orthogonal to beads. You should always
      have a super detailed markdown plan first. Then treat transforming that markdown plan into
      beads as a separate, distinct problem with its own challenges.&rdquo;
    </BlockQuote>
  </SubSection>

  <SubSection title="Beads as Executable Memory">
    <P>
      If the beads are weak, the swarm becomes improvisational. If they are rich, the swarm
      becomes almost mechanical. The goal is to front-load every decision into the bead graph
      so that implementation is a matter of execution, not re-design.
    </P>
    <BlockQuote>
      &ldquo;It works better if most of the decision making is made ahead of time during the
      planning phases and then is embedded in the beads.&rdquo;
    </BlockQuote>
  </SubSection>

  <SubSection title="Critical Design Principles">
    <NumberedList
      items={[
        <><Hl>Self-contained</Hl>: Every piece of context, reasoning, and intent from the plan embedded in beads. A fresh agent should be able to work from the bead alone.</>,
        <><Hl>Rich content</Hl>: Long descriptions with embedded markdown. Design decisions live inside beads, not in external documents.</>,
        <><Hl>Complete coverage</Hl>: Everything from the plan must be represented. Lose nothing in translation.</>,
        <><Hl>Dependency structure</Hl>: Explicit and correct for <IC>bv</IC> routing. The graph is the execution schedule.</>,
        <><Hl>Include testing</Hl>: Comprehensive unit tests and e2e scripts with detailed logging specified inside the bead, not as an afterthought.</>,
        <><Hl>Beads are for agents</Hl>: &ldquo;Conceptually, the beads are more for them than for you.&rdquo;</>,
      ]}
    />
  </SubSection>

  <SubSection title="Beads CLI Reference">
    <CodeBlock
      language="bash"
      code={`br create --title "..." --priority 2 --label backend    # Create issue
br list --status open --json                             # List open issues
br ready --json                                          # Show unblocked tasks
br show <id>                                             # View issue details
br update <id> --status in_progress                      # Claim task
br close <id> --reason "Completed"                       # Close task
br dep add <id> <other-id>                               # Add dependency
br comments add <id> "Found root cause..."               # Add comment
br sync --flush-only                                     # Export to JSONL`}
    />
    <P>
      Key concepts: Priority P0&ndash;P4 (integers), Types (task / bug / feature / epic /
      question / docs), Dependencies (<IC>br ready</IC> shows currently unblocked work),
      Storage (SQLite + JSONL hybrid for both speed and portability).
    </P>
  </SubSection>

  <SubSection title="Scale Examples">
    <DataTable
      headers={["Project", "Plan Size", "Beads Created"]}
      rows={[
        ["CASS Memory System", "5,500 lines", "347 beads"],
        ["FrankenSQLite", "—", "Hundreds (via parallel subagents)"],
        ["Frankensearch", "—", "122 open beads across 3 epics"],
      ]}
    />
  </SubSection>

  <SubSection title="What Three Good Beads Look Like">
    <P>
      The title is not the important part. What matters is that each bead is rich enough
      that a fresh agent can immediately understand correct implementation.
    </P>
    <BulletList
      items={[
        <><strong>br-101 Upload and Parse Pipeline:</strong> accepted file formats, frontmatter parsing rules, where failures are logged, what happens on malformed input, unit and e2e test coverage requirements.</>,
        <><strong>br-102 Search Index and Query UX:</strong> search behavior, indexing rules, latency expectations, filter semantics, empty-state UX, test coverage targets.</>,
        <><strong>br-103 Ingestion Failure Dashboard:</strong> admin workflow, permission boundaries, retry logic, logging strategy, and why the dashboard matters to the overall feature.</>,
      ]}
    />
  </SubSection>
</GuideSection>

<Divider />

<GuideSection
  id="bead-polishing"
  number="9"
  title="Phase 5: Iterative Bead Polishing"
  icon={<Sparkles className="h-5 w-5" />}
>
  <P highlight>
    This is the &ldquo;check your beads N times&rdquo; phase. Most people underinvest in
    it. More rounds here pay larger dividends than almost anything else you can do before
    implementation begins.
  </P>

  <PromptBlock
    title="The Polishing Prompt"
    prompt={`Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the \`br\` cli tool for all changes, and you can and should also use the \`bv\` tool to help diagnose potential problems with the beads.`}
    where="Claude Code (Opus), usually 4-6 rounds across one or more fresh sessions"
    whyItWorks="Each pass through a fresh context window finds things previous passes normalized past. The capitalized warnings prevent the most common failure mode: simplification drift."
  />

  <SubSection title="How Many Rounds?">
    <P>
      The number of polishing rounds is the single most impactful lever you control before
      implementation. Running it once is table stakes. Running it six times is where the
      real gains compound.
    </P>
    <DataTable
      headers={["Project Scale", "Minimum Rounds", "Notes"]}
      rows={[
        ["Small project", "3", "Any fewer and major issues will survive to implementation"],
        ["Normal project", "4-6", "The standard range for production-quality bead sets"],
        ["Heavyweight / high-stakes", "6+", "Keep going past 6 if still finding meaningful issues"],
      ]}
    />
    <BlockQuote>
      &ldquo;I used to only run that once or twice before implementation, but I experimented
      recently with running it 6+ times, and it kept making useful refinements.&rdquo;
    </BlockQuote>
    <TipBox variant="tip">
      Agents typically manage 2&ndash;3 polishing passes before running out of context window.
      Starting fresh sessions for additional passes is not a bug&mdash;it is the mechanism.
      Fresh context is fresh eyes.
    </TipBox>
  </SubSection>

  <SubSection title="What Polishing Actually Does">
    <BulletList
      items={[
        <><strong>Duplicate detection and merging</strong>&mdash;FrankenSQLite had 9 exact duplicate pairs caught and collapsed in polishing.</>,
        <><strong>Quality scoring</strong> against WHAT / WHY / HOW criteria&mdash;beads that fail any dimension get expanded.</>,
        <><strong>Description filling via parallel subagents</strong>&mdash;thin beads get fleshed out in parallel rather than sequentially.</>,
        <><strong>Dependency correction</strong>&mdash;cycles, missing edges, and wrongly ordered dependencies are fixed.</>,
        <><strong>Coverage verification against the plan</strong>&mdash;every element of the markdown plan is cross-referenced to confirm it is represented in at least one bead.</>,
      ]}
    />
  </SubSection>

  <SubSection title="Cross-Reference Against the Plan">
    <P>
      Polishing is bidirectional. Tell agents to go through each bead and check it against
      the plan, <em>and also</em> go through the plan and cross-reference every element
      against the beads. Both directions catch different classes of omission.
    </P>
  </SubSection>

  <SubSection title="Fresh Eyes Technique">
    <P>
      Start a brand new session with zero context about the beads and give it this opener:
    </P>
    <PromptBlock
      title="Fresh-Eyes Opener"
      prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code.\n\nWe recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using br and bv.`}
      where="New Claude Code session with no prior context"
      whyItWorks="A session that has never seen the beads before has not normalized to their current state. It will flag things that feel wrong rather than familiar."
    />
  </SubSection>

  <SubSection title="Final Cross-Model Check">
    <P>
      After <Jargon term="claude-code">Claude Code</Jargon> polishing rounds are complete, run one final round using <Jargon term="codex">Codex</Jargon> with
      GPT (high reasoning effort) using the same polishing prompt. Different models have
      different blind spots. This final pass consistently catches things Claude missed.
    </P>
  </SubSection>

  <SubSection title="Convergence Detection">
    <P>
      Three weighted signals tell you when polishing is done:
    </P>
    <DataTable
      headers={["Signal", "Weight", "What to Check"]}
      rows={[
        ["Output size shrinking", "35%", "Are agent responses getting shorter each round?"],
        ["Change velocity slowing", "35%", "Is the rate of change decelerating round-over-round?"],
        ["Content similarity increasing", "30%", "Are successive rounds more similar than different?"],
      ]}
    />
    <P>
      When the weighted convergence score reaches 0.75, you&apos;re ready to move on. Above
      0.90, you are firmly in diminishing returns.
    </P>
    <DataTable
      headers={["Phase", "Rounds", "Character"]}
      rows={[
        ["Major Fixes", "1-3", "Wild swings, fundamental structural changes"],
        ["Architecture", "4-7", "Interface improvements, boundary refinements"],
        ["Refinement", "8-12", "Edge cases, nuanced handling"],
        ["Polishing", "13+", "Converging to steady state"],
      ]}
    />
    <TipBox variant="warning">
      Early termination red flags: <strong>oscillation</strong> (alternating between two
      versions&mdash;apply the &ldquo;Third Alternative&rdquo; prompt),{" "}
      <strong>expansion</strong> (output growing&mdash;agent is adding complexity rather than
      converging; step back), <strong>plateau at low quality</strong> (kill the approach and
      restart fresh with a new framing).
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

<GuideSection
  id="idea-wizard"
  number="10"
  title="Phase 5b: The Idea-Wizard Pipeline"
  icon={<Lightbulb className="h-5 w-5" />}
>
  <P>
    For existing projects that need new features rather than a ground-up build, the
    Idea-Wizard pipeline is a formalized 6-phase approach. It produces the same quality of
    bead set as the full planning pipeline, but starting from a different entry point.
  </P>

  <SubSection title="The 6 Phases">
    <NumberedList
      items={[
        <><strong>Ground in reality:</strong> Read <IC>AGENTS.md</IC> and list all existing beads. This step is mandatory&mdash;it prevents duplicating work that is already in flight or already complete.</>,
        <><strong>Generate 30, winnow to 5:</strong> Brainstorm 30 candidate ideas, then self-select the best 5 with explicit justification for why each made the cut.</>,
        <><strong>Expand to 15:</strong> Produce ideas 6&ndash;15 (&ldquo;ok and your next best 10 and why&rdquo;). Check each against existing beads for novelty before proceeding.</>,
        <><strong>Human review:</strong> Select which ideas to actually pursue. This is the human&apos;s primary decision gate in this pipeline.</>,
        <><strong>Turn into beads:</strong> Create beads with full descriptions, dependencies, and priorities for every selected idea.</>,
        <><strong>Refine (repeat 4&ndash;5x):</strong> Run the polishing loop from Phase 5 on the new beads before any implementation begins.</>,
      ]}
    />
  </SubSection>

  <SubSection title="When to Use Which Pipeline">
    <DataTable
      headers={["Situation", "Pipeline"]}
      rows={[
        ["New project from scratch", "Full pipeline (Phases 0-5)"],
        ["Adding features to existing project", "Idea-Wizard pipeline"],
        ["Combining both approaches", "Use Idea-Wizard to generate ideas, then full markdown plan, then beads"],
      ]}
    />
  </SubSection>

  <SubSection title="Ad-Hoc Changes: TODO Mode vs. Formal Beads">
    <P>
      Not every improvement warrants a full bead. There are two paths for ad-hoc work:
    </P>
    <BulletList
      items={[
        <><strong>Formalize into beads</strong> if the change is substantial, touches multiple workflows, or would benefit from explicit dependency tracking.</>,
        <><strong>Execute ad hoc with TODO system</strong> if the change is quick, bounded, and self-contained.</>,
      ]}
    />
    <PromptBlock
      title="Ad-Hoc TODO Prompt"
      prompt={`OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!`}
      where="Claude Code, for bounded ad-hoc improvements"
      whyItWorks="The explicit TODO obligation prevents agents from completing the visible surface of a task while leaving invisible sub-tasks undone."
    />
    <TipBox variant="tip">
      If a task that started as ad hoc begins expanding or involving multiple agents,
      convert it to proper beads before it grows further. The cost of late formalization is
      much higher than early formalization.
    </TipBox>
  </SubSection>
</GuideSection>

<Divider />

<GuideSection
  id="agents-md"
  number="11"
  title="Phase 6: The AGENTS.md File"
  icon={<FileText className="h-5 w-5" />}
>
  <P highlight>
    The <IC>AGENTS.md</IC> file is the single most critical piece of infrastructure for
    agent coordination. A baseline version should exist earlier as part of the foundation
    bundle; it appears here as &ldquo;Phase 6&rdquo; because this is where its importance
    becomes impossible to miss.
  </P>

  <TipBox variant="info">
    <IC>AGENTS.md</IC> is the swarm&apos;s durable operating manual. It tells a fresh or
    partially-amnesic agent how to behave, what tools exist, what the project is, and what
    the absolute rules are. A blank or thin <IC>AGENTS.md</IC> creates chaos immediately.
  </TipBox>

  <SubSection title="What It Contains">
    <BulletList
      items={[
        "All tools available to agents, each with a prepared blurb explaining purpose and usage",
        "Project-specific rules, conventions, and architectural decisions",
        "Safety rules: no file deletion, no destructive git commands",
        "Best practices references specific to the project stack",
        "A plain-language description of what the project is and how it works",
      ]}
    />
  </SubSection>

  <SubSection title="Bootstrap From a Known-Good Template">
    <NumberedList
      items={[
        <>Copy a known-good <IC>AGENTS.md</IC> from a mature project (e.g., <IC>/dp/destructive_command_guard/AGENTS.md</IC>) into the new project.</>,
        "Use it as the initial control plane while the plan and beads are being worked out.",
        "Once the project is better understood, replace the project-specific content sections.",
        "Keep the general rules, safety notes, and tool blurbs&mdash;those transfer universally.",
      ]}
    />
    <TipBox variant="warning">
      A blank <IC>AGENTS.md</IC> creates chaos immediately. Never start a new project
      without one. Copying a template takes 30 seconds; recovering from a poorly-coordinated
      swarm takes hours.
    </TipBox>
  </SubSection>

  <SubSection title="Core Rules">
    <NumberedList
      items={[
        <><strong>Rule 0 &mdash; Override Prerogative:</strong> The human&apos;s instructions override everything, including these rules.</>,
        <><strong>Rule 1 &mdash; No File Deletion:</strong> Never delete files without explicit permission from the human.</>,
        <><strong>No destructive git:</strong> <IC>git reset --hard</IC>, <IC>git clean -fd</IC>, and <IC>rm -rf</IC> are absolutely forbidden.</>,
        <><strong>Branch policy:</strong> All work on <IC>main</IC>, never <IC>master</IC>. No feature branches.</>,
        <><strong>No script-based code changes:</strong> Always make code changes manually, never via generated scripts.</>,
        <><strong>No file proliferation:</strong> Never create <IC>mainV2.rs</IC>, <IC>main_improved.rs</IC>, or similar variants. Edit the original.</>,
        <><strong>Compiler checks after changes:</strong> Run <IC>cargo check</IC>, <IC>cargo clippy</IC>, <IC>cargo fmt --check</IC> (or equivalent) after every change.</>,
        <><strong>Multi-agent awareness:</strong> Never stash, revert, or overwrite another agent&apos;s changes. Use Agent Mail to coordinate.</>,
      ]}
    />
  </SubSection>

  <SubSection title="Why Agents Must Constantly Re-Read It">
    <BlockQuote>
      &ldquo;After compaction they become like drug-addled children and all bets are off.
      The main thing that&apos;s dangerous is for them to do a compaction and then not
      immediately reread AGENTS.md because that file contains their whole marching orders.&rdquo;
    </BlockQuote>
    <P>
      From session history, <Hl>&ldquo;Reread AGENTS.md&rdquo;</Hl> is the single most
      common prompt prefix across the entire archive. It appears at the start of virtually
      every new session and every post-compaction continuation.
    </P>
  </SubSection>

  <SubSection title="Compaction Management">
    <P>Context compaction is the single biggest threat to agent quality. After compaction, agents lose the nuances from <IC>AGENTS.md</IC> and start making mistakes:</P>
    <BlockQuote>&ldquo;The main thing that&apos;s dangerous is for them to do a compaction and then not immediately reread AGENTS.md because that file contains their whole marching orders. Suddenly they&apos;re like a bumbling new employee who doesn&apos;t know the ropes at all.&rdquo;</BlockQuote>
    <P>The pragmatic approach: don&apos;t fight compaction, just re-read <IC>AGENTS.md</IC> and roll with it. If the agent starts doing dumb things even after re-reading, start a fresh session.</P>
    <BlockQuote>&ldquo;I used to be a compaction absolutist, but now I just tell them to re-read AGENTS.md and roll with it until they start doing dumb stuff, then start a new session.&rdquo;</BlockQuote>
    <P>In practice, this reread ritual is important enough that it has been automated for Claude Code with <IC>post_compact_reminder</IC>. That is a good example of a small automation attached to a validated ritual: the behavior was discovered manually first, then operationalized once it proved repeatedly necessary.</P>
    <P highlight>When beads are well-constructed, compaction matters less because each bead is self-contained with full context. The agent can pick up any bead fresh without needing the full conversation history.</P>
    <BlockQuote>&ldquo;Not sure exactly when the compaction happens matters that much when you use beads the way I do.&rdquo;</BlockQuote>
  </SubSection>

  <SubSection title="Tool Blurbs Are Essential">
    <P>
      Every tool in <IC>AGENTS.md</IC> must have a prepared blurb: what it does, when to
      use it, and what the key invocation patterns are. Think of it as the new{" "}
      <IC>man</IC> page&mdash;dense, accurate, and always present.
    </P>
    <BlockQuote>
      &ldquo;I view that as a core part of creating a new agent tool: you have to also give
      the blurb. It&apos;s like the new man page.&rdquo;
    </BlockQuote>
    <P>
      Each project should maintain its own <IC>AGENTS.md</IC> with only the tool blurbs
      relevant to that project. Creating a new project with <IC>acfs newproj</IC> generates a starter <IC>AGENTS.md</IC> automatically. A universal blurb set creates noise and increases
      compaction frequency without adding value.
    </P>
    <TipBox variant="info">
      Real-world examples of <IC>AGENTS.md</IC> files: a{" "}
      <a href="https://github.com/Dicklesworthstone/brenner_bot/blob/main/AGENTS.md" target="_blank" rel="noopener noreferrer" className="underline">complex NextJS webapp + TypeScript CLI</a> and a{" "}
      <a href="https://github.com/Dicklesworthstone/repo_updater/blob/main/AGENTS.md" target="_blank" rel="noopener noreferrer" className="underline">Bash script project</a>.
    </TipBox>
  </SubSection>

  <SubSection title="Tradeoff: Size vs. Compaction Frequency">
    <DataTable
      headers={["AGENTS.md Size", "Compaction Frequency", "Tradeoff"]}
      rows={[
        ["Thin (< 200 lines)", "Less frequent", "Agents lack context; make more mistakes"],
        ["Medium (200-600 lines)", "Moderate", "Good balance for most projects"],
        ["Rich (600+ lines)", "More frequent", "Agents start faster and make fewer errors; worthwhile tradeoff"],
      ]}
    />
    <P>
      More content means more frequent compactions, but it also means agents start each
      session with complete context and spend less time re-discovering how to behave. The
      compaction cost is real but the context gain consistently outweighs it.
    </P>
  </SubSection>
</GuideSection>


              <Divider />

              {/* SECTION 12 */}
              <GuideSection id="swarm" number="12" title="Phase 7: Agent Swarm Execution" icon={<Users className="h-5 w-5" />}>

                <P>Once beads are polished, it&apos;s time to unleash the swarm.</P>

                <SubSection title="NTM: The Agent Cockpit">
                  <P><ToolPill>NTM</ToolPill> (Named Tmux Manager) is the command center for orchestrating multiple agents:</P>
                  <CodeBlock language="bash" code={`# Spawn a multi-agent session
ntm spawn myproject --cc=2 --cod=1 --gmi=1

# This creates:
# - A tmux session named "myproject"
# - 2 Claude Code panes
# - 1 Codex pane
# - 1 Gemini pane

# Send a prompt to ALL agents
ntm send myproject "Your marching orders prompt here"

# Send to specific agent type
ntm send myproject --cc "Focus on the API layer"
ntm send myproject --cod "Focus on the frontend"

# List active sessions
ntm list

# Attach to watch progress
ntm attach myproject

# Open the command palette (battle-tested prompts)
ntm palette`} />
                  <P>NTM is useful, but it is <Hl>not mandatory</Hl>. The methodology needs a way to run multiple agents, send them prompts quickly, and keep them coordinated. It does not require tmux specifically.</P>
                  <P>Why the default ratio <IC>--cc=2 --cod=1 --gmi=1</IC>?</P>
                  <BulletList items={[
                    <><Hl>2 Claude</Hl> &mdash; Great for architecture and complex reasoning; the workhorse</>,
                    <><Hl>1 Codex</Hl> &mdash; Fast iteration and testing; complementary strengths</>,
                    <><Hl>1 Gemini</Hl> &mdash; Different perspective; good for docs and review duty</>
                  ]} />
                </SubSection>

                <SubSection title="What a Mux Is, and What tmux Is">
                  <P>A <Hl>mux</Hl> is a <Jargon term="tmux">terminal multiplexer</Jargon>: a layer that lets you manage multiple shell sessions inside one higher-level session manager. In practice, that usually means some combination of tabs, panes, detached sessions, and reconnection to work that is still running on a local or remote machine.</P>
                  <P><Jargon term="tmux">tmux</Jargon> is the classic Unix terminal multiplexer. It is powerful, battle-tested, and widely available on remote Linux machines. NTM is built on top of tmux, which is why NTM is such a natural fit for multi-agent work.</P>
                  <P>But tmux is only one mux. WezTerm has its own built-in mux. Zellij is another mux. The method cares that you have a workable orchestration layer, not that you picked one specific brand of multiplexer.</P>
                  <P>One common alternative to NTM is to use <Hl>WezTerm</Hl> because native scrollback and text selection are more convenient there than in tmux. A very workable setup is:</P>
                  <BulletList items={[
                    "Run agents in separate tabs using WezTerm and its built-in mux, often across remote machines",
                    <>Trigger your most common prompts from a <Jargon term="stream-deck">Stream Deck</Jargon> with the prompts preconfigured</>,
                    "Keep a large prompt file open in Zed and paste rarer prompts manually",
                    <>In Claude Code, use the project-specific <IC>Ctrl-r</IC> prompt history search when you want to recall something you already used recently</>
                  ]} />
                  <P>There is no single correct operator interface for this part. NTM is one good cockpit. WezTerm tabs plus mux is another. The important thing is that you can launch agents, get prompts into them quickly, monitor them, and keep the coordination layer (<IC>AGENTS.md</IC>, Agent Mail, beads, <IC>bv</IC>) intact.</P>
                  <P><ToolPill>FrankenTerm</ToolPill>, which is built on WezTerm, is aimed more explicitly at this style of workflow, but it is not ready yet.</P>
                  <TipBox variant="info">For concrete setup notes on operator environments, see the WezTerm persistent remote sessions guide, Ghostty terminfo for remote machines, and host-aware color themes guide in the misc_coding_agent_tips_and_scripts repo. These describe WezTerm&apos;s native mux as supporting persistent remote sessions that survive disconnects, sleep, or reboot, while still preserving native scrollback and text selection.</TipBox>
                </SubSection>

                <SubSection title="The Marching Orders Prompt">
                  <P>Give each agent in the swarm this initial prompt:</P>
                  <PromptBlock
                    title="Agent Marching Orders"
                    prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents. Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. *CRITICAL*: All cargo builds and tests and other CPU intensive operations MUST be done using rch to offload them!!! see AGENTS.md for details on how to do this!!!`}
                    where="Sent to each agent at swarm start via ntm send or pasted manually"
                    whyItWorks="Covers every step of the join-up sequence: read context, register, coordinate, then pick work using bv. The explicit warning about communication purgatory prevents agents from getting stuck in endless messaging without producing code."
                  />
                </SubSection>

                <SubSection title="The First 10 Minutes">
                  <P>Once the swarm is live (<IC>ntm spawn</IC>), the first 10 minutes determine whether the session runs smoothly or degrades into chaos. Here&apos;s the recommended sequence:</P>
                  <NumberedList items={[
                    "Stagger agent starts by 30\u201360 seconds",
                    <>Wait 4 seconds after launch before sending the initial prompt</>,
                    <>For Codex: press Enter twice after pasting long prompts</>,
                    <>Each agent&apos;s first action should be: read <IC>AGENTS.md</IC>, register with Agent Mail, query <IC>bv</IC></>
                  ]} />
                </SubSection>

                <SubSection title="The Human&apos;s Role During Execution">
                  <P>During implementation, the human&apos;s job is <Hl>monitoring and maintenance</Hl>, not design. The hard cognitive work happened during planning. This is the repeating cycle:</P>
                  <NumberedList items={[
                    <>Check bead progress (<IC>br list --status in_progress --json</IC> or <IC>bv --robot-triage</IC>)</>,
                    <>Handle compactions: &ldquo;Reread AGENTS.md so it&apos;s still fresh in your mind.&rdquo;</>,
                    "Run periodic reviews: every 30\u201360 minutes, fresh eyes review",
                    <>Manage <Jargon term="rate-limits">rate limits</Jargon>: <IC>caam activate claude backup-2</IC></>,
                    "Commit periodically: every 1\u20132 hours, organized commit prompt",
                    "Handle surprises: create new beads for unanticipated issues"
                  ]} />
                </SubSection>

                <SubSection title="Agent Count Recommendations">
                  <DataTable
                    headers={["Open Beads", "Claude (cc)", "Codex (cod)", "Gemini (gmi)"]}
                    rows={[
                      ["400+", "4", "4", "2"],
                      ["100\u2013399", "3", "3", "2"],
                      ["<100", "1", "1", "1"]
                    ]}
                  />
                </SubSection>

                <SubSection title="The Coordination Trio">
                  <P>The system is distributed and decentralized, built on a trio of tools:</P>
                  <BulletList items={[
                    <><ToolPill>Beads (br)</ToolPill> &mdash; centralized task store, single source of truth</>,
                    <><ToolPill>Agent Mail (am)</ToolPill> &mdash; inter-agent communication and file reservations</>,
                    <><ToolPill>Beads Viewer (bv)</ToolPill> &mdash; graph-theory &ldquo;compass&rdquo; directing agents to optimal next tasks</>
                  ]} />
                  <BlockQuote>&ldquo;Agent Mail + Beads + bv are what unlock the truly insane productivity gains.&rdquo;</BlockQuote>
                  <P>Each tool is essential but insufficient alone. Agent Mail without beads leaves agents with no structured work. Beads without bv leaves agents randomly choosing tasks. bv without Agent Mail leaves agents unable to communicate.</P>
                  <BlockQuote>&ldquo;Each agent just uses bv on its own to find the next optimal bead to work on and marks it as being in-progress and communicates about this to the other agents using Agent Mail. It&apos;s a distributed, robust system where every agent is fungible and replaceable.&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="Why Naive Agent Communication Fails">
                  <P>Building your own agent coordination from scratch is full of footguns:</P>
                  <P><Hl>Footgun #1: Broadcast-to-all defaults.</Hl> Agents are lazy and will only use broadcast mode, spamming every agent with mostly irrelevant information. Burns precious context window.</P>
                  <P><Hl>Footgun #2: Poor <Jargon term="mcp">MCP</Jargon> ergonomics.</Hl> It takes huge iteration to get the API surface right so agents use it reliably without wasting <Jargon term="token">tokens</Jargon>.</P>
                  <P><Hl>Footgun #3: Forcing git worktrees.</Hl> Worktrees demolish velocity and create reconciliation debt when agents diverge.</P>
                  <P><Hl>Footgun #4: Rigid identity and locking.</Hl> Rigid locks held by dead agents block everyone else. Agent Mail uses advisory reservations with TTL expiry and reclaim mechanics.</P>
                </SubSection>

                <SubSection title="Bead IDs as Threading Anchors">
                  <P>Bead IDs create a unified audit trail across all coordination layers:</P>
                  <CodeBlock language="bash" code={`1. Pick work:        br ready --json → choose br-123
              2. Reserve files:    file_reservation_paths(..., reason="br-123")
              3. Announce:         send_message(..., thread_id="br-123", subject="[br-123] Starting auth refactor")
              4. Work:             Reply in thread with progress updates
              5. Complete:         br close br-123, release_file_reservations(...), final message
              6. Commit:           git commit -m "feat: auth refactor (br-123)"`} />
                </SubSection>

                <SubSection title="Agent Mail Registration and Macros">
                  <P>Agent Mail provides four high-level macros:</P>
                  <NumberedList items={[
                    <><IC>macro_start_session</IC> &mdash; Bootstrap: ensure project &rarr; register agent &rarr; fetch inbox</>,
                    <><IC>macro_prepare_thread</IC> &mdash; Join existing thread with summary</>,
                    <><IC>macro_file_reservation_cycle</IC> &mdash; Reserve &rarr; work &rarr; auto-release</>,
                    <><IC>macro_contact_handshake</IC> &mdash; Cross-agent contact setup</>
                  ]} />
                  <P>The raw registration flow:</P>
                  <NumberedList items={[
                    <><IC>ensure_project(project_key=&quot;/data/projects/myrepo&quot;)</IC></>,
                    <><IC>register_agent(project_key, program=&quot;claude_code&quot;, model=&quot;opus&quot;)</IC> &mdash; auto-generates names like &ldquo;ScarletCave&rdquo;</>,
                    <><IC>fetch_inbox(project_key, agent_name)</IC> &mdash; check for existing messages</>,
                    <><IC>read resource://agents/&#123;project_key&#125;</IC> &mdash; see who else is active</>
                  ]} />
                </SubSection>

                <SubSection title="bv for Task Selection: The Graph-Theory Compass">
                  <P>With 200&ndash;500 initial beads, there&apos;s usually a mechanically correct answer for what each agent should work on, from the dependency structure:</P>
                  <BlockQuote>&ldquo;That right answer comes from the dependency structure of the tasks, and this can be mechanically computed using basic graph theory. And that&apos;s what bv does.&rdquo;</BlockQuote>
                  <P><IC>bv</IC> precomputes dependency metrics (PageRank, betweenness, HITS, critical path, cycle detection):</P>
                  <CodeBlock language="bash" code={`bv --robot-triage        # THE MEGA-COMMAND: full recommendations with scores
              bv --robot-next          # Minimal: just the single top pick
              bv --robot-plan          # Parallel execution tracks
              bv --robot-insights      # Full graph metrics
              bv --robot-priority      # Priority recommendations
              bv --robot-diff --diff-since <commit|date>  # Changes since last check
              bv --robot-recipes       # List pre-filter/sort recipes`} />
                  <TipBox variant="warning">Use ONLY <IC>--robot-*</IC> flags. Bare <IC>bv</IC> launches an interactive TUI that blocks your session.</TipBox>
                </SubSection>

                <SubSection title="The bv Origin Story">
                  <P><IC>bv</IC> was made in a single day (&ldquo;just under 7k lines of Golang&rdquo;). Later rewritten to 80k lines. This illustrates effort doesn&apos;t correspond to impact.</P>
                  <BlockQuote>&ldquo;bv started out a tool for humans but always had a robust agent mode. It&apos;s just that my use of it has pivoted to being mostly about the robots.&rdquo;</BlockQuote>
                  <P highlight>A critical design principle: robot mode shouldn&apos;t be the human TUI dumped to JSON. It needs its own affordances.</P>
                  <P>When multiple agents each independently query <IC>bv</IC>, the result is emergent coordination. Agents naturally spread across the optimal work frontier without a central coordinator.</P>
                </SubSection>

                <SubSection title="bv Graph Metrics: A Decision Framework">
                  <DataTable
                    headers={["Pattern", "Meaning", "Action"]}
                    rows={[
                      ["High PageRank + High Betweenness", "Critical bottleneck", "DROP EVERYTHING, fix first"],
                      ["High PageRank + Low Betweenness", "Foundation piece", "Important but not blocking"],
                      ["Low PageRank + High Betweenness", "Unexpected chokepoint", "Investigate why"],
                      ["Low PageRank + Low Betweenness", "Leaf work", "Safe to parallelize"]
                    ]}
                  />
                  <P>Advanced filtering:</P>
                  <CodeBlock language="bash" code={`bv --robot-plan --label backend              # Scope to label
              bv --robot-insights --as-of HEAD~30          # Historical
              bv --recipe actionable --robot-plan          # Only unblocked
              bv --recipe high-impact --robot-triage       # Top PageRank
              bv --robot-triage --robot-triage-by-track    # Group by streams
              bv --robot-triage --robot-triage-by-label    # Group by domain`} />
                </SubSection>

                <SubSection title="How to Get Agents to Use bv">
                  <P>Drop this blurb into your <IC>AGENTS.md</IC>:</P>
                  <CodeBlock language="markdown" code={`### Using bv as an AI sidecar
              bv is a fast terminal UI for Beads projects. It renders lists/details and precomputes dependency metrics so you instantly see blockers and execution order. For agents, call the robot flags for deterministic, dependency-aware outputs.
              - bv --robot-help: shows all AI-facing commands
              - bv --robot-insights: JSON graph metrics
              - bv --robot-plan: JSON execution plan
              - bv --robot-priority: JSON priority recommendations
              - bv --robot-recipes: list recipes
              - bv --robot-diff --diff-since <commit|date>: JSON diff`} />
                </SubSection>

                <SubSection title="The &ldquo;Clockwork Deity&rdquo; Mindset">
                  <BlockQuote>&ldquo;YOU are the bottleneck. Be the clockwork deity to your agent swarms: design a beautiful and intricate machine, set it running, and then move on to the next project.&rdquo;</BlockQuote>
                  <P>The human&apos;s job is front-loaded: create the plan, turn it into beads, set up agents, then step away.</P>
                  <BlockQuote>&ldquo;If you use the right tooling and workflows, it transforms into 80% planning and turning the markdown plan into very detailed beads. And then the rest is just making sure the swarm stays busy.&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="No Role Specialization">
                  <BlockQuote>&ldquo;No, every agent is fungible and a generalist. They are all using the same base model and reading the same AGENTS.md file.&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="The Thundering Herd Problem">
                  <P>When multiple agents start simultaneously, they may all pick the same bead. Solutions:</P>
                  <BulletList items={[
                    "Tell agents to immediately mark beads as in-progress",
                    "Stagger the start by 30 seconds minimum between each agent launch",
                    "Wait 4 seconds after launch before sending the initial prompt",
                    "For Codex: send Enter twice after pasting long prompts",
                    "Use Agent Mail to announce what you\u2019re working on"
                  ]} />
                  <BlockQuote>&ldquo;Classic &lsquo;thundering herd&rsquo; problem. Usually addressed with retry with exponential backoff and jitter, but here marking beads quickly and staggered start is best.&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="Scaling Considerations">
                  <BlockQuote>&ldquo;Efficiency definitely declines as N grows but if you have enough tasks and they have agent mail and you don&apos;t start them all at the exact same time, you go faster as N grows.&rdquo;</BlockQuote>
                  <P>Practical strategies:</P>
                  <BulletList items={[
                    "12 agents max on a single project",
                    "Or run 5 agents per project across multiple projects",
                    "Don\u2019t divide roles \u2014 all agents are generalists",
                    "Agents do rounds of reviewing their own work and others\u2019"
                  ]} />
                </SubSection>

                <SubSection title="Account Switching with CAAM">
                  <P>When you hit rate limits, use <ToolPill>CAAM</ToolPill> for sub-100ms account switching:</P>
                  <CodeBlock language="bash" code={`caam status                     # See current accounts
              caam activate claude backup-2   # Switch instantly`} />
                </SubSection>

                <SubSection title="Diagnosing a Stuck Swarm">
                  <P>When a swarm goes bad, the failure is usually one of two things:</P>
                  <NumberedList items={[
                    <><Hl>A local coordination jam</Hl>, where agents are stepping on each other or losing operational context</>,
                    <><Hl>A strategic drift problem</Hl>, where the swarm is busy but is no longer closing the real gap to the goal</>
                  ]} />
                  <P>The most common symptoms and interventions:</P>
                  <DataTable
                    headers={["Symptom", "Likely Cause", "Fix"]}
                    rows={[
                      ["Multiple agents pick same bead", "Not staggered; not marking in_progress", "Stagger starts, force Agent Mail claims, check reservations, make sure agents use bv"],
                      ["Agent goes in circles after compaction", "Forgot AGENTS.md", "Force reread of AGENTS.md, use post-compaction reminder tooling, kill/restart if erratic"],
                      ["Bead sits in_progress too long", "Agent crashed or silently blocked", "Check Agent Mail, check if session alive, reclaim bead, split out blocker if underspecified"],
                      ["Contradictory implementations", "No Agent Mail coordination or wrong bead boundary", "Audit reservation use, ensure work is threaded through br-### conversation, revise bead boundaries"],
                      ["Lots of code but goal feels far", "Strategic drift: open beads don\u2019t close the remaining gap", "Stop and run high-level diagnosis before burning more tokens"]
                    ]}
                  />
                  <P>That last case is the one people miss most often because the swarm can <Hl>look productive while still heading in the wrong direction</Hl>. These are the <Hl>&ldquo;Come to Jesus&rdquo; moments</Hl> with the agents, used to make sure &ldquo;we aren&apos;t losing sight of the bigger picture&rdquo; after days of methodically cranking through beads.</P>
                  <P>In those moments, the right move is not another local review. It is a high-level reality check:</P>
                  <PromptBlock
                    title="Strategic Reality Check"
                    prompt={`Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?`}
                    where="Sent to one agent during a suspected strategic drift"
                    whyItWorks="Forces a step back from local bead-grinding to evaluate whether the current bead graph actually converges on the project goal. If the answer is 'no,' you add or revise beads before resuming."
                  />
                  <P highlight>If the answer is &ldquo;no,&rdquo; do not just keep coding blindly. Add or revise beads, re-polish them, and then resume swarm execution with a corrected frontier. Busy agents are not the goal; a bead graph that actually converges on the project goal is the goal.</P>
                </SubSection>

                <SubSection title="Running Case Study: Atlas Notes as a Live Swarm">
                  <P>For the same example project, a small first swarm might look like this:</P>
                  <BulletList items={[
                    <><Hl>Claude agent A</Hl> claims <IC>br-101</IC> and implements upload + parse handling.</>,
                    <><Hl>Codex agent B</Hl> claims <IC>br-102</IC> and works on the search path plus tests.</>,
                    <><Hl>Claude agent C</Hl> claims <IC>br-103</IC> and builds the admin failure dashboard.</>,
                    <><Hl>Gemini agent D</Hl> stays flexible: reviews recent work, checks docs, and fills in test or UX gaps where needed.</>
                  ]} />
                  <P>All four agents share the same codebase, read the same <IC>AGENTS.md</IC>, coordinate via Agent Mail, and use <IC>bv</IC> whenever they are uncertain about what unlocks the most progress next. That is what makes the swarm feel like one system rather than four unrelated terminals.</P>
                </SubSection>

                <SubSection title="What the Human Actually Does During an Active Swarm">
                  <P>Newcomers often imagine the human either has to micromanage every agent or disappear completely. In practice, the human does neither. The human tends the swarm the way an operator tends a machine that mostly runs on its own.</P>
                  <P>On roughly a <Hl>10&ndash;30 minute cadence</Hl>, the human does some subset of the following:</P>
                  <NumberedList items={[
                    <>Check <IC>br</IC> or <IC>bv</IC> to see whether progress is flowing or whether work has jammed up behind a blocker.</>,
                    "Look for beads that have been in_progress for too long or that keep bouncing between agents.",
                    "Check Agent Mail for unanswered requests, reservation conflicts, or silence from agents that should be talking.",
                    "Send a fresh-eyes review prompt to one agent while the others keep implementing.",
                    <>Rescue agents after compaction by forcing a re-read of <IC>AGENTS.md</IC>.</>,
                    "Reassign or add agents if a project phase has become lopsided.",
                    "Make sure heavy builds/tests are being offloaded instead of thrashing the local box.",
                    "Periodically designate one agent to handle organized commits and pushes."
                  ]} />
                  <P highlight>The key idea is that the human is managing <Hl>flow quality</Hl>, not hand-authoring every local decision.</P>
                </SubSection>

              </GuideSection>

              <Divider />

              {/* SECTION 13 */}
              <GuideSection id="single-branch" number="13" title="Phase 8: The Single-Branch Git Model" icon={<GitBranch className="h-5 w-5" />}>

                <P highlight>ACFS uses one branch (<IC>main</IC>) with one worktree. All agents commit directly to main.</P>

                <SubSection title="Why Not Branches or Worktrees?">
                  <BlockQuote>&ldquo;I hate worktrees, to me they create more problems than they solve.&rdquo;</BlockQuote>
                  <P><Hl>Branch-per-agent creates merge hell.</Hl> With 10+ agents making frequent commits, merging N branches back to main produces cascading conflicts.</P>
                  <P><Hl>Worktrees add filesystem complexity.</Hl> Each worktree is a full checkout. Disk usage multiplies and path confusion leads to cross-worktree edits that corrupt state.</P>
                  <P><Hl>Agents lose context across branches.</Hl> When an agent switches branches, its in-context understanding becomes stale.</P>
                  <P><Hl>Logical conflicts survive textual merges.</Hl> A function signature change on one branch and a new callsite on another will merge cleanly but fail to compile. On single branch, the second agent sees the change immediately.</P>
                </SubSection>

                <SubSection title="Three Conflict Prevention Mechanisms">
                  <P>The single-branch model works because three mechanisms prevent conflicts:</P>

                  <SubSection title="1. File Reservations (Agent Mail)">
                    <P>Before editing files, agents reserve them:</P>
                    <CodeBlock language="python" code={`file_reservation_paths(
                  project_key="/data/projects/my-repo",
                  agent_name="BlueLake",
                  paths=["src/auth/*.rs"],
                  ttl_seconds=3600,
                  exclusive=true,
                  reason="br-42: refactor auth"
              )`} />
                    <P>Reservations are advisory, not rigid. They expire automatically via TTL. Agents can observe if reserved files haven&apos;t been touched recently and reclaim them.</P>
                    <BlockQuote>&ldquo;This is critical because you want a system robust to agents suddenly dying or getting their memory wiped.&rdquo;</BlockQuote>
                  </SubSection>

                  <SubSection title="2. Pre-Commit Guard">
                    <P>Agent Mail&apos;s pre-commit hook checks reservations at commit time. If you try to commit a file reserved by another agent, the commit is blocked.</P>
                  </SubSection>

                  <SubSection title="3. DCG (Destructive Command Guard)">
                    <P><Jargon term="dcg">DCG</Jargon> mechanically blocks dangerous commands:</P>
                    <DataTable
                      headers={["Blocked Command", "Safe Alternative", "Why"]}
                      rows={[
                        ["git reset --hard", "git stash", "Recoverable"],
                        ["git checkout -- file", "git stash push file", "Preserves changes"],
                        ["git push --force", "git push --force-with-lease", "Checks remote"],
                        ["git clean -fd", "git clean -fdn (preview)", "Shows what would delete"],
                        ["rm -rf /path", "rm -ri /path", "Interactive confirmation"]
                      ]}
                    />
                    <TipBox variant="info">Origin: On December 17, 2025, an agent ran <IC>git checkout --</IC> on uncommitted work. Files were recovered via <IC>git fsck --lost-found</IC>, but the incident proved that instructions don&apos;t prevent execution &mdash; mechanical enforcement does.</TipBox>
                  </SubSection>
                </SubSection>

                <SubSection title="The Recommended Git Workflow">
                  <CodeBlock language="bash" code={`1. Pull latest          git pull --rebase
              2. Reserve files        file_reservation_paths(...)
              3. Edit and test        cargo test / bun test / go test
              4. Commit immediately   git add <files> && git commit
              5. Push                 git push
              6. Release reservation  release_file_reservations(...)`} />
                  <P>Key principles:</P>
                  <BulletList items={[
                    <><Hl>Commit early, commit often.</Hl> Small commits reduce conflict window</>,
                    <><Hl>Push after every commit.</Hl> Unpushed commits are invisible to others</>,
                    <><Hl>Reserve before editing.</Hl> Don&apos;t touch files without a reservation</>,
                    <><Hl>Release when done.</Hl> Don&apos;t hold reservations longer than needed</>
                  ]} />
                </SubSection>

                <SubSection title="Handling Other Agents&apos; Changes">
                  <P>From <IC>AGENTS.md</IC>:</P>
                  <BlockQuote>&ldquo;You NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made.&rdquo;</BlockQuote>
                </SubSection>

              </GuideSection>

              <Divider />

              {/* SECTION 14 */}
              <GuideSection id="code-review" number="14" title="Phase 9: Code Review Loops" icon={<Eye className="h-5 w-5" />}>

                <P>Code review in a multi-agent swarm follows a different rhythm than traditional code review. No PR, no human reviewer, no approval gate. Instead, review is woven into the implementation cycle itself.</P>

                <SubSection title="Self-Review After Each Bead">
                  <PromptBlock
                    title="Self-Review Prompt"
                    prompt={`Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.`}
                    where="Send to each agent after completing a bead"
                    whyItWorks="Forces the agent to re-examine its own work without the bias of implementation momentum"
                  />
                  <P><Hl>How many rounds?</Hl> Run until the agent reports &ldquo;I reviewed everything and found no issues.&rdquo; Typically 1&ndash;2 rounds for simple beads, 2&ndash;3 for complex ones. If 3+ rounds keep finding bugs, the approach may be fundamentally off.</P>
                  <P><Hl>When to send:</Hl> Include in <IC>AGENTS.md</IC> workflow expectations. Well-trained agents will do this automatically.</P>
                </SubSection>

                <SubSection title="Cross-Agent Review (Periodic)">
                  <P>Every 30&ndash;60 minutes or after a natural milestone:</P>
                  <PromptBlock
                    title="Cross-Agent Review Prompt"
                    prompt={`Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!`}
                    where="Send to 1-2 agents that just finished a bead"
                    whyItWorks="Catches cross-agent integration bugs that self-review misses"
                  />
                  <P>Cross-agent review catches a fundamentally different class of bugs than self-review. When Agent A implements a function and Agent B calls it, Agent A&apos;s self-review won&apos;t catch Agent B passing arguments in the wrong order.</P>
                  <TipBox variant="tip">Don&apos;t have all agents stop to review simultaneously. Pick 1&ndash;2 agents that just finished a bead while others continue.</TipBox>
                </SubSection>

                <SubSection title="How Fresh-Eyes Reviews Work in Practice">
                  <P>The most effective reviews use subagent delegation: the parent agent identifies recently changed files (via <IC>git diff --name-only HEAD~5</IC>) and dispatches a fresh subagent to review each file. The fresh subagent has genuinely fresh eyes because it has no memory of the design decisions.</P>
                  <P>Each review should answer:</P>
                  <NumberedList items={[
                    <>Is the implementation correct? Does it do what the bead says?</>,
                    <>Are there edge cases? Empty inputs, concurrent access, error paths</>,
                    <>Are there similar issues elsewhere? Search for same pattern</>,
                    <>Should the approach be different? Sometimes correct but not simplest</>
                  ]} />
                </SubSection>

                <SubSection title="Moving to the Next Bead">
                  <P>After reviews come clean, the transition prompt combines re-reading <IC>AGENTS.md</IC>, querying <IC>bv</IC>, and communicating:</P>
                  <PromptBlock
                    title="Bead Transition Prompt"
                    prompt={`Reread AGENTS.md so it's still fresh in your mind. Use bv with the robot flags to find the most impactful bead(s) to work on next...`}
                    where="Send after self-review passes cleanly"
                    whyItWorks="Ensures graph-theory routing via bv to choose the task that unblocks the most downstream work"
                  />
                  <P>This transition prompt is the glue between beads. It ensures the agent uses graph-theory routing (<IC>bv</IC>) to choose the task that unblocks the most downstream work.</P>
                </SubSection>

              </GuideSection>

              <Divider />

              {/* SECTION 15 */}
              <GuideSection id="testing" number="15" title="Phase 10: Testing and Quality Assurance" icon={<Shield className="h-5 w-5" />}>

                <SubSection title="UBS: The Quality Gate">
                  <CodeBlock language="bash" code={`ubs file.rs file2.rs                    # Specific files (< 1s)
              ubs $(git diff --name-only --cached)    # Staged files
              ubs --only=rust,toml src/               # Language filter
              ubs .                                   # Whole project`} />
                  <P highlight>Golden Rule: <IC>ubs &lt;changed-files&gt;</IC> before every commit. Exit 0 = safe. Exit &gt;0 = fix and re-run.</P>
                </SubSection>

                <SubSection title="Creating Test Beads">
                  <P>If test coverage is insufficient after implementation:</P>
                  <PromptBlock
                    title="Test Bead Generation Prompt"
                    prompt={`Do we have full unit test coverage without using mocks/fake stuff? What about complete e2e integration test scripts with great, detailed logging? If not, then create a comprehensive and granular set of beads for all this.`}
                    where="After core implementation beads are complete"
                    whyItWorks="Generates structured test work that can be distributed across the agent swarm"
                  />
                </SubSection>

                <SubSection title="Testing With Agent Swarms">
                  <P>Tests are effectively free labor:</P>
                  <BlockQuote>&ldquo;The tests become obsolete and need to be revised as the code changes, which slows down dev velocity. But if all the tests are written and maintained by agents, who cares? Add another couple agents and let them deal with it. It&apos;s free!&rdquo;</BlockQuote>
                  <BlockQuote>&ldquo;By the time all the beads are done I generally have hundreds and hundreds of unit tests and e2e integration tests. Larger projects like brennerbot.org have nearly 5,000 tests!&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="The Review Philosophy">
                  <BlockQuote>&ldquo;I&apos;m constantly having them review themselves and the work of other agents throughout the process. I had routines where I just do this deep review with them until they stop coming up with any problems. Then I have them create tons of unit tests and e2e tests.&rdquo;</BlockQuote>
                </SubSection>

                <SubSection title="Compiler Checks (CRITICAL)">
                  <P highlight>After any substantive code changes, always run the appropriate compiler and linter checks:</P>
                  <CodeBlock language="bash" code={`# Rust
              cargo check --all-targets
              cargo clippy --all-targets -- -D warnings
              cargo fmt --check

              # Go
              go build ./...
              go vet ./...

              # TypeScript
              bun typecheck
              bun lint`} />
                </SubSection>

              </GuideSection>

              <Divider />

              {/* SECTION 16 */}
              <GuideSection id="ui-polish" number="16" title="Phase 11: UI/UX Polish" icon={<Palette className="h-5 w-5" />}>

                <P>For projects with a user interface, there&apos;s a dedicated polishing phase after core functionality works but before shipping.</P>

                <SubSection title="Why This Is a Separate Phase">
                  <P>UI/UX polish doesn&apos;t fit naturally into the bead implementation cycle. When an agent implements a &ldquo;user authentication&rdquo; bead, it focuses on making auth work correctly. Whether the login form has good visual hierarchy, whether error messages are helpful, whether the flow feels smooth on mobile &mdash; these are orthogonal concerns requiring a different attention mode.</P>
                </SubSection>

                <SubSection title="The Polish Workflow">
                  <P><Hl>Step 1:</Hl> Run the general review prompt:</P>
                  <PromptBlock
                    title="General Polish Review"
                    prompt={`Great, now I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you...`}
                    where="After core functionality is complete"
                    whyItWorks="Casts a wide net to surface UX issues the implementation-focused agents missed"
                  />

                  <P><Hl>Step 2:</Hl> Review the suggestions and pick which to pursue. The agent will typically generate 15&ndash;30 suggestions. Some excellent, some unnecessary. This is a human judgment step.</P>

                  <P><Hl>Step 3:</Hl> Turn selected suggestions into beads and implement through normal swarm process.</P>

                  <P><Hl>Step 4:</Hl> Run the platform-specific polish prompt:</P>
                  <PromptBlock
                    title="Platform-Specific Polish"
                    prompt={`I still think there are strong opportunities to enhance the UI/UX... I want you to carefully consider desktop UI/UX and mobile UI/UX separately while doing this and hyper-optimize for both separately...`}
                    where="After first round of polish suggestions are implemented"
                    whyItWorks="The 'don't you agree?' phrasing triggers the model to critically evaluate its own work rather than just validating it"
                  />

                  <P><Hl>Step 5:</Hl> Repeat steps 1&ndash;4 until improvements become marginal. Typically 2&ndash;3 rounds.</P>
                </SubSection>

                <SubSection title="De-Slopification">
                  <P>After agents write documentation, run a de-slopify pass:</P>
                  <DataTable
                    headers={["Pattern", "Problem"]}
                    rows={[
                      ["Emdash overuse", "LLMs use emdashes constantly"],
                      ["\"It's not X, it's Y\"", "Formulaic contrast structure"],
                      ["\"Here's why it matters:\"", "Clickbait-style lead-in"],
                      ["\"Let's dive in\"", "Forced enthusiasm"],
                      ["\"At its core...\"", "Pseudo-profound opener"],
                      ["\"It's worth noting...\"", "Unnecessary hedge"]
                    ]}
                  />
                  <TipBox variant="warning">This must be done manually, not via regex. Read each line and revise systematically.</TipBox>
                </SubSection>

              </GuideSection>

              <Divider />

              {/* SECTION 17 */}
              <GuideSection id="bug-hunting" number="17" title="Phase 12: Deep Bug Hunting" icon={<Bug className="h-5 w-5" />}>
                <P>
                  This phase is distinct from the per-bead reviews in Phase 9. Phase 9 reviews happen after each bead is completed and focus on the code just written. Phase 12 happens after all (or most) beads are done and casts a wider net across the entire codebase, looking for problems that only become visible when you see how all the pieces fit together.
                </P>
                <P>
                  The two prompts below serve different purposes and should be alternated. This is one of the more art-than-science parts of the methodology. The prompts overlap in literal meaning, but they reliably activate different search behaviors in the models. This is where the &ldquo;agent theory of mind&rdquo; or &ldquo;gestalt psychology of LLMs&rdquo; framing becomes useful.
                </P>

                <SubSection title="Random Exploration Review">
                  <PromptBlock
                    title="Random Exploration Review"
                    prompt={`I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md.`}
                    where="Any agent terminal"
                    whyItWorks="The 'randomly explore' framing forces the agent away from high-traffic files that already received the most attention during implementation. Bugs that survive to this phase are typically in less-obvious files: utility modules, error handling paths, configuration parsing, edge-case branches."
                  />
                </SubSection>

                <SubSection title="Cross-Agent Deep Review">
                  <PromptBlock
                    title="Cross-Agent Deep Review"
                    prompt={`Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!`}
                    where="Any agent terminal"
                    whyItWorks="Agents that didn't write the code approach it without the assumptions the author had. A different agent reading code for the first time is much more likely to notice token expiry off-by-one errors or error messages that leak internal state."
                  />
                </SubSection>

                <SubSection title="Why Alternate These Two Prompts">
                  <BulletList items={[
                    <><Hl>Cross-agent prompt</Hl> &mdash; tends to induce a suspicious, adversarial stance aimed at boundary failures and root causes in code written by others.</>,
                    <><Hl>Random-exploration prompt</Hl> &mdash; tends to induce a curiosity-driven stance aimed at reconstructing workflows and finding latent bugs.</>,
                  ]} />
                  <P>
                    By alternating between these two stances, you get complementary coverage: one looks for how things break at seams, the other discovers bugs hiding in plain sight within unfamiliar code paths.
                  </P>
                </SubSection>

                <SubSection title="How to Run Deep Bug Hunting">
                  <P highlight>
                    <Hl>Workflow:</Hl> Send the random exploration prompt to 2&ndash;3 agents simultaneously. Each will explore different parts (randomness ensures variety). After they report, send the cross-agent review. Alternate until agents consistently come back clean.
                  </P>
                  <P highlight>
                    <Hl>When to stop:</Hl> When two consecutive rounds (one random exploration, one cross-agent review) both come back clean. If agents keep finding bugs after 4+ rounds, something more fundamental is wrong &mdash; go back to bead space and create specific fix beads.
                  </P>
                  <TipBox variant="tip">
                    <Hl>Combine with UBS:</Hl> Run <IC>ubs .</IC> on the full project before starting. Fix everything UBS flags first, then let agents hunt for subtler issues.
                  </TipBox>
                </SubSection>
              </GuideSection>

              <Divider />

              {/* SECTION 18 */}
              <GuideSection id="shipping" number="18" title="Phase 13: Committing and Shipping" icon={<Ship className="h-5 w-5" />}>
                <SubSection title="Organized Commits">
                  <P>
                    Periodically have one agent handle git operations:
                  </P>
                  <PromptBlock
                    title="Organized Commit Prompt"
                    prompt={`Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files.`}
                    where="Dedicated git agent terminal"
                    whyItWorks="A single agent with full project context can create logically grouped commits with meaningful messages, producing a clean git history that future agents (and humans) can reason about."
                  />
                </SubSection>

                <SubSection title="Landing the Plane (Mandatory Session Completion)">
                  <P highlight>
                    When ending a work session, agents <Hl>MUST</Hl> complete ALL steps:
                  </P>
                  <NumberedList items={[
                    <><Hl>File issues for remaining work</Hl> &mdash; Create beads for anything that needs follow-up</>,
                    <><Hl>Run quality gates</Hl> &mdash; Tests, linters, builds (if code changed)</>,
                    <><Hl>Update issue status</Hl> &mdash; Close finished work, update in-progress items</>,
                    <><Hl>PUSH TO REMOTE</Hl> &mdash; This is <Hl>MANDATORY</Hl>:</>,
                  ]} />
                  <CodeBlock language="bash" code={`git pull --rebase
              br sync --flush-only    # Export beads to JSONL (no git ops)
              git add .beads/         # Stage beads changes
              git add <other files>   # Stage code changes
              git commit -m "..."     # Commit everything
              git push
              git status              # MUST show "up to date with origin"`} />
                  <NumberedList items={[
                    <><Hl>Verify</Hl> &mdash; All changes committed AND pushed</>,
                  ]} />
                  <BlockQuote>
                    Work is NOT complete until <IC>git push</IC> succeeds. NEVER stop before pushing &mdash; that leaves work stranded locally.
                  </BlockQuote>
                </SubSection>

                <SubSection title="Running Case Study: What &ldquo;Done for Now&rdquo; Looks Like">
                  <P>
                    For Atlas Notes, &ldquo;done for now&rdquo; would mean:
                  </P>
                  <BulletList items={[
                    "The upload, parse, search, and admin-review workflows all work end to end",
                    "The key beads are closed and remaining polish/future ideas exist as new beads",
                    "Tests cover the critical user journeys and known failure paths",
                    "UBS and compiler/lint checks are clean",
                    "Commits and pushes are complete",
                    <>The next session can restart from beads, <IC>AGENTS.md</IC>, and Agent Mail threads rather than from human memory</>,
                  ]} />
                  <TipBox variant="info">
                    That last point matters. A Flywheel session is only truly landable when a future swarm can pick it back up without the human re-explaining the project from scratch.
                  </TipBox>
                </SubSection>
              </GuideSection>

              <Divider />

              {/* SECTION 19 */}
              <GuideSection id="toolchain" number="19" title="The Complete Toolchain" icon={<Wrench className="h-5 w-5" />}>
                <SubSection title="The Flywheel Stack (11 Tools)">
                  <DataTable
                    headers={["Tool", "Command", "Purpose", "Key Feature"]}
                    rows={[
                      ["NTM", "ntm", "Named Tmux Manager", "Agent cockpit: spawn/send/broadcast/palette"],
                      ["Agent Mail", "am", "Agent coordination", "Identities, inbox/outbox, file reservations"],
                      ["UBS", "ubs", "Ultimate Bug Scanner", "1000+ patterns, pre-commit guardrails"],
                      ["Beads", "br", "Issue tracking", "Dependency-aware, JSONL+SQLite hybrid"],
                      ["Beads Viewer", "bv", "Triage engine", "PageRank, betweenness, HITS, robot mode"],
                      ["RCH", "rch", "Build/test offloading", "Keeps heavy CPU off the local swarm box"],
                      ["CASS", "cass", "Session search", "Unified agent history indexing"],
                      ["CASS Memory", "cm", "Procedural memory", "Episodic \u2192 working \u2192 procedural"],
                      ["CAAM", "caam", "Auth switching", "Sub-100ms account swap"],
                      ["DCG", "dcg", "Safety guard", "Blocks destructive git/fs operations"],
                      ["SLB", "slb", "Two-person rule", "Optional guardrails for dangerous commands"],
                    ]}
                  />
                  <P>
                    Not every entry is used the same way. <IC>br</IC>, <IC>bv</IC>, <IC>ubs</IC>, and <IC>rch</IC> are ordinary shell commands. Agent Mail is primarily experienced through MCP tools/macros.
                  </P>
                </SubSection>

                <SubSection title="The Flywheel Interactions">
                  <CodeBlock language="bash" code={`NTM spawns agents --> Agents read AGENTS.md
                                --> Agents register with Agent Mail
                                --> Agents query bv for task priority
                                --> Agents claim beads via br
                                --> Agents reserve files via Agent Mail
                                --> Agents implement and test
                                --> UBS scans for bugs
                                --> Agents commit and push
                                --> CASS indexes the session
                                --> CM distills procedural memory
                                --> Next cycle is better`} />
                </SubSection>

                <SubSection title="Supporting Infrastructure">
                  <DataTable
                    headers={["Component", "Purpose"]}
                    rows={[
                      ["AGENTS.md", "Per-project configuration teaching agents about tools and rules"],
                      ["Best practices guides", "Referenced in AGENTS.md, kept current"],
                      ["Markdown plan files", "Source-of-truth planning documents"],
                      ["acfs newproj", "Bootstraps projects with full tooling"],
                      ["acfs doctor", "Single command to verify entire installation"],
                      ["NTM command palette", "Battle-tested prompt library"],
                      ["Claude Code Skills", "Each tool has a dedicated skill for automated workflows"],
                    ]}
                  />
                </SubSection>

                <SubSection title="The Skills Ecosystem">
                  <P>
                    A <Hl>skill</Hl> is a reusable operational instruction pack for an agent. In Claude Code terms, that usually means a <IC>SKILL.md</IC> file plus optional references, scripts, or templates that tell the agent how to use a tool, what pitfalls to avoid, and what a good result looks like. A good skill is closer to executable know-how than to ordinary prose documentation.
                  </P>
                  <P highlight>
                    A tool changes what the agent <Hl>can do</Hl>. A skill changes <Hl>how well</Hl> the agent knows how to do it. The same model with and without a good skill often behaves like two different agents.
                  </P>
                  <P>
                    Every Flywheel tool has a corresponding Claude Code skill. Many skills are bundled directly in the tool repos and get installed automatically with the tool.
                  </P>
                  <TipBox variant="info">
                    For a broader public skills collection: <a href="https://github.com/Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations/tree/main/skills" target="_blank" rel="noopener noreferrer" className="underline">github.com/Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations</a>
                  </TipBox>
                  <P>For a much larger paid library of higher-end skills, see <Hl>jeffreys-skills.md</Hl>. It is a $20/month service with many of the strongest curated skills, new skills added continuously, and a dedicated proprietary CLI called <IC>jsm</IC> for managing them. Unlike jeffreysprompts.com, it does not have a free section.</P>
                  <P>The prompt side has a similar split. <Hl>jeffreysprompts.com</Hl> has a generous free section and is open source. It also has a paid Pro tier with additional prompts and a dedicated proprietary CLI called <IC>jfp</IC> for managing prompt collections.</P>
                  <P>Both paid offerings&mdash;the Pro side of jeffreysprompts.com and jeffreys-skills.md&mdash;are still under active development. That means readers should expect the occasional rough edge or bug. Active work is underway to fix issues quickly, feedback is genuinely appreciated, and refunds are available if someone tries them and is unhappy.</P>
                  <P highlight>Skills provide the prompts, procedures, anti-pattern guidance, and tool-specific workflows directly to agents, which reduces the amount of bespoke prompting a human needs to do by hand.</P>
                </SubSection>

                <SubSection title="Model Recommendations by Phase">
                  <DataTable
                    headers={["Phase", "Recommended Model", "Why"]}
                    rows={[
                      ["Initial plan creation", "GPT Pro (web)", "Extended reasoning, all-you-can-eat pricing"],
                      ["Plan synthesis", "GPT Pro (web)", "Best \u201cfinal arbiter\u201d"],
                      ["Plan refinement", "GPT Pro + Opus", "Pro reviews, Claude integrates"],
                      ["Plan \u2192 Beads", "Claude Code (Opus)", "Best for structured creation"],
                      ["Bead polishing", "Claude Code (Opus)", "Consistent, thorough"],
                      ["Implementation", "Claude + Codex + Gemini", "Diverse swarm"],
                      ["Code review", "Claude + Gemini", "Gemini good for review duty"],
                      ["Final verification", "Codex (GPT)", "Different model catches different things"],
                    ]}
                  />
                </SubSection>
              </GuideSection>

              <Divider />


              {/* ==================== SECTION 20: Key Principles and Insights ==================== */}
              <GuideSection id="principles" number="20" title="Key Principles and Insights" icon={<Zap className="h-5 w-5" />}>
                <P highlight>
                  Before the numbered principles, keep one framing idea in mind: the workflow works because it keeps
                  different kinds of context in different layers.
                </P>
                <BulletList items={[
                  <>The markdown plan holds whole-system intent and reasoning.</>,
                  <>The beads hold executable task structure and embedded local context.</>,
                  <><IC>AGENTS.md</IC> holds operating rules and tool knowledge that must survive compaction.</>,
                  <>The codebase holds the implementation itself, which is too large to be the primary planning medium.</>,
                ]} />

                <SubSection title="Core Principles">
                  <PrincipleCard
                    number="1"
                    title="Plans Fit in Context Windows; Code Doesn&rsquo;t"
                  >
                    Even a 6,000-line plan fits easily in a context window. The equivalent codebase won&rsquo;t. Reasoning at the plan level is fundamentally more effective.
                  </PrincipleCard>

                  <PrincipleCard
                    number="2"
                    title="One Comprehensive Plan, Not Incremental Skeletons"
                  >
                    You get a better result faster by creating one big comprehensive, detailed, granular plan. That&rsquo;s the only way to get these models to use their big brains to understand the entire system all at the same time.
                  </PrincipleCard>

                  <PrincipleCard
                    number="3"
                    title="Beads Supersede the Plan"
                  >
                    Once beads are created properly, the plan becomes a historical artifact. Once you convert the plan docs into beads, you&rsquo;re supposed to not really need to refer back to the docs if you did a good job.
                  </PrincipleCard>

                  <PrincipleCard
                    number="4"
                    title="Agent Fungibility"
                  >
                    Every agent is a generalist. No role specialization. All agents read the same AGENTS.md and can pick up any bead. When one agent breaks, it&rsquo;s not even a problem when all the agents are fungible. Agents become like commodities. This is opposed to &ldquo;specialist agent&rdquo; architectures. Specialist agents become bottlenecks. With 12 fungible agents, losing one makes almost no difference. Think of it like RaptorQ fountain codes: beads are &ldquo;blobs&rdquo; in a stream, any agent catches any bead in any order. No &ldquo;rarest chunk&rdquo; bottleneck.
                  </PrincipleCard>
                </SubSection>

                <SubSection title="Fungibility: Failure Recovery">
                  <P>
                    Failure recovery is trivial with fungible agents:
                  </P>
                  <NumberedList items={[
                    <>Bead remains marked <IC>in_progress</IC></>,
                    <>Any other agent can resume it</>,
                    <>No dependency on the specific dead agent</>,
                    <>Replacement: <IC>ntm add PROJECT --cc=1</IC>, give standard init prompt</>,
                  ]} />
                </SubSection>

                <SubSection title="Coordination and Identity">
                  <PrincipleCard
                    number="5"
                    title="Shared Workspace Over Worktrees"
                  >
                    All agents work in the same directory. Agent Mail file reservations, pre-commit guards, and DCG handle coordination. &ldquo;I run like 10+ of them at once in a single project without git worktrees. Agent Mail is the solution.&rdquo;
                  </PrincipleCard>

                  <PrincipleCard
                    number="6"
                    title="Semi-Persistent Identity"
                  >
                    You want &ldquo;semi-persistent identity.&rdquo; An identity that can last for the duration of a discrete task but one that can also vanish without a trace and not break things. Agent Mail generates names like &ldquo;ScarletCave&rdquo; and &ldquo;CoralBadger&rdquo; &mdash; meaningful enough for coordination, disposable enough that losing one doesn&rsquo;t corrupt state.
                  </PrincipleCard>
                </SubSection>

                <SubSection title="Security and Generality">
                  <PrincipleCard
                    number="7"
                    title="Security Comes Free with Good Planning"
                  >
                    Security review is baked into the standard workflow at multiple levels rather than being a separate phase you have to remember to run. The cross-agent deep review prompt explicitly calls out security.
                  </PrincipleCard>

                  <P>The cross-agent review prompt (used in Phase 9 and Phase 12) that drives security findings:</P>
                  <CodeBlock language="text" code={`Ok can you now turn your attention to reviewing the code written by your
fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis and
then fix or revise them if necessary? Don't restrict yourself to the latest
commits, cast a wider net and go super deep!`} />

                  <P>That prompt runs repeatedly throughout implementation and produces security findings alongside every other kind of defect. In addition:</P>
                  <BulletList items={[
                    <><Hl>Plan-level security:</Hl> When models reason about an entire system&apos;s architecture at once (which is what the plan enables), they spot authentication gaps, data exposure risks, and trust boundary violations without being told to look for them. These are architectural issues, and architecture review is what planning is.</>,
                    <><Hl>UBS catches security anti-patterns mechanically:</Hl> Unpinned dependencies, missing input validation, hardcoded secrets, unsafe unwraps, and supply chain vulnerabilities are all in UBS&apos;s 1000+ pattern set. Running <IC>ubs &lt;changed-files&gt;</IC> before every commit catches these without relying on agent judgment.</>,
                    <><Hl>Testing-level security:</Hl> Beads that include comprehensive e2e tests naturally cover authentication and authorization paths.</>,
                  ]} />
                  <P highlight>The key insight is that security vulnerabilities are usually symptoms of incomplete reasoning about the system. If the plan is detailed enough to cover all user workflows, edge cases, and failure modes, security considerations emerge from that completeness rather than requiring a separate checklist.</P>
                  <TipBox variant="info">
                    <P><Hl>This is true when:</Hl> the plan covers trust boundaries, auth flows, failure paths, and data exposure risks; cross-agent review and UBS are both part of the normal loop; and the project is not so regulated that explicit security process is mandatory.</P>
                    <P><Hl>A newcomer should not misread this as:</Hl> &ldquo;security needs no deliberate thought.&rdquo; The claim is narrower: the standard Flywheel loop already forces a large amount of security reasoning and security bug detection if you actually run it properly.</P>
                    <P>For projects with explicit security requirements (financial, healthcare, infrastructure), you should add a dedicated security review bead and reference relevant compliance standards in the plan.</P>
                  </TipBox>

                  <PrincipleCard
                    number="8"
                    title="The Prompts Are Deliberately Generic"
                  >
                    &ldquo;My projects all start with a ridiculously detailed plan file which is then turned into beads, so the vagueness in the prompts is a feature, letting me reuse them for every project.&rdquo; The specificity lives in: (1) The beads themselves, (2) AGENTS.md, (3) The codebase. The prompts are reusable scaffolding.
                  </PrincipleCard>
                </SubSection>

                <SubSection title="Agent-First Tooling">
                  <PrincipleCard
                    number="9"
                    title="Tools Must Be Agent-First"
                  >
                    Every tool ships with a prepared AGENTS.md blurb. Tools should be designed by agents, for agents, with iterative feedback. &ldquo;Every new dev tool in the year of our lord 2025 should have a robot mode designed specifically for agents to use.&rdquo;
                  </PrincipleCard>

                  <PrincipleCard
                    number="9b"
                    title="Agent Feedback Forms and Net Promoter Scores"
                  >
                    A surprisingly powerful technique: apply feedback mechanisms like surveys and net promoter scores directly to agents evaluating tools.
                  </PrincipleCard>

                  <P>The feedback prompt (used with UBS as the canonical example):</P>
                  <CodeBlock language="text" code={`Based on your experience with [TOOL] today in this project, how would you
rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was
it helpful to you? Did it flag a lot of useful things that you would have
missed otherwise? Did the issues it flagged have a good signal-to-noise
ratio? What did it do well, and what was it bad at? Did you run into any
errors or problems while using it?

What changes to [TOOL] would make it work even better for you and be more
useful in your development workflow? Would you recommend it to fellow
coding agents? How strongly, and why or why not? The more specific you can
be, and the more dimensions you can score [TOOL] on, the more helpful it
will be for me as I improve it and incorporate your feedback to make [TOOL]
even better for you in the future!`} />
                  <P>This produces structured, actionable feedback. When used across multiple agents working on different project types, you get a diverse sample of experiences. One agent reviewing UBS for a Python ML project said:</P>
                  <BlockQuote>
                    &ldquo;UBS proved to be an extremely high-leverage tool. It successfully shifted my focus from just &lsquo;writing code&rsquo; to &lsquo;engineering robust software.&rsquo; While standard linters (like ruff or clippy) catch syntax and style errors, UBS caught architectural and operational risks&mdash;security holes, supply chain vulnerabilities (unpinned datasets), and runtime stability issues (hangs due to missing timeouts, panics from unwrap).&rdquo;
                  </BlockQuote>
                  <P>The feedback loop closes when you pipe agent reviews directly into another agent working on the tool itself:</P>
                  <BlockQuote>
                    &ldquo;Another satisfied customer! (I&apos;ll be piping that feedback directly into another agent which is working on UBS itself. How&apos;s that for customer responsiveness?). All the complaints it had are very easy to fix.&rdquo;
                  </BlockQuote>
                  <P>This is fundamentally different from traditional user testing because the iteration speed is orders of magnitude faster. You can go from feedback to fix to re-test in minutes, not weeks.</P>
                  <BlockQuote>
                    &ldquo;Many of the same concepts we use for people will be directly applicable to agents. For example,
                    feedback forms and &lsquo;net promoter score&rsquo; (i.e., would you recommend this tool to your fellow agents?). I&apos;m already using this for tools. By robots, for robots.&rdquo;
                  </BlockQuote>
                </SubSection>

                <SubSection title="Compounding and Portability">
                  <PrincipleCard
                    number="10"
                    title="The Flywheel Compounds"
                  >
                    Each session makes the next one better. Session N produces raw data. CASS logs every session. Between sessions, CM distills patterns. Session N+1 starts with those patterns loaded. UBS patterns grow from repeated bugs becoming rules. Agent Mail coordination norms improve through AGENTS.md refinement.
                  </PrincipleCard>

                  <P>The compounding in detail:</P>
                  <BulletList items={[
                    <><Hl>Session N</Hl> produces raw data. CASS logs every session.</>,
                    <><Hl>Between sessions,</Hl> CM distills patterns. Running <IC>cm reflect</IC> processes recent sessions and extracts procedural rules with confidence scores that decay (90-day half-life).</>,
                    <><Hl>Session N+1</Hl> starts with those patterns loaded. <IC>cm context &quot;Building an API&quot;</IC> retrieves relevant procedural memory.</>,
                    <><Hl>UBS patterns</Hl> grow from repeated bugs becoming rules.</>,
                    <><Hl>Agent Mail</Hl> coordination norms improve through <IC>AGENTS.md</IC> refinement.</>,
                  ]} />
                  <TipBox variant="tip">
                    The compounding is real but not automatic early on. You have to actually run <IC>cm reflect</IC>,
                    review CASS data, update <IC>AGENTS.md</IC>. But spending 15 minutes between projects reviewing what
                    worked produces outsized returns.
                  </TipBox>

                  <PrincipleCard
                    number="11"
                    title="Avoid Vendor Lock-In"
                  >
                    Use model-agnostic coordination primitives. Beads, Agent Mail, and bv work identically regardless of which agent invokes them. A Claude agent and Codex agent and Gemini agent can all call br ready --json.
                  </PrincipleCard>

                  <P>
                    Avoid provider-specific task management and communication. Beads live in <IC>.beads/</IC> files
                    readable by any agent. Agent Mail is an MCP server any MCP-capable agent can connect to.
                  </P>
                  <TipBox variant="info">
                    Practical test: could you swap out every Claude agent for Codex without changing <IC>AGENTS.md</IC>,
                    beads, or Agent Mail setup?
                  </TipBox>
                </SubSection>

                <SubSection title="Execution and Self-Improvement">
                  <PrincipleCard
                    number="12"
                    title="The Project Is a Foregone Conclusion"
                  >
                    Once you have the beads in good shape based on a great markdown plan, implementation success is essentially guaranteed. The rest is basically mindless &ldquo;machine tending&rdquo; of your swarm of 5&ndash;15 agents.
                  </PrincipleCard>

                  <P>This claim sounds bold, but it follows logically from everything above. If the plan is thorough (Phase 1&ndash;3), and the beads faithfully encode it with full context and correct dependencies (Phase 4&ndash;5), and the agents have a clear <IC>AGENTS.md</IC> (Phase 6), then implementation becomes a mechanical process of agents picking up beads, implementing them, reviewing, and moving on.</P>

                  <TipBox variant="info">
                    <P><Hl>This is true when:</Hl></P>
                    <BulletList items={[
                      "The plan has genuinely converged rather than merely become long",
                      "The beads are self-contained enough that fresh agents can execute them without guessing",
                      "The swarm has working coordination, review, and testing loops",
                      "The human is still tending the machine when the flow jams or reality diverges from the plan",
                    ]} />
                    <P><Hl>It stops being true when:</Hl></P>
                    <BulletList items={[
                      "The architecture is still being invented during implementation",
                      "The bead graph is thin, vague, or missing dependencies",
                      <>The swarm cannot coordinate cleanly because <IC>AGENTS.md</IC>, Agent Mail, or <IC>bv</IC> usage is weak</>,
                    ]} />
                  </TipBox>

                  <P>What &ldquo;machine tending&rdquo; actually looks like hour by hour:</P>
                  <NumberedList items={[
                    <>Check bead progress (<IC>br list --status in_progress --json</IC> or <IC>bv --robot-triage</IC>). Are agents making steady progress? Are any beads stuck?</>,
                    <>Handle compactions. When you see an agent acting confused or repeating itself, send: &ldquo;Reread AGENTS.md so it&rsquo;s still fresh in your mind.&rdquo; This is the single most common intervention. It takes 5 seconds.</>,
                    <>Run periodic reviews. Every 30&ndash;60 minutes, pick an agent and send the &ldquo;fresh eyes&rdquo; review prompt. This catches bugs before they compound.</>,
                    <>Manage rate limits. When an agent gets rate-limited, switch its account with <IC>caam activate claude backup-2</IC> or start a new agent with <IC>ntm add PROJECT --cc=1</IC>.</>,
                    <>Commit periodically. Every 1&ndash;2 hours, designate one agent to do the organized commit prompt. This keeps the git history clean and ensures all agents see each other&rsquo;s work.</>,
                    <>Handle surprises. Occasionally something comes up during implementation that wasn&rsquo;t anticipated in the plan. Create a new bead for it, or if it&rsquo;s a plan-level issue, update the plan and create new beads.</>,
                  ]} />

                  <P highlight>The key realization is that none of these tasks require deep thought. They&rsquo;re monitoring and maintenance, not design. The hard cognitive work happened during planning. That&rsquo;s why you can tend multiple project swarms simultaneously.</P>

                  <P>When the &ldquo;foregone conclusion&rdquo; breaks down:</P>
                  <BulletList items={[
                    <><Hl>Vague beads:</Hl> agents start improvising, producing inconsistent implementations</>,
                    <><Hl>Missing dependencies:</Hl> agents work on tasks whose prerequisites aren&rsquo;t done yet</>,
                    <><Hl>Thin AGENTS.md:</Hl> agents don&rsquo;t know the project conventions and produce non-idiomatic code</>,
                    <><Hl>No Agent Mail:</Hl> agents step on each other&rsquo;s files without coordination</>,
                  ]} />
                  <P>If you find yourself doing heavy cognitive work during implementation, that&rsquo;s a signal that your planning or bead polishing was insufficient. The remedy is usually to pause implementation, go back to bead space, and add the missing detail.</P>

                  <PrincipleCard
                    number="13"
                    title="Recursive Self-Improvement: The Meta-Skill Pattern"
                  >
                    Your agent toolchain should improve itself using its own output as fuel. Using skills to improve skills, skills to improve tool use, and then feeding the actual experience back into the design skill for improving the tool interface.
                  </PrincipleCard>

                  <P>How to Actually Do This:</P>
                  <NumberedList items={[
                    <><Hl>Build the baseline.</Hl> Create a tool and a skill for it. Ship it.</>,
                    <><Hl>Let agents use it in real work.</Hl> CASS logs every session.</>,
                    <><Hl>Mine the sessions.</Hl> After 10+ sessions, search CASS for sessions where agents invoked the tool. Look for: clarifying questions, repeated mistakes, creative workarounds, outright failures.</>,
                    <><Hl>Feed findings into a rewrite.</Hl> Give session analysis + current skill to a fresh agent. The key insight: this rewriting step itself can be a skill (the meta-skill pattern).</>,
                    <><Hl>Repeat.</Hl> After 3&ndash;4 cycles, the skill is dramatically more reliable.</>,
                  ]} />

                  <TipBox variant="tip">
                    <P>
                      <Hl>The Hidden Knowledge Extraction Principle:</Hl> Models have internalized vast CS literature that
                      never surfaces without precise asking. Skills are the mechanism for asking precisely the right
                      questions. Without a skill: &ldquo;Optimize this function&rdquo; produces generic improvements.
                      With an extreme-optimization skill: the agent considers cache-oblivious data structures, SIMD
                      vectorization, van Emde Boas layout, fractional cascading&hellip;
                    </P>
                    <BlockQuote>
                      &ldquo;The knowledge is just sitting there and the models have it. But you need to know how to coax
                      it out of them.&rdquo;
                    </BlockQuote>
                  </TipBox>

                  <P>The Four Layers of recursive improvement:</P>
                  <BulletList items={[
                    <><Hl>Layer 1:</Hl> Feedback forms after tool use (start here, no infrastructure needed)</>,
                    <><Hl>Layer 2:</Hl> CASS-powered skill refinement (requires session logging)</>,
                    <><Hl>Layer 3:</Hl> Skills that generate work (idea-wizard, optimization skills create new beads)</>,
                    <><Hl>Layer 4:</Hl> Skills bundled with tool installers (refined through multiple CASS cycles before shipping)</>,
                  ]} />
                </SubSection>
              </GuideSection>

              <Divider />

              {/* ==================== SECTION 21: Operationalizing the Method ==================== */}
              <GuideSection id="operationalizing" number="21" title="Operators & Validation Gates" icon={<Cog className="h-5 w-5" />}>
                <P highlight>
                  This is the layer that turns CASS-mined rituals into skills, skills into <IC>AGENTS.md</IC> blurbs,
                  and those blurbs into more deterministic swarm behavior.
                </P>

                <SubSection title="The First-Pass Kernel">
                  <P>Nine axioms that anchor the entire method:</P>
                  <NumberedList items={[
                    <>Global reasoning belongs in plan space.</>,
                    <>The markdown plan must be comprehensive before coding starts.</>,
                    <>Plan-to-beads is a distinct translation problem.</>,
                    <>Beads are the execution substrate.</>,
                    <>Convergence matters more than first drafts.</>,
                    <>Swarm agents are fungible.</>,
                    <>Coordination must survive crashes and compaction.</>,
                    <>Session history is part of the system.</>,
                    <>Implementation is not the finish line.</>,
                  ]} />
                </SubSection>

                <SubSection title="Operator Library">
                  <P>
                    The recurring moves below show up throughout real Flywheel sessions. These operators matter more than
                    any single prompt because they say <Hl>when</Hl> to apply a move, what <Hl>failure</Hl> looks like,
                    and what output is expected.
                  </P>

                  <OperatorCard
                    number="1"
                    name="Plan-First Expansion"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Project fits in plan but would explode once implemented; multiple architectural paths; fuzzy user workflow"
                    failureMode="Skeleton-first coding, local code exploration as substitute for product reasoning"
                  >
                    Expand the full system design at the plan level before writing any code. Reason about architecture,
                    data flow, and user workflows entirely in the markdown plan where the full picture fits in context.
                  </OperatorCard>

                  <OperatorCard
                    number="2"
                    name="Competing-Plan Triangulation"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Project important enough that one model&rsquo;s biases are dangerous; want broader search"
                    failureMode="Picking first decent plan; combining every idea indiscriminately"
                  >
                    Ask 3+ competing LLMs to produce independent plans, then synthesize the best elements into a superior
                    hybrid version through careful analysis.
                  </OperatorCard>

                  <OperatorCard
                    number="3"
                    name="Overshoot Mismatch Hunt"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Review output too short; model stopped after &ldquo;reasonable&rdquo; number of problems"
                    failureMode="Asking for &ldquo;all problems&rdquo; and getting shallow pass"
                  >
                    Deliberately overshoot expectations. Tell the model you&rsquo;re &ldquo;positive it missed at least 80
                    elements&rdquo; to break conservative output ceilings and force exhaustive review.
                  </OperatorCard>

                  <OperatorCard
                    number="4"
                    name="Plan-to-Beads Transfer Audit"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Large plan being turned into tasks; agents creating beads quickly"
                    failureMode="Assuming beautiful plan implies good beads; creating terse beads"
                  >
                    Systematically verify every plan element maps to a bead and every bead traces back to the plan.
                    Check both directions to prevent features from disappearing during conversion.
                  </OperatorCard>

                  <OperatorCard
                    number="5"
                    name="Convergence Polish Loop"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Plan or bead graph has visible rough edges; first polishing found real issues"
                    failureMode="Treating first revision as final; endless polishing after returns go flat"
                  >
                    Iterate 4&ndash;6 polishing passes on beads, checking for correctness, completeness, and
                    self-containedness. Stop when passes stop finding substantive issues.
                  </OperatorCard>

                  <OperatorCard
                    number="6"
                    name="Fresh-Eyes Reset"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Agent has done several long review rounds; suggestions repetitive"
                    failureMode="Trusting tired context window; mistaking exhaustion for convergence"
                  >
                    Start a completely new session with a fresh agent. Have it read <IC>AGENTS.md</IC> and
                    <IC>README.md</IC> from scratch, then review the work with no prior context.
                  </OperatorCard>

                  <OperatorCard
                    number="7"
                    name="Fungible Swarm Launch"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Beads polished enough; multiple agents in same repo"
                    failureMode="Launching before beads self-contained; role specialization becoming load-bearing"
                  >
                    Launch agents with identical init prompts, staggered 30&ndash;60 seconds apart. Ensure Agent Mail,
                    <IC>bv</IC>, and <IC>AGENTS.md</IC> are ready before starting.
                  </OperatorCard>

                  <OperatorCard
                    number="8"
                    name="Feedback-to-Infrastructure Closure"
                    definition="Recurring cognitive move in the Flywheel methodology"
                    trigger="Same confusion appears repeatedly in CASS; project finishes with clear lessons"
                    failureMode="Treating lessons as anecdotes; improving code but never improving the method"
                  >
                    Mine CASS for repeated patterns, distill them into skills or <IC>AGENTS.md</IC> updates, and close
                    the loop so the next project starts with those improvements baked in.
                  </OperatorCard>
                </SubSection>

                <SubSection title="Validation Gates">
                  <DataTable
                    headers={["Gate", "Must Be True", "Failure If Skipped"]}
                    rows={[
                      ["Foundation", "Goals, workflows, stack, AGENTS.md exist and coherent", "Plan absorbs ambiguity \u2192 confused agents"],
                      ["Plan", "Plan covers workflows, architecture, testing, failure paths", "Agents improvise architecture"],
                      ["Translation", "Every plan element maps to beads, checked both directions", "Features disappear during conversion"],
                      ["Bead", "Beads self-contained, dependency-correct, rich context", "Swarm depends on reopening plan"],
                      ["Launch", "Agent Mail, bv, AGENTS.md, staggered startup ready", "Agents collide and duplicate work"],
                      ["Ship", "Reviews, tests, UBS, feedback capture complete", "Code ships but method doesn\u2019t improve"],
                    ]}
                  />
                </SubSection>

                <SubSection title="Anti-Patterns">
                  <BulletList items={[
                    <><Hl>Verbosity mistaken for completeness</Hl> &mdash; long output does not mean thorough output</>,
                    <><Hl>First-draft beads treated as ready</Hl> &mdash; beads always need 4&ndash;6 polishing passes</>,
                    <><Hl>Hidden rationale</Hl> &mdash; design decisions only in plan, not carried to beads</>,
                    <><Hl>Cargo-cult prompts</Hl> &mdash; copying prompts without understanding trigger and failure mode</>,
                    <><Hl>Load-bearing agents</Hl> &mdash; any agent whose loss would stall the project</>,
                    <><Hl>Phase skipping</Hl> &mdash; jumping to implementation before plan and beads are solid</>,
                    <><Hl>No closure loop</Hl> &mdash; finishing the project without feeding lessons back into the method</>,
                  ]} />
                </SubSection>

                <SubSection title="How CASS, Skills, AGENTS.md, and Validators Fit Together">
                  <BulletList items={[
                    <><Hl>CASS</Hl> discovers repeated prompts, recurring breakdowns, successful recoveries</>,
                    <><Hl>Skills</Hl> package operators and anti-patterns into reusable workflows</>,
                    <><Hl>AGENTS.md</Hl> carries the compressed operating subset every agent must keep after compaction</>,
                    <><Hl>Validators</Hl> turn gates into scripts, checklists, or CI-enforced contracts</>,
                  ]} />
                  <TipBox variant="info">
                    That is the real progression: repeated behavior becomes ritual, ritual becomes skill, skill becomes
                    infrastructure, infrastructure changes what the next swarm can do.
                  </TipBox>
                </SubSection>
              </GuideSection>

              <Divider />

              {/* ==================== SECTION 22: Observed Patterns and Lessons ==================== */}
              <GuideSection id="patterns" number="22" title="Observed Patterns and Lessons" icon={<Target className="h-5 w-5" />}>
                <SubSection title="Patterns That Work">
                  <P highlight>
                    The <Hl>&ldquo;30 to 5 to 15&rdquo; funnel:</Hl> brainstorm 30, winnow to 5 &mdash; much better
                    than asking for 5 directly. The winnowing forces critical evaluation.
                  </P>
                  <BulletList items={[
                    <><Hl>Parallel subagents for bulk bead operations:</Hl> Creating dozens of beads faster when dispatched to parallel subagents. Used in FrankenSQLite and alien_cs_graveyard.</>,
                    <><Hl>Staggered agent starts:</Hl> 30&ndash;60 seconds apart avoids thundering herd.</>,
                    <><Hl>One agent for git operations:</Hl> prevents merge conflicts, coherent commits.</>,
                  ]} />
                </SubSection>

                <SubSection title="Anti-Patterns to Avoid">
                  <BulletList items={[
                    <><Hl>Single-pass beads:</Hl> First-draft beads are never optimal. 4&ndash;5 polishing passes minimum.</>,
                    <><Hl>Skipping plan-to-bead validation:</Hl> missing features discovered only during implementation.</>,
                    <><Hl>Communication purgatory:</Hl> agents spending more time messaging than coding. Be proactive about starting work.</>,
                    <><Hl>Holding reservations too long:</Hl> long TTLs block other agents. Reserve, edit, commit, release.</>,
                    <><Hl>Not re-reading AGENTS.md after compaction:</Hl> mandatory, not optional.</>,
                  ]} />
                </SubSection>

                <SubSection title="Scale Observations">
                  <DataTable
                    headers={["Project", "Beads", "Plan Lines", "Agents", "Time to MVP"]}
                    rows={[
                      ["CASS Memory System", "347+", "5,500", "~25", "~5 hours"],
                      ["FrankenSQLite", "Hundreds", "Large spec", "Many parallel", "Multi-session"],
                      ["Frankensearch", "122+ (3 epics)", "\u2014", "Multiple", "Multi-session"],
                      ["Apollobot", "26", "\u2014", "Single session", "2\u20133 polish rounds"],
                    ]}
                  />
                </SubSection>

                <SubSection title="Ritual Detection via CASS">
                  <P>
                    CASS enables ritual detection &mdash; discovering prompts repeated so frequently they constitute
                    validated methodology:
                  </P>
                  <DataTable
                    headers={["Repetition Count", "Status", "Action"]}
                    rows={[
                      ["count \u2265 10", "RITUAL", "Validated methodology. Extract into skill."],
                      ["count 5\u20139", "Emerging pattern", "Worth investigating further"],
                      ["count < 5", "One-off", "Not generalizable yet"],
                    ]}
                  />

                  <P>The mining query:</P>
                  <CodeBlock language="bash" code={`cass search "*" --workspace /data/projects/PROJECT --json --fields minimal --limit 500 \\
                | jq '[.hits[] | select(.line_number <= 3) | .title[0:80]]
                      | group_by(.) | map({prompt: .[0], count: length})
                      | sort_by(-.count) | map(select(.count >= 5)) | .[0:30]'`} />

                  <TipBox variant="info">
                    This is how the prompt library was originally discovered &mdash; mined bottom-up from hundreds
                    of real sessions, not invented top-down.
                  </TipBox>
                </SubSection>

                <SubSection title="Common Problems">
                  <NumberedList items={[
                    <><Hl>Agent Mail CLI availability:</Hl> Sometimes binary not at expected path; agents fall back to REST API</>,
                    <><Hl>Context window exhaustion:</Hl> Agents manage 2&ndash;3 polishing passes before needing fresh session</>,
                    <><Hl>Duplicate beads at scale:</Hl> 100+ beads develop duplicates; dedicated dedup passes necessary</>,
                    <><Hl>Plan-bead gap:</Hl> Synthesis stalls between plan revision and bead creation; always explicitly transition</>,
                  ]} />
                </SubSection>
              </GuideSection>

              <Divider />

              {/* ==================== SECTION 23: Practical Considerations ==================== */}
              <GuideSection id="practical" number="23" title="Practical Considerations" icon={<Rocket className="h-5 w-5" />}>
                <SubSection title="The Incremental Onboarding Path">
                  <P>
                    This is the learning order, not the ideal order inside a serious project. There is also no single
                    correct session-management layer &mdash; NTM, tmux directly, WezTerm, or another setup.
                  </P>
                  <NumberedList items={[
                    <>Start with: <ToolPill>Agent Mail</ToolPill> + <ToolPill>Beads (br)</ToolPill> + <ToolPill>Beads Viewer (bv)</ToolPill></>,
                    <>Add: <ToolPill>UBS</ToolPill> for bug hunting</>,
                    <>Add: <ToolPill>DCG</ToolPill> for destructive command protection</>,
                    <>Add: <ToolPill>CASS</ToolPill> for session history</>,
                    <>Add: <ToolPill>CM</ToolPill> for codifying lessons</>,
                  ]} />

                  <P>Common beginner mistakes:</P>
                  <BulletList items={[
                    <><Hl>Slipshod plan:</Hl> making a hasty plan with Claude Code instead of multi-model iterative process</>,
                    <><Hl>One-shot beads:</Hl> trying to convert plan to beads in single pass</>,
                    <><Hl>Skipping polishing:</Hl> not doing at least 3 rounds of checking and expanding beads</>,
                  ]} />
                </SubSection>

                <SubSection title="Cost">
                  <BulletList items={[
                    <>~$500/month for Claude Max and GPT Pro subscriptions</>,
                    <>~$50/month for a cloud server</>,
                    <>Multiple Max accounts may be needed for large swarms</>,
                    <><ToolPill>CAAM</ToolPill> enables instant switching when hitting rate limits</>,
                  ]} />
                  <TipBox variant="info">
                    At scale: &ldquo;I have 14 Claude Max accounts and 7 GPT Pro accounts now.&rdquo; Token usage for a
                    single intensive session: ~20M input, ~3.5M output, ~2.6M reasoning, ~1.15 billion cached reads.
                  </TipBox>
                </SubSection>

                <SubSection title="Time Investment">
                  <BulletList items={[
                    <><Hl>Planning phase:</Hl> 3+ hours for a complex feature</>,
                    <><Hl>Plan to beads:</Hl> significant time (&ldquo;Claude needed coaxing and cajoling&rdquo; for 347 beads)</>,
                    <><Hl>Bead polishing:</Hl> 2&ndash;3 passes per session</>,
                    <><Hl>Implementation:</Hl> with a good swarm, remarkably fast. CASS Memory went from nothing to 11k lines in ~5 hours</>,
                  ]} />
                </SubSection>

                <SubSection title="Live Status Update (From a Real Session)">
                  <BlockQuote>
                    &ldquo;Starting from absolutely nothing ~5 hours ago except a big plan document, I turned that into
                    over 350 beads, I now have ~11k lines of code, about 8k core code and rest testing. Around 204
                    commits. Probably at least 25 agents involved. For a &lsquo;can I use this tool effectively&rsquo;
                    definition: ~85&ndash;90% done.&rdquo;
                  </BlockQuote>
                </SubSection>

                <SubSection title="What This Approach Can Produce">
                  <BlockQuote>
                    &ldquo;If you simply use these tools, workflows, and prompts in the way I just described, you can
                    create really incredible software in just a couple days, sometimes in just one day.&rdquo;
                  </BlockQuote>
                  <BlockQuote>
                    &ldquo;You see my GitHub profile for the proof. It looks like the output from a team of 100+
                    developers.&rdquo;
                  </BlockQuote>
                </SubSection>

                <SubSection title="Getting Started">
                  <P>
                    The complete system is free and 100% open-source: <Hl>https://agent-flywheel.com/</Hl>
                  </P>
                  <BlockQuote>
                    &ldquo;You don&rsquo;t even need to know much at all about computers; you just need the desire to
                    learn and some grit and determination.&rdquo;
                  </BlockQuote>

                  <CodeBlock language="bash" code={`# 1. Rent a VPS (~$40-56/month, Ubuntu)
              # 2. SSH in
              ssh ubuntu@your-server-ip

              # 3. Run the one-liner
              curl -fsSL https://agent-flywheel.com/install.sh | bash

              # 4. Reconnect (if was root)
              ssh ubuntu@your-server-ip

              # 5. Learn the workflow
              onboard

              # 6. Create your first project
              acfs newproj my-first-project --interactive

              # 7. Spawn agents
              ntm spawn my-first-project --cc=2 --cod=1 --gmi=1

              # 8. Start building!
              ntm send my-first-project "Let's build something awesome."`} />
                </SubSection>
              </GuideSection>

              <Divider />

              {/* ==================== SECTION 24: The Complete Prompt Library ==================== */}
              <GuideSection id="prompt-library" number="24" title="The Complete Prompt Library" icon={<ScrollText className="h-5 w-5" />}>
                <P highlight>
                  Treat the prompt blocks below as canonical wording. Some contain quirks or typos preserved verbatim
                  from prompts that worked well in real sessions.
                </P>
                <P>
                  For a larger public prompt collection, see <Hl>jeffreysprompts.com</Hl> (generous free section,
                  open source). Also has a paid Pro tier with a CLI called <ToolPill>jfp</ToolPill>. For skills:
                  <Hl> jeffreys-skills.md</Hl> ($20/month) with curated skills and a CLI called <ToolPill>jsm</ToolPill>.
                  Both paid offerings are under active development.
                </P>

                <SubSection title="Planning Prompts">
                  <PromptBlock
                    title="Plan Creation: Multi-Model Synthesis"
                    prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan):`}
                    where="GPT Pro web app with Extended Reasoning"
                  />

                  <PromptBlock
                    title="Plan Refinement: Iterative Improvement"
                    prompt={`Carefully review this entire plan for me and come up with your best revisions in terms of better architecture, new features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc. For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style changes relative to the original markdown plan shown below:\n\n<PASTE YOUR EXISTING COMPLETE PLAN HERE>`}
                    where="GPT Pro web app, fresh conversation each round"
                  />

                  <PromptBlock
                    title="Plan Refinement: Integration"
                    prompt={`OK, now integrate these revisions to the markdown plan in-place; be meticulous. At the end, you can tell me which changes you wholeheartedly agree with, which you somewhat agree with, and which you disagree with:\n\n[Pasted GPT Pro output]`}
                    where="Claude Code"
                  />

                  <PromptBlock
                    title="Plan Refinement: The 'Lie to Them' Exhaustive Check"
                    prompt={`Do this again, and actually be super super careful: can you please check over the plan again and compare it to all that feedback I gave you? I am positive that you missed or screwed up at least 80 elements of that complex feedback.`}
                    where="During plan revision, when initial comparison finds only ~20 issues"
                    whyItWorks="Deliberately overshoots expectations. The claim of '80 elements' forces the model past conservative output ceilings into genuinely exhaustive review."
                  />
                </SubSection>

                <SubSection title="Bead Prompts">
                  <PromptBlock
                    title="Plan to Beads: Conversion"
                    prompt={`OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never nead to consult back to the original markdown plan document. Remember to ONLY use the \`br\` tool to create and modify the beads and add the dependencies.`}
                    where="Claude Code (Opus)"
                    whyItWorks="Forces agent to treat plan-to-beads as a translation problem. The key sentence about never needing to reopen the plan pushes rationale, test expectations, design intent, and sequencing into the bead graph itself. Restricting to br prevents drifting into pseudo-beads in markdown."
                  />

                  <PromptBlock
                    title="Beads: Iterative Polishing"
                    prompt={`Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the \`br\` cli tool for all changes, and you can and should also use the \`bv\` tool to help diagnose potential problems with the beads.`}
                    where="Claude Code (Opus), usually 4-6 rounds across one or more fresh sessions"
                    whyItWorks="Keeps system from freezing beads too early. Tells the model to stay in plan space for as long as it is still finding meaningful improvements. The warnings against oversimplifying and losing functionality are crucial because models otherwise tend to 'improve' artifacts by deleting complexity they do not fully understand. Combines local bead QA with graph QA via bv."
                  />

                  <PromptBlock
                    title="Beads: Deduplication Check"
                    prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over ALL open beads. Make sure none of them are duplicative or excessively overlapping... try to intelligently and cleverly merge them into single canonical beads that best exemplify the strengths of each.`}
                    where="After large bead creation batches"
                  />

                  <PromptBlock
                    title="Beads: Fresh Eyes Review"
                    prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project.\n\n[Then in follow-up:]\n\nWe recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using \`br\` and \`bv\`.`}
                    where="New Claude Code session"
                  />
                </SubSection>

                <SubSection title="Implementation Prompts">
                  <PromptBlock
                    title="Implementation: Agent Marching Orders"
                    prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents. Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. *CRITICAL*: All cargo builds and tests and other CPU intensive operations MUST be done using rch to offload them!!! see AGENTS.md for details on how to do this!!!`}
                    where="Every agent in the swarm (via ntm send)"
                    whyItWorks="Front-loads shared context, forces Agent Mail registration, pivots from passive waiting to execution. The line about 'communication purgatory' matters because swarm failure often comes from over-coordination rather than under-coordination. The rch requirement externalizes expensive builds, preventing local CPU contention from degrading the multi-agent system."
                  />

                  <PromptBlock
                    title="Context Recovery: Post-Compaction"
                    prompt={`Reread AGENTS.md so it's still fresh in your mind.`}
                    where="Immediately after any context compaction (the single most commonly used prompt)"
                    whyItWorks="Compaction wipes out the soft operational knowledge that keeps the swarm sane: how to behave, how to coordinate, what tools exist, what rules matter, and what kinds of mistakes to avoid. The reread prompt restores that control plane in one move. Important enough that the reminder has been automated with /dp/post_compact_reminder."
                  />

                  <PromptBlock
                    title="Execution: Ad-Hoc TODO Mode"
                    prompt={`OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!`}
                    where="Quick, bounded changes that are not worth full bead formalization upfront"
                    whyItWorks="Forces the agent to externalize its local execution plan into a durable checklist instead of juggling a sprawling ad-hoc task in conversational memory. In tools that support a built-in TODO system, that checklist survives compaction. When not to use it: if the change is expanding, depends on other work, needs graph-aware sequencing, or should be part of the permanent project record, stop and turn it into proper beads instead."
                  />

                  <PromptBlock
                    title="Navigation: Move to Next Bead"
                    prompt={`Reread AGENTS.md so it's still fresh in your mind. Use bv with the robot flags (see AGENTS.md for info on this) to find the most impactful bead(s) to work on next and then start on it. Remember to mark the beads appropriately and communicate with your fellow agents. Pick the next bead you can actually do usefully now and start coding on it immediately; communicate what you're working on to your fellow agents and mark beads appropriately as you work. And respond to any agent mail messages you've received.`}
                    where="After reviews come up clean"
                  />

                  <PromptBlock
                    title="Committing: Organized Git Operations"
                    prompt={`Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files.`}
                    where="Periodically during implementation"
                  />
                </SubSection>

                <SubSection title="Review and Testing Prompts">
                  <PromptBlock
                    title="Swarm Diagnosis: High-Level Reality Check"
                    prompt={`Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open beads, would we close that gap completely?`}
                    where="When swarm looks active but you suspect strategic drift"
                    whyItWorks="Breaks the spell of local productivity. Compares real state against actual goal."
                  />

                  <PromptBlock
                    title="Review: Self-Review"
                    prompt={`great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.`}
                    where="Each agent after completing a bead"
                    whyItWorks="The phrase 'fresh eyes' is doing real work. It pushes the model to reframe just-written code as something potentially wrong, confusing, or internally inconsistent. That reduces the common pattern where an agent stops once the code compiles and never performs the immediate low-cost bug sweep."
                  />

                  <PromptBlock
                    title="Review: Cross-Agent Review"
                    prompt={`Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!`}
                    where="Periodically during implementation"
                    whyItWorks="Forces the swarm to stop treating code ownership as sacred. The instruction not to restrict review to the latest commits prevents shallow PR-style skimming and pushes the agent to trace older surrounding code, dependency surfaces, and adjacent workflows where the real root cause may live. The first-principles wording nudges the reviewer away from symptom-fixing toward actual causal diagnosis."
                  />

                  <PromptBlock
                    title="Review: Catch-All Oversight"
                    prompt={`Great. Look over everything again for any obvious oversights or omissions or mistakes, conceptual errors, blunders, etc.`}
                    where="After any significant change, as a quick final sanity check"
                  />

                  <PromptBlock
                    title="Testing: Coverage Check"
                    prompt={`Do we have full unit test coverage without using mocks/fake stuff? What about complete e2e integration test scripts with great, detailed logging? If not, then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid with detailed comments.`}
                    where="After all implementation beads completed"
                  />

                  <PromptBlock
                    title="Bug Hunting: Random Exploration"
                    prompt={`I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.`}
                    where="Periodically during implementation"
                    whyItWorks="Breaks the locality trap. Random exploration forces the agent to sample the codebase in a broader way, follow import and execution edges, and reconstruct workflows from the code outward. The prompt first asks the agent to build a mental model of purpose and flow, then asks for criticism. That ordering catches logic errors, mismatched assumptions, and silent product-level breakage. Alternate this with the cross-agent review prompt for better coverage."
                  />
                </SubSection>

                <SubSection title="UI/UX Prompts">
                  <PromptBlock
                    title="UI/UX: General Polish"
                    prompt={`Great, now I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you, things that could very obviously be improved from a user-friendliness and intuitiveness standpoint, places where our UI/UX could be improved and polished to be slicker, more visually appealing, and more premium feeling and just ultra high quality, like Stripe-level apps.`}
                    where="After core implementation complete"
                  />

                  <PromptBlock
                    title="UI/UX: Platform-Specific Deep Polish"
                    prompt={`I still think there are strong opportunities to enhance the UI/UX look and feel and to make everything work better and be more intuitive, user-friendly, visually appealing, polished, slick, and world class in terms of following UI/UX best practices like those used by Stripe, don't you agree? And I want you to carefully consider desktop UI/UX and mobile UI/UX separately while doing this and hyper-optimize for both separately to play to the specifics of each modality. I'm looking for true world-class visual appeal, polish, slickness, etc. that makes people gasp at how stunning and perfect it is in every way.`}
                    where="After initial UI/UX polish pass"
                  />
                </SubSection>

                <SubSection title="CASS Memory and Continuous Improvement Prompts">
                  <PromptBlock
                    title="CASS Memory: Context Retrieval"
                    prompt={`cm context "Building an API" --json   # Get relevant memories
              cm recall "authentication patterns"   # Search past sessions
              cm reflect                            # Update procedural memory
              cm mark b-8f3a2c --helpful            # Reinforce useful rule
              cm mark b-xyz789 --harmful --reason "Caused regression"`}
                    where="Between sessions or at session start"
                  />

                  <P>
                    CM implements a three-layer memory architecture:
                  </P>
                  <BulletList items={[
                    <><Hl>EPISODIC MEMORY (cass):</Hl> Raw session logs</>,
                    <><Hl>WORKING MEMORY (Diary):</Hl> Structured summaries</>,
                    <><Hl>PROCEDURAL MEMORY (Playbook):</Hl> Distilled rules with confidence scores</>,
                  ]} />
                  <P>
                    Rules have 90-day confidence half-life and 4x harmful multiplier. Stages:
                    candidate &rarr; established &rarr; proven.
                  </P>

                  <PromptBlock
                    title="Idea-Wizard: Generate Ideas"
                    prompt={`Come up with 30 ideas for improvements, enhancements, new features for this project. Then winnow to your VERY best 5 and explain why.\n\n[Then:] ok and your next best 10 and why.`}
                    where="For existing projects needing new features"
                  />

                  <PromptBlock
                    title="Meta-Skill: Skill Refinement via CASS Mining"
                    prompt={`Search CASS for all sessions where agents used the [SKILL] skill. Look for: patterns of confusion, repeated mistakes, steps agents skipped, workarounds they invented, and things they did that weren't in the skill but should be.\n\nThen rewrite the skill to fix every issue you found. Make the happy path obvious, add guardrails for the common mistakes, and incorporate the best workarounds as official steps. Test the rewritten skill against the failure cases from the session logs.`}
                    where="Claude Code, targeting any skill with 10+ CASS sessions of usage data. This is the meta-skill pattern in action."
                  />
                </SubSection>

                <SubSection title="Documentation and Feedback Prompts">
                  <PromptBlock
                    title="README: The README Reviser"
                    prompt={`OK, we have made tons of recent changes that aren't yet reflected in the README file. First, reread AGENTS.md so it's still fresh in your mind. Now, we need to revise the README for these changes (don't write about them as "changes" however, make it read like it was always like that, since we don't have any users yet!). Also, what else can we put in there to make the README longer and more detailed about what we built, why it's useful, how it works, the algorithms/design principles used, etc? This should be incremental NEW content, not replacement for what is there already.`}
                    where="After significant implementation work"
                  />

                  <PromptBlock
                    title="Documentation: De-Slopify"
                    prompt={`I want you to read through the complete text carefully and look for any telltale signs of "AI slop" style writing; one big tell is the use of emdash. You should try to replace this with a semicolon, a comma, or just recast the sentence accordingly so it sounds good while avoiding emdash.\n\nAlso, you want to avoid certain telltale writing tropes, like sentences of the form "It's not [just] XYZ, it's ABC" or "Here's why" or "Here's why it matters:". Basically, anything that sounds like the kind of thing an LLM would write disproportionately more commonly than a human writer and which sounds inauthentic/cringe.\n\nAnd you can't do this sort of thing using regex or a script, you MUST manually read each line of the text and revise it manually in a systematic, methodical, diligent way.`}
                    where="After agents write README or user-facing documentation"
                  />

                  <PromptBlock
                    title="Tool Feedback: Agent Satisfaction Survey"
                    prompt={`Based on your experience with [TOOL] today in this project, how would you rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was it helpful to you? Did it flag a lot of useful things that you would have missed otherwise? Did the issues it flagged have a good signal-to-noise ratio? What did it do well, and what was it bad at? Did you run into any errors or problems while using it?\n\nWhat changes to [TOOL] would make it work even better for you and be more useful in your development workflow? Would you recommend it to fellow coding agents? How strongly, and why or why not? The more specific you can be, and the more dimensions you can score [TOOL] on, the more helpful it will be for me as I improve it and incorporate your feedback to make [TOOL] even better for you in the future!`}
                    where="After agents have used a tool extensively in a real project. Pipe the output into another agent working on the tool itself for immediate improvements."
                  />
                </SubSection>

                <TipBox variant="info">
                  Synthesized from ~75+ substantive X posts by @doodlestein (Jeffrey Emanuel) mined via <IC>xf</IC> archive
                  search, the Agentic Coding Flywheel Setup documentation, and real-world usage patterns from CASS.
                </TipBox>
              </GuideSection>

              <Divider />

                                          {/* Footer CTA */}
              <FooterCTA />
            </div>

            {/* Sticky TOC - desktop only */}
            <aside className="hidden lg:block w-72 shrink-0 relative">
              <div 
                className="sticky top-24 max-h-[calc(100vh-8rem)] overflow-y-auto pl-8 pb-12 border-l border-white/[0.05] scrollbar-hide"
                style={{ 
                  maskImage: 'linear-gradient(to bottom, black 80%, transparent 100%)',
                  WebkitMaskImage: 'linear-gradient(to bottom, black 80%, transparent 100%)' 
                }}
              >
                <p className="text-[10px] font-semibold text-primary/70 uppercase tracking-[0.2em] mb-8 px-3">
                  Navigation
                </p>
                <TableOfContents items={TOC_ITEMS} />
              </div>
            </aside>
          </div>
        </div>
      </main>
    </ErrorBoundary>
  );
}

// =============================================================================
// FOOTER CTA
// =============================================================================
const INSTALL_COMMAND = `curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe`;

function FooterCTA() {
  const [copied, setCopied] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const handleCopy = useCallback(async () => {
    const ok = await copyTextToClipboard(INSTALL_COMMAND);
    if (!ok) return;
    setCopied(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setCopied(false);
      timerRef.current = null;
    }, 2000);
  }, []);

  return (
    <section className="border-t border-border/50 py-12 md:py-16">
      <div className="mx-auto text-center">
        <h2 className="text-xl font-bold text-white sm:text-2xl md:text-3xl">
          Get the Complete Flywheel Stack
        </h2>
        <p className="mx-auto mt-4 max-w-xl text-sm text-muted-foreground sm:text-base">
          One command installs all 11 tools, three AI coding agents, and the
          complete agentic coding environment. 30 minutes to fully configured.
        </p>
        <div className="mt-6 flex flex-col items-center gap-4">
          <div className="group relative w-full max-w-5xl">
            <div className="overflow-x-auto rounded-xl bg-card/80 ring-1 ring-border/50 transition-all duration-200 hover:ring-primary/30">
              <div className="flex items-center justify-between gap-4 px-4 py-3 sm:px-6 sm:py-4">
                <code className="flex-1 whitespace-nowrap font-mono text-xs text-primary sm:text-sm">
                  {INSTALL_COMMAND}
                </code>
                <button
                  onClick={handleCopy}
                  className="flex-shrink-0 rounded-lg bg-secondary p-2 text-muted-foreground transition-all duration-200 hover:bg-primary hover:text-white active:scale-95"
                  aria-label={copied ? "Copied!" : "Copy to clipboard"}
                >
                  {copied ? (
                    <Check className="h-4 w-4 text-success" />
                  ) : (
                    <Copy className="h-4 w-4" />
                  )}
                </button>
              </div>
            </div>
          </div>
          <p className="text-xs text-muted-foreground">
            Or use the{" "}
            <a
              href="/wizard/os-selection"
              className="text-primary underline hover:text-primary/80"
            >
              step-by-step wizard
            </a>{" "}
            for guided setup.
          </p>
        </div>
      </div>
    </section>
  );
}
