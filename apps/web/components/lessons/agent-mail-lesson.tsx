"use client";

import { motion, AnimatePresence, useInView } from "@/components/motion";
import { useState, useCallback, useEffect, useRef, useMemo } from "react";
import {
  Mail,
  Users,
  FileText,
  Lock,
  MessageSquare,
  Send,
  Inbox,
  Search,
  Bot,
  Workflow,
  CheckCircle,
  AlertTriangle,
  Unlock,
  Play,
  ChevronLeft,
  ChevronRight,
  Pause,
  X,
  ArrowRight,
  Clock,
  RotateCcw,
  Eye,
} from "lucide-react";
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  FeatureCard,
  FeatureGrid,
} from "./lesson-components";

export function AgentMailLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Coordinate multiple agents without conflicts using Agent Mail.
      </GoalBanner>

      {/* What Is Agent Mail */}
      <Section
        title="What Is Agent Mail?"
        icon={<Mail className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>MCP Agent Mail</Highlight> is a coordination system that
          lets multiple AI agents work on the same project without stepping on
          each other&apos;s toes.
        </Paragraph>
        <Paragraph>
          Think of it as email + file locking for agents. Agents can send
          messages, claim files they&apos;re working on, and stay in sync—all
          persisted in git.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<MessageSquare className="h-5 w-5" />}
              title="Messaging"
              description="Agents send and receive messages with context"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Lock className="h-5 w-5" />}
              title="File Reservations"
              description="Advisory locks prevent edit conflicts"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Searchable Threads"
              description="Find past decisions and discussions"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Git Persistence"
              description="All artifacts are human-auditable in git"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Why Coordination Matters */}
      <Section
        title="Why Coordination Matters"
        icon={<Users className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          Without coordination, multiple agents working on the same codebase
          can:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <ProblemCard
            problem="Overwrite each other's changes"
            solution="File reservations prevent conflicts"
          />
          <ProblemCard
            problem="Duplicate work on the same task"
            solution="Message threads track who's doing what"
          />
          <ProblemCard
            problem="Make conflicting architectural decisions"
            solution="Shared context via searchable threads"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Agent Mail is available as an MCP server. Your agents can use it
            automatically when configured!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Core Concepts */}
      <Section
        title="Core Concepts"
        icon={<Workflow className="h-5 w-5" />}
        delay={0.2}
      >
        <div className="space-y-8">
          {/* Project & Agents */}
          <ConceptCard
            icon={<Bot className="h-5 w-5" />}
            title="Projects & Agents"
            description="Each project has registered agents with unique names"
          >
            <CodeBlock
              code={`# Agent names are adjective+noun combinations
# Examples: "BlueLake", "GreenCastle", "RedStone"

# Register an agent
ensure_project(human_key="/data/projects/my-app")
register_agent(
  project_key="/data/projects/my-app",
  program="claude-code",
  model="opus-4.5"
)`}
              language="python"
            />
          </ConceptCard>

          {/* Messages */}
          <ConceptCard
            icon={<Send className="h-5 w-5" />}
            title="Sending Messages"
            description="Agents communicate via structured messages"
          >
            <CodeBlock
              code={`send_message(
  project_key="/data/projects/my-app",
  sender_name="BlueLake",
  to=["GreenCastle"],
  subject="API design question",
  body_md="Should we use REST or GraphQL for the new endpoint?"
)`}
              language="python"
            />
          </ConceptCard>

          {/* File Reservations */}
          <ConceptCard
            icon={<Lock className="h-5 w-5" />}
            title="File Reservations"
            description="Claim files before editing to prevent conflicts"
          >
            <CodeBlock
              code={`# Reserve files before editing
file_reservation_paths(
  project_key="/data/projects/my-app",
  agent_name="BlueLake",
  paths=["src/api/*.py", "src/routes/*.py"],
  ttl_seconds=3600,  # 1 hour lease
  exclusive=true     # No one else can edit
)

# Release when done
release_file_reservations(
  project_key="/data/projects/my-app",
  agent_name="BlueLake"
)`}
              language="python"
            />
          </ConceptCard>

          {/* Inbox */}
          <ConceptCard
            icon={<Inbox className="h-5 w-5" />}
            title="Checking Your Inbox"
            description="Fetch messages addressed to you"
          >
            <CodeBlock
              code={`# Check for new messages
fetch_inbox(
  project_key="/data/projects/my-app",
  agent_name="BlueLake",
  since_ts="2025-01-15T10:00:00Z",
  include_bodies=true
)

# Acknowledge important messages
acknowledge_message(
  project_key="/data/projects/my-app",
  agent_name="BlueLake",
  message_id=1234
)`}
              language="python"
            />
          </ConceptCard>
        </div>
      </Section>

      <Divider />

      {/* Common Patterns */}
      <Section
        title="Common Patterns"
        icon={<Workflow className="h-5 w-5" />}
        delay={0.25}
      >
        <div className="space-y-6">
          <PatternCard
            title="Starting a Session"
            description="Use the macro for quick setup"
            code={`macro_start_session(
  human_key="/data/projects/my-app",
  program="claude-code",
  model="opus-4.5",
  task_description="Implementing auth"
)`}
          />

          <PatternCard
            title="Replying to a Thread"
            description="Keep discussions organized"
            code={`reply_message(
  project_key="/data/projects/my-app",
  message_id=1234,
  sender_name="GreenCastle",
  body_md="I agree, let's use GraphQL. Starting work now."
)`}
          />

          <PatternCard
            title="Searching Past Discussions"
            description="Find relevant context"
            code={`search_messages(
  project_key="/data/projects/my-app",
  query="authentication AND JWT",
  limit=10
)`}
          />
        </div>
      </Section>

      <Divider />

      {/* The Coordination Flow */}
      <Section
        title="The Coordination Flow"
        icon={<Workflow className="h-5 w-5" />}
        delay={0.3}
      >
        <InteractiveCoordinationSim />
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<CheckCircle className="h-5 w-5" />}
        delay={0.35}
      >
        <div className="space-y-4">
          <BestPractice
            title="Reserve before editing"
            description="Always claim files before making changes to prevent conflicts"
          />
          <BestPractice
            title="Keep subjects specific"
            description="Use descriptive subjects (≤80 chars) for easy searching"
          />
          <BestPractice
            title="Use thread_id consistently"
            description="Keep related discussions in the same thread"
          />
          <BestPractice
            title="Set realistic TTLs"
            description="Don't hold file reservations longer than needed"
          />
          <BestPractice
            title="Acknowledge when required"
            description="Use acknowledge_message for ack_required messages"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            If you see <code>FILE_RESERVATION_CONFLICT</code>, another agent
            has the file. Wait for expiry, adjust your patterns, or use
            non-exclusive reservations.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Quick Reference */}
      <Section
        title="Quick Reference"
        icon={<FileText className="h-5 w-5" />}
        delay={0.4}
      >
        <div className="mt-6 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
          <div className="p-5 border-b border-white/[0.06] bg-gradient-to-r from-primary/10 to-violet-500/10">
            <span className="font-bold text-white text-lg">Key Functions</span>
          </div>
          <div className="divide-y divide-white/[0.06]">
            <FunctionRow name="ensure_project" purpose="Initialize a project" />
            <FunctionRow name="register_agent" purpose="Register your identity" />
            <FunctionRow name="send_message" purpose="Send a message" />
            <FunctionRow name="reply_message" purpose="Reply to a thread" />
            <FunctionRow name="fetch_inbox" purpose="Get your messages" />
            <FunctionRow name="acknowledge_message" purpose="Confirm receipt" />
            <FunctionRow name="file_reservation_paths" purpose="Claim files" />
            <FunctionRow name="release_file_reservations" purpose="Release files" />
            <FunctionRow name="search_messages" purpose="Search threads" />
            <FunctionRow name="macro_start_session" purpose="Quick session setup" />
          </div>
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// PROBLEM CARD
// =============================================================================
function ProblemCard({
  problem,
  solution,
}: {
  problem: string;
  solution: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-center gap-4 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-red-500/20 text-red-400 group-hover:bg-red-500/30 transition-colors">
        ✗
      </div>
      <div className="flex-1">
        <span className="text-white/50 line-through">{problem}</span>
      </div>
      <div className="text-white/50 group-hover:text-white/70 transition-colors">→</div>
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 group-hover:bg-emerald-500/30 transition-colors">
        ✓
      </div>
      <div className="flex-1">
        <span className="text-white/80 font-medium">{solution}</span>
      </div>
    </motion.div>
  );
}

// =============================================================================
// CONCEPT CARD
// =============================================================================
function ConceptCard({
  icon,
  title,
  description,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="group relative space-y-4 p-6 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden transition duration-500 hover:border-white/[0.12]"
    >
      {/* Subtle gradient overlay on hover */}
      <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-violet-500/5 opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <div className="relative flex items-center gap-4">
        <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30 text-primary shadow-lg shadow-primary/10">
          {icon}
        </div>
        <div>
          <h4 className="font-bold text-white text-lg">{title}</h4>
          <p className="text-sm text-white/50">{description}</p>
        </div>
      </div>
      <div className="relative">{children}</div>
    </motion.div>
  );
}

// =============================================================================
// PATTERN CARD
// =============================================================================
function PatternCard({
  title,
  description,
  code,
}: {
  title: string;
  description: string;
  code: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -4, scale: 1.01 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden transition duration-500 hover:border-white/[0.15]"
    >
      {/* Gradient overlay on hover */}
      <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-violet-500/5 opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <div className="relative p-5 border-b border-white/[0.06] bg-white/[0.02]">
        <h4 className="font-bold text-white text-lg">{title}</h4>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
      <div className="relative p-4">
        <CodeBlock code={code} language="python" />
      </div>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE COORDINATION SIMULATION V2 - Mail System Visualization
// =============================================================================

type AgentId = "agent1" | "agent2" | "agent3";

interface MailMessage {
  id: number;
  from: AgentId;
  to: AgentId;
  subject: string;
  body: string;
  timestamp: string;
  acknowledged: boolean;
  threadId: number;
}

interface FileReservation {
  path: string;
  owner: AgentId | null;
  conflictFlash: boolean;
}

interface AgentInbox {
  id: AgentId;
  name: string;
  color: string;
  gradient: string;
  borderColor: string;
  textColor: string;
  bgAccent: string;
  task: string;
  registered: boolean;
  messages: MailMessage[];
  reservedFiles: string[];
}

interface ActivityLogEntry {
  id: number;
  step: number;
  type: "register" | "reserve" | "conflict" | "message" | "ack" | "release";
  agent: AgentId;
  text: string;
  timestamp: string;
}

interface SimState {
  agents: AgentInbox[];
  files: FileReservation[];
  flyingEnvelope: { from: AgentId; to: AgentId; subject: string } | null;
  activityLog: ActivityLogEntry[];
  conflict: { agent: AgentId; file: string } | null;
}

interface SimStepDef {
  label: string;
  description: string;
  icon: "register" | "reserve" | "conflict" | "message" | "ack" | "release";
}

const SIM_FILES: string[] = [
  "src/api.ts",
  "src/auth.ts",
  "src/ui.tsx",
  "src/db.ts",
  "src/utils.ts",
  "src/config.ts",
];

const SIM_STEP_DEFS: SimStepDef[] = [
  {
    label: "Agent-1 registers & claims files",
    description: "BlueLake claims src/api.ts and src/auth.ts for exclusive editing",
    icon: "reserve",
  },
  {
    label: "Agent-2 attempts overlapping claim",
    description: "GreenCastle tries to claim src/api.ts -- CONFLICT detected!",
    icon: "conflict",
  },
  {
    label: "Agent-2 claims different file",
    description: "GreenCastle claims src/ui.tsx instead -- success",
    icon: "reserve",
  },
  {
    label: "Agent-1 sends message",
    description: 'BlueLake sends "API ready for integration" to GreenCastle',
    icon: "message",
  },
  {
    label: "Agent-2 acknowledges",
    description: "GreenCastle confirms receipt of the message",
    icon: "ack",
  },
  {
    label: "Agent-1 releases reservations",
    description: "BlueLake releases src/api.ts and src/auth.ts back to the pool",
    icon: "release",
  },
];

const AGENT_CONFIGS: {
  id: AgentId;
  name: string;
  color: string;
  gradient: string;
  borderColor: string;
  textColor: string;
  bgAccent: string;
  task: string;
}[] = [
  {
    id: "agent1",
    name: "BlueLake",
    color: "blue",
    gradient: "from-blue-500/20 to-indigo-500/20",
    borderColor: "border-blue-500/30",
    textColor: "text-blue-400",
    bgAccent: "bg-blue-500",
    task: "API development",
  },
  {
    id: "agent2",
    name: "GreenCastle",
    color: "green",
    gradient: "from-emerald-500/20 to-green-500/20",
    borderColor: "border-emerald-500/30",
    textColor: "text-emerald-400",
    bgAccent: "bg-emerald-500",
    task: "UI integration",
  },
  {
    id: "agent3",
    name: "RedStone",
    color: "red",
    gradient: "from-red-500/20 to-amber-500/20",
    borderColor: "border-red-500/30",
    textColor: "text-red-400",
    bgAccent: "bg-red-500",
    task: "Database layer",
  },
];

function computeSimState(step: number): SimState {
  const agents: AgentInbox[] = AGENT_CONFIGS.map((c) => ({
    ...c,
    registered: false,
    messages: [],
    reservedFiles: [],
  }));
  const files: FileReservation[] = SIM_FILES.map((p) => ({
    path: p,
    owner: null,
    conflictFlash: false,
  }));
  const activityLog: ActivityLogEntry[] = [];
  let flyingEnvelope: SimState["flyingEnvelope"] = null;
  let conflict: SimState["conflict"] = null;

  // Step 0: Agent-1 registers and claims files
  if (step >= 0) {
    agents[0].registered = true;
    agents[1].registered = true;
    agents[2].registered = true;
    // BlueLake claims src/api.ts and src/auth.ts
    agents[0].reservedFiles = ["src/api.ts", "src/auth.ts"];
    files[0].owner = "agent1";
    files[1].owner = "agent1";
    activityLog.push({
      id: 1,
      step: 0,
      type: "reserve",
      agent: "agent1",
      text: "BlueLake claimed src/api.ts, src/auth.ts",
      timestamp: "10:00:01",
    });
  }

  // Step 1: Agent-2 tries overlapping claim -- CONFLICT
  if (step >= 1) {
    conflict = { agent: "agent2", file: "src/api.ts" };
    files[0].conflictFlash = true;
    activityLog.push({
      id: 2,
      step: 1,
      type: "conflict",
      agent: "agent2",
      text: "CONFLICT: GreenCastle denied src/api.ts (held by BlueLake)",
      timestamp: "10:00:05",
    });
  }

  // Step 2: Agent-2 claims src/ui.tsx instead
  if (step >= 2) {
    conflict = null;
    files[0].conflictFlash = false;
    agents[1].reservedFiles = ["src/ui.tsx"];
    files[2].owner = "agent2";
    activityLog.push({
      id: 3,
      step: 2,
      type: "reserve",
      agent: "agent2",
      text: "GreenCastle claimed src/ui.tsx",
      timestamp: "10:00:08",
    });
  }

  // Step 3: BlueLake sends message to GreenCastle
  if (step >= 3) {
    const msg: MailMessage = {
      id: 1,
      from: "agent1",
      to: "agent2",
      subject: "API ready for integration",
      body: "The /api/login and /api/auth endpoints are done. You can import { authMiddleware } from src/auth.ts for your UI routes.",
      timestamp: "10:01:12",
      acknowledged: false,
      threadId: 1,
    };
    agents[0].messages.push(msg);
    agents[1].messages.push(msg);
    flyingEnvelope = {
      from: "agent1",
      to: "agent2",
      subject: "API ready for integration",
    };
    activityLog.push({
      id: 4,
      step: 3,
      type: "message",
      agent: "agent1",
      text: 'BlueLake -> GreenCastle: "API ready for integration"',
      timestamp: "10:01:12",
    });
  }

  // Step 4: GreenCastle acknowledges
  if (step >= 4) {
    flyingEnvelope = null;
    // Mark message as acknowledged
    for (const a of agents) {
      for (const m of a.messages) {
        if (m.id === 1) m.acknowledged = true;
      }
    }
    activityLog.push({
      id: 5,
      step: 4,
      type: "ack",
      agent: "agent2",
      text: "GreenCastle acknowledged message #1",
      timestamp: "10:01:20",
    });
  }

  // Step 5: BlueLake releases reservations
  if (step >= 5) {
    agents[0].reservedFiles = [];
    files[0].owner = null;
    files[1].owner = null;
    activityLog.push({
      id: 6,
      step: 5,
      type: "release",
      agent: "agent1",
      text: "BlueLake released src/api.ts, src/auth.ts",
      timestamp: "10:02:00",
    });
  }

  return { agents, files, flyingEnvelope, activityLog, conflict };
}

const STEP_ICON_MAP: Record<SimStepDef["icon"], React.ReactNode> = {
  register: <Bot className="h-3.5 w-3.5" />,
  reserve: <Lock className="h-3.5 w-3.5" />,
  conflict: <AlertTriangle className="h-3.5 w-3.5" />,
  message: <Send className="h-3.5 w-3.5" />,
  ack: <CheckCircle className="h-3.5 w-3.5" />,
  release: <Unlock className="h-3.5 w-3.5" />,
};

const springSmooth = { type: "spring" as const, stiffness: 200, damping: 25 };

function getFileOwnerColor(owner: AgentId | null): {
  bg: string;
  border: string;
  text: string;
  rgbaBg: string;
} {
  switch (owner) {
    case "agent1":
      return {
        bg: "bg-blue-500/20",
        border: "border-blue-500/40",
        text: "text-blue-400",
        rgbaBg: "rgba(59,130,246,0.08)",
      };
    case "agent2":
      return {
        bg: "bg-emerald-500/20",
        border: "border-emerald-500/40",
        text: "text-emerald-400",
        rgbaBg: "rgba(16,185,129,0.08)",
      };
    case "agent3":
      return {
        bg: "bg-red-500/20",
        border: "border-red-500/40",
        text: "text-red-400",
        rgbaBg: "rgba(239,68,68,0.08)",
      };
    default:
      return {
        bg: "",
        border: "",
        text: "",
        rgbaBg: "rgba(255,255,255,0)",
      };
  }
}

function getAgentNameById(id: AgentId): string {
  const found = AGENT_CONFIGS.find((a) => a.id === id);
  return found ? found.name : id;
}

function getLogTypeColor(
  type: ActivityLogEntry["type"]
): { text: string; bg: string } {
  switch (type) {
    case "register":
      return { text: "text-violet-400", bg: "bg-violet-500/20" };
    case "reserve":
      return { text: "text-blue-400", bg: "bg-blue-500/20" };
    case "conflict":
      return { text: "text-red-400", bg: "bg-red-500/20" };
    case "message":
      return { text: "text-amber-400", bg: "bg-amber-500/20" };
    case "ack":
      return { text: "text-emerald-400", bg: "bg-emerald-500/20" };
    case "release":
      return { text: "text-cyan-400", bg: "bg-cyan-500/20" };
  }
}

// ---------------------------------------------------------------------------
// Thread viewer modal
// ---------------------------------------------------------------------------
function ThreadViewer({
  message,
  onClose,
}: {
  message: MailMessage;
  onClose: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="absolute inset-0 z-30 flex items-center justify-center bg-black/60 backdrop-blur-sm rounded-3xl"
      onClick={onClose}
    >
      <motion.div
        initial={{ opacity: 0, scale: 0.9, y: 20 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.95, y: 10 }}
        transition={springSmooth}
        className="relative w-full max-w-md mx-4 rounded-2xl border border-white/[0.12] bg-[#0d1117]/95 backdrop-blur-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/[0.08] bg-gradient-to-r from-primary/10 to-violet-500/10">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20 border border-primary/30">
              <MessageSquare className="h-4 w-4 text-primary" />
            </div>
            <div>
              <p className="text-sm font-bold text-white">Thread #{message.threadId}</p>
              <p className="text-xs text-white/40">{message.subject}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="flex h-7 w-7 items-center justify-center rounded-lg border border-white/[0.08] bg-white/[0.04] text-white/50 hover:text-white hover:bg-white/[0.08] transition"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>

        {/* Message body */}
        <div className="p-5 space-y-4">
          {/* Original message */}
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold text-blue-400">
                {getAgentNameById(message.from)}
              </span>
              <ArrowRight className="h-3 w-3 text-white/30" />
              <span className="text-xs font-semibold text-emerald-400">
                {getAgentNameById(message.to)}
              </span>
              <span className="text-[10px] text-white/30 ml-auto">
                {message.timestamp}
              </span>
            </div>
            <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4">
              <p className="text-sm text-white/70 leading-relaxed">
                {message.body}
              </p>
            </div>
          </div>

          {/* Ack status */}
          {message.acknowledged && (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={springSmooth}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20"
            >
              <CheckCircle className="h-4 w-4 text-emerald-400" />
              <span className="text-xs text-emerald-300 font-medium">
                Acknowledged by {getAgentNameById(message.to)}
              </span>
            </motion.div>
          )}
        </div>
      </motion.div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Agent Inbox Card
// ---------------------------------------------------------------------------
function AgentInboxCard({
  agent,
  isConflictAgent,
  conflict,
  onMessageClick,
  active,
}: {
  agent: AgentInbox;
  isConflictAgent: boolean;
  conflict: SimState["conflict"];
  onMessageClick: (msg: MailMessage) => void;
  active: boolean;
}) {
  const unreadCount = agent.messages.filter((m) => !m.acknowledged && m.to === agent.id).length;

  return (
    <motion.div
      layout
      animate={{
        opacity: agent.registered ? 1 : 0.35,
        scale: isConflictAgent ? [1, 1.02, 0.98, 1.02, 1] : 1,
        x: isConflictAgent ? [0, -3, 3, -3, 0] : 0,
      }}
      transition={{
        duration: isConflictAgent ? 0.5 : 0.3,
        layout: springSmooth,
      }}
      className={`relative flex flex-col rounded-2xl border backdrop-blur-xl overflow-hidden transition-colors duration-300 ${
        isConflictAgent
          ? "border-red-500/60 bg-red-500/10"
          : agent.registered
            ? `${agent.borderColor} bg-gradient-to-br ${agent.gradient}`
            : "border-white/[0.06] bg-white/[0.02]"
      }`}
    >
      {/* Pulsing glow */}
      {agent.registered && !isConflictAgent && (
        <motion.div
          className={`absolute inset-0 blur-xl pointer-events-none ${
            agent.bgAccent === 'bg-blue-500' ? 'bg-blue-500/10' :
            agent.bgAccent === 'bg-emerald-500' ? 'bg-emerald-500/10' :
            agent.bgAccent === 'bg-red-500' ? 'bg-red-500/10' : 'bg-white/10'
          }`}
          animate={active ? { opacity: [0.2, 0.45, 0.2] } : { opacity: 0.2 }}
          transition={active ? { duration: 3, repeat: Infinity, ease: "easeInOut" } : { duration: 0.2 }}
        />
      )}

      {/* Card header */}
      <div className="relative flex items-center gap-3 px-4 py-3.5 border-b border-white/[0.06]">
        <div
          className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br ${agent.gradient} border ${agent.borderColor} shadow-lg`}
        >
          <Bot className={`h-4 w-4 ${agent.textColor}`} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <p
              className={`font-bold text-sm truncate ${agent.registered ? "text-white" : "text-white/40"}`}
            >
              {agent.name}
            </p>
            {unreadCount > 0 && (
              <motion.span
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={springSmooth}
                className="flex h-5 min-w-[20px] items-center justify-center rounded-full bg-red-500/90 px-1.5 text-[10px] font-bold text-white shadow-lg shadow-red-500/30"
              >
                {unreadCount}
              </motion.span>
            )}
          </div>
          <p className="text-xs text-white/40 truncate">{agent.task}</p>
        </div>

        {/* Online indicator */}
        {agent.registered && (
          <motion.div
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            className="flex h-2.5 w-2.5 rounded-full bg-emerald-400 shadow-lg shadow-emerald-400/50"
          >
            <motion.div
              className="h-full w-full rounded-full bg-emerald-400"
              animate={active ? { scale: [1, 1.8, 1], opacity: [1, 0, 1] } : { scale: 1, opacity: 1 }}
              transition={active ? { duration: 2, repeat: Infinity } : { duration: 0.2 }}
            />
          </motion.div>
        )}
      </div>

      {/* Reserved files */}
      <div className="relative px-4 py-2.5 min-h-[52px]">
        {agent.reservedFiles.length > 0 ? (
          <div className="flex flex-wrap gap-1.5">
            {agent.reservedFiles.map((f) => (
              <motion.span
                key={f}
                initial={{ opacity: 0, scale: 0.7 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.7 }}
                transition={springSmooth}
                className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-mono ${agent.textColor} bg-white/[0.06] border border-white/[0.08]`}
              >
                <Lock className="h-2.5 w-2.5" />
                {f}
              </motion.span>
            ))}
          </div>
        ) : (
          <p className="text-[10px] text-white/20 italic">No file reservations</p>
        )}
      </div>

      {/* Conflict badge */}
      <AnimatePresence>
        {isConflictAgent && conflict && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden"
          >
            <div className="mx-4 mb-3 flex items-center gap-2 px-3 py-2 rounded-xl bg-red-500/15 border border-red-500/30">
              <AlertTriangle className="h-3.5 w-3.5 text-red-400 shrink-0" />
              <span className="text-[11px] text-red-300 font-medium">
                Denied: {conflict.file} is reserved
              </span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Messages */}
      <div className="relative border-t border-white/[0.06]">
        <div className="px-4 py-2 flex items-center gap-1.5">
          <Inbox className="h-3 w-3 text-white/30" />
          <span className="text-[10px] font-semibold text-white/30 uppercase tracking-wider">
            Messages
          </span>
        </div>
        <div className="px-3 pb-3 space-y-1.5 min-h-[40px]">
          <AnimatePresence>
            {agent.messages
              .filter((m) => m.to === agent.id || m.from === agent.id)
              .map((msg) => {
                const isSender = msg.from === agent.id;
                return (
                  <motion.button
                    key={`${msg.id}-${isSender ? "sent" : "rcvd"}`}
                    initial={{ opacity: 0, x: isSender ? -10 : 10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, scale: 0.9 }}
                    transition={springSmooth}
                    onClick={() => onMessageClick(msg)}
                    className="w-full flex items-center gap-2 px-3 py-2 rounded-xl border border-white/[0.06] bg-white/[0.02] hover:bg-white/[0.06] hover:border-white/[0.12] transition text-left group/msg cursor-pointer"
                  >
                    {isSender ? (
                      <Send className="h-3 w-3 text-white/30 shrink-0" />
                    ) : (
                      <Mail className="h-3 w-3 text-white/30 shrink-0" />
                    )}
                    <span className="text-xs text-white/60 truncate flex-1 group-hover/msg:text-white/80 transition-colors">
                      {isSender ? `To ${getAgentNameById(msg.to)}` : `From ${getAgentNameById(msg.from)}`}:{" "}
                      {msg.subject}
                    </span>
                    {msg.acknowledged && (
                      <CheckCircle className="h-3 w-3 text-emerald-400 shrink-0" />
                    )}
                    <Eye className="h-3 w-3 text-white/20 shrink-0 opacity-0 group-hover/msg:opacity-100 transition-opacity" />
                  </motion.button>
                );
              })}
          </AnimatePresence>
          {agent.messages.filter(
            (m) => m.to === agent.id || m.from === agent.id
          ).length === 0 && (
            <p className="text-[10px] text-white/15 italic px-2 py-1">
              No messages yet
            </p>
          )}
        </div>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Main InteractiveCoordinationSim V2
// ---------------------------------------------------------------------------
function InteractiveCoordinationSim() {
  const [currentStep, setCurrentStep] = useState(-1);
  const [isPlaying, setIsPlaying] = useState(false);
  const [selectedMessage, setSelectedMessage] = useState<MailMessage | null>(null);
  const logContainerRef = useRef<HTMLDivElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const totalSteps = SIM_STEP_DEFS.length;

  const goNext = useCallback(() => {
    setCurrentStep((s) => Math.min(s + 1, totalSteps - 1));
  }, [totalSteps]);

  const goPrev = useCallback(() => {
    setCurrentStep((s) => Math.max(s - 1, -1));
  }, []);

  const togglePlay = useCallback(() => {
    setIsPlaying((p) => !p);
  }, []);

  const resetSim = useCallback(() => {
    setCurrentStep(-1);
    setIsPlaying(false);
    setSelectedMessage(null);
  }, []);

  // Auto-advance when playing
  useEffect(() => {
    if (!isPlaying) return;
    const timer = setTimeout(() => {
      if (currentStep >= totalSteps - 1) {
        setIsPlaying(false);
      } else {
        goNext();
      }
    }, 2000);
    return () => clearTimeout(timer);
  }, [isPlaying, currentStep, totalSteps, goNext]);

  // Auto-scroll activity log
  useEffect(() => {
    if (logContainerRef.current) {
      const el = logContainerRef.current;
      // Use setTimeout to run after DOM update
      const timer = setTimeout(() => {
        el.scrollTop = el.scrollHeight;
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [currentStep]);

  const simState = useMemo(() => computeSimState(currentStep), [currentStep]);
  const { agents, files, flyingEnvelope, activityLog, conflict } = simState;

  const handleMessageClick = useCallback((msg: MailMessage) => {
    setSelectedMessage(msg);
  }, []);

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-primary/8 rounded-full blur-[100px] pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-violet-500/8 rounded-full blur-[100px] pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-40 h-40 bg-amber-500/5 rounded-full blur-[80px] pointer-events-none" />

      <div className="relative p-5 sm:p-8 space-y-6">
        {/* ---- Title bar ---- */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30 shadow-lg shadow-primary/10">
              <Mail className="h-5 w-5 text-primary" />
            </div>
            <div>
              <h3 className="text-base font-bold text-white">Agent Mail System</h3>
              <p className="text-xs text-white/40">Real-time coordination simulation</p>
            </div>
          </div>

          {/* Central hub indicator */}
          <motion.div
            animate={{
              boxShadow:
                currentStep >= 0 && inView
                  ? [
                      "0 0 0px rgba(168,85,247,0.2)",
                      "0 0 20px rgba(168,85,247,0.4)",
                      "0 0 0px rgba(168,85,247,0.2)",
                    ]
                  : "0 0 0px rgba(168,85,247,0)",
            }}
            transition={inView ? { duration: 2, repeat: Infinity } : { duration: 0.2 }}
            className="flex items-center gap-2 px-3.5 py-2 rounded-xl border border-violet-500/30 bg-violet-500/10"
          >
            <Workflow className="h-4 w-4 text-violet-400" />
            <span className="text-xs font-semibold text-violet-300">
              Mail Hub
            </span>
            {currentStep >= 0 && (
              <motion.span
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                className="flex h-2 w-2 rounded-full bg-emerald-400"
              >
                <motion.span
                  className="h-full w-full rounded-full bg-emerald-400"
                  animate={inView ? { scale: [1, 2, 1], opacity: [1, 0, 1] } : { scale: 1, opacity: 1 }}
                  transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
                />
              </motion.span>
            )}
          </motion.div>
        </div>

        {/* ---- Agent Inbox Cards (3 columns) ---- */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {agents.map((agent) => {
            const isConflictAgent =
              conflict !== null && conflict.agent === agent.id;
            return (
              <AgentInboxCard
                key={agent.id}
                agent={agent}
                isConflictAgent={isConflictAgent}
                conflict={conflict}
                onMessageClick={handleMessageClick}
                active={inView}
              />
            );
          })}
        </div>

        {/* ---- Flying Envelope Animation ---- */}
        <AnimatePresence>
          {flyingEnvelope && (
            <motion.div
              key="flying-envelope"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="flex items-center justify-center py-2"
            >
              <motion.div
                initial={{ x: -80, y: 0, scale: 0.6, rotate: -10 }}
                animate={{
                  x: ["-80px", "0px", "80px"],
                  y: ["0px", "-24px", "0px"],
                  scale: [0.6, 1.1, 0.8],
                  rotate: [-10, 0, 10],
                }}
                transition={{ duration: 1.4, ease: "easeInOut" }}
                className="flex items-center gap-2.5 px-5 py-3 rounded-2xl bg-gradient-to-r from-blue-500/15 to-emerald-500/15 border border-blue-500/30 backdrop-blur-xl shadow-2xl shadow-blue-500/10"
              >
                <motion.div
                  animate={{ rotate: [0, -15, 15, 0] }}
                  transition={{ duration: 0.4, repeat: 3 }}
                >
                  <Mail className="h-5 w-5 text-blue-400" />
                </motion.div>
                <div className="flex flex-col">
                  <span className="text-xs font-semibold text-white/80">
                    {flyingEnvelope.subject}
                  </span>
                  <span className="text-[10px] text-white/40">
                    {getAgentNameById(flyingEnvelope.from)}{" "}
                    <ArrowRight className="inline h-2.5 w-2.5" />{" "}
                    {getAgentNameById(flyingEnvelope.to)}
                  </span>
                </div>
                <Send className="h-4 w-4 text-emerald-400" />
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* ---- File Reservation Map ---- */}
        <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
          <div className="px-5 py-3 border-b border-white/[0.06] bg-gradient-to-r from-white/[0.04] to-transparent flex items-center justify-between">
            <div className="flex items-center gap-2">
              <FileText className="h-4 w-4 text-white/50" />
              <span className="text-sm font-semibold text-white/70">
                File Reservation Map
              </span>
            </div>
            {/* Legend */}
            <div className="hidden sm:flex items-center gap-3">
              {AGENT_CONFIGS.map((a) => (
                <div key={a.id} className="flex items-center gap-1.5">
                  <div
                    className={`h-2.5 w-2.5 rounded-full ${
                      a.bgAccent === 'bg-blue-500' ? 'bg-blue-500/60' :
                      a.bgAccent === 'bg-emerald-500' ? 'bg-emerald-500/60' :
                      a.bgAccent === 'bg-red-500' ? 'bg-red-500/60' : 'bg-white/60'
                    }`}
                  />
                  <span className="text-[10px] text-white/40">{a.name}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-px bg-white/[0.04] p-px">
            {files.map((file) => {
              const ownerColors = getFileOwnerColor(file.owner);
              const ownerName = file.owner
                ? getAgentNameById(file.owner)
                : null;

              return (
                <motion.div
                  key={file.path}
                  animate={{
                    backgroundColor: file.conflictFlash
                      ? [
                          "rgba(239,68,68,0.15)",
                          "rgba(239,68,68,0.03)",
                          "rgba(239,68,68,0.15)",
                        ]
                      : ownerColors.rgbaBg,
                  }}
                  transition={
                    file.conflictFlash
                      ? { duration: 0.3, repeat: 4, repeatType: "reverse" as const }
                      : { duration: 0.4 }
                  }
                  className="relative flex flex-col items-center gap-2 p-4 bg-[#0d1117]/50"
                >
                  {/* File icon */}
                  <motion.div
                    animate={{
                      scale: file.conflictFlash ? [1, 1.15, 1] : 1,
                    }}
                    transition={
                      file.conflictFlash
                        ? { duration: 0.2, repeat: 4 }
                        : { duration: 0.3 }
                    }
                  >
                    <FileText
                      className={`h-5 w-5 ${file.owner ? ownerColors.text : "text-white/20"}`}
                    />
                  </motion.div>

                  {/* File path */}
                  <code className="text-[11px] font-mono text-white/50 text-center leading-tight">
                    {file.path}
                  </code>

                  {/* Lock badge */}
                  <AnimatePresence mode="wait">
                    {file.owner ? (
                      <motion.div
                        key={`locked-${file.owner}`}
                        initial={{ opacity: 0, scale: 0, rotate: -90 }}
                        animate={{ opacity: 1, scale: 1, rotate: 0 }}
                        exit={{ opacity: 0, scale: 0, rotate: 90 }}
                        transition={springSmooth}
                        className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium ${ownerColors.bg} ${ownerColors.text} border ${ownerColors.border}`}
                      >
                        <Lock className="h-2.5 w-2.5" />
                        {ownerName}
                      </motion.div>
                    ) : (
                      <motion.div
                        key="free"
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        className="flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] text-white/20"
                      >
                        <Unlock className="h-2.5 w-2.5" />
                        Free
                      </motion.div>
                    )}
                  </AnimatePresence>

                  {/* Conflict X overlay */}
                  <AnimatePresence>
                    {file.conflictFlash && (
                      <motion.div
                        initial={{ opacity: 0, scale: 0 }}
                        animate={{ opacity: 1, scale: [0, 1.3, 1] }}
                        exit={{ opacity: 0, scale: 0 }}
                        className="absolute top-2 right-2"
                      >
                        <X className="h-4 w-4 text-red-400" />
                      </motion.div>
                    )}
                  </AnimatePresence>
                </motion.div>
              );
            })}
          </div>
        </div>

        {/* ---- Activity Log ---- */}
        <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
          <div className="px-5 py-3 border-b border-white/[0.06] bg-gradient-to-r from-white/[0.04] to-transparent flex items-center gap-2">
            <Clock className="h-4 w-4 text-white/50" />
            <span className="text-sm font-semibold text-white/70">
              Activity Log
            </span>
            {activityLog.length > 0 && (
              <span className="ml-auto text-[10px] text-white/30 font-mono">
                {activityLog.length} event{activityLog.length !== 1 ? "s" : ""}
              </span>
            )}
          </div>
          <div
            ref={logContainerRef}
            className="max-h-[160px] overflow-y-auto scrollbar-thin"
          >
            <AnimatePresence>
              {activityLog.length === 0 && (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="flex items-center justify-center py-6"
                >
                  <p className="text-xs text-white/20 italic">
                    Start the simulation to see activity
                  </p>
                </motion.div>
              )}
              {activityLog.map((entry) => {
                const colors = getLogTypeColor(entry.type);
                return (
                  <motion.div
                    key={entry.id}
                    initial={{ opacity: 0, x: -16, height: 0 }}
                    animate={{ opacity: 1, x: 0, height: "auto" }}
                    transition={springSmooth}
                    className="flex items-center gap-3 px-5 py-2.5 border-b border-white/[0.03] last:border-0"
                  >
                    <span className="text-[10px] font-mono text-white/25 shrink-0 w-14">
                      {entry.timestamp}
                    </span>
                    <div
                      className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-md ${colors.bg}`}
                    >
                      <span className={colors.text}>
                        {entry.type === "conflict" ? (
                          <AlertTriangle className="h-2.5 w-2.5" />
                        ) : entry.type === "reserve" ? (
                          <Lock className="h-2.5 w-2.5" />
                        ) : entry.type === "message" ? (
                          <Send className="h-2.5 w-2.5" />
                        ) : entry.type === "ack" ? (
                          <CheckCircle className="h-2.5 w-2.5" />
                        ) : entry.type === "release" ? (
                          <Unlock className="h-2.5 w-2.5" />
                        ) : (
                          <Bot className="h-2.5 w-2.5" />
                        )}
                      </span>
                    </div>
                    <span
                      className={`text-xs ${entry.type === "conflict" ? "text-red-300 font-semibold" : "text-white/60"}`}
                    >
                      {entry.text}
                    </span>
                  </motion.div>
                );
              })}
            </AnimatePresence>
          </div>
        </div>

        {/* ---- Stepper Controls ---- */}
        <div className="space-y-4 pt-2">
          {/* Step description */}
          <div className="text-center min-h-[3.5rem] flex items-center justify-center">
            <AnimatePresence mode="wait">
              {currentStep >= 0 ? (
                <motion.div
                  key={currentStep}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -12 }}
                  transition={springSmooth}
                  className="space-y-1.5"
                >
                  <div className="flex items-center justify-center gap-2">
                    <span
                      className={`flex h-6 w-6 items-center justify-center rounded-lg ${
                        SIM_STEP_DEFS[currentStep].icon === "conflict"
                          ? "bg-red-500/20 text-red-400"
                          : SIM_STEP_DEFS[currentStep].icon === "ack"
                            ? "bg-emerald-500/20 text-emerald-400"
                            : "bg-primary/20 text-primary"
                      }`}
                    >
                      {STEP_ICON_MAP[SIM_STEP_DEFS[currentStep].icon]}
                    </span>
                    <p className="text-sm font-semibold text-white">
                      Step {currentStep + 1}:{" "}
                      {SIM_STEP_DEFS[currentStep].label}
                    </p>
                  </div>
                  <p className="text-xs text-white/50">
                    {SIM_STEP_DEFS[currentStep].description}
                  </p>
                </motion.div>
              ) : (
                <motion.p
                  key="initial"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="text-sm text-white/40"
                >
                  Press Play or Next to begin the coordination simulation
                </motion.p>
              )}
            </AnimatePresence>
          </div>

          {/* Step progress dots */}
          <div className="flex items-center justify-center gap-2">
            {SIM_STEP_DEFS.map((stepDef, i) => {
              const isActive = i === currentStep;
              const isPast = i < currentStep;
              return (
                <motion.button
                  key={i}
                  onClick={() => {
                    setCurrentStep(i);
                    setIsPlaying(false);
                  }}
                  animate={{
                    scale: isActive ? 1.4 : 1,
                    backgroundColor: isActive
                      ? stepDef.icon === "conflict"
                        ? "rgb(239,68,68)"
                        : "rgb(var(--color-primary))"
                      : isPast
                        ? "rgba(255,255,255,0.35)"
                        : "rgba(255,255,255,0.1)",
                  }}
                  whileHover={{ scale: 1.5 }}
                  transition={springSmooth}
                  className="h-2.5 w-2.5 rounded-full cursor-pointer"
                  aria-label={`Go to step ${i + 1}: ${stepDef.label}`}
                />
              );
            })}
          </div>

          {/* Control buttons */}
          <div className="flex items-center justify-center gap-3">
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={resetSim}
              disabled={currentStep < 0}
              className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl border border-white/[0.1] bg-white/[0.04] text-white/60 text-sm font-medium backdrop-blur-xl transition hover:border-white/[0.2] hover:bg-white/[0.08] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
            >
              <RotateCcw className="h-3.5 w-3.5" />
              Reset
            </motion.button>

            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={goPrev}
              disabled={currentStep < 0}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl border border-white/[0.1] bg-white/[0.04] text-white/60 text-sm font-medium backdrop-blur-xl transition hover:border-white/[0.2] hover:bg-white/[0.08] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
            >
              <ChevronLeft className="h-4 w-4" />
              Prev
            </motion.button>

            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={togglePlay}
              className={`flex items-center gap-1.5 px-6 py-2.5 rounded-xl border text-sm font-semibold backdrop-blur-xl transition ${
                isPlaying
                  ? "border-amber-500/40 bg-amber-500/15 text-amber-300 hover:bg-amber-500/25"
                  : "border-primary/40 bg-primary/15 text-primary hover:bg-primary/25"
              }`}
            >
              {isPlaying ? (
                <>
                  <Pause className="h-4 w-4" />
                  Pause
                </>
              ) : (
                <>
                  <Play className="h-4 w-4" />
                  Play
                </>
              )}
            </motion.button>

            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={goNext}
              disabled={currentStep >= totalSteps - 1}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl border border-white/[0.1] bg-white/[0.04] text-white/60 text-sm font-medium backdrop-blur-xl transition hover:border-white/[0.2] hover:bg-white/[0.08] hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
            >
              Next
              <ChevronRight className="h-4 w-4" />
            </motion.button>
          </div>
        </div>
      </div>

      {/* ---- Thread Viewer Modal ---- */}
      <AnimatePresence>
        {selectedMessage && (
          <ThreadViewer
            message={selectedMessage}
            onClose={() => setSelectedMessage(null)}
          />
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// BEST PRACTICE
// =============================================================================
function BestPractice({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-5 rounded-2xl border border-emerald-500/20 bg-emerald-500/5 backdrop-blur-xl transition duration-300 hover:border-emerald-500/40 hover:bg-emerald-500/10"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/20 text-emerald-400 shadow-lg shadow-emerald-500/10 group-hover:shadow-emerald-500/20 transition-shadow">
        <CheckCircle className="h-5 w-5" />
      </div>
      <div>
        <p className="font-semibold text-white group-hover:text-emerald-300 transition-colors">{title}</p>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FUNCTION ROW
// =============================================================================
function FunctionRow({ name, purpose }: { name: string; purpose: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-4 transition duration-200 hover:bg-white/[0.02]"
    >
      <code className="text-sm text-primary font-mono font-medium px-3 py-1.5 rounded-lg bg-primary/10 border border-primary/20 group-hover:bg-primary/15 transition-colors">
        {name}
      </code>
      <span className="text-white/50 text-sm group-hover:text-white/70 transition-colors">{purpose}</span>
    </motion.div>
  );
}
