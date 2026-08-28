'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from "@/components/motion";
import {
  AlignLeft,
  Terminal,
  Wand2,
  Eye,
  Copy,
  Settings,
  Play,
  Shield,
  CheckCircle2,
  Sparkles,
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
const InteractiveDiagramFixer = InteractiveDiagramFixerImpl;

export function AadcLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Fix malformed ASCII art diagrams that AI agents produce with misaligned boxes and broken lines.
      </GoalBanner>

      {/* Section 1: What Is AADC */}
      <Section title="What Is AADC?" icon={<AlignLeft className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>AADC (ASCII Art Diagram Corrector)</Highlight> automatically
          fixes alignment issues, broken box edges, and misconnected lines in ASCII
          diagrams. AI models frequently generate diagrams with subtle rendering
          errors that AADC corrects.
        </Paragraph>
        <Paragraph>
          When agents produce architecture diagrams, flowcharts, or tables in ASCII,
          the output often has columns that don&apos;t align, boxes with gaps, or
          connectors that miss their targets. AADC detects and repairs these issues.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Wand2 className="h-5 w-5" />}
              title="Auto-Repair"
              description="Fix alignment and spacing"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<AlignLeft className="h-5 w-5" />}
              title="Box Detection"
              description="Repair broken box edges"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="Preview"
              description="See before/after diff"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Copy className="h-5 w-5" />}
              title="Clipboard"
              description="Copy fixed output directly"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Fix a diagram from a file or stdin.
        </Paragraph>

        <CodeBlock
          code={`# Fix a diagram file
aadc fix diagram.txt

# Pipe from clipboard
pbpaste | aadc fix

# Fix and copy result
aadc fix diagram.txt | pbcopy

# Show what changed
aadc fix --diff diagram.txt`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Use <code>--diff</code> to see exactly what AADC changed before accepting the output.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'aadc fix <file>', description: 'Fix alignment issues in a diagram' },
            { command: 'aadc fix --diff <file>', description: 'Show changes as a diff' },
            { command: 'aadc check <file>', description: 'Check for issues without fixing' },
            { command: 'aadc --help', description: 'Show all available options' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 4: Example */}
      <Section title="Before and After" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          AADC fixes common AI-generated diagram issues.
        </Paragraph>

        <CodeBlock
          code={`# Before (broken):
+--------+    +-------+
| Client  |-->| Server|
+--------+    +-------+
                  |
              +-------+
              |  DB   |
              +------+

# After (fixed):
+----------+    +--------+
|  Client  |--->| Server |
+----------+    +--------+
                    |
                +--------+
                |   DB   |
                +--------+`}
          filename="Correction Example"
        />

        <TipBox variant="info">
          AADC handles box edges, connector lines, padding, and column alignment
          in a single pass.
        </TipBox>

        <div className="mt-8">
          <InteractiveDiagramFixer />
        </div>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">AADC + Agents</span>
            <p className="text-white/80 text-sm mt-1">Post-process agent diagram output</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">AADC + S2P</span>
            <p className="text-white/80 text-sm mt-1">Clean diagrams before including in prompts</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">AADC + CSCTF</span>
            <p className="text-white/80 text-sm mt-1">Fix diagrams in archived conversations</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">AADC + CM</span>
            <p className="text-white/80 text-sm mt-1">Clean architecture diagrams in memory files</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE DIAGRAM FIXER - ASCII Art Repair Studio
// =============================================================================

interface DiagramScenario {
  id: string;
  label: string;
  icon: string;
  broken: string[];
  fixed: string[];
  issues: string[];
  command: string;
  diagramType: string;
}

const DIAGRAM_SCENARIOS: DiagramScenario[] = [
  {
    id: "flowchart",
    label: "Flowchart",
    icon: "~",
    diagramType: "Flowchart",
    command: "aadc fix --type flowchart diagram.txt",
    broken: [
      "+--------+    +-------+",
      "| Client  |-->| Server|",
      "+--------+    +-------+",
      "                  |    ",
      "              +-------+",
      "              |  DB   |",
      "              +------+ ",
    ],
    fixed: [
      "+----------+    +--------+",
      "|  Client  |--->| Server |",
      "+----------+    +--------+",
      "                    |     ",
      "                +--------+",
      "                |   DB   |",
      "                +--------+",
    ],
    issues: ["Mismatched box widths", "Broken bottom edge on DB", "Arrow connector too short"],
  },
  {
    id: "table",
    label: "Table",
    icon: "#",
    diagramType: "Table",
    command: "aadc fix --type table models.txt",
    broken: [
      "+------+-------+------+",
      "| Name | Tokens| Cost |",
      "+------+-------+------+",
      "| Claude | 480K | $7.20|",
      "| GPT  | 320K  | $3.20|",
      "+------+-------+------+",
    ],
    fixed: [
      "+--------+--------+-------+",
      "| Name   | Tokens | Cost  |",
      "+--------+--------+-------+",
      "| Claude | 480K   | $7.20 |",
      "| GPT    | 320K   | $3.20 |",
      "+--------+--------+-------+",
    ],
    issues: ["Column widths inconsistent", "Cell padding uneven", "Row separators misaligned"],
  },
  {
    id: "sequence",
    label: "Sequence",
    icon: "|",
    diagramType: "Sequence Diagram",
    command: "aadc fix --type sequence auth.txt",
    broken: [
      " Client       Server      DB  ",
      "   |            |          |   ",
      "   |--login---->|          |   ",
      "   |            |--query-->|   ",
      "   |            |<--rows---|   ",
      "   |<--token----|          |   ",
      "   |            |          |   ",
    ],
    fixed: [
      " Client        Server       DB ",
      "   |             |           |  ",
      "   |---login---->|           |  ",
      "   |             |---query-->|  ",
      "   |             |<---rows---|  ",
      "   |<---token----|           |  ",
      "   |             |           |  ",
    ],
    issues: ["Lifeline spacing uneven", "Arrow lengths inconsistent", "Header alignment off"],
  },
  {
    id: "classdiag",
    label: "Class",
    icon: "=",
    diagramType: "Class Diagram",
    command: "aadc fix --type class models.txt",
    broken: [
      "+----------+     +--------+",
      "| BaseModel |     | Config|",
      "+----------+     +--------+",
      "| +name    |     | +path |",
      "| +type     |     | +env  |",
      "+----------+     +--------+",
      "      ^                    ",
      "      |                    ",
      "+----------+               ",
      "| UserModel|               ",
      "+----------+               ",
      "| +email  |               ",
      "+----------+               ",
    ],
    fixed: [
      "+-----------+    +--------+",
      "| BaseModel |    | Config |",
      "+-----------+    +--------+",
      "| +name     |    | +path  |",
      "| +type     |    | +env   |",
      "+-----------+    +--------+",
      "      ^                    ",
      "      |                    ",
      "+-----------+              ",
      "| UserModel |              ",
      "+-----------+              ",
      "| +email    |              ",
      "+-----------+              ",
    ],
    issues: ["Box widths mismatched", "Field padding inconsistent", "Inheritance line offset"],
  },
  {
    id: "tree",
    label: "Tree",
    icon: "/",
    diagramType: "File Tree",
    command: "aadc fix --type tree structure.txt",
    broken: [
      "project/          ",
      "|- src/           ",
      " |- index.ts     ",
      " |- utils/       ",
      "  |- helpers.ts  ",
      "  |- format.ts   ",
      "|- tests/         ",
      " |- index.test.ts",
      "|- package.json   ",
    ],
    fixed: [
      "project/              ",
      "+-- src/               ",
      "|   +-- index.ts       ",
      "|   +-- utils/         ",
      "|       +-- helpers.ts ",
      "|       +-- format.ts  ",
      "+-- tests/             ",
      "|   +-- index.test.ts  ",
      "+-- package.json       ",
    ],
    issues: ["Missing tree connectors", "Indentation inconsistent", "No branch lines", "Leaf nodes unaligned"],
  },
  {
    id: "pipeline",
    label: "Pipeline",
    icon: ">",
    diagramType: "Pipeline Diagram",
    command: "aadc fix --type pipeline ci.txt",
    broken: [
      "[Lint]-->[Test]-->[Build]-->[Deploy]",
      "  |        |        |         |     ",
      " 2m      5m       3m        8m     ",
      "  |        |        |         |     ",
      " pass    pass     pass      pass    ",
    ],
    fixed: [
      "[Lint]--->[Test]--->[Build]--->[Deploy]",
      "  |         |         |          |     ",
      " 2m        5m        3m         8m     ",
      "  |         |         |          |     ",
      " pass      pass      pass       pass   ",
    ],
    issues: ["Arrow lengths unequal", "Column alignment broken", "Status row misaligned"],
  },
];

/** Character-level diff between two strings for highlighting */
function computeCharDiffs(
  broken: string,
  fixed: string
): { char: string; status: "same" | "added" | "removed" }[] {
  const result: { char: string; status: "same" | "added" | "removed" }[] = [];
  const maxLen = Math.max(broken.length, fixed.length);
  for (let i = 0; i < maxLen; i++) {
    const bc = i < broken.length ? broken[i] : "";
    const fc = i < fixed.length ? fixed[i] : "";
    if (bc === fc) {
      result.push({ char: fc, status: "same" });
    } else if (fc) {
      result.push({ char: fc, status: "added" });
    }
  }
  return result;
}

const CHAR_DELAY_MS = 18;
const LINE_PAUSE_MS = 120;

function InteractiveDiagramFixerImpl() {
  const [scenarioIndex, setScenarioIndex] = useState(0);
  const [phase, setPhase] = useState<"idle" | "scanning" | "repairing" | "done">("idle");
  const [repairedLineCount, setRepairedLineCount] = useState(0);
  const [repairedCharCount, setRepairedCharCount] = useState(0);
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const [healthScore, setHealthScore] = useState(0);
  const [showDiff, setShowDiff] = useState(false);
  const timerIdsRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);

  const scenario = DIAGRAM_SCENARIOS[scenarioIndex];

  const clearTimers = useCallback(() => {
    timerIdsRef.current.forEach(clearTimeout);
    timerIdsRef.current = [];
  }, []);

  // Cleanup on unmount
  useEffect(() => clearTimers, [clearTimers]);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [terminalLines]);

  const addTerminalLine = useCallback((line: string) => {
    setTerminalLines((prev) => [...prev, line]);
  }, []);

  const pushTimer = useCallback((id: ReturnType<typeof setTimeout>) => {
    timerIdsRef.current.push(id);
  }, []);

  const handleReset = useCallback(() => {
    clearTimers();
    setPhase("idle");
    setRepairedLineCount(0);
    setRepairedCharCount(0);
    setTerminalLines([]);
    setHealthScore(0);
    setShowDiff(false);
  }, [clearTimers]);

  const handleSelectScenario = useCallback(
    (index: number) => {
      if (phase === "scanning" || phase === "repairing") return;
      handleReset();
      setScenarioIndex(index);
    },
    [phase, handleReset]
  );

  const handleRunFix = useCallback(() => {
    if (phase === "scanning" || phase === "repairing") return;
    if (phase === "done") {
      handleReset();
      return;
    }

    handleReset();

    // Phase 1: Scanning
    setPhase("scanning");
    const scanLines = [
      `$ ${scenario.command}`,
      `[aadc] Detecting diagram type...`,
      `[aadc] Type: ${scenario.diagramType}`,
      `[aadc] Scanning for structural issues...`,
    ];

    let delay = 0;
    for (const line of scanLines) {
      const captured = line;
      delay += 250;
      pushTimer(setTimeout(() => addTerminalLine(captured), delay));
    }

    // Report each issue
    for (let i = 0; i < scenario.issues.length; i++) {
      const issue = scenario.issues[i];
      delay += 300;
      pushTimer(
        setTimeout(() => {
          addTerminalLine(`[aadc]  ! Issue ${i + 1}: ${issue}`);
        }, delay)
      );
    }

    delay += 400;
    pushTimer(
      setTimeout(() => {
        addTerminalLine(
          `[aadc] Found ${scenario.issues.length} issues. Repairing...`
        );
        setPhase("repairing");
      }, delay)
    );

    // Phase 2: Repairing line by line, char by char
    const totalLines = scenario.broken.length;
    for (let lineIdx = 0; lineIdx < totalLines; lineIdx++) {
      const fixedLine = scenario.fixed[lineIdx];
      const charCount = fixedLine.length;

      for (let charIdx = 0; charIdx <= charCount; charIdx++) {
        delay += CHAR_DELAY_MS;
        const capturedLine = lineIdx;
        const capturedChar = charIdx;
        pushTimer(
          setTimeout(() => {
            setRepairedLineCount(capturedLine);
            setRepairedCharCount(capturedChar);
          }, delay)
        );
      }

      delay += LINE_PAUSE_MS;
      const capturedLineIdx = lineIdx;
      pushTimer(
        setTimeout(() => {
          setRepairedLineCount(capturedLineIdx + 1);
          setRepairedCharCount(0);
          // Update health score progressively
          const progress = Math.round(
            ((capturedLineIdx + 1) / totalLines) * 100
          );
          setHealthScore(progress);
          addTerminalLine(
            `[aadc]  + Line ${capturedLineIdx + 1}/${totalLines} repaired`
          );
        }, delay)
      );
    }

    // Phase 3: Done
    delay += 300;
    pushTimer(
      setTimeout(() => {
        addTerminalLine(`[aadc] All ${totalLines} lines repaired.`);
        addTerminalLine(`[aadc] Diagram health: 100%`);
        setPhase("done");
        setShowDiff(true);
        setHealthScore(100);
      }, delay)
    );
  }, [
    phase,
    handleReset,
    scenario,
    addTerminalLine,
    pushTimer,
  ]);

  // Build the "currently displayed" lines for the left (broken+repairing) panel
  const buildLiveLines = useCallback((): string[] => {
    if (phase === "idle" || phase === "scanning") {
      return scenario.broken;
    }
    if (phase === "done") {
      return scenario.fixed;
    }
    // Repairing: lines before repairedLineCount are fully fixed,
    // the line at repairedLineCount is partially fixed (char by char),
    // lines after are still broken
    return scenario.broken.map((brokenLine, i) => {
      if (i < repairedLineCount) return scenario.fixed[i];
      if (i === repairedLineCount) {
        const fixedLine = scenario.fixed[i];
        const partial =
          fixedLine.substring(0, repairedCharCount) +
          brokenLine.substring(repairedCharCount);
        return partial;
      }
      return brokenLine;
    });
  }, [phase, scenario, repairedLineCount, repairedCharCount]);

  const liveLines = buildLiveLines();

  // Compute overall repair progress (0..1)
  const totalChars = scenario.fixed.reduce((sum, l) => sum + l.length, 0);
  const repairedCharsTotal =
    scenario.fixed
      .slice(0, repairedLineCount)
      .reduce((sum, l) => sum + l.length, 0) + repairedCharCount;
  const repairProgress =
    phase === "done" ? 1 : phase === "idle" || phase === "scanning" ? 0 : Math.min(repairedCharsTotal / Math.max(totalChars, 1), 1);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 right-1/4 w-48 h-48 bg-violet-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 left-1/4 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-0 w-64 h-64 bg-blue-500/3 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 space-y-4">
        {/* Header row */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Wand2 className="h-4 w-4 text-violet-400/60" />
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              ASCII Art Repair Studio
            </span>
          </div>
          <AnimatePresence mode="wait">
            <motion.div
              key={phase}
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full border ${
                phase === "done"
                  ? "bg-emerald-500/10 border-emerald-500/30"
                  : phase === "repairing" || phase === "scanning"
                    ? "bg-amber-500/10 border-amber-500/30"
                    : "bg-red-500/10 border-red-500/30"
              }`}
            >
              {phase === "done" ? (
                <CheckCircle2 className="h-3 w-3 text-emerald-400" />
              ) : phase === "repairing" || phase === "scanning" ? (
                <Sparkles className="h-3 w-3 text-amber-400 animate-pulse" />
              ) : (
                <AlignLeft className="h-3 w-3 text-red-400" />
              )}
              <span
                className={`text-[10px] font-medium ${
                  phase === "done"
                    ? "text-emerald-400"
                    : phase === "repairing" || phase === "scanning"
                      ? "text-amber-400"
                      : "text-red-400"
                }`}
              >
                {phase === "done"
                  ? "Repaired"
                  : phase === "repairing"
                    ? "Repairing..."
                    : phase === "scanning"
                      ? "Scanning..."
                      : "Broken"}
              </span>
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Scenario selector stepper */}
        <div className="flex gap-1 rounded-lg border border-white/[0.08] bg-black/30 p-1 overflow-x-auto">
          {DIAGRAM_SCENARIOS.map((sc, i) => (
            <motion.button
              key={sc.id}
              onClick={() => handleSelectScenario(i)}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={`flex-shrink-0 px-3 py-1.5 rounded-md text-xs font-medium transition-colors ${
                scenarioIndex === i
                  ? "bg-white/[0.1] text-white border border-white/[0.1]"
                  : "text-white/40 hover:text-white/60 border border-transparent"
              }`}
            >
              <span className="mr-1 font-mono opacity-50">{sc.icon}</span>
              {sc.label}
            </motion.button>
          ))}
        </div>

        {/* Diagram health score gauge */}
        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
              Diagram Health
            </span>
            <span
              className={`text-xs font-mono font-bold ${
                healthScore >= 100
                  ? "text-emerald-400"
                  : healthScore > 0
                    ? "text-amber-400"
                    : "text-red-400"
              }`}
            >
              {healthScore}%
            </span>
          </div>
          <div className="h-2 rounded-full bg-black/40 border border-white/[0.06] overflow-hidden">
            <motion.div
              className={`h-full rounded-full ${
                healthScore >= 100
                  ? "bg-gradient-to-r from-emerald-500 to-emerald-400"
                  : healthScore > 0
                    ? "bg-gradient-to-r from-amber-500 to-amber-400"
                    : "bg-red-500/50"
              }`}
              initial={{ width: "0%" }}
              animate={{ width: `${healthScore}%` }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            />
          </div>
        </div>

        {/* Main content: split panes */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
          {/* Left pane: live repair view */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 px-1">
              <Eye className="h-3 w-3 text-white/30" />
              <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
                Live Repair View
              </span>
            </div>
            <div className="rounded-xl border border-white/[0.08] bg-black/50 p-3 font-mono text-[11px] leading-relaxed overflow-x-auto min-h-[180px]">
              <AnimatePresence mode="wait">
                <motion.div
                  key={`live-${scenarioIndex}`}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.15 }}
                >
                  {liveLines.map((line, i) => {
                    const isFullyRepaired = i < repairedLineCount && phase !== "idle" && phase !== "scanning";
                    const isCurrentLine =
                      i === repairedLineCount && phase === "repairing";
                    const isStillBroken = !isFullyRepaired && !isCurrentLine;

                    return (
                      <div
                        key={`live-line-${scenarioIndex}-${i}`}
                        className="relative whitespace-pre"
                      >
                        {/* Line number gutter */}
                        <span className="inline-block w-5 text-right mr-2 text-white/15 select-none text-[10px]">
                          {i + 1}
                        </span>
                        {isCurrentLine ? (
                          // Character-by-character repair highlighting
                          <>
                            <span className="text-emerald-400/90">
                              {line.substring(0, repairedCharCount)}
                            </span>
                            <span className="bg-emerald-400/20 text-emerald-300 border-b border-emerald-400/40">
                              {line[repairedCharCount] ?? ""}
                            </span>
                            <span className="text-white/40">
                              {line.substring(repairedCharCount + 1)}
                            </span>
                          </>
                        ) : (
                          <span
                            className={
                              isFullyRepaired
                                ? "text-emerald-400/80"
                                : isStillBroken && (phase === "repairing" || phase === "done")
                                  ? "text-white/30"
                                  : "text-white/50"
                            }
                          >
                            {line}
                          </span>
                        )}
                        {/* Flash highlight on just-completed lines */}
                        {isFullyRepaired && i === repairedLineCount - 1 && phase === "repairing" && (
                          <motion.span
                            initial={{ opacity: 0.4 }}
                            animate={{ opacity: 0 }}
                            transition={{ duration: 0.5 }}
                            className="absolute inset-0 bg-emerald-400/8 rounded pointer-events-none"
                          />
                        )}
                      </div>
                    );
                  })}
                </motion.div>
              </AnimatePresence>
            </div>
          </div>

          {/* Right pane: diff view */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 px-1">
              <Settings className="h-3 w-3 text-white/30" />
              <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
                {showDiff ? "Diff View" : "Original (Broken)"}
              </span>
            </div>
            <div className="rounded-xl border border-white/[0.08] bg-black/50 p-3 font-mono text-[11px] leading-relaxed overflow-x-auto min-h-[180px]">
              <AnimatePresence mode="wait">
                {showDiff ? (
                  <motion.div
                    key={`diff-${scenarioIndex}`}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.2 }}
                  >
                    {scenario.broken.map((brokenLine, i) => {
                      const fixedLine = scenario.fixed[i];
                      const hasChanges = brokenLine !== fixedLine;

                      if (!hasChanges) {
                        return (
                          <div
                            key={`diff-same-${i}`}
                            className="whitespace-pre text-white/30"
                          >
                            <span className="inline-block w-4 text-right mr-1 text-white/10 select-none text-[10px]">
                              {" "}
                            </span>
                            {fixedLine}
                          </div>
                        );
                      }

                      const charDiffs = computeCharDiffs(brokenLine, fixedLine);

                      return (
                        <div key={`diff-changed-${i}`}>
                          {/* Removed line */}
                          <div className="whitespace-pre bg-red-500/5 rounded-sm">
                            <span className="inline-block w-4 text-right mr-1 text-red-400/40 select-none text-[10px]">
                              -
                            </span>
                            <span className="text-red-400/60">{brokenLine}</span>
                          </div>
                          {/* Added line with char-level highlighting */}
                          <div className="whitespace-pre bg-emerald-500/5 rounded-sm">
                            <span className="inline-block w-4 text-right mr-1 text-emerald-400/40 select-none text-[10px]">
                              +
                            </span>
                            {charDiffs.map((cd, ci) => (
                              <span
                                key={`cd-${i}-${ci}`}
                                className={
                                  cd.status === "added"
                                    ? "text-emerald-300 bg-emerald-400/15"
                                    : "text-emerald-400/60"
                                }
                              >
                                {cd.char}
                              </span>
                            ))}
                          </div>
                        </div>
                      );
                    })}
                  </motion.div>
                ) : (
                  <motion.div
                    key={`broken-${scenarioIndex}`}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.15 }}
                  >
                    {scenario.broken.map((line, i) => (
                      <div
                        key={`broken-line-${i}`}
                        className="whitespace-pre text-white/40"
                      >
                        <span className="inline-block w-5 text-right mr-2 text-white/15 select-none text-[10px]">
                          {i + 1}
                        </span>
                        {line}
                      </div>
                    ))}
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Issues detected */}
        <div className="space-y-2">
          <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
            Issues Detected
          </span>
          <div className="flex flex-wrap gap-2">
            {scenario.issues.map((issue, i) => {
              const issueResolved =
                phase === "done" ||
                (phase === "repairing" &&
                  repairProgress > (i + 1) / scenario.issues.length);

              return (
                <motion.span
                  key={`${scenarioIndex}-issue-${i}`}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                    delay: i * 0.05,
                  }}
                  className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-xs font-medium transition duration-300 ${
                    issueResolved
                      ? "border-emerald-500/20 bg-emerald-500/5 text-emerald-400/70 line-through"
                      : "border-white/[0.08] bg-white/[0.02] text-white/50"
                  }`}
                >
                  {issueResolved ? (
                    <CheckCircle2 className="h-3 w-3 text-emerald-400/60" />
                  ) : (
                    <Eye className="h-3 w-3 text-white/30" />
                  )}
                  {issue}
                </motion.span>
              );
            })}
          </div>
        </div>

        {/* Mini terminal */}
        <div className="space-y-2">
          <div className="flex items-center gap-2 px-1">
            <Terminal className="h-3 w-3 text-white/30" />
            <span className="text-[10px] uppercase tracking-wider text-white/30 font-medium">
              Terminal Output
            </span>
          </div>
          <div
            ref={terminalRef}
            className="rounded-xl border border-white/[0.08] bg-black/60 p-3 font-mono text-[10px] leading-relaxed max-h-[140px] overflow-y-auto overflow-x-auto"
          >
            {terminalLines.length === 0 ? (
              <span className="text-white/20">
                $ waiting for command...
              </span>
            ) : (
              terminalLines.map((line, i) => {
                const isCommand = line.startsWith("$");
                const isError = line.includes("! Issue");
                const isSuccess =
                  line.includes("repaired") || line.includes("100%");

                return (
                  <motion.div
                    key={`term-${i}`}
                    initial={{ opacity: 0, x: -4 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: 0.15 }}
                    className={`whitespace-pre ${
                      isCommand
                        ? "text-cyan-400/80"
                        : isError
                          ? "text-amber-400/70"
                          : isSuccess
                            ? "text-emerald-400/70"
                            : "text-white/40"
                    }`}
                  >
                    {line}
                  </motion.div>
                );
              })
            )}
            {/* Blinking cursor */}
            {(phase === "scanning" || phase === "repairing") && (
              <span className="inline-block w-1.5 h-3 bg-white/40 animate-pulse ml-0.5" />
            )}
          </div>
        </div>

        {/* Repair progress bar (only during repair) */}
        {(phase === "repairing" || phase === "scanning") && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="space-y-1"
          >
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/30">
                Repair progress
              </span>
              <span className="text-[10px] font-mono text-white/40">
                {Math.round(repairProgress * 100)}%
              </span>
            </div>
            <div className="h-1 rounded-full bg-black/40 overflow-hidden">
              <motion.div
                className="h-full rounded-full bg-gradient-to-r from-violet-500 to-cyan-400"
                style={{ width: `${repairProgress * 100}%` }}
                transition={{ duration: 0.1 }}
              />
            </div>
          </motion.div>
        )}

        {/* Action button */}
        <motion.button
          onClick={handleRunFix}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          disabled={phase === "scanning" || phase === "repairing"}
          className={`w-full py-3 rounded-xl border font-medium text-sm flex items-center justify-center gap-2 transition-colors ${
            phase === "scanning" || phase === "repairing"
              ? "border-white/[0.06] bg-white/[0.02] text-white/30 cursor-not-allowed"
              : phase === "done"
                ? "border-amber-500/30 bg-amber-500/10 text-amber-400 hover:bg-amber-500/15"
                : "border-emerald-500/30 bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/15"
          }`}
        >
          {phase === "scanning" ? (
            <>
              <Sparkles className="h-4 w-4 animate-pulse" />
              Scanning diagram...
            </>
          ) : phase === "repairing" ? (
            <>
              <Sparkles className="h-4 w-4 animate-pulse" />
              Repairing characters...
            </>
          ) : phase === "done" ? (
            <>
              <RotateCcw className="h-4 w-4" />
              Reset &amp; Try Again
            </>
          ) : (
            <>
              <Play className="h-4 w-4" />
              Run aadc fix
            </>
          )}
        </motion.button>
      </div>
    </div>
  );
}
