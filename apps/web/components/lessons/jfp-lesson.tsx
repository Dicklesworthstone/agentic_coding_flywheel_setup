'use client';

import { useState, useMemo, useCallback, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  GraduationCap,
  Terminal,
  Globe,
  Search,
  Download,
  Copy,
  Play,
  Check,
  Loader2,
  Sparkles,
  Layers,
  TestTube2,
  FileText,
  Bug,
  Plus,
  RefreshCw,
  Eye,
  Zap,
  ArrowRight,
  Grip,
  Send,
  Wand2,
  GitCompare,
  Beaker,
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

export function JfpLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Discover and install curated prompts for agentic coding with JeffreysPrompts.
      </GoalBanner>

      {/* Section 1: What Is JFP */}
      <Section title="What Is JFP?" icon={<GraduationCap className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>JFP (JeffreysPrompts.com CLI)</Highlight> gives you access to a curated
          library of battle-tested prompts for Claude, GPT, and other AI coding agents. Browse,
          copy, and install prompts directly as Claude Code skills.
        </Paragraph>
        <Paragraph>
          The CLI and website share the same prompt library, so use whichever interface fits your
          workflow. Prompts are organized into bundles and workflows for complex use cases.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Browse"
              description="Explore curated prompt collection"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
            <FeatureCard
              icon={<Copy className="h-5 w-5" />}
              title="Copy"
              description="Copy prompts to clipboard instantly"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Install"
              description="Install as Claude Code skills"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Web + CLI"
              description="Use browser or terminal"
              gradient="from-violet-500/20 to-purple-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Interactive Prompt Crafting Laboratory */}
      <Section title="Prompt Crafting Laboratory" icon={<Sparkles className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Master the art of prompt engineering. Explore how prompts evolve from vague to precise,
          build your own templates, and see quality scores in real time.
        </Paragraph>
        <div className="mt-6">
          <InteractivePromptGallery />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'jfp list', description: 'List all available prompts' },
            { command: 'jfp search <query>', description: 'Search for prompts' },
            { command: 'jfp show <id>', description: 'View prompt details' },
            { command: 'jfp copy <id>', description: 'Copy prompt to clipboard' },
            { command: 'jfp install <id>', description: 'Install as Claude Code skill' },
            { command: 'jfp installed', description: 'List installed skills' },
          ]}
        />

        <TipBox variant="info">
          Visit <a href="https://jeffreysprompts.com" className="text-blue-400 underline">jeffreysprompts.com</a> for a beautiful UI to browse prompts.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# Browse all prompts
jfp list

# Search for code review prompts
jfp search "code review"

# Install a prompt as a skill
jfp install idea-wizard

# Use in Claude Code
/idea-wizard "build a REST API"`} />
      </Section>
    </div>
  );
}

// =============================================================================
// DATA TYPES & CONSTANTS
// =============================================================================

type PromptCategory = 'Bug Fix' | 'Feature Add' | 'Refactor' | 'Test Writing' | 'Code Review' | 'Architecture';
type LabTab = 'evolution' | 'compare' | 'builder' | 'terminal';

interface QualityScores {
  clarity: number;
  specificity: number;
  context: number;
  constraints: number;
  examples: number;
}

interface PromptVersion {
  version: number;
  label: string;
  text: string;
  scores: QualityScores;
  highlights: string[];
}

interface PromptEvolution {
  id: string;
  category: PromptCategory;
  title: string;
  description: string;
  versions: [PromptVersion, PromptVersion, PromptVersion];
}

interface TemplateSectionData {
  id: string;
  label: string;
  icon: string;
  text: string;
  color: string;
}

const CATEGORY_CONFIG: Record<PromptCategory, { icon: React.ReactNode; gradient: string; color: string }> = {
  'Bug Fix': { icon: <Bug className="h-3.5 w-3.5" />, gradient: 'from-red-500 to-orange-500', color: 'text-red-400' },
  'Feature Add': { icon: <Plus className="h-3.5 w-3.5" />, gradient: 'from-emerald-500 to-teal-500', color: 'text-emerald-400' },
  'Refactor': { icon: <RefreshCw className="h-3.5 w-3.5" />, gradient: 'from-amber-500 to-yellow-500', color: 'text-amber-400' },
  'Test Writing': { icon: <TestTube2 className="h-3.5 w-3.5" />, gradient: 'from-blue-500 to-indigo-500', color: 'text-blue-400' },
  'Code Review': { icon: <Eye className="h-3.5 w-3.5" />, gradient: 'from-violet-500 to-purple-500', color: 'text-violet-400' },
  'Architecture': { icon: <Layers className="h-3.5 w-3.5" />, gradient: 'from-pink-500 to-rose-500', color: 'text-pink-400' },
};

const TAB_CONFIG: { id: LabTab; label: string; icon: React.ReactNode }[] = [
  { id: 'evolution', label: 'Prompt Evolution', icon: <Wand2 className="h-3.5 w-3.5" /> },
  { id: 'compare', label: 'Vague vs Precise', icon: <GitCompare className="h-3.5 w-3.5" /> },
  { id: 'builder', label: 'Template Builder', icon: <Beaker className="h-3.5 w-3.5" /> },
  { id: 'terminal', label: 'Agent Terminal', icon: <Terminal className="h-3.5 w-3.5" /> },
];

const PROMPT_EVOLUTIONS: PromptEvolution[] = [
  {
    id: 'bugfix-auth',
    category: 'Bug Fix',
    title: 'Authentication Token Expiry Bug',
    description: 'Watch a bug fix prompt evolve from vague to surgical precision',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Fix the login bug. Users are getting logged out randomly.',
        scores: { clarity: 25, specificity: 15, context: 10, constraints: 5, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Fix the JWT token refresh bug in our Next.js app. Users get logged out after ~1 hour. The refresh token endpoint returns 401 sometimes. Check the token rotation logic in auth/middleware.ts.',
        scores: { clarity: 60, specificity: 55, context: 50, constraints: 30, examples: 20 },
        highlights: ['JWT token refresh', 'Next.js', '~1 hour', 'auth/middleware.ts'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Fix the JWT refresh token race condition in auth/middleware.ts.\n\nBug: When multiple API calls fire simultaneously after token expiry, each triggers a refresh. The second refresh fails because the first already rotated the token.\n\nContext:\n- Next.js 16 + NextAuth v5\n- Tokens expire after 1 hour\n- Refresh endpoint: /api/auth/refresh\n- See error logs: "TokenRotationError: refresh_token already used"\n\nConstraints:\n- Must not break existing sessions\n- Add mutex/queue for concurrent refresh attempts\n- Include retry logic with exponential backoff\n\nExpected: Single refresh per expiry cycle, queued requests wait for the fresh token.',
        scores: { clarity: 95, specificity: 90, context: 85, constraints: 90, examples: 80 },
        highlights: ['race condition', 'auth/middleware.ts', 'multiple API calls', 'mutex/queue', 'exponential backoff', 'TokenRotationError'],
      },
    ],
  },
  {
    id: 'feature-search',
    category: 'Feature Add',
    title: 'Full-Text Search Implementation',
    description: 'See a feature request prompt go from wishful to actionable',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Add search to our app.',
        scores: { clarity: 20, specificity: 10, context: 5, constraints: 5, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Add full-text search for our blog posts. Should support fuzzy matching and highlighting. We use PostgreSQL and have about 10k posts. Show results in a dropdown as the user types.',
        scores: { clarity: 55, specificity: 50, context: 45, constraints: 35, examples: 25 },
        highlights: ['full-text search', 'fuzzy matching', 'PostgreSQL', '10k posts', 'dropdown'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Implement full-text search for blog posts using PostgreSQL tsvector.\n\nRequirements:\n- Search fields: title (weight A), body (weight B), tags (weight C)\n- Fuzzy matching via pg_trgm extension with similarity threshold 0.3\n- Debounced typeahead (300ms) with result dropdown (max 8 items)\n- Highlight matching terms with <mark> tags in results\n\nTech stack: Next.js 16 API routes, Prisma ORM, PostgreSQL 16\n\nPerformance:\n- Add GIN index on tsvector column\n- Response time < 100ms for 10k documents\n- Cache frequent queries with Redis (TTL: 5min)\n\nUI: Use existing SearchCombobox component from @/components/ui.\nReturn type: { id, title, excerpt (150 chars), highlights[], score }',
        scores: { clarity: 90, specificity: 95, context: 85, constraints: 85, examples: 90 },
        highlights: ['tsvector', 'pg_trgm', 'weight A/B/C', 'GIN index', '< 100ms', 'SearchCombobox', 'Prisma ORM'],
      },
    ],
  },
  {
    id: 'refactor-state',
    category: 'Refactor',
    title: 'State Management Refactor',
    description: 'Transform a refactoring request from hand-wavy to systematic',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Clean up the state management, it is a mess.',
        scores: { clarity: 20, specificity: 10, context: 10, constraints: 5, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Refactor our React state management. We have too many useStates in the dashboard page. Move shared state to context or Zustand. The dashboard re-renders too often.',
        scores: { clarity: 50, specificity: 45, context: 40, constraints: 30, examples: 15 },
        highlights: ['React state', 'useStates', 'dashboard', 'context or Zustand', 're-renders'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Refactor dashboard state from 12 useState hooks to Zustand slices.\n\nCurrent problems:\n- app/dashboard/page.tsx has 12 useState hooks (lines 45-89)\n- Every filter change re-renders the entire chart grid (6 charts)\n- Network waterfall: 4 sequential fetches that could be parallel\n\nTarget architecture:\n- Create stores/dashboardStore.ts with slices: filters, charts, userPrefs\n- Use Zustand selectors for granular subscriptions\n- Wrap chart grid in React.memo with shallow equality\n- Parallelize data fetches with Promise.all in a single useEffect\n\nConstraints:\n- Preserve URL sync for filter state (?range=7d&metric=revenue)\n- Keep the existing DashboardFilter and ChartCard component APIs\n- No new dependencies beyond zustand (already installed)\n- Add unit tests for each store slice\n\nSuccess metric: Dashboard re-renders drop from 47 to < 10 per filter change (measure with React DevTools Profiler).',
        scores: { clarity: 95, specificity: 92, context: 90, constraints: 88, examples: 85 },
        highlights: ['12 useState hooks', 'Zustand slices', 'lines 45-89', 'shallow equality', 'Promise.all', '47 to < 10'],
      },
    ],
  },
  {
    id: 'test-api',
    category: 'Test Writing',
    title: 'API Integration Tests',
    description: 'Level up test writing prompts from basic to comprehensive',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Write tests for our API.',
        scores: { clarity: 15, specificity: 10, context: 5, constraints: 5, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Write integration tests for our REST API endpoints. Cover the user CRUD operations and authentication flow. Use Jest and Supertest. Test both success and error cases.',
        scores: { clarity: 55, specificity: 45, context: 40, constraints: 35, examples: 20 },
        highlights: ['integration tests', 'REST API', 'CRUD', 'Jest and Supertest', 'error cases'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Write integration tests for the user management API endpoints.\n\nEndpoints to cover:\n- POST /api/users (create) - validate email, handle duplicates\n- GET /api/users/:id (read) - 200, 404, malformed ID\n- PATCH /api/users/:id (update) - partial updates, concurrent edits\n- DELETE /api/users/:id (delete) - cascade behavior, already deleted\n\nTest infrastructure:\n- Framework: Vitest + Supertest against test server\n- Database: Use testcontainers/postgresql for isolated DB per test suite\n- Auth: Generate test JWT tokens with helper in tests/fixtures/auth.ts\n- Seed data: Use factories from tests/factories/user.factory.ts\n\nEdge cases to cover:\n- SQL injection attempts in string fields\n- Unicode names and emoji\n- Payload > 1MB (should return 413)\n- Rate limiting: 100 req/min per IP\n- Concurrent PATCH to same resource (optimistic locking with version field)\n\nOutput format: Group by endpoint, use describe/it blocks.\nMinimum 40 test cases. Run in < 30 seconds with parallel execution.',
        scores: { clarity: 92, specificity: 95, context: 88, constraints: 90, examples: 92 },
        highlights: ['testcontainers/postgresql', 'factories', 'SQL injection', 'optimistic locking', '40 test cases', '< 30 seconds'],
      },
    ],
  },
  {
    id: 'review-perf',
    category: 'Code Review',
    title: 'Performance-Focused Code Review',
    description: 'Evolve a code review request from shallow to deep analysis',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Review this code and tell me if there are any issues.',
        scores: { clarity: 20, specificity: 15, context: 5, constraints: 10, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Review the checkout flow code for performance issues. The page takes 3+ seconds to load. Focus on unnecessary re-renders, large bundle imports, and API call efficiency. Check components in app/checkout/.',
        scores: { clarity: 55, specificity: 50, context: 45, constraints: 40, examples: 20 },
        highlights: ['checkout flow', '3+ seconds', 're-renders', 'bundle imports', 'app/checkout/'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Performance review of checkout flow (app/checkout/).\n\nSymptoms:\n- LCP: 3.2s (target: < 1.5s), FID: 180ms (target: < 100ms)\n- Bundle analysis shows checkout chunk is 420KB (should be < 150KB)\n- 7 sequential API calls in useEffect on mount\n\nReview checklist:\n1. Component splitting: identify code-split boundaries (lazy load payment form, address autocomplete)\n2. Re-render audit: find components missing React.memo or useMemo\n3. Import analysis: flag barrel imports (e.g., import from "lodash" vs "lodash/debounce")\n4. API optimization: which calls can be parallelized or deferred?\n5. Image optimization: any unoptimized images in checkout flow?\n6. Third-party scripts: Stripe.js loading strategy (defer vs async)\n\nOutput format:\n| File | Issue | Severity | Fix | Estimated Impact |\nProvide concrete code diffs for top 5 fixes.\nEstimate total LCP improvement for each fix.',
        scores: { clarity: 95, specificity: 93, context: 90, constraints: 85, examples: 88 },
        highlights: ['LCP: 3.2s', '420KB', '7 sequential API calls', 'code-split boundaries', 'barrel imports', 'Stripe.js'],
      },
    ],
  },
  {
    id: 'arch-microservice',
    category: 'Architecture',
    title: 'Microservice Extraction',
    description: 'See an architecture prompt mature from vague to production-ready',
    versions: [
      {
        version: 1, label: 'Vague',
        text: 'Help me break this monolith into microservices.',
        scores: { clarity: 20, specificity: 10, context: 10, constraints: 5, examples: 0 },
        highlights: [],
      },
      {
        version: 2, label: 'Better',
        text: 'Extract the notification system from our Node.js monolith into a standalone microservice. It handles email, SMS, and push notifications. Currently processes about 50k notifications per day. Use message queues for async delivery.',
        scores: { clarity: 55, specificity: 50, context: 50, constraints: 35, examples: 20 },
        highlights: ['notification system', 'Node.js monolith', 'email, SMS, push', '50k/day', 'message queues'],
      },
      {
        version: 3, label: 'Precise',
        text: 'Extract notification service from monolith (src/services/notifications/).\n\nCurrent state:\n- 8 files, ~2400 lines in src/services/notifications/\n- Direct DB queries to users, preferences, templates tables\n- Called from 14 places across the codebase (see: grep -r "notificationService")\n- Processes 50k notifications/day (peak: 200/min during marketing campaigns)\n\nTarget architecture:\n- Standalone Node.js service with its own PostgreSQL schema\n- Event-driven: publish NotificationRequested events to RabbitMQ\n- Channels: email (SendGrid), SMS (Twilio), push (Firebase FCM)\n- Template engine: Handlebars with i18n support (12 locales)\n\nMigration plan:\n1. Strangler fig pattern: new service handles writes, monolith reads during transition\n2. Dual-write phase (2 weeks) with reconciliation job\n3. API contract: POST /api/v1/notifications/send with OpenAPI spec\n4. Circuit breaker for each channel (fallback: queue for retry)\n\nConstraints:\n- Zero downtime migration\n- Preserve delivery guarantees (at-least-once)\n- SLA: 99.9% delivery within 30 seconds\n- Budget: single t3.medium instance\n\nDeliverables: Architecture diagram, API spec, migration runbook, Terraform config.',
        scores: { clarity: 95, specificity: 95, context: 92, constraints: 90, examples: 85 },
        highlights: ['Strangler fig pattern', 'dual-write', 'circuit breaker', 'at-least-once', '99.9%', 'Terraform'],
      },
    ],
  },
];

const TEMPLATE_SECTIONS: TemplateSectionData[] = [
  { id: 'role', label: 'Role', icon: 'user', text: 'You are a senior {{ROLE}} engineer with expertise in {{TECH_STACK}}.', color: 'text-violet-400' },
  { id: 'task', label: 'Task', icon: 'target', text: '{{ACTION}} the {{COMPONENT}} in {{FILE_PATH}}.', color: 'text-emerald-400' },
  { id: 'context', label: 'Context', icon: 'info', text: 'Current behavior: {{CURRENT}}.\nExpected behavior: {{EXPECTED}}.', color: 'text-blue-400' },
  { id: 'constraints', label: 'Constraints', icon: 'lock', text: '- Must maintain backward compatibility\n- No new dependencies\n- Follow existing code style', color: 'text-amber-400' },
  { id: 'output', label: 'Output Format', icon: 'file', text: 'Provide:\n1. Implementation with inline comments\n2. Unit tests\n3. Brief explanation of changes', color: 'text-pink-400' },
  { id: 'examples', label: 'Examples', icon: 'code', text: 'Example input: {{EXAMPLE_INPUT}}\nExample output: {{EXAMPLE_OUTPUT}}', color: 'text-cyan-400' },
];

const VAGUE_VS_PRECISE: { vague: string; precise: string; category: PromptCategory; vagueResult: number; preciseResult: number }[] = [
  { category: 'Bug Fix', vague: 'Fix the crash', precise: 'Fix the null pointer dereference in UserService.getProfile() when user.address is undefined (line 142)', vagueResult: 25, preciseResult: 92 },
  { category: 'Feature Add', vague: 'Add dark mode', precise: 'Add dark mode toggle using next-themes with system preference detection, persisted to localStorage, applied via Tailwind dark: prefix', vagueResult: 35, preciseResult: 90 },
  { category: 'Refactor', vague: 'Make this cleaner', precise: 'Extract the 3 repeated validation blocks (lines 45, 89, 134) into a shared validateInput() utility in lib/validation.ts', vagueResult: 20, preciseResult: 88 },
  { category: 'Test Writing', vague: 'Add some tests', precise: 'Write Vitest unit tests for calculateDiscount() covering: percentage caps, negative values, expired coupons, and stacked discounts', vagueResult: 30, preciseResult: 95 },
  { category: 'Code Review', vague: 'Check for issues', precise: 'Review for N+1 query patterns in the dashboard data loader, specifically the user.posts.comments chain in getDashboardData()', vagueResult: 22, preciseResult: 91 },
  { category: 'Architecture', vague: 'Design the backend', precise: 'Design a CQRS event-sourced order service with separate read/write models, Kafka event bus, and PostgreSQL + Redis projections', vagueResult: 18, preciseResult: 93 },
];

const TERMINAL_LINES = [
  { type: 'command' as const, text: '$ jfp search "code review performance"' },
  { type: 'output' as const, text: 'Found 3 prompts matching "code review performance":' },
  { type: 'output' as const, text: '' },
  { type: 'result' as const, text: '  1. perf-review-pro    Performance-focused code review     4.9' },
  { type: 'result' as const, text: '  2. bundle-analyzer    Bundle size optimization review      4.7' },
  { type: 'result' as const, text: '  3. render-audit       React re-render analysis             4.6' },
  { type: 'output' as const, text: '' },
  { type: 'command' as const, text: '$ jfp install perf-review-pro' },
  { type: 'progress' as const, text: 'Downloading prompt template...' },
  { type: 'progress' as const, text: 'Installing as Claude Code skill...' },
  { type: 'success' as const, text: 'Installed! Use with: /perf-review-pro <file_or_directory>' },
  { type: 'output' as const, text: '' },
  { type: 'command' as const, text: '$ /perf-review-pro app/checkout/' },
  { type: 'output' as const, text: 'Analyzing checkout flow for performance issues...' },
  { type: 'output' as const, text: '' },
  { type: 'agent' as const, text: 'I\'ll review app/checkout/ for performance issues.' },
  { type: 'agent' as const, text: '' },
  { type: 'agent' as const, text: 'Found 5 critical issues:' },
  { type: 'agent' as const, text: '  1. Barrel import of lodash adds 72KB (use lodash/debounce)' },
  { type: 'agent' as const, text: '  2. CartSummary missing React.memo - 23 unnecessary re-renders' },
  { type: 'agent' as const, text: '  3. Stripe.js loaded synchronously blocking LCP by 1.2s' },
  { type: 'agent' as const, text: '  4. 4 sequential API calls can be parallelized (save ~800ms)' },
  { type: 'agent' as const, text: '  5. Unoptimized product images (avg 340KB, should be < 50KB)' },
  { type: 'agent' as const, text: '' },
  { type: 'agent' as const, text: 'Estimated LCP improvement: 3.2s -> 1.3s' },
];

// =============================================================================
// RADAR CHART COMPONENT (SVG pentagon)
// =============================================================================

const RADAR_AXES: { key: keyof QualityScores; label: string }[] = [
  { key: 'clarity', label: 'Clarity' },
  { key: 'specificity', label: 'Specificity' },
  { key: 'context', label: 'Context' },
  { key: 'constraints', label: 'Constraints' },
  { key: 'examples', label: 'Examples' },
];

function RadarChart({ scores, animate }: { scores: QualityScores; animate: boolean }) {
  const cx = 100;
  const cy = 100;
  const maxR = 70;
  const levels = 4;

  function polarToXY(angleDeg: number, radius: number) {
    const rad = ((angleDeg - 90) * Math.PI) / 180;
    return { x: cx + radius * Math.cos(rad), y: cy + radius * Math.sin(rad) };
  }

  const angleStep = 360 / 5;

  const gridPolygons = Array.from({ length: levels }, (_, i) => {
    const r = (maxR / levels) * (i + 1);
    const pts = Array.from({ length: 5 }, (__, j) => {
      const p = polarToXY(j * angleStep, r);
      return `${p.x},${p.y}`;
    }).join(' ');
    return pts;
  });

  const dataPoints = RADAR_AXES.map((axis, i) => {
    const val = scores[axis.key] / 100;
    const r = val * maxR;
    return polarToXY(i * angleStep, r);
  });
  const dataPath = dataPoints.map((p) => `${p.x},${p.y}`).join(' ');

  const labelPositions = RADAR_AXES.map((axis, i) => {
    const p = polarToXY(i * angleStep, maxR + 18);
    return { ...p, label: axis.label, value: scores[axis.key] };
  });

  return (
    <div className="flex items-center justify-center">
      <svg viewBox="0 0 200 200" className="w-full max-w-[220px] h-auto">
        {/* Grid */}
        {gridPolygons.map((pts, i) => (
          <polygon
            key={i}
            points={pts}
            fill="none"
            stroke="rgba(255,255,255,0.06)"
            strokeWidth="0.5"
          />
        ))}
        {/* Axis lines */}
        {Array.from({ length: 5 }, (_, i) => {
          const p = polarToXY(i * angleStep, maxR);
          return (
            <line
              key={i}
              x1={cx}
              y1={cy}
              x2={p.x}
              y2={p.y}
              stroke="rgba(255,255,255,0.08)"
              strokeWidth="0.5"
            />
          );
        })}
        {/* Data polygon */}
        <motion.polygon
          points={dataPath}
          fill="rgba(168,85,247,0.15)"
          stroke="rgba(168,85,247,0.6)"
          strokeWidth="1.5"
          initial={animate ? { opacity: 0 } : undefined}
          animate={animate ? { opacity: 1 } : undefined}
          transition={{ duration: 0.5, delay: 0.2 }}
        />
        {/* Data points */}
        {dataPoints.map((p, i) => (
          <motion.circle
            key={i}
            cx={p.x}
            cy={p.y}
            r="3"
            fill="rgba(168,85,247,0.8)"
            stroke="rgba(168,85,247,1)"
            strokeWidth="1"
            initial={animate ? { opacity: 0, scale: 0 } : undefined}
            animate={animate ? { opacity: 1, scale: 1 } : undefined}
            transition={{ duration: 0.3, delay: 0.3 + i * 0.08 }}
          />
        ))}
        {/* Labels */}
        {labelPositions.map((lp, i) => (
          <text
            key={i}
            x={lp.x}
            y={lp.y}
            textAnchor="middle"
            dominantBaseline="middle"
            className="fill-white/50 text-[7px] font-medium"
          >
            {lp.label}
          </text>
        ))}
      </svg>
    </div>
  );
}

// =============================================================================
// QUALITY SCORE BAR
// =============================================================================

function QualityBar({ label, value, delay }: { label: string; value: number; delay: number }) {
  const color = value >= 80 ? 'bg-emerald-500' : value >= 50 ? 'bg-amber-500' : 'bg-red-500';
  const textColor = value >= 80 ? 'text-emerald-400' : value >= 50 ? 'text-amber-400' : 'text-red-400';

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-[10px]">
        <span className="text-white/50">{label}</span>
        <span className={`font-mono font-semibold ${textColor}`}>{value}%</span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className={`h-full rounded-full ${color}`}
          initial={{ width: 0 }}
          animate={{ width: `${value}%` }}
          transition={{ type: 'spring', stiffness: 200, damping: 25, delay }}
        />
      </div>
    </div>
  );
}

// =============================================================================
// PROMPT EVOLUTION TAB
// =============================================================================

function PromptEvolutionTab() {
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [activeVersion, setActiveVersion] = useState(0);
  const evo = PROMPT_EVOLUTIONS[selectedIdx];
  const version = evo.versions[activeVersion];

  function highlightText(text: string, highlights: string[]) {
    if (highlights.length === 0) return <span className="text-white/60">{text}</span>;

    const parts: React.ReactNode[] = [];
    let remaining = text;
    let keyIdx = 0;

    for (const hl of highlights) {
      const idx = remaining.toLowerCase().indexOf(hl.toLowerCase());
      if (idx === -1) continue;
      if (idx > 0) {
        parts.push(<span key={`t-${keyIdx}`} className="text-white/60">{remaining.slice(0, idx)}</span>);
        keyIdx++;
      }
      parts.push(
        <span key={`h-${keyIdx}`} className="text-primary bg-primary/10 rounded px-0.5">
          {remaining.slice(idx, idx + hl.length)}
        </span>
      );
      keyIdx++;
      remaining = remaining.slice(idx + hl.length);
    }
    if (remaining) {
      parts.push(<span key={`r-${keyIdx}`} className="text-white/60">{remaining}</span>);
    }
    return <>{parts}</>;
  }

  const overallScore = Math.round(
    (version.scores.clarity + version.scores.specificity + version.scores.context +
     version.scores.constraints + version.scores.examples) / 5
  );

  return (
    <div className="space-y-5">
      {/* Category selector */}
      <div className="flex flex-wrap gap-2">
        {PROMPT_EVOLUTIONS.map((pe, i) => {
          const cfg = CATEGORY_CONFIG[pe.category];
          return (
            <button
              key={pe.id}
              onClick={() => { setSelectedIdx(i); setActiveVersion(0); }}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                selectedIdx === i
                  ? 'bg-primary/20 text-primary border border-primary/30'
                  : 'bg-white/[0.02] text-white/40 border border-white/[0.08] hover:text-white/60 hover:border-white/[0.12]'
              }`}
            >
              {cfg.icon}
              {pe.category}
            </button>
          );
        })}
      </div>

      {/* Selected prompt info */}
      <AnimatePresence mode="wait">
        <motion.div
          key={evo.id}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          className="space-y-4"
        >
          <div>
            <h4 className="text-sm font-semibold text-white">{evo.title}</h4>
            <p className="text-xs text-white/40 mt-0.5">{evo.description}</p>
          </div>

          {/* Version selector: v1 -> v2 -> v3 */}
          <div className="flex items-center gap-2">
            {evo.versions.map((v, vi) => (
              <div key={v.version} className="flex items-center gap-2">
                <button
                  onClick={() => setActiveVersion(vi)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition-all ${
                    activeVersion === vi
                      ? 'bg-primary/20 text-primary border border-primary/30 shadow-lg shadow-primary/10'
                      : 'bg-white/[0.02] text-white/30 border border-white/[0.08] hover:text-white/50'
                  }`}
                >
                  <span className="font-mono">v{v.version}</span>
                  <span className="hidden sm:inline">{v.label}</span>
                </button>
                {vi < 2 && (
                  <ArrowRight className="h-3 w-3 text-white/20 shrink-0" />
                )}
              </div>
            ))}
          </div>

          {/* Content area: prompt text + radar chart */}
          <div className="grid gap-4 lg:grid-cols-5">
            {/* Prompt text */}
            <div className="lg:col-span-3 space-y-3">
              <div className="rounded-xl bg-black/40 border border-white/[0.06] p-4">
                <div className="flex items-center gap-2 mb-3">
                  <div className={`h-1.5 w-1.5 rounded-full ${
                    activeVersion === 0 ? 'bg-red-400' : activeVersion === 1 ? 'bg-amber-400' : 'bg-emerald-400'
                  }`} />
                  <span className="text-[10px] font-mono text-white/30 uppercase tracking-wider">
                    Version {version.version} - {version.label}
                  </span>
                  <div className="flex-1" />
                  <span className={`text-xs font-mono font-semibold ${
                    overallScore >= 80 ? 'text-emerald-400' : overallScore >= 45 ? 'text-amber-400' : 'text-red-400'
                  }`}>
                    {overallScore}/100
                  </span>
                </div>
                <div className="font-mono text-xs leading-relaxed whitespace-pre-wrap">
                  {highlightText(version.text, version.highlights)}
                </div>
              </div>

              {/* Score bars */}
              <div className="grid grid-cols-2 gap-x-4 gap-y-2 px-1 sm:grid-cols-3">
                {RADAR_AXES.map((axis, i) => (
                  <QualityBar
                    key={axis.key}
                    label={axis.label}
                    value={version.scores[axis.key]}
                    delay={i * 0.05}
                  />
                ))}
              </div>
            </div>

            {/* Radar chart */}
            <div className="lg:col-span-2 flex flex-col items-center justify-center">
              <AnimatePresence mode="wait">
                <motion.div
                  key={`${evo.id}-v${activeVersion}`}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.9 }}
                  transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                  className="w-full"
                >
                  <RadarChart scores={version.scores} animate={true} />
                </motion.div>
              </AnimatePresence>
              <p className="text-[10px] text-white/30 text-center mt-1">Quality Radar</p>
            </div>
          </div>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// VAGUE VS PRECISE COMPARISON TAB
// =============================================================================

function VagueVsPreciseTab() {
  const [selectedIdx, setSelectedIdx] = useState(0);
  const item = VAGUE_VS_PRECISE[selectedIdx];

  return (
    <div className="space-y-5">
      {/* Category buttons */}
      <div className="flex flex-wrap gap-2">
        {VAGUE_VS_PRECISE.map((vp, i) => {
          const vpCfg = CATEGORY_CONFIG[vp.category];
          return (
            <button
              key={i}
              onClick={() => setSelectedIdx(i)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                selectedIdx === i
                  ? 'bg-primary/20 text-primary border border-primary/30'
                  : 'bg-white/[0.02] text-white/40 border border-white/[0.08] hover:text-white/60'
              }`}
            >
              {vpCfg.icon}
              {vp.category}
            </button>
          );
        })}
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={selectedIdx}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
        >
          {/* Side by side cards */}
          <div className="grid gap-4 md:grid-cols-2">
            {/* Vague */}
            <div className="rounded-xl border border-red-500/20 bg-red-500/[0.03] p-4 space-y-3">
              <div className="flex items-center gap-2">
                <div className="h-2 w-2 rounded-full bg-red-400" />
                <span className="text-xs font-semibold text-red-400 uppercase tracking-wider">Vague Prompt</span>
              </div>
              <p className="font-mono text-xs text-white/50 leading-relaxed">{item.vague}</p>
              <div className="space-y-1.5 pt-1">
                <div className="flex items-center justify-between text-[10px]">
                  <span className="text-white/40">Agent Result Quality</span>
                  <span className="font-mono font-semibold text-red-400">{item.vagueResult}%</span>
                </div>
                <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
                  <motion.div
                    className="h-full rounded-full bg-gradient-to-r from-red-500 to-red-400"
                    initial={{ width: 0 }}
                    animate={{ width: `${item.vagueResult}%` }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.2 }}
                  />
                </div>
                <div className="flex flex-wrap gap-1 pt-1">
                  {['Ambiguous scope', 'No context', 'Missing constraints'].map((tag) => (
                    <span key={tag} className="px-1.5 py-0.5 rounded text-[9px] bg-red-500/10 text-red-400/70 border border-red-500/20">
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            </div>

            {/* Precise */}
            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/[0.03] p-4 space-y-3">
              <div className="flex items-center gap-2">
                <div className="h-2 w-2 rounded-full bg-emerald-400" />
                <span className="text-xs font-semibold text-emerald-400 uppercase tracking-wider">Precise Prompt</span>
              </div>
              <p className="font-mono text-xs text-white/70 leading-relaxed">{item.precise}</p>
              <div className="space-y-1.5 pt-1">
                <div className="flex items-center justify-between text-[10px]">
                  <span className="text-white/40">Agent Result Quality</span>
                  <span className="font-mono font-semibold text-emerald-400">{item.preciseResult}%</span>
                </div>
                <div className="h-2 rounded-full bg-white/[0.06] overflow-hidden">
                  <motion.div
                    className="h-full rounded-full bg-gradient-to-r from-emerald-500 to-emerald-400"
                    initial={{ width: 0 }}
                    animate={{ width: `${item.preciseResult}%` }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.3 }}
                  />
                </div>
                <div className="flex flex-wrap gap-1 pt-1">
                  {['Specific location', 'Clear context', 'Defined output'].map((tag) => (
                    <span key={tag} className="px-1.5 py-0.5 rounded text-[9px] bg-emerald-500/10 text-emerald-400/70 border border-emerald-500/20">
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Quality improvement indicator */}
          <motion.div
            className="mt-4 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 flex items-center gap-4"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.4 }}
          >
            <div className="flex items-center gap-2">
              <Zap className="h-4 w-4 text-amber-400" />
              <span className="text-xs text-white/50">Quality Improvement:</span>
            </div>
            <div className="flex-1 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
              <motion.div
                className="h-full rounded-full bg-gradient-to-r from-red-500 via-amber-500 to-emerald-500"
                initial={{ width: 0 }}
                animate={{ width: '100%' }}
                transition={{ duration: 1.2, delay: 0.5 }}
              />
            </div>
            <span className="text-sm font-mono font-bold text-emerald-400">
              +{item.preciseResult - item.vagueResult}%
            </span>
          </motion.div>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// TEMPLATE BUILDER TAB
// =============================================================================

function TemplateBuilderTab() {
  const [enabledSections, setEnabledSections] = useState<Set<string>>(
    () => new Set(['role', 'task', 'context'])
  );
  const [sectionOrder, setSectionOrder] = useState<string[]>(
    () => TEMPLATE_SECTIONS.map((s) => s.id)
  );
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const dragOverRef = useRef<string | null>(null);

  const toggleSection = useCallback((id: string) => {
    setEnabledSections((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleDragStart = useCallback((id: string) => {
    setDraggedId(id);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent, overId: string) => {
    e.preventDefault();
    dragOverRef.current = overId;
  }, []);

  const handleDrop = useCallback(() => {
    if (draggedId && dragOverRef.current && draggedId !== dragOverRef.current) {
      setSectionOrder((prev) => {
        const arr = [...prev];
        const fromIdx = arr.indexOf(draggedId);
        const toIdx = arr.indexOf(dragOverRef.current!);
        if (fromIdx === -1 || toIdx === -1) return prev;
        arr.splice(fromIdx, 1);
        arr.splice(toIdx, 0, draggedId);
        return arr;
      });
    }
    setDraggedId(null);
    dragOverRef.current = null;
  }, [draggedId]);

  const handleDragEnd = useCallback(() => {
    setDraggedId(null);
    dragOverRef.current = null;
  }, []);

  const builtPrompt = useMemo(() => {
    return sectionOrder
      .filter((id) => enabledSections.has(id))
      .map((id) => {
        const section = TEMPLATE_SECTIONS.find((s) => s.id === id);
        if (!section) return '';
        return `[${section.label.toUpperCase()}]\n${section.text}`;
      })
      .join('\n\n');
  }, [enabledSections, sectionOrder]);

  const qualityScore = useMemo(() => {
    let score = 0;
    if (enabledSections.has('role')) score += 15;
    if (enabledSections.has('task')) score += 25;
    if (enabledSections.has('context')) score += 25;
    if (enabledSections.has('constraints')) score += 15;
    if (enabledSections.has('output')) score += 10;
    if (enabledSections.has('examples')) score += 10;
    return score;
  }, [enabledSections]);

  return (
    <div className="space-y-5">
      <p className="text-xs text-white/40">
        Drag to reorder sections. Toggle to include or exclude. Watch the assembled prompt and quality score update in real time.
      </p>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* Section toggles - drag and drop */}
        <div className="space-y-2">
          <div className="flex items-center gap-2 mb-3">
            <Layers className="h-3.5 w-3.5 text-white/40" />
            <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">Template Sections</span>
          </div>
          {sectionOrder.map((sectionId) => {
            const section = TEMPLATE_SECTIONS.find((s) => s.id === sectionId);
            if (!section) return null;
            const isEnabled = enabledSections.has(section.id);
            const isDragging = draggedId === section.id;

            return (
              <motion.div
                key={section.id}
                layout
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                draggable
                onDragStart={() => handleDragStart(section.id)}
                onDragOver={(e: React.DragEvent) => handleDragOver(e, section.id)}
                onDrop={handleDrop}
                onDragEnd={handleDragEnd}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-lg border transition-all cursor-grab active:cursor-grabbing ${
                  isDragging
                    ? 'border-primary/40 bg-primary/10 opacity-50'
                    : isEnabled
                      ? 'border-white/[0.12] bg-white/[0.04]'
                      : 'border-white/[0.06] bg-white/[0.01] opacity-50'
                }`}
              >
                <Grip className="h-3.5 w-3.5 text-white/20 shrink-0" />
                <button
                  onClick={() => toggleSection(section.id)}
                  className={`h-4 w-4 rounded border flex items-center justify-center shrink-0 transition-all ${
                    isEnabled
                      ? 'bg-primary/20 border-primary/40 text-primary'
                      : 'border-white/20 text-transparent'
                  }`}
                >
                  {isEnabled && <Check className="h-2.5 w-2.5" />}
                </button>
                <span className={`text-xs font-medium ${section.color}`}>{section.label}</span>
                <span className="flex-1 text-[10px] text-white/30 truncate font-mono">{section.text.split('\n')[0]}</span>
              </motion.div>
            );
          })}
        </div>

        {/* Assembled prompt preview */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <FileText className="h-3.5 w-3.5 text-white/40" />
              <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">Assembled Prompt</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] text-white/30">Quality:</span>
              <span className={`text-xs font-mono font-bold ${
                qualityScore >= 80 ? 'text-emerald-400' : qualityScore >= 50 ? 'text-amber-400' : 'text-red-400'
              }`}>
                {qualityScore}/100
              </span>
            </div>
          </div>

          {/* Quality bar */}
          <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
            <motion.div
              className={`h-full rounded-full ${
                qualityScore >= 80 ? 'bg-emerald-500' : qualityScore >= 50 ? 'bg-amber-500' : 'bg-red-500'
              }`}
              animate={{ width: `${qualityScore}%` }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            />
          </div>

          <div className="rounded-xl bg-black/40 border border-white/[0.06] p-4 max-h-[320px] overflow-y-auto">
            <AnimatePresence mode="wait">
              <motion.div
                key={builtPrompt}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
              >
                {builtPrompt ? (
                  <pre className="font-mono text-xs leading-relaxed text-white/60 whitespace-pre-wrap">{builtPrompt}</pre>
                ) : (
                  <p className="text-xs text-white/30 italic">Enable sections to build your prompt template...</p>
                )}
              </motion.div>
            </AnimatePresence>
          </div>

          {/* Section count badges */}
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-[10px] text-white/30">{enabledSections.size} of {TEMPLATE_SECTIONS.length} sections active</span>
            <div className="flex-1" />
            {enabledSections.size < TEMPLATE_SECTIONS.length && (
              <button
                onClick={() => setEnabledSections(new Set(TEMPLATE_SECTIONS.map((s) => s.id)))}
                className="text-[10px] text-primary/70 hover:text-primary transition-colors"
              >
                Enable all
              </button>
            )}
            {enabledSections.size > 0 && (
              <button
                onClick={() => setEnabledSections(new Set())}
                className="text-[10px] text-white/30 hover:text-white/50 transition-colors"
              >
                Clear all
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// AGENT TERMINAL TAB
// =============================================================================

function AgentTerminalTab() {
  const [visibleLines, setVisibleLines] = useState(0);
  const [isRunning, setIsRunning] = useState(false);
  const terminalRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const startSimulation = useCallback(() => {
    setVisibleLines(0);
    setIsRunning(true);
  }, []);

  useEffect(() => {
    if (!isRunning) return;

    if (visibleLines >= TERMINAL_LINES.length) return;

    const line = TERMINAL_LINES[visibleLines];
    const delay = line?.type === 'command' ? 600 : line?.type === 'progress' ? 800 : line?.type === 'agent' ? 300 : 150;

    timerRef.current = setTimeout(() => {
      setVisibleLines((prev) => prev + 1);
    }, delay);

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [isRunning, visibleLines]);

  // Stop running when all lines shown
  useEffect(() => {
    if (isRunning && visibleLines >= TERMINAL_LINES.length) {
      setTimeout(() => setIsRunning(false), 0);
    }
  }, [isRunning, visibleLines]);

  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [visibleLines]);

  function getLineStyle(type: string) {
    switch (type) {
      case 'command': return 'text-emerald-400 font-semibold';
      case 'result': return 'text-blue-400';
      case 'progress': return 'text-amber-400/70';
      case 'success': return 'text-emerald-400';
      case 'agent': return 'text-violet-300';
      default: return 'text-white/50';
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-xs text-white/40">
          Watch a prompt being searched, installed, and executed in an agent terminal.
        </p>
        <button
          onClick={startSimulation}
          disabled={isRunning}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
            isRunning
              ? 'bg-white/[0.04] text-white/30 border border-white/[0.06] cursor-wait'
              : 'bg-primary/10 text-primary border border-primary/30 hover:bg-primary/20'
          }`}
        >
          {isRunning ? (
            <>
              <motion.span animate={{ rotate: 360 }} transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}>
                <Loader2 className="h-3 w-3" />
              </motion.span>
              Running...
            </>
          ) : (
            <>
              <Play className="h-3 w-3" />
              {visibleLines > 0 ? 'Replay' : 'Run Demo'}
            </>
          )}
        </button>
      </div>

      {/* Terminal window */}
      <div className="rounded-xl border border-white/[0.08] bg-black/60 overflow-hidden">
        {/* Title bar */}
        <div className="flex items-center gap-2 px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.02]">
          <div className="flex gap-1.5">
            <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
            <div className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
            <div className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
          </div>
          <span className="text-[10px] text-white/30 font-mono ml-2">agent-terminal -- jfp</span>
          <div className="flex-1" />
          <Terminal className="h-3 w-3 text-white/20" />
        </div>

        {/* Terminal content */}
        <div ref={terminalRef} className="p-4 font-mono text-xs leading-relaxed max-h-[360px] overflow-y-auto space-y-0.5">
          {visibleLines === 0 && !isRunning && (
            <div className="flex flex-col items-center justify-center py-8 gap-2 text-white/20">
              <Send className="h-6 w-6" />
              <p className="text-xs">Click &quot;Run Demo&quot; to start the simulation</p>
            </div>
          )}
          {TERMINAL_LINES.slice(0, visibleLines).map((line, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, x: -4 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.15 }}
              className={getLineStyle(line.type)}
            >
              {line.text || '\u00A0'}
            </motion.div>
          ))}
          {isRunning && (
            <motion.span
              animate={{ opacity: [1, 0] }}
              transition={{ duration: 0.6, repeat: Infinity, repeatType: 'reverse' }}
              className="inline-block w-2 h-3.5 bg-emerald-400/70 ml-0.5"
            />
          )}
        </div>
      </div>

      {/* Status bar */}
      <div className="flex items-center gap-4 text-[10px] text-white/30 px-1">
        <span>Lines: {visibleLines}/{TERMINAL_LINES.length}</span>
        <div className="flex-1 h-px bg-white/[0.06]" />
        <span className={`flex items-center gap-1 ${isRunning ? 'text-emerald-400/70' : 'text-white/30'}`}>
          <div className={`h-1.5 w-1.5 rounded-full ${isRunning ? 'bg-emerald-400' : 'bg-white/20'}`} />
          {isRunning ? 'Executing' : visibleLines > 0 ? 'Complete' : 'Ready'}
        </span>
      </div>
    </div>
  );
}

// =============================================================================
// MAIN INTERACTIVE PROMPT GALLERY (LABORATORY)
// =============================================================================

function InteractivePromptGallery() {
  const [activeTab, setActiveTab] = useState<LabTab>('evolution');

  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Decorative glows */}
      <div className="absolute top-0 right-1/4 w-48 h-48 bg-primary/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 left-1/4 w-32 h-32 bg-amber-500/10 rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-6 space-y-5">
        {/* Lab header */}
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 border border-primary/20">
            <Beaker className="h-4 w-4 text-primary" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-white">Prompt Crafting Lab</h3>
            <p className="text-[10px] text-white/30">Explore, compare, build, and test prompts</p>
          </div>
        </div>

        {/* Tab bar */}
        <div className="flex gap-1 p-1 rounded-xl bg-white/[0.03] border border-white/[0.06]">
          {TAB_CONFIG.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`relative flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition-all flex-1 justify-center ${
                activeTab === tab.id
                  ? 'text-primary'
                  : 'text-white/40 hover:text-white/60'
              }`}
            >
              {activeTab === tab.id && (
                <motion.div
                  layoutId="lab-tab-bg"
                  className="absolute inset-0 rounded-lg bg-primary/10 border border-primary/20"
                  transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                />
              )}
              <span className="relative flex items-center gap-1.5">
                {tab.icon}
                <span className="hidden sm:inline">{tab.label}</span>
              </span>
            </button>
          ))}
        </div>

        {/* Tab content */}
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          >
            {activeTab === 'evolution' && <PromptEvolutionTab />}
            {activeTab === 'compare' && <VagueVsPreciseTab />}
            {activeTab === 'builder' && <TemplateBuilderTab />}
            {activeTab === 'terminal' && <AgentTerminalTab />}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
