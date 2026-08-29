'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from "@/components/motion";
import {
  Terminal,
  BellRing,
  BookOpen,
  RefreshCw,
  Play,
  FileText,
  Brain,
  Shrink,
  ShieldAlert,
  ShieldCheck,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Zap,
  RotateCcw,
} from 'lucide-react';
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
} from './lesson-components';

function CompactionSimulator() {
  return <CompactionSimulatorImpl />;
}

export function PcrLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Keep agents aligned after context compaction with Post-Compact Reminder.
      </GoalBanner>

      {/* Section 1: What Is PCR */}
      <Section title="What Is PCR?" icon={<BellRing className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>PCR (Post-Compact Reminder)</Highlight> is a Claude Code hook
          that fires after context compaction and forces the agent to re-read AGENTS.md.
          This prevents agents from &ldquo;forgetting&rdquo; project rules and conventions
          after their context window is compressed.
        </Paragraph>
        <Paragraph>
          Without PCR, agents that hit context limits lose awareness of project-specific
          instructions. PCR ensures continuity by automatically injecting a reminder
          to re-read the project guidelines.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<BellRing className="h-5 w-5" />}
              title="Auto-Reminder"
              description="Triggers on every context compaction event"
              gradient="from-rose-500/20 to-pink-500/20"
            />
            <FeatureCard
              icon={<BookOpen className="h-5 w-5" />}
              title="AGENTS.md Re-read"
              description="Forces re-reading project guidelines"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<RefreshCw className="h-5 w-5" />}
              title="Context Recovery"
              description="Restores lost project awareness after compaction"
              gradient="from-green-500/20 to-emerald-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Zero Config"
              description="Installs as a Claude Code hook, works automatically"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Setup */}
      <Section title="Setup & Verification" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            {
              command:
                'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/post_compact_reminder/main/install-post-compact-reminder.sh" | bash -s -- --yes',
              description: 'Install or repair PCR',
            },
            {
              command: 'test -x "$HOME/.local/bin/claude-post-compact-reminder"',
              description: 'Verify the hook script exists',
            },
            {
              command:
                'echo \'{"session_id":"demo","source":"compact"}\' | ~/.local/bin/claude-post-compact-reminder',
              description: 'Simulate a compact event and inspect the reminder output',
            },
          ]}
        />

        <TipBox>
          Restart Claude Code after installing or repairing PCR so the updated
          `SessionStart` hook configuration is loaded. If you are running from a
          local copy of the installer script, `./install-post-compact-reminder.sh --status`
          and `--doctor` provide fuller health checks than the raw file probes above.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: How It Works */}
      <Section title="How It Works" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# PCR registers a SessionStart hook in Claude Code settings
# with matcher: "compact". Claude sends JSON on stdin when that event fires.

# Simulate the exact compact payload locally:
echo '{"session_id":"demo","source":"compact"}' | \\
  ~/.local/bin/claude-post-compact-reminder

# Normal startup events stay quiet because the hook only emits output when
# source == "compact".`} />

        <Paragraph>
          PCR does not parse <Highlight>AGENTS.md</Highlight> or <Highlight>CLAUDE.md</Highlight>{' '}
          itself. Its job is narrower and safer: emit a reminder after compaction so the
          agent re-reads the project instructions before continuing.
        </Paragraph>

        <Paragraph>
          You can also change the reminder tone without touching the hook script by
          re-running the installer with templates like <Highlight>minimal</Highlight>,{' '}
          <Highlight>detailed</Highlight>, <Highlight>checklist</Highlight>, or{' '}
          <Highlight>default</Highlight>.
        </Paragraph>
      </Section>

      <Divider />

      {/* Section 4: Interactive Compaction Simulator */}
      <Section title="See PCR in Action" icon={<Zap className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          Watch what happens when context compaction hits &mdash; with and without PCR.
          Click <Highlight>Fill Context</Highlight> to simulate a long session, then
          <Highlight> Compact</Highlight> to trigger compaction. Toggle PCR on/off to
          compare the outcomes.
        </Paragraph>
        <div className="mt-6">
          <CompactionSimulator />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE COMPACTION SIMULATOR
// =============================================================================

/** Represents an item in the agent's context window. */
interface ContextItem {
  id: number;
  label: string;
  type: "rule" | "message" | "code";
  color: string;
  iconType: "shield" | "brain" | "file";
}

/** Project rules that the agent must remember. */
const PROJECT_RULES: ContextItem[] = [
  { id: 1, label: "Never delete files without permission", type: "rule", color: "text-rose-400", iconType: "shield" },
  { id: 2, label: "Use bun, never npm", type: "rule", color: "text-rose-400", iconType: "shield" },
  { id: 3, label: "Follow RCH offloading requirements", type: "rule", color: "text-rose-400", iconType: "shield" },
  { id: 4, label: "Read AGENTS.md for task assignments", type: "rule", color: "text-rose-400", iconType: "shield" },
];

/** Conversation messages that accumulate over time. */
const SESSION_MESSAGES: ContextItem[] = [
  { id: 10, label: "Implement auth middleware", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 11, label: "Add PKCE flow support", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 12, label: "Refactor token storage", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 13, label: "Debug OAuth callback", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 14, label: "Write integration tests", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 15, label: "Update API documentation", type: "message", color: "text-blue-400", iconType: "brain" },
  { id: 16, label: "Fix session expiry handling", type: "code", color: "text-emerald-400", iconType: "file" },
  { id: 17, label: "Add rate limiting logic", type: "code", color: "text-emerald-400", iconType: "file" },
  { id: 18, label: "Optimize DB queries", type: "code", color: "text-emerald-400", iconType: "file" },
  { id: 19, label: "Configure CI pipeline", type: "code", color: "text-emerald-400", iconType: "file" },
];

type SimPhase = "empty" | "filling" | "full" | "compacting" | "compacted" | "pcr-firing" | "restored";

const FILL_INTERVAL_MS = 300;
const COMPACT_ANIM_MS = 800;
const PCR_FIRE_MS = 1200;
const RESTORE_MS = 600;

function CompactionSimulatorImpl() {
  const [phase, setPhase] = useState<SimPhase>("empty");
  const [pcrEnabled, setPcrEnabled] = useState(true);
  const [contextItems, setContextItems] = useState<ContextItem[]>([]);
  const [fillIndex, setFillIndex] = useState(0);
  const [pcrMessage, setPcrMessage] = useState(false);

  const fillTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const transitionTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const pcrEnabledRef = useRef(pcrEnabled);

  const clearTransitionTimers = useCallback(() => {
    transitionTimersRef.current.forEach((timer) => clearTimeout(timer));
    transitionTimersRef.current = [];
  }, []);

  const scheduleTransition = useCallback((callback: () => void, delay: number) => {
    const timer = setTimeout(() => {
      transitionTimersRef.current = transitionTimersRef.current.filter(
        (pendingTimer) => pendingTimer !== timer
      );
      callback();
    }, delay);
    transitionTimersRef.current.push(timer);
  }, []);

  // Keep ref in sync via useEffect
  useEffect(() => {
    pcrEnabledRef.current = pcrEnabled;
  }, [pcrEnabled]);

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (fillTimerRef.current) clearTimeout(fillTimerRef.current);
      clearTransitionTimers();
    };
  }, [clearTransitionTimers]);

  // Drive the fill animation with sequential timeouts
  useEffect(() => {
    if (phase !== "filling") return;

    const allItems = [...PROJECT_RULES, ...SESSION_MESSAGES];

    if (fillIndex < allItems.length) {
      fillTimerRef.current = setTimeout(() => {
        setContextItems((prev) => [...prev, allItems[fillIndex]]);
        setFillIndex((prev) => prev + 1);
      }, FILL_INTERVAL_MS);
    } else {
      // Filling done - move to full
      fillTimerRef.current = setTimeout(() => {
        setPhase("full");
      }, 200);
    }

    return () => {
      if (fillTimerRef.current) clearTimeout(fillTimerRef.current);
    };
  }, [phase, fillIndex]);

  const handleFillContext = useCallback(() => {
    if (phase !== "empty") return;
    clearTransitionTimers();
    setContextItems([]);
    setFillIndex(0);
    setPcrMessage(false);
    setPhase("filling");
  }, [clearTransitionTimers, phase]);

  const handleCompact = useCallback(() => {
    if (phase !== "full") return;
    clearTransitionTimers();
    setPhase("compacting");

    // After compaction animation: remove old messages and rules
    scheduleTransition(() => {
      // Keep only the last 3 messages (simulating compaction keeping recent context)
      setContextItems((prev) => prev.filter((item) => item.type !== "rule").slice(-3));
      setPhase("compacted");

      // If PCR is enabled, fire the reminder after a short delay
      if (pcrEnabledRef.current) {
        scheduleTransition(() => {
          setPhase("pcr-firing");
          setPcrMessage(true);

          // After PCR fires, restore rules
          scheduleTransition(() => {
            setContextItems((prev) => [...PROJECT_RULES, ...prev]);
            setPhase("restored");
          }, RESTORE_MS);
        }, PCR_FIRE_MS);
      }
    }, COMPACT_ANIM_MS);
  }, [clearTransitionTimers, phase, scheduleTransition]);

  const handleReset = useCallback(() => {
    if (fillTimerRef.current) clearTimeout(fillTimerRef.current);
    clearTransitionTimers();
    setPhase("empty");
    setContextItems([]);
    setFillIndex(0);
    setPcrMessage(false);
  }, [clearTransitionTimers]);

  // Compute context usage percentage
  const maxTokens = PROJECT_RULES.length + SESSION_MESSAGES.length;
  const usagePercent = Math.round((contextItems.length / maxTokens) * 100);

  // Determine status label and color
  const statusInfo = getStatusInfo(phase, pcrEnabled);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-rose-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 space-y-5">
        {/* Header row: PCR toggle + action buttons */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          {/* PCR Toggle */}
          <motion.button
            onClick={() => {
              if (phase === "empty" || phase === "full") {
                setPcrEnabled((prev) => !prev);
              }
            }}
            whileHover={phase === "empty" || phase === "full" ? { scale: 1.02 } : {}}
            whileTap={phase === "empty" || phase === "full" ? { scale: 0.98 } : {}}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-3 px-4 py-2.5 rounded-xl border transition duration-300 ${
              pcrEnabled
                ? "border-emerald-500/30 bg-emerald-500/10"
                : "border-red-500/30 bg-red-500/10"
            } ${phase === "empty" || phase === "full" ? "cursor-pointer" : "cursor-default opacity-60"}`}
          >
            {pcrEnabled ? (
              <ShieldCheck className="h-5 w-5 text-emerald-400" />
            ) : (
              <ShieldAlert className="h-5 w-5 text-red-400" />
            )}
            <div className="flex flex-col items-start">
              <span className="text-xs font-semibold text-white/80">
                PCR Hook
              </span>
              <span className={`text-[10px] font-medium ${pcrEnabled ? "text-emerald-400" : "text-red-400"}`}>
                {pcrEnabled ? "Enabled" : "Disabled"}
              </span>
            </div>
            {/* Toggle track */}
            <div className={`relative w-10 h-5 rounded-full transition-colors duration-300 ${
              pcrEnabled ? "bg-emerald-500/30" : "bg-red-500/30"
            }`}>
              <motion.div
                animate={{ x: pcrEnabled ? 20 : 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full ${
                  pcrEnabled ? "bg-emerald-400" : "bg-red-400"
                }`}
              />
            </div>
          </motion.button>

          {/* Action buttons */}
          <div className="flex items-center gap-2">
            {phase === "empty" && (
              <motion.button
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                onClick={handleFillContext}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gradient-to-r from-blue-500/20 to-indigo-500/20 border border-blue-500/30 text-sm font-medium text-blue-300 hover:border-blue-500/50 transition-colors"
              >
                <Brain className="h-4 w-4" />
                Fill Context
              </motion.button>
            )}
            {phase === "full" && (
              <motion.button
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                onClick={handleCompact}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-500/30 text-sm font-medium text-amber-300 hover:border-amber-500/50 transition-colors"
              >
                <Shrink className="h-4 w-4" />
                Compact
              </motion.button>
            )}
            {(phase === "compacted" || phase === "restored") && (
              <motion.button
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                onClick={handleReset}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gradient-to-r from-white/[0.06] to-white/[0.03] border border-white/[0.15] text-sm font-medium text-white/60 hover:border-white/[0.25] transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reset
              </motion.button>
            )}
          </div>
        </div>

        {/* Context usage bar */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
              Context Window Usage
            </span>
            <span className="text-xs text-white/40 font-mono">
              {contextItems.length}/{maxTokens} tokens
            </span>
          </div>
          <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              animate={{ width: `${usagePercent}%` }}
              transition={{ type: "spring", stiffness: 100, damping: 20 }}
              className={`h-full rounded-full transition-colors duration-500 ${
                usagePercent >= 90
                  ? "bg-gradient-to-r from-red-500 to-orange-500"
                  : usagePercent >= 60
                    ? "bg-gradient-to-r from-amber-500 to-yellow-500"
                    : "bg-gradient-to-r from-blue-500 to-indigo-500"
              }`}
            />
          </div>
        </div>

        {/* Status indicator */}
        <motion.div
          animate={{
            borderColor: statusInfo.borderClass,
          }}
          className={`flex items-center gap-2.5 px-4 py-2.5 rounded-xl border bg-black/30 transition-colors duration-500`}
          style={{ borderColor: statusInfo.borderHex }}
        >
          <statusInfo.Icon className={`h-4 w-4 ${statusInfo.iconColor} shrink-0`} />
          <span className={`text-xs font-medium ${statusInfo.textColor}`}>
            {statusInfo.label}
          </span>
        </motion.div>

        {/* Context window visualization */}
        <div className="rounded-xl border border-white/[0.08] bg-black/40 p-4 min-h-[200px]">
          <div className="flex items-center gap-2 mb-3">
            <Brain className="h-4 w-4 text-white/40" />
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Agent Context Window
            </span>
          </div>

          {/* Context items */}
          <div className="space-y-1.5">
            {contextItems.length === 0 && phase === "empty" && (
              <div className="flex items-center justify-center py-8">
                <span className="text-xs text-white/30 font-mono">
                  Empty context &mdash; click &ldquo;Fill Context&rdquo; to simulate a session
                </span>
              </div>
            )}

            <AnimatePresence mode="popLayout">
              {contextItems.map((item) => (
                <motion.div
                  key={`${item.type}-${item.id}`}
                  initial={{ opacity: 0, x: -16, scale: 0.95 }}
                  animate={{ opacity: 1, x: 0, scale: 1 }}
                  exit={{ opacity: 0, x: 16, scale: 0.9, height: 0, marginBottom: 0 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  layout
                  className={`flex items-center gap-2.5 px-3 py-1.5 rounded-lg border transition-colors duration-300 ${
                    item.type === "rule"
                      ? "border-rose-500/20 bg-rose-500/[0.06]"
                      : item.type === "message"
                        ? "border-blue-500/10 bg-blue-500/[0.03]"
                        : "border-emerald-500/10 bg-emerald-500/[0.03]"
                  }`}
                >
                  {item.iconType === "shield" && (
                    <ShieldCheck className={`h-3 w-3 shrink-0 ${item.color}`} />
                  )}
                  {item.iconType === "brain" && (
                    <Brain className={`h-3 w-3 shrink-0 ${item.color}`} />
                  )}
                  {item.iconType === "file" && (
                    <FileText className={`h-3 w-3 shrink-0 ${item.color}`} />
                  )}
                  <span className={`text-xs font-mono ${item.color} opacity-80`}>
                    {item.type === "rule" ? "[RULE] " : item.type === "message" ? "[MSG] " : "[CODE] "}
                    {item.label}
                  </span>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </div>

        {/* PCR Hook firing indicator */}
        <AnimatePresence>
          {pcrMessage && (
            <motion.div
              initial={{ opacity: 0, height: 0, y: 12 }}
              animate={{ opacity: 1, height: "auto", y: 0 }}
              exit={{ opacity: 0, height: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="overflow-hidden"
            >
              <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/[0.06] p-4 space-y-2">
                <div className="flex items-center gap-2">
                  <motion.div
                    animate={{ rotate: [0, -10, 10, -10, 0] }}
                    transition={{ duration: 0.5, delay: 0.2 }}
                  >
                    <BellRing className="h-4 w-4 text-emerald-400" />
                  </motion.div>
                  <span className="text-xs font-semibold text-emerald-400 uppercase tracking-wider">
                    PCR Hook Fired
                  </span>
                </div>
                <div className="rounded-lg bg-black/40 border border-white/[0.06] p-3">
                  <code className="text-[11px] text-emerald-300/80 font-mono leading-relaxed block">
                    {`[PCR] Context compaction detected.\n[PCR] Reminder: Re-read AGENTS.md now.\n[PCR] Restoring project rules and conventions...`}
                  </code>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Outcome summary */}
        <AnimatePresence>
          {(phase === "compacted" || phase === "restored") && (
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={`rounded-xl border p-4 space-y-2 ${
                phase === "restored"
                  ? "border-emerald-500/20 bg-emerald-500/[0.04]"
                  : "border-red-500/20 bg-red-500/[0.04]"
              }`}
            >
              <div className="flex items-center gap-2">
                {phase === "restored" ? (
                  <CheckCircle2 className="h-4 w-4 text-emerald-400" />
                ) : (
                  <XCircle className="h-4 w-4 text-red-400" />
                )}
                <span className={`text-sm font-semibold ${
                  phase === "restored" ? "text-emerald-300" : "text-red-300"
                }`}>
                  {phase === "restored"
                    ? "Rules Restored Successfully"
                    : "Rules Lost After Compaction"}
                </span>
              </div>
              <p className={`text-xs leading-relaxed ${
                phase === "restored" ? "text-emerald-400/70" : "text-red-400/70"
              }`}>
                {phase === "restored"
                  ? "PCR detected the compaction event and reminded the agent to re-read AGENTS.md. All project rules and conventions have been restored to the context window."
                  : "Without PCR, the agent has no reminder to re-read project rules. It will continue working but may violate conventions like using npm instead of bun, or deleting files without permission."}
              </p>
              {phase === "compacted" && !pcrEnabled && (
                <p className="text-xs text-white/30 mt-1">
                  Toggle PCR on and reset to see how the hook prevents this.
                </p>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

/** Returns status indicator props based on current simulation phase. */
function getStatusInfo(phase: SimPhase, pcrEnabled: boolean) {
  switch (phase) {
    case "empty":
      return {
        Icon: Brain,
        iconColor: "text-white/40",
        textColor: "text-white/50",
        borderClass: "rgba(255,255,255,0.08)",
        borderHex: "rgba(255,255,255,0.08)",
        label: "Agent idle — ready to start a session",
      };
    case "filling":
      return {
        Icon: Brain,
        iconColor: "text-blue-400",
        textColor: "text-blue-300",
        borderClass: "rgba(59,130,246,0.3)",
        borderHex: "rgba(59,130,246,0.3)",
        label: "Agent working — context window filling up...",
      };
    case "full":
      return {
        Icon: AlertTriangle,
        iconColor: "text-amber-400",
        textColor: "text-amber-300",
        borderClass: "rgba(245,158,11,0.3)",
        borderHex: "rgba(245,158,11,0.3)",
        label: "Context window full — compaction required!",
      };
    case "compacting":
      return {
        Icon: Shrink,
        iconColor: "text-orange-400",
        textColor: "text-orange-300",
        borderClass: "rgba(249,115,22,0.3)",
        borderHex: "rgba(249,115,22,0.3)",
        label: "Compacting context — removing old messages...",
      };
    case "compacted":
      return pcrEnabled
        ? {
            Icon: BellRing,
            iconColor: "text-emerald-400",
            textColor: "text-emerald-300",
            borderClass: "rgba(16,185,129,0.3)",
            borderHex: "rgba(16,185,129,0.3)",
            label: "Compaction complete — PCR hook will fire...",
          }
        : {
            Icon: XCircle,
            iconColor: "text-red-400",
            textColor: "text-red-300",
            borderClass: "rgba(239,68,68,0.3)",
            borderHex: "rgba(239,68,68,0.3)",
            label: "Compaction complete — project rules lost!",
          };
    case "pcr-firing":
      return {
        Icon: BellRing,
        iconColor: "text-emerald-400",
        textColor: "text-emerald-300",
        borderClass: "rgba(16,185,129,0.3)",
        borderHex: "rgba(16,185,129,0.3)",
        label: "PCR firing — reminding agent to re-read AGENTS.md...",
      };
    case "restored":
      return {
        Icon: CheckCircle2,
        iconColor: "text-emerald-400",
        textColor: "text-emerald-300",
        borderClass: "rgba(16,185,129,0.3)",
        borderHex: "rgba(16,185,129,0.3)",
        label: "Context restored — agent has re-read project rules",
      };
  }
}
