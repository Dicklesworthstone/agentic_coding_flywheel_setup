'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Terminal,
  RefreshCw,
  FileText,
  Brain,
  Play,
  Pause,
  Zap,
  PenLine,
  Search,
  Sparkles,
  ChevronRight,
  Shield,
  Gauge,
  AlertTriangle,
  MessageSquare,
  Eye,
  ArrowRight,
  Check,
  X,
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

export function AprLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master AI-powered plan revision with Automated Plan Reviser Pro.
      </GoalBanner>

      {/* Section 1: What Is APR */}
      <Section title="What Is APR?" icon={<RefreshCw className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>APR (Automated Plan Reviser Pro)</Highlight> automates iterative specification
          refinement using extended AI reasoning. Instead of manually running 15-20 review rounds,
          APR orchestrates the process automatically.
        </Paragraph>
        <Paragraph>
          Early rounds fix architectural issues, middle rounds refine structure, later rounds
          polish abstractions. The process resembles numerical optimization settling into a minimum.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Brain className="h-5 w-5" />}
              title="AI-Powered"
              description="Uses advanced LLMs to refine plans"
              gradient="from-teal-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Markdown Support"
              description="Works with your existing plan files"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<RefreshCw className="h-5 w-5" />}
              title="Iterative"
              description="Refine plans through multiple passes"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fast"
              description="Get improved plans in seconds"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Interactive Refinement Loop Visualization */}
      <Section title="The Refinement Cycle" icon={<RefreshCw className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Watch how APR iteratively improves a specification through multiple passes.
          Each cycle tightens the quality until the plan converges on a polished result.
        </Paragraph>
        <div className="mt-8">
          <InteractiveRefinementLoop />
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'apr refine plan.md', description: 'Refine a plan file' },
            { command: 'apr refine --output revised.md', description: 'Save to specific file' },
            { command: 'apr --help', description: 'Show all options' },
          ]}
        />

        <TipBox>
          Use APR after Claude Code generates an initial plan to get a more thorough version.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Typical Workflow */}
      <Section title="Typical Workflow" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <CodeBlock code={`# 1. Generate initial plan with Claude Code
# (Claude creates plan.md)

# 2. Refine with APR
apr refine plan.md -o refined-plan.md

# 3. Review the refined plan
cat refined-plan.md

# 4. Feed back to Claude Code for implementation`} />
      </Section>
    </div>
  );
}

// =============================================================================
// INTERACTIVE REFINEMENT LOOP - Autonomous refinement engine visualization
// =============================================================================

// --- Types ---

interface ReviewCheck {
  category: string;
  label: string;
  status: 'pass' | 'fail' | 'warn' | 'pending';
  detail: string;
}

interface ReviewerComment {
  line: number;
  author: string;
  text: string;
  type: 'suggestion' | 'issue' | 'praise';
}

interface PlanLine {
  text: string;
  status: 'unchanged' | 'added' | 'removed' | 'modified';
}

interface IterationData {
  id: number;
  title: string;
  subtitle: string;
  icon: React.ReactNode;
  color: string;
  quality: number;
  planLines: PlanLine[];
  checks: ReviewCheck[];
  comments: ReviewerComment[];
  terminalLines: string[];
  changeSummary: string;
}

// --- Data ---

const ITERATION_DATA: IterationData[] = [
  {
    id: 1,
    title: 'Initial Draft',
    subtitle: 'Raw specification from LLM',
    icon: <PenLine className="h-4 w-4" />,
    color: '#ef4444',
    quality: 28,
    planLines: [
      { text: '# Auth Service Plan', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'Build a login and signup system.', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Features', status: 'unchanged' },
      { text: '- Add login', status: 'unchanged' },
      { text: '- Add signup', status: 'unchanged' },
      { text: '- Handle tokens', status: 'unchanged' },
      { text: '- Basic error handling', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Database', status: 'unchanged' },
      { text: '- Store users somewhere', status: 'unchanged' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'fail', detail: 'No endpoints specified' },
      { category: 'architecture', label: 'Data models present', status: 'fail', detail: 'No schema definitions' },
      { category: 'security', label: 'Auth strategy defined', status: 'fail', detail: 'No token strategy' },
      { category: 'security', label: 'Input validation', status: 'fail', detail: 'Not addressed' },
      { category: 'performance', label: 'Rate limiting', status: 'fail', detail: 'Not mentioned' },
      { category: 'edge-cases', label: 'Error handling', status: 'warn', detail: 'Only "basic" mentioned' },
    ],
    comments: [
      { line: 3, author: 'Architecture Review', text: 'Too vague -- needs concrete endpoints, methods, request/response shapes.', type: 'issue' },
      { line: 8, author: 'Security Audit', text: '"Handle tokens" is underspecified. Define token type, expiry, rotation strategy.', type: 'issue' },
      { line: 12, author: 'Architecture Review', text: '"Store users somewhere" needs a schema with fields and constraints.', type: 'issue' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 1',
      'Loading plan.md (13 lines)...',
      'Running architecture review...',
      '[FAIL] 5 critical issues found',
      '[WARN] 1 concern flagged',
      'Generating revision...',
    ],
    changeSummary: 'Initial draft loaded. Major gaps in all categories.',
  },
  {
    id: 2,
    title: 'Architecture Review',
    subtitle: 'Endpoints, data models, structure',
    icon: <Search className="h-4 w-4" />,
    color: '#f97316',
    quality: 45,
    planLines: [
      { text: '# Auth Service Plan', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'JWT-based authentication service with REST API.', status: 'modified' },
      { text: '', status: 'unchanged' },
      { text: '## API Endpoints', status: 'modified' },
      { text: '- POST /auth/login {email, password}', status: 'added' },
      { text: '- POST /auth/signup {email, password, name}', status: 'added' },
      { text: '- POST /auth/refresh {refreshToken}', status: 'added' },
      { text: '- Handle tokens', status: 'removed' },
      { text: '', status: 'unchanged' },
      { text: '## Token Strategy', status: 'added' },
      { text: '- Access token: JWT, 15min expiry', status: 'added' },
      { text: '- Refresh token: opaque, 7d expiry', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Database', status: 'unchanged' },
      { text: '- Users table with email, hashed password, name', status: 'modified' },
      { text: '- Basic error handling', status: 'removed' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'pass', detail: '3 endpoints specified' },
      { category: 'architecture', label: 'Data models present', status: 'warn', detail: 'Partial schema only' },
      { category: 'security', label: 'Auth strategy defined', status: 'pass', detail: 'JWT + refresh token' },
      { category: 'security', label: 'Input validation', status: 'fail', detail: 'No validation rules' },
      { category: 'performance', label: 'Rate limiting', status: 'fail', detail: 'Not addressed' },
      { category: 'edge-cases', label: 'Error handling', status: 'fail', detail: 'Removed, not replaced' },
    ],
    comments: [
      { line: 6, author: 'Architecture Review', text: 'Good. Now add response shapes for each endpoint.', type: 'suggestion' },
      { line: 13, author: 'Security Audit', text: 'Specify signing algorithm (RS256 vs HS256) and key rotation.', type: 'suggestion' },
      { line: 16, author: 'Architecture Review', text: 'Add full column definitions, types, and constraints.', type: 'issue' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 2',
      'Applying architecture review fixes...',
      '[PASS] Endpoints now defined',
      '[PASS] Token strategy added',
      '[FAIL] 2 issues remain',
      'Quality: 28% -> 45% (+17)',
    ],
    changeSummary: 'Added endpoints, token strategy. Data models still incomplete.',
  },
  {
    id: 3,
    title: 'Edge Case Analysis',
    subtitle: 'Error handling, validation, boundaries',
    icon: <AlertTriangle className="h-4 w-4" />,
    color: '#eab308',
    quality: 62,
    planLines: [
      { text: '# Auth Service Plan', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'JWT-based authentication service with REST API.', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## API Endpoints', status: 'unchanged' },
      { text: '- POST /auth/login {email, password} -> {access, refresh}', status: 'modified' },
      { text: '- POST /auth/signup {email, password, name} -> {access, refresh}', status: 'modified' },
      { text: '- POST /auth/refresh {refreshToken} -> {access}', status: 'modified' },
      { text: '', status: 'unchanged' },
      { text: '## Validation Rules', status: 'added' },
      { text: '- email: valid format, max 255 chars', status: 'added' },
      { text: '- password: min 8 chars, 1 uppercase, 1 number', status: 'added' },
      { text: '- name: 1-100 chars, trimmed', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Error Responses', status: 'added' },
      { text: '- 400: Malformed request body', status: 'added' },
      { text: '- 401: Invalid credentials (generic msg)', status: 'added' },
      { text: '- 409: Email already registered', status: 'added' },
      { text: '- 422: Validation errors array', status: 'added' },
      { text: '- 429: Rate limit exceeded', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Token Strategy', status: 'unchanged' },
      { text: '- Access token: JWT, 15min expiry', status: 'unchanged' },
      { text: '- Refresh token: opaque, 7d expiry', status: 'unchanged' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'pass', detail: 'Response shapes added' },
      { category: 'architecture', label: 'Data models present', status: 'warn', detail: 'Schema still needs types' },
      { category: 'security', label: 'Auth strategy defined', status: 'pass', detail: 'JWT + refresh token' },
      { category: 'security', label: 'Input validation', status: 'pass', detail: 'Rules defined per field' },
      { category: 'performance', label: 'Rate limiting', status: 'warn', detail: 'Mentioned in errors but no config' },
      { category: 'edge-cases', label: 'Error handling', status: 'pass', detail: '5 error codes documented' },
    ],
    comments: [
      { line: 12, author: 'Edge Case Analyzer', text: 'Good validation. Consider adding password deny-list (common passwords).', type: 'suggestion' },
      { line: 20, author: 'Edge Case Analyzer', text: 'Rate limit error defined but no rate limit configuration section.', type: 'issue' },
      { line: 6, author: 'Architecture Review', text: 'Endpoint shapes look solid now.', type: 'praise' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 3',
      'Running edge case analysis...',
      '[PASS] Input validation rules added',
      '[PASS] Error responses documented',
      '[WARN] Rate limit config missing',
      'Quality: 45% -> 62% (+17)',
    ],
    changeSummary: 'Added validation rules, error responses. Rate limiting needs config.',
  },
  {
    id: 4,
    title: 'Performance Optimization',
    subtitle: 'Rate limits, caching, indexing',
    icon: <Gauge className="h-4 w-4" />,
    color: '#22c55e',
    quality: 78,
    planLines: [
      { text: '# Auth Service Plan', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'JWT-based authentication service with REST API.', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## API Endpoints', status: 'unchanged' },
      { text: '| Method | Path           | Body                    | Response          |', status: 'modified' },
      { text: '|--------|----------------|-------------------------|-------------------|', status: 'added' },
      { text: '| POST   | /auth/login    | {email, password}       | {access, refresh} |', status: 'modified' },
      { text: '| POST   | /auth/signup   | {email, password, name} | {access, refresh} |', status: 'modified' },
      { text: '| POST   | /auth/refresh  | {refreshToken}          | {access}          |', status: 'modified' },
      { text: '| POST   | /auth/logout   | {refreshToken}          | 204 No Content    |', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Rate Limiting', status: 'added' },
      { text: '- Login: 5 req/min/IP, exponential backoff', status: 'added' },
      { text: '- Signup: 3 req/min/IP', status: 'added' },
      { text: '- Refresh: 10 req/min/user', status: 'added' },
      { text: '- Redis-backed sliding window counter', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Database Schema', status: 'modified' },
      { text: '- users(id UUID PK, email UNIQUE, password_hash, name, ...)', status: 'modified' },
      { text: '- refresh_tokens(id UUID PK, user_id FK, token_hash, ...)', status: 'added' },
      { text: '- Index: users(email), refresh_tokens(token_hash)', status: 'added' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'pass', detail: 'Table format with logout' },
      { category: 'architecture', label: 'Data models present', status: 'pass', detail: 'Full schema with indices' },
      { category: 'security', label: 'Auth strategy defined', status: 'pass', detail: 'JWT + refresh token' },
      { category: 'security', label: 'Input validation', status: 'pass', detail: 'Rules defined per field' },
      { category: 'performance', label: 'Rate limiting', status: 'pass', detail: 'Per-endpoint with Redis' },
      { category: 'edge-cases', label: 'Error handling', status: 'pass', detail: '5 error codes documented' },
    ],
    comments: [
      { line: 11, author: 'Performance Review', text: 'Logout endpoint added -- good for token revocation.', type: 'praise' },
      { line: 14, author: 'Performance Review', text: 'Redis sliding window is the right choice here.', type: 'praise' },
      { line: 20, author: 'Architecture Review', text: 'Add created_at/updated_at timestamps and soft delete.', type: 'suggestion' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 4',
      'Running performance optimization...',
      '[PASS] Rate limiting configured',
      '[PASS] Database indices added',
      '[PASS] All 6 checks passing',
      'Quality: 62% -> 78% (+16)',
    ],
    changeSummary: 'Added rate limiting, database schema with indices, logout endpoint.',
  },
  {
    id: 5,
    title: 'Security Audit',
    subtitle: 'Hardening, secrets, threat model',
    icon: <Shield className="h-4 w-4" />,
    color: '#3b82f6',
    quality: 90,
    planLines: [
      { text: '# Auth Service Plan (v5 - security hardened)', status: 'modified' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'JWT-based auth service. RS256 signed tokens.', status: 'modified' },
      { text: '', status: 'unchanged' },
      { text: '## API Endpoints', status: 'unchanged' },
      { text: '| Method | Path           | Body                    | Response          |', status: 'unchanged' },
      { text: '|--------|----------------|-------------------------|-------------------|', status: 'unchanged' },
      { text: '| POST   | /auth/login    | {email, password}       | {access, refresh} |', status: 'unchanged' },
      { text: '| POST   | /auth/signup   | {email, password, name} | {access, refresh} |', status: 'unchanged' },
      { text: '| POST   | /auth/refresh  | {refreshToken}          | {access}          |', status: 'unchanged' },
      { text: '| POST   | /auth/logout   | {refreshToken}          | 204 No Content    |', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Security', status: 'added' },
      { text: '- Passwords: bcrypt cost 12, reject top-10k common', status: 'added' },
      { text: '- Tokens: RS256, kid header, 15min access / 7d refresh', status: 'added' },
      { text: '- Refresh rotation: single-use, reuse detection -> revoke family', status: 'added' },
      { text: '- CORS: allow-list origins, no wildcards', status: 'added' },
      { text: '- Headers: HSTS, X-Content-Type-Options, X-Frame-Options', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Rate Limiting', status: 'unchanged' },
      { text: '- Login: 5 req/min/IP, exponential backoff on failure', status: 'modified' },
      { text: '- Account lockout after 10 consecutive failures (30min)', status: 'added' },
      { text: '- Signup: 3 req/min/IP', status: 'unchanged' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'pass', detail: 'Table format with logout' },
      { category: 'architecture', label: 'Data models present', status: 'pass', detail: 'Full schema with indices' },
      { category: 'security', label: 'Auth strategy defined', status: 'pass', detail: 'RS256 with kid rotation' },
      { category: 'security', label: 'Input validation', status: 'pass', detail: 'With password deny-list' },
      { category: 'performance', label: 'Rate limiting', status: 'pass', detail: 'Backoff + account lockout' },
      { category: 'edge-cases', label: 'Error handling', status: 'pass', detail: 'Generic messages, no leaks' },
    ],
    comments: [
      { line: 16, author: 'Security Audit', text: 'Refresh token family revocation is excellent for detecting token theft.', type: 'praise' },
      { line: 14, author: 'Security Audit', text: 'bcrypt(12) + common password reject -- solid password policy.', type: 'praise' },
      { line: 22, author: 'Security Audit', text: 'Account lockout prevents brute-force while backoff slows automation.', type: 'praise' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 5',
      'Running security audit...',
      '[PASS] Password hashing hardened',
      '[PASS] Token rotation secured',
      '[PASS] Security headers specified',
      'Quality: 78% -> 90% (+12)',
    ],
    changeSummary: 'Added security section, password policy, CORS, token rotation, lockout.',
  },
  {
    id: 6,
    title: 'Final Polish',
    subtitle: 'Converged -- production-ready spec',
    icon: <Sparkles className="h-4 w-4" />,
    color: '#a855f7',
    quality: 97,
    planLines: [
      { text: '# Auth Service Plan (v6 - final)', status: 'modified' },
      { text: '', status: 'unchanged' },
      { text: '## Overview', status: 'unchanged' },
      { text: 'Production-ready JWT auth. RS256, refresh rotation,', status: 'modified' },
      { text: 'bcrypt(12), Redis rate-limits. Deploys as standalone', status: 'added' },
      { text: 'microservice behind API gateway.', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## API Endpoints', status: 'unchanged' },
      { text: '| Method | Path           | Body                    | Response          |', status: 'unchanged' },
      { text: '|--------|----------------|-------------------------|-------------------|', status: 'unchanged' },
      { text: '| POST   | /auth/login    | {email, password}       | {access, refresh} |', status: 'unchanged' },
      { text: '| POST   | /auth/signup   | {email, password, name} | {access, refresh} |', status: 'unchanged' },
      { text: '| POST   | /auth/refresh  | {refreshToken}          | {access}          |', status: 'unchanged' },
      { text: '| POST   | /auth/logout   | {refreshToken}          | 204 No Content    |', status: 'unchanged' },
      { text: '', status: 'unchanged' },
      { text: '## Observability', status: 'added' },
      { text: '- Structured JSON logs (login_success, login_fail, ...)', status: 'added' },
      { text: '- Prometheus metrics: auth_requests_total, auth_latency_ms', status: 'added' },
      { text: '- Distributed tracing via OpenTelemetry', status: 'added' },
      { text: '', status: 'unchanged' },
      { text: '## Deployment', status: 'added' },
      { text: '- Docker image, Helm chart, health check on /healthz', status: 'added' },
      { text: '- Graceful shutdown with 30s drain period', status: 'added' },
      { text: '- Config via env vars (12-factor)', status: 'added' },
    ],
    checks: [
      { category: 'architecture', label: 'API endpoints defined', status: 'pass', detail: 'Complete with all verbs' },
      { category: 'architecture', label: 'Data models present', status: 'pass', detail: 'Full schema, indices, FK' },
      { category: 'security', label: 'Auth strategy defined', status: 'pass', detail: 'RS256, rotation, lockout' },
      { category: 'security', label: 'Input validation', status: 'pass', detail: 'Comprehensive rules' },
      { category: 'performance', label: 'Rate limiting', status: 'pass', detail: 'Redis sliding window' },
      { category: 'edge-cases', label: 'Error handling', status: 'pass', detail: 'All codes documented' },
    ],
    comments: [
      { line: 16, author: 'Final Review', text: 'Observability section ensures production debuggability.', type: 'praise' },
      { line: 21, author: 'Final Review', text: 'Deployment spec with health checks -- ready for k8s.', type: 'praise' },
      { line: 0, author: 'APR Engine', text: 'Converged. Quality delta < 3% -- no further passes needed.', type: 'praise' },
    ],
    terminalLines: [
      '$ apr refine plan.md --pass 6',
      'Running final polish...',
      '[PASS] All 6 checks passing',
      '[INFO] Quality delta: +7 (< 10 threshold)',
      '[DONE] Converged after 6 passes',
      'Quality: 90% -> 97% -- FINAL',
      '',
      '$ cat refined-plan.md | wc -l',
      '  87 lines (was 13)',
    ],
    changeSummary: 'Added observability, deployment. Converged -- production-ready.',
  },
];

// --- Helpers ---

function getCheckIcon(status: ReviewCheck['status']) {
  switch (status) {
    case 'pass':
      return <Check className="h-3 w-3 text-emerald-400" />;
    case 'fail':
      return <X className="h-3 w-3 text-red-400" />;
    case 'warn':
      return <AlertTriangle className="h-3 w-3 text-amber-400" />;
    case 'pending':
      return <RefreshCw className="h-3 w-3 text-white/30 animate-spin" />;
  }
}

function getCheckBg(status: ReviewCheck['status']) {
  switch (status) {
    case 'pass':
      return 'bg-emerald-500/10 border-emerald-500/20';
    case 'fail':
      return 'bg-red-500/10 border-red-500/20';
    case 'warn':
      return 'bg-amber-500/10 border-amber-500/20';
    case 'pending':
      return 'bg-white/[0.03] border-white/[0.08]';
  }
}

function getCommentColor(type: ReviewerComment['type']) {
  switch (type) {
    case 'issue':
      return { bg: 'bg-red-500/10', border: 'border-red-500/25', text: 'text-red-300', icon: <X className="h-3 w-3 text-red-400" /> };
    case 'suggestion':
      return { bg: 'bg-amber-500/10', border: 'border-amber-500/25', text: 'text-amber-300', icon: <AlertTriangle className="h-3 w-3 text-amber-400" /> };
    case 'praise':
      return { bg: 'bg-emerald-500/10', border: 'border-emerald-500/25', text: 'text-emerald-300', icon: <Check className="h-3 w-3 text-emerald-400" /> };
  }
}

function getLineBg(status: PlanLine['status']) {
  switch (status) {
    case 'added':
      return 'bg-emerald-500/[0.08]';
    case 'removed':
      return 'bg-red-500/[0.08]';
    case 'modified':
      return 'bg-amber-500/[0.06]';
    case 'unchanged':
      return '';
  }
}

function getLinePrefix(status: PlanLine['status']) {
  switch (status) {
    case 'added':
      return { char: '+', color: 'text-emerald-400' };
    case 'removed':
      return { char: '-', color: 'text-red-400' };
    case 'modified':
      return { char: '~', color: 'text-amber-400' };
    case 'unchanged':
      return { char: ' ', color: 'text-white/20' };
  }
}

// --- Sub-components ---

function QualityChart({ iterations, currentIdx }: { iterations: IterationData[]; currentIdx: number }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <div ref={rootRef} className="rounded-xl border border-white/[0.08] bg-black/30 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
          Quality Progression
        </span>
        <motion.span
          key={iterations[currentIdx].quality}
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          className="text-sm font-bold"
          style={{ color: iterations[currentIdx].color }}
        >
          {iterations[currentIdx].quality}%
        </motion.span>
      </div>

      {/* Bar chart */}
      <div className="flex items-end gap-1 h-20">
        {iterations.map((iter, i) => {
          const isVisible = i <= currentIdx;
          const height = isVisible ? `${iter.quality}%` : '0%';
          return (
            <div key={iter.id} className="flex-1 flex flex-col items-center gap-1">
              <motion.div
                className="w-full rounded-t-sm relative overflow-hidden"
                style={{ backgroundColor: isVisible ? iter.color : 'transparent' }}
                animate={{ height, opacity: isVisible ? 1 : 0.15 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25, delay: isVisible ? i * 0.05 : 0 }}
              >
                {isVisible && i === currentIdx && (
                  <motion.div
                    className="absolute inset-0 bg-white/10"
                    animate={inView ? { opacity: [0, 0.3, 0] } : { opacity: 0 }}
                    transition={inView ? { duration: 2, repeat: Infinity } : { duration: 0.2 }}
                  />
                )}
              </motion.div>
              <span
                className="text-[10px] font-mono transition-colors duration-300"
                style={{ color: isVisible ? iter.color : 'rgba(255,255,255,0.2)' }}
              >
                {isVisible ? `${iter.quality}` : ''}
              </span>
            </div>
          );
        })}
      </div>

      {/* Labels */}
      <div className="flex gap-1">
        {iterations.map((iter, i) => (
          <div
            key={iter.id}
            className="flex-1 text-center text-[10px] font-medium transition-colors duration-300"
            style={{
              color: i <= currentIdx ? iter.color : 'rgba(255,255,255,0.15)',
              opacity: i === currentIdx ? 1 : 0.6,
            }}
          >
            P{iter.id}
          </div>
        ))}
      </div>
    </div>
  );
}

function ReviewPanel({ checks, animateIn }: { checks: ReviewCheck[]; animateIn: boolean }) {
  const passCount = checks.filter((c) => c.status === 'pass').length;
  const failCount = checks.filter((c) => c.status === 'fail').length;
  const warnCount = checks.filter((c) => c.status === 'warn').length;

  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider flex items-center gap-1.5">
          <Eye className="h-3 w-3" />
          Automated Checks
        </span>
        <div className="flex items-center gap-2 text-[10px] font-mono">
          {passCount > 0 && <span className="text-emerald-400">{passCount} pass</span>}
          {warnCount > 0 && <span className="text-amber-400">{warnCount} warn</span>}
          {failCount > 0 && <span className="text-red-400">{failCount} fail</span>}
        </div>
      </div>

      <div className="space-y-1.5">
        {checks.map((check, i) => (
          <motion.div
            key={`${check.category}-${check.label}`}
            initial={animateIn ? { opacity: 0, x: -8 } : false}
            animate={{ opacity: 1, x: 0 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25, delay: animateIn ? i * 0.06 : 0 }}
            className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg border text-[11px] ${getCheckBg(check.status)}`}
          >
            <div className="flex-shrink-0">{getCheckIcon(check.status)}</div>
            <span className="font-medium text-white/70 flex-1">{check.label}</span>
            <span className="text-white/40 text-[10px] hidden sm:inline">{check.detail}</span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

function PlanDocument({
  lines,
  comments,
  showComments,
  animateIn,
  iterColor,
}: {
  lines: PlanLine[];
  comments: ReviewerComment[];
  showComments: boolean;
  animateIn: boolean;
  iterColor: string;
}) {
  // Map comments to line indices for annotation display
  const commentsByLine: Record<number, ReviewerComment[]> = {};
  for (const c of comments) {
    if (!commentsByLine[c.line]) commentsByLine[c.line] = [];
    commentsByLine[c.line].push(c);
  }

  return (
    <div
      className="rounded-xl border overflow-hidden transition-colors duration-500"
      style={{ borderColor: `${iterColor}25` }}
    >
      {/* File header */}
      <div
        className="px-3 py-2 border-b flex items-center gap-2 transition-colors duration-500"
        style={{ borderColor: `${iterColor}15`, backgroundColor: `${iterColor}06` }}
      >
        <FileText className="h-3 w-3" style={{ color: iterColor }} />
        <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider">
          plan.md
        </span>
        <div className="flex-1" />
        <span className="text-[10px] font-mono text-white/30">
          {lines.filter((l) => l.status !== 'removed').length} lines
        </span>
      </div>

      {/* Plan content with diff markers */}
      <div className="max-h-[320px] overflow-y-auto">
        {lines.map((line, i) => {
          const prefix = getLinePrefix(line.status);
          const lineComments = showComments ? (commentsByLine[i] || []) : [];
          const isRemoved = line.status === 'removed';

          return (
            <motion.div
              key={`line-${i}-${line.text.slice(0, 20)}`}
              initial={animateIn ? { opacity: 0, x: -4 } : false}
              animate={{ opacity: 1, x: 0 }}
              transition={{
                type: 'spring',
                stiffness: 200,
                damping: 25,
                delay: animateIn ? i * 0.02 : 0,
              }}
            >
              <div className={`flex items-start px-1 ${getLineBg(line.status)}`}>
                {/* Line number */}
                <span className="w-6 text-right text-[10px] font-mono text-white/15 select-none py-0.5 flex-shrink-0">
                  {i + 1}
                </span>
                {/* Diff prefix */}
                <span className={`w-4 text-center text-[10px] font-mono ${prefix.color} select-none py-0.5 flex-shrink-0`}>
                  {prefix.char}
                </span>
                {/* Content */}
                <span
                  className={`flex-1 text-[11px] font-mono py-0.5 ${
                    isRemoved
                      ? 'text-red-400/50 line-through'
                      : line.status === 'added'
                        ? 'text-emerald-300/80'
                        : line.status === 'modified'
                          ? 'text-amber-200/80'
                          : 'text-white/60'
                  }`}
                >
                  {line.text || '\u00A0'}
                </span>
                {/* Comment indicator */}
                {lineComments.length > 0 && (
                  <span className="flex-shrink-0 px-1 py-0.5">
                    <MessageSquare className="h-3 w-3 text-amber-400/60" />
                  </span>
                )}
              </div>
              {/* Inline comments */}
              <AnimatePresence>
                {lineComments.map((comment, ci) => {
                  const cStyle = getCommentColor(comment.type);
                  return (
                    <motion.div
                      key={`comment-${i}-${ci}`}
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                      className={`ml-10 mr-2 mb-1 px-2.5 py-1.5 rounded-lg border ${cStyle.bg} ${cStyle.border}`}
                    >
                      <div className="flex items-start gap-1.5">
                        <div className="flex-shrink-0 mt-0.5">{cStyle.icon}</div>
                        <div>
                          <span className="text-[10px] font-semibold text-white/40 block">
                            {comment.author}
                          </span>
                          <span className={`text-[10px] ${cStyle.text}`}>
                            {comment.text}
                          </span>
                        </div>
                      </div>
                    </motion.div>
                  );
                })}
              </AnimatePresence>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}

function MiniTerminal({ lines, animateIn }: { lines: string[]; animateIn: boolean }) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
      <div className="px-3 py-1.5 border-b border-white/[0.06] flex items-center gap-2">
        <div className="flex gap-1">
          <div className="h-2 w-2 rounded-full bg-red-500/60" />
          <div className="h-2 w-2 rounded-full bg-amber-500/60" />
          <div className="h-2 w-2 rounded-full bg-emerald-500/60" />
        </div>
        <span className="text-[10px] font-mono text-white/30">terminal</span>
      </div>
      <div className="p-3 space-y-0.5 max-h-[160px] overflow-y-auto">
        {lines.map((line, i) => {
          const isCommand = line.startsWith('$');
          const isPass = line.includes('[PASS]');
          const isFail = line.includes('[FAIL]');
          const isWarn = line.includes('[WARN]');
          const isDone = line.includes('[DONE]');
          const isInfo = line.includes('[INFO]');

          let lineColor = 'text-white/50';
          if (isCommand) lineColor = 'text-white/80';
          if (isPass) lineColor = 'text-emerald-400/80';
          if (isFail) lineColor = 'text-red-400/80';
          if (isWarn) lineColor = 'text-amber-400/80';
          if (isDone) lineColor = 'text-purple-400/80';
          if (isInfo) lineColor = 'text-blue-400/80';

          return (
            <motion.div
              key={`term-${i}`}
              initial={animateIn ? { opacity: 0, x: -6 } : false}
              animate={{ opacity: 1, x: 0 }}
              transition={{
                type: 'spring',
                stiffness: 200,
                damping: 25,
                delay: animateIn ? i * 0.08 : 0,
              }}
              className={`text-[11px] font-mono ${lineColor} leading-relaxed`}
            >
              {line || '\u00A0'}
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}

function IterationNav({
  iterations,
  currentIdx,
  onSelect,
}: {
  iterations: IterationData[];
  currentIdx: number;
  onSelect: (idx: number) => void;
}) {
  return (
    <div className="flex items-center gap-1 overflow-x-auto pb-1">
      {iterations.map((iter, i) => {
        const isCurrent = i === currentIdx;
        const isPast = i < currentIdx;
        return (
          <motion.button
            type="button"
            key={iter.id}
            onClick={() => onSelect(i)}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={{ type: 'spring', stiffness: 400, damping: 25 }}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg transition-colors text-[10px] font-medium border flex-shrink-0"
            style={{
              backgroundColor: isCurrent ? `${iter.color}15` : 'transparent',
              borderColor: isCurrent ? `${iter.color}30` : isPast ? `${iter.color}10` : 'rgba(255,255,255,0.05)',
              color: isCurrent ? iter.color : isPast ? `${iter.color}` : 'rgba(255,255,255,0.3)',
              opacity: isCurrent ? 1 : isPast ? 0.7 : 0.4,
            }}
          >
            <div
              className="h-2 w-2 rounded-full flex-shrink-0 transition duration-300"
              style={{
                backgroundColor: iter.color,
                transform: isCurrent ? 'scale(1.3)' : 'scale(1)',
              }}
            />
            <span className="hidden sm:inline">{iter.title}</span>
            <span className="sm:hidden">P{iter.id}</span>
          </motion.button>
        );
      })}
    </div>
  );
}

// --- Active tab type for bottom panels ---
type ActiveTab = 'checks' | 'terminal' | 'comments';

// --- Main Component ---

function InteractiveRefinementLoop() {
  const [currentIdx, setCurrentIdx] = useState(0);
  const [isPlaying, setIsPlaying] = useState(true);
  const [showComments, setShowComments] = useState(true);
  const [activeTab, setActiveTab] = useState<ActiveTab>('checks');
  const [animateKey, setAnimateKey] = useState(0);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const iteration = ITERATION_DATA[currentIdx];
  const totalIterations = ITERATION_DATA.length;

  // Auto-advance
  useEffect(() => {
    if (!isPlaying) return;
    timerRef.current = setTimeout(() => {
      setCurrentIdx((prev) => (prev < totalIterations - 1 ? prev + 1 : 0));
      setAnimateKey((prev) => prev + 1);
    }, 4500);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [isPlaying, currentIdx, totalIterations]);

  const goToIteration = useCallback((idx: number) => {
    setCurrentIdx(idx);
    setAnimateKey((prev) => prev + 1);
  }, []);

  const togglePlay = useCallback(() => {
    setIsPlaying((prev) => !prev);
  }, []);

  const toggleComments = useCallback(() => {
    setShowComments((prev) => !prev);
  }, []);

  // Count stats for current iteration
  const passCount = iteration.checks.filter((c) => c.status === 'pass').length;
  const totalChecks = iteration.checks.length;
  const commentCount = iteration.comments.length;

  // Progress across all iterations
  const progressPercent = ((currentIdx + 1) / totalIterations) * 100;

  return (
    <div className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div
        className="absolute top-0 left-1/4 w-72 h-72 rounded-full blur-3xl pointer-events-none transition-colors duration-1000"
        style={{ backgroundColor: `${iteration.color}08` }}
      />
      <div
        className="absolute bottom-0 right-1/4 w-56 h-56 rounded-full blur-3xl pointer-events-none transition-colors duration-1000"
        style={{ backgroundColor: `${iteration.color}05` }}
      />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-violet-500/[0.03] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-8 space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-3">
            <AnimatePresence mode="wait">
              <motion.div
                key={currentIdx}
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0.8, opacity: 0 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className="flex items-center gap-2.5"
              >
                <span
                  className="inline-flex items-center justify-center h-9 w-9 rounded-xl text-sm font-bold text-white border-2 transition-colors duration-500"
                  style={{ borderColor: iteration.color, backgroundColor: `${iteration.color}15` }}
                >
                  {iteration.icon}
                </span>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-white/90">
                      Pass {iteration.id}: {iteration.title}
                    </span>
                    <span
                      className="text-[10px] px-2 py-0.5 rounded-full font-semibold transition-colors duration-500"
                      style={{ color: iteration.color, backgroundColor: `${iteration.color}15` }}
                    >
                      {iteration.quality}%
                    </span>
                  </div>
                  <span className="text-[11px] text-white/40">{iteration.subtitle}</span>
                </div>
              </motion.div>
            </AnimatePresence>
          </div>

          <div className="flex items-center gap-2">
            {/* Toggle comments */}
            <motion.button
              type="button"
              onClick={toggleComments}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              transition={{ type: 'spring', stiffness: 400, damping: 25 }}
              className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border text-[10px] font-medium transition-colors ${
                showComments
                  ? 'border-amber-500/30 bg-amber-500/10 text-amber-300'
                  : 'border-white/[0.1] bg-white/[0.04] text-white/50'
              }`}
            >
              <MessageSquare className="h-3 w-3" />
              <span className="hidden sm:inline">Comments</span>
            </motion.button>

            {/* Play/Pause */}
            <motion.button
              type="button"
              onClick={togglePlay}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              transition={{ type: 'spring', stiffness: 400, damping: 25 }}
              className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-white/[0.1] bg-white/[0.04] text-white/70 hover:text-white hover:border-white/[0.2] transition-colors text-[10px] font-medium"
            >
              {isPlaying ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {isPlaying ? 'Pause' : 'Play'}
            </motion.button>
          </div>
        </div>

        {/* Progress bar */}
        <div className="w-full h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="h-full rounded-full"
            style={{ backgroundColor: iteration.color }}
            animate={{ width: `${progressPercent}%` }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          />
        </div>

        {/* Iteration navigation */}
        <IterationNav
          iterations={ITERATION_DATA}
          currentIdx={currentIdx}
          onSelect={goToIteration}
        />

        {/* Main content grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-5">
          {/* Left column: Plan document (wider) */}
          <div className="lg:col-span-7 space-y-4">
            <AnimatePresence mode="wait">
              <motion.div
                key={`plan-${animateKey}`}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              >
                <PlanDocument
                  lines={iteration.planLines}
                  comments={iteration.comments}
                  showComments={showComments}
                  animateIn={true}
                  iterColor={iteration.color}
                  />
              </motion.div>
            </AnimatePresence>

            {/* Change summary */}
            <AnimatePresence mode="wait">
              <motion.div
                key={`summary-${currentIdx}`}
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className="flex items-start gap-2 px-3 py-2 rounded-lg border border-white/[0.06] bg-white/[0.02]"
              >
                <ArrowRight className="h-3 w-3 text-white/30 mt-0.5 flex-shrink-0" />
                <span className="text-xs text-white/50">{iteration.changeSummary}</span>
              </motion.div>
            </AnimatePresence>

            {/* Diff legend */}
            <div className="flex flex-wrap gap-3 px-1 text-[10px] font-mono text-white/40">
              <span className="flex items-center gap-1">
                <span className="inline-block w-2 h-2 rounded-sm bg-emerald-500/40" /> Added
              </span>
              <span className="flex items-center gap-1">
                <span className="inline-block w-2 h-2 rounded-sm bg-red-500/40" /> Removed
              </span>
              <span className="flex items-center gap-1">
                <span className="inline-block w-2 h-2 rounded-sm bg-amber-500/40" /> Modified
              </span>
              <span className="flex items-center gap-1">
                <span className="inline-block w-2 h-2 rounded-sm bg-white/10" /> Unchanged
              </span>
            </div>
          </div>

          {/* Right column: Quality + Checks/Terminal */}
          <div className="lg:col-span-5 space-y-4">
            {/* Quality chart */}
            <QualityChart iterations={ITERATION_DATA} currentIdx={currentIdx} />

            {/* Tabbed panel: Checks / Terminal / Comments */}
            <div className="rounded-xl border border-white/[0.08] bg-black/20 overflow-hidden">
              {/* Tab bar */}
              <div className="flex border-b border-white/[0.06]">
                {(
                  [
                    { key: 'checks' as ActiveTab, label: 'Checks', icon: <Eye className="h-3 w-3" />, badge: `${passCount}/${totalChecks}` },
                    { key: 'terminal' as ActiveTab, label: 'Terminal', icon: <Terminal className="h-3 w-3" />, badge: null },
                    { key: 'comments' as ActiveTab, label: 'Reviews', icon: <MessageSquare className="h-3 w-3" />, badge: `${commentCount}` },
                  ] as const
                ).map((tab) => (
                  <button
                    key={tab.key}
                    type="button"
                    onClick={() => setActiveTab(tab.key)}
                    className={`flex-1 flex items-center justify-center gap-1.5 px-2 py-2 text-[10px] font-medium transition-colors border-b-2 ${
                      activeTab === tab.key
                        ? 'text-white/80 border-white/30 bg-white/[0.03]'
                        : 'text-white/35 border-transparent hover:text-white/50'
                    }`}
                  >
                    {tab.icon}
                    <span className="hidden sm:inline">{tab.label}</span>
                    {tab.badge && (
                      <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-white/[0.06] text-white/40">
                        {tab.badge}
                      </span>
                    )}
                  </button>
                ))}
              </div>

              {/* Tab content */}
              <div className="p-3">
                <AnimatePresence mode="wait">
                  {activeTab === 'checks' && (
                    <motion.div
                      key={`checks-${animateKey}`}
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -4 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    >
                      <ReviewPanel checks={iteration.checks} animateIn={true} />
                    </motion.div>
                  )}
                  {activeTab === 'terminal' && (
                    <motion.div
                      key={`terminal-${animateKey}`}
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -4 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    >
                      <MiniTerminal
                        lines={iteration.terminalLines}
                        animateIn={true}
                      />
                    </motion.div>
                  )}
                  {activeTab === 'comments' && (
                    <motion.div
                      key={`comments-${animateKey}`}
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -4 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    >
                      <div className="space-y-2">
                        {iteration.comments.map((comment, ci) => {
                          const cStyle = getCommentColor(comment.type);
                          return (
                            <motion.div
                              key={`review-comment-${ci}`}
                              initial={{ opacity: 0, x: -6 }}
                              animate={{ opacity: 1, x: 0 }}
                              transition={{ type: 'spring', stiffness: 200, damping: 25, delay: ci * 0.08 }}
                              className={`px-3 py-2 rounded-lg border ${cStyle.bg} ${cStyle.border}`}
                            >
                              <div className="flex items-start gap-2">
                                <div className="flex-shrink-0 mt-0.5">{cStyle.icon}</div>
                                <div className="flex-1">
                                  <div className="flex items-center gap-2 mb-0.5">
                                    <span className="text-[10px] font-bold text-white/50">
                                      {comment.author}
                                    </span>
                                    <span className="text-[10px] font-mono text-white/25">
                                      line {comment.line + 1}
                                    </span>
                                  </div>
                                  <span className={`text-[11px] ${cStyle.text}`}>
                                    {comment.text}
                                  </span>
                                </div>
                              </div>
                            </motion.div>
                          );
                        })}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </div>

            {/* Mini terminal always visible at bottom right */}
            <AnimatePresence mode="wait">
              <motion.div
                key={`mini-term-${animateKey}`}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              >
                <MiniTerminal
                  lines={iteration.terminalLines}
                  animateIn={true}
                />
              </motion.div>
            </AnimatePresence>
          </div>
        </div>

        {/* Bottom: Convergence timeline */}
        <div className="pt-3 border-t border-white/[0.06]">
          <div className="flex items-center gap-3">
            <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider flex-shrink-0">
              Convergence
            </span>
            <div className="flex-1 flex items-center gap-0.5">
              {ITERATION_DATA.map((iter, i) => {
                const isActive = i <= currentIdx;
                const isCurrent = i === currentIdx;
                return (
                  <div key={iter.id} className="flex items-center flex-1">
                    <motion.div
                      className="h-2 flex-1 rounded-full transition-colors duration-500"
                      style={{
                        backgroundColor: isActive ? iter.color : 'rgba(255,255,255,0.04)',
                      }}
                      animate={{
                        opacity: isActive ? (isCurrent ? 1 : 0.6) : 0.2,
                      }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    />
                    {i < ITERATION_DATA.length - 1 && (
                      <ChevronRight
                        className="h-3 w-3 flex-shrink-0 transition-colors duration-300"
                        style={{
                          color: isActive ? iter.color : 'rgba(255,255,255,0.1)',
                          opacity: isActive ? 0.6 : 0.2,
                        }}
                      />
                    )}
                  </div>
                );
              })}
            </div>
            <motion.span
              key={iteration.quality}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="text-xs font-bold flex-shrink-0"
              style={{ color: iteration.color }}
            >
              {iteration.quality}%
            </motion.span>
          </div>
        </div>
      </div>
    </div>
  );
}
