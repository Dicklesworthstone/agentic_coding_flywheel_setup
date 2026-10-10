/**
 * Drift guard for /cloud-agents: the page's data must match the setup
 * script it documents (scripts/claude-code-web-setup.sh) and the README.
 */

import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
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
  CLOUD_EXECUTABLES,
  cloudSubsetRecipe,
} from "./claude-code-web";
import nextConfig from "../next.config";
import { getStaticRouteSocialData } from "./social-image-routes";
import { createSocialImage } from "./social-image";
import { CLOUD_WALKTHROUGHS, DEVIN_CLOUD_BLUEPRINT, getCloudAgentSetupInstructions, GROK_CLOUD_CHECK_SCRIPT } from "./cloud-agent-walkthroughs";

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
  test("computer-use handoff includes the complete selected walkthrough without provider docs links", () => {
    for (const agent of CLOUD_AGENTS) {
      const instructions = getCloudAgentSetupInstructions(agent.id);
      expect(instructions).toStartWith(`# Set up Agent Flywheel for ${agent.name}\n`);
      expect(instructions).toContain(agent.caveat);
      expect(instructions).toContain("not on my local computer");
      expect(instructions).toContain("Preserve my existing setup commands");
      expect(instructions).toContain("ask at that point");
      expect(instructions).toContain("raw.githubusercontent.com and downloads.agent-flywheel.com");
      expect(instructions).not.toContain(agent.docs);
      for (const step of CLOUD_WALKTHROUGHS[agent.id].steps) {
        expect(instructions).toContain(step.title);
        for (const paragraph of step.paragraphs) expect(instructions).toContain(paragraph);
        for (const field of step.fields ?? []) expect(instructions).toContain(`**${field.label}:** ${field.value}`);
        if (step.paste) expect(instructions).toContain(`\n${step.paste.text}\n\`\`\``);
        if (step.note) expect(instructions).toContain(step.note);
        if (step.screenshot) expect(instructions).toContain(`https://agent-flywheel.com${step.screenshot.src}`);
      }
      expect(instructions).toContain("Check a fresh task/session");
      expect(instructions).toContain("Visual guide: https://agent-flywheel.com/cloud-agents#");
    }
  });

  test("handoff retains exact runnable recipes, later-task instructions and the Muse capability boundary", () => {
    const claude = getCloudAgentSetupInstructions("claude");
    const codex = getCloudAgentSetupInstructions("codex");
    expect(claude).toContain(`\`\`\`bash\n${CLAUDE_CODE_WEB_SETUP_SCRIPT}\n\`\`\``);
    expect(codex).toContain(`\`\`\`bash\n${CODEX_CLOUD_SETUP_SCRIPT}\n\`\`\``);
    expect(codex).toContain(CODEX_CLOUD_START_SKILL);
    expect(codex).toContain("br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp");
    expect(codex).toContain("setup exit 0 alone is not installation success");
    expect(getCloudAgentSetupInstructions("devin")).toContain(`\`\`\`yaml\n${DEVIN_CLOUD_BLUEPRINT}\n\`\`\``);
    expect(getCloudAgentSetupInstructions("muse")).toContain("Otherwise report the unsupported capability and stop without installing");
    expect(getCloudAgentSetupInstructions("muse")).toContain(GENERIC_CLOUD_SETUP_SCRIPT);
    expect(() => getCloudAgentSetupInstructions("__proto__")).toThrow("Unknown cloud agent");
  });

  test("dedicated cloud share images render nonempty PNGs at each platform size", async () => {
    for (const [variant, height] of [["opengraph", 630], ["twitter", 600]] as const) {
      const response = createSocialImage(getStaticRouteSocialData("/cloud-agents"), variant);
      expect(response.status).toBe(200);
      const bytes = Buffer.from(await response.arrayBuffer());
      expect(bytes.length).toBeGreaterThan(4096);
      expect(bytes.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      expect(bytes.readUInt32BE(16)).toBe(1200);
      expect(bytes.readUInt32BE(20)).toBe(height);
    }
  });

  test("custom-root task instructions connect writable search and memory state", () => {
    for (const text of [CODEX_CLOUD_START_SKILL, GENERIC_CLOUD_TASK_INSTRUCTIONS]) {
      expect(text).toContain("CASS_DATA_DIR, CASS_MEMORY_HOME and JFP_HOME exports in each task shell");
      expect(text).toContain("preserve existing overrides");
      expect(text).toContain("XDG_DATA_HOME/XDG_CONFIG_HOME writable");
      expect(readme).toContain(text);
    }
    for (const provider of ["codex", "amp", "devin", "grok", "generic"]) {
      expect(getCloudAgentSetupInstructions(provider)).toContain("CASS_MEMORY_HOME");
      expect(getCloudAgentSetupInstructions(provider)).toContain("CASS_DATA_DIR");
    }
    expect(script).toContain('if [[ -z "${XDG_DATA_HOME:-}" ]]; then');
  });

  test("MS task guidance connects project initialization, indexing and robot search", () => {
    const instruction = "Before using MS, follow the guide's local initialization and indexing steps in a writable project; reuse existing .ms/MS_ROOT/MS_CONFIG state.";
    for (const text of [CODEX_CLOUD_START_SKILL, GENERIC_CLOUD_TASK_INSTRUCTIONS]) {
      expect(text).toContain(instruction);
      expect(readme).toContain(text);
    }
    for (const provider of ["codex", "amp", "devin", "grok", "generic"]) {
      expect(getCloudAgentSetupInstructions(provider)).toContain(instruction);
    }
    expect(CLAUDE_CODE_WEB_TOOLS.find((tool) => tool.id === "ms")?.command).toBe('ms search "query" --robot');
    for (const text of [script, readme]) {
      expect(text).toContain("ms init --robot");
      expect(text).toContain("ms index <skill-directory> --robot");
      expect(text).toContain('ms search "query" --robot');
      expect(text).toContain("with configured overrides, skip this initialization recipe");
    }
  });

  test("walkthroughs cover every provider with stable, unique step anchors", () => {
    expect(Object.keys(CLOUD_WALKTHROUGHS).sort()).toEqual(CLOUD_AGENTS.map((agent) => agent.id).sort());
    for (const walkthrough of Object.values(CLOUD_WALKTHROUGHS)) {
      expect(walkthrough.steps.length).toBeGreaterThanOrEqual(3);
      expect(new Set(walkthrough.steps.map((step) => step.id)).size).toBe(walkthrough.steps.length);
      expect(walkthrough.steps.every((step) => /^[a-z0-9-]+$/.test(step.id))).toBe(true);
    }
    expect(CLOUD_WALKTHROUGHS.codex.steps.find((step) => step.id === "install-script")?.paste?.text).toBe(CODEX_CLOUD_SETUP_SCRIPT);
    expect(CLOUD_WALKTHROUGHS.codex.steps.find((step) => step.id === "start-skill")?.paste?.text).toBe(CODEX_CLOUD_START_SKILL);
    expect(CLOUD_WALKTHROUGHS.claude.steps.find((step) => step.id === "setup-script")?.paste?.text).toBe(CLAUDE_CODE_WEB_SETUP_SCRIPT);
  });

  test("all eight genuine screenshot references exist with accurate intrinsic dimensions", () => {
    const screenshots = Object.values(CLOUD_WALKTHROUGHS).flatMap((walkthrough) => walkthrough.steps.flatMap((step) => step.screenshot ? [step.screenshot] : []));
    expect(screenshots).toHaveLength(8);
    expect(new Set(screenshots.map((shot) => shot.src)).size).toBe(8);
    for (const shot of screenshots) {
      expect(shot.src).toMatch(/^\/cloud-agents\/[a-z-]+\.png$/);
      const bytes = readFileSync(join(REPO_ROOT, "apps/web/public", shot.src));
      expect(bytes.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      expect(bytes.readUInt32BE(16)).toBe(shot.width);
      expect(bytes.readUInt32BE(20)).toBe(shot.height);
      expect(shot.alt.length).toBeGreaterThan(30);
      expect(shot.caption).toContain("8 Oct 2026");
    }
  });

  test("provider examples retain exact scripts and explicit hosted limits", () => {
    expect(DEVIN_CLOUD_BLUEPRINT).toContain(GENERIC_CLOUD_SETUP_SCRIPT.split("\n").map((line) => `      ${line}`).join("\n"));
    expect(DEVIN_CLOUD_BLUEPRINT).toContain(GENERIC_CLOUD_TASK_INSTRUCTIONS.split("\n").map((line) => `      ${line}`).join("\n"));
    for (const source of [GENERIC_CLOUD_SETUP_SCRIPT, GROK_CLOUD_CHECK_SCRIPT]) {
      const result = spawnSync("bash", ["-n"], { input: source, encoding: "utf8" });
      expect(result.status).toBe(0);
      expect(result.stderr).toBe("");
    }
    expect(GROK_CLOUD_CHECK_SCRIPT).toContain('"$tool" --version >/dev/null 2>&1 || exit 1');
    for (const id of ["amp", "devin", "grok"]) {
      expect(CLOUD_WALKTHROUGHS[id].visualEvidence).toContain("No ");
      expect(CLOUD_WALKTHROUGHS[id].steps.some((step) => step.screenshot)).toBe(false);
    }
    expect(CLOUD_WALKTHROUGHS.muse.steps.some((step) => step.paste?.text.includes("curl -fsSL"))).toBe(false);
  });

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

  test("the eleven executables match every verification list and the mirror bundles", () => {
    const listed = "br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp";
    expect(CLOUD_EXECUTABLES.join(", ").replace(/, (\S+)$/, " and $1")).toBe(listed);
    expect(getCloudAgentSetupInstructions("claude")).toContain(listed);
    expect(GROK_CLOUD_CHECK_SCRIPT).toContain(`for tool in ${CLOUD_EXECUTABLES.join(" ")}; do`);
    const mirror = JSON.parse(readFileSync(join(REPO_ROOT, "cloud-mirror.json"), "utf8")) as { tools: Record<string, { bins: string[] }> };
    expect(Object.values(mirror.tools).flatMap((tool) => tool.bins).sort()).toEqual([...CLOUD_EXECUTABLES].sort());
  });

  test("subset recipes keep each agent's own mode and stay valid bash", () => {
    for (const agent of CLOUD_AGENTS) {
      const recipe = cloudSubsetRecipe(agent.id);
      expect(recipe).toContain('| ACFS_CLOUD_TOOLS="br bv am ubs" ');
      expect(recipe.replace(' ACFS_CLOUD_TOOLS="br bv am ubs"', "")).toBe(agent.script ?? GENERIC_CLOUD_SETUP_SCRIPT);
      const result = spawnSync("bash", ["-n"], { input: recipe, encoding: "utf8" });
      expect(result.status).toBe(0);
    }
    expect(cloudSubsetRecipe("claude")).not.toContain("ACFS_CLOUD_AGENT");
    expect(cloudSubsetRecipe("codex")).toContain("ACFS_CLOUD_AGENT=codex");
    expect(cloudSubsetRecipe("muse")).toContain("ACFS_CLOUD_AGENT=generic");
  });

  test("screenshot highlights stay inside their image and name a control", () => {
    for (const walkthrough of Object.values(CLOUD_WALKTHROUGHS)) {
      for (const step of walkthrough.steps) {
        for (const box of step.screenshot?.highlights ?? []) {
          expect(box.label.length).toBeGreaterThan(2);
          expect(box.x).toBeGreaterThanOrEqual(0);
          expect(box.y).toBeGreaterThanOrEqual(0);
          expect(box.x + box.w).toBeLessThanOrEqual(100);
          expect(box.y + box.h).toBeLessThanOrEqual(100);
        }
      }
    }
  });

  test("the Muse brief embeds the Linux steps once, without a second document", () => {
    const muse = getCloudAgentSetupInstructions("muse");
    expect(muse.match(/^# /gm)).toHaveLength(1);
    expect(muse.match(/^## Completion and handoff$/gm)).toHaveLength(1);
    expect(muse.match(/^Visual guide: /gm)).toHaveLength(1);
    for (const step of CLOUD_WALKTHROUGHS.generic.steps) expect(muse).toContain(step.title);
    expect(muse.indexOf("## Linux template")).toBeGreaterThan(muse.indexOf("Use the Linux template only if those checks pass"));
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

  test("failed bootstrap downloads never execute partial content in full and subset recipes", () => {
    const workspace = realpathSync(mkdtempSync(join(tmpdir(), "acfs-failed-bootstrap-")));
    const bin = join(workspace, "bin");
    const template = join(workspace, "empty-template");
    mkdirSync(bin);
    mkdirSync(template);
    const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")));
    env.GIT_CONFIG_NOSYSTEM = "1";
    env.GIT_CONFIG_GLOBAL = "/dev/null";
    env.GIT_TEMPLATE_DIR = template;
    env.PATH = `${bin}:${process.env.PATH}`;
    const failures: string[] = [];
    for (const partial of [false, true]) {
      writeFileSync(join(bin, "curl"), `#!/bin/sh
${partial ? "printf '%s\\n' 'printf partial > partial-bootstrap-ran'" : ""}
printf '%s\\n' 'curl: simulated download failure' >&2
exit 22
`, { mode: 0o755 });
      for (const agent of CLOUD_AGENTS.filter((entry) => entry.script)) {
        for (const [kind, recipe] of [["full", agent.script!], ["subset", cloudSubsetRecipe(agent.id)]]) {
          const repo = join(workspace, `${agent.id}-${kind}-${partial} with spaces`);
          mkdirSync(repo);
          expect(spawnSync("git", ["init", "--quiet", repo], { env, encoding: "utf8" }).status).toBe(0);
          const exclude = join(repo, ".git/info/exclude");
          mkdirSync(dirname(exclude), { recursive: true });
          writeFileSync(exclude, "# Keep my exclusions\n");
          const source = agent.id === "claude" ? `${recipe}\nprintf continued > existing-setup-ran\n` : recipe;
          const result = spawnSync("bash", ["-c", source], { cwd: repo, env, encoding: "utf8" });
          const label = `${agent.id}-${kind}-${partial ? "partial" : "missing"}`;
          if (existsSync(join(repo, "partial-bootstrap-ran"))) failures.push(`${label}: failed download bytes executed`);
          if (!result.stderr.includes("bootstrap download failed")) failures.push(`${label}: missing bootstrap diagnostic`);
          if (agent.id === "claude" ? result.status !== 0 : result.status === 0 || result.status === null) {
            failures.push(`${label}: unexpected exit ${result.status}`);
          }
          if (agent.id === "claude" && !existsSync(join(repo, "existing-setup-ran"))) failures.push(`${label}: following setup command skipped`);
          if (readFileSync(exclude, "utf8") !== "# Keep my exclusions\n") failures.push(`${label}: exclusions changed`);
        }
      }
    }
    expect(failures).toEqual([]);
  });

  test("full and subset recipes pass hardened download arguments through real Bash quoting", () => {
    const workspace = realpathSync(mkdtempSync(join(tmpdir(), "acfs-fetch-recipe-")));
    const bin = join(workspace, "bin");
    const template = join(workspace, "empty-template");
    mkdirSync(bin);
    mkdirSync(template);
    const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")));
    env.GIT_CONFIG_NOSYSTEM = "1";
    env.GIT_CONFIG_GLOBAL = "/dev/null";
    env.GIT_TEMPLATE_DIR = template;
    env.PATH = `${bin}:${process.env.PATH}`;
    writeFileSync(join(bin, "curl"), `#!/bin/sh
printf '%s\\0' "$@" > "$ACFS_TEST_CURL_ARGS"
cat <<'BOOTSTRAP'
printf '%s' "\${ACFS_CLOUD_AGENT:-claude}" > bootstrap-mode
BOOTSTRAP
`, { mode: 0o755 });
    for (const agent of CLOUD_AGENTS.filter((entry) => entry.script)) {
      for (const [kind, recipe] of [["full", agent.script!], ["subset", cloudSubsetRecipe(agent.id)]]) {
        const repo = join(workspace, `${agent.id}-${kind} with spaces`);
        mkdirSync(repo);
        expect(spawnSync("git", ["init", "--quiet", repo], { env, encoding: "utf8" }).status).toBe(0);
        const argsPath = join(repo, "curl-args");
        const result = spawnSync("bash", ["-c", recipe], {
          cwd: repo, env: { ...env, ACFS_TEST_CURL_ARGS: argsPath }, encoding: "utf8",
        });
        if (result.status !== 0) throw new Error(`${agent.id}-${kind}: ${result.stderr}`);
        expect(result.status).toBe(0);
        expect(result.stderr).toBe("");
        expect(readFileSync(argsPath, "utf8").split("\0").slice(0, -1)).toEqual([
          "-q", "-fsSL", "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "5", "--max-time", "20",
          "-A", "OpenAI File Downloader, XaiImageApiFetch/1.0", "-H", "Accept-Encoding: identity",
          CLAUDE_CODE_WEB_SCRIPT_URL,
        ]);
        expect(readFileSync(join(repo, "bootstrap-mode"), "utf8"))
          .toBe(agent.id === "claude" ? "claude" : agent.id === "codex" ? "codex" : "generic");
      }
    }
  });
});
