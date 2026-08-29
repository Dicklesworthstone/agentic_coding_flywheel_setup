'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Terminal,
  Zap,
  Database,
  Clock,
  FileText,
  Play,
  Archive,
  Search,
  Heart,
  Repeat2,
  Loader2,
  Eye,
  Hash,
  MessageSquare,
  BarChart3,
  Filter,
  ArrowRight,
  CheckCircle2,
  TrendingUp,
  Bot,
  Download,
  ChevronRight,
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

export function XfLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Search your X/Twitter archive with sub-millisecond queries using xf.
      </GoalBanner>

      {/* Section 1: What Is XF */}
      <Section title="What Is XF?" icon={<Archive className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>XF</Highlight> provides blazingly fast full-text search across your personal
          X/Twitter archive: tweets, likes, DMs, and Grok conversations. Built with Tantivy, it
          delivers sub-millisecond queries with hybrid BM25 and semantic search.
        </Paragraph>
        <Paragraph>
          All indexing happens locally on your machine. No data leaves your system. Index once
          at ~10,000 docs/second, then search instantly across years of content.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Ultra-Fast"
              description="Sub-millisecond query times"
              gradient="from-slate-500/20 to-gray-500/20"
            />
            <FeatureCard
              icon={<Database className="h-5 w-5" />}
              title="Tantivy + SQLite"
              description="Full-text search with metadata"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Clock className="h-5 w-5" />}
              title="Date Ranges"
              description="Filter by time periods"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Export"
              description="Output to JSON, CSV, or plain text"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'xf index <archive-path>', description: 'Index your Twitter archive' },
            { command: 'xf search <query>', description: 'Search your tweets' },
            { command: 'xf search --from 2023-01-01', description: 'Search with date filter' },
            { command: 'xf --help', description: 'Show all options' },
          ]}
        />

        <TipBox variant="info">
          Download your archive from X/Twitter settings, then run <code>xf index</code> once.
        </TipBox>
      </Section>

      <Divider />

      {/* Interactive Archive Search Demo */}
      <Section title="Archive Mining Lab" icon={<Search className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Explore the full power of <Highlight>xf</Highlight> across 6 different archive mining
          scenarios. Watch tweets flow through the analysis pipeline with real-time relevance
          scoring, engagement metrics, and sentiment analysis.
        </Paragraph>
        <InteractiveArchiveSearch />
      </Section>

      <Divider />

      {/* Section 3: Example Searches */}
      <Section title="Example Searches" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Index your archive (one-time)
xf index ~/Downloads/twitter-archive

# Search for a topic
xf search "machine learning"

# Search within a date range
xf search "rust" --from 2024-01-01 --to 2024-06-30

# Export results to JSON
xf search "AI" --format json > results.json`} />
      </Section>
    </div>
  );
}

// =============================================================================
// TYPES
// =============================================================================

interface TweetResult {
  id: string;
  date: string;
  content: string;
  likes: number;
  retweets: number;
  views: number;
  relevance: number;
  sentiment: 'positive' | 'neutral' | 'negative';
  hashtags: string[];
  type: 'tweet' | 'dm' | 'grok' | 'like' | 'thread';
}

interface Scenario {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  command: string;
  totalResults: number;
  searchTimeMs: number;
  indexStats: {
    totalDocs: number;
    dateRange: string;
    topHashtags: string[];
  };
  pipelineSteps: string[];
  results: TweetResult[];
}

// =============================================================================
// SCENARIO DATA
// =============================================================================

const SCENARIOS: Scenario[] = [
  {
    id: 'keyword',
    label: 'Keyword Search',
    icon: <Search className="h-3.5 w-3.5" />,
    description: 'Full-text BM25 search across all tweets',
    command: 'xf search "machine learning"',
    totalResults: 847,
    searchTimeMs: 0.42,
    indexStats: {
      totalDocs: 23847,
      dateRange: '2019-03-14 to 2024-12-28',
      topHashtags: ['#ML', '#AI', '#DeepLearning', '#NLP', '#Transformers'],
    },
    pipelineSteps: ['Parse query', 'BM25 index scan', 'Relevance rank', 'Top-K extract'],
    results: [
      {
        id: 'kw-1',
        date: '2024-11-15',
        content: 'Just finished a deep dive into transformer architectures. The attention mechanism is pure elegance -- machine learning keeps surprising me with how far we have come from simple perceptrons.',
        likes: 234,
        retweets: 67,
        views: 18200,
        relevance: 0.97,
        sentiment: 'positive',
        hashtags: ['#ML', '#Transformers'],
        type: 'tweet',
      },
      {
        id: 'kw-2',
        date: '2024-09-03',
        content: 'Hot take: most machine learning papers would benefit from 50% less math notation and 50% more intuitive diagrams. Communication matters.',
        likes: 1823,
        retweets: 412,
        views: 89400,
        relevance: 0.91,
        sentiment: 'neutral',
        hashtags: ['#ML', '#Academia'],
        type: 'tweet',
      },
      {
        id: 'kw-3',
        date: '2024-06-22',
        content: 'Shipped a new feature using gradient boosted trees instead of a neural net. Sometimes classical machine learning is all you need. 10x faster inference too.',
        likes: 89,
        retweets: 23,
        views: 4200,
        relevance: 0.85,
        sentiment: 'positive',
        hashtags: ['#ML', '#Engineering'],
        type: 'tweet',
      },
      {
        id: 'kw-4',
        date: '2024-03-10',
        content: 'The machine learning community needs to talk more about failure cases. We learn more from what does not work than from another SOTA benchmark.',
        likes: 567,
        retweets: 145,
        views: 31200,
        relevance: 0.78,
        sentiment: 'neutral',
        hashtags: ['#ML', '#Research'],
        type: 'tweet',
      },
    ],
  },
  {
    id: 'dm-archive',
    label: 'DM Archive',
    icon: <MessageSquare className="h-3.5 w-3.5" />,
    description: 'Search your private direct messages',
    command: 'xf search --type dm "project deadline"',
    totalResults: 156,
    searchTimeMs: 0.28,
    indexStats: {
      totalDocs: 8432,
      dateRange: '2020-01-05 to 2024-12-15',
      topHashtags: [],
    },
    pipelineSteps: ['Parse query', 'DM filter', 'Phrase match', 'Chronological sort'],
    results: [
      {
        id: 'dm-1',
        date: '2024-12-02',
        content: 'Hey, the project deadline got moved to Friday. Can you push the API changes by Thursday EOD? The staging env is ready.',
        likes: 0,
        retweets: 0,
        views: 0,
        relevance: 0.94,
        sentiment: 'neutral',
        hashtags: [],
        type: 'dm',
      },
      {
        id: 'dm-2',
        date: '2024-10-19',
        content: 'Project deadline extended by 2 weeks! The client loved the demo but wants us to add the analytics dashboard before launch.',
        likes: 0,
        retweets: 0,
        views: 0,
        relevance: 0.89,
        sentiment: 'positive',
        hashtags: [],
        type: 'dm',
      },
      {
        id: 'dm-3',
        date: '2024-08-05',
        content: 'Missed the project deadline by one day, but the extra polish was worth it. Ship quality over speed every time.',
        likes: 0,
        retweets: 0,
        views: 0,
        relevance: 0.82,
        sentiment: 'neutral',
        hashtags: [],
        type: 'dm',
      },
    ],
  },
  {
    id: 'grok-chat',
    label: 'Grok Chats',
    icon: <Bot className="h-3.5 w-3.5" />,
    description: 'Extract and search Grok conversation history',
    command: 'xf search --type grok "explain recursion"',
    totalResults: 42,
    searchTimeMs: 0.19,
    indexStats: {
      totalDocs: 1247,
      dateRange: '2024-02-10 to 2024-12-20',
      topHashtags: [],
    },
    pipelineSteps: ['Parse query', 'Grok filter', 'Semantic match', 'Context extract'],
    results: [
      {
        id: 'grok-1',
        date: '2024-11-30',
        content: '[Grok] Recursion in programming is when a function calls itself to solve smaller subproblems. Think of it like Russian nesting dolls -- each doll contains a smaller version of itself.',
        likes: 0,
        retweets: 0,
        views: 0,
        relevance: 0.96,
        sentiment: 'neutral',
        hashtags: [],
        type: 'grok',
      },
      {
        id: 'grok-2',
        date: '2024-09-12',
        content: '[You] Can you explain recursion with a Rust example? I keep getting stack overflows. [Grok] Sure! You need a base case. Here is a factorial function: fn factorial(n: u64) -> u64 { if n <= 1 { 1 } else { n * factorial(n-1) } }',
        likes: 0,
        retweets: 0,
        views: 0,
        relevance: 0.91,
        sentiment: 'neutral',
        hashtags: [],
        type: 'grok',
      },
    ],
  },
  {
    id: 'likes-export',
    label: 'Likes Export',
    icon: <Heart className="h-3.5 w-3.5" />,
    description: 'Search through your liked tweets archive',
    command: 'xf search --type likes "startup advice"',
    totalResults: 1289,
    searchTimeMs: 0.55,
    indexStats: {
      totalDocs: 34521,
      dateRange: '2019-06-01 to 2024-12-28',
      topHashtags: ['#Startup', '#Founder', '#SaaS', '#Growth', '#VC'],
    },
    pipelineSteps: ['Parse query', 'Likes filter', 'BM25 rank', 'Engagement sort'],
    results: [
      {
        id: 'like-1',
        date: '2024-12-10',
        content: 'The best startup advice I ever got: charge more. Seriously. If customers are not pushing back on price at all, you are leaving money on the table.',
        likes: 12400,
        retweets: 3200,
        views: 2100000,
        relevance: 0.93,
        sentiment: 'positive',
        hashtags: ['#Startup'],
        type: 'like',
      },
      {
        id: 'like-2',
        date: '2024-08-22',
        content: 'Startup advice thread: 1. Ship weekly. 2. Talk to users daily. 3. Measure everything. 4. Fire yourself from tasks. 5. Hire slow. 6. Never run out of cash.',
        likes: 8900,
        retweets: 2100,
        views: 1400000,
        relevance: 0.88,
        sentiment: 'positive',
        hashtags: ['#Startup', '#Founder'],
        type: 'like',
      },
      {
        id: 'like-3',
        date: '2024-05-14',
        content: 'Contrarian startup advice: do not optimize for growth. Optimize for learning speed. Growth follows understanding, not the other way around.',
        likes: 4500,
        retweets: 890,
        views: 560000,
        relevance: 0.81,
        sentiment: 'neutral',
        hashtags: ['#Startup', '#Growth'],
        type: 'like',
      },
    ],
  },
  {
    id: 'thread-recon',
    label: 'Thread Rebuild',
    icon: <FileText className="h-3.5 w-3.5" />,
    description: 'Reconstruct full threads from fragmented tweets',
    command: 'xf threads --reconstruct "rust error handling"',
    totalResults: 23,
    searchTimeMs: 0.67,
    indexStats: {
      totalDocs: 23847,
      dateRange: '2019-03-14 to 2024-12-28',
      topHashtags: ['#Rust', '#ErrorHandling', '#Programming'],
    },
    pipelineSteps: ['Parse query', 'Thread detect', 'Reply chain walk', 'Reconstruct order'],
    results: [
      {
        id: 'thread-1',
        date: '2024-10-05',
        content: '[1/4] Thread on Rust error handling patterns. After 3 years of production Rust, here is what actually works vs. what the tutorials tell you...',
        likes: 2340,
        retweets: 678,
        views: 145000,
        relevance: 0.95,
        sentiment: 'positive',
        hashtags: ['#Rust'],
        type: 'thread',
      },
      {
        id: 'thread-2',
        date: '2024-10-05',
        content: '[2/4] Pattern 1: Use thiserror for library crates, anyhow for applications. Do NOT mix them. Your callers will thank you when they can match on specific errors.',
        likes: 1890,
        retweets: 534,
        views: 98000,
        relevance: 0.93,
        sentiment: 'neutral',
        hashtags: ['#Rust', '#ErrorHandling'],
        type: 'thread',
      },
      {
        id: 'thread-3',
        date: '2024-10-05',
        content: '[3/4] Pattern 2: The ? operator is beautiful but do not let it propagate errors you should handle locally. Context matters -- use .context() from anyhow liberally.',
        likes: 1560,
        retweets: 412,
        views: 82000,
        relevance: 0.90,
        sentiment: 'neutral',
        hashtags: ['#Rust', '#ErrorHandling'],
        type: 'thread',
      },
    ],
  },
  {
    id: 'sentiment',
    label: 'Sentiment Analysis',
    icon: <TrendingUp className="h-3.5 w-3.5" />,
    description: 'Analyze emotional tone across search results',
    command: 'xf search "AI" --sentiment --stats',
    totalResults: 523,
    searchTimeMs: 1.24,
    indexStats: {
      totalDocs: 23847,
      dateRange: '2019-03-14 to 2024-12-28',
      topHashtags: ['#AI', '#AGI', '#LLM', '#Safety', '#OpenAI'],
    },
    pipelineSteps: ['Parse query', 'BM25 scan', 'Sentiment classify', 'Aggregate stats'],
    results: [
      {
        id: 'sent-1',
        date: '2024-11-28',
        content: 'AI safety is not just about alignment. It is about building systems where humans maintain meaningful oversight at every layer. Defense in depth.',
        likes: 1567,
        retweets: 389,
        views: 87000,
        relevance: 0.96,
        sentiment: 'positive',
        hashtags: ['#AI', '#Safety'],
        type: 'tweet',
      },
      {
        id: 'sent-2',
        date: '2024-08-19',
        content: 'Read three AI safety papers today. The interpretability research coming out of Anthropic is genuinely exciting -- we are starting to see inside the black box.',
        likes: 423,
        retweets: 112,
        views: 24500,
        relevance: 0.88,
        sentiment: 'positive',
        hashtags: ['#AI', '#Interpretability'],
        type: 'tweet',
      },
      {
        id: 'sent-3',
        date: '2024-05-30',
        content: 'Unpopular opinion: the best AI safety work right now is happening in engineering, not philosophy. Concrete evals beat abstract debates.',
        likes: 892,
        retweets: 234,
        views: 45000,
        relevance: 0.81,
        sentiment: 'neutral',
        hashtags: ['#AI', '#Safety'],
        type: 'tweet',
      },
      {
        id: 'sent-4',
        date: '2024-02-12',
        content: 'Frustrated with how many AI tools ship without basic guardrails. If you are building with LLMs and not thinking about safety, you are building tech debt that compounds.',
        likes: 678,
        retweets: 178,
        views: 38000,
        relevance: 0.73,
        sentiment: 'negative',
        hashtags: ['#AI', '#LLM'],
        type: 'tweet',
      },
    ],
  },
];

// =============================================================================
// PIPELINE STEP ANIMATION DELAYS
// =============================================================================

const PIPELINE_STEP_DURATION = 400;
const RESULT_REVEAL_DELAY = 200;

// =============================================================================
// FORMAT HELPERS
// =============================================================================

function formatNumber(n: number): string {
  if (n >= 1000000) {
    return (n / 1000000).toFixed(1) + 'M';
  }
  if (n >= 1000) {
    return (n / 1000).toFixed(1) + 'k';
  }
  return String(n);
}

function getSentimentColor(s: string): string {
  if (s === 'positive') return 'text-emerald-400';
  if (s === 'negative') return 'text-rose-400';
  return 'text-white/40';
}

function getSentimentBg(s: string): string {
  if (s === 'positive') return 'bg-emerald-500/20 border-emerald-500/30';
  if (s === 'negative') return 'bg-rose-500/20 border-rose-500/30';
  return 'bg-white/[0.04] border-white/[0.08]';
}

function getTypeIcon(type: string): React.ReactNode {
  if (type === 'dm') return <MessageSquare className="h-3.5 w-3.5 text-blue-400" />;
  if (type === 'grok') return <Bot className="h-3.5 w-3.5 text-purple-400" />;
  if (type === 'like') return <Heart className="h-3.5 w-3.5 text-rose-400" />;
  if (type === 'thread') return <FileText className="h-3.5 w-3.5 text-amber-400" />;
  return <Archive className="h-3.5 w-3.5 text-sky-400" />;
}

function getTypeBadgeColor(type: string): string {
  if (type === 'dm') return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
  if (type === 'grok') return 'bg-purple-500/20 text-purple-400 border-purple-500/30';
  if (type === 'like') return 'bg-rose-500/20 text-rose-400 border-rose-500/30';
  if (type === 'thread') return 'bg-amber-500/20 text-amber-400 border-amber-500/30';
  return 'bg-sky-500/20 text-sky-400 border-sky-500/30';
}

// =============================================================================
// INTERACTIVE ARCHIVE SEARCH
// =============================================================================

function InteractiveArchiveSearch() {
  const [activeScenario, setActiveScenario] = useState<string | null>(null);
  const [pipelineStep, setPipelineStep] = useState(-1);
  const [showResults, setShowResults] = useState(false);
  const [showStats, setShowStats] = useState(false);
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pipelineTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const scenario = activeScenario
    ? SCENARIOS.find((s) => s.id === activeScenario) ?? null
    : null;

  const clearTimers = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    if (pipelineTimerRef.current) {
      clearTimeout(pipelineTimerRef.current);
      pipelineTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    return () => {
      clearTimers();
    };
  }, [clearTimers]);

  const runScenario = useCallback(
    (id: string) => {
      clearTimers();

      const sc = SCENARIOS.find((s) => s.id === id);
      if (!sc) return;

      setActiveScenario(id);
      setPipelineStep(-1);
      setShowResults(false);
      setShowStats(false);
      setTerminalLines([`$ ${sc.command}`]);

      // Animate pipeline steps sequentially
      const steps = sc.pipelineSteps;
      const scTotalResults = sc.totalResults;
      const scSearchTimeMs = sc.searchTimeMs;
      let currentStep = 0;

      function advancePipeline() {
        if (currentStep < steps.length) {
          setPipelineStep(currentStep);
          setTerminalLines((prev) => [
            ...prev,
            `  [${String(currentStep + 1)}/${String(steps.length)}] ${steps[currentStep]}...`,
          ]);
          currentStep++;
          pipelineTimerRef.current = setTimeout(advancePipeline, PIPELINE_STEP_DURATION);
        } else {
          // Pipeline done - show results
          setTerminalLines((prev) => [
            ...prev,
            `  Found ${scTotalResults.toLocaleString()} results in ${String(scSearchTimeMs)}ms`,
            '',
          ]);
          timerRef.current = setTimeout(() => {
            setShowResults(true);
            pipelineTimerRef.current = setTimeout(() => {
              setShowStats(true);
            }, 300);
          }, 200);
        }
      }

      pipelineTimerRef.current = setTimeout(advancePipeline, 300);
    },
    [clearTimers],
  );

  // Sentiment distribution for the sentiment scenario
  const sentimentCounts = scenario
    ? {
        positive: scenario.results.filter((r) => r.sentiment === 'positive').length,
        neutral: scenario.results.filter((r) => r.sentiment === 'neutral').length,
        negative: scenario.results.filter((r) => r.sentiment === 'negative').length,
      }
    : { positive: 0, neutral: 0, negative: 0 };

  const sentimentTotal =
    sentimentCounts.positive + sentimentCounts.neutral + sentimentCounts.negative;

  return (
    <div ref={rootRef} className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-48 h-48 bg-sky-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-32 h-32 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-40 h-40 bg-purple-500/5 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 space-y-5">
        {/* Header with archive stats badge */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-sky-500/20 border border-sky-500/30">
              <Archive className="h-4 w-4 text-sky-400" />
            </div>
            <div>
              <div className="text-sm font-semibold text-white/90">
                X/Twitter Archive Mining Lab
              </div>
              <div className="text-xs text-white/40">
                23,847 documents indexed
              </div>
            </div>
          </div>
          <div className="flex items-center gap-1.5 text-xs font-mono text-emerald-400/70">
            <div className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" />
            Index ready
          </div>
        </div>

        {/* Scenario selector - 2 rows of 3 */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
          {SCENARIOS.map((sc) => (
            <button
              key={sc.id}
              onClick={() => runScenario(sc.id)}
              className={`group flex items-center gap-2 px-3 py-2.5 rounded-lg text-xs font-medium transition text-left ${
                activeScenario === sc.id
                  ? 'bg-primary/20 text-primary border border-primary/30 shadow-lg shadow-primary/5'
                  : 'bg-white/[0.02] text-white/40 border border-white/[0.08] hover:text-white/60 hover:border-white/[0.15] hover:bg-white/[0.04]'
              }`}
            >
              <span
                className={`shrink-0 ${activeScenario === sc.id ? 'text-primary' : 'text-white/30 group-hover:text-white/50'}`}
              >
                {sc.icon}
              </span>
              <div className="min-w-0">
                <div className="truncate">{sc.label}</div>
                <div
                  className={`text-[10px] truncate ${activeScenario === sc.id ? 'text-primary/60' : 'text-white/20'}`}
                >
                  {sc.description}
                </div>
              </div>
            </button>
          ))}
        </div>

        {/* Mini terminal */}
        <div className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
          <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
            <div className="flex gap-1.5">
              <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
              <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
              <div className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
            </div>
            <span className="ml-2 text-[10px] text-white/30 font-mono">
              xf archive search
            </span>
          </div>
          <div className="p-4 font-mono text-xs space-y-0.5 max-h-40 overflow-y-auto">
            {terminalLines.length === 0 ? (
              <div className="flex items-center gap-2 text-white/30">
                <span className="text-emerald-400">$</span>
                <span>Select a scenario above to start mining...</span>
                <motion.span
                  animate={inView ? { opacity: [1, 0] } : { opacity: 1 }}
                  transition={
                    inView
                      ? { duration: 0.8, repeat: Infinity, repeatType: 'reverse' }
                      : { duration: 0.2 }
                  }
                  className="inline-block w-1.5 h-3.5 bg-primary/60"
                />
              </div>
            ) : (
              <AnimatePresence mode="popLayout">
                {terminalLines.map((line, i) => (
                  <motion.div
                    key={`${activeScenario}-line-${String(i)}`}
                    initial={{ opacity: 0, x: -8 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{
                      type: 'spring',
                      stiffness: 200,
                      damping: 25,
                    }}
                    className={
                      i === 0
                        ? 'text-white/70'
                        : line.includes('Found')
                          ? 'text-emerald-400/80'
                          : 'text-white/40'
                    }
                  >
                    {i === 0 && (
                      <span className="text-emerald-400 mr-2">$</span>
                    )}
                    {i === 0 ? line.replace('$ ', '') : line}
                  </motion.div>
                ))}
              </AnimatePresence>
            )}
          </div>
        </div>

        {/* Pipeline visualization */}
        <AnimatePresence mode="wait">
          {scenario && pipelineStep >= 0 && !showResults && (
            <motion.div
              key={`pipeline-${activeScenario}`}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4"
            >
              <div className="flex items-center gap-2 mb-3">
                <Filter className="h-3.5 w-3.5 text-sky-400" />
                <span className="text-xs font-semibold text-white/70">
                  Search Pipeline
                </span>
              </div>
              <div className="flex items-center gap-1 flex-wrap">
                {scenario.pipelineSteps.map((step, i) => (
                  <div key={step} className="flex items-center gap-1">
                    <motion.div
                      initial={{ scale: 0.8, opacity: 0 }}
                      animate={{
                        scale: i <= pipelineStep ? 1 : 0.9,
                        opacity: i <= pipelineStep ? 1 : 0.3,
                      }}
                      transition={{
                        type: 'spring',
                        stiffness: 200,
                        damping: 25,
                      }}
                      className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-mono border ${
                        i < pipelineStep
                          ? 'bg-emerald-500/15 border-emerald-500/30 text-emerald-400'
                          : i === pipelineStep
                            ? 'bg-sky-500/15 border-sky-500/30 text-sky-400'
                            : 'bg-white/[0.02] border-white/[0.06] text-white/30'
                      }`}
                    >
                      {i < pipelineStep ? (
                        <CheckCircle2 className="h-3 w-3" />
                      ) : i === pipelineStep ? (
                        <motion.div
                          animate={inView ? { rotate: 360 } : { rotate: 0 }}
                          transition={
                            inView
                              ? { duration: 1, repeat: Infinity, ease: 'linear' }
                              : { duration: 0.2 }
                          }
                        >
                          <Loader2 className="h-3 w-3" />
                        </motion.div>
                      ) : (
                        <ChevronRight className="h-3 w-3" />
                      )}
                      {step}
                    </motion.div>
                    {i < scenario.pipelineSteps.length - 1 && (
                      <ArrowRight
                        className={`h-3 w-3 shrink-0 ${i < pipelineStep ? 'text-emerald-400/50' : 'text-white/15'}`}
                      />
                    )}
                  </div>
                ))}
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Empty state */}
        {!scenario && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="flex flex-col items-center justify-center py-12 gap-3 text-white/25"
          >
            <Search className="h-12 w-12" />
            <span className="text-sm font-medium">
              Choose a mining scenario to explore your archive
            </span>
            <span className="text-xs text-white/15">
              6 scenarios available: search, DMs, Grok, likes, threads, sentiment
            </span>
          </motion.div>
        )}

        {/* Results area */}
        <AnimatePresence mode="wait">
          {showResults && scenario && (
            <motion.div
              key={`results-${activeScenario}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="space-y-4"
            >
              {/* Stats dashboard row */}
              {showStats && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    type: 'spring',
                    stiffness: 200,
                    damping: 25,
                  }}
                  className="grid grid-cols-2 sm:grid-cols-4 gap-2"
                >
                  <StatCard
                    icon={<Database className="h-3.5 w-3.5 text-sky-400" />}
                    label="Indexed"
                    value={formatNumber(scenario.indexStats.totalDocs)}
                  />
                  <StatCard
                    icon={<Search className="h-3.5 w-3.5 text-emerald-400" />}
                    label="Matched"
                    value={scenario.totalResults.toLocaleString()}
                  />
                  <StatCard
                    icon={<Zap className="h-3.5 w-3.5 text-amber-400" />}
                    label="Latency"
                    value={`${String(scenario.searchTimeMs)}ms`}
                  />
                  <StatCard
                    icon={<Clock className="h-3.5 w-3.5 text-purple-400" />}
                    label="Date Range"
                    value={scenario.indexStats.dateRange.split(' to ')[0].slice(0, 7)}
                  />
                </motion.div>
              )}

              {/* Top hashtags bar (if applicable) */}
              {showStats && scenario.indexStats.topHashtags.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    type: 'spring',
                    stiffness: 200,
                    damping: 25,
                    delay: 0.1,
                  }}
                  className="flex items-center gap-2 flex-wrap"
                >
                  <Hash className="h-3 w-3 text-white/30 shrink-0" />
                  {scenario.indexStats.topHashtags.map((tag) => (
                    <span
                      key={tag}
                      className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-white/[0.04] border border-white/[0.08] text-white/40"
                    >
                      {tag}
                    </span>
                  ))}
                </motion.div>
              )}

              {/* Sentiment breakdown bar (only for sentiment scenario) */}
              {showStats && activeScenario === 'sentiment' && sentimentTotal > 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    type: 'spring',
                    stiffness: 200,
                    damping: 25,
                    delay: 0.15,
                  }}
                  className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3"
                >
                  <div className="flex items-center gap-2 mb-2">
                    <BarChart3 className="h-3.5 w-3.5 text-sky-400" />
                    <span className="text-xs font-semibold text-white/60">
                      Sentiment Distribution
                    </span>
                  </div>
                  <div className="flex h-3 rounded-full overflow-hidden gap-0.5">
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{
                        width: `${String((sentimentCounts.positive / sentimentTotal) * 100)}%`,
                      }}
                      transition={{
                        type: 'spring',
                        stiffness: 100,
                        damping: 20,
                        delay: 0.2,
                      }}
                      className="bg-emerald-500/60 rounded-l-full"
                    />
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{
                        width: `${String((sentimentCounts.neutral / sentimentTotal) * 100)}%`,
                      }}
                      transition={{
                        type: 'spring',
                        stiffness: 100,
                        damping: 20,
                        delay: 0.3,
                      }}
                      className="bg-white/20"
                    />
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{
                        width: `${String((sentimentCounts.negative / sentimentTotal) * 100)}%`,
                      }}
                      transition={{
                        type: 'spring',
                        stiffness: 100,
                        damping: 20,
                        delay: 0.4,
                      }}
                      className="bg-rose-500/60 rounded-r-full"
                    />
                  </div>
                  <div className="flex items-center justify-between mt-1.5 text-[10px] font-mono">
                    <span className="text-emerald-400">
                      Positive {sentimentCounts.positive}
                    </span>
                    <span className="text-white/40">
                      Neutral {sentimentCounts.neutral}
                    </span>
                    <span className="text-rose-400">
                      Negative {sentimentCounts.negative}
                    </span>
                  </div>
                </motion.div>
              )}

              {/* Results summary */}
              <div className="flex items-center justify-between text-xs font-mono px-1">
                <span className="text-white/40">
                  Showing {scenario.results.length} of{' '}
                  {scenario.totalResults.toLocaleString()} results
                </span>
                <span className="text-emerald-400/70 flex items-center gap-1">
                  <Zap className="h-3 w-3" />
                  {scenario.searchTimeMs}ms
                </span>
              </div>

              {/* Tweet result cards */}
              {scenario.results.map((result, i) => (
                <motion.div
                  key={result.id}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    type: 'spring',
                    stiffness: 200,
                    damping: 25,
                    delay: i * RESULT_REVEAL_DELAY / 1000,
                  }}
                  className="rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden hover:border-white/[0.15] transition duration-300 group"
                >
                  <div className="p-4 space-y-3">
                    {/* Card header */}
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="flex h-7 w-7 items-center justify-center rounded-full bg-white/[0.04] border border-white/[0.08]">
                          {getTypeIcon(result.type)}
                        </div>
                        <span className="text-xs text-white/40 font-mono">
                          {result.date}
                        </span>
                        <span
                          className={`text-[10px] font-medium px-1.5 py-0.5 rounded border ${getTypeBadgeColor(result.type)}`}
                        >
                          {result.type}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-xs text-white/30">
                        {result.views > 0 && (
                          <span className="flex items-center gap-1">
                            <Eye className="h-3 w-3 text-white/20" />
                            {formatNumber(result.views)}
                          </span>
                        )}
                        {result.likes > 0 && (
                          <span className="flex items-center gap-1">
                            <Heart className="h-3 w-3 text-rose-400/60" />
                            {formatNumber(result.likes)}
                          </span>
                        )}
                        {result.retweets > 0 && (
                          <span className="flex items-center gap-1">
                            <Repeat2 className="h-3 w-3 text-emerald-400/60" />
                            {formatNumber(result.retweets)}
                          </span>
                        )}
                      </div>
                    </div>

                    {/* Tweet content */}
                    <p className="text-sm text-white/70 leading-relaxed">
                      {result.content}
                    </p>

                    {/* Bottom row: hashtags + sentiment + relevance */}
                    <div className="flex items-center gap-3 flex-wrap">
                      {/* Hashtags */}
                      {result.hashtags.length > 0 && (
                        <div className="flex items-center gap-1">
                          {result.hashtags.map((tag) => (
                            <span
                              key={tag}
                              className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-sky-500/10 text-sky-400/60 border border-sky-500/20"
                            >
                              {tag}
                            </span>
                          ))}
                        </div>
                      )}

                      {/* Sentiment badge */}
                      <span
                        className={`text-[10px] font-medium px-1.5 py-0.5 rounded border ${getSentimentBg(result.sentiment)} ${getSentimentColor(result.sentiment)}`}
                      >
                        {result.sentiment}
                      </span>

                      {/* Spacer */}
                      <div className="flex-1" />

                      {/* Relevance score */}
                      <div className="flex items-center gap-2 min-w-[140px]">
                        <span className="text-[10px] text-white/40 font-mono shrink-0">
                          {(result.relevance * 100).toFixed(0)}%
                        </span>
                        <div className="flex-1 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                          <motion.div
                            initial={{ width: 0 }}
                            animate={{
                              width: `${String(result.relevance * 100)}%`,
                            }}
                            transition={{
                              type: 'spring',
                              stiffness: 100,
                              damping: 20,
                              delay:
                                i * RESULT_REVEAL_DELAY / 1000 + 0.3,
                            }}
                            className="h-full rounded-full bg-gradient-to-r from-sky-500 to-indigo-500"
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                </motion.div>
              ))}

              {/* Export hint */}
              {showStats && (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.5 }}
                  className="flex items-center justify-center gap-2 py-2 text-[10px] text-white/20 font-mono"
                >
                  <Download className="h-3 w-3" />
                  xf search &quot;{scenario.id === 'keyword' ? 'machine learning' : '...'}&quot; --format json &gt; results.json
                </motion.div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// STAT CARD SUB-COMPONENT
// =============================================================================

function StatCard({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="rounded-lg border border-white/[0.08] bg-white/[0.02] p-2.5 flex items-center gap-2">
      <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-white/[0.04] shrink-0">
        {icon}
      </div>
      <div className="min-w-0">
        <div className="text-[10px] text-white/30 uppercase tracking-wide">
          {label}
        </div>
        <div className="text-xs font-semibold text-white/80 font-mono truncate">
          {value}
        </div>
      </div>
    </div>
  );
}
