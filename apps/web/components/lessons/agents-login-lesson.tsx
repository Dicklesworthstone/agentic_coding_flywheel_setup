"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence, springs } from "@/components/motion";
import {
  Bot,
  Key,
  Zap,
  Terminal,
  CheckCircle2,
  AlertTriangle,
  Database,
  Sparkles,
  Play,
  Pause,
  SkipBack,
  SkipForward,
  Shield,
  XCircle,
  Server,
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
  BulletList,
} from "./lesson-components";

export function AgentsLoginLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Login to your coding agents and understand the shortcuts.
      </GoalBanner>

      {/* The Three Agents */}
      <Section
        title="The Three Agents"
        icon={<Bot className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          You have three powerful coding agents installed, each from a different
          AI company:
        </Paragraph>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <AgentInfoCard
            name="Claude Code"
            command="claude"
            alias="cc"
            company="Anthropic"
            gradient="from-orange-500 to-amber-500"
            delay={0.1}
          />
          <AgentInfoCard
            name="Codex CLI"
            command="codex"
            alias="cod"
            company="OpenAI"
            gradient="from-emerald-500 to-teal-500"
            delay={0.2}
          />
          <AgentInfoCard
            name="Antigravity CLI"
            command="agy"
            alias="agy"
            company="Google"
            gradient="from-blue-500 to-purple-500"
            delay={0.3}
          />
        </div>

        <Paragraph>
          The Antigravity CLI (<Highlight>agy</Highlight>) is pinned to Gemini
          3.1 Pro (High). It replaced the Gemini CLI (<Highlight>gmi</Highlight>),
          which retired 2026-06-18 — <Highlight>gmi</Highlight> still works for
          reading old <Highlight>~/.gemini/tmp</Highlight> history, but use{" "}
          <Highlight>agy</Highlight> for all new work.
        </Paragraph>

        <div className="mt-8">
          <InteractiveAgentComparison />
        </div>
      </Section>

      <Divider />

      {/* What The Aliases Do */}
      <Section
        title="What The Aliases Do"
        icon={<Zap className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          The aliases are configured for <Highlight>maximum power</Highlight>{" "}
          (vibe mode):
        </Paragraph>

        <div className="mt-8 space-y-6">
          <AliasCard
            alias="cc"
            name="Claude Code"
            code={`NODE_OPTIONS="--max-old-space-size=32768" \\
  claude --dangerously-skip-permissions`}
            features={[
              "Extra memory for large projects",
              "Background tasks enabled by default",
              "No permission prompts",
            ]}
            gradient="from-orange-500/20 to-amber-500/20"
          />

          <AliasCard
            alias="cod"
            name="Codex CLI"
            code="codex --dangerously-bypass-approvals-and-sandbox"
            features={[
              "Bypass safety prompts",
              "No approval/sandbox checks",
            ]}
            gradient="from-emerald-500/20 to-teal-500/20"
          />

          <AliasCard
            alias="agy"
            name="Antigravity CLI"
            code={`agy --model "Gemini 3.1 Pro (High)" \\
  --dangerously-skip-permissions`}
            features={[
              'Model pinned to "Gemini 3.1 Pro (High)"',
              "Auto-approves tool permissions (no confirmations)",
              "Successor to the retired Gemini CLI",
            ]}
            gradient="from-blue-500/20 to-purple-500/20"
          />
        </div>

        <Paragraph>
          Legacy: <Highlight>gmi</Highlight> is still defined, but it now launches
          the same locked Antigravity path as <Highlight>agy</Highlight>. The
          Gemini CLI retired 2026-06-18, so use <Highlight>agy</Highlight> for
          new work and treat old Gemini references as history/context only.
        </Paragraph>
      </Section>

      <Divider />

      {/* First Login */}
      <Section
        title="First Login"
        icon={<Key className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>Each agent needs to be authenticated once:</Paragraph>

        <div className="mt-8 space-y-6">
          {/* Claude Login */}
          <LoginStep
            agent="Claude Code"
            command="claude auth login"
            description="Follow the browser link to authenticate with your Anthropic account."
            gradient="from-orange-500/10 to-amber-500/10"
          />

          {/* Codex Login */}
          <CodexLoginSection />

          {/* OpenAI Warning */}
          <OpenAIAccountWarning />

          {/* Antigravity Login */}
          <LoginStep
            agent="Antigravity CLI"
            command="agy"
            description="Run agy once and follow the prompts to authenticate with your Google account. The model is pinned to Gemini 3.1 Pro (High)."
            gradient="from-blue-500/10 to-purple-500/10"
          />

          {/* Gemini Login (legacy) */}
          <LoginStep
            agent="Gemini CLI (legacy)"
            command='export GEMINI_API_KEY="your-gemini-api-key"'
            description="Only for intentionally opening the retired gemini binary or old ~/.gemini/tmp material. The gmi shortcut now launches locked agy."
            gradient="from-blue-500/10 to-indigo-500/10"
          />
        </div>
      </Section>

      <Divider />

      {/* Backup Credentials */}
      <Section
        title="Backup Your Credentials!"
        icon={<Database className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          After logging in, <Highlight>immediately</Highlight> back up your
          credentials:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`caam backup claude my-main-account
caam backup codex my-main-account
caam backup agy my-main-account`}
          />
        </div>

        <Paragraph>Now you can switch accounts later with:</Paragraph>

        <div className="mt-6">
          <CodeBlock code="caam activate claude my-other-account" />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            This is incredibly useful when you hit rate limits! Switch to a
            backup account and keep working.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Test Your Agents */}
      <Section
        title="Test Your Agents"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>Try each one to verify they&apos;re working:</Paragraph>

        <div className="mt-6 space-y-4">
          <CodeBlock code={`cc "Hello! Please confirm you're working."`} />
          <CodeBlock code={`cod "Hello! Please confirm you're working."`} />
          <CodeBlock code={`agy "Hello! Please confirm you're working."`} />
        </div>
      </Section>

      <Divider />

      {/* Quick Tips */}
      <Section
        title="Quick Tips"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="mt-4">
          <BulletList
            items={[
              <span key="1">
                <strong>Start simple</strong> - Let agents do small tasks first
              </span>,
              <span key="2">
                <strong>Be specific</strong> - Clear instructions get better
                results
              </span>,
              <span key="3">
                <strong>Check the output</strong> - Agents can make mistakes
              </span>,
              <span key="4">
                <strong>Use multiple agents</strong> - Different agents have
                different strengths
              </span>,
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Practice */}
      <Section
        title="Practice This Now"
        icon={<CheckCircle2 className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>Let&apos;s verify your agents are ready:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check which agents are installed
$ which claude codex agy

# Check your agent credential backups
$ caam ls

# If you haven't logged in yet, start with Claude:
$ claude auth login`}
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            If you set up your accounts during the wizard (Step 7: Set Up
            Accounts), you already have the credentials ready—just run the login
            commands!
          </TipBox>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// AGENT INFO CARD - Display agent with gradient styling
// =============================================================================
function AgentInfoCard({
  name,
  command,
  alias,
  company,
  gradient,
  delay,
}: {
  name: string;
  command: string;
  alias: string;
  company: string;
  gradient: string;
  delay: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay }}
      whileHover={{ y: -4, scale: 1.02 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.15]"
    >
      {/* Gradient overlay on hover */}
      <div
        className={`absolute inset-0 bg-gradient-to-br ${gradient} opacity-0 group-hover:opacity-20 transition-opacity duration-500`}
      />

      <div className="relative flex flex-col items-center text-center">
        <div
          className={`flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br ${gradient} shadow-lg mb-4`}
        >
          <Bot className="h-7 w-7 text-white" />
        </div>
        <span className="font-bold text-white">{name}</span>
        <span className="text-xs text-white/60 mt-1">{company}</span>

        <div className="mt-4 flex flex-col gap-2 w-full">
          <code className="px-3 py-1.5 rounded-lg bg-black/40 border border-white/[0.08] text-xs font-mono text-white/70">
            {command}
          </code>
          {alias !== command && (
            <code className="px-3 py-1.5 rounded-lg bg-primary/10 border border-primary/20 text-xs font-mono text-primary">
              {alias}
            </code>
          )}
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// ALIAS CARD - Display alias configuration
// =============================================================================
function AliasCard({
  alias,
  name,
  code,
  features,
  gradient,
}: {
  alias: string;
  name: string;
  code: string;
  features: string[];
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15]`}
    >
      <div className="flex items-center gap-3 mb-4">
        <code className="px-3 py-1.5 rounded-lg bg-primary/20 border border-primary/30 text-lg font-mono font-bold text-primary">
          {alias}
        </code>
        <span className="text-white/60">({name})</span>
      </div>

      <div className="mb-4 rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden">
        <pre className="p-4 text-xs font-mono text-white/80 overflow-x-auto">
          {code}
        </pre>
      </div>

      <ul className="space-y-2">
        {features.map((feature, i) => (
          <li key={i} className="flex items-center gap-2 text-sm text-white/60">
            <CheckCircle2 className="h-4 w-4 text-emerald-400 shrink-0" />
            {feature}
          </li>
        ))}
      </ul>
    </motion.div>
  );
}

// =============================================================================
// LOGIN STEP - Display login command for each agent
// =============================================================================
function LoginStep({
  agent,
  command,
  description,
  gradient,
}: {
  agent: string;
  command: string;
  description: string;
  gradient: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className={`group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br ${gradient} p-6 backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]`}
    >
      <h4 className="font-bold text-white mb-3 group-hover:text-primary transition-colors">{agent}</h4>
      <div className="mb-3 rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden group-hover:bg-black/40 transition-colors">
        <pre className="p-3 text-sm font-mono text-emerald-400">
          <span className="text-white/50">$ </span>
          {command}
        </pre>
      </div>
      <p className="text-sm text-white/60 group-hover:text-white/80 transition-colors">{description}</p>
    </motion.div>
  );
}

// =============================================================================
// CODEX LOGIN SECTION - Headless VPS auth options
// =============================================================================
function CodexLoginSection() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-gradient-to-br from-emerald-500/10 to-teal-500/10 p-6 backdrop-blur-xl transition-all duration-300 hover:border-white/[0.15]"
    >
      <h4 className="font-bold text-white mb-3 group-hover:text-primary transition-colors">
        Codex CLI
      </h4>

      <p className="text-sm text-white/60 mb-4">
        <strong className="text-amber-400">On a headless VPS</strong>, Codex requires special handling because its OAuth callback expects{" "}
        <InlineCode>localhost:1455</InlineCode>.
      </p>

      {/* Option 1: Device Auth */}
      <div className="mb-4">
        <p className="text-xs font-semibold text-emerald-400 mb-2">
          Option 1: Device Auth (Recommended)
        </p>
        <ol className="list-decimal list-inside text-xs text-white/60 space-y-1 mb-2 pl-2">
          <li>
            Enable &quot;Device code login&quot; in{" "}
            <a
              href="https://chatgpt.com/settings/security"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary underline"
            >
              ChatGPT Settings → Security
            </a>
          </li>
          <li>Then run the command below</li>
        </ol>
        <div className="rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden">
          <pre className="p-3 text-sm font-mono text-emerald-400">
            <span className="text-white/50">$ </span>codex login --device-auth
          </pre>
        </div>
      </div>

      {/* Option 2: SSH Tunnel */}
      <div className="mb-4">
        <p className="text-xs font-semibold text-emerald-400 mb-2">
          Option 2: SSH Tunnel
        </p>
        <ol className="list-decimal list-inside text-xs text-white/60 space-y-1 mb-2 pl-2">
          <li>On your laptop, create a tunnel</li>
          <li>Then run <InlineCode>codex login</InlineCode> on the VPS through that tunneled SSH session</li>
        </ol>
        <div className="rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden">
          <pre className="p-3 text-xs font-mono text-emerald-400 overflow-x-auto">
            <span className="text-white/50"># On laptop:</span>{"\n"}
            <span className="text-white/50">$ </span>ssh -L 1455:localhost:1455 ubuntu@YOUR_VPS_IP{"\n"}
            <span className="text-white/50"># Then on VPS:</span>{"\n"}
            <span className="text-white/50">$ </span>codex login
          </pre>
        </div>
      </div>

      {/* Option 3: Standard */}
      <div>
        <p className="text-xs font-semibold text-white/60 mb-2">
          Option 3: Standard localhost callback (if you&apos;re not on a headless VPS)
        </p>
        <div className="rounded-xl bg-black/30 border border-white/[0.06] overflow-hidden">
          <pre className="p-3 text-sm font-mono text-emerald-400">
            <span className="text-white/50">$ </span>codex login
          </pre>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE AGENT COMPARISON - Clickable agent selector with detail cards
// =============================================================================

type AgentId = "claude" | "codex" | "antigravity";
const AGENT_KEYS: AgentId[] = ["claude", "codex", "antigravity"];
const AGENT_X_POSITION: Record<AgentId, number> = {
  claude: 17,
  codex: 50,
  antigravity: 83,
};
const AGENT_START_X: Record<AgentId, number> = {
  claude: 100,
  codex: 300,
  antigravity: 500,
};
const AGENT_LABELS: Record<AgentId, string> = {
  claude: "Claude Code",
  codex: "Codex CLI",
  antigravity: "Antigravity CLI",
};

function particleUnit(agentKey: AgentId, index: number, salt: number) {
  const agentOffset = AGENT_KEYS.indexOf(agentKey) + 1;
  const seed = agentOffset * 997 + index * 37 + salt * 101;
  return ((seed * 9301 + 49297) % 233280) / 233280;
}

// =============================================================================
// LIVE AGENT TERMINAL RACE - Interactive multi-scenario auth visualization
// =============================================================================

interface TerminalLine {
  text: string;
  type: "command" | "output" | "success" | "error" | "info" | "blank";
  delay: number; // ms from scenario start
}

interface ScenarioAgent {
  lines: TerminalLine[];
  result: "success" | "fail";
  finishDelay: number; // total ms to complete
}

interface Scenario {
  id: string;
  title: string;
  description: string;
  icon: React.ReactNode;
  agents: {
    claude: ScenarioAgent;
    codex: ScenarioAgent;
    antigravity: ScenarioAgent;
  };
}

const SCENARIOS: Scenario[] = [
  {
    id: "ssh-keygen",
    title: "SSH Key Generation",
    description: "Generate and register SSH keys for Git authentication",
    icon: <Key className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: '$ claude "Generate SSH key for GitHub"', type: "command", delay: 0 },
          { text: "Analyzing current SSH configuration...", type: "info", delay: 400 },
          { text: '$ ssh-keygen -t ed25519 -C "user@dev"', type: "command", delay: 900 },
          { text: "Generating public/private ed25519 key pair.", type: "output", delay: 1300 },
          { text: "Your identification has been saved.", type: "output", delay: 1700 },
          { text: "$ eval $(ssh-agent -s) && ssh-add ~/.ssh/id_ed25519", type: "command", delay: 2100 },
          { text: "Identity added: /home/user/.ssh/id_ed25519", type: "success", delay: 2600 },
          { text: "$ gh ssh-key add ~/.ssh/id_ed25519.pub", type: "command", delay: 3000 },
          { text: "SSH key added to GitHub account.", type: "success", delay: 3500 },
        ],
        result: "success",
        finishDelay: 3800,
      },
      codex: {
        lines: [
          { text: '$ codex "Set up SSH key for Git"', type: "command", delay: 0 },
          { text: "$ ssh-keygen -t rsa -b 4096", type: "command", delay: 300 },
          { text: "Generating public/private rsa key pair.", type: "output", delay: 700 },
          { text: "Your identification has been saved.", type: "output", delay: 1100 },
          { text: "$ cat ~/.ssh/id_rsa.pub", type: "command", delay: 1400 },
          { text: "ssh-rsa AAAB3NzaC1yc2EAAAA...", type: "output", delay: 1700 },
          { text: "Copy the above key to GitHub Settings.", type: "info", delay: 2000 },
          { text: "Manual step required: paste key in browser", type: "error", delay: 2300 },
        ],
        result: "fail",
        finishDelay: 2600,
      },
      antigravity: {
        lines: [
          { text: '$ agy "Create SSH keys for GitHub"', type: "command", delay: 0 },
          { text: "Let me explain SSH key cryptography...", type: "info", delay: 500 },
          { text: "Ed25519 uses Edwards-curve Digital Sig...", type: "info", delay: 1000 },
          { text: '$ ssh-keygen -t ed25519 -C "user@dev"', type: "command", delay: 1600 },
          { text: "Generating public/private ed25519 key pair.", type: "output", delay: 2000 },
          { text: "$ eval $(ssh-agent -s)", type: "command", delay: 2500 },
          { text: "Agent pid 12345", type: "output", delay: 2800 },
          { text: "$ ssh-add ~/.ssh/id_ed25519", type: "command", delay: 3200 },
          { text: "Identity added successfully.", type: "success", delay: 3600 },
          { text: "Now add to GitHub via Settings > SSH...", type: "info", delay: 4000 },
        ],
        result: "success",
        finishDelay: 4300,
      },
    },
  },
  {
    id: "api-auth",
    title: "API Key Authentication",
    description: "Configure API keys and validate credentials",
    icon: <Shield className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: '$ claude "Set up OpenAI API key"', type: "command", delay: 0 },
          { text: "Checking environment configuration...", type: "info", delay: 400 },
          { text: "$ echo 'export OPENAI_API_KEY=sk-...' >> ~/.bashrc", type: "command", delay: 800 },
          { text: "$ source ~/.bashrc", type: "command", delay: 1200 },
          { text: "Validating API key with test request...", type: "info", delay: 1600 },
          { text: '$ curl -s api.openai.com/v1/models -H "Auth..."', type: "command", delay: 2000 },
          { text: '{"data":[{"id":"gpt-4o"...}]}', type: "output", delay: 2500 },
          { text: "API key validated. 47 models accessible.", type: "success", delay: 2900 },
        ],
        result: "success",
        finishDelay: 3200,
      },
      codex: {
        lines: [
          { text: '$ codex "Configure my API keys"', type: "command", delay: 0 },
          { text: "$ export OPENAI_API_KEY=sk-...", type: "command", delay: 250 },
          { text: "$ python -c 'import openai; print(openai.Model.list())'", type: "command", delay: 600 },
          { text: '{"data": [{"id": "gpt-4o"...}]}', type: "output", delay: 1000 },
          { text: "API key is working. Done!", type: "success", delay: 1300 },
        ],
        result: "success",
        finishDelay: 1600,
      },
      antigravity: {
        lines: [
          { text: '$ agy "Help me set up API auth"', type: "command", delay: 0 },
          { text: "There are several auth approaches:", type: "info", delay: 500 },
          { text: "1. Environment variables (recommended)", type: "info", delay: 900 },
          { text: "2. Config files (~/.config/...)", type: "info", delay: 1200 },
          { text: "3. Secret managers (Vault, AWS SM)", type: "info", delay: 1500 },
          { text: "$ export OPENAI_API_KEY=sk-...", type: "command", delay: 2000 },
          { text: "$ echo $OPENAI_API_KEY | head -c 8", type: "command", delay: 2400 },
          { text: "sk-proj-... (key set successfully)", type: "success", delay: 2800 },
        ],
        result: "success",
        finishDelay: 3100,
      },
    },
  },
  {
    id: "oauth-flow",
    title: "OAuth Browser Flow",
    description: "Handle OAuth callbacks on a headless VPS",
    icon: <Server className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: "$ claude auth login", type: "command", delay: 0 },
          { text: "Opening browser for authentication...", type: "info", delay: 400 },
          { text: "Waiting for OAuth callback...", type: "info", delay: 800 },
          { text: "Visit: https://claude.ai/oauth/auth?...", type: "output", delay: 1200 },
          { text: "Callback received on localhost:7771", type: "output", delay: 2200 },
          { text: "Token exchange successful.", type: "success", delay: 2700 },
          { text: "Logged in as user@example.com", type: "success", delay: 3100 },
        ],
        result: "success",
        finishDelay: 3400,
      },
      codex: {
        lines: [
          { text: "$ codex login", type: "command", delay: 0 },
          { text: "Opening browser for ChatGPT auth...", type: "info", delay: 300 },
          { text: "Callback URL: http://localhost:1455", type: "output", delay: 700 },
          { text: "Error: Connection refused on :1455", type: "error", delay: 1800 },
          { text: "Headless VPS has no browser!", type: "error", delay: 2200 },
          { text: "Hint: Use --device-auth or SSH tunnel", type: "info", delay: 2600 },
          { text: "$ codex login --device-auth", type: "command", delay: 3000 },
          { text: "Visit: https://chatgpt.com/device?code=ABCD-1234", type: "output", delay: 3400 },
          { text: "Device authorized. Logged in!", type: "success", delay: 4400 },
        ],
        result: "success",
        finishDelay: 4700,
      },
      antigravity: {
        lines: [
          { text: "$ agy", type: "command", delay: 0 },
          { text: "Opening browser for Google sign-in...", type: "info", delay: 500 },
          { text: "Visit: https://accounts.google.com/o/oauth2/...", type: "output", delay: 900 },
          { text: "Welcome to Antigravity CLI!", type: "info", delay: 1300 },
          { text: "Model pinned: Gemini 3.1 Pro (High)", type: "success", delay: 1800 },
          { text: "Ready to chat as user@gmail.com", type: "success", delay: 2400 },
        ],
        result: "success",
        finishDelay: 2800,
      },
    },
  },
  {
    id: "token-rotation",
    title: "Token Rotation (caam)",
    description: "Backup and rotate agent credentials with caam",
    icon: <Database className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: "$ caam backup claude main-acct", type: "command", delay: 0 },
          { text: "Backing up Claude credentials...", type: "info", delay: 400 },
          { text: "Credentials saved to ~/.caam/claude/main-acct", type: "success", delay: 900 },
          { text: "$ caam ls", type: "command", delay: 1300 },
          { text: "claude: main-acct (active)", type: "output", delay: 1600 },
          { text: "$ caam activate claude backup-acct", type: "command", delay: 2000 },
          { text: "Switched Claude to backup-acct", type: "success", delay: 2500 },
          { text: "Rate-limit bypassed! Ready to work.", type: "success", delay: 2900 },
        ],
        result: "success",
        finishDelay: 3200,
      },
      codex: {
        lines: [
          { text: "$ caam backup codex main-acct", type: "command", delay: 0 },
          { text: "Backing up Codex credentials...", type: "info", delay: 350 },
          { text: "Credentials saved to ~/.caam/codex/main-acct", type: "success", delay: 800 },
          { text: "$ caam activate codex alt-team-acct", type: "command", delay: 1200 },
          { text: "Switched Codex to alt-team-acct", type: "success", delay: 1700 },
          { text: "Ready with new credentials!", type: "success", delay: 2100 },
        ],
        result: "success",
        finishDelay: 2400,
      },
      antigravity: {
        lines: [
          { text: "$ caam backup agy main-acct", type: "command", delay: 0 },
          { text: "Backing up Antigravity credentials...", type: "info", delay: 400 },
          { text: "Credentials saved to ~/.caam/agy/main-acct", type: "success", delay: 900 },
          { text: "$ caam activate agy work-acct", type: "command", delay: 1300 },
          { text: "Switched Antigravity to work-acct", type: "success", delay: 1800 },
        ],
        result: "success",
        finishDelay: 2100,
      },
    },
  },
  {
    id: "rate-limit",
    title: "Rate Limit Recovery",
    description: "Handle rate limiting by switching agent accounts",
    icon: <AlertTriangle className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: '$ cc "Refactor the auth module"', type: "command", delay: 0 },
          { text: "Error 429: Rate limit exceeded", type: "error", delay: 600 },
          { text: "Retry after: 3600 seconds", type: "error", delay: 1000 },
          { text: "$ caam activate claude backup-acct", type: "command", delay: 1500 },
          { text: "Switched to backup-acct", type: "success", delay: 2000 },
          { text: '$ cc "Refactor the auth module"', type: "command", delay: 2400 },
          { text: "Analyzing auth module structure...", type: "info", delay: 2900 },
          { text: "Refactoring complete! 12 files updated.", type: "success", delay: 3800 },
        ],
        result: "success",
        finishDelay: 4100,
      },
      codex: {
        lines: [
          { text: '$ cod "Fix the login bug"', type: "command", delay: 0 },
          { text: "Error: Rate limit hit (429)", type: "error", delay: 500 },
          { text: "No backup accounts configured!", type: "error", delay: 900 },
          { text: "$ caam ls", type: "command", delay: 1300 },
          { text: "codex: main-acct (active) - no backups", type: "error", delay: 1700 },
          { text: "Must wait 1 hour or add backup account.", type: "error", delay: 2100 },
        ],
        result: "fail",
        finishDelay: 2400,
      },
      antigravity: {
        lines: [
          { text: '$ agy "Update the documentation"', type: "command", delay: 0 },
          { text: "Processing request...", type: "info", delay: 400 },
          { text: "Error: Quota exceeded for gemini-pro", type: "error", delay: 1000 },
          { text: "$ caam activate agy work-acct", type: "command", delay: 1500 },
          { text: "Switched to work-acct", type: "success", delay: 2000 },
          { text: '$ agy "Update the documentation"', type: "command", delay: 2400 },
          { text: "Documentation updated across 8 files.", type: "success", delay: 3400 },
        ],
        result: "success",
        finishDelay: 3700,
      },
    },
  },
  {
    id: "multi-agent",
    title: "Multi-Agent Workflow",
    description: "Use all three agents on different parts of a project",
    icon: <Sparkles className="h-4 w-4" />,
    agents: {
      claude: {
        lines: [
          { text: '$ cc "Architect the new payment module"', type: "command", delay: 0 },
          { text: "Planning module structure...", type: "info", delay: 500 },
          { text: "Created: src/payments/types.ts", type: "output", delay: 1200 },
          { text: "Created: src/payments/processor.ts", type: "output", delay: 1800 },
          { text: "Created: src/payments/validator.ts", type: "output", delay: 2400 },
          { text: "Created: src/payments/index.ts", type: "output", delay: 2800 },
          { text: "Architecture complete: 4 files, 380 lines", type: "success", delay: 3400 },
        ],
        result: "success",
        finishDelay: 3700,
      },
      codex: {
        lines: [
          { text: '$ cod "Write tests for payments module"', type: "command", delay: 0 },
          { text: "Scanning payment module exports...", type: "info", delay: 300 },
          { text: "$ touch src/payments/__tests__/processor.test.ts", type: "command", delay: 600 },
          { text: "Writing 24 test cases...", type: "info", delay: 1000 },
          { text: "$ bun test src/payments/", type: "command", delay: 1800 },
          { text: "24 passed, 0 failed (1.2s)", type: "success", delay: 2400 },
        ],
        result: "success",
        finishDelay: 2700,
      },
      antigravity: {
        lines: [
          { text: '$ agy "Document the payments module"', type: "command", delay: 0 },
          { text: "Analyzing module public API...", type: "info", delay: 500 },
          { text: "Generating JSDoc annotations...", type: "info", delay: 1100 },
          { text: "Created: docs/payments-guide.md", type: "output", delay: 1800 },
          { text: "Updated: README.md with API section", type: "output", delay: 2400 },
          { text: "Added: inline docs to all exports", type: "output", delay: 3000 },
          { text: "Documentation complete! Coverage: 100%", type: "success", delay: 3600 },
        ],
        result: "success",
        finishDelay: 3900,
      },
    },
  },
];

const AGENT_COLORS = {
  claude: {
    text: "text-orange-400",
    bg: "bg-orange-500",
    bgFaint: "bg-orange-500/10",
    border: "border-orange-500/30",
    glow: "shadow-orange-500/20",
    hex: "#f97316",
  },
  codex: {
    text: "text-emerald-400",
    bg: "bg-emerald-500",
    bgFaint: "bg-emerald-500/10",
    border: "border-emerald-500/30",
    glow: "shadow-emerald-500/20",
    hex: "#10b981",
  },
  antigravity: {
    text: "text-blue-400",
    bg: "bg-blue-500",
    bgFaint: "bg-blue-500/10",
    border: "border-blue-500/30",
    glow: "shadow-blue-500/20",
    hex: "#3b82f6",
  },
} as const;

// Particle type for auth success effect
interface Particle {
  id: number;
  x: number;
  y: number;
  angle: number;
  speed: number;
  life: number;
  color: string;
}

function InteractiveAgentComparison() {
  const [scenarioIndex, setScenarioIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [visibleLines, setVisibleLines] = useState<Record<AgentId, number>>({
    claude: 0,
    codex: 0,
    antigravity: 0,
  });
  const [agentDone, setAgentDone] = useState<Record<AgentId, boolean>>({
    claude: false,
    codex: false,
    antigravity: false,
  });
  const [particles, setParticles] = useState<Particle[]>([]);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const particleIdRef = useRef(0);
  const containerRef = useRef<HTMLDivElement>(null);

  const scenario = SCENARIOS[scenarioIndex];

  const clearTimers = useCallback(() => {
    for (const t of timersRef.current) clearTimeout(t);
    timersRef.current = [];
  }, []);

  const resetState = useCallback(() => {
    clearTimers();
    setVisibleLines({ claude: 0, codex: 0, antigravity: 0 });
    setAgentDone({ claude: false, codex: false, antigravity: false });
    setParticles([]);
    setIsPlaying(false);
  }, [clearTimers]);

  const spawnParticles = useCallback((agentKey: AgentId) => {
    const count = 8;
    const newParticles: Particle[] = [];
    const color = AGENT_COLORS[agentKey].hex;
    for (let i = 0; i < count; i++) {
      particleIdRef.current += 1;
      newParticles.push({
        id: particleIdRef.current,
        x: AGENT_X_POSITION[agentKey],
        y: 50,
        angle:
          (Math.PI * 2 * i) / count + particleUnit(agentKey, i, 1) * 0.5,
        speed: 2 + particleUnit(agentKey, i, 2) * 3,
        life: 1,
        color,
      });
    }
    setParticles((prev) => [...prev, ...newParticles]);
    // Decay particles
    const decayTimer = setTimeout(() => {
      setParticles((prev) =>
        prev.filter((p) => !newParticles.some((np) => np.id === p.id))
      );
    }, 1200);
    timersRef.current.push(decayTimer);
  }, []);

  const playScenario = useCallback(
    (sc: Scenario) => {
      clearTimers();
      setVisibleLines({ claude: 0, codex: 0, antigravity: 0 });
      setAgentDone({ claude: false, codex: false, antigravity: false });
      setParticles([]);
      setIsPlaying(true);

      const agentKeys = AGENT_KEYS;

      for (const agentKey of agentKeys) {
        const agentScenario = sc.agents[agentKey];
        for (let i = 0; i < agentScenario.lines.length; i++) {
          const line = agentScenario.lines[i];
          const timer = setTimeout(() => {
            setVisibleLines((prev) => ({
              ...prev,
              [agentKey]: i + 1,
            }));
          }, line.delay + 300);
          timersRef.current.push(timer);
        }

        // Mark done
        const doneTimer = setTimeout(() => {
          setAgentDone((prev) => ({ ...prev, [agentKey]: true }));
          if (agentScenario.result === "success") {
            spawnParticles(agentKey);
          }
        }, agentScenario.finishDelay + 300);
        timersRef.current.push(doneTimer);
      }

      // Auto-stop playing after longest agent finishes
      const maxDelay = Math.max(
        ...agentKeys.map((k) => sc.agents[k].finishDelay)
      );
      const stopTimer = setTimeout(() => {
        setIsPlaying(false);
      }, maxDelay + 800);
      timersRef.current.push(stopTimer);
    },
    [clearTimers, spawnParticles]
  );

  const handlePlay = useCallback(() => {
    if (isPlaying) {
      resetState();
    } else {
      playScenario(scenario);
    }
  }, [isPlaying, resetState, playScenario, scenario]);

  const handlePrev = useCallback(() => {
    resetState();
    setScenarioIndex((prev) => (prev > 0 ? prev - 1 : SCENARIOS.length - 1));
  }, [resetState]);

  const handleNext = useCallback(() => {
    resetState();
    setScenarioIndex((prev) => (prev < SCENARIOS.length - 1 ? prev + 1 : 0));
  }, [resetState]);

  // Clean up timers on unmount
  useEffect(() => {
    return () => {
      for (const t of timersRef.current) clearTimeout(t);
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden"
    >
      {/* Header */}
      <div className="px-6 pt-6 pb-4">
        <div className="flex items-center gap-3 mb-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
            <Terminal className="h-4 w-4 text-primary" />
          </div>
          <h3 className="text-lg font-bold text-white">
            Agent Authentication Race
          </h3>
        </div>
        <p className="text-sm text-white/50">
          Watch how each agent handles real authentication scenarios
        </p>
      </div>

      {/* Scenario stepper */}
      <div className="px-6 pb-4">
        <div className="flex items-center gap-2 mb-3">
          {SCENARIOS.map((sc, i) => (
            <motion.button
              key={sc.id}
              onClick={() => {
                resetState();
                setScenarioIndex(i);
              }}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              transition={springs.snappy}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                i === scenarioIndex
                  ? "bg-primary/20 border border-primary/30 text-primary"
                  : "border border-white/[0.08] bg-white/[0.02] text-white/40 hover:text-white/60"
              }`}
            >
              {sc.icon}
              <span className="hidden sm:inline">{sc.title}</span>
              <span className="sm:hidden">{i + 1}</span>
            </motion.button>
          ))}
        </div>

        {/* Scenario info + controls */}
        <div className="flex items-center justify-between">
          <div>
            <AnimatePresence mode="wait">
              <motion.div
                key={scenario.id}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 10 }}
                transition={springs.snappy}
              >
                <h4 className="text-sm font-semibold text-white">
                  {scenario.title}
                </h4>
                <p className="text-xs text-white/40">{scenario.description}</p>
              </motion.div>
            </AnimatePresence>
          </div>

          {/* Playback controls */}
          <div className="flex items-center gap-2">
            <motion.button
              onClick={handlePrev}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={springs.snappy}
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
            >
              <SkipBack className="h-3.5 w-3.5" />
            </motion.button>
            <motion.button
              onClick={handlePlay}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={springs.snappy}
              className={`flex h-10 w-10 items-center justify-center rounded-xl border transition-colors ${
                isPlaying
                  ? "border-amber-500/30 bg-amber-500/20 text-amber-400"
                  : "border-primary/30 bg-primary/20 text-primary"
              }`}
            >
              {isPlaying ? (
                <Pause className="h-4 w-4" />
              ) : (
                <Play className="h-4 w-4 ml-0.5" />
              )}
            </motion.button>
            <motion.button
              onClick={handleNext}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              transition={springs.snappy}
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
            >
              <SkipForward className="h-3.5 w-3.5" />
            </motion.button>
          </div>
        </div>
      </div>

      {/* SVG connection visualization */}
      <div className="relative px-6 pb-2">
        <svg
          viewBox="0 0 600 80"
          className="w-full h-auto"
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Central auth server */}
          <rect
            x="262"
            y="8"
            width="76"
            height="32"
            rx="8"
            className="fill-white/[0.04] stroke-white/[0.12]"
            strokeWidth="1"
          />
          <text
            x="300"
            y="22"
            textAnchor="middle"
            className="fill-white/60 text-[8px] font-bold"
          >
            AUTH
          </text>
          <text
            x="300"
            y="33"
            textAnchor="middle"
            className="fill-white/40 text-[7px]"
          >
            SERVER
          </text>

          {/* Connection lines with animation */}
          {AGENT_KEYS.map((agentKey) => {
            const startX = AGENT_START_X[agentKey];
            const isDone = agentDone[agentKey];
            const isSuccess =
              isDone && scenario.agents[agentKey].result === "success";
            const isFail =
              isDone && scenario.agents[agentKey].result === "fail";
            let color = "rgba(255,255,255,0.08)";
            if (isSuccess) {
              color = AGENT_COLORS[agentKey].hex;
            } else if (isFail) {
              color = "#ef4444";
            }

            return (
              <g key={agentKey}>
                {/* Line from agent to server */}
                <line
                  x1={startX}
                  y1={68}
                  x2={300}
                  y2={40}
                  stroke={color}
                  strokeWidth={isDone ? 2 : 1}
                  strokeDasharray={isDone ? "none" : "4 4"}
                  opacity={isDone ? 0.8 : 0.3}
                >
                  {isPlaying && !isDone && (
                    <animate
                      attributeName="stroke-dashoffset"
                      from="8"
                      to="0"
                      dur="0.6s"
                      repeatCount="indefinite"
                    />
                  )}
                </line>

                {/* Data flow pulse dot */}
                {isPlaying && !isDone && (
                  <circle r="3" fill={AGENT_COLORS[agentKey].hex} opacity="0.6">
                    <animateMotion
                      dur="1.5s"
                      repeatCount="indefinite"
                      path={`M${startX},68 L300,40`}
                    />
                  </circle>
                )}

                {/* Success/fail indicator at agent */}
                {isDone && (
                  <circle
                    cx={startX}
                    cy={68}
                    r="5"
                    fill={isSuccess ? "#22c55e" : "#ef4444"}
                    opacity="0.8"
                  >
                    <animate
                      attributeName="r"
                      values="5;7;5"
                      dur="1.5s"
                      repeatCount="indefinite"
                    />
                  </circle>
                )}

                {/* Agent label */}
                <text
                  x={startX}
                  y={78}
                  textAnchor="middle"
                  className={`text-[7px] font-medium`}
                  fill={AGENT_COLORS[agentKey].hex}
                  opacity={0.7}
                >
                  {agentKey === "claude"
                    ? "Claude"
                    : agentKey === "codex"
                      ? "Codex"
                      : "Antigravity"}
                </text>
              </g>
            );
          })}

          {/* Particle effects */}
          {particles.map((p) => (
            <circle
              key={p.id}
              cx={`${p.x}%`}
              cy={`${p.y}%`}
              r="2"
              fill={p.color}
              opacity={p.life * 0.8}
            >
              <animate
                attributeName="cx"
                from={`${p.x}%`}
                to={`${p.x + Math.cos(p.angle) * p.speed * 8}%`}
                dur="1s"
                fill="freeze"
              />
              <animate
                attributeName="cy"
                from={`${p.y}%`}
                to={`${p.y + Math.sin(p.angle) * p.speed * 8}%`}
                dur="1s"
                fill="freeze"
              />
              <animate
                attributeName="opacity"
                from="0.8"
                to="0"
                dur="1s"
                fill="freeze"
              />
              <animate
                attributeName="r"
                from="3"
                to="0"
                dur="1s"
                fill="freeze"
              />
            </circle>
          ))}
        </svg>
      </div>

      {/* Terminal panels */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-0 md:gap-px bg-white/[0.04]">
        {AGENT_KEYS.map((agentKey) => (
          <AgentTerminalPanel
            key={`${scenario.id}-${agentKey}`}
            agentKey={agentKey}
            agentScenario={scenario.agents[agentKey]}
            visibleCount={visibleLines[agentKey]}
            isDone={agentDone[agentKey]}
            isPlaying={isPlaying}
          />
        ))}
      </div>

      {/* Scenario progress dots */}
      <div className="flex items-center justify-center gap-2 py-4 bg-black/20">
        {SCENARIOS.map((_, i) => (
          <motion.button
            key={i}
            onClick={() => {
              resetState();
              setScenarioIndex(i);
            }}
            whileHover={{ scale: 1.3 }}
            transition={springs.snappy}
            className={`h-2 rounded-full transition-all duration-300 ${
              i === scenarioIndex
                ? "w-6 bg-primary"
                : "w-2 bg-white/20 hover:bg-white/40"
            }`}
          />
        ))}
      </div>
    </div>
  );
}

// =============================================================================
// AGENT TERMINAL PANEL - Individual terminal with typing animation
// =============================================================================
function AgentTerminalPanel({
  agentKey,
  agentScenario,
  visibleCount,
  isDone,
  isPlaying,
}: {
  agentKey: AgentId;
  agentScenario: ScenarioAgent;
  visibleCount: number;
  isDone: boolean;
  isPlaying: boolean;
}) {
  const colors = AGENT_COLORS[agentKey];
  const terminalRef = useRef<HTMLDivElement>(null);

  // Auto-scroll terminal to bottom
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [visibleCount]);

  const agentLabel = AGENT_LABELS[agentKey];

  return (
    <div className="bg-black/40 flex flex-col">
      {/* Terminal header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-white/[0.06]">
        <div className="flex items-center gap-2">
          <div className={`h-2.5 w-2.5 rounded-full ${colors.bg}`} />
          <span className={`text-xs font-semibold ${colors.text}`}>
            {agentLabel}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          {isDone ? (
            agentScenario.result === "success" ? (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={springs.snappy}
                className="flex items-center gap-1 px-2 py-0.5 rounded-full bg-emerald-500/20 border border-emerald-500/30"
              >
                <CheckCircle2 className="h-3 w-3 text-emerald-400" />
                <span className="text-[10px] font-medium text-emerald-400">
                  PASS
                </span>
              </motion.div>
            ) : (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={springs.snappy}
                className="flex items-center gap-1 px-2 py-0.5 rounded-full bg-red-500/20 border border-red-500/30"
              >
                <XCircle className="h-3 w-3 text-red-400" />
                <span className="text-[10px] font-medium text-red-400">
                  FAIL
                </span>
              </motion.div>
            )
          ) : isPlaying ? (
            <div className="flex items-center gap-1">
              <motion.div
                className={`h-1.5 w-1.5 rounded-full ${colors.bg}`}
                animate={{ opacity: [0.3, 1, 0.3] }}
                transition={{ duration: 1, repeat: Infinity }}
              />
              <span className="text-[10px] text-white/30">running</span>
            </div>
          ) : (
            <span className="text-[10px] text-white/20">idle</span>
          )}
        </div>
      </div>

      {/* Terminal body */}
      <div
        ref={terminalRef}
        className="px-3 py-2 font-mono text-[11px] leading-relaxed min-h-[180px] max-h-[220px] overflow-y-auto scrollbar-thin scrollbar-thumb-white/10"
      >
        {visibleCount === 0 && !isPlaying && (
          <div className="flex items-center justify-center h-full min-h-[160px] text-white/20">
            <span className="text-xs">Press play to start</span>
          </div>
        )}
        <AnimatePresence>
          {agentScenario.lines.slice(0, visibleCount).map((line, i) => (
            <motion.div
              key={`${agentKey}-line-${i}`}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.15 }}
              className={`py-0.5 ${getLineColor(line.type)}`}
            >
              {line.type === "command" && (
                <span className="text-white/30 select-none">
                  {line.text.startsWith("$") ? "" : "$ "}
                </span>
              )}
              <span>{line.text}</span>
              {line.type === "success" && (
                <span className="ml-1 inline-block">
                  <CheckCircle2 className="h-3 w-3 inline text-emerald-400" />
                </span>
              )}
              {line.type === "error" && (
                <span className="ml-1 inline-block">
                  <XCircle className="h-3 w-3 inline text-red-400" />
                </span>
              )}
            </motion.div>
          ))}
        </AnimatePresence>

        {/* Blinking cursor while running */}
        {isPlaying && !isDone && visibleCount > 0 && (
          <motion.span
            className={`inline-block w-1.5 h-3.5 ${colors.bg} ml-0.5`}
            animate={{ opacity: [1, 0, 1] }}
            transition={{ duration: 0.8, repeat: Infinity }}
          />
        )}
      </div>

      {/* Terminal footer - timing */}
      <div className="px-3 py-1.5 border-t border-white/[0.04] flex items-center justify-between">
        <span className="text-[10px] text-white/20">
          {visibleCount}/{agentScenario.lines.length} steps
        </span>
        {isDone && (
          <motion.span
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-[10px] text-white/30"
          >
            {(agentScenario.finishDelay / 1000).toFixed(1)}s
          </motion.span>
        )}
      </div>
    </div>
  );
}

function getLineColor(type: TerminalLine["type"]): string {
  switch (type) {
    case "command":
      return "text-white/90";
    case "output":
      return "text-white/50";
    case "success":
      return "text-emerald-400";
    case "error":
      return "text-red-400";
    case "info":
      return "text-blue-300/70";
    case "blank":
      return "";
  }
}

// =============================================================================
// OPENAI ACCOUNT WARNING - Critical warning about account types
// =============================================================================
function OpenAIAccountWarning() {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -2, scale: 1.01 }}
      className="group relative rounded-2xl border border-amber-500/30 bg-gradient-to-br from-amber-500/10 to-orange-500/10 p-6 backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-amber-500/50"
    >
      <div className="absolute top-0 right-0 w-32 h-32 bg-amber-500/20 rounded-full blur-3xl" />

      <div className="relative">
        <div className="flex items-center gap-3 mb-4">
          <AlertTriangle className="h-5 w-5 text-amber-400" />
          <span className="font-bold text-amber-400">
            OpenAI Has TWO Account Types
          </span>
        </div>

        {/* Account type comparison */}
        <div className="grid gap-4 md:grid-cols-2 mb-4">
          <div className="p-4 rounded-xl bg-black/20 border border-white/[0.06]">
            <h5 className="font-bold text-white mb-2">
              ChatGPT (Pro/Plus/Team)
            </h5>
            <ul className="space-y-1 text-xs text-white/60">
              <li>• For Codex CLI, ChatGPT web</li>
              <li>• Auth via ChatGPT login ({`\`codex login --device-auth\``} is recommended on a VPS)</li>
              <li>
                • Get at{" "}
                <span className="text-primary">chat.openai.com</span>
              </li>
            </ul>
          </div>
          <div className="p-4 rounded-xl bg-black/20 border border-white/[0.06]">
            <h5 className="font-bold text-white mb-2">API (pay-as-you-go)</h5>
            <ul className="space-y-1 text-xs text-white/60">
              <li>• For OpenAI API, libraries</li>
              <li>• Uses OPENAI_API_KEY env var</li>
              <li>
                • Get at{" "}
                <span className="text-primary">platform.openai.com</span>
              </li>
            </ul>
          </div>
        </div>

        <p className="text-sm text-white/70">
          Codex CLI uses <strong>ChatGPT OAuth</strong>, not API keys. If you
          have an <InlineCode>OPENAI_API_KEY</InlineCode>, that&apos;s for the
          API—different system!
        </p>

        <p className="mt-3 text-sm text-amber-400/80">
          <strong>If login fails:</strong> Check ChatGPT Settings → Security →
          &quot;API/Device access&quot;
        </p>
      </div>
    </motion.div>
  );
}
