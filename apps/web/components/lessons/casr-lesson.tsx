'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from "@/components/motion";
import {
  Terminal,
  Repeat,
  FileText,
  ArrowRightLeft,
  Play,
  Lightbulb,
  CheckCircle2,
  Clock,
  ArrowRight,
  Database,
  Zap,
  Layers,
  Archive,
  ChevronRight,
  ChevronLeft,
  Sparkles,
  Shield,
  Cpu,
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
const InteractiveSessionHandoff = InteractiveSessionHandoffImpl;

export function CasrLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Resume coding sessions across AI providers with Cross-Agent Session Resumer.
      </GoalBanner>

      {/* Section 1: What Is CASR */}
      <Section title="What Is CASR?" icon={<Repeat className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>CASR (Cross-Agent Session Resumer)</Highlight> converts and resumes
          AI coding sessions across different providers. Start a session in Claude Code,
          continue it in Codex CLI, and pick it back up in Antigravity CLI without losing context.
        </Paragraph>
        <Paragraph>
          CASR extracts conversation context, code changes, and decisions into a
          portable format that any agent can ingest. This enables provider-hopping
          when you hit rate limits or want a second opinion.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ArrowRightLeft className="h-5 w-5" />}
              title="Provider Agnostic"
              description="Convert sessions between Claude, Codex, and Antigravity"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Context Preservation"
              description="Decisions, code changes, and rationale carry over"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Repeat className="h-5 w-5" />}
              title="Seamless Handoff"
              description="Resume mid-task without re-explaining context"
              gradient="from-cyan-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Lightbulb className="h-5 w-5" />}
              title="Rate Limit Recovery"
              description="Switch providers instantly when throttled"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'casr export', description: 'Export current session context' },
            { command: 'casr resume --from claude', description: 'Resume a Claude session in current provider' },
            { command: 'casr list', description: 'List available session snapshots' },
            { command: 'casr --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          Use CASR when you hit a rate limit on one provider and want to seamlessly
          continue your work on another without losing context.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Export current Claude Code session
casr export

# Resume in Codex CLI
casr resume --from claude --to codex

# List all saved session snapshots
casr list`} />
      </Section>

      <Divider />

      {/* Section 4: Interactive Session Handoff */}
      <Section title="Try a Session Handoff" icon={<ArrowRightLeft className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          Step through the full session handoff pipeline. Watch an agent session get captured,
          distilled, and injected into a new agent with animated token compression and context flow.
        </Paragraph>
        <div className="mt-6">
          <InteractiveSessionHandoff />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE SESSION HANDOFF - Dramatic upgrade with stepper, SVG pipeline,
// token counter, context window visualization, and mini terminal
// =============================================================================

interface ScenarioStep {
  id: string;
  label: string;
  shortLabel: string;
  icon: React.ReactNode;
  description: string;
  terminalLines: string[];
  tokensBefore: number;
  tokensAfter: number;
}

const SCENARIO_STEPS: ScenarioStep[] = [
  {
    id: 'capture',
    label: 'Session Capture',
    shortLabel: 'Capture',
    icon: <Database className="h-4 w-4" />,
    description: 'The current agent\'s full session is captured including all conversation turns, tool calls, file edits, and reasoning traces.',
    terminalLines: [
      '$ casr export --format portable',
      'Scanning session history...',
      'Found 47 conversation turns',
      'Found 12 tool invocations',
      'Found 8 file modifications',
      'Session captured: .casr/session_2026-03-12.json',
    ],
    tokensBefore: 128000,
    tokensAfter: 128000,
  },
  {
    id: 'extract',
    label: 'Context Extraction',
    shortLabel: 'Extract',
    icon: <Layers className="h-4 w-4" />,
    description: 'Key context is extracted: task description, code changes, architectural decisions, and unresolved questions are pulled from the raw session.',
    terminalLines: [
      '$ casr extract --session latest',
      'Parsing conversation graph...',
      'Extracting task context... done',
      'Extracting code diffs... 8 files',
      'Extracting decisions... 5 items',
      'Extraction complete: 42KB context',
    ],
    tokensBefore: 128000,
    tokensAfter: 48200,
  },
  {
    id: 'distill',
    label: 'Knowledge Distillation',
    shortLabel: 'Distill',
    icon: <Sparkles className="h-4 w-4" />,
    description: 'The extracted context is compressed and distilled. Redundant information is removed, key decisions are summarized, and a portable handoff document is produced.',
    terminalLines: [
      '$ casr distill --optimize',
      'Compressing conversation turns...',
      'Deduplicating code context...',
      'Summarizing 5 decisions -> 5 bullets',
      'Optimizing for target window...',
      'Distilled: 128K -> 8.2K tokens (93.6%)',
    ],
    tokensBefore: 48200,
    tokensAfter: 8200,
  },
  {
    id: 'bootstrap',
    label: 'New Agent Bootstrap',
    shortLabel: 'Bootstrap',
    icon: <Cpu className="h-4 w-4" />,
    description: 'A new agent session is initialized with the target provider. The agent\'s system prompt and capabilities are configured for the handoff.',
    terminalLines: [
      '$ casr resume --to codex --dry-run',
      'Initializing Codex CLI session...',
      'Configuring system prompt...',
      'Setting workspace: ~/projects/auth',
      'Agent ready, awaiting context...',
      'Bootstrap complete.',
    ],
    tokensBefore: 0,
    tokensAfter: 2100,
  },
  {
    id: 'inject',
    label: 'Context Injection',
    shortLabel: 'Inject',
    icon: <Zap className="h-4 w-4" />,
    description: 'The distilled handoff document is injected into the new agent\'s context window. The agent now has full awareness of the prior session\'s work.',
    terminalLines: [
      '$ casr resume --to codex',
      'Injecting handoff document...',
      'Loading task: auth middleware refactor',
      'Loading 8 file contexts...',
      'Loading 5 key decisions...',
      'Context injection complete: 10.3K tokens',
    ],
    tokensBefore: 2100,
    tokensAfter: 10300,
  },
  {
    id: 'verify',
    label: 'Verification',
    shortLabel: 'Verify',
    icon: <Shield className="h-4 w-4" />,
    description: 'The new agent verifies it understands the handoff by summarizing the task, confirming key decisions, and identifying the next action to take.',
    terminalLines: [
      '$ casr verify --check-context',
      'Agent confirms task understanding...',
      'Verified: 5/5 decisions acknowledged',
      'Verified: 8/8 files in workspace',
      'Next action: implement PKCE verifier',
      'Handoff verified. Session ready.',
    ],
    tokensBefore: 10300,
    tokensAfter: 10300,
  },
];

const AGENTS_DATA = [
  { id: 'claude', name: 'Claude', color: '#f97316', textClass: 'text-orange-400', bgClass: 'bg-orange-500/15', borderClass: 'border-orange-500/30' },
  { id: 'codex', name: 'Codex', color: '#10b981', textClass: 'text-emerald-400', bgClass: 'bg-emerald-500/15', borderClass: 'border-emerald-500/30' },
  { id: 'gemini', name: 'Gemini', color: '#3b82f6', textClass: 'text-blue-400', bgClass: 'bg-blue-500/15', borderClass: 'border-blue-500/30' },
];

const CONTEXT_WINDOW_MAX = 128000;

const springTransition = { type: "spring" as const, stiffness: 200, damping: 25 };

function InteractiveSessionHandoffImpl() {
  const [currentStep, setCurrentStep] = useState(0);
  const [sourceAgent] = useState(0); // Claude
  const [targetAgent] = useState(1); // Codex
  const [terminalVisibleLines, setTerminalVisibleLines] = useState(0);
  const [animatedTokens, setAnimatedTokens] = useState(0);
  const [animatedCompressed, setAnimatedCompressed] = useState(0);
  const [pipelineProgress, setPipelineProgress] = useState(0);
  const terminalRef = useRef<HTMLDivElement>(null);
  const animFrameRef = useRef(0);
  const pipelineFrameRef = useRef(0);

  const step = SCENARIO_STEPS[currentStep];
  const source = AGENTS_DATA[sourceAgent];
  const target = AGENTS_DATA[targetAgent];

  // Animate terminal lines appearing one by one when step changes
  useEffect(() => {
    setTerminalVisibleLines(0);
    const totalLines = SCENARIO_STEPS[currentStep].terminalLines.length;
    const timers: ReturnType<typeof setTimeout>[] = [];
    for (let i = 0; i < totalLines; i++) {
      const timer = setTimeout(() => {
        setTerminalVisibleLines(i + 1);
      }, 200 + i * 280);
      timers.push(timer);
    }
    return () => {
      timers.forEach(clearTimeout);
    };
  }, [currentStep]);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [terminalVisibleLines]);

  // Animate token counter
  useEffect(() => {
    const targetTokens = step.tokensBefore;
    const targetCompressed = step.tokensAfter;
    let running = true;
    const duration = 600;
    const t0 = performance.now();
    const startTokens = animatedTokens;
    const startCompressed = animatedCompressed;

    function tick(now: number) {
      if (!running) return;
      const elapsed = now - t0;
      const progress = Math.min(elapsed / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 3);

      setAnimatedTokens(Math.round(startTokens + (targetTokens - startTokens) * ease));
      setAnimatedCompressed(Math.round(startCompressed + (targetCompressed - startCompressed) * ease));

      if (progress < 1) {
        animFrameRef.current = requestAnimationFrame(tick);
      }
    }

    animFrameRef.current = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(animFrameRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step.tokensBefore, step.tokensAfter]);

  // Animate pipeline progress
  useEffect(() => {
    const targetProgress = ((currentStep + 1) / SCENARIO_STEPS.length) * 100;
    let running = true;
    const duration = 500;
    const t0 = performance.now();
    const startProgress = pipelineProgress;

    function tick(now: number) {
      if (!running) return;
      const elapsed = now - t0;
      const progress = Math.min(elapsed / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 3);
      setPipelineProgress(startProgress + (targetProgress - startProgress) * ease);
      if (progress < 1) {
        pipelineFrameRef.current = requestAnimationFrame(tick);
      }
    }

    pipelineFrameRef.current = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(pipelineFrameRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentStep]);

  const goNext = useCallback(() => {
    setCurrentStep((prev) => Math.min(prev + 1, SCENARIO_STEPS.length - 1));
  }, []);

  const goPrev = useCallback(() => {
    setCurrentStep((prev) => Math.max(prev - 1, 0));
  }, []);

  const goToStep = useCallback((idx: number) => {
    setCurrentStep(idx);
  }, []);

  // Compression ratio for current step
  const compressionRatio = animatedTokens > 0
    ? Math.round((1 - animatedCompressed / animatedTokens) * 100)
    : 0;

  // Context window fill percentage
  const contextFillPct = Math.min((animatedCompressed / CONTEXT_WINDOW_MAX) * 100, 100);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 rounded-full blur-3xl pointer-events-none" style={{ background: `${source.color}08` }} />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 rounded-full blur-3xl pointer-events-none" style={{ background: `${target.color}08` }} />

      <div className="relative p-5 sm:p-6 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <p className="text-sm font-semibold text-white/80">Session Handoff Pipeline</p>
          <p className="text-xs text-white/40">
            <span className={source.textClass}>{source.name}</span>
            <ArrowRight className="inline h-3 w-3 mx-1.5 text-white/30" />
            <span className={target.textClass}>{target.name}</span>
          </p>
        </div>

        {/* ========== Stepper ========== */}
        <div className="space-y-3">
          {/* Step indicators */}
          <div className="flex items-center justify-between gap-1">
            {SCENARIO_STEPS.map((s, i) => {
              const isActive = i === currentStep;
              const isCompleted = i < currentStep;
              return (
                <button
                  key={s.id}
                  onClick={() => goToStep(i)}
                  className="flex-1 group relative"
                >
                  <div className="flex flex-col items-center gap-1.5">
                    <motion.div
                      animate={{
                        scale: isActive ? 1 : 0.85,
                        opacity: isActive ? 1 : isCompleted ? 0.8 : 0.4,
                      }}
                      transition={springTransition}
                      className={`relative flex h-8 w-8 items-center justify-center rounded-lg border transition-colors ${
                        isActive
                          ? 'border-violet-500/50 bg-violet-500/20 text-violet-300'
                          : isCompleted
                            ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                            : 'border-white/[0.08] bg-white/[0.03] text-white/30'
                      }`}
                    >
                      {isCompleted ? (
                        <CheckCircle2 className="h-4 w-4" />
                      ) : (
                        s.icon
                      )}
                      {isActive && (
                        <motion.div
                          layoutId="step-glow"
                          className="absolute inset-0 rounded-lg bg-violet-500/20 blur-md"
                          transition={springTransition}
                        />
                      )}
                    </motion.div>
                    <span className={`text-[9px] font-medium leading-tight text-center hidden sm:block ${
                      isActive ? 'text-white/70' : isCompleted ? 'text-white/50' : 'text-white/25'
                    }`}>
                      {s.shortLabel}
                    </span>
                  </div>
                  {/* Connector line */}
                  {i < SCENARIO_STEPS.length - 1 && (
                    <div className="absolute top-4 left-[calc(50%+16px)] right-[calc(-50%+16px)] h-px bg-white/[0.06]">
                      <motion.div
                        animate={{ scaleX: isCompleted ? 1 : 0 }}
                        transition={springTransition}
                        className="h-full bg-emerald-500/40 origin-left"
                      />
                    </div>
                  )}
                </button>
              );
            })}
          </div>

          {/* Overall progress bar */}
          <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              animate={{ width: `${pipelineProgress}%` }}
              transition={springTransition}
              className="h-full rounded-full bg-gradient-to-r from-violet-500 to-cyan-500"
            />
          </div>
        </div>

        {/* ========== Step Content ========== */}
        <AnimatePresence mode="wait">
          <motion.div
            key={step.id}
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -16 }}
            transition={springTransition}
            className="space-y-5"
          >
            {/* Step title and description */}
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <div className="flex h-6 w-6 items-center justify-center rounded-md bg-violet-500/20 text-violet-300">
                  {step.icon}
                </div>
                <h4 className="text-sm font-semibold text-white/90">{step.label}</h4>
                <span className="text-[10px] font-mono text-white/30 px-1.5 py-0.5 rounded bg-white/[0.04]">
                  {currentStep + 1}/{SCENARIO_STEPS.length}
                </span>
              </div>
              <p className="text-xs text-white/50 leading-relaxed pl-8">
                {step.description}
              </p>
            </div>

            {/* ========== SVG Pipeline Diagram ========== */}
            <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 overflow-hidden">
              <svg viewBox="0 0 600 120" className="w-full h-auto" aria-label="Session handoff pipeline diagram">
                <defs>
                  <filter id="casr-glow" x="-50%" y="-50%" width="200%" height="200%">
                    <feGaussianBlur stdDeviation="3" result="blur" />
                    <feMerge>
                      <feMergeNode in="blur" />
                      <feMergeNode in="SourceGraphic" />
                    </feMerge>
                  </filter>
                  <linearGradient id="flow-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor={source.color} stopOpacity="0.8" />
                    <stop offset="50%" stopColor="#8b5cf6" stopOpacity="0.8" />
                    <stop offset="100%" stopColor={target.color} stopOpacity="0.8" />
                  </linearGradient>
                  <linearGradient id="pipe-bg" x1="0%" y1="0%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor="white" stopOpacity="0.04" />
                    <stop offset="100%" stopColor="white" stopOpacity="0.04" />
                  </linearGradient>
                </defs>

                {/* Pipeline background track */}
                <rect x="80" y="52" width="440" height="16" rx="8" fill="url(#pipe-bg)" stroke="white" strokeOpacity="0.06" strokeWidth="1" />

                {/* Animated flow fill */}
                <motion.rect
                  x="80"
                  y="52"
                  height="16"
                  rx="8"
                  fill="url(#flow-gradient)"
                  initial={{ width: 0 }}
                  animate={{ width: (pipelineProgress / 100) * 440 }}
                  transition={springTransition}
                  opacity={0.5}
                />

                {/* Source agent node */}
                <g>
                  <motion.rect
                    x="8" y="30" width="64" height="60" rx="12"
                    fill={source.color}
                    fillOpacity={currentStep <= 2 ? 0.15 : 0.06}
                    stroke={source.color}
                    strokeOpacity={currentStep <= 2 ? 0.5 : 0.2}
                    strokeWidth="1.5"
                    animate={{ fillOpacity: currentStep <= 2 ? 0.15 : 0.06 }}
                    transition={springTransition}
                  />
                  <text x="40" y="55" textAnchor="middle" fill={source.color} fontSize="10" fontWeight="600">{source.name}</text>
                  <text x="40" y="72" textAnchor="middle" fill="white" fillOpacity="0.35" fontSize="8">Source</text>
                  {currentStep <= 2 && (
                    <motion.circle
                      cx="40" cy="40" r="3"
                      fill={source.color}
                      animate={{ opacity: [0.3, 1, 0.3] }}
                      transition={{ duration: 1.5, repeat: Infinity }}
                    />
                  )}
                </g>

                {/* Archive/distill node in center */}
                <g>
                  <motion.rect
                    x="248" y="24" width="104" height="72" rx="12"
                    fill="#8b5cf6"
                    fillOpacity={currentStep >= 1 && currentStep <= 3 ? 0.15 : 0.04}
                    stroke="#8b5cf6"
                    strokeOpacity={currentStep >= 1 && currentStep <= 3 ? 0.5 : 0.15}
                    strokeWidth="1.5"
                    animate={{
                      fillOpacity: currentStep >= 1 && currentStep <= 3 ? 0.15 : 0.04,
                      strokeOpacity: currentStep >= 1 && currentStep <= 3 ? 0.5 : 0.15,
                    }}
                    transition={springTransition}
                  />
                  <text x="300" y="52" textAnchor="middle" fill="#a78bfa" fontSize="9" fontWeight="600">CASR Archive</text>
                  <text x="300" y="66" textAnchor="middle" fill="white" fillOpacity="0.35" fontSize="8">Extract + Distill</text>
                  {/* Compression indicator */}
                  {currentStep >= 2 && (
                    <motion.text
                      x="300" y="82" textAnchor="middle" fill="#a78bfa" fontSize="8" fontWeight="500"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 0.7 }}
                      transition={springTransition}
                    >
                      93.6% compressed
                    </motion.text>
                  )}
                </g>

                {/* Target agent node */}
                <g>
                  <motion.rect
                    x="528" y="30" width="64" height="60" rx="12"
                    fill={target.color}
                    fillOpacity={currentStep >= 3 ? 0.15 : 0.04}
                    stroke={target.color}
                    strokeOpacity={currentStep >= 3 ? 0.5 : 0.15}
                    strokeWidth="1.5"
                    animate={{
                      fillOpacity: currentStep >= 3 ? 0.15 : 0.04,
                      strokeOpacity: currentStep >= 3 ? 0.5 : 0.15,
                    }}
                    transition={springTransition}
                  />
                  <text x="560" y="55" textAnchor="middle" fill={target.color} fontSize="10" fontWeight="600">{target.name}</text>
                  <text x="560" y="72" textAnchor="middle" fill="white" fillOpacity="0.35" fontSize="8">Target</text>
                  {currentStep >= 4 && (
                    <motion.circle
                      cx="560" cy="40" r="3"
                      fill={target.color}
                      animate={{ opacity: [0.3, 1, 0.3] }}
                      transition={{ duration: 1.5, repeat: Infinity }}
                    />
                  )}
                </g>

                {/* Data particles flowing through pipeline */}
                {currentStep >= 1 && currentStep <= 4 && (
                  <>
                    <motion.circle
                      r="3"
                      fill="url(#flow-gradient)"
                      filter="url(#casr-glow)"
                      animate={{
                        cx: [90, 300, 520],
                        cy: [60, 60, 60],
                        opacity: [0, 1, 0],
                      }}
                      transition={{
                        duration: 2.5,
                        repeat: Infinity,
                        ease: "linear",
                      }}
                    />
                    <motion.circle
                      r="2"
                      fill="url(#flow-gradient)"
                      filter="url(#casr-glow)"
                      animate={{
                        cx: [90, 300, 520],
                        cy: [60, 60, 60],
                        opacity: [0, 0.7, 0],
                      }}
                      transition={{
                        duration: 2.5,
                        repeat: Infinity,
                        ease: "linear",
                        delay: 0.8,
                      }}
                    />
                    <motion.circle
                      r="2"
                      fill="url(#flow-gradient)"
                      filter="url(#casr-glow)"
                      animate={{
                        cx: [90, 300, 520],
                        cy: [60, 60, 60],
                        opacity: [0, 0.6, 0],
                      }}
                      transition={{
                        duration: 2.5,
                        repeat: Infinity,
                        ease: "linear",
                        delay: 1.6,
                      }}
                    />
                  </>
                )}

                {/* Step-specific highlight arrows */}
                {currentStep === 0 && (
                  <motion.path
                    d="M 72 60 L 80 60"
                    stroke={source.color}
                    strokeWidth="2"
                    strokeLinecap="round"
                    initial={{ pathLength: 0 }}
                    animate={{ pathLength: 1 }}
                    transition={{ duration: 0.5 }}
                  />
                )}
                {currentStep === 5 && (
                  <motion.g initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={springTransition}>
                    <circle cx="560" cy="40" r="8" fill="none" stroke="#22c55e" strokeWidth="1.5" strokeOpacity="0.6" />
                    <motion.circle
                      cx="560" cy="40" r="8"
                      fill="none" stroke="#22c55e" strokeWidth="1"
                      animate={{ r: [8, 16], opacity: [0.5, 0] }}
                      transition={{ duration: 1.5, repeat: Infinity }}
                    />
                  </motion.g>
                )}

                {/* Step position indicator */}
                <motion.circle
                  r="5"
                  fill="#8b5cf6"
                  filter="url(#casr-glow)"
                  animate={{
                    cx: 80 + (currentStep / (SCENARIO_STEPS.length - 1)) * 440,
                    cy: 110,
                  }}
                  transition={springTransition}
                />
                <rect x="80" y="108" width="440" height="4" rx="2" fill="white" fillOpacity="0.04" />
              </svg>
            </div>

            {/* ========== Token Counter + Context Window ========== */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Token compression counter */}
              <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 space-y-3">
                <div className="flex items-center gap-2">
                  <Archive className="h-3.5 w-3.5 text-violet-400/70" />
                  <span className="text-[10px] uppercase tracking-wider text-white/40 font-semibold">Token Compression</span>
                </div>

                <div className="space-y-2">
                  {/* Input tokens */}
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] text-white/30">Input</span>
                    <span className="text-sm font-mono text-white/70 tabular-nums">
                      {animatedTokens.toLocaleString()}
                    </span>
                  </div>
                  <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                    <motion.div
                      animate={{ width: `${Math.min((animatedTokens / CONTEXT_WINDOW_MAX) * 100, 100)}%` }}
                      transition={springTransition}
                      className="h-full rounded-full bg-gradient-to-r from-orange-500/60 to-orange-400/40"
                    />
                  </div>

                  {/* Output tokens */}
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] text-white/30">Output</span>
                    <span className="text-sm font-mono text-white/70 tabular-nums">
                      {animatedCompressed.toLocaleString()}
                    </span>
                  </div>
                  <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                    <motion.div
                      animate={{ width: `${Math.min((animatedCompressed / CONTEXT_WINDOW_MAX) * 100, 100)}%` }}
                      transition={springTransition}
                      className="h-full rounded-full bg-gradient-to-r from-emerald-500/60 to-cyan-400/40"
                    />
                  </div>

                  {/* Compression ratio */}
                  <div className="flex items-center justify-between pt-1 border-t border-white/[0.06]">
                    <span className="text-[10px] text-white/30">Compression</span>
                    <motion.span
                      key={compressionRatio}
                      initial={{ opacity: 0.5, scale: 0.95 }}
                      animate={{ opacity: 1, scale: 1 }}
                      className={`text-sm font-mono font-semibold tabular-nums ${
                        compressionRatio > 80 ? 'text-emerald-400' : compressionRatio > 0 ? 'text-amber-400' : 'text-white/40'
                      }`}
                    >
                      {compressionRatio > 0 ? `${compressionRatio}%` : '--'}
                    </motion.span>
                  </div>
                </div>
              </div>

              {/* Context window visualization */}
              <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 space-y-3">
                <div className="flex items-center gap-2">
                  <Layers className="h-3.5 w-3.5 text-cyan-400/70" />
                  <span className="text-[10px] uppercase tracking-wider text-white/40 font-semibold">Target Context Window</span>
                </div>

                {/* Visual context window blocks */}
                <div className="relative h-24 rounded-lg border border-white/[0.06] bg-black/40 overflow-hidden">
                  {/* Grid lines for scale */}
                  {[25, 50, 75].map((pct) => (
                    <div key={pct} className="absolute top-0 bottom-0 border-l border-white/[0.03]" style={{ left: `${pct}%` }} />
                  ))}

                  {/* Context fill */}
                  <motion.div
                    animate={{ width: `${contextFillPct}%` }}
                    transition={springTransition}
                    className="absolute inset-y-0 left-0 bg-gradient-to-r from-cyan-500/20 to-violet-500/20 border-r border-cyan-400/30"
                  >
                    {/* Inner segments showing different context types */}
                    {currentStep >= 4 && (
                      <div className="absolute inset-0 flex">
                        <div className="h-full bg-orange-500/10 border-r border-orange-500/20" style={{ width: '20%' }}>
                          <span className="absolute bottom-0.5 left-0.5 text-[7px] text-orange-300/50">sys</span>
                        </div>
                        <div className="h-full bg-violet-500/10 border-r border-violet-500/20" style={{ width: '50%' }}>
                          <span className="absolute bottom-0.5 left-0.5 text-[7px] text-violet-300/50">task+diffs</span>
                        </div>
                        <div className="h-full bg-emerald-500/10" style={{ width: '30%' }}>
                          <span className="absolute bottom-0.5 left-0.5 text-[7px] text-emerald-300/50">decisions</span>
                        </div>
                      </div>
                    )}
                  </motion.div>

                  {/* Labels */}
                  <div className="absolute top-1.5 left-2 text-[9px] font-mono text-white/30">0K</div>
                  <div className="absolute top-1.5 right-2 text-[9px] font-mono text-white/30">128K</div>
                  <div className="absolute bottom-1.5 left-2 flex items-center gap-1">
                    <span className="text-[9px] font-mono text-cyan-400/60">
                      {contextFillPct > 0 ? `${contextFillPct.toFixed(1)}% used` : 'empty'}
                    </span>
                  </div>
                </div>

                {/* Token budget summary */}
                <div className="flex items-center justify-between text-[10px]">
                  <span className="text-white/30">Handoff uses</span>
                  <span className="font-mono text-cyan-400/70">
                    {animatedCompressed.toLocaleString()} / {CONTEXT_WINDOW_MAX.toLocaleString()} tokens
                  </span>
                </div>
              </div>
            </div>

            {/* ========== Mini Terminal ========== */}
            <div className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
              {/* Terminal header */}
              <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
                <div className="flex gap-1.5">
                  <div className="h-2.5 w-2.5 rounded-full bg-red-500/40" />
                  <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/40" />
                  <div className="h-2.5 w-2.5 rounded-full bg-green-500/40" />
                </div>
                <span className="text-[10px] font-mono text-white/30 ml-2">casr session handoff</span>
                <div className="flex-1" />
                <Terminal className="h-3 w-3 text-white/20" />
              </div>

              {/* Terminal content */}
              <div
                ref={terminalRef}
                className="p-4 font-mono text-xs space-y-0.5 max-h-[180px] overflow-y-auto scrollbar-thin scrollbar-track-transparent scrollbar-thumb-white/10"
              >
                <AnimatePresence mode="popLayout">
                  {step.terminalLines.slice(0, terminalVisibleLines).map((line, i) => {
                    const isCommand = line.startsWith('$');
                    const isResult = line.includes('complete') || line.includes('done') || line.includes('ready') || line.includes('verified') || line.includes('Verified');
                    return (
                      <motion.div
                        key={`${step.id}-${i}`}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ type: "spring", stiffness: 300, damping: 30 }}
                        className={`leading-relaxed ${
                          isCommand
                            ? 'text-emerald-400/80'
                            : isResult
                              ? 'text-cyan-400/70'
                              : 'text-white/40'
                        }`}
                      >
                        {isCommand && <span className="text-violet-400/60">~/project </span>}
                        {line}
                      </motion.div>
                    );
                  })}
                </AnimatePresence>

                {/* Blinking cursor */}
                {terminalVisibleLines < step.terminalLines.length && (
                  <motion.span
                    animate={{ opacity: [1, 0] }}
                    transition={{ duration: 0.8, repeat: Infinity, repeatType: "reverse" }}
                    className="inline-block w-2 h-3.5 bg-white/50 ml-0.5"
                  />
                )}
                {terminalVisibleLines === step.terminalLines.length && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    className="flex items-center gap-1 mt-1 pt-1 border-t border-white/[0.04]"
                  >
                    <CheckCircle2 className="h-3 w-3 text-emerald-400/60" />
                    <span className="text-[10px] text-emerald-400/50">Step complete</span>
                  </motion.div>
                )}
              </div>
            </div>

            {/* ========== Session Context Summary ========== */}
            <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4">
              <div className="flex items-center gap-2 mb-3">
                <FileText className="h-3.5 w-3.5 text-white/40" />
                <span className="text-[10px] uppercase tracking-wider text-white/40 font-semibold">Handoff Payload</span>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                {/* Task */}
                <div className="space-y-1">
                  <span className="text-[9px] uppercase tracking-wider text-white/25 font-medium">Task</span>
                  <motion.p
                    animate={{
                      opacity: currentStep >= 1 ? 1 : 0.3,
                    }}
                    transition={springTransition}
                    className="text-[11px] text-white/60 font-mono leading-snug"
                  >
                    Refactoring auth middleware to support OAuth2 PKCE flow
                  </motion.p>
                </div>

                {/* Files */}
                <div className="space-y-1">
                  <span className="text-[9px] uppercase tracking-wider text-white/25 font-medium">Files ({currentStep >= 1 ? 8 : 0})</span>
                  <div className="flex flex-wrap gap-1">
                    <AnimatePresence>
                      {currentStep >= 1 && ['middleware.ts', 'pkce.ts', 'login.ts'].map((file, i) => (
                        <motion.span
                          key={file}
                          initial={{ opacity: 0, scale: 0.8 }}
                          animate={{ opacity: 1, scale: 1 }}
                          exit={{ opacity: 0, scale: 0.8 }}
                          transition={{ ...springTransition, delay: i * 0.05 }}
                          className="px-1.5 py-0.5 rounded bg-white/[0.04] border border-white/[0.06] text-[9px] text-white/40 font-mono"
                        >
                          {file}
                        </motion.span>
                      ))}
                    </AnimatePresence>
                    {currentStep >= 1 && (
                      <motion.span
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className="px-1.5 py-0.5 rounded bg-white/[0.04] text-[9px] text-white/30"
                      >
                        +5 more
                      </motion.span>
                    )}
                  </div>
                </div>

                {/* Decisions */}
                <div className="space-y-1">
                  <span className="text-[9px] uppercase tracking-wider text-white/25 font-medium">Decisions ({currentStep >= 2 ? 5 : 0})</span>
                  <AnimatePresence>
                    {currentStep >= 2 && (
                      <motion.ul
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        className="space-y-0.5"
                      >
                        {['httpOnly cookie storage', 'Token rotation on use'].map((d, i) => (
                          <motion.li
                            key={d}
                            initial={{ opacity: 0, x: -4 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{ ...springTransition, delay: i * 0.08 }}
                            className="text-[9px] text-white/40 font-mono flex items-center gap-1"
                          >
                            <CheckCircle2 className="h-2.5 w-2.5 text-emerald-400/50 shrink-0" />
                            {d}
                          </motion.li>
                        ))}
                        <motion.li
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          className="text-[9px] text-white/25 font-mono"
                        >
                          +3 more decisions
                        </motion.li>
                      </motion.ul>
                    )}
                  </AnimatePresence>
                </div>
              </div>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* ========== Navigation Controls ========== */}
        <div className="flex items-center justify-between pt-2">
          <motion.button
            onClick={goPrev}
            disabled={currentStep === 0}
            whileHover={currentStep > 0 ? { x: -2 } : {}}
            whileTap={currentStep > 0 ? { scale: 0.95 } : {}}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg border text-xs font-medium transition-colors ${
              currentStep === 0
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-white/[0.12] text-white/60 hover:text-white/80 hover:border-white/[0.2] bg-white/[0.02]'
            }`}
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Previous
          </motion.button>

          <div className="flex items-center gap-1.5">
            {SCENARIO_STEPS.map((_, i) => (
              <button
                key={i}
                onClick={() => goToStep(i)}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  i === currentStep
                    ? 'w-6 bg-violet-400'
                    : i < currentStep
                      ? 'w-1.5 bg-emerald-400/40'
                      : 'w-1.5 bg-white/10'
                }`}
              />
            ))}
          </div>

          <motion.button
            onClick={goNext}
            disabled={currentStep === SCENARIO_STEPS.length - 1}
            whileHover={currentStep < SCENARIO_STEPS.length - 1 ? { x: 2 } : {}}
            whileTap={currentStep < SCENARIO_STEPS.length - 1 ? { scale: 0.95 } : {}}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg border text-xs font-medium transition-colors ${
              currentStep === SCENARIO_STEPS.length - 1
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-violet-500/30 text-violet-300 hover:text-violet-200 hover:border-violet-500/50 bg-violet-500/10'
            }`}
          >
            {currentStep === SCENARIO_STEPS.length - 1 ? 'Complete' : 'Next'}
            <ChevronRight className="h-3.5 w-3.5" />
          </motion.button>
        </div>

        {/* ========== Handoff Timeline / History ========== */}
        <div className="rounded-xl border border-white/[0.08] bg-black/20 p-4 space-y-2">
          <div className="flex items-center gap-2">
            <Clock className="h-3.5 w-3.5 text-white/30" />
            <span className="text-[10px] uppercase tracking-wider text-white/35 font-semibold">Pipeline Timeline</span>
          </div>
          <div className="flex items-center gap-1 overflow-x-auto py-1">
            {SCENARIO_STEPS.map((s, i) => {
              const isActive = i === currentStep;
              const isCompleted = i < currentStep;
              return (
                <div key={s.id} className="flex items-center shrink-0">
                  <motion.div
                    animate={{
                      backgroundColor: isActive ? 'rgba(139, 92, 246, 0.2)' : isCompleted ? 'rgba(34, 197, 94, 0.1)' : 'rgba(255,255,255,0.02)',
                      borderColor: isActive ? 'rgba(139, 92, 246, 0.4)' : isCompleted ? 'rgba(34, 197, 94, 0.2)' : 'rgba(255,255,255,0.06)',
                    }}
                    transition={springTransition}
                    className="flex items-center gap-1 px-2 py-1 rounded-md border text-[9px] font-mono"
                  >
                    {isCompleted ? (
                      <CheckCircle2 className="h-2.5 w-2.5 text-emerald-400/60" />
                    ) : (
                      <span className={isActive ? 'text-violet-400' : 'text-white/20'}>{s.icon}</span>
                    )}
                    <span className={isActive ? 'text-violet-300' : isCompleted ? 'text-emerald-400/60' : 'text-white/25'}>
                      {s.shortLabel}
                    </span>
                  </motion.div>
                  {i < SCENARIO_STEPS.length - 1 && (
                    <ArrowRight className={`h-2.5 w-2.5 mx-0.5 shrink-0 ${isCompleted ? 'text-emerald-400/30' : 'text-white/10'}`} />
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
