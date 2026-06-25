"use client";

import type React from "react";
import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Shield,
  ShieldAlert,
  Key,
  Users,
  AlertTriangle,
  Lock,
  Terminal,
  CheckCircle,
  XCircle,
  UserCheck,
  RefreshCw,
  Zap,
  Eye,
  ShieldCheck,
  Clock,
  ToggleLeft,
  ToggleRight,
  Ban,
  Activity,
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

export function SafetyToolsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Use DCG, SLB and CAAM for layered safety and account management.
      </GoalBanner>

      {/* Introduction */}
      <Section
        title="Safety First"
        icon={<Shield className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          AI agents are powerful but can cause damage if misused. The
          Dicklesworthstone stack includes three safety tools:
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<ShieldAlert className="h-5 w-5" />}
              title="DCG"
              description="Pre-execution blocking of destructive commands"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Users className="h-5 w-5" />}
              title="SLB"
              description="Two-person rule for dangerous commands"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="CAAM"
              description="Agent authentication switching"
              gradient="from-primary/20 to-violet-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* SLB Section */}
      <Section
        title="SLB: Simultaneous Launch Button"
        icon={<Users className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          <Highlight>SLB</Highlight> implements a &quot;two-person rule&quot;
          for dangerous commands. Just like nuclear launch codes require two
          keys, SLB requires two approvals before executing risky operations.
        </Paragraph>

        <div className="mt-8">
          <InteractiveSafetyDemo />
        </div>
      </Section>

      {/* When to Use SLB */}
      <Section
        title="When to Use SLB"
        icon={<AlertTriangle className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-4">
          <DangerCard
            command="rm -rf /"
            risk="Deletes entire filesystem"
            slb="Requires confirmation from two agents"
          />
          <DangerCard
            command="git push --force origin main"
            risk="Overwrites shared history"
            slb="Requires explicit approval"
          />
          <DangerCard
            command="DROP DATABASE production"
            risk="Destroys production data"
            slb="Two-person verification"
          />
          <DangerCard
            command="kubectl delete namespace prod"
            risk="Takes down production services"
            slb="Mandatory review"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            Never bypass SLB protections. If a command requires two approvals,
            there&apos;s a reason. Get a second opinion.
          </TipBox>
        </div>
      </Section>

      {/* SLB Commands */}
      <Section
        title="SLB Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.25}
      >
        <CommandList
          commands={[
            {
              command: "slb pending",
              description: "Show pending requests",
            },
            {
              command: 'slb run "rm -rf /tmp" --reason "Clean build"',
              description: "Request approval and execute when approved",
            },
            {
              command: "slb approve <id> --session-id <sid>",
              description: "Approve a pending request",
            },
            {
              command: 'slb reject <id> --session-id <sid> --reason "..."',
              description: "Reject a pending request",
            },
            {
              command: "slb status <request-id>",
              description: "Check status of a specific request",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* DCG Section */}
      <Section
        title="DCG: Destructive Command Guard"
        icon={<ShieldAlert className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          <Highlight>DCG</Highlight> blocks dangerous commands before they run.
          It inspects every command from Claude Code and stops destructive
          patterns like hard resets, force pushes, and recursive deletes.
        </Paragraph>
        <Paragraph>
          If a command is safe, it runs normally. If it&apos;s risky, DCG blocks
          it and suggests a safer alternative.
        </Paragraph>

        <div className="mt-6">
          <TipBox variant="warning">
            Treat a DCG block as a safety checkpoint. Read the explanation and
            prefer the safer command whenever possible.
          </TipBox>
        </div>
      </Section>

      {/* DCG Commands */}
      <Section
        title="DCG Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.35}
      >
        <CommandList
          commands={[
            {
              command: "dcg test '<command>' --explain",
              description: "Explain why a command would be blocked",
            },
            {
              command: "dcg packs",
              description: "List available protection packs",
            },
            {
              command: "dcg install",
              description: "Register DCG as a Claude Code hook",
            },
            {
              command: "dcg allow-once <code>",
              description: "Bypass a single approved command",
            },
            {
              command: "dcg doctor",
              description: "Check installation and hook status",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* CAAM Section */}
      <Section
        title="CAAM: Coding Agent Account Manager"
        icon={<Key className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          <Highlight>CAAM</Highlight> enables sub-100ms account switching for
          subscription-based AI services (Claude Max, Codex CLI, and Google/Antigravity access).
          Swap OAuth tokens instantly without re-authenticating.
        </Paragraph>

        <div className="mt-6 space-y-4">
          <CaamFeature
            icon={<Key className="h-5 w-5" />}
            title="Token Management"
            description="Backup and restore OAuth tokens for each tool"
          />
          <CaamFeature
            icon={<RefreshCw className="h-5 w-5" />}
            title="Instant Switching"
            description="Switch accounts in under 100ms via symlink swap"
          />
          <CaamFeature
            icon={<Eye className="h-5 w-5" />}
            title="Multi-Tool Support"
            description="Works with Claude, Codex, and Antigravity CLIs"
          />
          <CaamFeature
            icon={<Lock className="h-5 w-5" />}
            title="Profile Backup"
            description="Save profiles by email for easy restoration"
          />
        </div>
      </Section>

      {/* CAAM Use Cases */}
      <Section
        title="CAAM Use Cases"
        icon={<UserCheck className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="space-y-4">
          <UseCase
            scenario="Personal vs Work"
            description="Switch between personal and work subscriptions"
          />
          <UseCase
            scenario="Rate Limits"
            description="Rotate to a fresh account when hitting usage caps"
          />
          <UseCase
            scenario="Cost Separation"
            description="Use different subscriptions for different projects"
          />
          <UseCase
            scenario="Multi-Account"
            description="Manage multiple Claude Max / Codex accounts"
          />
        </div>
      </Section>

      {/* CAAM Commands */}
      <Section
        title="CAAM Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.4}
      >
        <CommandList
          commands={[
            {
              command: "caam ls [tool]",
              description: "List saved profiles (claude, codex, gemini)",
            },
            {
              command: "caam backup <tool> <email>",
              description: "Save current auth as a named profile",
            },
            {
              command: "caam activate <tool> <email>",
              description: "Activate a saved profile",
            },
            {
              command: "caam status [tool]",
              description: "Show currently active profile",
            },
            {
              command: "caam delete <tool> <email>",
              description: "Remove a saved profile",
            },
          ]}
        />
      </Section>

      <Divider />

      {/* Integration with Agents */}
      <Section
        title="Integration with Agents"
        icon={<Zap className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          DCG, SLB, and CAAM integrate with Claude Code, Codex, and Gemini:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Example: DCG blocks a destructive command
$ claude "reset the repo"
> DCG: blocked git reset --hard
> Suggestion: git restore --staged .

# Example: Dangerous command triggers SLB
$ claude "delete all test files"
> SLB: This command requires approval
> Waiting for second approval...
> Run 'slb approve req-123 --session-id <sid>' from another session

# Example: Switch Claude accounts for a project
$ caam activate claude work@company.com
> Activated profile 'work@company.com' for claude
> Symlink updated in 47ms

$ claude "continue the project"
> Using profile: work@company.com`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.5}
      >
        <div className="grid gap-6 md:grid-cols-3">
          {/* SLB Best Practices */}
          <div className="rounded-2xl border border-red-500/20 bg-red-500/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <Users className="h-5 w-5 text-red-400" />
              SLB Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Never bypass approval requirements" />
              <BestPractice text="Review commands before approving" />
              <BestPractice text="Use descriptive request messages" />
              <BestPractice text="Set up notifications for pending requests" />
            </div>
          </div>

          {/* DCG Best Practices */}
          <div className="rounded-2xl border border-rose-500/20 bg-rose-500/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <ShieldAlert className="h-5 w-5 text-rose-400" />
              DCG Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Read the block explanation before acting" />
              <BestPractice text="Prefer safer alternatives over allow-once" />
              <BestPractice text="Enable only the packs you need" />
              <BestPractice text="Re-register after updates: dcg install" />
            </div>
          </div>

          {/* CAAM Best Practices */}
          <div className="rounded-2xl border border-primary/20 bg-primary/5 p-5">
            <h4 className="font-bold text-white flex items-center gap-2 mb-4">
              <Key className="h-5 w-5 text-primary" />
              CAAM Best Practices
            </h4>
            <div className="space-y-3">
              <BestPractice text="Backup profiles before switching" />
              <BestPractice text="Use email as profile identifier" />
              <BestPractice text="Verify active profile with caam status" />
              <BestPractice text="Delete old profiles when no longer needed" />
            </div>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Quick Reference */}
      <Section
        title="Quick Reference"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.55}
      >
        <div className="grid gap-4 md:grid-cols-3">
          <QuickRefCard
            title="SLB"
            commands={[
              "slb pending",
              "slb run <cmd> --reason ...",
              "slb approve <id> --session-id ...",
              "slb status <id>",
            ]}
            color="from-red-500/20 to-rose-500/20"
          />
          <QuickRefCard
            title="DCG"
            commands={[
              "dcg test '<cmd>' --explain",
              "dcg packs",
              "dcg allow-once <code>",
              "dcg doctor",
            ]}
            color="from-rose-500/20 to-fuchsia-500/20"
          />
          <QuickRefCard
            title="CAAM"
            commands={[
              "caam ls [tool]",
              "caam backup <tool> <email>",
              "caam activate <tool> <email>",
              "caam status [tool]",
            ]}
            color="from-primary/20 to-violet-500/20"
          />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE SAFETY DEMO V2 - "Control Room" Layout
// =============================================================================

interface DcgCommand {
  cmd: string;
  blocked: boolean;
  rule?: string;
  label: string;
}

const DCG_COMMANDS: DcgCommand[] = [
  { cmd: "rm -rf /", blocked: true, rule: "Recursive delete at root - catastrophic", label: "rm -rf /" },
  { cmd: "git reset --hard HEAD~10", blocked: true, rule: "Hard reset destroys uncommitted work", label: "git reset --hard" },
  { cmd: "DROP TABLE users;", blocked: true, rule: "DROP TABLE on production database", label: "DROP TABLE" },
  { cmd: "git status", blocked: false, label: "git status" },
  { cmd: "ls -la /tmp", blocked: false, label: "ls -la /tmp" },
  { cmd: "echo 'hello world'", blocked: false, label: "echo hello" },
];

const SLB_CRITICAL_CMD = "kubectl delete namespace production";

interface SecurityEvent {
  id: number;
  time: string;
  type: "blocked" | "allowed" | "approved";
  cmd: string;
}

function useTypewriter(text: string, isActive: boolean, speed = 40): string {
  const [displayed, setDisplayed] = useState("");
  const prevTextRef = useRef("");

  useEffect(() => {
    if (!isActive) {
      setDisplayed("");
      prevTextRef.current = "";
      return;
    }
    if (text === prevTextRef.current) return;
    prevTextRef.current = text;
    setDisplayed("");
    let i = 0;
    const interval = setInterval(() => {
      i++;
      if (i <= text.length) {
        setDisplayed(text.slice(0, i));
      } else {
        clearInterval(interval);
      }
    }, speed);
    return () => clearInterval(interval);
  }, [text, isActive, speed]);

  return displayed;
}

function InteractiveSafetyDemo() {
  const [isProtected, setIsProtected] = useState(true);
  const [activeDcgCmd, setActiveDcgCmd] = useState<DcgCommand | null>(null);
  const [dcgResult, setDcgResult] = useState<"blocked" | "allowed" | null>(null);
  const [dcgShake, setDcgShake] = useState(false);
  const [slbApproval1, setSlbApproval1] = useState(false);
  const [slbApproval2, setSlbApproval2] = useState(false);
  const [slbCountdown, setSlbCountdown] = useState<number | null>(null);
  const [slbExecuted, setSlbExecuted] = useState(false);
  const [events, setEvents] = useState<SecurityEvent[]>([
    { id: 0, time: "14:31:02", type: "blocked", cmd: "rm -rf /" },
    { id: 1, time: "14:31:15", type: "allowed", cmd: "git status" },
    { id: 2, time: "14:31:28", type: "approved", cmd: "slb approve req-42" },
  ]);
  const eventCounterRef = useRef(3);
  const dcgTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const slbTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const typedText = useTypewriter(
    activeDcgCmd?.cmd ?? "",
    activeDcgCmd !== null && dcgResult === null
  );

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (dcgTimerRef.current) clearTimeout(dcgTimerRef.current);
      if (slbTimerRef.current) clearTimeout(slbTimerRef.current);
    };
  }, []);

  const addEvent = (type: SecurityEvent["type"], cmd: string) => {
    const now = new Date();
    const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}:${String(now.getSeconds()).padStart(2, "0")}`;
    const id = eventCounterRef.current;
    eventCounterRef.current += 1;
    setEvents((prev) => [{ id, time, type, cmd }, ...prev].slice(0, 8));
  };

  const handleDcgCommand = (command: DcgCommand) => {
    if (dcgTimerRef.current) clearTimeout(dcgTimerRef.current);
    setDcgResult(null);
    setActiveDcgCmd(command);

    const typingDuration = command.cmd.length * 40 + 200;
    dcgTimerRef.current = setTimeout(() => {
      if (isProtected && command.blocked) {
        setDcgResult("blocked");
        setDcgShake(true);
        addEvent("blocked", command.cmd);
        dcgTimerRef.current = setTimeout(() => {
          setDcgShake(false);
        }, 600);
      } else {
        setDcgResult("allowed");
        addEvent("allowed", command.cmd);
      }
    }, typingDuration);
  };

  const handleSlbApproval = (slot: 1 | 2) => {
    if (slbExecuted) return;
    if (slot === 1 && !slbApproval1) {
      setSlbApproval1(true);
      addEvent("approved", "Approval 1 granted");
    }
    if (slot === 2 && !slbApproval2) {
      setSlbApproval2(true);
      addEvent("approved", "Approval 2 granted");
    }
  };

  // Start countdown when both approvals are in
  useEffect(() => {
    if (slbApproval1 && slbApproval2 && !slbExecuted && slbCountdown === null) {
      const t = setTimeout(() => {
        setSlbCountdown(3);
      }, 0);
      return () => clearTimeout(t);
    }
  }, [slbApproval1, slbApproval2, slbExecuted, slbCountdown]);

  // Run countdown
  useEffect(() => {
    if (slbCountdown === null || slbCountdown <= 0) return;
    slbTimerRef.current = setTimeout(() => {
      setSlbCountdown((c) => (c !== null ? c - 1 : null));
    }, 1000);
    return () => {
      if (slbTimerRef.current) clearTimeout(slbTimerRef.current);
    };
  }, [slbCountdown]);

  // Execute when countdown reaches 0
  useEffect(() => {
    if (slbCountdown === 0 && !slbExecuted) {
      slbTimerRef.current = setTimeout(() => {
        setSlbExecuted(true);
        addEvent("approved", "kubectl delete namespace production");
      }, 200);
    }
  }, [slbCountdown, slbExecuted]);

  const resetSlb = () => {
    setSlbApproval1(false);
    setSlbApproval2(false);
    setSlbCountdown(null);
    setSlbExecuted(false);
  };

  const springSmooth = { type: "spring" as const, stiffness: 200, damping: 25 };

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background ambient glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-red-500/[0.06] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-emerald-500/[0.06] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-primary/[0.03] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 space-y-4">
        {/* Header bar */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Shield className="h-5 w-5 text-primary" />
            <span className="text-sm font-bold text-white/90 tracking-wide uppercase">
              Safety Control Room
            </span>
          </div>
          {/* Protected / Unprotected toggle */}
          <button
            type="button"
            onClick={() => setIsProtected((p) => !p)}
            className={`flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-semibold transition-all duration-300 border ${
              isProtected
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-400"
                : "border-red-500/30 bg-red-500/10 text-red-400"
            }`}
          >
            {isProtected ? (
              <ToggleRight className="h-4 w-4" />
            ) : (
              <ToggleLeft className="h-4 w-4" />
            )}
            {isProtected ? "Protected" : "Unprotected"}
          </button>
        </div>

        {/* Split-screen panels */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* LEFT PANEL: DCG Terminal */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
            <div className="flex items-center gap-2 px-4 py-3 border-b border-white/[0.06] bg-white/[0.01]">
              <ShieldAlert className="h-4 w-4 text-red-400" />
              <span className="text-xs font-bold text-white/70 uppercase tracking-wider">
                DCG Terminal
              </span>
              <span className="ml-auto text-[10px] text-white/30 font-mono">
                destructive-command-guard v3.1
              </span>
            </div>

            {/* Terminal display */}
            <motion.div
              animate={{
                x: dcgShake ? [0, -8, 8, -6, 6, -3, 3, 0] : 0,
              }}
              transition={{ duration: 0.5 }}
              className="p-4 font-mono text-sm min-h-[140px]"
            >
              <div className="flex items-center gap-2 mb-3">
                <div className="h-2.5 w-2.5 rounded-full bg-red-500/80" />
                <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/80" />
                <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/80" />
                <span className="text-[10px] text-white/20 ml-1">bash</span>
              </div>

              {activeDcgCmd ? (
                <div className="space-y-2">
                  <p className="text-white/60">
                    <span className="text-emerald-400">$</span>{" "}
                    {dcgResult !== null ? activeDcgCmd.cmd : typedText}
                    {dcgResult === null && (
                      <motion.span
                        animate={{ opacity: [1, 0] }}
                        transition={{ duration: 0.8, repeat: Infinity }}
                        className="text-white/60"
                      >
                        |
                      </motion.span>
                    )}
                  </p>
                  <AnimatePresence mode="wait">
                    {dcgResult === "blocked" && (
                      <motion.div
                        key="blocked-result"
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0 }}
                        transition={springSmooth}
                        className="space-y-2"
                      >
                        <div className="flex items-center gap-2">
                          <motion.div
                            initial={{ scale: 0, rotate: -45 }}
                            animate={{ scale: 1, rotate: 0 }}
                            transition={{ type: "spring", stiffness: 400, damping: 15 }}
                          >
                            <Ban className="h-4 w-4 text-red-400" />
                          </motion.div>
                          <span className="text-red-400 font-bold text-xs uppercase tracking-widest">
                            BLOCKED
                          </span>
                        </div>
                        <motion.div
                          initial={{ opacity: 0, x: -16 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ ...springSmooth, delay: 0.15 }}
                          className="rounded-lg border border-red-500/20 bg-red-500/5 px-3 py-2"
                        >
                          <p className="text-[11px] text-red-300/80">
                            <span className="text-red-400 font-semibold">Rule:</span>{" "}
                            {activeDcgCmd.rule}
                          </p>
                        </motion.div>
                      </motion.div>
                    )}
                    {dcgResult === "allowed" && (
                      <motion.div
                        key="allowed-result"
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0 }}
                        transition={springSmooth}
                        className="flex items-center gap-2"
                      >
                        <motion.div
                          initial={{ scale: 0 }}
                          animate={{ scale: 1 }}
                          transition={{ type: "spring", stiffness: 500, damping: 20 }}
                        >
                          <CheckCircle className="h-4 w-4 text-emerald-400" />
                        </motion.div>
                        <span className="text-emerald-400 text-xs font-semibold">
                          {isProtected ? "ALLOWED - safe command" : "PASSED - no protection active"}
                        </span>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>
              ) : (
                <p className="text-white/30 text-xs">
                  Click a command below to test DCG...
                </p>
              )}
            </motion.div>

            {/* Command buttons */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 p-4 pt-0">
              {DCG_COMMANDS.map((command) => (
                <button
                  key={command.cmd}
                  type="button"
                  onClick={() => handleDcgCommand(command)}
                  className={`group relative rounded-xl px-3 py-2 text-left text-[11px] font-mono transition-all duration-200 border ${
                    command.blocked
                      ? "border-red-500/20 bg-red-500/5 hover:border-red-500/40 hover:bg-red-500/10 text-red-300/80"
                      : "border-emerald-500/20 bg-emerald-500/5 hover:border-emerald-500/40 hover:bg-emerald-500/10 text-emerald-300/80"
                  }`}
                >
                  <span className="flex items-center gap-1.5">
                    {command.blocked ? (
                      <ShieldAlert className="h-3 w-3 shrink-0 opacity-60" />
                    ) : (
                      <ShieldCheck className="h-3 w-3 shrink-0 opacity-60" />
                    )}
                    {command.label}
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* RIGHT PANEL: SLB Launch Console */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
            <div className="flex items-center gap-2 px-4 py-3 border-b border-white/[0.06] bg-white/[0.01]">
              <Users className="h-4 w-4 text-amber-400" />
              <span className="text-xs font-bold text-white/70 uppercase tracking-wider">
                SLB Launch Console
              </span>
              <span className="ml-auto text-[10px] text-white/30 font-mono">
                two-person rule
              </span>
            </div>

            <div className="p-4 space-y-4">
              {/* Critical command display */}
              <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 px-4 py-3">
                <p className="text-[10px] uppercase tracking-wider text-amber-400/60 font-semibold mb-1">
                  Critical Command Pending
                </p>
                <code className="text-sm text-amber-300 font-mono">
                  {SLB_CRITICAL_CMD}
                </code>
              </div>

              {/* Approval slots */}
              <div className="grid grid-cols-2 gap-3">
                {/* Approval 1 */}
                <motion.button
                  type="button"
                  onClick={() => handleSlbApproval(1)}
                  disabled={slbApproval1 || slbExecuted}
                  animate={{
                    borderColor: slbApproval1
                      ? "rgba(34, 197, 94, 0.4)"
                      : "rgba(255, 255, 255, 0.08)",
                  }}
                  transition={springSmooth}
                  className="relative rounded-xl border bg-white/[0.02] backdrop-blur-xl p-4 text-center transition-colors hover:bg-white/[0.04] disabled:cursor-default"
                >
                  <div className="flex flex-col items-center gap-2">
                    <AnimatePresence mode="wait">
                      {slbApproval1 ? (
                        <motion.div
                          key="approved-1"
                          initial={{ scale: 0, rotate: -180 }}
                          animate={{ scale: 1, rotate: 0 }}
                          transition={{ type: "spring", stiffness: 400, damping: 15 }}
                        >
                          <CheckCircle className="h-8 w-8 text-emerald-400" />
                        </motion.div>
                      ) : (
                        <motion.div
                          key="pending-1"
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          exit={{ opacity: 0, scale: 0.5 }}
                          transition={springSmooth}
                          className="h-8 w-8 rounded-full border-2 border-dashed border-white/20 flex items-center justify-center"
                        >
                          <Key className="h-4 w-4 text-white/30" />
                        </motion.div>
                      )}
                    </AnimatePresence>
                    <span className="text-[11px] font-semibold text-white/60">
                      {slbApproval1 ? "Approved" : "Approval 1"}
                    </span>
                    {!slbApproval1 && !slbExecuted && (
                      <span className="text-[10px] text-primary/60">
                        Click to approve
                      </span>
                    )}
                  </div>
                </motion.button>

                {/* Approval 2 */}
                <motion.button
                  type="button"
                  onClick={() => handleSlbApproval(2)}
                  disabled={slbApproval2 || slbExecuted}
                  animate={{
                    borderColor: slbApproval2
                      ? "rgba(34, 197, 94, 0.4)"
                      : "rgba(255, 255, 255, 0.08)",
                  }}
                  transition={springSmooth}
                  className="relative rounded-xl border bg-white/[0.02] backdrop-blur-xl p-4 text-center transition-colors hover:bg-white/[0.04] disabled:cursor-default"
                >
                  <div className="flex flex-col items-center gap-2">
                    <AnimatePresence mode="wait">
                      {slbApproval2 ? (
                        <motion.div
                          key="approved-2"
                          initial={{ scale: 0, rotate: 180 }}
                          animate={{ scale: 1, rotate: 0 }}
                          transition={{ type: "spring", stiffness: 400, damping: 15 }}
                        >
                          <CheckCircle className="h-8 w-8 text-emerald-400" />
                        </motion.div>
                      ) : (
                        <motion.div
                          key="pending-2"
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          exit={{ opacity: 0, scale: 0.5 }}
                          transition={springSmooth}
                          className="h-8 w-8 rounded-full border-2 border-dashed border-white/20 flex items-center justify-center"
                        >
                          <Key className="h-4 w-4 text-white/30" />
                        </motion.div>
                      )}
                    </AnimatePresence>
                    <span className="text-[11px] font-semibold text-white/60">
                      {slbApproval2 ? "Approved" : "Approval 2"}
                    </span>
                    {!slbApproval2 && !slbExecuted && (
                      <span className="text-[10px] text-primary/60">
                        Click to approve
                      </span>
                    )}
                  </div>
                </motion.button>
              </div>

              {/* Countdown / Execution status */}
              <div className="min-h-[56px] flex items-center justify-center">
                <AnimatePresence mode="wait">
                  {slbExecuted ? (
                    <motion.div
                      key="slb-executed"
                      initial={{ opacity: 0, scale: 0.8 }}
                      animate={{ opacity: 1, scale: 1 }}
                      exit={{ opacity: 0 }}
                      transition={{ type: "spring", stiffness: 400, damping: 20 }}
                      className="flex flex-col items-center gap-1"
                    >
                      <div className="flex items-center gap-2">
                        <motion.div
                          initial={{ scale: 0 }}
                          animate={{ scale: [0, 1.3, 1] }}
                          transition={{ duration: 0.5 }}
                        >
                          <CheckCircle className="h-6 w-6 text-emerald-400" />
                        </motion.div>
                        <span className="text-sm font-bold text-emerald-400">
                          EXECUTED SUCCESSFULLY
                        </span>
                      </div>
                      <button
                        type="button"
                        onClick={resetSlb}
                        className="mt-1 text-[10px] text-white/40 hover:text-white/70 transition-colors underline underline-offset-2"
                      >
                        Reset demo
                      </button>
                    </motion.div>
                  ) : slbCountdown !== null && slbCountdown > 0 ? (
                    <motion.div
                      key="slb-countdown"
                      initial={{ opacity: 0, scale: 0.5 }}
                      animate={{ opacity: 1, scale: 1 }}
                      exit={{ opacity: 0, scale: 0.5 }}
                      transition={springSmooth}
                      className="flex flex-col items-center gap-1"
                    >
                      <div className="flex items-center gap-2 text-amber-400">
                        <Clock className="h-4 w-4" />
                        <span className="text-sm font-semibold">Executing in...</span>
                      </div>
                      <motion.span
                        key={slbCountdown}
                        initial={{ scale: 1.5, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ type: "spring", stiffness: 300, damping: 20 }}
                        className="text-2xl font-bold text-amber-300 font-mono"
                      >
                        {slbCountdown}
                      </motion.span>
                    </motion.div>
                  ) : slbApproval1 || slbApproval2 ? (
                    <motion.div
                      key="slb-partial"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      transition={springSmooth}
                      className="text-xs text-white/40 text-center"
                    >
                      {slbApproval1 && slbApproval2
                        ? "Both approvals in - preparing execution..."
                        : `Waiting for second approval (${slbApproval1 || slbApproval2 ? 1 : 0}/2)...`}
                    </motion.div>
                  ) : (
                    <motion.div
                      key="slb-waiting"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      transition={springSmooth}
                      className="text-xs text-white/30 text-center"
                    >
                      Two approvals required to execute
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </div>
          </div>
        </div>

        {/* Bottom: Security Events Ticker */}
        <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
          <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.01]">
            <Activity className="h-3.5 w-3.5 text-primary/70" />
            <span className="text-[10px] font-bold text-white/50 uppercase tracking-wider">
              Security Events
            </span>
            <motion.div
              animate={{ opacity: [0.3, 1, 0.3] }}
              transition={{ duration: 2, repeat: Infinity }}
              className="ml-auto h-2 w-2 rounded-full bg-emerald-400"
            />
            <span className="text-[10px] text-white/30">LIVE</span>
          </div>
          <div className="max-h-[100px] overflow-hidden">
            <div className="p-3 space-y-1">
              <AnimatePresence initial={false}>
                {events.slice(0, 5).map((event) => (
                  <motion.div
                    key={event.id}
                    initial={{ opacity: 0, height: 0, x: -20 }}
                    animate={{ opacity: 1, height: "auto", x: 0 }}
                    exit={{ opacity: 0, height: 0 }}
                    transition={springSmooth}
                    className="flex items-center gap-2 font-mono text-[11px] overflow-hidden"
                  >
                    <span className="text-white/20 shrink-0">[{event.time}]</span>
                    <span
                      className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-bold uppercase ${
                        event.type === "blocked"
                          ? "bg-red-500/20 text-red-400"
                          : event.type === "allowed"
                            ? "bg-emerald-500/20 text-emerald-400"
                            : "bg-amber-500/20 text-amber-400"
                      }`}
                    >
                      {event.type}
                    </span>
                    <span className="text-white/50 truncate">{event.cmd}</span>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// DANGER CARD
// =============================================================================
function DangerCard({
  command,
  risk,
  slb,
}: {
  command: string;
  risk: string;
  slb: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group rounded-2xl border border-red-500/20 bg-red-500/5 p-5 backdrop-blur-xl transition-all duration-300 hover:border-red-500/40 hover:bg-red-500/10"
    >
      <code className="text-sm text-red-400 font-mono font-medium">{command}</code>
      <div className="flex items-start gap-3 mt-3">
        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-red-500/20">
          <XCircle className="h-4 w-4 text-red-400" />
        </div>
        <span className="text-sm text-white/60">{risk}</span>
      </div>
      <div className="flex items-start gap-3 mt-2">
        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20">
          <Shield className="h-4 w-4 text-emerald-400" />
        </div>
        <span className="text-sm text-emerald-400/80 font-medium">{slb}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CAAM FEATURE
// =============================================================================
function CaamFeature({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-primary/30 hover:bg-white/[0.04]"
    >
      <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/20 text-primary shrink-0 shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
        {icon}
      </div>
      <div>
        <h4 className="font-semibold text-white group-hover:text-primary transition-colors">{title}</h4>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// USE CASE
// =============================================================================
function UseCase({
  scenario,
  description,
}: {
  scenario: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-center gap-4 p-4 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/20 text-primary shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
        <UserCheck className="h-5 w-5" />
      </div>
      <div>
        <span className="font-medium text-white group-hover:text-primary transition-colors">{scenario}</span>
        <span className="text-white/50 mx-2">—</span>
        <span className="text-sm text-white/50">{description}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({ text }: { text: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -5 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-3 p-2 -mx-2 rounded-lg transition-colors hover:bg-white/[0.03]"
    >
      <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 group-hover:bg-emerald-500/30 transition-colors">
        <CheckCircle className="h-3.5 w-3.5 text-emerald-400" />
      </div>
      <span className="text-sm text-white/70 group-hover:text-white transition-colors">{text}</span>
    </motion.div>
  );
}

// =============================================================================
// QUICK REF CARD
// =============================================================================
function QuickRefCard({
  title,
  commands,
  color,
}: {
  title: string;
  commands: string[];
  color: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${color} p-6 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.2]`}
    >
      {/* Decorative glow */}
      <div className="absolute -top-8 -right-8 w-24 h-24 bg-white/10 rounded-full blur-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <h4 className="relative font-bold text-white mb-4 text-lg">{title}</h4>
      <div className="relative space-y-2">
        {commands.map((cmd) => (
          <code
            key={cmd}
            className="block text-sm text-white/80 font-mono py-1 px-2 -mx-2 rounded-lg transition-colors group-hover:text-white hover:bg-white/[0.05]"
          >
            $ {cmd}
          </code>
        ))}
      </div>
    </motion.div>
  );
}
