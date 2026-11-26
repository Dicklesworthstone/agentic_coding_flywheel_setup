import {
  CORE_FLYWHEEL_EXHIBIT_COUNT,
  CORE_FLYWHEEL_OUTLINE,
  CORE_FLYWHEEL_PROMPT_COUNT,
  guidePartCount,
} from "@/lib/guide-outlines";
import type { SocialImageData } from "@/lib/social-image";

// Share-card copy for every static route, plus the builders for lesson and
// tool cards. Descriptions are written to fit two lines on the card (at most
// 100 characters); lib/social-image-routes.test.ts holds the budgets and
// checks the wizard steps against lib/wizardSteps.ts.

/** Number of steps in the setup wizard (WIZARD_STEPS.length, kept in sync by test). */
export const WIZARD_SOCIAL_TOTAL = 13;

function wizardStep(
  path: string,
  current: number,
  title: string,
  accent: string,
  description: string,
): SocialImageData {
  return {
    badge: "Setup wizard",
    title,
    accent,
    description,
    path,
    theme: "wizard",
    step: { current, total: WIZARD_SOCIAL_TOTAL },
    hub: String(current).padStart(2, "0"),
    hubLabel: `of ${WIZARD_SOCIAL_TOTAL}`,
  };
}

const STATIC_ROUTE_SOCIAL_DATA: Record<string, SocialImageData> = {
  "/": {
    badge: "Agentic coding, set up for you",
    title: "AI agents coding",
    accent: "for you",
    description:
      "One command turns a fresh Ubuntu VPS into a complete multi-agent coding environment.",
    path: "/",
    theme: "default",
    nodes: ["Claude Code", "Codex", "Antigravity"],
    tags: ["One command", "Free & open source", "Ubuntu VPS"],
  },
  "/core-flywheel": {
    badge: "Start here · The core flywheel",
    title: "The Core",
    accent: "Flywheel",
    description:
      "Three tools, one loop: Agent Mail coordinates, br tracks the work, bv picks what to do next.",
    path: "/core-flywheel",
    theme: "guide",
    nodes: ["Agent Mail", "br", "bv"],
    // The landing cover's figures (lib/guide-outlines.ts, pinned to the page by test).
    stats: [
      { value: String(guidePartCount(CORE_FLYWHEEL_OUTLINE)), label: "Parts" },
      { value: String(CORE_FLYWHEEL_EXHIBIT_COUNT), label: "Visualizations" },
      { value: String(CORE_FLYWHEEL_PROMPT_COUNT), label: "Copy-ready prompts" },
    ],
  },
  "/complete-guide": {
    badge: "The complete guide",
    title: "The Agentic Coding",
    accent: "Flywheel",
    description:
      "Frontier-model planning, beads, and coordinated agent swarms, with every prompt included.",
    path: "/complete-guide",
    theme: "guide",
  },
  "/flywheel": {
    badge: "The flywheel",
    title: "Unheard-of velocity in",
    accent: "complex software",
    description:
      "Connected tools that let many agents plan, build, review, and ship in parallel while you're away.",
    path: "/flywheel",
    theme: "flywheel",
    nodes: ["ntm", "br", "bv", "am", "ubs", "cass"],
    tags: ["Parallel agents", "Review loops", "Safety rails"],
  },
  "/learn": {
    badge: "Learning hub",
    title: "Learn the",
    accent: "flywheel",
    description:
      "Hands-on lessons on Linux, SSH, tmux, git, and multi-agent workflows, one step at a time.",
    path: "/learn",
    theme: "learn",
    tags: ["Beginner friendly", "Hands-on", "Step by step"],
  },
  "/learn/commands": {
    badge: "Command reference",
    title: "The commands you'll",
    accent: "actually use",
    description:
      "Copy-ready command patterns for setup, verification, troubleshooting, and daily flywheel work.",
    path: "/learn/commands",
    theme: "learn",
    command: "acfs doctor",
  },
  "/learn/glossary": {
    badge: "Learning glossary",
    title: "Plain-English",
    accent: "definitions",
    description:
      "The infrastructure, tooling, and agentic coding concepts from the learning track, explained simply.",
    path: "/learn/glossary",
    theme: "learn",
    tags: ["Definitions", "Beginner friendly", "ACFS terms"],
  },
  "/glossary": {
    badge: "Jargon decoder",
    title: "Every term,",
    accent: "decoded",
    description:
      "Plain-English definitions for the words you'll meet in the wizard, the guides, and the learning hub.",
    path: "/glossary",
    theme: "tools",
    tags: ["Linux", "VPS", "Agent tools"],
  },
  "/workflow": {
    badge: "The agentic workflow",
    title: "From plan to",
    accent: "production",
    description:
      "Plan with frontier models, turn the plan into beads, then let a coordinated swarm build and ship.",
    path: "/workflow",
    theme: "workflow",
    tags: ["Planning", "Beads", "Swarms"],
  },
  "/tldr": {
    badge: "The TL;DR",
    title: "The whole flywheel",
    accent: "on one page",
    description:
      "Every tool in the stack, what it does, and why connected tools beat one-off automation.",
    path: "/tldr",
    theme: "flywheel",
    tags: ["Overview", "Tool synergy", "Architecture"],
  },
  "/omarchy": {
    badge: "Omarchy · Arch family",
    title: "The flywheel, native on",
    accent: "Omarchy",
    description:
      "One command installs the full agentic coding stack on Omarchy and Arch, using pacman packages.",
    path: "/omarchy",
    theme: "omarchy",
    tags: ["pacman", "starship", "Hyprland"],
  },
  "/cloud-agents": {
    badge: "Cloud agent setup",
    title: "Give your cloud agent a",
    accent: "flywheel",
    description:
      "Real screenshots, exact steps, and copy-ready scripts for Claude Code, ChatGPT / Codex, and more.",
    path: "/cloud-agents",
    theme: "tools",
    nodes: ["br", "bv", "am", "ubs", "cass", "jsm"],
    tags: ["Claude Code", "ChatGPT / Codex", "Linux agents"],
  },
  "/troubleshooting": {
    badge: "Troubleshooting",
    title: "Fix it",
    accent: "fast",
    description:
      "Diagnose SSH, installer, auth, and environment problems with known-good fixes you can copy.",
    path: "/troubleshooting",
    theme: "support",
    tags: ["SSH", "Installer", "Recovery"],
  },
  "/docs/security": {
    badge: "Security",
    title: "Defense in",
    accent: "depth",
    description:
      "Keep a one-login-everywhere setup safe: account security, SSO strategy, and practical guardrails.",
    path: "/docs/security",
    theme: "security",
    tags: ["Accounts", "SSO strategy", "Guardrails"],
  },

  "/wizard/os-selection": wizardStep(
    "/wizard/os-selection",
    1,
    "Choose your",
    "operating system",
    "Start the guided setup from macOS, Windows, or Linux before you provision your coding server.",
  ),
  "/wizard/install-terminal": wizardStep(
    "/wizard/install-terminal",
    2,
    "Install a",
    "terminal",
    "Set up a reliable terminal so every command in the setup behaves the same way on your machine.",
  ),
  "/wizard/generate-ssh-key": wizardStep(
    "/wizard/generate-ssh-key",
    3,
    "Generate your",
    "SSH key",
    "Create a key pair for secure, passwordless access to the server you are about to rent.",
  ),
  "/wizard/rent-vps": wizardStep(
    "/wizard/rent-vps",
    4,
    "Rent a",
    "VPS",
    "Pick a provider and plan with enough headroom for parallel agents, builds, and background work.",
  ),
  "/wizard/create-vps": wizardStep(
    "/wizard/create-vps",
    5,
    "Create the",
    "server",
    "Launch the instance with the right Ubuntu image and your SSH key before you connect.",
  ),
  "/wizard/ssh-connect": wizardStep(
    "/wizard/ssh-connect",
    6,
    "Connect over",
    "SSH",
    "Open your first remote session and confirm the host key, network, and login all work.",
  ),
  "/wizard/accounts": wizardStep(
    "/wizard/accounts",
    7,
    "Set up your",
    "accounts",
    "Create the service accounts your agents need for models, source control, and deployment.",
  ),
  "/wizard/preflight-check": wizardStep(
    "/wizard/preflight-check",
    8,
    "Run the",
    "pre-flight check",
    "Validate the server before installing so you avoid lock conflicts and configuration drift.",
  ),
  "/wizard/run-installer": wizardStep(
    "/wizard/run-installer",
    9,
    "Run the",
    "installer",
    "One command installs the full agentic coding stack in checkpointed phases.",
  ),
  "/wizard/reconnect-ubuntu": wizardStep(
    "/wizard/reconnect-ubuntu",
    10,
    "Reconnect as",
    "ubuntu",
    "Switch from root to the ubuntu account you will use for day-to-day work.",
  ),
  "/wizard/verify-key-connection": wizardStep(
    "/wizard/verify-key-connection",
    11,
    "Verify your",
    "key login",
    "Confirm passwordless SSH works end to end so every future session is fast and secure.",
  ),
  "/wizard/status-check": wizardStep(
    "/wizard/status-check",
    12,
    "Run a",
    "status check",
    "Check that every installed tool is healthy before you start running agents.",
  ),
  "/wizard/launch-onboarding": wizardStep(
    "/wizard/launch-onboarding",
    13,
    "Launch",
    "onboarding",
    "Start the interactive onboarding and learn the workflows that make the flywheel spin.",
  ),
  "/wizard/windows-terminal-setup": {
    badge: "Setup wizard · Windows",
    title: "Set up",
    accent: "Windows Terminal",
    description:
      "Configure a Windows Terminal profile for reliable copy, paste, and SSH sessions.",
    path: "/wizard/windows-terminal-setup",
    theme: "wizard",
    tags: ["Windows", "Terminal", "SSH"],
  },
};

export function getStaticRouteSocialData(routePath: string): SocialImageData {
  const data = STATIC_ROUTE_SOCIAL_DATA[routePath];
  if (!data) {
    throw new Error(`[social-image] Missing static route data for: ${routePath}`);
  }
  return data;
}

/** Every route with static share-card copy (used by the drift test). */
export const STATIC_SOCIAL_ROUTES = Object.keys(STATIC_ROUTE_SOCIAL_DATA);

/** Set the end of a name in the accent italic: "Case Study: *SLB*", "tmux *Basics*". */
function splitAccent(name: string): { title: string; accent: string } {
  const colon = name.indexOf(": ");
  if (colon > 0) return { title: name.slice(0, colon + 1), accent: name.slice(colon + 2) };
  const words = name.trim().split(/\s+/);
  if (words.length === 1) return { title: "", accent: words[0] };
  return { title: words.slice(0, -1).join(" "), accent: words[words.length - 1] };
}

export function lessonSocialData(
  lesson: { id: number; slug: string; title: string; description: string; duration: string },
  lessonCount: number,
): SocialImageData {
  const number = lesson.id + 1;
  return {
    badge: `Learning hub · Lesson ${number}`,
    ...splitAccent(lesson.title),
    description: lesson.description,
    path: `/learn/${lesson.slug}`,
    theme: "learn",
    hub: String(number).padStart(2, "0"),
    hubLabel: `of ${lessonCount}`,
    tags: [lesson.duration, "Hands-on", "Learning hub"],
  };
}

export function toolSocialData(tool: {
  id: string;
  title: string;
  tagline: string;
  quickCommand?: string;
}): SocialImageData {
  // Only a single short invocation fits the terminal line, and only its first
  // word names the tool: a pipeline such as `printf … | claude-post-compact-reminder`
  // would put `printf` on the dial and cut the line mid-argument.
  const example = tool.quickCommand?.trim().replace(/\s+/g, " ");
  const command =
    example && example.length <= 40 && !/[|;]|&&/.test(example) ? example : undefined;
  const binary = command?.split(" ")[0] ?? "";
  return {
    badge: "Tool deep dive",
    ...splitAccent(tool.title),
    // Taglines use " - " as a separator; a colon reads better on the card.
    description: tool.tagline.replace(" - ", ": "),
    path: `/learn/tools/${tool.id}`,
    theme: "tools",
    hub: /^[a-z][\w-]{0,6}$/.test(binary) ? binary : undefined,
    command,
    tags: command ? undefined : ["Learning hub", "ACFS"],
  };
}

/** Alt text that says what the card says, so it stays in step with the copy. */
export function socialImageAlt(data: SocialImageData): string {
  const title = [data.title, data.accent].filter(Boolean).join(" ").replace(/[,:]$/, "");
  return `Agent Flywheel: ${title}. ${data.description}`;
}
