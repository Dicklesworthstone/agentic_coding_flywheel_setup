import { strict as assert } from "node:assert";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  parsePluginInstallArguments,
  pluginInstallMain,
  type PluginInstallCommandServices,
} from "./plugin-install.js";
import { buildPluginInstallPlan, type PluginInstallPlan } from "./plugin-plan.js";
import {
  checkPluginInstallPlan,
  detectPluginInstallTarget,
  executePluginInstallPlan,
  PluginInstallError,
  type PluginInstallHealth,
} from "./plugin-runtime.js";

const script = Buffer.from('set -eu\nmkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\nexit 0\\n" > "$HOME/.local/bin/acfs_health_cli"\nchmod 755 "$HOME/.local/bin/acfs_health_cli"\n');
function makePlan(): PluginInstallPlan {
  return buildPluginInstallPlan({
    modules: [{
      id: "plugin.health.cli", phase: 6, run_as: "target_user", enabled_by_default: false,
      dependencies: ["base.system"], install: [],
      verify: ["command -v -- acfs_health_cli >/dev/null 2>&1"],
      plugin: { packageId: "health", version: "1.0.0", sourceCommit: "a".repeat(40), pluginSha256: "b".repeat(64) },
      verified_installer: { tool: "tool", url: "https://example.com/install.sh", runner: "bash" },
    }],
    firstPartyModules: [{ id: "base.system", phase: 1, verify: ["command -v bash"] }],
    installers: { tool: { url: "https://example.com/install.sh", sha256: createHash("sha256").update(script).digest("hex") } },
    trust: { manifestSha256: "c".repeat(64), checksumsSha256: "d".repeat(64) },
    target: detectPluginInstallTarget(), only: ["plugin.health.cli"],
  });
}
function args(plan: PluginInstallPlan): string[] {
  const { os, version, arch, libc } = plan.target;
  return ["--archive", "reviewed.tar.gz", "--review", "trusted.json", "--target", `${os}/${version}/${arch}/${libc}`, "--only", "plugin.health.cli"];
}
function healthy(plan: PluginInstallPlan): PluginInstallHealth {
  return {
    schema: "acfs.plugin-install-health.v1", planSha256: plan.planSha256,
    receiptSha256: "e".repeat(64), receiptStatus: "complete", status: "healthy", healthChecked: true,
    prerequisites: [{ id: "base.system", passed: true }],
    actions: [{ id: "plugin.health.cli", recordedStatus: "complete", passed: true }],
  };
}
function harness(plan = makePlan()) {
  const output: string[] = [];
  const calls: string[] = [];
  const never = async (): Promise<never> => {
    calls.push("mutation");
    throw new Error("Mutation must not run during health checking");
  };
  const services: PluginInstallCommandServices = {
    loadPlan: async () => { calls.push("load"); return plan; },
    check: async (value, signal) => {
      assert.equal(value, plan);
      assert.equal(signal.aborted, false);
      calls.push("check");
      return healthy(plan);
    },
    execute: never, executeCached: never, prepareCache: never, recover: never,
    write: (message) => output.push(message),
  };
  return { plan, output, calls, services };
}

test("--check is explicit, independent and rejects every conflicting operation", () => {
  const base = args(makePlan());
  assert.equal(parsePluginInstallArguments(base).check, false);
  const parsed = parsePluginInstallArguments([...base, "--check"]);
  assert.equal(parsed.check, true);
  assert.equal(parsed.apply, false);
  assert.equal(parsed.status, false);
  assert.equal(parsed.recover, false);
  for (const conflict of [
    ["--check"], ["--status"], ["--dry-run"], ["--recover"], ["--yes"],
    ["--accept-plan", "f".repeat(64)], ["--accept-receipt", "f".repeat(64)],
    ["--yes", "--accept-plan", "f".repeat(64)],
    ["--prepare-cache", "cache"], ["--installer-cache", "cache"],
  ]) {
    assert.throws(() => parsePluginInstallArguments([...base, "--check", ...conflict]), Error, conflict.join(" "));
  }
});

test("health output reloads the plan and cannot dispatch an installer or recovery", async () => {
  const item = harness();
  const code = await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services);
  assert.equal(code, 0);
  assert.deepEqual(item.calls, ["load", "check"]);
  assert.equal(item.output.length, 1);
  const result = JSON.parse(item.output[0]!);
  assert.equal(result.status, "checked");
  assert.equal(result.mode, "check");
  assert.equal(result.health.status, "healthy");
  assert.equal(result.receipt, undefined);
});

test("default preview and --status never implicitly opt into health commands", async () => {
  const item = harness();
  item.services.inspect = async () => ({
    schema: "acfs.plugin-install-status.v1", planSha256: item.plan.planSha256,
    status: "not_started", receiptSha256: null, receipt: null, recoveryEligible: false, healthChecked: false,
  });
  assert.equal(await pluginInstallMain([...args(item.plan), "--json"], item.services), 0);
  assert.equal(JSON.parse(item.output[0]!).status, "planned");
  assert.equal(await pluginInstallMain([...args(item.plan), "--status", "--json"], item.services), 0);
  assert.equal(JSON.parse(item.output[1]!).status, "inspected");
  assert.deepEqual(item.calls, ["load", "load"]);
});

test("unhealthy, incomplete and unprobed states all return a nonzero exit", async () => {
  for (const status of ["unhealthy", "incomplete", "busy", "interrupted", "not_started"] as const) {
    const item = harness();
    const health = healthy(item.plan);
    health.status = status;
    if (status === "unhealthy") health.actions[0]!.passed = false;
    else if (status === "incomplete") {
      health.receiptStatus = "failed";
      health.actions[0]!.recordedStatus = "failed";
    } else {
      health.receiptStatus = status;
      health.healthChecked = false;
      health.actions = [];
      health.prerequisites = [];
      health.receiptSha256 = status === "interrupted" ? "e".repeat(64) : null;
    }
    item.services.check = async () => health;
    assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1, status);
    const result = JSON.parse(item.output[0]!);
    assert.equal(result.status, "checked");
    assert.equal(result.health.status, status);
    assert.deepEqual(item.calls, ["load"]);
  }
});

test("inconsistent or incomplete health evidence cannot claim success", async () => {
  const mutations: Array<(value: PluginInstallHealth) => void> = [
    (value) => { value.planSha256 = "f".repeat(64); },
    (value) => { value.receiptSha256 = null; },
    (value) => { value.healthChecked = false; },
    (value) => { value.actions = []; },
    (value) => { value.prerequisites = []; },
    (value) => { value.actions.push({ ...value.actions[0]! }); },
    (value) => { value.actions[0]!.id = "plugin.other.cli"; },
    (value) => { value.prerequisites[0]!.id = "base.other"; },
    (value) => { value.actions[0]!.passed = false; },
    (value) => { value.prerequisites[0]!.passed = false; },
    (value) => { value.actions[0]!.recordedStatus = "failed"; },
    (value) => { value.receiptStatus = "failed"; },
    (value) => { value.status = "busy"; },
  ];
  for (const mutate of mutations) {
    const item = harness();
    const health = healthy(item.plan);
    mutate(health);
    item.services.check = async () => health;
    assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1);
    assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_state_invalid");
    assert.deepEqual(item.calls, ["load"]);
  }
});

test("an unavailable health service fails closed instead of selecting another operation", async () => {
  const item = harness();
  item.services.check = undefined;
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_operation_unavailable");
  assert.deepEqual(item.calls, ["load"]);
});

test("trust validation failures prevent health checks and do not leak raw exception text", async () => {
  const item = harness();
  item.services.loadPlan = async () => { throw new Error("SECRET_REVIEW_PATH"); };
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1);
  assert.deepEqual(item.calls, []);
  assert.equal(item.output.join("\n").includes("SECRET_REVIEW_PATH"), false);
});

test("human output identifies failed modules and states the limits of executable checks", async () => {
  const item = harness();
  item.services.check = async () => {
    const value = healthy(item.plan);
    value.status = "unhealthy";
    value.actions[0]!.passed = false;
    value.prerequisites[0]!.passed = false;
    return value;
  };
  assert.equal(await pluginInstallMain([...args(item.plan), "--check"], item.services), 1);
  assert.match(item.output[0]!, /Prerequisite failed: base.system/);
  assert.match(item.output[0]!, /Executable check failed: plugin.health.cli/);
  assert.match(item.output[0]!, /not version, authentication or end-to-end functionality/);
});

test("SIGTERM during checking cannot emit a healthy result or leak signal listeners", async () => {
  const item = harness();
  const before = [process.listenerCount("SIGINT"), process.listenerCount("SIGTERM")];
  item.services.check = async () => {
    process.emit("SIGTERM");
    return healthy(item.plan);
  };
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 143);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_install_cancelled");
  assert.deepEqual([process.listenerCount("SIGINT"), process.listenerCount("SIGTERM")], before);
});

test("health deadlines have a stable diagnostic and never report installation completion", async () => {
  const item = harness();
  item.services.check = async () => { throw new PluginInstallError("plugin_health_timeout", "Total deadline exceeded"); };
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_health_timeout");
});

test("CLI health dispatch detects real installed-binary drift while preserving the receipt", {
  skip: process.getuid!() === 0 ? "Run real execution test as an unprivileged Linux user" : false,
}, async () => {
  const item = harness();
  const home = mkdtempSync(join(tmpdir(), "acfs-health-cli-"));
  await executePluginInstallPlan(item.plan, { home, download: async () => script });
  const path = join(home, ".acfs/plugin-installs", `${item.plan.planSha256}.json`);
  const before = readFileSync(path);
  item.services.check = (plan, signal) => checkPluginInstallPlan(plan, { home, signal });
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 0);
  renameSync(join(home, ".local/bin/acfs_health_cli"), join(home, ".local/bin/acfs_health_cli.saved"));
  assert.equal(await pluginInstallMain([...args(item.plan), "--check", "--json"], item.services), 1);
  assert.equal(JSON.parse(item.output[1]!).health.status, "unhealthy");
  assert.deepEqual(readFileSync(path), before);
  assert.deepEqual(item.calls, ["load", "load"]);
});
