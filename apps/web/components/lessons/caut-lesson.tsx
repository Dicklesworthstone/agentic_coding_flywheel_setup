'use client';

import { useState, useCallback, useEffect, useRef, useMemo, useId } from 'react';
import { motion, AnimatePresence, useInView } from "@/components/motion";
import {
  BarChart3,
  Terminal,
  DollarSign,
  PieChart,
  Clock,
  Play,
  Shield,
  TrendingUp,
  Zap,
  ArrowUpRight,
  ArrowDownRight,
  AlertTriangle,
  Activity,
  RefreshCw,
  ChevronLeft,
  ChevronRight,
  Gauge,
  ArrowLeftRight,
  Flame,
  Sparkles,
  CheckCircle2,
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

function InteractiveCostDashboard() {
  return <InteractiveCostDashboardImpl />;
}

export function CautLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Track LLM API usage across providers and agents to understand costs and optimize spending.
      </GoalBanner>

      {/* Section 1: What Is CAUT */}
      <Section title="What Is CAUT?" icon={<BarChart3 className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>CAUT (Coding Agent Usage Tracker)</Highlight> monitors token
          consumption and API costs across all your AI coding agents. It aggregates
          usage from Claude, GPT, and Gemini into a single dashboard.
        </Paragraph>
        <Paragraph>
          When running multiple agents simultaneously, costs can escalate quickly.
          CAUT gives you visibility into which agents, sessions, and providers are
          consuming the most tokens, helping you optimize your workflow.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<DollarSign className="h-5 w-5" />}
              title="Cost Tracking"
              description="Per-provider spend analysis"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<PieChart className="h-5 w-5" />}
              title="Usage Breakdown"
              description="Input vs output tokens"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="Time Series"
              description="Historical usage trends"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Multi-Agent"
              description="Track across all sessions"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-8">
          <InteractiveCostDashboard />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Get a quick overview of your usage.
        </Paragraph>

        <CodeBlock
          code={`# Show today's usage summary
caut summary

# Show usage for the past week
caut summary --period 7d

# Show per-provider breakdown
caut breakdown

# Show per-session token counts
caut sessions --sort tokens`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Run <code>caut summary</code> at the end of each day to understand your usage patterns.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'caut summary', description: 'Usage summary for current period' },
            { command: 'caut breakdown', description: 'Per-provider cost breakdown' },
            { command: 'caut sessions', description: 'Token usage by session' },
            { command: 'caut export --format csv', description: 'Export usage data' },
          ]}
        />

        <TipBox variant="info">
          CAUT reads usage data from agent log files and API response headers.
          No additional API calls are made.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Cost Optimization */}
      <Section title="Cost Optimization" icon={<DollarSign className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Use CAUT data to optimize your agent spending.
        </Paragraph>

        <CodeBlock
          code={`# Find your most expensive sessions
caut sessions --sort cost --limit 10

# Compare providers
caut compare --providers anthropic,openai

# Show token efficiency (output/input ratio)
caut efficiency

# Set a daily budget alert
caut alert --daily-budget 50`}
          filename="Optimization"
        />
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">CAUT + RANO</span>
            <p className="text-white/80 text-sm mt-1">Network traffic feeds usage tracking data</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">CAUT + CAAM</span>
            <p className="text-white/80 text-sm mt-1">Track usage per account for billing insights</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">CAUT + NTM</span>
            <p className="text-white/80 text-sm mt-1">See cost per agent in multi-agent swarms</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">CAUT + TRU</span>
            <p className="text-white/80 text-sm mt-1">Measure TRU compression savings in real tokens</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE COST OPERATIONS CENTER
// =============================================================================

const SPRING = { type: "spring" as const, stiffness: 200, damping: 25 };
const SPRING_SNAPPY = { type: "spring" as const, stiffness: 400, damping: 35 };

interface ProviderState {
  id: string;
  name: string;
  color: string;
  bgColor: string;
  borderColor: string;
  gradientFrom: string;
  gradientTo: string;
  dotColor: string;
  costPerMToken: number;
  currentCost: number;
  tokensK: number;
  sparkline: number[];
  rateLimited: boolean;
  accountName: string;
}

interface ScenarioStep {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  budgetUsed: number; // 0-100
  totalCost: number;
  savings: number;
  providers: {
    anthropic: { cost: number; tokensK: number; rateLimited: boolean; accountName: string };
    openai: { cost: number; tokensK: number; rateLimited: boolean; accountName: string };
    google: { cost: number; tokensK: number; rateLimited: boolean; accountName: string };
  };
  alerts: AlertItem[];
  logLines: string[];
}

interface AlertItem {
  level: "info" | "warn" | "error" | "success";
  message: string;
}

const SCENARIO_STEPS: ScenarioStep[] = [
  {
    id: "normal",
    label: "Normal Spend",
    icon: <Activity className="h-3.5 w-3.5" />,
    description: "All providers running within budget. Steady token flow across 3 agents.",
    budgetUsed: 28,
    totalCost: 14.20,
    savings: 0,
    providers: {
      anthropic: { cost: 7.20, tokensK: 480, rateLimited: false, accountName: "work-primary" },
      openai: { cost: 4.50, tokensK: 450, rateLimited: false, accountName: "team-openai" },
      google: { cost: 2.50, tokensK: 360, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "info", message: "3 agents active across 2 sessions" },
    ],
    logLines: [
      "09:14:02  anthropic  480K tokens  $7.20  work-primary",
      "09:14:02  openai     450K tokens  $4.50  team-openai",
      "09:14:02  google     360K tokens  $2.50  gcp-main",
    ],
  },
  {
    id: "budget-alert",
    label: "Budget Alert",
    icon: <AlertTriangle className="h-3.5 w-3.5" />,
    description: "Anthropic spend approaching daily budget threshold. CAUT fires a warning.",
    budgetUsed: 62,
    totalCost: 31.40,
    savings: 0,
    providers: {
      anthropic: { cost: 18.90, tokensK: 1260, rateLimited: false, accountName: "work-primary" },
      openai: { cost: 8.00, tokensK: 800, rateLimited: false, accountName: "team-openai" },
      google: { cost: 4.50, tokensK: 640, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "warn", message: "Daily budget 62% consumed - $31.40 of $50.00" },
      { level: "warn", message: "Anthropic spend rate: $2.70/hr (projected $43.20 today)" },
    ],
    logLines: [
      "11:42:18  WARN  Budget alert: 62% of daily $50 consumed",
      "11:42:18  WARN  Anthropic projected to hit limit by 16:00",
      "11:42:18  INFO  Recommendation: shift load to google (cheapest)",
    ],
  },
  {
    id: "cost-spike",
    label: "Cost Spike",
    icon: <Flame className="h-3.5 w-3.5" />,
    description: "Agent swarm spawned 5 new sessions. Token burn rate triples in minutes.",
    budgetUsed: 84,
    totalCost: 42.10,
    savings: 0,
    providers: {
      anthropic: { cost: 24.80, tokensK: 1650, rateLimited: false, accountName: "work-primary" },
      openai: { cost: 11.30, tokensK: 1130, rateLimited: false, accountName: "team-openai" },
      google: { cost: 6.00, tokensK: 860, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "error", message: "SPIKE: Burn rate jumped from $4.20/hr to $12.60/hr" },
      { level: "warn", message: "Budget will be exhausted in ~38 minutes at current rate" },
      { level: "info", message: "5 new NTM agents spawned in session #47" },
    ],
    logLines: [
      "13:05:44  ALERT  Cost spike detected: 3x normal burn rate",
      "13:05:44  INFO   NTM session #47 spawned 5 agents",
      "13:05:44  WARN   Budget exhaustion ETA: 38 min",
      "13:05:45  INFO   Auto-throttle recommendation sent to NTM",
    ],
  },
  {
    id: "account-switch",
    label: "Account Switch",
    icon: <ArrowLeftRight className="h-3.5 w-3.5" />,
    description: "CAAM rotates Anthropic to a backup account. Cost tracking seamlessly follows.",
    budgetUsed: 84,
    totalCost: 42.10,
    savings: 0,
    providers: {
      anthropic: { cost: 24.80, tokensK: 1650, rateLimited: false, accountName: "work-backup" },
      openai: { cost: 11.30, tokensK: 1130, rateLimited: false, accountName: "team-openai" },
      google: { cost: 6.00, tokensK: 860, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "info", message: "CAAM rotated anthropic: work-primary -> work-backup" },
      { level: "success", message: "CAUT tracking updated for new account credentials" },
    ],
    logLines: [
      "13:06:01  CAAM   Rotating anthropic account...",
      "13:06:01  CAAM   work-primary -> work-backup (0ms downtime)",
      "13:06:02  CAUT   Rebinding usage tracker to work-backup",
      "13:06:02  OK     Seamless handoff complete",
    ],
  },
  {
    id: "rate-limit",
    label: "Rate Limit Hit",
    icon: <Shield className="h-3.5 w-3.5" />,
    description: "OpenAI account hits TPM limit. CAAM swaps to backup while CAUT logs the event.",
    budgetUsed: 88,
    totalCost: 44.30,
    savings: 0,
    providers: {
      anthropic: { cost: 25.50, tokensK: 1700, rateLimited: false, accountName: "work-backup" },
      openai: { cost: 12.80, tokensK: 1280, rateLimited: true, accountName: "team-openai-2" },
      google: { cost: 6.00, tokensK: 860, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "error", message: "OpenAI team-openai: 429 Too Many Requests (TPM limit)" },
      { level: "info", message: "CAAM auto-rotated to team-openai-2 in 12ms" },
      { level: "warn", message: "team-openai cooldown: ~45s remaining" },
    ],
    logLines: [
      "13:12:33  ERROR  openai/team-openai: 429 rate_limit_exceeded",
      "13:12:33  CAAM   Scanning available openai accounts...",
      "13:12:33  CAAM   Switching to team-openai-2 (12ms)",
      "13:12:34  CAUT   Rate limit event logged for billing analysis",
    ],
  },
  {
    id: "optimization",
    label: "Optimization",
    icon: <Sparkles className="h-3.5 w-3.5" />,
    description: "CAUT applies cost optimization: shifts heavy tasks to cheaper providers and enables caching.",
    budgetUsed: 64,
    totalCost: 32.00,
    savings: 12.30,
    providers: {
      anthropic: { cost: 16.20, tokensK: 1080, rateLimited: false, accountName: "work-backup" },
      openai: { cost: 8.40, tokensK: 840, rateLimited: false, accountName: "team-openai-2" },
      google: { cost: 7.40, tokensK: 1060, rateLimited: false, accountName: "gcp-main" },
    },
    alerts: [
      { level: "success", message: "Optimization applied: shifted 30% of prompts to google" },
      { level: "success", message: "Prompt caching enabled: $5.80 saved on repeated context" },
      { level: "success", message: "Total savings this session: $12.30" },
    ],
    logLines: [
      "13:18:00  OPT    Analyzing provider cost efficiency...",
      "13:18:00  OPT    Shifting bulk tasks: anthropic -> google (-38%)",
      "13:18:01  OPT    Enabling prompt cache for repeated context blocks",
      "13:18:01  SAVE   $12.30 recovered vs pre-optimization trajectory",
      "13:18:01  OK     Budget utilization dropped from 88% to 64%",
    ],
  },
];

function hashSeed(seedKey: string): number {
  let hash = 2166136261;
  for (let i = 0; i < seedKey.length; i++) {
    hash ^= seedKey.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function seededUnitInterval(seed: number, index: number): number {
  const value = Math.sin((seed + index * 131) * 12.9898) * 43758.5453123;
  return value - Math.floor(value);
}

// Generates deterministic sparkline data points to avoid hydration mismatches.
function generateSparkline(base: number, volatility: number, points: number, seedKey: string): number[] {
  const result: number[] = [];
  let current = base;
  const seed = hashSeed(`${seedKey}:${base}:${volatility}:${points}`);
  for (let i = 0; i < points; i++) {
    current = Math.max(0, current + (seededUnitInterval(seed, i) - 0.45) * volatility);
    result.push(Math.round(current));
  }
  return result;
}

// SVG sparkline mini-chart
function SparklineChart({
  data,
  color,
  width = 120,
  height = 32,
}: {
  data: number[];
  color: string;
  width?: number;
  height?: number;
}) {
  const gradientId = useId();
  if (data.length < 2) return null;
  const max = Math.max(...data);
  const min = Math.min(...data);
  const range = max - min || 1;

  const points = data
    .map((val, i) => {
      const x = (i / (data.length - 1)) * width;
      const y = height - ((val - min) / range) * (height - 4) - 2;
      return `${x},${y}`;
    })
    .join(" ");

  const areaPoints = `0,${height} ${points} ${width},${height}`;

  return (
    <svg width={width} height={height} className="overflow-visible">
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0.0} />
        </linearGradient>
      </defs>
      <polygon
        points={areaPoints}
        fill={`url(#${gradientId})`}
      />
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// Animated bar chart for provider costs
function ProviderBar({
  provider,
  maxCost,
  isHighlighted,
}: {
  provider: ProviderState;
  maxCost: number;
  isHighlighted: boolean;
}) {
  const barWidth = maxCost > 0 ? (provider.currentCost / maxCost) * 100 : 0;

  return (
    <motion.div
      layout
      transition={SPRING}
      className={`rounded-xl border p-3 transition-colors ${
        isHighlighted
          ? `${provider.borderColor} ${provider.bgColor}`
          : "border-white/[0.08] bg-white/[0.02] hover:border-white/[0.12]"
      }`}
    >
      <div className="flex items-center justify-between mb-1.5">
        <div className="flex items-center gap-2">
          <div
            className={`h-2.5 w-2.5 rounded-full bg-gradient-to-r ${provider.gradientFrom} ${provider.gradientTo}`}
          />
          <span className={`text-sm font-semibold ${isHighlighted ? provider.color : "text-white/70"}`}>
            {provider.name}
          </span>
          {provider.rateLimited && (
            <motion.span
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={SPRING_SNAPPY}
              className="text-[10px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded bg-red-500/20 text-red-400 border border-red-500/30"
            >
              Rate Limited
            </motion.span>
          )}
        </div>
        <div className="flex items-center gap-3">
          <span className="text-[10px] text-white/30 font-mono">
            {provider.accountName}
          </span>
          <span className={`text-xs font-semibold font-mono ${provider.color}`}>
            ${provider.currentCost.toFixed(2)}
          </span>
        </div>
      </div>

      {/* Cost bar */}
      <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden mb-2">
        <motion.div
          initial={{ width: 0 }}
          animate={{ width: `${barWidth}%` }}
          transition={{ type: "spring", stiffness: 100, damping: 20 }}
          className={`h-full rounded-full bg-gradient-to-r ${provider.gradientFrom} ${provider.gradientTo} ${
            provider.rateLimited ? "opacity-50" : ""
          }`}
        />
      </div>

      {/* Token count + sparkline */}
      <div className="flex items-center justify-between">
        <span className="text-xs text-white/40 font-mono">
          {provider.tokensK >= 1000
            ? `${(provider.tokensK / 1000).toFixed(1)}M`
            : `${provider.tokensK}K`}{" "}
          tokens
        </span>
        <SparklineChart
          data={provider.sparkline}
          color={provider.dotColor}
          width={80}
          height={20}
        />
      </div>
    </motion.div>
  );
}

// Budget gauge / thermometer
function BudgetGauge({ percent }: { percent: number }) {
  const clampedPercent = Math.min(100, Math.max(0, percent));

  const getGaugeColor = (pct: number): string => {
    if (pct < 50) return "from-emerald-500 to-emerald-400";
    if (pct < 75) return "from-amber-500 to-yellow-400";
    return "from-red-500 to-orange-400";
  };

  const getGlowColor = (pct: number): string => {
    if (pct < 50) return "bg-emerald-500/20";
    if (pct < 75) return "bg-amber-500/20";
    return "bg-red-500/20";
  };

  const getTextColor = (pct: number): string => {
    if (pct < 50) return "text-emerald-400";
    if (pct < 75) return "text-amber-400";
    return "text-red-400";
  };

  const getLabelColor = (pct: number): string => {
    if (pct < 50) return "text-emerald-400/60";
    if (pct < 75) return "text-amber-400/60";
    return "text-red-400/60";
  };

  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <div ref={rootRef} className="rounded-xl border border-white/[0.08] bg-black/30 p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <Gauge className="h-3.5 w-3.5 text-white/40" />
          <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
            Daily Budget
          </span>
        </div>
        <motion.span
          key={`budget-${clampedPercent}`}
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={SPRING_SNAPPY}
          className={`text-lg font-bold font-mono ${getTextColor(clampedPercent)}`}
        >
          {clampedPercent}%
        </motion.span>
      </div>

      {/* Thermometer bar */}
      <div className="relative h-4 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          initial={{ width: 0 }}
          animate={{ width: `${clampedPercent}%` }}
          transition={{ type: "spring", stiffness: 80, damping: 18 }}
          className={`h-full rounded-full bg-gradient-to-r ${getGaugeColor(clampedPercent)} relative`}
        >
          {/* Animated glow at the end */}
          <motion.div
            animate={inView ? { opacity: [0.5, 1, 0.5] } : { opacity: 0.5 }}
            transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
            className={`absolute right-0 top-0 h-full w-4 ${getGlowColor(clampedPercent)} blur-sm`}
          />
        </motion.div>

        {/* Tick marks */}
        <div className="absolute inset-0 flex items-center">
          {[25, 50, 75].map((mark) => (
            <div
              key={mark}
              className="absolute h-full w-px bg-white/[0.1]"
              style={{ left: `${mark}%` }}
            />
          ))}
        </div>
      </div>

      {/* Labels */}
      <div className="flex justify-between mt-1.5">
        <span className="text-[10px] text-white/20 font-mono">$0</span>
        <span className={`text-[10px] font-mono ${getLabelColor(clampedPercent)}`}>$50 limit</span>
      </div>
    </div>
  );
}

// Savings counter with tick-up animation
function SavingsCounter({ target }: { target: number }) {
  const [displayed, setDisplayed] = useState(0);
  const rafRef = useRef<number | null>(null);
  const startTimeRef = useRef<number | null>(null);
  const startValueRef = useRef(0);

  useEffect(() => {
    startValueRef.current = displayed;
    startTimeRef.current = null;

    const animate = (timestamp: number) => {
      if (startTimeRef.current === null) {
        startTimeRef.current = timestamp;
      }
      const elapsed = timestamp - startTimeRef.current;
      const duration = 800;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = startValueRef.current + (target - startValueRef.current) * eased;

      setDisplayed(current);

      if (progress < 1) {
        rafRef.current = requestAnimationFrame(animate);
      }
    };

    rafRef.current = requestAnimationFrame(animate);
    return () => {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
    // We intentionally only re-run when target changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target]);

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4">
      <div className="flex items-center gap-2 mb-2">
        <TrendingUp className="h-3.5 w-3.5 text-emerald-400/60" />
        <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
          Savings Recovered
        </span>
      </div>
      <div className="flex items-baseline gap-1">
        <motion.span
          key={`savings-${target}`}
          initial={{ scale: 1.2, color: "rgb(52, 211, 153)" }}
          animate={{ scale: 1, color: target > 0 ? "rgb(52, 211, 153)" : "rgba(255,255,255,0.5)" }}
          transition={SPRING}
          className="text-2xl font-bold font-mono"
        >
          ${displayed.toFixed(2)}
        </motion.span>
        {target > 0 && (
          <motion.span
            initial={{ opacity: 0, x: -4 }}
            animate={{ opacity: 1, x: 0 }}
            transition={SPRING}
            className="text-xs text-emerald-400/60 font-medium"
          >
            saved
          </motion.span>
        )}
      </div>
      {target > 0 ? (
        <div className="flex items-center gap-1 mt-1">
          <ArrowDownRight className="h-3 w-3 text-emerald-400/60" />
          <span className="text-[10px] text-emerald-400/60 font-medium">
            Prompt caching + provider shifting
          </span>
        </div>
      ) : (
        <div className="flex items-center gap-1 mt-1">
          <span className="text-[10px] text-white/20 font-medium">
            No optimizations applied yet
          </span>
        </div>
      )}
    </div>
  );
}

// Alert log panel
function AlertPanel({ alerts }: { alerts: AlertItem[] }) {
  const levelStyles: Record<string, { border: string; text: string; icon: React.ReactNode }> = {
    info: {
      border: "border-blue-500/30",
      text: "text-blue-400",
      icon: <Activity className="h-3 w-3" />,
    },
    warn: {
      border: "border-amber-500/30",
      text: "text-amber-400",
      icon: <AlertTriangle className="h-3 w-3" />,
    },
    error: {
      border: "border-red-500/30",
      text: "text-red-400",
      icon: <Flame className="h-3 w-3" />,
    },
    success: {
      border: "border-emerald-500/30",
      text: "text-emerald-400",
      icon: <CheckCircle2 className="h-3 w-3" />,
    },
  };

  return (
    <div className="space-y-1.5">
      <AnimatePresence mode="popLayout">
        {alerts.map((alert, idx) => {
          const style = levelStyles[alert.level] ?? levelStyles.info;
          return (
            <motion.div
              key={`${alert.level}-${alert.message}`}
              initial={{ opacity: 0, x: -12, height: 0 }}
              animate={{ opacity: 1, x: 0, height: "auto" }}
              exit={{ opacity: 0, x: 12, height: 0 }}
              transition={{ ...SPRING, delay: idx * 0.08 }}
              className={`flex items-start gap-2 px-3 py-2 rounded-lg border bg-black/20 ${style.border}`}
            >
              <span className={`${style.text} mt-0.5 shrink-0`}>{style.icon}</span>
              <span className={`text-xs font-mono ${style.text}`}>{alert.message}</span>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

// Live log terminal
function LiveLog({ lines }: { lines: string[] }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <div ref={rootRef} className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <Terminal className="h-3 w-3 text-white/30" />
        <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
          Live Feed
        </span>
        <motion.div
          animate={inView ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
          transition={inView ? { duration: 1.2, repeat: Infinity } : { duration: 0.2 }}
          className="h-1.5 w-1.5 rounded-full bg-emerald-500 ml-auto"
        />
      </div>
      <div className="p-3 space-y-0.5 max-h-32 overflow-y-auto">
        <AnimatePresence mode="popLayout">
          {lines.map((line, idx) => (
            <motion.div
              key={`${line}-${idx}`}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ ...SPRING, delay: idx * 0.06 }}
              className="text-[11px] font-mono text-white/50 leading-relaxed whitespace-nowrap"
            >
              <span className="text-white/20 select-none">$ </span>
              {line}
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
}

// Account switcher animation
function AccountSwitcher({
  fromAccount,
  toAccount,
  isAnimating,
}: {
  fromAccount: string;
  toAccount: string;
  isAnimating: boolean;
}) {
  if (!isAnimating || fromAccount === toAccount) return null;

  return (
    <motion.div
      initial={{ opacity: 0, scaleY: 0 }}
      animate={{ opacity: 1, scaleY: 1 }}
      exit={{ opacity: 0, scaleY: 0 }}
      transition={SPRING}
      className="flex items-center justify-center gap-3 px-4 py-3 rounded-xl border border-violet-500/30 bg-violet-500/10"
    >
      <motion.span
        initial={{ x: 0 }}
        animate={{ x: -8, opacity: 0.4 }}
        transition={{ ...SPRING, delay: 0.2 }}
        className="text-xs font-mono text-violet-300 line-through"
      >
        {fromAccount}
      </motion.span>
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1, rotate: 360 }}
        transition={{ ...SPRING_SNAPPY, delay: 0.3 }}
      >
        <RefreshCw className="h-3.5 w-3.5 text-violet-400" />
      </motion.div>
      <motion.span
        initial={{ x: 8, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        transition={{ ...SPRING, delay: 0.4 }}
        className="text-xs font-mono text-violet-300 font-bold"
      >
        {toAccount}
      </motion.span>
    </motion.div>
  );
}

function InteractiveCostDashboardImpl() {
  const [stepIndex, setStepIndex] = useState(0);
  const [previousStepIndex, setPreviousStepIndex] = useState(0);
  const [showAccountSwitch, setShowAccountSwitch] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const step = SCENARIO_STEPS[stepIndex];

  // Build sparkline data for each provider based on current step
  const providerStates: ProviderState[] = useMemo(() => {
    const pData = step.providers;
    return [
      {
        id: "anthropic",
        name: "Anthropic (Claude)",
        color: "text-orange-400",
        bgColor: "bg-orange-500/10",
        borderColor: "border-orange-500/30",
        gradientFrom: "from-orange-500",
        gradientTo: "to-amber-500",
        dotColor: "#f97316",
        costPerMToken: 15,
        currentCost: pData.anthropic.cost,
        tokensK: pData.anthropic.tokensK,
        sparkline: generateSparkline(pData.anthropic.tokensK / 20, 8, 12, `${step.id}:anthropic`),
        rateLimited: pData.anthropic.rateLimited,
        accountName: pData.anthropic.accountName,
      },
      {
        id: "openai",
        name: "OpenAI (GPT)",
        color: "text-emerald-400",
        bgColor: "bg-emerald-500/10",
        borderColor: "border-emerald-500/30",
        gradientFrom: "from-emerald-500",
        gradientTo: "to-teal-500",
        dotColor: "#34d399",
        costPerMToken: 10,
        currentCost: pData.openai.cost,
        tokensK: pData.openai.tokensK,
        sparkline: generateSparkline(pData.openai.tokensK / 20, 6, 12, `${step.id}:openai`),
        rateLimited: pData.openai.rateLimited,
        accountName: pData.openai.accountName,
      },
      {
        id: "google",
        name: "Google (Gemini)",
        color: "text-blue-400",
        bgColor: "bg-blue-500/10",
        borderColor: "border-blue-500/30",
        gradientFrom: "from-blue-500",
        gradientTo: "to-indigo-500",
        dotColor: "#60a5fa",
        costPerMToken: 7,
        currentCost: pData.google.cost,
        tokensK: pData.google.tokensK,
        sparkline: generateSparkline(pData.google.tokensK / 20, 5, 12, `${step.id}:google`),
        rateLimited: pData.google.rateLimited,
        accountName: pData.google.accountName,
      },
    ];
  }, [step]);

  const maxCost = Math.max(...providerStates.map((p) => p.currentCost));

  // Detect account switch scenario
  const isAccountStep = step.id === "account-switch" || step.id === "rate-limit";
  useEffect(() => {
    if (!isAccountStep) return;

    const showTimer = setTimeout(() => setShowAccountSwitch(true), 0);
    const hideTimer = setTimeout(() => setShowAccountSwitch(false), 3000);
    return () => {
      clearTimeout(showTimer);
      clearTimeout(hideTimer);
    };
  }, [isAccountStep, stepIndex]);


  const setScenarioStep = useCallback((nextStep: number | ((current: number) => number)) => {
    setStepIndex((current) => {
      const resolved = typeof nextStep === "function" ? nextStep(current) : nextStep;
      const clamped = Math.max(0, Math.min(SCENARIO_STEPS.length - 1, resolved));
      if (clamped !== current) {
        setPreviousStepIndex(current);
        setShowAccountSwitch(false);
      }
      return clamped;
    });
  }, []);

  const goNext = useCallback(() => {
    setScenarioStep((prev) => prev + 1);
  }, [setScenarioStep]);

  const goPrev = useCallback(() => {
    setScenarioStep((prev) => prev - 1);
  }, [setScenarioStep]);

  // Determine account switch info for the animation
  const prevStep = SCENARIO_STEPS[previousStepIndex];
  const isAccountSwitchStep = step.id === "account-switch";
  const isRateLimitStep = step.id === "rate-limit";
  const accountSwitchFrom = isRateLimitStep
    ? prevStep?.providers.openai.accountName ?? ""
    : prevStep?.providers.anthropic.accountName ?? "";
  const accountSwitchTo = isRateLimitStep
    ? step.providers.openai.accountName
    : step.providers.anthropic.accountName;

  return (
    <div ref={rootRef} className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-orange-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-blue-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-0 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-6 space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-2">
            <motion.div
              animate={inView ? { rotate: [0, 360] } : { rotate: 0 }}
              transition={inView ? { duration: 20, repeat: Infinity, ease: "linear" } : { duration: 0.2 }}
            >
              <Activity className="h-4 w-4 text-white/40" />
            </motion.div>
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Cost Operations Center
            </span>
            <motion.div
              animate={inView ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
              transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
              className="h-1.5 w-1.5 rounded-full bg-emerald-500"
            />
            <span className="text-[10px] text-emerald-400/60 font-medium">LIVE</span>
          </div>
        </div>

        {/* Scenario stepper */}
        <div className="space-y-3">
          {/* Step pills */}
          <div className="flex gap-1.5 overflow-x-auto pb-1 scrollbar-none">
            {SCENARIO_STEPS.map((s, idx) => (
              <motion.button
                key={s.id}
                onClick={() => setScenarioStep(idx)}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                transition={SPRING_SNAPPY}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-medium whitespace-nowrap transition-colors border ${
                  stepIndex === idx
                    ? "bg-white/[0.1] text-white border-white/[0.15]"
                    : "text-white/35 hover:text-white/55 border-transparent hover:border-white/[0.06]"
                }`}
              >
                {s.icon}
                {s.label}
              </motion.button>
            ))}
          </div>

          {/* Step navigation + description */}
          <div className="flex items-center gap-3">
            <motion.button
              onClick={goPrev}
              disabled={stepIndex === 0}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-white/40 hover:text-white/70 disabled:opacity-20 disabled:hover:text-white/40 shrink-0"
            >
              <ChevronLeft className="h-3.5 w-3.5" />
            </motion.button>

            <AnimatePresence mode="wait">
              <motion.div
                key={step.id}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={SPRING}
                className="flex-1 min-w-0"
              >
                <div className="flex items-center gap-2 mb-0.5">
                  <span className="text-xs font-semibold text-white/80">{step.label}</span>
                  <span className="text-[10px] text-white/25 font-mono">
                    Step {stepIndex + 1}/{SCENARIO_STEPS.length}
                  </span>
                </div>
                <p className="text-xs text-white/40 leading-relaxed line-clamp-2">
                  {step.description}
                </p>
              </motion.div>
            </AnimatePresence>

            <motion.button
              onClick={goNext}
              disabled={stepIndex === SCENARIO_STEPS.length - 1}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-white/40 hover:text-white/70 disabled:opacity-20 disabled:hover:text-white/40 shrink-0"
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </motion.button>
          </div>
        </div>

        {/* Account switch animation overlay */}
        <AnimatePresence>
          {showAccountSwitch && (isAccountSwitchStep || isRateLimitStep) && (
            <AccountSwitcher
              fromAccount={accountSwitchFrom}
              toAccount={accountSwitchTo}
              isAnimating={showAccountSwitch}
            />
          )}
        </AnimatePresence>

        {/* Main dashboard grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {/* Total cost card */}
          <motion.div
            layout
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-black/30 p-4"
          >
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="h-3.5 w-3.5 text-white/40" />
              <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
                Total Spend
              </span>
            </div>
            <AnimatePresence mode="wait">
              <motion.div
                key={`cost-${step.id}`}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={SPRING}
                className="text-2xl font-bold text-white/90 font-mono"
              >
                ${step.totalCost.toFixed(2)}
              </motion.div>
            </AnimatePresence>
            <div className="flex items-center gap-1 mt-1">
              {step.totalCost > 30 ? (
                <>
                  <ArrowUpRight className="h-3 w-3 text-red-400/60" />
                  <span className="text-[10px] text-red-400/60 font-medium">
                    Above daily average
                  </span>
                </>
              ) : (
                <>
                  <ArrowDownRight className="h-3 w-3 text-emerald-400/60" />
                  <span className="text-[10px] text-emerald-400/60 font-medium">
                    Within normal range
                  </span>
                </>
              )}
            </div>
          </motion.div>

          {/* Total tokens card */}
          <motion.div
            layout
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-black/30 p-4"
          >
            <div className="flex items-center gap-2 mb-2">
              <Zap className="h-3.5 w-3.5 text-amber-400/60" />
              <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
                Total Tokens
              </span>
            </div>
            <AnimatePresence mode="wait">
              <motion.div
                key={`tokens-${step.id}`}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={SPRING}
                className="text-2xl font-bold text-white/90 font-mono"
              >
                {(() => {
                  const total =
                    step.providers.anthropic.tokensK +
                    step.providers.openai.tokensK +
                    step.providers.google.tokensK;
                  return total >= 1000
                    ? `${(total / 1000).toFixed(1)}M`
                    : `${total}K`;
                })()}
              </motion.div>
            </AnimatePresence>
            <div className="flex items-center gap-1 mt-1">
              <BarChart3 className="h-3 w-3 text-white/30" />
              <span className="text-[10px] text-white/30 font-medium">
                Across {providerStates.filter((p) => !p.rateLimited).length} active providers
              </span>
            </div>
          </motion.div>
        </div>

        {/* Budget gauge + Savings counter side by side */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <BudgetGauge percent={step.budgetUsed} />
          <SavingsCounter target={step.savings} />
        </div>

        {/* Provider breakdown bars */}
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <PieChart className="h-4 w-4 text-white/40" />
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Provider Breakdown
            </span>
          </div>

          <AnimatePresence mode="wait">
            <motion.div
              key={step.id}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="space-y-2"
            >
              {providerStates.map((provider) => (
                <ProviderBar
                  key={provider.id}
                  provider={provider}
                  maxCost={maxCost}
                  isHighlighted={provider.rateLimited}
                />
              ))}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Cost distribution mini-chart */}
        <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4">
          <div className="flex items-center gap-2 mb-3">
            <BarChart3 className="h-3.5 w-3.5 text-white/40" />
            <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
              Cost Distribution
            </span>
          </div>
          <div className="flex items-end gap-1 h-16">
            {providerStates.map((provider) => {
              const heightPct = maxCost > 0 ? (provider.currentCost / maxCost) * 100 : 0;
              return (
                <div key={provider.id} className="flex-1 flex flex-col items-center gap-1">
                  <motion.div
                    initial={{ height: 0 }}
                    animate={{ height: `${heightPct}%` }}
                    transition={{ type: "spring", stiffness: 100, damping: 18 }}
                    className={`w-full rounded-t-md bg-gradient-to-t ${provider.gradientFrom} ${provider.gradientTo} ${
                      provider.rateLimited ? "opacity-40" : "opacity-80"
                    } min-h-[2px]`}
                  />
                  <span className="text-[10px] text-white/30 font-mono truncate w-full text-center">
                    {provider.name.split(" ")[0]}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Alerts panel */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-white/40" />
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Alerts
            </span>
            <motion.span
              key={`alert-count-${step.alerts.length}-${step.id}`}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={SPRING_SNAPPY}
              className="text-[10px] font-mono text-white/30 bg-white/[0.05] px-1.5 py-0.5 rounded"
            >
              {step.alerts.length}
            </motion.span>
          </div>
          <AlertPanel alerts={step.alerts} />
        </div>

        {/* Live log */}
        <LiveLog lines={step.logLines} />

        {/* Footer tip */}
        <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/[0.06]">
          <TrendingUp className="h-3.5 w-3.5 text-white/30 shrink-0" />
          <span className="text-xs text-white/40">
            Step through scenarios to see how CAUT tracks costs, detects spikes, and applies optimizations in real time.
          </span>
        </div>
      </div>
    </div>
  );
}
