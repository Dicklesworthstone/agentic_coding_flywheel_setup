'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Cpu,
  Terminal,
  Zap,
  Server,
  Settings,
  Activity,
  Play,
  Shield,
  Monitor,
  CheckCircle2,
  AlertTriangle,
  Loader2,
  ChevronLeft,
  ChevronRight,
  Sparkles,
  Wifi,
  WifiOff,
  ArrowRight,
  HardDrive,
  Clock,
  Package,
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

export function RchLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Offload Rust builds to remote workers for faster compilation in multi-agent workflows.
      </GoalBanner>

      {/* Section 1: What Is RCH */}
      <Section title="What Is RCH?" icon={<Cpu className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>RCH (Remote Compilation Helper)</Highlight> transparently intercepts
          cargo commands and routes them to powerful remote build servers. Your local
          machine stays responsive while heavy Rust compilations run elsewhere.
        </Paragraph>
        <Paragraph>
          When running multiple AI agents that all trigger builds, your local CPU becomes
          a bottleneck. RCH solves this by syncing source to remote workers, building
          there, and streaming artifacts back.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Server className="h-5 w-5" />}
              title="Remote Workers"
              description="Build on powerful remote servers"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Transparent"
              description="Works via Claude Code hook"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="Fast Sync"
              description="rsync + zstd compression"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Worker Pool"
              description="Priority-based scheduling"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: How It Works */}
      <Section title="How It Works" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          RCH intercepts cargo commands via a Claude Code hook and offloads them to
          remote workers.
        </Paragraph>

        <div className="mt-8 mb-8">
          <InteractiveFleetDashboard />
        </div>

        <CodeBlock
          code={`# Local: You run cargo build
cargo build --release
         ↓
# RCH Hook intercepts the command
         ↓
# Source synced to worker via rsync
         ↓
# Remote: Build runs on powerful server
         ↓
# Artifacts synced back to local machine`}
          filename="Build Flow"
        />

        <TipBox variant="tip">
          The hook is transparent. You run normal cargo commands and RCH handles the rest.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Quick Start */}
      <Section title="Quick Start" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Get started with these essential commands.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'rch hook install', description: 'Install the Claude Code hook' },
            { command: 'rch daemon start', description: 'Start the local daemon' },
            { command: 'rch workers add user@host', description: 'Add a remote worker' },
            { command: 'rch status', description: 'Check system status' },
          ]}
        />

        <TipBox variant="warning">
          Make sure SSH keys are set up for passwordless access to workers before adding them.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Worker Management */}
      <Section title="Worker Management" icon={<Server className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          RCH supports multiple remote workers with priority-based scheduling.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'rch workers add user@hostname', description: 'Add a new worker' },
            { command: 'rch workers list', description: 'List configured workers' },
            { command: 'rch workers status', description: 'Check worker connectivity' },
            { command: 'rch workers ping', description: 'Verify all workers are reachable' },
          ]}
        />

        <CodeBlock
          code={`# Workers are stored in ~/.config/rch/workers.toml
[[workers]]
name = "build-server-1"
host = "ubuntu@192.168.1.100"
slots = 48
priority = 100
tags = ["fast", "baremetal"]

[[workers]]
name = "build-server-2"
host = "ubuntu@192.168.1.101"
slots = 16
priority = 80
tags = ["secondary"]`}
          filename="~/.config/rch/workers.toml"
        />
      </Section>

      <Divider />

      {/* Section 5: Diagnostics */}
      <Section title="Diagnostics" icon={<Activity className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          RCH includes comprehensive diagnostics to troubleshoot issues.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'rch doctor', description: 'Run full diagnostic check' },
            { command: 'rch doctor --fix', description: 'Auto-fix common issues' },
            { command: 'rch daemon status', description: 'Check if daemon is running' },
            { command: 'rch config show', description: 'View current configuration' },
          ]}
        />

        <TipBox variant="tip">
          Run <code>rch doctor</code> if builds aren&apos;t being offloaded. It checks
          prerequisites, configuration, and worker connectivity.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Configuration */}
      <Section title="Configuration" icon={<Settings className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          RCH configuration lives in <code>~/.config/rch/</code>.
        </Paragraph>

        <CodeBlock
          code={`# View current config
rch config show

# Set default worker
rch config set default_worker=build-server-1

# Update RCH binaries on all workers
rch update --remote`}
          filename="Configuration Commands"
        />

        <TipBox variant="info">
          Keep workers in sync with <code>rch update --remote</code> after updating the local RCH binary.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 7: Integration */}
      <Section title="Tool Integration" icon={<Zap className="h-5 w-5" />} delay={0.4}>
        <Paragraph>
          RCH integrates seamlessly with other flywheel tools.
        </Paragraph>

        <div className="space-y-4">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.45 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RCH + NTM</h4>
            <p className="text-muted-foreground text-sm">
              Agents spawned by NTM automatically use RCH for their builds.
              Multiple agents can compile in parallel without overwhelming local CPU.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RCH + RU</h4>
            <p className="text-muted-foreground text-sm">
              RU syncs repos that RCH then builds remotely. Use{' '}
              <code className="text-primary">ru sync</code> to update sources,
              then build with RCH-accelerated cargo.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.55 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RCH + Beads</h4>
            <p className="text-muted-foreground text-sm">
              Track build-related tasks via beads. Create issues for build
              failures or optimization opportunities.
            </p>
          </motion.div>
        </div>
      </Section>

      <Divider />

      {/* Section 8: Best Practices */}
      <Section title="Best Practices" icon={<Shield className="h-5 w-5" />} delay={0.45}>
        <Paragraph>
          Get the most out of RCH with these recommendations.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">SSH Keys</span>
            <p className="text-white/80 text-sm mt-1">Set up passwordless SSH access</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">Fast Workers</span>
            <p className="text-white/80 text-sm mt-1">Use servers with many CPU cores</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Keep Synced</span>
            <p className="text-white/80 text-sm mt-1">Update workers with rch update --remote</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">Monitor Status</span>
            <p className="text-white/80 text-sm mt-1">Check rch status regularly</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE COMPILATION FLEET DASHBOARD
// =============================================================================

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

// ---------------------------------------------------------------------------
// Types & Data
// ---------------------------------------------------------------------------

type WorkerHealth = 'online' | 'building' | 'done' | 'error' | 'offline' | 'syncing';

interface WorkerNode {
  id: number;
  name: string;
  host: string;
  cpuCores: number;
  ramGb: number;
  cpuPct: number;
  ramPct: number;
  buildProgress: number;
  health: WorkerHealth;
  job: string;
  latencyMs: number;
}

interface BuildJob {
  id: string;
  crate: string;
  assignedTo: number | null;
  status: 'queued' | 'building' | 'done' | 'failed';
}

interface FleetScenario {
  id: string;
  label: string;
  icon: typeof Server;
  color: string;
  description: string;
  workers: WorkerNode[];
  buildQueue: BuildJob[];
  terminalLines: string[];
  localTimeSec: number;
  remoteTimeSec: number;
  artifactsMb: number;
}

function makeWorker(
  id: number,
  name: string,
  host: string,
  cpuCores: number,
  ramGb: number,
  overrides: Partial<WorkerNode> = {},
): WorkerNode {
  return {
    id,
    name,
    host,
    cpuCores,
    ramGb,
    cpuPct: 0,
    ramPct: 0,
    buildProgress: 0,
    health: 'online',
    job: '',
    latencyMs: 12 + id * 3,
    ...overrides,
  };
}

const BASE_WORKERS: WorkerNode[] = [
  makeWorker(0, 'vps-alpha-01', '10.0.1.10', 48, 64),
  makeWorker(1, 'vps-alpha-02', '10.0.1.11', 48, 64),
  makeWorker(2, 'vps-bravo-01', '10.0.2.10', 32, 32),
  makeWorker(3, 'vps-bravo-02', '10.0.2.11', 32, 32),
  makeWorker(4, 'vps-charlie-01', '10.0.3.10', 16, 16),
  makeWorker(5, 'vps-charlie-02', '10.0.3.11', 16, 16),
  makeWorker(6, 'vps-delta-01', '10.0.4.10', 64, 128),
  makeWorker(7, 'vps-delta-02', '10.0.4.11', 64, 128),
];

const SCENARIOS: FleetScenario[] = [
  {
    id: 'idle',
    label: 'Idle Fleet',
    icon: Server,
    color: 'emerald',
    description: 'All 8 worker nodes online and idle. Fleet is healthy and ready to accept build jobs.',
    workers: BASE_WORKERS.map((w) => ({ ...w, health: 'online' as const, cpuPct: 2 + w.id, ramPct: 8 + w.id * 2 })),
    buildQueue: [],
    terminalLines: [
      '$ rch status',
      'RCH Remote Compilation Helper v3.2.0',
      '',
      'Fleet: 8/8 workers online',
      'Queue: 0 jobs pending',
      'Daemon: running (pid 4821)',
      '',
      'All systems nominal.',
    ],
    localTimeSec: 0,
    remoteTimeSec: 0,
    artifactsMb: 0,
  },
  {
    id: 'dispatched',
    label: 'Build Dispatched',
    icon: ArrowRight,
    color: 'blue',
    description: 'cargo build --release intercepted. Source tree syncing to workers via rsync + zstd.',
    workers: BASE_WORKERS.map((w) => ({
      ...w,
      health: 'syncing' as const,
      cpuPct: 15 + w.id * 2,
      ramPct: 12 + w.id * 3,
      job: 'rsync',
    })),
    buildQueue: [
      { id: 'J-001', crate: 'my-service', assignedTo: null, status: 'queued' },
      { id: 'J-002', crate: 'my-lib-core', assignedTo: null, status: 'queued' },
      { id: 'J-003', crate: 'my-lib-utils', assignedTo: null, status: 'queued' },
      { id: 'J-004', crate: 'my-lib-db', assignedTo: null, status: 'queued' },
      { id: 'J-005', crate: 'my-lib-api', assignedTo: null, status: 'queued' },
      { id: 'J-006', crate: 'my-lib-auth', assignedTo: null, status: 'queued' },
    ],
    terminalLines: [
      '$ cargo build --release',
      '[rch] Hook intercepted: cargo build --release',
      '[rch] Syncing workspace (142 MB) to 8 workers...',
      '[rch] rsync --zstd -a src/ -> vps-alpha-01',
      '[rch] rsync --zstd -a src/ -> vps-alpha-02',
      '[rch] rsync --zstd -a src/ -> vps-bravo-01',
      '[rch] ... (6 more workers)',
      '[rch] Sync complete in 3.2s',
    ],
    localTimeSec: 0,
    remoteTimeSec: 0,
    artifactsMb: 0,
  },
  {
    id: 'compiling',
    label: 'Parallel Compilation',
    icon: Cpu,
    color: 'amber',
    description: 'All workers compiling crates in parallel. CPU utilization near max across the fleet.',
    workers: BASE_WORKERS.map((w) => ({
      ...w,
      health: 'building' as const,
      cpuPct: 78 + (w.id % 4) * 5,
      ramPct: 55 + (w.id % 3) * 10,
      buildProgress: 30 + w.id * 8,
      job: ['my-service', 'my-lib-core', 'my-lib-utils', 'my-lib-db', 'my-lib-api', 'my-lib-auth', 'my-service', 'my-lib-core'][w.id],
    })),
    buildQueue: [
      { id: 'J-001', crate: 'my-service', assignedTo: 0, status: 'building' },
      { id: 'J-002', crate: 'my-lib-core', assignedTo: 1, status: 'building' },
      { id: 'J-003', crate: 'my-lib-utils', assignedTo: 2, status: 'building' },
      { id: 'J-004', crate: 'my-lib-db', assignedTo: 3, status: 'building' },
      { id: 'J-005', crate: 'my-lib-api', assignedTo: 4, status: 'building' },
      { id: 'J-006', crate: 'my-lib-auth', assignedTo: 5, status: 'building' },
    ],
    terminalLines: [
      '[rch] Dispatching 6 crates across 8 workers',
      '[vps-alpha-01] Compiling my-service v0.9.3',
      '[vps-alpha-02] Compiling my-lib-core v1.2.0',
      '[vps-bravo-01] Compiling my-lib-utils v0.4.1',
      '[vps-bravo-02] Compiling my-lib-db v2.0.0',
      '[vps-charlie-01] Compiling my-lib-api v1.1.0',
      '[vps-charlie-02] Compiling my-lib-auth v0.8.2',
      '[rch] Fleet CPU avg: 87% | 304/320 cores active',
    ],
    localTimeSec: 240,
    remoteTimeSec: 45,
    artifactsMb: 0,
  },
  {
    id: 'failure',
    label: 'Worker Failure',
    icon: AlertTriangle,
    color: 'red',
    description: 'vps-bravo-02 went offline mid-build. RCH automatically reroutes job J-004 to vps-delta-01.',
    workers: BASE_WORKERS.map((w) => {
      if (w.id === 3) return { ...w, health: 'offline' as const, cpuPct: 0, ramPct: 0, buildProgress: 42, job: 'FAILED' };
      if (w.id === 6) return { ...w, health: 'building' as const, cpuPct: 91, ramPct: 68, buildProgress: 15, job: 'my-lib-db (rerouted)' };
      if (w.id < 3) return { ...w, health: 'building' as const, cpuPct: 82 + w.id * 3, ramPct: 60 + w.id * 5, buildProgress: 60 + w.id * 8, job: ['my-service', 'my-lib-core', 'my-lib-utils'][w.id] };
      return { ...w, health: 'building' as const, cpuPct: 75 + w.id * 2, ramPct: 50 + w.id * 4, buildProgress: 55 + w.id * 5, job: ['', '', '', '', 'my-lib-api', 'my-lib-auth', '', ''][w.id] };
    }),
    buildQueue: [
      { id: 'J-001', crate: 'my-service', assignedTo: 0, status: 'building' },
      { id: 'J-002', crate: 'my-lib-core', assignedTo: 1, status: 'building' },
      { id: 'J-003', crate: 'my-lib-utils', assignedTo: 2, status: 'building' },
      { id: 'J-004', crate: 'my-lib-db', assignedTo: 6, status: 'building' },
      { id: 'J-005', crate: 'my-lib-api', assignedTo: 4, status: 'building' },
      { id: 'J-006', crate: 'my-lib-auth', assignedTo: 5, status: 'building' },
    ],
    terminalLines: [
      '[rch] WARNING: vps-bravo-02 connection lost',
      '[rch] Job J-004 (my-lib-db) failed on vps-bravo-02',
      '[rch] Failover: rerouting J-004 -> vps-delta-01',
      '[vps-delta-01] Compiling my-lib-db v2.0.0 (retry)',
      '[rch] Fleet: 7/8 workers active',
      '[rch] Estimated completion: +8s due to failover',
      '[rch] Other jobs unaffected, continuing...',
    ],
    localTimeSec: 240,
    remoteTimeSec: 53,
    artifactsMb: 0,
  },
  {
    id: 'complete',
    label: 'Build Complete',
    icon: Package,
    color: 'teal',
    description: 'All crates compiled successfully. Artifacts syncing back to local machine via zstd-compressed transfer.',
    workers: BASE_WORKERS.map((w) => {
      if (w.id === 3) return { ...w, health: 'offline' as const, cpuPct: 0, ramPct: 0, buildProgress: 0, job: 'offline' };
      return { ...w, health: 'done' as const, cpuPct: 5 + w.id, ramPct: 10 + w.id * 2, buildProgress: 100, job: 'done' };
    }),
    buildQueue: [
      { id: 'J-001', crate: 'my-service', assignedTo: 0, status: 'done' },
      { id: 'J-002', crate: 'my-lib-core', assignedTo: 1, status: 'done' },
      { id: 'J-003', crate: 'my-lib-utils', assignedTo: 2, status: 'done' },
      { id: 'J-004', crate: 'my-lib-db', assignedTo: 6, status: 'done' },
      { id: 'J-005', crate: 'my-lib-api', assignedTo: 4, status: 'done' },
      { id: 'J-006', crate: 'my-lib-auth', assignedTo: 5, status: 'done' },
    ],
    terminalLines: [
      '[rch] All 6 crates compiled successfully',
      '[rch] Syncing artifacts (87 MB) back to local...',
      '[rch] zstd compress: 87 MB -> 24 MB',
      '[rch] Transfer: 24 MB in 1.8s (13.3 MB/s)',
      '[rch] Artifacts placed in target/release/',
      '',
      'Finished `release` profile in 48.3s',
      '  (vs ~240s local estimate: 5.0x speedup)',
    ],
    localTimeSec: 240,
    remoteTimeSec: 48,
    artifactsMb: 87,
  },
  {
    id: 'healthcheck',
    label: 'Fleet Health',
    icon: Activity,
    color: 'violet',
    description: 'Running rch doctor across the fleet. All nodes checked for SSH, disk, toolchain, and daemon status.',
    workers: BASE_WORKERS.map((w) => {
      if (w.id === 3) return { ...w, health: 'offline' as const, cpuPct: 0, ramPct: 0, buildProgress: 0, job: 'unreachable', latencyMs: 9999 };
      return { ...w, health: 'online' as const, cpuPct: 3 + w.id, ramPct: 6 + w.id * 2, buildProgress: 0, job: 'healthy' };
    }),
    buildQueue: [],
    terminalLines: [
      '$ rch doctor',
      'RCH Doctor - Fleet Health Check',
      '',
      '  vps-alpha-01   OK  ssh OK  rustc 1.77  48 cores  ping 12ms',
      '  vps-alpha-02   OK  ssh OK  rustc 1.77  48 cores  ping 15ms',
      '  vps-bravo-01   OK  ssh OK  rustc 1.77  32 cores  ping 18ms',
      '  vps-bravo-02   FAIL  ssh timeout after 5s',
      '  vps-charlie-01 OK  ssh OK  rustc 1.77  16 cores  ping 24ms',
      '  vps-charlie-02 OK  ssh OK  rustc 1.77  16 cores  ping 27ms',
      '  vps-delta-01   OK  ssh OK  rustc 1.77  64 cores  ping 30ms',
      '  vps-delta-02   OK  ssh OK  rustc 1.77  64 cores  ping 33ms',
      '',
      'Fleet: 7/8 healthy | 1 unreachable',
      'Recommendation: remove or repair vps-bravo-02',
    ],
    localTimeSec: 0,
    remoteTimeSec: 0,
    artifactsMb: 0,
  },
];

// ---------------------------------------------------------------------------
// Color maps
// ---------------------------------------------------------------------------

const COLOR_MAP: Record<string, { border: string; bg: string; text: string; dot: string }> = {
  emerald: { border: 'border-emerald-400/30', bg: 'bg-emerald-500/[0.08]', text: 'text-emerald-300', dot: '#22c55e' },
  blue: { border: 'border-blue-400/30', bg: 'bg-blue-500/[0.08]', text: 'text-blue-300', dot: '#3b82f6' },
  amber: { border: 'border-amber-400/30', bg: 'bg-amber-500/[0.08]', text: 'text-amber-300', dot: '#f59e0b' },
  red: { border: 'border-red-400/30', bg: 'bg-red-500/[0.08]', text: 'text-red-300', dot: '#ef4444' },
  teal: { border: 'border-teal-400/30', bg: 'bg-teal-500/[0.08]', text: 'text-teal-300', dot: '#14b8a6' },
  violet: { border: 'border-violet-400/30', bg: 'bg-violet-500/[0.08]', text: 'text-violet-300', dot: '#8b5cf6' },
};

function healthColor(h: WorkerHealth): string {
  switch (h) {
    case 'online': return 'text-emerald-400';
    case 'building': return 'text-amber-400';
    case 'done': return 'text-teal-400';
    case 'error': return 'text-red-400';
    case 'offline': return 'text-red-500';
    case 'syncing': return 'text-blue-400';
  }
}

function healthBg(h: WorkerHealth): string {
  switch (h) {
    case 'online': return 'bg-emerald-400';
    case 'building': return 'bg-amber-400';
    case 'done': return 'bg-teal-400';
    case 'error': return 'bg-red-400';
    case 'offline': return 'bg-red-500/50';
    case 'syncing': return 'bg-blue-400';
  }
}

function healthBorder(h: WorkerHealth): string {
  switch (h) {
    case 'online': return 'border-emerald-400/30';
    case 'building': return 'border-amber-400/30';
    case 'done': return 'border-teal-400/30';
    case 'error': return 'border-red-400/30';
    case 'offline': return 'border-red-500/20';
    case 'syncing': return 'border-blue-400/30';
  }
}

function healthIcon(h: WorkerHealth) {
  switch (h) {
    case 'online': return <Wifi className="h-3 w-3 text-emerald-400" />;
    case 'building': return <Loader2 className="h-3 w-3 text-amber-400 animate-spin" />;
    case 'done': return <CheckCircle2 className="h-3 w-3 text-teal-400" />;
    case 'error': return <AlertTriangle className="h-3 w-3 text-red-400" />;
    case 'offline': return <WifiOff className="h-3 w-3 text-red-500" />;
    case 'syncing': return <Loader2 className="h-3 w-3 text-blue-400 animate-spin" />;
  }
}

function jobStatusColor(s: BuildJob['status']): string {
  switch (s) {
    case 'queued': return 'text-white/50';
    case 'building': return 'text-amber-400';
    case 'done': return 'text-emerald-400';
    case 'failed': return 'text-red-400';
  }
}

function jobStatusBg(s: BuildJob['status']): string {
  switch (s) {
    case 'queued': return 'bg-white/[0.06]';
    case 'building': return 'bg-amber-500/[0.1]';
    case 'done': return 'bg-emerald-500/[0.1]';
    case 'failed': return 'bg-red-500/[0.1]';
  }
}

// ---------------------------------------------------------------------------
// SVG Network Topology
// ---------------------------------------------------------------------------

function NetworkTopology({ scenario }: { scenario: FleetScenario }) {
  const isActive = scenario.id === 'dispatched' || scenario.id === 'compiling' || scenario.id === 'failure';
  const isReturning = scenario.id === 'complete';

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
      <div className="flex items-center gap-2 mb-2">
        <Monitor className="h-3 w-3 text-blue-400" />
        <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">Network Topology</span>
      </div>
      <svg viewBox="0 0 400 180" className="w-full" style={{ maxHeight: 180 }}>
        {/* Local machine */}
        <rect x="10" y="65" width="70" height="50" rx="8" fill="rgba(59,130,246,0.12)" stroke="rgba(59,130,246,0.3)" strokeWidth="1" />
        <text x="45" y="85" textAnchor="middle" fill="rgba(255,255,255,0.8)" fontSize="8" fontWeight="600">Local</text>
        <text x="45" y="98" textAnchor="middle" fill="rgba(255,255,255,0.4)" fontSize="6">Machine</text>

        {/* Dispatcher */}
        <rect x="140" y="65" width="70" height="50" rx="8" fill="rgba(139,92,246,0.12)" stroke="rgba(139,92,246,0.3)" strokeWidth="1" />
        <text x="175" y="85" textAnchor="middle" fill="rgba(255,255,255,0.8)" fontSize="8" fontWeight="600">RCH</text>
        <text x="175" y="98" textAnchor="middle" fill="rgba(255,255,255,0.4)" fontSize="6">Dispatcher</text>

        {/* Connection line: local -> dispatcher */}
        <line x1="80" y1="90" x2="140" y2="90" stroke="rgba(255,255,255,0.15)" strokeWidth="1" strokeDasharray="4 2" />

        {/* Animated packet: local -> dispatcher */}
        {isActive && (
          <circle r="3" fill="#3b82f6">
            <animateMotion dur="1.2s" repeatCount="indefinite" path="M 80,90 L 140,90" />
          </circle>
        )}
        {isReturning && (
          <circle r="3" fill="#14b8a6">
            <animateMotion dur="1.2s" repeatCount="indefinite" path="M 140,90 L 80,90" />
          </circle>
        )}

        {/* Worker fleet */}
        {scenario.workers.map((w, i) => {
          const col = i % 2;
          const row = Math.floor(i / 2);
          const wx = 280 + col * 58;
          const wy = 10 + row * 42;
          const isOffline = w.health === 'offline';
          const fillColor = isOffline ? 'rgba(239,68,68,0.08)' : w.health === 'building' ? 'rgba(245,158,11,0.12)' : w.health === 'done' ? 'rgba(20,184,166,0.12)' : 'rgba(255,255,255,0.04)';
          const strokeColor = isOffline ? 'rgba(239,68,68,0.3)' : w.health === 'building' ? 'rgba(245,158,11,0.3)' : w.health === 'done' ? 'rgba(20,184,166,0.3)' : 'rgba(255,255,255,0.1)';

          return (
            <g key={w.id}>
              {/* Connection: dispatcher -> worker */}
              <line x1="210" y1="90" x2={wx} y2={wy + 16} stroke={isOffline ? 'rgba(239,68,68,0.15)' : 'rgba(255,255,255,0.1)'} strokeWidth="0.5" strokeDasharray={isOffline ? '2 2' : 'none'} />

              {/* Animated packet: dispatcher -> worker */}
              {isActive && !isOffline && (
                <circle r="2" fill="#f59e0b" opacity="0.8">
                  <animateMotion dur={`${1.5 + i * 0.15}s`} repeatCount="indefinite" path={`M 210,90 L ${wx},${wy + 16}`} />
                </circle>
              )}
              {isReturning && !isOffline && (
                <circle r="2" fill="#14b8a6" opacity="0.8">
                  <animateMotion dur={`${1.2 + i * 0.1}s`} repeatCount="indefinite" path={`M ${wx},${wy + 16} L 210,90`} />
                </circle>
              )}

              {/* Worker box */}
              <rect x={wx - 24} y={wy} width="48" height="32" rx="6" fill={fillColor} stroke={strokeColor} strokeWidth="0.8" />
              <text x={wx} y={wy + 14} textAnchor="middle" fill={isOffline ? 'rgba(239,68,68,0.6)' : 'rgba(255,255,255,0.7)'} fontSize="6" fontWeight="600">
                W-{i + 1}
              </text>
              <text x={wx} y={wy + 24} textAnchor="middle" fill="rgba(255,255,255,0.35)" fontSize="5">
                {w.cpuCores}c
              </text>

              {/* Health dot */}
              <circle cx={wx + 18} cy={wy + 6} r="2.5" fill={isOffline ? '#ef4444' : w.health === 'building' ? '#f59e0b' : w.health === 'done' ? '#14b8a6' : '#22c55e'} opacity={isOffline ? 0.6 : 1}>
                {w.health === 'building' && <animate attributeName="opacity" values="1;0.4;1" dur="1.2s" repeatCount="indefinite" />}
              </circle>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Worker Card
// ---------------------------------------------------------------------------

function WorkerCard({ worker, index }: { worker: WorkerNode; index: number }) {
  const isOffline = worker.health === 'offline';

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.92 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ ...SPRING, delay: index * 0.04 }}
      className={`rounded-lg border p-2.5 transition-colors duration-300 ${healthBorder(worker.health)} ${isOffline ? 'bg-red-500/[0.03]' : 'bg-white/[0.02]'}`}
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[10px] font-bold text-white/70 font-mono truncate">{worker.name.replace('vps-', '')}</span>
        <div className="flex items-center gap-1">
          <div className={`w-1.5 h-1.5 rounded-full ${healthBg(worker.health)} ${worker.health === 'building' || worker.health === 'syncing' ? 'animate-pulse' : ''}`} />
          {healthIcon(worker.health)}
        </div>
      </div>

      {/* Host + latency */}
      <div className="text-[10px] text-white/30 font-mono mb-2 flex justify-between">
        <span>{worker.host}</span>
        <span className={isOffline ? 'text-red-400' : ''}>{isOffline ? 'timeout' : `${worker.latencyMs}ms`}</span>
      </div>

      {/* CPU bar */}
      <div className="mb-1">
        <div className="flex justify-between text-[10px] mb-0.5">
          <span className="text-white/40">CPU</span>
          <span className={`font-mono ${worker.cpuPct > 80 ? 'text-amber-400' : 'text-white/40'}`}>{worker.cpuPct}%</span>
        </div>
        <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className={`h-full rounded-full ${worker.cpuPct > 80 ? 'bg-amber-400/70' : 'bg-blue-400/50'}`}
            animate={{ width: `${worker.cpuPct}%` }}
            transition={{ duration: 0.6, ease: 'easeOut' }}
          />
        </div>
      </div>

      {/* RAM bar */}
      <div className="mb-1.5">
        <div className="flex justify-between text-[10px] mb-0.5">
          <span className="text-white/40">RAM</span>
          <span className="text-white/40 font-mono">{worker.ramPct}%</span>
        </div>
        <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className={`h-full rounded-full ${worker.ramPct > 70 ? 'bg-violet-400/60' : 'bg-emerald-400/40'}`}
            animate={{ width: `${worker.ramPct}%` }}
            transition={{ duration: 0.6, ease: 'easeOut' }}
          />
        </div>
      </div>

      {/* Build progress */}
      {worker.buildProgress > 0 && (
        <div>
          <div className="flex justify-between text-[10px] mb-0.5">
            <span className="text-white/40">Build</span>
            <span className={`font-mono ${healthColor(worker.health)}`}>{worker.buildProgress}%</span>
          </div>
          <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className={`h-full rounded-full ${worker.health === 'done' ? 'bg-teal-400/60' : worker.health === 'offline' ? 'bg-red-400/40' : 'bg-amber-400/60'}`}
              animate={{ width: `${worker.buildProgress}%` }}
              transition={{ duration: 0.4, ease: 'easeOut' }}
            />
          </div>
        </div>
      )}

      {/* Job label */}
      {worker.job && worker.job !== 'healthy' && worker.job !== 'done' && worker.job !== 'offline' && (
        <div className={`mt-1.5 text-[10px] font-mono truncate ${healthColor(worker.health)}`}>
          {worker.job === 'rsync' ? 'syncing...' : worker.job === 'FAILED' ? 'FAILED' : worker.job}
        </div>
      )}
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Build Queue
// ---------------------------------------------------------------------------

function BuildQueue({ jobs }: { jobs: BuildJob[] }) {
  if (jobs.length === 0) {
    return (
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
        <div className="flex items-center gap-2 mb-2">
          <HardDrive className="h-3 w-3 text-white/40" />
          <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">Build Queue</span>
        </div>
        <p className="text-[10px] text-white/30 italic">No jobs in queue</p>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
      <div className="flex items-center gap-2 mb-2">
        <HardDrive className="h-3 w-3 text-amber-400" />
        <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">Build Queue</span>
        <span className="ml-auto text-[10px] text-white/30 font-mono">{jobs.length} jobs</span>
      </div>
      <div className="space-y-1">
        {jobs.map((job, i) => (
          <motion.div
            key={job.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ ...SPRING, delay: i * 0.05 }}
            className={`flex items-center gap-2 px-2 py-1 rounded-md text-[10px] font-mono ${jobStatusBg(job.status)}`}
          >
            <span className="text-white/40 w-10 flex-shrink-0">{job.id}</span>
            <span className={`flex-1 truncate ${jobStatusColor(job.status)}`}>{job.crate}</span>
            {job.assignedTo !== null && (
              <span className="text-white/30 flex-shrink-0">W-{job.assignedTo + 1}</span>
            )}
            <span className={`flex-shrink-0 ${jobStatusColor(job.status)}`}>
              {job.status === 'queued' && 'queued'}
              {job.status === 'building' && 'building'}
              {job.status === 'done' && 'done'}
              {job.status === 'failed' && 'failed'}
            </span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Build Time Comparison
// ---------------------------------------------------------------------------

function BuildTimeComparison({ localSec, remoteSec }: { localSec: number; remoteSec: number }) {
  if (localSec === 0 || remoteSec === 0) return null;

  const speedup = (localSec / remoteSec).toFixed(1);
  const remoteWidthPct = (remoteSec / localSec) * 100;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3">
      <div className="flex items-center gap-2 mb-3">
        <Clock className="h-3 w-3 text-emerald-400" />
        <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">Build Time Comparison</span>
        <span className="ml-auto text-[10px] font-bold text-emerald-400">{speedup}x faster</span>
      </div>
      <div className="space-y-2">
        {/* Local */}
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-mono text-white/40 w-12 flex-shrink-0">Local</span>
          <div className="flex-1 h-5 rounded-md bg-white/[0.04] border border-white/[0.06] overflow-hidden relative">
            <motion.div
              className="h-full bg-gradient-to-r from-red-500/40 to-orange-500/40 rounded-md"
              initial={{ width: '0%' }}
              animate={{ width: '100%' }}
              transition={{ duration: 1.5, ease: 'easeOut' }}
            />
            <span className="absolute inset-0 flex items-center justify-center text-[10px] font-bold text-white/70">
              {Math.floor(localSec / 60)}m {localSec % 60}s
            </span>
          </div>
        </div>
        {/* Remote */}
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-mono text-emerald-400/80 w-12 flex-shrink-0">RCH</span>
          <div className="flex-1 h-5 rounded-md bg-white/[0.04] border border-white/[0.06] overflow-hidden relative">
            <motion.div
              className="h-full bg-gradient-to-r from-emerald-500/50 to-teal-500/50 rounded-md"
              initial={{ width: '0%' }}
              animate={{ width: `${remoteWidthPct}%` }}
              transition={{ duration: 0.8, ease: 'easeOut', delay: 0.3 }}
            />
            <span className="absolute left-0 inset-y-0 flex items-center pl-2 text-[10px] font-bold text-emerald-300/90">
              {remoteSec}s
            </span>
          </div>
        </div>
      </div>
      <div className="mt-2 flex items-center gap-1.5 text-xs text-white/35">
        <Zap className="h-2.5 w-2.5 text-emerald-400" />
        <span>8 workers, 320 total CPU cores vs 8-core local machine</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Artifact Transfer
// ---------------------------------------------------------------------------

function ArtifactTransfer({ mb }: { mb: number }) {
  if (mb === 0) return null;

  return (
    <div className="rounded-xl border border-teal-400/20 bg-teal-500/[0.04] p-3">
      <div className="flex items-center gap-2 mb-2">
        <Package className="h-3 w-3 text-teal-400" />
        <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">Artifact Sync</span>
      </div>
      <div className="flex items-center gap-3">
        <div className="flex-1">
          <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className="h-full rounded-full bg-gradient-to-r from-teal-400/60 to-emerald-400/60"
              initial={{ width: '0%' }}
              animate={{ width: '100%' }}
              transition={{ duration: 1.5, ease: 'easeOut' }}
            />
          </div>
        </div>
        <span className="text-[10px] font-mono text-teal-300">{mb} MB</span>
      </div>
      <div className="mt-1.5 flex items-center gap-4 text-[10px] text-white/30 font-mono">
        <span>zstd: {mb} MB -&gt; {Math.round(mb * 0.28)} MB</span>
        <span>1.8s transfer</span>
        <span>13.3 MB/s</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Mini Terminal
// ---------------------------------------------------------------------------

function MiniTerminal({ lines }: { lines: string[] }) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [lines]);

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-1.5 px-3 py-1.5 bg-white/[0.03] border-b border-white/[0.06]">
        <div className="w-2 h-2 rounded-full bg-red-400/60" />
        <div className="w-2 h-2 rounded-full bg-amber-400/60" />
        <div className="w-2 h-2 rounded-full bg-emerald-400/60" />
        <span className="ml-2 text-[10px] text-white/40 font-mono">rch terminal</span>
      </div>
      <div ref={scrollRef} className="p-3 max-h-40 overflow-y-auto">
        <AnimatePresence mode="sync">
          {lines.map((line, i) => (
            <motion.div
              key={`${i}-${line}`}
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2, delay: i * 0.03 }}
              className={`text-[10px] font-mono leading-relaxed ${
                line.startsWith('$') ? 'text-emerald-400' :
                line.includes('WARNING') || line.includes('FAIL') ? 'text-red-400' :
                line.includes('OK') || line.includes('success') || line.includes('Finished') ? 'text-emerald-300/80' :
                line.includes('[rch]') ? 'text-blue-300/70' :
                line.includes('[vps-') ? 'text-amber-300/60' :
                line === '' ? '' :
                'text-white/50'
              }`}
            >
              {line || '\u00A0'}
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Dashboard Component
// ---------------------------------------------------------------------------

function InteractiveFleetDashboard() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const scenario = SCENARIOS[scenarioIdx];
  const colors = COLOR_MAP[scenario.color] ?? COLOR_MAP.emerald;
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });

  const handleStepBack = useCallback(() => {
    setScenarioIdx((prev) => (prev > 0 ? prev - 1 : SCENARIOS.length - 1));
  }, []);

  const handleStepForward = useCallback(() => {
    setScenarioIdx((prev) => (prev < SCENARIOS.length - 1 ? prev + 1 : 0));
  }, []);

  const handleSelectScenario = useCallback((i: number) => {
    setScenarioIdx(i);
  }, []);

  // Fleet summary stats
  const onlineCount = scenario.workers.filter((w) => w.health !== 'offline').length;
  const totalCores = scenario.workers.reduce((sum, w) => sum + (w.health !== 'offline' ? w.cpuCores : 0), 0);
  const activeBuildCount = scenario.workers.filter((w) => w.health === 'building' || w.health === 'syncing').length;
  const avgCpu = scenario.workers.length > 0
    ? Math.round(scenario.workers.reduce((s, w) => s + w.cpuPct, 0) / scenario.workers.length)
    : 0;

  return (
    <div ref={ref} className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-blue-500/[0.06] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/[0.06] rounded-full blur-3xl pointer-events-none" />

      {/* Scenario-based border flash */}
      <AnimatePresence>
        {scenario.id === 'failure' && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={inView ? { opacity: [0, 0.4, 0] } : { opacity: 0 }}
            exit={{ opacity: 0 }}
            transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
            className="absolute inset-0 bg-red-500/10 rounded-2xl pointer-events-none z-10"
          />
        )}
      </AnimatePresence>

      <div className="relative p-5 sm:p-6 space-y-4">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="flex items-center justify-center gap-2">
            <Sparkles className="h-4 w-4 text-blue-400" />
            <p className="text-sm font-semibold text-white/90">Compilation Fleet Dashboard</p>
            <Sparkles className="h-4 w-4 text-blue-400" />
          </div>
          <p className="text-xs text-white/50">
            Step through scenarios to see how RCH manages remote compilation across a worker fleet
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
                  className={`rounded-xl border px-2 py-1.5 text-[10px] font-medium transition-colors flex items-center gap-1 ${
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
          {SCENARIOS.map((_, i) => (
            <motion.div
              key={i}
              animate={{
                scale: scenarioIdx === i ? 1.4 : 1,
                backgroundColor: scenarioIdx === i ? (COLOR_MAP[SCENARIOS[i].color]?.dot ?? '#3b82f6') : 'rgba(255,255,255,0.15)',
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

        {/* Fleet summary bar */}
        <div className="flex flex-wrap items-center justify-center gap-3 sm:gap-6 text-[10px] font-mono">
          <div className="flex items-center gap-1.5">
            <Server className="h-3 w-3 text-emerald-400" />
            <span className="text-white/50">Fleet:</span>
            <span className="text-emerald-400 font-bold">{onlineCount}/8</span>
          </div>
          <div className="flex items-center gap-1.5">
            <Cpu className="h-3 w-3 text-blue-400" />
            <span className="text-white/50">Cores:</span>
            <span className="text-blue-400 font-bold">{totalCores}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <Activity className="h-3 w-3 text-amber-400" />
            <span className="text-white/50">Active:</span>
            <span className="text-amber-400 font-bold">{activeBuildCount}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <Zap className="h-3 w-3 text-violet-400" />
            <span className="text-white/50">Avg CPU:</span>
            <span className="text-violet-400 font-bold">{avgCpu}%</span>
          </div>
        </div>

        {/* Main grid: SVG topology + worker grid */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.25 }}
          >
            {/* Network topology */}
            <NetworkTopology scenario={scenario} />

            {/* Worker grid: 8 cards in 4x2 */}
            <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-2">
              {scenario.workers.map((w, idx) => (
                <WorkerCard key={w.id} worker={w} index={idx} />
              ))}
            </div>

            {/* Lower section: queue + terminal side by side */}
            <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-3">
              <BuildQueue jobs={scenario.buildQueue} />
              <MiniTerminal lines={scenario.terminalLines} />
            </div>

            {/* Build time comparison (only for scenarios with timing data) */}
            <div className="mt-3">
              <BuildTimeComparison localSec={scenario.localTimeSec} remoteSec={scenario.remoteTimeSec} />
            </div>

            {/* Artifact transfer (only for complete scenario) */}
            <div className="mt-3">
              <ArtifactTransfer mb={scenario.artifactsMb} />
            </div>
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
