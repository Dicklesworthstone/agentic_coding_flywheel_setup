"use client";

import {
  AlertTriangle,
  ArrowUp,
  Check,
  ChevronDown,
  Copy,
  Info,
  Lightbulb,
  Link2,
  ListTree,
  SquareTerminal,
} from "lucide-react";
import {
  createContext,
  type MouseEvent as ReactMouseEvent,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";
import { BottomSheet } from "@/components/ui/bottom-sheet";
import {
  CodeBlock as SharedCodeBlock,
  type CodeBlockProps as SharedCodeBlockProps,
} from "@/components/ui/code-block";
import {
  COPY_FAILURE_MESSAGE,
  COPY_SUCCESS_MESSAGE,
  useCopyFeedback,
} from "@/lib/hooks/useCopyFeedback";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import { cn } from "@/lib/utils";

export { FlywheelDiagram } from "./flywheel-diagram";

// Shared type scale for the long-form guides. Body copy is 17px on phones and
// 18px from `sm`, at a measure of ~68 characters; figures, tables and prompt
// panels use the full article width.
const BODY_TEXT = "text-[1.0625rem] leading-[1.75] text-zinc-300 sm:text-[1.125rem]";
const MEASURE = "max-w-[68ch]";
const ACCENT = "#FF5500";

/** Stable, readable fragment ids for sub-headings ("planning-the-foundation-bundle"). */
export function guideSlug(text: string): string {
  return text
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72)
    .replace(/-+$/, "");
}

const PROMPT_HIGHLIGHT_PATTERN =
  /(\[[A-Z_]+\]|\b(?:Do we have|Search|Review|Read|Write|Fix|Create|Update|OK|Look|Execute)\b)/g;
const PROMPT_HIGHLIGHT_KEYWORDS = new Set([
  "Do we have",
  "Search",
  "Review",
  "Read",
  "Write",
  "Fix",
  "Create",
  "Update",
  "OK",
  "Look",
  "Execute",
]);

function renderHighlightedPrompt(text: string): ReactNode[] {
  return text.split(PROMPT_HIGHLIGHT_PATTERN).map((part, partIndex) => {
    if (/^\[[A-Z_]+\]$/.test(part)) {
      return (
        <span key={partIndex} className="rounded bg-white/10 px-1 font-medium text-zinc-100">
          {part}
        </span>
      );
    }

    if (PROMPT_HIGHLIGHT_KEYWORDS.has(part)) {
      return (
        <span key={partIndex} className="font-medium text-[#FF8A4C]">
          {part}
        </span>
      );
    }

    return part;
  });
}

// =============================================================================
// GUIDE SECTION
// =============================================================================
// Sub-headings read the enclosing section id so their fragment ids stay
// unique across the page (two sections may both have a "Why It Works").
const GuideSectionContext = createContext<string | null>(null);

interface GuideSectionProps {
  id: string;
  /** Part number ("1"…"12"); an empty string marks an unnumbered interlude. */
  number?: string;
  title: string;
  children: ReactNode;
}

export function GuideSection({ id, number, title, children }: GuideSectionProps) {
  const eyebrow = number ? `Part ${number.padStart(2, "0")}` : "Interlude";
  const headingId = `${id}-heading`;

  return (
    <section
      id={id}
      aria-labelledby={headingId}
      className="relative scroll-mt-[5.5rem] xl:scroll-mt-8"
    >
      <header className="mb-10 sm:mb-14">
        <div className="flex items-center gap-4 font-mono text-xs font-medium uppercase tracking-[0.22em]">
          <span className="text-[#FF7A33]">{eyebrow}</span>
          <span aria-hidden="true" className="h-px flex-1 bg-gradient-to-r from-white/15 to-transparent" />
        </div>
        <h2
          id={headingId}
          tabIndex={-1}
          className="mt-5 max-w-[22ch] font-serif text-[2.625rem] font-normal leading-[1.02] tracking-[-0.012em] text-white outline-none sm:text-[3.375rem] lg:text-[3.875rem]"
        >
          {title}
        </h2>
      </header>
      <GuideSectionContext.Provider value={id}>
        <div className="space-y-7 sm:space-y-8">{children}</div>
      </GuideSectionContext.Provider>
    </section>
  );
}

// =============================================================================
// SUBSECTION
// =============================================================================
export function SubSection({ title, children }: { title: string; children: ReactNode }) {
  const sectionId = useContext(GuideSectionContext);
  const slug = guideSlug(title);
  const id = sectionId ? `${sectionId}-${slug}` : slug;

  return (
    <div className="pt-8 first:pt-0 sm:pt-12 sm:first:pt-0">
      <div className="group/heading relative">
        <a
          href={`#${id}`}
          aria-label={`Link to this part: ${title}`}
          className="absolute -left-9 top-1 hidden h-8 w-8 items-center justify-center rounded-md text-zinc-500 opacity-0 transition-opacity hover:text-[#FF7A33] focus-visible:opacity-100 group-hover/heading:opacity-100 xl:flex"
        >
          <Link2 aria-hidden="true" className="h-4 w-4" />
        </a>
        <h3
          id={id}
          data-guide-subsection={title}
          className={cn(
            MEASURE,
            "scroll-mt-24 text-[1.375rem] font-semibold leading-[1.25] tracking-[-0.012em] text-white outline-none sm:text-[1.625rem] xl:scroll-mt-10",
          )}
        >
          {title}
        </h3>
      </div>
      <div className="mt-5 space-y-6 sm:mt-6 sm:space-y-7">{children}</div>
    </div>
  );
}

// =============================================================================
// PARAGRAPH
// =============================================================================
export function P({ children, highlight }: { children: ReactNode; highlight?: boolean }) {
  if (highlight) {
    return (
      <p className="max-w-[62ch] border-l-2 border-[#FF5500] pl-5 text-[1.1875rem] leading-[1.6] text-zinc-100 sm:pl-6 sm:text-[1.3125rem]">
        {children}
      </p>
    );
  }
  return <p className={cn(MEASURE, BODY_TEXT)}>{children}</p>;
}

// =============================================================================
// BLOCKQUOTE - Serif pull quote
// =============================================================================
export function BlockQuote({ children }: { children: ReactNode }) {
  return (
    <blockquote className="relative max-w-[56ch] py-2 pl-9 sm:pl-12">
      <span
        aria-hidden="true"
        className="absolute left-0 top-0 select-none font-serif text-[3.25rem] leading-none text-[#FF5500] sm:text-[4rem]"
      >
        &ldquo;
      </span>
      <div className="font-serif text-[1.5rem] italic leading-[1.32] tracking-[-0.005em] text-zinc-100 sm:text-[1.875rem]">
        {children}
      </div>
    </blockquote>
  );
}

// =============================================================================
// CODE BLOCK - Terminal panel, tuned to the guide palette
// =============================================================================
export function CodeBlock(props: Omit<SharedCodeBlockProps, "variant" | "copyable">) {
  return (
    <SharedCodeBlock
      {...props}
      variant="terminal"
      copyable
      className={cn(
        "rounded-xl border-white/[0.09] bg-[#07090D] shadow-none ring-0 hover:border-white/[0.16] hover:shadow-none",
        props.className,
      )}
    />
  );
}

export function IllustrativeDisclosure() {
  return (
    <p className="-mt-3 flex max-w-[72ch] items-start gap-2.5 text-sm leading-relaxed text-zinc-400">
      <Info aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-[#FFBD2E]" />
      <span>
        Illustrative simulation: scores, percentages, timings, and agent state in this exhibit
        explain the mechanism; they are not measured benchmarks or performance guarantees.
      </span>
    </p>
  );
}

// =============================================================================
// PROMPT BLOCK - Copy-ready prompt with run notes
// =============================================================================
// Prompts longer than this start collapsed; Copy always copies the full text.
const PROMPT_COLLAPSE_LINES = 14;
const PROMPT_COLLAPSE_CHARS = 1100;

export function PromptBlock({
  title,
  prompt,
  where,
  whyItWorks,
}: {
  title: string;
  prompt: string;
  /** Where and when to run it (tool, session, timing). */
  where?: string;
  whyItWorks?: string;
}) {
  const { state, copy } = useCopyFeedback();
  const figureRef = useRef<HTMLElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const bodyId = useId();
  const collapsible =
    prompt.split("\n").length > PROMPT_COLLAPSE_LINES || prompt.length > PROMPT_COLLAPSE_CHARS;
  const [expanded, setExpanded] = useState(false);
  const collapsed = collapsible && !expanded;

  const toggle = () => {
    if (expanded) {
      // Collapsing from the bottom of a long prompt would strand the reader
      // far below the panel; bring its top back into view first.
      const top = figureRef.current?.getBoundingClientRect().top ?? 0;
      if (top < 0) window.scrollBy({ top: top - 96 });
    }
    setExpanded(!expanded);
  };

  return (
    <figure
      ref={figureRef}
      className="overflow-hidden rounded-xl border border-white/[0.09] bg-[#07090D]"
    >
      {/* Toolbar: the title must stay the first <span> and the copy button
          its sibling (see e2e "prompt headers keep full titles"). */}
      <div className="flex items-start justify-between gap-3 border-b border-white/[0.07] bg-white/[0.025] py-1.5 pl-4 pr-1.5 sm:pl-5">
        <SquareTerminal aria-hidden="true" className="mt-[0.8rem] h-4 w-4 shrink-0 text-[#FF7A33]" />
        <span className="min-w-0 flex-1 break-words py-[0.6rem] text-[0.9375rem] font-semibold leading-snug text-zinc-100">
          {title}
        </span>
        <button
          type="button"
          onClick={() => void copy(prompt, { selectOnFailure: bodyRef.current })}
          aria-label={`Copy prompt: ${title}`}
          className="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center gap-2 rounded-lg px-3 text-sm font-medium text-zinc-300 transition-colors hover:bg-white/[0.07] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
        >
          {state === "copied" ? (
            <Check aria-hidden="true" className="h-4 w-4 text-[#FF7A33]" />
          ) : (
            <Copy aria-hidden="true" className="h-4 w-4" />
          )}
          <span className="hidden sm:inline">{state === "copied" ? "Copied" : "Copy"}</span>
        </button>
      </div>

      <p
        role="status"
        aria-live="polite"
        className={
          state === "failed"
            ? "border-b border-white/[0.07] px-4 py-2 text-sm font-medium text-red-300 sm:px-5"
            : "sr-only"
        }
      >
        {state === "copied" ? COPY_SUCCESS_MESSAGE : state === "failed" ? COPY_FAILURE_MESSAGE : ""}
      </p>

      <div className="relative">
        <div
          id={bodyId}
          ref={bodyRef}
          tabIndex={0}
          aria-label={`Prompt text: ${title}`}
          role="region"
          className={cn(
            "whitespace-pre-wrap break-words px-4 py-4 font-mono text-[0.875rem] leading-[1.75] text-zinc-300 outline-none selection:bg-[#FF5500]/25 selection:text-white focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#FF5500]/60 sm:px-5 sm:py-5 sm:text-[0.9rem]",
            collapsed && "max-h-[19rem] overflow-hidden",
          )}
        >
          {renderHighlightedPrompt(prompt)}
        </div>
        {collapsed && (
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-[#07090D] via-[#07090D]/85 to-transparent"
          />
        )}
      </div>

      {collapsible && (
        <button
          type="button"
          aria-expanded={expanded}
          aria-controls={bodyId}
          onClick={toggle}
          className="flex min-h-11 w-full items-center justify-center gap-2 border-t border-white/[0.07] text-sm font-medium text-zinc-300 transition-colors hover:bg-white/[0.03] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#FF5500]/60"
        >
          {expanded ? "Show less" : "Show full prompt"}
          <ChevronDown
            aria-hidden="true"
            className={cn("h-4 w-4 transition-transform", expanded && "rotate-180")}
          />
        </button>
      )}

      {(where || whyItWorks) && (
        <dl className="grid gap-x-6 gap-y-4 border-t border-white/[0.07] bg-black/25 px-4 py-4 sm:grid-cols-[7.5rem_minmax(0,1fr)] sm:gap-y-3 sm:px-5 sm:py-5">
          {where && (
            <>
              <dt className="font-mono text-xs font-medium uppercase tracking-[0.16em] text-zinc-400 sm:pt-[0.2rem]">
                Where &amp; when
              </dt>
              <dd className="-mt-3 text-[0.9375rem] leading-relaxed text-zinc-300 sm:mt-0">{where}</dd>
            </>
          )}
          {whyItWorks && (
            <>
              <dt className="font-mono text-xs font-medium uppercase tracking-[0.16em] text-[#FF7A33] sm:pt-[0.2rem]">
                Why it works
              </dt>
              <dd className="-mt-3 text-[0.9375rem] leading-relaxed text-zinc-300 sm:mt-0">
                {whyItWorks}
              </dd>
            </>
          )}
        </dl>
      )}
    </figure>
  );
}

// =============================================================================
// DATA TABLE - Real table on wide screens, labelled cards on phones
// =============================================================================
// Explicit ARIA roles keep table semantics when the phone layout switches
// the rows to display:block (Safari drops them otherwise).
export function DataTable({
  headers,
  rows,
}: {
  headers: string[];
  rows: (string | ReactNode)[][];
}) {
  const wide = headers.length >= 4;

  return (
    <div
      role="region"
      aria-label={`Table: ${headers.join(", ")}`}
      tabIndex={0}
      className="overflow-x-auto rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60 md:border md:border-white/[0.08] md:bg-white/[0.015]"
    >
      <table role="table" className={cn("w-full border-collapse text-left", wide && "md:min-w-[40rem]")}>
        <thead role="rowgroup" className="max-md:sr-only">
          <tr role="row" className="border-b border-white/[0.09] bg-white/[0.025]">
            {headers.map((header) => (
              <th
                key={header}
                role="columnheader"
                scope="col"
                className="whitespace-nowrap px-5 py-3.5 font-mono text-xs font-medium uppercase tracking-[0.14em] text-zinc-400"
              >
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody role="rowgroup" className="max-md:block max-md:space-y-3">
          {rows.map((row, rowIndex) => (
            <tr
              key={rowIndex}
              role="row"
              className="max-md:block max-md:rounded-xl max-md:border max-md:border-white/[0.08] max-md:bg-white/[0.02] max-md:px-4 max-md:py-3.5 md:border-b md:border-white/[0.06] md:last:border-b-0"
            >
              {row.map((cell, cellIndex) => (
                <td
                  key={cellIndex}
                  role="cell"
                  data-label={headers[cellIndex]}
                  className={cn(
                    "align-top text-[0.975rem] leading-relaxed max-md:block md:px-5 md:py-4",
                    cellIndex === 0
                      ? "font-semibold text-white max-md:text-[1.0625rem]"
                      : "text-zinc-300 max-md:mt-3 max-md:before:mb-1 max-md:before:block max-md:before:font-mono max-md:before:text-xs max-md:before:font-medium max-md:before:uppercase max-md:before:tracking-[0.14em] max-md:before:text-zinc-400 max-md:before:content-[attr(data-label)]",
                  )}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// =============================================================================
// TIP BOX - Left-rule callout
// =============================================================================
const TIP_VARIANTS = {
  tip: { label: "Tip", color: "#FFBD2E", Icon: Lightbulb },
  warning: { label: "Warning", color: "#FF6B61", Icon: AlertTriangle },
  info: { label: "Note", color: "#7DD3FC", Icon: Info },
} as const;

export function TipBox({
  children,
  variant = "tip",
}: {
  children: ReactNode;
  variant?: "tip" | "warning" | "info";
}) {
  const { label, color, Icon } = TIP_VARIANTS[variant];

  return (
    <div
      role="note"
      className="max-w-[72ch] rounded-r-xl border-l-2 bg-white/[0.03] px-5 py-4 sm:px-6 sm:py-5"
      style={{ borderColor: color }}
    >
      <p
        className="flex items-center gap-2 font-mono text-xs font-medium uppercase tracking-[0.18em]"
        style={{ color }}
      >
        <Icon aria-hidden="true" className="h-3.5 w-3.5" />
        {label}
      </p>
      <div className="mt-2 text-[1rem] leading-[1.7] text-zinc-300 sm:text-[1.0625rem]">
        {children}
      </div>
    </div>
  );
}

// =============================================================================
// HIGHLIGHT - Emphasized term
// =============================================================================
export function Hl({ children }: { children: ReactNode }) {
  return (
    <span className="font-medium text-white underline decoration-[#FF5500]/55 decoration-[1.5px] underline-offset-[0.22em]">
      {children}
    </span>
  );
}

// =============================================================================
// LISTS
// =============================================================================
export function BulletList({ items }: { items: (string | ReactNode)[] }) {
  return (
    <ul role="list" className={cn(MEASURE, "space-y-3")}>
      {items.map((item, i) => (
        <li key={i} className={cn(BODY_TEXT, "relative pl-6")}>
          <span
            aria-hidden="true"
            className="absolute left-[0.2rem] top-[0.72em] h-[5px] w-[5px] rotate-45 bg-[#FF5500]"
          />
          {item}
        </li>
      ))}
    </ul>
  );
}

export function NumberedList({ items }: { items: (string | ReactNode)[] }) {
  return (
    <ol role="list" className={cn(MEASURE, "space-y-4")}>
      {items.map((item, i) => (
        <li key={i} className="grid grid-cols-[2.25rem_minmax(0,1fr)] items-baseline">
          <span
            aria-hidden="true"
            className="select-none font-mono text-sm font-medium tabular-nums text-[#FF7A33]"
          >
            {String(i + 1).padStart(2, "0")}
          </span>
          <div className={BODY_TEXT}>{item}</div>
        </li>
      ))}
    </ol>
  );
}

// =============================================================================
// DIVIDER - Section break
// =============================================================================
export function Divider() {
  return (
    <div aria-hidden="true" className="my-20 flex items-center gap-5 sm:my-28">
      <span className="h-px flex-1 bg-gradient-to-r from-transparent to-white/[0.12]" />
      <svg viewBox="0 0 20 20" className="h-4 w-4 text-white/25">
        <circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" strokeWidth="1.25" />
        <circle cx="10" cy="2" r="2" fill={ACCENT} />
      </svg>
      <span className="h-px flex-1 bg-gradient-to-l from-transparent to-white/[0.12]" />
    </div>
  );
}

// =============================================================================
// STAT CARD - For metrics and numbers
// =============================================================================
export function StatCard({
  value,
  label,
  sublabel,
}: {
  value: string;
  label: string;
  sublabel?: string;
}) {
  return (
    <div className="rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 sm:p-5">
      <div className="font-serif text-[2.5rem] leading-none tracking-[-0.01em] text-white sm:text-[3rem]">
        {value}
      </div>
      <div className="mt-3 text-sm font-semibold text-zinc-100">{label}</div>
      {sublabel && <div className="mt-1 text-sm leading-snug text-zinc-400">{sublabel}</div>}
    </div>
  );
}

// =============================================================================
// GUIDE NAV - "On this page": sticky sidebar (lg+) / sticky section rail
// =============================================================================
// One <nav> and one set of section links for every breakpoint: the links are
// restyled, never duplicated, so assistive tech and tests see a single
// navigation. Phones add a "Contents" sheet with sub-headings and progress.
export interface GuideNavItem {
  id: string;
  label: string;
  number: string;
}

interface SubHeading {
  id: string;
  title: string;
}

const WORDS_PER_MINUTE = 230;

function formatMinutes(minutes: number): string {
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} h ${rest} min` : `${hours} h`;
}

function isPlainLeftClick(e: ReactMouseEvent<HTMLAnchorElement>) {
  return !(e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey);
}

export function GuideNav({ items, title }: { items: GuideNavItem[]; title: string }) {
  const [activeId, setActiveId] = useState("");
  const [activeSubId, setActiveSubId] = useState("");
  const [subheadings, setSubheadings] = useState<Record<string, SubHeading[]>>({});
  const [minutesLeft, setMinutesLeft] = useState<number | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const reducedMotion = useReducedMotion();
  const listRef = useRef<HTMLOListElement>(null);
  const progressRef = useRef(0);
  const bars = useRef(new Set<HTMLElement>());

  // Progress bars are painted directly (transform only) so scrolling never
  // re-renders the nav; the callback ref paints a newly mounted bar at once.
  // Their resting state is an arbitrary `[transform:scaleX(0)]`, not
  // `scale-x-0`: Tailwind 4 emits that as the separate `scale` property,
  // which would multiply with the inline transform and pin the bar at 0.
  const registerBar = useCallback((el: HTMLElement | null) => {
    if (!el) return;
    const set = bars.current;
    set.add(el);
    el.style.transform = `scaleX(${progressRef.current})`;
    return () => {
      set.delete(el);
    };
  }, []);

  useEffect(() => {
    const article = document.querySelector<HTMLElement>("[data-guide-article]");
    const sections = items
      .map((item) => document.getElementById(item.id))
      .filter((el): el is HTMLElement => el !== null);
    if (!article || sections.length === 0) return;

    const headings = Array.from(article.querySelectorAll<HTMLElement>("[data-guide-subsection]"));
    const headingSection = new Map<HTMLElement, string>();
    const bySection: Record<string, SubHeading[]> = {};
    for (const heading of headings) {
      const section = heading.closest<HTMLElement>("section[id]");
      if (!section) continue;
      headingSection.set(heading, section.id);
      (bySection[section.id] ??= []).push({
        id: heading.id,
        title: heading.dataset.guideSubsection ?? heading.textContent ?? "",
      });
    }
    const words = (article.textContent ?? "").split(/\s+/).length;

    let frame = 0;
    const update = () => {
      frame = 0;
      const viewport = window.innerHeight;
      const line = Math.min(viewport * 0.3, 220);

      let current = "";
      for (const section of sections) {
        if (section.getBoundingClientRect().top <= line) current = section.id;
        else break;
      }
      const atBottom =
        window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 4;
      if (atBottom) current = sections[sections.length - 1].id;

      let currentSub = "";
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top > line) break;
        currentSub = headingSection.get(heading) === current ? heading.id : "";
      }

      const rect = article.getBoundingClientRect();
      const travel = rect.height - viewport;
      const progress = travel > 0 ? Math.min(1, Math.max(0, -rect.top / travel)) : 0;
      progressRef.current = progress;
      for (const bar of bars.current) bar.style.transform = `scaleX(${progress})`;

      setActiveId(current);
      setActiveSubId(currentSub);
      setMinutesLeft(Math.max(0, Math.ceil((words * (1 - progress)) / WORDS_PER_MINUTE)));
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };

    frame = requestAnimationFrame(() => {
      setSubheadings(bySection);
      update();
    });
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule, { passive: true });
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  }, [items]);

  // Keep the current entry visible inside the list itself: sideways on the
  // phone rail, vertically in the desktop sidebar. Never scrolls the page.
  useEffect(() => {
    const list = listRef.current;
    if (!list || !activeId) return;
    const entry = list.querySelector<HTMLElement>(`[data-nav-id="${activeId}"]`);
    if (!entry) return;
    const behavior: ScrollBehavior = reducedMotion ? "auto" : "smooth";
    if (list.scrollWidth > list.clientWidth + 1) {
      const left = entry.offsetLeft - list.clientWidth / 2 + entry.offsetWidth / 2;
      list.scrollTo({ left: Math.max(0, left), behavior });
    } else if (list.scrollHeight > list.clientHeight + 1) {
      const top = entry.offsetTop;
      if (top < list.scrollTop + 24 || top + 48 > list.scrollTop + list.clientHeight) {
        list.scrollTo({ top: Math.max(0, top - 24), behavior });
      }
    }
  }, [activeId, activeSubId, reducedMotion]);

  const jumpTo = useCallback(
    (id: string) => {
      const target = document.getElementById(id);
      if (!target) return false;
      target.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth", block: "start" });
      window.history.pushState(null, "", `#${id}`);
      // Move keyboard focus with the reader, without a second scroll.
      const heading = target.matches("h2, h3") ? target : target.querySelector<HTMLElement>("h2");
      if (heading) {
        if (!heading.hasAttribute("tabindex")) heading.setAttribute("tabindex", "-1");
        heading.focus({ preventScroll: true });
      }
      return true;
    },
    [reducedMotion],
  );

  const onNavClick = (e: ReactMouseEvent<HTMLAnchorElement>, id: string) => {
    // Keep native new-tab/window behavior and respect an earlier handler.
    if (!isPlainLeftClick(e)) return;
    if (jumpTo(id)) e.preventDefault();
  };

  const onSheetClick = (e: ReactMouseEvent<HTMLAnchorElement>, id: string) => {
    if (!isPlainLeftClick(e)) return;
    e.preventDefault();
    setSheetOpen(false);
    // Let the sheet release its scroll lock before scrolling the page.
    requestAnimationFrame(() => requestAnimationFrame(() => jumpTo(id)));
  };

  const activeIndex = items.findIndex((item) => item.id === activeId);
  const activeItem = activeIndex >= 0 ? items[activeIndex] : null;
  const timeLeft = minutesLeft === null ? null : minutesLeft === 0 ? "Finished" : `≈ ${formatMinutes(minutesLeft)} left`;

  return (
    <>
      <nav
        aria-label="On this page"
        className="sticky top-0 z-30 -mx-5 border-b border-white/[0.07] bg-[#020408]/88 backdrop-blur-md backdrop-saturate-150 sm:-mx-8 xl:mx-0 xl:flex xl:h-dvh xl:flex-col xl:border-b-0 xl:bg-transparent xl:py-10 xl:backdrop-filter-none"
      >
        {/* Desktop header: guide title, progress and time left */}
        <div className="hidden xl:block xl:pb-5 xl:pl-3">
          <p className="font-mono text-xs font-medium uppercase tracking-[0.2em] text-zinc-400">
            {title}
          </p>
          <div className="relative mt-4 h-[2px] overflow-hidden rounded-full bg-white/10">
            <span
              ref={registerBar}
              className="absolute inset-0 origin-left bg-[#FF5500] [transform:scaleX(0)]"
            />
          </div>
          <p className="mt-2.5 min-h-[1.25rem] font-mono text-xs tabular-nums text-zinc-400">
            {timeLeft}
          </p>
        </div>

        <div className="flex items-center xl:min-h-0 xl:flex-1 xl:items-stretch">
          <ol
            ref={listRef}
            role="list"
            className="guide-rail-mask scrollbar-none relative flex min-w-0 flex-1 gap-1 overflow-x-auto px-4 py-2 sm:px-7 xl:block xl:h-full xl:space-y-0.5 xl:overflow-y-auto xl:overflow-x-hidden xl:px-0 xl:pb-10 xl:pt-1"
          >
            {items.map((item) => {
              const isActive = item.id === activeId;
              const subs = subheadings[item.id] ?? [];
              return (
                <li key={item.id} data-nav-id={item.id} className="shrink-0 xl:shrink">
                  <a
                    href={`#${item.id}`}
                    aria-current={isActive ? "location" : undefined}
                    onClick={(e) => onNavClick(e, item.id)}
                    className={cn(
                      "group/link relative inline-flex min-h-11 items-center gap-2 whitespace-nowrap rounded-full px-3 text-[0.8125rem] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70",
                      "xl:flex xl:min-h-0 xl:items-baseline xl:gap-3 xl:whitespace-normal xl:rounded-md xl:py-[0.45rem] xl:pl-3 xl:pr-2 xl:text-[0.875rem] xl:leading-snug",
                      isActive
                        ? "bg-white/[0.08] text-white xl:bg-white/[0.05]"
                        : "text-zinc-400 hover:bg-white/[0.04] hover:text-zinc-100",
                    )}
                  >
                    {isActive && (
                      <span
                        aria-hidden="true"
                        className="absolute inset-y-1.5 left-0 hidden w-[2px] rounded-full bg-[#FF5500] xl:block"
                      />
                    )}
                    <span
                      className={cn(
                        "font-mono text-xs tabular-nums",
                        isActive ? "text-[#FF7A33]" : "text-zinc-500 group-hover/link:text-zinc-400",
                      )}
                    >
                      {item.number ? item.number.padStart(2, "0") : "··"}
                    </span>
                    {item.label}
                  </a>
                  {isActive && subs.length > 0 && (
                    <ul role="list" className="mb-2 ml-[1.15rem] mt-1 hidden border-l border-white/10 xl:block">
                      {subs.map((sub) => {
                        const subActive = sub.id === activeSubId;
                        return (
                          <li key={sub.id}>
                            <a
                              href={`#${sub.id}`}
                              onClick={(e) => onNavClick(e, sub.id)}
                              data-active={subActive || undefined}
                              className={cn(
                                "-ml-px block border-l py-1.5 pl-4 pr-2 text-[0.8125rem] leading-snug transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70",
                                subActive
                                  ? "border-[#FF5500] text-zinc-100"
                                  : "border-transparent text-zinc-500 hover:text-zinc-200",
                              )}
                            >
                              {sub.title}
                            </a>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                </li>
              );
            })}
          </ol>

          <button
            type="button"
            onClick={() => setSheetOpen(true)}
            aria-label="Open contents"
            aria-haspopup="dialog"
            className="mr-2 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-zinc-300 transition-colors hover:bg-white/[0.06] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70 sm:mr-5 xl:hidden"
          >
            <ListTree aria-hidden="true" className="h-5 w-5" />
          </button>
        </div>

        <a
          href="#main-content"
          className="mt-4 hidden items-center gap-2 rounded-md py-2 pl-3 text-[0.8125rem] font-medium text-zinc-500 transition-colors hover:text-zinc-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70 xl:flex"
        >
          <ArrowUp aria-hidden="true" className="h-3.5 w-3.5" />
          Back to top
        </a>

        {/* Phone reading progress, along the bottom edge of the bar */}
        <div aria-hidden="true" className="absolute inset-x-0 -bottom-px h-[2px] xl:hidden">
          <span ref={registerBar} className="block h-full origin-left bg-[#FF5500] [transform:scaleX(0)]" />
        </div>
      </nav>

      <BottomSheet
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        title={`${title}: contents`}
        className="dark border-white/10 bg-[#090C12]"
      >
        <div className="pb-6 pr-12">
          <p className="font-mono text-xs font-medium uppercase tracking-[0.2em] text-zinc-400">
            {title}
          </p>
          <p className="mt-1 text-2xl font-semibold tracking-[-0.015em] text-white">Contents</p>
          <div className="relative mt-4 h-[2px] overflow-hidden rounded-full bg-white/10">
            <span ref={registerBar} className="absolute inset-0 origin-left bg-[#FF5500] [transform:scaleX(0)]" />
          </div>
          <p className="mt-2 font-mono text-xs tabular-nums text-zinc-400">
            {activeItem ? `Now reading: ${activeItem.label}` : "Not started"}
            {timeLeft ? ` · ${timeLeft}` : ""}
          </p>
        </div>
        <ol role="list" className="space-y-0.5 pb-8">
          {items.map((item) => {
            const isActive = item.id === activeId;
            const subs = subheadings[item.id] ?? [];
            return (
              <li key={item.id}>
                <a
                  href={`#${item.id}`}
                  onClick={(e) => onSheetClick(e, item.id)}
                  className={cn(
                    "flex min-h-12 items-baseline gap-3 rounded-lg px-3 py-3 text-base font-medium",
                    isActive ? "bg-white/[0.06] text-white" : "text-zinc-300",
                  )}
                >
                  <span className={cn("font-mono text-xs tabular-nums", isActive ? "text-[#FF7A33]" : "text-zinc-500")}>
                    {item.number ? item.number.padStart(2, "0") : "··"}
                  </span>
                  {item.label}
                </a>
                {isActive && subs.length > 0 && (
                  <ul role="list" className="mb-2 ml-6 border-l border-white/10">
                    {subs.map((sub) => (
                      <li key={sub.id}>
                        <a
                          href={`#${sub.id}`}
                          onClick={(e) => onSheetClick(e, sub.id)}
                          className={cn(
                            "-ml-px flex min-h-11 items-center border-l py-2 pl-4 pr-2 text-[0.9375rem] leading-snug",
                            sub.id === activeSubId
                              ? "border-[#FF5500] text-white"
                              : "border-transparent text-zinc-400",
                          )}
                        >
                          {sub.title}
                        </a>
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            );
          })}
        </ol>
      </BottomSheet>
    </>
  );
}

export * from "./agent-mail-viz";
export * from "./context-horizon-viz";
export * from "./convergence-viz";
export * from "./flywheel-diagram";
export * from "./plan-evolution-studio";
export * from "./plan-to-beads-viz";
export * from "./swarm-execution-viz";
