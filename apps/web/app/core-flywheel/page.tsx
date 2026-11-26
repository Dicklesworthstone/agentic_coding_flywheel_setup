import { Bug, Search, Shield } from "lucide-react";
import Link from "next/link";
import { Fragment } from "react";
import { CoordinationTrioViz } from "@/components/complete-guide/coordination-trio-viz";

import {
  BlockQuote,
  BulletList,
  CodeBlock,
  DataTable,
  GuideArticle,
  GuideNav,
  GuideSection,
  Hl,
  NumberedList,
  P,
  PromptBlock,
  SubSection,
  TipBox,
} from "@/components/complete-guide/guide-components";
import { GuideColophon, GuideFooterCTA, GuideHero } from "@/components/complete-guide/guide-shell";
import { ArtifactLadderViz } from "@/components/core-flywheel/artifact-ladder-viz";
import { BeadComparisonViz } from "@/components/core-flywheel/bead-comparison-viz";
import { CoreLoopDiagram } from "@/components/core-flywheel/core-loop-diagram";
import { HumanAgentTimelineViz } from "@/components/core-flywheel/human-agent-timeline-viz";
import { OperatingRhythmViz } from "@/components/core-flywheel/operating-rhythm-viz";
import { SwarmChaosViz } from "@/components/core-flywheel/swarm-chaos-viz";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import { COMPLETE_GUIDE_MODELS } from "@/lib/complete-guide";
import {
  CORE_FLYWHEEL_OUTLINE,
  CORE_FLYWHEEL_PROMPT_COUNT,
  CORE_FLYWHEEL_REVIEWED_ON,
  guidePartCount,
} from "@/lib/guide-outlines";

export default function CoreFlywheelPage() {
  return (
    <ErrorBoundary>
      <main
        id="main-content"
        tabIndex={-1}
        className="text-aa-floor min-h-screen bg-[#020408] pb-24 outline-none selection:bg-[#FF5500]/25 selection:text-white overflow-x-clip sm:pb-32"
      >
        <GuideHero
          current="core"
          eyebrow="Start here · The core flywheel"
          title={
            <>
              The Core <em className="italic text-[#FF5500]">Flywheel</em>
            </>
          }
          dek={
            <>
              Three tools, one loop, most of the value. The beginner-friendly core of the Agentic
              Coding Flywheel: Agent Mail for coordination, br for task structure, and bv for
              deciding what to work on next.
            </>
          }
          primary={{ href: "#why", label: "Start reading" }}
          secondary={{ href: "/wizard/os-selection", label: "Set up the stack" }}
          note={
            <>
              Already comfortable with the loop?{" "}
              <Link
                href="/complete-guide"
                className="font-medium text-zinc-200 underline decoration-[#FF5500]/60 underline-offset-4 transition-colors hover:text-white"
              >
                Read the complete guide
              </Link>{" "}
              for the full methodology.
            </>
          }
          stats={[
            { value: String(guidePartCount(CORE_FLYWHEEL_OUTLINE)), label: "Parts" },
            { value: "3", label: "Core tools" },
            { value: String(CORE_FLYWHEEL_PROMPT_COUNT), label: "Copy-ready prompts" },
          ]}
          contents={CORE_FLYWHEEL_OUTLINE}
          promptCount={CORE_FLYWHEEL_PROMPT_COUNT}
        />

        <div className="relative mx-auto max-w-[1320px] px-5 sm:px-8 xl:grid xl:grid-cols-[14.5rem_minmax(0,1fr)] xl:gap-14 xl:px-10 2xl:grid-cols-[16rem_minmax(0,1fr)] 2xl:gap-20">
          <GuideNav
            items={CORE_FLYWHEEL_OUTLINE}
            title="The core flywheel"
            promptCount={CORE_FLYWHEEL_PROMPT_COUNT}
          />
          <GuideArticle outline={CORE_FLYWHEEL_OUTLINE}>
          {/* ============================================================= */}
          {/* SECTION 1: WHY THE CORE LOOP                                   */}
          {/* ============================================================= */}
          <GuideSection id="why">
            <P highlight>
              The full Flywheel has grown large enough that many people find it overwhelming at
              first, and that reaction makes sense. But a much smaller core captures most of what
              makes the approach work.
            </P>

            <P>
              The larger system adds planning workflows, memory systems, prompt libraries, launch
              tooling, safety tooling, skills, and a lot of accumulated operational detail. You do
              not need any of that on day one.
            </P>

            <P>
              The core loop uses just <Hl>three tools</Hl>. If you understand those three and use
              them together, you already have the heart of the system.
            </P>

            <DataTable
              headers={["Layer", "What It Is For"]}
              rows={[
                ["Frontier models", "Writing and refining the markdown plan"],
                [
                  "br (beads_rust)",
                  "Turning the plan into tasks (beads) with dependencies, and tracking who has claimed what",
                ],
                [
                  "bv (beads_viewer)",
                  "Reading the dependency graph and ranking which ready bead is worth doing next",
                ],
                [
                  "Agent Mail",
                  "Messages, file reservations, and handoffs between agents",
                ],
              ]}
            />

            <P>
              Separate the process into two layers: the <Hl>planning substrate</Hl> (frontier models
              used to create and refine the markdown plan) and the <Hl>core operating loop</Hl>{" "}
              (Agent Mail, br, and bv once the plan is ready to drive execution).
            </P>

            <SubSection title="Who This Is For">
              <P>
                This guide is for a capable software developer who is new to agentic coding and
                does not want to absorb the full Flywheel guide up front. The goal is narrower: get
                you to the point where several agents can work in one repo without chaos, work is
                kept as explicit tasks with dependencies, and each agent picks the best unblocked
                task instead of choosing at random.
              </P>
              <P>
                Once that works for you, the rest of the Flywheel stack is much easier to
                appreciate.
              </P>
            </SubSection>

            <TipBox variant="info">
              &quot;Three-tool core&quot; means the execution machinery you keep running while the
              project is being built. It does not mean you skip planning. The first step is still
              an excellent markdown plan.
            </TipBox>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 2: FIVE TERMS                                          */}
          {/* ============================================================= */}
          <GuideSection id="terms">
            <P>
              Keep these five terms straight and the rest of the guide is much easier to follow.
            </P>

            <DataTable
              headers={["Term", "Meaning"]}
              rows={[
                [
                  "Bead",
                  "A task stored in br, with enough context, dependency information, and completion criteria that an agent can do it without guessing.",
                ],
                [
                  "Ready bead",
                  "An open bead whose dependencies are all closed, so an agent can start it now. br ready lists them.",
                ],
                [
                  "Claim",
                  "An agent taking ownership of a bead. br update <id> --claim assigns the bead to that agent and marks it in_progress in one atomic step; the agent then announces it in Agent Mail.",
                ],
                [
                  "Reservation",
                  "A time-limited lease on files or globs, taken in Agent Mail before editing, so two agents do not unknowingly edit the same code. It is advisory, and it expires if the agent disappears.",
                ],
                [
                  "Thread",
                  "The Agent Mail conversation for one bead, using the bead ID (for example br-123) as its thread ID. Start, progress, and completion messages collect there.",
                ],
              ]}
            />

            <SubSection title="How the Tools Work Together (Behind the Scenes)">
              <P>
                You do not wire these tools together by hand. When your <code>AGENTS.md</code>{" "}
                describes the workflow, the agents do it themselves: they claim beads in br, reserve
                files and announce their work in Agent Mail, use the bead ID as the thread ID, and
                close beads when they finish. You write it down once; the agents follow it.
              </P>
              <TipBox variant="info">
                The human&apos;s job is to write a good plan, create good beads, launch agents with
                the right marching orders, and then tend the swarm. The agents handle the
                coordination plumbing themselves.
              </TipBox>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 3: THE CORE IDEA                                       */}
          {/* ============================================================= */}
          <GuideSection id="core-loop">
            <P highlight>
              The core loop is simple: generate a plan, encode it as beads, launch agents with
              marching orders, let them coordinate through Agent Mail while bv routes them toward
              the best next bead, and tend the swarm until the graph is done.
            </P>

            <CoreLoopDiagram />

            <SubSection title="Normal Chat Coding vs. The Core Loop">
              <DataTable
                headers={["Normal Chat Coding", "The Core Loop"]}
                rows={[
                  [
                    "The task mostly lives in chat",
                    "The task gets formalized into a markdown plan and then beads",
                  ],
                  [
                    "Coordination lives in scrollback or in the human's head",
                    "Coordination is externalized through Agent Mail",
                  ],
                  [
                    "Agents pick work based on local convenience",
                    "bv routes work from the dependency graph",
                  ],
                  [
                    "Progress is hard to inspect later",
                    "The bead graph and message threads form a durable record",
                  ],
                  [
                    "A crashed agent often takes its local state with it",
                    "Another agent can resume from the bead and the thread",
                  ],
                ]}
              />
            </SubSection>

            <P>
              The core loop moves work out of ephemeral chat and into explicit, inspectable
              artifacts. That is the short answer to &quot;why bother?&quot;
            </P>

            <SwarmChaosViz />
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 4: THE THREE TOOLS                                     */}
          {/* ============================================================= */}
          <GuideSection id="three-tools">
            <P>
              These three tools address three different failure modes. Each helps on its own, but
              the payoff comes when they run together as one loop.
            </P>

            <SubSection title="Agent Mail Solves Coordination">
              <P>
                Without Agent Mail, parallel agents collide: two of them edit the same files, nobody
                knows who is doing what, messages vanish into chat history, and work is stranded
                when an agent crashes.
              </P>
              <P>
                Agent Mail is a local MCP server (with an <code>am</code> command-line tool) that
                gives agents a shared coordination layer: <Hl>identities</Hl>, <Hl>threads</Hl>,{" "}
                <Hl>inboxes</Hl>, and <Hl>file reservations</Hl>. Agents announce what they are
                doing, reserve the files they are about to edit, and leave a written trail another
                agent can pick up if one disappears. Once your AGENTS.md tells agents to use it,
                they do this on their own.
              </P>
            </SubSection>

            <SubSection title="br Solves Task Structure">
              <P>
                Without br, work collapses into vague conversational intentions: &quot;fix the auth
                stuff,&quot; &quot;clean up the admin area,&quot; &quot;someone should improve
                tests.&quot; That kind of tasking is too fuzzy for a swarm.
              </P>
              <P>
                <code>br</code> turns work into explicit beads with <Hl>status</Hl>,{" "}
                <Hl>priority</Hl>, and <Hl>dependencies</Hl>, stored in a local SQLite database and
                exported to JSONL files that you commit alongside your code. (br never runs git
                itself.) Once work is represented that way, several agents can make progress without
                constant human steering.
              </P>
            </SubSection>

            <SubSection title="bv Solves Routing">
              <P>
                Even with good beads, agents still need to know what to do next. Without bv, they
                choose work based on local convenience or whatever they most recently saw in
                context.
              </P>
              <P>
                <code>bv</code> reads the bead graph, scores it with graph metrics such as PageRank
                and critical path, and recommends the ready bead most worth doing next. Agents call
                it with <code>--robot-*</code> flags such as <code>bv --robot-triage</code>; bare{" "}
                <code>bv</code> opens an interactive TUI meant for humans. That turns the swarm from
                &quot;many agents doing work&quot; into &quot;many agents{" "}
                <Hl>moving the project forward in the right order</Hl>.&quot;
              </P>
            </SubSection>

            <CoordinationTrioViz />

            <SubSection title="What Goes Wrong If You Skip One">
              <DataTable
                headers={["If You Skip...", "What Usually Happens"]}
                rows={[
                  [
                    "Agent Mail",
                    "Agents overlap, duplicate work, and lose shared situational awareness",
                  ],
                  ["br", "Work stays vague, hidden in chat, and hard to coordinate across agents"],
                  ["bv", "Agents pick tasks based on convenience instead of graph-aware leverage"],
                ]}
              />
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 5: THE ARTIFACT LADDER                                 */}
          {/* ============================================================= */}
          <GuideSection id="artifact-ladder">
            <P>
              One reason agentic coding feels confusing at first is that the{" "}
              <Hl>active artifact keeps changing</Hl>. The easiest way to stay oriented is to know
              what the current artifact means and what you do with it next.
            </P>

            <ArtifactLadderViz />

            <SubSection title="Plan Space, Bead Space, and Code Space">
              <P>
                <strong>Plan space</strong> is where you decide the workflows, constraints,
                architecture, and testing expectations. <strong>Bead space</strong> is where you
                transform that thinking into executable memory for agents.{" "}
                <strong>Code space</strong> is where agents implement the local task that a bead
                defines.
              </P>
              <P>
                The general rule is simple. Debates belong in plan space. Translation and dependency
                shaping belong in bead space. Implementation belongs in code space.
              </P>
              <TipBox variant="warning">
                If the swarm starts discovering missing structure while coding, the answer is often
                to step back up into bead space or plan space instead of forcing more code through a
                weak task graph.
              </TipBox>
            </SubSection>

            <SubSection title="What a Good Plan Looks Like">
              <P>
                A strong plan lets a fresh reader answer five questions without guessing: what are
                the main workflows? What constraints matter? What architecture are we choosing? How
                will we know it works? What failure cases must not disappear into hand-waving?
              </P>
              <CodeBlock
                language="markdown"
                code={`## Upload workflow
- Users drag Markdown files into the upload surface.
- The system parses frontmatter plus body text and stores a normalized note record.

## Constraints
- Unauthorized users must never see note content or note metadata.
- Failed ingestions must be preserved for operator review instead of discarded.

## Architecture choice
- Use a dedicated ingestion pipeline so parse failures can be persisted and retried.
- Keep search indexing separate from upload handling so indexing can be retried independently.

## Tests and failure handling
- Unit coverage for parsing and index mapping.
- E2E coverage for upload, failed-ingestion review, retry, search, and filtering.`}
              />
              <P>
                It gives a fresh agent workflows, constraints, architecture, testing, and failure
                handling in one place. Before you turn the plan into beads, check that these five
                questions are answerable from the plan alone.
              </P>
            </SubSection>

            <SubSection title="Escalation Ladder">
              <P>
                When something feels wrong, use the smallest escalation that actually fits the
                problem:
              </P>
              <BulletList
                items={[
                  <Fragment key="code">
                    <strong>Local code confusion</strong> — stay in code space and resolve it there
                  </Fragment>,
                  <Fragment key="bead">
                    <strong>Weak or underspecified bead</strong> — step back into bead space and
                    rewrite the bead
                  </Fragment>,
                  <Fragment key="graph">
                    <strong>Wrong graph</strong> — fix the dependencies or add the missing bead
                  </Fragment>,
                  <Fragment key="plan">
                    <strong>Missing plan work</strong> — step back into plan space and revise the
                    markdown plan
                  </Fragment>,
                  <Fragment key="agent">
                    <strong>Degraded agent</strong> — restart it with a fresh session
                  </Fragment>,
                ]}
              />
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 6: CONCRETE EXAMPLE                                    */}
          {/* ============================================================= */}
          <GuideSection id="example">
            <P>
              A small project makes the workflow easier to picture. Imagine building an internal
              tool called <strong>Atlas Notes</strong>: team members upload Markdown notes, the
              system tags and indexes them, users can search them quickly, and admins can inspect
              failed ingestions.
            </P>

            <P>
              Give four agents only that description and they will step on each other and make
              mismatched assumptions. With the core loop, it goes like this instead:
            </P>

            <NumberedList
              items={[
                "You ask several frontier models for competing markdown plans, then have one model merge them into a single strong plan.",
                "You tell an agent to turn that plan into beads (upload pipeline, indexing, admin screen, auth, and end-to-end tests) with explicit dependencies, then have it polish them.",
                "You launch 2-4 agents, one at a time, with the same marching orders. They read AGENTS.md, join Agent Mail, and use bv to pick beads.",
                "You tend the swarm: check progress every 10-15 minutes, rescue confused agents, and add missing beads when needed.",
                "Agents implement, review their own work with fresh eyes, close beads, and move to the next one. You step in for strategic decisions.",
              ]}
            />

            <SubSection title="What a Good Bead Looks Like">
              <P>
                The bead is the unit of work agents actually execute. Weak beads force
                improvisation. Rich beads make execution mechanical. Here is a real bead from the
                ACFS repo, lightly trimmed:
              </P>
              <CodeBlock
                language="markdown"
                code={`bd-01s: Add --deep flag to acfs doctor

Context:
Part of EPIC: Enhanced Doctor with Functional Tests.

What to Do:
Add --deep flag to doctor.sh that enables functional tests beyond
binary existence:
- Add DEEP_MODE=false global
- Parse --deep flag alongside existing --json
- --deep and --json can be combined

Acceptance Criteria:
- --deep flag parsed correctly
- Default doctor unchanged (fast, existence only)
- --deep runs additional tests
- Works with --json for structured output

Files to Modify:
- scripts/lib/doctor.sh: Argument parsing`}
              />
              <P>
                The <code>bd-</code> prefix is just this repo&apos;s configured ID prefix, left over
                from the original beads tool. <code>br init</code> takes the prefix from{" "}
                <code>--prefix</code> or the directory name, so your IDs will look different; this
                guide uses <code>br-123</code>-style examples.
              </P>
              <P>
                The prose does not need polish. A fresh agent should be able to understand the task,
                the reason for it, and the acceptance criteria without reopening the whole markdown
                plan. You can browse real beads from actual Flywheel projects at{" "}
                <a
                  href="https://dicklesworthstone.github.io/beads_for_franken_engine"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  FrankenEngine
                </a>
                ,{" "}
                <a
                  href="https://dicklesworthstone.github.io/beads-for-frankentui/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  FrankenTUI
                </a>
                , and{" "}
                <a
                  href="https://dicklesworthstone.github.io/beads_for_asupersync"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  Asupersync
                </a>
                .
              </P>
            </SubSection>

            <SubSection title="Weak vs. Strong Artifacts">
              <P>
                Quality thresholds get easier to feel when you compare weak and strong versions
                directly. The weak version names a topic. The strong version scopes the actual
                requirement, constraint, and testing obligation.
              </P>
              <BeadComparisonViz />
            </SubSection>

            <SubSection title="What the Agents Do Automatically">
              <P>
                Once you launch agents with good marching orders, they handle the coordination
                mechanics themselves. A typical bead thread in Agent Mail looks like this, written
                entirely by agents:
              </P>

              <CodeBlock
                language="text"
                code={`[br-103] Start: Failed-ingestion admin screen
Claimed br-103. Reserved the admin UI files and the retry handler path.
Will post an update once the list view works and retry is wired.

[br-103] Progress: Main path wired
List view and detail view working. Now handling edge cases and tests.

[br-103] Completed
Admin screen done: list view, detail view, and retry action wired.
Auth checks in place. E2E coverage for malformed upload → admin review → retry.
Closed br-103 and released my file reservations.`}
              />
              <P>
                You do not write these messages. Agents write them because your AGENTS.md tells them
                to coordinate through Agent Mail, use the bead ID as the thread ID, and prefix
                subjects with it. Your job is to read these threads and notice whether work is
                flowing or stuck.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 7: THE OPERATING RHYTHM                                */}
          {/* ============================================================= */}
          <GuideSection id="operating-rhythm">
            <P highlight>
              This section covers what <strong>you, the human</strong>, actually do. The agents
              handle the coordination plumbing (Agent Mail messages, file reservations, bead status
              updates). Your job is to set them up to succeed.
            </P>

            <OperatingRhythmViz />

            <SubSection title="Step 1: Create an Excellent Markdown Plan">
              <P>
                Before beads, swarms, or file reservations, write a serious markdown plan. Do not
                settle for one quick draft from one model. Ask several frontier models for
                independent plans, then paste the others into the conversation that produced your
                favorite and ask it to merge them:
              </P>

              <PromptBlock
                title="Multi-Model Synthesis"
                prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan:

[Paste all plans here]`}
                where={`The ${COMPLETE_GUIDE_MODELS.primaryPlanner} conversation in ${COMPLETE_GUIDE_MODELS.primaryPlannerSurface} that wrote one of the plans (or your strongest available model)`}
                whyItWorks="Different frontier models have different blind spots. Competitive synthesis forces the model to admit where others are better and merge the strongest ideas."
              />

              <P>
                At minimum, the plan should cover the user-facing workflows, the important
                constraints, the major architectural decisions, and the testing expectations.
              </P>
            </SubSection>

            <SubSection title="Step 2: Tell an Agent to Convert the Plan into Beads">
              <P>
                You do not create every bead by hand. Run <code>br init</code> once in the repo,
                have a coding agent read the final plan, and then give it this prompt:
              </P>

              <PromptBlock
                title="Plan to Beads Conversion"
                prompt={`OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting. The beads should be so detailed that we never need to consult back to the original markdown plan document. Remember to ONLY use the \`br\` tool to create and modify the beads and add the dependencies. Use ultrathink.`}
                where={`Claude Code with ${COMPLETE_GUIDE_MODELS.claudeExecutor}, in the same session where it read the plan`}
                whyItWorks="Beads become the source of truth for execution. Once they are strong enough, agents rarely need to open the markdown plan again."
              />

              <P>
                Then polish the beads, 4-6 rounds, with this prompt. Each round catches things the
                previous one missed. This is the &quot;measure twice, cut once&quot; step of the
                method, and the one people most often shortchange.
              </P>

              <PromptBlock
                title="Bead Polishing"
                prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the \`br\` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.`}
                where={`Claude Code with ${COMPLETE_GUIDE_MODELS.claudeExecutor}, repeated 4-6 times; start a fresh session if improvements flatten out`}
                whyItWorks="Fixing a bead is far cheaper than fixing the code built from it. The warnings against oversimplifying matter because models otherwise 'improve' beads by deleting complexity they do not fully understand."
              />

              <TipBox>
                <strong>Beads are executable memory.</strong> The markdown plan is the best artifact
                for whole-system thought. Beads are the plan after it has been transformed into a
                format optimized for distributed execution. Weak beads force improvisation. Rich
                beads make execution mechanical.
              </TipBox>
            </SubSection>

            <SubSection title="Step 3: Launch Agents with Marching Orders">
              <P>
                Once the beads are polished and your AGENTS.md is solid, start the agents. Separate
                terminal tabs are enough. On an ACFS machine,{" "}
                <code>ntm spawn myproject --cc=2 --cod=1</code> opens a tmux session with two Claude
                Code panes and one Codex pane for you. Give each agent these marching orders:
              </P>

              <PromptBlock
                title="Swarm Marching Orders"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents.

Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages.

Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately.

When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. Use ultrathink.`}
                where="Every agent in the swarm gets this as its first prompt"
                whyItWorks="Every agent is a fungible generalist. The specifics come from AGENTS.md and the beads, not from the prompt, so the same prompt works for every project."
              />

              <P>
                Stagger the starts. If every agent boots at once, several can grab the same bead (a
                &quot;thundering herd&quot;). Send the prompt to one agent, wait until it has joined
                Agent Mail and claimed a bead, then start the next. There is no magic delay; watch
                for the claim.
              </P>
            </SubSection>

            <SubSection title="Step 4: Tend the Swarm">
              <P>
                Now you are the operator. Every 10-15 minutes or so, check on the swarm:
              </P>

              <NumberedList
                items={[
                  <Fragment key="triage">
                    Run <code>bv --robot-triage</code> and check whether the top recommendation
                    still makes sense.
                  </Fragment>,
                  <Fragment key="threads">
                    Skim the Agent Mail threads (the server&apos;s web UI at <code>/mail/</code> is
                    built for this). Are agents making progress or stuck?
                  </Fragment>,
                  <Fragment key="stuck">
                    Run <code>br list --status in_progress</code> and look for beads that have not
                    moved.
                  </Fragment>,
                  <Fragment key="reread">
                    If an agent seems confused after compaction, send: &quot;Reread AGENTS.md so
                    it&apos;s still fresh in your mind.&quot;
                  </Fragment>,
                  "If an agent is truly degraded, kill it and start a fresh one.",
                ]}
              />

              <P>
                That is usually enough to keep the loop healthy without turning you into a
                full-time traffic cop.
              </P>
            </SubSection>

            <SubSection title="Step 5: Review, Close, Repeat">
              <P>After an agent finishes a bead, have it review its own work:</P>

              <PromptBlock
                title="Fresh-Eyes Review"
                prompt={`Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. Use ultrathink.`}
                where="After each bead is implemented; repeat until a pass finds nothing new"
                whyItWorks="Forces a mode switch from writing to adversarial reading while the code is still fresh. One of the cheapest quality multipliers in the whole method."
              />

              <P>
                Then the agent closes the bead (<code>br close br-123</code>), releases its file
                reservations, posts a final message in the thread, and asks bv for the next bead.
                The cycle repeats until the graph is done.
              </P>

              <P>
                Committing is a separate step, because br never runs git. Every hour or two, have
                one agent run <code>br sync --flush-only</code> and commit the code and the{" "}
                <code>.beads/</code> files together in logical groups.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 8: THE HUMAN'S JOB                                     */}
          {/* ============================================================= */}
          <GuideSection id="operator">
            <P highlight>
              The human is not supposed to micromanage every code edit or manually coordinate Agent
              Mail threads. The human is there to keep the structure clean enough that the agents
              can work effectively inside it.
            </P>

            <HumanAgentTimelineViz />

            <SubSection title="What You Do">
              <BulletList
                items={[
                  <Fragment key="plan">
                    <strong>Create the plan and beads</strong> — this is where most of your time and
                    thinking goes
                  </Fragment>,
                  <Fragment key="agents-md">
                    <strong>Write a good AGENTS.md</strong> — this is the operating manual that
                    makes everything else work
                  </Fragment>,
                  <Fragment key="launch">
                    <strong>Launch agents with marching orders</strong> — the same generic prompt
                    every time
                  </Fragment>,
                  <Fragment key="graph">
                    <strong>Keep the bead graph honest</strong> — notice when a missing task or
                    dependency must be added
                  </Fragment>,
                  <Fragment key="restart">
                    <strong>Restart or redirect agents</strong> when they drift, get loopy, or lose
                    context
                  </Fragment>,
                  <Fragment key="question">
                    <strong>Ask the hard question</strong> periodically (see below)
                  </Fragment>,
                ]}
              />
            </SubSection>

            <SubSection title="What the Agents Do (Not You)">
              <BulletList
                items={[
                  "Register with Agent Mail and discover the other active agents",
                  "Claim beads in br (which marks them in_progress) and announce them in Agent Mail",
                  "Reserve files before editing to prevent conflicts",
                  "Send progress updates and completion messages in each bead's thread",
                  "Close beads when done and release their file reservations",
                  "Use bv to find the next best bead when they finish one",
                ]}
              />
              <P>
                All of this is set up once in your AGENTS.md. You do not make Agent Mail calls,
                update bead statuses, or thread bead IDs into messages yourself. The agents do it
                because the operating manual tells them to.
              </P>
            </SubSection>

            <SubSection title="The Reality Check">
              <P>
                When the swarm looks active but you suspect it is not actually closing the real gap,
                stop and ask:
              </P>
              <BlockQuote>
                Where are we on this project? Do we actually have the thing we are trying to build?
                If not, what is blocking us? If we intelligently implement all open and in-progress
                beads, would we close that gap completely? Why or why not?
              </BlockQuote>
              <P>
                If the answer is &quot;no,&quot; the fix is usually not more implementation effort.
                Revise the bead graph, add missing work, or step back into planning.
              </P>
            </SubSection>

            <SubSection title="Minimum Viable AGENTS.md">
              <P>
                Even the core loop needs a minimal <code>AGENTS.md</code> at the repo root. It does
                not have to be a giant doctrine document, but it should cover:
              </P>
              <BulletList
                items={[
                  "What the repo is for and what the stack is",
                  "Non-negotiable safety and style rules (for example: never delete files or run destructive git commands without permission)",
                  <Fragment key="coordination">
                    Coordination: register with Agent Mail, reserve files before editing, use the
                    bead ID as the thread ID, and prefix subjects with it (<code>[br-123]</code>)
                  </Fragment>,
                  <Fragment key="beads">
                    Task flow: pick work with <code>bv --robot-triage</code> or{" "}
                    <code>bv --robot-next</code>, claim it with <code>br update &lt;id&gt; --claim</code>,
                    finish with <code>br close &lt;id&gt;</code>
                  </Fragment>,
                  <Fragment key="robot">
                    Only <code>--robot-*</code> flags for bv: bare <code>bv</code> opens an
                    interactive TUI that stalls an agent
                  </Fragment>,
                  <Fragment key="sync">
                    br never commits: run <code>br sync --flush-only</code>, then commit{" "}
                    <code>.beads/</code> with the code
                  </Fragment>,
                ]}
              />
              <P>
                You do not have to write the tool sections from scratch. The Agent Mail, br, and bv
                READMEs each include a ready-made AGENTS.md blurb, and <code>br agents --add</code>{" "}
                and <code>bv --agents-add</code> insert theirs for you.
              </P>
              <BlockQuote>
                Treat AGENTS.md as the swarm&apos;s durable operating manual. It tells a fresh or
                partially confused agent how to behave, what tools exist, and what &quot;doing a
                good job&quot; looks like in this repo.
              </BlockQuote>

              <TipBox variant="warning">
                <strong>After compaction, agents must re-read AGENTS.md.</strong> If an agent still
                seems confused or loopy after rereading it, stop trying to rescue the degraded state
                and start a fresh session instead.
              </TipBox>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 9: COMMON FAILURE MODES                                */}
          {/* ============================================================= */}
          <GuideSection id="failure-modes">
            <DataTable
              headers={["Symptom", "Likely Cause", "Fix"]}
              rows={[
                [
                  "Agents keep overlapping",
                  "AGENTS.md doesn't make claims and file reservations mandatory",
                  "Strengthen the coordination section in AGENTS.md",
                ],
                [
                  "Two agents start the same bead",
                  "Agents were launched all at once, or one skipped the claim",
                  "Stagger launches and require br update <id> --claim before any work starts",
                ],
                [
                  "Agents choose random work",
                  "AGENTS.md doesn't explain bv usage clearly",
                  "Add the bv robot-flag commands (bv --robot-triage, bv --robot-next) to AGENTS.md",
                ],
                [
                  "An agent hangs right after calling bv",
                  "It ran bare bv, which opens an interactive TUI",
                  "Tell agents in AGENTS.md to use only --robot-* flags",
                ],
                [
                  "A task keeps stalling",
                  "The bead is underspecified or missing a dependency",
                  "Rewrite the bead or add the missing dependency",
                ],
                [
                  "The swarm feels busy but confused",
                  "The markdown plan was too weak",
                  "Go back up a level and improve the plan before continuing",
                ],
              ]}
            />

            <SubSection title="Agent Disappeared Mid-Bead">
              <P>When an agent vanishes mid-bead, the recovery path should be boring:</P>
              <NumberedList
                items={[
                  <Fragment key="find">
                    Find the orphaned bead: <code>br list --status in_progress</code> shows beads
                    still assigned to the missing agent.
                  </Fragment>,
                  "Read the bead's Agent Mail thread for the last meaningful progress update.",
                  <Fragment key="release">
                    Hand the bead back with{" "}
                    <code>br update &lt;id&gt; --status open --assignee &quot;&quot;</code>. Until
                    you do, bv will not offer it as a new claim and <code>br update --claim</code>{" "}
                    will refuse it. The missing agent&apos;s file reservations expire on their own.
                  </Fragment>,
                  "Launch a fresh agent with the standard marching orders. It will find the bead through bv, claim it, and continue from the code on disk plus the thread history.",
                ]}
              />
              <TipBox variant="info">
                If recovery feels hard, the bead or the AGENTS.md was probably too thin. That is a
                signal to write richer beads and a more thorough operating manual.
              </TipBox>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 10: WHAT IT FEELS LIKE                                  */}
          {/* ============================================================= */}
          <GuideSection id="what-it-feels-like">
            <P>
              At some point, the workflow stops feeling like extra ceremony and starts feeling like
              a <Hl>calmer control surface</Hl>:
            </P>

            <BulletList
              items={[
                <Fragment key="dup">
                  <strong>Less duplicated work</strong>, because agents manage ownership and
                  reservations automatically
                </Fragment>,
                <Fragment key="drift">
                  <strong>Less &quot;what should I do next?&quot; drift</strong>, because bv keeps
                  answering that question for the agents
                </Fragment>,
                <Fragment key="restart">
                  <strong>Easier restart after context loss</strong>, because the work lives in
                  beads and threads instead of only in chat history
                </Fragment>,
                <Fragment key="handoff">
                  <strong>Easier handoff</strong>, because any agent can read the bead, read the
                  thread, and continue
                </Fragment>,
              ]}
            />

            <P>
              That operator feeling is a good sign. It usually means the artifacts are carrying the
              work instead of your short-term memory.
            </P>

            <SubSection title="Why This Captures Most of the Value">
              <P>
                People often assume the magic of the Flywheel comes from the total number of tools.
                It does not. Most of the value comes from three things:
              </P>
              <NumberedList
                items={[
                  "Work is explicit instead of implicit",
                  "Coordination is externalized instead of living in human memory",
                  "Task choice is graph-aware instead of random",
                ]}
              />
              <P>
                Those three properties are already present in the core loop. That is why the smaller
                system gets you surprisingly far.
              </P>
            </SubSection>

            <SubSection title="When Not to Use the Core Loop">
              <P>
                You probably do not need it for a tiny one-file change with no real dependency
                structure, a purely local experiment, or a quick one-agent cleanup that does not
                need externalized coordination.
              </P>
              <P>
                The loop earns its keep when work has enough structure, enough ambiguity, or enough
                parallelism that explicit planning, explicit tasks, and explicit coordination start
                paying for themselves.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 11: HELPER UTILITIES                                    */}
          {/* ============================================================= */}
          <GuideSection id="helpers">
            <P>
              Once the core loop runs smoothly, three helper utilities make it safer, catch bugs
              earlier, and let agents reuse past work. They are{" "}
              <Hl>multipliers on top of the core loop</Hl>, not prerequisites.
            </P>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
              <HelperCard
                icon={<Shield className="h-6 w-6" />}
                name="DCG"
                fullName="Destructive Command Guard"
                color="#FF5F56"
                description="A pre-execution hook for Claude Code, Codex, and other agent CLIs that blocks destructive git and filesystem commands before they run, with optional packs for databases, containers, and cloud CLIs. Checks are fast enough to run on every command."
                usage="Runs automatically once installed. When it blocks a command, take the safer route it suggests or ask a human to run the command."
                command="dcg explain 'git reset --hard'"
              />
              <HelperCard
                icon={<Bug className="h-6 w-6" />}
                name="UBS"
                fullName="Ultimate Bug Scanner"
                color="#FFBD2E"
                description="A static bug scanner for JS/TS, Python, Rust, Go, Bash, and more. It flags likely bugs, such as security risks and shell quoting mistakes, before they reach a commit."
                usage="Scan staged changes before every commit. Exit 0 means no critical findings; anything else means fix and re-run."
                command="ubs --staged"
              />
              <HelperCard
                icon={<Search className="h-6 w-6" />}
                name="CASS"
                fullName="Coding Agent Session Search"
                color="#a78bfa"
                description="Indexes past sessions from Claude Code, Codex, and many other agents, so a problem that was already solved can be found instead of solved again."
                usage="Search before re-solving something. Agents always pass --robot or --json; bare cass opens an interactive TUI."
                command="cass search 'auth middleware' --robot --limit 5"
              />
            </div>

            <SubSection title="What You Can Ignore for Now">
              <P>
                If you are just getting started, you do not need to master any of this yet:
              </P>
              <BulletList
                items={[
                  "Memory systems such as CM, beyond an occasional cass search",
                  "Big prompt libraries",
                  "Advanced launch tooling like ntm",
                  "The full planning doctrine",
                  "Every supporting tool in ACFS",
                ]}
              />
              <P>
                Those things help, some of them a lot. But they build on the core loop; they are not
                prerequisites. You can run the core loop with separate terminal tabs and no special
                session manager.
              </P>
            </SubSection>

            <SubSection title="What You Should Not Ignore">
              <P>Even in the smaller version, a few principles still matter a lot:</P>
              <BulletList
                items={[
                  "Do not start a swarm with only vague goals. Make a real plan first.",
                  "Do not treat beads as tiny throwaway todo lines. They need rich context.",
                  "Do not skip the bead polishing rounds. Single-pass beads are rarely good enough.",
                  "Do not use chat scrollback as your coordination system. That is what Agent Mail is for.",
                ]}
              />
              <P>
                If you violate those, the workflow quickly degrades back into ordinary multi-agent
                chaos.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 12: GETTING STARTED & GRADUATION                       */}
          {/* ============================================================= */}
          <GuideSection id="getting-started">
            <SubSection title="Your First Project">
              <P>
                Expect the planning and bead steps to take hours, not minutes. That time is the
                point: it is where the method buys its quality.
              </P>
              <NumberedList
                items={[
                  "Pick one real project, not a toy.",
                  <Fragment key="setup">
                    In the repo, run <code>br init</code>, write a minimal AGENTS.md (Section 8),
                    and make sure the Agent Mail server is running (ACFS runs it as a service;
                    elsewhere, start it with <code>am</code>).
                  </Fragment>,
                  "Ask several frontier models for competing markdown plans.",
                  "Have one model merge them into a single strong plan.",
                  "Tell an agent to create beads from the plan, with dependencies.",
                  "Polish the beads 4-6 times with fresh review passes.",
                  <Fragment key="triage">
                    Run <code>bv --robot-triage</code> to check that the graph and its top
                    recommendations make sense.
                  </Fragment>,
                  "Launch 2-4 agents, one at a time, with the standard marching orders.",
                  "Tend the swarm. Check in every 10-15 minutes.",
                ]}
              />

              <P>Start smaller than your ego wants to:</P>
              <DataTable
                headers={["Mode", "What It Is Good For"]}
                rows={[
                  ["1 agent", "Learn the artifact flow without coordination overhead"],
                  ["2 agents", "Feel the first real coordination benefits"],
                  [
                    "4 agents",
                    "Experience meaningful swarm behavior where routing and handoff matter",
                  ],
                ]}
              />
            </SubSection>

            <SubSection title="Try This Now">
              <P>If you want to feel the method instead of only reading about it:</P>
              <NumberedList
                items={[
                  "Pick one real repo and give it a minimal AGENTS.md",
                  "Write one serious markdown plan for a small feature",
                  "Tell an agent to create three real beads, one of which depends on another",
                  <Fragment key="next">
                    Run <code>bv --robot-next</code> and check that it recommends an unblocked bead
                  </Fragment>,
                  "Launch two agents with the marching orders, one after the other, and watch them split the ready beads",
                ]}
              />
              <P>Those five steps are enough to make the core loop stop feeling theoretical.</P>
            </SubSection>

            <SubSection title="The Cheat Card">
              <P highlight>If you want the loop on one screen, keep this:</P>
              <NumberedList
                items={[
                  "Plan with multiple models",
                  "Merge the plans into one markdown plan",
                  "Write a minimal AGENTS.md",
                  "Tell an agent to create beads",
                  "Polish beads 4-6 times",
                  "Launch agents one at a time with the marching orders",
                  "Tend the swarm every 10-15 minutes",
                  "Have agents do a fresh-eyes review after each bead",
                  "Repeat until the graph is done",
                ]}
              />
            </SubSection>

            <SubSection title="When to Graduate to the Full Flywheel">
              <P>
                Move up to the{" "}
                <a
                  href="/complete-guide"
                  className="text-[#FF5500] hover:text-[#FFBD2E] transition-colors font-medium underline decoration-[#FF5500]/30 underline-offset-4 hover:decoration-[#FFBD2E]/50"
                >
                  full guide
                </a>{" "}
                when one or more of these becomes true:
              </P>
              <BulletList
                items={[
                  "Your projects are large enough that you want much richer planning workflows",
                  "You want stronger AGENTS.md operating manuals with comprehensive tool documentation",
                  "You want repeatable prompt libraries and skills",
                  "You want better recovery from compaction and session loss",
                  "You want memory systems (CASS, CM) that improve the workflow over time",
                ]}
              />
              <P>
                At that point, the bigger document stops feeling like overhead and starts feeling
                like leverage.
              </P>
            </SubSection>
          </GuideSection>

          <GuideFooterCTA
            eyebrow="Ready for more?"
            title={
              <>
                Graduate to the full <em className="italic text-[#FF5500]">Flywheel</em>
              </>
            }
            body={
              <>
                Once the core loop feels natural, the complete guide adds richer planning
                workflows, memory systems, prompt libraries, and the rest of the Agent Flywheel
                stack.
              </>
            }
            primary={{ href: "/complete-guide", label: "Read the complete guide" }}
            secondary={{ href: "/wizard/os-selection", label: "Install the stack" }}
          />
          <GuideColophon reviewedOn={CORE_FLYWHEEL_REVIEWED_ON} sourcePath="core-flywheel/page.tsx" />
          </GuideArticle>
        </div>
      </main>
    </ErrorBoundary>
  );
}

// =============================================================================
// HELPER CARD - For DCG, UBS, CASS section
// =============================================================================
function HelperCard({
  icon,
  name,
  fullName,
  color,
  description,
  usage,
  command,
}: {
  icon: React.ReactNode;
  name: string;
  fullName: string;
  color: string;
  description: string;
  usage: string;
  command: string;
}) {
  return (
    <div className="flex flex-col rounded-xl border border-white/[0.08] bg-white/[0.02] p-5 sm:p-6">
      <div className="flex items-center gap-3.5">
        <span
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg border"
          style={{ borderColor: `${color}40`, backgroundColor: `${color}14`, color }}
        >
          {icon}
        </span>
        <div className="min-w-0">
          <p className="font-mono text-xs font-medium uppercase tracking-[0.14em]" style={{ color }}>
            {fullName}
          </p>
          <h3 className="mt-0.5 text-xl font-semibold tracking-[-0.01em] text-white">{name}</h3>
        </div>
      </div>

      <p className="mt-4 flex-1 text-[0.9375rem] leading-relaxed text-zinc-300">{description}</p>

      <div className="mt-5 border-t border-white/[0.07] pt-4">
        <p className="font-mono text-xs font-medium uppercase tracking-[0.14em] text-zinc-400">
          Usage
        </p>
        <p className="mt-1.5 text-sm leading-relaxed text-zinc-300">{usage}</p>
        <code
          className="mt-3 block overflow-x-auto whitespace-nowrap rounded-md border border-l-2 border-white/[0.07] bg-black/30 px-3 py-2 font-mono text-[0.8125rem] text-zinc-200"
          style={{ borderLeftColor: color }}
        >
          {command}
        </code>
      </div>
    </div>
  );
}
