"use client";

import Link from "next/link";
import { useState, useCallback } from "react";
import {
  ArrowLeft,
  ArrowUpRight,
  Check,
  ChevronRight,
  Copy,
  Home,
  LayoutGrid,
  ShieldAlert,
  Sparkles,
  Terminal,
} from "lucide-react";
import { motion } from "@/components/motion";
import type { ToolCard, ToolId } from "./tool-data";
import { TOOLS } from "./tool-data";

function FloatingOrb({
  className,
  delay = 0,
}: {
  className: string;
  delay?: number;
}) {
  return (
    <motion.div
      className={`absolute rounded-full pointer-events-none ${className}`}
      animate={{
        y: [0, -20, 0],
        scale: [1, 1.05, 1],
      }}
      transition={{
        duration: 8,
        delay,
        repeat: Infinity,
        ease: "easeInOut",
      }}
    />
  );
}

function RelatedToolCard({ toolId }: { toolId: ToolId }) {
  const tool = TOOLS[toolId];
  if (!tool) return null;

  return (
    <Link href={`/learn/tools/${toolId}`}>
      <motion.div
        whileHover={{ y: -2, scale: 1.02 }}
        whileTap={{ scale: 0.98 }}
        className="group relative flex items-center gap-3 rounded-xl border border-white/[0.08] bg-white/[0.03] p-3 backdrop-blur-md transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.06]"
        style={{
          boxShadow: "0 4px 24px rgba(0,0,0,0.2)",
        }}
      >
        <div
          className={`absolute inset-0 rounded-xl bg-gradient-to-br ${tool.gradient} opacity-0 transition-opacity duration-300 group-hover:opacity-100`}
        />
        <div
          className={`relative flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${tool.gradient} border border-white/10`}
        >
          <div className="text-white/90">{tool.icon}</div>
        </div>
        <div className="relative min-w-0 flex-1">
          <div className="truncate font-medium text-sm text-white/90 group-hover:text-white transition-colors">
            {tool.title}
          </div>
        </div>
        <ChevronRight
          className="relative h-4 w-4 text-white/40 group-hover:text-white/70 transition-colors"
          aria-hidden="true"
        />
      </motion.div>
    </Link>
  );
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for older browsers
      const textarea = document.createElement("textarea");
      textarea.value = text;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [text]);

  return (
    <button
      onClick={handleCopy}
      className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1 rounded-md px-2 py-1 text-xs text-white/40 transition-colors hover:bg-white/10 hover:text-white/70"
      aria-label={copied ? "Copied!" : "Copy command"}
    >
      {copied ? (
        <>
          <Check className="h-3 w-3" aria-hidden="true" />
          <span>Copied!</span>
        </>
      ) : (
        <>
          <Copy className="h-3 w-3" aria-hidden="true" />
          <span>Copy</span>
        </>
      )}
    </button>
  );
}

interface ToolPageContentProps {
  tool: ToolCard;
}

export function ToolPageContent({ tool: doc }: ToolPageContentProps) {
  return (
    <div className="min-h-screen bg-black relative overflow-x-hidden">
      {/* Dramatic ambient background */}
      <div className="fixed inset-0 pointer-events-none">
        <FloatingOrb
          className="w-[700px] h-[700px] bg-primary/10 blur-[180px] -top-48 left-1/4"
          delay={0}
        />
        <FloatingOrb
          className="w-[500px] h-[500px] bg-violet-500/10 blur-[150px] top-1/3 -right-24"
          delay={2}
        />
        <FloatingOrb
          className="w-[400px] h-[400px] bg-emerald-500/8 blur-[120px] bottom-0 left-0"
          delay={4}
        />

        {/* Radial gradient overlay */}
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,_rgba(var(--primary-rgb),0.15),_transparent)]" />

        {/* Grid pattern */}
        <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:80px_80px]" />
      </div>

      <div className="relative mx-auto max-w-2xl px-6 py-10 md:px-12 md:py-16">
        {/* Navigation */}
        <motion.div
          className="mb-10 flex items-center justify-between"
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
        >
          <Link
            href="/learn"
            className="group flex items-center gap-2 text-white/50 transition-colors hover:text-white"
          >
            <ArrowLeft
              className="h-4 w-4 transition-transform group-hover:-translate-x-1"
              aria-hidden="true"
            />
            <span className="text-sm font-medium">Learning Hub</span>
          </Link>
          <Link
            href="/"
            className="group flex items-center gap-2 text-white/50 transition-colors hover:text-white"
          >
            <Home className="h-4 w-4" aria-hidden="true" />
            <span className="text-sm font-medium">Home</span>
          </Link>
        </motion.div>

        {/* Main Card */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="group relative"
        >
          {/* Glow effect behind card */}
          <div
            className="absolute -inset-4 rounded-3xl opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-60"
            style={{ background: doc.glowColor }}
          />

          <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.03] backdrop-blur-xl overflow-hidden">
            {/* Top gradient bar */}
            <div
              className={`h-1 w-full bg-gradient-to-r ${doc.gradient}`}
              style={{
                boxShadow: `0 0 30px ${doc.glowColor}`,
              }}
            />

            <div className="p-8 md:p-10">
              {/* Icon + Title */}
              <div className="relative mb-8 flex items-start gap-5">
                <motion.div
                  className={`relative flex h-20 w-20 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br ${doc.gradient} border border-white/10`}
                  initial={{ scale: 0.8, opacity: 0, rotate: -10 }}
                  animate={{ scale: 1, opacity: 1, rotate: 0 }}
                  transition={{ duration: 0.5, delay: 0.2, type: "spring" }}
                  style={{
                    boxShadow: `0 0 40px ${doc.glowColor}`,
                  }}
                >
                  {/* Shimmer effect */}
                  <div className="absolute inset-0 rounded-2xl overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full animate-[shimmer_3s_infinite]" />
                  </div>
                  <div className="text-white relative z-10">{doc.icon}</div>
                </motion.div>

                <div className="min-w-0 flex-1 pt-1">
                  <motion.h1
                    className="mb-2 font-mono text-3xl font-bold tracking-tight text-white md:text-4xl"
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: 0.5, delay: 0.3 }}
                  >
                    {doc.title}
                  </motion.h1>
                  <motion.p
                    className="text-lg text-white/60"
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: 0.5, delay: 0.4 }}
                  >
                    {doc.tagline}
                  </motion.p>
                </div>
              </div>

              {/* Primary CTA - Documentation Link */}
              <motion.div
                className="mb-8"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: 0.5 }}
              >
                <a
                  href={doc.docsUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group/btn relative flex w-full items-center justify-center gap-3 rounded-xl bg-white/10 border border-white/10 py-4 px-6 font-semibold text-white transition-all duration-300 hover:bg-white/15 hover:border-white/20 hover:shadow-lg"
                  style={{
                    boxShadow: `0 4px 30px rgba(0,0,0,0.3)`,
                  }}
                >
                  <Sparkles className="h-5 w-5 text-primary" aria-hidden="true" />
                  <span>View Full Documentation on {doc.docsLabel}</span>
                  <ArrowUpRight
                    className="h-5 w-5 transition-transform group-hover/btn:translate-x-1 group-hover/btn:-translate-y-1"
                    aria-hidden="true"
                  />
                </a>
              </motion.div>

              {/* Quick Command */}
              {doc.quickCommand && (
                <motion.div
                  className="mb-8"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5, delay: 0.6 }}
                >
                  <div className="flex items-center gap-2 mb-3">
                    <Terminal className="h-4 w-4 text-primary" aria-hidden="true" />
                    <span className="text-sm font-semibold text-white/70 uppercase tracking-wider">
                      Quick Start
                    </span>
                  </div>
                  <div className="relative group/cmd rounded-xl border border-white/[0.08] bg-black/40 backdrop-blur-sm overflow-hidden">
                    <div className="flex items-center gap-2 px-4 py-2 border-b border-white/[0.05]">
                      <div className="w-3 h-3 rounded-full bg-red-500/70" aria-hidden="true" />
                      <div className="w-3 h-3 rounded-full bg-yellow-500/70" aria-hidden="true" />
                      <div className="w-3 h-3 rounded-full bg-green-500/70" aria-hidden="true" />
                      <span className="ml-2 text-xs text-white/30">
                        terminal
                      </span>
                    </div>
                    <div className="p-4 font-mono text-sm pr-24">
                      <span className="text-emerald-400" aria-hidden="true">$</span>
                      <span className="text-white/90 ml-2">
                        {doc.quickCommand}
                      </span>
                    </div>
                    <CopyButton text={doc.quickCommand} />
                  </div>
                </motion.div>
              )}

              {doc.id === "dcg" && (
                <motion.div
                  className="mb-8"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5, delay: 0.65 }}
                >
                  <div className="flex items-center gap-2 mb-3">
                    <ShieldAlert className="h-4 w-4 text-primary" aria-hidden="true" />
                    <span className="text-sm font-semibold text-white/70 uppercase tracking-wider">
                      Uninstallation
                    </span>
                  </div>
                  <div className="rounded-xl border border-white/[0.08] bg-black/40 p-4 text-sm text-white/70">
                    <p className="mb-4">
                      Remove the hook only, or fully purge DCG from your system.
                      You can re-enable it anytime with{" "}
                      <code className="font-mono text-white/90 bg-white/5 px-1 rounded">dcg install</code>.
                    </p>
                    <pre className="rounded-lg border border-white/[0.08] bg-black/60 p-3 text-xs font-mono text-white/90 whitespace-pre overflow-x-auto">
{`# Remove hook only
dcg uninstall

# Full removal (hook + binary + config)
dcg uninstall --purge

# Verify removal
dcg doctor`}
                    </pre>
                  </div>
                </motion.div>
              )}

              {/* Related Tools */}
              {doc.relatedTools.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.5, delay: 0.7 }}
                >
                  <div className="flex items-center gap-2 mb-4">
                    <LayoutGrid className="h-4 w-4 text-primary" aria-hidden="true" />
                    <span className="text-sm font-semibold text-white/70 uppercase tracking-wider">
                      Related Tools
                    </span>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-2">
                    {doc.relatedTools.slice(0, 4).map((relatedId, index) => (
                      <motion.div
                        key={relatedId}
                        initial={{ opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.3, delay: 0.8 + index * 0.1 }}
                      >
                        <RelatedToolCard toolId={relatedId} />
                      </motion.div>
                    ))}
                  </div>
                </motion.div>
              )}
            </div>
          </div>
        </motion.div>

        {/* Footer Links */}
        <motion.div
          className="mt-10 flex flex-col items-center gap-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.5, delay: 1 }}
        >
          <Link
            href="/learn/commands"
            className="group flex items-center gap-2 text-white/50 transition-colors hover:text-primary"
          >
            <span className="text-sm">See all commands in the Command Reference</span>
            <ChevronRight
              className="h-4 w-4 transition-transform group-hover:translate-x-1"
              aria-hidden="true"
            />
          </Link>
        </motion.div>
      </div>

      {/* Custom shimmer animation */}
      <style jsx global>{`
        @keyframes shimmer {
          0% {
            transform: translateX(-100%);
          }
          100% {
            transform: translateX(100%);
          }
        }
      `}</style>
    </div>
  );
}
