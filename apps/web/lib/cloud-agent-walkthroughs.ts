import {
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CODEX_CLOUD_SETUP_SCRIPT,
  CODEX_CLOUD_START_SKILL,
  GENERIC_CLOUD_SETUP_SCRIPT,
  GENERIC_CLOUD_TASK_INSTRUCTIONS,
} from "./claude-code-web";

export type SetupScreenshot = {
  src: string;
  width: number;
  height: number;
  alt: string;
  caption: string;
};

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
const claudeScreenshot = (file: string, width: number, height: number, alt: string, caption: string): SetupScreenshot => ({
  src: `/cloud-agents/${file}.png`, width, height, alt, caption: `${caption} · Claude Code, 8 Oct 2026`,
});
const codexScreenshot = (file: string, width: number, height: number, alt: string, caption: string): SetupScreenshot => ({
  src: `/cloud-agents/${file}.png`, width, height, alt, caption: `${caption} · ChatGPT, 8 Oct 2026`,
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
        screenshot: claudeScreenshot("claude-cloud-menu", 1720, 618, "Claude task composer with the environment menu showing Local, Cloud and Remote Control.", "1. Choose Cloud"),
      },
      {
        id: "add-environment", title: "Choose Add cloud environment…",
        paragraphs: ["In the Cloud submenu, click Add cloud environment…. To update an existing environment, open its configuration instead."],
        screenshot: claudeScreenshot("claude-add-environment", 1772, 516, "Cloud submenu showing existing Default environments and Add cloud environment at the bottom.", "2. Add a cloud environment"),
      },
      {
        id: "network", title: "Name it and choose network access",
        paragraphs: ["In Name, enter Flywheel (or any name you will recognize). Open Network access and choose Full for the simplest setup.", "For a narrower policy, choose Custom and allow the two hosts below. If your organization fixes the policy to Trusted, keep that policy and inspect the log for tools it could not download."],
        fields: [{ label: "Name", value: "Flywheel" }, { label: "Network access", value: "Full, or Custom with the two hosts" }],
        paste: { title: "Custom allowed domains", text: domains, label: "Copy Claude custom download domains" },
        screenshot: claudeScreenshot("claude-network-options", 1456, 2328, "Add cloud environment dialog with Network access expanded to None, Trusted, Full and Custom.", "3. Full and Custom are in Network access"),
      },
      {
        id: "setup-script", title: "Paste into Setup script",
        paragraphs: ["Copy the script below into the Setup script field. The npm install text in the screenshot is a placeholder, not the flywheel script.", "If you already have project setup commands, keep them and add the flywheel download line after them. No network secret or environment variable is required for these public downloads."],
        fields: [{ label: "Destination", value: "Setup script" }],
        paste: { title: "Setup script", text: CLAUDE_CODE_WEB_SETUP_SCRIPT, label: "Copy setup script", regionLabel: "Setup script for a Claude Code cloud environment" },
        screenshot: claudeScreenshot("claude-setup-fields", 1182, 2260, "Add cloud environment form with Name, Network access, Setup script, Environment variables and Add environment button.", "4. Paste into Setup script, then Add environment"),
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
        screenshot: codexScreenshot("codex-cloud-composer", 1686, 730, "ChatGPT task composer with Cloud and Choose environment above the Do anything input.", "1. Start in Cloud"),
      },
      {
        id: "create-environment", title: "Open Choose environment → Create environment",
        paragraphs: ["Click Choose environment, then Create environment. For an existing setup, use Settings → Codex Cloud → Environments and its Edit action."],
        screenshot: codexScreenshot("codex-create-environment", 1632, 808, "Choose environment menu with an existing flywheel environment and Create environment.", "2. Create an environment"),
      },
      {
        id: "repositories", title: "Select your repositories and Get started",
        paragraphs: ["Search for the repository you want to work on and tick its checkbox. Click Get started. The flywheel downloads are public; you do not need to own or attach the tool repositories."],
        screenshot: codexScreenshot("codex-select-repositories", 1416, 1608, "Create a cloud environment dialog with repository search, selection checkboxes and Get started.", "3. Select your project, then Get started"),
      },
      {
        id: "network", title: "Open Environment and allow the two download hosts",
        paragraphs: ["In the setup conversation, open the Environment panel (the sliders/settings control). Under Internet access, turn on Allow Codex to access internet.", "Keep Allow domains on Package managers, or use Custom domains only if that matches your project. Click the pencil beside Additional allowed domains, add both hosts below, and save that editor."],
        fields: [{ label: "Internet access", value: "Allow Codex to access internet: on" }, { label: "Additional allowed domains", value: "Add both hosts below" }],
        paste: { title: "Additional allowed domains", text: domains, label: "Copy Codex additional allowed domains" },
        screenshot: codexScreenshot("codex-environment-fields", 2326, 1980, "Environment panel showing Install script and Start skill pencil controls, internet switch, Package managers preset and Additional allowed domains.", "4. The script editors and network controls live here"),
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
      { id: "paste", title: "Merge the flywheel steps into the blueprint", paragraphs: ["Use the Linux build target. Merge the example below into your existing initialize and knowledge lists. Keep all project steps and do not add duplicate top-level YAML keys.", "initialize installs tools during a build. The blueprint's knowledge contents tell Devin where its tool guide lives; they are reference text, not shell commands."], fields: [{ label: "initialize", value: "Named run step: Install flywheel tools" }, { label: "knowledge", value: "Named contents item: flywheel-tools" }], paste: { title: "Blueprint additions (YAML)", text: DEVIN_CLOUD_BLUEPRINT, label: "Copy Devin blueprint additions" } },
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
      { id: "check-script", title: "Add a Check Script, then Save", paragraphs: ["Paste this into Check Script. It returns success only when all eleven executables run their version command. Click Save. Team Setup applies at computer startup and periodic refresh."], paste: { title: "Check Script", text: GROK_CLOUD_CHECK_SCRIPT, label: "Copy Grok Bot check script" } },
      { id: "verify", title: "Load the guide in a Bot task and verify", paragraphs: ["Include these instructions in your Bot task. Inspect the setup log and test a later refresh too. This is the Grok Bot computer workflow; Grok Build and delegated Cloud Agents use different setup controls."], paste: { title: "Bot task instructions", text: GENERIC_CLOUD_TASK_INSTRUCTIONS, label: "Copy Grok Bot task instructions" }, note: "The documented computers are Debian-based. ACFS's hosted compatibility here is still unverified." },
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
