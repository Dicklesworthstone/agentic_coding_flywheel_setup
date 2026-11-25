"use client";

import { ArrowRight, ClipboardList, Key, Layers, Shield, ShieldCheck, Users } from "lucide-react";
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

export function SecurityLayersLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand the three-layer security model that makes agent autonomy safe — DCG blocks
        dangerous commands, SLB gates risky operations behind peer review, and CAAM prevents
        credential exposure.
      </GoalBanner>

      {/* Section 1: Defense in Depth */}
      <Section title="Defense in Depth" icon={<ShieldCheck className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Single safety measures fail. The flywheel uses{" "}
          <Highlight>three independent layers</Highlight> so that no single point of failure can let
          a dangerous operation through.
        </Paragraph>

        <div className="mt-6 space-y-3">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <ArrowRight className="h-4 w-4 text-emerald-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-emerald-400">Layer 1: DCG</strong> — Mechanical,
              sub-millisecond pattern matching blocks known-bad commands
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <ArrowRight className="h-4 w-4 text-amber-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-amber-400">Layer 2: SLB</strong> — Human-in-the-loop approval
              for commands that are dangerous but sometimes needed
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <ArrowRight className="h-4 w-4 text-blue-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-blue-400">Layer 3: CAAM</strong> — Credential rotation and
              isolation so one exhausted or compromised account can&apos;t stall every agent
            </span>
          </div>
        </div>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="DCG"
              description="Block destructive commands mechanically"
              gradient="from-emerald-500/20 to-green-500/20"
            />
            <FeatureCard
              icon={<Users className="h-5 w-5" />}
              title="SLB"
              description="Two-person rule for risky operations"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="CAAM"
              description="Credential isolation and rotation"
              gradient="from-blue-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="Combined"
              description="Each layer catches what others miss"
              gradient="from-violet-500/20 to-purple-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Layer 1: DCG — Mechanical Enforcement */}
      <Section
        title="Layer 1: DCG — Mechanical Enforcement"
        icon={<Shield className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          DCG is a pre-execution hook (Claude Code, Codex, Antigravity, and other agent CLIs) that
          runs <Highlight>before every command execution</Highlight>. It parses each command&apos;s
          structure (using ast-grep for embedded scripts) and checks it against its packs at
          sub-millisecond latency — agents don&apos;t even notice it&apos;s there.
        </Paragraph>

        <CodeBlock
          code={`# DCG blocks destructive commands automatically
# Agent tries: rm -rf /
# → BLOCKED: core.filesystem:rm-rf-root-home

# DCG understands command STRUCTURE, not just strings
dcg test "rm -rf /" --explain
# → BLOCKED: Root path deletion

dcg test "rm -rf /tmp/build" --explain
# → ALLOWED: Scoped to /tmp (not root)

dcg test "git push --force origin feature-x" --explain
# → BLOCKED: --force can overwrite remote history on any branch

dcg test "git push --force-with-lease origin feature-x" --explain
# → ALLOWED: the lease refuses to clobber commits you haven't seen

# DCG packs (rule bundles)
dcg packs --enabled
# → core.git, core.filesystem (always on), plus packs you enable

# Health check
dcg doctor --format json`}
          filename="DCG Pattern Matching"
        />

        <TipBox variant="tip">
          DCG keeps false positives low by looking at command structure instead of raw strings. It
          understands that <code className="text-emerald-300">rm -rf /tmp/build</code> is scoped
          while <code className="text-red-300">rm -rf /</code> is destructive.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Layer 2: SLB — Two-Person Rule */}
      <Section
        title="Layer 2: SLB — Two-Person Rule"
        icon={<Users className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          For commands that are <Highlight>sometimes needed but always dangerous</Highlight>, SLB
          enforces a two-person rule. One agent creates a launch request, and a human (or second
          agent) must approve before execution.
        </Paragraph>

        <CodeBlock
          code={`# Initialize SLB in a project
slb init

# Default "independent" policy refuses local approvals; opt in first
slb config set general.approval_policy same_host

# Every requester and reviewer works in an SLB session
slb session start --agent agent-1   # → prints the session ID and key

# Agent 1 wants to force-push (DCG would normally block)
slb request "git push --force origin feature-x" --reason "Rewrite history on my feature branch" -s <agent-1-id>
# → Launch request created: slb-a7f3

# Agent 1 sees:
# ⚠️ CRITICAL: needs 2 approvals before execution

# Each reviewer (human or another agent) approves from their own session
slb approve slb-a7f3 --session-id <reviewer-id> --session-key <reviewer-key>

# Once both approvals are in, the command can execute
slb execute slb-a7f3 -s <agent-1-id>

# Policy for unattended workflows
slb config set general.timeout_action auto_reject   # Reject if nobody reviews in time

# Reviewing agents stream pending requests
slb watch --session-id <reviewer-id> --json
# → NDJSON events for every request awaiting review`}
          filename="SLB Workflow"
        />

        <TipBox variant="warning">
          SLB is for commands that DCG blocks but you actually need to run. The workflow is: DCG
          blocks → create SLB request → peer reviews → approved → execute. Never bypass DCG without
          SLB review.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Layer 3: CAAM — Credential Isolation */}
      <Section
        title="Layer 3: CAAM — Credential Isolation"
        icon={<Key className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          CAAM manages <Highlight>multiple subscription logins per agent CLI</Highlight> with
          automatic rotation on rate limits. This prevents a single compromised or rate-limited
          account from stopping all agents.
        </Paragraph>

        <CodeBlock
          code={`# List saved profiles
caam ls

# Switch the active Claude account
caam activate claude personal@gmail.com

# Mark the exhausted account so rotation skips it
caam cooldown set claude/work@company.com --minutes 15

# Let caam pick the best available account
caam next claude

# Save a newly logged-in account
caam backup claude third@company.com

# Check live quota and reset times
caam limits claude

# In agent swarms, each agent runs in its own isolated profile
# caam exec claude agent-1 -- ...
# caam exec claude agent-2 -- ...
# No single account gets overwhelmed`}
          filename="CAAM Account Management"
        />

        <TipBox variant="tip">
          CAAM&apos;s auto-rotation means agent swarms can run for hours without hitting rate
          limits. When one account reaches its quota, CAAM seamlessly switches to the next available
          account.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: How the Layers Interact */}
      <Section title="How the Layers Interact" icon={<Layers className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          When an agent runs a command, it passes through each security layer in sequence. Here is
          the <Highlight>decision flow</Highlight>:
        </Paragraph>

        <div className="mt-6 space-y-3">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 text-xs font-bold">
              1
            </span>
            <span className="text-white/90 text-sm">
              Agent issues command → <strong className="text-emerald-400">DCG intercepts</strong>
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 text-xs font-bold">
              2
            </span>
            <span className="text-white/90 text-sm">
              DCG pattern match → <strong className="text-emerald-400">Safe?</strong> → Execute
              immediately
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-red-500/10 border border-red-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-red-500/20 text-red-400 text-xs font-bold">
              3
            </span>
            <span className="text-white/90 text-sm">
              DCG pattern match → <strong className="text-red-400">Dangerous?</strong> → Block
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-amber-500/20 text-amber-400 text-xs font-bold">
              4
            </span>
            <span className="text-white/90 text-sm">
              Blocked but needed? → <strong className="text-amber-400">SLB request</strong> → Peer
              review → Execute or reject
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-blue-500/20 text-blue-400 text-xs font-bold">
              5
            </span>
            <span className="text-white/90 text-sm">
              API call? → <strong className="text-blue-400">CAAM selects account</strong> → Rate
              limited? → Auto-rotate
            </span>
          </div>
        </div>

        <CodeBlock
          code={`# Real scenario: Agent needs to drop and recreate a test database

# Step 1: Agent tries "DROP DATABASE test_db"
# → DCG: BLOCKED (database.postgresql:drop-database)

# Step 2: Agent creates SLB request
slb request "DROP DATABASE test_db" --reason "Recreate the throwaway test DB" -s <agent-id>
# → slb-b2e9 created, awaiting approval (CRITICAL: 2 approvals)

# Step 3: Reviewers see it's a test DB and approve
slb approve slb-b2e9 --session-id <reviewer-id> --session-key <reviewer-key>

# Step 4: Command executes safely through SLB
slb execute slb-b2e9 -s <agent-id>

# Step 5: Agent continues with API calls via CAAM
# → CAAM routes to claude-2 (claude-1 is cooling down)`}
          filename="Real Scenario"
        />
      </Section>

      <Divider />

      {/* Section 6: Audit Trail */}
      <Section title="Audit Trail" icon={<ClipboardList className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          All three layers produce <Highlight>audit logs</Highlight>, giving you a complete picture
          of every security decision made during agent operation.
        </Paragraph>

        <CodeBlock
          code={`# DCG logs every block decision
dcg stats --days 1
# → Blocked/allowed/bypassed counts and the rules that fired

# SLB tracks every request, approval, and execution
slb history --json
# → Full history with who requested, who approved, when

# CAAM logs account switches and rate limit events
caam history --limit 50
# → Shows rotation events, usage spikes, cooldown periods

# Combined: full picture of agent safety
# "At 14:32, agent-3 tried 'rm -rf /data',
#  DCG blocked it, no SLB request created.
#  At 14:35, agent-1 hit rate limit on claude-1,
#  CAAM rotated to claude-2 in 12ms."`}
          filename="Audit Logs"
        />

        <div className="mt-6 rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl">
          <p className="text-white/80 text-sm leading-relaxed">
            <strong className="text-white">
              Three independent layers, each catching what the others miss.
            </strong>{" "}
            DCG for speed, SLB for judgment, CAAM for resource protection. Together they make it
            safe to give agents real autonomy.
          </p>
        </div>
      </Section>
    </div>
  );
}
