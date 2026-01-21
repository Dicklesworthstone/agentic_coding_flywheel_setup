'use client';

import {
  Terminal,
  RefreshCw,
  FileText,
  Brain,
  Play,
  Zap,
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

export function AprLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master AI-powered plan revision with Automated Plan Reviser Pro.
      </GoalBanner>

      {/* Section 1: What Is APR */}
      <Section title="What Is APR?" icon={<RefreshCw className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>APR (Automated Plan Reviser Pro)</Highlight> automates iterative specification
          refinement using extended AI reasoning. Instead of manually running 15-20 review rounds,
          APR orchestrates the process automatically.
        </Paragraph>
        <Paragraph>
          Early rounds fix architectural issues, middle rounds refine structure, later rounds
          polish abstractions. The process resembles numerical optimization settling into a minimum.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Brain className="h-5 w-5" />}
              title="AI-Powered"
              description="Uses advanced LLMs to refine plans"
              gradient="from-teal-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Markdown Support"
              description="Works with your existing plan files"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<RefreshCw className="h-5 w-5" />}
              title="Iterative"
              description="Refine plans through multiple passes"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fast"
              description="Get improved plans in seconds"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'apr refine plan.md', description: 'Refine a plan file' },
            { command: 'apr refine --output revised.md', description: 'Save to specific file' },
            { command: 'apr --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          Use APR after Claude Code generates an initial plan to get a more thorough version.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Typical Workflow */}
      <Section title="Typical Workflow" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# 1. Generate initial plan with Claude Code
# (Claude creates plan.md)

# 2. Refine with APR
apr refine plan.md -o refined-plan.md

# 3. Review the refined plan
cat refined-plan.md

# 4. Feed back to Claude Code for implementation`} />
      </Section>
    </div>
  );
}
