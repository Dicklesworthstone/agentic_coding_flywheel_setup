"use client";

import { CheckSquare, FileText, FolderPlus, Rocket, Users } from "lucide-react";
import Link from "next/link";
import {
  CommandList,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function ProjectBootstrapLesson() {
  return (
    <div className="space-y-8" data-testid="project-bootstrap-walkthrough">
      <GoalBanner>
        Create a working Python or TypeScript project, run its tests, and prepare the first
        task for your coding agent.
      </GoalBanner>

      <Section title="1. Start a new project" icon={<Rocket className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Use the guided project creator from an interactive terminal on your VPS. It needs
          a current ACFS installation with guided new-project support, Python 3, and Git.
          TypeScript starter checks also need Bun.
        </Paragraph>
        <CommandList commands={[
          {
            command: "acfs newproj --guided",
            description: "Choose a project name, destination, and Python or TypeScript starter",
          },
        ]} />
        <Paragraph>
          Pick a new project name inside an existing parent directory. The destination
          must be absent or empty. Keep your existing repositories separate; the guide
          creates a new project and does not migrate an existing one.
        </Paragraph>
        <TipBox variant="info">
          If your installed version does not recognize <code>--guided</code>, inspect{" "}
          <code>acfs newproj --help</code> and use instructions for that version. Need an
          ACFS environment first?{" "}
          <Link className="text-primary underline" href="/wizard/os-selection">
            Open the setup wizard
          </Link>.
        </TipBox>
        <FeatureGrid>
          <FeatureCard
            icon={<FolderPlus className="h-5 w-5" />}
            title="A local Git project"
            description="A repository on main with a README and gitignore"
            gradient="from-violet-500/20 to-purple-500/20"
          />
          <FeatureCard
            icon={<CheckSquare className="h-5 w-5" />}
            title="Working starter and tests"
            description="Python or TypeScript source, three tests, and a check script"
            gradient="from-emerald-500/20 to-teal-500/20"
          />
          <FeatureCard
            icon={<FileText className="h-5 w-5" />}
            title="Project instructions"
            description="AGENTS.md and a first task to review before starting an agent"
            gradient="from-blue-500/20 to-indigo-500/20"
          />
          <FeatureCard
            icon={<Users className="h-5 w-5" />}
            title="Optional coordination"
            description="Choose Beads and an existing Agent Mail service only when needed"
            gradient="from-amber-500/20 to-orange-500/20"
          />
        </FeatureGrid>
      </Section>

      <Divider />

      <Section title="2. Review the plan before creating files" icon={<FileText className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Answering questions creates nothing. The review screen lists the files, commands,
          optional remote operations, and private recovery-plan location. Choose what
          happens next:
        </Paragraph>
        <ul className="space-y-3 text-white/70">
          <li><code>details</code> shows the complete plan and exact file contents.</li>
          <li><code>save</code> saves only the private plan, without creating the project.</li>
          <li><code>create</code> saves the plan and applies the reviewed operations.</li>
          <li><code>cancel</code> or Enter at the review prompt exits without writing files.</li>
        </ul>
        <Paragraph>
          GitHub publication defaults to <Highlight>none</Highlight> for a local project.
          Explicitly selecting private or public creates a new GitHub repository and pushes
          one reviewed initial commit through your authenticated GitHub CLI. Optional
          repo_updater registration needs <code>ru</code> and updates its reviewed user
          configuration and state.
        </Paragraph>
        <Paragraph>
          Beads requires <code>br</code>. Agent Mail requires an already running service;
          the guide asks for its URL and a credential environment variable name, never the
          credential value. Choose these integrations only when those prerequisites are ready.
          Saving a plan does not contact the services.
        </Paragraph>
        <TipBox variant="info">
          If creation is interrupted, keep the saved plan and any partial project. Fix the
          reported problem and follow the printed apply or resume command with the same
          plan and ACFS version. A plan-only failure before project creation uses the
          first-apply command; interrupted work may require inspection before resuming.
        </TipBox>
      </Section>

      <Divider />

      <Section title="3. Verify the starter and read its instructions" icon={<CheckSquare className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          After successful creation, use the exact <code>cd</code> command printed for your
          chosen destination. Run the following commands from that project directory.
          Creation writes the tests but does not execute them.
        </Paragraph>
        <CommandList commands={[
          {
            command: "sh scripts/check.sh",
            description: "Run the three starter tests: Python standard library or Bun for TypeScript",
          },
          {
            command: "cat AGENTS.md",
            description: "Review the generated project policy before asking an agent to edit",
          },
          {
            command: "cat FIRST_AGENT_PROMPT.md",
            description: "Read the first task you will give to your chosen agent",
          },
        ]} />
        <Paragraph>
          Start one of the coding agents you installed from this same directory, sign in if
          needed, and give it the task from <Highlight>FIRST_AGENT_PROMPT.md</Highlight>.
          Confirm that it has read the project policy. If you have no coding agent installed,
          the starter and checks still work from your terminal.
        </Paragraph>
      </Section>

      <Divider />

      <Section title="4. Continue with the integrations you selected" icon={<Users className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          If you selected Beads, initialization is already part of the reviewed creation
          plan. Inspect the board before deciding on the first feature:
        </Paragraph>
        <CommandList commands={[
          {
            command: "br ready --json",
            description: "Only if Beads was selected: inspect available work without reinitializing it",
          },
        ]} />
        <Paragraph>
          If you selected Agent Mail, read the generated <Highlight>AGENT_MAIL.md</Highlight>,
          approve your client&apos;s project trust, check connectivity, and register a separate
          identity for each agent session. Native client configuration supports Claude Code,
          Codex, and Gemini. Configuration files alone do not prove a live connection.
        </Paragraph>
        <Paragraph>
          Extend the generated AGENTS.md as your project develops. DCG, SLB, and UBS are
          separate tools to configure when needed; this starter does not install or configure
          them. Review any existing Git hooks and hook configuration before adding checks.
          Run and review the project checks before staging the specific changes you intend
          to commit.
        </Paragraph>
        <div className="flex flex-wrap gap-4 text-sm">
          <Link className="inline-flex min-h-11 items-center text-primary underline" href="/learn/tools/beads">
            Beads reference
          </Link>
          <Link className="inline-flex min-h-11 items-center text-primary underline" href="/learn/tools/agent-mail">
            Agent Mail reference
          </Link>
          <Link className="inline-flex min-h-11 items-center text-primary underline" href="/learn/tools/ubs">
            UBS reference
          </Link>
          <Link
            className="inline-flex min-h-11 items-center text-primary underline"
            href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/main/docs/operations/guided-first-project.md"
            target="_blank"
            rel="noopener noreferrer"
          >
            Full guide and recovery instructions
          </Link>
        </div>
      </Section>
    </div>
  );
}
