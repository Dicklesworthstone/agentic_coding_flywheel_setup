import { strict as assert } from "node:assert";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { buildPluginInstallPlan, type PlannablePluginModule } from "./plugin-plan.js";
import {
  checkPluginInstallPlan,
  detectPluginInstallTarget,
  executePluginInstallPlan,
  inspectPluginInstallPlan,
  PluginInstallError,
  type PluginInstallReceipt,
} from "./plugin-runtime.js";

const integration = {
  skip: process.getuid!() === 0 ? "Run real execution tests as an unprivileged Linux user" : false,
};
const rejected = (code: string) => (error: unknown): boolean =>
  error instanceof PluginInstallError && error.code === code;

function fixture(check = "command -v bash") {
  const home = mkdtempSync(join(tmpdir(), "acfs-plugin-health-"));
  const sources = [0, 1].map((index) => Buffer.from(
    `set -eu\nmkdir -p "$HOME/.local/bin"\n` +
    `printf '#!/bin/sh\\ntouch "$HOME/binary-was-executed"\\n' > "$HOME/.local/bin/acfs_health_${index}"\n` +
    `chmod 755 "$HOME/.local/bin/acfs_health_${index}"\n` +
    `printf '${index}\\n' >> "$HOME/install-order"\n`,
  ));
  const modules: PlannablePluginModule[] = sources.map((_, index) => ({
    id: `plugin.health.tool${index}`,
    phase: 6,
    run_as: "target_user",
    enabled_by_default: false,
    dependencies: index ? ["plugin.health.tool0"] : ["base.system"],
    install: [],
    verify: [`command -v -- acfs_health_${index} >/dev/null 2>&1`],
    plugin: {
      packageId: "health", version: "1.0.0", sourceCommit: "a".repeat(40),
      pluginSha256: "b".repeat(64),
    },
    verified_installer: {
      tool: `tool${index}`, url: `https://example.com/install${index}.sh`, runner: "bash",
    },
  }));
  const plan = buildPluginInstallPlan({
    modules,
    firstPartyModules: [{ id: "base.system", phase: 1, verify: [check] }],
    installers: Object.fromEntries(sources.map((bytes, index) => [
      `tool${index}`,
      { url: `https://example.com/install${index}.sh`, sha256: createHash("sha256").update(bytes).digest("hex") },
    ])),
    target: detectPluginInstallTarget(),
    trust: { manifestSha256: "c".repeat(64), checksumsSha256: "d".repeat(64) },
    only: ["plugin.health.tool1"],
  });
  let downloads = 0;
  const download = async (action: { id: string }): Promise<Buffer> => {
    downloads++;
    return sources[Number(action.id.at(-1))]!;
  };
  const path = join(home, ".acfs/plugin-installs", `${plan.planSha256}.json`);
  const receipt = (): PluginInstallReceipt => JSON.parse(readFileSync(path, "utf8"));
  return { home, plan, path, download, count: () => downloads, receipt };
}

function unchanged(item: ReturnType<typeof fixture>) {
  const bytes = readFileSync(item.path);
  const before = statSync(item.path);
  const order = readFileSync(join(item.home, "install-order"), "utf8");
  const downloads = item.count();
  return (): void => {
    assert.deepEqual(readFileSync(item.path), bytes);
    assert.equal(statSync(item.path).mtimeMs, before.mtimeMs);
    assert.equal(statSync(item.path).ino, before.ino);
    assert.equal(readFileSync(join(item.home, "install-order"), "utf8"), order);
    assert.equal(item.count(), downloads);
    assert.equal(existsSync(join(item.home, "binary-was-executed")), false);
  };
}

test("health refuses root without creating state or downloading", { skip: process.getuid!() !== 0 }, async () => {
  const item = fixture();
  await assert.rejects(checkPluginInstallPlan(item.plan, item), rejected("plugin_root_execution_refused"));
  assert.equal(existsSync(join(item.home, ".acfs")), false);
  assert.equal(item.count(), 0);
});

test("not-started checks do not create directories or a lock", integration, async () => {
  const item = fixture('touch "$HOME/check-executed"');
  const health = await checkPluginInstallPlan(item.plan, item);
  assert.equal(health.status, "not_started");
  assert.equal(health.healthChecked, false);
  assert.equal(health.receiptSha256, null);
  assert.deepEqual(health.actions, []);
  assert.equal(existsSync(join(item.home, ".acfs")), false);
  assert.equal(existsSync(join(item.home, "check-executed")), false);
});

test("a real completed installation is checked without state writes or installer calls", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  const verifyUnchanged = unchanged(item);
  const health = await checkPluginInstallPlan(item.plan, item);
  assert.equal(health.status, "healthy");
  assert.equal(health.receiptStatus, "complete");
  assert.equal(health.healthChecked, true);
  assert.equal(health.receiptSha256, createHash("sha256").update(readFileSync(item.path)).digest("hex"));
  assert.deepEqual(health.prerequisites, [{ id: "base.system", passed: true }]);
  assert.deepEqual(health.actions, [
    { id: "plugin.health.tool0", recordedStatus: "complete", passed: true },
    { id: "plugin.health.tool1", recordedStatus: "complete", passed: true },
  ]);
  verifyUnchanged();
});

test("a stale success receipt does not conceal missing plugin executables", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  renameSync(join(item.home, ".local/bin/acfs_health_0"), join(item.home, ".local/bin/acfs_health_0.saved"));
  const verifyUnchanged = unchanged(item);
  assert.equal((await inspectPluginInstallPlan(item.plan, item)).status, "complete");
  const health = await checkPluginInstallPlan(item.plan, item);
  assert.equal(health.status, "unhealthy");
  assert.equal(health.actions[0]!.passed, false);
  assert.equal(health.actions[1]!.passed, true);
  verifyUnchanged();
});

test("first-party prerequisite drift is reported without repairing anything", integration, async () => {
  const item = fixture('test -f "$HOME/prerequisite"');
  writeFileSync(join(item.home, "prerequisite"), "ready");
  await executePluginInstallPlan(item.plan, item);
  renameSync(join(item.home, "prerequisite"), join(item.home, "prerequisite.saved"));
  const verifyUnchanged = unchanged(item);
  const health = await checkPluginInstallPlan(item.plan, item);
  assert.equal(health.status, "unhealthy");
  assert.deepEqual(health.prerequisites, [{ id: "base.system", passed: false }]);
  assert.equal(health.actions.every((action) => action.passed), true);
  verifyUnchanged();
});

test("binary existence cannot promote an incomplete or failed receipt", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  for (const status of ["pending", "failed"] as const) {
    const receipt = item.receipt();
    receipt.status = status;
    receipt.actions["plugin.health.tool1"] = { status, exitCode: status === "failed" ? 17 : null };
    writeFileSync(item.path, JSON.stringify(receipt) + "\n");
    const verifyUnchanged = unchanged(item);
    const health = await checkPluginInstallPlan(item.plan, item);
    assert.equal(health.status, "incomplete");
    assert.equal(health.receiptStatus, status);
    assert.equal(health.healthChecked, true);
    assert.equal(health.actions.every((action) => action.passed), true);
    verifyUnchanged();
  }
});

test("interrupted receipts are not probed or recovered implicitly", integration, async () => {
  const item = fixture('test ! -f "$HOME/forbid-check"');
  await executePluginInstallPlan(item.plan, item);
  writeFileSync(join(item.home, "forbid-check"), "checking would fail");
  const receipt = item.receipt();
  receipt.status = "running";
  receipt.actions["plugin.health.tool1"] = { status: "running", exitCode: null };
  writeFileSync(item.path, JSON.stringify(receipt) + "\n");
  const verifyUnchanged = unchanged(item);
  const health = await checkPluginInstallPlan(item.plan, item);
  assert.equal(health.status, "interrupted");
  assert.equal(health.healthChecked, false);
  assert.deepEqual(health.prerequisites, []);
  assert.deepEqual(health.actions, []);
  verifyUnchanged();
});

test("a real competing flock prevents health checks without stealing the lock", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  const verifyUnchanged = unchanged(item);
  const child = spawn("/usr/bin/flock", [
    "--exclusive", join(item.home, ".acfs/plugin-installs/install.lock"),
    "/bin/sh", "-c", "printf ready; read line",
  ], { stdio: ["pipe", "pipe", "ignore"] });
  const closed = new Promise<void>((accept, reject) => {
    child.once("error", reject);
    child.once("close", (code) => code === 0 ? accept() : reject(new Error(`flock exited ${code}`)));
  });
  try {
    await new Promise<void>((accept, reject) => {
      child.stdout!.once("data", () => accept());
      child.once("error", reject);
    });
    const health = await checkPluginInstallPlan(item.plan, item);
    assert.equal(health.status, "busy");
    assert.equal(health.healthChecked, false);
    assert.equal(health.receiptSha256, null);
    verifyUnchanged();
  } finally {
    child.stdin!.end("done\n");
    await closed;
  }
  assert.equal((await checkPluginInstallPlan(item.plan, item)).status, "healthy");
});

test("malformed, unsafe and lockless receipts fail closed and preserve bytes", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  const original = readFileSync(item.path);
  writeFileSync(item.path, '{"broken":');
  await assert.rejects(checkPluginInstallPlan(item.plan, item), rejected("plugin_state_invalid"));
  assert.equal(readFileSync(item.path, "utf8"), '{"broken":');
  writeFileSync(item.path, original);
  chmodSync(item.path, 0o644);
  await assert.rejects(checkPluginInstallPlan(item.plan, item), rejected("plugin_state_unsafe"));
  assert.deepEqual(readFileSync(item.path), original);
  chmodSync(item.path, 0o600);
  const lock = join(item.home, ".acfs/plugin-installs/install.lock");
  renameSync(lock, lock + ".saved");
  await assert.rejects(checkPluginInstallPlan(item.plan, item), rejected("plugin_state_unsafe"));
  assert.equal(existsSync(lock), false);
  assert.deepEqual(readFileSync(item.path), original);
});

test("an aborted health request produces no result or state writes", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  const verifyUnchanged = unchanged(item);
  const controller = new AbortController();
  controller.abort(new Error("cancelled"));
  await assert.rejects(checkPluginInstallPlan(item.plan, { home: item.home, signal: controller.signal }), /cancelled/);
  verifyUnchanged();
});

test("total deadline cancels slow checks and releases the lease without success", integration, async () => {
  const item = fixture('test ! -f "$HOME/slow" || sleep 10');
  await executePluginInstallPlan(item.plan, item);
  writeFileSync(join(item.home, "slow"), "yes");
  const verifyUnchanged = unchanged(item);
  await assert.rejects(checkPluginInstallPlan(item.plan, { home: item.home, timeoutSeconds: 1 }), rejected("plugin_health_timeout"));
  verifyUnchanged();
  renameSync(join(item.home, "slow"), join(item.home, "slow.saved"));
  assert.equal((await checkPluginInstallPlan(item.plan, item)).status, "healthy");
});

test("receipt changes during canonical verification prevent a healthy result", integration, async () => {
  const item = fixture('test ! -f "$HOME/change-receipt" || printf " " >> "$HOME"/.acfs/plugin-installs/*.json');
  await executePluginInstallPlan(item.plan, item);
  const before = readFileSync(item.path, "utf8");
  writeFileSync(join(item.home, "change-receipt"), "yes");
  await assert.rejects(checkPluginInstallPlan(item.plan, item), rejected("plugin_state_invalid"));
  assert.equal(readFileSync(item.path, "utf8"), before + " ");
  assert.equal(item.count(), 2);
});

test("changed plans and invalid deadlines are refused before checks", integration, async () => {
  const item = fixture();
  await executePluginInstallPlan(item.plan, item);
  const verifyUnchanged = unchanged(item);
  await assert.rejects(checkPluginInstallPlan({ ...item.plan, planSha256: "f".repeat(64) }, item), rejected("plugin_plan_changed"));
  for (const timeoutSeconds of [0, 601, 0.5, NaN]) {
    await assert.rejects(checkPluginInstallPlan(item.plan, { home: item.home, timeoutSeconds }), rejected("plugin_timeout_invalid"));
  }
  verifyUnchanged();
});
