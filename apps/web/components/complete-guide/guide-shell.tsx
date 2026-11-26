import { ArrowDown, ArrowRight, ArrowUp, ArrowUpRight } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { GUIDE_ISSUES_URL, GUIDE_SOURCE_BASE, type GuidePart } from "@/lib/guide-outlines";
import { FlywheelDial } from "./flywheel-dial";
import { PromptLibraryButton } from "./prompt-library";

// Server-rendered chrome shared by the two long-form guides: the editorial
// cover, the closing call to action, and the colophon.

function DialMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" className={className}>
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.75" />
      <circle cx="12" cy="12" r="3.5" stroke="currentColor" strokeWidth="1.75" />
      <circle cx="12" cy="3" r="2.6" fill="#FF5500" />
    </svg>
  );
}

// -----------------------------------------------------------------------------
// Hero
// -----------------------------------------------------------------------------
interface HeroLink {
  href: string;
  label: string;
}

interface GuideHeroProps {
  current: "core" | "complete";
  eyebrow: string;
  title: ReactNode;
  dek: ReactNode;
  primary: HeroLink;
  secondary: HeroLink;
  /** One quiet line under the buttons (e.g. a pointer to the other guide). */
  note?: ReactNode;
  stats: { value: string; label: string }[];
  contents: readonly GuidePart[];
  /** The page's PromptBlock count, shown on the prompt library button. */
  promptCount: number;
}

const GUIDE_LINKS = [
  { key: "core", href: "/core-flywheel", short: "Core", label: "Core guide" },
  { key: "complete", href: "/complete-guide", short: "Complete", label: "Complete guide" },
] as const;

export function GuideHero({
  current,
  eyebrow,
  title,
  dek,
  primary,
  secondary,
  note,
  stats,
  contents,
  promptCount,
}: GuideHeroProps) {
  return (
    <header className="relative isolate overflow-hidden border-b border-white/[0.06]">
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -left-[20%] -top-[22rem] h-[48rem] w-[64rem] bg-[radial-gradient(closest-side,rgba(255,85,0,0.14),transparent)]" />
        {/* Below lg the dial crowns the top right; its arc runs in the gap
            between the site bar and the eyebrow, clear of the text. */}
        <FlywheelDial
          id={`${current}-cover-sm`}
          arc={[234, 277]}
          nodes={false}
          className="absolute -right-[14.25rem] top-3 h-[36rem] w-[36rem] text-white/[0.07] sm:-right-[10rem] sm:top-0 sm:h-[44rem] sm:w-[44rem] lg:hidden"
        />
        <div className="absolute inset-x-0 bottom-0 h-48 bg-gradient-to-b from-transparent to-[#020408]" />
      </div>

      <div className="mx-auto max-w-[1320px] px-5 sm:px-8 lg:px-10">
        <div className="flex h-16 items-center justify-between gap-4 sm:h-20">
          <Link
            href="/"
            className="-ml-1 inline-flex min-h-11 items-center gap-2.5 whitespace-nowrap rounded-md px-1 text-[0.9375rem] font-semibold tracking-[-0.01em] text-zinc-100 transition-colors hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
          >
            <DialMark className="h-5 w-5 text-zinc-300" />
            Agent Flywheel
          </Link>
          <nav aria-label="Guides" className="-mr-2 flex items-center text-sm sm:mr-0 sm:gap-1">
            {GUIDE_LINKS.map((link) => {
              const active = link.key === current;
              return (
                <Link
                  key={link.key}
                  href={link.href}
                  aria-current={active ? "page" : undefined}
                  className={`inline-flex min-h-11 items-center whitespace-nowrap rounded-full px-2.5 font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70 sm:px-3 ${
                    active ? "text-white" : "text-zinc-400 hover:text-zinc-100"
                  }`}
                >
                  <span className="sm:hidden">{link.short}</span>
                  <span className="hidden sm:inline">{link.label}</span>
                </Link>
              );
            })}
          </nav>
        </div>

        <div className="grid gap-14 pb-16 pt-10 sm:pb-24 sm:pt-16 lg:grid-cols-[minmax(0,1fr)_20rem] lg:gap-16 lg:pb-24 lg:pt-12 xl:grid-cols-[minmax(0,1fr)_23rem] xl:gap-24">
          <div className="min-w-0">
            <p className="font-mono text-xs font-medium uppercase tracking-[0.24em] text-[#FF7A33]">
              {eyebrow}
            </p>
            <h1 className="mt-6 max-w-[12ch] font-serif text-[3.375rem] font-normal leading-[0.94] tracking-[-0.02em] text-white sm:text-[5.25rem] lg:text-[6.25rem] xl:text-[7.25rem]">
              {title}
            </h1>
            <p className="mt-7 max-w-[38rem] text-[1.125rem] leading-[1.65] text-zinc-300 sm:text-[1.3125rem]">
              {dek}
            </p>
            <div className="mt-9 flex flex-col gap-3 sm:flex-row sm:items-center">
              <a
                href={primary.href}
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#FF5500] px-6 text-[0.9375rem] font-semibold text-black transition-colors hover:bg-[#FF7A33] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-[#020408]"
              >
                {primary.label}
                <ArrowDown aria-hidden="true" className="h-4 w-4" />
              </a>
              <Link
                href={secondary.href}
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-white/15 px-6 text-[0.9375rem] font-semibold text-zinc-100 transition-colors hover:border-white/30 hover:bg-white/[0.04] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
              >
                {secondary.label}
                <ArrowRight aria-hidden="true" className="h-4 w-4" />
              </Link>
            </div>
            {note && <p className="mt-6 max-w-[40rem] text-[0.9375rem] leading-relaxed text-zinc-400">{note}</p>}

            <dl
              className={`mt-10 grid max-w-[40rem] gap-x-6 gap-y-6 border-t border-white/[0.08] pt-6 sm:flex sm:flex-wrap sm:gap-x-12 ${
                stats.length === 3 ? "grid-cols-3" : "grid-cols-2"
              }`}
            >
              {stats.map((stat) => (
                <div key={stat.label} className="flex flex-col">
                  <dt className="order-2 mt-1.5 font-mono text-xs font-medium uppercase tracking-[0.16em] text-zinc-400">
                    {stat.label}
                  </dt>
                  <dd className="order-1 font-serif text-[2rem] leading-none text-white sm:text-[2.375rem]">
                    {stat.value}
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          {/* From lg the dial frames the contents card like a watch face, and
              its momentum arc fills the space beside the stats. */}
          <div className="relative hidden self-start lg:block">
            <FlywheelDial
              id={`${current}-cover-lg`}
              arc={[100, 160]}
              className="pointer-events-none absolute left-1/2 top-1/2 h-[60rem] w-[60rem] -translate-x-1/2 -translate-y-1/2 text-white/[0.06] [mask-image:linear-gradient(to_bottom,transparent_4%,#000_19%)]"
            />
            <div className="relative rounded-2xl border border-white/[0.08] bg-[#05070B]/80 p-6 backdrop-blur-sm">
              <p className="font-mono text-xs font-medium uppercase tracking-[0.2em] text-zinc-400">
                In this guide
              </p>
              <ol role="list" className="mt-3 divide-y divide-white/[0.06]">
                {contents.map((item) => (
                  <li key={item.id}>
                    <a
                      href={`#${item.id}`}
                      className="group flex items-baseline gap-3 py-2.5 text-[0.9375rem] leading-snug text-zinc-300 transition-colors hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
                    >
                      <span className="w-6 shrink-0 font-mono text-xs tabular-nums text-zinc-500 group-hover:text-[#FF7A33]">
                        {item.number ? item.number.padStart(2, "0") : "··"}
                      </span>
                      {item.label}
                    </a>
                  </li>
                ))}
              </ol>
              <PromptLibraryButton
                count={promptCount}
                className="-mx-2 mt-3 flex w-[calc(100%+1rem)] items-center justify-between gap-3 rounded-xl border border-white/[0.08] bg-white/[0.025] px-3.5 py-3 text-left text-[0.9375rem] transition-colors hover:border-[#FF5500]/40 hover:bg-white/[0.05] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
              />
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}

// -----------------------------------------------------------------------------
// Closing call to action
// -----------------------------------------------------------------------------
interface GuideFooterCTAProps {
  eyebrow: string;
  title: ReactNode;
  body: ReactNode;
  primary: HeroLink;
  secondary: HeroLink;
}

export function GuideFooterCTA({ eyebrow, title, body, primary, secondary }: GuideFooterCTAProps) {
  return (
    <aside
      aria-labelledby="guide-next-step"
      className="relative isolate mt-24 overflow-hidden rounded-2xl border border-white/[0.09] bg-[#06080C] px-6 py-12 sm:mt-32 sm:px-12 sm:py-16"
    >
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -bottom-40 -right-24 h-[30rem] w-[40rem] bg-[radial-gradient(closest-side,rgba(255,85,0,0.16),transparent)]" />
        <FlywheelDial
          id="cta"
          arc={[188, 246]}
          className="absolute -bottom-[22rem] -right-[20rem] h-[40rem] w-[40rem] text-white/[0.07] sm:-right-[14rem]"
        />
      </div>
      <p className="font-mono text-xs font-medium uppercase tracking-[0.22em] text-[#FF7A33]">
        {eyebrow}
      </p>
      <h2
        id="guide-next-step"
        className="mt-4 max-w-[16ch] font-serif text-[2.5rem] font-normal leading-[1.02] tracking-[-0.015em] text-white sm:text-[3.5rem]"
      >
        {title}
      </h2>
      <p className="mt-5 max-w-[34rem] text-[1.0625rem] leading-[1.7] text-zinc-300 sm:text-[1.125rem]">
        {body}
      </p>
      <div className="mt-9 flex flex-col gap-3 sm:flex-row">
        <Link
          href={primary.href}
          className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#FF5500] px-6 text-[0.9375rem] font-semibold text-black transition-colors hover:bg-[#FF7A33] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-[#06080C]"
        >
          {primary.label}
          <ArrowRight aria-hidden="true" className="h-4 w-4" />
        </Link>
        <Link
          href={secondary.href}
          className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-white/15 px-6 text-[0.9375rem] font-semibold text-zinc-100 transition-colors hover:border-white/30 hover:bg-white/[0.04] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
        >
          {secondary.label}
        </Link>
      </div>
    </aside>
  );
}

// -----------------------------------------------------------------------------
// Colophon: when the guide was last checked, and where to correct it
// -----------------------------------------------------------------------------
const COLOPHON_LINK =
  "inline-flex min-h-11 items-center gap-1.5 rounded-md text-zinc-300 underline decoration-white/20 underline-offset-4 transition-colors hover:text-white hover:decoration-[#FF5500]/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70";

export function GuideColophon({ reviewedOn, sourcePath }: { reviewedOn: string; sourcePath: string }) {
  return (
    <footer className="mt-14 flex flex-col gap-4 border-t border-white/[0.07] pt-8 sm:mt-16 md:flex-row md:items-center md:justify-between md:gap-10">
      <p className="text-sm leading-relaxed text-zinc-400">
        <span className="font-mono text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">
          Colophon
        </span>
        <span aria-hidden="true" className="mx-2.5 text-zinc-600">
          /
        </span>
        Current as of {reviewedOn}. Corrections are welcome.
      </p>
      <ul role="list" className="-my-2 flex flex-wrap gap-x-6 text-sm font-medium">
        <li>
          <a href={`${GUIDE_SOURCE_BASE}/${sourcePath}`} className={COLOPHON_LINK}>
            View source
            <ArrowUpRight aria-hidden="true" className="h-3.5 w-3.5 text-zinc-500" />
          </a>
        </li>
        <li>
          <a href={GUIDE_ISSUES_URL} className={COLOPHON_LINK}>
            Report an issue
            <ArrowUpRight aria-hidden="true" className="h-3.5 w-3.5 text-zinc-500" />
          </a>
        </li>
        <li>
          <a href="#main-content" className={COLOPHON_LINK}>
            Back to top
            <ArrowUp aria-hidden="true" className="h-3.5 w-3.5 text-zinc-500" />
          </a>
        </li>
      </ul>
    </footer>
  );
}
