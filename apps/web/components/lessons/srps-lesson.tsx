"use client";

import { useState, useEffect, useCallback, useRef, useMemo } from "react";
import { motion, AnimatePresence, useInView } from "@/components/motion";
import {
  Shield,
  Activity,
  Gauge,
  Terminal,
  Settings,
  Zap,
  Monitor,
  Cpu,
  HardDrive,
  ShieldCheck,
  ShieldAlert,
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  Wifi,
  Play,
  ChevronRight,
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

export function SrpsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Keep your workstation responsive under heavy AI agent load.
      </GoalBanner>

      <Section
        title="What Is SRPS?"
        icon={<Shield className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>SRPS (System Resource Protection Script)</Highlight> installs
          ananicy-cpp with 1700+ rules to automatically deprioritize background
          processes, plus sysmoni TUI for real-time monitoring. When AI agents
          run heavy builds, SRPS keeps your terminal responsive.
        </Paragraph>
        <Paragraph>
          Think of it as automatic resource management: compilers, bundlers, and
          test runners get deprioritized so your interactive sessions stay snappy.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Cpu className="h-5 w-5" />}
              title="1700+ Rules"
              description="Pre-configured for compilers, bundlers, browsers, IDEs"
              gradient="from-yellow-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="sysmoni TUI"
              description="Real-time CPU/memory monitoring with ananicy status"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Gauge className="h-5 w-5" />}
              title="Sysctl Tweaks"
              description="Kernel optimizations for responsiveness under memory pressure"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Settings className="h-5 w-5" />}
              title="Zero Config"
              description="Install once, benefits forever - no tuning needed"
              gradient="from-sky-500/20 to-blue-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveResourceMonitor />
      </div>

      <Divider />

      <Section
        title="Installation"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          SRPS installs the ananicy-cpp daemon and sysmoni monitoring tool in
          one command.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Install SRPS with all components
$ curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh | bash -s -- --install

# Verify daemon is running
$ systemctl status ananicy-cpp
> Active: active (running)`}
            language="bash"
          />
        </div>

        <TipBox variant="info">
          Installation requires sudo for systemd service setup and sysctl changes.
          The script will prompt for confirmation before making system changes.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Real-Time Monitoring with sysmoni"
        icon={<Monitor className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          The <Highlight>sysmoni</Highlight> TUI shows real-time CPU and memory
          usage per process, along with the ananicy rule being applied to each.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Launch the monitoring TUI
$ sysmoni

# See per-process CPU/memory with ananicy rule status
# q to quit, arrows to navigate, s to sort, f to filter`}
            language="bash"
          />
        </div>

        <BulletList
          items={[
            "Per-process CPU and memory usage",
            "ananicy rule status for each process",
            "Nice level and scheduling class",
            "Real-time updates (configurable interval)",
          ]}
        />
      </Section>

      <Divider />

      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.25}
      >
        <CommandList
          commands={[
            {
              command: "sysmoni",
              description: "Launch real-time process monitoring TUI",
            },
            {
              command: "systemctl status ananicy-cpp",
              description: "Check daemon status",
            },
            {
              command: "ls /etc/ananicy.d/",
              description: "List active rule directories",
            },
            {
              command: "journalctl -u ananicy-cpp",
              description: "View daemon logs",
            },
            {
              command: "sudo systemctl restart ananicy-cpp",
              description: "Restart after adding custom rules",
            },
          ]}
        />
      </Section>

      <Divider />

      <Section
        title="What Gets Managed"
        icon={<Gauge className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          SRPS automatically deprioritizes resource-intensive processes while
          keeping interactive sessions responsive:
        </Paragraph>

        <BulletList
          items={[
            <>
              <Highlight>Compilers:</Highlight> rustc, gcc, clang, tsc, swc
            </>,
            <>
              <Highlight>Bundlers:</Highlight> webpack, esbuild, vite, rollup
            </>,
            <>
              <Highlight>Test runners:</Highlight> cargo test, jest, pytest
            </>,
            <>
              <Highlight>Browsers:</Highlight> Chrome, Firefox, Electron apps
            </>,
            <>
              <Highlight>IDEs:</Highlight> VS Code, JetBrains, language servers
            </>,
          ]}
        />

        <TipBox variant="tip">
          Your terminal emulator, tmux sessions, and input handling stay at
          normal priority. Heavy builds run in the background without freezing
          your interactive work.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Adding Custom Rules"
        icon={<Settings className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          You can add rules for any process that SRPS does not know about.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Example: add rule for a custom heavy process
$ echo '{"name": "my-heavy-process", "nice": 19, "sched": "idle", "ioclass": "idle"}' | \\
    sudo tee /etc/ananicy.d/00-default/99-custom.rules

# Restart to apply
$ sudo systemctl restart ananicy-cpp`}
            language="bash"
          />
        </div>

        <TipBox variant="warning">
          Be careful with nice values below 0 (higher priority). Only root can
          set negative nice values, and overusing them can make your system less
          responsive, not more.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Synergies with Other Tools"
        icon={<Zap className="h-5 w-5" />}
        delay={0.4}
      >
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6"
        >
          <BulletList
            items={[
              <>
                <Highlight>ntm:</Highlight> Keeps tmux sessions responsive when
                agents spawn heavy builds
              </>,
              <>
                <Highlight>slb:</Highlight> Prevents multiple agents from
                starving each other for CPU/memory
              </>,
              <>
                <Highlight>dcg:</Highlight> Combined safety - DCG prevents
                destructive commands, SRPS prevents resource exhaustion
              </>,
            ]}
          />
        </motion.div>

        <TipBox variant="info">
          When running multi-agent sessions with SLB, SRPS is especially valuable.
          Each agent may spawn compilers, test runners, and other heavy processes.
          SRPS ensures they do not overwhelm your system.
        </TipBox>
      </Section>

      <Divider />

      <Section
        title="Troubleshooting"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          If SRPS is not working as expected, check these common issues:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <CodeBlock
            code={`# Check if daemon is running
$ systemctl status ananicy-cpp

# View recent logs
$ journalctl -u ananicy-cpp -n 50

# Validate all rule files
$ ananicy-cpp --config-test

# Uninstall if needed
$ curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh | bash -s -- --uninstall`}
            language="bash"
          />
        </div>

        <TipBox variant="info">
          If you need to temporarily disable SRPS, use{" "}
          <Highlight>sudo systemctl stop ananicy-cpp</Highlight>. Re-enable with{" "}
          <Highlight>sudo systemctl start ananicy-cpp</Highlight>.
        </TipBox>
      </Section>
    </div>
  );
}

export default SrpsLesson;

// ---------------------------------------------------------------------------
// Interactive Resource Monitor -- System Resource Monitoring Center
// ---------------------------------------------------------------------------

interface ScenarioConfig {
  id: string;
  label: string;
  description: string;
  icon: React.ReactNode;
  cpuProfile: number[];
  memProfile: number[];
  swapPressure: number;
  diskReadProfile: number[];
  diskWriteProfile: number[];
  netUpload: number;
  netDownload: number;
  oomRisk: boolean;
  governorKicks: boolean;
}

const SCENARIOS: ScenarioConfig[] = [
  {
    id: "normal",
    label: "Normal Operation",
    description: "Agents idle or doing light work",
    icon: <Activity className="h-4 w-4" />,
    cpuProfile: [8, 5, 12, 3, 6, 2, 9, 4],
    memProfile: [22, 18, 15, 10],
    swapPressure: 2,
    diskReadProfile: [5, 12, 3, 8],
    diskWriteProfile: [2, 6, 1, 4],
    netUpload: 8,
    netDownload: 15,
    oomRisk: false,
    governorKicks: false,
  },
  {
    id: "cargo-build",
    label: "cargo build",
    description: "Agent-1 compiles a large Rust project",
    icon: <Cpu className="h-4 w-4" />,
    cpuProfile: [95, 92, 88, 94, 90, 87, 93, 91],
    memProfile: [55, 18, 15, 10],
    swapPressure: 5,
    diskReadProfile: [65, 12, 3, 8],
    diskWriteProfile: [45, 6, 1, 4],
    netUpload: 12,
    netDownload: 35,
    oomRisk: false,
    governorKicks: true,
  },
  {
    id: "memory-pressure",
    label: "Memory Pressure",
    description: "Multiple agents allocating large buffers",
    icon: <Monitor className="h-4 w-4" />,
    cpuProfile: [35, 28, 40, 32, 22, 18, 25, 20],
    memProfile: [72, 58, 45, 38],
    swapPressure: 65,
    diskReadProfile: [20, 15, 10, 12],
    diskWriteProfile: [55, 40, 30, 25],
    netUpload: 5,
    netDownload: 10,
    oomRisk: true,
    governorKicks: true,
  },
  {
    id: "disk-filling",
    label: "Disk Filling",
    description: "Agent writing large build artifacts",
    icon: <HardDrive className="h-4 w-4" />,
    cpuProfile: [25, 20, 15, 18, 12, 10, 14, 8],
    memProfile: [30, 22, 18, 15],
    swapPressure: 8,
    diskReadProfile: [15, 10, 8, 12],
    diskWriteProfile: [92, 78, 65, 55],
    netUpload: 3,
    netDownload: 8,
    oomRisk: false,
    governorKicks: true,
  },
  {
    id: "network-saturation",
    label: "Network Saturation",
    description: "Agents pulling deps and pushing artifacts",
    icon: <Wifi className="h-4 w-4" />,
    cpuProfile: [18, 15, 22, 12, 20, 10, 16, 8],
    memProfile: [25, 20, 18, 12],
    swapPressure: 4,
    diskReadProfile: [30, 25, 20, 15],
    diskWriteProfile: [35, 28, 22, 18],
    netUpload: 85,
    netDownload: 92,
    oomRisk: false,
    governorKicks: true,
  },
  {
    id: "governor-intervention",
    label: "Governor Saves Day",
    description: "All agents spike, governor throttles them",
    icon: <Shield className="h-4 w-4" />,
    cpuProfile: [88, 85, 92, 78, 82, 75, 90, 80],
    memProfile: [68, 55, 48, 42],
    swapPressure: 45,
    diskReadProfile: [55, 40, 35, 30],
    diskWriteProfile: [65, 50, 42, 38],
    netUpload: 55,
    netDownload: 70,
    oomRisk: true,
    governorKicks: true,
  },
];

interface ProcessEntry {
  pid: number;
  name: string;
  agent: string;
  cpu: number;
  mem: number;
  nice: number;
  ioClass: string;
  rule: string;
}

const AGENT_COLORS = [
  "text-orange-400",
  "text-sky-400",
  "text-violet-400",
  "text-amber-400",
] as const;

const AGENT_BG_COLORS = [
  "bg-orange-400",
  "bg-sky-400",
  "bg-violet-400",
  "bg-amber-400",
] as const;

const TERMINAL_LINES = [
  { cmd: "$ sysmoni", delay: 0 },
  { cmd: "  Monitoring 47 processes with ananicy-cpp rules", delay: 1.2 },
  { cmd: "$ systemctl status ananicy-cpp", delay: 2.8 },
  { cmd: "  Active: active (running) since Mon 2026-03-09 14:32:01 UTC", delay: 3.6 },
  { cmd: "$ cat /etc/ananicy.d/00-default/rustc.rules", delay: 5.0 },
  { cmd: '  {"name": "rustc", "nice": 19, "sched": "idle", "ioclass": "idle"}', delay: 5.8 },
  { cmd: "$ srps --status", delay: 7.2 },
  { cmd: "  Governor: active | Throttled: 4 processes | Uptime: 72h", delay: 8.0 },
];

function useAnimationFrame(callback: (dt: number) => void, active: boolean) {
  const callbackRef = useRef(callback);

  useEffect(() => {
    callbackRef.current = callback;
  });

  useEffect(() => {
    if (!active) return;
    let prev = performance.now();
    let id: number;
    const loop = (now: number) => {
      const dt = (now - prev) / 1000;
      prev = now;
      callbackRef.current(dt);
      id = requestAnimationFrame(loop);
    };
    id = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(id);
  }, [active]);
}

function clamp(v: number, min: number, max: number) {
  return Math.max(min, Math.min(max, v));
}

function InteractiveResourceMonitor() {
  const [srpsActive, setSrpsActive] = useState(false);
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const scenario = SCENARIOS[scenarioIdx];

  // Use useState initializer to avoid Math.random in render/useMemo
  const [initialSeeds] = useState<number[]>(() =>
    Array.from({ length: 16 }, () => Math.random() * 1000)
  );

  // CPU cores (8)
  const [coreLoads, setCoreLoads] = useState<number[]>([12, 10, 8, 6, 9, 5, 7, 4]);
  // Memory per agent (4 agents)
  const [memValues, setMemValues] = useState<number[]>([22, 18, 15, 10]);
  const [swapUsage, setSwapUsage] = useState(2);
  // Disk I/O per process (4 agents): [read, write] each
  const [diskReads, setDiskReads] = useState<number[]>([5, 12, 3, 8]);
  const [diskWrites, setDiskWrites] = useState<number[]>([2, 6, 1, 4]);
  // Network
  const [netUp, setNetUp] = useState(8);
  const [netDown, setNetDown] = useState(15);
  // Network history for chart
  const [netHistory, setNetHistory] = useState<Array<{ up: number; down: number }>>(() =>
    Array.from({ length: 30 }, () => ({ up: 8, down: 15 }))
  );
  // Terminal output
  const [terminalVisibleLines, setTerminalVisibleLines] = useState(0);
  const termTimerRef = useRef(0);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  // Process table
  const [sortColumn, setSortColumn] = useState<"cpu" | "mem">("cpu");

  // Derived values
  const totalCpu = useMemo(
    () => coreLoads.reduce((a, b) => a + b, 0) / 8,
    [coreLoads]
  );
  const totalMem = useMemo(
    () => memValues.reduce((a, b) => a + b, 0),
    [memValues]
  );
  const totalDiskRead = useMemo(
    () => diskReads.reduce((a, b) => a + b, 0) / 4,
    [diskReads]
  );
  const totalDiskWrite = useMemo(
    () => diskWrites.reduce((a, b) => a + b, 0) / 4,
    [diskWrites]
  );

  const systemOverloaded = !srpsActive && totalCpu > 80;
  const oomWarning = !srpsActive && scenario.oomRisk && totalMem > 150;
  const governorVisible = srpsActive && scenario.governorKicks;

  const processTable: ProcessEntry[] = useMemo(() => {
    const agentNames = ["rustc", "webpack", "jest", "tsc"];
    const agentLabels = ["agent-1", "agent-2", "agent-3", "agent-4"];
    const rules = ["compile.rules", "bundle.rules", "test.rules", "check.rules"];
    const pids = [14823, 14901, 15042, 15108];

    const entries = agentNames.map((name, i) => ({
      pid: pids[i],
      name,
      agent: agentLabels[i],
      cpu: coreLoads[i * 2] + coreLoads[i * 2 + 1],
      mem: memValues[i],
      nice: srpsActive ? 19 : 0,
      ioClass: srpsActive ? "idle" : "best-effort",
      rule: srpsActive ? rules[i] : "none",
    }));

    return entries.sort((a, b) =>
      sortColumn === "cpu" ? b.cpu - a.cpu : b.mem - a.mem
    );
  }, [coreLoads, memValues, srpsActive, sortColumn]);

  const simulate = useCallback(
    (dt: number) => {
      const now = Date.now();

      setCoreLoads((prev) =>
        prev.map((val, i) => {
          const target = scenario.cpuProfile[i];
          const seed = initialSeeds[i];
          const noise =
            Math.sin(now / (400 + seed)) * 5 +
            Math.cos(now / (600 + seed * 0.7)) * 3;

          if (srpsActive) {
            const throttled = target * 0.3 + noise * 0.3;
            return clamp(val + (throttled - val) * dt * 3, 2, 35);
          }
          const full = target + noise * 1.5;
          return clamp(val + (full - val) * dt * 2.5, 5, 99);
        })
      );

      setMemValues((prev) =>
        prev.map((val, i) => {
          const target = scenario.memProfile[i];
          const seed = initialSeeds[i + 8];
          const noise =
            Math.cos(now / (500 + seed)) * 3 +
            Math.sin(now / (700 + seed * 0.5)) * 2;

          if (srpsActive) {
            const throttled = target * 0.45 + noise * 0.2;
            return clamp(val + (throttled - val) * dt * 2.5, 3, 35);
          }
          const full = target + noise;
          return clamp(val + (full - val) * dt * 1.8, 5, 80);
        })
      );

      setSwapUsage((prev) => {
        const target = scenario.swapPressure;
        const noise = Math.sin(now / 800) * 3;
        if (srpsActive) {
          const throttled = target * 0.2 + noise * 0.2;
          return clamp(prev + (throttled - prev) * dt * 2, 0, 15);
        }
        return clamp(prev + (target + noise - prev) * dt * 1.5, 0, 90);
      });

      setDiskReads((prev) =>
        prev.map((val, i) => {
          const target = scenario.diskReadProfile[i];
          const seed = initialSeeds[i + 4];
          const noise = Math.sin(now / (350 + seed)) * 8;
          if (srpsActive) {
            const throttled = target * 0.3 + noise * 0.3;
            return clamp(val + (throttled - val) * dt * 3, 1, 30);
          }
          return clamp(val + (target + noise - val) * dt * 2, 2, 98);
        })
      );

      setDiskWrites((prev) =>
        prev.map((val, i) => {
          const target = scenario.diskWriteProfile[i];
          const seed = initialSeeds[i + 12];
          const noise = Math.cos(now / (420 + seed)) * 6;
          if (srpsActive) {
            const throttled = target * 0.25 + noise * 0.2;
            return clamp(val + (throttled - val) * dt * 3, 1, 25);
          }
          return clamp(val + (target + noise - val) * dt * 2, 1, 98);
        })
      );

      setNetUp((prev) => {
        const target = scenario.netUpload;
        const noise = Math.sin(now / 600) * 5;
        if (srpsActive) {
          const throttled = target * 0.35 + noise * 0.3;
          return clamp(prev + (throttled - prev) * dt * 2.5, 1, 30);
        }
        return clamp(prev + (target + noise - prev) * dt * 2, 1, 98);
      });

      setNetDown((prev) => {
        const target = scenario.netDownload;
        const noise = Math.cos(now / 550) * 6;
        if (srpsActive) {
          const throttled = target * 0.3 + noise * 0.3;
          return clamp(prev + (throttled - prev) * dt * 2.5, 1, 35);
        }
        return clamp(prev + (target + noise - prev) * dt * 2, 1, 98);
      });

      // Network history (sampled every ~200ms)
      setNetHistory((prev) => {
        const last = prev[prev.length - 1];
        // Only push a new sample every ~200ms worth of accumulated dt
        if (last) {
          const newEntry = {
            up: clamp(
              srpsActive
                ? scenario.netUpload * 0.35 + Math.sin(now / 600) * 3
                : scenario.netUpload + Math.sin(now / 600) * 5,
              1,
              98
            ),
            down: clamp(
              srpsActive
                ? scenario.netDownload * 0.3 + Math.cos(now / 550) * 4
                : scenario.netDownload + Math.cos(now / 550) * 6,
              1,
              98
            ),
          };
          const next = [...prev.slice(-29), newEntry];
          return next;
        }
        return prev;
      });

      // Terminal line progression
      termTimerRef.current += dt;
    },
    [srpsActive, scenario, initialSeeds]
  );

  // Terminal line advancement via setTimeout in useEffect
  useEffect(() => {
    if (terminalVisibleLines >= TERMINAL_LINES.length) return;
    const nextLine = TERMINAL_LINES[terminalVisibleLines];
    const delay = terminalVisibleLines === 0 ? 500 : nextLine.delay * 300;
    const timeout = setTimeout(() => {
      setTerminalVisibleLines((v) => v + 1);
    }, delay);
    return () => clearTimeout(timeout);
  }, [terminalVisibleLines]);

  useAnimationFrame(simulate, inView);

  // Cycle terminal lines
  useEffect(() => {
    if (!inView) return;
    const interval = setInterval(() => {
      setTerminalVisibleLines(0);
      // Defer the reset using setTimeout so we don't setState synchronously in effect
      setTimeout(() => {
        termTimerRef.current = 0;
      }, 0);
    }, 12000);
    return () => clearInterval(interval);
  }, [inView]);

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-emerald-500/[0.04] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-56 h-56 bg-sky-500/[0.03] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 lg:p-8 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <p className="text-sm font-semibold text-white/80">
            System Resource Monitoring Center
          </p>
          <p className="text-xs text-white/50">
            Select a scenario and toggle SRPS to see real-time resource
            protection in action
          </p>
        </div>

        {/* Scenario selector */}
        <ScenarioSelector
          scenarios={SCENARIOS}
          activeIdx={scenarioIdx}
          onSelect={setScenarioIdx}
        />

        {/* Mode toggle */}
        <div className="flex justify-center">
          <motion.button
            type="button"
            onClick={() => setSrpsActive((v) => !v)}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`relative flex items-center gap-3 rounded-2xl border px-6 py-3 font-medium text-sm transition-colors ${
              srpsActive
                ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-300"
                : "border-red-500/30 bg-red-500/[0.06] text-red-300"
            }`}
          >
            <AnimatePresence mode="wait">
              {srpsActive ? (
                <motion.div
                  key="active"
                  initial={{ rotate: -30, scale: 0.5, opacity: 0 }}
                  animate={{ rotate: 0, scale: 1, opacity: 1 }}
                  exit={{ rotate: 30, scale: 0.5, opacity: 0 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                >
                  <ShieldCheck className="h-5 w-5" />
                </motion.div>
              ) : (
                <motion.div
                  key="inactive"
                  initial={{ rotate: 30, scale: 0.5, opacity: 0 }}
                  animate={{ rotate: 0, scale: 1, opacity: 1 }}
                  exit={{ rotate: -30, scale: 0.5, opacity: 0 }}
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                >
                  <ShieldAlert className="h-5 w-5" />
                </motion.div>
              )}
            </AnimatePresence>

            <span>{srpsActive ? "SRPS Active" : "Unprotected"}</span>

            <div
              className={`relative h-6 w-11 rounded-full transition-colors ${
                srpsActive ? "bg-emerald-500/30" : "bg-red-500/20"
              }`}
            >
              <motion.div
                animate={{ x: srpsActive ? 20 : 2 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
                className={`absolute top-1 h-4 w-4 rounded-full ${
                  srpsActive ? "bg-emerald-400" : "bg-red-400"
                }`}
              />
            </div>
          </motion.button>
        </div>

        {/* System status indicator */}
        <SystemStatusBanner
          systemOverloaded={systemOverloaded}
          oomWarning={oomWarning}
          srpsActive={srpsActive}
          scenarioLabel={scenario.label}
        />

        {/* Main dashboard grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Left column */}
          <div className="space-y-4">
            {/* CPU Cores */}
            <CpuCorePanel coreLoads={coreLoads} srpsActive={srpsActive} />

            {/* Memory + Swap */}
            <MemoryPanel
              memValues={memValues}
              swapUsage={swapUsage}
              oomWarning={oomWarning}
              srpsActive={srpsActive}
              active={inView}
            />
          </div>

          {/* Right column */}
          <div className="space-y-4">
            {/* Disk I/O */}
            <DiskIoPanel
              diskReads={diskReads}
              diskWrites={diskWrites}
              totalRead={totalDiskRead}
              totalWrite={totalDiskWrite}
            />

            {/* Network */}
            <NetworkPanel
              netUp={netUp}
              netDown={netDown}
              netHistory={netHistory}
            />
          </div>
        </div>

        {/* Process Table */}
        <ProcessTable
          processes={processTable}
          sortColumn={sortColumn}
          onSortChange={setSortColumn}
          srpsActive={srpsActive}
        />

        {/* Governor Panel */}
        <AnimatePresence>
          {governorVisible && srpsActive && (
            <GovernorPanel scenario={scenario} totalCpu={totalCpu} active={inView} />
          )}
        </AnimatePresence>

        {/* Mini Terminal */}
        <MiniTerminal visibleLines={terminalVisibleLines} active={inView} />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Scenario Selector
// ---------------------------------------------------------------------------

function ScenarioSelector({
  scenarios,
  activeIdx,
  onSelect,
}: {
  scenarios: ScenarioConfig[];
  activeIdx: number;
  onSelect: (idx: number) => void;
}) {
  return (
    <div className="flex flex-wrap justify-center gap-2">
      {scenarios.map((s, i) => (
        <motion.button
          key={s.id}
          type="button"
          onClick={() => onSelect(i)}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className={`flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-medium transition-colors ${
            activeIdx === i
              ? "border-primary/40 bg-primary/10 text-primary"
              : "border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/70 hover:border-white/[0.15]"
          }`}
        >
          {s.icon}
          <span className="hidden sm:inline">{s.label}</span>
          <span className="sm:hidden">
            {s.label.length > 10 ? s.label.slice(0, 10) : s.label}
          </span>
        </motion.button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// System Status Banner
// ---------------------------------------------------------------------------

function SystemStatusBanner({
  systemOverloaded,
  oomWarning,
  srpsActive,
  scenarioLabel,
}: {
  systemOverloaded: boolean;
  oomWarning: boolean;
  srpsActive: boolean;
  scenarioLabel: string;
}) {
  return (
    <AnimatePresence mode="wait">
      {systemOverloaded ? (
        <motion.div
          key="overloaded"
          initial={{ opacity: 0, y: 8 }}
          animate={{
            opacity: 1,
            y: 0,
            x: [0, -2, 2, -1, 1, 0],
          }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center justify-center gap-2 rounded-xl border border-red-500/30 bg-red-500/[0.08] px-4 py-2"
        >
          <AlertTriangle className="h-4 w-4 text-red-400 animate-pulse" />
          <span className="text-xs font-medium text-red-400">
            System Unresponsive &mdash; CPU Exhausted ({scenarioLabel})
          </span>
        </motion.div>
      ) : oomWarning ? (
        <motion.div
          key="oom"
          initial={{ opacity: 0, y: 8 }}
          animate={{
            opacity: 1,
            y: 0,
            x: [0, -1, 1, 0],
          }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center justify-center gap-2 rounded-xl border border-orange-500/30 bg-orange-500/[0.08] px-4 py-2"
        >
          <AlertTriangle className="h-4 w-4 text-orange-400 animate-pulse" />
          <span className="text-xs font-medium text-orange-400">
            OOM Risk &mdash; Memory Pressure Critical
          </span>
        </motion.div>
      ) : srpsActive ? (
        <motion.div
          key="protected"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center justify-center gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/[0.06] px-4 py-2"
        >
          <ShieldCheck className="h-4 w-4 text-emerald-400" />
          <span className="text-xs font-medium text-emerald-400">
            System Responsive &mdash; SRPS Governor Active
          </span>
        </motion.div>
      ) : (
        <motion.div
          key="warning"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
          className="flex items-center justify-center gap-2 rounded-xl border border-amber-500/30 bg-amber-500/[0.06] px-4 py-2"
        >
          <Activity className="h-4 w-4 text-amber-400" />
          <span className="text-xs font-medium text-amber-400">
            No Protection &mdash; Resources Climbing
          </span>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

// ---------------------------------------------------------------------------
// CPU Core Panel -- 8 animated cores
// ---------------------------------------------------------------------------

function CpuCorePanel({
  coreLoads,
  srpsActive,
}: {
  coreLoads: number[];
  srpsActive: boolean;
}) {
  const avgLoad = coreLoads.length > 0 ? coreLoads.reduce((a, b) => a + b, 0) / coreLoads.length : 0;

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Cpu className="h-4 w-4 text-primary" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            CPU Cores
          </span>
        </div>
        <span
          className={`font-mono text-xs ${
            avgLoad > 80
              ? "text-red-400"
              : avgLoad > 50
                ? "text-amber-400"
                : "text-emerald-400"
          }`}
        >
          Avg {Math.round(avgLoad)}%
        </span>
      </div>

      <div className="grid grid-cols-4 gap-2">
        {coreLoads.map((load, i) => (
          <CoreBar key={i} coreIndex={i} load={load} srpsActive={srpsActive} />
        ))}
      </div>

      {/* Aggregate bar */}
      <div className="space-y-1">
        <div className="flex items-center justify-between text-[10px] text-white/40">
          <span>Total System CPU</span>
          <span className="font-mono">{Math.round(avgLoad)}%</span>
        </div>
        <div className="h-2 w-full rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className={`h-full rounded-full ${getBarColorClass(avgLoad, 100)}`}
            animate={{ width: `${clamp(avgLoad, 0, 100)}%` }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
          />
        </div>
      </div>
    </div>
  );
}

function CoreBar({
  coreIndex,
  load,
  srpsActive,
}: {
  coreIndex: number;
  load: number;
  srpsActive: boolean;
}) {
  const colorClass = getBarColorClass(load, 100);
  const glowClass = getBarGlowClass(load, 100);

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="text-[10px] text-white/40 font-mono">
          C{coreIndex}
        </span>
        <span
          className={`text-[10px] font-mono ${
            load > 80
              ? "text-red-400"
              : load > 50
                ? "text-amber-400"
                : "text-white/50"
          }`}
        >
          {Math.round(load)}%
        </span>
      </div>
      <div className="h-16 w-full rounded-lg bg-white/[0.04] overflow-hidden flex flex-col-reverse">
        <motion.div
          className={`w-full rounded-lg ${colorClass} ${glowClass}`}
          animate={{ height: `${clamp(load, 0, 100)}%` }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
        />
      </div>
      {srpsActive && load < 35 && (
        <div className="text-center">
          <span className="text-[10px] text-emerald-400/60">throttled</span>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Memory Panel
// ---------------------------------------------------------------------------

function MemoryPanel({
  memValues,
  swapUsage,
  oomWarning,
  srpsActive,
  active,
}: {
  memValues: number[];
  swapUsage: number;
  oomWarning: boolean;
  srpsActive: boolean;
  active: boolean;
}) {
  const totalMem = memValues.reduce((a, b) => a + b, 0);
  const memPct = clamp(totalMem / 2, 0, 100); // Assuming ~200% scale for 4 agents
  const swapPct = clamp(swapUsage, 0, 100);
  const agentNames = ["rustc", "webpack", "jest", "tsc"];

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Monitor className="h-4 w-4 text-violet-400" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            Memory
          </span>
        </div>
        <div className="flex items-center gap-2">
          {oomWarning && (
            <motion.span
              animate={active ? { opacity: [0.5, 1, 0.5] } : { opacity: 0.5 }}
              transition={active ? { duration: 1.2, repeat: Infinity } : { duration: 0.2 }}
              className="text-[10px] font-bold text-red-400 uppercase"
            >
              OOM RISK
            </motion.span>
          )}
          <span className="font-mono text-xs text-white/50">
            {Math.round(totalMem)}% used
          </span>
        </div>
      </div>

      {/* Circular gauge */}
      <div className="flex items-center gap-4">
        <MemoryGauge percentage={memPct} oomRisk={oomWarning} active={active} />

        <div className="flex-1 space-y-2">
          {agentNames.map((name, i) => (
            <div key={name} className="space-y-0.5">
              <div className="flex items-center justify-between">
                <span className={`text-[10px] font-mono ${AGENT_COLORS[i]}`}>
                  {name}
                </span>
                <span className="text-[10px] font-mono text-white/40">
                  {Math.round(memValues[i])}%
                </span>
              </div>
              <div className="h-1.5 w-full rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${AGENT_BG_COLORS[i]}`}
                  animate={{
                    width: `${clamp(memValues[i], 0, 100)}%`,
                  }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                  }}
                  style={{ opacity: 0.7 }}
                />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Swap bar */}
      <div className="space-y-1 pt-1 border-t border-white/[0.06]">
        <div className="flex items-center justify-between text-[10px]">
          <span className="text-white/40">Swap Usage</span>
          <span
            className={`font-mono ${swapPct > 50 ? "text-red-400" : swapPct > 25 ? "text-amber-400" : "text-white/50"}`}
          >
            {Math.round(swapPct)}%
          </span>
        </div>
        <div className="h-1.5 w-full rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className={`h-full rounded-full ${getBarColorClass(swapPct, 100)}`}
            animate={{ width: `${swapPct}%` }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
          />
        </div>
        {srpsActive && (
          <span className="text-[10px] text-emerald-400/60">
            Swap pressure managed by sysctl tweaks
          </span>
        )}
      </div>
    </div>
  );
}

function MemoryGauge({
  percentage,
  oomRisk,
  active,
}: {
  percentage: number;
  oomRisk: boolean;
  active: boolean;
}) {
  const radius = 32;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percentage / 100) * circumference;
  const gaugeColor =
    percentage > 80
      ? "stroke-red-500"
      : percentage > 55
        ? "stroke-amber-500"
        : percentage > 35
          ? "stroke-yellow-500"
          : "stroke-emerald-500";

  return (
    <div className="relative flex-shrink-0">
      <svg width="80" height="80" className="-rotate-90">
        <circle
          cx="40"
          cy="40"
          r={radius}
          fill="none"
          stroke="rgba(255,255,255,0.06)"
          strokeWidth="6"
        />
        <motion.circle
          cx="40"
          cy="40"
          r={radius}
          fill="none"
          className={gaugeColor}
          strokeWidth="6"
          strokeLinecap="round"
          strokeDasharray={circumference}
          animate={{ strokeDashoffset: offset }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span
          className={`text-sm font-bold font-mono ${oomRisk ? "text-red-400" : "text-white/70"}`}
        >
          {Math.round(percentage)}%
        </span>
        <span className="text-[10px] text-white/40">MEM</span>
      </div>
      {oomRisk && (
        <motion.div
          className="absolute -top-1 -right-1"
          animate={active ? { scale: [1, 1.2, 1] } : { scale: 1 }}
          transition={active ? { duration: 0.8, repeat: Infinity } : { duration: 0.2 }}
        >
          <AlertTriangle className="h-3.5 w-3.5 text-red-400" />
        </motion.div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Disk I/O Panel
// ---------------------------------------------------------------------------

function DiskIoPanel({
  diskReads,
  diskWrites,
  totalRead,
  totalWrite,
}: {
  diskReads: number[];
  diskWrites: number[];
  totalRead: number;
  totalWrite: number;
}) {
  const agentNames = ["rustc", "webpack", "jest", "tsc"];

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <HardDrive className="h-4 w-4 text-amber-400" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            Disk I/O
          </span>
        </div>
        <div className="flex items-center gap-3 text-[10px] font-mono">
          <span className="text-sky-400">
            R {Math.round(totalRead)} MB/s
          </span>
          <span className="text-orange-400">
            W {Math.round(totalWrite)} MB/s
          </span>
        </div>
      </div>

      {/* Waterfall bars */}
      <div className="space-y-2">
        {agentNames.map((name, i) => (
          <div key={name} className="space-y-1">
            <div className="flex items-center justify-between">
              <span className={`text-[10px] font-mono ${AGENT_COLORS[i]}`}>
                {name}
              </span>
              <span className="text-[10px] font-mono text-white/30">
                R:{Math.round(diskReads[i])} W:{Math.round(diskWrites[i])}
              </span>
            </div>
            <div className="flex gap-1">
              {/* Read bar */}
              <div className="flex-1 h-2 rounded-full bg-white/[0.04] overflow-hidden">
                <motion.div
                  className="h-full rounded-full bg-sky-500/70"
                  animate={{
                    width: `${clamp(diskReads[i], 0, 100)}%`,
                  }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                  }}
                />
              </div>
              {/* Write bar */}
              <div className="flex-1 h-2 rounded-full bg-white/[0.04] overflow-hidden">
                <motion.div
                  className="h-full rounded-full bg-orange-500/70"
                  animate={{
                    width: `${clamp(diskWrites[i], 0, 100)}%`,
                  }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                  }}
                />
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Legend */}
      <div className="flex items-center gap-4 pt-1 border-t border-white/[0.06]">
        <div className="flex items-center gap-1">
          <div className="h-2 w-2 rounded-full bg-sky-500/70" />
          <span className="text-[10px] text-white/40">Read</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="h-2 w-2 rounded-full bg-orange-500/70" />
          <span className="text-[10px] text-white/40">Write</span>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Network Panel
// ---------------------------------------------------------------------------

function NetworkPanel({
  netUp,
  netDown,
  netHistory,
}: {
  netUp: number;
  netDown: number;
  netHistory: Array<{ up: number; down: number }>;
}) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Wifi className="h-4 w-4 text-sky-400" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            Network
          </span>
        </div>
        <div className="flex items-center gap-3 text-[10px] font-mono">
          <span className="flex items-center gap-0.5 text-emerald-400">
            <ArrowUp className="h-3 w-3" />
            {Math.round(netUp)} Mbps
          </span>
          <span className="flex items-center gap-0.5 text-sky-400">
            <ArrowDown className="h-3 w-3" />
            {Math.round(netDown)} Mbps
          </span>
        </div>
      </div>

      {/* Mini bandwidth chart */}
      <NetworkChart history={netHistory} />

      {/* Upload / Download gauges */}
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1">
          <div className="flex items-center justify-between text-[10px]">
            <span className="text-white/40 flex items-center gap-1">
              <ArrowUp className="h-2.5 w-2.5 text-emerald-400" />
              Upload
            </span>
            <span className="font-mono text-emerald-400">
              {Math.round(netUp)}%
            </span>
          </div>
          <div className="h-2 w-full rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className="h-full rounded-full bg-emerald-500/70"
              animate={{ width: `${clamp(netUp, 0, 100)}%` }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            />
          </div>
        </div>
        <div className="space-y-1">
          <div className="flex items-center justify-between text-[10px]">
            <span className="text-white/40 flex items-center gap-1">
              <ArrowDown className="h-2.5 w-2.5 text-sky-400" />
              Download
            </span>
            <span className="font-mono text-sky-400">
              {Math.round(netDown)}%
            </span>
          </div>
          <div className="h-2 w-full rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className="h-full rounded-full bg-sky-500/70"
              animate={{ width: `${clamp(netDown, 0, 100)}%` }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function NetworkChart({
  history,
}: {
  history: Array<{ up: number; down: number }>;
}) {
  const width = 280;
  const height = 50;
  const points = history.length;

  const buildPath = (key: "up" | "down") => {
    const step = width / (points - 1);
    let d = "";
    history.forEach((entry, i) => {
      const x = i * step;
      const y = height - (entry[key] / 100) * height;
      if (i === 0) {
        d += `M ${x} ${y}`;
      } else {
        const prevX = (i - 1) * step;
        const prevY = height - (history[i - 1][key] / 100) * height;
        const cpx = (prevX + x) / 2;
        d += ` C ${cpx} ${prevY}, ${cpx} ${y}, ${x} ${y}`;
      }
    });
    return d;
  };

  const buildArea = (key: "up" | "down") => {
    const path = buildPath(key);
    const step = width / (points - 1);
    const lastX = (points - 1) * step;
    return `${path} L ${lastX} ${height} L 0 ${height} Z`;
  };

  return (
    <div className="rounded-lg bg-white/[0.02] border border-white/[0.05] p-2 overflow-hidden">
      <svg
        viewBox={`0 0 ${width} ${height}`}
        className="w-full h-12"
        preserveAspectRatio="none"
      >
        {/* Grid lines */}
        {[0.25, 0.5, 0.75].map((pct) => (
          <line
            key={pct}
            x1="0"
            y1={height * (1 - pct)}
            x2={width}
            y2={height * (1 - pct)}
            stroke="rgba(255,255,255,0.04)"
            strokeDasharray="4 4"
          />
        ))}

        {/* Download area + line */}
        <path d={buildArea("down")} fill="rgba(56,189,248,0.08)" />
        <path
          d={buildPath("down")}
          fill="none"
          stroke="rgba(56,189,248,0.5)"
          strokeWidth="1.5"
        />

        {/* Upload area + line */}
        <path d={buildArea("up")} fill="rgba(52,211,153,0.08)" />
        <path
          d={buildPath("up")}
          fill="none"
          stroke="rgba(52,211,153,0.5)"
          strokeWidth="1.5"
        />
      </svg>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Process Table
// ---------------------------------------------------------------------------

function ProcessTable({
  processes,
  sortColumn,
  onSortChange,
  srpsActive,
}: {
  processes: ProcessEntry[];
  sortColumn: "cpu" | "mem";
  onSortChange: (col: "cpu" | "mem") => void;
  srpsActive: boolean;
}) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Activity className="h-4 w-4 text-sky-400" />
          <span className="text-xs font-semibold text-white/70 uppercase tracking-wider">
            Process Table
          </span>
        </div>
        <div className="flex items-center gap-1 text-[10px] text-white/40">
          Sort by:
          <button
            type="button"
            onClick={() => onSortChange("cpu")}
            className={`px-1.5 py-0.5 rounded ${sortColumn === "cpu" ? "bg-white/10 text-white/80" : "hover:text-white/60"}`}
          >
            CPU
          </button>
          <button
            type="button"
            onClick={() => onSortChange("mem")}
            className={`px-1.5 py-0.5 rounded ${sortColumn === "mem" ? "bg-white/10 text-white/80" : "hover:text-white/60"}`}
          >
            MEM
          </button>
        </div>
      </div>

      {/* Table header */}
      <div className="grid grid-cols-12 gap-1 text-[10px] font-semibold text-white/40 uppercase tracking-wider border-b border-white/[0.06] pb-1.5">
        <span className="col-span-1">PID</span>
        <span className="col-span-2">Process</span>
        <span className="col-span-2">Agent</span>
        <span className="col-span-2 text-right">CPU%</span>
        <span className="col-span-2 text-right">MEM%</span>
        <span className="col-span-1 text-right">Nice</span>
        <span className="col-span-2 text-right">Rule</span>
      </div>

      {/* Rows */}
      <div className="space-y-1">
        {processes.map((proc, idx) => (
          <motion.div
            key={proc.pid}
            layout
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`grid grid-cols-12 gap-1 text-[10px] font-mono py-1.5 px-1 rounded-lg ${
              idx === 0
                ? "bg-white/[0.04] border border-white/[0.06]"
                : "hover:bg-white/[0.02]"
            }`}
          >
            <span className="col-span-1 text-white/40">{proc.pid}</span>
            <span className="col-span-2 text-white/70">{proc.name}</span>
            <span
              className={`col-span-2 ${AGENT_COLORS[["agent-1", "agent-2", "agent-3", "agent-4"].indexOf(proc.agent)]}`}
            >
              {proc.agent}
            </span>
            <span
              className={`col-span-2 text-right ${proc.cpu > 100 ? "text-red-400" : proc.cpu > 60 ? "text-amber-400" : "text-white/60"}`}
            >
              {Math.round(proc.cpu)}%
            </span>
            <span
              className={`col-span-2 text-right ${proc.mem > 60 ? "text-red-400" : proc.mem > 35 ? "text-amber-400" : "text-white/60"}`}
            >
              {Math.round(proc.mem)}%
            </span>
            <span
              className={`col-span-1 text-right ${srpsActive ? "text-emerald-400" : "text-white/40"}`}
            >
              {proc.nice}
            </span>
            <span
              className={`col-span-2 text-right truncate ${srpsActive ? "text-emerald-400/70" : "text-white/30"}`}
            >
              {proc.rule}
            </span>
          </motion.div>
        ))}
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between text-[10px] text-white/30 pt-1 border-t border-white/[0.06]">
        <span>4 agent processes tracked by ananicy-cpp</span>
        {srpsActive && (
          <motion.span
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-emerald-400/60 flex items-center gap-1"
          >
            <ShieldCheck className="h-2.5 w-2.5" />
            All throttled to nice +19, idle sched
          </motion.span>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Governor Panel
// ---------------------------------------------------------------------------

function GovernorPanel({
  scenario,
  totalCpu,
  active,
}: {
  scenario: ScenarioConfig;
  totalCpu: number;
  active: boolean;
}) {
  const throttleActions = [
    { process: "rustc", action: "nice +19, sched idle", savings: "~60% CPU" },
    {
      process: "webpack",
      action: "nice +15, ioclass idle",
      savings: "~45% CPU",
    },
    { process: "jest", action: "nice +19, sched batch", savings: "~50% CPU" },
    { process: "tsc", action: "nice +10, ioclass idle", savings: "~40% CPU" },
  ];

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9, y: 20 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.9, y: 20 }}
      transition={{ type: "spring", stiffness: 200, damping: 25 }}
      className="rounded-2xl border border-emerald-500/20 bg-emerald-500/[0.04] p-4 space-y-3"
    >
      <div className="flex items-center gap-3">
        <motion.div
          animate={
            active
              ? { rotate: [0, -5, 5, -3, 3, 0], scale: [1, 1.05, 1] }
              : { rotate: 0, scale: 1 }
          }
          transition={
            active
              ? { duration: 2, repeat: Infinity, repeatType: "reverse" }
              : { duration: 0.2 }
          }
        >
          <Shield className="h-8 w-8 text-emerald-400" />
        </motion.div>
        <div>
          <p className="text-sm font-semibold text-emerald-400">
            SRPS Governor Throttling
          </p>
          <p className="text-xs text-white/50 mt-0.5">
            Scenario: {scenario.label} &mdash; CPU reduced from{" "}
            {Math.round(totalCpu * 2.8)}% to {Math.round(totalCpu)}%
          </p>
        </div>
      </div>

      {/* Throttle action list */}
      <div className="space-y-1.5">
        {throttleActions.map((action) => (
          <motion.div
            key={action.process}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center gap-2 text-[10px]"
          >
            <ChevronRight className="h-3 w-3 text-emerald-500/50" />
            <span className="font-mono text-emerald-300 w-16">
              {action.process}
            </span>
            <span className="text-white/40">{action.action}</span>
            <span className="ml-auto text-emerald-400/70 font-mono">
              {action.savings}
            </span>
          </motion.div>
        ))}
      </div>

      {/* Governor stats */}
      <div className="flex items-center gap-4 pt-2 border-t border-emerald-500/10 text-[10px]">
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-full bg-emerald-400 animate-pulse" />
          <span className="text-white/50">Governor: active</span>
        </div>
        <span className="text-white/30">|</span>
        <span className="text-white/50">
          Rules matched: {scenario.governorKicks ? 4 : 0}
        </span>
        <span className="text-white/30">|</span>
        <span className="text-emerald-400/60">
          System responsiveness: optimal
        </span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Mini Terminal
// ---------------------------------------------------------------------------

function MiniTerminal({ visibleLines, active }: { visibleLines: number; active: boolean }) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-black/40 p-4 space-y-2 overflow-hidden">
      <div className="flex items-center gap-2 pb-2 border-b border-white/[0.06]">
        <div className="flex gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
          <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
        </div>
        <span className="text-[10px] text-white/40 font-mono">
          srps-terminal
        </span>
        <Play className="h-3 w-3 text-white/20 ml-auto" />
      </div>

      <div className="font-mono text-[11px] leading-relaxed space-y-0.5 min-h-[120px]">
        <AnimatePresence>
          {TERMINAL_LINES.slice(0, visibleLines).map((line, i) => (
            <motion.div
              key={`${line.cmd}-${i}`}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className={
                line.cmd.startsWith("$")
                  ? "text-emerald-400"
                  : line.cmd.startsWith("  Active:")
                    ? "text-sky-400/70"
                    : line.cmd.startsWith("  Governor:")
                      ? "text-amber-400/70"
                      : "text-white/50"
              }
            >
              {line.cmd}
              {i === visibleLines - 1 && line.cmd.startsWith("$") && (
                <motion.span
                  animate={active ? { opacity: [1, 0] } : { opacity: 1 }}
                  transition={
                    active
                      ? { duration: 0.6, repeat: Infinity, repeatType: "reverse" }
                      : { duration: 0.2 }
                  }
                  className="inline-block w-2 h-3.5 bg-emerald-400/70 ml-0.5 align-middle"
                />
              )}
            </motion.div>
          ))}
        </AnimatePresence>

        {visibleLines === 0 && (
          <div className="text-emerald-400">
            <span>$ </span>
            <motion.span
              animate={active ? { opacity: [1, 0] } : { opacity: 1 }}
              transition={
                active
                  ? { duration: 0.6, repeat: Infinity, repeatType: "reverse" }
                  : { duration: 0.2 }
              }
              className="inline-block w-2 h-3.5 bg-emerald-400/70 align-middle"
            />
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Shared utility functions
// ---------------------------------------------------------------------------

function getBarColorClass(value: number, max: number): string {
  const pct = value / max;
  if (pct > 0.8) return "bg-red-500";
  if (pct > 0.6) return "bg-amber-500";
  if (pct > 0.4) return "bg-yellow-500";
  return "bg-emerald-500";
}

function getBarGlowClass(value: number, max: number): string {
  const pct = value / max;
  if (pct > 0.8) return "shadow-red-500/40 shadow-[0_0_12px]";
  if (pct > 0.6) return "shadow-amber-500/30 shadow-[0_0_8px]";
  return "";
}
