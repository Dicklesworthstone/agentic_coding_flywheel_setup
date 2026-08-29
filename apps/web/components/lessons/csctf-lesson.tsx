'use client';

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  FileText,
  Terminal,
  Zap,
  Download,
  Globe,
  Shield,
  Settings,
  Play,
  Link2,
  Search,
  FileCode,
  CheckCircle2,
  ArrowRight,
  RotateCcw,
  MessageSquare,
  Code2,
  Hash,
  Image as ImageIcon,
  Table,
  ExternalLink,
  User,
  Bot,
  Sparkles,
  Clock,
  FileDown,
  Layers,
  ChevronRight,
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

function InteractiveConversionPipeline() {
  return <InteractiveConversionPipelineImpl />;
}

export function CsctfLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Convert AI chat share links into clean Markdown and HTML files for archiving and reference.
      </GoalBanner>

      {/* Section 1: What Is CSCTF */}
      <Section title="What Is CSCTF?" icon={<FileText className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>CSCTF (Chat Shared Conversation to File)</Highlight> downloads
          conversations from ChatGPT, Claude, Gemini, and Grok share links, converting
          them into clean Markdown and HTML files you can keep forever.
        </Paragraph>
        <Paragraph>
          AI providers can remove shared conversations at any time. CSCTF preserves
          your best conversations locally with proper formatting, code blocks, and
          metadata intact.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Multi-Provider"
              description="ChatGPT, Claude, Gemini, Grok"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<FileText className="h-5 w-5" />}
              title="Dual Output"
              description="Markdown + HTML per conversation"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Offline Archive"
              description="Keep conversations forever"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Code Preserved"
              description="Syntax highlighting intact"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveConversionPipeline />
      </div>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Pass a share link and CSCTF handles the rest.
        </Paragraph>

        <CodeBlock
          code={`# Convert a ChatGPT share link
csctf "https://chatgpt.com/share/abc123"

# Convert a Claude share link
csctf "https://claude.ai/share/xyz789"

# Output goes to current directory:
#   conversation_title.md
#   conversation_title.html`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          CSCTF auto-detects the provider from the URL. No flags needed.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'csctf "<share-url>"', description: 'Convert a single conversation' },
            { command: 'csctf -o ~/archive "<url>"', description: 'Save to specific directory' },
            { command: 'csctf --md-only "<url>"', description: 'Output Markdown only' },
            { command: 'csctf --html-only "<url>"', description: 'Output HTML only' },
          ]}
        />

        <TipBox variant="info">
          The generated Markdown works great as input for other tools like S2P or
          as context for new AI conversations.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Batch Processing */}
      <Section title="Batch Processing" icon={<Zap className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Archive multiple conversations at once by passing a file of URLs.
        </Paragraph>

        <CodeBlock
          code={`# Create a file with one URL per line
cat > urls.txt << 'EOF'
https://chatgpt.com/share/abc123
https://claude.ai/share/xyz789
https://gemini.google.com/share/def456
EOF

# Process all URLs
csctf --batch urls.txt -o ~/ai-archive/`}
          filename="Batch Mode"
        />
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Settings className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          CSCTF fits naturally into the agent workflow.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">CSCTF + CASS</span>
            <p className="text-white/80 text-sm mt-1">Archive conversations, then search them with CASS</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">CSCTF + S2P</span>
            <p className="text-white/80 text-sm mt-1">Convert archived chats into LLM-ready prompts</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">CSCTF + CM</span>
            <p className="text-white/80 text-sm mt-1">Extract patterns from past conversations into memory</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">CSCTF + Beads</span>
            <p className="text-white/80 text-sm mt-1">Link archived conversations to task issues</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Conversion Pipeline Visualization (DRAMATICALLY UPGRADED)
// ---------------------------------------------------------------------------

interface SourceInfo {
  id: string;
  name: string;
  icon: string;
  color: string;
  textColor: string;
  borderColor: string;
  bgColor: string;
  glowColor: string;
  url: string;
  title: string;
  messages: ChatMessage[];
  detectedFormats: FormatBadge[];
  fileSize: string;
  tokens: number;
  outputSize: string;
  outputTokens: number;
}

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  hasCode?: boolean;
  hasImage?: boolean;
  hasLink?: boolean;
  hasTable?: boolean;
}

interface FormatBadge {
  type: 'code' | 'image' | 'link' | 'table';
  count: number;
}

type PipelineStage = 'idle' | 'fetch' | 'parse' | 'clean' | 'format' | 'output' | 'done';

const PIPELINE_STAGES: { key: PipelineStage; label: string; icon: typeof Link2 }[] = [
  { key: 'fetch', label: 'Fetch', icon: Download },
  { key: 'parse', label: 'Parse', icon: Search },
  { key: 'clean', label: 'Clean', icon: Sparkles },
  { key: 'format', label: 'Format', icon: Code2 },
  { key: 'output', label: 'Output', icon: FileDown },
];

const FORMAT_ICONS: Record<string, typeof Code2> = {
  code: Code2,
  image: ImageIcon,
  link: ExternalLink,
  table: Table,
};

const FORMAT_COLORS: Record<string, string> = {
  code: 'text-emerald-400 border-emerald-500/30 bg-emerald-500/10',
  image: 'text-pink-400 border-pink-500/30 bg-pink-500/10',
  link: 'text-blue-400 border-blue-500/30 bg-blue-500/10',
  table: 'text-amber-400 border-amber-500/30 bg-amber-500/10',
};

const SOURCES: SourceInfo[] = [
  {
    id: 'chatgpt',
    name: 'ChatGPT',
    icon: 'G',
    color: '#10a37f',
    textColor: 'text-emerald-400',
    borderColor: 'border-emerald-500/30',
    bgColor: 'bg-emerald-500/10',
    glowColor: 'bg-emerald-500/[0.06]',
    url: 'chatgpt.com/share/e8f2a1b3',
    title: 'Building a REST API with Express',
    messages: [
      { role: 'user', content: 'How do I set up Express with TypeScript?' },
      { role: 'assistant', content: 'Here is a complete setup for Express + TypeScript with proper error handling:', hasCode: true },
      { role: 'user', content: 'Can you add rate limiting middleware?' },
      { role: 'assistant', content: 'I\'ll add express-rate-limit with a sliding window configuration:', hasCode: true, hasLink: true },
    ],
    detectedFormats: [
      { type: 'code', count: 6 },
      { type: 'link', count: 3 },
      { type: 'table', count: 1 },
    ],
    fileSize: '24.3 KB',
    tokens: 4820,
    outputSize: '18.1 KB',
    outputTokens: 3640,
  },
  {
    id: 'claude',
    name: 'Claude',
    icon: 'C',
    color: '#d97706',
    textColor: 'text-amber-400',
    borderColor: 'border-amber-500/30',
    bgColor: 'bg-amber-500/10',
    glowColor: 'bg-amber-500/[0.06]',
    url: 'claude.ai/share/conv_9x7kp2m',
    title: 'Debug Memory Leak in Node Process',
    messages: [
      { role: 'user', content: 'My Node.js process keeps growing in memory. Here\'s my heap snapshot:' },
      { role: 'assistant', content: 'I can see the leak. The event listeners are never being removed. Let me trace the reference chain:', hasCode: true, hasImage: true },
      { role: 'user', content: 'That fixed it! Can you also optimize the buffer allocation?' },
      { role: 'assistant', content: 'Yes, switching to a pool allocator will reduce GC pressure significantly:', hasCode: true, hasTable: true },
    ],
    detectedFormats: [
      { type: 'code', count: 4 },
      { type: 'image', count: 2 },
      { type: 'link', count: 1 },
      { type: 'table', count: 2 },
    ],
    fileSize: '31.7 KB',
    tokens: 6340,
    outputSize: '22.4 KB',
    outputTokens: 4510,
  },
  {
    id: 'gemini',
    name: 'Gemini',
    icon: 'G',
    color: '#4285f4',
    textColor: 'text-blue-400',
    borderColor: 'border-blue-500/30',
    bgColor: 'bg-blue-500/10',
    glowColor: 'bg-blue-500/[0.06]',
    url: 'gemini.google.com/share/a3d7f1e2',
    title: 'ML Pipeline with TensorFlow',
    messages: [
      { role: 'user', content: 'Design a data pipeline for training image classifiers.' },
      { role: 'assistant', content: 'Here is an efficient tf.data pipeline with augmentation and prefetching:', hasCode: true, hasTable: true },
      { role: 'user', content: 'How should I handle class imbalance in the dataset?' },
      { role: 'assistant', content: 'Use a combination of weighted loss and oversampling. Here\'s the comparison:', hasCode: true, hasTable: true, hasImage: true },
    ],
    detectedFormats: [
      { type: 'code', count: 9 },
      { type: 'image', count: 3 },
      { type: 'table', count: 4 },
      { type: 'link', count: 2 },
    ],
    fileSize: '42.1 KB',
    tokens: 8420,
    outputSize: '34.6 KB',
    outputTokens: 6920,
  },
  {
    id: 'grok',
    name: 'Grok',
    icon: 'X',
    color: '#a855f7',
    textColor: 'text-purple-400',
    borderColor: 'border-purple-500/30',
    bgColor: 'bg-purple-500/10',
    glowColor: 'bg-purple-500/[0.06]',
    url: 'x.com/i/grok/share/r4v8n2q1',
    title: 'Regex Patterns for Log Parsing',
    messages: [
      { role: 'user', content: 'I need regex patterns to parse nginx access logs.' },
      { role: 'assistant', content: 'Here are battle-tested patterns for common nginx log formats:', hasCode: true },
      { role: 'user', content: 'Now parse error logs with stack traces too.' },
      { role: 'assistant', content: 'For multi-line stack traces you\'ll need a different approach:', hasCode: true, hasLink: true },
    ],
    detectedFormats: [
      { type: 'code', count: 5 },
      { type: 'link', count: 2 },
    ],
    fileSize: '16.8 KB',
    tokens: 3360,
    outputSize: '12.2 KB',
    outputTokens: 2450,
  },
  {
    id: 'discord',
    name: 'Discord',
    icon: 'D',
    color: '#5865F2',
    textColor: 'text-indigo-400',
    borderColor: 'border-indigo-500/30',
    bgColor: 'bg-indigo-500/10',
    glowColor: 'bg-indigo-500/[0.06]',
    url: 'discord.com/channels/export/928371',
    title: 'Team Debug Session - Auth Middleware',
    messages: [
      { role: 'user', content: 'Anyone know why JWT refresh tokens are expiring early?' },
      { role: 'assistant', content: 'Check your clock skew tolerance. Most JWT libs default to 0s which is too strict:', hasCode: true },
      { role: 'user', content: 'That was it! Changed to 30s leeway and it\'s working.' },
      { role: 'assistant', content: 'Good catch. Also consider rotating refresh tokens on each use for better security:', hasCode: true, hasLink: true },
    ],
    detectedFormats: [
      { type: 'code', count: 3 },
      { type: 'link', count: 4 },
      { type: 'image', count: 1 },
    ],
    fileSize: '19.5 KB',
    tokens: 3900,
    outputSize: '14.8 KB',
    outputTokens: 2960,
  },
  {
    id: 'slack',
    name: 'Slack',
    icon: 'S',
    color: '#E01E5A',
    textColor: 'text-rose-400',
    borderColor: 'border-rose-500/30',
    bgColor: 'bg-rose-500/10',
    glowColor: 'bg-rose-500/[0.06]',
    url: 'slack.com/archives/C04NQKP/thread',
    title: 'Deploy Pipeline Troubleshooting',
    messages: [
      { role: 'user', content: 'CI pipeline is failing on the Docker build step. Here\'s the log:' },
      { role: 'assistant', content: 'The multi-stage build is referencing a deleted base image tag. Pin it to a digest:', hasCode: true, hasTable: true },
      { role: 'user', content: 'Fixed! But now the health check is timing out in k8s.' },
      { role: 'assistant', content: 'Increase initialDelaySeconds and add a proper readiness probe separate from liveness:', hasCode: true },
    ],
    detectedFormats: [
      { type: 'code', count: 4 },
      { type: 'table', count: 1 },
      { type: 'link', count: 2 },
    ],
    fileSize: '21.2 KB',
    tokens: 4240,
    outputSize: '16.1 KB',
    outputTokens: 3220,
  },
];

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function ChatBubble({
  message,
  index,
  isHighlighted,
  isDecomposing,
  providerColor,
}: {
  message: ChatMessage;
  index: number;
  isHighlighted: boolean;
  isDecomposing: boolean;
  providerColor: string;
}) {
  const isUser = message.role === 'user';

  return (
    <motion.div
      initial={{ opacity: 0, x: isUser ? -12 : 12 }}
      animate={{
        opacity: isDecomposing ? 0.3 : 1,
        x: 0,
        scale: isDecomposing ? 0.95 : isHighlighted ? 1.01 : 1,
      }}
      transition={{
        type: 'spring',
        stiffness: 200,
        damping: 25,
        delay: index * 0.08,
      }}
      className={`flex gap-2 ${isUser ? '' : 'flex-row-reverse'}`}
    >
      <div
        className={`shrink-0 h-6 w-6 rounded-full flex items-center justify-center text-[10px] font-bold ${
          isUser
            ? 'bg-white/10 text-white/60'
            : 'text-white'
        }`}
        style={isUser ? undefined : { backgroundColor: providerColor + '33' }}
      >
        {isUser ? <User className="h-3 w-3" /> : <Bot className="h-3 w-3" />}
      </div>
      <div
        className={`relative rounded-xl px-3 py-2 max-w-[85%] text-xs leading-relaxed transition duration-300 ${
          isUser
            ? 'bg-white/[0.06] border border-white/[0.08] text-white/70'
            : 'border text-white/80'
        } ${
          isHighlighted && !isDecomposing
            ? 'ring-1 ring-white/20 shadow-lg'
            : ''
        }`}
        style={
          !isUser
            ? {
                backgroundColor: providerColor + '0D',
                borderColor: providerColor + '30',
              }
            : undefined
        }
      >
        <p className="line-clamp-2">{message.content}</p>
        {/* Format indicators */}
        {(message.hasCode || message.hasImage || message.hasLink || message.hasTable) && (
          <div className="flex gap-1 mt-1.5">
            {message.hasCode && (
              <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[10px]">
                <Code2 className="h-2 w-2" /> code
              </span>
            )}
            {message.hasImage && (
              <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-pink-500/10 border border-pink-500/20 text-pink-400 text-[10px]">
                <ImageIcon className="h-2 w-2" /> img
              </span>
            )}
            {message.hasLink && (
              <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-blue-500/10 border border-blue-500/20 text-blue-400 text-[10px]">
                <ExternalLink className="h-2 w-2" /> link
              </span>
            )}
            {message.hasTable && (
              <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-amber-500/10 border border-amber-500/20 text-amber-400 text-[10px]">
                <Table className="h-2 w-2" /> table
              </span>
            )}
          </div>
        )}
      </div>
    </motion.div>
  );
}

function MarkdownBlock({
  index,
  type,
  content,
  visible,
}: {
  index: number;
  type: 'heading' | 'text' | 'code' | 'metadata';
  content: string;
  visible: boolean;
}) {
  const styles: Record<string, string> = {
    heading: 'text-white/90 font-bold text-xs',
    text: 'text-white/60 text-xs',
    code: 'text-emerald-400 font-mono text-[10px] bg-emerald-500/[0.06] border border-emerald-500/20 rounded-md px-2 py-1',
    metadata: 'text-white/30 font-mono text-[10px] italic',
  };

  return (
    <AnimatePresence>
      {visible && (
        <motion.div
          initial={{ opacity: 0, x: 30, scale: 0.9 }}
          animate={{ opacity: 1, x: 0, scale: 1 }}
          exit={{ opacity: 0, x: -10 }}
          transition={{
            type: 'spring',
            stiffness: 200,
            damping: 25,
            delay: index * 0.12,
          }}
          className={styles[type]}
        >
          {content}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function FormatDetectionBadge({
  badge,
  index,
  isDetecting,
  isDetected,
  active,
}: {
  badge: FormatBadge;
  index: number;
  isDetecting: boolean;
  isDetected: boolean;
  active: boolean;
}) {
  const Icon = FORMAT_ICONS[badge.type];
  const colorClass = FORMAT_COLORS[badge.type];

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.6 }}
      animate={{
        opacity: isDetected ? 1 : isDetecting ? 0.6 : 0.2,
        scale: isDetected ? 1 : isDetecting ? 0.95 : 0.85,
      }}
      transition={{
        type: 'spring',
        stiffness: 200,
        damping: 25,
        delay: index * 0.15,
      }}
      className={`inline-flex items-center gap-1.5 px-2 py-1 rounded-lg border text-[10px] font-medium ${colorClass} ${
        isDetecting && !isDetected ? 'animate-pulse' : ''
      }`}
    >
      {Icon && <Icon className="h-3 w-3" />}
      <span className="capitalize">{badge.type}</span>
      {isDetected && (
        <motion.span
          initial={{ opacity: 0, scale: 0 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
          className="font-mono"
        >
          x{badge.count}
        </motion.span>
      )}
      {isDetecting && !isDetected && (
        <motion.div
          animate={active ? { rotate: 360 } : { rotate: 0 }}
          transition={active ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
          className="h-2 w-2 border border-current border-t-transparent rounded-full"
        />
      )}
    </motion.div>
  );
}

function PipelineProgressBar({
  stage,
  providerColor,
}: {
  stage: PipelineStage;
  providerColor: string;
}) {
  const stageIdx = PIPELINE_STAGES.findIndex((s) => s.key === stage);
  const totalStages = PIPELINE_STAGES.length;
  const progressPercent = stage === 'done'
    ? 100
    : stage === 'idle'
      ? 0
      : ((stageIdx + 0.5) / totalStages) * 100;
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  return (
    <div ref={rootRef} className="space-y-2">
      {/* Stage labels */}
      <div className="flex justify-between">
        {PIPELINE_STAGES.map((s, i) => {
          const Icon = s.icon;
          const isPast = stage === 'done' || stageIdx > i;
          const isCurrent = stageIdx === i && stage !== 'done';

          return (
            <div key={s.key} className="flex flex-col items-center gap-1">
              <motion.div
                animate={{
                  scale: isCurrent ? 1.15 : 1,
                  opacity: isPast || isCurrent ? 1 : 0.3,
                }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className="relative"
              >
                {isPast ? (
                  <CheckCircle2 className="h-4 w-4 text-emerald-400" />
                ) : isCurrent ? (
                  <motion.div
                    animate={inView ? { rotate: [0, 5, -5, 0] } : { rotate: 0 }}
                    transition={inView ? { duration: 0.8, repeat: Infinity } : { duration: 0.2 }}
                  >
                    <Icon className="h-4 w-4" style={{ color: providerColor }} />
                  </motion.div>
                ) : (
                  <Icon className="h-4 w-4 text-white/20" />
                )}
              </motion.div>
              <span
                className={`text-[10px] font-medium hidden sm:block ${
                  isPast
                    ? 'text-emerald-400'
                    : isCurrent
                      ? 'text-white/80'
                      : 'text-white/30'
                }`}
              >
                {s.label}
              </span>
            </div>
          );
        })}
      </div>

      {/* Progress bar track */}
      <div className="relative h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
        <motion.div
          className="absolute inset-y-0 left-0 rounded-full"
          style={{ backgroundColor: providerColor }}
          initial={{ width: '0%' }}
          animate={{ width: `${progressPercent}%` }}
          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
        />
        {/* Animated shimmer on the bar */}
        {stage !== 'idle' && stage !== 'done' && (
          <motion.div
            className="absolute inset-y-0 w-16 rounded-full"
            style={{
              background: `linear-gradient(90deg, transparent, ${providerColor}44, transparent)`,
            }}
            animate={inView ? { x: ['-64px', '400px'] } : { x: '-64px' }}
            transition={inView ? { duration: 1.5, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
          />
        )}
      </div>
    </div>
  );
}

function SizeComparison({
  source,
}: {
  source: SourceInfo;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.3 }}
      className="grid grid-cols-2 gap-3"
    >
      {/* Input stats */}
      <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 space-y-2">
        <div className="flex items-center gap-1.5">
          <Globe className="h-3 w-3 text-white/40" />
          <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">
            Raw Input
          </span>
        </div>
        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-white/50">Size</span>
            <span className="text-[10px] font-mono text-white/70">{source.fileSize}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-white/50">Tokens</span>
            <span className="text-[10px] font-mono text-white/70">{source.tokens.toLocaleString()}</span>
          </div>
        </div>
      </div>

      {/* Output stats */}
      <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/[0.04] p-3 space-y-2">
        <div className="flex items-center gap-1.5">
          <FileText className="h-3 w-3 text-emerald-400/60" />
          <span className="text-[10px] font-semibold text-emerald-400/60 uppercase tracking-wider">
            Clean Output
          </span>
        </div>
        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-emerald-400/50">Size</span>
            <span className="text-[10px] font-mono text-emerald-400/80">{source.outputSize}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-emerald-400/50">Tokens</span>
            <span className="text-[10px] font-mono text-emerald-400/80">{source.outputTokens.toLocaleString()}</span>
          </div>
        </div>
      </div>

      {/* Savings indicator */}
      <motion.div
        className="col-span-2 text-center"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5 }}
      >
        <span className="text-[10px] text-emerald-400/70">
          {Math.round((1 - source.outputTokens / source.tokens) * 100)}% smaller after cleaning
          {' '}({(source.tokens - source.outputTokens).toLocaleString()} tokens saved)
        </span>
      </motion.div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Markdown output lines for each source
// ---------------------------------------------------------------------------
function getMarkdownLines(source: SourceInfo): { type: 'heading' | 'text' | 'code' | 'metadata'; content: string }[] {
  return [
    { type: 'metadata', content: `<!-- Converted by CSCTF from ${source.name} -->` },
    { type: 'heading', content: `# ${source.title}` },
    { type: 'metadata', content: `*Source: ${source.url} | ${source.messages.length} messages*` },
    { type: 'text', content: `**User:** ${source.messages[0].content}` },
    { type: 'text', content: `**${source.name}:** ${source.messages[1].content.slice(0, 60)}...` },
    { type: 'code', content: '```typescript\n  // extracted code block\n```' },
    { type: 'text', content: `**User:** ${source.messages[2].content}` },
    { type: 'text', content: `**${source.name}:** ${source.messages[3].content.slice(0, 60)}...` },
    { type: 'code', content: '```typescript\n  // extracted code block\n```' },
    { type: 'metadata', content: `<!-- ${source.detectedFormats.map((f) => `${f.count} ${f.type}(s)`).join(', ')} -->` },
  ];
}

// ---------------------------------------------------------------------------
// Main Pipeline Component
// ---------------------------------------------------------------------------

function InteractiveConversionPipelineImpl() {
  const [selectedSource, setSelectedSource] = useState<string | null>(null);
  const [stage, setStage] = useState<PipelineStage>('idle');
  const [highlightedMsg, setHighlightedMsg] = useState(-1);
  const [visibleMdLines, setVisibleMdLines] = useState(0);
  const [formatDetectionIdx, setFormatDetectionIdx] = useState(-1);
  const timerIdsRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const source = useMemo(
    () => SOURCES.find((s) => s.id === selectedSource) ?? null,
    [selectedSource],
  );

  const markdownLines = useMemo(
    () => (source ? getMarkdownLines(source) : []),
    [source],
  );

  const clearTimers = useCallback(() => {
    timerIdsRef.current.forEach(clearTimeout);
    timerIdsRef.current = [];
  }, []);

  // Cleanup on unmount
  useEffect(() => clearTimers, [clearTimers]);

  const isRunning = stage !== 'idle' && stage !== 'done';

  const handleSelectSource = useCallback(
    (id: string) => {
      if (isRunning) return;
      clearTimers();

      setSelectedSource(id);
      setStage('fetch');
      setHighlightedMsg(-1);
      setVisibleMdLines(0);
      setFormatDetectionIdx(-1);

      const t = (fn: () => void, delay: number) => {
        const tid = setTimeout(fn, delay);
        timerIdsRef.current.push(tid);
      };

      // Stage: fetch -> parse (highlight chat messages one by one)
      t(() => setStage('parse'), 700);
      t(() => setHighlightedMsg(0), 800);
      t(() => setHighlightedMsg(1), 1100);
      t(() => setHighlightedMsg(2), 1400);
      t(() => setHighlightedMsg(3), 1700);

      // Stage: clean (detect formats)
      t(() => setStage('clean'), 2000);
      t(() => setFormatDetectionIdx(0), 2100);
      t(() => setFormatDetectionIdx(1), 2400);
      t(() => setFormatDetectionIdx(2), 2700);
      t(() => setFormatDetectionIdx(3), 3000);

      // Stage: format (generate markdown lines)
      t(() => setStage('format'), 3200);
      t(() => setVisibleMdLines(1), 3300);
      t(() => setVisibleMdLines(2), 3500);
      t(() => setVisibleMdLines(3), 3700);
      t(() => setVisibleMdLines(4), 3900);
      t(() => setVisibleMdLines(5), 4100);
      t(() => setVisibleMdLines(6), 4300);
      t(() => setVisibleMdLines(7), 4500);
      t(() => setVisibleMdLines(8), 4700);
      t(() => setVisibleMdLines(9), 4900);
      t(() => setVisibleMdLines(10), 5100);

      // Stage: output -> done
      t(() => setStage('output'), 5200);
      t(() => {
        setStage('done');
        timerIdsRef.current = [];
      }, 5800);
    },
    [clearTimers, isRunning],
  );

  const handleReset = useCallback(() => {
    clearTimers();
    setStage('idle');
    setSelectedSource(null);
    setHighlightedMsg(-1);
    setVisibleMdLines(0);
    setFormatDetectionIdx(-1);
  }, [clearTimers]);

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-72 h-72 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-56 h-56 bg-violet-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-5 sm:p-8 space-y-5">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-white/[0.08] bg-white/[0.03] mb-2">
            <Layers className="h-3 w-3 text-white/50" />
            <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
              Live Pipeline
            </span>
          </div>
          <p className="text-sm font-semibold text-white/90">
            Interactive Conversion Pipeline
          </p>
          <p className="text-xs text-white/40 max-w-md mx-auto">
            Select a source to watch CSCTF fetch, parse, and convert a conversation into clean Markdown
          </p>
        </div>

        {/* Source Selection - 6 sources in 2 rows of 3 */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
          {SOURCES.map((s) => {
            const isActive = selectedSource === s.id;
            return (
              <motion.button
                key={s.id}
                type="button"
                onClick={() => handleSelectSource(s.id)}
                disabled={isRunning}
                whileHover={isRunning ? undefined : { scale: 1.03 }}
                whileTap={isRunning ? undefined : { scale: 0.97 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className={`relative rounded-xl border p-2.5 text-left transition-colors ${
                  isActive
                    ? `${s.borderColor} ${s.bgColor}`
                    : 'border-white/[0.08] bg-white/[0.02] hover:bg-white/[0.04]'
                } ${isRunning && !isActive ? 'opacity-30 cursor-not-allowed' : 'cursor-pointer'}`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <div
                    className="h-5 w-5 rounded-md flex items-center justify-center text-[10px] font-bold text-white"
                    style={{ backgroundColor: s.color + '33' }}
                  >
                    {s.icon}
                  </div>
                  <span
                    className={`text-xs font-semibold ${isActive ? s.textColor : 'text-white/70'}`}
                  >
                    {s.name}
                  </span>
                </div>
                <p className="text-[10px] text-white/30 font-mono truncate">{s.url}</p>
                <p className="text-[10px] text-white/50 truncate mt-0.5">{s.title}</p>
              </motion.button>
            );
          })}
        </div>

        {/* Pipeline Content */}
        <AnimatePresence mode="wait">
          {stage !== 'idle' && source && (
            <motion.div
              key={`pipeline-${source.id}`}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -12 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="space-y-4"
            >
              {/* URL bar */}
              <div className="rounded-xl border border-white/[0.08] bg-white/[0.03] p-3 flex items-center gap-3">
                <Link2 className="h-3.5 w-3.5 text-white/30 shrink-0" />
                <p className="text-[10px] font-mono text-white/60 truncate flex-1">
                  https://{source.url}
                </p>
                <div className="flex items-center gap-1">
                  <Clock className="h-3 w-3 text-white/30" />
                  <span className="text-[10px] text-white/30 font-mono">
                    {source.messages.length} msgs
                  </span>
                </div>
              </div>

              {/* Progress bar */}
              <PipelineProgressBar stage={stage} providerColor={source.color} />

              {/* Main two-panel area: Chat on left, Markdown on right */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {/* LEFT: Chat Conversation Panel */}
                <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 space-y-2 min-h-[200px]">
                  <div className="flex items-center gap-2 mb-2">
                    <MessageSquare className="h-3 w-3 text-white/40" />
                    <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">
                      Source Conversation
                    </span>
                    <div className="flex-1" />
                    <span
                      className="text-[10px] font-semibold px-1.5 py-0.5 rounded-md"
                      style={{
                        color: source.color,
                        backgroundColor: source.color + '1A',
                      }}
                    >
                      {source.name}
                    </span>
                  </div>

                  <div className="space-y-2">
                    {source.messages.map((msg, i) => (
                      <ChatBubble
                        key={i}
                        message={msg}
                        index={i}
                        isHighlighted={highlightedMsg >= i}
                        isDecomposing={
                          (stage === 'format' || stage === 'output' || stage === 'done') &&
                          highlightedMsg >= i
                        }
                        providerColor={source.color}
                      />
                    ))}
                  </div>

                  {/* Format Detection Badges */}
                  <AnimatePresence>
                    {(stage === 'clean' || stage === 'format' || stage === 'output' || stage === 'done') && (
                      <motion.div
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                        className="pt-2 border-t border-white/[0.06]"
                      >
                        <span className="text-[10px] text-white/30 uppercase tracking-wider font-semibold block mb-1.5">
                          Detected Formats
                        </span>
                        <div className="flex flex-wrap gap-1.5">
                          {source.detectedFormats.map((badge, i) => (
                            <FormatDetectionBadge
                              key={badge.type}
                              badge={badge}
                              index={i}
                              isDetecting={formatDetectionIdx >= i && formatDetectionIdx < source.detectedFormats.length}
                              isDetected={formatDetectionIdx > i || stage === 'format' || stage === 'output' || stage === 'done'}
                              active={inView}
                            />
                          ))}
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>

                {/* RIGHT: Markdown Output Panel */}
                <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3 space-y-1.5 min-h-[200px]">
                  <div className="flex items-center gap-2 mb-2">
                    <FileText className="h-3 w-3 text-white/40" />
                    <span className="text-[10px] font-semibold text-white/40 uppercase tracking-wider">
                      Markdown Output
                    </span>
                    <div className="flex-1" />
                    {stage === 'done' && (
                      <motion.span
                        initial={{ opacity: 0, scale: 0.8 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                        className="text-[10px] font-semibold text-emerald-400 px-1.5 py-0.5 rounded-md bg-emerald-500/10"
                      >
                        Complete
                      </motion.span>
                    )}
                  </div>

                  {/* Markdown lines appear progressively */}
                  <div className="space-y-1.5 font-mono">
                    {markdownLines.map((line, i) => (
                      <MarkdownBlock
                        key={i}
                        index={i}
                        type={line.type}
                        content={line.content}
                        visible={i < visibleMdLines}
                      />
                    ))}
                  </div>

                  {/* Center arrow when nothing to show yet */}
                  {visibleMdLines === 0 && stage !== 'done' && (
                    <div className="flex items-center justify-center h-24 text-white/10">
                      <motion.div
                        animate={inView ? { x: [0, 6, 0] } : { x: 0 }}
                        transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
                        className="flex items-center gap-2"
                      >
                        <ChevronRight className="h-5 w-5" />
                        <span className="text-[10px]">Waiting for pipeline...</span>
                      </motion.div>
                    </div>
                  )}
                </div>
              </div>

              {/* Conversion arrow between panels (visible only on md+) */}
              <div className="hidden md:flex absolute top-1/2 left-1/2 -translate-x-1/2 pointer-events-none" style={{ marginTop: '80px' }}>
                <AnimatePresence>
                  {(stage === 'format' || stage === 'output') && (
                    <motion.div
                      initial={{ opacity: 0, scale: 0 }}
                      animate={{ opacity: 0.5, scale: 1 }}
                      exit={{ opacity: 0, scale: 0 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    >
                      <ArrowRight className="h-5 w-5 text-white/20" />
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Done: Output files + size comparison */}
              <AnimatePresence>
                {stage === 'done' && (
                  <motion.div
                    initial={{ opacity: 0, y: 12 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    className="space-y-4"
                  >
                    <div className="flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4 text-emerald-400" />
                      <span className="text-xs font-semibold text-emerald-400">
                        Conversion complete
                      </span>
                    </div>

                    {/* Output file cards */}
                    <div className="grid sm:grid-cols-2 gap-3">
                      <motion.div
                        initial={{ opacity: 0, x: -16 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.1 }}
                        className="rounded-xl border border-blue-500/20 bg-blue-500/[0.06] p-3 space-y-2"
                      >
                        <div className="flex items-center gap-2">
                          <FileText className="h-4 w-4 text-blue-400" />
                          <span className="text-xs font-semibold text-blue-400">Markdown</span>
                        </div>
                        <p className="text-[10px] font-mono text-white/50 break-all">
                          {source.title.toLowerCase().replace(/\s+/g, '_')}.md
                        </p>
                        <div className="space-y-1 pt-1">
                          <OutputMetric icon={MessageSquare} label="Messages" value={source.messages.length * 2} />
                          <OutputMetric icon={Code2} label="Code blocks" value={source.detectedFormats.find((f) => f.type === 'code')?.count ?? 0} />
                          <OutputMetric icon={Hash} label="Headings" value={source.messages.length} />
                        </div>
                      </motion.div>

                      <motion.div
                        initial={{ opacity: 0, x: 16 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.2 }}
                        className="rounded-xl border border-violet-500/20 bg-violet-500/[0.06] p-3 space-y-2"
                      >
                        <div className="flex items-center gap-2">
                          <FileCode className="h-4 w-4 text-violet-400" />
                          <span className="text-xs font-semibold text-violet-400">HTML</span>
                        </div>
                        <p className="text-[10px] font-mono text-white/50 break-all">
                          {source.title.toLowerCase().replace(/\s+/g, '_')}.html
                        </p>
                        <div className="space-y-1 pt-1">
                          <OutputMetric icon={Shield} label="Syntax highlighting" value="Yes" />
                          <OutputMetric icon={Globe} label="Self-contained" value="Yes" />
                          <OutputMetric icon={Download} label="Offline-ready" value="Yes" />
                        </div>
                      </motion.div>
                    </div>

                    {/* Size / token comparison */}
                    <SizeComparison source={source} />
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Reset Button */}
        {stage === 'done' && (
          <div className="flex justify-center pt-1">
            <motion.button
              type="button"
              onClick={handleReset}
              initial={{ opacity: 0, scale: 0.85 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.96 }}
              className="flex items-center gap-2 rounded-xl border border-white/[0.08] bg-white/[0.03] px-5 py-2 text-xs font-medium text-white/50 hover:text-white/70 transition-colors"
            >
              <RotateCcw className="h-3.5 w-3.5" />
              Try Another Source
            </motion.button>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Helper: Output metric row
// ---------------------------------------------------------------------------

function OutputMetric({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof MessageSquare;
  label: string;
  value: string | number;
}) {
  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-1.5">
        <Icon className="h-3 w-3 text-white/30" />
        <span className="text-[10px] text-white/40">{label}</span>
      </div>
      <span className="text-[10px] font-mono text-white/60">{value}</span>
    </div>
  );
}
