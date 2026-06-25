"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  RefreshCw,
  Zap,
  Clock,
  Terminal,
  FileText,
  AlertTriangle,
  CheckCircle2,
  Sparkles,
  Bot,
  Package,
  Settings,
  PartyPopper,
  Loader2,
  Play,
  RotateCcw,
  Wrench,
  Minus,
  XCircle,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Divider,
  GoalBanner,
  BulletList,
} from "./lesson-components";

export function KeepingUpdatedLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Learn how to keep your ACFS tools current.
      </GoalBanner>

      {/* Why Updates Matter */}
      <Section
        title="Why Updates Matter"
        icon={<Zap className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          Your VPS has 30+ tools installed. Each one gets improvements:
        </Paragraph>

        <div className="mt-6">
          <BulletList
            items={[
              "Bug fixes and security patches",
              "New features and capabilities",
              "Better performance",
            ]}
          />
        </div>

        <div className="mt-6">
          <UpdateBenefitsCard />
        </div>
      </Section>

      <Divider />

      {/* The Update Command */}
      <Section
        title="The Update Command"
        icon={<RefreshCw className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          ACFS provides a single command to update everything:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock code="acfs-update" />
        </div>

        <Paragraph>That&apos;s it! This updates:</Paragraph>

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <UpdateItem
            icon={<Package className="h-4 w-4" />}
            label="System packages"
            description="apt"
          />
          <UpdateItem
            icon={<Terminal className="h-4 w-4" />}
            label="Shell tools"
            description="OMZ, P10K, plugins"
          />
          <UpdateItem
            icon={<Bot className="h-4 w-4" />}
            label="Coding agents"
            description="Claude, Codex, Antigravity"
          />
          <UpdateItem
            icon={<Settings className="h-4 w-4" />}
            label="Cloud CLIs"
            description="Wrangler, Supabase, Vercel"
          />
        </div>

        <div className="mt-8">
          <InteractiveUpdatePipeline />
        </div>
      </Section>

      <Divider />

      {/* Common Update Patterns */}
      <Section
        title="Common Update Patterns"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-6">
          <UpdatePattern
            title="Quick Agent Update"
            description="If you just want the latest agent versions:"
            command="acfs-update --agents-only"
          />

          <UpdatePattern
            title="Skip System Packages"
            description="apt updates can be slow. Skip them when you're in a hurry:"
            command="acfs-update --no-apt"
          />

          <UpdatePattern
            title="Preview Changes"
            description="See what would be updated without changing anything:"
            command="acfs-update --dry-run"
          />

          <UpdatePattern
            title="Include Stack Tools"
            description="The Dicklesworthstone stack (ntm, slb, ubs, etc.) is skipped by default because it takes longer. Include it with:"
            command="acfs-update --stack"
          />
        </div>
      </Section>

      <Divider />

      {/* Automated Updates */}
      <Section
        title="Automated Updates"
        icon={<Clock className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>For hands-off maintenance, use quiet mode:</Paragraph>

        <div className="mt-6">
          <CodeBlock code="acfs-update --yes --quiet" />
        </div>

        <Paragraph>
          This runs without prompts and only shows errors.
        </Paragraph>

        <div className="mt-6">
          <TipBox variant="tip">
            You can add this to a cron job for weekly updates!
          </TipBox>
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Edit crontab
crontab -e

# Add this line for weekly Sunday 3am updates
0 3 * * 0 $HOME/.local/bin/acfs-update --yes --quiet >> $HOME/.acfs/logs/cron-update.log 2>&1`}
          />
        </div>
      </Section>

      <Divider />

      {/* Checking Update Logs */}
      <Section
        title="Checking Update Logs"
        icon={<FileText className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>Every update is logged:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# List recent logs
ls -lt ~/.acfs/logs/updates/ | head -5

# View the most recent log
cat ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)

# Watch a running update
tail -f ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)`}
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* Troubleshooting */}
      <Section
        title="Troubleshooting"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="space-y-6">
          <TroubleshootingCard
            title="apt is locked"
            description='If you see "apt is locked by another process":'
            solution={`# See which process is holding the lock
sudo fuser -v /var/lib/dpkg/lock-frontend || true

# Wait for other apt operations to finish, then repair interrupted packages
sudo dpkg --configure -a`}
          />

          <TroubleshootingCard
            title="Agent update failed"
            description="Try updating directly:"
            solution={`# Claude
claude update --channel latest

# Codex
bun install -g --trust @openai/codex@latest

# Antigravity
agy update`}
          />

          <TroubleshootingCard
            title="Shell tools won't update"
            description="Check git remote access:"
            solution="git -C ~/.oh-my-zsh remote -v"
          />
        </div>
      </Section>

      <Divider />

      {/* Quick Reference */}
      <Section
        title="Quick Reference"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.4}
      >
        <QuickReferenceTable />
      </Section>

      <Divider />

      {/* How Often to Update */}
      <Section
        title="How Often to Update?"
        icon={<Clock className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>Recommendations:</Paragraph>

        <div className="mt-6 space-y-3">
          <FrequencyItem
            frequency="Weekly"
            recommendation="Full update including stack"
          />
          <FrequencyItem
            frequency="After issues"
            recommendation="If something breaks, update first"
          />
          <FrequencyItem
            frequency="Before major work"
            recommendation="Get latest agent versions"
          />
        </div>
      </Section>

      <Divider />

      {/* Congratulations */}
      <Section
        title="Congratulations!"
        icon={<PartyPopper className="h-5 w-5" />}
        delay={0.5}
      >
        <CongratulationsCard />
      </Section>
    </div>
  );
}

// =============================================================================
// UPDATE BENEFITS CARD
// =============================================================================
function UpdateBenefitsCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2 }}
      className="relative rounded-2xl border border-white/[0.08] bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-emerald-500/30"
    >
      <h4 className="font-bold text-white mb-4">Keeping things updated means:</h4>
      <div className="space-y-3">
        <BenefitRow icon={<CheckCircle2 />} text="Fewer mysterious errors" />
        <BenefitRow icon={<CheckCircle2 />} text="Better security" />
        <BenefitRow icon={<CheckCircle2 />} text="Access to new agent features" />
      </div>
    </motion.div>
  );
}

function BenefitRow({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-3 p-2 -mx-2 rounded-lg transition-all duration-300 hover:bg-white/[0.02]"
    >
      <div className="text-emerald-400 h-5 w-5 group-hover:scale-110 transition-transform">{icon}</div>
      <span className="text-white/70 group-hover:text-white/90 transition-colors">{text}</span>
    </motion.div>
  );
}

// =============================================================================
// UPDATE ITEM
// =============================================================================
function UpdateItem({
  icon,
  label,
  description,
}: {
  icon: React.ReactNode;
  label: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ scale: 1.02, y: -2 }}
      className="group flex items-center gap-3 p-3 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="text-primary group-hover:scale-110 transition-transform">{icon}</div>
      <div>
        <span className="text-sm font-medium text-white group-hover:text-primary transition-colors">{label}</span>
        <span className="text-xs text-white/50 block">{description}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// UPDATE PATTERN
// =============================================================================
function UpdatePattern({
  title,
  description,
  command,
}: {
  title: string;
  description: string;
  command: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group space-y-3 p-4 -mx-4 rounded-xl transition-all duration-300 hover:bg-white/[0.02]"
    >
      <h4 className="font-bold text-white group-hover:text-primary transition-colors">{title}</h4>
      <p className="text-white/60">{description}</p>
      <CodeBlock code={command} />
    </motion.div>
  );
}

// =============================================================================
// TROUBLESHOOTING CARD
// =============================================================================
function TroubleshootingCard({
  title,
  description,
  solution,
}: {
  title: string;
  description: string;
  solution: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-6 backdrop-blur-xl transition-all duration-300 hover:border-amber-500/50"
    >
      <h4 className="font-bold text-amber-400 mb-2">{title}</h4>
      <p className="text-white/60 mb-4">{description}</p>
      <div className="rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden">
        <pre className="p-4 text-sm font-mono text-white/80 overflow-x-auto whitespace-pre-wrap">
          {solution}
        </pre>
      </div>
    </motion.div>
  );
}

// =============================================================================
// QUICK REFERENCE TABLE
// =============================================================================
function QuickReferenceTable() {
  const commands = [
    { command: "acfs-update", description: "Update everything (except stack)" },
    { command: "acfs-update --stack", description: "Include stack tools" },
    { command: "acfs-update --agents-only", description: "Just update agents" },
    { command: "acfs-update --no-apt", description: "Skip apt (faster)" },
    { command: "acfs-update --dry-run", description: "Preview changes" },
    { command: "acfs-update --yes --quiet", description: "Automated mode" },
    { command: "acfs-update --help", description: "Full help" },
  ];

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="grid grid-cols-[1fr_1fr] divide-x divide-white/[0.06]">
        <div className="p-3 bg-white/[0.02] text-sm font-medium text-white/60">
          Command
        </div>
        <div className="p-3 bg-white/[0.02] text-sm font-medium text-white/60">
          What it does
        </div>
      </div>
      {commands.map((cmd, i) => (
        <div
          key={i}
          className="grid grid-cols-[1fr_1fr] divide-x divide-white/[0.06] border-t border-white/[0.06]"
        >
          <div className="p-3">
            <code className="text-xs font-mono text-primary">{cmd.command}</code>
          </div>
          <div className="p-3 text-sm text-white/70">{cmd.description}</div>
        </div>
      ))}
    </div>
  );
}

// =============================================================================
// FREQUENCY ITEM
// =============================================================================
function FrequencyItem({
  frequency,
  recommendation,
}: {
  frequency: string;
  recommendation: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 6, scale: 1.01 }}
      className="group flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary group-hover:bg-primary/20 group-hover:shadow-lg group-hover:shadow-primary/20 transition-all">
        <Clock className="h-5 w-5" />
      </div>
      <div>
        <span className="font-bold text-white group-hover:text-primary transition-colors">{frequency}</span>
        <span className="text-white/50"> - {recommendation}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CONGRATULATIONS CARD
// =============================================================================
function CongratulationsCard() {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: 0.5 }}
      className="relative rounded-3xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/20 via-teal-500/10 to-cyan-500/20 p-8 backdrop-blur-xl overflow-hidden"
    >
      {/* Decorative elements */}
      <div className="absolute top-0 right-0 w-48 h-48 bg-emerald-500/30 rounded-full blur-3xl" />
      <div className="absolute bottom-0 left-0 w-32 h-32 bg-teal-500/20 rounded-full blur-3xl" />

      <div className="relative text-center">
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ delay: 0.6, type: "spring" }}
          className="inline-flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-emerald-500 to-teal-500 shadow-2xl shadow-emerald-500/50 mb-6"
        >
          <PartyPopper className="h-10 w-10 text-white" />
        </motion.div>

        <h3 className="text-2xl font-bold text-white mb-4">
          You&apos;ve completed the ACFS onboarding!
        </h3>

        <p className="text-white/70 mb-6">You now have:</p>

        <div className="grid gap-3 sm:grid-cols-2 max-w-lg mx-auto text-left">
          <CompletionItem text="A fully configured development VPS" />
          <CompletionItem text="Three powerful coding agents" />
          <CompletionItem text="A complete coordination toolstack" />
          <CompletionItem text="The knowledge to use it all" />
        </div>

        <div className="mt-8 pt-6 border-t border-white/[0.1]">
          <p className="text-2xl font-bold bg-gradient-to-r from-emerald-400 to-teal-400 bg-clip-text text-transparent">
            Go build something amazing!
          </p>
        </div>
      </div>
    </motion.div>
  );
}

function CompletionItem({ text }: { text: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ scale: 1.02, x: 2 }}
      className="group flex items-center gap-3 p-3 rounded-xl bg-white/[0.05] border border-white/[0.08] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.08]"
    >
      <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0 group-hover:scale-110 transition-transform" />
      <span className="text-white/80 text-sm group-hover:text-white transition-colors">{text}</span>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE UPDATE PIPELINE — Multi-Repo Operations Center
// =============================================================================

type RepoSyncStatus = "idle" | "syncing" | "updated" | "conflict" | "error" | "manual";

interface RepoNode {
  id: string;
  name: string;
  shortName: string;
  versionFrom: string;
  versionTo: string;
  category: "system" | "shell" | "agent" | "cloud" | "stack";
  dependsOn: string[];
}

const REPOS: RepoNode[] = [
  { id: "apt", name: "System Packages", shortName: "apt", versionFrom: "24.04.1", versionTo: "24.04.2", category: "system", dependsOn: [] },
  { id: "omz", name: "Oh My Zsh", shortName: "OMZ", versionFrom: "abc1234", versionTo: "def5678", category: "shell", dependsOn: ["apt"] },
  { id: "p10k", name: "Powerlevel10k", shortName: "P10K", versionFrom: "1.19.0", versionTo: "1.20.0", category: "shell", dependsOn: ["omz"] },
  { id: "plugins", name: "ZSH Plugins", shortName: "Plugins", versionFrom: "v0.8.1", versionTo: "v0.9.0", category: "shell", dependsOn: ["omz"] },
  { id: "claude", name: "Claude Code", shortName: "Claude", versionFrom: "1.0.47", versionTo: "1.0.48", category: "agent", dependsOn: ["apt"] },
  { id: "codex", name: "OpenAI Codex", shortName: "Codex", versionFrom: "0.1.24", versionTo: "0.1.25", category: "agent", dependsOn: ["apt"] },
  { id: "agy", name: "Antigravity CLI", shortName: "agy", versionFrom: "1.0.11", versionTo: "1.0.12", category: "agent", dependsOn: ["apt"] },
  { id: "wrangler", name: "Wrangler", shortName: "Wrnglr", versionFrom: "3.91.0", versionTo: "3.92.0", category: "cloud", dependsOn: ["apt"] },
  { id: "supabase", name: "Supabase CLI", shortName: "Supa", versionFrom: "1.200.3", versionTo: "1.201.0", category: "cloud", dependsOn: ["apt"] },
  { id: "vercel", name: "Vercel CLI", shortName: "Vercel", versionFrom: "37.8.0", versionTo: "37.9.0", category: "cloud", dependsOn: ["apt"] },
  { id: "ntm", name: "NTM Stack", shortName: "NTM", versionFrom: "0.9.3", versionTo: "0.9.4", category: "stack", dependsOn: ["apt", "supabase"] },
  { id: "dcg", name: "DCG Tools", shortName: "DCG", versionFrom: "0.4.1", versionTo: "0.4.2", category: "stack", dependsOn: ["apt", "wrangler"] },
];

interface Scenario {
  id: string;
  label: string;
  description: string;
  command: string;
  repoSequence: { repoId: string; finalStatus: RepoSyncStatus; delay: number; errorMsg?: string }[];
  terminalLines: string[];
}

const SCENARIOS: Scenario[] = [
  {
    id: "routine",
    label: "Routine Sync",
    description: "Standard update across all components. Everything pulls cleanly.",
    command: "acfs-update --stack",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "omz", finalStatus: "updated", delay: 400 },
      { repoId: "p10k", finalStatus: "updated", delay: 600 },
      { repoId: "plugins", finalStatus: "updated", delay: 700 },
      { repoId: "claude", finalStatus: "updated", delay: 500 },
      { repoId: "codex", finalStatus: "updated", delay: 600 },
      { repoId: "agy", finalStatus: "updated", delay: 700 },
      { repoId: "wrangler", finalStatus: "updated", delay: 900 },
      { repoId: "supabase", finalStatus: "updated", delay: 1000 },
      { repoId: "vercel", finalStatus: "updated", delay: 1100 },
      { repoId: "ntm", finalStatus: "updated", delay: 1300 },
      { repoId: "dcg", finalStatus: "updated", delay: 1400 },
    ],
    terminalLines: [
      "$ acfs-update --stack",
      "[apt] Fetching package lists...",
      "[apt] 3 packages upgraded",
      "[shell] Pulling oh-my-zsh latest... done",
      "[shell] Pulling p10k... done",
      "[shell] Pulling zsh-plugins... done",
      "[agents] claude update --channel latest",
      "[agents] codex updated to 0.1.25",
      "[agents] agy updated to 1.0.12",
      "[cloud] wrangler 3.91.0 -> 3.92.0",
      "[cloud] supabase 1.200.3 -> 1.201.0",
      "[cloud] vercel 37.8.0 -> 37.9.0",
      "[stack] ntm 0.9.3 -> 0.9.4",
      "[stack] dcg 0.4.1 -> 0.4.2",
      "All 12 components updated successfully!",
    ],
  },
  {
    id: "breaking",
    label: "Breaking Change",
    description: "A major version bump in Wrangler introduces breaking API changes. The updater detects this and pauses.",
    command: "acfs-update --stack",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "omz", finalStatus: "updated", delay: 400 },
      { repoId: "p10k", finalStatus: "updated", delay: 600 },
      { repoId: "plugins", finalStatus: "updated", delay: 700 },
      { repoId: "claude", finalStatus: "updated", delay: 500 },
      { repoId: "codex", finalStatus: "updated", delay: 600 },
      { repoId: "agy", finalStatus: "updated", delay: 700 },
      { repoId: "wrangler", finalStatus: "error", delay: 900, errorMsg: "BREAKING: v4.0.0 requires Node 22+" },
      { repoId: "supabase", finalStatus: "updated", delay: 1000 },
      { repoId: "vercel", finalStatus: "updated", delay: 1100 },
      { repoId: "ntm", finalStatus: "updated", delay: 1300 },
      { repoId: "dcg", finalStatus: "conflict", delay: 1400, errorMsg: "Depends on wrangler@^3" },
    ],
    terminalLines: [
      "$ acfs-update --stack",
      "[apt] 3 packages upgraded",
      "[shell] All shell tools updated",
      "[agents] All agents updated",
      "[cloud] wrangler 3.91.0 -> 4.0.0",
      "WARNING: wrangler 4.0.0 is a major version bump!",
      "  Breaking: Requires Node.js >= 22.0.0",
      "  Current: Node.js 20.11.0",
      "[cloud] Pinning wrangler@3.92.0 (safe)",
      "[stack] dcg depends on wrangler@^3, conflict!",
      "Recommendation: Run 'nvm install 22' first",
      "10/12 components updated, 2 need attention",
    ],
  },
  {
    id: "conflict",
    label: "Version Conflict",
    description: "NTM and Supabase CLI have conflicting dependency requirements. The resolver detects and handles it.",
    command: "acfs-update --stack",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "omz", finalStatus: "updated", delay: 400 },
      { repoId: "p10k", finalStatus: "updated", delay: 600 },
      { repoId: "plugins", finalStatus: "updated", delay: 700 },
      { repoId: "claude", finalStatus: "updated", delay: 500 },
      { repoId: "codex", finalStatus: "updated", delay: 600 },
      { repoId: "agy", finalStatus: "updated", delay: 700 },
      { repoId: "wrangler", finalStatus: "updated", delay: 900 },
      { repoId: "supabase", finalStatus: "conflict", delay: 1000, errorMsg: "Needs @supabase/auth@2.x" },
      { repoId: "vercel", finalStatus: "updated", delay: 1100 },
      { repoId: "ntm", finalStatus: "conflict", delay: 1300, errorMsg: "Needs @supabase/auth@1.x" },
      { repoId: "dcg", finalStatus: "updated", delay: 1400 },
    ],
    terminalLines: [
      "$ acfs-update --stack",
      "[apt] 3 packages upgraded",
      "[shell] All shell tools updated",
      "[agents] All agents updated",
      "[cloud] wrangler updated",
      "[cloud] supabase 1.200.3 -> 1.201.0",
      "CONFLICT: supabase@1.201.0 needs @supabase/auth@2.x",
      "  but ntm@0.9.4 requires @supabase/auth@1.x",
      "[cloud] vercel updated",
      "[stack] ntm: dependency conflict detected",
      "Resolution: Pin supabase@1.200.3 until ntm updates",
      "10/12 components updated, 2 conflicts resolved",
    ],
  },
  {
    id: "automerge",
    label: "Auto-Merge",
    description: "Git-based tools (OMZ, plugins) have local modifications. The updater auto-merges cleanly via stash/pop.",
    command: "acfs-update --stack",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "omz", finalStatus: "updated", delay: 600 },
      { repoId: "p10k", finalStatus: "updated", delay: 800 },
      { repoId: "plugins", finalStatus: "updated", delay: 900 },
      { repoId: "claude", finalStatus: "updated", delay: 500 },
      { repoId: "codex", finalStatus: "updated", delay: 600 },
      { repoId: "agy", finalStatus: "updated", delay: 700 },
      { repoId: "wrangler", finalStatus: "updated", delay: 900 },
      { repoId: "supabase", finalStatus: "updated", delay: 1000 },
      { repoId: "vercel", finalStatus: "updated", delay: 1100 },
      { repoId: "ntm", finalStatus: "updated", delay: 1300 },
      { repoId: "dcg", finalStatus: "updated", delay: 1400 },
    ],
    terminalLines: [
      "$ acfs-update --stack",
      "[apt] 3 packages upgraded",
      "[shell] omz: local modifications detected",
      "[shell] omz: git stash -> pull -> stash pop",
      "[shell] omz: Auto-merge successful!",
      "[shell] p10k: clean pull",
      "[shell] plugins: git stash -> pull -> stash pop",
      "[shell] plugins: Auto-merge successful!",
      "[agents] All agents updated cleanly",
      "[cloud] All cloud CLIs updated",
      "[stack] All stack tools updated",
      "All 12 components updated (2 auto-merged)!",
    ],
  },
  {
    id: "manual",
    label: "Manual Intervention",
    description: "A merge conflict in OMZ custom config cannot be auto-resolved. The updater flags it for manual fix.",
    command: "acfs-update --stack",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "omz", finalStatus: "manual", delay: 600, errorMsg: "Merge conflict in custom/themes" },
      { repoId: "p10k", finalStatus: "updated", delay: 800 },
      { repoId: "plugins", finalStatus: "updated", delay: 900 },
      { repoId: "claude", finalStatus: "updated", delay: 500 },
      { repoId: "codex", finalStatus: "updated", delay: 600 },
      { repoId: "agy", finalStatus: "updated", delay: 700 },
      { repoId: "wrangler", finalStatus: "updated", delay: 900 },
      { repoId: "supabase", finalStatus: "updated", delay: 1000 },
      { repoId: "vercel", finalStatus: "updated", delay: 1100 },
      { repoId: "ntm", finalStatus: "updated", delay: 1300 },
      { repoId: "dcg", finalStatus: "updated", delay: 1400 },
    ],
    terminalLines: [
      "$ acfs-update --stack",
      "[apt] 3 packages upgraded",
      "[shell] omz: local modifications detected",
      "[shell] omz: git stash -> pull -> stash pop",
      "CONFLICT: Auto-merge failed in custom/themes/",
      "  Fix: cd ~/.oh-my-zsh && git mergetool",
      "  Or:  git checkout --theirs custom/themes/",
      "[shell] p10k, plugins updated",
      "[agents] All agents updated",
      "[cloud] All cloud CLIs updated",
      "[stack] All stack tools updated",
      "11/12 updated, 1 needs manual merge",
    ],
  },
  {
    id: "fleet",
    label: "Fleet Rollout",
    description: "Simulates rolling updates across a fleet of VPS instances. Agents update in waves to minimize downtime.",
    command: "acfs-update --fleet --rolling",
    repoSequence: [
      { repoId: "apt", finalStatus: "updated", delay: 0 },
      { repoId: "claude", finalStatus: "updated", delay: 300 },
      { repoId: "omz", finalStatus: "updated", delay: 500 },
      { repoId: "p10k", finalStatus: "updated", delay: 600 },
      { repoId: "plugins", finalStatus: "updated", delay: 650 },
      { repoId: "codex", finalStatus: "updated", delay: 700 },
      { repoId: "agy", finalStatus: "updated", delay: 800 },
      { repoId: "wrangler", finalStatus: "updated", delay: 1000 },
      { repoId: "supabase", finalStatus: "updated", delay: 1100 },
      { repoId: "vercel", finalStatus: "updated", delay: 1200 },
      { repoId: "ntm", finalStatus: "updated", delay: 1400 },
      { repoId: "dcg", finalStatus: "updated", delay: 1500 },
    ],
    terminalLines: [
      "$ acfs-update --fleet --rolling",
      "[fleet] Wave 1/4: System packages",
      "[apt] 3 packages upgraded across fleet",
      "[fleet] Wave 2/4: Shell + Agents (parallel)",
      "[shell] All shell tools synced",
      "[agents] Claude, Codex, Antigravity updated",
      "[fleet] Health check... all instances green",
      "[fleet] Wave 3/4: Cloud CLIs",
      "[cloud] Wrangler, Supabase, Vercel updated",
      "[fleet] Health check... all instances green",
      "[fleet] Wave 4/4: Stack tools",
      "[stack] NTM, DCG updated",
      "Fleet rollout complete! 12/12 components on all instances",
    ],
  },
];

const CATEGORY_COLORS: Record<string, { bg: string; border: string; text: string; fill: string }> = {
  system: { bg: "bg-blue-500/10", border: "border-blue-500/30", text: "text-blue-400", fill: "rgba(96,165,250,0.8)" },
  shell: { bg: "bg-violet-500/10", border: "border-violet-500/30", text: "text-violet-400", fill: "rgba(167,139,250,0.8)" },
  agent: { bg: "bg-orange-500/10", border: "border-orange-500/30", text: "text-orange-400", fill: "rgba(251,146,60,0.8)" },
  cloud: { bg: "bg-emerald-500/10", border: "border-emerald-500/30", text: "text-emerald-400", fill: "rgba(52,211,153,0.8)" },
  stack: { bg: "bg-amber-500/10", border: "border-amber-500/30", text: "text-amber-400", fill: "rgba(251,191,36,0.8)" },
};

const STATUS_COLORS: Record<RepoSyncStatus, { bg: string; border: string; text: string; icon: string }> = {
  idle: { bg: "bg-white/[0.02]", border: "border-white/[0.06]", text: "text-white/30", icon: "text-white/20" },
  syncing: { bg: "bg-amber-500/[0.04]", border: "border-amber-500/40", text: "text-amber-300", icon: "text-amber-400" },
  updated: { bg: "bg-emerald-500/[0.04]", border: "border-emerald-500/30", text: "text-emerald-300", icon: "text-emerald-400" },
  conflict: { bg: "bg-yellow-500/[0.04]", border: "border-yellow-500/30", text: "text-yellow-300", icon: "text-yellow-400" },
  error: { bg: "bg-red-500/[0.04]", border: "border-red-500/30", text: "text-red-300", icon: "text-red-400" },
  manual: { bg: "bg-purple-500/[0.04]", border: "border-purple-500/30", text: "text-purple-300", icon: "text-purple-400" },
};

const STAGE_STEP_DURATION = 800;

function InteractiveUpdatePipeline() {
  const [activeScenario, setActiveScenario] = useState(0);
  const [repoStatuses, setRepoStatuses] = useState<Record<string, RepoSyncStatus>>(
    () => Object.fromEntries(REPOS.map((r) => [r.id, "idle" as RepoSyncStatus]))
  );
  const [repoErrors, setRepoErrors] = useState<Record<string, string>>({});
  const [isRunning, setIsRunning] = useState(false);
  const [terminalOutput, setTerminalOutput] = useState<string[]>([]);
  const [selectedRepo, setSelectedRepo] = useState<string | null>(null);
  const [showGraph, setShowGraph] = useState(false);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);
  const progressRef = useRef<HTMLDivElement>(null);

  const scenario = SCENARIOS[activeScenario];

  const clearAllTimers = useCallback(() => {
    timersRef.current.forEach((t) => clearTimeout(t));
    timersRef.current = [];
  }, []);

  const scheduleTimer = useCallback((cb: () => void, delay: number) => {
    const t = setTimeout(() => {
      timersRef.current = timersRef.current.filter((x) => x !== t);
      cb();
    }, delay);
    timersRef.current.push(t);
    return t;
  }, []);

  const resetAll = useCallback(() => {
    clearAllTimers();
    setRepoStatuses(Object.fromEntries(REPOS.map((r) => [r.id, "idle" as RepoSyncStatus])));
    setRepoErrors({});
    setIsRunning(false);
    setTerminalOutput([]);
    setSelectedRepo(null);
  }, [clearAllTimers]);

  const runScenario = useCallback(() => {
    resetAll();
    setIsRunning(true);

    const seq = scenario.repoSequence;
    const lines = scenario.terminalLines;

    // Add the command line immediately
    scheduleTimer(() => {
      setTerminalOutput([lines[0]]);
    }, 50);

    // Schedule terminal output lines
    const lineDelay = (seq[seq.length - 1].delay + STAGE_STEP_DURATION) / (lines.length - 1);
    for (let i = 1; i < lines.length; i++) {
      const lineIndex = i;
      scheduleTimer(() => {
        setTerminalOutput((prev) => [...prev, lines[lineIndex]]);
      }, lineIndex * lineDelay + 100);
    }

    // Schedule repo status transitions
    for (const step of seq) {
      const stepCopy = step;
      // Start syncing
      scheduleTimer(() => {
        setRepoStatuses((prev) => ({ ...prev, [stepCopy.repoId]: "syncing" }));
      }, stepCopy.delay + 100);

      // Finish with final status
      scheduleTimer(() => {
        setRepoStatuses((prev) => ({ ...prev, [stepCopy.repoId]: stepCopy.finalStatus }));
        if (stepCopy.errorMsg) {
          setRepoErrors((prev) => ({ ...prev, [stepCopy.repoId]: stepCopy.errorMsg as string }));
        }
      }, stepCopy.delay + STAGE_STEP_DURATION);
    }

    // Mark complete
    const totalDuration = seq[seq.length - 1].delay + STAGE_STEP_DURATION + 200;
    scheduleTimer(() => {
      setIsRunning(false);
    }, totalDuration);
  }, [resetAll, scenario, scheduleTimer]);

  // Scroll terminal to bottom on new output
  useEffect(() => {
    if (terminalRef.current) {
      const el = terminalRef.current;
      setTimeout(() => {
        el.scrollTop = el.scrollHeight;
      }, 10);
    }
  }, [terminalOutput]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearAllTimers();
    };
  }, [clearAllTimers]);

  // Reset when scenario changes
  useEffect(() => {
    const t = setTimeout(() => resetAll(), 0);
    return () => clearTimeout(t);
  }, [activeScenario, resetAll]);

  // Derived stats
  const updatedCount = Object.values(repoStatuses).filter((s) => s === "updated").length;
  const errorCount = Object.values(repoStatuses).filter((s) => s === "error" || s === "conflict" || s === "manual").length;
  const syncingCount = Object.values(repoStatuses).filter((s) => s === "syncing").length;
  const totalProgress = ((updatedCount + errorCount) / REPOS.length) * 100;
  const allDone = !isRunning && updatedCount + errorCount === REPOS.length && updatedCount + errorCount > 0;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* Header bar */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex gap-1.5">
          <div className="h-3 w-3 rounded-full bg-red-500/60" />
          <div className="h-3 w-3 rounded-full bg-yellow-500/60" />
          <div className="h-3 w-3 rounded-full bg-green-500/60" />
        </div>
        <code className="ml-3 text-sm font-mono text-white/70 flex-1 truncate">
          <span className="text-emerald-400">$</span> {scenario.command}
        </code>
        <div className="flex items-center gap-1.5">
          <div className={`h-2 w-2 rounded-full ${isRunning ? "bg-amber-400 animate-pulse" : allDone ? "bg-emerald-400" : "bg-white/20"}`} />
          <span className="text-xs text-white/40 font-mono">
            {isRunning ? "RUNNING" : allDone ? "DONE" : "READY"}
          </span>
        </div>
      </div>

      {/* Scenario selector stepper */}
      <div className="px-4 pt-4 pb-2">
        <div className="flex items-center gap-2 mb-3">
          <Settings className="h-4 w-4 text-white/40" />
          <span className="text-xs font-medium text-white/50 uppercase tracking-wider">Scenario</span>
        </div>
        <div className="flex flex-wrap gap-2">
          {SCENARIOS.map((s, i) => (
            <motion.button
              key={s.id}
              whileHover={{ scale: 1.03 }}
              whileTap={{ scale: 0.97 }}
              onClick={() => {
                if (!isRunning) {
                  setActiveScenario(i);
                }
              }}
              disabled={isRunning}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-200 border ${
                activeScenario === i
                  ? "border-primary/40 bg-primary/10 text-primary"
                  : "border-white/[0.06] bg-white/[0.02] text-white/50 hover:text-white/70 hover:border-white/[0.12]"
              } disabled:opacity-40 disabled:cursor-not-allowed`}
            >
              {s.label}
            </motion.button>
          ))}
        </div>
        <AnimatePresence mode="wait">
          <motion.p
            key={scenario.id}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="mt-2 text-xs text-white/40 leading-relaxed"
          >
            {scenario.description}
          </motion.p>
        </AnimatePresence>
      </div>

      {/* Health Dashboard */}
      <div className="px-4 py-3 border-t border-white/[0.04]">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <Zap className="h-4 w-4 text-white/40" />
            <span className="text-xs font-medium text-white/50 uppercase tracking-wider">Health Dashboard</span>
          </div>
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => setShowGraph(!showGraph)}
            className="flex items-center gap-1.5 px-2 py-1 rounded-md border border-white/[0.06] bg-white/[0.02] text-xs text-white/40 hover:text-white/60 hover:border-white/[0.12] transition-all"
          >
            <Package className="h-3 w-3" />
            {showGraph ? "Grid" : "Graph"}
          </motion.button>
        </div>

        <AnimatePresence mode="wait">
          {showGraph ? (
            <motion.div
              key="graph"
              initial={{ opacity: 0, scale: 0.98 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.98 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <DependencyGraph repoStatuses={repoStatuses} />
            </motion.div>
          ) : (
            <motion.div
              key="grid"
              initial={{ opacity: 0, scale: 0.98 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.98 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <RepoGrid
                repoStatuses={repoStatuses}
                repoErrors={repoErrors}
                selectedRepo={selectedRepo}
                onSelectRepo={setSelectedRepo}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Version Comparison Panel (when a repo is selected) */}
      <AnimatePresence>
        {selectedRepo && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="overflow-hidden"
          >
            <VersionComparisonPanel
              repoId={selectedRepo}
              status={repoStatuses[selectedRepo]}
              errorMsg={repoErrors[selectedRepo]}
              onClose={() => setSelectedRepo(null)}
            />
          </motion.div>
        )}
      </AnimatePresence>

      {/* Mini Terminal */}
      <div className="px-4 py-3 border-t border-white/[0.04]">
        <div className="flex items-center gap-2 mb-2">
          <Terminal className="h-4 w-4 text-white/40" />
          <span className="text-xs font-medium text-white/50 uppercase tracking-wider">Live Output</span>
        </div>
        <div
          ref={terminalRef}
          className="rounded-xl bg-black/40 border border-white/[0.06] p-3 h-36 overflow-y-auto font-mono text-xs"
        >
          {terminalOutput.length === 0 ? (
            <span className="text-white/20">Press &quot;Run Scenario&quot; to start...</span>
          ) : (
            terminalOutput.map((line, i) => (
              <TerminalLine key={`${scenario.id}-line-${i}`} line={line} index={i} />
            ))
          )}
        </div>
      </div>

      {/* Success / Warning banner */}
      <AnimatePresence>
        {allDone && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="overflow-hidden"
          >
            <div className={`mx-4 mb-3 rounded-xl border p-3 ${
              errorCount > 0
                ? "border-yellow-500/30 bg-gradient-to-r from-yellow-500/10 to-amber-500/10"
                : "border-emerald-500/30 bg-gradient-to-r from-emerald-500/15 to-teal-500/15"
            }`}>
              <div className="flex items-center justify-center gap-3">
                {errorCount > 0 ? (
                  <>
                    <AlertTriangle className="h-5 w-5 text-yellow-400" />
                    <span className="text-sm font-bold text-yellow-300">
                      {updatedCount} updated, {errorCount} need attention
                    </span>
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="h-5 w-5 text-emerald-400" />
                    <span className="text-sm font-bold text-emerald-300">
                      All {REPOS.length} components updated!
                    </span>
                    <CheckCircle2 className="h-5 w-5 text-emerald-400" />
                  </>
                )}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Bottom bar: progress + controls */}
      <div className="flex items-center justify-between gap-4 px-4 py-3 border-t border-white/[0.06] bg-white/[0.02]">
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-xs text-white/50">
              {allDone
                ? "Complete"
                : isRunning
                  ? `Syncing... ${updatedCount + errorCount}/${REPOS.length}`
                  : "Ready"}
            </span>
            <div className="flex items-center gap-3">
              {syncingCount > 0 && (
                <span className="text-xs text-amber-400/70 flex items-center gap-1">
                  <Loader2 className="h-3 w-3 animate-spin" />
                  {syncingCount} active
                </span>
              )}
              {errorCount > 0 && (
                <span className="text-xs text-red-400/70">
                  {errorCount} issues
                </span>
              )}
              <span className="text-xs text-white/40">
                {Math.round(totalProgress)}%
              </span>
            </div>
          </div>
          <div ref={progressRef} className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className={`h-full rounded-full ${
                errorCount > 0
                  ? "bg-gradient-to-r from-emerald-500 via-yellow-500 to-emerald-500"
                  : "bg-gradient-to-r from-emerald-500 to-teal-400"
              }`}
              initial={{ width: "0%" }}
              animate={{ width: `${totalProgress}%` }}
              transition={{ type: "spring", stiffness: 100, damping: 20 }}
            />
          </div>
        </div>

        {allDone || (!isRunning && updatedCount + errorCount > 0) ? (
          <motion.button
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={{ type: "spring", stiffness: 400, damping: 25 }}
            onClick={resetAll}
            className="flex items-center gap-2 rounded-lg border border-white/[0.1] bg-white/[0.04] px-4 py-2 text-sm font-medium text-white/80 hover:bg-white/[0.08] hover:text-white transition-colors"
          >
            <RotateCcw className="h-4 w-4" />
            Reset
          </motion.button>
        ) : (
          <motion.button
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={{ type: "spring", stiffness: 400, damping: 25 }}
            onClick={runScenario}
            disabled={isRunning}
            className="flex items-center gap-2 rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-4 py-2 text-sm font-medium text-emerald-300 hover:bg-emerald-500/20 hover:text-emerald-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            <Play className="h-4 w-4" />
            Run Scenario
          </motion.button>
        )}
      </div>
    </motion.div>
  );
}

// =============================================================================
// REPO GRID — Animated repo tiles with status indicators
// =============================================================================

function RepoGrid({
  repoStatuses,
  repoErrors,
  selectedRepo,
  onSelectRepo,
}: {
  repoStatuses: Record<string, RepoSyncStatus>;
  repoErrors: Record<string, string>;
  selectedRepo: string | null;
  onSelectRepo: (id: string | null) => void;
}) {
  return (
    <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
      {REPOS.map((repo, i) => {
        const status = repoStatuses[repo.id];
        const catColor = CATEGORY_COLORS[repo.category];
        const statusColor = STATUS_COLORS[status];
        const isSelected = selectedRepo === repo.id;
        const hasError = repoErrors[repo.id];

        return (
          <motion.button
            key={repo.id}
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.03 }}
            whileHover={{ scale: 1.04, y: -2 }}
            whileTap={{ scale: 0.97 }}
            onClick={() => onSelectRepo(isSelected ? null : repo.id)}
            className={`relative flex flex-col items-center gap-1.5 p-3 rounded-xl border transition-all duration-200 ${statusColor.bg} ${
              isSelected ? "border-primary/40 ring-1 ring-primary/20" : statusColor.border
            }`}
          >
            {/* Syncing glow */}
            {status === "syncing" && (
              <motion.div
                className="absolute inset-0 rounded-xl border border-amber-500/20"
                animate={{ opacity: [0.2, 0.5, 0.2] }}
                transition={{ duration: 1.2, repeat: Infinity, repeatType: "reverse" }}
                style={{ boxShadow: "0 0 16px rgba(245, 158, 11, 0.1)" }}
              />
            )}

            {/* Status icon */}
            <div className="relative">
              <RepoStatusIcon status={status} />
            </div>

            {/* Name */}
            <span className={`text-xs font-medium truncate w-full text-center ${statusColor.text}`}>
              {repo.shortName}
            </span>

            {/* Category badge */}
            <span className={`text-[9px] px-1.5 py-0.5 rounded-full ${catColor.bg} ${catColor.text} border ${catColor.border}`}>
              {repo.category}
            </span>

            {/* Error indicator dot */}
            {hasError && (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                className="absolute -top-1 -right-1 h-3 w-3 rounded-full bg-red-500 border-2 border-black/50"
              />
            )}
          </motion.button>
        );
      })}
    </div>
  );
}

// =============================================================================
// REPO STATUS ICON — Animated icon per status
// =============================================================================

function RepoStatusIcon({ status }: { status: RepoSyncStatus }) {
  return (
    <AnimatePresence mode="wait">
      {status === "idle" && (
        <motion.div
          key="idle"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{ type: "spring", stiffness: 300, damping: 25 }}
        >
          <Minus className="h-4 w-4 text-white/20" />
        </motion.div>
      )}
      {status === "syncing" && (
        <motion.div
          key="syncing"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1, rotate: 360 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{
            type: "spring",
            stiffness: 200,
            damping: 20,
            rotate: { repeat: Infinity, duration: 1, ease: "linear" },
          }}
        >
          <Loader2 className="h-4 w-4 text-amber-400" />
        </motion.div>
      )}
      {status === "updated" && (
        <motion.div
          key="updated"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{ type: "spring", stiffness: 400, damping: 20 }}
        >
          <CheckCircle2 className="h-4 w-4 text-emerald-400" />
        </motion.div>
      )}
      {status === "conflict" && (
        <motion.div
          key="conflict"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{ type: "spring", stiffness: 400, damping: 20 }}
        >
          <AlertTriangle className="h-4 w-4 text-yellow-400" />
        </motion.div>
      )}
      {status === "error" && (
        <motion.div
          key="error"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{ type: "spring", stiffness: 400, damping: 20 }}
        >
          <XCircle className="h-4 w-4 text-red-400" />
        </motion.div>
      )}
      {status === "manual" && (
        <motion.div
          key="manual"
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.5 }}
          transition={{ type: "spring", stiffness: 400, damping: 20 }}
        >
          <Wrench className="h-4 w-4 text-purple-400" />
        </motion.div>
      )}
    </AnimatePresence>
  );
}

// =============================================================================
// SVG DEPENDENCY GRAPH — Shows repo relationships
// =============================================================================

function DependencyGraph({ repoStatuses }: { repoStatuses: Record<string, RepoSyncStatus> }) {
  // Layout: position repos in a tree-like graph
  const positions: Record<string, { x: number; y: number }> = {
    apt: { x: 250, y: 25 },
    omz: { x: 80, y: 75 },
    p10k: { x: 30, y: 130 },
    plugins: { x: 130, y: 130 },
    claude: { x: 210, y: 75 },
    codex: { x: 290, y: 75 },
    agy: { x: 370, y: 75 },
    wrangler: { x: 450, y: 75 },
    supabase: { x: 160, y: 130 },
    vercel: { x: 350, y: 130 },
    ntm: { x: 160, y: 185 },
    dcg: { x: 400, y: 185 },
  };

  const statusFill = (status: RepoSyncStatus) => {
    switch (status) {
      case "syncing": return "rgba(245,158,11,0.7)";
      case "updated": return "rgba(52,211,153,0.7)";
      case "conflict": return "rgba(234,179,8,0.7)";
      case "error": return "rgba(239,68,68,0.7)";
      case "manual": return "rgba(168,85,247,0.7)";
      default: return "rgba(255,255,255,0.15)";
    }
  };

  const statusStroke = (status: RepoSyncStatus) => {
    switch (status) {
      case "syncing": return "rgba(245,158,11,0.5)";
      case "updated": return "rgba(52,211,153,0.4)";
      case "conflict": return "rgba(234,179,8,0.4)";
      case "error": return "rgba(239,68,68,0.4)";
      case "manual": return "rgba(168,85,247,0.4)";
      default: return "rgba(255,255,255,0.08)";
    }
  };

  return (
    <div className="rounded-xl border border-white/[0.06] bg-black/30 p-2 overflow-hidden">
      <svg viewBox="0 0 500 210" className="w-full h-auto" aria-label="Dependency graph of update components">
        {/* Draw dependency edges */}
        {REPOS.map((repo) =>
          repo.dependsOn.map((depId) => {
            const from = positions[depId];
            const to = positions[repo.id];
            if (!from || !to) return null;
            const depStatus = repoStatuses[depId];
            const isActive = depStatus === "syncing" || depStatus === "updated";
            return (
              <line
                key={`${depId}-${repo.id}`}
                x1={from.x}
                y1={from.y + 12}
                x2={to.x}
                y2={to.y - 12}
                stroke={isActive ? "rgba(52,211,153,0.25)" : "rgba(255,255,255,0.06)"}
                strokeWidth={1}
                strokeDasharray={isActive ? "none" : "3 3"}
              />
            );
          })
        )}

        {/* Draw repo nodes */}
        {REPOS.map((repo) => {
          const pos = positions[repo.id];
          if (!pos) return null;
          const status = repoStatuses[repo.id];
          const catColor = CATEGORY_COLORS[repo.category];

          return (
            <g key={repo.id}>
              {/* Glow for syncing */}
              {status === "syncing" && (
                <motion.circle
                  cx={pos.x}
                  cy={pos.y}
                  r={18}
                  fill="none"
                  stroke="rgba(245,158,11,0.3)"
                  strokeWidth={1}
                  animate={{ r: [18, 24, 18], opacity: [0.3, 0.6, 0.3] }}
                  transition={{ duration: 1.2, repeat: Infinity, repeatType: "reverse" }}
                />
              )}

              {/* Node circle */}
              <circle
                cx={pos.x}
                cy={pos.y}
                r={14}
                fill={statusFill(status)}
                stroke={statusStroke(status)}
                strokeWidth={1.5}
              />

              {/* Category color ring */}
              <circle
                cx={pos.x}
                cy={pos.y}
                r={16}
                fill="none"
                stroke={catColor.fill}
                strokeWidth={0.5}
                strokeOpacity={0.3}
              />

              {/* Label */}
              <text
                x={pos.x}
                y={pos.y + 3.5}
                textAnchor="middle"
                fill="white"
                fillOpacity={status === "idle" ? 0.3 : 0.9}
                fontSize={7}
                fontFamily="monospace"
                fontWeight={600}
              >
                {repo.shortName}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

// =============================================================================
// VERSION COMPARISON PANEL — old -> new versions with changelog
// =============================================================================

function VersionComparisonPanel({
  repoId,
  status,
  errorMsg,
  onClose,
}: {
  repoId: string;
  status: RepoSyncStatus;
  errorMsg?: string;
  onClose: () => void;
}) {
  const repo = REPOS.find((r) => r.id === repoId);
  if (!repo) return null;

  const catColor = CATEGORY_COLORS[repo.category];
  const statusColor = STATUS_COLORS[status];

  const changelogs: Record<string, string[]> = {
    apt: ["Security patches for openssl", "Updated ca-certificates bundle", "Performance fix for dpkg"],
    omz: ["New git aliases added", "Faster startup time", "Fixed autocompletion for bun"],
    p10k: ["Nerd Font v3 icon support", "Improved segment rendering"],
    plugins: ["zsh-autosuggestions: better history matching", "zsh-syntax-highlighting: new themes"],
    claude: ["Improved tool use reliability", "Faster streaming responses", "New /compact command"],
    codex: ["Multi-file editing support", "Better error recovery", "Sandbox improvements"],
    agy: ["Pinned Gemini 3.1 Pro model", "DCG hook integration", "Terminal settings refreshed"],
    wrangler: ["D1 export support", "Hyperdrive GA", "Pages build caching"],
    supabase: ["Edge Functions v2", "Branching GA", "Realtime improvements"],
    vercel: ["Fluid compute support", "Faster deploys", "Improved DX for monorepos"],
    ntm: ["New migration engine", "Schema diffing", "Better TypeScript types"],
    dcg: ["Parallel generation", "Template caching", "New output formats"],
  };

  const changes = changelogs[repoId] ?? ["No changelog available"];

  return (
    <div className="mx-4 mb-3 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className={`text-sm font-bold ${catColor.text}`}>{repo.name}</span>
          <span className={`text-xs px-1.5 py-0.5 rounded-full ${statusColor.bg} ${statusColor.border} border ${statusColor.text}`}>
            {status}
          </span>
        </div>
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onClose}
          className="text-white/30 hover:text-white/60 transition-colors"
        >
          <XCircle className="h-4 w-4" />
        </motion.button>
      </div>

      {/* Version comparison */}
      <div className="flex items-center gap-3 mb-3">
        <div className="flex-1 rounded-lg border border-white/[0.06] bg-black/20 p-2 text-center">
          <span className="text-[10px] text-white/30 block mb-0.5">Current</span>
          <code className="text-xs font-mono text-red-400/80">{repo.versionFrom}</code>
        </div>
        <div className="flex items-center">
          <RefreshCw className={`h-4 w-4 ${status === "syncing" ? "text-amber-400 animate-spin" : "text-white/20"}`} />
        </div>
        <div className="flex-1 rounded-lg border border-white/[0.06] bg-black/20 p-2 text-center">
          <span className="text-[10px] text-white/30 block mb-0.5">Target</span>
          <code className="text-xs font-mono text-emerald-400/80">{repo.versionTo}</code>
        </div>
      </div>

      {/* Error message */}
      {errorMsg && (
        <div className="rounded-lg border border-red-500/20 bg-red-500/5 p-2 mb-3">
          <span className="text-xs text-red-400 font-mono">{errorMsg}</span>
        </div>
      )}

      {/* Changelog */}
      <div className="space-y-1">
        <span className="text-[10px] text-white/30 uppercase tracking-wider">Changelog highlights</span>
        {changes.map((change, i) => (
          <motion.div
            key={`${repoId}-change-${i}`}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.05 }}
            className="flex items-start gap-2 text-xs text-white/50"
          >
            <Sparkles className="h-3 w-3 text-primary/50 shrink-0 mt-0.5" />
            <span>{change}</span>
          </motion.div>
        ))}
      </div>

      {/* Dependencies */}
      {repo.dependsOn.length > 0 && (
        <div className="mt-3 pt-2 border-t border-white/[0.04]">
          <span className="text-[10px] text-white/30 uppercase tracking-wider">Depends on</span>
          <div className="flex flex-wrap gap-1 mt-1">
            {repo.dependsOn.map((depId) => {
              const dep = REPOS.find((r) => r.id === depId);
              return (
                <span
                  key={depId}
                  className="text-[10px] px-1.5 py-0.5 rounded bg-white/[0.04] border border-white/[0.06] text-white/40 font-mono"
                >
                  {dep?.shortName ?? depId}
                </span>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// =============================================================================
// TERMINAL LINE — color-coded output line
// =============================================================================

function TerminalLine({ line, index }: { line: string; index: number }) {
  const getLineColor = (text: string) => {
    if (text.startsWith("$")) return "text-emerald-400";
    if (text.startsWith("WARNING") || text.startsWith("CONFLICT")) return "text-yellow-400";
    if (text.includes("error") || text.includes("BREAKING")) return "text-red-400";
    if (text.includes("updated") || text.includes("done") || text.includes("success") || text.includes("Complete") || text.includes("complete")) return "text-emerald-400/80";
    if (text.startsWith("[fleet]")) return "text-cyan-400/70";
    if (text.startsWith("  ")) return "text-white/40";
    if (text.includes("Recommendation") || text.includes("Fix:") || text.includes("Or:") || text.includes("Resolution")) return "text-violet-400/70";
    return "text-white/50";
  };

  return (
    <motion.div
      initial={{ opacity: 0, x: -6 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ type: "spring", stiffness: 300, damping: 25, delay: index * 0.02 }}
      className={`leading-relaxed ${getLineColor(line)}`}
    >
      {line}
    </motion.div>
  );
}
