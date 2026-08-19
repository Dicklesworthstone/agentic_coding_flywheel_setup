'use client';

import {
  Terminal,
  Power,
  Play,
  Search,
  FileText,
  RotateCcw,
  CheckCircle2,
} from 'lucide-react';
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
} from './lesson-components';

export function PfrLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Bring your whole agent fleet back after a blackout with Power Failure Resumer.
      </GoalBanner>

      {/* Section 1: What Is PFR */}
      <Section title="What Is PFR?" icon={<Power className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>pfr (Power Failure Resumer)</Highlight> recovers crashed agent
          sessions after a hard power cut. Its forensic insight: when the machine dies,
          every crashed session&apos;s file stops changing at nearly the same moment
          before boot. PFR clusters that pocket of last-modified timestamps, then scores
          each candidate&apos;s confidence as high, medium, or low &mdash; with reasons.
        </Paragraph>
        <Paragraph>
          Sessions that were already resumed are skipped automatically, so running it
          twice never double-opens anything.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Forensic Detection"
              description="Clusters sessions whose files froze together before boot"
              gradient="from-rose-500/20 to-pink-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Frozen Plans"
              description="Decisions are frozen into last-plan.json before acting"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<RotateCcw className="h-5 w-5" />}
              title="Model-Aware Resume"
              description="Reopens each victim with its recorded model in its own tab"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<CheckCircle2 className="h-5 w-5" />}
              title="Verified Recovery"
              description="Checks ps, writes last-report.json, non-zero exit on silent failures"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'pfr --dry-run', description: 'Show what would be resumed, without touching anything' },
            { command: 'pfr -y', description: 'Resume all detected victims without prompting' },
            { command: 'pfr --last-plan --pick', description: 'Review the frozen plan and pick sessions to resume' },
            { command: 'pfr --doctor --json', description: 'Verify installation health' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 3: How Recovery Works */}
      <Section title="How Recovery Works" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# After the machine comes back up, see what died
pfr --dry-run

# Happy with the plan? Resume everything
pfr -y

# Each victim reopens with its recorded model:
#   Claude Code sessions  -> cc --resume
#   Codex sessions        -> cod resume
# ...each in its own terminal tab.

# Afterward, pfr verifies against ps and writes last-report.json.
# A silent failure (tab opened but no live process) exits non-zero.`} />

        <Paragraph>
          The plan-then-act split matters: <Highlight>last-plan.json</Highlight> freezes
          the detection decisions so you can inspect or re-run them with{' '}
          <Highlight>--last-plan --pick</Highlight>, and{' '}
          <Highlight>last-report.json</Highlight> records what actually happened.
        </Paragraph>

        <TipBox variant="warning">
          There is no <Highlight>--version</Highlight> flag &mdash; use{' '}
          <Highlight>pfr --doctor</Highlight> instead. And PFR is a local-workstation
          tool: on a headless server it can still plan, but it cannot reopen terminal
          tabs.
        </TipBox>
      </Section>
    </div>
  );
}
