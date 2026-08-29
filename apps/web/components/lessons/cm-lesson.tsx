"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence, useInView } from "@/components/motion";
import {
  Brain,
  Lightbulb,
  BookOpen,
  Database,
  Terminal,
  Sparkles,
  Target,
  AlertCircle,
  CheckCircle,
  FileText,
  Zap,
  RefreshCw,
  Archive,
  Cpu,
  Layers,
  Search,
  Play,
  Pause,
  ChevronRight,
  GitBranch,
  Bug,
  Settings,
  Users,
  Clock,
} from "lucide-react";
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
} from "./lesson-components";

export function CmLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Build procedural memory for agents that improves over time.
      </GoalBanner>

      {/* What Is CM */}
      <Section
        title="What Is CM?"
        icon={<Brain className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>CM (CASS Memory System)</Highlight> gives AI agents
          effective memory by extracting lessons from past sessions and making
          them retrievable for future work.
        </Paragraph>
        <Paragraph>
          Think of it like how humans learn: you encounter a problem, solve it,
          and remember the solution. CM does this for your agents automatically.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<BookOpen className="h-5 w-5" />}
              title="Lesson Extraction"
              description="Automatically extract rules from past sessions"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Target className="h-5 w-5" />}
              title="Context Retrieval"
              description="Get relevant rules before starting tasks"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<AlertCircle className="h-5 w-5" />}
              title="Anti-Patterns"
              description="Learn what NOT to do from past mistakes"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<RefreshCw className="h-5 w-5" />}
              title="Continuous Learning"
              description="Memory improves with every session"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* How It Works */}
      <Section
        title="How It Works"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.15}
      >
        <InteractiveMemoryPipeline />

        <div className="mt-8">
          <TipBox variant="info">
            CM builds a &quot;playbook&quot; of rules over time. The more
            sessions you analyze, the smarter your agents become!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* The Onboarding Flow */}
      <Section
        title="Onboarding: Building Your Playbook"
        icon={<BookOpen className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          The <code>cm onboard</code> command guides you through analyzing past
          sessions and extracting valuable rules:
        </Paragraph>

        <div className="mt-6">
          <OnboardingSteps />
        </div>
      </Section>

      <Divider />

      {/* Essential Commands */}
      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.25}
      >
        <CommandList
          commands={[
            {
              command: "cm onboard status",
              description: "Check playbook status and recommendations",
            },
            {
              command: "cm onboard sample --fill-gaps",
              description: "Get sessions to analyze (filtered by gaps)",
            },
            {
              command: "cm onboard read /path/session.jsonl --template",
              description: "Read a session with rich context",
            },
            {
              command: 'cm playbook add "rule" --category "debugging"',
              description: "Add an extracted rule",
            },
            {
              command: "cm onboard mark-done /path/session.jsonl",
              description: "Mark session as processed",
            },
            {
              command: 'cm context "task description" --json',
              description: "Get relevant context for a task",
            }
          ]}
        />
      </Section>

      <Divider />

      {/* Using Context */}
      <Section
        title="Using Context Before Tasks"
        icon={<Target className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          Before starting complex tasks, retrieve relevant context from your
          playbook:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`$ cm context "implement user authentication" --json

{
  "relevantBullets": [
    {
      "id": "b-8f3a2c",
      "rule": "Always use bcrypt with cost factor ≥12 for password hashing",
      "category": "security"
    },
    {
      "id": "b-2d4e1f",
      "rule": "Store JWT secrets in environment variables, never in code",
      "category": "security"
    }
  ],
  "antiPatterns": [
    {
      "id": "ap-9c7b3d",
      "pattern": "Using MD5 for password storage",
      "consequence": "Trivially reversible, security vulnerability"
    }
  ],
  "historySnippets": [
    {
      "session": "2025-01-10.jsonl",
      "summary": "Implemented OAuth2 flow with refresh tokens"
    }
  ],
  "suggestedCassQueries": [
    "authentication error handling",
    "JWT refresh token"
  ]
}`}
            language="json"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Reference rule IDs in your work. For example: &quot;Following
            b-8f3a2c, using bcrypt with cost 12...&quot;
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* The Protocol */}
      <Section
        title="The Memory Protocol"
        icon={<Zap className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="space-y-6">
          <ProtocolStep
            number={1}
            title="START"
            description='Run cm context "<task>" --json before non-trivial work'
          />
          <ProtocolStep
            number={2}
            title="WORK"
            description='Reference rule IDs when following them (e.g., "Following b-8f3a2c...")'
          />
          <ProtocolStep
            number={3}
            title="FEEDBACK"
            description="Leave inline comments when rules help or hurt"
          />
          <ProtocolStep
            number={4}
            title="END"
            description="Just finish your work. Learning happens automatically."
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`// Feedback format in code:
// [cass: helpful b-8f3a2c] - bcrypt recommendation prevented weak hashing
// [cass: harmful b-xyz123] - this rule didn't apply to async context`}
            language="typescript"
          />
        </div>
      </Section>

      <Divider />

      {/* Rule Categories */}
      <Section
        title="Rule Categories"
        icon={<FileText className="h-5 w-5" />}
        delay={0.4}
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <CategoryCard
            name="debugging"
            description="Problem-solving techniques"
            color="from-red-500/20 to-rose-500/20"
          />
          <CategoryCard
            name="security"
            description="Security best practices"
            color="from-amber-500/20 to-orange-500/20"
          />
          <CategoryCard
            name="performance"
            description="Optimization patterns"
            color="from-emerald-500/20 to-teal-500/20"
          />
          <CategoryCard
            name="architecture"
            description="Design decisions"
            color="from-primary/20 to-violet-500/20"
          />
          <CategoryCard
            name="testing"
            description="Test strategies"
            color="from-blue-500/20 to-indigo-500/20"
          />
          <CategoryCard
            name="tooling"
            description="Tool-specific knowledge"
            color="from-pink-500/20 to-rose-500/20"
          />
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.45}
      >
        <div className="space-y-4">
          <BestPractice
            title="Run cm context before complex tasks"
            description="Don't reinvent the wheel—check what you've learned"
          />
          <BestPractice
            title="Extract specific, actionable rules"
            description="'Use bcrypt cost ≥12' is better than 'be secure'"
          />
          <BestPractice
            title="Include anti-patterns"
            description="What NOT to do is as valuable as what to do"
          />
          <BestPractice
            title="Categorize rules properly"
            description="Makes retrieval more accurate"
          />
          <BestPractice
            title="Provide feedback on rules"
            description="Helps the system learn which rules are actually useful"
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.5}
      >
        <CodeBlock
          code={`# Check your playbook status
$ cm onboard status

# Get context for your current task
$ cm context "refactor database queries" --json

# See what sessions need analysis
$ cm onboard sample --fill-gaps`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE MEMORY PIPELINE V2 - Memory System Dashboard
// =============================================================================

interface SessionCard {
  id: string;
  date: string;
  topic: string;
  icon: React.ReactNode;
  color: string;
}

interface MemoryRule {
  id: string;
  rule: string;
  category: "code" | "debug" | "arch" | "team";
  sourceSessions: string[];
  isNew: boolean;
}

interface QueryExample {
  label: string;
  query: string;
  matchingRules: string[];
  scores: Record<string, number>;
}

const SPRING_CONFIG = { type: "spring" as const, stiffness: 200, damping: 25 };

const SESSION_DATA: SessionCard[] = [
  { id: "s1", date: "Mar 10", topic: "Fix auth token refresh loop", icon: <Bug className="h-3.5 w-3.5" />, color: "#f87171" },
  { id: "s2", date: "Mar 9", topic: "Refactor DB connection pool", icon: <Database className="h-3.5 w-3.5" />, color: "#60a5fa" },
  { id: "s3", date: "Mar 8", topic: "Add rate limiting middleware", icon: <Settings className="h-3.5 w-3.5" />, color: "#a78bfa" },
  { id: "s4", date: "Mar 7", topic: "Migrate to TypeScript strict", icon: <FileText className="h-3.5 w-3.5" />, color: "#34d399" },
  { id: "s5", date: "Mar 5", topic: "Setup CI/CD pipeline", icon: <GitBranch className="h-3.5 w-3.5" />, color: "#fbbf24" },
  { id: "s6", date: "Mar 3", topic: "Debug memory leak in worker", icon: <Bug className="h-3.5 w-3.5" />, color: "#f87171" },
  { id: "s7", date: "Mar 1", topic: "Implement caching layer", icon: <Layers className="h-3.5 w-3.5" />, color: "#2dd4bf" },
  { id: "s8", date: "Feb 28", topic: "Code review standards doc", icon: <Users className="h-3.5 w-3.5" />, color: "#fb923c" },
];

const MEMORY_RULES: MemoryRule[] = [
  { id: "r1", rule: "Always use connection pooling with max 20 connections", category: "code", sourceSessions: ["s2", "s7"], isNew: false },
  { id: "r2", rule: "Check for circular refs before debugging memory leaks", category: "debug", sourceSessions: ["s6"], isNew: false },
  { id: "r3", rule: "Rate limiters need both IP and user-level buckets", category: "arch", sourceSessions: ["s3"], isNew: false },
  { id: "r4", rule: "Use strict: true in tsconfig from project start", category: "code", sourceSessions: ["s4"], isNew: false },
  { id: "r5", rule: "Token refresh needs mutex to prevent race conditions", category: "debug", sourceSessions: ["s1"], isNew: true },
  { id: "r6", rule: "CI must run type-check before tests to fail fast", category: "arch", sourceSessions: ["s5"], isNew: false },
  { id: "r7", rule: "PRs need at least one approval plus passing CI", category: "team", sourceSessions: ["s8"], isNew: false },
  { id: "r8", rule: "Cache invalidation via TTL + event-driven hybrid", category: "arch", sourceSessions: ["s7", "s2"], isNew: true },
];

const CATEGORY_META: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
  code: { label: "Code Patterns", color: "#60a5fa", icon: <FileText className="h-3.5 w-3.5" /> },
  debug: { label: "Debugging Tips", color: "#f87171", icon: <Bug className="h-3.5 w-3.5" /> },
  arch: { label: "Architecture Rules", color: "#a78bfa", icon: <Layers className="h-3.5 w-3.5" /> },
  team: { label: "Team Preferences", color: "#fbbf24", icon: <Users className="h-3.5 w-3.5" /> },
};

const QUERY_EXAMPLES: QueryExample[] = [
  {
    label: "Fix database timeout",
    query: "fix database timeout",
    matchingRules: ["r1", "r8"],
    scores: { r1: 0.94, r8: 0.72 },
  },
  {
    label: "Debug memory issue",
    query: "debug memory issue",
    matchingRules: ["r2", "r5"],
    scores: { r2: 0.97, r5: 0.61 },
  },
  {
    label: "Setup new project",
    query: "setup new project",
    matchingRules: ["r4", "r6", "r7"],
    scores: { r4: 0.88, r6: 0.82, r7: 0.65 },
  },
];

const PROCESSING_STAGES = ["Extract", "Correlate", "Synthesize", "Store"] as const;

function InteractiveMemoryPipeline() {
  const [selectedSession, setSelectedSession] = useState<string | null>(null);
  const [activeQuery, setActiveQuery] = useState<QueryExample | null>(null);
  const [processingStage, setProcessingStage] = useState(-1);
  const [isAutoPlaying, setIsAutoPlaying] = useState(false);
  const [feedingSession, setFeedingSession] = useState<string | null>(null);
  const [glowingRules, setGlowingRules] = useState<Set<string>>(new Set());
  const autoPlayTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const autoPlayTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearAutoPlayTimers = useCallback(() => {
    for (const t of autoPlayTimersRef.current) clearTimeout(t);
    autoPlayTimersRef.current = [];
    if (autoPlayTimerRef.current) {
      clearTimeout(autoPlayTimerRef.current);
      autoPlayTimerRef.current = null;
    }
  }, []);

  // Auto-play demo flow
  useEffect(() => {
    if (!isAutoPlaying) {
      clearAutoPlayTimers();
      return;
    }
    clearAutoPlayTimers();

    const schedule = (fn: () => void, delay: number) => {
      const t = setTimeout(fn, delay);
      autoPlayTimersRef.current.push(t);
      autoPlayTimerRef.current = t;
      return t;
    };

    // Step 1: Select a session
    schedule(() => {
      setSelectedSession("s1");
      setFeedingSession("s1");

      // Step 2: Processing stages
      schedule(() => {
        setProcessingStage(0);
        schedule(() => {
          setProcessingStage(1);
          schedule(() => {
            setProcessingStage(2);
            schedule(() => {
              setProcessingStage(3);

              // Step 3: Rule appears with glow
              schedule(() => {
                setFeedingSession(null);
                setGlowingRules(new Set(["r5"]));
                setProcessingStage(-1);

                // Step 4: Query demonstration
                schedule(() => {
                  setSelectedSession(null);
                  setActiveQuery(QUERY_EXAMPLES[0]);
                  setGlowingRules(new Set());

                  // Step 5: Reset
                  schedule(() => {
                    setActiveQuery(null);
                    setIsAutoPlaying(false);
                  }, 3000);
                }, 2500);
              }, 1200);
            }, 800);
          }, 800);
        }, 800);
      }, 1200);
    }, 600);

    return clearAutoPlayTimers;
  }, [isAutoPlaying, clearAutoPlayTimers]);

  const handleSessionClick = useCallback((sessionId: string) => {
    if (isAutoPlaying) return;
    setSelectedSession((prev) => (prev === sessionId ? null : sessionId));
    setActiveQuery(null);
  }, [isAutoPlaying]);

  const handleQueryClick = useCallback((example: QueryExample) => {
    if (isAutoPlaying) return;
    setActiveQuery((prev) => (prev?.label === example.label ? null : example));
    setSelectedSession(null);
    setGlowingRules(new Set());
  }, [isAutoPlaying]);

  const toggleAutoPlay = useCallback(() => {
    if (isAutoPlaying) {
      clearAutoPlayTimers();
      setIsAutoPlaying(false);
      setSelectedSession(null);
      setFeedingSession(null);
      setProcessingStage(-1);
      setGlowingRules(new Set());
      setActiveQuery(null);
    } else {
      setIsAutoPlaying(true);
      // Removed broken condition and comment since auto-play handles starting its own sequence based on state
    }
  }, [isAutoPlaying, clearAutoPlayTimers]);

  const highlightedRuleIds = activeQuery
    ? new Set(activeQuery.matchingRules)
    : selectedSession
      ? new Set(MEMORY_RULES.filter((r) => r.sourceSessions.includes(selectedSession)).map((r) => r.id))
      : new Set<string>();

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* CSS animations for neural network connections */}
      <style>{`
        @keyframes cmPulseGlow {
          0%, 100% { opacity: 0.3; }
          50% { opacity: 0.8; }
        }
        @keyframes cmSlideIn {
          0% { transform: translateX(-20px); opacity: 0; }
          100% { transform: translateX(0); opacity: 1; }
        }
        @keyframes cmNeuralPulse {
          0% { stroke-dashoffset: 20; opacity: 0.2; }
          50% { opacity: 0.7; }
          100% { stroke-dashoffset: 0; opacity: 0.2; }
        }
        @keyframes cmProcessSpin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        .cm-neural-line {
          stroke-dasharray: 4 6;
          animation: cmNeuralPulse 2s ease-in-out infinite;
        }
        .cm-process-spin {
          animation: cmProcessSpin 3s linear infinite;
        }
        .cm-glow-new {
          animation: cmPulseGlow 2s ease-in-out infinite;
        }
        .cm-scroll-area {
          scrollbar-width: thin;
          scrollbar-color: rgba(255,255,255,0.1) transparent;
        }
        .cm-scroll-area::-webkit-scrollbar {
          width: 4px;
        }
        .cm-scroll-area::-webkit-scrollbar-track {
          background: transparent;
        }
        .cm-scroll-area::-webkit-scrollbar-thumb {
          background: rgba(255,255,255,0.1);
          border-radius: 2px;
        }
      `}</style>

      {/* Background glow effects */}
      <div className="absolute top-0 left-0 w-64 h-64 bg-blue-500/5 rounded-full blur-3xl" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-48 h-48 bg-violet-500/5 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-0 w-56 h-56 bg-emerald-500/5 rounded-full blur-3xl" />

      <div className="relative p-4 sm:p-6">
        {/* Header with auto-play toggle */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-violet-500/20 to-purple-500/20 border border-violet-500/20">
              <Brain className="h-3.5 w-3.5 text-violet-400" />
            </div>
            <span className="text-sm font-semibold text-white/80">Memory System Dashboard</span>
          </div>
          <button
            onClick={toggleAutoPlay}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition duration-200 hover:scale-105"
            style={{
              borderColor: isAutoPlaying ? "rgba(251,191,36,0.3)" : "rgba(255,255,255,0.1)",
              backgroundColor: isAutoPlaying ? "rgba(251,191,36,0.1)" : "rgba(255,255,255,0.03)",
              color: isAutoPlaying ? "#fbbf24" : "rgba(255,255,255,0.6)",
            }}
          >
            {isAutoPlaying ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
            {isAutoPlaying ? "Stop Demo" : "Auto Demo"}
          </button>
        </div>

        {/* 3-Panel Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_1.2fr_1fr] gap-3">
          {/* LEFT: Session Archive */}
          <MemorySessionArchive
            sessions={SESSION_DATA}
            selectedSession={selectedSession}
            feedingSession={feedingSession}
            onSessionClick={handleSessionClick}
          />

          {/* CENTER: Analysis Engine */}
          <MemoryAnalysisEngine
            processingStage={processingStage}
            feedingSession={feedingSession}
            sessions={SESSION_DATA}
          />

          {/* RIGHT: Memory Bank */}
          <MemoryRuleBank
            rules={MEMORY_RULES}
            highlightedRuleIds={highlightedRuleIds}
            glowingRules={glowingRules}
            activeQuery={activeQuery}
            selectedSession={selectedSession}
          />
        </div>

        {/* Bottom: Context Query Bar */}
        <MemoryContextQuery
          examples={QUERY_EXAMPLES}
          activeQuery={activeQuery}
          onQueryClick={handleQueryClick}
        />
      </div>
    </div>
  );
}

// =============================================================================
// SESSION ARCHIVE PANEL
// =============================================================================
function MemorySessionArchive({
  sessions,
  selectedSession,
  feedingSession,
  onSessionClick,
}: {
  sessions: SessionCard[];
  selectedSession: string | null;
  feedingSession: string | null;
  onSessionClick: (id: string) => void;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <div ref={rootRef} className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Panel header */}
      <div className="flex items-center gap-2 px-3 py-2.5 border-b border-white/[0.06]">
        <Archive className="h-3.5 w-3.5 text-blue-400" />
        <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">Session Archive</span>
        <span className="ml-auto text-[10px] text-white/30 font-mono">{sessions.length} sessions</span>
      </div>

      {/* Scrollable session list */}
      <div className="cm-scroll-area overflow-y-auto max-h-[280px] p-2 space-y-1.5">
        {sessions.map((session, idx) => {
          const isSelected = selectedSession === session.id;
          const isFeeding = feedingSession === session.id;

          return (
            <motion.button
              key={session.id}
              initial={{ opacity: 0, x: -12 }}
              animate={{
                opacity: isFeeding && inView ? [1, 0.5, 1] : 1,
                x: isFeeding && inView ? [0, 8, 0] : 0,
                scale: isSelected ? 1.02 : 1,
              }}
              transition={
                isFeeding && inView
                  ? { duration: 1.5, repeat: Infinity, ease: "easeInOut" }
                  : { ...SPRING_CONFIG, delay: idx * 0.04 }
              }
              onClick={() => onSessionClick(session.id)}
              className="w-full text-left group"
            >
              <div
                className="flex items-center gap-2.5 px-2.5 py-2 rounded-xl border transition duration-200"
                style={{
                  borderColor: isSelected
                    ? `${session.color}40`
                    : "rgba(255,255,255,0.04)",
                  backgroundColor: isSelected
                    ? `${session.color}10`
                    : "rgba(255,255,255,0.01)",
                }}
              >
                <div
                  className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md"
                  style={{
                    backgroundColor: `${session.color}15`,
                    color: session.color,
                  }}
                >
                  {session.icon}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-[11px] text-white/80 truncate leading-tight font-medium">
                    {session.topic}
                  </p>
                  <div className="flex items-center gap-1 mt-0.5">
                    <Clock className="h-2.5 w-2.5 text-white/25" />
                    <span className="text-[10px] text-white/30">{session.date}</span>
                  </div>
                </div>
                {isSelected && (
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={SPRING_CONFIG}
                  >
                    <ChevronRight className="h-3 w-3 text-white/40" />
                  </motion.div>
                )}
                {isFeeding && (
                  <motion.div
                    animate={inView ? { x: [0, 4, 0] } : { x: 0 }}
                    transition={inView ? { duration: 0.8, repeat: Infinity } : { duration: 0.2 }}
                    className="text-amber-400"
                  >
                    <Zap className="h-3 w-3" />
                  </motion.div>
                )}
              </div>
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// ANALYSIS ENGINE PANEL
// =============================================================================
function MemoryAnalysisEngine({
  processingStage,
  feedingSession,
  sessions,
}: {
  processingStage: number;
  feedingSession: string | null;
  sessions: SessionCard[];
}) {
  const isProcessing = processingStage >= 0;
  const feedSession = feedingSession
    ? sessions.find((s) => s.id === feedingSession)
    : null;

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Panel header */}
      <div className="flex items-center gap-2 px-3 py-2.5 border-b border-white/[0.06]">
        <Cpu className="h-3.5 w-3.5 text-violet-400" />
        <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">Analysis Engine</span>
        {isProcessing && (
          <motion.span
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="ml-auto text-[10px] text-amber-400 font-mono"
          >
            Processing...
          </motion.span>
        )}
      </div>

      <div className="p-3 flex flex-col items-center justify-center min-h-[248px]">
        {/* Neural network SVG visualization */}
        <div className="relative w-full">
          <svg viewBox="0 0 320 180" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
            {/* Neural connection lines */}
            {[0, 1, 2].map((row) =>
              [0, 1, 2, 3].map((col) => (
                <line
                  key={`neural-${row}-${col}`}
                  x1={40 + col * 80}
                  y1={50 + row * 35}
                  x2={40 + ((col + 1) % 4) * 80}
                  y2={50 + ((row + 1) % 3) * 35}
                  stroke={isProcessing ? "#8b5cf6" : "#ffffff"}
                  strokeWidth="0.5"
                  className="cm-neural-line"
                  style={{
                    animationDelay: `${(row * 4 + col) * 0.15}s`,
                    opacity: isProcessing ? 0.4 : 0.08,
                  }}
                />
              ))
            )}

            {/* Neural nodes */}
            {[0, 1, 2].map((row) =>
              [0, 1, 2, 3].map((col) => (
                <circle
                  key={`node-${row}-${col}`}
                  cx={40 + col * 80}
                  cy={50 + row * 35}
                  r={isProcessing && col === processingStage ? 5 : 2.5}
                  fill={
                    isProcessing && col <= processingStage
                      ? "#8b5cf6"
                      : "rgba(255,255,255,0.15)"
                  }
                  style={{
                    transition: "all 0.4s ease",
                    filter:
                      isProcessing && col === processingStage
                        ? "drop-shadow(0 0 6px #8b5cf6)"
                        : "none",
                  }}
                />
              ))
            )}
          </svg>

          {/* Feeding session card overlay */}
          <AnimatePresence>
            {feedSession && (
              <motion.div
                initial={{ opacity: 0, x: -30, y: 0 }}
                animate={{ opacity: 1, x: 0, y: 0 }}
                exit={{ opacity: 0, x: 30 }}
                transition={SPRING_CONFIG}
                className="absolute top-2 left-2 flex items-center gap-1.5 px-2 py-1 rounded-lg border text-[10px]"
                style={{
                  borderColor: `${feedSession.color}30`,
                  backgroundColor: `${feedSession.color}10`,
                  color: feedSession.color,
                }}
              >
                {feedSession.icon}
                <span className="font-medium truncate max-w-[100px]">{feedSession.topic}</span>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Processing stages progress */}
        <div className="w-full flex items-center gap-1 mt-2 px-1">
          {PROCESSING_STAGES.map((stage, idx) => {
            const isActive = processingStage === idx;
            const isDone = processingStage > idx;

            return (
              <div key={stage} className="flex-1 flex flex-col items-center gap-1">
                <motion.div
                  animate={{
                    scale: isActive ? 1.1 : 1,
                    backgroundColor: isDone
                      ? "rgba(139,92,246,0.2)"
                      : isActive
                        ? "rgba(139,92,246,0.15)"
                        : "rgba(255,255,255,0.02)",
                  }}
                  transition={SPRING_CONFIG}
                  className="w-full h-1.5 rounded-full border"
                  style={{
                    borderColor: isDone || isActive
                      ? "rgba(139,92,246,0.3)"
                      : "rgba(255,255,255,0.06)",
                  }}
                >
                  {(isDone || isActive) && (
                    <motion.div
                      initial={{ width: "0%" }}
                      animate={{ width: isDone ? "100%" : "60%" }}
                      transition={{ duration: 0.6, ease: "easeOut" }}
                      className="h-full rounded-full"
                      style={{ backgroundColor: "#8b5cf6" }}
                    />
                  )}
                </motion.div>
                <span
                  className="text-[10px] font-medium"
                  style={{
                    color: isDone || isActive
                      ? "#8b5cf6"
                      : "rgba(255,255,255,0.25)",
                  }}
                >
                  {stage}
                </span>
              </div>
            );
          })}
        </div>

        {/* Idle state message */}
        {!isProcessing && !feedingSession && (
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-xs text-white/30 mt-3 text-center"
          >
            Click a session or run auto-demo to see analysis
          </motion.p>
        )}
      </div>
    </div>
  );
}

// =============================================================================
// MEMORY RULE BANK PANEL
// =============================================================================
function MemoryRuleBank({
  rules,
  highlightedRuleIds,
  glowingRules,
  activeQuery,
  selectedSession,
}: {
  rules: MemoryRule[];
  highlightedRuleIds: Set<string>;
  glowingRules: Set<string>;
  activeQuery: QueryExample | null;
  selectedSession: string | null;
}) {
  const categories = ["code", "debug", "arch", "team"] as const;

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Panel header */}
      <div className="flex items-center gap-2 px-3 py-2.5 border-b border-white/[0.06]">
        <Database className="h-3.5 w-3.5 text-emerald-400" />
        <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">Memory Bank</span>
        <span className="ml-auto text-[10px] text-white/30 font-mono">{rules.length} rules</span>
      </div>

      <div className="cm-scroll-area overflow-y-auto max-h-[280px] p-2 space-y-2">
        {categories.map((cat) => {
          const meta = CATEGORY_META[cat];
          const catRules = rules.filter((r) => r.category === cat);

          return (
            <div key={cat}>
              {/* Category label */}
              <div className="flex items-center gap-1.5 px-1.5 py-1">
                <div style={{ color: meta.color }}>{meta.icon}</div>
                <span className="text-[10px] font-semibold uppercase tracking-wider" style={{ color: meta.color }}>
                  {meta.label}
                </span>
              </div>

              {/* Rules in this category */}
              <div className="space-y-1">
                {catRules.map((rule) => {
                  const isHighlighted = highlightedRuleIds.has(rule.id);
                  const isGlowing = glowingRules.has(rule.id);
                  const score = activeQuery?.scores[rule.id];

                  return (
                    <motion.div
                      key={rule.id}
                      animate={{
                        scale: isHighlighted ? 1.02 : 1,
                        borderColor: isHighlighted
                          ? `${meta.color}40`
                          : "rgba(255,255,255,0.04)",
                      }}
                      transition={SPRING_CONFIG}
                      className="relative px-2.5 py-1.5 rounded-lg border overflow-hidden"
                      style={{
                        backgroundColor: isHighlighted
                          ? `${meta.color}08`
                          : "rgba(255,255,255,0.01)",
                      }}
                    >
                      {/* New rule glow effect */}
                      {isGlowing && (
                        <div
                          className="absolute inset-0 rounded-lg cm-glow-new"
                          style={{
                            boxShadow: `inset 0 0 20px ${meta.color}30, 0 0 12px ${meta.color}20`,
                          }}
                        />
                      )}

                      <p className="relative text-xs text-white/60 leading-snug">
                        {rule.rule}
                      </p>

                      {/* Source session badges */}
                      {isHighlighted && selectedSession && (
                        <motion.div
                          initial={{ opacity: 0, height: 0 }}
                          animate={{ opacity: 1, height: "auto" }}
                          className="flex items-center gap-1 mt-1"
                        >
                          <span className="text-[10px] text-white/25">from:</span>
                          {rule.sourceSessions.map((sId) => (
                            <span
                              key={sId}
                              className="text-[10px] px-1.5 py-0.5 rounded-md font-mono"
                              style={{
                                backgroundColor: `${meta.color}15`,
                                color: meta.color,
                              }}
                            >
                              {sId}
                            </span>
                          ))}
                        </motion.div>
                      )}

                      {/* Relevance score bar */}
                      {score !== undefined && (
                        <motion.div
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          className="flex items-center gap-1.5 mt-1"
                        >
                          <div className="flex-1 h-1 rounded-full bg-white/[0.06] overflow-hidden">
                            <motion.div
                              initial={{ width: "0%" }}
                              animate={{ width: `${score * 100}%` }}
                              transition={{ duration: 0.8, ease: "easeOut", delay: 0.2 }}
                              className="h-full rounded-full"
                              style={{ backgroundColor: meta.color }}
                            />
                          </div>
                          <span className="text-[10px] font-mono" style={{ color: meta.color }}>
                            {Math.round(score * 100)}%
                          </span>
                        </motion.div>
                      )}

                      {/* New badge */}
                      {rule.isNew && isGlowing && (
                        <motion.span
                          initial={{ opacity: 0, scale: 0.8 }}
                          animate={{ opacity: 1, scale: 1 }}
                          className="absolute top-1 right-1 text-[10px] font-bold px-1.5 py-0.5 rounded-md"
                          style={{
                            backgroundColor: `${meta.color}20`,
                            color: meta.color,
                          }}
                        >
                          NEW
                        </motion.span>
                      )}
                    </motion.div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// CONTEXT QUERY BAR
// =============================================================================
function MemoryContextQuery({
  examples,
  activeQuery,
  onQueryClick,
}: {
  examples: QueryExample[];
  activeQuery: QueryExample | null;
  onQueryClick: (example: QueryExample) => void;
}) {
  return (
    <div className="mt-3 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl p-3">
      {/* Query bar */}
      <div className="flex items-center gap-2 px-3 py-2 rounded-xl border border-white/[0.06] bg-white/[0.02]">
        <Search className="h-3.5 w-3.5 text-white/30 shrink-0" />
        <span className="text-xs text-white/40 flex-1 truncate">
          {activeQuery
            ? activeQuery.query
            : "Describe your task to find relevant memories..."}
        </span>
        {activeQuery && (
          <motion.span
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            className="text-[10px] font-medium text-emerald-400 shrink-0"
          >
            {activeQuery.matchingRules.length} matches
          </motion.span>
        )}
      </div>

      {/* Example query chips */}
      <div className="flex flex-wrap gap-1.5 mt-2">
        {examples.map((example) => {
          const isActive = activeQuery?.label === example.label;

          return (
            <motion.button
              key={example.label}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.97 }}
              onClick={() => onQueryClick(example)}
              className="flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-medium border transition duration-200"
              style={{
                borderColor: isActive ? "rgba(16,185,129,0.3)" : "rgba(255,255,255,0.06)",
                backgroundColor: isActive ? "rgba(16,185,129,0.1)" : "rgba(255,255,255,0.02)",
                color: isActive ? "#10b981" : "rgba(255,255,255,0.5)",
              }}
            >
              <Target className="h-2.5 w-2.5" />
              {example.label}
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// ONBOARDING STEPS
// =============================================================================
function OnboardingSteps() {
  const steps = [
    {
      cmd: "cm onboard status",
      desc: "Check status and see recommendations",
    },
    {
      cmd: "cm onboard sample --fill-gaps",
      desc: "Get sessions filtered by playbook gaps",
    },
    {
      cmd: "cm onboard read /path/session.jsonl --template",
      desc: "Read session with rich context",
    },
    {
      cmd: 'cm playbook add "rule" --category "category"',
      desc: "Add extracted rules",
    },
    {
      cmd: "cm onboard mark-done /path/session.jsonl",
      desc: "Mark session as processed",
    },
  ];

  return (
    <div className="space-y-4">
      {steps.map((step, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.1 }}
          whileHover={{ x: 4, scale: 1.01 }}
          className="group flex items-start gap-4 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
        >
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white text-sm font-bold shadow-lg shadow-primary/20 group-hover:shadow-xl group-hover:shadow-primary/30 transition-shadow">
            {i + 1}
          </div>
          <div className="flex-1 min-w-0">
            <code className="text-sm text-primary break-all font-medium">{step.cmd}</code>
            <p className="text-sm text-white/50 mt-1">{step.desc}</p>
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// PROTOCOL STEP
// =============================================================================
function ProtocolStep({
  number,
  title,
  description,
}: {
  number: number;
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 text-white font-bold text-lg shadow-lg shadow-primary/20 group-hover:shadow-xl group-hover:shadow-primary/30 transition-shadow">
        {number}
      </div>
      <div className="pt-1">
        <h4 className="font-bold text-white text-lg group-hover:text-primary transition-colors">{title}</h4>
        <p className="text-sm text-white/60 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CATEGORY CARD
// =============================================================================
function CategoryCard({
  name,
  description,
  color,
}: {
  name: string;
  description: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -4, scale: 1.03 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${color} p-5 backdrop-blur-xl overflow-hidden transition duration-500 hover:border-white/[0.2]`}
    >
      {/* Decorative glow */}
      <div className="absolute -top-8 -right-8 w-24 h-24 bg-white/10 rounded-full blur-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <code className="relative text-sm text-white font-mono font-medium">{name}</code>
      <p className="relative text-xs text-white/60 mt-2">{description}</p>
    </motion.div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-emerald-500/20 bg-emerald-500/5 backdrop-blur-xl transition duration-300 hover:border-emerald-500/40 hover:bg-emerald-500/10"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400 shadow-lg shadow-emerald-500/10 group-hover:shadow-emerald-500/20 transition-shadow">
        <Lightbulb className="h-5 w-5" />
      </div>
      <div>
        <p className="font-semibold text-white group-hover:text-emerald-300 transition-colors">{title}</p>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}
