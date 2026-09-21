import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import {
  chmodSync,
  existsSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  symlinkSync,
  truncateSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { gunzipSync } from "node:zlib";
import {
  PLUGIN_ARCHIVE_LIMITS,
  PluginArchiveError,
  readVerifiedPluginArchive,
  verifyPluginArchiveBytes,
} from "./plugin-archive.js";
import {
  buildPluginArchive,
  PluginPackError,
  pluginArchiveBytes,
  writePluginArchive,
} from "./plugin-pack.js";

const hash = (bytes: Uint8Array): string => createHash("sha256").update(bytes).digest("hex");
function fixture(extra: Record<string, Buffer | string> = {}, reverse = false) {
  const directory = mkdtempSync(join(tmpdir(), "acfs-package-author-"));
  const source = join(directory, "source");
  mkdirSync(source, { mode: 0o700 });
  const manifest = {
    packageId: "example.tools",
    version: "1.2.3",
    extensions: {
      archiveFiles: Object.entries(extra).map(([path, data]) => ({
        path,
        sha256: hash(Buffer.from(data)),
      })),
    },
  };
  const files = {
    "plugin.json": JSON.stringify(manifest, null, 2) + "\n",
    "README.md": "Example documentation.\n",
    LICENSE: "MIT\n",
    ...extra,
  };
  const entries = Object.entries(files);
  if (reverse) entries.reverse();
  for (const [path, data] of entries) {
    mkdirSync(dirname(join(source, path)), { recursive: true, mode: 0o755 });
    writeFileSync(join(source, path), data, { mode: 0o644 });
  }
  return { directory, source, manifest, files, output: join(directory, "example-tools.tar.gz") };
}
function unchanged(item: ReturnType<typeof fixture>): void {
  for (const [path, bytes] of Object.entries(item.files))
    assert.deepEqual(readFileSync(join(item.source, path)), Buffer.from(bytes));
  assert.ok(!existsSync(item.output));
}
const refused = (error: unknown): boolean =>
  error instanceof PluginPackError || error instanceof PluginArchiveError;

test("builds and validates a real package without extracting, executing or writing anything", () => {
  const item = fixture({
    "docs/start.md": "Read the docs.",
    "assets/data.bin": Buffer.from([0, 255, 32, 1]),
  });
  const before = readdirSync(item.directory);
  const built = buildPluginArchive(item.source);
  assert.equal(built.reviewRequired, true);
  assert.equal(built.fileCount, 5);
  assert.deepEqual(built.manifest, item.manifest);
  const bytes = pluginArchiveBytes(built);
  assert.equal(hash(bytes), built.packageSha256);
  assert.equal(bytes.length, built.compressedBytes);
  assert.equal(gunzipSync(bytes).length, built.expandedBytes);
  assert.deepEqual(verifyPluginArchiveBytes(bytes, built.packageSha256).manifest, item.manifest);
  assert.deepEqual(readdirSync(item.directory), before);
  unchanged(item);
});

test("system tar independently reads produced ustar entries and exact manifest bytes", () => {
  const item = fixture({ "docs/start.md": "An exact snapshot." });
  const bytes = pluginArchiveBytes(buildPluginArchive(item.source));
  const names = execFileSync("tar", ["-tzf", "-"], { input: bytes, encoding: "utf8" })
    .trim()
    .split("\n");
  assert.deepEqual(names, [
    "acfs-plugin-package",
    "acfs-plugin-package/LICENSE",
    "acfs-plugin-package/README.md",
    "acfs-plugin-package/docs",
    "acfs-plugin-package/docs/start.md",
    "acfs-plugin-package/plugin.json",
  ]);
  const listing = execFileSync("tar", ["-tvzf", "-"], { input: bytes, encoding: "utf8" })
    .trim()
    .split("\n");
  assert.ok(listing[0]!.startsWith("d"));
  assert.ok(listing[3]!.startsWith("d"));
  assert.deepEqual(
    execFileSync("tar", ["-xOzf", "-", "acfs-plugin-package/plugin.json"], { input: bytes }),
    Buffer.from(item.files["plugin.json"]),
  );
});

test("reproducible bytes ignore source location, creation order, file modes and timestamps", () => {
  const extra = {
    "docs/start.md": "Same documentation.",
    "assets/icon.bin": Buffer.from([0, 128, 255]),
  };
  const first = fixture(extra);
  const second = fixture(extra, true);
  for (const path of Object.keys(second.files)) {
    chmodSync(join(second.source, path), 0o700);
    utimesSync(join(second.source, path), new Date("2001-01-01"), new Date("2002-01-01"));
  }
  const a = buildPluginArchive(first.source);
  const b = buildPluginArchive(second.source);
  assert.equal(a.packageSha256, b.packageSha256);
  assert.deepEqual(pluginArchiveBytes(a), pluginArchiveBytes(b));
  const gzip = pluginArchiveBytes(a);
  assert.equal(gzip.subarray(4, 8).readUInt32LE(), 0);
  assert.equal(gzip[9], 255);
  const tar = gunzipSync(gzip);
  assert.equal(tar.subarray(108, 116).toString(), "0000000\0");
  assert.equal(tar.subarray(116, 124).toString(), "0000000\0");
  assert.equal(tar.subarray(136, 148).toString(), "00000000000\0");
  assert.ok(!tar.includes(Buffer.from(first.directory)));
});

test("changing a declared asset requires a matching declaration and changes the package digest", () => {
  const first = fixture({ "docs/start.md": "old" });
  const second = fixture({ "docs/start.md": "new" });
  assert.notEqual(
    buildPluginArchive(first.source).packageSha256,
    buildPluginArchive(second.source).packageSha256,
  );
  writeFileSync(join(first.source, "docs/start.md"), "new");
  assert.throws(() => buildPluginArchive(first.source), /digest mismatch/);
});

test("preserves semantically meaningful JSON spelling rather than silently rewriting manifests", () => {
  const item = fixture();
  const first = buildPluginArchive(item.source);
  writeFileSync(join(item.source, "plugin.json"), JSON.stringify(item.manifest));
  const second = buildPluginArchive(item.source);
  assert.deepEqual(first.manifest, second.manifest);
  assert.notEqual(first.packageSha256, second.packageSha256);
});

test("publication writes the retained immutable snapshot, not changed sources or a caller buffer", () => {
  const item = fixture();
  const built = buildPluginArchive(item.source);
  const expected = pluginArchiveBytes(built);
  const exposed = pluginArchiveBytes(built);
  exposed.fill(0);
  writeFileSync(join(item.source, "README.md"), "changed after build");
  const result = writePluginArchive(built, item.output);
  assert.deepEqual(readFileSync(item.output), expected);
  assert.equal(lstatSync(item.output).mode & 0o777, 0o600);
  assert.equal(readVerifiedPluginArchive(item.output, result.packageSha256).fileCount, 3);
  assert.deepEqual(result, {
    packageSha256: built.packageSha256,
    compressedBytes: built.compressedBytes,
    expandedBytes: built.expandedBytes,
    fileCount: 3,
    reviewRequired: true,
  });
});

test("exposes frozen manifest metadata and refuses fabricated build objects", () => {
  const item = fixture();
  const build = buildPluginArchive(item.source);
  assert.ok(Object.isFrozen(build));
  assert.ok(Object.isFrozen(build.manifest));
  assert.ok(Object.isFrozen((build.manifest as typeof item.manifest).extensions.archiveFiles));
  assert.throws(() => {
    (build.manifest as typeof item.manifest).version = "different";
  }, TypeError);
  assert.throws(() => writePluginArchive({ ...build }, item.output), PluginPackError);
  assert.throws(() => pluginArchiveBytes({ ...build }), PluginPackError);
  unchanged(item);
});

for (const name of [".env", ".git", "docs/unlisted.md", "review.json", "install.sh"]) {
  test(`refuses undeclared or private workspace member ${name}`, () => {
    const item = fixture();
    mkdirSync(dirname(join(item.source, name)), { recursive: true });
    writeFileSync(join(item.source, name), "not declared");
    assert.throws(() => buildPluginArchive(item.source), refused);
    assert.ok(!existsSync(item.output));
  });
}
for (const missing of ["plugin.json", "README.md", "LICENSE"]) {
  test(`refuses missing required ${missing}`, () => {
    const directory = mkdtempSync(join(tmpdir(), "acfs-missing-package-"));
    for (const [name, bytes] of Object.entries({
      "plugin.json": "{}",
      "README.md": "Docs",
      LICENSE: "MIT",
    })) {
      if (name !== missing) writeFileSync(join(directory, name), bytes);
    }
    assert.throws(() => buildPluginArchive(directory), /missing/);
  });
}
for (const json of [
  '{"a":1,"a":2}',
  '{"a":1,"\\u0061":2}',
  "\ufeff{}",
  '{"number":1e999}',
  "[]",
  "{} trailing",
]) {
  test(`refuses ambiguous or invalid manifest ${JSON.stringify(json)}`, () => {
    const item = fixture();
    writeFileSync(join(item.source, "plugin.json"), json);
    assert.throws(() => buildPluginArchive(item.source), refused);
  });
}

test("refuses symlinked files, directories and source ancestors before following them", () => {
  const item = fixture();
  const outside = mkdtempSync(join(tmpdir(), "acfs-package-outside-"));
  const other = join(outside, "other");
  writeFileSync(other, "private");
  symlinkSync(other, join(item.source, "linked"));
  assert.throws(() => buildPluginArchive(item.source), PluginPackError);
  const dirLink = join(outside, "dir-link");
  symlinkSync(item.source, dirLink);
  assert.throws(() => buildPluginArchive(dirLink), PluginPackError);
  const nested = join(item.source, "nested");
  mkdirSync(nested);
  assert.throws(() => buildPluginArchive(join(dirLink, "nested")), PluginPackError);
  assert.equal(readFileSync(other, "utf8"), "private");
});

test("refuses hardlinks, FIFOs, unsafe write permissions and special permission bits", () => {
  for (const mode of ["hardlink", "fifo", "writable", "privileged"]) {
    const item = fixture();
    const path = join(item.source, "README.md");
    if (mode === "hardlink") linkSync(path, join(item.directory, "hardlink"));
    if (mode === "fifo") execFileSync("mkfifo", [join(item.source, "fifo")]);
    if (mode === "writable") chmodSync(path, 0o666);
    if (mode === "privileged") chmodSync(path, 0o4755);
    assert.throws(() => buildPluginArchive(item.source), PluginPackError);
  }
});

test("empty declared static files are represented without disappearing", () => {
  const item = fixture({ "assets/empty.bin": Buffer.alloc(0) });
  assert.equal(buildPluginArchive(item.source).fileCount, 4);
});

test("uses ustar prefixes for long portable paths without PAX extensions", () => {
  const path = `docs/${"a".repeat(70)}/${"b".repeat(70)}/guide.md`;
  const item = fixture({ [path]: "Long path content" });
  const bytes = pluginArchiveBytes(buildPluginArchive(item.source));
  assert.equal(
    execFileSync("tar", ["-xOzf", "-", `acfs-plugin-package/${path}`], {
      input: bytes,
      encoding: "utf8",
    }),
    "Long path content",
  );
});

test("refuses paths that require nonportable names or unsupported extended tar headers", () => {
  for (const path of [
    `docs/${"x".repeat(110)}`,
    "docs/name with spaces.md",
    "docs/back\\slash",
    "docs/caf\u00e9.md",
  ]) {
    const item = fixture({ [path]: "static" });
    assert.throws(() => buildPluginArchive(item.source), PluginPackError);
  }
});

for (const secret of [
  "-----BEGIN PRIVATE KEY-----",
  "-----BEGIN OPENSSH PRIVATE KEY-----",
  "ghp_" + "a1".repeat(16),
  "github_pat_" + "Ab".repeat(16),
  "hvs." + "X".repeat(24),
  "sk-proj-" + "Ab1".repeat(16),
  "AKIA" + "A".repeat(16),
]) {
  test("refuses a credential marker even when its static asset hash is correctly declared", () => {
    const item = fixture({ "docs/credentials.txt": secret });
    try {
      buildPluginArchive(item.source);
      assert.fail("secret accepted");
    } catch (error) {
      assert.ok(error instanceof PluginPackError);
      assert.ok(!error.message.includes(secret));
      assert.ok(!error.message.includes(item.source));
    }
    unchanged(item);
  });
}

test("member, expanded, entry-count and compressed budgets bound authoring", () => {
  const member = fixture();
  truncateSync(join(member.source, "README.md"), PLUGIN_ARCHIVE_LIMITS.memberBytes + 1);
  assert.throws(() => buildPluginArchive(member.source), /member size/);
  const total = fixture();
  mkdirSync(join(total.source, "assets"));
  for (let n = 0; n < 8; n++) {
    const path = join(total.source, "assets", `file${n}`);
    writeFileSync(path, "x");
    truncateSync(path, PLUGIN_ARCHIVE_LIMITS.memberBytes);
  }
  assert.throws(() => buildPluginArchive(total.source), /total expanded/);
  const entries = fixture();
  mkdirSync(join(entries.source, "docs"));
  for (let n = 0; n < PLUGIN_ARCHIVE_LIMITS.entries; n++)
    writeFileSync(join(entries.source, "docs", `f${n}`), "x");
  assert.throws(() => buildPluginArchive(entries.source), /entry budget/);
  const compressed = fixture({
    "assets/one.bin": randomBytes(8 * 1024 * 1024),
    "assets/two.bin": randomBytes(8 * 1024 * 1024),
  });
  assert.throws(() => buildPluginArchive(compressed.source), /compressed size/);
});

test("publication refuses existing files, symlinks and hardlinks without modifying them", () => {
  const item = fixture();
  const build = buildPluginArchive(item.source);
  writeFileSync(item.output, "preserve");
  assert.throws(() => writePluginArchive(build, item.output), PluginPackError);
  assert.equal(readFileSync(item.output, "utf8"), "preserve");
  const linked = join(item.directory, "linked.tar.gz");
  symlinkSync(item.output, linked);
  assert.throws(() => writePluginArchive(build, linked), PluginPackError);
  const hard = join(item.directory, "hard.tar.gz");
  linkSync(item.output, hard);
  assert.throws(() => writePluginArchive(build, hard), PluginPackError);
  assert.equal(readFileSync(hard, "utf8"), "preserve");
});

test("publication refuses missing/symlinked parents and output inside source without creating directories", () => {
  const item = fixture();
  const build = buildPluginArchive(item.source);
  const missing = join(item.directory, "missing");
  assert.throws(() => writePluginArchive(build, join(missing, "out.tar.gz")), PluginPackError);
  assert.ok(!existsSync(missing));
  const link = join(item.directory, "parent-link");
  symlinkSync(item.directory, link);
  assert.throws(() => writePluginArchive(build, join(link, "out.tar.gz")), PluginPackError);
  assert.throws(() => writePluginArchive(build, join(item.source, "out.tar.gz")), PluginPackError);
  unchanged(item);
});

test("byte verification enforces budgets and rejects wrong digests before decompressing", () => {
  const bytes = pluginArchiveBytes(buildPluginArchive(fixture().source));
  assert.throws(() => verifyPluginArchiveBytes(bytes, ""), /trusted SHA/);
  assert.throws(
    () => verifyPluginArchiveBytes(Buffer.from("not gzip"), "a".repeat(64)),
    /trusted digest/,
  );
  assert.throws(() => verifyPluginArchiveBytes(Buffer.alloc(0), "a".repeat(64)), /compressed size/);
  assert.throws(
    () =>
      verifyPluginArchiveBytes(
        Buffer.alloc(PLUGIN_ARCHIVE_LIMITS.compressedBytes + 1),
        "a".repeat(64),
      ),
    /compressed size/,
  );
  const view = new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.equal(verifyPluginArchiveBytes(view, hash(bytes)).fileCount, 3);
});
