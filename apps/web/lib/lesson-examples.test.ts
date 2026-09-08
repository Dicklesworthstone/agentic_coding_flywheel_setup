/**
 * Lesson example guard (docs-vs-CLI drift)
 *
 * The onboarding lessons (`acfs/onboard/lessons/*.md`), the /learn lesson
 * components (`apps/web/components/lessons/*.tsx`), the command reference
 * (`apps/web/lib/commands.ts`, `apps/web/lib/flywheel.ts`, `tool-data.tsx`),
 * the glossary, the manifest `command_example` fields and the README are
 * copy-pasted by users. Every example they show must exist in the installed
 * CLI.
 *
 * Each row below records one example that was verified against the real
 * `<cli> [<sub>] --help` and fixed (#393, #394). `wrong` is the form that the
 * CLI rejects and must never come back; `right` is the form the docs must
 * keep teaching, checked in the files that carry the example. A row without
 * `right` is a pure ban (the documented capability has no equivalent).
 *
 * `wrong` patterns are applied to EVERY doc source, not only the files that
 * originally carried them, so a dead example cannot be re-introduced in a
 * sibling lesson. Patterns that scan to end-of-example use `[^\n"'`]*` so a
 * flag on the next line, or in the next quoted string, is not attributed to
 * the wrong command.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const ONBOARD = "acfs/onboard/lessons";
const LESSONS = "apps/web/components/lessons";
const COMMANDS = "apps/web/lib/commands.ts";
const FLYWHEEL = "apps/web/lib/flywheel.ts";
const JARGON = "apps/web/lib/jargon.ts";
const TOOL_DATA = "apps/web/app/learn/tools/[tool]/tool-data.tsx";
const MANIFEST = "acfs.manifest.yaml";
const README = "README.md";
const ONBOARD_SH = "packages/onboard/onboard.sh";

function listSources(): string[] {
  const md = readdirSync(join(REPO_ROOT, ONBOARD))
    .filter((f) => f.endsWith(".md"))
    .map((f) => `${ONBOARD}/${f}`);
  const tsx = readdirSync(join(REPO_ROOT, LESSONS))
    .filter((f) => f.endsWith(".tsx"))
    .map((f) => `${LESSONS}/${f}`);
  return [...md, ...tsx, COMMANDS, FLYWHEEL, JARGON, TOOL_DATA, MANIFEST, README, ONBOARD_SH];
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

const L = (name: string) => `${LESSONS}/${name}`;
const O = (name: string) => `${ONBOARD}/${name}`;

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
      in: [O("06_ntm_command_palette.md"), L("ntm-palette-lesson.tsx")],
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
      in: [L("ntm-palette-lesson.tsx")],
    },
  },

  // ---------------------------------------------------------------- #394
  // apr 1.3.0: rounds are `apr run <round>`; there is no refine/--pass.
  {
    issue: "#394",
    cli: "apr",
    wrong: /apr refine\b|apr run \d+ --pass\b/,
    right: { pattern: /apr run 1\b/, in: [O("13_apr.md"), L("apr-lesson.tsx"), COMMANDS, TOOL_DATA] },
  },
  {
    issue: "#394",
    cli: "apr",
    wrong: /apr review\b/,
    right: { pattern: /apr integrate 2 --copy/, in: [O("13_apr.md"), L("apr-lesson.tsx")] },
  },
  // ru 1.3.1: `commit-sweep` (dry-run by default, --execute) replaced the
  // never-shipped `agent-sweep`.
  {
    issue: "#394",
    cli: "ru",
    wrong: /\bagent[- ]sweep\b/i,
    right: {
      pattern: /ru commit-sweep --execute/,
      in: [O("09_ru.md"), L("ru-lesson.tsx"), FLYWHEEL, README],
    },
  },
  {
    issue: "#394",
    cli: "ru",
    wrong: /ru commit-sweep\b[^\n"'`]*--(parallel|with-release|resume|prompt)\b/,
    right: { pattern: /ru commit-sweep\b/, in: [L("flywheel-loop-lesson.tsx"), ONBOARD_SH, JARGON] },
  },
  {
    issue: "#394",
    cli: "ru",
    // The old `ru agent-sweep --prompt "..."` broadcast is `ntm send --all`.
    wrong: /--prompt "Update AGENTS\.md/,
    right: { pattern: /ntm send myproject --all "Update AGENTS\.md/, in: [L("agents-md-lesson.tsx")] },
  },
  // sbh 0.6.0: ballast is a subcommand group; cleanup is `clean`; recovery
  // is `emergency`; quarantine restore is `undo`.
  {
    issue: "#394",
    cli: "sbh",
    wrong: /sbh (release|restore|create|cleanup|analyze|purge-caches|reclaim)\b/,
    right: { pattern: /sbh ballast (release|replenish)\b/, in: [O("34_sbh.md"), L("sbh-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "sbh",
    wrong: /sbh clean --auto\b/,
    right: { pattern: /sbh emergency\b/, in: [O("34_sbh.md"), L("sbh-lesson.tsx")] },
  },
  // jfp 1.0.3 moved skill installs to jsm.
  {
    issue: "#394",
    cli: "jfp",
    wrong: /jfp install(ed)?\b/,
    right: { pattern: /jsm install (idea-wizard|<id>|perf-review-pro)/, in: [O("12_jfp.md"), L("jfp-lesson.tsx")] },
  },
  // ms 0.2.2: skills are loaded, imported or built; never invoked/created.
  {
    issue: "#394",
    cli: "ms",
    wrong: /\bms (create|invoke)\b/,
    right: { pattern: /ms load\b/, in: [O("11_meta_skill.md"), L("ms-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "ms",
    wrong: /ms list --installed\b/,
    right: { pattern: /ms (import|build)\b/, in: [O("11_meta_skill.md")] },
  },
  // pt 2.1.0: scan / deep-scan / query / run; no search, --top, --port, kill.
  {
    issue: "#394",
    cli: "pt",
    wrong: /\bpt (search|kill)\b|\bpt --(top|port|robot)\b|pt scan\b[^\n"'`]*--sort-by\b/,
    right: { pattern: /pt scan\b/, in: [O("14_pt.md"), L("pt-lesson.tsx"), MANIFEST] },
  },
  {
    issue: "#394",
    cli: "pt",
    wrong: /\bpt run\b[^\n"'`]*--sort-by\b/,
    right: { pattern: /pt run --goal 'free 4GB RAM'/, in: [O("14_pt.md"), L("pt-lesson.tsx")] },
  },
  // rch 1.0.64: workers init/discover/probe/list; update --fleet.
  {
    issue: "#394",
    cli: "rch",
    wrong: /rch workers (add|ping|status)\b|rch update --remote\b/,
    right: { pattern: /rch workers probe --all/, in: [O("17_rch.md"), L("rch-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "rch",
    wrong: /rch workers init\b[^\n"'`]*user@/,
    right: { pattern: /rch update --fleet\b/, in: [O("17_rch.md"), L("rch-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "rch",
    wrong: /rch workers discover\b[^\n"'`]*user@/,
    right: { pattern: /rch workers init\b/, in: [O("17_rch.md"), L("rch-lesson.tsx")] },
  },
  // xf 0.4.1: --since/--until; threads come from `xf tweet <id> --thread`
  // (reply chains within your own archived tweets); no sentiment flags.
  {
    issue: "#394",
    cli: "xf",
    // The query is quoted, so scan the whole line rather than stopping at a quote.
    wrong: /xf search\b[^\n]*--(from|to|sentiment|stats)\b|xf threads\b/,
    right: { pattern: /--since 2024-01-01 --until 2024-06-30/, in: [O("15_xf.md"), L("xf-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "xf",
    wrong: /--reconstruct\b/,
    right: { pattern: /xf tweet \d+ --thread/, in: [L("xf-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "xf",
    wrong: /Sentiment classify/,
    right: { pattern: /xf search "AI" --sort engagement/, in: [L("xf-lesson.tsx")] },
  },
  // brenner 0.4.1: corpus search only; session start/status/compile/publish
  // keyed by --thread-id; excerpt build --ordering; no crossref/synthesize.
  {
    issue: "#394",
    cli: "brenner",
    wrong: /brenner (corpus list|session (list|resume)|publish|crossref|synthesize)\b|excerpt build\b[^\n"'`]*--format\b/,
    right: { pattern: /brenner corpus search "/, in: [O("19_brenner_bot.md"), L("brenner-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "brenner",
    wrong: /brenner session start "/,
    right: {
      pattern: /brenner session (status|compile|publish) --thread-id/,
      in: [O("19_brenner_bot.md"), L("brenner-lesson.tsx")],
    },
  },
  {
    issue: "#394",
    cli: "brenner",
    wrong: /brenner session \w+ --session\b/,
    right: {
      pattern: /excerpt build --sections 42-50 --ordering chronological/,
      in: [O("19_brenner_bot.md"), L("brenner-lesson.tsx")],
    },
  },
  // casr 0.4.x: resume <target> <session-id>, list, info, providers.
  {
    issue: "#394",
    cli: "casr",
    wrong: /casr (capture|export|extract|distill|verify|session|preview)\b|casr resume\b[^\n"'`]*--(to|from|session)\b/,
    right: {
      pattern: /casr resume cod <session-id>/,
      in: [O("35_casr.md"), L("casr-lesson.tsx"), FLYWHEEL, MANIFEST],
    },
  },
  {
    issue: "#394",
    cli: "casr",
    wrong: /casr resume (claude|codex|gemini)\b/,
    right: { pattern: /casr info [^\n]*--peek/, in: [O("35_casr.md"), L("casr-lesson.tsx")] },
  },
  // dsr 0.1.2: release <tool> <version>; fallback <tool>; no --tag/--batch.
  {
    issue: "#394",
    cli: "dsr",
    wrong: /dsr (release|fallback)\b[^\n"'`]*--(tag|batch|repos)\b/,
    right: { pattern: /dsr release ntm 1\.2\.3/, in: [O("36_dsr.md"), MANIFEST] },
  },
  {
    issue: "#394",
    cli: "dsr",
    // `dsr release` needs <tool> <version>; versions are bare (1.2.3, not
    // v1.2.3) and there is no --sign (signing is part of the pipeline).
    wrong: /dsr release(['"`]|\s*$)|dsr release \w+ (--version )?v\d|dsr release\b[^\n"'`]*--sign\b/m,
    right: { pattern: /dsr fallback ntm --version/, in: [L("dsr-lesson.tsx")] },
  },
  // caam 0.1.18: next (alias rotate) <tool>; history --limit.
  {
    issue: "#394",
    cli: "caam",
    wrong: /caam (failover|log)\b|caam rotate --all-agents\b/,
    right: { pattern: /caam next (codex|claude|gemini)\b/, in: [L("caam-lesson.tsx"), L("debugging-agents-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "caam",
    wrong: /caam history --last\b/,
    right: { pattern: /caam history --limit 50/, in: [L("security-layers-lesson.tsx")] },
  },
  // cm 0.2.14: playbook add (alias add); no rule.
  {
    issue: "#394",
    cli: "cm",
    wrong: /\bcm rule\b|\bcm (reflect|distill)\b[^\n"'`]*--(task|patterns)\b/,
    right: { pattern: /cm playbook add "/, in: [L("debugging-agents-lesson.tsx")] },
  },
  // dcg 0.14.x: stats/history; no log.
  {
    issue: "#394",
    cli: "dcg",
    wrong: /dcg (log|guard)\b/,
    right: { pattern: /dcg stats --days 1/, in: [L("security-layers-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "dcg",
    wrong: /dcg test\b[^\n"'`]*--strict\b/,
    right: { pattern: /dcg test "/, in: [L("flywheel-loop-lesson.tsx")] },
  },
  // ntm 1.33.0: spawn/interrupt/view/zoom/overlay; no launch/layout/pause.
  {
    issue: "#394",
    cli: "ntm",
    wrong: /ntm (launch|layout|pause)\b|ntm spawn\b[^\n"'`]*--(agents|task)\b/,
    right: { pattern: /ntm spawn myproject --cc=/, in: [L("welcome-lesson.tsx"), L("flywheel-loop-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "ntm",
    wrong: /ntm interrupt\b[^\n"'`]*pane-\d/,
    right: { pattern: /ntm interrupt (myproject|<session>)/, in: [L("debugging-agents-lesson.tsx"), L("ntm-palette-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "ntm",
    wrong: /ntm send\b[^\n"'`]*--target\b|ntm send pane-\d/,
    right: { pattern: /ntm (view|zoom) <session>/, in: [L("ntm-palette-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "ntm",
    wrong: /ntm config set rate-stagger\b/,
    right: { pattern: /--stagger-mode=smart/, in: [L("debugging-agents-lesson.tsx")] },
  },
  // am 0.3.34: mail send with the five required flags; no broadcast.
  {
    issue: "#394",
    cli: "am",
    wrong: /\bam (broadcast|send)\b/,
    right: {
      pattern: /am mail send --project [^\n]*--from [^\n]*--to [^\n]*--subject [^\n]*--body/,
      in: [L("debugging-agents-lesson.tsx"), L("flywheel-loop-lesson.tsx")],
    },
  },
  // slb: request/run (--reason), pending, history; no create/list.
  {
    issue: "#394",
    cli: "slb",
    wrong: /slb (create|list)\b/,
    right: { pattern: /slb request "[^"]+" --reason/, in: [L("security-layers-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "slb",
    wrong: /slb history\b[^\n"'`]*--all\b/,
    right: { pattern: /slb history --json/, in: [L("security-layers-lesson.tsx")] },
  },
  // mdwb: Typer CLI with fetch/show/links/crawl/search; no bare URL, -o, --links.
  {
    issue: "#394",
    cli: "mdwb",
    wrong: /mdwb "|mdwb \$url|mdwb -o\b|mdwb --(links|recursive)\b/,
    right: { pattern: /mdwb fetch "/, in: [L("mdwb-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "mdwb",
    wrong: /mdwb fetch\b[^\n"'`]*(-o |--links)/,
    right: { pattern: /mdwb (show|links) <job-id>/, in: [L("mdwb-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "mdwb",
    wrong: /mdwb crawl\b[^\n"'`]*--recursive\b/,
    right: { pattern: /mdwb crawl https:/, in: [FLYWHEEL] },
  },
  // acfs-update is local-only; there is no --fleet/--rolling.
  {
    issue: "#394",
    cli: "acfs-update",
    wrong: /acfs-update\b[^\n"'`]*--(fleet|rolling)\b/,
    right: { pattern: /acfs-update --yes --quiet/, in: [L("keeping-updated-lesson.tsx")] },
  },
  // `acfs <tool>` is not a launcher; the real subcommands are newproj,
  // doctor, status, session, update, swarm, support-bundle, ...
  {
    issue: "#394",
    cli: "acfs",
    wrong: /\bacfs (bv|br|cm|ntm|am|ubs|caut|dcg|apr|ru|dsr|cass|beads|agents-md)\b/,
    right: { pattern: /bv --robot-triage/, in: [L("flywheel-loop-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "acfs",
    wrong: /acfs status --verbose\b/,
    right: { pattern: /\bbr (list|ready)\b/, in: [L("welcome-lesson.tsx"), L("flywheel-loop-lesson.tsx")] },
  },
  {
    issue: "#394",
    cli: "acfs",
    wrong: /acfs beads\b/,
    right: { pattern: /acfs newproj myproject/, in: [L("welcome-lesson.tsx")] },
  },
];

describe("lesson examples match the installed CLIs", () => {
  test("every doc source exists and is non-empty", () => {
    expect(SOURCES.length).toBeGreaterThan(40);
    for (const rel of SOURCES) {
      expect({ rel, empty: contentOf(rel).trim().length === 0 }).toEqual({ rel, empty: false });
    }
  });

  test("every `right` file is a known doc source", () => {
    for (const row of ROWS) {
      for (const rel of row.right?.in ?? []) {
        expect({ row: row.wrong.source, rel, known: CONTENT.has(rel) }).toEqual({
          row: row.wrong.source,
          rel,
          known: true,
        });
      }
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
