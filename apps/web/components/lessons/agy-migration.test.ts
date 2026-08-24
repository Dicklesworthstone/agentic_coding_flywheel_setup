/**
 * Onboarding curriculum agy-migration Tests (bd-47kjh.10.1.3 / .10.1.4)
 *
 * The interactive lessons are large TSX components whose teaching content lives
 * in JSX text (not exported data), so live rendering is asserted in Playwright
 * E2E (e2e/antigravity-pages.spec.ts). Here we guard the migration at the source
 * level — the migrated lessons must teach `agy` as the primary third agent AND
 * retain the labeled-legacy `gmi` note, with no operational gmi command left
 * behind (the over-migration / under-migration regression guard).
 *
 * It also cross-checks the exported descriptive data (NTM card in flywheel.ts +
 * tldr-content.ts) so the forward trio reads cc/cod/agy.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { flywheelTools } from "../../lib/flywheel";

const LESSON_DIR = import.meta.dir;
const read = (file: string) => readFileSync(join(LESSON_DIR, file), "utf8");

describe("agents-login-lesson teaches agy, keeps gmi as legacy", () => {
  const src = read("agents-login-lesson.tsx");

  test("teaches the agy launcher on the pinned model", () => {
    expect(src).toContain("agy");
    expect(src).toContain('Gemini 3.7 Flash (High)');
  });

  test("retains a labeled-legacy gmi note (no over-migration)", () => {
    expect(src).toMatch(/gmi/);
    expect(src.toLowerCase()).toMatch(/legacy|retired/);
  });

  test("no operational gmi command remains (e.g. `$ gmi \"...\"` or --gmi=)", () => {
    expect(src).not.toMatch(/\$ gmi /);
    expect(src).not.toContain("--gmi=");
  });
});

describe("welcome-lesson teaches agy as the third agent", () => {
  const src = read("welcome-lesson.tsx");

  test("references agy and the Antigravity CLI", () => {
    expect(src).toContain("agy");
    expect(src).toContain("Antigravity CLI");
  });

  test("third agent card/tool no longer uses gmi as the primary shortcut", () => {
    expect(src).not.toContain('shortcut="gmi"');
    expect(src).not.toContain('shortName: "gmi"');
  });
});

describe("NTM descriptive data uses the cc/cod/agy trio", () => {
  test("flywheel NTM tool advertises the cc/cod/agy classification", () => {
    const ntm = flywheelTools.find((t) => t.id === "ntm");
    expect(ntm).toBeDefined();
    const blob = JSON.stringify(ntm);
    expect(blob).toContain("cc/cod/agy");
    expect(blob).not.toContain("cc/cod/gmi");
  });
});
