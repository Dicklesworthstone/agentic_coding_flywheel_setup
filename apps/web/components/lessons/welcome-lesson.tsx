"use client";

import { motion } from "@/components/motion";
import {
  Terminal,
  Code2,
  Bot,
  Cpu,
  Layers,
  Monitor,
  Server,
  Wifi,
  GitBranch,
  Wrench,
  ChevronRight,
  Laptop,
  Cloud,
  Zap,
  BookOpen,
} from "lucide-react";
import {
  Section,
  Paragraph,
  FeatureCard,
  FeatureGrid,
  TipBox,
  StepList,
  DiagramBox,
  Highlight,
  Divider,
  GoalBanner,
} from "./lesson-components";

export function WelcomeLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand what you have and what you&apos;re about to learn.
      </GoalBanner>

      {/* What You Now Have Section */}
      <Section
        title="What You Now Have"
        icon={<Zap className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph highlight>
          Congratulations! You&apos;ve just set up a fully-armed{" "}
          <Highlight>agentic engineering workstation</Highlight>.
        </Paragraph>

        <div className="mt-8">
          <Paragraph>Here&apos;s what&apos;s installed on your VPS:</Paragraph>
        </div>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Terminal className="h-5 w-5" />}
              title="Beautiful Terminal"
              description="zsh, Oh My Zsh, and Powerlevel10k for a stunning shell experience"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Wrench className="h-5 w-5" />}
              title="Modern CLI Tools"
              description="lsd, bat, ripgrep, fzf, and zoxide for supercharged productivity"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Code2 className="h-5 w-5" />}
              title="Language Runtimes"
              description="JavaScript (Bun), Python (uv), Rust, and Go ready to go"
              gradient="from-sky-500/20 to-blue-500/20"
            />
            <FeatureCard
              icon={<Bot className="h-5 w-5" />}
              title="Three Coding Agents"
              description="Claude Code (cc), Codex CLI (cod), and Gemini CLI (gmi)"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        {/* Agent Cards */}
        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <AgentCard
            name="Claude Code"
            shortcut="cc"
            color="from-orange-500 to-amber-500"
          />
          <AgentCard
            name="Codex CLI"
            shortcut="cod"
            color="from-emerald-500 to-teal-500"
          />
          <AgentCard
            name="Gemini CLI"
            shortcut="gmi"
            color="from-blue-500 to-indigo-500"
          />
        </div>
      </Section>

      <Divider />

      {/* The Mental Model Section */}
      <Section
        title="The Mental Model"
        icon={<Layers className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>Think of your setup like this:</Paragraph>

        {/* Architecture Diagram */}
        <div className="mt-8 relative">
          <ArchitectureDiagram />
        </div>

        <div className="mt-8 space-y-4">
          <Paragraph>
            Your laptop is just the{" "}
            <Highlight>remote control</Highlight>. The real work happens on the
            VPS.
          </Paragraph>
          <Paragraph>
            If your SSH connection drops? No problem. Your work continues in
            tmux.
          </Paragraph>
        </div>
      </Section>

      <Divider />

      {/* What This Tutorial Will Teach You */}
      <Section
        title="What You'll Learn"
        icon={<BookOpen className="h-5 w-5" />}
        delay={0.3}
      >
        <StepList
          steps={[
            {
              title: "Linux basics",
              description: "Navigating the filesystem with confidence",
            },
            {
              title: "SSH fundamentals",
              description: "Staying connected to your VPS",
            },
            {
              title: "tmux essentials",
              description: "Persistent sessions that survive disconnects",
            },
            {
              title: "Agent commands",
              description: "Talking to Claude, Codex, and Gemini",
            },
            {
              title: "NTM mastery",
              description: "Orchestrating multiple agents at once",
            },
            {
              title: "The flywheel workflow",
              description: "Putting it all together for maximum velocity",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Tip */}
      <TipBox variant="tip">
        If you ever break something, you can delete this VPS and re-run ACFS.
        That&apos;s the beauty of VPS development!
      </TipBox>
    </div>
  );
}

// =============================================================================
// AGENT CARD - Individual agent display
// =============================================================================
function AgentCard({
  name,
  shortcut,
  color,
}: {
  name: string;
  shortcut: string;
  color: string;
}) {
  return (
    <motion.div
      whileHover={{ y: -4, scale: 1.03 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.15]"
    >
      {/* Gradient background on hover */}
      <div
        className={`absolute inset-0 bg-gradient-to-br ${color} opacity-0 group-hover:opacity-10 transition-opacity duration-500`}
      />

      <div className="relative flex flex-col items-center text-center">
        <div
          className={`flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br ${color} shadow-lg mb-4`}
        >
          <Bot className="h-7 w-7 text-white" />
        </div>
        <span className="font-bold text-white">{name}</span>
        <code className="mt-2 px-3 py-1.5 rounded-lg bg-black/40 border border-white/[0.1] text-sm font-mono text-white/60">
          {shortcut}
        </code>
      </div>
    </motion.div>
  );
}

// =============================================================================
// ARCHITECTURE DIAGRAM - Visual representation of the system
// =============================================================================
function ArchitectureDiagram() {
  return (
    <div className="relative p-8 rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glow effects */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/10 rounded-full blur-3xl" />

      <div className="relative grid grid-cols-1 md:grid-cols-[1fr_auto_1fr] gap-6 items-center">
        {/* Left side - Your Laptop */}
        <motion.div
          initial={{ opacity: 0, x: -30 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.2 }}
        >
          <DiagramBox
            label="Your Laptop"
            sublabel="The Cockpit"
            icon={<Laptop className="h-8 w-8" />}
            gradient="from-sky-500/20 to-blue-500/20"
          />
        </motion.div>

        {/* Connection Arrow */}
        <motion.div
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.4 }}
          className="flex flex-col items-center gap-2"
        >
          <div className="hidden md:flex items-center gap-2">
            <div className="h-px w-8 bg-gradient-to-r from-sky-500/50 to-primary/50" />
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-black/40 border border-white/[0.1]">
              <Wifi className="h-3.5 w-3.5 text-primary" />
              <span className="text-xs font-mono text-white/50">SSH</span>
            </div>
            <div className="h-px w-8 bg-gradient-to-r from-primary/50 to-emerald-500/50" />
            <ChevronRight className="h-5 w-5 text-emerald-400" />
          </div>
          <div className="md:hidden flex flex-col items-center gap-2 py-4">
            <div className="w-px h-8 bg-gradient-to-b from-sky-500/50 to-primary/50" />
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-black/40 border border-white/[0.1]">
              <Wifi className="h-3.5 w-3.5 text-primary" />
              <span className="text-xs font-mono text-white/50">SSH</span>
            </div>
            <div className="w-px h-8 bg-gradient-to-b from-primary/50 to-emerald-500/50" />
            <ChevronRight className="h-5 w-5 text-emerald-400 rotate-90" />
          </div>
        </motion.div>

        {/* Right side - VPS */}
        <motion.div
          initial={{ opacity: 0, x: 30 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.6 }}
          className="space-y-4"
        >
          <DiagramBox
            label="Your VPS"
            sublabel="The Engine Room"
            icon={<Cloud className="h-8 w-8" />}
            gradient="from-emerald-500/20 to-teal-500/20"
          />

          {/* VPS Components */}
          <div className="grid grid-cols-3 gap-3">
            <VPSComponent
              icon={<Server className="h-4 w-4" />}
              label="tmux"
              sublabel="Sessions"
            />
            <VPSComponent
              icon={<Bot className="h-4 w-4" />}
              label="Agents"
              sublabel="Workers"
            />
            <VPSComponent
              icon={<Cpu className="h-4 w-4" />}
              label="NTM"
              sublabel="Orchestrator"
            />
          </div>
        </motion.div>
      </div>
    </div>
  );
}

function VPSComponent({
  icon,
  label,
  sublabel,
}: {
  icon: React.ReactNode;
  label: string;
  sublabel: string;
}) {
  return (
    <div className="flex flex-col items-center p-3 rounded-xl border border-white/[0.06] bg-white/[0.02] text-center">
      <div className="text-white/60 mb-1">{icon}</div>
      <span className="text-xs font-medium text-white">{label}</span>
      <span className="text-[10px] text-white/40">{sublabel}</span>
    </div>
  );
}
