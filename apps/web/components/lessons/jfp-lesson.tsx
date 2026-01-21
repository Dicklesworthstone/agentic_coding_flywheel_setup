'use client';

import {
  GraduationCap,
  Terminal,
  Globe,
  Search,
  Download,
  Copy,
  Play,
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

export function JfpLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Discover and install curated prompts for agentic coding with JeffreysPrompts.
      </GoalBanner>

      {/* Section 1: What Is JFP */}
      <Section title="What Is JFP?" icon={<GraduationCap className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>JFP (JeffreysPrompts.com CLI)</Highlight> gives you access to a curated
          library of battle-tested prompts for Claude, GPT, and other AI coding agents. Browse,
          copy, and install prompts directly as Claude Code skills.
        </Paragraph>
        <Paragraph>
          The CLI and website share the same prompt library, so use whichever interface fits your
          workflow. Prompts are organized into bundles and workflows for complex use cases.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Browse"
              description="Explore curated prompt collection"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Copy className="h-5 w-5" />}
              title="Copy"
              description="Copy prompts to clipboard instantly"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Install"
              description="Install as Claude Code skills"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Web + CLI"
              description="Use browser or terminal"
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
            { command: 'jfp list', description: 'List all available prompts' },
            { command: 'jfp search <query>', description: 'Search for prompts' },
            { command: 'jfp show <id>', description: 'View prompt details' },
            { command: 'jfp copy <id>', description: 'Copy prompt to clipboard' },
            { command: 'jfp install <id>', description: 'Install as Claude Code skill' },
            { command: 'jfp installed', description: 'List installed skills' },
          ]}
        />

        <TipBox variant="info">
          Visit <a href="https://jeffreysprompts.com" className="text-blue-400 underline">jeffreysprompts.com</a> for a beautiful UI to browse prompts.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Browse all prompts
jfp list

# Search for code review prompts
jfp search "code review"

# Install a prompt as a skill
jfp install idea-wizard

# Use in Claude Code
/idea-wizard "build a REST API"`} />
      </Section>
    </div>
  );
}
