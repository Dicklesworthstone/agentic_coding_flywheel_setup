'use client';

import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  GraduationCap,
  Terminal,
  Package,
  Search,
  Play,
  Settings,
  Download,
  Code2,
  Server,
  CheckCircle2,
  Circle,
  ChevronRight,
  FolderTree,
  FileText,
  Loader2,
  Sparkles,
  X,
  Shield,
  GitBranch,
  Zap,
  Layers,
  ArrowRight,
  Eye,
  Hash,
  Star,
  TrendingUp,
  BarChart3,
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

export function MsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master local-first skill management for Claude Code and other AI agents with Meta Skill.
      </GoalBanner>

      {/* Section 1: What Is Meta Skill */}
      <Section title="What Is Meta Skill?" icon={<GraduationCap className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>Meta Skill (ms)</Highlight> is a local-first knowledge management platform that
          turns operational knowledge into structured, searchable, reusable artifacts with Git-backed
          audit trails.
        </Paragraph>
        <Paragraph>
          It combines BM25 lexical matching with deterministic hash embeddings for hybrid semantic
          search. No external APIs required. Skills can come from hand-written files, CASS session
          mining, or bundle imports.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Package className="h-5 w-5" />}
              title="Local-First"
              description="Skills stored on your machine, no cloud dependency"
              gradient="from-purple-500/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Easy Install"
              description="One command to install from JeffreysPrompts"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Browse Skills"
              description="Discover and search available skills"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Settings className="h-5 w-5" />}
              title="Manage"
              description="Update, disable, and organize your skills"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-8">
          <InteractiveSkillBrowser />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'ms list', description: 'List all installed skills' },
            { command: 'ms install <skill>', description: 'Install a skill from registry' },
            { command: 'ms uninstall <skill>', description: 'Remove an installed skill' },
            { command: 'ms update', description: 'Update all installed skills' },
            { command: 'ms doctor', description: 'Check skill system health' },
            { command: 'ms search <query>', description: 'Search for skills in registry' },
          ]}
        />

        <TipBox>
          Install popular skills directly: <code>ms install code-review</code>
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Working with Skills */}
      <Section title="Working with Skills" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Once installed, skills are automatically available in Claude Code. Use them with
          the slash command syntax.
        </Paragraph>

        <CodeBlock code={`# List your installed skills
ms list

# Install a skill
ms install idea-wizard

# Use it in Claude Code
/idea-wizard "build a todo app"

# Update all skills to latest versions
ms update`} />
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE SKILL BROWSER - Skill Library Dashboard
// =============================================================================

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

interface Skill {
  id: string;
  name: string;
  description: string;
  file: string;
  installed: boolean;
  category: string;
  triggers: string[];
  commands: string[];
  dependencies: string[];
  usageCount: number;
  rating: number;
  version: string;
}

interface SkillCategory {
  id: string;
  label: string;
  icon: React.ReactNode;
  gradient: string;
  borderColor: string;
  textColor: string;
  bgAccent: string;
}

const CATEGORIES: SkillCategory[] = [
  {
    id: 'all',
    label: 'All Skills',
    icon: <Layers className="h-4 w-4" />,
    gradient: 'from-white/10 to-white/5',
    borderColor: 'border-white/20',
    textColor: 'text-white',
    bgAccent: 'bg-white/10',
  },
  {
    id: 'cli',
    label: 'CLI Tools',
    icon: <Terminal className="h-4 w-4" />,
    gradient: 'from-violet-500/20 to-purple-500/20',
    borderColor: 'border-violet-500/30',
    textColor: 'text-violet-400',
    bgAccent: 'bg-violet-500/10',
  },
  {
    id: 'agent',
    label: 'Agent Workflows',
    icon: <Sparkles className="h-4 w-4" />,
    gradient: 'from-cyan-500/20 to-blue-500/20',
    borderColor: 'border-cyan-500/30',
    textColor: 'text-cyan-400',
    bgAccent: 'bg-cyan-500/10',
  },
  {
    id: 'infra',
    label: 'Infrastructure',
    icon: <Server className="h-4 w-4" />,
    gradient: 'from-amber-500/20 to-orange-500/20',
    borderColor: 'border-amber-500/30',
    textColor: 'text-amber-400',
    bgAccent: 'bg-amber-500/10',
  },
  {
    id: 'security',
    label: 'Security',
    icon: <Shield className="h-4 w-4" />,
    gradient: 'from-rose-500/20 to-red-500/20',
    borderColor: 'border-rose-500/30',
    textColor: 'text-rose-400',
    bgAccent: 'bg-rose-500/10',
  },
  {
    id: 'dev',
    label: 'Development',
    icon: <Code2 className="h-4 w-4" />,
    gradient: 'from-emerald-500/20 to-teal-500/20',
    borderColor: 'border-emerald-500/30',
    textColor: 'text-emerald-400',
    bgAccent: 'bg-emerald-500/10',
  },
  {
    id: 'coord',
    label: 'Coordination',
    icon: <GitBranch className="h-4 w-4" />,
    gradient: 'from-fuchsia-500/20 to-pink-500/20',
    borderColor: 'border-fuchsia-500/30',
    textColor: 'text-fuchsia-400',
    bgAccent: 'bg-fuchsia-500/10',
  },
];

const INITIAL_SKILLS: Skill[] = [
  {
    id: 'code-review',
    name: 'code-review',
    description: 'Automated code review with best-practice checks, security scanning, and style suggestions. Generates inline comments and a summary report.',
    file: 'code-review.md',
    installed: true,
    category: 'dev',
    triggers: ['/review', '/cr', 'review this PR'],
    commands: ['ms invoke code-review --file src/', 'ms invoke code-review --diff HEAD~1'],
    dependencies: ['refactor-guru'],
    usageCount: 2847,
    rating: 4.9,
    version: '2.3.1',
  },
  {
    id: 'refactor-guru',
    name: 'refactor-guru',
    description: 'Intelligent refactoring suggestions with before/after diffs, impact analysis, and complexity scoring. Detects code smells automatically.',
    file: 'refactor-guru.md',
    installed: true,
    category: 'dev',
    triggers: ['/refactor', '/clean', 'refactor this function'],
    commands: ['ms invoke refactor-guru --target src/utils.ts', 'ms invoke refactor-guru --smell'],
    dependencies: ['code-review'],
    usageCount: 1923,
    rating: 4.7,
    version: '1.8.0',
  },
  {
    id: 'idea-wizard',
    name: 'idea-wizard',
    description: 'Turn vague ideas into structured project plans with architecture diagrams, tech stack recommendations, and milestone breakdowns.',
    file: 'idea-wizard.md',
    installed: false,
    category: 'agent',
    triggers: ['/idea', '/brainstorm', 'plan this project'],
    commands: ['ms invoke idea-wizard --prompt "build a todo app"', 'ms invoke idea-wizard --interactive'],
    dependencies: ['doc-gen'],
    usageCount: 3421,
    rating: 4.8,
    version: '3.1.0',
  },
  {
    id: 'doc-gen',
    name: 'doc-gen',
    description: 'Generate comprehensive documentation from code with JSDoc, README templates, API docs, and usage examples. Supports multiple output formats.',
    file: 'doc-gen.md',
    installed: false,
    category: 'dev',
    triggers: ['/docs', '/document', 'generate docs'],
    commands: ['ms invoke doc-gen --source src/', 'ms invoke doc-gen --format markdown'],
    dependencies: [],
    usageCount: 2156,
    rating: 4.6,
    version: '2.0.4',
  },
  {
    id: 'stacktrace-decoder',
    name: 'stacktrace-decoder',
    description: 'Parse and explain complex stack traces with source mapping, root cause analysis, and suggested fixes. Works with Node.js, Python, Rust, and Go.',
    file: 'stacktrace-decoder.md',
    installed: true,
    category: 'cli',
    triggers: ['/decode', '/trace', 'explain this error'],
    commands: ['ms invoke stacktrace-decoder --paste', 'ms invoke stacktrace-decoder --file crash.log'],
    dependencies: ['log-analyzer'],
    usageCount: 1567,
    rating: 4.5,
    version: '1.4.2',
  },
  {
    id: 'log-analyzer',
    name: 'log-analyzer',
    description: 'Pattern-match log files to find anomalies, errors, and performance bottlenecks. Generates timeline visualizations and alert summaries.',
    file: 'log-analyzer.md',
    installed: false,
    category: 'cli',
    triggers: ['/logs', '/analyze', 'check the logs'],
    commands: ['ms invoke log-analyzer --file app.log', 'ms invoke log-analyzer --tail --service api'],
    dependencies: [],
    usageCount: 987,
    rating: 4.3,
    version: '1.2.0',
  },
  {
    id: 'git-bisect-helper',
    name: 'git-bisect-helper',
    description: 'Automate git bisect to find the exact commit that introduced a bug. Supports custom test commands and parallel testing.',
    file: 'git-bisect-helper.md',
    installed: false,
    category: 'cli',
    triggers: ['/bisect', '/findbug', 'find which commit broke'],
    commands: ['ms invoke git-bisect-helper --test "bun test"', 'ms invoke git-bisect-helper --auto'],
    dependencies: ['stacktrace-decoder'],
    usageCount: 654,
    rating: 4.4,
    version: '1.1.0',
  },
  {
    id: 'test-gen',
    name: 'test-gen',
    description: 'Generate unit and integration tests with edge cases, mocking strategies, and coverage targets. Infers test frameworks from project config.',
    file: 'test-gen.md',
    installed: true,
    category: 'dev',
    triggers: ['/test', '/generate-tests', 'write tests for'],
    commands: ['ms invoke test-gen --file src/utils.ts', 'ms invoke test-gen --coverage 90'],
    dependencies: ['code-review'],
    usageCount: 2891,
    rating: 4.8,
    version: '2.5.0',
  },
  {
    id: 'docker-compose',
    name: 'docker-compose',
    description: 'Generate optimized Dockerfiles and docker-compose configs with multi-stage builds, health checks, and security hardening.',
    file: 'docker-compose.md',
    installed: false,
    category: 'infra',
    triggers: ['/docker', '/containerize', 'dockerize this'],
    commands: ['ms invoke docker-compose --stack node,postgres', 'ms invoke docker-compose --optimize'],
    dependencies: ['ci-pipeline', 'deploy-helper'],
    usageCount: 1432,
    rating: 4.6,
    version: '2.1.0',
  },
  {
    id: 'ci-pipeline',
    name: 'ci-pipeline',
    description: 'Create CI/CD pipelines for GitHub Actions, GitLab CI, or CircleCI from project config. Auto-detects build steps and test suites.',
    file: 'ci-pipeline.md',
    installed: true,
    category: 'infra',
    triggers: ['/ci', '/pipeline', 'set up CI'],
    commands: ['ms invoke ci-pipeline --platform github', 'ms invoke ci-pipeline --detect'],
    dependencies: ['test-gen'],
    usageCount: 1876,
    rating: 4.7,
    version: '2.2.1',
  },
  {
    id: 'deploy-helper',
    name: 'deploy-helper',
    description: 'Deployment checklists, rollback plans, and environment configuration validation. Supports blue-green and canary deployment strategies.',
    file: 'deploy-helper.md',
    installed: false,
    category: 'infra',
    triggers: ['/deploy', '/release', 'deploy to production'],
    commands: ['ms invoke deploy-helper --env production', 'ms invoke deploy-helper --rollback'],
    dependencies: ['ci-pipeline'],
    usageCount: 1098,
    rating: 4.5,
    version: '1.7.0',
  },
  {
    id: 'secret-scanner',
    name: 'secret-scanner',
    description: 'Scan codebases for leaked credentials, API keys, and sensitive data. Integrates with pre-commit hooks and CI pipelines.',
    file: 'secret-scanner.md',
    installed: true,
    category: 'security',
    triggers: ['/scan-secrets', '/secrets', 'check for leaked keys'],
    commands: ['ms invoke secret-scanner --dir .', 'ms invoke secret-scanner --hook install'],
    dependencies: [],
    usageCount: 2234,
    rating: 4.9,
    version: '3.0.2',
  },
  {
    id: 'threat-model',
    name: 'threat-model',
    description: 'Generate STRIDE threat models from architecture descriptions. Identifies attack surfaces, trust boundaries, and mitigation strategies.',
    file: 'threat-model.md',
    installed: false,
    category: 'security',
    triggers: ['/threat', '/stride', 'analyze security'],
    commands: ['ms invoke threat-model --arch diagram.md', 'ms invoke threat-model --interactive'],
    dependencies: ['secret-scanner'],
    usageCount: 876,
    rating: 4.4,
    version: '1.3.0',
  },
  {
    id: 'swarm-dispatch',
    name: 'swarm-dispatch',
    description: 'Coordinate multi-agent task execution with dependency resolution, parallel scheduling, and progress tracking across agent instances.',
    file: 'swarm-dispatch.md',
    installed: false,
    category: 'coord',
    triggers: ['/swarm', '/dispatch', 'run agents in parallel'],
    commands: ['ms invoke swarm-dispatch --tasks plan.json', 'ms invoke swarm-dispatch --agents 4'],
    dependencies: ['idea-wizard'],
    usageCount: 1567,
    rating: 4.7,
    version: '2.0.0',
  },
  {
    id: 'session-replay',
    name: 'session-replay',
    description: 'Replay and analyze previous agent sessions to extract patterns, identify failures, and mine reusable knowledge for skill creation.',
    file: 'session-replay.md',
    installed: false,
    category: 'coord',
    triggers: ['/replay', '/session', 'review last session'],
    commands: ['ms invoke session-replay --last', 'ms invoke session-replay --extract-skills'],
    dependencies: [],
    usageCount: 1234,
    rating: 4.6,
    version: '1.5.0',
  },
  {
    id: 'prompt-optimizer',
    name: 'prompt-optimizer',
    description: 'Analyze and optimize system prompts for clarity, token efficiency, and instruction adherence. Scores prompts on multiple dimensions.',
    file: 'prompt-optimizer.md',
    installed: false,
    category: 'agent',
    triggers: ['/optimize-prompt', '/prompt', 'improve this prompt'],
    commands: ['ms invoke prompt-optimizer --file CLAUDE.md', 'ms invoke prompt-optimizer --benchmark'],
    dependencies: ['session-replay'],
    usageCount: 1789,
    rating: 4.8,
    version: '2.4.0',
  },
  {
    id: 'context-packer',
    name: 'context-packer',
    description: 'Intelligently pack maximum relevant context into agent prompts. Uses semantic chunking and priority ranking to fit within token limits.',
    file: 'context-packer.md',
    installed: true,
    category: 'agent',
    triggers: ['/pack', '/context', 'pack context for'],
    commands: ['ms invoke context-packer --dir src/ --limit 8000', 'ms invoke context-packer --smart'],
    dependencies: ['prompt-optimizer'],
    usageCount: 2543,
    rating: 4.9,
    version: '3.2.0',
  },
];

const FILE_TREE_INITIAL: Array<{
  path: string;
  type: 'dir' | 'file';
  depth: number;
}> = [
  { path: '.claude/', type: 'dir' as const, depth: 0 },
  { path: 'skills/', type: 'dir' as const, depth: 1 },
];

type ViewMode = 'grid' | 'detail' | 'deps' | 'terminal';

function getCategoryMeta(categoryId: string): SkillCategory {
  return CATEGORIES.find((c) => c.id === categoryId) ?? CATEGORIES[0];
}

// Highlight matching text in search
function HighlightMatch({ text, query }: { text: string; query: string }) {
  if (!query.trim()) return <>{text}</>;
  const regex = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
  const parts = text.split(regex);
  // After split with a capturing group, odd indices are matches
  return (
    <>
      {parts.map((part, i) =>
        i % 2 === 1 ? (
          <span key={i} className="text-primary bg-primary/20 rounded px-0.5">
            {part}
          </span>
        ) : (
          <span key={i}>{part}</span>
        )
      )}
    </>
  );
}

// Mini terminal component for skill invocation examples
function MiniTerminal({ lines, isVisible }: { lines: string[]; isVisible: boolean }) {
  const [visibleLines, setVisibleLines] = useState<number>(0);
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });

  useEffect(() => {
    if (!isVisible) {
      const t = setTimeout(() => setVisibleLines(0), 0);
      return () => clearTimeout(t);
    }
    const timers: ReturnType<typeof setTimeout>[] = [];
    // Reset to 0 first, then reveal line-by-line
    const resetTimer = setTimeout(() => setVisibleLines(0), 0);
    timers.push(resetTimer);
    lines.forEach((_, idx) => {
      const t = setTimeout(() => {
        setVisibleLines(idx + 1);
      }, 300 + idx * 400);
      timers.push(t);
    });
    return () => timers.forEach(clearTimeout);
  }, [isVisible, lines]);

  return (
    <div ref={ref} className="rounded-lg bg-black/60 border border-white/[0.06] overflow-hidden">
      {/* Terminal title bar */}
      <div className="flex items-center gap-1.5 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
        <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
        <div className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
        <span className="ml-2 text-[10px] text-white/30 font-mono">skill-invoke</span>
      </div>
      {/* Terminal body */}
      <div className="p-3 font-mono text-xs space-y-1 min-h-[80px]">
        {lines.map((line, idx) => (
          <AnimatePresence key={idx}>
            {idx < visibleLines && (
              <motion.div
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ ...SPRING, delay: 0.05 }}
                className={
                  line.startsWith('$')
                    ? 'text-emerald-400'
                    : line.startsWith('#')
                      ? 'text-white/30'
                      : line.startsWith('>')
                        ? 'text-cyan-400/80'
                        : line.startsWith('!')
                          ? 'text-amber-400/80'
                          : 'text-white/50'
                }
              >
                {line}
              </motion.div>
            )}
          </AnimatePresence>
        ))}
        {visibleLines < lines.length && isVisible && (
          <motion.span
            animate={inView ? { opacity: [1, 0] } : { opacity: 1 }}
            transition={inView ? { repeat: Infinity, duration: 0.8 } : { duration: 0.2 }}
            className="inline-block w-2 h-3.5 bg-emerald-400/80"
          />
        )}
      </div>
    </div>
  );
}

// Dependency graph visualization
function DependencyGraph({
  skills,
  selectedSkill,
  onSelectSkill,
}: {
  skills: Skill[];
  selectedSkill: Skill | null;
  onSelectSkill: (skill: Skill) => void;
}) {
  const svgRef = useRef<SVGSVGElement>(null);

  // Layout nodes in a simple force-directed style
  const [nodePositions] = useState(() => {
    const positions: Record<string, { x: number; y: number }> = {};
    const centerX = 200;
    const centerY = 140;
    const radiusX = 150;
    const radiusY = 100;
    skills.forEach((skill, i) => {
      const angle = (i / skills.length) * 2 * Math.PI - Math.PI / 2;
      positions[skill.id] = {
        x: centerX + radiusX * Math.cos(angle),
        y: centerY + radiusY * Math.sin(angle),
      };
    });
    return positions;
  });

  // Build edges from dependencies
  const edges = useMemo(() => {
    const result: { from: string; to: string; highlighted: boolean }[] = [];
    skills.forEach((skill) => {
      skill.dependencies.forEach((depName) => {
        const depSkill = skills.find((s) => s.name === depName);
        if (depSkill && nodePositions[skill.id] && nodePositions[depSkill.id]) {
          result.push({
            from: skill.id,
            to: depSkill.id,
            highlighted:
              selectedSkill?.id === skill.id || selectedSkill?.id === depSkill.id,
          });
        }
      });
    });
    return result;
  }, [skills, selectedSkill, nodePositions]);

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 backdrop-blur-xl">
      <div className="flex items-center gap-2 mb-3">
        <GitBranch className="h-4 w-4 text-white/40" />
        <span className="text-xs font-bold text-white/60 uppercase tracking-wider">
          Dependency Graph
        </span>
      </div>
      <div className="relative overflow-hidden rounded-lg bg-black/20 border border-white/[0.04]">
        <svg
          ref={svgRef}
          viewBox="0 0 400 280"
          className="w-full h-auto"
          style={{ minHeight: 200 }}
        >
          {/* Edges */}
          {edges.map((edge, i) => {
            const from = nodePositions[edge.from];
            const to = nodePositions[edge.to];
            if (!from || !to) return null;
            return (
              <motion.line
                key={`${edge.from}-${edge.to}-${i}`}
                x1={from.x}
                y1={from.y}
                x2={to.x}
                y2={to.y}
                stroke={edge.highlighted ? 'rgba(139, 92, 246, 0.6)' : 'rgba(255,255,255,0.08)'}
                strokeWidth={edge.highlighted ? 2 : 1}
                strokeDasharray={edge.highlighted ? 'none' : '4 4'}
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 0.8, delay: i * 0.05 }}
              />
            );
          })}
          {/* Arrow markers for edges */}
          {edges.map((edge, i) => {
            const from = nodePositions[edge.from];
            const to = nodePositions[edge.to];
            if (!from || !to) return null;
            const dx = to.x - from.x;
            const dy = to.y - from.y;
            const len = Math.sqrt(dx * dx + dy * dy);
            if (len === 0) return null;
            const nx = dx / len;
            const ny = dy / len;
            const arrowX = to.x - nx * 14;
            const arrowY = to.y - ny * 14;
            return (
              <motion.circle
                key={`arrow-${edge.from}-${edge.to}-${i}`}
                cx={arrowX}
                cy={arrowY}
                r={2.5}
                fill={edge.highlighted ? 'rgba(139, 92, 246, 0.8)' : 'rgba(255,255,255,0.15)'}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.5 + i * 0.05 }}
              />
            );
          })}
          {/* Nodes */}
          {skills.map((skill, i) => {
            const pos = nodePositions[skill.id];
            if (!pos) return null;
            const isSelected = selectedSkill?.id === skill.id;
            const catMeta = getCategoryMeta(skill.category);
            const isConnected =
              selectedSkill?.dependencies.includes(skill.name) ||
              skill.dependencies.some(
                (d) => skills.find((s) => s.name === d)?.id === selectedSkill?.id
              );
            return (
              <g
                key={skill.id}
                onClick={() => onSelectSkill(skill)}
                style={{ cursor: 'pointer' }}
              >
                <motion.circle
                  cx={pos.x}
                  cy={pos.y}
                  r={isSelected ? 14 : 10}
                  fill={
                    isSelected
                      ? 'rgba(139, 92, 246, 0.3)'
                      : isConnected
                        ? 'rgba(139, 92, 246, 0.15)'
                        : skill.installed
                          ? 'rgba(52, 211, 153, 0.15)'
                          : 'rgba(255, 255, 255, 0.05)'
                  }
                  stroke={
                    isSelected
                      ? 'rgba(139, 92, 246, 0.8)'
                      : isConnected
                        ? 'rgba(139, 92, 246, 0.4)'
                        : skill.installed
                          ? 'rgba(52, 211, 153, 0.4)'
                          : 'rgba(255, 255, 255, 0.12)'
                  }
                  strokeWidth={isSelected ? 2 : 1}
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ ...SPRING, delay: i * 0.04 }}
                />
                <motion.text
                  x={pos.x}
                  y={pos.y + (isSelected ? 24 : 20)}
                  textAnchor="middle"
                  fill={isSelected ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.4)'}
                  fontSize={isSelected ? 9 : 8}
                  fontFamily="monospace"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.3 + i * 0.04 }}
                >
                  {skill.name.length > 12
                    ? skill.name.slice(0, 11) + '\u2026'
                    : skill.name}
                </motion.text>
                {/* Category-color inner dot */}
                <motion.circle
                  cx={pos.x}
                  cy={pos.y}
                  r={3}
                  fill={
                    catMeta.textColor.includes('violet')
                      ? 'rgba(139,92,246,0.8)'
                      : catMeta.textColor.includes('cyan')
                        ? 'rgba(6,182,212,0.8)'
                        : catMeta.textColor.includes('amber')
                          ? 'rgba(245,158,11,0.8)'
                          : catMeta.textColor.includes('rose')
                            ? 'rgba(244,63,94,0.8)'
                            : catMeta.textColor.includes('emerald')
                              ? 'rgba(52,211,153,0.8)'
                              : catMeta.textColor.includes('fuchsia')
                                ? 'rgba(217,70,239,0.8)'
                                : 'rgba(255,255,255,0.6)'
                  }
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ ...SPRING, delay: 0.2 + i * 0.04 }}
                />
              </g>
            );
          })}
        </svg>
      </div>
      <p className="text-xs text-white/25 mt-2 text-center">
        Click nodes to explore skill dependencies
      </p>
    </div>
  );
}

// Stats bar showing aggregate metrics
function StatsBar({ skills }: { skills: Skill[] }) {
  const installedCount = skills.filter((s) => s.installed).length;
  const totalUsage = skills.reduce((sum, s) => sum + s.usageCount, 0);
  const avgRating = skills.length > 0 ? skills.reduce((sum, s) => sum + s.rating, 0) / skills.length : 0;

  return (
    <div className="grid grid-cols-4 gap-3">
      {[
        { label: 'Total', value: skills.length.toString(), icon: <Package className="h-3.5 w-3.5" />, color: 'text-white/70' },
        { label: 'Installed', value: `${installedCount}`, icon: <CheckCircle2 className="h-3.5 w-3.5" />, color: 'text-emerald-400' },
        { label: 'Usage', value: `${(totalUsage / 1000).toFixed(1)}k`, icon: <TrendingUp className="h-3.5 w-3.5" />, color: 'text-cyan-400' },
        { label: 'Avg Rating', value: avgRating.toFixed(1), icon: <Star className="h-3.5 w-3.5" />, color: 'text-amber-400' },
      ].map((stat, i) => (
        <motion.div
          key={stat.label}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...SPRING, delay: i * 0.06 }}
          className="rounded-lg border border-white/[0.06] bg-white/[0.02] px-3 py-2.5 text-center"
        >
          <div className={`flex items-center justify-center gap-1.5 ${stat.color} mb-1`}>
            {stat.icon}
            <span className="text-base font-bold">{stat.value}</span>
          </div>
          <span className="text-[10px] text-white/30 uppercase tracking-wider">{stat.label}</span>
        </motion.div>
      ))}
    </div>
  );
}

function InteractiveSkillBrowser() {
  const [searchQuery, setSearchQuery] = useState('');
  const [activeCategory, setActiveCategory] = useState('all');
  const [selectedSkill, setSelectedSkill] = useState<Skill | null>(null);
  const [viewMode, setViewMode] = useState<ViewMode>('grid');
  const [installingSkill, setInstallingSkill] = useState<string | null>(null);
  const [installProgress, setInstallProgress] = useState(0);
  const [localSkills, setLocalSkills] = useState(INITIAL_SKILLS);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  // Filtered skills
  const filteredSkills = useMemo(() => {
    let result = localSkills;
    if (activeCategory !== 'all') {
      result = result.filter((s) => s.category === activeCategory);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter(
        (s) =>
          s.name.toLowerCase().includes(q) ||
          s.description.toLowerCase().includes(q) ||
          s.triggers.some((t) => t.toLowerCase().includes(q))
      );
    }
    return result;
  }, [localSkills, activeCategory, searchQuery]);

  // Category counts
  const categoryCounts = useMemo(() => {
    const counts: Record<string, number> = { all: localSkills.length };
    localSkills.forEach((s) => {
      counts[s.category] = (counts[s.category] ?? 0) + 1;
    });
    return counts;
  }, [localSkills]);

  // Handle install
  const handleInstall = useCallback(
    (skill: Skill) => {
      if (skill.installed || installingSkill) return;
      setInstallingSkill(skill.id);
      setInstallProgress(0);
    },
    [installingSkill]
  );

  // Animate install progress
  useEffect(() => {
    if (!installingSkill) return;

    const interval = setInterval(() => {
      setInstallProgress((prev) => {
        if (prev >= 100) {
          clearInterval(interval);
          // Use setTimeout to avoid synchronous setState in effect
          setTimeout(() => {
            setLocalSkills((skills) =>
              skills.map((s) =>
                s.id === installingSkill ? { ...s, installed: true } : s
              )
            );
            setSelectedSkill((prev) =>
              prev?.id === installingSkill ? { ...prev, installed: true } : prev
            );
            setInstallingSkill(null);
          }, 0);
          return 100;
        }
        return prev + 3;
      });
    }, 50);

    return () => clearInterval(interval);
  }, [installingSkill]);

  // Terminal lines for selected skill
  const terminalLines = useMemo(() => {
    if (!selectedSkill) return [];
    return [
      `# Invoke ${selectedSkill.name}`,
      `$ ms invoke ${selectedSkill.name}`,
      `> Loading skill from .claude/skills/${selectedSkill.file}`,
      `> Resolving ${selectedSkill.dependencies.length} dependencies...`,
      `> Skill ready. Triggers: ${selectedSkill.triggers.join(', ')}`,
      `! Tip: Use "${selectedSkill.triggers[0]}" in Claude Code`,
    ];
  }, [selectedSkill]);

  // Installed files derived from skills
  const installedFiles = useMemo(() => {
    const base: { path: string; type: 'dir' | 'file'; depth: number }[] = [...FILE_TREE_INITIAL];
    localSkills
      .filter((s) => s.installed)
      .forEach((s) => {
        base.push({ path: s.file, type: 'file', depth: 2 });
      });
    return base;
  }, [localSkills]);

  const viewModes: { id: ViewMode; label: string; icon: React.ReactNode }[] = [
    { id: 'grid', label: 'Grid', icon: <Layers className="h-3.5 w-3.5" /> },
    { id: 'detail', label: 'Detail', icon: <Eye className="h-3.5 w-3.5" /> },
    { id: 'deps', label: 'Deps', icon: <GitBranch className="h-3.5 w-3.5" /> },
    { id: 'terminal', label: 'Terminal', icon: <Terminal className="h-3.5 w-3.5" /> },
  ];

  return (
    <div ref={rootRef} className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Dashboard header */}
      <div className="border-b border-white/[0.06] px-6 py-4">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30">
              <Sparkles className="h-5 w-5 text-primary" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-white">Skill Library Dashboard</h3>
              <p className="text-xs text-white/40">
                Browse, search, and manage {localSkills.length} skills across{' '}
                {CATEGORIES.length - 1} categories
              </p>
            </div>
          </div>
          {/* View mode toggle */}
          <div className="flex items-center gap-1 rounded-lg border border-white/[0.06] bg-white/[0.02] p-1">
            {viewModes.map((mode) => (
              <button
                key={mode.id}
                onClick={() => setViewMode(mode.id)}
                className={`flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors ${
                  viewMode === mode.id
                    ? 'bg-primary/20 text-primary border border-primary/30'
                    : 'border-white/[0.06] text-white/40 hover:border-white/[0.12] hover:text-white/60'
                }`}
              >
                {mode.icon}
                <span className="hidden sm:inline">{mode.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Stats bar */}
      <div className="px-6 pt-4">
        <StatsBar skills={localSkills} />
      </div>

      {/* Search + category filters */}
      <div className="px-6 pt-4 space-y-3">
        {/* Search bar */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-white/30" />
          <input
            ref={searchInputRef}
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search skills by name, description, or trigger..."
            className="w-full rounded-xl border border-white/[0.08] bg-white/[0.02] py-2.5 pl-10 pr-10 text-sm text-white placeholder-white/30 outline-none focus:border-primary/40 focus:ring-1 focus:ring-primary/20 transition-colors"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-white/30 hover:text-white/60 transition-colors"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>

        {/* Category filter pills */}
        <div className="flex flex-wrap gap-1.5">
          {CATEGORIES.map((cat) => {
            const isActive = activeCategory === cat.id;
            const count = categoryCounts[cat.id] ?? 0;
            return (
              <motion.button
                key={cat.id}
                whileHover={{ scale: 1.03 }}
                whileTap={{ scale: 0.97 }}
                transition={SPRING}
                onClick={() => setActiveCategory(cat.id)}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium border transition-colors ${
                  isActive
                    ? `${cat.borderColor} bg-gradient-to-r ${cat.gradient} ${cat.textColor}`
                    : 'border-white/[0.06] text-white/40 hover:border-white/[0.12] hover:text-white/60'
                }`}
              >
                {cat.icon}
                {cat.label}
                <span
                  className={`ml-0.5 text-[10px] ${
                    isActive ? 'opacity-70' : 'opacity-40'
                  }`}
                >
                  {count}
                </span>
              </motion.button>
            );
          })}
        </div>
      </div>

      {/* Main content area */}
      <div className="p-6">
        <AnimatePresence mode="wait">
          {/* GRID VIEW */}
          {viewMode === 'grid' && (
            <motion.div
              key="grid"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={SPRING}
            >
              {filteredSkills.length === 0 ? (
                <div className="text-center py-12">
                  <Search className="mx-auto h-8 w-8 text-white/15 mb-3" />
                  <p className="text-sm text-white/30">No skills match your search</p>
                  <button
                    onClick={() => {
                      setSearchQuery('');
                      setActiveCategory('all');
                    }}
                    className="mt-2 text-xs text-primary/60 hover:text-primary transition-colors"
                  >
                    Clear filters
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {filteredSkills.map((skill, i) => {
                    const cat = getCategoryMeta(skill.category);
                    const isInstalling = installingSkill === skill.id;
                    const isSelected = selectedSkill?.id === skill.id;
                    return (
                      <motion.div
                        key={skill.id}
                        initial={{ opacity: 0, y: 16 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ ...SPRING, delay: i * 0.03 }}
                        onClick={() => setSelectedSkill(skill)}
                        className={`group relative rounded-xl border p-4 cursor-pointer transition-colors ${
                          isSelected
                            ? `${cat.borderColor} bg-gradient-to-br ${cat.gradient}`
                            : 'border-white/[0.06] bg-white/[0.01] hover:border-white/[0.12] hover:bg-white/[0.03]'
                        }`}
                      >
                        {/* Top row: icon + name + status */}
                        <div className="flex items-start gap-3 mb-3">
                          <div
                            className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${cat.gradient} ${cat.textColor}`}
                          >
                            {cat.icon}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-semibold text-white truncate">
                                <HighlightMatch text={skill.name} query={searchQuery} />
                              </span>
                              {skill.installed && (
                                <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400 shrink-0" />
                              )}
                            </div>
                            <span className={`text-[10px] ${cat.textColor} opacity-70`}>
                              {cat.label}
                            </span>
                          </div>
                        </div>

                        {/* Description */}
                        <p className="text-xs text-white/50 leading-relaxed line-clamp-2 mb-3">
                          <HighlightMatch text={skill.description} query={searchQuery} />
                        </p>

                        {/* Trigger badges */}
                        <div className="flex flex-wrap gap-1 mb-3">
                          {skill.triggers.slice(0, 2).map((trigger) => (
                            <span
                              key={trigger}
                              className="rounded-md bg-white/[0.04] border border-white/[0.06] px-1.5 py-0.5 text-[10px] font-mono text-white/40"
                            >
                              {trigger}
                            </span>
                          ))}
                          {skill.triggers.length > 2 && (
                            <span className="text-[10px] text-white/25">
                              +{skill.triggers.length - 2}
                            </span>
                          )}
                        </div>

                        {/* Bottom: stats + install */}
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3 text-[10px] text-white/30">
                            <span className="flex items-center gap-1">
                              <BarChart3 className="h-3 w-3" />
                              {skill.usageCount.toLocaleString()}
                            </span>
                            <span className="flex items-center gap-1">
                              <Star className="h-3 w-3" />
                              {skill.rating}
                            </span>
                            <span className="flex items-center gap-1">
                              <Hash className="h-3 w-3" />
                              v{skill.version}
                            </span>
                          </div>
                          {isInstalling ? (
                            <div className="flex items-center gap-1.5">
                              <motion.div
                                animate={inView ? { rotate: 360 } : { rotate: 0 }}
                                transition={inView ? { repeat: Infinity, duration: 1, ease: 'linear' } : { duration: 0.2 }}
                              >
                                <Loader2 className={`h-3.5 w-3.5 ${cat.textColor}`} />
                              </motion.div>
                              <span className="text-[10px] text-white/40">
                                {installProgress}%
                              </span>
                            </div>
                          ) : !skill.installed ? (
                            <motion.button
                              whileHover={{ scale: 1.08 }}
                              whileTap={{ scale: 0.92 }}
                              transition={SPRING}
                              onClick={(e) => {
                                e.stopPropagation();
                                handleInstall(skill);
                              }}
                              className={`rounded-md px-2.5 py-1 text-[10px] font-medium border ${cat.borderColor} ${cat.textColor} bg-transparent hover:bg-white/[0.05] transition-colors`}
                            >
                              Install
                            </motion.button>
                          ) : (
                            <span className="text-[10px] text-emerald-400/60 font-medium">
                              Installed
                            </span>
                          )}
                        </div>

                        {/* Install progress bar */}
                        {isInstalling && (
                          <div className="mt-2 h-1 rounded-full bg-white/[0.06] overflow-hidden">
                            <motion.div
                              className={`h-full rounded-full bg-gradient-to-r ${cat.gradient.replace(/\/20/g, '/60')}`}
                              initial={{ width: '0%' }}
                              animate={{ width: `${installProgress}%` }}
                              transition={{ duration: 0.08 }}
                            />
                          </div>
                        )}
                      </motion.div>
                    );
                  })}
                </div>
              )}
            </motion.div>
          )}

          {/* DETAIL VIEW */}
          {viewMode === 'detail' && (
            <motion.div
              key="detail"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={SPRING}
              className="flex flex-col lg:flex-row gap-4"
            >
              {/* Skill list */}
              <div className="lg:w-64 shrink-0 space-y-1 max-h-[500px] overflow-y-auto pr-1">
                {filteredSkills.map((skill, i) => {
                  const cat = getCategoryMeta(skill.category);
                  const isSelected = selectedSkill?.id === skill.id;
                  return (
                    <motion.button
                      key={skill.id}
                      initial={{ opacity: 0, x: -12 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ ...SPRING, delay: i * 0.03 }}
                      onClick={() => setSelectedSkill(skill)}
                      className={`w-full flex items-center gap-2.5 rounded-lg border p-2.5 text-left transition-colors ${
                        isSelected
                          ? `${cat.borderColor} bg-gradient-to-r ${cat.gradient}`
                          : 'border-white/[0.04] hover:border-white/[0.10] hover:bg-white/[0.02]'
                      }`}
                    >
                      <div className={`shrink-0 ${cat.textColor}`}>{cat.icon}</div>
                      <div className="flex-1 min-w-0">
                        <span className="text-xs font-mono text-white/80 truncate block">
                          <HighlightMatch text={skill.name} query={searchQuery} />
                        </span>
                      </div>
                      {skill.installed ? (
                        <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400 shrink-0" />
                      ) : (
                        <Circle className="h-3.5 w-3.5 text-white/15 shrink-0" />
                      )}
                      <ChevronRight className="h-3 w-3 text-white/20 shrink-0" />
                    </motion.button>
                  );
                })}
              </div>

              {/* Detail panel */}
              <div className="flex-1">
                <AnimatePresence mode="wait">
                  {selectedSkill ? (
                    <motion.div
                      key={selectedSkill.id}
                      initial={{ opacity: 0, x: 16 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: -8 }}
                      transition={SPRING}
                      className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl"
                    >
                      {/* Detail header */}
                      <div className="flex items-start justify-between mb-4">
                        <div className="flex items-center gap-3">
                          <div
                            className={`flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br ${getCategoryMeta(selectedSkill.category).gradient} ${getCategoryMeta(selectedSkill.category).textColor}`}
                          >
                            {getCategoryMeta(selectedSkill.category).icon}
                          </div>
                          <div>
                            <h4 className="text-sm font-bold text-white font-mono">
                              {selectedSkill.name}
                            </h4>
                            <div className="flex items-center gap-2 mt-0.5">
                              <span
                                className={`text-[10px] ${getCategoryMeta(selectedSkill.category).textColor}`}
                              >
                                {getCategoryMeta(selectedSkill.category).label}
                              </span>
                              <span className="text-[10px] text-white/25">|</span>
                              <span className="text-[10px] text-white/30">
                                v{selectedSkill.version}
                              </span>
                            </div>
                          </div>
                        </div>
                        <button
                          onClick={() => setSelectedSkill(null)}
                          className="rounded-md p-1 text-white/30 hover:text-white/60 hover:bg-white/[0.05] transition-colors"
                        >
                          <X className="h-4 w-4" />
                        </button>
                      </div>

                      {/* Status + stats */}
                      <div className="flex items-center gap-4 mb-4">
                        <div className="flex items-center gap-1.5">
                          {selectedSkill.installed ? (
                            <>
                              <span className="relative flex h-2 w-2">
                                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                                <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
                              </span>
                              <span className="text-xs text-emerald-400 font-medium">
                                Installed
                              </span>
                            </>
                          ) : (
                            <>
                              <span className="h-2 w-2 rounded-full bg-white/20" />
                              <span className="text-xs text-white/40 font-medium">
                                Available
                              </span>
                            </>
                          )}
                        </div>
                        <div className="flex items-center gap-1 text-xs text-white/30">
                          <Star className="h-3 w-3 text-amber-400" />
                          {selectedSkill.rating}
                        </div>
                        <div className="flex items-center gap-1 text-xs text-white/30">
                          <TrendingUp className="h-3 w-3" />
                          {selectedSkill.usageCount.toLocaleString()} uses
                        </div>
                      </div>

                      {/* Description */}
                      <div className="mb-4">
                        <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                          Description
                        </span>
                        <p className="mt-1 text-sm text-white/60 leading-relaxed">
                          {selectedSkill.description}
                        </p>
                      </div>

                      {/* Triggers */}
                      <div className="mb-4">
                        <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                          Trigger Patterns
                        </span>
                        <div className="mt-1.5 flex flex-wrap gap-1.5">
                          {selectedSkill.triggers.map((trigger) => (
                            <span
                              key={trigger}
                              className="rounded-md border border-white/[0.08] bg-white/[0.02] px-2 py-1 text-xs font-mono text-white/50 hover:text-white/70 hover:border-white/[0.15] transition-colors"
                            >
                              {trigger}
                            </span>
                          ))}
                        </div>
                      </div>

                      {/* Commands */}
                      <div className="mb-4">
                        <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                          Example Commands
                        </span>
                        <div className="mt-1.5 space-y-1">
                          {selectedSkill.commands.map((cmd) => (
                            <div
                              key={cmd}
                              className="rounded-lg bg-black/30 border border-white/[0.04] px-3 py-2"
                            >
                              <code className="text-xs font-mono text-white/50">{cmd}</code>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* Dependencies */}
                      <div className="mb-4">
                        <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                          Dependencies
                        </span>
                        <div className="mt-1.5 flex flex-wrap gap-1.5">
                          {selectedSkill.dependencies.length > 0 ? (
                            selectedSkill.dependencies.map((dep) => {
                              const depSkill = localSkills.find((s) => s.name === dep);
                              return (
                                <button
                                  key={dep}
                                  onClick={() => {
                                    if (depSkill) setSelectedSkill(depSkill);
                                  }}
                                  className="flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-white/[0.02] px-2 py-1 text-xs text-white/50 hover:text-white/70 hover:border-white/[0.15] transition-colors"
                                >
                                  <ArrowRight className="h-3 w-3" />
                                  {dep}
                                  {depSkill?.installed && (
                                    <CheckCircle2 className="h-3 w-3 text-emerald-400" />
                                  )}
                                </button>
                              );
                            })
                          ) : (
                            <span className="text-xs text-white/20 italic">No dependencies</span>
                          )}
                        </div>
                      </div>

                      {/* File path */}
                      <div>
                        <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                          File Path
                        </span>
                        <div className="mt-1.5 rounded-lg bg-black/30 border border-white/[0.04] px-3 py-2">
                          <code className="text-xs font-mono text-white/50">
                            .claude/skills/{selectedSkill.file}
                          </code>
                        </div>
                      </div>

                      {/* Install button for uninstalled skills */}
                      {!selectedSkill.installed && (
                        <div className="mt-4">
                          {installingSkill === selectedSkill.id ? (
                            <div className="space-y-2">
                              <div className="flex items-center gap-2">
                                <motion.div
                                  animate={inView ? { rotate: 360 } : { rotate: 0 }}
                                  transition={inView ? { repeat: Infinity, duration: 1, ease: 'linear' } : { duration: 0.2 }}
                                >
                                  <Loader2
                                    className={`h-4 w-4 ${getCategoryMeta(selectedSkill.category).textColor}`}
                                  />
                                </motion.div>
                                <span className="text-xs text-white/50">
                                  Installing... {installProgress}%
                                </span>
                              </div>
                              <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                                <motion.div
                                  className={`h-full rounded-full bg-gradient-to-r ${getCategoryMeta(selectedSkill.category).gradient.replace(/\/20/g, '/60')}`}
                                  initial={{ width: '0%' }}
                                  animate={{ width: `${installProgress}%` }}
                                  transition={{ duration: 0.08 }}
                                />
                              </div>
                            </div>
                          ) : (
                            <motion.button
                              whileHover={{ scale: 1.02 }}
                              whileTap={{ scale: 0.98 }}
                              transition={SPRING}
                              onClick={() => handleInstall(selectedSkill)}
                              className={`w-full rounded-lg border py-2.5 text-sm font-medium transition-colors ${getCategoryMeta(selectedSkill.category).borderColor} ${getCategoryMeta(selectedSkill.category).textColor} bg-gradient-to-r ${getCategoryMeta(selectedSkill.category).gradient} hover:brightness-110`}
                            >
                              <div className="flex items-center justify-center gap-2">
                                <Download className="h-4 w-4" />
                                Install {selectedSkill.name}
                              </div>
                            </motion.button>
                          )}
                        </div>
                      )}
                    </motion.div>
                  ) : (
                    <motion.div
                      key="empty-detail"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      className="rounded-xl border border-white/[0.06] bg-white/[0.01] p-12 text-center"
                    >
                      <Eye className="mx-auto h-8 w-8 text-white/15 mb-3" />
                      <p className="text-sm text-white/30">
                        Select a skill from the list to view details
                      </p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </motion.div>
          )}

          {/* DEPENDENCY GRAPH VIEW */}
          {viewMode === 'deps' && (
            <motion.div
              key="deps"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={SPRING}
              className="flex flex-col lg:flex-row gap-4"
            >
              <div className="flex-1">
                <DependencyGraph
                  skills={filteredSkills}
                  selectedSkill={selectedSkill}
                  onSelectSkill={setSelectedSkill}
                />
              </div>
              <div className="lg:w-72 space-y-4">
                {/* Selected skill info in dep view */}
                <AnimatePresence mode="wait">
                  {selectedSkill ? (
                    <motion.div
                      key={selectedSkill.id}
                      initial={{ opacity: 0, y: 12 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -8 }}
                      transition={SPRING}
                      className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 backdrop-blur-xl"
                    >
                      <div className="flex items-center justify-between mb-3">
                        <h4 className="text-sm font-bold text-white font-mono">
                          {selectedSkill.name}
                        </h4>
                        <button
                          onClick={() => setSelectedSkill(null)}
                          className="rounded-md p-1 text-white/30 hover:text-white/60 hover:bg-white/[0.05] transition-colors"
                        >
                          <X className="h-3.5 w-3.5" />
                        </button>
                      </div>
                      <p className="text-xs text-white/50 leading-relaxed mb-3">
                        {selectedSkill.description}
                      </p>
                      <div className="space-y-2">
                        <div>
                          <span className="text-[10px] text-white/30 uppercase tracking-wider font-medium">
                            Depends On
                          </span>
                          <div className="mt-1 flex flex-wrap gap-1">
                            {selectedSkill.dependencies.length > 0 ? (
                              selectedSkill.dependencies.map((dep) => (
                                <span
                                  key={dep}
                                  className="rounded-md bg-violet-500/10 border border-violet-500/20 px-1.5 py-0.5 text-[10px] font-mono text-violet-400"
                                >
                                  {dep}
                                </span>
                              ))
                            ) : (
                              <span className="text-[10px] text-white/20 italic">None</span>
                            )}
                          </div>
                        </div>
                        <div>
                          <span className="text-[10px] text-white/30 uppercase tracking-wider font-medium">
                            Used By
                          </span>
                          <div className="mt-1 flex flex-wrap gap-1">
                            {localSkills
                              .filter((s) => s.dependencies.includes(selectedSkill.name))
                              .map((s) => (
                                <button
                                  key={s.id}
                                  onClick={() => setSelectedSkill(s)}
                                  className="rounded-md bg-cyan-500/10 border border-cyan-500/20 px-1.5 py-0.5 text-[10px] font-mono text-cyan-400 hover:bg-cyan-500/20 transition-colors"
                                >
                                  {s.name}
                                </button>
                              ))}
                            {localSkills.filter((s) =>
                              s.dependencies.includes(selectedSkill.name)
                            ).length === 0 && (
                              <span className="text-[10px] text-white/20 italic">None</span>
                            )}
                          </div>
                        </div>
                      </div>
                    </motion.div>
                  ) : (
                    <motion.div
                      key="empty-dep"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      className="rounded-xl border border-white/[0.06] bg-white/[0.01] p-8 text-center"
                    >
                      <GitBranch className="mx-auto h-6 w-6 text-white/15 mb-2" />
                      <p className="text-xs text-white/30">
                        Click a node to explore dependencies
                      </p>
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* File tree */}
                <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 backdrop-blur-xl">
                  <div className="flex items-center gap-2 mb-3">
                    <FolderTree className="h-4 w-4 text-white/40" />
                    <span className="text-xs font-bold text-white/60 uppercase tracking-wider">
                      Installed Skill Files
                    </span>
                  </div>
                  <div className="space-y-0.5 font-mono text-xs">
                    {installedFiles.map((item) => (
                      <div
                        key={item.path}
                        className="flex items-center gap-1.5"
                        style={{ paddingLeft: `${item.depth * 12}px` }}
                      >
                        {item.type === 'dir' ? (
                          <FolderTree className="h-3 w-3 text-amber-400/60 shrink-0" />
                        ) : (
                          <FileText className="h-3 w-3 text-violet-400/60 shrink-0" />
                        )}
                        <span
                          className={
                            item.type === 'dir' ? 'text-amber-400/80' : 'text-white/50'
                          }
                        >
                          {item.path}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </motion.div>
          )}

          {/* TERMINAL VIEW */}
          {viewMode === 'terminal' && (
            <motion.div
              key="terminal"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={SPRING}
              className="flex flex-col lg:flex-row gap-4"
            >
              {/* Skill quick-select */}
              <div className="lg:w-56 shrink-0 space-y-1 max-h-[400px] overflow-y-auto pr-1">
                {filteredSkills
                  .filter((s) => s.installed)
                  .map((skill, i) => {
                    const cat = getCategoryMeta(skill.category);
                    const isSelected = selectedSkill?.id === skill.id;
                    return (
                      <motion.button
                        key={skill.id}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ ...SPRING, delay: i * 0.03 }}
                        onClick={() => setSelectedSkill(skill)}
                        className={`w-full flex items-center gap-2 rounded-lg border p-2.5 text-left transition-colors ${
                          isSelected
                            ? `${cat.borderColor} bg-gradient-to-r ${cat.gradient}`
                            : 'border-white/[0.04] hover:border-white/[0.10] hover:bg-white/[0.02]'
                        }`}
                      >
                        <Zap className={`h-3.5 w-3.5 shrink-0 ${cat.textColor}`} />
                        <span className="text-xs font-mono text-white/70 truncate">
                          {skill.name}
                        </span>
                      </motion.button>
                    );
                  })}
                {filteredSkills.filter((s) => s.installed).length === 0 && (
                  <div className="text-center py-6">
                    <Terminal className="mx-auto h-5 w-5 text-white/15 mb-2" />
                    <p className="text-xs text-white/25">No installed skills to invoke</p>
                  </div>
                )}
              </div>

              {/* Terminal area */}
              <div className="flex-1 space-y-4">
                <MiniTerminal
                  lines={
                    selectedSkill
                      ? terminalLines
                      : [
                          '# Select an installed skill to preview invocation',
                          '$ ms list --installed',
                          `> ${localSkills.filter((s) => s.installed).length} skills installed`,
                        ]
                  }
                  isVisible={true}
                />

                {selectedSkill && (
                  <motion.div
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={SPRING}
                    className="rounded-xl border border-white/[0.06] bg-white/[0.02] p-4"
                  >
                    <span className="text-[10px] font-medium text-white/30 uppercase tracking-wider">
                      Quick Invoke Commands
                    </span>
                    <div className="mt-2 space-y-1.5">
                      {selectedSkill.commands.map((cmd) => (
                        <div
                          key={cmd}
                          className="flex items-center gap-2 rounded-lg bg-black/20 border border-white/[0.04] px-3 py-2 group"
                        >
                          <span className="text-emerald-400 text-xs">$</span>
                          <code className="text-xs font-mono text-white/50 flex-1">{cmd}</code>
                        </div>
                      ))}
                    </div>
                  </motion.div>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
