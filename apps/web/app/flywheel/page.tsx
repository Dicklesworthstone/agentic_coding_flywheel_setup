"use client";

import Link from "next/link";
import { useState } from "react";
import {
  ArrowLeft,
  Terminal,
  ChevronRight,
  Zap,
  GitBranch,
  Cpu,
  Layers,
  Workflow,
  ExternalLink,
  LayoutGrid,
  ShieldAlert,
  ShieldCheck,
  Mail,
  Bug,
  Brain,
  Search,
  KeyRound,
  Star,
  Copy,
  Check,
  Sparkles,
  Clock,
  Users,
  Quote,
  Rocket,
  Shield,
  Code2,
  ChevronDown,
  ArrowRight,
  GitMerge,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import FlywheelVisualization from "@/components/flywheel-visualization";
import {
  flywheelTools,
  workflowScenarios,
  agentPrompts,
  synergyExplanations,
  type FlywheelTool,
  type WorkflowScenario,
  type AgentPrompt,
} from "@/lib/flywheel";

// ============================================================
// ICON MAPPING
// ============================================================

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  LayoutGrid,
  ShieldAlert,
  ShieldCheck,
  Mail,
  GitBranch,
  GitMerge,
  Bug,
  Brain,
  Search,
  KeyRound,
};

// ============================================================
// HERO SECTION
// ============================================================

function HeroSection() {
  return (
    <section className="relative overflow-hidden">
      {/* Background effects */}
      <div className="absolute inset-0 bg-gradient-hero" />
      <div className="absolute inset-0 bg-grid-pattern opacity-20" />
      <div className="pointer-events-none absolute left-1/4 top-1/4 h-[500px] w-[500px] rounded-full bg-primary/10 blur-[120px]" />
      <div className="pointer-events-none absolute right-1/4 bottom-1/4 h-[400px] w-[400px] rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[100px]" />

      <div className="relative z-10 mx-auto max-w-7xl px-6 pt-16 pb-20 lg:pt-24 lg:pb-28">
        {/* Badge */}
        <div
          className="mb-6 inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-4 py-2 opacity-0 animate-slide-up"
          style={{ animationDelay: "0.1s", animationFillMode: "forwards" }}
        >
          <Sparkles className="h-4 w-4 text-primary" />
          <span className="text-sm font-medium text-primary">
            8+ projects • 6+ agents • Autonomous progress
          </span>
        </div>

        {/* Main headline */}
        <h1
          className="max-w-4xl font-mono text-3xl font-bold leading-[1.15] tracking-tight sm:text-4xl lg:text-5xl xl:text-6xl opacity-0 animate-slide-up"
          style={{ animationDelay: "0.2s", animationFillMode: "forwards" }}
        >
          <span className="text-gradient-cosmic">Unheard-of Velocity</span>
          <br />
          <span className="text-foreground">in Complex Software</span>
        </h1>

        {/* Subtitle */}
        <p
          className="mt-6 max-w-2xl text-base leading-relaxed text-muted-foreground sm:text-lg lg:text-xl opacity-0 animate-slide-up"
          style={{ animationDelay: "0.3s", animationFillMode: "forwards" }}
        >
          Ten interconnected tools (plus utilities) that enable multiple AI agents to work in parallel,
          review each other&apos;s work, and make incredible autonomous progress,
          all <span className="text-foreground font-medium">while you&apos;re away</span>.
        </p>

        {/* Key insight quote */}
        <div
          className="mt-8 max-w-2xl rounded-2xl border border-border/30 bg-card/30 p-5 backdrop-blur-sm opacity-0 animate-slide-up"
          style={{ animationDelay: "0.4s", animationFillMode: "forwards" }}
        >
          <div className="flex gap-3">
            <Quote className="h-6 w-6 shrink-0 text-primary/50" />
            <div>
              <p className="text-sm leading-relaxed text-foreground italic sm:text-base">
                &ldquo;The magic isn&apos;t in any single tool. It&apos;s in how they work together.
                Using three tools is 10x better than using one.&rdquo;
              </p>
            </div>
          </div>
        </div>

        {/* Stats row */}
        <div
          className="mt-10 grid grid-cols-2 gap-4 sm:flex sm:flex-wrap sm:items-center sm:gap-6 lg:gap-8 opacity-0 animate-slide-up"
          style={{ animationDelay: "0.5s", animationFillMode: "forwards" }}
        >
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 sm:h-12 sm:w-12">
              <Users className="h-5 w-5 text-primary sm:h-6 sm:w-6" />
            </div>
            <div>
              <p className="text-xl font-bold text-foreground sm:text-2xl">6+</p>
              <p className="text-[12px] text-muted-foreground sm:text-sm">Parallel agents</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-500/10 sm:h-12 sm:w-12">
              <Layers className="h-5 w-5 text-emerald-400 sm:h-6 sm:w-6" />
            </div>
            <div>
              <p className="text-xl font-bold text-foreground sm:text-2xl">8+</p>
              <p className="text-[12px] text-muted-foreground sm:text-sm">Projects simultaneously</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-500/10 sm:h-12 sm:w-12">
              <Star className="h-5 w-5 text-amber-400 sm:h-6 sm:w-6" />
            </div>
            <div>
              <p className="text-xl font-bold text-foreground sm:text-2xl">2K+</p>
              <p className="text-[12px] text-muted-foreground sm:text-sm">GitHub stars</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-violet-500/10 sm:h-12 sm:w-12">
              <Clock className="h-5 w-5 text-violet-400 sm:h-6 sm:w-6" />
            </div>
            <div>
              <p className="text-xl font-bold text-foreground sm:text-2xl">3+ hrs</p>
              <p className="text-[12px] text-muted-foreground sm:text-sm">Autonomous work</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

// ============================================================
// WORKFLOW SECTION
// ============================================================

function WorkflowCard({ scenario, index }: { scenario: WorkflowScenario; index: number }) {
  const [isExpanded, setIsExpanded] = useState(false);

  return (
    <div
      className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 opacity-0 animate-slide-up"
      style={{ animationDelay: `${0.1 + index * 0.1}s`, animationFillMode: "forwards" }}
    >
      <div className="absolute -right-20 -top-20 h-40 w-40 rounded-full bg-primary/10 blur-3xl opacity-0 transition-opacity duration-500 group-hover:opacity-100" />

      <div className="relative p-5 lg:p-6">
        {/* Header */}
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h3 className="text-lg font-bold text-foreground">{scenario.title}</h3>
            <p className="mt-1 text-sm text-muted-foreground">{scenario.description}</p>
          </div>
          <div className="shrink-0 rounded-lg bg-primary/10 px-2.5 py-1 text-[12px] font-semibold text-primary">
            {scenario.timeframe}
          </div>
        </div>

        {/* Tools involved */}
        <div className="mb-4 flex flex-wrap gap-2">
          {scenario.steps.map((step, i) => {
            const tool = flywheelTools.find((t) => t.id === step.tool);
            if (!tool) return null;
            const Icon = iconMap[tool.icon] || Zap;
            return (
              <div
                key={i}
                className={`flex items-center gap-1.5 rounded-full bg-gradient-to-br ${tool.color} px-2.5 py-1`}
              >
                <Icon className="h-3 w-3 text-white" />
                <span className="text-xs font-medium text-white">{tool.shortName}</span>
              </div>
            );
          })}
        </div>

        {/* Expand toggle - 44px min height for touch targets */}
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          aria-expanded={isExpanded}
          className="flex w-full items-center justify-between rounded-lg bg-muted/30 px-4 py-3 min-h-[44px] text-left transition-colors hover:bg-muted/50"
        >
          <span className="text-sm font-medium text-foreground">
            {isExpanded ? "Hide steps" : "Show workflow steps"}
          </span>
          <ChevronDown
            className={`h-4 w-4 text-muted-foreground transition-transform ${isExpanded ? "rotate-180" : ""}`}
          />
        </button>

        {/* Expanded steps */}
        {isExpanded && (
          <div className="mt-4 space-y-2.5 animate-scale-in">
            {scenario.steps.map((step, i) => {
              const tool = flywheelTools.find((t) => t.id === step.tool);
              if (!tool) return null;
              const Icon = iconMap[tool.icon] || Zap;

              return (
                <div key={i} className="flex gap-3 rounded-xl bg-muted/20 p-3">
                  <div
                    className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${tool.color}`}
                  >
                    <Icon className="h-4 w-4 text-white" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-foreground">{step.action}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">→ {step.result}</p>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Outcome */}
        <div className="mt-4 rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-3">
          <div className="flex items-start gap-2">
            <Rocket className="h-4 w-4 shrink-0 text-emerald-400 mt-0.5" />
            <p className="text-sm font-medium text-emerald-300">{scenario.outcome}</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function WorkflowSection() {
  return (
    <section className="border-t border-border/30 bg-card/20 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        {/* Section header */}
        <div className="mb-12 max-w-3xl">
          <div className="mb-4 flex items-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[12px] font-bold uppercase tracking-[0.2em] text-primary">
              Real Workflows
            </span>
          </div>
          <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
            How the Tools Work Together
          </h2>
          <p className="mt-4 text-base text-muted-foreground lg:text-lg">
            These aren&apos;t hypothetical scenarios. These are actual daily workflows running across
            8+ projects with multiple AI agents.
          </p>
        </div>

        {/* Workflow cards */}
        <div className="grid gap-5 lg:grid-cols-2">
          {workflowScenarios.map((scenario, index) => (
            <WorkflowCard key={scenario.id} scenario={scenario} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

// ============================================================
// PROMPTS SECTION
// ============================================================

function PromptCard({ prompt, index }: { prompt: AgentPrompt; index: number }) {
  const [copied, setCopied] = useState(false);

  const copyPrompt = async () => {
    try {
      await navigator.clipboard.writeText(prompt.prompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for older browsers or when clipboard permission is denied
      const textArea = document.createElement("textarea");
      textArea.value = prompt.prompt;
      textArea.style.position = "fixed";
      textArea.style.opacity = "0";
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // Silent fail - user can manually copy
      }
      document.body.removeChild(textArea);
    }
  };

  const categoryColors: Record<string, string> = {
    exploration: "from-cyan-400 to-sky-500",
    review: "from-violet-400 to-purple-500",
    improvement: "from-pink-400 to-fuchsia-500",
    planning: "from-emerald-400 to-teal-500",
    execution: "from-amber-400 to-orange-500",
  };

  return (
    <div
      className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 opacity-0 animate-slide-up"
      style={{ animationDelay: `${0.1 + index * 0.05}s`, animationFillMode: "forwards" }}
    >
      <div className="p-5">
        {/* Header */}
        <div className="mb-3 flex items-start justify-between gap-3">
          <div>
            <div
              className={`mb-2 inline-flex rounded-full bg-gradient-to-r ${categoryColors[prompt.category]} px-2.5 py-1 text-[12px] font-semibold text-white`}
            >
              {prompt.category.charAt(0).toUpperCase() + prompt.category.slice(1)}
            </div>
            <h3 className="text-base font-bold text-foreground">{prompt.title}</h3>
          </div>
          <button
            onClick={copyPrompt}
            className="shrink-0 flex items-center justify-center min-w-[44px] min-h-[44px] rounded-lg bg-muted/50 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            title="Copy prompt"
          >
            {copied ? <Check className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4" />}
          </button>
        </div>

        {/* Prompt text */}
        <div className="rounded-xl bg-muted/30 p-3 font-mono text-[12px] leading-relaxed text-muted-foreground">
          <p className="line-clamp-3">{prompt.prompt}</p>
        </div>

        {/* When to use */}
        <p className="mt-3 text-[12px] text-muted-foreground">
          <span className="font-medium text-foreground">When: </span>
          {prompt.whenToUse}
        </p>

        {/* Best with tools */}
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <span className="text-[12px] text-muted-foreground">Best with:</span>
          {prompt.bestWith.map((toolId) => {
            const tool = flywheelTools.find((t) => t.id === toolId);
            if (!tool) return null;
            return (
              <span
                key={toolId}
                className="rounded-full bg-muted px-2 py-0.5 text-[12px] font-medium text-foreground"
              >
                {tool.shortName}
              </span>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function PromptsSection() {
  return (
    <section className="border-t border-border/30 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        {/* Section header */}
        <div className="mb-12 max-w-3xl">
          <div className="mb-4 flex items-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[12px] font-bold uppercase tracking-[0.2em] text-primary">
              Battle-Tested Prompts
            </span>
          </div>
          <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
            The Prompts That Power the Workflow
          </h2>
          <p className="mt-4 text-base text-muted-foreground lg:text-lg">
            Copy these prompts to your Stream Deck or command palette. Each takes under a second
            to execute with a single button press.
          </p>
        </div>

        {/* Prompts grid */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {agentPrompts.map((prompt, index) => (
            <PromptCard key={prompt.id} prompt={prompt} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

// ============================================================
// SYNERGY SECTION
// ============================================================

function SynergySection() {
  return (
    <section className="border-t border-border/30 bg-card/20 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        {/* Section header */}
        <div className="mb-12 text-center">
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[12px] font-bold uppercase tracking-[0.2em] text-primary">
              The Flywheel Effect
            </span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
            Using Three Tools is 10x Better Than One
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-base text-muted-foreground lg:text-lg">
            Each tool amplifies the others. The synergies compound over time.
          </p>
        </div>

        {/* Synergy cards */}
        <div className="grid gap-5 lg:grid-cols-2 xl:grid-cols-3">
          {synergyExplanations.map((synergy, index) => (
            <div
              key={synergy.title}
              className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-5 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 opacity-0 animate-slide-up"
              style={{ animationDelay: `${0.1 + index * 0.1}s`, animationFillMode: "forwards" }}
            >
              {/* Tools involved */}
              <div className="mb-4 flex items-center gap-2">
                {synergy.tools.map((toolId, i) => {
                  const tool = flywheelTools.find((t) => t.id === toolId);
                  if (!tool) return null;
                  const Icon = iconMap[tool.icon] || Zap;
                  return (
                    <div key={toolId} className="flex items-center">
                      {i > 0 && <span className="mx-1 text-muted-foreground">+</span>}
                      <div
                        className={`flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br ${tool.color}`}
                      >
                        <Icon className="h-4 w-4 text-white" />
                      </div>
                    </div>
                  );
                })}
                <div className="ml-auto rounded-lg bg-emerald-500/10 px-2.5 py-1 text-sm font-bold text-emerald-400">
                  {synergy.multiplier}
                </div>
              </div>

              {/* Title and description */}
              <h3 className="mb-2 text-base font-bold text-foreground">{synergy.title}</h3>
              <p className="text-sm text-muted-foreground">{synergy.description}</p>

              {/* Example */}
              <div className="mt-4 rounded-xl bg-muted/30 p-3">
                <p className="text-[12px] text-foreground italic">&ldquo;{synergy.example}&rdquo;</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ============================================================
// TOOLS GRID SECTION
// ============================================================

function ToolCard({ tool, index }: { tool: FlywheelTool; index: number }) {
  const Icon = iconMap[tool.icon] || Zap;
  const [copied, setCopied] = useState(false);

  const copyInstall = async () => {
    if (!tool.installCommand) return;

    try {
      await navigator.clipboard.writeText(tool.installCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for older browsers or when clipboard permission is denied
      const textArea = document.createElement("textarea");
      textArea.value = tool.installCommand;
      textArea.style.position = "fixed";
      textArea.style.opacity = "0";
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // Silent fail - user can manually copy
      }
      document.body.removeChild(textArea);
    }
  };

  return (
    <div
      className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 card-hover opacity-0 animate-slide-up"
      style={{ animationDelay: `${0.1 + index * 0.05}s`, animationFillMode: "forwards" }}
    >
      <div
        className={`absolute -right-20 -top-20 h-40 w-40 rounded-full opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-30 bg-gradient-to-br ${tool.color}`}
      />

      <div className="relative p-5">
        {/* Header */}
        <div className="mb-3 flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div
              className={`flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg ${tool.color}`}
            >
              <Icon className="h-5 w-5 text-white" />
            </div>
            <div>
              <h3 className="font-bold text-foreground">{tool.name}</h3>
              <p className="text-[12px] text-muted-foreground">{tool.tagline}</p>
            </div>
          </div>
          {tool.stars && (
            <div className="flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-1 text-xs font-semibold text-amber-400">
              <Star className="h-3 w-3 fill-current" />
              {tool.stars >= 1000 ? `${(tool.stars / 1000).toFixed(1)}K` : tool.stars}
            </div>
          )}
        </div>

        {/* Language badge */}
        <div className="mb-3">
          <span className="rounded-full bg-muted px-2 py-0.5 text-[12px] font-medium text-muted-foreground">
            {tool.language}
          </span>
        </div>

        {/* Description */}
        <p className="mb-3 text-sm text-muted-foreground line-clamp-2">{tool.description}</p>

        {/* Features */}
        <ul className="mb-3 space-y-1">
          {tool.features.slice(0, 2).map((feature, i) => (
            <li key={i} className="flex items-start gap-2 text-[12px] text-muted-foreground">
              <Check className="mt-0.5 h-3 w-3 shrink-0 text-primary" />
              <span className="line-clamp-1">{feature}</span>
            </li>
          ))}
        </ul>

        {/* Install command */}
        {tool.installCommand && (
          <div className="mb-3 flex items-center gap-2 rounded-lg bg-muted/50 p-2">
            <code className="flex-1 overflow-hidden text-ellipsis whitespace-nowrap font-mono text-[10px] text-muted-foreground">
              {tool.installCommand.length > 60
                ? tool.installCommand.slice(0, 60) + "..."
                : tool.installCommand}
            </code>
            <button
              onClick={copyInstall}
              className="shrink-0 flex items-center justify-center min-w-[44px] min-h-[44px] -my-2 rounded text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            >
              {copied ? <Check className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4" />}
            </button>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-2">
          <Button asChild size="sm" variant="outline" className="flex-1 h-11 text-xs">
            <a href={tool.href} target="_blank" rel="noopener noreferrer">
              GitHub
              <ExternalLink className="ml-1 h-3 w-3" />
            </a>
          </Button>
          {tool.demoUrl && (
            <Button asChild size="sm" variant="ghost" className="h-11 text-xs">
              <a href={tool.demoUrl} target="_blank" rel="noopener noreferrer">
                Demo
              </a>
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

function ToolsSection() {
  return (
    <section className="border-t border-border/30 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        {/* Section header */}
        <div className="mb-12 text-center">
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[12px] font-bold uppercase tracking-[0.2em] text-primary">
              The Complete Stack
            </span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
            All Ten Flywheel Tools
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-base text-muted-foreground lg:text-lg">
            Each tool installs in under 30 seconds. Written in Go, Rust, TypeScript, Python, and Bash.
          </p>
        </div>

        {/* Tools grid */}
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {flywheelTools.map((tool, index) => (
            <ToolCard key={tool.id} tool={tool} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

// ============================================================
// PHILOSOPHY SECTION
// ============================================================

function PhilosophySection() {
  const items = [
    {
      icon: Code2,
      title: "Unix Philosophy",
      description: "Each tool does one thing well. They compose through JSON, MCP, and Git.",
      color: "from-cyan-400 to-sky-500",
    },
    {
      icon: Cpu,
      title: "Agent-First",
      description: "Every tool has --robot mode. Designed for AI agents to call programmatically.",
      color: "from-violet-400 to-purple-500",
    },
    {
      icon: Workflow,
      title: "Self-Reinforcing",
      description: "The flywheel effect: each tool makes the others more powerful.",
      color: "from-emerald-400 to-teal-500",
    },
    {
      icon: Shield,
      title: "Battle-Tested",
      description: "Born from daily use with 3+ AI agents on production codebases.",
      color: "from-amber-400 to-orange-500",
    },
  ];

  return (
    <section className="border-t border-border/30 bg-card/20 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        {/* Section header */}
        <div className="mb-12 text-center">
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[12px] font-bold uppercase tracking-[0.2em] text-primary">
              Design Philosophy
            </span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
            Built From Daily Experience
          </h2>
        </div>

        {/* Philosophy cards */}
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {items.map((item, index) => (
            <div
              key={item.title}
              className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-5 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 opacity-0 animate-slide-up"
              style={{ animationDelay: `${0.1 + index * 0.1}s`, animationFillMode: "forwards" }}
            >
              <div
                className={`absolute -right-20 -top-20 h-40 w-40 rounded-full opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-30 bg-gradient-to-br ${item.color}`}
              />
              <div className="relative">
                <div className={`mb-4 inline-flex rounded-xl p-3 bg-gradient-to-br ${item.color}`}>
                  <item.icon className="h-5 w-5 text-white" />
                </div>
                <h3 className="mb-2 text-base font-bold text-foreground">{item.title}</h3>
                <p className="text-sm text-muted-foreground">{item.description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ============================================================
// CTA SECTION
// ============================================================

function CTASection() {
  return (
    <section className="border-t border-border/30 py-16 lg:py-24">
      <div className="mx-auto max-w-7xl px-6">
        <div className="relative overflow-hidden rounded-2xl border border-primary/30 bg-gradient-to-br from-primary/10 via-card/50 to-card/30 p-8 text-center backdrop-blur-sm lg:rounded-3xl lg:p-12">
          <div className="absolute left-1/4 top-1/4 h-48 w-48 rounded-full bg-primary/10 blur-[80px]" />
          <div className="absolute right-1/4 bottom-1/4 h-36 w-36 rounded-full bg-[oklch(0.7_0.2_330/0.1)] blur-[60px]" />

          <div className="relative z-10">
            <h2 className="font-mono text-2xl font-bold tracking-tight text-foreground sm:text-3xl lg:text-4xl">
              Ready to 10x Your Velocity?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-base text-muted-foreground lg:text-lg">
              The Agent Flywheel installer sets up all flywheel tools automatically.
              From zero to multi-agent workflows in 30 minutes.
            </p>

            <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <Button asChild size="lg" className="bg-primary text-primary-foreground">
                <Link href="/wizard/os-selection">
                  Start the Wizard
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline">
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <GitBranch className="mr-2 h-4 w-4" />
                  View Source
                </a>
              </Button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

// ============================================================
// MAIN PAGE
// ============================================================

export default function FlywheelPage() {
  return (
    <div className="relative min-h-screen bg-background overflow-x-hidden">
      {/* Navigation */}
      <nav className="relative z-20 mx-auto flex max-w-7xl items-center justify-between px-6 py-4 lg:py-6">
        <div className="flex items-center gap-4">
          <Button asChild variant="ghost" size="default" className="h-11 text-muted-foreground hover:text-foreground">
            <Link href="/">
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Link>
          </Button>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20 lg:h-9 lg:w-9">
            <Terminal className="h-4 w-4 text-primary lg:h-5 lg:w-5" />
          </div>
          <span className="font-mono text-base font-bold tracking-tight lg:text-lg">Agent Flywheel</span>
        </div>
        <div className="flex items-center gap-4">
          <Button asChild size="default" variant="outline" className="h-11 border-primary/30 hover:bg-primary/10">
            <Link href="/wizard/os-selection">
              Get Started
              <ChevronRight className="ml-1 h-4 w-4" />
            </Link>
          </Button>
        </div>
      </nav>

      {/* Main content */}
      <main>
        <HeroSection />

        {/* Interactive Flywheel Visualization */}
        <section className="mx-auto max-w-7xl px-6 py-16 lg:py-24">
          <FlywheelVisualization />
        </section>

        <WorkflowSection />
        <PromptsSection />
        <SynergySection />
        <ToolsSection />
        <PhilosophySection />
        <CTASection />
      </main>

      {/* Footer */}
      <footer className="border-t border-border/30 py-10">
        <div className="mx-auto max-w-7xl px-6">
          <div className="flex flex-col items-center justify-between gap-5 sm:flex-row">
            <div className="flex items-center gap-2">
              <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/20">
                <Terminal className="h-3.5 w-3.5 text-primary" />
              </div>
              <span className="font-mono text-sm font-bold">Agent Flywheel</span>
            </div>

            <div className="flex items-center gap-3 text-sm text-muted-foreground">
              <a
                href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center min-h-[44px] px-2 transition-colors hover:text-foreground"
              >
                GitHub
              </a>
              <Link href="/" className="flex items-center min-h-[44px] px-2 transition-colors hover:text-foreground">
                Home
              </Link>
              <Link href="/wizard/os-selection" className="flex items-center min-h-[44px] px-2 transition-colors hover:text-foreground">
                Get Started
              </Link>
            </div>

            <p className="text-[12px] text-muted-foreground">Built for the agentic coding community</p>
          </div>
        </div>
      </footer>
    </div>
  );
}
