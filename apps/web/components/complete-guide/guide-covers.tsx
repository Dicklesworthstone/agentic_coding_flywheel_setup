"use client";

import { ArrowRight, BookOpen, Compass, type LucideIcon } from "lucide-react";
import Link from "next/link";
import { fadeUp, motion, staggerContainer } from "@/components/motion";
import { COMPLETE_GUIDE_PROMPT_COUNT } from "@/lib/complete-guide";
import {
  COMPLETE_GUIDE_EXHIBIT_COUNT,
  COMPLETE_GUIDE_OUTLINE,
  CORE_FLYWHEEL_EXHIBIT_COUNT,
  CORE_FLYWHEEL_OUTLINE,
  CORE_FLYWHEEL_PROMPT_COUNT,
  guidePartCount,
} from "@/lib/guide-outlines";

// The two long-form guides, as cards on the landing page. They use the landing
// page's own type and card style (mono section heading, theme tokens, primary
// accent), not the guides' editorial look. Every count is derived from the
// guide outlines (lib/guide-outlines.ts), which tests pin to the pages.

interface GuideCard {
  key: string;
  href: string;
  icon: LucideIcon;
  badge: string;
  title: string;
  dek: string;
  stats: { value: number; label: string }[];
  cta: string;
}

const GUIDES: GuideCard[] = [
  {
    key: "core",
    href: "/core-flywheel",
    icon: Compass,
    badge: "Start here",
    title: "The Core Flywheel",
    dek: "The three tools that carry most of the method (Agent Mail, beads and bv), explained from scratch and followed through a worked example.",
    stats: [
      { value: guidePartCount(CORE_FLYWHEEL_OUTLINE), label: "Parts" },
      { value: CORE_FLYWHEEL_EXHIBIT_COUNT, label: "Exhibits" },
      { value: CORE_FLYWHEEL_PROMPT_COUNT, label: "Prompts" },
    ],
    cta: "Start with the core loop",
  },
  {
    key: "complete",
    href: "/complete-guide",
    icon: BookOpen,
    badge: "The full method",
    title: "The Agentic Coding Flywheel",
    dek: "The whole method: refining a markdown plan across several models, turning it into beads, running a coordinated agent swarm, and reviewing and hardening what it builds.",
    stats: [
      { value: guidePartCount(COMPLETE_GUIDE_OUTLINE), label: "Parts" },
      { value: COMPLETE_GUIDE_EXHIBIT_COUNT, label: "Exhibits" },
      { value: COMPLETE_GUIDE_PROMPT_COUNT, label: "Prompts" },
    ],
    cta: "Read the complete guide",
  },
];

export function GuideCovers() {
  return (
    <section aria-labelledby="guides-heading" className="mx-auto max-w-7xl px-6 py-24">
      <div className="mb-12 text-center">
        <h2 id="guides-heading" className="mb-4 font-mono text-3xl font-bold tracking-tight">
          Learn the Method
        </h2>
        <p className="mx-auto max-w-2xl text-muted-foreground">
          Two long-form guides to planning-first agentic coding. Start with the core loop, then
          read the complete method.
        </p>
      </div>

      <motion.ul
        role="list"
        className="mx-auto grid max-w-5xl gap-6 lg:grid-cols-2"
        variants={staggerContainer}
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, margin: "-80px" }}
      >
        {GUIDES.map((guide) => (
          <motion.li key={guide.key} variants={fadeUp} className="flex">
            <GuideCardLink guide={guide} />
          </motion.li>
        ))}
      </motion.ul>
    </section>
  );
}

function GuideCardLink({ guide }: { guide: GuideCard }) {
  const titleId = `guide-card-${guide.key}`;
  const dekId = `${titleId}-dek`;
  const Icon = guide.icon;
  return (
    <Link
      href={guide.href}
      aria-labelledby={titleId}
      aria-describedby={dekId}
      className="group relative flex w-full flex-col overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition duration-300 hover:-translate-y-1 hover:border-primary/30 hover:shadow-[0_20px_40px_-12px_oklch(0.75_0.18_195/0.15)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary active:scale-[0.99] motion-reduce:hover:translate-y-0 sm:p-8"
    >
      {/* Glow on hover, as on the feature cards below. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-[oklch(0.75_0.18_195)] opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-25"
      />

      <div className="relative flex items-center gap-3">
        <span className="inline-flex rounded-xl bg-primary/10 p-3 text-primary">
          <Icon aria-hidden="true" className="h-6 w-6" />
        </span>
        <span className="rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-primary">
          {guide.badge}
        </span>
      </div>

      <h3 id={titleId} className="relative mt-6 text-2xl font-bold tracking-tight sm:text-3xl">
        {guide.title}
      </h3>
      <p id={dekId} className="relative mt-3 leading-relaxed text-muted-foreground">
        {guide.dek}
      </p>

      <dl className="relative mt-6 flex gap-8 border-t border-border/50 pt-6 sm:gap-10">
        {guide.stats.map((stat) => (
          <div key={stat.label} className="flex flex-col">
            <dt className="order-2 mt-1 text-xs uppercase tracking-widest text-muted-foreground">
              {stat.label}
            </dt>
            <dd className="order-1 font-mono text-2xl font-bold tabular-nums text-foreground">
              {stat.value}
            </dd>
          </div>
        ))}
      </dl>

      <span className="relative mt-auto flex items-center gap-2 pt-8 font-semibold text-primary">
        {guide.cta}
        <ArrowRight
          aria-hidden="true"
          className="h-4 w-4 transition-transform group-hover:translate-x-1"
        />
      </span>
    </Link>
  );
}
