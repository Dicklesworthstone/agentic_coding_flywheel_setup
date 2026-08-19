'use client';

import {
  Terminal,
  Brain,
  Search,
  Database,
  Play,
  ShieldCheck,
  History,
  Hash,
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

export function EeLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Give your agents durable, explainable local memory with Eidetic Engine.
      </GoalBanner>

      {/* Section 1: What Is EE */}
      <Section title="What Is Eidetic Engine?" icon={<Brain className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>ee (Eidetic Engine)</Highlight> is durable, explainable local memory
          for coding agents. It stores typed memories &mdash; rules, decisions, failures,
          commands, and conventions &mdash; and retrieves them with hybrid BM25 + local
          vector search, so an agent starting a new session can instantly recall what
          past sessions learned the hard way.
        </Paragraph>
        <Paragraph>
          Everything runs locally: there is no cloud API, and every retrieval comes with
          an explainable score breakdown so you can see exactly why a memory was selected
          for a given task.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Hybrid Retrieval"
              description="BM25 + local vectors with a per-item score breakdown"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<ShieldCheck className="h-5 w-5" />}
              title="Confidence Decay"
              description="Stale memories fade; harmful memories get demoted"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<History className="h-5 w-5" />}
              title="CASS History Mining"
              description="Import lessons from past agent sessions automatically"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Hash className="h-5 w-5" />}
              title="Deterministic Packs"
              description="Stable pack hashes and a versioned JSON schema"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Core Workflow */}
      <Section title="Core Workflow" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'ee pack "fix the auth bug"', description: 'Build a token-budgeted context pack for a task' },
            { command: 'ee remember', description: 'Capture a new rule, decision, or failure' },
            { command: 'ee search "query"', description: 'Search stored memories' },
            { command: 'ee why', description: 'Explain why memories were selected' },
            { command: 'ee curate', description: 'Distill raw memories into procedural rules' },
            { command: 'ee import cass', description: 'Mine past CASS sessions into memories' },
            { command: 'ee preflight check --cmd "rm -rf build"', description: 'Check a risky command against failure memories' },
            { command: 'ee doctor --json', description: 'Verify installation health' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 3: When to Use It */}
      <Section title="When to Use It" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Reach for <Highlight>ee</Highlight> at three moments: at{' '}
          <Highlight>session start</Highlight> (run <Highlight>ee pack</Highlight> to load
          relevant context), <Highlight>after learning a rule</Highlight> (run{' '}
          <Highlight>ee remember</Highlight> so the lesson survives the session), and{' '}
          <Highlight>before risky commands</Highlight> (run{' '}
          <Highlight>ee preflight</Highlight> to check against past failures).
        </Paragraph>
        <CodeBlock code={`# Start of session: pull the most relevant memories for the task
ee pack "fix the auth bug"

# After discovering something worth keeping
ee remember

# Before doing anything destructive
ee preflight check --cmd "rm -rf build"`} />

        <TipBox>
          Memory is advisory, not authoritative. If a stored memory conflicts with the
          live AGENTS.md or README, the live project files always win &mdash; use{' '}
          <Highlight>ee curate</Highlight> to prune memories that have gone stale.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Explainability */}
      <Section title="Explainable by Design" icon={<Database className="h-5 w-5" />} delay={0.4}>
        <Paragraph>
          Every pack is deterministic: the same memories and the same query produce the
          same pack hash, and the JSON schema is versioned. When a selection looks wrong,{' '}
          <Highlight>ee why</Highlight> shows the per-item score breakdown (lexical match,
          vector similarity, confidence, recency) so you can debug retrieval instead of
          guessing.
        </Paragraph>
      </Section>
    </div>
  );
}
