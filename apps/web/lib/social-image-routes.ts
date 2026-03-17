import type { SocialImageData } from "@/lib/social-image";

const STATIC_ROUTE_SOCIAL_DATA: Record<string, SocialImageData> = {
  "/": {
    badge: "Agentic Coding",
    title: "Agent Flywheel",
    description:
      "Turn a fresh VPS into a complete multi-agent coding environment with Claude, Codex, Gemini, and modern developer tooling.",
    path: "/",
    theme: "default",
    tags: ["Claude", "Codex", "Gemini"],
  },
  "/core-flywheel": {
    badge: "The 3-Tool Core Loop",
    title: "The Core Flywheel",
    description:
      "The beginner-friendly entry point: Agent Mail for coordination, br for task management, and bv for graph-aware triage.",
    path: "/core-flywheel",
    theme: "flywheel",
    tags: ["Agent Mail", "Beads", "bv"],
  },
  "/flywheel": {
    badge: "20+ Interconnected Tools",
    title: "The Agentic Coding Flywheel",
    description:
      "A self-reinforcing stack where agents coordinate, review, and ship in parallel while safety and quality stay enforced.",
    path: "/flywheel",
    theme: "flywheel",
    tags: ["Parallel Agents", "Autonomous Progress", "Safety"],
  },
  "/learn": {
    badge: "Interactive Lessons",
    title: "ACFS Learning Hub",
    description:
      "Master Linux, SSH, tmux, git, and multi-agent workflows with structured lessons designed for real-world execution.",
    path: "/learn",
    theme: "learn",
    tags: ["Beginner Friendly", "Hands-On", "Step-by-Step"],
  },
  "/learn/commands": {
    badge: "Terminal Playbook",
    title: "Command Reference",
    description:
      "Quick command patterns for core setup, verification, troubleshooting, and daily operation inside the flywheel workflow.",
    path: "/learn/commands",
    theme: "learn",
    tags: ["CLI", "Reference", "Copy-Paste Ready"],
  },
  "/learn/glossary": {
    badge: "Concepts Made Clear",
    title: "Learning Glossary",
    description:
      "Plain-language definitions for infrastructure, tooling, and agentic coding concepts used throughout the learning track.",
    path: "/learn/glossary",
    theme: "learn",
    tags: ["Definitions", "Beginner Friendly", "ACFS Terms"],
  },
  "/glossary": {
    badge: "Jargon Decoder",
    title: "Agent Flywheel Glossary",
    description:
      "Translate technical terms into practical intuition so you can move faster across setup, debugging, and collaboration.",
    path: "/glossary",
    theme: "tools",
    tags: ["Linux", "VPS", "Agent Tools"],
  },
  "/tools": {
    badge: "Tool Catalog",
    title: "Agent Tool Stack",
    description:
      "Explore the integrated toolchain powering orchestration, safety, debugging, memory, and multi-repo execution.",
    path: "/tools",
    theme: "tools",
    tags: ["Orchestration", "Safety", "Productivity"],
  },
  "/workflow": {
    badge: "Execution Blueprint",
    title: "The Complete Workflow",
    description:
      "A practical end-to-end operating model for planning, task graphs, swarm implementation, review, and deployment.",
    path: "/workflow",
    theme: "workflow",
    tags: ["Planning", "Swarms", "Ship Faster"],
  },
  "/tldr": {
    badge: "High-Level Overview",
    title: "The Flywheel TL;DR",
    description:
      "A compact overview of the full stack and why connected tools outperform isolated, one-off automation.",
    path: "/tldr",
    theme: "flywheel",
    tags: ["Overview", "Tool Synergy", "Architecture"],
  },
  "/troubleshooting": {
    badge: "Fix Common Failures",
    title: "Troubleshooting Guide",
    description:
      "Diagnose SSH, installer, auth, and environment issues quickly with actionable fixes and known-good command patterns.",
    path: "/troubleshooting",
    theme: "support",
    tags: ["SSH", "Installer", "Recovery"],
  },
  "/docs/security": {
    badge: "Defense in Depth",
    title: "Security Documentation",
    description:
      "Security architecture, threat model, and practical controls for safer autonomous coding with multiple AI agents.",
    path: "/docs/security",
    theme: "security",
    tags: ["Threat Model", "Guardrails", "Best Practices"],
  },

  "/wizard/os-selection": {
    badge: "Setup Wizard • Step 1",
    title: "Choose Your Operating System",
    description:
      "Start the guided installation path for macOS, Windows, or Linux before provisioning your remote coding server.",
    path: "/wizard/os-selection",
    theme: "wizard",
    tags: ["Step 1", "OS Detection", "Quick Start"],
  },
  "/wizard/install-terminal": {
    badge: "Setup Wizard • Step 2",
    title: "Install a Terminal",
    description:
      "Prepare a reliable terminal environment so every subsequent setup and verification command works consistently.",
    path: "/wizard/install-terminal",
    theme: "wizard",
    tags: ["Step 2", "Terminal", "Foundation"],
  },
  "/wizard/generate-ssh-key": {
    badge: "Setup Wizard • Step 3",
    title: "Generate Your SSH Key",
    description:
      "Create and validate key-based authentication to secure remote access and avoid fragile password-only workflows.",
    path: "/wizard/generate-ssh-key",
    theme: "wizard",
    tags: ["Step 3", "SSH", "Security"],
  },
  "/wizard/rent-vps": {
    badge: "Setup Wizard • Step 4",
    title: "Rent a VPS",
    description:
      "Choose a provider and plan that can handle parallel agent sessions, builds, and background automation reliably.",
    path: "/wizard/rent-vps",
    theme: "wizard",
    tags: ["Step 4", "VPS", "Sizing"],
  },
  "/wizard/create-vps": {
    badge: "Setup Wizard • Step 5",
    title: "Create the VPS Instance",
    description:
      "Launch your server correctly with the expected operating system and credentials before initial SSH access.",
    path: "/wizard/create-vps",
    theme: "wizard",
    tags: ["Step 5", "Provisioning", "Launch"],
  },
  "/wizard/ssh-connect": {
    badge: "Setup Wizard • Step 6",
    title: "Connect via SSH",
    description:
      "Establish your first remote session and confirm network, host key, and authentication details are correct.",
    path: "/wizard/ssh-connect",
    theme: "wizard",
    tags: ["Step 6", "SSH", "Connectivity"],
  },
  "/wizard/accounts": {
    badge: "Setup Wizard • Step 7",
    title: "Set Up Required Accounts",
    description:
      "Create the core service accounts needed for multi-agent coding, source control, deployment, and platform access.",
    path: "/wizard/accounts",
    theme: "wizard",
    tags: ["Step 7", "Accounts", "Integrations"],
  },
  "/wizard/preflight-check": {
    badge: "Setup Wizard • Step 8",
    title: "Run a Pre-Flight Check",
    description:
      "Validate prerequisites before installation so you avoid avoidable failures, lock conflicts, and configuration drift.",
    path: "/wizard/preflight-check",
    theme: "wizard",
    tags: ["Step 8", "Validation", "Readiness"],
  },
  "/wizard/run-installer": {
    badge: "Setup Wizard • Step 9",
    title: "Run the Installer",
    description:
      "Execute the one-liner installer and bootstrap your full agentic coding environment with checkpointed setup phases.",
    path: "/wizard/run-installer",
    theme: "wizard",
    tags: ["Step 9", "One-Liner", "Bootstrap"],
  },
  "/wizard/reconnect-ubuntu": {
    badge: "Setup Wizard • Step 10",
    title: "Reconnect as Ubuntu User",
    description:
      "Transition from root to your Ubuntu workflow account and align with the expected day-to-day operating context.",
    path: "/wizard/reconnect-ubuntu",
    theme: "wizard",
    tags: ["Step 10", "User Context", "Hardening"],
  },
  "/wizard/verify-key-connection": {
    badge: "Setup Wizard • Step 11",
    title: "Verify Key-Based Login",
    description:
      "Confirm passwordless SSH works end-to-end so future sessions remain fast, secure, and predictable.",
    path: "/wizard/verify-key-connection",
    theme: "wizard",
    tags: ["Step 11", "SSH Keys", "Verification"],
  },
  "/wizard/status-check": {
    badge: "Setup Wizard • Step 12",
    title: "Run a Status Check",
    description:
      "Audit installed components and ensure the toolchain is healthy before launching full autonomous workflows.",
    path: "/wizard/status-check",
    theme: "wizard",
    tags: ["Step 12", "Health Check", "Audit"],
  },
  "/wizard/launch-onboarding": {
    badge: "Setup Wizard • Step 13",
    title: "Launch Onboarding",
    description:
      "Start the interactive onboarding track to learn operations, collaboration patterns, and high-leverage workflows.",
    path: "/wizard/launch-onboarding",
    theme: "wizard",
    tags: ["Step 13", "Onboarding", "Learn Fast"],
  },
  "/wizard/windows-terminal-setup": {
    badge: "Wizard Companion Step",
    title: "Windows Terminal Setup",
    description:
      "Configure a stable Windows Terminal profile for smooth command execution, copy/paste reliability, and SSH sessions.",
    path: "/wizard/windows-terminal-setup",
    theme: "wizard",
    tags: ["Windows", "Terminal", "Configuration"],
  },
};

export function getStaticRouteSocialData(routePath: string): SocialImageData {
  const data = STATIC_ROUTE_SOCIAL_DATA[routePath];
  if (!data) {
    throw new Error(`[social-image] Missing static route data for: ${routePath}`);
  }
  return data;
}
