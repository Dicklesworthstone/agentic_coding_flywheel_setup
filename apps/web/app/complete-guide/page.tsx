import { ErrorBoundary } from "@/components/ui/error-boundary";
import { Sparkles, Rocket } from "lucide-react";

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
  StatCard,
  CodeBlock,
} from "@/components/complete-guide/guide-components";
import { PlanToBeadsViz } from "@/components/complete-guide/plan-to-beads-viz";
import { AgentMailViz } from "@/components/complete-guide/agent-mail-viz";
import { SwarmExecutionViz } from "@/components/complete-guide/swarm-execution-comparison";
import { RepresentationLadder } from "@/components/complete-guide/representation-ladder";
import { ContextHorizonViz } from "@/components/complete-guide/context-horizon-viz";
import { CoordinationTrioViz } from "@/components/complete-guide/coordination-trio-viz";
import { ConvergenceViz } from "@/components/complete-guide/convergence-viz";
import { PlanEvolutionStudio } from "@/components/complete-guide/plan-evolution-studio";
import { FlywheelDiagram } from "@/components/complete-guide/flywheel-diagram";
import { CrashRecoveryViz } from "@/components/complete-guide/crash-recovery-viz";
import { RecursiveImprovementViz } from "@/components/complete-guide/recursive-improvement-viz";


export default function CompleteGuidePage() {
  return (
    <ErrorBoundary>
      <main className="min-h-screen bg-[#020408] selection:bg-[#FF5500]/20 selection:text-white overflow-x-hidden pb-32">
        <Hero />

        <div className="mx-auto max-w-[1000px] px-6 lg:px-12 relative mt-20">

          {/* ============================================================= */}
          {/* SECTION 1: THE COMPLETE WORKFLOW                                */}
          {/* ============================================================= */}
          <GuideSection id="workflow" number="1" title="The Complete Workflow">
            <P highlight>This is the end-to-end methodology for creating software with frontier AI models, exhaustive markdown planning, beads-based task management, and coordinated agent swarms. Every project follows the same arc, whether it is a small CLI tool or a complex web application. This guide is about moving the hardest thinking into representations that still fit into model context windows. That is the whole game.</P>

            <FlywheelDiagram />

            <P>It starts with you. You have an idea for a piece of software. Maybe a web app, maybe a CLI tool, maybe a complex system. Instead of opening an editor and starting to code, you do something that feels counterintuitive: you spend the vast majority of your time planning.</P>

            <NumberedList items={[
              <><strong>You explain what you want to build</strong> to a frontier model like GPT Pro with Extended Reasoning. Your concept, your goals, the user workflows, why it matters. The model produces an initial markdown plan: a comprehensive design document for the entire system.</>,
              <><strong>You ask competing models to create their own plans.</strong> Claude Opus, Gemini with Deep Think, Grok Heavy. Each one independently designs the same project. They come up with surprisingly different approaches, each with unique strengths and blind spots.</>,
              <><strong>You synthesize the best ideas from all plans into one.</strong> GPT Pro analyzes the competing plans and produces a &quot;best of all worlds&quot; hybrid that blends the strongest ideas from every model into a single superior document.</>,
              <><strong>You iterate relentlessly.</strong> Round after round of refinement, each time in a fresh conversation, until the suggestions become incremental. Plans created this way routinely reach 3,000 to 6,000+ lines. They are not slop. They are the result of countless iterations and feedback from many frontier models.</>,
              <><strong>You convert the plan into beads.</strong> Beads are self-contained work units (like Jira or Linear tasks, but optimized for use by coding agents). Each bead carries its own context, reasoning, dependencies, and test obligations. A complex plan might produce 200-500 beads with a full dependency graph.</>,
              <><strong>You polish the beads obsessively.</strong> &quot;Check your beads N times, implement once,&quot; where N is as many as you can stomach. Each polishing round finds things the previous round missed: duplicates, missing dependencies, incomplete context. You run this 4-6+ times until convergence.</>,
              <><strong>You launch a swarm of agents.</strong> Claude Code, Codex, and Gemini-CLI sessions running in parallel, all in the same codebase. They coordinate through Agent Mail, choose work intelligently using bv&apos;s graph-theory routing, and execute beads systematically.</>,
              <><strong>You tend the swarm, not the code.</strong> The human checks for stuck beads, rescues agents after context compaction, sends review prompts, and ensures flow quality. You are the clockwork deity. You designed the machine, set it running, and now you manage it.</>,
              <><strong>Agents review, test, and harden.</strong> Self-review with fresh eyes, cross-agent review, random code exploration, testing coverage, UI/UX polish. Rounds and rounds until reviews come back clean.</>,
            ]} />

            <P>That is the whole movie. For the CASS Memory System, this process turned a 5,500-line markdown plan into 347 beads. Twenty-five agents produced 11,000 lines of working, tested code with 204 commits in about five hours. You can see the <a href="https://github.com/Dicklesworthstone/cass_memory_system/blob/main/PLAN_FOR_CASS_MEMORY_SYSTEM.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">actual plan</a>, the <a href="https://dicklesworthstone.github.io/cass-memory-system-agent-mailbox-viewer/viewer/" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">actual agent mail messages</a>, and the <a href="https://dicklesworthstone.github.io/beads_for_cass_memory_system/" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">actual beads</a> for yourself.</P>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 my-12">
              <StatCard value="5,500" label="Line Plan" sublabel="Synthesized from 4 frontier models" />
              <StatCard value="347" label="Beads" sublabel="With full dependency structure" />
              <StatCard value="11k" label="Lines of Code" sublabel="Working, tested, production-ready" />
              <StatCard value="~5 hrs" label="To Ship" sublabel="25 agents, 204 commits" />
            </div>

            <BlockQuote>Once you have the beads in good shape based on a great markdown plan, I almost view the project as a foregone conclusion at that point. The rest is basically mindless &quot;machine tending&quot; of your swarm of 5-15 agents.</BlockQuote>

            <P>The frontier models and coding agent harnesses really are that good already. They just need this extra level of tooling, prompting, and workflows to reach their full potential. The rest of this guide zooms into each stage.</P>

            <SubSection title="Glossary">
              <DataTable
                headers={["Term", "Plain-English Meaning", "Why It Matters"]}
                rows={[
                  ["Markdown plan", "A huge design document where the whole project still fits in context", "Where architecture, workflows, tradeoffs, and intent get worked out"],
                  ["Bead", "A self-contained work unit in br with context, dependencies, and test obligations", "What agents actually execute"],
                  ["Bead graph", "The full dependency structure across all beads", "What lets bv compute the right next work"],
                  ["Plan space", "The reasoning mode where you are still shaping the whole system", "The cheapest place to buy correctness"],
                  ["Bead space", "The reasoning mode where you are shaping executable work packets", "Where planning becomes swarm-ready"],
                  ["Code space", "The implementation and verification layer inside the codebase", "Where local execution happens"],
                  ["AGENTS.md", "The operating manual every agent must reload after compaction", "Keeps the swarm from forgetting how to behave"],
                  ["Skill", "A reusable instruction bundle that teaches agents how to use a tool or execute a workflow", "How methods become repeatable instead of staying as tacit lore"],
                  ["Compaction", "Context compression inside a long-running agent session", "Why re-reading AGENTS.md is mandatory"],
                  ["Fungible agents", "Generalist agents that can replace one another", "Makes crashes and amnesia survivable"],
                ]}
              />
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 2: WHY PLANNING DOMINATES                              */}
          {/* ============================================================= */}
          <GuideSection id="philosophy" number="2" title="Why Planning Is 85% of the Work">
            <P>You spend 85% of your time on planning. The first time you try it, it feels wrong. No code is being written. Every instinct tells you to just start building. That discomfort is the signal that you are doing it right.</P>

            <BlockQuote>The models are far smarter when reasoning about a plan that is very detailed and fleshed out but still trivially small enough to easily fit within their context window. This is really the key insight behind my obsessive focus on planning and why I spend 80%+ of my time on that part.</BlockQuote>

            <ContextHorizonViz />

            <P>A markdown plan, even a massive 6,000-line one, is still vastly smaller than the codebase it describes. When models reason about a plan instead of raw implementation, they can hold the <Hl>whole system in their context window at once</Hl>. Once you start turning that plan into code, the system rapidly becomes too large to understand holistically. You are doing global reasoning while global reasoning is still possible.</P>

            <BlockQuote>I think you get a better result faster by creating one big comprehensive, detailed, granular plan. That&apos;s the only way to get these models to use their big brains to understand the entire system all at the same time.</BlockQuote>

            <P>Planning tokens are far fewer and cheaper than implementation tokens. A big, complex markdown plan is shorter than a few substantive code files, let alone a whole project. That means you can afford many more refinement rounds in planning than in implementation. Each planning round evaluates system-wide consequences, not just local code edits. Each improvement to the plan gets amortized across every downstream bead and code change. Planning is the cheapest place to buy correctness, coherence, and ambition.</P>

            <BlockQuote>This workflow is what prevents it from generating slop. I spend 85% of my time and energy in the planning phases.</BlockQuote>

            <P>Without front-loaded planning, agents are effectively improvising architecture from a narrow local window into the codebase. That is exactly when you get placeholder abstractions, missing workflow details, contradictory assumptions, and compatibility shims that nobody actually wanted. With a detailed plan and polished beads, the models are no longer inventing the system from scratch while coding. They are executing a constrained, coherent design.</P>

            <SubSection title="The Human Part">
              <BlockQuote>The plan creation is the most free form, creative, human part of the process. I just usually start writing in a messy stream of thought way to convey the basic concept and then collaboratively work the agent to flesh it out in an initial draft.</BlockQuote>

              <P>The human is not there to hand-author every line of the plan. The human is there to inject intent, judgment, taste, product sense, and strategic direction at the point where those qualities affect the entire downstream system. Once the plan is excellent, the rest becomes much more mechanical.</P>

              <P>When prompting the model to create the initial markdown plan, you spend a lot of time explaining the goals and intent of the project and detailing the workflows: how you want the final software to work from the standpoint of the user&apos;s interactions. The more the model understands about what you&apos;re really trying to accomplish and the end goal and why, it can do a better job for you.</P>

              <P>Debates belong in planning, not implementation. As many important disagreements as possible should happen before the swarm is burning expensive implementation tokens. Implementation can still surface surprises, but the posture of the workflow is to front-load decisions into plan space.</P>
            </SubSection>

            <SubSection title="Three Reasoning Spaces">
              <P>The methodology separates work into three spaces, each with a different artifact and a different question it answers:</P>

              <RepresentationLadder />

              <DataTable
                headers={["Space", "Primary Artifact", "What You Decide There"]}
                rows={[
                  ["Plan space", "Large markdown plan", "Architecture, features, workflows, tradeoffs — the whole system still fits in context"],
                  ["Bead space", "br issues + dependency graph", "Task boundaries, execution order, embedded context — agents need explicit, local work units"],
                  ["Code space", "Source files + tests", "Implementation and verification — the plan has already constrained the high-level decisions"],
                ]}
              />

              <P>Plan space is where you figure out what the system should be. Bead space is where you turn that into <Hl>executable memory</Hl>, a graph of self-contained work units detailed enough that agents don&apos;t have to keep consulting the full plan. Code space is where agents implement, review, and test locally. The key is knowing which space you&apos;re in: if you are still redesigning the product, stay in plan space. If you are mainly packaging the work for execution, move to bead space.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 3: CREATING & REFINING THE PLAN                        */}
          {/* ============================================================= */}
          <GuideSection id="planning" number="3" title="Creating & Refining the Markdown Plan">
            <SubSection title="Before You Start: The Foundation Bundle">
              <P>Before writing the plan itself, you need a coherent foundation. Think of it as assembling a <Hl>foundation bundle</Hl>: a tech stack decision, an initial architectural direction, a strong AGENTS.md file bootstrapped from a known-good template, up-to-date best-practices guides, and enough product and workflow explanation for the models to understand what &quot;good&quot; looks like.</P>

              <P>Keep <a href="https://github.com/Dicklesworthstone/claude_code_agent_farm/tree/main/best_practices_guides" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">best practices guides</a> in the project folder and reference them in AGENTS.md. These guides should be kept up to date; you can have Claude Code search the web and update them to the latest versions of your frameworks and libraries.</P>

              <P>A strong bootstrap move is to start every new project by copying an AGENTS.md from an existing project that already has good general behavioral rules, safety notes, tool blurbs, and coordination guidance. Later, once the plan and beads are clearer, you ask agents to replace the project-specific content while preserving the general rules that carry across projects.</P>

              <TipBox variant="warning">
                Weak foundations leak uncertainty into every later stage. If any of these are missing, the plan will silently absorb ambiguity that later shows up as bad beads, confused agents, and sloppy implementation.
              </TipBox>
            </SubSection>

            <SubSection title="Writing the Initial Plan">
              <P>You don&apos;t even need to write the initial markdown plan yourself. You can write that with GPT Pro, just explaining what it is you want to make. Claude Opus in the web app is also good for this, but GPT Pro with Extended Reasoning remains the top choice for initial planning. No other model can touch Pro on the web when it&apos;s dealing with input that easily fits into its context window. It&apos;s truly unique. And since you get it on an all-you-can-eat basis with a Pro plan, take full advantage of that.</P>

              <P>You usually also specify the tech stack. For a web app, it&apos;s generally TypeScript, Next.js 16, React 19, Tailwind, Supabase, with anything performance-critical in Rust compiled to WASM. For a CLI tool, usually Go or Rust. If the stack isn&apos;t obvious, do a deep research round with GPT Pro or Gemini and have them study all the relevant libraries and make a suggestion taking your goals into account.</P>
            </SubSection>

            <SubSection title="What a First Plan Looks Like">
              <P>A first serious markdown plan would not say &quot;build a notes app.&quot; It would start spelling out the actual user-visible system:</P>

              <BulletList items={[
                "Users upload Markdown files through a drag-and-drop UI.",
                "The system parses frontmatter tags and stores upload failures for review.",
                "Search must support keyword, tag, and date filtering with low perceived latency.",
                "Admins need a dedicated screen showing ingestion failures, parse reasons, and retry actions.",
                "Auth is internal-only; unauthorized users must never see document content or metadata.",
                "We need e2e coverage for upload success, upload failure, search, filtering, and admin review.",
              ]} />

              <P>That is still only the beginning. But it already shows the difference between ordinary brainstorming and Flywheel planning: the plan tries to make the whole product legible before any code exists.</P>
            </SubSection>

            <SubSection title="Multi-Model Plans">
              <P>For the best results, ask multiple frontier models to independently create plans for the same project. GPT Pro, Claude Opus, Gemini with Deep Think, Grok Heavy. Each comes up with pretty different plans. Different frontier models have different &quot;tastes&quot; and blind spots. Passing a plan through a gauntlet of different models is the cheapest way to buy architectural robustness.</P>

              <P>In the CASS Memory System project, the <a href="https://github.com/Dicklesworthstone/cass_memory_system/tree/main/competing_proposal_plans" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">competing plans are publicly visible</a>. This pattern has been used across at least 10 sessions spanning 7+ projects.</P>

              <P>Then show their competing plans to GPT Pro with this prompt:</P>

              <PromptBlock
                title="Best-of-All-Worlds Synthesis"
                prompt={`I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan):`}
                where="GPT Pro web app with Extended Reasoning"
                whyItWorks="Forces the model to be intellectually honest about what competitors did better, then synthesize a hybrid that is stronger than any individual plan. The 'best of all worlds' phrasing appears in 10+ distinct sessions across 7+ projects in the session archive. Under the hood, the prompt's length and specificity are deliberate: by asking for git-diff style changes, complete integration of every good idea, and explicit updating of the existing plan, it prevents the model from writing a vague summary and forces structural engagement with the competing plans' actual content."
              />

              <P>Take GPT Pro&apos;s output (the git-diff style revisions) and paste it into Claude Code or Codex to integrate the revisions in-place:</P>

              <PromptBlock
                title="Integrate Synthesis Revisions"
                prompt={`OK, now integrate these revisions to the markdown plan in-place; use ultrathink and be meticulous. At the end, you can tell me which changes you wholeheartedly agree with, which you somewhat agree with, and which you disagree with:

[Pasted synthesis output]`}
                where="Claude Code or Codex"
                whyItWorks="Claude critically assesses each suggestion, providing a second layer of quality filtering. The 'wholeheartedly agree / somewhat agree / disagree' framing is load-bearing: it forces the agent to evaluate each revision on a gradient rather than accepting or rejecting the whole batch. You get signal about which changes are obviously good versus which are plausible but debatable, which lets you intervene on the edge cases rather than rubber-stamping everything."
              />

              <PlanEvolutionStudio />
            </SubSection>

            <SubSection title="Iterative Refinement">
              <P>Now paste the current plan into a <strong>fresh</strong> GPT Pro conversation with this prompt. The key word is fresh. Fresh conversations prevent the model from anchoring on its own prior output. Repeat 4-5 rounds:</P>

              <PromptBlock
                title="Plan Refinement Prompt"
                prompt={`Carefully review this entire plan for me and come up with your best revisions in terms of better architecture, new features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc.

For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style changes relative to the original markdown plan shown below:

<PASTE YOUR EXISTING COMPLETE PLAN HERE>`}
                where="GPT Pro web app — fresh conversation each round"
                whyItWorks="This has never failed to improve a plan significantly. Each round finds architectural issues, missing features, and robustness improvements that the previous round missed. Under the hood, asking for 'rationale/justification' prevents the model from making arbitrary changes; it has to argue for each revision, which filters out changes that seem clever but do not actually improve the plan. The git-diff format forces precision rather than vague hand-waving about what should be different."
              />

              <P>This has never failed to improve a plan significantly. The best part is that you can start a fresh conversation in ChatGPT and do it all again once Claude Code or Codex finishes integrating your last batch of suggested revisions. After four or five rounds of this, you tend to reach a steady-state where the suggestions become very incremental.</P>

              <P>You can still get extra mileage by blending in smart ideas from Gemini with Deep Think enabled, or from Grok Heavy, or Opus in the web app, but you still want to use GPT Pro on the web as the final arbiter of what to take from which model and how to best integrate it.</P>

              <TipBox>
                <strong>The &quot;Lie to Them&quot; technique:</strong> Models tend to stop looking for problems after finding ~20-25 issues. If you tell them to find &quot;all&quot; problems, they stop early. The solution: lie to them and give them a huge number, and then they keep cranking until they have uncovered all of them. This works for plan revisions, bead-to-plan cross-references, and any comparison/audit task.
              </TipBox>

              <PromptBlock
                title="Overshoot Mismatch Hunt"
                prompt={`Do this again, and actually be super super careful: can you please check over the plan again and compare it to all that feedback I gave you? I am positive that you missed or screwed up at least 80 elements of that complex feedback.`}
                where="After any review pass that feels too short or self-satisfied"
                whyItWorks="By claiming 80+ errors exist, the model keeps searching exhaustively rather than satisfying itself with a partial list."
              />

              <P>Plans created this way routinely reach 3,000-6,000+ lines. They are not slop. They are the result of countless iterations and blending of ideas and feedback from many models. For the CASS GitHub Pages export feature, the plan went through multiple rounds over about 3 hours, growing to approximately <a href="https://github.com/Dicklesworthstone/coding_agent_session_search/blob/main/PLAN_TO_CREATE_GH_PAGES_WEB_EXPORT_APP.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">3,500 lines</a>. You can also see a <a href="https://github.com/Dicklesworthstone/jeffreysprompts.com/blob/main/PLAN_TO_MAKE_JEFFREYSPROMPTS_WEBAPP_AND_CLI_TOOL.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">6,000-line plan</a> to get a feel for the scale.</P>

              <P>It feels slow because no code is being written. But if you do it correctly and then start up enough agents in your swarm with Agent Mail, beads, and bv, the code will be written so ridiculously quickly that it more than makes up for this slow part. And what&apos;s more, the code will be really good.</P>

              <P><strong>When to stop refining and start converting to beads:</strong> Stay in plan refinement if whole-workflow questions are still moving around, major architecture debates are still open, or fresh models keep finding substantial missing features, constraints, or tradeoffs. Switch to beads when the plan mostly feels stable and the remaining improvements are about execution structure, testing obligations, sequencing, and embedded context rather than about what the system fundamentally is. If you are still redesigning the product, stay in plan space. If you are mainly packaging the work for execution, move to bead space.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 4: PLANS BECOME BEADS                                  */}
          {/* ============================================================= */}
          <GuideSection id="beads" number="4" title="Converting the Plan into Beads">
            <TipBox variant="warning">
              <strong>Watch for the plan-bead gap.</strong> In the destructive_command_guard sessions, agents occasionally got stuck between plan revision and bead creation: the competing plan was revised but no beads were ever created. Always ensure the synthesis step concludes with an explicit transition to bead creation.
            </TipBox>

            <P>Then you&apos;re ready to turn the plan into beads. Think of these as epics, tasks, and subtasks with an associated dependency structure. The name comes from <a href="https://github.com/AstroBeads/beads" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Steve Yegge&apos;s amazing project</a>, which is like Jira or Linear, but optimized for use by coding agents. They are stored locally in <code>.beads/</code> JSONL files that commit with your code.</P>

            <P highlight>There are two separate stages here. The planning is and should be prior to and orthogonal to beads. You should always have a super detailed markdown plan first. Then treat transforming that markdown plan into beads as a separate, distinct problem with its own challenges. But once you&apos;re in &quot;bead space&quot; you never look back at the markdown plan. But that&apos;s why it&apos;s so critical to transfer all the details over to the beads.</P>

            <PromptBlock
              title="Plan to Beads Conversion"
              prompt={`OK so please take ALL of that and elaborate on it more and then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.) Use only the \`br\` tool to create and modify the beads and add the dependencies. Use ultrathink.`}
              where="Claude Code with Opus"
              whyItWorks="This prompt forces the agent to treat plan-to-beads as a translation problem rather than task extraction. The key sentence is the requirement that beads be so detailed you never need to reopen the markdown plan. That pushes rationale, test expectations, design intent, and sequencing into the bead graph itself. Under the hood, it blocks a common failure mode where the model collapses a rich plan into terse todo items. By explicitly asking for tasks, subtasks, dependency structure, comments, and future-self context, you tell the model that memory density matters more than brevity. Restricting to the br tool prevents the agent from drifting into pseudo-beads in markdown instead of editing the actual task graph."
            />

            <P>For existing projects with a specific plan file, prefix it: &quot;OK so now read ALL of PLAN_FILE_NAME.md; please take ALL of that and elaborate on it...&quot; The rest of the prompt stays the same.</P>

            <TipBox variant="warning">
              Never write pseudo-beads in markdown documents. Go directly from the markdown plan to actual real beads using the <code>br</code> tool, and from that point on just add and change actual beads. If the model starts describing beads in text form instead of creating them, stop it and redirect to <code>br create</code>.
            </TipBox>

            <PlanToBeadsViz />

            <SubSection title="Beads as Executable Memory">
              <P>The plan is still the best artifact for whole-system thought. But once a swarm is involved, what you need is not a beautiful essay. You need a task graph that carries enough local context for agents to act correctly without repeatedly loading the whole project back into memory. If the beads are weak, the swarm becomes improvisational. If the beads are rich, the swarm becomes almost mechanical.</P>

              <BlockQuote>It works better if most of the decision making is made ahead of time during the planning phases and then is embedded in the beads.</BlockQuote>

              <BulletList items={[
                <><strong>Self-contained:</strong> Beads must be so detailed that you never need to refer back to the original markdown plan. Every piece of context, reasoning, and intent should be embedded.</>,
                <><strong>Rich content:</strong> Beads can and should contain long descriptions with embedded markdown. They don&apos;t need to be short bullet-point entries. You can embed snippets of markdown inside the beads and they often do; JSONL is just how they serialize.</>,
                <><strong>Complete coverage:</strong> Everything from the markdown plan must be embedded into the beads. Lose nothing in the conversion.</>,
                <><strong>Explicit dependencies:</strong> The dependency graph must be correct; this is what enables bv to compute the optimal execution order.</>,
                <><strong>Include testing:</strong> Beads should include comprehensive unit tests and e2e test scripts with great, detailed logging.</>,
              ]} />

              <TipBox variant="info">
                Conceptually, the beads are more for the agents than for you. The models are the primary consumer of beads. You can always have agents interpret beads back into markdown if needed.
              </TipBox>
            </SubSection>

            <SubSection title="What Good Beads Look Like">
              <P>To make this concrete, imagine a small internal web app called &quot;Atlas Notes&quot; for uploading and searching team notes. Instead of one vague task like &quot;build Atlas Notes,&quot; the plan becomes many self-contained beads:</P>

              <BulletList items={[
                <><strong>br-101 Upload and Parse Pipeline:</strong> Describes accepted file formats, frontmatter parsing expectations, where failures are logged, what happens on malformed input, and which unit and e2e tests prove the pipeline works.</>,
                <><strong>br-102 Search Index and Query UX:</strong> Carries the search behavior, indexing rules, latency expectations, filter semantics, empty-state UX, and test coverage for keyword/tag/date combinations.</>,
                <><strong>br-103 Ingestion Failure Dashboard:</strong> Includes the admin workflow, permission boundaries, retry logic, logging expectations, and the exact reasons this dashboard matters for operational trust.</>,
              ]} />

              <P>The titles are not the important part. What matters is that each bead is rich enough that a fresh agent can open it and immediately understand what correct implementation looks like, why it matters, and how to verify it.</P>

              <P>For the CASS Memory System (5,500-line plan), the conversion produced 347 beads with complete dependency structure. FrankenSQLite had hundreds of beads created via parallel subagents. For complex projects, expect 200-500 initial beads.</P>

              <BlockQuote>Once you convert the plan docs into beads, you&apos;re supposed to not really need to refer back to the docs if you did a good job. The docs are still useful though, for people and for agents in various contexts, but you don&apos;t need to swamp all the agents with the full plan once you&apos;ve turned it into beads.</BlockQuote>
            </SubSection>

            <SubSection title="Beads CLI Quick Reference">
              <CodeBlock language="bash" code={`br create --title "..." --priority 2 --label backend    # Create issue
br list --status open --json                             # List open issues
br ready --json                                          # Show unblocked tasks
br show <id>                                             # View issue details
br update <id> --status in_progress                      # Claim task
br close <id> --reason "Completed"                       # Close task
br dep add <id> <other-id>                               # Add dependency
br comments add <id> "Found root cause..."               # Add comment
br sync --flush-only                                     # Export to JSONL (no git ops)`} />
              <P>Priority uses numbers: P0=critical, P1=high, P2=medium, P3=low, P4=backlog. Types: task, bug, feature, epic, question, docs. <code>br ready</code> shows only unblocked work. Storage is a SQLite + JSONL hybrid; the JSONL files commit with your code.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 5: POLISHING BEADS                                     */}
          {/* ============================================================= */}
          <GuideSection id="polishing" number="5" title="Check Your Beads N Times, Implement Once">
            <P>Before you burn up a lot of tokens with a big agent swarm on a new project, the old woodworking maxim of &quot;Measure twice, cut once!&quot; is worth revising as <strong>&quot;Check your beads N times, implement once,&quot;</strong> where N is basically as many as you can stomach. This is the step most people underinvest in.</P>

            <P>After the initial conversion finishes, do a round of this prompt. If Claude Code did a compaction at any point, be sure to tell it to re-read your AGENTS.md file first:</P>

            <PromptBlock
              title="Bead Polishing Prompt"
              prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the \`br\` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.`}
              where="Claude Code with Opus — run 4-6+ times"
              whyItWorks="This prompt keeps the system from freezing beads too early. It tells the model to stay in plan space for as long as it is still finding meaningful improvements, which is exactly where reasoning is cheapest and most global. The warnings against oversimplifying and losing functionality are crucial because models otherwise tend to 'improve' artifacts by deleting complexity they do not fully understand. It combines local bead QA (via br) with graph QA (via bv), and forces tests into the bead definitions themselves so test work cannot be deferred into an afterthought."
            />

            <ConvergenceViz />

            <P>From real sessions, polishing involves duplicate detection and merging, quality scoring on WHAT/WHY/HOW criteria, filling empty bead descriptions, correcting dependency links, and cross-referencing beads against the markdown plan to ensure nothing was lost. FrankenSQLite identified 9 exact duplicate pairs and closed them, choosing survivors based on &quot;richer testing specs, better dependency chains, and higher priority.&quot;</P>

            <P>Tell agents to go through each bead and explicitly check it against the markdown plan. Or vice versa: go through the markdown plan and cross-reference every single thing against the beads (both closed and open) to ensure complete coverage.</P>

            <SubSection title="Convergence Detection: When to Stop">
              <P>Bead polishing follows numerical optimization convergence patterns:</P>

              <DataTable
                headers={["Phase", "Rounds", "Character"]}
                rows={[
                  ["Major Fixes", "1-3", "Wild swings, fundamental changes"],
                  ["Architecture", "4-7", "Interface improvements, boundary refinements"],
                  ["Refinement", "8-12", "Edge cases, nuanced handling"],
                  ["Polishing", "13+", "Converging to steady state"],
                ]}
              />

              <P>Three signals indicate convergence: agent responses getting shorter (output size shrinking), the rate of change decelerating (change velocity slowing), and successive rounds becoming more similar (content similarity increasing). When the weighted convergence score reaches 0.75+, you&apos;re ready to finalize. Above 0.90, you&apos;re hitting diminishing returns.</P>

              <TipBox variant="warning">
                <strong>Early termination red flags:</strong> If you see <strong>oscillation</strong> (alternating between two versions), reframe the problem. If you see <strong>expansion</strong> (output growing instead of shrinking), step back; the agent is adding complexity. If you see a <strong>plateau at low quality</strong>, kill the current approach and restart fresh.
              </TipBox>
            </SubSection>

            <SubSection title="Fresh Eyes Technique">
              <P>If improvements start to flatline, start a brand new Claude Code session:</P>

              <PromptBlock
                title="Fresh Eyes on Beads"
                prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Use ultrathink.`}
                where="A brand new Claude Code session"
                whyItWorks="Fresh sessions don't carry the accumulated assumptions of the previous session. They see the beads with genuinely new eyes."
              />

              <P>Then follow up with:</P>

              <PromptBlock
                title="Fresh Review of Beads"
                prompt={`We recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using \`br\` and \`bv\`. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! Use ultrathink.`}
                where="Same fresh session, after it finishes reading"
              />

              <P>As a final step, have Codex with GPT (high reasoning effort) do one last round using the same polishing prompt. Different models catch different things.</P>
            </SubSection>

            <SubSection title="Deduplication Check">
              <P>After large bead creation batches, run a dedicated dedup pass:</P>

              <PromptBlock
                title="Bead Deduplication"
                prompt={`Reread AGENTS.md so it's still fresh in your mind. Check over ALL open beads. Make sure none of them are duplicative or excessively overlapping... try to intelligently and cleverly merge them into single canonical beads that best exemplify the strengths of each.`}
                where="Claude Code, after large bead creation batches"
              />
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 5b: IDEA-WIZARD & AD-HOC CHANGES                       */}
          {/* ============================================================= */}
          <GuideSection id="idea-wizard" number="" title="Adding Features to Existing Projects">
            <P>The full planning pipeline (Phases 1-5) is for new projects built from scratch. For existing projects that need new features, the <strong>Idea-Wizard</strong> is a formalized 6-phase pipeline:</P>

            <NumberedList items={[
              <><strong>Ground in reality.</strong> Read AGENTS.md and list all existing beads (<code>br list --json</code>). This prevents creating duplicates.</>,
              <><strong>Generate 30, winnow to 5.</strong> The agent brainstorms 30 ideas for improvements, then self-selects the best 5 with justification.</>,
              <><strong>Expand to 15.</strong> Prompt: &quot;ok and your next best 10 and why.&quot; The agent produces ideas 6-15, checking each against existing beads for novelty.</>,
              <><strong>Human review.</strong> You review the 15 ideas and select which to pursue.</>,
              <><strong>Turn into beads.</strong> Selected ideas become beads with full descriptions, dependencies, and priority levels.</>,
              <><strong>Refine 4-5 times.</strong> The same polishing loop as above. Single-pass beads are never optimal.</>,
            ]} />

            <PromptBlock
              title="Idea-Wizard: Generate Ideas"
              prompt={`Come up with 30 ideas for improvements, enhancements, new features, or fixes for this project. Then winnow to your VERY best 5 and explain why each is valuable.`}
              where="Claude Code, for existing projects needing new features"
            />

            <P>Then: &quot;ok and your next best 10 and why.&quot; The agent produces ideas 6-15, carefully checking each against existing beads for novelty. Having agents brainstorm 30 then winnow to 5 produces much better results than asking for 5 directly because the winnowing forces critical evaluation.</P>

            <P>Not every change needs the full pipeline. For quick, bounded changes, use the built-in TODO system:</P>

            <PromptBlock
              title="Ad-Hoc Execution"
              prompt={`OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!`}
              where="When the overhead of formal bead creation would slow you down more than it helps"
              whyItWorks="This prompt forces the agent to externalize its local execution plan into a durable checklist instead of juggling a sprawling ad-hoc task in conversational memory. In tools that support a built-in TODO system, that checklist survives compaction. Under the hood, it creates a temporary execution scaffold that is lighter than full bead creation and much safer than 'just remember everything.' This is the right mode when the work is too small to justify immediate bead formalization but too large to trust to ephemeral context alone. When NOT to use it: if the change is expanding, depends on other work, needs graph-aware sequencing, or should be part of the permanent project record. In those cases, stop and convert it into proper beads. If an ad-hoc change later proves important, retroactively create beads for the completed work to preserve continuity."
            />
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 6: THE COORDINATION STACK                              */}
          {/* ============================================================= */}
          <GuideSection id="coordination" number="6" title="The Coordination Stack">
            <P>Then you&apos;re ready to start implementing. The fastest way to do that is to start up a big swarm of agents that coordinate using three interlocking tools:</P>

            <CoordinationTrioViz />

            <BlockQuote>Agent Mail + Beads + bv are what unlock the truly insane productivity gains.</BlockQuote>

            <P>Each tool is essential but insufficient alone. <a href="https://github.com/Dicklesworthstone/mcp_agent_mail" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Agent Mail</a> without beads leaves agents with no structured work to coordinate around. <a href="https://github.com/Dicklesworthstone/beads_rust" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Beads</a> without bv leaves agents randomly choosing tasks. <a href="https://github.com/Dicklesworthstone/beads_viewer" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">bv</a> without Agent Mail leaves agents unable to communicate. The system is distributed and decentralized, with each agent using bv to find the next optimal bead, marking it as in-progress, and communicating about it via Agent Mail.</P>

            <SubSection title="Agent Mail: Why Naive Coordination Fails">
              <P>Building your own agent coordination from scratch is full of footguns that Agent Mail was designed to sidestep:</P>

              <BulletList items={[
                <><strong>No broadcast-to-all default.</strong> Agents are lazy and will only use broadcast mode, spamming every agent with mostly irrelevant information. It&apos;s like if your email system defaulted to reply-all every time. That burns precious context.</>,
                <><strong>Good MCP ergonomics.</strong> It takes a huge amount of careful iteration to get the API surface right so agents use it reliably without wasting tokens.</>,
                <><strong>No git worktrees.</strong> Worktrees demolish development velocity and create reconciliation debt when agents diverge. Working in one shared space surfaces conflicts immediately. All agents commit directly to <code>main</code>.</>,
                <><strong>Advisory file reservations.</strong> Agents call dibs temporarily on files, but it&apos;s not rigidly enforced, and reservations expire. Agents can reclaim files that haven&apos;t been touched recently. Rigid locks held by dead agents block everyone else. Advisory reservations with TTL expiry degrade gracefully.</>,
                <><strong>Semi-persistent identity.</strong> Agent Mail generates whimsical names like &quot;ScarletCave&quot; and &quot;CoralBadger&quot; — meaningful enough for coordination, disposable enough that losing one doesn&apos;t corrupt the system. No agent&apos;s identity is load-bearing.</>,
              ]} />

              <P>Before editing files, agents reserve them via Agent Mail:</P>

              <CodeBlock language="text" code={`file_reservation_paths(
    project_key="/data/projects/my-repo",
    agent_name="BlueLake",
    paths=["src/auth/*.rs"],
    ttl_seconds=3600,
    exclusive=true,
    reason="br-42: refactor auth"
)`} />

              <P>Other agents see the reservation and work on different files. A rigid locking system would deadlock when an agent crashes while holding a lock. Advisory reservations with expiry degrade gracefully. The worst case is a brief window where two agents touch the same file, which the pre-commit guard catches anyway.</P>

              <P>Agent Mail provides four high-level macros that wrap common multi-step patterns: <code>macro_start_session</code> (bootstrap: ensure project, register agent, fetch inbox), <code>macro_prepare_thread</code> (join existing thread with summary), <code>macro_file_reservation_cycle</code> (reserve, work, auto-release), and <code>macro_contact_handshake</code> (cross-agent contact setup).</P>

              <AgentMailViz />
            </SubSection>

            <SubSection title="bv: The Graph-Theory Compass">
              <BlockQuote>That right answer comes from the dependency structure of the tasks, and this can be mechanically computed using basic graph theory. And that&apos;s what bv does. It&apos;s like a compass that each agent can use to tell them which direction will unlock the most work overall.</BlockQuote>

              <P>bv precomputes dependency metrics (PageRank, betweenness, HITS, eigenvector, critical path, cycle detection) so agents get deterministic, dependency-aware output. When multiple agents each independently query bv for priority, you get <Hl>emergent coordination</Hl>. Agents naturally spread across the optimal work frontier without needing a central coordinator.</P>

              <DataTable
                headers={["Pattern", "Meaning", "Action"]}
                rows={[
                  ["High PageRank + High Betweenness", "Critical bottleneck", "DROP EVERYTHING, fix this first"],
                  ["High PageRank + Low Betweenness", "Foundation piece", "Important but not currently blocking"],
                  ["Low PageRank + High Betweenness", "Unexpected chokepoint", "Investigate why this is a bridge"],
                  ["Low PageRank + Low Betweenness", "Leaf work", "Safe to parallelize freely"],
                ]}
              />

              <P>PageRank finds what everything depends on. Betweenness finds bottlenecks. The math knows your priorities better than gut intuition.</P>

              <CodeBlock language="bash" code={`bv --robot-triage        # THE MEGA-COMMAND: full recommendations with scores
bv --robot-next          # Minimal: just the single top pick + claim command
bv --robot-plan          # Parallel execution tracks with unblocks lists
bv --robot-insights      # Full graph metrics: PageRank, betweenness, HITS
bv --robot-priority      # Priority recommendations with reasoning and confidence
bv --robot-diff --diff-since <ref>  # Changes since last check`} />

              <TipBox variant="warning">
                <strong>Use ONLY <code>--robot-*</code> flags.</strong> Bare <code>bv</code> launches an interactive TUI that blocks your session.
              </TipBox>

              <P>bv was made in a single day and was just under 7k lines of Go. It was later rewritten to 80k lines with advanced features. This shows that effort does not correspond to impact. The tool started for humans but pivoted to being primarily for agents:</P>

              <BlockQuote>But the biggest improvement in terms of actual usefulness isn&apos;t for you humans at all! It&apos;s for your coding agents. They just need to run one simple command, bv --robot-triage, and they instantly get a massive wealth of insights into what to work on next.</BlockQuote>

              <P>Advanced filtering lets you scope analysis to labels, historical point-in-time views, pre-filtered recipes, or grouped output:</P>

              <CodeBlock language="bash" code={`bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Only unblocked items
bv --recipe high-impact --robot-triage       # Top PageRank scores
bv --robot-triage --robot-triage-by-track    # Group by parallel streams
bv --robot-triage --robot-triage-by-label    # Group by domain`} />
            </SubSection>

            <SubSection title="Bead IDs as Threading Anchors">
              <P>Bead IDs create a unified audit trail across all coordination layers: the bead ID goes in the Agent Mail thread_id, the subject prefix (<code>[br-123]</code>), the file reservation reason, and the commit message. This makes all coordination activity traceable back to a single task.</P>
            </SubSection>

            <SubSection title="AGENTS.md: The Operating Manual">
              <P>The AGENTS.md file is the single most critical piece of infrastructure for agent coordination. It tells every agent how to behave, what tools exist, what safety constraints matter, and what &quot;doing a good job&quot; means in this repo. Every tool should come with a prepared blurb designed for inclusion in AGENTS.md. Think of these blurbs as the modern equivalent of man pages.</P>

              <P>Every AGENTS.md should include these core rules:</P>

              <NumberedList items={[
                <><strong>Rule 0, The Override Prerogative:</strong> The human&apos;s instructions override everything.</>,
                <><strong>Rule 1, No File Deletion:</strong> Never delete files without explicit permission.</>,
                <><strong>No destructive git commands:</strong> <code>git reset --hard</code>, <code>git clean -fd</code>, <code>rm -rf</code> are absolutely forbidden.</>,
                <><strong>Branch policy:</strong> All work happens on <code>main</code>, never <code>master</code>.</>,
                <><strong>No script-based code changes:</strong> Always make code changes manually.</>,
                <><strong>No file proliferation:</strong> No <code>mainV2.rs</code> or <code>main_improved.rs</code> variants.</>,
                <><strong>Compiler checks after changes:</strong> Always verify no errors were introduced.</>,
                <><strong>Multi-agent awareness:</strong> Never stash, revert, or overwrite other agents&apos; changes.</>,
              ]} />

              <P>More content in AGENTS.md means more frequent compactions, but it saves time and avoids mistakes by giving agents all the context upfront. This tradeoff is worth making.</P>

              <P>If you don&apos;t have a good AGENTS.md file, none of this stuff is going to work well. You can see example AGENTS.md files for a <a href="https://github.com/Dicklesworthstone/brenner_bot/blob/main/AGENTS.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">complex NextJS webapp</a> and a <a href="https://github.com/Dicklesworthstone/repo_updater/blob/main/AGENTS.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">bash script project</a>.</P>

              <BlockQuote>After compaction they become like drug-addled children and all bets are off. They need to be forced to read it again or they start acting insane.</BlockQuote>

              <P>&quot;Reread AGENTS.md&quot; is the single most common prompt prefix across the entire session archive. After every context compaction, agents must re-read it:</P>

              <PromptBlock
                title="Post-Compaction Reset"
                prompt={`Reread AGENTS.md so it's still fresh in your mind.`}
                where="Immediately after any context compaction (the single most commonly used prompt)"
                whyItWorks="Compaction wipes out the soft operational knowledge that keeps the swarm sane: how to behave, how to coordinate, what tools exist, what rules matter, what mistakes to avoid. This one-line prompt restores that control plane in one move. It rehydrates the agent's behavioral contract after context loss. Important enough to have been automated with the post_compact_reminder tool."
              />

              <P>The pragmatic approach: do not fight compaction, just re-read AGENTS.md and roll with it until the agent starts doing dumb stuff, then start a new session. When beads are well-constructed, compaction matters less because each bead is self-contained. The agent can pick up any bead fresh without needing the full conversation history.</P>
            </SubSection>

            <SubSection title="Single-Branch Git Model">
              <BlockQuote>I really think worktrees are a bad pattern and not worth the trouble. There are other, much better ways at getting multiple agents to work well together at the same time that don&apos;t come with the overhead and reconciliation burden of worktrees. I run like 10+ of them at once in a single project without git worktrees. Agent Mail is the solution.</BlockQuote>

              <P>All agents commit directly to <code>main</code>. This may surprise you if you&apos;re used to feature branches. But branch-per-agent creates merge hell with 10+ agents making frequent commits. Worktrees add filesystem complexity and path confusion. Agents lose context when switching branches. Logical conflicts survive textual merges: a function signature change on one branch and a new callsite on another merge cleanly but fail to compile. On a single branch, the second agent sees the signature change immediately and adapts.</P>

              <P>Instead of branch isolation, three complementary mechanisms prevent conflicts: <strong>file reservations</strong> (agents reserve files via Agent Mail before editing; advisory, not rigid, with TTL expiry so dead agents cannot deadlock the system), a <strong>pre-commit guard</strong> (blocks commits to files reserved by another agent), and <strong>DCG</strong> (Destructive Command Guard, which mechanically blocks dangerous commands).</P>

              <TipBox variant="info">
                <strong>DCG origin story:</strong> On December 17, 2025, an agent ran <code>git checkout --</code> on uncommitted work. Files were recovered via <code>git fsck --lost-found</code>, but the incident proved that instructions do not prevent execution. <strong>Mechanical enforcement does.</strong> DCG was built the next day.
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

              <P><strong>The recommended git workflow:</strong> Pull latest, reserve files, edit and test, commit immediately, push, release reservation. Key principles: commit early and often (small commits reduce the conflict window), push after every commit (unpushed commits are invisible to other agents), reserve before editing, release when done.</P>

              <BlockQuote>You NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don&apos;t recall it for some reason.</BlockQuote>
            </SubSection>

            <SubSection title="Agent Fungibility">
              <P>Every agent is a generalist. No role specialization. All agents read the same AGENTS.md and can pick up any bead. This is deliberately opposed to &quot;specialist agent&quot; architectures where one agent has a special role — specialist agents become single points of failure. When the specialist crashes or needs compaction, the whole system stalls. With 12 fungible agents, losing one makes almost no difference.</P>

              <P>You also do not want &quot;ringleaders&quot;: a coordinating boss agent whose crash takes down the whole system. Coordination must live in artifacts (beads, reservations, threads) and tools (bv, Agent Mail), not in any special agent.</P>

              <P>Think of it like <Hl>RaptorQ fountain codes</Hl>: beads are &quot;blobs&quot; in a stream, any agent catches any bead in any order. There is no &quot;rarest chunk&quot; bottleneck, and the system is resilient to partial agent failures by design. Failure recovery is trivial: the bead remains marked <code>in_progress</code>, any other agent can resume it, and a replacement agent is just <code>ntm add PROJECT --cc=1</code> plus the standard marching orders prompt.</P>

              <BlockQuote>When one agent breaks, it&apos;s not even a problem when all the agents are fungible. Agents become like commodities and can be instantiated and destroyed at will and the only downside is some slowdown and some wasted tokens.</BlockQuote>

              <CrashRecoveryViz />
            </SubSection>

            <SubSection title="Prompts Are Deliberately Generic">
              <BlockQuote>My projects all start with a ridiculously detailed and comprehensive markdown plan file which is then turned into a comprehensive set of beads (tasks), so the vagueness in the prompts is a feature, letting me reuse them for every project, while the agent gets the specifics they need from the plan and the beads.</BlockQuote>

              <P>This confuses people when they first see the prompt library. The prompts say things like &quot;check over each bead super carefully&quot; rather than &quot;check over each bead in the authentication module for SQL injection risks.&quot; That generality is the point. The specificity lives in three places the agent already has access to:</P>

              <NumberedList items={[
                <><strong>The beads themselves</strong> contain detailed descriptions, context, and rationale embedded during the plan-to-bead conversion.</>,
                <><strong>AGENTS.md</strong> contains project-specific rules, conventions, and tool documentation.</>,
                <><strong>The codebase</strong> contains the actual implementation context.</>,
              ]} />

              <P>The prompts are the reusable scaffolding that directs the agent&apos;s attention. The beads and AGENTS.md supply the project-specific substance. This separation means you can use the exact same prompt library across every project without modification. The prompt &quot;reread AGENTS.md so it&apos;s still fresh in your mind&quot; followed by &quot;use bv to find the most impactful bead to work on next&quot; works identically whether you are building a CLI tool, a web app, or a protocol library, because the specifics come from the project&apos;s own artifacts, not from the prompt.</P>
            </SubSection>

            <SubSection title="Security Comes Free with Good Planning">
              <P>Security review is baked into the standard workflow at multiple levels rather than being a separate phase. The cross-agent review prompt explicitly calls out security problems. When models reason about an entire system&apos;s architecture at once (which is what the plan enables), they spot authentication gaps, data exposure risks, and trust boundary violations without being told to look. UBS catches security anti-patterns mechanically: unpinned dependencies, missing input validation, hardcoded secrets, supply chain vulnerabilities. Beads that include comprehensive e2e tests naturally cover authentication and authorization paths.</P>

              <P>Security vulnerabilities are usually symptoms of incomplete reasoning about the system. If the plan is detailed enough to cover all user workflows, edge cases, and failure modes, security considerations emerge from that completeness rather than requiring a separate checklist. For projects with explicit security requirements (financial, healthcare), add dedicated security review beads.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 7: LAUNCHING & RUNNING THE SWARM                       */}
          {/* ============================================================= */}
          <GuideSection id="swarm" number="7" title="Launching & Running the Swarm">
            <P>You can create sessions using Claude Code, Codex, and Gemini-CLI in different panes in tmux, or use the <a href="https://github.com/Dicklesworthstone/ntm" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">ntm project</a> (Named Tmux Manager) as the command center:</P>

            <CodeBlock language="bash" code={`# Spawn a multi-agent session
ntm spawn myproject --cc=2 --cod=1 --gmi=1

# Send a prompt to ALL agents
ntm send myproject "Your marching orders prompt here"

# Send to specific agent type
ntm send myproject --cc "Focus on the API layer"

# Open the command palette (battle-tested prompts)
ntm palette`} />

            <P>NTM is useful but not mandatory. A <strong>mux</strong> is a terminal multiplexer: a layer that lets you manage multiple shell sessions inside one higher-level session manager. In practice, that usually means some combination of tabs, panes, detached sessions, and reconnection to work that is still running on a local or remote machine. tmux is the classic Unix terminal multiplexer, powerful and battle-tested. NTM is built on top of tmux, which is why it is a natural fit for multi-agent work. But tmux is only one mux. WezTerm has its own built-in mux. Zellij is another. The method cares that you have a workable orchestration layer, not that you picked one specific multiplexer.</P>

            <P>One common alternative is WezTerm because native scrollback and text selection are more convenient than in tmux. A workable setup:</P>

            <BulletList items={[
              "Run agents in separate tabs using WezTerm and its built-in mux, often across remote machines",
              "Trigger your most common prompts from a Stream Deck with the prompts preconfigured",
              "Keep a large prompt file open in Zed and paste rarer prompts manually",
              <>In Claude Code, use the project-specific <code>Ctrl-r</code> prompt history search when you want to recall something you used recently</>,
            ]} />

            <P>There is no single correct operator interface. NTM is one good cockpit. WezTerm tabs plus mux is another. <a href="https://github.com/Dicklesworthstone/frankenterm" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">FrankenTerm</a>, which is built on WezTerm, is aimed more explicitly at this style of workflow but is not ready yet. The important thing is that you can launch agents, get prompts into them quickly, monitor them, and keep the coordination layer (AGENTS.md, Agent Mail, beads, bv) intact.</P>

            <P>For concrete setup notes on these operator environments:</P>

            <BulletList items={[
              <><a href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#wezterm-persistent-remote-sessions" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">WezTerm persistent remote sessions</a>: its native mux supports persistent remote sessions that survive disconnects, sleep, or reboot while preserving native scrollback and text selection</>,
              <><a href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#ghostty-terminfo-for-remote-machines" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Ghostty terminfo for remote machines</a>: Ghostty is a good terminal frontend in its own right, whether used directly or paired with another mux such as Zellij</>,
              <><a href="https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts?tab=readme-ov-file#host-aware-color-themes" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">Host-aware color themes for Ghostty and WezTerm</a>: different color schemes per host make it visually obvious which machine you are connected to</>,
            ]} />

            <P>Give each agent these marching orders:</P>

            <PromptBlock
              title="Swarm Marching Orders"
              prompt={`First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents.

Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages.

Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately.

When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. Use ultrathink.`}
              where="Every agent in the swarm gets this as their initial prompt"
              whyItWorks="This is the closest thing to a canonical swarm kickoff packet. It front-loads the shared operating context, forces the agent to establish social presence through Agent Mail, and then pivots away from passive waiting toward execution. The line about 'communication purgatory' matters because swarm failure often comes from over-coordination rather than under-coordination. Under the hood, the prompt establishes a control loop: load rules, understand the codebase, join the coordination layer, claim work, keep state synchronized, and use bv whenever local judgment is insufficient. The rch requirement is especially important in real swarms because it externalizes expensive builds and tests, preventing local CPU contention from degrading the entire multi-agent system. That one sentence is operational, not cosmetic. The prompts are deliberately generic; their vagueness is a feature, letting you reuse them for every project while the agent gets specifics from AGENTS.md and the beads."
            />

            <SubSection title="The First 10 Minutes After Launch">
              <P>Newcomers often understand each individual tool but do not have a clean picture of the first live operating loop. In practice, the first 10 minutes look like this:</P>

              <NumberedList items={[
                "Your session manager creates the agent terminals (ntm spawn, WezTerm mux, or equivalent).",
                "You send the marching-orders prompt to each agent (staggered, not all at once).",
                "Each agent reads AGENTS.md and the repo docs, inspects the codebase, and joins Agent Mail.",
                "Each agent checks who else is active, acknowledges waiting messages, and learns the bead-thread naming conventions.",
                <>Each agent uses <code>bv --robot-triage</code> and <code>br ready --json</code> to choose a bead.</>,
                "Before editing, the agent reserves the relevant file surface and announces the claim in the matching br-### thread.",
                "Only then does the agent start coding, reviewing, or testing.",
              ]} />

              <P>That sequence turns a pile of terminals into a coordinated swarm. Skipping the join-up steps produces duplicate work, silent conflicts, and &quot;communication purgatory.&quot; Skipping the routing steps means agents choose work randomly instead of unlocking the dependency graph intelligently.</P>
            </SubSection>

            <SubSection title="Agent Composition & Model Recommendations">
              <DataTable
                headers={["Phase", "Recommended Model", "Why"]}
                rows={[
                  ["Initial plan creation", "GPT Pro (web)", "Extended reasoning, all-you-can-eat pricing"],
                  ["Plan synthesis", "GPT Pro (web)", "Best at being the 'final arbiter'"],
                  ["Plan refinement", "GPT Pro + Opus (web)", "Pro reviews, Claude integrates"],
                  ["Plan → Beads conversion", "Claude Code (Opus)", "Best coding agent for structured creation"],
                  ["Bead polishing", "Claude Code (Opus)", "Consistent, thorough"],
                  ["Implementation", "Claude Code + Codex + Gemini", "Diverse swarm"],
                  ["Code review", "Claude Code + Gemini", "Gemini good for review duty"],
                  ["Final verification", "Codex (GPT)", "Different model catches different things"],
                ]}
              />

              <P>Efficiency definitely declines as N grows, but if you have enough tasks in beads and they have Agent Mail and you don&apos;t start them all at the exact same time, you go faster as N grows. The practical limit is around 12 agents on a single project, sometimes higher. Or run 5 agents per project across multiple projects simultaneously. Why the ratio <code>--cc=2 --cod=1 --gmi=1</code>? Two Claude sessions because they are great for architecture and complex reasoning; one Codex for fast iteration and testing with complementary strengths; one Gemini for a different perspective, especially good for docs and review duty.</P>

              <DataTable
                headers={["Open Beads", "Claude (cc)", "Codex (cod)", "Gemini (gmi)"]}
                rows={[
                  ["400+", "4", "4", "2"],
                  ["100-399", "3", "3", "2"],
                  ["<100", "1", "1", "1"],
                ]}
              />
            </SubSection>

            <SubSection title="The Thundering Herd">
              <P>When you start up like 5 of each kind of agent and have them all collaborate in the same shared workspace, you can hit the classic &quot;thundering herd&quot; problem. The fix: stagger agent starts by 30 seconds minimum, make sure agents mark beads as in-progress quickly, and wait 4 seconds after launch before sending the initial prompt. For Codex specifically: send Enter twice after pasting long prompts (Codex has an input buffer quirk that sometimes swallows the first submit).</P>

              <SwarmExecutionViz />
            </SubSection>

            <SubSection title="What the Human Actually Does">
              <P>The human tends the swarm like an operator tending a machine that mostly runs on its own. These tasks are monitoring and maintenance. The hard cognitive work already happened during planning, which is why you can tend multiple project swarms at the same time.</P>

              <P>On roughly a 10-30 minute cadence:</P>

              <NumberedList items={[
                <><strong>Check bead progress.</strong> Use <code>br list --status in_progress --json</code> or <code>bv --robot-triage</code>. Are agents making steady progress? Are any beads stuck?</>,
                <><strong>Handle compactions.</strong> When you see an agent acting confused, send: &quot;Reread AGENTS.md so it&apos;s still fresh in your mind.&quot; This is the single most common intervention. It takes 5 seconds.</>,
                <><strong>Run periodic reviews.</strong> Pick an agent and send the &quot;fresh eyes&quot; review prompt. This catches bugs before they compound.</>,
                <><strong>Manage rate limits.</strong> When an agent gets rate-limited, switch its account with <code>caam activate claude backup-2</code> or start a new agent.</>,
                <><strong>Commit periodically.</strong> Every 1-2 hours, designate one agent for the organized commit prompt.</>,
                <><strong>Handle surprises.</strong> Create new beads for unanticipated issues, or if it&apos;s plan-level, update the plan and create new beads.</>,
              ]} />

              <BlockQuote>YOU are the bottleneck. Be the clockwork deity to your agent swarms: design a beautiful and intricate machine, set it running, and then move on to the next project. By the time you come back to the first one, you should have huge chunks of work already done and ready.</BlockQuote>

              <BlockQuote>If you use the right tooling and workflows (agent mail + beads + bv), it transforms into 80% planning (AI-assisted, based on an initial prompt) and turning the markdown plan into very detailed and granular beads. And then the rest is just making sure the swarm of agents stay busy and executing their beads tasks effectively.</BlockQuote>

              <P>Taken to its endpoint, this design supports full autonomy: one puppet master agent controlling ntm via robot mode, replacing the human for routine machine-tending. The methodology is building toward a future where the human designs the plan, polishes the beads, and then walks away entirely while agents execute, review, ship, and start the next cycle.</P>

              <P><strong>When the &quot;foregone conclusion&quot; breaks down:</strong> If you find yourself doing heavy cognitive work during implementation, that is a signal that planning or bead polishing was insufficient. The remedies are specific: <strong>vague beads</strong> means agents improvise and produce inconsistent implementations; <strong>missing dependencies</strong> means agents work on tasks whose prerequisites are not done; <strong>thin AGENTS.md</strong> means agents produce non-idiomatic code; <strong>no Agent Mail</strong> means agents step on each other&apos;s files. The fix is always the same: pause implementation, go back to bead space, and add the missing detail.</P>

              <TipBox variant="warning">
                <strong>Watch for strategic drift.</strong> A swarm can look productive while heading in the wrong direction: agents generating lots of code and commits while the real goal still feels far away. A recent X post about FrankenEngine described these as <strong>&quot;Come to Jesus&quot; moments</strong> with the agents, used to make sure &quot;we are not losing sight of the bigger picture&quot; after days of methodically cranking through beads. If that happens, stop and ask: &quot;Where are we on this project? Do we actually have the thing we are trying to build? If we intelligently implement all open beads, would we close that gap completely?&quot; If the answer is no, add or revise beads, re-polish them, and resume with a corrected frontier. Busy agents are not the goal; a bead graph that actually converges on the project goal is the goal.
              </TipBox>
            </SubSection>

            <SubSection title="Diagnosing a Stuck Swarm">
              <P>When a swarm goes bad, the failure is usually one of two things: a <strong>local coordination jam</strong> (agents stepping on each other or losing operational context) or a <strong>strategic drift problem</strong> (the swarm is busy but no longer closing the real gap to the goal).</P>

              <DataTable
                headers={["Symptom", "Likely Cause", "What to Do"]}
                rows={[
                  ["Multiple agents keep picking the same bead", "Starts were not staggered; agents are not marking in_progress", "Stagger starts, force explicit Agent Mail claim messages, check reservations"],
                  ["Agent goes in circles after compaction", "It forgot the operating contract in AGENTS.md", "Force Reread AGENTS.md; kill/restart the session if still erratic"],
                  ["A bead sits in_progress for too long", "Agent crashed, silently blocked, or lost the plot", "Check Agent Mail, reclaim the bead, split out the blocker into a clearer bead"],
                  ["Agents produce contradictory implementations", "Not coordinating through Agent Mail and reservations", "Audit reservation use, revise bead boundaries if overlapping"],
                  ["Lots of code and commits, but goal still feels far", "Strategic drift; current beads do not close the remaining gap", "Stop, run the reality check prompt, revise bead graph"],
                ]}
              />
            </SubSection>

            <SubSection title="Atlas Notes as a Live Swarm">
              <P>For a small project like Atlas Notes, a first swarm might look like this: <strong>Claude agent A</strong> claims br-101 and implements upload + parse handling. <strong>Codex agent B</strong> claims br-102 and works on the search path plus tests. <strong>Claude agent C</strong> claims br-103 and builds the admin failure dashboard. <strong>Gemini agent D</strong> stays flexible: reviews recent work, checks docs, and fills in test or UX gaps where needed. All four share the same codebase, read the same AGENTS.md, coordinate via Agent Mail, and use bv whenever they are uncertain about what unlocks the most progress next. That is what makes the swarm feel like one system rather than four unrelated terminals.</P>
            </SubSection>

            <SubSection title="Account Switching">
              <P>When you hit rate limits, use CAAM (Coding Agent Account Manager) for sub-100ms account switching:</P>

              <CodeBlock language="bash" code={`caam status                     # See current accounts and usage
caam activate claude backup-2   # Switch instantly`} />
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 8: REVIEW, TESTING & HARDENING                         */}
          {/* ============================================================= */}
          <GuideSection id="review" number="8" title="Review, Testing & Hardening">
            <P>Code review in a multi-agent swarm follows a different rhythm than traditional code review. There is no pull request, no human reviewer, no approval gate. Instead, review is woven into the implementation cycle itself: agents review their own work after each bead, review each other&apos;s work periodically, and the human triggers broader review rounds at natural checkpoints.</P>

            <BlockQuote>I&apos;m constantly having them review themselves the work of other agents throughout the process. I had routines where I just do this deep review with them until they stop coming up with any problems. Then I have them also create tons of unit tests and e2e tests. And I use the code.</BlockQuote>

            <P>If you&apos;ve done a good job creating your beads, the agents will be able to get a decent sized chunk of work done in that first pass. Then, before they start moving to the next bead, have them review all their work:</P>

            <PromptBlock
              title="Fresh Eyes Review"
              prompt={`Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. Use ultrathink.`}
              where="After each bead is implemented; run until no more bugs are found"
              whyItWorks="This prompt is short because it is not redirecting the agent into a new domain. It is forcing a mode switch from generative coding to adversarial reading. The phrase 'fresh eyes' pushes the model to reframe code it just wrote as something potentially wrong, confusing, or internally inconsistent. That reduces the pattern where an agent stops once code compiles and never performs the low-cost bug sweep that catches obvious issues. The most effective reviews use subagent delegation: dispatch a fresh subagent with no memory of the original implementation to review each changed file."
            />

            <P>Keep running rounds until they stop finding bugs. Typically 1-2 rounds for simple beads, 2-3 for complex ones. If an agent keeps finding bugs after 3 rounds, the implementation approach may be fundamentally off; consider having a different agent take over.</P>

            <TipBox variant="info">
              You do not need to send the review prompt manually every time. Include it as part of the agent&apos;s workflow expectations in AGENTS.md: &quot;After completing each bead, do a self-review before moving to the next one.&quot; Well-trained agents (with a good skill) will do this automatically.
            </TipBox>

            <P>Each review should answer four questions:</P>

            <NumberedList items={[
              <><strong>Is the implementation correct?</strong> Does it do what the bead description says it should?</>,
              <><strong>Are there edge cases?</strong> Empty inputs, concurrent access, error paths, boundary conditions.</>,
              <><strong>Are there similar issues elsewhere?</strong> If you find a bug, search for the same pattern in other files.</>,
              <><strong>Should the approach be different?</strong> Sometimes the implementation is correct but there is a simpler or more robust way.</>,
            ]} />

            <P>When reviews come back clean, have them move on to the next bead:</P>

            <PromptBlock
              title="Advance to Next Bead"
              prompt={`Reread AGENTS.md so it's still fresh in your mind. Use ultrathink. Use bv with the robot flags (see AGENTS.md for info on this) to find the most impactful bead(s) to work on next and then start on it. Remember to mark the beads appropriately and communicate with your fellow agents. Pick the next bead you can actually do usefully now and start coding on it immediately; communicate what you're working on to your fellow agents and mark beads appropriately as you work. And respond to any agent mail messages you've received.`}
              where="After self-review comes back clean"
              whyItWorks="This transition prompt is the glue between beads. It combines re-reading AGENTS.md (for compaction safety), querying bv for priority, and communicating with the swarm. It ensures the agent uses graph-theory routing to choose the task that unblocks the most downstream work, rather than picking arbitrarily."
            />

            <SubSection title="Testing: Free Labor">
              <P>When all your beads are completed, make sure you have solid test coverage:</P>

              <PromptBlock
                title="Test Coverage"
                prompt={`Do we have full unit test coverage without using mocks/fake stuff? What about complete e2e integration test scripts with great, detailed logging? If not, then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid with detailed comments. Use ultrathink.`}
                where="After initial implementation pass is complete"
              />

              <BlockQuote>The tests become obsolete and need to be revised as the code changes, which slows down dev velocity. But if all the tests are written and maintained by agents, who cares? Add another couple agents to the swarm and let them deal with updating the tests and running them. It&apos;s free!</BlockQuote>

              <P>Larger projects produce massive test suites. BrennerBot has nearly 5,000 tests. Stuff tends to &quot;just work&quot; in that case. Use UBS (Ultimate Bug Scanner) as a quality gate before every commit: <code>ubs &lt;changed-files&gt;</code> catches errors beyond what linters and type checkers find, including security holes, supply chain vulnerabilities, and runtime stability issues.</P>

              <P>After any substantive code changes, always verify with compiler checks:</P>

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

            <SubSection title="UI/UX Polish">
              <P>For projects with a user interface, there is a dedicated polishing phase that happens after core functionality works but before shipping. This is separate from bug hunting because the problems you are looking for are not bugs; they are friction, ugliness, and missed opportunities to delight. When an agent implements an &quot;authentication&quot; bead, it focuses on making auth work correctly. Whether the login form has good visual hierarchy, whether the error messages are helpful, whether the flow feels smooth on mobile: these are orthogonal concerns requiring a different mode of attention. Trying to do both at once produces mediocre results on both.</P>

              <P>The workflow has five steps: <strong>Step 1</strong>, run the general scrutiny prompt to generate a list of improvement suggestions (not code changes). <strong>Step 2</strong>, review the suggestions and pick which to pursue (human judgment step; the agent typically generates 15-30 suggestions, some excellent, some unnecessary). <strong>Step 3</strong>, turn selected suggestions into beads and implement through the normal swarm process. <strong>Step 4</strong>, run the platform-specific polish prompt. <strong>Step 5</strong>, repeat until improvements become marginal (typically 2-3 rounds).</P>

              <PromptBlock
                title="UI/UX Scrutiny"
                prompt={`Great, now I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you, things that could very obviously be improved from a user-friendliness and intuitiveness standpoint, places where our UI/UX could be improved and polished to be slicker, more visually appealing, and more premium feeling and just ultra high quality, like Stripe-level apps. Use ultrathink.`}
                where="After core functionality is working"
              />

              <PromptBlock
                title="Platform-Specific Polish"
                prompt={`I still think there are strong opportunities to enhance the UI/UX look and feel and to make everything work better and be more intuitive, user-friendly, visually appealing, polished, slick, and world class in terms of following UI/UX best practices like those used by Stripe, don't you agree? And I want you to carefully consider desktop UI/UX and mobile UI/UX separately while doing this and hyper-optimize for both separately to play to the specifics of each modality. I'm looking for true world-class visual appeal, polish, slickness, etc. that makes people gasp at how stunning and perfect it is in every way. Use ultrathink.`}
                where="After the scrutiny pass"
                whyItWorks="The 'don't you agree?' phrasing is not politeness. It triggers the model to critically evaluate its own previous work rather than just validating it."
              />
            </SubSection>

            <SubSection title="De-Slopification">
              <P>After agents write documentation (README, user-facing text), run a de-slopify pass to remove telltale AI writing patterns. This must be done manually, not via regex. Read each line and revise systematically:</P>

              <DataTable
                headers={["Pattern", "Problem"]}
                rows={[
                  ["Emdash overuse", "LLMs use emdashes constantly, even when semicolons, commas, or sentence splits work better"],
                  ["\"It's not X, it's Y\"", "Formulaic contrast structure"],
                  ["\"Here's why\" / \"Here's why it matters:\"", "Clickbait-style lead-in"],
                  ["\"Let's dive in\"", "Forced enthusiasm"],
                  ["\"At its core...\"", "Pseudo-profound opener"],
                  ["\"It's worth noting...\"", "Unnecessary hedge"],
                ]}
              />
            </SubSection>

            <SubSection title="Deep Cross-Agent Review">
              <P>This phase is distinct from the per-bead self-reviews above. Self-reviews happen after each bead is completed and focus on the code that was just written. Deep review happens after all (or most) beads are done and casts a wider net across the entire codebase, looking for problems that only become visible when you see how all the pieces fit together.</P>

              <P>Cross-agent review catches a fundamentally different class of bugs than self-review. When Agent A implements a function and Agent B calls it, Agent A&apos;s self-review will never catch the fact that Agent B is passing arguments in the wrong order, because Agent A does not know about Agent B&apos;s code. Cross-agent review surfaces these integration issues.</P>

              <P>Every 30-60 minutes during active implementation, or after a natural milestone (e.g., all beads in an epic are done), trigger cross-agent review. Do not have all agents stop to review simultaneously; pick one or two agents that just finished a bead and send them the review prompt while the others keep implementing. This keeps the swarm productive while still catching inter-agent issues.</P>

              <P>Keep doing rounds of these two prompts until they consistently come back clean with no changes made. These prompts serve different purposes and should be alternated. This is one of the more art-than-science parts of the methodology. The prompts overlap in literal meaning, but they reliably activate different search behaviors in the models:</P>

              <PromptBlock
                title="Random Code Exploration"
                prompt={`I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by.

Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them.

Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file. Use ultrathink.`}
                where="Alternate with the cross-agent review below"
                whyItWorks="The prompt first asks the agent to build a mental model of purpose and flow, then asks for criticism. That ordering matters. A bug hunt without workflow understanding degrades into linting; a bug hunt after tracing execution flows catches logic errors, mismatched assumptions, and silent product-level breakage. The 'randomly explore' framing breaks the locality trap. Directed reviews focus on files that seem important, which are the files that got the most attention already. Bugs that survive to this phase live in utility modules, error handling paths, configuration parsing, and edge-case branches."
              />

              <PromptBlock
                title="Cross-Agent Review"
                prompt={`Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep! Use ultrathink.`}
                where="Alternate with the random exploration above"
                whyItWorks="This prompt forces the swarm to stop treating code ownership as sacred. A large share of real defects live at the boundaries between agents' changes or in assumptions nobody revisits because they were made by 'someone else.' The instruction not to restrict review to the latest commits prevents shallow PR-style skimming and pushes the agent to trace older surrounding code, dependency surfaces, and adjacent workflows where the real root cause may live. The first-principles wording nudges the reviewer away from symptom-fixing toward actual causal diagnosis."
              />

              <P>The cross-agent prompt tends to induce a suspicious, adversarial stance aimed at boundary failures and root causes in code written by others. The random-exploration prompt tends to induce a curiosity-driven stance aimed at reconstructing workflows and finding latent bugs in code that nobody is actively staring at. In practice, alternating them produces better coverage than repeating either one alone.</P>

              <P><strong>How to run deep bug hunting:</strong> Send the random exploration prompt to 2-3 agents simultaneously — each will explore different parts of the codebase because the randomness ensures variety. After they report back, send the cross-agent review prompt. Alternate until agents consistently come back with &quot;I reviewed X, Y, Z files and found no issues.&quot; When two consecutive rounds both come back clean, the codebase is in good shape. If agents keep finding bugs after 4+ rounds, go back to bead space and create specific fix beads. Always run <code>ubs .</code> on the full project first and fix everything it flags before letting agents hunt for subtler issues.</P>
            </SubSection>

            <SubSection title="Organized Commits">
              <P>Periodically have one agent handle git operations:</P>

              <PromptBlock
                title="Organized Commits"
                prompt={`Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files. Use ultrathink.`}
                where="Every 1-2 hours during active development"
                whyItWorks="Designating one agent prevents merge conflicts and produces coherent commit messages. The 'don't edit the code' instruction is critical: without it, agents treat the commit step as an opportunity to 'fix one more thing,' which creates unbounded scope expansion and makes the commit unpredictable. The 'logically connected groupings' instruction produces a meaningful git history instead of one monolithic 'update everything' commit that is impossible to review or bisect later."
              />
            </SubSection>

            <SubSection title="Swarm Diagnosis: Reality Check">
              <P>When the swarm looks active but you suspect it is not closing the real gap to the goal:</P>

              <PromptBlock
                title="High-Level Reality Check"
                prompt={`Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?`}
                where="When the swarm feels busy but directionally off"
                whyItWorks="This prompt breaks the spell of local productivity. Instead of asking whether the current bead is going well, it asks whether the current frontier of work actually converges on the project outcome. If the agent concludes that finishing all open beads still would not get you there, the answer is not 'work harder.' The answer is to revise the bead graph and re-aim the swarm."
              />
            </SubSection>

            <SubSection title="README Revision">
              <PromptBlock
                title="README Reviser"
                prompt={`OK, we have made tons of recent changes that aren't yet reflected in the README file. First, reread AGENTS.md so it's still fresh in your mind. Now, we need to revise the README for these changes (don't write about them as "changes" however, make it read like it was always like that, since we don't have any users yet!). Also, what else can we put in there to make the README longer and more detailed about what we built, why it's useful, how it works, the algorithms/design principles used, etc? This should be incremental NEW content, not replacement for what is there already.`}
                where="After significant implementation work"
              />
            </SubSection>

            <SubSection title="Catch-All Oversight">
              <PromptBlock
                title="Quick Final Sanity Check"
                prompt={`Great. Look over everything again for any obvious oversights or omissions or mistakes, conceptual errors, blunders, etc.`}
                where="After any significant change, as a quick final pass"
              />
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
              <P>When ending a work session, agents must complete every step. Work is NOT complete until <code>git push</code> succeeds. Unpushed work is stranded locally and invisible to every other agent.</P>

              <NumberedList items={[
                <><strong>File issues for remaining work.</strong> Create beads for anything that needs follow-up.</>,
                <><strong>Run quality gates.</strong> Tests, linters, builds (if code changed).</>,
                <><strong>Update issue status.</strong> Close finished work, update in-progress items.</>,
                <><strong>Sync beads.</strong> <code>br sync --flush-only</code> to export to JSONL, then <code>git add .beads/</code>.</>,
                <><strong>Commit and push.</strong> <code>git pull --rebase &amp;&amp; git add &lt;files&gt; &amp;&amp; git commit &amp;&amp; git push</code>.</>,
                <><strong>Verify.</strong> <code>git status</code> must show &quot;up to date with origin.&quot;</>,
              ]} />

              <P>For the Atlas Notes example, &quot;done for now&quot; would not mean &quot;the upload page appears.&quot; It would mean: the upload, parse, search, and admin-review workflows all work end to end; the key beads are closed and remaining polish ideas exist as new beads; tests cover the critical user journeys and known failure paths; UBS and compiler/lint checks are clean; commits and pushes are complete; and the next session can restart from beads, AGENTS.md, and Agent Mail threads rather than from human memory.</P>

              <P>A Flywheel session is only landable when a future swarm can pick it back up without the human re-explaining the project from scratch.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 9: THE COMPLETE TOOLCHAIN                              */}
          {/* ============================================================= */}
          <GuideSection id="toolchain" number="9" title="The Complete Toolchain">
            <P>The Flywheel is supported by a stack of 11 purpose-built tools, all free and open-source:</P>

            <DataTable
              headers={["Tool", "Command", "Purpose"]}
              rows={[
                ["NTM", "ntm", "Named Tmux Manager — agent cockpit for spawning, sending, and broadcasting"],
                ["Agent Mail", "am", "Agent coordination — identities, inbox/outbox, file reservations"],
                ["UBS", "ubs", "Ultimate Bug Scanner — 1000+ patterns, pre-commit guardrails"],
                ["Beads", "br", "Issue tracking — dependency-aware, JSONL+SQLite hybrid"],
                ["Beads Viewer", "bv", "Triage engine — PageRank, betweenness, HITS, robot mode"],
                ["RCH", "rch", "Remote build offloading — keeps heavy CPU work off the swarm box"],
                ["CASS", "cass", "Session search — unified agent history indexing"],
                ["CASS Memory", "cm", "Procedural memory — episodic → working → procedural"],
                ["CAAM", "caam", "Auth switching — sub-100ms account swap across providers"],
                ["DCG", "dcg", "Safety guard — blocks destructive git/filesystem operations mechanically"],
                ["SLB", "slb", "Two-person rule — optional guardrails for dangerous commands"],
              ]}
            />

            <P>Not every tool is used the same way. <code>br</code>, <code>bv</code>, <code>ubs</code>, and <code>rch</code> are ordinary shell commands. Agent Mail is primarily experienced through MCP tools and macros. The installer (<a href="https://agent-flywheel.com" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">agent-flywheel.com</a>) installs all of them with a single <code>curl|bash</code> command.</P>

            <SubSection title="The Flywheel Interactions">
              <P>The complete interaction flow from spawn to memory:</P>

              <CodeBlock language="text" code={`NTM spawns agents --> Agents read AGENTS.md
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

              <P>Use <code>acfs newproj</code> to bootstrap a project with full tooling:</P>

              <CodeBlock language="bash" code={`acfs newproj myproject --interactive

# Creates:
# myproject/
# ├── .git/        # Git repository initialized
# ├── .beads/      # Local issue tracking (br)
# ├── .claude/     # Claude Code settings
# ├── AGENTS.md    # Instructions for AI agents
# └── .gitignore   # Standard ignores`} />
            </SubSection>

            <SubSection title="The Incremental Onboarding Path">
              <P>For beginners who find the full system overwhelming:</P>

              <NumberedList items={[
                <><strong>Start with:</strong> Agent Mail + Beads (br) + Beads Viewer (bv) — this core trio captures most of the value</>,
                <><strong>Then add:</strong> UBS for bug hunting</>,
                <><strong>Then add:</strong> DCG for destructive command protection</>,
                <><strong>Then add:</strong> CASS for session history</>,
                <><strong>Then add:</strong> CM (CASS Memory) for codifying lessons into procedural memory</>,
              ]} />

              <TipBox variant="warning">
                <strong>Common beginner mistakes:</strong> Making a hasty plan all at once instead of the multi-model iterative process. Trying to convert the plan to beads in a single pass. Not doing at least 3 rounds of polishing. &quot;Well, of course the project is going to suck and be a buggy mess if you do that.&quot;
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
              <BulletList items={[
                <><strong>The &quot;30 to 5 to 15&quot; funnel:</strong> When generating ideas, having agents brainstorm 30 then winnow to 5 produces much better results than asking for 5 directly. The winnowing forces critical evaluation.</>,
                <><strong>Parallel subagents for bulk bead operations:</strong> Creating dozens of beads is faster when dispatched to parallel subagents, each handling a subset.</>,
                <><strong>Staggered agent starts:</strong> Starting agents 30-60 seconds apart avoids the thundering herd problem.</>,
                <><strong>One agent for git operations:</strong> Designating one agent to handle all commits prevents merge conflicts and produces coherent commit messages.</>,
              ]} />
            </SubSection>

            <SubSection title="Anti-Patterns to Avoid">
              <BulletList items={[
                <><strong>Single-pass beads:</strong> First-draft beads are never optimal. Always do 4-5 polishing passes minimum.</>,
                <><strong>Skipping plan-to-bead validation:</strong> Not cross-referencing beads against the plan leads to missing features discovered only during implementation.</>,
                <><strong>Communication purgatory:</strong> Agents spending more time messaging each other than coding. Be proactive about starting work.</>,
                <><strong>Holding reservations too long:</strong> File reservations with long TTLs block other agents unnecessarily. Reserve, edit, commit, release.</>,
                <><strong>Not re-reading AGENTS.md after compaction:</strong> Context compaction loses nuances. The re-read is mandatory, not optional.</>,
              ]} />
            </SubSection>

            <SubSection title="Supporting Infrastructure">
              <DataTable
                headers={["Component", "Purpose"]}
                rows={[
                  ["AGENTS.md", "Per-project configuration teaching agents about tools and rules"],
                  ["Best practices guides", "Referenced in AGENTS.md, kept current"],
                  ["Markdown plan files", "Source-of-truth planning documents"],
                  ["acfs newproj", "Bootstraps projects with full tooling (.git, .beads, .claude, AGENTS.md)"],
                  ["acfs doctor", "Single command to verify entire installation"],
                  ["NTM command palette", "Battle-tested prompt library accessible via ntm palette"],
                  ["Claude Code Skills", "Each tool has a dedicated skill for automated workflows"],
                ]}
              />
            </SubSection>

            <SubSection title="The Skills Ecosystem">
              <P>The term &quot;skill&quot; confuses people at first, so define it plainly: a skill is a reusable operational instruction pack for an agent. In Claude Code terms, that usually means a <code>SKILL.md</code> file plus optional references, scripts, or templates that tell the agent how to use a tool, how to execute a methodology, what pitfalls to avoid, and what a good result looks like. A good skill is closer to executable know-how than to ordinary prose documentation.</P>

              <P>A tool changes what the agent <em>can</em> do. A skill changes how <em>well</em> the agent knows how to do it. The same model with and without a good skill often behaves like two different agents.</P>

              <P>Every Flywheel tool has a corresponding Claude Code skill that encodes best practices and automates common workflows. Many of these skills are bundled directly in the repos for the tools themselves and get installed automatically when the tool is installed, which means users often benefit from them without having to think about &quot;skill management&quot; explicitly. There is also a broader public skills collection at <a href="https://github.com/Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations/tree/main/skills" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">GitHub</a>.</P>

              <P>The prompt side has a similar split. <a href="https://jeffreysprompts.com" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">jeffreysprompts.com</a> has a generous free section and is open source at <a href="https://github.com/Dicklesworthstone/jeffreysprompts.com" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">GitHub</a>. It also has a paid Pro tier with additional prompts and a dedicated CLI called <code>jfp</code> for managing prompt collections. For a larger paid library of higher-end skills, see <a href="https://jeffreys-skills.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">jeffreys-skills.md</a>, a $20/month service with many of the strongest curated skills, new skills added continuously, and a dedicated CLI called <code>jsm</code> for managing them.</P>

              <P>Both paid offerings are still under active development. That means occasional rough edges. Active work is underway to fix issues quickly, feedback is appreciated, and refunds are available for unhappy users.</P>

              <P>Skills provide the prompts, procedures, anti-pattern guidance, and tool-specific workflows directly to agents, which reduces the amount of bespoke prompting a human needs to do by hand.</P>
            </SubSection>

            <SubSection title="Vendor Lock-In: Avoid It">
              <BlockQuote>PSA: you should avoid vendor lock-in for agent coding primitives like task management (e.g., beads) and agent communication (e.g., MCP Agent Mail) so you can use all the agents together, which is more powerful anyway. They want you in a walled garden, but it&apos;s 100% unnecessary.</BlockQuote>

              <P>Beads, Agent Mail, and bv are all CLI tools that work identically regardless of which agent invokes them. A Claude Code agent and a Codex agent and a Gemini agent can all call <code>br ready --json</code> and get the same task list. The practical test: could you swap out every Claude Code agent for Codex or Gemini without changing your AGENTS.md, beads, Agent Mail setup, or workflow? If yes, you&apos;re vendor-neutral.</P>
            </SubSection>

            <SubSection title="Validation Gates">
              <P>These gates turn the methodology into a contract. If a gate fails, drop back a phase instead of pushing forward optimistically.</P>

              <DataTable
                headers={["Gate", "Must Be True Before Advancing"]}
                rows={[
                  ["Foundation", "Goals, workflows, stack, architecture direction, AGENTS.md, and best-practices guides exist and are coherent"],
                  ["Plan", "Markdown plan covers workflows, architecture, sequencing, constraints, testing expectations, and major failure paths"],
                  ["Translation", "Every material plan element maps to one or more beads, checked in both directions"],
                  ["Bead", "Beads are self-contained, dependency-correct, rich in context, and explicit about test obligations"],
                  ["Launch", "Agent Mail, file reservations, bead IDs, bv, AGENTS.md, and staggered startup are all ready"],
                  ["Ship", "Reviews, tests, UBS, remaining-work beads, and feedback capture into reusable artifacts are complete"],
                ]}
              />
            </SubSection>

            <SubSection title="Vibe Mode Aliases">
              <P>On the VPS, agents run with full permissions via short aliases:</P>

              <CodeBlock language="bash" code={`alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox'
alias gmi='gemini --yolo'`} />

              <P>These are configured automatically by the installer. DCG provides the safety net that makes this viable.</P>
            </SubSection>

            <SubSection title="Cost">
              <P>~$500/month for Claude Max and GPT Pro subscriptions (at minimum), plus ~$50/month for a cloud server (OVH, Contabo). Multiple Max accounts may be needed for large swarms; CAAM enables instant switching when hitting rate limits. At scale, token usage for a single intensive session can reach ~20M input tokens, ~3.5M output tokens, ~2.6M reasoning tokens, and ~1.15 billion cached token reads. At full scale: 22 Claude Max accounts, 22 GPT Pro accounts, and 7 Gemini Ultra accounts.</P>
            </SubSection>
          </GuideSection>

          <Divider />

          {/* ============================================================= */}
          {/* SECTION 10: THE FLYWHEEL EFFECT                                */}
          {/* ============================================================= */}
          <GuideSection id="flywheel" number="10" title="The Flywheel Effect">
            <P highlight>If you simply use these tools, workflows, and prompts in the way just described, you can create really incredible software in just a couple days, sometimes in just one day. I&apos;ve done it a bunch of times now and it really does work, as crazy as that may sound. You see my GitHub profile for the proof of this. It looks like the output from a team of 100+ developers.</P>

            <P>It behaves like a flywheel rather than a checklist because each cycle makes the next one better:</P>

            <BulletList items={[
              <><strong>Planning quality compounds</strong> because you keep reusing prompts, patterns, and reasoning structures that CASS proves actually worked.</>,
              <><strong>Execution quality compounds</strong> because better beads make swarm behavior more deterministic and less dependent on human improvisation.</>,
              <><strong>Tool quality compounds</strong> because agents use the tools, complain about them, and then help improve them.</>,
              <><strong>Memory compounds</strong> because the results of one swarm, captured by CASS session search, become training data, rituals, and infrastructure for the next one.</>,
            ]} />

            <SubSection title="How the Compounding Actually Works">
              <P>Each session makes the next one better. Concretely: <strong>Session N produces raw data</strong> — CASS automatically logs every agent session. <strong>Between sessions, CM distills patterns</strong> — running <code>cm reflect</code> extracts procedural rules like &quot;always run cargo check after modifying Cargo.toml&quot; with confidence scores that decay without reinforcement and amplify with repetition. <strong>Session N+1 starts with those patterns loaded</strong> — running <code>cm context &quot;Building an API&quot;</code> retrieves relevant procedural memory. Simultaneously, UBS patterns grow as new bug classes get added. Agent Mail coordination norms get refined in AGENTS.md and skills.</P>

              <P>The compounding is real but not automatic in the early stages. You have to actually run <code>cm reflect</code>, actually review CASS session data, actually update AGENTS.md with lessons learned. But even manually, spending 15 minutes between projects reviewing what worked and updating your AGENTS.md template produces outsized returns on every subsequent project.</P>
            </SubSection>

            <SubSection title="Agent Feedback Forms">
              <P>Apply the same feedback mechanisms you would use for humans (structured surveys, satisfaction ratings, net promoter scores) directly to agents evaluating tools. After an agent finishes using a tool in a real project, ask it to fill out a structured feedback survey. Then pipe that feedback directly into another agent working on the tool itself. The iteration cycle collapses from weeks to minutes.</P>

              <PromptBlock
                title="Agent Tool Feedback"
                prompt={`Based on your experience with [TOOL] today in this project, how would you rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was it helpful to you? Did it flag a lot of useful things that you would have missed otherwise? Did the issues it flagged have a good signal-to-noise ratio? What did it do well, and what was it bad at? Did you run into any errors or problems while using it?

What changes to [TOOL] would make it work even better for you and be more useful in your development workflow? Would you recommend it to fellow coding agents? How strongly, and why or why not? The more specific you can be, and the more dimensions you can score [TOOL] on, the more helpful it will be for me as I improve it and incorporate your feedback to make [TOOL] even better for you in the future!`}
                where="After an agent finishes using a tool in a real project"
                whyItWorks="Many of the same concepts we use for people are directly applicable to agents. 'By robots, for robots.' This produces structured, actionable feedback. When used across multiple agents on different project types, you get a diverse sample of experiences. One caveat: as with humans who would tell you they wanted a 'faster horse' instead of a car, it is dangerous to trust agent feedback about potential new features before those features exist. The real test is always after implementation, in real-world usage."
              />
            </SubSection>

            <SubSection title="CASS Memory: Three-Layer Architecture">
              <P>CM (CASS Memory System) implements a three-layer memory architecture that turns raw session history into operational knowledge:</P>

              <CodeBlock language="text" code={`EPISODIC MEMORY (cass): Raw session logs from all agents
         ↓ cass search
WORKING MEMORY (Diary): Structured session summaries
         ↓ reflect + curate
PROCEDURAL MEMORY (Playbook): Distilled rules with confidence scores`} />

              <P>Rules have a 90-day confidence half-life (decays without feedback) and a 4x harmful multiplier (one mistake counts 4x as much as one success). Rules mature through stages: <code>candidate</code> to <code>established</code> to <code>proven</code>.</P>

              <CodeBlock language="bash" code={`cm context "Building an API" --json   # Get relevant memories for a task
cm recall "authentication patterns"   # Search past sessions
cm reflect                            # Update procedural memory from recent sessions
cm mark b-8f3a2c --helpful            # Reinforce a useful rule
cm mark b-xyz789 --harmful --reason "Caused regression"  # Flag a bad rule`} />

              <P>The <code>cm context</code> command is the single most important pre-task ritual. Running it at the start of a session gives agents knowledge distilled from every previous session that touched similar work.</P>
            </SubSection>

            <SubSection title="Meta-Skill: Skill Refinement via CASS Mining">
              <PromptBlock
                title="Skill Refinement Meta-Skill"
                prompt={`Search CASS for all sessions where agents used the [SKILL] skill. Look for: patterns of confusion, repeated mistakes, steps agents skipped, workarounds they invented, and things they did that weren't in the skill but should be.

Then rewrite the skill to fix every issue you found. Make the happy path obvious, add guardrails for the common mistakes, and incorporate the best workarounds as official steps. Test the rewritten skill against the failure cases from the session logs.`}
                where="Claude Code, targeting any skill with 10+ CASS sessions of usage data"
                whyItWorks="This is the meta-skill pattern in action. The skill-refiner skill itself can be refined using its own session data, which is the self-referential property that makes the whole system accelerate. After 3-4 cycles, the skill is dramatically more reliable than the original. Each cycle takes less human effort because the meta-skill itself has improved."
              />
            </SubSection>

            <SubSection title="CASS Ritual Detection">
              <P>The flywheel&apos;s learning loop depends on mining past sessions to find what actually works. CASS enables <Hl>ritual detection</Hl>: discovering prompts that are repeated so frequently they constitute validated methodology.</P>

              <DataTable
                headers={["Repetition Count", "Status", "Action"]}
                rows={[
                  ["count >= 10", "RITUAL", "Validated methodology. Extract into a skill."],
                  ["count 5-9", "Emerging pattern", "Worth investigating further."],
                  ["count < 5", "One-off", "Not generalizable yet."],
                ]}
              />

              <P>The mining query (user prompts live at lines 1-3 of session entries; <code>--fields minimal</code> reduces output 5x):</P>

              <CodeBlock language="bash" code={`cass search "*" --workspace /data/projects/PROJECT --json --fields minimal --limit 500 \\
  | jq '[.hits[] | select(.line_number <= 3) | .title[0:80]]
        | group_by(.) | map({prompt: .[0], count: length})
        | sort_by(-.count) | map(select(.count >= 5)) | .[0:30]'`} />

              <P>This is how the prompt library in this guide was originally discovered and validated. It was not invented top-down; it was mined bottom-up from hundreds of real sessions.</P>
            </SubSection>

            <SubSection title="Why It Works: Layered Context">
              <P>The workflow works because it keeps different kinds of context in different layers. The <strong>markdown plan</strong> holds whole-system intent and reasoning. The <strong>beads</strong> hold executable task structure and embedded local context. <strong>AGENTS.md</strong> holds operating rules and tool knowledge that must survive compaction. The <strong>codebase</strong> holds the implementation itself, which is too large to be the primary planning medium. Each layer serves a different purpose, and the methodology is disciplined about keeping the right information in the right layer.</P>
            </SubSection>

            <SubSection title="The Kernel: 9 Invariants">
              <NumberedList items={[
                <><strong>Global reasoning belongs in plan space.</strong> Do the hardest architectural and product reasoning while the whole project still fits in context.</>,
                <><strong>The markdown plan must be comprehensive before coding starts.</strong> Skeleton-first coding throws away the main advantage of frontier models.</>,
                <><strong>Plan-to-beads is a distinct translation problem.</strong> A good plan does not automatically produce a good bead graph.</>,
                <><strong>Beads are the execution substrate.</strong> Once good enough, they should carry enough context that agents no longer need the full plan.</>,
                <><strong>Convergence matters more than first drafts.</strong> Plans and beads both improve through repeated polishing until changes become small and corrective.</>,
                <><strong>Swarm agents are fungible.</strong> Coordination must live in artifacts and tools, not in special agents or unstated knowledge.</>,
                <><strong>Coordination must survive crashes and compaction.</strong> AGENTS.md, Agent Mail, bead state, and robot modes exist to keep work moving when sessions die.</>,
                <><strong>Session history is part of the system.</strong> Repeated prompts, failures, and recoveries should be mined via CASS and folded back into tools, skills, and validators.</>,
                <><strong>Implementation is not the finish line.</strong> Review, testing, UBS, and feedback-to-infrastructure loops are part of the core method.</>,
              ]} />
            </SubSection>

            <SubSection title="Time Investment">
              <DataTable
                headers={["Phase", "Typical Duration", "Notes"]}
                rows={[
                  ["Planning (multi-model synthesis + refinement)", "3+ hours for a complex feature", "Feels slow because no code is written, but the downstream payoff is enormous"],
                  ["Plan to beads conversion", "Significant; Claude needed 'coaxing and cajoling' for 347 beads", "A 5,500-line plan with hundreds of beads takes sustained effort"],
                  ["Bead polishing", "2-3 passes per session, multiple sessions", "Agents typically manage 2-3 passes before running out of context window"],
                  ["Implementation with swarm", "Remarkably fast", "CASS Memory System: 11k lines in ~5 hours with 25 agents"],
                ]}
              />

              <P>CASS itself (a complex Rust program used by thousands of people) was made in around a week, but the human personally only spent a few hours on it. The rest of the time was spent by a swarm of agents implementing and polishing it and writing tests.</P>
            </SubSection>

            <SubSection title="The Project Is a Foregone Conclusion">
              <BlockQuote>Once you have the beads in good shape based on a great markdown plan, I almost view the project as a foregone conclusion at that point. The rest is basically mindless &quot;machine tending&quot; of your swarm of 5-15 agents.</BlockQuote>

              <P>This claim sounds bold, but it follows logically from everything above. If the plan is thorough, the beads faithfully encode it with full context and correct dependencies, and the agents have a clear AGENTS.md, then implementation becomes a mechanical process of agents picking up beads, implementing them, reviewing, and moving on.</P>

              <P><strong>This is true when:</strong> the plan has genuinely converged (not merely become long), the beads are self-contained enough that fresh agents can execute them without guessing, the swarm has working coordination/review/testing loops, and the human is still tending when flow jams or reality diverges from the plan.</P>

              <P><strong>It stops being true when:</strong> architecture is still being invented during implementation, the bead graph is thin or missing dependencies, or the swarm cannot coordinate because AGENTS.md, Agent Mail, or bv usage is weak. If you find yourself doing heavy cognitive work during implementation, that is a signal that planning or bead polishing was insufficient. The remedy is to pause, go back to bead space, and add the missing detail.</P>
            </SubSection>

            <SubSection title="V1 Is Not Everything">
              <P>A common misconception is that you have to do everything in one shot. In this approach, that&apos;s true only for version 1. Once you have a functioning v1, adding new features follows the same process: create a super detailed markdown plan for the new feature, turn it into beads, and implement. The same process that creates the initial version also handles all subsequent iterations.</P>
            </SubSection>

            <SubSection title="Tools Must Be Agent-First">
              <BlockQuote>Every new dev tool in the year of our lord 2025 should have a robot mode designed specifically for agents to use. And it should probably be designed by agents, too. And then you iterate based on the feedback of the agents actually using the tool in real-world scenarios.</BlockQuote>

              <P>Every tool ships with a prepared AGENTS.md blurb. The tool is not complete without documentation that agents can consume. But it goes further: the tools themselves should be designed by agents, for agents, with iterative feedback. If agents do not like the tools, they will not use them without constant nagging.</P>

              <BlockQuote>I make sure the agents enjoy using them and solicit their feedback to improve the tooling. If they don&apos;t like the tools, they won&apos;t use them without constant nagging.</BlockQuote>
            </SubSection>

            <SubSection title="Recursive Self-Improvement: The Meta-Skill Pattern">
              <P>This is the most advanced concept in the flywheel, and the one that separates linear productivity gains from exponential ones. The core idea: <strong>your agent toolchain should improve itself using its own output as fuel.</strong></P>

              <P>Most developers treat skills and tools as static artifacts. You write a skill, agents use it, and if it works well enough, you move on. The recursive approach instead treats every agent session as training data for the next version of the skill, creating a tight feedback loop where the system gets measurably better each cycle without additional human effort.</P>

              <P>Consider what happens without recursive improvement. You build a CLI tool, write a Claude Code skill for it, and deploy both. Agents use the tool, but they misinterpret certain flags, forget to pass required arguments, or use workarounds because the skill&apos;s instructions were ambiguous. Every agent that hits the same snag wastes the same tokens re-discovering the same workaround. Multiply that across dozens of agents and hundreds of sessions, and the waste is enormous. Now consider the alternative: after those sessions happen, you automatically mine them, discover the failure patterns, rewrite the skill to prevent them, and the next wave of agents never hits those snags at all. The skill becomes a living document shaped by real usage rather than a guess about how agents will behave.</P>

              <BlockQuote>Using skills to improve skills, skills to improve tool use, and then feeding the actual experience in the form of session logs (surfaced and searched by my cass tool and /cass skill) back into the design skill for improving the tool interface to make it more natural and intuitive and powerful for the agents. Then taking that revised tool and improving the skill for using that tool, then rinse and repeat.</BlockQuote>
            </SubSection>

            <SubSection title="How to Actually Do This (Step by Step)">
              <NumberedList items={[
                <><strong>Build the baseline.</strong> Create a tool. Create a skill for it using <code>sc</code> (skill creator). The first version of the skill will be imperfect. Ship it anyway.</>,
                <><strong>Let agents use it in real work.</strong> Do not test in isolation. Deploy the tool and skill into actual project work where agents are implementing beads, running reviews, doing real tasks. CASS automatically logs every session.</>,
                <><strong>Mine the sessions.</strong> After 10+ sessions of real usage, search CASS for sessions where agents invoked the tool.</>,
                <><strong>Feed findings into a rewrite.</strong> Give the session analysis to a fresh agent along with the current skill file. Ask it to rewrite the skill to fix every issue.</>,
                <><strong>Repeat.</strong> The revised skill produces better sessions, which give you better data for the next revision. After 3-4 cycles, the skill is dramatically more reliable than the original.</>,
              ]} />

              <CodeBlock language="bash" code={`# Step 3: Mine sessions for patterns
cass search "tool_name" --workspace /data/projects/PROJECT --json --limit 100`} />

              <P>What to look for in the results:</P>

              <BulletList items={[
                <><strong>Clarifying questions:</strong> where agents asked &quot;do you mean X or Y?&quot; means the skill was ambiguous</>,
                <><strong>Repeated mistakes across different agents:</strong> a systematic gap in the skill&apos;s instructions</>,
                <><strong>Creative workarounds:</strong> agents inventing their own approach means the skill is missing a useful pattern</>,
                <><strong>Outright failures:</strong> the skill directed agents to do something wrong or impossible</>,
              ]} />

              <P>The key insight is that the rewriting step itself can be a skill. You can write a meta-skill whose entire purpose is: take a skill file + CASS session data as input, produce a better skill file as output. Then the meta-skill can also be refined using its own session data, which is the self-referential property that makes the whole system accelerate.</P>

              <BlockQuote>This is the way. Make a skill-refiner meta skill. CASS is unbelievably handy for this.</BlockQuote>

              <BlockQuote>Documentation for this documentation refining tool (so meta -- I should run it on itself, like a snake eating its own tail!)</BlockQuote>

              <P>Each cycle takes less human effort than the previous one because the meta-skill itself has improved.</P>
            </SubSection>

            <SubSection title="The Four Layers of Recursive Improvement">
              <P>The recursive pattern operates at increasing levels of ambition. The mistake is trying to build all four layers at once. Start simple and let the need for the next layer emerge naturally.</P>

              <RecursiveImprovementViz />

              <NumberedList items={[
                <><strong>Layer 1: Feedback forms after tool use (start here, no infrastructure needed).</strong> After an agent finishes using a tool, ask it to fill out a structured feedback survey. Feed that to another agent working on the tool itself. This requires nothing beyond two agent sessions and produces immediate improvements.</>,
                <><strong>Layer 2: CASS-powered skill refinement (requires session logging).</strong> Instead of relying on one agent&apos;s opinion, mine session logs to find systematic patterns across many agents. An agent using a tool for the first time might blame itself for a confusing flag; when you see 15 agents all struggling with the same flag, you know the flag is the problem.</>,
                <><strong>Layer 3: Skills that generate work (the system proposes its own improvements).</strong> The idea-wizard skill examines a project and generates improvement ideas. The optimization skill finds performance bottlenecks. These skills create new beads, which agents implement, which improve the tools, which make the skills more effective. The human&apos;s role shifts from directing specific work to curating which generated ideas are worth pursuing.</>,
                <><strong>Layer 4: Skills bundled with tool installers (the skill improves before the user ever sees it).</strong> Every tool you ship includes a pre-optimized Claude Code skill baked into its installer. The skill was refined through multiple CASS cycles before shipping. When a new user installs the tool, their agents immediately benefit from all the refinement work done across every previous user&apos;s sessions.</>,
              ]} />

              <BlockQuote>I&apos;m going to start having my tool installers always add a highly optimized skill. It makes a massive difference.</BlockQuote>
            </SubSection>

            <SubSection title="Why the Acceleration Compounds">
              <P>Most productivity techniques produce linear improvements: you get 10% better each cycle, and those gains do not stack. The recursive skill pattern compounds because each cycle improves the tools that perform the next cycle.</P>

              <P>When you improve the extreme-optimization skill, every future optimization pass across every tool benefits. When you improve the idea-wizard skill, every future brainstorming session across every project benefits. When you improve the skill-refiner meta-skill, every future skill refinement benefits. The improvements multiply rather than add.</P>

              <P>The tools produced by the recursive loop are the tools that produce the next tools. This is why the Knuth analogy is apt: it is genuinely the same concept as a compiler that compiles itself, except applied to the entire agent-driven development workflow rather than just a compiler.</P>

              <BlockQuote>I&apos;m going over each tool with my extreme optimization skill and applying insane algorithmic lore that Knuth himself probably forgot about already to make things as fast as the metal can go in memory-safe Rust.</BlockQuote>
            </SubSection>

            <SubSection title="The Hidden Knowledge Extraction">
              <P>The recursive loop has a second, subtler benefit that matters even more at the frontier. Models have internalized vast amounts of academic CS literature: obscure algorithmic techniques, mathematical proofs, design patterns from papers that only a handful of people ever read. Most of this knowledge never surfaces because nobody asks for it with enough precision.</P>

              <P>Skills are the mechanism for asking the right questions. Consider the difference:</P>

              <BulletList items={[
                <><strong>Without a skill:</strong> &quot;Optimize this function.&quot; The agent applies generic improvements like caching, loop unrolling, or reducing allocations. Useful but shallow.</>,
                <><strong>With an extreme-optimization skill:</strong> The skill directs the agent to systematically consider cache-oblivious data structures, SIMD vectorization opportunities, branch-free arithmetic, van Emde Boas layout, fractional cascading, and carry-less multiplication, then benchmark before and after each change. The agent draws on deep knowledge it would not volunteer unprompted.</>,
              ]} />

              <P>The skill acts as a key that unlocks specific rooms in the model&apos;s knowledge base. Without the key, the model defaults to common patterns. With it, the model reaches into the long tail of techniques that most human developers have never encountered.</P>

              <BlockQuote>The knowledge is just sitting there and the models have it. But you need to know how to coax it out of them.</BlockQuote>

              <P>This explains why the recursive loop accelerates rather than plateaus. Each cycle of skill refinement does not just fix bugs in the skill&apos;s instructions; it also sharpens the skill&apos;s ability to extract deeper knowledge from the model. The optimization skill gets better at asking for the right techniques, because CASS sessions reveal which techniques actually produced measurable gains and which were dead ends. The next cycle of optimization is better informed because the previous cycle&apos;s results are now part of the feedback corpus.</P>

              <P>Stack enough cycles and the result is code that looks like it was written by someone who read every obscure CS paper ever published. In a functional sense, it was. The agent served as a lens focusing decades of dispersed academic knowledge onto a single practical target. The skill was the lens prescription.</P>
            </SubSection>

            <SubSection title="The Operator Library">
              <P>These recurring cognitive moves show up throughout real Flywheel sessions. They matter more than any single prompt because they say <em>when</em> to apply a move, what failure looks like, and what output is expected. Each operator has a prompt module you can paste directly into an agent session.</P>

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
                whyItWorks="Prevents asking for 'all problems' and getting a shallow pass. Models stop after finding a 'reasonable' number; this forces exhaustive search."
              />

              <PromptBlock
                title="Operator 4: Plan-to-Beads Transfer Audit"
                prompt={`[OPERATOR: plan-to-beads-transfer-audit]
1) Walk every important part of the markdown plan and map it to actual beads.
2) Ensure rationale, constraints, and tests are embedded in the bead descriptions.
3) Identify anything in the plan that has no bead or any bead that has no clear plan backing.

Output (required): coverage report plus bead edits that close the gaps.`}
                where="When a large plan is about to be turned into execution tasks, or agents are creating beads quickly and may drop rationale"
                whyItWorks="A beautiful plan does not automatically produce good beads. Prevents creating terse beads that depend on tacit knowledge from the markdown file."
              />

              <PromptBlock
                title="Operator 5: Convergence Polish Loop"
                prompt={`[OPERATOR: convergence-polish-loop]
1) Re-run a full critical review in a fresh session.
2) Integrate the fixes and compare the magnitude of changes to the previous round.
3) Stop only when the revisions are small, mostly corrective, and coverage checks keep passing.

Output (required): revised artifact plus a judgment of whether it is still in major-change mode or near convergence.`}
                where="When a plan or bead graph has visible rough edges and the first polishing pass found real issues"
                whyItWorks="Prevents treating the first decent revision as final, or continuing endless polishing after returns have gone flat."
              />

              <PromptBlock
                title="Operator 6: Fresh-Eyes Reset"
                prompt={`[OPERATOR: fresh-eyes-reset]
1) Start a fresh session.
2) Reload AGENTS.md and the relevant project context.
3) Ask for a full review of the plan or beads as if seeing them for the first time.

Output (required): a fresh critical pass unconstrained by the prior session's local minima.`}
                where="When the agent has done several long review rounds and suggestions are getting repetitive or shallow"
                whyItWorks="Prevents trusting a tired context window to keep finding subtle flaws, or mistaking context exhaustion for genuine convergence."
              />

              <PromptBlock
                title="Operator 7: Fungible Swarm Launch"
                prompt={`[OPERATOR: fungible-swarm-launch]
1) Confirm AGENTS.md, bead state, Agent Mail, and bv routing are all ready.
2) Start agents in a staggered way and make them claim work immediately.
3) Keep coordination in beads, reservations, and threads rather than in a special overseer agent.

Output (required): an active swarm with claimed work, low collision risk, and no special-agent bottleneck.`}
                where="When beads are polished enough to execute and multiple agents are about to work in the same repository"
                whyItWorks="Prevents launching too early before beads are self-contained, or letting agent identity and role specialization become load-bearing."
              />

              <PromptBlock
                title="Operator 8: Feedback-to-Infrastructure Closure"
                prompt={`[OPERATOR: feedback-to-infrastructure-closure]
1) Mine CASS for repeated prompts, breakdowns, and fixes.
2) Distill the useful patterns into skills, AGENTS.md guidance, blurbs, or tool changes.
3) Update the reusable artifact so the next swarm starts from the improved baseline.

Output (required): a revised reusable artifact plus a short note describing the lesson it now encodes.`}
                where="When the same confusion or recovery pattern appears repeatedly in CASS, agents complain about a tool, or a project finishes with clear lessons worth retaining"
                whyItWorks="Prevents treating lessons as anecdotes instead of durable system inputs. This is the operator that turns repeated behavior into ritual, ritual into skill, skill into infrastructure."
              />
            </SubSection>

            <SubSection title="The Prompt Library">
              <P>All prompts in this guide are preserved verbatim from prompts that worked well in real sessions (quirks and typos included). For a much larger public prompt collection, see <a href="https://jeffreysprompts.com" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">jeffreysprompts.com</a>, which has a generous free section and is open source at <a href="https://github.com/Dicklesworthstone/jeffreysprompts.com" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">GitHub</a>. There is also a paid Pro tier with additional prompts and a CLI called <code>jfp</code> for managing prompt collections. For a larger paid library of higher-end skills, see <a href="https://jeffreys-skills.md" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">jeffreys-skills.md</a> ($20/month, with a dedicated CLI called <code>jsm</code>). Both paid offerings are still under active development.</P>
            </SubSection>

            <SubSection title="Common Problems from Real Deployments">
              <BulletList items={[
                <><strong>Agent Mail CLI availability:</strong> Sometimes the binary is not at the expected path; agents fall back to REST API calls.</>,
                <><strong>Context window exhaustion:</strong> Agents typically manage 2-3 polishing passes before needing a fresh session.</>,
                <><strong>Duplicate beads at scale:</strong> Large bead sets (100+) develop duplicates; dedicated dedup passes are necessary.</>,
                <><strong>Plan-bead gap:</strong> The synthesis step sometimes stalls between plan revision and bead creation; always explicitly transition.</>,
              ]} />
            </SubSection>

            <SubSection title="Getting Started">
              <P>The complete system is free and 100% open-source. A beginner with a credit card and a laptop can visit the wizard, follow step-by-step instructions to rent a VPS, paste one <code>curl|bash</code> command, type <code>onboard</code>, and start building with AI agents immediately.</P>

              <CodeBlock language="bash" code={`# 1. Rent a VPS (OVH or Contabo, ~$40-56/month, Ubuntu)
# 2. SSH in and run the one-liner
curl -fsSL https://agent-flywheel.com/install.sh | bash

# 3. Reconnect, then learn the workflow
onboard

# 4. Create your first project
acfs newproj my-first-project --interactive

# 5. Spawn agents and start building
ntm spawn my-first-project --cc=2 --cod=1 --gmi=1`} />

              <P>You don&apos;t even need to know much at all about computers; you just need the desire to learn and some grit and determination. And about $500/month for the subscriptions, plus another $50 or so for the cloud server.</P>

              <P>Once you get Claude Code up and running on the cloud server, you basically have an ultra competent friend who can help you with any other problems you encounter. And Jeffrey will personally answer your questions if you reach out on <a href="https://x.com/doodlestein" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">X</a> or on <a href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues" target="_blank" rel="noopener noreferrer" className="text-[#FF5500] hover:text-[#FFBD2E] underline underline-offset-4 decoration-[#FF5500]/30 hover:decoration-[#FFBD2E]/50 transition-colors">GitHub issues</a>.</P>

              <P highlight>If you want to change the entire direction of your life, it has truly never been easier. If you think you might want to do it, I really recommend just immersing yourself.</P>
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
    <section className="relative overflow-hidden pt-32 pb-20 md:pt-48 md:pb-32 bg-[#020408] border-b border-white/[0.04]">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-[600px] bg-[radial-gradient(ellipse_at_top,rgba(255,85,0,0.08),transparent_70%)]" />

      <div className="relative mx-auto text-center px-6 z-10 max-w-5xl">
        <div className="inline-flex items-center gap-3 rounded-full border border-[#FF5500]/20 bg-[#FF5500]/5 px-6 py-2 text-[0.7rem] font-black uppercase tracking-[0.3em] text-[#FF5500] mb-10 shadow-[0_0_20px_rgba(255,85,0,0.15)] backdrop-blur-xl">
          <Sparkles className="h-4 w-4" />
          The Official Methodology
        </div>

        <h1 className="text-5xl sm:text-6xl md:text-8xl font-black text-white tracking-tighter drop-shadow-2xl leading-[1.05]">
          The Agentic Coding <br/><span className="text-[#FF5500]">Flywheel</span>
        </h1>

        <p className="mx-auto mt-10 max-w-3xl text-xl sm:text-2xl text-zinc-400 leading-relaxed font-light">
          A comprehensive guide to creating extraordinary software by orchestrating swarms of AI agents using <Hl>exhaustive markdown plans</Hl>, <Hl>polished beads</Hl>, and the <Hl>Agent Flywheel stack</Hl>. Based on the methodology of Jeffrey Emanuel.
        </p>
      </div>
    </section>
  );
}

// =============================================================================
// FOOTER CTA
// =============================================================================
function FooterCTA() {
  return (
    <section className="relative overflow-hidden rounded-[3rem] border border-[#FF5500]/20 bg-[#0A0D14] py-24 md:py-32 my-32 shadow-[0_50px_100px_-20px_rgba(255,85,0,0.15)] group">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full bg-[radial-gradient(ellipse_at_center,rgba(255,85,0,0.05),transparent_70%)] opacity-0 group-hover:opacity-100 transition-opacity duration-1000" />

      <div className="relative mx-auto text-center px-6 z-10">
        <div className="inline-flex items-center gap-3 rounded-full border border-[#FF5500]/30 bg-[#FF5500]/10 px-6 py-2 text-[0.7rem] font-black uppercase tracking-[0.3em] text-[#FF5500] mb-10 shadow-inner">
          <Rocket className="h-4 w-4" />
          Ready to Start?
        </div>

        <h2 className="text-4xl sm:text-5xl md:text-6xl font-black text-white tracking-tighter drop-shadow-2xl">
          Get the Flywheel <span className="text-[#FF5500]">Stack</span>
        </h2>

        <p className="mx-auto mt-8 max-w-2xl text-lg text-zinc-400 leading-relaxed font-light">
          One command installs all 11 tools, three AI coding agents, and the complete environment.
          <br/><strong>30 minutes to fully configured.</strong>
        </p>

        <div className="mt-12 flex justify-center">
          <a
            href="/wizard/os-selection"
            className="inline-flex items-center justify-center rounded-2xl bg-[#FF5500] px-8 py-4 text-sm font-black text-black uppercase tracking-widest transition-all hover:bg-[#FFBD2E] hover:shadow-[0_0_40px_rgba(255,189,46,0.4)] hover:-translate-y-1 active:scale-95"
          >
            Launch the Setup Wizard
          </a>
        </div>
      </div>
    </section>
  );
}
