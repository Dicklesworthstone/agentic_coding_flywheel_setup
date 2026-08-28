"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  ShieldAlert,
  ShieldCheck,
  Shield,
  CheckCircle,
  XCircle,
  Terminal,
  AlertTriangle,
  Layers,
  KeyRound,
  Zap,
  RotateCcw,
  Eye,
  Lock,
  Unlock,
  Activity,
  ChevronRight,
  Gauge,
  History,
  ToggleLeft,
  ToggleRight,
  Stethoscope,
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
  BulletList,
} from "./lesson-components";

export function DcgLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Use DCG to block destructive commands before they do damage.
      </GoalBanner>

      <Section
        title="What Is DCG?"
        icon={<ShieldAlert className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>DCG (Destructive Command Guard)</Highlight> is a Claude
          Code hook that blocks dangerous commands before they execute. It
          protects your repos from hard resets, recursive deletes, destructive
          database commands, and more.
        </Paragraph>
        <Paragraph>
          Think of it as a safety interlock: if a command looks destructive,
          DCG stops it and suggests a safer alternative.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ShieldCheck className="h-5 w-5" />}
              title="Pre-Execution Blocking"
              description="Stops damage before it happens"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Layers className="h-5 w-5" />}
              title="Protection Packs"
              description="Git, filesystem, database, cloud, and more"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<KeyRound className="h-5 w-5" />}
              title="Allow-Once Codes"
              description="Explicit bypass when you know it is safe"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fail-Open Design"
              description="Errors never block your workflow"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      <Section
        title="How DCG Intercepts Commands"
        icon={<ShieldCheck className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          DCG runs as a <Highlight>PreToolUse hook</Highlight> inside Claude
          Code. Every command is checked against a set of rules before it runs.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Example: test a command before running it
$ dcg test "git reset --hard" --explain
> BLOCKED: git.reset.hard
> Why: hard reset discards uncommitted work
> Safer: git restore --staged .`}
            language="bash"
          />
        </div>

        <div className="mt-8">
          <InteractiveDcgDemo />
        </div>

        <TipBox variant="warning">
          If DCG blocks a command, slow down and read the explanation. It is
          showing you the dangerous part and a safer path.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <CommandList
          commands={[
            {
              command: "dcg test '<command>'",
              description: "Check if a command would be blocked",
            },
            {
              command: "dcg test '<command>' --explain",
              description: "Explain why a command is unsafe",
            },
            {
              command: "dcg packs",
              description: "List available protection packs",
            },
            {
              command: "dcg install",
              description: "Register the Claude Code hook",
            },
            {
              command: "dcg uninstall",
              description: "Remove the hook (use --purge for full removal)",
            },
            {
              command: "dcg allow-once <code>",
              description: "Bypass for a single approved command",
            },
            {
              command: "dcg doctor",
              description: "Check installation and hook status",
            },
          ]}
        />
      </Section>

      <Divider />

      <Section
        title="Uninstalling DCG"
        icon={<ShieldAlert className="h-5 w-5" />}
        delay={0.23}
      >
        <Paragraph>
          If you need to remove DCG, you can uninstall the hook and optionally
          purge the binary and config. You can always re-enable it later with{" "}
          <Highlight>dcg install</Highlight>.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Remove hook only (keeps dcg installed)
$ dcg uninstall

# Full removal (hook + binary + config)
$ dcg uninstall --purge

# Verify removal
$ dcg doctor
$ claude /hooks`}
            language="bash"
          />
        </div>

        <TipBox variant="info">
          If you still want command safety but fewer blocks, prefer adjusting
          packs instead of uninstalling.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Protection Packs"
        icon={<Layers className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          Packs let you enable or disable rules based on your workflow. Keep the
          ones you need to avoid false positives.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# ~/.config/dcg/config.toml
[packs]
enabled = ["git", "filesystem", "database.postgresql", "containers.docker"]`}
            language="toml"
            filename="config.toml"
          />
        </div>

        <TipBox variant="info">
          Start with <Highlight>git</Highlight> and{" "}
          <Highlight>filesystem</Highlight> packs. Add database or cloud packs
          only when you use those tools.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="When You See a Block"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          A block is a warning, not a dead end. Use it as a checkpoint:
        </Paragraph>
        <BulletList
          items={[
            "Read the explanation carefully.",
            "Prefer the safer alternative when possible.",
            "Use allow-once only if you are confident.",
            "Document the decision in your commit or notes.",
          ]}
        />
      </Section>

      <Divider />

      <Section
        title="DCG + SLB"
        icon={<Zap className="h-5 w-5" />}
        delay={0.35}
      >
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6"
        >
          <Paragraph>
            DCG blocks obvious destructive commands instantly. SLB handles
            contextual risk that needs human approval. Together, they form a
            layered safety system.
          </Paragraph>
        </motion.div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Scenario data
// ---------------------------------------------------------------------------

type ThreatLevel = "critical" | "high" | "medium" | "low" | "safe" | "info";

interface DcgScenario {
  id: string;
  command: string;
  blocked: boolean;
  rule: string | null;
  pack: string;
  threatLevel: ThreatLevel;
  explanation: string;
  safer: string | null;
  detail: string;
  allowOnceCode: string | null;
}

const DCG_SCENARIOS: DcgScenario[] = [
  {
    id: "rm-rf",
    command: "rm -rf /",
    blocked: true,
    rule: "fs.rm.recursive.force.root",
    pack: "filesystem",
    threatLevel: "critical",
    explanation: "Recursive force delete of root filesystem. Catastrophic data loss.",
    safer: "rm -r ./build  (scoped, no -f)",
    detail: "Pattern match: rm with -r and -f flags targeting / or broad paths. This is the most dangerous filesystem command possible.",
    allowOnceCode: null,
  },
  {
    id: "git-reset",
    command: "git reset --hard HEAD~5",
    blocked: true,
    rule: "git.reset.hard",
    pack: "git",
    threatLevel: "high",
    explanation: "Hard reset discards 5 commits of uncommitted work permanently.",
    safer: "git stash && git reset --soft HEAD~5",
    detail: "Pattern match: git reset with --hard flag. Destroys working tree changes and staged files with no recovery path.",
    allowOnceCode: "DCG-A1X7",
  },
  {
    id: "safe-cmd",
    command: "git status && cargo build",
    blocked: false,
    rule: null,
    pack: "git",
    threatLevel: "safe",
    explanation: "Read-only git command chained with build. No destructive effects.",
    safer: null,
    detail: "No destructive patterns detected. git status is read-only, cargo build creates artifacts in target/ directory.",
    allowOnceCode: null,
  },
  {
    id: "allow-once",
    command: "git push --force origin main",
    blocked: true,
    rule: "git.push.force",
    pack: "git",
    threatLevel: "high",
    explanation: "Force push overwrites remote history. Others may lose work.",
    safer: "git push --force-with-lease origin main",
    detail: "Pattern match: git push with --force flag. Bypass available if you have confirmed no one else has pushed.",
    allowOnceCode: "DCG-F3K9",
  },
  {
    id: "drop-table",
    command: "DROP TABLE users CASCADE",
    blocked: true,
    rule: "db.drop.table.cascade",
    pack: "database",
    threatLevel: "critical",
    explanation: "Destroys table and all dependent objects. Unrecoverable without backup.",
    safer: "pg_dump -t users > backup.sql  (backup first)",
    detail: "Pattern match: DROP TABLE with CASCADE. Removes the table, indexes, constraints, and anything referencing it.",
    allowOnceCode: null,
  },
  {
    id: "docker-prune",
    command: "docker system prune -af --volumes",
    blocked: true,
    rule: "containers.prune.all",
    pack: "containers",
    threatLevel: "medium",
    explanation: "Removes all unused images, containers, networks, and volumes.",
    safer: "docker image prune  (just dangling images)",
    detail: "Pattern match: docker system prune with -a and --volumes. Will delete named volumes with data.",
    allowOnceCode: "DCG-P2M4",
  },
  {
    id: "dcg-doctor",
    command: "dcg doctor",
    blocked: false,
    rule: null,
    pack: "system",
    threatLevel: "info",
    explanation: "Health check of DCG installation. Reports hook status and pack config.",
    safer: null,
    detail: "DCG internal command. Checks: hook registered, config valid, packs loaded, binary version.",
    allowOnceCode: null,
  },
  {
    id: "chmod-777",
    command: "chmod -R 777 /etc",
    blocked: true,
    rule: "fs.chmod.world.writable",
    pack: "filesystem",
    threatLevel: "critical",
    explanation: "Makes /etc world-writable. Massive security vulnerability.",
    safer: "chmod 755 ./my-script.sh  (specific file, sane perms)",
    detail: "Pattern match: chmod with 777 on system directory. Opens every config file to modification by any user.",
    allowOnceCode: null,
  },
];

const PACKS_DATA = [
  { name: "git", rules: 12, desc: "Reset, force push, branch delete", enabled: true },
  { name: "filesystem", rules: 18, desc: "rm -rf, chmod, chown, symlinks", enabled: true },
  { name: "database", rules: 9, desc: "DROP, TRUNCATE, ALTER", enabled: true },
  { name: "containers", rules: 7, desc: "Prune, remove, system wipe", enabled: false },
  { name: "cloud", rules: 14, desc: "AWS/GCP delete, terraform destroy", enabled: false },
  { name: "network", rules: 5, desc: "iptables flush, DNS overwrite", enabled: false },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function threatColor(level: ThreatLevel): string {
  switch (level) {
    case "critical": return "text-red-400";
    case "high": return "text-orange-400";
    case "medium": return "text-amber-400";
    case "low": return "text-yellow-300";
    case "safe": return "text-emerald-400";
    case "info": return "text-sky-400";
  }
}

function threatBg(level: ThreatLevel): string {
  switch (level) {
    case "critical": return "bg-red-500";
    case "high": return "bg-orange-500";
    case "medium": return "bg-amber-500";
    case "low": return "bg-yellow-400";
    case "safe": return "bg-emerald-500";
    case "info": return "bg-sky-500";
  }
}

function threatBorder(level: ThreatLevel): string {
  switch (level) {
    case "critical": return "border-red-500/40";
    case "high": return "border-orange-500/40";
    case "medium": return "border-amber-500/40";
    case "low": return "border-yellow-400/40";
    case "safe": return "border-emerald-500/40";
    case "info": return "border-sky-500/40";
  }
}

function threatGlow(level: ThreatLevel): string {
  switch (level) {
    case "critical": return "bg-red-500/20";
    case "high": return "bg-orange-500/20";
    case "medium": return "bg-amber-500/20";
    case "low": return "bg-yellow-400/20";
    case "safe": return "bg-emerald-500/20";
    case "info": return "bg-sky-500/20";
  }
}

function formatTimestamp(idx: number): string {
  const base = 14;
  const min = base + idx * 3;
  const sec = (idx * 17) % 60;
  return `${String(min).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// Pipeline phase enum
// ---------------------------------------------------------------------------
type PipelinePhase = "idle" | "typing" | "intercepted" | "matching" | "verdict";

// ---------------------------------------------------------------------------
// Interactive DCG Demo - Command Guard Control Room
// ---------------------------------------------------------------------------

interface BlockLogEntry {
  scenarioId: string;
  command: string;
  rule: string | null;
  blocked: boolean;
  threatLevel: ThreatLevel;
  timestamp: string;
}

function InteractiveDcgDemo() {
  const [activeTab, setActiveTab] = useState<"pipeline" | "packs" | "log">("pipeline");
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const [phase, setPhase] = useState<PipelinePhase>("idle");
  const [typedChars, setTypedChars] = useState(0);
  const [blockLog, setBlockLog] = useState<BlockLogEntry[]>([]);
  const [packs, setPacks] = useState(PACKS_DATA.map((p) => ({ ...p })));
  const [showBypass, setShowBypass] = useState(false);
  const [bypassInput, setBypassInput] = useState("");
  const [bypassResult, setBypassResult] = useState<"idle" | "success" | "fail">("idle");

  const phaseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const typeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (phaseTimerRef.current) clearTimeout(phaseTimerRef.current);
      if (typeTimerRef.current) clearTimeout(typeTimerRef.current);
    };
  }, []);

  const scenario = selectedIdx !== null ? DCG_SCENARIOS[selectedIdx] : null;

  // Run the pipeline animation
  const runPipeline = useCallback((idx: number) => {
    if (phaseTimerRef.current) clearTimeout(phaseTimerRef.current);
    if (typeTimerRef.current) clearTimeout(typeTimerRef.current);

    setSelectedIdx(idx);
    setPhase("typing");
    setTypedChars(0);
    setShowBypass(false);
    setBypassResult("idle");
    setBypassInput("");
    setActiveTab("pipeline");

    const cmd = DCG_SCENARIOS[idx].command;
    let charIdx = 0;

    function typeNext() {
      charIdx++;
      setTypedChars(charIdx);
      if (charIdx < cmd.length) {
        typeTimerRef.current = setTimeout(typeNext, 25 + (charIdx % 3) * 10);
      } else {
        phaseTimerRef.current = setTimeout(() => {
          setPhase("intercepted");
          phaseTimerRef.current = setTimeout(() => {
            setPhase("matching");
            phaseTimerRef.current = setTimeout(() => {
              setPhase("verdict");
              const s = DCG_SCENARIOS[idx];
              setBlockLog((prev) => [
                {
                  scenarioId: s.id,
                  command: s.command,
                  rule: s.rule,
                  blocked: s.blocked,
                  threatLevel: s.threatLevel,
                  timestamp: formatTimestamp(prev.length),
                },
                ...prev,
              ].slice(0, 20));
            }, 600);
          }, 500);
        }, 300);
      }
    }

    typeTimerRef.current = setTimeout(typeNext, 80);
  }, []);

  const resetPipeline = useCallback(() => {
    if (phaseTimerRef.current) clearTimeout(phaseTimerRef.current);
    if (typeTimerRef.current) clearTimeout(typeTimerRef.current);
    setSelectedIdx(null);
    setPhase("idle");
    setTypedChars(0);
    setShowBypass(false);
    setBypassResult("idle");
    setBypassInput("");
  }, []);

  const handleBypassSubmit = useCallback(() => {
    if (!scenario) return;
    if (scenario.allowOnceCode && bypassInput.trim() === scenario.allowOnceCode) {
      setBypassResult("success");
    } else {
      setBypassResult("fail");
    }
  }, [scenario, bypassInput]);

  const togglePack = useCallback((idx: number) => {
    setPacks((prev) => prev.map((p, i) => (i === idx ? { ...p, enabled: !p.enabled } : p)));
  }, []);

  const totalRulesActive = packs.filter((p) => p.enabled).reduce((s, p) => s + p.rules, 0);

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-red-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-emerald-500/[0.04] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 space-y-4">
        {/* Header bar */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-red-500/30 to-orange-500/30 border border-red-500/20">
              <Shield className="h-4 w-4 text-red-400" />
            </div>
            <div>
              <p className="text-sm font-bold text-white/90">DCG Control Room</p>
              <p className="text-[10px] text-white/40">Command Guard v2.1 active</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <StatusPill
              label={`${totalRulesActive} rules`}
              color="emerald"
              icon={<ShieldCheck className="h-3 w-3" />}
            />
            <StatusPill
              label={`${blockLog.filter((e) => e.blocked).length} blocked`}
              color="red"
              icon={<XCircle className="h-3 w-3" />}
            />
          </div>
        </div>

        {/* Tab bar */}
        <div className="flex gap-1 rounded-xl bg-black/30 p-1">
          {([
            { key: "pipeline" as const, label: "Pipeline", icon: <Activity className="h-3.5 w-3.5" /> },
            { key: "packs" as const, label: "Packs", icon: <Layers className="h-3.5 w-3.5" /> },
            { key: "log" as const, label: "History", icon: <History className="h-3.5 w-3.5" /> },
          ]).map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`flex-1 flex items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-xs font-medium transition ${
                activeTab === tab.key
                  ? "bg-white/[0.08] text-white shadow-sm"
                  : "text-white/40 hover:text-white/60"
              }`}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>

        {/* Scenario selector */}
        <div>
          <p className="text-[10px] uppercase tracking-wider text-white/30 mb-2 font-semibold">Select Command to Analyze</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {DCG_SCENARIOS.map((s, i) => (
              <motion.button
                key={s.id}
                type="button"
                onClick={() => runPipeline(i)}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                transition={{ type: "spring", stiffness: 400, damping: 25 }}
                className={`relative rounded-xl border px-3 py-2.5 text-left font-mono text-[11px] transition-colors overflow-hidden ${
                  selectedIdx === i
                    ? `${threatBorder(s.threatLevel)} ${threatGlow(s.threatLevel)}`
                    : "border-white/[0.06] bg-white/[0.02] hover:border-white/[0.15]"
                }`}
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className={`flex-shrink-0 h-1.5 w-1.5 rounded-full ${threatBg(s.threatLevel)}`} />
                    <span className={`truncate ${selectedIdx === i ? threatColor(s.threatLevel) : "text-white/70"}`}>
                      <span className="text-white/30">$ </span>{s.command}
                    </span>
                  </div>
                  {s.blocked ? (
                    <XCircle className="h-3 w-3 text-red-400/60 flex-shrink-0" />
                  ) : (
                    <CheckCircle className="h-3 w-3 text-emerald-400/60 flex-shrink-0" />
                  )}
                </div>
              </motion.button>
            ))}
          </div>
        </div>

        {/* Tab content */}
        <AnimatePresence mode="wait">
          {activeTab === "pipeline" && (
            <motion.div
              key="pipeline"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <PipelineView
                scenario={scenario}
                phase={phase}
                typedChars={typedChars}
                showBypass={showBypass}
                setShowBypass={setShowBypass}
                bypassInput={bypassInput}
                setBypassInput={setBypassInput}
                bypassResult={bypassResult}
                onBypassReset={() => setBypassResult("idle")}
                onBypassSubmit={handleBypassSubmit}
                onReset={resetPipeline}
              />
            </motion.div>
          )}
          {activeTab === "packs" && (
            <motion.div
              key="packs"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <PacksBrowser packs={packs} onToggle={togglePack} />
            </motion.div>
          )}
          {activeTab === "log" && (
            <motion.div
              key="log"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            >
              <BlockHistoryLog entries={blockLog} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// StatusPill
// ---------------------------------------------------------------------------

function StatusPill({
  label,
  color,
  icon,
}: {
  label: string;
  color: "emerald" | "red" | "amber" | "sky";
  icon: React.ReactNode;
}) {
  const classes: Record<string, string> = {
    emerald: "bg-emerald-500/10 border-emerald-500/20 text-emerald-400",
    red: "bg-red-500/10 border-red-500/20 text-red-400",
    amber: "bg-amber-500/10 border-amber-500/20 text-amber-400",
    sky: "bg-sky-500/10 border-sky-500/20 text-sky-400",
  };
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[10px] font-medium ${classes[color]}`}>
      {icon}
      {label}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Pipeline View - the animated command pipeline
// ---------------------------------------------------------------------------

function PipelineView({
  scenario,
  phase,
  typedChars,
  showBypass,
  setShowBypass,
  bypassInput,
  setBypassInput,
  bypassResult,
  onBypassReset,
  onBypassSubmit,
  onReset,
}: {
  scenario: DcgScenario | null;
  phase: PipelinePhase;
  typedChars: number;
  showBypass: boolean;
  setShowBypass: (v: boolean) => void;
  bypassInput: string;
  setBypassInput: (v: string) => void;
  bypassResult: "idle" | "success" | "fail";
  onBypassReset: () => void;
  onBypassSubmit: () => void;
  onReset: () => void;
}) {
  if (!scenario && phase === "idle") {
    return (
      <div className="rounded-xl border border-white/[0.06] bg-black/20 p-8 text-center">
        <Shield className="h-10 w-10 text-white/20 mx-auto mb-3" />
        <p className="text-sm text-white/40">Select a command above to see DCG in action</p>
        <p className="text-[10px] text-white/25 mt-1">Watch the full interception pipeline animate</p>
      </div>
    );
  }

  if (!scenario) return null;

  const cmdDisplay = phase === "typing"
    ? scenario.command.slice(0, typedChars)
    : scenario.command;

  const phaseSteps: { label: string; icon: React.ReactNode; done: boolean; active: boolean }[] = [
    {
      label: "Agent Types",
      icon: <Terminal className="h-3.5 w-3.5" />,
      done: phase !== "typing",
      active: phase === "typing",
    },
    {
      label: "DCG Intercepts",
      icon: <Eye className="h-3.5 w-3.5" />,
      done: phase === "matching" || phase === "verdict",
      active: phase === "intercepted",
    },
    {
      label: "Rule Match",
      icon: <Activity className="h-3.5 w-3.5" />,
      done: phase === "verdict",
      active: phase === "matching",
    },
    {
      label: scenario.blocked ? "BLOCKED" : "ALLOWED",
      icon: scenario.blocked ? <Lock className="h-3.5 w-3.5" /> : <Unlock className="h-3.5 w-3.5" />,
      done: false,
      active: phase === "verdict",
    },
  ];

  return (
    <div className="space-y-3">
      {/* Phase progress indicators */}
      <div className="flex items-center gap-1 overflow-hidden">
        {phaseSteps.map((step, i) => (
          <div key={step.label} className="flex items-center gap-1 flex-1 min-w-0">
            <motion.div
              animate={{
                backgroundColor: step.active
                  ? (scenario.blocked && i === 3 ? "rgba(239,68,68,0.3)" : "rgba(99,102,241,0.3)")
                  : step.done
                    ? "rgba(16,185,129,0.2)"
                    : "rgba(255,255,255,0.03)",
                borderColor: step.active
                  ? (scenario.blocked && i === 3 ? "rgba(239,68,68,0.5)" : "rgba(99,102,241,0.5)")
                  : step.done
                    ? "rgba(16,185,129,0.3)"
                    : "rgba(255,255,255,0.06)",
              }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="flex items-center gap-1.5 rounded-lg border px-2 py-1.5 flex-1 min-w-0"
            >
              <span className={step.active ? (scenario.blocked && i === 3 ? "text-red-400" : "text-primary") : step.done ? "text-emerald-400" : "text-white/30"}>
                {step.done ? <CheckCircle className="h-3.5 w-3.5" /> : step.icon}
              </span>
              <span className={`text-[10px] font-medium truncate ${
                step.active ? (scenario.blocked && i === 3 ? "text-red-400" : "text-white/80") : step.done ? "text-emerald-400/80" : "text-white/30"
              }`}>
                {step.label}
              </span>
            </motion.div>
            {i < phaseSteps.length - 1 && (
              <ChevronRight className="h-3 w-3 text-white/20 flex-shrink-0" />
            )}
          </div>
        ))}
      </div>

      {/* Terminal display */}
      <motion.div
        animate={
          phase === "verdict" && scenario.blocked
            ? { x: [0, -4, 4, -3, 3, -1, 1, 0] }
            : {}
        }
        transition={{ type: "spring", stiffness: 500, damping: 30 }}
        className={`rounded-xl border bg-black/40 overflow-hidden transition-colors duration-300 ${
          phase === "verdict"
            ? scenario.blocked ? "border-red-500/30" : "border-emerald-500/30"
            : "border-white/[0.08]"
        }`}
      >
        {/* Terminal chrome */}
        <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
          <div className="flex gap-1.5">
            <span className="h-2 w-2 rounded-full bg-red-500/60" />
            <span className="h-2 w-2 rounded-full bg-yellow-500/60" />
            <span className="h-2 w-2 rounded-full bg-green-500/60" />
          </div>
          <span className="text-[10px] text-white/30 ml-1 font-mono">dcg-guard</span>
          {phase === "verdict" && (
            <button
              type="button"
              onClick={onReset}
              className="ml-auto flex items-center gap-1 text-[10px] text-white/40 hover:text-white/60 transition-colors"
            >
              <RotateCcw className="h-3 w-3" />
              Reset
            </button>
          )}
        </div>

        <div className="p-4 font-mono text-sm space-y-2">
          {/* Command being typed */}
          <div className="flex items-start gap-1">
            <span className="text-emerald-400">$</span>
            <span className="text-white/50">dcg test &quot;</span>
            <span className={phase === "verdict" ? (scenario.blocked ? "text-red-400" : "text-emerald-400") : "text-white/80"}>
              {cmdDisplay}
            </span>
            {phase === "typing" && (
              <motion.span
                animate={{ opacity: [1, 0] }}
                transition={{ duration: 0.6, repeat: Infinity, repeatType: "reverse" }}
                className="text-white/60"
              >
                |
              </motion.span>
            )}
            <span className="text-white/50">&quot; --explain</span>
          </div>

          {/* Interception notice */}
          <AnimatePresence>
            {(phase === "intercepted" || phase === "matching" || phase === "verdict") && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
              >
                <span className="text-sky-400 text-xs">[DCG]</span>
                <span className="text-white/50 text-xs"> Intercepting command...</span>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Rule matching */}
          <AnimatePresence>
            {(phase === "matching" || phase === "verdict") && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
              >
                {scenario.rule ? (
                  <div className="text-xs">
                    <span className="text-amber-400">[MATCH]</span>
                    <span className="text-white/50"> Rule: </span>
                    <span className="text-amber-300">{scenario.rule}</span>
                    <span className="text-white/30"> (pack: {scenario.pack})</span>
                  </div>
                ) : (
                  <div className="text-xs">
                    <span className="text-emerald-400">[SCAN]</span>
                    <span className="text-white/50"> No destructive patterns matched</span>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>

          {/* Verdict */}
          <AnimatePresence>
            {phase === "verdict" && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className="space-y-1 pt-1"
              >
                {scenario.blocked ? (
                  <>
                    <div className="text-xs flex items-center gap-1">
                      <XCircle className="h-3 w-3 text-red-400" />
                      <span className="text-red-400 font-bold">BLOCKED</span>
                      <span className="text-white/30">|</span>
                      <span className="text-white/50">{scenario.explanation}</span>
                    </div>
                    {scenario.safer && (
                      <div className="text-xs">
                        <span className="text-emerald-400">  Safer:</span>
                        <span className="text-emerald-300/80"> {scenario.safer}</span>
                      </div>
                    )}
                    {scenario.allowOnceCode && (
                      <div className="text-xs">
                        <span className="text-amber-400">  Bypass:</span>
                        <span className="text-white/40"> dcg allow-once {scenario.allowOnceCode}</span>
                      </div>
                    )}
                  </>
                ) : (
                  <div className="text-xs flex items-center gap-1">
                    <CheckCircle className="h-3 w-3 text-emerald-400" />
                    <span className="text-emerald-400 font-bold">ALLOWED</span>
                    <span className="text-white/30">|</span>
                    <span className="text-white/50">{scenario.explanation}</span>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </motion.div>

      {/* Threat level + details card */}
      <AnimatePresence>
        {phase === "verdict" && (
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="space-y-3"
          >
            {/* Threat level bar */}
            <div className={`rounded-xl border ${threatBorder(scenario.threatLevel)} ${threatGlow(scenario.threatLevel)} p-3`}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Gauge className={`h-4 w-4 ${threatColor(scenario.threatLevel)}`} />
                  <span className="text-xs font-semibold text-white/70">Threat Level</span>
                </div>
                <span className={`text-xs font-bold uppercase ${threatColor(scenario.threatLevel)}`}>
                  {scenario.threatLevel}
                </span>
              </div>
              {/* Visual threat bar */}
              <div className="mt-2 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  initial={{ width: "0%" }}
                  animate={{
                    width:
                      scenario.threatLevel === "critical" ? "100%"
                        : scenario.threatLevel === "high" ? "75%"
                          : scenario.threatLevel === "medium" ? "50%"
                            : scenario.threatLevel === "low" ? "25%"
                              : scenario.threatLevel === "safe" ? "10%"
                                : "5%",
                  }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  className={`h-full rounded-full ${threatBg(scenario.threatLevel)}`}
                />
              </div>
            </div>

            {/* Detail card */}
            <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3 text-xs text-white/50 leading-relaxed">
              <p className="text-white/30 font-semibold uppercase tracking-wider text-[10px] mb-1">Analysis Detail</p>
              <p>{scenario.detail}</p>
            </div>

            {/* Allow-once bypass demo */}
            {scenario.blocked && scenario.allowOnceCode && (
              <div className="rounded-xl border border-amber-500/20 bg-amber-500/[0.05] p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <KeyRound className="h-3.5 w-3.5 text-amber-400" />
                    <span className="text-xs font-semibold text-amber-400">Allow-Once Bypass</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => setShowBypass(!showBypass)}
                    className="text-[10px] text-amber-400/60 hover:text-amber-400 transition-colors"
                  >
                    {showBypass ? "Hide" : "Try It"}
                  </button>
                </div>
                <AnimatePresence>
                  {showBypass && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: "auto" }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    >
                      <p className="text-[10px] text-white/40 mb-2">
                        Enter the bypass code to allow this command once:
                      </p>
                      <div className="flex gap-2">
                        <input
                          type="text"
                          value={bypassInput}
                          onChange={(e) => {
                            setBypassInput(e.target.value);
                            onBypassReset();
                          }}
                          placeholder="DCG-XXXX"
                          className="flex-1 rounded-lg border border-white/[0.08] bg-black/40 px-3 py-1.5 text-xs font-mono text-white/80 placeholder:text-white/20 focus:outline-none focus:border-amber-500/40"
                        />
                        <button
                          type="button"
                          onClick={onBypassSubmit}
                          className="rounded-lg bg-amber-500/20 border border-amber-500/30 px-3 py-1.5 text-xs font-medium text-amber-400 hover:bg-amber-500/30 transition-colors"
                        >
                          Submit
                        </button>
                      </div>
                      <AnimatePresence mode="wait">
                        {bypassResult === "success" && (
                          <motion.p
                            key="ok"
                            initial={{ opacity: 0, y: 4 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0 }}
                            className="text-[10px] text-emerald-400 mt-2 flex items-center gap-1"
                          >
                            <CheckCircle className="h-3 w-3" />
                            Bypass accepted. Command allowed once.
                          </motion.p>
                        )}
                        {bypassResult === "fail" && (
                          <motion.p
                            key="err"
                            initial={{ opacity: 0, y: 4 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0 }}
                            className="text-[10px] text-red-400 mt-2 flex items-center gap-1"
                          >
                            <XCircle className="h-3 w-3" />
                            Invalid code. Hint: check the terminal output above.
                          </motion.p>
                        )}
                      </AnimatePresence>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            )}

            {/* dcg doctor result for doctor scenario */}
            {scenario.id === "dcg-doctor" && <DcgDoctorPanel />}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Doctor Panel
// ---------------------------------------------------------------------------

function DcgDoctorPanel() {
  const checks = [
    { label: "Hook registered", ok: true },
    { label: "Config file valid", ok: true },
    { label: "Binary in PATH", ok: true },
    { label: "Packs loaded", ok: true },
    { label: "Version: v2.1.0", ok: true },
  ];

  return (
    <div className="rounded-xl border border-sky-500/20 bg-sky-500/[0.05] p-3 space-y-2">
      <div className="flex items-center gap-2 mb-1">
        <Stethoscope className="h-3.5 w-3.5 text-sky-400" />
        <span className="text-xs font-semibold text-sky-400">dcg doctor output</span>
      </div>
      {checks.map((c) => (
        <motion.div
          key={c.label}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center gap-2 text-xs"
        >
          {c.ok ? (
            <CheckCircle className="h-3 w-3 text-emerald-400" />
          ) : (
            <XCircle className="h-3 w-3 text-red-400" />
          )}
          <span className={c.ok ? "text-white/60" : "text-red-400"}>{c.label}</span>
        </motion.div>
      ))}
      <p className="text-[10px] text-emerald-400/80 mt-1 font-medium">All checks passed</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Packs Browser
// ---------------------------------------------------------------------------

function PacksBrowser({
  packs: packsList,
  onToggle,
}: {
  packs: { name: string; rules: number; desc: string; enabled: boolean }[];
  onToggle: (idx: number) => void;
}) {
  return (
    <div className="space-y-3">
      <div className="rounded-xl border border-white/[0.06] bg-black/20 p-3">
        <div className="flex items-center gap-2 mb-3">
          <Layers className="h-4 w-4 text-primary" />
          <span className="text-xs font-bold text-white/80">Protection Packs</span>
          <span className="text-[10px] text-white/30 ml-auto">
            {packsList.filter((p) => p.enabled).length}/{packsList.length} enabled
          </span>
        </div>

        <div className="space-y-2">
          {packsList.map((p, i) => (
            <motion.div
              key={p.name}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.05 }}
              className={`flex items-center justify-between rounded-lg border p-3 transition-colors ${
                p.enabled
                  ? "border-emerald-500/20 bg-emerald-500/[0.04]"
                  : "border-white/[0.06] bg-white/[0.01]"
              }`}
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className={`h-2 w-2 rounded-full flex-shrink-0 ${
                  p.enabled ? "bg-emerald-500" : "bg-white/20"
                }`} />
                <div className="min-w-0">
                  <p className={`text-xs font-semibold ${p.enabled ? "text-white/80" : "text-white/40"}`}>
                    {p.name}
                  </p>
                  <p className="text-[10px] text-white/30 truncate">{p.desc}</p>
                </div>
              </div>
              <div className="flex items-center gap-3 flex-shrink-0">
                <span className="text-[10px] text-white/30">{p.rules} rules</span>
                <button type="button" onClick={() => onToggle(i)} className="text-white/50 hover:text-white/80 transition-colors">
                  {p.enabled ? (
                    <ToggleRight className="h-5 w-5 text-emerald-400" />
                  ) : (
                    <ToggleLeft className="h-5 w-5 text-white/30" />
                  )}
                </button>
              </div>
            </motion.div>
          ))}
        </div>
      </div>

      {/* Mini terminal showing dcg packs command */}
      <div className="rounded-xl border border-white/[0.06] bg-black/30 p-3">
        <div className="flex items-center gap-1.5 mb-2">
          <div className="flex gap-1">
            <span className="h-1.5 w-1.5 rounded-full bg-red-500/60" />
            <span className="h-1.5 w-1.5 rounded-full bg-yellow-500/60" />
            <span className="h-1.5 w-1.5 rounded-full bg-green-500/60" />
          </div>
          <span className="text-[9px] text-white/20 ml-1 font-mono">terminal</span>
        </div>
        <div className="font-mono text-[11px] space-y-1">
          <p>
            <span className="text-emerald-400">$</span>
            <span className="text-white/60"> dcg packs</span>
          </p>
          {packsList.map((p) => (
            <p key={p.name} className="text-white/40">
              {"  "}
              {p.enabled ? (
                <span className="text-emerald-400">[on] </span>
              ) : (
                <span className="text-white/25">[--] </span>
              )}
              <span className={p.enabled ? "text-white/60" : "text-white/30"}>
                {p.name}
              </span>
              <span className="text-white/20"> ({p.rules} rules)</span>
            </p>
          ))}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Block History Log
// ---------------------------------------------------------------------------

function BlockHistoryLog({ entries }: { entries: BlockLogEntry[] }) {
  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-white/[0.06] bg-black/20 p-8 text-center">
        <History className="h-8 w-8 text-white/15 mx-auto mb-2" />
        <p className="text-xs text-white/30">No commands analyzed yet</p>
        <p className="text-[10px] text-white/20 mt-1">Run commands from the Pipeline tab to see history</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="rounded-xl border border-white/[0.06] bg-black/20 overflow-hidden">
        {/* Header */}
        <div className="flex items-center gap-3 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
          <History className="h-3.5 w-3.5 text-white/40" />
          <span className="text-xs font-semibold text-white/60">Block History</span>
          <span className="text-[10px] text-white/30 ml-auto">{entries.length} entries</span>
        </div>

        {/* Entries */}
        <div className="max-h-64 overflow-y-auto">
          {entries.map((entry, i) => (
            <motion.div
              key={`${entry.scenarioId}-${i}`}
              initial={{ opacity: 0, x: -12 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={`flex items-center gap-3 px-3 py-2 border-b border-white/[0.04] last:border-b-0 ${
                i === 0 ? "bg-white/[0.02]" : ""
              }`}
            >
              <span className="text-[10px] text-white/25 font-mono w-10 flex-shrink-0">
                {entry.timestamp}
              </span>
              <span className={`flex-shrink-0 h-1.5 w-1.5 rounded-full ${threatBg(entry.threatLevel)}`} />
              {entry.blocked ? (
                <XCircle className="h-3 w-3 text-red-400 flex-shrink-0" />
              ) : (
                <CheckCircle className="h-3 w-3 text-emerald-400 flex-shrink-0" />
              )}
              <span className="text-[11px] font-mono text-white/60 truncate min-w-0">
                {entry.command}
              </span>
              {entry.rule && (
                <span className="text-[9px] text-white/25 font-mono flex-shrink-0 ml-auto">
                  {entry.rule}
                </span>
              )}
            </motion.div>
          ))}
        </div>
      </div>

      {/* Summary stats */}
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-lg border border-white/[0.06] bg-black/20 p-2 text-center">
          <p className="text-lg font-bold text-white/80">{entries.length}</p>
          <p className="text-[9px] text-white/30 uppercase tracking-wider">Total</p>
        </div>
        <div className="rounded-lg border border-red-500/20 bg-red-500/[0.05] p-2 text-center">
          <p className="text-lg font-bold text-red-400">{entries.filter((e) => e.blocked).length}</p>
          <p className="text-[9px] text-red-400/50 uppercase tracking-wider">Blocked</p>
        </div>
        <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/[0.05] p-2 text-center">
          <p className="text-lg font-bold text-emerald-400">{entries.filter((e) => !e.blocked).length}</p>
          <p className="text-[9px] text-emerald-400/50 uppercase tracking-wider">Allowed</p>
        </div>
      </div>
    </div>
  );
}
