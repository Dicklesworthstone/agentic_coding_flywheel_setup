import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildArchitectureAudit, runArchitectureAudit, type ArchitectureCatalogue } from "./architecture-audit.js";
import { normalizeArchitecture } from "./binary-architecture.js";

const catalogue: ArchitectureCatalogue = {
  modules: [{ id: "agents.claude", optional: false, enabledByDefault: true },
    { id: "stack.rch", optional: true, enabledByDefault: false },
    { id: "base.system", optional: false, enabledByDefault: true }],
  commands: [{ moduleId: "agents.claude", cliName: "claude" }, { moduleId: "stack.rch", cliName: "rch" }],
  provenance: { acfsVersion: "fixture", manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) },
};
function fixture() {
  const home = mkdtempSync(join(tmpdir(), "acfs-architecture-audit-"));
  const bin = join(home, ".local/bin");
  mkdirSync(bin, { recursive: true });
  return { home, bin };
}
function elf(machine: number): Buffer {
  const bytes = Buffer.alloc(120);
  bytes.set([127, 69, 76, 70, 2, 1, 1, 0]);
  bytes.writeUInt16LE(2, 16); bytes.writeUInt16LE(machine, 18); bytes.writeUInt32LE(1, 20);
  bytes.writeBigUInt64LE(0x400000n, 24); bytes.writeBigUInt64LE(64n, 32);
  bytes.writeUInt16LE(64, 52); bytes.writeUInt16LE(56, 54); bytes.writeUInt16LE(1, 56);
  bytes.writeUInt32LE(1, 64); bytes.writeUInt32LE(5, 68);
  bytes.writeBigUInt64LE(0x400000n, 80); bytes.writeBigUInt64LE(120n, 96); bytes.writeBigUInt64LE(120n, 104);
  return bytes;
}

test("matrix exposes missing commands and absent CLI metadata without inventing support", () => {
  const { home } = fixture();
  const report = buildArchitectureAudit(catalogue, { home, target: "aarch64", pathEntries: [] });
  assert.equal(report.exitCode, 1);
  assert.equal(report.modules.length, 3);
  assert.equal(report.summary.missing, 2);
  assert.equal(report.summary.unknown, 1);
  assert.equal(report.modules[1].optional, true);
  assert.equal(report.modules[2].result.code, "module_has_no_cli_metadata");
  assert.equal(report.policy.executesCandidates, false);
  assert.deepEqual(report.provenance, catalogue.provenance);
});
test("explicit downloaded ELF artifacts are inspectable before chmod/install on both architectures", () => {
  const { home } = fixture();
  for (const [machine, target] of [[62, "x86_64"], [183, "aarch64"]] as const) {
    const path = join(home, "artifact=" + machine);
    writeFileSync(path, elf(machine), { mode: 0o600 });
    const result = runArchitectureAudit(["--arch", target, "--binary", `stack.rch=${path}`, "--json"], catalogue);
    assert.equal(result.exitCode, 0);
    const report = JSON.parse(result.output);
    assert.equal(report.modules.length, 1);
    assert.equal(report.modules[0].source, "explicit_artifact");
    assert.equal(report.modules[0].result.architecture, target);
    assert.equal(report.status, "compatible_headers");
    assert.equal(report.policy.certifiesReleases, false);
  }
});
test("managed wrong-architecture copy is not hidden by a compatible later PATH executable", () => {
  const { home, bin } = fixture();
  const later = join(home, "later"); mkdirSync(later);
  writeFileSync(join(bin, "claude"), elf(183), { mode: 0o700 });
  writeFileSync(join(later, "claude"), elf(62), { mode: 0o700 });
  const report = buildArchitectureAudit(catalogue, { home, target: "x86_64", only: ["agents.claude"], pathEntries: [later] });
  assert.equal(report.exitCode, 1);
  assert.equal(report.modules[0].path, "$HOME/.local/bin/claude");
  assert.equal(report.modules[0].result.code, "elf_machine_mismatch");
});
test("wrappers remain incomplete and never run their payload", () => {
  const { home, bin } = fixture();
  const marker = join(home, "not-created");
  writeFileSync(join(bin, "claude"), `#!/bin/sh\necho bad > '${marker}'\n`, { mode: 0o700 });
  const report = buildArchitectureAudit(catalogue, { home, target: "x86_64", only: ["agents.claude"], pathEntries: [] });
  assert.equal(report.exitCode, 3);
  assert.equal(report.status, "incomplete");
  assert.equal(report.modules[0].result.code, "script_payload_unverified");
  assert.throws(() => readFileSync(marker), { code: "ENOENT" });
});
test("unknown/duplicate catalogue metadata and out-of-scope artifact overrides are rejected", () => {
  const { home } = fixture();
  const options = { home, target: "x86_64" as const, pathEntries: [] };
  for (const invalid of [
    { ...catalogue, modules: [...catalogue.modules, catalogue.modules[0]] },
    { ...catalogue, commands: [...catalogue.commands, catalogue.commands[0]] },
    { ...catalogue, commands: [{ moduleId: "unknown.module", cliName: "bad" }] },
    { ...catalogue, commands: [{ moduleId: "stack.rch", cliName: "../../bad" }] },
    { ...catalogue, provenance: { ...catalogue.provenance, manifestSha256: "missing" } },
  ]) assert.throws(() => buildArchitectureAudit(invalid, options));
  assert.throws(() => buildArchitectureAudit(catalogue, { ...options, only: ["unknown.module"] }));
  assert.throws(() => buildArchitectureAudit(catalogue, { ...options, only: ["agents.claude"], binaries: new Map([["stack.rch", "/tmp/rch"]]) }));
});
test("CLI rejects malformed scope, options, duplicate artifacts and unsupported targets", () => {
  for (const args of [["--arch", "mips"], ["--arch"], ["--only", ""], ["--only", "stack.rch,"],
    ["--binary", "stack.rch="], ["--binary", "stack.rch=/a", "--binary", "stack.rch=/b"],
    ["--path", "relative"], ["--only", "unknown.module"], ["--apply"], ["--json", "--only", "--arch"]]) {
    assert.throws(() => runArchitectureAudit(args, catalogue), JSON.stringify(args));
  }
  assert.equal(runArchitectureAudit(["--help"], catalogue).exitCode, 0);
});
test("explicit artifacts can cover metadata-less modules without changing the canonical catalogue", () => {
  const { home } = fixture();
  const path = join(home, "system-artifact"); writeFileSync(path, elf(62));
  const report = buildArchitectureAudit(catalogue, { home, target: "x86_64", binaries: new Map([["base.system", path]]) });
  assert.equal(report.exitCode, 0);
  assert.equal(report.modules[0].command, null);
  assert.equal(report.modules[0].source, "explicit_artifact");
  assert.equal(catalogue.commands.length, 2);
});
test("scope order is stable and repeated module IDs are deduplicated", () => {
  const { home } = fixture();
  const result = runArchitectureAudit(["--home", home, "--path", "", "--only", "stack.rch,base.system", "--only", "stack.rch", "--json"], catalogue);
  const report = JSON.parse(result.output);
  assert.deepEqual(report.modules.map((row: { moduleId: string }) => row.moduleId), ["stack.rch", "base.system"]);
  assert.equal(result.exitCode, 1);
});
test("human output identifies blockers and renders control characters safely", () => {
  const { home, bin } = fixture();
  writeFileSync(join(bin, "claude"), elf(183), { mode: 0o700 });
  const result = runArchitectureAudit(["--home", home, "--path", "", "--arch", "x86_64", "--only", "agents.claude"], catalogue);
  assert.equal(result.exitCode, 1);
  assert.match(result.output, /INCOMPATIBLE agents.claude: elf_machine_mismatch/);
  assert.match(result.output, /no candidate execution/);
  assert.throws(() => runArchitectureAudit(["--binary", "stack.rch=/bad\x1bpath"], catalogue));
});
test("non-executable files are not mistaken for installed commands, while explicit artifact reads still work", () => {
  const { home, bin } = fixture();
  const path = join(bin, "claude"); writeFileSync(path, elf(62)); chmodSync(path, 0o600);
  const report = buildArchitectureAudit(catalogue, { home, target: "x86_64", only: ["agents.claude"], pathEntries: [] });
  assert.equal(report.modules[0].result.status, "missing");
  assert.equal(buildArchitectureAudit(catalogue, { home, target: "x86_64", binaries: new Map([["agents.claude", path]]) }).exitCode, 0);
});
test("real host executable can be bound to a module and inspected without version probes", { skip: process.platform !== "linux" }, () => {
  const { home } = fixture();
  const target = normalizeArchitecture(process.arch)!;
  const report = buildArchitectureAudit(catalogue, { home, target, binaries: new Map([["stack.rch", "/bin/true"]]) });
  assert.equal(report.exitCode, 0);
  assert.equal(report.modules[0].result.status, "compatible");
  assert.equal(report.modules[0].result.interpreterChecked, true);
});
