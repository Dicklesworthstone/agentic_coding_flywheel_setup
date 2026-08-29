'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Users,
  Terminal,
  RefreshCw,
  ShieldCheck,
  Timer,
  Key,
  ArrowLeftRight,
  Gauge,
  AlertTriangle,
  Zap,
  ChevronLeft,
  ChevronRight,
  Sparkles,
  Activity,
  Clock,
  Shield,
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

export function CaamLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Manage multiple AI provider accounts and automatically rotate when rate
        limits hit to keep your agents running continuously.
      </GoalBanner>

      {/* Section 1: What Is CAAM */}
      <Section title="What Is CAAM?" icon={<Users className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>CAAM (Coding Agent Account Manager)</Highlight> manages
          multiple API accounts across AI providers (Anthropic, OpenAI, Google)
          and automatically switches between them when rate limits hit. Instead of
          waiting for cooldowns, your agents keep working on the next available
          account.
        </Paragraph>
        <Paragraph>
          When running agent swarms with NTM, each agent consumes API quota fast.
          CAAM tracks per-account rate limit state and rotates credentials so
          agents experience near-zero downtime from throttling.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ArrowLeftRight className="h-5 w-5" />}
              title="Account Switching"
              description="Rotate across multiple API keys per provider"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Timer className="h-5 w-5" />}
              title="Cooldown Tracking"
              description="Per-account rate limit state with TTL"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Gauge className="h-5 w-5" />}
              title="Usage Metrics"
              description="Track tokens and costs per account"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="Multi-Provider"
              description="Anthropic, OpenAI, Google in one system"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
        <div className="mt-8">
          <InteractiveAccountRotation />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Key className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Register your accounts, then let CAAM handle switching.
        </Paragraph>

        <CodeBlock
          code={`# Add an Anthropic account
caam add --provider anthropic --name "work-account" --key sk-ant-...

# Add a second account for the same provider
caam add --provider anthropic --name "personal" --key sk-ant-...

# Add an OpenAI account
caam add --provider openai --name "openai-main" --key sk-...

# List all registered accounts
caam list

# Check which account is active
caam status`}
          filename="Account Setup"
        />

        <TipBox variant="warning">
          API keys are stored encrypted on disk. Never commit the CAAM config
          directory to version control.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'caam list', description: 'List all registered accounts with status' },
            { command: 'caam status', description: 'Show active account and rate limit state' },
            { command: 'caam switch <name>', description: 'Manually switch to a specific account' },
            { command: 'caam rotate', description: 'Auto-switch to the next available account' },
            { command: 'caam cooldown <name>', description: 'Mark an account as rate-limited' },
            { command: 'caam reset <name>', description: 'Clear cooldown state for an account' },
            { command: 'caam remove <name>', description: 'Remove an account from CAAM' },
          ]}
        />

        <TipBox variant="tip">
          Use <code>caam rotate</code> in your agent startup scripts. It picks the
          account with the lowest recent usage and longest time since last rate limit.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Rate Limit Strategy */}
      <Section title="Rate Limit Strategy" icon={<RefreshCw className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          CAAM tracks three signals per account to make intelligent rotation decisions:
        </Paragraph>

        <CodeBlock
          code={`# View rate limit details for all accounts
caam status --verbose

# Example output:
# PROVIDER    ACCOUNT       STATUS    COOLDOWN   TOKENS/24H
# anthropic   work-account  active    --         142,000
# anthropic   personal      ready     --         23,000
# openai      openai-main   cooldown  4m 32s     89,000

# Auto-rotate picks "personal" (lowest usage, no cooldown)
caam rotate

# When an agent hits a rate limit, mark the account
caam cooldown work-account --ttl 5m

# CAAM automatically skips accounts still in cooldown
caam rotate  # → switches to "personal"`}
          filename="Rate Limit Management"
        />

        <TipBox variant="info">
          CAAM&apos;s rotation algorithm weighs three factors: cooldown TTL remaining,
          tokens used in the last 24 hours, and time since the account was last
          rate-limited. This prevents hot-spotting on a single account.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: NTM Integration */}
      <Section title="CAAM + Agent Swarms" icon={<ShieldCheck className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          When NTM spawns multiple agents, each one can be assigned a different
          CAAM account to maximize throughput.
        </Paragraph>

        <CodeBlock
          code={`# In your NTM spawn config, assign accounts per agent:
# Agent 1 uses work-account, Agent 2 uses personal, etc.

# Check which agents are using which accounts
caam status --by-session

# Monitor aggregate usage across all agents
caam usage --period 1h

# Set a budget ceiling (CAAM refuses to rotate when exceeded)
caam budget --daily 100 --provider anthropic`}
          filename="Multi-Agent Setup"
        />

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">CAAM + NTM</span>
            <p className="text-white/80 text-sm mt-1">Assign accounts per spawned agent for parallel throughput</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">CAAM + CAUT</span>
            <p className="text-white/80 text-sm mt-1">Track per-account costs alongside usage metrics</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">CAAM + SLB</span>
            <p className="text-white/80 text-sm mt-1">Require approval before switching to expensive accounts</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">CAAM + ASB</span>
            <p className="text-white/80 text-sm mt-1">Back up account configs across machines with ASB</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Account Rotation Control Panel
// ---------------------------------------------------------------------------

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

type AccountStatus = 'active' | 'standby' | 'cooldown' | 'recovering';

interface Account {
  id: string;
  name: string;
  provider: 'Anthropic' | 'OpenAI' | 'Google';
  providerColor: string;
  usagePct: number;
  rateLimitPct: number;
  tokensSent: number;
  status: AccountStatus;
  cooldownSec: number;
  sparkline: number[];
}

interface Scenario {
  id: string;
  label: string;
  icon: typeof Activity;
  color: keyof typeof COLOR_MAP;
  description: string;
  accounts: Account[];
  activeAccountId: string;
  terminalLines: string[];
  rotationEvent: { from: string; to: string } | null;
  switchTimeMs: number;
}

const COLOR_MAP = {
  emerald: {
    border: 'border-emerald-500/40',
    bg: 'bg-emerald-500/[0.08]',
    text: 'text-emerald-300',
    glow: 'bg-emerald-500/[0.04]',
  },
  amber: {
    border: 'border-amber-500/40',
    bg: 'bg-amber-500/[0.08]',
    text: 'text-amber-300',
    glow: 'bg-amber-500/[0.04]',
  },
  blue: {
    border: 'border-blue-500/40',
    bg: 'bg-blue-500/[0.08]',
    text: 'text-blue-300',
    glow: 'bg-blue-500/[0.04]',
  },
  red: {
    border: 'border-red-500/40',
    bg: 'bg-red-500/[0.08]',
    text: 'text-red-300',
    glow: 'bg-red-500/[0.04]',
  },
  violet: {
    border: 'border-violet-500/40',
    bg: 'bg-violet-500/[0.08]',
    text: 'text-violet-300',
    glow: 'bg-violet-500/[0.04]',
  },
  sky: {
    border: 'border-sky-500/40',
    bg: 'bg-sky-500/[0.08]',
    text: 'text-sky-300',
    glow: 'bg-sky-500/[0.04]',
  },
} as const;

function makeSparkline(base: number, variance: number, length: number): number[] {
  const result: number[] = [];
  for (let i = 0; i < length; i++) {
    result.push(Math.max(0, Math.min(100, base + (i % 3 === 0 ? variance : i % 3 === 1 ? -variance * 0.6 : variance * 0.3))));
  }
  return result;
}

const SCENARIOS: Scenario[] = [
  {
    id: 'normal',
    label: 'Normal Usage',
    icon: Activity,
    color: 'emerald',
    description: 'All accounts healthy. Active account handling requests at moderate load. Rate limits well within safe range.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 34, rateLimitPct: 22, tokensSent: 142000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(30, 8, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 8, rateLimitPct: 5, tokensSent: 23000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(8, 3, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 15, rateLimitPct: 10, tokensSent: 67000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(15, 5, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 3, rateLimitPct: 2, tokensSent: 11000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(3, 2, 12) },
    ],
    activeAccountId: 'a1',
    terminalLines: [
      '$ caam status --verbose',
      'CAAM Account Manager v3.2.1',
      '',
      'PROVIDER    ACCOUNT        STATUS   COOLDOWN  TOKENS/24H',
      'anthropic   work-primary   active   --        142,000',
      'anthropic   work-backup    standby  --         23,000',
      'openai      openai-main    standby  --         67,000',
      'google      gemini-pro     standby  --         11,000',
      '',
      'Active: work-primary (anthropic)',
      'Rate limit headroom: 78%',
    ],
    rotationEvent: null,
    switchTimeMs: 0,
  },
  {
    id: 'approaching',
    label: 'Rate Limit Near',
    icon: AlertTriangle,
    color: 'amber',
    description: 'Primary account approaching rate limit. CAAM detects 87% usage and pre-selects the next account for rotation.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 87, rateLimitPct: 85, tokensSent: 392000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(75, 12, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 8, rateLimitPct: 5, tokensSent: 23000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(8, 3, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 22, rateLimitPct: 14, tokensSent: 97000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(20, 6, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 5, rateLimitPct: 3, tokensSent: 18000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(5, 2, 12) },
    ],
    activeAccountId: 'a1',
    terminalLines: [
      '$ caam status --verbose',
      '! WARNING: work-primary at 87% rate limit',
      '',
      'PROVIDER    ACCOUNT        STATUS   COOLDOWN  TOKENS/24H',
      'anthropic   work-primary   active   --        392,000',
      'anthropic   work-backup    standby  --         23,000',
      'openai      openai-main    standby  --         97,000',
      'google      gemini-pro     standby  --         18,000',
      '',
      '! Pre-selecting work-backup for rotation',
      '  Estimated switch time: <100ms',
    ],
    rotationEvent: null,
    switchTimeMs: 0,
  },
  {
    id: 'switch',
    label: 'Instant Switch',
    icon: Zap,
    color: 'blue',
    description: 'Rate limit hit! CAAM instantly rotates to work-backup in 47ms. No agent downtime. The depleted account enters cooldown.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 100, rateLimitPct: 100, tokensSent: 450000, status: 'cooldown', cooldownSec: 300, sparkline: makeSparkline(90, 10, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 12, rateLimitPct: 8, tokensSent: 31000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(10, 4, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 22, rateLimitPct: 14, tokensSent: 97000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(20, 6, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 5, rateLimitPct: 3, tokensSent: 18000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(5, 2, 12) },
    ],
    activeAccountId: 'a2',
    terminalLines: [
      '$ caam rotate',
      '! Rate limit hit on work-primary',
      '  Switching to work-backup...',
      '  Switch completed in 47ms',
      '',
      '$ caam cooldown work-primary --ttl 5m',
      'Cooldown set: work-primary (5m 0s remaining)',
      '',
      '$ caam status',
      'Active: work-backup (anthropic)',
      'Cooldown: work-primary (4m 53s)',
    ],
    rotationEvent: { from: 'a1', to: 'a2' },
    switchTimeMs: 47,
  },
  {
    id: 'cooldown',
    label: 'Cooldown Timer',
    icon: Timer,
    color: 'violet',
    description: 'Primary account cooling down with 3:42 remaining. Backup account handling all traffic. Usage rising steadily on backup.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 100, rateLimitPct: 100, tokensSent: 450000, status: 'cooldown', cooldownSec: 222, sparkline: makeSparkline(95, 5, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 48, rateLimitPct: 38, tokensSent: 156000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(35, 10, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 22, rateLimitPct: 14, tokensSent: 97000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(20, 6, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 5, rateLimitPct: 3, tokensSent: 18000, status: 'standby', cooldownSec: 0, sparkline: makeSparkline(5, 2, 12) },
    ],
    activeAccountId: 'a2',
    terminalLines: [
      '$ caam status --verbose',
      'CAAM Account Manager v3.2.1',
      '',
      'PROVIDER    ACCOUNT        STATUS    COOLDOWN  TOKENS/24H',
      'anthropic   work-primary   cooldown  3m 42s    450,000',
      'anthropic   work-backup    active    --        156,000',
      'openai      openai-main    standby   --         97,000',
      'google      gemini-pro     standby   --         18,000',
      '',
      'Active: work-backup (anthropic)',
      'Next rotation candidate: openai-main',
    ],
    rotationEvent: null,
    switchTimeMs: 0,
  },
  {
    id: 'multi-balance',
    label: 'Multi-Provider',
    icon: ArrowLeftRight,
    color: 'sky',
    description: 'High-throughput swarm mode: CAAM balances load across all providers. Each account stays below 60% to avoid rate limits entirely.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 42, rateLimitPct: 35, tokensSent: 189000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(40, 8, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 38, rateLimitPct: 30, tokensSent: 164000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(35, 7, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 55, rateLimitPct: 48, tokensSent: 245000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(50, 10, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 31, rateLimitPct: 22, tokensSent: 134000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(28, 6, 12) },
    ],
    activeAccountId: 'a1',
    terminalLines: [
      '$ caam status --by-session',
      'CAAM Multi-Provider Balance Mode',
      '',
      'SESSION   PROVIDER    ACCOUNT        TOKENS/HR',
      'agent-1   anthropic   work-primary   12,400',
      'agent-2   anthropic   work-backup    11,800',
      'agent-3   openai      openai-main    15,200',
      'agent-4   google      gemini-pro      9,600',
      '',
      'All accounts below 60% threshold',
      'Balance score: 0.91 (excellent)',
    ],
    rotationEvent: null,
    switchTimeMs: 0,
  },
  {
    id: 'failover',
    label: 'Emergency',
    icon: Shield,
    color: 'red',
    description: 'Anthropic API outage! Both accounts unreachable. CAAM emergency failover: all traffic rerouted to OpenAI and Google in 82ms.',
    accounts: [
      { id: 'a1', name: 'work-primary', provider: 'Anthropic', providerColor: 'orange', usagePct: 100, rateLimitPct: 100, tokensSent: 450000, status: 'cooldown', cooldownSec: 999, sparkline: makeSparkline(95, 5, 12) },
      { id: 'a2', name: 'work-backup', provider: 'Anthropic', providerColor: 'orange', usagePct: 100, rateLimitPct: 100, tokensSent: 412000, status: 'cooldown', cooldownSec: 999, sparkline: makeSparkline(92, 5, 12) },
      { id: 'o1', name: 'openai-main', provider: 'OpenAI', providerColor: 'emerald', usagePct: 68, rateLimitPct: 58, tokensSent: 305000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(55, 12, 12) },
      { id: 'g1', name: 'gemini-pro', provider: 'Google', providerColor: 'sky', usagePct: 52, rateLimitPct: 42, tokensSent: 228000, status: 'active', cooldownSec: 0, sparkline: makeSparkline(42, 10, 12) },
    ],
    activeAccountId: 'o1',
    terminalLines: [
      '$ caam status',
      '!! EMERGENCY: Anthropic API unreachable',
      '  work-primary: CONNECTION_REFUSED',
      '  work-backup:  CONNECTION_REFUSED',
      '',
      '$ caam failover --auto',
      '  Rerouting agent-1 → openai-main (38ms)',
      '  Rerouting agent-2 → gemini-pro  (44ms)',
      '  Total failover time: 82ms',
      '',
      'All agents operational on backup providers',
    ],
    rotationEvent: { from: 'a1', to: 'o1' },
    switchTimeMs: 82,
  },
];

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

let sparkIdCounter = 0;
function SparklineChart({ data, color, width = 80, height = 24 }: { data: number[]; color: string; width?: number; height?: number }) {
  const [gradientId] = useState(() => `spark-${++sparkIdCounter}`);
  const points = data.map((v, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - (v / 100) * height;
    return `${x},${y}`;
  }).join(' ');

  const areaPoints = `0,${height} ${points} ${width},${height}`;

  return (
    <svg width={width} height={height} className="overflow-visible">
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </linearGradient>
      </defs>
      <polygon points={areaPoints} fill={`url(#${gradientId})`} />
      <polyline points={points} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CooldownRing({ seconds, maxSeconds }: { seconds: number; maxSeconds: number }) {
  const radius = 18;
  const circumference = 2 * Math.PI * radius;
  const progress = Math.min(seconds / maxSeconds, 1);
  const offset = circumference * (1 - progress);
  const minutes = Math.floor(seconds / 60);
  const secs = seconds % 60;

  return (
    <div className="relative flex items-center justify-center">
      <svg width={44} height={44} className="-rotate-90">
        <circle cx={22} cy={22} r={radius} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={3} />
        <motion.circle
          cx={22}
          cy={22}
          r={radius}
          fill="none"
          stroke="#a78bfa"
          strokeWidth={3}
          strokeLinecap="round"
          strokeDasharray={circumference}
          animate={{ strokeDashoffset: offset }}
          transition={SPRING}
        />
      </svg>
      <span className="absolute text-[10px] font-mono text-violet-300 font-bold">
        {minutes}:{secs.toString().padStart(2, '0')}
      </span>
    </div>
  );
}

function UsageGauge({ pct, size = 52 }: { pct: number; size?: number }) {
  const radius = (size - 8) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - pct / 100);
  const gaugeColor = pct >= 90 ? '#ef4444' : pct >= 70 ? '#f59e0b' : '#22c55e';

  return (
    <div className="relative flex items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={4} />
        <motion.circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={gaugeColor}
          strokeWidth={4}
          strokeLinecap="round"
          strokeDasharray={circumference}
          animate={{ strokeDashoffset: offset }}
          transition={SPRING}
        />
      </svg>
      <motion.span
        className="absolute text-[10px] font-mono font-bold"
        animate={{ color: gaugeColor }}
        transition={SPRING}
      >
        {pct}%
      </motion.span>
    </div>
  );
}

function RateLimitBar({ pct }: { pct: number }) {
  const barColor = pct >= 90 ? 'bg-red-500' : pct >= 70 ? 'bg-amber-500' : 'bg-emerald-500';
  return (
    <div className="w-full">
      <div className="flex justify-between text-[10px] text-white/40 mb-0.5">
        <span>Rate Limit</span>
        <span>{pct}%</span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${barColor}`}
          animate={{ width: `${pct}%` }}
          transition={SPRING}
        />
      </div>
    </div>
  );
}

function getProviderBadgeColor(color: string) {
  switch (color) {
    case 'orange': return 'bg-orange-500/20 text-orange-300 border-orange-500/30';
    case 'emerald': return 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30';
    case 'sky': return 'bg-sky-500/20 text-sky-300 border-sky-500/30';
    default: return 'bg-white/10 text-white/60 border-white/20';
  }
}

function getSparkColor(providerColor: string) {
  switch (providerColor) {
    case 'orange': return '#fb923c';
    case 'emerald': return '#34d399';
    case 'sky': return '#38bdf8';
    default: return '#94a3b8';
  }
}

function getStatusStyles(status: AccountStatus) {
  switch (status) {
    case 'active': return { border: 'border-emerald-500/50', bg: 'bg-emerald-500/[0.06]', dot: 'bg-emerald-400', label: 'Active', labelColor: 'text-emerald-400' };
    case 'cooldown': return { border: 'border-red-500/50', bg: 'bg-red-500/[0.06]', dot: 'bg-red-400', label: 'Cooldown', labelColor: 'text-red-400' };
    case 'recovering': return { border: 'border-amber-500/50', bg: 'bg-amber-500/[0.06]', dot: 'bg-amber-400', label: 'Recovering', labelColor: 'text-amber-400' };
    case 'standby':
    default: return { border: 'border-white/[0.08]', bg: 'bg-white/[0.02]', dot: 'bg-white/20', label: 'Standby', labelColor: 'text-white/40' };
  }
}

function formatTokens(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(0)}K`;
  return String(n);
}

function MiniTerminal({ lines }: { lines: string[] }) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-1.5 px-3 py-1.5 bg-white/[0.03] border-b border-white/[0.06]">
        <div className="w-2 h-2 rounded-full bg-red-500/60" />
        <div className="w-2 h-2 rounded-full bg-amber-500/60" />
        <div className="w-2 h-2 rounded-full bg-emerald-500/60" />
        <span className="ml-2 text-[10px] text-white/30 font-mono">caam</span>
      </div>
      <div className="p-3 font-mono text-[10px] leading-relaxed space-y-0.5 max-h-[180px] overflow-y-auto">
        {lines.map((line, i) => {
          const isCommand = line.startsWith('$');
          const isWarning = line.startsWith('!');
          const isEmpty = line.trim() === '';
          return (
            <motion.div
              key={`${i}-${line.slice(0, 20)}`}
              initial={{ opacity: 0, x: -4 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.04, ...SPRING }}
              className={
                isCommand ? 'text-emerald-400 font-semibold' :
                isWarning ? 'text-amber-400' :
                isEmpty ? 'h-2' :
                'text-white/60'
              }
            >
              {line}
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}

function RotationArrow({ fromName, toName, switchMs }: { fromName: string; toName: string; switchMs: number }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <motion.div
      ref={rootRef}
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.8 }}
      transition={SPRING}
      className="flex items-center justify-center gap-2 py-2 px-4 rounded-xl border border-blue-500/30 bg-blue-500/[0.06]"
    >
      <span className="text-xs text-red-400 font-medium">{fromName}</span>
      <motion.div
        animate={inView ? { x: [0, 6, 0] } : { x: 0 }}
        transition={inView ? { duration: 0.6, repeat: Infinity } : { duration: 0.2 }}
      >
        <Zap className="h-4 w-4 text-blue-400" />
      </motion.div>
      <span className="text-xs text-emerald-400 font-medium">{toName}</span>
      {switchMs > 0 && (
        <span className="text-[10px] font-mono text-blue-300 ml-1">
          {switchMs}ms
        </span>
      )}
    </motion.div>
  );
}

function AccountCard({ account, isActiveScenarioAccount, active }: { account: Account; isActiveScenarioAccount: boolean; active: boolean }) {
  const styles = getStatusStyles(account.status);
  const sparkColor = getSparkColor(account.providerColor);

  return (
    <motion.div
      layout
      animate={
        account.status === 'cooldown'
          ? { x: [0, -3, 3, -3, 3, 0] }
          : { x: 0 }
      }
      transition={
        account.status === 'cooldown'
          ? { duration: 0.4, ease: 'easeInOut' }
          : SPRING
      }
      className={`relative rounded-2xl border p-3 transition-colors ${styles.border} ${styles.bg}`}
    >
      {/* Active pulse */}
      {account.status === 'active' && isActiveScenarioAccount && (
        <motion.div
          className="absolute inset-0 rounded-2xl border-2 border-emerald-500/30"
          animate={active ? { opacity: [0.3, 0.7, 0.3], scale: [1, 1.01, 1] } : { opacity: 0.3, scale: 1 }}
          transition={active ? { duration: 2, repeat: Infinity, ease: 'easeInOut' } : { duration: 0.2 }}
        />
      )}

      {/* Header row */}
      <div className="flex items-start justify-between gap-1 mb-1.5">
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-semibold text-white/90 truncate">{account.name}</p>
          <span className={`inline-block mt-0.5 rounded-full border px-1.5 py-0 text-[10px] font-medium ${getProviderBadgeColor(account.providerColor)}`}>
            {account.provider}
          </span>
        </div>
        <UsageGauge pct={account.usagePct} size={40} />
      </div>

      {/* Rate limit bar */}
      <RateLimitBar pct={account.rateLimitPct} />

      {/* Sparkline */}
      <div className="mt-2 flex items-center justify-between">
        <SparklineChart data={account.sparkline} color={sparkColor} width={64} height={18} />
        <span className="text-[10px] font-mono text-white/30">{formatTokens(account.tokensSent)}</span>
      </div>

      {/* Cooldown ring or status */}
      <div className="mt-2 flex items-center gap-1.5">
        {account.status === 'cooldown' && account.cooldownSec > 0 ? (
          <CooldownRing seconds={account.cooldownSec} maxSeconds={300} />
        ) : (
          <>
            {account.status === 'active' ? (
              <motion.div
                className={`h-1.5 w-1.5 rounded-full ${styles.dot}`}
                animate={active ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
                transition={active ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
              />
            ) : (
              <div className={`h-1.5 w-1.5 rounded-full ${styles.dot}`} />
            )}
            <span className={`text-[10px] font-medium ${styles.labelColor}`}>{styles.label}</span>
          </>
        )}
      </div>
    </motion.div>
  );
}

function RecoveryTimeline({ accounts }: { accounts: Account[] }) {
  const cooldownAccounts = accounts.filter(a => a.status === 'cooldown');
  if (cooldownAccounts.length === 0) return null;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
      <div className="flex items-center gap-1.5 mb-2">
        <Clock className="h-3 w-3 text-violet-400" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Recovery Timeline</span>
      </div>
      <div className="space-y-2">
        {cooldownAccounts.map(acc => {
          const pct = Math.min((acc.cooldownSec / 300) * 100, 100);
          return (
            <div key={acc.id}>
              <div className="flex justify-between text-[10px] mb-0.5">
                <span className="text-white/60">{acc.name}</span>
                <span className="text-violet-300 font-mono">
                  {Math.floor(acc.cooldownSec / 60)}:{(acc.cooldownSec % 60).toString().padStart(2, '0')}
                </span>
              </div>
              <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  className="h-full rounded-full bg-violet-500/60"
                  animate={{ width: `${pct}%` }}
                  transition={SPRING}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ProviderSummary({ accounts }: { accounts: Account[] }) {
  const providers = ['Anthropic', 'OpenAI', 'Google'] as const;
  const providerColors: Record<string, string> = { Anthropic: '#fb923c', OpenAI: '#34d399', Google: '#38bdf8' };

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
      <div className="flex items-center gap-1.5 mb-2">
        <Gauge className="h-3 w-3 text-sky-400" />
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Provider Load</span>
      </div>
      <div className="space-y-2">
        {providers.map(provider => {
          const provAccounts = accounts.filter(a => a.provider === provider);
          if (provAccounts.length === 0) return null;
          const avgUsage = Math.round(provAccounts.reduce((s, a) => s + a.usagePct, 0) / provAccounts.length);
          const totalTokens = provAccounts.reduce((s, a) => s + a.tokensSent, 0);
          const color = providerColors[provider];
          const barColor = avgUsage >= 90 ? 'bg-red-500' : avgUsage >= 70 ? 'bg-amber-500' : 'bg-emerald-500';

          return (
            <div key={provider}>
              <div className="flex justify-between text-[10px] mb-0.5">
                <span style={{ color }} className="font-medium">{provider}</span>
                <span className="text-white/40">{formatTokens(totalTokens)} total</span>
              </div>
              <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${barColor}`}
                  animate={{ width: `${avgUsage}%` }}
                  transition={SPRING}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main interactive component
// ---------------------------------------------------------------------------

function InteractiveAccountRotation() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [animatedAccounts, setAnimatedAccounts] = useState<Account[]>(SCENARIOS[0].accounts);
  const animRef = useRef(0);
  const prevAccountsRef = useRef<Account[]>(SCENARIOS[0].accounts);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const scenario = SCENARIOS[scenarioIdx];
  const colors = COLOR_MAP[scenario.color] ?? COLOR_MAP.emerald;

  // Animate account values toward new targets
  useEffect(() => {
    const targetAccounts = scenario.accounts;
    const startAccounts = prevAccountsRef.current;
    const duration = 900;
    const t0 = performance.now();
    let running = true;

    function tick(now: number) {
      if (!running) return;
      const elapsed = now - t0;
      const progress = Math.min(elapsed / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 3);

      const interpolated = targetAccounts.map((target, i) => {
        const start = startAccounts[i] ?? target;
        return {
          ...target,
          usagePct: Math.round(start.usagePct + (target.usagePct - start.usagePct) * ease),
          rateLimitPct: Math.round(start.rateLimitPct + (target.rateLimitPct - start.rateLimitPct) * ease),
          tokensSent: Math.round(start.tokensSent + (target.tokensSent - start.tokensSent) * ease),
          cooldownSec: Math.round(start.cooldownSec + (target.cooldownSec - start.cooldownSec) * ease),
        };
      });

      setAnimatedAccounts(interpolated);

      if (progress < 1) {
        animRef.current = requestAnimationFrame(tick);
      } else {
        prevAccountsRef.current = targetAccounts;
      }
    }

    animRef.current = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(animRef.current);
    };
  }, [scenario.accounts]);

  const handleSelectScenario = useCallback((idx: number) => {
    setScenarioIdx(idx);
  }, []);

  const handleStepForward = useCallback(() => {
    setScenarioIdx((prev) => (prev + 1) % SCENARIOS.length);
  }, []);

  const handleStepBack = useCallback(() => {
    setScenarioIdx((prev) => (prev - 1 + SCENARIOS.length) % SCENARIOS.length);
  }, []);

  const isEmergency = scenario.id === 'failover';

  const rotFromName = scenario.rotationEvent
    ? scenario.accounts.find(a => a.id === scenario.rotationEvent?.from)?.name ?? ''
    : '';
  const rotToName = scenario.rotationEvent
    ? scenario.accounts.find(a => a.id === scenario.rotationEvent?.to)?.name ?? ''
    : '';

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-orange-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 w-48 h-48 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none -translate-x-1/2 -translate-y-1/2" />

      {/* Emergency flash overlay */}
      <AnimatePresence>
        {isEmergency && (
          <motion.div
            key="emergency-flash"
            initial={{ opacity: 0 }}
            animate={inView ? { opacity: [0, 0.15, 0, 0.1, 0] } : { opacity: 0 }}
            transition={inView ? { duration: 2, repeat: Infinity } : { duration: 0.2 }}
            className="absolute inset-0 bg-red-500/20 rounded-3xl pointer-events-none z-10"
          />
        )}
      </AnimatePresence>

      <div className="relative p-6 sm:p-8 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="flex items-center justify-center gap-2">
            <Sparkles className="h-4 w-4 text-blue-400" />
            <p className="text-sm font-semibold text-white/90">Account Rotation Control Panel</p>
            <Sparkles className="h-4 w-4 text-blue-400" />
          </div>
          <p className="text-xs text-white/50">
            Step through scenarios to see how CAAM manages accounts, rate limits, and emergency failover
          </p>
        </div>

        {/* Scenario stepper */}
        <div className="flex items-center justify-center gap-2">
          <motion.button
            type="button"
            onClick={handleStepBack}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-1.5 text-white/40 hover:text-white/70 transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </motion.button>

          <div className="flex flex-wrap justify-center gap-1.5">
            {SCENARIOS.map((s, i) => {
              const Icon = s.icon;
              const isActive = scenarioIdx === i;
              const sColors = COLOR_MAP[s.color] ?? COLOR_MAP.emerald;
              return (
                <motion.button
                  key={s.id}
                  type="button"
                  onClick={() => handleSelectScenario(i)}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  transition={SPRING}
                  className={`rounded-xl border px-2.5 py-1.5 text-[11px] font-medium transition-colors flex items-center gap-1.5 ${
                    isActive
                      ? `${sColors.border} ${sColors.bg} ${sColors.text}`
                      : 'border-white/[0.06] bg-white/[0.02] text-white/40 hover:text-white/60'
                  }`}
                >
                  <Icon className="h-3 w-3" />
                  <span className="hidden sm:inline">{s.label}</span>
                </motion.button>
              );
            })}
          </div>

          <motion.button
            type="button"
            onClick={handleStepForward}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-1.5 text-white/40 hover:text-white/70 transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </motion.button>
        </div>

        {/* Step indicator dots */}
        <div className="flex items-center justify-center gap-1.5">
          {SCENARIOS.map((s, i) => (
            <motion.div
              key={s.id}
              animate={{
                scale: scenarioIdx === i ? 1.3 : 1,
                backgroundColor: scenarioIdx === i
                  ? (COLOR_MAP[s.color]?.text === 'text-red-300' ? '#ef4444' : '#3b82f6')
                  : 'rgba(255,255,255,0.15)',
              }}
              transition={SPRING}
              className="w-1.5 h-1.5 rounded-full"
            />
          ))}
        </div>

        {/* Scenario description */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={SPRING}
            className={`rounded-xl border px-4 py-2.5 ${colors.border} ${colors.bg}`}
          >
            <p className={`text-xs font-medium ${colors.text}`}>{scenario.description}</p>
          </motion.div>
        </AnimatePresence>

        {/* Rotation event banner */}
        <AnimatePresence>
          {scenario.rotationEvent && (
            <RotationArrow fromName={rotFromName} toName={rotToName} switchMs={scenario.switchTimeMs} />
          )}
        </AnimatePresence>

        {/* Main dashboard grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {/* LEFT: Account cards grid */}
          <div className="lg:col-span-2 space-y-3">
            <div className="flex items-center gap-1.5 mb-1">
              <Users className="h-3 w-3 text-white/50" />
              <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Accounts</span>
            </div>
            <AnimatePresence mode="wait">
              <motion.div
                key={scenario.id}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={SPRING}
                className="grid grid-cols-2 gap-3"
              >
                {animatedAccounts.map(account => (
                  <AccountCard
                    key={account.id}
                    account={account}
                    isActiveScenarioAccount={account.id === scenario.activeAccountId}
                    active={inView}
                  />
                ))}
              </motion.div>
            </AnimatePresence>
          </div>

          {/* RIGHT: Sidepanel */}
          <div className="space-y-3">
            <ProviderSummary accounts={animatedAccounts} />
            <RecoveryTimeline accounts={animatedAccounts} />
          </div>
        </div>

        {/* Mini terminal */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING}
          >
            <MiniTerminal lines={scenario.terminalLines} />
          </motion.div>
        </AnimatePresence>

        {/* Footer stats */}
        <div className="flex flex-wrap items-center justify-center gap-4 text-[10px] text-white/40">
          <div className="flex items-center gap-1">
            <Activity className="h-3 w-3" />
            <span>Active: {animatedAccounts.filter(a => a.status === 'active').length}</span>
          </div>
          <div className="flex items-center gap-1">
            <Timer className="h-3 w-3" />
            <span>Cooldown: {animatedAccounts.filter(a => a.status === 'cooldown').length}</span>
          </div>
          <div className="flex items-center gap-1">
            <Gauge className="h-3 w-3" />
            <span>Total tokens: {formatTokens(animatedAccounts.reduce((s, a) => s + a.tokensSent, 0))}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
