'use client';

import { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  BarChart3,
  Eye,
  Network,
  Cpu,
  Bot,
  Layers,
  TrendingUp,
  Play,
  Star,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Ban,
  ArrowRight,
  RotateCcw,
  Zap,
  Target,
  GitBranch,
  RefreshCw,
  Activity,
  Terminal,
  ChevronRight,
  Circle,
  Hash,
  Gauge,
  Shield,
  Trophy,
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

export function BvLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Use BV to triage issues with graph-aware intelligence and coordinate
        multi-agent work through robot mode.
      </GoalBanner>

      {/* Section 1: What Is BV */}
      <Section title="What Is BV?" icon={<Eye className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>BV (Beads Viewer)</Highlight> is a high-performance Terminal
          UI for browsing, triaging, and analyzing issues tracked by the Beads
          system. While <code>br</code> manages the issue data, BV is your
          intelligence layer — computing dependency graphs, identifying
          bottlenecks, and giving AI agents structured triage recommendations.
        </Paragraph>
        <Paragraph>
          BV computes 9+ graph metrics over your issue dependency graph, including
          PageRank, betweenness centrality, HITS scores, eigenvector centrality,
          and k-core decomposition. It uses these to surface the highest-impact
          work items automatically.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Network className="h-5 w-5" />}
              title="Graph Metrics"
              description="PageRank, betweenness, HITS, eigenvector, k-core"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Bot className="h-5 w-5" />}
              title="Robot Mode"
              description="40+ flags for AI agent automation"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="TUI Dashboard"
              description="Split-view Kanban with live reload"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<TrendingUp className="h-5 w-5" />}
              title="Drift Detection"
              description="Baseline snapshots with threshold alerts"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveGraphTriage />
      </div>

      <Divider />

      {/* Section 2: Robot Triage — The Mega-Command */}
      <Section title="Robot Triage" icon={<Bot className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          The <Highlight>--robot-triage</Highlight> flag is BV&apos;s mega-command.
          It runs a two-phase analysis — first computing graph metrics, then
          combining them with status, age, and blocking relationships to produce
          a prioritized list of what to work on next.
        </Paragraph>

        <CodeBlock
          code={`# Full triage with all metrics (the main entry point)
bv --robot-triage

# Just get the single top recommendation
bv --robot-next

# Triage grouped by label (for multi-agent workload splitting)
bv --robot-triage-by-label

# Triage grouped by track
bv --robot-triage-by-track

# Scope triage to a specific label
bv --robot-triage --label "backend"`}
          filename="Robot Triage"
        />

        <TipBox variant="tip">
          Always use <code>bv --robot-triage</code> as your starting point — never
          run bare <code>bv</code> from an agent. The robot flags produce
          structured JSON that agents can parse directly.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Graph Analysis Commands */}
      <Section title="Graph Analysis" icon={<Network className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          BV builds a full dependency graph from your issues and computes metrics
          used by real-world network analysis. These reveal which issues are true
          bottlenecks versus just noisy.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'bv --robot-insights', description: 'Full graph analysis with all metrics as JSON' },
            { command: 'bv --robot-priority', description: 'Priority recommendations based on graph centrality' },
            { command: 'bv --robot-plan', description: 'Dependency-respecting execution plan' },
            { command: 'bv --robot-blocker-chain', description: 'Find the longest blocking chains' },
            { command: 'bv --robot-orphans', description: 'Discover disconnected issues with no dependencies' },
            { command: 'bv --robot-related <bead-id>', description: 'Find issues related to a specific bead' },
            { command: 'bv --robot-graph --format mermaid', description: 'Export dependency graph as Mermaid diagram' },
          ]}
        />

        <TipBox variant="info">
          Graph metrics include confidence scores. High PageRank + high betweenness
          means an issue sits on many critical paths — fix it first.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: File Impact & Sprint Planning */}
      <Section title="Impact & Planning" icon={<Cpu className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          BV connects issues to source files, letting you assess the blast radius
          of changes and plan sprints with realistic capacity.
        </Paragraph>

        <CodeBlock
          code={`# Which beads touch this file?
bv --robot-file-beads src/auth/login.ts

# What's the blast radius of changing these files?
bv --robot-impact src/api/routes.ts,src/db/schema.ts

# Full impact network analysis
bv --robot-impact-network

# Code hotspots (files with the most linked issues)
bv --robot-file-hotspots

# Sprint capacity planning
bv --robot-capacity --agents=3

# Forecast completion ETAs
bv --robot-forecast`}
          filename="Impact Analysis"
        />
      </Section>

      <Divider />

      {/* Section 5: Diagnostics & Drift */}
      <Section title="Diagnostics & Drift" icon={<BarChart3 className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          BV can snapshot your project&apos;s health metrics and detect when things
          drift outside thresholds — useful for CI alerts or periodic health checks.
        </Paragraph>

        <CodeBlock
          code={`# Proactive alerts (drift + anomalies)
bv --robot-alerts

# Detect drift from baseline
bv --robot-drift

# Performance and cache metrics
bv --robot-metrics

# Diff since a git ref (time-travel)
bv --robot-diff --since HEAD~5

# View historical state
bv --as-of v1.0.0

# Label health (velocity, staleness, cascade effects)
bv --robot-label-health`}
          filename="Diagnostics"
        />

        <TipBox variant="tip">
          Use <code>bv --robot-alerts</code> in a cron job or CI step. Exit code
          0 means healthy, 1 means drifted, 2 means critical — perfect for
          automated monitoring.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Flywheel Integration */}
      <Section title="Flywheel Integration" icon={<TrendingUp className="h-5 w-5" />} delay={0.35}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">BV + BR</span>
            <p className="text-white/80 text-sm mt-1">BR manages issue data, BV analyzes it with graph intelligence</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">BV + NTM</span>
            <p className="text-white/80 text-sm mt-1">Use triage-by-label to assign work across spawned agents</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">BV + CASS</span>
            <p className="text-white/80 text-sm mt-1">Search past sessions for context on high-priority beads</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">BV + Agent Mail</span>
            <p className="text-white/80 text-sm mt-1">Coordinate triage decisions across concurrent agents</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Graph Triage Engine — Types & Data
// ---------------------------------------------------------------------------

type IssueStatus = 'open' | 'in-progress' | 'blocked' | 'done';

type AnalysisMode =
  | 'overview'
  | 'pagerank'
  | 'critical-path'
  | 'cycles'
  | 'quick-wins'
  | 'bottlenecks';

interface GraphNodeMetrics {
  pageRank: number;
  betweenness: number;
  hits_authority: number;
  hits_hub: number;
  eigenvector: number;
  kCore: number;
  inDegree: number;
  outDegree: number;
}

interface GraphNode {
  id: string;
  label: string;
  status: IssueStatus;
  x: number;
  y: number;
  metrics: GraphNodeMetrics;
  isQuickWin: boolean;
  why: string;
  blockedBy: string[];
  age: number; // days open
  track: string;
}

interface GraphEdge {
  from: string;
  to: string;
  isBlocker: boolean;
}

interface TriageRecommendation {
  id: string;
  action: string;
  reason: string;
  impact: 'critical' | 'high' | 'medium' | 'low';
  metric: string;
}

const GRAPH_NODES: GraphNode[] = [
  {
    id: 'DB',
    label: 'DB migration',
    status: 'in-progress',
    x: 320, y: 55,
    metrics: { pageRank: 0.31, betweenness: 0.82, hits_authority: 0.15, hits_hub: 0.91, eigenvector: 0.88, kCore: 3, inDegree: 0, outDegree: 4 },
    isQuickWin: false,
    why: 'Highest PageRank and betweenness -- sits on every critical path. Completing this unblocks 4 downstream issues.',
    blockedBy: [],
    age: 12,
    track: 'backend',
  },
  {
    id: 'AUTH',
    label: 'Auth refactor',
    status: 'blocked',
    x: 130, y: 140,
    metrics: { pageRank: 0.24, betweenness: 0.65, hits_authority: 0.40, hits_hub: 0.55, eigenvector: 0.72, kCore: 3, inDegree: 2, outDegree: 2 },
    isQuickWin: false,
    why: 'Blocks 2 downstream issues. High betweenness centrality makes it a critical relay node.',
    blockedBy: ['DB', 'CACHE'],
    age: 18,
    track: 'backend',
  },
  {
    id: 'API',
    label: 'API v2 endpoints',
    status: 'open',
    x: 510, y: 140,
    metrics: { pageRank: 0.18, betweenness: 0.48, hits_authority: 0.70, hits_hub: 0.20, eigenvector: 0.60, kCore: 3, inDegree: 3, outDegree: 2 },
    isQuickWin: false,
    why: 'High authority score -- many issues depend on it. Blocked by DB and AUTH.',
    blockedBy: ['DB', 'AUTH'],
    age: 10,
    track: 'backend',
  },
  {
    id: 'UI',
    label: 'Dashboard UI',
    status: 'open',
    x: 560, y: 270,
    metrics: { pageRank: 0.12, betweenness: 0.10, hits_authority: 0.85, hits_hub: 0.05, eigenvector: 0.35, kCore: 2, inDegree: 1, outDegree: 0 },
    isQuickWin: false,
    why: 'Leaf node with high authority -- user-visible but low graph impact.',
    blockedBy: ['API'],
    age: 5,
    track: 'frontend',
  },
  {
    id: 'TESTS',
    label: 'Integration tests',
    status: 'open',
    x: 320, y: 320,
    metrics: { pageRank: 0.09, betweenness: 0.05, hits_authority: 0.10, hits_hub: 0.08, eigenvector: 0.15, kCore: 1, inDegree: 1, outDegree: 0 },
    isQuickWin: true,
    why: 'No blockers, no dependents -- quick win for velocity stats.',
    blockedBy: [],
    age: 3,
    track: 'testing',
  },
  {
    id: 'CACHE',
    label: 'Cache layer',
    status: 'done',
    x: 100, y: 270,
    metrics: { pageRank: 0.05, betweenness: 0.22, hits_authority: 0.05, hits_hub: 0.40, eigenvector: 0.30, kCore: 2, inDegree: 0, outDegree: 2 },
    isQuickWin: false,
    why: 'Already completed -- contributed to unblocking AUTH.',
    blockedBy: [],
    age: 0,
    track: 'backend',
  },
  {
    id: 'DOCS',
    label: 'API documentation',
    status: 'open',
    x: 130, y: 380,
    metrics: { pageRank: 0.07, betweenness: 0.02, hits_authority: 0.05, hits_hub: 0.12, eigenvector: 0.08, kCore: 1, inDegree: 0, outDegree: 1 },
    isQuickWin: true,
    why: 'Isolated subgraph -- safe quick win with no risk of conflicts.',
    blockedBy: [],
    age: 7,
    track: 'docs',
  },
  {
    id: 'PERF',
    label: 'Perf optimization',
    status: 'blocked',
    x: 510, y: 380,
    metrics: { pageRank: 0.14, betweenness: 0.12, hits_authority: 0.75, hits_hub: 0.10, eigenvector: 0.42, kCore: 2, inDegree: 1, outDegree: 1 },
    isQuickWin: false,
    why: 'Blocked by API v2. High HITS authority -- final optimization pass.',
    blockedBy: ['API'],
    age: 14,
    track: 'backend',
  },
  {
    id: 'NOTIFY',
    label: 'Notification svc',
    status: 'open',
    x: 320, y: 190,
    metrics: { pageRank: 0.11, betweenness: 0.30, hits_authority: 0.50, hits_hub: 0.35, eigenvector: 0.45, kCore: 2, inDegree: 1, outDegree: 2 },
    isQuickWin: false,
    why: 'Medium betweenness -- bridges backend to frontend concerns.',
    blockedBy: ['DB'],
    age: 8,
    track: 'backend',
  },
  {
    id: 'BILLING',
    label: 'Billing module',
    status: 'open',
    x: 370, y: 420,
    metrics: { pageRank: 0.10, betweenness: 0.08, hits_authority: 0.60, hits_hub: 0.15, eigenvector: 0.28, kCore: 1, inDegree: 2, outDegree: 0 },
    isQuickWin: false,
    why: 'Depends on PERF and NOTIFY. Last node in critical chain.',
    blockedBy: ['PERF', 'NOTIFY'],
    age: 2,
    track: 'backend',
  },
];

const GRAPH_EDGES: GraphEdge[] = [
  { from: 'DB', to: 'AUTH', isBlocker: true },
  { from: 'DB', to: 'API', isBlocker: true },
  { from: 'DB', to: 'NOTIFY', isBlocker: true },
  { from: 'AUTH', to: 'API', isBlocker: false },
  { from: 'API', to: 'UI', isBlocker: false },
  { from: 'API', to: 'PERF', isBlocker: true },
  { from: 'CACHE', to: 'AUTH', isBlocker: false },
  { from: 'CACHE', to: 'TESTS', isBlocker: false },
  { from: 'DOCS', to: 'API', isBlocker: false },
  { from: 'NOTIFY', to: 'BILLING', isBlocker: false },
  { from: 'PERF', to: 'BILLING', isBlocker: false },
  { from: 'NOTIFY', to: 'UI', isBlocker: false },
];

// Simulated cycle for cycle detection mode
const CYCLE_EDGES: Array<{ from: string; to: string }> = [
  { from: 'API', to: 'NOTIFY' },
  { from: 'NOTIFY', to: 'PERF' },
  { from: 'PERF', to: 'API' },
];

// Critical path: DB -> API -> PERF -> BILLING (longest chain)
const CRITICAL_PATH_IDS = ['DB', 'API', 'PERF', 'BILLING'];
const CRITICAL_PATH_EDGES = [
  { from: 'DB', to: 'API' },
  { from: 'API', to: 'PERF' },
  { from: 'PERF', to: 'BILLING' },
];

const TRIAGE_RECOMMENDATIONS: TriageRecommendation[] = [
  { id: 'DB', action: 'Complete DB migration ASAP', reason: 'Highest PageRank (0.31) + betweenness (0.82). Unblocks 4 issues.', impact: 'critical', metric: 'pageRank + betweenness' },
  { id: 'AUTH', action: 'Unblock AUTH after DB completes', reason: 'Second-highest betweenness (0.65). Critical relay node.', impact: 'high', metric: 'betweenness' },
  { id: 'TESTS', action: 'Assign to idle agent now', reason: 'Zero dependencies, zero blockers. Free velocity.', impact: 'medium', metric: 'quick-win' },
  { id: 'DOCS', action: 'Parallel quick-win task', reason: 'Isolated subgraph. No conflict risk.', impact: 'medium', metric: 'quick-win' },
  { id: 'API', action: 'Queue after DB + AUTH', reason: 'High authority (0.70). Enables PERF and UI.', impact: 'high', metric: 'hits_authority' },
  { id: 'NOTIFY', action: 'Start after DB unblocks', reason: 'Bridges backend to frontend. Medium betweenness.', impact: 'medium', metric: 'betweenness' },
];

const STATUS_COLORS: Record<IssueStatus, { fill: string; stroke: string; text: string; bg: string; label: string }> = {
  'open':        { fill: '#3b82f6', stroke: '#60a5fa', text: 'text-blue-400',    bg: 'bg-blue-500',    label: 'Open' },
  'in-progress': { fill: '#f59e0b', stroke: '#fbbf24', text: 'text-amber-400',   bg: 'bg-amber-500',   label: 'In Progress' },
  'blocked':     { fill: '#ef4444', stroke: '#f87171', text: 'text-red-400',     bg: 'bg-red-500',     label: 'Blocked' },
  'done':        { fill: '#22c55e', stroke: '#4ade80', text: 'text-emerald-400', bg: 'bg-emerald-500', label: 'Done' },
};

const IMPACT_COLORS: Record<TriageRecommendation['impact'], string> = {
  critical: 'text-red-400 bg-red-500/10 border-red-500/30',
  high: 'text-amber-400 bg-amber-500/10 border-amber-500/30',
  medium: 'text-blue-400 bg-blue-500/10 border-blue-500/30',
  low: 'text-white/50 bg-white/[0.04] border-white/[0.08]',
};

const MODE_CONFIG: Record<AnalysisMode, { label: string; icon: typeof Eye; description: string }> = {
  'overview':      { label: 'Overview',      icon: Eye,        description: 'Full dependency graph with status coloring' },
  'pagerank':      { label: 'PageRank',      icon: Trophy,     description: 'Node size scaled by PageRank score' },
  'critical-path': { label: 'Critical Path', icon: GitBranch,  description: 'Longest dependency chain highlighted' },
  'cycles':        { label: 'Cycles',        icon: RefreshCw,  description: 'Circular dependency detection' },
  'quick-wins':    { label: 'Quick Wins',    icon: Zap,        description: 'Zero-dependency tasks for free velocity' },
  'bottlenecks':   { label: 'Bottlenecks',   icon: Target,     description: 'High betweenness centrality nodes' },
};

const TERMINAL_COMMANDS: Record<AnalysisMode, string[]> = {
  'overview': [
    '$ bv --robot-triage',
    '{"phase":"graph_metrics","nodes":10,"edges":12}',
    '{"phase":"priority_rank","top":"DB","score":0.31}',
    '{"status":"complete","recommendations":6}',
  ],
  'pagerank': [
    '$ bv --robot-insights --metric pagerank',
    '{"DB":0.31,"AUTH":0.24,"API":0.18,"PERF":0.14}',
    '{"UI":0.12,"NOTIFY":0.11,"BILLING":0.10}',
    '{"TESTS":0.09,"DOCS":0.07,"CACHE":0.05}',
  ],
  'critical-path': [
    '$ bv --robot-blocker-chain',
    '{"chain":["DB","API","PERF","BILLING"]}',
    '{"length":4,"estimated_days":28}',
    '{"bottleneck":"DB","blocks_remaining":3}',
  ],
  'cycles': [
    '$ bv --robot-insights --cycles',
    '{"warning":"cycle_detected","nodes":3}',
    '{"cycle":["API","NOTIFY","PERF","API"]}',
    '{"recommendation":"break_edge PERF->API"}',
  ],
  'quick-wins': [
    '$ bv --robot-triage --filter quick-wins',
    '{"quick_wins":["TESTS","DOCS"]}',
    '{"TESTS":{"blockers":0,"dependents":0}}',
    '{"DOCS":{"blockers":0,"dependents":1}}',
  ],
  'bottlenecks': [
    '$ bv --robot-priority --metric betweenness',
    '{"DB":{"betweenness":0.82,"blocking":4}}',
    '{"AUTH":{"betweenness":0.65,"blocking":2}}',
    '{"API":{"betweenness":0.48,"blocking":2}}',
  ],
};

// ---------------------------------------------------------------------------
// InteractiveGraphTriage — The Main Visualization
// ---------------------------------------------------------------------------

function InteractiveGraphTriage() {
  const [triageRun, setTriageRun] = useState(false);
  const [animatingPhase, setAnimatingPhase] = useState<'idle' | 'computing' | 'done'>('idle');
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  const [analysisMode, setAnalysisMode] = useState<AnalysisMode>('overview');
  const [criticalPathStep, setCriticalPathStep] = useState(0);
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const [showMetricsDetail, setShowMetricsDetail] = useState(false);
  const terminalRef = useRef<HTMLDivElement>(null);
  const criticalPathTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Clean up timers on unmount
  useEffect(() => {
    return () => {
      if (criticalPathTimerRef.current) {
        clearInterval(criticalPathTimerRef.current);
      }
    };
  }, []);

  // Animate terminal output when mode changes
  useEffect(() => {
    if (!triageRun) return;
    const timers: ReturnType<typeof setTimeout>[] = [];
    const commands = TERMINAL_COMMANDS[analysisMode];
    commands.forEach((line, i) => {
      const t = setTimeout(() => {
        setTerminalLines((prev) => [...prev, line]);
      }, (i + 1) * 350);
      timers.push(t);
    });
    return () => {
      timers.forEach(clearTimeout);
    };
  }, [analysisMode, triageRun]);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      const el = terminalRef.current;
      setTimeout(() => {
        el.scrollTop = el.scrollHeight;
      }, 0);
    }
  }, [terminalLines]);

  // Animate critical path tracing
  useEffect(() => {
    if (analysisMode !== 'critical-path' || !triageRun) {
      if (criticalPathTimerRef.current) {
        clearInterval(criticalPathTimerRef.current);
        criticalPathTimerRef.current = null;
      }
      return;
    }
    criticalPathTimerRef.current = setInterval(() => {
      setCriticalPathStep((prev) => {
        if (prev >= CRITICAL_PATH_IDS.length) {
          return 0;
        }
        return prev + 1;
      });
    }, 900);
    return () => {
      if (criticalPathTimerRef.current) {
        clearInterval(criticalPathTimerRef.current);
        criticalPathTimerRef.current = null;
      }
    };
  }, [analysisMode, triageRun]);

  const topNode = useMemo(() => {
    return GRAPH_NODES.reduce((best, n) =>
      n.status !== 'done' && n.metrics.pageRank > best.metrics.pageRank ? n : best
    , GRAPH_NODES[0]);
  }, []);

  const handleRunTriage = useCallback(() => {
    if (animatingPhase === 'computing') return;
    setTriageRun(false);
    setAnimatingPhase('computing');
    setSelectedNode(null);
    setTerminalLines([]);
    setCriticalPathStep(0);
    setTimeout(() => {
      setTriageRun(true);
      setAnimatingPhase('done');
      setSelectedNode(topNode.id);
    }, 1800);
  }, [animatingPhase, topNode.id]);

  const handleAnalysisModeChange = useCallback((mode: AnalysisMode) => {
    if (criticalPathTimerRef.current) {
      clearInterval(criticalPathTimerRef.current);
      criticalPathTimerRef.current = null;
    }
    setCriticalPathStep(0);
    setTerminalLines([]);
    setAnalysisMode(mode);
  }, []);

  const handleReset = useCallback(() => {
    setTriageRun(false);
    setAnimatingPhase('idle');
    setSelectedNode(null);
    setAnalysisMode('overview');
    setTerminalLines([]);
    setCriticalPathStep(0);
    setShowMetricsDetail(false);
  }, []);

  const getNodeRadius = useCallback((node: GraphNode): number => {
    if (!triageRun) return 20;
    switch (analysisMode) {
      case 'pagerank':
        return 14 + node.metrics.pageRank * 60;
      case 'bottlenecks':
        return 14 + node.metrics.betweenness * 30;
      case 'quick-wins':
        return node.isQuickWin ? 28 : 16;
      default:
        return 14 + node.metrics.pageRank * 50;
    }
  }, [triageRun, analysisMode]);

  const getNodeOpacity = useCallback((node: GraphNode): number => {
    if (!triageRun) return 1;
    switch (analysisMode) {
      case 'quick-wins':
        return node.isQuickWin && node.status !== 'done' ? 1 : 0.3;
      case 'critical-path':
        return CRITICAL_PATH_IDS.includes(node.id) ? 1 : 0.25;
      case 'bottlenecks':
        return node.metrics.betweenness > 0.3 ? 1 : 0.3;
      case 'cycles': {
        const cycleNodeIds = new Set(CYCLE_EDGES.flatMap((e) => [e.from, e.to]));
        return cycleNodeIds.has(node.id) ? 1 : 0.25;
      }
      default:
        return 1;
    }
  }, [triageRun, analysisMode]);

  const selectedData = useMemo(() => {
    if (!selectedNode) return null;
    return GRAPH_NODES.find((n) => n.id === selectedNode) ?? null;
  }, [selectedNode]);

  const sortedNodes = useMemo(() => {
    return [...GRAPH_NODES]
      .filter((n) => n.status !== 'done')
      .sort((a, b) => b.metrics.pageRank - a.metrics.pageRank);
  }, []);

  const quickWinNodes = useMemo(() => {
    return GRAPH_NODES.filter((n) => n.isQuickWin && n.status !== 'done');
  }, []);

  const bottleneckNodes = useMemo(() => {
    return [...GRAPH_NODES]
      .filter((n) => n.metrics.betweenness > 0.3 && n.status !== 'done')
      .sort((a, b) => b.metrics.betweenness - a.metrics.betweenness);
  }, []);

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-80 h-80 bg-violet-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-64 h-64 bg-blue-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-indigo-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 lg:p-8 space-y-5">
        {/* Header */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-violet-500/20 bg-violet-500/[0.06]">
            <Network className="h-3.5 w-3.5 text-violet-400" />
            <span className="text-xs font-semibold text-violet-400 uppercase tracking-wider">
              Graph Triage Engine
            </span>
          </div>
          <p className="text-sm text-white/50">
            {triageRun
              ? 'Explore 6 analysis modes to understand your dependency graph'
              : 'Click "Run Triage" to compute graph metrics and see recommendations'}
          </p>
        </div>

        {/* Analysis Mode Tabs */}
        <AnimatePresence>
          {triageRun && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            >
              <div className="flex flex-wrap items-center justify-center gap-1.5 sm:gap-2">
                {(Object.entries(MODE_CONFIG) as [AnalysisMode, typeof MODE_CONFIG[AnalysisMode]][]).map(([mode, config]) => {
                  const ModeIcon = config.icon;
                  const isActive = analysisMode === mode;
                  return (
                    <motion.button
                      key={mode}
                      type="button"
                      onClick={() => handleAnalysisModeChange(mode)}
                      whileHover={{ scale: 1.04 }}
                      whileTap={{ scale: 0.96 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                      className={`flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-medium transition ${
                        isActive
                          ? 'border border-violet-500/40 bg-violet-500/15 text-violet-300 shadow-lg shadow-violet-500/10'
                          : 'border border-white/[0.06] bg-white/[0.02] text-white/40 hover:text-white/60 hover:bg-white/[0.04]'
                      }`}
                    >
                      <ModeIcon className="h-3 w-3" />
                      <span className="hidden sm:inline">{config.label}</span>
                    </motion.button>
                  );
                })}
              </div>
              {/* Mode description */}
              <p className="text-center text-[10px] text-white/30 mt-2">
                {MODE_CONFIG[analysisMode].description}
              </p>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Legend */}
        <div className="flex flex-wrap items-center justify-center gap-3 sm:gap-4">
          {(Object.entries(STATUS_COLORS) as [IssueStatus, typeof STATUS_COLORS[IssueStatus]][]).map(([status, meta]) => (
            <div key={status} className="flex items-center gap-1.5">
              <div className={`h-2.5 w-2.5 rounded-full ${meta.bg}`} />
              <span className="text-[10px] text-white/50">{meta.label}</span>
            </div>
          ))}
          <div className="flex items-center gap-1.5">
            <Star className="h-2.5 w-2.5 text-yellow-400" />
            <span className="text-[10px] text-white/50">Quick Win</span>
          </div>
          {triageRun && analysisMode === 'critical-path' && (
            <div className="flex items-center gap-1.5">
              <div className="h-2.5 w-5 rounded bg-gradient-to-r from-cyan-400 to-cyan-500" />
              <span className="text-[10px] text-cyan-400/70">Critical Path</span>
            </div>
          )}
          {triageRun && analysisMode === 'cycles' && (
            <div className="flex items-center gap-1.5">
              <div className="h-2.5 w-5 rounded bg-gradient-to-r from-red-400 to-rose-500" />
              <span className="text-[10px] text-red-400/70">Cycle</span>
            </div>
          )}
        </div>

        <div className="flex flex-col xl:flex-row gap-5">
          {/* Left: SVG Graph + Controls */}
          <div className="flex-1 min-w-0 space-y-4">
            {/* SVG Dependency Graph */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-2 overflow-hidden relative">
              {/* Computing overlay */}
              <AnimatePresence>
                {animatingPhase === 'computing' && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="absolute inset-0 z-10 flex flex-col items-center justify-center bg-black/40 backdrop-blur-sm rounded-2xl"
                  >
                    <motion.div
                      animate={{ rotate: 360 }}
                      transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
                    >
                      <Network className="h-8 w-8 text-violet-400" />
                    </motion.div>
                    <motion.p
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ delay: 0.3 }}
                      className="text-sm text-violet-300 mt-3 font-mono"
                    >
                      Computing graph metrics...
                    </motion.p>
                    <div className="flex gap-1 mt-2">
                      {['PageRank', 'Betweenness', 'HITS', 'Eigenvector'].map((metric, i) => (
                        <motion.span
                          key={metric}
                          initial={{ opacity: 0, scale: 0.8 }}
                          animate={{ opacity: 1, scale: 1 }}
                          transition={{ delay: 0.5 + i * 0.25 }}
                          className="text-[9px] px-1.5 py-0.5 rounded bg-white/[0.06] text-white/40 font-mono"
                        >
                          {metric}
                        </motion.span>
                      ))}
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>

              <svg
                viewBox="0 0 660 470"
                className="w-full h-auto"
                style={{ minHeight: 300 }}
              >
                <defs>
                  <marker id="bv-arrow" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
                    <polygon points="0 0, 8 3, 0 6" fill="rgba(255,255,255,0.25)" />
                  </marker>
                  <marker id="bv-arrow-red" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
                    <polygon points="0 0, 8 3, 0 6" fill="rgba(239,68,68,0.6)" />
                  </marker>
                  <marker id="bv-arrow-cyan" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
                    <polygon points="0 0, 8 3, 0 6" fill="rgba(34,211,238,0.8)" />
                  </marker>
                  <marker id="bv-arrow-cycle" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
                    <polygon points="0 0, 8 3, 0 6" fill="rgba(244,63,94,0.8)" />
                  </marker>
                  <filter id="bv-glow" x="-50%" y="-50%" width="200%" height="200%">
                    <feGaussianBlur stdDeviation="6" result="blur" />
                    <feMerge>
                      <feMergeNode in="blur" />
                      <feMergeNode in="SourceGraphic" />
                    </feMerge>
                  </filter>
                  <filter id="bv-glow-cyan" x="-50%" y="-50%" width="200%" height="200%">
                    <feGaussianBlur stdDeviation="4" result="blur" />
                    <feFlood floodColor="#22d3ee" floodOpacity="0.3" result="color" />
                    <feComposite in="color" in2="blur" operator="in" result="glow" />
                    <feMerge>
                      <feMergeNode in="glow" />
                      <feMergeNode in="SourceGraphic" />
                    </feMerge>
                  </filter>
                  <filter id="bv-glow-red" x="-50%" y="-50%" width="200%" height="200%">
                    <feGaussianBlur stdDeviation="4" result="blur" />
                    <feFlood floodColor="#f43f5e" floodOpacity="0.3" result="color" />
                    <feComposite in="color" in2="blur" operator="in" result="glow" />
                    <feMerge>
                      <feMergeNode in="glow" />
                      <feMergeNode in="SourceGraphic" />
                    </feMerge>
                  </filter>
                  <linearGradient id="bv-critical-grad" x1="0%" y1="0%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.8" />
                    <stop offset="100%" stopColor="#06b6d4" stopOpacity="0.4" />
                  </linearGradient>
                  <linearGradient id="bv-cycle-grad" x1="0%" y1="0%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor="#f43f5e" stopOpacity="0.8" />
                    <stop offset="100%" stopColor="#e11d48" stopOpacity="0.4" />
                  </linearGradient>
                </defs>

                {/* Regular Edges */}
                {GRAPH_EDGES.map((edge) => {
                  const fromNode = GRAPH_NODES.find((n) => n.id === edge.from);
                  const toNode = GRAPH_NODES.find((n) => n.id === edge.to);
                  if (!fromNode || !toNode) return null;

                  // Check if edge is on critical path
                  const isCriticalEdge = triageRun && analysisMode === 'critical-path' &&
                    CRITICAL_PATH_EDGES.some((cp) => cp.from === edge.from && cp.to === edge.to);

                  // Determine edge opacity based on mode
                  let edgeOpacity = 1;
                  if (triageRun) {
                    if (analysisMode === 'critical-path' && !isCriticalEdge) edgeOpacity = 0.15;
                    if (analysisMode === 'quick-wins') edgeOpacity = 0.1;
                    if (analysisMode === 'cycles') edgeOpacity = 0.1;
                    if (analysisMode === 'bottlenecks') {
                      const isBetweenBottlenecks = fromNode.metrics.betweenness > 0.3 || toNode.metrics.betweenness > 0.3;
                      edgeOpacity = isBetweenBottlenecks ? 0.6 : 0.1;
                    }
                  }

                  return (
                    <line
                      key={`${edge.from}-${edge.to}`}
                      x1={fromNode.x}
                      y1={fromNode.y}
                      x2={toNode.x}
                      y2={toNode.y}
                      stroke={
                        isCriticalEdge
                          ? '#22d3ee'
                          : edge.isBlocker
                            ? 'rgba(239,68,68,0.4)'
                            : 'rgba(255,255,255,0.12)'
                      }
                      strokeWidth={isCriticalEdge ? 3 : edge.isBlocker ? 2 : 1.5}
                      strokeDasharray={isCriticalEdge ? 'none' : edge.isBlocker ? '6 4' : 'none'}
                      markerEnd={
                        isCriticalEdge
                          ? 'url(#bv-arrow-cyan)'
                          : edge.isBlocker
                            ? 'url(#bv-arrow-red)'
                            : 'url(#bv-arrow)'
                      }
                      opacity={edgeOpacity}
                      filter={isCriticalEdge ? 'url(#bv-glow-cyan)' : undefined}
                    />
                  );
                })}

                {/* Cycle edges (shown only in cycle detection mode) */}
                {triageRun && analysisMode === 'cycles' && CYCLE_EDGES.map((edge) => {
                  const fromNode = GRAPH_NODES.find((n) => n.id === edge.from);
                  const toNode = GRAPH_NODES.find((n) => n.id === edge.to);
                  if (!fromNode || !toNode) return null;

                  // Offset cycle edges slightly for visibility
                  const dx = toNode.x - fromNode.x;
                  const dy = toNode.y - fromNode.y;
                  const len = Math.sqrt(dx * dx + dy * dy) || 1;
                  const offsetX = (-dy / len) * 12;
                  const offsetY = (dx / len) * 12;

                  const midX = (fromNode.x + toNode.x) / 2 + offsetX * 2;
                  const midY = (fromNode.y + toNode.y) / 2 + offsetY * 2;

                  return (
                    <path
                      key={`cycle-${edge.from}-${edge.to}`}
                      d={`M ${fromNode.x + offsetX} ${fromNode.y + offsetY} Q ${midX} ${midY} ${toNode.x + offsetX} ${toNode.y + offsetY}`}
                      stroke="#f43f5e"
                      strokeWidth={2.5}
                      fill="none"
                      strokeDasharray="8 4"
                      markerEnd="url(#bv-arrow-cycle)"
                      filter="url(#bv-glow-red)"
                      opacity={0.8}
                    >
                      <animate
                        attributeName="stroke-dashoffset"
                        values="0;-24"
                        dur="1.5s"
                        repeatCount="indefinite"
                      />
                    </path>
                  );
                })}

                {/* Critical path animated trace */}
                {triageRun && analysisMode === 'critical-path' && CRITICAL_PATH_EDGES.map((edge, i) => {
                  const fromNode = GRAPH_NODES.find((n) => n.id === edge.from);
                  const toNode = GRAPH_NODES.find((n) => n.id === edge.to);
                  if (!fromNode || !toNode) return null;

                  const isTraced = criticalPathStep > i;

                  return isTraced ? (
                    <line
                      key={`cp-trace-${edge.from}-${edge.to}`}
                      x1={fromNode.x}
                      y1={fromNode.y}
                      x2={toNode.x}
                      y2={toNode.y}
                      stroke="#22d3ee"
                      strokeWidth={4}
                      opacity={0.6}
                      filter="url(#bv-glow-cyan)"
                    >
                      <animate
                        attributeName="opacity"
                        values="0.4;0.8;0.4"
                        dur="2s"
                        repeatCount="indefinite"
                      />
                    </line>
                  ) : null;
                })}

                {/* Nodes */}
                {GRAPH_NODES.map((node) => {
                  const radius = getNodeRadius(node);
                  const nodeOpacity = getNodeOpacity(node);
                  const color = STATUS_COLORS[node.status];
                  const isTop = triageRun && node.id === topNode.id;
                  const isSelected = node.id === selectedNode;
                  const isOnCriticalPath = triageRun && analysisMode === 'critical-path' && CRITICAL_PATH_IDS.includes(node.id);
                  const isCriticalPathActive = isOnCriticalPath && CRITICAL_PATH_IDS.indexOf(node.id) < criticalPathStep;
                  const cycleNodeIds = new Set(CYCLE_EDGES.flatMap((e) => [e.from, e.to]));
                  const isInCycle = triageRun && analysisMode === 'cycles' && cycleNodeIds.has(node.id);
                  const isBottleneck = triageRun && analysisMode === 'bottlenecks' && node.metrics.betweenness > 0.3;

                  return (
                    <g
                      key={node.id}
                      style={{ cursor: 'pointer' }}
                      opacity={nodeOpacity}
                      onClick={() => setSelectedNode(node.id === selectedNode ? null : node.id)}
                    >
                      {/* Top recommendation pulsing glow */}
                      {isTop && analysisMode === 'overview' && (
                        <circle
                          cx={node.x}
                          cy={node.y}
                          r={radius + 8}
                          fill="none"
                          stroke={color.stroke}
                          strokeWidth={2}
                          opacity={0.5}
                          filter="url(#bv-glow)"
                        >
                          <animate attributeName="r" values={`${radius + 6};${radius + 14};${radius + 6}`} dur="2s" repeatCount="indefinite" />
                          <animate attributeName="opacity" values="0.5;0.2;0.5" dur="2s" repeatCount="indefinite" />
                        </circle>
                      )}

                      {/* Critical path glow ring */}
                      {isCriticalPathActive && (
                        <circle
                          cx={node.x}
                          cy={node.y}
                          r={radius + 6}
                          fill="none"
                          stroke="#22d3ee"
                          strokeWidth={2}
                          filter="url(#bv-glow-cyan)"
                        >
                          <animate attributeName="opacity" values="0.8;0.3;0.8" dur="1.5s" repeatCount="indefinite" />
                        </circle>
                      )}

                      {/* Cycle warning ring */}
                      {isInCycle && (
                        <circle
                          cx={node.x}
                          cy={node.y}
                          r={radius + 6}
                          fill="none"
                          stroke="#f43f5e"
                          strokeWidth={2}
                          strokeDasharray="4 3"
                          filter="url(#bv-glow-red)"
                        >
                          <animate attributeName="stroke-dashoffset" values="0;-14" dur="1s" repeatCount="indefinite" />
                        </circle>
                      )}

                      {/* Bottleneck ring */}
                      {isBottleneck && (
                        <circle
                          cx={node.x}
                          cy={node.y}
                          r={radius + 6}
                          fill="none"
                          stroke="#f59e0b"
                          strokeWidth={2}
                          filter="url(#bv-glow)"
                        >
                          <animate attributeName="opacity" values="0.7;0.3;0.7" dur="2s" repeatCount="indefinite" />
                        </circle>
                      )}

                      {/* Selection ring */}
                      {isSelected && (
                        <circle
                          cx={node.x}
                          cy={node.y}
                          r={radius + 4}
                          fill="none"
                          stroke="rgba(255,255,255,0.5)"
                          strokeWidth={1.5}
                          strokeDasharray="4 3"
                        />
                      )}

                      {/* Main circle */}
                      <circle
                        cx={node.x}
                        cy={node.y}
                        r={radius}
                        fill={
                          isInCycle
                            ? 'rgba(244,63,94,0.15)'
                            : isCriticalPathActive
                              ? 'rgba(34,211,238,0.15)'
                              : `${color.fill}20`
                        }
                        stroke={
                          isInCycle
                            ? '#f43f5e'
                            : isCriticalPathActive
                              ? '#22d3ee'
                              : color.stroke
                        }
                        strokeWidth={isSelected ? 2.5 : 1.5}
                      />

                      {/* Center status dot */}
                      <circle
                        cx={node.x}
                        cy={node.y}
                        r={4}
                        fill={color.fill}
                        opacity={0.8}
                      />

                      {/* Node label above */}
                      <text
                        x={node.x}
                        y={node.y - radius - 8}
                        textAnchor="middle"
                        fill="rgba(255,255,255,0.7)"
                        fontSize="10"
                        fontFamily="monospace"
                      >
                        {node.id}
                      </text>

                      {/* Metric score below (shown after triage) */}
                      {triageRun && (
                        <text
                          x={node.x}
                          y={node.y + radius + 14}
                          textAnchor="middle"
                          fill={
                            isInCycle ? '#f43f5e'
                              : isCriticalPathActive ? '#22d3ee'
                                : color.stroke
                          }
                          fontSize="10"
                          fontWeight="bold"
                          fontFamily="monospace"
                        >
                          {analysisMode === 'bottlenecks'
                            ? `B:${node.metrics.betweenness.toFixed(2)}`
                            : `PR:${node.metrics.pageRank.toFixed(2)}`}
                        </text>
                      )}

                      {/* Quick-win star badge */}
                      {triageRun && node.isQuickWin && node.status !== 'done' && (
                        <g transform={`translate(${node.x + radius - 2}, ${node.y - radius + 2})`}>
                          <circle cx={0} cy={0} r={7} fill="#422006" stroke="#facc15" strokeWidth={1} />
                          <text x={0} y={3.5} textAnchor="middle" fill="#facc15" fontSize="9">
                            {'\u2605'}
                          </text>
                        </g>
                      )}

                      {/* Bottleneck warning badge */}
                      {isBottleneck && (
                        <g transform={`translate(${node.x - radius + 2}, ${node.y - radius + 2})`}>
                          <circle cx={0} cy={0} r={7} fill="rgba(245,158,11,0.2)" stroke="#f59e0b" strokeWidth={1} />
                          <text x={0} y={3.5} textAnchor="middle" fill="#f59e0b" fontSize="9">!</text>
                        </g>
                      )}

                      {/* Cycle warning badge */}
                      {isInCycle && (
                        <g transform={`translate(${node.x - radius + 2}, ${node.y - radius + 2})`}>
                          <circle cx={0} cy={0} r={7} fill="rgba(244,63,94,0.2)" stroke="#f43f5e" strokeWidth={1} />
                          <text x={0} y={4} textAnchor="middle" fill="#f43f5e" fontSize="9" fontFamily="monospace">C</text>
                        </g>
                      )}
                    </g>
                  );
                })}
              </svg>
            </div>

            {/* Controls */}
            <div className="flex flex-wrap justify-center gap-3">
              <motion.button
                type="button"
                onClick={handleRunTriage}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                disabled={animatingPhase === 'computing'}
                className={`flex items-center gap-2 rounded-2xl border px-5 py-2.5 text-sm font-medium transition-colors ${
                  animatingPhase === 'computing'
                    ? 'border-white/[0.06] bg-white/[0.02] text-white/30 cursor-wait'
                    : 'border-violet-500/30 bg-violet-500/10 text-violet-300 hover:bg-violet-500/20'
                }`}
              >
                {animatingPhase === 'computing' ? (
                  <>
                    <motion.div
                      animate={{ rotate: 360 }}
                      transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                    >
                      <Network className="h-4 w-4" />
                    </motion.div>
                    Computing...
                  </>
                ) : (
                  <>
                    <Play className="h-4 w-4" />
                    Run Triage
                  </>
                )}
              </motion.button>

              {triageRun && (
                <motion.button
                  type="button"
                  onClick={handleReset}
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                  whileHover={{ scale: 1.04 }}
                  whileTap={{ scale: 0.96 }}
                  className="flex items-center gap-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 py-2.5 text-sm font-medium text-white/50 hover:text-white/70 transition-colors"
                >
                  <RotateCcw className="h-4 w-4" />
                  Reset
                </motion.button>
              )}
            </div>

            {/* Mini Terminal */}
            <AnimatePresence>
              {triageRun && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                  className="overflow-hidden"
                >
                  <div className="rounded-2xl border border-white/[0.08] bg-black/40 overflow-hidden">
                    {/* Terminal header */}
                    <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
                      <Terminal className="h-3 w-3 text-white/30" />
                      <span className="text-[10px] text-white/30 font-mono">bv --robot output</span>
                      <div className="flex gap-1 ml-auto">
                        <Circle className="h-2 w-2 text-red-500/50" />
                        <Circle className="h-2 w-2 text-yellow-500/50" />
                        <Circle className="h-2 w-2 text-green-500/50" />
                      </div>
                    </div>
                    {/* Terminal body */}
                    <div
                      ref={terminalRef}
                      className="p-3 font-mono text-[11px] space-y-0.5 max-h-28 overflow-y-auto"
                    >
                      {terminalLines.map((line, i) => (
                        <motion.div
                          key={`${analysisMode}-${i}`}
                          initial={{ opacity: 0, x: -8 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                          className={
                            line.startsWith('$')
                              ? 'text-emerald-400'
                              : line.includes('warning') || line.includes('cycle')
                                ? 'text-red-400/70'
                                : 'text-white/40'
                          }
                        >
                          {line}
                        </motion.div>
                      ))}
                      {terminalLines.length > 0 && (
                        <span className="text-emerald-400 animate-pulse">{'>'} _</span>
                      )}
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* Right Side Panel */}
          <AnimatePresence mode="wait">
            {triageRun && (
              <motion.div
                key="side-panel"
                initial={{ opacity: 0, x: 20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 20 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className="w-full xl:w-80 shrink-0 space-y-4"
              >
                {/* Top Recommendation Card */}
                <div className="rounded-2xl border border-violet-500/20 bg-violet-500/[0.06] p-4 space-y-3">
                  <div className="flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4 text-violet-400" />
                    <span className="text-xs font-semibold text-violet-400 uppercase tracking-wider">
                      Top Recommendation
                    </span>
                  </div>
                  <div>
                    <p className="text-sm font-semibold text-white/90">{topNode.label}</p>
                    <div className="flex items-center gap-3 mt-1">
                      <span className="text-[10px] font-mono text-violet-400/70">PR: {topNode.metrics.pageRank.toFixed(2)}</span>
                      <span className="text-[10px] font-mono text-violet-400/70">BW: {topNode.metrics.betweenness.toFixed(2)}</span>
                      <span className="text-[10px] font-mono text-violet-400/70">EV: {topNode.metrics.eigenvector.toFixed(2)}</span>
                    </div>
                  </div>
                  <p className="text-xs text-white/60 leading-relaxed">{topNode.why}</p>
                </div>

                {/* Node Detail Panel */}
                <AnimatePresence mode="wait">
                  {selectedData && selectedData.id !== topNode.id && (
                    <motion.div
                      key={selectedData.id}
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -8 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3"
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <SelectedNodeIcon status={selectedData.status} />
                          <span className={`text-xs font-semibold uppercase tracking-wider ${STATUS_COLORS[selectedData.status].text}`}>
                            {selectedData.id}
                          </span>
                        </div>
                        <button
                          type="button"
                          onClick={() => setShowMetricsDetail(!showMetricsDetail)}
                          className="text-[10px] text-white/30 hover:text-white/50 transition-colors"
                        >
                          {showMetricsDetail ? 'hide' : 'metrics'}
                        </button>
                      </div>
                      <div>
                        <p className="text-sm font-medium text-white/80">{selectedData.label}</p>
                        <div className="flex items-center gap-2 mt-1">
                          <span className="text-[10px] font-mono text-white/40">
                            {STATUS_COLORS[selectedData.status].label}
                          </span>
                          <span className="text-[10px] text-white/20">|</span>
                          <span className="text-[10px] font-mono text-white/40">
                            {selectedData.age}d old
                          </span>
                          <span className="text-[10px] text-white/20">|</span>
                          <span className="text-[10px] font-mono text-white/40">
                            {selectedData.track}
                          </span>
                        </div>
                      </div>

                      {/* Full Metrics */}
                      <AnimatePresence>
                        {showMetricsDetail && (
                          <motion.div
                            initial={{ opacity: 0, height: 0 }}
                            animate={{ opacity: 1, height: 'auto' }}
                            exit={{ opacity: 0, height: 0 }}
                            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                            className="overflow-hidden"
                          >
                            <div className="grid grid-cols-2 gap-1.5 pt-1">
                              <MetricBadge label="PageRank" value={selectedData.metrics.pageRank} maxVal={0.31} />
                              <MetricBadge label="Betweenness" value={selectedData.metrics.betweenness} maxVal={0.82} />
                              <MetricBadge label="HITS Auth" value={selectedData.metrics.hits_authority} maxVal={0.85} />
                              <MetricBadge label="HITS Hub" value={selectedData.metrics.hits_hub} maxVal={0.91} />
                              <MetricBadge label="Eigenvector" value={selectedData.metrics.eigenvector} maxVal={0.88} />
                              <MetricBadge label="k-Core" value={selectedData.metrics.kCore} maxVal={3} isInteger />
                              <MetricBadge label="In-Degree" value={selectedData.metrics.inDegree} maxVal={3} isInteger />
                              <MetricBadge label="Out-Degree" value={selectedData.metrics.outDegree} maxVal={4} isInteger />
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>

                      <p className="text-xs text-white/60 leading-relaxed">{selectedData.why}</p>

                      {selectedData.blockedBy.length > 0 && (
                        <div className="flex items-center gap-1.5 pt-1">
                          <Ban className="h-3 w-3 text-red-400" />
                          <span className="text-[10px] text-red-400/80">
                            Blocked by: {selectedData.blockedBy.join(', ')}
                          </span>
                        </div>
                      )}
                      {selectedData.isQuickWin && (
                        <div className="flex items-center gap-1.5 pt-1">
                          <Star className="h-3 w-3 text-yellow-400" />
                          <span className="text-[10px] text-yellow-400/80">Quick win candidate</span>
                        </div>
                      )}
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* Mode-specific panels */}
                <AnimatePresence mode="wait">
                  {analysisMode === 'overview' && (
                    <TriageRankingPanel
                      key="ranking"
                      nodes={sortedNodes}
                      selectedNode={selectedNode}
                      onSelect={(id) => setSelectedNode(id === selectedNode ? null : id)}
                    />
                  )}

                  {analysisMode === 'pagerank' && (
                    <PageRankPanel
                      key="pagerank"
                      nodes={sortedNodes}
                      selectedNode={selectedNode}
                      onSelect={(id) => setSelectedNode(id === selectedNode ? null : id)}
                    />
                  )}

                  {analysisMode === 'critical-path' && (
                    <CriticalPathPanel
                      key="critical-path"
                      step={criticalPathStep}
                    />
                  )}

                  {analysisMode === 'cycles' && (
                    <CycleDetectionPanel key="cycles" />
                  )}

                  {analysisMode === 'quick-wins' && (
                    <QuickWinsPanel
                      key="quick-wins"
                      nodes={quickWinNodes}
                      selectedNode={selectedNode}
                      onSelect={(id) => setSelectedNode(id === selectedNode ? null : id)}
                    />
                  )}

                  {analysisMode === 'bottlenecks' && (
                    <BottleneckPanel
                      key="bottlenecks"
                      nodes={bottleneckNodes}
                      selectedNode={selectedNode}
                      onSelect={(id) => setSelectedNode(id === selectedNode ? null : id)}
                    />
                  )}
                </AnimatePresence>

                {/* Recommendations Panel */}
                <RecommendationsPanel />
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-Components
// ---------------------------------------------------------------------------

function SelectedNodeIcon({ status }: { status: IssueStatus }) {
  const icons: Record<IssueStatus, typeof Clock> = {
    'open': Clock,
    'in-progress': ArrowRight,
    'blocked': Ban,
    'done': CheckCircle2,
  };
  const Icon = icons[status];
  const color = STATUS_COLORS[status];
  return <Icon className={`h-4 w-4 ${color.text}`} />;
}

function MetricBadge({ label, value, maxVal, isInteger }: { label: string; value: number; maxVal: number; isInteger?: boolean }) {
  const pct = Math.min((value / maxVal) * 100, 100);
  return (
    <div className="rounded-lg bg-white/[0.03] border border-white/[0.06] p-1.5">
      <div className="flex items-center justify-between mb-1">
        <span className="text-[9px] text-white/40">{label}</span>
        <span className="text-[9px] font-mono text-white/60">{isInteger ? value : value.toFixed(2)}</span>
      </div>
      <div className="h-1 bg-white/[0.06] rounded-full overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-violet-500/60 to-violet-400/40 rounded-full transition-[width]"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}

function TriageRankingPanel({
  nodes,
  selectedNode,
  onSelect,
}: {
  nodes: GraphNode[];
  selectedNode: string | null;
  onSelect: (id: string) => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-2"
    >
      <div className="flex items-center gap-2 mb-3">
        <BarChart3 className="h-3.5 w-3.5 text-white/40" />
        <p className="text-xs font-semibold text-white/60 uppercase tracking-wider">
          Triage Ranking
        </p>
      </div>
      {nodes.map((node, i) => {
        const color = STATUS_COLORS[node.status];
        return (
          <motion.button
            key={node.id}
            type="button"
            onClick={() => onSelect(node.id)}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.04 }}
            className={`w-full flex items-center gap-2 rounded-xl px-3 py-2 text-left transition-colors ${
              node.id === selectedNode
                ? 'bg-white/[0.06] border border-white/[0.12]'
                : 'hover:bg-white/[0.03] border border-transparent'
            }`}
          >
            <span className="text-xs font-mono text-white/30 w-4">{i + 1}.</span>
            <div className={`h-2 w-2 rounded-full ${color.bg} shrink-0`} />
            <span className="text-xs text-white/70 truncate flex-1">{node.label}</span>
            <span className="text-[10px] font-mono text-white/40">{node.metrics.pageRank.toFixed(2)}</span>
            {node.isQuickWin && <Star className="h-3 w-3 text-yellow-400 shrink-0" />}
          </motion.button>
        );
      })}
    </motion.div>
  );
}

function PageRankPanel({
  nodes,
  selectedNode,
  onSelect,
}: {
  nodes: GraphNode[];
  selectedNode: string | null;
  onSelect: (id: string) => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-2"
    >
      <div className="flex items-center gap-2 mb-3">
        <Trophy className="h-3.5 w-3.5 text-violet-400" />
        <p className="text-xs font-semibold text-violet-400 uppercase tracking-wider">
          PageRank Scores
        </p>
      </div>
      {nodes.map((node, i) => {
        const pct = (node.metrics.pageRank / 0.31) * 100;
        return (
          <motion.button
            key={node.id}
            type="button"
            onClick={() => onSelect(node.id)}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.04 }}
            className={`w-full rounded-xl px-3 py-2 text-left transition-colors ${
              node.id === selectedNode
                ? 'bg-white/[0.06] border border-white/[0.12]'
                : 'hover:bg-white/[0.03] border border-transparent'
            }`}
          >
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs text-white/70">{node.label}</span>
              <span className="text-[10px] font-mono text-violet-400">{node.metrics.pageRank.toFixed(3)}</span>
            </div>
            <div className="h-1.5 bg-white/[0.06] rounded-full overflow-hidden">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${pct}%` }}
                transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
                className="h-full bg-gradient-to-r from-violet-500 to-purple-400 rounded-full"
              />
            </div>
          </motion.button>
        );
      })}
    </motion.div>
  );
}

function CriticalPathPanel({ step }: { step: number }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-cyan-500/20 bg-cyan-500/[0.04] p-4 space-y-3"
    >
      <div className="flex items-center gap-2">
        <GitBranch className="h-3.5 w-3.5 text-cyan-400" />
        <p className="text-xs font-semibold text-cyan-400 uppercase tracking-wider">
          Critical Path
        </p>
      </div>
      <p className="text-[10px] text-white/40">
        Longest dependency chain: {CRITICAL_PATH_IDS.length} nodes, ~28 estimated days
      </p>
      <div className="space-y-1">
        {CRITICAL_PATH_IDS.map((id, i) => {
          const node = GRAPH_NODES.find((n) => n.id === id);
          if (!node) return null;
          const isReached = i < step;
          const color = STATUS_COLORS[node.status];
          return (
            <div key={id} className="flex items-center gap-2">
              <div className={`h-5 w-5 rounded-full flex items-center justify-center text-[9px] font-mono transition-colors ${
                isReached ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/40' : 'bg-white/[0.04] text-white/30 border border-white/[0.08]'
              }`}>
                {i + 1}
              </div>
              {i < CRITICAL_PATH_IDS.length - 1 && (
                <ChevronRight className={`h-3 w-3 ${isReached ? 'text-cyan-400' : 'text-white/20'}`} />
              )}
              <span className={`text-xs transition-colors ${isReached ? 'text-white/80' : 'text-white/30'}`}>
                {node.label}
              </span>
              <span className={`text-[9px] ml-auto ${color.text}`}>
                {color.label}
              </span>
            </div>
          );
        })}
      </div>
      <div className="flex items-center gap-1.5 pt-2 border-t border-white/[0.06]">
        <Activity className="h-3 w-3 text-cyan-400/60" />
        <span className="text-[10px] text-cyan-400/60">
          Bottleneck: DB migration (blocks 3 downstream)
        </span>
      </div>
    </motion.div>
  );
}

function CycleDetectionPanel() {
  const cycleNodes = ['API', 'NOTIFY', 'PERF'];
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-red-500/20 bg-red-500/[0.04] p-4 space-y-3"
    >
      <div className="flex items-center gap-2">
        <RefreshCw className="h-3.5 w-3.5 text-red-400" />
        <p className="text-xs font-semibold text-red-400 uppercase tracking-wider">
          Cycle Detected
        </p>
      </div>
      <p className="text-[10px] text-white/40">
        Circular dependency found between {cycleNodes.length} nodes. This creates a deadlock where no node can be completed first.
      </p>
      <div className="flex items-center gap-1.5 flex-wrap">
        {cycleNodes.map((id, i) => (
          <div key={id} className="flex items-center gap-1.5">
            <span className="text-xs font-mono text-red-400 px-2 py-0.5 rounded bg-red-500/10 border border-red-500/20">
              {id}
            </span>
            {i < cycleNodes.length - 1 && (
              <ArrowRight className="h-3 w-3 text-red-400/50" />
            )}
          </div>
        ))}
        <ArrowRight className="h-3 w-3 text-red-400/50" />
        <span className="text-xs font-mono text-red-400/50">API</span>
      </div>
      <div className="p-2 rounded-lg bg-red-500/[0.06] border border-red-500/20">
        <p className="text-[10px] text-red-300/70 font-mono">
          Recommendation: Break edge PERF {'->'} API to resolve cycle
        </p>
      </div>
      <div className="flex items-center gap-1.5 pt-1">
        <Shield className="h-3 w-3 text-amber-400/60" />
        <span className="text-[10px] text-amber-400/60">
          Note: This is a simulated cycle for demonstration
        </span>
      </div>
    </motion.div>
  );
}

function QuickWinsPanel({
  nodes,
  selectedNode,
  onSelect,
}: {
  nodes: GraphNode[];
  selectedNode: string | null;
  onSelect: (id: string) => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-yellow-500/20 bg-yellow-500/[0.04] p-4 space-y-3"
    >
      <div className="flex items-center gap-2">
        <Zap className="h-3.5 w-3.5 text-yellow-400" />
        <p className="text-xs font-semibold text-yellow-400 uppercase tracking-wider">
          Quick Wins
        </p>
      </div>
      <p className="text-[10px] text-white/40">
        Tasks with zero blockers that can be started immediately for free velocity.
      </p>
      {nodes.map((node, i) => (
        <motion.button
          key={node.id}
          type="button"
          onClick={() => onSelect(node.id)}
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.08 }}
          className={`w-full flex items-center gap-2 rounded-xl px-3 py-2 text-left transition-colors ${
            node.id === selectedNode
              ? 'bg-yellow-500/10 border border-yellow-500/20'
              : 'hover:bg-white/[0.03] border border-transparent'
          }`}
        >
          <Star className="h-3 w-3 text-yellow-400 shrink-0" />
          <span className="text-xs text-white/70 flex-1">{node.label}</span>
          <div className="flex flex-col items-end">
            <span className="text-[9px] font-mono text-white/40">0 blockers</span>
            <span className="text-[9px] font-mono text-white/30">{node.age}d old</span>
          </div>
        </motion.button>
      ))}
      <div className="flex items-center gap-1.5 pt-2 border-t border-white/[0.06]">
        <Hash className="h-3 w-3 text-yellow-400/40" />
        <span className="text-[10px] text-white/30">
          Assign to idle agents for parallel execution
        </span>
      </div>
    </motion.div>
  );
}

function BottleneckPanel({
  nodes,
  selectedNode,
  onSelect,
}: {
  nodes: GraphNode[];
  selectedNode: string | null;
  onSelect: (id: string) => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-amber-500/20 bg-amber-500/[0.04] p-4 space-y-3"
    >
      <div className="flex items-center gap-2">
        <Target className="h-3.5 w-3.5 text-amber-400" />
        <p className="text-xs font-semibold text-amber-400 uppercase tracking-wider">
          Bottleneck Analysis
        </p>
      </div>
      <p className="text-[10px] text-white/40">
        High betweenness centrality nodes that sit on many shortest paths between other issues.
      </p>
      {nodes.map((node, i) => {
        const pct = (node.metrics.betweenness / 0.82) * 100;
        return (
          <motion.button
            key={node.id}
            type="button"
            onClick={() => onSelect(node.id)}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
            className={`w-full rounded-xl px-3 py-2 text-left transition-colors ${
              node.id === selectedNode
                ? 'bg-amber-500/10 border border-amber-500/20'
                : 'hover:bg-white/[0.03] border border-transparent'
            }`}
          >
            <div className="flex items-center justify-between mb-1">
              <div className="flex items-center gap-2">
                <Gauge className="h-3 w-3 text-amber-400/60" />
                <span className="text-xs text-white/70">{node.label}</span>
              </div>
              <span className="text-[10px] font-mono text-amber-400">{node.metrics.betweenness.toFixed(2)}</span>
            </div>
            <div className="h-1.5 bg-white/[0.06] rounded-full overflow-hidden">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${pct}%` }}
                transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.08 }}
                className="h-full bg-gradient-to-r from-amber-500 to-orange-400 rounded-full"
              />
            </div>
            <div className="flex items-center justify-between mt-1">
              <span className="text-[9px] text-white/30">Blocks {node.metrics.outDegree} issues</span>
              <span className="text-[9px] text-white/30">k-core: {node.metrics.kCore}</span>
            </div>
          </motion.button>
        );
      })}
    </motion.div>
  );
}

function RecommendationsPanel() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.2 }}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-2"
    >
      <div className="flex items-center gap-2 mb-3">
        <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400" />
        <p className="text-xs font-semibold text-emerald-400 uppercase tracking-wider">
          Actionable Recommendations
        </p>
      </div>
      {TRIAGE_RECOMMENDATIONS.map((rec, i) => (
        <motion.div
          key={rec.id}
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.3 + i * 0.05 }}
          className="flex items-start gap-2 py-1.5"
        >
          <span className={`text-[9px] px-1.5 py-0.5 rounded border font-semibold uppercase shrink-0 mt-0.5 ${IMPACT_COLORS[rec.impact]}`}>
            {rec.impact}
          </span>
          <div className="min-w-0">
            <p className="text-[11px] text-white/70 leading-tight">{rec.action}</p>
            <p className="text-[9px] text-white/30 mt-0.5">{rec.reason}</p>
          </div>
        </motion.div>
      ))}
    </motion.div>
  );
}
