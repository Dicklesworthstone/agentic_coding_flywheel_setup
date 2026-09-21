import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  loadPluginInstallPlan,
  type PluginInstallCommandServices,
  parsePluginInstallArguments,
  pluginInstallMain,
} from "./plugin-install.js";
import { buildPluginInstallPlan, type PluginPlanInput } from "./plugin-plan.js";
import type { PluginInstallReceipt } from "./plugin-runtime.js";

const base = [
  "--archive",
  "package.tar.gz",
  "--review",
  "review.json",
  "--target",
  "ubuntu/26.04/x86_64/glibc",
  "--only",
  "plugin.example.cli",
];
function fixture() {
  const input: PluginPlanInput = {
    modules: [
      {
        id: "plugin.example.cli",
        phase: 6,
        run_as: "target_user",
        enabled_by_default: false,
        dependencies: [],
        install: [],
        verify: ["command -v -- example >/dev/null 2>&1"],
        plugin: {
          packageId: "example",
          version: "1.0.0",
          sourceCommit: "a".repeat(40),
          pluginSha256: "b".repeat(64),
        },
        verified_installer: {
          tool: "example",
          url: "https://example.com/install.sh",
          runner: "bash",
        },
      },
    ],
    firstPartyModules: [],
    installers: { example: { url: "https://example.com/install.sh", sha256: "c".repeat(64) } },
    target: { os: "ubuntu", version: "26.04", arch: "x86_64", libc: "glibc" },
    trust: { manifestSha256: "d".repeat(64), checksumsSha256: "e".repeat(64) },
    only: ["plugin.example.cli"],
  };
  const plan = buildPluginInstallPlan(input);
  const output: string[] = [];
  let executions = 0;
  let loads = 0;
  const receipt: PluginInstallReceipt = {
    schema: "acfs.plugin-install-receipt.v1",
    planSha256: plan.planSha256,
    packageSha256: plan.package.pluginSha256,
    status: "complete",
    updatedAt: new Date().toISOString(),
    actions: { "plugin.example.cli": { status: "complete", exitCode: 0 } },
  };
  const services: PluginInstallCommandServices = {
    loadPlan: async () => {
      loads++;
      return plan;
    },
    execute: async () => {
      executions++;
      return receipt;
    },
    write: (message) => output.push(message),
  };
  return { plan, receipt, services, output, executions: () => executions, loads: () => loads };
}

test("default command and explicit dry-run only return a plan", async () => {
  for (const extra of [[], ["--dry-run"]]) {
    const item = fixture();
    assert.equal(await pluginInstallMain([...base, ...extra, "--json"], item.services), 0);
    assert.equal(item.loads(), 1);
    assert.equal(item.executions(), 0);
    const output = JSON.parse(item.output[0]!);
    assert.equal(output.status, "planned");
    assert.equal(output.mode, "dry-run");
    assert.equal(output.plan.planSha256, item.plan.planSha256);
  }
});

test("execution requires both explicit consent and the freshly recomputed plan fingerprint", async () => {
  const item = fixture();
  assert.equal(
    await pluginInstallMain(
      [...base, "--yes", "--accept-plan", item.plan.planSha256, "--json"],
      item.services,
    ),
    0,
  );
  assert.equal(item.executions(), 1);
  assert.equal(JSON.parse(item.output[0]!).status, "complete");
});

test("stale plan approval fails before execution", async () => {
  const item = fixture();
  assert.equal(
    await pluginInstallMain(
      [...base, "--yes", "--accept-plan", "f".repeat(64), "--json"],
      item.services,
    ),
    1,
  );
  assert.equal(item.executions(), 0);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_plan_changed");
});

for (const extra of [
  ["--yes"],
  ["--accept-plan", "a".repeat(64)],
  ["--yes", "--accept-plan", "bad"],
  ["--yes", "--dry-run", "--accept-plan", "a".repeat(64)],
  ["--json", "--json"],
  ["--unknown", "SECRET"],
]) {
  test(`refuses malformed consent/options ${JSON.stringify(extra)}`, async () => {
    const item = fixture();
    assert.equal(await pluginInstallMain([...base, ...extra], item.services), 2);
    assert.equal(item.loads(), 0);
    assert.equal(item.executions(), 0);
    assert.ok(!item.output.join("").includes("SECRET"));
  });
}
for (const ids of [
  "",
  "base.system",
  "plugin.example.cli,",
  ",plugin.example.cli",
  "plugin.example.cli,plugin.example.cli",
  "plugin.example.cli,../escape",
]) {
  test(`rejects malformed or broadened module selections ${JSON.stringify(ids)}`, () => {
    assert.throws(() => parsePluginInstallArguments([...base.slice(0, -1), ids]));
  });
}

test("supports exact multi-module and skip selections", () => {
  const parsed = parsePluginInstallArguments([
    ...base.slice(0, -1),
    "plugin.example.cli,plugin.example.lib",
    "--skip",
    "plugin.example.unused",
  ]);
  assert.deepEqual(parsed.only, ["plugin.example.cli", "plugin.example.lib"]);
  assert.deepEqual(parsed.skip, ["plugin.example.unused"]);
});

test("does not turn an incomplete or mismatched runtime receipt into success", async () => {
  for (const mutation of ["status", "plan", "package", "missing-action", "action-exit"]) {
    const item = fixture();
    if (mutation === "status") item.receipt.status = "failed";
    if (mutation === "plan") item.receipt.planSha256 = "f".repeat(64);
    if (mutation === "package") item.receipt.packageSha256 = "f".repeat(64);
    if (mutation === "missing-action") item.receipt.actions = {};
    if (mutation === "action-exit") item.receipt.actions["plugin.example.cli"]!.exitCode = 17;
    assert.equal(
      await pluginInstallMain(
        [...base, "--yes", "--accept-plan", item.plan.planSha256, "--json"],
        item.services,
      ),
      1,
    );
    assert.equal(JSON.parse(item.output[0]!).status, "failed");
  }
});

test("loader and runtime exceptions do not leak paths or raw installer output", async () => {
  for (const stage of ["loadPlan", "execute"] as const) {
    const item = fixture();
    item.services[stage] = async () => {
      throw new Error("/private/path SECRET_TOKEN");
    };
    assert.equal(
      await pluginInstallMain(
        [...base, "--yes", "--accept-plan", item.plan.planSha256, "--json"],
        item.services,
      ),
      1,
    );
    assert.ok(!item.output.join("").includes("SECRET_TOKEN"));
    assert.ok(!item.output.join("").includes("/private/path"));
  }
});

test("cleans up signal handlers after all command outcomes", async () => {
  const before = [process.listenerCount("SIGINT"), process.listenerCount("SIGTERM")];
  const item = fixture();
  await pluginInstallMain([...base, "--json"], item.services);
  await pluginInstallMain(["--bogus"], item.services);
  assert.deepEqual([process.listenerCount("SIGINT"), process.listenerCount("SIGTERM")], before);
});

test("SIGINT cancellation cannot emit success even if a runtime incorrectly returns a complete receipt", async () => {
  const item = fixture();
  item.services.execute = async (_plan, signal) => {
    process.emit("SIGINT");
    assert.equal(signal.aborted, true);
    return item.receipt;
  };
  assert.equal(
    await pluginInstallMain(
      [...base, "--yes", "--accept-plan", item.plan.planSha256, "--json"],
      item.services,
    ),
    130,
  );
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, "plugin_install_cancelled");
});

test("public help and argument rejection execute without loading canonical dependencies", () => {
  const extension = extname(fileURLToPath(import.meta.url));
  const script = fileURLToPath(new URL(`./plugin-install${extension}`, import.meta.url));
  const help = spawnSync(process.execPath, [script, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /read-only plan/);
  const bad = spawnSync(process.execPath, [script, "--archive", "/PRIVATE", "--json"], {
    encoding: "utf8",
  });
  assert.equal(bad.status, 2, bad.stderr);
  assert.equal(JSON.parse(bad.stdout).status, "failed");
  assert.ok(!bad.stdout.includes("PRIVATE"));
});

test("canonical archive-to-plan integration binds real review, manifest and installer checksums", async () => {
  const { parse } = await import("yaml");
  const manifestBytes = readFileSync(new URL("../../../acfs.manifest.yaml", import.meta.url));
  const checksumBytes = readFileSync(new URL("../../../checksums.yaml", import.meta.url));
  const canonical = parse(manifestBytes.toString());
  const installer = parse(checksumBytes.toString()).installers.bun;
  const directory = mkdtempSync(join(tmpdir(), "acfs-plugin-cli-integration-"));
  const root = join(directory, "acfs-plugin-package");
  mkdirSync(root);
  const manifest = {
    schema: "acfs.plugin-package.v1",
    schemaVersion: 1,
    packageId: "example.tools",
    displayName: "Example Tools",
    version: "1.0.0",
    description: "Reviewed fixture tools.",
    publisher: {
      name: "Test Maintainer",
      contactUrl: "https://example.com/security",
      sourceUrl: "https://example.com/source",
    },
    license: "MIT",
    provenance: {
      generatedAt: "2026-05-08T00:00:00Z",
      sourceRef: "main",
      sourceCommit: "a".repeat(40),
      acfsManifestVersion: canonical.version,
    },
    targets: [{ os: "ubuntu", versions: ["26.04"], arch: ["x86_64"], libc: ["glibc"] }],
    capabilities: {
      allowed: ["verified_installer", "doctor_check"],
      reviewRequired: [],
      disallowed: ["arbitrary_shell", "secret_values"],
    },
    modules: [
      {
        id: "plugin.example_tools.cli",
        description: "Reviewed fixture CLI.",
        category: "tools",
        phase: 6,
        run_as: "target_user",
        optional: false,
        enabled_by_default: false,
        dependencies: [],
        install: {
          kind: "verified_installer",
          tool: "bun",
          url: installer.url,
          runner: "bash",
          args: [],
          env: [],
        },
        verify: [{ kind: "command_exists", command: "bun" }],
        docs_url: "https://example.com/docs",
      },
    ],
    offline: {
      bundlingPolicy: "metadata_only",
      liveAuthRequired: false,
      providerInteractionRequired: false,
    },
    extensions: {},
  };
  writeFileSync(join(root, "plugin.json"), JSON.stringify(manifest));
  writeFileSync(join(root, "README.md"), "Fixture");
  writeFileSync(join(root, "LICENSE"), "MIT");
  const archiveBytes = execFileSync("/usr/bin/tar", [
    "--format=ustar",
    "-czf",
    "-",
    "-C",
    directory,
    "acfs-plugin-package",
  ]);
  const digest = (bytes: Buffer): string => createHash("sha256").update(bytes).digest("hex");
  const archive = join(directory, "package.tar.gz");
  writeFileSync(archive, archiveBytes);
  const review = join(directory, "review.json");
  const reviewRecord = {
    schema: "acfs.plugin-review.v1",
    packageId: manifest.packageId,
    version: manifest.version,
    sourceCommit: manifest.provenance.sourceCommit,
    packageSha256: digest(archiveBytes),
    reviewer: "Fixture Maintainer",
    reviewedAt: new Date(Date.now() - 60_000).toISOString(),
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
    target: { os: "ubuntu", version: "26.04", arch: "x86_64", libc: "glibc" },
    approvedCapabilities: ["verified_installer", "doctor_check"],
  };
  writeFileSync(review, JSON.stringify(reviewRecord));
  const options = parsePluginInstallArguments([
    "--archive",
    archive,
    "--review",
    review,
    "--target",
    "ubuntu/26.04/x86_64/glibc",
    "--only",
    "plugin.example_tools.cli",
  ]);
  const plan = await loadPluginInstallPlan(options);
  assert.equal(plan.package.pluginSha256, digest(archiveBytes));
  assert.equal(plan.trust.manifestSha256, digest(manifestBytes));
  assert.equal(plan.trust.checksumsSha256, digest(checksumBytes));
  assert.equal(plan.actions.length, 1);
  assert.equal(plan.actions[0]!.installer.sha256, installer.sha256);
  assert.deepEqual(plan.prerequisites, []);
  writeFileSync(review, JSON.stringify({ ...reviewRecord, packageSha256: "f".repeat(64) }));
  await assert.rejects(loadPluginInstallPlan(options));
  assert.deepEqual(
    readFileSync(new URL("../../../checksums.yaml", import.meta.url)),
    checksumBytes,
  );
  assert.deepEqual(
    readFileSync(new URL("../../../acfs.manifest.yaml", import.meta.url)),
    manifestBytes,
  );
});
