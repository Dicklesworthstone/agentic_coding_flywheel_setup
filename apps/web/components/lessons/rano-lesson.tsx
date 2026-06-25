'use client';

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Network,
  Terminal,
  Eye,
  BarChart3,
  Bug,
  Filter,
  Settings,
  Shield,
  Play,
  RotateCcw,
  CheckCircle2,
  Clock,
  ChevronLeft,
  ChevronRight,
  Globe,
  Zap,
  Activity,
  Radio,
  ShieldAlert,
  MapPin,
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

export function RanoLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Monitor and debug AI CLI network traffic to understand what your agents send and receive.
      </GoalBanner>

      {/* Section 1: What Is RANO */}
      <Section title="What Is RANO?" icon={<Network className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>RANO</Highlight> is a network observer purpose-built for AI coding CLIs.
          It intercepts HTTP requests between your local agents (Claude Code, Codex, Antigravity CLI)
          and their APIs, logging requests and responses for analysis.
        </Paragraph>
        <Paragraph>
          When agents behave unexpectedly, RANO helps you see exactly what&apos;s being sent
          and received, making it invaluable for debugging prompt issues, token usage tracking,
          and understanding agent behavior.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="Transparent Proxy"
              description="Zero-config interception"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Usage Stats"
              description="Token and cost tracking"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Filter className="h-5 w-5" />}
              title="Smart Filtering"
              description="Provider-aware log parsing"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Bug className="h-5 w-5" />}
              title="Debug Mode"
              description="Full request/response logging"
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
        <Paragraph>
          Start observing AI CLI traffic.
        </Paragraph>

        <CommandList
          commands={[
            { command: 'rano start', description: 'Start the observer proxy' },
            { command: 'rano status', description: 'Check if observer is running' },
            { command: 'rano logs', description: 'View captured traffic' },
            { command: 'rano stop', description: 'Stop the observer' },
          ]}
        />

        <TipBox variant="tip">
          RANO automatically detects which AI CLIs are installed and configures interception
          for each one.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Analyzing Traffic */}
      <Section title="Analyzing Traffic" icon={<BarChart3 className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          RANO provides structured views of captured API traffic.
        </Paragraph>

        <CodeBlock
          code={`# View recent requests with token counts
rano logs --tokens

# Filter by provider
rano logs --provider anthropic
rano logs --provider openai

# Show full request/response bodies
rano logs --verbose --last 5

# Export logs for analysis
rano export --format json -o traffic.json`}
          filename="Log Analysis"
        />

        <TipBox variant="info">
          Token counts help you understand which agents are consuming the most context
          and optimize your prompting strategy accordingly.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Debug Mode */}
      <Section title="Debug Mode" icon={<Bug className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          When an agent behaves unexpectedly, debug mode captures everything.
        </Paragraph>

        <CodeBlock
          code={`# Start with full debug logging
rano start --debug

# Watch traffic in real-time
rano watch

# Filter for errors only
rano logs --errors

# Show request timing
rano logs --timing`}
          filename="Debug Commands"
        />

        <TipBox variant="warning">
          Debug mode logs full request and response bodies, which may include sensitive data.
          Use it for troubleshooting, then stop it when done.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Integration" icon={<Settings className="h-5 w-5" />} delay={0.3}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">RANO + CAUT</span>
            <p className="text-white/80 text-sm mt-1">Detailed traffic feeds into usage tracking</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">RANO + CAAM</span>
            <p className="text-white/80 text-sm mt-1">See which account each request uses</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">RANO + NTM</span>
            <p className="text-white/80 text-sm mt-1">Monitor traffic across all spawned agents</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">RANO + Beads</span>
            <p className="text-white/80 text-sm mt-1">Track API issues as beads for follow-up</p>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Section 6: Best Practices */}
      <Section title="Best Practices" icon={<Shield className="h-5 w-5" />} delay={0.35}>
        <TipBox variant="tip">
          Run RANO during development to build intuition about what your agents are actually
          sending. You&apos;ll often discover wasted tokens or redundant API calls.
        </TipBox>

        <TipBox variant="warning">
          RANO is a debugging tool, not a permanent fixture. Running it continuously adds
          latency and disk usage. Enable it when investigating issues, disable it otherwise.
        </TipBox>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Network Operations Center
// ---------------------------------------------------------------------------

// --- Types ---

interface Region {
  id: string;
  name: string;
  shortName: string;
  x: number;
  y: number;
  color: string;
}

interface NetworkPacket {
  id: number;
  fromRegion: string;
  toRegion: string;
  type: 'normal' | 'attack' | 'blocked' | 'cdn' | 'failover';
  progress: number;
}

interface ThreatEvent {
  id: number;
  severity: 'low' | 'medium' | 'high' | 'critical';
  source: string;
  message: string;
  timestamp: string;
}

interface LogLine {
  id: number;
  command: string;
  output: string;
  type: 'info' | 'warning' | 'error' | 'success';
}

interface RegionMetrics {
  regionId: string;
  rps: number;
  bandwidthMbps: number;
  latencyMs: number;
  status: 'healthy' | 'degraded' | 'down';
}

interface Scenario {
  id: string;
  title: string;
  icon: React.ReactNode;
  description: string;
  metrics: RegionMetrics[];
  threats: ThreatEvent[];
  logs: LogLine[];
  packetTypes: NetworkPacket['type'][];
}

// --- Constants ---

const REGIONS: Region[] = [
  { id: 'us-east', name: 'US East (Virginia)', shortName: 'US-E', x: 175, y: 135, color: '#60a5fa' },
  { id: 'us-west', name: 'US West (Oregon)', shortName: 'US-W', x: 95, y: 125, color: '#818cf8' },
  { id: 'eu-west', name: 'EU West (Ireland)', shortName: 'EU-W', x: 320, y: 100, color: '#34d399' },
  { id: 'ap-east', name: 'Asia Pacific (Tokyo)', shortName: 'AP-E', x: 540, y: 130, color: '#f472b6' },
  { id: 'ap-south', name: 'Asia Pacific (Mumbai)', shortName: 'AP-S', x: 460, y: 175, color: '#fbbf24' },
  { id: 'sa-east', name: 'South America (Sao Paulo)', shortName: 'SA-E', x: 210, y: 240, color: '#fb923c' },
];

const NETWORK_PATHS: Array<[string, string]> = [
  ['us-east', 'eu-west'],
  ['us-east', 'us-west'],
  ['eu-west', 'ap-east'],
  ['ap-east', 'ap-south'],
  ['us-east', 'sa-east'],
  ['us-west', 'ap-east'],
  ['eu-west', 'ap-south'],
  ['us-east', 'ap-south'],
];

const PACKET_COLORS: Record<NetworkPacket['type'], string> = {
  normal: '#60a5fa',
  attack: '#ef4444',
  blocked: '#f59e0b',
  cdn: '#34d399',
  failover: '#a78bfa',
};

const SEVERITY_STYLES: Record<ThreatEvent['severity'], { bg: string; border: string; text: string; dot: string }> = {
  low: { bg: 'bg-blue-500/10', border: 'border-blue-500/30', text: 'text-blue-400', dot: 'bg-blue-400' },
  medium: { bg: 'bg-yellow-500/10', border: 'border-yellow-500/30', text: 'text-yellow-400', dot: 'bg-yellow-400' },
  high: { bg: 'bg-orange-500/10', border: 'border-orange-500/30', text: 'text-orange-400', dot: 'bg-orange-400' },
  critical: { bg: 'bg-red-500/10', border: 'border-red-500/30', text: 'text-red-400', dot: 'bg-red-400' },
};

function makeScenarios(): Scenario[] {
  return [
    {
      id: 'normal',
      title: 'Normal Traffic',
      icon: <Activity className="h-4 w-4" />,
      description: 'Healthy baseline traffic across all regions. All APIs responding normally with low latency.',
      metrics: [
        { regionId: 'us-east', rps: 2450, bandwidthMbps: 180, latencyMs: 12, status: 'healthy' },
        { regionId: 'us-west', rps: 1820, bandwidthMbps: 140, latencyMs: 18, status: 'healthy' },
        { regionId: 'eu-west', rps: 1960, bandwidthMbps: 155, latencyMs: 24, status: 'healthy' },
        { regionId: 'ap-east', rps: 1540, bandwidthMbps: 120, latencyMs: 45, status: 'healthy' },
        { regionId: 'ap-south', rps: 890, bandwidthMbps: 72, latencyMs: 62, status: 'healthy' },
        { regionId: 'sa-east', rps: 640, bandwidthMbps: 48, latencyMs: 78, status: 'healthy' },
      ],
      threats: [
        { id: 1, severity: 'low', source: '192.168.1.0/24', message: 'Routine port scan detected', timestamp: '14:23:01' },
      ],
      logs: [
        { id: 1, command: 'rano status', output: 'Observer active — 6 regions healthy', type: 'success' },
        { id: 2, command: 'rano logs --summary', output: '9,300 req/s total | 0 errors | avg 39ms', type: 'info' },
        { id: 3, command: 'rano watch --provider anthropic', output: 'Streaming: 2,450 req/s via us-east', type: 'info' },
      ],
      packetTypes: ['normal', 'normal', 'normal', 'cdn'],
    },
    {
      id: 'ddos-detect',
      title: 'DDoS Detection',
      icon: <ShieldAlert className="h-4 w-4" />,
      description: 'Volumetric attack detected from multiple sources targeting US-East. RANO correlating traffic patterns.',
      metrics: [
        { regionId: 'us-east', rps: 48200, bandwidthMbps: 4200, latencyMs: 340, status: 'degraded' },
        { regionId: 'us-west', rps: 1820, bandwidthMbps: 140, latencyMs: 22, status: 'healthy' },
        { regionId: 'eu-west', rps: 12400, bandwidthMbps: 980, latencyMs: 85, status: 'degraded' },
        { regionId: 'ap-east', rps: 8900, bandwidthMbps: 720, latencyMs: 120, status: 'degraded' },
        { regionId: 'ap-south', rps: 890, bandwidthMbps: 72, latencyMs: 62, status: 'healthy' },
        { regionId: 'sa-east', rps: 640, bandwidthMbps: 48, latencyMs: 78, status: 'healthy' },
      ],
      threats: [
        { id: 1, severity: 'critical', source: '45.33.0.0/16', message: 'DDoS: SYN flood on us-east (48k req/s)', timestamp: '14:25:03' },
        { id: 2, severity: 'high', source: '185.220.0.0/16', message: 'DDoS: HTTP flood amplification via eu-west', timestamp: '14:25:05' },
        { id: 3, severity: 'high', source: '103.42.0.0/16', message: 'DDoS: Botnet traffic from ap-east cluster', timestamp: '14:25:07' },
        { id: 4, severity: 'medium', source: 'Multiple', message: 'Anomalous pattern: 23x baseline traffic spike', timestamp: '14:25:08' },
      ],
      logs: [
        { id: 1, command: 'rano alert --check', output: 'CRITICAL: DDoS detected on us-east (48,200 req/s)', type: 'error' },
        { id: 2, command: 'rano logs --errors --last 10', output: '3,421 timeouts in last 60s | source: 45.33.0.0/16', type: 'warning' },
        { id: 3, command: 'rano trace --source 45.33.0.0/16', output: 'Tracing: 23,000+ unique IPs, botnet signature match', type: 'error' },
        { id: 4, command: 'rano mitigate --recommend', output: 'Suggest: enable rate-limit + geo-block on 3 CIDRs', type: 'warning' },
      ],
      packetTypes: ['attack', 'attack', 'attack', 'normal', 'attack'],
    },
    {
      id: 'rate-limit',
      title: 'Rate Limiting Active',
      icon: <Filter className="h-4 w-4" />,
      description: 'Intelligent rate limiting engaged. Malicious traffic throttled while legitimate requests pass through.',
      metrics: [
        { regionId: 'us-east', rps: 3200, bandwidthMbps: 240, latencyMs: 28, status: 'healthy' },
        { regionId: 'us-west', rps: 1820, bandwidthMbps: 140, latencyMs: 18, status: 'healthy' },
        { regionId: 'eu-west', rps: 2100, bandwidthMbps: 170, latencyMs: 32, status: 'healthy' },
        { regionId: 'ap-east', rps: 1600, bandwidthMbps: 125, latencyMs: 48, status: 'healthy' },
        { regionId: 'ap-south', rps: 890, bandwidthMbps: 72, latencyMs: 62, status: 'healthy' },
        { regionId: 'sa-east', rps: 640, bandwidthMbps: 48, latencyMs: 78, status: 'healthy' },
      ],
      threats: [
        { id: 1, severity: 'medium', source: '45.33.0.0/16', message: 'Rate limited: 44,800 req/s dropped', timestamp: '14:26:12' },
        { id: 2, severity: 'low', source: '185.220.0.0/16', message: 'Rate limited: 10,200 req/s dropped', timestamp: '14:26:14' },
      ],
      logs: [
        { id: 1, command: 'rano ratelimit --enable --threshold 5000', output: 'Rate limiter active: 5,000 req/s per source', type: 'success' },
        { id: 2, command: 'rano ratelimit --status', output: 'Dropping 55,000 req/s | Passing 10,250 req/s', type: 'info' },
        { id: 3, command: 'rano logs --blocked --count', output: '44,800 blocked from 45.33.0.0/16 in last 30s', type: 'warning' },
      ],
      packetTypes: ['normal', 'blocked', 'normal', 'blocked', 'normal'],
    },
    {
      id: 'geo-block',
      title: 'Geo-Blocking',
      icon: <Globe className="h-4 w-4" />,
      description: 'Geographic IP blocking enabled. Traffic from known attack regions rejected at network edge.',
      metrics: [
        { regionId: 'us-east', rps: 2500, bandwidthMbps: 185, latencyMs: 14, status: 'healthy' },
        { regionId: 'us-west', rps: 1850, bandwidthMbps: 142, latencyMs: 16, status: 'healthy' },
        { regionId: 'eu-west', rps: 1980, bandwidthMbps: 158, latencyMs: 22, status: 'healthy' },
        { regionId: 'ap-east', rps: 120, bandwidthMbps: 8, latencyMs: 52, status: 'degraded' },
        { regionId: 'ap-south', rps: 890, bandwidthMbps: 72, latencyMs: 62, status: 'healthy' },
        { regionId: 'sa-east', rps: 640, bandwidthMbps: 48, latencyMs: 78, status: 'healthy' },
      ],
      threats: [
        { id: 1, severity: 'medium', source: 'ap-east CIDR block', message: 'Geo-block: 8,780 req/s rejected from AS4134', timestamp: '14:27:30' },
        { id: 2, severity: 'low', source: 'Monitor', message: 'Legitimate ap-east traffic rerouted via ap-south', timestamp: '14:27:32' },
      ],
      logs: [
        { id: 1, command: 'rano geoblock --add 103.42.0.0/16,45.33.0.0/16', output: 'Geo-block enabled for 2 CIDR ranges', type: 'success' },
        { id: 2, command: 'rano geoblock --status', output: 'Blocking: 2 ranges | Rejected: 8,780 req/s', type: 'info' },
        { id: 3, command: 'rano logs --geo --provider anthropic', output: 'Anthropic traffic clean: 0 blocked legitimate', type: 'success' },
      ],
      packetTypes: ['normal', 'blocked', 'normal', 'cdn'],
    },
    {
      id: 'cdn-route',
      title: 'CDN Routing',
      icon: <Zap className="h-4 w-4" />,
      description: 'Edge caching and CDN acceleration enabled. Static API schemas cached, reducing origin load by 40%.',
      metrics: [
        { regionId: 'us-east', rps: 1470, bandwidthMbps: 95, latencyMs: 8, status: 'healthy' },
        { regionId: 'us-west', rps: 1090, bandwidthMbps: 72, latencyMs: 6, status: 'healthy' },
        { regionId: 'eu-west', rps: 1180, bandwidthMbps: 80, latencyMs: 4, status: 'healthy' },
        { regionId: 'ap-east', rps: 920, bandwidthMbps: 60, latencyMs: 10, status: 'healthy' },
        { regionId: 'ap-south', rps: 530, bandwidthMbps: 38, latencyMs: 14, status: 'healthy' },
        { regionId: 'sa-east', rps: 380, bandwidthMbps: 25, latencyMs: 12, status: 'healthy' },
      ],
      threats: [],
      logs: [
        { id: 1, command: 'rano cdn --enable --edge-cache', output: 'CDN layer active: 6 edge nodes online', type: 'success' },
        { id: 2, command: 'rano cdn --stats', output: 'Cache hit: 42% | Origin load reduced 40%', type: 'info' },
        { id: 3, command: 'rano logs --timing --cdn', output: 'Edge avg 9ms | Origin avg 45ms | Savings: 80%', type: 'success' },
        { id: 4, command: 'rano watch --latency', output: 'Global p99 latency: 18ms (was 78ms)', type: 'info' },
      ],
      packetTypes: ['cdn', 'cdn', 'normal', 'cdn', 'cdn'],
    },
    {
      id: 'failover',
      title: 'Failover Active',
      icon: <Radio className="h-4 w-4" />,
      description: 'US-East experiencing outage. Automatic failover routing traffic through US-West and EU-West.',
      metrics: [
        { regionId: 'us-east', rps: 0, bandwidthMbps: 0, latencyMs: 9999, status: 'down' },
        { regionId: 'us-west', rps: 4200, bandwidthMbps: 320, latencyMs: 24, status: 'degraded' },
        { regionId: 'eu-west', rps: 3800, bandwidthMbps: 290, latencyMs: 35, status: 'degraded' },
        { regionId: 'ap-east', rps: 1540, bandwidthMbps: 120, latencyMs: 48, status: 'healthy' },
        { regionId: 'ap-south', rps: 1200, bandwidthMbps: 92, latencyMs: 55, status: 'healthy' },
        { regionId: 'sa-east', rps: 980, bandwidthMbps: 74, latencyMs: 65, status: 'healthy' },
      ],
      threats: [
        { id: 1, severity: 'critical', source: 'us-east', message: 'Region DOWN: us-east unresponsive for 45s', timestamp: '14:30:00' },
        { id: 2, severity: 'high', source: 'failover', message: 'Failover engaged: us-east traffic split to us-west + eu-west', timestamp: '14:30:02' },
        { id: 3, severity: 'medium', source: 'capacity', message: 'us-west at 78% capacity after failover absorption', timestamp: '14:30:05' },
      ],
      logs: [
        { id: 1, command: 'rano health --check', output: 'CRITICAL: us-east — no heartbeat for 45s', type: 'error' },
        { id: 2, command: 'rano failover --trigger us-east', output: 'Failover active: routing to us-west (60%) + eu-west (40%)', type: 'warning' },
        { id: 3, command: 'rano status --failover', output: 'us-west: 78% cap | eu-west: 65% cap | All req served', type: 'info' },
        { id: 4, command: 'rano logs --provider anthropic --errors', output: '0 dropped requests — failover seamless', type: 'success' },
      ],
      packetTypes: ['failover', 'failover', 'normal', 'cdn'],
    },
  ];
}

// ---------------------------------------------------------------------------
// World Map SVG (simplified continents)
// ---------------------------------------------------------------------------

function WorldMapSvg({
  regions,
  packets,
  activeScenario,
}: {
  regions: Region[];
  packets: NetworkPacket[];
  activeScenario: Scenario;
}) {
  const regionMap = useMemo(() => {
    const map: Record<string, Region> = {};
    for (const r of regions) {
      map[r.id] = r;
    }
    return map;
  }, [regions]);

  const metricsMap = useMemo(() => {
    const map: Record<string, RegionMetrics> = {};
    for (const m of activeScenario.metrics) {
      map[m.regionId] = m;
    }
    return map;
  }, [activeScenario.metrics]);

  return (
    <svg viewBox="0 0 640 320" className="w-full h-full" xmlns="http://www.w3.org/2000/svg">
      {/* Background grid */}
      <defs>
        <pattern id="noc-grid" width="32" height="32" patternUnits="userSpaceOnUse">
          <path d="M 32 0 L 0 0 0 32" fill="none" stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />
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

      {/* Simplified continent outlines */}
      {/* North America */}
      <path
        d="M60,60 Q80,50 120,55 Q160,60 180,80 Q190,100 185,120 Q180,140 160,155 Q140,165 120,160 Q100,155 85,140 Q70,125 60,105 Q55,85 60,60Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />
      {/* South America */}
      <path
        d="M165,175 Q175,170 195,175 Q215,185 225,210 Q230,235 220,260 Q210,275 195,280 Q180,278 172,265 Q165,245 160,220 Q158,195 165,175Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />
      {/* Europe */}
      <path
        d="M290,65 Q310,55 335,60 Q355,65 360,80 Q362,95 350,105 Q340,112 325,115 Q310,118 295,110 Q285,100 282,85 Q280,75 290,65Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />
      {/* Africa */}
      <path
        d="M310,125 Q325,118 345,122 Q360,130 365,155 Q368,180 360,210 Q350,235 335,245 Q320,248 308,235 Q298,220 295,195 Q292,165 300,145 Q305,132 310,125Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />
      {/* Asia */}
      <path
        d="M380,55 Q420,45 470,50 Q520,58 555,80 Q570,100 565,125 Q555,145 535,155 Q510,162 480,165 Q450,170 420,160 Q395,148 382,130 Q370,110 372,85 Q375,65 380,55Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />
      {/* Australia */}
      <path
        d="M500,210 Q520,200 545,205 Q565,215 570,235 Q568,255 550,265 Q530,270 510,262 Q498,250 495,235 Q494,220 500,210Z"
        fill="rgba(255,255,255,0.02)"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth="0.8"
      />

      {/* Network paths */}
      {NETWORK_PATHS.map(([fromId, toId]) => {
        const from = regionMap[fromId];
        const to = regionMap[toId];
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
        const from = regionMap[pkt.fromRegion];
        const to = regionMap[pkt.toRegion];
        if (!from || !to) return null;
        const px = from.x + (to.x - from.x) * pkt.progress;
        const py = from.y + (to.y - from.y) * pkt.progress;
        const color = PACKET_COLORS[pkt.type];
        return (
          <g key={pkt.id}>
            <circle cx={px} cy={py} r="4" fill={color} opacity={0.3} filter="url(#noc-glow-strong)" />
            <circle cx={px} cy={py} r="2" fill={color} opacity={0.9} filter="url(#noc-glow)" />
          </g>
        );
      })}

      {/* Region nodes */}
      {regions.map((region) => {
        const metric = metricsMap[region.id];
        const isDown = metric?.status === 'down';
        const isDegraded = metric?.status === 'degraded';
        const ringColor = isDown ? '#ef4444' : isDegraded ? '#f59e0b' : region.color;
        const pulseOpacity = isDown ? 0.5 : isDegraded ? 0.3 : 0.15;
        return (
          <g key={region.id}>
            {/* Pulse ring */}
            <circle cx={region.x} cy={region.y} r="14" fill="none" stroke={ringColor} strokeWidth="1" opacity={pulseOpacity}>
              <animate attributeName="r" values="14;22;14" dur="2s" repeatCount="indefinite" />
              <animate attributeName="opacity" values={`${pulseOpacity};0;${pulseOpacity}`} dur="2s" repeatCount="indefinite" />
            </circle>
            {/* Node circle */}
            <circle cx={region.x} cy={region.y} r="8" fill={isDown ? '#1a0505' : 'rgba(0,0,0,0.6)'} stroke={ringColor} strokeWidth="1.5" />
            {isDown ? (
              <text x={region.x} y={region.y + 1} textAnchor="middle" dominantBaseline="middle" fill="#ef4444" fontSize="8" fontWeight="bold">
                X
              </text>
            ) : (
              <circle cx={region.x} cy={region.y} r="3" fill={ringColor} opacity={0.8} />
            )}
            {/* Label */}
            <text x={region.x} y={region.y - 16} textAnchor="middle" fill="rgba(255,255,255,0.6)" fontSize="8" fontFamily="monospace">
              {region.shortName}
            </text>
            {/* RPS label */}
            {metric && (
              <text x={region.x} y={region.y + 24} textAnchor="middle" fill="rgba(255,255,255,0.35)" fontSize="7" fontFamily="monospace">
                {isDown ? 'DOWN' : `${metric.rps.toLocaleString()} rps`}
              </text>
            )}
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
  status: 'healthy' | 'degraded' | 'down';
}) {
  const pct = Math.min((value / max) * 100, 100);
  const barColor =
    status === 'down' ? 'bg-red-500' : status === 'degraded' ? 'bg-yellow-500' : pct > 75 ? 'bg-amber-500' : 'bg-emerald-500';
  return (
    <div className="space-y-1">
      <div className="flex justify-between items-center">
        <span className="text-[9px] text-white/40 uppercase tracking-wider">{label}</span>
        <span className="text-[10px] font-mono text-white/60">
          {status === 'down' ? '--' : `${value.toLocaleString()}${unit}`}
        </span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${barColor}`}
          initial={{ width: 0 }}
          animate={{ width: status === 'down' ? '100%' : `${pct}%` }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          style={status === 'down' ? { opacity: 0.3 } : undefined}
        />
      </div>
    </div>
  );
}

function ThreatPanel({ threats }: { threats: ThreatEvent[] }) {
  if (threats.length === 0) {
    return (
      <div className="flex items-center justify-center py-6 gap-2">
        <CheckCircle2 className="h-4 w-4 text-emerald-400/50" />
        <span className="text-xs text-emerald-400/50">No active threats</span>
      </div>
    );
  }
  return (
    <div className="space-y-1.5 max-h-40 overflow-y-auto">
      {threats.map((t) => {
        const s = SEVERITY_STYLES[t.severity];
        return (
          <motion.div
            key={t.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className={`flex items-start gap-2 p-2 rounded-lg border ${s.border} ${s.bg}`}
          >
            <div className={`mt-0.5 h-2 w-2 rounded-full shrink-0 ${s.dot}`} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className={`text-[9px] font-bold uppercase tracking-wider ${s.text}`}>{t.severity}</span>
                <span className="text-[9px] text-white/30 font-mono">{t.timestamp}</span>
              </div>
              <p className="text-[10px] text-white/60 leading-tight mt-0.5 truncate">{t.message}</p>
            </div>
          </motion.div>
        );
      })}
    </div>
  );
}

function LiveLogStream({ logs }: { logs: LogLine[] }) {
  const LOG_TYPE_STYLES: Record<LogLine['type'], string> = {
    info: 'text-blue-400',
    warning: 'text-yellow-400',
    error: 'text-red-400',
    success: 'text-emerald-400',
  };

  return (
    <div className="space-y-1 font-mono text-[10px]">
      {logs.map((log, i) => (
        <motion.div
          key={log.id}
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: i * 0.08 }}
        >
          <div className="flex items-center gap-1">
            <span className="text-emerald-500/70">$</span>
            <span className="text-white/70">{log.command}</span>
          </div>
          <div className={`pl-3 ${LOG_TYPE_STYLES[log.type]} opacity-80`}>
            {log.output}
          </div>
        </motion.div>
      ))}
    </div>
  );
}

function NocStatCard({ label, value, icon, color }: { label: string; value: string; icon: React.ReactNode; color: string }) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-2.5 text-center">
      <div className={`flex items-center justify-center gap-1 ${color} mb-0.5`}>
        {icon}
        <span className="text-[9px] font-semibold uppercase tracking-wider">{label}</span>
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
  const [packets, setPackets] = useState<NetworkPacket[]>([]);
  const packetIdRef = useRef(0);
  const frameRef = useRef<ReturnType<typeof requestAnimationFrame> | null>(null);
  const lastTickRef = useRef<number>(0);
  const spawnTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const activeScenario = scenarios[stepIndex];

  // Aggregate stats
  const aggStats = useMemo(() => {
    const metrics = activeScenario.metrics;
    const totalRps = metrics.reduce((sum, m) => sum + m.rps, 0);
    const totalBw = metrics.reduce((sum, m) => sum + m.bandwidthMbps, 0);
    const healthyCount = metrics.filter((m) => m.status === 'healthy').length;
    const avgLatency =
      metrics.filter((m) => m.status !== 'down').length > 0
        ? Math.round(
            metrics.filter((m) => m.status !== 'down').reduce((sum, m) => sum + m.latencyMs, 0) /
              metrics.filter((m) => m.status !== 'down').length,
          )
        : 0;
    return { totalRps, totalBw, healthyCount, regionsTotal: metrics.length, avgLatency };
  }, [activeScenario]);

  // Spawn packets on a schedule
  const spawnPacket = useCallback(() => {
    const types = activeScenario.packetTypes;
    const pathIdx = Math.floor(Math.random() * NETWORK_PATHS.length);
    const path = NETWORK_PATHS[pathIdx];
    const typeIdx = Math.floor(Math.random() * types.length);
    packetIdRef.current += 1;
    const newPacket: NetworkPacket = {
      id: packetIdRef.current,
      fromRegion: path[0],
      toRegion: path[1],
      type: types[typeIdx],
      progress: 0,
    };
    setPackets((prev) => [...prev.slice(-20), newPacket]);
  }, [activeScenario.packetTypes]);

  // Animation loop for packet progress
  useEffect(() => {
    if (!isPlaying) {
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
        prev
          .map((p) => ({ ...p, progress: p.progress + dt * 0.5 }))
          .filter((p) => p.progress < 1),
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
  }, [isPlaying]);

  // Spawn packets periodically when playing
  useEffect(() => {
    if (!isPlaying) {
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
  }, [isPlaying, spawnPacket]);

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
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-violet-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-4 sm:p-6 lg:p-8 space-y-5">
        {/* Header */}
        <div className="text-center">
          <div className="inline-flex items-center gap-2 mb-2">
            <Globe className="h-4 w-4 text-blue-400" />
            <p className="text-sm font-semibold text-white/80">Network Operations Center</p>
            {isPlaying && (
              <motion.div
                animate={{ opacity: [1, 0.3, 1] }}
                transition={{ duration: 1.5, repeat: Infinity }}
                className="flex items-center gap-1"
              >
                <div className="h-2 w-2 rounded-full bg-red-400" />
                <span className="text-[10px] text-red-400 font-mono">LIVE</span>
              </motion.div>
            )}
          </div>
          <p className="text-xs text-white/40">
            Step through network scenarios to see how RANO monitors and responds to traffic events
          </p>
        </div>

        {/* Scenario stepper indicators */}
        <div className="flex items-center justify-center gap-1.5">
          {scenarios.map((s, i) => (
            <button
              key={s.id}
              type="button"
              onClick={() => {
                setStepIndex(i);
                setPackets([]);
              }}
              className={`h-1.5 rounded-full transition-all ${
                i === stepIndex ? 'w-6 bg-blue-400' : i < stepIndex ? 'w-3 bg-white/20' : 'w-3 bg-white/[0.08]'
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
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
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
              <p className="text-[10px] text-white/40 leading-snug mt-0.5">{activeScenario.description}</p>
            </div>
          </motion.div>
        </AnimatePresence>

        {/* Top-level aggregate stats */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <NocStatCard
            label="Total RPS"
            value={aggStats.totalRps.toLocaleString()}
            icon={<Activity className="h-3 w-3" />}
            color="text-blue-400"
          />
          <NocStatCard
            label="Bandwidth"
            value={`${aggStats.totalBw} Mbps`}
            icon={<Zap className="h-3 w-3" />}
            color="text-violet-400"
          />
          <NocStatCard
            label="Regions"
            value={`${aggStats.healthyCount}/${aggStats.regionsTotal}`}
            icon={<MapPin className="h-3 w-3" />}
            color={aggStats.healthyCount < aggStats.regionsTotal ? 'text-amber-400' : 'text-emerald-400'}
          />
          <NocStatCard
            label="Avg Latency"
            value={`${aggStats.avgLatency}ms`}
            icon={<Clock className="h-3 w-3" />}
            color={aggStats.avgLatency > 100 ? 'text-red-400' : aggStats.avgLatency > 50 ? 'text-amber-400' : 'text-emerald-400'}
          />
        </div>

        {/* Main grid: Map + Panels */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {/* World Map */}
          <div className="lg:col-span-2 rounded-2xl border border-white/[0.08] bg-black/30 overflow-hidden relative">
            <div className="px-3 py-2 border-b border-white/[0.06] flex items-center justify-between">
              <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                Global Traffic Map
              </span>
              <div className="flex items-center gap-3">
                {Object.entries(PACKET_COLORS).map(([type, color]) => (
                  <div key={type} className="flex items-center gap-1">
                    <div className="h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
                    <span className="text-[8px] text-white/30 capitalize">{type}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="p-2 aspect-[2/1]">
              <WorldMapSvg
                regions={REGIONS}
                packets={packets}
                activeScenario={activeScenario}
              />
            </div>
          </div>

          {/* Right sidebar: Metrics + Threats */}
          <div className="space-y-4">
            {/* Region Metrics */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
              <div className="px-3 py-2 border-b border-white/[0.06]">
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Region Metrics
                </span>
              </div>
              <div className="p-3 space-y-3">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={activeScenario.id}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    className="space-y-3"
                  >
                    {activeScenario.metrics.map((m) => {
                      const region = REGIONS.find((r) => r.id === m.regionId);
                      if (!region) return null;
                      return (
                        <div key={m.regionId} className="space-y-1.5">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-1.5">
                              <div
                                className="h-2 w-2 rounded-full"
                                style={{ backgroundColor: m.status === 'down' ? '#ef4444' : m.status === 'degraded' ? '#f59e0b' : region.color }}
                              />
                              <span className="text-[10px] font-mono text-white/60">{region.shortName}</span>
                            </div>
                            <span className={`text-[9px] font-bold uppercase tracking-wider ${
                              m.status === 'down' ? 'text-red-400' : m.status === 'degraded' ? 'text-yellow-400' : 'text-emerald-400'
                            }`}>
                              {m.status}
                            </span>
                          </div>
                          <MetricGauge label="Req/s" value={m.rps} max={50000} unit="" status={m.status} />
                          <MetricGauge label="Latency" value={m.latencyMs} max={500} unit="ms" status={m.status} />
                        </div>
                      );
                    })}
                  </motion.div>
                </AnimatePresence>
              </div>
            </div>

            {/* Threat Detection Panel */}
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
              <div className="px-3 py-2 border-b border-white/[0.06] flex items-center justify-between">
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Threat Detection
                </span>
                {activeScenario.threats.length > 0 && (
                  <span className="text-[9px] font-mono text-red-400">
                    {activeScenario.threats.length} alert{activeScenario.threats.length !== 1 ? 's' : ''}
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
                    transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                  >
                    <ThreatPanel threats={activeScenario.threats} />
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
              <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                RANO Command Log
              </span>
            </div>
            <span className="text-[9px] font-mono text-white/30">
              ~ {activeScenario.logs.length} commands
            </span>
          </div>
          <div className="p-3 max-h-36 overflow-y-auto">
            <AnimatePresence mode="wait">
              <motion.div
                key={activeScenario.id}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
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
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className={`flex items-center gap-1.5 rounded-2xl border px-4 py-2 text-xs font-medium transition-colors ${
              stepIndex === 0
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white/80'
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
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className={`flex items-center gap-2 rounded-2xl border px-5 py-2.5 text-sm font-medium transition-colors ${
              isPlaying
                ? 'border-red-500/30 bg-red-500/10 text-red-300 hover:bg-red-500/20'
                : 'border-blue-500/30 bg-blue-500/10 text-blue-300 hover:bg-blue-500/20'
            }`}
          >
            {isPlaying ? (
              <>
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
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
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className={`flex items-center gap-1.5 rounded-2xl border px-4 py-2 text-xs font-medium transition-colors ${
              stepIndex === scenarios.length - 1
                ? 'border-white/[0.04] text-white/20 cursor-not-allowed'
                : 'border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white/80'
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
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="flex items-center gap-1.5 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-4 py-2 text-xs font-medium text-white/40 hover:text-white/60 transition-colors"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            Reset
          </motion.button>
        </div>
      </div>
    </div>
  );
}
