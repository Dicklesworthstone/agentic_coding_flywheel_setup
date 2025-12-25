"use client";

import { motion } from "@/components/motion";
import {
  Cpu,
  Terminal,
  Play,
  Layers,
  Send,
  List,
  Link2,
  Zap,
  LayoutGrid,
  Bot,
  Sparkles,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
} from "./lesson-components";

export function NtmCoreLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master NTM (Named Tmux Manager) for orchestrating agents.
      </GoalBanner>

      {/* What Is NTM */}
      <Section
        title="What Is NTM?"
        icon={<Cpu className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          NTM is your <Highlight>command center</Highlight> for managing
          multiple coding agents.
        </Paragraph>
        <Paragraph>
          It creates organized tmux sessions with dedicated panes for each
          agent.
        </Paragraph>

        <div className="mt-8">
          <NtmDiagram />
        </div>
      </Section>

      <Divider />

      {/* The NTM Tutorial */}
      <Section
        title="The NTM Tutorial"
        icon={<Play className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          NTM has a built-in tutorial. Start it now:
        </Paragraph>
        <div className="mt-6">
          <CodeBlock code="ntm tutorial" />
        </div>
        <Paragraph>
          This will walk you through the basics interactively.
        </Paragraph>
      </Section>

      <Divider />

      {/* Essential NTM Commands */}
      <Section
        title="Essential NTM Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-8">
          <CommandSection
            title="Check Dependencies"
            icon={<Layers className="h-4 w-4" />}
            code="ntm deps -v"
            description="Verifies all required tools are installed."
          />

          <CommandSection
            title="Create a Project Session"
            icon={<LayoutGrid className="h-4 w-4" />}
            code="ntm spawn myproject --cc=2 --cod=1 --gmi=1"
            description="Creates a tmux session with multiple agent panes."
          >
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <SessionComponent
                label="2 Claude Code panes"
                color="from-orange-500 to-amber-500"
              />
              <SessionComponent
                label="1 Codex pane"
                color="from-emerald-500 to-teal-500"
              />
              <SessionComponent
                label="1 Gemini pane"
                color="from-blue-500 to-indigo-500"
              />
              <SessionComponent
                label='Session: "myproject"'
                color="from-violet-500 to-purple-500"
              />
            </div>
          </CommandSection>

          <CommandSection
            title="List Sessions"
            icon={<List className="h-4 w-4" />}
            code="ntm list"
            description="See all running NTM sessions."
          />

          <CommandSection
            title="Attach to a Session"
            icon={<Link2 className="h-4 w-4" />}
            code="ntm attach myproject"
            description="Jump into an existing session to see agent output."
          />

          <CommandSection
            title="Send a Command to All Agents"
            icon={<Send className="h-4 w-4" />}
            code='ntm send myproject "Analyze this codebase and summarize what it does"'
            description="This sends the same prompt to ALL agents in the session!"
          />

          <CommandSection
            title="Send to Specific Agent Type"
            icon={<Bot className="h-4 w-4" />}
            code={`ntm send myproject --cc "Focus on the API layer"
ntm send myproject --cod "Focus on the frontend"`}
            description="Target specific agent types with different tasks."
          />
        </div>
      </Section>

      <Divider />

      {/* The Power of NTM */}
      <Section
        title="The Power of NTM"
        icon={<Zap className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>Imagine this workflow:</Paragraph>

        <div className="mt-6">
          <WorkflowSteps />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            That&apos;s the power of multi-agent development—different
            perspectives working in parallel!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Quick Session Template */}
      <Section
        title="Quick Session Template"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>For a typical project:</Paragraph>

        <div className="mt-6">
          <CodeBlock code="ntm spawn myproject --cc=2 --cod=1 --gmi=1" />
        </div>

        <div className="mt-6">
          <AgentRatioCard />
        </div>
      </Section>

      <Divider />

      {/* Session Navigation */}
      <Section
        title="Session Navigation"
        icon={<LayoutGrid className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>Once inside an NTM session:</Paragraph>

        <div className="mt-6">
          <KeyboardShortcutTable
            shortcuts={[
              { keys: ["Ctrl+a", "n"], action: "Next window" },
              { keys: ["Ctrl+a", "p"], action: "Previous window" },
              { keys: ["Ctrl+a", "h/j/k/l"], action: "Move between panes" },
              { keys: ["Ctrl+a", "z"], action: "Zoom current pane" },
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
          code={`# Create a test session
$ ntm spawn test-session --cc=1

# List sessions
$ ntm list

# Send a simple task
$ ntm send test-session "Say hello and confirm you're working"

# Attach to see the result
$ ntm attach test-session`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// NTM DIAGRAM - Visual representation of NTM
// =============================================================================
function NtmDiagram() {
  return (
    <div className="relative p-6 rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-violet-500/10 rounded-full blur-3xl" />

      <div className="relative flex flex-col items-center gap-6">
        {/* NTM Command Center */}
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="flex items-center gap-4 px-6 py-4 rounded-2xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30"
        >
          <Cpu className="h-8 w-8 text-primary" />
          <div>
            <span className="font-bold text-white">NTM</span>
            <span className="text-sm text-white/50 block">Command Center</span>
          </div>
        </motion.div>

        {/* Connecting lines */}
        <div className="flex items-center gap-2">
          <div className="w-px h-8 bg-gradient-to-b from-primary/50 to-white/20" />
        </div>

        {/* Agent Panes */}
        <div className="grid grid-cols-3 gap-4 w-full max-w-lg">
          <AgentPane name="Claude" shortcut="cc" color="from-orange-500 to-amber-500" delay={0.3} />
          <AgentPane name="Codex" shortcut="cod" color="from-emerald-500 to-teal-500" delay={0.4} />
          <AgentPane name="Gemini" shortcut="gmi" color="from-blue-500 to-indigo-500" delay={0.5} />
        </div>
      </div>
    </div>
  );
}

function AgentPane({
  name,
  shortcut,
  color,
  delay,
}: {
  name: string;
  shortcut: string;
  color: string;
  delay: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay }}
      whileHover={{ y: -4, scale: 1.05 }}
      className={`group flex flex-col items-center p-4 rounded-xl bg-gradient-to-br ${color} bg-opacity-20 border border-white/[0.1] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.2]`}
    >
      <Bot className="h-6 w-6 text-white mb-2 group-hover:scale-110 transition-transform" />
      <span className="text-sm font-medium text-white">{name}</span>
      <code className="text-xs text-white/60 mt-1 group-hover:text-white/80 transition-colors">{shortcut}</code>
    </motion.div>
  );
}

// =============================================================================
// COMMAND SECTION - Display a command with description
// =============================================================================
function CommandSection({
  title,
  icon,
  code,
  description,
  children,
}: {
  title: string;
  icon: React.ReactNode;
  code: string;
  description: string;
  children?: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group space-y-4 p-4 -mx-4 rounded-xl transition-all duration-300 hover:bg-white/[0.02]"
    >
      <div className="flex items-center gap-3">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary group-hover:bg-primary/20 group-hover:shadow-lg group-hover:shadow-primary/20 transition-all">
          {icon}
        </div>
        <h4 className="text-lg font-semibold text-white group-hover:text-primary transition-colors">{title}</h4>
      </div>
      <CodeBlock code={code} />
      <p className="text-white/60">{description}</p>
      {children}
    </motion.div>
  );
}

// =============================================================================
// SESSION COMPONENT - Display session info
// =============================================================================
function SessionComponent({
  label,
  color,
}: {
  label: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ scale: 1.02, x: 2 }}
      className={`group flex items-center gap-3 p-3 rounded-xl bg-gradient-to-br ${color} bg-opacity-10 border border-white/[0.08] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]`}
    >
      <div className={`h-2 w-2 rounded-full bg-gradient-to-br ${color} group-hover:scale-125 transition-transform`} />
      <span className="text-sm text-white/70 group-hover:text-white/90 transition-colors">{label}</span>
    </motion.div>
  );
}

// =============================================================================
// WORKFLOW STEPS - Visual workflow
// =============================================================================
function WorkflowSteps() {
  const steps = [
    "Spawn a session with multiple agents",
    "Send a high-level task to all of them",
    "Each agent works in parallel",
    "Compare their solutions",
    "Take the best parts from each",
  ];

  return (
    <div className="relative space-y-4">
      <div className="absolute left-4 top-4 bottom-4 w-px bg-gradient-to-b from-primary/50 via-violet-500/50 to-emerald-500/50" />

      {steps.map((step, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.1 }}
          whileHover={{ x: 6, scale: 1.01 }}
          className="group relative flex items-center gap-4 pl-2 py-1 rounded-lg transition-all duration-300"
        >
          <div className="relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-primary to-violet-500 text-white text-sm font-bold shadow-lg shadow-primary/30 group-hover:shadow-xl group-hover:shadow-primary/40 group-hover:scale-110 transition-all">
            {i + 1}
          </div>
          <span className="text-white/70 group-hover:text-white/90 transition-colors">{step}</span>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// AGENT RATIO CARD - Why this ratio
// =============================================================================
function AgentRatioCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2 }}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15]"
    >
      <h4 className="font-bold text-white mb-4">Why this ratio?</h4>
      <div className="space-y-3">
        <RatioItem
          count="2"
          name="Claude"
          reason="Great for architecture and complex reasoning"
          color="from-orange-500 to-amber-500"
        />
        <RatioItem
          count="1"
          name="Codex"
          reason="Fast iteration and testing"
          color="from-emerald-500 to-teal-500"
        />
        <RatioItem
          count="1"
          name="Gemini"
          reason="Different perspective, good for docs"
          color="from-blue-500 to-indigo-500"
        />
      </div>
    </motion.div>
  );
}

function RatioItem({
  count,
  name,
  reason,
  color,
}: {
  count: string;
  name: string;
  reason: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-2 -mx-2 rounded-lg transition-all duration-300 hover:bg-white/[0.02]"
    >
      <div
        className={`flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br ${color} text-white font-bold text-sm shadow-lg group-hover:shadow-xl group-hover:scale-110 transition-all`}
      >
        {count}
      </div>
      <div>
        <span className="font-medium text-white group-hover:text-primary transition-colors">{name}</span>
        <span className="text-white/50"> - {reason}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// KEYBOARD SHORTCUT TABLE
// =============================================================================
function KeyboardShortcutTable({
  shortcuts,
}: {
  shortcuts: { keys: string[]; action: string }[];
}) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="grid grid-cols-[1fr_1fr] divide-x divide-white/[0.06]">
        <div className="p-3 bg-white/[0.02] text-sm font-medium text-white/60">
          Keys
        </div>
        <div className="p-3 bg-white/[0.02] text-sm font-medium text-white/60">
          Action
        </div>
      </div>
      {shortcuts.map((shortcut, i) => (
        <div
          key={i}
          className="grid grid-cols-[1fr_1fr] divide-x divide-white/[0.06] border-t border-white/[0.06]"
        >
          <div className="p-3 flex items-center gap-2">
            {shortcut.keys.map((key, j) => (
              <span key={j} className="flex items-center gap-1">
                <kbd className="px-2 py-1 rounded bg-black/40 border border-white/[0.1] text-xs font-mono text-white">
                  {key}
                </kbd>
                {j < shortcut.keys.length - 1 && (
                  <span className="text-white/30 text-xs">then</span>
                )}
              </span>
            ))}
          </div>
          <div className="p-3 text-white/70 text-sm">{shortcut.action}</div>
        </div>
      ))}
    </div>
  );
}
