import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { INSTALLER_OUTPUT_DRILL, isDrillAnswerCorrect, type DrillLine } from "./installerOutputDrill";

const INSTALL_SH = readFileSync(join(import.meta.dir, "..", "..", "..", "install.sh"), "utf8");

/** The install.sh source that prints this line, or null for non-installer lines. */
function installerSourceFor(line: DrillLine): string | null {
  switch (line.kind) {
    case "step": {
      const match = line.text.match(/^\[(\d+\/\d+)\] (.+)$/);
      if (!match) throw new Error(`step line must look like [n/N] message: ${line.text}`);
      return `log_step "${match[1]}" "${match[2]}"`;
    }
    case "success":
      return `log_success "${line.text.replace(/^✓ /, "")}"`;
    case "warning":
      return `log_warn "${line.text.replace(/^⚠ /, "")}"`;
    case "error":
      return `log_error "${line.text.replace(/^✖ /, "")}"`;
    case "info":
      return line.text;
    default:
      return null;
  }
}

describe("installer output drill", () => {
  test("quotes only lines the installer really prints", () => {
    const quoted = INSTALLER_OUTPUT_DRILL.flatMap((scenario) => scenario.lines)
      .map(installerSourceFor)
      .filter((source): source is string => source !== null);
    expect(quoted.length).toBeGreaterThan(5);
    expect(quoted.filter((source) => !INSTALL_SH.includes(source))).toEqual([]);
  });

  test("symbols match their log kinds", () => {
    for (const line of INSTALLER_OUTPUT_DRILL.flatMap((scenario) => scenario.lines)) {
      if (line.kind === "success") expect(line.text.startsWith("✓ ")).toBe(true);
      if (line.kind === "warning") expect(line.text.startsWith("⚠ ")).toBe(true);
      if (line.kind === "error") expect(line.text.startsWith("✖ ")).toBe(true);
    }
  });

  test("scenarios are unique, explained, and need both answers", () => {
    const ids = INSTALLER_OUTPUT_DRILL.map((scenario) => scenario.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const scenario of INSTALLER_OUTPUT_DRILL) {
      expect(scenario.explanation.length).toBeGreaterThan(20);
      expect(isDrillAnswerCorrect(scenario, scenario.answer)).toBe(true);
      expect(isDrillAnswerCorrect(scenario, scenario.answer === "wait" ? "act" : "wait")).toBe(
        false,
      );
    }
    const answers = new Set(INSTALLER_OUTPUT_DRILL.map((scenario) => scenario.answer));
    expect(answers).toEqual(new Set(["wait", "act"]));
  });
});
