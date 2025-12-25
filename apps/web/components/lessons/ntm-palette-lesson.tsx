"use client";

import { motion } from "@/components/motion";
import {
  Palette,
  Sparkles,
  Code2,
  FileText,
  Bug,
  TestTube,
  Layers,
  Send,
  FolderOpen,
  Lightbulb,
  Play,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  InlineCode,
  BulletList,
} from "./lesson-components";

export function NtmPaletteLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Discover the pre-built prompts that supercharge your agents.
      </GoalBanner>

      {/* What Is The Command Palette */}
      <Section
        title="What Is The Command Palette?"
        icon={<Palette className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          NTM ships with a <Highlight>command palette</Highlight> - a collection
          of battle-tested prompts for common development tasks.
        </Paragraph>
        <Paragraph>
          These aren&apos;t just prompts. They&apos;re carefully crafted
          instructions that get the best results from coding agents.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock code="ntm palette" />
        </div>
        <Paragraph>
          This opens an interactive browser of all available prompts.
        </Paragraph>
      </Section>

      <Divider />

      {/* Palette Categories */}
      <Section
        title="Palette Categories"
        icon={<Layers className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>The prompts are organized into categories:</Paragraph>

        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <CategoryCard
            icon={<Layers className="h-5 w-5" />}
            title="Architecture & Design"
            items={[
              "System design analysis",
              "Architecture review",
              "API design patterns",
            ]}
            gradient="from-violet-500/20 to-purple-500/20"
            delay={0.1}
          />
          <CategoryCard
            icon={<Code2 className="h-5 w-5" />}
            title="Code Quality"
            items={[
              "Code review prompts",
              "Refactoring suggestions",
              "Bug hunting strategies",
            ]}
            gradient="from-sky-500/20 to-blue-500/20"
            delay={0.2}
          />
          <CategoryCard
            icon={<TestTube className="h-5 w-5" />}
            title="Testing"
            items={[
              "Test generation",
              "Coverage analysis",
              "Edge case discovery",
            ]}
            gradient="from-emerald-500/20 to-teal-500/20"
            delay={0.3}
          />
          <CategoryCard
            icon={<FileText className="h-5 w-5" />}
            title="Documentation"
            items={[
              "README generation",
              "API documentation",
              "Inline comment review",
            ]}
            gradient="from-amber-500/20 to-orange-500/20"
            delay={0.4}
          />
          <CategoryCard
            icon={<Bug className="h-5 w-5" />}
            title="Debugging"
            items={[
              "Error analysis",
              "Performance profiling",
              "Memory leak detection",
            ]}
            gradient="from-red-500/20 to-rose-500/20"
            delay={0.5}
          />
        </div>
      </Section>

      <Divider />

      {/* Using Palette Prompts */}
      <Section
        title="Using Palette Prompts"
        icon={<Send className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-8">
          <UsageOption
            number={1}
            title="Copy and Send"
            steps={[
              <>Open the palette: <InlineCode>ntm palette</InlineCode></>,
              "Select a prompt",
              "Copy it",
              <>Use <InlineCode>ntm send</InlineCode> or paste directly</>,
            ]}
          />

          <UsageOption
            number={2}
            title="Direct Send (Power Move)"
            steps={[]}
          >
            <div className="mt-4">
              <CodeBlock code="ntm palette myproject --send" />
            </div>
            <p className="mt-3 text-white/60">
              This lets you select a prompt and immediately send it to all
              agents!
            </p>
          </UsageOption>
        </div>
      </Section>

      <Divider />

      {/* Example Prompts */}
      <Section
        title="Example Prompts"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>Here are a few examples from the palette:</Paragraph>

        <div className="mt-8 space-y-6">
          <ExamplePrompt
            title="Code Review"
            prompt={`Review this code with an emphasis on:
1. Security vulnerabilities
2. Performance issues
3. Code readability
4. Edge cases not handled

For each issue, provide:
- The specific problem
- Why it matters
- A suggested fix`}
            gradient="from-sky-500/20 to-blue-500/20"
          />

          <ExamplePrompt
            title="Architecture Analysis"
            prompt={`Analyze the architecture of this codebase:
1. Identify the main components
2. Map the data flow
3. Note any anti-patterns
4. Suggest improvements

Create a simple diagram if helpful.`}
            gradient="from-violet-500/20 to-purple-500/20"
          />
        </div>
      </Section>

      <Divider />

      {/* Customizing The Palette */}
      <Section
        title="Customizing The Palette"
        icon={<FolderOpen className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>You can add your own prompts:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Location of custom prompts
~/.acfs/palette/custom/`}
          />
        </div>

        <Paragraph>
          Create <InlineCode>.md</InlineCode> files with your prompts, and
          they&apos;ll appear in the palette.
        </Paragraph>
      </Section>

      <Divider />

      {/* Pro Tips */}
      <Section
        title="Pro Tips"
        icon={<Lightbulb className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="mt-4">
          <BulletList
            items={[
              <span key="1">
                <strong>Start broad, then narrow</strong> - Use high-level
                prompts first
              </span>,
              <span key="2">
                <strong>Combine agents</strong> - Send different prompts to
                different agents
              </span>,
              <span key="3">
                <strong>Build on responses</strong> - Use agent output in
                follow-up prompts
              </span>,
              <span key="4">
                <strong>Save good prompts</strong> - Add working prompts to your
                custom palette
              </span>,
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Play className="h-5 w-5" />}
        delay={0.4}
      >
        <CodeBlock
          code={`# Open the palette
$ ntm palette

# Browse the categories
# Select something interesting
# Try sending it to your test session`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// CATEGORY CARD - Display a palette category
// =============================================================================
function CategoryCard({
  icon,
  title,
  items,
  gradient,
  delay,
}: {
  icon: React.ReactNode;
  title: string;
  items: string[];
  gradient: string;
  delay: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-5 backdrop-blur-xl transition-all duration-500 hover:border-white/[0.15]`}
    >
      <div className="flex items-center gap-3 mb-4">
        <div className="text-white">{icon}</div>
        <h4 className="font-bold text-white">{title}</h4>
      </div>
      <ul className="space-y-2">
        {items.map((item, i) => (
          <li key={i} className="text-sm text-white/60 flex items-center gap-2">
            <div className="h-1 w-1 rounded-full bg-white/40" />
            {item}
          </li>
        ))}
      </ul>
    </motion.div>
  );
}

// =============================================================================
// USAGE OPTION - How to use the palette
// =============================================================================
function UsageOption({
  number,
  title,
  steps,
  children,
}: {
  number: number;
  title: string;
  steps: React.ReactNode[];
  children?: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl"
    >
      <div className="flex items-center gap-4 mb-4">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white font-bold">
          {number}
        </div>
        <h4 className="text-lg font-bold text-white">{title}</h4>
      </div>

      {steps.length > 0 && (
        <ol className="space-y-2 ml-14">
          {steps.map((step, i) => (
            <li key={i} className="text-white/70 flex items-center gap-2">
              <span className="text-primary font-medium">{i + 1}.</span>
              {step}
            </li>
          ))}
        </ol>
      )}

      {children}
    </motion.div>
  );
}

// =============================================================================
// EXAMPLE PROMPT - Display an example prompt
// =============================================================================
function ExamplePrompt({
  title,
  prompt,
  gradient,
}: {
  title: string;
  prompt: string;
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className={`relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} overflow-hidden`}
    >
      <div className="p-4 border-b border-white/[0.08] bg-black/20">
        <h4 className="font-bold text-white">{title}</h4>
      </div>
      <div className="p-4">
        <pre className="text-sm text-white/80 whitespace-pre-wrap font-mono">
          {prompt}
        </pre>
      </div>
    </motion.div>
  );
}
