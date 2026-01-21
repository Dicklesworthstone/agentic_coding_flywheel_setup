'use client';

import {
  Terminal,
  Activity,
  Search,
  Shield,
  Play,
  AlertTriangle,
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

export function PtLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master intelligent process management with Process Triage.
      </GoalBanner>

      {/* Section 1: What Is PT */}
      <Section title="What Is Process Triage?" icon={<Activity className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>PT (Process Triage)</Highlight> identifies and terminates abandoned or
          zombie processes using a Bayesian-inspired scoring algorithm. It evaluates process type,
          age, orphan status, and resource usage to calculate abandonment probability.
        </Paragraph>
        <Paragraph>
          PT remembers your kill/spare decisions for similar processes, improving recommendations
          over time. It requires explicit confirmation and attempts graceful SIGTERM first.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Smart Search"
              description="Find processes by name, PID, or resource usage"
              gradient="from-lime-500/20 to-green-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="Resource Analysis"
              description="See CPU, memory, and I/O at a glance"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<AlertTriangle className="h-5 w-5" />}
              title="Problem Detection"
              description="Identify runaway and zombie processes"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safe Actions"
              description="Signal processes with confirmation"
              gradient="from-red-500/20 to-rose-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'pt', description: 'Show process overview' },
            { command: 'pt --top', description: 'Show top resource consumers' },
            { command: 'pt search <name>', description: 'Find processes by name' },
            { command: 'pt --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          PT is useful when agents need to diagnose why builds are slow or what&apos;s consuming resources.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Find what's using CPU
pt --top

# Search for node processes
pt search node

# Find processes using port 3000
pt --port 3000`} />
      </Section>
    </div>
  );
}
