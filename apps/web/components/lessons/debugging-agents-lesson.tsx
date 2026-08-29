'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Bug,
  Activity,
  Search,
  DollarSign,
  Wifi,
  AlertTriangle,
  Terminal,
  Zap,
  CheckCircle2,
  XCircle,
  Clock,
  BarChart3,
  ChevronRight,
  ChevronLeft,
  Eye,
  EyeOff,
  Layers,
  RefreshCw,
  Cpu,
  GitMerge,
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
const InteractiveDebugDashboard = InteractiveDebugDashboardImpl;

export function DebuggingAgentsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Diagnose agent failures, rate limits, cost overruns, and network issues
        using RANO, CAUT, WA, and CASS together.
      </GoalBanner>

      {/* Section 1: The Debugging Toolkit */}
      <Section title="The Debugging Toolkit" icon={<Bug className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          When agents stop working, you need to answer: <Highlight>Is it a rate
          limit? A network issue? A cost overrun? A bug in the prompt?</Highlight>
          Four tools give you complete observability.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Wifi className="h-5 w-5" />}
              title="RANO"
              description="Network traffic — see every API call"
              gradient="from-cyan-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<DollarSign className="h-5 w-5" />}
              title="CAUT"
              description="Cost tracking — per-session spend analysis"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="WA"
              description="Terminal state — pattern detection across panes"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="CASS"
              description="History — search past sessions for solutions"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-8">
          <InteractiveDebugDashboard />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Rate Limit Diagnosis */}
      <Section title="Rate Limit Diagnosis" icon={<AlertTriangle className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Rate limits are the most common agent failure. Here&apos;s how to
          diagnose and work around them.
        </Paragraph>

        <CodeBlock
          code={`# Step 1: Check if RANO sees 429 responses
rano status
# Look for: HTTP 429 Too Many Requests

# Step 2: Check which provider is throttling
caut breakdown
# Shows per-provider token consumption

# Step 3: Check WA for rate limit patterns across panes
wa robot events --rule-id "claude_code.rate_limit" --unhandled-only

# Step 4: Rotate to a fresh account
caam status --verbose
caam rotate

# Step 5: Check CASS for how you solved this before
cass search "rate limit workaround rotation" --limit 3`}
          filename="Rate Limit Workflow"
        />

        <TipBox variant="tip">
          If you see 429s from RANO but CAUT shows low token usage, you&apos;re
          likely hitting requests-per-minute limits, not token limits. Space out
          your requests or use CAAM to rotate accounts.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Network Issues */}
      <Section title="Network Debugging" icon={<Wifi className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          RANO intercepts all agent API traffic, letting you see exactly what&apos;s
          happening at the network level.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'rano status', description: 'Show active connections and recent errors' },
            { command: 'rano log --errors-only', description: 'Filter to just failed requests' },
            { command: 'rano log --provider anthropic', description: 'Filter by API provider' },
            { command: 'rano log --slow --threshold 10s', description: 'Find requests taking over 10 seconds' },
            { command: 'rano log --status 5xx', description: 'Find server errors from providers' },
          ]}
        />

        <CodeBlock
          code={`# Common patterns and what they mean:

# Lots of 429s → Rate limiting (use CAAM to rotate)
# Connection timeouts → Network/DNS issue (check VPS connectivity)
# 500/503 errors → Provider outage (switch to different provider)
# Slow responses (>30s) → Provider overloaded (try during off-peak)
# SSL errors → Certificate issue (check system time/certs)`}
          filename="Error Pattern Guide"
        />
      </Section>

      <Divider />

      {/* Section 4: Cost Tracking */}
      <Section title="Cost Investigation" icon={<DollarSign className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          When costs spike unexpectedly, use CAUT to find the expensive sessions
          and RANO to see what they&apos;re doing.
        </Paragraph>

        <CodeBlock
          code={`# Find your most expensive sessions today
caut sessions --sort cost --limit 5

# Compare against yesterday
caut summary --period 1d
caut summary --period 2d  # includes yesterday

# Check token efficiency (high input/low output = wasted context)
caut efficiency

# Drill into a specific session's API calls
rano log --session <session-id> --verbose

# Common cost culprits:
# 1. Agents re-reading large files repeatedly
# 2. Long context windows with low-value content
# 3. Agents stuck in retry loops
# 4. Using Opus when Sonnet would suffice`}
          filename="Cost Analysis"
        />

        <TipBox variant="warning">
          If an agent&apos;s input tokens are 10x its output tokens, it&apos;s
          probably stuffing too much context. Use TRU to compress source files
          before feeding them to agents.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Stuck Agent Detection */}
      <Section title="Stuck Agent Detection" icon={<Activity className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          WA detects when agents go silent. An idle pane usually means the agent
          is waiting for approval, hit an error, or is genuinely stuck.
        </Paragraph>

        <CodeBlock
          code={`# Check all pane states
wa robot state | jq '.data.panes[] |
  select(.idle_seconds > 120) |
  {id, title, idle_seconds, last_output_preview}'

# Get the last 50 lines from a stuck pane
wa robot get-text <pane_id> --tail 50

# Search for error patterns in pane output
wa search "error|failed|panic|traceback" --pane <pane_id>

# Check if agent is waiting for SLB approval
wa robot events --rule-id "claude_code.waiting_approval"

# Force-send a nudge to wake up a stuck agent
wa robot send <pane_id> "Continue with the task"`}
          filename="Stuck Agent Diagnosis"
        />
      </Section>

      <Divider />

      {/* Section 6: Learning from History */}
      <Section title="Learning from History" icon={<Search className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          CASS stores all past agent sessions. When you encounter a new problem,
          search for how you (or another agent) solved it before.
        </Paragraph>

        <CodeBlock
          code={`# Search for how a specific error was resolved
cass search "ECONNREFUSED anthropic API fix" --limit 5

# Find sessions that worked with a specific tool
cass search "successfully deployed with docker" --limit 3

# Search across all agent types
cass search "memory leak node process" --robot --limit 5

# Use CM to check if there's a playbook rule
cm context "debugging API connection failures" --json`}
          filename="Historical Search"
        />

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-cyan-500/10 border border-cyan-500/30">
            <span className="text-cyan-400 font-semibold">Quick Diagnosis</span>
            <p className="text-white/80 text-sm mt-1">RANO status + CAUT summary = instant health check</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Deep Investigation</span>
            <p className="text-white/80 text-sm mt-1">WA events + RANO logs = full request trace</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">Cost Audit</span>
            <p className="text-white/80 text-sm mt-1">CAUT breakdown + session drill-down = spend accountability</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">Pattern Recognition</span>
            <p className="text-white/80 text-sm mt-1">CASS history + CM playbook = never solve twice</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Debug War Room — Live Agent Debugging Dashboard
// ---------------------------------------------------------------------------

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

interface DebugScenario {
  id: string;
  title: string;
  icon: React.ReactNode;
  color: string;
  bgColor: string;
  borderColor: string;
  contextFill: number;
  tokenUsage: { input: number; output: number };
  conversationTurns: number;
  stackFrames: StackFrame[];
  agentView: string[];
  reality: string[];
  fixes: FixSuggestion[];
  sessionLog: LogEntry[];
}

interface StackFrame {
  layer: string;
  file: string;
  isError: boolean;
  description: string;
}

interface FixSuggestion {
  rank: number;
  label: string;
  command: string;
  confidence: number;
}

interface LogEntry {
  time: string;
  level: 'info' | 'warn' | 'error';
  message: string;
}

function makeScenarios(): DebugScenario[] {
  return [
    {
      id: 'infinite-loop',
      title: 'Infinite Loop Detected',
      icon: <RefreshCw className="h-4 w-4" />,
      color: 'text-red-400',
      bgColor: 'bg-red-500/10',
      borderColor: 'border-red-500/30',
      contextFill: 97,
      tokenUsage: { input: 198000, output: 4200 },
      conversationTurns: 47,
      stackFrames: [
        { layer: 'Agent Loop', file: 'agent/main.ts', isError: true, description: 'runLoop() called 47 times without progress' },
        { layer: 'Tool Call', file: 'tools/edit.ts', isError: true, description: 'Same edit applied and reverted repeatedly' },
        { layer: 'File System', file: 'fs/write.ts', isError: false, description: 'Write succeeds but lint fails' },
        { layer: 'Lint Check', file: 'lint/eslint.ts', isError: true, description: 'Error persists after each edit attempt' },
      ],
      agentView: [
        'I need to fix this lint error',
        'Let me edit the file...',
        'Edit applied successfully',
        'Running lint check...',
        'Lint failed. Let me try again...',
        '(repeats 47 times)',
      ],
      reality: [
        'Agent applies correct fix',
        'BUT: another rule conflicts',
        'Lint reports different error',
        'Agent reverts to original approach',
        'Same conflict triggers again',
        'Context window filling with retries',
      ],
      fixes: [
        { rank: 1, label: 'Kill loop and reset context', command: 'wa robot send pane-1 "/clear"', confidence: 95 },
        { rank: 2, label: 'Add eslint-disable for conflicting rule', command: 'Agent: "Add eslint-disable comment"', confidence: 82 },
        { rank: 3, label: 'Break task into two separate steps', command: 'ntm send pane-1 "Fix only the type error first"', confidence: 78 },
      ],
      sessionLog: [
        { time: '14:02:01', level: 'info', message: 'Agent started task: fix lint errors' },
        { time: '14:02:15', level: 'info', message: 'Edit applied to src/utils.ts' },
        { time: '14:02:18', level: 'warn', message: 'Lint check failed: no-unused-vars' },
        { time: '14:02:22', level: 'info', message: 'Agent retrying edit...' },
        { time: '14:03:45', level: 'warn', message: 'Loop detected: 12 identical edits' },
        { time: '14:05:30', level: 'error', message: 'Context 97% full, 47 turns with no progress' },
      ],
    },
    {
      id: 'stale-context',
      title: 'Stale Context Window',
      icon: <Clock className="h-4 w-4" />,
      color: 'text-amber-400',
      bgColor: 'bg-amber-500/10',
      borderColor: 'border-amber-500/30',
      contextFill: 89,
      tokenUsage: { input: 178000, output: 12400 },
      conversationTurns: 31,
      stackFrames: [
        { layer: 'Context Manager', file: 'context/window.ts', isError: true, description: 'Stale file content from 28 turns ago' },
        { layer: 'File Read', file: 'tools/read.ts', isError: false, description: 'Last read at turn 3, file changed at turn 15' },
        { layer: 'Git State', file: 'git/status.ts', isError: true, description: 'Branch diverged, agent unaware' },
        { layer: 'Edit Engine', file: 'tools/edit.ts', isError: false, description: 'Edits based on outdated file content' },
      ],
      agentView: [
        'File has function getUserData() on line 42',
        'I will modify line 42...',
        'Edit applied to line 42',
        'Tests should pass now',
        'Running tests...',
        'Tests pass (agent believes)',
      ],
      reality: [
        'Another agent moved getUserData() to line 78',
        'Line 42 now contains unrelated code',
        'Edit corrupted the wrong function',
        'Tests are actually failing',
        'Agent context has stale file snapshot',
        'Git shows 3 conflicting commits',
      ],
      fixes: [
        { rank: 1, label: 'Force context refresh', command: 'wa robot send pane-2 "Read the file again"', confidence: 92 },
        { rank: 2, label: 'Clear conversation and restart', command: 'wa robot send pane-2 "/clear"', confidence: 88 },
        { rank: 3, label: 'Pull latest changes first', command: 'ntm send pane-2 "Run git pull first"', confidence: 85 },
      ],
      sessionLog: [
        { time: '13:45:00', level: 'info', message: 'Agent read src/api.ts (snapshot stored)' },
        { time: '13:52:00', level: 'info', message: 'Pane-3 agent committed changes to src/api.ts' },
        { time: '14:01:00', level: 'warn', message: 'Agent editing based on stale content' },
        { time: '14:01:30', level: 'error', message: 'Edit target not found at expected line' },
        { time: '14:02:00', level: 'warn', message: 'Agent forced edit, corrupted function' },
        { time: '14:03:00', level: 'error', message: 'Test suite: 7 failures, 2 errors' },
      ],
    },
    {
      id: 'wrong-file',
      title: 'Wrong File Edited',
      icon: <XCircle className="h-4 w-4" />,
      color: 'text-orange-400',
      bgColor: 'bg-orange-500/10',
      borderColor: 'border-orange-500/30',
      contextFill: 54,
      tokenUsage: { input: 92000, output: 8700 },
      conversationTurns: 14,
      stackFrames: [
        { layer: 'File Resolution', file: 'tools/resolve.ts', isError: true, description: 'Ambiguous path resolved to wrong file' },
        { layer: 'Search', file: 'tools/grep.ts', isError: false, description: 'Found 3 files matching pattern' },
        { layer: 'Edit Engine', file: 'tools/edit.ts', isError: false, description: 'Edit succeeded on wrong target' },
        { layer: 'Test Runner', file: 'test/runner.ts', isError: true, description: 'Unrelated test broke from wrong edit' },
      ],
      agentView: [
        'Need to edit utils.ts',
        'Found file at src/utils.ts',
        'Applying type fix...',
        'Edit successful',
        'Running tests...',
        'All passing',
      ],
      reality: [
        'There are 3 utils.ts files in project',
        'Agent picked src/utils.ts (shared lib)',
        'Should have edited app/utils.ts (app-specific)',
        'Shared lib change broke other consumers',
        'Original bug still present',
        '2 other modules now broken',
      ],
      fixes: [
        { rank: 1, label: 'Revert the wrong edit', command: 'git checkout src/utils.ts', confidence: 98 },
        { rank: 2, label: 'Be explicit about file path', command: 'ntm send pane-1 "Edit app/utils.ts specifically"', confidence: 90 },
        { rank: 3, label: 'Add path context to prompt', command: 'cm rule add "Always use full paths"', confidence: 72 },
      ],
      sessionLog: [
        { time: '15:10:00', level: 'info', message: 'Task: fix type error in utils.ts' },
        { time: '15:10:05', level: 'info', message: 'Search found 3 files matching "utils.ts"' },
        { time: '15:10:08', level: 'warn', message: 'Agent chose src/utils.ts (ambiguous)' },
        { time: '15:10:20', level: 'info', message: 'Edit applied to src/utils.ts:42' },
        { time: '15:10:45', level: 'error', message: 'Module "shared/auth" now fails import' },
        { time: '15:11:00', level: 'error', message: 'Cascade: 2 downstream modules broken' },
      ],
    },
    {
      id: 'test-cascade',
      title: 'Test Failure Cascade',
      icon: <Layers className="h-4 w-4" />,
      color: 'text-rose-400',
      bgColor: 'bg-rose-500/10',
      borderColor: 'border-rose-500/30',
      contextFill: 72,
      tokenUsage: { input: 145000, output: 21000 },
      conversationTurns: 23,
      stackFrames: [
        { layer: 'Test Suite', file: 'test/suite.ts', isError: true, description: '23 tests failing from 1 root cause' },
        { layer: 'Shared Fixture', file: 'test/fixtures.ts', isError: true, description: 'Setup function returns wrong shape' },
        { layer: 'Type Layer', file: 'types/api.ts', isError: false, description: 'Interface changed, fixtures not updated' },
        { layer: 'Agent Focus', file: 'agent/context.ts', isError: true, description: 'Agent fixing tests one-by-one instead of root' },
      ],
      agentView: [
        'Test 1 failing: expected object got undefined',
        'Fixed test 1 by adding null check',
        'Test 2 failing: same pattern',
        'Fixed test 2 with null check',
        'Test 3 failing: same pattern...',
        'Fixing each test individually...',
      ],
      reality: [
        'All 23 tests share one fixture',
        'Fixture returns old API shape',
        'API interface was updated yesterday',
        'Fixing fixture once fixes all 23 tests',
        'Agent wasting tokens on symptoms',
        'Cost: $4.20 for individual fixes vs $0.18 for root cause',
      ],
      fixes: [
        { rank: 1, label: 'Fix the shared test fixture', command: 'ntm send pane-1 "Fix test/fixtures.ts to match new API shape"', confidence: 96 },
        { rank: 2, label: 'Show agent the failure pattern', command: 'ntm send pane-1 "All 23 failures share fixtures.ts"', confidence: 91 },
        { rank: 3, label: 'Regenerate fixtures from types', command: 'ntm send pane-1 "Generate fixtures from types/api.ts"', confidence: 84 },
      ],
      sessionLog: [
        { time: '11:00:00', level: 'info', message: 'Agent started: fix failing tests' },
        { time: '11:00:30', level: 'warn', message: '23 tests failing in test suite' },
        { time: '11:01:00', level: 'info', message: 'Agent fixing test #1 individually' },
        { time: '11:05:00', level: 'info', message: 'Agent fixing test #8 individually' },
        { time: '11:12:00', level: 'warn', message: 'Pattern detected: same null check added 8 times' },
        { time: '11:15:00', level: 'error', message: 'Cost alert: $4.20 spent, 15 tests remain' },
      ],
    },
    {
      id: 'rate-spiral',
      title: 'Rate Limit Spiral',
      icon: <AlertTriangle className="h-4 w-4" />,
      color: 'text-yellow-400',
      bgColor: 'bg-yellow-500/10',
      borderColor: 'border-yellow-500/30',
      contextFill: 63,
      tokenUsage: { input: 87000, output: 2100 },
      conversationTurns: 52,
      stackFrames: [
        { layer: 'Rate Limiter', file: 'api/rateLimit.ts', isError: true, description: 'Provider returning 429 on every request' },
        { layer: 'Retry Logic', file: 'api/retry.ts', isError: true, description: 'Exponential backoff not increasing fast enough' },
        { layer: 'Agent Scheduler', file: 'agent/schedule.ts', isError: false, description: '3 agents hitting same provider simultaneously' },
        { layer: 'Account Pool', file: 'auth/caam.ts', isError: true, description: 'All accounts in pool exhausted' },
      ],
      agentView: [
        'Sending API request...',
        'Got 429, retrying in 1s...',
        'Got 429, retrying in 2s...',
        'Got 429, retrying in 4s...',
        'Request succeeded!',
        'Sending next request... (429 again)',
      ],
      reality: [
        '3 agents sharing same API key',
        'Combined rate: 180 req/min (limit: 60)',
        'Backoff resets too quickly',
        'Agents compete for same rate budget',
        'Each retry adds to queue pressure',
        'Spiral: more retries = more 429s',
      ],
      fixes: [
        { rank: 1, label: 'Rotate API accounts', command: 'caam rotate --all-agents', confidence: 94 },
        { rank: 2, label: 'Stagger agent requests', command: 'ntm config set rate-stagger 5s', confidence: 87 },
        { rank: 3, label: 'Pause 2 of 3 agents', command: 'ntm pause pane-2 pane-3', confidence: 80 },
      ],
      sessionLog: [
        { time: '09:30:00', level: 'info', message: 'All 3 agents active, same provider' },
        { time: '09:30:15', level: 'warn', message: 'First 429 response from Anthropic API' },
        { time: '09:31:00', level: 'warn', message: '429 rate: 12/min across all agents' },
        { time: '09:33:00', level: 'error', message: '429 rate: 45/min, spiral detected' },
        { time: '09:35:00', level: 'error', message: 'All CAAM accounts exhausted' },
        { time: '09:36:00', level: 'error', message: 'Agents fully blocked, 0 successful requests' },
      ],
    },
    {
      id: 'conflicting-edits',
      title: 'Conflicting Agent Edits',
      icon: <GitMerge className="h-4 w-4" />,
      color: 'text-purple-400',
      bgColor: 'bg-purple-500/10',
      borderColor: 'border-purple-500/30',
      contextFill: 68,
      tokenUsage: { input: 134000, output: 18500 },
      conversationTurns: 19,
      stackFrames: [
        { layer: 'Git Merge', file: 'git/merge.ts', isError: true, description: 'Merge conflict in 3 files' },
        { layer: 'Agent A Edit', file: 'src/auth.ts', isError: true, description: 'Refactored function signature' },
        { layer: 'Agent B Edit', file: 'src/auth.ts', isError: true, description: 'Added parameter to same function' },
        { layer: 'Coordination', file: 'agents/mail.ts', isError: true, description: 'No lock acquired before edits' },
      ],
      agentView: [
        'Agent A: Refactoring auth module',
        'Agent B: Adding OAuth parameter',
        'Both working on src/auth.ts',
        'Agent A commits first',
        'Agent B commits...',
        'Both report success',
      ],
      reality: [
        'Neither agent checked for locks',
        'Both read same file version',
        'Agent A changed function signature',
        'Agent B added param to old signature',
        'Git merge produces conflict markers',
        'Build broken, both agents unaware',
      ],
      fixes: [
        { rank: 1, label: 'Resolve conflicts manually', command: 'git mergetool src/auth.ts', confidence: 97 },
        { rank: 2, label: 'Add file locking via Agent Mail', command: 'am broadcast "Lock src/auth.ts before editing"', confidence: 85 },
        { rank: 3, label: 'Assign files to specific agents', command: 'cm rule add "Only pane-1 edits src/auth.ts"', confidence: 79 },
      ],
      sessionLog: [
        { time: '16:00:00', level: 'info', message: 'Agent A starts auth refactor' },
        { time: '16:00:05', level: 'info', message: 'Agent B starts OAuth feature' },
        { time: '16:02:00', level: 'info', message: 'Agent A commits refactor to branch' },
        { time: '16:02:30', level: 'info', message: 'Agent B commits OAuth changes' },
        { time: '16:03:00', level: 'error', message: 'Merge conflict in src/auth.ts' },
        { time: '16:03:15', level: 'error', message: 'CI pipeline failed: conflict markers in source' },
      ],
    },
  ];
}

// ---------------------------------------------------------------------------
// Sub-components for the War Room panels
// ---------------------------------------------------------------------------

function ContextFillGauge({ fill, animated }: { fill: number; animated: boolean }) {
  const getColor = (val: number) => {
    if (val >= 90) return 'from-red-500 to-red-600';
    if (val >= 70) return 'from-amber-500 to-orange-500';
    return 'from-emerald-500 to-cyan-500';
  };
  const getTextColor = (val: number) => {
    if (val >= 90) return 'text-red-400';
    if (val >= 70) return 'text-amber-400';
    return 'text-emerald-400';
  };

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <span className="text-[10px] text-white/50 font-medium">Context Window</span>
        <motion.span
          className={`text-xs font-mono font-bold ${getTextColor(fill)}`}
          key={animated ? fill : 'idle'}
          initial={{ opacity: 0.5, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={SPRING}
        >
          {animated ? `${fill}%` : '--%'}
        </motion.span>
      </div>
      <div className="h-2.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full bg-gradient-to-r ${getColor(fill)}`}
          initial={{ width: '0%' }}
          animate={{ width: animated ? `${fill}%` : '0%' }}
          transition={{ ...SPRING, delay: 0.1 }}
        />
      </div>
    </div>
  );
}

function TokenUsageBar({
  label,
  value,
  maxVal,
  color,
  animated,
}: {
  label: string;
  value: number;
  maxVal: number;
  color: string;
  animated: boolean;
}) {
  const pct = Math.min((value / maxVal) * 100, 100);
  const formatted = value >= 1000 ? `${(value / 1000).toFixed(0)}k` : `${value}`;
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="text-[10px] text-white/40">{label}</span>
        <span className="text-[10px] font-mono text-white/60">
          {animated ? formatted : '--'}
        </span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${color}`}
          initial={{ width: '0%' }}
          animate={{ width: animated ? `${pct}%` : '0%' }}
          transition={{ ...SPRING, delay: 0.2 }}
        />
      </div>
    </div>
  );
}

function StackTracePanel({ frames, animated }: { frames: StackFrame[]; animated: boolean }) {
  return (
    <div className="space-y-1.5">
      {frames.map((frame, i) => (
        <motion.div
          key={frame.layer}
          initial={{ opacity: 0, x: -12 }}
          animate={{ opacity: animated ? 1 : 0.3, x: animated ? 0 : -12 }}
          transition={{ ...SPRING, delay: animated ? i * 0.08 : 0 }}
          className={`flex items-start gap-2 rounded-lg border px-2.5 py-1.5 text-[11px] ${
            frame.isError
              ? 'border-red-500/30 bg-red-500/[0.06]'
              : 'border-white/[0.06] bg-white/[0.02]'
          }`}
        >
          <div className={`mt-0.5 h-1.5 w-1.5 rounded-full shrink-0 ${
            frame.isError ? 'bg-red-400' : 'bg-emerald-400'
          }`} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="font-semibold text-white/80">{frame.layer}</span>
              <span className="text-white/30 font-mono truncate">{frame.file}</span>
            </div>
            <p className={`mt-0.5 ${frame.isError ? 'text-red-300/80' : 'text-white/50'}`}>
              {frame.description}
            </p>
          </div>
        </motion.div>
      ))}
    </div>
  );
}

function DivergencePanel({
  agentView,
  reality,
  animated,
}: {
  agentView: string[];
  reality: string[];
  animated: boolean;
}) {
  return (
    <div className="grid grid-cols-2 gap-2">
      {/* Agent's View */}
      <div className="rounded-xl border border-blue-500/20 bg-blue-500/[0.04] p-2.5">
        <div className="flex items-center gap-1.5 mb-2">
          <Eye className="h-3 w-3 text-blue-400" />
          <span className="text-[10px] font-semibold text-blue-300">Agent Believes</span>
        </div>
        <div className="space-y-1">
          {agentView.map((line, i) => (
            <motion.p
              key={`a-${i}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: animated ? 1 : 0.2 }}
              transition={{ ...SPRING, delay: animated ? i * 0.06 : 0 }}
              className="text-xs text-white/60 leading-relaxed"
            >
              {line}
            </motion.p>
          ))}
        </div>
      </div>
      {/* Reality */}
      <div className="rounded-xl border border-red-500/20 bg-red-500/[0.04] p-2.5">
        <div className="flex items-center gap-1.5 mb-2">
          <EyeOff className="h-3 w-3 text-red-400" />
          <span className="text-[10px] font-semibold text-red-300">Reality</span>
        </div>
        <div className="space-y-1">
          {reality.map((line, i) => (
            <motion.p
              key={`r-${i}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: animated ? 1 : 0.2 }}
              transition={{ ...SPRING, delay: animated ? i * 0.06 + 0.2 : 0 }}
              className="text-xs text-white/60 leading-relaxed"
            >
              {line}
            </motion.p>
          ))}
        </div>
      </div>
    </div>
  );
}

function FixSuggestionsPanel({ fixes, animated }: { fixes: FixSuggestion[]; animated: boolean }) {
  return (
    <div className="space-y-1.5">
      {fixes.map((fix, i) => (
        <motion.div
          key={fix.rank}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: animated ? 1 : 0.2, y: animated ? 0 : 8 }}
          transition={{ ...SPRING, delay: animated ? i * 0.1 : 0 }}
          className="flex items-start gap-2.5 rounded-lg border border-white/[0.06] bg-white/[0.02] px-3 py-2"
        >
          <div className={`mt-0.5 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold shrink-0 ${
            fix.rank === 1
              ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
              : 'bg-white/[0.06] text-white/50 border border-white/[0.08]'
          }`}>
            {fix.rank}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-between gap-2">
              <span className="text-[11px] font-medium text-white/80">{fix.label}</span>
              <span className={`text-[10px] font-mono shrink-0 ${
                fix.confidence >= 90 ? 'text-emerald-400' : fix.confidence >= 80 ? 'text-amber-400' : 'text-white/40'
              }`}>
                {animated ? `${fix.confidence}%` : '--%'}
              </span>
            </div>
            <code className="mt-1 block text-[10px] text-amber-300/70 bg-white/[0.03] px-1.5 py-0.5 rounded font-mono truncate">
              {fix.command}
            </code>
          </div>
        </motion.div>
      ))}
    </div>
  );
}

function SessionLogPanel({ entries, animated }: { entries: LogEntry[]; animated: boolean }) {
  const levelColors: Record<string, string> = {
    info: 'text-cyan-400/70',
    warn: 'text-amber-400/80',
    error: 'text-red-400',
  };
  const levelDots: Record<string, string> = {
    info: 'bg-cyan-400/60',
    warn: 'bg-amber-400',
    error: 'bg-red-400',
  };

  return (
    <div className="space-y-0.5 font-mono">
      {entries.map((entry, i) => (
        <motion.div
          key={`${entry.time}-${i}`}
          initial={{ opacity: 0, x: -6 }}
          animate={{ opacity: animated ? 1 : 0.15, x: animated ? 0 : -6 }}
          transition={{ ...SPRING, delay: animated ? i * 0.07 : 0 }}
          className="flex items-start gap-2 py-0.5"
        >
          <div className={`mt-1.5 h-1.5 w-1.5 rounded-full shrink-0 ${levelDots[entry.level]}`} />
          <span className="text-[10px] text-white/30 shrink-0">{entry.time}</span>
          <span className={`text-[10px] ${levelColors[entry.level]}`}>{entry.message}</span>
        </motion.div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Animated SVG agent status indicator
// ---------------------------------------------------------------------------

function AgentStatusSVG({ scenario, animated }: { scenario: DebugScenario; animated: boolean }) {
  const turnsAngle = animated ? (scenario.conversationTurns / 60) * 360 : 0;
  const fillAngle = animated ? (scenario.contextFill / 100) * 360 : 0;

  // SVG arc helper for circular gauge
  const describeArc = (cx: number, cy: number, r: number, startAngle: number, endAngle: number) => {
    const clampedEnd = Math.min(endAngle, 359.99);
    const startRad = ((startAngle - 90) * Math.PI) / 180;
    const endRad = ((clampedEnd - 90) * Math.PI) / 180;
    const x1 = cx + r * Math.cos(startRad);
    const y1 = cy + r * Math.sin(startRad);
    const x2 = cx + r * Math.cos(endRad);
    const y2 = cy + r * Math.sin(endRad);
    const largeArc = clampedEnd - startAngle > 180 ? 1 : 0;
    return `M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2}`;
  };

  const getContextColor = (val: number) => {
    if (val >= 90) return '#f87171';
    if (val >= 70) return '#fbbf24';
    return '#34d399';
  };

  return (
    <svg viewBox="0 0 120 120" className="w-full h-full" aria-hidden="true">
      {/* Background ring */}
      <circle cx="60" cy="60" r="50" fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="8" />
      {/* Context fill ring */}
      <motion.path
        d={describeArc(60, 60, 50, 0, fillAngle)}
        fill="none"
        stroke={getContextColor(scenario.contextFill)}
        strokeWidth="8"
        strokeLinecap="round"
        initial={{ pathLength: 0 }}
        animate={{ pathLength: animated ? 1 : 0 }}
        transition={{ duration: 1.2, ease: 'easeOut' }}
      />
      {/* Inner ring: turns */}
      <circle cx="60" cy="60" r="38" fill="none" stroke="rgba(255,255,255,0.04)" strokeWidth="4" />
      <motion.path
        d={describeArc(60, 60, 38, 0, turnsAngle)}
        fill="none"
        stroke="#818cf8"
        strokeWidth="4"
        strokeLinecap="round"
        initial={{ pathLength: 0 }}
        animate={{ pathLength: animated ? 1 : 0 }}
        transition={{ duration: 1, ease: 'easeOut', delay: 0.3 }}
      />
      {/* Center text */}
      <text x="60" y="55" textAnchor="middle" className="fill-white/80 text-[14px] font-bold font-mono">
        {animated ? scenario.conversationTurns : '--'}
      </text>
      <text x="60" y="70" textAnchor="middle" className="fill-white/40 text-[8px]">
        turns
      </text>
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Main War Room Component
// ---------------------------------------------------------------------------

function InteractiveDebugDashboardImpl() {
  const [scenarios] = useState<DebugScenario[]>(makeScenarios);
  const [activeIdx, setActiveIdx] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [debugPhase, setDebugPhase] = useState<'idle' | 'scanning' | 'analyzed'>('idle');
  const phaseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const scenario = scenarios[activeIdx];

  const cleanup = useCallback(() => {
    if (phaseTimerRef.current) {
      clearTimeout(phaseTimerRef.current);
      phaseTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    return cleanup;
  }, [cleanup]);

  // Handle step navigation
  const goToScenario = useCallback((idx: number) => {
    cleanup();
    setActiveIdx(idx);
    setDebugPhase('idle');
    setIsPlaying(false);
  }, [cleanup]);

  const goNext = useCallback(() => {
    if (activeIdx < scenarios.length - 1) {
      goToScenario(activeIdx + 1);
    }
  }, [activeIdx, scenarios.length, goToScenario]);

  const goPrev = useCallback(() => {
    if (activeIdx > 0) {
      goToScenario(activeIdx - 1);
    }
  }, [activeIdx, goToScenario]);

  // Run the diagnostic animation
  const handleDiagnose = useCallback(() => {
    if (isPlaying) return;
    cleanup();
    setIsPlaying(true);
    setDebugPhase('scanning');

    phaseTimerRef.current = setTimeout(() => {
      setDebugPhase('analyzed');
      setIsPlaying(false);
    }, 1800);
  }, [isPlaying, cleanup]);

  const handleReset = useCallback(() => {
    cleanup();
    setDebugPhase('idle');
    setIsPlaying(false);
  }, [cleanup]);

  const isAnalyzed = debugPhase === 'analyzed';
  const isScanning = debugPhase === 'scanning';

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-red-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/[0.04] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="flex items-center justify-center gap-2">
            <Shield className="h-4 w-4 text-red-400" />
            <p className="text-sm font-semibold text-white/90">Agent Debug War Room</p>
          </div>
          <p className="text-xs text-white/50">
            Step through 6 real debugging scenarios. Click &ldquo;Diagnose&rdquo; to analyze each one.
          </p>
        </div>

        {/* Scenario Stepper */}
        <div className="flex items-center gap-1 justify-center flex-wrap">
          {scenarios.map((s, i) => (
            <motion.button
              key={s.id}
              type="button"
              onClick={() => goToScenario(i)}
              whileHover={{ scale: 1.08 }}
              whileTap={{ scale: 0.95 }}
              transition={SPRING}
              className={`flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-[10px] font-medium transition-colors border ${
                i === activeIdx
                  ? `${s.borderColor} ${s.bgColor} ${s.color}`
                  : 'border-white/[0.06] bg-white/[0.02] text-white/40 hover:text-white/60 hover:border-white/[0.12]'
              }`}
            >
              {s.icon}
              <span className="hidden sm:inline">{s.title}</span>
              <span className="sm:hidden">{i + 1}</span>
            </motion.button>
          ))}
        </div>

        {/* Scenario Title Bar */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING}
            className={`flex items-center justify-between rounded-xl border ${scenario.borderColor} ${scenario.bgColor} px-4 py-2.5`}
          >
            <div className="flex items-center gap-2">
              <span className={scenario.color}>{scenario.icon}</span>
              <span className={`text-sm font-semibold ${scenario.color}`}>{scenario.title}</span>
            </div>
            <div className="flex items-center gap-1.5 text-[10px] text-white/40">
              <span>Scenario {activeIdx + 1}/{scenarios.length}</span>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Main Dashboard Grid */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="grid grid-cols-1 lg:grid-cols-3 gap-3"
          >
            {/* Left Column: Agent State */}
            <div className="space-y-3">
              {/* Agent Status Gauge */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Cpu className="h-3.5 w-3.5 text-indigo-400" />
                  <span className="text-[11px] font-semibold text-white/80">Agent State</span>
                  {isScanning && (
                    <motion.div
                      animate={inView ? { rotate: 360 } : { rotate: 0 }}
                      transition={inView ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                      className="ml-auto"
                    >
                      <RefreshCw className="h-3 w-3 text-blue-400" />
                    </motion.div>
                  )}
                </div>

                <div className="flex items-center gap-3">
                  <div className="w-20 h-20 shrink-0">
                    <AgentStatusSVG scenario={scenario} animated={isAnalyzed || isScanning} />
                  </div>
                  <div className="flex-1 space-y-2">
                    <ContextFillGauge fill={scenario.contextFill} animated={isAnalyzed || isScanning} />
                    <TokenUsageBar
                      label="Input tokens"
                      value={scenario.tokenUsage.input}
                      maxVal={200000}
                      color="bg-gradient-to-r from-cyan-500 to-blue-500"
                      animated={isAnalyzed || isScanning}
                    />
                    <TokenUsageBar
                      label="Output tokens"
                      value={scenario.tokenUsage.output}
                      maxVal={200000}
                      color="bg-gradient-to-r from-violet-500 to-purple-500"
                      animated={isAnalyzed || isScanning}
                    />
                  </div>
                </div>
              </div>

              {/* Error Stack Trace */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Layers className="h-3.5 w-3.5 text-red-400" />
                  <span className="text-[11px] font-semibold text-white/80">Error Trace</span>
                </div>
                <StackTracePanel frames={scenario.stackFrames} animated={isAnalyzed} />
              </div>
            </div>

            {/* Center Column: Divergence + Fixes */}
            <div className="space-y-3">
              {/* Agent View vs Reality */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3">
                <div className="flex items-center gap-2 mb-2">
                  <BarChart3 className="h-3.5 w-3.5 text-amber-400" />
                  <span className="text-[11px] font-semibold text-white/80">Model vs Reality</span>
                </div>
                <DivergencePanel
                  agentView={scenario.agentView}
                  reality={scenario.reality}
                  animated={isAnalyzed}
                />
              </div>

              {/* Fix Suggestions */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Zap className="h-3.5 w-3.5 text-emerald-400" />
                  <span className="text-[11px] font-semibold text-white/80">Ranked Fixes</span>
                </div>
                <FixSuggestionsPanel fixes={scenario.fixes} animated={isAnalyzed} />
              </div>
            </div>

            {/* Right Column: Session Log */}
            <div className="space-y-3">
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-3">
                <div className="flex items-center gap-2 mb-2">
                  <Terminal className="h-3.5 w-3.5 text-cyan-400" />
                  <span className="text-[11px] font-semibold text-white/80">Session Log</span>
                </div>
                <div className="max-h-[280px] overflow-y-auto scrollbar-thin">
                  <SessionLogPanel entries={scenario.sessionLog} animated={isAnalyzed || isScanning} />
                </div>
              </div>

              {/* Diagnosis Summary */}
              <AnimatePresence>
                {isAnalyzed && (
                  <motion.div
                    initial={{ opacity: 0, y: 12, height: 0 }}
                    animate={{ opacity: 1, y: 0, height: 'auto' }}
                    exit={{ opacity: 0, y: -8, height: 0 }}
                    transition={SPRING}
                    className="rounded-2xl border border-emerald-500/30 bg-emerald-500/[0.06] p-3 overflow-hidden"
                  >
                    <div className="flex items-center gap-2 mb-2">
                      <CheckCircle2 className="h-4 w-4 text-emerald-400" />
                      <span className="text-xs font-semibold text-emerald-300">Root Cause Identified</span>
                    </div>
                    <p className="text-xs text-white/70 leading-relaxed">
                      {scenario.stackFrames.find((f) => f.isError)?.description ?? 'Unknown error'}
                      {' '}&#8212; {scenario.fixes[0]?.label ?? 'Manual investigation needed'} (
                      <span className="text-emerald-400 font-mono">{scenario.fixes[0]?.confidence ?? 0}% confidence</span>)
                    </p>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Controls */}
        <div className="flex items-center justify-center gap-3 pt-1">
          <motion.button
            type="button"
            onClick={goPrev}
            disabled={activeIdx === 0}
            whileHover={{ scale: 1.06 }}
            whileTap={{ scale: 0.95 }}
            transition={SPRING}
            className={`flex items-center gap-1 rounded-xl border px-3 py-2 text-xs font-medium transition-colors ${
              activeIdx === 0
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-white/[0.1] text-white/60 hover:bg-white/[0.04]'
            }`}
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Prev
          </motion.button>

          {isAnalyzed ? (
            <motion.button
              type="button"
              onClick={handleReset}
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.96 }}
              transition={SPRING}
              className="flex items-center gap-2 rounded-xl border border-white/[0.12] bg-white/[0.04] px-5 py-2 text-xs font-medium text-white/60 hover:bg-white/[0.06] transition-colors"
            >
              <RefreshCw className="h-3.5 w-3.5" />
              Reset
            </motion.button>
          ) : (
            <motion.button
              type="button"
              onClick={handleDiagnose}
              disabled={isScanning}
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.96 }}
              transition={SPRING}
              className={`flex items-center gap-2 rounded-xl border px-5 py-2 text-xs font-medium transition-colors ${
                isScanning
                  ? 'border-blue-500/20 bg-blue-500/[0.06] text-blue-300/50 cursor-not-allowed'
                  : 'border-blue-500/40 bg-blue-500/10 text-blue-300 hover:bg-blue-500/20'
              }`}
            >
              {isScanning ? (
                <>
                  <motion.div
                    animate={inView ? { rotate: 360 } : { rotate: 0 }}
                    transition={inView ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                  >
                    <Activity className="h-3.5 w-3.5" />
                  </motion.div>
                  Scanning...
                </>
              ) : (
                <>
                  <Bug className="h-3.5 w-3.5" />
                  Diagnose
                </>
              )}
            </motion.button>
          )}

          <motion.button
            type="button"
            onClick={goNext}
            disabled={activeIdx === scenarios.length - 1}
            whileHover={{ scale: 1.06 }}
            whileTap={{ scale: 0.95 }}
            transition={SPRING}
            className={`flex items-center gap-1 rounded-xl border px-3 py-2 text-xs font-medium transition-colors ${
              activeIdx === scenarios.length - 1
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-white/[0.1] text-white/60 hover:bg-white/[0.04]'
            }`}
          >
            Next
            <ChevronRight className="h-3.5 w-3.5" />
          </motion.button>
        </div>
      </div>
    </div>
  );
}
