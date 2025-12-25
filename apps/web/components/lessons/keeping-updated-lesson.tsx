"use client";

import { motion } from "@/components/motion";
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
            description="Claude, Codex, Gemini"
          />
          <UpdateItem
            icon={<Settings className="h-4 w-4" />}
            label="Cloud CLIs"
            description="Wrangler, Supabase, Vercel"
          />
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
0 3 * * 0 /home/ubuntu/.local/bin/acfs-update --yes --quiet >> ~/.acfs/logs/cron-update.log 2>&1`}
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
            solution={`# Wait for other apt operations to finish, or:
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a`}
          />

          <TroubleshootingCard
            title="Agent update failed"
            description="Try updating directly:"
            solution={`# Claude
claude update

# Codex
bun install -g --trust @openai/codex@latest

# Gemini
bun install -g --trust @google/gemini-cli@latest`}
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
      className="relative rounded-2xl border border-white/[0.08] bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl"
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
    <div className="flex items-center gap-3">
      <div className="text-emerald-400 h-5 w-5">{icon}</div>
      <span className="text-white/70">{text}</span>
    </div>
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
    <div className="flex items-center gap-3 p-3 rounded-xl border border-white/[0.08] bg-white/[0.02]">
      <div className="text-primary">{icon}</div>
      <div>
        <span className="text-sm font-medium text-white">{label}</span>
        <span className="text-xs text-white/50 block">{description}</span>
      </div>
    </div>
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
      className="space-y-3"
    >
      <h4 className="font-bold text-white">{title}</h4>
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
      className="relative rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-6 backdrop-blur-xl"
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
    <div className="flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02]">
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
        <Clock className="h-5 w-5" />
      </div>
      <div>
        <span className="font-bold text-white">{frequency}</span>
        <span className="text-white/50"> - {recommendation}</span>
      </div>
    </div>
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
    <div className="flex items-center gap-3 p-3 rounded-xl bg-white/[0.05] border border-white/[0.08]">
      <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0" />
      <span className="text-white/80 text-sm">{text}</span>
    </div>
  );
}
