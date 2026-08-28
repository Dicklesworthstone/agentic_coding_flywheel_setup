'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Workflow,
  Terminal,
  Eye,
  Mail,
  BarChart3,
  ArrowRight,
  RefreshCw,
  ChevronLeft,
  ChevronRight,
  Play,
  Pause,
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
} from './lesson-components';

export function SwarmCoordinationLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Run a complete multi-agent task loop with Beads robot triage, Agent
        Mail reservations, RCH-backed builds, UBS scanning, and a clean handoff.
      </GoalBanner>

      {/* Section 1: The Swarm Pipeline */}
      <Section title="The Swarm Pipeline" icon={<Workflow className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Running a single AI agent is simple. Running <Highlight>3-6 agents
          simultaneously</Highlight> across multiple providers requires
          coordination. The flywheel provides a complete pipeline:
        </Paragraph>

        <div className="mt-6 space-y-3">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <ArrowRight className="h-4 w-4 text-blue-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-blue-400">1. Pick</strong> — use <code>bv --robot-next</code> and <code>br ready --json</code>
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <ArrowRight className="h-4 w-4 text-violet-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-violet-400">2. Claim</strong> — register with Agent Mail and mark the Bead in progress
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <ArrowRight className="h-4 w-4 text-emerald-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-emerald-400">3. Reserve</strong> — lock the exact files before edits start
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-cyan-500/10 border border-cyan-500/30">
            <ArrowRight className="h-4 w-4 text-cyan-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-cyan-400">4. Execute</strong> — keep the slice narrow and coordinate dependencies in-thread
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <ArrowRight className="h-4 w-4 text-amber-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-amber-400">5. Verify</strong> — use <code>rch exec --</code> for heavy Rust gates and scan with UBS
            </span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-rose-500/10 border border-rose-500/30">
            <ArrowRight className="h-4 w-4 text-rose-400 shrink-0" />
            <span className="text-white/90 text-sm">
              <strong className="text-rose-400">6. Land</strong> — close/sync Beads, release reservations, and post the handoff
            </span>
          </div>
        </div>

        <div className="mt-8">
          <InteractiveSwarmOrchestrator />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Coordination Preflight */}
      <Section title="Coordination Preflight" icon={<Terminal className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Start with machine-readable task state, then pull only the prior
          context that can change the plan. Memory is a preflight hint; current
          repo files and Beads state remain the source of truth.
        </Paragraph>

        <CodeBlock
          code={`# Pick ready work without launching an interactive TUI
bv --robot-next
bv --robot-triage
br ready --json

# Inspect and claim exactly one Bead
br show bd-1234 --json
br update bd-1234 --status in_progress

# Pull bounded memory and session history
cm context "bd-1234 checkout validation in /data/projects/my-app" \\
  --workspace /data/projects/my-app --limit 5 --history 3 --json
cass search "checkout validation command shape" \\
  --workspace /data/projects/my-app --limit 5 --fields summary --json --max-tokens 1200

# Register Agent Mail identity through MCP tools
ensure_project(human_key="/data/projects/my-app")
register_agent(
  project_key="/data/projects/my-app",
  program="codex-cli",
  model="gpt-5",
  task_description="bd-1234 checkout validation"
)`}
          filename="Preflight"
        />

        <TipBox variant="tip">
          Keep the memory preflight small: extract command shapes, prior traps,
          and drift-prone facts to recheck. Verify anything stale against
          `AGENTS.md`, README files, Beads output, and the live code.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Claim and Reserve */}
      <Section title="Claim and Reserve" icon={<BarChart3 className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          A swarm stays calm when each agent owns a tight surface. Reserve only
          the files you expect to touch, then announce the claim in the Bead
          thread.
        </Paragraph>

        <CodeBlock
          code={`# Optional: split a larger queue by coherent labels
bv --robot-triage-by-label

# Reserve via Agent Mail MCP before editing
file_reservation_paths(
  project_key="/data/projects/my-app",
  agent_name="BlueLake",
  paths=["src/checkout/session.ts", "tests/checkout/session.test.ts"],
  ttl_seconds=3600,
  exclusive=true,
  reason="bd-1234: checkout validation"
)

# Announce the start in-thread
send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  thread_id="bd-1234",
  subject="[bd-1234] Start: checkout validation",
  body_md="Reserved checkout session files. Plan: validation plus focused tests."
)`}
          filename="Claim and Reservation"
        />

        <TipBox variant="warning">
          If the reservation conflicts, pick a different ready Bead or narrow
          the paths. Do not edit files another active agent has reserved.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Execute and Verify */}
      <Section title="Execute and Verify" icon={<Eye className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Keep implementation narrow, then run the smallest meaningful gate
          first. Rust-heavy gates should go through RCH so parallel agents do
          not overwhelm the local host.
        </Paragraph>

        <CodeBlock
          code={`# Rust checks use remote compilation
rch exec -- cargo test
rch exec -- cargo clippy

# Web checks use Bun
cd apps/web
bun run type-check
bun run lint
bun run build

# Scan only the changed files before commit
ubs src/checkout/session.ts tests/checkout/session.test.ts`}
          filename="Verification Commands"
        />

        <TipBox variant="info">
          For documentation-only changes, use focused static checks and UBS on
          the changed files. For shared code paths, widen to the repo&apos;s full
          gate before commit.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Agent Communication */}
      <Section title="Agent Communication" icon={<Mail className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Agent Mail provides structured messaging between agents. When one
          agent completes a dependency, it posts in the same Bead thread so
          dependents know what changed.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'send_message(..., thread_id="bd-1234")', description: 'Notify a dependent agent in the Bead thread' },
            { command: 'fetch_inbox(project_key=..., agent_name=..., include_bodies=true)', description: 'Check for incoming messages' },
            { command: 'acknowledge_message(project_key=..., agent_name=..., message_id=...)', description: 'Acknowledge important coordination mail' },
            { command: 'file_reservation_paths(..., exclusive=true, reason="bd-1234")', description: 'Reserve files before editing' },
            { command: 'release_file_reservations(project_key=..., agent_name=...)', description: 'Release reservations after commit' },
          ]}
        />

        <CodeBlock
          code={`send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  thread_id="bd-1234",
  subject="[bd-1234] API endpoints ready",
  body_md="GET /users and POST /users are implemented and covered by tests."
)

fetch_inbox(
  project_key="/data/projects/my-app",
  agent_name="GreenCastle",
  include_bodies=true
)`}
          filename="Message Flow"
        />
      </Section>

      <Divider />

      {/* Section 6: Landing the Plane */}
      <Section title="Landing the Plane" icon={<RefreshCw className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          A swarm task is not done when the patch works locally. Close the Bead,
          sync the issue export, commit the exact changed files, release
          reservations, and leave a final handoff in the thread.
        </Paragraph>

        <CodeBlock
          code={`br close bd-1234 --reason "Implemented checkout validation"
br sync --flush-only

git status
git add src/checkout/session.ts tests/checkout/session.test.ts .beads/
git commit -m "fix(checkout): validate checkout sessions"
git push origin main
git push origin main:master

release_file_reservations(
  project_key="/data/projects/my-app",
  agent_name="BlueLake"
)

send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  thread_id="bd-1234",
  subject="[bd-1234] Completed: checkout validation",
  body_md="Landed commit abc123. Gates: type-check, lint, build, UBS. Reservations released."
)`}
          filename="Closeout Flow"
        />

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">Beads Closed</span>
            <p className="text-white/80 text-sm mt-1">Finished work is closed and exported with <code>br sync --flush-only</code></p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Focused Commit</span>
            <p className="text-white/80 text-sm mt-1">Only owned files and Beads export changes are staged</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">Reservations Released</span>
            <p className="text-white/80 text-sm mt-1">Other agents can safely pick nearby work</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">Thread Handoff</span>
            <p className="text-white/80 text-sm mt-1">The final note lists changes, gates, and residual risk</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE SWARM COMMAND CENTER - 7-step coordination simulation
// =============================================================================

const SPRING_CFG = { type: 'spring' as const, stiffness: 200, damping: 25 };

// -- Agent definitions (hexagonal layout) -------------------------------------

interface HexAgent {
  id: string;
  name: string;
  provider: string;
  task: string;
  files: string[];
  color: string;
  /** Hex grid column/row for layout */
  col: number;
  row: number;
}

const HEX_AGENTS: HexAgent[] = [
  { id: 'claude-1', name: 'Claude-1', provider: 'Anthropic', task: 'Backend API', files: ['src/api/routes.ts', 'src/api/middleware.ts'], color: '#f97316', col: 0, row: 0 },
  { id: 'claude-2', name: 'Claude-2', provider: 'Anthropic', task: 'Auth System', files: ['src/auth/oauth.ts', 'src/auth/session.ts'], color: '#fb923c', col: 2, row: 0 },
  { id: 'codex-1', name: 'Codex-1', provider: 'OpenAI', task: 'Frontend UI', files: ['src/components/App.tsx', 'src/components/Nav.tsx'], color: '#10b981', col: 4, row: 0 },
  { id: 'gemini-1', name: 'Gemini-1', provider: 'Google', task: 'Database Layer', files: ['src/db/schema.ts', 'src/db/migrations.ts'], color: '#3b82f6', col: 1, row: 1 },
  { id: 'claude-3', name: 'Claude-3', provider: 'Anthropic', task: 'Tests & CI', files: ['tests/api.test.ts', 'tests/auth.test.ts'], color: '#e879f9', col: 3, row: 1 },
  { id: 'codex-2', name: 'Codex-2', provider: 'OpenAI', task: 'Docs & Types', files: ['docs/api.md', 'src/types/index.ts'], color: '#22d3ee', col: 5, row: 1 },
];

type AgentStatus = 'idle' | 'spawning' | 'working' | 'sending' | 'conflict' | 'merging' | 'done' | 'rate-limited';

const STATUS_PALETTE: Record<AgentStatus, { bg: string; border: string; label: string }> = {
  idle: { bg: 'rgba(255,255,255,0.03)', border: 'rgba(255,255,255,0.1)', label: 'Idle' },
  spawning: { bg: 'rgba(139,92,246,0.12)', border: 'rgba(139,92,246,0.5)', label: 'Spawning' },
  working: { bg: 'rgba(16,185,129,0.10)', border: 'rgba(52,211,153,0.5)', label: 'Working' },
  sending: { bg: 'rgba(234,179,8,0.10)', border: 'rgba(250,204,21,0.5)', label: 'Sending Mail' },
  conflict: { bg: 'rgba(239,68,68,0.12)', border: 'rgba(248,113,113,0.6)', label: 'Conflict!' },
  merging: { bg: 'rgba(96,165,250,0.10)', border: 'rgba(96,165,250,0.5)', label: 'Merging' },
  done: { bg: 'rgba(16,185,129,0.15)', border: 'rgba(52,211,153,0.6)', label: 'Done' },
  'rate-limited': { bg: 'rgba(239,68,68,0.10)', border: 'rgba(248,113,113,0.5)', label: 'Rate Limited' },
};

// -- Mail messages shown during agent-communication step ----------------------

interface MailMessage {
  from: string;
  to: string;
  subject: string;
  color: string;
}

// -- Step definitions ---------------------------------------------------------

interface SwarmScenario {
  title: string;
  subtitle: string;
  command: string;
  agentStatuses: Record<string, AgentStatus>;
  /** Which agent pairs have active connection lines */
  connections: [string, string][];
  /** Messages flowing between agents */
  messages: MailMessage[];
  /** Files that are reserved (agent -> files) */
  reservations: Record<string, string[]>;
  /** Which files have conflicts */
  conflictFiles: string[];
  /** Overall swarm progress 0-100 */
  progress: number;
  /** Beads in the task queue (remaining) */
  queueBeads: { id: string; label: string; assignedTo: string | null }[];
}

const SCENARIOS: SwarmScenario[] = [
  {
    title: '1. Ready Work and Context',
    subtitle: 'Robot triage selects work, then CASS and CM recover bounded prior context',
    command: 'cm context "bd-001 API routes" --workspace . --json',
    agentStatuses: { 'claude-1': 'spawning', 'claude-2': 'spawning', 'codex-1': 'spawning', 'gemini-1': 'spawning', 'claude-3': 'spawning', 'codex-2': 'spawning' },
    connections: [],
    messages: [],
    reservations: {},
    conflictFiles: [],
    progress: 0,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: null },
      { id: 'bd-002', label: 'Auth flow', assignedTo: null },
      { id: 'bd-003', label: 'UI components', assignedTo: null },
      { id: 'bd-004', label: 'DB schema', assignedTo: null },
      { id: 'bd-005', label: 'Test suite', assignedTo: null },
      { id: 'bd-006', label: 'Type defs', assignedTo: null },
    ],
  },
  {
    title: '2. Agent Mail Registered',
    subtitle: 'Each agent registers identity, claims one Bead, and reserves its files',
    command: 'ensure_project(...) && register_agent(...)',
    agentStatuses: { 'claude-1': 'working', 'claude-2': 'working', 'codex-1': 'working', 'gemini-1': 'working', 'claude-3': 'working', 'codex-2': 'working' },
    connections: [],
    messages: [],
    reservations: {
      'claude-1': ['src/api/routes.ts', 'src/api/middleware.ts'],
      'claude-2': ['src/auth/oauth.ts', 'src/auth/session.ts'],
      'codex-1': ['src/components/App.tsx', 'src/components/Nav.tsx'],
      'gemini-1': ['src/db/schema.ts', 'src/db/migrations.ts'],
      'claude-3': ['tests/api.test.ts', 'tests/auth.test.ts'],
      'codex-2': ['docs/api.md', 'src/types/index.ts'],
    },
    conflictFiles: [],
    progress: 8,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: 'claude-1' },
      { id: 'bd-002', label: 'Auth flow', assignedTo: 'claude-2' },
      { id: 'bd-003', label: 'UI components', assignedTo: 'codex-1' },
      { id: 'bd-004', label: 'DB schema', assignedTo: 'gemini-1' },
      { id: 'bd-005', label: 'Test suite', assignedTo: 'claude-3' },
      { id: 'bd-006', label: 'Type defs', assignedTo: 'codex-2' },
    ],
  },
  {
    title: '3. Reservation Conflict Detected',
    subtitle: 'Claude-3 requests src/api/routes.ts while Claude-1 owns it exclusively',
    command: 'file_reservation_paths(... paths=["src/api/routes.ts"])',
    agentStatuses: { 'claude-1': 'working', 'claude-2': 'working', 'codex-1': 'working', 'gemini-1': 'working', 'claude-3': 'conflict', 'codex-2': 'working' },
    connections: [['claude-3', 'claude-1']],
    messages: [],
    reservations: {
      'claude-1': ['src/api/routes.ts', 'src/api/middleware.ts'],
      'claude-2': ['src/auth/oauth.ts', 'src/auth/session.ts'],
      'codex-1': ['src/components/App.tsx', 'src/components/Nav.tsx'],
      'gemini-1': ['src/db/schema.ts', 'src/db/migrations.ts'],
      'claude-3': ['tests/api.test.ts', 'tests/auth.test.ts'],
      'codex-2': ['docs/api.md', 'src/types/index.ts'],
    },
    conflictFiles: ['src/api/routes.ts'],
    progress: 25,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: 'claude-1' },
      { id: 'bd-002', label: 'Auth flow', assignedTo: 'claude-2' },
      { id: 'bd-003', label: 'UI components', assignedTo: 'codex-1' },
      { id: 'bd-004', label: 'DB schema', assignedTo: 'gemini-1' },
      { id: 'bd-005', label: 'Test suite', assignedTo: 'claude-3' },
      { id: 'bd-006', label: 'Type defs', assignedTo: 'codex-2' },
    ],
  },
  {
    title: '4. Agent Communication',
    subtitle: 'Agents use Agent Mail to coordinate dependencies and hand off work',
    command: 'send_message(... thread_id="bd-001")',
    agentStatuses: { 'claude-1': 'sending', 'claude-2': 'working', 'codex-1': 'working', 'gemini-1': 'sending', 'claude-3': 'working', 'codex-2': 'working' },
    connections: [['claude-1', 'codex-1'], ['gemini-1', 'claude-3'], ['claude-2', 'claude-1']],
    messages: [
      { from: 'claude-1', to: 'codex-1', subject: 'API endpoints ready', color: '#f97316' },
      { from: 'gemini-1', to: 'claude-3', subject: 'DB schema finalized', color: '#3b82f6' },
      { from: 'claude-2', to: 'claude-1', subject: 'Auth middleware done', color: '#fb923c' },
    ],
    reservations: {
      'claude-1': ['src/api/routes.ts', 'src/api/middleware.ts'],
      'claude-2': ['src/auth/oauth.ts', 'src/auth/session.ts'],
      'codex-1': ['src/components/App.tsx', 'src/components/Nav.tsx'],
      'gemini-1': ['src/db/schema.ts', 'src/db/migrations.ts'],
      'claude-3': ['tests/api.test.ts', 'tests/auth.test.ts'],
      'codex-2': ['docs/api.md', 'src/types/index.ts'],
    },
    conflictFiles: [],
    progress: 50,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: 'claude-1' },
      { id: 'bd-002', label: 'Auth flow', assignedTo: 'claude-2' },
      { id: 'bd-003', label: 'UI components', assignedTo: 'codex-1' },
      { id: 'bd-004', label: 'DB schema', assignedTo: 'gemini-1' },
      { id: 'bd-005', label: 'Test suite', assignedTo: 'claude-3' },
      { id: 'bd-006', label: 'Type defs', assignedTo: 'codex-2' },
    ],
  },
  {
    title: '5. Verification Gates',
    subtitle: 'Heavy Rust checks use RCH and changed files are scanned with UBS',
    command: 'rch exec -- cargo test && ubs <changed-files>',
    agentStatuses: { 'claude-1': 'working', 'claude-2': 'done', 'codex-1': 'working', 'gemini-1': 'done', 'claude-3': 'working', 'codex-2': 'working' },
    connections: [],
    messages: [],
    reservations: {
      'claude-1': ['src/api/routes.ts', 'src/api/middleware.ts'],
      'codex-1': ['src/components/App.tsx', 'src/components/Nav.tsx'],
      'claude-3': ['tests/api.test.ts', 'tests/auth.test.ts'],
      'codex-2': ['docs/api.md', 'src/types/index.ts'],
    },
    conflictFiles: [],
    progress: 65,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: 'claude-1' },
      { id: 'bd-002', label: 'Auth flow', assignedTo: null },
      { id: 'bd-003', label: 'UI components', assignedTo: 'codex-1' },
      { id: 'bd-004', label: 'DB schema', assignedTo: null },
      { id: 'bd-005', label: 'Test suite', assignedTo: 'claude-3' },
      { id: 'bd-006', label: 'Type defs', assignedTo: 'codex-2' },
    ],
  },
  {
    title: '6. Beads Closed and Synced',
    subtitle: 'Finished Beads are closed, exported, and committed with the code',
    command: 'br close bd-001 --reason "Done" && br sync --flush-only',
    agentStatuses: { 'claude-1': 'merging', 'claude-2': 'done', 'codex-1': 'merging', 'gemini-1': 'done', 'claude-3': 'merging', 'codex-2': 'merging' },
    connections: [['claude-1', 'codex-1'], ['claude-3', 'codex-2'], ['claude-1', 'claude-3']],
    messages: [],
    reservations: {},
    conflictFiles: [],
    progress: 85,
    queueBeads: [
      { id: 'bd-001', label: 'API routes', assignedTo: null },
      { id: 'bd-002', label: 'Auth flow', assignedTo: null },
      { id: 'bd-003', label: 'UI components', assignedTo: null },
      { id: 'bd-004', label: 'DB schema', assignedTo: null },
      { id: 'bd-005', label: 'Test suite', assignedTo: null },
      { id: 'bd-006', label: 'Type defs', assignedTo: null },
    ],
  },
  {
    title: '7. Swarm Complete',
    subtitle: 'Reservations are released and the final handoff is posted in-thread',
    command: 'release_file_reservations(...) && send_message(...)',
    agentStatuses: { 'claude-1': 'done', 'claude-2': 'done', 'codex-1': 'done', 'gemini-1': 'done', 'claude-3': 'done', 'codex-2': 'done' },
    connections: [],
    messages: [],
    reservations: {},
    conflictFiles: [],
    progress: 100,
    queueBeads: [],
  },
];

// -- Hex layout helpers -------------------------------------------------------

/** Size of each hexagonal cell */
const HEX_R = 42;
const HEX_W = HEX_R * 2;
const HEX_H = Math.sqrt(3) * HEX_R;

function hexCenter(col: number, row: number, offsetX: number, offsetY: number) {
  const x = offsetX + col * HEX_W * 0.78;
  const y = offsetY + row * (HEX_H + 8) + (col % 2 === 1 ? (HEX_H + 8) / 2 : 0);
  return { x, y };
}

function hexPoints(cx: number, cy: number, r: number): string {
  const pts: string[] = [];
  for (let i = 0; i < 6; i++) {
    const angle = (Math.PI / 3) * i - Math.PI / 6;
    pts.push(`${cx + r * Math.cos(angle)},${cy + r * Math.sin(angle)}`);
  }
  return pts.join(' ');
}

// -- Sub-components -----------------------------------------------------------

function HexAgentNode({
  agent,
  status,
  cx,
  cy,
  hasConflict,
}: {
  agent: HexAgent;
  status: AgentStatus;
  cx: number;
  cy: number;
  hasConflict: boolean;
}) {
  const palette = STATUS_PALETTE[status];
  const isActive = status === 'working' || status === 'sending' || status === 'spawning' || status === 'merging';

  return (
    <motion.g
      initial={{ opacity: 0, scale: 0.5 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={SPRING_CFG}
    >
      {/* Outer pulse for active agents */}
      {isActive && (
        <motion.polygon
          points={hexPoints(cx, cy, HEX_R + 5)}
          fill="none"
          stroke={agent.color}
          strokeWidth={1.5}
          animate={{ strokeOpacity: [0.1, 0.5, 0.1] }}
          transition={{ duration: 2, repeat: Infinity }}
        />
      )}

      {/* Conflict flash */}
      {hasConflict && (
        <motion.polygon
          points={hexPoints(cx, cy, HEX_R + 7)}
          fill="none"
          stroke="#ef4444"
          strokeWidth={2}
          animate={{ strokeOpacity: [0.2, 0.8, 0.2], scale: [1, 1.03, 1] }}
          transition={{ duration: 0.8, repeat: Infinity }}
        />
      )}

      {/* Main hex fill */}
      <polygon
        points={hexPoints(cx, cy, HEX_R)}
        fill={palette.bg}
        stroke={palette.border}
        strokeWidth={1.2}
      />

      {/* Agent name */}
      <text
        x={cx}
        y={cy - 10}
        textAnchor="middle"
        fill={agent.color}
        fontSize="10"
        fontWeight="700"
        fontFamily="system-ui"
      >
        {agent.name}
      </text>

      {/* Provider label */}
      <text
        x={cx}
        y={cy + 2}
        textAnchor="middle"
        fill="rgba(255,255,255,0.35)"
        fontSize="7"
        fontFamily="system-ui"
      >
        {agent.provider}
      </text>

      {/* Task */}
      <text
        x={cx}
        y={cy + 14}
        textAnchor="middle"
        fill="rgba(255,255,255,0.55)"
        fontSize="8"
        fontWeight="500"
        fontFamily="system-ui"
      >
        {agent.task}
      </text>

      {/* Status indicator dot */}
      <circle
        cx={cx + HEX_R - 18}
        cy={cy - HEX_R + 18}
        r={5}
        fill={status === 'done' ? '#10b981' : status === 'conflict' || status === 'rate-limited' ? '#ef4444' : agent.color}
        opacity={0.9}
      />

      {/* Done checkmark */}
      {status === 'done' && (
        <motion.text
          x={cx + HEX_R - 18}
          y={cy - HEX_R + 21.5}
          textAnchor="middle"
          fill="white"
          fontSize="8"
          fontWeight="bold"
          fontFamily="system-ui"
          initial={{ opacity: 0, scale: 0 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={SPRING_CFG}
        >
          &#x2713;
        </motion.text>
      )}

      {/* Rate-limit X */}
      {status === 'rate-limited' && (
        <motion.text
          x={cx + HEX_R - 18}
          y={cy - HEX_R + 21.5}
          textAnchor="middle"
          fill="white"
          fontSize="8"
          fontWeight="bold"
          fontFamily="system-ui"
          animate={{ opacity: [1, 0.4, 1] }}
          transition={{ duration: 0.6, repeat: Infinity }}
        >
          !
        </motion.text>
      )}

      {/* Typing indicator for working agents */}
      {(status === 'working' || status === 'sending' || status === 'spawning') && (
        <TypingDotsRow cx={cx} cy={cy + 26} color={agent.color} />
      )}
    </motion.g>
  );
}

function TypingDotsRow({ cx, cy, color }: { cx: number; cy: number; color: string }) {
  return (
    <g>
      {[0, 1, 2].map((i) => (
        <motion.circle
          key={i}
          cx={cx - 6 + i * 6}
          cy={cy}
          r={1.8}
          fill={color}
          animate={{ opacity: [0.25, 0.9, 0.25] }}
          transition={{ duration: 0.7, repeat: Infinity, delay: i * 0.15 }}
        />
      ))}
    </g>
  );
}

function ConnectionLine({
  x1,
  y1,
  x2,
  y2,
  color,
}: {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  color: string;
}) {
  return (
    <motion.line
      x1={x1}
      y1={y1}
      x2={x2}
      y2={y2}
      stroke={color}
      strokeWidth={1.2}
      strokeDasharray="6 3"
      initial={{ pathLength: 0, opacity: 0 }}
      animate={{ pathLength: 1, opacity: 0.5 }}
      transition={{ ...SPRING_CFG, duration: 0.6 }}
    />
  );
}

function MessageDot({
  x1,
  y1,
  x2,
  y2,
  color,
  delayMs,
}: {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  color: string;
  delayMs: number;
}) {
  return (
    <motion.circle
      r={4}
      fill={color}
      initial={{ cx: x1, cy: y1, opacity: 0.9 }}
      animate={{
        cx: [x1, x2],
        cy: [y1, y2],
        opacity: [0.9, 0.9, 0.4],
        scale: [0.8, 1.2, 0.6],
      }}
      transition={{
        duration: 1.8,
        repeat: Infinity,
        repeatDelay: 0.8,
        delay: delayMs / 1000,
        type: 'spring',
        stiffness: 60,
        damping: 14,
      }}
    />
  );
}

// -- Panels below SVG ---------------------------------------------------------

function TaskQueuePanel({ beads }: { beads: SwarmScenario['queueBeads'] }) {
  if (beads.length === 0) {
    return (
      <div className="text-center text-xs text-white/30 py-2">Queue empty - all tasks complete</div>
    );
  }
  return (
    <div className="flex flex-wrap gap-1.5">
      {beads.map((b) => {
        const assigned = b.assignedTo !== null;
        const agent = assigned ? HEX_AGENTS.find((a) => a.id === b.assignedTo) : null;
        return (
          <motion.div
            key={b.id}
            layout
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING_CFG}
            className="flex items-center gap-1 rounded-md px-2 py-0.5 text-[10px] border"
            style={{
              borderColor: agent ? agent.color + '40' : 'rgba(255,255,255,0.08)',
              backgroundColor: agent ? agent.color + '10' : 'rgba(255,255,255,0.02)',
              color: agent ? agent.color : 'rgba(255,255,255,0.4)',
            }}
          >
            <span className="font-mono opacity-60">{b.id}</span>
            <span>{b.label}</span>
            {agent && (
              <span className="ml-0.5 font-semibold" style={{ color: agent.color }}>
                {'\u2192'} {agent.name}
              </span>
            )}
          </motion.div>
        );
      })}
    </div>
  );
}

function FileReservationPanel({
  reservations,
  conflictFiles,
}: {
  reservations: Record<string, string[]>;
  conflictFiles: string[];
}) {
  const entries = Object.entries(reservations);
  if (entries.length === 0) {
    return (
      <div className="text-center text-xs text-white/30 py-2">No active file reservations</div>
    );
  }
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-1">
      {entries.map(([agentId, files]) => {
        const agent = HEX_AGENTS.find((a) => a.id === agentId);
        if (!agent) return null;
        return files.map((file) => {
          const isConflict = conflictFiles.includes(file);
          return (
            <motion.div
              key={`${agentId}-${file}`}
              layout
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={SPRING_CFG}
              className="flex items-center gap-1.5 rounded px-2 py-0.5 text-[10px] font-mono border"
              style={{
                borderColor: isConflict ? 'rgba(248,113,113,0.5)' : agent.color + '30',
                backgroundColor: isConflict ? 'rgba(239,68,68,0.08)' : agent.color + '08',
              }}
            >
              {isConflict && (
                <span className="text-red-400 font-bold text-[10px]">!!</span>
              )}
              <span style={{ color: agent.color }} className="shrink-0 font-semibold">
                {agent.name}
              </span>
              <span className="text-white/40 truncate">{file}</span>
            </motion.div>
          );
        });
      })}
    </div>
  );
}

function MailMessagePanel({ messages }: { messages: MailMessage[] }) {
  if (messages.length === 0) {
    return (
      <div className="text-center text-xs text-white/30 py-2">No active messages</div>
    );
  }
  return (
    <div className="space-y-1">
      {messages.map((msg, i) => (
        <motion.div
          key={`${msg.from}-${msg.to}-${i}`}
          initial={{ opacity: 0, x: -12 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ ...SPRING_CFG, delay: i * 0.1 }}
          className="flex items-center gap-2 rounded-lg px-3 py-1.5 border text-xs"
          style={{
            borderColor: msg.color + '30',
            backgroundColor: msg.color + '08',
          }}
        >
          <span className="font-semibold" style={{ color: msg.color }}>{msg.from}</span>
          <span className="text-white/30">{'\u2192'}</span>
          <span className="font-semibold text-white/70">{msg.to}</span>
          <span className="text-white/40 ml-auto truncate max-w-[140px]">&ldquo;{msg.subject}&rdquo;</span>
        </motion.div>
      ))}
    </div>
  );
}

function ProgressBar({ progress }: { progress: number }) {
  return (
    <div className="relative h-3 rounded-full overflow-hidden bg-white/[0.04] border border-white/[0.06]">
      <motion.div
        className="absolute inset-y-0 left-0 rounded-full"
        style={{
          background: progress === 100
            ? 'linear-gradient(90deg, #10b981, #34d399)'
            : 'linear-gradient(90deg, #8b5cf6, #a78bfa)',
        }}
        initial={{ width: '0%' }}
        animate={{ width: `${progress}%` }}
        transition={{ type: 'spring', stiffness: 80, damping: 20 }}
      />
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-[9px] font-bold text-white/70 drop-shadow-sm">
          {progress}%
        </span>
      </div>
    </div>
  );
}

// -- Active tab selector for bottom panels ------------------------------------

type PanelTab = 'queue' | 'files' | 'mail';

function PanelTabBar({
  active,
  onSelect,
  messageCount,
}: {
  active: PanelTab;
  onSelect: (t: PanelTab) => void;
  messageCount: number;
}) {
  const tabs: { key: PanelTab; label: string; badge?: number }[] = [
    { key: 'queue', label: 'Task Queue' },
    { key: 'files', label: 'File Map' },
    { key: 'mail', label: 'Agent Mail', badge: messageCount > 0 ? messageCount : undefined },
  ];
  return (
    <div className="flex gap-1 border-b border-white/[0.06] px-4">
      {tabs.map((t) => (
        <button
          key={t.key}
          type="button"
          onClick={() => onSelect(t.key)}
          className={`relative px-3 py-1.5 text-[10px] font-medium transition-colors ${
            active === t.key ? 'text-white' : 'text-white/40 hover:text-white/60'
          }`}
        >
          {t.label}
          {t.badge !== undefined && (
            <span className="ml-1 inline-flex h-3.5 min-w-[14px] items-center justify-center rounded-full bg-amber-500/20 px-1 text-[8px] font-bold text-amber-400">
              {t.badge}
            </span>
          )}
          {active === t.key && (
            <motion.div
              layoutId="swarm-panel-tab-indicator"
              className="absolute inset-x-0 -bottom-px h-px bg-primary"
              transition={SPRING_CFG}
            />
          )}
        </button>
      ))}
    </div>
  );
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

function InteractiveSwarmOrchestrator() {
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [activePanel, setActivePanel] = useState<PanelTab>('queue');
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const totalSteps = SCENARIOS.length;
  const scenario = SCENARIOS[step];

  // Auto-advance when playing
  const advanceStep = useCallback(() => {
    setStep((s) => {
      const next = s + 1;
      if (next >= SCENARIOS.length) {
        return s; // stay at last step, effect below will stop playing
      }
      return next;
    });
  }, []);

  // Stop playing when at last step
  useEffect(() => {
    if (playing && step >= SCENARIOS.length - 1) {
      setTimeout(() => setPlaying(false), 0);
    }
  }, [playing, step]);

  useEffect(() => {
    if (playing) {
      timerRef.current = setTimeout(() => {
        advanceStep();
      }, 3200);
    }
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [playing, step, advanceStep]);

  // Auto-select relevant panel when step changes
  useEffect(() => {
    const s = SCENARIOS[step];
    if (s.messages.length > 0) {
      setTimeout(() => setActivePanel('mail'), 0);
    } else if (s.conflictFiles.length > 0 || Object.keys(s.reservations).length > 0) {
      setTimeout(() => setActivePanel('files'), 0);
    } else {
      setTimeout(() => setActivePanel('queue'), 0);
    }
  }, [step]);

  const goNext = () => {
    setPlaying(false);
    setStep((s) => Math.min(s + 1, totalSteps - 1));
  };

  const goPrev = () => {
    setPlaying(false);
    setStep((s) => Math.max(s - 1, 0));
  };

  const togglePlay = () => {
    if (step >= totalSteps - 1 && !playing) {
      setStep(0);
      setPlaying(true);
    } else {
      setPlaying((p) => !p);
    }
  };

  // SVG layout constants
  const svgW = 560;
  const svgH = 260;
  const gridOffsetX = 70;
  const gridOffsetY = 56;

  // Build a lookup from agent id -> hex center
  const agentCenters: Record<string, { x: number; y: number }> = {};
  for (const agent of HEX_AGENTS) {
    agentCenters[agent.id] = hexCenter(agent.col, agent.row, gridOffsetX, gridOffsetY);
  }

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-primary/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-violet-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-0 w-24 h-24 bg-emerald-500/5 rounded-full blur-2xl pointer-events-none" />

      {/* Header: scenario title + command */}
      <div className="relative px-5 pt-5 pb-2">
        <AnimatePresence mode="wait">
          <motion.div
            key={step}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING_CFG}
            className="space-y-1.5"
          >
            <div className="flex items-center gap-2">
              <span className="text-sm font-bold text-white/90">{scenario.title}</span>
              <span className="text-[10px] px-2 py-0.5 rounded-full border border-white/[0.08] bg-white/[0.03] text-white/40">
                Step {step + 1}/{totalSteps}
              </span>
            </div>
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-black/40 border border-white/[0.08] font-mono text-xs">
              <span className="text-emerald-400 select-none">$</span>
              <span className="text-white/60">{scenario.command}</span>
            </div>
            <p className="text-xs text-white/40 leading-relaxed">{scenario.subtitle}</p>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* SVG Hex Grid Visualization */}
      <div className="relative px-2 pb-1">
        <svg
          viewBox={`0 0 ${svgW} ${svgH}`}
          className="w-full"
          role="img"
          aria-label="Swarm command center hex grid showing agent coordination"
        >
          <defs>
            <radialGradient id="swarm-center-glow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="rgba(139,92,246,0.15)" />
              <stop offset="100%" stopColor="rgba(139,92,246,0)" />
            </radialGradient>
            {HEX_AGENTS.map((a) => (
              <radialGradient key={`ag-${a.id}`} id={`ag-${a.id}`} cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor={a.color} stopOpacity="0.15" />
                <stop offset="100%" stopColor={a.color} stopOpacity="0" />
              </radialGradient>
            ))}
          </defs>

          {/* Subtle center glow behind grid */}
          <ellipse cx={svgW / 2} cy={svgH / 2} rx={200} ry={100} fill="url(#swarm-center-glow)" />

          {/* Connection lines between communicating agents */}
          <AnimatePresence>
            {scenario.connections.map(([fromId, toId]) => {
              const from = agentCenters[fromId];
              const to = agentCenters[toId];
              if (!from || !to) return null;
              const fromAgent = HEX_AGENTS.find((a) => a.id === fromId);
              return (
                <ConnectionLine
                  key={`conn-${fromId}-${toId}-${step}`}
                  x1={from.x}
                  y1={from.y}
                  x2={to.x}
                  y2={to.y}
                  color={fromAgent?.color ?? '#888'}
                />
              );
            })}
          </AnimatePresence>

          {/* Animated message dots flying between agents */}
          <AnimatePresence>
            {scenario.messages.map((msg, mi) => {
              const fromAgent = HEX_AGENTS.find((a) => a.id === msg.from);
              const toAgent = HEX_AGENTS.find((a) => a.id === msg.to);
              if (!fromAgent || !toAgent) return null;
              const fc = agentCenters[fromAgent.id];
              const tc = agentCenters[toAgent.id];
              return (
                <MessageDot
                  key={`mdot-${msg.from}-${msg.to}-${step}`}
                  x1={fc.x}
                  y1={fc.y}
                  x2={tc.x}
                  y2={tc.y}
                  color={msg.color}
                  delayMs={mi * 400}
                />
              );
            })}
          </AnimatePresence>

          {/* Hex agent nodes */}
          {HEX_AGENTS.map((agent) => {
            const center = agentCenters[agent.id];
            const status = scenario.agentStatuses[agent.id] ?? 'idle';
            const hasConflict = status === 'conflict';
            return (
              <HexAgentNode
                key={agent.id}
                agent={agent}
                status={status as AgentStatus}
                cx={center.x}
                cy={center.y}
                hasConflict={hasConflict}
              />
            );
          })}
        </svg>
      </div>

      {/* Progress bar */}
      <div className="relative px-5 pb-2">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-[10px] font-medium text-white/40">Swarm Progress</span>
          <span className="text-[10px] text-white/25 ml-auto">
            {HEX_AGENTS.filter((a) => scenario.agentStatuses[a.id] === 'done').length}/{HEX_AGENTS.length} agents done
          </span>
        </div>
        <ProgressBar progress={scenario.progress} />
      </div>

      {/* Status legend */}
      <div className="relative flex flex-wrap gap-x-3 gap-y-1 px-5 py-2">
        {HEX_AGENTS.map((agent) => {
          const status = scenario.agentStatuses[agent.id] ?? 'idle';
          const palette = STATUS_PALETTE[status as AgentStatus];
          return (
            <div key={agent.id} className="flex items-center gap-1 text-[9px]">
              <div
                className="h-2 w-2 rounded-full"
                style={{ backgroundColor: agent.color, opacity: 0.8 }}
              />
              <span className="text-white/50">{agent.name}:</span>
              <span
                className="font-medium"
                style={{ color: palette.border }}
              >
                {palette.label}
              </span>
            </div>
          );
        })}
      </div>

      {/* Tabbed bottom panels */}
      <div className="relative">
        <PanelTabBar
          active={activePanel}
          onSelect={setActivePanel}
          messageCount={scenario.messages.length}
        />
        <div className="px-4 py-2.5 min-h-[60px]">
          <AnimatePresence mode="wait">
            <motion.div
              key={`${activePanel}-${step}`}
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={SPRING_CFG}
            >
              {activePanel === 'queue' && <TaskQueuePanel beads={scenario.queueBeads} />}
              {activePanel === 'files' && (
                <FileReservationPanel
                  reservations={scenario.reservations}
                  conflictFiles={scenario.conflictFiles}
                />
              )}
              {activePanel === 'mail' && <MailMessagePanel messages={scenario.messages} />}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* Playback controls */}
      <div className="relative flex items-center justify-center gap-4 px-6 pb-3 pt-1">
        <button
          type="button"
          onClick={goPrev}
          disabled={step === 0}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Previous step"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        <button
          type="button"
          onClick={togglePlay}
          className="flex h-10 w-10 items-center justify-center rounded-full border border-primary/30 bg-primary/10 text-primary transition hover:bg-primary/20"
          aria-label={playing ? 'Pause' : 'Play'}
        >
          {playing ? (
            <Pause className="h-4 w-4" />
          ) : (
            <Play className="h-4 w-4" />
          )}
        </button>

        <button
          type="button"
          onClick={goNext}
          disabled={step >= totalSteps - 1}
          className="flex h-8 w-8 items-center justify-center rounded-full border border-white/[0.08] bg-white/[0.02] text-white/60 transition hover:bg-white/[0.06] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
          aria-label="Next step"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      {/* Step indicator dots */}
      <div className="relative flex items-center justify-center gap-2 pb-5">
        {SCENARIOS.map((s, i) => (
          <button
            key={i}
            type="button"
            onClick={() => {
              setPlaying(false);
              setStep(i);
            }}
            className={`h-2 rounded-full transition-[width,background-color] duration-300 ${
              i === step
                ? 'w-6 bg-primary'
                : i < step
                  ? 'w-2 bg-white/30'
                  : 'w-2 bg-white/10'
            }`}
            aria-label={`Go to step ${i + 1}: ${s.title}`}
          />
        ))}
      </div>
    </div>
  );
}
