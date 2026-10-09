/**
 * Drift guard for /cloud-agents: the page's data must match the setup
 * script it documents (scripts/claude-code-web-setup.sh) and the README.
 */

import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

import {
  CLAUDE_CODE_WEB_OPTIONS,
  CLAUDE_CODE_WEB_SCRIPT_PATH,
  CLAUDE_CODE_WEB_SCRIPT_URL,
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CLAUDE_CODE_WEB_TOOLS,
  CODEX_CLOUD_SETUP_SCRIPT,
  CODEX_CLOUD_START_SKILL,
  GENERIC_CLOUD_SETUP_SCRIPT,
  GENERIC_CLOUD_TASK_INSTRUCTIONS,
  CLOUD_AGENTS,
  CLOUD_AGENT_ROUTE,
} from "./claude-code-web";
import nextConfig from "../next.config";
import { getStaticRouteSocialData } from "./social-image-routes";

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

describe("cloud agent page data", () => {
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
    expect(readme).toContain(GENERIC_CLOUD_SETUP_SCRIPT);
    expect(readme).toContain(GENERIC_CLOUD_TASK_INSTRUCTIONS);
  });

  test("the neutral canonical route is wired into metadata, homepage and redirect", async () => {
    expect(getStaticRouteSocialData(CLOUD_AGENT_ROUTE).path).toBe(CLOUD_AGENT_ROUTE);
    expect(readFileSync(join(REPO_ROOT, "apps/web/app/cloud-agents/layout.tsx"), "utf8"))
      .toContain('canonical: "/cloud-agents"');
    expect(readFileSync(join(REPO_ROOT, "apps/web/app/page.tsx"), "utf8"))
      .toContain('href="/cloud-agents"');
    expect(await nextConfig.redirects?.()).toContainEqual({
      source: "/claude-code-web", destination: CLOUD_AGENT_ROUTE, permanent: true,
    });
  });

  test("other providers use generic mode and retain honest acceptance boundaries", () => {
    expect(new Set(CLOUD_AGENTS.map((agent) => agent.id)).size).toBe(CLOUD_AGENTS.length);
    expect(CLOUD_AGENTS.filter((agent) => agent.evidence === "Hosted test").map((agent) => agent.id))
      .toEqual(["claude", "codex"]);
    for (const id of ["amp", "devin", "grok", "generic"]) {
      const agent = CLOUD_AGENTS.find((item) => item.id === id)!;
      expect(agent.script).toContain("ACFS_CLOUD_AGENT=generic bash");
      expect(agent.instructions).toContain("$HOME/.acfs/cloud/AGENTS.md");
      expect(agent.docs).toStartWith("https://");
    }
    expect(CLOUD_AGENTS.find((agent) => agent.id === "muse")?.script).toBeUndefined();
    expect(CLOUD_AGENTS.find((agent) => agent.id === "amp")?.caveat).toContain("Debian 12");
    expect(CLOUD_AGENTS.find((agent) => agent.id === "codex")?.caveat).toContain("did not work");
  });

  test("the actual Codex recipe fails on a missing bootstrap and leaves Git exclusions alone", () => {
    const workspace = realpathSync(mkdtempSync(join(tmpdir(), "acfs-codex-recipe-")));
    const repo = join(workspace, "repository with spaces");
    const bin = join(workspace, "bin");
    const template = join(workspace, "empty-template");
    mkdirSync(repo);
    mkdirSync(bin);
    mkdirSync(template);
    // Inherited Git overrides must never redirect this test to a real checkout.
    const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")));
    env.GIT_CONFIG_NOSYSTEM = "1";
    env.GIT_CONFIG_GLOBAL = "/dev/null";
    env.GIT_TEMPLATE_DIR = template;
    env.PATH = `${bin}:${process.env.PATH}`;
    const init = spawnSync("git", ["init", "--quiet", repo], { env, encoding: "utf8" });
    expect(init.status).toBe(0);
    const exclude = join(repo, ".git/info/exclude");
    mkdirSync(join(repo, ".git/info"), { recursive: true });
    writeFileSync(exclude, "# Keep my exclusions\n");
    writeFileSync(join(bin, "curl"), "#!/bin/sh\nexit 22\n", { mode: 0o755 });
    const result = spawnSync("bash", ["-c", CODEX_CLOUD_SETUP_SCRIPT], {
      cwd: repo, env, encoding: "utf8",
    });
    expect(result.status).not.toBe(0);
    expect(readFileSync(exclude, "utf8")).toBe("# Keep my exclusions\n");
    // The same public recipe must still execute a fetched script successfully.
    writeFileSync(join(bin, "curl"), '#!/bin/sh\ncat <<\'BOOTSTRAP\'\nprintf "%s" "$ACFS_CLOUD_ROOT" > bootstrap-ran\nBOOTSTRAP\n', { mode: 0o755 });
    const success = spawnSync("bash", ["-c", CODEX_CLOUD_SETUP_SCRIPT], {
      cwd: repo, env, encoding: "utf8",
    });
    expect(success.status).toBe(0);
    expect(readFileSync(join(repo, "bootstrap-ran"), "utf8")).toBe(join(repo, ".acfs-cloud"));
    expect(readFileSync(exclude, "utf8")).toContain("/.acfs-cloud/\n/.agents/skills/acfs-cloud-tools/\n");
  });
});
