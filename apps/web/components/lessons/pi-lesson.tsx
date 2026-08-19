'use client';

import {
  Terminal,
  Cpu,
  Play,
  Zap,
  Database,
  Shield,
  HardDrive,
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

export function PiLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Run a native single-binary coding agent &mdash; with or without an API key &mdash;
        using Pi Agent.
      </GoalBanner>

      {/* Section 1: What Is Pi */}
      <Section title="What Is Pi Agent?" icon={<Cpu className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>pi (Pi Agent)</Highlight> is a from-scratch Rust port of Mario
          Zechner&apos;s Pi Agent: a native, single-binary coding agent. It streams
          responses with inline extended thinking, ships 9 built-in tools, and supports
          Markdown-defined subagents for custom workflows.
        </Paragraph>
        <Paragraph>
          It is multi-provider, including <Highlight>zero-config local models</Highlight>{' '}
          via ollama, llama.cpp, and LM Studio &mdash; meaning you can run a full coding
          agent with no API key at all.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Native Cold Start"
              description="Single Rust binary — no Node or Bun bootstrap to wait on"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Database className="h-5 w-5" />}
              title="Bounded Long Sessions"
              description="SQLite session index with fast resume and bounded resources"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Gated Extensions"
              description="Capability-gated extensions with two-stage exec mediation"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<HardDrive className="h-5 w-5" />}
              title="Trust Lifecycle"
              description="Trust lifecycle plus a risk ledger for auditable actions"
              gradient="from-violet-500/20 to-purple-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'pi "refactor this function"', description: 'Run an interactive agent task' },
            { command: 'pi -p "summarize" < error.log', description: 'Pipe input for one-shot print mode' },
            { command: 'pi --continue', description: 'Resume the most recent session' },
            { command: 'cat ~/.pi/agent/models.json', description: 'Configure local models (ollama, llama.cpp, LM Studio)' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 3: Local Models */}
      <Section title="Running Without an API Key" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Point <Highlight>pi</Highlight> at a local model server and it works with no
          cloud account. Local models are auto-detected for common servers, and custom
          endpoints go in <Highlight>~/.pi/agent/models.json</Highlight>.
        </Paragraph>
        <CodeBlock code={`# Start a local model server (any of these)
ollama serve
# ...or llama.cpp / LM Studio

# Then just run pi — zero-config local model discovery
pi "write unit tests for src/parser.rs"

# Custom endpoints live in ~/.pi/agent/models.json`} />

        <TipBox variant="warning">
          The existing TypeScript pi is preserved as <Highlight>legacy-pi</Highlight>,
          and an <Highlight>rpi</Highlight> launcher is added alongside. If a script or
          alias expects the old behavior, point it at legacy-pi.
        </TipBox>
      </Section>
    </div>
  );
}
