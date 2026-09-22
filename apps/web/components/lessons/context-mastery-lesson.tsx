"use client";

import { ArrowDown, Brain, FileCode, Gauge, Layers, Minimize2, Search } from "lucide-react";
import {
  CodeBlock,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function ContextMasteryLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Maximize what fits in your agent&apos;s context window using TRU, S2P, CASS, and CM — the
        difference between an agent that forgets and one that remembers everything.
      </GoalBanner>

      {/* Section 1: The Context Problem */}
      <Section title="The Context Problem" icon={<Layers className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Every AI agent has a <Highlight>finite context window</Highlight>. When it fills up, the
          agent compacts (forgets earlier messages) or degrades. Four tools help you fit more useful
          information into less space.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Minimize2 className="h-5 w-5" />}
              title="TRU"
              description="40-70% token reduction via compression"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<FileCode className="h-5 w-5" />}
              title="S2P"
              description="Bundle source files into a single prompt"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="CASS"
              description="Retrieve specific solutions, not whole files"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Brain className="h-5 w-5" />}
              title="CM"
              description="Distilled rules instead of raw session logs"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: TRU Compression */}
      <Section title="Encode Data with TRU" icon={<Minimize2 className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          <Highlight>TRU (toon_rust)</Highlight> converts JSON to TOON, a notation that carries the
          same data with far fewer quotes, braces and commas. It is for structured data (API
          responses, search results, config, exports), not for source code. Tables of records shrink
          by roughly half.
        </Paragraph>

        <CodeBlock
          code={`# Encode a JSON file before handing it to an agent
toon results.json
# → same records as TOON, no braces/quotes, one line per row

# Check the estimate first
toon --stats results.json
# → Token estimates: ~78 (JSON) → ~53 (TOON)

# Pipe JSON straight from another tool
gh issue list --json number,title,labels | toon --encode

# Decode back to JSON when a program needs it
toon results.toon`}
          filename="TRU Encoding"
        />

        <TipBox variant="tip">
          TRU pays off most on uniform arrays of objects (issue lists, rows, search hits). Nested
          objects with unique keys save less, and prose or source code is not TOON&apos;s job.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: S2P Bundling */}
      <Section title="Bundle with S2P" icon={<FileCode className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          <Highlight>S2P (Source to Prompt)</Highlight> combines multiple source files into a
          single, well-structured prompt with automatic token counting. Instead of agents reading
          files one by one, give them everything at once.
        </Paragraph>

        <CodeBlock
          code={`# Bundle all TypeScript files in a directory
s2p src/api/ --include "*.ts"

# Bundle with token count for each file
s2p src/ --include "*.ts" --show-tokens

# Exclude test files and node_modules
s2p src/ --include "*.ts" --exclude "*test*,*spec*"

# Output to clipboard for pasting
s2p src/components/ --include "*.tsx" --clipboard`}
          filename="S2P Bundling"
        />

        <TipBox variant="info">
          S2P shows token counts per file, so you can see which files are consuming the most
          context. Drop large auto-generated files that agents rarely need.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Targeted Retrieval with CASS */}
      <Section title="Retrieve with CASS" icon={<Search className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Instead of dumping entire files into context, use CASS to retrieve{" "}
          <Highlight>specific snippets</Highlight> from past sessions where a problem was already
          solved.
        </Paragraph>

        <CodeBlock
          code={`# Find how you solved a specific problem before
cass search "postgres connection pool exhaustion fix" --robot --limit 3

# Get targeted context with just the relevant snippet
cass view /path/to/session.jsonl -n 42 --json
# → Returns just the solution, not the whole 10,000-line session

# Expand context around a hit if you need more detail
cass expand /path -n 42 -C 3 --json

# Use minimal fields to save tokens in the response
cass search "auth middleware pattern" --robot --fields minimal`}
          filename="Targeted Retrieval"
        />

        <TipBox variant="tip">
          Use <code>--fields minimal</code> to get just the snippet and score, not the full
          metadata. This can cut the response size by 60%.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Distilled Knowledge with CM */}
      <Section title="Distill with CM" icon={<Brain className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          CM distills entire sessions into <Highlight>single-line rules</Highlight>. Instead of
          re-reading a 500-message session, your agent gets &ldquo;Always use bcrypt with cost
          factor 12&rdquo; — one line instead of 50,000 tokens.
        </Paragraph>

        <CodeBlock
          code={`# Get all relevant rules for a task (tiny token footprint)
cm context "implement rate limiting" --json
# → Returns 3-5 rules, ~200 tokens total

# Compare to reading the full session:
# Rule: "Use sliding window, not fixed window, for rate limiting"
# vs. re-reading a 2-hour debugging session (50,000+ tokens)

# The memory protocol in action:
# 1. Agent starts → cm context loads ~200 tokens of rules
# 2. Agent works → references rule IDs in decisions
# 3. Agent finishes → new rules extracted for future use`}
          filename="Knowledge Distillation"
        />
      </Section>

      <Divider />

      {/* Section 6: The Combined Workflow */}
      <Section title="The Combined Workflow" icon={<Gauge className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          Here&apos;s how to combine all four tools for maximum context efficiency.
        </Paragraph>

        <div className="space-y-3">
          <div className="flex items-start gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <ArrowDown className="h-4 w-4 text-amber-400 shrink-0 mt-0.5" />
            <span className="text-white/90 text-sm">
              <strong className="text-amber-400">Step 1: CM Context</strong> — Load distilled rules
              for the task (~200 tokens)
            </span>
          </div>
          <div className="flex items-start gap-3 p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <ArrowDown className="h-4 w-4 text-violet-400 shrink-0 mt-0.5" />
            <span className="text-white/90 text-sm">
              <strong className="text-violet-400">Step 2: CASS Search</strong> — Find specific past
              solutions if needed (~500 tokens)
            </span>
          </div>
          <div className="flex items-start gap-3 p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <ArrowDown className="h-4 w-4 text-blue-400 shrink-0 mt-0.5" />
            <span className="text-white/90 text-sm">
              <strong className="text-blue-400">Step 3: S2P Bundle</strong> — Collect relevant
              source files with token counts
            </span>
          </div>
          <div className="flex items-start gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <ArrowDown className="h-4 w-4 text-emerald-400 shrink-0 mt-0.5" />
            <span className="text-white/90 text-sm">
              <strong className="text-emerald-400">Step 4: TRU Compress</strong> — Shrink the bundle
              by 40-70% before sending
            </span>
          </div>
        </div>

        <div className="mt-6 p-4 rounded-lg bg-white/[0.03] border border-white/[0.08]">
          <p className="text-sm text-white/70">
            <strong className="text-white">Result:</strong> An agent that starts with distilled
            knowledge, targeted solutions, and compressed source — fitting 10x more useful
            information into the same context window.
          </p>
        </div>
      </Section>
    </div>
  );
}
