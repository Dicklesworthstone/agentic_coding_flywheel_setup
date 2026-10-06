/**
 * "Keep waiting or act?" drill for reading installer output (bd-hjbld). Every
 * installer line is quoted from install.sh; lib/installerOutputDrill.test.ts
 * fails if the installer stops printing it, so the drill cannot drift from
 * what users actually see.
 */

export type DrillLineKind =
  /** `log_step "n/N" "message"` -> `[n/N] message` */
  | "step"
  /** `log_success "message"` -> `✓ message` */
  | "success"
  /** `log_warn "message"` -> `⚠ message` */
  | "warning"
  /** `log_error "message"` -> `✖ message` */
  | "error"
  /** `log_info` text, printed as-is */
  | "info"
  /** Printed by the laptop's ssh client, not the installer */
  | "ssh"
  /** Narration of what the screen is doing, not printed text */
  | "narration";

export interface DrillLine {
  kind: DrillLineKind;
  text: string;
}

export type DrillChoice = "wait" | "act";

export interface DrillScenario {
  id: string;
  lines: DrillLine[];
  answer: DrillChoice;
  explanation: string;
}

export const INSTALLER_OUTPUT_DRILL: readonly DrillScenario[] = [
  {
    id: "progress",
    lines: [
      { kind: "success", text: "✓ Shell setup complete" },
      { kind: "step", text: "[4/9] Installing CLI tools..." },
    ],
    answer: "wait",
    explanation:
      "[n/9] lines are the installer's phases and ✓ marks one that finished. This is normal progress.",
  },
  {
    id: "warning",
    lines: [
      { kind: "step", text: "[1/9] Normalizing user account..." },
      { kind: "warning", text: "⚠ SSH key prompt failed or was skipped; continuing" },
    ],
    answer: "wait",
    explanation:
      "⚠ lines are warnings. This one says it is continuing, so let it. Only a run that stops with ✖ errors needs you.",
  },
  {
    id: "quiet",
    lines: [
      { kind: "step", text: "[5/9] Installing language runtimes..." },
      { kind: "narration", text: "(no new output for 3 minutes; the cursor is still blinking)" },
    ],
    answer: "wait",
    explanation:
      "Some steps download hundreds of megabytes without printing anything (Rust alone is about 300 MB). A blinking cursor means it is still working.",
  },
  {
    id: "failed",
    lines: [
      { kind: "error", text: "✖ ACFS installation failed!" },
      { kind: "info", text: "To resume installation from this point:" },
    ],
    answer: "act",
    explanation:
      "The run stopped. Run the resume command printed under that heading, or the same install command again: finished phases are skipped.",
  },
  {
    id: "dropped",
    lines: [
      { kind: "step", text: "[6/9] Installing coding agents..." },
      { kind: "ssh", text: "client_loop: send disconnect: Broken pipe" },
    ],
    answer: "act",
    explanation:
      "Your laptop lost the connection (sleep or Wi-Fi). SSH back in and run the same install command again: it waits for a run that is still going, or resumes from the last finished phase.",
  },
  {
    id: "upgrade-reboot",
    lines: [
      {
        kind: "warning",
        text: "⚠ Ubuntu upgrade will take 30-60 minutes per version and require reboots.",
      },
      { kind: "warning", text: "⚠ Your SSH session will disconnect. Reconnect after each reboot." },
      { kind: "ssh", text: "Connection to 203.0.113.42 closed by remote host." },
    ],
    answer: "act",
    explanation:
      "The VPS is rebooting for the Ubuntu upgrade, which carries on by itself. Wait a minute, SSH back in and watch it with journalctl -u acfs-upgrade-resume -f. Don't start another install meanwhile.",
  },
];

export function isDrillAnswerCorrect(scenario: DrillScenario, choice: DrillChoice): boolean {
  return scenario.answer === choice;
}
