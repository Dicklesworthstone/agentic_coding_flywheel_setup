"use client";

import {
  AlertTriangle,
  ArrowRight,
  ArrowUp,
  ArrowUpRight,
  Check,
  ChevronDown,
  Copy,
  Info,
  Lightbulb,
  Link2,
  ListTree,
  SquareSlash,
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
  COPY_FAILURE_MESSAGE,
  COPY_SUCCESS_MESSAGE,
  useCopyFeedback,
} from "@/lib/hooks/useCopyFeedback";
import { type GuidePart, guideSlug } from "@/lib/guide-outlines";
import { type GuideSkill, skillUrl } from "@/lib/guide-skills";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import { cn } from "@/lib/utils";
import {
  collectGuidePrompts,
  type LibraryPrompt,
  OPEN_PROMPT_LIBRARY_EVENT,
  PromptLibrary,
} from "./prompt-library";

export { FlywheelDiagram } from "./flywheel-diagram";

// Shared type scale for the long-form guides. Body copy is 17px on phones and
// 18px from `sm`, at a measure of ~68 characters; figures, tables and prompt
// panels use the full article width.
const BODY_TEXT = "text-[1.0625rem] leading-[1.75] text-zinc-300 sm:text-[1.125rem]";
// One text column for prose, headings, tips and skill notes (about 68
// characters of body text a line); figures, prompts and tables use the full
// article width. `ch` is not used: Instrument Sans has wide digits, so 68ch
// came out near 86 characters of running text.
const MEASURE = "max-w-[40rem]";
// Boxed blocks (prompts, tips, tables, code) get more room than the gap
// between paragraphs, so a run of them does not read as one stack.
const BLOCK_SPACING = "my-9 first:mt-0 last:mb-0 sm:my-11";

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
// ARTICLE + OUTLINE
// =============================================================================
// The guide's outline (lib/guide-outlines.ts) is the single source for each
// part's number and title, and for whether a part has another after it.
const GuideOutlineContext = createContext<readonly GuidePart[]>([]);

export function GuideArticle({ outline, children }: { outline: readonly GuidePart[]; children: ReactNode }) {
  return (
    <GuideOutlineContext.Provider value={outline}>
      <article data-guide-article className="mx-auto min-w-0 max-w-[57rem] pt-14 sm:pt-20 xl:mx-0">
        {children}
      </article>
    </GuideOutlineContext.Provider>
  );
}

function isPlainLeftClick(e: ReactMouseEvent<HTMLElement>) {
  return !(e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey);
}

/**
 * Scroll to a part, sub-heading or prompt, record it in history, and move
 * keyboard focus with the reader (without a second scroll).
 */
function jumpToGuideTarget(id: string, smooth: boolean): boolean {
  const target = document.getElementById(id);
  if (!target) return false;
  target.scrollIntoView({ behavior: smooth ? "smooth" : "auto", block: "start" });
  window.history.pushState(null, "", `#${id}`);
  const focusTarget = target.matches("h2, h3")
    ? target
    : target.querySelector<HTMLElement>("h2, [data-prompt-text]");
  if (focusTarget) {
    if (!focusTarget.hasAttribute("tabindex")) focusTarget.setAttribute("tabindex", "-1");
    focusTarget.focus({ preventScroll: true });
  }
  if (target.hasAttribute("data-guide-prompt")) {
    // A brief outline shows which of several similar panels the jump landed on.
    target.removeAttribute("data-flash");
    void target.offsetWidth;
    target.setAttribute("data-flash", "");
    window.setTimeout(() => target.removeAttribute("data-flash"), 1600);
  }
  return true;
}

// =============================================================================
// GUIDE SECTION - Chapter opener, body, and the link on to the next part
// =============================================================================
// Sub-headings read the enclosing section id so their fragment ids stay
// unique across the page (two sections may both have a "Why It Works").
const GuideSectionContext = createContext<string | null>(null);

export function GuideSection({ id, children }: { id: string; children: ReactNode }) {
  const outline = useContext(GuideOutlineContext);
  const index = outline.findIndex((part) => part.id === id);
  if (index < 0) throw new Error(`[guide] "${id}" is not in this guide's outline`);
  const part = outline[index];
  const next = outline[index + 1];
  const totalParts = outline.filter((entry) => entry.number).length;
  const headingId = `${id}-heading`;
  const numeral = part.number.padStart(2, "0");

  return (
    <section id={id} aria-labelledby={headingId} className="relative scroll-mt-[5.5rem] xl:scroll-mt-8">
      <header className="mb-10 sm:mb-14">
        <div className="flex items-end gap-4 sm:gap-6">
          {part.number && (
            <span
              aria-hidden="true"
              className="guide-numeral -mb-[0.08em] select-none font-serif text-[4.75rem] leading-[0.8] tracking-[-0.04em] sm:text-[6.75rem] lg:text-[7.75rem]"
            >
              {numeral}
            </span>
          )}
          <div className="flex min-w-0 flex-1 items-center gap-4 pb-1 font-mono text-xs font-medium uppercase tracking-[0.22em] sm:pb-2">
            <span className="whitespace-nowrap text-[#FF7A33]">
              {part.number ? `Part ${part.number}` : "Interlude"}
              {part.number && <span className="text-zinc-500"> of {totalParts}</span>}
            </span>
            <span aria-hidden="true" className="h-px flex-1 bg-gradient-to-r from-white/15 to-transparent" />
          </div>
        </div>
        <h2
          id={headingId}
          tabIndex={-1}
          className="mt-5 max-w-[22ch] font-serif text-[2.625rem] font-normal leading-[1.02] tracking-[-0.012em] text-white outline-none sm:mt-7 sm:text-[3.375rem] lg:text-[3.875rem]"
        >
          {part.number ? <span className="sr-only">Part {part.number}: </span> : null}
          {part.title}
        </h2>
      </header>
      <GuideSectionContext.Provider value={id}>
        <div className="space-y-6 sm:space-y-7">{children}</div>
      </GuideSectionContext.Provider>

      {/* End of part. The next part's opener follows directly, so a quiet
          mark is enough; repeating its title here would say it twice. */}
      {next && (
        <div aria-hidden="true" className="my-20 flex items-center gap-5 sm:my-28">
          <span className="h-px flex-1 bg-gradient-to-r from-transparent to-white/[0.12]" />
          <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5 text-zinc-600">
            <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.5" />
            <circle cx="12" cy="12" r="3.5" stroke="currentColor" strokeWidth="1.5" />
            <circle cx="12" cy="3" r="2.4" fill="#FF5500" />
          </svg>
          <span className="h-px flex-1 bg-gradient-to-l from-transparent to-white/[0.12]" />
        </div>
      )}
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
    <div className="pt-10 first:pt-0 sm:pt-14 sm:first:pt-0">
      <div className="group/heading relative">
        <a
          href={`#${id}`}
          aria-label={`Link to this part: ${title}`}
          className="absolute -left-9 top-1.5 hidden h-8 w-8 items-center justify-center rounded-md text-zinc-500 opacity-0 transition-opacity hover:text-[#FF7A33] focus-visible:opacity-100 group-hover/heading:opacity-100 xl:flex sm:top-2.5"
        >
          <Link2 aria-hidden="true" className="h-4 w-4" />
        </a>
        {/* Serif, one step below the part title (and above exhibit titles,
            which are figures inside the subsection). */}
        <h3
          id={id}
          data-guide-subsection={title}
          className={cn(
            MEASURE,
            "scroll-mt-24 text-balance font-serif text-[1.875rem] font-normal leading-[1.08] tracking-[-0.01em] text-white outline-none sm:text-[2.375rem] xl:scroll-mt-10",
          )}
        >
          {title}
        </h3>
      </div>
      <div className="mt-5 space-y-5 sm:mt-6 sm:space-y-6">{children}</div>
    </div>
  );
}

// =============================================================================
// PARAGRAPH
// =============================================================================
export function P({ children, highlight }: { children: ReactNode; highlight?: boolean }) {
  if (highlight) {
    // A lead paragraph: larger and brighter, with no rule, so it never looks
    // like the left-ruled Tip and Warning callouts.
    return (
      <p className={cn(MEASURE, "text-[1.1875rem] leading-[1.6] text-zinc-100 sm:text-[1.375rem] sm:leading-[1.55]")}>
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
    <blockquote className={cn("relative max-w-[56ch] py-2 pl-9 sm:pl-12", BLOCK_SPACING)}>
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
// CODE BLOCK - Commands and code, in the same frame as the prompt panels
// =============================================================================
// On phones code and prompt panels run to the screen edges: the page gutter
// is px-5 below sm, and monospace text needs the width more than the frame.
const PHONE_BLEED = "max-sm:-mx-5 max-sm:rounded-none max-sm:border-x-0";

export function CodeBlock({
  code,
  language = "bash",
  filename,
  className,
}: {
  code: string;
  language?: string;
  filename?: string;
  className?: string;
}) {
  const { state, copy } = useCopyFeedback();
  const preRef = useRef<HTMLPreElement>(null);
  const text = code.trim();
  const label = filename ?? language;

  return (
    <figure
      data-guide-code
      className={cn(
        "overflow-hidden rounded-xl border border-white/[0.09] bg-[#07090D]",
        BLOCK_SPACING,
        PHONE_BLEED,
        className,
      )}
    >
      <div className="flex items-center justify-between gap-3 border-b border-white/[0.07] py-1 pl-4 pr-1.5 sm:pl-5">
        <span className="flex min-w-0 items-center gap-2.5 font-mono text-xs font-medium tracking-[0.06em] text-zinc-400">
          <SquareTerminal aria-hidden="true" className="h-4 w-4 shrink-0 text-[#FF7A33]" />
          <span className="truncate">{label}</span>
        </span>
        <button
          type="button"
          onClick={() => void copy(text, { selectOnFailure: preRef.current })}
          aria-label={state === "copied" ? "Copied!" : "Copy to clipboard"}
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
      {/* The focusable wrapper is the one scroll region; globals.css would
          otherwise make the <pre> scroll on its own as well. */}
      <div
        tabIndex={0}
        role="region"
        aria-label={`Code: ${label}`}
        className="overflow-x-auto px-4 py-4 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#FF5500]/60 sm:px-5"
      >
        <pre
          ref={preRef}
          className="overflow-visible font-mono text-[0.84rem] leading-[1.75] text-zinc-300 selection:bg-[#FF5500]/25 selection:text-white sm:text-[0.875rem]"
        >
          {text.split("\n").map((line, i) => (
            <code key={i} className="block min-h-[1lh] w-max">
              {line.startsWith("$") ? (
                <>
                  <span className="select-none font-semibold text-[#FF7A33]">$</span>
                  <span className="text-zinc-100">{line.slice(1)}</span>
                </>
              ) : line.startsWith("#") ? (
                <span className="italic text-zinc-500">{line}</span>
              ) : (
                line
              )}
            </code>
          ))}
        </pre>
      </div>
    </figure>
  );
}

export function IllustrativeDisclosure() {
  return (
    // A caption for the exhibit above it: globals.css pulls that exhibit's
    // bottom margin in, and the margin here keeps the next paragraph away.
    <p
      data-guide-disclosure
      className={cn(MEASURE, "mb-10 flex items-start gap-2.5 text-sm leading-relaxed text-zinc-400 sm:mb-12")}
    >
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
      id={`prompt-${guideSlug(title)}`}
      data-guide-prompt={title}
      className={cn(
        "guide-prompt scroll-mt-24 overflow-hidden rounded-xl border border-white/[0.09] bg-[#07090D] xl:scroll-mt-10",
        BLOCK_SPACING,
        PHONE_BLEED,
      )}
    >
      {/* Toolbar: the title must stay the first <span> and the copy button
          its sibling (see e2e "prompt headers keep full titles"). */}
      <div className="flex items-start justify-between gap-3 border-b border-white/[0.07] py-1.5 pl-4 pr-1.5 sm:pl-5">
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
          data-prompt-text
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
        <dl className="grid gap-x-6 gap-y-4 border-t border-white/[0.07] bg-white/[0.015] px-4 py-4 sm:grid-cols-[7.5rem_minmax(0,1fr)] sm:gap-y-3 sm:px-5 sm:py-5">
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
const SHORT_CELL_CHARS = 26;
// A small grid of short values (counts, flags) stays a real table on phones:
// as cards it would turn three rows into a screen and a half.
const COMPACT_TABLE_COLUMNS = 4;
const COMPACT_CELL_CHARS = 14;

export function DataTable({
  headers,
  rows,
}: {
  headers: string[];
  rows: (string | ReactNode)[][];
}) {
  const compact =
    headers.length <= COMPACT_TABLE_COLUMNS &&
    headers.every((header) => header.length <= COMPACT_CELL_CHARS + 6) &&
    rows.every((row) =>
      row.every((cell) => typeof cell === "string" && cell.length <= COMPACT_CELL_CHARS),
    );
  if (compact) return <CompactTable headers={headers} rows={rows as string[][]} />;

  const wide = headers.length >= 4;
  // On phones a column of short values (commands, counts) sits on its
  // label's line; a column with any longer text goes underneath, so every
  // card in the table has the same shape.
  const inlineColumns = headers.map((_, column) =>
    rows.every((row) => {
      const cell = row[column];
      return typeof cell === "string" && cell.length <= SHORT_CELL_CHARS;
    }),
  );

  return (
    <div
      role="region"
      aria-label={`Table: ${headers.join(", ")}`}
      tabIndex={0}
      className={cn(
        "overflow-x-auto rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60 md:border md:border-white/[0.08] md:bg-white/[0.015]",
        BLOCK_SPACING,
      )}
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
              {row.map((cell, cellIndex) => {
                const inline = inlineColumns[cellIndex];
                return (
                  <td
                    key={cellIndex}
                    role="cell"
                    data-label={headers[cellIndex]}
                    className={cn(
                      "align-top text-[0.975rem] leading-relaxed max-md:block md:px-5 md:py-4",
                      cellIndex === 0
                        ? "font-semibold text-white max-md:text-[1.0625rem]"
                        : "text-zinc-300 max-md:before:font-mono max-md:before:text-xs max-md:before:font-medium max-md:before:uppercase max-md:before:tracking-[0.14em] max-md:before:text-zinc-400 max-md:before:content-[attr(data-label)]",
                      cellIndex > 0 &&
                        (inline
                          ? "max-md:mt-2 max-md:flex max-md:items-baseline max-md:gap-3 max-md:before:w-[6.5rem] max-md:before:shrink-0"
                          : "max-md:mt-3 max-md:before:mb-1 max-md:before:block"),
                    )}
                  >
                    {cell}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CompactTable({ headers, rows }: { headers: string[]; rows: string[][] }) {
  return (
    <div
      role="region"
      aria-label={`Table: ${headers.join(", ")}`}
      tabIndex={0}
      className={cn(
        "overflow-x-auto rounded-xl border border-white/[0.08] bg-white/[0.015] outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60",
        BLOCK_SPACING,
      )}
    >
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="border-b border-white/[0.09] bg-white/[0.025]">
            {headers.map((header) => (
              <th
                key={header}
                scope="col"
                className="px-3 py-3 font-mono text-xs font-medium uppercase tracking-[0.12em] text-zinc-400 sm:px-5 sm:py-3.5 sm:tracking-[0.14em]"
              >
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, rowIndex) => (
            <tr key={rowIndex} className="border-b border-white/[0.06] last:border-b-0">
              {row.map((cell, cellIndex) =>
                cellIndex === 0 ? (
                  <th
                    key={cellIndex}
                    scope="row"
                    className="whitespace-nowrap px-3 py-2.5 text-[0.9375rem] font-semibold text-white sm:px-5 sm:py-3.5"
                  >
                    {cell}
                  </th>
                ) : (
                  <td
                    key={cellIndex}
                    className="px-3 py-2.5 text-[0.9375rem] tabular-nums text-zinc-300 sm:px-5 sm:py-3.5"
                  >
                    {cell}
                  </td>
                ),
              )}
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
  info: { label: "Note", color: "#A1A1AA", Icon: Info },
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
      className={cn(MEASURE, BLOCK_SPACING, "rounded-r-xl border-l-2 bg-white/[0.03] px-5 py-4 sm:px-6 sm:py-5")}
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
// SKILL NOTE - The jeffreys-skills.md skill that packages the step at hand
// =============================================================================
export function SkillNote({
  skills,
  children,
}: {
  skills: readonly GuideSkill[];
  /** Why the skill helps at this step; name each skill when there are several. */
  children: ReactNode;
}) {
  const label = skills.length > 1 ? "Skills for this step" : "Skill for this step";

  return (
    // Unboxed: a hairline and a mono label mark it as an aside, so it never
    // reads as one more panel in a run of prompt blocks.
    <div
      role="note"
      aria-label={label}
      className={cn(MEASURE, "border-t border-white/[0.09] pt-4 sm:pt-5")}
    >
      {/* Label left, source right; on a narrow column the source drops beneath. */}
      <p className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 font-mono text-xs font-medium">
        <span className="flex items-center gap-2 uppercase tracking-[0.18em] text-[#FF7A33]">
          <SquareSlash aria-hidden="true" className="h-3.5 w-3.5" />
          {label}
        </span>
        <span className="tracking-[0.02em] text-zinc-400">jeffreys-skills.md</span>
      </p>
      <ul role="list" className="mt-3 flex flex-wrap gap-2">
        {skills.map((skill) => (
          <li key={skill} className="min-w-0 max-w-full">
            <a
              href={skillUrl(skill)}
              target="_blank"
              rel="noopener noreferrer"
              className="group/skill inline-flex min-h-8 max-w-full items-center gap-1.5 rounded-md border border-white/[0.12] bg-black/30 px-2.5 py-1 font-mono text-[0.875rem] leading-snug text-white transition-colors hover:border-[#FF5500]/60 hover:text-[#FFBD2E] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#FF5500]"
            >
              <span className="min-w-0 [overflow-wrap:anywhere]">/{skill}</span>
              <ArrowUpRight
                aria-hidden="true"
                className="h-3.5 w-3.5 shrink-0 text-zinc-400 transition-colors group-hover/skill:text-[#FFBD2E]"
              />
              <span className="sr-only"> (opens in a new tab)</span>
            </a>
          </li>
        ))}
      </ul>
      <div className="mt-3 text-[0.96875rem] leading-[1.7] text-zinc-400 sm:text-[1rem]">
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
// GUIDE NAV - "On this page": sticky sidebar (xl+) / sticky section rail
// =============================================================================
// One <nav> and one set of section links for every breakpoint: the links are
// restyled, never duplicated, so assistive tech and tests see a single
// navigation. Phones add a "Contents" sheet with sub-headings and progress;
// every width can open the prompt library.
export type GuideNavItem = GuidePart;

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

export function GuideNav({
  items,
  title,
  promptCount,
}: {
  items: readonly GuidePart[];
  title: string;
  /** Shown on the prompt library buttons (the page's PromptBlock count). */
  promptCount: number;
}) {
  const [activeId, setActiveId] = useState("");
  const [activeSubId, setActiveSubId] = useState("");
  const [subheadings, setSubheadings] = useState<Record<string, SubHeading[]>>({});
  const [minutesLeft, setMinutesLeft] = useState<number | null>(null);
  const [percent, setPercent] = useState(0);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [libraryPrompts, setLibraryPrompts] = useState<LibraryPrompt[]>([]);
  const reducedMotion = useReducedMotion();
  const listRef = useRef<HTMLOListElement>(null);
  const progressRef = useRef(0);
  const bars = useRef(new Set<HTMLElement>());
  const rings = useRef(new Set<SVGCircleElement>());

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

  // The desktop progress dial: a circle drawn with pathLength=1, so the
  // remaining fraction is exactly its dash offset.
  const registerRing = useCallback((el: SVGCircleElement | null) => {
    if (!el) return;
    const set = rings.current;
    set.add(el);
    el.style.strokeDashoffset = String(1 - progressRef.current);
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
      for (const ring of rings.current) ring.style.strokeDashoffset = String(1 - progress);

      setActiveId(current);
      setActiveSubId(currentSub);
      setPercent(Math.round(progress * 100));
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

  const jumpTo = useCallback((id: string) => jumpToGuideTarget(id, !reducedMotion), [reducedMotion]);

  // The library reads the prompts from the page when it opens, so it always
  // matches what is rendered (and costs nothing until someone asks for it).
  const openLibrary = useCallback(() => {
    setLibraryPrompts(collectGuidePrompts());
    setLibraryOpen(true);
  }, []);

  useEffect(() => {
    window.addEventListener(OPEN_PROMPT_LIBRARY_EVENT, openLibrary);
    return () => window.removeEventListener(OPEN_PROMPT_LIBRARY_EVENT, openLibrary);
  }, [openLibrary]);

  const onLibraryJump = (id: string) => {
    setLibraryOpen(false);
    // Let the dialog close (and hand focus back) before scrolling.
    requestAnimationFrame(() => requestAnimationFrame(() => jumpTo(id)));
  };

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
        {/* Desktop header: a progress dial, the guide title and time left */}
        <div className="hidden xl:flex xl:items-center xl:gap-3.5 xl:pb-6 xl:pl-3">
          <div className="relative h-12 w-12 shrink-0">
            <svg viewBox="0 0 48 48" aria-hidden="true" className="h-full w-full -rotate-90">
              <circle cx="24" cy="24" r="21" fill="none" stroke="rgb(255 255 255 / 0.1)" strokeWidth="2" />
              <circle
                ref={registerRing}
                cx="24"
                cy="24"
                r="21"
                fill="none"
                stroke="#FF5500"
                strokeWidth="2"
                pathLength={1}
                strokeDasharray="1"
                strokeDashoffset="1"
              />
            </svg>
            <span className="absolute inset-0 flex items-center justify-center font-mono text-xs font-medium tabular-nums tracking-[-0.02em] text-zinc-200">
              {percent}
              <span className="text-zinc-500">%</span>
            </span>
          </div>
          <div className="min-w-0">
            <p className="font-mono text-xs font-medium uppercase tracking-[0.12em] text-zinc-300">
              {title}
            </p>
            <p className="mt-1.5 min-h-[1rem] font-mono text-xs tabular-nums text-zinc-400">
              {timeLeft}
            </p>
          </div>
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

        <div className="mt-4 hidden flex-col gap-0.5 border-t border-white/[0.06] pt-3 xl:flex">
          <button
            type="button"
            onClick={openLibrary}
            aria-haspopup="dialog"
            className="flex items-center gap-2.5 rounded-md py-2 pl-3 pr-2 text-left text-[0.8125rem] font-medium text-zinc-300 transition-colors hover:bg-white/[0.04] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
          >
            <SquareTerminal aria-hidden="true" className="h-3.5 w-3.5 text-[#FF7A33]" />
            Prompt library
            <span className="ml-auto font-mono text-xs tabular-nums text-zinc-500">{promptCount}</span>
          </button>
          <a
            href="#main-content"
            className="flex items-center gap-2.5 rounded-md py-2 pl-3 text-[0.8125rem] font-medium text-zinc-500 transition-colors hover:text-zinc-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
          >
            <ArrowUp aria-hidden="true" className="h-3.5 w-3.5" />
            Back to top
          </a>
        </div>

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
          <p className="mt-1.5 font-serif text-[2rem] font-normal leading-none tracking-[-0.01em] text-white">Contents</p>
          <div className="relative mt-4 h-[2px] overflow-hidden rounded-full bg-white/10">
            <span ref={registerBar} className="absolute inset-0 origin-left bg-[#FF5500] [transform:scaleX(0)]" />
          </div>
          <p className="mt-2 font-mono text-xs tabular-nums text-zinc-400">
            {activeItem ? `Now reading: ${activeItem.label}` : "Not started"}
            {timeLeft ? ` · ${timeLeft}` : ""}
          </p>
        </div>
        <button
          type="button"
          aria-haspopup="dialog"
          onClick={() => {
            setSheetOpen(false);
            requestAnimationFrame(() => requestAnimationFrame(openLibrary));
          }}
          className="mb-5 flex min-h-16 w-full items-center gap-3.5 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-left transition-colors active:bg-white/[0.06] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
        >
          <SquareTerminal aria-hidden="true" className="h-5 w-5 shrink-0 text-[#FF7A33]" />
          <span className="min-w-0 flex-1">
            <span className="block text-base font-semibold text-white">Prompt library</span>
            <span className="block text-sm text-zinc-400">{promptCount} copy-ready prompts, searchable</span>
          </span>
          <ArrowRight aria-hidden="true" className="h-4 w-4 shrink-0 text-zinc-500" />
        </button>
        <ol role="list" className="space-y-0.5 pb-8">
          {items.map((item) => {
            const isActive = item.id === activeId;
            const subs = subheadings[item.id] ?? [];
            return (
              <li key={item.id}>
                <a
                  href={`#${item.id}`}
                  aria-current={isActive ? "location" : undefined}
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

      <PromptLibrary
        open={libraryOpen}
        prompts={libraryPrompts}
        outline={items}
        guideTitle={title}
        onClose={() => setLibraryOpen(false)}
        onJump={onLibraryJump}
      />
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
