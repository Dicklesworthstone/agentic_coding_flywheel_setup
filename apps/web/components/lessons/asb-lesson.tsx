'use client';

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Terminal,
  Save,
  Clock,
  Play,
  Shield,
  Archive,
  RotateCcw,
  CheckCircle,
  AlertTriangle,
  Database,
  HardDrive,
  Hash,
  ChevronRight,
  Server,
  FileCheck,
  Copy,
  Layers,
  FolderSync,
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

function InteractiveBackupRestore() {
  return <InteractiveBackupRestoreImpl />;
}

export function AsbLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Back up and restore your AI agent configurations with Agent Settings Backup.
      </GoalBanner>

      {/* Section 1: What Is ASB */}
      <Section title="What Is ASB?" icon={<Save className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>ASB (Agent Settings Backup)</Highlight> is a smart backup tool
          for AI coding agent configuration folders. It backs up settings for Claude Code,
          Cursor, Codex CLI, Antigravity CLI, and other agents to a single versioned archive.
        </Paragraph>
        <Paragraph>
          When you provision a new machine or recover from a misconfiguration, ASB
          restores all your agent settings, skills, hooks, and preferences in one command.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Save className="h-5 w-5" />}
              title="Multi-Agent Backup"
              description="Claude, Cursor, Codex, Antigravity configs in one archive"
              gradient="from-emerald-500/20 to-green-500/20"
            />
            <FeatureCard
              icon={<FolderSync className="h-5 w-5" />}
              title="One-Command Restore"
              description="Restore all settings to a new machine instantly"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="Versioned Snapshots"
              description="Keep historical snapshots of your config state"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Selective Restore"
              description="Restore specific agents or specific config files"
              gradient="from-purple-500/20 to-violet-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      {/* Interactive Backup/Restore Visualization */}
      <InteractiveBackupRestore />

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'asb backup', description: 'Create a backup of all agent settings' },
            { command: 'asb restore', description: 'Restore settings from latest backup' },
            { command: 'asb list', description: 'List available backup snapshots' },
            { command: 'asb diff', description: 'Show changes since last backup' },
          ]}
        />

        <TipBox>
          Run ASB backup before provisioning new machines or making major configuration
          changes to your agent setups.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Back up all agent configs
asb backup

# Restore to a fresh machine
asb restore

# See what changed since last backup
asb diff`} />
      </Section>
    </div>
  );
}

// =============================================================================
// DATA & TYPES
// =============================================================================

interface AgentConfig {
  name: string;
  shortName: string;
  color: string;
  bgColor: string;
  files: string[];
  sizeMB: number;
}

const AGENTS: AgentConfig[] = [
  { name: 'Claude Code', shortName: 'claude', color: 'text-orange-400', bgColor: 'bg-orange-500', files: ['CLAUDE.md', 'hooks.json', 'settings.json'], sizeMB: 2.4 },
  { name: 'Cursor', shortName: 'cursor', color: 'text-blue-400', bgColor: 'bg-blue-500', files: ['settings.json', 'rules/', 'mcp.json'], sizeMB: 1.8 },
  { name: 'Codex CLI', shortName: 'codex', color: 'text-emerald-400', bgColor: 'bg-emerald-500', files: ['config.yaml', 'instructions.md'], sizeMB: 0.9 },
  { name: 'Antigravity CLI', shortName: 'agy', color: 'text-violet-400', bgColor: 'bg-violet-500', files: ['settings.json', 'hooks.json', 'AGENTS.md'], sizeMB: 1.1 },
  { name: 'Aider', shortName: 'aider', color: 'text-rose-400', bgColor: 'bg-rose-500', files: ['.aider.conf.yml', 'conventions.md'], sizeMB: 0.6 },
  { name: 'Cline', shortName: 'cline', color: 'text-cyan-400', bgColor: 'bg-cyan-500', files: ['cline_mcp.json', 'rules/'], sizeMB: 1.3 },
];

const TOTAL_SIZE_MB = AGENTS.reduce((sum, a) => sum + a.sizeMB, 0);

interface Scenario {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  command: string;
  terminalLines: string[];
  highlights: string;
}

const SCENARIOS: Scenario[] = [
  {
    id: 'scheduled',
    label: 'Scheduled Backup',
    icon: <Clock className="h-4 w-4" />,
    description: 'Automated daily backup captures all agent configs into a timestamped snapshot archive.',
    command: 'asb backup --scheduled',
    terminalLines: [
      '$ asb backup --scheduled',
      'Scheduled backup starting...',
      'Scanning 6 agent configurations...',
      '  claude: 3 files (2.4 MB)',
      '  cursor: 3 files (1.8 MB)',
      '  codex: 2 files (0.9 MB)',
      '  gemini: 2 files (1.1 MB)',
      '  aider: 2 files (0.6 MB)',
      '  cline: 2 files (1.3 MB)',
      'Compressing archive... 8.1 MB -> 3.2 MB',
      'Snapshot saved: backup-2026-03-12T08:00.tar.gz',
      'Checksum: sha256:a4f8c2...verified',
      'Scheduled backup complete!',
    ],
    highlights: 'All configs captured on schedule with automatic compression and checksum verification.',
  },
  {
    id: 'pre-deploy',
    label: 'Pre-Deploy Snapshot',
    icon: <Shield className="h-4 w-4" />,
    description: 'Create a safety snapshot before deploying major agent configuration changes.',
    command: 'asb backup --tag pre-deploy-v3',
    terminalLines: [
      '$ asb backup --tag pre-deploy-v3',
      'Creating tagged snapshot...',
      'Tag: pre-deploy-v3',
      'Scanning configurations...',
      '  All 6 agents detected',
      '  14 config files total',
      'Generating integrity checksums...',
      '  claude: sha256:7b2f91...ok',
      '  cursor: sha256:e3a4d8...ok',
      '  codex:  sha256:1c9fb0...ok',
      'Snapshot tagged and stored',
      'Retention: 30 days (policy: default)',
      'Safe to proceed with deployment!',
    ],
    highlights: 'Tagged snapshots let you label important milestones and roll back to exact known states.',
  },
  {
    id: 'disaster',
    label: 'Disaster Recovery',
    icon: <AlertTriangle className="h-4 w-4" />,
    description: 'Recover all agent configs after catastrophic data loss or system reinstall.',
    command: 'asb restore --latest',
    terminalLines: [
      '$ asb restore --latest',
      'Finding latest snapshot...',
      'Found: backup-2026-03-12T08:00.tar.gz',
      'Verifying archive integrity...',
      '  Checksum: sha256:a4f8c2...match!',
      'Restoring 6 agent configurations...',
      '  ~/.claude/    -> 3 files restored',
      '  ~/.cursor/    -> 3 files restored',
      '  ~/.codex/     -> 2 files restored',
      '  ~/.gemini/    -> 2 files restored',
      '  ~/.aider/     -> 2 files restored',
      '  ~/.cline/     -> 2 files restored',
      'All 14 files restored successfully!',
    ],
    highlights: 'Full disaster recovery restores every agent to its last known good state.',
  },
  {
    id: 'selective',
    label: 'Selective Restore',
    icon: <FileCheck className="h-4 w-4" />,
    description: 'Restore only specific agents or files without touching other configurations.',
    command: 'asb restore --agent claude --agent cursor',
    terminalLines: [
      '$ asb restore --agent claude --agent cursor',
      'Selective restore mode',
      'Target agents: claude, cursor',
      'Loading snapshot: backup-2026-03-12T08:00.tar.gz',
      'Extracting selected configs...',
      '  ~/.claude/CLAUDE.md      -> restored',
      '  ~/.claude/hooks.json     -> restored',
      '  ~/.claude/settings.json  -> restored',
      '  ~/.cursor/settings.json  -> restored',
      '  ~/.cursor/rules/         -> restored',
      '  ~/.cursor/mcp.json       -> restored',
      'Skipped: codex, gemini, aider, cline',
      '6 files restored (2 agents)',
    ],
    highlights: 'Restore just what you need. Other agent configs remain untouched.',
  },
  {
    id: 'migration',
    label: 'Cross-VPS Migration',
    icon: <Copy className="h-4 w-4" />,
    description: 'Export a portable backup and import it on a completely new VPS.',
    command: 'asb export --portable | ssh new-vps asb import',
    terminalLines: [
      '$ asb export --portable',
      'Creating portable archive...',
      'Including all 6 agent configs',
      'Embedding metadata and checksums...',
      'Archive: asb-portable-2026-03-12.tar.gz (3.2 MB)',
      '',
      '$ scp asb-portable-*.tar.gz user@new-vps:~/',
      'Transferred: 3.2 MB -> new-vps',
      '',
      '$ ssh new-vps asb import asb-portable-*.tar.gz',
      'Importing portable archive...',
      'Verified integrity: all checksums match',
      'All 6 agents configured on new VPS!',
    ],
    highlights: 'Portable exports bundle everything needed to replicate your setup on any machine.',
  },
  {
    id: 'verify',
    label: 'Backup Verification',
    icon: <Hash className="h-4 w-4" />,
    description: 'Verify backup integrity and compare checksums against live configurations.',
    command: 'asb verify --snapshot latest',
    terminalLines: [
      '$ asb verify --snapshot latest',
      'Loading snapshot metadata...',
      'Computing live checksums...',
      '',
      'Agent       Backup      Live        Status',
      '----------- ----------- ----------- ------',
      'claude      sha256:7b2f sha256:7b2f  MATCH',
      'cursor      sha256:e3a4 sha256:e3a4  MATCH',
      'codex       sha256:1c9f sha256:1c9f  MATCH',
      'gemini      sha256:0d8e sha256:0d8e  MATCH',
      'aider       sha256:5a71 sha256:a2c3  DRIFT',
      'cline       sha256:b6f2 sha256:b6f2  MATCH',
      '',
      '5/6 agents match. 1 has drifted.',
      'Run: asb backup --agent aider to update',
    ],
    highlights: 'Verification detects config drift so you know exactly when to re-backup.',
  },
];

type AnimPhase = 'idle' | 'running' | 'done';

// =============================================================================
// VPS STATE DIAGRAM (SVG)
// =============================================================================

function VpsStateDiagram({
  phase,
  scenarioId,
  progress,
}: {
  phase: AnimPhase;
  scenarioId: string;
  progress: number;
}) {
  const isRestore = scenarioId === 'disaster' || scenarioId === 'selective';
  const isVerify = scenarioId === 'verify';
  const isMigration = scenarioId === 'migration';

  const vpsColor = phase === 'done'
    ? 'rgba(52,211,153,0.3)'
    : phase === 'running'
      ? 'rgba(96,165,250,0.3)'
      : 'rgba(255,255,255,0.06)';

  const snapshotColor = phase === 'done'
    ? 'rgba(52,211,153,0.4)'
    : phase === 'running'
      ? 'rgba(251,191,36,0.4)'
      : 'rgba(255,255,255,0.08)';

  const arrowOpacity = phase === 'idle' ? 0.15 : 0.7;
  const flowDirection = isRestore ? -1 : 1;

  return (
    <svg viewBox="0 0 480 140" className="w-full h-auto" aria-hidden="true">
      {/* VPS Box */}
      <motion.rect
        x={20} y={20} width={160} height={100} rx={14}
        fill={vpsColor}
        stroke="rgba(255,255,255,0.12)"
        strokeWidth={1.5}
        animate={{ fill: vpsColor }}
        transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      />
      <text x={100} y={52} textAnchor="middle" className="fill-white/70 text-[11px] font-semibold">
        VPS System
      </text>
      <text x={100} y={72} textAnchor="middle" className="fill-white/40 text-[9px] font-mono">
        {AGENTS.length} agent configs
      </text>
      <text x={100} y={88} textAnchor="middle" className="fill-white/30 text-[9px] font-mono">
        {TOTAL_SIZE_MB.toFixed(1)} MB total
      </text>
      {/* Agent dots inside VPS */}
      {AGENTS.map((agent, i) => {
        const cx = 48 + (i % 3) * 36;
        const cy = 100 + Math.floor(i / 3) * 0; // single row at bottom of VPS
        const dotActive = phase === 'done' || (phase === 'running' && progress > (i / AGENTS.length));
        return (
          <motion.circle
            key={agent.shortName}
            cx={cx} cy={cy}
            r={4}
            className={dotActive ? ({
              'bg-orange-500': 'fill-orange-500',
              'bg-blue-500': 'fill-blue-500',
              'bg-emerald-500': 'fill-emerald-500',
              'bg-violet-500': 'fill-violet-500',
              'bg-rose-500': 'fill-rose-500',
              'bg-cyan-500': 'fill-cyan-500',
            }[agent.bgColor] ?? 'fill-white/50') : 'fill-white/10'}
            animate={{ r: dotActive ? 5 : 3.5, opacity: dotActive ? 0.9 : 0.3 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          />
        );
      })}

      {/* Arrow between VPS and Snapshot */}
      <g opacity={arrowOpacity}>
        <motion.line
          x1={195} y1={70} x2={280} y2={70}
          stroke="rgba(255,255,255,0.4)"
          strokeWidth={1.5}
          strokeDasharray="6 3"
          animate={{
            strokeDashoffset: phase === 'running' ? [0, flowDirection * -36] : 0,
          }}
          transition={phase === 'running' ? { duration: 1.2, repeat: Infinity, ease: 'linear' } : {}}
        />
        <motion.polygon
          points={isRestore ? '200,65 200,75 192,70' : '278,65 278,75 286,70'}
          fill="rgba(255,255,255,0.5)"
          animate={{ opacity: phase === 'running' ? [0.4, 1, 0.4] : arrowOpacity }}
          transition={phase === 'running' ? { duration: 1.0, repeat: Infinity } : {}}
        />
        <text
          x={238} y={62}
          textAnchor="middle"
          className="fill-white/30 text-[8px] font-mono"
        >
          {isRestore ? 'restore' : isVerify ? 'verify' : isMigration ? 'export' : 'snapshot'}
        </text>
      </g>

      {/* Snapshot Blob */}
      <motion.rect
        x={298} y={20} width={160} height={100} rx={14}
        fill={snapshotColor}
        stroke="rgba(255,255,255,0.12)"
        strokeWidth={1.5}
        animate={{ fill: snapshotColor }}
        transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      />
      <text x={378} y={48} textAnchor="middle" className="fill-white/70 text-[11px] font-semibold">
        {isMigration ? 'Portable Archive' : 'Snapshot Store'}
      </text>
      <text x={378} y={66} textAnchor="middle" className="fill-white/40 text-[9px] font-mono">
        .tar.gz compressed
      </text>
      <text x={378} y={82} textAnchor="middle" className="fill-white/30 text-[9px] font-mono">
        sha256 verified
      </text>

      {/* Progress bar inside snapshot box */}
      {phase === 'running' && (
        <g>
          <rect x={318} y={94} width={120} height={6} rx={3} fill="rgba(255,255,255,0.06)" />
          <motion.rect
            x={318} y={94} height={6} rx={3}
            fill="rgba(52,211,153,0.6)"
            animate={{ width: progress * 120 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          />
        </g>
      )}

      {/* Done checkmark */}
      {phase === 'done' && (
        <motion.g
          initial={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
        >
          <circle cx={378} cy={98} r={8} fill="rgba(52,211,153,0.3)" />
          <path d="M374,98 L377,101 L383,95" stroke="rgba(52,211,153,0.9)" strokeWidth={1.5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </motion.g>
      )}

      {/* Verify drift indicator */}
      {isVerify && phase === 'done' && (
        <motion.g
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.3, type: 'spring', stiffness: 200, damping: 25 }}
        >
          <rect x={330} y={108} width={96} height={16} rx={4} fill="rgba(251,191,36,0.15)" stroke="rgba(251,191,36,0.3)" strokeWidth={0.5} />
          <text x={378} y={120} textAnchor="middle" className="fill-amber-400/80 text-[8px] font-mono">
            1 drift detected
          </text>
        </motion.g>
      )}
    </svg>
  );
}

// =============================================================================
// STORAGE TIMELINE
// =============================================================================

interface TimelineEntry {
  label: string;
  sizeMB: number;
  daysAgo: number;
  tagged: boolean;
}

const TIMELINE_DATA: TimelineEntry[] = [
  { label: 'Today 08:00', sizeMB: 3.2, daysAgo: 0, tagged: true },
  { label: 'Yesterday', sizeMB: 3.1, daysAgo: 1, tagged: false },
  { label: '3 days ago', sizeMB: 3.0, daysAgo: 3, tagged: false },
  { label: '1 week ago', sizeMB: 2.8, daysAgo: 7, tagged: true },
  { label: '2 weeks ago', sizeMB: 2.5, daysAgo: 14, tagged: false },
];

const MAX_TIMELINE_SIZE = Math.max(...TIMELINE_DATA.map((e) => e.sizeMB));

function StorageTimeline({ visible }: { visible: boolean }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[10px] text-white/40 font-mono px-1">
        <span>Backup History</span>
        <span>Retention: 30 days</span>
      </div>
      <div className="space-y-1.5">
        {TIMELINE_DATA.map((entry, i) => {
          const widthPct = (entry.sizeMB / MAX_TIMELINE_SIZE) * 100;
          return (
            <motion.div
              key={entry.label}
              initial={{ opacity: 0, x: -20 }}
              animate={visible ? { opacity: 1, x: 0 } : { opacity: 0, x: -20 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.08 }}
              className="flex items-center gap-2"
            >
              <span className="text-[9px] text-white/30 font-mono w-20 shrink-0 text-right">
                {entry.label}
              </span>
              <div className="flex-1 h-5 relative">
                <div className="absolute inset-0 rounded-sm bg-white/[0.03]" />
                <motion.div
                  className={`absolute inset-y-0 left-0 rounded-sm ${entry.tagged ? 'bg-emerald-500/25' : 'bg-blue-500/15'}`}
                  initial={{ width: 0 }}
                  animate={visible ? { width: `${widthPct}%` } : { width: 0 }}
                  transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.08 + 0.15 }}
                />
                <div className="absolute inset-0 flex items-center px-2">
                  <span className="text-[9px] font-mono text-white/50">
                    {entry.sizeMB} MB
                  </span>
                </div>
              </div>
              {entry.tagged && (
                <span className="text-[8px] px-1.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400/70 border border-emerald-500/20 font-semibold">
                  TAG
                </span>
              )}
            </motion.div>
          );
        })}
      </div>
      {/* Usage summary */}
      <div className="flex items-center justify-between px-1 pt-1">
        <span className="text-[9px] text-white/25 font-mono">
          {TIMELINE_DATA.length} snapshots stored
        </span>
        <span className="text-[9px] text-white/25 font-mono">
          Total: {TIMELINE_DATA.reduce((s, e) => s + e.sizeMB, 0).toFixed(1)} MB
        </span>
      </div>
    </div>
  );
}

// =============================================================================
// CHECKSUM COMPARISON
// =============================================================================

interface ChecksumRow {
  agent: string;
  backupHash: string;
  liveHash: string;
  match: boolean;
}

const CHECKSUM_DATA: ChecksumRow[] = [
  { agent: 'claude', backupHash: '7b2f91a3', liveHash: '7b2f91a3', match: true },
  { agent: 'cursor', backupHash: 'e3a4d822', liveHash: 'e3a4d822', match: true },
  { agent: 'codex', backupHash: '1c9fb0e7', liveHash: '1c9fb0e7', match: true },
  { agent: 'gemini', backupHash: '0d8e4f19', liveHash: '0d8e4f19', match: true },
  { agent: 'aider', backupHash: '5a71c2d6', liveHash: 'a2c39b01', match: false },
  { agent: 'cline', backupHash: 'b6f2ea48', liveHash: 'b6f2ea48', match: true },
];

function ChecksumVerification({
  visible,
  revealedCount,
}: {
  visible: boolean;
  revealedCount: number;
}) {
  return (
    <div className="space-y-1.5">
      {/* Header */}
      <div className="grid grid-cols-[80px_1fr_1fr_50px] gap-2 text-[9px] font-mono text-white/30 px-2">
        <span>Agent</span>
        <span>Backup</span>
        <span>Live</span>
        <span className="text-right">Status</span>
      </div>
      {/* Rows */}
      {CHECKSUM_DATA.map((row, i) => {
        const revealed = visible && i < revealedCount;
        return (
          <motion.div
            key={row.agent}
            initial={{ opacity: 0, y: 6 }}
            animate={revealed ? { opacity: 1, y: 0 } : { opacity: 0, y: 6 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
            className={`grid grid-cols-[80px_1fr_1fr_50px] gap-2 text-[10px] font-mono px-2 py-1 rounded-md ${
              revealed && !row.match ? 'bg-amber-500/[0.06]' : 'bg-white/[0.01]'
            }`}
          >
            <span className="text-white/50">{row.agent}</span>
            <span className="text-blue-400/60 truncate">{row.backupHash}</span>
            <motion.span
              className={`truncate ${revealed ? (row.match ? 'text-emerald-400/60' : 'text-amber-400/80') : 'text-white/20'}`}
              animate={revealed && !row.match ? { opacity: [0.5, 1, 0.5] } : { opacity: 1 }}
              transition={revealed && !row.match ? { duration: 1.5, repeat: Infinity } : {}}
            >
              {revealed ? row.liveHash : '........'}
            </motion.span>
            <span className={`text-right font-semibold ${
              !revealed ? 'text-white/20' : row.match ? 'text-emerald-400/80' : 'text-amber-400/80'
            }`}>
              {!revealed ? '--' : row.match ? 'OK' : 'DRIFT'}
            </span>
          </motion.div>
        );
      })}
    </div>
  );
}

// =============================================================================
// RETENTION POLICY CHART
// =============================================================================

function RetentionChart({ visible }: { visible: boolean }) {
  const bars = [
    { label: 'Daily', count: 7, max: 7, color: 'bg-blue-500/30' },
    { label: 'Weekly', count: 4, max: 4, color: 'bg-violet-500/30' },
    { label: 'Monthly', count: 3, max: 6, color: 'bg-emerald-500/30' },
    { label: 'Tagged', count: 2, max: 10, color: 'bg-amber-500/30' },
  ];

  return (
    <div className="space-y-2">
      <div className="text-[10px] text-white/40 font-mono px-1">
        Retention Policy
      </div>
      <div className="space-y-2">
        {bars.map((bar, i) => (
          <motion.div
            key={bar.label}
            initial={{ opacity: 0, x: -10 }}
            animate={visible ? { opacity: 1, x: 0 } : { opacity: 0, x: -10 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.1 }}
            className="flex items-center gap-2"
          >
            <span className="text-[9px] text-white/40 font-mono w-14 text-right shrink-0">
              {bar.label}
            </span>
            <div className="flex-1 h-4 bg-white/[0.02] rounded-sm relative overflow-hidden">
              <motion.div
                className={`absolute inset-y-0 left-0 rounded-sm ${bar.color}`}
                initial={{ width: 0 }}
                animate={visible ? { width: `${(bar.count / bar.max) * 100}%` } : { width: 0 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.1 + 0.2 }}
              />
              <div className="absolute inset-0 flex items-center justify-end px-1.5">
                <span className="text-[8px] font-mono text-white/40">
                  {bar.count}/{bar.max}
                </span>
              </div>
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// =============================================================================
// MINI TERMINAL
// =============================================================================

function MiniTerminal({
  lines,
  visibleCount,
}: {
  lines: string[];
  visibleCount: number;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [visibleCount]);

  const displayed = lines.slice(0, visibleCount);

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      {/* Title bar */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06]">
        <div className="flex gap-1.5">
          <div className="h-2 w-2 rounded-full bg-red-500/60" />
          <div className="h-2 w-2 rounded-full bg-yellow-500/60" />
          <div className="h-2 w-2 rounded-full bg-green-500/60" />
        </div>
        <span className="text-[10px] text-white/30 font-mono ml-1">asb terminal</span>
      </div>
      {/* Body */}
      <div ref={scrollRef} className="p-3 font-mono text-[10px] leading-relaxed space-y-0.5 max-h-48 overflow-y-auto">
        <AnimatePresence initial={false}>
          {displayed.map((line, i) => (
            <motion.div
              key={`${i}-${line}`}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className={
                line.startsWith('$') ? 'text-emerald-400/80' :
                line.includes('DRIFT') || line.includes('drift') ? 'text-amber-400/80' :
                line.includes('restored') || line.includes('complete') || line.includes('match') || line.includes('verified') || line.includes('MATCH') || line.includes('OK') ? 'text-emerald-400/60' :
                line.includes('Agent') || line.includes('---') ? 'text-white/50' :
                line === '' ? 'h-2' :
                'text-white/35'
              }
            >
              {line || '\u00A0'}
            </motion.div>
          ))}
        </AnimatePresence>
        {/* Blinking cursor */}
        <motion.span
          className="inline-block w-1.5 h-3 bg-emerald-400/60"
          animate={{ opacity: [1, 0, 1] }}
          transition={{ duration: 1, repeat: Infinity }}
        />
      </div>
    </div>
  );
}

// =============================================================================
// MAIN INTERACTIVE COMPONENT
// =============================================================================

function InteractiveBackupRestoreImpl() {
  const [scenarioIndex, setScenarioIndex] = useState(0);
  const [phase, setPhase] = useState<AnimPhase>('idle');
  const [progress, setProgress] = useState(0);
  const [terminalVisibleCount, setTerminalVisibleCount] = useState(0);
  const [checksumRevealed, setChecksumRevealed] = useState(0);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const [snapshotIds] = useState<string[]>(() =>
    SCENARIOS.map((_, i) => `snap-${i}-${Date.now().toString(36)}`)
  );

  const scenario = SCENARIOS[scenarioIndex];
  const isVerifyScenario = scenario.id === 'verify';

  const clearTimers = useCallback(() => {
    for (const t of timersRef.current) clearTimeout(t);
    timersRef.current = [];
  }, []);

  useEffect(() => {
    return clearTimers;
  }, [clearTimers]);

  const resetScenario = useCallback(() => {
    clearTimers();
    setPhase('idle');
    setProgress(0);
    setTerminalVisibleCount(0);
    setChecksumRevealed(0);
  }, [clearTimers]);

  const switchScenario = useCallback(
    (idx: number) => {
      if (idx === scenarioIndex && phase === 'idle') return;
      resetScenario();
      setScenarioIndex(idx);
    },
    [scenarioIndex, phase, resetScenario],
  );

  const runScenario = useCallback(() => {
    if (phase === 'running') return;
    resetScenario();

    // Use setTimeout to avoid synchronous setState in rapid succession
    setTimeout(() => {
      setPhase('running');
      const totalLines = scenario.terminalLines.length;
      const lineDelay = 220;

      // Animate terminal lines one by one
      for (let i = 0; i < totalLines; i++) {
        const t = setTimeout(() => {
          setTerminalVisibleCount(i + 1);
          setProgress((i + 1) / totalLines);

          // For verify scenario, reveal checksum rows in sync
          if (isVerifyScenario && i >= 4 && i <= 11) {
            setChecksumRevealed(i - 3);
          }
        }, (i + 1) * lineDelay);
        timersRef.current.push(t);
      }

      // Mark done after all lines
      const doneTimer = setTimeout(() => {
        setPhase('done');
        if (isVerifyScenario) {
          setChecksumRevealed(CHECKSUM_DATA.length);
        }
      }, (totalLines + 1) * lineDelay);
      timersRef.current.push(doneTimer);
    }, 0);
  }, [phase, scenario, isVerifyScenario, resetScenario]);

  // Determine which panels to show based on scenario
  const showTimeline = scenario.id === 'scheduled' || scenario.id === 'pre-deploy';
  const showChecksums = scenario.id === 'verify';
  const showRetention = scenario.id === 'scheduled' || scenario.id === 'pre-deploy';

  const scenarioGlowColor = useMemo(() => {
    switch (scenario.id) {
      case 'scheduled': return 'emerald';
      case 'pre-deploy': return 'blue';
      case 'disaster': return 'red';
      case 'selective': return 'violet';
      case 'migration': return 'cyan';
      case 'verify': return 'amber';
      default: return 'emerald';
    }
  }, [scenario.id]);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className={`absolute top-0 left-1/4 w-64 h-64 rounded-full blur-3xl pointer-events-none transition-colors duration-700 ${
        scenarioGlowColor === 'emerald' ? 'bg-emerald-500/[0.06]' :
        scenarioGlowColor === 'blue' ? 'bg-blue-500/[0.06]' :
        scenarioGlowColor === 'red' ? 'bg-red-500/[0.06]' :
        scenarioGlowColor === 'violet' ? 'bg-violet-500/[0.06]' :
        scenarioGlowColor === 'cyan' ? 'bg-cyan-500/[0.06]' :
        scenarioGlowColor === 'amber' ? 'bg-amber-500/[0.06]' : 'bg-emerald-500/[0.06]'
      }`} />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-blue-500/[0.04] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-500/20 border border-emerald-500/30">
              <Archive className="h-4 w-4 text-emerald-400" />
            </div>
            <div>
              <span className="text-sm font-semibold text-white/80 block">Backup &amp; Restore Control Center</span>
              <span className="text-[10px] text-white/30">Explore 6 scenarios step by step</span>
            </div>
          </div>
          <button
            onClick={resetScenario}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-white/[0.06] border border-white/[0.08] text-white/50 hover:text-white/80 hover:bg-white/[0.1] transition-colors text-xs font-medium"
          >
            <RotateCcw className="h-3 w-3" />
            Reset
          </button>
        </div>

        {/* Scenario Stepper */}
        <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1">
          {SCENARIOS.map((sc, i) => {
            const isActive = i === scenarioIndex;
            return (
              <motion.button
                key={sc.id}
                onClick={() => switchScenario(i)}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.97 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-[11px] font-medium whitespace-nowrap transition-all shrink-0 ${
                  isActive
                    ? 'bg-white/[0.1] text-white/90 border border-white/[0.15] shadow-lg shadow-white/[0.02]'
                    : 'bg-white/[0.02] text-white/40 border border-white/[0.06] hover:bg-white/[0.05] hover:text-white/60'
                }`}
              >
                <span className={`transition-colors ${isActive ? 'text-emerald-400' : ''}`}>
                  {sc.icon}
                </span>
                <span className="hidden sm:inline">{sc.label}</span>
                <span className="sm:hidden">{sc.label.split(' ')[0]}</span>
              </motion.button>
            );
          })}
        </div>

        {/* Scenario Description */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="rounded-xl border border-white/[0.06] bg-white/[0.02] p-4"
          >
            <div className="flex items-start gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/[0.06] border border-white/[0.08]">
                {scenario.icon}
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-sm font-semibold text-white/80">{scenario.label}</div>
                <div className="text-xs text-white/40 mt-0.5">{scenario.description}</div>
                <div className="mt-2 flex items-center gap-1.5">
                  <span className="text-[10px] font-mono text-emerald-400/70 bg-emerald-500/[0.08] px-2 py-0.5 rounded-md border border-emerald-500/15">
                    {scenario.command}
                  </span>
                </div>
              </div>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* VPS State Diagram */}
        <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3">
          <div className="flex items-center gap-2 mb-2 px-1">
            <Server className="h-3.5 w-3.5 text-white/30" />
            <span className="text-[10px] text-white/30 font-medium">System State Diagram</span>
            {phase === 'done' && (
              <motion.span
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className="ml-auto text-[9px] font-semibold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400/80 border border-emerald-500/20"
              >
                Complete
              </motion.span>
            )}
          </div>
          <VpsStateDiagram
            phase={phase}
            scenarioId={scenario.id}
            progress={progress}
          />
        </div>

        {/* Two-column layout: terminal + side panel */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Terminal */}
          <div>
            <MiniTerminal
              lines={scenario.terminalLines}
              visibleCount={terminalVisibleCount}
            />
          </div>

          {/* Side panel: contextual based on scenario */}
          <div className="space-y-4">
            {showChecksums && (
              <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Hash className="h-3.5 w-3.5 text-white/30" />
                  <span className="text-[10px] text-white/30 font-medium">Integrity Verification</span>
                </div>
                <ChecksumVerification visible={phase !== 'idle'} revealedCount={checksumRevealed} />
              </div>
            )}

            {showTimeline && (
              <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Layers className="h-3.5 w-3.5 text-white/30" />
                  <span className="text-[10px] text-white/30 font-medium">Storage Timeline</span>
                </div>
                <StorageTimeline visible={phase !== 'idle'} />
              </div>
            )}

            {showRetention && (
              <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3">
                <RetentionChart visible={phase !== 'idle'} />
              </div>
            )}

            {!showChecksums && !showTimeline && (
              <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3 space-y-3">
                <div className="flex items-center gap-2 mb-1">
                  <Database className="h-3.5 w-3.5 text-white/30" />
                  <span className="text-[10px] text-white/30 font-medium">Agent Config Status</span>
                </div>
                {/* Agent status grid for restore/migration/selective */}
                <div className="grid grid-cols-2 gap-2">
                  {AGENTS.map((agent, i) => {
                    const isActive = phase === 'running' && progress > ((i + 0.5) / AGENTS.length);
                    const isDone = phase === 'done';
                    const isSelective = scenario.id === 'selective';
                    const isIncluded = !isSelective || agent.shortName === 'claude' || agent.shortName === 'cursor';
                    const statusLabel = isDone
                      ? (isIncluded ? 'Restored' : 'Skipped')
                      : isActive && isIncluded
                        ? 'Processing...'
                        : 'Waiting';

                    return (
                      <motion.div
                        key={agent.shortName}
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.05 }}
                        className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg border transition-all ${
                          isDone && isIncluded
                            ? 'border-emerald-500/20 bg-emerald-500/[0.05]'
                            : isDone && !isIncluded
                              ? 'border-white/[0.04] bg-white/[0.01] opacity-40'
                              : isActive && isIncluded
                                ? 'border-blue-500/20 bg-blue-500/[0.05]'
                                : 'border-white/[0.06] bg-white/[0.01]'
                        }`}
                      >
                        <div className={`h-1.5 w-1.5 rounded-full ${
                          isDone && isIncluded ? 'bg-emerald-400' :
                          isActive && isIncluded ? 'bg-blue-400' :
                          'bg-white/20'
                        }`} />
                        <div className="min-w-0 flex-1">
                          <div className={`text-[10px] font-semibold ${agent.color}`}>{agent.shortName}</div>
                          <div className="text-[8px] text-white/30">{statusLabel}</div>
                        </div>
                        <span className="text-[8px] font-mono text-white/20">{agent.sizeMB}MB</span>
                      </motion.div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Scenario Highlights */}
        <AnimatePresence mode="wait">
          {phase === 'done' && (
            <motion.div
              key={`highlight-${scenario.id}`}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="flex items-start gap-3 rounded-xl border border-emerald-500/15 bg-emerald-500/[0.04] p-4"
            >
              <CheckCircle className="h-4 w-4 text-emerald-400 shrink-0 mt-0.5" />
              <div className="text-xs text-emerald-300/70 leading-relaxed">
                {scenario.highlights}
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Action Bar */}
        <div className="flex items-center justify-between gap-3">
          {/* Run / Next controls */}
          <div className="flex items-center gap-2">
            <motion.button
              onClick={runScenario}
              disabled={phase === 'running'}
              whileHover={{ scale: 1.03 }}
              whileTap={{ scale: 0.97 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all ${
                phase === 'running'
                  ? 'bg-white/[0.02] text-white/20 border border-white/[0.06] cursor-not-allowed'
                  : phase === 'done'
                    ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/30'
                    : 'bg-blue-500/20 text-blue-400 border border-blue-500/30 hover:bg-blue-500/30'
              }`}
            >
              {phase === 'running' ? (
                <>
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                  >
                    <HardDrive className="h-4 w-4" />
                  </motion.div>
                  Running...
                </>
              ) : phase === 'done' ? (
                <>
                  <Play className="h-4 w-4" />
                  Replay
                </>
              ) : (
                <>
                  <Play className="h-4 w-4" />
                  Run Scenario
                </>
              )}
            </motion.button>

            {phase === 'done' && scenarioIndex < SCENARIOS.length - 1 && (
              <motion.button
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                onClick={() => switchScenario(scenarioIndex + 1)}
                whileHover={{ scale: 1.03 }}
                whileTap={{ scale: 0.97 }}
                className="flex items-center gap-1.5 px-3 py-2.5 rounded-lg text-sm font-medium bg-white/[0.06] text-white/60 border border-white/[0.08] hover:bg-white/[0.1] hover:text-white/80 transition-all"
              >
                Next Scenario
                <ChevronRight className="h-3.5 w-3.5" />
              </motion.button>
            )}
          </div>

          {/* Progress indicator */}
          <div className="flex items-center gap-1.5">
            {SCENARIOS.map((_, i) => (
              <button
                key={snapshotIds[i]}
                onClick={() => switchScenario(i)}
                className={`h-1.5 rounded-full transition-all ${
                  i === scenarioIndex
                    ? 'w-5 bg-white/40'
                    : 'w-1.5 bg-white/15 hover:bg-white/25'
                }`}
              />
            ))}
          </div>
        </div>

        {/* Phase hint */}
        <div className="text-center text-[11px] text-white/25">
          {phase === 'idle' && `Click "Run Scenario" to watch ${scenario.label.toLowerCase()} in action`}
          {phase === 'running' && `Executing ${scenario.command}...`}
          {phase === 'done' && (
            scenarioIndex < SCENARIOS.length - 1
              ? `Try the next scenario or replay this one`
              : 'All scenarios explored! Reset to revisit any scenario.'
          )}
        </div>
      </div>
    </div>
  );
}
