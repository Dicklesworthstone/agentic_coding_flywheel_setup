'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { motion, AnimatePresence, springs, useInView } from '@/components/motion';
import {
  Terminal,
  Activity,
  Search,
  Shield,
  Play,
  AlertTriangle,
  Skull,
  CheckCircle,
  XCircle,
  Crosshair,
  RotateCcw,
  ChevronLeft,
  ChevronRight,
  Cpu,
  HardDrive,
  Zap,
  TreePine,
  Gauge,
  Flame,
  Ghost,
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

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

export function PtLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master intelligent process management with Process Triage.
      </GoalBanner>

      {/* Section 1: What Is PT */}
      <Section title="What Is Process Triage?" icon={<Activity className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>PT (Process Triage)</Highlight> identifies and terminates abandoned or
          zombie processes using a Bayesian-inspired scoring algorithm. It evaluates process type,
          age, orphan status, and resource usage to calculate abandonment probability.
        </Paragraph>
        <Paragraph>
          PT remembers your kill/spare decisions for similar processes, improving recommendations
          over time. It requires explicit confirmation and attempts graceful SIGTERM first.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Smart Search"
              description="Find processes by name, PID, or resource usage"
              gradient="from-lime-500/20 to-green-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="Resource Analysis"
              description="See CPU, memory, and I/O at a glance"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<AlertTriangle className="h-5 w-5" />}
              title="Problem Detection"
              description="Identify runaway and zombie processes"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safe Actions"
              description="Signal processes with confirmation"
              gradient="from-red-500/20 to-rose-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Interactive Process Triage Dashboard */}
      <Section title="Try It: Process Triage Dashboard" icon={<Crosshair className="h-5 w-5" />} delay={0.15}>
        <InteractiveProcessTriageDashboard />
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'pt', description: 'Show process overview' },
            { command: 'pt --top', description: 'Show top resource consumers' },
            { command: 'pt search <name>', description: 'Find processes by name' },
            { command: 'pt --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          PT is useful when agents need to diagnose why builds are slow or what&apos;s consuming resources.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Find what's using CPU
pt --top

# Search for node processes
pt search node

# Find processes using port 3000
pt --port 3000`} />
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Types & Data
// ---------------------------------------------------------------------------

interface SimProcess {
  pid: number;
  ppid: number;
  name: string;
  cpu: number;
  memory: number;
  ioRead: number;
  ioWrite: number;
  state: 'running' | 'sleeping' | 'zombie' | 'disk-wait';
  uptime: string;
  dangerScore: number;
  verdict: 'safe' | 'suspicious' | 'kill';
  reason: string;
}

interface SystemResources {
  cpuCores: number;
  cpuUsage: number;
  ramTotal: number;
  ramUsed: number;
  swapTotal: number;
  swapUsed: number;
  loadAvg: [number, number, number];
  diskRead: number;
  diskWrite: number;
}

interface Scenario {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  terminalLines: string[];
  processes: SimProcess[];
  resources: SystemResources;
}

const SCENARIOS: Scenario[] = [
  {
    id: 'normal',
    label: 'Normal System',
    icon: <CheckCircle className="h-4 w-4" />,
    description: 'Healthy system with typical development workloads. All processes within expected ranges.',
    terminalLines: [
      '$ pt --top',
      'Process Triage v2.4 -- scanning 147 processes',
      'System load: 1.24 (healthy)',
      '',
      'All processes nominal. No action needed.',
    ],
    processes: [
      { pid: 1, ppid: 0, name: 'systemd', cpu: 0.1, memory: 12, ioRead: 0, ioWrite: 0.5, state: 'sleeping', uptime: '14d 3h', dangerScore: 0.01, verdict: 'safe', reason: 'System init process. Protected.' },
      { pid: 1842, ppid: 1, name: 'node (next-dev)', cpu: 8.3, memory: 284, ioRead: 2.1, ioWrite: 0.8, state: 'running', uptime: '2h 15m', dangerScore: 0.1, verdict: 'safe', reason: 'Active dev server with recent file watch activity.' },
      { pid: 2201, ppid: 1, name: 'postgres', cpu: 2.1, memory: 156, ioRead: 5.2, ioWrite: 3.1, state: 'sleeping', uptime: '14d 3h', dangerScore: 0.05, verdict: 'safe', reason: 'Database service. Active connections detected.' },
      { pid: 3384, ppid: 1842, name: 'claude-agent', cpu: 14.7, memory: 512, ioRead: 1.8, ioWrite: 4.2, state: 'running', uptime: '45m', dangerScore: 0.08, verdict: 'safe', reason: 'AI agent actively processing. IPC heartbeat OK.' },
      { pid: 4100, ppid: 1, name: 'sshd', cpu: 0.0, memory: 8, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '14d 3h', dangerScore: 0.02, verdict: 'safe', reason: 'SSH daemon. System service.' },
      { pid: 5500, ppid: 1842, name: 'typescript-lsp', cpu: 3.2, memory: 220, ioRead: 0.4, ioWrite: 0.1, state: 'running', uptime: '2h 14m', dangerScore: 0.06, verdict: 'safe', reason: 'Language server supporting IDE. Child of dev server.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 28, ramTotal: 16384, ramUsed: 5200, swapTotal: 4096, swapUsed: 128, loadAvg: [1.24, 1.1, 0.98], diskRead: 9.5, diskWrite: 8.7 },
  },
  {
    id: 'runaway-cargo',
    label: 'Runaway Build',
    icon: <Flame className="h-4 w-4" />,
    description: 'A cargo build process is consuming all CPU cores and thrashing swap.',
    terminalLines: [
      '$ pt --top',
      'Process Triage v2.4 -- scanning 203 processes',
      '\x1b[31m!! WARNING: CPU saturation detected (98.7%)\x1b[0m',
      '\x1b[33m!! SWAP pressure: 87% utilized\x1b[0m',
      '',
      'Top offender: PID 6601 cargo (94.2% CPU, 6.8G RAM)',
      'Recommendation: KILL -- build running 3h47m (expected <20m)',
    ],
    processes: [
      { pid: 1, ppid: 0, name: 'systemd', cpu: 0.1, memory: 12, ioRead: 0, ioWrite: 0.2, state: 'sleeping', uptime: '14d 3h', dangerScore: 0.01, verdict: 'safe', reason: 'System init. Protected.' },
      { pid: 6601, ppid: 6600, name: 'cargo build', cpu: 94.2, memory: 6800, ioRead: 45.0, ioWrite: 120.0, state: 'running', uptime: '3h 47m', dangerScore: 0.92, verdict: 'kill', reason: 'Runaway build. 3h47m runtime (expected <20min). All cores saturated. System unresponsive.' },
      { pid: 6605, ppid: 6601, name: 'rustc (proc-macro)', cpu: 47.1, memory: 2400, ioRead: 12.0, ioWrite: 55.0, state: 'running', uptime: '3h 46m', dangerScore: 0.88, verdict: 'kill', reason: 'Child of runaway cargo. Proc-macro expansion stuck in loop.' },
      { pid: 6608, ppid: 6601, name: 'cc1plus (linker)', cpu: 38.5, memory: 1800, ioRead: 8.0, ioWrite: 40.0, state: 'disk-wait', uptime: '2h 10m', dangerScore: 0.85, verdict: 'kill', reason: 'Linker thrashing. Writing heavily to swap.' },
      { pid: 1842, ppid: 1, name: 'node (next-dev)', cpu: 0.3, memory: 284, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '6h 15m', dangerScore: 0.12, verdict: 'safe', reason: 'Dev server starved but alive. Will recover after kill.' },
      { pid: 3384, ppid: 1842, name: 'claude-agent', cpu: 0.1, memory: 512, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '45m', dangerScore: 0.15, verdict: 'safe', reason: 'Agent waiting on I/O. Will resume after load drops.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 98.7, ramTotal: 16384, ramUsed: 14800, swapTotal: 4096, swapUsed: 3565, loadAvg: [12.4, 10.8, 8.2], diskRead: 65.0, diskWrite: 215.0 },
  },
  {
    id: 'memory-leak',
    label: 'Memory Leak',
    icon: <Zap className="h-4 w-4" />,
    description: 'A Node.js process has a memory leak, slowly consuming all available RAM.',
    terminalLines: [
      '$ pt search node',
      'Process Triage v2.4 -- 3 matches for "node"',
      '',
      '\x1b[33m!! PID 2900: Memory growing 120MB/hour\x1b[0m',
      'Current: 4.2G (started at 280M, 18h ago)',
      'Recommendation: SUSPICIOUS -- likely memory leak',
    ],
    processes: [
      { pid: 1, ppid: 0, name: 'systemd', cpu: 0.1, memory: 12, ioRead: 0, ioWrite: 0.2, state: 'sleeping', uptime: '14d 3h', dangerScore: 0.01, verdict: 'safe', reason: 'System init. Protected.' },
      { pid: 2900, ppid: 1, name: 'node (api-server)', cpu: 22.5, memory: 4300, ioRead: 0.8, ioWrite: 0.3, state: 'running', uptime: '18h 22m', dangerScore: 0.78, verdict: 'suspicious', reason: 'Memory grew from 280M to 4.3G over 18h. Growth rate: ~120MB/hr. Classic leak pattern.' },
      { pid: 2950, ppid: 2900, name: 'node (worker-1)', cpu: 8.0, memory: 1200, ioRead: 0.3, ioWrite: 0.1, state: 'running', uptime: '18h 22m', dangerScore: 0.65, verdict: 'suspicious', reason: 'Worker thread inheriting leak. Shared heap.' },
      { pid: 2951, ppid: 2900, name: 'node (worker-2)', cpu: 7.8, memory: 1180, ioRead: 0.3, ioWrite: 0.1, state: 'running', uptime: '18h 22m', dangerScore: 0.64, verdict: 'suspicious', reason: 'Worker thread inheriting leak. Shared heap.' },
      { pid: 1842, ppid: 1, name: 'node (next-dev)', cpu: 5.1, memory: 310, ioRead: 1.2, ioWrite: 0.5, state: 'running', uptime: '6h', dangerScore: 0.08, verdict: 'safe', reason: 'Stable memory footprint. Normal dev server.' },
      { pid: 2201, ppid: 1, name: 'postgres', cpu: 4.5, memory: 280, ioRead: 8.0, ioWrite: 5.0, state: 'running', uptime: '14d 3h', dangerScore: 0.05, verdict: 'safe', reason: 'Database under higher load from leaky app queries.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 48, ramTotal: 16384, ramUsed: 12800, swapTotal: 4096, swapUsed: 1200, loadAvg: [3.2, 3.8, 3.5], diskRead: 10.6, diskWrite: 6.1 },
  },
  {
    id: 'zombies',
    label: 'Zombie Horde',
    icon: <Ghost className="h-4 w-4" />,
    description: 'Multiple zombie processes left behind by crashed parent scripts.',
    terminalLines: [
      '$ pt',
      'Process Triage v2.4 -- scanning 189 processes',
      '\x1b[31m!! 4 zombie processes detected\x1b[0m',
      '\x1b[33m!! 2 orphaned processes found\x1b[0m',
      '',
      'Zombies cannot be killed directly.',
      'Killing parent PID 7000 (bash) will reap them.',
    ],
    processes: [
      { pid: 7000, ppid: 1, name: 'bash (deploy.sh)', cpu: 0.0, memory: 8, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '2d 4h', dangerScore: 0.82, verdict: 'kill', reason: 'Crashed deploy script still holding zombie children. Kill to reap.' },
      { pid: 7001, ppid: 7000, name: 'curl <defunct>', cpu: 0.0, memory: 0, ioRead: 0, ioWrite: 0, state: 'zombie', uptime: '2d 4h', dangerScore: 0.95, verdict: 'kill', reason: 'Zombie. Parent 7000 not calling wait(). Kill parent to reap.' },
      { pid: 7002, ppid: 7000, name: 'python3 <defunct>', cpu: 0.0, memory: 0, ioRead: 0, ioWrite: 0, state: 'zombie', uptime: '2d 4h', dangerScore: 0.95, verdict: 'kill', reason: 'Zombie. Cannot be killed directly, must reap via parent.' },
      { pid: 7003, ppid: 7000, name: 'grep <defunct>', cpu: 0.0, memory: 0, ioRead: 0, ioWrite: 0, state: 'zombie', uptime: '2d 4h', dangerScore: 0.95, verdict: 'kill', reason: 'Zombie. Slot wasted in process table.' },
      { pid: 5519, ppid: 1, name: 'sleep 99999', cpu: 0.0, memory: 2, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '5d 11h', dangerScore: 0.88, verdict: 'kill', reason: 'Orphaned sleep. No session. Leftover from terminated script.' },
      { pid: 5520, ppid: 1, name: 'tail -f /dev/null', cpu: 0.0, memory: 1, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '5d 11h', dangerScore: 0.86, verdict: 'kill', reason: 'Orphaned tail. Reparented to init. No useful work.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 15, ramTotal: 16384, ramUsed: 4100, swapTotal: 4096, swapUsed: 64, loadAvg: [0.8, 0.9, 0.7], diskRead: 2.1, diskWrite: 1.5 },
  },
  {
    id: 'disk-io',
    label: 'Disk I/O Bottleneck',
    icon: <HardDrive className="h-4 w-4" />,
    description: 'Saturated disk I/O from concurrent heavy writes blocking all processes.',
    terminalLines: [
      '$ pt --top',
      'Process Triage v2.4 -- scanning 156 processes',
      '\x1b[31m!! Disk I/O saturated: 450MB/s write\x1b[0m',
      '\x1b[33m!! 8 processes in D (disk-wait) state\x1b[0m',
      '',
      'Top I/O: PID 8100 rsync (220MB/s write)',
      'Recommendation: Throttle or reschedule large transfers',
    ],
    processes: [
      { pid: 8100, ppid: 1, name: 'rsync (backup)', cpu: 15.0, memory: 340, ioRead: 180.0, ioWrite: 220.0, state: 'disk-wait', uptime: '1h 30m', dangerScore: 0.7, verdict: 'suspicious', reason: 'Massive I/O transfer saturating disk. Consider ionice or rescheduling.' },
      { pid: 8200, ppid: 1, name: 'docker (pull)', cpu: 5.0, memory: 450, ioRead: 90.0, ioWrite: 150.0, state: 'disk-wait', uptime: '25m', dangerScore: 0.6, verdict: 'suspicious', reason: 'Docker pull competing for I/O. Multiple layers extracting concurrently.' },
      { pid: 1842, ppid: 1, name: 'node (next-dev)', cpu: 1.2, memory: 290, ioRead: 0.5, ioWrite: 0.1, state: 'disk-wait', uptime: '6h', dangerScore: 0.15, verdict: 'safe', reason: 'Blocked on I/O. Will resume when disk pressure drops.' },
      { pid: 2201, ppid: 1, name: 'postgres', cpu: 8.5, memory: 600, ioRead: 40.0, ioWrite: 65.0, state: 'disk-wait', uptime: '14d', dangerScore: 0.35, verdict: 'safe', reason: 'WAL writes delayed. May cause query timeouts but is self-recovering.' },
      { pid: 8300, ppid: 8200, name: 'unpigz', cpu: 25.0, memory: 80, ioRead: 60.0, ioWrite: 0, state: 'running', uptime: '20m', dangerScore: 0.5, verdict: 'suspicious', reason: 'Decompression using all cores, feeding disk write pipeline.' },
      { pid: 3384, ppid: 1842, name: 'claude-agent', cpu: 0.5, memory: 512, ioRead: 0.2, ioWrite: 0.1, state: 'sleeping', uptime: '45m', dangerScore: 0.1, verdict: 'safe', reason: 'Agent idle, waiting for dev server response.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 55, ramTotal: 16384, ramUsed: 8900, swapTotal: 4096, swapUsed: 200, loadAvg: [6.8, 5.2, 3.1], diskRead: 370.0, diskWrite: 450.0 },
  },
  {
    id: 'triage-kill',
    label: 'Triage & Kill',
    icon: <Skull className="h-4 w-4" />,
    description: 'Practice the full triage workflow: identify, score, confirm, and kill problematic processes.',
    terminalLines: [
      '$ pt',
      'Process Triage v2.4 -- scanning 167 processes',
      '\x1b[31m!! 2 processes recommended for termination\x1b[0m',
      '\x1b[33m!! 1 suspicious process flagged\x1b[0m',
      '',
      '$ pt kill 7720',
      'Send SIGTERM to PID 7720 (npm install)? [y/N] y',
      'SIGTERM sent. Waiting 5s for graceful exit...',
      'Process 7720 terminated.',
    ],
    processes: [
      { pid: 1842, ppid: 1, name: 'node (next-dev)', cpu: 12.3, memory: 284, ioRead: 2.0, ioWrite: 0.8, state: 'running', uptime: '2h', dangerScore: 0.1, verdict: 'safe', reason: 'Active dev server. Recently accessed filesystem.' },
      { pid: 7720, ppid: 1, name: 'npm install', cpu: 88.2, memory: 1740, ioRead: 25.0, ioWrite: 45.0, state: 'running', uptime: '47m', dangerScore: 0.82, verdict: 'kill', reason: 'Running 47 minutes (expected <5min). Likely hung on network or lock.' },
      { pid: 9471, ppid: 1, name: 'python3 <defunct>', cpu: 0.0, memory: 0, ioRead: 0, ioWrite: 0, state: 'zombie', uptime: '3d 8h', dangerScore: 0.95, verdict: 'kill', reason: 'Zombie process. Parent exited without wait(). Wasting PID slot.' },
      { pid: 3384, ppid: 1842, name: 'claude-agent', cpu: 34.7, memory: 512, ioRead: 1.5, ioWrite: 3.8, state: 'running', uptime: '45m', dangerScore: 0.08, verdict: 'safe', reason: 'Actively processing. IPC heartbeat every 2s. High CPU expected.' },
      { pid: 5519, ppid: 1, name: 'sleep 99999', cpu: 0.0, memory: 2, ioRead: 0, ioWrite: 0, state: 'sleeping', uptime: '5d', dangerScore: 0.88, verdict: 'kill', reason: 'Orphaned sleep. No parent, no session. Leftover garbage.' },
      { pid: 2201, ppid: 1, name: 'postgres', cpu: 2.1, memory: 156, ioRead: 5.0, ioWrite: 3.0, state: 'sleeping', uptime: '14d', dangerScore: 0.05, verdict: 'safe', reason: 'Protected system service. Active connections.' },
    ],
    resources: { cpuCores: 8, cpuUsage: 62, ramTotal: 16384, ramUsed: 8200, swapTotal: 4096, swapUsed: 512, loadAvg: [4.2, 3.5, 2.8], diskRead: 33.5, diskWrite: 52.6 },
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getDangerColor(score: number): string {
  if (score >= 0.7) return 'bg-red-500';
  if (score >= 0.4) return 'bg-amber-500';
  return 'bg-emerald-500';
}

function getDangerTextColor(score: number): string {
  if (score >= 0.7) return 'text-red-400';
  if (score >= 0.4) return 'text-amber-400';
  return 'text-emerald-400';
}

function getStateColor(state: SimProcess['state']): string {
  switch (state) {
    case 'running': return 'text-emerald-400';
    case 'sleeping': return 'text-blue-400';
    case 'zombie': return 'text-red-400';
    case 'disk-wait': return 'text-amber-400';
  }
}

function getStateLabel(state: SimProcess['state']): string {
  switch (state) {
    case 'running': return 'R';
    case 'sleeping': return 'S';
    case 'zombie': return 'Z';
    case 'disk-wait': return 'D';
  }
}

function formatMem(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)}G`;
  return `${mb}M`;
}

function formatIO(mbps: number): string {
  if (mbps >= 100) return `${mbps.toFixed(0)}`;
  if (mbps >= 1) return `${mbps.toFixed(1)}`;
  return `${mbps.toFixed(2)}`;
}

function getGaugeColor(pct: number): string {
  if (pct >= 90) return '#ef4444';
  if (pct >= 70) return '#f59e0b';
  return '#10b981';
}

// ---------------------------------------------------------------------------
// Resource Gauge SVG
// ---------------------------------------------------------------------------

function ResourceGauge({ label, value, max, unit, icon }: {
  label: string;
  value: number;
  max: number;
  unit: string;
  icon: React.ReactNode;
}) {
  const pct = Math.min((value / max) * 100, 100);
  const radius = 32;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (pct / 100) * circumference;
  const color = getGaugeColor(pct);

  return (
    <div className="flex flex-col items-center gap-1.5">
      <div className="relative w-20 h-20">
        <svg viewBox="0 0 80 80" className="w-full h-full -rotate-90">
          <circle cx="40" cy="40" r={radius} fill="none" stroke="white" strokeOpacity={0.06} strokeWidth={6} />
          <motion.circle
            cx="40" cy="40" r={radius} fill="none"
            stroke={color}
            strokeWidth={6}
            strokeLinecap="round"
            strokeDasharray={circumference}
            initial={{ strokeDashoffset: circumference }}
            animate={{ strokeDashoffset }}
            transition={SPRING}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-white/40">{icon}</span>
          <span className="text-xs font-mono font-bold text-white/80 mt-0.5">{pct.toFixed(0)}%</span>
        </div>
      </div>
      <div className="text-center">
        <div className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">{label}</div>
        <div className="text-[10px] font-mono text-white/30">{formatMem(value)}/{formatMem(max)} {unit}</div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Process Tree
// ---------------------------------------------------------------------------

function ProcessTree({ processes }: { processes: SimProcess[] }) {
  const roots = processes.filter(p => !processes.some(pp => pp.pid === p.ppid));
  const children = (ppid: number) => processes.filter(p => p.ppid === ppid && p.pid !== ppid);

  return (
    <div className="space-y-1 font-mono text-[11px]">
      {roots.map(root => (
        <div key={root.pid}>
          <div className="flex items-center gap-2">
            <span className={`font-bold ${getStateColor(root.state)}`}>{getStateLabel(root.state)}</span>
            <span className="text-white/40">{root.pid}</span>
            <span className="text-white/70">{root.name}</span>
          </div>
          {children(root.pid).map((child, ci) => {
            const isLast = ci === children(root.pid).length - 1;
            return (
              <motion.div
                key={child.pid}
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ ...SPRING, delay: ci * 0.05 }}
                className="flex items-center gap-2 ml-4"
              >
                <span className="text-white/20">{isLast ? '\u2514\u2500' : '\u251C\u2500'}</span>
                <span className={`font-bold ${getStateColor(child.state)}`}>{getStateLabel(child.state)}</span>
                <span className="text-white/40">{child.pid}</span>
                <span className="text-white/60">{child.name}</span>
              </motion.div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Mini Terminal
// ---------------------------------------------------------------------------

function MiniTerminal({ lines }: { lines: string[] }) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-1.5 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="w-2.5 h-2.5 rounded-full bg-red-500/60" />
        <div className="w-2.5 h-2.5 rounded-full bg-amber-500/60" />
        <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/60" />
        <span className="text-[10px] text-white/30 ml-2 font-mono">terminal</span>
      </div>
      <div className="p-3 space-y-0.5 max-h-44 overflow-y-auto">
        {lines.map((line, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -6 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ ...SPRING, delay: i * 0.08 }}
            className={`font-mono text-[11px] leading-relaxed ${
              line.startsWith('$') ? 'text-emerald-400' :
              line.includes('!!') || line.includes('WARNING') ? 'text-red-400' :
              line.includes('Recommendation') ? 'text-amber-300' :
              line.includes('terminated') || line.includes('nominal') ? 'text-emerald-400' :
              'text-white/50'
            }`}
          >
            {line || '\u00A0'}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// CPU/Memory Bar
// ---------------------------------------------------------------------------

function UsageBar({ value, max, color, pulse }: {
  value: number;
  max: number;
  color: string;
  pulse?: boolean;
}) {
  const pct = Math.min((value / max) * 100, 100);
  return (
    <div className="flex items-center gap-1.5 w-full">
      <div className="flex-1 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${color}`}
          initial={{ width: '0%' }}
          animate={{ width: `${pct}%` }}
          transition={SPRING}
          style={pulse ? { animation: 'pulse 1.5s cubic-bezier(0.4,0,0.6,1) infinite' } : undefined}
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Kill Confirmation Dialog
// ---------------------------------------------------------------------------

function KillDialog({ proc, onConfirm, onCancel }: {
  proc: SimProcess;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.95 }}
      transition={SPRING}
      className="absolute inset-0 z-20 flex items-center justify-center bg-black/60 backdrop-blur-sm rounded-3xl"
    >
      <motion.div
        initial={{ y: 20 }}
        animate={{ y: 0 }}
        transition={SPRING}
        className="mx-4 max-w-sm w-full rounded-2xl border border-red-500/30 bg-gradient-to-b from-red-950/80 to-black/90 p-6 shadow-2xl shadow-red-500/10"
      >
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-xl bg-red-500/20 border border-red-500/30 flex items-center justify-center">
            <Skull className="h-5 w-5 text-red-400" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-red-300">Kill Process?</h4>
            <p className="text-xs text-white/40">This action cannot be undone</p>
          </div>
        </div>

        <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 mb-4 space-y-1">
          <div className="flex justify-between text-xs">
            <span className="text-white/40">PID</span>
            <span className="font-mono text-white/70">{proc.pid}</span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-white/40">Process</span>
            <span className="font-mono text-white/70">{proc.name}</span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-white/40">Signal</span>
            <span className="font-mono text-amber-400">SIGTERM (15)</span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-white/40">Fallback</span>
            <span className="font-mono text-red-400">SIGKILL (9) after 5s</span>
          </div>
        </div>

        {proc.state === 'zombie' && (
          <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-2.5 mb-4 flex items-start gap-2">
            <AlertTriangle className="h-3.5 w-3.5 text-amber-400 mt-0.5 shrink-0" />
            <p className="text-xs text-amber-300/80 leading-relaxed">
              Zombie processes cannot be killed directly. PT will signal the parent process (PID {proc.ppid}) instead.
            </p>
          </div>
        )}

        <div className="flex gap-2">
          <motion.button
            type="button"
            onClick={onCancel}
            whileHover={{ scale: 1.03 }}
            whileTap={{ scale: 0.97 }}
            transition={SPRING}
            className="flex-1 py-2 rounded-xl border border-white/[0.08] bg-white/[0.04] text-xs text-white/50 hover:bg-white/[0.08] transition-colors"
          >
            Cancel
          </motion.button>
          <motion.button
            type="button"
            onClick={onConfirm}
            whileHover={{ scale: 1.03 }}
            whileTap={{ scale: 0.97 }}
            transition={SPRING}
            className="flex-1 py-2 rounded-xl border border-red-500/30 bg-red-500/20 text-xs text-red-300 font-semibold hover:bg-red-500/30 transition-colors flex items-center justify-center gap-1.5"
          >
            <Skull className="h-3.5 w-3.5" />
            Confirm Kill
          </motion.button>
        </div>
      </motion.div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Main Interactive Dashboard
// ---------------------------------------------------------------------------

function InteractiveProcessTriageDashboard() {
  const [step, setStep] = useState(0);
  const [selectedPid, setSelectedPid] = useState<number | null>(null);
  const [killedPids, setKilledPids] = useState<Set<number>>(() => new Set());
  const [killDialogPid, setKillDialogPid] = useState<number | null>(null);
  const [triageRunning, setTriageRunning] = useState(false);
  const [scoredCount, setScoredCount] = useState(0);
  const [triageDone, setTriageDone] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });

  const scenario = SCENARIOS[step];
  const totalSteps = SCENARIOS.length;

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const resetScenarioState = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    setSelectedPid(null);
    setKilledPids(new Set());
    setKillDialogPid(null);
    setTriageRunning(false);
    setScoredCount(0);
    setTriageDone(false);
  }, []);

  const goToStep = useCallback((newStep: number) => {
    resetScenarioState();
    setStep(newStep);
  }, [resetScenarioState]);

  const runTriage = useCallback(() => {
    if (triageRunning || triageDone) return;
    setTriageRunning(true);
    setScoredCount(0);
    setTriageDone(false);
    setSelectedPid(null);
    setKilledPids(new Set());
    setKillDialogPid(null);

    const procs = SCENARIOS[step].processes;
    procs.forEach((_, i) => {
      const t = setTimeout(() => {
        setScoredCount(i + 1);
        if (i === procs.length - 1) {
          timerRef.current = setTimeout(() => {
            setTriageRunning(false);
            setTriageDone(true);
          }, 350);
        }
      }, (i + 1) * 400);
      // Store the last process timer for cleanup
      if (i === procs.length - 1) {
        timerRef.current = t;
      }
    });
  }, [step, triageRunning, triageDone]);

  const handleKillConfirm = useCallback(() => {
    if (killDialogPid === null) return;
    setKilledPids(prev => {
      const next = new Set(prev);
      next.add(killDialogPid);
      return next;
    });
    setKillDialogPid(null);
    setSelectedPid(null);
  }, [killDialogPid]);

  const sortedProcesses = [...scenario.processes].sort((a, b) => b.dangerScore - a.dangerScore);
  const killablePids = scenario.processes.filter(p => p.verdict === 'kill').map(p => p.pid);
  const suspiciousPids = scenario.processes.filter(p => p.verdict === 'suspicious').map(p => p.pid);
  const safePids = scenario.processes.filter(p => p.verdict === 'safe').map(p => p.pid);
  const killDialogProc = scenario.processes.find(p => p.pid === killDialogPid);
  const res = scenario.resources;

  return (
    <div ref={ref} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-red-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-emerald-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-56 h-56 bg-blue-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-8 space-y-5">
        {/* Header */}
        <div className="text-center">
          <p className="text-sm font-semibold text-white/80">
            Process Triage Dashboard
          </p>
          <p className="text-xs text-white/40 mt-1">
            Navigate scenarios to see how PT diagnoses different system states
          </p>
        </div>

        {/* Stepper */}
        <div className="flex items-center justify-center gap-2">
          <motion.button
            type="button"
            onClick={() => goToStep(Math.max(0, step - 1))}
            disabled={step === 0}
            whileHover={{ scale: 1.08 }}
            whileTap={{ scale: 0.92 }}
            transition={SPRING}
            className="p-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 hover:bg-white/[0.06] disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </motion.button>

          <div className="flex gap-1.5">
            {SCENARIOS.map((s, i) => (
              <motion.button
                key={s.id}
                type="button"
                onClick={() => goToStep(i)}
                whileHover={{ scale: 1.15 }}
                whileTap={{ scale: 0.9 }}
                transition={SPRING}
                className={`relative flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[10px] font-medium transition ${
                  i === step
                    ? 'bg-primary/20 border border-primary/30 text-primary'
                    : 'bg-white/[0.02] border border-white/[0.06] text-white/30 hover:text-white/50 hover:border-white/[0.12]'
                }`}
              >
                {s.icon}
                <span className="hidden sm:inline">{s.label}</span>
                <span className="sm:hidden">{i + 1}</span>
              </motion.button>
            ))}
          </div>

          <motion.button
            type="button"
            onClick={() => goToStep(Math.min(totalSteps - 1, step + 1))}
            disabled={step === totalSteps - 1}
            whileHover={{ scale: 1.08 }}
            whileTap={{ scale: 0.92 }}
            transition={SPRING}
            className="p-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 hover:bg-white/[0.06] disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </motion.button>
        </div>

        {/* Scenario Description */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING}
          >
            <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-primary">{scenario.icon}</span>
                <span className="text-sm font-semibold text-white/80">{scenario.label}</span>
                <span className="text-[10px] text-white/30 ml-auto">Step {step + 1}/{totalSteps}</span>
              </div>
              <p className="text-xs text-white/50 leading-relaxed">{scenario.description}</p>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Resource Gauges + Actions */}
        <AnimatePresence mode="wait">
          <motion.div
            key={`res-${scenario.id}`}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <div className="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-4">
              {/* Gauges */}
              <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
                <div className="flex items-center gap-2 mb-3">
                  <Gauge className="h-3.5 w-3.5 text-white/40" />
                  <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">System Resources</span>
                </div>
                <div className="flex flex-wrap justify-around gap-4">
                  <ResourceGauge
                    label="CPU"
                    value={res.cpuUsage}
                    max={100}
                    unit=""
                    icon={<Cpu className="h-3.5 w-3.5" />}
                  />
                  <ResourceGauge
                    label="RAM"
                    value={res.ramUsed}
                    max={res.ramTotal}
                    unit=""
                    icon={<Activity className="h-3.5 w-3.5" />}
                  />
                  <ResourceGauge
                    label="Swap"
                    value={res.swapUsed}
                    max={res.swapTotal}
                    unit=""
                    icon={<HardDrive className="h-3.5 w-3.5" />}
                  />
                  <div className="flex flex-col items-center gap-1.5 justify-center">
                    <div className="text-center space-y-1">
                      <div className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">Load Avg</div>
                      <div className="font-mono text-xs text-white/70">
                        {res.loadAvg.map(v => v.toFixed(2)).join(' ')}
                      </div>
                      <div className="text-[10px] text-white/30">{res.cpuCores} cores</div>
                    </div>
                    <div className="text-center space-y-1 mt-1">
                      <div className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">Disk I/O</div>
                      <div className="flex gap-3 text-[10px] font-mono">
                        <span className="text-emerald-400">{'\u2191'}{formatIO(res.diskRead)} MB/s</span>
                        <span className="text-amber-400">{'\u2193'}{formatIO(res.diskWrite)} MB/s</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Actions + Triage button */}
              <div className="flex flex-col gap-3 min-w-[140px]">
                {!triageDone && !triageRunning && (
                  <motion.button
                    type="button"
                    onClick={runTriage}
                    whileHover={{ scale: 1.04 }}
                    whileTap={{ scale: 0.96 }}
                    transition={SPRING}
                    className="flex items-center justify-center gap-2 px-5 py-2.5 rounded-xl bg-primary/20 text-primary border border-primary/30 text-sm font-medium hover:bg-primary/30 transition-colors"
                  >
                    <Crosshair className="h-4 w-4" />
                    Run Triage
                  </motion.button>
                )}
                {triageRunning && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={springs.smooth}
                    className="flex items-center justify-center gap-2 px-5 py-2.5 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-400 text-sm font-medium"
                  >
                    <motion.div
                      animate={inView ? { rotate: 360 } : { rotate: 0 }}
                      transition={inView ? { duration: 1.5, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                    >
                      <Search className="h-4 w-4" />
                    </motion.div>
                    {scoredCount}/{scenario.processes.length}
                  </motion.div>
                )}
                {triageDone && (
                  <motion.button
                    type="button"
                    onClick={resetScenarioState}
                    initial={{ opacity: 0, scale: 0.9 }}
                    animate={{ opacity: 1, scale: 1 }}
                    whileHover={{ scale: 1.04 }}
                    whileTap={{ scale: 0.96 }}
                    transition={SPRING}
                    className="flex items-center justify-center gap-2 px-4 py-2 rounded-xl bg-white/[0.04] text-white/50 border border-white/[0.08] text-xs hover:bg-white/[0.08] hover:text-white/70 transition-colors"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    Re-run
                  </motion.button>
                )}

                {/* Summary badges */}
                {triageDone && (
                  <motion.div
                    initial={{ opacity: 0, y: 6 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={SPRING}
                    className="flex flex-col gap-1.5"
                  >
                    <div className="flex items-center gap-1.5 text-[10px]">
                      <div className="h-2 w-2 rounded-full bg-emerald-500" />
                      <span className="text-white/40">Safe: {safePids.length}</span>
                    </div>
                    <div className="flex items-center gap-1.5 text-[10px]">
                      <div className="h-2 w-2 rounded-full bg-amber-500" />
                      <span className="text-white/40">Suspicious: {suspiciousPids.length}</span>
                    </div>
                    <div className="flex items-center gap-1.5 text-[10px]">
                      <div className="h-2 w-2 rounded-full bg-red-500" />
                      <span className="text-white/40">Kill: {killablePids.length}</span>
                    </div>
                    {killedPids.size > 0 && (
                      <div className="flex items-center gap-1.5 text-[10px]">
                        <Skull className="h-2.5 w-2.5 text-white/30" />
                        <span className="text-white/30">Killed: {killedPids.size}</span>
                      </div>
                    )}
                  </motion.div>
                )}
              </div>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Process Table */}
        <AnimatePresence mode="wait">
          <motion.div
            key={`procs-${scenario.id}`}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
              {/* Table header */}
              <div className="grid grid-cols-[44px_36px_1fr_52px_52px_44px_64px] gap-1.5 px-3 py-2 border-b border-white/[0.06] text-[10px] uppercase tracking-wider text-white/25 font-semibold bg-white/[0.01]">
                <span>PID</span>
                <span>S</span>
                <span>Process</span>
                <span className="text-right">CPU%</span>
                <span className="text-right">MEM</span>
                <span className="text-right">I/O</span>
                <span className="text-right">Danger</span>
              </div>

              {/* Rows */}
              <div className="divide-y divide-white/[0.04]">
                {sortedProcesses.map((proc, i) => {
                  const isScored = triageDone || i < scoredCount;
                  const isKilled = killedPids.has(proc.pid);
                  const isSelected = selectedPid === proc.pid;
                  const highCpu = proc.cpu > 50;
                  const highMem = proc.memory > 2000;

                  return (
                    <div key={proc.pid}>
                      <motion.button
                        type="button"
                        layout
                        onClick={() => {
                          if (isScored && !isKilled) {
                            setSelectedPid(isSelected ? null : proc.pid);
                          }
                        }}
                        transition={SPRING}
                        className={`w-full text-left px-3 py-2.5 transition-colors ${
                          isKilled
                            ? 'opacity-30'
                            : isSelected
                              ? 'bg-white/[0.04]'
                              : 'hover:bg-white/[0.03]'
                        }`}
                      >
                        <div className="grid grid-cols-[44px_36px_1fr_52px_52px_44px_64px] gap-1.5 items-center">
                          <span className="font-mono text-[11px] text-white/40">{proc.pid}</span>
                          <span className={`font-mono text-[10px] font-bold ${getStateColor(proc.state)}`}>
                            {getStateLabel(proc.state)}
                          </span>
                          <div className="flex items-center gap-1.5 min-w-0">
                            <span className={`text-xs truncate ${isKilled ? 'line-through text-white/20' : 'text-white/70'}`}>
                              {proc.name}
                            </span>
                            {isKilled && (
                              <motion.span
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                transition={springs.snappy}
                                className="shrink-0 rounded-full bg-red-500/20 border border-red-500/30 px-1.5 py-0.5 text-[10px] text-red-400 font-bold"
                              >
                                KILLED
                              </motion.span>
                            )}
                          </div>
                          {/* CPU with bar */}
                          <div className="text-right">
                            <span className={`font-mono text-[10px] ${highCpu ? 'text-red-400' : 'text-white/40'}`}>
                              {proc.cpu.toFixed(1)}
                            </span>
                            <UsageBar value={proc.cpu} max={100} color={highCpu ? 'bg-red-500' : 'bg-blue-500'} pulse={highCpu && !isKilled} />
                          </div>
                          {/* Memory */}
                          <div className="text-right">
                            <span className={`font-mono text-[10px] ${highMem ? 'text-amber-400' : 'text-white/40'}`}>
                              {formatMem(proc.memory)}
                            </span>
                            <UsageBar value={proc.memory} max={8192} color={highMem ? 'bg-amber-500' : 'bg-indigo-500'} />
                          </div>
                          {/* I/O */}
                          <span className="text-right font-mono text-[10px] text-white/30">
                            {proc.ioRead + proc.ioWrite > 0 ? `${formatIO(proc.ioRead + proc.ioWrite)}` : '-'}
                          </span>
                          {/* Danger score */}
                          <div className="flex items-center gap-1">
                            <div className="flex-1 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                              <motion.div
                                className={`h-full rounded-full ${isScored ? getDangerColor(proc.dangerScore) : 'bg-white/[0.08]'}`}
                                initial={{ width: '0%' }}
                                animate={{ width: isScored ? `${proc.dangerScore * 100}%` : '0%' }}
                                transition={SPRING}
                              />
                            </div>
                            <span className={`text-[10px] font-mono w-5 text-right ${isScored ? getDangerTextColor(proc.dangerScore) : 'text-white/15'}`}>
                              {isScored ? (proc.dangerScore * 100).toFixed(0) : '--'}
                            </span>
                          </div>
                        </div>
                      </motion.button>

                      {/* Expanded detail panel */}
                      <AnimatePresence>
                        {isSelected && isScored && !isKilled && (
                          <motion.div
                            key={`detail-${proc.pid}`}
                            initial={{ opacity: 0, height: 0 }}
                            animate={{ opacity: 1, height: 'auto' }}
                            exit={{ opacity: 0, height: 0 }}
                            transition={SPRING}
                            className="overflow-hidden"
                          >
                            <div className={`mx-3 mb-3 rounded-xl border p-4 ${
                              proc.verdict === 'kill' ? 'border-red-500/20 bg-red-500/[0.04]' :
                              proc.verdict === 'suspicious' ? 'border-amber-500/20 bg-amber-500/[0.04]' :
                              'border-emerald-500/20 bg-emerald-500/[0.04]'
                            }`}>
                              <div className="flex items-center gap-2 mb-2">
                                {proc.verdict === 'kill' && <XCircle className="h-4 w-4 text-red-400" />}
                                {proc.verdict === 'suspicious' && <AlertTriangle className="h-4 w-4 text-amber-400" />}
                                {proc.verdict === 'safe' && <CheckCircle className="h-4 w-4 text-emerald-400" />}
                                <span className={`text-xs font-semibold ${
                                  proc.verdict === 'kill' ? 'text-red-400' :
                                  proc.verdict === 'suspicious' ? 'text-amber-400' :
                                  'text-emerald-400'
                                }`}>
                                  {proc.verdict === 'kill' ? 'Kill Recommended' : proc.verdict === 'suspicious' ? 'Suspicious' : 'Safe'}
                                </span>
                                <span className="text-[10px] text-white/20 ml-auto font-mono">
                                  Score: {(proc.dangerScore * 100).toFixed(0)} | Uptime: {proc.uptime} | PPID: {proc.ppid}
                                </span>
                              </div>
                              <p className="text-xs text-white/50 leading-relaxed mb-3">{proc.reason}</p>

                              {/* Resource detail */}
                              <div className="grid grid-cols-4 gap-3 mb-3">
                                <div className="text-center">
                                  <div className="text-[10px] text-white/25 uppercase">CPU</div>
                                  <div className="text-xs font-mono text-white/60">{proc.cpu.toFixed(1)}%</div>
                                </div>
                                <div className="text-center">
                                  <div className="text-[10px] text-white/25 uppercase">Memory</div>
                                  <div className="text-xs font-mono text-white/60">{formatMem(proc.memory)}</div>
                                </div>
                                <div className="text-center">
                                  <div className="text-[10px] text-white/25 uppercase">I/O Read</div>
                                  <div className="text-xs font-mono text-white/60">{formatIO(proc.ioRead)} MB/s</div>
                                </div>
                                <div className="text-center">
                                  <div className="text-[10px] text-white/25 uppercase">I/O Write</div>
                                  <div className="text-xs font-mono text-white/60">{formatIO(proc.ioWrite)} MB/s</div>
                                </div>
                              </div>

                              {/* Kill button for dangerous processes */}
                              {(proc.verdict === 'kill' || proc.verdict === 'suspicious') && (
                                <motion.button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setKillDialogPid(proc.pid);
                                  }}
                                  whileHover={{ scale: 1.03 }}
                                  whileTap={{ scale: 0.97 }}
                                  transition={SPRING}
                                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-500/15 text-red-400 border border-red-500/25 text-xs font-medium hover:bg-red-500/25 transition-colors"
                                >
                                  <Skull className="h-3.5 w-3.5" />
                                  Kill Process
                                </motion.button>
                              )}
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </div>
                  );
                })}
              </div>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Bottom panels: Process Tree + Terminal */}
        <AnimatePresence mode="wait">
          <motion.div
            key={`bottom-${scenario.id}`}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ ...SPRING, delay: 0.1 }}
            className="grid grid-cols-1 md:grid-cols-2 gap-4"
          >
            {/* Process Tree */}
            <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
              <div className="flex items-center gap-2 mb-3">
                <TreePine className="h-3.5 w-3.5 text-white/40" />
                <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">Process Tree</span>
              </div>
              <ProcessTree processes={scenario.processes} />
            </div>

            {/* Terminal Output */}
            <div>
              <MiniTerminal lines={scenario.terminalLines} />
            </div>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* Kill confirmation dialog overlay */}
      <AnimatePresence>
        {killDialogPid !== null && killDialogProc && (
          <KillDialog
            proc={killDialogProc}
            onConfirm={handleKillConfirm}
            onCancel={() => setKillDialogPid(null)}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
