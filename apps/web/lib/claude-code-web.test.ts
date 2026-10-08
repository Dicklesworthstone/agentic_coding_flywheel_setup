/**
 * Drift guard for /claude-code-web: the page's data must match the setup
 * script it documents (scripts/claude-code-web-setup.sh) and the README.
 */

import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  CLAUDE_CODE_WEB_OPTIONS,
  CLAUDE_CODE_WEB_SCRIPT_PATH,
  CLAUDE_CODE_WEB_SCRIPT_URL,
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CLAUDE_CODE_WEB_TOOLS,
  CODEX_CLOUD_SETUP_SCRIPT,
  CODEX_CLOUD_START_SKILL,
} from "./claude-code-web";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const script = readFileSync(join(REPO_ROOT, CLAUDE_CODE_WEB_SCRIPT_PATH), "utf-8");
const readme = readFileSync(join(REPO_ROOT, "README.md"), "utf-8");

function scriptAssignment(name: string): string {
  const match = script.match(new RegExp(`^${name}="([^"]*)"$`, "m"));
  if (!match) throw new Error(`${name} is not assigned in ${CLAUDE_CODE_WEB_SCRIPT_PATH}`);
  return match[1];
}

function scriptDefault(name: string): string {
  const match = script.match(new RegExp(`\\$\\{${name}:-([^}]*)\\}`));
  if (!match) throw new Error(`${name} has no default in ${CLAUDE_CODE_WEB_SCRIPT_PATH}`);
  return match[1];
}

describe("claude-code-web page data", () => {
  test("lists exactly the script's default tools, in order", () => {
    expect(CLAUDE_CODE_WEB_TOOLS.map((tool) => tool.id).join(" ")).toBe(
      scriptAssignment("ACFS_CLOUD_DEFAULT_TOOLS"),
    );
  });

  test("every listed tool has a row in the script's tool table", () => {
    const rows = scriptAssignment("ACFS_CLOUD_TOOL_TABLE")
      .split("\n")
      .filter((row) => row.includes("|"))
      .map((row) => row.split("|")[0]);
    for (const tool of CLAUDE_CODE_WEB_TOOLS) {
      expect(rows).toContain(tool.id);
    }
  });

  test("option defaults match the script", () => {
    for (const option of CLAUDE_CODE_WEB_OPTIONS) {
      const expected =
        option.name === "ACFS_CLOUD_TOOLS"
          ? scriptAssignment("ACFS_CLOUD_DEFAULT_TOOLS")
          : scriptDefault(option.name);
      expect(option.defaultValue).toBe(expected);
    }
  });

  test("the setup script URL is the script's own raw URL", () => {
    const raw = scriptAssignment("ACFS_RAW").replace("${ACFS_REF}", "main");
    expect(CLAUDE_CODE_WEB_SCRIPT_URL).toBe(`${raw}/${CLAUDE_CODE_WEB_SCRIPT_PATH}`);
  });

  test("the README shows the same setup script", () => {
    expect(readme).toContain(CLAUDE_CODE_WEB_SETUP_SCRIPT);
    expect(readme).toContain(CODEX_CLOUD_SETUP_SCRIPT);
    expect(readme).toContain(CODEX_CLOUD_START_SKILL);
  });
});
