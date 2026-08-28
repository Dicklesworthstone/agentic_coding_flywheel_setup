'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  RefreshCw,
  Terminal,
  Zap,
  FolderSync,
  Bot,
  Shield,
  Clock,
  Settings,
  CheckCircle,
  Play,
  CheckCircle2,
  XCircle,
  Loader2,
  RotateCcw,
  FolderGit2,
  GitBranch,
  GitMerge,
  AlertTriangle,
  FileText,
  Sparkles,
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

export function RuLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master multi-repo synchronization and AI-driven commit automation with RU.
      </GoalBanner>

      {/* Section 1: What Is RU */}
      <Section title="What Is RU?" icon={<RefreshCw className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>RU (Repo Updater)</Highlight> is your command center for managing
          dozens of GitHub repositories. One command syncs everything. AI automation
          commits your dirty repos intelligently.
        </Paragraph>
        <Paragraph>
          Without RU, you&apos;d manually cd into each repo and run git pull. With 20+ repos,
          that&apos;s tedious and error-prone. RU handles it all with parallel workers.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<FolderSync className="h-5 w-5" />}
              title="Parallel Sync"
              description="Work-stealing queue syncs repos 4x faster"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Bot className="h-5 w-5" />}
              title="Agent Sweep"
              description="AI-driven commit automation"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="Resume Support"
              description="Pick up where you left off"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Git Plumbing"
              description="No string parsing, locale-safe"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-8">
          <InteractiveRepoSync />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Start with these core commands. They cover 90% of daily usage.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'ru sync', description: 'Clone missing + pull all repos' },
            { command: 'ru sync -j4', description: 'Parallel sync with 4 workers' },
            { command: 'ru sync --autostash', description: 'Stash local changes before pull' },
            { command: 'ru status', description: 'Check all repo states' },
            { command: 'ru status --fetch', description: 'Fetch + show ahead/behind' },
            { command: 'ru list --paths', description: 'Show all repo paths' },
            { command: 'ru doctor', description: 'Health check RU installation' },
          ]}
        />

        <TipBox variant="tip">
          Use <code>ru sync --resume</code> if sync was interrupted. RU remembers progress!
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Agent Sweep */}
      <Section title="Agent Sweep: AI Automation" icon={<Bot className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Agent Sweep is RU&apos;s killer feature. It uses Claude Code to automatically
          commit dirty repos with intelligent commit messages.
        </Paragraph>

        <CodeBlock
          code={`# Phase 1: Understand
# Agent reads AGENTS.md, explores codebase, learns conventions

# Phase 2: Plan
# Agent produces JSON commit plan (files, messages)
# RU validates: no secrets, file size limits, schema check

# Phase 3: Execute
# RU executes validated plan with deterministic git commands`}
          filename="Three-Phase Workflow"
        />

        <CommandList
          commands={[
            { command: 'ru agent-sweep --dry-run', description: 'Preview what would happen' },
            { command: 'ru agent-sweep --parallel 4', description: 'Process 4 repos simultaneously' },
            { command: 'ru agent-sweep --with-release', description: 'Include version bumps and tags' },
            { command: 'ru agent-sweep --resume', description: 'Continue interrupted sweep' },
          ]}
        />

        <TipBox variant="warning">
          Always run <code>--dry-run</code> first to preview the commit plan!
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: AI Code Review */}
      <Section title="AI Code Review" icon={<CheckCircle className="h-5 w-5" />} delay={0.23}>
        <Paragraph>
          RU can orchestrate AI-assisted code reviews across your repos using{' '}
          <Highlight>ru review</Highlight>. The review system integrates with ntm&apos;s
          robot mode to spawn Claude agents for thorough analysis.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'ru review', description: 'Review uncommitted changes in current repo' },
            { command: 'ru review --plan', description: 'Create detailed review plan first' },
            { command: 'ru review --all', description: 'Review all dirty repos' },
            { command: 'ru review --scope=security', description: 'Focus on security issues' },
          ]}
        />

        <TipBox variant="tip">
          Combine with <code>ubs</code> for comprehensive coverage: run <code>ubs .</code> for
          static analysis, then <code>ru review</code> for semantic understanding.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Configuration */}
      <Section title="Configuration" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          RU follows XDG conventions. Configure once, sync everywhere.
        </Paragraph>

        <CodeBlock
          code={`# Base directory for repositories
PROJECTS_DIR=/data/projects

# Parallel workers (1-8)
PARALLEL=4

# Update strategy: ff-only | rebase | merge
UPDATE_STRATEGY=ff-only

# Auto-stash local changes before pull
AUTOSTASH=false`}
          filename="~/.config/ru/config"
        />

        <CodeBlock
          code={`# Shorthand
Dicklesworthstone/ntm
Dicklesworthstone/beads_viewer

# With branch
owner/repo@develop

# Custom local name
owner/repo as my-fork

# SSH URL
git@github.com:owner/repo.git as myrepo`}
          filename="~/.config/ru/repos.d/public.txt"
        />

        <TipBox variant="tip">
          Run <code>ru init --example</code> to create starter config files.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Integration */}
      <Section title="Tool Integration" icon={<Zap className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          RU becomes more powerful when combined with other flywheel tools.
        </Paragraph>

        <div className="space-y-4">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.35 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RU + NTM</h4>
            <p className="text-muted-foreground text-sm">
              Agent Sweep uses NTM robot mode to spawn Claude sessions. NTM manages
              the tmux panes, RU orchestrates the workflow.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.4 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RU + BV</h4>
            <p className="text-muted-foreground text-sm">
              After syncing repos, use BV to check beads across all projects.
              Combine <code className="text-primary">ru status</code> with{' '}
              <code className="text-primary">bv --robot-triage</code>.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.45 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">RU + Mail</h4>
            <p className="text-muted-foreground text-sm">
              Agents can claim repos via Mail to prevent conflicts during
              parallel agent-sweep runs.
            </p>
          </motion.div>
        </div>
      </Section>

      <Divider />

      {/* Section 7: Exit Codes */}
      <Section title="Exit Codes" icon={<Play className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          RU uses meaningful exit codes for scripting and automation.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <code className="text-emerald-400 font-mono">0</code>
            <span className="text-white/80 ml-2">Success</span>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <code className="text-amber-400 font-mono">1</code>
            <span className="text-white/80 ml-2">Partial failure (some repos failed)</span>
          </div>
          <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/30">
            <code className="text-red-400 font-mono">2</code>
            <span className="text-white/80 ml-2">Conflicts (manual resolution needed)</span>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <code className="text-violet-400 font-mono">5</code>
            <span className="text-white/80 ml-2">Interrupted (use --resume)</span>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// InteractiveRepoSync - Multi-repo sync operations center with 6 scenarios
// ---------------------------------------------------------------------------

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };
const SPRING_SNAPPY = { type: 'spring' as const, stiffness: 400, damping: 35 };

type RepoSyncStatus = 'pending' | 'cloning' | 'pulling' | 'dirty' | 'ai-commit' | 'conflict' | 'synced' | 'error';

interface SyncRepo {
  name: string;
  owner: string;
  status: RepoSyncStatus;
  progress: number;
  branch: string;
  ahead: number;
  behind: number;
  changedFiles: number;
  commitMsg: string;
  lastAction: string;
}

type ScenarioId = 'parallel-sync' | 'initial-clone' | 'dirty-detect' | 'ai-commit' | 'conflict-resolve' | 'full-sweep';

interface Scenario {
  id: ScenarioId;
  label: string;
  icon: React.ReactNode;
  description: string;
  command: string;
}

const SCENARIOS: Scenario[] = [
  { id: 'parallel-sync', label: 'Parallel Sync', icon: <FolderSync className="h-3.5 w-3.5" />, description: '10 repos synced with 4 workers', command: 'ru sync -j4' },
  { id: 'initial-clone', label: 'Initial Clone', icon: <FolderGit2 className="h-3.5 w-3.5" />, description: 'Clone missing repos from manifest', command: 'ru sync --clone' },
  { id: 'dirty-detect', label: 'Dirty Detection', icon: <AlertTriangle className="h-3.5 w-3.5" />, description: 'Identify repos with uncommitted changes', command: 'ru status --fetch' },
  { id: 'ai-commit', label: 'AI Commit', icon: <Sparkles className="h-3.5 w-3.5" />, description: 'AI analyzes diffs and generates commits', command: 'ru agent-sweep --dry-run' },
  { id: 'conflict-resolve', label: 'Conflict Resolution', icon: <GitMerge className="h-3.5 w-3.5" />, description: 'Detect and report merge conflicts', command: 'ru sync --autostash' },
  { id: 'full-sweep', label: 'Full Sweep', icon: <Bot className="h-3.5 w-3.5" />, description: 'Agent sweep + parallel commit + push', command: 'ru agent-sweep --parallel 4' },
];

const ALL_REPOS: SyncRepo[] = [
  { name: 'ntm', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 3, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'beads_rust', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 1, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'cass', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'develop', ahead: 2, behind: 0, changedFiles: 4, commitMsg: '', lastAction: '' },
  { name: 'slb', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 5, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'dcg', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 1, behind: 2, changedFiles: 2, commitMsg: '', lastAction: '' },
  { name: 'ubs', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 0, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'ru', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 7, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'caam', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 0, changedFiles: 1, commitMsg: '', lastAction: '' },
  { name: 'flywheel', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'main', ahead: 0, behind: 4, changedFiles: 0, commitMsg: '', lastAction: '' },
  { name: 'bv', owner: 'Dicklesworthstone', status: 'pending', progress: 0, branch: 'feat/ui', ahead: 3, behind: 1, changedFiles: 6, commitMsg: '', lastAction: '' },
];

const AI_COMMIT_MESSAGES = [
  'fix(parser): handle edge case in nested TOML arrays',
  'refactor(core): extract validation into shared module',
  'feat(api): add batch endpoint for parallel queries',
  'chore(deps): bump framer-motion to v12.1.0',
  'fix(ui): correct z-index stacking in modal overlay',
  'docs(readme): update CLI usage examples',
];

function InteractiveRepoSync() {
  const [activeScenario, setActiveScenario] = useState<ScenarioId>('parallel-sync');
  const [repos, setRepos] = useState<SyncRepo[]>(() => ALL_REPOS.map((r) => ({ ...r })));
  const [isRunning, setIsRunning] = useState(false);
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const [aiTyping, setAiTyping] = useState('');
  const [aiTargetRepo, setAiTargetRepo] = useState('');
  const [completedScenario, setCompletedScenario] = useState(false);
  const [workerSlots, setWorkerSlots] = useState<(string | null)[]>([null, null, null, null]);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);

  const clearTimers = useCallback(() => {
    timersRef.current.forEach((t) => clearTimeout(t));
    timersRef.current = [];
  }, []);

  const addTimer = useCallback((fn: () => void, ms: number) => {
    const id = setTimeout(fn, ms);
    timersRef.current.push(id);
    return id;
  }, []);

  const addTerminalLine = useCallback((line: string) => {
    setTerminalLines((prev) => [...prev.slice(-14), line]);
  }, []);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [terminalLines]);

  const resetAll = useCallback(() => {
    clearTimers();
    setRepos(ALL_REPOS.map((r) => ({ ...r })));
    setTerminalLines([]);
    setAiTyping('');
    setAiTargetRepo('');
    setIsRunning(false);
    setCompletedScenario(false);
    setWorkerSlots([null, null, null, null]);
  }, [clearTimers]);

  // ---- Update a single repo in state ----
  const updateRepo = useCallback((name: string, updates: Partial<SyncRepo>) => {
    setRepos((prev) => prev.map((r) => (r.name === name ? { ...r, ...updates } : r)));
  }, []);

  // ---- Scenario: Parallel Sync ----
  const runParallelSync = useCallback(() => {
    const order = ['ntm', 'beads_rust', 'slb', 'ru', 'cass', 'dcg', 'ubs', 'flywheel', 'caam', 'bv'];
    const workerQueue = [...order];
    const delay = 300;
    const activeSlots: (string | null)[] = [null, null, null, null];
    const finishTimes: Record<string, number> = {};

    // Assign duration pseudo-randomly based on name length
    order.forEach((name) => {
      finishTimes[name] = 1200 + (name.length * 200);
    });

    // Start initial batch
    for (let s = 0; s < 4 && workerQueue.length > 0; s++) {
      const repo = workerQueue.shift()!;
      activeSlots[s] = repo;
      const staggeredDelay = delay + s * 120;
      addTimer(() => {
        updateRepo(repo, { status: 'pulling', progress: 15, lastAction: 'git fetch origin' });
        addTerminalLine(`[worker-${s}] pulling ${repo}...`);
        setWorkerSlots((prev) => { const next = [...prev]; next[s] = repo; return next; });
      }, staggeredDelay);
    }

    // Process completions + next starts
    let completionDelay = 1800;
    const processedRepos: string[] = [];

    const scheduleCompletion = (repoName: string, slotIndex: number) => {
      const isError = repoName === 'bv'; // bv has conflicts in this scenario
      const thisDuration = finishTimes[repoName] ?? 1500;
      const finishAt = completionDelay + thisDuration;

      // Progress ticks
      const ticks = 4;
      for (let t = 1; t <= ticks; t++) {
        const tickDelay = completionDelay + (thisDuration / ticks) * t;
        const prog = Math.min(15 + (85 / ticks) * t, isError ? 60 : 100);
        addTimer(() => updateRepo(repoName, { progress: prog }), tickDelay);
      }

      addTimer(() => {
        if (isError) {
          updateRepo(repoName, { status: 'conflict', progress: 60, lastAction: 'CONFLICT in merge' });
          addTerminalLine(`[worker-${slotIndex}] CONFLICT: ${repoName} — manual resolution needed`);
        } else {
          updateRepo(repoName, { status: 'synced', progress: 100, lastAction: 'fast-forward to origin/main' });
          addTerminalLine(`[worker-${slotIndex}] synced ${repoName} (ff)`);
        }
        processedRepos.push(repoName);

        // Assign next from queue
        if (workerQueue.length > 0) {
          const next = workerQueue.shift()!;
          activeSlots[slotIndex] = next;
          setWorkerSlots((prev) => { const n = [...prev]; n[slotIndex] = next; return n; });
          updateRepo(next, { status: 'pulling', progress: 10, lastAction: 'git fetch origin' });
          addTerminalLine(`[worker-${slotIndex}] pulling ${next}...`);
          scheduleCompletion(next, slotIndex);
        } else {
          activeSlots[slotIndex] = null;
          setWorkerSlots((prev) => { const n = [...prev]; n[slotIndex] = null; return n; });
        }

        // Check if all done
        if (processedRepos.length === order.length) {
          addTimer(() => {
            addTerminalLine('9/10 synced, 1 conflict — exit code 2');
            setIsRunning(false);
            setCompletedScenario(true);
          }, 400);
        }
      }, finishAt);

      completionDelay = Math.max(completionDelay, finishAt + 200);
    };

    // Schedule first batch completions
    for (let s = 0; s < 4; s++) {
      if (activeSlots[s]) {
        scheduleCompletion(activeSlots[s]!, s);
      }
    }
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Scenario: Initial Clone ----
  const runInitialClone = useCallback(() => {
    const cloneOrder = ['ntm', 'beads_rust', 'cass', 'slb', 'dcg'];
    const delay = 200;

    addTerminalLine('$ ru sync --clone');
    addTerminalLine('Scanning repos.d/ manifest...');

    addTimer(() => addTerminalLine(`Found ${cloneOrder.length} missing repos to clone`), 600);

    cloneOrder.forEach((name, i) => {
      const startDelay = delay + i * 1600;

      addTimer(() => {
        updateRepo(name, { status: 'cloning', progress: 10, lastAction: `git clone git@github.com:Dicklesworthstone/${name}.git` });
        addTerminalLine(`Cloning ${name}...`);
      }, startDelay);

      // Progress ticks
      for (let t = 1; t <= 5; t++) {
        addTimer(() => {
          updateRepo(name, { progress: Math.min(10 + t * 18, 100) });
        }, startDelay + t * 280);
      }

      addTimer(() => {
        updateRepo(name, { status: 'synced', progress: 100, lastAction: 'clone complete' });
        addTerminalLine(`Cloned ${name} (${Math.floor(12 + name.length * 2.3)}MB)`);
      }, startDelay + 1400);
    });

    addTimer(() => {
      addTerminalLine(`${cloneOrder.length}/${cloneOrder.length} cloned — exit code 0`);
      setIsRunning(false);
      setCompletedScenario(true);
    }, delay + cloneOrder.length * 1600 + 400);
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Scenario: Dirty Detection ----
  const runDirtyDetect = useCallback(() => {
    const dirtyRepos = ['cass', 'dcg', 'caam', 'bv'];
    const cleanRepos = ['ntm', 'beads_rust', 'slb', 'ubs', 'ru', 'flywheel'];
    const delay = 200;

    addTerminalLine('$ ru status --fetch');
    addTerminalLine('Fetching all remotes...');

    // Scan all repos
    [...cleanRepos, ...dirtyRepos].forEach((name, i) => {
      const scanDelay = delay + 400 + i * 350;
      addTimer(() => {
        const isDirty = dirtyRepos.includes(name);
        const repo = ALL_REPOS.find((r) => r.name === name)!;
        updateRepo(name, {
          status: isDirty ? 'dirty' : 'synced',
          progress: 100,
          changedFiles: isDirty ? repo.changedFiles : 0,
          lastAction: isDirty ? `${repo.changedFiles} modified files` : 'clean',
        });
        if (isDirty) {
          addTerminalLine(`  DIRTY  ${name} (${repo.changedFiles} files, +${repo.ahead} -${repo.behind})`);
        } else {
          addTerminalLine(`  CLEAN  ${name}`);
        }
      }, scanDelay);
    });

    addTimer(() => {
      addTerminalLine(`4 dirty, 6 clean — exit code 0`);
      setIsRunning(false);
      setCompletedScenario(true);
    }, delay + 400 + 10 * 350 + 500);
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Scenario: AI Commit ----
  const runAiCommit = useCallback(() => {
    const dirtyRepos = ['cass', 'dcg', 'bv'];
    const delay = 200;

    addTerminalLine('$ ru agent-sweep --dry-run');
    addTerminalLine('Phase 1: Scanning for dirty repos...');

    // Mark dirty repos
    dirtyRepos.forEach((name, i) => {
      addTimer(() => {
        const repo = ALL_REPOS.find((r) => r.name === name)!;
        updateRepo(name, { status: 'dirty', progress: 30, changedFiles: repo.changedFiles });
        addTerminalLine(`Found dirty: ${name} (${repo.changedFiles} files)`);
      }, delay + 600 + i * 400);
    });

    // AI analysis per repo
    let aiDelay = delay + 600 + dirtyRepos.length * 400 + 600;

    dirtyRepos.forEach((name, i) => {
      const msgIndex = i % AI_COMMIT_MESSAGES.length;
      const msg = AI_COMMIT_MESSAGES[msgIndex];

      addTimer(() => {
        addTerminalLine(`Phase 2: AI analyzing diff for ${name}...`);
        updateRepo(name, { status: 'ai-commit', progress: 50 });
        setAiTargetRepo(name);
        setAiTyping('');
      }, aiDelay);

      // Type out the commit message character by character
      const chars = msg.split('');
      chars.forEach((char, ci) => {
        addTimer(() => {
          setAiTyping((prev) => prev + char);
        }, aiDelay + 400 + ci * 35);
      });

      const typingDuration = 400 + chars.length * 35 + 300;

      addTimer(() => {
        updateRepo(name, { status: 'synced', progress: 100, commitMsg: msg, lastAction: 'AI committed' });
        addTerminalLine(`  Commit: "${msg}"`);
        setAiTyping('');
        setAiTargetRepo('');
      }, aiDelay + typingDuration);

      aiDelay += typingDuration + 500;
    });

    addTimer(() => {
      addTerminalLine(`${dirtyRepos.length} repos committed — exit code 0`);
      setIsRunning(false);
      setCompletedScenario(true);
    }, aiDelay + 300);
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Scenario: Conflict Resolution ----
  const runConflictResolve = useCallback(() => {
    const syncRepos = ['ntm', 'dcg', 'bv', 'slb'];
    const delay = 200;

    addTerminalLine('$ ru sync --autostash');

    syncRepos.forEach((name, i) => {
      const startDelay = delay + 400 + i * 2000;

      addTimer(() => {
        updateRepo(name, { status: 'pulling', progress: 20, lastAction: 'git stash' });
        addTerminalLine(`[${name}] stashing local changes...`);
      }, startDelay);

      addTimer(() => {
        updateRepo(name, { progress: 50, lastAction: 'git pull --rebase' });
        addTerminalLine(`[${name}] pulling with rebase...`);
      }, startDelay + 600);

      if (name === 'bv') {
        // Conflict scenario
        addTimer(() => {
          updateRepo(name, { status: 'conflict', progress: 65, lastAction: 'CONFLICT: src/main.rs' });
          addTerminalLine(`[${name}] CONFLICT in src/main.rs — stash pop failed`);
        }, startDelay + 1200);

        addTimer(() => {
          addTerminalLine(`[${name}] Attempting auto-resolve via 3-way merge...`);
        }, startDelay + 1500);

        addTimer(() => {
          updateRepo(name, { status: 'synced', progress: 100, lastAction: 'conflict auto-resolved' });
          addTerminalLine(`[${name}] Conflict auto-resolved, stash re-applied`);
        }, startDelay + 1800);
      } else {
        addTimer(() => {
          updateRepo(name, { status: 'synced', progress: 100, lastAction: 'ff + stash pop' });
          addTerminalLine(`[${name}] synced, stash re-applied`);
        }, startDelay + 1200);
      }
    });

    addTimer(() => {
      addTerminalLine('4/4 synced (1 conflict auto-resolved) — exit code 0');
      setIsRunning(false);
      setCompletedScenario(true);
    }, delay + 400 + syncRepos.length * 2000 + 500);
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Scenario: Full Sweep ----
  const runFullSweep = useCallback(() => {
    const sweepRepos = ['cass', 'dcg', 'caam', 'bv', 'ntm', 'slb'];
    const delay = 200;

    addTerminalLine('$ ru agent-sweep --parallel 4');
    addTerminalLine('Spawning 4 Claude Code agents...');

    // Phase 1: Detect dirty
    sweepRepos.forEach((name, i) => {
      addTimer(() => {
        const repo = ALL_REPOS.find((r) => r.name === name)!;
        updateRepo(name, { status: 'dirty', progress: 15, changedFiles: Math.max(repo.changedFiles, 1) });
      }, delay + 300 + i * 150);
    });

    addTimer(() => {
      addTerminalLine(`Found ${sweepRepos.length} repos needing attention`);
    }, delay + 300 + sweepRepos.length * 150 + 200);

    // Phase 2: Parallel AI commit (2 at a time for visual clarity)
    let agentDelay = delay + 1600;
    for (let batch = 0; batch < sweepRepos.length; batch += 2) {
      const batchRepos = sweepRepos.slice(batch, batch + 2);

      batchRepos.forEach((name, bi) => {
        const msgIdx = (batch + bi) % AI_COMMIT_MESSAGES.length;

        addTimer(() => {
          updateRepo(name, { status: 'ai-commit', progress: 50 });
          addTerminalLine(`[agent-${batch + bi}] analyzing ${name}...`);
        }, agentDelay + bi * 150);

        addTimer(() => {
          updateRepo(name, { progress: 80, commitMsg: AI_COMMIT_MESSAGES[msgIdx] });
          addTerminalLine(`[agent-${batch + bi}] committing ${name}: "${AI_COMMIT_MESSAGES[msgIdx].slice(0, 40)}..."`);
        }, agentDelay + 1000 + bi * 150);

        addTimer(() => {
          updateRepo(name, { status: 'synced', progress: 100, lastAction: 'agent committed + pushed' });
        }, agentDelay + 1600 + bi * 150);
      });

      agentDelay += 2000;
    }

    addTimer(() => {
      addTerminalLine(`${sweepRepos.length}/${sweepRepos.length} swept — exit code 0`);
      setIsRunning(false);
      setCompletedScenario(true);
    }, agentDelay + 400);
  }, [addTimer, addTerminalLine, updateRepo]);

  // ---- Run selected scenario ----
  const runScenario = useCallback(() => {
    resetAll();
    addTimer(() => {
      setIsRunning(true);
      switch (activeScenario) {
        case 'parallel-sync': runParallelSync(); break;
        case 'initial-clone': runInitialClone(); break;
        case 'dirty-detect': runDirtyDetect(); break;
        case 'ai-commit': runAiCommit(); break;
        case 'conflict-resolve': runConflictResolve(); break;
        case 'full-sweep': runFullSweep(); break;
      }
    }, 80);
  }, [activeScenario, resetAll, addTimer, runParallelSync, runInitialClone, runDirtyDetect, runAiCommit, runConflictResolve, runFullSweep]);

  // Auto-play on mount
  useEffect(() => {
    const id = setTimeout(() => {
      setIsRunning(true);
      runParallelSync();
    }, 700);
    return () => {
      clearTimeout(id);
      clearTimers();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Counters
  const syncedCount = repos.filter((r) => r.status === 'synced').length;
  const errorCount = repos.filter((r) => r.status === 'conflict' || r.status === 'error').length;
  const dirtyCount = repos.filter((r) => r.status === 'dirty' || r.status === 'ai-commit').length;
  const activeCount = repos.filter((r) => r.status === 'pulling' || r.status === 'cloning' || r.status === 'ai-commit').length;

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-blue-500/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/6 w-48 h-48 bg-violet-500/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-32 h-32 bg-amber-500/6 rounded-full blur-3xl pointer-events-none" />

      {/* Scenario selector tabs */}
      <div className="relative px-4 pt-4 pb-2">
        <div className="flex items-center gap-1.5 overflow-x-auto scrollbar-none pb-1">
          {SCENARIOS.map((s) => (
            <button
              key={s.id}
              onClick={() => {
                if (!isRunning) {
                  setActiveScenario(s.id);
                  resetAll();
                }
              }}
              disabled={isRunning}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition duration-200 ${
                activeScenario === s.id
                  ? 'bg-white/[0.1] text-white border border-white/[0.15] shadow-sm shadow-white/5'
                  : 'text-white/40 hover:text-white/60 border border-transparent hover:bg-white/[0.04]'
              } ${isRunning ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'}`}
            >
              {s.icon}
              <span className="hidden sm:inline">{s.label}</span>
            </button>
          ))}
        </div>
        <p className="text-[11px] text-white/30 mt-1.5 px-1">
          {SCENARIOS.find((s) => s.id === activeScenario)?.description}
        </p>
      </div>

      {/* Command bar */}
      <div className="relative px-4 pb-3">
        <div className="flex items-center justify-between gap-2 px-3 py-2 rounded-lg bg-black/50 border border-white/[0.08]">
          <div className="flex items-center gap-2 font-mono text-sm min-w-0">
            <span className="text-emerald-400 select-none shrink-0">$</span>
            <span className="text-white/80 truncate">
              {SCENARIOS.find((s) => s.id === activeScenario)?.command}
            </span>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {isRunning && (
              <motion.div
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                className="flex items-center gap-1.5 text-amber-400"
              >
                <Loader2 className="h-3 w-3 animate-spin" />
                <span className="text-[10px] font-mono">running</span>
              </motion.div>
            )}
            <button
              onClick={runScenario}
              disabled={isRunning}
              className="flex items-center gap-1.5 px-3 py-1 rounded-md bg-white/[0.06] border border-white/[0.08] text-white/60 hover:text-white/90 hover:bg-white/[0.1] transition-colors text-xs font-medium disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {completedScenario ? <RotateCcw className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {completedScenario ? 'Replay' : 'Run'}
            </button>
          </div>
        </div>
      </div>

      {/* Worker slots indicator */}
      {activeScenario === 'parallel-sync' && (
        <div className="relative px-4 pb-2">
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-white/30 font-mono shrink-0">workers:</span>
            <div className="flex items-center gap-1.5">
              {workerSlots.map((slot, i) => (
                <motion.div
                  key={i}
                  className={`px-2 py-0.5 rounded text-[10px] font-mono transition duration-300 ${
                    slot
                      ? 'bg-amber-500/15 text-amber-400 border border-amber-500/20'
                      : 'bg-white/[0.03] text-white/20 border border-white/[0.06]'
                  }`}
                  animate={{ scale: slot ? 1 : 0.95 }}
                  transition={SPRING}
                >
                  {slot ?? 'idle'}
                </motion.div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Main content: Repo grid + terminal */}
      <div className="relative px-4 py-3 grid grid-cols-1 lg:grid-cols-5 gap-3">
        {/* Repo tiles grid */}
        <div className="lg:col-span-3">
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
            {repos.map((repo) => (
              <SyncRepoTile
                key={repo.name}
                repo={repo}
                isAiTarget={aiTargetRepo === repo.name}
                aiTyping={aiTargetRepo === repo.name ? aiTyping : ''}
              />
            ))}
          </div>

          {/* Git branch graph mini-viz */}
          <div className="mt-3 p-3 rounded-xl bg-black/30 border border-white/[0.06]">
            <div className="flex items-center gap-2 mb-2">
              <GitBranch className="h-3.5 w-3.5 text-white/40" />
              <span className="text-[11px] text-white/40 font-medium">Branch States</span>
            </div>
            <div className="space-y-1">
              {repos.filter((r) => r.status !== 'pending').slice(0, 6).map((repo) => (
                <BranchRow key={repo.name} repo={repo} />
              ))}
              {repos.filter((r) => r.status !== 'pending').length === 0 && (
                <p className="text-[10px] text-white/20 font-mono py-1">Waiting for sync to start...</p>
              )}
            </div>
          </div>
        </div>

        {/* Terminal output */}
        <div className="lg:col-span-2">
          <div className="h-full rounded-xl bg-black/50 border border-white/[0.06] overflow-hidden flex flex-col">
            <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
              <Terminal className="h-3.5 w-3.5 text-white/40" />
              <span className="text-[11px] text-white/40 font-mono">output</span>
              <div className="ml-auto flex items-center gap-1">
                <div className="w-2 h-2 rounded-full bg-red-500/60" />
                <div className="w-2 h-2 rounded-full bg-amber-500/60" />
                <div className="w-2 h-2 rounded-full bg-emerald-500/60" />
              </div>
            </div>
            <div
              ref={terminalRef}
              className="flex-1 p-3 overflow-y-auto max-h-64 lg:max-h-80 scrollbar-thin scrollbar-track-transparent scrollbar-thumb-white/10"
            >
              <div className="space-y-0.5 font-mono text-[11px]">
                <AnimatePresence>
                  {terminalLines.map((line, i) => (
                    <motion.div
                      key={`${i}-${line.slice(0, 20)}`}
                      initial={{ opacity: 0, x: -8 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ duration: 0.15 }}
                      className={`leading-relaxed ${
                        line.includes('CONFLICT') || line.includes('DIRTY')
                          ? 'text-red-400'
                          : line.includes('synced') || line.includes('cloned') || line.includes('Cloned') || line.includes('CLEAN') || line.includes('committed') || line.includes('resolved') || line.includes('swept')
                            ? 'text-emerald-400/80'
                            : line.includes('exit code')
                              ? 'text-white/70 font-semibold'
                              : line.includes('agent') || line.includes('AI') || line.includes('Commit')
                                ? 'text-violet-400/80'
                                : 'text-white/50'
                      }`}
                    >
                      {line}
                    </motion.div>
                  ))}
                </AnimatePresence>
                {terminalLines.length === 0 && (
                  <span className="text-white/20">Press Run to start...</span>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* AI commit message generation overlay */}
      <AnimatePresence>
        {aiTargetRepo && aiTyping && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={SPRING}
            className="relative mx-4 mb-3 px-4 py-3 rounded-xl bg-violet-500/[0.08] border border-violet-500/20 backdrop-blur-sm"
          >
            <div className="flex items-start gap-3">
              <div className="shrink-0 mt-0.5">
                <motion.div
                  animate={{ rotate: [0, 360] }}
                  transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
                >
                  <Sparkles className="h-4 w-4 text-violet-400" />
                </motion.div>
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-[11px] font-medium text-violet-300">AI Generating Commit for {aiTargetRepo}</span>
                  <motion.div
                    animate={{ opacity: [1, 0.3, 1] }}
                    transition={{ duration: 1, repeat: Infinity }}
                    className="w-1 h-3 bg-violet-400/60 rounded-full"
                  />
                </div>
                <div className="font-mono text-xs text-white/70 break-all">
                  <span className="text-violet-400/60 mr-1">msg:</span>
                  {aiTyping}
                  <motion.span
                    animate={{ opacity: [1, 0] }}
                    transition={{ duration: 0.5, repeat: Infinity }}
                    className="inline-block w-[6px] h-[14px] bg-violet-400/80 ml-0.5 -mb-0.5"
                  />
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Summary bar */}
      <div className="relative px-4 pb-4 pt-1">
        <div className="flex items-center gap-3 px-4 py-3 rounded-lg bg-black/30 border border-white/[0.08]">
          <div className="flex-1">
            <div className="flex items-center justify-between mb-1.5">
              <div className="flex items-center gap-3">
                <StatusPill count={syncedCount} label="synced" color="emerald" />
                <StatusPill count={activeCount} label="active" color="amber" />
                <StatusPill count={dirtyCount} label="dirty" color="violet" />
                <StatusPill count={errorCount} label="issues" color="red" />
              </div>
              {completedScenario && (
                <motion.span
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={SPRING_SNAPPY}
                  className="text-xs font-mono text-emerald-400"
                >
                  {errorCount > 0 ? `exit ${errorCount > 0 ? 2 : 1}` : 'exit 0'}
                </motion.span>
              )}
            </div>
            <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
              <motion.div
                className={`h-full rounded-full ${
                  errorCount > 0
                    ? 'bg-gradient-to-r from-emerald-500 to-red-500'
                    : syncedCount > 0
                      ? 'bg-gradient-to-r from-emerald-500 to-emerald-400'
                      : 'bg-blue-500/70'
                }`}
                animate={{ width: `${((syncedCount + errorCount) / 10) * 100}%` }}
                transition={{ type: 'spring', stiffness: 100, damping: 20 }}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// SyncRepoTile - individual repo tile with rich status display
// ---------------------------------------------------------------------------

function SyncRepoTile({
  repo,
  isAiTarget,
  aiTyping,
}: {
  repo: SyncRepo;
  isAiTarget: boolean;
  aiTyping: string;
}) {
  const statusStyles: Record<RepoSyncStatus, { border: string; bg: string; text: string; glow: string }> = {
    pending: { border: 'border-white/[0.06]', bg: 'bg-white/[0.02]', text: 'text-white/30', glow: '' },
    cloning: { border: 'border-blue-500/30', bg: 'bg-blue-500/[0.05]', text: 'text-blue-400', glow: 'shadow-blue-500/10' },
    pulling: { border: 'border-amber-500/30', bg: 'bg-amber-500/[0.05]', text: 'text-amber-400', glow: 'shadow-amber-500/10' },
    dirty: { border: 'border-orange-500/30', bg: 'bg-orange-500/[0.05]', text: 'text-orange-400', glow: '' },
    'ai-commit': { border: 'border-violet-500/30', bg: 'bg-violet-500/[0.05]', text: 'text-violet-400', glow: 'shadow-violet-500/10' },
    conflict: { border: 'border-red-500/30', bg: 'bg-red-500/[0.05]', text: 'text-red-400', glow: 'shadow-red-500/10' },
    synced: { border: 'border-emerald-500/30', bg: 'bg-emerald-500/[0.05]', text: 'text-emerald-400', glow: '' },
    error: { border: 'border-red-500/30', bg: 'bg-red-500/[0.05]', text: 'text-red-400', glow: '' },
  };

  const style = statusStyles[repo.status];

  const statusIcon: Record<RepoSyncStatus, React.ReactNode> = {
    pending: <FolderGit2 className="h-3.5 w-3.5 text-white/25" />,
    cloning: <Loader2 className="h-3.5 w-3.5 text-blue-400 animate-spin" />,
    pulling: <Loader2 className="h-3.5 w-3.5 text-amber-400 animate-spin" />,
    dirty: <AlertTriangle className="h-3.5 w-3.5 text-orange-400" />,
    'ai-commit': <Sparkles className="h-3.5 w-3.5 text-violet-400" />,
    conflict: <XCircle className="h-3.5 w-3.5 text-red-400" />,
    synced: <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400" />,
    error: <XCircle className="h-3.5 w-3.5 text-red-400" />,
  };

  return (
    <motion.div
      layout
      animate={
        repo.status === 'conflict'
          ? { x: [0, -3, 3, -3, 3, 0] }
          : {}
      }
      transition={
        repo.status === 'conflict'
          ? { duration: 0.4, ease: 'easeInOut' }
          : SPRING
      }
      className={`relative rounded-lg border ${style.border} ${style.bg} p-2 overflow-hidden transition-colors duration-300 ${style.glow ? `shadow-sm ${style.glow}` : ''}`}
    >
      {/* Pulse overlays */}
      <AnimatePresence>
        {(repo.status === 'pulling' || repo.status === 'cloning') && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: [0.02, 0.06, 0.02] }}
            exit={{ opacity: 0 }}
            transition={{ duration: 1.5, repeat: Infinity, ease: 'easeInOut' }}
            className={`absolute inset-0 ${repo.status === 'cloning' ? 'bg-blue-400' : 'bg-amber-400'} rounded-lg`}
          />
        )}
      </AnimatePresence>

      <AnimatePresence>
        {repo.status === 'ai-commit' && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: [0.02, 0.05, 0.02] }}
            exit={{ opacity: 0 }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
            className="absolute inset-0 bg-violet-400 rounded-lg"
          />
        )}
      </AnimatePresence>

      {/* Header */}
      <div className="relative flex items-center gap-1.5 mb-1.5">
        <AnimatePresence mode="wait">
          <motion.div
            key={repo.status}
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0, opacity: 0 }}
            transition={SPRING_SNAPPY}
          >
            {statusIcon[repo.status]}
          </motion.div>
        </AnimatePresence>
        <span className={`text-[10px] font-mono font-medium ${style.text} truncate leading-tight`}>
          {repo.name}
        </span>
      </div>

      {/* Branch badge */}
      {repo.status !== 'pending' && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex items-center gap-1 mb-1.5"
        >
          <GitBranch className="h-2.5 w-2.5 text-white/20" />
          <span className="text-[9px] font-mono text-white/25">{repo.branch}</span>
          {repo.changedFiles > 0 && repo.status !== 'synced' && (
            <span className="text-[9px] font-mono text-orange-400/70 ml-auto">{repo.changedFiles}f</span>
          )}
        </motion.div>
      )}

      {/* Progress bar */}
      <div className="h-0.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${
            repo.status === 'conflict' || repo.status === 'error'
              ? 'bg-red-500/70'
              : repo.status === 'synced'
                ? 'bg-emerald-500/70'
                : repo.status === 'ai-commit'
                  ? 'bg-violet-500/70'
                  : repo.status === 'dirty'
                    ? 'bg-orange-500/50'
                    : repo.status === 'cloning'
                      ? 'bg-blue-500/70'
                      : repo.status === 'pulling'
                        ? 'bg-amber-500/70'
                        : 'bg-white/10'
          }`}
          animate={{ width: `${repo.progress}%` }}
          transition={{ type: 'spring', stiffness: 120, damping: 20 }}
        />
      </div>

      {/* AI typing indicator on tile */}
      {isAiTarget && aiTyping && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="mt-1 text-[8px] font-mono text-violet-400/60 truncate"
        >
          {aiTyping.slice(-20)}
        </motion.div>
      )}
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// BranchRow - mini git graph row showing branch state for a repo
// ---------------------------------------------------------------------------

function BranchRow({ repo }: { repo: SyncRepo }) {
  const getNodeColor = () => {
    switch (repo.status) {
      case 'synced': return 'bg-emerald-400';
      case 'pulling': case 'cloning': return 'bg-amber-400';
      case 'dirty': case 'ai-commit': return 'bg-violet-400';
      case 'conflict': case 'error': return 'bg-red-400';
      default: return 'bg-white/30';
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, x: -6 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.2 }}
      className="flex items-center gap-2 py-0.5"
    >
      {/* Branch line */}
      <div className="flex items-center gap-0.5 w-16 shrink-0">
        <div className={`w-2 h-2 rounded-full ${getNodeColor()} shrink-0`} />
        <div className="h-px flex-1 bg-white/[0.08]" />
        {repo.ahead > 0 && (
          <div className="w-1.5 h-1.5 rounded-full bg-blue-400 shrink-0" />
        )}
      </div>
      <span className="text-[10px] font-mono text-white/40 w-14 truncate">{repo.name}</span>
      <span className="text-[9px] font-mono text-white/20 w-10">{repo.branch}</span>
      <div className="flex items-center gap-1 ml-auto">
        {repo.ahead > 0 && (
          <span className="text-[9px] font-mono text-blue-400/60">+{repo.ahead}</span>
        )}
        {repo.behind > 0 && (
          <span className="text-[9px] font-mono text-amber-400/60">-{repo.behind}</span>
        )}
        {repo.commitMsg && (
          <FileText className="h-2.5 w-2.5 text-violet-400/40 ml-1" />
        )}
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// StatusPill - compact status counter
// ---------------------------------------------------------------------------

function StatusPill({
  count,
  label,
  color,
}: {
  count: number;
  label: string;
  color: 'emerald' | 'amber' | 'violet' | 'red';
}) {
  if (count === 0) return null;

  const colorMap = {
    emerald: 'text-emerald-400/80 bg-emerald-500/10',
    amber: 'text-amber-400/80 bg-amber-500/10',
    violet: 'text-violet-400/80 bg-violet-500/10',
    red: 'text-red-400/80 bg-red-500/10',
  };

  return (
    <motion.span
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={SPRING_SNAPPY}
      className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono ${colorMap[color]}`}
    >
      {count} {label}
    </motion.span>
  );
}
