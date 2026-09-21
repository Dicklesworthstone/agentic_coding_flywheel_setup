"use client";

import {
  AlertTriangle,
  BarChart3,
  CheckCircle,
  GitBranch,
  PackageCheck,
  Shield,
  Zap,
} from "lucide-react";
import {
  CodeBlock,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function CiCdLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Build automated quality gates using UBS, Beads, and DSR so bugs from agent-generated code
        never reach production.
      </GoalBanner>

      {/* Section 1: Why CI/CD for Agents */}
      <Section
        title="Why CI/CD for Agent Code?"
        icon={<GitBranch className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          AI coding agents write code fast but make{" "}
          <Highlight>predictable classes of mistakes</Highlight>: unclosed resources, missing error
          handling, hardcoded secrets, and stale imports. Automated quality gates catch these before
          they ship.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="UBS Scanner"
              description="1000+ bug patterns across 9 languages"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Beads Tracking"
              description="Export findings as trackable issues"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<PackageCheck className="h-5 w-5" />}
              title="DSR Releases"
              description="Build releases locally when CI is throttled"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<CheckCircle className="h-5 w-5" />}
              title="Pre-Commit Hooks"
              description="Block bad code before it enters git"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: UBS as Quality Gate */}
      <Section title="UBS Quality Gate" icon={<Shield className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          UBS detects 1000+ bug patterns that AI agents commonly produce. Run it on every commit and
          in CI pipelines.
        </Paragraph>

        <CodeBlock
          code={`# Scan only staged files (fast pre-commit check)
ubs --staged

# Scan working tree changes vs HEAD
ubs --diff

# CI mode: fail the build on warnings
ubs . --fail-on-warning

# Output SARIF for GitHub Code Scanning
ubs . --format=sarif > results.sarif

# Focus on specific bug categories
ubs . --category=resource-lifecycle
ubs . --category=security

# Generate an HTML report for review
ubs . --html-report=scan-results.html

# Compare against a baseline (only show new bugs)
ubs . --comparison=baseline.json`}
          filename="UBS Commands"
        />

        <TipBox variant="tip">
          Use <code>ubs --staged</code> in a pre-commit hook so agents can&apos;t commit code with
          known bugs. The scan runs in under 2 seconds for most projects.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Pre-Commit Hook Setup */}
      <Section title="Pre-Commit Hook" icon={<AlertTriangle className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Wire UBS into your git hooks so every commit is automatically scanned.
        </Paragraph>

        <CodeBlock
          code={`#!/bin/bash
# .git/hooks/pre-commit (or .githooks/pre-commit)

# Run UBS on staged files only
if command -v ubs &>/dev/null; then
  echo "Running UBS scan on staged files..."
  ubs --staged --fail-on-warning
  if [ $? -ne 0 ]; then
    echo "UBS found issues. Fix them before committing."
    echo "Run 'ubs --staged' to see details."
    exit 1
  fi
fi

# DCG is separate: it runs as a Claude Code hook, not a Git hook.`}
          filename=".git/hooks/pre-commit"
        />

        <TipBox variant="info">
          UBS supports inline suppression with <code># ubs:ignore</code> comments for intentional
          false positives. Use sparingly.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Beads Integration */}
      <Section title="Export to Beads" icon={<BarChart3 className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          UBS can export Beads-compatible JSONL so you can review findings and turn the high-signal
          ones into tracked issues.
        </Paragraph>

        <CodeBlock
          code={`# Export UBS findings as Beads-compatible JSONL
ubs . --beads-jsonl findings.jsonl

# Review a few findings first
head -n 3 findings.jsonl

# Create the findings you want to track as real issues
br create --title "Fix UBS finding: resource leak in worker pool" --labels quality,ubs --priority 1
br create --title "Fix UBS finding: missing auth error handling" --labels quality,ubs --priority 1

# Now use BV to triage the findings
bv --robot-triage
# → Prioritize the new quality issues alongside your regular work

# Track scan results over time
ubs . --format=json > scans/$(date +%Y%m%d).json
ubs . --comparison=scans/20260310.json
# → Shows only NEW bugs since the baseline`}
          filename="Beads Export"
        />
      </Section>

      <Divider />

      {/* Section 5: DSR for Local Releases */}
      <Section title="DSR: Local Releases" icon={<PackageCheck className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          When GitHub Actions is throttled or your CI is overloaded, DSR lets you build artifacts
          locally and then upload a GitHub release from the verified build output.
        </Paragraph>

        <CodeBlock
          code={`# Build artifacts locally
dsr build ntm

# Build only one target
dsr build ntm --target linux/amd64

# Build a tagged version explicitly
dsr build ntm --version 1.2.3

# Upload the verified artifacts as a draft release
dsr release ntm 1.2.3 --draft

# Verify an existing release later
dsr release verify ntm 1.2.3`}
          filename="DSR Commands"
        />

        <TipBox variant="warning">
          Run <code>dsr build &lt;tool&gt;</code> first to verify the artifact set, then publish
          with <code>dsr release &lt;tool&gt; &lt;version&gt; --draft</code> before creating a final
          release.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Complete Pipeline */}
      <Section title="Complete Pipeline" icon={<Zap className="h-5 w-5" />} delay={0.35}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/30">
            <span className="text-red-400 font-semibold">Pre-Commit</span>
            <p className="text-white/80 text-sm mt-1">
              UBS --staged catches bugs before they enter git
            </p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Post-Commit</span>
            <p className="text-white/80 text-sm mt-1">UBS findings exported to Beads for triage</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">CI Pipeline</span>
            <p className="text-white/80 text-sm mt-1">
              SARIF output for GitHub Code Scanning integration
            </p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">Release</span>
            <p className="text-white/80 text-sm mt-1">
              DSR builds releases locally when CI is unavailable
            </p>
          </div>
        </div>
      </Section>
    </div>
  );
}
