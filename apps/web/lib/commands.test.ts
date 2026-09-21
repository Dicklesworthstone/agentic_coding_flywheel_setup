/**
 * Command-reference + tool-page Tests (agy migration)
 *
 * Structural tests for the command reference after the gmi -> agy migration
 * (bd-47kjh.10.1.2). Crucially, this cross-checks that every agent command's
 * docsUrl resolves to a real tool-data route — guarding the 404 risk where a
 * docsUrl points at /learn/tools/<id> but tool-data has no matching key (the
 * route is built from tool-data keys via generateStaticParams()).
 */

import { describe, expect, test } from "bun:test";
import { TOOL_IDS, TOOLS } from "../app/learn/tools/[tool]/tool-data";
import { COMMANDS } from "./commands";

describe("agy command reference entry", () => {
  test("an `agy` command exists in the agents category", () => {
    const agy = COMMANDS.find((c) => c.name === "agy");
    expect(agy).toBeDefined();
    expect(agy?.category).toBe("agents");
    expect(agy?.fullName).toBe("Antigravity CLI");
    expect(agy?.example).toContain("agy ");
    expect(agy?.docsUrl).toBe("/learn/tools/antigravity-cli");
  });

  test("the agy example passes its prompt with -p (#390)", () => {
    // The Antigravity CLI reads a prompt only from -p/--print, -i, or stdin
    // and rejects a positional argument, unlike cc/cod. The documented form
    // must work even without the ACFS launcher's positional-prompt shim.
    const agy = COMMANDS.find((c) => c.name === "agy");
    expect(agy?.example).toMatch(/^agy -p ["']/);
  });

  test("legacy gmi command is retained (no over-migration)", () => {
    const gmi = COMMANDS.find((c) => c.name === "gmi");
    expect(gmi).toBeDefined();
    expect(gmi?.fullName.toLowerCase()).toContain("legacy");
    // gmi launches the same locked agy, so its example needs -p as well.
    expect(gmi?.example).toMatch(/^gmi -p ["']/);
  });
});

describe("antigravity-cli tool page exists (404 guard)", () => {
  test("tool-data has an antigravity-cli entry", () => {
    expect(TOOL_IDS).toContain("antigravity-cli");
    expect(TOOLS["antigravity-cli"]).toBeDefined();
    expect(TOOLS["antigravity-cli"].title).toBe("Antigravity CLI");
    expect(TOOLS["antigravity-cli"].quickCommand).toBe("agy");
  });

  test("legacy gemini-cli tool page is retained and labeled legacy", () => {
    expect(TOOL_IDS).toContain("gemini-cli");
    expect(TOOLS["gemini-cli"].title.toLowerCase()).toContain("legacy");
  });

  test("every agent command docsUrl that points at /learn/tools/<id> resolves to a real route", () => {
    const toolRoutes = new Set(TOOL_IDS);
    for (const cmd of COMMANDS) {
      if (!cmd.docsUrl?.startsWith("/learn/tools/")) continue;
      const toolId = cmd.docsUrl.replace("/learn/tools/", "");
      expect({ command: cmd.name, toolId, exists: toolRoutes.has(toolId) }).toEqual({
        command: cmd.name,
        toolId,
        exists: true,
      });
    }
  });
});
