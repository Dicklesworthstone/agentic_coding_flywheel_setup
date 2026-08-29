'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Globe,
  Terminal,
  Zap,
  FileText,
  Code,
  Settings,
  Play,
  Shield,
  ArrowRight,
  RotateCcw,
  Trash2,
  FileCode2,
  ChevronLeft,
  ChevronRight,
  BookOpen,
  MessageSquare,
  Newspaper,
  GraduationCap,
  Star,
  Gauge,
  BarChart3,
  Sparkles,
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

export function MdwbLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Convert web pages into clean Markdown that AI agents can read and reason about.
      </GoalBanner>

      {/* Section 1: What Is MDWB */}
      <Section title="What Is MDWB?" icon={<Globe className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>MDWB (Markdown Web Browser)</Highlight> fetches web pages and
          converts them into clean Markdown, stripping out ads, navigation, and
          scripts. The result is perfect for feeding into LLMs as context.
        </Paragraph>
        <Paragraph>
          When AI agents need information from the web, raw HTML is noisy and
          token-expensive. MDWB extracts just the content, preserving headings,
          code blocks, lists, and links in a format LLMs handle efficiently.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Any Web Page"
              description="Works with most websites"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Clean Output"
              description="No ads, scripts, or clutter"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Code className="h-5 w-5" />}
              title="Code Blocks"
              description="Preserves code formatting"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Fast"
              description="Built in Rust for speed"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveWebToMarkdown />
      </div>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Convert any URL to Markdown with a single command.
        </Paragraph>

        <CodeBlock
          code={`# Convert a web page to Markdown
mdwb "https://docs.example.com/api/reference"

# Save to a file
mdwb "https://docs.example.com/guide" > guide.md

# Pipe directly to an AI agent
mdwb "https://docs.example.com/api" | claude "summarize this API"`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Pipe MDWB output directly into AI agents for instant web research.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'mdwb "<url>"', description: 'Convert a URL to Markdown' },
            { command: 'mdwb -o output.md "<url>"', description: 'Save output to a file' },
            { command: 'mdwb --links "<url>"', description: 'Include link URLs in output' },
            { command: 'mdwb --help', description: 'Show all available options' },
          ]}
        />

        <TipBox variant="info">
          MDWB handles JavaScript-rendered pages, documentation sites, and
          blog posts. It works best with content-focused pages.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Use Cases */}
      <Section title="Common Use Cases" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          MDWB shines when you need web content in LLM-friendly format.
        </Paragraph>

        <CodeBlock
          code={`# Research a library's docs before using it
mdwb "https://docs.rs/tokio/latest" > tokio-docs.md

# Get error context from StackOverflow
mdwb "https://stackoverflow.com/questions/12345" > context.md

# Archive a blog post for reference
mdwb "https://blog.example.com/architecture-decisions" > arch.md

# Feed multiple pages to an agent
for url in $(cat urls.txt); do
  mdwb "$url"
done | claude "analyze these documents"`}
          filename="Use Cases"
        />
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          MDWB connects web knowledge to the agent workflow.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">MDWB + TRU</span>
            <p className="text-white/80 text-sm mt-1">Fetch docs, then compress for maximum context</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">MDWB + FSFS</span>
            <p className="text-white/80 text-sm mt-1">Index downloaded pages for local semantic search</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">MDWB + CSCTF</span>
            <p className="text-white/80 text-sm mt-1">Archive both web pages and AI conversations</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">MDWB + Brenner</span>
            <p className="text-white/80 text-sm mt-1">Feed research papers into Brenner corpus</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Web-to-Markdown Conversion Studio
// ---------------------------------------------------------------------------

interface HtmlElement {
  tag: string;
  content: string;
  isNoise: boolean;
  markdownOutput: string;
}

interface PageType {
  id: string;
  label: string;
  icon: typeof Globe;
  url: string;
  color: string;
  elements: HtmlElement[];
  htmlBytes: number;
  mdBytes: number;
  qualityScore: number;
}

const PAGE_TYPES: PageType[] = [
  {
    id: 'blog',
    label: 'Blog Post',
    icon: BookOpen,
    url: 'blog.example.com/rust-performance',
    color: 'violet',
    elements: [
      { tag: '<nav>', content: 'Home | About | Contact', isNoise: true, markdownOutput: '' },
      { tag: '<script>', content: 'analytics.track("page_view")', isNoise: true, markdownOutput: '' },
      { tag: '<div class="ad">', content: 'SPONSORED: Buy Now!', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'Why Rust Is Fast', isNoise: false, markdownOutput: '# Why Rust Is Fast' },
      { tag: '<p class="meta">', content: 'By Jane - 5 min read', isNoise: true, markdownOutput: '' },
      { tag: '<p>', content: 'Rust achieves C-level performance through zero-cost abstractions.', isNoise: false, markdownOutput: 'Rust achieves C-level performance through zero-cost abstractions.' },
      { tag: '<h2>', content: 'Key Features', isNoise: false, markdownOutput: '## Key Features' },
      { tag: '<ul>', content: 'No GC | Move semantics | Compile-time checks', isNoise: false, markdownOutput: '- No GC\n- Move semantics\n- Compile-time checks' },
      { tag: '<footer>', content: 'Copyright 2025 TechBlog', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 2840,
    mdBytes: 312,
    qualityScore: 94,
  },
  {
    id: 'api-docs',
    label: 'API Docs',
    icon: Code,
    url: 'docs.example.com/api/auth',
    color: 'blue',
    elements: [
      { tag: '<link>', content: 'stylesheet: docs-theme.css', isNoise: true, markdownOutput: '' },
      { tag: '<nav class="sidebar">', content: 'API Reference | Guide | Auth', isNoise: true, markdownOutput: '' },
      { tag: '<div class="banner">', content: 'New v3 API available!', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'Authentication API', isNoise: false, markdownOutput: '# Authentication API' },
      { tag: '<p>', content: 'Use Bearer tokens for all authenticated endpoints.', isNoise: false, markdownOutput: 'Use Bearer tokens for all authenticated endpoints.' },
      { tag: '<pre><code>', content: 'curl -H "Authorization: Bearer TOKEN" /api/user', isNoise: false, markdownOutput: '```\ncurl -H "Authorization: Bearer TOKEN" /api/user\n```' },
      { tag: '<h2>', content: 'Rate Limits', isNoise: false, markdownOutput: '## Rate Limits' },
      { tag: '<table>', content: 'Free: 100/hr | Pro: 10K/hr | Enterprise: Unlimited', isNoise: false, markdownOutput: '| Plan | Limit |\n|---|---|\n| Free | 100/hr |\n| Pro | 10K/hr |' },
      { tag: '<script>', content: 'initCodeHighlighting()', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 3120,
    mdBytes: 389,
    qualityScore: 97,
  },
  {
    id: 'github',
    label: 'GitHub README',
    icon: FileCode2,
    url: 'github.com/example/fast-cli',
    color: 'emerald',
    elements: [
      { tag: '<div class="js-repo-nav">', content: 'Code | Issues | Pull Requests', isNoise: true, markdownOutput: '' },
      { tag: '<div class="signup-prompt">', content: 'Sign up for GitHub', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'fast-cli', isNoise: false, markdownOutput: '# fast-cli' },
      { tag: '<p>', content: 'A blazing-fast command-line toolkit built in Rust.', isNoise: false, markdownOutput: 'A blazing-fast command-line toolkit built in Rust.' },
      { tag: '<h2>', content: 'Installation', isNoise: false, markdownOutput: '## Installation' },
      { tag: '<pre><code>', content: 'cargo install fast-cli', isNoise: false, markdownOutput: '```sh\ncargo install fast-cli\n```' },
      { tag: '<h2>', content: 'Usage', isNoise: false, markdownOutput: '## Usage' },
      { tag: '<pre><code>', content: 'fast-cli run --config my.toml', isNoise: false, markdownOutput: '```sh\nfast-cli run --config my.toml\n```' },
      { tag: '<div class="footer-links">', content: 'Terms | Privacy | Security', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 4560,
    mdBytes: 284,
    qualityScore: 92,
  },
  {
    id: 'stackoverflow',
    label: 'Stack Overflow',
    icon: MessageSquare,
    url: 'stackoverflow.com/questions/71234',
    color: 'amber',
    elements: [
      { tag: '<div class="top-bar">', content: 'Products | OverflowAI | Labs', isNoise: true, markdownOutput: '' },
      { tag: '<div class="sidebar">', content: 'Related Questions | Hot Network', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'How to handle async errors in Rust?', isNoise: false, markdownOutput: '# How to handle async errors in Rust?' },
      { tag: '<div class="vote-count">', content: '47 votes', isNoise: true, markdownOutput: '' },
      { tag: '<p>', content: 'Use the ? operator with Result types for clean async error propagation.', isNoise: false, markdownOutput: 'Use the ? operator with Result types for clean async error propagation.' },
      { tag: '<pre><code>', content: 'async fn fetch() -> Result<Data, Error> {\n  let resp = client.get(url).await?;\n  Ok(resp.json().await?)\n}', isNoise: false, markdownOutput: '```rust\nasync fn fetch() -> Result<Data, Error> {\n  let resp = client.get(url).await?;\n  Ok(resp.json().await?)\n}\n```' },
      { tag: '<div class="comments">', content: '12 comments collapsed', isNoise: true, markdownOutput: '' },
      { tag: '<div class="ads">', content: 'Sponsored: Cloud hosting...', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 5890,
    mdBytes: 342,
    qualityScore: 88,
  },
  {
    id: 'wikipedia',
    label: 'Wikipedia',
    icon: GraduationCap,
    url: 'en.wikipedia.org/wiki/Rust_(language)',
    color: 'cyan',
    elements: [
      { tag: '<div id="mw-navigation">', content: 'Main page | Contents | Talk', isNoise: true, markdownOutput: '' },
      { tag: '<div class="infobox">', content: 'Paradigm: multi-paradigm | Designed by: Graydon Hoare', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'Rust (programming language)', isNoise: false, markdownOutput: '# Rust (programming language)' },
      { tag: '<p>', content: 'Rust is a general-purpose programming language emphasizing performance, type safety, and concurrency.', isNoise: false, markdownOutput: 'Rust is a general-purpose programming language emphasizing performance, type safety, and concurrency.' },
      { tag: '<h2>', content: 'History', isNoise: false, markdownOutput: '## History' },
      { tag: '<p>', content: 'Rust grew out of a personal project by Mozilla employee Graydon Hoare.', isNoise: false, markdownOutput: 'Rust grew out of a personal project by Mozilla employee Graydon Hoare.' },
      { tag: '<div class="reflist">', content: '[1] [2] [3] ... 248 references', isNoise: true, markdownOutput: '' },
      { tag: '<div id="catlinks">', content: 'Categories: Programming languages', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 89400,
    mdBytes: 4120,
    qualityScore: 91,
  },
  {
    id: 'news',
    label: 'News Article',
    icon: Newspaper,
    url: 'news.example.com/tech/ai-coding',
    color: 'rose',
    elements: [
      { tag: '<div class="masthead">', content: 'TechNews | Subscribe | Sign In', isNoise: true, markdownOutput: '' },
      { tag: '<div class="cookie-wall">', content: 'Accept cookies to continue', isNoise: true, markdownOutput: '' },
      { tag: '<div class="paywall">', content: 'Subscribe for $9.99/mo', isNoise: true, markdownOutput: '' },
      { tag: '<h1>', content: 'AI-Powered Coding Tools Reshape Development', isNoise: false, markdownOutput: '# AI-Powered Coding Tools Reshape Development' },
      { tag: '<p class="byline">', content: 'By Sarah Chen | March 2026', isNoise: true, markdownOutput: '' },
      { tag: '<p>', content: 'A new generation of AI coding assistants is transforming how software teams build and ship products.', isNoise: false, markdownOutput: 'A new generation of AI coding assistants is transforming how software teams build and ship products.' },
      { tag: '<blockquote>', content: '"We ship 3x faster with AI pair programming" - CTO at Acme Corp', isNoise: false, markdownOutput: '> "We ship 3x faster with AI pair programming" - CTO at Acme Corp' },
      { tag: '<div class="newsletter">', content: 'Sign up for our newsletter', isNoise: true, markdownOutput: '' },
      { tag: '<div class="related">', content: 'More stories you might like...', isNoise: true, markdownOutput: '' },
    ],
    htmlBytes: 6720,
    mdBytes: 398,
    qualityScore: 85,
  },
];

const COMMANDS = [
  { cmd: 'mdwb "<url>"', desc: 'Convert URL to Markdown' },
  { cmd: 'mdwb -o file.md "<url>"', desc: 'Save to file' },
  { cmd: 'mdwb --links "<url>"', desc: 'Preserve link URLs' },
  { cmd: 'mdwb "<url>" | claude', desc: 'Pipe to AI agent' },
];

type ConversionStage = 'idle' | 'fetching' | 'scanning' | 'stripping' | 'converting' | 'done';

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

function InteractiveWebToMarkdown() {
  const [pageIndex, setPageIndex] = useState(0);
  const [stage, setStage] = useState<ConversionStage>('idle');
  const [highlightedElement, setHighlightedElement] = useState(-1);
  const [convertedTokens, setConvertedTokens] = useState<string[]>([]);
  const [flyingTokenIndex, setFlyingTokenIndex] = useState(-1);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.15 });

  const page = PAGE_TYPES[pageIndex];

  const clearTimers = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    timersRef.current = [];
  }, []);

  const handleSelectPage = useCallback((idx: number) => {
    clearTimers();
    setPageIndex(idx);
    setStage('idle');
    setHighlightedElement(-1);
    setConvertedTokens([]);
    setFlyingTokenIndex(-1);
  }, [clearTimers]);

  const handleStepForward = useCallback(() => {
    const nextIdx = (pageIndex + 1) % PAGE_TYPES.length;
    handleSelectPage(nextIdx);
  }, [pageIndex, handleSelectPage]);

  const handleStepBack = useCallback(() => {
    const prevIdx = (pageIndex - 1 + PAGE_TYPES.length) % PAGE_TYPES.length;
    handleSelectPage(prevIdx);
  }, [pageIndex, handleSelectPage]);

  const handleConvert = useCallback(() => {
    if (stage !== 'idle' && stage !== 'done') return;
    clearTimers();
    setConvertedTokens([]);
    setHighlightedElement(-1);
    setFlyingTokenIndex(-1);

    // Stage 1: Fetching
    setStage('fetching');

    // Stage 2: Scanning through elements
    const t1 = setTimeout(() => {
      setStage('scanning');
      // Highlight each element sequentially
      page.elements.forEach((_, i) => {
        const tH = setTimeout(() => {
          setHighlightedElement(i);
        }, i * 200);
        timersRef.current.push(tH);
      });
    }, 700);
    timersRef.current.push(t1);

    const scanDuration = page.elements.length * 200 + 200;

    // Stage 3: Stripping noise
    const t2 = setTimeout(() => {
      setStage('stripping');
      setHighlightedElement(-1);
    }, 700 + scanDuration);
    timersRef.current.push(t2);

    // Stage 4: Converting - fly tokens one by one
    const t3 = setTimeout(() => {
      setStage('converting');
      const contentElements = page.elements.filter(el => !el.isNoise);
      contentElements.forEach((el, i) => {
        const tF = setTimeout(() => {
          setFlyingTokenIndex(i);
          setConvertedTokens(prev => [...prev, el.markdownOutput]);
        }, i * 350);
        timersRef.current.push(tF);
      });

      const convertDuration = contentElements.length * 350 + 300;
      const tDone = setTimeout(() => {
        setStage('done');
        setFlyingTokenIndex(-1);
      }, convertDuration);
      timersRef.current.push(tDone);
    }, 700 + scanDuration + 600);
    timersRef.current.push(t3);
  }, [stage, page, clearTimers]);

  const handleReset = useCallback(() => {
    clearTimers();
    setStage('idle');
    setHighlightedElement(-1);
    setConvertedTokens([]);
    setFlyingTokenIndex(-1);
  }, [clearTimers]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      timersRef.current.forEach(clearTimeout);
    };
  }, []);

  const noiseCount = page.elements.filter(el => el.isNoise).length;
  const contentCount = page.elements.filter(el => !el.isNoise).length;
  const reductionPct = Math.round((1 - page.mdBytes / page.htmlBytes) * 100);

  const colorMap: Record<string, { border: string; bg: string; text: string; glow: string }> = {
    violet: { border: 'border-violet-500/30', bg: 'bg-violet-500/10', text: 'text-violet-300', glow: 'bg-violet-500/[0.06]' },
    blue: { border: 'border-blue-500/30', bg: 'bg-blue-500/10', text: 'text-blue-300', glow: 'bg-blue-500/[0.06]' },
    emerald: { border: 'border-emerald-500/30', bg: 'bg-emerald-500/10', text: 'text-emerald-300', glow: 'bg-emerald-500/[0.06]' },
    amber: { border: 'border-amber-500/30', bg: 'bg-amber-500/10', text: 'text-amber-300', glow: 'bg-amber-500/[0.06]' },
    cyan: { border: 'border-cyan-500/30', bg: 'bg-cyan-500/10', text: 'text-cyan-300', glow: 'bg-cyan-500/[0.06]' },
    rose: { border: 'border-rose-500/30', bg: 'bg-rose-500/10', text: 'text-rose-300', glow: 'bg-rose-500/[0.06]' },
  };
  const colors = colorMap[page.color] ?? colorMap.violet;

  const isAnimating = stage !== 'idle' && stage !== 'done';

  return (
    <div ref={ref} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 right-1/4 w-72 h-72 bg-violet-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 left-1/4 w-56 h-56 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 w-48 h-48 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none -translate-x-1/2 -translate-y-1/2" />

      <div className="relative p-6 sm:p-8 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="flex items-center justify-center gap-2">
            <Sparkles className="h-4 w-4 text-violet-400" />
            <p className="text-sm font-semibold text-white/90">Web-to-Markdown Conversion Studio</p>
            <Sparkles className="h-4 w-4 text-violet-400" />
          </div>
          <p className="text-xs text-white/50">
            Watch HTML get fetched, noise stripped, and content converted to clean Markdown
          </p>
        </div>

        {/* Page type stepper */}
        <div className="flex items-center justify-center gap-2">
          <motion.button
            type="button"
            onClick={handleStepBack}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-1.5 text-white/40 hover:text-white/70 transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </motion.button>

          <div className="flex flex-wrap justify-center gap-1.5">
            {PAGE_TYPES.map((p, i) => {
              const Icon = p.icon;
              const isActive = pageIndex === i;
              const pColors = colorMap[p.color] ?? colorMap.violet;
              return (
                <motion.button
                  key={p.id}
                  type="button"
                  onClick={() => handleSelectPage(i)}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  transition={SPRING}
                  className={`rounded-xl border px-2.5 py-1.5 text-[11px] font-medium transition-colors flex items-center gap-1.5 ${
                    isActive
                      ? `${pColors.border} ${pColors.bg} ${pColors.text}`
                      : 'border-white/[0.06] bg-white/[0.02] text-white/40 hover:text-white/60'
                  }`}
                >
                  <Icon className="h-3 w-3" />
                  {p.label}
                </motion.button>
              );
            })}
          </div>

          <motion.button
            type="button"
            onClick={handleStepForward}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={SPRING}
            className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-1.5 text-white/40 hover:text-white/70 transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </motion.button>
        </div>

        {/* URL bar */}
        <motion.div
          layout
          className={`flex items-center gap-2 rounded-xl border px-3 py-2 ${colors.border} bg-black/30`}
        >
          <Globe className={`h-3.5 w-3.5 shrink-0 ${colors.text}`} />
          <span className="text-xs font-mono text-white/60 truncate">{page.url}</span>
          <span className={`ml-auto text-[10px] font-medium ${colors.text} shrink-0`}>
            {(page.htmlBytes / 1024).toFixed(1)} KB
          </span>
        </motion.div>

        {/* Split-screen conversion view */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3 min-h-[300px]">
          {/* LEFT PANEL: HTML Browser View */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden flex flex-col">
            {/* Browser chrome */}
            <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
              <div className="flex gap-1">
                <div className="w-2 h-2 rounded-full bg-red-400/50" />
                <div className="w-2 h-2 rounded-full bg-amber-400/50" />
                <div className="w-2 h-2 rounded-full bg-emerald-400/50" />
              </div>
              <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider ml-2">
                HTML Source
              </span>
              <span className="ml-auto text-[10px] font-mono text-white/30">
                {page.elements.length} elements
              </span>
            </div>

            {/* HTML element list */}
            <div className="flex-1 p-2 space-y-1 overflow-y-auto max-h-[260px]">
              {page.elements.map((el, i) => {
                const isHighlighted = highlightedElement === i;
                const isStripped = (stage === 'stripping' || stage === 'converting' || stage === 'done') && el.isNoise;
                const isConverting = stage === 'converting' || stage === 'done';
                const isContent = !el.isNoise;

                return (
                  <motion.div
                    key={`${page.id}-${i}`}
                    initial={{ opacity: 0, x: -10 }}
                    animate={{
                      opacity: isStripped ? 0.25 : 1,
                      x: 0,
                      scale: isHighlighted ? 1.02 : 1,
                    }}
                    transition={SPRING}
                    className={`rounded-lg border px-2.5 py-1.5 text-[11px] font-mono transition-colors ${
                      isHighlighted
                        ? el.isNoise
                          ? 'border-red-500/40 bg-red-500/10'
                          : 'border-emerald-500/40 bg-emerald-500/10'
                        : isStripped
                          ? 'border-red-500/10 bg-red-500/[0.03] line-through'
                          : isConverting && isContent
                            ? 'border-emerald-500/20 bg-emerald-500/[0.05]'
                            : 'border-white/[0.06] bg-white/[0.01]'
                    }`}
                  >
                    <div className="flex items-start gap-2">
                      <span className={`shrink-0 font-semibold ${
                        isHighlighted
                          ? el.isNoise ? 'text-red-400' : 'text-emerald-400'
                          : isStripped
                            ? 'text-red-400/40'
                            : 'text-white/30'
                      }`}>
                        {el.tag}
                      </span>
                      <span className={`truncate ${
                        isStripped ? 'text-white/20' : 'text-white/50'
                      }`}>
                        {el.content}
                      </span>
                      {isHighlighted && (
                        <motion.span
                          initial={{ opacity: 0, scale: 0.5 }}
                          animate={{ opacity: 1, scale: 1 }}
                          className={`ml-auto shrink-0 text-[10px] font-bold px-1.5 py-0.5 rounded-md ${
                            el.isNoise
                              ? 'bg-red-500/20 text-red-300'
                              : 'bg-emerald-500/20 text-emerald-300'
                          }`}
                        >
                          {el.isNoise ? 'NOISE' : 'KEEP'}
                        </motion.span>
                      )}
                      {isStripped && !isHighlighted && (
                        <Trash2 className="h-3 w-3 text-red-400/30 shrink-0 ml-auto" />
                      )}
                    </div>
                  </motion.div>
                );
              })}
            </div>
          </div>

          {/* RIGHT PANEL: Markdown Output */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden flex flex-col">
            {/* Markdown header */}
            <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06] bg-white/[0.02]">
              <FileText className="h-3 w-3 text-emerald-400/60" />
              <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">
                Markdown Output
              </span>
              <AnimatePresence>
                {convertedTokens.length > 0 && (
                  <motion.span
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0 }}
                    className="ml-auto text-[10px] font-mono text-emerald-400"
                  >
                    {convertedTokens.length} / {contentCount} blocks
                  </motion.span>
                )}
              </AnimatePresence>
            </div>

            {/* Markdown content */}
            <div className="flex-1 p-3 overflow-y-auto max-h-[260px]">
              <AnimatePresence mode="popLayout">
                {stage === 'idle' ? (
                  <motion.div
                    key="placeholder"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="h-full flex flex-col items-center justify-center gap-3"
                  >
                    <div className="flex items-center gap-1.5">
                      <Globe className="h-5 w-5 text-white/15" />
                      <ArrowRight className="h-3 w-3 text-white/10" />
                      <FileText className="h-5 w-5 text-white/15" />
                    </div>
                    <span className="text-xs text-white/25">
                      Click Convert to start the pipeline
                    </span>
                  </motion.div>
                ) : (
                  <div className="space-y-1.5">
                    {convertedTokens.map((token, i) => (
                      <motion.div
                        key={`token-${i}`}
                        initial={{ opacity: 0, x: 20, filter: 'blur(4px)' }}
                        animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
                        transition={{ ...SPRING, delay: 0.05 }}
                      >
                        <pre className="text-[11px] font-mono text-emerald-300/80 leading-relaxed whitespace-pre-wrap">
                          {token}
                        </pre>
                      </motion.div>
                    ))}
                    {stage === 'fetching' && (
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className="flex items-center gap-2 text-xs text-white/30"
                      >
                        <motion.div
                          animate={inView ? { rotate: 360 } : { rotate: 0 }}
                          transition={inView ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                        >
                          <Globe className="h-3.5 w-3.5" />
                        </motion.div>
                        Fetching page...
                      </motion.div>
                    )}
                    {stage === 'scanning' && (
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className="flex items-center gap-2 text-xs text-amber-300/50"
                      >
                        <motion.div
                          animate={inView ? { opacity: [0.3, 1, 0.3] } : { opacity: 1 }}
                          transition={inView ? { duration: 1.2, repeat: Infinity } : { duration: 0.2 }}
                        >
                          <BarChart3 className="h-3.5 w-3.5" />
                        </motion.div>
                        Scanning elements...
                      </motion.div>
                    )}
                    {stage === 'stripping' && (
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className="flex items-center gap-2 text-xs text-red-300/50"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                        Removing {noiseCount} noise elements...
                      </motion.div>
                    )}
                    {stage === 'converting' && convertedTokens.length < contentCount && (
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={inView ? { opacity: [0.4, 1, 0.4] } : { opacity: 1 }}
                        transition={inView ? { duration: 0.8, repeat: Infinity } : { duration: 0.2 }}
                        className="flex items-center gap-2 text-xs text-violet-300/50"
                      >
                        <FileCode2 className="h-3.5 w-3.5" />
                        Converting...
                      </motion.div>
                    )}
                  </div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Flying token animation overlay */}
        <AnimatePresence>
          {flyingTokenIndex >= 0 && stage === 'converting' && (
            <motion.div
              key={`fly-${flyingTokenIndex}`}
              initial={{ opacity: 0.8, x: '25%', y: '50%', scale: 0.7 }}
              animate={{ opacity: 0, x: '75%', scale: 0.3 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.4 }}
              className="absolute inset-0 pointer-events-none flex items-center justify-center"
            >
              <div className="rounded-lg bg-emerald-400/20 border border-emerald-400/30 px-3 py-1 text-[10px] font-mono text-emerald-300">
                md
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Stats row: token comparison + quality score */}
        <AnimatePresence>
          {(stage === 'done' || stage === 'converting') && (
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 12 }}
              transition={SPRING}
              className="grid grid-cols-1 sm:grid-cols-3 gap-3"
            >
              {/* Size comparison */}
              <div className="sm:col-span-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                    Size Comparison
                  </span>
                  <span className="text-[10px] font-mono text-emerald-400">
                    {reductionPct}% reduction
                  </span>
                </div>
                <div className="space-y-2">
                  <div className="flex items-center gap-3">
                    <span className="text-[10px] text-white/40 w-8 shrink-0 text-right">HTML</span>
                    <div className="flex-1 h-5 rounded-full bg-white/[0.04] overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: '100%' }}
                        transition={{ ...SPRING, delay: 0.1 }}
                        className="h-full rounded-full bg-gradient-to-r from-red-400/30 to-red-500/40 flex items-center justify-end pr-2"
                      >
                        <span className="text-[10px] font-mono text-red-200/70">{(page.htmlBytes / 1024).toFixed(1)} KB</span>
                      </motion.div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="text-[10px] text-white/40 w-8 shrink-0 text-right">MD</span>
                    <div className="flex-1 h-5 rounded-full bg-white/[0.04] overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${(page.mdBytes / page.htmlBytes) * 100}%` }}
                        transition={{ ...SPRING, delay: 0.25 }}
                        className="h-full rounded-full bg-gradient-to-r from-emerald-400/40 to-emerald-500/50 flex items-center justify-end pr-2"
                      >
                        <span className="text-[10px] font-mono text-emerald-200/80">{(page.mdBytes / 1024).toFixed(1)} KB</span>
                      </motion.div>
                    </div>
                  </div>
                </div>
                <div className="flex items-center justify-center gap-4 text-[10px] text-white/40 pt-1">
                  <span>Noise removed: <span className="text-red-300/70 font-medium">{noiseCount}</span></span>
                  <span className="text-white/10">|</span>
                  <span>Content kept: <span className="text-emerald-300/70 font-medium">{contentCount}</span></span>
                  <span className="text-white/10">|</span>
                  <span>Token savings: <span className="text-violet-300/70 font-medium">~{reductionPct}%</span></span>
                </div>
              </div>

              {/* Quality score meter */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 flex flex-col items-center justify-center gap-2">
                <Gauge className="h-4 w-4 text-white/30" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Quality
                </span>
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ ...SPRING, delay: 0.3 }}
                  className="relative flex items-center justify-center"
                >
                  <svg viewBox="0 0 80 80" className="h-16 w-16">
                    {/* Background circle */}
                    <circle
                      cx="40" cy="40" r="32"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="5"
                      className="text-white/[0.06]"
                    />
                    {/* Score arc */}
                    <motion.circle
                      cx="40" cy="40" r="32"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="5"
                      strokeLinecap="round"
                      strokeDasharray={`${2 * Math.PI * 32}`}
                      initial={{ strokeDashoffset: 2 * Math.PI * 32 }}
                      animate={{ strokeDashoffset: 2 * Math.PI * 32 * (1 - page.qualityScore / 100) }}
                      transition={{ duration: 1.2, delay: 0.4 }}
                      className="text-emerald-400"
                      style={{ transform: 'rotate(-90deg)', transformOrigin: '50% 50%' }}
                    />
                  </svg>
                  <span className="absolute text-lg font-bold text-emerald-400">{page.qualityScore}</span>
                </motion.div>
                <div className="flex items-center gap-1">
                  {Array.from({ length: 5 }).map((_, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0, scale: 0 }}
                      animate={{
                        opacity: i < Math.round(page.qualityScore / 20) ? 1 : 0.2,
                        scale: 1,
                      }}
                      transition={{ ...SPRING, delay: 0.5 + i * 0.08 }}
                    >
                      <Star className={`h-3 w-3 ${
                        i < Math.round(page.qualityScore / 20) ? 'text-amber-400 fill-amber-400' : 'text-white/20'
                      }`} />
                    </motion.div>
                  ))}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Command bar */}
        <AnimatePresence>
          {stage === 'done' && (
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
              transition={SPRING}
              className="rounded-2xl border border-white/[0.08] bg-black/30 p-3"
            >
              <div className="flex items-center gap-2 mb-2.5">
                <Terminal className="h-3.5 w-3.5 text-violet-400/60" />
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  MDWB Commands
                </span>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                {COMMANDS.map((c, i) => (
                  <motion.div
                    key={c.cmd}
                    initial={{ opacity: 0, x: -8 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ ...SPRING, delay: 0.1 + i * 0.06 }}
                    className="flex items-center gap-2 rounded-lg border border-white/[0.05] bg-white/[0.02] px-2.5 py-1.5"
                  >
                    <code className="text-[10px] font-mono text-violet-300/80 shrink-0">{c.cmd}</code>
                    <span className="text-[10px] text-white/30 ml-auto">{c.desc}</span>
                  </motion.div>
                ))}
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Pipeline stage indicator */}
        <div className="flex items-center justify-center gap-1.5 flex-wrap">
          {(['fetching', 'scanning', 'stripping', 'converting', 'done'] as ConversionStage[]).map((s, i) => {
            const stageOrder = ['fetching', 'scanning', 'stripping', 'converting', 'done'];
            const currentIdx = stageOrder.indexOf(stage);
            const isActive = stage === s;
            const isPast = currentIdx > i;
            const icons = [Globe, BarChart3, Trash2, FileCode2, FileText];
            const labels = ['Fetch', 'Scan', 'Strip', 'Convert', 'Done'];
            const Icon = icons[i];
            return (
              <div key={s} className="flex items-center gap-1.5">
                {i > 0 && <ArrowRight className="h-2.5 w-2.5 text-white/15" />}
                <motion.div
                  animate={{
                    scale: isActive ? 1.08 : 1,
                    opacity: isActive || isPast ? 1 : 0.25,
                  }}
                  transition={SPRING}
                  className={`flex items-center gap-1 rounded-lg border px-2 py-1 text-[10px] font-medium ${
                    isActive
                      ? 'border-white/20 bg-white/[0.06] text-white/80'
                      : isPast
                        ? 'border-emerald-500/20 bg-emerald-500/[0.04] text-emerald-400/60'
                        : 'border-white/[0.04] bg-white/[0.01] text-white/20'
                  }`}
                >
                  {isActive ? (
                    <motion.div
                      animate={{ rotate: s !== 'done' && inView ? 360 : 0 }}
                      transition={s !== 'done' && inView ? { duration: 1.5, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                    >
                      <Icon className="h-2.5 w-2.5" />
                    </motion.div>
                  ) : (
                    <Icon className="h-2.5 w-2.5" />
                  )}
                  {labels[i]}
                </motion.div>
              </div>
            );
          })}
        </div>

        {/* Controls */}
        <div className="flex justify-center gap-3">
          <motion.button
            type="button"
            onClick={handleConvert}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={SPRING}
            disabled={isAnimating}
            className={`flex items-center gap-2 rounded-2xl border px-5 py-2.5 text-sm font-medium transition-colors ${
              isAnimating
                ? 'border-white/[0.06] bg-white/[0.02] text-white/30 cursor-wait'
                : `${colors.border} ${colors.bg} ${colors.text} hover:brightness-125`
            }`}
          >
            {isAnimating ? (
              <>
                <motion.div
                  animate={inView ? { rotate: 360 } : { rotate: 0 }}
                  transition={inView ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                >
                  <Globe className="h-4 w-4" />
                </motion.div>
                Processing...
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                Convert
              </>
            )}
          </motion.button>

          <AnimatePresence>
            {stage === 'done' && (
              <motion.button
                type="button"
                onClick={handleReset}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={SPRING}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                className="flex items-center gap-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 py-2.5 text-sm font-medium text-white/50 hover:text-white/70 transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reset
              </motion.button>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
