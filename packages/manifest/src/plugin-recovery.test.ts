import { strict as assert } from "node:assert";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  linkSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import type { PluginInstallPlan } from "./plugin-plan.js";
import {
  detectPluginInstallTarget,
  executePluginInstallPlan,
  inspectPluginInstallPlan,
  PluginInstallError,
  type PluginInstallReceipt,
  recoverPluginInstallPlan,
} from "./plugin-runtime.js";

const integration = { skip: process.platform !== "linux" || process.getuid?.() === 0 };
const hash = (bytes: Buffer): string => createHash("sha256").update(bytes).digest("hex");
const refused =
  (code: string) =>
  (error: unknown): boolean =>
    error instanceof PluginInstallError && error.code === code;
function fixture() {
  const home = mkdtempSync(join(tmpdir(), "acfs-recovery-"));
  const sources = ["lib", "app"].map((name) =>
    Buffer.from(
      `set -eu\necho ${name} >> "$HOME/runs"\n` +
        (name === "app"
          ? 'echo $$ > "$HOME/worker.pid"\nwhile ! test -f "$HOME/release"; do sleep 0.05; done\n'
          : "") +
        `mkdir -p "$HOME/.local/bin"\nprintf '#!/bin/sh\\nexit 0\\n' > "$HOME/.local/bin/acfs_recover_${name}"\nchmod 755 "$HOME/.local/bin/acfs_recover_${name}"\n`,
    ),
  );
  const payload = {
    schema: "acfs.plugin-install-plan.v1" as const,
    package: {
      packageId: "example",
      version: "1.0.0",
      sourceCommit: "a".repeat(40),
      pluginSha256: "b".repeat(64),
    },
    target: detectPluginInstallTarget(),
    trust: { manifestSha256: "c".repeat(64), checksumsSha256: "d".repeat(64) },
    requested: ["plugin.example.app"],
    skipped: [],
    dependencyIds: ["plugin.example.lib"],
    prerequisites: [],
    actions: ["lib", "app"].map((name, index) => ({
      id: `plugin.example.${name}`,
      installer: {
        tool: name,
        url: `https://example.com/${name}.sh`,
        sha256: hash(sources[index]!),
        runner: "bash" as const,
        args: [],
      },
      verify: [`acfs_recover_${name}`],
    })),
  };
  const plan: PluginInstallPlan = {
    ...payload,
    planSha256: hash(Buffer.from(JSON.stringify(payload))),
  };
  const directory = join(home, ".acfs/plugin-installs");
  const path = join(directory, `${plan.planSha256}.json`);
  const lock = join(directory, "install.lock");
  const receipt: PluginInstallReceipt = {
    schema: "acfs.plugin-install-receipt.v1",
    planSha256: plan.planSha256,
    packageSha256: plan.package.pluginSha256,
    status: "running",
    updatedAt: new Date().toISOString(),
    executionProtocol: "inherited-lock-v1",
    actions: {
      "plugin.example.lib": { status: "complete", exitCode: 0 },
      "plugin.example.app": { status: "running", exitCode: null },
    },
  };
  const seed = (): void => {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    writeFileSync(lock, "", { mode: 0o600 });
    writeFileSync(path, JSON.stringify(receipt) + "\n", { mode: 0o600 });
  };
  const bytes = (): Buffer => readFileSync(path);
  const backup = (): string =>
    join(directory, `${plan.planSha256}.interrupted-${hash(bytes())}.json`);
  return { home, sources, plan, directory, path, lock, receipt, seed, bytes, backup };
}
async function eventually(
  predicate: () => Promise<boolean> | boolean,
  message: string,
): Promise<void> {
  const end = Date.now() + 8000;
  while (!(await predicate())) {
    if (Date.now() >= end) assert.fail(message);
    await new Promise<void>((done) => setTimeout(done, 25));
  }
}

test(
  "status on an unused home is read-only and never manufactures installation state",
  integration,
  async () => {
    const item = fixture();
    const before = readdirSync(item.home);
    const result = await inspectPluginInstallPlan(item.plan, item);
    assert.equal(result.status, "not_started");
    assert.equal(result.receipt, null);
    assert.equal(result.receiptSha256, null);
    assert.equal(result.healthChecked, false);
    assert.deepEqual(readdirSync(item.home), before);
  },
);

test(
  "status does not create a lock in an empty pre-existing state directory",
  integration,
  async () => {
    const item = fixture();
    mkdirSync(item.directory, { recursive: true, mode: 0o700 });
    assert.equal((await inspectPluginInstallPlan(item.plan, item)).status, "not_started");
    assert.deepEqual(readdirSync(item.directory), []);
  },
);

test(
  "status returns the exact receipt fingerprint without running health commands",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const before = item.bytes();
    const stat = statSync(item.path);
    const result = await inspectPluginInstallPlan(item.plan, item);
    assert.equal(result.status, "interrupted");
    assert.equal(result.recoveryEligible, true);
    assert.equal(result.receiptSha256, hash(before));
    assert.equal(result.healthChecked, false);
    assert.deepEqual(item.bytes(), before);
    assert.equal(statSync(item.path).ino, stat.ino);
    assert.equal(statSync(item.path).mtimeMs, stat.mtimeMs);
    assert.equal(existsSync(join(item.home, "runs")), false);
  },
);

test(
  "a recorded complete receipt is historical status, not a new health check",
  integration,
  async () => {
    const item = fixture();
    item.receipt.status = "complete";
    item.receipt.actions["plugin.example.app"] = { status: "complete", exitCode: 0 };
    item.seed();
    const result = await inspectPluginInstallPlan(item.plan, item);
    assert.equal(result.status, "complete");
    assert.equal(result.healthChecked, false);
    assert.equal(result.recoveryEligible, false);
    assert.equal(existsSync(join(item.home, ".local")), false);
  },
);

test(
  "incomplete finalization with no running action does not authorize interruption recovery",
  integration,
  async () => {
    const item = fixture();
    item.receipt.actions["plugin.example.app"] = { status: "complete", exitCode: 0 };
    item.seed();
    const result = await inspectPluginInstallPlan(item.plan, item);
    assert.equal(result.status, "incomplete");
    assert.equal(result.recoveryEligible, false);
    await assert.rejects(
      recoverPluginInstallPlan(item.plan, hash(item.bytes()), item),
      refused("plugin_recovery_not_needed"),
    );
  },
);

test(
  "legacy interrupted records remain inspectable but cannot assume inherited locking",
  integration,
  async () => {
    const item = fixture();
    delete item.receipt.executionProtocol;
    item.seed();
    const before = item.bytes();
    const result = await inspectPluginInstallPlan(item.plan, item);
    assert.equal(result.status, "interrupted");
    assert.equal(result.recoveryEligible, false);
    await assert.rejects(
      recoverPluginInstallPlan(item.plan, result.receiptSha256!, item),
      refused("plugin_recovery_unsupported"),
    );
    assert.deepEqual(item.bytes(), before);
    assert.equal(readdirSync(item.directory).length, 2);
  },
);

test(
  "recovery preserves original bytes and makes only interrupted actions retryable",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const before = item.bytes();
    const result = await recoverPluginInstallPlan(item.plan, hash(before), item);
    assert.deepEqual(result.retryModuleIds, ["plugin.example.app"]);
    assert.equal(result.previousReceiptSha256, hash(before));
    assert.deepEqual(readFileSync(join(item.directory, result.preservedReceipt)), before);
    assert.equal(statSync(join(item.directory, result.preservedReceipt)).mode & 0o777, 0o600);
    assert.equal(result.receipt.status, "failed");
    assert.equal(result.receipt.actions["plugin.example.app"]!.status, "failed");
    assert.equal(
      result.receipt.actions["plugin.example.app"]!.exitCode,
      null,
      "an unknown exit must not be invented",
    );
    assert.deepEqual(result.receipt.actions["plugin.example.lib"], {
      status: "complete",
      exitCode: 0,
    });
    assert.equal(result.receipt.recoveredFrom, hash(before));
    assert.equal(
      existsSync(join(item.home, "runs")),
      false,
      "recovery must not execute an installer",
    );
    assert.equal((await inspectPluginInstallPlan(item.plan, item)).status, "failed");
  },
);

for (const digest of ["", "g".repeat(64), "f".repeat(64)]) {
  test(
    `recovery refuses missing malformed or stale approval ${digest.slice(0, 4)}`,
    integration,
    async () => {
      const item = fixture();
      item.seed();
      const before = item.bytes();
      await assert.rejects(
        recoverPluginInstallPlan(item.plan, digest, item),
        refused("plugin_receipt_changed"),
      );
      assert.deepEqual(item.bytes(), before);
      assert.equal(readdirSync(item.directory).length, 2);
    },
  );
}

test(
  "inspection fingerprints become invalid as soon as another writer changes the receipt",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const seen = await inspectPluginInstallPlan(item.plan, item);
    item.receipt.updatedAt = "2026-09-17T00:00:00.000Z";
    writeFileSync(item.path, JSON.stringify(item.receipt));
    const current = item.bytes();
    await assert.rejects(
      recoverPluginInstallPlan(item.plan, seen.receiptSha256!, item),
      refused("plugin_receipt_changed"),
    );
    assert.deepEqual(item.bytes(), current);
  },
);

test(
  "an already preserved matching snapshot supports retry after a backup-only crash",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const before = item.bytes();
    writeFileSync(item.backup(), before, { mode: 0o600 });
    assert.equal(
      (await recoverPluginInstallPlan(item.plan, hash(before), item)).receipt.status,
      "failed",
    );
    assert.equal(
      readdirSync(item.directory).filter((name) => name.includes(".interrupted-")).length,
      1,
    );
  },
);

for (const kind of ["different", "symlink", "hardlink"]) {
  test(`recovery refuses unsafe preserved evidence: ${kind}`, integration, async () => {
    const item = fixture();
    item.seed();
    const before = item.bytes();
    if (kind === "different") writeFileSync(item.backup(), "existing-evidence", { mode: 0o600 });
    if (kind === "symlink") symlinkSync(item.path, item.backup());
    if (kind === "hardlink") {
      const other = join(item.home, "evidence");
      writeFileSync(other, before, { mode: 0o600 });
      linkSync(other, item.backup());
    }
    await assert.rejects(recoverPluginInstallPlan(item.plan, hash(before), item));
    assert.deepEqual(item.bytes(), before);
  });
}

for (const kind of ["duplicate", "secret-field", "truncated", "protocol", "timestamp"]) {
  test(
    `status and recovery reject malformed receipt without exposing it: ${kind}`,
    integration,
    async () => {
      const item = fixture();
      item.seed();
      let text = JSON.stringify(item.receipt);
      if (kind === "duplicate") text = text.replace("{", '{"status":"complete",');
      if (kind === "secret-field") text = text.replace("{", '{"stdout":"SECRET_TEST_VALUE",');
      if (kind === "truncated") text = text.slice(0, -3);
      if (kind === "protocol") text = text.replace("inherited-lock-v1", "unreviewed-protocol");
      if (kind === "timestamp")
        text = text.replace(item.receipt.updatedAt, "2026-02-30T00:00:00.000Z");
      writeFileSync(item.path, text);
      const before = item.bytes();
      for (const action of [
        () => inspectPluginInstallPlan(item.plan, item),
        () => recoverPluginInstallPlan(item.plan, hash(before), item),
      ]) {
        await assert.rejects(action(), (error: unknown) => {
          assert.ok(error instanceof PluginInstallError);
          assert.equal(error.code, "plugin_state_invalid");
          assert.ok(!error.message.includes("SECRET_TEST_VALUE"));
          return true;
        });
      }
      assert.deepEqual(item.bytes(), before);
    },
  );
}

test(
  "status and recovery refuse unsafe state rather than repairing its permissions",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const digest = hash(item.bytes());
    chmodSync(item.directory, 0o777);
    await assert.rejects(inspectPluginInstallPlan(item.plan, item), refused("plugin_state_unsafe"));
    await assert.rejects(
      recoverPluginInstallPlan(item.plan, digest, item),
      refused("plugin_state_unsafe"),
    );
    assert.equal(statSync(item.directory).mode & 0o777, 0o777);
  },
);

test("recovery with no receipt never creates state", integration, async () => {
  const item = fixture();
  await assert.rejects(
    recoverPluginInstallPlan(item.plan, "a".repeat(64), item),
    refused("plugin_recovery_not_needed"),
  );
  assert.equal(existsSync(item.directory), false);
});

test("cancelled recovery leaves the receipt and directory unchanged", integration, async () => {
  const item = fixture();
  item.seed();
  const before = item.bytes();
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    recoverPluginInstallPlan(item.plan, hash(before), {
      home: item.home,
      signal: controller.signal,
    }),
  );
  assert.deepEqual(item.bytes(), before);
  assert.equal(readdirSync(item.directory).length, 2);
});

test("exactly one caller can consume an inspected recovery approval", integration, async () => {
  const item = fixture();
  item.seed();
  const digest = hash(item.bytes());
  const results = await Promise.allSettled([
    recoverPluginInstallPlan(item.plan, digest, item),
    recoverPluginInstallPlan(item.plan, digest, item),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  assert.equal(
    readdirSync(item.directory).filter((name) => name.includes(".interrupted-")).length,
    1,
  );
});

test(
  "real parent death stays busy until orphan exit, then recovers and resumes without replaying dependencies",
  integration,
  async () => {
    const item = fixture();
    const url = new URL(
      `./plugin-runtime${extname(fileURLToPath(import.meta.url))}`,
      import.meta.url,
    ).href;
    const code = `import {executePluginInstallPlan} from ${JSON.stringify(url)};
    const scripts=${JSON.stringify(item.sources.map((bytes) => bytes.toString()))};
    await executePluginInstallPlan(${JSON.stringify(item.plan)}, {home:${JSON.stringify(item.home)}, timeoutSeconds:10,
      download:async(action)=>Buffer.from(scripts[action.id.endsWith('.lib')?0:1])});`;
    const child = spawn(
      process.execPath,
      process.versions.bun ? ["--eval", code] : ["--input-type=module", "--eval", code],
      { stdio: "ignore" },
    );
    const exited = new Promise<void>((done) => child.once("close", () => done()));
    try {
      await eventually(() => existsSync(join(item.home, "worker.pid")), "installer did not start");
      child.kill("SIGKILL");
      await exited;
      const busy = await inspectPluginInstallPlan(item.plan, item);
      assert.equal(busy.status, "busy");
      assert.equal(busy.recoveryEligible, false);
      assert.equal(busy.receiptSha256, null);
      await assert.rejects(
        recoverPluginInstallPlan(item.plan, hash(item.bytes()), item),
        refused("plugin_install_busy"),
      );
      writeFileSync(join(item.home, "release"), "continue");
      await eventually(
        async () => (await inspectPluginInstallPlan(item.plan, item)).status === "interrupted",
        "orphan did not exit",
      );
      const inspected = await inspectPluginInstallPlan(item.plan, item);
      const original = item.bytes();
      const recovered = await recoverPluginInstallPlan(item.plan, inspected.receiptSha256!, item);
      assert.deepEqual(recovered.retryModuleIds, ["plugin.example.app"]);
      assert.deepEqual(readFileSync(join(item.directory, recovered.preservedReceipt)), original);
      const final = await executePluginInstallPlan(item.plan, {
        home: item.home,
        download: async (action) => item.sources[action.id.endsWith(".lib") ? 0 : 1]!,
      });
      assert.equal(final.status, "complete");
      assert.equal(readFileSync(join(item.home, "runs"), "utf8"), "lib\napp\napp\n");
    } finally {
      writeFileSync(join(item.home, "release"), "continue");
      child.kill("SIGKILL");
      await exited;
    }
  },
);

test(
  "status and recovery recheck host and plan fingerprints before inspecting state",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    const before = item.bytes();
    const digest = hash(before);
    const changedPlan = structuredClone(item.plan);
    changedPlan.actions[0]!.installer.args.push("unreviewed");
    const changedTarget = structuredClone(item.plan);
    changedTarget.target.version = "unreviewed";
    for (const [plan, code] of [
      [changedPlan, "plugin_plan_changed"],
      [changedTarget, "plugin_target_unsupported"],
    ] as const) {
      await assert.rejects(inspectPluginInstallPlan(plan, item), refused(code));
      await assert.rejects(recoverPluginInstallPlan(plan, digest, item), refused(code));
    }
    assert.deepEqual(item.bytes(), before);
    assert.equal(readdirSync(item.directory).length, 2);
  },
);

test(
  "status and recovery reject empty and oversized receipts without changing them",
  integration,
  async () => {
    const item = fixture();
    item.seed();
    for (const bytes of [Buffer.alloc(0), Buffer.alloc(1024 * 1024 + 1, 32)]) {
      writeFileSync(item.path, bytes);
      await assert.rejects(
        inspectPluginInstallPlan(item.plan, item),
        refused("plugin_state_invalid"),
      );
      await assert.rejects(
        recoverPluginInstallPlan(item.plan, hash(bytes), item),
        refused("plugin_state_invalid"),
      );
      assert.deepEqual(item.bytes(), bytes);
    }
  },
);

test("root cannot use inspection or recovery to create or alter user state", {
  skip: process.getuid?.() !== 0,
}, async () => {
  const item = fixture();
  await assert.rejects(
    inspectPluginInstallPlan(item.plan, item),
    refused("plugin_root_execution_refused"),
  );
  await assert.rejects(
    recoverPluginInstallPlan(item.plan, "a".repeat(64), item),
    refused("plugin_root_execution_refused"),
  );
  assert.equal(existsSync(item.directory), false);
});
