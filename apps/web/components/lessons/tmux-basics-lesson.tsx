"use client";

import { motion } from "@/components/motion";
import {
  LayoutGrid,
  Play,
  Pause,
  List,
  ArrowLeftRight,
  Copy,
  Scissors,
  Columns,
  Rows,
  Bot,
  Keyboard,
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

export function TmuxBasicsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>Never lose work when SSH drops.</GoalBanner>

      {/* What Is tmux */}
      <Section
        title="What Is tmux?"
        icon={<LayoutGrid className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>tmux</Highlight> is a <strong>terminal multiplexer</strong>.
          It lets you:
        </Paragraph>
        <div className="mt-6">
          <BulletList
            items={[
              "Keep sessions running after you disconnect",
              "Split your terminal into panes",
              "Have multiple windows in one connection",
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Essential Commands */}
      <Section
        title="Essential Commands"
        icon={<Play className="h-5 w-5" />}
        delay={0.15}
      >
        {/* Start Session */}
        <div className="space-y-8">
          <CommandSection
            title="Start a New Session"
            code="tmux new -s myproject"
            description='This creates a session named "myproject".'
          />

          <CommandSection
            title="Detach (Leave Session Running)"
            keyCombo={["Ctrl+a", "d"]}
            description="Your session continues running in the background!"
          />

          <CommandSection
            title="List Sessions"
            code="tmux ls"
            description="See all running sessions."
          />

          <CommandSection
            title="Reattach to a Session"
            code={`tmux attach -t myproject
# Or just:
tmux a`}
            description="Attaches to the most recent session."
          />
        </div>
      </Section>

      <Divider />

      {/* The Prefix Key */}
      <Section
        title="The Prefix Key"
        icon={<Keyboard className="h-5 w-5" />}
        delay={0.2}
      >
        <TipBox variant="info">
          In ACFS, the prefix key is <InlineCode>Ctrl+a</InlineCode> (not the
          default <InlineCode>Ctrl+b</InlineCode>). All tmux commands start with
          the prefix.
        </TipBox>
      </Section>

      <Divider />

      {/* Splitting Panes */}
      <Section
        title="Splitting Panes"
        icon={<Columns className="h-5 w-5" />}
        delay={0.25}
      >
        <KeyboardShortcutGrid
          shortcuts={[
            {
              keys: ["Ctrl+a", "|"],
              action: "Split vertically",
              icon: <Columns className="h-4 w-4" />,
            },
            {
              keys: ["Ctrl+a", "-"],
              action: "Split horizontally",
              icon: <Rows className="h-4 w-4" />,
            },
            {
              keys: ["Ctrl+a", "h/j/k/l"],
              action: "Move between panes",
              icon: <ArrowLeftRight className="h-4 w-4" />,
            },
            {
              keys: ["Ctrl+a", "x"],
              action: "Close current pane",
              icon: <Scissors className="h-4 w-4" />,
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Windows */}
      <Section
        title="Windows (Tabs)"
        icon={<LayoutGrid className="h-5 w-5" />}
        delay={0.3}
      >
        <KeyboardShortcutGrid
          shortcuts={[
            {
              keys: ["Ctrl+a", "c"],
              action: "New window",
              icon: <Play className="h-4 w-4" />,
            },
            {
              keys: ["Ctrl+a", "n"],
              action: "Next window",
              icon: <ArrowLeftRight className="h-4 w-4" />,
            },
            {
              keys: ["Ctrl+a", "p"],
              action: "Previous window",
              icon: <ArrowLeftRight className="h-4 w-4 rotate-180" />,
            },
            {
              keys: ["Ctrl+a", "0-9"],
              action: "Go to window number",
              icon: <List className="h-4 w-4" />,
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Copy Mode */}
      <Section
        title="Copy Mode (Scrolling)"
        icon={<Copy className="h-5 w-5" />}
        delay={0.35}
      >
        <KeyboardShortcutGrid
          shortcuts={[
            {
              keys: ["Ctrl+a", "["],
              action: "Enter copy mode",
              icon: <Play className="h-4 w-4" />,
            },
            {
              keys: ["j/k", "or arrows"],
              action: "Scroll",
              icon: <ArrowLeftRight className="h-4 w-4 rotate-90" />,
            },
            { keys: ["q"], action: "Exit copy mode", icon: <Pause className="h-4 w-4" /> },
            { keys: ["v"], action: "Start selection", icon: <Copy className="h-4 w-4" /> },
            { keys: ["y"], action: "Copy selection", icon: <Copy className="h-4 w-4" /> },
          ]}
        />
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Play className="h-5 w-5" />}
        delay={0.4}
      >
        <CodeBlock
          code={`# Create a session
$ tmux new -s practice

# Split the screen
# Press Ctrl+a, then |

# Move to the new pane
# Press Ctrl+a, then l

# Run something
$ ls -la

# Detach
# Press Ctrl+a, then d

# Verify it's still running
$ tmux ls

# Reattach
$ tmux attach -t practice`}
          showLineNumbers
        />
      </Section>

      <Divider />

      {/* Why This Matters */}
      <Section
        title="Why This Matters for Agents"
        icon={<Bot className="h-5 w-5" />}
        delay={0.45}
      >
        <WhyItMattersCard />
      </Section>
    </div>
  );
}

// =============================================================================
// COMMAND SECTION - Display a command with description
// =============================================================================
function CommandSection({
  title,
  code,
  keyCombo,
  description,
}: {
  title: string;
  code?: string;
  keyCombo?: string[];
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group space-y-4 p-4 -mx-4 rounded-xl transition-all duration-300 hover:bg-white/[0.02]"
    >
      <h4 className="text-lg font-semibold text-white group-hover:text-primary transition-colors">{title}</h4>
      {code && <CodeBlock code={code} />}
      {keyCombo && (
        <div className="flex items-center gap-2">
          <span className="text-sm text-white/50">Press:</span>
          {keyCombo.map((key, i) => (
            <span key={i} className="flex items-center gap-2">
              <kbd className="px-3 py-1.5 rounded-lg bg-white/[0.06] border border-white/[0.1] text-sm font-mono text-white">
                {key}
              </kbd>
              {i < keyCombo.length - 1 && (
                <span className="text-white/30">then</span>
              )}
            </span>
          ))}
        </div>
      )}
      <p className="text-white/60">{description}</p>
    </motion.div>
  );
}

// =============================================================================
// KEYBOARD SHORTCUT GRID - Display shortcuts in a grid
// =============================================================================
interface ShortcutItem {
  keys: string[];
  action: string;
  icon: React.ReactNode;
}

function KeyboardShortcutGrid({ shortcuts }: { shortcuts: ShortcutItem[] }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {shortcuts.map((shortcut, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: i * 0.1 }}
          whileHover={{ y: -2, scale: 1.01 }}
          className="group flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
        >
          <div className="text-primary group-hover:text-primary/80 transition-colors">{shortcut.icon}</div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              {shortcut.keys.map((key, j) => (
                <span key={j} className="flex items-center gap-1">
                  <kbd className="px-2 py-1 rounded bg-black/40 border border-white/[0.1] text-xs font-mono text-white">
                    {key}
                  </kbd>
                  {j < shortcut.keys.length - 1 && (
                    <span className="text-white/30 text-xs">+</span>
                  )}
                </span>
              ))}
            </div>
            <span className="text-sm text-white/50">{shortcut.action}</span>
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// WHY IT MATTERS CARD - Highlight importance
// =============================================================================
function WhyItMattersCard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.5 }}
      className="relative rounded-2xl border border-emerald-500/30 bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl overflow-hidden"
    >
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/20 rounded-full blur-3xl" />

      <div className="relative flex items-start gap-5">
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-500 shadow-lg shadow-emerald-500/30">
          <Bot className="h-7 w-7 text-white" />
        </div>
        <div>
          <h4 className="text-lg font-bold text-white mb-2">
            Your Agents Run in tmux
          </h4>
          <p className="text-white/60">
            Your coding agents (Claude, Codex, Gemini) run in tmux panes. If SSH
            drops, they keep running. When you reconnect and reattach,
            they&apos;re still there!
          </p>
        </div>
      </div>
    </motion.div>
  );
}
