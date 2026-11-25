"use client";

import {
  Activity,
  ArrowRight,
  Ban,
  CheckCircle,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Clock,
  Database,
  Eye,
  FileSearch,
  Gauge,
  Globe,
  Lock,
  Pause,
  Play,
  Settings,
  Shield,
  Terminal,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
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

const InteractiveTrafficInspector = InteractiveTrafficInspectorImpl;

export function RustProxyLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Route only selected domains through an upstream HTTP proxy, machine-wide, without a global
        system proxy.
      </GoalBanner>

      {/* Section 1: What Is Rust Proxy */}
      <Section title="What Is Rust Proxy?" icon={<Shield className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>Rust Proxy</Highlight> is a targeted, machine-wide transparent proxy for Linux.
          iptables + ipset redirect only the domains you list into a local daemon, which tunnels
          them through your chosen upstream HTTP proxy.
        </Paragraph>
        <Paragraph>
          Everything else stays direct, and no app needs proxy settings. It routes traffic; it does
          not inspect or decrypt it.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Transparent"
              description="No app changes needed"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Lock className="h-5 w-5" />}
              title="HTTPS Support"
              description="Tunnels TLS via CONNECT, no MITM"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Activity className="h-5 w-5" />}
              title="Low Latency"
              description="Minimal overhead in Rust"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="Proxy Stats"
              description="Bytes, ping, health, failover"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          <code>init</code> writes a config that already targets the main AI and cloud provider
          domains (Anthropic, OpenAI, Google, AWS, Cloudflare, Vercel, Supabase). Register an
          upstream proxy, add any other domains, then start the routing daemon.
        </Paragraph>

        <CodeBlock
          code={`# Create ~/.config/rust_proxy/config.toml (with default targets)
rust_proxy init

# Register an upstream HTTP proxy
rust_proxy proxy add mesh-us us-wa.proxymesh.com:31280 \\
  --username-env PROXY_USER --password-env PROXY_PASS

# Add a domain that is not in the defaults
rust_proxy targets add api.x.ai

# Activate, then run the daemon (iptables + ipset need root)
rust_proxy activate --select
sudo rust_proxy daemon

# Verify
rust_proxy status`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          No <code>HTTPS_PROXY</code> needed: the daemon redirects only traffic bound for your target
          domains, machine-wide. By default the ipset also includes the published AWS, Cloudflare and
          Google IPv4 ranges; set the <code>include_*_ip_ranges</code> settings to false to turn
          that off. Linux and IPv4 only.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: "rust_proxy init", description: "Create the default config" },
            { command: "rust_proxy targets list", description: "Show the domains that get proxied" },
            { command: "rust_proxy activate --select", description: "Choose the active upstream proxy" },
            { command: "sudo rust_proxy daemon", description: "Run the routing daemon (root)" },
            { command: "rust_proxy status --json", description: "Daemon, routing and rule status" },
            { command: "rust_proxy list", description: "Upstream proxies with bytes and ping stats" },
            { command: "sudo rust_proxy deactivate", description: "Stop routing and clear iptables/ipset" },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 4: Use Cases */}
      <Section title="Routing Diagnostics" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Check how a destination will be routed and whether the upstream proxy is healthy.
        </Paragraph>

        <CodeBlock
          code={`# Would this destination be proxied?
rust_proxy test https://api.anthropic.com --verbose

# Trace the CONNECT flow
rust_proxy trace api.anthropic.com --tls

# Upstream latency
rust_proxy ping --count 5

# Health check
rust_proxy doctor`}
          filename="Diagnostics"
        />

        <TipBox variant="warning">
          The daemon edits iptables/ipset rules, so <code>daemon</code>, <code>deactivate</code> and{" "}
          <code>cleanup-stale</code> need sudo. Run <code>sudo rust_proxy deactivate</code> to
          restore direct routing.
        </TipBox>

        <div className="mt-8">
          <InteractiveTrafficInspector />
        </div>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Zap className="h-5 w-5" />} delay={0.3}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">RP + RANO</span>
            <p className="text-white/80 text-sm mt-1">
              RANO shows which process talks to which provider; RP decides which of those
              connections leave through the upstream proxy
            </p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">RP + NTM</span>
            <p className="text-white/80 text-sm mt-1">
              Every agent pane gets the same routing, with no per-pane proxy env vars
            </p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">RP + CAAM</span>
            <p className="text-white/80 text-sm mt-1">
              CAAM switches accounts; RP only picks the network path and never sees API keys
            </p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">RP + Beads</span>
            <p className="text-white/80 text-sm mt-1">Track network issues as beads</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE TRAFFIC INSPECTOR - DRAMATICALLY UPGRADED
// =============================================================================

const SPRING = { type: "spring", stiffness: 200, damping: 25 } as const;
const SPRING_SNAPPY = { type: "spring", stiffness: 400, damping: 35 } as const;

// --- Scenario Data Types ---

interface ProxyRule {
  id: string;
  type: "target" | "direct" | "upstream" | "health" | "policy" | "reload";
  pattern: string;
  action: string;
  matched: boolean;
}

interface RequestHeader {
  key: string;
  value: string;
  /** Added by rust_proxy itself (the client never sends it). */
  modified?: boolean;
  redacted?: boolean;
}

interface TimingBreakdown {
  dns: number;
  /** Daemon: accept the redirected socket and pick an upstream proxy. */
  proxyProcessing: number;
  /** CONNECT round trip to the upstream HTTP proxy. */
  connect: number;
  /** End-to-end TLS handshake, passed through the tunnel untouched. */
  tls: number;
  serverWait: number;
}

interface LogEntry {
  timestamp: string;
  level: "info" | "warn" | "error" | "debug";
  message: string;
}

interface ScenarioStep {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  /** CONNECT (tunneled), DIRECT (never redirected) or TRACE (diagnostic run). */
  method: string;
  url: string;
  /** Upstream proxy that carries the tunnel ("" when none does). */
  upstream: string;
  /** Status of the tunnel request; 0 when rust_proxy never handles the connection. */
  statusCode: number;
  statusText: string;
  /** What rust_proxy sends to the upstream proxy. */
  requestHeaders: RequestHeader[];
  /** What comes back (from the upstream proxy, or from the daemon itself). */
  responseHeaders: RequestHeader[];
  timing: TimingBreakdown;
  totalLatency: number;
  payloadNote: string;
  rules: ProxyRule[];
  logs: LogEntry[];
  packetColor: string;
  responseColor: string;
  flowState: "tunneled" | "direct" | "failover" | "rejected" | "reloaded" | "traced";
}

const SCENARIOS: ScenarioStep[] = [
  {
    id: "tunneled",
    label: "Target: Tunneled",
    icon: <Lock className="h-3 w-3" />,
    description:
      "api.anthropic.com is a target, so iptables redirects it to the daemon, which tunnels it through the upstream proxy with CONNECT. TLS passes through untouched.",
    method: "CONNECT",
    url: "api.anthropic.com -> 160.79.104.10:443",
    upstream: "mesh-us",
    statusCode: 200,
    statusText: "Connection established",
    requestHeaders: [
      { key: "Request-Line", value: "CONNECT 160.79.104.10:443 HTTP/1.1" },
      { key: "Host", value: "160.79.104.10:443" },
      {
        key: "Proxy-Authorization",
        value: "Basic ...redacted",
        modified: true,
        redacted: true,
      },
    ],
    responseHeaders: [{ key: "Status-Line", value: "HTTP/1.1 200 Connection established" }],
    timing: { dns: 4, proxyProcessing: 0.3, connect: 38, tls: 52, serverWait: 1180 },
    totalLatency: 1274.3,
    payloadNote:
      "Encrypted TLS records, copied byte-for-byte in both directions.\nrust_proxy never terminates TLS, so request and response bodies\n(and the client's API key) are never visible to it.",
    rules: [
      {
        id: "r1",
        type: "target",
        pattern: "api.anthropic.com",
        action: "IP in ipset rust_proxy_targets",
        matched: true,
      },
      {
        id: "r2",
        type: "upstream",
        pattern: "mesh-us",
        action: "Active proxy (healthy)",
        matched: true,
      },
      {
        id: "r3",
        type: "direct",
        pattern: "everything else",
        action: "Not redirected",
        matched: false,
      },
    ],
    logs: [
      {
        timestamp: "14:22:01.342",
        level: "debug",
        message: "Selected proxy for connection proxy=mesh-us strategy=Single",
      },
      {
        timestamp: "14:22:01.342",
        level: "debug",
        message: "Daemon log: nothing else per tunnel (TLS is copied, never decrypted)",
      },
      {
        timestamp: "14:22:05.010",
        level: "info",
        message: "$ rust_proxy list   # Sent/Received for mesh-us now include this tunnel",
      },
    ],
    packetColor: "#60a5fa",
    responseColor: "#34d399",
    flowState: "tunneled",
  },
  {
    id: "direct",
    label: "Non-Target: Direct",
    icon: <Globe className="h-3 w-3" />,
    description:
      "api.github.com is not a target, so its IPs are not in the ipset. iptables leaves the connection alone: it goes straight out and the daemon never sees it.",
    method: "DIRECT",
    url: "api.github.com -> 140.82.112.6:443",
    upstream: "",
    statusCode: 0,
    statusText: "Not redirected",
    requestHeaders: [],
    responseHeaders: [],
    timing: { dns: 4, proxyProcessing: 0, connect: 0, tls: 22, serverWait: 68 },
    totalLatency: 94,
    payloadNote:
      "Nothing to show: the connection was never redirected, so rust_proxy\nsent no CONNECT request and adds no overhead.",
    rules: [
      {
        id: "r1",
        type: "target",
        pattern: "api.github.com",
        action: "Not in targets list",
        matched: false,
      },
      {
        id: "r2",
        type: "direct",
        pattern: "140.82.112.6",
        action: "No ipset match: normal routing",
        matched: true,
      },
    ],
    logs: [
      { timestamp: "14:23:15.001", level: "info", message: "$ rust_proxy test api.github.com" },
      { timestamp: "14:23:15.006", level: "info", message: "Resolved IPs: 140.82.112.6" },
      {
        timestamp: "14:23:15.006",
        level: "warn",
        message: "WOULD NOT BE PROXIED (direct connection)",
      },
      {
        timestamp: "14:23:15.006",
        level: "debug",
        message: "Daemon log: no entry (connection never redirected)",
      },
    ],
    packetColor: "#60a5fa",
    responseColor: "#34d399",
    flowState: "direct",
  },
  {
    id: "failover",
    label: "Failover",
    icon: <Gauge className="h-3 w-3" />,
    description:
      "Health checks against mesh-us keep failing, so auto-failover sends new tunnels to the next proxy by priority. Failback returns to mesh-us after it recovers.",
    method: "CONNECT",
    url: "api.openai.com -> 162.159.140.245:443",
    upstream: "backup-eu",
    statusCode: 200,
    statusText: "Connection established",
    requestHeaders: [
      { key: "Request-Line", value: "CONNECT 162.159.140.245:443 HTTP/1.1" },
      { key: "Host", value: "162.159.140.245:443" },
      {
        key: "Proxy-Authorization",
        value: "Basic ...redacted",
        modified: true,
        redacted: true,
      },
    ],
    responseHeaders: [{ key: "Status-Line", value: "HTTP/1.1 200 Connection established" }],
    timing: { dns: 3, proxyProcessing: 0.4, connect: 64, tls: 58, serverWait: 940 },
    totalLatency: 1065.4,
    payloadNote:
      "Same encrypted TLS stream, now carried by backup-eu.\nFailover changes the route for new connections only;\nthe client needs no reconfiguration.",
    rules: [
      {
        id: "r1",
        type: "target",
        pattern: "api.openai.com",
        action: "IP in ipset rust_proxy_targets",
        matched: true,
      },
      {
        id: "r2",
        type: "health",
        pattern: "mesh-us",
        action: "Health check failed",
        matched: true,
      },
      {
        id: "r3",
        type: "upstream",
        pattern: "backup-eu",
        action: "Next by priority (healthy)",
        matched: true,
      },
    ],
    logs: [
      {
        timestamp: "14:24:02.100",
        level: "warn",
        message: "Proxy health check failed proxy_id=mesh-us",
      },
      {
        timestamp: "14:24:02.101",
        level: "warn",
        message: "Failover triggered from=mesh-us to=backup-eu reason=health check failure",
      },
      {
        timestamp: "14:24:05.410",
        level: "debug",
        message: "Selected proxy for connection proxy=backup-eu strategy=Single",
      },
      {
        timestamp: "14:26:32.200",
        level: "info",
        message: 'Failback triggered - returning to original proxy to=Some("mesh-us")',
      },
    ],
    packetColor: "#f59e0b",
    responseColor: "#34d399",
    flowState: "failover",
  },
  {
    id: "rejected",
    label: "All Proxies Down",
    icon: <Ban className="h-3 w-3" />,
    description:
      "No upstream proxy is healthy. The default fail_closed policy refuses the connection instead of letting target traffic leak out directly.",
    method: "CONNECT",
    url: "api.anthropic.com -> 160.79.104.10:443",
    upstream: "",
    statusCode: 503,
    statusText: "No healthy proxy",
    requestHeaders: [],
    responseHeaders: [
      { key: "Status-Line", value: "HTTP/1.1 503 Service Unavailable" },
      { key: "Content-Type", value: "text/plain" },
      { key: "Connection", value: "close" },
    ],
    timing: { dns: 4, proxyProcessing: 0.4, connect: 0, tls: 0, serverWait: 0 },
    totalLatency: 4.4,
    payloadNote:
      "No tunnel was opened and nothing was sent upstream. The daemon\nanswers \"No healthy proxy available\" itself and closes the socket,\nso the client sees a failed connection.",
    rules: [
      {
        id: "r1",
        type: "target",
        pattern: "api.anthropic.com",
        action: "IP in ipset rust_proxy_targets",
        matched: true,
      },
      {
        id: "r2",
        type: "health",
        pattern: "mesh-us, backup-eu",
        action: "All unhealthy",
        matched: true,
      },
      {
        id: "r3",
        type: "policy",
        pattern: "fail_closed (default)",
        action: "Reject; never go direct",
        matched: true,
      },
    ],
    logs: [
      {
        timestamp: "14:25:30.001",
        level: "warn",
        message: "Proxy health check failed proxy_id=mesh-us",
      },
      {
        timestamp: "14:25:30.002",
        level: "warn",
        message: "Proxy health check failed proxy_id=backup-eu",
      },
      {
        timestamp: "14:25:41.310",
        level: "error",
        message:
          "Degradation policy failed error=No healthy proxy available (fail_closed policy) policy=FailClosed",
      },
      {
        timestamp: "14:25:41.310",
        level: "warn",
        message: "connection error: No healthy proxy available (fail_closed policy)",
      },
    ],
    packetColor: "#ef4444",
    responseColor: "#ef4444",
    flowState: "rejected",
  },
  {
    id: "reloaded",
    label: "Live Reload",
    icon: <Database className="h-3 w-3" />,
    description:
      "You add a target while the daemon runs. It applies the config change live and updates the ipset: no restart, no dropped tunnels.",
    method: "CONNECT",
    url: "generativelanguage.googleapis.com -> 142.250.72.10:443",
    upstream: "mesh-us",
    statusCode: 200,
    statusText: "Connection established",
    requestHeaders: [
      { key: "Request-Line", value: "CONNECT 142.250.72.10:443 HTTP/1.1" },
      { key: "Host", value: "142.250.72.10:443" },
      {
        key: "Proxy-Authorization",
        value: "Basic ...redacted",
        modified: true,
        redacted: true,
      },
    ],
    responseHeaders: [{ key: "Status-Line", value: "HTTP/1.1 200 Connection established" }],
    timing: { dns: 5, proxyProcessing: 0.3, connect: 40, tls: 48, serverWait: 620 },
    totalLatency: 713.3,
    payloadNote:
      "The new target applies to new connections. Tunnels opened before\nthe reload keep running untouched.",
    rules: [
      {
        id: "r1",
        type: "reload",
        pattern: "config.toml",
        action: "Change detected, applied live",
        matched: true,
      },
      {
        id: "r2",
        type: "target",
        pattern: "generativelanguage.googleapis.com",
        action: "Added to ipset",
        matched: true,
      },
      {
        id: "r3",
        type: "upstream",
        pattern: "mesh-us",
        action: "Active proxy (healthy)",
        matched: true,
      },
    ],
    logs: [
      {
        timestamp: "14:26:10.500",
        level: "info",
        message: "$ rust_proxy targets add generativelanguage.googleapis.com --provider google",
      },
      { timestamp: "14:26:10.742", level: "info", message: "Routing generation applied" },
      { timestamp: "14:26:10.743", level: "info", message: "Configuration hot-reloaded" },
      {
        timestamp: "14:26:12.031",
        level: "debug",
        message: "Selected proxy for connection proxy=mesh-us strategy=Single",
      },
    ],
    packetColor: "#a78bfa",
    responseColor: "#34d399",
    flowState: "reloaded",
  },
  {
    id: "traced",
    label: "Test & Trace",
    icon: <FileSearch className="h-3 w-3" />,
    description:
      "test predicts whether a destination would be proxied. trace --tls runs DNS, proxy selection, CONNECT and a TLS handshake through the upstream, timing each step.",
    method: "TRACE",
    url: "rust_proxy trace api.anthropic.com --tls",
    upstream: "mesh-us",
    statusCode: 200,
    statusText: "Connection established",
    requestHeaders: [
      { key: "Request-Line", value: "CONNECT api.anthropic.com:443 HTTP/1.1" },
      { key: "Host", value: "api.anthropic.com:443" },
      {
        key: "Proxy-Authorization",
        value: "Basic ...redacted",
        modified: true,
        redacted: true,
      },
    ],
    responseHeaders: [{ key: "Status-Line", value: "HTTP/1.1 200 Connection established" }],
    timing: { dns: 6, proxyProcessing: 0.2, connect: 41, tls: 55, serverWait: 0 },
    totalLatency: 102.2,
    payloadNote:
      "trace stops after the TLS handshake and sends no API request.\nAdd --json (or --format toon) for machine-readable steps.",
    rules: [
      {
        id: "r1",
        type: "target",
        pattern: "api.anthropic.com",
        action: "test: WOULD BE PROXIED via 'mesh-us'",
        matched: true,
      },
      {
        id: "r2",
        type: "upstream",
        pattern: "mesh-us",
        action: "Proxy selection (strategy: Single)",
        matched: true,
      },
      {
        id: "r3",
        type: "health",
        pattern: "TLS handshake",
        action: "Completed through the tunnel",
        matched: true,
      },
    ],
    logs: [
      {
        timestamp: "14:27:05.100",
        level: "info",
        message: "DNS resolution: Resolved 1 IP(s): 160.79.104.10 (6ms)",
      },
      {
        timestamp: "14:27:05.100",
        level: "info",
        message: "Proxy selection: Selected mesh-us (strategy: Single)",
      },
      {
        timestamp: "14:27:05.100",
        level: "info",
        message: "CONNECT request: Sent CONNECT for api.anthropic.com:443 (with auth)",
      },
      {
        timestamp: "14:27:05.141",
        level: "info",
        message: "Proxy response: HTTP status 200 (41ms)",
      },
      {
        timestamp: "14:27:05.196",
        level: "info",
        message: "TLS handshake: Handshake completed (55ms)",
      },
    ],
    packetColor: "#ec4899",
    responseColor: "#34d399",
    flowState: "traced",
  },
];

// --- SVG Flow Diagram Component ---

function FlowDiagram({ scenario, animating }: { scenario: ScenarioStep; animating: boolean }) {
  const isRejected = scenario.flowState === "rejected";
  const isDirect = scenario.flowState === "direct";
  const isTunneled = !isRejected && !isDirect;

  // SVG path coordinates: client -> rust_proxy daemon -> upstream HTTP proxy -> API
  const clientX = 50;
  const proxyX = 180;
  const upstreamX = 315;
  const serverX = 445;
  const midY = 42;
  const bypassY = 92;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 overflow-hidden">
      <DiagramScroller label="Routing flow diagram" minWidth={500}>
      <svg viewBox="0 0 500 100" className="w-full h-auto" aria-label="Routing flow diagram">
        {/* Connection lines (client -> daemon is the iptables REDIRECT hop) */}
        <line
          x1={clientX + 30}
          y1={midY}
          x2={proxyX - 34}
          y2={midY}
          stroke="white"
          strokeOpacity={isDirect ? 0.04 : 0.1}
          strokeWidth={1.5}
          strokeDasharray="4 4"
        />
        <line
          x1={proxyX + 34}
          y1={midY}
          x2={upstreamX - 38}
          y2={midY}
          stroke={isRejected ? "red" : "white"}
          strokeOpacity={isRejected ? 0.15 : isDirect ? 0.04 : 0.1}
          strokeWidth={1.5}
          strokeDasharray={isRejected ? "2 6" : "4 4"}
        />
        <line
          x1={upstreamX + 38}
          y1={midY}
          x2={serverX - 30}
          y2={midY}
          stroke={isRejected ? "red" : "white"}
          strokeOpacity={isRejected ? 0.15 : isDirect ? 0.04 : 0.1}
          strokeWidth={1.5}
          strokeDasharray={isRejected ? "2 6" : "4 4"}
        />

        {/* Direct path: not in the ipset, so iptables never redirects it */}
        {isDirect && (
          <g>
            <polyline
              points={`${clientX},${midY + 20} ${clientX},${bypassY} ${serverX},${bypassY} ${serverX},${midY + 20}`}
              fill="none"
              stroke="rgba(52,211,153,0.35)"
              strokeWidth={1.5}
              strokeDasharray="4 4"
            />
            <text
              x={(clientX + serverX) / 2}
              y={bypassY - 6}
              textAnchor="middle"
              fill="rgba(52,211,153,0.8)"
              fontSize={12}
              fontFamily="monospace"
            >
              direct (no ipset match)
            </text>
          </g>
        )}

        {/* Client node */}
        <rect
          x={clientX - 28}
          y={midY - 20}
          width={56}
          height={40}
          rx={8}
          fill="rgba(96,165,250,0.1)"
          stroke="rgba(96,165,250,0.3)"
          strokeWidth={1}
        />
        <text
          x={clientX}
          y={midY + 1}
          textAnchor="middle"
          fill="rgba(96,165,250,0.8)"
          fontSize={12}
          fontFamily="monospace"
          fontWeight={600}
        >
          Client
        </text>

        {/* rust_proxy daemon node */}
        <g opacity={isDirect ? 0.35 : 1}>
          <rect
            x={proxyX - 32}
            y={midY - 22}
            width={64}
            height={44}
            rx={8}
            fill="rgba(167,139,250,0.1)"
            stroke="rgba(167,139,250,0.3)"
            strokeWidth={1}
          />
          <text
            x={proxyX}
            y={midY - 3}
            textAnchor="middle"
            fill="rgba(167,139,250,0.8)"
            fontSize={12}
            fontFamily="monospace"
            fontWeight={600}
          >
            Rust
          </text>
          <text
            x={proxyX}
            y={midY + 12}
            textAnchor="middle"
            fill="rgba(167,139,250,0.8)"
            fontSize={12}
            fontFamily="monospace"
            fontWeight={600}
          >
            Proxy
          </text>
        </g>

        {/* Upstream HTTP proxy node */}
        <g opacity={isTunneled ? 1 : 0.35}>
          <rect
            x={upstreamX - 36}
            y={midY - 22}
            width={72}
            height={44}
            rx={8}
            fill={isRejected ? "rgba(239,68,68,0.05)" : "rgba(245,158,11,0.1)"}
            stroke={isRejected ? "rgba(239,68,68,0.2)" : "rgba(245,158,11,0.3)"}
            strokeWidth={1}
          />
          <text
            x={upstreamX}
            y={midY - 3}
            textAnchor="middle"
            fill={isRejected ? "rgba(239,68,68,0.6)" : "rgba(245,158,11,0.85)"}
            fontSize={12}
            fontFamily="monospace"
            fontWeight={600}
          >
            Upstream
          </text>
          <text
            x={upstreamX}
            y={midY + 12}
            textAnchor="middle"
            fill={isRejected ? "rgba(239,68,68,0.6)" : "rgba(245,158,11,0.85)"}
            fontSize={12}
            fontFamily="monospace"
          >
            {scenario.upstream || (isRejected ? "all down" : "unused")}
          </text>
        </g>

        {/* API server node */}
        <rect
          x={serverX - 28}
          y={midY - 20}
          width={56}
          height={40}
          rx={8}
          fill={isRejected ? "rgba(239,68,68,0.05)" : "rgba(52,211,153,0.1)"}
          stroke={isRejected ? "rgba(239,68,68,0.15)" : "rgba(52,211,153,0.3)"}
          strokeWidth={1}
        />
        <text
          x={serverX}
          y={midY + 4}
          textAnchor="middle"
          fill={isRejected ? "rgba(239,68,68,0.4)" : "rgba(52,211,153,0.8)"}
          fontSize={12}
          fontFamily="monospace"
          fontWeight={600}
        >
          API
        </text>

        {/* Rejected X mark: no tunnel is opened */}
        {isRejected && (
          <g>
            <line
              x1={proxyX + 57}
              y1={midY - 12}
              x2={proxyX + 77}
              y2={midY + 12}
              stroke="rgba(239,68,68,0.6)"
              strokeWidth={2}
              strokeLinecap="round"
            />
            <line
              x1={proxyX + 77}
              y1={midY - 12}
              x2={proxyX + 57}
              y2={midY + 12}
              stroke="rgba(239,68,68,0.6)"
              strokeWidth={2}
              strokeLinecap="round"
            />
          </g>
        )}

        {/* Animated packet: client -> daemon (iptables REDIRECT) */}
        {animating && !isDirect && (
          <motion.circle
            cx={clientX + 30}
            cy={midY}
            r={4}
            fill={scenario.packetColor}
            initial={{ cx: clientX + 30, opacity: 0 }}
            animate={{ cx: proxyX - 34, opacity: [0, 1, 1, 0.5] }}
            transition={{ duration: 0.8, ease: "easeInOut", repeat: Infinity, repeatDelay: 1.4 }}
          />
        )}

        {/* Animated tunnel: daemon -> upstream proxy -> API */}
        {animating && isTunneled && (
          <motion.circle
            cx={proxyX + 34}
            cy={midY}
            r={4}
            fill={scenario.packetColor}
            initial={{ cx: proxyX + 34, opacity: 0 }}
            animate={{ cx: serverX - 30, opacity: [0, 1, 1, 0.5] }}
            transition={{
              duration: 0.8,
              ease: "easeInOut",
              delay: 0.5,
              repeat: Infinity,
              repeatDelay: 1.4,
            }}
          />
        )}

        {/* Animated response: API -> upstream -> daemon -> client */}
        {animating && isTunneled && (
          <motion.circle
            cx={serverX - 30}
            cy={midY + 8}
            r={3}
            fill={scenario.responseColor}
            initial={{ cx: serverX - 30, opacity: 0 }}
            animate={{ cx: clientX + 30, opacity: [0, 0.8, 0.8, 0] }}
            transition={{
              duration: 1.2,
              ease: "easeInOut",
              delay: 1.2,
              repeat: Infinity,
              repeatDelay: 1,
            }}
          />
        )}

        {/* Direct traffic: client -> API, bypassing rust_proxy entirely */}
        {animating && isDirect && (
          <motion.circle
            cx={clientX}
            cy={bypassY}
            r={4}
            fill={scenario.packetColor}
            initial={{ cx: clientX, opacity: 0 }}
            animate={{ cx: serverX, opacity: [0, 1, 1, 0.5] }}
            transition={{ duration: 1, ease: "easeInOut", repeat: Infinity, repeatDelay: 1.2 }}
          />
        )}
        {animating && isDirect && (
          <motion.circle
            cx={serverX}
            cy={bypassY - 1}
            r={3}
            fill={scenario.responseColor}
            initial={{ cx: serverX, opacity: 0 }}
            animate={{ cx: clientX, opacity: [0, 0.8, 0.8, 0] }}
            transition={{
              duration: 1,
              ease: "easeInOut",
              delay: 1.1,
              repeat: Infinity,
              repeatDelay: 1.2,
            }}
          />
        )}

        {/* Rejected: the daemon answers the client itself (fail_closed) */}
        {animating && isRejected && (
          <motion.circle
            cx={proxyX - 34}
            cy={midY + 8}
            r={3}
            fill="#ef4444"
            initial={{ cx: proxyX - 34, opacity: 0 }}
            animate={{ cx: clientX + 30, opacity: [0, 0.8, 0.8, 0] }}
            transition={{
              duration: 0.5,
              ease: "easeInOut",
              delay: 0.6,
              repeat: Infinity,
              repeatDelay: 1.7,
            }}
          />
        )}

        {/* Method + tunnel status labels */}
        <text
          x={clientX + 34}
          y={midY - 28}
          fill="var(--muted-foreground)"
          fontSize={12}
          fontFamily="monospace"
        >
          {scenario.method}
        </text>
        {scenario.statusCode > 0 && (
          <text
            x={(proxyX + upstreamX) / 2}
            y={midY - 28}
            textAnchor="middle"
            fill={scenario.statusCode >= 400 ? "rgba(239,68,68,0.6)" : "rgba(52,211,153,0.6)"}
            fontSize={12}
            fontFamily="monospace"
          >
            {scenario.statusCode}
          </text>
        )}
      </svg>
      </DiagramScroller>
    </div>
  );
}

// --- Header Tree View ---

function HeaderTree({ headers, title }: { headers: RequestHeader[]; title: string }) {
  const [expanded, setExpanded] = useState(true);

  return (
    <div className="rounded-lg border border-white/[0.06] bg-black/20 overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-white/[0.02] transition-colors"
      >
        {expanded ? (
          <ChevronDown className="h-3 w-3 text-muted-foreground" />
        ) : (
          <ChevronUp className="h-3 w-3 text-muted-foreground" />
        )}
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          {title}
        </span>
        <span className="text-xs text-muted-foreground font-mono">({headers.length})</span>
      </button>
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={SPRING}
            className="overflow-hidden"
          >
            <div className="px-3 pb-2 space-y-0.5">
              {headers.length === 0 && (
                <div className="font-mono text-xs text-muted-foreground">Nothing sent</div>
              )}
              {headers.map((h) => (
                <div
                  key={h.key}
                  className="flex items-start gap-2 font-mono text-xs leading-relaxed"
                >
                  <span className={h.modified ? "text-amber-400/80" : "text-blue-400/80"}>
                    {h.key}:
                  </span>
                  <span
                    className={`${h.redacted ? "text-red-400/80 line-through" : h.modified ? "text-amber-400/80" : "text-muted-foreground"} break-all`}
                  >
                    {h.value}
                  </span>
                  {h.modified && (
                    <span className="shrink-0 px-1 py-0.5 rounded text-xs bg-amber-500/10 text-amber-400/80 border border-amber-500/20">
                      ADDED
                    </span>
                  )}
                  {h.redacted && (
                    <span className="shrink-0 px-1 py-0.5 rounded text-xs bg-red-500/10 text-red-400/80 border border-red-500/20">
                      REDACTED
                    </span>
                  )}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// --- Latency Waterfall Chart ---

function LatencyWaterfall({ timing, total }: { timing: TimingBreakdown; total: number }) {
  const segments = [
    { label: "DNS", value: timing.dns, color: "bg-sky-400" },
    { label: "Daemon", value: timing.proxyProcessing, color: "bg-amber-400" },
    { label: "CONNECT", value: timing.connect, color: "bg-blue-400" },
    { label: "TLS", value: timing.tls, color: "bg-violet-400" },
    { label: "Server", value: timing.serverWait, color: "bg-emerald-400" },
  ];

  const maxVal = Math.max(total, 1);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Latency Waterfall
        </span>
        <span className="text-xs font-mono text-muted-foreground">
          {total < 1 ? `${total}ms` : `${Math.round(total)}ms`} total
        </span>
      </div>
      <div className="space-y-1">
        {segments.map((seg) => {
          const pct = (seg.value / maxVal) * 100;
          return (
            <div key={seg.label} className="flex items-center gap-2">
              <span className="text-xs text-muted-foreground font-mono w-14 text-right">
                {seg.label}
              </span>
              <div className="flex-1 h-3 rounded-full bg-white/[0.04] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${seg.color} opacity-60`}
                  initial={{ width: 0 }}
                  animate={{ width: `${Math.max(pct, pct > 0 ? 2 : 0)}%` }}
                  transition={SPRING}
                />
              </div>
              <span className="text-xs text-muted-foreground font-mono w-12">
                {seg.value < 1 && seg.value > 0 ? `${seg.value}ms` : `${Math.round(seg.value)}ms`}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// --- Rule Engine Panel ---

function RuleEnginePanel({ rules }: { rules: ProxyRule[] }) {
  const typeColors: Record<string, string> = {
    target: "text-emerald-400 bg-emerald-500/10 border-emerald-500/20",
    direct: "text-sky-400 bg-sky-500/10 border-sky-500/20",
    upstream: "text-amber-400 bg-amber-500/10 border-amber-500/20",
    health: "text-orange-400 bg-orange-500/10 border-orange-500/20",
    policy: "text-red-400 bg-red-500/10 border-red-500/20",
    reload: "text-violet-400 bg-violet-500/10 border-violet-500/20",
  };

  return (
    <div className="space-y-2">
      <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
        Routing Decision
      </span>
      <div className="space-y-1">
        {rules.map((rule) => (
          <motion.div
            key={rule.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={SPRING}
            className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg border ${
              rule.matched
                ? "border-white/[0.1] bg-white/[0.04]"
                : "border-white/[0.04] bg-white/[0.01]"
            }`}
          >
            {rule.matched ? (
              <CheckCircle className="h-3 w-3 text-emerald-400 shrink-0" />
            ) : (
              <div className="h-3 w-3 rounded-full border border-white/[0.1] shrink-0" />
            )}
            <span
              className={`px-1.5 py-0.5 rounded text-xs font-semibold uppercase border ${typeColors[rule.type] || "text-muted-foreground"}`}
            >
              {rule.type}
            </span>
            <span className="text-xs font-mono text-muted-foreground flex-1 truncate">
              {rule.pattern}
            </span>
            <span className="text-xs text-muted-foreground truncate">{rule.action}</span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// --- Live Log Stream ---

function LogStream({ logs, active }: { logs: LogEntry[]; active: boolean }) {
  const levelColors: Record<string, string> = {
    info: "text-blue-400/80",
    warn: "text-amber-400/80",
    error: "text-red-400/80",
    debug: "text-muted-foreground",
  };

  const levelBg: Record<string, string> = {
    info: "bg-blue-500/10",
    warn: "bg-amber-500/10",
    error: "bg-red-500/10",
    debug: "bg-white/[0.02]",
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Log
        </span>
        <motion.div
          animate={active ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
          transition={active ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
          className="h-1.5 w-1.5 rounded-full bg-emerald-500"
        />
      </div>
      <div className="rounded-lg border border-white/[0.06] bg-black/40 overflow-hidden">
        <div className="max-h-[120px] overflow-y-auto">
          {logs.map((log, idx) => (
            <motion.div
              key={`${log.timestamp}-${idx}`}
              initial={{ opacity: 0, x: -12 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ ...SPRING, delay: idx * 0.08 }}
              className={`flex items-start gap-2 px-3 py-1 font-mono text-xs border-b border-white/[0.03] last:border-0 ${levelBg[log.level]}`}
            >
              <span className="text-muted-foreground shrink-0">{log.timestamp}</span>
              <span className={`shrink-0 uppercase font-semibold ${levelColors[log.level]}`}>
                {log.level.padEnd(5)}
              </span>
              <span className="text-muted-foreground break-all">{log.message}</span>
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}

// --- Flow State Badge ---

function FlowStateBadge({ state }: { state: ScenarioStep["flowState"] }) {
  const config: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
    tunneled: {
      label: "Tunneled via Upstream",
      color: "border-emerald-500/30 bg-emerald-500/10 text-emerald-400",
      icon: <CheckCircle className="h-3 w-3" />,
    },
    direct: {
      label: "Direct (Not Redirected)",
      color: "border-sky-500/30 bg-sky-500/10 text-sky-400",
      icon: <Globe className="h-3 w-3" />,
    },
    failover: {
      label: "Failed Over",
      color: "border-orange-500/30 bg-orange-500/10 text-orange-400",
      icon: <Gauge className="h-3 w-3" />,
    },
    rejected: {
      label: "Fail Closed",
      color: "border-red-500/30 bg-red-500/10 text-red-400",
      icon: <Ban className="h-3 w-3" />,
    },
    reloaded: {
      label: "Hot Reloaded",
      color: "border-violet-500/30 bg-violet-500/10 text-violet-400",
      icon: <Database className="h-3 w-3" />,
    },
    traced: {
      label: "Route Traced",
      color: "border-pink-500/30 bg-pink-500/10 text-pink-400",
      icon: <FileSearch className="h-3 w-3" />,
    },
  };

  const c = config[state];
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={SPRING}
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-xs font-medium ${c.color}`}
    >
      {c.icon}
      {c.label}
    </motion.div>
  );
}

// --- Active Tab Selector for Details ---

type DetailTab = "headers" | "waterfall" | "rules" | "logs";

function DetailTabBar({
  active,
  onChange,
}: {
  active: DetailTab;
  onChange: (t: DetailTab) => void;
}) {
  const tabs: { id: DetailTab; label: string; icon: React.ReactNode }[] = [
    { id: "headers", label: "Tunnel", icon: <Eye className="h-3 w-3" /> },
    { id: "waterfall", label: "Timing", icon: <Clock className="h-3 w-3" /> },
    { id: "rules", label: "Routing", icon: <Shield className="h-3 w-3" /> },
    { id: "logs", label: "Logs", icon: <Terminal className="h-3 w-3" /> },
  ];

  return (
    <div className="flex gap-1 p-1 rounded-lg bg-white/[0.02] border border-white/[0.06]">
      {tabs.map((tab) => (
        <motion.button
          key={tab.id}
          onClick={() => onChange(tab.id)}
          whileHover={{ scale: 1.03 }}
          whileTap={{ scale: 0.97 }}
          transition={SPRING_SNAPPY}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-colors ${
            active === tab.id
              ? "bg-white/[0.08] text-white/80 border border-white/[0.1]"
              : "text-muted-foreground hover:text-foreground border border-transparent"
          }`}
        >
          {tab.icon}
          {tab.label}
        </motion.button>
      ))}
    </div>
  );
}

// =============================================================================
// MAIN INTERACTIVE COMPONENT
// =============================================================================

function InteractiveTrafficInspectorImpl() {
  const [stepIndex, setStepIndex] = useState(0);
  const [activeTab, setActiveTab] = useState<DetailTab>("headers");
  const [isAnimating, setIsAnimating] = useState(true);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const scenario = SCENARIOS[stepIndex];

  const setScenarioStep = useCallback((nextStep: number | ((current: number) => number)) => {
    setStepIndex((current) => {
      const resolved = typeof nextStep === "function" ? nextStep(current) : nextStep;
      return Math.max(0, Math.min(SCENARIOS.length - 1, resolved));
    });
  }, []);

  const goNext = useCallback(() => {
    setScenarioStep((prev) => prev + 1);
  }, [setScenarioStep]);

  const goPrev = useCallback(() => {
    setScenarioStep((prev) => prev - 1);
  }, [setScenarioStep]);

  // Reset tab when switching scenarios so we always see something relevant
  useEffect(() => {
    const timer = setTimeout(() => {
      setActiveTab("headers");
    }, 0);
    return () => clearTimeout(timer);
  }, [stepIndex]);

  return (
    <div
      ref={rootRef}
      className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-blue-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/3 w-48 h-48 bg-violet-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-6 space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-2">
            <motion.div
              animate={inView ? { rotate: [0, 360] } : { rotate: 0 }}
              transition={
                inView ? { duration: 20, repeat: Infinity, ease: "linear" } : { duration: 0.2 }
              }
            >
              <Activity className="h-4 w-4 text-muted-foreground" />
            </motion.div>
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Routing Inspector
            </span>
            <motion.div
              animate={inView ? { opacity: [1, 0.3, 1] } : { opacity: 1 }}
              transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
              className="h-1.5 w-1.5 rounded-full bg-emerald-500"
            />
            <span className="text-xs text-emerald-400/80 font-medium">LIVE</span>
          </div>

          <div className="flex gap-2">
            <motion.button
              onClick={() => setIsAnimating(!isAnimating)}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              transition={SPRING_SNAPPY}
              className={`px-3 py-1.5 rounded-lg border text-xs font-medium flex items-center gap-1.5 ${
                isAnimating
                  ? "border-amber-500/30 bg-amber-500/10 text-amber-400"
                  : "border-white/[0.08] bg-white/[0.02] text-muted-foreground"
              }`}
            >
              {isAnimating ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {isAnimating ? "Pause" : "Animate"}
            </motion.button>
          </div>
        </div>

        {/* Scenario stepper */}
        <div className="space-y-3">
          {/* Step pills - scrollable */}
          <div className="flex gap-1.5 overflow-x-auto pb-1 scrollbar-none">
            {SCENARIOS.map((s, idx) => (
              <motion.button
                key={s.id}
                onClick={() => setScenarioStep(idx)}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                transition={SPRING_SNAPPY}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition-colors border ${
                  stepIndex === idx
                    ? "bg-white/[0.1] text-white border-white/[0.15]"
                    : "text-muted-foreground hover:text-foreground border-transparent hover:border-white/[0.06]"
                }`}
              >
                {s.icon}
                {s.label}
              </motion.button>
            ))}
          </div>

          {/* Step navigation + description */}
          <div className="flex items-center gap-3">
            <motion.button
              type="button"
              onClick={goPrev}
              aria-label="Previous step"
              disabled={stepIndex === 0}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-muted-foreground hover:text-white/70 disabled:opacity-20 disabled:hover:text-muted-foreground shrink-0"
            >
              <ChevronLeft className="h-3.5 w-3.5" />
            </motion.button>

            <AnimatePresence mode="wait">
              <motion.div
                key={scenario.id}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={SPRING}
                className="flex-1 min-w-0"
              >
                <div className="flex items-center gap-2 mb-0.5 flex-wrap">
                  <span className="text-xs font-semibold text-white/80">{scenario.label}</span>
                  <span className="text-xs text-muted-foreground font-mono">
                    Step {stepIndex + 1}/{SCENARIOS.length}
                  </span>
                  <FlowStateBadge state={scenario.flowState} />
                </div>
                <p className="text-xs text-muted-foreground leading-relaxed line-clamp-2">
                  {scenario.description}
                </p>
              </motion.div>
            </AnimatePresence>

            <motion.button
              type="button"
              onClick={goNext}
              aria-label="Next step"
              disabled={stepIndex === SCENARIOS.length - 1}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-muted-foreground hover:text-white/70 disabled:opacity-20 disabled:hover:text-muted-foreground shrink-0"
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </motion.button>
          </div>
        </div>

        {/* Request summary bar */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + "-summary"}
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={SPRING}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-black/30 border border-white/[0.06] font-mono text-xs overflow-x-auto"
          >
            <span
              className={
                scenario.method === "DIRECT"
                  ? "text-emerald-400/80 font-semibold"
                  : "text-amber-400/80 font-semibold"
              }
            >
              {scenario.method}
            </span>
            <span className="text-muted-foreground truncate">{scenario.url}</span>
            <ArrowRight className="h-3 w-3 text-muted-foreground shrink-0" />
            {scenario.statusCode > 0 && (
              <span
                className={`font-semibold shrink-0 ${scenario.statusCode >= 400 ? "text-red-400" : "text-emerald-400/70"}`}
              >
                {scenario.statusCode}
              </span>
            )}
            <span
              className={`shrink-0 ${scenario.statusCode >= 400 ? "text-red-400/80" : "text-muted-foreground"}`}
            >
              {scenario.statusText}
            </span>
            <span className="text-muted-foreground shrink-0">|</span>
            <span
              className={`shrink-0 ${scenario.totalLatency > 1000 ? "text-amber-400/70" : "text-muted-foreground"}`}
            >
              {scenario.totalLatency < 1
                ? `${scenario.totalLatency}ms`
                : `${Math.round(scenario.totalLatency)}ms`}
            </span>
          </motion.div>
        </AnimatePresence>

        {/* Animated flow diagram */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + "-flow"}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <FlowDiagram scenario={scenario} animating={isAnimating && inView} />
          </motion.div>
        </AnimatePresence>

        {/* Detail tabs */}
        <DetailTabBar active={activeTab} onChange={setActiveTab} />

        {/* Tab content */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + "-" + activeTab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING}
          >
            {activeTab === "headers" && (
              <div className="space-y-3">
                <HeaderTree headers={scenario.requestHeaders} title="Sent to Upstream Proxy" />
                <HeaderTree headers={scenario.responseHeaders} title="Reply" />
                {/* Payload: rust_proxy never decrypts it */}
                <div className="rounded-lg border border-white/[0.06] bg-black/30 overflow-hidden">
                  <div className="px-3 py-2 border-b border-white/[0.04]">
                    <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                      Payload
                    </span>
                  </div>
                  <pre className="px-3 py-2 font-mono text-xs text-muted-foreground leading-relaxed overflow-x-auto whitespace-pre">
                    {scenario.payloadNote}
                  </pre>
                </div>
              </div>
            )}

            {activeTab === "waterfall" && (
              <div className="space-y-4">
                <LatencyWaterfall timing={scenario.timing} total={scenario.totalLatency} />
                {/* Additional stats */}
                <div className="grid grid-cols-3 gap-3">
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-xs uppercase tracking-wider text-muted-foreground block">
                      Total
                    </span>
                    <span className="text-sm font-mono text-white/60 font-semibold">
                      {scenario.totalLatency < 1
                        ? `${scenario.totalLatency}ms`
                        : `${Math.round(scenario.totalLatency)}ms`}
                    </span>
                  </div>
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-xs uppercase tracking-wider text-muted-foreground block">
                      Tunnel Setup
                    </span>
                    <span className="text-sm font-mono text-amber-400/70 font-semibold">
                      {`${Math.round(scenario.timing.proxyProcessing + scenario.timing.connect)}ms`}
                    </span>
                  </div>
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-xs uppercase tracking-wider text-muted-foreground block">
                      Setup %
                    </span>
                    <span className="text-sm font-mono text-white/60 font-semibold">
                      {scenario.totalLatency > 0
                        ? `${(((scenario.timing.proxyProcessing + scenario.timing.connect) / scenario.totalLatency) * 100).toFixed(1)}%`
                        : "0%"}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {activeTab === "rules" && <RuleEnginePanel rules={scenario.rules} />}

            {activeTab === "logs" && <LogStream logs={scenario.logs} active={inView} />}
          </motion.div>
        </AnimatePresence>

        {/* Tip */}
        <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/[0.06]">
          <Eye className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
          <span className="text-xs text-muted-foreground">
            Step through 6 routing scenarios. Each shows the path a connection takes, the CONNECT
            exchange with the upstream proxy, a latency breakdown, the routing decision, and log
            lines. Payloads never appear: rust_proxy does not decrypt TLS.
          </span>
        </div>
      </div>
    </div>
  );
}
