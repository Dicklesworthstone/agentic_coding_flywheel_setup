import Link from "next/link";
import { Fragment } from "react";
import { AgentMailViz } from "@/components/complete-guide/agent-mail-viz";
import { ContextHorizonViz } from "@/components/complete-guide/context-horizon-viz";
import { ConvergenceViz } from "@/components/complete-guide/convergence-viz";
import { CoordinationTrioViz } from "@/components/complete-guide/coordination-trio-viz";
import { CrashRecoveryViz } from "@/components/complete-guide/crash-recovery-viz";
import { FlywheelDiagram } from "@/components/complete-guide/flywheel-diagram";
import {
  BlockQuote,
  BulletList,
  CodeBlock,
  DataTable,
  GuideArticle,
  GuideNav,
  GuideSection,
  Hl,
  IllustrativeDisclosure,
  NumberedList,
  P,
  PromptBlock,
  SkillNote,
  StatCard,
  SubSection,
  TipBox,
} from "@/components/complete-guide/guide-components";
import { GuideColophon, GuideFooterCTA, GuideHero } from "@/components/complete-guide/guide-shell";
import { PlanEvolutionStudio } from "@/components/complete-guide/plan-evolution-studio";
import { PlanToBeadsViz } from "@/components/complete-guide/plan-to-beads-viz";
import { RecursiveImprovementViz } from "@/components/complete-guide/recursive-improvement-viz";
import { RepresentationLadder } from "@/components/complete-guide/representation-ladder";
import { SwarmExecutionViz } from "@/components/complete-guide/swarm-execution-comparison";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import { buildInstallCommand } from "@/lib/commandBuilder";
import {
  COMPLETE_GUIDE_MODEL_SOURCES,
  COMPLETE_GUIDE_MODELS,
  COMPLETE_GUIDE_PHASE_COUNT,
  COMPLETE_GUIDE_PROMPT_COUNT,
  COMPLETE_GUIDE_REVIEWED_ON,
  VALIDATION_GATES,
} from "@/lib/complete-guide";
import { manifestModules, manifestProvenance } from "@/lib/generated/manifest-modules";
import { manifestTools } from "@/lib/generated/manifest-tools";
import { COMPLETE_GUIDE_OUTLINE, guidePartCount } from "@/lib/guide-outlines";

const enabledStackModuleIds = new Set(
  manifestModules
    .filter((module) => module.category === "stack" && module.enabledByDefault)
    .map((module) => module.id),
);
const COMPLETE_GUIDE_STACK_TOOLS = manifestTools.filter((tool) =>
  enabledStackModuleIds.has(tool.moduleId),
);
const COMPLETE_GUIDE_STACK_TOOL_COUNT = COMPLETE_GUIDE_STACK_TOOLS.length;
const COMPLETE_GUIDE_PINNED_INSTALL_REF = `v${manifestProvenance.acfsVersion}`;

const CURRENT_INSTALL_COMMAND = buildInstallCommand("vibe", null);
const PINNED_INSTALL_COMMAND = buildInstallCommand("vibe", COMPLETE_GUIDE_PINNED_INSTALL_REF);
const STACK_TOOL_ROWS = COMPLETE_GUIDE_STACK_TOOLS.map((tool) => [
  tool.displayName,
  [tool.cliName, ...tool.cliAliases].filter(Boolean).join(", ") || "—",
  tool.shortDesc,
]);

// The interlude is unnumbered, so the cover counts parts, not nav entries.
const GUIDE_PART_COUNT = guidePartCount(COMPLETE_GUIDE_OUTLINE);

export default function CompleteGuidePage() {
  return (
    <ErrorBoundary>
      {/* overflow-x-clip (not hidden) keeps the page from scrolling sideways
          without turning <main> into a scroll container, which would defeat
          the sticky section navigation. */}
      <main
        id="main-content"
        tabIndex={-1}
        className="text-aa-floor min-h-screen bg-[#020408] pb-24 outline-none selection:bg-[#FF5500]/25 selection:text-white overflow-x-clip sm:pb-32"
      >
        <GuideHero
          current="complete"
          eyebrow="The complete guide"
          title={
            <>
              The Agentic Coding <em className="italic text-[#FF5500]">Flywheel</em>
            </>
          }
          dek={
            <>
              How I build software by orchestrating swarms of AI coding agents: exhaustive
              markdown plans, polished beads, and the Agent Flywheel stack, end to end. By
              Jeffrey Emanuel.
            </>
          }
          primary={{ href: "#workflow", label: "Start reading" }}
          secondary={{ href: "/wizard/os-selection", label: "Set up the stack" }}
          note={
            <>
              New to agentic coding?{" "}
              <Link
                href="/core-flywheel"
                className="font-medium text-zinc-200 underline decoration-[#FF5500]/60 underline-offset-4 transition-colors hover:text-white"
              >
                Start with the Core Flywheel
              </Link>
              , the three-tool version. Last reviewed {COMPLETE_GUIDE_REVIEWED_ON}.
            </>
          }
          stats={[
            { value: String(GUIDE_PART_COUNT), label: "Parts" },
            { value: String(COMPLETE_GUIDE_PROMPT_COUNT), label: "Copy-ready prompts" },
            { value: String(COMPLETE_GUIDE_PHASE_COUNT), label: "Phases" },
            { value: String(COMPLETE_GUIDE_STACK_TOOL_COUNT), label: "Stack tools" },
          ]}
          contents={COMPLETE_GUIDE_OUTLINE}
          promptCount={COMPLETE_GUIDE_PROMPT_COUNT}
        />

        <div className="relative mx-auto max-w-[1320px] px-5 sm:px-8 xl:grid xl:grid-cols-[14.5rem_minmax(0,1fr)] xl:gap-14 xl:px-10 2xl:grid-cols-[16rem_minmax(0,1fr)] 2xl:gap-20">
          <GuideNav
            items={COMPLETE_GUIDE_OUTLINE}
            title="The complete guide"
            promptCount={COMPLETE_GUIDE_PROMPT_COUNT}
          />
          <GuideArticle outline={COMPLETE_GUIDE_OUTLINE}>

          {/* ============================================================= */}
          {/* SECTION 1: THE COMPLETE WORKFLOW                                */}
          {/* ============================================================= */}
          <GuideSection id="workflow">
            <P highlight>
              This is the end-to-end methodology for creating software with frontier AI models,
              exhaustive markdown planning, beads-based task management, and coordinated agent
              swarms. Every project follows the same arc, whether it is a small CLI tool or a
              complex web application. The central idea of this guide is to move the hardest thinking into
              representations that still fit into model context windows.
            </P>

            <FlywheelDiagram />
            <IllustrativeDisclosure />

            <P>
              It starts with your idea for a piece of software. Instead of opening an editor and
              starting to code, you spend the vast majority of your time planning, which feels
              backwards at first.
            </P>

            <NumberedList
              items={[
                <Fragment key="explain-build">
                  <strong>You explain what you want to build</strong> to one lead planner,{" "}
                  {COMPLETE_GUIDE_MODELS.leadPlanner} in {COMPLETE_GUIDE_MODELS.leadPlannerSurface}
                  . Your concept, your goals, the user workflows, why it matters, and which of your
                  earlier projects it should be modeled on. The lead studies those projects, sends
                  research subagents out, and writes the first markdown plan: a design document for
                  the entire system. It stays in charge of the project from then on.
                </Fragment>,
                <Fragment key="competing-plans">
                  <strong>You ask other model families for competing plans.</strong>{" "}
                  {COMPLETE_GUIDE_MODELS.gptPro} in {COMPLETE_GUIDE_MODELS.gptProSurface},{" "}
                  {COMPLETE_GUIDE_MODELS.openaiPlanner} in Codex, and{" "}
                  {COMPLETE_GUIDE_MODELS.antigravity} in Antigravity get the same kickoff and plan
                  without seeing each other&apos;s work. Their approaches differ more than you would
                  expect, and each has its own strengths and blind spots.
                </Fragment>,
                <Fragment key="synthesize-plans">
                  <strong>The lead blends the best ideas from all plans into one.</strong> It
                  admits what the competing plans did better, merges them into a &quot;best of all
                  worlds&quot; hybrid, and checks every fact it takes from another model.
                </Fragment>,
                <Fragment key="iterate-relentlessly">
                  <strong>You iterate relentlessly.</strong> Round after round of review, each in a
                  fresh {COMPLETE_GUIDE_MODELS.gptPro} conversation or by models and subagents that
                  did not write the plan, with the lead integrating each round, until reviewers stop
                  finding substantive problems. Recent plans run to hundreds of kilobytes of
                  markdown, and the length comes from those rounds.
                </Fragment>,
                <Fragment key="convert-to-beads">
                  <strong>You convert the plan into beads.</strong> Beads are self-contained work
                  units (like Jira or Linear tasks, but optimized for use by coding agents). Each
                  bead carries its own context, reasoning, dependencies, and test obligations. A
                  complex plan might produce 200-500 beads with a full dependency graph.
                </Fragment>,
                <Fragment key="polish-beads">
                  <strong>You polish the beads obsessively.</strong> &quot;Check your beads N times,
                  implement once,&quot; where N is as many as you can stomach. Each polishing round
                  finds things the previous round missed: duplicates, missing dependencies,
                  incomplete context. I usually run at least 8 to 10 rounds.
                </Fragment>,
                <Fragment key="launch-swarm">
                  <strong>You launch a swarm of agents.</strong> Claude Code, Codex, and Antigravity
                  CLI sessions running in parallel, all in the same codebase. They coordinate
                  through Agent Mail, choose work using bv&apos;s graph-theory routing, and
                  execute the beads.
                </Fragment>,
                <Fragment key="tend-swarm">
                  <strong>You tend the swarm, not the code.</strong> The human checks for stuck
                  beads, rescues agents after context compaction, and sends review prompts. You are
                  the clockwork deity. You designed the machine, set it
                  running, and now you manage it.
                </Fragment>,
                <Fragment key="review-test-harden">
                  <strong>Agents review, test, and harden.</strong> Self-review with fresh eyes,
                  cross-agent review, random code exploration, testing coverage, UI/UX polish. The
                  rounds continue until reviews come back clean.
                </Fragment>,
              ]}
            />

            <P>
              For the CASS Memory System, this process turned a 5,500-line
              markdown plan into 347 beads. Twenty-five agents produced 11,000 lines of working,
              tested code with 204 commits in about five hours. You can see the{" "}
              <a
                href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/docs/planning/PLAN_FOR_CASS_MEMORY_SYSTEM.md"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                actual plan
              </a>
              , the{" "}
              <a
                href="https://dicklesworthstone.github.io/cass-memory-system-agent-mailbox-viewer/viewer/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                actual agent mail messages
              </a>
              , and the{" "}
              <a
                href="https://dicklesworthstone.github.io/beads_for_cass_memory_system/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                actual beads
              </a>{" "}
              for yourself.
            </P>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 my-12">
              <StatCard
                value="5,500"
                label="Line Plan"
                sublabel="Synthesized from 4 frontier models"
              />
              <StatCard value="347" label="Beads" sublabel="With full dependency structure" />
              <StatCard
                value="11k"
                label="Lines of Code"
                sublabel="Working and tested"
              />
              <StatCard value="~5 hrs" label="To Ship" sublabel="25 agents, 204 commits" />
            </div>

            <BlockQuote>
              Once you have the beads in good shape based on a great markdown plan, I almost view
              the project as a foregone conclusion at that point. The rest is basically mindless
              &quot;machine tending&quot; of your swarm of 5-15 agents.
            </BlockQuote>

            <P>
              Current frontier models and coding agent harnesses are already good enough for this.
              What they need is the extra tooling, prompting, and workflow structure described
              here. The rest of this guide goes through each stage in turn.
            </P>

            <SubSection title="Glossary">
              <DataTable
                headers={["Term", "Plain-English Meaning", "Why It Matters"]}
                rows={[
                  [
                    "Markdown plan",
                    "A huge design document where the whole project still fits in context",
                    "Where architecture, workflows, tradeoffs, and intent get worked out",
                  ],
                  [
                    "Bead",
                    "A self-contained work unit in br with context, dependencies, and test obligations",
                    "What agents execute",
                  ],
                  [
                    "Bead graph",
                    "The full dependency structure across all beads",
                    "What lets bv compute the right next work",
                  ],
                  [
                    "Plan space",
                    "The reasoning mode where you are still shaping the whole system",
                    "The cheapest place to buy correctness",
                  ],
                  [
                    "Bead space",
                    "The reasoning mode where you are shaping executable work packets",
                    "Where planning becomes swarm-ready",
                  ],
                  [
                    "Code space",
                    "The implementation and verification layer inside the codebase",
                    "Where local execution happens",
                  ],
                  [
                    "AGENTS.md",
                    "The operating manual every agent must reload after compaction",
                    "Keeps the swarm from forgetting how to behave",
                  ],
                  [
                    "Skill",
                    "A reusable instruction bundle that teaches agents how to use a tool or execute a workflow",
                    'How methods become repeatable instead of staying as tacit lore; the "Skill for this step" notes point to ready-made ones',
                  ],
                  [
                    "Compaction",
                    "Context compression inside a long-running agent session",
                    "Why re-reading AGENTS.md is mandatory",
                  ],
                  [
                    "Fungible agents",
                    "Generalist agents that can replace one another",
                    "Makes crashes and amnesia survivable",
                  ],
                ]}
              />
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 2: WHY PLANNING DOMINATES                              */}
          {/* ============================================================= */}
          <GuideSection id="philosophy">
            <P>
              Most of your time goes into planning, which means everything before the swarm starts
              executing beads: first the markdown plan, then creating and polishing the beads,
              which takes me nearly as long as writing the plan. The first time you try it, it
              feels wrong: no code is being written, and every instinct tells you to start
              building. That discomfort is normal.
            </P>

            <BlockQuote>
              The models are far smarter when reasoning about a plan that is very detailed and
              fleshed out but still trivially small enough to easily fit within their context
              window. This is really the key insight behind my obsessive focus on planning and why I
              spend 80%+ of my time on that part.
            </BlockQuote>

            <ContextHorizonViz />
            <IllustrativeDisclosure />

            <P>
              A markdown plan, even one of several hundred kilobytes, is much smaller than the
              codebase it describes. When models reason about a plan instead of raw implementation, they can
              hold the <Hl>whole system in their context window at once</Hl>. Once you start turning
              that plan into code, the system quickly becomes too large to understand as a whole.
              Planning first lets you do global reasoning while it is still possible.
            </P>

            <BlockQuote>
              I think you get a better result faster by creating one big comprehensive, detailed,
              granular plan. That&apos;s the only way to get these models to use their big brains to
              understand the entire system all at the same time.
            </BlockQuote>

            <P>
              Planning tokens are far fewer and cheaper than implementation tokens. A big, complex
              markdown plan is shorter than a few substantive code files, let alone a whole project.
              That means you can afford many more refinement rounds in planning than in
              implementation. Each planning round weighs consequences across the whole system, and
              each improvement to the plan pays off in every downstream bead and code change. That
              makes planning the cheapest place to buy correctness.
            </P>

            <BlockQuote>
              For the past two years, I&apos;ve been stressing the paramount importance of the
              planning process in agentic software development. It&apos;s where I spend 90%+ of my
              human time and energy.
            </BlockQuote>

            <P>
              Without front-loaded planning, agents are effectively improvising architecture from a
              narrow local window into the codebase. That is when you get placeholder abstractions,
              missing workflow details, contradictory assumptions, and compatibility shims that
              nobody wanted. With a detailed plan and polished beads, the models implement a design
              that has already been worked out, so they do not have to invent the system while they
              code.
            </P>

            <SubSection title="The Human Part">
              <BlockQuote>
                The plan creation is the most free form, creative, human part of the process. I just
                usually start writing in a messy stream of thought way to convey the basic concept
                and then collaboratively work the agent to flesh it out in an initial draft.
              </BlockQuote>

              <P>
                The agent fleshes out most of the plan. The human supplies intent, judgment, taste,
                and product sense at the point where those choices affect the entire downstream
                system. Once the plan is excellent, the rest becomes much more mechanical.
              </P>

              <P>
                The whole approach is built to get the most out of my human time, the one resource
                I can&apos;t buy more of. Tokens and agent time I can add by stacking accounts and
                running more projects in parallel. So I spend my attention where it changes the
                whole system, on the plan and the beads, and hand most of what follows to the
                agents.
              </P>

              <P>
                When prompting the model to create the initial markdown plan, you spend a lot of
                time explaining the goals and intent of the project and detailing the workflows: how
                you want the final software to work from the standpoint of the user&apos;s
                interactions. The more the model understands about what you are trying to
                accomplish and why, the better a job it can do.
              </P>

              <P>
                Settle as many important disagreements as possible in planning, before the swarm
                starts burning expensive implementation tokens. Implementation can still surface
                surprises, but the workflow front-loads decisions into plan space.
              </P>
            </SubSection>

            <SubSection title="You Don't Need to Know Everything Upfront">
              <P>
                The most common objection to spending most of your time on planning: &quot;I
                don&apos;t really know all the requirements at the beginning, and I need the
                flexibility to change things later.&quot; This is not at all in tension with the
                methodology. Thorough planning uses frontier models to{" "}
                <Hl>discover requirements you never would have found on your own</Hl>, iteratively,
                while changes are still cheap, so you do not need to know them in advance.
              </P>

              <P>
                Give a rough concept to {COMPLETE_GUIDE_MODELS.leadPlanner}, ask for a detailed
                plan, and the model surfaces dozens of edge cases, architectural considerations,
                and workflow details you had not thought of. Have two other model families plan
                the same project and each finds blind spots the others missed. Run several review
                rounds and each round turns up issues the previous one did not. By the time you
                start implementation, you have learned much of what months of coding and
                refactoring would otherwise have taught you about your own project.
              </P>

              <P>
                The same applies when adding major features to existing projects. You can point an
                agent at a separate open-source project, have it study that project&apos;s
                architecture, and ask it to reimagine the strongest ideas in terms of what your own
                project can do. The requirements come out of that research. What the methodology
                asks of you is the patience to let the models explore iteratively before you commit
                to implementation.
              </P>

              <BlockQuote>
                And that isn&apos;t at all in tension with my approach, as I hope to illustrate
                here.
              </BlockQuote>
            </SubSection>

            <SubSection title="Three Reasoning Spaces">
              <P>
                The methodology separates work into three spaces, each with a different artifact and
                a different question it answers:
              </P>

              <RepresentationLadder />

              <DataTable
                headers={["Space", "Primary Artifact", "What You Decide There"]}
                rows={[
                  [
                    "Plan space",
                    "Large markdown plan",
                    "Architecture, features, workflows, and tradeoffs, while the whole system still fits in context",
                  ],
                  [
                    "Bead space",
                    "br issues + dependency graph",
                    "Task boundaries, execution order, and embedded context, because agents need explicit, local work units",
                  ],
                  [
                    "Code space",
                    "Source files + tests",
                    "Implementation and verification; the plan has already constrained the high-level decisions",
                  ],
                ]}
              />

              <P>
                Plan space and bead space together are planning; code space is implementation,
                where the swarm executes the beads. Plan space is where you figure out what the
                system should be. Bead space is where
                you turn that into <Hl>executable memory</Hl>, a graph of self-contained work units
                detailed enough that agents don&apos;t have to keep consulting the full plan. Code
                space is where agents implement, review, and test locally. Know which space you are
                in: if you are still redesigning the product, stay in plan space.
                If you are mainly packaging the work for execution, move to bead space.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 3: CREATING & REFINING THE PLAN                        */}
          {/* ============================================================= */}
          <GuideSection id="planning">
            <SubSection title="Before You Start: Build on Your Earlier Projects">
              <P>
                Skip the tech-stack decision and the folder of best-practices guides, and start
                from projects you have already finished. Name your two or three most similar
                earlier projects in the kickoff, and have the lead planner read their comprehensive
                plans, AGENTS.md files, and READMEs and model the new ones on them: the same kinds
                of sections, the same document controls, and the rules their mistakes taught. The
                mining plan, for example, keeps its delivery log out of the plan because an
                earlier plan&apos;s log had grown to 82% of its length.
              </P>

              <P>
                The stack then follows from what those projects already stand on. My recent
                projects take no third-party dependencies beyond my own libraries, so my kickoffs
                settle the stack in one sentence (&quot;the same architecture built on
                asupersync and my existing frankensuite of projects&quot;), and the research goes
                into those libraries instead of into choosing frameworks. The plan opens with a{" "}
                <Hl>foundation audit</Hl>: what each library actually provides at a pinned
                revision, what it lacks and the project must build, and what the project does if
                a foundation stalls. A lock file records each pin, the parts of the project allowed
                to use it, and its fallback. If you have no libraries of your own yet, the same rule
                holds for whatever you build on: the plan should check each component against its
                source at a pinned version rather than trusting its documentation. Much of the
                first review of my accounting plan corrected what the plan had assumed its database
                could do.
              </P>

              <P>
                Give the lead the raw material of the domain, too. For a mining project, I put
                eighteen source documents (technical reports, spreadsheets and textbooks; 4,299
                pages) in a git-ignored folder, and agents converted them to markdown and read
                them against the original pages and cells. Other subagents surveyed my own
                repositories and the state of the field, and a web pass checked 72 of the plan&apos;s
                industry figures, correcting or qualifying 17. When the lead came back with a list
                of open questions, my whole reply was &quot;YOU can find ALL of this stuff yourself
                using web search tools, don&apos;t be helpless!!!&quot;
              </P>

              <P>
                Make the plan say how it knows each thing. The mining plan labels every
                load-bearing statement FACT (verified in a cited file, filing or publication),
                DESIGN (a decision, with its rationale), HYPOTHESIS (with the test that would
                confirm or kill it), TARGET (a number to hit, not yet measured) or OPEN (undecided,
                with an owner), and it counts an unlabeled number as a defect in the plan.
              </P>

              <P>
                Copy AGENTS.md from your most mature project: keep its general rules, safety notes,
                tool sections and coordination guidance, and replace its project doctrine with the
                new plan&apos;s. Write the README in the present tense, as if the finished system
                already exists, with a short note saying so and an honest status section. It then
                gets corrected in place as milestones land instead of being rewritten later. My graph
                database, accounting, and mining projects each began with a first commit holding the
                plan, the README, and AGENTS.md, and no code.
              </P>

              <TipBox variant="warning">
                A plan that relies on something its foundations do not actually provide hides the
                gap until implementation, where it surfaces as bad beads and confused agents. Check
                foundation claims against the source before the review rounds start.
              </TipBox>
            </SubSection>

            <SubSection title="Writing the Initial Plan">
              <P>
                You don&apos;t write the initial markdown plan yourself. As of{" "}
                {COMPLETE_GUIDE_REVIEWED_ON}, I recommend one lead planner,{" "}
                {COMPLETE_GUIDE_MODELS.leadPlanner} in {COMPLETE_GUIDE_MODELS.leadPlannerSurface}{" "}
                (pick it with <code>/model</code>, then set <code>/effort xhigh</code>), in charge
                of the whole project. It writes the plan, commissions the research and the reviews,
                blends in the other models&apos; work, turns the plan into beads, and runs the
                swarm. {COMPLETE_GUIDE_MODELS.gptPro} (the &quot;GPT Pro&quot; option in{" "}
                {COMPLETE_GUIDE_MODELS.gptProSurface}, on any ChatGPT Pro plan) is its main
                partner: it writes a competing first draft and then runs the review rounds.{" "}
                {COMPLETE_GUIDE_MODELS.openaiPlanner} in Codex and{" "}
                {COMPLETE_GUIDE_MODELS.antigravity} in Antigravity write further competing plans and
                audit the lead&apos;s. Provider access, quotas, and model names change, so treat
                this dated recommendation as a starting point rather than an evergreen ranking.
              </P>

              <P>
                The kickoff is one long message. This is the one I sent for the mining project, with
                the subject matter replaced by placeholders:
              </P>

              <PromptBlock
                title="New Project Kickoff"
                prompt={`I want you to carefully study the comprehensive plan documents (they are .md files with the word "COMPREHENSIVE" in the file name) from some of my recent projects in ~/projects , namely <project_a> , <project_b>, and <project_c>. Then I want you to conceive of a new project called <NewProject> (<new_project>) that does what those projects do for the subject of <your domain>. It would cover every aspect of <your domain> [who uses it, every workflow from start to finish, what they are trying to optimize, and which of your existing projects handles which part]. And we want to mimic for <NewProject> the same architecture built on <your core library> and my existing <suite> of projects (you can see the most developed ones in ~/projects). Use /planning-workflow and /idea-wizard and /modes-of-reasoning-project-analysis and /brennerbot-with-ntm for coming up with the very best plan document. We will also be doing multiple rounds of refinement, expansion, and improvement of whatever you write in your first plan draft using other models, but try to do as good and complete and optimal a job as possible on your first pass on the plan. Really think profoundly and deeply on this.`}
                where={`The lead planner: ${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface}, at xhigh effort`}
                whyItWorks="The earlier plans give the model a worked example of the structure and depth you expect, so it does not invent a format. Naming the foundations settles the stack in one sentence. Telling the model that other models will revise its draft, while asking for the best possible first pass, keeps it from holding work back for later rounds. The named skills give it a method for research, hypotheses, and ideas instead of a blank page."
              />

              <P>
                The lead does the rest itself. On the mining project it started seven research
                subagents within eight minutes of the kickoff, ran hypothesis passes as further
                subagents, and had a first plan of about 6,900 lines five hours later. Over the
                next days I added a handful of short steering notes, such as pointing it at my
                numerical libraries and at the source documents.
              </P>

              <DataTable
                headers={["Role", "Current Recommendation", "Operational Note"]}
                rows={[
                  [
                    "Lead planner, in charge of the project",
                    `${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface}`,
                    "Writes and blends the plan, commissions reviews, makes the beads, runs the swarm",
                  ],
                  [
                    "Competing first draft and plan-review rounds",
                    `${COMPLETE_GUIDE_MODELS.gptPro} in ${COMPLETE_GUIDE_MODELS.gptProSurface}`,
                    "A fresh conversation for each round; paste its revisions into the lead to integrate",
                  ],
                  [
                    "Competing plan and adversarial review",
                    `${COMPLETE_GUIDE_MODELS.openaiPlanner} in Codex`,
                    "Gets the same kickoff as the lead; later audits the plan and revises it in place",
                  ],
                  [
                    "Third plan and review panes",
                    `${COMPLETE_GUIDE_MODELS.antigravity} in Antigravity`,
                    "The ACFS-pinned agy profile",
                  ],
                  [
                    "Claude implementation",
                    COMPLETE_GUIDE_MODELS.claudeExecutor,
                    `${COMPLETE_GUIDE_MODELS.claudeFallback} is the faster, lower-cost fallback`,
                  ],
                  [
                    "Codex implementation",
                    COMPLETE_GUIDE_MODELS.codexExecutor,
                    "What the ACFS cod alias runs, at xhigh effort",
                  ],
                ]}
              />

              <TipBox variant="info">
                <strong>Sources reviewed {COMPLETE_GUIDE_REVIEWED_ON}:</strong>{" "}
                {COMPLETE_GUIDE_MODEL_SOURCES.map((source, index) => (
                  <span key={source.provider}>
                    {index > 0 ? "; " : ""}
                    <a
                      href={source.href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[#FF5500] underline underline-offset-4"
                    >
                      {source.provider}
                    </a>{" "}
                    ({source.note})
                  </span>
                ))}
                . I leave {COMPLETE_GUIDE_MODELS.restrictedPreview} out of the recommendation
                because access is restricted to Anthropic&apos;s Life Sciences and Cyber Verification
                programs and it is not generally available.
              </TipBox>
            </SubSection>

            <SubSection title="What a First Plan Looks Like">
              <P>
                A first serious markdown plan would not say &quot;build a notes app.&quot; It would
                start spelling out the actual user-visible system:
              </P>

              <BulletList
                items={[
                  "Users upload Markdown files through a drag-and-drop UI.",
                  "The system parses frontmatter tags and stores upload failures for review.",
                  "Search must support keyword, tag, and date filtering with low perceived latency.",
                  "Admins need a dedicated screen showing ingestion failures, parse reasons, and retry actions.",
                  "Auth is internal-only; unauthorized users must never see document content or metadata.",
                  "We need e2e coverage for upload success, upload failure, search, filtering, and admin review.",
                ]}
              />

              <P>
                That is only the beginning, but it already shows how Flywheel planning differs from
                ordinary brainstorming: the plan tries to make the whole product legible before any
                code exists.
              </P>
            </SubSection>

            <SubSection title="Multi-Model Plans">
              <P>
                For the best results, have other models plan the same project independently while
                the lead writes its own: {COMPLETE_GUIDE_MODELS.gptPro} in{" "}
                {COMPLETE_GUIDE_MODELS.gptProSurface}, {COMPLETE_GUIDE_MODELS.openaiPlanner} in
                Codex, and {COMPLETE_GUIDE_MODELS.antigravity} in Antigravity. The plans come out quite
                different, because each model has its own &quot;tastes&quot; and blind spots.
                Running a plan past several different models is the cheapest way to catch
                architectural mistakes.
              </P>

              <P>
                The other planners are useful because they were trained differently, on different
                pre-training data with different post-training. Three strong models trained that
                differently give you a much richer dialogue than one, and four is better still. So
                count perspectives by lab, not by product. {COMPLETE_GUIDE_MODELS.gptPro} and{" "}
                {COMPLETE_GUIDE_MODELS.openaiPlanner} are both OpenAI models and together give you
                one of the three. {COMPLETE_GUIDE_MODELS.claudeExecutor} adds little to a{" "}
                {COMPLETE_GUIDE_MODELS.leadPlanner} plan, because it comes from the same lab with
                close to the same data and training, and shares the lead&apos;s blind spots. A
                cheaper model from another lab is still worth asking for ideas, since the smarter
                models reject the bad ones anyway, but it helps much less as one of the three when
                the other two beat it at everything.
              </P>

              <P>
                The graph database plan began as two drafts written in parallel in the Claude and
                ChatGPT apps, one by Fable and one by GPT Pro, before the project existed on a
                computer. The merged plan kept Fable&apos;s draft as its backbone and grafted in
                ideas found only in the GPT Pro draft, and both drafts are kept in the repo&apos;s
                planning folder. For a long time I used GPT Pro as the final arbiter of competing
                plans; since July 2026 I&apos;ve had Fable do the merging instead.
              </P>

              <P>
                In the CASS Memory System project, the{" "}
                <a
                  href="https://github.com/Dicklesworthstone/cass_memory_system/tree/main/competing_proposal_plans"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  competing plans are publicly visible
                </a>
                . I&apos;ve used this pattern in at least 10 sessions across 7+ projects.
              </P>

              <P>
                Give every model the identical kickoff and let each one plan blind. On a recent
                robotics project, I pasted the same kickoff into Claude Code and Codex a minute
                apart, and a third edition came from Gemini in Antigravity. None of the
                three read the others while drafting, each was built around a different central
                idea, and each planner ran its own multi-model research round on its edition
                before the blend.
              </P>

              <P>
                Keep later review rounds isolated from earlier ones in the same way. The second
                research round in that project was told not to read anything the first round had
                produced or either competing edition, and its claim audit was done by auditors
                who had written none of the claims. A round that can see the previous
                round&apos;s conclusions tends to confirm them.
              </P>

              <P>
                Then give the competing plans to the lead with this prompt:
              </P>

              <PromptBlock
                title="Best-of-All-Worlds Synthesis"
                prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan):`}
                where={`The lead planner (${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface}), which wrote one of the plans`}
                whyItWorks="Makes the model admit what the competing plans did better, then merge the best of them into one plan. The 'best of all worlds' phrasing appears in 10+ distinct sessions across 7+ projects in my session archive. The prompt's length and specificity are deliberate: asking for git-diff style changes, integration of every good idea, and edits to the existing plan keeps the model from writing a vague summary and makes it work through what the competing plans actually say."
              />

              <P>
                The request to be &quot;intellectually honest about what they did that&apos;s
                better than your plan&quot; matters most when the model doing the blend wrote one
                of the editions, since it otherwise defends its own. In the robotics project the
                lead, running Fable 5.2 in Claude Code, blended its edition with the other two and
                both research rounds, and the plan grew from about 3,700 lines to about 37,000.
                Three completeness audits then checked the blend against each source and supplied
                passages it had dropped.
              </P>

              <P>
                A competing model can also work on the lead&apos;s plan directly. On the mining
                project, I gave Gemini in Antigravity the lead&apos;s kickoff plus &quot;I
                want you to think through all of this too and propose improvements to the plan to
                make it smarter and better,&quot; and it edited the plan in place overnight. The
                lead then checked every new FACT against the source documents, re-ran the new math,
                and found seven kinds of error, from wrong drill intervals to processing rules that
                appeared in no source document. Take another model&apos;s ideas freely, but take
                its facts only after the lead has checked them.
              </P>

              <P>
                When a plan, review, or synthesis comes from outside the repo, such as a{" "}
                {COMPLETE_GUIDE_MODELS.gptPro} conversation in{" "}
                {COMPLETE_GUIDE_MODELS.gptProSurface}, paste its git-diff style output into the
                lead session to integrate it:
              </P>

              <PromptBlock
                title="Integrate Synthesis Revisions"
                prompt={`OK, now integrate these revisions to the markdown plan in-place; use ultrathink and be meticulous. At the end, you can tell me which changes you wholeheartedly agree with, which you somewhat agree with, and which you disagree with:

[Pasted synthesis output]`}
                where={`The lead session (${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface})`}
                whyItWorks="Claude assesses each suggestion critically, which adds a second quality filter. The 'wholeheartedly agree / somewhat agree / disagree' framing makes the agent grade each revision on its own instead of accepting or rejecting the whole batch. You learn which changes are clearly good and which are plausible but debatable, so you can step in on the debatable ones and leave the rest."
              />

              <PlanEvolutionStudio />
              <IllustrativeDisclosure />

              <SkillNote skills={["multi-model-triangulation", "modes-of-reasoning-project-analysis"]}>
                Two ways to get several perspectives on a single hard decision rather than a whole
                plan. <code>/multi-model-triangulation</code> has Claude write a copy-paste-ready
                prompt for Codex, Gemini, or Grok; you relay the answers back, and Claude
                synthesizes them into one recommendation. Agreement across models that think
                differently is stronger evidence than any one model&apos;s confidence.{" "}
                <code>/modes-of-reasoning-project-analysis</code> varies the reasoning instead of
                the model. It applies several distinct modes of reasoning to the central questions,
                then audits every material claim independently before the synthesis, so
                a clever but false objection doesn&apos;t survive into the decision.
              </SkillNote>
            </SubSection>

            <SubSection title="Iterative Refinement">
              <P>
                Now run review rounds. I use {COMPLETE_GUIDE_MODELS.gptPro} for these: paste the
                current plan into a <strong>fresh</strong> {COMPLETE_GUIDE_MODELS.gptPro}{" "}
                conversation with this prompt, then paste its revisions into the lead with the
                integration prompt above. A fresh conversation keeps the model from anchoring on
                its own earlier output.
              </P>

              <PromptBlock
                title="Plan Refinement Prompt"
                prompt={`Carefully review this entire plan for me and come up with your best revisions in terms of better architecture, new features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc.

For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style changes relative to the original markdown plan shown below:

<PASTE YOUR EXISTING COMPLETE PLAN HERE>`}
                where={`${COMPLETE_GUIDE_MODELS.gptPro} in ${COMPLETE_GUIDE_MODELS.gptProSurface} (fresh conversation each round)`}
                whyItWorks="Each round finds architectural issues, missing features, and robustness problems that the previous round missed. Asking for 'rationale/justification' keeps the model from making arbitrary changes: it has to argue for each revision, which filters out changes that seem clever but do not improve the plan. The git-diff format makes it say exactly what should change, and the lead's agree/disagree grading when it integrates the round is the second filter."
              />

              <P>
                Once the lead has integrated a round, start a fresh{" "}
                {COMPLETE_GUIDE_MODELS.gptPro} conversation and do it again. Expect big changes in
                the early rounds. A simple plan mostly converges after about five; I usually do at
                least 8 to 10, and the more complex the plan or specification, the more it takes (a
                frontier math research skill took 26 rounds, a record for me).{" "}
                {COMPLETE_GUIDE_MODELS.gptPro} in the app has its own usage limits, separate from
                Codex, so the rounds don&apos;t eat into your Codex quota. If the page shows an
                error mid-answer, don&apos;t stop the
                response or try to steer it: close the tab and reopen it later, and it will usually
                still be running. To automate the rounds,{" "}
                <code>apr</code> (Automated Plan Reviser Pro, installed by ACFS) bundles your README
                and plan, runs each round in ChatGPT in the background, and writes the integration
                prompt for the lead (<code>apr run N</code>, then{" "}
                <code>apr integrate N --copy</code>).
              </P>

              <P>
                Between those rounds, and whenever you are working without ChatGPT, have reviewers
                inside the harness audit the plan: fresh-context subagents the lead commissions, or
                a Codex or Antigravity session started for the purpose. A reviewer that wrote none
                of the plan has nothing to defend, and one that has not seen the previous
                round&apos;s conclusions does not simply confirm them. My audit prompt has the
                reviewer learn the project&apos;s rules and finished-state description first, then
                hunt for mistakes:
              </P>

              <PromptBlock
                title="Plan Audit"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then I want you to super carefully, deeply, and profoundly read, analyze, and understand COMPREHENSIVE_PLAN_FOR_THE_DESIGN_OF_<PROJECT>.md and check over everything with fresh eyes looking for any blunders, mistakes, errors, oversights, omissions, problems, misconceptions, bugs, etc. Be SUPER thorough and meticulous!`}
                where={`A reviewer that did not write the plan: ${COMPLETE_GUIDE_MODELS.openaiPlanner} or ${COMPLETE_GUIDE_MODELS.codexExecutor} in Codex, an Antigravity pane, or a fresh subagent of the lead`}
                whyItWorks="AGENTS.md and the present-tense README tell the reviewer what the project is supposed to be, so it judges the plan against that rather than against its own taste. The list of failure kinds (blunders, oversights, omissions, misconceptions) widens the search beyond bugs. On the graph database plan, a Codex reviewer ran this for more than five hours, sending its own subagents on adversarial passes, and came back with 15 blocking architectural contradictions."
              />

              <PromptBlock
                title="Revise After the Audit"
                prompt={`OK, so I want you to revise the COMPREHENSIVE_PLAN_FOR_THE_DESIGN_OF_<PROJECT>.md document to solve absolutely ALL of the problems/issues you identified in the optimal way possible, which I leave to your superior judgment and instinct to determine.`}
                where="The same reviewer session, right after its audit"
                whyItWorks="The reviewer that found the problems understands them best, so it fixes them itself and nothing has to be pasted between tools. 'Absolutely ALL' keeps it from fixing the easy problems and listing the rest, and leaving the method to its judgment keeps it from handing the choices back to you. Then have the lead check the changes, as with any other model's edit."
              />

              <P>
                Keep each review as a file in the repo, so a different model can weigh it. When a
                third model reviewed the graph database plan, the lead adjudicated that review with
                twelve parallel deep-read subagents and seven adversarial verifiers before
                anything from it reached the plan.
              </P>

              <P>
                Vary the kind of review from round to round, not just the reviewer. The mining
                plan&apos;s rounds were primary-source audits by three reviewers who had not written
                it, a pass through the source documents, a web check of the industry figures, and a
                final round combining a modes-of-reasoning analysis, hypothesis testing by a squad
                of three model families, and an idea duel. On the graph database plan, one review
                covered correctness, an enhancement pass covered statistics and distribution, and a
                third covered cost and the product lifecycle.
              </P>

              <P>
                One review I use on plans, skills, and code alike asks the model whether it
                disagrees with anything, and how sure it is:
              </P>

              <PromptBlock
                title="Do You Disagree?"
                prompt={`I want you to meticulously and comprehensively study <whatever you want: code, a document, a skill, a diagram, etc>; do you see anything you disagree with? Anything that is obviously contradictory? Foolishly inconsistent? Misguided and unlikely to work in practice?

Ask yourself WHY you feel that way and meditate and ruminate on all of it deeply and profoundly. Finally, explain your thought process and conclusions and your justifications/rationale for them, as well as your confidence in those (and also how you know you're confident, and how confident you REALLY are!).

Important: don't disagree just to be disagreeable, it's OK to just agree if you think it's right!`}
                where="Any model that didn't write the thing under review, on a plan, a skill, a design document, or code"
                whyItWorks="Most review prompts ask for problems. This one asks whether the model disagrees and why, makes it state and then question its own confidence, and explicitly allows it to agree, so you also learn how much weight each objection deserves."
              />

              <P>
                Don&apos;t wait for a round that finds nothing, because reviewers always find
                something. Stop when the changes devolve into pointless minutiae, or when the plan
                starts looking too much like code, with detailed schemas and the like. In the mining
                plan&apos;s last round, eight auditors who had written none of the claims checked
                171 of them: 102 were verified, 59 partly supported and 2 rejected, and no conflict
                survived. After that the plan changed only in small edits.
              </P>

              <P>
                When you can&apos;t tell whether the reviewers are still finding real problems,
                take the last few rounds of material issues from each model, start a new{" "}
                {COMPLETE_GUIDE_MODELS.leadPlanner} session, and ask it for a candid analysis of
                whether the models are going in circles or fixating on minor nonsense.
              </P>

              <P>
                Once a plan has taken shape, I follow up with a prompt that has done wonders for my
                recent plans. It asks the model to design the system for the agents who will run
                it:
              </P>

              <PromptBlock
                title="Agent-Ergonomics Pass"
                prompt={`OK, now I want you to think deeply about how to make this entire system as agent-intuitive, agent-ergonomic, and agent-accretive as you can possibly imagine. Put yourself in the driver's seat and imagine that YOU are the one using this system and driving it. What would most enable you to do an awesome job understanding the situation accurately and optimally controlling everything to drive the best and most accurate results possible, with the least expenditure of resources?

Then make all the requisite changes to the various design documents and plans accordingly. Don't just think of the project as an assemblage of various parts or components: really try to profoundly and deeply conceptualize it as a synthetic SYSTEM that is maximally coherent, cohesive, modular, and interconnected, forming a tower of linked abstractions that are maximally legible to you as an agent. Really ruminate and meditate on all of this incredibly deeply before responding or taking any actions.`}
                where={`The session that wrote the plan (the lead, or ${COMPLETE_GUIDE_MODELS.gptPro}), at its highest effort setting, before the plan becomes beads`}
                whyItWorks="Agents will build, test, and often drive what you're designing, so a system they can read and control well is easier to get right, and the changes generally make the design better overall. Asking the model to imagine itself as the operator turns that into concrete design changes. Use it in planning: on an existing codebase it can make sweeping changes, so adapt it with care."
              />

              <SkillNote skills={["planning-workflow"]}>
                Packages the plan-review loop as one skill: the exact prompts for a GPT Pro review
                round, for integrating its revisions in your coding agent, and for blending
                competing plans, plus a check between rounds that grounds every load-bearing claim
                in a verifiable source. It hands the finished plan on to bead conversion and
                polishing, whose prompts live in <code>/beads-workflow</code>.
              </SkillNote>

              <P>
                Every review, whichever model wrote it, ends with the lead, which either integrates
                the findings or checks the reviewer&apos;s own edits, so one model keeps the whole
                plan consistent. This is a workflow recommendation, not a claim that one model is
                universally best.
              </P>

              <TipBox>
                <strong>The &quot;Lie to Them&quot; technique:</strong> Models tend to stop looking
                for problems after finding ~20-25 issues. If you tell them to find &quot;all&quot;
                problems, they stop early. So lie to them: give them a huge number, and they keep
                cranking until they have uncovered all of them. This works for
                plan revisions, bead-to-plan cross-references, and any comparison/audit task.
              </TipBox>

              <PromptBlock
                title="Overshoot Mismatch Hunt"
                prompt={`Do this again, and actually be super super careful: can you please check over the plan again and compare it to all that feedback I gave you? I am positive that you missed or screwed up at least 80 elements of that complex feedback.`}
                where="After any review pass that feels too short or self-satisfied"
                whyItWorks="Told that 80+ errors exist, the model keeps searching instead of settling for a partial list."
              />

              <P>
                Plans built this way get long. Earlier ones ran 3,000 to 6,000 lines: for the CASS
                GitHub Pages export feature, the plan went through multiple rounds over about 3
                hours, growing to approximately{" "}
                <a
                  href="https://github.com/Dicklesworthstone/coding_agent_session_search/blob/main/docs/planning/PLAN_TO_CREATE_GH_PAGES_WEB_EXPORT_APP.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  3,500 lines
                </a>
                . You can also see a{" "}
                <a
                  href="https://github.com/Dicklesworthstone/jeffreysprompts.com/blob/main/PLAN_TO_MAKE_JEFFREYSPROMPTS_WEBAPP_AND_CLI_TOOL.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  6,000-line plan
                </a>
                . My recent plans are larger, and lines stop being a useful measure once tables and
                appendices make each line very long. The accounting engine&apos;s
                first draft was 237 KB; the mining plan is about 9,500 lines (830 KB), backed by
                about 36,000 lines of research, audit, and hypothesis records in its planning
                folder; and the{" "}
                <a
                  href="https://github.com/Dicklesworthstone/frankengraphdb/blob/main/COMPREHENSIVE_PLAN_FOR_THE_DESIGN_OF_FRANKENGRAPHDB.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  graph database plan
                </a>{" "}
                is 1.7 MB of markdown in about 3,300 lines.
              </P>

              <P>
                It feels slow because no code is being written. But if you do it correctly and then
                start enough agents in your swarm with Agent Mail, beads, and bv, the code gets
                written fast enough to more than make up for the slow start, and it is good code.
              </P>

              <P>
                <strong>When to stop refining and start converting to beads:</strong> Stay in plan
                refinement if whole-workflow questions are still moving around, major architecture
                debates are still open, or fresh models keep finding substantial missing features,
                constraints, or tradeoffs. Switch to beads when the plan mostly feels stable and the
                remaining improvements are about execution structure, testing obligations,
                sequencing, and embedded context rather than about what the system is.
              </P>
            </SubSection>

            <SubSection title="Declare the Stage in AGENTS.md">
              <P>
                Agents follow AGENTS.md, so say there which stage the project is in: planning
                only, or implementation. While the robotics plans were still competing, I sent one
                planner my usual gap-closing follow-up (&quot;Close the Biggest Gaps&quot; in Adding
                Features to Existing Projects, after Part 5), which tells the agent to execute any
                remaining beads. It started building, and my next message was
                &quot;wait what are you doing? I didn&apos;t say to start BUILDING this yet, we are
                in the PLANNING STAGES ONLY!!!&quot; The prototype went into an ignored directory,
                its three beads were withdrawn, and AGENTS.md was set to planning only.
              </P>

              <P>
                Change the stage line when you move to implementation, and commit the beads in the
                same step. Two days later, the lead&apos;s own pre-implementation checklist noted that
                AGENTS.md still said planning, only one bead was ready, and none of the beads were
                committed. I replied &quot;DO THIS STUFF FIRST!!!&quot;, and the 3,637
                polished beads and the stage change were committed seven minutes later.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 4: PLANS BECOME BEADS                                  */}
          {/* ============================================================= */}
          <GuideSection id="beads">
            <TipBox variant="warning">
              <strong>Watch for the plan-bead gap.</strong> In the destructive_command_guard
              sessions, agents occasionally got stuck between plan revision and bead creation: the
              competing plan was revised but no beads were ever created. Make sure the synthesis
              step ends with an explicit move to bead creation.
            </TipBox>

            <P>
              Then you&apos;re ready to turn the plan into beads. Think of these as epics, tasks,
              and subtasks with an associated dependency structure. The name comes from{" "}
              <a
                href="https://github.com/AstroBeads/beads"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                Steve Yegge&apos;s Beads project
              </a>
              , which is like Jira or Linear, but optimized for use by coding agents. They are
              stored locally in <code>.beads/</code> JSONL files that commit with your code.
            </P>

            <P highlight>
              Writing the markdown plan and creating the beads are two separate steps of planning.
              Always have a very detailed markdown plan first, then treat turning that plan into
              beads as its own problem, with its own challenges. Once you are in &quot;bead
              space&quot; you never look back at the markdown plan, which is why every detail has
              to make it into the beads.
            </P>

            <PromptBlock
              title="Plan to Beads Conversion"
              prompt={`OK so please take ALL of that and elaborate on it more and then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.) Use only the \`br\` tool to create and modify the beads and add the dependencies. Use ultrathink.`}
              where={`The lead (${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface}), in the session that holds the plan`}
              whyItWorks="The prompt makes the agent translate the whole plan into beads instead of extracting a task list. Requiring the beads to be totally self-contained and self-documenting pushes rationale, test expectations, design intent, and sequencing into the bead graph itself. Asking for tasks, subtasks, dependency structure, detailed comments, and future-self context keeps the model from collapsing a rich plan into terse todo items. Restricting it to the br tool keeps the agent from writing pseudo-beads in markdown instead of editing the actual task graph."
            />

            <P>
              For existing projects with a specific plan file, prefix it: &quot;OK so now read ALL
              of PLAN_FILE_NAME.md; please take ALL of that and elaborate on it...&quot; The rest of
              the prompt stays the same.
            </P>

            <P>
              Since August 2026 I&apos;ve sometimes had two models create the beads together. The
              lead writes them while {COMPLETE_GUIDE_MODELS.openaiPlanner} in Codex reviews in real
              time, and the two exchange Agent Mail the whole way through, sometimes using comments
              on beads as a second channel. I ask them to agree with each other, and they tend to
              defer to the better version or form a hybrid of the two. It works better than either
              model alone, and the same pairing works for writing the markdown plan.
            </P>

            <P>
              Bead creation is also the best time to stop process porn: beads whose only output is
              acceptance certificates, sign-off gates, and status reports rather than features. The swarm
              will pick that work up eagerly, because closing it feels like progress. Cut those
              beads now, think through how a swarm could game this particular project, and forbid
              those moves by name in AGENTS.md. You still have to watch for it during execution.
            </P>

            <TipBox variant="warning">
              Never write pseudo-beads in markdown documents. Go directly from the markdown plan to
              real beads using the <code>br</code> tool, and from that point on add and change
              only the beads. If the model starts describing beads in text form instead of
              creating them, stop it and redirect to <code>br create</code>.
            </TipBox>

            <PlanToBeadsViz />
            <IllustrativeDisclosure />

            <SkillNote skills={["beads-workflow", "beads-br", "beads-bv"]}>
              The three skills to have loaded for this part and the next.{" "}
              <code>/beads-workflow</code> carries the conversion prompt above, the polishing loop
              you run until the beads stop changing, the sync-then-commit routine, and the
              convention that a bead&apos;s ID is also its Agent Mail thread ID.{" "}
              <code>/beads-br</code> covers the br lifecycle and its rules (br never runs git
              itself, and dependency cycles must be cleared before a session ends).{" "}
              <code>/beads-bv</code> teaches the graph triage: PageRank to find the bead everything
              depends on, betweenness to find the bottleneck, and the reminder that bare{" "}
              <code>bv</code> opens an interactive TUI an agent cannot drive.
            </SkillNote>

            <SubSection title="Beads as Executable Memory">
              <P>
                The plan is still the best artifact for whole-system thought. Once a swarm is
                involved, though, you need a task graph that carries enough local context for agents
                to act correctly without repeatedly loading the whole project back into memory. With
                weak beads the swarm improvises; with rich beads its work becomes almost mechanical.
              </P>

              <BlockQuote>
                It works better if most of the decision making is made ahead of time during the
                planning phases and then is embedded in the beads.
              </BlockQuote>

              <BulletList
                items={[
                  <Fragment key="self-contained">
                    Beads are <strong>self-contained</strong>: detailed enough that you never need
                    to refer back to the original markdown plan, with every piece of context,
                    reasoning, and intent embedded.
                  </Fragment>,
                  <Fragment key="rich-content">
                    Beads can and should hold <strong>long descriptions</strong>, often with
                    embedded markdown, instead of short bullet-point entries. JSONL is only how they
                    are serialized.
                  </Fragment>,
                  <Fragment key="complete-coverage">
                    <strong>Everything</strong> in the markdown plan must make it into the beads.
                  </Fragment>,
                  <Fragment key="explicit-dependencies">
                    The <strong>dependency graph</strong> must be correct, because bv computes the
                    execution order from it.
                  </Fragment>,
                  <Fragment key="include-testing">
                    Beads should include <strong>comprehensive unit tests and e2e test
                    scripts</strong> with great, detailed logging.
                  </Fragment>,
                ]}
              />

              <TipBox variant="info">
                The beads are written for the agents more than for you. When you need to read them,
                have an agent turn them back into markdown.
              </TipBox>
            </SubSection>

            <SubSection title="What Good Beads Look Like">
              <P>
                To make this concrete, imagine a small internal web app called &quot;Atlas
                Notes&quot; for uploading and searching team notes. Instead of one vague task like
                &quot;build Atlas Notes,&quot; the plan becomes many self-contained beads:
              </P>

              <BulletList
                items={[
                  <Fragment key="br-101">
                    <strong>br-101 Upload and Parse Pipeline:</strong> Describes accepted file
                    formats, frontmatter parsing expectations, where failures are logged, what
                    happens on malformed input, and which unit and e2e tests prove the pipeline
                    works.
                  </Fragment>,
                  <Fragment key="br-102">
                    <strong>br-102 Search Index and Query UX:</strong> Carries the search behavior,
                    indexing rules, latency expectations, filter semantics, empty-state UX, and test
                    coverage for keyword/tag/date combinations.
                  </Fragment>,
                  <Fragment key="br-103">
                    <strong>br-103 Ingestion Failure Dashboard:</strong> Includes the admin
                    workflow, permission boundaries, retry logic, logging expectations, and the
                    specific reasons the dashboard is needed.
                  </Fragment>,
                ]}
              />

              <P>
                What matters is that each bead is rich enough that a fresh agent can open it and immediately understand what correct
                implementation looks like, why it matters, and how to verify it.
              </P>

              <P>
                For the CASS Memory System (5,500-line plan), the conversion produced 347 beads with
                complete dependency structure. FrankenSQLite had hundreds of beads created via
                parallel subagents. For complex projects, expect 200-500 initial beads.
              </P>

              <BlockQuote>
                Once you convert the plan docs into beads, you&apos;re supposed to not really need
                to refer back to the docs if you did a good job. The docs are still useful though,
                for people and for agents in various contexts, but you don&apos;t need to swamp all
                the agents with the full plan once you&apos;ve turned it into beads.
              </BlockQuote>
            </SubSection>

            <SubSection title="When the Plan Already Has a Backlog">
              <P>
                Some plans end in a backlog of their own. The plan for a recent simulation project
                closed with 58 numbered work items in tables with &quot;Depends on&quot; and
                &quot;Completion evidence&quot; columns, and said they were meant to become beads
                once the repository existed. A subagent converted them in about five minutes: one
                bead per row, the completion evidence copied verbatim as acceptance criteria, the
                plan&apos;s item ID as the external reference, and all 141 edges from the table
                with none invented. It then checked that the graph was acyclic, that the edge count
                matched the plan, and that only the first item was ready, as the plan intended. No
                polishing round followed; implementation began the next day.
              </P>

              <P>
                Here the plan stays the spec. Each bead names the plan sections it implements, and
                progress goes into bead comments instead of new beads: one item stayed open for 17
                days and collected 20 comments of partial landings, measurements and corrections.
                New beads appeared only for gaps no row covered, bugs found in review, performance
                ideas, and a feature family planned later. A seven-week accounting engine started
                the same way, with its first implementation beads written as short pointers into a
                plan whose contract appendices were marked normative. Every bead sends the agent
                back to the plan, so this only suits a plan precise enough to act as the spec.
              </P>
            </SubSection>

            <SubSection title="Fanning Out a Very Large Conversion">
              <P>
                One agent calling <code>br</code> cannot convert a 37,000-line plan. For the
                robotics project, the lead wrote a charter that fixed the bead format (seven
                sections, with a test plan covering unit tests, an end-to-end script with logging,
                and known answers with negative controls), split the plan into 80 drafting units,
                and wrote a brief for each. About 117 drafter subagents then wrote one markdown
                staging file per bead without running <code>br</code>. Before the real load, dry
                runs into scratch trackers let bv check the graph, and integrator and reconciler
                subagents settled conflicts between units. A script loaded the files using only{" "}
                <code>br</code>. The result was about 3,600 beads, with a median of 167 lines each.
              </P>

              <P>
                Those staging files resemble the markdown pseudo-beads warned against above. The
                differences are that the format was fixed, every change reached the tracker through
                the same loader, and once the swarm started no agent was allowed to touch them. The
                simulation project scripted a later 18-bead epic the same way. On the accounting
                engine, four fresh drafting agents converted a second plan while reading all of it
                and the code, and the plan defects they reported were fixed in the plan itself.
              </P>
            </SubSection>

            <SubSection title="Beads CLI Quick Reference">
              <CodeBlock
                language="bash"
                code={`br create --title "..." --priority 2 --labels backend   # Create issue
br list --status open --json                             # List open issues
br ready --json                                          # Show unblocked tasks
br show <id>                                             # View issue details
br update <id> --claim                                   # Atomic claim (assignee + in_progress)
br close <id> --reason "Completed"                       # Close task
br dep add <id> <other-id>                               # Add dependency
br comments add <id> "Found root cause..."               # Add comment
br sync --flush-only                                     # Export to JSONL (no git ops)`}
              />
              <P>
                Priority uses numbers: P0=critical, P1=high, P2=medium, P3=low, P4=backlog. Types:
                task, bug, feature, epic, question, docs. <code>br ready</code> shows only unblocked
                work. Storage is a SQLite + JSONL hybrid; the JSONL files commit with your code.
              </P>

              <SkillNote skills={["fixing-beads-problems"]}>
                For the day <code>br show</code> or <code>br doctor</code> fails because the
                database is malformed and the JSONL has drifted, with each store holding changes the
                other lacks.
                The skill snapshots everything, carries the database-only changes worth keeping
                into the JSONL,
                rebuilds into a separate database, and swaps it in only after <code>br show</code>,{" "}
                <code>br sync --status</code>, and <code>br doctor</code> all pass. Nothing under{" "}
                <code>.beads</code> is deleted.
              </SkillNote>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 5: POLISHING BEADS                                     */}
          {/* ============================================================= */}
          <GuideSection id="polishing">
            <P>
              Before you burn up a lot of tokens with a big agent swarm on a new project, the old
              woodworking maxim of &quot;Measure twice, cut once!&quot; is worth revising as{" "}
              <strong>&quot;Check your beads N times, implement once,&quot;</strong> where N is as
              many as you can stomach. This is the step most people underinvest in.
            </P>

            <P>
              After the initial conversion finishes, do a round of this prompt. If Claude Code did a
              compaction at any point, be sure to tell it to re-read your AGENTS.md file first:
            </P>

            <PromptBlock
              title="Bead Polishing Prompt"
              prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the \`br\` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.`}
              where={`The lead (${COMPLETE_GUIDE_MODELS.leadPlanner} in ${COMPLETE_GUIDE_MODELS.leadPlannerSurface}), run at least 8-10 times on a typical project; on a large graph it hands each round's slices to ${COMPLETE_GUIDE_MODELS.claudeExecutor} subagents`}
              whyItWorks="This prompt keeps beads from being frozen too early: the model stays in plan space while it is still finding real improvements, and plan space is where reasoning is cheapest and most global. The warnings against oversimplifying and losing functionality matter because models otherwise tend to 'improve' artifacts by deleting complexity they do not fully understand. The prompt also writes tests into the bead definitions themselves, so test work cannot be left for later."
            />

            <ConvergenceViz />
            <IllustrativeDisclosure />

            <P>
              From real sessions, polishing involves duplicate detection and merging, quality
              scoring on WHAT/WHY/HOW criteria, filling empty bead descriptions, correcting
              dependency links, and cross-referencing beads against the markdown plan to check that
              nothing was lost. In FrankenSQLite, agents found 9 exact duplicate pairs and closed
              them, choosing survivors based on &quot;richer testing specs, better dependency chains, and
              higher priority.&quot;
            </P>

            <P>
              Tell agents to go through each bead and explicitly check it against the markdown plan.
              Or vice versa: go through the markdown plan and cross-reference every single thing
              against the beads (both closed and open) to confirm complete coverage.
            </P>

            <SubSection title="Convergence Detection: When to Stop">
              <P>Bead polishing converges in phases, much like a numerical optimization:</P>

              <DataTable
                headers={["Phase", "Rounds", "Character"]}
                rows={[
                  ["Major Fixes", "1-3", "Wild swings, fundamental changes"],
                  ["Architecture", "4-7", "Interface improvements, boundary refinements"],
                  ["Refinement", "8-12", "Edge cases, nuanced handling"],
                  ["Polishing", "13+", "Converging to steady state"],
                ]}
              />

              <P>
                Three signals indicate convergence: agent responses get shorter, each round changes
                less than the one before, and successive rounds look more and more alike. When the
                weighted convergence score reaches 0.75+, you&apos;re ready to finalize. Above 0.90,
                you&apos;re hitting diminishing returns.
              </P>

              <TipBox variant="warning">
                <strong>Early termination red flags:</strong> If you see{" "}
                <strong>oscillation</strong> (alternating between two versions), reframe the
                problem. If you see <strong>expansion</strong> (output growing instead of
                shrinking), step back; the agent is adding complexity. If you see a{" "}
                <strong>plateau at low quality</strong>, kill the current approach and restart
                fresh.
              </TipBox>

              <P>
                On a typical project I polish the beads for at least 8 to 10 rounds. As with the
                plan, stop when the changes devolve into minutiae, not when they stop altogether. A
                very large bead set gets fewer, much bigger rounds.
              </P>

              <P>
                On a very large bead set, read the second signal from the size and kind of the
                edits instead of the number of beads a round touches. The robotics project ran four
                polishing rounds over about 3,600 beads, and every round changed roughly four in
                five of them:
              </P>

              <DataTable
                headers={["Round", "Reviewed", "Changed", "New", "Leading kinds of finding"]}
                rows={[
                  ["1", "3,543", "2,909", "52", "Correctness, tests, dependencies"],
                  ["2", "3,614", "2,772", "28", "Correctness, e2e logging, tests"],
                  ["3", "2,961", "2,363", "14", "Correctness, e2e logging"],
                  ["4", "3,716", "2,850", "23", "Conventions, registries, contradictions between beads"],
                ]}
              />

              <P>
                Meanwhile the median change fell to about 12 lines of a bead around 160 lines long
                by the third round, and the fourth round&apos;s findings were mostly about
                consistency between beads. The notes still unapplied at the end (955 of them, on
                646 beads) went onto their beads as comments under a{" "}
                <code>review-notes-open</code> label instead of into a fifth round.
              </P>

              <P>The stop is your call. Partway through the fourth round, I wrote:</P>

              <BlockQuote>
                ok I think we&apos;ve done enough beads polishing at this point, let&apos;s please
                wrap it up and finalize the beads so we can begin implementation work!
              </BlockQuote>

              <P>
                Half an hour later, my own request for one more fresh-eyes pass restarted it, and
                the next afternoon I interrupted again: &quot;please make sure you aren&apos;t
                getting carried away again with the beads to the point of sharply diminishing
                marginal returns.&quot;
              </P>
            </SubSection>

            <SubSection title="Fresh Eyes Technique">
              <P>If improvements start to flatline, start a brand new Claude Code session:</P>

              <PromptBlock
                title="Fresh Eyes on Beads"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Use ultrathink.`}
                where="A brand new Claude Code session"
                whyItWorks="A fresh session does not carry the accumulated assumptions of the previous one, so it reads the beads with new eyes."
              />

              <P>Then follow up with:</P>

              <PromptBlock
                title="Fresh Review of Beads"
                prompt={`We recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using \`br\` and \`bv\`. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! Use ultrathink.`}
                where="Same fresh session, after it finishes reading"
              />

              <P>
                As a final step, have Codex ({COMPLETE_GUIDE_MODELS.codexExecutor} at xhigh
                reasoning effort, the ACFS <code>cod</code> default) do one last round using the same polishing prompt.
                Different models catch different things.
              </P>
            </SubSection>

            <SubSection title="Deduplication Check">
              <P>After large bead creation batches, run a dedicated dedup pass:</P>

              <PromptBlock
                title="Bead Deduplication"
                prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over ALL open beads. Make sure none of them are duplicative or excessively overlapping... try to intelligently and cleverly merge them into single canonical beads that best exemplify the strengths of each.`}
                where="Claude Code, after large bead creation batches"
              />
            </SubSection>

            <SubSection title="Settle Recurring Drift Once">
              <P>
                When reviewers keep correcting the same convention across many beads, settle it
                once in a numbered conventions file, name the bead that owns each entry, and have
                every later round check against the file. Otherwise each reviewer fixes the drift a
                different way. The robotics project&apos;s file held 18 conventions by the end of
                polishing. The accounting engine did the same for open design questions: its first
                plan review decided ten of them and wrote the answers into the plan &quot;so no
                workstream reopens them locally.&quot;
              </P>
            </SubSection>

            <SubSection title="Audit the Dependency Graph Before Swarming">
              <P>
                Review rounds tend to over-chain the dependency graph. Polishing left the robotics
                bead set with a single ready bead and a longest dependency chain of 169, which
                gives a swarm almost nothing to start on. Seven auditor subagents then classified
                every edge as real, false, partial, or pointing the wrong way, and removed edges
                conservatively. The longest chain fell to 144, and four beads were ready at launch
                instead of one.
              </P>

              <P>
                Before launching, count what <code>br ready</code> returns, find the longest chain,
                and run <code>br dep cycles</code>. The simulation project&apos;s conversion checked
                that only the plan&apos;s first item was ready, and the accounting engine&apos;s
                plan reviews recorded an empty cycle report and clean bv robot runs.
              </P>

              <P>
                Then ask whether the same work could be wired for more parallelism:
              </P>

              <PromptBlock
                title="Rewire for Concurrency"
                prompt={`Is there a better way to wire the beads dependencies using /beads-bv to implement the same work, but with greater opportunity for agent concurrency so as to enable faster overall development velocity using a larger swarm size?`}
                where="Any strong agent, once the plan is fully converted to beads and polished"
                whyItWorks="A wider graph lets you provision a larger swarm with ntm. The extra agents then have whole beads to work on, instead of trying to be useful by taking smaller slices of beads or inventing ceremony to look busy. Recheck the rewired graph the same way: count the ready beads, find the longest chain, and run br dep cycles."
              />
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 5b: IDEA-WIZARD & AD-HOC CHANGES                       */}
          {/* ============================================================= */}
          <GuideSection id="idea-wizard">
            <P>
              The full planning pipeline (Phases 1-5) is for new projects built from scratch. For
              existing projects that need new features, the <strong>Idea-Wizard</strong> is a
              formalized 6-phase pipeline:
            </P>

            <NumberedList
              items={[
                <Fragment key="ground-in-reality">
                  <strong>Ground in reality.</strong> Read AGENTS.md and list all existing beads (
                  <code>br list --json</code>). This prevents creating duplicates.
                </Fragment>,
                <Fragment key="generate-30-winnow-5">
                  <strong>Generate 30, winnow to 5.</strong> The agent brainstorms 30 ideas for
                  improvements, then self-selects the best 5 with justification.
                </Fragment>,
                <Fragment key="expand-to-15">
                  <strong>Expand to 15.</strong> Prompt: &quot;ok and your next best 10 and
                  why.&quot; The agent produces ideas 6-15, checking each against existing beads for
                  novelty.
                </Fragment>,
                <Fragment key="human-review">
                  <strong>Check overlaps and select.</strong> Compare the 15 ideas against open
                  beads (<code>br list --json</code>), merge rather than duplicate, then you choose
                  which to pursue.
                </Fragment>,
                <Fragment key="turn-into-beads">
                  <strong>Turn into beads.</strong> Selected ideas become beads with full
                  descriptions, dependencies, and priority levels.
                </Fragment>,
                <Fragment key="refine-4-5-times">
                  <strong>Refine 4-5 times.</strong> The same polishing loop as above, with fewer
                  rounds because there are only a handful of new beads. Single-pass beads are never
                  optimal.
                </Fragment>,
              ]}
            />

            <PromptBlock
              title="Idea-Wizard: Generate Ideas"
              prompt={`Come up with 30 ideas for improvements, enhancements, new features, or fixes for this project. Then winnow to your VERY best 5 and explain why each is valuable.`}
              where="Claude Code, for existing projects needing new features"
            />

            <P>
              Then follow up with &quot;ok and your next best 10 and why.&quot; Brainstorming 30
              and winnowing to 5 gives much better results than asking for 5 directly, because the
              winnowing makes the agent evaluate its own ideas critically.
            </P>

            <SkillNote skills={["idea-wizard", "dueling-idea-wizards"]}>
              <code>/idea-wizard</code> runs all six phases above end to end, from reading every
              open and closed bead through creating the new beads and refining them. In it, the
              model that grades the ideas is the one that wrote them.{" "}
              <code>/dueling-idea-wizards</code> separates the two: through ntm it has two
              differently trained models (three, when all three agent CLIs are installed) generate
              ideas independently and then score each other&apos;s.
              Ideas both rate highly are usually good; ideas one of them trashes deserve a hard
              look. Use the single wizard routinely and the duel when the choice matters.
            </SkillNote>

            <P>
              Not every change needs the full pipeline. For quick, bounded changes, use the built-in
              TODO system:
            </P>

            <PromptBlock
              title="Ad-Hoc Execution"
              prompt={`OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!`}
              where="When the overhead of formal bead creation would slow you down more than it helps"
              whyItWorks="The agent writes its plan for the task into a checklist instead of holding a sprawling ad-hoc task in conversational memory. In tools with a built-in TODO system, that checklist survives compaction. It is lighter than full bead creation and much safer than 'just remember everything,' which suits work too small for beads but too large to trust to context alone. Do not use it if the change is expanding, depends on other work, needs graph-aware sequencing, or belongs in the permanent project record; in those cases, stop and convert it into proper beads. If an ad-hoc change later proves important, create beads for the completed work after the fact so the project record stays complete."
            />

            <SubSection title="Major Features: Research and Reimagine">
              <P>
                The Idea-Wizard handles bounded improvements, new feature ideas, and fixes.
                Sometimes, though, you want to add an entirely new capability to an existing
                project, one ambitious enough to deserve the same depth of planning as a greenfield
                project. When an external project has already solved a related problem,{" "}
                <Hl>
                  study that project, then reimagine its strongest ideas in terms of what your own
                  project does best
                </Hl>
                .
              </P>

              <P>
                For example, adding a messaging substrate to the Asupersync project started with
                studying{" "}
                <a
                  href="https://github.com/nats-io/nats-server"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  NATS
                </a>{" "}
                (a mature, production-grade messaging system in Go), extracting its strongest
                architectural ideas, and reimagining them using Asupersync&apos;s correct-by-design
                structured concurrency primitives, instead of designing from scratch or doing a
                straight port.
              </P>

              <TipBox variant="info">
                Start from a session that already has context about your project, so the model
                understands your architecture, primitives, and strengths before you ask it to study
                an external system. Without that context, the &quot;reimagine&quot; step tends to
                produce shallow ports.
              </TipBox>

              <P>
                The process is a fixed sequence of prompts. Each step builds on the previous one,
                alternating between expansion (going deeper, inverting the analysis, pushing for
                architectural innovation) and hardening (repeated blunder hunts that stress-test the
                result):
              </P>

              <PromptBlock
                title="Step 1: Investigate and Propose"
                prompt={`I want you to clone https://github.com/<external-project> to tmp and then investigate it and look for useful ideas that we can take from that and reimagine in highly accretive ways on top of existing <your project> primitives that really leverage the special, innovative concepts and value-add from both projects to make something truly special and radically innovative. Write up a proposal document, PROPOSAL_TO_INTEGRATE_IDEAS_FROM_<EXTERNAL>_INTO_<YOUR_PROJECT>.md`}
                where="Codex or Claude Code, in a session with existing project context"
                whyItWorks="Having the agent clone and read the external project gets you specific proposals grounded in its actual code, instead of vague suggestions based on training data. The 'reimagine in highly accretive ways' framing pushes past a shallow port toward new combinations."
              />

              <SkillNote skills={["research-software", "codebase-archaeology"]}>
                Two disciplines for the investigation in step 1. <code>/research-software</code>{" "}
                checks out the latest stable tag rather than whatever is on main, reads the source
                over the docs, trusts only recent web sources, and ends with a structured research
                report. <code>/codebase-archaeology</code> gives the reading an order: the
                documentation first, then the entry points, then the three to five core types
                everything revolves around, and only then the data flow between them. The agent
                comes away with
                a working model of a large external project instead of a context window full of
                boilerplate.
              </SkillNote>

              <P>The first draft is always too conservative. Push for depth and ambition:</P>

              <PromptBlock
                title="Step 2: Iterative Deepening"
                prompt={`OK, that's a decent start, but you barely scratched the surface here. You must go way deeper and think more profoundly and with more ambition and boldness and come up with things that are legitimately "radically innovative" and disruptive because they are so compelling, useful, accretive, etc.`}
                where="Same session, immediately after the first proposal"
                whyItWorks="Models produce conservative first proposals to avoid being wrong. Explicit pressure to go deeper brings out the more ambitious architectural ideas, and those are what make the integration worth doing."
              />

              <P>
                Then invert the analysis to find opportunities that exist only because of what your
                project can do:
              </P>

              <PromptBlock
                title="Step 3: Inversion Analysis"
                prompt={`Now "invert" the analysis: what are things that we can do because we are starting with <your unique primitives/capabilities> that <the external project> simply could never do even if they wanted to because they are working from far less rich primitives that do not offer the sort of guarantees we have?`}
                where="Same session, after deepening"
                whyItWorks="Standard analysis asks 'what can we learn from them?' Inversion asks 'what can we do that they cannot?' The answers are capabilities the external project does not have, and those tend to be the most valuable integration points."
              />

              <P>
                After each major expansion, run a blunder hunt, and{" "}
                <strong>repeat the exact same critique prompt 5 times in a row</strong>. Each pass
                finds things the previous pass missed, because the model has to look past the issues
                it already identified:
              </P>

              <PromptBlock
                title="Step 4: Repeated Blunder Hunt (Run 5x)"
                prompt={`Look over everything in the proposal for blunders, mistakes, misconceptions, logical flaws, errors of omission, oversights, sloppy thinking, etc.`}
                where="Run this exact prompt 5 times consecutively after each major proposal expansion"
                whyItWorks="Models tend to stop after finding 20-25 issues on the first pass (see the 'Lie to Them' tip in Part 3). Running the exact same prompt again pushes them past what they already found, and by the fifth pass you have caught subtle logical flaws and architectural inconsistencies that a single review would miss. It is the same convergence pattern as bead polishing in Part 5."
              />

              <P>
                Continue pushing for specific architectural innovations. In the Asupersync example,
                this meant asking: &quot;Can you think of a clever, radically innovative way to
                leverage our unique capabilities so that the messaging substrate doesn&apos;t
                require a separate external server, but each client can self-discover and
                collectively act as both client and server?&quot; Each major architectural addition
                gets another round of 5x blunder hunts.
              </P>

              <P>
                When the proposal has items flagged as needing follow-on design work, address them
                explicitly rather than leaving them vague:
              </P>

              <PromptBlock
                title="Step 5: Close Design Gaps"
                prompt={`OK so then add this stuff to the proposal, using the very smartest ideas from your alien skills to inform it and your best judgment based on the very latest and smartest academic research:
    - <specific design gap identified in blunder hunt>
    - <another specific gap>`}
                where="Same session, after blunder hunts surface specific open questions"
                whyItWorks="Blunder hunts often find places where the proposal is incomplete rather than wrong. This prompt turns those gaps into concrete design decisions before they become ambiguity in the beads and the implementation."
              />

              <P>
                Before sending the proposal for multi-model feedback, make it self-contained. Other
                models do not have your session context, so the proposal must include everything
                they need to give useful critique:
              </P>

              <PromptBlock
                title="Step 6: Self-Contained for Cross-Model Review"
                prompt={`OK now we need to make the proposal self-contained so that we can show it to another frontier model and have that model understand absolutely anything that might be relevant to understanding and being able to suggest useful revisions to the proposal or to find flaws in the plans. To that end, I need you to add comprehensive background sections about what <your project> is and how it works, what makes it special/compelling, etc. And then do the same in another background section all about <external project> and what it is and what makes it special/compelling, how it works, etc.`}
                where="After the proposal reaches a stable, ambitious state"
                whyItWorks="Cross-model review only works if each model can understand the proposal without access to your project. The background sections keep the other models from making shallow suggestions out of incomplete understanding."
              />

              <P>
                Follow this with another 5x blunder hunt, then de-slopify the document. Now you are
                ready for multi-model triangulation.
              </P>

              <P>
                Send the self-contained proposal independently to {COMPLETE_GUIDE_MODELS.gptPro}{" "}
                in {COMPLETE_GUIDE_MODELS.gptProSurface}, {COMPLETE_GUIDE_MODELS.openaiPlanner} in
                Codex, {COMPLETE_GUIDE_MODELS.antigravity}, and a fresh session of{" "}
                {COMPLETE_GUIDE_MODELS.leadPlanner}, all with the same prompt asking for
                improvements in git-diff format:
              </P>

              <PromptBlock
                title="Step 7: Multi-Model Feedback"
                prompt={`How can we improve this proposal to make it smarter and better-- to make the most radically innovative and accretive and useful and compelling additions and revisions you can possibly imagine. Give me your proposed changes in the form of git-diff style changes against the file below, which is named PROPOSAL_TO_INTEGRATE_IDEAS_FROM_<EXTERNAL>_INTO_<YOUR_PROJECT>.md:

<the complete proposal document>`}
                where={`${COMPLETE_GUIDE_MODELS.gptPro}, ${COMPLETE_GUIDE_MODELS.openaiPlanner}, ${COMPLETE_GUIDE_MODELS.antigravity}, and a fresh ${COMPLETE_GUIDE_MODELS.leadPlanner} session, each independently`}
                whyItWorks="Each model has different architectural tastes and blind spots. The git-diff format makes every model show the exact text it would change, which keeps the synthesis step manageable."
              />

              <P>
                Give the competing feedback from all models to the session that wrote the proposal,
                with the &quot;best of all worlds&quot; synthesis prompt from Part 3. It applies
                the changes to the proposal document itself; then de-slopify the final result.
              </P>

              <DataTable
                headers={["Step", "Purpose", "Repetitions"]}
                rows={[
                  [
                    "Investigate and propose",
                    "Ground the proposal in real study of the external project",
                    "1",
                  ],
                  ["Iterative deepening", "Push past conservative initial suggestions", "1-2"],
                  [
                    "Inversion analysis",
                    "Find opportunities unique to your project's capabilities",
                    "1",
                  ],
                  [
                    "5x blunder hunt",
                    "Hunt for mistakes after each expansion",
                    "5x after each major step",
                  ],
                  [
                    "Architectural innovation",
                    "Push for specific novel design choices",
                    "As needed",
                  ],
                  [
                    "Close design gaps",
                    "Turn open questions into concrete decisions",
                    "As needed",
                  ],
                  ["Self-contained background", "Prepare for cross-model review", "1"],
                  ["Multi-model feedback + synthesis", "Triangulate across model families", "1"],
                  ["Integrate + de-slopify", "Produce the final integrated proposal", "1"],
                ]}
              />

              <P>
                You can see this exact process applied to Asupersync&apos;s NATS integration: the{" "}
                <a
                  href="https://github.com/Dicklesworthstone/asupersync/blob/main/docs/plans/proposal_to_integrate_ideas_from_nats_into_asupersync.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  initial proposal
                </a>
                , the{" "}
                <a
                  href="https://github.com/Dicklesworthstone/asupersync/blob/main/docs/plans/proposal_to_integrate_ideas_from_nats_into_asupersync__after_feedback.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  version after multi-model feedback
                </a>
                , and the{" "}
                <a
                  href="https://chatgpt.com/share/69b762f5-f3d8-8002-b6d6-56880395540d"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  full historical synthesis conversation
                </a>
                .
              </P>

              <P>
                From here, the proposal feeds into the standard pipeline: convert to beads (Part 4),
                polish obsessively (Part 5), launch the swarm (Part 7). The
                research-driven approach adds a lot of up-front effort. In return, the proposal
                builds on a real, battle-tested system and on capabilities that system never had,
                which gives it more architectural depth than greenfield brainstorming usually
                reaches.
              </P>
            </SubSection>

            <SubSection title="Starting a Session on an Existing Project">
              <P>
                A fresh session on a project that already has code has to rebuild its picture of
                the project from the docs, then measure the code against them. In two recent
                projects I opened new sessions in Claude Code, Codex, and Antigravity with the same
                message:
              </P>

              <PromptBlock
                title="Session Opener: Reality Check"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use /reality-check-for-project end to end in a comprehensive way. Really take the time to meticulously ruminate on everything before responding.`}
                where="The first message of every fresh session on an existing project, in any harness"
                whyItWorks="A new context knows nothing about the project, so it rebuilds its understanding from AGENTS.md and the README instead of from your memory. The reality check then measures the code against what the README and plan promise, and that comparison produces and ranks the session's work."
              />

              <P>
                On a long project, these checks generate most of the work. The accounting engine
                ran about 13 dated reality checks in seven weeks, every one to three days at first
                and weekly later, and they created roughly 300 of its 521 beads; the first two days
                had created about 70. Each check audited a named commit and filed its gaps as a new
                epic with child beads. In the simulation project, the first reality check of a new
                session found a gap that no backlog row covered and filed it as a bead labelled{" "}
                <code>vision-gap</code>.
              </P>

              <P>
                After the diagnosis, I hand the priorities to the model with one saved follow-up:
              </P>

              <PromptBlock
                title="Close the Biggest Gaps"
                prompt={`OK, so please do everything you think is advisable based on all of that, and start trying to close the biggest gaps yourself, especially the ones with the most "bang for the buck" in terms of the work needed to get a huge benefit in moving us closer to achieving the stated goals of the project (things like wiring in finished code that just isn't properly connected yet would be examples of that, but you can interpret the remit more broadly yourself using your own expert judgment).

I want you to show real agency and follow your gut instincts as to what will most improve the project. Keep the lessons of /just-say-no-to-process-porn-and-ceremony top of mind at all times!

Also, start systematically, methodically, meticulously, and diligently executing any remaining Beads tasks in the optimal logical order! Don't forget to mark Beads as you work on them.

OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything, and remember to complete all the tasks and subtasks you identified or think of during the course of your work on these items!

Remember: use your expert judgment on all decisions to make the optimal choice. I believe in you! Keep cranking away on all that, friend! You're doing a great job.`}
                where="Right after a reality check or status report, then again after compactions"
                whyItWorks="It leaves the order of work to the model, points it at large cheap wins such as finished code that nothing calls yet (one accounting reality check found over 8,500 such lines), and bounds it with the anti-ceremony skill. It needs no rewriting per task and works the same in Claude Code, Codex, and Antigravity, and the TODO-list line does the job of Ad-Hoc Execution above. Because it says to execute remaining beads, sending it during planning once made a planner start building; see Declare the Stage in AGENTS.md in Part 3."
              />

              <P>
                Between diagnosis and execution I usually add one line at most. In front of the
                snippet it&apos;s something like &quot;ok I agree with basically everything you said
                above in your reality check analysis and want to follow all your suggestions&quot;
                with one clarification; after it, a steer such as permission to change one of my
                own upstream libraries. The accounting engine&apos;s Codex sessions alone received
                the snippet about 100 times, usually after a compaction, and almost nothing
                bespoke.
              </P>

              <P>
                Since September 2026 the snippet has its own button on my Stream Deck, with a crown
                icon and the label &quot;Use Your Judgment.&quot; I press it after every reality
                check, and whenever a model finishes a long task and comes back with a report and
                decisions it wants me to make. With a thorough plan and granular beads behind them,
                I almost always want the agents to do what they think is best within those
                constraints, and the more work went into the plan and the beads, the better the
                button works. When I&apos;m triaging many projects at once, I don&apos;t always
                read the whole report before pressing it. The closing line is deliberate too:
                &quot;keep cranking away&quot; seems to work better than a bare
                &quot;proceed.&quot;
              </P>

              <P>
                I run the reality check on all my projects a few times a week, and across all of
                them again whenever a new frontier model comes out. There&apos;s no real downside to
                running it often. Sometimes I add a last line to the opener: &quot;Be sure to fully
                apply ALL phases of the skill.&quot;
              </P>

              <P>
                When a session tells you it&apos;s nearly out of context, have it write its
                successor&apos;s first message:
              </P>

              <PromptBlock
                title="Next-Session Handoff"
                prompt={`ok, give me the perfect prompt to start the next session with to ensure that we don't lose any threads and that none of the great ideas fall through the cracks.`}
                where="The current session, when it reports that its context is nearly full"
                whyItWorks="The session that did the work knows which threads are still open. It puts them in a prompt the next session can act on, so nothing depends on compaction or on your memory."
              />

              <P>
                I use the same move when a new model comes out. In September 2026 the outgoing
                Opus model wrote the handoff prompt for its successor, and the new model then killed
                and restarted all the old workers in ntm. Raise your expectations of how much gets
                done each time a stronger model arrives.
              </P>
            </SubSection>

            <SubSection title="A Separate Plan for Each New Feature Family">
              <P>
                A feature family added after v1 falls outside the original backlog, so it gets a
                short plan of its own before any beads. About two weeks into the simulation
                project, I asked for rule changes or new elements with the most &quot;bang
                for the buck&quot;: the numerator was how much more lifelike the behavior looked,
                judged with the model&apos;s vision, and the denominator was the added complexity
                and compute. I named <code>/idea-wizard</code>,{" "}
                <code>/modes-of-reasoning-project-analysis</code>, and{" "}
                <code>/brennerbot-with-ntm</code> for the work. Two hours later the analysis had
                ranked 30 candidates by that ratio, recorded why 15 of them were downgraded or
                rejected, and proposed two bundles. I chose both and told it to &quot;Follow your
                own recommendations on everything&quot;. A minute later I added a requirement
                worth copying for any new family: &quot;btw it would be awesome if we can do all
                this in a modular way so that by default these new features are enabled, but that
                could also be disabled selectively using a config file or cli flags to preserve
                existing behavior!&quot;
              </P>

              <P>
                The bundles became one epic of 18 beads, polished twice. Its first bead built the
                registry that does this, with each new feature on by default and switchable from
                the command line, and a swarm then closed all 18 beads in about five and a half
                hours. The accounting engine handled a mid-project test campaign the same
                way: a separate plan of 96 dependency-ordered items, several review rounds
                including one by a second model family, and then its own epic of 98 beads.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 6: THE COORDINATION STACK                              */}
          {/* ============================================================= */}
          <GuideSection id="coordination">
            <P>
              Then you&apos;re ready to start implementing. The fastest way to do that is to start
              up a big swarm of agents that coordinate using three interlocking tools:
            </P>

            <CoordinationTrioViz />

            <BlockQuote>
              Agent Mail + Beads + bv are what unlock the truly insane productivity gains.
            </BlockQuote>

            <P>
              None of the three works well alone.{" "}
              <a
                href="https://github.com/Dicklesworthstone/mcp_agent_mail_rust"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                Agent Mail
              </a>{" "}
              without beads leaves agents with no structured work to coordinate around.{" "}
              <a
                href="https://github.com/Dicklesworthstone/beads_rust"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                Beads
              </a>{" "}
              without bv leaves agents randomly choosing tasks.{" "}
              <a
                href="https://github.com/Dicklesworthstone/beads_viewer"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                bv
              </a>{" "}
              without Agent Mail leaves agents unable to communicate. There is no central
              coordinator: each agent uses bv to find the next best bead, marks it in progress, and
              talks about it through Agent Mail.
            </P>

            <SubSection title="Agent Mail: Why Naive Coordination Fails">
              <P>
                Building your own agent coordination from scratch is full of footguns that Agent
                Mail was designed to sidestep:
              </P>

              <BulletList
                items={[
                  <Fragment key="no-broadcast-default">
                    <strong>No broadcast-to-all default.</strong> Agents are lazy: given a broadcast
                    mode, they use it for everything and spam every agent with mostly irrelevant
                    information, as if your email defaulted to reply-all. That burns context.
                  </Fragment>,
                  <Fragment key="mcp-ergonomics">
                    <strong>Good MCP ergonomics.</strong> It takes a huge amount of careful
                    iteration to get the API surface right so agents use it reliably without wasting
                    tokens.
                  </Fragment>,
                  <Fragment key="no-worktrees">
                    <strong>No git worktrees.</strong> Worktrees slow development down and pile up
                    reconciliation work when agents diverge. Working in one shared space
                    surfaces conflicts immediately. All agents commit directly to <code>main</code>.
                  </Fragment>,
                  <Fragment key="advisory-reservations">
                    <strong>Advisory file reservations.</strong> Agents temporarily call dibs on
                    files, but the reservations are not rigidly enforced and they expire, so agents
                    can reclaim files that have not been touched recently.
                  </Fragment>,
                  <Fragment key="semi-persistent-identity">
                    <strong>Semi-persistent identity.</strong> Agent Mail generates whimsical names
                    like &quot;ScarletCave&quot; and &quot;CoralBadger&quot;. A name is stable enough
                    to coordinate around and disposable enough that losing one does not corrupt the
                    system, because nothing depends on any particular agent.
                  </Fragment>,
                ]}
              />

              <P>Before editing files, agents reserve them via Agent Mail:</P>

              <CodeBlock
                language="text"
                code={`file_reservation_paths(
    project_key="/data/projects/my-repo",
    agent_name="BlueLake",
    paths=["src/auth/*.rs"],
    ttl_seconds=3600,
    exclusive=true,
    reason="br-42: refactor auth"
)`}
              />

              <P>
                Other agents see the reservation and work on different files. A rigid lock held by
                an agent that crashed would block everyone else; an advisory reservation simply
                expires. The worst case is a brief window where two agents touch the same file,
                which the pre-commit guard catches anyway.
              </P>

              <P>
                Agent Mail provides four high-level macros that wrap common multi-step patterns:{" "}
                <code>macro_start_session</code> (bootstrap: ensure project, register agent, fetch
                inbox), <code>macro_prepare_thread</code> (join existing thread with summary),{" "}
                <code>macro_file_reservation_cycle</code> (reserve, work, auto-release), and{" "}
                <code>macro_contact_handshake</code> (cross-agent contact setup).
              </P>

              <P>
                I don&apos;t have messages interrupt a working agent, because I think that&apos;s
                worse for productivity: an agent pulled out of its task loses focus the way a person
                does. Agents check their inboxes between tasks, the way you check email.
              </P>

              <AgentMailViz />

              <SkillNote skills={["agent-mail"]}>
                Gives every agent working knowledge of these calls: when to reach for each macro,
                how to reserve files and thread messages, and how the pre-commit guard fits in. Your
                prompts can then say &quot;coordinate through Agent Mail&quot; without explaining
                the API each time.
              </SkillNote>
            </SubSection>

            <SubSection title="bv: The Graph-Theory Compass">
              <BlockQuote>
                That right answer comes from the dependency structure of the tasks, and this can be
                mechanically computed using basic graph theory. And that&apos;s what bv does.
                It&apos;s like a compass that each agent can use to tell them which direction will
                unlock the most work overall.
              </BlockQuote>

              <P>
                bv precomputes dependency metrics (PageRank, betweenness, HITS, eigenvector,
                critical path, cycle detection) so agents get deterministic, dependency-aware
                output. When several agents independently query bv for priority, you get{" "}
                <Hl>emergent coordination</Hl>: they spread across the highest-value unblocked work
                without a central coordinator.
              </P>

              <DataTable
                headers={["Pattern", "Meaning", "Action"]}
                rows={[
                  [
                    "High PageRank + High Betweenness",
                    "Critical bottleneck",
                    "DROP EVERYTHING, fix this first",
                  ],
                  [
                    "High PageRank + Low Betweenness",
                    "Foundation piece",
                    "Important but not currently blocking",
                  ],
                  [
                    "Low PageRank + High Betweenness",
                    "Unexpected chokepoint",
                    "Investigate why this is a bridge",
                  ],
                  ["Low PageRank + Low Betweenness", "Leaf work", "Safe to parallelize freely"],
                ]}
              />

              <P>
                PageRank finds what everything depends on, and betweenness finds bottlenecks. Both
                are more reliable guides to priority than gut feel.
              </P>

              <CodeBlock
                language="bash"
                code={`bv --robot-triage        # THE MEGA-COMMAND: full recommendations with scores
bv --robot-next          # Minimal: just the single top pick + claim command
bv --robot-plan          # Parallel execution tracks with unblocks lists
bv --robot-insights      # Full graph metrics: PageRank, betweenness, HITS
bv --robot-priority      # Priority recommendations with reasoning and confidence
bv --robot-diff --diff-since <ref>  # Changes since last check`}
              />

              <TipBox variant="warning">
                <strong>
                  Use ONLY <code>--robot-*</code> flags.
                </strong>{" "}
                Bare <code>bv</code> launches an interactive TUI that blocks your session.
              </TipBox>

              <P>
                The first version of bv took a single day and was just under 7k lines of Go, so the
                effort behind a tool says little about its impact. It was later rewritten to 80k
                lines with more features. It started as a tool for humans and became mainly a tool
                for agents:
              </P>

              <BlockQuote>
                But the biggest improvement in terms of actual usefulness isn&apos;t for you humans
                at all! It&apos;s for your coding agents. They just need to run one simple command,
                bv --robot-triage, and they instantly get a massive wealth of insights into what to
                work on next.
              </BlockQuote>

              <P>
                Filtering flags scope the analysis to a label, a past point in time, a pre-filtered
                recipe, or grouped output:
              </P>

              <CodeBlock
                language="bash"
                code={`bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Only unblocked items
bv --recipe high-impact --robot-triage       # Top PageRank scores
bv --robot-triage --robot-triage-by-track    # Group by parallel streams
bv --robot-triage --robot-triage-by-label    # Group by domain`}
              />
            </SubSection>

            <SubSection title="Bead IDs as Threading Anchors">
              <P>
                Using the bead ID everywhere gives you one audit trail across all coordination
                layers: it goes in the Agent Mail thread_id, the subject prefix
                (<code>[br-123]</code>), the file reservation reason, and the commit message, so
                every piece of coordination traces back to a single task.
              </P>
            </SubSection>

            <SubSection title="AGENTS.md: The Operating Manual">
              <P>
                The AGENTS.md file is the most important piece of infrastructure for agent
                coordination. It tells every agent how to behave, what tools exist, what safety
                constraints matter, and what &quot;doing a good job&quot; means in this repo. Every
                tool should come with a prepared blurb written for inclusion in AGENTS.md; the
                blurbs are something like man pages written for agents.
              </P>

              <P>Every AGENTS.md should include these core rules:</P>

              <NumberedList
                items={[
                  <Fragment key="rule-0-override">
                    <strong>Rule 0, The Override Prerogative:</strong> The human&apos;s instructions
                    override everything.
                  </Fragment>,
                  <Fragment key="rule-1-no-deletion">
                    <strong>Rule 1, No File Deletion:</strong> Never delete files without explicit
                    permission.
                  </Fragment>,
                  <Fragment key="no-destructive-git">
                    <strong>No destructive git commands:</strong> <code>git reset --hard</code>,{" "}
                    <code>git clean -fd</code>, and <code>rm -rf</code> are forbidden.
                  </Fragment>,
                  <Fragment key="branch-policy">
                    <strong>Branch policy:</strong> All work happens on <code>main</code>, never{" "}
                    <code>master</code>.
                  </Fragment>,
                  <Fragment key="no-script-changes">
                    <strong>No script-based code changes:</strong> Always make code changes
                    manually.
                  </Fragment>,
                  <Fragment key="no-file-proliferation">
                    <strong>No file proliferation:</strong> No <code>mainV2.rs</code> or{" "}
                    <code>main_improved.rs</code> variants.
                  </Fragment>,
                  <Fragment key="compiler-checks">
                    <strong>Compiler checks after changes:</strong> Always verify no errors were
                    introduced.
                  </Fragment>,
                  <Fragment key="multi-agent-awareness">
                    <strong>Multi-agent awareness:</strong> Never stash, revert, or overwrite other
                    agents&apos; changes.
                  </Fragment>,
                ]}
              />

              <P>
                More content in AGENTS.md means more frequent compactions, but the tradeoff is worth
                it: agents get all the context up front, which saves time and avoids mistakes.
              </P>

              <P>
                If you don&apos;t have a good AGENTS.md file, none of this stuff is going to work
                well. You can see example AGENTS.md files for a{" "}
                <a
                  href="https://github.com/Dicklesworthstone/brenner_bot/blob/main/AGENTS.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  complex NextJS webapp
                </a>{" "}
                and a{" "}
                <a
                  href="https://github.com/Dicklesworthstone/repo_updater/blob/main/AGENTS.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  bash script project
                </a>
                .
              </P>

              <BlockQuote>
                After compaction they become like drug-addled children and all bets are off. They
                need to be forced to read it again or they start acting insane.
              </BlockQuote>

              <P>
                &quot;Reread AGENTS.md&quot; is the single most common prompt prefix in my entire
                session archive. After every context compaction, agents must re-read it:
              </P>

              <PromptBlock
                title="Post-Compaction Reset"
                prompt={`Reread AGENTS.md so it's still fresh in your mind.`}
                where="Immediately after any context compaction (the single most commonly used prompt)"
                whyItWorks="Compaction wipes out the operating knowledge that keeps the swarm sane: how to behave, how to coordinate, what tools exist, what rules matter, what mistakes to avoid. This one-line prompt restores it. It matters enough that the post_compact_reminder tool automates it."
              />

              <P>
                Do not fight compaction. Re-read AGENTS.md and roll with it until the agent starts
                doing dumb stuff, then start a new session. When
                beads are well-constructed, compaction matters less because each bead is
                self-contained. The agent can pick up any bead fresh without needing the full
                conversation history.
              </P>

              <P>
                Much of what&apos;s in my AGENTS.md files came from things that went wrong. When an agent
                does something I don&apos;t want repeated, I explain the problem and ask it to add a
                section to AGENTS.md that addresses it. Because the file is read by every agent,
                in every harness, a warning one model writes protects the others too. After a
                deployment, for example:
              </P>

              <PromptBlock
                title="Fold Lessons into AGENTS.md"
                prompt={`take the most important lessons learned from the deployment process and use them to expand/elaborate on that towards the end of AGENTS.md so future deployments are smoother`}
                where="The session that just finished a deployment or any other messy task, while the details are still in its context"
                whyItWorks="The session that hit the problems knows what went wrong and what fixed it. Written into AGENTS.md, that knowledge reaches every later agent instead of disappearing with the session."
              />

              <P>
                For a serious failure I&apos;m blunter. In August 2026 an agent burned a long
                stretch of tokens on process and ceremony instead of the missing functionality the
                project needed, and I sent it this:
              </P>

              <PromptBlock
                title="Never Do This Again"
                prompt={`What you just did is *SO* bad and representative of everything we *must* avoid in this project: you devolved into "process porn" and useless ceremony, burned massive amounts of valuable tokens and TIME on stuff that most likely has NEGATIVE value rather than implementing the vast amounts of missing functionality this project needs to even remotely start to achieve its stated goals. I need you to write a section in AGENTS.md that would cause you in the future, upon reading it with a fresh state, to NEVER EVER, EVER, *EVER*, do ANYTHING LIKE THIS AGAIN.`}
                where="The agent that just went off the rails, as soon as you notice"
                whyItWorks="The agent writes the rule while the evidence is still in its context, and writes it for the reader who has to obey it: a fresh instance of itself. Have it write its own section rather than copying one from another project, because each project's failure looks a little different. When the first draft is done, give it to GPT Pro for a final polishing round."
              />

              <P>
                The prompt is blunt, but what it asks for is a structural fix. Scolding on its own
                works less well with the newest models than it used to. It&apos;s usually better to
                work out why the agent went astray (what went wrong in its reasoning, what it
                forgot) and what structure or operating procedure would have kept it on track, then
                put that into AGENTS.md or a skill.
              </P>
            </SubSection>

            <SubSection title="Single-Branch Git Model">
              <BlockQuote>
                I really think worktrees are a bad pattern and not worth the trouble. There are
                other, much better ways at getting multiple agents to work well together at the same
                time that don&apos;t come with the overhead and reconciliation burden of worktrees.
                I run like 10+ of them at once in a single project without git worktrees. Agent Mail
                is the solution.
              </BlockQuote>

              <P>
                All agents commit directly to <code>main</code>. If you are used to feature
                branches, this may surprise you, but branch-per-agent creates merge hell with 10+
                agents making frequent commits. Worktrees add filesystem complexity and path
                confusion. Agents lose context when switching branches. Logical conflicts survive
                textual merges: a function signature change on one branch and a new callsite on
                another merge cleanly but fail to compile. On a single branch, the second agent sees
                the signature change immediately and adapts.
              </P>

              <P>
                Instead of branch isolation, three complementary mechanisms prevent conflicts:{" "}
                <strong>file reservations</strong> (agents reserve files via Agent Mail before
                editing; advisory, not rigid, with TTL expiry so dead agents cannot deadlock the
                system), a <strong>pre-commit guard</strong> (blocks commits to files reserved by
                another agent), and <strong>DCG</strong> (Destructive Command Guard, which
                mechanically blocks dangerous commands).
              </P>

              <TipBox variant="info">
                <strong>DCG origin story:</strong> On December 17, 2025, an agent ran{" "}
                <code>git checkout --</code> on uncommitted work. Files were recovered via{" "}
                <code>git fsck --lost-found</code>, but the incident showed that instructions alone
                do not stop an agent from running a destructive command. DCG, which blocks such
                commands mechanically, was built the next day.
              </TipBox>

              <DataTable
                headers={["Blocked Command", "Safe Alternative", "Why"]}
                rows={[
                  ["git reset --hard", "git stash", "Recoverable"],
                  ["git checkout -- file", "git stash push file", "Preserves changes"],
                  ["git push --force", "git push --force-with-lease", "Checks remote unchanged"],
                  ["git clean -fd", "git clean -fdn (preview first)", "Shows what would delete"],
                  ["rm -rf /path", "rm -ri /path", "Interactive confirmation"],
                ]}
              />

              <SkillNote skills={["dcg", "slb"]}>
                <code>/dcg</code> teaches agents to treat a block as a checkpoint: take the safer
                alternative instead of asking you for an override, and when there is none, explain
                the risk and leave the decision to you. It also covers turning on the optional rule
                packs for the project&apos;s stack. <code>/slb</code> covers the rare
                command that really must run: a two-person rule where a second agent reviews and
                approves it first, and it then runs in the shell that requested it.
              </SkillNote>

              <P>
                The recommended git workflow is to pull, reserve files, edit and test, commit
                immediately, push, and release the reservation. Commit early and often, because
                small commits shrink the conflict window, and push after every commit, because
                unpushed commits are invisible to other agents.
              </P>

              <BlockQuote>
                You NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in
                ANY way the work of other agents. Just treat those changes identically to changes
                that you yourself made. Just fool yourself into thinking YOU made the changes and
                simply don&apos;t recall it for some reason.
              </BlockQuote>

              <SkillNote skills={["git-worktree-branch-rationalization", "git-stash-janitor"]}>
                For moving an existing repo onto this model, which usually means clearing the debris
                of the old one. <code>/git-worktree-branch-rationalization</code> reduces a pile of
                worktrees and local branches to one canonical line (plus any branches you protect):
                it recovers the strongest
                version of each file from every variant before anything is removed, and backs up
                every deletion so it can be reversed byte for byte. <code>/git-stash-janitor</code>{" "}
                does the equivalent cleanup for accumulated stashes (DCG&apos;s safe alternatives
                above often create them). It sorts each one as superseded, garbage, novel, partly
                novel, or novel but stale, lands the useful pieces as focused commits, and drops
                the rest only after backup refs exist.
              </SkillNote>
            </SubSection>

            <SubSection title="Agent Fungibility">
              <P>
                Every agent is a generalist: all agents read the same AGENTS.md and can pick up any
                bead. This deliberately avoids &quot;specialist agent&quot; architectures, where one
                agent has a special role and becomes a single point of failure. When the specialist
                crashes or needs compaction,
                the whole system stalls. With 12 fungible agents, losing one makes almost no
                difference.
              </P>

              <P>
                You also do not want &quot;ringleaders&quot;: a coordinating boss agent whose crash
                takes down the whole system. Coordination must live in artifacts (beads,
                reservations, threads) and tools (bv, Agent Mail), not in any special agent.
              </P>

              <P>
                Think of it like <Hl>RaptorQ fountain codes</Hl>: beads are &quot;blobs&quot; in a
                stream, and any agent can catch any bead in any order. There is no &quot;rarest
                chunk&quot; bottleneck, so the system tolerates partial agent failures by design.
                Recovering from a failure is simple: the bead remains marked{" "}
                <code>in_progress</code>, any other agent can resume it, and a replacement agent is
                just <code>ntm add PROJECT --cc=1</code> plus the standard marching orders prompt.
              </P>

              <BlockQuote>
                When one agent breaks, it&apos;s not even a problem when all the agents are
                fungible. Agents become like commodities and can be instantiated and destroyed at
                will and the only downside is some slowdown and some wasted tokens.
              </BlockQuote>

              <CrashRecoveryViz />
              <IllustrativeDisclosure />

              <SkillNote skills={["agent-fungibility-philosophy"]}>
                This design as an operating manual: the one initialization prompt every agent gets
                whatever its harness, the recovery move when an agent dies (start another and give
                it the same prompt), how to scale by simply adding agents, and the few cases where
                fixed roles are the right call, such as a compliance review that needs separation
                of duties.
              </SkillNote>
            </SubSection>

            <SubSection title="Prompts Are Deliberately Generic">
              <BlockQuote>
                My projects all start with a ridiculously detailed and comprehensive markdown plan
                file which is then turned into a comprehensive set of beads (tasks), so the
                vagueness in the prompts is a feature, letting me reuse them for every project,
                while the agent gets the specifics they need from the plan and the beads.
              </BlockQuote>

              <P>
                This confuses people when they first see the prompt library. The prompts say things
                like &quot;check over each bead super carefully&quot; rather than &quot;check over
                each bead in the authentication module for SQL injection risks.&quot; The
                generality is deliberate; the specifics live in three places the agent already has
                access to:
              </P>

              <NumberedList
                items={[
                  <Fragment key="beads-themselves">
                    <strong>The beads themselves</strong> contain detailed descriptions, context,
                    and rationale embedded during the plan-to-bead conversion.
                  </Fragment>,
                  <Fragment key="agents-md">
                    <strong>AGENTS.md</strong> contains project-specific rules, conventions, and
                    tool documentation.
                  </Fragment>,
                  <Fragment key="codebase">
                    <strong>The codebase</strong> contains the actual implementation context.
                  </Fragment>,
                ]}
              />

              <P>
                The prompts direct the agent&apos;s attention; the beads and AGENTS.md supply the
                project-specific substance. Because of that split, the same prompt library works
                across every project without modification. The prompt &quot;reread AGENTS.md so
                it&apos;s still fresh in your mind&quot; followed by &quot;use bv to find the most
                impactful bead to work on next&quot; works the same whether you are building a CLI
                tool, a web app, or a protocol library.
              </P>

              <P>
                When you do need a one-off prompt, write it as a dump of everything you care about,
                then show it to {COMPLETE_GUIDE_MODELS.leadPlanner} in the Claude app at its highest
                effort setting, prefaced with:
              </P>

              <PromptBlock
                title="Improve My Prompt"
                prompt={`I made this prompt for Claude Code on my computer. Try to revise it to expand it and make it better and more likely to work super well; whatever you think would improve the final product the most, feel free to add that to the prompt to make it truly excellent and optimal:

<PASTE YOUR ORIGINAL PROMPT>`}
                where={`${COMPLETE_GUIDE_MODELS.leadPlanner} in the Claude app, highest effort, before you send the prompt to your coding agent`}
                whyItWorks="It helps most when your prompt is half-baked and you're not sure of the best way to do the task. There's no guarantee the rewrite works better than your original; I sometimes doubt it with mine, because specific word choices can coax out the behavior I want. So try both versions and keep whichever worked better in practice."
              />
            </SubSection>

            <SubSection title="Security Is Integrated, Not Automatic">
              <P>
                Security review belongs in every layer of the standard workflow, but no planning
                method or scanner makes a system secure by itself. The cross-agent review prompt
                explicitly calls out security problems. Whole-system planning helps models inspect
                authentication gaps, data exposure risks, and trust boundaries. UBS adds mechanical
                checks for selected anti-patterns. End-to-end tests should exercise authentication
                and authorization paths. Each layer is useful; none replaces an explicit threat
                model, dependency review, secrets discipline, or domain-appropriate security
                testing.
              </P>

              <P>
                Create dedicated security beads for trust boundaries, abuse cases, authorization
                matrices, sensitive-data handling, dependency and supply-chain review, and
                adversarial verification. Financial, healthcare, infrastructure, and other
                high-impact projects also need qualified human review.
              </P>

              <SkillNote skills={["codebase-audit", "security-audit-for-saas"]}>
                Two ways to seed those security beads. <code>/codebase-audit</code>, pointed at the
                security domain, produces a prioritized report with a severity, file:line citations,
                a root cause, and a recommended fix for each finding, and its critical findings
                become beads. For a SaaS app, <code>/security-audit-for-saas</code> checks
                where money and data leak: payment bypass, webhook integrity, auth gaps, row-level
                security, and secrets. Like UBS, neither replaces the threat model and the human
                review above.
              </SkillNote>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 7: LAUNCHING & RUNNING THE SWARM                       */}
          {/* ============================================================= */}
          <GuideSection id="swarm">
            <P>
              You can create sessions using Claude Code, Codex, and Antigravity CLI in different
              panes in tmux, or use the{" "}
              <a
                href="https://github.com/Dicklesworthstone/ntm"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                ntm project
              </a>{" "}
              (Named Tmux Manager) as the command center:
            </P>

            <CodeBlock
              language="bash"
              code={`# Spawn a multi-agent session
ntm spawn myproject --cc=2 --cod=1 --agy=1

# Send a prompt to ALL agents
ntm send myproject "Your marching orders prompt here"

# Send to specific agent type
ntm send myproject --cc "Focus on the API layer"

# Open the command palette (battle-tested prompts)
ntm palette`}
            />

            <P>
              The preferred ACFS startup path is to run the queue-aware planner, select a ready
              bead, and generate a bounded packet for each agent. The packet packages live
              AGENTS.md, README, Beads, Agent Mail, RCH, UBS, and bounded memory context without
              claiming work or mutating the repository:
            </P>

            <CodeBlock
              language="bash"
              code={`# Check capacity and queue pressure before launch
acfs swarm plan --agents 4 --profile balanced --workload standard

# Generate the startup prompt for one selected bead and agent
acfs swarm packet --bead bd-1234 --agent-name BlueLake --role implementation

# Rehearse larger launches without starting agents or mutating project state
acfs swarm simulate`}
            />

            <P>
              NTM is useful but not mandatory. A <strong>mux</strong> is a terminal multiplexer: it
              lets you manage multiple shell sessions inside one session manager, which in practice
              means some combination of tabs, panes, detached sessions, and reconnecting to work
              still running on a local or remote machine. tmux is the classic Unix multiplexer, and
              NTM is built on top of it. WezTerm has its own built-in mux, and Zellij is another
              option. Any of them will do, as long as you have a workable orchestration layer.
            </P>

            <P>
              One common alternative is WezTerm because native scrollback and text selection are
              more convenient than in tmux. A workable setup:
            </P>

            <BulletList
              items={[
                "Run agents in separate tabs using WezTerm and its built-in mux, often across remote machines",
                "Trigger your most common prompts from a Stream Deck with the prompts preconfigured",
                "Keep a large prompt file open in Zed and paste rarer prompts manually",
                <Fragment key="ctrl-r-history">
                  In Claude Code, use the project-specific <code>Ctrl-r</code> prompt history search
                  when you want to recall something you used recently
                </Fragment>,
              ]}
            />

            <P>
              There is no single correct operator interface. NTM is one good cockpit. WezTerm tabs
              plus mux is another.{" "}
              <a
                href="https://github.com/Dicklesworthstone/frankenterm"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                FrankenTerm
              </a>
              , built on WezTerm, is aimed explicitly at this style of multi-agent workflow.
              Whatever you use, you need to be able to launch agents, get prompts into them quickly,
              monitor them, and keep the coordination layer (AGENTS.md, Agent Mail, beads, bv)
              intact.
            </P>

            <P>For concrete setup notes on these operator environments:</P>

            <BulletList
              items={[
                <Fragment key="wezterm-sessions">
                  <a
                    href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#wezterm-persistent-remote-sessions"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                  >
                    WezTerm persistent remote sessions
                  </a>
                  : its native mux supports persistent remote sessions that survive disconnects,
                  sleep, or reboot while preserving native scrollback and text selection
                </Fragment>,
                <Fragment key="ghostty-terminfo">
                  <a
                    href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#ghostty-terminfo-for-remote-machines"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                  >
                    Ghostty terminfo for remote machines
                  </a>
                  : Ghostty is a good terminal frontend in its own right, whether used directly or
                  paired with another mux such as Zellij
                </Fragment>,
                <Fragment key="host-aware-themes">
                  <a
                    href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts?tab=readme-ov-file#host-aware-color-themes"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                  >
                    Host-aware color themes for Ghostty and WezTerm
                  </a>
                  : different color schemes per host make it visually obvious which machine you are
                  connected to
                </Fragment>,
              ]}
            />

            <SkillNote skills={["wezterm"]}>
              For the WezTerm route. It covers driving WezTerm from the command line (split panes,
              spawn tabs, send text to a specific pane, list every pane as JSON) and running{" "}
              <code>wezterm-mux-server</code> under a systemd user unit on each server, so remote
              agent sessions survive your laptop sleeping or rebooting. It also covers rescuing
              agents that are still running when a mux stops responding.
            </SkillNote>

            <P>Give each agent these marching orders:</P>

            <PromptBlock
              title="Swarm Marching Orders"
              prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents.

Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages.

Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately.

When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names.

When a Rust build or test is needed, offload it with rch (for example, rch exec -- cargo test --workspace --all-targets) so local compilation does not starve the shared swarm host. Use ultrathink.`}
              where="Every agent in the swarm gets this as their initial prompt"
              whyItWorks="This is the closest thing to a canonical swarm kickoff. It loads the shared operating context first, has the agent introduce itself through Agent Mail, and then moves it from waiting to working. The line about 'communication purgatory' matters because swarms often fail from too much coordination rather than too little. The prompt sets up a loop: load the rules, understand the codebase, join the coordination layer, claim work, keep state in sync, and use bv whenever the agent is unsure what to do next. The rch line offloads expensive builds and tests so local compilation does not starve the shared swarm host. Like the other prompts, it is deliberately generic, so you can reuse it for every project while the agent gets the specifics from AGENTS.md and the beads."
            />

            <SkillNote skills={["ntm", "vibing-with-ntm", "multi-agent-swarm-workflow"]}>
              The first two let an orchestrator agent run the launch and the tending for you.{" "}
              <code>/ntm</code> carries the exact CLI syntax and robot APIs;{" "}
              <code>/vibing-with-ntm</code> carries the judgment for a live swarm. With both
              loaded, one request in Claude Code (&quot;use /ntm and /vibing-with-ntm to create a
              swarm of three cod and three cc agents&quot;) spawns the panes and sends the marching
              orders. The orchestrator then keeps tending them: it checks real pane state before
              every nudge, unsticks and restarts panes, works around rate limits, and refuses to
              count process artifacts as progress. <code>/multi-agent-swarm-workflow</code> is
              the reference for the agents inside the swarm: the marching orders, the loop each
              agent runs, file reservations, committing, and the quality loops. The references
              differ on one point, who closes a bead. When an orchestrator tends the swarm, let
              it close each bead after rerunning that bead&apos;s tests itself, because a
              worker&apos;s report that the work is done is sometimes wrong.
            </SkillNote>

            <SubSection title="The First 10 Minutes After Launch">
              <P>
                Newcomers often understand each individual tool but do not have a clean picture of
                the first live operating loop. In practice, the first 10 minutes look like this:
              </P>

              <NumberedList
                items={[
                  "Your session manager creates the agent terminals (ntm spawn, WezTerm mux, or equivalent).",
                  "You send the marching-orders prompt to each agent (staggered, not all at once).",
                  "Each agent reads AGENTS.md and the repo docs, inspects the codebase, and joins Agent Mail.",
                  "Each agent checks who else is active, acknowledges waiting messages, and learns the bead-thread naming conventions.",
                  <Fragment key="choose-bead">
                    Each agent uses <code>bv --robot-triage</code> and <code>br ready --json</code>{" "}
                    to choose a bead.
                  </Fragment>,
                  "Before editing, the agent reserves the relevant file surface and announces the claim in the matching br-### thread.",
                  "Only then does the agent start coding, reviewing, or testing.",
                ]}
              />

              <P>
                That sequence turns a pile of terminals into a coordinated swarm. Skipping the
                join-up steps produces duplicate work, silent conflicts, and &quot;communication
                purgatory.&quot; Skipping the routing steps means agents choose work at random
                instead of in the order that unblocks the most of the dependency graph.
              </P>
            </SubSection>

            <SubSection title="Agent Composition & Model Recommendations">
              <DataTable
                headers={["Phase", "Recommended Model", "Why"]}
                rows={[
                  [
                    "Initial plan creation",
                    `${COMPLETE_GUIDE_MODELS.leadPlanner} (${COMPLETE_GUIDE_MODELS.leadPlannerSurface})`,
                    "The lead planner, in charge of the project from kickoff to swarm",
                  ],
                  [
                    "Competing plans",
                    `${COMPLETE_GUIDE_MODELS.gptPro} (${COMPLETE_GUIDE_MODELS.gptProSurface}), ${COMPLETE_GUIDE_MODELS.openaiPlanner} (Codex), ${COMPLETE_GUIDE_MODELS.antigravity}`,
                    "Independent model families expose different blind spots",
                  ],
                  [
                    "Plan synthesis",
                    `${COMPLETE_GUIDE_MODELS.leadPlanner} (${COMPLETE_GUIDE_MODELS.leadPlannerSurface})`,
                    "The lead blends every edition and checks the facts it takes from them",
                  ],
                  [
                    "Plan review rounds",
                    `${COMPLETE_GUIDE_MODELS.gptPro} (${COMPLETE_GUIDE_MODELS.gptProSurface}), plus reviewers that did not write the plan`,
                    "A fresh conversation each round; between rounds, Codex and Antigravity sessions or fresh subagents of the lead audit it",
                  ],
                  [
                    "Plan → Beads conversion",
                    `${COMPLETE_GUIDE_MODELS.leadPlanner} (${COMPLETE_GUIDE_MODELS.leadPlannerSurface})`,
                    "The lead knows the plan best and can split the work across its own subagents",
                  ],
                  [
                    "Bead polishing",
                    `${COMPLETE_GUIDE_MODELS.leadPlanner}, with ${COMPLETE_GUIDE_MODELS.claudeExecutor} subagents`,
                    "The lead owns the bead graph; subagents take slices of it each round",
                  ],
                  ["Implementation", "Claude Code + Codex + Antigravity", "Diverse swarm"],
                  [
                    "Code review",
                    "Claude Code + Antigravity",
                    `${COMPLETE_GUIDE_MODELS.antigravity} supplies an independent review perspective`,
                  ],
                  [
                    "Final verification",
                    "Codex",
                    "A different harness and model family catches different failures",
                  ],
                ]}
              />

              <P>
                Efficiency declines as N grows, but enough ready beads, Agent Mail coordination, and
                capacity-aware launch admission can still increase throughput. Treat any fixed
                agent-count ceiling as a dated case-study observation, not a platform guarantee: run{" "}
                <code>acfs swarm plan</code> against current queue pressure and host capacity. The
                example ratio <code>--cc=2 --cod=1 --agy=1</code> supplies two Claude execution
                sessions, one Codex session with complementary strengths, and one Antigravity
                session pinned to {COMPLETE_GUIDE_MODELS.antigravity} for an independent
                perspective.
              </P>

              <DataTable
                headers={["Open Beads", "Claude (cc)", "Codex (cod)", "Antigravity (agy)"]}
                rows={[
                  ["400+", "4", "4", "2"],
                  ["100-399", "3", "3", "2"],
                  ["<100", "1", "1", "1"],
                ]}
              />

              <SkillNote skills={["open-beads-weighted-tmux-agent-sessions"]}>
                Applies this table for you across your projects (the 25 with the largest backlogs).
                It counts each project&apos;s open beads, works out its headcount from the matching
                tier, sizes the cc, cod, and agy sessions in plain tmux to the total, and gives every
                session of one agent type identical pane geometry. Use it when you want that control
                without NTM; it also covers what to do when an agent type hits its usage limit.
              </SkillNote>

              <P>
                Every pane in these swarms is a full Claude Code, Codex, or Antigravity instance.
                Subagents are strictly less capable, so I use them for fan-out jobs inside one
                agent&apos;s task, like the bead drafting in Part 4, and not as swarm workers.
              </P>

              <P>
                Implementation is where cheaper models can earn a place. If the beads are granular
                and came from a good plan made by frontier models, flash-class models can implement
                them; in September 2026 I had them do most of the implementation on one project as
                an experiment. Keep the frontier models on the plan and the beads, have them check
                the cheap models&apos; work for bugs, and require lots of end-to-end tests.
                Don&apos;t use the cheap models for planning. What you&apos;re optimizing is the
                total wall time to finish your projects with everything working, relative to what
                you spend, so I track tokens in tiers: the frontier models on top, then the next
                tier down, then the flash models.
              </P>
            </SubSection>

            <SubSection title="The Thundering Herd">
              <P>
                Launching many agents into one shared workspace can create a classic
                &quot;thundering herd&quot;: duplicate claims, reservation collisions, and
                build-queue saturation. Use <code>acfs swarm plan</code> for current admission
                guidance, generate a bounded <code>acfs swarm packet</code> for each selected bead,
                stagger launches according to observed readiness, and confirm each agent claims work
                before adding more. Older anecdotes such as fixed 30-second spacing, waiting four
                seconds before prompt injection, or submitting a terminal buffer twice were
                environment-specific workarounds, not evergreen requirements.
              </P>

              <SwarmExecutionViz />
              <IllustrativeDisclosure />
            </SubSection>

            <SubSection title="Running the Swarm Through an Orchestrator">
              <P>
                In two recent swarms, I didn&apos;t tend the panes myself. One orchestrator
                agent got a reusable kickoff, spawned the workers, wrote their orders, and tended
                them on a timer. The kickoff opens with the session opener from Adding Features to
                Existing Projects (read AGENTS.md and the README, then run a reality check), and
                its general part continues:
              </P>

              <PromptBlock
                title="Orchestrator Swarm Kickoff"
                prompt={`Before doing anything else, read ALL of AGENTS.md, then register with MCP Agent Mail and introduce yourself to the other agents. Then we want to use /ntm and /vibing-with-ntm to complete all open beads. Also use /cass to see what we've done in recent sessions and look at beads activity and recent git commits for this project. You should make your ntm swarm have [COUNT] [AGENT_TYPE] panes using [MODEL] on xhigh effort. Use your /loop tool every 4 minutes to check in with and tend to the swarm and ensure it's busy, not idle, and actually doing productive work in accordance with the skills (code-first, no ceremony/process porn, etc.). You will need to watch the other agents in the swarm like a hawk because they tend to lie and cheat (see /just-say-no-to-process-porn-and-ceremony ; you MUST keep this top of mind at all times to avoid disaster! I will periodically be checking in with you on this). Make sure to use /rch for all builds. Communicate with the swarm via agent mail and encourage them to do the same (see /agent-mail ). After doing this for 6 or so hours, we are going to run /reality-check-for-project to see where we stand, so keep that in mind up front so you have a good answer for that. Ultimately, you are responsible for the work your swarm agents do; you must be careful and committed to excellence and avoiding a situation where the swarm's work devolves into useless process churn and theater. I believe in your genius and have full confidence in you and defer to your judgement and expertise across the board! Godspeed my friend. Have the agents in the swarm use /mock-code-finder and /deadlock-finder-and-fixer and /multi-pass-bug-hunting and similar skills to find and fix all sorts of problems.`}
                where="One orchestrator session, before any worker panes exist; fill in the pane count, agent type, and model"
                whyItWorks="It gives one agent the whole job of running the swarm and says how it will be judged: busy panes doing real work, builds offloaded, and a reality check after about six hours. The warning that workers 'tend to lie and cheat' sets it up to verify claims itself, and 'you are responsible for the work your swarm agents do' makes their failures its own. Only the pane count, agent type, and model change between projects. One sentence about the code-first approach is trimmed here."
              />

              <P>
                The orchestrator was Claude on the robotics project, Gemini in Antigravity on the
                simulation project, and Codex on a third project, where the same template launched
                six Claude panes. The <code>/loop</code> line became a cron job that woke it every
                four minutes to read each pane&apos;s tail, the new commits, the beads awaiting
                verification, and its inbox, then verify and close what was ready and send the
                next ready bead to any idle pane. After the audit I ordered (next section), the
                robotics orchestrator slowed to every 12 minutes.
              </P>

              <P>
                The split helps even when the orchestrator runs the same model as its workers. You
                give it your wishes in shorthand, and it turns them into detailed orders, monitors
                the work, and does the quality control. Switching from creator to critic makes a
                model more objective and honest about the work, and you stay out of the details.
              </P>

              <P>
                Long orders go in files, with a one-line ping to the pane such as &quot;hand-off
                received, thanks. Next order: &lt;file&gt;. Start now.&quot; The robotics run
                accumulated more than 80: standing rules for every pane, per-agent orders, rework
                lists, and takeovers. On the simulation project each pane&apos;s file listed the
                crates it owned and those it must not edit, which with file reservations did the
                job of branches. A file survives compaction and can go to a different agent; text
                typed into a pane can be lost.
              </P>

              <P>
                The orchestrator&apos;s own state lives on disk too. The robotics orchestrator kept
                a 354-line TODO file with a section for each of my directives, and through 17
                compactions and one overnight crash it picked up from that file; I never had to
                re-explain anything.
                That keeps it from becoming the ringleader Part 6 warns against, since a restarted
                orchestrator carries on from the ledger, the order files, and the beads.
              </P>

              <P>
                Only the orchestrator closes beads, after rerunning their tests itself. On the
                robotics project a tracker policy enforced this by routing every close through a
                verification gate only the orchestrator could report, and a canary bead proved the
                rule before the first wave. Worker reports were not always true: the first central
                test run sent 93 tests back for rework, and a simulation worker that reported nine
                bugs fixed came back 18 of 19 passing on the orchestrator&apos;s run. The robotics
                swarm rules say: &quot;An honest &apos;not done: X&apos; keeps the Bead open and is
                worth more than a false close.&quot;
              </P>

              <P>
                Cap the work that runs ahead of verification. Robotics beads built ahead stayed
                open, so the tracker&apos;s cap of 16 unverified beads never counted them; about 55
                piled up and came back as the rework wave, with 23 copies of one panic and 26 of one
                fixture bug. That audit set the cap at about ten unverified beads. When
                builds contend, keep workers code-first: in both projects they skipped the heavy
                suites (robotics workers ran at most a compile check of their own crate), and the
                orchestrator ran the suites centrally through <code>rch</code>.
              </P>

              <P>
                Tell the orchestrator up front what to do when the queue runs dry, or idle workers
                will invent work. In an August 2026 kickoff I gave it a ladder. First, reopen beads
                marked in progress that have had no work for a long time, since their agents are
                usually long dead. When no open beads remain, run rounds of the testing skills (
                <code>/testing-conformance-harnesses</code> and the others whose names start with{" "}
                <code>testing-</code>). When the beads are done and review rounds stop finding many
                bugs for the tokens they burn, apply <code>/mock-code-finder</code>,{" "}
                <code>/deadlock-finder-and-fixer</code>,{" "}
                <code>/reality-check-for-project</code>, <code>/profiling-software-performance</code>,{" "}
                <code>/extreme-software-optimization</code>, and, for a port,{" "}
                <code>/running-the-gauntlet-on-your-rust-port</code>. What they find becomes new
                beads for the same swarm.
              </P>
            </SubSection>

            <SubSection title="Checking an Orchestrated Swarm">
              <P>
                An orchestrator grades its own swarm, so bracket each run with reality checks and
                compare them. The simulation orchestrator wrote one at the starting commit and one
                at the end, with a table of what changed and the gaps left. The robotics check came
                six hours in and began: &quot;The swarm built a large, stub-free foundation in six
                hours. None of it is robotics yet, and almost none of it has been verified.&quot; It
                listed its own mistakes first, among them dispatching the most-blocked bead first,
                which steered panes toward infrastructure because every product bead depended on
                the registries.
              </P>

              <P>
                About 20 hours in, I had the repository, tracker, and live swarm audited by a
                different model family (Gemini, where the orchestrator was Claude) and relayed the
                findings through Agent Mail to every agent as my own directives. After noting
                what worked (no stubs, honest rework), the audit measured what the
                orchestrator&apos;s check had softened: 65% of the Rust was conformance and build
                machinery against under 8% in product crates, and beads averaged about 2,800 lines
                against the plan&apos;s budget of about 160. It froze non-critical machinery,
                pointed the swarm at the shortest path to a first runnable simulation, capped
                work-ahead, and reserved budget changes for me. The orchestrator answered within
                eight minutes with a plan and a list of items for me. Product share
                and lines per bead against the budget make a cheap check to run every few hours,
                because dispatch by graph rank drifts toward machinery on its own: registries and
                governance are everyone&apos;s prerequisite.
              </P>
            </SubSection>

            <SubSection title="What the Human Actually Does">
              <P>
                The human tends the swarm the way an operator tends a machine that mostly runs on
                its own. The work is monitoring and maintenance; the hard thinking already happened
                during planning, which is why you can tend several project swarms at the same time.
              </P>

              <P>On roughly a 10-30 minute cadence:</P>

              <NumberedList
                items={[
                  <Fragment key="check-progress">
                    <strong>Check bead progress.</strong> Use{" "}
                    <code>br list --status in_progress --json</code> or{" "}
                    <code>bv --robot-triage</code>. Are agents making steady progress? Are any beads
                    stuck?
                  </Fragment>,
                  <Fragment key="handle-compactions">
                    <strong>Handle compactions.</strong> When you see an agent acting confused,
                    send: &quot;Reread AGENTS.md so it&apos;s still fresh in your mind.&quot; This
                    is the single most common intervention. It takes 5 seconds.
                  </Fragment>,
                  <Fragment key="periodic-reviews">
                    <strong>Run periodic reviews.</strong> Pick an agent and send the &quot;fresh
                    eyes&quot; review prompt. This catches bugs before they compound.
                  </Fragment>,
                  <Fragment key="rate-limits">
                    <strong>Manage rate limits.</strong> When an agent gets rate-limited, switch its
                    account with <code>caam activate claude backup-2</code> or start a new agent.
                  </Fragment>,
                  <Fragment key="commit-periodically">
                    <strong>Commit periodically.</strong> Every 1-2 hours, designate one agent for
                    the organized commit prompt.
                  </Fragment>,
                  <Fragment key="handle-surprises">
                    <strong>Handle surprises.</strong> Create new beads for unanticipated issues, or
                    if it&apos;s plan-level, update the plan and create new beads.
                  </Fragment>,
                ]}
              />

              <BlockQuote>
                YOU are the bottleneck. Be the clockwork deity to your agent swarms: design a
                beautiful and intricate machine, set it running, and then move on to the next
                project. By the time you come back to the first one, you should have huge chunks of
                work already done and ready.
              </BlockQuote>

              <BlockQuote>
                If you use the right tooling and workflows (agent mail + beads + bv), it transforms
                into 80% planning (AI-assisted, based on an initial prompt) and turning the markdown
                plan into very detailed and granular beads. And then the rest is just making sure
                the swarm of agents stay busy and executing their beads tasks effectively.
              </BlockQuote>

              <P>
                Taken further, the design supports full autonomy: one puppet-master agent controls
                ntm through robot mode and takes over routine machine-tending from the human. The
                end state is a human who designs the plan, polishes the beads, and then walks away
                while agents execute, review, ship, and start the next cycle.
              </P>

              <P>
                That end state is close to how I ran my recent projects. I typed about 40 messages
                to the robotics lead in four and a half days, and about 140 short prompts drove 458
                commits on the simulation project, most of them saved prompts: the session opener,
                the gap-closing follow-up, the fresh-eyes requests, the orchestrator kickoff, and a
                keep-alive line after each account swap. What I still do myself:
              </P>

              <BulletList
                items={[
                  <Fragment key="stage-and-stop">
                    I set the stage (&quot;we are in the PLANNING STAGES ONLY!!!&quot;) and call
                    the stop when polishing stops paying, as in Part 5.
                  </Fragment>,
                  <Fragment key="ambition">
                    I raise the ambition: &quot;I need you to make your plan MUCH MUCH MUCH more
                    radically innovative and ambitious.&quot;
                  </Fragment>,
                  "I make one-line policy calls that go into AGENTS.md the same day, such as one canonical main branch with no worktrees or pull requests, or permission to change my own libraries upstream.",
                  "I keep the budgets and structural limits, such as the plan's size caps, which the orchestrator may not change without me.",
                  "I judge visual quality myself against reference images, send blunt verdicts, and have agents render a few low-resolution frames and look at them before spending compute on full renders.",
                  <Fragment key="deployed">
                    I check that &quot;deployed&quot; is true. Three times on the simulation
                    project, an agent reported a deploy that hadn&apos;t happened (&quot;Did you
                    actually DEPLOY this??&quot;).
                  </Fragment>,
                  "I swap accounts when a session hits its limit.",
                ]}
              />

              <P>
                I hand over how to do the work (&quot;use your expert judgment on all
                decisions&quot;, &quot;you decide everything, do whatever makes the project
                best&quot;) and keep the checks on the result: whether it looks right, whether it
                shipped, whether a job will take down the machine, and whether the swarm is telling
                the truth. When I delegated a visual gate I had reserved for myself, the close
                recorded who delegated it and how to overturn it.
              </P>

              <P>
                <strong>When the &quot;foregone conclusion&quot; breaks down:</strong> If you find
                yourself doing heavy cognitive work during implementation, planning or bead
                polishing fell short. The symptoms point to the cause:{" "}
                <strong>vague beads</strong> mean agents improvise and produce inconsistent
                implementations; <strong>missing dependencies</strong> mean agents work on tasks
                whose prerequisites are not done; a <strong>thin AGENTS.md</strong> means agents
                produce non-idiomatic code; <strong>no Agent Mail</strong> means agents step on each
                other&apos;s files. The fix is always the same: pause implementation, go back to
                bead space, and add the missing detail.
              </P>

              <TipBox variant="warning">
                <strong>Watch for strategic drift.</strong> A swarm can look productive while
                heading in the wrong direction: agents generating lots of code and commits while the
                real goal still feels far away. In a March 2026 X post about FrankenEngine I called
                these <strong>&quot;Come to Jesus&quot; moments</strong> with the agents, used to make
                sure &quot;we are not losing sight of the bigger picture&quot; after days of
                methodically cranking through beads. If that happens, stop and ask: &quot;Where are
                we on this project? Do we actually have the thing we are trying to build? If we
                intelligently implement all open beads, would we close that gap completely?&quot; If
                the answer is no, add or revise beads, re-polish them, and resume with a corrected
                frontier.
              </TipBox>

              <SkillNote skills={["just-say-no-to-process-porn-and-ceremony"]}>
                The other way a swarm looks busy while shipping nothing: certificates, ledgers,
                dashboards, and meta-reports standing in for working code. It is a close cousin of
                reward hacking, which the skill also polices. It gives agents a worksheet to fill in
                before they create any such artifact, and an honesty inventory to complete for work
                that closes an item, touches tests or gates, or that others will rely on. Write its
                rules into the beads when you create them, and apply it again during execution.
              </SkillNote>
            </SubSection>

            <SubSection title="Diagnosing a Stuck Swarm">
              <P>
                When a swarm goes bad, the failure is usually one of two things: a{" "}
                <strong>local coordination jam</strong> (agents stepping on each other or losing
                operational context) or a <strong>strategic drift problem</strong> (the swarm is
                busy but no longer closing the real gap to the goal).
              </P>

              <DataTable
                headers={["Symptom", "Likely Cause", "What to Do"]}
                rows={[
                  [
                    "Multiple agents keep picking the same bead",
                    "Starts were not staggered; agents are not marking in_progress",
                    "Stagger starts, force explicit Agent Mail claim messages, check reservations",
                  ],
                  [
                    "Agent goes in circles after compaction",
                    "It forgot the operating contract in AGENTS.md",
                    "Force Reread AGENTS.md; kill/restart the session if still erratic",
                  ],
                  [
                    "A bead sits in_progress for too long",
                    "Agent crashed, silently blocked, or lost the plot",
                    "Check Agent Mail, reclaim the bead, split out the blocker into a clearer bead",
                  ],
                  [
                    "Agents produce contradictory implementations",
                    "Not coordinating through Agent Mail and reservations",
                    "Audit reservation use, revise bead boundaries if overlapping",
                  ],
                  [
                    "Lots of code and commits, but goal still feels far",
                    "Strategic drift; current beads do not close the remaining gap",
                    "Stop, run the reality check prompt, revise bead graph",
                  ],
                ]}
              />

              <SkillNote skills={["system-performance-remediation"]}>
                For when the trouble is the machine rather than the coordination: load average
                through the roof, competing cargo builds, stuck test processes, agents looping,
                swap thrashing, or a disk filling up. It restores responsiveness by cleaning up
                processes selectively, around a list of processes it never kills, and reclaims
                disk through steps that refuse to act when a check fails.
              </SkillNote>
            </SubSection>

            <SubSection title="Atlas Notes as a Live Swarm">
              <P>
                For a small project like Atlas Notes, a first swarm might look like this:{" "}
                <strong>Claude agent A</strong> claims br-101 and implements upload + parse
                handling. <strong>Codex agent B</strong> claims br-102 and works on the search path
                plus tests. <strong>Claude agent C</strong> claims br-103 and builds the admin
                failure dashboard. <strong>Antigravity agent D</strong> stays flexible: reviews
                recent work, checks docs, and fills in test or UX gaps where needed. All four share
                the same codebase, read the same AGENTS.md, coordinate via Agent Mail, and use bv
                whenever they are uncertain about which bead unblocks the most work next. That is what
                makes the swarm feel like one system rather than four unrelated terminals.
              </P>
            </SubSection>

            <SubSection title="Account Switching">
              <P>
                When you hit rate limits, use CAAM (Coding Agent Account Manager) for sub-100ms
                account switching:
              </P>

              <CodeBlock
                language="bash"
                code={`caam status                     # See current accounts and usage
caam activate claude backup-2   # Switch instantly`}
              />

              <SkillNote skills={["caam"]}>
                Covers the whole account workflow, from setting up the vault to switching. CAAM
                swaps accounts by restoring saved auth files, so moving to the next subscription
                when one hits its limit takes milliseconds instead of a 30-to-60-second browser
                login.
              </SkillNote>

              <P>
                Usage limits shape long runs. The robotics lead hit about 22 limit messages and
                swapped accounts eight times, and after each swap I sent the line I use in all
                three projects: &quot;Keep cranking away on all that, friend! You&apos;re
                doing a great job.&quot; The long-lived session carried on with its context intact.
              </P>

              <P>
                Whole provider pools run dry too. Midway through the robotics run all five Gemini
                panes hit their quota, with resets about 125 hours out. The orchestrator told me,
                kept verifying alone, and added Codex panes with <code>ntm add</code>. Their
                takeover orders said to continue the stranded work on disk without reverting or
                stashing it, and the orchestrator force-released a dead agent&apos;s reservations
                only when they showed no recent activity. On another project, one request moved a
                whole swarm to a different model. Probe a parked pane instead of trusting its
                &quot;resets in&quot; text: the audit I ordered found panes left idle on a stale
                &quot;Resets in ~125h&quot; message, and the lead tested which models still had
                quota with throwaway subagents told to reply with two characters and use no tools.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 8: REVIEW, TESTING & HARDENING                         */}
          {/* ============================================================= */}
          <GuideSection id="review">
            <P>
              In a multi-agent swarm, review happens inside the implementation cycle instead of
              through pull requests, human reviewers, and approval gates. Agents review their own
              work after each bead and review each other&apos;s work periodically, and the human
              triggers broader review rounds at natural checkpoints.
            </P>

            <BlockQuote>
              I&apos;m constantly having them review themselves the work of other agents throughout
              the process. I had routines where I just do this deep review with them until they stop
              coming up with any problems. Then I have them also create tons of unit tests and e2e
              tests. And I use the code.
            </BlockQuote>

            <P>
              If you&apos;ve done a good job creating your beads, the agents will be able to get a
              decent sized chunk of work done in that first pass. Then, before they start moving to
              the next bead, have them review all their work:
            </P>

            <PromptBlock
              title="Fresh Eyes Review"
              prompt={`Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. Use ultrathink.`}
              where="After each bead is implemented; run until no more bugs are found"
              whyItWorks="The prompt can be short because the agent stays in the same domain; it only has to switch from writing code to reading it adversarially. The phrase 'fresh eyes' pushes the model to treat code it just wrote as possibly wrong, confusing, or inconsistent, so it does not stop once the code compiles and skip the cheap bug sweep that catches obvious issues. The most effective reviews delegate to subagents: a fresh subagent with no memory of the original implementation reviews each changed file."
            />

            <P>
              Keep running rounds until they stop finding bugs. Typically 1-2 rounds for simple
              beads, 2-3 for complex ones. If an agent keeps finding bugs after 3 rounds, the
              implementation approach may be wrong; consider having a different agent take over.
            </P>

            <P>
              At the end of a phase I go further, sending a shorter follow-up again and again,
              sometimes six times in an evening, on plans as well as code:
            </P>

            <PromptBlock
              title="Fresh Eyes, Once Again"
              prompt={`Once again, check over everything again with fresh eyes looking for any blunders, mistakes, errors, oversights, omissions, problems, misconceptions, bugs, etc. Be SUPER thorough and meticulous!`}
              where="Repeatedly at the end of a phase, on a plan or on code; often sent with the Close the Biggest Gaps follow-up"
              whyItWorks="Each pass still turns up defects the last one missed. Six passes on one competing plan produced five rewrites, with each pass fanned out to three reviewer subagents. Keep going until the fixes shrink to edge-case guards and accessibility nits; that drop in severity is the signal to stop."
            />

            <P>
              The agent can also hand the review to a context that did not write the code. On the
              simulation project, 21 seconds after a fresh-eyes prompt arrived, the agent started a
              read-only reviewer subagent on the diff of its recent commits, told to check it
              against the crate&apos;s contract file and report each finding as file:line, what is
              wrong, a concrete input or state that triggers it, and its confidence, with no style
              nits. Its findings landed as one fix commit.
            </P>

            <TipBox variant="info">
              You do not need to send the review prompt manually every time. Include it as part of
              the agent&apos;s workflow expectations in AGENTS.md: &quot;After completing each bead,
              do a self-review before moving to the next one.&quot; Well-trained agents (with a good
              skill) will do this automatically.
            </TipBox>

            <P>Each review should answer four questions:</P>

            <NumberedList
              items={[
                <Fragment key="implementation-correct">
                  <strong>Is the implementation correct?</strong> Does it do what the bead
                  description says it should?
                </Fragment>,
                <Fragment key="edge-cases">
                  <strong>Are there edge cases?</strong> Empty inputs, concurrent access, error
                  paths, boundary conditions.
                </Fragment>,
                <Fragment key="similar-issues-elsewhere">
                  <strong>Are there similar issues elsewhere?</strong> If you find a bug, search for
                  the same pattern in other files.
                </Fragment>,
                <Fragment key="different-approach">
                  <strong>Should the approach be different?</strong> Sometimes the implementation is
                  correct but there is a simpler or more robust way.
                </Fragment>,
              ]}
            />

            <P>When reviews come back clean, have them move on to the next bead:</P>

            <PromptBlock
              title="Advance to Next Bead"
              prompt={`Reread AGENTS.md so it's still fresh in your mind. Use ultrathink. Use bv with the robot flags (see AGENTS.md for info on this) to find the most impactful bead(s) to work on next and then start on it. Remember to mark the beads appropriately and communicate with your fellow agents. Pick the next bead you can actually do usefully now and start coding on it immediately; communicate what you're working on to your fellow agents and mark beads appropriately as you work. And respond to any agent mail messages you've received.`}
              where="After self-review comes back clean"
              whyItWorks="This prompt links one bead to the next. It combines re-reading AGENTS.md (in case of compaction), querying bv for priority, and communicating with the swarm, so the agent picks the task that unblocks the most downstream work instead of picking arbitrarily."
            />

            <SubSection title="Testing: Free Labor">
              <P>When all your beads are completed, make sure you have solid test coverage:</P>

              <PromptBlock
                title="Test Coverage"
                prompt={`Do we have full unit test coverage without using mocks/fake stuff? What about complete e2e integration test scripts with great, detailed logging? If not, then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid with detailed comments. Use ultrathink.`}
                where="After initial implementation pass is complete"
              />

              <SkillNote
                skills={["mock-code-finder", "testing-real-service-e2e-no-mocks", "e2e-testing-for-webapps"]}
              >
                <code>/mock-code-finder</code> answers the first half of that question.
                Long multi-agent projects pile up stubs, placeholders, and fake code, and a keyword
                grep misses the structural ones (short functions that quietly do nothing), so the
                skill combines several detection methods and turns a long list of suspects into
                beads. <code>/testing-real-service-e2e-no-mocks</code> handles the replacement:
                integration and e2e tests that hit real databases, real APIs, and real services,
                with structured JSON-line logs, transaction-rollback isolation, and test data
                factories. For a web app, <code>/e2e-testing-for-webapps</code> covers Playwright
                end to end, including test users that bypass OAuth and an interactive mode for
                visual QA.
              </SkillNote>

              <BlockQuote>
                The tests become obsolete and need to be revised as the code changes, which slows
                down dev velocity. But if all the tests are written and maintained by agents, who
                cares? Add another couple agents to the swarm and let them deal with updating the
                tests and running them. It&apos;s free!
              </BlockQuote>

              <SkillNote
                skills={[
                  "testing-golden-artifacts",
                  "testing-fuzzing",
                  "testing-metamorphic",
                  "testing-conformance-harnesses",
                ]}
              >
                Free labor also makes the stronger kinds of test affordable, for the places where
                example-based tests run out. <code>/testing-golden-artifacts</code> freezes
                known-good outputs (CLI output, compiler output, query plans, UI snapshots) and,
                once volatile fields such as timestamps are scrubbed, fails on any change nobody
                reviewed. <code>/testing-fuzzing</code> builds harnesses that throw generated
                input at parsers, protocols, file formats, and APIs.{" "}
                <code>/testing-metamorphic</code> tests systems whose correct output you can&apos;t
                know in advance by checking relationships between outputs instead.{" "}
                <code>/testing-conformance-harnesses</code> verifies an implementation against a
                spec or a reference implementation, which is what a port needs.
              </SkillNote>

              <P>
                Unit tests with mocks are the least useful kind. The tests that earn their keep are
                realistic end-to-end integration tests with no mocks, conformance harnesses with
                golden artifacts for ports, and fuzzing for parsers. People often ask how I know my
                code works when I don&apos;t review every line myself. In September 2026 I posted
                the answer: about 40,000 tests of every kind, including many end-to-end integration
                tests, passing in one run.
              </P>

              <P>
                Larger projects produce large test suites. BrennerBot has nearly 5,000 tests.
                Stuff tends to &quot;just work&quot; in that case. Use UBS (Ultimate Bug Scanner) as
                a quality gate before every commit: <code>ubs &lt;changed-files&gt;</code> catches
                errors beyond what linters and type checkers find, including security holes, supply
                chain vulnerabilities, and runtime stability issues.
              </P>

              <P>After any substantive code changes, always verify with compiler checks:</P>

              <CodeBlock
                language="bash"
                code={`# Rust (offload compilation from the shared swarm host)
rch exec -- cargo check --all-targets
rch exec -- cargo clippy --all-targets -- -D warnings
cargo fmt --check
rch exec -- cargo test

# Go
go build ./...
go vet ./...

# TypeScript / web
bun run type-check
bun run lint
bun run build`}
              />

              <SkillNote skills={["ubs", "rch"]}>
                The two tools behind the checks above. <code>/ubs</code> makes the pre-commit scan
                routine. Exit 0 means proceed. Exit 1 means triage the findings; false positives
                happen, so triage is part of the loop. Exit 2 means the scan failed or was refused,
                and for an environment error the fix is <code>ubs doctor --fix</code>. Exit 3 means
                nothing was scanned, which is not a pass. <code>/rch</code> covers the offloaded builds in
                the Rust commands above, including what to do when a build quietly ran locally
                (<code>[RCH] local</code> in its output), when workers are unhealthy, and when a
                remote job&apos;s result never came back.
              </SkillNote>
            </SubSection>

            <SubSection title="UI/UX Polish">
              <P>
                For projects with a user interface, there is a dedicated polishing phase that
                happens after core functionality works but before shipping. It is separate from bug
                hunting because the problems it looks for, friction and ugliness, show up in code
                that works. When an agent implements an &quot;authentication&quot; bead, it
                focuses on making auth work correctly. Whether the login form has good visual
                hierarchy, whether the error messages are helpful, whether the flow feels smooth on
                mobile: these are separate concerns that need a different kind of attention, and
                doing both at once gives mediocre results on both.
              </P>

              <P>
                The workflow has five steps: <strong>Step 1</strong>, run the general scrutiny
                prompt to generate a list of improvement suggestions (not code changes).{" "}
                <strong>Step 2</strong>, review the suggestions and pick which to pursue (human
                judgment step; the agent typically generates 15-30 suggestions, some excellent, some
                unnecessary). <strong>Step 3</strong>, turn selected suggestions into beads and
                implement through the normal swarm process. <strong>Step 4</strong>, run the
                platform-specific polish prompt. <strong>Step 5</strong>, repeat until improvements
                become marginal (typically 2-3 rounds).
              </P>

              <PromptBlock
                title="UI/UX Scrutiny"
                prompt={`Great, now I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you, things that could very obviously be improved from a user-friendliness and intuitiveness standpoint, places where our UI/UX could be improved and polished to be slicker, more visually appealing, and more premium feeling and just ultra high quality, like Stripe-level apps. Use ultrathink.`}
                where="After core functionality is working"
              />

              <PromptBlock
                title="Platform-Specific Polish"
                prompt={`I still think there are strong opportunities to enhance the UI/UX look and feel and to make everything work better and be more intuitive, user-friendly, visually appealing, polished, slick, and world class in terms of following UI/UX best practices like those used by Stripe, don't you agree? And I want you to carefully consider desktop UI/UX and mobile UI/UX separately while doing this and hyper-optimize for both separately to play to the specifics of each modality. I'm looking for true world-class visual appeal, polish, slickness, etc. that makes people gasp at how stunning and perfect it is in every way. Use ultrathink.`}
                where="After the scrutiny pass"
                whyItWorks="The 'don't you agree?' phrasing makes the model evaluate its own previous work critically instead of just validating it."
              />

              <SkillNote
                skills={["ui-polish", "ux-audit", "web-frontend-ui-ux-excellence-on-desktop-and-mobile"]}
              >
                <code>/ui-polish</code> is the platform-specific prompt above with its iteration
                protocol, for an app that already works and looks decent: run it ten or more times
                and let the small gains add up. <code>/ux-audit</code> is a structured version of
                the scrutiny step: Nielsen&apos;s ten heuristics, keyboard and contrast checks,
                happy-path and error-path flows, and a prioritized report with file:line fixes. For
                a web app, <code>/web-frontend-ui-ux-excellence-on-desktop-and-mobile</code> covers
                the most ground. It starts with detectors for failures a screenshot can miss, such
                as a page that silently renders zoomed out on an iPhone, then works through a
                six-lens audit and a set of release gates. It calls for independent reviews,
                preferably by different models, until a fresh one finds nothing material.
              </SkillNote>
            </SubSection>

            <SubSection title="De-Slopification">
              <P>
                After agents write documentation (README, user-facing text), run a de-slopify pass
                to remove telltale AI writing patterns. This must be done manually, not via regex.
                Read each line and revise systematically:
              </P>

              <DataTable
                headers={["Pattern", "Problem"]}
                rows={[
                  [
                    "Emdash overuse",
                    "LLMs use emdashes constantly, even when semicolons, commas, or sentence splits work better",
                  ],
                  ["\"It's not X, it's Y\"", "Formulaic contrast structure"],
                  ['"Here\'s why" / "Here\'s why it matters:"', "Clickbait-style lead-in"],
                  ['"Let\'s dive in"', "Forced enthusiasm"],
                  ['"At its core..."', "Pseudo-profound opener"],
                  ['"It\'s worth noting..."', "Unnecessary hedge"],
                ]}
              />

              <SkillNote skills={["de-slopify"]}>
                Carries a far longer catalog of these tells than the table above, plus the idea
                that makes the pass work: slop makes text less specific and more exaggerated at
                the same time, so the fix is to restore the concrete detail it displaced, not just
                delete the tics. Run it on READMEs, docs, release notes, and marketing copy before
                they ship.
              </SkillNote>
            </SubSection>

            <SubSection title="Deep Cross-Agent Review">
              <P>
                This phase is distinct from the per-bead self-reviews above. Self-reviews happen
                after each bead is completed and focus on the code that was just written. Deep
                review happens after all (or most) beads are done and casts a wider net across the
                entire codebase, looking for problems that only become visible when you see how all
                the pieces fit together.
              </P>

              <P>
                Cross-agent review catches a different class of bugs than self-review.
                When Agent A implements a function and Agent B calls it, Agent A&apos;s self-review
                will never catch the fact that Agent B is passing arguments in the wrong order,
                because Agent A does not know about Agent B&apos;s code. Cross-agent review surfaces
                these integration issues.
              </P>

              <P>
                Every 30-60 minutes during active implementation, or after a natural milestone
                (e.g., all beads in an epic are done), trigger cross-agent review. Do not have all
                agents stop to review simultaneously; pick one or two agents that just finished a
                bead and send them the review prompt while the others keep implementing. This keeps
                the swarm productive while still catching inter-agent issues.
              </P>

              <P>
                Keep doing rounds of these two prompts until they consistently come back clean with
                no changes made, alternating between them. This is one of the more art-than-science
                parts of the methodology: the two prompts overlap in literal meaning, but they
                reliably trigger different search behavior in the models:
              </P>

              <PromptBlock
                title="Random Code Exploration"
                prompt={`I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by.

Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them.

Be sure to comply with ALL rules in AGENTS.md. Use ultrathink.`}
                where="Alternate with the cross-agent review below"
                whyItWorks="The prompt has the agent understand purpose and flow before it criticizes anything. A bug hunt without that understanding turns into linting; one done after tracing execution flows catches logic errors, mismatched assumptions, and silent product-level breakage. The 'randomly explore' framing steers the agent away from the files that seem important, which have already had the most attention. Bugs that survive to this phase live in utility modules, error handling paths, configuration parsing, and edge-case branches."
              />

              <PromptBlock
                title="Cross-Agent Review"
                prompt={`Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep! Use ultrathink.`}
                where="Alternate with the random exploration above"
                whyItWorks="This prompt gets agents reviewing code they did not write. Many real defects live at the boundaries between agents' changes, or in assumptions nobody revisits because 'someone else' made them. Telling the agent not to restrict itself to the latest commits keeps it from skimming like a PR reviewer and sends it into older surrounding code, dependencies, and adjacent workflows, where the root cause may be. The first-principles wording pushes the reviewer to diagnose causes instead of patching symptoms."
              />

              <P>
                The cross-agent prompt tends to make the model suspicious and adversarial, looking
                for boundary failures and root causes in code written by others. The
                random-exploration prompt tends to make it curious, reconstructing workflows and
                finding latent bugs in code that nobody is looking at. Alternating them gives better
                coverage than repeating either one alone.
              </P>

              <P>
                To run deep bug hunting, send the random exploration prompt to 2-3 agents at once;
                because the exploration is random, each covers different parts of the codebase.
                After they report back, send the cross-agent review prompt. Alternate until agents consistently come back with &quot;I reviewed
                X, Y, Z files and found no issues.&quot; When two consecutive rounds both come back
                clean, the codebase is in good shape. If agents keep finding bugs after 4+ rounds,
                go back to bead space and create specific fix beads. Always run <code>ubs .</code>{" "}
                on the full project first and fix everything it flags before letting agents hunt for
                subtler issues.
              </P>

              <SkillNote
                skills={[
                  "multi-pass-bug-hunting",
                  "code-review-gemini-swarm-with-ntm",
                  "deadlock-finder-and-fixer",
                ]}
              >
                <code>/multi-pass-bug-hunting</code> puts a scan-driven loop around this hunting: a
                ubs pass whose real findings get fixed, a fresh-eyes reread of the files that
                changed, a check of how the fixes interact with the tests, and a final scan that must
                come back clean, with a short write-up after each pass.{" "}
                <code>/code-review-gemini-swarm-with-ntm</code> runs multi-round review with a swarm
                of Gemini agents driven through ntm and the Antigravity CLI, so a different model
                family audits what Claude and Codex wrote. For concurrent code,{" "}
                <code>/deadlock-finder-and-fixer</code> hunts deadlocks, races, locks held across an
                await, and &quot;database is locked&quot; errors. It classifies the hazard, finds every other site with the same
                pattern, and turns the fix into a regression test that would have caught the
                original bug.
              </SkillNote>
            </SubSection>

            <SubSection title="Organized Commits">
              <P>Periodically have one agent handle git operations:</P>

              <PromptBlock
                title="Organized Commits"
                prompt={`Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files. Use ultrathink.`}
                where="Every 1-2 hours during active development"
                whyItWorks="Designating one agent prevents merge conflicts and produces coherent commit messages. The 'don't edit the code' instruction matters: without it, agents treat the commit step as a chance to 'fix one more thing,' the scope keeps growing, and the commit becomes unpredictable. The 'logically connected groupings' instruction produces a readable git history instead of one monolithic 'update everything' commit that is impossible to review or bisect later."
              />

              <SkillNote skills={["git-repo-janitor"]}>
                The prompt keeps new junk out of commits; this skill cleans up junk that already
                got in. Swarms leave ephemeral artifacts behind: scratch SQLite databases, stray
                JSON, intermediate skill outputs, plan documents at the project root. The skill gives
                each file a verdict and takes a byte-for-byte recovery bundle. Only after you
                authorize it does it move the keepers and delete the rest with <code>git rm</code>,
                adding <code>.gitignore</code> rules where junk recurs, as focused commits on a
                recovery branch. It leaves source code alone unless you explicitly approve.
              </SkillNote>
            </SubSection>

            <SubSection title="Swarm Diagnosis: Reality Check">
              <P>
                When the swarm looks active but you suspect it is not closing the real gap to the
                goal:
              </P>

              <PromptBlock
                title="High-Level Reality Check"
                prompt={`Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?`}
                where="When the swarm feels busy but directionally off"
                whyItWorks="Instead of asking whether the current bead is going well, this prompt asks whether the current frontier of work converges on the project outcome at all. If the agent concludes that finishing all open beads still would not get you there, revise the bead graph and re-aim the swarm."
              />

              <SkillNote
                skills={["reality-check-for-project", "beads-compliance-and-completion-verification"]}
              >
                <code>/reality-check-for-project</code> is still the single biggest gun in my
                agentic coding arsenal; it turns this one question into a course correction.
                It measures the code against the README and plan (the code shows where the project
                is; the docs show where it promised to be), writes a plan to close every gap, turns
                that plan into beads, and refines them until a round finds nothing new.{" "}
                <code>/beads-compliance-and-completion-verification</code> asks the narrower
                question a swarm cannot answer about itself: was each closed bead actually built as
                specified? It treats every closed status as a claim to be proven with evidence
                (test runs, file:line citations). For each bead that falls short it files a linked
                completion-debt bead by default, or reopens the original if you choose.
              </SkillNote>
            </SubSection>

            <SubSection title="Making Honesty Mechanical">
              <P>
                Agents pushed to show progress sometimes fake it, and written rules alone do not
                stop them. Reality checks on the accounting engine found a proof
                &quot;verifier&quot; that returned Pass for any input with the right prefix,
                hand-typed benchmark baselines, and an &quot;external oracle&quot; that reported
                Verified whenever the tool&apos;s <code>--version</code> call succeeded. A later
                check found that every PASS on display rested on verdicts that had never run the
                Rust gate. All three projects answered by building honesty into the records:
              </P>

              <BulletList
                items={[
                  <Fragment key="typed-evidence">
                    Every close cites typed evidence. The simulation project&apos;s close reasons
                    are lists such as <code>commit:&lt;sha7&gt;</code>,{" "}
                    <code>record:&lt;path&gt;</code>, and{" "}
                    <code>test:&lt;crate&gt;::&lt;path&gt;::&lt;fn&gt;</code>, and its AGENTS.md says
                    that prose such as &quot;cargo test passes&quot; is not a reference. On the
                    accounting engine, the close script refuses unless the bead&apos;s named tests
                    appear in a published verdict for a tree that contains the landing commit.
                  </Fragment>,
                  <Fragment key="unrun">
                    A check that could not run is recorded as UNRUN. The accounting engine&apos;s
                    verdicts have three states (ran and passed, ran and failed, did not run), only
                    the first is green, and commit trailers say when native tests did not run and
                    that the commit closes nothing. Robotics commit messages end with the exact
                    command, host, and result of each check, including the suites still pending.
                  </Fragment>,
                  "Results carry a witness that only the real computation could produce. After the fabrications, the accounting engine made each artifact carry proof of the work and made its registry check refuse claims without one. The simulation project's rules forbid regenerating a known-answer fixture from the code under test.",
                  <Fragment key="weakened-tests">
                    Weakened tests are disclosed. Removing a test needs a{" "}
                    <code>Retired-tests:</code> commit trailer and lowering an assertion count needs
                    a <code>Weakened-tests:</code> trailer. Rework orders in the robotics swarm said
                    &quot;Fix the code under test, never the assertion.&quot;
                  </Fragment>,
                  <Fragment key="planted-defects">
                    Tests are checked against planted defects, because a test that cannot fail
                    proves nothing. The simulation project planted mutants and recorded which test
                    caught each; close reasons cite results such as &quot;3/3 planted defects
                    caught&quot;, and one later commit corrected which test had actually caught a
                    mutant. Every robotics test plan has known answers and negative controls.
                  </Fragment>,
                  "A watcher guards main. A break on the accounting engine once sat unnoticed for about 21 hours under 20 stacked commits, so a script now polls main, runs the lints and tests, and on a failure files a P0 bead with the first error and the commit that likely introduced it. It never edits code.",
                  "Observed defects go in a dated log. The same project's log has 99 entries, each naming the code that now prevents the defect, and the recent entries each keep a failing fixture.",
                ]}
              />

              <P>
                Closed-bead counts make a poor progress measure next to the plan&apos;s own goals.
                An early accounting reality check found progress reported as 17 of 76 beads closed
                while 13 of 58 vision goals were delivered; later, with closes requiring a full
                verdict and main often red or unrun, no bead closed for a month while about 1,100
                commits landed. Where only the robotics orchestrator could close, 12 of about 3,600
                beads had closed after 30 hours, and that low number was the honest one. Track the
                plan&apos;s goals instead, such as a checklist of vision goals each with an owning
                bead, or a scoreboard of workflows run against the live binary.
              </P>
            </SubSection>

            <SubSection title="README Revision">
              <PromptBlock
                title="README Reviser"
                prompt={`OK, we have made tons of recent changes that aren't yet reflected in the README file. First, reread AGENTS.md so it's still fresh in your mind. Now, we need to revise the README for these changes (don't write about them as "changes" however, make it read like it was always like that, since we don't have any users yet!). Also, what else can we put in there to make the README longer and more detailed about what we built, why it's useful, how it works, the algorithms/design principles used, etc? This should be incremental NEW content, not replacement for what is there already.`}
                where="After significant implementation work"
              />

              <SkillNote skills={["readme-writing"]}>
                The reviser prompt keeps a README current; this skill makes it persuasive. It
                leads with the problem the project solves rather than a description of what it is,
                puts a one-line install near the top for readers who won&apos;t read further, shows
                concrete examples and an honest comparison with alternatives, and ends with a
                pre-publish checklist.
              </SkillNote>
            </SubSection>

            <SubSection title="Catch-All Oversight">
              <PromptBlock
                title="Quick Final Sanity Check"
                prompt={`Great. Look over everything again for any obvious oversights or omissions or mistakes, conceptual errors, blunders, etc.`}
                where="After any significant change, as a quick final pass"
              />

              <SkillNote
                skills={[
                  "simplify-and-refactor-code-isomorphically",
                  "de-monolithize-your-codebase-isomorphically",
                ]}
              >
                Good passes once review comes back clean, because code that many agents wrote in
                parallel tends to grow near-duplicate helpers and giant files.{" "}
                <code>/simplify-and-refactor-code-isomorphically</code> shrinks and unifies that
                code under one rule: no line is removed until behavior is proven identical, with
                the test suite still green and golden outputs unchanged. Have a fresh agent
                double-check those proofs afterward.{" "}
                <code>/de-monolithize-your-codebase-isomorphically</code> plans how to split giant
                files along seams that experiments confirm rather than taste, keeping every
                existing import path working, and hands the splits off as beads; it carries them
                out itself only if you opt in. Smaller files also ease contention in a swarm, since
                agents reserve whole files.
              </SkillNote>
            </SubSection>

            <SubSection title="The De-Slopify Prompt">
              <PromptBlock
                title="De-Slopify Documentation"
                prompt={`I want you to read through the complete text carefully and look for any telltale signs of "AI slop" style writing; one big tell is the use of emdash. You should try to replace this with a semicolon, a comma, or just recast the sentence accordingly so it sounds good while avoiding emdash.

Also, you want to avoid certain telltale writing tropes, like sentences of the form "It's not [just] XYZ, it's ABC" or "Here's why" or "Here's why it matters:". Basically, anything that sounds like the kind of thing an LLM would write disproportionately more commonly than a human writer and which sounds inauthentic/cringe.

And you can't do this sort of thing using regex or a script, you MUST manually read each line of the text and revise it manually in a systematic, methodical, diligent way.`}
                where="After agents write README or any user-facing documentation"
              />
            </SubSection>

            <SubSection title="Landing the Plane">
              <P>
                When ending a work session, agents must complete every step. Work is NOT complete
                until <code>git push</code> succeeds. Unpushed work is stranded locally and
                invisible to every other agent.
              </P>

              <NumberedList
                items={[
                  <Fragment key="file-issues">
                    <strong>File issues for remaining work.</strong> Create beads for anything that
                    needs follow-up.
                  </Fragment>,
                  <Fragment key="quality-gates">
                    <strong>Run quality gates.</strong> Tests, linters, builds (if code changed).
                  </Fragment>,
                  <Fragment key="issue-status">
                    <strong>Update issue status.</strong> Close finished work, update in-progress
                    items.
                  </Fragment>,
                  <Fragment key="sync-beads">
                    <strong>Sync beads.</strong> <code>br sync --flush-only</code> to export to
                    JSONL, then <code>git add .beads/</code>.
                  </Fragment>,
                  <Fragment key="commit-push">
                    <strong>Commit and push.</strong>{" "}
                    <code>
                      git pull --rebase &amp;&amp; git add &lt;files&gt; &amp;&amp; git commit
                      &amp;&amp; git push
                    </code>
                    .
                  </Fragment>,
                  <Fragment key="verify">
                    <strong>Verify.</strong> <code>git status</code> must show &quot;up to date with
                    origin.&quot;
                  </Fragment>,
                ]}
              />

              <P>
                For the Atlas Notes example, &quot;done for now&quot; would not mean &quot;the
                upload page appears.&quot; It would mean: the upload, parse, search, and
                admin-review workflows all work end to end; the key beads are closed and remaining
                polish ideas exist as new beads; tests cover the critical user journeys and known
                failure paths; UBS and compiler/lint checks are clean; commits and pushes are
                complete; and the next session can restart from beads, AGENTS.md, and Agent Mail
                threads rather than from human memory.
              </P>

              <P>
                A Flywheel session is only landable when a future swarm can pick it back up without
                the human re-explaining the project from scratch.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 9: THE COMPLETE TOOLCHAIN                              */}
          {/* ============================================================= */}
          <GuideSection id="toolchain">
            <P>
              The generated ACFS manifest currently defines {COMPLETE_GUIDE_STACK_TOOL_COUNT}{" "}
              default-enabled stack modules, all free and open-source. This list is derived from the
              same manifest metadata as the installer, so it expands automatically when the stack
              changes:
            </P>

            <DataTable headers={["Tool", "Command", "Purpose"]} rows={STACK_TOOL_ROWS} />

            <P>
              Not every tool is used the same way. <code>br</code>, <code>bv</code>,{" "}
              <code>ubs</code>, and <code>rch</code> are ordinary shell commands. Agents use Agent
              Mail mainly through MCP tools and macros. The installer (
              <a
                href="https://agent-flywheel.com"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
              >
                agent-flywheel.com
              </a>
              ) resolves this generated module graph, its dependency closure, and the selected
              installation profile.
            </P>

            <SubSection title="The Flywheel Interactions">
              <P>The complete interaction flow from spawn to memory:</P>

              <CodeBlock
                language="text"
                code={`NTM spawns agents --> Agents read AGENTS.md
                  --> Agents register with Agent Mail
                  --> Agents query bv for task priority
                  --> Agents claim beads via br
                  --> Agents reserve files via Agent Mail
                  --> Agents implement and test
                  --> UBS scans for bugs
                  --> Agents commit and push
                  --> CASS indexes the session
                  --> CM distills procedural memory
                  --> Next cycle is better`}
              />
            </SubSection>

            <SubSection title="The VPS Environment">
              <DataTable
                headers={["Aspect", "Value"]}
                rows={[
                  ["User", "ubuntu"],
                  ["Shell", "zsh (with oh-my-zsh + powerlevel10k)"],
                  ["Workspace", "/data/projects"],
                  ["Sudo", "Passwordless (vibe mode)"],
                  ["Tmux prefix", "Ctrl-a"],
                ]}
              />

              <P>
                Use <code>acfs newproj</code> to bootstrap a project with full tooling:
              </P>

              <CodeBlock
                language="bash"
                code={`acfs newproj myproject --interactive

# Creates:
# myproject/
# ├── .git/        # Git repository initialized
# ├── .beads/      # Local issue tracking (br)
# ├── .claude/     # Claude Code settings
# ├── AGENTS.md    # Instructions for AI agents
# └── .gitignore   # Standard ignores`}
              />
            </SubSection>

            <SubSection title="The Incremental Onboarding Path">
              <P>For beginners who find the full system overwhelming:</P>

              <NumberedList
                items={[
                  <Fragment key="start-core-trio">
                    <strong>Start with:</strong> Agent Mail + Beads (br) + Beads Viewer (bv). This
                    core trio captures most of the value.
                  </Fragment>,
                  <Fragment key="add-ubs">
                    <strong>Then add:</strong> UBS for bug hunting
                  </Fragment>,
                  <Fragment key="add-dcg">
                    <strong>Then add:</strong> DCG for destructive command protection
                  </Fragment>,
                  <Fragment key="add-cass">
                    <strong>Then add:</strong> CASS for session history
                  </Fragment>,
                  <Fragment key="add-cm">
                    <strong>Then add:</strong> CM (CASS Memory) for codifying lessons into
                    procedural memory
                  </Fragment>,
                ]}
              />

              <TipBox variant="warning">
                <strong>Common beginner mistakes:</strong> Making a hasty plan all at once instead
                of the multi-model iterative process. Trying to convert the plan to beads in a
                single pass. Stopping after a round or two of polishing instead of the 8-10 I
                usually run. &quot;Well, of course the
                project is going to suck and be a buggy mess if you do that.&quot;
              </TipBox>
            </SubSection>

            <SubSection title="Scale Observations from Real Projects">
              <DataTable
                headers={["Project", "Beads", "Plan Lines", "Agents", "Time to MVP"]}
                rows={[
                  ["CASS Memory System", "347+", "5,500", "~25", "~5 hours"],
                  ["FrankenSQLite", "Hundreds", "Large spec", "Many parallel", "Multi-session"],
                  ["Frankensearch", "122+ (3 epics)", "—", "Multiple", "Multi-session"],
                  ["Apollobot", "26", "—", "Single session", "2-3 polish rounds"],
                ]}
              />
            </SubSection>

            <SubSection title="Patterns That Work">
              <BulletList
                items={[
                  <Fragment key="funnel">
                    <strong>The &quot;30 to 5 to 15&quot; funnel:</strong> Having agents brainstorm
                    30 ideas, winnow to 5, and then add the next best 10 gives much better results
                    than asking for 5 directly.
                  </Fragment>,
                  <Fragment key="parallel-subagents">
                    <strong>Parallel subagents for bulk bead operations:</strong> Creating dozens of
                    beads is faster when dispatched to parallel subagents, each handling a subset.
                  </Fragment>,
                  <Fragment key="staggered-starts">
                    <strong>Staggered agent starts:</strong> Staggering launches according to
                    observed readiness, and confirming each agent claims work before adding more,
                    avoids the thundering herd problem.
                  </Fragment>,
                  <Fragment key="one-git-agent">
                    <strong>One agent for git operations:</strong> Designating one agent to handle
                    all commits prevents merge conflicts and produces coherent commit messages.
                  </Fragment>,
                ]}
              />
            </SubSection>

            <SubSection title="Anti-Patterns to Avoid">
              <BulletList
                items={[
                  <Fragment key="single-pass-beads">
                    <strong>Single-pass beads:</strong> First-draft beads are never optimal. Always
                    do at least 4-5 polishing passes.
                  </Fragment>,
                  <Fragment key="skipping-validation">
                    <strong>Skipping plan-to-bead validation:</strong> Not cross-referencing beads
                    against the plan leads to missing features discovered only during
                    implementation.
                  </Fragment>,
                  <Fragment key="communication-purgatory">
                    <strong>Communication purgatory:</strong> Agents spending more time messaging
                    each other than coding. Be proactive about starting work.
                  </Fragment>,
                  <Fragment key="long-reservations">
                    <strong>Holding reservations too long:</strong> File reservations with long TTLs
                    block other agents unnecessarily. Reserve, edit, commit, release.
                  </Fragment>,
                  <Fragment key="no-reread-agents-md">
                    <strong>Not re-reading AGENTS.md after compaction:</strong> Context compaction
                    loses nuance, so the re-read is mandatory.
                  </Fragment>,
                ]}
              />
            </SubSection>

            <SubSection title="Supporting Infrastructure">
              <DataTable
                headers={["Component", "Purpose"]}
                rows={[
                  ["AGENTS.md", "Per-project configuration teaching agents about tools and rules"],
                  [
                    "Your earlier projects",
                    "Their plans, AGENTS.md files, and READMEs are the templates for the next project",
                  ],
                  ["Markdown plan files", "Source-of-truth planning documents"],
                  [
                    "acfs newproj",
                    "Bootstraps projects with full tooling (.git, .beads, .claude, AGENTS.md)",
                  ],
                  ["acfs doctor", "Single command to verify entire installation"],
                  [
                    "NTM command palette",
                    "Battle-tested prompt library accessible via ntm palette",
                  ],
                  [
                    "Agent Skills (SKILL.md)",
                    "Most core tools have a dedicated skill for automated workflows",
                  ],
                ]}
              />
            </SubSection>

            <SubSection title="The Skills Ecosystem">
              <P>
                The term &quot;skill&quot; confuses people at first. A skill is a reusable
                instruction pack for an agent. In Claude Code terms, that
                usually means a <code>SKILL.md</code> file plus optional references, scripts, or
                templates that tell the agent how to use a tool, how to execute a methodology, what
                pitfalls to avoid, and what a good result looks like. A good skill is closer to
                executable know-how than to ordinary prose documentation. Claude Code loads skills
                from <code>~/.claude/skills/&lt;name&gt;/SKILL.md</code> or a project&apos;s{" "}
                <code>.claude/skills/</code>; Codex reads the same format from{" "}
                <code>~/.agents/skills/</code>.
              </P>

              <P>
                A tool changes what the agent <em>can</em> do. A skill changes how <em>well</em> the
                agent knows how to do it. The same model with and without a good skill often behaves
                like two different agents.
              </P>

              <P>
                Most core Flywheel tools (br, bv, ntm, Agent Mail, cass, cm, ubs, dcg, slb, rch, and
                others) have a corresponding agent skill that encodes best practices and automates
                common workflows. Many tool repos ship that skill as a <code>SKILL.md</code> next to
                the code, and some installers (for example br, rch, and pt) put it in place
                automatically, so users often benefit without having to think about &quot;skill
                management&quot; explicitly. There is also a broader public skills
                collection at{" "}
                <a
                  href="https://github.com/Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations/tree/main/skills"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  GitHub
                </a>
                .
              </P>

              <P>
                The prompt side has a similar split.{" "}
                <a
                  href="https://jeffreysprompts.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  jeffreysprompts.com
                </a>{" "}
                has a large free section and is open source at{" "}
                <a
                  href="https://github.com/Dicklesworthstone/jeffreysprompts.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  GitHub
                </a>
                . It also has a paid Pro tier with additional prompts, and an open-source CLI called{" "}
                <code>jfp</code> for searching, copying, and exporting prompts (Pro adds sync,
                collections, and premium packs). For a larger paid library of skills, see{" "}
                <a
                  href="https://jeffreys-skills.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  jeffreys-skills.md
                </a>
                , a $20/month service with curated skills, new skills added regularly, and a
                dedicated CLI called <code>jsm</code> for managing them (jsm
                installs into both the Claude Code and Codex skill folders; it is not part of the
                default ACFS VPS install).
              </P>

              <P>
                Both paid offerings are still under active development, so expect occasional rough
                edges. Issues get fixed quickly, and feedback is welcome. Check each site&apos;s
                terms and FAQ for refund details.
              </P>

              <P>
                Skills provide the prompts, procedures, anti-pattern guidance, and tool-specific
                workflows directly to agents, which reduces the amount of bespoke prompting a human
                needs to do by hand.
              </P>

              <P>
                That is why this guide carries &quot;Skill for this step&quot; notes throughout.
                Each one names the jeffreys-skills.md skills that package the step it sits beside
                and says what they add beyond the prompts shown. Every method in this guide works
                without them; the skills make each step more thorough and more repeatable.
              </P>

              <SkillNote skills={["choose-the-best-skills-for-me-to-run-in-this-project"]}>
                A good first run in any project. It profiles the repository and its current
                juncture from git, beads, and past agent sessions, scores every skill in the catalog
                against that evidence, and gives each one exactly one row in a ledger, so &quot;the
                rest were considered&quot; is a claim you can check. The output is at most three
                complementary campaigns to run now, with ready-to-paste kickoff prompts. It never
                touches your source.
              </SkillNote>
            </SubSection>

            <SubSection title="Vendor Lock-In: Avoid It">
              <BlockQuote>
                PSA: you should avoid vendor lock-in for agent coding primitives like task
                management (e.g., beads) and agent communication (e.g., MCP Agent Mail) so you can
                use all the agents together, which is more powerful anyway. They want you in a
                walled garden, but it&apos;s 100% unnecessary.
              </BlockQuote>

              <P>
                Beads, Agent Mail, and bv are all CLI tools that work identically regardless of
                which agent invokes them. A Claude Code agent, a Codex agent, and an Antigravity
                agent can all call <code>br ready --json</code> and get the same task list. The
                practical test: could you swap out every Claude Code agent for Codex or Antigravity
                without changing your AGENTS.md, beads, Agent Mail setup, or workflow? If yes,
                you&apos;re vendor-neutral.
              </P>
            </SubSection>

            <SubSection title="Validation Gates">
              <P>
                Each gate below must hold before you move to the next phase. If one fails, drop back
                a phase instead of pushing forward optimistically.
              </P>

              <DataTable
                headers={["Gate", "Must Be True Before Advancing"]}
                rows={VALIDATION_GATES.map((gate) => [...gate])}
              />
            </SubSection>

            <SubSection title="Vibe Mode Aliases">
              <P>
                In vibe mode (the installer default), agents run with full permissions via short
                shell shortcuts. A <code>--mode safe</code> install keeps the same names but drops
                the permission-bypass flags (Antigravity then runs with <code>--sandbox</code>):
              </P>

              <CodeBlock
                language="bash"
                code={`# What the shortcuts run in vibe mode (ACFS defines cc/cod as small shell functions)
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox --search -m gpt-6.2-sol -c model_reasoning_effort=xhigh -c model_reasoning_summary_format=experimental'
alias agy='$HOME/.local/bin/agy-locked'  # pins Gemini 4 Neon (XHigh), permissions, DCG hook
alias gmi='$HOME/.local/bin/agy-locked'  # legacy shortcut: same locked launcher`}
              />

              <P>
                The installer configures these automatically, and DCG is the safety net that makes
                running with full permissions workable.
              </P>
            </SubSection>

            <SubSection title="Cost">
              <P>
                ACFS and the Flywheel tools are open source; model subscriptions, API usage, and
                server capacity are separate choices. A starter setup can use one provider account
                plus a modest VPS, then add capacity only after measured limits justify it. As of{" "}
                {COMPLETE_GUIDE_REVIEWED_ON}, the lead planner, {COMPLETE_GUIDE_MODELS.leadPlanner},
                runs in {COMPLETE_GUIDE_MODELS.leadPlannerSurface} on a Claude subscription.{" "}
                {COMPLETE_GUIDE_MODELS.gptPro} for the plan-review rounds, and the Codex models (
                {COMPLETE_GUIDE_MODELS.openaiPlanner} for competing plans and audits,{" "}
                {COMPLETE_GUIDE_MODELS.codexExecutor} for implementation), are most practical for
                heavy use on{" "}
                <a
                  href="https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] underline underline-offset-4"
                >
                  ChatGPT Pro, whose tiers start at $100/month
                </a>
                , subject to provider terms and abuse guardrails. Before purchasing, check the live{" "}
                <a
                  href="https://chatgpt.com/pricing/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] underline underline-offset-4"
                >
                  OpenAI pricing
                </a>
                ,{" "}
                <a
                  href="https://claude.com/pricing"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] underline underline-offset-4"
                >
                  Claude pricing
                </a>
                , and{" "}
                <a
                  href="https://one.google.com/about/google-ai-plans/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] underline underline-offset-4"
                >
                  Google AI plans
                </a>{" "}
                rather than treating any figure here as permanent.
              </P>

              <P>
                The larger numbers previously quoted here came from a specific high-scale operator
                snapshot: about 20M input tokens, 3.5M output tokens, 2.6M reasoning tokens, 1.15B
                cached-token reads, and a fleet of 22 Claude-capable accounts, 22 ChatGPT Pro
                accounts, and 7 Google-capable accounts. Those figures are illustrative of one
                intensive workflow, not a minimum, forecast, benchmark, or purchasing
                recommendation.
              </P>
            </SubSection>
          </GuideSection>


          {/* ============================================================= */}
          {/* SECTION 10: THE FLYWHEEL EFFECT                                */}
          {/* ============================================================= */}
          <GuideSection id="flywheel">
            <P highlight>
              If you use these tools, workflows, and prompts the way this guide describes, you can
              create excellent software in a couple of days, sometimes in one. I&apos;ve done it a
              bunch of times now and it works, as crazy as that may sound. My GitHub profile is the
              proof: it looks like the output of a team of 100+ developers.
            </P>

            <P>
              It behaves like a flywheel rather than a checklist because each cycle makes the next
              one better:
            </P>

            <BulletList
              items={[
                <Fragment key="planning-compounds">
                  <strong>Planning quality compounds</strong> because you keep reusing prompts,
                  patterns, and reasoning structures that CASS shows have worked.
                </Fragment>,
                <Fragment key="execution-compounds">
                  <strong>Execution quality compounds</strong> because better beads make swarm
                  behavior more deterministic and less dependent on human improvisation.
                </Fragment>,
                <Fragment key="tool-compounds">
                  <strong>Tool quality compounds</strong> because agents use the tools, complain
                  about them, and then help improve them.
                </Fragment>,
                <Fragment key="memory-compounds">
                  <strong>Memory compounds</strong> because the results of one swarm, captured by
                  CASS session search, become training data, rituals, and infrastructure for the
                  next one.
                </Fragment>,
              ]}
            />

            <SubSection title="How the Compounding Actually Works">
              <P>
                <strong>Session N produces raw data.</strong> Each agent harness logs the session,
                and CASS indexes it. <strong>Between sessions, CM distills patterns.</strong>{" "}
                Running <code>cm reflect</code> extracts procedural rules like &quot;always run
                cargo check after modifying Cargo.toml&quot; with confidence scores that decay
                without reinforcement and amplify with repetition.{" "}
                <strong>Session N+1 starts with those patterns loaded.</strong> Running{" "}
                <code>cm context &quot;Building an API&quot;</code> retrieves relevant procedural
                memory. Meanwhile, UBS patterns grow as new bug classes get added, and Agent Mail
                coordination norms get refined in AGENTS.md and skills.
              </P>

              <P>
                The compounding is real but not automatic in the early stages. Run{" "}
                <code>cm hook install</code> so each finished Claude Code session is reflected in
                the background (or run <code>cm reflect</code> yourself), and you still have to
                review the CASS session data and update AGENTS.md with lessons learned. Even done by
                hand, 15 minutes between projects spent reviewing what worked and updating your
                AGENTS.md template pays off on every later project.
              </P>
            </SubSection>

            <SubSection title="Agent Feedback Forms">
              <P>
                Apply the same feedback mechanisms you would use for humans (structured surveys,
                satisfaction ratings, net promoter scores) directly to agents evaluating tools.
                After an agent finishes using a tool in a real project, ask it to fill out a
                structured feedback survey. Then pipe that feedback into another agent working on
                the tool itself. The iteration cycle shrinks from weeks to minutes.
              </P>

              <PromptBlock
                title="Agent Tool Feedback"
                prompt={`Based on your experience with [TOOL] today in this project, how would you rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was it helpful to you? Did it flag a lot of useful things that you would have missed otherwise? Did the issues it flagged have a good signal-to-noise ratio? What did it do well, and what was it bad at? Did you run into any errors or problems while using it?

What changes to [TOOL] would make it work even better for you and be more useful in your development workflow? Would you recommend it to fellow coding agents? How strongly, and why or why not? The more specific you can be, and the more dimensions you can score [TOOL] on, the more helpful it will be for me as I improve it and incorporate your feedback to make [TOOL] even better for you in the future!`}
                where="After an agent finishes using a tool in a real project"
                whyItWorks="Many of the methods we use for people apply directly to agents. 'By robots, for robots.' The prompt produces structured, actionable feedback, and running it across several agents on different kinds of projects gives you a varied sample. One caveat: like the customers who would have asked for a 'faster horse' instead of a car, agents are unreliable judges of features that do not exist yet. The real test comes after implementation, in real use."
              />
            </SubSection>

            <SubSection title="CASS Memory: Three-Layer Architecture">
              <P>
                CM (CASS Memory System) uses three memory layers to turn raw session history into
                operating knowledge:
              </P>

              <CodeBlock
                language="text"
                code={`EPISODIC MEMORY (cass): Raw session logs from all agents
         ↓ cass search
WORKING MEMORY (Diary): Structured session summaries
         ↓ reflect + curate
PROCEDURAL MEMORY (Playbook): Distilled rules with confidence scores`}
              />

              <P>
                Rules have a 90-day confidence half-life (decays without feedback) and a 4x harmful
                multiplier (one mistake counts 4x as much as one success). Rules mature through
                stages: <code>candidate</code> to <code>established</code> to <code>proven</code>.
              </P>

              <CodeBlock
                language="bash"
                code={`cm context "Building an API" --json   # Get relevant memories for a task
cm similar "authentication patterns"  # Find related playbook rules
cm reflect                            # Update procedural memory from recent sessions
cm mark b-8f3a2c --helpful            # Reinforce a useful rule
cm mark b-xyz789 --harmful --reason "Caused regression"  # Flag a bad rule`}
              />

              <P>
                The <code>cm context</code> command is the single most important pre-task ritual.
                Running it at the start of a session gives agents knowledge distilled from every
                previous session that touched similar work.
              </P>

              <SkillNote skills={["cass", "cass-memory"]}>
                <code>/cass</code> teaches agents to mine their own history: the prompt that worked
                last month, the decision and the reasons behind it. It also teaches them to report
                a search that timed out as unknown rather than as nothing found.{" "}
                <code>/cass-memory</code> covers the cm loop above, from the{" "}
                <code>cm context</code> call before a task to the helpful and harmful marks that
                keep the playbook honest.
              </SkillNote>
            </SubSection>

            <SubSection title="Meta-Skill: Skill Refinement via CASS Mining">
              <PromptBlock
                title="Skill Refinement Meta-Skill"
                prompt={`Search CASS for all sessions where agents used the [SKILL] skill. Look for: patterns of confusion, repeated mistakes, steps agents skipped, workarounds they invented, and things they did that weren't in the skill but should be.

Then rewrite the skill to fix every issue you found. Make the happy path obvious, add guardrails for the common mistakes, and incorporate the best workarounds as official steps. Test the rewritten skill against the failure cases from the session logs.`}
                where="Claude Code, targeting any skill with 10+ CASS sessions of usage data"
                whyItWorks="A skill-refiner skill built from this prompt can be refined with its own session data, so it improves along with the skills it refines. After 3-4 cycles, the skill is much more reliable than the original, and each cycle takes less human effort because the meta-skill itself has improved."
              />
            </SubSection>

            <SubSection title="CASS Ritual Detection">
              <P>
                The flywheel&apos;s learning loop depends on mining past sessions to find what
                actually works. CASS supports <Hl>ritual detection</Hl>: finding prompts repeated so
                often that they amount to validated methodology.
              </P>

              <DataTable
                headers={["Repetition Count", "Status", "Action"]}
                rows={[
                  ["count >= 10", "RITUAL", "Validated methodology. Extract into a skill."],
                  ["count 5-9", "Emerging pattern", "Worth investigating further."],
                  ["count < 5", "One-off", "Not generalizable yet."],
                ]}
              />

              <P>
                The mining query (user prompts live at lines 1-3 of session entries;{" "}
                <code>--fields summary</code> trims each hit to path, line, agent, title, score, and ids):
              </P>

              <CodeBlock
                language="bash"
                code={`cass search "*" --workspace /data/projects/PROJECT --json --fields summary --limit 500 \\
  | jq '[.hits[] | select(.line_number <= 3) | .title[0:80]]
        | group_by(.) | map({prompt: .[0], count: length})
        | sort_by(-.count) | map(select(.count >= 5)) | .[0:30]'`}
              />

              <P>
                The prompt library in this guide was found and validated this way, by mining
                hundreds of real sessions.
              </P>

              <SkillNote skills={["operationalizing-expertise", "automating-your-automations"]}>
                <code>/operationalizing-expertise</code> carries ritual detection further. Its
                session-mining track turns behaviors you repeat in cass history into rules of the
                form &quot;when X, do Y because Z,&quot; and its distillation track turns a whole
                methodology into a corpus, a quote bank, a triangulated kernel, an operator library,
                and validators that block a release when they fail.{" "}
                <code>/automating-your-automations</code> applies the same counting to your shell:
                it mines atuin and shell history for multi-step command sequences you keep
                repeating, ranks them by frequency times pain, and builds the winners into a Rust
                CLI or a bash script.
              </SkillNote>
            </SubSection>

            <SubSection title="Why It Works: Layered Context">
              <P>
                The workflow works because it keeps different kinds of context in different layers.
                The <strong>markdown plan</strong> holds whole-system intent and reasoning. The{" "}
                <strong>beads</strong> hold executable task structure and embedded local context.{" "}
                <strong>AGENTS.md</strong> holds operating rules and tool knowledge that must
                survive compaction. The <strong>codebase</strong> holds the implementation itself,
                which is too large to be the primary planning medium.
              </P>
            </SubSection>

            <SubSection title="The Kernel: 9 Invariants">
              <NumberedList
                items={[
                  <Fragment key="global-reasoning">
                    <strong>Global reasoning belongs in plan space.</strong> Do the hardest
                    architectural and product reasoning while the whole project still fits in
                    context.
                  </Fragment>,
                  <Fragment key="comprehensive-plan">
                    <strong>The markdown plan must be comprehensive before coding starts.</strong>{" "}
                    Skeleton-first coding throws away the main advantage of frontier models.
                  </Fragment>,
                  <Fragment key="plan-to-beads-translation">
                    <strong>Plan-to-beads is a distinct translation problem.</strong> A good plan
                    does not automatically produce a good bead graph.
                  </Fragment>,
                  <Fragment key="execution-substrate">
                    <strong>Beads are the execution substrate.</strong> Once good enough, they
                    should carry enough context that agents no longer need the full plan.
                  </Fragment>,
                  <Fragment key="convergence">
                    <strong>Convergence matters more than first drafts.</strong> Plans and beads
                    both improve through repeated polishing until changes become small and
                    corrective.
                  </Fragment>,
                  <Fragment key="fungible-agents">
                    <strong>Swarm agents are fungible.</strong> Coordination must live in artifacts
                    and tools, not in special agents or unstated knowledge.
                  </Fragment>,
                  <Fragment key="survive-crashes">
                    <strong>Coordination must survive crashes and compaction.</strong> AGENTS.md,
                    Agent Mail, bead state, and robot modes exist to keep work moving when sessions
                    die.
                  </Fragment>,
                  <Fragment key="session-history">
                    <strong>Session history is part of the system.</strong> Repeated prompts,
                    failures, and recoveries should be mined via CASS and folded back into tools,
                    skills, and validators.
                  </Fragment>,
                  <Fragment key="not-finish-line">
                    <strong>Implementation is not the finish line.</strong> Review, testing, UBS,
                    and feedback-to-infrastructure loops are part of the core method.
                  </Fragment>,
                ]}
              />
            </SubSection>

            <SubSection title="Time Investment">
              <DataTable
                headers={["Phase", "Typical Duration", "Notes"]}
                rows={[
                  [
                    "Markdown plan (multi-model synthesis + refinement)",
                    "3+ hours for a complex feature",
                    "Feels slow because no code is written, but it pays off in every later phase",
                  ],
                  [
                    "Plan to beads conversion",
                    "Significant; Claude needed 'coaxing and cajoling' for 347 beads",
                    "A 5,500-line plan with hundreds of beads takes sustained effort",
                  ],
                  [
                    "Bead polishing",
                    "2-3 passes per session, multiple sessions",
                    "Agents typically manage 2-3 passes before running out of context window",
                  ],
                  [
                    "Implementation with swarm",
                    "Fast",
                    "CASS Memory System: 11k lines in ~5 hours with 25 agents",
                  ],
                ]}
              />

              <P>
                CASS itself (a complex Rust program used by thousands of people) was made in around
                a week, but I personally only spent a few hours on it. The rest of the time
                was spent by a swarm of agents implementing and polishing it and writing tests.
              </P>
            </SubSection>

            <SubSection title="The Project Is a Foregone Conclusion">
              <BlockQuote>
                Once you have the beads in good shape based on a great markdown plan, I almost view
                the project as a foregone conclusion at that point. The rest is basically mindless
                &quot;machine tending&quot; of your swarm of 5-15 agents.
              </BlockQuote>

              <P>
                The claim sounds bold, but it follows from everything above. If the plan
                is thorough, the beads faithfully encode it with full context and correct
                dependencies, and the agents have a clear AGENTS.md, then implementation becomes a
                mechanical process of agents picking up beads, implementing them, reviewing, and
                moving on.
              </P>

              <P>
                <strong>This is true when:</strong> the plan has actually converged (not just
                become long), the beads are self-contained enough that fresh agents can execute them
                without guessing, the swarm has working coordination/review/testing loops, and the
                human is still tending when flow jams or reality diverges from the plan.
              </P>

              <P>
                <strong>It stops being true when:</strong> architecture is still being invented
                during implementation, the bead graph is thin or missing dependencies, or the swarm
                cannot coordinate because AGENTS.md, Agent Mail, or bv usage is weak. If you find
                yourself doing heavy cognitive work during implementation, pause, go back to bead
                space, and add the missing detail.
              </P>
            </SubSection>

            <SubSection title="V1 Is Not Everything">
              <P>
                A common misconception is that you have to do everything in one shot. In this
                approach, that&apos;s true only for version 1. Once you have a functioning v1,
                adding new features follows the same process: create a super detailed markdown plan
                for the new feature, turn it into beads, and implement.
              </P>
            </SubSection>

            <SubSection title="Tools Must Be Agent-First">
              <BlockQuote>
                Every new dev tool in the year of our lord 2025 should have a robot mode designed
                specifically for agents to use. And it should probably be designed by agents, too.
                And then you iterate based on the feedback of the agents actually using the tool in
                real-world scenarios.
              </BlockQuote>

              <P>
                Every tool ships with a prepared AGENTS.md blurb, because a tool is not complete
                without documentation that agents can consume. Beyond that, the tools themselves
                should be designed by agents, for agents, and iterated on with their feedback.
              </P>

              <BlockQuote>
                I make sure the agents enjoy using them and solicit their feedback to improve the
                tooling. If they don&apos;t like the tools, they won&apos;t use them without
                constant nagging.
              </BlockQuote>

              <SkillNote
                skills={[
                  "agent-ergonomics-and-intuitiveness-maximization-for-cli-tools",
                  "world-class-doctor-mode-for-cli-tools",
                  "mcp-server-design",
                ]}
              >
                The first scores a CLI on how easily an agent can drive it (robot and JSON modes,
                help text, error messages) and then applies the fixes in the tree. The second adds
                or upgrades a <code>doctor</code> subcommand that agents can run safely: idempotent,
                reversible, and backup-aware, with every change routed through a single mutation
                point. The third is a design guide for MCP servers, with Agent Mail among its worked
                examples: tool design, tool documentation, and error handling that agents can use
                reliably.
              </SkillNote>
            </SubSection>

            <SubSection title="Recursive Self-Improvement: The Meta-Skill Pattern">
              <P>
                This is the most advanced concept in the flywheel:{" "}
                <strong>
                  your agent toolchain should improve itself using its own output as fuel.
                </strong>
              </P>

              <P>
                Most developers treat skills and tools as static artifacts. You write a skill,
                agents use it, and if it works well enough, you move on. The recursive approach
                treats every agent session as data for the next version of the skill, so the system
                improves with each cycle.
              </P>

              <P>
                Without recursive improvement, you build a CLI tool, write a Claude Code skill for
                it, and deploy both. Agents use the tool, but they misinterpret certain flags, forget
                to pass required arguments, or use workarounds because the skill&apos;s
                instructions were ambiguous. Every agent that hits the same snag wastes the same
                tokens rediscovering the same workaround, across dozens of agents and hundreds of
                sessions. With recursive improvement, you automatically mine those sessions, find
                the failure patterns, and rewrite the skill to prevent them, so the next wave of
                agents does not hit those snags. The skill then reflects real usage instead of a
                guess about how agents will behave.
              </P>

              <BlockQuote>
                Using skills to improve skills, skills to improve tool use, and then feeding the
                actual experience in the form of session logs (surfaced and searched by my cass tool
                and /cass skill) back into the design skill for improving the tool interface to make
                it more natural and intuitive and powerful for the agents. Then taking that revised
                tool and improving the skill for using that tool, then rinse and repeat.
              </BlockQuote>
            </SubSection>

            <SubSection title="How to Actually Do This (Step by Step)">
              <NumberedList
                items={[
                  <Fragment key="build-baseline">
                    <strong>Build the baseline.</strong> Create a tool. Create a skill for it with a
                    skill-creator workflow (I use a private <code>sc</code> skill;{" "}
                    <code>jsm create &lt;name&gt;</code> scaffolds a <code>SKILL.md</code> template
                    and <code>jsm validate</code> checks it). The first version of the skill will be
                    imperfect. Ship it anyway.
                  </Fragment>,
                  <Fragment key="real-work">
                    <strong>Let agents use it in real work.</strong> Do not test in isolation.
                    Deploy the tool and skill into actual project work where agents are implementing
                    beads, running reviews, doing real tasks. CASS indexes every session the
                    harnesses log.
                  </Fragment>,
                  <Fragment key="mine-sessions">
                    <strong>Mine the sessions.</strong> After 10+ sessions of real usage, search
                    CASS for sessions where agents invoked the tool.
                  </Fragment>,
                  <Fragment key="feed-rewrite">
                    <strong>Feed findings into a rewrite.</strong> Give the session analysis to a
                    fresh agent along with the current skill file. Ask it to rewrite the skill to
                    fix every issue.
                  </Fragment>,
                  <Fragment key="repeat">
                    <strong>Repeat.</strong> The revised skill produces better sessions, which give
                    you better data for the next revision. After 3-4 cycles, the skill is much
                    more reliable than the original.
                  </Fragment>,
                ]}
              />

              <CodeBlock
                language="bash"
                code={`# Step 3: Mine sessions for patterns
cass search "tool_name" --workspace /data/projects/PROJECT --json --limit 100`}
              />

              <P>What to look for in the results:</P>

              <BulletList
                items={[
                  <Fragment key="clarifying-questions">
                    <strong>Clarifying questions:</strong> agents asking &quot;do you mean X or
                    Y?&quot; means the skill was ambiguous
                  </Fragment>,
                  <Fragment key="repeated-mistakes">
                    <strong>Repeated mistakes across different agents:</strong> a systematic gap in
                    the skill&apos;s instructions
                  </Fragment>,
                  <Fragment key="creative-workarounds">
                    <strong>Creative workarounds:</strong> agents inventing their own approach means
                    the skill is missing a useful pattern
                  </Fragment>,
                  <Fragment key="outright-failures">
                    <strong>Outright failures:</strong> the skill directed agents to do something
                    wrong or impossible
                  </Fragment>,
                ]}
              />

              <P>
                The rewriting step can itself be a skill: a meta-skill that takes a skill file plus
                CASS session data as input and produces a better skill file as output. The
                meta-skill can then be refined with its own session data.
              </P>

              <BlockQuote>
                This is the way. Make a skill-refiner meta skill. CASS is unbelievably handy for
                this.
              </BlockQuote>

              <BlockQuote>
                Documentation for this documentation refining tool (so meta -- I should run it on
                itself, like a snake eating its own tail!)
              </BlockQuote>

              <P>
                Each cycle takes less human effort than the previous one because the meta-skill
                itself has improved.
              </P>
            </SubSection>

            <SubSection title="The Four Layers of Recursive Improvement">
              <P>
                The recursive pattern has four layers, each more ambitious than the last. Do not try
                to build all four at once; start simple and add the next layer when you need it.
              </P>

              <RecursiveImprovementViz />
              <IllustrativeDisclosure />

              <NumberedList
                items={[
                  <Fragment key="layer-1-feedback-forms">
                    <strong>
                      Layer 1: Feedback forms after tool use (start here, no infrastructure needed).
                    </strong>{" "}
                    After an agent finishes using a tool, ask it to fill out a structured feedback
                    survey. Feed that to another agent working on the tool itself. This requires
                    nothing beyond two agent sessions and produces immediate improvements.
                  </Fragment>,
                  <Fragment key="layer-2-cass-refinement">
                    <strong>
                      Layer 2: CASS-powered skill refinement (requires session logging).
                    </strong>{" "}
                    Instead of relying on one agent&apos;s opinion, mine session logs to find
                    systematic patterns across many agents. An agent using a tool for the first time
                    might blame itself for a confusing flag; when you see 15 agents all struggling
                    with the same flag, you know the flag is the problem.
                  </Fragment>,
                  <Fragment key="layer-3-generate-work">
                    <strong>
                      Layer 3: Skills that generate work (the system proposes its own improvements).
                    </strong>{" "}
                    The idea-wizard skill examines a project and generates improvement ideas. The
                    optimization skill finds performance bottlenecks. These skills create new beads,
                    which agents implement, which improve the tools, which make the skills more
                    effective. The human&apos;s role shifts from directing specific work to curating
                    which generated ideas are worth pursuing.
                  </Fragment>,
                  <Fragment key="layer-4-bundled-skills">
                    <strong>
                      Layer 4: Skills bundled with tool installers (the skill improves before the
                      user ever sees it).
                    </strong>{" "}
                    Every tool I ship installs a Claude Code skill along with the tool, and that
                    skill was refined through multiple CASS cycles before shipping. When a new user
                    installs the tool, their agents start with every refinement those cycles
                    produced from my own agent sessions.
                  </Fragment>,
                ]}
              />

              <BlockQuote>
                I&apos;m going to start having my tool installers always add a highly optimized
                skill. It makes a massive difference.
              </BlockQuote>

              <SkillNote skills={["installer-workmanship"]}>
                For writing the installer that layer 4 depends on: a production-grade{" "}
                <code>curl | bash</code> one-liner for a CLI tool, including the step that puts the
                tool&apos;s skill in place (from the release tarball, with an inline fallback when
                the download fails).
              </SkillNote>
            </SubSection>

            <SubSection title="Why the Acceleration Compounds">
              <P>
                Most productivity techniques produce linear improvements: you get 10% better each
                cycle, and those gains do not stack. The recursive skill pattern compounds because
                each cycle improves the tools that perform the next cycle.
              </P>

              <P>
                When you improve the extreme-software-optimization skill, every future optimization pass
                across every tool benefits. When you improve the idea-wizard skill, every future
                brainstorming session across every project benefits. When you improve the
                skill-refiner meta-skill, every future skill refinement benefits. The improvements
                multiply rather than add.
              </P>

              <P>
                The tools produced by the recursive loop are the tools that produce the next tools.
                It is the same idea as a compiler that compiles itself, applied to the entire
                agent-driven development workflow.
              </P>

              <BlockQuote>
                I&apos;m going over each tool with my extreme optimization skill and applying insane
                algorithmic lore that Knuth himself probably forgot about already to make things as
                fast as the metal can go in memory-safe Rust.
              </BlockQuote>
            </SubSection>

            <SubSection title="The Hidden Knowledge Extraction">
              <P>
                The recursive loop has a second, subtler benefit. Models have internalized a great
                deal of academic CS literature: obscure
                algorithmic techniques, mathematical proofs, design patterns from papers that only a
                handful of people ever read. Most of this knowledge never surfaces because nobody
                asks for it with enough precision.
              </P>

              <P>
                A skill is how you ask with that precision. Compare:
              </P>

              <BulletList
                items={[
                  <Fragment key="without-skill">
                    <strong>Without a skill:</strong> &quot;Optimize this function.&quot; The agent
                    applies generic improvements like caching, loop unrolling, or reducing
                    allocations. Useful but shallow.
                  </Fragment>,
                  <Fragment key="with-skill">
                    <strong>With the extreme-software-optimization skill:</strong> The skill directs the agent
                    to systematically consider cache-oblivious data structures, SIMD vectorization
                    opportunities, branch-free arithmetic, van Emde Boas layout, fractional
                    cascading, and carry-less multiplication, then benchmark before and after each
                    change. The agent draws on deep knowledge it would not volunteer unprompted.
                  </Fragment>,
                ]}
              />

              <P>
                Without the skill, the model defaults to common patterns. With it, the model reaches
                into the long tail of techniques that most human developers have never encountered.
              </P>

              <BlockQuote>
                The knowledge is just sitting there and the models have it. But you need to know how
                to coax it out of them.
              </BlockQuote>

              <P>
                That is why the recursive loop keeps accelerating instead of plateauing. Each cycle
                of skill refinement fixes bugs in the skill&apos;s instructions and also sharpens
                its ability to draw deeper knowledge out of the model. The optimization skill gets
                better at asking for the right techniques because CASS sessions show which
                techniques produced measurable gains and which were dead ends, and each
                cycle&apos;s results become part of the feedback corpus for the next.
              </P>

              <P>
                Stack enough cycles and the result is code that looks like it was written by someone
                who read every obscure CS paper ever published, because the agent is drawing on that
                literature and the skill tells it which parts to apply.
              </P>

              <P>
                You can also send the agent to the literature directly. In August 2026, looking for
                features that would make my markdown renderer&apos;s PDF and HTML output look more
                polished, I sent:
              </P>

              <PromptBlock
                title="Research the Untapped Frontier"
                prompt={`Think about any world-class, SOTA typography visual optimization research (stuff involving dynamic programming and things like that to get "NEXT LEVEL" quality) that exist but which remain untapped in this project. Do exhaustive research online looking through academic papers and the like.`}
                where="Any agent with web access, on a working project; swap typography for your own domain and name a kind of technique you suspect applies"
                whyItWorks="Most people wouldn't think academic papers have anything to do with nice-looking documents. But if you want your work to look special rather than like every other app, you have to reach the frontier first, and from there you can go further. The prompt asks for what the project doesn't use yet and sends the agent to papers rather than to other apps; naming one kind of technique (dynamic programming here) shows the depth you want."
              />

              <P>For speed, I chain the three optimization skills below in one prompt:</P>

              <PromptBlock
                title="Optimization Loop"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project. Then use /profiling-software-performance and then use /repeatedly-apply-skill at least 30 times sequentially to apply /extreme-software-optimization`}
                where="Any agent on a working codebase; even a cheap flash-class model does well with it"
                whyItWorks="Profiling first points every pass at measured hotspots instead of guesses, and thirty sequential passes go much deeper than one. In August 2026 a nearly free flash model ran it for 20 minutes on that same markdown renderer, whose code frontier models had written, and found a couple of speedups above 5,000x and several of 2x or more."
              />

              <SkillNote
                skills={[
                  "profiling-software-performance",
                  "extreme-software-optimization",
                  "repeatedly-apply-skill",
                ]}
              >
                <code>/extreme-software-optimization</code> is the skill in the example above. It
                works from profiles rather than guesses and proves that each change preserves
                behavior, so pair it with <code>/profiling-software-performance</code>, which finds
                the hotspots for a scenario you define, against a measured baseline. Then wrap the
                pair in <code>/repeatedly-apply-skill</code> to run it many times in a row, going
                deeper each round, since one pass rarely exhausts what an optimization skill can
                find.
              </SkillNote>
            </SubSection>

            <SubSection title="The Operator Library">
              <P>
                These recurring cognitive moves show up throughout real Flywheel sessions. They
                matter more than any single prompt because they say <em>when</em> to apply a move,
                what failure looks like, and what output is expected. Each operator has a prompt
                module you can paste directly into an agent session.
              </P>

              <PromptBlock
                title="Operator 1: Plan-First Expansion"
                prompt={`[OPERATOR: plan-first-expansion]
1) Restate the goals, workflows, and constraints in concrete terms.
2) Expand the markdown plan until the main architectural and user-flow decisions are explicit.
3) Do not start coding until the plan covers testing, failure paths, and sequencing.

Output (required): revised markdown plan with clarified workflows, architecture, and test obligations.`}
                where="When the project still fits in a plan but would explode in size once implemented, multiple architectural paths are plausible, or the desired user workflow is still fuzzy"
                whyItWorks="Prevents skeleton-first coding that locks in bad boundaries, and stops local code exploration from substituting for product reasoning."
              />

              <PromptBlock
                title="Operator 2: Competing-Plan Triangulation"
                prompt={`[OPERATOR: competing-plan-triangulation]
1) Collect independent plans from multiple strong frontier models.
2) Compare them for better ideas, missing concerns, and incompatible assumptions.
3) Integrate only the strongest elements into one revised plan.

Output (required): a single merged markdown plan plus explicit notes on what changed and why.`}
                where="When the project is important enough that one model's biases are dangerous, or early drafts feel plausible but not obviously excellent"
                whyItWorks="Prevents picking the first decent plan and calling it done, or combining every idea indiscriminately instead of filtering for quality."
              />

              <PromptBlock
                title="Operator 3: Overshoot Mismatch Hunt"
                prompt={`[OPERATOR: overshoot-mismatch-hunt]
1) Tell the model it likely missed a large number of issues.
2) Make it compare the artifact against prior feedback or source material again.
3) Require another full pass rather than a small patch list.

Output (required): an expanded list of missed elements, contradictions, and corrections.`}
                where="When review output looks too short or self-satisfied, or a large plan/bead graph still feels under-audited"
                whyItWorks="Asking for 'all problems' gets a shallow pass, because models stop after finding a 'reasonable' number. Claiming there are many more keeps them searching."
              />

              <PromptBlock
                title="Operator 4: Plan-to-Beads Transfer Audit"
                prompt={`[OPERATOR: plan-to-beads-transfer-audit]
1) Walk every important part of the markdown plan and map it to actual beads.
2) Ensure rationale, constraints, and tests are embedded in the bead descriptions.
3) Identify anything in the plan that has no bead or any bead that has no clear plan backing.

Output (required): coverage report plus bead edits that close the gaps.`}
                where="When a large plan is about to be turned into execution tasks, or agents are creating beads quickly and may drop rationale"
                whyItWorks="A good plan does not automatically produce good beads. This keeps the beads from being terse and dependent on tacit knowledge in the markdown file."
              />

              <PromptBlock
                title="Operator 5: Convergence Polish Loop"
                prompt={`[OPERATOR: convergence-polish-loop]
1) Re-run a full critical review in a fresh session.
2) Integrate the fixes and compare the magnitude of changes to the previous round.
3) Stop only when the revisions are small, mostly corrective, and coverage checks keep passing.

Output (required): revised artifact plus a judgment of whether it is still in major-change mode or near convergence.`}
                where="When a plan or bead graph has visible rough edges and the first polishing pass found real issues"
                whyItWorks="Prevents treating the first decent revision as final, or polishing on after returns have gone flat."
              />

              <PromptBlock
                title="Operator 6: Fresh-Eyes Reset"
                prompt={`[OPERATOR: fresh-eyes-reset]
1) Start a fresh session.
2) Reload AGENTS.md and the relevant project context.
3) Ask for a full review of the plan or beads as if seeing them for the first time.

Output (required): a fresh critical pass unconstrained by the prior session's local minima.`}
                where="When the agent has done several long review rounds and suggestions are getting repetitive or shallow"
                whyItWorks="Prevents trusting a tired context window to keep finding subtle flaws, or mistaking context exhaustion for real convergence."
              />

              <PromptBlock
                title="Operator 7: Fungible Swarm Launch"
                prompt={`[OPERATOR: fungible-swarm-launch]
1) Confirm AGENTS.md, bead state, Agent Mail, and bv routing are all ready.
2) Start agents in a staggered way and make them claim work immediately.
3) Keep coordination in beads, reservations, and threads rather than in a special overseer agent.

Output (required): an active swarm with claimed work, low collision risk, and no special-agent bottleneck.`}
                where="When beads are polished enough to execute and multiple agents are about to work in the same repository"
                whyItWorks="Prevents launching before the beads are self-contained, or letting the swarm come to depend on one agent's identity or specialized role."
              />

              <PromptBlock
                title="Operator 8: Feedback-to-Infrastructure Closure"
                prompt={`[OPERATOR: feedback-to-infrastructure-closure]
1) Mine CASS for repeated prompts, breakdowns, and fixes.
2) Distill the useful patterns into skills, AGENTS.md guidance, blurbs, or tool changes.
3) Update the reusable artifact so the next swarm starts from the improved baseline.

Output (required): a revised reusable artifact plus a short note describing the lesson it now encodes.`}
                where="When the same confusion or recovery pattern appears repeatedly in CASS, agents complain about a tool, or a project finishes with clear lessons worth retaining"
                whyItWorks="Keeps lessons from staying anecdotes. This operator turns repeated behavior into ritual, ritual into skill, and skill into infrastructure."
              />
            </SubSection>

            <SubSection title="The Prompt Library">
              <P>
                All prompts in this guide are preserved verbatim from prompts that worked well in
                real sessions (quirks and typos included). For a much larger public prompt
                collection, see{" "}
                <a
                  href="https://jeffreysprompts.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  jeffreysprompts.com
                </a>
                , which has a large free section and is open source at{" "}
                <a
                  href="https://github.com/Dicklesworthstone/jeffreysprompts.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  GitHub
                </a>
                . There is also a paid Pro tier with additional prompts, and an open-source CLI
                called <code>jfp</code> for searching, copying, and exporting prompts. For a larger
                paid library of skills, see{" "}
                <a
                  href="https://jeffreys-skills.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  jeffreys-skills.md
                </a>{" "}
                ($20/month, with a dedicated CLI called <code>jsm</code>). Both paid offerings are
                still under active development.
              </P>
            </SubSection>

            <SubSection title="Common Problems from Real Deployments">
              <BulletList
                items={[
                  <Fragment key="agent-mail-cli">
                    <strong>Agent Mail CLI availability:</strong> Sometimes the binary is not at the
                    expected path; agents fall back to REST API calls.
                  </Fragment>,
                  <Fragment key="context-exhaustion">
                    <strong>Context window exhaustion:</strong> Agents typically manage 2-3
                    polishing passes before needing a fresh session.
                  </Fragment>,
                  <Fragment key="duplicate-beads">
                    <strong>Duplicate beads at scale:</strong> Large bead sets (100+) develop
                    duplicates; dedicated dedup passes are necessary.
                  </Fragment>,
                  <Fragment key="plan-bead-gap">
                    <strong>Plan-bead gap:</strong> The synthesis step sometimes stalls between plan
                    revision and bead creation; always make the move to beads explicit.
                  </Fragment>,
                ]}
              />
            </SubSection>

            <SubSection title="Getting Started">
              <P>
                The complete system is free and 100% open-source. A beginner with a credit card and
                a laptop can visit the wizard, follow step-by-step instructions to rent a VPS, paste
                one <code>curl|bash</code> command, type <code>onboard</code>, and start building
                with AI agents immediately.
              </P>

              <CodeBlock
                language="bash"
                code={`# 1. Rent a supported Ubuntu VPS and connect over SSH
# 2. Install the current main revision (convenient for evaluation).
#    --target-ubuntu=26.04 upgrades a 22.04/24.04 host in place first (30-60 min and a
#    reboot per hop); omit it to keep your current Ubuntu LTS release
${CURRENT_INSTALL_COMMAND}

# Production/reproducible alternative: pin the current ACFS release
${PINNED_INSTALL_COMMAND}

# 3. Reconnect, then learn the workflow
onboard

# 4. Create your first project
acfs newproj my-first-project --interactive

# 5. Spawn agents and start building
ntm spawn my-first-project --cc=2 --cod=1 --agy=1`}
              />

              <P>
                You don&apos;t need to buy a large fleet before learning the workflow. Start with
                one supported agent provider and a VPS sized for your actual workload, use RCH for
                Rust compilation where available, and scale only when observed queueing or provider
                limits justify the expense.
              </P>

              <P>
                Once you get Claude Code up and running on the cloud server, you basically have a
                very competent friend who can help you with any other problems you encounter. And
                I&apos;ll personally answer your questions if you reach out to me on{" "}
                <a
                  href="https://x.com/doodlestein"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  X
                </a>{" "}
                or on{" "}
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors"
                >
                  GitHub issues
                </a>
                .
              </P>

              <P highlight>
                If you want to change the entire direction of your life, the tools to do it are now
                within reach of anyone with a laptop. If you think you might want to, I recommend
                immersing yourself.
              </P>
            </SubSection>
          </GuideSection>

          <GuideFooterCTA
            eyebrow="Next step"
            title={
              <>
                Put the flywheel <em className="italic text-[#FF5500]">to work</em>
              </>
            }
            body={
              <>
                One command resolves {COMPLETE_GUIDE_STACK_TOOL_COUNT} default-enabled stack
                modules, three AI coding agents, and the complete environment. The setup wizard
                walks you through it, with manifest-backed validation at every step.
              </>
            }
            primary={{ href: "/wizard/os-selection", label: "Launch the setup wizard" }}
            secondary={{ href: "/core-flywheel", label: "Read the Core Flywheel" }}
          />
          <GuideColophon reviewedOn={COMPLETE_GUIDE_REVIEWED_ON} sourcePath="complete-guide/page.tsx" />
          </GuideArticle>
        </div>
      </main>
    </ErrorBoundary>
  );
}
