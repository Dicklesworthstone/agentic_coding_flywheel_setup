"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import {
  ArrowRight,
  Terminal,
  Rocket,
  ShieldCheck,
  Zap,
  GitBranch,
  Cpu,
  Clock,
  Sparkles,
  ChevronRight,
  MessageCircle,
  Check,
  X,
  Server,
  Bot,
  Coins,
  Laptop,
  Cloud,
  Moon,
  BookOpen,
} from "lucide-react";
import { motion, AnimatePresence } from "@/components/motion";
import { Button } from "@/components/ui/button";
import { Jargon } from "@/components/jargon";
import { springs, fadeUp, staggerContainer, fadeScale } from "@/components/motion";
import { useScrollReveal, staggerDelay } from "@/lib/hooks/useScrollReveal";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

// Animated terminal lines
const TERMINAL_LINES = [
  { type: "command", text: "curl -fsSL https://agent-flywheel.com/install | bash" },
  { type: "output", text: "▸ Detecting Ubuntu 24.04... ✓" },
  { type: "output", text: "▸ Installing zsh + oh-my-zsh + powerlevel10k..." },
  { type: "output", text: "▸ Installing bun, uv, rust, go..." },
  { type: "output", text: "▸ Installing Claude Code, Codex CLI, Gemini CLI..." },
  { type: "output", text: "▸ Configuring tmux, ripgrep, lazygit..." },
  { type: "output", text: "▸ Setting up Dicklesworthstone stack..." },
  { type: "success", text: "✓ Setup complete! Run 'onboard' to get started." },
];

function AnimatedTerminal() {
  const [visibleLines, setVisibleLines] = useState(0);
  const [cursorVisible, setCursorVisible] = useState(true);
  const [isMobile, setIsMobile] = useState(false);
  const prefersReducedMotion = useReducedMotion();

  // Detect mobile to simplify animations
  useEffect(() => {
    const checkMobile = () => {
      setIsMobile(window.matchMedia("(max-width: 768px)").matches);
    };
    checkMobile();
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  }, []);

  useEffect(() => {
    const interval = setInterval(() => {
      setVisibleLines((prev) => {
        if (prev >= TERMINAL_LINES.length) {
          return 1; // Reset to loop
        }
        return prev + 1;
      });
    }, 800);

    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    const cursorInterval = setInterval(() => {
      setCursorVisible((prev) => !prev);
    }, 530);
    return () => clearInterval(cursorInterval);
  }, []);

  // On mobile or reduced motion, skip animations entirely
  const skipAnimations = prefersReducedMotion || isMobile;

  return (
    <motion.div
      className="terminal-window shadow-2xl"
      initial={skipAnimations ? {} : { opacity: 0, scale: 0.95, y: 20 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={springs.smooth}
    >
      <div className="terminal-header">
        <div className="terminal-dot terminal-dot-red" />
        <div className="terminal-dot terminal-dot-yellow" />
        <div className="terminal-dot terminal-dot-green" />
        <span className="ml-3 font-mono text-xs text-muted-foreground">
          ubuntu@vps ~
        </span>
      </div>
      {/* Fixed height container to prevent layout shifts */}
      <div className="terminal-content h-[280px] overflow-hidden">
        {/* Use simple rendering on mobile to prevent jank */}
        {skipAnimations ? (
          // Static render without AnimatePresence on mobile
          TERMINAL_LINES.slice(0, visibleLines).map((line, i) => (
            <div key={`${line.text}-${i}`} className="terminal-line mb-2">
              {line.type === "command" && (
                <>
                  <span className="terminal-prompt">$</span>
                  <span className="terminal-command">{line.text}</span>
                </>
              )}
              {line.type === "output" && (
                <span className="terminal-output">{line.text}</span>
              )}
              {line.type === "success" && (
                <span className="text-[oklch(0.72_0.19_145)]">{line.text}</span>
              )}
            </div>
          ))
        ) : (
          // Animated render on desktop
          <AnimatePresence mode="sync">
            {TERMINAL_LINES.slice(0, visibleLines).map((line, i) => (
              <motion.div
                key={`${line.text}-${i}`}
                className="terminal-line mb-2"
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ ...springs.snappy, delay: i * 0.05 }}
              >
                {line.type === "command" && (
                  <>
                    <span className="terminal-prompt">$</span>
                    <span className="terminal-command">{line.text}</span>
                  </>
                )}
                {line.type === "output" && (
                  <span className="terminal-output">{line.text}</span>
                )}
                {line.type === "success" && (
                  <span className="text-[oklch(0.72_0.19_145)]">{line.text}</span>
                )}
              </motion.div>
            ))}
          </AnimatePresence>
        )}
        {visibleLines <= TERMINAL_LINES.length && (
          <div className="terminal-line">
            <span className="terminal-prompt">$</span>
            {skipAnimations ? (
              <span className="terminal-cursor" style={{ opacity: cursorVisible ? 1 : 0 }} />
            ) : (
              <motion.span
                className="terminal-cursor"
                animate={{ opacity: cursorVisible ? 1 : 0 }}
                transition={{ duration: 0.1 }}
              />
            )}
          </div>
        )}
      </div>
    </motion.div>
  );
}

interface FeatureCardProps {
  icon: React.ReactNode;
  title: string;
  description: React.ReactNode;
  gradient: string;
  index: number;
}

function FeatureCard({ icon, title, description, gradient, index }: FeatureCardProps) {
  return (
    <motion.div
      className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition-all duration-300 hover:border-primary/30 active:scale-[0.98] active:bg-card/70"
      variants={fadeUp}
      whileHover={{ y: -4, boxShadow: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)" }}
      transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
    >
      {/* Gradient glow on hover */}
      <motion.div
        className={`absolute -right-20 -top-20 h-40 w-40 rounded-full blur-3xl ${gradient}`}
        initial={{ opacity: 0 }}
        whileHover={{ opacity: 0.3 }}
        transition={springs.smooth}
      />

      <div className="relative z-10">
        <motion.div
          className="mb-4 inline-flex rounded-xl bg-primary/10 p-3 text-primary"
          whileHover={{ scale: 1.1, rotate: 5 }}
          transition={springs.snappy}
        >
          {icon}
        </motion.div>
        <h3 className="mb-2 text-lg font-semibold tracking-tight">{title}</h3>
        <p className="text-sm leading-relaxed text-muted-foreground">{description}</p>
      </div>
    </motion.div>
  );
}

const FEATURES = [
  {
    icon: <Rocket className="h-6 w-6" />,
    title: "One-liner Install",
    description: (
      <>
        A single command transforms your <Jargon term="vps">VPS</Jargon>. No manual configuration, no dependency hell.
      </>
    ),
    gradient: "bg-[oklch(0.75_0.18_195)]",
  },
  {
    icon: <Cpu className="h-6 w-6" />,
    title: "Three AI Agents",
    description: (
      <>
        <Jargon term="claude-code">Claude Code</Jargon>, <Jargon term="codex">Codex CLI</Jargon>, and{" "}
        <Jargon term="gemini-cli">Gemini CLI</Jargon>, all configured with optimal settings for coding.
      </>
    ),
    gradient: "bg-[oklch(0.7_0.2_330)]",
  },
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Idempotent & Safe",
    description: (
      <>
        Re-run anytime. <Jargon term="idempotent">Idempotent</Jargon> phases resume on failure.{" "}
        <Jargon term="sha256">SHA256</Jargon> verified installers.
      </>
    ),
    gradient: "bg-[oklch(0.72_0.19_145)]",
  },
  {
    icon: <Zap className="h-6 w-6" />,
    title: "Vibe Mode",
    description: (
      <>
        Passwordless <Jargon term="sudo">sudo</Jargon> with dangerous flags enabled for maximum velocity on throwaway{" "}
        <Jargon term="vps">VPS</Jargon> environments.
      </>
    ),
    gradient: "bg-[oklch(0.78_0.16_75)]",
  },
  {
    icon: <Terminal className="h-6 w-6" />,
    title: "Modern Shell",
    description: (
      <>
        <Jargon term="zsh">zsh</Jargon> + <Jargon term="oh-my-zsh">oh-my-zsh</Jargon> +{" "}
        <Jargon term="powerlevel10k">powerlevel10k</Jargon> with <Jargon term="lsd">lsd</Jargon>,{" "}
        <Jargon term="atuin">atuin</Jargon>, <Jargon term="fzf">fzf</Jargon>, and{" "}
        <Jargon term="zoxide">zoxide</Jargon>; developer UX perfected.
      </>
    ),
    gradient: "bg-[oklch(0.65_0.18_290)]",
  },
  {
    icon: <Clock className="h-6 w-6" />,
    title: "Interactive Tutorial",
    description: (
      <>
        Run &apos;onboard&apos; after setup for guided lessons from <Jargon term="linux">Linux</Jargon> basics to full{" "}
        <Jargon term="agentic">agentic</Jargon> workflows.{" "}
        <Link href="/learn/welcome" className="inline-flex items-center gap-1 text-primary hover:underline">
          Preview lessons <BookOpen className="h-3 w-3" />
        </Link>
      </>
    ),
    gradient: "bg-[oklch(0.75_0.18_195)]",
  },
];

function FeaturesSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section ref={ref as React.RefObject<HTMLElement>} className="mx-auto max-w-7xl px-6 py-24">
      <motion.div
        className="mb-12 text-center"
        initial={{ opacity: 0, y: 20 }}
        animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
        transition={springs.smooth}
      >
        <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight">
          Everything You Need
        </h2>
        <p className="mx-auto max-w-2xl text-muted-foreground">
          A single <Jargon term="curl">curl</Jargon> command installs and configures your complete{" "}
          <Jargon term="agentic">agentic</Jargon> coding environment
        </p>
      </motion.div>

      <motion.div
        className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3"
        variants={staggerContainer}
        initial="hidden"
        animate={isInView ? "visible" : "hidden"}
      >
        {FEATURES.map((feature, i) => (
          <FeatureCard key={feature.title} {...feature} index={i} />
        ))}
      </motion.div>
    </section>
  );
}

const FLYWHEEL_TOOLS = [
  { name: "NTM", color: "from-sky-400 to-blue-500", desc: "Agent Orchestration" },
  { name: "Mail", color: "from-violet-400 to-purple-500", desc: "Coordination" },
  { name: "UBS", color: "from-rose-400 to-red-500", desc: "Bug Scanning" },
  { name: "BV", color: "from-emerald-400 to-teal-500", desc: "Task Graph" },
  { name: "CASS", color: "from-cyan-400 to-sky-500", desc: "Search" },
  { name: "CM", color: "from-pink-400 to-fuchsia-500", desc: "Memory" },
  { name: "CAAM", color: "from-amber-400 to-orange-500", desc: "Auth" },
  { name: "SLB", color: "from-yellow-400 to-amber-500", desc: "Safety" },
];

function FlywheelSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 bg-card/20 py-24">
      <div className="mx-auto max-w-7xl px-6">
        <motion.div
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[11px] font-bold uppercase tracking-[0.25em] text-primary">Ecosystem</span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight">
            The <Jargon term="agentic">Agentic</Jargon> Coding <Jargon term="flywheel">Flywheel</Jargon>
          </h2>
          <p className="mx-auto max-w-2xl text-muted-foreground">
            Eight interconnected tools that transform multi-<Jargon term="ai-agents">agent</Jargon> workflows.
            Each tool enhances the others.
          </p>
        </motion.div>

        {/* Tool preview grid */}
        <motion.div
          className="grid grid-cols-2 gap-4 mb-8 xs:grid-cols-4 sm:grid-cols-8"
          variants={staggerContainer}
          initial="hidden"
          animate={isInView ? "visible" : "hidden"}
        >
          {FLYWHEEL_TOOLS.map((tool, i) => (
            <motion.div
              key={tool.name}
              className="flex flex-col items-center gap-2"
              variants={fadeScale}
              transition={{ delay: staggerDelay(i, 0.06) }}
              whileHover={{ scale: 1.1, y: -4 }}
            >
              <motion.div
                className={`flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${tool.color} shadow-lg`}
                whileHover={{ rotate: [0, -5, 5, 0] }}
                transition={{ duration: 0.4 }}
              >
                <span className="text-xs font-bold text-white">{tool.name}</span>
              </motion.div>
              <span className="text-[10px] text-muted-foreground text-center">{tool.desc}</span>
            </motion.div>
          ))}
        </motion.div>

        <motion.div
          className="flex justify-center"
          initial={{ opacity: 0, y: 10 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }}
          transition={{ ...springs.smooth, delay: 0.5 }}
        >
          <Button asChild size="lg" variant="outline" className="border-primary/30 hover:bg-primary/10">
            <Link href="/flywheel">
              Explore the Flywheel
              <ChevronRight className="ml-2 h-4 w-4" />
            </Link>
          </Button>
        </motion.div>
      </div>
    </section>
  );
}

const WORKFLOW_STEPS = [
  "Choose OS",
  "Install Terminal",
  "Generate SSH Key",
  "Rent VPS",
  "Create Instance",
  "SSH Connect",
  "Set Up Accounts",
  "Pre-Flight Check",
  "Run Installer",
  "Reconnect",
  "Verify Key",
  "Status Check",
  "Launch Onboard",
];

function WorkflowStepsSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 bg-card/30 py-24">
      <div className="mx-auto max-w-7xl px-6">
        <motion.div
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight">
            {WORKFLOW_STEPS.length} Steps to Liftoff
          </h2>
          <p className="mx-auto max-w-2xl text-muted-foreground">
            The wizard guides you from &quot;I have a laptop&quot; to &quot;<Jargon term="ai-agents">AI agents</Jargon> are coding for me&quot;
          </p>
        </motion.div>

        {/* Horizontal scroll on mobile, wrap on desktop */}
        <div className="relative -mx-6 px-6 sm:mx-0 sm:px-0">
          <motion.div
            className="flex gap-3 overflow-x-auto pb-4 sm:flex-wrap sm:justify-center sm:overflow-visible sm:pb-0 scrollbar-hide"
            variants={staggerContainer}
            initial="hidden"
            animate={isInView ? "visible" : "hidden"}
          >
            {WORKFLOW_STEPS.map((step, i) => (
              <motion.div
                key={step}
                className="flex shrink-0 items-center gap-2 rounded-full border border-border/50 bg-card/50 px-4 py-2 text-sm transition-colors hover:border-primary/30 hover:bg-card active:scale-95"
                variants={fadeUp}
                transition={{ delay: staggerDelay(i, 0.05) }}
                whileHover={{ scale: 1.05, y: -2 }}
              >
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/20 text-xs font-medium text-primary">
                  {i + 1}
                </span>
                <span className="whitespace-nowrap text-foreground">{step}</span>
              </motion.div>
            ))}
          </motion.div>
        </div>

        <motion.div
          className="mt-12 flex justify-center"
          initial={{ opacity: 0, y: 10 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }}
          transition={{ ...springs.smooth, delay: 0.6 }}
        >
          <Button asChild size="lg" className="bg-primary text-primary-foreground">
            <Link href="/wizard/os-selection">
              Start Your Journey
              <ArrowRight className="ml-2 h-4 w-4" />
            </Link>
          </Button>
        </motion.div>
      </div>
    </section>
  );
}

function AboutSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 py-24">
      <div className="mx-auto max-w-4xl px-6">
        <motion.div
          className="text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          <div className="mb-6 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[11px] font-bold uppercase tracking-[0.25em] text-primary">About</span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>

          <h2 className="mb-6 font-mono text-3xl font-bold tracking-tight">
            Who Made This? Why Is It Free?
          </h2>
        </motion.div>

        <motion.div
          className="space-y-6 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={{ ...springs.smooth, delay: 0.1 }}
        >
          {/* Headshot with gradient ring */}
          <motion.div
            className="mx-auto flex items-center justify-center"
            whileHover={{ scale: 1.05 }}
            transition={springs.snappy}
          >
            <div className="relative">
              {/* Gradient ring */}
              <div className="absolute -inset-1 rounded-full bg-gradient-to-br from-[oklch(0.75_0.18_195)] via-[oklch(0.7_0.2_330)] to-[oklch(0.78_0.16_75)] opacity-75 blur-sm" />
              <div className="absolute -inset-1 rounded-full bg-gradient-to-br from-[oklch(0.75_0.18_195)] via-[oklch(0.7_0.2_330)] to-[oklch(0.78_0.16_75)]" />
              {/* Image container */}
              <div className="relative h-28 w-28 overflow-hidden rounded-full border-2 border-background sm:h-32 sm:w-32">
                <Image
                  src="/je_headshot.jpg"
                  alt="Jeffrey Emanuel"
                  fill
                  sizes="(max-width: 640px) 112px, 128px"
                  className="object-cover"
                  priority
                />
              </div>
              {/* Sparkle accent */}
              <div className="absolute -right-1 -top-1 flex h-6 w-6 items-center justify-center rounded-full bg-background shadow-lg">
                <Sparkles className="h-3.5 w-3.5 text-[oklch(0.78_0.16_75)]" />
              </div>
            </div>
          </motion.div>

          <div className="space-y-4 text-muted-foreground leading-relaxed">
            <p>
              I&apos;m{" "}
              <a
                href="https://jeffreyemanuel.com/"
                target="_blank"
                rel="noopener noreferrer"
                className="font-medium text-primary hover:underline"
              >
                Jeffrey Emanuel
              </a>
              , and I built this because I was being inundated with requests from friends,
              older relatives, and strangers on the internet asking me to help them get started
              with using AI for software development.
            </p>

            <p>
              I wanted <strong className="text-foreground">one resource</strong> I could point
              people to that would help them &quot;from soup to nuts&quot; in getting set up;
              even if they have almost no computer expertise, just motivation and desire.
            </p>

            <p>
              This is also a platform to share my suite of{" "}
              <strong className="text-foreground">
                totally free, <Jargon term="open-source">open-source</Jargon>{" "}
                <Jargon term="agentic">agentic</Jargon> coding tools
              </strong>.
              I originally built these for myself to move faster in my consulting work with
              Private Equity and Hedge Funds. Now I want to help others be more productive
              and creative too.
            </p>
          </div>

          <motion.div
            className="flex flex-wrap items-center justify-center gap-4 pt-4"
            initial={{ opacity: 0 }}
            animate={isInView ? { opacity: 1 } : { opacity: 0 }}
            transition={{ ...springs.smooth, delay: 0.3 }}
          >
            <a
              href="https://x.com/doodlestein"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-border/50 bg-card/50 px-4 py-2 text-sm text-muted-foreground transition-colors hover:border-primary/30 hover:text-foreground"
            >
              <MessageCircle className="h-4 w-4" />
              Follow me on X
            </a>
            <a
              href="https://github.com/Dicklesworthstone"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-border/50 bg-card/50 px-4 py-2 text-sm text-muted-foreground transition-colors hover:border-primary/30 hover:text-foreground"
            >
              <GitBranch className="h-4 w-4" />
              View my projects
            </a>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}

// "Why VPS?" Explainer Section
const WHY_VPS_ITEMS = [
  {
    icon: <Laptop className="h-6 w-6 text-white" />,
    title: "Not Your Laptop",
    description: "AI agents consume significant RAM and CPU. Running them locally drains your battery and slows everything down.",
    detail: "Each agent uses ~2GB RAM. With 10+ agents, you need 48-64GB—more than most laptops have.",
    gradient: "from-amber-400 to-orange-500",
  },
  {
    icon: <Cloud className="h-6 w-6 text-white" />,
    title: "Not AWS/GCP/Azure",
    description: "Cloud giants charge by the hour and make billing unpredictable. A dedicated VPS is simpler and cheaper.",
    detail: "A 64GB VPS costs ~$40-56/month flat. Equivalent cloud resources would cost 3-5x more.",
    gradient: "from-sky-400 to-blue-500",
  },
  {
    icon: <Moon className="h-6 w-6 text-white" />,
    title: "Works While You Sleep",
    description: "Your VPS runs 24/7. Queue up tasks before bed, wake up to completed code.",
    detail: "AI agents can refactor, test, and iterate autonomously—compounding progress overnight.",
    gradient: "from-violet-400 to-purple-500",
  },
];

function WhyVPSSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 py-24 relative overflow-hidden">
      <div className="pointer-events-none absolute -left-40 top-1/4 h-80 w-80 rounded-full bg-[oklch(0.75_0.18_195/0.08)] blur-[100px]" />
      <div className="pointer-events-none absolute -right-40 bottom-1/4 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[100px]" />

      <div className="mx-auto max-w-7xl px-6 relative">
        <motion.div
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[11px] font-bold uppercase tracking-[0.25em] text-primary">The Foundation</span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight sm:text-4xl">Why a VPS?</h2>
          <p className="mx-auto max-w-2xl text-muted-foreground">
            <Jargon term="agentic">Agentic</Jargon> workflows need dedicated compute. A <Jargon term="vps">VPS</Jargon> gives you a 24/7 server that&apos;s always ready.
          </p>
        </motion.div>

        <motion.div
          className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3"
          variants={staggerContainer}
          initial="hidden"
          animate={isInView ? "visible" : "hidden"}
        >
          {WHY_VPS_ITEMS.map((item, i) => (
            <motion.div
              key={item.title}
              className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition-all duration-300 hover:border-primary/30"
              variants={fadeUp}
              transition={{ delay: staggerDelay(i, 0.1) }}
              whileHover={{ y: -4, boxShadow: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)" }}
            >
              <motion.div
                className={`pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-gradient-to-br ${item.gradient} blur-3xl opacity-0 group-hover:opacity-20 transition-opacity`}
              />
              <div className="relative">
                <div className={`mb-4 inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${item.gradient}`}>
                  {item.icon}
                </div>
                <h3 className="mb-2 text-lg font-semibold">{item.title}</h3>
                <p className="mb-3 text-sm leading-relaxed text-muted-foreground">{item.description}</p>
                <p className="text-xs text-muted-foreground/70 italic">{item.detail}</p>
              </div>
            </motion.div>
          ))}
        </motion.div>

        <motion.div
          className="mt-10 text-center"
          initial={{ opacity: 0, y: 10 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }}
          transition={{ ...springs.smooth, delay: 0.4 }}
        >
          <p className="mb-4 text-muted-foreground">Ready to see if this approach is right for you?</p>
          <Button asChild variant="outline" className="border-primary/30 hover:bg-primary/10">
            <a href="#is-this-for-you">Check If This Is For You<ChevronRight className="ml-2 h-4 w-4" /></a>
          </Button>
        </motion.div>
      </div>
    </section>
  );
}

// "Is This For You?" Decision Section
const FOR_YOU_ITEMS = [
  { text: "You want AI to write real, production code for you", detail: "Full implementations, not just suggestions" },
  { text: "Sites like Lovable.dev are too limiting for what you want to build", detail: "You need full control and complexity" },
  { text: "You're willing to invest ~$500/month in AI subscriptions", detail: "Claude Max + ChatGPT Pro + VPS hosting" },
  { text: "You can follow step-by-step instructions", detail: "No coding experience required, just patience" },
];

const NOT_FOR_YOU_ITEMS = [
  { text: "You want a completely free solution", detail: "AI subscriptions have real costs" },
  { text: "You only want occasional AI help with snippets", detail: "This is for full agentic workflows" },
  { text: "You're looking for mobile-first development", detail: "This requires a desktop or laptop" },
  { text: "You need enterprise compliance out of the box", detail: "This is for individual developers" },
];

function IsThisForYouSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section id="is-this-for-you" ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 py-24 relative overflow-hidden">
      <div className="pointer-events-none absolute -left-40 top-1/2 h-80 w-80 -translate-y-1/2 rounded-full bg-[oklch(0.72_0.19_145/0.08)] blur-[100px]" />
      <div className="pointer-events-none absolute -right-40 top-1/2 h-80 w-80 -translate-y-1/2 rounded-full bg-[oklch(0.65_0.22_25/0.08)] blur-[100px]" />

      <div className="mx-auto max-w-7xl px-6 relative">
        <motion.div className="mb-12 text-center" initial={{ opacity: 0, y: 20 }} animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }} transition={springs.smooth}>
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[11px] font-bold uppercase tracking-[0.25em] text-primary">Honest Assessment</span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight sm:text-4xl">Is This For You?</h2>
          <p className="mx-auto max-w-2xl text-muted-foreground">We believe in radical transparency. Here&apos;s who will get the most value from this setup.</p>
        </motion.div>

        <div className="grid gap-6 lg:grid-cols-2 lg:gap-8">
          {/* For You Card */}
          <motion.div className="relative overflow-hidden rounded-2xl border border-[oklch(0.72_0.19_145/0.3)] bg-gradient-to-br from-[oklch(0.72_0.19_145/0.05)] to-transparent p-6 sm:p-8" initial={{ opacity: 0, x: -30 }} animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: -30 }} transition={{ ...springs.smooth, delay: 0.1 }}>
            <div className="pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-[oklch(0.72_0.19_145/0.15)] blur-3xl" />
            <div className="relative">
              <div className="mb-6 flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[oklch(0.72_0.19_145/0.2)]">
                  <Check className="h-5 w-5 text-[oklch(0.72_0.19_145)]" />
                </div>
                <h3 className="font-mono text-xl font-bold text-[oklch(0.72_0.19_145)]">This is for you if...</h3>
              </div>
              <ul className="space-y-4">
                {FOR_YOU_ITEMS.map((item, i) => (
                  <motion.li key={item.text} className="group flex gap-3" initial={{ opacity: 0, x: -10 }} animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: -10 }} transition={{ ...springs.smooth, delay: 0.15 + i * 0.05 }}>
                    <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[oklch(0.72_0.19_145/0.2)]">
                      <Check className="h-3 w-3 text-[oklch(0.72_0.19_145)]" />
                    </div>
                    <div>
                      <p className="font-medium text-foreground">{item.text}</p>
                      <p className="text-sm text-muted-foreground">{item.detail}</p>
                    </div>
                  </motion.li>
                ))}
              </ul>
            </div>
          </motion.div>

          {/* Not For You Card */}
          <motion.div className="relative overflow-hidden rounded-2xl border border-[oklch(0.65_0.22_25/0.3)] bg-gradient-to-br from-[oklch(0.65_0.22_25/0.05)] to-transparent p-6 sm:p-8" initial={{ opacity: 0, x: 30 }} animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: 30 }} transition={{ ...springs.smooth, delay: 0.1 }}>
            <div className="pointer-events-none absolute -left-20 -top-20 h-40 w-40 rounded-full bg-[oklch(0.65_0.22_25/0.15)] blur-3xl" />
            <div className="relative">
              <div className="mb-6 flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[oklch(0.65_0.22_25/0.2)]">
                  <X className="h-5 w-5 text-[oklch(0.65_0.22_25)]" />
                </div>
                <h3 className="font-mono text-xl font-bold text-[oklch(0.65_0.22_25)]">This is not for you if...</h3>
              </div>
              <ul className="space-y-4">
                {NOT_FOR_YOU_ITEMS.map((item, i) => (
                  <motion.li key={item.text} className="group flex gap-3" initial={{ opacity: 0, x: 10 }} animate={isInView ? { opacity: 1, x: 0 } : { opacity: 0, x: 10 }} transition={{ ...springs.smooth, delay: 0.15 + i * 0.05 }}>
                    <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[oklch(0.65_0.22_25/0.2)]">
                      <X className="h-3 w-3 text-[oklch(0.65_0.22_25)]" />
                    </div>
                    <div>
                      <p className="font-medium text-foreground">{item.text}</p>
                      <p className="text-sm text-muted-foreground">{item.detail}</p>
                    </div>
                  </motion.li>
                ))}
              </ul>
            </div>
          </motion.div>
        </div>

        <motion.div className="mt-10 text-center" initial={{ opacity: 0, y: 10 }} animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }} transition={{ ...springs.smooth, delay: 0.5 }}>
          <p className="mb-4 text-muted-foreground">Sound like you? Let&apos;s talk about the investment.</p>
          <Button asChild variant="outline" className="border-primary/30 hover:bg-primary/10">
            <a href="#pricing">See Full Cost Breakdown<ChevronRight className="ml-2 h-4 w-4" /></a>
          </Button>
        </motion.div>
      </div>
    </section>
  );
}

// "What Does This Cost?" Pricing Section
const PRICING_ITEMS = [
  { name: "Cloud VPS", price: "$40–56", period: "/month", description: "64GB RAM Ubuntu server (Contabo, OVH)", icon: Server, gradient: "from-sky-400 to-blue-500", note: "64GB RAM for 10+ agents" },
  { name: "Claude Max", price: "$200", period: "/month", description: "Anthropic's Claude Code CLI", icon: Bot, gradient: "from-amber-400 to-orange-500", note: "$400 for power users (2 accounts)" },
  { name: "ChatGPT Pro", price: "$200", period: "/month", description: "ChatGPT 5.2 Pro for extended thinking planning", icon: Cpu, gradient: "from-emerald-400 to-teal-500", note: "Essential for plan documents" },
];

function WhatDoesThisCostSection() {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  return (
    <section id="pricing" ref={ref as React.RefObject<HTMLElement>} className="border-t border-border/30 bg-card/20 py-24 relative overflow-hidden">
      <div className="pointer-events-none absolute inset-0 bg-grid-pattern opacity-20" />

      <div className="mx-auto max-w-7xl px-6 relative">
        <motion.div className="mb-12 text-center" initial={{ opacity: 0, y: 20 }} animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }} transition={springs.smooth}>
          <div className="mb-4 flex items-center justify-center gap-3">
            <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
            <span className="text-[11px] font-bold uppercase tracking-[0.25em] text-primary">Investment</span>
            <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
          </div>
          <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight sm:text-4xl">What Does This Cost?</h2>
          <p className="mx-auto max-w-2xl text-muted-foreground">Complete transparency: here&apos;s what you&apos;ll actually pay each month. The tools are free; you pay for the AI services.</p>
        </motion.div>

        <motion.div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 mb-10" variants={staggerContainer} initial="hidden" animate={isInView ? "visible" : "hidden"}>
          {PRICING_ITEMS.map((item, i) => (
            <motion.div key={item.name} className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition-all duration-300 hover:border-primary/30" variants={fadeUp} transition={{ delay: staggerDelay(i, 0.1) }} whileHover={{ y: -4, boxShadow: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)" }}>
              <motion.div className={`pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-gradient-to-br ${item.gradient} blur-3xl opacity-0 group-hover:opacity-20 transition-opacity`} />
              <div className="relative">
                <div className={`mb-4 inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${item.gradient}`}>
                  <item.icon className="h-6 w-6 text-white" />
                </div>
                <h3 className="mb-1 text-lg font-semibold">{item.name}</h3>
                <div className="mb-2 flex items-baseline gap-1">
                  <span className="text-3xl font-bold text-gradient-cosmic">{item.price}</span>
                  <span className="text-sm text-muted-foreground">{item.period}</span>
                </div>
                <p className="mb-3 text-sm text-muted-foreground">{item.description}</p>
                <p className="text-xs text-muted-foreground/70 italic">{item.note}</p>
              </div>
            </motion.div>
          ))}
        </motion.div>

        <motion.div className="relative overflow-hidden rounded-2xl border border-primary/30 bg-gradient-to-r from-primary/5 via-[oklch(0.7_0.2_330/0.05)] to-primary/5 p-6 sm:p-8" initial={{ opacity: 0, scale: 0.95 }} animate={isInView ? { opacity: 1, scale: 1 } : { opacity: 0, scale: 0.95 }} transition={{ ...springs.smooth, delay: 0.4 }}>
          <div className="flex flex-col items-center gap-4 text-center sm:flex-row sm:justify-between sm:text-left">
            <div className="flex items-center gap-4">
              <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-primary/20">
                <Coins className="h-7 w-7 text-primary" />
              </div>
              <div>
                <p className="text-sm font-medium text-muted-foreground">Estimated Monthly Total</p>
                <p className="font-mono text-2xl font-bold sm:text-3xl">
                  <span className="text-gradient-cosmic">$440 – $656</span>
                  <span className="text-base font-normal text-muted-foreground">/month</span>
                </p>
              </div>
            </div>
            <div className="flex flex-col gap-2 text-sm text-muted-foreground sm:items-end">
              <div className="flex items-center gap-2"><Check className="h-4 w-4 text-[oklch(0.72_0.19_145)]" /><span>All tools & setup scripts included free</span></div>
              <div className="flex items-center gap-2"><Check className="h-4 w-4 text-[oklch(0.72_0.19_145)]" /><span>Cancel AI subscriptions anytime</span></div>
              <div className="flex items-center gap-2"><Check className="h-4 w-4 text-[oklch(0.72_0.19_145)]" /><span>No hidden fees or upsells</span></div>
            </div>
          </div>
        </motion.div>

        <motion.div className="mt-10 text-center" initial={{ opacity: 0, y: 10 }} animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }} transition={{ ...springs.smooth, delay: 0.5 }}>
          <p className="mb-6 max-w-2xl mx-auto text-muted-foreground">Consider: a junior developer costs $5,000+/month. For under $700, you get <strong className="text-foreground">10+ AI agents</strong> working 24/7, writing code while you sleep.</p>
          <Button asChild size="lg" className="bg-primary text-primary-foreground">
            <Link href="/wizard/os-selection">Start Your Setup<ArrowRight className="ml-2 h-4 w-4" /></Link>
          </Button>
        </motion.div>
      </div>
    </section>
  );
}

function StatBadge({ value, label }: { value: string; label: string }) {
  return (
    <div className="flex flex-col items-center gap-1 px-4">
      <span className="text-2xl font-bold text-gradient-cyan">{value}</span>
      <span className="text-xs text-muted-foreground">{label}</span>
    </div>
  );
}

function ToolBadge({ name, color }: { name: string; color: string }) {
  return (
    <span
      className="inline-flex items-center rounded-full border border-border/50 bg-card/50 px-3 py-1.5 text-sm font-medium transition-all hover:scale-105 hover:border-primary/30"
      style={{ color }}
    >
      {name}
    </span>
  );
}

export default function HomePage() {
  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      {/* Cosmic gradient background */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-hero" />
      <div className="pointer-events-none absolute inset-0 bg-grid-pattern opacity-30" />

      {/* Floating orbs - hidden on mobile to prevent performance issues */}
      <div
        className="pointer-events-none absolute left-1/4 top-1/4 h-96 w-96 rounded-full bg-[oklch(0.75_0.18_195/0.1)] blur-[100px] hidden sm:block sm:animate-pulse-glow"
      />
      <div
        className="pointer-events-none absolute right-1/4 bottom-1/4 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[80px] hidden sm:block sm:animate-pulse-glow"
        style={{ animationDelay: "1s" }}
      />

      {/* Navigation */}
      <nav className="relative z-20 mx-auto flex max-w-7xl items-center justify-between px-6 py-6">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/20">
            <Terminal className="h-5 w-5 text-primary" />
          </div>
          <span className="font-mono text-lg font-bold tracking-tight">Agent Flywheel</span>
        </div>
        <div className="flex items-center gap-4">
          <a
            href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden text-sm text-muted-foreground transition-colors hover:text-foreground sm:block"
          >
            GitHub
          </a>
          <Link
            href="/learn"
            className="hidden items-center gap-1 text-sm text-muted-foreground transition-colors hover:text-foreground sm:flex"
          >
            <BookOpen className="h-4 w-4" />
            Learn
          </Link>
          <Button asChild size="sm" variant="outline" className="border-primary/30 hover:bg-primary/10">
            <Link href="/wizard/os-selection">
              Get Started
              <ChevronRight className="ml-1 h-4 w-4" />
            </Link>
          </Button>
        </div>
      </nav>

      {/* Hero Section */}
      <main className="relative z-10">
        <section className="mx-auto max-w-7xl px-6 pb-20 pt-12 sm:pt-20">
          <div className="grid gap-12 lg:grid-cols-2 lg:gap-16">
            {/* Left column - Text */}
            <motion.div
              className="flex flex-col justify-center"
              variants={staggerContainer}
              initial="hidden"
              animate="visible"
            >
              {/* Badge */}
              <motion.div
                className="mb-6 inline-flex w-fit items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-4 py-1.5 text-sm text-primary"
                variants={fadeUp}
              >
                <Sparkles className="h-4 w-4" />
                <span>Zero to agentic coding in 30 minutes</span>
              </motion.div>

              {/* Headline */}
              <motion.h1
                className="mb-6 font-mono text-4xl font-bold leading-tight tracking-tight sm:text-5xl lg:text-6xl"
                variants={fadeUp}
              >
                <span className="text-gradient-cosmic">AI Agents</span>
                <br />
                <span className="text-foreground">Coding For You</span>
              </motion.h1>

              {/* Subheadline */}
              <motion.p
                className="mb-8 max-w-xl text-lg leading-relaxed text-muted-foreground"
                variants={fadeUp}
              >
                Transform a fresh <Jargon term="cloud-server">cloud server</Jargon> into a fully-configured{" "}
                <Jargon term="agentic">agentic</Jargon> coding environment.{" "}
                <Jargon term="claude-code">Claude Code</Jargon>, OpenAI <Jargon term="codex">Codex</Jargon>,{" "}
                Google <Jargon term="gemini-cli">Gemini</Jargon>: all pre-configured with 30+ modern developer tools.
                All totally free and <Jargon term="open-source">open-source</Jargon>.
              </motion.p>

              {/* CTA Buttons */}
              <motion.div
                className="flex flex-col gap-3 sm:flex-row sm:items-center"
                variants={fadeUp}
              >
                <Button
                  asChild
                  size="lg"
                  className="group relative overflow-hidden bg-primary text-primary-foreground hover:bg-primary/90"
                >
                  <Link href="/wizard/os-selection">
                    <span className="relative z-10 flex items-center gap-2">
                      Start the Wizard
                      <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                    </span>
                    <span className="absolute inset-0 -z-10 bg-gradient-to-r from-primary via-[oklch(0.7_0.2_330)] to-primary opacity-0 transition-opacity group-hover:opacity-100" style={{ backgroundSize: "200% 100%", animation: "shimmer 2s linear infinite" }} />
                  </Link>
                </Button>
                <Button asChild size="lg" variant="outline" className="border-border/50 hover:bg-muted/50">
                  <a
                    href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <GitBranch className="mr-2 h-4 w-4" />
                    View on GitHub
                  </a>
                </Button>
              </motion.div>

              {/* Stats */}
              <motion.div
                className="mt-10 flex flex-wrap items-center justify-center gap-4 sm:justify-start sm:gap-0 sm:divide-x sm:divide-border/50"
                variants={fadeUp}
              >
                <StatBadge value="30+" label="Tools Installed" />
                <StatBadge value="3" label="AI Agents" />
                <StatBadge value="~30m" label="Setup Time" />
              </motion.div>
            </motion.div>

            {/* Right column - Terminal */}
            <motion.div
              className="flex items-center justify-center lg:justify-end"
              initial={{ opacity: 0, x: 40 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ ...springs.smooth, delay: 0.3 }}
            >
              <AnimatedTerminal />
            </motion.div>
          </div>
        </section>

        {/* Tools ticker */}
        <section className="border-y border-border/30 bg-card/30 py-6">
          <div className="mx-auto max-w-7xl px-6">
            <div className="flex flex-col items-center gap-4 sm:flex-row sm:justify-center sm:gap-6">
              <span className="shrink-0 text-xs uppercase tracking-widest text-muted-foreground">
                Powered by
              </span>
              <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
                <ToolBadge name="Claude Code" color="oklch(0.78 0.16 75)" />
                <ToolBadge name="Codex CLI" color="oklch(0.72 0.19 145)" />
                <ToolBadge name="Gemini CLI" color="oklch(0.75 0.18 195)" />
                <ToolBadge name="Bun" color="oklch(0.78 0.16 75)" />
                <ToolBadge name="Rust" color="oklch(0.65 0.22 25)" />
                <ToolBadge name="Go" color="oklch(0.75 0.18 195)" />
                <ToolBadge name="tmux" color="oklch(0.72 0.19 145)" />
                <ToolBadge name="zsh" color="oklch(0.7 0.2 330)" />
              </div>
            </div>
          </div>
        </section>

        {/* Features Grid */}
        <FeaturesSection />

        {/* Flywheel Teaser */}
        <FlywheelSection />

        {/* Workflow Steps Preview */}
        <WorkflowStepsSection />

        {/* Why VPS? Section */}
        <WhyVPSSection />

        {/* Is This For You? Section */}
        <IsThisForYouSection />

        {/* Pricing Section */}
        <WhatDoesThisCostSection />

        {/* About Section */}
        <AboutSection />

        {/* Footer */}
        <footer className="border-t border-border/30 py-12">
          <div className="mx-auto max-w-7xl px-6">
            <div className="flex flex-col items-center gap-8 text-center sm:flex-row sm:justify-between sm:text-left">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
                  <Terminal className="h-4 w-4 text-primary" />
                </div>
                <span className="font-mono text-sm font-bold">Agent Flywheel</span>
              </div>

              <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-muted-foreground">
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="transition-colors hover:text-foreground"
                >
                  GitHub
                </a>
                <Link
                  href="/learn"
                  className="transition-colors hover:text-foreground"
                >
                  Learning Hub
                </Link>
                <a
                  href="https://github.com/Dicklesworthstone/ntm"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="transition-colors hover:text-foreground"
                >
                  NTM
                </a>
                <a
                  href="https://github.com/Dicklesworthstone/mcp_agent_mail"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="transition-colors hover:text-foreground"
                >
                  Agent Mail
                </a>
              </div>

              <p className="text-xs text-muted-foreground">
                Created by{" "}
                <a
                  href="https://jeffreyemanuel.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:underline"
                >
                  Jeffrey Emanuel
                </a>
              </p>
            </div>
          </div>
        </footer>
      </main>
    </div>
  );
}
