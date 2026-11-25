"use client";

import {
  Activity,
  BarChart3,
  Bug,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock,
  Eye,
  Filter,
  Globe,
  Network,
  Play,
  Radio,
  RotateCcw,
  Settings,
  Shield,
  ShieldAlert,
  Terminal,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion, useInView } from "@/components/motion";
import {
  CodeBlock,
  CommandList,
  DiagramScroller,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function RanoLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        See which endpoints your AI CLIs and their child processes connect to, without a proxy or
        code changes.
      </GoalBanner>

      {/* Section 1: What Is RANO */}
      <Section title="What Is RANO?" icon={<Network className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>RANO</Highlight> is a network observer purpose-built for AI coding CLIs. It
          polls <code>/proc</code> (or macOS libproc) to map the sockets held by Claude Code, Codex
          CLI, Gemini CLI and their child processes to a PID and a provider. It is not a proxy and
          never sees request or response bodies.
        </Paragraph>
        <Paragraph>
          When agents behave unexpectedly, RANO shows which endpoints they connect to, how often
          they reconnect, and which process or subprocess holds each socket.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="No Proxy"
              description="Polls /proc or libproc"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Live Stats"
              description="Top providers, domains and IPs"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Filter className="h-5 w-5" />}
              title="Smart Filtering"
              description="Provider tagging per socket"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Bug className="h-5 w-5" />}
              title="SQLite History"
              description="report, diff and CSV/JSONL export"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveTrafficMonitor />
      </div>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Terminal className="h-5 w-5" />} delay={0.15}>
        <Paragraph>Run it in a spare terminal while your agents work.</Paragraph>

        <CommandList
          commands={[
            {
              command: "rano",
              description: "Observe claude/codex/gemini and their children (Ctrl+C stops)",
            },
            { command: "rano --pattern codex --json", description: "Narrow to one CLI, emit JSON lines" },
            { command: "rano report --latest", description: "Summarize the latest session from SQLite" },
            { command: "rano status", description: "One-line activity summary for your prompt" },
          ]}
        />

        <TipBox variant="tip">
          With no flags RANO watches processes matching claude, codex and gemini (plus their
          descendants). Use <code>--pattern</code>, <code>--pid</code> or{" "}
          <code>--exclude-pattern</code> to change targets.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Session History */}
      <Section title="Session History" icon={<BarChart3 className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          Each run is logged to SQLite (<code>observer.sqlite</code> by default), so you can
          summarize, export, and compare sessions afterward.
        </Paragraph>

        <CodeBlock
          code={`# Summarize the latest session (providers, top domains/IPs)
rano report --latest

# Last 24 hours as JSON
rano report --since 24h --json

# Export one provider's events
rano export --format csv --provider anthropic > anthropic.csv

# Compare two sessions
rano diff --old <run-id> --new <run-id>`}
          filename="Session History"
        />

        <TipBox variant="info">
          RANO records connections, not tokens or payloads. Use CAUT for usage and cost.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Alerts and Retry Detection */}
      <Section title="Alerts and Retry Detection" icon={<Bug className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          When an agent behaves unexpectedly, turn on the live checks that match the symptom.
        </Paragraph>

        <CodeBlock
          code={`# Live stats including UDP and listening sockets
rano --preset verbose

# Warn on reconnect storms
rano --pattern claude --retry-threshold 5 --retry-window-ms 30000

# Alert on long-lived connections
rano --alert-duration-ms 30000

# Single poll, then exit
rano --once --json`}
          filename="Live Checks"
        />

        <TipBox variant="warning">
          RANO records process command lines in SQLite, log files and exports. Use{" "}
          <code>--redact-cmdline</code> (or <code>--preset audit</code>) to mask recognizable
          secrets in argv before they&apos;re stored, or <code>--redact-cmdline all</code> to hide
          command lines entirely.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Integration" icon={<Settings className="h-5 w-5" />} delay={0.3}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">RANO + CAUT</span>
            <p className="text-white/80 text-sm mt-1">
              RANO shows which endpoints were hit; CAUT shows the usage and cost
            </p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">RANO + CAAM</span>
            <p className="text-white/80 text-sm mt-1">
              Reconnect storms are a hint to check limits or switch accounts
            </p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">RANO + NTM</span>
            <p className="text-white/80 text-sm mt-1">
              Watch the sockets of every agent NTM spawns, children included
            </p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">RANO + Beads</span>
            <p className="text-white/80 text-sm mt-1">Track network issues as beads for follow-up</p>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Section 6: Best Practices */}
      <Section title="Best Practices" icon={<Shield className="h-5 w-5" />} delay={0.35}>
        <TipBox variant="tip">
          Run RANO during development to see which endpoints your agents and their subprocesses
          actually reach. You&apos;ll often spot redundant reconnects or hosts you didn&apos;t
          expect.
        </TipBox>

        <TipBox variant="warning">
          RANO samples by polling, so connections that open and close between polls can be missed.
          Hostnames come from reverse DNS by default (pcap mode adds DNS and TLS SNI), so a
          CDN-hosted API can appear under a CDN name or as a bare IP. Treat it as an observer, not a
          packet log; use tcpdump or Wireshark when you need every packet or the payloads.
        </TipBox>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Socket Observer
// ---------------------------------------------------------------------------
// A simplified simulation of what RANO observes: sockets owned by monitored
// processes (and their children), tagged with a provider and the remote
// endpoint. RANO never sees request/response bodies, HTTP status codes, or
// tokens, and it never blocks or reroutes traffic. Log outputs below are real
// rano output formats (documentation-range IPs; multi-line outputs excerpted).

// --- Types ---

/** RANO tags each socket by the provider of the owning process (or its ancestor). */
type ProviderTag = "anthropic" | "openai" | "google" | "unknown";
type PacketType = ProviderTag | "flagged";

interface ObservedNode {
  id: string;
  name: string;
  shortName: string;
  kind: "process" | "endpoint";
  /** Process nodes: parent in the monitored process tree. */
  parentId?: string;
  /** Process nodes: PID shown under the node. */
  pid?: number;
  x: number;
  y: number;
  color: string;
}

interface SocketPacket {
  id: number;
  fromNode: string;
  toNode: string;
  type: PacketType;
  progress: number;
}

interface SocketFlow {
  from: string;
  to: string;
  type: PacketType;
}

interface AlertEvent {
  id: number;
  severity: "info" | "warning" | "critical";
  message: string;
  timestamp: string;
}

interface LogLine {
  id: number;
  command: string;
  output: string;
  type: "info" | "warning" | "error" | "success";
}

interface EndpointMetrics {
  nodeId: string;
  /** Endpoint episodes observed this session. */
  connects: number;
  /** Sockets open in the latest poll. */
  active: number;
  status: "ok" | "flagged" | "idle";
}

interface Scenario {
  id: string;
  title: string;
  icon: React.ReactNode;
  description: string;
  metrics: EndpointMetrics[];
  alerts: AlertEvent[];
  logs: LogLine[];
  flows: SocketFlow[];
}

// --- Constants ---

const ENDPOINT_COLOR = "#cbd5e1";

const NODES: ObservedNode[] = [
  {
    id: "claude",
    name: "claude (Claude Code)",
    shortName: "claude",
    kind: "process",
    pid: 2000,
    x: 70,
    y: 70,
    color: "#fb923c",
  },
  {
    id: "claude-node",
    name: "node (child process of claude)",
    shortName: "node",
    kind: "process",
    parentId: "claude",
    pid: 2047,
    x: 190,
    y: 110,
    color: "#fdba74",
  },
  {
    id: "codex",
    name: "codex (Codex CLI)",
    shortName: "codex",
    kind: "process",
    pid: 3100,
    x: 70,
    y: 180,
    color: "#34d399",
  },
  {
    id: "codex-curl",
    name: "curl (codex → bash → curl)",
    shortName: "curl",
    kind: "process",
    parentId: "codex",
    pid: 3188,
    x: 190,
    y: 220,
    color: "#6ee7b7",
  },
  {
    id: "gemini",
    name: "gemini (Gemini CLI)",
    shortName: "gemini",
    kind: "process",
    pid: 4200,
    x: 70,
    y: 280,
    color: "#60a5fa",
  },
  {
    id: "api-anthropic",
    name: "api.anthropic.com",
    shortName: "api.anthropic.com",
    kind: "endpoint",
    x: 520,
    y: 50,
    color: ENDPOINT_COLOR,
  },
  {
    id: "api-openai",
    name: "api.openai.com",
    shortName: "api.openai.com",
    kind: "endpoint",
    x: 520,
    y: 115,
    color: ENDPOINT_COLOR,
  },
  {
    id: "googleapis",
    name: "generativelanguage.googleapis.com",
    shortName: "…googleapis.com",
    kind: "endpoint",
    x: 520,
    y: 180,
    color: ENDPOINT_COLOR,
  },
  {
    id: "github",
    name: "github.com",
    shortName: "github.com",
    kind: "endpoint",
    x: 520,
    y: 235,
    color: ENDPOINT_COLOR,
  },
  {
    id: "unresolved",
    name: "203.0.113.42 (no hostname)",
    shortName: "203.0.113.42",
    kind: "endpoint",
    x: 520,
    y: 290,
    color: ENDPOINT_COLOR,
  },
];

const PACKET_COLORS: Record<PacketType, string> = {
  anthropic: "#fb923c",
  openai: "#34d399",
  google: "#60a5fa",
  unknown: "#94a3b8",
  flagged: "#ef4444",
};

const SEVERITY_STYLES: Record<
  AlertEvent["severity"],
  { bg: string; border: string; text: string; dot: string }
> = {
  info: {
    bg: "bg-blue-500/10",
    border: "border-blue-500/30",
    text: "text-blue-400",
    dot: "bg-blue-400",
  },
  warning: {
    bg: "bg-yellow-500/10",
    border: "border-yellow-500/30",
    text: "text-yellow-400",
    dot: "bg-yellow-400",
  },
  critical: {
    bg: "bg-red-500/10",
    border: "border-red-500/30",
    text: "text-red-400",
    dot: "bg-red-400",
  },
};

function makeScenarios(): Scenario[] {
  return [
    {
      id: "baseline",
      title: "Default Observation",
      icon: <Activity className="h-4 w-4" />,
      description:
        "With no flags, RANO polls for processes matching claude, codex and gemini, follows their children, and tags every socket with a provider and remote endpoint.",
      metrics: [
        { nodeId: "api-anthropic", connects: 24, active: 3, status: "ok" },
        { nodeId: "api-openai", connects: 11, active: 1, status: "ok" },
        { nodeId: "googleapis", connects: 6, active: 1, status: "ok" },
        { nodeId: "github", connects: 0, active: 0, status: "idle" },
        { nodeId: "unresolved", connects: 0, active: 0, status: "idle" },
      ],
      alerts: [],
      logs: [
        {
          id: 1,
          command: "rano",
          output:
            "2026-11-25T14:24:02Z | + connect | anthropic | pid=2000 | claude | tcp | 10.0.0.5:51022 <-> 198.51.100.7:443 | domain=api.anthropic.com",
          type: "success",
        },
        {
          id: 2,
          command: "rano --pattern codex",
          output:
            "2026-11-25T14:24:05Z | + connect | openai | pid=3100 | codex | tcp | 10.0.0.5:51040 <-> 198.51.100.20:443 | domain=api.openai.com",
          type: "info",
        },
        {
          id: 3,
          command: "rano status",
          output: "5 active | anthropic:24 openai:11",
          type: "info",
        },
      ],
      flows: [
        { from: "claude", to: "api-anthropic", type: "anthropic" },
        { from: "claude-node", to: "api-anthropic", type: "anthropic" },
        { from: "codex", to: "api-openai", type: "openai" },
        { from: "gemini", to: "googleapis", type: "google" },
      ],
    },
    {
      id: "retry-storm",
      title: "Retry Storm",
      icon: <Zap className="h-4 w-4" />,
      description:
        "Claude Code reconnects to the same endpoint again and again, a common sign of rate limiting or a flaky network. RANO sees the reconnects, not the HTTP status codes behind them.",
      metrics: [
        { nodeId: "api-anthropic", connects: 52, active: 2, status: "flagged" },
        { nodeId: "api-openai", connects: 11, active: 1, status: "ok" },
        { nodeId: "googleapis", connects: 6, active: 1, status: "ok" },
        { nodeId: "github", connects: 0, active: 0, status: "idle" },
        { nodeId: "unresolved", connects: 0, active: 0, status: "idle" },
      ],
      alerts: [
        {
          id: 1,
          severity: "warning",
          message: "Retry pattern: 5 connections to api.anthropic.com:443 in 30s",
          timestamp: "14:25:03",
        },
        {
          id: 2,
          severity: "warning",
          message: "Retry pattern: 7 connections to api.anthropic.com:443 in 30s",
          timestamp: "14:25:41",
        },
      ],
      logs: [
        {
          id: 1,
          command: "rano --pattern claude --retry-threshold 5 --retry-window-ms 30000",
          output: "⚠ Retry pattern: 5 connections to api.anthropic.com:443 in 30s",
          type: "warning",
        },
        {
          id: 2,
          command: "rano --pattern claude --json --retry-threshold 5 --retry-window-ms 30000",
          output: '{"type":"retry_warning","count":5,"endpoint":"198.51.100.7:443","window_seconds":30}',
          type: "warning",
        },
        {
          id: 3,
          command:
            "rano export --format jsonl --since 1h | jq -c 'select(.retry_count) | {ts, domain, retry_count}'",
          output:
            '{"ts":"2026-11-25T14:25:03Z","domain":"api.anthropic.com","retry_count":5}\n{"ts":"2026-11-25T14:25:41Z","domain":"api.anthropic.com","retry_count":7}',
          type: "info",
        },
      ],
      flows: [
        { from: "claude", to: "api-anthropic", type: "flagged" },
        { from: "claude", to: "api-anthropic", type: "flagged" },
        { from: "claude", to: "api-anthropic", type: "anthropic" },
        { from: "codex", to: "api-openai", type: "openai" },
        { from: "gemini", to: "googleapis", type: "google" },
      ],
    },
    {
      id: "unexpected-endpoint",
      title: "Unexpected Endpoint",
      icon: <ShieldAlert className="h-4 w-4" />,
      description:
        "A shell spawned by Codex runs curl against an address with no hostname. RANO attributes the socket to curl, tags it openai (inherited from its codex ancestor), and can show the full process chain.",
      metrics: [
        { nodeId: "api-anthropic", connects: 24, active: 3, status: "ok" },
        { nodeId: "api-openai", connects: 12, active: 1, status: "ok" },
        { nodeId: "googleapis", connects: 6, active: 1, status: "ok" },
        { nodeId: "github", connects: 0, active: 0, status: "idle" },
        { nodeId: "unresolved", connects: 2, active: 1, status: "flagged" },
      ],
      alerts: [
        {
          id: 1,
          severity: "warning",
          message: "unknown_domain | unresolved: 203.0.113.42 | pid=3188 | curl",
          timestamp: "14:26:12",
        },
      ],
      logs: [
        {
          id: 1,
          command: "rano --pattern codex --alert-unknown-domain",
          output:
            "[ALERT] 2026-11-25T14:26:12Z | WARNING | unknown_domain | unresolved: 203.0.113.42 | pid=3188 | curl | tcp | 10.0.0.5:40112 -> 203.0.113.42:443",
          type: "warning",
        },
        {
          id: 2,
          command: "rano --pattern codex --show-ancestry",
          output:
            "2026-11-25T14:26:12Z | + connect | openai | ... → bash(3150) → curl(3188) | tcp | 10.0.0.5:40112 <-> 203.0.113.42:443 | domain=unknown",
          type: "info",
        },
        {
          id: 3,
          command:
            "rano export --format jsonl --since 1h | jq -r 'select(.comm == \"curl\") | .ancestry_path'",
          output: "systemd:1,tmux:1600,bash:1700,codex:3100,bash:3150,curl:3188",
          type: "info",
        },
      ],
      flows: [
        { from: "codex-curl", to: "unresolved", type: "flagged" },
        { from: "codex", to: "api-openai", type: "openai" },
        { from: "claude", to: "api-anthropic", type: "anthropic" },
        { from: "gemini", to: "googleapis", type: "google" },
      ],
    },
    {
      id: "long-lived",
      title: "Long-Lived Connection",
      icon: <Clock className="h-4 w-4" />,
      description:
        "A streaming response keeps a Codex socket open for 45 seconds. With --alert-duration-ms, RANO flags endpoint episodes that close after more than the threshold.",
      metrics: [
        { nodeId: "api-anthropic", connects: 26, active: 2, status: "ok" },
        { nodeId: "api-openai", connects: 14, active: 1, status: "flagged" },
        { nodeId: "googleapis", connects: 7, active: 1, status: "ok" },
        { nodeId: "github", connects: 0, active: 0, status: "idle" },
        { nodeId: "unresolved", connects: 0, active: 0, status: "idle" },
      ],
      alerts: [
        {
          id: 1,
          severity: "warning",
          message: "long_duration | 45120ms > 30000ms | pid=3100 | codex",
          timestamp: "14:27:30",
        },
      ],
      logs: [
        {
          id: 1,
          command: "rano --alert-duration-ms 30000",
          output:
            "[ALERT] 2026-11-25T14:27:30Z | WARNING | long_duration | 45120ms > 30000ms | pid=3100 | codex | tcp | 10.0.0.5:52144 -> 198.51.100.20:443",
          type: "warning",
        },
        {
          id: 2,
          command: "rano --pattern codex",
          output:
            "2026-11-25T14:27:30Z | - close | openai | pid=3100 | codex | tcp | 10.0.0.5:52144 <-> 198.51.100.20:443 | domain=api.openai.com dur=45120ms",
          type: "info",
        },
        {
          id: 3,
          command: "rano report --latest",
          output: "Close durations: avg=2139.535ms max=45120ms samples=43",
          type: "info",
        },
      ],
      flows: [
        { from: "codex", to: "api-openai", type: "flagged" },
        { from: "claude", to: "api-anthropic", type: "anthropic" },
        { from: "claude-node", to: "api-anthropic", type: "anthropic" },
        { from: "gemini", to: "googleapis", type: "google" },
      ],
    },
    {
      id: "live-stats",
      title: "Live Stats Views",
      icon: <BarChart3 className="h-4 w-4" />,
      description:
        "While the monitor runs, RANO prints bar charts of observations by provider, domain, port or process. Here a curl child of Codex also reaches github.com.",
      metrics: [
        { nodeId: "api-anthropic", connects: 42, active: 3, status: "ok" },
        { nodeId: "api-openai", connects: 18, active: 1, status: "ok" },
        { nodeId: "googleapis", connects: 6, active: 1, status: "ok" },
        { nodeId: "github", connects: 2, active: 1, status: "ok" },
        { nodeId: "unresolved", connects: 0, active: 0, status: "idle" },
      ],
      alerts: [],
      logs: [
        {
          id: 1,
          command: "rano --preset live",
          output: "Live Stats [provider]\n  anthropic  | ████████████████████ 42 (domains=1, ips=2)",
          type: "info",
        },
        {
          id: 2,
          command: "rano --stats-view process --stats-top 3",
          output:
            "Live Stats [process]\n      30 ████████████████████ claude\n      18 ████████████         codex\n      12 ████████             node",
          type: "info",
        },
        {
          id: 3,
          command: "rano status --format '{active}/{total}'",
          output: "6/68",
          type: "success",
        },
      ],
      flows: [
        { from: "claude", to: "api-anthropic", type: "anthropic" },
        { from: "claude-node", to: "api-anthropic", type: "anthropic" },
        { from: "codex", to: "api-openai", type: "openai" },
        { from: "codex-curl", to: "github", type: "openai" },
        { from: "gemini", to: "googleapis", type: "google" },
      ],
    },
    {
      id: "history",
      title: "Report, Export & Diff",
      icon: <Filter className="h-4 w-4" />,
      description:
        "The session has ended, so nothing is live. Its history is in SQLite (observer.sqlite by default): summarize it, export CSV or JSONL, or diff it against an earlier session.",
      metrics: [
        { nodeId: "api-anthropic", connects: 42, active: 0, status: "idle" },
        { nodeId: "api-openai", connects: 18, active: 0, status: "idle" },
        { nodeId: "googleapis", connects: 6, active: 0, status: "idle" },
        { nodeId: "github", connects: 2, active: 0, status: "idle" },
        { nodeId: "unresolved", connects: 0, active: 0, status: "idle" },
      ],
      alerts: [],
      logs: [
        {
          id: 1,
          command: "rano report --latest",
          output: "Events:  136 total (68 connects, 68 closes)",
          type: "info",
        },
        {
          id: 2,
          command:
            "rano export --format jsonl --run-id afternoon-audit | jq -r '.domain // \"unknown\"' | sort | uniq -c",
          output:
            "     84 api.anthropic.com\n     36 api.openai.com\n     12 generativelanguage.googleapis.com\n      4 github.com",
          type: "info",
        },
        {
          id: 3,
          command: "rano diff --old morning-audit --new afternoon-audit",
          output: "New Domains: (1 added)\n  + github.com\n\nNew Processes: (1 appeared)\n  + curl",
          type: "success",
        },
      ],
      flows: [],
    },
  ];
}

// ---------------------------------------------------------------------------
// Process → endpoint socket map
// ---------------------------------------------------------------------------

function SocketMapSvg({
  nodes,
  packets,
  activeScenario,
}: {
  nodes: ObservedNode[];
  packets: SocketPacket[];
  activeScenario: Scenario;
}) {
  const nodeMap = useMemo(() => {
    const map: Record<string, ObservedNode> = {};
    for (const n of nodes) {
      map[n.id] = n;
    }
    return map;
  }, [nodes]);

  const metricsMap = useMemo(() => {
    const map: Record<string, EndpointMetrics> = {};
    for (const m of activeScenario.metrics) {
      map[m.nodeId] = m;
    }
    return map;
  }, [activeScenario.metrics]);

  const flowLinks = useMemo(() => {
    const seen = new Set<string>();
    const links: Array<[string, string]> = [];
    for (const f of activeScenario.flows) {
      const key = `${f.from}->${f.to}`;
      if (!seen.has(key)) {
        seen.add(key);
        links.push([f.from, f.to]);
      }
    }
    return links;
  }, [activeScenario.flows]);

  return (
    <svg viewBox="0 0 640 320" className="w-full min-w-[640px] h-auto" xmlns="http://www.w3.org/2000/svg">
      {/* Background grid */}
      <defs>
        <pattern id="noc-grid" width="32" height="32" patternUnits="userSpaceOnUse">
          <path
            d="M 32 0 L 0 0 0 32"
            fill="none"
            stroke="rgba(255,255,255,0.03)"
            strokeWidth="0.5"
          />
        </pattern>
        {/* Glow filter */}
        <filter id="noc-glow">
          <feGaussianBlur stdDeviation="3" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
        <filter id="noc-glow-strong">
          <feGaussianBlur stdDeviation="6" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <rect width="640" height="320" fill="transparent" />
      <rect width="640" height="320" fill="url(#noc-grid)" />

      {/* Column labels */}
      <text
        x={130}
        y={16}
        textAnchor="middle"
        fill="var(--muted-foreground)"
        fontSize="12"
        fontFamily="monospace"
      >
        monitored processes
      </text>
      <text
        x={520}
        y={16}
        textAnchor="middle"
        fill="var(--muted-foreground)"
        fontSize="12"
        fontFamily="monospace"
      >
        remote endpoints
      </text>

      {/* Process tree (parent → child) */}
      {nodes
        .filter((n) => n.parentId)
        .map((child) => {
          const parent = child.parentId ? nodeMap[child.parentId] : undefined;
          if (!parent) return null;
          return (
            <line
              key={`tree-${child.id}`}
              x1={parent.x}
              y1={parent.y}
              x2={child.x}
              y2={child.y}
              stroke="rgba(255,255,255,0.12)"
              strokeWidth="1"
            />
          );
        })}

      {/* Observed socket paths */}
      {flowLinks.map(([fromId, toId]) => {
        const from = nodeMap[fromId];
        const to = nodeMap[toId];
        if (!from || !to) return null;
        return (
          <line
            key={`${fromId}-${toId}`}
            x1={from.x}
            y1={from.y}
            x2={to.x}
            y2={to.y}
            stroke="rgba(255,255,255,0.06)"
            strokeWidth="0.8"
            strokeDasharray="4,4"
          />
        );
      })}

      {/* Animated packets */}
      {packets.map((pkt) => {
        const from = nodeMap[pkt.fromNode];
        const to = nodeMap[pkt.toNode];
        if (!from || !to) return null;
        const px = from.x + (to.x - from.x) * pkt.progress;
        const py = from.y + (to.y - from.y) * pkt.progress;
        const color = PACKET_COLORS[pkt.type];
        return (
          <g key={pkt.id}>
            <circle
              cx={px}
              cy={py}
              r="4"
              fill={color}
              opacity={0.3}
              filter="url(#noc-glow-strong)"
            />
            <circle cx={px} cy={py} r="2" fill={color} opacity={0.9} filter="url(#noc-glow)" />
          </g>
        );
      })}

      {/* Process and endpoint nodes */}
      {nodes.map((node) => {
        const metric = metricsMap[node.id];
        const isIdle = node.kind === "endpoint" && (!metric || metric.status === "idle");
        const isFlagged = metric?.status === "flagged";
        const ringColor = isFlagged
          ? "#f59e0b"
          : isIdle
            ? "rgba(255,255,255,0.25)"
            : node.color;
        const pulseOpacity = isFlagged ? 0.4 : isIdle ? 0.05 : 0.15;
        const caption =
          node.kind === "process"
            ? `pid ${node.pid}`
            : isIdle
              ? "idle"
              : `${metric?.active ?? 0} active`;
        return (
          <g key={node.id}>
            {/* Pulse ring */}
            <circle
              cx={node.x}
              cy={node.y}
              r="14"
              fill="none"
              stroke={ringColor}
              strokeWidth="1"
              opacity={pulseOpacity}
            >
              <animate attributeName="r" values="14;22;14" dur="2s" repeatCount="indefinite" />
              <animate
                attributeName="opacity"
                values={`${pulseOpacity};0;${pulseOpacity}`}
                dur="2s"
                repeatCount="indefinite"
              />
            </circle>
            {/* Node circle */}
            <circle
              cx={node.x}
              cy={node.y}
              r="8"
              fill="rgba(0,0,0,0.6)"
              stroke={ringColor}
              strokeWidth="1.5"
            />
            <circle cx={node.x} cy={node.y} r="3" fill={ringColor} opacity={0.8} />
            {/* Label */}
            <text
              x={node.x}
              y={node.y - 16}
              textAnchor="middle"
              fill="rgba(255,255,255,0.6)"
              fontSize="12"
              fontFamily="monospace"
            >
              {node.shortName}
            </text>
            {/* PID or active-socket caption */}
            <text
              x={node.x}
              y={node.y + 24}
              textAnchor="middle"
              fill="var(--muted-foreground)"
              fontSize="12"
              fontFamily="monospace"
            >
              {caption}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function MetricGauge({
  label,
  value,
  max,
  unit,
  status,
}: {
  label: string;
  value: number;
  max: number;
  unit: string;
  status: EndpointMetrics["status"];
}) {
  const pct = Math.min((value / max) * 100, 100);
  const barColor =
    status === "flagged"
      ? "bg-yellow-500"
      : status === "idle"
        ? "bg-white/30"
        : pct > 75
          ? "bg-amber-500"
          : "bg-emerald-500";
  return (
    <div className="space-y-1">
      <div className="flex justify-between items-center">
        <span className="text-xs text-muted-foreground uppercase tracking-wider">{label}</span>
        <span className="text-xs font-mono text-white/60">{`${value.toLocaleString()}${unit}`}</span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${barColor}`}
          initial={{ width: 0 }}
          animate={{ width: `${pct}%` }}
          transition={{ type: "spring", stiffness: 200, damping: 25 }}
        />
      </div>
    </div>
  );
}

function AlertPanel({ alerts }: { alerts: AlertEvent[] }) {
  if (alerts.length === 0) {
    return (
      <div className="flex items-center justify-center py-6 gap-2">
        <CheckCircle2 className="h-4 w-4 text-emerald-400/50" />
        <span className="text-xs text-emerald-400/50">No alerts or warnings</span>
      </div>
    );
  }
  return (
    <div className="space-y-1.5 max-h-40 overflow-y-auto">
      {alerts.map((t) => {
        const s = SEVERITY_STYLES[t.severity];
        return (
          <motion.div
            key={t.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-start gap-2 p-2 rounded-lg border ${s.border} ${s.bg}`}
          >
            <div className={`mt-0.5 h-2 w-2 rounded-full shrink-0 ${s.dot}`} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className={`text-xs font-bold uppercase tracking-wider ${s.text}`}>
                  {t.severity}
                </span>
                <span className="text-xs text-muted-foreground font-mono">{t.timestamp}</span>
              </div>
              <p className="text-xs text-white/60 leading-tight mt-0.5 truncate">{t.message}</p>
            </div>
          </motion.div>
        );
      })}
    </div>
  );
}

function LiveLogStream({ logs }: { logs: LogLine[] }) {
  const LOG_TYPE_STYLES: Record<LogLine["type"], string> = {
    info: "text-blue-400",
    warning: "text-yellow-400",
    error: "text-red-400",
    success: "text-emerald-400",
  };

  return (
    <div className="space-y-1 font-mono text-xs">
      {logs.map((log, i) => (
        <motion.div
          key={log.id}
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring", stiffness: 200, damping: 25, delay: i * 0.08 }}
        >
          <div className="flex items-start gap-1">
            <span className="text-emerald-500/70">$</span>
            <span className="min-w-0 break-words text-white/70">{log.command}</span>
          </div>
          <div
            className={`pl-3 whitespace-pre-wrap break-words ${LOG_TYPE_STYLES[log.type]} opacity-80`}
          >
            {log.output}
          </div>
        </motion.div>
      ))}
    </div>
  );
}

function NocStatCard({
  label,
  value,
  icon,
  color,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  color: string;
}) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-2.5 text-center">
      <div className={`flex items-center justify-center gap-1 ${color} mb-0.5`}>
        {icon}
        <span className="text-xs font-semibold uppercase tracking-wider">{label}</span>
      </div>
      <p className="text-sm font-bold font-mono text-white/80">{value}</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Interactive Component
// ---------------------------------------------------------------------------

function InteractiveTrafficMonitor() {
  const scenarios = useMemo(() => makeScenarios(), []);
  const [stepIndex, setStepIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [packets, setPackets] = useState<SocketPacket[]>([]);
  const packetIdRef = useRef(0);
  const frameRef = useRef<ReturnType<typeof requestAnimationFrame> | null>(null);
  const lastTickRef = useRef<number>(0);
  const spawnTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });

  const activeScenario = scenarios[stepIndex];

  // Aggregate stats
  const aggStats = useMemo(() => {
    const metrics = activeScenario.metrics;
    const totalConnects = metrics.reduce((sum, m) => sum + m.connects, 0);
    const totalActive = metrics.reduce((sum, m) => sum + m.active, 0);
    const processCount = new Set(activeScenario.flows.map((f) => f.from)).size;
    const alertCount = activeScenario.alerts.length;
    return { totalConnects, totalActive, processCount, alertCount };
  }, [activeScenario]);

  // Spawn packets on a schedule
  const spawnPacket = useCallback(() => {
    const flows = activeScenario.flows;
    if (flows.length === 0) return;
    const flow = flows[Math.floor(Math.random() * flows.length)];
    packetIdRef.current += 1;
    const newPacket: SocketPacket = {
      id: packetIdRef.current,
      fromNode: flow.from,
      toNode: flow.to,
      type: flow.type,
      progress: 0,
    };
    setPackets((prev) => [...prev.slice(-20), newPacket]);
  }, [activeScenario.flows]);

  // Animation loop for packet progress
  useEffect(() => {
    if (!isPlaying || !inView) {
      if (frameRef.current !== null) {
        cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
      return;
    }

    const animate = (time: number) => {
      if (lastTickRef.current === 0) {
        lastTickRef.current = time;
      }
      const dt = (time - lastTickRef.current) / 1000;
      lastTickRef.current = time;

      setPackets((prev) =>
        prev.map((p) => ({ ...p, progress: p.progress + dt * 0.5 })).filter((p) => p.progress < 1),
      );

      frameRef.current = requestAnimationFrame(animate);
    };

    lastTickRef.current = 0;
    frameRef.current = requestAnimationFrame(animate);

    return () => {
      if (frameRef.current !== null) {
        cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };
  }, [isPlaying, inView]);

  // Spawn packets periodically when playing
  useEffect(() => {
    if (!isPlaying || !inView) {
      if (spawnTimerRef.current !== null) {
        clearInterval(spawnTimerRef.current);
        spawnTimerRef.current = null;
      }
      return;
    }

    // Spawn one immediately
    const id = setTimeout(() => spawnPacket(), 0);
    const interval = setInterval(() => {
      spawnPacket();
    }, 600);
    spawnTimerRef.current = interval;

    return () => {
      clearTimeout(id);
      clearInterval(interval);
      spawnTimerRef.current = null;
    };
  }, [isPlaying, inView, spawnPacket]);

  const handlePrev = useCallback(() => {
    setStepIndex((i) => Math.max(0, i - 1));
    setPackets([]);
  }, []);

  const handleNext = useCallback(() => {
    setStepIndex((i) => Math.min(scenarios.length - 1, i + 1));
    setPackets([]);
  }, [scenarios.length]);

  const handleReset = useCallback(() => {
    setIsPlaying(false);
    setStepIndex(0);
    setPackets([]);
  }, []);

  const handleTogglePlay = useCallback(() => {
    setIsPlaying((p) => !p);
  }, []);

  return (
    <div
      ref={ref}
      className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden"
    >
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-violet-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 lg:p-8 space-y-5">
        {/* Header */}
        <div className="text-center">
          <div className="inline-flex items-center gap-2 mb-2">
            <Globe className="h-4 w-4 text-blue-400" />
            <p className="text-sm font-semibold text-white/80">Socket Observer</p>
            {isPlaying && (
              <motion.div
                animate={inView ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
                transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
                className="flex items-center gap-1"
              >
                <div className="h-2 w-2 rounded-full bg-red-400" />
                <span className="text-xs text-red-400 font-mono">LIVE</span>
              </motion.div>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            Step through scenarios to see which sockets RANO attributes to which process, and the
            commands that surface them (simulated; RANO observes and reports, it never blocks)
          </p>
        </div>

        {/* Scenario stepper indicators */}
        <div className="flex items-center justify-center gap-1.5">
          {scenarios.map((s, i) => (
            <button
              key={s.id}
              type="button"
              aria-label={`Scenario ${i + 1}: ${s.title}`}
              aria-current={i === stepIndex ? "step" : undefined}
              onClick={() => {
                setStepIndex(i);
                setPackets([]);
              }}
              className={`h-1.5 rounded-full transition-[width,background-color] ${
                i === stepIndex
                  ? "w-6 bg-blue-400"
                  : i < stepIndex
                    ? "w-3 bg-white/20"
                    : "w-3 bg-white/[0.08]"
              }`}
            />
          ))}
        </div>

        {/* Scenario header */}
        <AnimatePresence mode="wait">
          <motion.div
            key={activeScenario.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center gap-3 p-3 rounded-xl border border-white/[0.08] bg-white/[0.03]"
          >
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-500/10 border border-blue-500/30 text-blue-400 shrink-0">
              {activeScenario.icon}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-xs font-semibold text-white/80">
                  Step {stepIndex + 1}: {activeScenario.title}
                </span>
              </div>
              <p className="text-xs text-muted-foreground leading-snug mt-0.5">
                {activeScenario.description}
              </p>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Top-level aggregate stats */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <NocStatCard
            label="Connects"
            value={aggStats.totalConnects.toLocaleString()}
            icon={<Activity className="h-3 w-3" />}
            color="text-blue-400"
          />
          <NocStatCard
            label="Active"
            value={`${aggStats.totalActive} sockets`}
            icon={<Radio className="h-3 w-3" />}
            color="text-violet-400"
          />
          <NocStatCard
            label="Processes"
            value={`${aggStats.processCount}`}
            icon={<Eye className="h-3 w-3" />}
            color="text-emerald-400"
          />
          <NocStatCard
            label="Alerts"
            value={`${aggStats.alertCount}`}
            icon={<ShieldAlert className="h-3 w-3" />}
            color={aggStats.alertCount > 0 ? "text-amber-400" : "text-emerald-400"}
          />
        </div>

        {/* Main grid: Map + Panels */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {/* Socket Map */}
          <div className="lg:col-span-2 rounded-2xl border border-white/[0.08] bg-black/30 overflow-hidden relative">
            <div className="px-3 py-2 border-b border-white/[0.06] flex items-center justify-between">
              <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Process → Endpoint Sockets
              </span>
              <div className="flex items-center gap-3">
                {Object.entries(PACKET_COLORS).map(([type, color]) => (
                  <div key={type} className="flex items-center gap-1">
                    <div className="h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
                    <span className="text-xs text-muted-foreground">{type}</span>
                  </div>
                ))}
              </div>
            </div>
            <DiagramScroller label="Map of process-to-endpoint sockets" minWidth={640}>
              <div className="p-2">
                <SocketMapSvg nodes={NODES} packets={packets} activeScenario={activeScenario} />
              </div>
            </DiagramScroller>
          </div>

          {/* Right sidebar: Endpoint activity + Alerts */}
          <div className="space-y-4">
            {/* Endpoint Activity */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
              <div className="px-3 py-2 border-b border-white/[0.06]">
                <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  Endpoint Activity
                </span>
              </div>
              <div className="p-3 space-y-3">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={activeScenario.id}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                    className="space-y-3"
                  >
                    {activeScenario.metrics.map((m) => {
                      const node = NODES.find((n) => n.id === m.nodeId);
                      if (!node) return null;
                      return (
                        <div key={m.nodeId} className="space-y-1.5">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-1.5 min-w-0">
                              <div
                                className="h-2 w-2 rounded-full shrink-0"
                                style={{
                                  backgroundColor:
                                    m.status === "flagged"
                                      ? "#f59e0b"
                                      : m.status === "idle"
                                        ? "rgba(255,255,255,0.25)"
                                        : node.color,
                                }}
                              />
                              <span
                                className="text-xs font-mono text-white/60 truncate"
                                title={node.name}
                              >
                                {node.shortName}
                              </span>
                            </div>
                            <span
                              className={`text-xs font-bold uppercase tracking-wider ${
                                m.status === "flagged"
                                  ? "text-yellow-400"
                                  : m.status === "idle"
                                    ? "text-muted-foreground"
                                    : "text-emerald-400"
                              }`}
                            >
                              {m.status}
                            </span>
                          </div>
                          <MetricGauge
                            label="Connects"
                            value={m.connects}
                            max={60}
                            unit=""
                            status={m.status}
                          />
                          <MetricGauge
                            label="Active"
                            value={m.active}
                            max={5}
                            unit=""
                            status={m.status}
                          />
                        </div>
                      );
                    })}
                  </motion.div>
                </AnimatePresence>
              </div>
            </div>

            {/* Alerts Panel */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
              <div className="px-3 py-2 border-b border-white/[0.06] flex items-center justify-between">
                <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  Alerts &amp; Warnings
                </span>
                {activeScenario.alerts.length > 0 && (
                  <span className="text-xs font-mono text-red-400">
                    {activeScenario.alerts.length} alert
                    {activeScenario.alerts.length !== 1 ? "s" : ""}
                  </span>
                )}
              </div>
              <div className="p-3">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={activeScenario.id}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ type: "spring", stiffness: 200, damping: 25 }}
                  >
                    <AlertPanel alerts={activeScenario.alerts} />
                  </motion.div>
                </AnimatePresence>
              </div>
            </div>
          </div>
        </div>

        {/* Live Log Stream */}
        <div className="rounded-2xl border border-white/[0.08] bg-black/30 overflow-hidden">
          <div className="px-3 py-2 border-b border-white/[0.06] flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Terminal className="h-3 w-3 text-emerald-400/60" />
              <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                RANO Command Log
              </span>
            </div>
            <span className="text-xs font-mono text-muted-foreground">
              ~ {activeScenario.logs.length} commands
            </span>
          </div>
          <div className="p-3 max-h-64 overflow-y-auto">
            <AnimatePresence mode="wait">
              <motion.div
                key={activeScenario.id}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ type: "spring", stiffness: 200, damping: 25 }}
              >
                <LiveLogStream logs={activeScenario.logs} />
              </motion.div>
            </AnimatePresence>
          </div>
        </div>

        {/* Controls */}
        <div className="flex items-center justify-center gap-3">
          <motion.button
            type="button"
            onClick={handlePrev}
            disabled={stepIndex === 0}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-1.5 rounded-2xl border px-4 py-2 text-xs font-medium transition-colors ${
              stepIndex === 0
                ? "border-white/[0.04] text-muted-foreground cursor-not-allowed"
                : "border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white/80"
            }`}
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Prev
          </motion.button>

          <motion.button
            type="button"
            onClick={handleTogglePlay}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-2 rounded-2xl border px-5 py-2.5 text-sm font-medium transition-colors ${
              isPlaying
                ? "border-red-500/30 bg-red-500/10 text-red-300 hover:bg-red-500/20"
                : "border-blue-500/30 bg-blue-500/10 text-blue-300 hover:bg-blue-500/20"
            }`}
          >
            {isPlaying ? (
              <>
                <motion.div
                  animate={inView ? { rotate: 360 } : { rotate: 0 }}
                  transition={
                    inView ? { duration: 2, repeat: Infinity, ease: "linear" } : { duration: 0.2 }
                  }
                >
                  <Network className="h-4 w-4" />
                </motion.div>
                Stop
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                Simulate
              </>
            )}
          </motion.button>

          <motion.button
            type="button"
            onClick={handleNext}
            disabled={stepIndex === scenarios.length - 1}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className={`flex items-center gap-1.5 rounded-2xl border px-4 py-2 text-xs font-medium transition-colors ${
              stepIndex === scenarios.length - 1
                ? "border-white/[0.04] text-muted-foreground cursor-not-allowed"
                : "border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white/80"
            }`}
          >
            Next
            <ChevronRight className="h-3.5 w-3.5" />
          </motion.button>

          <motion.button
            type="button"
            onClick={handleReset}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            className="flex items-center gap-1.5 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-4 py-2 text-xs font-medium text-muted-foreground hover:text-foreground transition-colors"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            Reset
          </motion.button>
        </div>
      </div>
    </div>
  );
}
