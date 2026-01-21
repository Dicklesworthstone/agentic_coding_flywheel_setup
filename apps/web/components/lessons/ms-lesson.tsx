'use client';

import {
  GraduationCap,
  Terminal,
  Package,
  Search,
  Play,
  Settings,
  Download,
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

export function MsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master local-first skill management for Claude Code and other AI agents with Meta Skill.
      </GoalBanner>

      {/* Section 1: What Is Meta Skill */}
      <Section title="What Is Meta Skill?" icon={<GraduationCap className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>Meta Skill (ms)</Highlight> is a local-first knowledge management platform that
          turns operational knowledge into structured, searchable, reusable artifacts with Git-backed
          audit trails.
        </Paragraph>
        <Paragraph>
          It combines BM25 lexical matching with deterministic hash embeddings for hybrid semantic
          search. No external APIs required. Skills can come from hand-written files, CASS session
          mining, or bundle imports.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Package className="h-5 w-5" />}
              title="Local-First"
              description="Skills stored on your machine, no cloud dependency"
              gradient="from-purple-500/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Easy Install"
              description="One command to install from JeffreysPrompts"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Browse Skills"
              description="Discover and search available skills"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Settings className="h-5 w-5" />}
              title="Manage"
              description="Update, disable, and organize your skills"
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
            { command: 'ms list', description: 'List all installed skills' },
            { command: 'ms install <skill>', description: 'Install a skill from registry' },
            { command: 'ms uninstall <skill>', description: 'Remove an installed skill' },
            { command: 'ms update', description: 'Update all installed skills' },
            { command: 'ms doctor', description: 'Check skill system health' },
            { command: 'ms search <query>', description: 'Search for skills in registry' },
          ]}
        />

        <TipBox>
          Install popular skills directly: <code>ms install code-review</code>
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Working with Skills */}
      <Section title="Working with Skills" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Once installed, skills are automatically available in Claude Code. Use them with
          the slash command syntax.
        </Paragraph>

        <CodeBlock code={`# List your installed skills
ms list

# Install a skill
ms install idea-wizard

# Use it in Claude Code
/idea-wizard "build a todo app"

# Update all skills to latest versions
ms update`} />
      </Section>
    </div>
  );
}
