/**
 * Lesson example guard (docs-vs-CLI drift)
 *
 * The onboarding lessons (`acfs/onboard/lessons/*.md`), the /learn lesson
 * components (`apps/web/components/lessons/*.tsx`) and the command reference
 * (`apps/web/lib/commands.ts`, `apps/web/lib/flywheel.ts`) are copy-pasted by
 * users. Every example they show must exist in the installed CLI.
 *
 * Each row below records one example that was verified against the real
 * `<cli> [<sub>] --help` and fixed (#393, #394). `wrong` is the form that the
 * CLI rejects and must never come back; `right` is the form the docs must
 * keep teaching, checked in the files that carry the example. A row without
 * `right` is a pure ban (the documented capability has no equivalent).
 *
 * `wrong` patterns are applied to EVERY doc source, not only the files that
 * originally carried them, so a dead example cannot be re-introduced in a
 * sibling lesson.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const ONBOARD = "acfs/onboard/lessons";
const LESSONS = "apps/web/components/lessons";

function listSources(): string[] {
  const md = readdirSync(join(REPO_ROOT, ONBOARD))
    .filter((f) => f.endsWith(".md"))
    .map((f) => `${ONBOARD}/${f}`);
  const tsx = readdirSync(join(REPO_ROOT, LESSONS))
    .filter((f) => f.endsWith(".tsx"))
    .map((f) => `${LESSONS}/${f}`);
  return [...md, ...tsx, "apps/web/lib/commands.ts", "apps/web/lib/flywheel.ts"];
}

const SOURCES = listSources();
const CONTENT = new Map(SOURCES.map((rel) => [rel, readFileSync(join(REPO_ROOT, rel), "utf8")]));

function contentOf(rel: string): string {
  const text = CONTENT.get(rel);
  if (text === undefined) {
    throw new Error(`${rel} is not a lesson source (add it to listSources())`);
  }
  return text;
}

interface ExampleRow {
  /** Issue that established the row, for blame. */
  issue: string;
  /** The CLI the example belongs to. */
  cli: string;
  /** Form the installed CLI rejects. Banned from every source. */
  wrong: RegExp;
  /** Form that works, and the files that must still teach it. */
  right?: { pattern: RegExp; in: string[] };
}

const ROWS: ExampleRow[] = [
  // ---------------------------------------------------------------- #393
  {
    issue: "#393",
    cli: "ntm",
    // `ntm palette` is an interactive TUI: its only local flag is --help.
    wrong: /ntm palette\b[^\n"'`]*--(send|list)\b/,
    right: {
      // The non-interactive sender is `ntm send <session> ...`.
      pattern: /ntm send myproject/,
      in: [`${ONBOARD}/06_ntm_command_palette.md`, `${LESSONS}/ntm-palette-lesson.tsx`],
    },
  },
  {
    issue: "#393",
    cli: "ntm",
    // `ntm quick` scaffolds a project; it never sent a prompt. The palette
    // lesson's quick actions map to `ntm send -t <template>`.
    wrong: /ntm quick (review|test|fix|docs)\b/,
    right: {
      pattern: /ntm send <session> -t (code_review|test|fix|document)\b/,
      in: [`${LESSONS}/ntm-palette-lesson.tsx`],
    },
  },
];

describe("lesson examples match the installed CLIs", () => {
  test("every doc source exists and is non-empty", () => {
    expect(SOURCES.length).toBeGreaterThan(40);
    for (const rel of SOURCES) {
      expect({ rel, empty: contentOf(rel).trim().length === 0 }).toEqual({ rel, empty: false });
    }
  });

  for (const row of ROWS) {
    const label = `${row.cli}: ${row.wrong.source}`;

    test(`${row.issue} ${label} is gone from every doc source`, () => {
      const offenders = SOURCES.filter((rel) => row.wrong.test(contentOf(rel)));
      expect({ wrong: row.wrong.source, offenders }).toEqual({ wrong: row.wrong.source, offenders: [] });
    });

    if (row.right) {
      const { pattern, in: files } = row.right;
      test(`${row.issue} ${row.cli}: ${pattern.source} is taught where the broken form used to be`, () => {
        const missing = files.filter((rel) => !pattern.test(contentOf(rel)));
        expect({ right: pattern.source, missing }).toEqual({ right: pattern.source, missing: [] });
      });
    }
  }
});

describe("the ntm palette e2e test does not probe flags the palette lacks (#393)", () => {
  const script = readFileSync(join(REPO_ROOT, "scripts/test_ntm_palette.sh"), "utf8");

  test("no `ntm palette --list` and no error-swallowing `|| echo` fallback", () => {
    expect(script).not.toMatch(/ntm palette --list/);
    expect(script).not.toMatch(/2>\/dev\/null \| wc -l \|\| echo/);
  });

  test("asserts the subcommand via --help and counts entries in the palette file", () => {
    expect(script).toMatch(/ntm palette --help/);
    expect(script).toMatch(/palette_entry_count/);
  });
});
