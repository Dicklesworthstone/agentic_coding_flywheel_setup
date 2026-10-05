/**
 * Read-only Linux executable inspection. Never execute a candidate (or ldd).
 * A matching ELF header is not proof of functional, CPU-feature or libc support.
 * ELF layout: https://gabi.xinuos.com/elf/02-eheader.html
 */
import { closeSync, constants, fstatSync, openSync, readSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";

export type LinuxArchitecture = "x86_64" | "aarch64";
export type ArchitectureStatus = "compatible" | "incompatible" | "unknown" | "missing" | "unreadable";
export interface BinaryArchitectureResult {
  status: ArchitectureStatus;
  code: string;
  format: "elf" | "script" | "other";
  target: LinuxArchitecture;
  architecture?: LinuxArchitecture;
  machine?: number;
  interpreter?: string;
  interpreterChecked: boolean;
  sizeBytes?: number;
  detail: string;
}
export interface InspectBinaryOptions {
  target: LinuxArchitecture;
  /** Check PT_INTERP existence only on the actual matching Linux host. */
  checkHostInterpreter?: boolean;
}

const MAX_PROGRAM_HEADERS = 512;
const MAX_INTERPRETER_BYTES = 4096;
const MACHINE_ARCH = new Map<number, LinuxArchitecture>([[62, "x86_64"], [183, "aarch64"]]);

export function normalizeArchitecture(value: string): LinuxArchitecture | undefined {
  switch (value.toLowerCase()) {
    case "x86_64": case "amd64": case "x64": return "x86_64";
    case "aarch64": case "arm64": return "aarch64";
    default: return undefined;
  }
}

class InvalidElf extends Error {}
function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new InvalidElf(message);
}
function integer(value: bigint): number {
  check(value <= BigInt(Number.MAX_SAFE_INTEGER), "ELF offset exceeds the safe integer range.");
  return Number(value);
}
function slice(read: (offset: number, length: number) => Buffer, size: number,
  offset: number, length: number): Buffer {
  check(Number.isSafeInteger(offset) && Number.isSafeInteger(length) && offset >= 0 && length >= 0
    && offset <= size && length <= size - offset, "ELF structure extends beyond the file.");
  const bytes = read(offset, length);
  check(bytes.length === length, "ELF structure is truncated.");
  return bytes;
}

/** Pure bounded parser, shared by on-disk inspection and binary-fixture tests. */
export function inspectElf(
  read: (offset: number, length: number) => Buffer,
  size: number,
  target: LinuxArchitecture,
): BinaryArchitectureResult {
  const base = { target, format: "elf" as const, interpreterChecked: false, sizeBytes: size };
  try {
    const ident = slice(read, size, 0, 16);
    check(ident.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46])), "Invalid ELF magic.");
    if (ident[4] !== 2 || ident[5] !== 1) {
      return { ...base, status: "incompatible", code: "elf_class_or_endian",
        detail: "The selected Linux target requires a 64-bit little-endian executable." };
    }
    check(ident[6] === 1, "Unsupported ELF identification version.");
    if (ident[7] !== 0 && ident[7] !== 3) {
      return { ...base, status: "unknown", code: "elf_os_abi_unverified",
        detail: "This ELF OS ABI is not verified for Linux." };
    }
    const header = slice(read, size, 0, 64);
    const type = header.readUInt16LE(16);
    const machine = header.readUInt16LE(18);
    const architecture = MACHINE_ARCH.get(machine);
    check(type === 2 || type === 3, "ELF is not an executable or position-independent executable.");
    check(header.readUInt32LE(20) === 1 && header.readUInt16LE(52) === 64, "Invalid ELF header version or size.");
    if (architecture !== target) {
      return { ...base, machine, ...(architecture ? { architecture } : {}),
        status: "incompatible", code: "elf_machine_mismatch",
        detail: `ELF machine ${machine} does not match target ${target}.` };
    }
    const entry = header.readBigUInt64LE(24);
    const table = integer(header.readBigUInt64LE(32));
    const entrySize = header.readUInt16LE(54);
    const count = header.readUInt16LE(56);
    check(entrySize === 56 && count > 0 && count <= MAX_PROGRAM_HEADERS,
      "Unsupported or invalid ELF program-header table.");
    check(table >= 64, "ELF program-header table overlaps its header.");
    const programs = slice(read, size, table, entrySize * count);
    let hasEntry = false;
    let interpreter: string | undefined;
    let interpreterCount = 0;
    for (let i = 0; i < count; i++) {
      const program = programs.subarray(i * entrySize, (i + 1) * entrySize);
      const kind = program.readUInt32LE(0);
      const flags = program.readUInt32LE(4);
      const offset = integer(program.readBigUInt64LE(8));
      const address = program.readBigUInt64LE(16);
      const fileSize = integer(program.readBigUInt64LE(32));
      const memorySize = program.readBigUInt64LE(40);
      // Bound segments without reading payloads, even if they are not loaded.
      check(offset <= size && fileSize <= size - offset, "ELF segment extends beyond the file.");
      if (kind === 1) {
        check(BigInt(fileSize) <= memorySize, "ELF load segment is larger on disk than in memory.");
        check(address + memorySize <= (1n << 64n), "ELF load segment address overflows.");
        if ((flags & 1) && entry !== 0n && entry >= address && entry - address < memorySize) hasEntry = true;
      }
      if (kind === 3) {
        interpreterCount++;
        check(interpreterCount === 1, "Multiple ELF interpreters are not accepted for certification.");
        check(fileSize >= 2 && fileSize <= MAX_INTERPRETER_BYTES, "Invalid ELF interpreter length.");
        const value = slice(read, size, offset, fileSize);
        check(value[value.length - 1] === 0 && !value.subarray(0, -1).includes(0),
          "ELF interpreter must have one terminating NUL.");
        const path = value.subarray(0, -1);
        check([...path].every(byte => byte >= 0x20 && byte < 0x7f), "ELF interpreter contains non-ASCII or control bytes.");
        interpreter = path.toString("ascii");
        check(isAbsolute(interpreter), "ELF interpreter must be an absolute path.");
      }
    }
    check(hasEntry, "ELF has no entry point inside an executable load segment.");
    return { ...base, architecture, machine, ...(interpreter ? { interpreter } : {}),
      status: "compatible", code: "elf_header_compatible",
      detail: "ELF architecture and load headers match; CPU extensions, shared libraries and behavior are not verified." };
  } catch (error) {
    if (!(error instanceof InvalidElf)) throw error;
    return { ...base, status: "incompatible", code: "elf_malformed", detail: error.message };
  }
}

function ioCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error ? String(error.code) : undefined;
}

/** Follow ordinary executable symlinks, but never block on or consume devices/FIFOs. */
export function inspectBinary(path: string, options: InspectBinaryOptions): BinaryArchitectureResult {
  const target = normalizeArchitecture(options.target);
  if (!target) throw new Error("Unsupported target architecture.");
  const base = { target, format: "other" as const, interpreterChecked: false };
  let fd: number | undefined;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK);
    const before = fstatSync(fd);
    if (!before.isFile()) return { ...base, status: "unreadable", code: "not_regular_file",
      detail: "Candidate is not a regular file." };
    if (!Number.isSafeInteger(before.size)) return { ...base, status: "unreadable", code: "unsafe_file_size",
      detail: "Candidate size is outside the supported range." };
    const read = (offset: number, length: number): Buffer => {
      const buffer = Buffer.alloc(length);
      let received = 0;
      while (received < length) {
        const n = readSync(fd!, buffer, received, length - received, offset + received);
        if (!n) break;
        received += n;
      }
      return buffer.subarray(0, received);
    };
    const prefix = read(0, Math.min(before.size, 256));
    let result: BinaryArchitectureResult;
    if (prefix.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) {
      result = inspectElf(read, before.size, target);
    } else if (prefix.subarray(0, 2).toString("ascii") === "#!") {
      // A shell/Node wrapper may select another native payload. Do not certify
      // it from its shebang and do not inspect/evaluate arbitrary shell text.
      result = { ...base, format: "script", sizeBytes: before.size,
        status: "unknown", code: "script_payload_unverified",
        detail: "Script launcher detected; its interpreter and selected native payload require separate inspection." };
    } else {
      result = { ...base, sizeBytes: before.size, status: "unknown", code: "executable_format_unverified",
        detail: "Not a recognized Linux ELF executable; no candidate was executed." };
    }
    const after = fstatSync(fd);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) {
      return { ...base, status: "unreadable", code: "candidate_changed",
        detail: "Candidate changed during inspection; collect new evidence." };
    }
    if (result.status === "compatible" && result.interpreter && options.checkHostInterpreter) {
      if (process.platform !== "linux" || normalizeArchitecture(process.arch) !== target) {
        return { ...result, status: "unknown", code: "foreign_interpreter_unverified",
          detail: "Target loader availability cannot be checked on a different host platform." };
      }
      try {
        const loader = statSync(result.interpreter);
        if (!loader.isFile() || !(loader.mode & 0o111)) {
          return { ...result, interpreterChecked: true, status: "incompatible", code: "interpreter_unusable",
            detail: "The target's ELF interpreter is not an executable regular file." };
        }
      } catch (error) {
        return { ...result, interpreterChecked: true,
          status: ioCode(error) === "ENOENT" ? "incompatible" : "unknown",
          code: ioCode(error) === "ENOENT" ? "interpreter_missing" : "interpreter_unreadable",
          detail: "The ELF interpreter is unavailable on this host." };
      }
      result = { ...result, interpreterChecked: true };
    }
    return result;
  } catch (error) {
    const missing = ioCode(error) === "ENOENT";
    return { ...base, status: missing ? "missing" : "unreadable", code: missing ? "binary_missing" : "binary_unreadable",
      detail: missing ? "Candidate binary is missing." : "Candidate binary could not be inspected." };
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}
