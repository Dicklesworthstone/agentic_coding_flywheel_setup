'use client';

import { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Terminal,
  Package,
  Server,
  GitBranch,
  Play,
  Shield,
  Hammer,
  Archive,
  Upload,
  CheckCircle2,
  XCircle,
  Loader2,
  Sparkles,
  Tag,
  ChevronLeft,
  ChevronRight,
  Hash,
  Lock,
  Eye,
  FileCheck,
  Globe,
  Cpu,
  MonitorSmartphone,
  Layers,
  Copy,
  Check,
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
import { copyTextToClipboard } from '@/lib/utils';

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

export function DsrLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Ship releases locally when GitHub Actions is throttled with Doodlestein Self-Releaser.
      </GoalBanner>

      {/* Section 1: What Is DSR */}
      <Section title="What Is DSR?" icon={<Package className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>DSR (Doodlestein Self-Releaser)</Highlight> is fallback release
          infrastructure for when GitHub Actions is throttled or unavailable.
          It builds release artifacts locally using <code>act</code> (local GitHub Actions runner)
          and publishes them directly.
        </Paragraph>
        <Paragraph>
          When CI is backed up or your Actions minutes are exhausted, DSR lets you
          cut a release from your local machine with the same reproducibility as CI.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Server className="h-5 w-5" />}
              title="Local Builds"
              description="Run GitHub Actions workflows locally via act"
              gradient="from-orange-500/20 to-red-500/20"
            />
            <FeatureCard
              icon={<Package className="h-5 w-5" />}
              title="Release Artifacts"
              description="Build and publish release binaries"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<GitBranch className="h-5 w-5" />}
              title="Cross-Platform"
              description="Build for multiple OS targets from one machine"
              gradient="from-green-500/20 to-emerald-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="CI Parity"
              description="Same workflow definitions as your real CI"
              gradient="from-purple-500/20 to-violet-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveReleasePipeline />
      </div>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'dsr release', description: 'Build and publish a release locally' },
            { command: 'dsr build', description: 'Build artifacts without publishing' },
            { command: 'dsr status', description: 'Check release readiness' },
            { command: 'dsr --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          DSR is a safety net, not a replacement for CI. Use it when Actions is down
          or throttled and you need to ship now.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Check if you're ready to release
dsr status

# Build release artifacts locally
dsr build

# Full release: build + tag + publish
dsr release`} />
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Types & Constants
// ---------------------------------------------------------------------------

type PipelinePhase = 'idle' | 'building' | 'verifying' | 'signing' | 'checksums' | 'uploading' | 'publishing' | 'done';

interface ToolScenario {
  id: string;
  label: string;
  icon: typeof Tag;
  toolName: string;
  version: string;
  description: string;
  command: string;
  targets: PlatformTarget[];
  checksumPrefix: string;
}

interface PlatformTarget {
  os: string;
  arch: string;
  label: string;
  icon: typeof Cpu;
  sizeKb: number;
}

const PLATFORM_TARGETS: PlatformTarget[] = [
  { os: 'linux', arch: 'amd64', label: 'linux/amd64', icon: Cpu, sizeKb: 14200 },
  { os: 'linux', arch: 'arm64', label: 'linux/arm64', icon: Cpu, sizeKb: 13800 },
  { os: 'darwin', arch: 'amd64', label: 'darwin/amd64', icon: MonitorSmartphone, sizeKb: 15100 },
  { os: 'darwin', arch: 'arm64', label: 'darwin/arm64', icon: MonitorSmartphone, sizeKb: 14600 },
];

const TOOL_SCENARIOS: ToolScenario[] = [
  {
    id: 'ntm',
    label: 'NTM Release',
    icon: Layers,
    toolName: 'ntm',
    version: 'v2.4.1',
    description: 'Node Tool Manager release with cross-platform binaries',
    command: 'dsr release ntm --version v2.4.1',
    targets: PLATFORM_TARGETS,
    checksumPrefix: 'a3f8c2',
  },
  {
    id: 'ubs',
    label: 'UBS Release',
    icon: Server,
    toolName: 'ubs',
    version: 'v1.8.0',
    description: 'Universal Build System packaging for all platforms',
    command: 'dsr release ubs --version v1.8.0',
    targets: PLATFORM_TARGETS,
    checksumPrefix: 'e7d1b9',
  },
  {
    id: 'bv',
    label: 'BV Release',
    icon: Eye,
    toolName: 'bv',
    version: 'v3.1.2',
    description: 'Build Verifier release with integrity checks',
    command: 'dsr release bv --version v3.1.2',
    targets: PLATFORM_TARGETS.slice(0, 2),
    checksumPrefix: '4b2e7a',
  },
  {
    id: 'cass',
    label: 'CASS Release',
    icon: Shield,
    toolName: 'cass',
    version: 'v4.0.0',
    description: 'CASS Agent Safety System with signed artifacts',
    command: 'dsr release cass --version v4.0.0 --sign',
    targets: PLATFORM_TARGETS,
    checksumPrefix: 'f9c3d5',
  },
  {
    id: 'cm',
    label: 'CM Release',
    icon: Archive,
    toolName: 'cm',
    version: 'v2.2.3',
    description: 'CASS Memory System with incremental update',
    command: 'dsr release cm --version v2.2.3',
    targets: PLATFORM_TARGETS.slice(0, 3),
    checksumPrefix: '8d4f1e',
  },
  {
    id: 'batch',
    label: 'Multi-Tool Batch',
    icon: Globe,
    toolName: 'all',
    version: 'v2025.03',
    description: 'Batch release of all tools in the ACFS suite',
    command: 'dsr release --batch --tag v2025.03',
    targets: PLATFORM_TARGETS,
    checksumPrefix: 'c1a9e6',
  },
];

const PIPELINE_STAGES = [
  { id: 'build', label: 'Build', icon: Hammer, color: 'blue' },
  { id: 'verify', label: 'Verify', icon: FileCheck, color: 'cyan' },
  { id: 'sign', label: 'Sign', icon: Lock, color: 'violet' },
  { id: 'upload', label: 'Upload', icon: Upload, color: 'amber' },
  { id: 'publish', label: 'Publish', icon: Tag, color: 'emerald' },
] as const;

// ---------------------------------------------------------------------------
// Main Interactive Component
// ---------------------------------------------------------------------------

function InteractiveReleasePipeline() {
  const [activeScenario, setActiveScenario] = useState(0);
  const [phase, setPhase] = useState<PipelinePhase>('idle');
  const [isDraft, setIsDraft] = useState(true);
  const [buildProgress, setBuildProgress] = useState<number[]>(() => [0, 0, 0, 0]);
  const [stageProgress, setStageProgress] = useState<number[]>(() => [0, 0, 0, 0, 0]);
  const [checksumRevealed, setChecksumRevealed] = useState(false);
  const [terminalLines, setTerminalLines] = useState<TerminalLine[]>([]);
  const [showConfetti, setShowConfetti] = useState(false);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const intervalsRef = useRef<ReturnType<typeof setInterval>[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);

  const scenario = TOOL_SCENARIOS[activeScenario];

  // Cleanup on unmount
  useEffect(() => {
    const timers = timersRef.current;
    const intervals = intervalsRef.current;

    return () => {
      timers.forEach(clearTimeout);
      intervals.forEach(clearInterval);
    };
  }, []);

  const clearAllTimers = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    intervalsRef.current.forEach(clearInterval);
    timersRef.current.length = 0;
    intervalsRef.current.length = 0;
  }, []);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [terminalLines]);

  const addTerminalLine = useCallback((text: string, type: TerminalLine['type'] = 'output') => {
    setTerminalLines((prev) => [...prev, { text, type, id: Date.now() + Math.random() }]);
  }, []);

  const resetPipeline = useCallback(() => {
    clearAllTimers();
    setPhase('idle');
    setBuildProgress([0, 0, 0, 0]);
    setStageProgress([0, 0, 0, 0, 0]);
    setChecksumRevealed(false);
    setTerminalLines([]);
    setShowConfetti(false);
  }, [clearAllTimers]);

  const handleScenarioChange = useCallback((idx: number) => {
    resetPipeline();
    setActiveScenario(idx);
  }, [resetPipeline]);

  const handlePrev = useCallback(() => {
    const newIdx = activeScenario <= 0 ? TOOL_SCENARIOS.length - 1 : activeScenario - 1;
    handleScenarioChange(newIdx);
  }, [activeScenario, handleScenarioChange]);

  const handleNext = useCallback(() => {
    const newIdx = activeScenario >= TOOL_SCENARIOS.length - 1 ? 0 : activeScenario + 1;
    handleScenarioChange(newIdx);
  }, [activeScenario, handleScenarioChange]);

  const startPipeline = useCallback(() => {
    if (phase !== 'idle' && phase !== 'done') return;
    resetPipeline();

    // Use setTimeout to avoid synchronous state update in the callback scope
    const tStart = setTimeout(() => {
      setPhase('building');
      addTerminalLine(`$ ${scenario.command}`, 'command');
      addTerminalLine(`[dsr] Starting release for ${scenario.toolName} ${scenario.version}`, 'info');
      addTerminalLine(`[dsr] CI is throttled - switching to local build mode`, 'warning');
      addTerminalLine('', 'output');

      // Build phase: animate per-platform progress bars
      const targetCount = scenario.targets.length;
      let completedBuilds = 0;
      scenario.targets.forEach((target, tIdx) => {
        const baseDuration = 800 + tIdx * 400;
        const steps = 25;
        const stepDuration = baseDuration / steps;
        let step = 0;

        addTerminalLine(`[build] Compiling ${scenario.toolName} for ${target.label}...`, 'output');

        const interval = setInterval(() => {
          step++;
          setBuildProgress((prev) => {
            const next = [...prev];
            next[tIdx] = Math.min((step / steps) * 100, 100);
            return next;
          });
          if (step >= steps) {
            clearInterval(interval);
            completedBuilds++;
            addTerminalLine(`[build] ${target.label} done (${target.sizeKb}KB)`, 'success');
            setBuildProgress((prev) => {
              const next = [...prev];
              next[tIdx] = 100;
              return next;
            });

            if (completedBuilds === targetCount) {
              setStageProgress((prev) => {
                const next = [...prev];
                next[0] = 100;
                return next;
              });
              
              const t1 = setTimeout(() => {
                setPhase('signing');
                addTerminalLine(`[sign] Generating Ed25519 signatures...`, 'command');
                addTerminalLine('', 'output');

                // Animate signing progress
                animateStageProgress(1, 1000, () => {
                  addTerminalLine('[sign] Artifacts signed successfully', 'success');
                  const t2 = setTimeout(() => {
                    setPhase('checksums');
                    addTerminalLine(`[checksum] Calculating SHA256 hashes...`, 'command');
                    addTerminalLine('', 'output');

                    animateStageProgress(2, 600, () => {
                      setChecksumRevealed(true);
                      addTerminalLine('[checksum] checksums.yaml updated', 'success');
                      const t3 = setTimeout(() => {
                        setPhase('uploading');
                        addTerminalLine(`[upload] Uploading to GitHub release...`, 'command');
                        addTerminalLine('', 'output');

                        // Upload phase
                        const t4 = setTimeout(() => {
                          setPhase('publishing');
                          addTerminalLine(`[release] Uploading to GitHub Releases...`, 'command');
                          addTerminalLine('', 'output');

                          // Publish phase
                          const t5 = setTimeout(() => {
                            setPhase('done');
                            addTerminalLine(
                              `[publish] ${scenario.toolName} ${scenario.version} ${isDraft ? 'draft' : 'release'} created!`,
                              'success',
                            );
                            addTerminalLine(
                              `[dsr] https://github.com/acfs/${scenario.toolName}/releases/tag/${scenario.version}`,
                              'info',
                            );
                            setShowConfetti(true);
                            const tConfettiEnd = setTimeout(() => {
                              setShowConfetti(false);
                            }, 3000);
                            timersRef.current.push(tConfettiEnd);
                          }, 400);
                          timersRef.current.push(t5);
                        }, 400);
                        timersRef.current.push(t4);
                      }, 400);
                      timersRef.current.push(t3);
                    });
                  }, 400);
                  timersRef.current.push(t2);
                });
              }, 400);
              timersRef.current.push(t1);
            }
          }
        }, stepDuration);
        intervalsRef.current.push(interval);
      });
    }, 50);
    timersRef.current.push(tStart);

    function animateStageProgress(stageIdx: number, duration: number, onComplete: () => void) {
      const steps = 20;
      const stepDuration = duration / steps;
      let step = 0;
      const interval = setInterval(() => {
        step++;
        setStageProgress((prev) => {
          const next = [...prev];
          next[stageIdx] = Math.min((step / steps) * 100, 100);
          return next;
        });
        if (step >= steps) {
          clearInterval(interval);
          onComplete();
        }
      }, stepDuration);
      intervalsRef.current.push(interval);
    }
  }, [phase, scenario, isDraft, addTerminalLine, resetPipeline]);

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-orange-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-indigo-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-violet-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 sm:p-8 space-y-6">
        {/* Header */}
        <div className="text-center">
          <p className="text-sm font-semibold text-white/80">
            Release Pipeline Control Room
          </p>
          <p className="text-xs text-white/50 mt-1">
            Watch DSR build, verify, sign, and publish release artifacts locally
          </p>
        </div>

        {/* CI Throttled indicator */}
        <div className="flex justify-center">
          <div className="flex items-center gap-2 rounded-2xl border border-red-500/30 bg-red-500/[0.08] px-4 py-2">
            <XCircle className="h-4 w-4 text-red-400" />
            <span className="text-xs font-semibold text-red-400 uppercase tracking-wider">
              CI Throttled
            </span>
            <span className="text-[10px] text-red-400/60">
              &mdash; Actions minutes exhausted
            </span>
          </div>
        </div>

        {/* Scenario Stepper */}
        <ScenarioStepper
          scenarios={TOOL_SCENARIOS}
          activeIndex={activeScenario}
          onPrev={handlePrev}
          onNext={handleNext}
          onSelect={handleScenarioChange}
          disabled={phase !== 'idle' && phase !== 'done'}
        />

        {/* Scenario Info Card */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={SPRING}
            className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4"
          >
            <div className="flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-orange-500/20 to-amber-500/20 border border-orange-500/30">
                <scenario.icon className="h-5 w-5 text-orange-400" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-semibold text-white/90">{scenario.label}</span>
                  <span className="rounded-full bg-white/[0.06] border border-white/[0.08] px-2 py-0.5 text-[10px] font-mono text-white/50">
                    {scenario.version}
                  </span>
                </div>
                <p className="text-xs text-white/50 mt-0.5">{scenario.description}</p>
                <div className="mt-2 flex items-center gap-1.5 text-[10px] font-mono text-white/30">
                  <Terminal className="h-3 w-3" />
                  <span className="truncate">{scenario.command}</span>
                </div>
              </div>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Draft/Final Toggle */}
        <DraftFinalToggle isDraft={isDraft} setIsDraft={setIsDraft} disabled={phase !== 'idle' && phase !== 'done'} />

        {/* Main visualization grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Left: SVG Flow Diagram + Build Progress */}
          <div className="space-y-4">
            {/* SVG Pipeline Flow */}
            <ArtifactFlowDiagram phase={phase} stageProgress={stageProgress} isDraft={isDraft} />

            {/* Build progress per platform */}
            <PlatformBuildGrid
              targets={scenario.targets}
              progress={buildProgress}
              phase={phase}
            />
          </div>

          {/* Right: Checksum Verification + Terminal */}
          <div className="space-y-4">
            {/* Checksum Verification */}
            <ChecksumVerification
              targets={scenario.targets}
              checksumPrefix={scenario.checksumPrefix}
              revealed={checksumRevealed}
              phase={phase}
            />

            {/* Mini Terminal */}
            <MiniTerminal lines={terminalLines} terminalRef={terminalRef} />
          </div>
        </div>

        {/* Success banner */}
        <AnimatePresence>
          {phase === 'done' && (
            <motion.div
              initial={{ opacity: 0, scale: 0.9, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={SPRING}
              className="relative mx-auto max-w-sm rounded-2xl border border-emerald-500/30 bg-emerald-500/[0.08] px-6 py-4 text-center overflow-hidden"
            >
              <div className="flex items-center justify-center gap-2">
                <CheckCircle2 className="h-5 w-5 text-emerald-400" />
                <span className="text-sm font-bold text-emerald-300">
                  {scenario.toolName} {scenario.version} {isDraft ? 'Draft' : 'Release'} Published!
                </span>
                <Sparkles className="h-4 w-4 text-emerald-400" />
              </div>
              <p className="text-[10px] text-emerald-400/60 mt-1">
                {scenario.targets.length} platform artifacts built and published locally via DSR
              </p>
              {showConfetti && <ConfettiParticles />}
            </motion.div>
          )}
        </AnimatePresence>

        {/* Controls */}
        <div className="flex justify-center gap-3">
          <motion.button
            type="button"
            onClick={startPipeline}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={SPRING}
            disabled={phase !== 'idle' && phase !== 'done'}
            className={`flex items-center gap-2 rounded-2xl border px-5 py-2.5 text-sm font-medium transition-colors ${
              phase !== 'idle' && phase !== 'done'
                ? 'border-white/[0.06] bg-white/[0.02] text-white/30 cursor-wait'
                : 'border-orange-500/30 bg-orange-500/10 text-orange-300 hover:bg-orange-500/20'
            }`}
          >
            {phase !== 'idle' && phase !== 'done' ? (
              <>
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                >
                  <Loader2 className="h-4 w-4" />
                </motion.div>
                Releasing...
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                {phase === 'done' ? 'Run Again' : 'Start Release'}
              </>
            )}
          </motion.button>

          {phase === 'done' && (
            <motion.button
              type="button"
              onClick={resetPipeline}
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={SPRING}
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.96 }}
              className="flex items-center gap-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 py-2.5 text-sm font-medium text-white/50 hover:text-white/70 transition-colors"
            >
              Reset
            </motion.button>
          )}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Scenario Stepper
// ---------------------------------------------------------------------------

function ScenarioStepper({
  scenarios,
  activeIndex,
  onPrev,
  onNext,
  onSelect,
  disabled,
}: {
  scenarios: ToolScenario[];
  activeIndex: number;
  onPrev: () => void;
  onNext: () => void;
  onSelect: (idx: number) => void;
  disabled: boolean;
}) {
  return (
    <div className="flex items-center justify-center gap-3">
      <motion.button
        type="button"
        onClick={onPrev}
        disabled={disabled}
        whileHover={disabled ? {} : { scale: 1.1 }}
        whileTap={disabled ? {} : { scale: 0.9 }}
        transition={SPRING}
        className="flex h-8 w-8 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 disabled:opacity-30 transition-colors"
      >
        <ChevronLeft className="h-4 w-4" />
      </motion.button>

      <div className="flex items-center gap-1.5">
        {scenarios.map((s, idx) => (
          <motion.button
            key={s.id}
            type="button"
            onClick={() => onSelect(idx)}
            disabled={disabled}
            whileHover={disabled ? {} : { scale: 1.2 }}
            whileTap={disabled ? {} : { scale: 0.9 }}
            transition={SPRING}
            className="relative"
          >
            <div
              className={`h-2 rounded-full transition-all duration-300 ${
                idx === activeIndex
                  ? 'w-6 bg-orange-400'
                  : 'w-2 bg-white/20 hover:bg-white/40'
              }`}
            />
            {idx === activeIndex && (
              <motion.div
                layoutId="stepper-glow"
                className="absolute inset-0 -m-1 rounded-full bg-orange-400/20 blur-sm"
                transition={SPRING}
              />
            )}
          </motion.button>
        ))}
      </div>

      <motion.button
        type="button"
        onClick={onNext}
        disabled={disabled}
        whileHover={disabled ? {} : { scale: 1.1 }}
        whileTap={disabled ? {} : { scale: 0.9 }}
        transition={SPRING}
        className="flex h-8 w-8 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 disabled:opacity-30 transition-colors"
      >
        <ChevronRight className="h-4 w-4" />
      </motion.button>

      <span className="ml-2 text-[10px] font-mono text-white/30">
        {activeIndex + 1}/{scenarios.length}
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Draft/Final Toggle
// ---------------------------------------------------------------------------

function DraftFinalToggle({
  isDraft,
  setIsDraft,
  disabled,
}: {
  isDraft: boolean;
  setIsDraft: (val: boolean) => void;
  disabled: boolean;
}) {
  return (
    <div className="flex items-center justify-center gap-3">
      <span className={`text-xs font-medium transition-colors ${isDraft ? 'text-amber-400' : 'text-white/30'}`}>
        Draft
      </span>
      <motion.button
        type="button"
        onClick={() => setIsDraft(!isDraft)}
        disabled={disabled}
        whileTap={disabled ? {} : { scale: 0.95 }}
        transition={SPRING}
        className={`relative h-6 w-11 rounded-full border transition-colors ${
          isDraft
            ? 'border-amber-500/30 bg-amber-500/20'
            : 'border-emerald-500/30 bg-emerald-500/20'
        } ${disabled ? 'opacity-40' : 'cursor-pointer'}`}
      >
        <motion.div
          className={`absolute top-0.5 h-5 w-5 rounded-full ${isDraft ? 'bg-amber-400' : 'bg-emerald-400'}`}
          animate={{ left: isDraft ? 2 : 20 }}
          transition={SPRING}
        />
      </motion.button>
      <span className={`text-xs font-medium transition-colors ${!isDraft ? 'text-emerald-400' : 'text-white/30'}`}>
        Final
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// SVG Artifact Flow Diagram
// ---------------------------------------------------------------------------

const STAGE_COLORS: Record<string, { fill: string; stroke: string; text: string }> = {
  build: { fill: '#3b82f6', stroke: '#60a5fa', text: '#93c5fd' },
  verify: { fill: '#06b6d4', stroke: '#22d3ee', text: '#67e8f9' },
  sign: { fill: '#8b5cf6', stroke: '#a78bfa', text: '#c4b5fd' },
  upload: { fill: '#f59e0b', stroke: '#fbbf24', text: '#fcd34d' },
  publish: { fill: '#10b981', stroke: '#34d399', text: '#6ee7b7' },
};

function ArtifactFlowDiagram({
  phase,
  stageProgress,
  isDraft,
}: {
  phase: PipelinePhase;
  stageProgress: number[];
  isDraft: boolean;
}) {
  const phaseToStageIndex: Record<PipelinePhase, number> = {
    idle: -1,
    building: 0,
    verifying: 1,
    signing: 2,
    checksums: 2,
    uploading: 3,
    publishing: 4,
    done: 4,
  };
  const activeStageIdx = phaseToStageIndex[phase];

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4">
      <div className="flex items-center gap-2 mb-3">
        <GitBranch className="h-3.5 w-3.5 text-white/40" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
          Artifact Flow
        </span>
      </div>

      <svg viewBox="0 0 500 180" className="w-full" role="img" aria-label="Release pipeline artifact flow diagram">
        {/* Background grid dots */}
        {Array.from({ length: 20 }, (_, i) =>
          Array.from({ length: 8 }, (__, j) => (
            <circle
              key={`grid-${i}-${j}`}
              cx={25 + i * 24}
              cy={20 + j * 22}
              r={0.5}
              fill="rgba(255,255,255,0.05)"
            />
          )),
        )}

        {/* Connection lines between stages */}
        {PIPELINE_STAGES.map((stage, idx) => {
          if (idx === 0) return null;
          const x1 = 30 + (idx - 1) * 95 + 65;
          const x2 = 30 + idx * 95;
          const y = 55;
          const isActive = activeStageIdx >= idx;
          const colors = STAGE_COLORS[stage.id];
          return (
            <g key={`conn-${stage.id}`}>
              <line
                x1={x1}
                y1={y}
                x2={x2}
                y2={y}
                stroke={isActive ? colors.stroke : 'rgba(255,255,255,0.08)'}
                strokeWidth={2}
                strokeDasharray={isActive ? 'none' : '4 4'}
              />
              {isActive && (
                <motion.circle
                  cx={x1}
                  cy={y}
                  r={3}
                  fill={colors.fill}
                  initial={{ cx: x1 }}
                  animate={{ cx: x2 }}
                  transition={{ duration: 0.8, ease: 'easeInOut', repeat: Infinity, repeatDelay: 0.5 }}
                />
              )}
            </g>
          );
        })}

        {/* Stage boxes */}
        {PIPELINE_STAGES.map((stage, idx) => {
          const x = 30 + idx * 95;
          const y = 30;
          const w = 65;
          const h = 50;
          const isComplete = activeStageIdx > idx;
          const isActive = activeStageIdx === idx;
          const colors = STAGE_COLORS[stage.id];
          const progress = stageProgress[idx];

          return (
            <g key={stage.id}>
              {/* Stage background */}
              <rect
                x={x}
                y={y}
                width={w}
                height={h}
                rx={8}
                fill={isActive || isComplete ? `${colors.fill}22` : 'rgba(255,255,255,0.02)'}
                stroke={isActive ? colors.stroke : isComplete ? `${colors.stroke}66` : 'rgba(255,255,255,0.08)'}
                strokeWidth={isActive ? 2 : 1}
              />

              {/* Active glow */}
              {isActive && (
                <rect
                  x={x - 2}
                  y={y - 2}
                  width={w + 4}
                  height={h + 4}
                  rx={10}
                  fill="none"
                  stroke={colors.stroke}
                  strokeWidth={1}
                  opacity={0.3}
                />
              )}

              {/* Progress bar inside box */}
              {(isActive || isComplete) && (
                <rect
                  x={x + 4}
                  y={y + h - 8}
                  width={Math.max(0, (w - 8) * (progress / 100))}
                  height={3}
                  rx={1.5}
                  fill={colors.fill}
                  opacity={0.7}
                />
              )}

              {/* Stage label */}
              <text
                x={x + w / 2}
                y={y + 22}
                textAnchor="middle"
                fontSize={9}
                fontWeight={600}
                fill={isActive || isComplete ? colors.text : 'rgba(255,255,255,0.3)'}
              >
                {stage.label}
              </text>

              {/* Status indicator */}
              {isComplete && (
                <circle cx={x + w / 2} cy={y + 36} r={5} fill={colors.fill} opacity={0.8} />
              )}
              {isComplete && (
                <text x={x + w / 2} y={y + 39} textAnchor="middle" fontSize={7} fill="white" fontWeight={700}>
                  &#10003;
                </text>
              )}
              {isActive && (
                <circle cx={x + w / 2} cy={y + 36} r={4} fill="none" stroke={colors.stroke} strokeWidth={1.5}>
                  <animate attributeName="r" values="3;5;3" dur="1.5s" repeatCount="indefinite" />
                  <animate attributeName="opacity" values="1;0.4;1" dur="1.5s" repeatCount="indefinite" />
                </circle>
              )}
            </g>
          );
        })}

        {/* Source label */}
        <text x={30} y={105} fontSize={8} fill="rgba(255,255,255,0.35)" fontWeight={500}>Local Machine</text>
        <rect x={30} y={110} width={80} height={30} rx={6} fill="rgba(255,255,255,0.03)" stroke="rgba(255,255,255,0.08)" strokeWidth={1} />
        <text x={70} y={129} textAnchor="middle" fontSize={8} fill="rgba(255,255,255,0.4)" fontFamily="monospace">act runner</text>

        {/* Arrow from source to pipeline */}
        <line x1={110} y1={125} x2={160} y2={125} stroke="rgba(255,255,255,0.1)" strokeWidth={1} strokeDasharray="3 3" />
        <line x1={160} y1={125} x2={160} y2={80} stroke="rgba(255,255,255,0.1)" strokeWidth={1} strokeDasharray="3 3" />

        {/* Destination label */}
        <text x={345} y={105} fontSize={8} fill="rgba(255,255,255,0.35)" fontWeight={500}>GitHub Release</text>
        <rect x={345} y={110} width={120} height={30} rx={6} fill={phase === 'done' ? 'rgba(16,185,129,0.08)' : 'rgba(255,255,255,0.03)'} stroke={phase === 'done' ? 'rgba(52,211,153,0.3)' : 'rgba(255,255,255,0.08)'} strokeWidth={1} />
        <text x={405} y={129} textAnchor="middle" fontSize={8} fill={phase === 'done' ? 'rgba(110,231,183,0.8)' : 'rgba(255,255,255,0.4)'} fontFamily="monospace">
          {isDraft ? 'draft release' : 'final release'}
        </text>

        {/* Arrow from pipeline to destination */}
        <line x1={410} y1={80} x2={410} y2={110} stroke="rgba(255,255,255,0.1)" strokeWidth={1} strokeDasharray="3 3" />

        {/* Phase indicator text */}
        <text x={250} y={170} textAnchor="middle" fontSize={9} fill="rgba(255,255,255,0.25)" fontWeight={500}>
          {phase === 'idle' && 'Ready to release'}
          {phase === 'building' && 'Building artifacts...'}
          {phase === 'verifying' && 'Verifying checksums...'}
          {phase === 'checksums' && 'Calculating checksums...'}
          {phase === 'signing' && 'Signing with GPG...'}
          {phase === 'uploading' && 'Uploading to GitHub...'}
          {phase === 'publishing' && 'Creating release...'}
          {phase === 'done' && 'Release complete!'}
        </text>
      </svg>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Platform Build Grid
// ---------------------------------------------------------------------------

function PlatformBuildGrid({
  targets,
  progress,
  phase,
}: {
  targets: PlatformTarget[];
  progress: number[];
  phase: PipelinePhase;
}) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4">
      <div className="flex items-center gap-2 mb-3">
        <Hammer className="h-3.5 w-3.5 text-white/40" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
          Build Targets
        </span>
      </div>

      <div className="space-y-2">
        {targets.map((target, idx) => {
          const pct = progress[idx] || 0;
          const isComplete = pct >= 100;
          const isBuilding = phase === 'building' && pct > 0 && pct < 100;
          const TargetIcon = target.icon;

          return (
            <motion.div
              key={target.label}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ ...SPRING, delay: idx * 0.05 }}
              className="group"
            >
              <div className="flex items-center gap-2">
                <TargetIcon className={`h-3 w-3 ${isComplete ? 'text-emerald-400' : isBuilding ? 'text-blue-400' : 'text-white/30'}`} />
                <span className="text-[10px] font-mono text-white/60">{target.label}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[10px] font-mono text-white/30">
                  {isComplete ? `${target.sizeKb}KB` : isBuilding ? `${Math.round(pct)}%` : '--'}
                </span>
                {isComplete && (
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={SPRING}
                  >
                    <CheckCircle2 className="h-3 w-3 text-emerald-400" />
                  </motion.div>
                )}
                {isBuilding && (
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                  >
                    <Loader2 className="h-3 w-3 text-blue-400" />
                  </motion.div>
                )}
              </div>

              {/* Progress bar */}
              <div className="h-1 w-full rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${
                    isComplete
                      ? 'bg-emerald-500/60'
                      : 'bg-blue-500/60'
                  }`}
                  initial={{ width: '0%' }}
                  animate={{ width: `${pct}%` }}
                  transition={{ duration: 0.1, ease: 'linear' }}
                />
              </div>
            </motion.div>
          );
        })}

        {/* Empty slots for scenarios with fewer targets */}
        {targets.length < 4 && (
          <div className="pt-1">
            {Array.from({ length: 4 - targets.length }, (_, i) => (
              <div key={`empty-${i}`} className="flex items-center gap-2 py-1 opacity-30">
                <Cpu className="h-3 w-3 text-white/20" />
                <span className="text-[10px] font-mono text-white/20">--/--</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Checksum Verification
// ---------------------------------------------------------------------------

function ChecksumVerification({
  targets,
  checksumPrefix,
  revealed,
  phase,
}: {
  targets: PlatformTarget[];
  checksumPrefix: string;
  revealed: boolean;
  phase: PipelinePhase;
}) {
  const isVerifying = phase === 'verifying';
  const isVerified = phase !== 'idle' && phase !== 'building' && phase !== 'verifying';

  // Generate stable per-target hashes from the prefix
  const hashes = useMemo(() =>
    targets.map((t, i) => {
      const seed = checksumPrefix + t.label + i;
      let hash = '';
      for (let j = 0; j < 64; j++) {
        const code = seed.charCodeAt(j % seed.length);
        hash += ((code * (j + 7) * (i + 3)) % 16).toString(16);
      }
      return hash;
    }),
  [targets, checksumPrefix]);

  const [copiedIdx, setCopiedIdx] = useState<number | null>(null);
  const copyResetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (copyResetTimerRef.current) {
        clearTimeout(copyResetTimerRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async (hash: string, idx: number) => {
    const copiedOk = await copyTextToClipboard(hash);
    if (!copiedOk) {
      return;
    }
    setCopiedIdx(idx);
    if (copyResetTimerRef.current) {
      clearTimeout(copyResetTimerRef.current);
    }
    copyResetTimerRef.current = setTimeout(() => {
      setCopiedIdx(null);
      copyResetTimerRef.current = null;
    }, 1500);
  }, []);

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4">
      <div className="flex items-center gap-2 mb-3">
        <Hash className="h-3.5 w-3.5 text-white/40" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
          SHA-256 Checksums
        </span>
        {isVerified && (
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING}
            className="ml-auto flex items-center gap-1 text-[10px] text-emerald-400 font-mono"
          >
            <CheckCircle2 className="h-3 w-3" />
            verified
          </motion.span>
        )}
        {isVerifying && (
          <motion.span
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="ml-auto flex items-center gap-1 text-[10px] text-cyan-400 font-mono"
          >
            <motion.div animate={{ rotate: 360 }} transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}>
              <Loader2 className="h-3 w-3" />
            </motion.div>
            verifying
          </motion.span>
        )}
      </div>

      <div className="space-y-2">
        {targets.map((target, idx) => (
          <motion.div
            key={target.label}
            initial={{ opacity: 0 }}
            animate={{ opacity: revealed ? 1 : 0.3 }}
            transition={{ duration: 0.3, delay: idx * 0.1 }}
            className="group"
          >
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-mono text-white/40 w-24 shrink-0 truncate">
                {target.label}
              </span>
              <div className={`flex-1 font-mono text-[9px] leading-tight truncate transition-colors ${
                isVerified ? 'text-emerald-400/70' : isVerifying ? 'text-cyan-400/60' : 'text-white/25'
              }`}>
                {revealed ? hashes[idx] : '•'.repeat(64)}
              </div>
              {revealed && (
                <button
                  type="button"
                  onClick={() => handleCopy(hashes[idx], idx)}
                  className="shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  {copiedIdx === idx ? (
                    <Check className="h-3 w-3 text-emerald-400" />
                  ) : (
                    <Copy className="h-3 w-3 text-white/30 hover:text-white/60" />
                  )}
                </button>
              )}
            </div>

            {/* Verification animation bar */}
            {isVerifying && (
              <motion.div
                className="mt-1 h-px bg-gradient-to-r from-cyan-400/40 via-cyan-400/80 to-cyan-400/40"
                initial={{ scaleX: 0, originX: 0 }}
                animate={{ scaleX: 1 }}
                transition={{ duration: 1.2, delay: idx * 0.2, ease: 'easeInOut' }}
              />
            )}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Mini Terminal
// ---------------------------------------------------------------------------

interface TerminalLine {
  text: string;
  type: 'command' | 'output' | 'info' | 'success' | 'warning' | 'error';
  id: number;
}

const TERMINAL_LINE_COLORS: Record<TerminalLine['type'], string> = {
  command: 'text-cyan-300',
  output: 'text-white/50',
  info: 'text-blue-400',
  success: 'text-emerald-400',
  warning: 'text-amber-400',
  error: 'text-red-400',
};

function MiniTerminal({
  lines,
  terminalRef,
}: {
  lines: TerminalLine[];
  terminalRef: React.RefObject<HTMLDivElement | null>;
}) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-black/40 overflow-hidden">
      {/* Terminal header */}
      <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex items-center gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
        </div>
        <span className="text-[10px] font-mono text-white/30 ml-2">dsr-terminal</span>
      </div>

      {/* Terminal content */}
      <div
        ref={terminalRef}
        className="h-48 overflow-y-auto p-3 scrollbar-thin scrollbar-thumb-white/10 scrollbar-track-transparent"
      >
        {lines.length === 0 && (
          <div className="flex items-center gap-2 text-white/20">
            <Terminal className="h-3 w-3" />
            <span className="text-[10px] font-mono">Waiting for release command...</span>
          </div>
        )}

        <AnimatePresence initial={false}>
          {lines.map((line) => (
            <motion.div
              key={line.id}
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15 }}
              className={`font-mono text-[10px] leading-relaxed ${TERMINAL_LINE_COLORS[line.type]}`}
            >
              {line.text === '' ? (
                <br />
              ) : (
                line.text
              )}
            </motion.div>
          ))}
        </AnimatePresence>

        {/* Blinking cursor */}
        {lines.length > 0 && (
          <motion.span
            className="inline-block h-3 w-1.5 bg-cyan-400/60"
            animate={{ opacity: [1, 0] }}
            transition={{ duration: 0.8, repeat: Infinity, ease: 'linear' }}
          />
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Confetti Particles
// ---------------------------------------------------------------------------

const CONFETTI_COLORS = [
  'bg-emerald-400', 'bg-green-400', 'bg-teal-400',
  'bg-blue-400', 'bg-violet-400', 'bg-amber-400',
  'bg-rose-400', 'bg-orange-400',
];

function ConfettiParticles() {
  const [particles] = useState(() =>
    Array.from({ length: 30 }, (_, i) => ({
      id: i,
      x: (Math.random() - 0.5) * 320,
      y: -(Math.random() * 140 + 40),
      rotate: Math.random() * 720 - 360,
      scale: Math.random() * 0.7 + 0.3,
      color: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
      delay: Math.random() * 0.4,
    })),
  );

  return (
    <div className="absolute inset-0 pointer-events-none overflow-hidden">
      {particles.map((p) => (
        <motion.div
          key={p.id}
          className={`absolute left-1/2 top-1/2 h-1.5 w-1.5 rounded-full ${p.color}`}
          initial={{ x: 0, y: 0, scale: 0, rotate: 0, opacity: 1 }}
          animate={{
            x: p.x,
            y: p.y,
            scale: p.scale,
            rotate: p.rotate,
            opacity: 0,
          }}
          transition={{
            duration: 1.6,
            delay: p.delay,
            ease: [0.22, 1, 0.36, 1],
          }}
        />
      ))}
    </div>
  );
}
