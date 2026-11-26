import { ArrowDown, ArrowRight } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import type { GuideNavItem } from "./guide-components";

// Server-rendered chrome shared by the two long-form guides: the editorial
// cover, the closing call to action, and the flywheel dial motif.

// -----------------------------------------------------------------------------
// Flywheel dial: concentric rings, a tick-marked bezel and one live arc.
// -----------------------------------------------------------------------------
const DIAL_CENTER = 400;

function dialTicks(): string {
  const parts: string[] = [];
  for (let i = 0; i < 120; i++) {
    const angle = (i / 120) * Math.PI * 2;
    const inner = i % 10 === 0 ? 312 : 322;
    const outer = 334;
    const x1 = DIAL_CENTER + Math.cos(angle) * inner;
    const y1 = DIAL_CENTER + Math.sin(angle) * inner;
    const x2 = DIAL_CENTER + Math.cos(angle) * outer;
    const y2 = DIAL_CENTER + Math.sin(angle) * outer;
    parts.push(`M${x1.toFixed(1)} ${y1.toFixed(1)}L${x2.toFixed(1)} ${y2.toFixed(1)}`);
  }
  return parts.join("");
}

function arcPath(radius: number, fromDeg: number, toDeg: number): string {
  const point = (deg: number) => {
    const rad = (deg * Math.PI) / 180;
    return `${(DIAL_CENTER + Math.cos(rad) * radius).toFixed(1)} ${(DIAL_CENTER + Math.sin(rad) * radius).toFixed(1)}`;
  };
  const large = toDeg - fromDeg > 180 ? 1 : 0;
  return `M${point(fromDeg)}A${radius} ${radius} 0 ${large} 1 ${point(toDeg)}`;
}

const TICKS = dialTicks();
const ARC = arcPath(334, -100, -28);
const ARC_END = {
  x: DIAL_CENTER + Math.cos((-28 * Math.PI) / 180) * 334,
  y: DIAL_CENTER + Math.sin((-28 * Math.PI) / 180) * 334,
};

export function FlywheelDial({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 800 800" fill="none" aria-hidden="true" className={className}>
      <circle cx="400" cy="400" r="396" stroke="currentColor" strokeWidth="1" />
      <path d={TICKS} stroke="currentColor" strokeWidth="1.5" />
      <circle cx="400" cy="400" r="250" stroke="currentColor" strokeWidth="1" />
      <circle cx="400" cy="400" r="160" stroke="currentColor" strokeWidth="1" />
      <circle cx="400" cy="400" r="70" stroke="currentColor" strokeWidth="1" />
      <path d={ARC} stroke="#FF5500" strokeOpacity="0.75" strokeWidth="3" strokeLinecap="round" />
      <circle cx={ARC_END.x} cy={ARC_END.y} r="7" fill="#FF5500" />
      <circle cx="400" cy="150" r="5" fill="currentColor" />
      <circle cx="616.5" cy="525" r="5" fill="currentColor" />
      <circle cx="183.5" cy="525" r="5" fill="currentColor" />
    </svg>
  );
}

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
  contents: GuideNavItem[];
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
}: GuideHeroProps) {
  return (
    <header className="relative isolate overflow-hidden border-b border-white/[0.06]">
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -left-[20%] -top-[22rem] h-[48rem] w-[64rem] bg-[radial-gradient(closest-side,rgba(255,85,0,0.14),transparent)]" />
        <FlywheelDial className="absolute -right-[26rem] -top-[10rem] h-[60rem] w-[60rem] text-white/[0.06] sm:-right-[22rem] lg:-right-[16rem] lg:-top-[14rem] xl:-right-[5rem]" />
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

          <div className="hidden lg:block">
            <div className="rounded-2xl border border-white/[0.08] bg-[#05070B]/75 p-6 backdrop-blur-sm">
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
      className="relative isolate overflow-hidden rounded-2xl border border-white/[0.09] bg-[#06080C] px-6 py-12 sm:px-12 sm:py-16"
    >
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -bottom-40 -right-24 h-[30rem] w-[40rem] bg-[radial-gradient(closest-side,rgba(255,85,0,0.16),transparent)]" />
        <FlywheelDial className="absolute -bottom-[22rem] -right-[20rem] h-[40rem] w-[40rem] text-white/[0.07] sm:-right-[14rem]" />
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
