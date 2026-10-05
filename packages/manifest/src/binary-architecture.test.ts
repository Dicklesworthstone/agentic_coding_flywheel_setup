import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inspectBinary, inspectElf, normalizeArchitecture } from "./binary-architecture.js";

function elf(machine = 62, interpreter?: string): Buffer {
  const data = Buffer.alloc(512);
  Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0]).copy(data);
  data.writeUInt16LE(2, 16); data.writeUInt16LE(machine, 18); data.writeUInt32LE(1, 20);
  data.writeBigUInt64LE(0x400080n, 24); data.writeBigUInt64LE(64n, 32);
  data.writeUInt16LE(64, 52); data.writeUInt16LE(56, 54); data.writeUInt16LE(interpreter ? 2 : 1, 56);
  data.writeUInt32LE(1, 64); data.writeUInt32LE(5, 68);
  data.writeBigUInt64LE(0x400000n, 80);
  data.writeBigUInt64LE(512n, 96); data.writeBigUInt64LE(512n, 104);
  if (interpreter) {
    const bytes = Buffer.from(interpreter + "\0");
    assert.ok(bytes.length <= 256);
    data.writeUInt32LE(3, 120); data.writeBigUInt64LE(256n, 128);
    data.writeBigUInt64LE(BigInt(bytes.length), 152); bytes.copy(data, 256);
  }
  return data;
}
function inspect(data: Buffer, arch: "x86_64" | "aarch64" = "x86_64") {
  return inspectElf((offset, length) => data.subarray(offset, offset + length), data.length, arch);
}

test("architecture aliases are explicit and unknown architectures stay unknown", () => {
  for (const arch of ["x86_64", "amd64", "x64", "AMD64"]) assert.equal(normalizeArchitecture(arch), "x86_64");
  for (const arch of ["aarch64", "arm64"]) assert.equal(normalizeArchitecture(arch), "aarch64");
  for (const arch of ["arm", "i386", "riscv64", "", " arm64"]) assert.equal(normalizeArchitecture(arch), undefined);
});

test("native x86_64 and ARM64 executable headers are accepted only for matching targets", () => {
  for (const [machine, arch] of [[62, "x86_64"], [183, "aarch64"]] as const) {
    assert.equal(inspect(elf(machine), arch).status, "compatible");
    assert.equal(inspect(elf(machine), arch === "x86_64" ? "aarch64" : "x86_64").code, "elf_machine_mismatch");
  }
  assert.equal(inspect(elf(243)).code, "elf_machine_mismatch");
});

test("ELF32, big endian, unrelated OS ABIs and relocatable objects are not certified", () => {
  for (const [offset, value, code] of [[4, 1, "elf_class_or_endian"], [5, 2, "elf_class_or_endian"],
    [7, 9, "elf_os_abi_unverified"], [16, 1, "elf_malformed"]] as const) {
    const data = elf(); data[offset] = value; assert.equal(inspect(data).code, code);
  }
});

test("all truncated ELF headers and truncated program tables are rejected", () => {
  for (let length = 0; length < 120; length++) assert.equal(inspect(elf().subarray(0, length)).status, "incompatible");
});

test("unsafe offsets, extended table counts, overflow and missing executable entries fail closed", () => {
  const mutations = [
    (b: Buffer) => b.writeBigUInt64LE(1n << 63n, 32),
    (b: Buffer) => b.writeBigUInt64LE(500n, 32),
    (b: Buffer) => b.writeBigUInt64LE(0n, 32),
    (b: Buffer) => b.writeUInt16LE(65535, 56),
    (b: Buffer) => b.writeUInt16LE(0, 56),
    (b: Buffer) => b.writeUInt16LE(55, 54),
    (b: Buffer) => b.writeUInt32LE(4, 68),
    (b: Buffer) => b.writeBigUInt64LE(0n, 24),
    (b: Buffer) => b.writeBigUInt64LE(0x500000n, 24),
    (b: Buffer) => b.writeBigUInt64LE(513n, 96),
    (b: Buffer) => b.writeBigUInt64LE(511n, 104),
    (b: Buffer) => b.writeBigUInt64LE((1n << 64n) - 1n, 80),
  ];
  for (const mutate of mutations) { const data = elf(); mutate(data); assert.equal(inspect(data).code, "elf_malformed"); }
});

test("interpreter is bounded, absolute, singly NUL-terminated and never executed", () => {
  const path = "/lib64/ld-linux-x86-64.so.2";
  const good = inspect(elf(62, path)); assert.equal(good.interpreter, path); assert.equal(good.interpreterChecked, false);
  for (const path of ["relative-loader", "/loader\0extra", "/loader\n", "/loader\x7f"]) assert.equal(inspect(elf(62, path)).code, "elf_malformed");
  const noNul = elf(62, "/ld"); noNul[259] = 65; assert.equal(inspect(noNul).code, "elf_malformed");
  const oversized = elf(62, "/ld"); oversized.writeBigUInt64LE(4097n, 152); assert.equal(inspect(oversized).code, "elf_malformed");
  const duplicate = elf(62, "/ld"); duplicate.writeUInt16LE(3, 56); duplicate.copy(duplicate, 176, 120, 176);
  assert.equal(inspect(duplicate).code, "elf_malformed");
});

test("payloads are not read in order to inspect their architecture", () => {
  const data = elf(); let bytes = 0;
  const result = inspectElf((offset, length) => { bytes += length; return data.subarray(offset, offset + length); }, data.length, "x86_64");
  assert.equal(result.status, "compatible"); assert.equal(bytes, 16 + 64 + 56);
});

test("disk inspection follows executable symlinks but preserves source bytes", () => {
  const dir = mkdtempSync(join(tmpdir(), "acfs-architecture-"));
  const file = join(dir, "tool"); const link = join(dir, "link"); const data = elf();
  writeFileSync(file, data); symlinkSync(file, link);
  assert.equal(inspectBinary(link, { target: "x86_64" }).status, "compatible");
  assert.deepEqual(readFileSync(file), data);
  assert.equal(inspectBinary(dir, { target: "x86_64" }).code, "not_regular_file");
  assert.equal(inspectBinary(join(dir, "missing"), { target: "x86_64" }).status, "missing");
});

test("a script that would create a marker is only classified, never run", () => {
  const dir = mkdtempSync(join(tmpdir(), "acfs-architecture-")); const file = join(dir, "script");
  const marker = join(dir, "never-created");
  writeFileSync(file, `#!/bin/sh\nprintf executed > '${marker}'\n`); chmodSync(file, 0o755);
  assert.equal(inspectBinary(file, { target: "x86_64" }).code, "script_payload_unverified");
  assert.throws(() => readFileSync(marker));
  writeFileSync(file, "not an executable");
  assert.equal(inspectBinary(file, { target: "x86_64" }).status, "unknown");
});

test("a real system ELF is classified without launching it", () => {
  if (process.platform !== "linux") return;
  const arch = normalizeArchitecture(process.arch); if (!arch) return;
  const result = inspectBinary("/bin/true", { target: arch, checkHostInterpreter: true });
  assert.equal(result.status, "compatible", JSON.stringify(result));
  assert.equal(inspectBinary("/bin/true", { target: arch === "x86_64" ? "aarch64" : "x86_64" }).status, "incompatible");
});

test("a missing local ELF loader fails while a cross-target loader is not probed", () => {
  const dir = mkdtempSync(join(tmpdir(), "acfs-architecture-")); const path = join(dir, "tool");
  const arch = normalizeArchitecture(process.arch); if (process.platform !== "linux" || !arch) return;
  writeFileSync(path, elf(arch === "x86_64" ? 62 : 183, join(dir, "missing-loader")));
  assert.equal(inspectBinary(path, { target: arch, checkHostInterpreter: true }).code, "interpreter_missing");
  assert.equal(inspectBinary(path, { target: arch }).status, "compatible");
  const foreign = arch === "x86_64" ? "aarch64" : "x86_64";
  writeFileSync(path, elf(foreign === "x86_64" ? 62 : 183, join(dir, "missing-loader")));
  assert.equal(inspectBinary(path, { target: foreign, checkHostInterpreter: true }).code, "foreign_interpreter_unverified");
});
