"use client";

import { useEffect, useRef, useState, useCallback, useMemo } from "react";
import { motion, AnimatePresence } from "@/components/motion";
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
  Copy,
  Check,
  ChevronRight,
  Search,
  Command,
  Terminal,
  Settings,
  Monitor,
  Zap,
  Clock,
  ArrowRight,
  Keyboard,
  X,
  CornerDownLeft,
  Hash,
  Star,
} from "lucide-react";
import { copyTextToClipboard } from "@/lib/utils";
import {
  Section,
  Paragraph,
  CodeBlock,
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
        <div className="mt-8">
          <InteractivePaletteBrowser />
        </div>
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
      className={`relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-5 backdrop-blur-xl transition duration-500 hover:border-white/[0.15]`}
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
      whileHover={{ x: 4, scale: 1.01 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04] hover:shadow-lg hover:shadow-primary/10"
    >
      <div className="flex items-center gap-4 mb-4">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white font-bold shadow-lg shadow-primary/20 group-hover:shadow-primary/40 group-hover:scale-110 transition duration-300">
          {number}
        </div>
        <h4 className="text-lg font-bold text-white group-hover:text-primary transition-colors">{title}</h4>
      </div>

      {steps.length > 0 && (
        <ol className="space-y-2 ml-14">
          {steps.map((step, i) => (
            <li key={i} className="text-white/70 flex items-center gap-2 group-hover:text-white/80 transition-colors">
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
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} overflow-hidden transition duration-300 hover:border-white/[0.15] hover:shadow-lg hover:shadow-primary/10`}
    >
      <div className="p-4 border-b border-white/[0.08] bg-black/20 group-hover:bg-black/30 transition-colors">
        <h4 className="font-bold text-white group-hover:text-primary transition-colors">{title}</h4>
      </div>
      <div className="p-4">
        <pre className="text-sm text-white/80 whitespace-pre-wrap font-mono group-hover:text-white/90 transition-colors">
          {prompt}
        </pre>
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE PALETTE BROWSER - VS Code / Spotlight-style command palette
// =============================================================================

interface PaletteCommand {
  id: string;
  title: string;
  description: string;
  category: string;
  shortcut: string[];
  params?: string;
  fullText: string;
  starred?: boolean;
}

interface PaletteGroup {
  name: string;
  icon: React.ReactNode;
  color: string;
  gradient: string;
  badgeBg: string;
  badgeText: string;
}

const PALETTE_GROUPS: PaletteGroup[] = [
  {
    name: "Session Management",
    icon: <Terminal className="h-3.5 w-3.5" />,
    color: "emerald",
    gradient: "from-emerald-500/20 to-teal-500/20",
    badgeBg: "bg-emerald-500/20",
    badgeText: "text-emerald-400",
  },
  {
    name: "Agent Control",
    icon: <Zap className="h-3.5 w-3.5" />,
    color: "violet",
    gradient: "from-violet-500/20 to-purple-500/20",
    badgeBg: "bg-violet-500/20",
    badgeText: "text-violet-400",
  },
  {
    name: "Window Layout",
    icon: <Monitor className="h-3.5 w-3.5" />,
    color: "sky",
    gradient: "from-sky-500/20 to-blue-500/20",
    badgeBg: "bg-sky-500/20",
    badgeText: "text-sky-400",
  },
  {
    name: "Monitoring",
    icon: <Bug className="h-3.5 w-3.5" />,
    color: "amber",
    gradient: "from-amber-500/20 to-orange-500/20",
    badgeBg: "bg-amber-500/20",
    badgeText: "text-amber-400",
  },
  {
    name: "Configuration",
    icon: <Settings className="h-3.5 w-3.5" />,
    color: "red",
    gradient: "from-red-500/20 to-rose-500/20",
    badgeBg: "bg-red-500/20",
    badgeText: "text-red-400",
  },
  {
    name: "Quick Actions",
    icon: <Sparkles className="h-3.5 w-3.5" />,
    color: "cyan",
    gradient: "from-cyan-500/20 to-sky-500/20",
    badgeBg: "bg-cyan-500/20",
    badgeText: "text-cyan-400",
  },
];

const PALETTE_COMMANDS: PaletteCommand[] = [
  // Session Management
  {
    id: "new-session",
    title: "New Session",
    description: "Create a new tmux session with agent panes pre-configured",
    category: "Session Management",
    shortcut: ["Ctrl", "B", "N"],
    params: "--name <session>",
    fullText:
      "ntm new <project>\nCreate a fresh NTM session with tmux panes auto-configured for your agents.\nSets up the project directory, initializes agent windows, and attaches.\n\nOptions:\n  --agents <n>   Number of agent panes (default: 3)\n  --layout <l>   Layout preset: wide, tall, tiled\n  --attach       Auto-attach after creation",
  },
  {
    id: "attach-session",
    title: "Attach Session",
    description: "Reconnect to an existing NTM session by name",
    category: "Session Management",
    shortcut: ["Ctrl", "B", "A"],
    fullText:
      "ntm attach <session>\nRe-attach to a running NTM session. If the session has active agents,\nthey continue working while you were detached.\n\nOptions:\n  --readonly     Attach in read-only mode\n  --target <w>   Attach to specific window",
  },
  {
    id: "kill-session",
    title: "Kill Session",
    description: "Gracefully terminate a session and all its agents",
    category: "Session Management",
    shortcut: ["Ctrl", "B", "K"],
    fullText:
      "ntm kill <session>\nGracefully shuts down agents, saves state, and destroys the session.\n\nOptions:\n  --force        Skip graceful shutdown\n  --save-state   Save agent context before killing",
  },
  {
    id: "list-sessions",
    title: "List Sessions",
    description: "Show all active NTM sessions and their status",
    category: "Session Management",
    shortcut: ["Ctrl", "B", "L"],
    fullText:
      "ntm ls\nDisplay all running NTM sessions with:\n- Session name and uptime\n- Number of active agents\n- Current working directory\n- Resource usage (CPU/memory)",
  },
  // Agent Control
  {
    id: "send-prompt",
    title: "Send to Agents",
    description: "Broadcast a prompt to all agents in the session",
    category: "Agent Control",
    shortcut: ["Ctrl", "B", "S"],
    params: "--prompt <text>",
    fullText:
      "ntm send <prompt>\nBroadcast a prompt to all active agent panes simultaneously.\nAgents receive the prompt and begin processing in parallel.\n\nOptions:\n  --target <n>   Send to specific agent pane\n  --file <path>  Send contents of a file as prompt\n  --delay <ms>   Stagger delivery between agents",
    starred: true,
  },
  {
    id: "pause-agents",
    title: "Pause All Agents",
    description: "Temporarily halt agent execution without losing context",
    category: "Agent Control",
    shortcut: ["Ctrl", "B", "P"],
    fullText:
      "ntm pause\nSuspend all running agents while preserving their context.\nUseful for reviewing output before agents proceed.\n\nOptions:\n  --target <n>   Pause specific agent\n  --timeout <s>  Auto-resume after timeout",
  },
  {
    id: "resume-agents",
    title: "Resume Agents",
    description: "Continue paused agent execution",
    category: "Agent Control",
    shortcut: ["Ctrl", "B", "R"],
    fullText:
      "ntm resume\nResume all paused agents from where they left off.\n\nOptions:\n  --target <n>   Resume specific agent\n  --with <text>  Resume with additional context",
  },
  // Window Layout
  {
    id: "layout-wide",
    title: "Wide Layout",
    description: "Arrange panes in horizontal split (side-by-side agents)",
    category: "Window Layout",
    shortcut: ["Ctrl", "B", "W"],
    fullText:
      "ntm layout wide\nRearrange all panes into a wide horizontal layout.\nIdeal for widescreen monitors where agents work side-by-side.\n\nEach agent pane gets equal width with a minimum of 80 columns.",
  },
  {
    id: "layout-tiled",
    title: "Tiled Layout",
    description: "Grid arrangement for monitoring multiple agents equally",
    category: "Window Layout",
    shortcut: ["Ctrl", "B", "T"],
    fullText:
      "ntm layout tiled\nArrange panes in an even grid. Automatically calculates\noptimal rows and columns based on pane count.\n\nBest for 4+ agents when you want equal visibility.",
  },
  {
    id: "layout-focus",
    title: "Focus Mode",
    description: "Maximize one agent pane, minimize others to sidebar",
    category: "Window Layout",
    shortcut: ["Ctrl", "B", "F"],
    fullText:
      "ntm layout focus <pane>\nMaximize a single agent pane with others collapsed to a\nnarrow sidebar. Toggle back with the same shortcut.\n\nOptions:\n  --pane <n>     Pane number to focus (default: current)",
    starred: true,
  },
  // Monitoring
  {
    id: "status-overview",
    title: "Status Overview",
    description: "Dashboard view of all agents, tasks, and resource usage",
    category: "Monitoring",
    shortcut: ["Ctrl", "B", "D"],
    fullText:
      "ntm status\nShow a rich dashboard with:\n- Agent activity status (idle/working/error)\n- Current task description for each agent\n- CPU and memory per agent process\n- Time elapsed on current task\n- Token usage summary",
    starred: true,
  },
  {
    id: "tail-logs",
    title: "Tail Logs",
    description: "Stream agent logs in real-time with filtering",
    category: "Monitoring",
    shortcut: ["Ctrl", "B", "G"],
    params: "--filter <pattern>",
    fullText:
      "ntm logs\nStream real-time logs from all agents with color coding.\n\nOptions:\n  --agent <n>    Filter to specific agent\n  --level <l>    Filter by level: debug, info, warn, error\n  --since <t>    Show logs since timestamp\n  --follow       Continuously stream (default)",
  },
  {
    id: "agent-diff",
    title: "Agent Diff",
    description: "View file changes made by agents since session start",
    category: "Monitoring",
    shortcut: ["Ctrl", "B", "I"],
    fullText:
      "ntm diff\nShow a unified diff of all changes agents have made.\nGrouped by agent with color-coded additions and deletions.\n\nOptions:\n  --agent <n>    Changes from specific agent\n  --stat         Show diffstat summary only\n  --staged       Include staged changes only",
  },
  // Configuration
  {
    id: "config-agents",
    title: "Configure Agent Count",
    description: "Set the default number of agent panes for new sessions",
    category: "Configuration",
    shortcut: ["Ctrl", "Shift", "A"],
    params: "--count <n>",
    fullText:
      "ntm config agents <count>\nSet default agent count for new sessions (1-8).\nCurrent default is stored in ~/.ntm/config.yaml.\n\nOptions:\n  --global       Set globally\n  --project      Set for current project only",
  },
  {
    id: "config-theme",
    title: "Set Theme",
    description: "Switch the NTM color theme and pane styling",
    category: "Configuration",
    shortcut: ["Ctrl", "Shift", "T"],
    fullText:
      "ntm config theme <name>\nSwitch NTM visual theme.\n\nAvailable themes:\n  dark       Dark background with green accents (default)\n  midnight   Deep blue tones\n  solarized  Solarized dark variant\n  minimal    Minimal borders, maximum content",
  },
  {
    id: "config-model",
    title: "Set Default Model",
    description: "Choose the default AI model for agent panes",
    category: "Configuration",
    shortcut: ["Ctrl", "Shift", "M"],
    params: "--model <name>",
    fullText:
      "ntm config model <name>\nSet the default AI model for new agent panes.\n\nSupported models:\n  claude-opus     Most capable, best for complex tasks\n  claude-sonnet   Fast and balanced\n  gpt-4o          OpenAI alternative\n  custom          Use custom API endpoint",
  },
  // Quick Actions
  {
    id: "quick-review",
    title: "Quick Code Review",
    description: "Send a code review prompt to the focused agent",
    category: "Quick Actions",
    shortcut: ["Ctrl", "B", "1"],
    fullText:
      "ntm quick review\nInstantly send a battle-tested code review prompt to the focused agent.\nThe prompt covers security, performance, readability, and edge cases.\n\nEquivalent to: ntm palette --send \"Code Review\"",
    starred: true,
  },
  {
    id: "quick-test",
    title: "Quick Test Gen",
    description: "Generate tests for the current file in focus",
    category: "Quick Actions",
    shortcut: ["Ctrl", "B", "2"],
    fullText:
      "ntm quick test\nGenerate comprehensive tests for the file currently open in the\nfocused agent pane. Uses the project's testing framework conventions.\n\nEquivalent to: ntm palette --send \"Test Generation\"",
  },
  {
    id: "quick-fix",
    title: "Quick Bug Fix",
    description: "Analyze and fix the most recent error in the terminal",
    category: "Quick Actions",
    shortcut: ["Ctrl", "B", "3"],
    fullText:
      "ntm quick fix\nCapture the most recent error from the terminal and send it to\nthe focused agent with a debugging prompt. The agent will trace\nthe error, identify root cause, and suggest a fix.\n\nEquivalent to: ntm palette --send \"Error Analysis\"",
  },
  {
    id: "quick-docs",
    title: "Quick Documentation",
    description: "Generate docs for the current module or function",
    category: "Quick Actions",
    shortcut: ["Ctrl", "B", "4"],
    fullText:
      "ntm quick docs\nGenerate documentation for the code in the focused agent's context.\nProduces JSDoc comments, function descriptions, and usage examples.\n\nEquivalent to: ntm palette --send \"Inline Comments\"",
  },
];

// ---------------------------------------------------------------------------
// Fuzzy-search helpers
// ---------------------------------------------------------------------------

interface FuzzyMatch {
  command: PaletteCommand;
  score: number;
  matchedIndices: number[];
}

function fuzzyMatch(query: string, text: string): { score: number; indices: number[] } {
  const lowerQuery = query.toLowerCase();
  const lowerText = text.toLowerCase();
  let qi = 0;
  let score = 0;
  const indices: number[] = [];
  let prevMatchIdx = -2;

  for (let ti = 0; ti < lowerText.length && qi < lowerQuery.length; ti++) {
    if (lowerText[ti] === lowerQuery[qi]) {
      indices.push(ti);
      score += 1;
      // Bonus for consecutive characters
      if (ti === prevMatchIdx + 1) {
        score += 2;
      }
      // Bonus for matching at word boundaries
      if (ti === 0 || lowerText[ti - 1] === " " || lowerText[ti - 1] === "-") {
        score += 3;
      }
      prevMatchIdx = ti;
      qi++;
    }
  }

  if (qi < lowerQuery.length) {
    return { score: 0, indices: [] };
  }

  return { score, indices };
}

function searchCommands(query: string, commands: PaletteCommand[]): FuzzyMatch[] {
  if (!query.trim()) return commands.map((c) => ({ command: c, score: 1, matchedIndices: [] }));

  const results: FuzzyMatch[] = [];
  for (const cmd of commands) {
    const titleMatch = fuzzyMatch(query, cmd.title);
    const descMatch = fuzzyMatch(query, cmd.description);
    const catMatch = fuzzyMatch(query, cmd.category);
    const bestScore = Math.max(titleMatch.score * 2, descMatch.score, catMatch.score);
    if (bestScore > 0) {
      const bestIndices =
        titleMatch.score * 2 >= descMatch.score && titleMatch.score * 2 >= catMatch.score
          ? titleMatch.indices
          : descMatch.score >= catMatch.score
            ? descMatch.indices
            : catMatch.indices;
      results.push({ command: cmd, score: bestScore, matchedIndices: bestIndices });
    }
  }
  results.sort((a, b) => b.score - a.score);
  return results;
}

// ---------------------------------------------------------------------------
// Highlighted text renderer
// ---------------------------------------------------------------------------
function HighlightedText({ text, indices }: { text: string; indices: number[] }) {
  if (indices.length === 0) return <>{text}</>;
  const indexSet = new Set(indices);
  return (
    <>
      {text.split("").map((char, i) =>
        indexSet.has(i) ? (
          <span key={i} className="text-primary font-semibold">
            {char}
          </span>
        ) : (
          <span key={i}>{char}</span>
        )
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Keybinding pill
// ---------------------------------------------------------------------------
function KeyCombo({ keys }: { keys: string[] }) {
  return (
    <div className="flex items-center gap-0.5">
      {keys.map((key, i) => (
        <span key={i} className="flex items-center gap-0.5">
          {i > 0 && <span className="text-white/20 text-[9px] mx-0.5">+</span>}
          <kbd className="inline-flex h-5 min-w-[20px] items-center justify-center rounded border border-white/[0.12] bg-white/[0.06] px-1.5 font-mono text-[10px] font-medium text-white/50 shadow-sm">
            {key}
          </kbd>
        </span>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Mini terminal
// ---------------------------------------------------------------------------
function MiniTerminal({
  lines,
  isTyping,
}: {
  lines: string[];
  isTyping: boolean;
}) {
  return (
    <div className="rounded-lg border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-1.5 border-b border-white/[0.06] bg-black/30 px-3 py-1.5">
        <div className="h-2 w-2 rounded-full bg-red-400/60" />
        <div className="h-2 w-2 rounded-full bg-yellow-400/60" />
        <div className="h-2 w-2 rounded-full bg-green-400/60" />
        <span className="ml-2 text-[10px] text-white/30 font-mono">ntm palette</span>
      </div>
      <div className="p-3 font-mono text-xs leading-relaxed">
        {lines.map((line, i) => (
          <div key={i} className="text-white/60">
            {line.startsWith("$") ? (
              <>
                <span className="text-emerald-400">$</span>
                <span className="text-white/80">{line.slice(1)}</span>
              </>
            ) : line.startsWith(">") ? (
              <span className="text-sky-400">{line}</span>
            ) : line.startsWith("!") ? (
              <span className="text-amber-400">{line.slice(1)}</span>
            ) : (
              line
            )}
          </div>
        ))}
        {isTyping && (
          <motion.span
            animate={{ opacity: [1, 0] }}
            transition={{ duration: 0.8, repeat: Infinity, repeatType: "reverse" }}
            className="inline-block h-3.5 w-1.5 bg-emerald-400/80 ml-0.5"
          />
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// INTERACTIVE PALETTE BROWSER (main component)
// ---------------------------------------------------------------------------
function InteractivePaletteBrowser() {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [activeCommand, setActiveCommand] = useState<PaletteCommand | null>(null);
  const [copied, setCopied] = useState(false);
  const [sent, setSent] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(true);
  const [recentIds, setRecentIds] = useState<string[]>(() => [
    "send-prompt",
    "status-overview",
    "quick-review",
  ]);
  const [terminalLines, setTerminalLines] = useState<string[]>([
    "$ ntm palette",
    "> Loading command palette...",
    "> 20 commands loaded across 6 categories",
    "",
  ]);
  const [isTerminalTyping, setIsTerminalTyping] = useState(false);
  const [activeCategoryFilter, setActiveCategoryFilter] = useState<string | null>(null);

  const searchInputRef = useRef<HTMLInputElement>(null);
  const listContainerRef = useRef<HTMLDivElement>(null);
  const copiedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sentTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Cleanup timers
  useEffect(() => {
    return () => {
      if (copiedTimerRef.current) clearTimeout(copiedTimerRef.current);
      if (sentTimerRef.current) clearTimeout(sentTimerRef.current);
      if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    };
  }, []);

  // Pre-filter by category, then fuzzy search
  const filteredResults = useMemo(() => {
    let pool = PALETTE_COMMANDS;
    if (activeCategoryFilter) {
      pool = pool.filter((c) => c.category === activeCategoryFilter);
    }
    return searchCommands(searchQuery, pool);
  }, [searchQuery, activeCategoryFilter]);

  // Group filtered results by category
  const groupedResults = useMemo(() => {
    const groups: Record<string, FuzzyMatch[]> = {};
    for (const r of filteredResults) {
      const cat = r.command.category;
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(r);
    }
    return groups;
  }, [filteredResults]);

  // Flat list for keyboard nav
  const flatResults = useMemo(() => {
    const flat: FuzzyMatch[] = [];
    for (const group of PALETTE_GROUPS) {
      const items = groupedResults[group.name];
      if (items) flat.push(...items);
    }
    return flat;
  }, [groupedResults]);

  // Clamp selected index
  useEffect(() => {
    if (selectedIndex >= flatResults.length) {
      const clamped = Math.max(0, flatResults.length - 1);
      setTimeout(() => setSelectedIndex(clamped), 0);
    }
  }, [flatResults.length, selectedIndex]);

  const recentCommands = useMemo(() => {
    return recentIds
      .map((id) => PALETTE_COMMANDS.find((c) => c.id === id))
      .filter((c): c is PaletteCommand => c !== undefined);
  }, [recentIds]);

  const findGroupForCommand = useCallback((cmd: PaletteCommand) => {
    return PALETTE_GROUPS.find((g) => g.name === cmd.category) ?? PALETTE_GROUPS[0];
  }, []);

  function selectCommand(cmd: PaletteCommand) {
    setActiveCommand(cmd);
    // Add to recent
    setRecentIds((prev) => {
      const next = [cmd.id, ...prev.filter((id) => id !== cmd.id)];
      return next.slice(0, 5);
    });
    // Terminal feedback
    setIsTerminalTyping(true);
    setTerminalLines((prev) => [
      ...prev.slice(-4),
      `$ ntm palette --select "${cmd.title}"`,
      `> Category: ${cmd.category}`,
      `> ${cmd.description}`,
      "",
    ]);
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(() => {
      setIsTerminalTyping(false);
      typingTimerRef.current = null;
    }, 800);
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((i) => Math.min(i + 1, flatResults.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const match = flatResults[selectedIndex];
      if (match) selectCommand(match.command);
    } else if (e.key === "Escape") {
      if (activeCommand) {
        setActiveCommand(null);
      } else if (searchQuery) {
        setSearchQuery("");
      }
    }
  }

  async function handleCopy() {
    if (!activeCommand) return;
    const ok = await copyTextToClipboard(activeCommand.fullText);
    if (!ok) return;
    setCopied(true);
    if (copiedTimerRef.current) clearTimeout(copiedTimerRef.current);
    copiedTimerRef.current = setTimeout(() => {
      setCopied(false);
      copiedTimerRef.current = null;
    }, 1500);
    setTerminalLines((prev) => [
      ...prev.slice(-4),
      "!  Copied to clipboard",
      "",
    ]);
  }

  function handleSend() {
    if (!activeCommand) return;
    setSent(true);
    if (sentTimerRef.current) clearTimeout(sentTimerRef.current);
    sentTimerRef.current = setTimeout(() => {
      setSent(false);
      sentTimerRef.current = null;
    }, 1500);
    setTerminalLines((prev) => [
      ...prev.slice(-4),
      `$ ntm send --palette "${activeCommand.title}"`,
      "> Sent to 3 agents",
      "!  All agents received prompt",
      "",
    ]);
  }

  // Compute global index offsets per group for highlighting
  const groupOffsets = useMemo(() => {
    const offsets: number[] = [];
    let offset = 0;
    for (const group of PALETTE_GROUPS) {
      offsets.push(offset);
      const items = groupedResults[group.name];
      if (items) offset += items.length;
    }
    return offsets;
  }, [groupedResults]);

  return (
    <div className="space-y-4">
      {/* Palette toggle bar */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
        className="flex items-center gap-3"
      >
        <motion.button
          whileHover={{ scale: 1.03 }}
          whileTap={{ scale: 0.97 }}
          transition={{ type: "spring", stiffness: 400, damping: 25 }}
          onClick={() => setPaletteOpen(!paletteOpen)}
          className="flex items-center gap-2 rounded-xl border border-white/[0.1] bg-white/[0.04] px-4 py-2.5 text-sm font-medium text-white/80 hover:bg-white/[0.08] hover:text-white transition-colors backdrop-blur-xl"
        >
          <Command className="h-4 w-4 text-primary" />
          <span>{paletteOpen ? "Close" : "Open"} Command Palette</span>
          <div className="ml-2 flex items-center gap-0.5">
            <kbd className="rounded border border-white/[0.12] bg-white/[0.06] px-1.5 py-0.5 font-mono text-[10px] text-white/40">
              Ctrl
            </kbd>
            <span className="text-white/20 text-[10px]">+</span>
            <kbd className="rounded border border-white/[0.12] bg-white/[0.06] px-1.5 py-0.5 font-mono text-[10px] text-white/40">
              K
            </kbd>
          </div>
        </motion.button>
        <span className="text-xs text-white/30">
          {PALETTE_COMMANDS.length} commands available
        </span>
      </motion.div>

      <AnimatePresence mode="wait">
        {paletteOpen && (
          <motion.div
            key="palette"
            initial={{ opacity: 0, y: 20, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -10, scale: 0.98 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden shadow-2xl shadow-black/40"
          >
            {/* Search bar */}
            <div className="relative border-b border-white/[0.08] bg-black/30">
              <div className="flex items-center gap-3 px-4 py-3">
                <Search className="h-4 w-4 text-white/30 shrink-0" />
                <input
                  ref={searchInputRef}
                  type="text"
                  value={searchQuery}
                  onChange={(e) => {
                    setSearchQuery(e.target.value);
                    setSelectedIndex(0);
                    setActiveCommand(null);
                  }}
                  onKeyDown={handleKeyDown}
                  placeholder="Search commands... (type to filter)"
                  className="flex-1 bg-transparent text-sm text-white/90 placeholder:text-white/30 outline-none"
                />
                {searchQuery && (
                  <motion.button
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    onClick={() => {
                      setSearchQuery("");
                      setSelectedIndex(0);
                      searchInputRef.current?.focus();
                    }}
                    className="rounded-md p-0.5 text-white/30 hover:text-white/60 hover:bg-white/[0.06] transition-colors"
                  >
                    <X className="h-3.5 w-3.5" />
                  </motion.button>
                )}
                <div className="flex items-center gap-1 text-white/20">
                  <kbd className="rounded border border-white/[0.1] bg-white/[0.04] px-1 py-0.5 font-mono text-[9px]">
                    <CornerDownLeft className="h-2.5 w-2.5" />
                  </kbd>
                  <span className="text-[9px]">select</span>
                </div>
              </div>

              {/* Category filter pills */}
              <div className="flex gap-1.5 overflow-x-auto px-4 pb-2.5">
                <button
                  onClick={() => {
                    setActiveCategoryFilter(null);
                    setSelectedIndex(0);
                  }}
                  className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-medium transition ${
                    activeCategoryFilter === null
                      ? "bg-white/[0.12] text-white"
                      : "bg-white/[0.04] text-white/40 hover:bg-white/[0.08] hover:text-white/60"
                  }`}
                >
                  All
                </button>
                {PALETTE_GROUPS.map((group) => (
                  <button
                    key={group.name}
                    onClick={() => {
                      setActiveCategoryFilter(
                        activeCategoryFilter === group.name ? null : group.name
                      );
                      setSelectedIndex(0);
                    }}
                    className={`flex shrink-0 items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-medium transition ${
                      activeCategoryFilter === group.name
                        ? `${group.badgeBg} ${group.badgeText}`
                        : "bg-white/[0.04] text-white/40 hover:bg-white/[0.08] hover:text-white/60"
                    }`}
                  >
                    {group.icon}
                    <span className="hidden sm:inline">{group.name}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* Main content area */}
            <div className="flex flex-col lg:flex-row min-h-[420px] max-h-[600px]">
              {/* Command list */}
              <div
                ref={listContainerRef}
                className="flex-1 overflow-y-auto border-b border-white/[0.08] lg:border-b-0 lg:border-r lg:max-w-[420px]"
              >
                {/* Recently Used section */}
                {!searchQuery && !activeCategoryFilter && recentCommands.length > 0 && (
                  <div className="px-3 pt-3 pb-1">
                    <div className="flex items-center gap-2 px-2 pb-2">
                      <Clock className="h-3 w-3 text-white/25" />
                      <span className="text-[10px] font-medium uppercase tracking-wider text-white/25">
                        Recently Used
                      </span>
                    </div>
                    <div className="space-y-0.5">
                      {recentCommands.map((cmd) => {
                        const group = findGroupForCommand(cmd);
                        return (
                          <motion.button
                            key={`recent-${cmd.id}`}
                            whileHover={{ x: 2 }}
                            transition={{ type: "spring", stiffness: 200, damping: 25 }}
                            onClick={() => selectCommand(cmd)}
                            className={`flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-left transition-colors ${
                              activeCommand?.id === cmd.id
                                ? "bg-white/[0.08]"
                                : "hover:bg-white/[0.04]"
                            }`}
                          >
                            <div className={`${group.badgeText}`}>{group.icon}</div>
                            <span className="text-xs font-medium text-white/70 truncate">
                              {cmd.title}
                            </span>
                            <span className="ml-auto">
                              <KeyCombo keys={cmd.shortcut} />
                            </span>
                          </motion.button>
                        );
                      })}
                    </div>
                    <div className="mx-2 my-2 h-px bg-white/[0.06]" />
                  </div>
                )}

                {/* Grouped command list */}
                <div className="px-3 py-2 space-y-1">
                  {PALETTE_GROUPS.map((group, groupIdx) => {
                    const items = groupedResults[group.name];
                    if (!items || items.length === 0) return null;
                    return (
                      <div key={group.name}>
                        <div className="flex items-center gap-2 px-2 py-1.5">
                          <span className={group.badgeText}>{group.icon}</span>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-white/25">
                            {group.name}
                          </span>
                          <span className="text-[9px] text-white/15">
                            {items.length}
                          </span>
                        </div>
                        <AnimatePresence mode="popLayout">
                          <div className="space-y-0.5">
                            {items.map((match, itemIdx) => {
                              const currentGlobalIdx = groupOffsets[groupIdx] + itemIdx;
                              const isSelected = currentGlobalIdx === selectedIndex;
                              const isActive = activeCommand?.id === match.command.id;
                              return (
                                <motion.button
                                  key={match.command.id}
                                  initial={{ opacity: 0, x: -8 }}
                                  animate={{ opacity: 1, x: 0 }}
                                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                                  whileHover={{ x: 2 }}
                                  onClick={() => {
                                    selectCommand(match.command);
                                    setSelectedIndex(currentGlobalIdx);
                                  }}
                                  className={`group/item flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-left transition ${
                                    isActive
                                      ? "bg-white/[0.08] border border-white/[0.12]"
                                      : isSelected
                                        ? "bg-white/[0.05] border border-white/[0.08]"
                                        : "border border-transparent hover:bg-white/[0.04]"
                                  }`}
                                >
                                  {/* Star indicator */}
                                  {match.command.starred && (
                                    <Star className="h-2.5 w-2.5 text-amber-400/60 fill-amber-400/40 shrink-0" />
                                  )}
                                  <div className="flex-1 min-w-0">
                                    <div className="flex items-center gap-2">
                                      <span className="text-xs font-medium text-white/80 truncate">
                                        {searchQuery ? (
                                          <HighlightedText
                                            text={match.command.title}
                                            indices={
                                              fuzzyMatch(searchQuery, match.command.title).indices
                                            }
                                          />
                                        ) : (
                                          match.command.title
                                        )}
                                      </span>
                                      {match.command.params && (
                                        <span className="shrink-0 rounded bg-white/[0.06] px-1.5 py-0.5 font-mono text-[9px] text-white/30">
                                          {match.command.params}
                                        </span>
                                      )}
                                    </div>
                                    <p className="mt-0.5 truncate text-[11px] text-white/35">
                                      {match.command.description}
                                    </p>
                                  </div>
                                  <div className="shrink-0 ml-2 opacity-60 group-hover/item:opacity-100 transition-opacity">
                                    <KeyCombo keys={match.command.shortcut} />
                                  </div>
                                  <ChevronRight
                                    className={`h-3.5 w-3.5 shrink-0 transition ${
                                      isActive
                                        ? "text-primary"
                                        : "text-white/15 group-hover/item:text-white/30"
                                    }`}
                                  />
                                </motion.button>
                              );
                            })}
                          </div>
                        </AnimatePresence>
                      </div>
                    );
                  })}

                  {/* Empty state */}
                  {flatResults.length === 0 && (
                    <motion.div
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                      className="flex flex-col items-center justify-center py-12 text-center"
                    >
                      <Search className="h-8 w-8 text-white/10 mb-3" />
                      <p className="text-sm text-white/30">
                        No commands match &quot;{searchQuery}&quot;
                      </p>
                      <p className="text-xs text-white/20 mt-1">
                        Try a different search term
                      </p>
                    </motion.div>
                  )}
                </div>
              </div>

              {/* Command detail / preview panel */}
              <div className="flex-1 flex flex-col min-h-[300px]">
                <AnimatePresence mode="wait">
                  {activeCommand ? (
                    <motion.div
                      key={activeCommand.id}
                      initial={{ opacity: 0, x: 16 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: -8 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                      className="flex flex-col h-full"
                    >
                      {/* Command header */}
                      <div className="border-b border-white/[0.06] px-5 py-4">
                        <div className="flex items-center gap-2.5 mb-2">
                          <span
                            className={`${findGroupForCommand(activeCommand).badgeText}`}
                          >
                            {findGroupForCommand(activeCommand).icon}
                          </span>
                          <span
                            className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${findGroupForCommand(activeCommand).badgeBg} ${findGroupForCommand(activeCommand).badgeText}`}
                          >
                            {activeCommand.category}
                          </span>
                          {activeCommand.starred && (
                            <Star className="h-3 w-3 text-amber-400/60 fill-amber-400/40" />
                          )}
                        </div>
                        <h3 className="text-base font-bold text-white">
                          {activeCommand.title}
                        </h3>
                        <p className="mt-1 text-xs text-white/50">
                          {activeCommand.description}
                        </p>

                        {/* Keybinding visualization */}
                        <div className="mt-3 flex items-center gap-2">
                          <Keyboard className="h-3.5 w-3.5 text-white/25" />
                          <span className="text-[10px] text-white/25 mr-1">Shortcut:</span>
                          <div className="flex items-center gap-1">
                            {activeCommand.shortcut.map((key, i) => (
                              <span key={i} className="flex items-center gap-1">
                                {i > 0 && (
                                  <ArrowRight className="h-2.5 w-2.5 text-white/15" />
                                )}
                                <motion.kbd
                                  initial={{ opacity: 0, y: 4 }}
                                  animate={{ opacity: 1, y: 0 }}
                                  transition={{
                                    type: "spring",
                                    stiffness: 200,
                                    damping: 25,
                                    delay: i * 0.08,
                                  }}
                                  className="inline-flex h-7 min-w-[28px] items-center justify-center rounded-md border border-white/[0.15] bg-gradient-to-b from-white/[0.08] to-white/[0.03] px-2 font-mono text-xs font-medium text-white/60 shadow-sm shadow-black/20"
                                >
                                  {key}
                                </motion.kbd>
                              </span>
                            ))}
                          </div>
                        </div>
                      </div>

                      {/* Execution preview */}
                      <div className="flex-1 overflow-auto px-5 py-4">
                        <div className="flex items-center gap-2 mb-2">
                          <Hash className="h-3 w-3 text-white/25" />
                          <span className="text-[10px] font-medium uppercase tracking-wider text-white/25">
                            Execution Preview
                          </span>
                        </div>
                        <div className="rounded-lg border border-white/[0.08] bg-black/30 p-4 overflow-auto">
                          <pre className="whitespace-pre-wrap font-mono text-xs leading-relaxed text-white/65">
                            {activeCommand.fullText}
                          </pre>
                        </div>

                        {/* Parameter hint */}
                        {activeCommand.params && (
                          <motion.div
                            initial={{ opacity: 0, y: 8 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{
                              type: "spring",
                              stiffness: 200,
                              damping: 25,
                              delay: 0.15,
                            }}
                            className="mt-3 flex items-center gap-2 rounded-lg border border-white/[0.06] bg-white/[0.02] px-3 py-2"
                          >
                            <Lightbulb className="h-3.5 w-3.5 text-amber-400/60 shrink-0" />
                            <span className="text-[11px] text-white/40">
                              Accepts parameter:{" "}
                              <code className="rounded bg-white/[0.06] px-1 py-0.5 font-mono text-[10px] text-white/60">
                                {activeCommand.params}
                              </code>
                            </span>
                          </motion.div>
                        )}
                      </div>

                      {/* Action buttons */}
                      <div className="border-t border-white/[0.06] px-5 py-3">
                        <div className="flex gap-2">
                          <motion.button
                            whileHover={{ scale: 1.02 }}
                            whileTap={{ scale: 0.98 }}
                            transition={{ type: "spring", stiffness: 200, damping: 25 }}
                            onClick={handleSend}
                            className="relative flex flex-1 items-center justify-center gap-2 rounded-lg bg-gradient-to-r from-primary/80 to-violet-500/80 px-4 py-2.5 text-xs font-semibold text-white shadow-lg shadow-primary/20 hover:from-primary hover:to-violet-500 transition overflow-hidden"
                          >
                            {sent && (
                              <motion.div
                                initial={{ scale: 0, opacity: 0.6 }}
                                animate={{ scale: 4, opacity: 0 }}
                                transition={{ type: "spring", stiffness: 200, damping: 20 }}
                                className="absolute h-8 w-8 rounded-full bg-white/30"
                              />
                            )}
                            <Send className="h-3.5 w-3.5" />
                            <span className="relative">
                              {sent ? "Sent to All Agents!" : "Send to All Agents"}
                            </span>
                          </motion.button>
                          <motion.button
                            whileHover={{ scale: 1.02 }}
                            whileTap={{ scale: 0.98 }}
                            transition={{ type: "spring", stiffness: 200, damping: 25 }}
                            onClick={handleCopy}
                            className="flex items-center gap-1.5 rounded-lg border border-white/[0.1] bg-white/[0.04] px-4 py-2.5 text-xs font-medium text-white/70 hover:bg-white/[0.08] hover:text-white transition-colors"
                          >
                            {copied ? (
                              <Check className="h-3.5 w-3.5 text-emerald-400" />
                            ) : (
                              <Copy className="h-3.5 w-3.5" />
                            )}
                            <span>{copied ? "Copied!" : "Copy"}</span>
                          </motion.button>
                        </div>
                      </div>
                    </motion.div>
                  ) : (
                    <motion.div
                      key="empty-preview"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                      className="flex flex-col items-center justify-center h-full px-8 py-12"
                    >
                      <motion.div
                        animate={{ y: [0, -6, 0] }}
                        transition={{
                          duration: 3,
                          repeat: Infinity,
                          repeatType: "loop",
                          ease: "easeInOut",
                        }}
                        className="mb-4"
                      >
                        <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/10 to-violet-500/10 border border-white/[0.06]">
                          <Command className="h-7 w-7 text-white/20" />
                        </div>
                      </motion.div>
                      <p className="text-sm font-medium text-white/30 text-center">
                        Select a command to preview
                      </p>
                      <p className="mt-1 text-xs text-white/20 text-center">
                        Use arrow keys or click to browse
                      </p>
                      <div className="mt-4 flex items-center gap-3 text-white/15">
                        <div className="flex items-center gap-1">
                          <kbd className="rounded border border-white/[0.08] bg-white/[0.04] px-1.5 py-0.5 font-mono text-[9px]">
                            &uarr;
                          </kbd>
                          <kbd className="rounded border border-white/[0.08] bg-white/[0.04] px-1.5 py-0.5 font-mono text-[9px]">
                            &darr;
                          </kbd>
                          <span className="text-[9px] ml-0.5">navigate</span>
                        </div>
                        <div className="flex items-center gap-1">
                          <kbd className="rounded border border-white/[0.08] bg-white/[0.04] px-1.5 py-0.5 font-mono text-[9px]">
                            Enter
                          </kbd>
                          <span className="text-[9px] ml-0.5">select</span>
                        </div>
                        <div className="flex items-center gap-1">
                          <kbd className="rounded border border-white/[0.08] bg-white/[0.04] px-1.5 py-0.5 font-mono text-[9px]">
                            Esc
                          </kbd>
                          <span className="text-[9px] ml-0.5">back</span>
                        </div>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </div>

            {/* Mini terminal footer */}
            <div className="border-t border-white/[0.06]">
              <MiniTerminal lines={terminalLines} isTyping={isTerminalTyping} />
            </div>

            {/* Status bar */}
            <div className="flex items-center justify-between border-t border-white/[0.06] bg-black/20 px-4 py-1.5">
              <div className="flex items-center gap-3 text-[10px] text-white/25">
                <span className="flex items-center gap-1">
                  <Layers className="h-2.5 w-2.5" />
                  {PALETTE_GROUPS.length} categories
                </span>
                <span className="flex items-center gap-1">
                  <Hash className="h-2.5 w-2.5" />
                  {flatResults.length} / {PALETTE_COMMANDS.length} commands
                </span>
              </div>
              <div className="flex items-center gap-2 text-[10px] text-white/25">
                <span className="flex items-center gap-1">
                  <Star className="h-2.5 w-2.5 text-amber-400/40 fill-amber-400/30" />
                  {PALETTE_COMMANDS.filter((c) => c.starred).length} starred
                </span>
                <span>ntm v2.4.0</span>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
