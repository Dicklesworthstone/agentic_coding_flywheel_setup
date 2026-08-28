"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Key,
  Lock,
  Wifi,
  WifiOff,
  Shield,
  ShieldCheck,
  ShieldAlert,
  RefreshCw,
  Terminal,
  CheckCircle2,
  HelpCircle,
  Monitor,
  Server,
  Cloud,
  ArrowRight,
  Eye,
  EyeOff,
  Zap,
  AlertTriangle,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  InlineCode,
  FeatureGrid,
  FeatureCard,
} from "./lesson-components";

export function SSHBasicsLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Understand how to stay connected to your VPS.
      </GoalBanner>

      {/* What Is SSH */}
      <Section
        title="What Is SSH?"
        icon={<Lock className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>SSH (Secure Shell)</Highlight> is how you&apos;re connected to
          this VPS right now.
        </Paragraph>
        <Paragraph>
          It&apos;s an encrypted tunnel between your laptop and this server.
        </Paragraph>

        {/* Visual Connection Diagram */}
        <div className="mt-8">
          <InteractiveSSHTunnel />
        </div>
      </Section>

      <Divider />

      {/* How You Got Here */}
      <Section
        title="How You Got Here"
        icon={<Key className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          Your VPS connection happened in two stages:
        </Paragraph>

        {/* Stage Cards */}
        <div className="mt-8 grid gap-6 md:grid-cols-2">
          <StageCard
            number={1}
            title="Password Login"
            subtitle="During Setup"
            description="When you first created your VPS, you connected as root with a password"
            code="ssh root@YOUR_SERVER_IP"
            gradient="from-amber-500/20 to-orange-500/20"
          />
          <StageCard
            number={2}
            title="Key-Based Login"
            subtitle="Now"
            description="The installer copied your SSH key, so now you connect securely"
            code="ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_SERVER_IP"
            gradient="from-emerald-500/20 to-teal-500/20"
          />
        </div>

        {/* Command Breakdown */}
        <div className="mt-8">
          <h4 className="text-lg font-semibold text-white mb-4">
            Breaking down the command:
          </h4>
          <div className="grid gap-3 sm:grid-cols-2">
            <CommandPart label="ssh" description="The command" />
            <CommandPart
              label="-i ~/.ssh/acfs_ed25519"
              description="Your private key"
            />
            <CommandPart
              label="ubuntu"
              description="Your regular user (safer than root)"
            />
            <CommandPart
              label="@YOUR_SERVER_IP"
              description="The server address"
            />
          </div>
        </div>
      </Section>

      <Divider />

      {/* If Connection Drops */}
      <Section
        title="If Your Connection Drops"
        icon={<RefreshCw className="h-5 w-5" />}
        delay={0.2}
      >
        <TipBox variant="info">
          No worries! SSH connections drop sometimes. Just reconnect—your work
          is safe in tmux (next lesson).
        </TipBox>
      </Section>

      <Divider />

      {/* SSH Keys vs Passwords */}
      <Section
        title="SSH Keys vs Passwords"
        icon={<Shield className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          You&apos;re now using <Highlight>key-based authentication</Highlight>:
        </Paragraph>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="Private Key"
              description="Stays on your laptop at ~/.ssh/acfs_ed25519"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Lock className="h-5 w-5" />}
              title="Public Key"
              description="Lives on the VPS at ~/.ssh/authorized_keys"
              gradient="from-sky-500/20 to-blue-500/20"
            />
          </FeatureGrid>
        </div>

        <div className="mt-6">
          <Paragraph>
            This is more secure than passwords and lets you connect without
            typing anything.
          </Paragraph>
        </div>
      </Section>

      <Divider />

      {/* Keeping Connections Alive */}
      <Section
        title="Keeping Connections Alive"
        icon={<Wifi className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          Add this to your laptop&apos;s <InlineCode>~/.ssh/config</InlineCode>:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3`}
            language="ssh-config"
            filename="~/.ssh/config"
          />
        </div>

        <Paragraph>This sends keepalive packets every 60 seconds.</Paragraph>
      </Section>

      <Divider />

      {/* Quick Connect Alias */}
      <Section
        title="Quick Connect Alias"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          On your laptop, add to <InlineCode>~/.zshrc</InlineCode> or{" "}
          <InlineCode>~/.bashrc</InlineCode>:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`alias vps='ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_SERVER_IP'`}
            language="bash"
          />
        </div>

        <Paragraph>
          Then just type <InlineCode>vps</InlineCode> to connect!
        </Paragraph>
      </Section>

      <Divider />

      {/* Verify Section */}
      <Section
        title="Verify Your Understanding"
        icon={<HelpCircle className="h-5 w-5" />}
        delay={0.4}
      >
        <QuizCards />
      </Section>

      <Divider />

      {/* Practice Commands */}
      <Section
        title="Practice This Now"
        icon={<CheckCircle2 className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          Try these commands to confirm your SSH setup is working:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check your current user (should say "ubuntu")
$ whoami

# Check how long you've been connected
$ w

# View the public keys authorized to access this account
$ cat ~/.ssh/authorized_keys`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            When you see your public key (starts with{" "}
            <InlineCode>ssh-ed25519</InlineCode>), you know the setup worked!
          </TipBox>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE SSH TUNNEL V2 - Rich network visualization with 4 scenarios
// =============================================================================
type TunnelScenario = "connect" | "keyauth" | "portforward" | "reconnect";

interface TunnelPacket {
  id: number;
  progress: number;
  direction: "outgoing" | "incoming";
  label: string;
  encryptedLabel: string;
  color: string;
}

const SCENARIO_META: Record<TunnelScenario, { label: string; icon: React.ReactNode; description: string }> = {
  connect: { label: "SSH Connect", icon: <Zap className="h-3.5 w-3.5" />, description: "Watch the handshake: key exchange, authentication, and tunnel establishment" },
  keyauth: { label: "Key Auth", icon: <Key className="h-3.5 w-3.5" />, description: "See how public/private key pairs authenticate without passwords" },
  portforward: { label: "Port Forward", icon: <ArrowRight className="h-3.5 w-3.5" />, description: "Local port maps through the tunnel to a remote service" },
  reconnect: { label: "Reconnect", icon: <RefreshCw className="h-3.5 w-3.5" />, description: "Connection drops happen -- mosh and tmux keep your session alive" },
};

const SPRING_SMOOTH = { type: "spring" as const, stiffness: 200, damping: 25 };

// --- Shared SVG sub-components ---

function TunnelDefs({ encrypted }: { encrypted: boolean }) {
  const tunnelColor = encrypted ? "#22c55e" : "#ef4444";
  return (
    <defs>
      <linearGradient id="sshTunnelGrad" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stopColor="#3b82f6" stopOpacity="0.3" />
        <stop offset="30%" stopColor={tunnelColor} stopOpacity="0.5" />
        <stop offset="70%" stopColor={tunnelColor} stopOpacity="0.5" />
        <stop offset="100%" stopColor="#06b6d4" stopOpacity="0.3" />
      </linearGradient>
      <linearGradient id="sshTunnelGradRed" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stopColor="#ef4444" stopOpacity="0.2" />
        <stop offset="50%" stopColor="#ef4444" stopOpacity="0.35" />
        <stop offset="100%" stopColor="#ef4444" stopOpacity="0.2" />
      </linearGradient>
      <filter id="sshGlow">
        <feGaussianBlur stdDeviation="3" result="coloredBlur" />
        <feMerge>
          <feMergeNode in="coloredBlur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      <filter id="sshStrongGlow">
        <feGaussianBlur stdDeviation="5" result="coloredBlur" />
        <feMerge>
          <feMergeNode in="coloredBlur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      <filter id="sshGlitch">
        <feTurbulence type="turbulence" baseFrequency="0.05" numOctaves="2" result="turb" />
        <feDisplacementMap in="SourceGraphic" in2="turb" scale="8" />
      </filter>
    </defs>
  );
}

function LaptopIcon({ x, y }: { x: number; y: number }) {
  return (
    <motion.g
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: 0.1, ...SPRING_SMOOTH }}
    >
      {/* Laptop body */}
      <rect x={x} y={y} width="80" height="55" rx="8" fill="none" stroke="#60a5fa" strokeWidth="1.5" opacity="0.7" />
      <rect x={x + 8} y={y + 7} width="64" height="35" rx="3" fill="#3b82f6" opacity="0.12" />
      {/* Laptop base */}
      <rect x={x - 8} y={y + 55} width="96" height="8" rx="4" fill="none" stroke="#60a5fa" strokeWidth="1.5" opacity="0.7" />
      {/* Terminal prompt */}
      <text x={x + 14} y={y + 22} fill="#60a5fa" fontSize="7" fontFamily="monospace" opacity="0.8">$ ssh</text>
      {/* Blinking cursor */}
      <motion.rect
        x={x + 42}
        y={y + 14}
        width="6"
        height="12"
        rx="1"
        fill="#60a5fa"
        animate={{ opacity: [1, 0.15, 1] }}
        transition={{ duration: 1.2, repeat: Infinity }}
      />
      {/* Label */}
      <text x={x + 40} y={y + 85} textAnchor="middle" fill="white" fontSize="12" fontWeight="500">
        Your Laptop
      </text>
      {/* Monitor icon glyph */}
      <Monitor
        x={x + 28}
        y={y + 68}
        className="text-blue-400/50"
        width={24}
        height={14}
        strokeWidth={1.2}
      />
    </motion.g>
  );
}

function CloudIcon({ x, y }: { x: number; y: number }) {
  return (
    <motion.g
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2, ...SPRING_SMOOTH }}
    >
      <Cloud x={x - 16} y={y - 8} className="text-white/20" width={32} height={24} strokeWidth={1} />
      <text x={x} y={y + 24} textAnchor="middle" fill="white" fontSize="9" opacity="0.4">Internet</text>
    </motion.g>
  );
}

function ServerIcon({ x, y, blinking }: { x: number; y: number; blinking?: boolean }) {
  return (
    <motion.g
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: 0.15, ...SPRING_SMOOTH }}
    >
      {/* Server rack */}
      <rect x={x} y={y} width="80" height="70" rx="8" fill="none" stroke="#22d3ee" strokeWidth="1.5" opacity="0.7" />
      {[0, 1, 2].map((i) => (
        <g key={i}>
          <rect x={x + 10} y={y + 10 + i * 20} width="60" height="12" rx="2" fill="#06b6d4" opacity="0.1" />
          <motion.circle
            cx={x + 62}
            cy={y + 16 + i * 20}
            r="3"
            fill={blinking === false ? "#ef4444" : "#22d3ee"}
            animate={{ opacity: blinking === false ? 0.3 : [0.4, 1, 0.4] }}
            transition={{ duration: 1.5, repeat: Infinity, delay: i * 0.3 }}
          />
        </g>
      ))}
      <text x={x + 40} y={y + 90} textAnchor="middle" fill="white" fontSize="12" fontWeight="500">
        Your VPS
      </text>
      <Server x={x + 28} y={y + 73} className="text-cyan-400/50" width={24} height={14} strokeWidth={1.2} />
    </motion.g>
  );
}

function EncryptedTunnel({
  encrypted,
  broken,
  establishing,
}: {
  encrypted: boolean;
  broken?: boolean;
  establishing?: boolean;
}) {
  const tunnelColor = encrypted ? "#22c55e" : "#ef4444";
  const gradId = encrypted ? "sshTunnelGrad" : "sshTunnelGradRed";
  return (
    <motion.g
      initial={{ opacity: 0, scaleX: 0 }}
      animate={{
        opacity: broken ? 0.3 : 1,
        scaleX: broken ? 0.7 : 1,
        filter: broken ? "url(#sshGlitch)" : "none",
      }}
      transition={{ delay: 0.3, duration: 0.6 }}
      style={{ originX: "50%", originY: "50%" }}
    >
      {/* Outer tunnel shell */}
      <motion.rect
        x="150"
        y="108"
        width="300"
        height="44"
        rx="22"
        fill={`url(#${gradId})`}
        stroke={tunnelColor}
        strokeWidth="1"
        strokeOpacity={0.35}
        animate={{
          strokeOpacity: establishing ? [0.1, 0.6, 0.1] : broken ? 0.15 : [0.25, 0.55, 0.25],
        }}
        transition={{ duration: establishing ? 0.6 : 2, repeat: Infinity }}
        filter={encrypted && !broken ? "url(#sshGlow)" : undefined}
      />
      {/* Inner data path */}
      <motion.line
        x1="170"
        y1="130"
        x2="430"
        y2="130"
        stroke={tunnelColor}
        strokeWidth="1"
        strokeDasharray="6 4"
        strokeOpacity={broken ? 0.1 : 0.3}
        animate={{ strokeDashoffset: broken ? 0 : [0, -20] }}
        transition={{ duration: 1.5, repeat: Infinity, ease: "linear" }}
      />
      {/* Center lock icon */}
      {encrypted && !broken && (
        <motion.g
          animate={{ opacity: [0.5, 1, 0.5] }}
          transition={{ duration: 2.5, repeat: Infinity }}
          filter="url(#sshStrongGlow)"
        >
          <rect x="289" y="120" width="22" height="16" rx="3" fill="none" stroke="#22c55e" strokeWidth="1.2" />
          <path d="M293 120 V116 A7 7 0 0 1 307 116 V120" fill="none" stroke="#22c55e" strokeWidth="1.2" />
          <circle cx="300" cy="129" r="2" fill="#22c55e" opacity="0.8" />
        </motion.g>
      )}
      {!encrypted && !broken && (
        <motion.g animate={{ opacity: [0.4, 0.8, 0.4] }} transition={{ duration: 1.5, repeat: Infinity }}>
          <rect x="289" y="120" width="22" height="16" rx="3" fill="none" stroke="#ef4444" strokeWidth="1.2" opacity="0.6" />
          <path d="M293 120 V116 A7 7 0 0 1 307 116 V124" fill="none" stroke="#ef4444" strokeWidth="1.2" opacity="0.6" />
        </motion.g>
      )}
      {broken && (
        <motion.g animate={{ opacity: [0.3, 0.7, 0.3] }} transition={{ duration: 0.8, repeat: Infinity }}>
          <line x1="290" y1="118" x2="310" y2="142" stroke="#ef4444" strokeWidth="2" opacity="0.7" />
          <line x1="310" y1="118" x2="290" y2="142" stroke="#ef4444" strokeWidth="2" opacity="0.7" />
        </motion.g>
      )}
    </motion.g>
  );
}

function DataPackets({
  packets,
  encrypted,
}: {
  packets: TunnelPacket[];
  encrypted: boolean;
}) {
  return (
    <>
      {packets.map((pkt) => {
        const startX = pkt.direction === "outgoing" ? 140 : 460;
        const endX = pkt.direction === "outgoing" ? 460 : 140;
        const x = startX + (endX - startX) * pkt.progress;
        const y = 130;
        const inTunnel = pkt.progress > 0.15 && pkt.progress < 0.85;
        const showEncrypted = encrypted && inTunnel;
        const fillColor = showEncrypted
          ? "#eab308"
          : pkt.direction === "outgoing"
            ? "#22c55e"
            : "#06b6d4";
        const displayText = showEncrypted ? pkt.encryptedLabel : pkt.label;

        return (
          <motion.g
            key={pkt.id}
            initial={{ opacity: 0, scale: 0.4 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.4 }}
          >
            {/* Packet glow */}
            <motion.circle cx={x} cy={y} r="14" fill={fillColor} opacity={0.08}
              animate={{ r: [14, 18, 14], opacity: [0.06, 0.12, 0.06] }}
              transition={{ duration: 1.2, repeat: Infinity }}
            />
            {/* Packet body */}
            <rect x={x - 22} y={y - 9} width="44" height="18" rx="4" fill={fillColor} opacity={0.15} />
            <rect x={x - 22} y={y - 9} width="44" height="18" rx="4" fill="none" stroke={fillColor} strokeWidth="0.8" opacity={0.5} />
            <text x={x} y={y + 3.5} textAnchor="middle" fill={fillColor} fontSize="7" fontFamily="monospace" fontWeight="600">
              {displayText}
            </text>
            {showEncrypted && (
              <motion.g animate={{ opacity: [0.4, 0.9, 0.4] }} transition={{ duration: 0.6, repeat: Infinity }}>
                <rect x={x + 16} y={y - 7} width="8" height="7" rx="1.5" fill="none" stroke="#eab308" strokeWidth="0.7" />
                <path d={`M${x + 18} ${y - 7} V${y - 9.5} A2.5 2.5 0 0 1 ${x + 22.5} ${y - 9.5} V${y - 7}`} fill="none" stroke="#eab308" strokeWidth="0.7" />
              </motion.g>
            )}
            {!encrypted && inTunnel && (
              <motion.g animate={{ opacity: [0.5, 1, 0.5] }} transition={{ duration: 0.8, repeat: Infinity }}>
                <AlertTriangle x={x + 14} y={y - 10} width={10} height={10} className="text-red-500" strokeWidth={2} />
              </motion.g>
            )}
          </motion.g>
        );
      })}
    </>
  );
}

function StatusBadge({ connected, latencyMs, encrypted }: { connected: boolean; latencyMs: number; encrypted: boolean }) {
  return (
    <motion.g initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.5 }}>
      <rect x="232" y="218" width="136" height="24" rx="12" fill={connected ? (encrypted ? "#22c55e" : "#ef4444") : "#6b7280"} opacity="0.1" />
      <rect x="232" y="218" width="136" height="24" rx="12" fill="none" stroke={connected ? (encrypted ? "#22c55e" : "#ef4444") : "#6b7280"} strokeWidth="0.7" opacity="0.4" />
      <motion.circle
        cx="248"
        cy="230"
        r="3.5"
        fill={connected ? (encrypted ? "#22c55e" : "#ef4444") : "#6b7280"}
        animate={{ opacity: connected ? [0.5, 1, 0.5] : 0.3 }}
        transition={{ duration: 1.5, repeat: Infinity }}
      />
      <text x="300" y="234" textAnchor="middle" fill={connected ? (encrypted ? "#22c55e" : "#ef4444") : "#6b7280"} fontSize="9" fontWeight="600">
        {connected ? (encrypted ? `SECURED  ${latencyMs}ms` : `UNENCRYPTED  ${latencyMs}ms`) : "DISCONNECTED"}
      </text>
    </motion.g>
  );
}

// --- Scenario renderers ---

function ScenarioConnect() {
  const [phase, setPhase] = useState(0); // 0=idle, 1=handshake, 2=auth, 3=established
  const [packets, setPackets] = useState<TunnelPacket[]>([]);
  const counterRef = useRef(0);
  const phaseRef = useRef(0);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const schedulePhases = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    const t1 = setTimeout(() => { setPhase(1); phaseRef.current = 1; }, 400);
    const t2 = setTimeout(() => { setPhase(2); phaseRef.current = 2; }, 2000);
    const t3 = setTimeout(() => { setPhase(3); phaseRef.current = 3; }, 3600);
    timersRef.current = [t1, t2, t3];
  }, []);

  const replay = useCallback(() => {
    setPhase(0);
    setPackets([]);
    counterRef.current = 0;
    phaseRef.current = 0;
    schedulePhases();
  }, [schedulePhases]);

  useEffect(() => {
    schedulePhases();
    return () => { timersRef.current.forEach(clearTimeout); };
  }, [schedulePhases]);

  // Packet animation when established
  useEffect(() => {
    const moveInterval = setInterval(() => {
      setPackets((prev) =>
        prev.map((p) => ({ ...p, progress: p.progress + 0.018 })).filter((p) => p.progress <= 1)
      );
    }, 32);

    const spawnInterval = setInterval(() => {
      if (phaseRef.current < 3) return;
      counterRef.current += 1;
      const id = counterRef.current;
      const cmds = ["ls -la", "cd /var", "whoami", "cat log", "git pull"];
      const encs = ["x9#kQ!", "aZ&2mP", "!Rv8$f", "qW3@nL", "7b*Yj#"];
      const isOut = id % 2 !== 0;
      const idx = id % cmds.length;
      setPackets((prev) => [
        ...prev,
        { id, progress: 0, direction: isOut ? "outgoing" : "incoming", label: cmds[idx], encryptedLabel: encs[idx], color: isOut ? "#22c55e" : "#06b6d4" },
      ]);
    }, 1800);

    return () => { clearInterval(moveInterval); clearInterval(spawnInterval); };
  }, []);

  const phaseLabels = [
    { step: "Initiating...", detail: "Client sends hello" },
    { step: "Key Exchange", detail: "Diffie-Hellman negotiation" },
    { step: "Authentication", detail: "Verifying identity" },
    { step: "Tunnel Active", detail: "Encrypted channel ready" },
  ];
  const current = phaseLabels[phase];

  return (
    <div className="space-y-3">
      <svg viewBox="0 0 600 260" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <TunnelDefs encrypted={true} />
        <LaptopIcon x={20} y={85} />
        <CloudIcon x={300} y={56} />
        <ServerIcon x={500} y={82} />

        {phase >= 1 && (
          <EncryptedTunnel encrypted={phase >= 3} establishing={phase < 3} />
        )}

        {/* Handshake animation: keys meeting in center */}
        {phase === 1 && (
          <>
            <motion.g
              initial={{ x: 160 }}
              animate={{ x: 270 }}
              transition={{ duration: 1.4, ease: "easeInOut" }}
              filter="url(#sshStrongGlow)"
            >
              <circle cx="0" cy="130" r="10" fill="none" stroke="#3b82f6" strokeWidth="1.5" />
              <text x="0" y="134" textAnchor="middle" fill="#3b82f6" fontSize="10" fontWeight="bold">K</text>
            </motion.g>
            <motion.g
              initial={{ x: 440 }}
              animate={{ x: 330 }}
              transition={{ duration: 1.4, ease: "easeInOut" }}
              filter="url(#sshStrongGlow)"
            >
              <circle cx="0" cy="130" r="10" fill="none" stroke="#06b6d4" strokeWidth="1.5" />
              <text x="0" y="134" textAnchor="middle" fill="#06b6d4" fontSize="10" fontWeight="bold">K</text>
            </motion.g>
          </>
        )}

        {/* Auth verification */}
        {phase === 2 && (
          <motion.g
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: [0, 1, 1, 0.5], scale: [0.5, 1.2, 1, 1] }}
            transition={{ duration: 1.4, times: [0, 0.3, 0.6, 1] }}
            filter="url(#sshStrongGlow)"
          >
            <ShieldCheck x={288} y={116} className="text-emerald-400" width={24} height={24} strokeWidth={1.5} />
          </motion.g>
        )}

        {phase >= 3 && <DataPackets packets={packets} encrypted={true} />}
        <StatusBadge connected={phase >= 3} latencyMs={phase >= 3 ? 42 : 0} encrypted={true} />
      </svg>

      {/* Phase stepper */}
      <div className="flex items-center justify-between px-2">
        <div className="flex items-center gap-2">
          {phaseLabels.map((p, i) => (
            <div key={i} className="flex items-center gap-1.5">
              <motion.div
                className={`h-2 w-2 rounded-full ${i <= phase ? "bg-emerald-400" : "bg-white/20"}`}
                animate={{ scale: i === phase ? [1, 1.4, 1] : 1 }}
                transition={{ duration: 1, repeat: i === phase ? Infinity : 0 }}
              />
              {i < phaseLabels.length - 1 && (
                <div className={`w-6 h-px ${i < phase ? "bg-emerald-400/50" : "bg-white/10"}`} />
              )}
            </div>
          ))}
        </div>
        <div className="text-right">
          <span className="text-xs font-semibold text-emerald-400">{current.step}</span>
          <span className="text-xs text-white/40 ml-2">{current.detail}</span>
        </div>
      </div>

      <div className="flex justify-center">
        <button
          onClick={replay}
          className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.03] border border-white/[0.08] text-white/50 hover:border-white/[0.15] hover:text-white/70 transition duration-300"
        >
          <RefreshCw className="h-3 w-3" /> Replay
        </button>
      </div>
    </div>
  );
}

function ScenarioKeyAuth() {
  const [matchPhase, setMatchPhase] = useState(0); // 0=idle, 1=comparing, 2=matched
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const scheduleMatch = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    const t1 = setTimeout(() => setMatchPhase(1), 500);
    const t2 = setTimeout(() => setMatchPhase(2), 2200);
    timersRef.current = [t1, t2];
  }, []);

  const replay = useCallback(() => {
    setMatchPhase(0);
    scheduleMatch();
  }, [scheduleMatch]);

  useEffect(() => {
    scheduleMatch();
    return () => { timersRef.current.forEach(clearTimeout); };
  }, [scheduleMatch]);

  return (
    <div className="space-y-3">
      <svg viewBox="0 0 600 280" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <TunnelDefs encrypted={true} />
        <LaptopIcon x={20} y={85} />
        <ServerIcon x={500} y={82} />

        {/* Private key on laptop side */}
        <motion.g
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, ...SPRING_SMOOTH }}
        >
          <rect x="10" y="195" width="100" height="50" rx="8" fill="#8b5cf6" opacity="0.08" />
          <rect x="10" y="195" width="100" height="50" rx="8" fill="none" stroke="#8b5cf6" strokeWidth="0.8" opacity="0.4" />
          <Key x={20} y={203} className="text-violet-400" width={14} height={14} strokeWidth={1.5} />
          <text x="38" y="213" fill="#a78bfa" fontSize="8" fontWeight="600">PRIVATE KEY</text>
          <text x="18" y="228" fill="white" fontSize="6.5" fontFamily="monospace" opacity="0.5">~/.ssh/acfs_ed25519</text>
          <text x="18" y="238" fill="#a78bfa" fontSize="6" fontFamily="monospace" opacity="0.4">SHA256:xR3...9kQ</text>
        </motion.g>

        {/* Public key on server side */}
        <motion.g
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, ...SPRING_SMOOTH }}
        >
          <rect x="490" y="195" width="100" height="50" rx="8" fill="#0ea5e9" opacity="0.08" />
          <rect x="490" y="195" width="100" height="50" rx="8" fill="none" stroke="#0ea5e9" strokeWidth="0.8" opacity="0.4" />
          <Lock x={500} y={203} className="text-sky-400" width={14} height={14} strokeWidth={1.5} />
          <text x="518" y="213" fill="#38bdf8" fontSize="8" fontWeight="600">PUBLIC KEY</text>
          <text x="498" y="228" fill="white" fontSize="6.5" fontFamily="monospace" opacity="0.5">~/.ssh/authorized_keys</text>
          <text x="498" y="238" fill="#38bdf8" fontSize="6" fontFamily="monospace" opacity="0.4">SHA256:xR3...9kQ</text>
        </motion.g>

        {/* Matching animation: keys flying to center */}
        {matchPhase >= 1 && (
          <>
            <motion.g
              initial={{ x: 60, y: 210, opacity: 0.8 }}
              animate={{ x: 250, y: 130, opacity: 1 }}
              transition={{ duration: 1.2, ease: "easeInOut" }}
              filter="url(#sshStrongGlow)"
            >
              <circle cx="0" cy="0" r="12" fill="#8b5cf6" opacity="0.2" />
              <circle cx="0" cy="0" r="12" fill="none" stroke="#8b5cf6" strokeWidth="1.2" />
              <Key x={-6} y={-6} className="text-violet-400" width={12} height={12} strokeWidth={2} />
            </motion.g>
            <motion.g
              initial={{ x: 540, y: 210, opacity: 0.8 }}
              animate={{ x: 350, y: 130, opacity: 1 }}
              transition={{ duration: 1.2, ease: "easeInOut" }}
              filter="url(#sshStrongGlow)"
            >
              <circle cx="0" cy="0" r="12" fill="#0ea5e9" opacity="0.2" />
              <circle cx="0" cy="0" r="12" fill="none" stroke="#0ea5e9" strokeWidth="1.2" />
              <Lock x={-6} y={-6} className="text-sky-400" width={12} height={12} strokeWidth={2} />
            </motion.g>
          </>
        )}

        {/* Match success burst */}
        {matchPhase === 2 && (
          <motion.g
            initial={{ opacity: 0, scale: 0.3 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING_SMOOTH}
            filter="url(#sshStrongGlow)"
          >
            <motion.circle cx="300" cy="130" r="24" fill="#22c55e" opacity={0.15}
              animate={{ r: [24, 35, 24], opacity: [0.15, 0.05, 0.15] }}
              transition={{ duration: 2, repeat: Infinity }}
            />
            <ShieldCheck x={288} y={118} className="text-emerald-400" width={24} height={24} strokeWidth={1.5} />
            <text x="300" y="168" textAnchor="middle" fill="#22c55e" fontSize="9" fontWeight="600">KEYS MATCHED</text>
          </motion.g>
        )}

        {/* Tunnel appears after match */}
        {matchPhase === 2 && <EncryptedTunnel encrypted={true} />}
      </svg>

      <div className="flex items-center justify-center gap-6 text-xs">
        <div className="flex items-center gap-1.5 text-violet-400">
          <div className="h-2 w-2 rounded-full bg-violet-400" />
          Private (stays on laptop)
        </div>
        <div className="flex items-center gap-1.5 text-sky-400">
          <div className="h-2 w-2 rounded-full bg-sky-400" />
          Public (lives on server)
        </div>
        <div className="flex items-center gap-1.5 text-emerald-400">
          <motion.div
            className="h-2 w-2 rounded-full bg-emerald-400"
            animate={{ opacity: matchPhase === 2 ? 1 : 0.3 }}
          />
          {matchPhase === 2 ? "Authenticated" : "Waiting..."}
        </div>
      </div>

      <div className="flex justify-center">
        <button
          onClick={replay}
          className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.03] border border-white/[0.08] text-white/50 hover:border-white/[0.15] hover:text-white/70 transition duration-300"
        >
          <RefreshCw className="h-3 w-3" /> Replay
        </button>
      </div>
    </div>
  );
}

function ScenarioPortForward() {
  const [packets, setPackets] = useState<TunnelPacket[]>([]);
  const counterRef = useRef(0);

  useEffect(() => {
    const moveInterval = setInterval(() => {
      setPackets((prev) =>
        prev.map((p) => ({ ...p, progress: p.progress + 0.015 })).filter((p) => p.progress <= 1)
      );
    }, 32);

    const spawnInterval = setInterval(() => {
      counterRef.current += 1;
      const id = counterRef.current;
      const isOut = id % 2 !== 0;
      const labels = ["GET /api", "POST /db", "SELECT *", "200 OK", "JSON {}"];
      const encs = ["a#F2!q", "kP9&xZ", "mR$7jL", "vN3@wQ", "bY8*hT"];
      const idx = id % labels.length;
      setPackets((prev) => [
        ...prev,
        { id, progress: 0, direction: isOut ? "outgoing" : "incoming", label: labels[idx], encryptedLabel: encs[idx], color: isOut ? "#f59e0b" : "#8b5cf6" },
      ]);
    }, 1600);

    return () => { clearInterval(moveInterval); clearInterval(spawnInterval); };
  }, []);

  return (
    <div className="space-y-3">
      <svg viewBox="0 0 600 290" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <TunnelDefs encrypted={true} />
        <LaptopIcon x={20} y={85} />
        <CloudIcon x={300} y={56} />
        <ServerIcon x={500} y={82} />
        <EncryptedTunnel encrypted={true} />
        <DataPackets packets={packets} encrypted={true} />

        {/* Local port label */}
        <motion.g
          initial={{ opacity: 0, x: -10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.5, ...SPRING_SMOOTH }}
        >
          <rect x="8" y="170" width="104" height="36" rx="6" fill="#f59e0b" opacity="0.06" />
          <rect x="8" y="170" width="104" height="36" rx="6" fill="none" stroke="#f59e0b" strokeWidth="0.7" opacity="0.3" />
          <text x="60" y="184" textAnchor="middle" fill="#f59e0b" fontSize="8" fontWeight="600">LOCAL PORT</text>
          <text x="60" y="198" textAnchor="middle" fill="#fbbf24" fontSize="10" fontFamily="monospace" fontWeight="bold">localhost:5432</text>
        </motion.g>

        {/* Arrow from local port into tunnel */}
        <motion.g initial={{ opacity: 0 }} animate={{ opacity: 0.6 }} transition={{ delay: 0.7 }}>
          <motion.line x1="112" y1="188" x2="148" y2="135" stroke="#f59e0b" strokeWidth="1" strokeDasharray="4 3"
            animate={{ strokeDashoffset: [0, -14] }}
            transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
          />
          <polygon points="146,131 152,136 146,140" fill="#f59e0b" opacity="0.6" />
        </motion.g>

        {/* Remote port label */}
        <motion.g
          initial={{ opacity: 0, x: 10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.6, ...SPRING_SMOOTH }}
        >
          <rect x="488" y="170" width="104" height="36" rx="6" fill="#8b5cf6" opacity="0.06" />
          <rect x="488" y="170" width="104" height="36" rx="6" fill="none" stroke="#8b5cf6" strokeWidth="0.7" opacity="0.3" />
          <text x="540" y="184" textAnchor="middle" fill="#8b5cf6" fontSize="8" fontWeight="600">REMOTE PORT</text>
          <text x="540" y="198" textAnchor="middle" fill="#a78bfa" fontSize="10" fontFamily="monospace" fontWeight="bold">postgres:5432</text>
        </motion.g>

        {/* Arrow from tunnel to remote port */}
        <motion.g initial={{ opacity: 0 }} animate={{ opacity: 0.6 }} transition={{ delay: 0.8 }}>
          <motion.line x1="452" y1="135" x2="488" y2="188" stroke="#8b5cf6" strokeWidth="1" strokeDasharray="4 3"
            animate={{ strokeDashoffset: [0, -14] }}
            transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
          />
          <polygon points="486,184 492,189 486,193" fill="#8b5cf6" opacity="0.6" />
        </motion.g>

        {/* Command display */}
        <motion.g
          initial={{ opacity: 0, y: 5 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.9, ...SPRING_SMOOTH }}
        >
          <rect x="155" y="225" width="290" height="30" rx="6" fill="rgba(0,0,0,0.4)" />
          <rect x="155" y="225" width="290" height="30" rx="6" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="1" />
          <text x="168" y="244" fill="#22c55e" fontSize="8" fontFamily="monospace" opacity="0.6">$</text>
          <text x="178" y="244" fill="white" fontSize="8" fontFamily="monospace" opacity="0.7">ssh -L 5432:localhost:5432 ubuntu@vps</text>
        </motion.g>

        <StatusBadge connected={true} latencyMs={38} encrypted={true} />
      </svg>

      <div className="flex items-center justify-center gap-6 text-xs">
        <div className="flex items-center gap-1.5 text-amber-400">
          <div className="h-2 w-2 rounded-full bg-amber-400" />
          Local port (your machine)
        </div>
        <div className="flex items-center gap-1.5 text-violet-400">
          <div className="h-2 w-2 rounded-full bg-violet-400" />
          Remote port (VPS service)
        </div>
      </div>
    </div>
  );
}

function ScenarioReconnect() {
  const [phase, setPhase] = useState(0); // 0=connected, 1=dropping, 2=broken, 3=reconnecting, 4=restored
  const [packets, setPackets] = useState<TunnelPacket[]>([]);
  const counterRef = useRef(0);
  const phaseRef = useRef(0);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const schedulePhases = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    const t1 = setTimeout(() => { setPhase(1); phaseRef.current = 1; }, 2000);
    const t2 = setTimeout(() => { setPhase(2); phaseRef.current = 2; setPackets([]); }, 3000);
    const t3 = setTimeout(() => { setPhase(3); phaseRef.current = 3; }, 5000);
    const t4 = setTimeout(() => { setPhase(4); phaseRef.current = 4; }, 6500);
    timersRef.current = [t1, t2, t3, t4];
  }, []);

  const replay = useCallback(() => {
    setPhase(0);
    setPackets([]);
    counterRef.current = 0;
    phaseRef.current = 0;
    schedulePhases();
  }, [schedulePhases]);

  useEffect(() => {
    schedulePhases();
    return () => { timersRef.current.forEach(clearTimeout); };
  }, [schedulePhases]);

  useEffect(() => {
    const moveInterval = setInterval(() => {
      setPackets((prev) =>
        prev.map((p) => ({ ...p, progress: p.progress + 0.018 })).filter((p) => p.progress <= 1)
      );
    }, 32);

    const spawnInterval = setInterval(() => {
      const p = phaseRef.current;
      if (p === 1 || p === 2 || p === 3) return;
      counterRef.current += 1;
      const id = counterRef.current;
      const isOut = id % 2 !== 0;
      const cmds = ["vim app", "npm run", "git push", "make", "tail -f"];
      const encs = ["x9#kQ!", "aZ&2mP", "!Rv8$f", "qW3@nL", "7b*Yj#"];
      const idx = id % cmds.length;
      setPackets((prev) => [
        ...prev,
        { id, progress: 0, direction: isOut ? "outgoing" : "incoming", label: cmds[idx], encryptedLabel: encs[idx], color: isOut ? "#22c55e" : "#06b6d4" },
      ]);
    }, 1800);

    return () => { clearInterval(moveInterval); clearInterval(spawnInterval); };
  }, []);

  const connected = phase === 0 || phase === 4;
  const broken = phase === 2;

  const stageLabels = [
    { label: "Connected", color: "text-emerald-400", bg: "bg-emerald-400" },
    { label: "Signal lost...", color: "text-amber-400", bg: "bg-amber-400" },
    { label: "Disconnected", color: "text-red-400", bg: "bg-red-400" },
    { label: "Reconnecting...", color: "text-amber-400", bg: "bg-amber-400" },
    { label: "Restored!", color: "text-emerald-400", bg: "bg-emerald-400" },
  ];
  const current = stageLabels[phase];

  return (
    <div className="space-y-3">
      <svg viewBox="0 0 600 280" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <TunnelDefs encrypted={true} />
        <LaptopIcon x={20} y={85} />
        <CloudIcon x={300} y={56} />
        <ServerIcon x={500} y={82} blinking={connected} />

        <EncryptedTunnel
          encrypted={true}
          broken={broken || phase === 1}
          establishing={phase === 3}
        />

        {connected && <DataPackets packets={packets} encrypted={true} />}

        {/* Disconnect flash */}
        {phase === 2 && (
          <motion.g
            initial={{ opacity: 0 }}
            animate={{ opacity: [0, 1, 0] }}
            transition={{ duration: 0.5, repeat: 3 }}
          >
            <WifiOff x={288} y={118} className="text-red-500" width={24} height={24} strokeWidth={1.5} />
          </motion.g>
        )}

        {/* Reconnect spinner */}
        {phase === 3 && (
          <motion.g
            animate={{ rotate: [0, 360] }}
            transition={{ duration: 1.5, repeat: Infinity, ease: "linear" }}
            style={{ originX: "300px", originY: "130px" }}
          >
            <RefreshCw x={288} y={118} className="text-amber-400" width={24} height={24} strokeWidth={1.5} />
          </motion.g>
        )}

        {/* Tmux session preserved badge */}
        {(phase === 2 || phase === 3) && (
          <motion.g
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={SPRING_SMOOTH}
          >
            <rect x="195" y="172" width="210" height="30" rx="8" fill="#22c55e" opacity="0.06" />
            <rect x="195" y="172" width="210" height="30" rx="8" fill="none" stroke="#22c55e" strokeWidth="0.7" opacity="0.3" />
            <ShieldCheck x={205} y={178} className="text-emerald-400" width={16} height={16} strokeWidth={1.5} />
            <text x="230" y="192" fill="#22c55e" fontSize="9" fontWeight="600">
              tmux session preserved on VPS
            </text>
          </motion.g>
        )}

        {phase === 4 && (
          <motion.g
            initial={{ opacity: 0, scale: 0.6 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING_SMOOTH}
          >
            <rect x="220" y="172" width="160" height="26" rx="8" fill="#22c55e" opacity="0.08" />
            <rect x="220" y="172" width="160" height="26" rx="8" fill="none" stroke="#22c55e" strokeWidth="0.7" opacity="0.4" />
            <CheckCircle2 x={230} y={178} className="text-emerald-400" width={14} height={14} strokeWidth={1.5} />
            <text x="250" y="190" fill="#22c55e" fontSize="9" fontWeight="600">Session fully restored</text>
          </motion.g>
        )}

        <StatusBadge connected={connected} latencyMs={connected ? 45 : 0} encrypted={true} />
      </svg>

      {/* Phase indicator */}
      <div className="flex items-center justify-between px-2">
        <div className="flex items-center gap-1">
          {stageLabels.map((s, i) => (
            <div key={i} className="flex items-center gap-1">
              <motion.div
                className={`h-2 w-2 rounded-full ${i <= phase ? s.bg : "bg-white/20"}`}
                animate={{ scale: i === phase ? [1, 1.4, 1] : 1 }}
                transition={{ duration: 1, repeat: i === phase ? Infinity : 0 }}
              />
              {i < stageLabels.length - 1 && (
                <div className={`w-4 h-px ${i < phase ? "bg-white/20" : "bg-white/5"}`} />
              )}
            </div>
          ))}
        </div>
        <span className={`text-xs font-semibold ${current.color}`}>{current.label}</span>
      </div>

      <div className="flex justify-center">
        <button
          onClick={replay}
          className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.03] border border-white/[0.08] text-white/50 hover:border-white/[0.15] hover:text-white/70 transition duration-300"
        >
          <RefreshCw className="h-3 w-3" /> Replay
        </button>
      </div>
    </div>
  );
}

// --- Main Tunnel Component ---

function InteractiveSSHTunnel() {
  const [scenario, setScenario] = useState<TunnelScenario>("connect");
  const [showUnencrypted, setShowUnencrypted] = useState(false);

  // Unencrypted mode only applies to the connect scenario for the toggle demo
  const meta = SCENARIO_META[scenario];

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Scenario Tabs */}
      <div className="flex items-center gap-1 px-3 pt-4 pb-2 overflow-x-auto scrollbar-none">
        {(Object.keys(SCENARIO_META) as TunnelScenario[]).map((key) => {
          const s = SCENARIO_META[key];
          const active = scenario === key;
          return (
            <button
              key={key}
              onClick={() => { setScenario(key); setShowUnencrypted(false); }}
              className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition duration-300 border whitespace-nowrap ${
                active
                  ? "bg-emerald-500/15 border-emerald-500/40 text-emerald-400"
                  : "bg-white/[0.02] border-white/[0.06] text-white/40 hover:border-white/[0.12] hover:text-white/60"
              }`}
            >
              {s.icon}
              <span className="hidden sm:inline">{s.label}</span>
            </button>
          );
        })}

        {/* Encryption toggle (connect scenario only) */}
        {scenario === "connect" && (
          <button
            onClick={() => setShowUnencrypted((v) => !v)}
            className={`ml-auto flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition duration-300 border whitespace-nowrap ${
              showUnencrypted
                ? "bg-red-500/15 border-red-500/40 text-red-400"
                : "bg-white/[0.02] border-white/[0.06] text-white/40 hover:border-white/[0.12] hover:text-white/60"
            }`}
          >
            {showUnencrypted ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
            <span className="hidden sm:inline">{showUnencrypted ? "Unencrypted" : "Encrypted"}</span>
          </button>
        )}
      </div>

      {/* Scenario description */}
      <div className="px-4 pb-2">
        <p className="text-xs text-white/40">{meta.description}</p>
      </div>

      {/* Unencrypted warning */}
      <AnimatePresence>
        {showUnencrypted && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.3 }}
            className="mx-4 mb-2 overflow-hidden"
          >
            <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/30">
              <ShieldAlert className="h-4 w-4 text-red-400 shrink-0" />
              <span className="text-xs text-red-400">
                Without encryption, data travels as plaintext -- anyone on the network can read it!
              </span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Scenario Content */}
      <div className="px-2 sm:px-4 pb-4">
        <AnimatePresence mode="wait">
          <motion.div
            key={scenario + (showUnencrypted ? "-unenc" : "")}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.25 }}
          >
            {scenario === "connect" && !showUnencrypted && <ScenarioConnect />}
            {scenario === "connect" && showUnencrypted && <ScenarioConnectUnencrypted />}
            {scenario === "keyauth" && <ScenarioKeyAuth />}
            {scenario === "portforward" && <ScenarioPortForward />}
            {scenario === "reconnect" && <ScenarioReconnect />}
          </motion.div>
        </AnimatePresence>
      </div>

      {/* Terminal command display */}
      <div className="mx-4 mb-4">
        <div className="rounded-lg bg-black/40 border border-white/[0.06] px-4 py-3 font-mono text-xs overflow-x-auto">
          <span className="text-emerald-400/70">$</span>{" "}
          <span className="text-white/70">
            {scenario === "connect" && "ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_VPS_IP"}
            {scenario === "keyauth" && "ssh-keygen -t ed25519 -f ~/.ssh/acfs_ed25519"}
            {scenario === "portforward" && "ssh -L 5432:localhost:5432 ubuntu@YOUR_VPS_IP"}
            {scenario === "reconnect" && "mosh ubuntu@YOUR_VPS_IP -- tmux attach"}
          </span>
          <motion.span
            className="inline-block w-1.5 h-3.5 bg-emerald-400/80 ml-1 align-middle"
            animate={{ opacity: [1, 0, 1] }}
            transition={{ duration: 1.2, repeat: Infinity }}
          />
        </div>
      </div>
    </div>
  );
}

/** Unencrypted variant of the connect scenario -- shows readable packets with red warnings */
function ScenarioConnectUnencrypted() {
  const [packets, setPackets] = useState<TunnelPacket[]>([]);
  const counterRef = useRef(0);

  useEffect(() => {
    const moveInterval = setInterval(() => {
      setPackets((prev) =>
        prev.map((p) => ({ ...p, progress: p.progress + 0.018 })).filter((p) => p.progress <= 1)
      );
    }, 32);

    const spawnInterval = setInterval(() => {
      counterRef.current += 1;
      const id = counterRef.current;
      const isOut = id % 2 !== 0;
      const cmds = ["password", "ls -la", "secret", "cat .env", "token=X"];
      const idx = id % cmds.length;
      setPackets((prev) => [
        ...prev,
        { id, progress: 0, direction: isOut ? "outgoing" : "incoming", label: cmds[idx], encryptedLabel: cmds[idx], color: "#ef4444" },
      ]);
    }, 1600);

    return () => { clearInterval(moveInterval); clearInterval(spawnInterval); };
  }, []);

  return (
    <div className="space-y-3">
      <svg viewBox="0 0 600 260" className="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <TunnelDefs encrypted={false} />
        <LaptopIcon x={20} y={85} />
        <CloudIcon x={300} y={56} />
        <ServerIcon x={500} y={82} />
        <EncryptedTunnel encrypted={false} />
        <DataPackets packets={packets} encrypted={false} />

        {/* Eavesdropper icon */}
        <motion.g
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, ...SPRING_SMOOTH }}
        >
          <motion.g animate={{ opacity: [0.4, 0.8, 0.4] }} transition={{ duration: 2, repeat: Infinity }}>
            <Eye x={288} y={72} className="text-red-400" width={24} height={20} strokeWidth={1.5} />
            <text x="300" y="100" textAnchor="middle" fill="#ef4444" fontSize="7.5" fontWeight="600">EAVESDROPPER</text>
          </motion.g>
          {/* Line from eye to tunnel */}
          <motion.line x1="300" y1="100" x2="300" y2="110" stroke="#ef4444" strokeWidth="0.8" strokeDasharray="3 2"
            animate={{ strokeDashoffset: [0, -10] }}
            transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
          />
        </motion.g>

        <StatusBadge connected={true} latencyMs={42} encrypted={false} />
      </svg>
    </div>
  );
}

// =============================================================================
// STAGE CARD - Login stage display
// =============================================================================
function StageCard({
  number,
  title,
  subtitle,
  description,
  code,
  gradient,
}: {
  number: number;
  title: string;
  subtitle: string;
  description: string;
  code: string;
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      transition={{ delay: 0.2 + number * 0.1 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl overflow-hidden transition duration-300 hover:border-white/[0.15] hover:shadow-lg hover:shadow-primary/10`}
    >
      <div className="relative">
        <div className="flex items-center gap-3 mb-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/10 text-white text-sm font-bold group-hover:bg-white/20 group-hover:scale-110 transition duration-300">
            {number}
          </div>
          <div>
            <h4 className="font-bold text-white group-hover:text-primary transition-colors">{title}</h4>
            <span className="text-xs text-white/50 group-hover:text-white/70 transition-colors">{subtitle}</span>
          </div>
        </div>
        <p className="text-sm text-white/60 mb-4 group-hover:text-white/70 transition-colors">{description}</p>
        <code className="block px-3 py-2 rounded-lg bg-black/30 border border-white/[0.06] text-xs font-mono text-white/80 overflow-x-auto group-hover:border-primary/20 group-hover:bg-black/40 transition duration-300">
          {code}
        </code>
      </div>
    </motion.div>
  );
}

// =============================================================================
// COMMAND PART - Breakdown of command components
// =============================================================================
function CommandPart({
  label,
  description,
}: {
  label: string;
  description: string;
}) {
  return (
    <motion.div
      whileHover={{ x: 4, scale: 1.02 }}
      className="group flex items-center gap-3 p-3 rounded-xl border border-white/[0.06] bg-white/[0.02] transition duration-300 hover:border-primary/30 hover:bg-white/[0.04]"
    >
      <code className="px-2 py-1 rounded bg-primary/10 border border-primary/20 text-xs font-mono text-primary group-hover:bg-primary/20 group-hover:border-primary/40 transition duration-300">
        {label}
      </code>
      <span className="text-sm text-white/50 group-hover:text-white/70 transition-colors">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// QUIZ CARDS - Interactive quiz display
// =============================================================================
function QuizCards() {
  const questions = [
    {
      question: "Where does your private key live?",
      answer: "~/.ssh/acfs_ed25519 on your laptop",
    },
    {
      question: "What happens if SSH drops?",
      answer: "Reconnect; tmux saves your work",
    },
    {
      question: "What's the quick way to reconnect?",
      answer: "Use an alias",
    },
  ];

  return (
    <div className="space-y-4">
      {questions.map((q, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          whileHover={{ x: 4, scale: 1.01 }}
          transition={{ delay: i * 0.1 }}
          className="group relative rounded-xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl transition duration-300 hover:border-primary/30 hover:bg-white/[0.04] hover:shadow-lg hover:shadow-primary/10"
        >
          <div className="flex items-start gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary text-sm font-bold group-hover:bg-primary/20 group-hover:scale-110 transition duration-300">
              {i + 1}
            </div>
            <div className="flex-1">
              <p className="font-medium text-white group-hover:text-primary transition-colors">{q.question}</p>
              <p className="mt-2 text-sm text-white/50 group-hover:text-white/70 transition-colors">{q.answer}</p>
            </div>
          </div>
        </motion.div>
      ))}
    </div>
  );
}
