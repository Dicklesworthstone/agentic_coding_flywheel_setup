import {
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CLOUD_AGENTS,
  CODEX_CLOUD_SETUP_SCRIPT,
  CODEX_CLOUD_START_SKILL,
  GENERIC_CLOUD_SETUP_SCRIPT,
  GENERIC_CLOUD_TASK_INSTRUCTIONS,
} from "./claude-code-web";

/** A control the step asks you to use, as a percentage box over the screenshot. */
export type ScreenshotHighlight = {
  label: string;
  x: number;
  y: number;
  w: number;
  h: number;
};

export type SetupScreenshot = {
  src: string;
  width: number;
  height: number;
  alt: string;
  caption: string;
  /** Numbered in the order the step uses them. */
  highlights?: ScreenshotHighlight[];
};

function stepHandoffParts(steps: SetupStep[], numberPrefix = ""): string[] {
  const parts: string[] = [];
  steps.forEach((step, index) => {
    parts.push(`### ${numberPrefix}${index + 1}. ${step.title}`, ...step.paragraphs);
    if (step.fields) parts.push(step.fields.map((field) => `- **${field.label}:** ${field.value}`).join("\n"));
    if (step.paste) {
      const language = step.paste.text.startsWith("#!/bin/bash") ? "bash" : step.paste.text === DEVIN_CLOUD_BLUEPRINT ? "yaml" : "text";
      parts.push(`**Paste into ${step.paste.title}:**`, `\`\`\`${language}\n${step.paste.text}\n\`\`\``);
    }
    if (step.note) parts.push(`**Note:** ${step.note}`);
    if (step.screenshot) {
      parts.push(`![${step.screenshot.alt}](https://agent-flywheel.com${step.screenshot.src})`, step.screenshot.caption);
      const highlights = step.screenshot.highlights ?? [];
      if (highlights.length) parts.push(`Controls to use, in order: ${highlights.map((highlight, i) => `(${i + 1}) ${highlight.label}`).join("; ")}.`);
    }
  });
  return parts;
}

/** Self-contained computer-use handoff, kept in sync with the visible guide. */
export function getCloudAgentSetupInstructions(agentId: string): string {
  const agent = CLOUD_AGENTS.find((item) => item.id === agentId);
  const walkthrough = CLOUD_WALKTHROUGHS[agentId];
  if (!agent || !walkthrough) throw new Error(`Unknown cloud agent: ${agentId}`);

  const parts = [
    `# Set up Agent Flywheel for ${agent.name}`,
    "Use computer use in my browser to follow these instructions and configure my cloud coding environment. Install the tools in the provider's cloud environment, not on my local computer. Use the repository I specify; ask me which repository if it is unclear. Preserve my existing setup commands, project instructions, environments and repository access settings.",
    "## Working instructions",
    "- Follow the actual UI labels below. The screenshots are reference captures from 8 October 2026; if the UI differs, inspect it before acting. Do not invent a missing setup control.\n- Use my existing signed-in session. If sign-in, a billing change, organization permission or a network-policy approval is required, explain the exact action and ask at that point. Respect browser/computer-use approval requirements and organization restrictions.\n- Public downloads require no credentials or ownership of the tool repositories. Use the network setting named in the steps: Full access is the tested option where offered; when a narrower policy is preferred or required, allow only raw.githubusercontent.com and downloads.agent-flywheel.com in addition to the provider's package-manager defaults. Keep a locked organization policy and report unavailable tools.\n- Keep existing commands and settings. Merge the exact recipes below into their named fields. Do not replace unrelated setup or instruction content. Do not add secrets. Do not compile tools from source or run the full VPS installer.\n- Stop if this provider cannot supply a compatible, writable Linux x86_64 setup shell or retain installed files. For a documented but untested provider, verify compatibility rather than promising installation.",
    "## Provider and evidence",
    walkthrough.introduction,
    `**${agent.evidence}.** ${agent.caveat}`,
    walkthrough.visualEvidence,
    "## Setup steps",
    ...stepHandoffParts(walkthrough.steps),
  ];
  if (agentId === "muse") {
    // The capability checks gate the Linux template; embed only its steps so
    // the brief keeps one preamble and one completion section.
    const linux = CLOUD_WALKTHROUGHS.generic;
    parts.push(
      "## Linux template (only after every capability check passes)",
      "If all capability checks pass, continue with these Linux template steps. Otherwise report the unsupported capability and stop without installing.",
      linux.introduction,
      ...stepHandoffParts(linux.steps, "L"),
    );
  }
  parts.push(
    "## Completion and handoff",
    agentId === "muse"
      ? "Report the VM capability results and whether installation was possible. Do not claim a hosted Muse install merely from its terminal availability. If you installed with the Linux template, run its verification: check every executable (br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp), read $HOME/.acfs/cloud/setup.log and report each failure; setup exit 0 alone is not installation success. Check a fresh task/session to confirm the tools persist."
      : "Run the first-session verification from this guide. Check every executable: br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp. Read the setup log and tool guide at the paths in the recipe. Report each missing or failed tool and its log reason; setup exit 0 alone is not installation success. Check a fresh task/session after saving or publishing to confirm the tools persist and the agent loads the guide.",
    "Tell me which environment/project you configured, which settings and fields changed, which tools were verified, any missing tools or blocked steps, and what I must include in later tasks. Do not claim success before the runtime checks pass. Keep edits to provider setup only; do not commit project changes or start unrelated coding work.",
    `Visual guide: https://agent-flywheel.com/cloud-agents#${agentId}`,
  );
  return parts.join("\n\n") + "\n";
}

export type SetupStep = {
  id: string;
  title: string;
  paragraphs: string[];
  screenshot?: SetupScreenshot;
  fields?: { label: string; value: string }[];
  paste?: { title: string; text: string; label: string; regionLabel?: string };
  note?: string;
};

export type CloudWalkthrough = {
  introduction: string;
  visualEvidence: string;
  steps: SetupStep[];
};

const domains = "raw.githubusercontent.com\ndownloads.agent-flywheel.com";
const verifyHomeTools = `Read $HOME/.acfs/cloud/setup.log and the generated tool guide. In the task shell, export PATH="$HOME/.local/bin:$PATH". Run --version for br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp. Report every missing or failed executable and the relevant setup-log reason. An exit-0 setup does not mean all tools installed.`;
const claudeScreenshot = (file: string, width: number, height: number, alt: string, caption: string, highlights: ScreenshotHighlight[]): SetupScreenshot => ({
  src: `/cloud-agents/${file}.png`, width, height, alt, caption: `${caption} · Claude Code, 8 Oct 2026`, highlights,
});
const codexScreenshot = (file: string, width: number, height: number, alt: string, caption: string, highlights: ScreenshotHighlight[]): SetupScreenshot => ({
  src: `/cloud-agents/${file}.png`, width, height, alt, caption: `${caption} · ChatGPT, 8 Oct 2026`, highlights,
});

export const DEVIN_CLOUD_BLUEPRINT = `# Merge with your existing blueprint; keep its other steps.
initialize:
  - name: Install flywheel tools
    run: |
${GENERIC_CLOUD_SETUP_SCRIPT.split("\n").map((line) => `      ${line}`).join("\n")}
knowledge:
  - name: flywheel-tools
    contents: |
${GENERIC_CLOUD_TASK_INSTRUCTIONS.split("\n").map((line) => `      ${line}`).join("\n")}`;

export const GROK_CLOUD_CHECK_SCRIPT = `#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
for tool in br bv am mcp-agent-mail ubs cass cm ms ast-grep jsm jfp; do
  "$tool" --version >/dev/null 2>&1 || exit 1
done`;

/** Genuine captures are supplied by the user; field maps are not screenshots. */
export const CLOUD_WALKTHROUGHS: Record<string, CloudWalkthrough> = {
  claude: {
    introduction: "Create an environment, add the flywheel setup, then select it when starting your task.",
    visualEvidence: "Four actual UI screenshots. The form screenshots show the fields before you fill them in.",
    steps: [
      {
        id: "cloud-menu", title: "Open the Cloud menu",
        paragraphs: ["Open claude.ai/code. Above the task box, click the environment chip (Default in this example). Choose Cloud in the menu."],
        screenshot: claudeScreenshot("claude-cloud-menu", 1720, 618, "Claude task composer with the environment menu showing Local, Cloud and Remote Control.", "1. Choose Cloud", [
          { label: "Environment chip", x: 8.2, y: 64.3, w: 9.2, h: 7.8 },
          { label: "Cloud", x: 8.6, y: 45.8, w: 23.8, h: 7.4 },
        ]),
      },
      {
        id: "add-environment", title: "Choose Add cloud environment…",
        paragraphs: ["In the Cloud submenu, click Add cloud environment… at the bottom of the list. To update an existing environment, open its configuration instead."],
        screenshot: claudeScreenshot("claude-add-environment", 1772, 516, "Cloud submenu showing existing Default environments and Add cloud environment at the bottom.", "2. Add a cloud environment", [
          { label: "Add cloud environment…", x: 34.4, y: 59, w: 24, h: 9.8 },
        ]),
      },
      {
        id: "network", title: "Name it and choose network access",
        paragraphs: ["In Name, enter Flywheel (or any name you will recognize). Open Network access and choose Full for the simplest setup.", "For a narrower policy, choose Custom, allow the two hosts below and tick Also include default list of common package managers so your project's own installs still work. If you stay on Trusted, setup still starts; inspect the log for tools it could not download."],
        fields: [{ label: "Name", value: "Flywheel" }, { label: "Network access", value: "Full, or Custom with the two hosts" }],
        paste: { title: "Custom allowed domains", text: domains, label: "Copy Claude custom download domains" },
        screenshot: claudeScreenshot("claude-network-options", 1456, 2328, "Add cloud environment dialog with Network access expanded to None, Trusted, Full and Custom.", "3. Full and Custom are in Network access", [
          { label: "Name", x: 19.8, y: 12.8, w: 65, h: 3.8 },
          { label: "Full", x: 20.2, y: 35.4, w: 64.2, h: 4.8 },
        ]),
      },
      {
        id: "setup-script", title: "Paste into Setup script",
        paragraphs: ["Copy the script below into the Setup script field. The npm install text in the screenshot is a placeholder, not the flywheel script.", "If you already have project setup commands, keep them and add the flywheel download line after them. No network secret or environment variable is required for these public downloads."],
        fields: [{ label: "Destination", value: "Setup script" }],
        paste: { title: "Setup script", text: CLAUDE_CODE_WEB_SETUP_SCRIPT, label: "Copy setup script", regionLabel: "Setup script for a Claude Code cloud environment" },
        screenshot: claudeScreenshot("claude-setup-fields", 1182, 2260, "Add cloud environment form with Name, Network access, Setup script, Environment variables and Add environment button.", "4. Paste into Setup script, then Add environment", [
          { label: "Setup script", x: 11, y: 46.8, w: 80.2, h: 19.4 },
          { label: "Add environment", x: 67.3, y: 92.6, w: 23.8, h: 3.1 },
        ]),
      },
      {
        id: "start-and-check", title: "Add the environment and check a session",
        paragraphs: ["Click Add environment. Back at the composer, select Flywheel and your repository, then send a task. Setup runs before the agent starts.", "Paste the request below into the task. Review failures in the setup log even when setup reports exit 0."],
        paste: { title: "First task check", text: verifyHomeTools + " Also verify the registered Agent Mail stdio MCP server is healthy.", label: "Copy Claude first task check" },
      },
      {
        id: "reuse", title: "Use the same environment next time",
        paragraphs: ["For later tasks, choose Flywheel from Cloud and select the repository. Claude reads the managed tool guide from ~/.claude/CLAUDE.md.", "After changing the setup script, start a fresh session and check the log again. Keep your project instructions and setup commands alongside the flywheel additions."],
      },
    ],
  },
  codex: {
    introduction: "Prepare and publish the environment once. Include the tool instructions when starting each new task.",
    visualEvidence: "Four actual UI screenshots. The repository names are examples; choose your own project.",
    steps: [
      {
        id: "cloud", title: "Switch the task to Cloud",
        paragraphs: ["In ChatGPT's task composer, choose Work in → Cloud. The Cloud chip and Choose environment control appear above the task box."],
        screenshot: codexScreenshot("codex-cloud-composer", 1686, 730, "ChatGPT task composer with Cloud and Choose environment above the Do anything input.", "1. Start in Cloud", [
          { label: "Cloud", x: 8.4, y: 50.4, w: 8.2, h: 6.6 },
        ]),
      },
      {
        id: "create-environment", title: "Open Choose environment → Create environment",
        paragraphs: ["Click Choose environment, then Create environment. For an existing setup, use Settings → Codex Cloud → Environments and its Edit action."],
        screenshot: codexScreenshot("codex-create-environment", 1632, 808, "Choose environment menu with an existing flywheel environment and Create environment.", "2. Create an environment", [
          { label: "Choose environment", x: 15, y: 54.4, w: 21.6, h: 9.2 },
          { label: "Create environment", x: 16.4, y: 43.2, w: 32.2, h: 7.6 },
        ]),
      },
      {
        id: "repositories", title: "Select your repositories and Get started",
        paragraphs: ["Search for the repository you want to work on and tick its checkbox. Click Get started. The flywheel downloads are public; you do not need to own or attach the tool repositories."],
        screenshot: codexScreenshot("codex-select-repositories", 1416, 1608, "Create a cloud environment dialog with repository search, selection checkboxes and Get started.", "3. Select your project, then Get started", [
          { label: "Repository search", x: 12.4, y: 46.6, w: 62.4, h: 5.2 },
          { label: "Get started", x: 60.2, y: 88, w: 14.8, h: 5 },
        ]),
      },
      {
        id: "network", title: "Open Environment and allow the two download hosts",
        paragraphs: ["In the setup conversation, open the Environment panel (the sliders/settings control). Under Internet access, turn on Allow Codex to access internet.", "Keep Allow domains on Package managers; choose Custom domains only if your project needs that instead. Click the pencil beside Additional allowed domains, add both hosts below, and save that editor."],
        fields: [{ label: "Internet access", value: "Allow Codex to access internet: on" }, { label: "Additional allowed domains", value: "Add both hosts below" }],
        paste: { title: "Additional allowed domains", text: domains, label: "Copy Codex additional allowed domains" },
        screenshot: codexScreenshot("codex-environment-fields", 2326, 1980, "Environment panel showing Install script and Start skill pencil controls, internet switch, Package managers preset and Additional allowed domains.", "4. The script editors and network controls live here", [
          { label: "Allow Codex to access internet", x: 30.4, y: 43.8, w: 68, h: 5 },
          { label: "Additional allowed domains", x: 30.4, y: 52.8, w: 68, h: 4.8 },
        ]),
        note: "An organization policy may restrict these choices. Ask its admin to allow the public hosts if needed; adding a network secret is unnecessary.",
      },
      {
        id: "install-script", title: "Paste into the Install script editor",
        paragraphs: ["Under Scripts, click the pencil beside Install script. Paste the script below and save the editor. Older Codex environments call this Setup.", "Keep existing project dependency commands. Add these flywheel lines to the same script rather than replacing the project's setup. The tools stay in the writable repository workspace."],
        fields: [{ label: "Destination", value: "Scripts → Install script → pencil" }],
        paste: { title: "Install script", text: CODEX_CLOUD_SETUP_SCRIPT, label: "Copy Codex install script", regionLabel: "Install script for a Codex cloud environment" },
      },
      {
        id: "start-skill", title: "Save Start skill and keep a copy for every task",
        paragraphs: ["Click the pencil beside Start skill. Paste the instructions below and save the editor.", "Also include these instructions in every new task. Automatic Start skill and repository-skill discovery did not work in our hosted tests; the explicit task instructions are required."],
        fields: [{ label: "Destination", value: "Scripts → Start skill → pencil; also the new task prompt" }],
        paste: { title: "Task instructions / Start skill", text: CODEX_CLOUD_START_SKILL, label: "Copy Codex task instructions", regionLabel: "Codex Start skill instructions" },
      },
      {
        id: "publish", title: "Run setup, check the log, then Publish",
        paragraphs: ["Ask Codex in the setup conversation to run the saved Install script and check the generated setup log and tool versions. Resolve missing tools before relying on them.", "Save the environment draft, then choose Publish. Wait for Environment published. Saving the script alone does not prepare the filesystem used by new tasks."],
        paste: { title: "Setup verification request", text: "Run the saved Install script if it has not run yet. Read <repo>/.acfs-cloud/.acfs/cloud/setup.log and <repo>/.acfs-cloud/.codex/AGENTS.md. Set PATH to <repo>/.acfs-cloud/.local/bin and run --version for br, bv, am, mcp-agent-mail, ubs, cass, cm, ms, ast-grep, jsm and jfp. Report each failure and confirm the prepared files are present before I publish this environment.", label: "Copy Codex setup verification request" },
      },
      {
        id: "new-task", title: "Start a new task with the tool instructions",
        paragraphs: ["Select Start a new task, or choose this published environment in the Cloud composer. Add your task and the instructions from step 6.", "After setup changes, save and Republish, then test a new task. Existing tasks keep their own filesystem and do not receive the new snapshot. Hosted Agent Mail MCP is not configured by this recipe."],
      },
    ],
  },
  amp: {
    introduction: "Add the flywheel to the project's snapshot setup phase, then verify it in a fresh orb.",
    visualEvidence: "The field map follows Amp's documentation. No Amp account screenshot or hosted ACFS install has been captured.",
    steps: [
      { id: "settings", title: "Open the project's Orb settings", paragraphs: ["Open your project settings in Amp, then the Orb section. Find Pre-setup Script. It runs before the repository's .agents/setup."], fields: [{ label: "Project settings → Orb", value: "Pre-setup Script" }] },
      { id: "setup", title: "Paste into Pre-setup Script", paragraphs: ["Paste the script below, preserving any existing setup commands, and save the setting. Alternatively, merge it into an executable .agents/setup and commit that file.", "Keep installation out of .agents/resume: that hook has a short startup window and serves runtime work."], paste: { title: "Pre-setup Script", text: GENERIC_CLOUD_SETUP_SCRIPT, label: "Copy Amp Orbs setup script", regionLabel: "Setup script for Amp Orbs" } },
      { id: "fresh-orb", title: "Start a fresh orb and inspect setup", paragraphs: ["Start a new thread in the project. Amp prepares or reuses its project snapshot. Ask it to inspect ~/.acfs/cloud/setup.log; repository-hook output is also in /home/user/.cache/amp/logs/setup.log.", "Orbs use Debian 12. These bundles passed on Ubuntu 24.04; report any library or architecture failure rather than compiling from source."], paste: { title: "First orb check", text: verifyHomeTools, label: "Copy Amp first orb check" } },
      { id: "instructions", title: "Include the tool guide in each thread", paragraphs: ["Paste these instructions alongside your work request. Check a later fresh orb too, so the result is not just a one-off manual install."], paste: { title: "Task instructions", text: GENERIC_CLOUD_TASK_INSTRUCTIONS, label: "Copy Amp Orbs task instructions" }, note: "Amp says changes to .agents/setup alone do not invalidate an existing snapshot. Use its documented project snapshot workflow if a new orb still restores the old setup." },
    ],
  },
  devin: {
    introduction: "Add the tools to a Linux blueprint and the guide to its environment knowledge.",
    visualEvidence: "The field map follows Devin's blueprint documentation. No Devin account screenshot or hosted ACFS install has been captured.",
    steps: [
      { id: "blueprints", title: "Open Settings → Environment → Blueprints", paragraphs: ["In the organization sidebar, open Settings → Environment → Blueprints. In Repositories, click Add if your project is not listed; select it and confirm. Click the repository to open its blueprint editor."], fields: [{ label: "Settings → Environment → Blueprints", value: "Repositories → your repository → blueprint editor" }] },
      { id: "paste", title: "Merge the flywheel steps into the blueprint", paragraphs: ["Keep the blueprint on Devin's default Linux platform (no runs-on, or runs-on: linux). Merge the example below into your existing initialize and knowledge lists. Keep all project steps and do not add duplicate top-level YAML keys.", "initialize installs tools during a build. The blueprint's knowledge contents tell Devin where its tool guide lives; they are reference text, not shell commands."], fields: [{ label: "initialize", value: "Named run step: Install flywheel tools" }, { label: "knowledge", value: "Named contents item: flywheel-tools" }], paste: { title: "Blueprint additions (YAML)", text: DEVIN_CLOUD_BLUEPRINT, label: "Copy Devin blueprint additions" } },
      { id: "save", title: "Save and watch the snapshot build", paragraphs: ["Click Save. Open Settings → Environment → Snapshots and inspect Current build. After it shows Success, start a new Devin session from that snapshot."], fields: [{ label: "Save", value: "Starts a build" }, { label: "Environment → Snapshots → Current build", value: "Wait for Success" }] },
      { id: "verify", title: "Verify the tools in the new session", paragraphs: ["Give Devin the check below. Confirm the CPU and library compatibility as well as every tool version; this ACFS recipe has not been accepted in a hosted Devin session."], paste: { title: "New-session verification", text: verifyHomeTools, label: "Copy Devin first session check" } },
    ],
  },
  grok: {
    introduction: "An Enterprise team admin can add the tools through Grok Bot's Team Setup manifest.",
    visualEvidence: "The field map follows Grok Bot's Team Setup documentation. No Enterprise account screenshot or hosted ACFS install has been captured.",
    steps: [
      { id: "team-setup", title: "Open Grok Bot → Team Setup in the Cursor dashboard", paragraphs: ["As an Enterprise team admin, open the Grok Bot page in the Cursor dashboard and select Team Setup. This control is unavailable on other plans."], fields: [{ label: "Cursor dashboard → Grok Bot", value: "Team Setup (Enterprise)" }] },
      { id: "manifest", title: "Create a manifest and script entry", paragraphs: ["Next to Manifests, choose + for New Manifest. Enter acfs-flywheel as Manifest ID. Add a script entry with ID install-flywheel-tools. Keep existing manifests and entries."], fields: [{ label: "Manifest ID", value: "acfs-flywheel" }, { label: "Entry ID", value: "install-flywheel-tools" }] },
      { id: "setup-script", title: "Paste into Setup Script", paragraphs: ["Paste the script below into the entry's Setup Script field. Confirm the computer is Linux x86_64 and the team network policy permits both public download hosts."], paste: { title: "Setup Script", text: GENERIC_CLOUD_SETUP_SCRIPT, label: "Copy Grok Bot setup script" } },
      { id: "check-script", title: "Add a Check Script, then Save", paragraphs: ["Paste this into Check Script. It returns success only when all eleven executables run their version command; while any is missing, Team Setup reruns the Setup Script. Click Save. Team Setup applies at computer startup and periodic refresh."], paste: { title: "Check Script", text: GROK_CLOUD_CHECK_SCRIPT, label: "Copy Grok Bot check script" } },
      { id: "verify", title: "Load the guide in a Bot task and verify", paragraphs: ["Include these instructions in your Bot task. Inspect the setup log and test a later refresh too. This is the Grok Bot computer workflow; Grok Build and delegated Cloud Agents use different setup controls."], paste: { title: "Bot task instructions", text: GENERIC_CLOUD_TASK_INSTRUCTIONS, label: "Copy Grok Bot task instructions" }, note: "Team computers run Linux and Team Setup scripts run as the computer user. ACFS's hosted compatibility here is still unverified." },
    ],
  },
  muse: {
    introduction: "A supported install control has not been established. Check the VM before trying the Linux template.",
    visualEvidence: "No supported Muse setup screen or ACFS hosted install is verified. These are capability checks, not a fabricated UI walkthrough.",
    steps: [
      { id: "capabilities", title: "Check the VM before installing", paragraphs: ["Meta documents a terminal and a Debian runtime for Muse. Send the request below in its chat to check your VM's architecture, tools and persistent installation directory."], paste: { title: "VM capability request", text: "Without installing anything, report your Muse VM's OS, CPU architecture, writable persistent directory, and availability of Bash, Python 3, curl, tar and GNU timeout. Confirm whether installed CLI tools can be reused in later tasks and whether a supported setup/startup hook exists.", label: "Copy Muse VM capability request" } },
      { id: "downloads", title: "Confirm approved downloads and persistence", paragraphs: ["Confirm access to raw.githubusercontent.com and downloads.agent-flywheel.com under the VM's Sentinel approvals. Confirm installed files survive the next task."], fields: [{ label: "Required computer", value: "Linux x86_64 with compatible runtime libraries" }, { label: "Required persistence", value: "Writable installation root reused by later tasks" }] },
      { id: "template", title: "Use the Linux template only if those checks pass", paragraphs: ["Select Other Linux agent above for the exact shell recipe and explicit guide-loading instructions. If shell execution or persistence is unsupported, this setup cannot be installed there yet.", "Muse Code is a separate terminal/CI product. Its CLI support does not establish support in the personal Muse VM."], note: "No startup field, click path or hosted success is claimed for Muse." },
    ],
  },
  generic: {
    introduction: "For a provider where you control a Linux setup shell, install the bundle and load its guide explicitly.",
    visualEvidence: "This is a shell recipe. Setup field names and snapshot controls depend on your provider.",
    steps: [
      { id: "requirements", title: "Check the setup shell and installation root", paragraphs: ["Confirm Linux x86_64, compatible runtime libraries, Bash, Python 3, curl, tar and GNU timeout. Ubuntu 24.04 is the tested image. Find the provider's startup/install hook and ensure HOME is writable and retained in its snapshot."], fields: [{ label: "Install location", value: "$HOME/.local/bin" }, { label: "Log", value: "$HOME/.acfs/cloud/setup.log" }] },
      { id: "install", title: "Run in the provider's setup phase", paragraphs: ["Paste this into the provider's Bash setup hook, preserving existing commands. Allow the two public download hosts. For a different writable root, set an absolute ACFS_CLOUD_ROOT on the Bash invocation and use that root in the task instructions."], paste: { title: "Linux setup script", text: GENERIC_CLOUD_SETUP_SCRIPT, label: "Copy Other Linux agent setup script" } },
      { id: "instructions", title: "Load the guide in each task", paragraphs: ["Put these instructions into each work request or the provider's documented persistent instruction field. PATH needs to be set in each task shell. This recipe does not alter provider configuration or register MCP servers."], paste: { title: "Task instructions", text: GENERIC_CLOUD_TASK_INSTRUCTIONS, label: "Copy Other Linux agent task instructions", regionLabel: "Other Linux agent task instructions" } },
      { id: "verify", title: "Verify now and after a new session", paragraphs: ["Read the log and run every executable's version command. Save or publish the prepared filesystem using your provider's controls, then repeat the check in a new task. Missing tools are reported without source compilation."], paste: { title: "Session verification", text: verifyHomeTools, label: "Copy Linux session verification" } },
    ],
  },
};
