/**
 * Read a digest-pinned plugin tar.gz without extracting or executing any member.
 * This establishes byte provenance, not permission to activate a plugin.
 */
import { createHash } from 'node:crypto';
import { closeSync, constants, fstatSync, openSync, readSync } from 'node:fs';
import { TextDecoder } from 'node:util';
import { gunzipSync } from 'node:zlib';

export const PLUGIN_ARCHIVE_LIMITS = Object.freeze({
  compressedBytes: 16 * 1024 * 1024,
  expandedBytes: 64 * 1024 * 1024,
  manifestBytes: 1024 * 1024,
  memberBytes: 8 * 1024 * 1024,
  entries: 1024,
  jsonDepth: 64,
  jsonNodes: 50_000,
});

export type PluginArchiveErrorCode =
  | 'plugin_archive_layout_invalid'
  | 'plugin_package_hash_mismatch';

/** Diagnostics intentionally contain no local paths, member names, or hashes. */
export class PluginArchiveError extends Error {
  constructor(public readonly code: PluginArchiveErrorCode, message: string) {
    super(message);
    this.name = 'PluginArchiveError';
  }
}

export interface VerifiedPluginArchive {
  /** Digest of the exact compressed bytes used to produce manifest. */
  packageSha256: string;
  /** Still untrusted semantically: pass through validatePluginPackage. */
  manifest: unknown;
  compressedBytes: number;
  expandedBytes: number;
  fileCount: number;
}

function invalid(message: string): never {
  throw new PluginArchiveError('plugin_archive_layout_invalid', message);
}

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function isDigest(value: unknown): value is string {
  return typeof value === 'string' && /^[a-f0-9]{64}$/i.test(value);
}

/** Read one bounded, single-link regular file, never a FIFO, device, or symlink. */
export function readPluginInputFile(filePath: string, maxBytes: number): Buffer {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1
      || maxBytes > PLUGIN_ARCHIVE_LIMITS.compressedBytes) {
    invalid('Invalid plugin input size limit');
  }
  let fd: number | undefined;
  try {
    fd = openSync(filePath, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const before = fstatSync(fd);
    if (!before.isFile() || before.nlink !== 1 || before.size < 1 || before.size > maxBytes) {
      invalid('Plugin input must be a nonempty bounded single-link regular file');
    }
    const bytes = Buffer.alloc(before.size + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      if (count === 0) break;
      offset += count;
    }
    const after = fstatSync(fd);
    if (offset !== before.size || after.size !== before.size
        || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      invalid('Plugin input changed while being read');
    }
    return bytes.subarray(0, offset);
  } catch (error) {
    if (error instanceof PluginArchiveError) throw error;
    return invalid('Plugin input could not be opened or read safely');
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

/** JSON-only UTF-8, rejecting duplicate decoded keys, excessive depth and nodes. */
export function parsePluginJsonBytes(bytes: Uint8Array): unknown {
  if (bytes.byteLength === 0 || bytes.byteLength > PLUGIN_ARCHIVE_LIMITS.manifestBytes) {
    invalid('Plugin JSON exceeds the accepted size budget or is empty');
  }
  let text: string;
  let parsed: unknown;
  try {
    // Do not silently strip a UTF-8 BOM: JSON inputs have one byte interpretation.
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    parsed = JSON.parse(text);
  } catch {
    invalid('Plugin JSON must be valid UTF-8 JSON');
  }

  // JSON.parse proved syntax. Scan key boundaries before exposing its result,
  // since JSON.parse alone silently keeps the last duplicate key.
  let offset = 0;
  let nodes = 0;
  const whitespace = (): void => {
    while (/^[\t\n\r ]$/.test(text[offset] ?? '')) offset++;
  };
  const string = (): string => {
    const start = offset++;
    while (offset < text.length) {
      const char = text[offset++];
      if (char === '\\') offset++;
      else if (char === '"') return JSON.parse(text.slice(start, offset)) as string;
    }
    return invalid('Plugin JSON string is incomplete');
  };
  const value = (depth: number): void => {
    if (depth > PLUGIN_ARCHIVE_LIMITS.jsonDepth || ++nodes > PLUGIN_ARCHIVE_LIMITS.jsonNodes) {
      invalid('Plugin JSON exceeds its nesting or node budget');
    }
    whitespace();
    const char = text[offset];
    if (char === '{' || char === '[') {
      const object = char === '{';
      const end = object ? '}' : ']';
      const keys = new Set<string>();
      offset++;
      whitespace();
      if (text[offset] === end) { offset++; return; }
      while (offset < text.length) {
        if (object) {
          const key = string();
          if (keys.has(key)) invalid('Plugin JSON contains duplicate object keys');
          keys.add(key);
          whitespace();
          offset++; // colon, already syntax-checked
        }
        value(depth + 1);
        whitespace();
        if (text[offset++] === end) return;
        whitespace();
      }
    } else if (char === '"') {
      string();
    } else {
      const start = offset;
      while (offset < text.length && !/[\t\n\r ,}\]]/.test(text[offset]!)) offset++;
      const primitive = text.slice(start, offset);
      if (/^-?[0-9]/.test(primitive) && !Number.isFinite(Number(primitive))) {
        invalid('Plugin JSON numbers must be finite');
      }
    }
  };
  value(0);
  return parsed;
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function zero(bytes: Uint8Array): boolean {
  return bytes.every((byte) => byte === 0);
}

function textField(header: Buffer, start: number, length: number): string {
  const field = header.subarray(start, start + length);
  const nul = field.indexOf(0);
  if (nul >= 0 && !zero(field.subarray(nul))) invalid('Invalid tar text-field padding');
  const content = nul < 0 ? field : field.subarray(0, nul);
  if (content.some((byte) => byte < 32 || byte > 126)) invalid('Nonportable tar header text');
  return content.toString('ascii');
}

function octalField(header: Buffer, start: number, length: number): number {
  const field = header.subarray(start, start + length).toString('latin1');
  if (!/^[ ]*[0-7]+[\x00 ]*$/.test(field)) invalid('Invalid tar numeric field');
  const number = Number.parseInt(field.trim().replace(/\0.*$/, ''), 8);
  if (!Number.isSafeInteger(number)) invalid('Tar numeric field exceeds the supported range');
  return number;
}

function portablePath(path: string): boolean {
  return path.length <= 255 && path.split('/').every((part) =>
    /^[A-Za-z0-9_][A-Za-z0-9._-]*$/.test(part));
}

interface Member { bytes: Buffer; directory: boolean }
const ROOT = 'acfs-plugin-package';
const CORE_FILES = new Set(['plugin.json', 'README.md', 'LICENSE']);

function unpack(tar: Buffer): Map<string, Member> {
  if (tar.length < 1024 || tar.length % 512 !== 0) invalid('Truncated tar archive');
  const members = new Map<string, Member>();
  let offset = 0;
  let ended = false;
  while (offset + 512 <= tar.length) {
    const header = tar.subarray(offset, offset + 512);
    if (zero(header)) {
      if (offset + 1024 > tar.length || !zero(tar.subarray(offset))) {
        invalid('Tar archive has an incomplete terminator or trailing payload');
      }
      ended = true;
      break;
    }
    if (members.size >= PLUGIN_ARCHIVE_LIMITS.entries) invalid('Too many plugin archive members');
    const checksum = octalField(header, 148, 8);
    let actual = 0;
    for (let index = 0; index < 512; index++) {
      actual += index >= 148 && index < 156 ? 32 : header[index]!;
    }
    if (actual !== checksum) invalid('Tar header checksum mismatch');
    const magic = header.subarray(257, 265).toString('latin1');
    if (magic !== 'ustar\x0000' && magic !== 'ustar  \x00') {
      invalid('Only POSIX ustar and plain GNU tar headers are supported');
    }
    const kind = header[156];
    const directory = kind === 53;
    if (!directory && kind !== 0 && kind !== 48) {
      invalid('Links, devices, sparse files, and extended tar headers are forbidden');
    }
    if (textField(header, 157, 100) !== '') invalid('Tar link targets are forbidden');
    let path = textField(header, 0, 100);
    if (magic === 'ustar\x0000') {
      const prefix = textField(header, 345, 155);
      if (prefix) path = `${prefix}/${path}`;
    } else if (!zero(header.subarray(345))) {
      invalid('GNU tar extension fields are forbidden');
    }
    if (directory && path.endsWith('/')) path = path.slice(0, -1);
    if (!portablePath(path) || (path !== ROOT && !path.startsWith(`${ROOT}/`))) {
      invalid('Plugin archive member escapes the canonical root or has an unsafe path');
    }
    if (path === ROOT && !directory) invalid('Plugin archive root must be a directory');
    const relative = path === ROOT ? '' : path.slice(ROOT.length + 1);
    if (members.has(relative)) invalid('Duplicate plugin archive member');
    const mode = octalField(header, 100, 8);
    if (mode > 0o777) invalid('Privileged tar permission bits are forbidden');
    const size = octalField(header, 124, 12);
    const limit = relative === 'plugin.json'
      ? PLUGIN_ARCHIVE_LIMITS.manifestBytes : PLUGIN_ARCHIVE_LIMITS.memberBytes;
    if (size > limit || (directory && size !== 0)) invalid('Invalid plugin archive member size');
    const start = offset + 512;
    const end = start + Math.ceil(size / 512) * 512;
    if (end > tar.length || !zero(tar.subarray(start + size, end))) {
      invalid('Truncated tar member or nonzero file padding');
    }
    members.set(relative, { bytes: tar.subarray(start, start + size), directory });
    offset = end;
  }
  if (!ended) invalid('Tar archive is missing its end marker');
  return members;
}

/**
 * Additional static files are declared as extensions.archiveFiles: [{path, sha256}].
 * Paths are relative to the canonical root and confined to assets/docs/provenance.
 * README.md and LICENSE are implicitly declared; plugin.json cannot hash itself.
 */
function validateMembers(members: Map<string, Member>, manifest: unknown): number {
  const files = new Map<string, string | undefined>([...CORE_FILES].map((path) => [path, undefined]));
  if (!record(manifest)) invalid('Plugin manifest must be a JSON object');
  if (manifest.extensions !== undefined && !record(manifest.extensions)) {
    invalid('Plugin manifest extensions must be an object');
  }
  const declarations = record(manifest.extensions) ? manifest.extensions.archiveFiles : undefined;
  if (declarations !== undefined) {
    if (!Array.isArray(declarations) || declarations.length > PLUGIN_ARCHIVE_LIMITS.entries) {
      invalid('Plugin archive file declarations must be a bounded array');
    }
    for (const entry of declarations) {
      if (!record(entry) || Object.keys(entry).sort().join(',') !== 'path,sha256'
          || typeof entry.path !== 'string' || !portablePath(entry.path)
          || !/^(assets|docs|provenance)\/.+/.test(entry.path) || !isDigest(entry.sha256)
          || files.has(entry.path)) {
        invalid('Invalid or duplicate plugin archive file declaration');
      }
      files.set(entry.path, entry.sha256.toLowerCase());
    }
  }
  const directories = new Set(['', 'assets', 'docs', 'provenance']);
  for (const path of files.keys()) {
    const parts = path.split('/');
    for (let end = 1; end < parts.length; end++) directories.add(parts.slice(0, end).join('/'));
  }
  for (const [path, member] of members) {
    if (member.directory ? !directories.has(path) || files.has(path) : !files.has(path)) {
      invalid('Plugin archive contains an undeclared member or a file/directory collision');
    }
  }
  for (const [path, expected] of files) {
    const member = members.get(path);
    if (!member || member.directory) invalid('Plugin archive is missing a declared file');
    if (expected !== undefined && sha256(member.bytes) !== expected) {
      invalid('Plugin static-file digest mismatch');
    }
    const parts = path.split('/');
    for (let end = 1; end < parts.length; end++) {
      const parent = members.get(parts.slice(0, end).join('/'));
      if (parent && !parent.directory) invalid('Plugin file is nested below another file');
    }
  }
  return files.size;
}

/** Verify the compressed bytes first, then read only that verified snapshot. */
export function readVerifiedPluginArchive(
  archivePath: string,
  expectedPackageSha256: string,
): VerifiedPluginArchive {
  if (!isDigest(expectedPackageSha256)) {
    throw new PluginArchiveError('plugin_package_hash_mismatch', 'An independently trusted SHA-256 is required');
  }
  const compressed = readPluginInputFile(archivePath, PLUGIN_ARCHIVE_LIMITS.compressedBytes);
  const packageSha256 = sha256(compressed);
  if (packageSha256 !== expectedPackageSha256.toLowerCase()) {
    throw new PluginArchiveError('plugin_package_hash_mismatch', 'Plugin package digest does not match the trusted digest');
  }
  let tar: Buffer;
  try {
    tar = gunzipSync(compressed, { maxOutputLength: PLUGIN_ARCHIVE_LIMITS.expandedBytes });
  } catch {
    invalid('Plugin archive is invalid gzip or exceeds its expanded size budget');
  }
  const members = unpack(tar);
  const manifestFile = members.get('plugin.json');
  if (!manifestFile || manifestFile.directory) invalid('Plugin archive is missing its regular plugin.json');
  const manifest = parsePluginJsonBytes(manifestFile.bytes);
  const fileCount = validateMembers(members, manifest);
  return { packageSha256, manifest, compressedBytes: compressed.length, expandedBytes: tar.length, fileCount };
}
