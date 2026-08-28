"use client";

import { useState, useCallback, useEffect, useRef, useMemo } from "react";
import { motion, AnimatePresence } from "@/components/motion";
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
  Monitor,
  Plus,
  ArrowRight,
  Unplug,
  PlugZap,
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

      {/* Interactive Pane Simulator */}
      <Section
        title="Try Splitting Panes"
        icon={<Monitor className="h-5 w-5" />}
        delay={0.12}
      >
        <Paragraph>
          Click panes to select them, then use the buttons to split or close.
          This simulates what <Highlight>Ctrl+a</Highlight> shortcuts do in a
          real tmux session.
        </Paragraph>
        <div className="mt-6">
          <InteractiveTmuxSimulator />
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
      className="group space-y-4 p-4 -mx-4 rounded-xl transition duration-300 hover:bg-white/[0.02]"
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
                <span className="text-white/50">then</span>
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
          className="group flex items-center gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
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
                    <span className="text-white/50 text-xs">+</span>
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
            Your coding agents (Claude, Codex, Antigravity) run in tmux panes. If SSH
            drops, they keep running. When you reconnect and reattach,
            they&apos;re still there!
          </p>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE TMUX SIMULATOR V2 - Realistic tmux experience
// =============================================================================

/** Simulated terminal output for each pane to make it feel alive */
const PANE_OUTPUTS: string[][] = [
  [
    "$ npm run dev",
    "  VITE v5.4.1 ready in 312 ms",
    "",
    "  > Local:   http://localhost:5173/",
    "  > Network: http://192.168.1.42:5173/",
    "",
    "  watching for file changes...",
  ],
  [
    "$ git log --oneline -5",
    "a3f82d1 feat: add dashboard layout",
    "c91e4b7 fix: resolve auth token refresh",
    "e8d2a03 refactor: extract API client",
    "7b14f6c docs: update README setup steps",
    "1a9c8e2 chore: bump dependencies",
    "$ _",
  ],
  [
    "$ htop",
    "  PID USER      PRI  NI  VIRT   RES  CPU% MEM%",
    "  142 ubuntu     20   0  512M   48M  2.1  1.2",
    "  891 node       20   0 1024M  186M 12.4  4.7",
    " 1203 postgres   20   0  256M   92M  0.8  2.3",
    " 1547 claude     20   0  768M  224M 45.2  5.6",
    "  Tasks: 64, Thr: 182; Running: 3",
  ],
  [
    "$ tail -f /var/log/app.log",
    "[INFO]  2026-03-12 10:42:01 Request GET /api/v1/users",
    "[INFO]  2026-03-12 10:42:02 Response 200 in 14ms",
    "[WARN]  2026-03-12 10:42:05 Rate limit approaching",
    "[INFO]  2026-03-12 10:42:08 Request POST /api/v1/deploy",
    "[INFO]  2026-03-12 10:42:09 Deploy pipeline started",
    "[INFO]  2026-03-12 10:42:12 Build step 1/4 complete",
  ],
];

/** Content for different windows */
const WINDOW_CONFIGS = [
  { name: "editor", output: PANE_OUTPUTS[0] },
  { name: "git", output: PANE_OUTPUTS[1] },
  { name: "monitor", output: PANE_OUTPUTS[2] },
];

/** Simulated clock for status bar */
function useSimulatedClock() {
  const [time, setTime] = useState("10:42");
  useEffect(() => {
    const interval = setInterval(() => {
      const d = new Date();
      setTime(
        `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`,
      );
    }, 10000);
    // Set initial time via timeout to avoid synchronous setState in effect
    const t = setTimeout(() => {
      const d = new Date();
      setTime(
        `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`,
      );
    }, 0);
    return () => {
      clearInterval(interval);
      clearTimeout(t);
    };
  }, []);
  return time;
}

interface SimPane {
  id: string;
  outputIndex: number;
}

interface SimWindow {
  id: string;
  name: string;
  panes: SimPane[];
  /** Pane layout: list of split directions applied */
  splits: Array<"horizontal" | "vertical">;
  activePaneId: string;
}

type SimPhase = "live" | "detaching" | "detached" | "reattaching";

const SPRING_SMOOTH = { type: "spring" as const, stiffness: 200, damping: 25 };

let simPaneCounter = 0;
function makePane(outputIndex: number): SimPane {
  simPaneCounter += 1;
  return { id: `sp-${simPaneCounter}`, outputIndex };
}

const MAX_SIM_PANES = 4;

function InteractiveTmuxSimulator() {
  const time = useSimulatedClock();

  // --- state ---
  const [windows, setWindows] = useState<SimWindow[]>(() => {
    simPaneCounter = 0;
    const p = makePane(0);
    return [{ id: "w-1", name: "editor", panes: [p], splits: [], activePaneId: p.id }];
  });
  const [activeWindowId, setActiveWindowId] = useState("w-1");
  const [phase, setPhase] = useState<SimPhase>("live");
  const [detachedSnapshot, setDetachedSnapshot] = useState<SimWindow[] | null>(null);
  const windowCounterRef = useRef(1);

  const activeWindow = windows.find((w) => w.id === activeWindowId) ?? windows[0];
  const totalPanesInWindow = activeWindow.panes.length;

  // derive the output lines for a pane with an added activity line for persistence demo
  const getPaneOutput = useCallback(
    (pane: SimPane): string[] => {
      return PANE_OUTPUTS[pane.outputIndex % PANE_OUTPUTS.length];
    },
    [],
  );

  // --- handlers ---

  const handleSplitHorizontal = useCallback(() => {
    if (totalPanesInWindow >= MAX_SIM_PANES) return;
    const newPane = makePane(totalPanesInWindow);
    setWindows((prev) =>
      prev.map((w) =>
        w.id === activeWindowId
          ? {
              ...w,
              panes: [...w.panes, newPane],
              splits: [...w.splits, "horizontal"],
              activePaneId: newPane.id,
            }
          : w,
      ),
    );
  }, [activeWindowId, totalPanesInWindow]);

  const handleSplitVertical = useCallback(() => {
    if (totalPanesInWindow >= MAX_SIM_PANES) return;
    const newPane = makePane(totalPanesInWindow);
    setWindows((prev) =>
      prev.map((w) =>
        w.id === activeWindowId
          ? {
              ...w,
              panes: [...w.panes, newPane],
              splits: [...w.splits, "vertical"],
              activePaneId: newPane.id,
            }
          : w,
      ),
    );
  }, [activeWindowId, totalPanesInWindow]);

  const handleNewWindow = useCallback(() => {
    if (windows.length >= 4) return;
    windowCounterRef.current += 1;
    const cfg = WINDOW_CONFIGS[windows.length % WINDOW_CONFIGS.length];
    const p = makePane(windows.length % PANE_OUTPUTS.length);
    const newWin: SimWindow = {
      id: `w-${windowCounterRef.current}`,
      name: cfg.name,
      panes: [p],
      splits: [],
      activePaneId: p.id,
    };
    setWindows((prev) => [...prev, newWin]);
    setActiveWindowId(newWin.id);
  }, [windows.length]);

  const handleSwitchWindow = useCallback(() => {
    if (windows.length <= 1) return;
    const currentIdx = windows.findIndex((w) => w.id === activeWindowId);
    const nextIdx = (currentIdx + 1) % windows.length;
    setActiveWindowId(windows[nextIdx].id);
  }, [windows, activeWindowId]);

  const detachTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleDetach = useCallback(() => {
    if (phase !== "live") return;
    if (detachTimerRef.current) clearTimeout(detachTimerRef.current);
    setDetachedSnapshot(windows);
    setPhase("detaching");
    // After glitch animation, show detached state
    detachTimerRef.current = setTimeout(() => {
      setPhase("detached");
      detachTimerRef.current = null;
    }, 1200);
  }, [phase, windows]);

  const handleReattach = useCallback(() => {
    if (phase !== "detached") return;
    if (detachTimerRef.current) clearTimeout(detachTimerRef.current);
    setPhase("reattaching");
    detachTimerRef.current = setTimeout(() => {
      if (detachedSnapshot) {
        setWindows(detachedSnapshot);
        setActiveWindowId(detachedSnapshot[0].id);
      }
      setPhase("live");
      setDetachedSnapshot(null);
      detachTimerRef.current = null;
    }, 800);
  }, [phase, detachedSnapshot]);

  const handleSelectPane = useCallback(
    (paneId: string) => {
      setWindows((prev) =>
        prev.map((w) => (w.id === activeWindowId ? { ...w, activePaneId: paneId } : w)),
      );
    },
    [activeWindowId],
  );

  useEffect(() => {
    return () => {
      if (detachTimerRef.current) clearTimeout(detachTimerRef.current);
    };
  }, []);

  // --- render ---
  const isLive = phase === "live";

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={SPRING_SMOOTH}
      className="space-y-4"
    >
      {/* Command Buttons */}
      <div className="flex flex-wrap items-center gap-2">
        <SimButton
          onClick={handleSplitHorizontal}
          disabled={!isLive || totalPanesInWindow >= MAX_SIM_PANES}
          label="Split Horizontal"
          shortcut='Ctrl+b "'
          icon={<Rows className="h-3.5 w-3.5" />}
        />
        <SimButton
          onClick={handleSplitVertical}
          disabled={!isLive || totalPanesInWindow >= MAX_SIM_PANES}
          label="Split Vertical"
          shortcut="Ctrl+b %"
          icon={<Columns className="h-3.5 w-3.5" />}
        />
        <SimButton
          onClick={handleNewWindow}
          disabled={!isLive || windows.length >= 4}
          label="New Window"
          shortcut="Ctrl+b c"
          icon={<Plus className="h-3.5 w-3.5" />}
        />
        <SimButton
          onClick={handleSwitchWindow}
          disabled={!isLive || windows.length <= 1}
          label="Switch Window"
          shortcut="Ctrl+b n"
          icon={<ArrowRight className="h-3.5 w-3.5" />}
        />
        <SimButton
          onClick={handleDetach}
          disabled={phase !== "live"}
          label="Detach"
          shortcut="Ctrl+b d"
          icon={<Unplug className="h-3.5 w-3.5" />}
          variant="warning"
        />
        <SimButton
          onClick={handleReattach}
          disabled={phase !== "detached"}
          label="Reattach"
          shortcut="tmux a"
          icon={<PlugZap className="h-3.5 w-3.5" />}
          variant="success"
        />
      </div>

      {/* Terminal Window Chrome */}
      <div className="rounded-xl border border-white/[0.08] overflow-hidden backdrop-blur-xl bg-white/[0.02] shadow-2xl">
        {/* macOS-style title bar */}
        <div className="flex items-center gap-2 px-4 py-2.5 bg-white/[0.04] border-b border-white/[0.08]">
          <div className="flex gap-1.5">
            <div className="h-3 w-3 rounded-full bg-red-500/70" />
            <div className="h-3 w-3 rounded-full bg-yellow-500/70" />
            <div className="h-3 w-3 rounded-full bg-green-500/70" />
          </div>
          <span className="ml-2 text-xs font-mono text-white/40">
            {phase === "detached" ? "Terminal - disconnected" : "tmux - myproject"}
          </span>
        </div>

        {/* Main pane area */}
        <div className="relative h-64 sm:h-80 bg-[#0a0a0f] overflow-hidden">
          <AnimatePresence mode="wait">
            {/* --- LIVE VIEW --- */}
            {phase === "live" && (
              <motion.div
                key="live"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.3 }}
                className="absolute inset-0"
              >
                <SimPaneGrid
                  panes={activeWindow.panes}
                  splits={activeWindow.splits}
                  activePaneId={activeWindow.activePaneId}
                  onSelectPane={handleSelectPane}
                  getPaneOutput={getPaneOutput}
                />
              </motion.div>
            )}

            {/* --- DETACHING GLITCH --- */}
            {phase === "detaching" && (
              <motion.div
                key="detaching"
                className="absolute inset-0 flex items-center justify-center"
                initial={{ opacity: 1 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
              >
                <GlitchEffect />
              </motion.div>
            )}

            {/* --- DETACHED SCREEN --- */}
            {phase === "detached" && (
              <motion.div
                key="detached"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={SPRING_SMOOTH}
                className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-[#0a0a0f]"
              >
                <motion.div
                  initial={{ scale: 0.8, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ ...SPRING_SMOOTH, delay: 0.1 }}
                  className="flex flex-col items-center gap-3"
                >
                  <Unplug className="h-10 w-10 text-red-400/60" />
                  <span className="text-sm font-mono text-red-400/80">
                    [detached (from session myproject)]
                  </span>
                  <span className="text-xs font-mono text-white/30">$</span>
                </motion.div>

                <motion.div
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ ...SPRING_SMOOTH, delay: 0.4 }}
                  className="mt-4 px-4 py-2 rounded-lg border border-emerald-500/20 bg-emerald-500/[0.06]"
                >
                  <p className="text-xs text-emerald-400/80 text-center">
                    Session is still running in the background!
                    <br />
                    <span className="text-white/40">
                      Click &quot;Reattach&quot; to reconnect with everything preserved.
                    </span>
                  </p>
                </motion.div>
              </motion.div>
            )}

            {/* --- REATTACHING --- */}
            {phase === "reattaching" && (
              <motion.div
                key="reattaching"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center bg-[#0a0a0f]"
              >
                <motion.div
                  initial={{ scale: 0.9, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={SPRING_SMOOTH}
                  className="flex items-center gap-2"
                >
                  <PlugZap className="h-6 w-6 text-emerald-400/80" />
                  <span className="text-sm font-mono text-emerald-400/80">
                    Reconnecting to session...
                  </span>
                </motion.div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* tmux status bar (green, realistic) */}
        <TmuxStatusBar
          windows={windows}
          activeWindowId={activeWindowId}
          phase={phase}
          time={time}
          onSelectWindow={isLive ? setActiveWindowId : undefined}
        />
      </div>

      {/* Informational hints */}
      {phase === "live" && totalPanesInWindow >= MAX_SIM_PANES && (
        <p className="text-xs text-white/40 text-center">
          Maximum of {MAX_SIM_PANES} panes per window. Try creating a new window!
        </p>
      )}
    </motion.div>
  );
}

// =============================================================================
// TMUX STATUS BAR - Realistic green bar at bottom
// =============================================================================

function TmuxStatusBar({
  windows,
  activeWindowId,
  phase,
  time,
  onSelectWindow,
}: {
  windows: SimWindow[];
  activeWindowId: string;
  phase: SimPhase;
  time: string;
  onSelectWindow?: (id: string) => void;
}) {
  const isDetached = phase === "detached" || phase === "detaching" || phase === "reattaching";

  return (
    <div
      className={`flex items-center justify-between px-3 py-1 font-mono text-[11px] transition-colors duration-300 ${
        isDetached
          ? "bg-red-950/60 border-t border-red-500/20 text-red-400/60"
          : "bg-emerald-950/60 border-t border-emerald-500/20 text-emerald-300/90"
      }`}
    >
      {/* Left: session name */}
      <span className="shrink-0">[myproject]</span>

      {/* Center: window list */}
      <div className="flex items-center gap-1 overflow-x-auto mx-2">
        <AnimatePresence mode="popLayout">
          {windows.map((w, i) => {
            const isActive = w.id === activeWindowId;
            return (
              <motion.button
                key={w.id}
                initial={{ opacity: 0, scale: 0.8, width: 0 }}
                animate={{ opacity: 1, scale: 1, width: "auto" }}
                exit={{ opacity: 0, scale: 0.8, width: 0 }}
                transition={SPRING_SMOOTH}
                onClick={() => onSelectWindow?.(w.id)}
                disabled={!onSelectWindow}
                className={`px-2 py-0.5 rounded whitespace-nowrap transition-colors ${
                  isActive
                    ? isDetached
                      ? "bg-red-500/20 text-red-300"
                      : "bg-emerald-500/30 text-white"
                    : isDetached
                      ? "text-red-400/40 hover:text-red-400/60"
                      : "text-emerald-400/50 hover:text-emerald-300/80"
                }`}
              >
                {i}:{w.name}{isActive ? "*" : "-"}
              </motion.button>
            );
          })}
        </AnimatePresence>
      </div>

      {/* Right: hostname + time */}
      <div className="shrink-0 flex items-center gap-2">
        <span className="hidden sm:inline opacity-60">ubuntu@vps</span>
        <span>{time}</span>
      </div>
    </div>
  );
}

// =============================================================================
// PANE GRID - Renders panes in a split layout
// =============================================================================

function SimPaneGrid({
  panes,
  splits,
  activePaneId,
  onSelectPane,
  getPaneOutput,
}: {
  panes: SimPane[];
  splits: Array<"horizontal" | "vertical">;
  activePaneId: string;
  onSelectPane: (id: string) => void;
  getPaneOutput: (pane: SimPane) => string[];
}) {
  // Build a simple layout: first pane takes one side, then splits apply sequentially
  // For a clean visual we use CSS grid
  const gridStyle = useMemo(() => {
    if (panes.length === 1) {
      return { gridTemplateColumns: "1fr", gridTemplateRows: "1fr" };
    }
    if (panes.length === 2) {
      if (splits[0] === "vertical") {
        return { gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr" };
      }
      return { gridTemplateColumns: "1fr", gridTemplateRows: "1fr 1fr" };
    }
    if (panes.length === 3) {
      // First split determines major axis
      if (splits[0] === "vertical") {
        return { gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 1fr" };
      }
      return { gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 1fr" };
    }
    // 4 panes: 2x2 grid
    return { gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 1fr" };
  }, [panes.length, splits]);

  // Determine if a pane spans two cells in the 3-pane case
  const getSpanStyle = useCallback(
    (index: number): React.CSSProperties | undefined => {
      if (panes.length === 3 && index === 0) {
        if (splits[0] === "vertical") {
          return { gridRow: "1 / -1" };
        }
        return { gridColumn: "1 / -1" };
      }
      return undefined;
    },
    [panes.length, splits],
  );

  return (
    <div className="h-full w-full grid gap-0" style={gridStyle}>
      <AnimatePresence mode="popLayout">
        {panes.map((pane, i) => (
          <motion.div
            key={pane.id}
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.92 }}
            transition={SPRING_SMOOTH}
            style={getSpanStyle(i)}
            className={`relative overflow-hidden cursor-pointer border transition-colors duration-200 ${
              pane.id === activePaneId
                ? "border-emerald-500/50 bg-[#0d1117]"
                : "border-white/[0.06] bg-[#0a0a0f] hover:bg-[#0d0d14]"
            }`}
            onClick={() => onSelectPane(pane.id)}
          >
            {/* Active pane indicator */}
            {pane.id === activePaneId && (
              <motion.div
                layoutId="active-pane-glow"
                className="absolute inset-0 pointer-events-none border border-emerald-400/30 rounded-none"
                transition={SPRING_SMOOTH}
              />
            )}
            <SimPaneContent
              isActive={pane.id === activePaneId}
              output={getPaneOutput(pane)}
            />
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// PANE CONTENT - Terminal content inside each pane
// =============================================================================

function SimPaneContent({
  isActive,
  output,
}: {
  isActive: boolean;
  output: string[];
}) {
  return (
    <div className="h-full flex flex-col">
      {/* Terminal output lines */}
      <div className="flex-1 p-2 sm:p-3 overflow-hidden">
        <div className="text-[10px] sm:text-xs font-mono leading-relaxed space-y-0">
          {output.map((line, i) => (
            <div key={i} className="whitespace-pre">
              {line.startsWith("$") ? (
                <>
                  <span className="text-green-400/80">ubuntu@vps</span>
                  <span className="text-white/30">:</span>
                  <span className="text-blue-400/70">~</span>
                  <span className="text-white/40">
                    {line}
                  </span>
                </>
              ) : (
                <span className="text-white/50">{line}</span>
              )}
            </div>
          ))}
          {/* Blinking cursor on active pane */}
          {isActive && (
            <div className="inline-flex items-center mt-0.5">
              <span className="text-green-400/80">ubuntu@vps</span>
              <span className="text-white/30">:</span>
              <span className="text-blue-400/70">~</span>
              <span className="text-white/40">$ </span>
              <motion.span
                animate={{ opacity: [1, 0] }}
                transition={{
                  duration: 0.8,
                  repeat: Infinity,
                  repeatType: "reverse",
                }}
                className="inline-block w-1.5 h-3 bg-emerald-400/80"
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// GLITCH EFFECT - Plays during detach
// =============================================================================

function GlitchEffect() {
  const [glitchStep, setGlitchStep] = useState(0);

  useEffect(() => {
    const steps = [100, 200, 300, 500, 700, 900];
    const timeouts: ReturnType<typeof setTimeout>[] = [];
    steps.forEach((ms, i) => {
      timeouts.push(
        setTimeout(() => {
          setGlitchStep(i + 1);
        }, ms),
      );
    });
    return () => timeouts.forEach(clearTimeout);
  }, []);

  return (
    <div className="absolute inset-0 overflow-hidden">
      {/* Scanline noise layers */}
      <motion.div
        animate={{
          opacity: [0.3, 0.8, 0.1, 0.6, 0],
          y: [0, -20, 10, -5, 0],
        }}
        transition={{ duration: 1.2, ease: "linear" }}
        className="absolute inset-0"
      >
        {/* Horizontal glitch bars */}
        {Array.from({ length: 8 }).map((_, i) => (
          <motion.div
            key={i}
            initial={{ x: 0, opacity: 0 }}
            animate={{
              x: [0, (i % 2 === 0 ? 1 : -1) * (10 + i * 5), 0],
              opacity: [0, 0.8, 0],
            }}
            transition={{
              duration: 0.3,
              delay: i * 0.08,
              repeat: 2,
              repeatType: "mirror",
            }}
            className="h-2 bg-red-500/30"
            style={{ marginTop: `${i * 12 + 8}%` }}
          />
        ))}
      </motion.div>

      {/* Static noise overlay */}
      <motion.div
        animate={{ opacity: [0, 0.4, 0.1, 0.3, 0] }}
        transition={{ duration: 1.2, ease: "linear" }}
        className="absolute inset-0 bg-gradient-to-b from-red-500/10 via-transparent to-red-500/10"
        style={{
          backgroundImage:
            glitchStep > 2
              ? "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(255,0,0,0.03) 2px, rgba(255,0,0,0.03) 4px)"
              : undefined,
        }}
      />

      {/* Central disconnect text */}
      <div className="absolute inset-0 flex items-center justify-center">
        <motion.span
          initial={{ opacity: 0, scale: 1.2 }}
          animate={{ opacity: [0, 1, 1, 0], scale: [1.2, 1, 1, 0.95] }}
          transition={{ duration: 1.2, times: [0, 0.2, 0.7, 1] }}
          className="text-sm font-mono text-red-400/90 font-bold tracking-wider"
        >
          {glitchStep < 3 ? "CONNECTION INTERRUPTED" : "DETACHED"}
        </motion.span>
      </div>
    </div>
  );
}

// =============================================================================
// SIM BUTTON - Control button for the simulator
// =============================================================================

function SimButton({
  onClick,
  disabled,
  label,
  shortcut,
  icon,
  variant,
}: {
  onClick: () => void;
  disabled: boolean;
  label: string;
  shortcut?: string;
  icon: React.ReactNode;
  variant?: "default" | "warning" | "success";
}) {
  const colorClasses =
    variant === "warning"
      ? "border-orange-500/20 text-orange-300/80 bg-orange-500/[0.06] hover:border-orange-400/40 hover:text-orange-300 hover:bg-orange-500/[0.1]"
      : variant === "success"
        ? "border-emerald-500/20 text-emerald-300/80 bg-emerald-500/[0.06] hover:border-emerald-400/40 hover:text-emerald-300 hover:bg-emerald-500/[0.1]"
        : "border-white/[0.12] text-white/80 bg-white/[0.04] hover:border-primary/40 hover:text-primary hover:bg-primary/[0.06]";

  return (
    <motion.button
      whileHover={disabled ? undefined : { scale: 1.03 }}
      whileTap={disabled ? undefined : { scale: 0.97 }}
      onClick={onClick}
      disabled={disabled}
      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border backdrop-blur-xl transition duration-200 ${
        disabled
          ? "border-white/[0.05] text-white/20 bg-white/[0.02] cursor-not-allowed"
          : colorClasses
      }`}
    >
      {icon}
      <span>{label}</span>
      {shortcut && (
        <kbd className="ml-1 px-1.5 py-0.5 rounded bg-black/30 border border-white/[0.08] text-[10px] font-mono text-white/40">
          {shortcut}
        </kbd>
      )}
    </motion.button>
  );
}
