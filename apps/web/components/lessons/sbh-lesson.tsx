'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Terminal,
  HardDrive,
  Shield,
  Activity,
  Play,
  AlertTriangle,
  Gauge,
  Trash2,
  ChevronLeft,
  ChevronRight,
  FolderTree,
  Database,
  FileWarning,
  Sparkles,
  RotateCcw,
  Zap,
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
const InteractiveDiskPressure = InteractiveDiskPressureImpl;

export function SbhLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Protect your disk from pressure spikes with Storage Ballast Helper.
      </GoalBanner>

      {/* Section 1: What Is SBH */}
      <Section title="What Is Storage Ballast Helper?" icon={<HardDrive className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>SBH (Storage Ballast Helper)</Highlight> is a cross-platform disk-pressure
          defense tool designed for AI coding workloads. It pre-allocates a &ldquo;ballast&rdquo;
          file that can be released when disk space runs critically low, buying time
          to clean up.
        </Paragraph>
        <Paragraph>
          Agent coding sessions generate enormous amounts of build artifacts, logs, and
          caches. SBH monitors disk usage and automatically releases ballast when pressure
          exceeds configurable thresholds.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<HardDrive className="h-5 w-5" />}
              title="Ballast Files"
              description="Pre-allocated space released under pressure"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="Monitoring"
              description="Continuous disk usage tracking with alerts"
              gradient="from-green-500/20 to-emerald-500/20"
            />
            <FeatureCard
              icon={<AlertTriangle className="h-5 w-5" />}
              title="Auto-Release"
              description="Ballast freed automatically at critical thresholds"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safe Recovery"
              description="Prevents out-of-space crashes and data loss"
              gradient="from-red-500/20 to-rose-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveDiskPressure />
      </div>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'sbh status', description: 'Show disk usage and ballast state' },
            { command: 'sbh create --size 5G', description: 'Create a 5 GB ballast file' },
            { command: 'sbh release', description: 'Manually release ballast space' },
            { command: 'sbh reclaim', description: 'Re-create ballast after cleanup' },
          ]}
        />

        <TipBox>
          Create ballast files on machines running multi-agent swarms, where parallel
          cargo builds and npm installs can exhaust disk space unexpectedly.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Check current disk pressure
sbh status

# Create ballast on a new machine
sbh create --size 10G

# Emergency release when disk is full
sbh release`} />
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Disk Pressure Monitoring Dashboard
// ---------------------------------------------------------------------------

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

/** SVG arc path helper for donut charts */
function describeArc(
  cx: number,
  cy: number,
  r: number,
  startAngle: number,
  endAngle: number,
): string {
  const clampedEnd = Math.min(endAngle, startAngle + 359.999);
  const startRad = ((clampedEnd - 90) * Math.PI) / 180;
  const endRad = ((startAngle - 90) * Math.PI) / 180;
  const x1 = cx + r * Math.cos(endRad);
  const y1 = cy + r * Math.sin(endRad);
  const x2 = cx + r * Math.cos(startRad);
  const y2 = cy + r * Math.sin(startRad);
  const largeArc = clampedEnd - startAngle > 180 ? 1 : 0;
  return `M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2}`;
}

/** Get color for usage percentage */
function usageColor(pct: number): { stroke: string; text: string; bg: string; label: string } {
  if (pct >= 97) return { stroke: '#ef4444', text: 'text-red-400', bg: 'bg-red-500', label: 'CRITICAL' };
  if (pct >= 90) return { stroke: '#f59e0b', text: 'text-amber-400', bg: 'bg-amber-500', label: 'WARNING' };
  if (pct >= 75) return { stroke: '#eab308', text: 'text-yellow-400', bg: 'bg-yellow-500', label: 'ELEVATED' };
  return { stroke: '#22c55e', text: 'text-emerald-400', bg: 'bg-emerald-500', label: 'HEALTHY' };
}

interface MountPoint {
  path: string;
  totalGb: number;
  usedGb: number;
}

interface DiskCategory {
  name: string;
  sizeGb: number;
  color: string;
}

interface AlertEntry {
  time: string;
  message: string;
  severity: 'info' | 'warn' | 'critical' | 'success';
}

interface Scenario {
  id: string;
  label: string;
  icon: typeof HardDrive;
  color: string;
  description: string;
  mounts: MountPoint[];
  categories: DiskCategory[];
  alerts: AlertEntry[];
  terminalLines: string[];
  ballastStatus: 'reserved' | 'releasing' | 'released' | 'reclaiming';
  ballastGb: number;
}

const SCENARIOS: Scenario[] = [
  {
    id: 'normal',
    label: 'Normal',
    icon: Activity,
    color: 'emerald',
    description: 'System running smoothly. All mount points healthy with ballast reserved.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 28.4 },
      { path: '/home', totalGb: 100, usedGb: 42.1 },
      { path: '/tmp', totalGb: 10, usedGb: 1.8 },
      { path: '/var/log', totalGb: 20, usedGb: 6.3 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 12.5, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 8.2, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 14.3, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 6.3, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 5.8, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 7.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 24.5, color: '#6b7280' },
    ],
    alerts: [
      { time: '14:32', message: 'sbh status: all mounts healthy', severity: 'info' },
      { time: '14:30', message: 'Ballast file verified: 7.0 GB at /var/ballast', severity: 'info' },
      { time: '14:28', message: 'Disk monitor started, checking every 30s', severity: 'info' },
    ],
    terminalLines: [
      '$ sbh status',
      'SBH Storage Ballast Helper v2.1.0',
      '',
      'Mount    Used     Total    Pct   Status',
      '/        28.4 GB  50.0 GB  57%   OK',
      '/home    42.1 GB  100 GB   42%   OK',
      '/tmp     1.8 GB   10.0 GB  18%   OK',
      '/var/log 6.3 GB   20.0 GB  32%   OK',
      '',
      'Ballast: 7.0 GB reserved at /var/ballast',
      'Threshold: auto-release at 95%',
    ],
    ballastStatus: 'reserved',
    ballastGb: 7.0,
  },
  {
    id: 'log-growth',
    label: 'Log Growth',
    icon: FileWarning,
    color: 'amber',
    description: 'Agent logs growing rapidly. /var/log approaching warning threshold.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 34.7 },
      { path: '/home', totalGb: 100, usedGb: 58.3 },
      { path: '/tmp', totalGb: 10, usedGb: 4.2 },
      { path: '/var/log', totalGb: 20, usedGb: 17.6 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 18.2, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 12.4, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 19.8, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 17.6, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 9.1, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 7.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 30.7, color: '#6b7280' },
    ],
    alerts: [
      { time: '15:47', message: '/var/log at 88% - approaching threshold', severity: 'warn' },
      { time: '15:44', message: 'Log growth rate: 2.1 GB/hr detected', severity: 'warn' },
      { time: '15:40', message: 'Agent swarm generating verbose debug logs', severity: 'info' },
    ],
    terminalLines: [
      '$ sbh status',
      'SBH Storage Ballast Helper v2.1.0',
      '',
      'Mount    Used     Total    Pct   Status',
      '/        34.7 GB  50.0 GB  69%   OK',
      '/home    58.3 GB  100 GB   58%   OK',
      '/tmp     4.2 GB   10.0 GB  42%   OK',
      '/var/log 17.6 GB  20.0 GB  88%   WARNING',
      '',
      'Ballast: 7.0 GB reserved at /var/ballast',
      '! Log growth rate: 2.1 GB/hr',
    ],
    ballastStatus: 'reserved',
    ballastGb: 7.0,
  },
  {
    id: 'cleanup',
    label: 'Cleanup',
    icon: Trash2,
    color: 'blue',
    description: 'SBH triggered automatic log rotation and old build artifact cleanup.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 31.2 },
      { path: '/home', totalGb: 100, usedGb: 48.7 },
      { path: '/tmp', totalGb: 10, usedGb: 2.1 },
      { path: '/var/log', totalGb: 20, usedGb: 8.4 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 10.1, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 12.4, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 19.8, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 8.4, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 9.1, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 7.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 23.6, color: '#6b7280' },
    ],
    alerts: [
      { time: '16:02', message: 'Cleanup complete: freed 19.2 GB total', severity: 'success' },
      { time: '16:01', message: 'Rotated logs: freed 9.2 GB from /var/log', severity: 'success' },
      { time: '16:00', message: 'Removed stale build artifacts: freed 8.1 GB', severity: 'success' },
      { time: '15:59', message: 'Cleaned /tmp: freed 2.1 GB', severity: 'info' },
    ],
    terminalLines: [
      '$ sbh cleanup --auto',
      'Scanning for reclaimable space...',
      '',
      'Rotated:  /var/log/*.log.gz   -9.2 GB',
      'Removed:  build/artifacts/*    -8.1 GB',
      'Cleaned:  /tmp/agent-*         -2.1 GB',
      '',
      'Total freed: 19.2 GB',
      'All mount points now healthy.',
      'Ballast: 7.0 GB intact',
    ],
    ballastStatus: 'reserved',
    ballastGb: 7.0,
  },
  {
    id: 'docker-prune',
    label: 'Docker Prune',
    icon: Database,
    color: 'cyan',
    description: 'Docker images consuming massive space. Pruning unused layers and volumes.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 46.8 },
      { path: '/home', totalGb: 100, usedGb: 72.4 },
      { path: '/tmp', totalGb: 10, usedGb: 7.9 },
      { path: '/var/log', totalGb: 20, usedGb: 12.1 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 15.3, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 14.8, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 42.6, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 12.1, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 11.2, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 7.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 36.2, color: '#6b7280' },
    ],
    alerts: [
      { time: '17:15', message: '/ at 94% - nearing critical threshold!', severity: 'warn' },
      { time: '17:14', message: 'Docker using 42.6 GB across 23 images', severity: 'warn' },
      { time: '17:13', message: 'Recommending: docker system prune', severity: 'info' },
    ],
    terminalLines: [
      '$ sbh status --verbose',
      'WARNING: / at 94% usage',
      '',
      'Largest consumers:',
      '  Docker images    42.6 GB  (23 images)',
      '  Node modules     14.8 GB  (6 projects)',
      '  Build artifacts  15.3 GB',
      '',
      '$ docker system prune -af',
      'Deleted 18 images, 4 volumes',
      'Reclaimed: 28.3 GB',
    ],
    ballastStatus: 'reserved',
    ballastGb: 7.0,
  },
  {
    id: 'cache-purge',
    label: 'Cache Purge',
    icon: Zap,
    color: 'violet',
    description: 'Build caches from parallel agent sessions filling disk. Purging stale entries.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 47.2 },
      { path: '/home', totalGb: 100, usedGb: 91.3 },
      { path: '/tmp', totalGb: 10, usedGb: 8.6 },
      { path: '/var/log', totalGb: 20, usedGb: 14.8 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 28.7, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 22.1, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 24.5, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 14.8, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 31.4, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 7.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 33.4, color: '#6b7280' },
    ],
    alerts: [
      { time: '18:22', message: '/home at 91% - CRITICAL soon', severity: 'critical' },
      { time: '18:21', message: 'Cargo cache: 31.4 GB from 8 concurrent builds', severity: 'warn' },
      { time: '18:20', message: 'Running: cargo cache --autoclean-expensive', severity: 'info' },
      { time: '18:19', message: 'Node cache: 22.1 GB across 12 workspaces', severity: 'warn' },
    ],
    terminalLines: [
      '$ sbh analyze /home',
      'Top consumers in /home:',
      '  ~/.cargo/registry  31.4 GB',
      '  node_modules/      22.1 GB',
      '  target/            28.7 GB',
      '',
      '$ sbh purge-caches --aggressive',
      'Purging Cargo registry (keeping latest)...',
      'Purging node_modules (stale > 7d)...',
      'Freed: 41.2 GB from cache purge',
    ],
    ballastStatus: 'reserved',
    ballastGb: 7.0,
  },
  {
    id: 'emergency',
    label: 'Emergency',
    icon: AlertTriangle,
    color: 'red',
    description: 'CRITICAL: Disk full! Ballast auto-released. Emergency recovery in progress.',
    mounts: [
      { path: '/', totalGb: 50, usedGb: 42.5 },
      { path: '/home', totalGb: 100, usedGb: 94.7 },
      { path: '/tmp', totalGb: 10, usedGb: 9.8 },
      { path: '/var/log', totalGb: 20, usedGb: 19.4 },
    ],
    categories: [
      { name: 'Build artifacts', sizeGb: 32.1, color: '#3b82f6' },
      { name: 'Node modules', sizeGb: 24.8, color: '#8b5cf6' },
      { name: 'Docker images', sizeGb: 38.2, color: '#06b6d4' },
      { name: 'Logs', sizeGb: 19.4, color: '#f59e0b' },
      { name: 'Cargo cache', sizeGb: 28.9, color: '#ef4444' },
      { name: 'Ballast', sizeGb: 0.0, color: '#22c55e' },
      { name: 'Other', sizeGb: 23.0, color: '#6b7280' },
    ],
    alerts: [
      { time: '19:01', message: 'EMERGENCY: Ballast released! 7 GB freed on /', severity: 'critical' },
      { time: '19:00', message: '/ hit 99% - auto-release triggered!', severity: 'critical' },
      { time: '18:59', message: 'Agent writes failing: ENOSPC errors', severity: 'critical' },
      { time: '18:58', message: 'All cleanup strategies executing...', severity: 'warn' },
    ],
    terminalLines: [
      '$ sbh release --emergency',
      '!!! EMERGENCY BALLAST RELEASE !!!',
      '',
      'Released: /var/ballast (7.0 GB)',
      'Root / now at 85% (was 99%)',
      '',
      'Running emergency cleanup...',
      '  Truncating old logs...    -4.2 GB',
      '  Clearing /tmp...          -8.1 GB',
      '',
      '$ sbh reclaim  # after cleanup',
    ],
    ballastStatus: 'released',
    ballastGb: 0.0,
  },
];

const COLOR_MAP: Record<string, { border: string; bg: string; text: string }> = {
  emerald: { border: 'border-emerald-500/30', bg: 'bg-emerald-500/10', text: 'text-emerald-300' },
  amber: { border: 'border-amber-500/30', bg: 'bg-amber-500/10', text: 'text-amber-300' },
  blue: { border: 'border-blue-500/30', bg: 'bg-blue-500/10', text: 'text-blue-300' },
  cyan: { border: 'border-cyan-500/30', bg: 'bg-cyan-500/10', text: 'text-cyan-300' },
  violet: { border: 'border-violet-500/30', bg: 'bg-violet-500/10', text: 'text-violet-300' },
  red: { border: 'border-red-500/30', bg: 'bg-red-500/10', text: 'text-red-300' },
};

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-blue-400',
  warn: 'text-amber-400',
  critical: 'text-red-400',
  success: 'text-emerald-400',
};

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

/** Animated usage bar for a mount point */
function MountBar({ mount }: { mount: MountPoint }) {
  const pct = Math.round((mount.usedGb / mount.totalGb) * 100);
  const colors = usageColor(pct);
  const isCritical = pct >= 97;

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-[11px]">
        <span className="font-mono text-white/60 font-medium">{mount.path}</span>
        <span className={`font-mono font-semibold ${colors.text}`}>
          {mount.usedGb.toFixed(1)}/{mount.totalGb} GB ({pct}%)
        </span>
      </div>
      <div className="h-3 rounded-full bg-white/[0.06] overflow-hidden relative">
        <motion.div
          className={`h-full rounded-full ${isCritical ? 'animate-pulse' : ''}`}
          animate={{
            width: `${pct}%`,
            backgroundColor: colors.stroke,
          }}
          transition={SPRING}
        />
        {/* Threshold markers */}
        <div className="absolute top-0 left-[75%] h-full w-px bg-yellow-500/30" />
        <div className="absolute top-0 left-[90%] h-full w-px bg-red-500/40" />
        <div className="absolute top-0 left-[95%] h-full w-px bg-red-500/60" />
      </div>
    </div>
  );
}

/** SVG donut chart showing category breakdown */
function CategoryDonut({ categories, size = 180 }: { categories: DiskCategory[]; size?: number }) {
  const total = categories.reduce((sum, c) => sum + c.sizeGb, 0);
  const half = size / 2;
  const radius = half - 20;
  const segments: { path: string; color: string; name: string; pct: number }[] = [];
  let currentAngle = 0;

  for (const cat of categories) {
    const angle = (cat.sizeGb / total) * 360;
    if (angle > 0.5) {
      segments.push({
        path: describeArc(half, half, radius, currentAngle, currentAngle + angle),
        color: cat.color,
        name: cat.name,
        pct: Math.round((cat.sizeGb / total) * 100),
      });
    }
    currentAngle += angle;
  }

  return (
    <svg viewBox={`0 0 ${size} ${size}`} className="w-full h-full">
      <defs>
        <filter id="donut-glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      {/* Background ring */}
      <circle cx={half} cy={half} r={radius} fill="none" stroke="rgba(255,255,255,0.04)" strokeWidth={16} />
      {/* Category arcs */}
      {segments.map((seg, i) => (
        <path
          key={i}
          d={seg.path}
          fill="none"
          stroke={seg.color}
          strokeWidth={16}
          strokeLinecap="round"
          filter="url(#donut-glow)"
          style={{ opacity: 0.85 }}
        />
      ))}
      {/* Center text */}
      <text x={half} y={half - 6} textAnchor="middle" fill="white" fontSize="18" fontWeight="bold" fontFamily="monospace">
        {total.toFixed(0)} GB
      </text>
      <text x={half} y={half + 12} textAnchor="middle" fill="rgba(255,255,255,0.4)" fontSize="10" fontFamily="monospace">
        total used
      </text>
    </svg>
  );
}

/** Treemap visualization of largest disk consumers */
function FileTreemap({ categories }: { categories: DiskCategory[] }) {
  const sorted = [...categories].sort((a, b) => b.sizeGb - a.sizeGb);
  const total = sorted.reduce((s, c) => s + c.sizeGb, 0);

  return (
    <div className="grid grid-cols-4 gap-1 h-full min-h-[100px]">
      {sorted.map((cat, i) => {
        const pct = (cat.sizeGb / total) * 100;
        const span = pct > 20 ? 2 : 1;
        return (
          <motion.div
            key={cat.name}
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ ...SPRING, delay: i * 0.05 }}
            className="rounded-lg border border-white/[0.06] flex flex-col items-center justify-center p-1.5 min-h-[44px]"
            style={{
              gridColumn: `span ${span}`,
              backgroundColor: `${cat.color}15`,
              borderColor: `${cat.color}30`,
            }}
          >
            <span className="text-[10px] font-mono font-semibold text-white/70 truncate w-full text-center">
              {cat.name}
            </span>
            <span className="text-[10px] font-mono" style={{ color: cat.color }}>
              {cat.sizeGb.toFixed(1)} GB
            </span>
          </motion.div>
        );
      })}
    </div>
  );
}

/** Category legend below donut */
function CategoryLegend({ categories }: { categories: DiskCategory[] }) {
  return (
    <div className="grid grid-cols-2 gap-x-3 gap-y-1">
      {categories.map((cat) => (
        <div key={cat.name} className="flex items-center gap-1.5">
          <div className="w-2 h-2 rounded-sm shrink-0" style={{ backgroundColor: cat.color }} />
          <span className="text-[10px] text-white/50 truncate">{cat.name}</span>
          <span className="text-[10px] font-mono text-white/30 ml-auto shrink-0">
            {cat.sizeGb.toFixed(1)}
          </span>
        </div>
      ))}
    </div>
  );
}

/** Alert ticker */
function AlertTicker({ alerts }: { alerts: AlertEntry[] }) {
  return (
    <div className="space-y-1 max-h-[120px] overflow-y-auto">
      {alerts.map((alert, i) => (
        <motion.div
          key={`${alert.time}-${i}`}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ ...SPRING, delay: i * 0.08 }}
          className="flex items-start gap-2 text-[11px]"
        >
          <span className="font-mono text-white/30 shrink-0">{alert.time}</span>
          <span className={`${SEVERITY_COLORS[alert.severity]} font-mono`}>
            {alert.severity === 'critical' ? '!!!' : alert.severity === 'warn' ? '!' : alert.severity === 'success' ? '+' : '-'}
          </span>
          <span className="text-white/60">{alert.message}</span>
        </motion.div>
      ))}
    </div>
  );
}

/** Mini terminal panel */
function MiniTerminal({ lines }: { lines: string[] }) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden flex flex-col">
      <div className="flex items-center gap-2 px-3 py-1.5 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex gap-1">
          <div className="w-2 h-2 rounded-full bg-red-400/50" />
          <div className="w-2 h-2 rounded-full bg-amber-400/50" />
          <div className="w-2 h-2 rounded-full bg-emerald-400/50" />
        </div>
        <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider ml-1">
          Terminal
        </span>
      </div>
      <div className="p-3 space-y-0.5 overflow-y-auto max-h-[220px]">
        {lines.map((line, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: i * 0.04 }}
            className={`text-[11px] font-mono leading-relaxed ${
              line.startsWith('$')
                ? 'text-emerald-400'
                : line.startsWith('!')
                  ? 'text-red-400'
                  : line.startsWith('+') || line.includes('freed') || line.includes('Freed') || line.includes('Reclaimed')
                    ? 'text-emerald-400/80'
                    : line.includes('WARNING') || line.includes('CRITICAL') || line.includes('EMERGENCY')
                      ? 'text-amber-400'
                      : 'text-white/50'
            }`}
          >
            {line || '\u00A0'}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

/** Ballast status indicator */
function BallastIndicator({ status, sizeGb }: { status: string; sizeGb: number }) {
  const isReleased = status === 'released';
  const isReserved = status === 'reserved';

  return (
    <div className={`rounded-xl border p-3 transition-colors duration-300 ${
      isReleased
        ? 'border-red-500/30 bg-red-500/[0.06]'
        : 'border-emerald-500/20 bg-emerald-500/[0.04]'
    }`}>
      <div className="flex items-center gap-2">
        <Shield className={`h-4 w-4 ${isReleased ? 'text-red-400' : 'text-emerald-400'}`} />
        <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
          Ballast
        </span>
        <motion.span
          key={status}
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={SPRING}
          className={`ml-auto text-[10px] font-mono px-2 py-0.5 rounded-full font-medium ${
            isReleased
              ? 'bg-red-500/20 text-red-400'
              : isReserved
                ? 'bg-emerald-500/20 text-emerald-400'
                : 'bg-amber-500/20 text-amber-400'
          }`}
        >
          {status.toUpperCase()}
        </motion.span>
      </div>
      <div className="mt-2 flex items-center gap-3">
        <div className="flex-1 h-2 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="h-full rounded-full"
            animate={{
              width: `${(sizeGb / 7) * 100}%`,
              backgroundColor: isReleased ? '#ef4444' : '#22c55e',
            }}
            transition={SPRING}
          />
        </div>
        <span className={`text-[11px] font-mono ${isReleased ? 'text-red-400' : 'text-emerald-400'}`}>
          {sizeGb.toFixed(1)} GB
        </span>
      </div>
      <p className="text-xs text-white/40 mt-1.5">
        {isReleased
          ? 'Ballast released! Run sbh reclaim after cleanup.'
          : `${sizeGb.toFixed(1)} GB reserved at /var/ballast. Auto-releases at 95%.`}
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main interactive component
// ---------------------------------------------------------------------------

function InteractiveDiskPressureImpl() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [animatedMounts, setAnimatedMounts] = useState<MountPoint[]>(SCENARIOS[0].mounts);
  const animRef = useRef(0);
  const prevMountsRef = useRef<MountPoint[]>(SCENARIOS[0].mounts);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const scenario = SCENARIOS[scenarioIdx];
  const colors = COLOR_MAP[scenario.color] ?? COLOR_MAP.emerald;

  // Animate mount point values toward new targets
  useEffect(() => {
    const targetMounts = scenario.mounts;
    const startMounts = prevMountsRef.current;
    const duration = 900;
    const t0 = performance.now();
    let running = true;

    function tick(now: number) {
      if (!running) return;
      const elapsed = now - t0;
      const progress = Math.min(elapsed / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 3);

      const interpolated = targetMounts.map((target, i) => {
        const start = startMounts[i] ?? target;
        return {
          path: target.path,
          totalGb: target.totalGb,
          usedGb: Math.round((start.usedGb + (target.usedGb - start.usedGb) * ease) * 10) / 10,
        };
      });

      setAnimatedMounts(interpolated);

      if (progress < 1) {
        animRef.current = requestAnimationFrame(tick);
      } else {
        prevMountsRef.current = targetMounts;
      }
    }

    animRef.current = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(animRef.current);
    };
  }, [scenario.mounts]);

  const handleSelectScenario = useCallback((idx: number) => {
    setScenarioIdx(idx);
  }, []);

  const handleStepForward = useCallback(() => {
    setScenarioIdx((prev) => (prev + 1) % SCENARIOS.length);
  }, []);

  const handleStepBack = useCallback(() => {
    setScenarioIdx((prev) => (prev - 1 + SCENARIOS.length) % SCENARIOS.length);
  }, []);

  // Overall usage for the donut
  const totalAllMounts = animatedMounts.reduce((s, m) => s + m.totalGb, 0);
  const usedAllMounts = animatedMounts.reduce((s, m) => s + m.usedGb, 0);
  const overallPct = Math.round((usedAllMounts / totalAllMounts) * 100);
  const overallColors = usageColor(overallPct);
  const gaugeAngle = (overallPct / 100) * 360;

  const isEmergency = scenario.id === 'emergency';

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-red-500/[0.02] rounded-full blur-3xl pointer-events-none" />
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
            <p className="text-sm font-semibold text-white/90">Disk Pressure Monitoring Dashboard</p>
            <Sparkles className="h-4 w-4 text-blue-400" />
          </div>
          <p className="text-xs text-white/50">
            Step through scenarios to see how SBH monitors, warns, and recovers from disk pressure
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
          {SCENARIOS.map((_, i) => (
            <motion.div
              key={i}
              animate={{
                scale: scenarioIdx === i ? 1.3 : 1,
                backgroundColor: scenarioIdx === i ? (COLOR_MAP[SCENARIOS[i].color]?.text === 'text-red-300' ? '#ef4444' : '#3b82f6') : 'rgba(255,255,255,0.15)',
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

        {/* Main dashboard grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">

          {/* LEFT: Donut gauge + category legend */}
          <div className="space-y-3">
            {/* Overall gauge */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4">
              <div className="flex items-center gap-2 mb-3">
                <Gauge className="h-4 w-4 text-white/50" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Overall Usage
                </span>
                <motion.span
                  key={overallColors.label}
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={SPRING}
                  className={`ml-auto text-[10px] font-mono font-bold px-2 py-0.5 rounded-full ${
                    overallColors.label === 'CRITICAL'
                      ? 'bg-red-500/20 text-red-400'
                      : overallColors.label === 'WARNING'
                        ? 'bg-amber-500/20 text-amber-400'
                        : overallColors.label === 'ELEVATED'
                          ? 'bg-yellow-500/20 text-yellow-400'
                          : 'bg-emerald-500/20 text-emerald-400'
                  }`}
                >
                  {overallColors.label}
                </motion.span>
              </div>
              <div className="w-36 h-36 mx-auto relative">
                <svg viewBox="0 0 180 180" className="w-full h-full">
                  <defs>
                    <filter id="gauge-glow" x="-50%" y="-50%" width="200%" height="200%">
                      <feGaussianBlur stdDeviation="4" result="blur" />
                      <feMerge>
                        <feMergeNode in="blur" />
                        <feMergeNode in="SourceGraphic" />
                      </feMerge>
                    </filter>
                  </defs>
                  <circle cx={90} cy={90} r={70} fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth={14} />
                  <path
                    d={describeArc(90, 90, 70, 0, gaugeAngle)}
                    fill="none"
                    stroke={overallColors.stroke}
                    strokeWidth={14}
                    strokeLinecap="round"
                    filter="url(#gauge-glow)"
                    style={{ transition: 'stroke 0.4s ease' }}
                  />
                  <text x={90} y={82} textAnchor="middle" fill={overallColors.stroke} fontSize="26" fontWeight="bold" fontFamily="monospace" style={{ transition: 'fill 0.4s ease' }}>
                    {overallPct}%
                  </text>
                  <text x={90} y={100} textAnchor="middle" fill="rgba(255,255,255,0.4)" fontSize="10" fontFamily="monospace">
                    aggregate
                  </text>
                </svg>
              </div>
            </div>

            {/* Ballast indicator */}
            <BallastIndicator status={scenario.ballastStatus} sizeGb={scenario.ballastGb} />
          </div>

          {/* CENTER: Mount points + treemap */}
          <div className="space-y-3">
            {/* Mount point bars */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
              <div className="flex items-center gap-2">
                <HardDrive className="h-4 w-4 text-white/50" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Mount Points
                </span>
              </div>
              <AnimatePresence mode="wait">
                <motion.div
                  key={scenario.id}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.2 }}
                  className="space-y-2.5"
                >
                  {animatedMounts.map((mount) => (
                    <MountBar key={mount.path} mount={mount} />
                  ))}
                </motion.div>
              </AnimatePresence>
              {/* Threshold legend */}
              <div className="flex items-center gap-3 pt-1 border-t border-white/[0.04]">
                <div className="flex items-center gap-1">
                  <div className="w-3 h-px bg-yellow-500/50" />
                  <span className="text-[10px] text-white/30">75%</span>
                </div>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-px bg-red-500/50" />
                  <span className="text-[10px] text-white/30">90%</span>
                </div>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-px bg-red-500/70" />
                  <span className="text-[10px] text-white/30">95% release</span>
                </div>
              </div>
            </div>

            {/* File treemap */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-2">
              <div className="flex items-center gap-2">
                <FolderTree className="h-4 w-4 text-white/50" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Space Treemap
                </span>
              </div>
              <AnimatePresence mode="wait">
                <motion.div
                  key={scenario.id}
                  initial={{ opacity: 0, scale: 0.97 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0 }}
                  transition={SPRING}
                >
                  <FileTreemap categories={scenario.categories} />
                </motion.div>
              </AnimatePresence>
            </div>
          </div>

          {/* RIGHT: Category donut + alerts */}
          <div className="space-y-3">
            {/* Category donut */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-2">
              <div className="flex items-center gap-2">
                <Database className="h-4 w-4 text-white/50" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Breakdown
                </span>
              </div>
              <div className="w-32 h-32 mx-auto">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={scenario.id}
                    initial={{ opacity: 0, rotate: -10 }}
                    animate={{ opacity: 1, rotate: 0 }}
                    exit={{ opacity: 0 }}
                    transition={SPRING}
                    className="w-full h-full"
                  >
                    <CategoryDonut categories={scenario.categories} size={140} />
                  </motion.div>
                </AnimatePresence>
              </div>
              <CategoryLegend categories={scenario.categories} />
            </div>

            {/* Alert ticker */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3 space-y-2">
              <div className="flex items-center gap-2">
                <AlertTriangle className="h-3.5 w-3.5 text-white/50" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Alert Log
                </span>
              </div>
              <AnimatePresence mode="wait">
                <motion.div
                  key={scenario.id}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.2 }}
                >
                  <AlertTicker alerts={scenario.alerts} />
                </motion.div>
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Terminal panel (full width) */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={SPRING}
          >
            <MiniTerminal lines={scenario.terminalLines} />
          </motion.div>
        </AnimatePresence>

        {/* Reset button */}
        <div className="flex justify-center">
          <motion.button
            type="button"
            onClick={() => handleSelectScenario(0)}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={SPRING}
            className="flex items-center gap-2 rounded-xl border border-white/[0.08] bg-white/[0.02] px-4 py-2 text-xs text-white/40 hover:text-white/60 transition-colors"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            Reset to Normal
          </motion.button>
        </div>
      </div>
    </div>
  );
}
