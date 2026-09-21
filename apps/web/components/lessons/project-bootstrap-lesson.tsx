"use client";

import { CheckSquare, FileText, FolderPlus, Rocket, Shield, Users } from "lucide-react";
import {
  CodeBlock,
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
    <div className="space-y-8">
      <GoalBanner>
        Set up a new project for multi-agent development in 5 minutes with issue tracking, safety
        hooks, quality scanning, and agent coordination.
      </GoalBanner>

      {/* Section 1: Overview */}
      <Section title="The Bootstrap Checklist" icon={<Rocket className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Starting a new project with the flywheel means setting up
          <Highlight> six foundational layers</Highlight> that protect your code, track your work,
          and enable agent collaboration from day one.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<FolderPlus className="h-5 w-5" />}
              title="Issue Tracking"
              description="Beads for dependency-aware task management"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safety Hooks"
              description="DCG + SLB for pre-execution protection"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<CheckSquare className="h-5 w-5" />}
              title="Quality Gates"
              description="UBS for static analysis on every commit"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Users className="h-5 w-5" />}
              title="Agent Coordination"
              description="AGENTS.md + Agent Mail for multi-agent work"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Initialize Issue Tracking */}
      <Section title="1. Issue Tracking" icon={<FolderPlus className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Initialize Beads to get dependency-aware issue tracking from the start.
        </Paragraph>

        <CodeBlock
          code={`# Initialize beads in your project
cd /your/project
br init

# Create your first issues
SETUP_ID=$(br create "Set up project structure" --labels setup --silent)
API_ID=$(br create "Implement core API" --labels backend --silent)
WEB_ID=$(br create "Build frontend" --labels frontend --silent)

# Record the dependency chain
br dep add "$API_ID" "$SETUP_ID"
br dep add "$WEB_ID" "$API_ID"

# View the dependency graph
bv --robot-triage
# → Shows issues in priority order based on dependencies`}
          filename="Issue Tracking Setup"
        />

        <TipBox variant="tip">
          Define dependencies early. BV uses them to compute which issues should be worked on first,
          preventing agents from starting blocked work.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Install Safety Hooks */}
      <Section title="2. Safety Hooks" icon={<Shield className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Install DCG to block destructive commands and SLB for two-person approval on risky
          operations.
        </Paragraph>

        <CodeBlock
          code={`# Install DCG hook for Claude Code
dcg install
dcg doctor  # Verify installation

# Test that it works
dcg test "rm -rf /" --explain
# → BLOCKED: filesystem.recursive_delete

# Initialize SLB for two-person rule
slb init

# Test SLB classification
slb check "git push --force origin main"
# → CRITICAL: requires 2 approvals`}
          filename="Safety Setup"
        />

        <TipBox variant="warning">
          Always install DCG before giving agents access to your project. Without it, a single bad
          command can destroy uncommitted work.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Set Up Quality Scanning */}
      <Section title="3. Quality Gates" icon={<CheckSquare className="h-5 w-5" />} delay={0.25}>
        <Paragraph>Install UBS and wire it into git hooks so every commit is scanned.</Paragraph>

        <CodeBlock
          code={`# Run a baseline scan
ubs .
# → Shows existing issues in the codebase

# Save baseline for future comparison
ubs . --format=json > .ubs-baseline.json

# Set up pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if command -v ubs &>/dev/null; then
  ubs --staged --fail-on-warning || exit 1
fi
EOF
chmod +x .git/hooks/pre-commit

# Verify the hook works
git add . && git commit -m "test"
# → UBS runs automatically before the commit`}
          filename="Quality Gate Setup"
        />
      </Section>

      <Divider />

      {/* Section 5: AGENTS.md Convention */}
      <Section title="4. AGENTS.md" icon={<FileText className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Create an <Highlight>AGENTS.md</Highlight> file that tells AI agents how to work in your
          project. This is the single most important file for multi-agent coordination.
        </Paragraph>

        <CodeBlock
          code={`# AGENTS.md — Guidelines for AI Coding Agents

## Project Overview
Brief description of what the project does.

## Architecture
Key architectural decisions agents need to know.

## Conventions
- Use TypeScript strict mode
- Tests go in __tests__/ directories
- API routes follow REST conventions

## Agent Coordination
- Check agent mail before starting: am check-inbox --project /your/project --agent <name>
- Reserve files before editing: am file_reservations reserve --exclusive /your/project <name> src/api.ts
- Close beads when completing tasks: br close <id> --reason "Completed"

## Safety Rules
- DCG is installed — do not bypass it
- Run ubs --staged before every commit
- Never force-push to main`}
          filename="AGENTS.md Template"
        />

        <TipBox variant="info">
          Every AI agent (Claude, Codex, Antigravity) reads AGENTS.md at session start. Keep it
          concise — agents have limited context windows.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Agent Mail Registration */}
      <Section title="5. Agent Coordination" icon={<Users className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          Start an Agent Mail session so the project, agent identity, inbox, and reservations are
          all wired up correctly.
        </Paragraph>

        <CommandList
          commands={[
            {
              command:
                'am macros start-session --project /your/project --program codex-cli --model gpt-5 --task "bootstrap"',
              description: "Ensure the project exists and register an agent session",
            },
            {
              command: "am check-inbox --project /your/project --agent <name>",
              description: "Check for unread messages from other agents",
            },
            {
              command: "am file_reservations reserve --exclusive /your/project <name> src/api.ts",
              description: "Reserve a file for exclusive editing",
            },
            {
              command:
                'am mail send --project /your/project --from <name> --to other-agent --subject "project initialized" --body "Ready to start"',
              description: "Notify another agent that the project is ready",
            },
          ]}
        />

        <div className="mt-6 p-4 rounded-lg bg-white/[0.03] border border-white/[0.08]">
          <p className="text-sm text-white/70">
            <strong className="text-white">Quick bootstrap summary:</strong> <code>br init</code> →{" "}
            <code>dcg install</code> → <code>ubs .</code> → create AGENTS.md →{" "}
            <code>am macros start-session</code>. Five commands, five minutes, fully protected
            multi-agent development environment.
          </p>
        </div>
      </Section>
    </div>
  );
}
