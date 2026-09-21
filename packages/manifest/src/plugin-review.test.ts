import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  PluginReviewError,
  parsePluginTarget,
  readPluginReviewRecord,
  readReviewedPluginArchive,
} from "./plugin-review.js";

const root = mkdtempSync(join(tmpdir(), "acfs-plugin-review-"));
let serial = 0;
const NOW = Date.parse("2026-09-17T12:00:00Z");
const target = parsePluginTarget("ubuntu/26.04/x86_64/glibc");
const base = () => ({
  schema: "acfs.plugin-review.v1",
  packageId: "example.tools",
  version: "1.2.3",
  sourceCommit: "a".repeat(40),
  packageSha256: "b".repeat(64),
  reviewer: "maintainer",
  reviewedAt: "2026-09-16T00:00:00Z",
  expiresAt: "2026-09-18T00:00:00Z",
  target,
  approvedCapabilities: ["verified_installer", "doctor_check"],
});
function jsonFile(input: unknown): string {
  const path = join(root, `review-${++serial}.json`);
  writeFileSync(path, JSON.stringify(input));
  return path;
}
function fixture(): {
  archive: string;
  review: ReturnType<typeof base>;
  manifest: Record<string, unknown>;
} {
  const manifest = {
    packageId: "example.tools",
    version: "1.2.3",
    provenance: { sourceCommit: "a".repeat(40) },
    targets: [{ os: "ubuntu", versions: ["26.04"], arch: ["x86_64"], libc: ["glibc"] }],
    capabilities: { allowed: ["verified_installer", "doctor_check"] },
  };
  const staging = join(root, `stage-${++serial}`);
  mkdirSync(join(staging, "acfs-plugin-package"), { recursive: true });
  for (const [name, data] of [
    ["plugin.json", JSON.stringify(manifest)],
    ["README.md", "Example"],
    ["LICENSE", "MIT"],
  ]) {
    writeFileSync(join(staging, "acfs-plugin-package", name!), data!);
  }
  const bytes = execFileSync("tar", [
    "--format=ustar",
    "-czf",
    "-",
    "-C",
    staging,
    "acfs-plugin-package",
  ]);
  const archive = join(root, `archive-${serial}.tar.gz`);
  writeFileSync(archive, bytes);
  const review = { ...base(), packageSha256: createHash("sha256").update(bytes).digest("hex") };
  return { archive, review, manifest };
}

test("binds one external review to compressed bytes, package identity and explicit target", () => {
  const item = fixture();
  assert.deepEqual(
    readReviewedPluginArchive(item.archive, jsonFile(item.review), target, NOW).manifest,
    item.manifest,
  );
});

test("normalizes digest/source hex without changing package identity or version", () => {
  const record = base();
  record.packageSha256 = record.packageSha256.toUpperCase();
  record.sourceCommit = record.sourceCommit.toUpperCase();
  const parsed = readPluginReviewRecord(jsonFile(record), NOW);
  assert.equal(parsed.packageSha256, "b".repeat(64));
  assert.equal(parsed.sourceCommit, "a".repeat(40));
});

for (const invalid of [
  "",
  "ubuntu/26.04/x86_64",
  "ubuntu/26.04/x86_64/glibc/extra",
  "ubuntu//x86_64/glibc",
  "ubuntu/26.04/../../glibc",
  "ubuntu/26.04/x86_64/glibc\n",
]) {
  test(`requires a complete portable target ${JSON.stringify(invalid)}`, () => {
    assert.throws(() => parsePluginTarget(invalid), PluginReviewError);
  });
}

for (const mutation of [
  { expiresAt: "2026-09-17T12:00:00Z" },
  { expiresAt: "2026-09-16T00:00:00Z" },
  { reviewedAt: "2026-09-18T00:00:00Z" },
  { reviewedAt: "2026-02-30T00:00:00Z" },
  { expiresAt: "September 18, 2026" },
  { expiresAt: "2026-09-18T00:00:00+00:00" },
  { approvedCapabilities: ["root_run_as"] },
  { approvedCapabilities: ["default_enabled_module"] },
  { approvedCapabilities: ["verified_installer", "verified_installer"] },
  { approvedCapabilities: [] },
  { approvedCapabilities: [7] },
  { approvedCapabilities: "doctor_check" },
  { schema: "acfs.plugin-review.v2" },
  { ignored: true },
  { packageSha256: "invalid" },
  { sourceCommit: "short" },
  { reviewer: "   " },
  { version: "1.2.3\n" },
  { target: { ...target, ignored: true } },
]) {
  test(`fails closed on review mutation ${JSON.stringify(mutation)}`, () => {
    assert.throws(
      () => readPluginReviewRecord(jsonFile({ ...base(), ...mutation }), NOW),
      PluginReviewError,
    );
  });
}

test("requires every review field and rejects invalid clocks", () => {
  for (const key of Object.keys(base())) {
    const data: Record<string, unknown> = { ...base() };
    delete data[key];
    assert.throws(() => readPluginReviewRecord(jsonFile(data), NOW), PluginReviewError);
  }
  assert.throws(() => readPluginReviewRecord(jsonFile(base()), NaN), PluginReviewError);
});

test("enforces exact expiration boundary and permits canonical millisecond timestamps", () => {
  const data = base();
  data.reviewedAt = "2026-09-17T11:59:59.999Z";
  data.expiresAt = "2026-09-17T12:00:00.001Z";
  assert.equal(readPluginReviewRecord(jsonFile(data), NOW).version, "1.2.3");
  assert.throws(() => readPluginReviewRecord(jsonFile(data), NOW + 1), /expired/);
});

test("refuses identity substitutions and incomplete capability approval", () => {
  const item = fixture();
  for (const mutation of [
    { packageId: "other.tools" },
    { version: "1.2.4" },
    { sourceCommit: "c".repeat(40) },
    { approvedCapabilities: ["doctor_check"] },
  ]) {
    assert.throws(
      () =>
        readReviewedPluginArchive(
          item.archive,
          jsonFile({ ...item.review, ...mutation }),
          target,
          NOW,
        ),
      PluginReviewError,
    );
  }
});

test("refuses review target mismatch before opening the archive", () => {
  assert.throws(
    () =>
      readReviewedPluginArchive(
        "/missing/SECRET",
        jsonFile(base()),
        parsePluginTarget("ubuntu/26.04/aarch64/glibc"),
        NOW,
      ),
    /differs from the external review/,
  );
});

test("refuses targets that are reviewed but unsupported by the archived manifest", () => {
  const item = fixture();
  const other = parsePluginTarget("ubuntu/26.04/aarch64/glibc");
  assert.throws(
    () =>
      readReviewedPluginArchive(
        item.archive,
        jsonFile({ ...item.review, target: other }),
        other,
        NOW,
      ),
    /complete requested target/,
  );
});

test("does not accept review-like metadata bundled inside the archive instead of a local record", () => {
  const item = fixture();
  assert.throws(
    () => readReviewedPluginArchive(item.archive, item.archive, target, NOW),
    /External review record/,
  );
});

test("rejects duplicate review keys with redacted errors", () => {
  const path = join(root, "duplicate-review.json");
  writeFileSync(path, '{"reviewer":"SECRET","reviewer":"other"}');
  try {
    readPluginReviewRecord(path, NOW);
    assert.fail("accepted duplicate keys");
  } catch (error) {
    assert.ok(error instanceof PluginReviewError);
    assert.ok(!error.message.includes("SECRET"));
    assert.ok(!error.message.includes(path));
  }
});
