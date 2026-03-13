/**
 * Command Builder
 *
 * Generates personalized SSH, installer, and post-install commands
 * based on user preferences (IP, OS, username, mode, ref).
 *
 * @see bd-31ps.4 for the full spec
 */

import type { OperatingSystem, InstallMode } from "./userPreferences";
import { normalizeGitRef } from "./userPreferences";

const INSTALL_SCRIPT_BASE_URL =
  "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const DEFAULT_INSTALL_REF = "main";

export interface CommandBuilderInputs {
  ip: string;
  os: OperatingSystem;
  username: string;
  mode: InstallMode;
  ref: string | null;
}

export interface GeneratedCommand {
  id: string;
  label: string;
  description: string;
  command: string;
  windowsCommand?: string;
  runLocation: "local" | "vps";
}

function sshKeyPath(os: OperatingSystem): string {
  return os === "windows"
    ? "$HOME\\.ssh\\acfs_ed25519"
    : "~/.ssh/acfs_ed25519";
}

function sshKeyPathWindows(): string {
  return "$HOME\\.ssh\\acfs_ed25519";
}

export function formatSshHost(host: string): string {
  const normalized = host.trim();
  if (normalized.includes(":")) {
    // IPv6 address — strip any existing mismatched brackets and wrap cleanly
    const bare = normalized.replace(/^\[|\]$/g, "");
    return `[${bare}]`;
  }
  return normalized;
}

export function formatSshTarget(username: string, host: string): string {
  return `${username}@${formatSshHost(host)}`;
}

function normalizeInstallUsername(username: string | null | undefined): string | null {
  const trimmed = username?.trim() ?? "";
  if (!trimmed || trimmed === "ubuntu") return null;
  if (!/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(trimmed)) return null;
  return trimmed;
}

function normalizeSshUsername(username: string | null | undefined): string {
  return normalizeInstallUsername(username) ?? "ubuntu";
}

export function buildInstallCommand(
  mode: InstallMode,
  ref: string | null,
  username?: string | null,
): string {
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeInstallUsername(username);
  const installRef = safeRef ?? DEFAULT_INSTALL_REF;
  const userEnv = safeUsername ? `TARGET_USER="${safeUsername}" ` : "";
  const refEnv = safeRef ? `ACFS_REF="${safeRef}" ` : "";
  const installerUrl = `${INSTALL_SCRIPT_BASE_URL}/${installRef}/install.sh`;

  return `curl -fsSL "${installerUrl}?$(date +%s)" | ${userEnv}${refEnv}bash -s -- --yes --mode ${mode}`;
}

/**
 * Build all personalized commands from user inputs.
 */
export function buildCommands(inputs: CommandBuilderInputs): GeneratedCommand[] {
  const { ip, os, username, mode, ref } = inputs;
  const keyPath = sshKeyPath(os);
  const keyPathWin = sshKeyPathWindows();
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeSshUsername(username);
  const rootTarget = formatSshTarget("root", ip);
  const userTarget = formatSshTarget(safeUsername, ip);

  const commands: GeneratedCommand[] = [];

  // 1. SSH as root (first-time setup)
  commands.push({
    id: "ssh-root",
    label: "SSH as root",
    description: "First-time connection with your VPS password",
    command: `ssh ${rootTarget}`,
    runLocation: "local",
  });

  // 2. Installer
  commands.push({
    id: "installer",
    label: "Run installer",
    description: `Install ACFS in ${mode} mode${safeRef ? ` pinned to ${safeRef}` : ""}`,
    command: buildInstallCommand(mode, ref, safeUsername),
    runLocation: "vps",
  });

  // 3. SSH as configured user (post-install, key-based)
  commands.push({
    id: "ssh-user",
    label: `SSH as ${safeUsername}`,
    description: "Key-based login after installer completes",
    command: `ssh -i ${keyPath} ${userTarget}`,
    windowsCommand: `ssh -i ${keyPathWin} ${userTarget}`,
    runLocation: "local",
  });

  // 4. Doctor check
  commands.push({
    id: "doctor",
    label: "Health check",
    description: "Verify all tools installed correctly",
    command: "acfs doctor",
    runLocation: "vps",
  });

  // 5. Onboard
  commands.push({
    id: "onboard",
    label: "Start tutorial",
    description: "Launch the interactive onboarding",
    command: "onboard",
    runLocation: "vps",
  });

  return commands;
}

/**
 * Build a shareable URL with all command builder state encoded as query params.
 */
export function buildShareURL(inputs: CommandBuilderInputs): string {
  if (typeof window === "undefined") return "";
  const url = new URL(window.location.pathname, window.location.origin);
  const safeUsername = normalizeSshUsername(inputs.username);
  url.searchParams.set("ip", inputs.ip);
  url.searchParams.set("os", inputs.os);
  if (safeUsername !== "ubuntu") {
    url.searchParams.set("user", safeUsername);
  } else {
    url.searchParams.delete("user");
  }
  url.searchParams.set("mode", inputs.mode);
  const safeRef = normalizeGitRef(inputs.ref);
  if (safeRef) {
    url.searchParams.set("ref", safeRef);
  } else {
    url.searchParams.delete("ref");
  }
  return url.toString();
}
