import { ErrorBoundary } from "@/components/ui/error-boundary";
import { Sparkles, Rocket, ArrowRight, Shield, Bug, Search, ChevronDown } from "lucide-react";

import {
  GuideSection,
  SubSection,
  P,
  BlockQuote,
  PromptBlock,
  Hl,
  Divider,
  TipBox,
  BulletList,
  NumberedList,
  DataTable,
  CodeBlock,
} from "@/components/complete-guide/guide-components";
import { CoordinationTrioViz } from "@/components/complete-guide/coordination-trio-viz";
import { CoreLoopDiagram } from "@/components/core-flywheel/core-loop-diagram";
import { ArtifactLadderViz } from "@/components/core-flywheel/artifact-ladder-viz";
import { BeadComparisonViz } from "@/components/core-flywheel/bead-comparison-viz";
import { QuickNav } from "@/components/core-flywheel/quick-nav";
import { OperatingRhythmViz } from "@/components/core-flywheel/operating-rhythm-viz";
import { SwarmChaosViz } from "@/components/core-flywheel/swarm-chaos-viz";
import { HumanAgentTimelineViz } from "@/components/core-flywheel/human-agent-timeline-viz";


export default function CoreFlywheelPage() {
  return (
    <ErrorBoundary>
      <main className="min-h-screen bg-[#020408] selection:bg-[#FF5500]/20 selection:text-white overflow-x-hidden pb-40">
        <Hero />

        {/* Floating quick-nav for desktop */}
        <QuickNav />

        <div className="mx-auto max-w-[1000px] px-6 lg:px-12 relative mt-20">

          {/* ============================================================= */}
          {/* SECTION 1: WHY THE CORE LOOP                                   */}
          {/* ============================================================= */}
          <GuideSection id="why" number="1" title="Why a Simpler Starting Point">
            <P highlight>The full Flywheel system has grown large enough that many people find it overwhelming on first contact. That reaction makes sense. But there is a much smaller core that already captures most of what makes the approach powerful.</P>

            <P>The larger system includes planning workflows, memory systems, prompt libraries, launch tooling, safety tooling, skills, and a lot of accumulated operational detail. You do not need to absorb all of that up front.</P>

            <P>The core loop uses just <Hl>three tools</Hl>. If you understand those three and use them together correctly, you already have the heart of the system.</P>

            <DataTable
              headers={["Layer", "What It Is For"]}
              rows={[
                ["Frontier models", "Generating and refining the markdown plan"],
                ["br (beads_rust)", "Turning that plan into explicit task structure with dependencies"],
                ["bv (beads_viewer)", "Routing work through the dependency graph to find highest-leverage next bead"],
                ["Agent Mail", "Coordinating claims, reservations, progress, and handoff between agents"],
              ]}
            />

            <P>Separate the process into two layers: the <Hl>planning substrate</Hl> (frontier models used to create and refine the markdown plan) and the <Hl>core operating loop</Hl> (Agent Mail, br, and bv once the plan is ready to drive execution).</P>

            <SubSection title="Who This Is For">
              <P>This document is for a relatively smart software developer who is new to agentic coding and does not want to absorb the entire larger Flywheel guide up front. The goal is narrower: get you to the point where you can coordinate multiple agents without chaos, keep work organized as explicit tasks with dependencies, and keep agents working on the best next unblocked task instead of choosing randomly.</P>
              <P>If that works well for you, the larger Flywheel stack becomes much easier to appreciate later.</P>
            </SubSection>

            <TipBox variant="info">
              When this guide says &quot;three-tool core,&quot; it means the durable execution substrate you keep live while the project is being carried out. It does not mean the planning phase happens in a vacuum. The first step is still creating an excellent markdown plan.
            </TipBox>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 2: FIVE TERMS                                          */}
          {/* ============================================================= */}
          <GuideSection id="terms" number="2" title="Five Terms You Need">
            <P>If these five terms stay clear in your head, most of the rest of the guide gets much easier to follow.</P>

            <DataTable
              headers={["Term", "Meaning"]}
              rows={[
                ["Bead", "A self-contained task with enough context, dependency information, and completion criteria that an agent can work it without guessing."],
                ["Ready bead", "A bead whose blockers are cleared, so it can be started right now."],
                ["Claim", "When an agent announces via Agent Mail that it is taking responsibility for a bead. Agents do this automatically."],
                ["Reservation", "A coordination lock on files so two agents do not unknowingly collide. Agents manage these automatically via Agent Mail."],
                ["Thread", "The Agent Mail conversation tied to one bead, where start, progress, and completion messages accumulate. Created automatically by agents."],
              ]}
            />

            <SubSection title="How the Tools Work Together (Behind the Scenes)">
              <P>You do not need to manually manage the coordination between these tools. When your <code>AGENTS.md</code> file is set up correctly, the agents handle the integration automatically: they use bead IDs as thread identifiers in Agent Mail, they announce claims and reserve files before editing, and they update bead status as they work. You configure this once in AGENTS.md and then the agents just do it.</P>
              <TipBox variant="info">
                The human&apos;s job is to write a good plan, create good beads, launch agents with the right marching orders, and then tend the swarm. The agents handle the coordination plumbing themselves.
              </TipBox>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 3: THE CORE IDEA                                       */}
          {/* ============================================================= */}
          <GuideSection id="core-loop" number="3" title="The Core Loop">
            <P highlight>The core loop is simple: generate a plan, encode it as beads, launch agents with marching orders, let them coordinate through Agent Mail while bv routes them toward the best next bead, and tend the swarm until the graph is done.</P>

            <CoreLoopDiagram />

            <SubSection title="Normal Chat Coding vs. The Core Loop">
              <DataTable
                headers={["Normal Chat Coding", "The Core Loop"]}
                rows={[
                  ["The task mostly lives in chat", "The task gets formalized into a markdown plan and then beads"],
                  ["Coordination lives in scrollback or in the human's head", "Coordination is externalized through Agent Mail"],
                  ["Agents pick work based on local convenience", "bv routes work from the dependency graph"],
                  ["Progress is hard to inspect later", "The bead graph and message threads form a durable record"],
                  ["A crashed agent often takes its local state with it", "Another agent can resume from the bead and the thread"],
                ]}
              />
            </SubSection>

            <P>The core loop moves work out of ephemeral chat and into explicit, inspectable artifacts. That is the short answer to &quot;why bother?&quot;</P>

            <SwarmChaosViz />
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 4: THE THREE TOOLS                                     */}
          {/* ============================================================= */}
          <GuideSection id="three-tools" number="4" title="The Three Tools Are a Single Machine">
            <P>These three tools solve three different failure modes. Each helps on its own, but the value shows up most clearly when they form a stable loop together.</P>

            <SubSection title="Agent Mail Solves Coordination">
              <P>Without Agent Mail, multiple agents constantly collide: two agents edit the same files, nobody knows who is doing what, messages disappear into chat history, and work gets stranded when an agent crashes.</P>
              <P>Agent Mail gives agents a shared coordination layer with <Hl>identities</Hl>, <Hl>threads</Hl>, <Hl>inboxes</Hl>, and <Hl>file reservations</Hl>. Agents announce what they are doing, reserve edit surfaces, and recover when another agent disappears. All of this happens automatically once your AGENTS.md tells agents to use Agent Mail.</P>
            </SubSection>

            <SubSection title="br Solves Task Structure">
              <P>Without br, work collapses into vague conversational intentions: &quot;fix the auth stuff,&quot; &quot;clean up the admin area,&quot; &quot;someone should improve tests.&quot; That kind of tasking is too fuzzy for a swarm.</P>
              <P><code>br</code> turns work into explicit beads with <Hl>status</Hl>, <Hl>priority</Hl>, and <Hl>dependencies</Hl>. Once work is represented that way, multiple agents can make progress without constant human steering.</P>
            </SubSection>

            <SubSection title="bv Solves Routing">
              <P>Even with good beads, agents still need to know what to do next. Without bv, they choose work based on local convenience or whatever they most recently saw in context.</P>
              <P><code>bv</code> reads the bead graph and computes what is most worth doing next. That turns the swarm from &quot;many agents doing work&quot; into &quot;many agents <Hl>pushing the project forward efficiently</Hl>.&quot;</P>
            </SubSection>

            <CoordinationTrioViz />

            <SubSection title="What Goes Wrong If You Skip One">
              <DataTable
                headers={["If You Skip...", "What Usually Happens"]}
                rows={[
                  ["Agent Mail", "Agents overlap, duplicate work, and lose shared situational awareness"],
                  ["br", "Work stays vague, hidden in chat, and hard to coordinate across agents"],
                  ["bv", "Agents pick tasks based on convenience instead of graph-aware leverage"],
                ]}
              />
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 5: THE ARTIFACT LADDER                                 */}
          {/* ============================================================= */}
          <GuideSection id="artifact-ladder" number="5" title="The Artifact Ladder">
            <P>One reason agentic coding feels confusing at first is that the <Hl>active artifact keeps changing</Hl>. The easiest way to stay oriented is to know what the current artifact means and what you do with it next.</P>

            <ArtifactLadderViz />

            <SubSection title="Plan Space, Bead Space, and Code Space">
              <P><strong>Plan space</strong> is where you decide the workflows, constraints, architecture, and testing expectations. <strong>Bead space</strong> is where you transform that thinking into executable memory for agents. <strong>Code space</strong> is where agents implement the local task that a bead defines.</P>
              <P>The general rule is simple. Debates belong in plan space. Translation and dependency shaping belong in bead space. Implementation belongs in code space.</P>
              <TipBox variant="warning">
                If the swarm starts discovering missing structure while coding, the answer is often to step back up into bead space or plan space instead of forcing more code through a weak task graph.
              </TipBox>
            </SubSection>

            <SubSection title="What a Good Plan Looks Like">
              <P>A strong plan lets a fresh reader answer five questions without guessing: what are the main workflows? What constraints matter? What architecture are we choosing? How will we know it works? What failure cases must not disappear into hand-waving?</P>
              <CodeBlock language="markdown" code={`## Upload workflow
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
- E2E coverage for upload, failed-ingestion review, retry, search, and filtering.`} />
              <P>It gives a fresh agent workflows, constraints, architecture, testing, and failure handling in one place. Before you turn the plan into beads, check that these five questions are answerable from the plan alone.</P>
            </SubSection>

            <SubSection title="Escalation Ladder">
              <P>When something feels wrong, use the smallest escalation that actually fits the problem:</P>
              <BulletList items={[
                <><strong>Local code confusion</strong> — stay in code space and resolve it there</>,
                <><strong>Weak or underspecified bead</strong> — step back into bead space and rewrite the bead</>,
                <><strong>Wrong graph</strong> — fix the dependencies or add the missing bead</>,
                <><strong>Missing plan work</strong> — step back into plan space and revise the markdown plan</>,
                <><strong>Degraded agent</strong> — restart it with a fresh session</>,
              ]} />
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 6: CONCRETE EXAMPLE                                    */}
          {/* ============================================================= */}
          <GuideSection id="example" number="6" title="A Concrete Example: Atlas Notes">
            <P>A small project makes the workflow easier to picture. Imagine building an internal tool called <strong>Atlas Notes</strong>: team members upload Markdown notes, the system tags and indexes them, users can search them quickly, and admins can inspect failed ingestions.</P>

            <P>If you gave four agents only that vague description, they would step on each other and make mismatched assumptions. The core loop instead looks like this:</P>

            <NumberedList items={[
              "You ask multiple frontier models to produce competing markdown plans, then synthesize them into one strong plan.",
              "You tell an agent to convert that plan into beads — upload pipeline, indexing, admin screen, auth, and end-to-end tests — with explicit dependencies.",
              "You launch 2-4 agents with marching orders. They read AGENTS.md, join Agent Mail, and start picking up beads using bv.",
              "You tend the swarm: check progress every 10-15 minutes, rescue confused agents, and add missing beads when needed.",
              "Agents implement, review their own work with fresh eyes, close beads, and move to the next one. You step in for strategic decisions.",
            ]} />

            <SubSection title="What a Good Bead Looks Like">
              <P>The bead is the unit of work agents actually execute. Weak beads force improvisation. Rich beads make execution mechanical. Here is a real bead from the ACFS project:</P>
              <CodeBlock language="markdown" code={`bd-01s: Add --deep flag to acfs doctor

Context:
Part of EPIC: Enhanced Doctor with Functional Tests.

What to Do:
Add --deep flag to doctor.sh that enables functional tests beyond
binary existence checks:
- Add DEEP_MODE=false global
- Parse --deep flag alongside existing --json
- --deep and --json can be combined

Acceptance Criteria:
- --deep flag parsed correctly
- Default doctor unchanged (fast, existence checks only)
- --deep runs additional functional tests
- Works with --json for structured output

Files to Modify:
- scripts/lib/doctor.sh: Argument parsing`} />
              <P>The prose does not need polish. A fresh agent should be able to understand the task, the reason for it, and the acceptance criteria without reopening the whole markdown plan. You can browse real beads from actual Flywheel projects at <a href="https://dicklesworthstone.github.io/beads_for_franken_engine" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">FrankenEngine</a>, <a href="https://dicklesworthstone.github.io/beads-for-frankentui/" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">FrankenTUI</a>, and <a href="https://dicklesworthstone.github.io/beads_for_asupersync" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Asupersync</a>.</P>
            </SubSection>

            <SubSection title="Weak vs. Strong Artifacts">
              <P>Quality thresholds get easier to feel when you compare weak and strong versions directly. The weak version names a topic. The strong version scopes the actual requirement, constraint, and testing obligation.</P>
              <BeadComparisonViz />
            </SubSection>

            <SubSection title="What the Agents Do Automatically">
              <P>Once you launch agents with good marching orders, they automatically handle the coordination mechanics. A typical bead thread in Agent Mail looks like this — created entirely by agents, not by you:</P>

              <CodeBlock language="text" code={`[br-103] Start: Failed-ingestion admin screen
Claiming br-103. Reserving admin UI files plus retry handler path.
Will send update once list view is working and retry path is wired.

[br-103] Progress: Main path wired
List view and detail view working. Now handling edge cases and tests.

[br-103] Completed
Admin screen done. List view, detail view, and retry action wired.
Auth checks in place. E2E coverage for malformed upload → admin review → retry.`} />
              <P>You do not write these messages. The agents create them because your AGENTS.md tells them to coordinate through Agent Mail and use bead IDs as thread anchors. Your job is to monitor these threads to see if work is flowing or stuck.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 7: THE OPERATING RHYTHM                                */}
          {/* ============================================================= */}
          <GuideSection id="operating-rhythm" number="7" title="The Operating Rhythm">
            <P highlight>This section describes what <strong>you, the human</strong>, actually do. The agents handle the coordination plumbing (Agent Mail messages, file reservations, bead status updates). Your job is to create the conditions for them to succeed.</P>

            <OperatingRhythmViz />

            <SubSection title="Step 1: Create an Excellent Markdown Plan">
              <P>Before beads or swarms or file reservations, create a serious markdown plan. Do not settle for one quick draft from one model.</P>

              <PromptBlock
                title="Multi-Model Synthesis"
                prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan:

[Paste all plans here]`}
                where="GPT Pro web app with Extended Reasoning, or your strongest available model"
                whyItWorks="Different frontier models have different blind spots. Competitive synthesis forces the model to admit where others are better and merge the strongest ideas."
              />

              <P>At minimum, you want: the user-facing workflows, the important constraints, the major architectural decisions, and the testing expectations.</P>
            </SubSection>

            <SubSection title="Step 2: Tell an Agent to Convert the Plan into Beads">
              <P>You do not need to manually create every bead yourself. Tell a coding agent to do the conversion:</P>

              <PromptBlock
                title="Plan to Beads Conversion"
                prompt={`OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting. The beads should be so detailed that we never need to consult back to the original markdown plan document. Remember to ONLY use the \`br\` tool to create and modify the beads and add the dependencies. Use ultrathink.`}
                where="Claude Code with Opus"
                whyItWorks="Beads become the active source of truth for execution. Once they're strong enough, you never look back at the markdown plan."
              />

              <P>Then polish the beads 4-6 times with fresh review passes. Each round catches things the previous round missed. This is the &quot;measure twice, cut once&quot; of the methodology.</P>

              <TipBox>
                <strong>Beads are executable memory.</strong> The markdown plan is the best artifact for whole-system thought. Beads are the plan after it has been transformed into a format optimized for distributed execution. Weak beads force improvisation. Rich beads make execution mechanical.
              </TipBox>
            </SubSection>

            <SubSection title="Step 3: Launch Agents with Marching Orders">
              <P>Once beads are polished and your AGENTS.md is solid, start up a swarm of agents. Give each one these marching orders:</P>

              <PromptBlock
                title="Swarm Marching Orders"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents.

Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages.

Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately.

When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Use ultrathink.`}
                where="Every agent in the swarm gets this as their initial prompt"
                whyItWorks="Every agent is fungible and a generalist. The specifics come from AGENTS.md and the beads, not from the prompt. This generic prompt works for every project."
              />

              <P>Stagger agent starts by at least 30 seconds to avoid the &quot;thundering herd&quot; problem where all agents grab the same bead. Start smaller than your ego wants to: 1 agent to learn, 2 to feel coordination, 4 for real swarm behavior.</P>
            </SubSection>

            <SubSection title="Step 4: Tend the Swarm">
              <P>Now you are the operator. On roughly a 10-15 minute cadence, check on the swarm:</P>

              <NumberedList items={[
                <>Run <code>bv --robot-triage</code> and check whether the top recommendation still makes sense.</>,
                "Glance through Agent Mail threads — are agents making progress or stuck?",
                "Look for beads stuck in in_progress without movement.",
                <>If an agent seems confused after compaction, send: &quot;Reread AGENTS.md so it&apos;s still fresh in your mind.&quot;</>,
                "If an agent is truly degraded, kill it and start a fresh one.",
              ]} />

              <P>That is usually enough to keep the loop healthy without turning the human into a full-time traffic cop.</P>
            </SubSection>

            <SubSection title="Step 5: Review, Close, Repeat">
              <P>After agents finish each bead, have them review their own work:</P>

              <PromptBlock
                title="Fresh-Eyes Review"
                prompt={`Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. Use ultrathink.`}
                where="After each bead is implemented — run until no more bugs found"
                whyItWorks="Forces a mode switch from writing to adversarial reading while the code is still fresh. One of the cheapest quality multipliers in the whole method."
              />

              <P>Then they move to the next bead using bv to find the most impactful one. The cycle repeats until the graph is done.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 8: THE HUMAN'S JOB                                     */}
          {/* ============================================================= */}
          <GuideSection id="operator" number="8" title="The Human&apos;s Job">
            <P highlight>The human is not supposed to micromanage every code edit or manually coordinate Agent Mail threads. The human is there to keep the structure clean enough that the agents can work effectively inside it.</P>

            <HumanAgentTimelineViz />

            <SubSection title="What You Do">
              <BulletList items={[
                <><strong>Create the plan and beads</strong> — this is where most of your time and thinking goes</>,
                <><strong>Write a good AGENTS.md</strong> — this is the operating manual that makes everything else work</>,
                <><strong>Launch agents with marching orders</strong> — the same generic prompt every time</>,
                <><strong>Keep the bead graph honest</strong> — notice when a missing task or dependency must be added</>,
                <><strong>Restart or redirect agents</strong> when they drift, get loopy, or lose context</>,
                <><strong>Ask the hard question</strong> periodically (see below)</>,
              ]} />
            </SubSection>

            <SubSection title="What the Agents Do (Not You)">
              <BulletList items={[
                "Register with Agent Mail and discover other active agents",
                "Claim beads and announce what they are working on",
                "Reserve files before editing to prevent conflicts",
                "Update bead status (in_progress, closed) as they work",
                "Use bv to find the next best bead when they finish one",
                "Send progress updates and completion messages in Agent Mail threads",
              ]} />
              <P>All of this is configured once in your AGENTS.md. You do not need to manually invoke Agent Mail calls, update bead statuses, or thread bead IDs into messages. The agents do it because the operating manual tells them to.</P>
            </SubSection>

            <SubSection title="The Reality Check">
              <P>When the swarm looks active but you suspect it is not actually closing the real gap, stop and ask:</P>
              <BlockQuote>Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?</BlockQuote>
              <P>If the answer is &quot;no,&quot; the fix is usually not more implementation effort. Revise the bead graph, add missing work, or step back into planning.</P>
            </SubSection>

            <SubSection title="Minimum Viable AGENTS.md">
              <P>Even in the smaller core-loop version, you still need a minimal <code>AGENTS.md</code>. It does not have to be a giant doctrine document, but it should say:</P>
              <BulletList items={[
                "What the repo is for",
                "What the stack is",
                "Any non-negotiable safety or style rules",
                "How to use Agent Mail, br, and bv (include the prepared blurbs from each tool's docs)",
              ]} />
              <BlockQuote>Treat AGENTS.md as the swarm&apos;s durable operating manual. It tells a fresh or partially confused agent how to behave, what tools exist, and what &quot;doing a good job&quot; looks like in this repo.</BlockQuote>

              <TipBox variant="warning">
                <strong>After compaction, agents must re-read AGENTS.md.</strong> If an agent still seems confused or loopy after rereading it, stop trying to rescue the degraded state and start a fresh session instead.
              </TipBox>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 9: COMMON FAILURE MODES                                */}
          {/* ============================================================= */}
          <GuideSection id="failure-modes" number="9" title="Common Failure Modes">
            <DataTable
              headers={["Symptom", "Likely Cause", "Fix"]}
              rows={[
                ["Agents keep overlapping", "AGENTS.md doesn't emphasize Agent Mail claims and reservations enough", "Strengthen the coordination section in AGENTS.md"],
                ["Agents choose random work", "AGENTS.md doesn't explain bv usage clearly", "Add bv usage instructions to AGENTS.md with the robot-flag commands"],
                ["A task keeps stalling", "The bead is underspecified or missing a dependency", "Rewrite the bead or add the missing dependency"],
                ["The swarm feels busy but confused", "The markdown plan was too weak", "Go back up a level and improve the plan before continuing"],
              ]}
            />

            <SubSection title="Agent Disappeared Mid-Bead">
              <P>When an agent vanishes mid-bead, the recovery path should be boring:</P>
              <NumberedList items={[
                "Check the Agent Mail thread for the last meaningful progress update.",
                "Launch a fresh agent with the standard marching orders.",
                "The new agent will read AGENTS.md, discover the abandoned bead via bv, and pick it up.",
                "If the bead was partially completed, the new agent can continue from the code state plus the thread history.",
              ]} />
              <TipBox variant="info">
                If recovery feels hard, the bead or the AGENTS.md was probably too thin. That is a signal to write richer beads and a more thorough operating manual.
              </TipBox>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 10: WHAT IT FEELS LIKE                                  */}
          {/* ============================================================= */}
          <GuideSection id="what-it-feels-like" number="10" title="What It Feels Like Once It Clicks">
            <P>At some point, the workflow stops feeling like extra ceremony and starts feeling like a <Hl>calmer control surface</Hl>:</P>

            <BulletList items={[
              <><strong>Less duplicated work</strong>, because agents manage ownership and reservations automatically</>,
              <><strong>Less &quot;what should I do next?&quot; drift</strong>, because bv keeps answering that question for the agents</>,
              <><strong>Easier restart after context loss</strong>, because the work lives in beads and threads instead of only in chat history</>,
              <><strong>Easier handoff</strong>, because any agent can read the bead, read the thread, and continue</>,
            ]} />

            <P>That operator feeling is a good sign. It usually means the artifacts are carrying the work instead of your short-term memory.</P>

            <SubSection title="Why This Captures Most of the Value">
              <P>People often assume the magic of the Flywheel comes from the total number of tools. It does not. Most of the value comes from three things:</P>
              <NumberedList items={[
                "Work is explicit instead of implicit",
                "Coordination is externalized instead of living in human memory",
                "Task choice is graph-aware instead of random",
              ]} />
              <P>Those three properties are already present in the core loop. That is why the smaller system gets you surprisingly far.</P>
            </SubSection>

            <SubSection title="When Not to Use the Core Loop">
              <P>You probably do not need it for a tiny one-file change with no real dependency structure, a purely local experiment, or a quick one-agent cleanup that does not need externalized coordination.</P>
              <P>The loop earns its keep when work has enough structure, enough ambiguity, or enough parallelism that explicit planning, explicit tasks, and explicit coordination start paying for themselves.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 11: HELPER UTILITIES                                    */}
          {/* ============================================================= */}
          <GuideSection id="helpers" number="11" title="Helper Utilities: DCG, UBS & CASS">
            <P>Once the core loop is running smoothly, three helper utilities significantly improve safety, quality, and learning. They are <Hl>multipliers on top of the core loop</Hl>, not prerequisites.</P>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5 sm:gap-6 my-12">
              <HelperCard
                icon={<Shield className="h-6 w-6" />}
                name="DCG"
                fullName="Destructive Command Guard"
                color="#FF5F56"
                description="A Claude Code hook that blocks dangerous git and filesystem commands before execution. Sub-millisecond latency, mechanical enforcement."
                usage="Works automatically. When a dangerous command is blocked, use safer alternatives or ask the user to run it manually."
                command="dcg test 'rm -rf /' --explain"
              />
              <HelperCard
                icon={<Bug className="h-6 w-6" />}
                name="UBS"
                fullName="Ultimate Bug Scanner"
                color="#FFBD2E"
                description="Multi-language bug scanner with guardrails. Run it on changed files before every commit to catch injection, unquoted variables, and other hazards."
                usage="ubs <changed-files> before every commit. Exit 0 = safe. Exit >0 = fix and re-run."
                command="ubs $(git diff --name-only --cached)"
              />
              <HelperCard
                icon={<Search className="h-6 w-6" />}
                name="CASS"
                fullName="Cross-Agent Session Search"
                color="#a78bfa"
                description="Indexes prior agent conversations so solved problems can be reused. Finds patterns, decisions, and solutions across session history."
                usage="Search before reinventing a solution. If an agent solved a similar problem before, CASS will find it."
                command="cass search 'auth middleware' --robot --limit 5"
              />
            </div>

            <SubSection title="What You Can Ignore for Now">
              <P>If you are just getting started, you do not need to master all of this immediately:</P>
              <BulletList items={[
                "Large-scale session memory systems like CASS and CM",
                "Big prompt libraries",
                "Advanced launch tooling like ntm",
                "The full exhaustive planning doctrine",
                "Every supporting tool in ACFS",
              ]} />
              <P>Those things help. Some help a lot. But they are multipliers on top of the core loop, not prerequisites. You can run the core loop with separate terminal tabs and no special session manager.</P>
            </SubSection>

            <SubSection title="What You Should Not Ignore">
              <P>Even in the smaller version, a few principles still matter a lot:</P>
              <BulletList items={[
                "Do not start a swarm with only vague goals — make a real plan first",
                "Do not treat beads as tiny throwaway todo lines — they need rich context",
                "Do not skip the bead polishing rounds — single-pass beads are never optimal",
                "Do not rely on chat scrollback as your coordination system — that is what Agent Mail is for",
              ]} />
              <P>If you violate those, the workflow quickly degrades back into ordinary multi-agent chaos.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 12: GETTING STARTED & GRADUATION                       */}
          {/* ============================================================= */}
          <GuideSection id="getting-started" number="12" title="Getting Started">
            <SubSection title="The First 30 Minutes">
              <NumberedList items={[
                "Pick one real project, not a toy.",
                "Ask multiple frontier models for competing markdown plans.",
                "Synthesize them into one strong plan.",
                "Tell an agent to create beads from the plan with dependencies.",
                "Polish the beads 4-6 times with fresh review passes.",
                <>Run <code>bv --robot-triage</code> to verify the graph makes sense.</>,
                "Launch 2-4 agents with the standard marching orders.",
                "Tend the swarm. Check every 10-15 minutes.",
              ]} />

              <P>Start smaller than your ego wants to:</P>
              <DataTable
                headers={["Mode", "What It Is Good For"]}
                rows={[
                  ["1 agent", "Learn the artifact flow without coordination overhead"],
                  ["2 agents", "Feel the first real coordination benefits"],
                  ["4 agents", "Experience meaningful swarm behavior where routing and handoff matter"],
                ]}
              />
            </SubSection>

            <SubSection title="Try This Now">
              <P>If you want to feel the method instead of only reading about it:</P>
              <NumberedList items={[
                "Pick one real repo",
                "Write one serious markdown plan",
                "Tell an agent to create two real beads with one dependency",
                <>Run <code>bv --robot-next</code> and check that the recommendation makes sense</>,
                "Launch a second agent with the marching orders and watch them coordinate",
              ]} />
              <P>Those five steps are enough to make the core loop stop feeling theoretical.</P>
            </SubSection>

            <SubSection title="The Cheat Card">
              <P highlight>If you want the loop on one screen, keep this:</P>
              <NumberedList items={[
                "Plan with multiple models",
                "Synthesize into one markdown plan",
                "Tell an agent to create beads",
                "Polish beads 4-6 times",
                "Write a good AGENTS.md",
                "Launch agents with marching orders",
                "Tend the swarm every 10-15 minutes",
                "Have agents do fresh-eyes review after each bead",
                "Repeat until the graph is done",
              ]} />
            </SubSection>

            <SubSection title="When to Graduate to the Full Flywheel">
              <P>Move up to the <a href="/complete-guide" className="text-[#FF5500] hover:text-[#FFBD2E] transition-colors font-medium underline decoration-[#FF5500]/30 underline-offset-4 hover:decoration-[#FFBD2E]/50">full guide</a> when one or more of these becomes true:</P>
              <BulletList items={[
                "Your projects are large enough that you want much richer planning workflows",
                "You want stronger AGENTS.md operating manuals with comprehensive tool documentation",
                "You want repeatable prompt libraries and skills",
                "You want better recovery from compaction and session loss",
                "You want memory systems (CASS, CM) that improve the workflow over time",
              ]} />
              <P>At that point, the bigger document stops feeling like overhead and starts feeling like leverage.</P>
            </SubSection>
          </GuideSection>

          <Divider />
          <FooterCTA />

        </div>
      </main>
    </ErrorBoundary>
  );
}


// =============================================================================
// HERO SECTION
// =============================================================================
function Hero() {
  return (
    <section className="relative overflow-hidden pt-28 pb-24 md:pt-44 md:pb-36 bg-[#020408] border-b border-white/[0.04]">
      {/* Layered ambient effects for depth */}
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-[600px] bg-[radial-gradient(ellipse_at_top,rgba(255,85,0,0.08),transparent_70%)]" />
      {/* Secondary purple orb — lower left for depth */}
      <div className="absolute bottom-0 left-0 w-[500px] h-[500px] bg-[radial-gradient(ellipse_at_bottom_left,rgba(167,139,250,0.05),transparent_70%)] pointer-events-none" />
      {/* Floating amber accent orb */}
      <div className="absolute top-1/3 right-[10%] w-[300px] h-[300px] bg-[radial-gradient(circle,rgba(255,189,46,0.04),transparent_60%)] pointer-events-none animate-[float_8s_ease-in-out_infinite]" />

      <div className="relative mx-auto text-center px-6 z-10 max-w-5xl">
        {/* Badge with shimmer effect */}
        <div className="relative inline-flex items-center gap-3 rounded-full border border-[#FF5500]/20 bg-[#FF5500]/5 px-6 py-2.5 text-[0.7rem] font-black uppercase tracking-[0.3em] text-[#FF5500] mb-10 shadow-[0_0_20px_rgba(255,85,0,0.15)] backdrop-blur-xl overflow-hidden">
          <div className="absolute inset-0 bg-[linear-gradient(110deg,transparent_25%,rgba(255,85,0,0.12)_50%,transparent_75%)] bg-[length:200%_100%] animate-[shimmer_3s_ease-in-out_infinite] pointer-events-none" />
          <Sparkles className="h-4 w-4 relative z-10" />
          <span className="relative z-10">The Focused Version</span>
        </div>

        <h1 className="text-[2.25rem] sm:text-[2.75rem] md:text-7xl lg:text-8xl font-black text-white tracking-tighter drop-shadow-2xl leading-[1.05]">
          The Core <br/><span className="bg-gradient-to-r from-[#FF5500] to-[#FFBD2E] bg-clip-text text-transparent">Flywheel</span>
        </h1>

        <p className="mx-auto mt-8 sm:mt-10 max-w-2xl sm:max-w-3xl text-lg sm:text-xl md:text-2xl text-zinc-400 leading-relaxed font-light">
          Three tools. One loop. Most of the value. Learn the beginner-friendly core of the Agentic Coding Flywheel: <Hl>Agent Mail</Hl> for coordination, <Hl>br</Hl> for task structure, and <Hl>bv</Hl> for intelligent routing.
        </p>

        <div className="mt-10 sm:mt-12 flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-4">
          <a
            href="#core-loop"
            className="w-full sm:w-auto inline-flex items-center justify-center rounded-2xl bg-[#FF5500] px-8 py-4 text-sm font-black text-black uppercase tracking-widest transition-all duration-300 hover:bg-[#FFBD2E] hover:shadow-[0_0_40px_rgba(255,189,46,0.4)] hover:-translate-y-1 active:scale-95"
          >
            Start Learning
          </a>
          <a
            href="/complete-guide"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-2xl border border-white/10 bg-white/[0.02] px-8 py-4 text-sm font-bold text-zinc-400 uppercase tracking-widest transition-all duration-300 hover:border-[#FF5500]/30 hover:text-white hover:-translate-y-1 hover:bg-white/[0.04]"
          >
            Full Guide <ArrowRight className="h-4 w-4" />
          </a>
        </div>

        {/* Scroll indicator */}
        <div className="mt-16 md:mt-20 flex flex-col items-center gap-2 animate-[float_3s_ease-in-out_infinite]">
          <span className="text-[0.6rem] font-bold uppercase tracking-[0.3em] text-white/20">Scroll to explore</span>
          <ChevronDown className="h-4 w-4 text-white/20" />
        </div>
      </div>
    </section>
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
    <div
      className="group relative flex flex-col rounded-[2rem] border border-white/[0.04] bg-[#05070A] overflow-hidden transition-all duration-500 hover:-translate-y-2 shadow-2xl"
      style={{ ['--card-color' as string]: color }}
    >
      {/* Colored top accent bar */}
      <div
        className="h-[2px] w-full opacity-40 group-hover:opacity-80 transition-opacity duration-500"
        style={{ background: `linear-gradient(90deg, transparent, ${color}, transparent)` }}
      />

      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div
        className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 pointer-events-none"
        style={{ background: `radial-gradient(ellipse at top, ${color}0A, transparent 70%)` }}
      />

      <div className="relative z-10 flex flex-col h-full gap-5 p-6 sm:p-8">
        {/* Icon with glow on hover */}
        <div
          className="flex h-12 w-12 items-center justify-center rounded-xl border transition-all duration-500 group-hover:scale-110"
          style={{
            borderColor: `${color}33`,
            backgroundColor: `${color}0D`,
            color: color,
          }}
        >
          <div className="transition-all duration-500 group-hover:drop-shadow-[0_0_8px_var(--card-color)]">
            {icon}
          </div>
        </div>

        <div>
          <div className="text-[0.6rem] font-bold uppercase tracking-[0.2em] opacity-50 group-hover:opacity-70 transition-opacity duration-500" style={{ color }}>
            {fullName}
          </div>
          <h4 className="text-2xl font-black text-white tracking-tight mt-1">
            {name}
          </h4>
        </div>

        <p className="text-[0.95rem] text-zinc-400 font-light leading-relaxed flex-1">
          {description}
        </p>

        <div className="pt-5 border-t border-white/[0.04] space-y-3">
          <div>
            <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-[0.15em] block mb-1.5">Usage</span>
            <p className="text-[0.85rem] text-zinc-400 font-light leading-relaxed">{usage}</p>
          </div>
          <code
            className="block text-[0.8rem] text-zinc-500 font-mono bg-white/[0.02] rounded-lg px-3 py-2.5 border-l-2 border border-white/[0.04] transition-colors duration-500 group-hover:text-zinc-400"
            style={{ borderLeftColor: `${color}40` }}
          >
            {command}
          </code>
        </div>
      </div>
    </div>
  );
}


// =============================================================================
// FOOTER CTA
// =============================================================================
function FooterCTA() {
  return (
    <section className="relative overflow-hidden rounded-[3rem] border border-[#FF5500]/20 bg-[#0A0D14] py-24 md:py-32 my-32 shadow-[0_50px_100px_-20px_rgba(255,85,0,0.15)] group">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      {/* Multi-layer gradient effects */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full bg-[radial-gradient(ellipse_at_center,rgba(255,85,0,0.05),transparent_70%)] opacity-0 group-hover:opacity-100 transition-opacity duration-1000" />
      <div className="absolute -top-20 -right-20 w-[300px] h-[300px] bg-[radial-gradient(circle,rgba(255,189,46,0.06),transparent_60%)] pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-1000 delay-200" />
      <div className="absolute -bottom-20 -left-20 w-[300px] h-[300px] bg-[radial-gradient(circle,rgba(167,139,250,0.04),transparent_60%)] pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-1000 delay-300" />

      <div className="relative mx-auto text-center px-6 z-10">
        {/* Badge with shimmer */}
        <div className="relative inline-flex items-center gap-3 rounded-full border border-[#FF5500]/30 bg-[#FF5500]/10 px-6 py-2.5 text-[0.7rem] font-black uppercase tracking-[0.3em] text-[#FF5500] mb-10 shadow-inner overflow-hidden">
          <div className="absolute inset-0 bg-[linear-gradient(110deg,transparent_25%,rgba(255,85,0,0.15)_50%,transparent_75%)] bg-[length:200%_100%] animate-[shimmer_3s_ease-in-out_infinite] pointer-events-none" />
          <Rocket className="h-4 w-4 relative z-10" />
          <span className="relative z-10">Ready for More?</span>
        </div>

        <h2 className="text-3xl sm:text-5xl md:text-6xl font-black text-white tracking-tighter drop-shadow-2xl">
          Graduate to the Full <span className="bg-gradient-to-r from-[#FF5500] to-[#FFBD2E] bg-clip-text text-transparent">Flywheel</span>
        </h2>

        <p className="mx-auto mt-8 max-w-2xl text-base sm:text-lg text-zinc-400 leading-relaxed font-light">
          Once the core loop feels natural, the full methodology adds richer planning workflows, memory systems, prompt libraries, and the complete Dicklesworthstone stack.
        </p>

        <div className="mt-10 sm:mt-12 flex flex-col sm:flex-row justify-center gap-3 sm:gap-4">
          <a
            href="/complete-guide"
            className="w-full sm:w-auto inline-flex items-center justify-center rounded-2xl bg-[#FF5500] px-8 py-4 text-sm font-black text-black uppercase tracking-widest transition-all duration-300 hover:bg-[#FFBD2E] hover:shadow-[0_0_40px_rgba(255,189,46,0.4)] hover:-translate-y-1 active:scale-95"
          >
            Read the Full Guide
          </a>
          <a
            href="/wizard/os-selection"
            className="w-full sm:w-auto inline-flex items-center justify-center rounded-2xl border border-white/10 bg-white/[0.02] px-8 py-4 text-sm font-bold text-zinc-400 uppercase tracking-widest transition-all duration-300 hover:border-[#FF5500]/30 hover:text-white hover:-translate-y-1 hover:bg-white/[0.04]"
          >
            Install the Stack
          </a>
        </div>
      </div>
    </section>
  );
}
