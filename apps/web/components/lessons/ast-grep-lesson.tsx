"use client";

import { Code, FileText, RefreshCw, Search, Shield, Zap } from "lucide-react";
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

export function AstGrepLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Master structural code search with ast-grep — find patterns by AST shape, not string
        matching, for refactors, policy checks, and code analysis.
      </GoalBanner>

      <Section title="Why Structural Search?" icon={<Search className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Traditional <Highlight>regex-based grep</Highlight> searches treat code as flat text. That
          means matches inside comments, strings, and unrelated contexts all show up as false
          positives. Renaming a function with sed can silently break imports, type annotations, and
          documentation in one pass.
        </Paragraph>
        <Paragraph>
          <Highlight>ast-grep</Highlight> takes a different approach: it parses your code into an
          Abstract Syntax Tree (AST) and matches against the structural shape of the code. A pattern
          like <Highlight>useState($INIT)</Highlight> only matches actual function calls — never a
          comment that mentions useState or a string containing the word.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<RefreshCw className="h-5 w-5" />}
              title="Refactoring"
              description="Rename APIs and change import forms with structural precision"
              gradient="from-primary/20 to-violet-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Policy Enforcement"
              description="Enforce coding patterns consistently across repositories"
              gradient="from-amber-500/20 to-orange-500/20"
            />
            <FeatureCard
              icon={<Search className="h-5 w-5" />}
              title="Bug Detection"
              description="DCG and UBS use it internally for command and bug analysis"
              gradient="from-red-500/20 to-rose-500/20"
            />
            <FeatureCard
              icon={<Code className="h-5 w-5" />}
              title="Language-Aware"
              description="Understands 20+ languages including TypeScript, Rust, Python, and Go"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      <Section title="Pattern Basics" icon={<Code className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          ast-grep patterns use <Highlight>$NAME</Highlight> to capture a single AST node and{" "}
          <Highlight>$$$ARGS</Highlight> to capture zero or more nodes (variadic). The rest of the
          pattern is matched literally against the code structure.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Find all function declarations
ast-grep run -l TypeScript -p 'function $NAME($$$ARGS) { $$$BODY }'

# Find useState calls
ast-grep run -l TypeScript -p 'useState($INIT)'

# Find console.log statements
ast-grep run -l JavaScript -p 'console.log($$$ARGS)'

# Find async functions
ast-grep run -l TypeScript -p 'async function $NAME($$$ARGS) { $$$BODY }'`}
            language="bash"
          />
        </div>

        <TipBox variant="info">
          <Highlight>$NAME</Highlight> matches a single AST node (one expression, one identifier).{" "}
          <Highlight>$$$ARGS</Highlight> matches zero or more nodes — think of it like a variadic or
          rest parameter.
        </TipBox>
      </Section>

      <Divider />

      <Section title="Search & Replace" icon={<RefreshCw className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          ast-grep can do structural rewrites using the <Highlight>-r</Highlight> flag. Captured
          metavariables from the pattern are available in the replacement, so transformations
          preserve the original structure.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Replace var with const (only where safe)
ast-grep run -l JavaScript -p 'var $NAME = $VALUE' -r 'const $NAME = $VALUE'

# Rename an API function across the codebase
ast-grep run -l TypeScript -p 'oldApiName($$$ARGS)' -r 'newApiName($$$ARGS)'

# Convert require to import
ast-grep run -l JavaScript -p 'const $NAME = require("$MOD")' -r 'import $NAME from "$MOD"'

# Preview changes before applying
ast-grep run -l TypeScript -p 'oldFn($$$)' -r 'newFn($$$)' --interactive`}
            language="bash"
          />
        </div>

        <TipBox variant="warning">
          Always use <Highlight>--interactive</Highlight> or review the diff before applying
          rewrites to a whole codebase.
        </TipBox>
      </Section>

      <Divider />

      <Section title="Combining with ripgrep" icon={<Zap className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          The power combo: use <Highlight>rg</Highlight> for speed to narrow candidate files, then
          pipe into <Highlight>ast-grep</Highlight> for structural precision. ripgrep scans millions
          of lines per second; ast-grep ensures only real matches survive.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Step 1: ripgrep narrows candidate files (instant)
rg -l -t ts 'useState' src/

# Step 2: ast-grep matches structural pattern (precise)
rg -l -t ts 'useState' src/ | xargs ast-grep run -l TypeScript -p 'useState($INIT)' --json

# Real-world: find all React components using deprecated API
rg -l 'componentWillMount' src/ | xargs ast-grep run -l TypeScript -p 'componentWillMount() { $$$BODY }'

# Fleet-wide: combine with ru for multi-repo search
ru list --paths | xargs -I{} ast-grep run -l Rust -p 'unwrap()' {}`}
            language="bash"
          />
        </div>
      </Section>

      <Divider />

      <Section title="How DCG & UBS Use It" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          <Highlight>DCG</Highlight> uses ast-grep&apos;s Rust crates internally to parse commands
          and match destructive patterns at the AST level. <Highlight>UBS</Highlight> uses AST
          helpers for cross-language bug detection, including resource lifecycle analysis and type
          narrowing checks.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# DCG internally matches patterns like:
# "rm -rf /" → filesystem.recursive_delete
# "git push --force" → git.force_push
# "DROP TABLE" → sql.destructive_ddl

# Test what DCG would catch:
dcg test "rm -rf /tmp/build" --explain
# → ALLOWED: scoped to /tmp/build (not root)

dcg test "rm -rf /" --explain
# → BLOCKED: filesystem.recursive_delete (root path)

# UBS uses AST analysis for deeper checks:
ubs src/api.ts
# → Detects unclosed database connections via AST lifecycle analysis`}
            language="bash"
          />
        </div>

        <TipBox variant="info">
          ast-grep&apos;s structural matching is why DCG has zero false positives on command
          detection — it understands the actual shape of commands, not just string patterns.
        </TipBox>
      </Section>

      <Divider />

      <Section title="Rule Files" icon={<FileText className="h-5 w-5" />} delay={0.35}>
        <Paragraph>
          For reusable checks, define rules in YAML files and run them with{" "}
          <Highlight>ast-grep scan</Highlight>. A <Highlight>sgconfig.yml</Highlight> at your
          project root tells ast-grep where to find rule definitions.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# sgconfig.yml — project-level ast-grep rules
ruleDirs:
  - ./rules

# rules/no-console-log.yml
id: no-console-log
message: Remove console.log before committing
severity: warning
language: TypeScript
rule:
  pattern: console.log($$$ARGS)

# Run all project rules
ast-grep scan

# Output as JSON for CI integration
ast-grep scan --json`}
            language="yaml"
            filename="sgconfig.yml"
          />
        </div>
      </Section>
    </div>
  );
}
