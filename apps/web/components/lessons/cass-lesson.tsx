"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import {
  Search,
  History,
  Database,
  Terminal,
  Bot,
  FileSearch,
  Filter,
  Sparkles,
  Book,
  Zap,
  ChevronLeft,
  ChevronRight,
  Play,
  Loader2,
  GitBranch,
  Clock,
  ArrowRight,
  Network,
  Tag,
  Eye,
  X,
  AlertTriangle,
  CheckCircle,
  Copy,
  BarChart3,
  Lightbulb,
  Layers,
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
import { copyTextToClipboard } from "@/lib/utils";

export function CassLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Search across all past agent sessions to reuse solved problems.
      </GoalBanner>

      {/* What Is CASS */}
      <Section
        title="What Is CASS?"
        icon={<Search className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          <Highlight>CASS (Coding Agent Session Search)</Highlight> indexes all
          your past agent conversations—Claude Code, Codex, Antigravity, Cursor, and
          more—so you can find solutions to problems you&apos;ve already solved.
        </Paragraph>
        <Paragraph>
          It&apos;s like having a searchable memory of everything your agents
          have ever done across all projects.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Database className="h-5 w-5" />}
              title="Multi-Agent Index"
              description="Claude, Codex, Antigravity/Gemini, Cursor, ChatGPT sessions"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<FileSearch className="h-5 w-5" />}
              title="Full-Text Search"
              description="Search across code, prompts, and responses"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<History className="h-5 w-5" />}
              title="Cross-Project"
              description="Find solutions from any project or machine"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fast Retrieval"
              description="Instant results with context snippets"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Why Use CASS */}
      <Section
        title="Why Use CASS?"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          You&apos;ve likely solved many problems before with agents. Without
          CASS:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <UseCaseCard
            problem="You hit an error you've seen before but can't remember the fix"
            solution="Search CASS for the error message → find the exact solution"
          />
          <UseCaseCard
            problem="New project needs auth—you've implemented it before"
            solution="Search 'authentication' → find your past implementation"
          />
          <UseCaseCard
            problem="Different agent solved a similar problem better"
            solution="Search across all agents → find the best approach"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            CASS helps you avoid re-solving the same problems. Your past agent
            sessions are a goldmine of solutions!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Essential Commands */}
      <Section
        title="Essential Commands"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          <strong>Important:</strong> Never run bare <code>cass</code>—it
          launches a TUI that may block your session. Always use{" "}
          <code>--robot</code> or <code>--json</code>.
        </Paragraph>

        <div className="mt-6">
          <CommandList
            commands={[
              {
                command: "cass health",
                description: "Check indexing status",
              },
              {
                command: 'cass search "auth error" --robot --limit 5',
                description: "Search with machine-readable output",
              },
              {
                command: "cass view /path/to/session.jsonl -n 42 --json",
                description: "View a specific message",
              },
              {
                command: "cass expand /path/to/session.jsonl -n 42 -C 3 --json",
                description: "View with context (3 messages before/after)",
              },
              {
                command: "cass capabilities --json",
                description: "See what agents are indexed",
              },
              {
                command: "cass robot-docs guide",
                description: "Full documentation for AI agents",
              },
            ]}
          />
        </div>
      </Section>

      <Divider />

      {/* Search Patterns */}
      <Section
        title="Search Patterns"
        icon={<Filter className="h-5 w-5" />}
        delay={0.25}
      >
        <div className="space-y-6">
          <SearchPattern
            title="Basic Search"
            description="Find any mention of a term"
            code='cass search "database migration" --robot'
          />

          <SearchPattern
            title="Filter by Agent"
            description="Only search Claude Code sessions"
            code='cass search "error handling" --agent claude --robot'
          />

          <SearchPattern
            title="Recent Only"
            description="Search last 7 days"
            code='cass search "docker" --days 7 --robot'
          />

          <SearchPattern
            title="Minimal Output"
            description="Just essential fields"
            code='cass search "auth" --robot --fields minimal --limit 10'
          />

          <SearchPattern
            title="Error Messages"
            description="Find solutions to specific errors"
            code='cass search "Cannot read property of undefined" --robot'
          />
        </div>
      </Section>

      <Divider />

      {/* The Search Workflow */}
      <Section
        title="The Search Workflow"
        icon={<Zap className="h-5 w-5" />}
        delay={0.3}
      >
        <InteractiveSessionSearch />
      </Section>

      <Divider />

      {/* Output Format */}
      <Section
        title="Understanding Output"
        icon={<FileSearch className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          CASS returns structured results with session info and snippets:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`$ cass search "PostgreSQL connection" --robot --limit 2

{
  "hits": [
    {
      "source_path": "/home/ubuntu/.claude/projects/.../session.jsonl",
      "line_number": 87,
      "agent": "claude_code",
      "workspace": "/projects/myapp",
      "snippet": "...fixed the PostgreSQL connection by setting pool_size=20...",
      "score": 0.92
    },
    {
      "source_path": "/home/ubuntu/.codex/sessions/2025-01-12.jsonl",
      "line_number": 45,
      "agent": "codex",
      "workspace": "/projects/backend",
      "snippet": "...PostgreSQL connection string format: postgres://user:pass...",
      "score": 0.85
    }
  ],
  "_meta": { "query": "PostgreSQL connection", "took_ms": 42 }
}`}
            language="json"
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Use <code>cass expand</code> with the source path and line
            number to see the full conversation context!
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Best Practices */}
      <Section
        title="Best Practices"
        icon={<Book className="h-5 w-5" />}
        delay={0.4}
      >
        <div className="space-y-4">
          <BestPractice
            title="Use specific search terms"
            description="'PostgreSQL timeout error' is better than just 'error'"
          />
          <BestPractice
            title="Filter by agent for focused results"
            description="If you remember which agent solved it, use --agent"
          />
          <BestPractice
            title="Check multiple solutions"
            description="Different agents may have solved it differently"
          />
          <BestPractice
            title="Use --days for recent context"
            description="Older solutions might use outdated patterns"
          />
        </div>
      </Section>

      <Divider />

      {/* Try It Now */}
      <Section
        title="Try It Now"
        icon={<Terminal className="h-5 w-5" />}
        delay={0.45}
      >
        <CodeBlock
          code={`# Check your indexing status
$ cass health

# Search for a common pattern
$ cass search "import" --robot --limit 3

# View full documentation
$ cass robot-docs guide`}
          showLineNumbers
        />
      </Section>
    </div>
  );
}

// =============================================================================
// USE CASE CARD
// =============================================================================
function UseCaseCard({
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
      whileHover={{ y: -4, scale: 1.02 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl overflow-hidden transition-all duration-500 hover:border-white/[0.15]"
    >
      {/* Gradient overlay on hover */}
      <div className="absolute inset-0 bg-gradient-to-br from-red-500/5 via-transparent to-emerald-500/5 opacity-0 group-hover:opacity-100 transition-opacity duration-500" />

      <div className="relative flex items-start gap-4 mb-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-red-500/20 text-red-400">
          ✗
        </div>
        <p className="text-white/60 pt-1">{problem}</p>
      </div>
      <div className="relative flex items-start gap-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400">
          ✓
        </div>
        <p className="text-white/80 font-medium pt-1">{solution}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// SEARCH PATTERN
// =============================================================================
function SearchPattern({
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
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2 }}
      className="group space-y-3 p-5 rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-300 hover:border-white/[0.12] hover:bg-white/[0.04]"
    >
      <div>
        <h4 className="font-semibold text-white group-hover:text-primary transition-colors">{title}</h4>
        <p className="text-sm text-white/50">{description}</p>
      </div>
      <CodeBlock code={code} />
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE SESSION SEARCH - DRAMATICALLY ENHANCED
// =============================================================================

type AgentType = "claude" | "codex" | "gemini" | "cursor";

interface SearchHit {
  id: string;
  agent: AgentType;
  agentLabel: string;
  sessionPath: string;
  workspace: string;
  score: number;
  snippet: string;
  matchHighlights: string[];
  timestamp: string;
  lineNumber: number;
  expandedContext: string[];
  tags: string[];
}

interface TimelineEvent {
  agent: AgentType;
  agentLabel: string;
  date: string;
  summary: string;
  sessionRef: string;
}

interface KnowledgeNode {
  label: string;
  category: "pattern" | "solution" | "error" | "tool";
  connections: number[];
}

interface SearchScenario {
  id: string;
  label: string;
  icon: "error" | "prompt" | "solution" | "compare" | "timeline" | "knowledge";
  query: string;
  command: string;
  description: string;
  hits: SearchHit[];
  timeline: TimelineEvent[];
  knowledgeNodes: KnowledgeNode[];
  stats: {
    sessionsSearched: number;
    totalHits: number;
    agents: number;
    tookMs: number;
  };
}

const AGENT_STYLES: Record<
  AgentType,
  {
    border: string;
    bg: string;
    text: string;
    gradient: string;
    glow: string;
    ring: string;
    dot: string;
  }
> = {
  claude: {
    border: "border-l-orange-400",
    bg: "bg-orange-500/10",
    text: "text-orange-400",
    gradient: "from-orange-500 to-amber-500",
    glow: "shadow-orange-500/20",
    ring: "ring-orange-400/30",
    dot: "bg-orange-400",
  },
  codex: {
    border: "border-l-emerald-400",
    bg: "bg-emerald-500/10",
    text: "text-emerald-400",
    gradient: "from-emerald-500 to-teal-500",
    glow: "shadow-emerald-500/20",
    ring: "ring-emerald-400/30",
    dot: "bg-emerald-400",
  },
  gemini: {
    border: "border-l-blue-400",
    bg: "bg-blue-500/10",
    text: "text-blue-400",
    gradient: "from-blue-500 to-indigo-500",
    glow: "shadow-blue-500/20",
    ring: "ring-blue-400/30",
    dot: "bg-blue-400",
  },
  cursor: {
    border: "border-l-purple-400",
    bg: "bg-purple-500/10",
    text: "text-purple-400",
    gradient: "from-purple-500 to-pink-500",
    glow: "shadow-purple-500/20",
    ring: "ring-purple-400/30",
    dot: "bg-purple-400",
  },
};

const SCENARIO_ICONS = {
  error: AlertTriangle,
  prompt: Terminal,
  solution: Lightbulb,
  compare: GitBranch,
  timeline: Clock,
  knowledge: Network,
} as const;

const SEARCH_SCENARIOS: SearchScenario[] = [
  {
    id: "error-search",
    label: "Error Search",
    icon: "error",
    query: "ECONNREFUSED PostgreSQL",
    command: 'cass search "ECONNREFUSED PostgreSQL" --robot --limit 5',
    description: "Find past solutions for specific error messages across all agent sessions",
    hits: [
      {
        id: "e1",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/backend/session-2026-03-08.jsonl",
        workspace: "/projects/backend-api",
        score: 0.96,
        snippet: "Error: connect ECONNREFUSED 127.0.0.1:5432 - Fixed by restarting PostgreSQL service and updating pg_hba.conf to allow local connections",
        matchHighlights: ["ECONNREFUSED", "PostgreSQL"],
        timestamp: "2026-03-08T14:23:00Z",
        lineNumber: 87,
        expandedContext: [
          "user: My API tests are failing with connection refused errors",
          "user: Error: connect ECONNREFUSED 127.0.0.1:5432",
          "assistant: Let me check the PostgreSQL service status...",
          "assistant: The service is stopped. Let me also check pg_hba.conf...",
          ">>> Fixed by: 1) sudo systemctl start postgresql 2) Updated pg_hba.conf to use 'md5' instead of 'peer' for local connections",
          "assistant: I also added a health check to your docker-compose.yml so the app waits for PG to be ready",
          "user: All tests passing now, thanks!",
        ],
        tags: ["database", "connection", "postgresql"],
      },
      {
        id: "e2",
        agent: "codex",
        agentLabel: "Codex",
        sessionPath: "~/.codex/sessions/2026-02-22.jsonl",
        workspace: "/projects/microservices",
        score: 0.89,
        snippet: "ECONNREFUSED on PostgreSQL - root cause was Docker network misconfiguration, container using wrong hostname",
        matchHighlights: ["ECONNREFUSED", "PostgreSQL"],
        timestamp: "2026-02-22T09:15:00Z",
        lineNumber: 134,
        expandedContext: [
          "user: Database connection fails in Docker container",
          "user: Error: connect ECONNREFUSED 127.0.0.1:5432",
          "assistant: In Docker, localhost refers to the container itself, not the host...",
          ">>> Fixed by changing DB_HOST from 'localhost' to the Docker service name 'postgres' in docker-compose.yml",
          "assistant: Also added depends_on with health check condition",
          "user: That was the issue, works now",
        ],
        tags: ["docker", "networking", "postgresql"],
      },
      {
        id: "e3",
        agent: "cursor",
        agentLabel: "Cursor",
        sessionPath: "~/.cursor/sessions/session-2026-03-01.jsonl",
        workspace: "/projects/saas-app",
        score: 0.82,
        snippet: "PostgreSQL ECONNREFUSED after system reboot - added systemd service enable and connection retry with exponential backoff",
        matchHighlights: ["PostgreSQL", "ECONNREFUSED"],
        timestamp: "2026-03-01T16:40:00Z",
        lineNumber: 203,
        expandedContext: [
          "user: App crashes on server reboot, can't connect to postgres",
          "assistant: PostgreSQL service isn't set to start on boot...",
          ">>> Fixed with: sudo systemctl enable postgresql && added retry logic with exponential backoff in db.ts",
          "assistant: The retry function attempts 5 reconnections with 1s, 2s, 4s, 8s, 16s delays",
          "user: Perfect, survives reboots now",
        ],
        tags: ["systemd", "retry-logic", "postgresql"],
      },
    ],
    timeline: [
      { agent: "cursor", agentLabel: "Cursor", date: "Mar 1", summary: "Systemd enable + retry logic", sessionRef: "e3" },
      { agent: "codex", agentLabel: "Codex", date: "Feb 22", summary: "Docker network hostname fix", sessionRef: "e2" },
      { agent: "claude", agentLabel: "Claude Code", date: "Mar 8", summary: "pg_hba.conf + service restart", sessionRef: "e1" },
    ],
    knowledgeNodes: [
      { label: "ECONNREFUSED", category: "error", connections: [1, 2, 3] },
      { label: "pg_hba.conf", category: "solution", connections: [0, 4] },
      { label: "Docker networking", category: "solution", connections: [0, 5] },
      { label: "systemctl enable", category: "solution", connections: [0, 4] },
      { label: "PostgreSQL config", category: "tool", connections: [1, 3] },
      { label: "docker-compose", category: "tool", connections: [2] },
    ],
    stats: { sessionsSearched: 847, totalHits: 3, agents: 3, tookMs: 38 },
  },
  {
    id: "prompt-patterns",
    label: "Prompt Mining",
    icon: "prompt",
    query: "implement authentication",
    command: 'cass search "implement authentication" --robot --fields full',
    description: "Mine effective prompts and patterns from past sessions to reuse winning strategies",
    hits: [
      {
        id: "p1",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/webapp/session-2026-03-01.jsonl",
        workspace: "/projects/nextjs-saas",
        score: 0.97,
        snippet: "Implemented OAuth2 PKCE flow with refresh token rotation, httpOnly cookies, and CSRF protection middleware",
        matchHighlights: ["implement", "authentication"],
        timestamp: "2026-03-01T10:30:00Z",
        lineNumber: 203,
        expandedContext: [
          "user: Implement authentication for this Next.js app using Google OAuth",
          "user: Requirements: secure token storage, refresh tokens, CSRF protection",
          "assistant: I'll implement OAuth2 with PKCE flow for maximum security...",
          ">>> Created: auth/providers/google.ts, middleware/csrf.ts, lib/tokens.ts with httpOnly cookie storage and automatic token rotation",
          "assistant: Key security measures: 1) PKCE prevents auth code interception 2) httpOnly cookies prevent XSS 3) Refresh rotation prevents token theft",
          "user: The login flow is working perfectly, very secure",
        ],
        tags: ["oauth2", "pkce", "next.js", "security"],
      },
      {
        id: "p2",
        agent: "gemini",
        agentLabel: "Gemini",
        sessionPath: "~/.gemini/sessions/2026-02-18.jsonl",
        workspace: "/projects/express-api",
        score: 0.91,
        snippet: "JWT authentication with role-based access control, rate limiting on login, and bcrypt password hashing",
        matchHighlights: ["authentication"],
        timestamp: "2026-02-18T14:15:00Z",
        lineNumber: 67,
        expandedContext: [
          "user: Add JWT authentication to this Express API with admin/user roles",
          "assistant: Setting up JWT auth with RBAC...",
          ">>> Created: middleware/auth.ts with authenticate(), requireRole(), and optionalAuth() functions. Passwords hashed with bcrypt (12 rounds)",
          "assistant: Rate limiting set to 5 login attempts per 15 min per IP using express-rate-limit",
          "user: Works great with the existing routes",
        ],
        tags: ["jwt", "rbac", "express", "rate-limiting"],
      },
      {
        id: "p3",
        agent: "codex",
        agentLabel: "Codex",
        sessionPath: "~/.codex/sessions/2026-01-30.jsonl",
        workspace: "/projects/python-api",
        score: 0.85,
        snippet: "Session-based auth with Redis store, implemented magic link email login instead of passwords",
        matchHighlights: ["authentication"],
        timestamp: "2026-01-30T11:00:00Z",
        lineNumber: 312,
        expandedContext: [
          "user: implement passwordless authentication using magic links",
          "assistant: Implementing magic link auth with Redis session store...",
          ">>> Created: auth/magic_link.py with email token generation (SHA256, 15min expiry), Redis session management, and secure cookie config",
          "assistant: The flow: user enters email -> receives link -> clicks link -> session created in Redis",
          "user: Clean and simple, love it",
        ],
        tags: ["magic-link", "redis", "python", "passwordless"],
      },
    ],
    timeline: [
      { agent: "codex", agentLabel: "Codex", date: "Jan 30", summary: "Magic link + Redis sessions", sessionRef: "p3" },
      { agent: "gemini", agentLabel: "Gemini", date: "Feb 18", summary: "JWT + RBAC + rate limiting", sessionRef: "p2" },
      { agent: "claude", agentLabel: "Claude Code", date: "Mar 1", summary: "OAuth2 PKCE + token rotation", sessionRef: "p1" },
    ],
    knowledgeNodes: [
      { label: "Authentication", category: "pattern", connections: [1, 2, 3, 4] },
      { label: "OAuth2 PKCE", category: "solution", connections: [0, 5] },
      { label: "JWT + RBAC", category: "solution", connections: [0, 5] },
      { label: "Magic Links", category: "solution", connections: [0, 4] },
      { label: "Redis Sessions", category: "tool", connections: [0, 3] },
      { label: "Token Security", category: "pattern", connections: [1, 2] },
    ],
    stats: { sessionsSearched: 847, totalHits: 3, agents: 3, tookMs: 42 },
  },
  {
    id: "solution-mining",
    label: "Solution Mining",
    icon: "solution",
    query: "React performance optimization",
    command: 'cass search "React performance optimization" --robot --limit 5',
    description: "Extract proven solutions and optimization techniques from past agent work",
    hits: [
      {
        id: "s1",
        agent: "gemini",
        agentLabel: "Gemini",
        sessionPath: "~/.gemini/sessions/2026-03-05.jsonl",
        workspace: "/projects/dashboard",
        score: 0.94,
        snippet: "Optimized 10k-row table from 2.3s to 16ms render using react-window virtualization, useMemo for filter logic, and debounced input",
        matchHighlights: ["React", "performance", "optimization"],
        timestamp: "2026-03-05T09:45:00Z",
        lineNumber: 89,
        expandedContext: [
          "user: This data table with 10k rows is extremely slow",
          "user: Every keystroke in the filter causes full re-render",
          "assistant: I see several performance issues. Let me profile...",
          ">>> Key optimizations: 1) react-window FixedSizeList for virtualization 2) useMemo on filtered data 3) 150ms debounced filter input 4) React.memo on row component",
          "assistant: Render time: 2.3s -> 16ms. Bundle also smaller since we only render ~20 visible rows",
          "user: Incredible improvement!",
        ],
        tags: ["virtualization", "react-window", "useMemo", "debounce"],
      },
      {
        id: "s2",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/ecommerce/session-2026-02-25.jsonl",
        workspace: "/projects/ecommerce-frontend",
        score: 0.88,
        snippet: "Eliminated unnecessary re-renders with useCallback for event handlers, React.memo with custom comparator, and context splitting",
        matchHighlights: ["React", "performance"],
        timestamp: "2026-02-25T13:20:00Z",
        lineNumber: 445,
        expandedContext: [
          "user: Product listing page re-renders everything when cart updates",
          "assistant: The cart context is causing cascade re-renders...",
          ">>> Split CartContext into CartItemsContext and CartActionsContext. Wrapped product cards in React.memo with shallow compare. Used useCallback for all handlers.",
          "assistant: Re-renders went from 847 components to just 3 (cart icon + badge + count)",
          "user: Smooth as butter now",
        ],
        tags: ["context-splitting", "React.memo", "useCallback"],
      },
    ],
    timeline: [
      { agent: "claude", agentLabel: "Claude Code", date: "Feb 25", summary: "Context splitting + memo", sessionRef: "s2" },
      { agent: "gemini", agentLabel: "Gemini", date: "Mar 5", summary: "Virtualization + debounce", sessionRef: "s1" },
    ],
    knowledgeNodes: [
      { label: "React Performance", category: "pattern", connections: [1, 2, 3, 4] },
      { label: "Virtualization", category: "solution", connections: [0, 3] },
      { label: "Context Splitting", category: "solution", connections: [0, 4] },
      { label: "react-window", category: "tool", connections: [0, 1] },
      { label: "React.memo", category: "tool", connections: [0, 2] },
    ],
    stats: { sessionsSearched: 847, totalHits: 2, agents: 2, tookMs: 31 },
  },
  {
    id: "cross-agent",
    label: "Cross-Agent",
    icon: "compare",
    query: "Docker multi-stage build",
    command: 'cass search "Docker multi-stage build" --robot --compare',
    description: "Compare how different agents approached the same problem to find the best solution",
    hits: [
      {
        id: "c1",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/infra/session-2026-02-28.jsonl",
        workspace: "/projects/production-deploy",
        score: 0.93,
        snippet: "Multi-stage Docker build: builder stage for compilation, slim runtime stage. Image size reduced from 1.2GB to 89MB",
        matchHighlights: ["Docker", "multi-stage", "build"],
        timestamp: "2026-02-28T15:10:00Z",
        lineNumber: 156,
        expandedContext: [
          "user: Docker image is 1.2GB for a simple Node.js app",
          "assistant: Let me restructure the Dockerfile with multi-stage build...",
          ">>> Stage 1 (builder): node:20 for npm ci + build. Stage 2 (runtime): node:20-slim with only production deps. Image: 1.2GB -> 89MB",
          "assistant: Also added .dockerignore to exclude node_modules, .git, and test files",
          "user: Deploy time went from 4 min to 30 seconds!",
        ],
        tags: ["multi-stage", "image-size", "node.js"],
      },
      {
        id: "c2",
        agent: "codex",
        agentLabel: "Codex",
        sessionPath: "~/.codex/sessions/2026-03-10.jsonl",
        workspace: "/projects/backend-v2",
        score: 0.87,
        snippet: "Docker BuildKit multi-stage with cache mounts for node_modules - rebuilds in 8s instead of 3min by caching npm install layer",
        matchHighlights: ["Docker", "multi-stage", "build"],
        timestamp: "2026-03-10T11:30:00Z",
        lineNumber: 45,
        expandedContext: [
          "user: Docker rebuilds take forever even for tiny code changes",
          "assistant: Using BuildKit cache mounts with multi-stage...",
          ">>> RUN --mount=type=cache,target=/root/.npm npm ci -> caches npm downloads. COPY package*.json before source -> caches install layer. Result: 3min -> 8s rebuild",
          "assistant: The cache mount persists across builds, so npm ci only downloads new/changed packages",
          "user: Game changer for development iteration speed",
        ],
        tags: ["buildkit", "cache-mounts", "layer-caching"],
      },
      {
        id: "c3",
        agent: "gemini",
        agentLabel: "Gemini",
        sessionPath: "~/.gemini/sessions/2026-02-14.jsonl",
        workspace: "/projects/monorepo",
        score: 0.78,
        snippet: "Docker multi-stage for monorepo: used turbo prune to only include relevant packages, reducing context from 8GB to 200MB",
        matchHighlights: ["Docker", "multi-stage"],
        timestamp: "2026-02-14T08:00:00Z",
        lineNumber: 201,
        expandedContext: [
          "user: Docker build in our monorepo sends 8GB of context",
          "assistant: Using turbo prune to create a minimal Docker context...",
          ">>> Stage 1: turbo prune --scope=@app/web --docker. Stage 2: install pruned deps. Stage 3: build. Stage 4: slim runtime. Context: 8GB -> 200MB",
          "assistant: Each stage only copies what it needs from the previous stage",
          "user: CI pipeline is 5x faster now",
        ],
        tags: ["monorepo", "turborepo", "prune"],
      },
    ],
    timeline: [
      { agent: "gemini", agentLabel: "Gemini", date: "Feb 14", summary: "Monorepo turbo prune", sessionRef: "c3" },
      { agent: "claude", agentLabel: "Claude Code", date: "Feb 28", summary: "Slim runtime stage (89MB)", sessionRef: "c1" },
      { agent: "codex", agentLabel: "Codex", date: "Mar 10", summary: "BuildKit cache mounts", sessionRef: "c2" },
    ],
    knowledgeNodes: [
      { label: "Multi-stage Build", category: "pattern", connections: [1, 2, 3] },
      { label: "Image Slimming", category: "solution", connections: [0, 4] },
      { label: "BuildKit Caching", category: "solution", connections: [0, 4] },
      { label: "Monorepo Pruning", category: "solution", connections: [0, 5] },
      { label: "Dockerfile", category: "tool", connections: [1, 2] },
      { label: "Turborepo", category: "tool", connections: [3] },
    ],
    stats: { sessionsSearched: 847, totalHits: 3, agents: 3, tookMs: 45 },
  },
  {
    id: "timeline-recon",
    label: "Timeline",
    icon: "timeline",
    query: "database migration",
    command: 'cass search "database migration" --robot --sort date',
    description: "Reconstruct a timeline of how a problem evolved across sessions and agents",
    hits: [
      {
        id: "t1",
        agent: "codex",
        agentLabel: "Codex",
        sessionPath: "~/.codex/sessions/2026-01-15.jsonl",
        workspace: "/projects/api-v1",
        score: 0.91,
        snippet: "Set up Prisma migrations with seed data. Created initial schema with User, Post, Comment models",
        matchHighlights: ["database", "migration"],
        timestamp: "2026-01-15T10:00:00Z",
        lineNumber: 23,
        expandedContext: [
          "user: Set up database schema for our blog API",
          "assistant: I'll use Prisma for schema management and migrations...",
          ">>> Created prisma/schema.prisma with User, Post, Comment models. Ran prisma migrate dev --name init. Added seed.ts with test data.",
          "assistant: Migration files are version-controlled so the team stays in sync",
          "user: Clean setup, seed data works",
        ],
        tags: ["prisma", "schema", "initial-setup"],
      },
      {
        id: "t2",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/api-v1/session-2026-02-10.jsonl",
        workspace: "/projects/api-v1",
        score: 0.87,
        snippet: "Added migration for tags system with many-to-many relation. Fixed Prisma migrate deploy failing in CI due to missing DATABASE_URL",
        matchHighlights: ["migration"],
        timestamp: "2026-02-10T14:30:00Z",
        lineNumber: 178,
        expandedContext: [
          "user: Add a tags feature to posts, many-to-many relationship",
          "user: Also our CI migrations keep failing",
          "assistant: Creating the Tag model and junction table...",
          ">>> Migration: added Tag model + _PostToTag junction. CI fix: added DATABASE_URL to GitHub Actions secrets and used prisma migrate deploy (not dev) in CI",
          "assistant: The distinction: 'migrate dev' generates new migrations, 'migrate deploy' only applies existing ones",
          "user: CI pipeline green again, tags working",
        ],
        tags: ["prisma", "many-to-many", "ci-cd"],
      },
      {
        id: "t3",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/api-v1/session-2026-03-06.jsonl",
        workspace: "/projects/api-v1",
        score: 0.83,
        snippet: "Zero-downtime migration strategy: expand-contract pattern for renaming columns without breaking production",
        matchHighlights: ["migration"],
        timestamp: "2026-03-06T16:45:00Z",
        lineNumber: 312,
        expandedContext: [
          "user: Need to rename 'username' to 'handle' without downtime",
          "assistant: Using the expand-contract migration pattern...",
          ">>> Step 1: Add 'handle' column (expand). Step 2: Backfill data + dual-write in app. Step 3: Switch reads to 'handle'. Step 4: Remove 'username' (contract). Each step is a separate migration.",
          "assistant: This ensures zero downtime because the old column exists throughout the transition",
          "user: Deployed all 4 migrations over 2 days, no issues",
        ],
        tags: ["zero-downtime", "expand-contract", "production"],
      },
    ],
    timeline: [
      { agent: "codex", agentLabel: "Codex", date: "Jan 15", summary: "Initial Prisma schema setup", sessionRef: "t1" },
      { agent: "claude", agentLabel: "Claude Code", date: "Feb 10", summary: "Tags migration + CI fix", sessionRef: "t2" },
      { agent: "claude", agentLabel: "Claude Code", date: "Mar 6", summary: "Zero-downtime column rename", sessionRef: "t3" },
    ],
    knowledgeNodes: [
      { label: "DB Migrations", category: "pattern", connections: [1, 2, 3] },
      { label: "Prisma", category: "tool", connections: [0, 2] },
      { label: "Expand-Contract", category: "pattern", connections: [0, 3] },
      { label: "Zero-Downtime", category: "solution", connections: [0, 2] },
    ],
    stats: { sessionsSearched: 847, totalHits: 3, agents: 2, tookMs: 36 },
  },
  {
    id: "knowledge-extract",
    label: "Knowledge",
    icon: "knowledge",
    query: "testing strategies",
    command: 'cass search "testing strategies" --robot --extract-patterns',
    description: "Extract reusable knowledge patterns and best practices from agent sessions",
    hits: [
      {
        id: "k1",
        agent: "claude",
        agentLabel: "Claude Code",
        sessionPath: "~/.claude/projects/webapp/session-2026-03-02.jsonl",
        workspace: "/projects/webapp",
        score: 0.95,
        snippet: "Testing pyramid: 70% unit (vitest), 20% integration (supertest), 10% e2e (playwright). Achieved 94% coverage with meaningful tests",
        matchHighlights: ["testing", "strategies"],
        timestamp: "2026-03-02T11:20:00Z",
        lineNumber: 156,
        expandedContext: [
          "user: Our test suite is slow and brittle, mostly e2e tests",
          "assistant: Let me restructure following the testing pyramid...",
          ">>> Converted 80% of e2e tests to unit/integration. Unit: vitest + testing-library. Integration: supertest for API routes. E2e: playwright for critical user flows only.",
          "assistant: Test suite now runs in 45s instead of 12 minutes. Coverage went from 67% to 94%",
          "user: Tests are so much faster and more reliable now",
        ],
        tags: ["testing-pyramid", "vitest", "playwright"],
      },
      {
        id: "k2",
        agent: "cursor",
        agentLabel: "Cursor",
        sessionPath: "~/.cursor/sessions/session-2026-02-20.jsonl",
        workspace: "/projects/api",
        score: 0.88,
        snippet: "Contract testing between microservices using Pact. Prevents integration failures by validating API contracts independently",
        matchHighlights: ["testing"],
        timestamp: "2026-02-20T09:30:00Z",
        lineNumber: 89,
        expandedContext: [
          "user: Our microservices keep breaking each other's APIs",
          "assistant: Implementing contract testing with Pact...",
          ">>> Consumer-driven contracts: each service defines what it expects. Pact broker verifies contracts on every PR. Catches breaking changes before merge.",
          "assistant: Added pact tests for 3 critical service boundaries",
          "user: No more surprise integration failures in staging",
        ],
        tags: ["contract-testing", "pact", "microservices"],
      },
      {
        id: "k3",
        agent: "gemini",
        agentLabel: "Gemini",
        sessionPath: "~/.gemini/sessions/2026-03-09.jsonl",
        workspace: "/projects/mobile-app",
        score: 0.82,
        snippet: "Snapshot testing with jest for UI regression. Auto-update snapshots in CI only when visual review is approved",
        matchHighlights: ["testing"],
        timestamp: "2026-03-09T15:00:00Z",
        lineNumber: 234,
        expandedContext: [
          "user: We need to catch visual regressions without manual QA",
          "assistant: Setting up snapshot testing workflow...",
          ">>> Jest snapshots for component structure + Chromatic for visual diffs. CI blocks merge on unapproved visual changes. Auto-accept on label 'visual-approved'.",
          "assistant: This gives you automated visual QA without slowing down the pipeline",
          "user: Caught 3 regressions in the first week",
        ],
        tags: ["snapshot-testing", "visual-regression", "chromatic"],
      },
    ],
    timeline: [
      { agent: "cursor", agentLabel: "Cursor", date: "Feb 20", summary: "Contract testing with Pact", sessionRef: "k2" },
      { agent: "claude", agentLabel: "Claude Code", date: "Mar 2", summary: "Testing pyramid restructure", sessionRef: "k1" },
      { agent: "gemini", agentLabel: "Gemini", date: "Mar 9", summary: "Snapshot + visual regression", sessionRef: "k3" },
    ],
    knowledgeNodes: [
      { label: "Testing Strategy", category: "pattern", connections: [1, 2, 3, 4] },
      { label: "Testing Pyramid", category: "pattern", connections: [0, 5] },
      { label: "Contract Testing", category: "solution", connections: [0, 4] },
      { label: "Visual Regression", category: "solution", connections: [0, 5] },
      { label: "Pact", category: "tool", connections: [2] },
      { label: "Vitest / Playwright", category: "tool", connections: [1, 3] },
    ],
    stats: { sessionsSearched: 847, totalHits: 3, agents: 3, tookMs: 41 },
  },
];

type ViewTab = "results" | "timeline" | "knowledge";

const SEARCH_DELAY_MS = 1500;

function InteractiveSessionSearch() {
  const [activeScenarioIdx, setActiveScenarioIdx] = useState(0);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [expandedHit, setExpandedHit] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<ViewTab>("results");
  const [terminalLines, setTerminalLines] = useState<string[]>([]);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [searchProgress, setSearchProgress] = useState(0);
  const searchTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pendingTimersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const scenario = SEARCH_SCENARIOS[activeScenarioIdx];

  const pushTimer = useCallback((t: ReturnType<typeof setTimeout>) => {
    pendingTimersRef.current.push(t);
  }, []);

  const clearAllTimers = useCallback(() => {
    if (searchTimerRef.current) {
      clearInterval(searchTimerRef.current);
      searchTimerRef.current = null;
    }
    for (const t of pendingTimersRef.current) clearTimeout(t);
    pendingTimersRef.current = [];
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearAllTimers();
    };
  }, [clearAllTimers]);

  const runSearch = useCallback(
    (index: number) => {
      clearAllTimers();
      const sc = SEARCH_SCENARIOS[index];
      setActiveScenarioIdx(index);
      setSearching(true);
      setHasSearched(false);
      setExpandedHit(null);
      setActiveTab("results");
      setSearchProgress(0);

      // Animated terminal output
      setTerminalLines([`$ ${sc.command}`]);
      pushTimer(setTimeout(() => {
        setTerminalLines((prev) => [
          ...prev,
          `Searching ${sc.stats.sessionsSearched} indexed sessions...`,
        ]);
      }, 300));
      pushTimer(setTimeout(() => {
        setTerminalLines((prev) => [
          ...prev,
          `Scanning ${sc.stats.agents} agents: claude, codex, gemini, cursor`,
        ]);
      }, 600));

      // Progress bar animation
      const progressInterval = setInterval(() => {
        setSearchProgress((prev) => {
          if (prev >= 100) {
            clearInterval(progressInterval);
            return 100;
          }
          return prev + 4;
        });
      }, 50);
      searchTimerRef.current = progressInterval;

      pushTimer(setTimeout(() => {
        clearInterval(progressInterval);
        searchTimerRef.current = null;
        setSearchProgress(100);
        setTerminalLines((prev) => [
          ...prev,
          `Found ${sc.stats.totalHits} hits across ${sc.stats.agents} agents (${sc.stats.tookMs}ms)`,
          "",
        ]);
        setSearching(false);
        setHasSearched(true);
      }, SEARCH_DELAY_MS));
    },
    [clearAllTimers, pushTimer]
  );

  const handlePrev = useCallback(() => {
    const next =
      (activeScenarioIdx - 1 + SEARCH_SCENARIOS.length) %
      SEARCH_SCENARIOS.length;
    runSearch(next);
  }, [activeScenarioIdx, runSearch]);

  const handleNext = useCallback(() => {
    const next = (activeScenarioIdx + 1) % SEARCH_SCENARIOS.length;
    runSearch(next);
  }, [activeScenarioIdx, runSearch]);

  const handleCopy = useCallback(async (hitId: string, text: string) => {
    await copyTextToClipboard(text);
    setCopiedId(hitId);
    pushTimer(setTimeout(() => {
      setCopiedId(null);
    }, 2000));
  }, [pushTimer]);

  const IconForScenario = SCENARIO_ICONS[scenario.icon];

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 left-1/4 w-64 h-64 bg-primary/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-48 h-48 bg-emerald-500/8 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 right-0 w-32 h-32 bg-blue-500/8 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 space-y-5">
        {/* Header with scenario description */}
        <div className="flex items-center gap-3 mb-2">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/15 ring-1 ring-primary/20">
            <IconForScenario className="h-5 w-5 text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-semibold text-white">
              Cross-Agent Session Search
            </h4>
            <p className="text-xs text-white/40 truncate">
              {scenario.description}
            </p>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-white/30">
            <Database className="h-3.5 w-3.5" />
            <span>{scenario.stats.sessionsSearched} sessions indexed</span>
          </div>
        </div>

        {/* Scenario selector tabs */}
        <div className="flex items-center gap-2">
          <button
            onClick={handlePrev}
            disabled={searching}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white hover:border-white/[0.15] transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>

          <div className="flex-1 flex items-center gap-1.5 overflow-x-auto scrollbar-hide">
            {SEARCH_SCENARIOS.map((s, i) => {
              const SIcon = SCENARIO_ICONS[s.icon];
              return (
                <button
                  key={s.id}
                  onClick={() => runSearch(i)}
                  disabled={searching}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition-all ${
                    i === activeScenarioIdx
                      ? "bg-primary/20 text-primary border border-primary/30 shadow-lg shadow-primary/10"
                      : "bg-white/[0.02] text-white/40 border border-white/[0.08] hover:text-white/60 hover:border-white/[0.12]"
                  } disabled:cursor-not-allowed`}
                >
                  <SIcon className="h-3 w-3" />
                  {s.label}
                </button>
              );
            })}
          </div>

          <button
            onClick={handleNext}
            disabled={searching}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-white/[0.08] bg-white/[0.02] text-white/60 hover:text-white hover:border-white/[0.15] transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        {/* Mini terminal showing search command */}
        <div className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
          <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
            <div className="flex gap-1.5">
              <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
              <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
              <div className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
            </div>
            <span className="ml-2 text-xs text-white/30 font-mono">
              cass-terminal
            </span>
          </div>
          <div className="p-4 font-mono text-xs space-y-1 min-h-[80px] max-h-[120px] overflow-y-auto">
            <AnimatePresence mode="popLayout">
              {terminalLines.map((line, idx) => (
                <motion.div
                  key={`${activeScenarioIdx}-line-${idx}`}
                  initial={{ opacity: 0, x: -8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 25,
                  }}
                  className={
                    idx === 0
                      ? "text-emerald-400"
                      : line.startsWith("Found")
                        ? "text-primary font-semibold"
                        : "text-white/40"
                  }
                >
                  {line}
                </motion.div>
              ))}
            </AnimatePresence>
            {(searching || (!hasSearched && terminalLines.length === 0)) && (
              <motion.span
                animate={{ opacity: [1, 0] }}
                transition={{
                  duration: 0.8,
                  repeat: Infinity,
                  repeatType: "reverse",
                }}
                className="inline-block w-2 h-3.5 bg-emerald-400/80"
              />
            )}
          </div>

          {/* Progress bar during search */}
          {searching && (
            <div className="px-4 pb-3">
              <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                <motion.div
                  initial={{ width: 0 }}
                  animate={{ width: `${searchProgress}%` }}
                  className="h-full rounded-full bg-gradient-to-r from-primary to-emerald-400"
                />
              </div>
            </div>
          )}
        </div>

        {/* Run search button (before first search) */}
        {!searching && !hasSearched && (
          <motion.button
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ type: "spring", stiffness: 200, damping: 25 }}
            onClick={() => runSearch(activeScenarioIdx)}
            className="w-full flex items-center justify-center gap-2 py-3 rounded-xl border border-primary/30 bg-primary/10 text-primary font-medium hover:bg-primary/20 transition-colors"
          >
            <Play className="h-4 w-4" />
            Run Search
          </motion.button>
        )}

        {/* Searching spinner */}
        <AnimatePresence mode="wait">
          {searching && (
            <motion.div
              key="searching"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -12 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="flex flex-col items-center justify-center py-8 gap-4"
            >
              <div className="relative">
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{
                    duration: 1.2,
                    repeat: Infinity,
                    ease: "linear",
                  }}
                >
                  <Loader2 className="h-8 w-8 text-primary" />
                </motion.div>
                <div className="absolute inset-0 flex items-center justify-center">
                  <Search className="h-3.5 w-3.5 text-primary/60" />
                </div>
              </div>
              <div className="text-center space-y-1">
                <div className="font-mono text-sm text-white/60">
                  Searching across {scenario.stats.agents} agent indexes...
                </div>
                <div className="text-xs text-white/30">
                  {scenario.stats.sessionsSearched} sessions |{" "}
                  {searchProgress}% complete
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Results area */}
        <AnimatePresence mode="wait">
          {hasSearched && !searching && (
            <motion.div
              key={`results-${activeScenarioIdx}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ type: "spring", stiffness: 200, damping: 25 }}
              className="space-y-4"
            >
              {/* Stats bar */}
              <div className="flex items-center justify-between text-xs font-mono">
                <div className="flex items-center gap-4">
                  <span className="text-primary font-semibold">
                    {scenario.stats.totalHits} hit
                    {scenario.stats.totalHits !== 1 ? "s" : ""}
                  </span>
                  <span className="text-white/30">
                    {scenario.stats.agents} agents
                  </span>
                  <span className="text-white/30">
                    {scenario.stats.tookMs}ms
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  {(["claude", "codex", "gemini", "cursor"] as AgentType[])
                    .filter((a) =>
                      scenario.hits.some((h) => h.agent === a)
                    )
                    .map((agent) => (
                      <span
                        key={agent}
                        className={`flex items-center gap-1 ${AGENT_STYLES[agent].text}`}
                      >
                        <span
                          className={`h-1.5 w-1.5 rounded-full ${AGENT_STYLES[agent].dot}`}
                        />
                        {agent}
                      </span>
                    ))}
                </div>
              </div>

              {/* View tabs: Results | Timeline | Knowledge */}
              <div className="flex items-center gap-1 p-1 rounded-xl bg-white/[0.03] border border-white/[0.06]">
                {(
                  [
                    {
                      key: "results" as ViewTab,
                      label: "Results",
                      icon: Search,
                    },
                    {
                      key: "timeline" as ViewTab,
                      label: "Timeline",
                      icon: Clock,
                    },
                    {
                      key: "knowledge" as ViewTab,
                      label: "Knowledge Graph",
                      icon: Network,
                    },
                  ] as const
                ).map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setActiveTab(tab.key)}
                    className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition-all ${
                      activeTab === tab.key
                        ? "bg-primary/15 text-primary border border-primary/20"
                        : "text-white/40 hover:text-white/60"
                    }`}
                  >
                    <tab.icon className="h-3.5 w-3.5" />
                    {tab.label}
                  </button>
                ))}
              </div>

              {/* RESULTS TAB */}
              <AnimatePresence mode="wait">
                {activeTab === "results" && (
                  <motion.div
                    key="results-tab"
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{
                      type: "spring",
                      stiffness: 200,
                      damping: 25,
                    }}
                    className="space-y-3"
                  >
                    {scenario.hits.map((hit, i) => {
                      const colors = AGENT_STYLES[hit.agent];
                      const isExpanded = expandedHit === hit.id;
                      const isCopied = copiedId === hit.id;

                      return (
                        <motion.div
                          key={hit.id}
                          initial={{ opacity: 0, y: 16 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{
                            type: "spring",
                            stiffness: 200,
                            damping: 25,
                            delay: i * 0.08,
                          }}
                          className={`relative rounded-xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden transition-all duration-300 hover:border-white/[0.15] border-l-2 ${colors.border}`}
                        >
                          <div className="p-4 space-y-3">
                            {/* Header row */}
                            <div className="flex items-center justify-between">
                              <div className="flex items-center gap-2.5">
                                <div
                                  className={`flex h-7 w-7 items-center justify-center rounded-lg ${colors.bg} ring-1 ${colors.ring}`}
                                >
                                  <Bot
                                    className={`h-3.5 w-3.5 ${colors.text}`}
                                  />
                                </div>
                                <div>
                                  <span
                                    className={`text-sm font-semibold ${colors.text}`}
                                  >
                                    {hit.agentLabel}
                                  </span>
                                  <div className="text-[10px] text-white/30 font-mono">
                                    {hit.workspace}
                                  </div>
                                </div>
                              </div>
                              <div className="flex items-center gap-2">
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    handleCopy(hit.id, hit.snippet);
                                  }}
                                  className="flex h-6 w-6 items-center justify-center rounded-md bg-white/[0.04] text-white/30 hover:text-white/60 hover:bg-white/[0.08] transition-colors"
                                  title="Copy snippet"
                                >
                                  {isCopied ? (
                                    <CheckCircle className="h-3 w-3 text-emerald-400" />
                                  ) : (
                                    <Copy className="h-3 w-3" />
                                  )}
                                </button>
                                <button
                                  onClick={() =>
                                    setExpandedHit(
                                      isExpanded ? null : hit.id
                                    )
                                  }
                                  className="flex h-6 items-center gap-1 px-2 rounded-md bg-white/[0.04] text-white/30 hover:text-white/60 hover:bg-white/[0.08] transition-colors text-[10px] font-mono"
                                >
                                  {isExpanded ? (
                                    <>
                                      <X className="h-3 w-3" /> close
                                    </>
                                  ) : (
                                    <>
                                      <Eye className="h-3 w-3" /> expand
                                    </>
                                  )}
                                </button>
                              </div>
                            </div>

                            {/* Session path + timestamp */}
                            <div className="flex items-center justify-between">
                              <div className="font-mono text-[11px] text-white/35 truncate flex-1">
                                {hit.sessionPath}:{hit.lineNumber}
                              </div>
                              <div className="flex items-center gap-1.5 text-[10px] text-white/25 ml-2 shrink-0">
                                <Clock className="h-3 w-3" />
                                {hit.timestamp.slice(0, 10)}
                              </div>
                            </div>

                            {/* Relevance score bar */}
                            <div className="flex items-center gap-3">
                              <div className="flex items-center gap-1.5 shrink-0">
                                <BarChart3 className="h-3 w-3 text-white/30" />
                                <span className="text-xs text-white/50 font-mono w-10">
                                  {hit.score.toFixed(2)}
                                </span>
                              </div>
                              <div className="flex-1 h-2 rounded-full bg-white/[0.06] overflow-hidden">
                                <motion.div
                                  initial={{ width: 0 }}
                                  animate={{
                                    width: `${hit.score * 100}%`,
                                  }}
                                  transition={{
                                    type: "spring",
                                    stiffness: 100,
                                    damping: 20,
                                    delay: i * 0.08 + 0.2,
                                  }}
                                  className={`h-full rounded-full bg-gradient-to-r ${colors.gradient}`}
                                />
                              </div>
                            </div>

                            {/* Snippet with highlighted matches */}
                            <div className="font-mono text-xs text-white/60 bg-black/30 rounded-lg p-3 leading-relaxed">
                              <HighlightedSnippet
                                text={hit.snippet}
                                highlights={hit.matchHighlights}
                              />
                            </div>

                            {/* Tags */}
                            <div className="flex flex-wrap gap-1.5">
                              {hit.tags.map((tag) => (
                                <span
                                  key={tag}
                                  className="flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/[0.04] text-[10px] text-white/40 font-mono border border-white/[0.06]"
                                >
                                  <Tag className="h-2.5 w-2.5" />
                                  {tag}
                                </span>
                              ))}
                            </div>

                            {/* Expanded context */}
                            <AnimatePresence>
                              {isExpanded && (
                                <motion.div
                                  initial={{ height: 0, opacity: 0 }}
                                  animate={{
                                    height: "auto",
                                    opacity: 1,
                                  }}
                                  exit={{ height: 0, opacity: 0 }}
                                  transition={{
                                    type: "spring",
                                    stiffness: 200,
                                    damping: 25,
                                  }}
                                  className="overflow-hidden"
                                >
                                  <div className="border-t border-white/[0.06] pt-3 mt-1 space-y-2">
                                    <div className="flex items-center gap-2 mb-2">
                                      <FileSearch className="h-3.5 w-3.5 text-primary" />
                                      <span className="text-xs text-primary font-medium">
                                        cass expand{" "}
                                        {hit.sessionPath.split("/").pop()} -n{" "}
                                        {hit.lineNumber} -C 3 --json
                                      </span>
                                    </div>
                                    <div className="font-mono text-xs bg-black/40 rounded-lg p-3 space-y-1.5 border border-white/[0.04]">
                                      {hit.expandedContext.map(
                                        (line, li) => {
                                          const isMatch =
                                            line.startsWith(">>>");
                                          const isUser =
                                            line.startsWith("user:");
                                          return (
                                            <div
                                              key={li}
                                              className={`leading-relaxed ${
                                                isMatch
                                                  ? "text-primary font-semibold bg-primary/10 -mx-2 px-2 py-1 rounded border-l-2 border-primary/40"
                                                  : isUser
                                                    ? "text-white/50"
                                                    : "text-emerald-400/70"
                                              }`}
                                            >
                                              {isMatch && (
                                                <span className="text-[10px] text-primary/60 uppercase tracking-wider mr-2">
                                                  match
                                                </span>
                                              )}
                                              {isUser && (
                                                <span className="text-blue-400/60 mr-1">
                                                  &gt;
                                                </span>
                                              )}
                                              {!isUser && !isMatch && (
                                                <span className="text-emerald-400/40 mr-1">
                                                  &lt;
                                                </span>
                                              )}
                                              {isMatch
                                                ? line.slice(4)
                                                : isUser
                                                  ? line.slice(5)
                                                  : line.startsWith(
                                                        "assistant:"
                                                      )
                                                    ? line.slice(11)
                                                    : line}
                                            </div>
                                          );
                                        }
                                      )}
                                    </div>
                                  </div>
                                </motion.div>
                              )}
                            </AnimatePresence>
                          </div>
                        </motion.div>
                      );
                    })}
                  </motion.div>
                )}

                {/* TIMELINE TAB */}
                {activeTab === "timeline" && (
                  <motion.div
                    key="timeline-tab"
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{
                      type: "spring",
                      stiffness: 200,
                      damping: 25,
                    }}
                    className="space-y-1"
                  >
                    <div className="flex items-center gap-2 mb-4">
                      <History className="h-4 w-4 text-primary/60" />
                      <span className="text-xs text-white/50">
                        Session timeline for &quot;{scenario.query}&quot;
                      </span>
                    </div>

                    <div className="relative">
                      {/* Vertical timeline line */}
                      <div className="absolute left-[19px] top-3 bottom-3 w-px bg-gradient-to-b from-white/[0.12] via-white/[0.06] to-transparent" />

                      {scenario.timeline.map((event, i) => {
                        const colors = AGENT_STYLES[event.agent];
                        return (
                          <motion.div
                            key={event.sessionRef}
                            initial={{ opacity: 0, x: -20 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{
                              type: "spring",
                              stiffness: 200,
                              damping: 25,
                              delay: i * 0.12,
                            }}
                            className="relative flex items-start gap-4 py-4"
                          >
                            {/* Timeline dot */}
                            <div className="relative z-10">
                              <motion.div
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                transition={{
                                  type: "spring",
                                  stiffness: 200,
                                  damping: 25,
                                  delay: i * 0.12 + 0.1,
                                }}
                                className={`h-10 w-10 rounded-full ${colors.bg} ring-2 ${colors.ring} flex items-center justify-center shadow-lg ${colors.glow}`}
                              >
                                <Bot
                                  className={`h-4 w-4 ${colors.text}`}
                                />
                              </motion.div>
                            </div>

                            {/* Event content */}
                            <div className="flex-1 pt-1">
                              <div className="flex items-center justify-between mb-1">
                                <span
                                  className={`text-sm font-semibold ${colors.text}`}
                                >
                                  {event.agentLabel}
                                </span>
                                <span className="text-xs text-white/30 font-mono flex items-center gap-1">
                                  <Clock className="h-3 w-3" />
                                  {event.date}
                                </span>
                              </div>
                              <div className="text-sm text-white/60 bg-white/[0.03] rounded-lg p-3 border border-white/[0.06]">
                                {event.summary}
                              </div>
                              {i < scenario.timeline.length - 1 && (
                                <div className="flex items-center gap-1 mt-2 ml-1">
                                  <ArrowRight className="h-3 w-3 text-white/20" />
                                  <span className="text-[10px] text-white/20">
                                    evolved approach
                                  </span>
                                </div>
                              )}
                            </div>
                          </motion.div>
                        );
                      })}
                    </div>

                    {/* Timeline insight */}
                    <motion.div
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ delay: 0.5 }}
                      className="mt-4 p-3 rounded-lg bg-primary/5 border border-primary/15"
                    >
                      <div className="flex items-start gap-2">
                        <Lightbulb className="h-4 w-4 text-primary/60 mt-0.5 shrink-0" />
                        <div className="text-xs text-white/50">
                          <span className="text-primary/80 font-medium">
                            Insight:
                          </span>{" "}
                          Multiple agents solved &quot;{scenario.query}
                          &quot; problems across {scenario.timeline.length}{" "}
                          sessions. The latest approaches incorporate learnings
                          from earlier attempts.
                        </div>
                      </div>
                    </motion.div>
                  </motion.div>
                )}

                {/* KNOWLEDGE GRAPH TAB */}
                {activeTab === "knowledge" && (
                  <motion.div
                    key="knowledge-tab"
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{
                      type: "spring",
                      stiffness: 200,
                      damping: 25,
                    }}
                    className="space-y-4"
                  >
                    <div className="flex items-center gap-2 mb-2">
                      <Network className="h-4 w-4 text-primary/60" />
                      <span className="text-xs text-white/50">
                        Extracted knowledge patterns from search results
                      </span>
                    </div>

                    {/* Visual knowledge graph */}
                    <div className="relative rounded-xl border border-white/[0.06] bg-black/30 p-6 min-h-[200px] overflow-hidden">
                      {/* Connection lines rendered as SVG */}
                      <KnowledgeGraphSVG
                        nodes={scenario.knowledgeNodes}
                      />
                      {/* Nodes */}
                      <div className="relative z-10 flex flex-wrap gap-3 justify-center">
                        {scenario.knowledgeNodes.map((node, i) => {
                          const categoryStyles = {
                            pattern:
                              "bg-primary/15 text-primary border-primary/25 ring-primary/10",
                            solution:
                              "bg-emerald-500/15 text-emerald-400 border-emerald-500/25 ring-emerald-400/10",
                            error:
                              "bg-red-500/15 text-red-400 border-red-500/25 ring-red-400/10",
                            tool: "bg-blue-500/15 text-blue-400 border-blue-500/25 ring-blue-400/10",
                          };
                          const categoryIcons = {
                            pattern: Layers,
                            solution: CheckCircle,
                            error: AlertTriangle,
                            tool: Terminal,
                          };
                          const CatIcon = categoryIcons[node.category];
                          return (
                            <motion.div
                              key={node.label}
                              initial={{ opacity: 0, scale: 0.5 }}
                              animate={{ opacity: 1, scale: 1 }}
                              transition={{
                                type: "spring",
                                stiffness: 200,
                                damping: 25,
                                delay: i * 0.08,
                              }}
                              whileHover={{ scale: 1.08, y: -2 }}
                              className={`flex items-center gap-1.5 px-3 py-2 rounded-xl border ring-1 text-xs font-medium cursor-default transition-shadow hover:shadow-lg ${categoryStyles[node.category]}`}
                            >
                              <CatIcon className="h-3 w-3" />
                              {node.label}
                              <span className="text-[9px] opacity-50 ml-1">
                                ({node.connections.length})
                              </span>
                            </motion.div>
                          );
                        })}
                      </div>
                    </div>

                    {/* Knowledge legend */}
                    <div className="flex flex-wrap items-center gap-4 px-2">
                      {(
                        [
                          {
                            cat: "pattern",
                            color: "text-primary",
                            dot: "bg-primary",
                          },
                          {
                            cat: "solution",
                            color: "text-emerald-400",
                            dot: "bg-emerald-400",
                          },
                          {
                            cat: "error",
                            color: "text-red-400",
                            dot: "bg-red-400",
                          },
                          {
                            cat: "tool",
                            color: "text-blue-400",
                            dot: "bg-blue-400",
                          },
                        ] as const
                      ).map((item) => (
                        <div
                          key={item.cat}
                          className="flex items-center gap-1.5"
                        >
                          <span
                            className={`h-2 w-2 rounded-full ${item.dot}`}
                          />
                          <span
                            className={`text-[10px] capitalize ${item.color}`}
                          >
                            {item.cat}
                          </span>
                        </div>
                      ))}
                    </div>

                    {/* Extracted patterns summary */}
                    <div className="space-y-2">
                      <div className="text-xs text-white/40 font-medium px-1">
                        Extracted Patterns
                      </div>
                      {scenario.knowledgeNodes
                        .filter(
                          (n) =>
                            n.category === "pattern" ||
                            n.category === "solution"
                        )
                        .map((node, i) => (
                          <motion.div
                            key={node.label}
                            initial={{ opacity: 0, x: -12 }}
                            animate={{ opacity: 1, x: 0 }}
                            transition={{
                              type: "spring",
                              stiffness: 200,
                              damping: 25,
                              delay: i * 0.06,
                            }}
                            className="flex items-center gap-3 p-2.5 rounded-lg bg-white/[0.02] border border-white/[0.06] hover:border-white/[0.1] transition-colors"
                          >
                            <div
                              className={`h-2 w-2 rounded-full shrink-0 ${
                                node.category === "pattern"
                                  ? "bg-primary"
                                  : "bg-emerald-400"
                              }`}
                            />
                            <span className="text-xs text-white/60 flex-1">
                              {node.label}
                            </span>
                            <span className="text-[10px] text-white/25 font-mono">
                              {node.connections.length} connections
                            </span>
                          </motion.div>
                        ))}
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// =============================================================================
// HIGHLIGHTED SNIPPET - renders text with highlighted search matches
// =============================================================================
function HighlightedSnippet({
  text,
  highlights,
}: {
  text: string;
  highlights: string[];
}) {
  if (highlights.length === 0) {
    return <span>{text}</span>;
  }

  const escapedHighlights = highlights.map((h) =>
    h.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  );
  const regex = new RegExp(`(${escapedHighlights.join("|")})`, "gi");
  const parts = text.split(regex);

  return (
    <span>
      {parts.map((part, i) => {
        const isHighlight = highlights.some(
          (h) => h.toLowerCase() === part.toLowerCase()
        );
        return isHighlight ? (
          <span
            key={i}
            className="text-primary font-semibold bg-primary/15 px-0.5 rounded"
          >
            {part}
          </span>
        ) : (
          <span key={i}>{part}</span>
        );
      })}
    </span>
  );
}

// =============================================================================
// KNOWLEDGE GRAPH SVG - renders connection lines between nodes
// =============================================================================
function KnowledgeGraphSVG({
  nodes,
}: {
  nodes: KnowledgeNode[];
}) {
  // Precompute unique edges so each pair draws only one line
  const edges: [number, number][] = [];
  const edgeSet = new Set<string>();
  nodes.forEach((node, i) => {
    node.connections.forEach((j) => {
      if (j < nodes.length) {
        const key = `${Math.min(i, j)}-${Math.max(i, j)}`;
        if (!edgeSet.has(key)) {
          edgeSet.add(key);
          edges.push([i, j]);
        }
      }
    });
  });

  return (
    <div className="absolute inset-0 pointer-events-none">
      <svg
        width="100%"
        height="100%"
        className="absolute inset-0"
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
      >
        {edges.map(([from, to]) => {
          const totalNodes = nodes.length;
          const x1 = ((from + 0.5) / totalNodes) * 100;
          const x2 = ((to + 0.5) / totalNodes) * 100;
          return (
            <motion.line
              key={`${from}-${to}`}
              x1={`${x1}%`}
              y1="30%"
              x2={`${x2}%`}
              y2="70%"
              stroke="rgba(255,255,255,0.06)"
              strokeWidth="0.5"
              initial={{ pathLength: 0 }}
              animate={{ pathLength: 1 }}
              transition={{ duration: 0.8, delay: 0.3 }}
            />
          );
        })}
      </svg>
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
      className="group flex items-start gap-4 p-5 rounded-2xl border border-primary/20 bg-primary/5 backdrop-blur-xl transition-all duration-300 hover:border-primary/40 hover:bg-primary/10"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/20 text-primary shadow-lg shadow-primary/10 group-hover:shadow-primary/20 transition-shadow">
        <Sparkles className="h-5 w-5" />
      </div>
      <div>
        <p className="font-semibold text-white group-hover:text-primary transition-colors">{title}</p>
        <p className="text-sm text-white/50 mt-1">{description}</p>
      </div>
    </motion.div>
  );
}
