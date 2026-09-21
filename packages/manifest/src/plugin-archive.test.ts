import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  linkSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  symlinkSync,
  truncateSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { gzipSync } from "node:zlib";
import {
  PLUGIN_ARCHIVE_LIMITS,
  PluginArchiveError,
  parsePluginJsonBytes,
  readPluginInputFile,
  readVerifiedPluginArchive,
} from "./plugin-archive.js";

const ROOT = "acfs-plugin-package/";
const directory = mkdtempSync(join(tmpdir(), "acfs-plugin-archive-"));
let serial = 0;
const digest = (bytes: Uint8Array): string => createHash("sha256").update(bytes).digest("hex");
interface Entry {
  path: string;
  data?: string | Buffer;
  kind?: string;
  mode?: number;
  prefix?: string;
}
function header(entry: Entry): Buffer {
  const result = Buffer.alloc(512);
  const data = Buffer.from(entry.data ?? "");
  result.write(entry.path, 0, 100, "ascii");
  result.write((entry.mode ?? 0o644).toString(8).padStart(7, "0") + "\0", 100);
  result.write("0000000\0", 108);
  result.write("0000000\0", 116);
  result.write(data.length.toString(8).padStart(11, "0") + "\0", 124);
  result.write("00000000000\0", 136);
  result[156] = (entry.kind ?? "0").charCodeAt(0);
  result.write("ustar\x00", 257);
  result.write("00", 263);
  if (entry.prefix) result.write(entry.prefix, 345, 155, "ascii");
  checksum(result);
  return result;
}
function checksum(result: Buffer): void {
  result.fill(32, 148, 156);
  const sum = result.reduce((total, byte) => total + byte, 0);
  result.write(sum.toString(8).padStart(6, "0") + "\0 ", 148);
}
function tar(entries: Entry[]): Buffer {
  return Buffer.concat([
    ...entries.flatMap((entry) => {
      const data = Buffer.from(entry.data ?? "");
      return [header(entry), data, Buffer.alloc((512 - (data.length % 512)) % 512)];
    }),
    Buffer.alloc(1024),
  ]);
}
function core(manifest = "{}"): Entry[] {
  return [
    { path: ROOT, kind: "5", mode: 0o755 },
    { path: ROOT + "plugin.json", data: manifest },
    { path: ROOT + "README.md", data: "Read me\n" },
    { path: ROOT + "LICENSE", data: "MIT\n" },
  ];
}
function store(compressed: Buffer): string {
  const path = join(directory, `package-${++serial}.tar.gz`);
  writeFileSync(path, compressed);
  return path;
}
function load(raw: Buffer, expected?: string): ReturnType<typeof readVerifiedPluginArchive> {
  const compressed = gzipSync(raw);
  return readVerifiedPluginArchive(store(compressed), expected ?? digest(compressed));
}
function refuses(raw: Buffer, pattern?: RegExp): void {
  assert.throws(
    () => load(raw),
    (error: unknown) => {
      assert.ok(error instanceof PluginArchiveError);
      assert.equal(error.code, "plugin_archive_layout_invalid");
      if (pattern) assert.match(error.message, pattern);
      return true;
    },
  );
}

test("binds parsed JSON to exact compressed bytes without extraction", () => {
  const bytes = gzipSync(tar(core('{"packageId":"example.tools"}')));
  const archive = store(bytes);
  const before = readdirSync(directory);
  const result = readVerifiedPluginArchive(archive, digest(bytes).toUpperCase());
  assert.equal(result.packageSha256, digest(bytes));
  assert.deepEqual(result.manifest, { packageId: "example.tools" });
  assert.equal(result.compressedBytes, bytes.length);
  assert.equal(result.fileCount, 3);
  assert.deepEqual(readdirSync(directory), before);
});

test("requires an independent digest before reading any input", () => {
  for (const value of ["", "a".repeat(63), "g".repeat(64), " a".repeat(32)]) {
    assert.throws(
      () => readVerifiedPluginArchive("/missing/private/path", value),
      (error: unknown) =>
        error instanceof PluginArchiveError && error.code === "plugin_package_hash_mismatch",
    );
  }
});

test("compares the digest before attempting decompression", () => {
  assert.throws(
    () => readVerifiedPluginArchive(store(Buffer.from("not gzip")), "f".repeat(64)),
    (error: unknown) =>
      error instanceof PluginArchiveError && error.code === "plugin_package_hash_mismatch",
  );
});

test("rejects altered compressed bytes even if the tar contents are unchanged", () => {
  const bytes = gzipSync(tar(core()));
  const expected = digest(bytes);
  bytes[4] = 1; // gzip mtime, not tar data
  assert.throws(() => readVerifiedPluginArchive(store(bytes), expected), /trusted digest/);
});

for (const path of [
  "/tmp/escape",
  "../escape",
  ROOT + "../escape",
  ROOT + "docs/../../escape",
  ROOT + "./plugin.json",
  ROOT + "docs//file",
  ROOT + "docs\\file",
  ROOT + "C:drive",
  ROOT + "docs/\nfile",
  "other/plugin.json",
  ROOT + ".hidden",
  ROOT + "plugin.json/",
]) {
  test(`rejects unsafe member path ${JSON.stringify(path)}`, () =>
    refuses(tar([...core(), { path }])));
}
for (const kind of ["1", "2", "3", "4", "6", "7", "x", "g", "L", "K", "S"]) {
  test(`rejects tar type ${kind}`, () =>
    refuses(tar([...core(), { path: ROOT + "docs/file", kind }])));
}

test("rejects duplicate paths, including normalized directory duplicates", () => {
  refuses(tar([...core(), { path: ROOT + "plugin.json" }]), /Duplicate/);
  refuses(tar([...core(), { path: ROOT.slice(0, -1), kind: "5" }]), /Duplicate/);
});

test("rejects undeclared files and requires every core file", () => {
  refuses(tar([...core(), { path: ROOT + "docs/undeclared.md" }]), /undeclared/);
  for (const path of ["plugin.json", "README.md", "LICENSE"]) {
    refuses(tar(core().filter((entry) => entry.path !== ROOT + path)), /missing/);
  }
});

test("verifies declared static-file content and permits declared parent directories", () => {
  const content = Buffer.from("Static documentation.");
  const manifest = JSON.stringify({
    extensions: { archiveFiles: [{ path: "docs/guide/start.md", sha256: digest(content) }] },
  });
  const entries = [
    ...core(manifest),
    { path: ROOT + "docs/guide/", kind: "5" },
    { path: ROOT + "docs/guide/start.md", data: content },
  ];
  assert.equal(load(tar(entries)).fileCount, 4);
  entries[5]!.data = "tampered";
  refuses(tar(entries), /digest mismatch/);
  refuses(tar(core(manifest)), /missing/);
});

for (const declaration of [
  null,
  {},
  "docs/x",
  [{ path: "../x", sha256: "a".repeat(64) }],
  [{ path: "README.md", sha256: "a".repeat(64) }],
  [{ path: "docs/x", sha256: "bad" }],
  [{ path: "docs/x", sha256: "a".repeat(64), ignored: true }],
]) {
  test(`rejects malformed archive declarations ${JSON.stringify(declaration)}`, () => {
    refuses(tar(core(JSON.stringify({ extensions: { archiveFiles: declaration } }))));
  });
}

test("rejects directory/file collisions regardless of member order", () => {
  const empty = digest(Buffer.alloc(0));
  const manifest = JSON.stringify({
    extensions: {
      archiveFiles: [
        { path: "docs/x", sha256: empty },
        { path: "docs/x/y", sha256: empty },
      ],
    },
  });
  const files = [{ path: ROOT + "docs/x" }, { path: ROOT + "docs/x/y" }];
  refuses(tar([...core(manifest), ...files]), /nested/);
  refuses(tar([...core(manifest), ...files.reverse()]), /nested/);
});

test("rejects corrupted headers, unsupported numbers and privileged modes", () => {
  const raw = tar(core());
  raw[10] = raw[10]! ^ 1;
  refuses(raw, /checksum/);
  const numeric = tar(core());
  numeric[124] = 0x80;
  checksum(numeric.subarray(0, 512));
  refuses(numeric, /numeric/);
  refuses(tar([...core(), { path: ROOT + "docs/x", mode: 0o4755 }]), /permission/);
});

test("rejects nonempty directory bodies and nonzero padding", () => {
  refuses(tar([...core(), { path: ROOT + "docs/", kind: "5", data: "x" }]), /size/);
  const raw = tar(core());
  raw[1026] = 1; // padding after the two-byte manifest
  refuses(raw, /padding/);
});

test("rejects missing end markers, truncated bodies and a second tar payload", () => {
  const raw = tar(core());
  refuses(raw.subarray(0, raw.length - 1024), /end marker/);
  refuses(raw.subarray(0, raw.length - 512), /terminator/);
  refuses(raw.subarray(0, raw.length - 1), /Truncated/);
  refuses(Buffer.concat([raw, raw]), /trailing/);
});

test("rejects extra gzip members carrying another archive", () => {
  const bytes = Buffer.concat([gzipSync(tar(core())), gzipSync(tar(core()))]);
  assert.throws(() => readVerifiedPluginArchive(store(bytes), digest(bytes)), /trailing/);
});

test("accepts ustar prefix paths without permitting prefix traversal", () => {
  const entries = core();
  entries[1] = { path: "plugin.json", prefix: ROOT.slice(0, -1), data: "{}" };
  assert.equal(load(tar(entries)).fileCount, 3);
  entries[1]!.prefix = ROOT + "..";
  refuses(tar(entries), /unsafe path/);
});

test("accepts ordinary GNU tar and POSIX ustar packages produced by the system tar", () => {
  const staging = join(directory, `staging-${++serial}`);
  mkdirSync(join(staging, ROOT), { recursive: true });
  for (const entry of core().slice(1)) writeFileSync(join(staging, entry.path), entry.data!);
  for (const format of ["gnu", "ustar"]) {
    const bytes = execFileSync("tar", [
      `--format=${format}`,
      "-czf",
      "-",
      "-C",
      staging,
      ROOT.slice(0, -1),
    ]);
    assert.equal(readVerifiedPluginArchive(store(bytes), digest(bytes)).fileCount, 3);
  }
});

for (const text of [
  '{"a":1,"a":2}',
  '{"a":1,"\\u0061":2}',
  '{"x":{"a":1,"a":2}}',
  '[{"a":1,"a":2}]',
  '{"n":1e400}',
  '{"n":-1e400}',
  "\ufeff{}",
  '{"a":undefined}',
  "",
]) {
  test(`rejects ambiguous or invalid JSON ${JSON.stringify(text)}`, () => {
    assert.throws(() => parsePluginJsonBytes(Buffer.from(text)), PluginArchiveError);
  });
}

test("handles escaped JSON strings and keys without false duplicates", () => {
  const input = { 'a"b': ['x\\"y', { same: 1 }, { same: 2 }], braces: "{},[]" };
  assert.deepEqual(parsePluginJsonBytes(Buffer.from(JSON.stringify(input))), input);
});

test("enforces JSON depth, node, byte and UTF-8 budgets", () => {
  assert.throws(
    () => parsePluginJsonBytes(Buffer.from("[".repeat(66) + "0" + "]".repeat(66))),
    /budget/,
  );
  assert.throws(
    () => parsePluginJsonBytes(Buffer.from(JSON.stringify(Array(50_001).fill(0)))),
    /budget/,
  );
  assert.throws(
    () => parsePluginJsonBytes(Buffer.alloc(PLUGIN_ARCHIVE_LIMITS.manifestBytes + 1)),
    /budget/,
  );
  assert.throws(() => parsePluginJsonBytes(Buffer.from([123, 34, 0xff, 34, 58, 49, 125])), /UTF-8/);
});

test("bounds gzip expansion before inspecting tar", () => {
  const bytes = gzipSync(Buffer.alloc(PLUGIN_ARCHIVE_LIMITS.expandedBytes + 512));
  assert.throws(() => readVerifiedPluginArchive(store(bytes), digest(bytes)), /expanded size/);
});

test("bounds archive member sizes and counts", () => {
  refuses(tar(core(" ".repeat(PLUGIN_ARCHIVE_LIMITS.manifestBytes + 1))), /size/);
  const entries = core();
  for (let index = 0; index < PLUGIN_ARCHIVE_LIMITS.entries; index++) {
    entries.push({ path: ROOT + `docs/f${index}` });
  }
  refuses(tar(entries), /Too many/);
});

test("refuses symlinks, hardlinks, directories, FIFOs, empty and oversized input", () => {
  const source = store(gzipSync(tar(core())));
  const symlink = join(directory, "symlink");
  symlinkSync(source, symlink);
  assert.throws(() => readPluginInputFile(symlink, 1024), /safely/);
  const hardlink = join(directory, "hardlink");
  linkSync(source, hardlink);
  assert.throws(() => readPluginInputFile(hardlink, 1024), /single-link/);
  assert.throws(() => readPluginInputFile(directory, 1024), /regular file/);
  const fifo = join(directory, "fifo");
  execFileSync("mkfifo", [fifo]);
  assert.throws(() => readPluginInputFile(fifo, 1024), /regular file/);
  assert.throws(() => readPluginInputFile(store(Buffer.alloc(0)), 1024), /nonempty/);
  const oversized = store(Buffer.from("x"));
  truncateSync(oversized, PLUGIN_ARCHIVE_LIMITS.compressedBytes + 1);
  assert.throws(
    () => readPluginInputFile(oversized, PLUGIN_ARCHIVE_LIMITS.compressedBytes),
    /bounded/,
  );
});

test("redacts archive and JSON diagnostics instead of echoing input", () => {
  const privatePath = "/missing/ghp_SUPER_PRIVATE_TOKEN_1234567890123456789012345";
  try {
    readPluginInputFile(privatePath, 1024);
    assert.fail("accepted missing file");
  } catch (error) {
    assert.ok(error instanceof PluginArchiveError);
    assert.ok(!error.message.includes("PRIVATE"));
    assert.ok(!error.message.includes(privatePath));
  }
  assert.throws(
    () => parsePluginJsonBytes(Buffer.from('{"private":"TOKEN", bad}')),
    (error: unknown) => error instanceof PluginArchiveError && !error.message.includes("TOKEN"),
  );
});
