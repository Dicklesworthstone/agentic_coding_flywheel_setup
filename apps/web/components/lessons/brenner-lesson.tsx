'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  FlaskConical,
  Terminal,
  Zap,
  BookOpen,
  Search,
  Settings,
  Play,
  Users,
  Lightbulb,
  CheckCircle2,
  FileText,
  Link2,
  TrendingUp,
  Database,
  Eye,
  Network,
  ArrowRight,
  Sparkles,
  Target,
  AlertTriangle,
  ThumbsUp,
  ThumbsDown,
  Minus,
  Clock,
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

export function BrennerLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Coordinate multi-agent AI research sessions with structured scientific methodology.
      </GoalBanner>

      {/* Section 1: What Is Brenner Bot */}
      <Section title="What Is Brenner Bot?" icon={<FlaskConical className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>Brenner Bot</Highlight> is a research orchestration platform inspired by
          Nobel laureate Sydney Brenner&apos;s scientific methodology. It coordinates multi-agent
          AI research sessions with systematic problem formulation and rigorous constraint-based
          reasoning.
        </Paragraph>
        <Paragraph>
          The system combines a curated corpus of 236 transcript sections with multi-model AI
          syntheses from Claude, GPT, and Gemini to enable collaborative scientific research
          conversations.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<BookOpen className="h-5 w-5" />}
              title="Primary Corpus"
              description="236 sections with &sect;n citations"
              gradient="from-rose-500/20 to-pink-500/20"
            />
            <FeatureCard
              icon={<Users className="h-5 w-5" />}
              title="Multi-Model"
              description="Claude, GPT, Gemini syntheses"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Lightbulb className="h-5 w-5" />}
              title="Hypothesis Slates"
              description="Always includes third alternative"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Quote Bank"
              description="Searchable verbatim primitives"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Scientific Methodology */}
      <Section title="Scientific Methodology" icon={<Lightbulb className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Brenner Bot emphasizes rigorous scientific reasoning with these principles.
        </Paragraph>

        <InteractiveResearchPipeline />

        <div className="mt-8 grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-rose-500/10 border border-rose-500/30">
            <span className="text-rose-400 font-semibold">Problem Formulation</span>
            <p className="text-white/80 text-sm mt-1">Clear statement of what you&apos;re trying to understand</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">Discriminative Design</span>
            <p className="text-white/80 text-sm mt-1">Experiments that distinguish hypotheses</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">Third Alternative</span>
            <p className="text-white/80 text-sm mt-1">Always consider &quot;both hypotheses are wrong&quot;</p>
          </div>
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">Constraint Reasoning</span>
            <p className="text-white/80 text-sm mt-1">What data rules out, not just suggests</p>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Section 3: Quick Start */}
      <Section title="Quick Start" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Get started with these essential commands.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'brenner --version', description: 'Check installation' },
            { command: 'brenner doctor', description: 'Run diagnostics' },
            { command: 'brenner corpus search "query"', description: 'Search transcripts' },
            { command: 'brenner session start "topic"', description: 'Start research session' },
          ]}
        />

        <TipBox variant="tip">
          Research sessions coordinate via Agent Mail. Make sure Agent Mail is running first.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Corpus Search */}
      <Section title="Corpus Search" icon={<Search className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Search the primary source corpus for relevant passages.
        </Paragraph>

        <CodeBlock
          code={`# Search the transcript corpus
brenner corpus search "experimental design"

# List available sections
brenner corpus list

# Build excerpts from specific sections
brenner excerpt build --sections 42,43,44

# Export with citations
brenner excerpt build --sections 42-50 --format markdown`}
          filename="Corpus Commands"
        />

        <TipBox variant="info">
          Citations use stable &sect;n format (e.g., &sect;42) for reliable referencing.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Research Sessions */}
      <Section title="Research Sessions" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Launch multi-agent research workflows.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'brenner session start "hypothesis"', description: 'Start new session' },
            { command: 'brenner session resume <id>', description: 'Resume existing session' },
            { command: 'brenner session list', description: 'List active sessions' },
          ]}
        />

        <Paragraph>
          Sessions produce structured artifacts:
        </Paragraph>

        <div className="grid gap-2 text-sm">
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Hypothesis Slates</span> — Multiple competing explanations
          </div>
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Discriminative Tests</span> — Experiments that distinguish hypotheses
          </div>
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Assumption Ledgers</span> — Explicit premises with verification
          </div>
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Adversarial Critiques</span> — Challenges to the framing itself
          </div>
        </div>
      </Section>

      <Divider />

      {/* Section 6: Tool Integration */}
      <Section title="Tool Integration" icon={<Zap className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          Brenner Bot integrates with other flywheel tools.
        </Paragraph>

        <div className="space-y-4">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.4 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">Brenner + Agent Mail</h4>
            <p className="text-muted-foreground text-sm">
              Research sessions use Agent Mail for durable threads between agents.
              Each agent has an inbox/outbox with acknowledgment tracking.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.45 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">Brenner + NTM</h4>
            <p className="text-muted-foreground text-sm">
              NTM spawns parallel agent sessions for research. Use NTM to manage
              the tmux layout while Brenner coordinates the research flow.
            </p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5 }}
            className="p-4 rounded-xl border border-border/50 bg-card/30"
          >
            <h4 className="font-semibold text-primary mb-2">Brenner + CASS</h4>
            <p className="text-muted-foreground text-sm">
              Research session history is indexed by CASS. Search past sessions
              to build on previous research findings.
            </p>
          </motion.div>
        </div>
      </Section>

      <Divider />

      {/* Section 7: Web Interface */}
      <Section title="Web Interface" icon={<Settings className="h-5 w-5" />} delay={0.4}>
        <Paragraph>
          The web app at brennerbot.org provides additional features.
        </Paragraph>

        <div className="grid gap-2 text-sm">
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Corpus Browsing</span> — Full-text search with section navigation
          </div>
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Excerpt Composition</span> — Build cited passages from selections
          </div>
          <div className="p-2 rounded bg-card/30 border border-border/50">
            <span className="text-primary font-medium">Session Visualization</span> — View research session structure
          </div>
        </div>

        <TipBox variant="info">
          The CLI and web app complement each other—use CLI for automation and web for browsing.
        </TipBox>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE RESEARCH SESSION COCKPIT
// =============================================================================

const springTransition = { type: "spring" as const, stiffness: 200, damping: 25 };

interface ResearchPhase {
  id: number;
  key: string;
  label: string;
  icon: React.ReactNode;
  color: string;
  textColor: string;
  borderColor: string;
  bgColor: string;
  description: string;
  terminalLines: string[];
}

const RESEARCH_PHASES: ResearchPhase[] = [
  {
    id: 0,
    key: "hypothesis",
    label: "Hypothesis Formulation",
    icon: <Lightbulb className="h-4 w-4" />,
    color: "#3b82f6",
    textColor: "text-blue-400",
    borderColor: "border-blue-500/30",
    bgColor: "bg-blue-500/10",
    description: "Define competing hypotheses with explicit assumptions",
    terminalLines: [
      "$ brenner session start \"gene regulation\"",
      "Session #BR-0847 initialized",
      "Loading corpus sections 42-58...",
      "Generating hypothesis slate...",
      "H1: Transcriptional control dominates",
      "H2: Post-translational modification key",
      "H3: Neither -- combinatorial regulation",
    ],
  },
  {
    id: 1,
    key: "corpus",
    label: "Corpus Search",
    icon: <Search className="h-4 w-4" />,
    color: "#8b5cf6",
    textColor: "text-violet-400",
    borderColor: "border-violet-500/30",
    bgColor: "bg-violet-500/10",
    description: "Query the 236-section transcript corpus for evidence",
    terminalLines: [
      "$ brenner corpus search \"transcriptional control\"",
      "Searching 236 sections...",
      "Found 14 matches across 8 sections",
      "\u00a742: \"...the key insight was control...\"",
      "\u00a745: \"...not just transcription but...\"",
      "\u00a751: \"...you have to think about...\"",
      "Indexing quote bank...",
    ],
  },
  {
    id: 2,
    key: "evidence",
    label: "Evidence Extraction",
    icon: <FileText className="h-4 w-4" />,
    color: "#f59e0b",
    textColor: "text-amber-400",
    borderColor: "border-amber-500/30",
    bgColor: "bg-amber-500/10",
    description: "Extract and tag evidence for each hypothesis",
    terminalLines: [
      "$ brenner excerpt build --sections 42,45,51",
      "Extracting verbatim primitives...",
      "Tagged 6 excerpts supporting H1",
      "Tagged 4 excerpts supporting H2",
      "Tagged 3 excerpts contradicting H1",
      "Building citation graph...",
      "Evidence matrix updated",
    ],
  },
  {
    id: 3,
    key: "crossref",
    label: "Cross-Referencing",
    icon: <Link2 className="h-4 w-4" />,
    color: "#ec4899",
    textColor: "text-pink-400",
    borderColor: "border-pink-500/30",
    bgColor: "bg-pink-500/10",
    description: "Multi-agent triangulation across model syntheses",
    terminalLines: [
      "$ brenner crossref --session BR-0847",
      "Dispatching to 3 agent lanes...",
      "[Claude] Corpus analysis complete",
      "[GPT] Pattern cross-reference done",
      "[Gemini] Adversarial critique ready",
      "Merging triangulation results...",
      "Conflict detected: H1 vs H3 on \u00a745",
    ],
  },
  {
    id: 4,
    key: "synthesis",
    label: "Synthesis",
    icon: <Sparkles className="h-4 w-4" />,
    color: "#10b981",
    textColor: "text-emerald-400",
    borderColor: "border-emerald-500/30",
    bgColor: "bg-emerald-500/10",
    description: "Merge findings and score hypotheses against evidence",
    terminalLines: [
      "$ brenner synthesize --session BR-0847",
      "Scoring hypotheses against tests...",
      "H1: 0.62 confidence (weakened)",
      "H2: 0.78 confidence (strengthened)",
      "H3: 0.85 confidence (strongest)",
      "Updating assumption ledger...",
      "Synthesis report generated",
    ],
  },
  {
    id: 5,
    key: "publication",
    label: "Publication",
    icon: <BookOpen className="h-4 w-4" />,
    color: "#06b6d4",
    textColor: "text-cyan-400",
    borderColor: "border-cyan-500/30",
    bgColor: "bg-cyan-500/10",
    description: "Export structured findings with full citations",
    terminalLines: [
      "$ brenner publish --session BR-0847",
      "Compiling research report...",
      "Embedding 23 citations (\u00a7 format)",
      "Attaching assumption ledger (14 items)",
      "Exporting to markdown...",
      "Published: BR-0847-synthesis.md",
      "Session archived to CASS index",
    ],
  },
];

interface HypothesisData {
  id: string;
  label: string;
  shortLabel: string;
  color: string;
  textColor: string;
  initialConfidence: number;
}

const HYPOTHESES: HypothesisData[] = [
  {
    id: "h1",
    label: "Transcriptional control dominates regulation",
    shortLabel: "H1: Transcriptional",
    color: "#3b82f6",
    textColor: "text-blue-400",
    initialConfidence: 50,
  },
  {
    id: "h2",
    label: "Post-translational modification is the key driver",
    shortLabel: "H2: Post-translational",
    color: "#f59e0b",
    textColor: "text-amber-400",
    initialConfidence: 50,
  },
  {
    id: "h3",
    label: "Combinatorial regulation (third alternative)",
    shortLabel: "H3: Combinatorial",
    color: "#10b981",
    textColor: "text-emerald-400",
    initialConfidence: 50,
  },
];

// Confidence values at each research phase
const CONFIDENCE_BY_PHASE: Record<string, number[]> = {
  h1: [50, 55, 60, 52, 42, 35],
  h2: [50, 48, 55, 65, 72, 78],
  h3: [50, 52, 58, 70, 82, 88],
};

interface EvidenceItem {
  id: string;
  text: string;
  section: string;
  supports: string;
  stance: "supports" | "contradicts" | "neutral";
  appearsAtPhase: number;
}

const EVIDENCE_ITEMS: EvidenceItem[] = [
  { id: "e1", text: "Control at transcription level observed", section: "\u00a742", supports: "h1", stance: "supports", appearsAtPhase: 1 },
  { id: "e2", text: "Post-translational effects are secondary", section: "\u00a745", supports: "h1", stance: "supports", appearsAtPhase: 1 },
  { id: "e3", text: "Protein modification drives phenotype shift", section: "\u00a748", supports: "h2", stance: "supports", appearsAtPhase: 2 },
  { id: "e4", text: "Transcription alone insufficient", section: "\u00a751", supports: "h1", stance: "contradicts", appearsAtPhase: 2 },
  { id: "e5", text: "Multiple layers interact synergistically", section: "\u00a754", supports: "h3", stance: "supports", appearsAtPhase: 3 },
  { id: "e6", text: "Combinatorial model explains outliers", section: "\u00a758", supports: "h3", stance: "supports", appearsAtPhase: 3 },
  { id: "e7", text: "Single-mechanism models consistently fail", section: "\u00a761", supports: "h3", stance: "supports", appearsAtPhase: 4 },
  { id: "e8", text: "Cross-model consensus on multi-layer regulation", section: "\u00a764", supports: "h3", stance: "supports", appearsAtPhase: 4 },
];

interface CorpusSource {
  label: string;
  sections: string;
  hitCount: number;
  color: string;
}

const CORPUS_SOURCES: CorpusSource[] = [
  { label: "Transcription Studies", sections: "\u00a742-48", hitCount: 14, color: "#3b82f6" },
  { label: "Protein Modification", sections: "\u00a749-55", hitCount: 9, color: "#f59e0b" },
  { label: "Regulatory Networks", sections: "\u00a756-62", hitCount: 11, color: "#10b981" },
  { label: "Model Comparisons", sections: "\u00a763-70", hitCount: 7, color: "#ec4899" },
  { label: "Historical Context", sections: "\u00a771-80", hitCount: 5, color: "#8b5cf6" },
];

interface KnowledgeNode {
  id: string;
  label: string;
  x: number;
  y: number;
  color: string;
  appearsAtPhase: number;
}

interface KnowledgeEdge {
  from: string;
  to: string;
  appearsAtPhase: number;
}

const KNOWLEDGE_NODES: KnowledgeNode[] = [
  { id: "k1", label: "Transcription", x: 50, y: 30, color: "#3b82f6", appearsAtPhase: 0 },
  { id: "k2", label: "Translation", x: 170, y: 25, color: "#8b5cf6", appearsAtPhase: 1 },
  { id: "k3", label: "Modification", x: 290, y: 35, color: "#f59e0b", appearsAtPhase: 1 },
  { id: "k4", label: "Regulation", x: 110, y: 100, color: "#10b981", appearsAtPhase: 2 },
  { id: "k5", label: "Phenotype", x: 230, y: 105, color: "#ec4899", appearsAtPhase: 3 },
  { id: "k6", label: "Feedback", x: 50, y: 110, color: "#06b6d4", appearsAtPhase: 3 },
  { id: "k7", label: "Combinatorial", x: 170, y: 65, color: "#22c55e", appearsAtPhase: 4 },
];

const KNOWLEDGE_EDGES: KnowledgeEdge[] = [
  { from: "k1", to: "k2", appearsAtPhase: 1 },
  { from: "k2", to: "k3", appearsAtPhase: 1 },
  { from: "k1", to: "k4", appearsAtPhase: 2 },
  { from: "k3", to: "k4", appearsAtPhase: 2 },
  { from: "k4", to: "k5", appearsAtPhase: 3 },
  { from: "k6", to: "k1", appearsAtPhase: 3 },
  { from: "k4", to: "k7", appearsAtPhase: 4 },
  { from: "k7", to: "k5", appearsAtPhase: 4 },
  { from: "k3", to: "k7", appearsAtPhase: 4 },
  { from: "k6", to: "k4", appearsAtPhase: 4 },
];

// =============================================================================
// MAIN COCKPIT COMPONENT
// =============================================================================

function InteractiveResearchPipeline() {
  const [activePhase, setActivePhase] = useState(0);
  const [isAutoPlaying, setIsAutoPlaying] = useState(false);
  const [terminalLineCount, setTerminalLineCount] = useState(0);
  const [showEvidenceBoard, setShowEvidenceBoard] = useState(false);
  const autoPlayRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const terminalTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const terminalTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  // Animate terminal lines when phase changes
  const animateTerminal = useCallback((phase: number) => {
    // Clear previous terminal animation timers
    for (const t of terminalTimersRef.current) clearTimeout(t);
    terminalTimersRef.current = [];
    if (terminalTimerRef.current) clearTimeout(terminalTimerRef.current);

    setTerminalLineCount(0);
    const lines = RESEARCH_PHASES[phase].terminalLines;
    let count = 0;
    function showNextLine() {
      count += 1;
      if (count <= lines.length) {
        setTerminalLineCount(count);
        const t = setTimeout(showNextLine, 180);
        terminalTimersRef.current.push(t);
        terminalTimerRef.current = t;
      }
    }
    const initial = setTimeout(showNextLine, 300);
    terminalTimersRef.current.push(initial);
    terminalTimerRef.current = initial;
  }, []);

  const goToPhase = useCallback((phase: number) => {
    setActivePhase(phase);
    animateTerminal(phase);
  }, [animateTerminal]);

  useEffect(() => {
    animateTerminal(0);
    return () => {
      if (terminalTimerRef.current) clearTimeout(terminalTimerRef.current);
      for (const t of terminalTimersRef.current) clearTimeout(t);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Auto-play through phases
  useEffect(() => {
    if (isAutoPlaying) {
      autoPlayRef.current = setInterval(() => {
        setActivePhase((prev) => {
          const next = (prev + 1) % RESEARCH_PHASES.length;
          // Defer side effect out of state updater
          setTimeout(() => animateTerminal(next), 0);
          return next;
        });
      }, 3500);
    }
    return () => {
      if (autoPlayRef.current) clearInterval(autoPlayRef.current);
    };
  }, [isAutoPlaying, animateTerminal]);

  const currentPhase = RESEARCH_PHASES[activePhase];
  const visibleEvidence = EVIDENCE_ITEMS.filter((e) => e.appearsAtPhase <= activePhase);
  const visibleKnowledgeNodes = KNOWLEDGE_NODES.filter((n) => n.appearsAtPhase <= activePhase);
  const visibleKnowledgeEdges = KNOWLEDGE_EDGES.filter((e) => e.appearsAtPhase <= activePhase);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={springTransition}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* CSS animations */}
      <style>{`
        @keyframes brennerPulse {
          0%, 100% { opacity: 0.4; transform: scale(1); }
          50% { opacity: 0.8; transform: scale(1.1); }
        }
        @keyframes brennerScan {
          0% { transform: translateX(-100%); }
          100% { transform: translateX(200%); }
        }
        @keyframes brennerTypeCursor {
          0%, 100% { opacity: 1; }
          50% { opacity: 0; }
        }
        .brenner-pulse { animation: brennerPulse 2.5s ease-in-out infinite; }
        .brenner-pulse-d1 { animation-delay: 0.5s; }
        .brenner-pulse-d2 { animation-delay: 1.0s; }
        .brenner-pulse-d3 { animation-delay: 1.5s; }
        .brenner-scan { animation: brennerScan 2s ease-in-out infinite; }
        .brenner-cursor { animation: brennerTypeCursor 0.8s step-end infinite; }
        @keyframes edgeDash {
          0% { stroke-dashoffset: 12; }
          100% { stroke-dashoffset: 0; }
        }
        .brenner-edge-animated { animation: edgeDash 1s linear infinite; }
      `}</style>

      {/* Header bar */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-white/[0.06] bg-white/[0.02]">
        <FlaskConical className="h-4 w-4 text-violet-400" />
        <span className="text-sm font-medium text-white/80">Research Session Cockpit</span>
        <span className="mx-2 text-white/20">|</span>
        <span className="text-xs text-white/40 font-mono">BR-0847</span>
        <div className="ml-auto flex items-center gap-3">
          <button
            onClick={() => setShowEvidenceBoard(!showEvidenceBoard)}
            className={`text-xs px-2 py-1 rounded border transition cursor-pointer ${
              showEvidenceBoard
                ? "border-violet-500/40 bg-violet-500/10 text-violet-300"
                : "border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/70"
            }`}
          >
            <Eye className="h-3 w-3 inline mr-1" />
            Evidence Board
          </button>
          <button
            onClick={() => setIsAutoPlaying(!isAutoPlaying)}
            className={`text-xs px-2 py-1 rounded border transition cursor-pointer ${
              isAutoPlaying
                ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-300"
                : "border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/70"
            }`}
          >
            {isAutoPlaying ? "Pause" : "Auto-play"}
          </button>
        </div>
      </div>

      <div className="relative p-5">
        {/* Background glow */}
        <div
          className="absolute top-0 left-1/4 w-48 h-48 rounded-full blur-3xl pointer-events-none transition-colors duration-1000"
          style={{ backgroundColor: `${currentPhase.color}08` }}
        />
        <div
          className="absolute bottom-0 right-1/4 w-48 h-48 rounded-full blur-3xl pointer-events-none transition-colors duration-1000"
          style={{ backgroundColor: `${currentPhase.color}05` }}
        />

        {/* Phase timeline bar */}
        <PhaseTimeline
          phases={RESEARCH_PHASES}
          activePhase={activePhase}
          onPhaseClick={goToPhase}
        />

        {/* Main content area - 2 column layout */}
        <div className="mt-5 grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Left column: terminal + corpus search */}
          <div className="space-y-4">
            {/* Mini terminal */}
            <MiniTerminal
              phase={currentPhase}
              lineCount={terminalLineCount}
            />

            {/* Corpus search visualization */}
            <CorpusSearchViz
              activePhase={activePhase}
              sources={CORPUS_SOURCES}
            />
          </div>

          {/* Right column: confidence + knowledge graph */}
          <div className="space-y-4">
            {/* Hypothesis confidence meters */}
            <ConfidencePanel
              hypotheses={HYPOTHESES}
              activePhase={activePhase}
            />

            {/* Knowledge graph */}
            <KnowledgeGraph
              nodes={visibleKnowledgeNodes}
              edges={visibleKnowledgeEdges}
              allNodes={KNOWLEDGE_NODES}
              activePhase={activePhase}
            />
          </div>
        </div>

        {/* Evidence board (expandable) */}
        <AnimatePresence>
          {showEvidenceBoard && (
            <motion.div
              initial={{ opacity: 0, height: 0, marginTop: 0 }}
              animate={{ opacity: 1, height: "auto", marginTop: 16 }}
              exit={{ opacity: 0, height: 0, marginTop: 0 }}
              transition={springTransition}
              className="overflow-hidden"
            >
              <EvidenceBoard
                evidence={visibleEvidence}
                hypotheses={HYPOTHESES}
                activePhase={activePhase}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Phase progress bar */}
      <div className="px-4 py-3 border-t border-white/[0.06] bg-white/[0.02]">
        <div className="flex items-center justify-between mb-1.5">
          <span className="text-xs text-white/50">
            Phase {activePhase + 1} of {RESEARCH_PHASES.length}: {currentPhase.label}
          </span>
          <span className="text-xs text-white/40">
            {Math.round(((activePhase + 1) / RESEARCH_PHASES.length) * 100)}%
          </span>
        </div>
        <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="h-full rounded-full"
            style={{
              background: `linear-gradient(to right, ${RESEARCH_PHASES[0].color}, ${currentPhase.color})`,
            }}
            initial={{ width: "0%" }}
            animate={{ width: `${((activePhase + 1) / RESEARCH_PHASES.length) * 100}%` }}
            transition={{ type: "spring", stiffness: 100, damping: 20 }}
          />
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// PHASE TIMELINE
// =============================================================================

function PhaseTimeline({
  phases,
  activePhase,
  onPhaseClick,
}: {
  phases: ResearchPhase[];
  activePhase: number;
  onPhaseClick: (id: number) => void;
}) {
  return (
    <div className="flex items-center gap-1 overflow-x-auto pb-1">
      {phases.map((phase, i) => {
        const isActive = i === activePhase;
        const isPast = i < activePhase;
        return (
          <div key={phase.key} className="flex items-center">
            <motion.button
              onClick={() => onPhaseClick(i)}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.97 }}
              className={`relative flex items-center gap-1.5 px-3 py-2 rounded-lg border transition cursor-pointer text-xs font-medium whitespace-nowrap ${
                isActive
                  ? `${phase.borderColor} ${phase.bgColor} ${phase.textColor}`
                  : isPast
                    ? "border-white/[0.12] bg-white/[0.04] text-white/60"
                    : "border-white/[0.06] bg-white/[0.01] text-white/35 hover:text-white/50 hover:border-white/[0.1]"
              }`}
            >
              {isActive && (
                <motion.div
                  className="absolute inset-0 rounded-lg blur-xl -z-10"
                  style={{ backgroundColor: `${phase.color}20` }}
                  layoutId="phaseGlow"
                  transition={springTransition}
                />
              )}
              <span className={isActive ? phase.textColor : isPast ? "text-white/50" : "text-white/30"}>
                {phase.icon}
              </span>
              <span className="hidden sm:inline">{phase.label}</span>
              <span className="sm:hidden">{phase.label.split(" ")[0]}</span>
              {isPast && <CheckCircle2 className="h-3 w-3 text-emerald-400/60" />}
            </motion.button>
            {i < phases.length - 1 && (
              <div className="flex items-center mx-0.5">
                <ArrowRight className={`h-3 w-3 ${isPast ? "text-white/30" : "text-white/10"}`} />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// =============================================================================
// MINI TERMINAL
// =============================================================================

function MiniTerminal({
  phase,
  lineCount,
}: {
  phase: ResearchPhase;
  lineCount: number;
}) {
  const terminalRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (terminalRef.current) {
      const el = terminalRef.current;
      setTimeout(() => {
        el.scrollTop = el.scrollHeight;
      }, 0);
    }
  }, [lineCount]);

  const visibleLines = phase.terminalLines.slice(0, lineCount);
  const isTyping = lineCount < phase.terminalLines.length;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/40 overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <Terminal className="h-3.5 w-3.5 text-emerald-400" />
        <span className="text-xs text-white/50 font-mono">brenner-session</span>
        <div className="ml-auto flex gap-1.5">
          <div className="h-2 w-2 rounded-full bg-red-500/50" />
          <div className="h-2 w-2 rounded-full bg-amber-500/50" />
          <div className="h-2 w-2 rounded-full bg-emerald-500/50" />
        </div>
      </div>
      <div ref={terminalRef} className="p-3 font-mono text-xs space-y-0.5 h-[154px] overflow-y-auto">
        <AnimatePresence mode="popLayout">
          {visibleLines.map((line, i) => {
            const isCommand = line.startsWith("$");
            return (
              <motion.div
                key={`${phase.key}-${i}`}
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ ...springTransition, delay: 0.02 }}
              >
                <span className={isCommand ? "text-emerald-400" : "text-white/60"}>
                  {line}
                </span>
              </motion.div>
            );
          })}
        </AnimatePresence>
        {isTyping && (
          <span className="brenner-cursor text-emerald-400">_</span>
        )}
      </div>
    </div>
  );
}

// =============================================================================
// CORPUS SEARCH VISUALIZATION
// =============================================================================

function CorpusSearchViz({
  activePhase,
  sources,
}: {
  activePhase: number;
  sources: CorpusSource[];
}) {
  const visibleCount = Math.min(sources.length, activePhase + 2);
  const visibleSources = sources.slice(0, visibleCount);

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <Database className="h-3.5 w-3.5 text-violet-400" />
        <span className="text-xs text-white/50">Corpus Query Fan-out</span>
        <span className="ml-auto text-xs text-white/30">{visibleCount} sources</span>
      </div>
      <div className="p-3">
        {/* Central query node */}
        <div className="flex items-center gap-3 mb-3">
          <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-violet-500/30 bg-violet-500/10">
            <Search className="h-3 w-3 text-violet-400" />
            <span className="text-xs text-violet-300 font-mono">query</span>
          </div>
          <div className="flex-1 relative h-px">
            <div className="absolute inset-0 bg-gradient-to-r from-violet-500/40 to-transparent" />
            <div className="absolute top-1/2 -translate-y-1/2 h-2 w-8 brenner-scan opacity-60">
              <div className="h-full w-full bg-gradient-to-r from-transparent via-violet-400 to-transparent rounded-full" />
            </div>
          </div>
        </div>

        {/* Source fan-out */}
        <div className="space-y-1.5 ml-4">
          <AnimatePresence>
            {visibleSources.map((source, i) => (
              <motion.div
                key={source.label}
                initial={{ opacity: 0, x: -12, scaleX: 0.9 }}
                animate={{ opacity: 1, x: 0, scaleX: 1 }}
                transition={{ ...springTransition, delay: i * 0.08 }}
                className="flex items-center gap-2"
              >
                <div className="w-px h-4" style={{ backgroundColor: `${source.color}40` }} />
                <div
                  className="flex items-center gap-2 flex-1 px-2 py-1 rounded border bg-white/[0.02]"
                  style={{ borderColor: `${source.color}20` }}
                >
                  <div className="h-2 w-2 rounded-full brenner-pulse" style={{ backgroundColor: source.color, animationDelay: `${i * 0.3}s` }} />
                  <span className="text-xs text-white/60 flex-1">{source.label}</span>
                  <span className="text-xs text-white/30 font-mono">{source.sections}</span>
                  <span
                    className="text-xs font-medium px-1.5 rounded"
                    style={{ color: source.color, backgroundColor: `${source.color}15` }}
                  >
                    {source.hitCount} hits
                  </span>
                </div>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// CONFIDENCE PANEL
// =============================================================================

function ConfidencePanel({
  hypotheses,
  activePhase,
}: {
  hypotheses: HypothesisData[];
  activePhase: number;
}) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <TrendingUp className="h-3.5 w-3.5 text-amber-400" />
        <span className="text-xs text-white/50">Hypothesis Confidence</span>
        <span className="ml-auto text-xs text-white/30">
          Phase {activePhase + 1}
        </span>
      </div>
      <div className="p-3 space-y-3">
        {hypotheses.map((hyp) => {
          const confidence = CONFIDENCE_BY_PHASE[hyp.id][activePhase];
          const prevConfidence = activePhase > 0 ? CONFIDENCE_BY_PHASE[hyp.id][activePhase - 1] : hyp.initialConfidence;
          const delta = confidence - prevConfidence;
          const isLeading = confidence === Math.max(
            ...hypotheses.map((h) => CONFIDENCE_BY_PHASE[h.id][activePhase])
          );

          return (
            <div key={hyp.id} className="space-y-1">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div
                    className="h-2.5 w-2.5 rounded-full"
                    style={{ backgroundColor: hyp.color }}
                  />
                  <span className={`text-xs font-medium ${hyp.textColor}`}>
                    {hyp.shortLabel}
                  </span>
                  {isLeading && (
                    <motion.span
                      initial={{ opacity: 0, scale: 0.8 }}
                      animate={{ opacity: 1, scale: 1 }}
                      className="text-xs px-1 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                    >
                      leading
                    </motion.span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  {delta !== 0 && (
                    <span className={`text-xs ${delta > 0 ? "text-emerald-400" : "text-red-400"}`}>
                      {delta > 0 ? "+" : ""}{delta}%
                    </span>
                  )}
                  <span className="text-xs text-white/60 font-mono w-8 text-right">{confidence}%</span>
                </div>
              </div>
              {/* Confidence bar */}
              <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  className="h-full rounded-full"
                  style={{ backgroundColor: hyp.color }}
                  initial={{ width: "50%" }}
                  animate={{ width: `${confidence}%` }}
                  transition={{ type: "spring", stiffness: 120, damping: 20 }}
                />
              </div>
            </div>
          );
        })}

        {/* Mini spark history */}
        <div className="mt-2 pt-2 border-t border-white/[0.06]">
          <span className="text-xs text-white/30 mb-1 block">Confidence trajectory</span>
          <div className="flex items-end gap-0.5 h-8">
            {RESEARCH_PHASES.map((_, phaseIdx) => {
              const isCurrentOrPast = phaseIdx <= activePhase;
              return (
                <div key={`spark-${phaseIdx}`} className="flex-1 flex items-end gap-px">
                  {hypotheses.map((hyp) => {
                    const val = CONFIDENCE_BY_PHASE[hyp.id][phaseIdx];
                    return (
                      <motion.div
                        key={`${hyp.id}-${phaseIdx}`}
                        className="flex-1 rounded-t-sm"
                        style={{
                          backgroundColor: isCurrentOrPast ? hyp.color : `${hyp.color}20`,
                          opacity: isCurrentOrPast ? 0.7 : 0.2,
                        }}
                        initial={{ height: 0 }}
                        animate={{ height: `${(val / 100) * 32}px` }}
                        transition={{ type: "spring", stiffness: 150, damping: 20, delay: phaseIdx * 0.05 }}
                      />
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// KNOWLEDGE GRAPH
// =============================================================================

function KnowledgeGraph({
  nodes,
  edges,
  allNodes,
  activePhase,
}: {
  nodes: KnowledgeNode[];
  edges: KnowledgeEdge[];
  allNodes: KnowledgeNode[];
  activePhase: number;
}) {
  const nodeMap = new Map(allNodes.map((n) => [n.id, n]));

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <Network className="h-3.5 w-3.5 text-cyan-400" />
        <span className="text-xs text-white/50">Knowledge Graph</span>
        <span className="ml-auto text-xs text-white/30">{nodes.length} concepts</span>
      </div>
      <div className="relative h-[150px] overflow-hidden">
        <svg className="absolute inset-0 w-full h-full" viewBox="0 0 340 140">
          {/* Edges */}
          {edges.map((edge) => {
            const fromNode = nodeMap.get(edge.from);
            const toNode = nodeMap.get(edge.to);
            if (!fromNode || !toNode) return null;
            return (
              <motion.line
                key={`${edge.from}-${edge.to}`}
                x1={fromNode.x + 30}
                y1={fromNode.y + 10}
                x2={toNode.x + 30}
                y2={toNode.y + 10}
                stroke={fromNode.color}
                strokeWidth={1}
                strokeOpacity={0.3}
                strokeDasharray="4 4"
                className="brenner-edge-animated"
                initial={{ pathLength: 0, opacity: 0 }}
                animate={{ pathLength: 1, opacity: 1 }}
                transition={{ duration: 0.6, delay: 0.2 }}
              />
            );
          })}
        </svg>

        {/* Nodes */}
        <AnimatePresence>
          {nodes.map((node) => (
            <motion.div
              key={node.id}
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.5 }}
              transition={springTransition}
              className="absolute"
              style={{ left: node.x, top: node.y }}
            >
              <div
                className="px-2 py-1 rounded-md border text-xs font-medium whitespace-nowrap"
                style={{
                  borderColor: `${node.color}40`,
                  backgroundColor: `${node.color}15`,
                  color: node.color,
                }}
              >
                {node.label}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>

        {/* Phase label */}
        <div className="absolute bottom-2 right-3">
          <span className="text-xs text-white/20 font-mono">
            t={activePhase}
          </span>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// EVIDENCE BOARD
// =============================================================================

function EvidenceBoard({
  evidence,
  hypotheses,
  activePhase,
}: {
  evidence: EvidenceItem[];
  hypotheses: HypothesisData[];
  activePhase: number;
}) {
  const boardRef = useRef<HTMLDivElement>(null);
  const hypothesisRefs = useRef<Map<string, HTMLDivElement | null>>(new Map());
  const evidenceRefs = useRef<Map<string, HTMLDivElement | null>>(new Map());
  const [lineCoords, setLineCoords] = useState<
    Array<{ x1: number; y1: number; x2: number; y2: number; color: string; stance: string }>
  >([]);

  // Calculate SVG connection lines
  useEffect(() => {
    const timer = setTimeout(() => {
      if (!boardRef.current) return;
      const boardRect = boardRef.current.getBoundingClientRect();
      const coords: typeof lineCoords = [];

      evidence.forEach((ev) => {
        const evEl = evidenceRefs.current.get(ev.id);
        const hypEl = hypothesisRefs.current.get(ev.supports);
        if (evEl && hypEl) {
          const evRect = evEl.getBoundingClientRect();
          const hypRect = hypEl.getBoundingClientRect();
          const hyp = hypotheses.find((h) => h.id === ev.supports);
          coords.push({
            x1: hypRect.right - boardRect.left,
            y1: hypRect.top + hypRect.height / 2 - boardRect.top,
            x2: evRect.left - boardRect.left,
            y2: evRect.top + evRect.height / 2 - boardRect.top,
            color: hyp?.color ?? "#888",
            stance: ev.stance,
          });
        }
      });

      setLineCoords(coords);
    }, 400);
    return () => clearTimeout(timer);
  }, [evidence, hypotheses, activePhase]);

  const stanceIcon = (stance: EvidenceItem["stance"]) => {
    switch (stance) {
      case "supports":
        return <ThumbsUp className="h-3 w-3 text-emerald-400" />;
      case "contradicts":
        return <ThumbsDown className="h-3 w-3 text-red-400" />;
      default:
        return <Minus className="h-3 w-3 text-white/40" />;
    }
  };

  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
        <Target className="h-3.5 w-3.5 text-pink-400" />
        <span className="text-xs text-white/50">Evidence Board</span>
        <span className="ml-auto text-xs text-white/30">{evidence.length} items</span>
      </div>

      <div ref={boardRef} className="relative p-4">
        {/* SVG overlay for connection lines */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none z-10">
          {lineCoords.map((line, i) => (
            <motion.line
              key={i}
              x1={line.x1}
              y1={line.y1}
              x2={line.x2}
              y2={line.y2}
              stroke={line.stance === "contradicts" ? "#ef4444" : line.color}
              strokeWidth={1}
              strokeOpacity={0.3}
              strokeDasharray={line.stance === "contradicts" ? "3 3" : "none"}
              initial={{ pathLength: 0 }}
              animate={{ pathLength: 1 }}
              transition={{ duration: 0.5, delay: i * 0.05 }}
            />
          ))}
        </svg>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* Hypotheses column */}
          <div className="space-y-2">
            <span className="text-xs text-white/40 font-medium uppercase tracking-wider">Hypotheses</span>
            {hypotheses.map((hyp) => {
              const confidence = CONFIDENCE_BY_PHASE[hyp.id][activePhase];
              return (
                <div
                  key={hyp.id}
                  ref={(el) => { hypothesisRefs.current.set(hyp.id, el); }}
                  className="p-2 rounded-lg border"
                  style={{
                    borderColor: `${hyp.color}30`,
                    backgroundColor: `${hyp.color}08`,
                  }}
                >
                  <div className="flex items-center gap-1.5">
                    <Lightbulb className="h-3 w-3" style={{ color: hyp.color }} />
                    <span className={`text-xs font-medium ${hyp.textColor}`}>{hyp.shortLabel}</span>
                  </div>
                  <div className="mt-1 h-1 rounded-full bg-white/[0.06]">
                    <motion.div
                      className="h-full rounded-full"
                      style={{ backgroundColor: hyp.color }}
                      animate={{ width: `${confidence}%` }}
                      transition={{ type: "spring", stiffness: 120, damping: 20 }}
                    />
                  </div>
                  <span className="text-xs text-white/30 mt-0.5 block">{confidence}%</span>
                </div>
              );
            })}
          </div>

          {/* Evidence cards column (spans 2) */}
          <div className="sm:col-span-2 space-y-2">
            <span className="text-xs text-white/40 font-medium uppercase tracking-wider">Evidence</span>
            <AnimatePresence>
              {evidence.map((ev) => (
                <motion.div
                  key={ev.id}
                  ref={(el) => { evidenceRefs.current.set(ev.id, el); }}
                  initial={{ opacity: 0, y: 8, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  transition={springTransition}
                  className={`flex items-start gap-2 p-2 rounded-lg border ${
                    ev.stance === "contradicts"
                      ? "border-red-500/20 bg-red-500/5"
                      : ev.stance === "supports"
                        ? "border-emerald-500/20 bg-emerald-500/5"
                        : "border-white/[0.08] bg-white/[0.02]"
                  }`}
                >
                  <div className="mt-0.5">{stanceIcon(ev.stance)}</div>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-white/70 leading-relaxed">{ev.text}</p>
                    <span className="text-xs text-white/30 font-mono">{ev.section}</span>
                  </div>
                  <span className="text-xs text-white/20 whitespace-nowrap">
                    <Clock className="h-3 w-3 inline mr-0.5" />
                    P{ev.appearsAtPhase + 1}
                  </span>
                </motion.div>
              ))}
            </AnimatePresence>
            {evidence.length === 0 && (
              <div className="text-center py-6 text-white/30 text-xs">
                <AlertTriangle className="h-4 w-4 mx-auto mb-1 text-white/20" />
                No evidence collected yet. Advance through phases.
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
