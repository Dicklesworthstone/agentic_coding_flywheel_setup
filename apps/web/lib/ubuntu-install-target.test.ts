import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import {
  buildCommands,
  buildHandoffRunbook,
  buildInstallCommand,
  buildInstallCommandDetails,
  buildTeamProfile,
  buildTeamProfileImportDiff,
  formatHandoffRunbookMarkdown,
  formatTeamProfileReviewMarkdown,
} from "./commandBuilder";
import type { ModuleSelectionInput } from "./moduleSelection";
import { ACFS_RECOMMENDED_UBUNTU } from "./vpsProviders";

/**
 * Run the actual copy/paste command, replacing only its network transport.
 * The harmless fixture has the legacy installer default and the real
 * --target-ubuntu= argument shape. It does not install or modify the host.
 */
function observeInstaller(command: string) {
  const fixture = [
    'TARGET_UBUNTU_VERSION="25.10"',
    "TARGET_UBUNTU_VERSION_EXPLICIT=false",
    'for arg in "$@"; do',
    '  case "$arg" in',
    '    --target-ubuntu=*) TARGET_UBUNTU_VERSION="${arg#*=}"; TARGET_UBUNTU_VERSION_EXPLICIT=true ;;',
    "  esac",
    "done",
    'printf "%s\\0" "$TARGET_UBUNTU_VERSION" "$TARGET_UBUNTU_VERSION_EXPLICIT" "${TARGET_USER:-ubuntu}" "$@"',
  ].join("\n");
  const result = spawnSync(
    "/bin/bash",
    [
      "--noprofile",
      "--norc",
      "-p",
      "-c",
      ["curl() { printf '%s\\n' \"$ACFS_TEST_INSTALLER\"; }", command].join("\n"),
    ],
    {
      env: {
        PATH: "/usr/bin:/bin",
        ACFS_TEST_INSTALLER: fixture,
        // An inherited old setting must not redirect a newly copied command.
        UBUNTU_TARGET_VERSION: "25.10",
      },
      encoding: "utf8",
      timeout: 5000,
    },
  );
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  const fields = result.stdout.split("\0");
  assert.equal(fields.pop(), "");
  return { target: fields[0], explicit: fields[1], user: fields[2], args: fields.slice(3) };
}

for (const mode of ["vibe", "safe"] as const) {
  for (const ref of [null, "release/lts", "v0.9.0", "a1b6c2f34aac7596e676688c36cb57cbbb869f3c"]) {
    test(`installer argv binds the recommended target for ${mode}/${ref ?? "default"}`, () => {
      const details = buildInstallCommandDetails(mode, ref, "dev-user");
      const observed = observeInstaller(details.command);
      assert.equal(details.targetUbuntu, ACFS_RECOMMENDED_UBUNTU);
      assert.equal(observed.target, "26.04");
      assert.equal(observed.explicit, "true");
      assert.equal(observed.user, "dev-user");
      assert.equal(observed.args[observed.args.indexOf("--mode") + 1], mode);
      assert.equal(observed.args.filter((arg) => arg.startsWith("--target-ubuntu=")).length, 1);
      if (ref) {
        assert.equal(observed.args[observed.args.indexOf("--ref") + 1], ref);
        assert.ok(details.command.includes(`/${ref}/install.sh`));
      } else {
        assert.ok(!observed.args.includes("--ref"));
      }
      assert.ok(!observed.args.includes("--skip-ubuntu-upgrade"));
      assert.ok(!details.command.includes("$(date +%s)"));
    });
  }
}

for (const [input, expected] of [
  ["ubuntu", "ubuntu"],
  ["admin", "admin"],
  ["bad user;false", "ubuntu"],
  ["root", "ubuntu"],
]) {
  test(`explicit target preserves target-user normalization: ${input}`, () => {
    const observed = observeInstaller(buildInstallCommand("safe", null, input));
    assert.equal(observed.user, expected);
    assert.equal(observed.target, ACFS_RECOMMENDED_UBUNTU);
  });
}

for (const selection of [
  { profile: "stack-only" },
  { onlyModules: ["lang.bun"] },
  { onlyPhases: ["languages"], noDeps: true },
  { skipModules: ["cloud.vercel"] },
] satisfies ModuleSelectionInput[]) {
  test(`explicit target preserves selector argv: ${JSON.stringify(selection)}`, () => {
    const details = buildInstallCommandDetails("safe", "main", "ubuntu", selection);
    const observed = observeInstaller(details.command);
    assert.equal(observed.target, ACFS_RECOMMENDED_UBUNTU);
    const expectedSelectors = details.selectorArgs.map((arg) => arg.replace(/^"|"$/g, ""));
    assert.deepEqual(observed.args.slice(-expectedSelectors.length), expectedSelectors);
    assert.equal(observed.args.includes("--no-deps"), selection.noDeps === true);
  });
}

test("invalid selectors still fail before any copyable install command exists", () => {
  assert.throws(
    () =>
      buildInstallCommand("vibe", null, "ubuntu", {
        onlyModules: ["lang.bun; --target-ubuntu=25.10"],
      }),
    /Unknown module/,
  );
});

test("personalized commands, handoff and retry artifacts use the same explicit destination", () => {
  const inputs = {
    ip: "203.0.113.42",
    os: "linux" as const,
    username: "admin",
    mode: "safe" as const,
    ref: "release/lts",
    moduleSelection: { onlyModules: ["lang.bun"] },
  };
  const command = buildInstallCommand(
    inputs.mode,
    inputs.ref,
    inputs.username,
    inputs.moduleSelection,
  );
  const installer = buildCommands(inputs).find((entry) => entry.id === "installer");
  const runbook = buildHandoffRunbook(inputs);
  const retry = runbook.recoveryCommands.find((entry) => entry.id === "rerun-installer");
  assert.equal(installer?.command, command);
  assert.equal(runbook.install.command, command);
  assert.equal(retry?.command, command);
  assert.ok(formatHandoffRunbookMarkdown(runbook).includes(command));
  assert.ok(!JSON.stringify(runbook).includes(inputs.ip));
  assert.equal(observeInstaller(retry!.command).target, "26.04");
});

test("profile review and import commands cannot fall back to the legacy installer target", () => {
  const profile = buildTeamProfile({
    ip: "",
    os: "mac",
    username: "admin",
    mode: "safe",
    ref: null,
    providerSelection: {
      providerId: "other",
      planName: "custom plan",
      ubuntuVersion: "24.04",
      region: "not-listed",
      targetAgents: 10,
      workloadId: "standard",
    },
    moduleSelection: { onlyModules: ["lang.bun"] },
  });
  const review = formatTeamProfileReviewMarkdown(profile);
  assert.ok(review.includes(`--target-ubuntu=${ACFS_RECOMMENDED_UBUNTU}`));
  const diff = buildTeamProfileImportDiff(profile, { ubuntuVersion: "24.04" });
  assert.equal(diff.ok, true, JSON.stringify(diff.findings));
  assert.ok(diff.installerCommand.command);
  const observed = observeInstaller(diff.installerCommand.command!);
  assert.equal(observed.target, "26.04");
  assert.equal(observed.args[observed.args.indexOf("--only") + 1], "lang.bun");
});
