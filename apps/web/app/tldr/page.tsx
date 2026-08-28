"use client";

import { useRef, useState, useCallback, useEffect } from "react";
import { Copy, Check } from "lucide-react";
import { motion, useReducedMotion, useInView } from "@/components/motion";
import { ErrorBoundary } from "@/components/ui/error-boundary";
import { TldrHero } from "@/components/tldr/tldr-hero";
import { TldrToolGrid } from "@/components/tldr/tldr-tool-grid";
import { TldrSynergyDiagram } from "@/components/tldr/tldr-synergy-diagram";
import { tldrFlywheelTools, tldrPageData } from "@/lib/tldr-content";
import { copyTextToClipboard } from "@/lib/utils";

// =============================================================================
// FLYWHEEL EXPLANATION SECTION
// =============================================================================

function FlywheelExplanation() {
  const containerRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(containerRef, { once: true, margin: "-50px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const { flywheelExplanation } = tldrPageData;

  return (
    <section
      ref={containerRef}
      className="relative overflow-hidden py-12 md:py-24"
    >
      {/* Background gradient */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent via-primary/5 to-transparent" />

      <div className="container relative mx-auto px-4 sm:px-6">
        <div className="grid items-center gap-8 lg:grid-cols-2 lg:gap-12">
          {/* Text content */}
          <motion.div
            initial={reducedMotion ? {} : { opacity: 0, x: -20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.5 }}
          >
            <h2 className="text-xl font-bold text-white sm:text-2xl md:text-3xl">
              {flywheelExplanation.title}
            </h2>
            <div className="mt-4 space-y-3 sm:mt-6 sm:space-y-4">
              {flywheelExplanation.paragraphs.map((paragraph, index) => (
                <motion.p
                  key={paragraph.slice(0, 50)}
                  initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
                  animate={isInView ? { opacity: 1, y: 0 } : {}}
                  transition={{
                    duration: reducedMotion ? 0 : 0.4,
                    delay: reducedMotion ? 0 : 0.1 + index * 0.1,
                  }}
                  className="text-sm leading-relaxed text-muted-foreground sm:text-base"
                >
                  {paragraph}
                </motion.p>
              ))}
            </div>
          </motion.div>

          {/* Synergy diagram */}
          <motion.div
            initial={reducedMotion ? {} : { opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.2 }}
            className="mx-auto max-w-sm lg:max-w-none"
          >
            <TldrSynergyDiagram tools={tldrFlywheelTools} />
          </motion.div>
        </div>
      </div>
    </section>
  );
}

// =============================================================================
// FOOTER CTA WITH COPY BUTTON
// =============================================================================

const INSTALL_COMMAND = `curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe`;

function FooterCTA({ id }: { id?: string }) {
  const [copied, setCopied] = useState(false);
  const copyResetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (copyResetTimerRef.current) {
        clearTimeout(copyResetTimerRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async () => {
    const copiedOk = await copyTextToClipboard(INSTALL_COMMAND);
    if (!copiedOk) {
      return;
    }
    setCopied(true);
    if (copyResetTimerRef.current) {
      clearTimeout(copyResetTimerRef.current);
    }
    copyResetTimerRef.current = setTimeout(() => {
      setCopied(false);
      copyResetTimerRef.current = null;
    }, 2000);
  }, []);

  return (
    <section id={id} className="border-t border-border/50 py-12 md:py-16">
      <div className="container mx-auto px-4 text-center">
        <h2 className="text-xl font-bold text-white sm:text-2xl md:text-3xl">
          Get Started
        </h2>
        <p className="mx-auto mt-4 max-w-xl text-sm text-muted-foreground sm:text-base">
          The fastest way to set up the entire flywheel ecosystem is with ACFS.
          One command, 30 minutes, and you&apos;re ready to go.
        </p>
        <div className="mt-6 flex flex-col items-center gap-4 md:mt-8">
          <div className="group relative w-full max-w-6xl">
            {/* The command scrolls inside its own box; the copy button sits
                outside that scroll region so it never overlaps the text or
                scrolls away on phones. */}
            <div className="flex items-center gap-2 rounded-xl bg-card/80 pr-2 ring-1 ring-border/50 transition duration-200 hover:ring-primary/30 sm:gap-3 sm:pr-3">
              <div
                className="min-w-0 flex-1 overflow-x-auto px-4 py-3 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring sm:px-6 sm:py-4"
                tabIndex={0}
                role="region"
                aria-label="Install command"
              >
                {/* No `block` class here: globals.css turns `code.block` into
                    its own scroll container, which would nest a second,
                    non-focusable scroller inside this region. */}
                <code className="whitespace-nowrap font-mono text-xs text-primary sm:text-sm md:text-base">
                  {INSTALL_COMMAND}
                </code>
              </div>
              <button
                type="button"
                onClick={handleCopy}
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-secondary text-muted-foreground transition duration-200 hover:bg-primary hover:text-white active:scale-95"
                aria-label={copied ? "Copied!" : "Copy install command"}
              >
                {copied ? (
                  <Check className="h-4 w-4 text-success sm:h-5 sm:w-5" />
                ) : (
                  <Copy className="h-4 w-4 sm:h-5 sm:w-5" />
                )}
              </button>
            </div>
            {copied && (
              <div className="absolute -top-10 left-1/2 -translate-x-1/2 rounded-lg bg-success px-3 py-1.5 text-xs font-medium text-white shadow-lg">
                Copied!
              </div>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            Or use the{" "}
            <a
              href="/wizard/os-selection"
              className="text-primary underline hover:text-primary/80"
            >
              step-by-step wizard
            </a>{" "}
            for guided setup.
          </p>
        </div>
      </div>
    </section>
  );
}

// =============================================================================
// MAIN PAGE COMPONENT
// =============================================================================

export default function TldrPage() {
  return (
    <ErrorBoundary>
      <main id="main-content" tabIndex={-1} className="min-h-screen overflow-x-hidden">
        {/* Hero Section */}
        <TldrHero id="tldr-hero" />

        {/* Flywheel Explanation with Diagram */}
        <ErrorBoundary>
          <FlywheelExplanation />
        </ErrorBoundary>

        {/* Tools Grid */}
        <section className="py-12 md:py-24">
          <div className="container mx-auto px-4 sm:px-6">
            <ErrorBoundary>
              <TldrToolGrid tools={tldrFlywheelTools} />
            </ErrorBoundary>
          </div>
        </section>

        {/* Footer CTA */}
        <FooterCTA id="get-started" />
      </main>
    </ErrorBoundary>
  );
}
