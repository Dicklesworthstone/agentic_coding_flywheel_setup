"use client";

import { motion } from "@/components/motion";
import {
  Key,
  Lock,
  Wifi,
  Shield,
  RefreshCw,
  Terminal,
  CheckCircle2,
  HelpCircle,
  Laptop,
  Server,
  ArrowRight,
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
          <ConnectionDiagram />
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
// CONNECTION DIAGRAM - Visual SSH connection
// =============================================================================
function ConnectionDiagram() {
  return (
    <div className="relative p-6 rounded-2xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl">
      <div className="flex flex-col md:flex-row items-center justify-center gap-4 md:gap-8">
        {/* Laptop */}
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.2 }}
          className="flex flex-col items-center gap-3"
        >
          <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-sky-500/20 to-blue-500/20 border border-sky-500/30">
            <Laptop className="h-8 w-8 text-sky-400" />
          </div>
          <span className="text-sm font-medium text-white">Your Laptop</span>
        </motion.div>

        {/* Encrypted Tunnel */}
        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.4 }}
          className="flex items-center gap-2"
        >
          <div className="hidden md:block h-px w-12 bg-gradient-to-r from-sky-500/50 to-emerald-500/50" />
          <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-gradient-to-r from-primary/10 to-violet-500/10 border border-primary/30">
            <Lock className="h-4 w-4 text-primary" />
            <span className="text-xs font-medium text-white/70">
              Encrypted SSH
            </span>
          </div>
          <ArrowRight className="h-5 w-5 text-emerald-400" />
          <div className="hidden md:block h-px w-12 bg-gradient-to-r from-emerald-500/50 to-emerald-500/20" />
        </motion.div>

        {/* Server */}
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.6 }}
          className="flex flex-col items-center gap-3"
        >
          <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500/20 to-teal-500/20 border border-emerald-500/30">
            <Server className="h-8 w-8 text-emerald-400" />
          </div>
          <span className="text-sm font-medium text-white">Your VPS</span>
        </motion.div>
      </div>
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
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15] hover:shadow-lg hover:shadow-primary/10`}
    >
      <div className="relative">
        <div className="flex items-center gap-3 mb-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/10 text-white text-sm font-bold group-hover:bg-white/20 group-hover:scale-110 transition-all duration-300">
            {number}
          </div>
          <div>
            <h4 className="font-bold text-white group-hover:text-primary transition-colors">{title}</h4>
            <span className="text-xs text-white/50 group-hover:text-white/70 transition-colors">{subtitle}</span>
          </div>
        </div>
        <p className="text-sm text-white/60 mb-4 group-hover:text-white/70 transition-colors">{description}</p>
        <code className="block px-3 py-2 rounded-lg bg-black/30 border border-white/[0.06] text-xs font-mono text-white/80 overflow-x-auto group-hover:border-primary/20 group-hover:bg-black/40 transition-all duration-300">
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
      className="group flex items-center gap-3 p-3 rounded-xl border border-white/[0.06] bg-white/[0.02] transition-all duration-300 hover:border-primary/30 hover:bg-white/[0.04]"
    >
      <code className="px-2 py-1 rounded bg-primary/10 border border-primary/20 text-xs font-mono text-primary group-hover:bg-primary/20 group-hover:border-primary/40 transition-all duration-300">
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
          className="group relative rounded-xl border border-white/[0.08] bg-white/[0.02] p-5 backdrop-blur-xl transition-all duration-300 hover:border-primary/30 hover:bg-white/[0.04] hover:shadow-lg hover:shadow-primary/10"
        >
          <div className="flex items-start gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary text-sm font-bold group-hover:bg-primary/20 group-hover:scale-110 transition-all duration-300">
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
