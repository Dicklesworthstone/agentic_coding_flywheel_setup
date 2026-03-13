"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { motion, AnimatePresence, springs } from "@/components/motion";
import {
  Sparkles,
  Brain,
  Target,
  Maximize2,
  Layers,
  Anchor,
  Clock,
  CheckSquare,
  Lightbulb,
  Zap,
  Eye,
  FileText,
  Terminal,
  BarChart3,
  ChevronRight,
  Play,
  RotateCcw,
  ArrowRight,
  Code2,
  Shield,
  List,
  BookOpen,
  Gauge,
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

export function PromptEngineeringLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master the art of directing AI agents with precision and intention.
      </GoalBanner>

      {/* Introduction */}
      <Section
        title="Why Prompting Matters"
        icon={<Sparkles className="h-5 w-5" />}
        delay={0.1}
      >
        <Paragraph>
          The difference between a mediocre agent session and a brilliant one
          often comes down to <Highlight>how you direct the agent</Highlight>.
          This lesson dissects the patterns that make prompts effective, drawn
          from real-world workflows that consistently produce excellent results.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Target className="h-5 w-5" />}
              title="Intensity Calibration"
              description="Signal how much attention to allocate"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Maximize2 className="h-5 w-5" />}
              title="Scope Control"
              description="Expand or contract the search space"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Brain className="h-5 w-5" />}
              title="Metacognition"
              description="Force self-verification and reflection"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Anchor className="h-5 w-5" />}
              title="Context Anchoring"
              description="Ground behavior in stable references"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Pattern 1: Intensity Calibration */}
      <Section
        title="Pattern 1: Intensity Calibration"
        icon={<Zap className="h-5 w-5" />}
        delay={0.15}
      >
        <Paragraph>
          AI models allocate &quot;compute&quot; based on perceived task
          importance. <Highlight>Stacked modifiers</Highlight> signal that this
          task deserves maximum attention:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <IntensityExample
            phrase="super carefully"
            effect="Elevates attention above baseline"
          />
          <IntensityExample
            phrase="super careful, methodical, and critical"
            effect="Triple-stacking for maximum precision"
          />
          <IntensityExample
            phrase="systematically and meticulously and intelligently"
            effect="Emphasizes both process and quality"
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Low intensity (default behavior)
"Check the code for bugs"

# High intensity (elevated attention)
"Do a super careful, methodical, and critical check
with fresh eyes to find any obvious bugs, problems,
errors, issues, silly mistakes, etc. and then
systematically and meticulously and intelligently
correct them."`}
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            These aren&apos;t filler words. They&apos;re{" "}
            <strong>calibration signals</strong> that tell the model to allocate
            more reasoning depth to the task.
          </TipBox>
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            <strong>Claude Code feature:</strong> The{" "}
            <strong>/effort</strong> command (<code>/effort low/medium/high/max</code>) controls how much thinking
            Claude Code allocates to a task. Use <code>/effort max</code> for
            tasks requiring maximum reasoning depth. While
            it&apos;s a tool-level feature in Claude Code, using intensity words like
            &quot;think deeply&quot; or &quot;reason carefully&quot; can help other
            agents/models allocate more attention to complex tasks as well.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Pattern 2: Scope Control */}
      <Section
        title="Pattern 2: Scope Control"
        icon={<Maximize2 className="h-5 w-5" />}
        delay={0.2}
      >
        <Paragraph>
          Models tend to take shortcuts. Explicit scope directives push against
          premature narrowing:
        </Paragraph>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <ScopeCard
            direction="expand"
            phrases={[
              "take ALL of that",
              "Don't restrict yourself",
              "cast a wider net",
              "comprehensive and granular",
            ]}
          />
          <ScopeCard
            direction="deepen"
            phrases={[
              "go super deep",
              "deeply investigate and understand",
              "trace their functionality and execution flows",
              "first-principle analysis",
            ]}
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Avoiding narrow focus
"Don't restrict yourself to the latest commits,
cast a wider net and go super deep!"

# Comprehensive coverage
"Take ALL of that and elaborate on it more,
then create a comprehensive and granular set..."

# Depth with breadth
"Randomly explore the code files in this project,
choosing code files to deeply investigate and understand
and trace their functionality and execution flows
through the related code files which they import
or which they are imported by."`}
          />
        </div>
      </Section>

      <Divider />

      {/* Pattern 3: Self-Verification */}
      <Section
        title="Pattern 3: Forcing Self-Verification"
        icon={<CheckSquare className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          Questions trigger <Highlight>metacognition</Highlight>—forcing the
          model to evaluate its own output before finalizing:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <VerificationQuestion
            question="Are you sure it makes sense?"
            purpose="Basic sanity check"
          />
          <VerificationQuestion
            question="Is it optimal?"
            purpose="Pushes beyond 'good enough'"
          />
          <VerificationQuestion
            question="Could we change anything to make the system work better for users?"
            purpose="User-centric optimization"
          />
          <VerificationQuestion
            question="Check over each bead super carefully"
            purpose="Item-by-item review"
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# The Plan Review Pattern
"Check over each bead super carefully—
are you sure it makes sense?
Is it optimal?
Could we change anything to make the system work better?
If so, revise the beads.

It's a lot easier and faster to operate in 'plan space'
before we start implementing these things!"`}
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            <strong>Plan Space Principle:</strong> Revising plans is 10x cheaper
            than debugging implementations. Force verification at the planning
            stage.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Pattern 4: Fresh Eyes Technique */}
      <Section
        title="Pattern 4: The Fresh Eyes Technique"
        icon={<Eye className="h-5 w-5" />}
        delay={0.3}
      >
        <Paragraph>
          <Highlight>Psychological reset techniques</Highlight> help agents
          approach code without prior assumptions or confirmation bias:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <FreshEyesCard
            technique="Explicit Reset"
            example='with "fresh eyes"'
            mechanism="Signals to discard prior assumptions"
          />
          <FreshEyesCard
            technique="Random Exploration"
            example='"randomly explore the code files"'
            mechanism="Avoids tunnel vision on expected locations"
          />
          <FreshEyesCard
            technique="Peer Framing"
            example='"reviewing code written by your fellow agents"'
            mechanism="Creates psychological distance from own work"
          />
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# The Fresh Eyes Code Review
"I want you to carefully read over all of the new code
you just wrote and other existing code you just modified
with 'fresh eyes' looking super carefully for any obvious
bugs, errors, problems, issues, confusion, etc.
Carefully fix anything you uncover."

# Peer Review Framing
"Turn your attention to reviewing the code written by
your fellow agents and checking for any issues, bugs,
errors, problems, inefficiencies, security problems,
reliability issues, etc. and carefully diagnose their
underlying root causes using first-principle analysis."`}
          />
        </div>
      </Section>

      <Divider />

      {/* Pattern 5: Temporal Awareness */}
      <Section
        title="Pattern 5: Temporal Awareness"
        icon={<Clock className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          Great prompts consider <Highlight>future contexts</Highlight>—the
          agent that will continue this work, the human who will review it, the
          &quot;future self&quot; who needs to understand it:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Self-Documenting Output
"Create a comprehensive set of beads with detailed comments
so that the whole thing is totally self-contained and
self-documenting (including relevant background,
reasoning/justification, considerations, etc.—
anything we'd want our 'future self' to know about
the goals and intentions and thought process and how it
serves the over-arching goals of the project)."`}
          />
        </div>

        <div className="mt-6 space-y-3">
          <TemporalConcept
            concept="Future Self"
            description="Write as if explaining to someone with no context"
          />
          <TemporalConcept
            concept="Self-Contained"
            description="Output should work independently of current conversation"
          />
          <TemporalConcept
            concept="Over-Arching Goals"
            description="Connect current work to bigger picture"
          />
        </div>
      </Section>

      <Divider />

      {/* Pattern 6: Context Anchoring */}
      <Section
        title="Pattern 6: Context Anchoring"
        icon={<Anchor className="h-5 w-5" />}
        delay={0.4}
      >
        <Paragraph>
          <Highlight>Stable reference documents</Highlight> (like AGENTS.md)
          serve as behavioral anchors. Re-reading them is especially critical
          after context compaction.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# The Post-Compaction Refresh
"Reread AGENTS.md so it's still fresh in your mind.
Use /effort max."`}
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <strong>Why this matters after compaction:</strong>
            <br /><br />
            1. <strong>Context decay:</strong> Rules lose salience as more
            content is added
            <br />
            2. <strong>Summarization loss:</strong> Compaction may miss nuances
            <br />
            3. <strong>Drift prevention:</strong> Periodic grounding prevents
            behavioral divergence
            <br />
            4. <strong>Fresh frame:</strong> Re-reading establishes correct
            operating context
          </TipBox>
        </div>

        <div className="mt-6">
          <CodeBlock
            code={`# Grounding Throughout Work
"Be sure to comply with ALL rules in AGENTS.md and
ensure that any code you write or revise conforms to
the best practice guides referenced in the AGENTS.md file."

# Making Rules Explicit
"You may NOT delete any file or directory unless I
explicitly give the exact command in this session."`}
          />
        </div>
      </Section>

      <Divider />

      {/* Pattern 7: First Principles */}
      <Section
        title="Pattern 7: First Principles Analysis"
        icon={<Layers className="h-5 w-5" />}
        delay={0.45}
      >
        <Paragraph>
          Push for <Highlight>deep understanding</Highlight> over surface-level
          pattern matching:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Root Cause Emphasis
"Carefully diagnose their underlying root causes
using first-principle analysis and then fix or
revise them if necessary."

# Context Before Action
"Once you understand the purpose of the code in
the larger context of the workflows, I want you
to do a super careful, methodical check..."`}
          />
        </div>

        <div className="mt-6 space-y-3">
          <PrincipleCard
            principle="Understand Before Fixing"
            description="Trace execution flows and dependencies first"
          />
          <PrincipleCard
            principle="Root Cause Over Symptom"
            description="Diagnose underlying issues, not surface manifestations"
          />
          <PrincipleCard
            principle="Larger Context"
            description="Understand how code fits into overall workflows"
          />
        </div>
      </Section>

      <Divider />

      {/* Putting It Together */}
      <Section
        title="Putting It All Together"
        icon={<Lightbulb className="h-5 w-5" />}
        delay={0.5}
      >
        <Paragraph>
          Here&apos;s a real prompt that combines multiple patterns:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`"Reread AGENTS.md so it's still fresh in your mind.
Use /effort max.

I want you to sort of randomly explore the code files
in this project, choosing code files to deeply investigate
and understand and trace their functionality and execution
flows through the related code files which they import or
which they are imported by.

Once you understand the purpose of the code in the larger
context of the workflows, I want you to do a super careful,
methodical, and critical check with 'fresh eyes' to find
any obvious bugs, problems, errors, issues, silly mistakes,
etc. and then systematically and meticulously and
intelligently correct them.

Be sure to comply with ALL rules in AGENTS.md and ensure
that any code you write or revise conforms to the best
practice guides referenced in the AGENTS.md file."`}
            language="markdown"
          />
        </div>

        <div className="mt-6">
          <InteractivePromptLab />
        </div>
      </Section>

      <Divider />

      {/* Quick Reference */}
      <Section
        title="Quick Reference"
        icon={<FileText className="h-5 w-5" />}
        delay={0.55}
      >
        <div className="space-y-4">
          <QuickRefItem
            pattern="Intensity"
            when="Tasks requiring maximum precision"
            key_phrases="super carefully, methodical, use /effort max"
          />
          <QuickRefItem
            pattern="Scope Expansion"
            when="Avoiding narrow focus or shortcuts"
            key_phrases="take ALL, cast wider net, comprehensive"
          />
          <QuickRefItem
            pattern="Self-Verification"
            when="Before implementing or finalizing"
            key_phrases="are you sure?, is it optimal?, revise if needed"
          />
          <QuickRefItem
            pattern="Fresh Eyes"
            when="Code review, finding missed issues"
            key_phrases="fresh eyes, fellow agents, randomly explore"
          />
          <QuickRefItem
            pattern="Temporal"
            when="Creating persistent artifacts"
            key_phrases="future self, self-documenting, self-contained"
          />
          <QuickRefItem
            pattern="Anchoring"
            when="After compaction or drift risk"
            key_phrases="reread AGENTS.md, comply with ALL rules"
          />
          <QuickRefItem
            pattern="First Principles"
            when="Debugging or understanding complex code"
            key_phrases="root causes, first-principle, larger context"
          />
        </div>
      </Section>
    </div>
  );
}

// =============================================================================
// INTENSITY EXAMPLE
// =============================================================================
function IntensityExample({
  phrase,
  effect,
}: {
  phrase: string;
  effect: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-4 rounded-xl border border-primary/20 bg-primary/5 transition-all duration-300 hover:border-primary/40"
    >
      <code className="text-primary font-mono font-medium">&quot;{phrase}&quot;</code>
      <span className="text-white/60">→</span>
      <span className="text-white/70">{effect}</span>
    </motion.div>
  );
}

// =============================================================================
// SCOPE CARD
// =============================================================================
function ScopeCard({
  direction,
  phrases,
}: {
  direction: "expand" | "deepen";
  phrases: string[];
}) {
  const isExpand = direction === "expand";
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -4, scale: 1.02 }}
      className={`group rounded-2xl border p-5 backdrop-blur-xl transition-all duration-300 ${
        isExpand
          ? "border-emerald-500/20 bg-emerald-500/5 hover:border-emerald-500/40"
          : "border-blue-500/20 bg-blue-500/5 hover:border-blue-500/40"
      }`}
    >
      <h4 className={`font-bold mb-3 ${isExpand ? "text-emerald-400" : "text-blue-400"}`}>
        {isExpand ? "Breadth" : "Depth"}
      </h4>
      <ul className="space-y-2">
        {phrases.map((phrase) => (
          <li key={phrase} className="text-sm text-white/60 font-mono">
            &quot;{phrase}&quot;
          </li>
        ))}
      </ul>
    </motion.div>
  );
}

// =============================================================================
// VERIFICATION QUESTION
// =============================================================================
function VerificationQuestion({
  question,
  purpose,
}: {
  question: string;
  purpose: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group flex items-start gap-4 p-4 rounded-xl border border-amber-500/20 bg-amber-500/5 transition-all duration-300 hover:border-amber-500/40"
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-amber-500/20 text-amber-400">
        ?
      </div>
      <div>
        <p className="font-medium text-amber-300 italic">&quot;{question}&quot;</p>
        <p className="text-sm text-white/50 mt-1">{purpose}</p>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FRESH EYES CARD
// =============================================================================
function FreshEyesCard({
  technique,
  example,
  mechanism,
}: {
  technique: string;
  example: string;
  mechanism: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group rounded-2xl border border-violet-500/20 bg-violet-500/5 p-5 backdrop-blur-xl transition-all duration-300 hover:border-violet-500/40"
    >
      <div className="flex items-center gap-3 mb-3">
        <Eye className="h-5 w-5 text-violet-400" />
        <h4 className="font-bold text-violet-300">{technique}</h4>
      </div>
      <code className="text-sm text-white/70 font-mono">{example}</code>
      <p className="text-sm text-white/50 mt-2">{mechanism}</p>
    </motion.div>
  );
}

// =============================================================================
// TEMPORAL CONCEPT
// =============================================================================
function TemporalConcept({
  concept,
  description,
}: {
  concept: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-3 rounded-lg border border-white/[0.08] bg-white/[0.02] transition-all duration-300 hover:border-white/[0.15]"
    >
      <Clock className="h-4 w-4 text-primary shrink-0" />
      <span className="font-medium text-white">{concept}</span>
      <span className="text-white/50">--</span>
      <span className="text-sm text-white/50">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// PRINCIPLE CARD
// =============================================================================
function PrincipleCard({
  principle,
  description,
}: {
  principle: string;
  description: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4 }}
      className="group flex items-center gap-4 p-3 rounded-lg border border-blue-500/20 bg-blue-500/5 transition-all duration-300 hover:border-blue-500/40"
    >
      <Layers className="h-4 w-4 text-blue-400 shrink-0" />
      <span className="font-medium text-blue-300">{principle}</span>
      <span className="text-white/50">--</span>
      <span className="text-sm text-white/50">{description}</span>
    </motion.div>
  );
}

// =============================================================================
// INTERACTIVE PROMPT LAB -- TYPES & DATA
// =============================================================================

type TechniqueId =
  | "system"
  | "fewShot"
  | "chainOfThought"
  | "constraints"
  | "outputFormat"
  | "contextMgmt";

interface Technique {
  id: TechniqueId;
  label: string;
  shortLabel: string;
  icon: React.ReactNode;
  color: string;
  dotColor: string;
  bgColor: string;
  borderColor: string;
  hoverBorder: string;
  description: string;
  effectiveness: number;
  tokenCost: number;
  promptLayer: string;
  withoutText: string;
  withText: string;
  agentOutputBefore: string;
  agentOutputAfter: string;
}

const TECHNIQUES: Technique[] = [
  {
    id: "system",
    label: "System Prompts",
    shortLabel: "System",
    icon: <BookOpen className="h-4 w-4" />,
    color: "text-violet-400",
    dotColor: "bg-violet-400",
    bgColor: "bg-violet-500/10",
    borderColor: "border-violet-500/20",
    hoverBorder: "hover:border-violet-500/40",
    description:
      "Set the agent's role, persona, and operating constraints before it sees the user task.",
    effectiveness: 95,
    tokenCost: 180,
    promptLayer:
      'You are a senior TypeScript engineer. Follow clean-code principles. Never use `any` types. Always add JSDoc comments to exported functions.',
    withoutText: "Fix the login bug.",
    withText:
      '[SYSTEM] You are a senior TypeScript engineer...\n[USER] Fix the login bug.',
    agentOutputBefore:
      "function login(user, pass) {\n  // fixed the bug\n  return fetch('/api/login', {\n    method: 'POST',\n    body: JSON.stringify({user, pass})\n  })\n}",
    agentOutputAfter:
      '/** Authenticates user with credentials via API. */\nasync function login(\n  user: string,\n  pass: string\n): Promise<AuthResult> {\n  // Root cause: missing await + no error handling\n  const res = await fetch("/api/login", {\n    method: "POST",\n    headers: { "Content-Type": "application/json" },\n    body: JSON.stringify({ user, pass }),\n  });\n  if (!res.ok) throw new AuthError(res.status);\n  return res.json();\n}',
  },
  {
    id: "fewShot",
    label: "Few-Shot Examples",
    shortLabel: "Few-Shot",
    icon: <List className="h-4 w-4" />,
    color: "text-emerald-400",
    dotColor: "bg-emerald-400",
    bgColor: "bg-emerald-500/10",
    borderColor: "border-emerald-500/20",
    hoverBorder: "hover:border-emerald-500/40",
    description:
      "Provide 2-3 input/output examples so the agent learns the exact format and style you want.",
    effectiveness: 88,
    tokenCost: 350,
    promptLayer:
      'Example 1:\nInput: "usr not found"\nOutput: { code: "USR_404", message: "User not found", action: "Check user ID" }\n\nExample 2:\nInput: "db timeout"\nOutput: { code: "DB_TIMEOUT", message: "Database timeout", action: "Retry with backoff" }',
    withoutText: "Parse this error log and categorize the errors.",
    withText:
      'Here are examples of how to categorize errors:\n[examples...]\n\nNow parse this error log and categorize the errors.',
    agentOutputBefore:
      "Errors found:\n- Line 12: user not found\n- Line 45: database timeout\n- Line 78: permission denied",
    agentOutputAfter:
      '[\n  { code: "USR_404", message: "User not found",\n    action: "Check user ID", line: 12 },\n  { code: "DB_TIMEOUT", message: "Database timeout",\n    action: "Retry with backoff", line: 45 },\n  { code: "AUTH_403", message: "Permission denied",\n    action: "Verify API key scope", line: 78 }\n]',
  },
  {
    id: "chainOfThought",
    label: "Chain-of-Thought",
    shortLabel: "CoT",
    icon: <Brain className="h-4 w-4" />,
    color: "text-amber-400",
    dotColor: "bg-amber-400",
    bgColor: "bg-amber-500/10",
    borderColor: "border-amber-500/20",
    hoverBorder: "hover:border-amber-500/40",
    description:
      "Ask the agent to reason step-by-step before producing a final answer, dramatically reducing errors.",
    effectiveness: 92,
    tokenCost: 120,
    promptLayer:
      'Think step-by-step:\n1. First, identify what the function is supposed to do\n2. Trace the execution path for both success and failure cases\n3. Identify where the actual behavior diverges from expected\n4. Only then propose a fix with your reasoning',
    withoutText: "Why is this function returning null?",
    withText:
      "Think step-by-step: first identify intent, then trace execution, then find divergence. Why is this function returning null?",
    agentOutputBefore:
      "The function returns null because the variable\nis undefined. Try adding a null check.",
    agentOutputAfter:
      "Step 1 - Intent: getData() should fetch user\n  profile and return a UserProfile object.\nStep 2 - Trace: On line 14, `result` is assigned\n  from cache. If cache miss, falls through to\n  line 22 without assignment.\nStep 3 - Divergence: Missing else-branch for\n  cache miss. `result` stays undefined -> null.\nFix: Add API fetch in the else-branch (line 22).",
  },
  {
    id: "constraints",
    label: "Constraints & Guardrails",
    shortLabel: "Guards",
    icon: <Shield className="h-4 w-4" />,
    color: "text-rose-400",
    dotColor: "bg-rose-400",
    bgColor: "bg-rose-500/10",
    borderColor: "border-rose-500/20",
    hoverBorder: "hover:border-rose-500/40",
    description:
      "Set explicit boundaries on what the agent must NOT do, preventing costly mistakes before they happen.",
    effectiveness: 90,
    tokenCost: 90,
    promptLayer:
      'CONSTRAINTS:\n- Do NOT delete any existing tests\n- Do NOT modify the public API surface\n- Do NOT add new dependencies without asking\n- Maximum 50 lines changed per file\n- All changes must be backwards-compatible',
    withoutText: "Refactor the auth module.",
    withText:
      "Refactor the auth module.\nCONSTRAINTS: No API changes, no deleted tests, no new deps, max 50 lines/file.",
    agentOutputBefore:
      "Refactored auth module:\n- Replaced bcrypt with argon2 (new dep)\n- Changed AuthResult interface (breaking)\n- Removed 3 legacy test files\n- Rewrote 400 lines across 6 files",
    agentOutputAfter:
      "Refactored auth module (within constraints):\n- Extracted helpers (no API change)\n- All 47 existing tests pass\n- Zero new dependencies\n- 12, 8, 31 lines changed (3 files)\n- Fully backwards-compatible",
  },
  {
    id: "outputFormat",
    label: "Output Formatting",
    shortLabel: "Format",
    icon: <Code2 className="h-4 w-4" />,
    color: "text-cyan-400",
    dotColor: "bg-cyan-400",
    bgColor: "bg-cyan-500/10",
    borderColor: "border-cyan-500/20",
    hoverBorder: "hover:border-cyan-500/40",
    description:
      "Specify the exact structure, format, and sections you expect in the response for machine-parseable output.",
    effectiveness: 85,
    tokenCost: 100,
    promptLayer:
      'Respond in this exact format:\n## Summary\n[1-2 sentences]\n## Root Cause\n[technical explanation]\n## Fix\n```typescript\n[code]\n```\n## Verification\n[how to confirm the fix works]',
    withoutText: "Investigate and fix the race condition in the queue worker.",
    withText:
      "Investigate and fix the race condition.\nRespond with: ## Summary, ## Root Cause, ## Fix (code), ## Verification.",
    agentOutputBefore:
      "I looked at the queue worker and found a race\ncondition. Here's the fix:\n[300 lines of mixed explanation and code]",
    agentOutputAfter:
      "## Summary\nQueue worker processes duplicate jobs when\ntwo workers poll simultaneously.\n## Root Cause\nMissing atomic lock acquisition in dequeue().\n## Fix\n```typescript\nawait redis.set(lockKey, workerId, \"NX\", 5000);\n```\n## Verification\nRun: bun test queue.race.test.ts",
  },
  {
    id: "contextMgmt",
    label: "Context Management",
    shortLabel: "Context",
    icon: <Anchor className="h-4 w-4" />,
    color: "text-indigo-400",
    dotColor: "bg-indigo-400",
    bgColor: "bg-indigo-500/10",
    borderColor: "border-indigo-500/20",
    hoverBorder: "hover:border-indigo-500/40",
    description:
      "Strategically load, refresh, and prioritize context to keep the agent grounded across long sessions.",
    effectiveness: 93,
    tokenCost: 60,
    promptLayer:
      'Before you begin:\n1. Reread AGENTS.md so rules are fresh\n2. Review the last 3 commits for recent changes\n3. Check the test file for expected behavior\n\nPrioritize: AGENTS.md rules > test expectations > existing patterns',
    withoutText:
      "Continue working on the feature from earlier.",
    withText:
      "Reread AGENTS.md, review last 3 commits, check tests. Then continue working on the feature. Prioritize: rules > tests > patterns.",
    agentOutputBefore:
      "Sure, continuing from where we left off...\n[makes assumptions about prior context]\n[violates a rule from AGENTS.md]\n[breaks an existing test]",
    agentOutputAfter:
      "Refreshed context:\n- AGENTS.md: 12 rules loaded (key: no `any`)\n- Last 3 commits: added UserProfile type\n- Tests expect: validate() returns Result<T>\n\nContinuing with full alignment to rules\nand existing test expectations...",
  },
];

const MAX_CONTEXT_TOKENS = 1200;

// =============================================================================
// TERMINAL LINE TYPES
// =============================================================================

interface TerminalLine {
  type: "prompt" | "response" | "system" | "divider";
  text: string;
}

// =============================================================================
// INTERACTIVE PROMPT LAB -- MAIN COMPONENT
// =============================================================================
function InteractivePromptLab() {
  const [activeTechnique, setActiveTechnique] = useState<TechniqueId>("system");
  const [enabledTechniques, setEnabledTechniques] = useState<Set<TechniqueId>>(
    () => new Set<TechniqueId>(["system"])
  );
  const [activeTab, setActiveTab] = useState<
    "builder" | "compare" | "anatomy" | "terminal"
  >("builder");
  const [builderStep, setBuilderStep] = useState(0);
  const [isAnimatingTerminal, setIsAnimatingTerminal] = useState(false);
  const [terminalLines, setTerminalLines] = useState<TerminalLine[]>([]);
  const terminalRef = useRef<HTMLDivElement>(null);
  const terminalIntervalRef = useRef<number | null>(null);
  const pendingTimersRef = useRef<number[]>([]);

  const technique = TECHNIQUES.find((t) => t.id === activeTechnique)!;

  const toggleTechnique = useCallback((id: TechniqueId) => {
    setEnabledTechniques((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
    setActiveTechnique(id);
  }, []);

  const enabledList = TECHNIQUES.filter((t) => enabledTechniques.has(t.id));
  const totalTokens = enabledList.reduce((sum, t) => sum + t.tokenCost, 0);
  const avgEffectiveness =
    enabledList.length > 0
      ? Math.round(
          enabledList.reduce((sum, t) => sum + t.effectiveness, 0) /
            enabledList.length
        )
      : 0;

  // Builder step cycling
  const advanceBuilder = useCallback(() => {
    setBuilderStep((s) => (s + 1) % (enabledList.length + 1));
  }, [enabledList.length]);

  const resetBuilder = useCallback(() => {
    setBuilderStep(0);
  }, []);

  const clearPendingTerminalWork = useCallback(() => {
    if (terminalIntervalRef.current !== null) {
      clearInterval(terminalIntervalRef.current);
      terminalIntervalRef.current = null;
    }

    for (const timer of pendingTimersRef.current) {
      clearTimeout(timer);
    }
    pendingTimersRef.current.length = 0;
  }, []);

  const queuePendingTimer = useCallback((callback: () => void, delay = 0) => {
    const timer = window.setTimeout(() => {
      pendingTimersRef.current = pendingTimersRef.current.filter(
        (pendingTimer) => pendingTimer !== timer,
      );
      callback();
    }, delay);

    pendingTimersRef.current.push(timer);
    return timer;
  }, []);

  // Terminal simulation
  const runTerminal = useCallback(() => {
    if (isAnimatingTerminal) return;

    clearPendingTerminalWork();
    setIsAnimatingTerminal(true);
    setTerminalLines([]);

    const lines: TerminalLine[] = [
      { type: "system", text: "# Prompt Engineering Lab - Simulation" },
      { type: "divider", text: "---" },
    ];

    for (const t of enabledList) {
      lines.push({
        type: "system",
        text: `[Applying: ${t.label}]`,
      });
      lines.push({
        type: "prompt",
        text: t.promptLayer.split("\n")[0] + "...",
      });
    }

    lines.push({ type: "divider", text: "---" });
    lines.push({
      type: "system",
      text: `[Sending prompt with ${enabledList.length} techniques]`,
    });
    lines.push({
      type: "prompt",
      text: `$ agent --techniques=${enabledList.map((t) => t.shortLabel).join(",")}`,
    });
    lines.push({ type: "divider", text: "---" });
    lines.push({
      type: "response",
      text: `Agent responding with ${avgEffectiveness}% effectiveness...`,
    });
    lines.push({
      type: "response",
      text: technique.agentOutputAfter.split("\n").slice(0, 3).join("\n"),
    });
    lines.push({ type: "divider", text: "---" });
    lines.push({
      type: "system",
      text: `[Tokens used: ${totalTokens}/${MAX_CONTEXT_TOKENS} | Quality: ${avgEffectiveness}%]`,
    });

    let i = 0;
    const interval = window.setInterval(() => {
      if (i < lines.length) {
        const line = lines[i];
        setTerminalLines((prev) => [...prev, line]);
        i++;
      } else {
        clearInterval(interval);
        terminalIntervalRef.current = null;
        // Wrap in setTimeout to avoid setState during render
        queuePendingTimer(() => {
          setIsAnimatingTerminal(false);
        });
      }
    }, 300);
    terminalIntervalRef.current = interval;
  }, [
    isAnimatingTerminal,
      enabledList,
      avgEffectiveness,
      technique.agentOutputAfter,
      totalTokens,
      clearPendingTerminalWork,
      queuePendingTimer,
  ]);

  // Auto-scroll terminal
  useEffect(() => {
    if (terminalRef.current) {
      const el = terminalRef.current;
      queuePendingTimer(() => {
        el.scrollTop = el.scrollHeight;
      });
    }
  }, [terminalLines, queuePendingTimer]);

  // Cleanup interval and timers on unmount
  useEffect(() => clearPendingTerminalWork, [clearPendingTerminalWork]);

  const tabs = [
    { id: "builder" as const, label: "Prompt Builder", icon: <Layers className="h-3.5 w-3.5" /> },
    { id: "compare" as const, label: "Before / After", icon: <ArrowRight className="h-3.5 w-3.5" /> },
    { id: "anatomy" as const, label: "Anatomy & Tokens", icon: <BarChart3 className="h-3.5 w-3.5" /> },
    { id: "terminal" as const, label: "Live Terminal", icon: <Terminal className="h-3.5 w-3.5" /> },
  ];

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl overflow-hidden">
      {/* Header */}
      <div className="p-6 pb-0">
        <div className="flex items-center gap-3 mb-1">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-primary/30 to-violet-500/30 border border-primary/20">
            <Sparkles className="h-4 w-4 text-primary" />
          </div>
          <h4 className="font-bold text-white text-lg">
            Interactive Prompt Engineering Lab
          </h4>
        </div>
        <p className="text-sm text-white/50 mt-1 mb-4">
          Toggle techniques, watch prompts build layer by layer, and compare
          agent output quality.
        </p>

        {/* Technique toggles */}
        <div className="flex flex-wrap gap-2 mb-4">
          {TECHNIQUES.map((t) => {
            const isEnabled = enabledTechniques.has(t.id);
            const isActive = activeTechnique === t.id;
            return (
              <motion.button
                key={t.id}
                onClick={() => toggleTechnique(t.id)}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.97 }}
                transition={springs.snappy}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium border transition-all duration-200 ${
                  isActive && isEnabled
                    ? `${t.borderColor} ${t.bgColor} ${t.color} ring-1 ring-white/10`
                    : isEnabled
                      ? `${t.borderColor} ${t.bgColor} ${t.color}`
                      : "border-white/[0.06] bg-white/[0.01] text-white/30 hover:text-white/50"
                }`}
              >
                {t.icon}
                <span>{t.shortLabel}</span>
                {isEnabled && (
                  <motion.span
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    className={`ml-0.5 h-1.5 w-1.5 rounded-full ${t.dotColor}`}
                  />
                )}
              </motion.button>
            );
          })}
        </div>

        {/* Tab bar */}
        <div className="flex gap-1 border-b border-white/[0.06]">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors duration-200 border-b-2 -mb-px ${
                activeTab === tab.id
                  ? "border-primary text-primary"
                  : "border-transparent text-white/40 hover:text-white/60"
              }`}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      <div className="p-6">
        <AnimatePresence mode="wait">
          {activeTab === "builder" && (
            <motion.div
              key="builder"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={springs.smooth}
            >
              <PromptBuilderPanel
                techniques={enabledList}
                step={builderStep}
                onAdvance={advanceBuilder}
                onReset={resetBuilder}
              />
            </motion.div>
          )}
          {activeTab === "compare" && (
            <motion.div
              key="compare"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={springs.smooth}
            >
              <BeforeAfterPanel technique={technique} />
            </motion.div>
          )}
          {activeTab === "anatomy" && (
            <motion.div
              key="anatomy"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={springs.smooth}
            >
              <AnatomyPanel
                techniques={TECHNIQUES}
                enabledTechniques={enabledTechniques}
                totalTokens={totalTokens}
                avgEffectiveness={avgEffectiveness}
              />
            </motion.div>
          )}
          {activeTab === "terminal" && (
            <motion.div
              key="terminal"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={springs.smooth}
            >
              <TerminalPanel
                lines={terminalLines}
                isAnimating={isAnimatingTerminal}
                onRun={runTerminal}
                terminalRef={terminalRef}
                enabledCount={enabledList.length}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Technique detail strip */}
      <div className="px-6 pb-6">
        <motion.div
          layout
          className={`rounded-xl border p-4 ${technique.borderColor} ${technique.bgColor} backdrop-blur-xl`}
        >
          <div className="flex items-start gap-3">
            <div
              className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border ${technique.borderColor} ${technique.bgColor} ${technique.color}`}
            >
              {technique.icon}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 mb-1">
                <span className={`font-semibold text-sm ${technique.color}`}>
                  {technique.label}
                </span>
                <span className={`h-1.5 w-1.5 rounded-full ${technique.dotColor}`} />
              </div>
              <p className="text-xs text-white/50 leading-relaxed">
                {technique.description}
              </p>
            </div>
            <div className="flex flex-col items-end gap-1 shrink-0">
              <div className="flex items-center gap-1 text-xs text-white/40">
                <Gauge className="h-3 w-3" />
                <span>{technique.effectiveness}%</span>
              </div>
              <div className="flex items-center gap-1 text-xs text-white/30">
                <span>{technique.tokenCost} tokens</span>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </div>
  );
}

// =============================================================================
// PROMPT BUILDER PANEL -- animated layer-by-layer build
// =============================================================================
function PromptBuilderPanel({
  techniques,
  step,
  onAdvance,
  onReset,
}: {
  techniques: Technique[];
  step: number;
  onAdvance: () => void;
  onReset: () => void;
}) {
  const visibleLayers = techniques.slice(0, step);
  const hasMore = step < techniques.length;
  const isComplete = step >= techniques.length && techniques.length > 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-white/40 uppercase tracking-wider font-medium">
          Building prompt layer by layer ({step}/{techniques.length})
        </span>
        <div className="flex gap-2">
          {isComplete && (
            <motion.button
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              onClick={onReset}
              className="flex items-center gap-1 px-3 py-1.5 rounded-lg border border-white/[0.08] bg-white/[0.02] text-xs text-white/50 hover:text-white/70 transition-colors"
            >
              <RotateCcw className="h-3 w-3" />
              Reset
            </motion.button>
          )}
          {hasMore && (
            <motion.button
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.97 }}
              onClick={onAdvance}
              className="flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-primary/20 border border-primary/30 text-xs font-medium text-primary hover:bg-primary/30 transition-colors"
            >
              <Play className="h-3 w-3" />
              Add Next Layer
            </motion.button>
          )}
          {step === 0 && techniques.length > 0 && (
            <motion.button
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.97 }}
              onClick={onAdvance}
              className="flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-primary/20 border border-primary/30 text-xs font-medium text-primary hover:bg-primary/30 transition-colors"
            >
              <Play className="h-3 w-3" />
              Start Building
            </motion.button>
          )}
        </div>
      </div>

      {/* Prompt preview area */}
      <div className="rounded-xl border border-white/[0.08] bg-black/40 p-4 font-mono text-sm min-h-[200px]">
        {step === 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="flex items-center justify-center h-[160px]"
          >
            <p className="text-white/20 text-center text-xs">
              Click &quot;Start Building&quot; to watch prompt layers stack up.
              <br />
              Toggle techniques above to customize which layers appear.
            </p>
          </motion.div>
        )}

        <AnimatePresence mode="popLayout">
          {visibleLayers.map((t, i) => (
            <motion.div
              key={t.id}
              initial={{ opacity: 0, height: 0, y: 10 }}
              animate={{ opacity: 1, height: "auto", y: 0 }}
              exit={{ opacity: 0, height: 0 }}
              transition={{
                type: "spring",
                stiffness: 200,
                damping: 25,
                delay: 0.05,
              }}
              className="mb-3 last:mb-0"
            >
              <div
                className={`rounded-lg border p-3 ${t.borderColor} ${t.bgColor}`}
              >
                <div className="flex items-center gap-2 mb-1.5">
                  <span className={`${t.dotColor} h-2 w-2 rounded-full`} />
                  <span
                    className={`text-[10px] uppercase tracking-wider font-semibold ${t.color}`}
                  >
                    Layer {i + 1}: {t.label}
                  </span>
                </div>
                <pre className="text-xs text-white/60 whitespace-pre-wrap leading-relaxed">
                  {t.promptLayer}
                </pre>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>

        {isComplete && (
          <motion.div
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2, ...springs.smooth }}
            className="mt-3 pt-3 border-t border-white/[0.06]"
          >
            <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 p-3">
              <div className="flex items-center gap-2 mb-1">
                <span className="h-2 w-2 rounded-full bg-emerald-400" />
                <span className="text-[10px] uppercase tracking-wider font-semibold text-emerald-400">
                  User Task
                </span>
              </div>
              <pre className="text-xs text-white/60 whitespace-pre-wrap">
                Now execute the task with all layers applied...
              </pre>
            </div>
          </motion.div>
        )}
      </div>

      {/* Progress bar */}
      <div className="h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
        <motion.div
          className="h-full rounded-full bg-gradient-to-r from-primary/60 to-violet-500/60"
          initial={{ width: "0%" }}
          animate={{
            width:
              techniques.length > 0
                ? `${(step / techniques.length) * 100}%`
                : "0%",
          }}
          transition={springs.smooth}
        />
      </div>
    </div>
  );
}

// =============================================================================
// BEFORE / AFTER PANEL -- side-by-side comparison
// =============================================================================
function BeforeAfterPanel({ technique }: { technique: Technique }) {
  return (
    <div className="space-y-4">
      <p className="text-xs text-white/40 mb-3">
        Compare agent output quality{" "}
        <span className="text-rose-400">without</span> vs{" "}
        <span className="text-emerald-400">with</span> the{" "}
        <span className={technique.color}>{technique.label}</span> technique
        applied.
      </p>

      <div className="grid gap-4 md:grid-cols-2">
        {/* Without technique */}
        <div className="rounded-xl border border-rose-500/20 bg-rose-500/[0.03] p-4 backdrop-blur-xl">
          <div className="flex items-center gap-2 mb-3">
            <div className="h-2 w-2 rounded-full bg-rose-400" />
            <span className="text-[10px] font-semibold uppercase tracking-wider text-rose-400">
              Without {technique.shortLabel}
            </span>
          </div>
          <div className="mb-3 rounded-lg border border-white/[0.06] bg-black/30 p-3">
            <span className="text-[10px] text-white/30 uppercase tracking-wider">
              Prompt
            </span>
            <p className="font-mono text-xs text-white/50 mt-1">
              {technique.withoutText}
            </p>
          </div>
          <div className="rounded-lg border border-white/[0.06] bg-black/30 p-3">
            <span className="text-[10px] text-white/30 uppercase tracking-wider">
              Agent Output
            </span>
            <pre className="font-mono text-xs text-rose-300/60 mt-1 whitespace-pre-wrap leading-relaxed">
              {technique.agentOutputBefore}
            </pre>
          </div>
        </div>

        {/* With technique */}
        <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/[0.03] p-4 backdrop-blur-xl">
          <div className="flex items-center gap-2 mb-3">
            <div className="h-2 w-2 rounded-full bg-emerald-400" />
            <span className="text-[10px] font-semibold uppercase tracking-wider text-emerald-400">
              With {technique.shortLabel}
            </span>
          </div>
          <div className="mb-3 rounded-lg border border-white/[0.06] bg-black/30 p-3">
            <span className="text-[10px] text-white/30 uppercase tracking-wider">
              Prompt
            </span>
            <p className="font-mono text-xs text-white/50 mt-1">
              {technique.withText}
            </p>
          </div>
          <div className="rounded-lg border border-white/[0.06] bg-black/30 p-3">
            <span className="text-[10px] text-white/30 uppercase tracking-wider">
              Agent Output
            </span>
            <pre className="font-mono text-xs text-emerald-300/60 mt-1 whitespace-pre-wrap leading-relaxed">
              {technique.agentOutputAfter}
            </pre>
          </div>
        </div>
      </div>

      {/* Effectiveness score comparison */}
      <div className="flex items-center gap-4 pt-2 border-t border-white/[0.06]">
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1">
            <span className="text-[10px] text-rose-400 uppercase tracking-wider font-medium">
              Without
            </span>
            <span className="text-xs text-rose-400/60">~40%</span>
          </div>
          <div className="h-2 rounded-full bg-white/[0.04] overflow-hidden">
            <motion.div
              className="h-full rounded-full bg-rose-500/40"
              initial={{ width: "0%" }}
              animate={{ width: "40%" }}
              transition={{ delay: 0.3, duration: 0.8, ease: "easeOut" }}
            />
          </div>
        </div>
        <ChevronRight className="h-4 w-4 text-white/20 shrink-0" />
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1">
            <span className="text-[10px] text-emerald-400 uppercase tracking-wider font-medium">
              With {technique.shortLabel}
            </span>
            <span className="text-xs text-emerald-400/60">
              {technique.effectiveness}%
            </span>
          </div>
          <div className="h-2 rounded-full bg-white/[0.04] overflow-hidden">
            <motion.div
              className="h-full rounded-full bg-emerald-500/60"
              initial={{ width: "0%" }}
              animate={{ width: `${technique.effectiveness}%` }}
              transition={{ delay: 0.5, duration: 0.8, ease: "easeOut" }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// ANATOMY & TOKEN PANEL -- prompt sections + token budget visualization
// =============================================================================
function AnatomyPanel({
  techniques,
  enabledTechniques,
  totalTokens,
  avgEffectiveness,
}: {
  techniques: Technique[];
  enabledTechniques: Set<TechniqueId>;
  totalTokens: number;
  avgEffectiveness: number;
}) {
  const tokenPercent = Math.min((totalTokens / MAX_CONTEXT_TOKENS) * 100, 100);
  const isOverBudget = totalTokens > MAX_CONTEXT_TOKENS;

  return (
    <div className="space-y-5">
      {/* Token budget bar */}
      <div>
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs text-white/40 uppercase tracking-wider font-medium">
            Token Budget
          </span>
          <span
            className={`text-xs font-mono ${isOverBudget ? "text-rose-400" : "text-white/50"}`}
          >
            {totalTokens} / {MAX_CONTEXT_TOKENS} tokens
          </span>
        </div>
        <div className="h-4 rounded-full bg-white/[0.04] overflow-hidden relative">
          <motion.div
            className={`h-full rounded-full ${
              isOverBudget
                ? "bg-gradient-to-r from-rose-500/60 to-rose-400/60"
                : "bg-gradient-to-r from-primary/50 to-violet-500/50"
            }`}
            initial={{ width: "0%" }}
            animate={{ width: `${tokenPercent}%` }}
            transition={springs.smooth}
          />
          {/* Segment markers */}
          <div className="absolute inset-0 flex">
            {techniques.map((t) => {
              if (!enabledTechniques.has(t.id)) return null;
              const w = (t.tokenCost / MAX_CONTEXT_TOKENS) * 100;
              return (
                <motion.div
                  key={t.id}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className={`h-full ${t.bgColor} border-r border-black/20`}
                  style={{ width: `${w}%` }}
                  title={`${t.label}: ${t.tokenCost} tokens`}
                />
              );
            })}
          </div>
        </div>
        {/* Token legend */}
        <div className="flex flex-wrap gap-x-3 gap-y-1 mt-2">
          {techniques.map((t) => (
            <div
              key={t.id}
              className={`flex items-center gap-1 text-[10px] ${
                enabledTechniques.has(t.id) ? t.color : "text-white/20"
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${
                  enabledTechniques.has(t.id) ? t.dotColor : "bg-white/10"
                }`}
              />
              <span>
                {t.shortLabel} ({t.tokenCost})
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Prompt anatomy diagram */}
      <div className="rounded-xl border border-white/[0.08] bg-black/30 p-4">
        <h5 className="text-xs text-white/50 uppercase tracking-wider font-semibold mb-3">
          Prompt Anatomy
        </h5>
        <div className="space-y-1.5">
          {techniques.map((t, idx) => {
            const isEnabled = enabledTechniques.has(t.id);
            return (
              <motion.div
                key={t.id}
                initial={{ opacity: 0, x: -10 }}
                animate={{
                  opacity: isEnabled ? 1 : 0.3,
                  x: 0,
                }}
                transition={{ delay: idx * 0.05, ...springs.smooth }}
                className={`flex items-center gap-3 rounded-lg p-2.5 border transition-all duration-200 ${
                  isEnabled
                    ? `${t.borderColor} ${t.bgColor}`
                    : "border-white/[0.04] bg-white/[0.01]"
                }`}
              >
                <div className="flex items-center gap-2 w-28 shrink-0">
                  <span
                    className={`${isEnabled ? t.dotColor : "bg-white/10"} h-2 w-2 rounded-full`}
                  />
                  <span
                    className={`text-xs font-medium ${isEnabled ? t.color : "text-white/20"}`}
                  >
                    {t.shortLabel}
                  </span>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
                    <motion.div
                      className={`h-full rounded-full ${isEnabled ? t.dotColor : "bg-white/[0.06]"}`}
                      initial={{ width: "0%" }}
                      animate={{
                        width: isEnabled
                          ? `${(t.tokenCost / MAX_CONTEXT_TOKENS) * 100}%`
                          : "0%",
                      }}
                      transition={{ delay: idx * 0.08, ...springs.smooth }}
                    />
                  </div>
                </div>
                <span
                  className={`text-[10px] font-mono w-12 text-right ${isEnabled ? "text-white/40" : "text-white/15"}`}
                >
                  {t.tokenCost}t
                </span>
              </motion.div>
            );
          })}
        </div>
      </div>

      {/* Effectiveness scores */}
      <div className="grid grid-cols-2 gap-3">
        <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 text-center">
          <Gauge className="h-5 w-5 text-primary mx-auto mb-2" />
          <div className="text-2xl font-bold text-white">{avgEffectiveness}%</div>
          <div className="text-[10px] text-white/40 uppercase tracking-wider mt-1">
            Avg Effectiveness
          </div>
        </div>
        <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 text-center">
          <BarChart3 className="h-5 w-5 text-violet-400 mx-auto mb-2" />
          <div className="text-2xl font-bold text-white">
            {enabledTechniques.size}
          </div>
          <div className="text-[10px] text-white/40 uppercase tracking-wider mt-1">
            Active Techniques
          </div>
        </div>
      </div>

      {/* Effectiveness bars per technique */}
      <div className="space-y-2">
        <h5 className="text-xs text-white/40 uppercase tracking-wider font-medium">
          Technique Effectiveness
        </h5>
        {techniques.map((t, idx) => {
          const isEnabled = enabledTechniques.has(t.id);
          return (
            <div key={t.id} className="flex items-center gap-3">
              <span
                className={`text-xs w-16 shrink-0 ${isEnabled ? t.color : "text-white/20"}`}
              >
                {t.shortLabel}
              </span>
              <div className="flex-1 h-2 rounded-full bg-white/[0.04] overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${isEnabled ? t.dotColor : "bg-white/[0.06]"}`}
                  initial={{ width: "0%" }}
                  animate={{
                    width: isEnabled ? `${t.effectiveness}%` : "0%",
                  }}
                  transition={{
                    delay: idx * 0.06,
                    duration: 0.6,
                    ease: "easeOut",
                  }}
                />
              </div>
              <span
                className={`text-[10px] font-mono w-8 text-right ${isEnabled ? "text-white/50" : "text-white/15"}`}
              >
                {t.effectiveness}%
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// TERMINAL PANEL -- simulated terminal showing prompts and responses
// =============================================================================
function TerminalPanel({
  lines,
  isAnimating,
  onRun,
  terminalRef,
  enabledCount,
}: {
  lines: TerminalLine[];
  isAnimating: boolean;
  onRun: () => void;
  terminalRef: React.RefObject<HTMLDivElement | null>;
  enabledCount: number;
}) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs text-white/40">
          Simulated agent session with {enabledCount} technique
          {enabledCount !== 1 ? "s" : ""}
        </span>
        <motion.button
          whileHover={{ scale: 1.04 }}
          whileTap={{ scale: 0.97 }}
          onClick={onRun}
          disabled={isAnimating}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-lg text-xs font-medium transition-colors ${
            isAnimating
              ? "bg-white/[0.04] text-white/20 cursor-not-allowed"
              : "bg-emerald-500/20 border border-emerald-500/30 text-emerald-400 hover:bg-emerald-500/30"
          }`}
        >
          {isAnimating ? (
            <>
              <span className="h-3 w-3 rounded-full border-2 border-emerald-400/30 border-t-emerald-400 animate-spin" />
              Running...
            </>
          ) : (
            <>
              <Play className="h-3 w-3" />
              Run Simulation
            </>
          )}
        </motion.button>
      </div>

      {/* Terminal window */}
      <div className="rounded-xl border border-white/[0.08] bg-black/60 overflow-hidden">
        {/* Title bar */}
        <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.06] bg-white/[0.02]">
          <div className="flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-rose-500/60" />
            <span className="h-2.5 w-2.5 rounded-full bg-amber-500/60" />
            <span className="h-2.5 w-2.5 rounded-full bg-emerald-500/60" />
          </div>
          <span className="text-[10px] text-white/30 font-mono ml-2">
            prompt-lab ~ agent-session
          </span>
        </div>

        {/* Terminal body */}
        <div
          ref={terminalRef}
          className="p-4 font-mono text-xs min-h-[240px] max-h-[360px] overflow-y-auto scrollbar-thin scrollbar-thumb-white/10"
        >
          {lines.length === 0 && !isAnimating && (
            <div className="flex items-center justify-center h-[200px]">
              <p className="text-white/15 text-center">
                Click &quot;Run Simulation&quot; to see your prompt
                <br />
                techniques in action.
              </p>
            </div>
          )}

          <AnimatePresence mode="popLayout">
            {lines.map((line, i) => (
              <motion.div
                key={`${line.type}-${i}`}
                initial={{ opacity: 0, x: -6 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{
                  type: "spring",
                  stiffness: 300,
                  damping: 30,
                }}
                className="mb-1"
              >
                {line.type === "divider" ? (
                  <div className="border-t border-white/[0.06] my-2" />
                ) : line.type === "system" ? (
                  <span className="text-amber-400/60">{line.text}</span>
                ) : line.type === "prompt" ? (
                  <span className="text-emerald-400/70">{line.text}</span>
                ) : (
                  <span className="text-cyan-300/60 whitespace-pre-wrap">
                    {line.text}
                  </span>
                )}
              </motion.div>
            ))}
          </AnimatePresence>

          {isAnimating && (
            <motion.span
              initial={{ opacity: 0 }}
              animate={{ opacity: [0.2, 1, 0.2] }}
              transition={{ repeat: Infinity, duration: 1 }}
              className="inline-block w-2 h-3.5 bg-emerald-400/60 ml-0.5"
            />
          )}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// QUICK REF ITEM
// =============================================================================
function QuickRefItem({
  pattern,
  when,
  key_phrases,
}: {
  pattern: string;
  when: string;
  key_phrases: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      whileHover={{ x: 4, scale: 1.01 }}
      className="group grid grid-cols-3 gap-4 p-4 rounded-xl border border-white/[0.08] bg-white/[0.02] transition-all duration-300 hover:border-primary/30"
    >
      <div>
        <span className="text-xs text-white/60 uppercase">Pattern</span>
        <p className="font-bold text-primary">{pattern}</p>
      </div>
      <div>
        <span className="text-xs text-white/60 uppercase">When</span>
        <p className="text-sm text-white/70">{when}</p>
      </div>
      <div>
        <span className="text-xs text-white/60 uppercase">Key Phrases</span>
        <p className="text-xs text-white/50 font-mono">{key_phrases}</p>
      </div>
    </motion.div>
  );
}
