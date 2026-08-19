'use client';

import {
  Terminal,
  FileText,
  Play,
  Type,
  Code2,
  Globe,
  FileOutput,
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

export function FmdLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Turn Markdown into polished HTML and PDF with one binary using Franken Markdown.
      </GoalBanner>

      {/* Section 1: What Is FMD */}
      <Section title="What Is Franken Markdown?" icon={<FileText className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>fmd (Franken Markdown)</Highlight> is a pure-Rust, zero-dependency
          rendering engine that converts Markdown into polished HTML and PDF. It needs no
          headless browser, LaTeX toolchain, or Node runtime; a single binary renders
          both formats from the same AST.
        </Paragraph>
        <Paragraph>
          The HTML output is fully self-contained: inlined CSS, embedded font subsets,
          data-URI images, and built-in dark mode. The PDF output is tagged and compact,
          with real typography. Renders are deterministic: the same input produces the
          same bytes, and <Highlight>SOURCE_DATE_EPOCH</Highlight> is honored for
          reproducible builds.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Self-Contained HTML"
              description="Inlined CSS, embedded fonts, data-URI images, dark mode"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<Type className="h-5 w-5" />}
              title="Real Typography PDF"
              description="Knuth-Plass line breaking for book-quality text layout"
              gradient="from-rose-500/20 to-pink-500/20"
            />
            <FeatureCard
              icon={<Code2 className="h-5 w-5" />}
              title="Syntax + Mermaid"
              description="~16-language syntax highlighting plus Mermaid diagrams"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<FileOutput className="h-5 w-5" />}
              title="WASM Parity"
              description="Browser/WASM package renders identically to the CLI"
              gradient="from-amber-500/20 to-yellow-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'fmd README.md --out README.html', description: 'Render Markdown to self-contained HTML' },
            { command: 'fmd README.md --to pdf', description: 'Render the same file to a tagged, compact PDF' },
            { command: 'fmd render SPEC.md --to both --json', description: 'Render to HTML and PDF with machine-readable status' },
            { command: 'fmd doctor --json', description: 'Verify installation health' },
            { command: 'fmd capabilities --json', description: 'List supported features machine-readably' },
            { command: 'fmd --robot-triage', description: 'Agent-friendly triage output' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 3: Common Use Cases */}
      <Section title="Common Use Cases" icon={<Play className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Use <Highlight>fmd</Highlight> for shareable README previews (a single HTML
          file you can email or upload anywhere), reproducible PDF documentation (same
          input, same bytes, so signed or archived docs stay verifiable), and CI
          rendering of docs with machine-readable status output.
        </Paragraph>
        <CodeBlock code={`# Shareable one-file preview of a README
fmd README.md --out README.html

# Reproducible PDF docs (deterministic with SOURCE_DATE_EPOCH)
SOURCE_DATE_EPOCH=0 fmd SPEC.md --to pdf

# CI: render each doc to both formats with machine-readable status
for f in docs/*.md; do fmd render "$f" --to both --json; done`} />

        <TipBox>
          Because renders are deterministic, you can diff output bytes in CI to catch
          unintended documentation changes: if the bytes changed, the content changed.
        </TipBox>
      </Section>
    </div>
  );
}
