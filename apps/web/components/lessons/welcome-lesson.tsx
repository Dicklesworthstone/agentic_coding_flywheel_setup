"use client";

import { useState, useCallback, useEffect } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Terminal,
  Code2,
  Bot,
  Layers,
  Wrench,
  Zap,
  BookOpen,
  Shield,
  ChevronRight,
  Activity,
  Globe,
  Lock,
  HardDrive,
  Network,
} from "lucide-react";
import {
  Section,
  Paragraph,
  FeatureCard,
  FeatureGrid,
  TipBox,
  StepList,
  Highlight,
  Divider,
  GoalBanner,
} from "./lesson-components";

export function WelcomeLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand what you have and what you&apos;re about to learn.
      </GoalBanner>

      {/* What You Now Have Section */}
      <Section
        title="What You Now Have"
        icon={<Zap className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph highlight>
          Congratulations! You&apos;ve just set up a fully-armed{" "}
          <Highlight>agentic engineering workstation</Highlight>.
        </Paragraph>

        <div className="mt-8">
          <Paragraph>Here&apos;s what&apos;s installed on your VPS:</Paragraph>
        </div>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Terminal className="h-5 w-5" />}
              title="Beautiful Terminal"
              description="zsh, Oh My Zsh, and Powerlevel10k for a stunning shell experience"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Wrench className="h-5 w-5" />}
              title="Modern CLI Tools"
              description="lsd, bat, ripgrep, fzf, and zoxide for supercharged productivity"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Code2 className="h-5 w-5" />}
              title="Language Runtimes"
              description="JavaScript (Bun), Python (uv), Rust, and Go ready to go"
              gradient="from-sky-500/20 to-blue-500/20"
            />
            <FeatureCard
              icon={<Bot className="h-5 w-5" />}
              title="Three Coding Agents"
              description="Claude Code (cc), Codex CLI (cod), and Antigravity CLI (agy)"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>

        {/* Agent Cards */}
        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <AgentCard
            name="Claude Code"
            shortcut="cc"
            color="from-orange-500 to-amber-500"
          />
          <AgentCard
            name="Codex CLI"
            shortcut="cod"
            color="from-emerald-500 to-teal-500"
          />
          <AgentCard
            name="Antigravity CLI"
            shortcut="agy"
            color="from-blue-500 to-purple-500"
          />
        </div>
      </Section>

      <Divider />

      {/* The Mental Model Section */}
      <Section
        title="The Mental Model"
        icon={<Layers className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>Think of your setup like this:</Paragraph>

        {/* Architecture Diagram */}
        <div className="mt-8 relative">
          <InteractiveArchitecture />
        </div>

        <div className="mt-8 space-y-4">
          <Paragraph>
            Your laptop is just the{" "}
            <Highlight>remote control</Highlight>. The real work happens on the
            VPS.
          </Paragraph>
          <Paragraph>
            If your SSH connection drops? No problem. Your work continues in
            tmux.
          </Paragraph>
        </div>
      </Section>

      <Divider />

      {/* What This Tutorial Will Teach You */}
      <Section
        title="What You'll Learn"
        icon={<BookOpen className="h-5 w-5" />}
        delay={0.3}
      >
        <StepList
          steps={[
            {
              title: "Linux basics",
              description: "Navigating the filesystem with confidence",
            },
            {
              title: "SSH fundamentals",
              description: "Staying connected to your VPS",
            },
            {
              title: "tmux essentials",
              description: "Persistent sessions that survive disconnects",
            },
            {
              title: "Agent commands",
              description: "Talking to Claude, Codex, and Antigravity",
            },
            {
              title: "NTM mastery",
              description: "Orchestrating multiple agents at once",
            },
            {
              title: "The flywheel workflow",
              description: "Putting it all together for maximum velocity",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Tip */}
      <TipBox variant="tip">
        If you ever break something, you can delete this VPS and re-run ACFS.
        That&apos;s the beauty of VPS development!
      </TipBox>
    </div>
  );
}

// =============================================================================
// AGENT CARD - Individual agent display
// =============================================================================
function AgentCard({
  name,
  shortcut,
  color,
}: {
  name: string;
  shortcut: string;
  color: string;
}) {
  return (
    <motion.div
      whileHover={{ y: -4, scale: 1.03 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl overflow-hidden transition duration-500 hover:border-white/[0.15]"
    >
      {/* Gradient background on hover */}
      <div
        className={`absolute inset-0 bg-gradient-to-br ${color} opacity-0 group-hover:opacity-10 transition-opacity duration-500`}
      />

      <div className="relative flex flex-col items-center text-center">
        <div
          className={`flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br ${color} shadow-lg mb-4`}
        >
          <Bot className="h-7 w-7 text-white" />
        </div>
        <span className="font-bold text-white">{name}</span>
        <code className="mt-2 px-3 py-1.5 rounded-lg bg-black/40 border border-white/[0.1] text-sm font-mono text-white/60">
          {shortcut}
        </code>
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE ARCHITECTURE - Layered ACFS system explorer
// =============================================================================

interface ArchLayer {
  id: string;
  label: string;
  color: string;
  borderColor: string;
  glowColor: string;
  icon: React.ReactNode;
  components: ArchComponent[];
}

interface ArchComponent {
  id: string;
  name: string;
  shortName: string;
  description: string;
  commands: string[];
  dependencies: string[];
  status: "active" | "ready" | "standby";
}

const archLayers: ArchLayer[] = [
  {
    id: "infrastructure",
    label: "VPS Infrastructure",
    color: "bg-sky-500/10",
    borderColor: "border-sky-500/20",
    glowColor: "from-sky-500/20 to-sky-600/10",
    icon: <Globe className="h-4 w-4" />,
    components: [
      {
        id: "ubuntu",
        name: "Ubuntu 24.04 LTS",
        shortName: "Ubuntu",
        description:
          "The base operating system running on your VPS. Ubuntu LTS provides a stable, well-supported foundation with long-term security updates.",
        commands: ["lsb_release -a", "uname -r", "uptime"],
        dependencies: [],
        status: "active",
      },
      {
        id: "ssh",
        name: "SSH Server (OpenSSH)",
        shortName: "SSH",
        description:
          "Secure Shell daemon that accepts encrypted connections from your laptop. All traffic between your machine and the VPS flows through this encrypted tunnel.",
        commands: ["ssh user@vps", "ssh-keygen", "ssh-copy-id"],
        dependencies: ["ubuntu"],
        status: "active",
      },
      {
        id: "firewall",
        name: "UFW Firewall",
        shortName: "UFW",
        description:
          "Uncomplicated Firewall restricts network access to only the ports you need - SSH (22) and any development servers you expose.",
        commands: ["sudo ufw status", "sudo ufw allow 22"],
        dependencies: ["ubuntu"],
        status: "active",
      },
    ],
  },
  {
    id: "shell",
    label: "Shell & Terminal",
    color: "bg-emerald-500/10",
    borderColor: "border-emerald-500/20",
    glowColor: "from-emerald-500/20 to-emerald-600/10",
    icon: <Terminal className="h-4 w-4" />,
    components: [
      {
        id: "zsh",
        name: "Zsh + Oh My Zsh",
        shortName: "Zsh",
        description:
          "Z Shell with the Oh My Zsh framework and Powerlevel10k theme. Gives you autocomplete, syntax highlighting, and a gorgeous prompt.",
        commands: ["chsh -s $(which zsh)", "omz update"],
        dependencies: ["ubuntu"],
        status: "active",
      },
      {
        id: "tmux",
        name: "tmux Sessions",
        shortName: "tmux",
        description:
          "Terminal multiplexer that keeps sessions alive when SSH disconnects. Your agents keep running no matter what happens to your connection.",
        commands: ["tmux new -s work", "tmux attach", "tmux ls"],
        dependencies: ["zsh"],
        status: "active",
      },
      {
        id: "acfs-shell",
        name: "ACFS Shell Extensions",
        shortName: "acfs.zshrc",
        description:
          "Custom shell aliases and functions loaded by ACFS. Provides shortcuts like cc, cod, agy and all the acfs subcommands.",
        commands: ["source ~/.acfs.zshrc", "acfs help"],
        dependencies: ["zsh"],
        status: "active",
      },
    ],
  },
  {
    id: "devtools",
    label: "Dev Tools",
    color: "bg-violet-500/10",
    borderColor: "border-violet-500/20",
    glowColor: "from-violet-500/20 to-violet-600/10",
    icon: <Wrench className="h-4 w-4" />,
    components: [
      {
        id: "cli-tools",
        name: "Modern CLI (lsd, bat, rg, fzf)",
        shortName: "CLI Tools",
        description:
          "Replacement tools that are faster and prettier than the defaults. lsd for ls, bat for cat, ripgrep for grep, and fzf for fuzzy finding.",
        commands: ["lsd -la", "bat file.ts", "rg 'pattern'", "fzf"],
        dependencies: ["zsh"],
        status: "active",
      },
      {
        id: "runtimes",
        name: "Language Runtimes",
        shortName: "Runtimes",
        description:
          "Bun (JavaScript/TypeScript), Python via uv, Rust via rustup, and Go. Everything you need to build in any language.",
        commands: ["bun --version", "uv python list", "rustc --version", "go version"],
        dependencies: ["ubuntu"],
        status: "active",
      },
      {
        id: "git",
        name: "Git + GitHub CLI",
        shortName: "Git+gh",
        description:
          "Version control with Git and the GitHub CLI (gh) for PRs, issues, and repo management directly from the terminal.",
        commands: ["git status", "gh pr create", "gh repo clone"],
        dependencies: ["ubuntu"],
        status: "active",
      },
    ],
  },
  {
    id: "agents",
    label: "Coding Agents",
    color: "bg-amber-500/10",
    borderColor: "border-amber-500/20",
    glowColor: "from-amber-500/20 to-orange-500/10",
    icon: <Bot className="h-4 w-4" />,
    components: [
      {
        id: "claude",
        name: "Claude Code (Anthropic)",
        shortName: "cc",
        description:
          "Anthropic's agentic coding tool. The most capable agent for complex refactoring, architecture decisions, and multi-file changes.",
        commands: ["cc", "cc 'fix the login bug'", "cc --resume"],
        dependencies: ["tmux", "runtimes", "git"],
        status: "active",
      },
      {
        id: "codex",
        name: "Codex CLI (OpenAI)",
        shortName: "cod",
        description:
          "OpenAI's command-line coding agent. Great for quick edits, code generation, and working with GPT-4 models.",
        commands: ["cod", "cod 'add unit tests'"],
        dependencies: ["tmux", "runtimes", "git"],
        status: "ready",
      },
      {
        id: "antigravity",
        name: "Antigravity CLI (Google)",
        shortName: "agy",
        description:
          "Google's coding assistant, pinned to Gemini 3.7 Flash (High). Excellent for research-heavy tasks, fresh-eyes review, and large codebases. (Successor to the retired Gemini CLI / gmi.)",
        commands: ["agy", "agy 'explain this codebase'"],
        dependencies: ["tmux", "runtimes", "git"],
        status: "ready",
      },
    ],
  },
  {
    id: "coordination",
    label: "Coordination Stack",
    color: "bg-rose-500/10",
    borderColor: "border-rose-500/20",
    glowColor: "from-rose-500/20 to-pink-500/10",
    icon: <Network className="h-4 w-4" />,
    components: [
      {
        id: "ntm",
        name: "NTM (Neo-Terminal Manager)",
        shortName: "ntm",
        description:
          "The orchestrator. Launches multiple agents in parallel tmux panes so you can run Claude, Codex, and Antigravity simultaneously on different tasks.",
        commands: ["ntm launch", "ntm status", "ntm kill"],
        dependencies: ["tmux", "claude", "codex", "antigravity"],
        status: "active",
      },
      {
        id: "beads",
        name: "Beads (Task Tracking)",
        shortName: "beads",
        description:
          "Lightweight task and issue tracker that lives in your repo as a JSONL file. Agents can read and update beads to coordinate work.",
        commands: ["acfs beads list", "acfs beads add 'task'"],
        dependencies: ["git"],
        status: "active",
      },
      {
        id: "agents-md",
        name: "AGENTS.md Protocol",
        shortName: "AGENTS.md",
        description:
          "A markdown file in your repo that tells agents about the project, coding conventions, and how to behave. The shared brain for all agents.",
        commands: ["cat AGENTS.md", "acfs agents-md"],
        dependencies: ["git"],
        status: "active",
      },
    ],
  },
  {
    id: "safety",
    label: "Safety Layer",
    color: "bg-red-500/10",
    borderColor: "border-red-500/20",
    glowColor: "from-red-500/20 to-red-600/10",
    icon: <Shield className="h-4 w-4" />,
    components: [
      {
        id: "doctor",
        name: "acfs doctor",
        shortName: "doctor",
        description:
          "Diagnostic tool that checks your entire stack for problems: SSH keys, API keys, tool versions, tmux health, and more. Your first stop when something feels off.",
        commands: ["acfs doctor", "acfs doctor --fix"],
        dependencies: ["acfs-shell"],
        status: "active",
      },
      {
        id: "git-safety",
        name: "Git Safety Net",
        shortName: "Git Safety",
        description:
          "Automatic branch protection and commit hygiene. Agents work on branches, never directly on main. Easy to roll back any change.",
        commands: ["git log --oneline", "git diff", "git stash"],
        dependencies: ["git"],
        status: "active",
      },
      {
        id: "vps-reset",
        name: "VPS Reset Escape Hatch",
        shortName: "Reset",
        description:
          "If everything goes wrong, you can nuke the VPS and re-run the installer. Your code lives in Git, so nothing is ever truly lost.",
        commands: ["acfs reinstall", "install.sh"],
        dependencies: ["ubuntu"],
        status: "standby",
      },
    ],
  },
];

const terminalCommands = [
  { prompt: "~", cmd: "acfs status", output: "All systems nominal" },
  { prompt: "~", cmd: "ntm launch 3", output: "Spawning 3 agent panes..." },
  { prompt: "~", cmd: "acfs doctor", output: "14/14 checks passed" },
  { prompt: "~", cmd: "cc 'fix the auth bug'", output: "Claude Code starting..." },
  { prompt: "~/proj", cmd: "acfs beads list", output: "3 open, 2 done" },
  { prompt: "~", cmd: "tmux ls", output: "work: 4 panes (attached)" },
];

function InteractiveArchitecture() {
  const [selectedComponent, setSelectedComponent] = useState<string | null>(null);
  const [revealedLayers, setRevealedLayers] = useState(1);
  const [terminalLine, setTerminalLine] = useState(0);
  const [isAutoRevealing, setIsAutoRevealing] = useState(true);

  // Auto-reveal layers one by one
  useEffect(() => {
    if (!isAutoRevealing) return;
    if (revealedLayers >= archLayers.length) {
      setTimeout(() => {
        setIsAutoRevealing(false);
      }, 0);
      return;
    }
    const timer = window.setTimeout(() => {
      setRevealedLayers((prev) => prev + 1);
    }, 600);
    return () => window.clearTimeout(timer);
  }, [revealedLayers, isAutoRevealing]);

  // Cycle terminal commands
  useEffect(() => {
    const timer = window.setInterval(() => {
      setTerminalLine((prev) => (prev + 1) % terminalCommands.length);
    }, 3000);
    return () => window.clearInterval(timer);
  }, []);

  const handleComponentClick = useCallback((compId: string) => {
    setSelectedComponent((prev) => (prev === compId ? null : compId));
  }, []);

  const handleRevealAll = useCallback(() => {
    setRevealedLayers(archLayers.length);
    setTimeout(() => {
      setIsAutoRevealing(false);
    }, 0);
  }, []);

  // Find the selected component's full data
  const selectedData = selectedComponent
    ? archLayers
        .flatMap((l) => l.components)
        .find((c) => c.id === selectedComponent)
    : null;

  const selectedLayerData = selectedComponent
    ? archLayers.find((l) => l.components.some((c) => c.id === selectedComponent))
    : null;

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glow effects */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-violet-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-rose-500/5 rounded-full blur-3xl pointer-events-none" />

      {/* Inline keyframes */}
      <style>{`
        @keyframes archPulse {
          0%, 100% { opacity: 0.3; }
          50% { opacity: 0.7; }
        }
        @keyframes archDash {
          to { stroke-dashoffset: -16; }
        }
        @keyframes termBlink {
          0%, 100% { opacity: 1; }
          50% { opacity: 0; }
        }
        @keyframes healthPulse {
          0%, 100% { transform: scale(1); opacity: 0.8; }
          50% { transform: scale(1.5); opacity: 0.4; }
        }
      `}</style>

      <div className="p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30">
              <Layers className="h-4 w-4 text-primary" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-white">
                ACFS Architecture Explorer
              </h3>
              <p className="text-xs text-white/40">
                Click any component to explore
              </p>
            </div>
          </div>
          {revealedLayers < archLayers.length && (
            <button
              onClick={handleRevealAll}
              className="px-3 py-1.5 rounded-lg bg-white/[0.04] border border-white/[0.08] text-xs text-white/50 hover:text-white/80 hover:bg-white/[0.08] transition duration-300"
            >
              Reveal All
            </button>
          )}
        </div>

        {/* Main layout: layers + detail panel side by side on desktop */}
        <div className="flex flex-col lg:flex-row gap-4">
          {/* ---- Left: Layered Architecture Diagram ---- */}
          <div className="flex-1 space-y-2">
            {archLayers.map((layer, layerIdx) => {
              const isRevealed = layerIdx < revealedLayers;

              return (
                <AnimatePresence key={layer.id}>
                  {isRevealed && (
                    <motion.div
                      initial={{ opacity: 0, y: 20, scale: 0.97 }}
                      animate={{ opacity: 1, y: 0, scale: 1 }}
                      transition={{
                        type: "spring",
                        stiffness: 200,
                        damping: 25,
                        delay: 0.05,
                      }}
                      className={`relative rounded-xl border ${layer.borderColor} ${layer.color} p-3 backdrop-blur-sm`}
                    >
                      {/* Layer label */}
                      <div className="flex items-center gap-2 mb-2.5">
                        <div className="flex h-6 w-6 items-center justify-center rounded-lg bg-white/[0.06] text-white/60">
                          {layer.icon}
                        </div>
                        <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
                          {layer.label}
                        </span>
                        <div className="flex-1 h-px bg-white/[0.06]" />
                        <span className="text-[10px] text-white/30 font-mono">
                          L{layerIdx + 1}
                        </span>
                      </div>

                      {/* Component nodes */}
                      <div className="grid grid-cols-3 gap-2">
                        {layer.components.map((comp) => {
                          const isSelected = selectedComponent === comp.id;
                          // Check if this component is a dependency of the selected one
                          const isDepOfSelected =
                            selectedData?.dependencies.includes(comp.id) ??
                            false;
                          // Check if selected is a dependency of this one
                          const selectedIsDep =
                            selectedComponent !== null &&
                            comp.dependencies.includes(selectedComponent);

                          const isHighlighted =
                            isSelected || isDepOfSelected || selectedIsDep;

                          return (
                            <motion.button
                              key={comp.id}
                              onClick={() => handleComponentClick(comp.id)}
                              whileHover={{ scale: 1.04, y: -2 }}
                              whileTap={{ scale: 0.97 }}
                              className={`relative flex flex-col items-center gap-1 p-2.5 rounded-lg border transition duration-300 text-center cursor-pointer ${
                                isSelected
                                  ? "border-primary/50 bg-primary/10 shadow-lg shadow-primary/5"
                                  : isHighlighted
                                    ? "border-white/20 bg-white/[0.06]"
                                    : "border-white/[0.06] bg-white/[0.02] hover:border-white/[0.15] hover:bg-white/[0.04]"
                              }`}
                            >
                              {/* Health indicator */}
                              <div className="absolute top-1.5 right-1.5">
                                <div
                                  className={`h-1.5 w-1.5 rounded-full ${
                                    comp.status === "active"
                                      ? "bg-emerald-400"
                                      : comp.status === "ready"
                                        ? "bg-amber-400"
                                        : "bg-white/20"
                                  }`}
                                />
                                {comp.status === "active" && (
                                  <div
                                    className="absolute inset-0 h-1.5 w-1.5 rounded-full bg-emerald-400"
                                    style={{
                                      animation:
                                        "healthPulse 2s ease-in-out infinite",
                                    }}
                                  />
                                )}
                              </div>

                              {/* Component name */}
                              <span className="text-[11px] font-medium text-white/80 leading-tight">
                                {comp.shortName}
                              </span>

                              {/* Connection indicator for highlighted deps */}
                              {isDepOfSelected && !isSelected && (
                                <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-3 h-0.5 rounded-full bg-primary/40" />
                              )}
                              {selectedIsDep && !isSelected && (
                                <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-3 h-0.5 rounded-full bg-violet-400/40" />
                              )}
                            </motion.button>
                          );
                        })}
                      </div>

                      {/* Connection lines between layers (decorative dashes) */}
                      {layerIdx < archLayers.length - 1 &&
                        layerIdx < revealedLayers - 1 && (
                          <div className="absolute -bottom-2 left-1/2 -translate-x-1/2 flex gap-1">
                            {[0, 1, 2].map((i) => (
                              <div
                                key={i}
                                className="w-0.5 h-2 rounded-full bg-white/10"
                              />
                            ))}
                          </div>
                        )}
                    </motion.div>
                  )}
                </AnimatePresence>
              );
            })}

            {/* Layer count indicator */}
            {revealedLayers < archLayers.length && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="flex items-center justify-center gap-2 py-3 text-xs text-white/30"
              >
                <Activity className="h-3 w-3" />
                <span>
                  {archLayers.length - revealedLayers} more layer
                  {archLayers.length - revealedLayers > 1 ? "s" : ""}{" "}
                  loading...
                </span>
              </motion.div>
            )}
          </div>

          {/* ---- Right: Detail panel + Mini terminal ---- */}
          <div className="lg:w-72 flex flex-col gap-3">
            {/* Detail panel */}
            <AnimatePresence mode="wait">
              {selectedData && selectedLayerData ? (
                <motion.div
                  key={selectedData.id}
                  initial={{ opacity: 0, x: 12, scale: 0.97 }}
                  animate={{ opacity: 1, x: 0, scale: 1 }}
                  exit={{ opacity: 0, x: -8, scale: 0.98 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  className="rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl p-4 space-y-3"
                >
                  {/* Component header */}
                  <div className="flex items-start gap-2.5">
                    <div
                      className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${selectedLayerData.color} ${selectedLayerData.borderColor} border`}
                    >
                      {selectedLayerData.icon}
                    </div>
                    <div className="min-w-0">
                      <h4 className="text-sm font-semibold text-white leading-tight">
                        {selectedData.name}
                      </h4>
                      <span className="text-[10px] text-white/40 font-mono">
                        {selectedLayerData.label}
                      </span>
                    </div>
                  </div>

                  {/* Status badge */}
                  <div className="flex items-center gap-2">
                    <div
                      className={`flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] font-medium ${
                        selectedData.status === "active"
                          ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                          : selectedData.status === "ready"
                            ? "bg-amber-500/10 text-amber-400 border border-amber-500/20"
                            : "bg-white/5 text-white/40 border border-white/10"
                      }`}
                    >
                      <div
                        className={`h-1 w-1 rounded-full ${
                          selectedData.status === "active"
                            ? "bg-emerald-400"
                            : selectedData.status === "ready"
                              ? "bg-amber-400"
                              : "bg-white/30"
                        }`}
                      />
                      {selectedData.status === "active"
                        ? "Active"
                        : selectedData.status === "ready"
                          ? "Ready"
                          : "Standby"}
                    </div>
                  </div>

                  {/* Description */}
                  <p className="text-xs text-white/50 leading-relaxed">
                    {selectedData.description}
                  </p>

                  {/* Commands */}
                  <div>
                    <span className="text-[10px] font-semibold text-white/30 uppercase tracking-wider">
                      Commands
                    </span>
                    <div className="mt-1.5 space-y-1">
                      {selectedData.commands.map((cmd) => (
                        <div
                          key={cmd}
                          className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/30 border border-white/[0.06]"
                        >
                          <ChevronRight className="h-2.5 w-2.5 text-primary/60 shrink-0" />
                          <code className="text-[10px] font-mono text-white/60 truncate">
                            {cmd}
                          </code>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Dependencies */}
                  {selectedData.dependencies.length > 0 && (
                    <div>
                      <span className="text-[10px] font-semibold text-white/30 uppercase tracking-wider">
                        Depends on
                      </span>
                      <div className="mt-1.5 flex flex-wrap gap-1">
                        {selectedData.dependencies.map((depId) => {
                          const dep = archLayers
                            .flatMap((l) => l.components)
                            .find((c) => c.id === depId);
                          return (
                            <button
                              key={depId}
                              onClick={() => handleComponentClick(depId)}
                              className="px-2 py-0.5 rounded-md bg-white/[0.04] border border-white/[0.08] text-[10px] text-white/50 hover:text-white/80 hover:bg-white/[0.08] transition duration-200 cursor-pointer"
                            >
                              {dep?.shortName ?? depId}
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  )}
                </motion.div>
              ) : (
                <motion.div
                  key="empty"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="rounded-xl border border-dashed border-white/[0.06] bg-white/[0.01] p-6 flex flex-col items-center justify-center text-center"
                >
                  <HardDrive className="h-6 w-6 text-white/15 mb-2" />
                  <p className="text-xs text-white/30">
                    Select a component to see details, commands, and
                    dependencies
                  </p>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Mini terminal */}
            <div className="rounded-xl border border-white/[0.08] bg-black/40 backdrop-blur-xl overflow-hidden">
              {/* Terminal chrome */}
              <div className="flex items-center gap-1.5 px-3 py-2 border-b border-white/[0.06]">
                <div className="h-2 w-2 rounded-full bg-red-500/60" />
                <div className="h-2 w-2 rounded-full bg-amber-500/60" />
                <div className="h-2 w-2 rounded-full bg-emerald-500/60" />
                <span className="ml-2 text-[10px] text-white/30 font-mono">
                  terminal
                </span>
              </div>
              {/* Terminal content */}
              <div className="p-3 font-mono text-[11px] space-y-1.5 min-h-[80px]">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={terminalLine}
                    initial={{ opacity: 0, y: 6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -6 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  >
                    <div className="flex items-center gap-1">
                      <span className="text-emerald-400">
                        {terminalCommands[terminalLine].prompt}
                      </span>
                      <span className="text-white/30">$</span>
                      <span className="text-white/80">
                        {terminalCommands[terminalLine].cmd}
                      </span>
                      <span
                        className="inline-block w-1.5 h-3.5 bg-primary/60 ml-0.5"
                        style={{
                          animation: "termBlink 1s step-end infinite",
                        }}
                      />
                    </div>
                    <div className="mt-1 text-white/40 pl-1">
                      {terminalCommands[terminalLine].output}
                    </div>
                  </motion.div>
                </AnimatePresence>
              </div>
            </div>

            {/* Connection legend */}
            <div className="rounded-xl border border-white/[0.06] bg-white/[0.01] p-3">
              <span className="text-[10px] font-semibold text-white/30 uppercase tracking-wider">
                Status Key
              </span>
              <div className="mt-2 space-y-1.5">
                <div className="flex items-center gap-2">
                  <div className="relative h-2 w-2">
                    <div className="absolute inset-0 h-2 w-2 rounded-full bg-emerald-400" />
                    <div
                      className="absolute inset-0 h-2 w-2 rounded-full bg-emerald-400"
                      style={{
                        animation: "healthPulse 2s ease-in-out infinite",
                      }}
                    />
                  </div>
                  <span className="text-[10px] text-white/40">
                    Active - running and healthy
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="h-2 w-2 rounded-full bg-amber-400" />
                  <span className="text-[10px] text-white/40">
                    Ready - installed, needs auth
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="h-2 w-2 rounded-full bg-white/20" />
                  <span className="text-[10px] text-white/40">
                    Standby - available if needed
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Data flow visualization (bottom) */}
        <div className="mt-4 pt-4 border-t border-white/[0.06]">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-6">
              <DataFlowArrow
                from="Your Laptop"
                to="SSH Tunnel"
                color="text-sky-400"
              />
              <DataFlowArrow
                from="SSH Tunnel"
                to="tmux"
                color="text-violet-400"
              />
              <DataFlowArrow
                from="tmux"
                to="Agents"
                color="text-amber-400"
              />
              <DataFlowArrow from="NTM" to="All Agents" color="text-rose-400" />
            </div>
            <div className="flex items-center gap-1.5 text-[10px] text-white/25">
              <Lock className="h-3 w-3" />
              <span>End-to-end encrypted</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// Small data flow arrow component used in bottom bar
function DataFlowArrow({
  from,
  to,
  color,
}: {
  from: string;
  to: string;
  color: string;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-[10px] text-white/40">{from}</span>
      <div className="flex items-center gap-0.5">
        <div className={`w-4 h-px ${color} opacity-40`} />
        <ChevronRight className={`h-2.5 w-2.5 ${color} opacity-40`} />
      </div>
      <span className="text-[10px] text-white/40">{to}</span>
    </div>
  );
}

