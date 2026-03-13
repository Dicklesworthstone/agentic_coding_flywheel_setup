"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { motion, AnimatePresence, springs } from "@/components/motion";
import {
  Bug,
  Shield,
  Terminal,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Zap,
  Search,
  FileCode,
  GitCommit,
  Lightbulb,
  Play,
  RotateCcw,
  ChevronRight,
  Eye,
  Wrench,
  RefreshCw,
  FolderOpen,
  Lock,
  Code,
  BarChart3,
  ArrowRight,
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

export function UbsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Learn to catch bugs before they reach production with UBS.
      </GoalBanner>

      {/* What Is UBS */}
      <Section
        title="What Is UBS?"
        icon={<Bug className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>UBS (Ultimate Bug Scanner)</Highlight> is your safety net
          before every commit. It scans your code for common bugs, security
          issues, and anti-patterns that might slip through during development.
        </Paragraph>
        <Paragraph>
          Think of it as a code review bot that catches issues in seconds, not
          hours.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Security Scanning"
              description="XSS, injection, and OWASP vulnerabilities"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Bug className="h-5 w-5" />}
              title="Bug Detection"
              description="Null safety, async/await, type issues"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fast Feedback"
              description="Scan a file in under 1 second"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<FileCode className="h-5 w-5" />}
              title="Multi-Language"
              description="TypeScript, Python, Rust, Go, and more"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* The Golden Rule */}
      <Section
        title="The Golden Rule"
        icon={<GitCommit className="h-5 w-5" />}
        delay={0.15}
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          className="relative p-6 rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10"
        >
          <div className="flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-amber-500/20 text-amber-400">
              <Lightbulb className="h-6 w-6" />
            </div>
            <div>
              <p className="text-lg font-bold text-white">
                Run <code className="text-amber-400">ubs</code> before every
                commit.
              </p>
              <p className="text-white/60 mt-1">
                Exit 0 = safe to commit. Exit &gt;0 = fix issues first.
              </p>
            </div>
          </div>
        </motion.div>
      </Section>

      <Divider />

      {/* Essential Commands */}
      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <CommandList
          commands={[
            {
              command: "ubs file.ts",
              description: "Scan a specific file (fastest)",
            },
            {
              command: "ubs src/",
              description: "Scan a directory",
            },
            {
              command: "ubs $(git diff --name-only --cached)",
              description: "Scan staged files before commit",
            },
            {
              command: "ubs --only=js,python src/",
              description: "Filter by language (3-5x faster)",
            },
            {
              command: "ubs .",
              description: "Scan whole project (ignores node_modules)",
            },
          ]}
        />

        <div className="mt-6">
          <TipBox variant="tip">
            Always scope to changed files when possible.{" "}
            <code>ubs file.ts</code> runs in under 1 second, while{" "}
            <code>ubs .</code> may take 30+ seconds.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Understanding Output */}
      <Section
        title="Understanding Output"
        icon={<Search className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>UBS output follows a consistent format:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`\u26a0\ufe0f  Null Safety (3 errors)
    src/api/users.ts:42:5 \u2013 Possible null dereference
    \ud83d\udca1 Use optional chaining: user?.profile

    src/api/users.ts:87:12 \u2013 Unchecked array access
    \ud83d\udca1 Add bounds check before accessing array[i]

\u26a0\ufe0f  Security (1 error)
    src/api/auth.ts:23:8 \u2013 SQL injection risk
    \ud83d\udca1 Use parameterized queries instead of string concat

Exit code: 1`}
            language="text"
            filename="ubs output"
          />
        </div>

        <div className="mt-6 space-y-4">
          <OutputExplainer
            pattern="file:line:col"
            meaning="Exact location of the issue"
            color="text-emerald-400"
          />
          <OutputExplainer
            pattern="\ud83d\udca1"
            meaning="Suggested fix"
            color="text-amber-400"
          />
          <OutputExplainer
            pattern="Exit code 0/1"
            meaning="Pass (safe) / Fail (needs fixes)"
            color="text-primary"
          />
        </div>
      </Section>

      <Divider />

      {/* Bug Severity */}
      <Section
        title="Bug Severity Guide"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.3}
      >
        <div className="space-y-4">
          <SeverityCard
            level="Critical"
            icon={<XCircle className="h-5 w-5" />}
            color="from-red-500/20 to-rose-500/20"
            border="border-red-500/30"
            examples={[
              "Null safety violations",
              "XSS/Injection vulnerabilities",
              "Async/await issues",
              "Memory leaks",
            ]}
            action="Always fix immediately"
          />
          <SeverityCard
            level="Important"
            icon={<AlertTriangle className="h-5 w-5" />}
            color="from-amber-500/20 to-orange-500/20"
            border="border-amber-500/30"
            examples={[
              "Type narrowing issues",
              "Division by zero risks",
              "Resource leaks",
              "Missing error handling",
            ]}
            action="Fix before production"
          />
          <SeverityCard
            level="Contextual"
            icon={<CheckCircle className="h-5 w-5" />}
            color="from-primary/20 to-violet-500/20"
            border="border-primary/30"
            examples={[
              "TODO/FIXME comments",
              "Console.log statements",
              "Unused variables",
              "Magic numbers",
            ]}
            action="Use judgment"
          />
        </div>
      </Section>

      <Divider />

      {/* The Fix Workflow */}
      <Section
        title="The Fix Workflow"
        icon={<Zap className="h-5 w-5" />}
        delay={0.35}
      >
        <InteractiveBugScanner />
      </Section>

      <Divider />

      {/* Pre-Commit Hook */}
      <Section
        title="Pre-Commit Integration"
        icon={<GitCommit className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>
          For maximum safety, add UBS to your pre-commit workflow:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# In your workflow:
$ git add .
$ ubs $(git diff --name-only --cached)
# If exit 0: proceed with commit
# If exit 1: fix issues first

$ git commit -m "feat: add user auth"`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            ACFS agents are trained to run <code>ubs</code> automatically
            before committing. You get this protection by default!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.45}
      >
        <CodeBlock
          code={`# View session logs
$ ubs sessions --entries 1

# Scan your project
$ ubs .

# Get help
$ ubs --help`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// OUTPUT EXPLAINER
// =============================================================================
function OutputExplainer({
  pattern,
  meaning,
  color,
}: {
  pattern: string;
  meaning: string;
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-4 rounded-xl bg-white/[0.02] border border-white/[0.06] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.12] hover:bg-white/[0.04]"
    >
      <code className={`font-mono text-sm font-medium ${color}`}>{pattern}</code>
      <span className="text-white/50 group-hover:text-white/70 transition-colors">
        {"\u2192"}
      </span>
      <span className="text-white/60 group-hover:text-white/80 transition-colors">{meaning}</span>
    </motion.div>
  );
}

// =============================================================================
// SEVERITY CARD
// =============================================================================
function SeverityCard({
  level,
  icon,
  color,
  border,
  examples,
  action,
}: {
  level: string;
  icon: React.ReactNode;
  color: string;
  border: string;
  examples: string[];
  action: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group relative rounded-2xl border ${border} bg-gradient-to-br ${color} p-6 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.2]`}
    >
      {/* Decorative glow */}
      <div className="absolute -top-10 -right-10 w-32 h-32 bg-white/10 rounded-full blur-3xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <div className="relative flex items-start gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/10 text-white shadow-lg">
          {icon}
        </div>
        <div className="flex-1">
          <h4 className="font-bold text-white text-lg mb-3">{level}</h4>
          <ul className="space-y-2 mb-4">
            {examples.map((ex, i) => (
              <li key={i} className="text-sm text-white/70 flex items-center gap-2">
                <span className="w-1.5 h-1.5 rounded-full bg-white/50" />
                {ex}
              </li>
            ))}
          </ul>
          <p className="text-sm font-semibold text-white/90 flex items-center gap-2">
            <Zap className="h-4 w-4" />
            {action}
          </p>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE BUG SCANNER - WAR ROOM EDITION
// =============================================================================

// --- Scenario Types ---

type SeverityLevel = "critical" | "important" | "contextual";

interface ScanFinding {
  id: number;
  title: string;
  severity: SeverityLevel;
  file: string;
  line: number;
  col: number;
  description: string;
  codeSnippet: string;
  fix: string;
}

interface ScanFile {
  name: string;
  icon: "file" | "lock" | "code" | "folder";
  linesScanned: number;
}

interface ScanScenario {
  id: string;
  label: string;
  description: string;
  command: string;
  files: ScanFile[];
  findings: ScanFinding[];
  exitCode: number;
  ciMode: boolean;
}

// --- Scenario Data ---

const SCENARIOS: ScanScenario[] = [
  {
    id: "clean",
    label: "Clean Code",
    description: "A well-written file passes with zero findings",
    command: "ubs src/utils/helpers.ts",
    files: [
      { name: "src/utils/helpers.ts", icon: "code", linesScanned: 84 },
    ],
    findings: [],
    exitCode: 0,
    ciMode: false,
  },
  {
    id: "injection",
    label: "SQL Injection",
    description: "Detects string interpolation in database queries",
    command: "ubs src/api/users.ts",
    files: [
      { name: "src/api/users.ts", icon: "file", linesScanned: 127 },
    ],
    findings: [
      {
        id: 0,
        title: "SQL Injection",
        severity: "critical",
        file: "src/api/users.ts",
        line: 23,
        col: 8,
        description: "String interpolation in SQL query allows injection attacks",
        codeSnippet: "db.query(`SELECT * FROM users WHERE id = ${id}`)",
        fix: 'db.query("SELECT * FROM users WHERE id = ?", [id])',
      },
      {
        id: 1,
        title: "Null Dereference",
        severity: "critical",
        file: "src/api/users.ts",
        line: 42,
        col: 5,
        description: "Accessing .profile on possibly null user object",
        codeSnippet: "const name = user.profile.name;",
        fix: 'const name = user?.profile?.name ?? "Unknown";',
      },
    ],
    exitCode: 1,
    ciMode: false,
  },
  {
    id: "unquoted",
    label: "Unquoted Variable",
    description: "Catches unquoted shell variable that can cause word splitting",
    command: "ubs scripts/deploy.sh",
    files: [
      { name: "scripts/deploy.sh", icon: "code", linesScanned: 53 },
    ],
    findings: [
      {
        id: 0,
        title: "Unquoted Variable",
        severity: "important",
        file: "scripts/deploy.sh",
        line: 17,
        col: 12,
        description: "Unquoted $DIR can cause word splitting on paths with spaces",
        codeSnippet: "cp -r $DIR/build /opt/app/",
        fix: 'cp -r "$DIR/build" /opt/app/',
      },
    ],
    exitCode: 1,
    ciMode: false,
  },
  {
    id: "resource-leak",
    label: "Resource Leak",
    description: "Finds unclosed file handles and connections",
    command: "ubs src/db/connection.ts",
    files: [
      { name: "src/db/connection.ts", icon: "lock", linesScanned: 98 },
    ],
    findings: [
      {
        id: 0,
        title: "Resource Leak",
        severity: "critical",
        file: "src/db/connection.ts",
        line: 34,
        col: 3,
        description: "Database connection opened but never closed in error path",
        codeSnippet: "const conn = await pool.connect();\ntry { ... } catch { throw err; }",
        fix: "const conn = await pool.connect();\ntry { ... } finally { conn.release(); }",
      },
      {
        id: 1,
        title: "Missing Error Handling",
        severity: "important",
        file: "src/db/connection.ts",
        line: 56,
        col: 5,
        description: "Promise rejection not caught, may cause unhandled rejection",
        codeSnippet: "pool.query(sql);  // fire and forget",
        fix: "await pool.query(sql);  // or .catch(handleErr)",
      },
    ],
    exitCode: 1,
    ciMode: false,
  },
  {
    id: "ci-mode",
    label: "CI --fail-on-warning",
    description: "Strict mode that fails on contextual findings too",
    command: "ubs --fail-on-warning src/components/",
    files: [
      { name: "src/components/Header.tsx", icon: "file", linesScanned: 45 },
      { name: "src/components/Footer.tsx", icon: "file", linesScanned: 32 },
      { name: "src/components/Nav.tsx", icon: "file", linesScanned: 67 },
    ],
    findings: [
      {
        id: 0,
        title: "Console Statement",
        severity: "contextual",
        file: "src/components/Header.tsx",
        line: 12,
        col: 3,
        description: "console.log left in production code",
        codeSnippet: 'console.log("header rendered");',
        fix: "// Remove console.log or use a logger utility",
      },
      {
        id: 1,
        title: "Unused Import",
        severity: "contextual",
        file: "src/components/Nav.tsx",
        line: 2,
        col: 10,
        description: "Imported 'useEffect' is never used in this file",
        codeSnippet: "import { useState, useEffect } from 'react';",
        fix: "import { useState } from 'react';",
      },
    ],
    exitCode: 1,
    ciMode: true,
  },
  {
    id: "project-scan",
    label: "Whole Project",
    description: "Full project scan discovers issues across many files",
    command: "ubs .",
    files: [
      { name: "src/api/users.ts", icon: "file", linesScanned: 127 },
      { name: "src/api/auth.ts", icon: "lock", linesScanned: 89 },
      { name: "src/db/connection.ts", icon: "lock", linesScanned: 98 },
      { name: "src/utils/helpers.ts", icon: "code", linesScanned: 84 },
      { name: "src/components/App.tsx", icon: "file", linesScanned: 156 },
      { name: "scripts/deploy.sh", icon: "code", linesScanned: 53 },
    ],
    findings: [
      {
        id: 0,
        title: "SQL Injection",
        severity: "critical",
        file: "src/api/users.ts",
        line: 23,
        col: 8,
        description: "String interpolation in SQL query",
        codeSnippet: "db.query(`SELECT * FROM users WHERE id = ${id}`)",
        fix: 'db.query("SELECT * FROM users WHERE id = ?", [id])',
      },
      {
        id: 1,
        title: "Hardcoded Secret",
        severity: "critical",
        file: "src/api/auth.ts",
        line: 5,
        col: 14,
        description: "API key hardcoded in source file",
        codeSnippet: 'const API_KEY = "sk-live-abc123def456";',
        fix: "const API_KEY = process.env.API_KEY;",
      },
      {
        id: 2,
        title: "Resource Leak",
        severity: "critical",
        file: "src/db/connection.ts",
        line: 34,
        col: 3,
        description: "Connection opened but never closed on error",
        codeSnippet: "const conn = await pool.connect();",
        fix: "try { ... } finally { conn.release(); }",
      },
      {
        id: 3,
        title: "Unquoted Variable",
        severity: "important",
        file: "scripts/deploy.sh",
        line: 17,
        col: 12,
        description: "Unquoted $DIR may cause word splitting",
        codeSnippet: "cp -r $DIR/build /opt/app/",
        fix: 'cp -r "$DIR/build" /opt/app/',
      },
      {
        id: 4,
        title: "Magic Number",
        severity: "contextual",
        file: "src/components/App.tsx",
        line: 89,
        col: 22,
        description: "Magic number 86400 used without named constant",
        codeSnippet: "setTimeout(refresh, 86400 * 1000);",
        fix: "const DAY_IN_SEC = 86400;\nsetTimeout(refresh, DAY_IN_SEC * 1000);",
      },
    ],
    exitCode: 1,
    ciMode: false,
  },
];

const SEVERITY_CONFIG: Record<
  SeverityLevel,
  { border: string; bg: string; text: string; dot: string; label: string }
> = {
  critical: {
    border: "border-red-500/40",
    bg: "bg-red-500/10",
    text: "text-red-400",
    dot: "bg-red-500",
    label: "CRITICAL",
  },
  important: {
    border: "border-amber-500/40",
    bg: "bg-amber-500/10",
    text: "text-amber-400",
    dot: "bg-amber-500",
    label: "IMPORTANT",
  },
  contextual: {
    border: "border-blue-500/40",
    bg: "bg-blue-500/10",
    text: "text-blue-400",
    dot: "bg-blue-500",
    label: "CONTEXTUAL",
  },
};

type WarRoomPhase =
  | "idle"
  | "scanning"
  | "results"
  | "inspect"
  | "fixing"
  | "rescan"
  | "done";

const FIX_WORKFLOW_STEPS = [
  { icon: Eye, label: "Read Finding" },
  { icon: FileCode, label: "Navigate" },
  { icon: Wrench, label: "Apply Fix" },
  { icon: RefreshCw, label: "Re-scan" },
  { icon: CheckCircle, label: "Pass" },
];

// --- File icon helper ---

function FileIcon({ type }: { type: ScanFile["icon"] }) {
  switch (type) {
    case "lock":
      return <Lock className="h-3 w-3 text-amber-400/70" />;
    case "code":
      return <Code className="h-3 w-3 text-emerald-400/70" />;
    case "folder":
      return <FolderOpen className="h-3 w-3 text-blue-400/70" />;
    default:
      return <FileCode className="h-3 w-3 text-white/40" />;
  }
}

// --- Main Component ---

function InteractiveBugScanner() {
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [phase, setPhase] = useState<WarRoomPhase>("idle");
  const [fileProgress, setFileProgress] = useState<number[]>([]);
  const [currentFileIdx, setCurrentFileIdx] = useState(0);
  const [visibleFindings, setVisibleFindings] = useState<number[]>([]);
  const [selectedFinding, setSelectedFinding] = useState<number | null>(null);
  const [fixStep, setFixStep] = useState(0);
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const scanIntervalRef = useRef<number | null>(null);
  const fixTimersRef = useRef<number[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);

  const scenario = SCENARIOS[scenarioIdx];

  // Scroll terminal to bottom when lines change
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [terminalLines]);

  const addTerminalLine = useCallback((line: string) => {
    setTerminalLines((prev) => [...prev, line]);
  }, []);

  const clearAsyncWork = useCallback(() => {
    if (scanIntervalRef.current !== null) {
      clearInterval(scanIntervalRef.current);
      scanIntervalRef.current = null;
    }

    for (const timer of fixTimersRef.current) {
      clearTimeout(timer);
    }
    fixTimersRef.current.length = 0;
  }, []);

  const queueUiTimer = useCallback((callback: () => void, delay = 0) => {
    const timer = window.setTimeout(() => {
      fixTimersRef.current = fixTimersRef.current.filter(
        (pendingTimer) => pendingTimer !== timer,
      );
      callback();
    }, delay);

    fixTimersRef.current.push(timer);
    return timer;
  }, []);

  // Cleanup timers on unmount
  useEffect(() => clearAsyncWork, [clearAsyncWork]);

  const resetState = useCallback(() => {
    clearAsyncWork();
    setPhase("idle");
    setFileProgress([]);
    setCurrentFileIdx(0);
    setVisibleFindings([]);
    setSelectedFinding(null);
    setFixStep(0);
    setTerminalLines([]);
  }, [clearAsyncWork]);

  const selectScenario = useCallback(
    (idx: number) => {
      resetState();
      setScenarioIdx(idx);
    },
    [resetState]
  );

  const startScan = useCallback(() => {
    clearAsyncWork();

    const sc = SCENARIOS[scenarioIdx];
    setPhase("scanning");
    setFileProgress(sc.files.map(() => 0));
    setCurrentFileIdx(0);
    setVisibleFindings([]);
    setSelectedFinding(null);
    setFixStep(0);
    setTerminalLines([`$ ${sc.command}`, ""]);

    let fileIdx = 0;
    let progress = 0;

    scanIntervalRef.current = window.setInterval(() => {
      progress += 4;
      if (progress > 100) progress = 100;

      setFileProgress((prev) => {
        const next = [...prev];
        next[fileIdx] = progress;
        return next;
      });

      if (progress >= 100) {
        const fileName = sc.files[fileIdx].name;
        const fileFindings = sc.findings.filter((f) => f.file === fileName);
        const scanLine =
          fileFindings.length > 0
            ? `  [!] ${fileName} - ${fileFindings.length} issue${fileFindings.length > 1 ? "s" : ""} found`
            : `  [ok] ${fileName} - clean`;

        queueUiTimer(() => {
          addTerminalLine(scanLine);
        });

        fileIdx++;
        progress = 0;
        setCurrentFileIdx(fileIdx);

        if (fileIdx >= sc.files.length) {
          if (scanIntervalRef.current !== null) {
            clearInterval(scanIntervalRef.current);
            scanIntervalRef.current = null;
          }

          const exitLine =
            sc.findings.length > 0
              ? `\nExit code: ${sc.exitCode} (${sc.findings.length} finding${sc.findings.length !== 1 ? "s" : ""})`
              : "\nExit code: 0 - All clear!";

          queueUiTimer(() => {
            addTerminalLine(exitLine);
            setPhase(sc.findings.length > 0 ? "results" : "done");
            // Reveal findings one at a time
            sc.findings.forEach((_, i) => {
              queueUiTimer(() => {
                setVisibleFindings((prev) => [...prev, i]);
              }, (i + 1) * 300);
            });
          }, 200);
        }
      }
    }, 35);
  }, [scenarioIdx, addTerminalLine, clearAsyncWork, queueUiTimer]);

  const inspectFinding = useCallback(
    (findingIdx: number) => {
      setSelectedFinding(findingIdx);
      if (phase === "results") {
        setPhase("inspect");
      }
    },
    [phase]
  );

  const startFixWorkflow = useCallback(() => {
    // Clear any previous fix timers
    clearAsyncWork();

    setPhase("fixing");
    setFixStep(0);

    // Animate through fix steps
    const stepTimings = [800, 1200, 1000, 1200, 800];
    let cumulativeDelay = 0;
    stepTimings.forEach((delay, i) => {
      cumulativeDelay += delay;
      queueUiTimer(() => {
        setFixStep(i + 1);
        if (i === 0) {
          queueUiTimer(() => {
            addTerminalLine("\n$ # Reading finding details...");
          });
        }
        if (i === 1) {
          queueUiTimer(() => {
            addTerminalLine(
              `$ vim ${scenario.findings[0]?.file ?? "file.ts"}:${scenario.findings[0]?.line ?? 1}`
            );
          });
        }
        if (i === 2) {
          queueUiTimer(() => {
            addTerminalLine("$ # Applying fix...");
          });
        }
        if (i === 3) {
          queueUiTimer(() => {
            addTerminalLine(`$ ${scenario.command}`);
            addTerminalLine("  [ok] All files clean");
          });
        }
        if (i === 4) {
          queueUiTimer(() => {
            addTerminalLine("\nExit code: 0 - All clear!");
            setPhase("done");
          });
        }
      }, cumulativeDelay);
    });
  }, [scenario, addTerminalLine, clearAsyncWork, queueUiTimer]);

  // --- Severity heatmap data ---
  const heatmapData = scenario.files.map((file) => {
    const fileFindings = scenario.findings.filter((f) => f.file === file.name);
    const critCount = fileFindings.filter(
      (f) => f.severity === "critical"
    ).length;
    const impCount = fileFindings.filter(
      (f) => f.severity === "important"
    ).length;
    const ctxCount = fileFindings.filter(
      (f) => f.severity === "contextual"
    ).length;
    return { file: file.name, critical: critCount, important: impCount, contextual: ctxCount, total: fileFindings.length };
  });

  const hasFindings = scenario.findings.length > 0;
  const showHeatmap =
    (phase === "results" || phase === "inspect") && hasFindings;

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Scenario Selector */}
      <div className="flex items-center gap-1.5 px-3 py-2.5 border-b border-white/[0.08] bg-white/[0.02] overflow-x-auto scrollbar-none">
        {SCENARIOS.map((sc, i) => (
          <motion.button
            key={sc.id}
            onClick={() => selectScenario(i)}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={springs.snappy}
            className={`shrink-0 flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
              i === scenarioIdx
                ? "bg-primary/20 text-primary border border-primary/30"
                : "bg-white/[0.03] text-white/40 border border-white/[0.06] hover:text-white/60 hover:bg-white/[0.06]"
            }`}
          >
            {sc.exitCode === 0 ? (
              <CheckCircle className="h-3 w-3" />
            ) : (
              <AlertTriangle className="h-3 w-3" />
            )}
            <span className="hidden sm:inline">{sc.label}</span>
            <span className="sm:hidden">{sc.label.split(" ")[0]}</span>
          </motion.button>
        ))}
      </div>

      {/* Scenario Description Bar */}
      <div className="flex items-center gap-3 px-4 py-2 border-b border-white/[0.06] bg-white/[0.01]">
        <div className="flex items-center gap-2 flex-1 min-w-0">
          <Terminal className="h-3.5 w-3.5 text-white/30 shrink-0" />
          <code className="text-xs text-primary/80 font-mono truncate">
            {scenario.command}
          </code>
        </div>
        <span className="text-xs text-white/30 shrink-0">
          {scenario.description}
        </span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr,1px,1fr] min-h-[420px]">
        {/* Left Panel: File Scanner + Code */}
        <div className="relative p-4 overflow-hidden">
          {/* File scanning visualization */}
          <div className="flex items-center gap-2 mb-3 text-white/40 text-xs">
            <FolderOpen className="h-3.5 w-3.5" />
            <span>
              {phase === "scanning"
                ? "Scanning Files..."
                : phase === "idle"
                  ? "Files to Scan"
                  : `${scenario.files.length} File${scenario.files.length !== 1 ? "s" : ""} Scanned`}
            </span>
          </div>

          {/* File List with Progress Bars */}
          <div className="space-y-1.5 mb-4">
            {scenario.files.map((file, i) => {
              const prog = fileProgress[i] ?? 0;
              const isDone = prog >= 100;
              const isActive = phase === "scanning" && i === currentFileIdx;
              const fileFindings = scenario.findings.filter(
                (f) => f.file === file.name
              );
              const hasIssues = isDone && fileFindings.length > 0;

              return (
                <motion.div
                  key={file.name}
                  initial={{ opacity: 0, x: -12 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ ...springs.smooth, delay: i * 0.06 }}
                  className={`relative group rounded-lg border p-2.5 transition-all ${
                    isActive
                      ? "border-primary/40 bg-primary/5"
                      : hasIssues
                        ? "border-red-500/20 bg-red-500/5"
                        : isDone
                          ? "border-emerald-500/20 bg-emerald-500/5"
                          : "border-white/[0.06] bg-white/[0.02]"
                  }`}
                >
                  <div className="flex items-center gap-2 mb-1">
                    <FileIcon type={file.icon} />
                    <span className="text-xs font-mono text-white/60 truncate flex-1">
                      {file.name}
                    </span>
                    <span className="text-[10px] text-white/30">
                      {file.linesScanned} lines
                    </span>
                    {isDone && !hasIssues && (
                      <motion.span
                        initial={{ scale: 0 }}
                        animate={{ scale: 1 }}
                        transition={springs.snappy}
                      >
                        <CheckCircle className="h-3 w-3 text-emerald-400" />
                      </motion.span>
                    )}
                    {hasIssues && (
                      <motion.span
                        initial={{ scale: 0 }}
                        animate={{ scale: 1 }}
                        transition={springs.snappy}
                        className="flex items-center gap-1"
                      >
                        <XCircle className="h-3 w-3 text-red-400" />
                        <span className="text-[10px] text-red-400">
                          {fileFindings.length}
                        </span>
                      </motion.span>
                    )}
                  </div>

                  {/* Progress bar */}
                  {(phase === "scanning" || isDone) && (
                    <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
                      <motion.div
                        className={`h-full rounded-full ${
                          hasIssues
                            ? "bg-gradient-to-r from-red-500 to-rose-500"
                            : isDone
                              ? "bg-gradient-to-r from-emerald-500 to-teal-500"
                              : "bg-gradient-to-r from-primary to-violet-500"
                        }`}
                        initial={{ width: "0%" }}
                        animate={{ width: `${prog}%` }}
                        transition={springs.quick}
                      />
                    </div>
                  )}

                  {/* Scan line shimmer */}
                  {isActive && (
                    <motion.div
                      className="absolute inset-0 rounded-lg bg-gradient-to-r from-transparent via-primary/10 to-transparent"
                      animate={{ x: ["-100%", "100%"] }}
                      transition={{
                        duration: 1.2,
                        repeat: Infinity,
                        ease: "linear",
                      }}
                    />
                  )}
                </motion.div>
              );
            })}
          </div>

          {/* Severity Heatmap */}
          <AnimatePresence>
            {showHeatmap && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={springs.smooth}
                className="overflow-hidden"
              >
                <div className="flex items-center gap-2 mb-2 text-white/40 text-xs">
                  <BarChart3 className="h-3.5 w-3.5" />
                  <span>Severity Heatmap</span>
                </div>
                <div className="space-y-1">
                  {heatmapData
                    .filter((d) => d.total > 0)
                    .map((row) => {
                      const maxFindings = Math.max(
                        ...heatmapData.map((d) => d.total),
                        1
                      );
                      const pct = Math.round((row.total / maxFindings) * 100);

                      return (
                        <motion.div
                          key={row.file}
                          initial={{ opacity: 0, x: -8 }}
                          animate={{ opacity: 1, x: 0 }}
                          className="flex items-center gap-2"
                        >
                          <span className="text-[10px] font-mono text-white/40 w-28 truncate text-right shrink-0">
                            {row.file.split("/").pop()}
                          </span>
                          <div className="flex-1 h-3 rounded-full bg-white/[0.04] overflow-hidden flex">
                            {row.critical > 0 && (
                              <motion.div
                                className="h-full bg-red-500"
                                initial={{ width: 0 }}
                                animate={{
                                  width: `${(row.critical / row.total) * pct}%`,
                                }}
                                transition={springs.smooth}
                              />
                            )}
                            {row.important > 0 && (
                              <motion.div
                                className="h-full bg-amber-500"
                                initial={{ width: 0 }}
                                animate={{
                                  width: `${(row.important / row.total) * pct}%`,
                                }}
                                transition={springs.smooth}
                              />
                            )}
                            {row.contextual > 0 && (
                              <motion.div
                                className="h-full bg-blue-500"
                                initial={{ width: 0 }}
                                animate={{
                                  width: `${(row.contextual / row.total) * pct}%`,
                                }}
                                transition={springs.smooth}
                              />
                            )}
                          </div>
                          <span className="text-[10px] text-white/30 w-4 text-right">
                            {row.total}
                          </span>
                        </motion.div>
                      );
                    })}
                  <div className="flex items-center gap-3 mt-1.5">
                    <div className="flex items-center gap-1">
                      <span className="w-2 h-2 rounded-full bg-red-500" />
                      <span className="text-[9px] text-white/30">Critical</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <span className="w-2 h-2 rounded-full bg-amber-500" />
                      <span className="text-[9px] text-white/30">
                        Important
                      </span>
                    </div>
                    <div className="flex items-center gap-1">
                      <span className="w-2 h-2 rounded-full bg-blue-500" />
                      <span className="text-[9px] text-white/30">
                        Contextual
                      </span>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Mini Terminal */}
          <div className="mt-3">
            <div className="flex items-center gap-2 mb-1.5 text-white/40 text-xs">
              <Terminal className="h-3.5 w-3.5" />
              <span>Terminal</span>
            </div>
            <div
              ref={terminalRef}
              className="h-28 rounded-lg bg-black/40 border border-white/[0.06] p-2 overflow-y-auto font-mono text-[11px] leading-relaxed scrollbar-thin scrollbar-thumb-white/10"
            >
              {terminalLines.length === 0 ? (
                <span className="text-white/20">
                  $ {scenario.command}
                  <motion.span
                    animate={{ opacity: [1, 0, 1] }}
                    transition={{
                      duration: 1,
                      repeat: Infinity,
                      ease: "linear",
                    }}
                    className="inline-block w-1.5 h-3 bg-white/40 ml-0.5 align-middle"
                  />
                </span>
              ) : (
                terminalLines.map((line, i) => (
                  <motion.div
                    key={i}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.15 }}
                    className={
                      line.includes("[!]")
                        ? "text-red-400/80"
                        : line.includes("[ok]")
                          ? "text-emerald-400/80"
                          : line.includes("Exit code: 0")
                            ? "text-emerald-400"
                            : line.includes("Exit code:")
                              ? "text-red-400"
                              : "text-white/50"
                    }
                  >
                    {line || "\u00A0"}
                  </motion.div>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Divider */}
        <div className="hidden lg:block bg-white/[0.08]" />

        {/* Right Panel: Results + Actions */}
        <div className="p-4 border-t lg:border-t-0 border-white/[0.08]">
          <AnimatePresence mode="wait">
            {/* IDLE STATE */}
            {phase === "idle" && (
              <motion.div
                key="idle"
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.95 }}
                transition={springs.smooth}
                className="flex flex-col items-center justify-center h-full min-h-[380px] gap-5"
              >
                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 border border-primary/20">
                  <Bug className="h-8 w-8 text-primary" />
                </div>
                <div className="text-center">
                  <p className="text-white/70 text-sm font-medium">
                    {scenario.label} Scenario
                  </p>
                  <p className="text-white/40 text-xs mt-1 max-w-[240px]">
                    {scenario.description}
                  </p>
                </div>
                {scenario.ciMode && (
                  <motion.div
                    initial={{ opacity: 0, y: 4 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-amber-500/10 border border-amber-500/20"
                  >
                    <Shield className="h-3 w-3 text-amber-400" />
                    <span className="text-[10px] text-amber-400 font-medium">
                      CI strict mode: --fail-on-warning
                    </span>
                  </motion.div>
                )}
                <motion.button
                  onClick={startScan}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.96 }}
                  transition={springs.snappy}
                  className="flex items-center gap-2 px-6 py-3 rounded-xl bg-primary/20 text-primary border border-primary/30 text-sm font-medium hover:bg-primary/30 transition-colors"
                >
                  <Play className="h-4 w-4" />
                  Run UBS Scan
                </motion.button>
              </motion.div>
            )}

            {/* SCANNING STATE */}
            {phase === "scanning" && (
              <motion.div
                key="scanning"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={springs.smooth}
                className="flex flex-col items-center justify-center h-full min-h-[380px] gap-4"
              >
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{
                    duration: 2,
                    repeat: Infinity,
                    ease: "linear",
                  }}
                >
                  <Search className="h-10 w-10 text-primary" />
                </motion.div>
                <p className="text-white/60 text-sm font-medium">
                  Scanning {scenario.files.length} file
                  {scenario.files.length !== 1 ? "s" : ""}...
                </p>
                <div className="w-56 h-2 rounded-full bg-white/[0.06] overflow-hidden">
                  <motion.div
                    className="h-full rounded-full bg-gradient-to-r from-primary to-violet-500"
                    animate={{
                      width: `${
                        scenario.files.length > 0
                          ? Math.round(
                              ((fileProgress.filter((p) => p >= 100).length +
                                (fileProgress[currentFileIdx] ?? 0) / 100) /
                                scenario.files.length) *
                                100
                            )
                          : 0
                      }%`,
                    }}
                    transition={springs.quick}
                  />
                </div>
                <p className="text-xs text-white/30 font-mono">
                  {currentFileIdx < scenario.files.length
                    ? scenario.files[currentFileIdx].name
                    : "Finalizing..."}
                </p>
              </motion.div>
            )}

            {/* RESULTS STATE */}
            {(phase === "results" || phase === "inspect") && (
              <motion.div
                key="results"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={springs.smooth}
                className="space-y-2 h-full"
              >
                {/* Exit code banner */}
                <motion.div
                  initial={{ opacity: 0, y: -8 }}
                  animate={{ opacity: 1, y: 0 }}
                  className={`flex items-center gap-2 p-2.5 rounded-lg border ${
                    scenario.exitCode === 0
                      ? "border-emerald-500/30 bg-emerald-500/10"
                      : "border-red-500/30 bg-red-500/10"
                  }`}
                >
                  {scenario.exitCode === 0 ? (
                    <CheckCircle className="h-4 w-4 text-emerald-400" />
                  ) : (
                    <XCircle className="h-4 w-4 text-red-400" />
                  )}
                  <span
                    className={`text-sm font-medium ${
                      scenario.exitCode === 0
                        ? "text-emerald-400"
                        : "text-red-400"
                    }`}
                  >
                    Exit {scenario.exitCode}
                  </span>
                  <span className="text-xs text-white/30 ml-auto font-mono">
                    {scenario.findings.length} finding
                    {scenario.findings.length !== 1 ? "s" : ""}
                  </span>
                </motion.div>

                {/* Finding cards */}
                <div className="space-y-1.5 max-h-[200px] overflow-y-auto scrollbar-thin scrollbar-thumb-white/10 pr-1">
                  {scenario.findings.map((finding, i) => {
                    const styles = SEVERITY_CONFIG[finding.severity];
                    const isVisible = visibleFindings.includes(i);
                    const isSelected = selectedFinding === finding.id;

                    return (
                      <AnimatePresence key={finding.id}>
                        {isVisible && (
                          <motion.button
                            initial={{ opacity: 0, y: 12, scale: 0.95 }}
                            animate={{ opacity: 1, y: 0, scale: 1 }}
                            transition={springs.smooth}
                            onClick={() => inspectFinding(finding.id)}
                            className={`w-full text-left rounded-xl border transition-all ${
                              isSelected
                                ? `${styles.border} ${styles.bg} ring-1 ${styles.border}`
                                : "border-white/[0.08] bg-white/[0.02] hover:border-white/[0.12] hover:bg-white/[0.04]"
                            }`}
                          >
                            <div className="p-2.5">
                              <div className="flex items-center gap-2">
                                <span
                                  className={`w-2 h-2 rounded-full ${styles.dot} shrink-0`}
                                />
                                <span
                                  className={`text-xs font-bold ${styles.text}`}
                                >
                                  {finding.title}
                                </span>
                                <span
                                  className={`text-[9px] px-1.5 py-0.5 rounded-full ${styles.bg} ${styles.text} font-bold uppercase tracking-wider`}
                                >
                                  {styles.label}
                                </span>
                                <span className="text-[10px] text-white/30 ml-auto font-mono shrink-0">
                                  {finding.file.split("/").pop()}:{finding.line}:
                                  {finding.col}
                                </span>
                              </div>
                              <p className="text-[11px] text-white/50 mt-1 ml-4">
                                {finding.description}
                              </p>
                            </div>

                            {/* Expanded code snippet */}
                            <AnimatePresence>
                              {isSelected && (
                                <motion.div
                                  initial={{
                                    opacity: 0,
                                    height: 0,
                                  }}
                                  animate={{
                                    opacity: 1,
                                    height: "auto",
                                  }}
                                  exit={{
                                    opacity: 0,
                                    height: 0,
                                  }}
                                  transition={springs.smooth}
                                  className="overflow-hidden border-t border-white/[0.06]"
                                >
                                  <div className="p-2.5 space-y-2">
                                    <div>
                                      <span className="text-[9px] text-red-400/60 uppercase tracking-wider font-bold">
                                        Bug
                                      </span>
                                      <pre className="mt-0.5 text-[10px] text-red-300/80 font-mono bg-red-500/5 rounded p-1.5 overflow-x-auto">
                                        {finding.codeSnippet}
                                      </pre>
                                    </div>
                                    <div>
                                      <span className="text-[9px] text-emerald-400/60 uppercase tracking-wider font-bold">
                                        Fix
                                      </span>
                                      <pre className="mt-0.5 text-[10px] text-emerald-300/80 font-mono bg-emerald-500/5 rounded p-1.5 overflow-x-auto">
                                        {finding.fix}
                                      </pre>
                                    </div>
                                  </div>
                                </motion.div>
                              )}
                            </AnimatePresence>
                          </motion.button>
                        )}
                      </AnimatePresence>
                    );
                  })}
                </div>

                {/* Fix all button */}
                {visibleFindings.length === scenario.findings.length &&
                  scenario.findings.length > 0 && (
                    <motion.button
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ ...springs.smooth, delay: 0.3 }}
                      onClick={startFixWorkflow}
                      whileHover={{ scale: 1.03 }}
                      whileTap={{ scale: 0.97 }}
                      className="w-full mt-2 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 text-sm font-medium hover:bg-emerald-500/30 transition-colors"
                    >
                      <Wrench className="h-4 w-4" />
                      Fix All Issues
                      <ArrowRight className="h-3.5 w-3.5 ml-1" />
                    </motion.button>
                  )}
              </motion.div>
            )}

            {/* FIXING STATE */}
            {phase === "fixing" && (
              <motion.div
                key="fixing"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={springs.smooth}
                className="space-y-4 h-full"
              >
                <div className="flex items-center gap-2 mb-2">
                  <Wrench className="h-4 w-4 text-primary" />
                  <span className="text-sm font-medium text-white/70">
                    Fix Workflow
                  </span>
                </div>

                {/* Fix workflow stepper */}
                <div className="space-y-1.5">
                  {FIX_WORKFLOW_STEPS.map((ws, i) => {
                    const StepIcon = ws.icon;
                    const isComplete = fixStep > i;
                    const isCurrent = fixStep === i;

                    return (
                      <motion.div
                        key={ws.label}
                        initial={{ opacity: 0, x: -12 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{
                          ...springs.smooth,
                          delay: i * 0.08,
                        }}
                        className={`flex items-center gap-3 p-2.5 rounded-lg border transition-all ${
                          isCurrent
                            ? "border-primary/40 bg-primary/10"
                            : isComplete
                              ? "border-emerald-500/20 bg-emerald-500/5"
                              : "border-white/[0.06] bg-white/[0.02]"
                        }`}
                      >
                        <div
                          className={`flex h-7 w-7 items-center justify-center rounded-lg shrink-0 ${
                            isComplete
                              ? "bg-emerald-500/20"
                              : isCurrent
                                ? "bg-primary/20"
                                : "bg-white/[0.04]"
                          }`}
                        >
                          {isComplete ? (
                            <CheckCircle className="h-3.5 w-3.5 text-emerald-400" />
                          ) : (
                            <StepIcon
                              className={`h-3.5 w-3.5 ${
                                isCurrent
                                  ? "text-primary"
                                  : "text-white/30"
                              }`}
                            />
                          )}
                        </div>
                        <span
                          className={`text-xs font-medium ${
                            isComplete
                              ? "text-emerald-400/80"
                              : isCurrent
                                ? "text-white/80"
                                : "text-white/30"
                          }`}
                        >
                          {ws.label}
                        </span>
                        {isCurrent && (
                          <motion.div
                            className="ml-auto flex items-center gap-1"
                            animate={{ opacity: [0.4, 1, 0.4] }}
                            transition={{
                              duration: 1.5,
                              repeat: Infinity,
                            }}
                          >
                            <ChevronRight className="h-3 w-3 text-primary" />
                          </motion.div>
                        )}
                        {isComplete && (
                          <span className="ml-auto text-[10px] text-emerald-400/60">
                            Done
                          </span>
                        )}
                      </motion.div>
                    );
                  })}
                </div>

                {/* Fixed findings summary */}
                {fixStep >= 3 && (
                  <motion.div
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={springs.smooth}
                    className="space-y-1"
                  >
                    {scenario.findings.map((f) => (
                      <div
                        key={f.id}
                        className="flex items-center gap-2 p-2 rounded-lg border border-emerald-500/15 bg-emerald-500/5"
                      >
                        <CheckCircle className="h-3 w-3 text-emerald-400 shrink-0" />
                        <span className="text-[11px] text-emerald-400/70 line-through">
                          {f.title}
                        </span>
                        <span className="text-[10px] text-emerald-400/40 ml-auto">
                          Fixed
                        </span>
                      </div>
                    ))}
                  </motion.div>
                )}
              </motion.div>
            )}

            {/* DONE STATE */}
            {phase === "done" && (
              <motion.div
                key="done"
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0 }}
                transition={springs.smooth}
                className="flex flex-col items-center justify-center h-full min-h-[380px] gap-4"
              >
                {/* Success animation */}
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                    delay: 0.1,
                  }}
                  className="relative"
                >
                  <motion.div
                    className="absolute inset-0 rounded-full bg-emerald-500/20"
                    animate={{ scale: [1, 1.5, 1], opacity: [0.5, 0, 0.5] }}
                    transition={{
                      duration: 2,
                      repeat: Infinity,
                      ease: "easeInOut",
                    }}
                  />
                  <div className="relative flex h-20 w-20 items-center justify-center rounded-full bg-emerald-500/20 border border-emerald-500/30">
                    <CheckCircle className="h-10 w-10 text-emerald-400" />
                  </div>
                </motion.div>

                {/* Exit code badge */}
                <motion.div
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ ...springs.smooth, delay: 0.2 }}
                  className="text-center"
                >
                  <p className="text-2xl font-bold text-emerald-400">Exit 0</p>
                  <p className="text-sm text-white/50 mt-1">
                    {hasFindings
                      ? "All issues fixed -- safe to commit!"
                      : "No issues found -- clean code!"}
                  </p>
                </motion.div>

                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ ...springs.smooth, delay: 0.3 }}
                  className="flex items-center gap-2 px-4 py-2 rounded-full bg-emerald-500/10 border border-emerald-500/20"
                >
                  <Shield className="h-3.5 w-3.5 text-emerald-400" />
                  <span className="text-xs text-emerald-400 font-mono">
                    0 findings | safe to commit
                  </span>
                </motion.div>

                {/* Action buttons */}
                <div className="flex items-center gap-3 mt-2">
                  <motion.button
                    onClick={resetState}
                    whileHover={{ scale: 1.04 }}
                    whileTap={{ scale: 0.96 }}
                    transition={springs.snappy}
                    className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white/[0.04] text-white/50 border border-white/[0.08] text-xs hover:bg-white/[0.08] hover:text-white/70 transition-colors"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    Reset
                  </motion.button>
                  {scenarioIdx < SCENARIOS.length - 1 && (
                    <motion.button
                      onClick={() => selectScenario(scenarioIdx + 1)}
                      whileHover={{ scale: 1.04 }}
                      whileTap={{ scale: 0.96 }}
                      transition={springs.snappy}
                      className="flex items-center gap-2 px-4 py-2 rounded-xl bg-primary/20 text-primary border border-primary/30 text-xs hover:bg-primary/30 transition-colors"
                    >
                      Next Scenario
                      <ChevronRight className="h-3.5 w-3.5" />
                    </motion.button>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
