'use client';

import {
  ShieldCheck,
  Shield,
  Users,
  Key,
  Layers,
  ClipboardList,
  ArrowRight,
} from 'lucide-react';
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  FeatureCard,
  FeatureGrid,
} from './lesson-components';

export function SecurityLayersLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand the three-layer security model that makes agent autonomy safe
        — DCG blocks dangerous commands, SLB gates risky operations behind peer
        review, and CAAM prevents credential exposure.
      </GoalBanner>

      {/* Section 1: Defense in Depth */}
      <Section title="Defense in Depth" icon={<ShieldCheck className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Single safety measures fail. The flywheel uses <Highlight>three
          independent layers</Highlight> so that no single point of failure can
          let a dangerous operation through.
        </Paragraph>

        <div className="mt-6 space-y-3">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <ArrowRight className="h-4 w-4 text-emerald-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-emerald-400">Layer 1: DCG</strong> — Mechanical, sub-millisecond pattern matching blocks known-bad commands
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <ArrowRight className="h-4 w-4 text-amber-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-amber-400">Layer 2: SLB</strong> — Human-in-the-loop approval for commands that are dangerous but sometimes needed
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <ArrowRight className="h-4 w-4 text-blue-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-blue-400">Layer 3: CAAM</strong> — Credential rotation and isolation so compromised agents can&apos;t drain API keys
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
      <Section title="Layer 1: DCG — Mechanical Enforcement" icon={<Shield className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          DCG is a Claude Code hook that runs <Highlight>before every command
          execution</Highlight>. It uses ast-grep internally for structural
          pattern matching, operating at sub-millisecond latency — agents
          don&apos;t even notice it&apos;s there.
        </Paragraph>

        <CodeBlock
          code={`# DCG blocks destructive commands automatically
# Agent tries: rm -rf /
# → BLOCKED: filesystem.recursive_delete

# DCG understands command STRUCTURE, not just strings
dcg test "rm -rf /" --explain
# → BLOCKED: Root path deletion

dcg test "rm -rf /tmp/build" --explain
# → ALLOWED: Scoped to /tmp (not root)

dcg test "git push --force origin main" --explain
# → BLOCKED: Force push to protected branch

dcg test "git push --force origin feature-x" --explain
# → ALLOWED: Force push to feature branch

# DCG packs (rule bundles)
dcg packs --enabled
# → git-safety, filesystem-safety, database-safety, k8s-safety

# Health check
dcg doctor --format json`}
          filename="DCG Pattern Matching"
        />

        <TipBox variant="tip">
          DCG has zero false positives because it uses structural pattern
          matching via ast-grep. It understands that{' '}
          <code className="text-emerald-300">rm -rf /tmp/build</code> is scoped
          while <code className="text-red-300">rm -rf /</code> is destructive.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Layer 2: SLB — Two-Person Rule */}
      <Section title="Layer 2: SLB — Two-Person Rule" icon={<Users className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          For commands that are <Highlight>sometimes needed but always
          dangerous</Highlight>, SLB enforces a two-person rule. One agent
          creates a launch request, and a human (or second agent) must approve
          before execution.
        </Paragraph>

        <CodeBlock
          code={`# Initialize SLB in a project
slb init

# Agent 1 wants to force-push (DCG would normally block)
slb request "git push --force origin main" --reason "Rewrite history on my feature branch"
# → Launch request created: slb-a7f3

# Agent 1 sees:
# ⚠️ CRITICAL: Requires approval before execution

# Human reviews and approves
slb approve slb-a7f3

# Now the command can execute
slb execute slb-a7f3

# Policies for automated workflows
slb config set policy auto_reject     # Reject all by default
slb config set policy auto_approve_warn  # Auto-approve with warning

# Watch agent activity in real-time
slb watch --session-id my-agent
# → Live stream of all commands the agent tries`}
          filename="SLB Workflow"
        />

        <TipBox variant="warning">
          SLB is for commands that DCG blocks but you actually need to run. The
          workflow is: DCG blocks → create SLB request → peer reviews → approved
          → execute. Never bypass DCG without SLB review.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Layer 3: CAAM — Credential Isolation */}
      <Section title="Layer 3: CAAM — Credential Isolation" icon={<Key className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          CAAM manages <Highlight>multiple API provider accounts</Highlight> with
          automatic rotation on rate limits. This prevents a single compromised
          or rate-limited key from stopping all agents.
        </Paragraph>

        <CodeBlock
          code={`# List all configured accounts
caam list
# → claude-1 (active, 847/1000 requests)
# → claude-2 (standby, 12/1000 requests)
# → codex-1 (active, 230/500 requests)

# Switch active account
caam switch claude-2

# Auto-rotate when rate limited
caam config set auto-rotate true
caam config set cooldown-minutes 15

# Add a new account
caam add claude-3 --provider anthropic --key-file ~/.keys/claude3

# Check rate limit status
caam status --all
# → Shows usage, remaining quota, cooldown timers

# In agent swarms, each agent gets a different account
# Agent 1 → claude-1
# Agent 2 → claude-2
# Agent 3 → codex-1
# No single account gets overwhelmed`}
          filename="CAAM Account Management"
        />

        <TipBox variant="tip">
          CAAM&apos;s auto-rotation means agent swarms can run for hours without
          hitting rate limits. When one account reaches its quota, CAAM
          seamlessly switches to the next available account.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: How the Layers Interact */}
      <Section title="How the Layers Interact" icon={<Layers className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          When an agent runs a command, it passes through each security layer in
          sequence. Here is the <Highlight>decision flow</Highlight>:
        </Paragraph>

        <div className="mt-6 space-y-3">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 text-xs font-bold">1</span>
            <span className="text-white/90 text-sm">
              Agent issues command → <strong className="text-emerald-400">DCG intercepts</strong>
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 text-xs font-bold">2</span>
            <span className="text-white/90 text-sm">
              DCG pattern match → <strong className="text-emerald-400">Safe?</strong> → Execute immediately
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-red-500/10 border border-red-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-red-500/20 text-red-400 text-xs font-bold">3</span>
            <span className="text-white/90 text-sm">
              DCG pattern match → <strong className="text-red-400">Dangerous?</strong> → Block
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-amber-500/20 text-amber-400 text-xs font-bold">4</span>
            <span className="text-white/90 text-sm">
              Blocked but needed? → <strong className="text-amber-400">SLB request</strong> → Peer review → Execute or reject
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-blue-500/20 text-blue-400 text-xs font-bold">5</span>
            <span className="text-white/90 text-sm">
              API call? → <strong className="text-blue-400">CAAM selects account</strong> → Rate limited? → Auto-rotate
            </span>
          </div>
        </div>

        <CodeBlock
          code={`# Real scenario: Agent needs to drop and recreate a test database

# Step 1: Agent tries "DROP DATABASE test_db"
# → DCG: BLOCKED (sql.destructive_ddl)

# Step 2: Agent creates SLB request
slb request "DROP DATABASE test_db" --reason "Recreate the throwaway test DB"
# → slb-b2e9 created, awaiting approval

# Step 3: Human reviews, sees it's a test DB, approves
slb approve slb-b2e9

# Step 4: Command executes safely through SLB
slb execute slb-b2e9

# Step 5: Agent continues with API calls via CAAM
# → CAAM routes to claude-2 (claude-1 is cooling down)`}
          filename="Real Scenario"
        />
      </Section>

      <Divider />

      {/* Section 6: Audit Trail */}
      <Section title="Audit Trail" icon={<ClipboardList className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          All three layers produce <Highlight>audit logs</Highlight>, giving you
          a complete picture of every security decision made during agent
          operation.
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
            <strong className="text-white">Three independent layers, each
            catching what the others miss.</strong> DCG for speed, SLB for
            judgment, CAAM for resource protection. Together they make it safe
            to give agents real autonomy.
          </p>
        </div>
      </Section>
    </div>
  );
}
