"use client";

import {
  Activity,
  Stethoscope,
  Clock,
  LayoutDashboard,
  Gauge,
  ClipboardCheck,
  CheckCircle2,
  Shield,
} from "lucide-react";
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
} from "./lesson-components";

export function AcfsDoctorLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Keep your ACFS environment healthy with doctor checks, automated nightly
        updates, and workspace management — the maintenance tools that prevent
        environment drift.
      </GoalBanner>

      {/* Section 1: Why Maintenance Matters */}
      <Section
        title="Why Maintenance Matters"
        icon={<Activity className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          AI agents depend on correctly installed tools. A broken{" "}
          <Highlight>PATH</Highlight>, missing binary, or stale config can waste
          hours of debugging time. ACFS includes three maintenance systems that
          catch problems early, before they derail your work.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Stethoscope className="h-5 w-5" />}
              title="acfs doctor"
              description="Health checks for every installed component"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="acfs nightly"
              description="Automated updates while you sleep"
              gradient="from-indigo-500/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<LayoutDashboard className="h-5 w-5" />}
              title="acfs workspace"
              description="Agent-ready tmux sessions"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Gauge className="h-5 w-5" />}
              title="SRPS"
              description="System resource protection under load"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: acfs doctor */}
      <Section
        title="acfs doctor"
        icon={<Stethoscope className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          The <Highlight>acfs doctor</Highlight> command runs health checks on
          every component installed by ACFS. It checks binary existence, version
          constraints, and configuration validity — giving you a quick snapshot
          of your entire environment.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Run full system health check
acfs doctor

# Example output:
# ✓ zsh ........................ 5.9
# ✓ oh-my-zsh ................. installed
# ✓ bun ....................... 1.2.1
# ✓ uv ........................ 0.5.2
# ✗ rust ...................... NOT FOUND
# ✓ go ........................ 1.23.0
# ✓ tmux ...................... 3.5a
# ✓ claude-code ............... 1.0.32
# ✓ ntm ....................... 2.1.0
# ...
#
# Results: 68/70 checks passed, 2 issues found

# Auto-fix discovered issues
acfs doctor --fix

# JSON output for programmatic use
acfs doctor --format json

# Check a specific category
acfs doctor --category agents
acfs doctor --category tools
acfs doctor --category shell`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Run <code className="text-amber-300">acfs doctor</code> at the start
            of every session. It takes under 5 seconds and catches issues before
            they waste hours of agent time.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 3: Nightly Auto-Updates */}
      <Section
        title="Nightly Auto-Updates"
        icon={<Clock className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          A systemd timer runs updates automatically every night. It updates tool
          binaries, pulls latest configs, and runs doctor afterward to verify
          everything is still healthy.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check nightly update status
systemctl status acfs-nightly.timer

# View last update log
journalctl -u acfs-nightly.service --since yesterday

# Trigger a manual update now
acfs update

# What the nightly update does:
# 1. Pull latest ACFS configs
# 2. Update Agent Flywheel stack tools (cargo install)
# 3. Update global Bun packages
# 4. Update Go binaries
# 5. Run acfs doctor to verify
# 6. Log results to journal

# Disable nightly updates (not recommended)
sudo systemctl disable acfs-nightly.timer

# Re-enable
sudo systemctl enable --now acfs-nightly.timer`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            Don&apos;t disable nightly updates unless you have a specific reason.
            Tool version drift between agents causes subtle, hard-to-debug
            failures.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 4: Workspace Setup */}
      <Section
        title="Workspace Setup"
        icon={<LayoutDashboard className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          ACFS creates a ready-to-use workspace with a tmux session and project
          folder structure. Everything is configured so you can SSH in and
          immediately start working.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# The workspace is created during installation:
# ~/workspace/          — Default project directory
# ~/.acfs/              — ACFS configuration
# ~/.acfs/tmux.conf     — Tmux configuration
# ~/.acfs/zshrc         — Shell configuration

# The default tmux session structure:
# Session "main":
#   Window 0: "editor"  — Your primary workspace
#   Window 1: "agents"  — Agent terminals
#   Window 2: "logs"    — Log monitoring

# Reconnect to workspace after SSH
tmux attach -t main

# Or use NTM for named sessions
ntm spawn coding --agents cc,cod --project ~/workspace/myproject`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            The workspace is designed so you can SSH in, run{" "}
            <code className="text-amber-300">tmux attach</code>, and immediately
            start working. Everything persists across disconnections.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 5: SRPS: Resource Protection */}
      <Section
        title="SRPS: Resource Protection"
        icon={<Gauge className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          The <Highlight>System Resource Protection Service</Highlight> prevents
          agents from overwhelming the VPS. It monitors CPU, memory, disk, and
          process count, taking automatic action when thresholds are exceeded.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check current system resource status
srps status

# What SRPS monitors:
# - CPU usage > 90% for > 60 seconds → throttle agents
# - Memory usage > 85% → warn, > 95% → emergency cleanup
# - Disk usage > 90% → block new writes
# - Process count > 500 → kill orphaned processes

# View SRPS alerts
srps alerts --last 10

# Configure thresholds
srps config set cpu-warning 80
srps config set memory-critical 95

# When SRPS triggers:
# 1. Logs the event
# 2. Sends Agent Mail notification to all agents
# 3. Pauses lowest-priority agent work
# 4. Waits for resources to recover
# 5. Resumes work automatically`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            SRPS works with <Highlight>SBH</Highlight> (Storage Ballast Helper)
            which pre-allocates disk space as an emergency buffer. When disk
            fills up, SBH releases the ballast so the system can recover
            gracefully.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Section 6: The Health Checklist */}
      <Section
        title="The Health Checklist"
        icon={<ClipboardCheck className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          A practical maintenance routine that keeps your environment healthy
          with minimal effort.
        </Paragraph>

        <div className="mt-6 space-y-3">
          <ChecklistItem
            frequency="Daily"
            task="Run acfs doctor at session start"
            detail="5 seconds"
          />
          <ChecklistItem
            frequency="Daily"
            task="Check srps status if system feels slow"
            detail="Quick resource check"
          />
          <ChecklistItem
            frequency="Weekly"
            task="Review journalctl -u acfs-nightly.service for update failures"
            detail="Catch silent errors"
          />
          <ChecklistItem
            frequency="Weekly"
            task="Run acfs update manually if nightly was disabled"
            detail="Stay current"
          />
          <ChecklistItem
            frequency="Monthly"
            task="Check disk space with df -h and clean old builds"
            detail="Prevent disk pressure"
          />
        </div>

        <div className="mt-8">
          <SummaryCard />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// CHECKLIST ITEM
// =============================================================================
function ChecklistItem({
  frequency,
  task,
  detail,
}: {
  frequency: string;
  task: string;
  detail: string;
}) {
  const colorMap: Record<string, string> = {
    Daily: "text-emerald-400 bg-emerald-500/10 border-emerald-500/30",
    Weekly: "text-amber-400 bg-amber-500/10 border-amber-500/30",
    Monthly: "text-violet-400 bg-violet-500/10 border-violet-500/30",
  };

  const badgeClass = colorMap[frequency] || colorMap.Daily;

  return (
    <div className="group flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]">
      <div className="flex items-center gap-3 shrink-0">
        <CheckCircle2 className="h-5 w-5 text-white/30 group-hover:text-emerald-400 transition-colors" />
        <span
          className={`inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium ${badgeClass}`}
        >
          {frequency}
        </span>
      </div>
      <div className="flex-1 min-w-0">
        <span className="text-sm text-white/80 group-hover:text-white transition-colors">
          {task}
        </span>
        <span className="text-xs text-white/40 block mt-0.5">{detail}</span>
      </div>
    </div>
  );
}

// =============================================================================
// SUMMARY CARD
// =============================================================================
function SummaryCard() {
  return (
    <div className="relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden">
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/20 rounded-full blur-3xl" />
      <div className="relative">
        <div className="flex items-center gap-3 mb-3">
          <Shield className="h-5 w-5 text-emerald-400" />
          <h4 className="font-bold text-white">Bottom Line</h4>
        </div>
        <p className="text-white/70 leading-relaxed">
          Good maintenance is invisible. Five seconds of{" "}
          <code className="text-emerald-300 bg-emerald-500/10 px-1.5 py-0.5 rounded text-sm">
            acfs doctor
          </code>{" "}
          at session start prevents hours of debugging broken tools. Let the
          nightly timer handle updates so you can focus on building.
        </p>
      </div>
    </div>
  );
}
