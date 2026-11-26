"use client";

import { ArrowUpRight, Check, Copy, Search, SquareTerminal, X } from "lucide-react";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { GuidePart } from "@/lib/guide-outlines";
import { COPY_SUCCESS_MESSAGE } from "@/lib/hooks/useCopyFeedback";
import { cn, copyTextToClipboard } from "@/lib/utils";

const COPY_FAILED_IN_LIBRARY =
  "Copy failed. Open the prompt in the guide and select its text to copy it by hand.";

/** A prompt as rendered on the page (read from its PromptBlock). */
export interface LibraryPrompt {
  id: string;
  title: string;
  text: string;
  partId: string;
}

/** Window event that opens the library from anywhere on the page. */
export const OPEN_PROMPT_LIBRARY_EVENT = "guide:open-prompt-library";

/** Opens the library from server-rendered chrome such as the guide cover. */
export function PromptLibraryButton({ count, className }: { count: number; className?: string }) {
  return (
    <button
      type="button"
      aria-haspopup="dialog"
      onClick={() => window.dispatchEvent(new Event(OPEN_PROMPT_LIBRARY_EVENT))}
      className={className}
    >
      <span className="flex items-center gap-3">
        <SquareTerminal aria-hidden="true" className="h-4 w-4 shrink-0 text-[#FF7A33]" />
        <span className="font-medium text-zinc-100">Prompt library</span>
      </span>
      <span className="flex items-center gap-2 font-mono text-xs tabular-nums text-zinc-500">
        {count} prompts
        <ArrowUpRight aria-hidden="true" className="h-3.5 w-3.5" />
      </span>
    </button>
  );
}

/** Every PromptBlock in the article, in reading order. */
export function collectGuidePrompts(): LibraryPrompt[] {
  return Array.from(document.querySelectorAll<HTMLElement>("[data-guide-prompt]")).map((figure) => ({
    id: figure.id,
    title: figure.dataset.guidePrompt ?? "",
    text: figure.querySelector<HTMLElement>("[data-prompt-text]")?.textContent ?? "",
    partId: figure.closest<HTMLElement>("section[id]")?.id ?? "",
  }));
}

/**
 * A searchable list of every prompt in the guide. A native modal <dialog>
 * supplies the focus trap, Escape and inert background; it is a bottom sheet
 * on phones and a centred panel from `sm`.
 */
export function PromptLibrary({
  open,
  prompts,
  outline,
  guideTitle,
  onClose,
  onJump,
}: {
  open: boolean;
  prompts: LibraryPrompt[];
  outline: readonly GuidePart[];
  guideTitle: string;
  onClose: () => void;
  onJump: (id: string) => void;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const titleId = useId();
  const [query, setQuery] = useState("");
  const [copy, setCopy] = useState<{ id: string; ok: boolean } | null>(null);
  const resetTimer = useRef<number | undefined>(undefined);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      dialog.showModal();
      // A precise pointer means a keyboard is likely at hand; on touch screens
      // focusing the field would throw the keyboard over half the list.
      if (window.matchMedia("(pointer: fine)").matches) searchRef.current?.focus();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  useEffect(() => () => window.clearTimeout(resetTimer.current), []);

  const groups = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const matches = needle
      ? prompts.filter(
          (prompt) =>
            prompt.title.toLowerCase().includes(needle) || prompt.text.toLowerCase().includes(needle),
        )
      : prompts;
    return outline
      .map((part) => ({ part, prompts: matches.filter((prompt) => prompt.partId === part.id) }))
      .filter((group) => group.prompts.length > 0);
  }, [outline, prompts, query]);
  const shown = groups.reduce((sum, group) => sum + group.prompts.length, 0);

  const copyPrompt = async (prompt: LibraryPrompt) => {
    const ok = await copyTextToClipboard(prompt.text);
    window.clearTimeout(resetTimer.current);
    setCopy({ id: prompt.id, ok });
    resetTimer.current = window.setTimeout(() => setCopy(null), ok ? 2000 : 8000);
  };

  return (
    <dialog
      ref={dialogRef}
      data-guide-dialog
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        // A click on the dialog element itself landed on the backdrop.
        if (event.target === event.currentTarget) event.currentTarget.close();
      }}
      className={cn(
        "m-0 mt-auto h-[92dvh] max-h-none w-full max-w-none border-0 bg-transparent p-0 text-zinc-100",
        "backdrop:bg-black/70 backdrop:backdrop-blur-[2px]",
        "sm:m-auto sm:h-[min(86dvh,50rem)] sm:w-[min(48rem,calc(100vw-3rem))]",
      )}
    >
      <div className="guide-dialog-panel flex h-full flex-col overflow-hidden rounded-t-[1.25rem] border border-b-0 border-white/10 bg-[#090C12] shadow-[0_-24px_80px_-24px_rgba(0,0,0,0.9)] sm:rounded-2xl sm:border-b">
        <header className="border-b border-white/[0.07] px-5 pb-4 pt-3 sm:px-7 sm:pb-5 sm:pt-6">
          <div aria-hidden="true" className="mx-auto mb-3 h-1 w-10 rounded-full bg-white/15 sm:hidden" />
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <p className="font-mono text-xs font-medium uppercase tracking-[0.2em] text-[#FF7A33]">
                {guideTitle}
              </p>
              <h2 id={titleId} className="mt-1.5 font-serif text-[2rem] font-normal leading-none tracking-[-0.01em] text-white sm:text-[2.5rem]">
                Prompt library
              </h2>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                {prompts.length} copy-ready prompts in reading order. Copy one, or open it in context.
              </p>
            </div>
            <button
              type="button"
              onClick={() => dialogRef.current?.close()}
              aria-label="Close prompt library"
              className="-mr-2 -mt-1 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-zinc-400 transition-colors hover:bg-white/[0.07] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
            >
              <X aria-hidden="true" className="h-5 w-5" />
            </button>
          </div>
          <label className="mt-4 flex h-12 items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 transition-colors focus-within:border-[#FF5500] focus-within:bg-white/[0.05] focus-within:ring-1 focus-within:ring-[#FF5500]">
            <Search aria-hidden="true" className="h-4 w-4 shrink-0 text-zinc-500" />
            <span className="sr-only">Search prompts</span>
            <input
              ref={searchRef}
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search titles and prompt text"
              autoComplete="off"
              spellCheck={false}
              className="h-full min-w-0 flex-1 bg-transparent text-base text-zinc-100 outline-none placeholder:text-zinc-500 sm:text-[0.9375rem]"
            />
            {query && (
              <span className="shrink-0 font-mono text-xs tabular-nums text-zinc-500">
                {shown} / {prompts.length}
              </span>
            )}
          </label>
        </header>

        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-2 pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:px-3">
          {groups.map(({ part, prompts: partPrompts }) => (
            <div key={part.id} role="group" aria-label={part.title}>
              <p className="sticky top-0 z-10 flex items-baseline gap-2.5 bg-[#090C12]/95 px-3 pb-2 pt-5 font-mono text-xs font-medium uppercase tracking-[0.16em] text-zinc-500 backdrop-blur-sm sm:px-4">
                <span className="tabular-nums text-[#FF7A33]">
                  {part.number ? part.number.padStart(2, "0") : "··"}
                </span>
                {part.label}
              </p>
              <ul role="list" className="space-y-1">
                {partPrompts.map((prompt) => {
                  const state = copy?.id === prompt.id ? (copy.ok ? "copied" : "failed") : "idle";
                  return (
                    <li key={prompt.id} className="group/row flex items-stretch gap-1 rounded-xl transition-colors hover:bg-white/[0.035]">
                      <button
                        type="button"
                        onClick={() => onJump(prompt.id)}
                        className="min-w-0 flex-1 rounded-xl px-3 py-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#FF5500]/60 sm:px-4"
                      >
                        <span className="flex items-center gap-2 text-[0.9375rem] font-semibold leading-snug text-zinc-100">
                          <span className="min-w-0">{prompt.title}</span>
                          <ArrowUpRight
                            aria-hidden="true"
                            className="h-3.5 w-3.5 shrink-0 text-zinc-600 transition-colors group-hover/row:text-[#FF7A33]"
                          />
                        </span>
                        <span className="mt-1 line-clamp-2 font-mono text-[0.8125rem] leading-relaxed text-zinc-500">
                          {prompt.text}
                        </span>
                      </button>
                      <button
                        type="button"
                        onClick={() => void copyPrompt(prompt)}
                        aria-label={`Copy ${prompt.title}`}
                        className="flex w-12 shrink-0 items-center justify-center rounded-xl text-zinc-400 transition-colors hover:bg-white/[0.06] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#FF5500]/60"
                      >
                        {state === "copied" ? (
                          <Check aria-hidden="true" className="h-4 w-4 text-[#FF7A33]" />
                        ) : (
                          <Copy aria-hidden="true" className={cn("h-4 w-4", state === "failed" && "text-red-300")} />
                        )}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}

          {shown === 0 && (
            <div className="px-4 py-14 text-center">
              <p className="font-serif text-2xl text-zinc-200">Nothing matches “{query.trim()}”</p>
              <p className="mt-2 text-sm text-zinc-500">Try a word from the prompt itself, like “beads” or “review”.</p>
              <button
                type="button"
                onClick={() => {
                  setQuery("");
                  searchRef.current?.focus();
                }}
                className="mt-5 inline-flex min-h-11 items-center rounded-full border border-white/15 px-5 text-sm font-medium text-zinc-200 transition-colors hover:border-white/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/70"
              >
                Clear search
              </button>
            </div>
          )}
        </div>

        <p
          role="status"
          aria-live="polite"
          className={
            copy && !copy.ok
              ? "border-t border-white/[0.07] px-5 py-3 text-sm font-medium text-red-300 sm:px-7"
              : "sr-only"
          }
        >
          {copy ? (copy.ok ? COPY_SUCCESS_MESSAGE : COPY_FAILED_IN_LIBRARY) : ""}
        </p>
      </div>
    </dialog>
  );
}
