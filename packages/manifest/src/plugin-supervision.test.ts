import { strict as assert } from "node:assert";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import type { PluginInstallPlan } from "./plugin-plan.js";
import {
  detectPluginInstallTarget,
  executePluginInstallPlan,
  PluginInstallError,
} from "./plugin-runtime.js";

const hash = (bytes: Buffer): string => createHash("sha256").update(bytes).digest("hex");
const unprivileged = { skip: process.platform !== "linux" || process.getuid?.() === 0 };
const runtimeUrl = new URL(
  `./plugin-runtime${extname(fileURLToPath(import.meta.url))}`,
  import.meta.url,
).href;
const installed =
  'mkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\nexit 0\\n" > "$HOME/.local/bin/acfs_supervised"\nchmod 755 "$HOME/.local/bin/acfs_supervised"\n';
function fixture(source = installed) {
  const home = mkdtempSync(join(tmpdir(), "acfs-supervision-"));
  const script = Buffer.from("set -eu\n" + source);
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
    requested: ["plugin.example.cli"],
    skipped: [],
    dependencyIds: [],
    prerequisites: [],
    actions: [
      {
        id: "plugin.example.cli",
        installer: {
          tool: "example",
          url: "https://example.com/install.sh",
          sha256: hash(script),
          runner: "bash" as const,
          args: [],
        },
        verify: ["acfs_supervised"],
      },
    ],
  };
  const plan: PluginInstallPlan = {
    ...payload,
    planSha256: hash(Buffer.from(JSON.stringify(payload))),
  };
  let downloads = 0;
  const download = async (): Promise<Buffer> => {
    downloads++;
    return script;
  };
  const directory = join(home, ".acfs/plugin-installs");
  return {
    home,
    plan,
    script,
    download,
    count: () => downloads,
    directory,
    receipt: join(directory, `${plan.planSha256}.json`),
    lock: join(directory, "install.lock"),
  };
}
async function eventually(predicate: () => boolean, message: string, ms = 8000): Promise<void> {
  const end = Date.now() + ms;
  while (!predicate()) {
    if (Date.now() >= end) assert.fail(message);
    await new Promise<void>((done) => setTimeout(done, 25));
  }
}
const refused =
  (code: string) =>
  (error: unknown): boolean =>
    error instanceof PluginInstallError && error.code === code;
function live(pid: number): boolean {
  try {
    return !/^[ZX]$/.test(readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1]!.split(" ")[0]!);
  } catch {
    return false;
  }
}
function locked(path: string): boolean {
  return spawnSync("/usr/bin/flock", ["-n", path, "/usr/bin/true"]).status !== 0;
}

test(
  "completed supervised installation rechecks its checkpoint without reinstalling",
  unprivileged,
  async () => {
    const item = fixture();
    assert.equal((await executePluginInstallPlan(item.plan, item)).status, "complete");
    assert.equal(
      JSON.parse(readFileSync(item.receipt, "utf8")).executionProtocol,
      "inherited-lock-v1",
    );
    assert.equal((await executePluginInstallPlan(item.plan, item)).status, "complete");
    assert.equal(item.count(), 1);
    assert.equal(locked(item.lock), false);
  },
);

test(
  "all installer descendants inherit the exact locked open-file description",
  unprivileged,
  async () => {
    const item = fixture(
      '/usr/bin/flock -n "$HOME/.acfs/plugin-installs/install.lock" /usr/bin/true && exit 81\n' +
        "test -e /proc/self/fd/3\n/bin/sh -c 'test -e /proc/self/fd/3'\n" +
        installed,
    );
    assert.equal((await executePluginInstallPlan(item.plan, item)).status, "complete");
  },
);

test(
  "SIGKILL of the parent does not admit another install while the orphan is alive",
  unprivileged,
  async () => {
    const item = fixture(
      'echo $$ > "$HOME/worker.pid"\nwhile ! test -f "$HOME/release"; do sleep 0.05; done\n' +
        installed,
    );
    const code = `import {executePluginInstallPlan} from ${JSON.stringify(runtimeUrl)};
    await executePluginInstallPlan(${JSON.stringify(item.plan)}, {home:${JSON.stringify(item.home)}, timeoutSeconds:10,
    download:async()=>Buffer.from(${JSON.stringify(item.script.toString())})});`;
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
      const pid = Number(readFileSync(join(item.home, "worker.pid"), "utf8"));
      assert.equal(live(pid), true);
      assert.equal(locked(item.lock), true, "live orphan lost the installation lease");
      await assert.rejects(
        executePluginInstallPlan(item.plan, item),
        refused("plugin_install_busy"),
      );
      assert.equal(item.count(), 0);
      writeFileSync(join(item.home, "release"), "continue");
      await eventually(() => !locked(item.lock), "orphan did not release its lease");
      await assert.rejects(
        executePluginInstallPlan(item.plan, item),
        refused("plugin_install_interrupted"),
      );
      assert.equal(
        JSON.parse(readFileSync(item.receipt, "utf8")).actions["plugin.example.cli"].status,
        "running",
      );
    } finally {
      writeFileSync(join(item.home, "release"), "continue");
      child.kill("SIGKILL");
      await exited;
    }
  },
);

test(
  "zero-exit entrypoints cannot abandon a live background process and claim completion",
  unprivileged,
  async () => {
    const item = fixture(installed + 'sleep 30 &\necho $! > "$HOME/background.pid"\nexit 0\n');
    await assert.rejects(
      executePluginInstallPlan(item.plan, item),
      refused("plugin_install_failed"),
    );
    const pid = Number(readFileSync(join(item.home, "background.pid"), "utf8"));
    await eventually(() => !live(pid), "background process survived cleanup");
    const receipt = JSON.parse(readFileSync(item.receipt, "utf8"));
    assert.equal(receipt.status, "failed");
    assert.equal(receipt.actions["plugin.example.cli"].exitCode, 125);
    await eventually(() => !locked(item.lock), "cleaned-up group retained a live lease");
  },
);

test(
  "cancellation kills TERM-resistant grandchildren before allowing a retry",
  unprivileged,
  async () => {
    const item = fixture(
      'trap "" TERM\n/bin/sh -c \'trap "" TERM; echo $$ > "$HOME/grandchild.pid"; while :; do sleep 1; done\' &\nwait\n',
    );
    const controller = new AbortController();
    const result = executePluginInstallPlan(item.plan, {
      ...item,
      signal: controller.signal,
      timeoutSeconds: 10,
    });
    const failure = assert.rejects(result, refused("plugin_install_failed"));
    await eventually(
      () => existsSync(join(item.home, "grandchild.pid")),
      "grandchild did not start",
    );
    const pid = Number(readFileSync(join(item.home, "grandchild.pid"), "utf8"));
    controller.abort();
    await failure;
    await eventually(() => !live(pid), "TERM-resistant grandchild survived");
    assert.equal(
      JSON.parse(readFileSync(item.receipt, "utf8")).actions["plugin.example.cli"].exitCode,
      130,
    );
    await eventually(() => !locked(item.lock), "cancellation retained a live lease");
  },
);

test(
  "timeout cleans the full process group and preserves a failed receipt",
  unprivileged,
  async () => {
    const item = fixture('trap "" TERM\necho $$ > "$HOME/worker.pid"\nwhile :; do sleep 1; done\n');
    await assert.rejects(
      executePluginInstallPlan(item.plan, { ...item, timeoutSeconds: 1 }),
      refused("plugin_install_failed"),
    );
    await eventually(
      () => !live(Number(readFileSync(join(item.home, "worker.pid"), "utf8"))),
      "timed-out installer survived",
    );
    assert.equal(JSON.parse(readFileSync(item.receipt, "utf8")).status, "failed");
    await eventually(() => !locked(item.lock), "timeout retained a live lease");
  },
);

test(
  "replacement of the lock pathname cannot authorize a stale receipt writer",
  unprivileged,
  async () => {
    const item = fixture();
    await assert.rejects(
      executePluginInstallPlan(item.plan, {
        ...item,
        download: async () => {
          renameSync(item.lock, item.lock + ".original");
          writeFileSync(item.lock, "", { mode: 0o600 });
          return item.script;
        },
      }),
      refused("plugin_lock_failed"),
    );
    assert.equal(existsSync(item.receipt), false);
    assert.equal(existsSync(join(item.home, ".local/bin/acfs_supervised")), false);
  },
);

test("normal installer exit codes survive process supervision", unprivileged, async () => {
  const item = fixture("exit 17");
  await assert.rejects(executePluginInstallPlan(item.plan, item), refused("plugin_install_failed"));
  assert.equal(
    JSON.parse(readFileSync(item.receipt, "utf8")).actions["plugin.example.cli"].exitCode,
    17,
  );
  assert.equal(locked(item.lock), false);
});

test("root still cannot execute or create plugin state", {
  skip: process.getuid?.() !== 0,
}, async () => {
  const item = fixture();
  await assert.rejects(
    executePluginInstallPlan(item.plan, item),
    refused("plugin_root_execution_refused"),
  );
  assert.equal(existsSync(item.directory), false);
});
