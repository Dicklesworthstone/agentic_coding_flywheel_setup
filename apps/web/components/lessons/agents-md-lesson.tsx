"use client";

import {
  FileText,
  Star,
  Wrench,
  AlertTriangle,
  Layers,
  Rocket,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  CommandList,
  FeatureCard,
  FeatureGrid,
} from "./lesson-components";

export function AgentsMdLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Write AGENTS.md files that transform any project into an agent-ready
        workspace — the single most important file for AI coding agent
        onboarding.
      </GoalBanner>

      {/* Section 1: Why AGENTS.md? */}
      <Section
        title="Why AGENTS.md?"
        icon={<FileText className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          Every AI agent —{" "}
          <Highlight>Claude Code, Codex, Antigravity</Highlight> — reads AGENTS.md
          at session start. It&apos;s the{" "}
          <Highlight>&quot;API contract&quot;</Highlight> between you and the
          agents working in your project. Without it, agents guess conventions,
          make wrong assumptions, and produce inconsistent code.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Universal Standard"
              description="All major AI coding agents read AGENTS.md"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Rocket className="h-5 w-5" />}
              title="Onboarding Speed"
              description="Agents become productive in seconds"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Wrench className="h-5 w-5" />}
              title="Convention Enforcement"
              description="Rules applied consistently across sessions"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="Multi-Agent Consistency"
              description="Every agent follows the same patterns"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: The Gold Standard Template */}
      <Section
        title="The Gold Standard Template"
        icon={<Star className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          Here is the <Highlight>canonical structure</Highlight> based on
          real-world battle-tested templates. Every AGENTS.md should follow this
          general shape:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# AGENTS.md — Project Name

## RULE 0 - THE FUNDAMENTAL OVERRIDE PREROGATIVE
If I tell you to do something, even if it goes against what
follows below, YOU MUST LISTEN TO ME. I AM IN CHARGE, NOT YOU.

## Toolchain
- Language: Rust / TypeScript / Python
- Build: rch exec -- cargo build --release
- Test: rch exec -- cargo test
- Lint: rch exec -- cargo clippy -- -D warnings

## Architecture
Brief description of modules, key files, data flow.

## Conventions
- Error handling: use thiserror, not anyhow
- Tests go in tests/ directory
- API follows REST conventions

## Safety Rules
- DCG is installed — do not bypass it
- Run ubs before every commit
- Never force-push to main

## Agent Coordination
- Check agent mail: am check-inbox
- Reserve files before editing
- Update beads when completing tasks`}
            language="markdown"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Keep AGENTS.md under 200 lines. Agents have limited context
            windows — every unnecessary line wastes tokens that could hold your
            actual code.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 3: Project-Specific Sections */}
      <Section
        title="Project-Specific Sections"
        icon={<Wrench className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          Customize your AGENTS.md for your{" "}
          <Highlight>tech stack and workflows</Highlight>. Here&apos;s what a
          Rust project section looks like:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`## Rust-Specific

### Build & Test
rch exec -- cargo build --release    # Always release mode for benchmarks
rch exec -- cargo test -- --nocapture  # Show println! output in tests
rch exec -- cargo clippy -- -D warnings  # Treat warnings as errors

### Workspace Layout
\u251C\u2500\u2500 crates/
\u2502   \u251C\u2500\u2500 core/        # Library crate (no binary)
\u2502   \u251C\u2500\u2500 cli/         # Binary crate (depends on core)
\u2502   \u2514\u2500\u2500 server/      # HTTP server (depends on core)

### Dependencies
- tokio: async runtime (use #[tokio::main])
- serde: serialization (always derive Serialize, Deserialize)
- tracing: logging (not log or println!)

### Generated Files \u2014 NEVER Edit
- src/generated/     # All files auto-generated from schema
- Modify the generator in build.rs, not the output`}
            language="markdown"
          />
        </div>

        <Paragraph>
          And here&apos;s a <Highlight>Next.js project</Highlight> example:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`## Next.js-Specific

### Framework
- Next.js 16 App Router (NOT Pages Router)
- Runtime: Bun (never npm/yarn/pnpm)
- CSS: Tailwind CSS 4.x (not styled-components)

### File Conventions
- Pages: app/route/page.tsx
- Components: components/feature-name.tsx
- Server actions: app/actions/
- API routes: app/api/route/route.ts`}
            language="markdown"
          />
        </div>
      </Section>

      <Divider />

      {/* Section 4: Common Mistakes */}
      <Section
        title="Common Mistakes"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          What <Highlight>NOT</Highlight> to put in AGENTS.md. These
          anti-patterns actively harm agent performance:
        </Paragraph>

        <div className="mt-4 space-y-3">
          <Paragraph>
            <strong>Too long (&gt;500 lines)</strong> — agents compact context
            and lose later sections.
          </Paragraph>
          <Paragraph>
            <strong>Duplicating README content</strong> — link to it instead of
            copying.
          </Paragraph>
          <Paragraph>
            <strong>Vague rules</strong> (&quot;write good code&quot;) — be
            specific (&quot;use thiserror for error types&quot;).
          </Paragraph>
          <Paragraph>
            <strong>Missing safety rules</strong> — agents will run destructive
            commands without explicit prohibitions.
          </Paragraph>
          <Paragraph>
            <strong>No build/test commands</strong> — agents will guess and get
            them wrong.
          </Paragraph>
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# BAD \u2014 vague, wastes tokens
## Code Quality
Please write clean, well-documented, maintainable code
following industry best practices and design patterns.

# GOOD \u2014 specific, actionable
## Code Quality
- Functions > 50 lines must be split
- No unwrap() in library code (use ? operator)
- Every public function needs a /// doc comment`}
            language="markdown"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <strong>The #1 mistake is making AGENTS.md too long.</strong> Claude
            Code compacts context after ~100k tokens. If your AGENTS.md is 800
            lines, the bottom half gets lost.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 5: Fleet Standardization */}
      <Section
        title="Fleet Standardization"
        icon={<Layers className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          How to maintain <Highlight>consistent AGENTS.md across 20+
          projects</Highlight>. Use a gold standard template and customize
          per-project:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Keep a reference template
cat ~/projects/frankensearch/AGENTS.md  # Gold standard

# Standardize across fleet with RU
ru list --paths | while read -r repo; do
  # Compare each project's AGENTS.md to template
  diff <(head -50 "$repo/AGENTS.md") <(head -50 ~/reference/AGENTS.md)
done

# Use agent-sweep for mass updates
ru agent-sweep --prompt "Update AGENTS.md to match
the gold standard template structure while preserving
all project-specific sections"`}
            language="bash"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            When standardizing, <strong>ALWAYS</strong> preserve
            project-specific sections. The boilerplate sections (Rule 0, Safety,
            Git conventions) should match the template, but architecture and
            conventions are unique to each project.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 6: Auto-Generation with newproj */}
      <Section
        title="Auto-Generation with newproj"
        icon={<Rocket className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          The ACFS <Highlight>newproj</Highlight> wizard auto-generates
          AGENTS.md for new projects. It detects tech stacks and generates
          appropriate sections automatically:
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "acfs newproj",
                description:
                  "TUI wizard guides you through project setup",
              },
              {
                command: "# Auto-detects: package.json, Cargo.toml, pyproject.toml",
                description:
                  "Scans for known build files and configures the right language sections",
              },
              {
                command: "# Generates AGENTS.md with 15 sections",
                description:
                  "Required + optional sections based on detected tech stack",
              },
              {
                command: "# Includes DCG, UBS, and Agent Mail config",
                description:
                  "Safety rules, build commands, and agent coordination baked in",
              },
            ]}
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            <strong>Every new project starts agent-ready.</strong> No manual
            AGENTS.md writing needed for standard stacks.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}
