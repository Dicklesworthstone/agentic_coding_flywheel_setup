"use client";

import { useState, useCallback, ReactNode } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { HelpCircle, ChevronDown, Lightbulb, ArrowRight, Check, Download } from "lucide-react";
import { cn } from "@/lib/utils";
import { springs } from "@/components/motion";
import { Button } from "@/components/ui/button";

interface SimplerGuideProps {
  children: ReactNode;
  className?: string;
}

/**
 * "Make it simpler for me" collapsible section.
 * Provides beginner-friendly explanations with a friendly, approachable design.
 */
export function SimplerGuide({ children, className }: SimplerGuideProps) {
  const [isOpen, setIsOpen] = useState(false);

  const toggle = useCallback(() => setIsOpen((prev) => !prev), []);

  return (
    <div
      className={cn(
        "rounded-2xl border-2 border-dashed transition-all duration-300",
        isOpen
          ? "border-[oklch(0.7_0.15_280)] bg-[oklch(0.7_0.15_280/0.05)]"
          : "border-border/40 bg-muted/20 hover:border-[oklch(0.7_0.15_280/0.5)] hover:bg-[oklch(0.7_0.15_280/0.03)]",
        className
      )}
    >
      {/* Toggle button */}
      <button
        type="button"
        onClick={toggle}
        className="flex w-full items-center justify-between gap-3 p-4 text-left"
        aria-expanded={isOpen}
      >
        <div className="flex items-center gap-3">
          <div
            className={cn(
              "flex h-10 w-10 items-center justify-center rounded-full transition-colors",
              isOpen
                ? "bg-[oklch(0.7_0.15_280)] text-white"
                : "bg-[oklch(0.7_0.15_280/0.15)] text-[oklch(0.7_0.15_280)]"
            )}
          >
            <HelpCircle className="h-5 w-5" />
          </div>
          <div>
            <p
              className={cn(
                "font-semibold transition-colors",
                isOpen ? "text-[oklch(0.8_0.12_280)]" : "text-foreground"
              )}
            >
              Make it simpler for me
            </p>
            <p className="text-sm text-muted-foreground">
              {isOpen ? "Click to collapse" : "New to computers? Click for extra help"}
            </p>
          </div>
        </div>
        <motion.div
          animate={{ rotate: isOpen ? 180 : 0 }}
          transition={springs.snappy}
        >
          <ChevronDown
            className={cn(
              "h-5 w-5 transition-colors",
              isOpen ? "text-[oklch(0.7_0.15_280)]" : "text-muted-foreground"
            )}
          />
        </motion.div>
      </button>

      {/* Expandable content */}
      <AnimatePresence initial={false}>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={springs.smooth}
          >
            <div className="border-t-2 border-dashed border-[oklch(0.7_0.15_280/0.3)] px-4 pb-6 pt-4">
              {children}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/**
 * A section within the simpler guide with a title and optional icon.
 */
export function GuideSection({
  title,
  icon: Icon = Lightbulb,
  children,
  className,
}: {
  title: string;
  icon?: React.ElementType;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("space-y-3", className)}>
      <div className="flex items-center gap-2">
        <Icon className="h-5 w-5 text-[oklch(0.78_0.16_75)]" />
        <h3 className="font-semibold text-foreground">{title}</h3>
      </div>
      <div className="text-sm leading-relaxed text-muted-foreground">{children}</div>
    </div>
  );
}

/**
 * A numbered step within the guide.
 */
export function GuideStep({
  number,
  title,
  children,
  className,
}: {
  number: number;
  title: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex gap-4", className)}>
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[oklch(0.7_0.15_280)] text-sm font-bold text-white">
        {number}
      </div>
      <div className="flex-1 space-y-2 pt-1">
        <p className="font-medium text-foreground">{title}</p>
        <div className="text-sm leading-relaxed text-muted-foreground">{children}</div>
      </div>
    </div>
  );
}

/**
 * A checklist item showing what the user should see/do.
 */
export function GuideCheck({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex items-start gap-2", className)}>
      <Check className="mt-0.5 h-4 w-4 shrink-0 text-[oklch(0.72_0.19_145)]" />
      <span className="text-sm text-muted-foreground">{children}</span>
    </div>
  );
}

/**
 * A "what this means" explanation box.
 */
export function GuideExplain({
  term,
  children,
  className,
}: {
  term: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.08)] p-4",
        className
      )}
    >
      <p className="mb-2 font-medium text-[oklch(0.85_0.12_195)]">
        What is &quot;{term}&quot;?
      </p>
      <p className="text-sm leading-relaxed text-muted-foreground">{children}</p>
    </div>
  );
}

/**
 * An arrow pointing to the next action.
 */
export function GuideArrow({ children }: { children: ReactNode }) {
  return (
    <div className="flex items-center gap-2 rounded-lg bg-muted/50 px-3 py-2 text-sm">
      <ArrowRight className="h-4 w-4 text-primary" />
      <span className="font-medium text-foreground">{children}</span>
    </div>
  );
}

/**
 * Direct download button that immediately starts a download.
 * Used when we know the user's OS and can provide the correct installer.
 */
export function DirectDownloadButton({
  href,
  filename,
  label,
  sublabel,
  className,
}: {
  href: string;
  filename: string;
  label: string;
  sublabel?: string;
  className?: string;
}) {
  const handleClick = useCallback(() => {
    // Create a temporary link and trigger download
    const link = document.createElement("a");
    link.href = href;
    link.download = filename;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }, [href, filename]);

  return (
    <Button
      variant="default"
      size="lg"
      className={cn(
        "group h-auto flex-col gap-1 py-4",
        "bg-gradient-to-r from-[oklch(0.72_0.19_145)] to-[oklch(0.65_0.2_160)]",
        "hover:from-[oklch(0.68_0.2_145)] hover:to-[oklch(0.60_0.22_160)]",
        "shadow-lg shadow-[oklch(0.72_0.19_145/0.3)]",
        className
      )}
      onClick={handleClick}
    >
      <div className="flex items-center gap-2">
        <Download className="h-5 w-5" />
        <span className="text-base font-semibold">{label}</span>
      </div>
      {sublabel && (
        <span className="text-xs font-normal opacity-90">{sublabel}</span>
      )}
    </Button>
  );
}

/**
 * A warning/caution box for beginners.
 */
export function GuideCaution({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.08)] p-4",
        className
      )}
    >
      <p className="mb-2 flex items-center gap-2 font-medium text-[oklch(0.88_0.12_75)]">
        <span className="text-lg">⚠️</span> Important
      </p>
      <p className="text-sm leading-relaxed text-muted-foreground">{children}</p>
    </div>
  );
}

/**
 * A tip/hint box for beginners.
 */
export function GuideTip({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.08)] p-4",
        className
      )}
    >
      <p className="mb-2 flex items-center gap-2 font-medium text-[oklch(0.82_0.12_145)]">
        <span className="text-lg">💡</span> Tip
      </p>
      <p className="text-sm leading-relaxed text-muted-foreground">{children}</p>
    </div>
  );
}
