'use client';

import { useState, useCallback, useEffect } from 'react';
import { motion, AnimatePresence } from "@/components/motion";
import {
  Shield,
  Terminal,
  Zap,
  Activity,
  Lock,
  Settings,
  Play,
  Eye,
  ArrowRight,
  Pause,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  Globe,
  Clock,
  Ban,
  Gauge,
  Database,
  FileSearch,
  CheckCircle,
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
const InteractiveTrafficInspector = InteractiveTrafficInspectorImpl;

export function RustProxyLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Route and inspect network traffic through a transparent proxy for debugging API issues.
      </GoalBanner>

      {/* Section 1: What Is Rust Proxy */}
      <Section title="What Is Rust Proxy?" icon={<Shield className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>Rust Proxy</Highlight> is a high-performance transparent proxy
          for inspecting HTTP/HTTPS traffic between your tools and external services.
          It sits between clients and servers, logging requests and responses without
          modifying them.
        </Paragraph>
        <Paragraph>
          When debugging network issues with AI APIs or other services, Rust Proxy
          lets you see exactly what&apos;s going over the wire without changing your
          application configuration.
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
              description="TLS interception capable"
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
              title="Full Logging"
              description="Headers, bodies, timing"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Start the proxy and route traffic through it.
        </Paragraph>

        <CodeBlock
          code={`# Start the proxy on default port
rust_proxy start

# Start on a specific port
rust_proxy start --port 8080

# Route curl traffic through the proxy
HTTPS_PROXY=http://localhost:8080 curl https://api.example.com

# View captured traffic
rust_proxy logs`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Set <code>HTTPS_PROXY</code> environment variable to route any tool&apos;s
          traffic through the proxy.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'rust_proxy start', description: 'Start the proxy server' },
            { command: 'rust_proxy start --port 8080', description: 'Start on a specific port' },
            { command: 'rust_proxy logs', description: 'View captured traffic' },
            { command: 'rust_proxy stop', description: 'Stop the proxy' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 4: Use Cases */}
      <Section title="Debugging Scenarios" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Common situations where Rust Proxy helps.
        </Paragraph>

        <CodeBlock
          code={`# Debug API authentication issues
HTTPS_PROXY=http://localhost:8080 \
  claude "hello" 2>/dev/null
rust_proxy logs --last 1 --headers

# Measure API latency
rust_proxy logs --timing

# Filter by domain
rust_proxy logs --domain api.anthropic.com`}
          filename="Debug Scenarios"
        />

        <TipBox variant="warning">
          Rust Proxy can log sensitive data including API keys in headers.
          Use it only for debugging and stop it when done.
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
            <p className="text-white/80 text-sm mt-1">Low-level proxy complements RANO&apos;s AI-specific observer</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">RP + CAUT</span>
            <p className="text-white/80 text-sm mt-1">Traffic data feeds usage tracking</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">RP + CAAM</span>
            <p className="text-white/80 text-sm mt-1">Verify which API keys are being used</p>
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
  type: 'allow' | 'modify' | 'block' | 'rate-limit' | 'cache' | 'inspect';
  pattern: string;
  action: string;
  matched: boolean;
}

interface RequestHeader {
  key: string;
  value: string;
  modified?: boolean;
  redacted?: boolean;
}

interface TimingBreakdown {
  dns: number;
  tls: number;
  proxyProcessing: number;
  serverWait: number;
  transfer: number;
}

interface LogEntry {
  timestamp: string;
  level: 'info' | 'warn' | 'error' | 'debug';
  message: string;
}

interface ScenarioStep {
  id: string;
  label: string;
  icon: React.ReactNode;
  description: string;
  method: string;
  url: string;
  domain: string;
  path: string;
  statusCode: number;
  statusText: string;
  requestHeaders: RequestHeader[];
  responseHeaders: RequestHeader[];
  timing: TimingBreakdown;
  totalLatency: number;
  bodyPreview: string;
  rules: ProxyRule[];
  logs: LogEntry[];
  packetColor: string;
  responseColor: string;
  flowState: 'normal' | 'modified' | 'blocked' | 'rate-limited' | 'cached' | 'inspected';
}

const SCENARIOS: ScenarioStep[] = [
  {
    id: 'normal',
    label: 'Normal Request',
    icon: <Globe className="h-3 w-3" />,
    description: 'A standard GET request passes through the proxy transparently. No modifications, no blocks - just logged for inspection.',
    method: 'GET',
    url: 'https://api.github.com/repos/user/project',
    domain: 'api.github.com',
    path: '/repos/user/project',
    statusCode: 200,
    statusText: 'OK',
    requestHeaders: [
      { key: 'Host', value: 'api.github.com' },
      { key: 'Accept', value: 'application/vnd.github.v3+json' },
      { key: 'Authorization', value: 'Bearer ghp_...redacted', redacted: true },
      { key: 'User-Agent', value: 'curl/8.4.0' },
    ],
    responseHeaders: [
      { key: 'Content-Type', value: 'application/json; charset=utf-8' },
      { key: 'X-RateLimit-Remaining', value: '4832' },
      { key: 'X-GitHub-Request-Id', value: 'D4F2:1A3B:8C2E' },
      { key: 'Cache-Control', value: 'private, max-age=60' },
    ],
    timing: { dns: 4, tls: 22, proxyProcessing: 1, serverWait: 68, transfer: 14 },
    totalLatency: 109,
    bodyPreview: '{\n  "id": 123456,\n  "full_name": "user/project",\n  "stargazers_count": 42\n}',
    rules: [
      { id: 'r1', type: 'allow', pattern: '*.github.com', action: 'Pass through', matched: true },
      { id: 'r2', type: 'block', pattern: '*.tracking.io', action: 'Block request', matched: false },
      { id: 'r3', type: 'rate-limit', pattern: '*.openai.com', action: '10 req/min', matched: false },
    ],
    logs: [
      { timestamp: '14:22:01.342', level: 'info', message: 'New connection from 127.0.0.1:54212' },
      { timestamp: '14:22:01.343', level: 'debug', message: 'Rule match: *.github.com -> ALLOW' },
      { timestamp: '14:22:01.345', level: 'info', message: 'GET api.github.com/repos/user/project -> 200 (109ms)' },
    ],
    packetColor: '#60a5fa',
    responseColor: '#34d399',
    flowState: 'normal',
  },
  {
    id: 'modified-header',
    label: 'Header Injection',
    icon: <Settings className="h-3 w-3" />,
    description: 'The proxy injects a custom tracing header to correlate requests across services. The original request is untouched.',
    method: 'POST',
    url: 'https://api.anthropic.com/v1/messages',
    domain: 'api.anthropic.com',
    path: '/v1/messages',
    statusCode: 200,
    statusText: 'OK',
    requestHeaders: [
      { key: 'Host', value: 'api.anthropic.com' },
      { key: 'Content-Type', value: 'application/json' },
      { key: 'X-API-Key', value: 'sk-ant-...redacted', redacted: true },
      { key: 'X-Proxy-Trace-Id', value: 'rp-7f3a2b1c-e9d4', modified: true },
      { key: 'X-Forwarded-For', value: '192.168.1.100', modified: true },
    ],
    responseHeaders: [
      { key: 'Content-Type', value: 'application/json' },
      { key: 'X-Request-Id', value: 'req_01HXYZ...' },
      { key: 'X-Proxy-Latency', value: '2ms', modified: true },
    ],
    timing: { dns: 2, tls: 18, proxyProcessing: 2, serverWait: 1180, transfer: 38 },
    totalLatency: 1240,
    bodyPreview: '{\n  "content": [{\n    "type": "text",\n    "text": "Hello! How can I help?"\n  }]\n}',
    rules: [
      { id: 'r1', type: 'modify', pattern: '*.anthropic.com', action: 'Add trace header', matched: true },
      { id: 'r2', type: 'modify', pattern: '*', action: 'Add X-Forwarded-For', matched: true },
      { id: 'r3', type: 'allow', pattern: '*', action: 'Pass through', matched: true },
    ],
    logs: [
      { timestamp: '14:23:15.001', level: 'info', message: 'New connection from 127.0.0.1:54218' },
      { timestamp: '14:23:15.002', level: 'debug', message: 'Rule match: *.anthropic.com -> MODIFY (trace header)' },
      { timestamp: '14:23:15.002', level: 'info', message: 'Injected X-Proxy-Trace-Id: rp-7f3a2b1c-e9d4' },
      { timestamp: '14:23:16.242', level: 'info', message: 'POST api.anthropic.com/v1/messages -> 200 (1240ms)' },
    ],
    packetColor: '#f59e0b',
    responseColor: '#34d399',
    flowState: 'modified',
  },
  {
    id: 'blocked',
    label: 'Blocked Request',
    icon: <Ban className="h-3 w-3" />,
    description: 'A request to a blocked domain is intercepted by the proxy. The client receives a 403 immediately without the request ever reaching the server.',
    method: 'POST',
    url: 'https://telemetry.tracking.io/v2/events',
    domain: 'telemetry.tracking.io',
    path: '/v2/events',
    statusCode: 403,
    statusText: 'Forbidden (Proxy)',
    requestHeaders: [
      { key: 'Host', value: 'telemetry.tracking.io' },
      { key: 'Content-Type', value: 'application/json' },
      { key: 'User-Agent', value: 'analytics-sdk/2.1' },
    ],
    responseHeaders: [
      { key: 'X-Proxy-Blocked', value: 'true', modified: true },
      { key: 'X-Block-Rule', value: '*.tracking.io', modified: true },
    ],
    timing: { dns: 0, tls: 0, proxyProcessing: 1, serverWait: 0, transfer: 0 },
    totalLatency: 1,
    bodyPreview: '{\n  "error": "Request blocked by proxy rule",\n  "rule": "*.tracking.io"\n}',
    rules: [
      { id: 'r1', type: 'block', pattern: '*.tracking.io', action: 'Block request', matched: true },
      { id: 'r2', type: 'block', pattern: '*.ads.network', action: 'Block request', matched: false },
    ],
    logs: [
      { timestamp: '14:24:02.100', level: 'info', message: 'New connection from 127.0.0.1:54220' },
      { timestamp: '14:24:02.100', level: 'warn', message: 'BLOCKED: telemetry.tracking.io matches *.tracking.io' },
      { timestamp: '14:24:02.101', level: 'info', message: 'Returned 403 to client (1ms, request never sent)' },
    ],
    packetColor: '#ef4444',
    responseColor: '#ef4444',
    flowState: 'blocked',
  },
  {
    id: 'rate-limited',
    label: 'Rate Limited',
    icon: <Gauge className="h-3 w-3" />,
    description: 'The proxy enforces a rate limit. After 10 requests/minute to OpenAI, subsequent requests are queued and retried with exponential backoff.',
    method: 'POST',
    url: 'https://api.openai.com/v1/chat/completions',
    domain: 'api.openai.com',
    path: '/v1/chat/completions',
    statusCode: 429,
    statusText: 'Too Many Requests',
    requestHeaders: [
      { key: 'Host', value: 'api.openai.com' },
      { key: 'Content-Type', value: 'application/json' },
      { key: 'Authorization', value: 'Bearer sk-...redacted', redacted: true },
    ],
    responseHeaders: [
      { key: 'X-Proxy-Queued', value: 'true', modified: true },
      { key: 'X-Proxy-Queue-Position', value: '3', modified: true },
      { key: 'Retry-After', value: '6' },
    ],
    timing: { dns: 0, tls: 0, proxyProcessing: 6200, serverWait: 0, transfer: 0 },
    totalLatency: 6200,
    bodyPreview: '{\n  "error": {\n    "type": "rate_limit_exceeded",\n    "message": "Rate limit: 10 req/min"\n  }\n}',
    rules: [
      { id: 'r1', type: 'rate-limit', pattern: '*.openai.com', action: '10 req/min', matched: true },
      { id: 'r2', type: 'allow', pattern: '*', action: 'Pass through', matched: false },
    ],
    logs: [
      { timestamp: '14:25:30.001', level: 'info', message: 'New connection from 127.0.0.1:54225' },
      { timestamp: '14:25:30.002', level: 'warn', message: 'Rate limit hit: api.openai.com (11/10 per min)' },
      { timestamp: '14:25:30.002', level: 'info', message: 'Request queued, position #3. Retry in 6s.' },
      { timestamp: '14:25:36.204', level: 'info', message: 'Queue drained. Forwarding request...' },
      { timestamp: '14:25:36.204', level: 'warn', message: 'Upstream returned 429. Client notified.' },
    ],
    packetColor: '#f59e0b',
    responseColor: '#f59e0b',
    flowState: 'rate-limited',
  },
  {
    id: 'cached',
    label: 'Cached Response',
    icon: <Database className="h-3 w-3" />,
    description: 'The proxy serves a cached response for a previously-seen identical request. Zero network round-trip, sub-millisecond latency.',
    method: 'GET',
    url: 'https://registry.npmjs.org/express/latest',
    domain: 'registry.npmjs.org',
    path: '/express/latest',
    statusCode: 200,
    statusText: 'OK (Cached)',
    requestHeaders: [
      { key: 'Host', value: 'registry.npmjs.org' },
      { key: 'Accept', value: 'application/json' },
      { key: 'If-None-Match', value: '"abc123"' },
    ],
    responseHeaders: [
      { key: 'Content-Type', value: 'application/json' },
      { key: 'X-Proxy-Cache', value: 'HIT', modified: true },
      { key: 'X-Cache-Age', value: '42s', modified: true },
      { key: 'X-Cache-TTL', value: '118s remaining', modified: true },
    ],
    timing: { dns: 0, tls: 0, proxyProcessing: 0.3, serverWait: 0, transfer: 0.2 },
    totalLatency: 0.5,
    bodyPreview: '{\n  "name": "express",\n  "version": "4.18.2",\n  "description": "Fast web framework"\n}',
    rules: [
      { id: 'r1', type: 'cache', pattern: '*.npmjs.org', action: 'Cache 180s', matched: true },
      { id: 'r2', type: 'allow', pattern: '*', action: 'Pass through', matched: false },
    ],
    logs: [
      { timestamp: '14:26:10.500', level: 'info', message: 'New connection from 127.0.0.1:54230' },
      { timestamp: '14:26:10.500', level: 'debug', message: 'Cache HIT for registry.npmjs.org/express/latest' },
      { timestamp: '14:26:10.500', level: 'info', message: 'Served from cache (0.5ms, age: 42s)' },
    ],
    packetColor: '#a78bfa',
    responseColor: '#a78bfa',
    flowState: 'cached',
  },
  {
    id: 'tls-inspection',
    label: 'TLS Inspection',
    icon: <FileSearch className="h-3 w-3" />,
    description: 'The proxy performs TLS termination and re-encryption for deep inspection. Certificate details and encrypted payload are visible.',
    method: 'POST',
    url: 'https://api.anthropic.com/v1/messages',
    domain: 'api.anthropic.com',
    path: '/v1/messages',
    statusCode: 200,
    statusText: 'OK',
    requestHeaders: [
      { key: 'Host', value: 'api.anthropic.com' },
      { key: 'Content-Type', value: 'application/json' },
      { key: 'X-API-Key', value: 'sk-ant-api03-...full-key-visible', redacted: false },
      { key: ':scheme', value: 'https (terminated at proxy)' },
    ],
    responseHeaders: [
      { key: 'Content-Type', value: 'application/json' },
      { key: 'X-TLS-Version', value: 'TLSv1.3', modified: true },
      { key: 'X-TLS-Cipher', value: 'TLS_AES_256_GCM_SHA384', modified: true },
      { key: 'X-Proxy-Cert', value: 'proxy-ca.pem (self-signed)', modified: true },
    ],
    timing: { dns: 3, tls: 45, proxyProcessing: 8, serverWait: 920, transfer: 24 },
    totalLatency: 1000,
    bodyPreview: '{\n  "model": "claude-sonnet-4-6-20250514",\n  "content": [{\n    "text": "Decrypted response visible"\n  }]\n}',
    rules: [
      { id: 'r1', type: 'inspect', pattern: '*.anthropic.com', action: 'TLS intercept + log body', matched: true },
      { id: 'r2', type: 'modify', pattern: '*', action: 'Add trace header', matched: true },
    ],
    logs: [
      { timestamp: '14:27:05.100', level: 'info', message: 'New connection from 127.0.0.1:54235' },
      { timestamp: '14:27:05.102', level: 'debug', message: 'TLS termination: presenting proxy CA cert to client' },
      { timestamp: '14:27:05.110', level: 'debug', message: 'Re-encrypting to upstream with TLSv1.3' },
      { timestamp: '14:27:05.118', level: 'info', message: 'Deep inspection: request body logged (1.2KB)' },
      { timestamp: '14:27:06.100', level: 'info', message: 'POST api.anthropic.com/v1/messages -> 200 (1000ms)' },
    ],
    packetColor: '#ec4899',
    responseColor: '#34d399',
    flowState: 'inspected',
  },
];

// --- SVG Flow Diagram Component ---

function FlowDiagram({ scenario, animating }: { scenario: ScenarioStep; animating: boolean }) {
  const isBlocked = scenario.flowState === 'blocked';
  const isCached = scenario.flowState === 'cached';

  // SVG path coordinates
  const clientX = 60;
  const proxyX = 250;
  const serverX = 440;
  const midY = 50;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 overflow-hidden">
      <svg viewBox="0 0 500 100" className="w-full h-auto" aria-label="Request flow diagram">
        {/* Connection lines */}
        <line x1={clientX + 30} y1={midY} x2={proxyX - 30} y2={midY} stroke="white" strokeOpacity={0.1} strokeWidth={1.5} strokeDasharray="4 4" />
        {!isBlocked && (
          <line x1={proxyX + 30} y1={midY} x2={serverX - 30} y2={midY} stroke="white" strokeOpacity={0.1} strokeWidth={1.5} strokeDasharray="4 4" />
        )}
        {isBlocked && (
          <line x1={proxyX + 30} y1={midY} x2={serverX - 30} y2={midY} stroke="red" strokeOpacity={0.15} strokeWidth={1.5} strokeDasharray="2 6" />
        )}

        {/* Client node */}
        <rect x={clientX - 28} y={midY - 20} width={56} height={40} rx={8} fill="rgba(96,165,250,0.1)" stroke="rgba(96,165,250,0.3)" strokeWidth={1} />
        <text x={clientX} y={midY + 1} textAnchor="middle" fill="rgba(96,165,250,0.8)" fontSize={10} fontFamily="monospace" fontWeight={600}>Client</text>

        {/* Proxy node */}
        <rect x={proxyX - 32} y={midY - 22} width={64} height={44} rx={8} fill="rgba(167,139,250,0.1)" stroke="rgba(167,139,250,0.3)" strokeWidth={1} />
        <text x={proxyX} y={midY - 3} textAnchor="middle" fill="rgba(167,139,250,0.8)" fontSize={9} fontFamily="monospace" fontWeight={600}>Rust</text>
        <text x={proxyX} y={midY + 10} textAnchor="middle" fill="rgba(167,139,250,0.8)" fontSize={9} fontFamily="monospace" fontWeight={600}>Proxy</text>

        {/* Server node */}
        <rect x={serverX - 28} y={midY - 20} width={56} height={40} rx={8} fill={isBlocked ? "rgba(239,68,68,0.05)" : "rgba(52,211,153,0.1)"} stroke={isBlocked ? "rgba(239,68,68,0.15)" : "rgba(52,211,153,0.3)"} strokeWidth={1} />
        <text x={serverX} y={midY + 1} textAnchor="middle" fill={isBlocked ? "rgba(239,68,68,0.4)" : "rgba(52,211,153,0.8)"} fontSize={10} fontFamily="monospace" fontWeight={600}>Server</text>

        {/* Blocked X mark */}
        {isBlocked && (
          <g>
            <line x1={proxyX + 55} y1={midY - 12} x2={proxyX + 75} y2={midY + 12} stroke="rgba(239,68,68,0.6)" strokeWidth={2} strokeLinecap="round" />
            <line x1={proxyX + 75} y1={midY - 12} x2={proxyX + 55} y2={midY + 12} stroke="rgba(239,68,68,0.6)" strokeWidth={2} strokeLinecap="round" />
          </g>
        )}

        {/* Cache badge on proxy */}
        {isCached && (
          <g>
            <rect x={proxyX - 18} y={midY + 26} width={36} height={14} rx={4} fill="rgba(167,139,250,0.2)" stroke="rgba(167,139,250,0.3)" strokeWidth={0.5} />
            <text x={proxyX} y={midY + 35} textAnchor="middle" fill="rgba(167,139,250,0.9)" fontSize={7} fontFamily="monospace" fontWeight={600}>CACHE</text>
          </g>
        )}

        {/* Animated request packet: client -> proxy */}
        {animating && (
          <motion.circle
            cx={clientX + 30}
            cy={midY}
            r={4}
            fill={scenario.packetColor}
            initial={{ cx: clientX + 30, opacity: 0 }}
            animate={{ cx: proxyX - 30, opacity: [0, 1, 1, 0.5] }}
            transition={{ duration: 0.8, ease: "easeInOut", repeat: Infinity, repeatDelay: 1.4 }}
          />
        )}

        {/* Animated packet: proxy -> server (only if not blocked/cached) */}
        {animating && !isBlocked && !isCached && (
          <motion.circle
            cx={proxyX + 30}
            cy={midY}
            r={4}
            fill={scenario.packetColor}
            initial={{ cx: proxyX + 30, opacity: 0 }}
            animate={{ cx: serverX - 30, opacity: [0, 1, 1, 0.5] }}
            transition={{ duration: 0.8, ease: "easeInOut", delay: 0.5, repeat: Infinity, repeatDelay: 1.4 }}
          />
        )}

        {/* Animated response: server -> proxy -> client */}
        {animating && !isBlocked && !isCached && (
          <motion.circle
            cx={serverX - 30}
            cy={midY + 8}
            r={3}
            fill={scenario.responseColor}
            initial={{ cx: serverX - 30, opacity: 0 }}
            animate={{ cx: clientX + 30, opacity: [0, 0.8, 0.8, 0] }}
            transition={{ duration: 1.2, ease: "easeInOut", delay: 1.2, repeat: Infinity, repeatDelay: 1 }}
          />
        )}

        {/* Cached response: proxy -> client directly */}
        {animating && isCached && (
          <motion.circle
            cx={proxyX - 30}
            cy={midY + 8}
            r={3}
            fill={scenario.responseColor}
            initial={{ cx: proxyX - 30, opacity: 0 }}
            animate={{ cx: clientX + 30, opacity: [0, 0.8, 0.8, 0] }}
            transition={{ duration: 0.5, ease: "easeInOut", delay: 0.6, repeat: Infinity, repeatDelay: 1.7 }}
          />
        )}

        {/* Blocked response: proxy -> client (error) */}
        {animating && isBlocked && (
          <motion.circle
            cx={proxyX - 30}
            cy={midY + 8}
            r={3}
            fill="#ef4444"
            initial={{ cx: proxyX - 30, opacity: 0 }}
            animate={{ cx: clientX + 30, opacity: [0, 0.8, 0.8, 0] }}
            transition={{ duration: 0.5, ease: "easeInOut", delay: 0.6, repeat: Infinity, repeatDelay: 1.7 }}
          />
        )}

        {/* Method + status labels */}
        <text x={clientX + 80} y={midY - 28} fill="white" fillOpacity={0.3} fontSize={8} fontFamily="monospace">{scenario.method}</text>
        <text x={serverX - 80} y={midY - 28} textAnchor="end" fill={scenario.statusCode >= 400 ? "rgba(239,68,68,0.6)" : "rgba(52,211,153,0.6)"} fontSize={8} fontFamily="monospace">{scenario.statusCode} {scenario.statusText.split(' ')[0]}</text>
      </svg>
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
        {expanded ? <ChevronDown className="h-3 w-3 text-white/30" /> : <ChevronUp className="h-3 w-3 text-white/30" />}
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">{title}</span>
        <span className="text-[10px] text-white/20 font-mono">({headers.length})</span>
      </button>
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={SPRING}
            className="overflow-hidden"
          >
            <div className="px-3 pb-2 space-y-0.5">
              {headers.map((h) => (
                <div key={h.key} className="flex items-start gap-2 font-mono text-[10px] leading-relaxed">
                  <span className={h.modified ? "text-amber-400/80" : "text-blue-400/60"}>{h.key}:</span>
                  <span className={`${h.redacted ? "text-red-400/50 line-through" : h.modified ? "text-amber-400/60" : "text-white/40"} break-all`}>
                    {h.value}
                  </span>
                  {h.modified && (
                    <span className="shrink-0 px-1 py-0.5 rounded text-[8px] bg-amber-500/10 text-amber-400/60 border border-amber-500/20">
                      INJECTED
                    </span>
                  )}
                  {h.redacted && (
                    <span className="shrink-0 px-1 py-0.5 rounded text-[8px] bg-red-500/10 text-red-400/60 border border-red-500/20">
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
    { label: 'DNS', value: timing.dns, color: 'bg-sky-400' },
    { label: 'TLS', value: timing.tls, color: 'bg-violet-400' },
    { label: 'Proxy', value: timing.proxyProcessing, color: 'bg-amber-400' },
    { label: 'Server', value: timing.serverWait, color: 'bg-emerald-400' },
    { label: 'Transfer', value: timing.transfer, color: 'bg-blue-400' },
  ];

  const maxVal = Math.max(total, 1);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Latency Waterfall</span>
        <span className="text-[10px] font-mono text-white/40">{total < 1 ? `${total}ms` : `${Math.round(total)}ms`} total</span>
      </div>
      <div className="space-y-1">
        {segments.map((seg) => {
          const pct = (seg.value / maxVal) * 100;
          return (
            <div key={seg.label} className="flex items-center gap-2">
              <span className="text-[9px] text-white/30 font-mono w-12 text-right">{seg.label}</span>
              <div className="flex-1 h-3 rounded-full bg-white/[0.04] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${seg.color} opacity-60`}
                  initial={{ width: 0 }}
                  animate={{ width: `${Math.max(pct, pct > 0 ? 2 : 0)}%` }}
                  transition={SPRING}
                />
              </div>
              <span className="text-[9px] text-white/25 font-mono w-12">
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
    'allow': 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
    'modify': 'text-amber-400 bg-amber-500/10 border-amber-500/20',
    'block': 'text-red-400 bg-red-500/10 border-red-500/20',
    'rate-limit': 'text-orange-400 bg-orange-500/10 border-orange-500/20',
    'cache': 'text-violet-400 bg-violet-500/10 border-violet-500/20',
    'inspect': 'text-pink-400 bg-pink-500/10 border-pink-500/20',
  };

  return (
    <div className="space-y-2">
      <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Rule Engine</span>
      <div className="space-y-1">
        {rules.map((rule) => (
          <motion.div
            key={rule.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={SPRING}
            className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg border ${
              rule.matched
                ? 'border-white/[0.1] bg-white/[0.04]'
                : 'border-white/[0.04] bg-white/[0.01] opacity-40'
            }`}
          >
            {rule.matched ? (
              <CheckCircle className="h-3 w-3 text-emerald-400 shrink-0" />
            ) : (
              <div className="h-3 w-3 rounded-full border border-white/[0.1] shrink-0" />
            )}
            <span className={`px-1.5 py-0.5 rounded text-[8px] font-semibold uppercase border ${typeColors[rule.type] || 'text-white/40'}`}>
              {rule.type}
            </span>
            <span className="text-[10px] font-mono text-white/40 flex-1 truncate">{rule.pattern}</span>
            <span className="text-[9px] text-white/25 truncate">{rule.action}</span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

// --- Live Log Stream ---

function LogStream({ logs }: { logs: LogEntry[] }) {
  const levelColors: Record<string, string> = {
    'info': 'text-blue-400/60',
    'warn': 'text-amber-400/70',
    'error': 'text-red-400/70',
    'debug': 'text-white/25',
  };

  const levelBg: Record<string, string> = {
    'info': 'bg-blue-500/10',
    'warn': 'bg-amber-500/10',
    'error': 'bg-red-500/10',
    'debug': 'bg-white/[0.02]',
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Proxy Log</span>
        <motion.div
          animate={{ opacity: [1, 0.3, 1] }}
          transition={{ duration: 1.5, repeat: Infinity }}
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
              className={`flex items-start gap-2 px-3 py-1 font-mono text-[10px] border-b border-white/[0.03] last:border-0 ${levelBg[log.level]}`}
            >
              <span className="text-white/20 shrink-0">{log.timestamp}</span>
              <span className={`shrink-0 uppercase font-semibold ${levelColors[log.level]}`}>
                {log.level.padEnd(5)}
              </span>
              <span className="text-white/40 break-all">{log.message}</span>
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}

// --- Flow State Badge ---

function FlowStateBadge({ state }: { state: ScenarioStep['flowState'] }) {
  const config: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
    normal: { label: 'PassThrough', color: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400', icon: <CheckCircle className="h-3 w-3" /> },
    modified: { label: 'Headers Modified', color: 'border-amber-500/30 bg-amber-500/10 text-amber-400', icon: <Settings className="h-3 w-3" /> },
    blocked: { label: 'Request Blocked', color: 'border-red-500/30 bg-red-500/10 text-red-400', icon: <Ban className="h-3 w-3" /> },
    'rate-limited': { label: 'Rate Limited', color: 'border-orange-500/30 bg-orange-500/10 text-orange-400', icon: <Gauge className="h-3 w-3" /> },
    cached: { label: 'Served from Cache', color: 'border-violet-500/30 bg-violet-500/10 text-violet-400', icon: <Database className="h-3 w-3" /> },
    inspected: { label: 'TLS Inspected', color: 'border-pink-500/30 bg-pink-500/10 text-pink-400', icon: <FileSearch className="h-3 w-3" /> },
  };

  const c = config[state];
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={SPRING}
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-[11px] font-medium ${c.color}`}
    >
      {c.icon}
      {c.label}
    </motion.div>
  );
}

// --- Active Tab Selector for Details ---

type DetailTab = 'headers' | 'waterfall' | 'rules' | 'logs';

function DetailTabBar({ active, onChange }: { active: DetailTab; onChange: (t: DetailTab) => void }) {
  const tabs: { id: DetailTab; label: string; icon: React.ReactNode }[] = [
    { id: 'headers', label: 'Headers', icon: <Eye className="h-3 w-3" /> },
    { id: 'waterfall', label: 'Timing', icon: <Clock className="h-3 w-3" /> },
    { id: 'rules', label: 'Rules', icon: <Shield className="h-3 w-3" /> },
    { id: 'logs', label: 'Logs', icon: <Terminal className="h-3 w-3" /> },
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
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[11px] font-medium transition-colors ${
            active === tab.id
              ? 'bg-white/[0.08] text-white/80 border border-white/[0.1]'
              : 'text-white/30 hover:text-white/50 border border-transparent'
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
  const [activeTab, setActiveTab] = useState<DetailTab>('headers');
  const [isAnimating, setIsAnimating] = useState(true);

  const scenario = SCENARIOS[stepIndex];

  const setScenarioStep = useCallback((nextStep: number | ((current: number) => number)) => {
    setStepIndex((current) => {
      const resolved = typeof nextStep === 'function' ? nextStep(current) : nextStep;
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
      setActiveTab('headers');
    }, 0);
    return () => clearTimeout(timer);
  }, [stepIndex]);

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-blue-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/3 w-48 h-48 bg-violet-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-6 space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-2">
            <motion.div
              animate={{ rotate: [0, 360] }}
              transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
            >
              <Activity className="h-4 w-4 text-white/40" />
            </motion.div>
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
              Traffic Inspector
            </span>
            <motion.div
              animate={{ opacity: [1, 0.3, 1] }}
              transition={{ duration: 1.5, repeat: Infinity }}
              className="h-1.5 w-1.5 rounded-full bg-emerald-500"
            />
            <span className="text-[10px] text-emerald-400/60 font-medium">LIVE</span>
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
                  : "border-white/[0.08] bg-white/[0.02] text-white/40"
              }`}
            >
              {isAnimating ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {isAnimating ? 'Pause' : 'Animate'}
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
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-medium whitespace-nowrap transition-colors border ${
                  stepIndex === idx
                    ? "bg-white/[0.1] text-white border-white/[0.15]"
                    : "text-white/35 hover:text-white/55 border-transparent hover:border-white/[0.06]"
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
              onClick={goPrev}
              disabled={stepIndex === 0}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-white/40 hover:text-white/70 disabled:opacity-20 disabled:hover:text-white/40 shrink-0"
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
                  <span className="text-[10px] text-white/25 font-mono">
                    Step {stepIndex + 1}/{SCENARIOS.length}
                  </span>
                  <FlowStateBadge state={scenario.flowState} />
                </div>
                <p className="text-[11px] text-white/40 leading-relaxed line-clamp-2">
                  {scenario.description}
                </p>
              </motion.div>
            </AnimatePresence>

            <motion.button
              onClick={goNext}
              disabled={stepIndex === SCENARIOS.length - 1}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={SPRING_SNAPPY}
              className="h-7 w-7 rounded-lg border border-white/[0.08] bg-white/[0.02] flex items-center justify-center text-white/40 hover:text-white/70 disabled:opacity-20 disabled:hover:text-white/40 shrink-0"
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </motion.button>
          </div>
        </div>

        {/* Request summary bar */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + '-summary'}
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={SPRING}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-black/30 border border-white/[0.06] font-mono text-xs overflow-x-auto"
          >
            <span className={scenario.method === 'POST' ? 'text-amber-400/80 font-semibold' : 'text-emerald-400/80 font-semibold'}>
              {scenario.method}
            </span>
            <span className="text-white/50 truncate">{scenario.url}</span>
            <ArrowRight className="h-3 w-3 text-white/20 shrink-0" />
            <span className={`font-semibold shrink-0 ${scenario.statusCode >= 400 ? 'text-red-400' : 'text-emerald-400/70'}`}>
              {scenario.statusCode}
            </span>
            <span className={`shrink-0 ${scenario.statusCode >= 400 ? 'text-red-400/60' : 'text-white/30'}`}>
              {scenario.statusText}
            </span>
            <span className="text-white/20 shrink-0">|</span>
            <span className={`shrink-0 ${scenario.totalLatency > 1000 ? 'text-amber-400/70' : 'text-white/40'}`}>
              {scenario.totalLatency < 1 ? `${scenario.totalLatency}ms` : `${Math.round(scenario.totalLatency)}ms`}
            </span>
          </motion.div>
        </AnimatePresence>

        {/* Animated flow diagram */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + '-flow'}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            <FlowDiagram scenario={scenario} animating={isAnimating} />
          </motion.div>
        </AnimatePresence>

        {/* Detail tabs */}
        <DetailTabBar active={activeTab} onChange={setActiveTab} />

        {/* Tab content */}
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario.id + '-' + activeTab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={SPRING}
          >
            {activeTab === 'headers' && (
              <div className="space-y-3">
                <HeaderTree headers={scenario.requestHeaders} title="Request Headers" />
                <HeaderTree headers={scenario.responseHeaders} title="Response Headers" />
                {/* Body preview */}
                <div className="rounded-lg border border-white/[0.06] bg-black/30 overflow-hidden">
                  <div className="px-3 py-2 border-b border-white/[0.04]">
                    <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">Response Body</span>
                  </div>
                  <pre className="px-3 py-2 font-mono text-[10px] text-white/40 leading-relaxed overflow-x-auto whitespace-pre">
                    {scenario.bodyPreview}
                  </pre>
                </div>
              </div>
            )}

            {activeTab === 'waterfall' && (
              <div className="space-y-4">
                <LatencyWaterfall timing={scenario.timing} total={scenario.totalLatency} />
                {/* Additional stats */}
                <div className="grid grid-cols-3 gap-3">
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-[10px] uppercase tracking-wider text-white/25 block">Total</span>
                    <span className="text-sm font-mono text-white/60 font-semibold">
                      {scenario.totalLatency < 1 ? `${scenario.totalLatency}ms` : `${Math.round(scenario.totalLatency)}ms`}
                    </span>
                  </div>
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-[10px] uppercase tracking-wider text-white/25 block">Proxy Overhead</span>
                    <span className="text-sm font-mono text-amber-400/70 font-semibold">
                      {scenario.timing.proxyProcessing < 1 ? `${scenario.timing.proxyProcessing}ms` : `${Math.round(scenario.timing.proxyProcessing)}ms`}
                    </span>
                  </div>
                  <div className="p-3 rounded-lg border border-white/[0.06] bg-white/[0.02] text-center">
                    <span className="text-[10px] uppercase tracking-wider text-white/25 block">Overhead %</span>
                    <span className="text-sm font-mono text-white/60 font-semibold">
                      {scenario.totalLatency > 0 ? `${((scenario.timing.proxyProcessing / scenario.totalLatency) * 100).toFixed(1)}%` : '0%'}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {activeTab === 'rules' && (
              <RuleEnginePanel rules={scenario.rules} />
            )}

            {activeTab === 'logs' && (
              <LogStream logs={scenario.logs} />
            )}
          </motion.div>
        </AnimatePresence>

        {/* Tip */}
        <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/[0.06]">
          <Eye className="h-3.5 w-3.5 text-white/30 shrink-0" />
          <span className="text-[11px] text-white/40">
            Step through 6 proxy scenarios. Each shows the full request lifecycle: flow visualization, headers, latency waterfall, rule matching, and live logs.
          </span>
        </div>
      </div>
    </div>
  );
}
