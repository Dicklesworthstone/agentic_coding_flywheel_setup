/**
 * Compatible-agent roster tests (#392).
 *
 * The roster is generated from acfs.manifest.yaml into
 * lib/generated/manifest-agents.ts. These tests guard the data invariants the
 * UI relies on, and that both surfaces the issue asked for — the /learn
 * commands page and the wizard accounts step — actually render it.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  defaultManifestAgents,
  manifestAgents,
} from "./generated/manifest-web-index";

const WEB_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function readPage(relPath: string): string {
  return readFileSync(join(WEB_ROOT, relPath), "utf-8");
}

describe("manifest agent roster data", () => {
  test("ships at least one default agent and one opt-in agent", () => {
    expect(manifestAgents.length).toBeGreaterThan(0);
    expect(defaultManifestAgents.length).toBeGreaterThan(0);
    expect(manifestAgents.length).toBeGreaterThan(defaultManifestAgents.length);
  });

  test("defaultManifestAgents is exactly the default-status subset", () => {
    expect(defaultManifestAgents).toEqual(
      manifestAgents.filter((agent) => agent.status === "default"),
    );
  });

  test("module ids and CLI names are unique", () => {
    const moduleIds = manifestAgents.map((agent) => agent.moduleId);
    const cliNames = manifestAgents.map((agent) => agent.cli);

    expect(new Set(moduleIds).size).toBe(moduleIds.length);
    expect(new Set(cliNames).size).toBe(cliNames.length);
  });

  test("aliases never collide across agents", () => {
    const aliases = manifestAgents.flatMap((agent) => agent.aliases);
    expect(new Set(aliases).size).toBe(aliases.length);
  });

  test("every row carries the fields the table renders", () => {
    for (const agent of manifestAgents) {
      expect(agent.moduleId.startsWith("agents.")).toBe(true);
      expect(agent.displayName.length).toBeGreaterThan(0);
      expect(agent.summary.length).toBeGreaterThan(0);
      expect(agent.auth.length).toBeGreaterThan(0);
      expect(agent.docsUrl.startsWith("https://")).toBe(true);
      expect(["default", "optional", "legacy"]).toContain(agent.status);
    }
  });
});

describe("roster surfaces", () => {
  test.each([
    ["app/learn/commands/page.tsx", 'variant="glass"'],
    ["app/wizard/accounts/page.tsx", 'variant="surface"'],
  ])("%s renders the roster", (relPath, variant) => {
    const source = readPage(relPath);

    expect(source).toContain('from "@/components/agent-roster"');
    expect(source).toContain(`<AgentRoster ${variant}`);
  });

  test("the /learn commands page no longer hardcodes an agent count", () => {
    const source = readPage("app/learn/commands/page.tsx");

    expect(source).not.toContain("Your three coding agents");
    expect(source).toContain("defaultManifestAgents.length");
  });
});
