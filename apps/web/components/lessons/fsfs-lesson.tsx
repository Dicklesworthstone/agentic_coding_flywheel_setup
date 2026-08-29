'use client';

import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Terminal,
  Search,
  Zap,
  Database,
  Play,
  Layers,
  Loader2,
  CheckCircle,
  Merge,
  Clock,
  Brain,
  BookOpen,
  ChevronLeft,
  ChevronRight,
  FileText,
  Hash,
  GitCompare,
  BarChart3,
  Gauge,
  Sparkles,
  ArrowRight,
  Eye,
  Code,
  Globe,
  RotateCcw,
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

export function FsfsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Search your local files at blazing speed with FrankenSearch&apos;s hybrid retrieval engine.
      </GoalBanner>

      {/* Section 1: What Is FSFS */}
      <Section title="What Is FrankenSearch?" icon={<Search className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>FSFS (FrankenSearch)</Highlight> is a two-tier hybrid local search engine
          combining lexical (BM25) and semantic retrieval with progressive delivery.
          It indexes your local files and returns results ranked by both keyword relevance
          and meaning.
        </Paragraph>
        <Paragraph>
          FSFS builds an index once, then serves queries in milliseconds. It supports
          incremental updates so new files are searchable without a full re-index.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="BM25 Lexical Search"
              description="Fast keyword matching with TF-IDF scoring"
              gradient="from-purple-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="Semantic Retrieval"
              description="Embedding-based similarity for meaning-aware results"
              gradient="from-blue-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Progressive Delivery"
              description="Results stream as they're found, fast first results"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Database className="h-5 w-5" />}
              title="Incremental Index"
              description="Only re-indexes changed files for fast updates"
              gradient="from-green-500/20 to-emerald-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'fsfs index .', description: 'Index the current directory' },
            { command: 'fsfs search "query"', description: 'Search indexed files' },
            { command: 'fsfs search --semantic "concept"', description: 'Semantic-only search' },
            { command: 'fsfs status', description: 'Show index statistics' },
          ]}
        />

        <TipBox>
          Use FSFS when you need to search across large codebases or documentation sets
          where simple grep isn&apos;t enough.
        </TipBox>
      </Section>

      <Divider />

      {/* Interactive Hybrid Search Visualization */}
      <Section title="Try It: Hybrid Search Laboratory" icon={<Search className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Explore how <Highlight>FSFS</Highlight> combines keyword matching (BM25) with semantic
          vector search to deliver results that neither approach can achieve alone. Step through
          different query scenarios and watch the full search pipeline animate.
        </Paragraph>
        <div className="mt-6">
          <InteractiveHybridSearch />
        </div>
      </Section>

      <Divider />

      {/* Section 3: Common Scenarios */}
      <Section title="Common Scenarios" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Index a project
fsfs index ~/projects/my-app

# Search for error handling patterns
fsfs search "error handling retry"

# Find conceptually similar code
fsfs search --semantic "authentication middleware"`} />
      </Section>
    </div>
  );
}

/* =========================================================================
   CONSTANTS
   ========================================================================= */

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };
const SPRING_SNAPPY = { type: 'spring' as const, stiffness: 400, damping: 35 };

/* =========================================================================
   DATA TYPES & SCENARIO DATA
   ========================================================================= */

interface HybridResult {
  id: string;
  title: string;
  file: string;
  snippet: string;
  bm25Score: number;
  cosineScore: number;
  fusedScore: number;
  keywordMatches: string[];
  semanticLinks: string[];
}

interface PipelineToken {
  text: string;
  isHighlighted: boolean;
}

interface QueryScenario {
  id: string;
  label: string;
  icon: React.ReactNode;
  query: string;
  description: string;
  tokens: PipelineToken[];
  results: HybridResult[];
  bm25TimeMs: number;
  vectorTimeMs: number;
  fusionTimeMs: number;
  insight: string;
  command: string;
}

const SCENARIOS: QueryScenario[] = [
  {
    id: 'exact',
    label: 'Exact Match',
    icon: <Hash className="h-3.5 w-3.5" />,
    query: 'retryWithBackoff',
    description: 'Exact function name lookup -- BM25 dominates because tokens match perfectly.',
    tokens: [{ text: 'retryWithBackoff', isHighlighted: true }],
    results: [
      {
        id: 'e1', title: 'retryWithBackoff()', file: 'src/utils/retry.ts',
        snippet: 'export function retryWithBackoff(fn, maxRetries = 3) { ... }',
        bm25Score: 0.98, cosineScore: 0.72, fusedScore: 0.96,
        keywordMatches: ['retryWithBackoff'], semanticLinks: ['retry logic'],
      },
      {
        id: 'e2', title: 'fetchWithRetry()', file: 'src/api/client.ts',
        snippet: 'const result = await retryWithBackoff(() => fetch(url));',
        bm25Score: 0.85, cosineScore: 0.68, fusedScore: 0.82,
        keywordMatches: ['retryWithBackoff'], semanticLinks: ['HTTP retry'],
      },
      {
        id: 'e3', title: 'CircuitBreaker', file: 'src/resilience/circuit.ts',
        snippet: 'Falls back to retryWithBackoff when circuit is half-open',
        bm25Score: 0.61, cosineScore: 0.79, fusedScore: 0.73,
        keywordMatches: ['retryWithBackoff'], semanticLinks: ['fault tolerance'],
      },
    ],
    bm25TimeMs: 8, vectorTimeMs: 310, fusionTimeMs: 4,
    insight: 'BM25 finds the exact token instantly. Semantic search still adds the CircuitBreaker result which is conceptually related.',
    command: 'fsfs search "retryWithBackoff"',
  },
  {
    id: 'semantic',
    label: 'Semantic Similarity',
    icon: <Brain className="h-3.5 w-3.5" />,
    query: 'prevent cascading failures',
    description: 'No code uses this exact phrase -- semantic embeddings find related concepts.',
    tokens: [
      { text: 'prevent', isHighlighted: false },
      { text: 'cascading', isHighlighted: true },
      { text: 'failures', isHighlighted: true },
    ],
    results: [
      {
        id: 's1', title: 'CircuitBreaker', file: 'src/resilience/circuit.ts',
        snippet: 'Implements circuit-breaker pattern to stop cascading failures',
        bm25Score: 0.31, cosineScore: 0.95, fusedScore: 0.88,
        keywordMatches: ['failures'], semanticLinks: ['cascading failure prevention', 'circuit breaker'],
      },
      {
        id: 's2', title: 'BulkheadIsolation', file: 'src/resilience/bulkhead.ts',
        snippet: 'Isolates failures in one service from propagating to others',
        bm25Score: 0.12, cosineScore: 0.91, fusedScore: 0.78,
        keywordMatches: [], semanticLinks: ['fault isolation', 'resilience'],
      },
      {
        id: 's3', title: 'retryWithBackoff()', file: 'src/utils/retry.ts',
        snippet: 'Prevents transient errors from becoming permanent failures',
        bm25Score: 0.25, cosineScore: 0.82, fusedScore: 0.70,
        keywordMatches: ['failures'], semanticLinks: ['transient fault handling'],
      },
      {
        id: 's4', title: 'HealthCheck', file: 'src/monitoring/health.ts',
        snippet: 'Monitors upstream dependencies and triggers alerts on degradation',
        bm25Score: 0.05, cosineScore: 0.76, fusedScore: 0.58,
        keywordMatches: [], semanticLinks: ['system health', 'degradation detection'],
      },
    ],
    bm25TimeMs: 6, vectorTimeMs: 380, fusionTimeMs: 5,
    insight: 'BM25 barely matches (no exact terms in code). Semantic search finds 4 highly relevant results by understanding the intent.',
    command: 'fsfs search --semantic "prevent cascading failures"',
  },
  {
    id: 'typo',
    label: 'Typo-Tolerant',
    icon: <Eye className="h-3.5 w-3.5" />,
    query: 'authenication middlewar',
    description: 'Misspelled query -- BM25 fails on typos but semantic embeddings handle fuzzy meaning.',
    tokens: [
      { text: 'authenication', isHighlighted: true },
      { text: 'middlewar', isHighlighted: true },
    ],
    results: [
      {
        id: 't1', title: 'authMiddleware()', file: 'src/middleware/auth.ts',
        snippet: 'export const authMiddleware = (req, res, next) => { verifyToken(req)... }',
        bm25Score: 0.15, cosineScore: 0.92, fusedScore: 0.80,
        keywordMatches: [], semanticLinks: ['authentication', 'middleware pattern'],
      },
      {
        id: 't2', title: 'sessionValidator()', file: 'src/middleware/session.ts',
        snippet: 'Validates JWT tokens and refreshes expired sessions automatically',
        bm25Score: 0.03, cosineScore: 0.87, fusedScore: 0.68,
        keywordMatches: [], semanticLinks: ['session auth', 'JWT validation'],
      },
      {
        id: 't3', title: 'requireAuth', file: 'src/decorators/auth.ts',
        snippet: '@requireAuth({ roles: ["admin"] }) async handleRequest() { ... }',
        bm25Score: 0.08, cosineScore: 0.81, fusedScore: 0.63,
        keywordMatches: [], semanticLinks: ['role-based access', 'auth decorator'],
      },
    ],
    bm25TimeMs: 5, vectorTimeMs: 295, fusionTimeMs: 3,
    insight: 'BM25 scores near zero because the typos mismatch exact tokens. Semantic search recovers perfectly because the embedding captures intent.',
    command: 'fsfs search "authenication middlewar"',
  },
  {
    id: 'code',
    label: 'Code Search',
    icon: <Code className="h-3.5 w-3.5" />,
    query: 'async function* yield',
    description: 'Searching for a code pattern -- BM25 matches syntax tokens, semantics finds generators.',
    tokens: [
      { text: 'async', isHighlighted: true },
      { text: 'function*', isHighlighted: true },
      { text: 'yield', isHighlighted: true },
    ],
    results: [
      {
        id: 'c1', title: 'streamResults()', file: 'src/search/streamer.ts',
        snippet: 'async function* streamResults(query) { for await (const batch of ...) yield batch; }',
        bm25Score: 0.93, cosineScore: 0.88, fusedScore: 0.95,
        keywordMatches: ['async', 'function*', 'yield'], semanticLinks: ['async generator', 'streaming'],
      },
      {
        id: 'c2', title: 'paginateQuery()', file: 'src/db/paginator.ts',
        snippet: 'async function* paginateQuery(sql, pageSize = 100) { yield* chunks; }',
        bm25Score: 0.87, cosineScore: 0.82, fusedScore: 0.89,
        keywordMatches: ['async', 'function*', 'yield'], semanticLinks: ['pagination', 'lazy evaluation'],
      },
      {
        id: 'c3', title: 'EventEmitter', file: 'src/events/emitter.ts',
        snippet: 'Async iterable that yields events as they arrive from the bus',
        bm25Score: 0.42, cosineScore: 0.85, fusedScore: 0.74,
        keywordMatches: ['yield'], semanticLinks: ['async iteration', 'event stream'],
      },
    ],
    bm25TimeMs: 11, vectorTimeMs: 340, fusionTimeMs: 4,
    insight: 'Both engines contribute strongly. BM25 catches exact syntax matches while semantic search finds the conceptually related EventEmitter.',
    command: 'fsfs search "async function* yield"',
  },
  {
    id: 'multilang',
    label: 'Multi-Language',
    icon: <Globe className="h-3.5 w-3.5" />,
    query: 'Fehlerbehandlung Wiederholung',
    description: 'German query for "error handling retry" -- BM25 cannot match, semantic embeddings bridge languages.',
    tokens: [
      { text: 'Fehlerbehandlung', isHighlighted: true },
      { text: 'Wiederholung', isHighlighted: true },
    ],
    results: [
      {
        id: 'm1', title: 'retryWithBackoff()', file: 'src/utils/retry.ts',
        snippet: 'export function retryWithBackoff(fn, maxRetries = 3) { ... }',
        bm25Score: 0.0, cosineScore: 0.89, fusedScore: 0.68,
        keywordMatches: [], semanticLinks: ['retry = Wiederholung', 'error handling'],
      },
      {
        id: 'm2', title: 'ErrorBoundary', file: 'src/components/ErrorBoundary.tsx',
        snippet: 'class ErrorBoundary extends React.Component { handleError() ... }',
        bm25Score: 0.0, cosineScore: 0.84, fusedScore: 0.63,
        keywordMatches: [], semanticLinks: ['Fehlerbehandlung = error handling'],
      },
      {
        id: 'm3', title: 'gracefulDegradation()', file: 'src/utils/fallback.ts',
        snippet: 'Returns cached result when upstream service is unavailable',
        bm25Score: 0.0, cosineScore: 0.77, fusedScore: 0.56,
        keywordMatches: [], semanticLinks: ['fault tolerance', 'graceful fallback'],
      },
    ],
    bm25TimeMs: 3, vectorTimeMs: 420, fusionTimeMs: 3,
    insight: 'BM25 returns zero results (no German tokens in codebase). Semantic search bridges the language gap via multilingual embeddings.',
    command: 'fsfs search --semantic "Fehlerbehandlung Wiederholung"',
  },
  {
    id: 'rerank',
    label: 'Re-Ranking',
    icon: <BarChart3 className="h-3.5 w-3.5" />,
    query: 'database connection pool',
    description: 'Classic hybrid query -- watch how fusion re-ranks results from both engines for optimal ordering.',
    tokens: [
      { text: 'database', isHighlighted: false },
      { text: 'connection', isHighlighted: true },
      { text: 'pool', isHighlighted: true },
    ],
    results: [
      {
        id: 'r1', title: 'createPool()', file: 'src/db/pool.ts',
        snippet: 'export function createPool(config: PoolConfig) { return new Pool(config) }',
        bm25Score: 0.95, cosineScore: 0.88, fusedScore: 0.96,
        keywordMatches: ['database', 'connection', 'pool'], semanticLinks: ['connection pooling'],
      },
      {
        id: 'r2', title: 'ConnectionManager', file: 'src/db/manager.ts',
        snippet: 'Manages lifecycle of database connections with health checks and eviction',
        bm25Score: 0.72, cosineScore: 0.92, fusedScore: 0.89,
        keywordMatches: ['database', 'connection'], semanticLinks: ['connection lifecycle', 'resource management'],
      },
      {
        id: 'r3', title: 'DatabaseConfig', file: 'src/config/database.ts',
        snippet: 'interface DatabaseConfig { host, port, pool: { min: 2, max: 10 } }',
        bm25Score: 0.88, cosineScore: 0.65, fusedScore: 0.83,
        keywordMatches: ['database', 'pool'], semanticLinks: ['configuration'],
      },
      {
        id: 'r4', title: 'migrationRunner()', file: 'src/db/migrate.ts',
        snippet: 'Runs pending schema migrations using pooled connections',
        bm25Score: 0.35, cosineScore: 0.69, fusedScore: 0.60,
        keywordMatches: ['pool'], semanticLinks: ['schema migration', 'pooled connections'],
      },
    ],
    bm25TimeMs: 10, vectorTimeMs: 410, fusionTimeMs: 6,
    insight: 'ConnectionManager jumps from #3 (BM25) to #2 (fused) because its high semantic score boosts it above DatabaseConfig.',
    command: 'fsfs search "database connection pool"',
  },
];

/* =========================================================================
   PIPELINE PHASE TYPES
   ========================================================================= */

type PipelineStage =
  | 'idle'
  | 'tokenize'
  | 'keyword-index'
  | 'vector-embed'
  | 'score-fusion'
  | 'ranked'
  | 'done';

const PIPELINE_STAGES: { key: PipelineStage; label: string; icon: React.ReactNode }[] = [
  { key: 'tokenize', label: 'Tokenize', icon: <Hash className="h-3 w-3" /> },
  { key: 'keyword-index', label: 'BM25 Index', icon: <BookOpen className="h-3 w-3" /> },
  { key: 'vector-embed', label: 'Embed', icon: <Brain className="h-3 w-3" /> },
  { key: 'score-fusion', label: 'Fuse Scores', icon: <Merge className="h-3 w-3" /> },
  { key: 'ranked', label: 'Rank', icon: <BarChart3 className="h-3 w-3" /> },
];

function stageIndex(stage: PipelineStage): number {
  if (stage === 'idle') return -1;
  if (stage === 'done') return PIPELINE_STAGES.length;
  return PIPELINE_STAGES.findIndex((s) => s.key === stage);
}

/* =========================================================================
   SCORE BAR COMPONENT
   ========================================================================= */

function ScoreBar({
  value,
  color,
  label,
  delay,
}: {
  value: number;
  color: string;
  label: string;
  delay: number;
}) {
  const pct = Math.round(value * 100);
  return (
    <div className="flex items-center gap-2">
      <span className="w-10 text-[10px] font-mono text-white/40 text-right">{label}</span>
      <div className="flex-1 h-3 rounded-full bg-white/[0.04] overflow-hidden">
        <motion.div
          initial={{ width: 0 }}
          animate={{ width: `${pct}%` }}
          transition={{ ...SPRING, delay }}
          className={`h-full rounded-full ${color}`}
        />
      </div>
      <span className="w-9 text-[10px] font-mono text-white/50 text-right">{pct}%</span>
    </div>
  );
}

/* =========================================================================
   SCENARIO STEPPER
   ========================================================================= */

function ScenarioStepper({
  scenarios,
  activeIndex,
  onPrev,
  onNext,
  onSelect,
  disabled,
}: {
  scenarios: QueryScenario[];
  activeIndex: number;
  onPrev: () => void;
  onNext: () => void;
  onSelect: (idx: number) => void;
  disabled: boolean;
}) {
  return (
    <div className="flex items-center justify-center gap-3">
      <motion.button
        type="button"
        onClick={onPrev}
        disabled={disabled}
        whileHover={disabled ? {} : { scale: 1.1 }}
        whileTap={disabled ? {} : { scale: 0.9 }}
        transition={SPRING}
        className="flex h-8 w-8 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 disabled:opacity-30 transition-colors"
      >
        <ChevronLeft className="h-4 w-4" />
      </motion.button>

      <div className="flex items-center gap-1.5">
        {scenarios.map((s, idx) => (
          <motion.button
            key={s.id}
            type="button"
            onClick={() => onSelect(idx)}
            disabled={disabled}
            whileHover={disabled ? {} : { scale: 1.2 }}
            whileTap={disabled ? {} : { scale: 0.9 }}
            transition={SPRING}
            className="relative"
          >
            <div
              className={`h-2 rounded-full transition-[width,background-color] duration-300 ${
                idx === activeIndex
                  ? 'w-6 bg-purple-400'
                  : 'w-2 bg-white/20 hover:bg-white/40'
              }`}
            />
            {idx === activeIndex && (
              <motion.div
                layoutId="fsfs-stepper-glow"
                className="absolute inset-0 -m-1 rounded-full bg-purple-400/20 blur-sm"
                transition={SPRING}
              />
            )}
          </motion.button>
        ))}
      </div>

      <motion.button
        type="button"
        onClick={onNext}
        disabled={disabled}
        whileHover={disabled ? {} : { scale: 1.1 }}
        whileTap={disabled ? {} : { scale: 0.9 }}
        transition={SPRING}
        className="flex h-8 w-8 items-center justify-center rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/70 disabled:opacity-30 transition-colors"
      >
        <ChevronRight className="h-4 w-4" />
      </motion.button>

      <span className="ml-2 text-[10px] font-mono text-white/30">
        {activeIndex + 1}/{scenarios.length}
      </span>
    </div>
  );
}

/* =========================================================================
   PIPELINE PROGRESS BAR
   ========================================================================= */

function PipelineProgress({ stage }: { stage: PipelineStage }) {
  const currentIdx = stageIndex(stage);
  return (
    <div className="flex items-center gap-1">
      {PIPELINE_STAGES.map((s, idx) => {
        const isComplete = currentIdx > idx;
        const isActive = currentIdx === idx;
        return (
          <div key={s.key} className="flex items-center gap-1">
            <motion.div
              animate={{
                backgroundColor: isComplete
                  ? 'rgba(168,85,247,0.35)'
                  : isActive
                    ? 'rgba(168,85,247,0.2)'
                    : 'rgba(255,255,255,0.04)',
                borderColor: isComplete
                  ? 'rgba(168,85,247,0.5)'
                  : isActive
                    ? 'rgba(168,85,247,0.4)'
                    : 'rgba(255,255,255,0.08)',
              }}
              transition={SPRING}
              className="flex items-center gap-1.5 rounded-lg border px-2 py-1"
            >
              <span className={isComplete ? 'text-purple-300' : isActive ? 'text-purple-400' : 'text-white/30'}>
                {isComplete ? <CheckCircle className="h-3 w-3" /> : s.icon}
              </span>
              <span
                className={`text-[10px] font-medium ${
                  isComplete ? 'text-purple-300' : isActive ? 'text-purple-400' : 'text-white/30'
                }`}
              >
                {s.label}
              </span>
              {isActive && (
                <Loader2 className="h-2.5 w-2.5 text-purple-400 animate-spin" />
              )}
            </motion.div>
            {idx < PIPELINE_STAGES.length - 1 && (
              <motion.div
                animate={{
                  backgroundColor: isComplete ? 'rgba(168,85,247,0.4)' : 'rgba(255,255,255,0.08)',
                }}
                transition={SPRING}
                className="h-px w-3"
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

/* =========================================================================
   RESULT CARD
   ========================================================================= */

function ResultCard({
  result,
  index,
  showScores,
}: {
  result: HybridResult;
  index: number;
  showScores: boolean;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ ...SPRING, delay: index * 0.06 }}
      className="rounded-lg border border-white/[0.08] bg-white/[0.02] p-3 space-y-2"
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <FileText className="h-3 w-3 text-white/30 flex-shrink-0" />
          <span className="text-xs font-semibold text-white truncate">{result.title}</span>
        </div>
        <span className="flex-shrink-0 text-[10px] font-mono text-amber-300/70">
          {(result.fusedScore * 100).toFixed(0)}%
        </span>
      </div>

      <p className="text-[11px] font-mono text-white/30 truncate">{result.file}</p>

      {/* Snippet with keyword highlights */}
      <p className="text-xs text-white/50 leading-relaxed">
        {result.keywordMatches.length > 0
          ? highlightSnippet(result.snippet, result.keywordMatches)
          : result.snippet}
      </p>

      {/* Semantic links */}
      {result.semanticLinks.length > 0 && (
        <div className="flex flex-wrap gap-1 pt-1">
          {result.semanticLinks.map((link) => (
            <span
              key={link}
              className="inline-flex items-center gap-1 rounded-full bg-cyan-500/10 border border-cyan-500/20 px-2 py-0.5 text-[10px] font-medium text-cyan-400/70"
            >
              <Brain className="h-2 w-2" />
              {link}
            </span>
          ))}
        </div>
      )}

      {/* Score comparison bars */}
      <AnimatePresence>
        {showScores && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={SPRING}
            className="space-y-1 pt-2 border-t border-white/[0.05] overflow-hidden"
          >
            <ScoreBar value={result.bm25Score} color="bg-gradient-to-r from-purple-500/60 to-purple-400/40" label="BM25" delay={index * 0.04} />
            <ScoreBar value={result.cosineScore} color="bg-gradient-to-r from-cyan-500/60 to-cyan-400/40" label="Cos" delay={index * 0.04 + 0.05} />
            <ScoreBar value={result.fusedScore} color="bg-gradient-to-r from-amber-500/60 to-amber-400/40" label="Fused" delay={index * 0.04 + 0.1} />
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

/* =========================================================================
   RELEVANCE GAUGE
   ========================================================================= */

function RelevanceGauge({
  bm25Avg,
  cosineAvg,
  fusedAvg,
}: {
  bm25Avg: number;
  cosineAvg: number;
  fusedAvg: number;
}) {
  const improvement = fusedAvg > 0 ? Math.round(((fusedAvg - Math.max(bm25Avg, cosineAvg)) / Math.max(bm25Avg, cosineAvg, 0.01)) * 100) : 0;
  const arcRadius = 42;
  const circumference = Math.PI * arcRadius;

  return (
    <div className="flex flex-col items-center gap-3">
      <div className="relative w-24 h-14">
        <svg viewBox="0 0 100 60" className="w-full h-full">
          {/* Background arc */}
          <path
            d="M 8 55 A 42 42 0 0 1 92 55"
            fill="none"
            stroke="rgba(255,255,255,0.06)"
            strokeWidth="6"
            strokeLinecap="round"
          />
          {/* Fused score arc */}
          <motion.path
            d="M 8 55 A 42 42 0 0 1 92 55"
            fill="none"
            stroke="url(#fsfs-gaugeGradient)"
            strokeWidth="6"
            strokeLinecap="round"
            initial={{ pathLength: 0 }}
            animate={{ pathLength: fusedAvg }}
            transition={{ ...SPRING, delay: 0.2 }}
            style={{
              pathLength: 0,
              strokeDasharray: circumference,
              strokeDashoffset: 0,
            }}
          />
          <defs>
            <linearGradient id="fsfs-gaugeGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="rgb(168,85,247)" />
              <stop offset="50%" stopColor="rgb(6,182,212)" />
              <stop offset="100%" stopColor="rgb(245,158,11)" />
            </linearGradient>
          </defs>
        </svg>
        <div className="absolute inset-x-0 bottom-0 text-center">
          <span className="text-base font-bold text-white">{Math.round(fusedAvg * 100)}%</span>
        </div>
      </div>
      <div className="text-center space-y-1">
        <p className="text-[10px] font-medium text-white/50">Hybrid Relevance</p>
        {improvement > 0 && (
          <motion.p
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            transition={SPRING}
            className="text-[10px] font-semibold text-emerald-400"
          >
            +{improvement}% vs best single engine
          </motion.p>
        )}
      </div>
    </div>
  );
}

/* =========================================================================
   MINI TERMINAL
   ========================================================================= */

function MiniTerminal({ command, isRunning }: { command: string; isRunning: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });
  return (
    <div ref={ref} className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-1.5 border-b border-white/[0.06] bg-white/[0.02]">
        <div className="flex gap-1.5">
          <div className="h-2 w-2 rounded-full bg-red-500/40" />
          <div className="h-2 w-2 rounded-full bg-yellow-500/40" />
          <div className="h-2 w-2 rounded-full bg-green-500/40" />
        </div>
        <span className="text-[10px] font-mono text-white/30">terminal</span>
      </div>
      <div className="px-3 py-2.5 font-mono text-[11px]">
        <div className="flex items-center gap-2">
          <span className="text-emerald-400/70">$</span>
          <span className="text-white/70">{command}</span>
          {isRunning && (
            <motion.span
              animate={inView ? { opacity: [1, 0] } : { opacity: 1 }}
              transition={inView ? { duration: 0.6, repeat: Infinity, repeatType: 'reverse' } : { duration: 0.2 }}
              className="inline-block w-1.5 h-3.5 bg-white/50"
            />
          )}
        </div>
      </div>
    </div>
  );
}

/* =========================================================================
   HELPERS
   ========================================================================= */

function highlightSnippet(text: string, keywords: string[]): React.ReactNode {
  if (keywords.length === 0) return text;
  const escapedKeywords = keywords.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  const pattern = new RegExp(`(${escapedKeywords.join('|')})`, 'gi');
  const parts = text.split(pattern);
  return parts.map((part, i) => {
    const isMatch = keywords.some((k) => k.toLowerCase() === part.toLowerCase());
    if (isMatch) {
      return (
        <span key={i} className="bg-purple-500/25 text-purple-200 rounded px-0.5">
          {part}
        </span>
      );
    }
    return part;
  });
}

/* =========================================================================
   MAIN INTERACTIVE COMPONENT
   ========================================================================= */

function InteractiveHybridSearch() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [stage, setStage] = useState<PipelineStage>('idle');
  const [visibleResults, setVisibleResults] = useState<HybridResult[]>([]);
  const [showScores, setShowScores] = useState(false);

  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const scenario = SCENARIOS[scenarioIdx];

  const cleanup = useCallback(() => {
    for (const t of timersRef.current) clearTimeout(t);
    timersRef.current = [];
  }, []);

  useEffect(() => {
    return cleanup;
  }, [cleanup]);

  // Compute averages for gauge
  const scoreAverages = useMemo(() => {
    if (visibleResults.length === 0) return { bm25: 0, cosine: 0, fused: 0 };
    const n = visibleResults.length;
    return {
      bm25: visibleResults.reduce((s, r) => s + r.bm25Score, 0) / n,
      cosine: visibleResults.reduce((s, r) => s + r.cosineScore, 0) / n,
      fused: visibleResults.reduce((s, r) => s + r.fusedScore, 0) / n,
    };
  }, [visibleResults]);

  const runPipeline = useCallback(
    (idx: number) => {
      cleanup();
      setScenarioIdx(idx);
      setVisibleResults([]);
      setShowScores(false);

      const sc = SCENARIOS[idx];
      let elapsed = 0;

      // Stage 1: tokenize
      const t1 = setTimeout(() => setStage('tokenize'), 50);
      elapsed += 350;
      timersRef.current.push(t1);

      // Stage 2: keyword index
      const t2 = setTimeout(() => setStage('keyword-index'), elapsed);
      elapsed += 400;
      timersRef.current.push(t2);

      // Stage 3: vector embed
      const t3 = setTimeout(() => setStage('vector-embed'), elapsed);
      elapsed += 500;
      timersRef.current.push(t3);

      // Stage 4: score fusion
      const t4 = setTimeout(() => setStage('score-fusion'), elapsed);
      elapsed += 400;
      timersRef.current.push(t4);

      // Stage 5: ranked -> stream results
      const t5 = setTimeout(() => setStage('ranked'), elapsed);
      timersRef.current.push(t5);

      // Stream in results one by one
      sc.results.forEach((result, i) => {
        const rt = setTimeout(() => {
          setVisibleResults((prev) => [...prev, result]);
        }, elapsed + 120 * (i + 1));
        timersRef.current.push(rt);
      });

      // Done
      const doneTime = elapsed + 120 * (sc.results.length + 1) + 200;
      const t6 = setTimeout(() => {
        setStage('done');
        const scoreTimer = setTimeout(() => setShowScores(true), 300);
        timersRef.current.push(scoreTimer);
      }, doneTime);
      timersRef.current.push(t6);
    },
    [cleanup],
  );

  const handlePrev = useCallback(() => {
    const next = scenarioIdx <= 0 ? SCENARIOS.length - 1 : scenarioIdx - 1;
    runPipeline(next);
  }, [scenarioIdx, runPipeline]);

  const handleNext = useCallback(() => {
    const next = scenarioIdx >= SCENARIOS.length - 1 ? 0 : scenarioIdx + 1;
    runPipeline(next);
  }, [scenarioIdx, runPipeline]);

  const handleReset = useCallback(() => {
    cleanup();
    setStage('idle');
    setVisibleResults([]);
    setShowScores(false);
  }, [cleanup]);

  const isRunning = stage !== 'idle' && stage !== 'done';

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-purple-500/20 to-cyan-500/20 border border-purple-500/30">
            <GitCompare className="h-4 w-4 text-purple-400" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-white">Hybrid Search Laboratory</h3>
            <p className="text-xs text-white/40">
              Compare BM25 vs semantic vs hybrid fusion across 6 scenarios
            </p>
          </div>
        </div>
        {stage !== 'idle' && (
          <motion.button
            type="button"
            onClick={handleReset}
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING_SNAPPY}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="flex items-center gap-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] px-3 py-1.5 text-[10px] font-medium text-white/40 hover:text-white/60 transition-colors"
          >
            <RotateCcw className="h-3 w-3" />
            Reset
          </motion.button>
        )}
      </div>

      {/* Scenario Stepper */}
      <ScenarioStepper
        scenarios={SCENARIOS}
        activeIndex={scenarioIdx}
        onPrev={handlePrev}
        onNext={handleNext}
        onSelect={(idx) => runPipeline(idx)}
        disabled={isRunning}
      />

      {/* Scenario Label Chips */}
      <div className="flex flex-wrap gap-2 justify-center">
        {SCENARIOS.map((s, idx) => {
          const active = idx === scenarioIdx;
          return (
            <motion.button
              key={s.id}
              type="button"
              onClick={() => runPipeline(idx)}
              disabled={isRunning}
              whileHover={isRunning ? {} : { scale: 1.03 }}
              whileTap={isRunning ? {} : { scale: 0.97 }}
              transition={SPRING}
              className={`flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-[11px] font-medium transition-colors ${
                active
                  ? 'border-purple-500/40 bg-gradient-to-r from-purple-500/15 to-cyan-500/15 text-white'
                  : 'border-white/[0.08] bg-white/[0.02] text-white/40 hover:border-white/[0.15] hover:text-white/60 disabled:opacity-40'
              }`}
            >
              {s.icon}
              {s.label}
            </motion.button>
          );
        })}
      </div>

      {/* Active scenario description */}
      <AnimatePresence mode="wait">
        <motion.div
          key={scenario.id}
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -6 }}
          transition={SPRING}
          className="text-center"
        >
          <p className="text-xs text-white/40 max-w-lg mx-auto">{scenario.description}</p>
        </motion.div>
      </AnimatePresence>

      {/* Play button (idle state) */}
      {stage === 'idle' && (
        <div className="flex justify-center">
          <motion.button
            type="button"
            onClick={() => runPipeline(scenarioIdx)}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={SPRING_SNAPPY}
            className="flex items-center gap-2 rounded-2xl border border-purple-500/30 bg-gradient-to-r from-purple-500/15 to-cyan-500/15 px-6 py-3 text-sm font-medium text-white hover:from-purple-500/25 hover:to-cyan-500/25 transition-colors"
          >
            <Play className="h-4 w-4 text-purple-400" />
            Run Search Pipeline
          </motion.button>
        </div>
      )}

      {/* Pipeline visualization (running / done) */}
      <AnimatePresence>
        {stage !== 'idle' && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={SPRING}
            className="space-y-5 overflow-hidden"
          >
            {/* Mini terminal */}
            <MiniTerminal command={scenario.command} isRunning={isRunning} />

            {/* Pipeline progress */}
            <div className="overflow-x-auto pb-1">
              <PipelineProgress stage={stage} />
            </div>

            {/* Tokenization display */}
            <AnimatePresence>
              {stageIndex(stage) >= 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={SPRING}
                  className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4"
                >
                  <p className="text-[10px] font-medium text-white/40 mb-2">Query Tokens</p>
                  <div className="flex flex-wrap gap-2">
                    {scenario.tokens.map((tok, i) => (
                      <motion.span
                        key={tok.text}
                        initial={{ opacity: 0, scale: 0.8 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ ...SPRING, delay: i * 0.08 }}
                        className={`inline-flex items-center gap-1 rounded-lg border px-2.5 py-1 text-xs font-mono ${
                          tok.isHighlighted
                            ? 'border-purple-500/30 bg-purple-500/10 text-purple-300'
                            : 'border-white/[0.08] bg-white/[0.02] text-white/50'
                        }`}
                      >
                        <Hash className="h-2.5 w-2.5" />
                        {tok.text}
                      </motion.span>
                    ))}
                    <motion.span
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ ...SPRING, delay: 0.3 }}
                      className="flex items-center text-[10px] text-white/20"
                    >
                      <ArrowRight className="h-3 w-3 mx-1" />
                      BM25 + Vector
                    </motion.span>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Split view: BM25 vs Semantic vs Hybrid */}
            <AnimatePresence>
              {stageIndex(stage) >= 1 && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={SPRING}
                  className="grid grid-cols-1 md:grid-cols-3 gap-3"
                >
                  {/* BM25 Column */}
                  <div className="rounded-xl border border-purple-500/20 bg-purple-500/[0.03] p-3 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        <BookOpen className="h-3 w-3 text-purple-400" />
                        <span className="text-[11px] font-semibold text-purple-300">BM25</span>
                      </div>
                      <span className="text-[10px] font-mono text-purple-400/60">
                        {stage === 'done' || stageIndex(stage) >= 2
                          ? `${scenario.bm25TimeMs}ms`
                          : '...'}
                      </span>
                    </div>
                    <div className="space-y-1.5 min-h-[80px]">
                      <AnimatePresence>
                        {visibleResults.map((r, i) => (
                          <motion.div
                            key={r.id + '-bm25'}
                            initial={{ opacity: 0, x: -6 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{ ...SPRING, delay: i * 0.04 }}
                            className="rounded-lg border border-purple-500/10 bg-purple-500/[0.02] px-2.5 py-1.5"
                          >
                            <div className="flex items-center justify-between gap-1">
                              <span className="text-[10px] font-medium text-white/60 truncate">
                                {r.title}
                              </span>
                              <span className="text-[10px] font-mono text-purple-300/70 flex-shrink-0">
                                {Math.round(r.bm25Score * 100)}%
                              </span>
                            </div>
                            <div className="mt-1 h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
                              <motion.div
                                initial={{ width: 0 }}
                                animate={{ width: `${r.bm25Score * 100}%` }}
                                transition={{ ...SPRING, delay: i * 0.04 }}
                                className="h-full rounded-full bg-purple-500/50"
                              />
                            </div>
                          </motion.div>
                        ))}
                      </AnimatePresence>
                      {visibleResults.length === 0 && isRunning && (
                        <div className="flex items-center justify-center py-6 text-white/20 text-[10px]">
                          <Loader2 className="h-3 w-3 animate-spin mr-1.5" />
                          Scanning...
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Semantic Column */}
                  <div className="rounded-xl border border-cyan-500/20 bg-cyan-500/[0.03] p-3 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        <Brain className="h-3 w-3 text-cyan-400" />
                        <span className="text-[11px] font-semibold text-cyan-300">Semantic</span>
                      </div>
                      <span className="text-[10px] font-mono text-cyan-400/60">
                        {stage === 'done' || stageIndex(stage) >= 3
                          ? `${scenario.vectorTimeMs}ms`
                          : '...'}
                      </span>
                    </div>
                    <div className="space-y-1.5 min-h-[80px]">
                      <AnimatePresence>
                        {visibleResults.map((r, i) => (
                          <motion.div
                            key={r.id + '-cos'}
                            initial={{ opacity: 0, x: -6 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{ ...SPRING, delay: i * 0.04 + 0.05 }}
                            className="rounded-lg border border-cyan-500/10 bg-cyan-500/[0.02] px-2.5 py-1.5"
                          >
                            <div className="flex items-center justify-between gap-1">
                              <span className="text-[10px] font-medium text-white/60 truncate">
                                {r.title}
                              </span>
                              <span className="text-[10px] font-mono text-cyan-300/70 flex-shrink-0">
                                {Math.round(r.cosineScore * 100)}%
                              </span>
                            </div>
                            <div className="mt-1 h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
                              <motion.div
                                initial={{ width: 0 }}
                                animate={{ width: `${r.cosineScore * 100}%` }}
                                transition={{ ...SPRING, delay: i * 0.04 + 0.05 }}
                                className="h-full rounded-full bg-cyan-500/50"
                              />
                            </div>
                          </motion.div>
                        ))}
                      </AnimatePresence>
                      {visibleResults.length === 0 && isRunning && (
                        <div className="flex items-center justify-center py-6 text-white/20 text-[10px]">
                          <Loader2 className="h-3 w-3 animate-spin mr-1.5" />
                          Embedding...
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Fused Column */}
                  <div className="rounded-xl border border-amber-500/20 bg-amber-500/[0.03] p-3 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        <Merge className="h-3 w-3 text-amber-400" />
                        <span className="text-[11px] font-semibold text-amber-300">Hybrid Fused</span>
                      </div>
                      <span className="text-[10px] font-mono text-amber-400/60">
                        {stage === 'done'
                          ? `${scenario.fusionTimeMs}ms`
                          : '...'}
                      </span>
                    </div>
                    <div className="space-y-1.5 min-h-[80px]">
                      <AnimatePresence>
                        {visibleResults.map((r, i) => (
                          <motion.div
                            key={r.id + '-fused'}
                            initial={{ opacity: 0, x: -6 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{ ...SPRING, delay: i * 0.04 + 0.1 }}
                            className="rounded-lg border border-amber-500/10 bg-amber-500/[0.02] px-2.5 py-1.5"
                          >
                            <div className="flex items-center justify-between gap-1">
                              <span className="text-[10px] font-medium text-white/60 truncate">
                                {r.title}
                              </span>
                              <span className="text-[10px] font-mono text-amber-300/70 flex-shrink-0">
                                {Math.round(r.fusedScore * 100)}%
                              </span>
                            </div>
                            <div className="mt-1 h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
                              <motion.div
                                initial={{ width: 0 }}
                                animate={{ width: `${r.fusedScore * 100}%` }}
                                transition={{ ...SPRING, delay: i * 0.04 + 0.1 }}
                                className="h-full rounded-full bg-gradient-to-r from-purple-500/40 via-cyan-500/40 to-amber-500/50"
                              />
                            </div>
                          </motion.div>
                        ))}
                      </AnimatePresence>
                      {visibleResults.length === 0 && isRunning && (
                        <div className="flex items-center justify-center py-6 text-white/20 text-[10px]">
                          <Loader2 className="h-3 w-3 animate-spin mr-1.5" />
                          Fusing...
                        </div>
                      )}
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Detailed result cards */}
            <AnimatePresence>
              {visibleResults.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={SPRING}
                  className="space-y-3"
                >
                  <div className="flex items-center justify-between">
                    <p className="text-[11px] font-medium text-white/40">
                      Ranked Results ({visibleResults.length})
                    </p>
                    {stage === 'done' && (
                      <motion.button
                        type="button"
                        onClick={() => setShowScores((p) => !p)}
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={SPRING}
                        whileHover={{ scale: 1.05 }}
                        whileTap={{ scale: 0.95 }}
                        className="flex items-center gap-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] px-2.5 py-1 text-[10px] font-medium text-white/40 hover:text-white/60 transition-colors"
                      >
                        <Gauge className="h-3 w-3" />
                        {showScores ? 'Hide Scores' : 'Show Scores'}
                      </motion.button>
                    )}
                  </div>
                  <div className="space-y-2">
                    {visibleResults.map((r, i) => (
                      <ResultCard key={r.id} result={r} index={i} showScores={showScores} />
                    ))}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Bottom row: gauge + insight */}
            <AnimatePresence>
              {stage === 'done' && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={{ ...SPRING, delay: 0.15 }}
                  className="grid grid-cols-1 md:grid-cols-[auto_1fr] gap-4 items-start"
                >
                  {/* Relevance gauge */}
                  <div className="flex justify-center">
                    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
                      <RelevanceGauge
                        bm25Avg={scoreAverages.bm25}
                        cosineAvg={scoreAverages.cosine}
                        fusedAvg={scoreAverages.fused}
                      />
                    </div>
                  </div>

                  {/* Insight card */}
                  <div className="rounded-xl border border-white/[0.08] bg-gradient-to-br from-purple-500/[0.04] to-cyan-500/[0.04] p-4 space-y-3">
                    <div className="flex items-center gap-2">
                      <Sparkles className="h-3.5 w-3.5 text-amber-400" />
                      <span className="text-xs font-semibold text-white">Insight</span>
                    </div>
                    <p className="text-xs text-white/50 leading-relaxed">
                      {scenario.insight}
                    </p>

                    {/* Timing summary */}
                    <div className="flex flex-wrap gap-3 pt-2 border-t border-white/[0.05]">
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3 w-3 text-purple-400/60" />
                        <span className="text-[10px] font-mono text-purple-300/60">
                          BM25: {scenario.bm25TimeMs}ms
                        </span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3 w-3 text-cyan-400/60" />
                        <span className="text-[10px] font-mono text-cyan-300/60">
                          Vector: {scenario.vectorTimeMs}ms
                        </span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3 w-3 text-amber-400/60" />
                        <span className="text-[10px] font-mono text-amber-300/60">
                          Fusion: {scenario.fusionTimeMs}ms
                        </span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <Zap className="h-3 w-3 text-emerald-400/60" />
                        <span className="text-[10px] font-mono text-emerald-300/60">
                          Total: {scenario.bm25TimeMs + scenario.vectorTimeMs + scenario.fusionTimeMs}ms
                        </span>
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Idle state */}
      {stage === 'idle' && (
        <div className="text-center py-4 text-white/20 text-xs space-y-2">
          <Search className="h-6 w-6 mx-auto opacity-30" />
          <p>Select a scenario and click Run to see the hybrid pipeline in action</p>
        </div>
      )}
    </div>
  );
}
