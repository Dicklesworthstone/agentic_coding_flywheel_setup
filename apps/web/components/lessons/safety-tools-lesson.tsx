"use client";

import type React from "react";
import { motion } from "@/components/motion";
import {
  Shield,
  ShieldAlert,
  Key,
  Users,
  AlertTriangle,
  Lock,
  Terminal,
  CheckCircle,
  XCircle,
  UserCheck,
  RefreshCw,
  Zap,
  Eye,
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

export function SafetyToolsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Use DCG, SLB and CAAM for layered safety and account management.
      </GoalBanner>

      {/* Introduction */}
      <Section
        title="Safety First"
        icon={<Shield className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          AI agents are powerful but can cause damage if misused. The
          Dicklesworthstone stack includes three safety tools:
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ShieldAlert className="h-5 w-5" />}
              title="DCG"
              description="Pre-execution blocking of destructive commands"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Users className="h-5 w-5" />}
              title="SLB"
              description="Two-person rule for dangerous commands"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="CAAM"
              description="Agent authentication switching"
              gradient="from-primary/20 to-violet-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* SLB Section */}
      <Section
        title="SLB: Simultaneous Launch Button"
        icon={<Users className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          <Highlight>SLB</Highlight> implements a &quot;two-person rule&quot;
          for dangerous commands. Just like nuclear launch codes require two
          keys, SLB requires two approvals before executing risky operations.
        </Paragraph>

        <div className="mt-8">
          <SlbDiagram />
        </div>
      </Section>

      {/* When to Use SLB */}
      <Section
        title="When to Use SLB"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-4">
          <DangerCard
            command="rm -rf /"
            risk="Deletes entire filesystem"
            slb="Requires confirmation from two agents"
          />
          <DangerCard
            command="git push --force origin main"
            risk="Overwrites shared history"
            slb="Requires explicit approval"
          />
          <DangerCard
            command="DROP DATABASE production"
            risk="Destroys production data"
            slb="Two-person verification"
          />
          <DangerCard
            command="kubectl delete namespace prod"
            risk="Takes down production services"
            slb="Mandatory review"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            Never bypass SLB protections. If a command requires two approvals,
            there&apos;s a reason. Get a second opinion.
          </TipBox>
        </div>
      </Section>

      {/* SLB Commands */}
      <Section
        title="SLB Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.25}
      >
        <CommandList
          commands={[
            {
              command: "slb pending",
              description: "Show pending requests",
            },
            {
              command: 'slb run "rm -rf /tmp" --reason "Clean build"',
              description: "Request approval and execute when approved",
            },
            {
              command: "slb approve <id> --session-id <sid>",
              description: "Approve a pending request",
            },
            {
              command: 'slb reject <id> --session-id <sid> --reason "..."',
              description: "Reject a pending request",
            },
            {
              command: "slb status <request-id>",
              description: "Check status of a specific request",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* DCG Section */}
      <Section
        title="DCG: Destructive Command Guard"
        icon={<ShieldAlert className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          <Highlight>DCG</Highlight> blocks dangerous commands before they run.
          It inspects every command from Claude Code and stops destructive
          patterns like hard resets, force pushes, and recursive deletes.
        </Paragraph>
        <Paragraph>
          If a command is safe, it runs normally. If it&apos;s risky, DCG blocks
          it and suggests a safer alternative.
        </Paragraph>

        <div className="mt-6">
          <TipBox variant="warning">
            Treat a DCG block as a safety checkpoint. Read the explanation and
            prefer the safer command whenever possible.
          </TipBox>
        </div>
      </Section>

      {/* DCG Commands */}
      <Section
        title="DCG Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.35}
      >
        <CommandList
          commands={[
            {
              command: "dcg test '<command>' --explain",
              description: "Explain why a command would be blocked",
            },
            {
              command: "dcg packs",
              description: "List available protection packs",
            },
            {
              command: "dcg install",
              description: "Register DCG as a Claude Code hook",
            },
            {
              command: "dcg allow-once <code>",
              description: "Bypass a single approved command",
            },
            {
              command: "dcg doctor",
              description: "Check installation and hook status",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* CAAM Section */}
      <Section
        title="CAAM: Coding Agent Account Manager"
        icon={<Key className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          <Highlight>CAAM</Highlight> enables sub-100ms account switching for
          subscription-based AI services (Claude Max, Codex CLI, Gemini Ultra).
          Swap OAuth tokens instantly without re-authenticating.
        </Paragraph>

        <div className="mt-6 space-y-4">
          <CaamFeature
            icon={<Key className="h-5 w-5" />}
            title="Token Management"
            description="Backup and restore OAuth tokens for each tool"
          />
          <CaamFeature
            icon={<RefreshCw className="h-5 w-5" />}
            title="Instant Switching"
            description="Switch accounts in under 100ms via symlink swap"
          />
          <CaamFeature
            icon={<Eye className="h-5 w-5" />}
            title="Multi-Tool Support"
            description="Works with Claude, Codex, and Gemini CLIs"
          />
          <CaamFeature
            icon={<Lock className="h-5 w-5" />}
            title="Profile Backup"
            description="Save profiles by email for easy restoration"
          />
        </div>
      </Section>

      {/* CAAM Use Cases */}
      <Section
        title="CAAM Use Cases"
        icon={<UserCheck className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="space-y-4">
          <UseCase
            scenario="Personal vs Work"
            description="Switch between personal and work subscriptions"
          />
          <UseCase
            scenario="Rate Limits"
            description="Rotate to a fresh account when hitting usage caps"
          />
          <UseCase
            scenario="Cost Separation"
            description="Use different subscriptions for different projects"
          />
          <UseCase
            scenario="Multi-Account"
            description="Manage multiple Claude Max / Codex accounts"
          />
        </div>
      </Section>

      {/* CAAM Commands */}
      <Section
        title="CAAM Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.4}
      >
        <CommandList
          commands={[
            {
              command: "caam ls [tool]",
              description: "List saved profiles (claude, codex, gemini)",
            },
            {
              command: "caam backup <tool> <email>",
              description: "Save current auth as a named profile",
            },
            {
              command: "caam activate <tool> <email>",
              description: "Activate a saved profile",
            },
            {
              command: "caam status [tool]",
              description: "Show currently active profile",
            },
            {
              command: "caam delete <tool> <email>",
              description: "Remove a saved profile",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Integration with Agents */}
      <Section
        title="Integration with Agents"
        icon={<Zap className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          DCG, SLB, and CAAM integrate with Claude Code, Codex, and Gemini:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Example: DCG blocks a destructive command
$ claude "reset the repo"
> DCG: blocked git reset --hard
> Suggestion: git restore --staged .

# Example: Dangerous command triggers SLB
$ claude "delete all test files"
> SLB: This command requires approval
> Waiting for second approval...
> Run 'slb approve req-123 --session-id <sid>' from another session

# Example: Switch Claude accounts for a project
$ caam activate claude work@company.com
> Activated profile 'work@company.com' for claude
> Symlink updated in 47ms

$ claude "continue the project"
> Using profile: work@company.com`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.5}
      >
        <div className="grid gap-6 md:grid-cols-3">
          {/* SLB Best Practices */}
          <div className="rounded-2xl border border-red-500/20 bg-red-500/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <Users className="h-5 w-5 text-red-400" />
              SLB Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Never bypass approval requirements" />
              <BestPractice text="Review commands before approving" />
              <BestPractice text="Use descriptive request messages" />
              <BestPractice text="Set up notifications for pending requests" />
            </div>
          </div>

          {/* DCG Best Practices */}
          <div className="rounded-2xl border border-rose-500/20 bg-rose-500/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <ShieldAlert className="h-5 w-5 text-rose-400" />
              DCG Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Read the block explanation before acting" />
              <BestPractice text="Prefer safer alternatives over allow-once" />
              <BestPractice text="Enable only the packs you need" />
              <BestPractice text="Re-register after updates: dcg install" />
            </div>
          </div>

          {/* CAAM Best Practices */}
          <div className="rounded-2xl border border-primary/20 bg-primary/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <Key className="h-5 w-5 text-primary" />
              CAAM Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Backup profiles before switching" />
              <BestPractice text="Use email as profile identifier" />
              <BestPractice text="Verify active profile with caam status" />
              <BestPractice text="Delete old profiles when no longer needed" />
            </div>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Quick Reference */}
      <Section
        title="Quick Reference"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.55}
      >
        <div className="grid gap-4 md:grid-cols-3">
          <QuickRefCard
            title="SLB"
            commands={[
              "slb pending",
              "slb run <cmd> --reason ...",
              "slb approve <id> --session-id ...",
              "slb status <id>",
            ]}
            color="from-red-500/20 to-rose-500/20"
          />
          <QuickRefCard
            title="DCG"
            commands={[
              "dcg test '<cmd>' --explain",
              "dcg packs",
              "dcg allow-once <code>",
              "dcg doctor",
            ]}
            color="from-rose-500/20 to-fuchsia-500/20"
          />
          <QuickRefCard
            title="CAAM"
            commands={[
              "caam ls [tool]",
              "caam backup <tool> <email>",
              "caam activate <tool> <email>",
              "caam status [tool]",
            ]}
            color="from-primary/20 to-violet-500/20"
          />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// SLB DIAGRAM
// =============================================================================
function SlbDiagram() {
  return (
    <div className="relative p-8 rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/3 w-48 h-48 bg-red-500/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/3 w-48 h-48 bg-emerald-500/10 rounded-full blur-3xl" />

      <div className="relative flex flex-col items-center gap-6">
        {/* Command */}
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          whileHover={{ scale: 1.02 }}
          className="flex items-center gap-4 px-6 py-4 rounded-2xl bg-gradient-to-br from-red-500/20 to-rose-500/20 border border-red-500/30 shadow-lg shadow-red-500/10 transition-shadow hover:shadow-xl hover:shadow-red-500/20"
        >
          <AlertTriangle className="h-6 w-6 text-red-400" />
          <div>
            <span className="font-mono text-white text-sm">rm -rf /</span>
            <span className="text-xs text-white/50 block">Dangerous Command</span>
          </div>
        </motion.div>

        {/* Arrow down */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-white/30 text-xl"
        >
          ↓
        </motion.div>

        {/* Two approvals */}
        <div className="flex items-center gap-8">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2 }}
            whileHover={{ y: -4, scale: 1.05 }}
            className="group flex flex-col items-center gap-3 cursor-pointer"
          >
            <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-emerald-500/20 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 group-hover:shadow-xl group-hover:shadow-emerald-500/20 transition-all duration-300">
              <CheckCircle className="h-7 w-7 text-emerald-400" />
            </div>
            <span className="text-xs text-white/50 font-medium group-hover:text-emerald-400 transition-colors">Agent 1</span>
          </motion.div>

          <span className="text-white/30 text-xl">+</span>

          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.3 }}
            whileHover={{ y: -4, scale: 1.05 }}
            className="group flex flex-col items-center gap-3 cursor-pointer"
          >
            <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-emerald-500/20 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 group-hover:shadow-xl group-hover:shadow-emerald-500/20 transition-all duration-300">
              <CheckCircle className="h-7 w-7 text-emerald-400" />
            </div>
            <span className="text-xs text-white/50 font-medium group-hover:text-emerald-400 transition-colors">Agent 2</span>
          </motion.div>
        </div>

        {/* Arrow down */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.35 }}
          className="text-white/30 text-xl"
        >
          ↓
        </motion.div>

        {/* Execute */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
          whileHover={{ scale: 1.02 }}
          className="flex items-center gap-4 px-6 py-4 rounded-2xl bg-gradient-to-br from-emerald-500/20 to-teal-500/20 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 transition-shadow hover:shadow-xl hover:shadow-emerald-500/20"
        >
          <Shield className="h-6 w-6 text-emerald-400" />
          <div>
            <span className="font-bold text-white">Safe to Execute</span>
            <span className="text-xs text-white/50 block">Two approvals received</span>
          </div>
        </motion.div>
      </div>
    </div>
  );
}

// =============================================================================
// DANGER CARD
// =============================================================================
function DangerCard({
  command,
  risk,
  slb,
}: {
  command: string;
  risk: string;
  slb: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group rounded-2xl border border-red-500/20 bg-red-500/5 p-5 backdrop-blur-xl transition-all duration-300 hover:border-red-500/40 hover:bg-red-500/10"
    >
      <code className="text-sm text-red-400 font-mono font-medium">{command}</code>
      <div className="flex items-start gap-3 mt-3">
        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-red-500/20">
          <XCircle className="h-4 w-4 text-red-400" />
        </div>
        <span className="text-sm text-white/60">{risk}</span>
      </div>
      <div className="flex items-start gap-3 mt-2">
        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20">
          <Shield className="h-4 w-4 text-emerald-400" />
        </div>
        <span className="text-sm text-emerald-400/80 font-medium">{slb}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CAAM FEATURE
// =============================================================================
function CaamFeature({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-primary/30 hover:bg-white/[0.04]"
    >
      <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/20 text-primary shrink-0 shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
        {icon}
      </div>
      <div>
        <h4 className="font-semibold text-white group-hover:text-primary transition-colors">{title}</h4>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// USE CASE
// =============================================================================
function UseCase({
  scenario,
  description,
}: {
  scenario: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-center gap-4 p-4 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/20 text-primary shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
        <UserCheck className="h-5 w-5" />
      </div>
      <div>
        <span className="font-medium text-white group-hover:text-primary transition-colors">{scenario}</span>
        <span className="text-white/40 mx-2">—</span>
        <span className="text-sm text-white/50">{description}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({ text }: { text: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -5 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-3 p-2 -mx-2 rounded-lg transition-colors hover:bg-white/[0.03]"
    >
      <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 group-hover:bg-emerald-500/30 transition-colors">
        <CheckCircle className="h-3.5 w-3.5 text-emerald-400" />
      </div>
      <span className="text-sm text-white/70 group-hover:text-white transition-colors">{text}</span>
    </motion.div>
  );
}

// =============================================================================
// QUICK REF CARD
// =============================================================================
function QuickRefCard({
  title,
  commands,
  color,
}: {
  title: string;
  commands: string[];
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${color} p-6 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.2]`}
    >
      {/* Decorative glow */}
      <div className="absolute -top-8 -right-8 w-24 h-24 bg-white/10 rounded-full blur-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <h4 className="relative font-bold text-white mb-4 text-lg">{title}</h4>
      <div className="relative space-y-2">
        {commands.map((cmd) => (
          <code
            key={cmd}
            className="block text-sm text-white/80 font-mono py-1 px-2 -mx-2 rounded-lg transition-colors group-hover:text-white hover:bg-white/[0.05]"
          >
            $ {cmd}
          </code>
        ))}
      </div>
    </motion.div>
  );
}
