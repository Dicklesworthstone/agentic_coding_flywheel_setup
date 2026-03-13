'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from '@/components/motion';
import {
  Terminal,
  Image as ImageIcon,
  Cloud,
  Download,
  Eye,
  Share2,
  CheckCircle,
  AlertCircle,
  CloudDrizzle,
  Droplets,
  Camera,
  FileImage,
  Loader2,
  Link,
  Wifi,
  Shield,
  Zap,
  Globe,
  Layers,
  ArrowRight,
  Copy,
  HardDrive,
  Lock,
  Unlock,
  RefreshCw,
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

export function GiilLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Download cloud-hosted images for visual debugging with giil.
      </GoalBanner>

      {/* Section 1: What Is GIIL */}
      <Section title="What Is GIIL?" icon={<ImageIcon className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>GIIL</Highlight> (Get Image from Internet Link) downloads full-resolution images
          from cloud sharing services directly to your terminal. When a user shares a screenshot via
          iCloud, Dropbox, or Google Photos, GIIL fetches the actual image for AI agent analysis.
        </Paragraph>
        <Paragraph>
          This bridges the gap between mobile screenshots and terminal-based debugging. Users capture
          bugs on their phone, share a link, and agents can immediately view and analyze the image.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Cloud className="h-5 w-5" />}
              title="Multi-Platform"
              description="iCloud, Dropbox, Google Photos, Drive"
              gradient="from-blue-500/20 to-cyan-500/20"
            />
            <FeatureCard
              icon={<Download className="h-5 w-5" />}
              title="Full Resolution"
              description="Downloads original quality images"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Eye className="h-5 w-5" />}
              title="Visual Debugging"
              description="AI agents can analyze images"
              gradient="from-purple-500/20 to-pink-500/20"
            />
            <FeatureCard
              icon={<Share2 className="h-5 w-5" />}
              title="Album Support"
              description="Download all images with --all"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Section 2: Supported Platforms */}
      <Section title="Supported Platforms" icon={<Cloud className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          GIIL extracts images from these cloud sharing services:
        </Paragraph>
        <div className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="p-4 rounded-lg bg-gradient-to-br from-slate-800/50 to-slate-900/50 border border-slate-700/50">
            <h4 className="font-semibold text-white mb-2">iCloud</h4>
            <code className="text-xs text-slate-400">share.icloud.com/*</code>
          </div>
          <div className="p-4 rounded-lg bg-gradient-to-br from-slate-800/50 to-slate-900/50 border border-slate-700/50">
            <h4 className="font-semibold text-white mb-2">Dropbox</h4>
            <code className="text-xs text-slate-400">dropbox.com/s/*, dl.dropbox.com/*</code>
          </div>
          <div className="p-4 rounded-lg bg-gradient-to-br from-slate-800/50 to-slate-900/50 border border-slate-700/50">
            <h4 className="font-semibold text-white mb-2">Google Photos</h4>
            <code className="text-xs text-slate-400">photos.google.com/*</code>
          </div>
          <div className="p-4 rounded-lg bg-gradient-to-br from-slate-800/50 to-slate-900/50 border border-slate-700/50">
            <h4 className="font-semibold text-white mb-2">Google Drive</h4>
            <code className="text-xs text-slate-400">drive.google.com/*</code>
          </div>
        </div>
      </Section>

      <Divider />

      {/* Interactive Cloud Download Visualization */}
      <Section title="Try It: Cloud Download Simulator" icon={<Download className="h-5 w-5" />} delay={0.17}>
        <Paragraph>
          Click a cloud provider below to simulate downloading an image with <Highlight>giil</Highlight>.
          Watch the terminal command, progress bar, and image preview in action.
        </Paragraph>
        <div className="mt-6">
          <InteractiveCloudDownload />
        </div>
      </Section>

      <Divider />

      {/* Section 3: Essential Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'giil "<url>"', description: 'Download image from cloud link' },
            { command: 'giil "<url>" --output ~/screenshots', description: 'Save to custom directory' },
            { command: 'giil "<url>" --json', description: 'Output JSON metadata' },
            { command: 'giil "<url>" --all', description: 'Download all images from album' },
            { command: 'giil --help', description: 'Show all options' },
          ]}
        />

        <TipBox variant="info">
          Always wrap URLs in quotes to prevent shell expansion of special characters.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 4: Visual Debugging Workflow */}
      <Section title="Visual Debugging Workflow" icon={<Eye className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          GIIL enables a powerful visual debugging pattern for AI-assisted development:
        </Paragraph>

        <div className="mt-6 space-y-4">
          <div className="flex items-start gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-400 font-bold">1</div>
            <div>
              <h4 className="font-semibold text-white">User Screenshots Bug</h4>
              <p className="text-slate-400 text-sm">User captures the issue on their phone or desktop</p>
            </div>
          </div>
          <div className="flex items-start gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-400 font-bold">2</div>
            <div>
              <h4 className="font-semibold text-white">Share Cloud Link</h4>
              <p className="text-slate-400 text-sm">User shares iCloud/Dropbox/Google Photos link with agent</p>
            </div>
          </div>
          <div className="flex items-start gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-purple-500/20 flex items-center justify-center text-purple-400 font-bold">3</div>
            <div>
              <h4 className="font-semibold text-white">GIIL Downloads Image</h4>
              <p className="text-slate-400 text-sm"><code className="text-xs">giil &quot;&lt;url&gt;&quot;</code> fetches full-resolution image to working directory</p>
            </div>
          </div>
          <div className="flex items-start gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-500/20 flex items-center justify-center text-amber-400 font-bold">4</div>
            <div>
              <h4 className="font-semibold text-white">Agent Analyzes</h4>
              <p className="text-slate-400 text-sm">AI agent can now view and understand the visual context</p>
            </div>
          </div>
        </div>

        <CodeBlock code={`# Example: User reports UI bug
# They share: https://share.icloud.com/photos/abc123

# Download the screenshot
giil "https://share.icloud.com/photos/abc123"

# Image saved to current directory
# Agent can now analyze: screenshot.jpg`} />
      </Section>

      <Divider />

      {/* Section 5: Exit Codes */}
      <Section title="Exit Codes" icon={<CheckCircle className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          GIIL uses specific exit codes to indicate different outcomes:
        </Paragraph>

        <div className="mt-4 space-y-2">
          <div className="flex items-center gap-3 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/20">
            <CheckCircle className="h-5 w-5 text-emerald-400" />
            <span className="text-emerald-300 font-mono">0</span>
            <span className="text-slate-300">Success - Image downloaded</span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
            <AlertCircle className="h-5 w-5 text-red-400" />
            <span className="text-red-300 font-mono">10</span>
            <span className="text-slate-300">Network error - Check connectivity</span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20">
            <AlertCircle className="h-5 w-5 text-amber-400" />
            <span className="text-amber-300 font-mono">11</span>
            <span className="text-slate-300">Auth required - Link not publicly shared</span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-orange-500/10 border border-orange-500/20">
            <AlertCircle className="h-5 w-5 text-orange-400" />
            <span className="text-orange-300 font-mono">12</span>
            <span className="text-slate-300">Not found - Link expired or deleted</span>
          </div>
          <div className="flex items-center gap-3 p-3 rounded-lg bg-slate-500/10 border border-slate-500/20">
            <AlertCircle className="h-5 w-5 text-slate-400" />
            <span className="text-slate-300 font-mono">13</span>
            <span className="text-slate-300">Unsupported type - Video or document</span>
          </div>
        </div>

        <TipBox variant="warning">
          Exit code 11 (auth required) means the link is private. Ask the user to update
          sharing settings to &quot;Anyone with the link.&quot;
        </TipBox>
      </Section>

      <Divider />

      {/* Section 6: Advanced Usage */}
      <Section title="Advanced Usage" icon={<Terminal className="h-5 w-5" />} delay={0.35}>
        <CodeBlock code={`# Download to specific directory
giil "https://share.icloud.com/photos/abc123" --output ~/debug-screenshots

# Get JSON metadata (useful for scripting)
giil "https://dropbox.com/s/xyz789/screenshot.png" --json

# Download all images from a shared album
giil "https://photos.google.com/share/album123" --all

# Check if download succeeded in a script
if giil "$URL" 2>/dev/null; then
  echo "Image ready for analysis"
else
  echo "Download failed with code $?"
fi`} />

        <TipBox variant="info">
          GIIL only supports images. For videos or documents, you&apos;ll need to download
          them manually or use a different tool.
        </TipBox>
      </Section>
    </div>
  );
}

/* ─── Provider data for InteractiveCloudDownload ─── */

const SPRING = { type: 'spring' as const, stiffness: 200, damping: 25 };

interface CloudProvider {
  id: string;
  name: string;
  icon: React.ReactNode;
  brandColor: string;
  borderColor: string;
  textColor: string;
  gradient: string;
  glowColor: string;
  url: string;
  urlPattern: string;
  protocol: string;
  bypassMethod: string;
  file: {
    name: string;
    sizeBytes: number;
    size: string;
    dimensions: string;
    format: string;
    colorDepth: string;
  };
  imageGradient: string;
  pipelineSteps: string[];
}

const CLOUD_PROVIDERS: CloudProvider[] = [
  {
    id: 'icloud',
    name: 'iCloud',
    icon: <Cloud className="h-5 w-5" />,
    brandColor: 'bg-blue-500',
    borderColor: 'border-blue-500/30',
    textColor: 'text-blue-400',
    gradient: 'from-blue-500/20 to-cyan-500/20',
    glowColor: 'shadow-blue-500/20',
    url: 'https://share.icloud.com/photos/0a9Xk_login-bug-screenshot',
    urlPattern: 'share.icloud.com/photos/*',
    protocol: 'iCloud Web API',
    bypassMethod: 'Token extraction from share page meta tags',
    file: {
      name: 'login-bug-screenshot.jpg',
      sizeBytes: 2516582,
      size: '2.4 MB',
      dimensions: '2532 x 1170',
      format: 'JPEG',
      colorDepth: '24-bit sRGB',
    },
    imageGradient: 'from-blue-600/40 via-cyan-500/30 to-sky-400/40',
    pipelineSteps: [
      'GET share page HTML',
      'Extract data-token from meta',
      'POST /api/records/resolve',
      'Follow downloadURL redirect',
      'Stream binary to disk',
    ],
  },
  {
    id: 'dropbox',
    name: 'Dropbox',
    icon: <Droplets className="h-5 w-5" />,
    brandColor: 'bg-indigo-500',
    borderColor: 'border-indigo-500/30',
    textColor: 'text-indigo-400',
    gradient: 'from-indigo-500/20 to-blue-500/20',
    glowColor: 'shadow-indigo-500/20',
    url: 'https://dropbox.com/s/xr7kz/dashboard-overflow.png',
    urlPattern: 'dropbox.com/s/*',
    protocol: 'Dropbox Content API',
    bypassMethod: 'dl=1 parameter forces raw binary download',
    file: {
      name: 'dashboard-overflow.png',
      sizeBytes: 1887436,
      size: '1.8 MB',
      dimensions: '1920 x 1080',
      format: 'PNG',
      colorDepth: '32-bit RGBA',
    },
    imageGradient: 'from-indigo-600/40 via-violet-500/30 to-blue-400/40',
    pipelineSteps: [
      'Rewrite URL: ?dl=1',
      'Follow 302 to dl.dropbox.com',
      'Negotiate content-type',
      'Verify image/* MIME',
      'Stream binary to disk',
    ],
  },
  {
    id: 'google-photos',
    name: 'Google Photos',
    icon: <Camera className="h-5 w-5" />,
    brandColor: 'bg-emerald-500',
    borderColor: 'border-emerald-500/30',
    textColor: 'text-emerald-400',
    gradient: 'from-emerald-500/20 to-teal-500/20',
    glowColor: 'shadow-emerald-500/20',
    url: 'https://photos.google.com/share/AF1Q_mobile-crash',
    urlPattern: 'photos.google.com/share/*',
    protocol: 'Google Photos Embed API',
    bypassMethod: 'Parse data-image-url from share embed page',
    file: {
      name: 'mobile-crash-report.jpg',
      sizeBytes: 3250585,
      size: '3.1 MB',
      dimensions: '2778 x 1284',
      format: 'JPEG',
      colorDepth: '24-bit sRGB',
    },
    imageGradient: 'from-emerald-600/40 via-teal-500/30 to-green-400/40',
    pipelineSteps: [
      'GET share/embed page',
      'Scrape data-image-url',
      'Append =w0-h0 for full res',
      'GET image with referer',
      'Stream binary to disk',
    ],
  },
  {
    id: 'google-drive',
    name: 'Google Drive',
    icon: <HardDrive className="h-5 w-5" />,
    brandColor: 'bg-yellow-500',
    borderColor: 'border-yellow-500/30',
    textColor: 'text-yellow-400',
    gradient: 'from-yellow-500/20 to-amber-500/20',
    glowColor: 'shadow-yellow-500/20',
    url: 'https://drive.google.com/file/d/1Bk9q_error-toast/view',
    urlPattern: 'drive.google.com/file/d/*',
    protocol: 'Google Drive Export API',
    bypassMethod: 'Convert /view to /export?format=png',
    file: {
      name: 'error-toast-dialog.png',
      sizeBytes: 945210,
      size: '923 KB',
      dimensions: '1440 x 900',
      format: 'PNG',
      colorDepth: '32-bit RGBA',
    },
    imageGradient: 'from-yellow-600/40 via-amber-500/30 to-orange-400/40',
    pipelineSteps: [
      'Extract file ID from URL',
      'GET /uc?export=download&id=',
      'Handle virus scan warning',
      'Follow confirm token redirect',
      'Stream binary to disk',
    ],
  },
  {
    id: 'direct-url',
    name: 'Direct URL',
    icon: <Globe className="h-5 w-5" />,
    brandColor: 'bg-purple-500',
    borderColor: 'border-purple-500/30',
    textColor: 'text-purple-400',
    gradient: 'from-purple-500/20 to-pink-500/20',
    glowColor: 'shadow-purple-500/20',
    url: 'https://cdn.example.com/screenshots/navbar-bug.webp',
    urlPattern: '*.jpg, *.png, *.webp (any URL)',
    protocol: 'HTTP/2 Direct',
    bypassMethod: 'Direct binary download with content-type check',
    file: {
      name: 'navbar-bug.webp',
      sizeBytes: 578432,
      size: '565 KB',
      dimensions: '1366 x 768',
      format: 'WebP',
      colorDepth: '24-bit sRGB',
    },
    imageGradient: 'from-purple-600/40 via-pink-500/30 to-fuchsia-400/40',
    pipelineSteps: [
      'HEAD request for content-type',
      'Verify image/* MIME type',
      'GET with range support check',
      'Detect WebP/AVIF format',
      'Stream binary to disk',
    ],
  },
  {
    id: 'batch-album',
    name: 'Batch Album',
    icon: <Layers className="h-5 w-5" />,
    brandColor: 'bg-rose-500',
    borderColor: 'border-rose-500/30',
    textColor: 'text-rose-400',
    gradient: 'from-rose-500/20 to-orange-500/20',
    glowColor: 'shadow-rose-500/20',
    url: 'https://photos.google.com/share/album_3imgs --all',
    urlPattern: 'any album URL + --all flag',
    protocol: 'Batch Parallel Download',
    bypassMethod: 'Enumerate album, download all images concurrently',
    file: {
      name: '3 images (album)',
      sizeBytes: 7340032,
      size: '7.0 MB',
      dimensions: 'various',
      format: 'Mixed',
      colorDepth: 'Mixed',
    },
    imageGradient: 'from-rose-600/40 via-orange-500/30 to-amber-400/40',
    pipelineSteps: [
      'GET album share page',
      'Enumerate image entries',
      'Spawn parallel downloads (3)',
      'Verify each image on disk',
      'Report batch summary',
    ],
  },
];

/* ─── InteractiveCloudDownload component ─── */

type DownloadPhase =
  | 'idle'
  | 'pasting'
  | 'detecting'
  | 'negotiating'
  | 'downloading'
  | 'processing'
  | 'done';

const PHASE_LABELS: Record<DownloadPhase, string> = {
  idle: 'Ready',
  pasting: 'Pasting URL',
  detecting: 'Detecting Provider',
  negotiating: 'API Negotiation',
  downloading: 'Downloading',
  processing: 'Processing',
  done: 'Complete',
};

function formatBytes(bytes: number, progress: number): string {
  const downloaded = Math.floor((bytes * Math.min(progress, 100)) / 100);
  if (downloaded < 1024) return `${downloaded} B`;
  if (downloaded < 1048576) return `${(downloaded / 1024).toFixed(0)} KB`;
  return `${(downloaded / 1048576).toFixed(1)} MB`;
}

function formatSpeed(bytes: number, progress: number): string {
  if (progress <= 0 || progress > 100) return '-- KB/s';
  const fraction = Math.min(progress, 100) / 100;
  const speed = (bytes * fraction) / (fraction * 2.5);
  if (speed < 1024) return `${speed.toFixed(0)} B/s`;
  if (speed < 1048576) return `${(speed / 1024).toFixed(0)} KB/s`;
  return `${(speed / 1048576).toFixed(1)} MB/s`;
}

/* ─── Pipeline step sub-component ─── */

function PipelineStep({
  step,
  index,
  isActive,
  isComplete,
  textColor,
}: {
  step: string;
  index: number;
  isActive: boolean;
  isComplete: boolean;
  textColor: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -8 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ ...SPRING, delay: index * 0.06 }}
      className="flex items-center gap-2 text-xs font-mono"
    >
      <div className="flex-shrink-0 w-5 h-5 flex items-center justify-center">
        {isComplete ? (
          <CheckCircle className={`h-3.5 w-3.5 ${textColor}`} />
        ) : isActive ? (
          <Loader2 className={`h-3.5 w-3.5 animate-spin ${textColor}`} />
        ) : (
          <div className="h-1.5 w-1.5 rounded-full bg-white/20" />
        )}
      </div>
      <span
        className={
          isComplete
            ? 'text-white/60 line-through decoration-white/20'
            : isActive
              ? 'text-white/90'
              : 'text-white/30'
        }
      >
        {step}
      </span>
    </motion.div>
  );
}

/* ─── Provider connection status badge ─── */

function ConnectionBadge({
  provider,
  isConnected,
}: {
  provider: CloudProvider;
  isConnected: boolean;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <div
        className={`h-1.5 w-1.5 rounded-full ${
          isConnected ? 'bg-emerald-400 shadow-sm shadow-emerald-400/50' : 'bg-white/20'
        }`}
      />
      <span className={`text-[10px] font-mono ${isConnected ? provider.textColor : 'text-white/30'}`}>
        {isConnected ? 'connected' : 'standby'}
      </span>
    </div>
  );
}

/* ─── Typing effect for URL pasting ─── */

function useTypingEffect(text: string, isActive: boolean, speed: number = 20) {
  const [displayed, setDisplayed] = useState('');
  const [isDone, setIsDone] = useState(false);

  useEffect(() => {
    if (!isActive) {
      setDisplayed('');
      setIsDone(false);
      return;
    }
    let i = 0;
    setDisplayed('');
    setIsDone(false);
    const interval = setInterval(() => {
      i++;
      if (i > text.length) {
        clearInterval(interval);
        setIsDone(true);
        return;
      }
      setDisplayed(text.slice(0, i));
    }, speed);
    return () => clearInterval(interval);
  }, [text, isActive, speed]);

  return { displayed, isDone };
}

/* ─── Main InteractiveCloudDownload component ─── */

function InteractiveCloudDownload() {
  const [selectedProvider, setSelectedProvider] = useState<string | null>(null);
  const [phase, setPhase] = useState<DownloadPhase>('idle');
  const [progress, setProgress] = useState(0);
  const [imageBlur, setImageBlur] = useState(20);
  const [pipelineStep, setPipelineStep] = useState(0);
  const [showProtocol, setShowProtocol] = useState(false);
  const [completedDownloads, setCompletedDownloads] = useState<string[]>([]);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const callbackRef = useRef<(() => void) | null>(null);
  const pipelineTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const activeProvider = CLOUD_PROVIDERS.find((p) => p.id === selectedProvider);

  const typingActive = phase === 'pasting' && !!activeProvider;
  const { displayed: typedUrl, isDone: typingDone } = useTypingEffect(
    activeProvider?.url ?? '',
    typingActive,
    15
  );

  const cleanup = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    if (pipelineTimerRef.current) {
      clearInterval(pipelineTimerRef.current);
      pipelineTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    return cleanup;
  }, [cleanup]);

  // Typing done -> move to detecting
  useEffect(() => {
    if (typingDone && phase === 'pasting') {
      timerRef.current = setTimeout(() => {
        setPhase('detecting');
      }, 300);
    }
    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [typingDone, phase]);

  // Phase transition logic
  useEffect(() => {
    if (phase === 'detecting') {
      timerRef.current = setTimeout(() => {
        setPhase('negotiating');
        setPipelineStep(0);
      }, 900);
    } else if (phase === 'negotiating') {
      let step = 0;
      const totalSteps = activeProvider?.pipelineSteps.length ?? 5;
      pipelineTimerRef.current = setInterval(() => {
        step++;
        if (step >= totalSteps - 1) {
          if (pipelineTimerRef.current) {
            clearInterval(pipelineTimerRef.current);
            pipelineTimerRef.current = null;
          }
          callbackRef.current = () => {
            setPhase('downloading');
            setProgress(0);
          };
        }
        setPipelineStep(step);
      }, 400);
    } else if (phase === 'downloading') {
      intervalRef.current = setInterval(() => {
        setProgress((prev) => {
          if (prev >= 100) {
            if (intervalRef.current) {
              clearInterval(intervalRef.current);
              intervalRef.current = null;
            }
            callbackRef.current = () => setPhase('processing');
            return 100;
          }
          return prev + 2;
        });
      }, 40);
    } else if (phase === 'processing') {
      timerRef.current = setTimeout(() => {
        setImageBlur(20);
        let blurValue = 20;
        intervalRef.current = setInterval(() => {
          blurValue -= 2;
          if (blurValue <= 0) {
            blurValue = 0;
            if (intervalRef.current) {
              clearInterval(intervalRef.current);
              intervalRef.current = null;
            }
            callbackRef.current = () => setPhase('done');
          }
          setImageBlur(blurValue);
        }, 50);
      }, 0);
    } else if (phase === 'done' && activeProvider) {
      setCompletedDownloads((prev) => {
        if (prev.includes(activeProvider.id)) return prev;
        return [...prev, activeProvider.id];
      });
    }

    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
      if (pipelineTimerRef.current) {
        clearInterval(pipelineTimerRef.current);
        pipelineTimerRef.current = null;
      }
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [phase, activeProvider]);

  // Flush deferred callbacks stored in callbackRef
  useEffect(() => {
    if (callbackRef.current) {
      const cb = callbackRef.current;
      callbackRef.current = null;
      cb();
    }
  });

  const handleSelectProvider = useCallback(
    (providerId: string) => {
      cleanup();
      setSelectedProvider(providerId);
      setProgress(0);
      setImageBlur(20);
      setPipelineStep(0);
      setShowProtocol(false);
      timerRef.current = setTimeout(() => {
        setPhase('pasting');
      }, 50);
    },
    [cleanup]
  );

  const phaseIndex = ['idle', 'pasting', 'detecting', 'negotiating', 'downloading', 'processing', 'done'].indexOf(phase);

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl">
      {/* Header with phase indicator */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30">
            <CloudDrizzle className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-white">Cloud Image Download Pipeline</h3>
            <p className="text-xs text-white/40">Select a provider to simulate the full download pipeline</p>
          </div>
        </div>
        {phase !== 'idle' && (
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={SPRING}
            className="flex items-center gap-2 px-3 py-1.5 rounded-full border border-white/[0.08] bg-white/[0.03]"
          >
            {phase === 'done' ? (
              <CheckCircle className="h-3 w-3 text-emerald-400" />
            ) : (
              <Loader2 className="h-3 w-3 animate-spin text-white/50" />
            )}
            <span className="text-[10px] font-mono text-white/60 uppercase tracking-wider">
              {PHASE_LABELS[phase]}
            </span>
          </motion.div>
        )}
      </div>

      {/* Phase progress dots */}
      {phase !== 'idle' && (
        <motion.div
          initial={{ opacity: 0, y: -4 }}
          animate={{ opacity: 1, y: 0 }}
          transition={SPRING}
          className="flex items-center gap-1 mb-6"
        >
          {['pasting', 'detecting', 'negotiating', 'downloading', 'processing', 'done'].map((p, i) => {
            const thisIndex = i + 1;
            const isPhaseComplete = phaseIndex > thisIndex;
            const isCurrentPhase = phaseIndex === thisIndex;
            return (
              <div key={p} className="flex items-center gap-1">
                <div
                  className={`h-1.5 rounded-full transition-all duration-300 ${
                    isPhaseComplete
                      ? 'w-8 bg-emerald-500/60'
                      : isCurrentPhase
                        ? 'w-8 bg-white/40'
                        : 'w-4 bg-white/10'
                  }`}
                />
              </div>
            );
          })}
        </motion.div>
      )}

      {/* Provider cards - 2x3 grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-6">
        {CLOUD_PROVIDERS.map((provider) => {
          const isActive = selectedProvider === provider.id;
          const isCompleted = completedDownloads.includes(provider.id);
          return (
            <motion.button
              key={provider.id}
              type="button"
              onClick={() => handleSelectProvider(provider.id)}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              transition={SPRING}
              className={`relative rounded-xl border p-3 text-left transition-colors overflow-hidden ${
                isActive
                  ? `${provider.borderColor} bg-gradient-to-br ${provider.gradient}`
                  : 'border-white/[0.08] bg-white/[0.02] hover:border-white/[0.15]'
              }`}
            >
              {/* Subtle glow when active */}
              {isActive && (
                <div className={`absolute inset-0 ${provider.glowColor} shadow-lg opacity-30 pointer-events-none`} />
              )}

              <div className="relative">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <div
                      className={`flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br ${provider.gradient} ${provider.textColor}`}
                    >
                      {provider.icon}
                    </div>
                    <span className="text-xs font-semibold text-white">{provider.name}</span>
                  </div>
                  {isCompleted && !isActive && (
                    <CheckCircle className="h-3.5 w-3.5 text-emerald-400/60" />
                  )}
                </div>
                <p className="text-[10px] text-white/30 truncate font-mono">{provider.urlPattern}</p>
                <div className="mt-1.5">
                  <ConnectionBadge provider={provider} isConnected={isActive && phaseIndex >= 3} />
                </div>
              </div>

              {isActive && (
                <motion.div
                  layoutId="provider-active-ring"
                  className="absolute inset-0 rounded-xl border-2 border-white/20 pointer-events-none"
                  transition={SPRING}
                />
              )}
            </motion.button>
          );
        })}
      </div>

      {/* Main download area */}
      <AnimatePresence mode="wait">
        {activeProvider ? (
          <motion.div
            key={activeProvider.id}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={SPRING}
            className="space-y-4"
          >
            {/* Terminal window */}
            <div className="rounded-xl border border-white/[0.08] bg-black/50 overflow-hidden">
              {/* Title bar */}
              <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.02]">
                <div className="flex items-center gap-2">
                  <div className="flex gap-1.5">
                    <div className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
                    <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
                    <div className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
                  </div>
                  <span className="text-[10px] text-white/30 ml-2 font-mono">giil -- cloud image downloader</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <Wifi className={`h-3 w-3 ${phaseIndex >= 3 ? 'text-emerald-400' : 'text-white/20'}`} />
                  <Shield className={`h-3 w-3 ${phaseIndex >= 4 ? 'text-emerald-400' : 'text-white/20'}`} />
                </div>
              </div>

              {/* Terminal body */}
              <div className="p-4 font-mono text-xs space-y-2 min-h-[160px]">
                {/* Command line with typing effect */}
                <div className="flex items-start gap-2">
                  <span className="text-emerald-400 flex-shrink-0">$</span>
                  <div className="flex-1 break-all">
                    <span className="text-white/80">giil &quot;</span>
                    <span className={activeProvider.textColor}>
                      {phase === 'pasting' ? typedUrl : activeProvider.url}
                    </span>
                    {phase === 'pasting' && !typingDone && (
                      <motion.span
                        animate={{ opacity: [1, 0] }}
                        transition={{ duration: 0.6, repeat: Infinity }}
                        className="text-white/80"
                      >
                        |
                      </motion.span>
                    )}
                    <span className="text-white/80">&quot;</span>
                    {activeProvider.id === 'batch-album' && (
                      <span className="text-amber-400"> --all</span>
                    )}
                  </div>
                </div>

                {/* Phase: Detecting provider */}
                <AnimatePresence mode="wait">
                  {phase === 'detecting' && (
                    <motion.div
                      key="detecting"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      className="space-y-1.5 pl-4"
                    >
                      <div className="flex items-center gap-2 text-yellow-400/80">
                        <Loader2 className="h-3 w-3 animate-spin" />
                        <span>Detecting provider from URL pattern...</span>
                      </div>
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={{ delay: 0.3 }}
                        className="flex items-center gap-2"
                      >
                        <ArrowRight className="h-3 w-3 text-white/30" />
                        <span className="text-white/50">Pattern match:</span>
                        <span className={activeProvider.textColor}>{activeProvider.urlPattern}</span>
                      </motion.div>
                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={{ delay: 0.55 }}
                        className="flex items-center gap-2"
                      >
                        <CheckCircle className={`h-3 w-3 ${activeProvider.textColor}`} />
                        <span className="text-white/70">
                          Identified: <span className={activeProvider.textColor}>{activeProvider.name}</span>
                        </span>
                      </motion.div>
                    </motion.div>
                  )}

                  {/* Phase: API Negotiation */}
                  {phase === 'negotiating' && (
                    <motion.div
                      key="negotiating"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      exit={{ opacity: 0 }}
                      className="space-y-1.5 pl-4"
                    >
                      <div className="flex items-center gap-2 text-cyan-400/80">
                        <Lock className="h-3 w-3" />
                        <span>Negotiating with {activeProvider.protocol}...</span>
                      </div>
                      {activeProvider.pipelineSteps.map((step, i) => (
                        <PipelineStep
                          key={step}
                          step={step}
                          index={i}
                          isActive={pipelineStep === i}
                          isComplete={pipelineStep > i}
                          textColor={activeProvider.textColor}
                        />
                      ))}
                    </motion.div>
                  )}

                  {/* Phase: Downloading */}
                  {(phase === 'downloading' || phase === 'processing' || phase === 'done') && (
                    <motion.div
                      key="download-block"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      className="space-y-2 pl-4"
                    >
                      <div className="flex items-center gap-2 text-white/50">
                        <Unlock className="h-3 w-3 text-emerald-400" />
                        <span>Access granted - downloading {activeProvider.file.name}</span>
                      </div>

                      {/* Progress bar */}
                      <div className="relative h-2.5 w-full rounded-full bg-white/[0.06] overflow-hidden">
                        <motion.div
                          className={`absolute inset-y-0 left-0 rounded-full bg-gradient-to-r ${activeProvider.gradient}`}
                          style={{ width: `${Math.min(progress, 100)}%` }}
                        />
                        {phase === 'downloading' && (
                          <motion.div
                            className="absolute inset-y-0 w-20 bg-gradient-to-r from-transparent via-white/10 to-transparent"
                            animate={{ x: ['-80px', '400px'] }}
                            transition={{ duration: 1.2, repeat: Infinity, ease: 'linear' }}
                          />
                        )}
                      </div>

                      {/* Download stats */}
                      <div className="flex items-center justify-between text-[10px]">
                        <div className="flex items-center gap-3">
                          <span className="text-white/50">
                            {formatBytes(activeProvider.file.sizeBytes, progress)} / {activeProvider.file.size}
                          </span>
                          <span className="text-white/30">|</span>
                          <span className={activeProvider.textColor}>
                            {Math.min(progress, 100)}%
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          <Zap className="h-2.5 w-2.5 text-amber-400/60" />
                          <span className="text-white/40">
                            {phase === 'downloading'
                              ? formatSpeed(activeProvider.file.sizeBytes, progress)
                              : activeProvider.file.size}
                          </span>
                        </div>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* Success output */}
                <AnimatePresence>
                  {phase === 'done' && (
                    <motion.div
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={SPRING}
                      className="space-y-1.5 pl-4 pt-1"
                    >
                      <div className="flex items-center gap-2 text-emerald-400">
                        <CheckCircle className="h-3.5 w-3.5" />
                        <span>
                          {activeProvider.id === 'batch-album'
                            ? 'Saved 3 images to ./album_3imgs/'
                            : `Saved to ./${activeProvider.file.name}`}
                        </span>
                      </div>
                      <div className="text-white/30 text-[10px] pl-5">
                        {activeProvider.file.format} | {activeProvider.file.dimensions} | {activeProvider.file.size} | {activeProvider.file.colorDepth}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </div>

            {/* Protocol visualization panel */}
            <AnimatePresence>
              {phaseIndex >= 3 && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={SPRING}
                  className="overflow-hidden"
                >
                  <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
                    {/* Protocol header toggle */}
                    <button
                      type="button"
                      onClick={() => setShowProtocol((v) => !v)}
                      className="w-full flex items-center justify-between px-4 py-3 hover:bg-white/[0.02] transition-colors"
                    >
                      <div className="flex items-center gap-2 text-xs">
                        <Shield className={`h-3.5 w-3.5 ${activeProvider.textColor}`} />
                        <span className="text-white/70 font-medium">Protocol Analysis</span>
                        <span className="text-white/30 font-mono">({activeProvider.protocol})</span>
                      </div>
                      <motion.div
                        animate={{ rotate: showProtocol ? 90 : 0 }}
                        transition={SPRING}
                      >
                        <ArrowRight className="h-3 w-3 text-white/30" />
                      </motion.div>
                    </button>

                    <AnimatePresence>
                      {showProtocol && (
                        <motion.div
                          initial={{ opacity: 0, height: 0 }}
                          animate={{ opacity: 1, height: 'auto' }}
                          exit={{ opacity: 0, height: 0 }}
                          transition={SPRING}
                          className="overflow-hidden"
                        >
                          <div className="px-4 pb-4 space-y-3 border-t border-white/[0.06] pt-3">
                            {/* Bypass method */}
                            <div className="rounded-lg border border-white/[0.06] bg-black/30 p-3">
                              <div className="flex items-center gap-2 mb-2">
                                <Lock className="h-3 w-3 text-amber-400" />
                                <span className="text-[10px] font-mono text-amber-400 uppercase tracking-wider">
                                  Bypass Method
                                </span>
                              </div>
                              <p className="text-xs text-white/60">{activeProvider.bypassMethod}</p>
                            </div>

                            {/* Pipeline steps visual */}
                            <div className="rounded-lg border border-white/[0.06] bg-black/30 p-3">
                              <div className="flex items-center gap-2 mb-3">
                                <RefreshCw className="h-3 w-3 text-cyan-400" />
                                <span className="text-[10px] font-mono text-cyan-400 uppercase tracking-wider">
                                  Request Pipeline
                                </span>
                              </div>
                              <div className="space-y-2">
                                {activeProvider.pipelineSteps.map((step, i) => (
                                  <div key={step} className="flex items-center gap-2">
                                    <div
                                      className={`flex-shrink-0 w-4 h-4 rounded-full flex items-center justify-center text-[8px] font-bold ${
                                        phase === 'done'
                                          ? `bg-gradient-to-br ${activeProvider.gradient} text-white`
                                          : 'bg-white/[0.06] text-white/30'
                                      }`}
                                    >
                                      {i + 1}
                                    </div>
                                    <span className="text-[10px] text-white/50 font-mono">{step}</span>
                                    {i < activeProvider.pipelineSteps.length - 1 && (
                                      <ArrowRight className="h-2 w-2 text-white/15 flex-shrink-0 ml-auto" />
                                    )}
                                  </div>
                                ))}
                              </div>
                            </div>
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Image preview area */}
            <AnimatePresence>
              {(phase === 'processing' || phase === 'done') && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={SPRING}
                  className="overflow-hidden"
                >
                  <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 space-y-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2 text-sm text-white/60">
                        <FileImage className="h-4 w-4" />
                        <span>Image Preview</span>
                      </div>
                      {phase === 'done' && (
                        <motion.div
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          className="flex items-center gap-1.5 text-[10px] text-emerald-400/70 font-mono"
                        >
                          <Eye className="h-3 w-3" />
                          <span>Ready for AI analysis</span>
                        </motion.div>
                      )}
                    </div>

                    {/* Image preview with blur-to-sharp and UI shapes */}
                    <div
                      className="relative w-full h-52 rounded-lg overflow-hidden"
                      style={{ filter: `blur(${imageBlur}px)` }}
                    >
                      <div className={`absolute inset-0 bg-gradient-to-br ${activeProvider.imageGradient}`} />
                      <div className="absolute inset-0">
                        <div className="relative w-full h-full">
                          {/* Mock UI elements */}
                          <div className="absolute top-3 left-3 right-3 h-8 rounded-md bg-white/[0.08] flex items-center px-3 gap-2">
                            <div className="h-2 w-2 rounded-full bg-white/20" />
                            <div className="h-1.5 w-16 rounded bg-white/10" />
                            <div className="ml-auto flex gap-1">
                              <div className="h-1.5 w-6 rounded bg-white/10" />
                              <div className="h-1.5 w-6 rounded bg-white/10" />
                            </div>
                          </div>
                          <div className="absolute top-14 left-3 w-1/3 bottom-3 rounded-md bg-white/[0.05] p-2 space-y-1.5">
                            <div className="h-1.5 w-full rounded bg-white/10" />
                            <div className="h-1.5 w-3/4 rounded bg-white/10" />
                            <div className="h-1.5 w-5/6 rounded bg-white/10" />
                            <div className="h-1.5 w-2/3 rounded bg-white/10" />
                          </div>
                          <div className="absolute top-14 left-[38%] right-3 bottom-3 rounded-md bg-white/[0.04] flex items-center justify-center">
                            <div className="text-center">
                              <ImageIcon className="h-10 w-10 text-white/15 mx-auto" />
                              <div className="mt-2 h-1.5 w-20 rounded bg-white/10 mx-auto" />
                            </div>
                          </div>
                          {/* Bug indicator overlay */}
                          <div className="absolute top-16 right-8 w-12 h-12 rounded-lg border-2 border-red-400/30 bg-red-400/10 flex items-center justify-center">
                            <AlertCircle className="h-5 w-5 text-red-400/40" />
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* File metadata grid */}
                    <AnimatePresence>
                      {phase === 'done' && (
                        <motion.div
                          initial={{ opacity: 0, y: 8 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{ ...SPRING, delay: 0.1 }}
                          className="space-y-3"
                        >
                          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                            <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-2.5">
                              <p className="text-[10px] text-white/30 mb-0.5 uppercase tracking-wider">File</p>
                              <p className="text-[11px] font-mono text-white/80 truncate">
                                {activeProvider.file.name}
                              </p>
                            </div>
                            <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-2.5">
                              <p className="text-[10px] text-white/30 mb-0.5 uppercase tracking-wider">Size</p>
                              <p className="text-[11px] font-mono text-white/80">{activeProvider.file.size}</p>
                            </div>
                            <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-2.5">
                              <p className="text-[10px] text-white/30 mb-0.5 uppercase tracking-wider">Dimensions</p>
                              <p className="text-[11px] font-mono text-white/80">{activeProvider.file.dimensions}</p>
                            </div>
                            <div className="rounded-lg border border-white/[0.06] bg-white/[0.02] p-2.5">
                              <p className="text-[10px] text-white/30 mb-0.5 uppercase tracking-wider">Format</p>
                              <p className="text-[11px] font-mono text-white/80">
                                {activeProvider.file.format} / {activeProvider.file.colorDepth}
                              </p>
                            </div>
                          </div>

                          {/* giil command reference for this provider */}
                          <div className="rounded-lg border border-white/[0.06] bg-black/30 p-3">
                            <div className="flex items-center justify-between mb-2">
                              <div className="flex items-center gap-1.5">
                                <Terminal className="h-3 w-3 text-white/40" />
                                <span className="text-[10px] text-white/40 uppercase tracking-wider font-mono">
                                  Command Used
                                </span>
                              </div>
                              <Copy className="h-3 w-3 text-white/20" />
                            </div>
                            <code className={`text-xs ${activeProvider.textColor} break-all`}>
                              giil &quot;{activeProvider.url}&quot;
                              {activeProvider.id === 'batch-album' ? ' --all' : ''}
                            </code>
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Download gallery (completed items) */}
            {completedDownloads.length > 1 && phase === 'done' && (
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={SPRING}
                className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4"
              >
                <div className="flex items-center gap-2 mb-3 text-xs text-white/50">
                  <Layers className="h-3.5 w-3.5" />
                  <span>Downloaded Images ({completedDownloads.length})</span>
                </div>
                <div className="grid grid-cols-3 sm:grid-cols-6 gap-2">
                  {completedDownloads.map((id) => {
                    const p = CLOUD_PROVIDERS.find((prov) => prov.id === id);
                    if (!p) return null;
                    return (
                      <motion.div
                        key={id}
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={SPRING}
                        className={`relative h-14 rounded-lg overflow-hidden border ${
                          id === selectedProvider ? p.borderColor : 'border-white/[0.06]'
                        }`}
                      >
                        <div className={`absolute inset-0 bg-gradient-to-br ${p.imageGradient}`} />
                        <div className="absolute inset-0 flex items-center justify-center">
                          <ImageIcon className="h-4 w-4 text-white/25" />
                        </div>
                        <div className="absolute bottom-0 inset-x-0 bg-black/40 px-1.5 py-0.5">
                          <p className="text-[8px] text-white/60 truncate font-mono">
                            {p.file.name}
                          </p>
                        </div>
                      </motion.div>
                    );
                  })}
                </div>
              </motion.div>
            )}
          </motion.div>
        ) : (
          /* Empty state */
          <motion.div
            key="empty"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center py-10 space-y-3"
          >
            <div className="flex items-center justify-center gap-4 text-white/20">
              <Link className="h-5 w-5" />
              <ArrowRight className="h-4 w-4" />
              <Cloud className="h-6 w-6" />
              <ArrowRight className="h-4 w-4" />
              <Download className="h-5 w-5" />
              <ArrowRight className="h-4 w-4" />
              <ImageIcon className="h-5 w-5" />
            </div>
            <p className="text-white/30 text-sm">Select a cloud provider to see the full download pipeline</p>
            <p className="text-white/20 text-xs">URL paste &rarr; provider detection &rarr; API negotiation &rarr; download &rarr; preview</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
