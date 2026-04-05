"use client";

import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { motion, AnimatePresence } from "@/components/motion";
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
  ChevronLeft,
  ChevronRight,
  Pause,
  Circle,
  CheckCircle2,
  Loader2,
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
          <InteractiveNtmOrchestrator />
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

          <TipBox variant="warning">
            If <Highlight>ntm send</Highlight> fails with a CASS error (for example:
            “unrecognized subcommand &apos;robot&apos;”), bypass duplicate-checking:
            <div className="mt-4 space-y-3">
              <CodeBlock code='ntm send myproject --no-cass-check "Analyze this codebase and summarize what it does"' />
              <CodeBlock code='ntm --robot-send myproject --msg "Analyze this codebase and summarize what it does" --all' />
            </div>
          </TipBox>

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
// INTERACTIVE NTM ORCHESTRATOR V2 - Hexagonal cockpit visualization
// =============================================================================

interface AgentPaneV2 {
  id: string;
  name: string;
  model: string;
  flag: string;
  color: string;
  colorLight: string;
  colorDim: string;
  spawnStep: number; // which step this pane spawns at
  /** Hex position angle (degrees from top, clockwise) */
  angle: number;
  terminalLines: string[];
}

type AgentStatus = "idle" | "working" | "done";

const AGENTS: AgentPaneV2[] = [
  {
    id: "cc1",
    name: "Claude-1",
    model: "claude-sonnet-4-6",
    flag: "--cc",
    color: "#f97316",
    colorLight: "#fdba74",
    colorDim: "rgba(249,115,22,0.15)",
    spawnStep: 1,
    angle: 30,
    terminalLines: [
      "$ claude --model sonnet",
      "Analyzing codebase structure...",
      "Found 147 source files",
      "Mapping dependency graph...",
      "Generating architecture doc...",
      "Writing summary report...",
    ],
  },
  {
    id: "cc2",
    name: "Claude-2",
    model: "claude-sonnet-4-6",
    flag: "--cc",
    color: "#f97316",
    colorLight: "#fdba74",
    colorDim: "rgba(249,115,22,0.15)",
    spawnStep: 2,
    angle: 90,
    terminalLines: [
      "$ claude --model sonnet",
      "Scanning test coverage...",
      "Running static analysis...",
      "Checking type safety...",
      "Auditing error handling...",
      "Compiling review notes...",
    ],
  },
  {
    id: "cod1",
    name: "Codex",
    model: "codex-mini",
    flag: "--cod",
    color: "#10b981",
    colorLight: "#6ee7b7",
    colorDim: "rgba(16,185,129,0.15)",
    spawnStep: 3,
    angle: 150,
    terminalLines: [
      "$ codex --model mini",
      "Linting source files...",
      "Auto-fixing 23 issues...",
      "Optimizing imports...",
      "Running formatter...",
      "All checks passing!",
    ],
  },
  {
    id: "gmi1",
    name: "Gemini",
    model: "gemini-2.5-pro",
    flag: "--gmi",
    color: "#3b82f6",
    colorLight: "#93c5fd",
    colorDim: "rgba(59,130,246,0.15)",
    spawnStep: 4,
    angle: 210,
    terminalLines: [
      "$ gemini --model pro",
      "Reading documentation...",
      "Cross-referencing APIs...",
      "Generating type stubs...",
      "Writing integration tests...",
      "Documentation complete!",
    ],
  },
];

const TOTAL_STEPS = 8;

const STEP_COMMANDS: Record<number, string> = {
  0: "ntm spawn myproject --cc=2 --cod=1 --gmi=1",
  1: "Spawning Claude-1 (claude-sonnet-4-6)...",
  2: "Spawning Claude-2 (claude-sonnet-4-6)...",
  3: "Spawning Codex (codex-mini)...",
  4: "Spawning Gemini (gemini-2.5-pro)...",
  5: 'ntm send myproject "Analyze this codebase"',
  6: "Agents working in parallel...",
  7: "All agents complete!",
};

const STEP_DURATIONS: Record<number, number> = {
  0: 1600,
  1: 1400,
  2: 1400,
  3: 1400,
  4: 1400,
  5: 1800,
  6: 3000,
  7: 2000,
};

// Hexagonal layout: panes arranged around a center hub
const HUB_CX = 350;
const HUB_CY = 220;
const HEX_RADIUS = 155;
const PANE_W = 140;
const PANE_H = 100;

function getPaneCenter(angle: number): { x: number; y: number } {
  const rad = ((angle - 90) * Math.PI) / 180;
  return {
    x: HUB_CX + HEX_RADIUS * Math.cos(rad),
    y: HUB_CY + HEX_RADIUS * Math.sin(rad),
  };
}

function InteractiveNtmOrchestrator() {
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [terminalProgress, setTerminalProgress] = useState<Record<string, number>>({});
  const [particleBurst, setParticleBurst] = useState(false);
  const [progressValues, setProgressValues] = useState<Record<string, number>>({});

  // Derive visible panes from step
  const visiblePanes = useMemo(
    () => AGENTS.filter((a) => step >= a.spawnStep),
    [step],
  );

  const showBroadcast = step >= 5;
  const showWorking = step >= 6;
  const showComplete = step >= 7;

  // Derive agent statuses from step (no effect needed)
  const agentStatuses = useMemo(() => {
    const statuses: Record<string, AgentStatus> = {};
    for (const agent of AGENTS) {
      if (step < agent.spawnStep) continue;
      if (showComplete) {
        statuses[agent.id] = "done";
      } else if (showWorking) {
        statuses[agent.id] = "working";
      } else {
        statuses[agent.id] = "idle";
      }
    }
    return statuses;
  }, [step, showComplete, showWorking]);

  // Terminal text scrolling during working phase
  useEffect(() => {
    if (!showWorking || showComplete) return;
    const interval = setInterval(() => {
      setTerminalProgress((prev) => {
        const next = { ...prev };
        for (const agent of AGENTS) {
          const current = prev[agent.id] ?? 0;
          if (current < agent.terminalLines.length - 1) {
            next[agent.id] = current + 1;
          }
        }
        return next;
      });
    }, 500);
    return () => clearInterval(interval);
  }, [showWorking, showComplete]);

  // Progress bar animation during working phase
  useEffect(() => {
    if (!showWorking) return;
    if (showComplete) {
      const t = setTimeout(() => {
        setProgressValues(() => {
          const v: Record<string, number> = {};
          for (const agent of AGENTS) v[agent.id] = 100;
          return v;
        });
      }, 0);
      return () => clearTimeout(t);
    }
    const interval = setInterval(() => {
      setProgressValues((prev) => {
        const next = { ...prev };
        for (const agent of AGENTS) {
          const current = prev[agent.id] ?? 0;
          if (current < 95) {
            next[agent.id] = Math.min(current + Math.random() * 15 + 5, 95);
          }
        }
        return next;
      });
    }, 400);
    return () => clearInterval(interval);
  }, [showWorking, showComplete]);

  // Particle burst when broadcast happens
  useEffect(() => {
    if (step === 5) {
      const tStart = setTimeout(() => setParticleBurst(true), 0);
      const tEnd = setTimeout(() => setParticleBurst(false), 1200);
      return () => {
        clearTimeout(tStart);
        clearTimeout(tEnd);
      };
    }
    const t = setTimeout(() => setParticleBurst(false), 0);
    return () => clearTimeout(t);
  }, [step]);

  // Reset terminal progress when going backwards
  useEffect(() => {
    if (step < 6) {
      const t = setTimeout(() => {
        setTerminalProgress({});
        setProgressValues({});
      }, 0);
      return () => clearTimeout(t);
    }
  }, [step]);

  // Auto-play timer
  useEffect(() => {
    if (!playing) return;
    const duration = STEP_DURATIONS[step] ?? 1800;
    timerRef.current = setTimeout(() => {
      setStep((s) => {
        const next = s + 1;
        if (next >= TOTAL_STEPS) {
          // Use setTimeout to avoid synchronous setState in the updater
          setTimeout(() => setPlaying(false), 0);
          return TOTAL_STEPS - 1;
        }
        return next;
      });
    }, duration);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [playing, step]);

  const goNext = useCallback(() => {
    setPlaying(false);
    setStep((s) => Math.min(s + 1, TOTAL_STEPS - 1));
  }, []);

  const goPrev = useCallback(() => {
    setPlaying(false);
    setStep((s) => Math.max(s - 1, 0));
  }, []);

  const togglePlay = useCallback(() => {
    setStep((currentStep) => {
      if (currentStep >= TOTAL_STEPS - 1) {
        setTimeout(() => setPlaying(true), 0);
        return 0;
      }
      setTimeout(() => setPlaying((p) => !p), 0);
      return currentStep;
    });
  }, []);

  const goToStep = useCallback((i: number) => {
    setPlaying(false);
    setStep(i);
  }, []);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="pointer-events-none absolute -top-20 left-1/4 w-64 h-64 bg-violet-500/8 rounded-full blur-3xl" />
      <div className="pointer-events-none absolute -bottom-16 right-1/4 w-48 h-48 bg-orange-500/6 rounded-full blur-3xl" />
      <div className="pointer-events-none absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-40 h-40 bg-emerald-500/5 rounded-full blur-3xl" />

      {/* Command display bar */}
      <div className="relative px-4 sm:px-6 pt-5 pb-2">
        <div className="flex items-center gap-2 px-4 py-2.5 rounded-lg bg-black/50 border border-white/[0.08] font-mono text-sm">
          <span className="text-emerald-400 select-none shrink-0">$</span>
          <AnimatePresence mode="wait">
            <motion.span
              key={step}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ type: "spring", stiffness: 300, damping: 25 }}
              className="text-white/80 truncate"
            >
              {STEP_COMMANDS[step]}
            </motion.span>
          </AnimatePresence>
          {showComplete && (
            <motion.span
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="ml-auto shrink-0"
            >
              <CheckCircle2 className="h-4 w-4 text-emerald-400" />
            </motion.span>
          )}
        </div>
      </div>

      {/* SVG Cockpit Visualization */}
      <div className="relative px-2 sm:px-4 pb-2">
        <svg
          viewBox="0 0 700 440"
          className="w-full"
          role="img"
          aria-label="NTM cockpit visualization showing hexagonal agent layout"
        >
          <defs>
            {AGENTS.map((agent) => (
              <linearGradient
                key={`v2-grad-${agent.id}`}
                id={`v2-grad-${agent.id}`}
                x1="0%"
                y1="0%"
                x2="100%"
                y2="100%"
              >
                <stop offset="0%" stopColor={agent.color} stopOpacity="0.3" />
                <stop offset="100%" stopColor={agent.color} stopOpacity="0.05" />
              </linearGradient>
            ))}
            <radialGradient id="v2-hub-glow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="rgba(139,92,246,0.3)" />
              <stop offset="100%" stopColor="rgba(139,92,246,0)" />
            </radialGradient>
            <filter id="v2-glow">
              <feGaussianBlur stdDeviation="3" result="coloredBlur" />
              <feMerge>
                <feMergeNode in="coloredBlur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
            <filter id="v2-glow-strong">
              <feGaussianBlur stdDeviation="6" result="coloredBlur" />
              <feMerge>
                <feMergeNode in="coloredBlur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Hexagonal grid lines (subtle background pattern) */}
          <g opacity={0.04}>
            {[0, 60, 120, 180, 240, 300].map((angle) => {
              const rad = ((angle - 90) * Math.PI) / 180;
              const ex = HUB_CX + 200 * Math.cos(rad);
              const ey = HUB_CY + 200 * Math.sin(rad);
              return (
                <line
                  key={`hex-line-${angle}`}
                  x1={HUB_CX}
                  y1={HUB_CY}
                  x2={ex}
                  y2={ey}
                  stroke="white"
                  strokeWidth={1}
                />
              );
            })}
          </g>

          {/* Hub glow circle */}
          <circle
            cx={HUB_CX}
            cy={HUB_CY}
            r={50}
            fill="url(#v2-hub-glow)"
          />

          {/* Connection lines from hub to panes */}
          <AnimatePresence>
            {visiblePanes.map((agent) => {
              const center = getPaneCenter(agent.angle);
              return (
                <motion.line
                  key={`conn-${agent.id}`}
                  x1={HUB_CX}
                  y1={HUB_CY}
                  x2={center.x}
                  y2={center.y}
                  stroke={agent.color}
                  strokeOpacity={0.2}
                  strokeWidth={1.5}
                  strokeDasharray="4 3"
                  initial={{ pathLength: 0, opacity: 0 }}
                  animate={{ pathLength: 1, opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ type: "spring", stiffness: 150, damping: 20 }}
                />
              );
            })}
          </AnimatePresence>

          {/* Particle burst animation on broadcast */}
          {particleBurst &&
            visiblePanes.map((agent) => {
              const center = getPaneCenter(agent.angle);
              return Array.from({ length: 5 }).map((_, pi) => (
                <motion.circle
                  key={`particle-${agent.id}-${pi}`}
                  r={3 - pi * 0.4}
                  fill={agent.color}
                  filter="url(#v2-glow)"
                  initial={{
                    cx: HUB_CX,
                    cy: HUB_CY,
                    opacity: 1,
                    scale: 1,
                  }}
                  animate={{
                    cx: center.x,
                    cy: center.y,
                    opacity: [1, 0.9, 0],
                    scale: [1, 1.2, 0.5],
                  }}
                  transition={{
                    duration: 0.8,
                    delay: pi * 0.08,
                    ease: "easeOut",
                  }}
                />
              ));
            })}

          {/* Hub pulsing ring for broadcast */}
          {showBroadcast && !showComplete && (
            <motion.circle
              cx={HUB_CX}
              cy={HUB_CY}
              r={35}
              fill="none"
              stroke="rgba(139,92,246,0.4)"
              strokeWidth={2}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{
                scale: [1, 1.8, 2.2],
                opacity: [0.6, 0.2, 0],
              }}
              transition={{
                duration: 2,
                repeat: Infinity,
                ease: "easeOut",
              }}
            />
          )}

          {/* Central NTM Hub */}
          <motion.g
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
          >
            {/* Hub outer ring */}
            <circle
              cx={HUB_CX}
              cy={HUB_CY}
              r={36}
              fill="rgba(139,92,246,0.08)"
              stroke="rgba(139,92,246,0.35)"
              strokeWidth={1.5}
            />
            {/* Hub inner ring */}
            <circle
              cx={HUB_CX}
              cy={HUB_CY}
              r={24}
              fill="rgba(139,92,246,0.15)"
              stroke="rgba(139,92,246,0.5)"
              strokeWidth={1}
            />
            {/* Hub icon - circuit pattern */}
            <NtmHubIconV2 cx={HUB_CX} cy={HUB_CY} />
            {/* Label */}
            <text
              x={HUB_CX}
              y={HUB_CY + 52}
              fill="rgba(255,255,255,0.7)"
              fontSize="12"
              fontWeight="bold"
              fontFamily="system-ui"
              textAnchor="middle"
            >
              NTM Hub
            </text>
            <text
              x={HUB_CX}
              y={HUB_CY + 66}
              fill="rgba(255,255,255,0.35)"
              fontSize="9"
              fontFamily="monospace"
              textAnchor="middle"
            >
              Command Center
            </text>
          </motion.g>

          {/* Empty session placeholder at step 0 */}
          {step === 0 && (
            <motion.g
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              {/* Dashed hex outline */}
              {[30, 90, 150, 210].map((angle) => {
                const c = getPaneCenter(angle);
                return (
                  <rect
                    key={`placeholder-${angle}`}
                    x={c.x - PANE_W / 2}
                    y={c.y - PANE_H / 2}
                    width={PANE_W}
                    height={PANE_H}
                    rx={10}
                    fill="rgba(255,255,255,0.01)"
                    stroke="rgba(255,255,255,0.06)"
                    strokeWidth={1}
                    strokeDasharray="6 4"
                  />
                );
              })}
              <text
                x={HUB_CX}
                y={HUB_CY + 120}
                fill="rgba(255,255,255,0.2)"
                fontSize="11"
                fontFamily="system-ui"
                textAnchor="middle"
              >
                No agents spawned yet
              </text>
            </motion.g>
          )}

          {/* Agent terminal panes */}
          <AnimatePresence>
            {visiblePanes.map((agent) => {
              const center = getPaneCenter(agent.angle);
              const px = center.x - PANE_W / 2;
              const py = center.y - PANE_H / 2;
              const status = agentStatuses[agent.id] ?? "idle";
              const termLine = terminalProgress[agent.id] ?? 0;
              const progress = progressValues[agent.id] ?? 0;

              return (
                <motion.g
                  key={`pane-${agent.id}`}
                  initial={{ opacity: 0, scale: 0.3 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.3 }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                  }}
                >
                  {/* Explosion ring on spawn */}
                  <motion.circle
                    cx={center.x}
                    cy={center.y}
                    r={20}
                    fill="none"
                    stroke={agent.color}
                    strokeWidth={2}
                    initial={{ scale: 0.5, opacity: 0.8 }}
                    animate={{ scale: 3, opacity: 0 }}
                    transition={{ duration: 0.6, ease: "easeOut" }}
                  />

                  {/* Pane background */}
                  <rect
                    x={px}
                    y={py}
                    width={PANE_W}
                    height={PANE_H}
                    rx={10}
                    fill={`url(#v2-grad-${agent.id})`}
                    stroke={agent.color}
                    strokeOpacity={0.3}
                    strokeWidth={1.2}
                  />

                  {/* Title bar */}
                  <rect
                    x={px}
                    y={py}
                    width={PANE_W}
                    height={22}
                    rx={10}
                    fill={agent.colorDim}
                  />
                  <rect
                    x={px}
                    y={py + 10}
                    width={PANE_W}
                    height={12}
                    fill={agent.colorDim}
                  />

                  {/* Traffic light dots */}
                  <circle cx={px + 12} cy={py + 11} r={3} fill="rgba(255,255,255,0.15)" />
                  <circle cx={px + 22} cy={py + 11} r={3} fill="rgba(255,255,255,0.1)" />
                  <circle cx={px + 32} cy={py + 11} r={3} fill="rgba(255,255,255,0.08)" />

                  {/* Agent name */}
                  <text
                    x={px + 46}
                    y={py + 15}
                    fill={agent.colorLight}
                    fontSize="9"
                    fontWeight="600"
                    fontFamily="system-ui"
                  >
                    {agent.name}
                  </text>

                  {/* Status indicator */}
                  <OrchestratorStatusDot
                    x={px + PANE_W - 14}
                    y={py + 11}
                    status={status}
                    color={agent.color}
                  />

                  {/* Terminal content area */}
                  <rect
                    x={px + 4}
                    y={py + 24}
                    width={PANE_W - 8}
                    height={PANE_H - 28}
                    rx={4}
                    fill="rgba(0,0,0,0.3)"
                  />

                  {/* Model label */}
                  <text
                    x={px + 10}
                    y={py + 38}
                    fill="rgba(255,255,255,0.3)"
                    fontSize="7"
                    fontFamily="monospace"
                  >
                    {agent.model}
                  </text>

                  {/* Terminal output text */}
                  {status === "idle" && (
                    <text
                      x={px + 10}
                      y={py + 52}
                      fill="rgba(255,255,255,0.2)"
                      fontSize="7.5"
                      fontFamily="monospace"
                    >
                      Waiting for task...
                    </text>
                  )}

                  {(status === "working" || status === "done") && (
                    <>
                      <text
                        x={px + 10}
                        y={py + 52}
                        fill={agent.colorLight}
                        fillOpacity={0.7}
                        fontSize="7.5"
                        fontFamily="monospace"
                      >
                        {agent.terminalLines[Math.min(termLine, agent.terminalLines.length - 1)]}
                      </text>
                      {status === "working" && (
                        <OrchestratorTypingCursor
                          x={px + 10}
                          y={py + 64}
                          color={agent.colorLight}
                        />
                      )}
                    </>
                  )}

                  {/* Progress bar for working/done */}
                  {(status === "working" || status === "done") && (
                    <g>
                      <rect
                        x={px + 10}
                        y={py + PANE_H - 14}
                        width={PANE_W - 28}
                        height={4}
                        rx={2}
                        fill="rgba(255,255,255,0.05)"
                      />
                      <motion.rect
                        x={px + 10}
                        y={py + PANE_H - 14}
                        height={4}
                        rx={2}
                        fill={agent.color}
                        fillOpacity={0.7}
                        initial={{ width: 0 }}
                        animate={{
                          width:
                            ((status === "done" ? 100 : progress) / 100) *
                            (PANE_W - 28),
                        }}
                        transition={{
                          type: "spring",
                          stiffness: 100,
                          damping: 20,
                        }}
                      />
                      <text
                        x={px + PANE_W - 14}
                        y={py + PANE_H - 10}
                        fill="rgba(255,255,255,0.3)"
                        fontSize="6"
                        fontFamily="monospace"
                        textAnchor="end"
                      >
                        {status === "done"
                          ? "100%"
                          : `${Math.round(progress)}%`}
                      </text>
                    </g>
                  )}

                  {/* Done checkmark overlay */}
                  {status === "done" && (
                    <motion.g
                      initial={{ opacity: 0, scale: 0 }}
                      animate={{ opacity: 1, scale: 1 }}
                      transition={{
                        type: "spring",
                        stiffness: 200,
                        damping: 25,
                      }}
                    >
                      <text
                        x={px + 10}
                        y={py + 64}
                        fill={agent.colorLight}
                        fillOpacity={0.9}
                        fontSize="7.5"
                        fontWeight="bold"
                        fontFamily="monospace"
                      >
                        Done!
                      </text>
                    </motion.g>
                  )}
                </motion.g>
              );
            })}
          </AnimatePresence>

          {/* Minimap in bottom-right corner */}
          <g transform="translate(590, 350)">
            <rect
              x={0}
              y={0}
              width={90}
              height={70}
              rx={6}
              fill="rgba(0,0,0,0.4)"
              stroke="rgba(255,255,255,0.08)"
              strokeWidth={1}
            />
            <text
              x={8}
              y={14}
              fill="rgba(255,255,255,0.3)"
              fontSize="7"
              fontFamily="system-ui"
            >
              tmux layout
            </text>
            {/* Minimap panes */}
            {AGENTS.map((agent) => {
              const visible = step >= agent.spawnStep;
              // Map agent positions into minimap space
              const c = getPaneCenter(agent.angle);
              const mx = 45 + ((c.x - HUB_CX) / HEX_RADIUS) * 28;
              const my = 40 + ((c.y - HUB_CY) / HEX_RADIUS) * 18;
              return (
                <rect
                  key={`mini-${agent.id}`}
                  x={mx - 8}
                  y={my - 5}
                  width={16}
                  height={10}
                  rx={2}
                  fill={visible ? agent.color : "rgba(255,255,255,0.05)"}
                  fillOpacity={visible ? 0.6 : 1}
                  stroke={
                    visible ? agent.color : "rgba(255,255,255,0.08)"
                  }
                  strokeOpacity={visible ? 0.4 : 1}
                  strokeWidth={0.5}
                />
              );
            })}
            {/* Minimap hub dot */}
            <circle cx={45} cy={40} r={3} fill="rgba(139,92,246,0.6)" />
          </g>
        </svg>
      </div>

      {/* Status summary bar */}
      <div className="relative flex items-center justify-center gap-3 px-4 sm:px-6 pb-2 flex-wrap">
        {AGENTS.map((agent) => {
          const visible = step >= agent.spawnStep;
          const status = agentStatuses[agent.id] ?? "idle";
          return (
            <motion.div
              key={`status-${agent.id}`}
              initial={{ opacity: 0, y: 10 }}
              animate={{
                opacity: visible ? 1 : 0.3,
                y: 0,
              }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-white/[0.02] border border-white/[0.06] text-xs"
            >
              {visible && status === "done" ? (
                <CheckCircle2
                  className="h-3 w-3"
                  style={{ color: agent.color }}
                />
              ) : visible && status === "working" ? (
                <Loader2
                  className="h-3 w-3 animate-spin"
                  style={{ color: agent.color }}
                />
              ) : (
                <Circle
                  className="h-3 w-3"
                  style={{
                    color: visible ? agent.color : "rgba(255,255,255,0.2)",
                  }}
                />
              )}
              <span
                className="font-mono"
                style={{
                  color: visible
                    ? agent.colorLight
                    : "rgba(255,255,255,0.2)",
                }}
              >
                {agent.name}
              </span>
            </motion.div>
          );
        })}
      </div>

      {/* Controls */}
      <div className="relative flex items-center justify-center gap-4 px-6 pb-4 pt-2">
        <button
          type="button"
          onClick={goPrev}
          disabled={step === 0}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition-all hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Previous step"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        <button
          type="button"
          onClick={togglePlay}
          className="flex h-10 w-10 items-center justify-center rounded-full border border-primary/30 bg-primary/10 text-primary transition-all hover:bg-primary/20"
          aria-label={playing ? "Pause" : "Play"}
        >
          {playing ? (
            <Pause className="h-4 w-4" />
          ) : (
            <Play className="h-4 w-4" />
          )}
        </button>

        <button
          type="button"
          onClick={goNext}
          disabled={step >= TOTAL_STEPS - 1}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition-all hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Next step"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      {/* Step indicator dots */}
      <div className="relative flex items-center justify-center gap-1.5 pb-5">
        {Array.from({ length: TOTAL_STEPS }).map((_, i) => (
          <button
            key={i}
            type="button"
            onClick={() => goToStep(i)}
            className={`h-2 rounded-full transition-all duration-300 ${
              i === step
                ? "w-6 bg-primary"
                : i < step
                  ? "w-2 bg-white/30"
                  : "w-2 bg-white/10"
            }`}
            aria-label={`Go to step ${i + 1}: ${STEP_COMMANDS[i]}`}
          />
        ))}
      </div>
    </div>
  );
}

// =============================================================================
// V2 HELPER COMPONENTS
// =============================================================================

function NtmHubIconV2({ cx, cy }: { cx: number; cy: number }) {
  return (
    <g>
      {/* Central processor square */}
      <rect
        x={cx - 10}
        y={cy - 10}
        width={20}
        height={20}
        rx={4}
        fill="none"
        stroke="rgba(139,92,246,0.9)"
        strokeWidth={1.5}
      />
      <rect
        x={cx - 5}
        y={cy - 5}
        width={10}
        height={10}
        rx={2}
        fill="rgba(139,92,246,0.6)"
      />
      {/* Signal lines radiating out */}
      {[0, 90, 180, 270].map((angle) => {
        const rad = (angle * Math.PI) / 180;
        const ix = cx + 10 * Math.cos(rad);
        const iy = cy + 10 * Math.sin(rad);
        const ox = cx + 18 * Math.cos(rad);
        const oy = cy + 18 * Math.sin(rad);
        return (
          <line
            key={`hub-pin-${angle}`}
            x1={ix}
            y1={iy}
            x2={ox}
            y2={oy}
            stroke="rgba(139,92,246,0.5)"
            strokeWidth={1.5}
          />
        );
      })}
      {/* Diagonal signal lines */}
      {[45, 135, 225, 315].map((angle) => {
        const rad = (angle * Math.PI) / 180;
        const ix = cx + 9 * Math.cos(rad);
        const iy = cy + 9 * Math.sin(rad);
        const ox = cx + 15 * Math.cos(rad);
        const oy = cy + 15 * Math.sin(rad);
        return (
          <line
            key={`hub-diag-${angle}`}
            x1={ix}
            y1={iy}
            x2={ox}
            y2={oy}
            stroke="rgba(139,92,246,0.3)"
            strokeWidth={1}
          />
        );
      })}
    </g>
  );
}

function OrchestratorStatusDot({
  x,
  y,
  status,
  color,
}: {
  x: number;
  y: number;
  status: AgentStatus;
  color: string;
}) {
  if (status === "done") {
    return (
      <motion.circle
        cx={x}
        cy={y}
        r={4}
        fill="#10b981"
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
      />
    );
  }
  if (status === "working") {
    return (
      <motion.circle
        cx={x}
        cy={y}
        r={4}
        fill={color}
        animate={{ opacity: [1, 0.3, 1] }}
        transition={{ duration: 1, repeat: Infinity }}
      />
    );
  }
  return (
    <circle
      cx={x}
      cy={y}
      r={3}
      fill="rgba(255,255,255,0.15)"
    />
  );
}

function OrchestratorTypingCursor({
  x,
  y,
  color,
}: {
  x: number;
  y: number;
  color: string;
}) {
  return (
    <motion.g
      animate={{ opacity: [1, 0.2, 1] }}
      transition={{ duration: 0.8, repeat: Infinity }}
    >
      <rect
        x={x}
        y={y - 3}
        width={4}
        height={6}
        rx={1}
        fill={color}
        fillOpacity={0.6}
      />
    </motion.g>
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
                  <span className="text-white/50 text-xs">then</span>
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
