/** Reproducible package authoring. Builds bytes, never approvals or installers. */
import { createHash } from "node:crypto";
import {
  closeSync,
  constants,
  fchmodSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  opendirSync,
  openSync,
  readSync,
  type Stats,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, parse, resolve, sep } from "node:path";
import { gzipSync } from "node:zlib";
import {
  PLUGIN_ARCHIVE_LIMITS as LIMITS,
  PluginArchiveError,
  type VerifiedPluginArchive,
  verifyPluginArchiveBytes,
} from "./plugin-archive.js";

const ROOT = "acfs-plugin-package";
const digest = (bytes: Uint8Array): string => createHash("sha256").update(bytes).digest("hex");
const copies = new WeakMap<PluginArchiveBuild, { bytes: Buffer; source: string }>();

export class PluginPackError extends Error {
  constructor(
    public readonly code: "plugin_pack_source_invalid" | "plugin_pack_output_invalid",
    message: string,
  ) {
    super(message);
    this.name = "PluginPackError";
  }
}
export interface PluginArchiveBuild extends VerifiedPluginArchive {
  /** An authoring result is never an independently reviewed install authority. */
  reviewRequired: true;
}
export interface PluginArchivePublication {
  packageSha256: string;
  compressedBytes: number;
  expandedBytes: number;
  fileCount: number;
  reviewRequired: true;
}
interface SourceEntry {
  path: string;
  stat: Stats;
  bytes: Buffer;
}
function refuse(message: string): never {
  throw new PluginPackError("plugin_pack_source_invalid", message);
}
function outputError(): never {
  throw new PluginPackError(
    "plugin_pack_output_invalid",
    "Package output must be a new file outside the source, in an existing safe directory; existing or partial files are preserved",
  );
}
function same(a: Stats, b: Stats): boolean {
  return (
    a.dev === b.dev &&
    a.ino === b.ino &&
    a.size === b.size &&
    a.mtimeMs === b.mtimeMs &&
    a.ctimeMs === b.ctimeMs &&
    a.nlink === b.nlink
  );
}
function portable(path: string): boolean {
  return (
    path.length <= 255 &&
    path.split("/").every((part) => /^[A-Za-z0-9_][A-Za-z0-9._-]*$/.test(part))
  );
}
function checkAncestors(path: string): void {
  let current = parse(path).root;
  for (const part of path.slice(current.length).split(sep).filter(Boolean)) {
    current = join(current, part);
    const stat = lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink())
      refuse("Source or output has a non-directory or symlinked path component");
  }
}
function acceptable(stat: Stats): void {
  if (
    (!stat.isDirectory() && !stat.isFile()) ||
    stat.isSymbolicLink() ||
    (stat.isFile() && stat.nlink !== 1) ||
    (stat.mode & 0o7022) !== 0
  ) {
    refuse(
      "Package sources must be ordinary directories and single-link files without special or unsafe write permissions",
    );
  }
}
function snapshot(path: string, before: Stats, limit: number): Buffer {
  if (!Number.isSafeInteger(before.size) || before.size < 0 || before.size > limit)
    refuse("Package source exceeds its member size budget");
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const opened = fstatSync(fd);
    acceptable(opened);
    if (!opened.isFile() || !same(before, opened)) refuse("Package source changed before reading");
    const bytes = Buffer.alloc(before.size + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      if (count === 0) break;
      offset += count;
    }
    if (offset !== before.size || !same(before, fstatSync(fd)))
      refuse("Package source changed while reading");
    return bytes.subarray(0, offset);
  } finally {
    closeSync(fd);
  }
}

/** Known credential markers are refused even inside declared documentation/assets. */
function checkContent(bytes: Buffer): void {
  const text = bytes.toString("latin1");
  if (
    /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/i.test(text) ||
    /(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}/.test(text) ||
    /\b(?:hvs|hvb|hvr)\.[A-Za-z0-9_-]{20,}/i.test(text) ||
    /\b(?:sk-(?:proj-)?|glpat-|sbp_|shpat_|xox[baprs]-|npm_)[A-Za-z0-9_-]{20,}/.test(text) ||
    /\bAKIA[A-Z0-9]{16}\b/.test(text)
  ) {
    refuse("Package source contains a private-key or credential marker; content was not published");
  }
}
function inventory(source: string): SourceEntry[] {
  checkAncestors(source);
  const entries: SourceEntry[] = [];
  let expanded = 1024;
  const visit = (relative: string): void => {
    if (entries.length >= LIMITS.entries) refuse("Package source exceeds its entry budget");
    const memberPath = relative ? `${ROOT}/${relative}` : ROOT;
    if (!portable(memberPath)) refuse("Package source contains a nonportable member path");
    const path = relative ? join(source, ...relative.split("/")) : source;
    const stat = lstatSync(path);
    acceptable(stat);
    if (!relative && !stat.isDirectory()) refuse("Package source must be a directory");
    const directory = stat.isDirectory();
    expanded += 512 + (directory ? 0 : Math.ceil(stat.size / 512) * 512);
    if (expanded > LIMITS.expandedBytes)
      refuse("Package source exceeds its total expanded size budget");
    const bytes = directory
      ? Buffer.alloc(0)
      : snapshot(
          path,
          stat,
          relative === "plugin.json" ? LIMITS.manifestBytes : LIMITS.memberBytes,
        );
    if (!directory) checkContent(bytes);
    entries.push({ path: memberPath, stat, bytes });
    if (directory) {
      const stream = opendirSync(path);
      try {
        let entry;
        while ((entry = stream.readSync()) !== null) {
          visit(relative ? `${relative}/${entry.name}` : entry.name);
        }
      } finally {
        stream.closeSync();
      }
      if (!same(stat, lstatSync(path))) refuse("Package directory changed while reading");
    }
  };
  visit("");
  // Recheck every path, including files read before other directories were walked.
  checkAncestors(source);
  for (const entry of entries) {
    const relative = entry.path.slice(ROOT.length + 1);
    if (!same(entry.stat, lstatSync(relative ? join(source, ...relative.split("/")) : source))) {
      refuse("Package source changed during inventory");
    }
  }
  return entries.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}
function tarHeader(entry: SourceEntry): Buffer {
  let name = entry.path;
  let prefix = "";
  if (name.length > 100) {
    let split = name.lastIndexOf("/", 155);
    while (split > 0 && name.length - split - 1 > 100) split = name.lastIndexOf("/", split - 1);
    if (split < 1 || name.length - split - 1 > 100)
      refuse("Package path cannot be represented by portable ustar headers");
    prefix = name.slice(0, split);
    name = name.slice(split + 1);
  }
  const header = Buffer.alloc(512);
  const octal = (value: number, offset: number, length: number): void => {
    header.write(value.toString(8).padStart(length - 1, "0") + "\0", offset, length, "ascii");
  };
  header.write(name, 0, 100, "ascii");
  octal(entry.stat.isDirectory() ? 0o755 : 0o644, 100, 8);
  octal(0, 108, 8);
  octal(0, 116, 8); // uid/gid are never builder identities
  octal(entry.bytes.length, 124, 12);
  octal(0, 136, 12); // deterministic mtime
  header[156] = entry.stat.isDirectory() ? 53 : 48;
  header.write("ustar\x0000", 257, 8, "ascii");
  header.write(prefix, 345, 155, "ascii");
  header.fill(32, 148, 156);
  header.write(
    header
      .reduce((sum, byte) => sum + byte, 0)
      .toString(8)
      .padStart(6, "0") + "\0 ",
    148,
    8,
    "ascii",
  );
  return header;
}
function freezeJson(value: unknown): void {
  if (value && typeof value === "object") {
    Object.values(value).forEach(freezeJson);
    Object.freeze(value);
  }
}

/**
 * Snapshot a dedicated package source tree, emit deterministic ustar/gzip, and
 * round-trip it through the production archive validator. No files are written.
 * The manifest bytes are preserved: hashes/declarations are never auto-approved
 * or silently rewritten. Semantic validation is a separate mandatory CLI step.
 */
export function buildPluginArchive(sourceDirectory: string): PluginArchiveBuild {
  try {
    const source = resolve(sourceDirectory);
    const entries = inventory(source);
    const tar = Buffer.concat([
      ...entries.flatMap((entry) => [
        tarHeader(entry),
        entry.bytes,
        Buffer.alloc((512 - (entry.bytes.length % 512)) % 512),
      ]),
      Buffer.alloc(1024),
    ]);
    const bytes = gzipSync(tar, { level: 9 });
    bytes.fill(0, 4, 8);
    bytes[9] = 255; // no build time or builder OS metadata
    const validated = verifyPluginArchiveBytes(bytes, digest(bytes));
    freezeJson(validated.manifest);
    const result = Object.freeze({ ...validated, reviewRequired: true as const });
    copies.set(result, { bytes, source });
    return result;
  } catch (error) {
    if (error instanceof PluginPackError || error instanceof PluginArchiveError) throw error;
    return refuse("Package source could not be read safely; no output was published");
  }
}

/** Return an owned copy, never the producer's retained publication snapshot. */
export function pluginArchiveBytes(build: PluginArchiveBuild): Buffer {
  const retained = copies.get(build);
  if (!retained) return refuse("Package publication requires a build produced in this process");
  return Buffer.from(retained.bytes);
}

/** Publish only a process-built snapshot, exclusively; never overwrite or delete. */
export function writePluginArchive(
  build: PluginArchiveBuild,
  outputPath: string,
): PluginArchivePublication {
  const retained = copies.get(build);
  if (!retained) return refuse("Package publication requires a build produced in this process");
  try {
    const output = resolve(outputPath);
    if (
      output === retained.source ||
      output.startsWith(retained.source + sep) ||
      !/^[A-Za-z0-9_][A-Za-z0-9._-]*\.tar\.gz$/.test(basename(output))
    )
      return outputError();
    const parent = dirname(output);
    checkAncestors(parent);
    const parentStat = lstatSync(parent);
    if ((parentStat.mode & 0o002) !== 0 && (parentStat.mode & 0o1000) === 0) return outputError();
    const fd = openSync(
      output,
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
      0o600,
    );
    try {
      const stat = fstatSync(fd);
      if (!stat.isFile() || stat.nlink !== 1) return outputError();
      writeFileSync(fd, retained.bytes);
      fchmodSync(fd, 0o600);
      fsyncSync(fd);
      const current = lstatSync(output);
      if (current.dev !== stat.dev || current.ino !== stat.ino || current.nlink !== 1)
        return outputError();
    } finally {
      closeSync(fd);
    }
    const parentFd = openSync(
      parent,
      constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
    );
    try {
      const now = fstatSync(parentFd);
      if (now.dev !== parentStat.dev || now.ino !== parentStat.ino) return outputError();
      fsyncSync(parentFd);
    } finally {
      closeSync(parentFd);
    }
    return {
      packageSha256: build.packageSha256,
      compressedBytes: build.compressedBytes,
      expandedBytes: build.expandedBytes,
      fileCount: build.fileCount,
      reviewRequired: true,
    };
  } catch (error) {
    if (error instanceof PluginPackError) throw error;
    return outputError();
  }
}
