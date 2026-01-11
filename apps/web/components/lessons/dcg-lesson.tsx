"use client";

import { motion } from "@/components/motion";
import {
  ShieldAlert,
  ShieldCheck,
  Terminal,
  AlertTriangle,
  Layers,
  KeyRound,
  Zap,
} from "lucide-react";
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
} from "./lesson-components";

export function DcgLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Use DCG to block destructive commands before they do damage.
      </GoalBanner>

      <Section
        title="What Is DCG?"
        icon={<ShieldAlert className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>DCG (Destructive Command Guard)</Highlight> is a Claude
          Code hook that blocks dangerous commands before they execute. It
          protects your repos from hard resets, recursive deletes, destructive
          database commands, and more.
        </Paragraph>
        <Paragraph>
          Think of it as a safety interlock: if a command looks destructive,
          DCG stops it and suggests a safer alternative.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ShieldCheck className="h-5 w-5" />}
              title="Pre-Execution Blocking"
              description="Stops damage before it happens"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="Protection Packs"
              description="Git, filesystem, database, cloud, and more"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<KeyRound className="h-5 w-5" />}
              title="Allow-Once Codes"
              description="Explicit bypass when you know it is safe"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fail-Open Design"
              description="Errors never block your workflow"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      <Section
        title="How DCG Intercepts Commands"
        icon={<ShieldCheck className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          DCG runs as a <Highlight>PreToolUse hook</Highlight> inside Claude
          Code. Every command is checked against a set of rules before it runs.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Example: test a command before running it
$ dcg test "git reset --hard" --explain
> BLOCKED: git.reset.hard
> Why: hard reset discards uncommitted work
> Safer: git restore --staged .`}
            language="bash"
          />
        </div>

        <TipBox variant="warning">
          If DCG blocks a command, slow down and read the explanation. It is
          showing you the dangerous part and a safer path.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <CommandList
          commands={[
            {
              command: "dcg test '<command>'",
              description: "Check if a command would be blocked",
            },
            {
              command: "dcg test '<command>' --explain",
              description: "Explain why a command is unsafe",
            },
            {
              command: "dcg packs",
              description: "List available protection packs",
            },
            {
              command: "dcg install",
              description: "Register the Claude Code hook",
            },
            {
              command: "dcg allow-once <code>",
              description: "Bypass for a single approved command",
            },
            {
              command: "dcg doctor",
              description: "Check installation and hook status",
            },
          ]}
        />
      </Section>

      <Divider />

      <Section
        title="Protection Packs"
        icon={<Layers className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          Packs let you enable or disable rules based on your workflow. Keep the
          ones you need to avoid false positives.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# ~/.config/dcg/config.toml
[packs]
enabled = ["git", "filesystem", "database.postgresql", "containers.docker"]`}
            language="toml"
            filename="config.toml"
          />
        </div>

        <TipBox variant="info">
          Start with <Highlight>git</Highlight> and{" "}
          <Highlight>filesystem</Highlight> packs. Add database or cloud packs
          only when you use those tools.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="When You See a Block"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          A block is a warning, not a dead end. Use it as a checkpoint:
        </Paragraph>
        <ul className="space-y-2 text-white/70 text-lg">
          <li>1) Read the explanation carefully.</li>
          <li>2) Prefer the safer alternative when possible.</li>
          <li>3) Use allow-once only if you are confident.</li>
          <li>4) Document the decision in your commit or notes.</li>
        </ul>
      </Section>

      <Divider />

      <Section
        title="DCG + SLB"
        icon={<Zap className="h-5 w-5" />}
        delay={0.35}
      >
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6"
        >
          <Paragraph>
            DCG blocks obvious destructive commands instantly. SLB handles
            contextual risk that needs human approval. Together, they form a
            layered safety system.
          </Paragraph>
        </motion.div>
      </Section>
    </div>
  );
}
