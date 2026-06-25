'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Monitor,
  Terminal,
  Zap,
  Eye,
  Settings,
  Activity,
  Play,
  Shield,
  Search,
  ChevronLeft,
  ChevronRight,
  Pause,
  AlertCircle,
  Clock,
  FileText,
  BarChart3,
  Cpu,
  Timer,
  TrendingUp,
  Hash,
  Circle,
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

export function WaLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Coordinate multiple AI coding agents running in WezTerm with real-time observation and automation.
      </GoalBanner>

      {/* Section 1: What Is WA */}
      <Section title="What Is WA?" icon={<Monitor className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>WezTerm Automata (WA)</Highlight> is a terminal hypervisor that
          captures pane output in real-time, detects agent state transitions through
          pattern matching, and enables event-driven automation.
        </Paragraph>
        <Paragraph>
          When running multiple AI agents, you need to know when they hit rate limits,
          complete tasks, or need approval. WA observes all panes with sub-50ms latency
          and can trigger automated responses.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="Real-time Observation"
              description="Sub-50ms pane monitoring"
              gradient="from-cyan-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Pattern Detection"
              description="Recognizes agent state changes"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Full-Text Search"
              description="FTS5 with BM25 ranking"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Safety Engine"
              description="Capability gates & audit trails"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: How It Works */}
      <Section title="How It Works" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          WA runs as a daemon that observes all WezTerm panes, detects patterns,
          and exposes a Robot Mode API for agent integration.
        </Paragraph>

        <div className="mt-8">
          <InteractiveTerminalObserver />
        </div>

        <CodeBlock
          code={`# WA observes terminal panes
Agent types: "Thinking..."
         ↓
# Pattern detection engine
         ↓
Agent completes: "Done!"
         ↓
# Event triggers automation
         ↓
WA notifies other agents via mail`}
          filename="Observation Flow"
        />

        <TipBox variant="tip">
          WA uses delta extraction instead of full buffer snapshots for minimal overhead.
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
            { command: 'wa daemon start', description: 'Start the observation daemon' },
            { command: 'wa daemon status', description: 'Check daemon status' },
            { command: 'wa robot state', description: 'View all panes as JSON' },
            { command: 'wa search "query"', description: 'Search captured output' },
          ]}
        />

        <TipBox variant="warning">
          WA requires WezTerm to be running. It won&apos;t work with other terminal emulators.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Robot Mode */}
      <Section title="Robot Mode API" icon={<Activity className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Robot Mode provides a JSON API for machine-to-machine communication.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'wa robot state', description: 'Get all pane states as JSON' },
            { command: 'wa robot get-text <pane_id>', description: 'Get pane output' },
            { command: 'wa robot send <pane_id> "cmd"', description: 'Send input to pane' },
            { command: 'wa robot wait-for <pane_id> <pattern>', description: 'Wait for pattern' },
          ]}
        />

        <CodeBlock
          code={`# Example: Wait for agent completion
wa robot wait-for 42 "Task complete"

# Then trigger next action
wa robot send 43 "Start next task"`}
          filename="Robot Mode Example"
        />
      </Section>

      <Divider />

      {/* Section 5: Pattern Detection */}
      <Section title="Pattern Detection" icon={<Eye className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          WA detects state transitions for common AI agents.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-cyan-500/10 border border-cyan-500/30">
            <span className="text-cyan-400 font-semibold">Claude Code</span>
            <p className="text-white/80 text-sm mt-1">Rate limits, approvals, completions</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">Codex CLI</span>
            <p className="text-white/80 text-sm mt-1">Task completion, errors, waiting</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Antigravity CLI</span>
            <p className="text-white/80 text-sm mt-1">Response completion, quota warnings</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">Custom Patterns</span>
            <p className="text-white/80 text-sm mt-1">Define your own detection rules</p>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Section 6: Tool Integration */}
      <Section title="Tool Integration" icon={<Zap className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          WA integrates seamlessly with other flywheel tools.
        </Paragraph>

        <div className="space-y-4">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.4 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">WA + NTM</h4>
            <p className="text-muted-foreground text-sm">
              WA automatically observes agents spawned by NTM. Use NTM to spawn
              agents and WA to monitor their state.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.45 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">WA + Agent Mail</h4>
            <p className="text-muted-foreground text-sm">
              State changes detected by WA can trigger Agent Mail notifications.
              Coordinate agent handoffs through mail threads.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">WA + Beads</h4>
            <p className="text-muted-foreground text-sm">
              When WA detects task completion, it can update bead status.
              Track agent progress through your issue tracker.
            </p>
          </motion.div>
        </div>
      </Section>

      <Divider />

      {/* Section 7: Diagnostics */}
      <Section title="Diagnostics" icon={<Settings className="h-5 w-5" />} delay={0.4}>
        <Paragraph>
          Troubleshoot issues with built-in diagnostics.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'wa doctor', description: 'Run diagnostic checks' },
            { command: 'wa daemon status', description: 'Check daemon health' },
            { command: 'wa logs --tail 50', description: 'View recent logs' },
          ]}
        />

        <TipBox variant="info">
          Run <code>wa doctor</code> if pattern detection isn&apos;t working. It checks
          WezTerm connectivity and daemon status.
        </TipBox>
      </Section>
    </div>
  );
}

/* =============================================================================
 * InteractiveTerminalObserver — Agent Workspace Observatory
 *
 * Multi-pane view showing what agents are doing across tmux sessions with
 * activity heatmap, productivity metrics, timeline, and monitoring commands.
 * ========================================================================== */

// --- Types ---

interface AgentPaneData {
  id: number;
  name: string;
  status: 'active' | 'idle' | 'error' | 'complete' | 'rate-limited';
  lines: { text: string; color: string }[];
  linesChanged: number;
  filesTouched: number;
  commandsRun: number;
  progress: number;
}

interface FileActivity {
  path: string;
  heat: number; // 0-1
  agent: number;
}

interface TimelineEvent {
  time: string;
  agent: number;
  event: string;
  type: 'info' | 'warning' | 'error' | 'success';
}

interface Scenario {
  label: string;
  description: string;
  panes: AgentPaneData[];
  files: FileActivity[];
  timeline: TimelineEvent[];
  monitorOutput: string[];
  alertMessage: string | null;
}

// --- Scenario data ---

const SCENARIOS: Scenario[] = [
  {
    label: 'Single Agent Working',
    description: 'One agent actively coding in pane #42',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'Reading src/routes/users.ts...', color: 'text-white/70' },
          { text: 'Analyzing authentication flow...', color: 'text-white/70' },
          { text: 'Writing src/middleware/auth.ts', color: 'text-cyan-400' },
          { text: '+ export function validateToken()', color: 'text-emerald-400' },
        ],
        linesChanged: 47, filesTouched: 3, commandsRun: 12, progress: 35,
      },
      {
        id: 43, name: 'idle', status: 'idle',
        lines: [
          { text: '$ _', color: 'text-white/30' },
        ],
        linesChanged: 0, filesTouched: 0, commandsRun: 0, progress: 0,
      },
      {
        id: 44, name: 'idle', status: 'idle',
        lines: [
          { text: '$ _', color: 'text-white/30' },
        ],
        linesChanged: 0, filesTouched: 0, commandsRun: 0, progress: 0,
      },
      {
        id: 45, name: 'idle', status: 'idle',
        lines: [
          { text: '$ _', color: 'text-white/30' },
        ],
        linesChanged: 0, filesTouched: 0, commandsRun: 0, progress: 0,
      },
    ],
    files: [
      { path: 'src/routes/users.ts', heat: 0.8, agent: 42 },
      { path: 'src/middleware/auth.ts', heat: 1.0, agent: 42 },
      { path: 'src/types/auth.d.ts', heat: 0.4, agent: 42 },
    ],
    timeline: [
      { time: '14:32', agent: 42, event: 'Started task: auth middleware', type: 'info' },
      { time: '14:33', agent: 42, event: 'Reading 3 files', type: 'info' },
      { time: '14:35', agent: 42, event: 'Writing auth.ts (47 lines)', type: 'success' },
    ],
    monitorOutput: [
      '$ wa robot state | jq ".panes[] | {id,status}"',
      '{"id": 42, "status": "active"}',
      '{"id": 43, "status": "idle"}',
      '{"id": 44, "status": "idle"}',
      '{"id": 45, "status": "idle"}',
    ],
    alertMessage: null,
  },
  {
    label: 'Multi-Agent Swarm',
    description: 'Four agents working on different parts of the codebase',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'Writing src/routes/products.ts', color: 'text-cyan-400' },
          { text: '+ export async function getProducts()', color: 'text-emerald-400' },
          { text: '+ export async function createProduct()', color: 'text-emerald-400' },
        ],
        linesChanged: 124, filesTouched: 8, commandsRun: 34, progress: 65,
      },
      {
        id: 43, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project frontend', color: 'text-emerald-400' },
          { text: 'Writing components/ProductCard.tsx', color: 'text-cyan-400' },
          { text: '+ function ProductCard({ product })', color: 'text-emerald-400' },
        ],
        linesChanged: 89, filesTouched: 5, commandsRun: 22, progress: 48,
      },
      {
        id: 44, name: 'codex', status: 'active',
        lines: [
          { text: '$ codex --task "write tests"', color: 'text-violet-400' },
          { text: 'Creating tests/products.test.ts', color: 'text-cyan-400' },
          { text: '+ describe("Products API", () => {', color: 'text-emerald-400' },
        ],
        linesChanged: 67, filesTouched: 4, commandsRun: 18, progress: 72,
      },
      {
        id: 45, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project docs', color: 'text-emerald-400' },
          { text: 'Writing docs/api-reference.md', color: 'text-cyan-400' },
          { text: '## Products Endpoint', color: 'text-white/70' },
        ],
        linesChanged: 156, filesTouched: 6, commandsRun: 41, progress: 83,
      },
    ],
    files: [
      { path: 'src/routes/products.ts', heat: 1.0, agent: 42 },
      { path: 'src/models/product.ts', heat: 0.7, agent: 42 },
      { path: 'components/ProductCard.tsx', heat: 0.9, agent: 43 },
      { path: 'components/ProductList.tsx', heat: 0.6, agent: 43 },
      { path: 'tests/products.test.ts', heat: 0.8, agent: 44 },
      { path: 'docs/api-reference.md', heat: 1.0, agent: 45 },
    ],
    timeline: [
      { time: '14:20', agent: 42, event: 'Started: API routes', type: 'info' },
      { time: '14:21', agent: 43, event: 'Started: Frontend components', type: 'info' },
      { time: '14:22', agent: 44, event: 'Started: Test suite', type: 'info' },
      { time: '14:23', agent: 45, event: 'Started: Documentation', type: 'info' },
      { time: '14:30', agent: 44, event: '12 tests passing', type: 'success' },
      { time: '14:35', agent: 42, event: '6 routes created', type: 'success' },
    ],
    monitorOutput: [
      '$ wa robot state --summary',
      'Active agents: 4/4',
      'Total lines changed: 436',
      'Files touched: 23',
      'Swarm health: OPTIMAL',
    ],
    alertMessage: null,
  },
  {
    label: 'Agent Stuck in Loop',
    description: 'Agent #44 is repeating the same fix-lint-fix cycle',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'Refactoring database layer...', color: 'text-white/70' },
        ],
        linesChanged: 201, filesTouched: 11, commandsRun: 45, progress: 70,
      },
      {
        id: 43, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project frontend', color: 'text-emerald-400' },
          { text: 'Building search component...', color: 'text-white/70' },
        ],
        linesChanged: 98, filesTouched: 6, commandsRun: 28, progress: 55,
      },
      {
        id: 44, name: 'codex', status: 'error',
        lines: [
          { text: '$ codex --task "fix lint"', color: 'text-violet-400' },
          { text: 'Fixing src/utils.ts...', color: 'text-yellow-400' },
          { text: 'ESLint: 3 errors remaining', color: 'text-red-400' },
          { text: 'Fixing src/utils.ts... (retry)', color: 'text-yellow-400' },
          { text: 'ESLint: 3 errors remaining', color: 'text-red-400' },
        ],
        linesChanged: 12, filesTouched: 1, commandsRun: 47, progress: 15,
      },
      {
        id: 45, name: 'claude-code', status: 'complete',
        lines: [
          { text: '$ claude --project docs', color: 'text-emerald-400' },
          { text: 'Task complete. All docs updated.', color: 'text-emerald-400' },
        ],
        linesChanged: 312, filesTouched: 14, commandsRun: 52, progress: 100,
      },
    ],
    files: [
      { path: 'src/utils.ts', heat: 1.0, agent: 44 },
      { path: 'src/db/connection.ts', heat: 0.6, agent: 42 },
      { path: 'components/Search.tsx', heat: 0.8, agent: 43 },
    ],
    timeline: [
      { time: '14:40', agent: 44, event: 'Fix attempt #1: src/utils.ts', type: 'warning' },
      { time: '14:41', agent: 44, event: 'Fix attempt #2: src/utils.ts', type: 'warning' },
      { time: '14:42', agent: 44, event: 'LOOP DETECTED: 3+ retries', type: 'error' },
      { time: '14:42', agent: 45, event: 'Task completed successfully', type: 'success' },
    ],
    monitorOutput: [
      '$ wa robot state --alerts',
      'ALERT: Pane #44 loop detected',
      '  Pattern: "ESLint: 3 errors"',
      '  Repeats: 3 (threshold: 2)',
      '  Action: Notify + escalate',
    ],
    alertMessage: 'Loop detected on pane #44 -- agent retrying same fix. Consider intervention.',
  },
  {
    label: 'Agent Making Progress',
    description: 'Agent #42 steadily building a feature with green tests',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project payments', color: 'text-emerald-400' },
          { text: 'Created src/payments/stripe.ts', color: 'text-cyan-400' },
          { text: 'Created src/payments/webhook.ts', color: 'text-cyan-400' },
          { text: 'Running tests... 14/14 passing', color: 'text-emerald-400' },
          { text: 'Writing integration tests...', color: 'text-white/70' },
        ],
        linesChanged: 289, filesTouched: 9, commandsRun: 38, progress: 78,
      },
      {
        id: 43, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project checkout-ui', color: 'text-emerald-400' },
          { text: 'Building PaymentForm component', color: 'text-white/70' },
        ],
        linesChanged: 145, filesTouched: 7, commandsRun: 26, progress: 52,
      },
      {
        id: 44, name: 'idle', status: 'idle',
        lines: [
          { text: '$ _', color: 'text-white/30' },
        ],
        linesChanged: 0, filesTouched: 0, commandsRun: 0, progress: 0,
      },
      {
        id: 45, name: 'claude-code', status: 'active',
        lines: [
          { text: '$ claude --project infra', color: 'text-emerald-400' },
          { text: 'Configuring Stripe webhooks...', color: 'text-white/70' },
        ],
        linesChanged: 78, filesTouched: 4, commandsRun: 19, progress: 40,
      },
    ],
    files: [
      { path: 'src/payments/stripe.ts', heat: 1.0, agent: 42 },
      { path: 'src/payments/webhook.ts', heat: 0.9, agent: 42 },
      { path: 'tests/payments.test.ts', heat: 0.8, agent: 42 },
      { path: 'components/PaymentForm.tsx', heat: 0.7, agent: 43 },
      { path: 'infra/webhook-config.yml', heat: 0.5, agent: 45 },
    ],
    timeline: [
      { time: '14:50', agent: 42, event: 'Created stripe.ts (112 lines)', type: 'success' },
      { time: '14:52', agent: 42, event: 'Created webhook.ts (89 lines)', type: 'success' },
      { time: '14:54', agent: 42, event: '14/14 tests passing', type: 'success' },
      { time: '14:55', agent: 43, event: 'Building PaymentForm', type: 'info' },
    ],
    monitorOutput: [
      '$ wa search "tests passing" --pane 42',
      '[14:54] 14/14 tests passing',
      '[14:52]  8/8 tests passing',
      '[14:50]  3/3 tests passing',
      'Progress: consistent upward trend',
    ],
    alertMessage: null,
  },
  {
    label: 'Agent Rate Limited',
    description: 'Agent #42 hit API rate limit, WA reroutes work',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'rate-limited',
        lines: [
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'Writing src/routes/orders.ts...', color: 'text-white/70' },
          { text: 'ERROR: Rate limit exceeded (429)', color: 'text-red-400' },
          { text: 'Retrying in 58s...', color: 'text-yellow-400' },
        ],
        linesChanged: 167, filesTouched: 7, commandsRun: 31, progress: 45,
      },
      {
        id: 43, name: 'claude-code', status: 'active',
        lines: [
          { text: '--- Work rerouted from pane #42 ---', color: 'text-amber-400' },
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'Continuing orders.ts from pane #42', color: 'text-cyan-400' },
          { text: 'Writing remaining routes...', color: 'text-white/70' },
        ],
        linesChanged: 34, filesTouched: 2, commandsRun: 8, progress: 12,
      },
      {
        id: 44, name: 'codex', status: 'active',
        lines: [
          { text: '$ codex --task "write tests"', color: 'text-violet-400' },
          { text: 'Running test suite... 22/22 pass', color: 'text-emerald-400' },
        ],
        linesChanged: 88, filesTouched: 5, commandsRun: 24, progress: 68,
      },
      {
        id: 45, name: 'idle', status: 'idle',
        lines: [
          { text: '$ _', color: 'text-white/30' },
        ],
        linesChanged: 0, filesTouched: 0, commandsRun: 0, progress: 0,
      },
    ],
    files: [
      { path: 'src/routes/orders.ts', heat: 1.0, agent: 42 },
      { path: 'src/routes/orders.ts', heat: 0.8, agent: 43 },
      { path: 'tests/orders.test.ts', heat: 0.6, agent: 44 },
    ],
    timeline: [
      { time: '15:01', agent: 42, event: 'Rate limit 429 detected', type: 'error' },
      { time: '15:01', agent: 42, event: 'WA: Routing work to pane #43', type: 'warning' },
      { time: '15:02', agent: 43, event: 'Picked up task from pane #42', type: 'info' },
      { time: '15:03', agent: 43, event: 'Continuing orders.ts', type: 'success' },
    ],
    monitorOutput: [
      '$ wa robot state --alerts',
      'RATE_LIMIT: Pane #42 (429)',
      '  Cooldown: 58s remaining',
      '  Rerouted to: Pane #43',
      '  Status: Work continuing',
    ],
    alertMessage: 'Rate limit on pane #42 -- work automatically rerouted to pane #43.',
  },
  {
    label: 'Agent Completing Task',
    description: 'Agent #42 finishes, triggers downstream agents',
    panes: [
      {
        id: 42, name: 'claude-code', status: 'complete',
        lines: [
          { text: '$ claude --project api-server', color: 'text-emerald-400' },
          { text: 'All routes implemented', color: 'text-emerald-400' },
          { text: 'All 38 tests passing', color: 'text-emerald-400' },
          { text: 'Task complete. Notifying swarm.', color: 'text-emerald-400' },
        ],
        linesChanged: 512, filesTouched: 18, commandsRun: 67, progress: 100,
      },
      {
        id: 43, name: 'claude-code', status: 'active',
        lines: [
          { text: '--- Triggered by pane #42 completion ---', color: 'text-amber-400' },
          { text: '$ claude --project integration', color: 'text-emerald-400' },
          { text: 'Running full integration suite...', color: 'text-white/70' },
        ],
        linesChanged: 23, filesTouched: 2, commandsRun: 5, progress: 10,
      },
      {
        id: 44, name: 'codex', status: 'active',
        lines: [
          { text: '--- Triggered by pane #42 completion ---', color: 'text-amber-400' },
          { text: '$ codex --task "update changelog"', color: 'text-violet-400' },
          { text: 'Generating CHANGELOG entry...', color: 'text-white/70' },
        ],
        linesChanged: 15, filesTouched: 1, commandsRun: 3, progress: 20,
      },
      {
        id: 45, name: 'claude-code', status: 'active',
        lines: [
          { text: '--- Triggered by pane #42 completion ---', color: 'text-amber-400' },
          { text: '$ claude --project deploy', color: 'text-emerald-400' },
          { text: 'Preparing staging deployment...', color: 'text-white/70' },
        ],
        linesChanged: 8, filesTouched: 1, commandsRun: 4, progress: 15,
      },
    ],
    files: [
      { path: 'src/routes/*.ts', heat: 0.3, agent: 42 },
      { path: 'tests/integration/*.ts', heat: 0.9, agent: 43 },
      { path: 'CHANGELOG.md', heat: 0.7, agent: 44 },
      { path: 'deploy/staging.yml', heat: 0.8, agent: 45 },
    ],
    timeline: [
      { time: '15:10', agent: 42, event: 'TASK COMPLETE: API server', type: 'success' },
      { time: '15:10', agent: 42, event: 'WA: Triggering downstream agents', type: 'info' },
      { time: '15:11', agent: 43, event: 'Started: Integration tests', type: 'info' },
      { time: '15:11', agent: 44, event: 'Started: Changelog update', type: 'info' },
      { time: '15:11', agent: 45, event: 'Started: Staging deploy', type: 'info' },
    ],
    monitorOutput: [
      '$ wa robot state --summary',
      'Pane #42: COMPLETE (512 lines)',
      'Pane #43: triggered -> integration',
      'Pane #44: triggered -> changelog',
      'Pane #45: triggered -> deploy',
    ],
    alertMessage: null,
  },
];

// --- Color helpers ---

const STATUS_COLORS: Record<AgentPaneData['status'], { border: string; bg: string; text: string; dot: string }> = {
  active:       { border: 'border-emerald-500/40', bg: 'bg-emerald-500/5',  text: 'text-emerald-400', dot: 'bg-emerald-400' },
  idle:         { border: 'border-white/[0.08]',   bg: 'bg-white/[0.01]',   text: 'text-white/30',    dot: 'bg-white/20' },
  error:        { border: 'border-red-500/40',     bg: 'bg-red-500/5',      text: 'text-red-400',     dot: 'bg-red-400' },
  complete:     { border: 'border-cyan-500/40',    bg: 'bg-cyan-500/5',     text: 'text-cyan-400',    dot: 'bg-cyan-400' },
  'rate-limited': { border: 'border-amber-500/40', bg: 'bg-amber-500/5',   text: 'text-amber-400',   dot: 'bg-amber-400' },
};

const TIMELINE_COLORS: Record<TimelineEvent['type'], string> = {
  info: 'text-cyan-400',
  warning: 'text-amber-400',
  error: 'text-red-400',
  success: 'text-emerald-400',
};

const TIMELINE_DOTS: Record<TimelineEvent['type'], string> = {
  info: 'bg-cyan-400',
  warning: 'bg-amber-400',
  error: 'bg-red-400',
  success: 'bg-emerald-400',
};

// --- Sub-components ---

function AgentMiniPane({ pane, index }: { pane: AgentPaneData; index: number }) {
  const colors = STATUS_COLORS[pane.status];
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25, delay: index * 0.08 }}
      className={`rounded-lg border ${colors.border} ${colors.bg} overflow-hidden`}
    >
      {/* Pane title bar */}
      <div className="flex items-center gap-1.5 px-2.5 py-1.5 border-b border-white/[0.06] bg-black/40">
        <div className="flex gap-1">
          <div className="h-1.5 w-1.5 rounded-full bg-red-500/50" />
          <div className="h-1.5 w-1.5 rounded-full bg-yellow-500/50" />
          <div className="h-1.5 w-1.5 rounded-full bg-green-500/50" />
        </div>
        <span className="text-[9px] text-white/40 font-mono ml-1 flex-1 truncate">
          pane #{pane.id} -- {pane.name}
        </span>
        <motion.div
          className={`h-1.5 w-1.5 rounded-full ${colors.dot}`}
          animate={
            pane.status === 'active'
              ? { opacity: [0.5, 1, 0.5] }
              : pane.status === 'error' || pane.status === 'rate-limited'
                ? { opacity: [0.4, 1, 0.4], scale: [1, 1.3, 1] }
                : {}
          }
          transition={{ duration: 1.5, repeat: Infinity }}
        />
      </div>
      {/* Pane terminal content */}
      <div className="p-2 font-mono text-[10px] leading-relaxed min-h-[56px] max-h-[72px] overflow-hidden">
        {pane.lines.map((line, i) => (
          <div key={i} className={`${line.color} truncate`}>{line.text}</div>
        ))}
        {pane.status === 'active' && (
          <motion.span
            className="inline-block w-1.5 h-2.5 bg-emerald-400/80 mt-0.5"
            animate={{ opacity: [1, 0, 1] }}
            transition={{ duration: 1, repeat: Infinity }}
          />
        )}
      </div>
      {/* Progress bar */}
      {pane.progress > 0 && (
        <div className="px-2 pb-1.5">
          <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className={`h-full rounded-full ${
                pane.status === 'complete' ? 'bg-cyan-400' :
                pane.status === 'error' ? 'bg-red-400' :
                pane.status === 'rate-limited' ? 'bg-amber-400' :
                'bg-emerald-400'
              }`}
              initial={{ width: 0 }}
              animate={{ width: `${pane.progress}%` }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            />
          </div>
          <div className={`text-[8px] mt-0.5 ${colors.text}`}>{pane.progress}%</div>
        </div>
      )}
    </motion.div>
  );
}

function ActivityHeatmap({ files }: { files: FileActivity[] }) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-1.5 text-[10px] text-white/40 uppercase tracking-wider">
        <FileText className="h-3 w-3" />
        <span>File Activity</span>
      </div>
      {files.map((file, i) => (
        <motion.div
          key={`${file.path}-${file.agent}-${i}`}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.05 }}
          className="flex items-center gap-2"
        >
          <div className="flex-1 min-w-0">
            <div className="text-[10px] font-mono text-white/60 truncate">{file.path}</div>
          </div>
          <div className="w-16 h-2 rounded-full bg-white/[0.04] overflow-hidden flex-shrink-0">
            <motion.div
              className="h-full rounded-full"
              style={{
                background: `linear-gradient(90deg, rgba(34,211,238,${0.3 + file.heat * 0.5}) 0%, rgba(139,92,246,${0.3 + file.heat * 0.5}) 100%)`,
              }}
              initial={{ width: 0 }}
              animate={{ width: `${file.heat * 100}%` }}
              transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.05 + 0.2 }}
            />
          </div>
          <span className="text-[9px] text-white/30 w-4 text-right font-mono flex-shrink-0">
            #{file.agent}
          </span>
        </motion.div>
      ))}
    </div>
  );
}

function MetricsBar({ panes }: { panes: AgentPaneData[] }) {
  const totalLines = panes.reduce((s, p) => s + p.linesChanged, 0);
  const totalFiles = panes.reduce((s, p) => s + p.filesTouched, 0);
  const totalCommands = panes.reduce((s, p) => s + p.commandsRun, 0);
  const activeAgents = panes.filter((p) => p.status === 'active').length;

  const metrics = [
    { icon: <TrendingUp className="h-3 w-3" />, label: 'Lines', value: totalLines, color: 'text-emerald-400' },
    { icon: <FileText className="h-3 w-3" />, label: 'Files', value: totalFiles, color: 'text-cyan-400' },
    { icon: <Terminal className="h-3 w-3" />, label: 'Cmds', value: totalCommands, color: 'text-violet-400' },
    { icon: <Cpu className="h-3 w-3" />, label: 'Active', value: activeAgents, color: 'text-amber-400' },
  ];

  return (
    <div className="grid grid-cols-4 gap-2">
      {metrics.map((m, i) => (
        <motion.div
          key={m.label}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
          className="text-center p-2 rounded-lg border border-white/[0.06] bg-white/[0.02]"
        >
          <div className={`flex items-center justify-center gap-1 ${m.color}`}>
            {m.icon}
            <span className="text-sm font-bold font-mono">{m.value}</span>
          </div>
          <div className="text-[9px] text-white/40 mt-0.5">{m.label}</div>
        </motion.div>
      ))}
    </div>
  );
}

function EventTimeline({ events }: { events: TimelineEvent[] }) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-1.5 text-[10px] text-white/40 uppercase tracking-wider">
        <Clock className="h-3 w-3" />
        <span>Timeline</span>
      </div>
      <div className="space-y-1">
        {events.map((evt, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: 8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
            className="flex items-start gap-2 text-[10px]"
          >
            <span className="text-white/30 font-mono w-8 flex-shrink-0">{evt.time}</span>
            <div className="flex items-center gap-1.5 mt-0.5 flex-shrink-0">
              <div className={`h-1.5 w-1.5 rounded-full ${TIMELINE_DOTS[evt.type]}`} />
              <Hash className="h-2.5 w-2.5 text-white/20" />
              <span className="text-white/40 font-mono">{evt.agent}</span>
            </div>
            <span className={`${TIMELINE_COLORS[evt.type]} flex-1 min-w-0 truncate`}>
              {evt.event}
            </span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

function MonitorTerminal({ lines }: { lines: string[] }) {
  return (
    <div className="rounded-lg border border-white/[0.08] bg-black/60 overflow-hidden">
      <div className="flex items-center gap-1.5 px-3 py-1.5 border-b border-white/[0.06] bg-white/[0.02]">
        <BarChart3 className="h-3 w-3 text-cyan-400" />
        <span className="text-[9px] text-white/40 font-mono">wa monitor</span>
      </div>
      <div className="p-2.5 font-mono text-[10px] leading-relaxed space-y-0.5">
        {lines.map((line, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: i * 0.08 }}
            className={
              line.startsWith('$') ? 'text-emerald-400' :
              line.startsWith('ALERT') || line.startsWith('RATE_LIMIT') ? 'text-red-400' :
              line.includes('COMPLETE') || line.includes('OPTIMAL') || line.includes('passing') || line.includes('continuing') || line.includes('trend') ? 'text-emerald-400' :
              line.includes('triggered') ? 'text-amber-400' :
              'text-white/60'
            }
          >
            {line}
          </motion.div>
        ))}
        <motion.span
          className="inline-block w-1.5 h-2.5 bg-cyan-400/80 mt-0.5"
          animate={{ opacity: [1, 0, 1] }}
          transition={{ duration: 1, repeat: Infinity }}
        />
      </div>
    </div>
  );
}

// --- Tabs ---

type ObservatoryTab = 'panes' | 'metrics' | 'timeline';

const TAB_CONFIG: { key: ObservatoryTab; label: string; icon: React.ReactNode }[] = [
  { key: 'panes', label: 'Agent Panes', icon: <Monitor className="h-3 w-3" /> },
  { key: 'metrics', label: 'Metrics', icon: <BarChart3 className="h-3 w-3" /> },
  { key: 'timeline', label: 'Timeline', icon: <Timer className="h-3 w-3" /> },
];

// --- Main component ---

function InteractiveTerminalObserver() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [activeTab, setActiveTab] = useState<ObservatoryTab>('panes');
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const totalScenarios = SCENARIOS.length;
  const scenario = SCENARIOS[scenarioIdx];

  // Auto-play timer
  useEffect(() => {
    if (!playing) return;
    if (scenarioIdx >= totalScenarios - 1) {
      setTimeout(() => setPlaying(false), 0);
      return;
    }
    timerRef.current = setTimeout(() => {
      setScenarioIdx((s) => Math.min(s + 1, totalScenarios - 1));
    }, 4000);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [playing, scenarioIdx, totalScenarios]);

  const goNext = useCallback(() => {
    setPlaying(false);
    setScenarioIdx((s) => Math.min(s + 1, totalScenarios - 1));
  }, [totalScenarios]);

  const goPrev = useCallback(() => {
    setPlaying(false);
    setScenarioIdx((s) => Math.max(s - 1, 0));
  }, []);

  const togglePlay = useCallback(() => {
    if (scenarioIdx >= totalScenarios - 1 && !playing) {
      setScenarioIdx(0);
      setPlaying(true);
    } else {
      setPlaying((p) => !p);
    }
  }, [scenarioIdx, totalScenarios, playing]);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-cyan-500/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-40 h-40 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />

      {/* Header: Scenario label + description */}
      <div className="relative px-4 pt-4 pb-2 sm:px-6 sm:pt-5 sm:pb-3">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-black/40 border border-white/[0.08] font-mono text-sm flex-shrink-0">
            <Eye className="h-3.5 w-3.5 text-violet-400" />
            <span className="text-violet-400 text-xs">WA Observatory</span>
          </div>
          <AnimatePresence mode="wait">
            <motion.div
              key={scenarioIdx}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ type: 'spring', stiffness: 300, damping: 25 }}
              className="flex-1 min-w-0"
            >
              <div className="text-white/90 text-sm font-medium">{scenario.label}</div>
              <div className="text-white/40 text-xs">{scenario.description}</div>
            </motion.div>
          </AnimatePresence>
          {/* Scenario counter */}
          <div className="text-[10px] text-white/30 font-mono flex-shrink-0 hidden sm:block">
            {scenarioIdx + 1}/{totalScenarios}
          </div>
        </div>
      </div>

      {/* Alert banner */}
      <AnimatePresence>
        {scenario.alertMessage && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="relative mx-4 sm:mx-6"
          >
            <div className="flex items-start gap-2 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/30 mb-2">
              <AlertCircle className="h-3.5 w-3.5 text-red-400 flex-shrink-0 mt-0.5" />
              <span className="text-red-400 text-xs leading-relaxed">{scenario.alertMessage}</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Tab bar */}
      <div className="relative px-4 sm:px-6 pb-2">
        <div className="flex gap-1 p-1 rounded-lg bg-black/30 border border-white/[0.06]">
          {TAB_CONFIG.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[11px] font-medium transition-all ${
                activeTab === tab.key
                  ? 'bg-white/[0.08] text-white shadow-sm'
                  : 'text-white/40 hover:text-white/60 hover:bg-white/[0.03]'
              }`}
            >
              {tab.icon}
              <span className="hidden sm:inline">{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      <div className="relative px-4 pb-3 sm:px-6">
        <AnimatePresence mode="wait">
          {activeTab === 'panes' && (
            <motion.div
              key={`panes-${scenarioIdx}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
            >
              {/* 2x2 grid of agent panes */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 mb-3">
                {scenario.panes.map((pane, i) => (
                  <AgentMiniPane key={pane.id} pane={pane} index={i} />
                ))}
              </div>

              {/* Bottom row: heatmap + monitor */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="p-3 rounded-lg border border-white/[0.06] bg-black/30">
                  <ActivityHeatmap files={scenario.files} />
                </div>
                <MonitorTerminal lines={scenario.monitorOutput} />
              </div>
            </motion.div>
          )}

          {activeTab === 'metrics' && (
            <motion.div
              key={`metrics-${scenarioIdx}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="space-y-3"
            >
              {/* Aggregate metrics */}
              <MetricsBar panes={scenario.panes} />

              {/* Per-agent breakdown */}
              <div className="space-y-2">
                <div className="flex items-center gap-1.5 text-[10px] text-white/40 uppercase tracking-wider px-1">
                  <Activity className="h-3 w-3" />
                  <span>Per-Agent Breakdown</span>
                </div>
                {scenario.panes.map((pane, i) => {
                  const colors = STATUS_COLORS[pane.status];
                  return (
                    <motion.div
                      key={pane.id}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.06 }}
                      className={`flex items-center gap-3 p-2.5 rounded-lg border ${colors.border} ${colors.bg}`}
                    >
                      <div className="flex items-center gap-1.5 w-20 flex-shrink-0">
                        <Circle className={`h-2 w-2 ${colors.text}`} />
                        <span className="text-[10px] font-mono text-white/60">#{pane.id}</span>
                      </div>
                      <div className="flex-1 grid grid-cols-3 gap-2 text-center">
                        <div>
                          <div className="text-xs font-mono text-emerald-400">{pane.linesChanged}</div>
                          <div className="text-[8px] text-white/30">lines</div>
                        </div>
                        <div>
                          <div className="text-xs font-mono text-cyan-400">{pane.filesTouched}</div>
                          <div className="text-[8px] text-white/30">files</div>
                        </div>
                        <div>
                          <div className="text-xs font-mono text-violet-400">{pane.commandsRun}</div>
                          <div className="text-[8px] text-white/30">cmds</div>
                        </div>
                      </div>
                      <div className="w-12 flex-shrink-0 text-right">
                        <span className={`text-xs font-mono ${colors.text}`}>{pane.progress}%</span>
                      </div>
                    </motion.div>
                  );
                })}
              </div>

              {/* Heatmap in metrics tab too */}
              <div className="p-3 rounded-lg border border-white/[0.06] bg-black/30">
                <ActivityHeatmap files={scenario.files} />
              </div>
            </motion.div>
          )}

          {activeTab === 'timeline' && (
            <motion.div
              key={`timeline-${scenarioIdx}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
              className="space-y-3"
            >
              {/* Timeline events */}
              <div className="p-3 rounded-lg border border-white/[0.06] bg-black/30">
                <EventTimeline events={scenario.timeline} />
              </div>

              {/* Activity sparkline visualization */}
              <div className="p-3 rounded-lg border border-white/[0.06] bg-black/30">
                <div className="flex items-center gap-1.5 text-[10px] text-white/40 uppercase tracking-wider mb-2">
                  <Activity className="h-3 w-3" />
                  <span>Agent Activity (last hour)</span>
                </div>
                <div className="space-y-2">
                  {scenario.panes.map((pane, pi) => {
                    const colors = STATUS_COLORS[pane.status];
                    return (
                      <div key={pane.id} className="flex items-center gap-2">
                        <span className="text-[9px] font-mono text-white/40 w-6">#{pane.id}</span>
                        <div className="flex-1 flex items-end gap-px h-4">
                          {Array.from({ length: 20 }).map((_, bi) => {
                            // Deterministic bar height based on pane id and bar index
                            const seed = (pane.id * 7 + bi * 13 + pi * 3) % 17;
                            const isActive = pane.status === 'active' || pane.status === 'complete' || pane.status === 'error' || pane.status === 'rate-limited';
                            const height = isActive
                              ? Math.max(2, (seed / 17) * 16)
                              : 1;
                            return (
                              <motion.div
                                key={bi}
                                initial={{ height: 0 }}
                                animate={{ height }}
                                transition={{ type: 'spring', stiffness: 200, damping: 25, delay: bi * 0.02 + pi * 0.1 }}
                                className={`flex-1 rounded-sm ${isActive ? colors.dot : 'bg-white/[0.06]'}`}
                                style={{ opacity: isActive ? 0.3 + (seed / 17) * 0.7 : 0.15 }}
                              />
                            );
                          })}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Monitor output */}
              <MonitorTerminal lines={scenario.monitorOutput} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Controls */}
      <div className="relative flex items-center justify-center gap-4 px-6 pb-3 pt-1">
        <button
          type="button"
          onClick={goPrev}
          disabled={scenarioIdx === 0}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition-all hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Previous scenario"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        <button
          type="button"
          onClick={togglePlay}
          className="flex h-10 w-10 items-center justify-center rounded-full border border-primary/30 bg-primary/10 text-primary transition-all hover:bg-primary/20"
          aria-label={playing ? 'Pause' : 'Play'}
        >
          {playing ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
        </button>

        <button
          type="button"
          onClick={goNext}
          disabled={scenarioIdx >= totalScenarios - 1}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition-all hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Next scenario"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      {/* Scenario indicator dots */}
      <div className="relative flex items-center justify-center gap-2 pb-5">
        {SCENARIOS.map((s, i) => (
          <button
            key={i}
            type="button"
            onClick={() => {
              setPlaying(false);
              setScenarioIdx(i);
            }}
            className={`h-2 rounded-full transition-all duration-300 ${
              i === scenarioIdx
                ? 'w-6 bg-primary'
                : i < scenarioIdx
                  ? 'w-2 bg-white/30'
                  : 'w-2 bg-white/10'
            }`}
            aria-label={`Go to scenario ${i + 1}: ${s.label}`}
          />
        ))}
      </div>
    </div>
  );
}
