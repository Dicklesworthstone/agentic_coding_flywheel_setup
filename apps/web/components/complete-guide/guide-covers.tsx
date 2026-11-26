import { ArrowRight } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { instrumentSerifDeferred } from "@/app/fonts/instrument-serif";
import { COMPLETE_GUIDE_PROMPT_COUNT } from "@/lib/complete-guide";
import {
  COMPLETE_GUIDE_EXHIBIT_COUNT,
  COMPLETE_GUIDE_OUTLINE,
  CORE_FLYWHEEL_EXHIBIT_COUNT,
  CORE_FLYWHEEL_OUTLINE,
  CORE_FLYWHEEL_PROMPT_COUNT,
  guidePartCount,
} from "@/lib/guide-outlines";
import { FlywheelDial } from "./flywheel-dial";

// The two long-form guides, presented on the landing page as editorial
// covers in the guides' own type and dial motif. Every count is derived from
// the guide outlines (lib/guide-outlines.ts), which tests pin to the pages.

interface Cover {
  key: string;
  href: string;
  kicker: string;
  title: ReactNode;
  dek: string;
  stats: { value: number; label: string }[];
  cta: string;
  /** The corner dial's arc, from the sm breakpoint up. */
  arc: readonly [number, number];
  /** The phone dial's arc: only its crown, 253° to 287°, clears the card's edge. */
  horizon: readonly [number, number];
}

const COVERS: Cover[] = [
  {
    key: "core",
    href: "/core-flywheel",
    kicker: "Start here",
    title: (
      <>
        The Core <em className="italic text-[#FF5500]">Flywheel</em>
      </>
    ),
    dek: "Three tools, one loop, most of the value. Agent Mail, beads and bv, taught from first principles and walked through a worked example.",
    stats: [
      { value: guidePartCount(CORE_FLYWHEEL_OUTLINE), label: "Parts" },
      { value: CORE_FLYWHEEL_EXHIBIT_COUNT, label: "Visualizations" },
      { value: CORE_FLYWHEEL_PROMPT_COUNT, label: "Prompts" },
    ],
    cta: "Start with the core loop",
    arc: [192, 250],
    horizon: [228, 276],
  },
  {
    key: "complete",
    href: "/complete-guide",
    kicker: "The full method",
    title: (
      <>
        The Agentic Coding <em className="italic text-[#FF5500]">Flywheel</em>
      </>
    ),
    dek: "Exhaustive markdown plans, polished beads, coordinated agent swarms and relentless review: the complete methodology, end to end.",
    stats: [
      { value: guidePartCount(COMPLETE_GUIDE_OUTLINE), label: "Parts" },
      { value: COMPLETE_GUIDE_EXHIBIT_COUNT, label: "Visualizations" },
      { value: COMPLETE_GUIDE_PROMPT_COUNT, label: "Prompts" },
    ],
    cta: "Read the complete guide",
    arc: [206, 268],
    horizon: [234, 281],
  },
];

export function GuideCovers() {
  return (
    <section
      aria-labelledby="guides-heading"
      className={`${instrumentSerifDeferred.variable} relative py-20 sm:py-28`}
    >
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-10 flex flex-col gap-5 sm:mb-14 md:flex-row md:items-end md:justify-between md:gap-12">
          <div>
            <p className="font-mono text-xs font-medium uppercase tracking-[0.24em] text-[#FF5500]">
              The guides
            </p>
            <h2
              id="guides-heading"
              className="mt-4 font-serif text-[2.75rem] font-normal leading-[0.98] tracking-[-0.015em] text-foreground sm:text-[4rem]"
            >
              Learn the <em className="italic text-[#FF5500]">method</em>
            </h2>
          </div>
          <p className="max-w-[27rem] text-[1.0625rem] leading-relaxed text-muted-foreground">
            Two long-form guides to planning-first agentic coding. Start with the core loop,
            then go deeper into the full flywheel.
          </p>
        </div>

        <ul role="list" className="grid gap-5 lg:grid-cols-2 lg:gap-6">
          {COVERS.map((cover, index) => (
            <li key={cover.key} className="flex">
              <GuideCover cover={cover} index={index} />
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function GuideCover({ cover, index }: { cover: Cover; index: number }) {
  const titleId = `guide-cover-${cover.key}`;
  const dekId = `${titleId}-dek`;
  return (
    <Link
      href={cover.href}
      aria-labelledby={titleId}
      aria-describedby={dekId}
      className="group relative isolate flex w-full flex-col overflow-hidden rounded-[1.75rem] border border-white/[0.08] bg-[#06080C] p-7 pb-12 shadow-[0_30px_80px_-40px_rgba(0,0,0,0.9)] transition-colors duration-300 hover:border-white/[0.18] sm:p-10 lg:min-h-[36rem]"
    >
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -bottom-48 -right-40 h-[30rem] w-[34rem] bg-[radial-gradient(closest-side,rgba(255,85,0,0.16),transparent)] opacity-75 transition-opacity duration-500 group-hover:opacity-100" />
        {/* Phones: the stats run close to the card's foot, so the dial sinks
            below it and only its crown rises, a horizon under the call to action. */}
        <div className="absolute -bottom-[54rem] left-1/2 h-[60rem] w-[60rem] -translate-x-1/2 sm:hidden">
          <FlywheelDial
            id={`cover-${cover.key}-horizon`}
            arc={cover.horizon}
            nodes={false}
            outerRing={false}
            animated={false}
            className="h-full w-full text-white/[0.1]"
          />
        </div>
        {/* The wheel turns a little when the cover is hovered. */}
        <div className="absolute -bottom-[21rem] -right-[15rem] hidden h-[34rem] w-[34rem] transition-transform duration-[1400ms] ease-[cubic-bezier(0.16,1,0.3,1)] motion-safe:group-hover:rotate-[32deg] sm:block">
          <FlywheelDial
            id={`cover-${cover.key}`}
            arc={cover.arc}
            animated={false}
            className="h-full w-full text-white/[0.08]"
          />
        </div>
      </div>

      <p className="flex items-center gap-3 font-mono text-xs font-medium uppercase tracking-[0.22em] text-[#FF7A33]">
        <span className="tabular-nums">{String(index + 1).padStart(2, "0")}</span>
        <span aria-hidden="true" className="h-px w-8 bg-[#FF7A33]/50" />
        {cover.kicker}
      </p>

      <h3
        id={titleId}
        className="mt-7 max-w-[14ch] font-serif text-[2.75rem] font-normal leading-[0.98] tracking-[-0.015em] text-white sm:text-[3.5rem]"
      >
        {cover.title}
      </h3>
      <p id={dekId} className="mt-5 max-w-[30rem] text-[1.0625rem] leading-relaxed text-zinc-400">
        {cover.dek}
      </p>

      <dl className="mt-8 flex flex-wrap justify-between gap-x-4 gap-y-4 border-t border-white/[0.08] pt-6 sm:justify-start sm:gap-x-9">
        {cover.stats.map((stat) => (
          <div key={stat.label} className="flex flex-col">
            <dt className="order-2 mt-1.5 font-mono text-xs font-medium uppercase tracking-[0.1em] text-zinc-400 sm:tracking-[0.14em]">
              {stat.label}
            </dt>
            <dd className="order-1 font-serif text-[2.25rem] leading-none text-white">{stat.value}</dd>
          </div>
        ))}
      </dl>

      <span className="mt-auto flex items-center gap-4 pt-10 text-[0.9375rem] font-semibold text-white">
        <span
          aria-hidden="true"
          className="flex h-12 w-12 items-center justify-center rounded-full border border-white/15 transition-colors duration-300 group-hover:border-[#FF5500] group-hover:bg-[#FF5500] group-hover:text-black"
        >
          <ArrowRight className="h-5 w-5 transition-transform duration-300 group-hover:translate-x-0.5" />
        </span>
        {cover.cta}
      </span>
    </Link>
  );
}
