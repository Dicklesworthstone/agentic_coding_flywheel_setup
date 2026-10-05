import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { buildAgentReadinessReport, type CommandRunResult } from "./agent-readiness-audit.js";
import { normalizeArchitecture } from "./binary-architecture.js";

function fixture() {
  const home = mkdtempSync(join(tmpdir(), "acfs-readiness-arch-"));
  const bin = join(home, ".local/bin"); mkdirSync(bin, { recursive: true });
  return { home, bin };
}
function elf(machine: number, interpreter?: string): Buffer {
  const b = Buffer.alloc(512);
  b.set([127, 69, 76, 70, 2, 1, 1, 0]);
  b.writeUInt16LE(2, 16); b.writeUInt16LE(machine, 18); b.writeUInt32LE(1, 20);
  b.writeBigUInt64LE(0x400080n, 24); b.writeBigUInt64LE(64n, 32);
  b.writeUInt16LE(64, 52); b.writeUInt16LE(56, 54); b.writeUInt16LE(interpreter ? 2 : 1, 56);
  b.writeUInt32LE(1, 64); b.writeUInt32LE(5, 68); b.writeBigUInt64LE(0x400000n, 80);
  b.writeBigUInt64LE(512n, 96); b.writeBigUInt64LE(512n, 104);
  if (interpreter) {
    const value = Buffer.from(interpreter + "\0"); assert.ok(value.length < 256);
    b.writeUInt32LE(3, 120); b.writeBigUInt64LE(256n, 128); b.writeBigUInt64LE(BigInt(value.length), 152);
    value.copy(b, 256);
  }
  return b;
}
const host = normalizeArchitecture(process.arch);
const onLinux = { skip: process.platform !== "linux" || !host };
const machine = host === "aarch64" ? 183 : 62;
const other = machine === 62 ? 183 : 62;
const success = { status: 0, stdout: "tool 1.2.3\n", stderr: "" };

function audit(home: string, result: CommandRunResult = success, collectVersions = true) {
  const calls: string[] = [];
  const report = buildAgentReadinessReport({ home, pathEntries: [], env: {}, collectVersions,
    commandRunner: { run: (path, args, timeout) => {
      calls.push(basename(path)); assert.deepEqual(args, ["--version"]); assert.equal(timeout, 4000);
      return result;
    } } });
  return { calls, report, cli: report.tools.find(tool => tool.id === "claude")!.cli };
}

test("foreign native agents fail before any version runner is called", onLinux, () => {
  const { home, bin } = fixture();
  for (const name of ["claude", "codex", "agy", "caam"]) writeFileSync(join(bin, name), elf(other), { mode: 0o700 });
  const { calls, report } = audit(home);
  assert.deepEqual(calls, []);
  assert.equal(report.ok, false);
  assert.equal(report.summary.fail, 4);
  for (const tool of report.tools) {
    assert.equal(tool.cli.status, "fail");
    assert.equal(tool.cli.architecture?.code, "elf_machine_mismatch");
    assert.equal(tool.cli.versionProbe, undefined);
    assert.match(tool.nextActions[0], /Repair\/reinstall/);
  }
});
test("--no-version cannot hide an incompatible executable", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), elf(other), { mode: 0o700 });
  const { cli, calls } = audit(home, success, false);
  assert.equal(cli.status, "fail"); assert.deepEqual(calls, []);
});
test("matching ELF candidates retain architecture evidence through successful version probes", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), elf(machine), { mode: 0o700 });
  const { cli, calls } = audit(home);
  assert.equal(cli.status, "pass"); assert.equal(cli.version, "tool 1.2.3");
  assert.equal(cli.architecture?.architecture, host);
  assert.deepEqual(cli.versionProbe, { status: "passed", exitCode: 0 });
  assert.deepEqual(calls, ["claude"]);
});
test("missing loaders and truncated ELF files are rejected without launching a subprocess", onLinux, () => {
  for (const data of [elf(machine, "/this-acfs-loader-does-not-exist/ld.so"), elf(machine).subarray(0, 32)]) {
    const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), data, { mode: 0o700 });
    const { cli, calls } = audit(home);
    assert.equal(cli.status, "fail"); assert.deepEqual(calls, []);
    assert.ok(["elf_malformed", "interpreter_missing"].includes(cli.architecture!.code));
  }
});
test("all nonzero and absent version exit statuses fail readiness instead of preserving pass", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), elf(machine), { mode: 0o700 });
  for (const status of [1, 23, 126, 127, 137, null]) {
    const { cli, calls, report } = audit(home, { status, stdout: "partial success", stderr: "private error text" });
    assert.equal(cli.status, "fail"); assert.equal(report.ok, false);
    assert.equal(cli.version, undefined); assert.deepEqual(calls, ["claude"]);
    assert.deepEqual(cli.versionProbe, { status: "failed", exitCode: status });
    assert.ok(!JSON.stringify(cli).includes("private error text"));
    assert.ok(!JSON.stringify(cli).includes("partial success"));
  }
});
test("runner errors cannot report a successful zero exit or expose raw diagnostics", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), elf(machine), { mode: 0o700 });
  const { cli } = audit(home, { ...success, error: "secret-value-from-runner" });
  assert.equal(cli.status, "fail"); assert.ok(!JSON.stringify(cli).includes("secret-value-from-runner"));
  const report = buildAgentReadinessReport({ home, pathEntries: [], env: {},
    commandRunner: { run() { throw new Error("secret-from-exception"); } } });
  const failed = report.tools.find(tool => tool.id === "claude")!.cli;
  assert.equal(failed.status, "fail"); assert.equal(failed.versionProbe?.exitCode, null);
  assert.ok(!JSON.stringify(report).includes("secret-from-exception"));
});
test("wrapper architecture stays unknown after a successful version probe", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  const { cli, calls } = audit(home);
  assert.equal(cli.status, "warn"); assert.equal(cli.architecture?.status, "unknown");
  assert.equal(cli.versionProbe?.status, "passed"); assert.deepEqual(calls, ["claude"]);
});
test("--no-version inspects wrappers without executing their marker payload", onLinux, () => {
  const { home, bin } = fixture(); const marker = join(home, "must-not-run");
  writeFileSync(join(bin, "claude"), `#!/bin/sh\necho ran > '${marker}'\n`, { mode: 0o700 });
  const report = buildAgentReadinessReport({ home, pathEntries: [], env: {}, collectVersions: false });
  const cli = report.tools.find(tool => tool.id === "claude")!.cli;
  assert.equal(cli.status, "warn"); assert.equal(cli.versionProbe, undefined);
  assert.throws(() => readFileSync(marker), { code: "ENOENT" });
});
test("real failed --version process propagates into CLI readiness failure", onLinux, () => {
  const { home, bin } = fixture();
  writeFileSync(join(bin, "claude"), "#!/bin/sh\nprintf 'private diagnostic' >&2\nexit 23\n", { mode: 0o700 });
  const report = buildAgentReadinessReport({ home, pathEntries: [], env: {} });
  const cli = report.tools.find(tool => tool.id === "claude")!.cli;
  assert.equal(cli.status, "fail"); assert.equal(cli.versionProbe?.exitCode, 23);
  assert.ok(!JSON.stringify(report).includes("private diagnostic"));
});
test("empty successful version output is warned, not presented as a known version", onLinux, () => {
  const { home, bin } = fixture(); writeFileSync(join(bin, "claude"), elf(machine), { mode: 0o700 });
  const { cli } = audit(home, { status: 0, stdout: "", stderr: "" });
  assert.equal(cli.status, "warn"); assert.equal(cli.version, undefined);
  assert.equal(cli.versionProbe?.status, "passed");
});
test("normal executable symlinks are inspected but do not substitute a later healthy PATH candidate", onLinux, () => {
  const { home, bin } = fixture(); const target = join(home, "foreign");
  writeFileSync(target, elf(other), { mode: 0o700 }); symlinkSync(target, join(bin, "claude"));
  const later = join(home, "later"); mkdirSync(later);
  writeFileSync(join(later, "claude"), elf(machine), { mode: 0o700 });
  let calls = 0;
  const report = buildAgentReadinessReport({ home, env: {}, pathEntries: [later],
    commandRunner: { run() { calls++; return success; } } });
  assert.equal(report.tools.find(tool => tool.id === "claude")!.cli.status, "fail");
  assert.equal(calls, 0);
});
test("virtual filesystems without binary bytes remain usable and do not inspect real host paths", () => {
  let calls = 0;
  const report = buildAgentReadinessReport({ home: "/virtual-home", env: {}, pathEntries: [],
    fileSystem: { stat: path => path.endsWith("/claude") ? { kind: "file", executable: true } : { kind: "missing" },
      readFile: () => ({ kind: "missing" }), readDir: () => ({ kind: "missing" }) },
    commandRunner: { run() { calls++; return success; } } });
  const cli = report.tools.find(tool => tool.id === "claude")!.cli;
  assert.equal(cli.status, "pass"); assert.equal(cli.architecture, undefined); assert.equal(calls, 1);
});
