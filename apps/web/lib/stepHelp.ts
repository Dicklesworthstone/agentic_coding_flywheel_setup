/**
 * Per-step help content for the "Need help?" wizard button.
 *
 * Each step optionally defines common issues (symptom + solution)
 * and general tips. Steps without entries show a generic fallback.
 *
 * @see bd-1yfv for the full spec
 */

import { getUserOS, getVPSIP } from "./userPreferences";
import { getCompletedSteps, TOTAL_STEPS } from "./wizardSteps";

export interface StepIssue {
  symptom: string;
  solution: string;
}

export interface StepHelp {
  commonIssues: StepIssue[];
  tips: string[];
}

export const STEP_HELP: Partial<Record<number, StepHelp>> = {
  1: {
    commonIssues: [
      {
        symptom: "I don't know which OS to pick",
        solution:
          "Choose the operating system on the computer you'll be typing commands on. If you're on a Mac laptop, pick Mac. If you're on a Windows desktop, pick Windows.",
      },
    ],
    tips: [
      "This just affects which terminal instructions you see — you can change it later.",
      "Linux users skip the terminal installation step automatically.",
    ],
  },

  2: {
    commonIssues: [
      {
        symptom: "I already have a terminal, do I need another one?",
        solution:
          "If you're on Mac, the built-in Terminal.app works fine. On Windows, we recommend Windows Terminal from the Microsoft Store for a better experience.",
      },
      {
        symptom: "Windows Terminal won't install from the Store",
        solution:
          "Try downloading it directly from GitHub: search 'Windows Terminal GitHub releases' and grab the latest .msixbundle file.",
      },
    ],
    tips: [
      "Any terminal that supports SSH will work — the suggested ones just have the best experience.",
    ],
  },

  3: {
    commonIssues: [
      {
        symptom: "ssh-keygen: command not found",
        solution:
          "On Windows, make sure you're using PowerShell or Windows Terminal (not Command Prompt). On Mac/Linux, open a new terminal window.",
      },
      {
        symptom: "The key file already exists",
        solution:
          "If you already have an SSH key at ~/.ssh/acfs_ed25519, you can skip this step and reuse it. Just make sure you remember the passphrase (if any).",
      },
      {
        symptom: "Permission denied when creating the key",
        solution:
          "Make sure the ~/.ssh directory exists: run 'mkdir -p ~/.ssh && chmod 700 ~/.ssh' then try again.",
      },
    ],
    tips: [
      "Ed25519 keys are shorter and more secure than RSA keys.",
      "The passphrase is optional but recommended for security.",
    ],
  },

  5: {
    commonIssues: [
      {
        symptom: "Which VPS plan should I pick?",
        solution:
          "For the agent coding flywheel, pick the cheapest plan with at least 4GB RAM and Ubuntu 24.04. Hetzner's CX22 ($4.50/mo) is the best value.",
      },
      {
        symptom: "I entered my IP but can't continue",
        solution:
          "Make sure you're entering the IPv4 address (looks like 123.45.67.89), not a hostname. Check your VPS provider's dashboard for the IP.",
      },
      {
        symptom: "My VPS shows 'initializing' or 'building'",
        solution:
          "Wait 1-2 minutes for the VPS to finish provisioning. Refresh your provider's dashboard to check the status.",
      },
    ],
    tips: [
      "Copy the IP address directly from your provider's dashboard to avoid typos.",
      "Make sure you selected Ubuntu 24.04 (not 22.04 or Debian) when creating the VPS.",
    ],
  },

  6: {
    commonIssues: [
      {
        symptom: "Connection refused",
        solution:
          "The VPS might still be starting up. Wait 30 seconds and try again. Also verify the IP address is correct.",
      },
      {
        symptom: "Connection timed out",
        solution:
          "Check that your IP address is correct. If using a firewall or VPN, try disabling it temporarily. Your provider may need a few minutes to provision the server.",
      },
      {
        symptom: "Permission denied (publickey)",
        solution:
          "This usually means the SSH key isn't being found. Make sure you're using: ssh -i ~/.ssh/acfs_ed25519 root@YOUR_IP",
      },
      {
        symptom: "Host key verification failed",
        solution:
          "If you recreated your VPS, the old key is cached. Run: ssh-keygen -R YOUR_IP  then try connecting again.",
      },
    ],
    tips: [
      "The first connection will ask you to verify the host fingerprint — type 'yes' to continue.",
      "If using Windows, make sure you're in PowerShell, not Command Prompt.",
    ],
  },

  8: {
    commonIssues: [
      {
        symptom: "'bash' is not recognized (Windows)",
        solution:
          "You're running commands on your local machine instead of the VPS. Make sure you SSH into your VPS first, then run the preflight commands.",
      },
      {
        symptom: "APT is locked by another process",
        solution:
          "Another update is running. Wait a few minutes, check the holder with 'sudo fuser -v /var/lib/dpkg/lock-frontend || true', then reboot and retry if it remains stuck.",
      },
      {
        symptom: "Cannot reach github.com",
        solution:
          "Check your VPS network: try 'ping 8.8.8.8'. If that works but github.com doesn't, inspect DNS with 'resolvectl status' or reboot the VPS before retrying.",
      },
    ],
    tips: [
      "Run all preflight commands on the VPS (your SSH session), not your local machine.",
    ],
  },

  9: {
    commonIssues: [
      {
        symptom: "Installation appears stuck or frozen",
        solution:
          "Tool compilation (especially Rust tools) can take 5-15 minutes. The installer shows progress — watch for the spinner. Don't close the terminal.",
      },
      {
        symptom: "SSH connection dropped during install",
        solution:
          "Reconnect via SSH and re-run the installer. It's safe to run multiple times — it skips already-installed components.",
      },
      {
        symptom: "Permission denied errors during install",
        solution:
          "Make sure you're running as root (your prompt should show root@). If you connected as ubuntu, run: sudo -i  then re-run the installer.",
      },
    ],
    tips: [
      "The installer is safe to run multiple times — it won't break anything.",
      "Keep your SSH session open until you see the completion message.",
    ],
  },

  10: {
    commonIssues: [
      {
        symptom: "I can't connect as ubuntu",
        solution:
          "Use: ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_IP. If that fails with 'permission denied', connect as root and check that the installer completed successfully.",
      },
    ],
    tips: [
      "After this step, always connect as 'ubuntu' (not 'root') for daily work.",
    ],
  },

  12: {
    commonIssues: [
      {
        symptom: "acfs doctor shows failures",
        solution:
          "Re-run the installer: it's safe to run multiple times. Make sure you're connected as the ubuntu user, then run: source ~/.zshrc && acfs doctor",
      },
      {
        symptom: "Command not found: acfs",
        solution:
          "Run: source ~/.zshrc  — the acfs command is loaded from your shell configuration. If that doesn't work, the installer may not have completed.",
      },
    ],
    tips: [
      "Run 'source ~/.zshrc' if commands aren't found after installation.",
      "The status check verifies all installed tools — failures here mean the installer needs to be re-run.",
    ],
  },
};

/**
 * Build a debug info string for the current wizard state.
 * Useful for users to share when seeking support.
 */
export function getDebugInfo(currentStep: number): string {
  const os = getUserOS();
  const ip = getVPSIP();
  const completed = getCompletedSteps();
  const ua =
    typeof navigator !== "undefined" ? navigator.userAgent : "unknown";

  return [
    "# ACFS Wizard Debug Info",
    `Step: ${currentStep} of ${TOTAL_STEPS}`,
    `OS: ${os ?? "not selected"}`,
    `VPS IP: ${ip ?? "not entered"}`,
    `Completed steps: ${completed.length > 0 ? completed.join(", ") : "none"}`,
    `Browser: ${ua}`,
    `Time: ${new Date().toISOString()}`,
  ].join("\n");
}
