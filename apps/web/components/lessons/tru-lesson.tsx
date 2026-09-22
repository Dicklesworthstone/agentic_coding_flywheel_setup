"use client";

import {
  ArrowRight,
  BarChart3,
  Braces,
  ChevronLeft,
  ChevronRight,
  Component,
  Database,
  FileCode,
  Gauge,
  Minimize2,
  Play,
  RotateCcw,
  Settings,
  Shield,
  Sparkles,
  Terminal,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion, useInView } from "@/components/motion";
import {
  CodeBlock,
  CommandList,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

function InteractiveTokenCompressor() {
  return <InteractiveTokenCompressorImpl />;
}

export function TruLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Hand agents structured data as TOON instead of JSON so the same records cost fewer tokens.
      </GoalBanner>

      {/* Section 1: What Is TRU */}
      <Section title="What Is TRU?" icon={<Minimize2 className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>TRU (toon_rust)</Highlight> is a fast Rust implementation of{" "}
          <Highlight>TOON</Highlight>, Token-Optimized Object Notation: a data format that carries
          the same information as JSON with far fewer of the quotes, braces, brackets and commas
          that LLM tokenizers charge you for. The <code>toon</code> binary encodes JSON to TOON and
          decodes TOON back to JSON.
        </Paragraph>
        <Paragraph>
          It is a serialization format, not a source-code minifier. Feed it API responses, search
          results, config files, session exports and other structured data. Uniform arrays of
          objects benefit most: TOON writes them as one header row plus one CSV-like line per
          record, which is where the 40-60% token savings come from.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Minimize2 className="h-5 w-5" />}
              title="Fewer Tokens"
              description="Tabular data shrinks 40-60%"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Braces className="h-5 w-5" />}
              title="JSON In, JSON Out"
              description="Encode and decode, spec-first"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Token Estimates"
              description="--stats shows before/after"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Rust Speed"
              description="Native binary, streaming decode"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveTokenCompressor />
      </div>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Point <code>toon</code> at a file. A <code>.json</code> input is encoded, a{" "}
          <code>.toon</code> input is decoded, and stdin is encoded unless you pass{" "}
          <code>--decode</code>.
        </Paragraph>

        <CodeBlock
          code={`# Encode JSON to TOON (stdout)
toon users.json

# Decode TOON back to JSON
toon users.toon

# See the token estimate for the conversion
toon --stats users.json
# Token estimates: ~55 (JSON) → ~24 (TOON)
# Saved ~31 tokens (-56.4%)

# Pipe from a command that emits JSON
gh issue list --json number,title,state | toon --encode`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Use <code>--stats</code> before you commit to TOON for a given payload. Flat records and
          tables save the most; deeply nested objects with unique keys save the least.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: "toon <file.json>", description: "Encode JSON to TOON (auto-detected)" },
            { command: "toon <file.toon>", description: "Decode TOON back to JSON" },
            { command: "toon --stats <file.json>", description: "Encode and print token estimates" },
            { command: "toon <in> -o <out>", description: "Write the result to a file" },
            {
              command: "toon --key-folding safe <file.json>",
              description: "Collapse chains of single-key objects (a.b.c:)",
            },
            {
              command: "toon --delimiter tab <file.json>",
              description: "Use tabs in tabular rows (often fewer tokens)",
            },
            { command: "toon --help", description: "Show all available options" },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 4: How It Works */}
      <Section title="How It Works" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          TOON keeps JSON&apos;s data model and drops its punctuation. Objects become indented
          key-value lines, arrays declare their length up front, and arrays of uniform objects
          become a header row followed by one row per record.
        </Paragraph>

        <CodeBlock
          code={`# JSON (55 tokens)
{
  "users": [
    { "id": 1, "name": "Alice", "role": "admin", "active": true },
    { "id": 2, "name": "Bob", "role": "user", "active": false },
    { "id": 3, "name": "Carol", "role": "user", "active": true },
    { "id": 4, "name": "Dave", "role": "viewer", "active": true }
  ]
}

# TOON (24 tokens)
users[4]{id,name,role,active}:
  1,Alice,admin,true
  2,Bob,user,false
  3,Carol,user,true
  4,Dave,viewer,true`}
          filename="JSON vs TOON"
        />

        <TipBox variant="info">
          The array length and the field header let a model (or the decoder) know exactly how many
          records follow and what each column means, so nothing is lost even though every quote
          and brace is gone. Values that contain delimiters or colons are quoted automatically.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Anything in the flywheel that emits JSON can hand it to <code>toon</code> before it lands
          in an agent&apos;s context.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">TRU + CASS</span>
            <p className="text-white/80 text-sm mt-1">
              Encode <code>cass search --json</code> results before quoting them to an agent
            </p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">TRU + UBS</span>
            <p className="text-white/80 text-sm mt-1">
              UBS can emit its findings as TOON directly (it uses <code>toon</code> under the hood)
            </p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">TRU + ACFS doctor</span>
            <p className="text-white/80 text-sm mt-1">
              <code>acfs doctor --toon</code> prints the health report in TOON for agents
            </p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">TRU + gh / jq</span>
            <p className="text-white/80 text-sm mt-1">
              Pipe issue lists, PR metadata and CI payloads through <code>toon</code> in scripts
            </p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Token Compression Laboratory
// ---------------------------------------------------------------------------

interface CodeSample {
  id: string;
  lang: string;
  label: string;
  icon: React.ReactNode;
  original: string;
  compressed: string;
  originalTokens: number;
  compressedTokens: number;
  color: string;
  gradient: string;
}

// Outputs and token estimates below come from `toon --stats` (toon_rust 0.2.4).
const CODE_SAMPLES: CodeSample[] = [
  {
    id: "users-table",
    lang: "JSON",
    label: "Array of records",
    icon: <Database className="h-3.5 w-3.5" />,
    color: "text-blue-400",
    gradient: "from-blue-500/20 to-cyan-500/20",
    original: `{
  "users": [
    { "id": 1, "name": "Alice", "role": "admin", "active": true },
    { "id": 2, "name": "Bob", "role": "user", "active": false },
    { "id": 3, "name": "Carol", "role": "user", "active": true },
    { "id": 4, "name": "Dave", "role": "viewer", "active": true }
  ]
}`,
    compressed: `users[4]{id,name,role,active}:
  1,Alice,admin,true
  2,Bob,user,false
  3,Carol,user,true
  4,Dave,viewer,true`,
    originalTokens: 55,
    compressedTokens: 24,
  },
  {
    id: "search-results",
    lang: "JSON",
    label: "Search results",
    icon: <FileCode className="h-3.5 w-3.5" />,
    color: "text-emerald-400",
    gradient: "from-emerald-500/20 to-teal-500/20",
    original: `{
  "query": "flaky tests",
  "total": 3,
  "results": [
    { "file": "tests/api_test.rs", "line": 88, "score": 0.92, "snippet": "retry until the mock server answers" },
    { "file": "tests/db_test.rs", "line": 14, "score": 0.81, "snippet": "sleep(2) before assert" },
    { "file": "tests/ui_test.rs", "line": 203, "score": 0.77, "snippet": "flaky: depends on wall clock" }
  ]
}`,
    compressed: `query: flaky tests
total: 3
results[3]{file,line,score,snippet}:
  tests/api_test.rs,88,0.92,retry until the mock server answers
  tests/db_test.rs,14,0.81,sleep(2) before assert
  tests/ui_test.rs,203,0.77,"flaky: depends on wall clock"`,
    originalTokens: 78,
    compressedTokens: 53,
  },
  {
    id: "service-config",
    lang: "JSON",
    label: "Nested config",
    icon: <Component className="h-3.5 w-3.5" />,
    color: "text-violet-400",
    gradient: "from-violet-500/20 to-purple-500/20",
    original: `{
  "service": "billing-api",
  "env": "production",
  "database": {
    "host": "db.internal",
    "port": 5432,
    "pool": { "min": 2, "max": 16 }
  },
  "cache": {
    "host": "redis.internal",
    "ttlSeconds": 3600
  },
  "features": ["invoices", "refunds", "webhooks"]
}`,
    compressed: `service: billing-api
env: production
database:
  host: db.internal
  port: 5432
  pool:
    min: 2
    max: 16
cache:
  host: redis.internal
  ttlSeconds: 3600
features[3]: invoices,refunds,webhooks`,
    originalTokens: 53,
    compressedTokens: 40,
  },
];

// ---------------------------------------------------------------------------
// Animated token counter display
// ---------------------------------------------------------------------------
function AnimatedCounter({
  value,
  duration = 1.2,
  className,
}: {
  value: number;
  duration?: number;
  className?: string;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const from = prevRef.current;
    const to = value;
    prevRef.current = value;
    if (from === to) return;

    const start = performance.now();
    const ms = duration * 1000;

    function tick(now: number) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / ms, 1);
      // Ease-out cubic
      const eased = 1 - (1 - progress) ** 3;
      const current = Math.round(from + (to - from) * eased);
      setDisplay(current);
      if (progress < 1) {
        rafRef.current = requestAnimationFrame(tick);
      }
    }

    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
  }, [value, duration]);

  return <span className={className}>{display.toLocaleString()}</span>;
}

// ---------------------------------------------------------------------------
// Compression gauge / dial
// ---------------------------------------------------------------------------
function CompressionGauge({ percentage, isActive }: { percentage: number; isActive: boolean }) {
  const radius = 52;
  const stroke = 8;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percentage / 100) * circumference;

  return (
    <div className="relative flex items-center justify-center">
      <svg width="130" height="130" viewBox="0 0 130 130" className="-rotate-90">
        {/* Background arc */}
        <circle
          cx="65"
          cy="65"
          r={radius}
          fill="none"
          stroke="rgba(255,255,255,0.06)"
          strokeWidth={stroke}
          strokeLinecap="round"
        />
        {/* Active arc */}
        <motion.circle
          cx="65"
          cy="65"
          r={radius}
          fill="none"
          stroke="url(#gaugeGradient)"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{
            strokeDashoffset: isActive ? offset : circumference,
          }}
          transition={{ type: "spring", stiffness: 40, damping: 15, delay: 0.3 }}
        />
        <defs>
          <linearGradient id="gaugeGradient" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#34d399" />
            <stop offset="50%" stopColor="#22d3ee" />
            <stop offset="100%" stopColor="#818cf8" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <AnimatePresence mode="wait">
          {isActive ? (
            <motion.div
              key="active"
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.5 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="text-center"
            >
              <span className="text-2xl font-bold font-mono text-emerald-400">{percentage}%</span>
              <p className="text-[10px] text-white/40 uppercase tracking-wider mt-0.5">reduced</p>
            </motion.div>
          ) : (
            <motion.div
              key="idle"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="text-center"
            >
              <Gauge className="h-6 w-6 text-white/20 mx-auto" />
              <p className="text-[10px] text-white/30 mt-1">Ratio</p>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Context window savings bar
// ---------------------------------------------------------------------------
function ContextWindowBar({
  originalTokens,
  savedTokens,
  isActive,
}: {
  originalTokens: number;
  savedTokens: number;
  isActive: boolean;
}) {
  const contextWindowSize = 128000;
  const recoveredPct = (savedTokens / contextWindowSize) * 100;
  const usedPct = (originalTokens / contextWindowSize) * 100;

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[10px]">
        <span className="text-white/50 uppercase tracking-wider font-semibold">
          128k Context Window
        </span>
        <AnimatePresence mode="wait">
          {isActive && (
            <motion.span
              initial={{ opacity: 0, x: 10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 10 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="text-emerald-400 font-mono"
            >
              +{savedTokens.toLocaleString()} tokens recovered
            </motion.span>
          )}
        </AnimatePresence>
      </div>
      <div className="relative h-6 rounded-full bg-white/[0.04] border border-white/[0.06] overflow-hidden">
        {/* Used portion */}
        <motion.div
          className="absolute inset-y-0 left-0 rounded-full bg-white/[0.08]"
          initial={{ width: `${usedPct}%` }}
          animate={{ width: `${usedPct}%` }}
        />
        {/* Recovered portion - glowing */}
        <AnimatePresence>
          {isActive && (
            <motion.div
              className="absolute inset-y-0 rounded-full"
              style={{ left: `${usedPct - recoveredPct}%` }}
              initial={{ width: 0, opacity: 0 }}
              animate={{ width: `${recoveredPct}%`, opacity: 1 }}
              exit={{ width: 0, opacity: 0 }}
              transition={{ type: "spring", stiffness: 60, damping: 18, delay: 0.5 }}
            >
              <div className="h-full rounded-full bg-gradient-to-r from-emerald-500/40 to-cyan-500/40 shadow-[0_0_20px_rgba(52,211,153,0.3)]" />
            </motion.div>
          )}
        </AnimatePresence>
        {/* Scale marks */}
        <div className="absolute inset-0 flex items-center justify-between px-1">
          {[0, 25, 50, 75, 100].map((mark) => (
            <div key={mark} className="w-px h-2 bg-white/[0.08]" />
          ))}
        </div>
      </div>
      <div className="flex justify-between text-[10px] text-white/30 font-mono">
        <span>0</span>
        <span>32k</span>
        <span>64k</span>
        <span>96k</span>
        <span>128k</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Particle burst effect
// ---------------------------------------------------------------------------
function ParticleBurst({ isActive }: { isActive: boolean }) {
  const [particles] = useState(() =>
    Array.from({ length: 12 }, (_, i) => ({
      id: i,
      angle: (i / 12) * 360,
      distance: 30 + ((i * 7 + 3) % 11) * 4,
      size: 2 + ((i * 3 + 1) % 5) * 0.6,
      delay: ((i * 5 + 2) % 12) * 0.025,
      duration: 0.6 + ((i * 4 + 1) % 10) * 0.04,
    })),
  );

  return (
    <AnimatePresence>
      {isActive &&
        particles.map((p) => {
          const rad = (p.angle * Math.PI) / 180;
          const x = Math.cos(rad) * p.distance;
          const y = Math.sin(rad) * p.distance;
          return (
            <motion.div
              key={p.id}
              className="absolute rounded-full bg-emerald-400"
              style={{
                width: p.size,
                height: p.size,
                left: "50%",
                top: "50%",
              }}
              initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
              animate={{ x, y, opacity: 0, scale: 0 }}
              exit={{ opacity: 0 }}
              transition={{
                duration: p.duration,
                delay: p.delay,
                ease: "easeOut",
              }}
            />
          );
        })}
    </AnimatePresence>
  );
}

// ---------------------------------------------------------------------------
// Compression phase indicator
// ---------------------------------------------------------------------------
type CompressionPhase = "idle" | "scanning" | "tokenizing" | "compressing" | "optimizing" | "done";

const PHASE_CONFIG: Record<CompressionPhase, { label: string; color: string }> = {
  idle: { label: "Ready", color: "text-white/40" },
  scanning: { label: "Parsing JSON...", color: "text-blue-400" },
  tokenizing: { label: "Detecting uniform arrays...", color: "text-cyan-400" },
  compressing: { label: "Dropping quotes and braces...", color: "text-violet-400" },
  optimizing: { label: "Writing tabular rows...", color: "text-amber-400" },
  done: { label: "Encoded to TOON", color: "text-emerald-400" },
};

function PhaseIndicator({ phase, active }: { phase: CompressionPhase; active: boolean }) {
  const config = PHASE_CONFIG[phase];
  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={phase}
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -6 }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
        className={`flex items-center gap-2 text-xs font-medium ${config.color}`}
      >
        {phase !== "idle" && phase !== "done" && (
          <motion.div
            animate={active ? { rotate: 360 } : { rotate: 0 }}
            transition={
              active ? { duration: 1, repeat: Infinity, ease: "linear" } : { duration: 0.2 }
            }
          >
            <Minimize2 className="h-3 w-3" />
          </motion.div>
        )}
        {phase === "done" && <Sparkles className="h-3 w-3" />}
        <span>{config.label}</span>
      </motion.div>
    </AnimatePresence>
  );
}

// ---------------------------------------------------------------------------
// Token highlight overlay for original code
// ---------------------------------------------------------------------------
function HighlightedCode({ code, phase }: { code: string; phase: CompressionPhase }) {
  const lines = code.split("\n");
  const isScanning = phase === "scanning" || phase === "tokenizing";
  const isCompressing = phase === "compressing" || phase === "optimizing";

  return (
    <pre className="p-4 text-xs font-mono leading-relaxed overflow-x-auto max-h-72 overflow-y-auto">
      {lines.map((line, lineIdx) => (
        <div key={lineIdx} className="relative">
          <motion.span
            animate={{
              color: isCompressing ? "rgba(255,255,255,0.3)" : "rgba(255,255,255,0.7)",
            }}
            transition={{ duration: 0.4 }}
          >
            {line}
          </motion.span>
          {/* Scan line effect */}
          <AnimatePresence>
            {isScanning && (
              <motion.div
                className="absolute inset-0 bg-blue-400/[0.06] rounded"
                initial={{ opacity: 0 }}
                animate={{ opacity: [0, 1, 0] }}
                exit={{ opacity: 0 }}
                transition={{
                  duration: 0.6,
                  delay: lineIdx * 0.05,
                  repeat: 0,
                }}
              />
            )}
          </AnimatePresence>
          {line === "" && "\n"}
        </div>
      ))}
    </pre>
  );
}

// ---------------------------------------------------------------------------
// Main Interactive Token Compressor Implementation
// ---------------------------------------------------------------------------
function InteractiveTokenCompressorImpl() {
  const [selectedSample, setSelectedSample] = useState(0);
  const [phase, setPhase] = useState<CompressionPhase>("idle");
  const [displayedTokens, setDisplayedTokens] = useState(0);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const [showParticles, setShowParticles] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const sample = CODE_SAMPLES[selectedSample];
  const isCompressed = phase === "done";
  const isRunning = phase !== "idle" && phase !== "done";

  const reductionPct = useMemo(
    () => Math.round((1 - sample.compressedTokens / sample.originalTokens) * 100),
    [sample],
  );

  const savedTokens = useMemo(() => sample.originalTokens - sample.compressedTokens, [sample]);

  const clearTimers = useCallback(() => {
    for (const t of timersRef.current) clearTimeout(t);
    timersRef.current = [];
  }, []);

  const handleCompress = useCallback(() => {
    if (isRunning) return;
    clearTimers();
    setPhase("idle");
    setDisplayedTokens(sample.originalTokens);
    setShowParticles(false);

    // Phase sequence with delays
    const schedule = (fn: () => void, ms: number) => {
      const t = setTimeout(fn, ms);
      timersRef.current.push(t);
    };

    schedule(() => setPhase("scanning"), 50);
    schedule(() => setPhase("tokenizing"), 600);
    schedule(() => {
      setPhase("compressing");
      setDisplayedTokens(Math.round(sample.originalTokens * 0.7));
    }, 1200);
    schedule(() => {
      setPhase("optimizing");
      setDisplayedTokens(Math.round(sample.originalTokens * 0.4));
    }, 1900);
    schedule(() => {
      setPhase("done");
      setDisplayedTokens(sample.compressedTokens);
      setShowParticles(true);
    }, 2500);
    schedule(() => setShowParticles(false), 3500);
  }, [clearTimers, isRunning, sample]);

  const handleReset = useCallback(() => {
    clearTimers();
    setPhase("idle");
    setDisplayedTokens(0);
    setShowParticles(false);
  }, [clearTimers]);

  const handleSelectSample = useCallback(
    (idx: number) => {
      clearTimers();
      setSelectedSample(idx);
      setPhase("idle");
      setDisplayedTokens(0);
      setShowParticles(false);
    },
    [clearTimers],
  );

  const handlePrev = useCallback(() => {
    const next = selectedSample === 0 ? CODE_SAMPLES.length - 1 : selectedSample - 1;
    handleSelectSample(next);
  }, [selectedSample, handleSelectSample]);

  const handleNext = useCallback(() => {
    const next = selectedSample === CODE_SAMPLES.length - 1 ? 0 : selectedSample + 1;
    handleSelectSample(next);
  }, [selectedSample, handleSelectSample]);

  useEffect(() => clearTimers, [clearTimers]);

  return (
    <div
      ref={rootRef}
      className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden"
    >
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-72 h-72 bg-indigo-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 sm:p-8 space-y-6">
        {/* Header */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-white/[0.08] bg-white/[0.02]">
            <Sparkles className="h-3.5 w-3.5 text-emerald-400" />
            <span className="text-xs font-semibold text-white/70">
              JSON to TOON Laboratory
            </span>
          </div>
          <p className="text-xs text-white/40 max-w-md mx-auto">
            Pick a JSON payload, encode it, and watch the token estimate drop. Outputs and counts are
            real <code>toon --stats</code> results.
          </p>
        </div>

        {/* Sample stepper */}
        <div className="flex items-center gap-3 justify-center">
          <motion.button
            type="button"
            onClick={handlePrev}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center justify-center w-8 h-8 rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </motion.button>

          <div className="flex flex-wrap justify-center gap-1.5">
            {CODE_SAMPLES.map((s, i) => (
              <motion.button
                key={s.id}
                type="button"
                onClick={() => handleSelectSample(i)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className={`flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-medium transition-colors ${
                  selectedSample === i
                    ? `border-white/[0.15] bg-white/[0.06] ${s.color}`
                    : "border-white/[0.06] bg-white/[0.01] text-white/40 hover:text-white/60"
                }`}
              >
                {s.icon}
                <span className="hidden sm:inline">{s.label}</span>
                <span className="sm:hidden">{s.lang}</span>
              </motion.button>
            ))}
          </div>

          <motion.button
            type="button"
            onClick={handleNext}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center justify-center w-8 h-8 rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </motion.button>
        </div>

        {/* Sample info bar */}
        <div className="flex items-center justify-between px-2">
          <div className="flex items-center gap-2">
            <div
              className={`w-2 h-2 rounded-full ${isCompressed ? "bg-emerald-400" : isRunning ? "bg-blue-400 animate-pulse" : "bg-white/20"}`}
            />
            <span className="text-xs text-white/60 font-medium">{sample.label}</span>
            <span className="text-[10px] text-white/30 font-mono">{sample.lang}</span>
          </div>
          <PhaseIndicator phase={phase} active={inView} />
        </div>

        {/* Split panel: original and compressed */}
        <div className="grid gap-4 lg:grid-cols-2">
          {/* Original code panel */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
            <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.01]">
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  <div className="w-2 h-2 rounded-full bg-red-400/50" />
                  <div className="w-2 h-2 rounded-full bg-yellow-400/50" />
                  <div className="w-2 h-2 rounded-full bg-green-400/50" />
                </div>
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  JSON Input
                </span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[10px] font-mono text-white/40">
                  {sample.originalTokens.toLocaleString()} tokens
                </span>
                <FileCode className="h-3 w-3 text-white/20" />
              </div>
            </div>
            <HighlightedCode code={sample.original} phase={phase} />
          </div>

          {/* Compressed output panel */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden relative">
            <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.01]">
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  <div className="w-2 h-2 rounded-full bg-red-400/50" />
                  <div className="w-2 h-2 rounded-full bg-yellow-400/50" />
                  <div className="w-2 h-2 rounded-full bg-green-400/50" />
                </div>
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  TOON Output
                </span>
              </div>
              <AnimatePresence mode="wait">
                {isCompressed && (
                  <motion.div
                    key="token-count-compressed"
                    initial={{ opacity: 0, y: -4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 4 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="flex items-center gap-2"
                  >
                    <span className="text-[10px] font-mono text-emerald-400">
                      {sample.compressedTokens.toLocaleString()} tokens
                    </span>
                    <Zap className="h-3 w-3 text-emerald-400" />
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
            <div className="relative min-h-[200px]">
              <AnimatePresence mode="wait">
                {isRunning && (
                  <motion.div
                    key="compressing-animation"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="absolute inset-0 flex flex-col items-center justify-center gap-4 p-6"
                  >
                    {/* Pulsing compression icon */}
                    <div className="relative">
                      <motion.div
                        animate={
                          inView
                            ? { scale: [1, 1.3, 1], opacity: [0.3, 0.6, 0.3] }
                            : { scale: 1, opacity: 0.3 }
                        }
                        transition={
                          inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }
                        }
                        className="absolute inset-0 rounded-full bg-blue-500/20 blur-xl"
                        style={{ width: 60, height: 60, left: -10, top: -10 }}
                      />
                      <motion.div
                        animate={inView ? { rotate: 360 } : { rotate: 0 }}
                        transition={
                          inView
                            ? { duration: 2, repeat: Infinity, ease: "linear" }
                            : { duration: 0.2 }
                        }
                      >
                        <Minimize2 className="h-10 w-10 text-blue-400/80" />
                      </motion.div>
                    </div>
                    {/* Live token counter */}
                    <div className="text-center">
                      <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">
                        Token Count
                      </p>
                      <AnimatedCounter
                        value={displayedTokens}
                        duration={0.6}
                        className="text-2xl font-bold font-mono text-blue-300"
                      />
                    </div>
                    {/* Progress dots */}
                    <div className="flex gap-1.5">
                      {[0, 1, 2, 3].map((i) => (
                        <motion.div
                          key={i}
                          className="w-1.5 h-1.5 rounded-full bg-blue-400"
                          animate={inView ? { opacity: [0.2, 1, 0.2] } : { opacity: 0.2 }}
                          transition={
                            inView
                              ? { duration: 0.8, repeat: Infinity, delay: i * 0.15 }
                              : { duration: 0.2 }
                          }
                        />
                      ))}
                    </div>
                  </motion.div>
                )}
                {isCompressed && (
                  <motion.pre
                    key="compressed-result"
                    initial={{ opacity: 0, scale: 0.95, y: 10 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="p-4 text-xs text-emerald-300/80 font-mono leading-relaxed overflow-x-auto max-h-72 overflow-y-auto"
                  >
                    {sample.compressed}
                  </motion.pre>
                )}
                {phase === "idle" && (
                  <motion.div
                    key="placeholder-idle"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="absolute inset-0 flex flex-col items-center justify-center gap-3"
                  >
                    <div className="w-16 h-16 rounded-2xl border border-dashed border-white/[0.1] flex items-center justify-center">
                      <Minimize2 className="h-6 w-6 text-white/15" />
                    </div>
                    <span className="text-xs text-white/25">
                      Click &ldquo;Encode&rdquo; to see the result
                    </span>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Stats dashboard - appears after compression */}
        <AnimatePresence>
          {isCompressed && (
            <motion.div
              initial={{ opacity: 0, y: 20, height: 0 }}
              animate={{ opacity: 1, y: 0, height: "auto" }}
              exit={{ opacity: 0, y: 20, height: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="space-y-4 overflow-hidden"
            >
              {/* Stats row with gauge */}
              <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/[0.04] p-5">
                <div className="grid gap-6 sm:grid-cols-[1fr_auto_1fr]">
                  {/* Token comparison */}
                  <div className="flex flex-col items-center justify-center gap-4">
                    <div className="flex items-center gap-4">
                      {/* Before */}
                      <div className="text-center">
                        <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">
                          Before
                        </p>
                        <motion.div
                          initial={{ scale: 1.2, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ type: "spring", stiffness: 200, damping: 25 }}
                        >
                          <span className="text-xl font-bold font-mono text-white/70">
                            {sample.originalTokens.toLocaleString()}
                          </span>
                        </motion.div>
                        <p className="text-[10px] text-white/30">tokens</p>
                      </div>

                      {/* Arrow */}
                      <motion.div
                        initial={{ scale: 0, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.1 }}
                        className="relative"
                      >
                        <ArrowRight className="h-5 w-5 text-emerald-400/60" />
                        <ParticleBurst isActive={showParticles} />
                      </motion.div>

                      {/* After */}
                      <div className="text-center">
                        <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">
                          After
                        </p>
                        <motion.div
                          initial={{ scale: 1.2, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.15 }}
                        >
                          <span className="text-xl font-bold font-mono text-emerald-400">
                            {sample.compressedTokens.toLocaleString()}
                          </span>
                        </motion.div>
                        <p className="text-[10px] text-emerald-400/50">tokens</p>
                      </div>
                    </div>

                    {/* Saved tokens badge */}
                    <motion.div
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25, delay: 0.25 }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/20"
                    >
                      <Sparkles className="h-3 w-3 text-emerald-400" />
                      <span className="text-xs font-semibold text-emerald-400">
                        {savedTokens.toLocaleString()} tokens saved
                      </span>
                    </motion.div>
                  </div>

                  {/* Gauge */}
                  <div className="flex items-center justify-center">
                    <CompressionGauge percentage={reductionPct} isActive={isCompressed} />
                  </div>

                  {/* Bar chart comparison */}
                  <div className="flex items-center justify-center">
                    <div className="flex items-end gap-3 h-28">
                      {/* Before bar */}
                      <div className="flex flex-col items-center gap-1.5">
                        <span className="text-[10px] font-mono text-white/40">
                          {sample.originalTokens}
                        </span>
                        <motion.div
                          initial={{ height: 0 }}
                          animate={{ height: 80 }}
                          transition={{ type: "spring", stiffness: 100, damping: 20, delay: 0.1 }}
                          className="w-10 rounded-t-lg bg-gradient-to-t from-white/[0.08] to-white/[0.15]"
                        />
                        <span className="text-[10px] text-white/40 font-medium">Before</span>
                      </div>
                      {/* After bar */}
                      <div className="flex flex-col items-center gap-1.5">
                        <span className="text-[10px] font-mono text-emerald-400/80">
                          {sample.compressedTokens}
                        </span>
                        <motion.div
                          initial={{ height: 80 }}
                          animate={{ height: 80 * (1 - reductionPct / 100) }}
                          transition={{ type: "spring", stiffness: 100, damping: 20, delay: 0.3 }}
                          className="w-10 rounded-t-lg bg-gradient-to-t from-emerald-500/30 to-emerald-400/50"
                        />
                        <span className="text-[10px] text-emerald-400/60 font-medium">After</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Context window savings bar */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5">
                <ContextWindowBar
                  originalTokens={sample.originalTokens}
                  savedTokens={savedTokens}
                  isActive={isCompressed}
                />
              </div>

              {/* Compression breakdown */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 space-y-3">
                <p className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Where The Savings Come From
                </p>
                <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  {[
                    { label: "Unquoted keys and strings", pct: "\u201c\u201d", color: "bg-blue-400" },
                    { label: "No braces or brackets", pct: "{ }", color: "bg-violet-400" },
                    { label: "One header row per array", pct: "[n]{…}", color: "bg-amber-400" },
                    { label: "One CSV-like line per record", pct: "a,b,c", color: "bg-emerald-400" },
                  ].map((technique, i) => (
                    <motion.div
                      key={technique.label}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{
                        type: "spring",
                        stiffness: 200,
                        damping: 25,
                        delay: 0.1 * i,
                      }}
                      className="flex items-center gap-2 p-2 rounded-lg bg-white/[0.02]"
                    >
                      <div className={`w-1.5 h-6 rounded-full ${technique.color}/40`} />
                      <div className="flex-1 min-w-0">
                        <p className="text-[10px] text-white/60 truncate">{technique.label}</p>
                        <p className="text-xs font-bold font-mono text-white/80">{technique.pct}</p>
                      </div>
                    </motion.div>
                  ))}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Controls */}
        <div className="flex items-center justify-center gap-3">
          <motion.button
            type="button"
            onClick={handleCompress}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            disabled={isRunning}
            className={`flex items-center gap-2 rounded-2xl border px-6 py-2.5 text-sm font-medium transition-colors ${
              isRunning
                ? "border-white/[0.06] bg-white/[0.02] text-white/30 cursor-wait"
                : "border-blue-500/30 bg-blue-500/10 text-blue-300 hover:bg-blue-500/20"
            }`}
          >
            {isRunning ? (
              <>
                <motion.div
                  animate={inView ? { rotate: 360 } : { rotate: 0 }}
                  transition={
                    inView ? { duration: 1, repeat: Infinity, ease: "linear" } : { duration: 0.2 }
                  }
                >
                  <Minimize2 className="h-4 w-4" />
                </motion.div>
                Encoding...
              </>
            ) : (
              <>
                <Zap className="h-4 w-4" />
                {isCompressed ? "Re-Encode" : "Encode"}
              </>
            )}
          </motion.button>

          <AnimatePresence>
            {isCompressed && (
              <motion.button
                type="button"
                onClick={handleReset}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                className="flex items-center gap-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 py-2.5 text-sm font-medium text-white/50 hover:text-white/70 transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reset
              </motion.button>
            )}
          </AnimatePresence>
        </div>

        {/* Step counter */}
        <div className="flex items-center justify-center gap-1.5">
          {CODE_SAMPLES.map((_, i) => (
            <button
              key={i}
              type="button"
              onClick={() => handleSelectSample(i)}
              className={`w-1.5 h-1.5 rounded-full transition-colors ${
                i === selectedSample ? "bg-white/60" : "bg-white/15 hover:bg-white/25"
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
